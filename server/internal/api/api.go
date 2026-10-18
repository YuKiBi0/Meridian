// Package api serves the HTTP interface described in PRD §9.
package api

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"io/fs"
	"log/slog"
	"mime"
	"net"
	"net/http"
	"path"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/YuKiBi0/Meridian/server/internal/rooms"
	"github.com/YuKiBi0/Meridian/server/internal/store"
	"github.com/YuKiBi0/Meridian/server/internal/stream"
	"github.com/YuKiBi0/Meridian/server/internal/timer"
)

const heartbeat = 15 * time.Second

type Config struct {
	BasePath     string // "" or "/meridian"
	AdminToken   string
	CookieSecure bool
	Trusted      []*net.IPNet
	Console      fs.FS
}

type Server struct {
	cfg   Config
	rooms *rooms.Manager
	hub   *stream.Hub
	store *store.Store
	auth  *auth
	limit *limiter
}

func New(cfg Config, rm *rooms.Manager, h *stream.Hub, s *store.Store) *Server {
	return &Server{
		cfg:   cfg,
		rooms: rm,
		hub:   h,
		store: s,
		auth:  newAuth(cfg.AdminToken, cfg.CookieSecure, cfg.BasePath+"/"),
		limit: newLimiter(),
	}
}

// Handler returns the root handler with every route under BasePath.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.health)
	mux.HandleFunc("GET /api/v1/stream", s.stream)
	mux.HandleFunc("GET /api/v1/state", s.state)
	mux.HandleFunc("GET /api/v1/time", s.time)
	mux.HandleFunc("GET /api/v1/rooms/{room}", s.inRoom(s.publicRoom))

	mux.HandleFunc("POST /api/v1/admin/login", s.login)
	mux.HandleFunc("POST /api/v1/admin/logout", s.logout)
	admin := func(pattern string, h http.HandlerFunc) { mux.Handle(pattern, s.requireAdmin(h)) }
	admin("GET /api/v1/admin/session", func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusNoContent) })
	admin("GET /api/v1/admin/rooms", s.listRooms)
	admin("POST /api/v1/admin/rooms", s.createRoom)
	admin("GET /api/v1/admin/rooms/{room}", s.inRoom(s.getRoom))
	admin("PUT /api/v1/admin/rooms/{room}", s.inRoom(s.renameRoom))
	admin("DELETE /api/v1/admin/rooms/{room}", s.inRoom(s.deleteRoom))
	timerOp := func(method, op string, h roomHandler) {
		admin(method+" /api/v1/admin/rooms/{room}/timer/"+op, s.inRoom(h))
	}
	timerOp("POST", "start", s.start)
	timerOp("POST", "pause", s.simpleOp("pause", (*timer.Engine).Pause))
	timerOp("POST", "resume", s.simpleOp("resume", (*timer.Engine).Resume))
	timerOp("POST", "end", s.simpleOp("end", (*timer.Engine).End))
	timerOp("POST", "extend", s.adjust("extend", (*timer.Engine).Extend))
	timerOp("POST", "reduce", s.adjust("reduce", (*timer.Engine).Reduce))
	timerOp("PUT", "reminders", s.setReminders)
	admin("GET /api/v1/admin/presets", s.listPresets)
	admin("POST /api/v1/admin/presets", s.createPreset)
	admin("PUT /api/v1/admin/presets/order", s.reorderPresets)
	admin("PUT /api/v1/admin/presets/{id}", s.updatePreset)
	admin("DELETE /api/v1/admin/presets/{id}", s.deletePreset)
	admin("GET /api/v1/admin/logs", s.logs)
	mux.HandleFunc("/api/", func(w http.ResponseWriter, r *http.Request) {
		writeErr(w, http.StatusNotFound, "not_found", "没有这个接口")
	})
	mux.Handle("/", s.console())

	if s.cfg.BasePath == "" {
		return mux
	}
	root := http.NewServeMux()
	base := s.cfg.BasePath
	root.Handle(base+"/", http.StripPrefix(base, mux))
	root.HandleFunc(base, func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, base+"/", http.StatusMovedPermanently)
	})
	return root
}

// ---- helpers ----

type apiError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, status int, code, msg string) {
	writeJSON(w, status, map[string]apiError{"error": {Code: code, Message: msg}})
}

func decode(w http.ResponseWriter, r *http.Request, v any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 64<<10)
	err := json.NewDecoder(r.Body).Decode(v)
	if err == nil || errors.Is(err, io.EOF) {
		return true
	}
	writeErr(w, http.StatusBadRequest, "bad_request", "请求格式不对")
	return false
}

func (s *Server) opError(w http.ResponseWriter, err error) {
	var ve *timer.ValidationError
	switch {
	case errors.As(err, &ve):
		writeErr(w, http.StatusBadRequest, "bad_request", ve.Msg)
	case errors.Is(err, timer.ErrInvalidState):
		writeErr(w, http.StatusConflict, "invalid_state", "当前状态不能这样操作")
	case errors.Is(err, timer.ErrRemindersConflict):
		writeErr(w, http.StatusConflict, "reminders_conflict", "提醒已被其他控制台改动")
	case errors.Is(err, timer.ErrSeqConflict):
		writeErr(w, http.StatusConflict, "seq_conflict", "状态已被其他控制台改动")
	case errors.Is(err, rooms.ErrNotFound):
		writeErr(w, http.StatusNotFound, "room_not_found", "房间不存在")
	case errors.Is(err, rooms.ErrTooMany):
		writeErr(w, http.StatusBadRequest, "bad_request", "房间最多 100 个")
	case errors.Is(err, store.ErrNotFound):
		writeErr(w, http.StatusNotFound, "not_found", "预设不存在")
	case errors.Is(err, store.ErrTooMany):
		writeErr(w, http.StatusBadRequest, "bad_request", "预设最多 100 个")
	default:
		slog.Error("request failed", "err", err)
		writeErr(w, http.StatusInternalServerError, "internal", "服务器出错了")
	}
}

// record writes an operation log entry without delaying the response.
// room is "" for operations outside a room.
func (s *Server) record(r *http.Request, room, action string, params any, seq *int64) {
	ip := clientIP(r, s.cfg.Trusted)
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := s.store.AddLog(ctx, room, action, params, seq, ip); err != nil {
			slog.Warn("write op log", "err", err)
		}
	}()
}

func (s *Server) requireAdmin(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ok, viaCookie := s.auth.check(r)
		if !ok {
			writeErr(w, http.StatusUnauthorized, "unauthorized", "需要先登录")
			return
		}
		// Cookie-authenticated writes must be JSON: a cross-site form
		// cannot send that content type without a CORS preflight.
		if viaCookie && (r.Method == http.MethodPost || r.Method == http.MethodPut) && !isJSON(r) {
			writeErr(w, http.StatusUnsupportedMediaType, "bad_request", "只接受 JSON")
			return
		}
		next.ServeHTTP(w, r)
	})
}

func isJSON(r *http.Request) bool {
	mt, _, _ := mime.ParseMediaType(r.Header.Get("Content-Type"))
	return mt == "application/json"
}

// ---- public ----

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	if err := s.store.Ping(ctx); err != nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "db_unavailable"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// roomFromQuery resolves ?r= for the public state and stream endpoints.
func (s *Server) roomFromQuery(w http.ResponseWriter, r *http.Request) (rooms.Info, *timer.Engine, bool) {
	q := r.URL.Query().Get("r")
	if q == "" {
		writeErr(w, http.StatusBadRequest, "room_required", "地址里缺少房间号 ?r=")
		return rooms.Info{}, nil, false
	}
	id, ok := rooms.ParseID(q)
	if !ok {
		writeErr(w, http.StatusNotFound, "room_not_found", "房间不存在")
		return rooms.Info{}, nil, false
	}
	info, e, ok := s.rooms.Get(id)
	if !ok {
		writeErr(w, http.StatusNotFound, "room_not_found", "房间不存在")
	}
	return info, e, ok
}

func (s *Server) state(w http.ResponseWriter, r *http.Request) {
	if _, e, ok := s.roomFromQuery(w, r); ok {
		writeJSON(w, http.StatusOK, e.Snapshot())
	}
}

func (s *Server) time(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]int64{"server_time": time.Now().UnixMilli()})
}

// stream serves one room's events (PRD §9.1). A console without ?r= gets
// the room list stream instead, which carries only change signals.
func (s *Server) stream(w http.ResponseWriter, r *http.Request) {
	role := r.URL.Query().Get("role")
	var info rooms.Info
	var e *timer.Engine
	var sub *stream.Sub
	if role == stream.RoleConsole && r.URL.Query().Get("r") == "" {
		sub = s.hub.Subscribe(role, "")
	} else {
		var ok bool
		if info, e, ok = s.roomFromQuery(w, r); !ok {
			return
		}
		sub = s.hub.Subscribe(role, info.ID)
		// A delete that ran before Subscribe would never disconnect us.
		if _, _, ok := s.rooms.Get(info.ID); !ok {
			s.hub.Unsubscribe(sub)
			writeErr(w, http.StatusNotFound, "room_not_found", "房间不存在")
			return
		}
	}
	defer s.hub.Unsubscribe(sub)

	rc := http.NewResponseController(w)
	h := w.Header()
	h.Set("Content-Type", "text/event-stream; charset=utf-8")
	h.Set("Cache-Control", "no-cache, no-transform")
	h.Set("Connection", "keep-alive")
	h.Set("X-Accel-Buffering", "no")
	w.WriteHeader(http.StatusOK)
	io.WriteString(w, "retry: 2000\n\n")
	if e != nil {
		snap := e.Snapshot()
		w.Write(stream.Encode("room", -1, info))
		w.Write(stream.Encode("state", snap.Seq, snap))
	}
	if err := rc.Flush(); err != nil {
		return
	}
	tick := time.NewTicker(heartbeat)
	defer tick.Stop()
	for {
		select {
		case <-r.Context().Done():
			return
		case msg, ok := <-sub.C:
			if !ok {
				return
			}
			if _, err := w.Write(msg); err != nil {
				return
			}
		case <-tick.C:
			var err error
			if e != nil {
				_, err = w.Write(stream.Encode("sync", -1, e.Sync()))
			} else {
				_, err = io.WriteString(w, ": ping\n\n")
			}
			if err != nil {
				return
			}
		}
		if err := rc.Flush(); err != nil {
			return
		}
	}
}

// ---- auth ----

func (s *Server) login(w http.ResponseWriter, r *http.Request) {
	if !isJSON(r) {
		writeErr(w, http.StatusUnsupportedMediaType, "bad_request", "只接受 JSON")
		return
	}
	ip := clientIP(r, s.cfg.Trusted)
	if s.limit.blocked(ip) {
		writeErr(w, http.StatusTooManyRequests, "too_many_attempts", "尝试太多次了，一分钟后再试")
		return
	}
	var body struct {
		Token string `json:"token"`
	}
	if !decode(w, r, &body) {
		return
	}
	if !s.auth.tokenOK(body.Token) {
		s.limit.failed(ip)
		writeErr(w, http.StatusUnauthorized, "unauthorized", "口令不对")
		return
	}
	s.auth.setCookie(w)
	s.record(r, "", "login", nil, nil)
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) logout(w http.ResponseWriter, r *http.Request) {
	s.auth.clearCookie(w)
	w.WriteHeader(http.StatusNoContent)
}

// ---- rooms ----

type roomHandler func(w http.ResponseWriter, r *http.Request, info rooms.Info, e *timer.Engine)

// inRoom resolves the {room} path segment.
func (s *Server) inRoom(h roomHandler) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id, ok := rooms.ParseID(r.PathValue("room"))
		if !ok {
			s.opError(w, rooms.ErrNotFound)
			return
		}
		info, e, ok := s.rooms.Get(id)
		if !ok {
			s.opError(w, rooms.ErrNotFound)
			return
		}
		h(w, r, info, e)
	}
}

// roomSummary is a room as the console sees it.
type roomSummary struct {
	rooms.Info
	Clients int         `json:"clients"`
	State   timer.State `json:"state"`
}

func (s *Server) summary(info rooms.Info, st timer.State) roomSummary {
	return roomSummary{Info: info, Clients: s.hub.Counts(info.ID)[stream.RoleClient], State: st}
}

// publicRoom lets a client check that a room exists before joining it.
func (s *Server) publicRoom(w http.ResponseWriter, r *http.Request, info rooms.Info, _ *timer.Engine) {
	writeJSON(w, http.StatusOK, map[string]string{"id": info.ID, "name": info.Name})
}

func (s *Server) listRooms(w http.ResponseWriter, r *http.Request) {
	list := s.rooms.List()
	out := make([]roomSummary, len(list))
	for i, rm := range list {
		out[i] = s.summary(rm.Info, rm.State)
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) getRoom(w http.ResponseWriter, r *http.Request, info rooms.Info, e *timer.Engine) {
	writeJSON(w, http.StatusOK, s.summary(info, e.Snapshot()))
}

func (s *Server) createRoom(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Name string `json:"name"`
	}
	if !decode(w, r, &body) {
		return
	}
	info, err := s.rooms.Create(r.Context(), body.Name)
	if err != nil {
		s.opError(w, err)
		return
	}
	_, e, _ := s.rooms.Get(info.ID)
	s.record(r, info.ID, "room.create", map[string]any{"name": info.Name}, nil)
	writeJSON(w, http.StatusCreated, s.summary(info, e.Snapshot()))
}

func (s *Server) renameRoom(w http.ResponseWriter, r *http.Request, info rooms.Info, e *timer.Engine) {
	var body struct {
		Name string `json:"name"`
	}
	if !decode(w, r, &body) {
		return
	}
	info, err := s.rooms.Rename(r.Context(), info.ID, body.Name)
	if err != nil {
		s.opError(w, err)
		return
	}
	s.record(r, info.ID, "room.rename", map[string]any{"name": info.Name}, nil)
	writeJSON(w, http.StatusOK, s.summary(info, e.Snapshot()))
}

func (s *Server) deleteRoom(w http.ResponseWriter, r *http.Request, info rooms.Info, _ *timer.Engine) {
	if _, err := s.rooms.Delete(r.Context(), info.ID); err != nil {
		s.opError(w, err)
		return
	}
	s.record(r, info.ID, "room.delete", map[string]any{"name": info.Name}, nil)
	w.WriteHeader(http.StatusNoContent)
}

// ---- timer ----

type seqBody struct {
	IfSeq *int64 `json:"if_seq"`
}

func (s *Server) simpleOp(action string, op func(*timer.Engine, *int64) (timer.State, error)) roomHandler {
	return func(w http.ResponseWriter, r *http.Request, info rooms.Info, e *timer.Engine) {
		var body seqBody
		if !decode(w, r, &body) {
			return
		}
		st, err := op(e, body.IfSeq)
		if err != nil {
			s.opError(w, err)
			return
		}
		s.record(r, info.ID, action, nil, &st.Seq)
		writeJSON(w, http.StatusOK, st)
	}
}

func (s *Server) start(w http.ResponseWriter, r *http.Request, info rooms.Info, e *timer.Engine) {
	var body struct {
		PresetID string `json:"preset_id"`
		IfSeq    *int64 `json:"if_seq"`
		timer.Config
	}
	if !decode(w, r, &body) {
		return
	}
	cfg := body.Config
	params := map[string]any{"total_ms": cfg.TotalMs, "title": cfg.Title}
	if body.PresetID != "" {
		p, err := s.store.GetPreset(r.Context(), body.PresetID)
		if err != nil {
			s.opError(w, err)
			return
		}
		cfg = p.Config
		params = map[string]any{"preset_id": p.ID, "preset": p.Name, "total_ms": cfg.TotalMs}
	}
	if err := cfg.Normalize(); err != nil {
		s.opError(w, err)
		return
	}
	st, err := e.Start(cfg, body.IfSeq)
	if err != nil {
		s.opError(w, err)
		return
	}
	s.record(r, info.ID, "start", params, &st.Seq)
	writeJSON(w, http.StatusOK, st)
}

// adjust serves extend and reduce, which take the same body.
func (s *Server) adjust(action string, op func(*timer.Engine, time.Duration, timer.ExtendMode, *int64) (timer.State, error)) roomHandler {
	return func(w http.ResponseWriter, r *http.Request, info rooms.Info, e *timer.Engine) {
		var body struct {
			DeltaMs int64            `json:"delta_ms"`
			Mode    timer.ExtendMode `json:"mode"`
			IfSeq   *int64           `json:"if_seq"`
		}
		if !decode(w, r, &body) {
			return
		}
		st, err := op(e, time.Duration(body.DeltaMs)*time.Millisecond, body.Mode, body.IfSeq)
		if err != nil {
			s.opError(w, err)
			return
		}
		s.record(r, info.ID, action, map[string]any{"delta_ms": body.DeltaMs, "mode": body.Mode}, &st.Seq)
		writeJSON(w, http.StatusOK, st)
	}
}

func (s *Server) setReminders(w http.ResponseWriter, r *http.Request, info rooms.Info, e *timer.Engine) {
	var body struct {
		Reminders      []timer.Reminder `json:"reminders"`
		IfSeq          *int64           `json:"if_seq"`
		IfRemindersSeq *int64           `json:"if_reminders_seq"`
	}
	if !decode(w, r, &body) {
		return
	}
	st, err := e.SetReminders(body.Reminders, body.IfSeq, body.IfRemindersSeq)
	if err != nil {
		s.opError(w, err)
		return
	}
	s.record(r, info.ID, "reminders", map[string]any{"count": len(st.Reminders)}, &st.Seq)
	writeJSON(w, http.StatusOK, st)
}

// ---- presets ----

// presetsChanged tells every console to reload its preset list. It carries
// no data: the stream is public and presets are admin-only.
func (s *Server) presetsChanged() {
	s.hub.PublishRole(stream.RoleConsole, stream.Encode("presets", -1, struct{}{}))
}

func validPreset(p *store.Preset) error {
	p.Name = strings.TrimSpace(p.Name)
	if n := utf8.RuneCountInString(p.Name); n == 0 || n > timer.MaxTitleLen {
		return &timer.ValidationError{Msg: "名称需为 1 到 40 字"}
	}
	return p.Config.Normalize()
}

func (s *Server) listPresets(w http.ResponseWriter, r *http.Request) {
	ps, err := s.store.ListPresets(r.Context())
	if err != nil {
		s.opError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, ps)
}

func (s *Server) createPreset(w http.ResponseWriter, r *http.Request) {
	var p store.Preset
	if !decode(w, r, &p) {
		return
	}
	if err := validPreset(&p); err != nil {
		s.opError(w, err)
		return
	}
	p, err := s.store.CreatePreset(r.Context(), p)
	if err != nil {
		s.opError(w, err)
		return
	}
	s.record(r, "", "preset.create", map[string]any{"id": p.ID, "name": p.Name}, nil)
	s.presetsChanged()
	writeJSON(w, http.StatusCreated, p)
}

func (s *Server) updatePreset(w http.ResponseWriter, r *http.Request) {
	var p store.Preset
	if !decode(w, r, &p) {
		return
	}
	p.ID = r.PathValue("id")
	if err := validPreset(&p); err != nil {
		s.opError(w, err)
		return
	}
	p, err := s.store.UpdatePreset(r.Context(), p)
	if err != nil {
		s.opError(w, err)
		return
	}
	s.record(r, "", "preset.update", map[string]any{"id": p.ID, "name": p.Name}, nil)
	s.presetsChanged()
	writeJSON(w, http.StatusOK, p)
}

func (s *Server) deletePreset(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if err := s.store.DeletePreset(r.Context(), id); err != nil {
		s.opError(w, err)
		return
	}
	s.record(r, "", "preset.delete", map[string]any{"id": id}, nil)
	s.presetsChanged()
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) reorderPresets(w http.ResponseWriter, r *http.Request) {
	var body struct {
		IDs []string `json:"ids"`
	}
	if !decode(w, r, &body) {
		return
	}
	if err := s.store.ReorderPresets(r.Context(), body.IDs); err != nil {
		s.opError(w, err)
		return
	}
	s.record(r, "", "preset.reorder", nil, nil)
	s.presetsChanged()
	w.WriteHeader(http.StatusNoContent)
}

// ---- misc ----

func (s *Server) logs(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 || limit > 1000 {
		limit = 100
	}
	logs, err := s.store.ListLogs(r.Context(), limit)
	if err != nil {
		s.opError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, logs)
}

// console serves the embedded single-page console. Unknown paths without
// a file extension fall back to index.html.
func (s *Server) console() http.Handler {
	files := http.FileServerFS(s.cfg.Console)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		p := strings.TrimPrefix(path.Clean(r.URL.Path), "/")
		if p != "" && p != "index.html" {
			if _, err := fs.Stat(s.cfg.Console, p); err == nil {
				if strings.HasPrefix(p, "assets/") {
					w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
				}
				files.ServeHTTP(w, r)
				return
			}
			if path.Ext(p) != "" {
				http.NotFound(w, r)
				return
			}
		}
		index, err := fs.ReadFile(s.cfg.Console, "index.html")
		if err != nil {
			w.Header().Set("Content-Type", "text/plain; charset=utf-8")
			io.WriteString(w, "子午服务运行中。控制台尚未构建。\n")
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Header().Set("Cache-Control", "no-cache")
		w.Write(index)
	})
}

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
	cfg    Config
	engine *timer.Engine
	hub    *stream.Hub
	store  *store.Store
	auth   *auth
	limit  *limiter
}

func New(cfg Config, e *timer.Engine, h *stream.Hub, s *store.Store) *Server {
	return &Server{
		cfg:    cfg,
		engine: e,
		hub:    h,
		store:  s,
		auth:   newAuth(cfg.AdminToken, cfg.CookieSecure, cfg.BasePath+"/"),
		limit:  newLimiter(),
	}
}

// Handler returns the root handler with every route under BasePath.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.health)
	mux.HandleFunc("GET /api/v1/stream", s.stream)
	mux.HandleFunc("GET /api/v1/state", s.state)
	mux.HandleFunc("GET /api/v1/time", s.time)

	mux.HandleFunc("POST /api/v1/admin/login", s.login)
	mux.HandleFunc("POST /api/v1/admin/logout", s.logout)
	admin := func(pattern string, h http.HandlerFunc) { mux.Handle(pattern, s.requireAdmin(h)) }
	admin("GET /api/v1/admin/session", func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusNoContent) })
	admin("POST /api/v1/admin/timer/start", s.start)
	admin("POST /api/v1/admin/timer/pause", s.simpleOp("pause", s.engine.Pause))
	admin("POST /api/v1/admin/timer/resume", s.simpleOp("resume", s.engine.Resume))
	admin("POST /api/v1/admin/timer/end", s.simpleOp("end", s.engine.End))
	admin("POST /api/v1/admin/timer/extend", s.extend)
	admin("POST /api/v1/admin/timer/reduce", s.reduce)
	admin("PUT /api/v1/admin/timer/reminders", s.setReminders)
	admin("GET /api/v1/admin/presets", s.listPresets)
	admin("POST /api/v1/admin/presets", s.createPreset)
	admin("PUT /api/v1/admin/presets/order", s.reorderPresets)
	admin("PUT /api/v1/admin/presets/{id}", s.updatePreset)
	admin("DELETE /api/v1/admin/presets/{id}", s.deletePreset)
	admin("GET /api/v1/admin/clients", s.clients)
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
	case errors.Is(err, timer.ErrSeqConflict):
		writeErr(w, http.StatusConflict, "seq_conflict", "状态已被其他控制台改动")
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
func (s *Server) record(r *http.Request, action string, params any, seq *int64) {
	ip := clientIP(r, s.cfg.Trusted)
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := s.store.AddLog(ctx, action, params, seq, ip); err != nil {
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

func (s *Server) state(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, s.engine.Snapshot())
}

func (s *Server) time(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]int64{"server_time": time.Now().UnixMilli()})
}

func (s *Server) stream(w http.ResponseWriter, r *http.Request) {
	rc := http.NewResponseController(w)
	h := w.Header()
	h.Set("Content-Type", "text/event-stream; charset=utf-8")
	h.Set("Cache-Control", "no-cache, no-transform")
	h.Set("Connection", "keep-alive")
	h.Set("X-Accel-Buffering", "no")

	sub := s.hub.Subscribe(r.URL.Query().Get("role"))
	defer s.hub.Unsubscribe(sub)

	snap := s.engine.Snapshot()
	w.WriteHeader(http.StatusOK)
	io.WriteString(w, "retry: 2000\n\n")
	w.Write(stream.Encode("state", snap.Seq, snap))
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
			if _, err := w.Write(stream.Encode("sync", -1, s.engine.Sync())); err != nil {
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
	s.record(r, "login", nil, nil)
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) logout(w http.ResponseWriter, r *http.Request) {
	s.auth.clearCookie(w)
	w.WriteHeader(http.StatusNoContent)
}

// ---- timer ----

type seqBody struct {
	IfSeq *int64 `json:"if_seq"`
}

func (s *Server) simpleOp(action string, op func(*int64) (timer.State, error)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var body seqBody
		if !decode(w, r, &body) {
			return
		}
		st, err := op(body.IfSeq)
		if err != nil {
			s.opError(w, err)
			return
		}
		s.record(r, action, nil, &st.Seq)
		writeJSON(w, http.StatusOK, st)
	}
}

func (s *Server) start(w http.ResponseWriter, r *http.Request) {
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
	st, err := s.engine.Start(cfg, body.IfSeq)
	if err != nil {
		s.opError(w, err)
		return
	}
	s.record(r, "start", params, &st.Seq)
	writeJSON(w, http.StatusOK, st)
}

func (s *Server) extend(w http.ResponseWriter, r *http.Request) {
	var body struct {
		DeltaMs int64            `json:"delta_ms"`
		Mode    timer.ExtendMode `json:"mode"`
		IfSeq   *int64           `json:"if_seq"`
	}
	if !decode(w, r, &body) {
		return
	}
	st, err := s.engine.Extend(time.Duration(body.DeltaMs)*time.Millisecond, body.Mode, body.IfSeq)
	if err != nil {
		s.opError(w, err)
		return
	}
	s.record(r, "extend", map[string]any{"delta_ms": body.DeltaMs, "mode": body.Mode}, &st.Seq)
	writeJSON(w, http.StatusOK, st)
}

func (s *Server) reduce(w http.ResponseWriter, r *http.Request) {
	var body struct {
		DeltaMs int64            `json:"delta_ms"`
		Mode    timer.ExtendMode `json:"mode"`
		IfSeq   *int64           `json:"if_seq"`
	}
	if !decode(w, r, &body) {
		return
	}
	st, err := s.engine.Reduce(time.Duration(body.DeltaMs)*time.Millisecond, body.Mode, body.IfSeq)
	if err != nil {
		s.opError(w, err)
		return
	}
	s.record(r, "reduce", map[string]any{"delta_ms": body.DeltaMs, "mode": body.Mode}, &st.Seq)
	writeJSON(w, http.StatusOK, st)
}

func (s *Server) setReminders(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Reminders []timer.Reminder `json:"reminders"`
		IfSeq     *int64           `json:"if_seq"`
	}
	if !decode(w, r, &body) {
		return
	}
	st, err := s.engine.SetReminders(body.Reminders, body.IfSeq)
	if err != nil {
		s.opError(w, err)
		return
	}
	s.record(r, "reminders", map[string]any{"count": len(st.Reminders)}, &st.Seq)
	writeJSON(w, http.StatusOK, st)
}

// ---- presets ----

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
	s.record(r, "preset.create", map[string]any{"id": p.ID, "name": p.Name}, nil)
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
	s.record(r, "preset.update", map[string]any{"id": p.ID, "name": p.Name}, nil)
	writeJSON(w, http.StatusOK, p)
}

func (s *Server) deletePreset(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if err := s.store.DeletePreset(r.Context(), id); err != nil {
		s.opError(w, err)
		return
	}
	s.record(r, "preset.delete", map[string]any{"id": id}, nil)
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
	s.record(r, "preset.reorder", nil, nil)
	w.WriteHeader(http.StatusNoContent)
}

// ---- misc ----

func (s *Server) clients(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, s.hub.Counts())
}

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

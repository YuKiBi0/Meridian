// Package rooms runs one countdown per room (PRD §4) and wires each to the
// SSE hub and the database.
package rooms

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"sort"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/YuKiBi0/Meridian/server/internal/store"
	"github.com/YuKiBi0/Meridian/server/internal/stream"
	"github.com/YuKiBi0/Meridian/server/internal/timer"
)

const (
	MaxRooms   = 100
	MaxNameLen = 40
)

var (
	ErrNotFound = errors.New("room not found")
	ErrTooMany  = errors.New("too many rooms")
)

// NewID returns a UUIDv7 (RFC 9562): a millisecond timestamp followed by
// random bits, so ids sort by creation time.
func NewID() string {
	var b [16]byte
	if _, err := rand.Read(b[6:]); err != nil {
		panic(err)
	}
	ms := uint64(time.Now().UnixMilli())
	for i := 0; i < 6; i++ {
		b[i] = byte(ms >> (40 - 8*i))
	}
	b[6] = 0x70 | b[6]&0x0f
	b[8] = 0x80 | b[8]&0x3f
	h := hex.EncodeToString(b[:])
	return h[0:8] + "-" + h[8:12] + "-" + h[12:16] + "-" + h[16:20] + "-" + h[20:]
}

// ParseID returns id in canonical lowercase form, or false if it is not a
// UUID.
func ParseID(id string) (string, bool) {
	if len(id) != 36 {
		return "", false
	}
	id = strings.ToLower(id)
	for i, c := range id {
		switch i {
		case 8, 13, 18, 23:
			if c != '-' {
				return "", false
			}
		default:
			if !(c >= '0' && c <= '9' || c >= 'a' && c <= 'f') {
				return "", false
			}
		}
	}
	return id, true
}

// ValidName trims name and checks its length; names need not be unique.
func ValidName(name string) (string, error) {
	name = strings.TrimSpace(name)
	if n := utf8.RuneCountInString(name); n == 0 || n > MaxNameLen {
		return "", &timer.ValidationError{Msg: "房间名需为 1 到 40 字"}
	}
	return name, nil
}

// Info describes a room.
type Info struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	CreatedAt time.Time `json:"created_at"`
}

type room struct {
	info   Info
	engine *timer.Engine
}

// Manager owns every room. Its methods are safe for concurrent use.
type Manager struct {
	mu      sync.RWMutex
	rooms   map[string]*room
	store   *store.Store
	hub     *stream.Hub
	persist *store.Persister
}

// listener connects one room's engine to the hub and the database.
type listener struct {
	room    string
	hub     *stream.Hub
	persist *store.Persister
}

func (l listener) State(s timer.State) {
	l.hub.Publish(l.room, stream.Encode("state", s.Seq, s))
	// Consoles on the room list show each room's status.
	RoomsChanged(l.hub)
}
func (l listener) Reminder(f timer.Fired)    { l.hub.Publish(l.room, stream.Encode("reminder", -1, f)) }
func (l listener) Persist(p timer.Persisted) { l.persist.Save(l.room, p) }

// RoomsChanged tells consoles on the room list to reload it. It carries no
// data: the stream is public and the list is admin-only.
func RoomsChanged(h *stream.Hub) {
	h.Publish("", stream.Encode("rooms", -1, struct{}{}))
}

// Load restores every stored room and starts its engine.
func Load(ctx context.Context, st *store.Store, hub *stream.Hub, persist *store.Persister) (*Manager, error) {
	stored, err := st.ListRooms(ctx)
	if err != nil {
		return nil, err
	}
	m := &Manager{rooms: map[string]*room{}, store: st, hub: hub, persist: persist}
	now := time.Now()
	for _, r := range stored {
		t := timer.New()
		if r.Timer != nil {
			t = timer.Restore(*r.Timer, now)
		}
		m.rooms[r.ID] = m.start(Info{ID: r.ID, Name: r.Name, CreatedAt: r.CreatedAt}, t)
	}
	return m, nil
}

func (m *Manager) start(info Info, t *timer.Timer) *room {
	return &room{info: info, engine: timer.NewEngine(t, listener{room: info.ID, hub: m.hub, persist: m.persist})}
}

// Get returns the room's info and engine.
func (m *Manager) Get(id string) (Info, *timer.Engine, bool) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	r, ok := m.rooms[id]
	if !ok {
		return Info{}, nil, false
	}
	return r.info, r.engine, true
}

// Room is a room with its current countdown.
type Room struct {
	Info
	State timer.State
}

// List returns every room, oldest first.
func (m *Manager) List() []Room {
	m.mu.RLock()
	rs := make([]*room, 0, len(m.rooms))
	for _, r := range m.rooms {
		rs = append(rs, r)
	}
	m.mu.RUnlock()
	sort.Slice(rs, func(i, j int) bool {
		a, b := rs[i].info, rs[j].info
		if !a.CreatedAt.Equal(b.CreatedAt) {
			return a.CreatedAt.Before(b.CreatedAt)
		}
		return a.ID < b.ID
	})
	out := make([]Room, len(rs))
	for i, r := range rs {
		out[i] = Room{Info: r.info, State: r.engine.Snapshot()}
	}
	return out
}

// Len returns the number of rooms.
func (m *Manager) Len() int {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return len(m.rooms)
}

// Create adds a room with an idle countdown. Database calls happen outside
// the lock so a slow database never stalls the other rooms.
func (m *Manager) Create(ctx context.Context, name string) (Info, error) {
	name, err := ValidName(name)
	if err != nil {
		return Info{}, err
	}
	if m.Len() >= MaxRooms {
		return Info{}, ErrTooMany
	}
	info := Info{ID: NewID(), Name: name}
	if info.CreatedAt, err = m.store.CreateRoom(ctx, info.ID, name); err != nil {
		return Info{}, err
	}
	r := m.start(info, timer.New())
	m.mu.Lock()
	m.rooms[info.ID] = r
	m.mu.Unlock()
	RoomsChanged(m.hub)
	return info, nil
}

// Rename changes a room's name and tells everyone in it.
func (m *Manager) Rename(ctx context.Context, id, name string) (Info, error) {
	name, err := ValidName(name)
	if err != nil {
		return Info{}, err
	}
	if _, _, ok := m.Get(id); !ok {
		return Info{}, ErrNotFound
	}
	if err := m.store.RenameRoom(ctx, id, name); err != nil {
		if errors.Is(err, store.ErrNotFound) {
			err = ErrNotFound
		}
		return Info{}, err
	}
	m.mu.Lock()
	r, ok := m.rooms[id]
	var info Info
	if ok {
		r.info.Name = name
		info = r.info
	}
	m.mu.Unlock()
	if !ok {
		return Info{}, ErrNotFound
	}
	m.hub.Publish(id, stream.Encode("room", -1, info))
	RoomsChanged(m.hub)
	return info, nil
}

// Delete stops the room's countdown, removes it and disconnects everyone
// in it with a room_deleted event.
func (m *Manager) Delete(ctx context.Context, id string) (Info, error) {
	if _, _, ok := m.Get(id); !ok {
		return Info{}, ErrNotFound
	}
	// Already gone from the database means a concurrent delete won.
	if err := m.store.DeleteRoom(ctx, id); err != nil && !errors.Is(err, store.ErrNotFound) {
		return Info{}, err
	}
	m.mu.Lock()
	r, ok := m.rooms[id]
	delete(m.rooms, id)
	m.mu.Unlock()
	if !ok {
		return Info{}, ErrNotFound
	}
	r.engine.Close()
	m.persist.Forget(id)
	m.hub.CloseRoom(id, stream.Encode("room_deleted", -1, map[string]string{"id": id}))
	RoomsChanged(m.hub)
	return r.info, nil
}

// Close stops every engine.
func (m *Manager) Close() {
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, r := range m.rooms {
		r.engine.Close()
	}
}

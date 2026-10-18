// Package stream fans server-sent events out to subscribers.
package stream

import (
	"bytes"
	"encoding/json"
	"strconv"
	"sync"
)

// Roles a subscriber can declare with ?role=.
const (
	RoleClient  = "client"
	RoleConsole = "console"
)

const bufferSize = 32

// Sub is one SSE connection. C is closed when the hub drops it.
type Sub struct {
	C    chan []byte
	role string
	room string // "" for a console looking at the room list
}

// Hub broadcasts pre-encoded events. A subscriber that falls behind by
// more than bufferSize events is dropped; its client reconnects and gets
// a fresh snapshot, which is better than stalling everyone else.
type Hub struct {
	mu   sync.Mutex
	subs map[*Sub]struct{}
}

func NewHub() *Hub {
	return &Hub{subs: map[*Sub]struct{}{}}
}

// Subscribe adds a subscriber to room ("" is the room list, consoles only).
func (h *Hub) Subscribe(role, room string) *Sub {
	if role != RoleConsole {
		role = RoleClient
	}
	s := &Sub{C: make(chan []byte, bufferSize), role: role, room: room}
	h.mu.Lock()
	h.subs[s] = struct{}{}
	h.mu.Unlock()
	return s
}

func (h *Hub) Unsubscribe(s *Sub) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.drop(s)
}

func (h *Hub) drop(s *Sub) {
	if _, ok := h.subs[s]; ok {
		delete(h.subs, s)
		close(s.C)
	}
}

// send must be called with mu held.
func (h *Hub) send(s *Sub, msg []byte) {
	select {
	case s.C <- msg:
	default:
		h.drop(s)
	}
}

// Publish sends msg to every subscriber of room without blocking.
func (h *Hub) Publish(room string, msg []byte) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for s := range h.subs {
		if s.room == room {
			h.send(s, msg)
		}
	}
}

// PublishRole sends msg to subscribers of role in every room and the list.
func (h *Hub) PublishRole(role string, msg []byte) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for s := range h.subs {
		if s.role == role {
			h.send(s, msg)
		}
	}
}

// CloseRoom sends msg to every subscriber of room, then disconnects them.
func (h *Hub) CloseRoom(room string, msg []byte) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for s := range h.subs {
		if s.room == room {
			h.send(s, msg)
			h.drop(s)
		}
	}
}

// Counts returns the number of subscribers of room per role.
func (h *Hub) Counts(room string) map[string]int {
	h.mu.Lock()
	defer h.mu.Unlock()
	c := map[string]int{RoleClient: 0, RoleConsole: 0}
	for s := range h.subs {
		if s.room == room {
			c[s.role]++
		}
	}
	return c
}

// Encode formats one SSE event. id is omitted when negative.
func Encode(event string, id int64, data any) []byte {
	payload, err := json.Marshal(data)
	if err != nil {
		panic(err)
	}
	var b bytes.Buffer
	if id >= 0 {
		b.WriteString("id: ")
		b.WriteString(strconv.FormatInt(id, 10))
		b.WriteByte('\n')
	}
	b.WriteString("event: ")
	b.WriteString(event)
	b.WriteString("\ndata: ")
	b.Write(payload)
	b.WriteString("\n\n")
	return b.Bytes()
}

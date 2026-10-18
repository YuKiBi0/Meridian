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

func (h *Hub) Subscribe(role string) *Sub {
	if role != RoleConsole {
		role = RoleClient
	}
	s := &Sub{C: make(chan []byte, bufferSize), role: role}
	h.mu.Lock()
	h.subs[s] = struct{}{}
	h.mu.Unlock()
	return s
}

func (h *Hub) Unsubscribe(s *Sub) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if _, ok := h.subs[s]; ok {
		delete(h.subs, s)
		close(s.C)
	}
}

// Publish sends msg to every subscriber without blocking.
func (h *Hub) Publish(msg []byte) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for s := range h.subs {
		select {
		case s.C <- msg:
		default:
			delete(h.subs, s)
			close(s.C)
		}
	}
}

// Counts returns the number of subscribers per role.
func (h *Hub) Counts() map[string]int {
	h.mu.Lock()
	defer h.mu.Unlock()
	c := map[string]int{RoleClient: 0, RoleConsole: 0}
	for s := range h.subs {
		c[s.role]++
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

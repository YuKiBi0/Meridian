package store

import (
	"context"
	"log/slog"
	"sync"
	"time"

	"github.com/YuKiBi0/Meridian/server/internal/timer"
)

// Persister writes timer snapshots in the background so no engine ever
// waits on the database. Only the latest pending snapshot of each room is
// kept; failed writes are retried with backoff.
type Persister struct {
	s      *Store
	mu     sync.Mutex
	latest map[string]timer.Persisted // by room id
	signal chan struct{}
	done   chan struct{}
}

func NewPersister(s *Store) *Persister {
	p := &Persister{s: s, latest: map[string]timer.Persisted{}, signal: make(chan struct{}, 1), done: make(chan struct{})}
	go p.run()
	return p
}

// Save queues v for room, replacing anything of that room not yet written.
func (p *Persister) Save(room string, v timer.Persisted) {
	p.mu.Lock()
	p.latest[room] = v
	p.mu.Unlock()
	select {
	case p.signal <- struct{}{}:
	default:
	}
}

// Forget drops the pending snapshot of a deleted room.
func (p *Persister) Forget(room string) {
	p.mu.Lock()
	delete(p.latest, room)
	p.mu.Unlock()
}

// Close flushes the pending snapshot (bounded by ctx) and stops.
func (p *Persister) Close(ctx context.Context) {
	close(p.signal)
	select {
	case <-p.done:
	case <-ctx.Done():
	}
}

func (p *Persister) run() {
	defer close(p.done)
	backoff := time.Second
	for range p.signal {
		for {
			p.mu.Lock()
			var room string
			var v timer.Persisted
			found := false
			for room, v = range p.latest {
				found = true
				break
			}
			if found {
				delete(p.latest, room)
			}
			p.mu.Unlock()
			if !found {
				break
			}
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			err := p.s.SaveTimer(ctx, room, v)
			cancel()
			if err == nil {
				backoff = time.Second
				continue
			}
			slog.Error("save timer failed, retrying", "room", room, "err", err, "in", backoff)
			p.mu.Lock()
			if _, newer := p.latest[room]; !newer {
				p.latest[room] = v
			}
			p.mu.Unlock()
			time.Sleep(backoff)
			backoff = min(backoff*2, 30*time.Second)
		}
	}
}

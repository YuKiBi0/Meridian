package store

import (
	"context"
	"log/slog"
	"sync"
	"time"

	"github.com/YuKiBi0/Meridian/server/internal/timer"
)

// Persister writes timer snapshots in the background so the engine never
// waits on the database. Only the latest pending snapshot is kept; failed
// writes are retried with backoff.
type Persister struct {
	s      *Store
	mu     sync.Mutex
	latest *timer.Persisted
	signal chan struct{}
	done   chan struct{}
}

func NewPersister(s *Store) *Persister {
	p := &Persister{s: s, signal: make(chan struct{}, 1), done: make(chan struct{})}
	go p.run()
	return p
}

// Save queues p, replacing anything not yet written.
func (p *Persister) Save(v timer.Persisted) {
	p.mu.Lock()
	p.latest = &v
	p.mu.Unlock()
	select {
	case p.signal <- struct{}{}:
	default:
	}
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
			v := p.latest
			p.latest = nil
			p.mu.Unlock()
			if v == nil {
				break
			}
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			err := p.s.SaveTimer(ctx, *v)
			cancel()
			if err == nil {
				backoff = time.Second
				continue
			}
			slog.Error("save timer failed, retrying", "err", err, "in", backoff)
			p.mu.Lock()
			if p.latest == nil {
				p.latest = v
			}
			p.mu.Unlock()
			time.Sleep(backoff)
			backoff = min(backoff*2, 30*time.Second)
		}
	}
}

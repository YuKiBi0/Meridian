package timer

import (
	"sync"
	"time"
)

// Listener receives everything the engine emits. Calls happen while the
// engine lock is held, in order, so implementations must not block.
type Listener interface {
	State(State)
	Reminder(Fired)
	Persist(Persisted)
}

// Engine owns the single Timer, serializes access to it and wakes itself
// up exactly when the next reminder or the expiry is due.
type Engine struct {
	mu    sync.Mutex
	t     *Timer
	now   func() time.Time
	l     Listener
	wake  *time.Timer
	close bool
}

// NewEngine starts an engine from a restored timer (or New()).
func NewEngine(t *Timer, l Listener) *Engine {
	e := &Engine{t: t, now: time.Now, l: l}
	e.mu.Lock()
	defer e.mu.Unlock()
	now := e.now()
	e.settle(now)
	e.l.Persist(e.t.Persist())
	e.schedule(now)
	return e
}

// Close stops the wake-up timer.
func (e *Engine) Close() {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.close = true
	if e.wake != nil {
		e.wake.Stop()
	}
}

// Snapshot returns the current state.
func (e *Engine) Snapshot() State {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.t.Snapshot(e.now())
}

// Sync returns the heartbeat payload.
func (e *Engine) Sync() Sync {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.t.SyncAt(e.now())
}

func (e *Engine) Start(cfg Config, ifSeq *int64) (State, error) {
	return e.do(ifSeq, func(now time.Time) error {
		e.t.Start(cfg, NewID("r_"), now)
		return nil
	})
}

func (e *Engine) Pause(ifSeq *int64) (State, error) {
	return e.do(ifSeq, e.t.Pause)
}

func (e *Engine) Resume(ifSeq *int64) (State, error) {
	return e.do(ifSeq, e.t.Resume)
}

func (e *Engine) End(ifSeq *int64) (State, error) {
	return e.do(ifSeq, e.t.End)
}

func (e *Engine) Extend(delta time.Duration, mode ExtendMode, ifSeq *int64) (State, error) {
	return e.do(ifSeq, func(now time.Time) error {
		return e.t.Extend(delta, mode, now)
	})
}

func (e *Engine) do(ifSeq *int64, op func(time.Time) error) (State, error) {
	e.mu.Lock()
	defer e.mu.Unlock()
	now := e.now()
	e.settle(now)
	if err := e.t.CheckSeq(ifSeq); err != nil {
		return e.t.Snapshot(now), err
	}
	if err := op(now); err != nil {
		return e.t.Snapshot(now), err
	}
	// An extension or a fresh start may make reminders due immediately.
	fired, _ := e.t.Advance(now)
	s := e.t.Snapshot(now)
	e.l.State(s)
	for _, f := range fired {
		e.l.Reminder(f)
	}
	e.l.Persist(e.t.Persist())
	e.schedule(now)
	return s, nil
}

// settle applies anything that became due before now and emits it.
func (e *Engine) settle(now time.Time) {
	fired, changed := e.t.Advance(now)
	if changed {
		e.l.State(e.t.Snapshot(now))
	}
	for _, f := range fired {
		e.l.Reminder(f)
	}
	if changed || len(fired) > 0 {
		e.l.Persist(e.t.Persist())
	}
}

func (e *Engine) schedule(now time.Time) {
	if e.wake != nil {
		e.wake.Stop()
		e.wake = nil
	}
	if e.close {
		return
	}
	d, ok := e.t.NextDeadline()
	if !ok {
		return
	}
	e.wake = time.AfterFunc(d.Sub(now), e.tick)
}

func (e *Engine) tick() {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.close {
		return
	}
	now := e.now()
	e.settle(now)
	e.schedule(now)
}

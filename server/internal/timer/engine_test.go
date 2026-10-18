package timer

import (
	"sync"
	"testing"
	"time"
)

type recorder struct {
	mu        sync.Mutex
	states    []State
	reminders []Fired
	persisted int
}

func (r *recorder) State(s State) { r.mu.Lock(); r.states = append(r.states, s); r.mu.Unlock() }
func (r *recorder) Reminder(f Fired) {
	r.mu.Lock()
	r.reminders = append(r.reminders, f)
	r.mu.Unlock()
}
func (r *recorder) Persist(Persisted) { r.mu.Lock(); r.persisted++; r.mu.Unlock() }

func (r *recorder) last() (State, int) {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.states[len(r.states)-1], len(r.reminders)
}

func TestEngineWakesForRemindersAndExpiry(t *testing.T) {
	rec := &recorder{}
	e := NewEngine(New(), rec)
	defer e.Close()

	c := Config{TotalMs: 1200, Reminders: []Reminder{{AtMs: 1000, Text: "a"}, {AtMs: 0, Text: "end"}}}
	if err := c.Normalize(); err != nil {
		t.Fatal(err)
	}
	if _, err := e.Start(c, nil); err != nil {
		t.Fatal(err)
	}
	time.Sleep(400 * time.Millisecond)
	if _, n := rec.last(); n != 1 {
		t.Fatalf("reminders after 400ms = %d, want 1", n)
	}
	time.Sleep(1000 * time.Millisecond)
	s, n := rec.last()
	if s.Status != Expired || n != 2 {
		t.Fatalf("status=%v reminders=%d", s.Status, n)
	}
}

func TestEngineSeqConflict(t *testing.T) {
	e := NewEngine(New(), &recorder{})
	defer e.Close()
	c := Config{TotalMs: 60000}
	c.Normalize()
	s, _ := e.Start(c, nil)
	stale := s.Seq - 1
	if _, err := e.Pause(&stale); err != ErrSeqConflict {
		t.Fatalf("err = %v", err)
	}
	if _, err := e.Pause(&s.Seq); err != nil {
		t.Fatal(err)
	}
}

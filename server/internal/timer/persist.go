package timer

import (
	"time"
)

// Persisted is the durable form of a Timer. Running and expired runs are
// anchored to wall-clock times so they survive a restart; at runtime the
// monotonic clock is used instead.
type Persisted struct {
	Seq         int64
	RunID       string
	Status      Status
	Title       string
	TotalMs     int64
	RemainingMs int64
	EndsAt      *time.Time
	ExpiredAt   *time.Time
	OnExpire    OnExpire
	Reminders   []Reminder
	Fired       []string
}

// Persist returns the durable form of t.
func (t *Timer) Persist() Persisted {
	p := Persisted{
		Seq:         t.seq,
		RunID:       t.runID,
		Status:      t.status,
		Title:       t.cfg.Title,
		TotalMs:     t.total.Milliseconds(),
		RemainingMs: t.remaining.Milliseconds(),
		OnExpire:    t.cfg.OnExpire,
		Reminders:   t.cfg.Reminders,
		Fired:       []string{},
	}
	if p.OnExpire == "" {
		p.OnExpire = Stop
	}
	if p.Reminders == nil {
		p.Reminders = []Reminder{}
	}
	switch t.status {
	case Running:
		w := t.endsAt.Round(0)
		p.EndsAt = &w
	case Expired:
		w := t.expiredAt.Round(0)
		p.ExpiredAt = &w
	}
	for id := range t.fired {
		p.Fired = append(p.Fired, id)
	}
	return p
}

// Restore rebuilds a Timer from p at now. A run that finished while the
// server was down comes back as Expired; reminders crossed during the
// downtime are marked fired and never replayed.
func Restore(p Persisted, now time.Time) *Timer {
	t := New()
	t.seq = p.Seq + 1
	if p.Status == Idle || p.Status == "" {
		return t
	}
	t.runID = p.RunID
	t.status = p.Status
	t.cfg = Config{Title: p.Title, TotalMs: p.TotalMs, OnExpire: p.OnExpire, Reminders: p.Reminders}
	t.total = time.Duration(p.TotalMs) * time.Millisecond
	for _, id := range p.Fired {
		t.fired[id] = true
	}
	switch p.Status {
	case Paused:
		t.remaining = time.Duration(p.RemainingMs) * time.Millisecond
	case Running:
		if p.EndsAt == nil {
			return New()
		}
		rem := p.EndsAt.Sub(now) // wall-clock difference
		t.endsAt = now.Add(rem)  // re-anchored on the monotonic clock
		for _, r := range t.cfg.Reminders {
			if time.Duration(r.AtMs)*time.Millisecond >= rem {
				t.fired[r.ID] = true
			}
		}
		if rem <= 0 {
			t.status = Expired
			t.expiredAt = t.endsAt
		}
	case Expired:
		if p.ExpiredAt == nil {
			t.expiredAt = now
		} else {
			t.expiredAt = now.Add(-now.Sub(*p.ExpiredAt))
		}
		for _, r := range t.cfg.Reminders {
			t.fired[r.ID] = true
		}
	default:
		return New()
	}
	return t
}

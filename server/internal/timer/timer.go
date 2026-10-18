package timer

import (
	"errors"
	"time"
)

var (
	ErrInvalidState = errors.New("invalid state")
	ErrSeqConflict  = errors.New("seq conflict")
)

// LastEnd marks a run that was just ended by an operator.
type LastEnd struct {
	RunID string `json:"run_id"`
	At    int64  `json:"at"`
}

// State is the snapshot sent to subscribers (PRD §9.1).
type State struct {
	Seq         int64    `json:"seq"`
	RunID       *string  `json:"run_id"`
	Status      Status   `json:"status"`
	Title       string   `json:"title"`
	TotalMs     int64    `json:"total_ms"`
	RemainingMs int64    `json:"remaining_ms"`
	OvertimeMs  int64    `json:"overtime_ms"`
	OnExpire    OnExpire `json:"on_expire"`
	MarksMs     []int64  `json:"marks_ms"`
	ServerTime  int64    `json:"server_time"`
	LastEnd     *LastEnd `json:"last_end"`
}

// Sync is the heartbeat payload.
type Sync struct {
	Seq         int64  `json:"seq"`
	Status      Status `json:"status"`
	RemainingMs int64  `json:"remaining_ms"`
	OvertimeMs  int64  `json:"overtime_ms"`
	ServerTime  int64  `json:"server_time"`
}

// Fired is the payload of a reminder event.
type Fired struct {
	Seq        int64  `json:"seq"`
	RunID      string `json:"run_id"`
	ReminderID string `json:"reminder_id"`
	AtMs       int64  `json:"at_ms"`
	Title      string `json:"title"`
	Text       string `json:"text"`
	DurationMs int64  `json:"duration_ms"`
	Sticky     bool   `json:"sticky"`
}

// Timer is the countdown state machine. It never reads the clock itself:
// every method takes now, which keeps it deterministic and testable.
// It is not safe for concurrent use.
type Timer struct {
	seq       int64
	runID     string
	status    Status
	cfg       Config
	total     time.Duration
	endsAt    time.Time     // valid while running
	remaining time.Duration // valid while paused
	expiredAt time.Time     // valid while expired
	fired     map[string]bool
	lastEnd   *LastEnd
}

// New returns an idle timer.
func New() *Timer {
	return &Timer{status: Idle, fired: map[string]bool{}}
}

func (t *Timer) Seq() int64     { return t.seq }
func (t *Timer) Status() Status { return t.status }

// Remaining returns the time left at now.
func (t *Timer) Remaining(now time.Time) time.Duration {
	switch t.status {
	case Running:
		if d := t.endsAt.Sub(now); d > 0 {
			return d
		}
		return 0
	case Paused:
		return t.remaining
	}
	return 0
}

// OvertimeAt returns how long the timer has been counting past zero.
func (t *Timer) OvertimeAt(now time.Time) time.Duration {
	if t.status != Expired || t.cfg.OnExpire != Overtime {
		return 0
	}
	if d := now.Sub(t.expiredAt); d > 0 {
		return d
	}
	return 0
}

// CheckSeq returns ErrSeqConflict when ifSeq is set and stale.
func (t *Timer) CheckSeq(ifSeq *int64) error {
	if ifSeq != nil && *ifSeq != t.seq {
		return ErrSeqConflict
	}
	return nil
}

// Start begins a new run, replacing any current one. cfg must be normalized.
func (t *Timer) Start(cfg Config, runID string, now time.Time) {
	t.cfg = cfg
	t.runID = runID
	t.status = Running
	t.total = time.Duration(cfg.TotalMs) * time.Millisecond
	t.endsAt = now.Add(t.total)
	t.remaining = 0
	t.expiredAt = time.Time{}
	t.fired = map[string]bool{}
	t.lastEnd = nil
	t.seq++
}

// Pause freezes a running timer.
func (t *Timer) Pause(now time.Time) error {
	if t.status != Running {
		return ErrInvalidState
	}
	t.remaining = t.Remaining(now)
	t.status = Paused
	t.seq++
	return nil
}

// Resume continues a paused timer.
func (t *Timer) Resume(now time.Time) error {
	if t.status != Paused {
		return ErrInvalidState
	}
	t.endsAt = now.Add(t.remaining)
	t.status = Running
	t.seq++
	return nil
}

// End terminates the current run.
func (t *Timer) End(now time.Time) error {
	if t.status == Idle {
		return ErrInvalidState
	}
	t.lastEnd = &LastEnd{RunID: t.runID, At: now.UnixMilli()}
	t.runID = ""
	t.status = Idle
	t.cfg = Config{}
	t.total = 0
	t.remaining = 0
	t.fired = map[string]bool{}
	t.seq++
	return nil
}

// Extend adds delta following the rules of PRD §5.4.
func (t *Timer) Extend(delta time.Duration, mode ExtendMode, now time.Time) error {
	if delta < MinExtend || delta > MaxExtend {
		return invalid("延长时间需在 1 秒到 24 小时之间")
	}
	if mode != ExtendRemaining && mode != ExtendTotal {
		return invalid("mode 只能是 remaining 或 total")
	}
	var rem time.Duration
	switch t.status {
	case Running, Paused:
		rem = t.Remaining(now) + delta
		if mode == ExtendTotal {
			t.total += delta
		}
	case Expired:
		rem = delta
		if mode == ExtendTotal {
			t.total += delta
		}
		t.status = Running
		t.expiredAt = time.Time{}
	default:
		return ErrInvalidState
	}
	if rem > t.total {
		t.total = rem
	}
	if t.status == Running {
		t.endsAt = now.Add(rem)
	} else {
		t.remaining = rem
	}
	for _, r := range t.cfg.Reminders {
		if time.Duration(r.AtMs)*time.Millisecond < rem {
			delete(t.fired, r.ID)
		}
	}
	t.seq++
	return nil
}

// Advance settles everything that should have happened by now: it fires
// crossed reminders and moves a finished run to Expired. changed reports
// whether the state snapshot changed (seq was bumped).
func (t *Timer) Advance(now time.Time) (fired []Fired, changed bool) {
	if t.status != Running {
		return nil, false
	}
	rem := t.endsAt.Sub(now)
	if rem <= 0 {
		t.status = Expired
		t.expiredAt = t.endsAt
		t.remaining = 0
		t.seq++
		changed = true
	}
	for _, r := range t.cfg.Reminders { // sorted by AtMs descending
		if t.fired[r.ID] || time.Duration(r.AtMs)*time.Millisecond < rem {
			continue
		}
		t.fired[r.ID] = true
		fired = append(fired, Fired{
			Seq:        t.seq,
			RunID:      t.runID,
			ReminderID: r.ID,
			AtMs:       r.AtMs,
			Title:      t.cfg.Title,
			Text:       r.Text,
			DurationMs: r.DurationMs,
			Sticky:     r.Sticky,
		})
	}
	return fired, changed
}

// NextDeadline returns when Advance next needs to run.
func (t *Timer) NextDeadline() (time.Time, bool) {
	if t.status != Running {
		return time.Time{}, false
	}
	for _, r := range t.cfg.Reminders {
		if !t.fired[r.ID] && r.AtMs > 0 {
			return t.endsAt.Add(-time.Duration(r.AtMs) * time.Millisecond), true
		}
	}
	return t.endsAt, true
}

// Snapshot returns the full state at now.
func (t *Timer) Snapshot(now time.Time) State {
	s := State{
		Seq:         t.seq,
		Status:      t.status,
		Title:       t.cfg.Title,
		TotalMs:     t.total.Milliseconds(),
		RemainingMs: t.Remaining(now).Milliseconds(),
		OvertimeMs:  t.OvertimeAt(now).Milliseconds(),
		OnExpire:    t.cfg.OnExpire,
		MarksMs:     []int64{},
		ServerTime:  now.UnixMilli(),
	}
	if s.OnExpire == "" {
		s.OnExpire = Stop
	}
	if t.status == Idle {
		s.LastEnd = t.lastEnd
	} else {
		id := t.runID
		s.RunID = &id
	}
	for _, r := range t.cfg.Reminders {
		s.MarksMs = append(s.MarksMs, r.AtMs)
	}
	return s
}

// SyncAt returns the heartbeat payload at now.
func (t *Timer) SyncAt(now time.Time) Sync {
	return Sync{
		Seq:         t.seq,
		Status:      t.status,
		RemainingMs: t.Remaining(now).Milliseconds(),
		OvertimeMs:  t.OvertimeAt(now).Milliseconds(),
		ServerTime:  now.UnixMilli(),
	}
}

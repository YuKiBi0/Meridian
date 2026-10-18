package timer

import (
	"errors"
	"testing"
	"time"
)

var t0 = time.Date(2026, 10, 17, 12, 0, 0, 0, time.UTC)

func at(d time.Duration) time.Time { return t0.Add(d) }

func cfg(total time.Duration, reminders ...Reminder) Config {
	c := Config{Title: "测试", TotalMs: total.Milliseconds(), Reminders: reminders}
	if err := c.Normalize(); err != nil {
		panic(err)
	}
	return c
}

func started(c Config) *Timer {
	tm := New()
	tm.Start(c, "r_test", t0)
	return tm
}

func ms(d time.Duration) int64 { return d.Milliseconds() }

func TestStartPauseResume(t *testing.T) {
	tm := started(cfg(10 * time.Minute))
	if got := tm.Snapshot(at(time.Minute)); got.Status != Running || got.RemainingMs != ms(9*time.Minute) {
		t.Fatalf("after 1m: %+v", got)
	}
	if err := tm.Pause(at(2 * time.Minute)); err != nil {
		t.Fatal(err)
	}
	if got := tm.Remaining(at(5 * time.Minute)); got != 8*time.Minute {
		t.Fatalf("paused remaining = %v", got)
	}
	if err := tm.Resume(at(5 * time.Minute)); err != nil {
		t.Fatal(err)
	}
	if got := tm.Remaining(at(6 * time.Minute)); got != 7*time.Minute {
		t.Fatalf("resumed remaining = %v", got)
	}
	if tm.Seq() != 3 {
		t.Fatalf("seq = %d, want 3", tm.Seq())
	}
}

func TestInvalidTransitions(t *testing.T) {
	tm := New()
	for name, err := range map[string]error{
		"pause idle":  tm.Pause(t0),
		"resume idle": tm.Resume(t0),
		"end idle":    tm.End(t0),
		"extend idle": tm.Extend(time.Minute, ExtendTotal, t0),
	} {
		if !errors.Is(err, ErrInvalidState) {
			t.Errorf("%s: err = %v", name, err)
		}
	}
	tm.Start(cfg(time.Minute), "r", t0)
	if !errors.Is(tm.Resume(t0), ErrInvalidState) {
		t.Error("resume running should fail")
	}
	tm.Advance(at(2 * time.Minute))
	if !errors.Is(tm.Pause(at(2*time.Minute)), ErrInvalidState) {
		t.Error("pause expired should fail")
	}
}

func TestExpireStopAndOvertime(t *testing.T) {
	tm := started(cfg(time.Minute))
	_, changed := tm.Advance(at(59 * time.Second))
	if changed {
		t.Fatal("should not expire early")
	}
	_, changed = tm.Advance(at(61 * time.Second))
	if !changed || tm.Status() != Expired {
		t.Fatal("should expire")
	}
	if got := tm.Snapshot(at(90 * time.Second)); got.OvertimeMs != 0 || got.RemainingMs != 0 {
		t.Fatalf("stop mode: %+v", got)
	}

	c := cfg(time.Minute)
	c.OnExpire = Overtime
	tm = started(c)
	tm.Advance(at(70 * time.Second))
	if got := tm.Snapshot(at(90 * time.Second)); got.OvertimeMs != ms(30*time.Second) {
		t.Fatalf("overtime = %d", got.OvertimeMs)
	}
}

func TestExtendRemaining(t *testing.T) {
	tm := started(cfg(10 * time.Minute))
	if err := tm.Extend(2*time.Minute, ExtendRemaining, at(5*time.Minute)); err != nil {
		t.Fatal(err)
	}
	s := tm.Snapshot(at(5 * time.Minute))
	if s.TotalMs != ms(10*time.Minute) || s.RemainingMs != ms(7*time.Minute) {
		t.Fatalf("got total=%d remaining=%d", s.TotalMs, s.RemainingMs)
	}
	// Remaining above total raises total.
	tm.Extend(5*time.Minute, ExtendRemaining, at(5*time.Minute))
	s = tm.Snapshot(at(5 * time.Minute))
	if s.TotalMs != ms(12*time.Minute) || s.RemainingMs != ms(12*time.Minute) {
		t.Fatalf("got total=%d remaining=%d", s.TotalMs, s.RemainingMs)
	}
}

func TestExtendTotal(t *testing.T) {
	tm := started(cfg(10 * time.Minute))
	tm.Pause(at(4 * time.Minute))
	if err := tm.Extend(5*time.Minute, ExtendTotal, at(6*time.Minute)); err != nil {
		t.Fatal(err)
	}
	if tm.Status() != Paused {
		t.Fatal("extend must keep paused")
	}
	s := tm.Snapshot(at(8 * time.Minute))
	if s.TotalMs != ms(15*time.Minute) || s.RemainingMs != ms(11*time.Minute) {
		t.Fatalf("got total=%d remaining=%d", s.TotalMs, s.RemainingMs)
	}
}

func TestExtendFromExpired(t *testing.T) {
	c := cfg(10 * time.Minute)
	c.OnExpire = Overtime
	tm := started(c)
	tm.Advance(at(11 * time.Minute))
	tm.Extend(3*time.Minute, ExtendTotal, at(12*time.Minute))
	s := tm.Snapshot(at(12 * time.Minute))
	if s.Status != Running || s.TotalMs != ms(13*time.Minute) || s.RemainingMs != ms(3*time.Minute) || s.OvertimeMs != 0 {
		t.Fatalf("total mode: %+v", s)
	}

	tm = started(cfg(time.Minute))
	tm.Advance(at(2 * time.Minute))
	tm.Extend(5*time.Minute, ExtendRemaining, at(2*time.Minute))
	s = tm.Snapshot(at(2 * time.Minute))
	if s.TotalMs != ms(5*time.Minute) || s.RemainingMs != ms(5*time.Minute) {
		t.Fatalf("remaining mode, delta > total: %+v", s)
	}
}

func TestRemindersFireOnceAndRearm(t *testing.T) {
	tm := started(cfg(10*time.Minute,
		Reminder{AtMs: ms(5 * time.Minute), Text: "五分钟"},
		Reminder{AtMs: 0, Text: "时间到", Sticky: true},
	))
	if d, _ := tm.NextDeadline(); !d.Equal(at(5 * time.Minute)) {
		t.Fatalf("next deadline = %v", d)
	}
	if f, _ := tm.Advance(at(4 * time.Minute)); len(f) != 0 {
		t.Fatal("fired too early")
	}
	f, _ := tm.Advance(at(5 * time.Minute))
	if len(f) != 1 || f[0].Text != "五分钟" {
		t.Fatalf("fired = %+v", f)
	}
	if f, _ := tm.Advance(at(6 * time.Minute)); len(f) != 0 {
		t.Fatal("fired twice")
	}
	if d, _ := tm.NextDeadline(); !d.Equal(at(10 * time.Minute)) {
		t.Fatalf("next deadline = %v", d)
	}
	// Extending above the reminder point re-arms it.
	tm.Extend(2*time.Minute, ExtendRemaining, at(6*time.Minute)) // remaining 6m
	f, _ = tm.Advance(at(7 * time.Minute))                        // remaining 5m
	if len(f) != 1 {
		t.Fatalf("rearmed reminder fired %d times", len(f))
	}
	f, changed := tm.Advance(at(12 * time.Minute))
	if !changed || len(f) != 1 || !f[0].Sticky {
		t.Fatalf("zero reminder: changed=%v fired=%+v", changed, f)
	}
}

func TestSkippedRemindersFireTogether(t *testing.T) {
	tm := started(cfg(10*time.Minute,
		Reminder{AtMs: ms(5 * time.Minute), Text: "a"},
		Reminder{AtMs: ms(2 * time.Minute), Text: "b"},
	))
	f, _ := tm.Advance(at(9 * time.Minute))
	if len(f) != 2 || f[0].Text != "a" || f[1].Text != "b" {
		t.Fatalf("fired = %+v", f)
	}
}

func TestEndSetsLastEnd(t *testing.T) {
	tm := started(cfg(time.Minute))
	tm.End(at(10 * time.Second))
	s := tm.Snapshot(at(10 * time.Second))
	if s.Status != Idle || s.RunID != nil || s.LastEnd == nil || s.LastEnd.RunID != "r_test" {
		t.Fatalf("%+v", s)
	}
	tm.Start(cfg(time.Minute), "r_2", at(time.Minute))
	if tm.Snapshot(at(time.Minute)).LastEnd != nil {
		t.Fatal("last_end should clear on start")
	}
}

func TestCheckSeq(t *testing.T) {
	tm := started(cfg(time.Minute))
	stale, cur := int64(0), tm.Seq()
	if !errors.Is(tm.CheckSeq(&stale), ErrSeqConflict) {
		t.Fatal("stale seq accepted")
	}
	if tm.CheckSeq(&cur) != nil || tm.CheckSeq(nil) != nil {
		t.Fatal("valid seq rejected")
	}
}

func TestNormalize(t *testing.T) {
	bad := []Config{
		{TotalMs: 0},
		{TotalMs: ms(25 * time.Hour)},
		{TotalMs: 60000, OnExpire: "loop"},
		{TotalMs: 60000, Reminders: []Reminder{{AtMs: 60000, Text: "x"}}},
		{TotalMs: 60000, Reminders: []Reminder{{AtMs: 1000, Text: ""}}},
		{TotalMs: 60000, Reminders: []Reminder{{AtMs: 1000, Text: "x"}, {AtMs: 1000, Text: "y"}}},
		{TotalMs: 60000, Reminders: []Reminder{{AtMs: 1000, Text: "x", DurationMs: 1000}}},
		{TotalMs: 60000, Title: "一二三四五六七八九十一二三四五六七八九十一二三四五六七八九十一二三四五六七八九十一"},
	}
	for i, c := range bad {
		var ve *ValidationError
		if err := c.Normalize(); !errors.As(err, &ve) {
			t.Errorf("case %d: err = %v", i, err)
		}
	}
	good := Config{TotalMs: 60000, Reminders: []Reminder{{AtMs: 0, Text: "b"}, {AtMs: 30000, Text: "a"}}}
	if err := good.Normalize(); err != nil {
		t.Fatal(err)
	}
	if good.OnExpire != Stop || good.Reminders[0].AtMs != 30000 || good.Reminders[0].ID == "" || good.Reminders[0].DurationMs != 8000 {
		t.Fatalf("%+v", good)
	}
}

func TestRestore(t *testing.T) {
	c := cfg(10*time.Minute,
		Reminder{AtMs: ms(8 * time.Minute), Text: "a"},
		Reminder{AtMs: ms(3 * time.Minute), Text: "b"},
	)
	tm := started(c)
	p := tm.Persist()

	// Down for 4 minutes: 6m left, reminder "a" was crossed and must not replay.
	r := Restore(p, at(4*time.Minute))
	if r.Status() != Running || r.Remaining(at(4*time.Minute)) != 6*time.Minute {
		t.Fatalf("running restore: %v %v", r.Status(), r.Remaining(at(4*time.Minute)))
	}
	if r.Seq() != p.Seq+1 {
		t.Fatal("seq not bumped")
	}
	if f, _ := r.Advance(at(4 * time.Minute)); len(f) != 0 {
		t.Fatalf("replayed %+v", f)
	}
	if f, _ := r.Advance(at(7 * time.Minute)); len(f) != 1 || f[0].Text != "b" {
		t.Fatalf("fired %+v", f)
	}

	// Down past the end: comes back expired.
	r = Restore(p, at(15*time.Minute))
	if r.Status() != Expired {
		t.Fatalf("status = %v", r.Status())
	}

	tm.Pause(at(time.Minute))
	r = Restore(tm.Persist(), at(time.Hour))
	if r.Status() != Paused || r.Remaining(at(time.Hour)) != 9*time.Minute {
		t.Fatal("paused restore")
	}

	oc := cfg(time.Minute)
	oc.OnExpire = Overtime
	tm = started(oc)
	tm.Advance(at(2 * time.Minute))
	r = Restore(tm.Persist(), at(3*time.Minute))
	if got := r.OvertimeAt(at(3 * time.Minute)); got != 2*time.Minute {
		t.Fatalf("overtime after restore = %v", got)
	}
}

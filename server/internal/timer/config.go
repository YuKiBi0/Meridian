package timer

import (
	"crypto/rand"
	"encoding/base32"
	"fmt"
	"sort"
	"strings"
	"time"
	"unicode/utf8"
)

// Status is the lifecycle state of the single countdown.
type Status string

const (
	Idle    Status = "idle"
	Running Status = "running"
	Paused  Status = "paused"
	Expired Status = "expired"
)

// OnExpire decides what happens when remaining reaches zero.
type OnExpire string

const (
	Stop     OnExpire = "stop"
	Overtime OnExpire = "overtime"
)

// ExtendMode selects which quantities an extension adds to.
type ExtendMode string

const (
	ExtendRemaining ExtendMode = "remaining"
	ExtendTotal     ExtendMode = "total"
)

// Limits from PRD §5.6.
const (
	MinTotal           = time.Second
	MaxTotal           = 24 * time.Hour
	MaxTitleLen        = 40
	MaxReminders       = 20
	MaxReminderTextLen = 80
	MinReminderShow    = 3 * time.Second
	MaxReminderShow    = 60 * time.Second
	DefaultReminder    = 8 * time.Second
	MinExtend          = time.Second
	MaxExtend          = 24 * time.Hour
)

// Reminder fires once per run when remaining drops to AtMs.
type Reminder struct {
	ID         string `json:"id"`
	AtMs       int64  `json:"at_ms"`
	Text       string `json:"text"`
	DurationMs int64  `json:"duration_ms"`
	Sticky     bool   `json:"sticky"`
}

// Config describes one run of the countdown.
type Config struct {
	Title     string     `json:"title"`
	TotalMs   int64      `json:"total_ms"`
	OnExpire  OnExpire   `json:"on_expire"`
	Reminders []Reminder `json:"reminders"`
}

// ValidationError is returned when input breaks a PRD constraint.
type ValidationError struct{ Msg string }

func (e *ValidationError) Error() string { return e.Msg }

func invalid(format string, a ...any) error {
	return &ValidationError{Msg: fmt.Sprintf(format, a...)}
}

// Normalize validates c, fills defaults and sorts reminders by AtMs descending
// (the order in which they fire).
func (c *Config) Normalize() error {
	c.Title = strings.TrimSpace(c.Title)
	if utf8.RuneCountInString(c.Title) > MaxTitleLen {
		return invalid("标题最多 %d 字", MaxTitleLen)
	}
	total := time.Duration(c.TotalMs) * time.Millisecond
	if total < MinTotal || total > MaxTotal {
		return invalid("总时长需在 1 秒到 24 小时之间")
	}
	switch c.OnExpire {
	case "":
		c.OnExpire = Stop
	case Stop, Overtime:
	default:
		return invalid("on_expire 只能是 stop 或 overtime")
	}
	return normalizeReminders(&c.Reminders, c.TotalMs)
}

// normalizeReminders validates rs against a run of totalMs, fills defaults
// and sorts them by AtMs descending (the order in which they fire).
func normalizeReminders(rs *[]Reminder, totalMs int64) error {
	if len(*rs) > MaxReminders {
		return invalid("提醒最多 %d 个", MaxReminders)
	}
	if *rs == nil {
		*rs = []Reminder{}
	}
	seen := map[int64]bool{}
	ids := map[string]bool{}
	for i := range *rs {
		r := &(*rs)[i]
		r.Text = strings.TrimSpace(r.Text)
		if n := utf8.RuneCountInString(r.Text); n == 0 || n > MaxReminderTextLen {
			return invalid("提示内容需为 1 到 %d 字", MaxReminderTextLen)
		}
		if strings.Count(r.Text, "\n") > 1 {
			return invalid("提示内容最多 2 行")
		}
		if r.AtMs < 0 || r.AtMs >= totalMs {
			return invalid("提醒时间需小于总时长")
		}
		if seen[r.AtMs] {
			return invalid("同一时间点只能有一个提醒")
		}
		seen[r.AtMs] = true
		if r.Sticky {
			r.DurationMs = 0
		} else {
			if r.DurationMs == 0 {
				r.DurationMs = DefaultReminder.Milliseconds()
			}
			d := time.Duration(r.DurationMs) * time.Millisecond
			if d < MinReminderShow || d > MaxReminderShow {
				return invalid("提醒显示时长需在 3 到 60 秒之间")
			}
		}
		if r.ID == "" || ids[r.ID] {
			r.ID = NewID("m_")
		}
		ids[r.ID] = true
	}
	sort.SliceStable(*rs, func(i, j int) bool {
		return (*rs)[i].AtMs > (*rs)[j].AtMs
	})
	return nil
}

var idEncoding = base32.NewEncoding("0123456789abcdefghjkmnpqrstvwxyz").WithPadding(base32.NoPadding)

// NewID returns prefix followed by 16 random lowercase characters.
func NewID(prefix string) string {
	b := make([]byte, 10)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return prefix + idEncoding.EncodeToString(b)
}

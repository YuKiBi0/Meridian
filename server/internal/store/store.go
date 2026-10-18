// Package store persists presets, the current timer and the operation log
// in PostgreSQL.
package store

import (
	"context"
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/YuKiBi0/Meridian/server/internal/timer"
)

//go:embed migrations/*.sql
var migrations embed.FS

var ErrNotFound = errors.New("not found")

const (
	MaxPresets = 100
	keepLogs   = 1000
)

type Store struct {
	pool *pgxpool.Pool
}

// Open connects and applies pending migrations.
func Open(ctx context.Context, url string) (*Store, error) {
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		return nil, err
	}
	s := &Store{pool: pool}
	if err := s.migrate(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("migrate: %w", err)
	}
	return s, nil
}

func (s *Store) Close() { s.pool.Close() }

func (s *Store) Ping(ctx context.Context) error { return s.pool.Ping(ctx) }

func (s *Store) migrate(ctx context.Context) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	// Serialize concurrent starts.
	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(4242)`); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations (
		version INT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())`); err != nil {
		return err
	}
	names, err := fs.Glob(migrations, "migrations/*.sql")
	if err != nil {
		return err
	}
	sort.Strings(names)
	for _, name := range names {
		base := strings.TrimPrefix(name, "migrations/")
		version, err := strconv.Atoi(strings.SplitN(base, "_", 2)[0])
		if err != nil {
			return fmt.Errorf("bad migration name %s", base)
		}
		var done bool
		if err := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM schema_migrations WHERE version=$1)`, version).Scan(&done); err != nil {
			return err
		}
		if done {
			continue
		}
		sql, err := migrations.ReadFile(name)
		if err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, string(sql)); err != nil {
			return fmt.Errorf("%s: %w", base, err)
		}
		if _, err := tx.Exec(ctx, `INSERT INTO schema_migrations (version) VALUES ($1)`, version); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

// ---- timer ----

// LoadTimer returns the persisted timer, or ok=false on first start.
func (s *Store) LoadTimer(ctx context.Context) (p timer.Persisted, ok bool, err error) {
	var runID *string
	var reminders, fired []byte
	err = s.pool.QueryRow(ctx, `SELECT seq, run_id, status, title, total_ms, remaining_ms,
		ends_at, expired_at, on_expire, reminders, fired FROM timer_state WHERE id = 1`).Scan(
		&p.Seq, &runID, &p.Status, &p.Title, &p.TotalMs, &p.RemainingMs,
		&p.EndsAt, &p.ExpiredAt, &p.OnExpire, &reminders, &fired)
	if errors.Is(err, pgx.ErrNoRows) {
		return p, false, nil
	}
	if err != nil {
		return p, false, err
	}
	if runID != nil {
		p.RunID = *runID
	}
	if err := json.Unmarshal(reminders, &p.Reminders); err != nil {
		return p, false, err
	}
	if err := json.Unmarshal(fired, &p.Fired); err != nil {
		return p, false, err
	}
	return p, true, nil
}

func (s *Store) SaveTimer(ctx context.Context, p timer.Persisted) error {
	reminders, _ := json.Marshal(p.Reminders)
	fired, _ := json.Marshal(p.Fired)
	var runID *string
	if p.RunID != "" {
		runID = &p.RunID
	}
	_, err := s.pool.Exec(ctx, `INSERT INTO timer_state (id, seq, run_id, status, title, total_ms,
		remaining_ms, ends_at, expired_at, on_expire, reminders, fired, updated_at)
		VALUES (1, $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, now())
		ON CONFLICT (id) DO UPDATE SET seq=$1, run_id=$2, status=$3, title=$4, total_ms=$5,
		remaining_ms=$6, ends_at=$7, expired_at=$8, on_expire=$9, reminders=$10, fired=$11, updated_at=now()`,
		p.Seq, runID, p.Status, p.Title, p.TotalMs, p.RemainingMs, p.EndsAt, p.ExpiredAt,
		p.OnExpire, reminders, fired)
	return err
}

// ---- presets ----

// Preset is a reusable configuration. The embedded Config flattens into
// the JSON object (title, total_ms, on_expire, reminders).
type Preset struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	timer.Config
}

const presetCols = `id, name, title, total_ms, on_expire, reminders`

func scanPreset(row pgx.Row) (Preset, error) {
	var p Preset
	var reminders []byte
	err := row.Scan(&p.ID, &p.Name, &p.Title, &p.TotalMs, &p.OnExpire, &reminders)
	if errors.Is(err, pgx.ErrNoRows) {
		return p, ErrNotFound
	}
	if err != nil {
		return p, err
	}
	err = json.Unmarshal(reminders, &p.Reminders)
	return p, err
}

func (s *Store) ListPresets(ctx context.Context) ([]Preset, error) {
	rows, err := s.pool.Query(ctx, `SELECT `+presetCols+` FROM presets ORDER BY sort, created_at`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Preset{}
	for rows.Next() {
		p, err := scanPreset(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

func (s *Store) GetPreset(ctx context.Context, id string) (Preset, error) {
	return scanPreset(s.pool.QueryRow(ctx, `SELECT `+presetCols+` FROM presets WHERE id = $1`, id))
}

// ErrTooMany is returned when the preset limit is reached.
var ErrTooMany = errors.New("too many presets")

func (s *Store) CreatePreset(ctx context.Context, p Preset) (Preset, error) {
	var n int
	if err := s.pool.QueryRow(ctx, `SELECT count(*) FROM presets`).Scan(&n); err != nil {
		return p, err
	}
	if n >= MaxPresets {
		return p, ErrTooMany
	}
	p.ID = timer.NewID("p_")
	reminders, _ := json.Marshal(p.Reminders)
	_, err := s.pool.Exec(ctx, `INSERT INTO presets (id, name, title, total_ms, on_expire, reminders, sort)
		VALUES ($1, $2, $3, $4, $5, $6, (SELECT COALESCE(MAX(sort), 0) + 1 FROM presets))`,
		p.ID, p.Name, p.Title, p.TotalMs, p.OnExpire, reminders)
	return p, err
}

func (s *Store) UpdatePreset(ctx context.Context, p Preset) (Preset, error) {
	reminders, _ := json.Marshal(p.Reminders)
	tag, err := s.pool.Exec(ctx, `UPDATE presets SET name=$2, title=$3, total_ms=$4, on_expire=$5,
		reminders=$6, updated_at=now() WHERE id=$1`,
		p.ID, p.Name, p.Title, p.TotalMs, p.OnExpire, reminders)
	if err == nil && tag.RowsAffected() == 0 {
		err = ErrNotFound
	}
	return p, err
}

func (s *Store) DeletePreset(ctx context.Context, id string) error {
	tag, err := s.pool.Exec(ctx, `DELETE FROM presets WHERE id = $1`, id)
	if err == nil && tag.RowsAffected() == 0 {
		err = ErrNotFound
	}
	return err
}

// ReorderPresets sets sort by position in ids. Unknown ids are ignored.
func (s *Store) ReorderPresets(ctx context.Context, ids []string) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	for i, id := range ids {
		if _, err := tx.Exec(ctx, `UPDATE presets SET sort=$2 WHERE id=$1`, id, i+1); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

// ---- operation log ----

type LogEntry struct {
	ID       int64           `json:"id"`
	At       time.Time       `json:"at"`
	Action   string          `json:"action"`
	Params   json.RawMessage `json:"params"`
	SeqAfter *int64          `json:"seq_after"`
	RemoteIP string          `json:"remote_ip"`
}

func (s *Store) AddLog(ctx context.Context, action string, params any, seqAfter *int64, ip string) error {
	if params == nil {
		params = map[string]any{}
	}
	b, err := json.Marshal(params)
	if err != nil {
		return err
	}
	if _, err := s.pool.Exec(ctx, `INSERT INTO op_logs (action, params, seq_after, remote_ip)
		VALUES ($1, $2, $3, $4)`, action, b, seqAfter, ip); err != nil {
		return err
	}
	_, err = s.pool.Exec(ctx, `DELETE FROM op_logs WHERE id <= (SELECT id FROM op_logs ORDER BY id DESC OFFSET $1 LIMIT 1)`, keepLogs)
	return err
}

func (s *Store) ListLogs(ctx context.Context, limit int) ([]LogEntry, error) {
	rows, err := s.pool.Query(ctx, `SELECT id, at, action, params, seq_after, COALESCE(remote_ip, '')
		FROM op_logs ORDER BY id DESC LIMIT $1`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []LogEntry{}
	for rows.Next() {
		var e LogEntry
		if err := rows.Scan(&e.ID, &e.At, &e.Action, &e.Params, &e.SeqAfter, &e.RemoteIP); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

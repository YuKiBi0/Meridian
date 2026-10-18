// Package store persists rooms with their timers, presets and the operation
// log in PostgreSQL.
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
	"github.com/jackc/pgx/v5/pgconn"
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

// ---- rooms ----

// Room is a stored room with the durable form of its countdown, if any.
type Room struct {
	ID        string
	Name      string
	CreatedAt time.Time
	Timer     *timer.Persisted
}

// ListRooms returns every room with its timer, oldest first.
func (s *Store) ListRooms(ctx context.Context) ([]Room, error) {
	rows, err := s.pool.Query(ctx, `SELECT r.id::text, r.name, r.created_at, t.seq, t.run_id, t.status, t.title,
		t.total_ms, t.remaining_ms, t.ends_at, t.expired_at, t.on_expire, t.reminders, t.fired
		FROM rooms r LEFT JOIN room_timers t ON t.room_id = r.id ORDER BY r.created_at, r.id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Room{}
	for rows.Next() {
		var r Room
		var seq, totalMs, remainingMs *int64
		var runID, status, title, onExpire *string
		var reminders, fired []byte
		var endsAt, expiredAt *time.Time
		if err := rows.Scan(&r.ID, &r.Name, &r.CreatedAt, &seq, &runID, &status, &title,
			&totalMs, &remainingMs, &endsAt, &expiredAt, &onExpire, &reminders, &fired); err != nil {
			return nil, err
		}
		if seq != nil {
			p := timer.Persisted{Seq: *seq, Status: timer.Status(*status), Title: *title, TotalMs: *totalMs,
				RemainingMs: *remainingMs, EndsAt: endsAt, ExpiredAt: expiredAt, OnExpire: timer.OnExpire(*onExpire)}
			if runID != nil {
				p.RunID = *runID
			}
			if err := json.Unmarshal(reminders, &p.Reminders); err != nil {
				return nil, err
			}
			if err := json.Unmarshal(fired, &p.Fired); err != nil {
				return nil, err
			}
			r.Timer = &p
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

func (s *Store) CreateRoom(ctx context.Context, id, name string) (time.Time, error) {
	var at time.Time
	err := s.pool.QueryRow(ctx, `INSERT INTO rooms (id, name) VALUES ($1, $2) RETURNING created_at`, id, name).Scan(&at)
	return at, err
}

func (s *Store) RenameRoom(ctx context.Context, id, name string) error {
	tag, err := s.pool.Exec(ctx, `UPDATE rooms SET name=$2, updated_at=now() WHERE id=$1`, id, name)
	if err == nil && tag.RowsAffected() == 0 {
		err = ErrNotFound
	}
	return err
}

// DeleteRoom removes the room and, by cascade, its timer.
func (s *Store) DeleteRoom(ctx context.Context, id string) error {
	tag, err := s.pool.Exec(ctx, `DELETE FROM rooms WHERE id = $1`, id)
	if err == nil && tag.RowsAffected() == 0 {
		err = ErrNotFound
	}
	return err
}

// SaveTimer stores the timer of room. It does nothing once the room has
// been deleted, so a late background write cannot fail forever.
func (s *Store) SaveTimer(ctx context.Context, room string, p timer.Persisted) error {
	reminders, _ := json.Marshal(p.Reminders)
	fired, _ := json.Marshal(p.Fired)
	var runID *string
	if p.RunID != "" {
		runID = &p.RunID
	}
	_, err := s.pool.Exec(ctx, `INSERT INTO room_timers (room_id, seq, run_id, status, title, total_ms,
		remaining_ms, ends_at, expired_at, on_expire, reminders, fired, updated_at)
		SELECT $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, now()
		WHERE EXISTS (SELECT 1 FROM rooms WHERE id = $1)
		ON CONFLICT (room_id) DO UPDATE SET seq=$2, run_id=$3, status=$4, title=$5, total_ms=$6,
		remaining_ms=$7, ends_at=$8, expired_at=$9, on_expire=$10, reminders=$11, fired=$12, updated_at=now()`,
		room, p.Seq, runID, p.Status, p.Title, p.TotalMs, p.RemainingMs, p.EndsAt, p.ExpiredAt,
		p.OnExpire, reminders, fired)
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23503" {
		return nil // the room was deleted between the check and the insert
	}
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
	// RoomID is set for room operations; RoomName is the room's current
	// name, empty once it has been deleted.
	RoomID   *string `json:"room_id"`
	RoomName string  `json:"room_name"`
}

// AddLog records an operation. room is "" for operations outside a room.
func (s *Store) AddLog(ctx context.Context, room, action string, params any, seqAfter *int64, ip string) error {
	if params == nil {
		params = map[string]any{}
	}
	b, err := json.Marshal(params)
	if err != nil {
		return err
	}
	var roomID *string
	if room != "" {
		roomID = &room
	}
	if _, err := s.pool.Exec(ctx, `INSERT INTO op_logs (action, params, seq_after, remote_ip, room_id)
		VALUES ($1, $2, $3, $4, $5)`, action, b, seqAfter, ip, roomID); err != nil {
		return err
	}
	_, err = s.pool.Exec(ctx, `DELETE FROM op_logs WHERE id <= (SELECT id FROM op_logs ORDER BY id DESC OFFSET $1 LIMIT 1)`, keepLogs)
	return err
}

func (s *Store) ListLogs(ctx context.Context, limit int) ([]LogEntry, error) {
	rows, err := s.pool.Query(ctx, `SELECT l.id, l.at, l.action, l.params, l.seq_after, COALESCE(l.remote_ip, ''),
		l.room_id::text, COALESCE(r.name, '')
		FROM op_logs l LEFT JOIN rooms r ON r.id = l.room_id ORDER BY l.id DESC LIMIT $1`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []LogEntry{}
	for rows.Next() {
		var e LogEntry
		if err := rows.Scan(&e.ID, &e.At, &e.Action, &e.Params, &e.SeqAfter, &e.RemoteIP, &e.RoomID, &e.RoomName); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

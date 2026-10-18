-- Rooms: each one runs its own countdown (PRD §4, §10).
CREATE TABLE rooms (
  id          UUID PRIMARY KEY,
  name        TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE room_timers (
  room_id       UUID PRIMARY KEY REFERENCES rooms (id) ON DELETE CASCADE,
  seq           BIGINT NOT NULL,
  run_id        TEXT,
  status        TEXT NOT NULL,
  title         TEXT NOT NULL DEFAULT '',
  total_ms      BIGINT NOT NULL DEFAULT 0,
  remaining_ms  BIGINT NOT NULL DEFAULT 0,
  ends_at       TIMESTAMPTZ,
  expired_at    TIMESTAMPTZ,
  on_expire     TEXT NOT NULL DEFAULT 'stop',
  reminders     JSONB NOT NULL DEFAULT '[]',
  fired         JSONB NOT NULL DEFAULT '[]',
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The single 1.0 countdown becomes the first room, so a run in progress
-- survives the upgrade. The id is a UUIDv7 built from the current time.
WITH legacy AS (
  INSERT INTO rooms (id, name)
  SELECT encode(set_bit(set_bit(overlay(uuid_send(gen_random_uuid())
           PLACING substring(int8send(floor(extract(epoch FROM clock_timestamp()) * 1000)::bigint) FROM 3)
           FROM 1 FOR 6), 52, 1), 53, 1), 'hex')::uuid,
         '默认房间'
  FROM timer_state WHERE id = 1
  RETURNING id
)
INSERT INTO room_timers (room_id, seq, run_id, status, title, total_ms, remaining_ms,
  ends_at, expired_at, on_expire, reminders, fired)
SELECT legacy.id, t.seq, t.run_id, t.status, t.title, t.total_ms, t.remaining_ms,
  t.ends_at, t.expired_at, t.on_expire, t.reminders, t.fired
FROM legacy, timer_state t WHERE t.id = 1;

DROP TABLE timer_state;

-- Room operations are logged with their room; rooms may be deleted later,
-- so this is not a foreign key.
ALTER TABLE op_logs ADD COLUMN room_id UUID;

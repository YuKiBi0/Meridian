CREATE TABLE presets (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  title       TEXT NOT NULL DEFAULT '',
  total_ms    BIGINT NOT NULL CHECK (total_ms BETWEEN 1000 AND 86400000),
  on_expire   TEXT NOT NULL DEFAULT 'stop' CHECK (on_expire IN ('stop', 'overtime')),
  reminders   JSONB NOT NULL DEFAULT '[]',
  sort        INT NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE timer_state (
  id            INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
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

CREATE TABLE op_logs (
  id         BIGSERIAL PRIMARY KEY,
  at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  action     TEXT NOT NULL,
  params     JSONB NOT NULL DEFAULT '{}',
  seq_after  BIGINT,
  remote_ip  TEXT
);

CREATE INDEX op_logs_at_idx ON op_logs (at DESC);

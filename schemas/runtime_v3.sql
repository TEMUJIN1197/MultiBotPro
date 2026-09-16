PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA busy_timeout=5000;

-- Documentation copy of the runtime v3 schema used by hedgeBridge.mqh and
-- PythonApp/init_database.py. Keep table names aligned with the active bridge:
-- signals, proposals, replies, feedback, state_master, state_slave, events,
-- debt_ledger, and shadow_params.

CREATE TABLE IF NOT EXISTS signals (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  channel TEXT NOT NULL,
  ticket INTEGER,
  symbol TEXT,
  action INTEGER,
  type INTEGER NOT NULL DEFAULT 0,
  lots REAL,
  sl_dist_points REAL,
  tp_dist_points REAL,
  risk_money REAL,
  payload_json TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  processed INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS proposals (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  channel TEXT NOT NULL,
  request_id TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  state TEXT NOT NULL DEFAULT 'PENDING',
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT
);

CREATE TABLE IF NOT EXISTS replies (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  channel TEXT NOT NULL,
  request_id TEXT NOT NULL,
  action INTEGER NOT NULL,
  payload_json TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS feedback (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  channel TEXT NOT NULL,
  master_ticket INTEGER,
  action INTEGER NOT NULL,
  note TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  consumed INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS state_master (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  channel TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS state_slave (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  channel TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  channel TEXT NOT NULL,
  event_type TEXT NOT NULL,
  payload_json TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS debt_ledger (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  channel TEXT NOT NULL,
  symbol TEXT NOT NULL,
  event_type TEXT NOT NULL,
  delta_amount REAL NOT NULL,
  pruning_balance REAL NOT NULL,
  critical_balance REAL NOT NULL,
  metadata_json TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS shadow_params (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  symbol TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  score REAL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_signals_channel_processed ON signals(channel, processed, id);
CREATE INDEX IF NOT EXISTS idx_proposals_channel_state ON proposals(channel, state, id);
CREATE INDEX IF NOT EXISTS idx_replies_channel_request ON replies(channel, request_id, id);
CREATE INDEX IF NOT EXISTS idx_feedback_channel_consumed ON feedback(channel, consumed, id);
CREATE INDEX IF NOT EXISTS idx_state_master_channel ON state_master(channel, id);
CREATE INDEX IF NOT EXISTS idx_state_slave_channel ON state_slave(channel, id);
CREATE INDEX IF NOT EXISTS idx_events_channel ON events(channel, id);
CREATE INDEX IF NOT EXISTS idx_debt_ledger_channel ON debt_ledger(channel, id);
CREATE INDEX IF NOT EXISTS idx_shadow_params_symbol ON shadow_params(symbol, updated_at);

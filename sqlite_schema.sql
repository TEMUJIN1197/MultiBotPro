-- MultiBotPro v3 SQLite runtime schema
-- Shared by the MQL5 master/slave bridge and Python runtime.

PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;

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
CREATE INDEX IF NOT EXISTS idx_signals_channel_processed
    ON signals(channel, processed, id);

CREATE TABLE IF NOT EXISTS proposals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    channel TEXT NOT NULL,
    request_id TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    state TEXT NOT NULL DEFAULT 'PENDING',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_proposals_channel_state
    ON proposals(channel, state, id);

CREATE TABLE IF NOT EXISTS replies (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    channel TEXT NOT NULL,
    request_id TEXT NOT NULL,
    action INTEGER NOT NULL,
    payload_json TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_replies_channel_request
    ON replies(channel, request_id, id);

CREATE TABLE IF NOT EXISTS feedback (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    channel TEXT NOT NULL,
    master_ticket INTEGER,
    action INTEGER NOT NULL,
    note TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    consumed INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_feedback_channel_consumed
    ON feedback(channel, consumed, id);

CREATE TABLE IF NOT EXISTS state_master (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    channel TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_state_master_channel ON state_master(channel, id);

CREATE TABLE IF NOT EXISTS state_slave (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    channel TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_state_slave_channel ON state_slave(channel, id);

CREATE TABLE IF NOT EXISTS events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    channel TEXT NOT NULL,
    event_type TEXT NOT NULL,
    payload_json TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_events_channel ON events(channel, id);

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
CREATE INDEX IF NOT EXISTS idx_debt_ledger_channel ON debt_ledger(channel, id);

CREATE TABLE IF NOT EXISTS shadow_params (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    symbol TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    score REAL,
    updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_shadow_params_symbol ON shadow_params(symbol, updated_at);

CREATE TABLE IF NOT EXISTS worker_status (
    channel TEXT NOT NULL,
    symbol TEXT NOT NULL,
    chart_id TEXT NOT NULL,
    chart_id_hi INTEGER NOT NULL DEFAULT 0,
    chart_id_lo INTEGER NOT NULL DEFAULT 0,
    chart_symbol TEXT,
    symbols_csv TEXT,
    assignment_signature TEXT,
    state TEXT NOT NULL,
    linked_positions INTEGER NOT NULL DEFAULT 0,
    heartbeat INTEGER NOT NULL,
    updated_at TEXT NOT NULL,
    PRIMARY KEY(channel, symbol)
);
CREATE INDEX IF NOT EXISTS idx_worker_status_channel_symbol
    ON worker_status(channel, symbol);
CREATE INDEX IF NOT EXISTS idx_worker_status_channel_updated
    ON worker_status(channel, updated_at);

CREATE TABLE IF NOT EXISTS system_state (
    key TEXT PRIMARY KEY,
    value TEXT,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);
INSERT OR IGNORE INTO system_state(key, value) VALUES ('version', '3.0');
INSERT OR IGNORE INTO system_state(key, value) VALUES ('engine_status', 'READY');

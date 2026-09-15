-- MultiBotPro v1.0 SQLite Schema
-- This database handles the bridge between MQL5 and Python AI engines

CREATE TABLE IF NOT EXISTS system_state (
    key TEXT PRIMARY KEY,
    value TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS signal_queue (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    symbol TEXT NOT NULL,
    action INTEGER NOT NULL, -- 1: Open, 2: Close, 3: Modify
    type INTEGER, -- 0: Buy, 1: Sell
    lots REAL,
    ticket INTEGER,
    comment TEXT,
    status TEXT DEFAULT 'PENDING', -- PENDING, COMPLETED, FAILED
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS trade_ledger (
    ticket INTEGER PRIMARY KEY,
    symbol TEXT,
    entry_price REAL,
    exit_price REAL,
    profit REAL,
    closed_at TIMESTAMP
);

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

INSERT OR IGNORE INTO system_state (key, value) VALUES ('version', '1.0');
INSERT OR IGNORE INTO system_state (key, value) VALUES ('engine_status', 'READY');

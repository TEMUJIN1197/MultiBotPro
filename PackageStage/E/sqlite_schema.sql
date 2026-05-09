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

INSERT OR IGNORE INTO system_state (key, value) VALUES ('version', '1.0');
INSERT OR IGNORE INTO system_state (key, value) VALUES ('engine_status', 'READY');

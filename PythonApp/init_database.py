import sqlite3
import sys
import os

SCHEMA = """
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA busy_timeout=5000;

CREATE TABLE IF NOT EXISTS signals (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  channel TEXT NOT NULL,
  ticket INTEGER,
  symbol TEXT,
  action INTEGER,
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

CREATE TABLE IF NOT EXISTS events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  channel TEXT NOT NULL,
  event_type TEXT NOT NULL,
  payload_json TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_signals_channel_processed ON signals(channel, processed);
CREATE INDEX IF NOT EXISTS idx_proposals_channel_state ON proposals(channel, state);
CREATE INDEX IF NOT EXISTS idx_feedback_channel_consumed ON feedback(channel, consumed);
CREATE INDEX IF NOT EXISTS idx_events_channel_type ON events(channel, event_type);

CREATE TABLE IF NOT EXISTS shadow_params (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  symbol TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  score REAL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_shadow_params_symbol_updated ON shadow_params(symbol, updated_at);
"""

def main():
    if len(sys.argv) < 2:
        print("Usage: init_database.exe <Target MQL5 Files Directory>")
        return 1
        
    target_dir = sys.argv[1]
    if not os.path.isdir(target_dir):
        print(f"Directory not found: {target_dir}")
        print("Attempting to create directory...")
        try:
            os.makedirs(target_dir, exist_ok=True)
        except Exception as e:
            print(f"Failed to create directory: {e}")
            return 1
            
    db_path = os.path.join(target_dir, "MultiBotPro_v3.db")
    print(f"Initializing database at: {db_path}")
    
    try:
        conn = sqlite3.connect(db_path)
        conn.executescript(SCHEMA)
        conn.commit()
        conn.close()
        print("Database initialized successfully.")
        return 0
    except Exception as e:
        print(f"Error initializing SQLite database: {e}")
        return 1

if __name__ == "__main__":
    sys.exit(main())

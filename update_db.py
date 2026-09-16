import sqlite3
import os

db_path = os.path.join(os.environ['APPDATA'], 'MetaQuotes', 'Terminal', 'Common', 'Files', 'MultiBotPro_v3.db')
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Get existing tables
cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
tables = [row[0] for row in cursor.fetchall()]
print("Current tables:", tables)

# Create worker_status table if not exists
schema = """
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
CREATE INDEX IF NOT EXISTS idx_worker_status_channel_symbol ON worker_status(channel, symbol);
CREATE INDEX IF NOT EXISTS idx_worker_status_channel_updated ON worker_status(channel, updated_at);
"""

cursor.executescript(schema)
conn.commit()

cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
tables_after = [row[0] for row in cursor.fetchall()]
print("Tables after update:", tables_after)

conn.close()

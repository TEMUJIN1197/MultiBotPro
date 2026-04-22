import json
import os
import sqlite3
from datetime import datetime
from typing import Any, Dict, Iterable

from flask import Flask, jsonify, render_template_string, request


def load_runtime_config(path: str = "") -> Dict[str, Any]:
    cfg_path = path or os.getenv("MBP_RUNTIME_PATH", "runtime_v3.json")
    if not cfg_path or not os.path.exists(cfg_path):
        return {}
    try:
        with open(cfg_path, "r", encoding="utf-8") as f:
            data = json.load(f)
            return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def cfg_get(cfg: Dict[str, Any], keys: Iterable[str], default: Any = None) -> Any:
    node: Any = cfg
    for k in keys:
        if not isinstance(node, dict) or k not in node:
            return default
        node = node[k]
    return node


CFG = load_runtime_config()
DB_PATH = os.getenv("MBP_V3_DB", cfg_get(CFG, ["sqlite_path"], "MultiBotPro_v3.db"))
CHANNEL = os.getenv("MBP_V3_CHANNEL", cfg_get(CFG, ["channel"], "HEDGE_A"))
HOST = os.getenv("MBP_V3_DASH_HOST", cfg_get(CFG, ["dashboard", "host"], "127.0.0.1"))
PORT = int(os.getenv("MBP_V3_DASH_PORT", cfg_get(CFG, ["dashboard", "port"], 5073)))
MAX_EVENTS = int(os.getenv("MBP_V3_DASH_MAX_EVENTS", cfg_get(CFG, ["dashboard", "max_events"], 30)))
MAX_DEBT_ROWS = int(os.getenv("MBP_V3_DASH_MAX_DEBT", cfg_get(CFG, ["dashboard", "max_debt_rows"], 200)))

app = Flask(__name__)


def query_rows(sql: str, args=()):
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        rows = conn.execute(sql, args).fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


def query_scalar(sql: str, args=(), default=0):
    conn = sqlite3.connect(DB_PATH)
    try:
        row = conn.execute(sql, args).fetchone()
        if row is None:
            return default
        return row[0]
    finally:
        conn.close()


def get_last_event(event_type: str):
    rows = query_rows(
        "SELECT created_at FROM events WHERE channel=? AND event_type=? ORDER BY id DESC LIMIT 1",
        (CHANNEL, event_type),
    )
    return rows[0]["created_at"] if rows else None


@app.get("/api/health")
def health():
    limit = int(request.args.get("limit", MAX_EVENTS))
    events = query_rows(
        "SELECT created_at, event_type FROM events WHERE channel=? ORDER BY id DESC LIMIT ?",
        (CHANNEL, limit),
    )
    return jsonify({"db": DB_PATH, "channel": CHANNEL, "now": datetime.utcnow().isoformat() + "Z", "recent": events})


@app.get("/api/debt")
def debt():
    limit = int(request.args.get("limit", MAX_DEBT_ROWS))
    rows = query_rows(
        "SELECT symbol, event_type, delta_amount, pruning_balance, critical_balance, created_at FROM debt_ledger WHERE channel=? ORDER BY id DESC LIMIT ?",
        (CHANNEL, limit),
    )
    return jsonify(rows)


@app.get("/api/summary")
def summary():
    return jsonify(
        {
            "db": DB_PATH,
            "channel": CHANNEL,
            "last_heartbeat": get_last_event("heartbeat"),
            "pending_proposals": query_scalar(
                "SELECT COUNT(*) FROM proposals WHERE channel=? AND state='PENDING'", (CHANNEL,)
            ),
            "unconsumed_feedback": query_scalar(
                "SELECT COUNT(*) FROM feedback WHERE channel=? AND consumed=0", (CHANNEL,)
            ),
            "signals_unprocessed": query_scalar(
                "SELECT COUNT(*) FROM signals WHERE channel=? AND processed=0", (CHANNEL,)
            ),
        }
    )


@app.get("/")
def index():
    events = query_rows(
        "SELECT event_type, payload_json, created_at FROM events WHERE channel=? ORDER BY id DESC LIMIT ?",
        (CHANNEL, MAX_EVENTS),
    )
    rows = []
    for e in events:
        payload = {}
        try:
            payload = json.loads(e.get("payload_json") or "{}")
        except Exception:
            payload = {"raw": e.get("payload_json", "")}
        rows.append({"event": e["event_type"], "created_at": e["created_at"], "payload": payload})

    summary_data = {
        "last_heartbeat": get_last_event("heartbeat"),
        "pending_proposals": query_scalar(
            "SELECT COUNT(*) FROM proposals WHERE channel=? AND state='PENDING'", (CHANNEL,)
        ),
        "unconsumed_feedback": query_scalar(
            "SELECT COUNT(*) FROM feedback WHERE channel=? AND consumed=0", (CHANNEL,)
        ),
        "signals_unprocessed": query_scalar(
            "SELECT COUNT(*) FROM signals WHERE channel=? AND processed=0", (CHANNEL,)
        ),
    }

    html = """
    <html>
    <head>
      <title>MultiBotPro V3 Dashboard</title>
      <style>
        body { font-family: Arial, sans-serif; margin: 20px; background:#f8fafc; color:#0f172a; }
        .card { background:white; border:1px solid #dbeafe; border-radius:10px; padding:16px; margin-bottom:16px; }
        code { background:#eff6ff; padding:2px 6px; border-radius:6px; }
        table { width:100%; border-collapse: collapse; }
        th, td { border-bottom:1px solid #e2e8f0; padding:8px; text-align:left; vertical-align: top; }
      </style>
    </head>
    <body>
      <h2>MultiBotPro V3 Dashboard</h2>
      <div class="card">
        <div><strong>DB:</strong> <code>{{db}}</code></div>
        <div><strong>Channel:</strong> <code>{{channel}}</code></div>
      </div>
      <div class="card">
        <h3>Summary</h3>
        <div><strong>Last Heartbeat:</strong> <code>{{summary.last_heartbeat or "--"}}</code></div>
        <div><strong>Pending Proposals:</strong> <code>{{summary.pending_proposals}}</code></div>
        <div><strong>Unconsumed Feedback:</strong> <code>{{summary.unconsumed_feedback}}</code></div>
        <div><strong>Unprocessed Signals:</strong> <code>{{summary.signals_unprocessed}}</code></div>
      </div>
      <div class="card">
        <h3>Recent Events</h3>
        <table>
          <tr><th>Time</th><th>Event</th><th>Payload</th></tr>
          {% for r in rows %}
          <tr>
            <td>{{r.created_at}}</td>
            <td>{{r.event}}</td>
            <td><code>{{r.payload}}</code></td>
          </tr>
          {% endfor %}
        </table>
      </div>
    </body>
    </html>
    """
    return render_template_string(html, rows=rows, db=DB_PATH, channel=CHANNEL, summary=summary_data)


if __name__ == "__main__":
    app.run(host=HOST, port=PORT, debug=False)

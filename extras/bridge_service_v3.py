import json
import os
import sqlite3
import time
from datetime import datetime, timezone
from typing import Any, Dict, Iterable, List, Tuple


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(tzinfo=None).isoformat() + "Z"


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


class BridgeServiceV3:
    def __init__(
        self,
        db_path: str,
        channel: str = "HEDGE_A",
        poll_ms: int = 200,
        db_timeout_s: float = 5.0,
        busy_timeout_ms: int = 5000,
    ):
        self.db_path = db_path
        self.channel = channel
        self.poll_ms = poll_ms
        self.conn = sqlite3.connect(self.db_path, timeout=db_timeout_s)
        self.conn.row_factory = sqlite3.Row

        self.conn.execute("PRAGMA journal_mode=WAL;")
        self.conn.execute("PRAGMA synchronous=NORMAL;")
        self.conn.execute(f"PRAGMA busy_timeout={int(busy_timeout_ms)};")

        self._last_heartbeat = 0.0
        self._last_shadow_sync = 0.0

    def close(self):
        self.conn.close()

    def emit_event(self, event_type: str, payload: dict, commit: bool = True):
        self.conn.execute(
            "INSERT INTO events(channel, event_type, payload_json, created_at) VALUES(?,?,?,?)",
            (self.channel, event_type, json.dumps(payload), now_iso()),
        )
        if commit:
            self.conn.commit()

    def process_timeouts(self, timeout_ms: int = 3000, max_queue_batch: int = 200):
        rows = self.conn.execute(
            "SELECT id, request_id, created_at FROM proposals WHERE channel=? AND state='PENDING' ORDER BY id ASC LIMIT ?",
            (self.channel, max_queue_batch),
        ).fetchall()
        if not rows:
            return

        now_ts = time.time()
        update_rows: List[Tuple[str, int]] = []
        reply_rows: List[Tuple[str, str, int, str, str]] = []

        for r in rows:
            try:
                created = datetime.fromisoformat(str(r["created_at"]).replace("Z", "")).timestamp()
            except Exception:
                continue
            if (now_ts - created) * 1000.0 > timeout_ms:
                update_rows.append((now_iso(), int(r["id"])))
                reply_rows.append(
                    (self.channel, str(r["request_id"]), 0, json.dumps({"reason": "timeout"}), now_iso())
                )

        if update_rows:
            self.conn.executemany(
                "UPDATE proposals SET state='TIMEOUT', updated_at=? WHERE id=?", update_rows
            )
        if reply_rows:
            self.conn.executemany(
                "INSERT INTO replies(channel, request_id, action, payload_json, created_at) VALUES(?,?,?,?,?)",
                reply_rows,
            )
        if update_rows or reply_rows:
            self.conn.commit()

    def process_feedback(self, max_queue_batch: int = 200):
        rows = self.conn.execute(
            "SELECT id, master_ticket, action, note FROM feedback WHERE channel=? AND consumed=0 ORDER BY id ASC LIMIT ?",
            (self.channel, max_queue_batch),
        ).fetchall()
        if not rows:
            return

        for r in rows:
            self.emit_event(
                "feedback_consumed",
                {
                    "feedback_id": int(r["id"]),
                    "master_ticket": int(r["master_ticket"] or 0),
                    "action": int(r["action"]),
                    "note": r["note"] or "",
                },
                commit=False,
            )

        self.conn.executemany(
            "UPDATE feedback SET consumed=1 WHERE id=?",
            [(int(r["id"]),) for r in rows],
        )
        self.conn.commit()

    def write_shadow_sync(self, files_dir: str):
        os.makedirs(files_dir, exist_ok=True)
        p = os.path.join(files_dir, "ShadowSync.json")
        with open(p, "w", encoding="utf-8") as f:
            json.dump({"sync_time": time.time(), "channel": self.channel, "service": "bridge_v3"}, f)

    def run_forever(
        self,
        timeout_ms: int = 3000,
        files_dir: str = "",
        max_queue_batch: int = 200,
        heartbeat_interval_ms: int = 1000,
        shadow_sync_interval_s: int = 2,
    ):
        self.emit_event("service_start", {"channel": self.channel, "db_path": self.db_path})
        while True:
            self.process_feedback(max_queue_batch=max_queue_batch)
            self.process_timeouts(timeout_ms=timeout_ms, max_queue_batch=max_queue_batch)

            now = time.time()
            if (now - self._last_heartbeat) >= (heartbeat_interval_ms / 1000.0):
                self.emit_event("heartbeat", {"channel": self.channel})
                self._last_heartbeat = now

            if files_dir and (now - self._last_shadow_sync) >= shadow_sync_interval_s:
                self.write_shadow_sync(files_dir)
                self._last_shadow_sync = now

            time.sleep(max(0.05, self.poll_ms / 1000.0))


def main():
    cfg = load_runtime_config()

    db = os.getenv("MBP_V3_DB", cfg_get(cfg, ["sqlite_path"], "MultiBotPro_v3.db"))
    channel = os.getenv("MBP_V3_CHANNEL", cfg_get(cfg, ["channel"], "HEDGE_A"))
    poll_ms = int(os.getenv("MBP_V3_POLL_MS", cfg_get(cfg, ["service", "poll_interval_ms"], 200)))
    timeout_ms = int(os.getenv("MBP_V3_TIMEOUT_MS", cfg_get(cfg, ["service", "proposal_timeout_ms"], 3000)))
    files_dir = os.getenv("MBP_V3_FILES_DIR", cfg_get(cfg, ["files_dir"], ""))

    max_queue_batch = int(os.getenv("MBP_V3_MAX_QUEUE_BATCH", cfg_get(cfg, ["service", "max_queue_batch"], 200)))
    heartbeat_interval_ms = int(
        os.getenv("MBP_V3_HEARTBEAT_MS", cfg_get(cfg, ["service", "heartbeat_interval_ms"], 1000))
    )
    shadow_sync_interval_s = int(
        os.getenv("MBP_V3_SHADOW_SYNC_S", cfg_get(cfg, ["service", "shadow_sync_interval_s"], 2))
    )
    db_timeout_s = float(os.getenv("MBP_V3_DB_TIMEOUT_S", cfg_get(cfg, ["service", "db_timeout_s"], 5)))
    busy_timeout_ms = int(
        os.getenv("MBP_V3_BUSY_TIMEOUT_MS", cfg_get(cfg, ["service", "busy_timeout_ms"], 5000))
    )

    svc = BridgeServiceV3(
        db_path=db,
        channel=channel,
        poll_ms=poll_ms,
        db_timeout_s=db_timeout_s,
        busy_timeout_ms=busy_timeout_ms,
    )
    try:
        svc.run_forever(
            timeout_ms=timeout_ms,
            files_dir=files_dir,
            max_queue_batch=max_queue_batch,
            heartbeat_interval_ms=heartbeat_interval_ms,
            shadow_sync_interval_s=shadow_sync_interval_s,
        )
    finally:
        svc.close()


if __name__ == "__main__":
    main()

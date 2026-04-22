import json
import math
import random
import sqlite3
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Iterable, List
import os


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


@dataclass
class Trade:
    ticket: int
    symbol: str
    side: int  # 0 buy, 1 sell
    lots: float
    open_price: float
    sl: float
    tp: float


class EcosystemSimulatorV3:
    def __init__(self, db_path: str = "MultiBotPro_v3.db", channel: str = "HEDGE_A", db_timeout_s: float = 5.0):
        self.db_path = db_path
        self.channel = channel
        self.conn = sqlite3.connect(db_path, timeout=db_timeout_s)
        self.conn.execute("PRAGMA journal_mode=WAL;")
        self.conn.execute("PRAGMA synchronous=NORMAL;")
        self.master_equity = 10000.0
        self.slave_equity = 10000.0
        self.master_open = []
        self.slave_open = []
        self.ticket = 1

    def close(self):
        self.conn.close()

    def run(self, symbols=None, steps=500, seed: int = 42):
        if symbols is None:
            symbols = ["EURUSD", "GBPUSD", "USDJPY"]
        if seed is not None:
            random.seed(seed)

        price = {s: 1.0 + random.random() * 0.2 for s in symbols}
        t = datetime.now(timezone.utc).replace(tzinfo=None)

        for _ in range(steps):
            t += timedelta(minutes=1)
            for s in symbols:
                drift = random.uniform(-0.002, 0.002)
                price[s] = max(0.1, price[s] * (1.0 + drift))

                if random.random() < 0.02:
                    self.open_trade(s, side=0 if random.random() > 0.5 else 1, px=price[s])

                self.mark_to_market(s, price[s])

        self.persist_summary(t)

    def open_trade(self, symbol: str, side: int, px: float):
        lots = 0.1 + random.random() * 0.5
        sl = px * (0.998 if side == 0 else 1.002)
        tp = px * (1.002 if side == 0 else 0.998)

        m = Trade(self.ticket, symbol, side, lots, px, sl, tp)
        self.ticket += 1
        self.master_open.append(m)

        hedge_lots = max(0.01, lots * random.uniform(0.8, 1.2))
        s = Trade(self.ticket, symbol, 1 - side, hedge_lots, px, tp, sl)
        self.ticket += 1
        self.slave_open.append(s)

    def mark_to_market(self, symbol: str, px: float):
        def pnl(tr: Trade):
            d = (px - tr.open_price) if tr.side == 0 else (tr.open_price - px)
            return d * tr.lots * 10000.0

        mp = sum(pnl(t) for t in self.master_open if t.symbol == symbol)
        sp = sum(pnl(t) for t in self.slave_open if t.symbol == symbol)

        self.master_equity += mp * 0.001
        self.slave_equity += sp * 0.001

    def persist_summary(self, ts: datetime):
        payload = {
            "channel": self.channel,
            "time": ts.isoformat() + "Z",
            "master_equity": round(self.master_equity, 2),
            "slave_equity": round(self.slave_equity, 2),
            "equity_gap": round(self.slave_equity - self.master_equity, 2),
            "open_master": len(self.master_open),
            "open_slave": len(self.slave_open),
            "schema_version": "v3",
        }
        self.conn.execute(
            "CREATE TABLE IF NOT EXISTS events (id INTEGER PRIMARY KEY AUTOINCREMENT, channel TEXT, event_type TEXT, payload_json TEXT, created_at TEXT)"
        )
        self.conn.execute(
            "INSERT INTO events(channel, event_type, payload_json, created_at) VALUES(?,?,?,?)",
            (self.channel, "sim_summary", json.dumps(payload), datetime.now(timezone.utc).replace(tzinfo=None).isoformat() + "Z"),
        )
        self.conn.commit()


def main():
    cfg = load_runtime_config()
    db = os.getenv("MBP_V3_DB", cfg_get(cfg, ["sqlite_path"], "MultiBotPro_v3.db"))
    channel = os.getenv("MBP_V3_CHANNEL", cfg_get(cfg, ["channel"], "HEDGE_A"))

    symbols_env = os.getenv("MBP_V3_SIM_SYMBOLS", "")
    if symbols_env:
        symbols = [s.strip() for s in symbols_env.split(",") if s.strip()]
    else:
        symbols = cfg_get(cfg, ["simulator", "symbols"], ["EURUSD", "GBPUSD", "USDJPY"])

    steps = int(os.getenv("MBP_V3_SIM_STEPS", cfg_get(cfg, ["simulator", "steps"], 500)))
    seed = int(os.getenv("MBP_V3_SIM_SEED", cfg_get(cfg, ["simulator", "seed"], 42)))
    db_timeout_s = float(os.getenv("MBP_V3_DB_TIMEOUT_S", cfg_get(cfg, ["service", "db_timeout_s"], 5)))

    sim = EcosystemSimulatorV3(db_path=db, channel=channel, db_timeout_s=db_timeout_s)
    try:
        sim.run(symbols=symbols, steps=steps, seed=seed)
    finally:
        sim.close()


if __name__ == "__main__":
    main()

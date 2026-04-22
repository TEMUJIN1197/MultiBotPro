import json
import logging
import math
import os
import sqlite3
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Tuple

import MetaTrader5 as mt5
import numpy as np
import pandas as pd
import pandas_ta as ta
import pytz
import schedule
import urllib.request
import xml.etree.ElementTree as ET

try:
    import nltk
    from nltk.sentiment import SentimentIntensityAnalyzer
except Exception:
    nltk = None
    SentimentIntensityAnalyzer = None


logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")


DEFAULT_CONFIG = {
    "mt5_data_dir": r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Files",
    "symbols": ["AUDNZD_ATR", "CHFJPY_ATR", "EURGBP_ATR", "USDCAD_ATR"],
    "entry_tf": mt5.TIMEFRAME_M1,
    "lookback_days": 7,
    "max_workers": 4,
    "cycle_hours": 6,
    "transaction_cost_bps": 2.0,
    "rss_url": "https://www.investing.com/rss/news_285.rss",
    "rss_enabled": True,
    "external_enabled": True,
    "external_sentiment_url": os.getenv("SHADOW_SENTIMENT_URL", ""),
    "sqlite_path": "MultiBotPro_v3.db",
    "write_sqlite": True,
    "shadow_config_prefix": "ShadowConfig",
    "hybrid_sentiment": True,
    "param_ranges": {
        "MA1": {"start": 5, "end": 20, "step": 5},
        "MA2": {"start": 25, "end": 60, "step": 10},
        "BOX": {"start": 2, "end": 8, "step": 2},
        "ADX_P": {"start": 10, "end": 21, "step": 5},
        "ADX_L": {"start": 15.0, "end": 35.0, "step": 5.0},
        "DELTA": {"start": 2.0, "end": 10.0, "step": 2.0},
    },
    "grid_options": [0.0, 1.2, 1.6, 2.4, 4.8],
}


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


def cfg_get(cfg: Dict[str, Any], keys: List[str], default: Any = None) -> Any:
    node: Any = cfg
    for k in keys:
        if not isinstance(node, dict) or k not in node:
            return default
        node = node[k]
    return node


def apply_runtime_config(cfg: Dict[str, Any]) -> Dict[str, Any]:
    runtime_cfg = load_runtime_config()
    if not runtime_cfg:
        return cfg

    cfg = dict(cfg)

    sqlite_path = cfg_get(runtime_cfg, ["sqlite_path"], None)
    if sqlite_path:
        cfg["sqlite_path"] = sqlite_path

    symbols = cfg_get(runtime_cfg, ["shadowmaster", "symbols"], None)
    if isinstance(symbols, list) and symbols:
        cfg["symbols"] = symbols

    prefix = cfg_get(runtime_cfg, ["shadowmaster", "shadow_config_prefix"], None)
    if prefix:
        cfg["shadow_config_prefix"] = prefix

    for key in ["cycle_hours", "lookback_days", "max_workers", "transaction_cost_bps"]:
        val = cfg_get(runtime_cfg, ["shadowmaster", key], None)
        if val is not None:
            cfg[key] = val

    rss_url = cfg_get(runtime_cfg, ["sentiment", "rss_url"], None)
    if rss_url:
        cfg["rss_url"] = rss_url

    cfg["rss_enabled"] = bool(cfg_get(runtime_cfg, ["sentiment", "rss_enabled"], cfg.get("rss_enabled", True)))
    cfg["external_enabled"] = bool(
        cfg_get(runtime_cfg, ["sentiment", "external_enabled"], cfg.get("external_enabled", True))
    )

    env_name = cfg_get(runtime_cfg, ["sentiment", "external_url_env"], None)
    if env_name:
        cfg["external_sentiment_url"] = os.getenv(env_name, cfg.get("external_sentiment_url", ""))

    return cfg


def gen_range(p: Dict[str, float]) -> List[float]:
    return list(np.arange(p["start"], p["end"] + 0.00001, p["step"]))


def load_config(config_path: str = "") -> Dict:
    cfg = dict(DEFAULT_CONFIG)
    cfg = apply_runtime_config(cfg)
    if config_path and os.path.exists(config_path):
        with open(config_path, "r", encoding="utf-8") as f:
            user_cfg = json.load(f)
        for k, v in user_cfg.items():
            if isinstance(v, dict) and isinstance(cfg.get(k), dict):
                merged = dict(cfg[k])
                merged.update(v)
                cfg[k] = merged
            else:
                cfg[k] = v
    return cfg


@dataclass
class SymbolResult:
    symbol: str
    best_params: Dict
    score: float


class ShadowMasterV3:
    def __init__(self, cfg: Dict):
        self.cfg = cfg
        self.sia = None
        if nltk and SentimentIntensityAnalyzer:
            try:
                nltk.data.find("sentiment/vader_lexicon.zip")
                self.sia = SentimentIntensityAnalyzer()
            except LookupError:
                try:
                    nltk.download("vader_lexicon", quiet=True)
                    self.sia = SentimentIntensityAnalyzer()
                except Exception:
                    self.sia = None
            except Exception:
                self.sia = None

    def fetch_data(self, sym: str, timeframe: int, days: int) -> pd.DataFrame:
        if not mt5.symbol_select(sym, True):
            logging.warning("Symbol select failed: %s", sym)
            return pd.DataFrame()

        timezone = pytz.timezone("Etc/UTC")
        utc_to = datetime.now(timezone)
        utc_from = utc_to - timedelta(days=days)
        rates = mt5.copy_rates_range(sym, timeframe, utc_from, utc_to)
        if rates is None or len(rates) == 0:
            return pd.DataFrame()
        df = pd.DataFrame(rates)
        df["time"] = pd.to_datetime(df["time"], unit="s")
        df.set_index("time", inplace=True)
        return df

    def fetch_news_sentiment(self, symbol: str) -> bool:
        base_curr = symbol[0:3]
        quote_curr = symbol[3:6]

        scores = []
        try:
            if self.cfg.get("hybrid_sentiment", True):
                if self.cfg.get("rss_enabled", True):
                    scores.extend(self._rss_scores(base_curr, quote_curr))
                if self.cfg.get("external_enabled", True):
                    scores.extend(self._external_scores(base_curr, quote_curr))

            if not scores:
                return False

            avg = float(np.mean(scores))

            if avg <= -0.4:
                logging.warning(
                    "NLP KILLSWITCH ACTIVATED for %s (sentiment %.2f)",
                    symbol,
                    avg,
                )
                return True
            return False

        except Exception as e:
            logging.error("NLP Engine Error: %s", e)
            return False

    def _rss_scores(self, base_curr: str, quote_curr: str) -> List[float]:
        if not self.sia:
            return []
        url = self.cfg.get("rss_url", "")
        if not url:
            return []
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            xml_data = urllib.request.urlopen(req, timeout=10).read()
            root = ET.fromstring(xml_data)
            scores = []
            for item in root.findall("./channel/item"):
                title_el = item.find("title")
                title = title_el.text if title_el is not None else ""
                if not title:
                    continue
                if base_curr in title or quote_curr in title or "Crypto" in title or "Bitcoin" in title:
                    scores.append(self.sia.polarity_scores(title)["compound"])
            return scores
        except Exception:
            return []

    def _external_scores(self, base_curr: str, quote_curr: str) -> List[float]:
        url = self.cfg.get("external_sentiment_url", "")
        if not url:
            return []
        try:
            req = urllib.request.Request(
                f"{url}?base={base_curr}&quote={quote_curr}",
                headers={"User-Agent": "ShadowMasterV3"},
            )
            raw = urllib.request.urlopen(req, timeout=6).read().decode("utf-8")
            payload = json.loads(raw)
            if isinstance(payload, dict) and isinstance(payload.get("scores"), list):
                return [float(x) for x in payload["scores"]]
        except Exception:
            return []
        return []

    def precompute_indicators(self, df: pd.DataFrame, params: Dict) -> Dict[str, Dict[float, pd.Series]]:
        cache = {"ema": {}, "adx": {}, "box": {}}

        all_ma = sorted(set(gen_range(params["MA1"]) + gen_range(params["MA2"])) )
        for p in all_ma:
            cache["ema"][p] = ta.ema(df["close"], length=int(p))

        for p in gen_range(params["ADX_P"]):
            adx_data = ta.adx(df["high"], df["low"], df["close"], length=int(p))
            if adx_data is not None and f"ADX_{int(p)}" in adx_data:
                cache["adx"][p] = adx_data[f"ADX_{int(p)}"]

        for b in gen_range(params["BOX"]):
            lookback = int(b)
            tmp = pd.DataFrame(index=df.index)
            tmp["Roll_Max_L"] = df["high"].shift(1).rolling(window=lookback).max()
            tmp["Roll_Min_L"] = df["low"].shift(1).rolling(window=lookback).min()
            tmp["Roll_Max_R"] = df["high"].iloc[::-1].shift(1).rolling(window=lookback).max().iloc[::-1]
            tmp["Roll_Min_R"] = df["low"].iloc[::-1].shift(1).rolling(window=lookback).min().iloc[::-1]
            is_ph = (df["high"] > tmp["Roll_Max_L"]) & (df["high"] > tmp["Roll_Max_R"])
            is_pl = (df["low"] < tmp["Roll_Min_L"]) & (df["low"] < tmp["Roll_Min_R"])
            cache["box"][b] = {
                "high": df["high"].where(is_ph).ffill(),
                "low": df["low"].where(is_pl).ffill(),
            }

        return cache

    def score_strategy(self, pos: np.ndarray, close: pd.Series, cost_bps: float) -> Tuple[float, float, int]:
        rets = pd.Series(pos).shift(1).fillna(0.0).values * np.log(close / close.shift(1)).fillna(0.0).values
        if len(rets) == 0:
            return -9999.0, 0.0, 0

        trade_count = int(np.count_nonzero(np.diff(pos) != 0))
        cost = (cost_bps / 10000.0) * max(1, trade_count)

        mean = float(np.mean(rets))
        std = float(np.std(rets))
        sharpe = (mean / std) * math.sqrt(252 * 24 * 60) if std > 1e-10 else -1.0

        eq = np.cumsum(rets)
        peak = np.maximum.accumulate(eq)
        dd = peak - eq
        max_dd = float(np.max(dd)) if len(dd) else 0.0

        score = sharpe - (max_dd * 5.0) - cost
        return score, max_dd, trade_count

    def optimize_symbol(self, symbol: str) -> SymbolResult:
        logging.info("--- Preliminary Calculations for %s ---", symbol)
        df = self.fetch_data(symbol, self.cfg["entry_tf"], self.cfg["lookback_days"])
        if df.empty:
            return SymbolResult(symbol, {}, -9999.0)

        params = self.cfg["param_ranges"]
        cache = self.precompute_indicators(df, params)
        nlp_killswitch = self.fetch_news_sentiment(symbol)

        best_score = -9999.0
        best: Dict[str, Any] = {}

        ma1_p = gen_range(params["MA1"])
        ma2_p = gen_range(params["MA2"])
        box_p = gen_range(params["BOX"])
        adx_p = gen_range(params["ADX_P"])
        adx_l = gen_range(params["ADX_L"])
        delta_p = gen_range(params["DELTA"])
        grid_p = self.cfg["grid_options"]

        total = len(box_p) * len(adx_p) * len(adx_l) * len(delta_p) * len(grid_p) * sum(
            1 for m1 in ma1_p for m2 in ma2_p if m1 < m2
        )
        done = 0

        if total <= 0:
            return SymbolResult(symbol, {}, -9999.0)

        for box in box_p:
            box_high = cache["box"][box]["high"]
            for ap in adx_p:
                adx_series = cache["adx"].get(ap)
                if adx_series is None:
                    continue
                for m1 in ma1_p:
                    for m2 in ma2_p:
                        if m1 >= m2:
                            continue
                        ma1 = cache["ema"].get(m1)
                        ma2 = cache["ema"].get(m2)
                        if ma1 is None or ma2 is None:
                            continue

                        ma_buy = ma1 > ma2
                        box_buy = df["close"] > box_high.shift(1)

                        for al in adx_l:
                            adx_pass = adx_series >= al
                            for dl in delta_p:
                                for gr in grid_p:
                                    done += 1
                                    if done % 200 == 0:
                                        sys.stdout.write(
                                            f"\r{datetime.now().strftime('%H:%M:%S')} [INFO] Optimizing {symbol}: {done}/{total} combinations..."
                                        )
                                        sys.stdout.flush()

                                    pos = np.where(ma_buy & box_buy & adx_pass, 1, 0)
                                    score, max_dd, trades = self.score_strategy(
                                        pos=pos,
                                        close=df["close"],
                                        cost_bps=float(self.cfg["transaction_cost_bps"]),
                                    )

                                    if score > best_score:
                                        best_score = score
                                        best = {
                                            "MA1_Period": int(m1),
                                            "MA2_Period": int(m2),
                                            "Box_Lookback": int(box),
                                            "ADX_Period": int(ap),
                                            "ADX_MinLevel": float(al),
                                            "CurrencyStrengthDelta": float(dl),
                                            "GridMultiplier": float(gr),
                                            "NLP_Killswitch": bool(nlp_killswitch),
                                            "Score": round(float(score), 4),
                                            "MaxDrawdown": round(float(max_dd), 6),
                                            "Trades": int(trades),
                                            "schema_version": "v3",
                                            "run_id": int(time.time()),
                                            "Updated": datetime.now(timezone.utc).replace(tzinfo=None).isoformat() + "Z",
                                        }

        sys.stdout.write("\r" + " " * 100 + "\r")
        logging.info("Best %s: %s", symbol, best)

        return SymbolResult(symbol, best, best_score)

    def write_outputs(self, result: SymbolResult) -> None:
        if not result.best_params:
            return

        data_dir = self.cfg["mt5_data_dir"] or os.getcwd()
        os.makedirs(data_dir, exist_ok=True)
        prefix = self.cfg.get("shadow_config_prefix", "ShadowConfig")
        out_path = os.path.join(data_dir, f"{prefix}_{result.symbol}.json")
        tmp_path = out_path + ".tmp"

        with open(tmp_path, "w", encoding="utf-8") as f:
            json.dump(result.best_params, f, indent=2)
        os.replace(tmp_path, out_path)

        if self.cfg.get("write_sqlite", True):
            self.write_sqlite_config(result.symbol, result.best_params)

    def write_sqlite_config(self, symbol: str, params: Dict) -> None:
        db = self.cfg.get("sqlite_path", "MultiBotPro_v3.db")
        conn = sqlite3.connect(db)
        try:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS shadow_params (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    symbol TEXT NOT NULL,
                    payload_json TEXT NOT NULL,
                    score REAL,
                    updated_at TEXT NOT NULL
                )
                """
            )
            conn.execute(
                "INSERT INTO shadow_params(symbol, payload_json, score, updated_at) VALUES(?,?,?,?)",
                (
                    symbol,
                    json.dumps(params),
                    float(params.get("Score", -9999.0)),
                    datetime.now(timezone.utc).replace(tzinfo=None).isoformat() + "Z",
                ),
            )
            conn.commit()
        finally:
            conn.close()

    def run_cycle(self) -> None:
        logging.info("STARTING SHADOW MASTER OPTIMIZATION CYCLE...")
        if not mt5.initialize():
            logging.error("MT5 initialize failed")
            return

        try:
            futures = []
            results: List[SymbolResult] = []
            with ThreadPoolExecutor(max_workers=int(self.cfg.get("max_workers", 4))) as ex:
                for sym in self.cfg["symbols"]:
                    futures.append(ex.submit(self.optimize_symbol, sym))

                for fut in as_completed(futures):
                    res = fut.result()
                    results.append(res)
                    self.write_outputs(res)

            data_dir = self.cfg["mt5_data_dir"] or os.getcwd()
            sync_path = os.path.join(data_dir, "ShadowSync.json")
            with open(sync_path, "w", encoding="utf-8") as f:
                json.dump(
                    {"sync_time": time.time(), "schema_version": "v3", "symbols": [r.symbol for r in results]},
                    f,
                )

            print("\n" + "=" * 60)
            print("SHADOW MASTER FULL CYCLE COMPLETE")
            print("=" * 60 + "\n")

        finally:
            mt5.shutdown()


def main() -> None:
    config_path = ""
    if len(sys.argv) > 1:
        config_path = sys.argv[1]

    cfg = load_config(config_path)
    bot = ShadowMasterV3(cfg)
    bot.run_cycle()

    hours = int(cfg.get("cycle_hours", 6))
    if hours > 0:
        schedule.every(hours).hours.do(bot.run_cycle)
        while True:
            schedule.run_pending()
            time.sleep(30)


if __name__ == "__main__":
    main()





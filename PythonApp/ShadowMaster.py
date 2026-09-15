import json
import logging
import math
import os
import sqlite3
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional, Tuple

import MetaTrader5 as mt5
import numpy as np
import pandas as pd
import urllib.request
import xml.etree.ElementTree as ET

try:
    import nltk
    from nltk.sentiment import SentimentIntensityAnalyzer
except Exception:
    nltk = None
    SentimentIntensityAnalyzer = None


LOG_FORMAT = "%(asctime)s [%(levelname)s] %(message)s"
logging.basicConfig(level=logging.INFO, format=LOG_FORMAT)

RUNTIME_CONTRACT_NAME = "MultiBotPro.ShadowMaster"
RUNTIME_CONTRACT_VERSION = "1.0"
RUNTIME_TRANSPORT = "file-json"

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
    "sentiment_threshold": -0.4,
    "sqlite_path": "MultiBotPro_v3.db",
    "write_sqlite": True,
    "shadow_config_prefix": "ShadowConfig",
    "hybrid_sentiment": True,
    "openai": {
        "enabled": bool(os.getenv("OPENAI_API_KEY")),
        "model": os.getenv("OPENAI_MODEL", "gpt-5.5"),
        "reasoning_effort": os.getenv("OPENAI_REASONING_EFFORT", "low"),
        "timeout_seconds": int(os.getenv("OPENAI_TIMEOUT_SECONDS", "25")),
        "max_output_tokens": int(os.getenv("OPENAI_MAX_OUTPUT_TOKENS", "220")),
        "api_key_env": os.getenv("OPENAI_API_KEY_ENV", "OPENAI_API_KEY"),
        "project_env": os.getenv("OPENAI_PROJECT_ENV", "OPENAI_PROJECT"),
        "organization_env": os.getenv("OPENAI_ORGANIZATION_ENV", "OPENAI_ORG_ID"),
        "base_url_env": os.getenv("OPENAI_BASE_URL_ENV", "OPENAI_BASE_URL"),
        "store": False,
    },
    "param_ranges": {
        "MA1": {"start": 5, "end": 20, "step": 5},
        "MA2": {"start": 25, "end": 60, "step": 10},
        "BOX": {"start": 2, "end": 8, "step": 2},
        "ADX_P": {"start": 10, "end": 21, "step": 5},
        "ADX_L": {"start": 15.0, "end": 35.0, "step": 5.0},
        "DELTA": {"start": 2.0, "end": 10.0, "step": 2.0},
    },
    "grid_options": [0.0, 1.2, 1.6, 2.4, 4.8],
    "runtime_contract": {
        "name": RUNTIME_CONTRACT_NAME,
        "version": RUNTIME_CONTRACT_VERSION,
        "transport": RUNTIME_TRANSPORT,
        "command_file": r"MultiBotPro2\runtime_v3.json",
        "status_file": "ShadowMasterRuntime.json",
        "shadow_config_prefix": "ShadowConfig",
    },
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


def to_bool(value: Any, default: bool = False) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in {"1", "true", "yes", "on"}:
            return True
        if normalized in {"0", "false", "no", "off", ""}:
            return False
    return default


def to_float(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except Exception:
        return default


def normalize_symbols(symbols: Any) -> List[str]:
    if not isinstance(symbols, list):
        return []

    analysis_suffixes = {"R", "ATR", "RENKO", "MEDIANRENKO", "TURBORENKO", "HEIKENRENKO", "HA", "CUSTOM"}
    result: List[str] = []
    seen = set()
    for value in symbols:
        symbol = str(value or "").strip()
        if not symbol:
            continue

        parts = symbol.split("_", 1)
        if len(parts) == 2 and parts[1].upper() in analysis_suffixes:
            symbol = parts[0].strip()
            if not symbol:
                continue

        key = symbol.upper()
        if key in seen:
            continue
        seen.add(key)
        result.append(symbol)
    return result


def indicator_ema(values: pd.Series, length: int) -> pd.Series:
    return values.ewm(span=max(1, int(length)), adjust=False, min_periods=max(1, int(length))).mean()


def indicator_atr(high: pd.Series, low: pd.Series, close: pd.Series, length: int = 14) -> pd.Series:
    period = max(1, int(length))
    prev_close = close.shift(1)
    true_range = pd.concat(
        [
            high - low,
            (high - prev_close).abs(),
            (low - prev_close).abs(),
        ],
        axis=1,
    ).max(axis=1)
    return true_range.ewm(alpha=1.0 / period, adjust=False, min_periods=period).mean()


def indicator_adx(high: pd.Series, low: pd.Series, close: pd.Series, length: int = 14) -> pd.Series:
    period = max(1, int(length))
    up_move = high.diff()
    down_move = -low.diff()
    plus_dm = pd.Series(np.where((up_move > down_move) & (up_move > 0), up_move, 0.0), index=high.index)
    minus_dm = pd.Series(np.where((down_move > up_move) & (down_move > 0), down_move, 0.0), index=high.index)

    atr = indicator_atr(high, low, close, period)
    plus_di = 100.0 * plus_dm.ewm(alpha=1.0 / period, adjust=False, min_periods=period).mean() / atr
    minus_di = 100.0 * minus_dm.ewm(alpha=1.0 / period, adjust=False, min_periods=period).mean() / atr
    dx = 100.0 * (plus_di - minus_di).abs() / (plus_di + minus_di).replace(0.0, np.nan)
    return dx.ewm(alpha=1.0 / period, adjust=False, min_periods=period).mean()


def apply_runtime_config(cfg: Dict[str, Any], runtime_path: str = "") -> Dict[str, Any]:
    runtime_cfg = load_runtime_config(runtime_path)
    if not runtime_cfg:
        return cfg

    cfg = dict(cfg)

    runtime_contract = cfg_get(runtime_cfg, ["runtime_contract"], None)
    if isinstance(runtime_contract, dict):
        merged_contract = dict(cfg.get("runtime_contract", {}))
        merged_contract.update(runtime_contract)
        cfg["runtime_contract"] = merged_contract

    sqlite_path = cfg_get(runtime_cfg, ["sqlite_path"], None)
    if sqlite_path:
        cfg["sqlite_path"] = sqlite_path

    mt5_data_dir = cfg_get(runtime_cfg, ["mt5_data_dir"], None)
    if mt5_data_dir:
        cfg["mt5_data_dir"] = mt5_data_dir

    channel = cfg_get(runtime_cfg, ["channel"], None)
    if not channel:
        channel = cfg_get(runtime_cfg, ["network", "channel"], None)
    if channel:
        cfg["channel"] = channel

    write_sqlite = cfg_get(runtime_cfg, ["use_sqlite_bridge"], None)
    if write_sqlite is None:
        write_sqlite = cfg_get(runtime_cfg, ["bridge", "use_sqlite_bridge"], None)
    if write_sqlite is not None:
        cfg["write_sqlite"] = to_bool(write_sqlite, cfg.get("write_sqlite", True))

    symbols = cfg_get(runtime_cfg, ["shadowmaster", "symbols"], None)
    normalized_symbols = normalize_symbols(symbols)
    if normalized_symbols:
        cfg["symbols"] = normalized_symbols

    prefix = cfg_get(runtime_cfg, ["shadowmaster", "shadow_config_prefix"], None)
    if prefix:
        cfg["shadow_config_prefix"] = prefix

    for key in ["cycle_hours", "lookback_days", "max_workers", "transaction_cost_bps"]:
        val = cfg_get(runtime_cfg, ["shadowmaster", key], None)
        if val is not None:
            cfg[key] = val

    cfg["symbols"] = normalize_symbols(cfg.get("symbols", []))
    if cfg["symbols"]:
        cfg["max_workers"] = max(1, min(int(to_float(cfg.get("max_workers", 1), 1)), len(cfg["symbols"])))

    rss_url = cfg_get(runtime_cfg, ["sentiment", "rss_url"], None)
    if rss_url:
        cfg["rss_url"] = rss_url

    cfg["rss_enabled"] = bool(cfg_get(runtime_cfg, ["sentiment", "rss_enabled"], cfg.get("rss_enabled", True)))
    cfg["external_enabled"] = bool(
        cfg_get(runtime_cfg, ["sentiment", "external_enabled"], cfg.get("external_enabled", True))
    )
    cfg["sentiment_threshold"] = to_float(
        cfg_get(runtime_cfg, ["sentiment", "killswitch_threshold"], cfg.get("sentiment_threshold", -0.4)),
        cfg.get("sentiment_threshold", -0.4),
    )

    env_name = cfg_get(runtime_cfg, ["sentiment", "external_url_env"], None)
    if env_name:
        cfg["external_sentiment_url"] = os.getenv(env_name, cfg.get("external_sentiment_url", ""))

    openai_cfg = dict(cfg.get("openai", {}))
    for key in [
        "enabled",
        "model",
        "reasoning_effort",
        "timeout_seconds",
        "max_output_tokens",
        "api_key_env",
        "project_env",
        "organization_env",
        "base_url_env",
        "store",
    ]:
        val = cfg_get(runtime_cfg, ["openai", key], None)
        if val is not None:
            openai_cfg[key] = val
    if openai_cfg:
        cfg["openai"] = openai_cfg

    return cfg


def gen_range(p: Dict[str, float]) -> List[float]:
    return list(np.arange(p["start"], p["end"] + 0.00001, p["step"]))


def load_config(config_path: str = "") -> Dict:
    cfg = dict(DEFAULT_CONFIG)
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
    cfg = apply_runtime_config(cfg, config_path)
    return cfg


def validate_runtime_contract(cfg: Dict[str, Any]) -> None:
    contract = cfg.get("runtime_contract", {})
    if not isinstance(contract, dict):
        logging.warning("Runtime contract missing; continuing with defaults")
        return

    name = str(contract.get("name", ""))
    version = str(contract.get("version", ""))
    transport = str(contract.get("transport", ""))
    if name != RUNTIME_CONTRACT_NAME or version != RUNTIME_CONTRACT_VERSION or transport != RUNTIME_TRANSPORT:
        logging.warning(
            "Runtime contract mismatch | got name=%s version=%s transport=%s expected name=%s version=%s transport=%s",
            name,
            version,
            transport,
            RUNTIME_CONTRACT_NAME,
            RUNTIME_CONTRACT_VERSION,
            RUNTIME_TRANSPORT,
        )


def setup_logging(cfg: Dict[str, Any]) -> None:
    log_cfg = cfg.get("logging", {})
    if not isinstance(log_cfg, dict):
        log_cfg = {}

    level_name = str(log_cfg.get("level", "INFO")).upper()
    level = getattr(logging, level_name, logging.INFO)
    root = logging.getLogger()
    root.setLevel(level)

    log_file = str(log_cfg.get("file", "logs/runtime.log") or "logs/runtime.log")
    if not os.path.isabs(log_file):
        log_file = os.path.join(os.getcwd(), log_file)

    try:
        os.makedirs(os.path.dirname(log_file), exist_ok=True)
        has_same_file = False
        for handler in root.handlers:
            if isinstance(handler, logging.FileHandler) and getattr(handler, "baseFilename", "") == os.path.abspath(log_file):
                has_same_file = True
                break
        if not has_same_file:
            file_handler = logging.FileHandler(log_file, encoding="utf-8")
            file_handler.setFormatter(logging.Formatter(LOG_FORMAT))
            file_handler.setLevel(level)
            root.addHandler(file_handler)
        logging.info("ShadowMaster logging active | file=%s", log_file)
    except Exception as exc:
        logging.warning("ShadowMaster file logging setup failed: %s", exc)


def shadowmaster_lock_path(cfg: Dict[str, Any]) -> str:
    data_dir = cfg.get("mt5_data_dir") or os.getcwd()
    return os.path.join(data_dir, "ShadowMaster.lock.json")


def read_json_file(path: str) -> Dict[str, Any]:
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
            return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def acquire_shadowmaster_lock(cfg: Dict[str, Any], stale_after_sec: int = 180) -> bool:
    data_dir = cfg.get("mt5_data_dir") or os.getcwd()
    os.makedirs(data_dir, exist_ok=True)
    lock_path = shadowmaster_lock_path(cfg)
    existing = read_json_file(lock_path)
    now = int(time.time())
    existing_heartbeat = int(to_float(existing.get("last_heartbeat", 0), 0))
    existing_pid = int(to_float(existing.get("pid", 0), 0))
    if existing_pid != os.getpid() and existing_heartbeat > 0 and (now - existing_heartbeat) <= stale_after_sec:
        logging.warning(
            "Another ShadowMaster instance appears active | pid=%s heartbeat_age=%ss lock=%s. Exiting duplicate.",
            existing_pid,
            now - existing_heartbeat,
            lock_path,
        )
        return False

    write_shadowmaster_lock(cfg, "STARTING")
    logging.info("ShadowMaster instance lock acquired | pid=%s lock=%s", os.getpid(), lock_path)
    return True


def write_shadowmaster_lock(cfg: Dict[str, Any], state: str) -> None:
    lock_path = shadowmaster_lock_path(cfg)
    tmp_path = f"{lock_path}.{os.getpid()}.tmp"
    try:
        with open(tmp_path, "w", encoding="utf-8") as f:
            json.dump(
                {
                    "pid": os.getpid(),
                    "state": state,
                    "last_heartbeat": int(time.time()),
                    "updated_at": datetime.now(timezone.utc).replace(tzinfo=None).isoformat() + "Z",
                },
                f,
            )
        os.replace(tmp_path, lock_path)
    except Exception as exc:
        logging.warning("ShadowMaster lock write failed: %s", exc)


@dataclass
class SymbolResult:
    symbol: str
    best_params: Dict
    score: float


class ShadowMasterV3:
    def __init__(self, cfg: Dict):
        self.cfg = cfg
        self.sia = None
        self._openai_warning_emitted = False
        self._last_heartbeat_state = ""
        self._cycle_id = 0
        self._last_cycle_started_at = ""
        self._last_cycle_completed_at = ""
        self._last_results: List[Dict[str, Any]] = []
        self._heartbeat_lock = threading.Lock()
        self._heartbeat_stop = threading.Event()
        self._heartbeat_thread: Optional[threading.Thread] = None
        self._heartbeat_state = "STARTING"
        self.write_heartbeat("STARTING")
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

    def write_heartbeat(self, state: str) -> None:
        data_dir = self.cfg.get("mt5_data_dir") or os.getcwd()
        self._heartbeat_state = state
        try:
            with self._heartbeat_lock:
                os.makedirs(data_dir, exist_ok=True)
                out_path = os.path.join(data_dir, "ShadowMasterRuntime.json")
                tmp_path = f"{out_path}.{os.getpid()}.tmp"
                status = {
                    "schema_version": "v3",
                    "runtime_contract": dict(self.cfg.get("runtime_contract", {})),
                    "role": "SHADOW_MASTER",
                    "last_heartbeat": int(time.time()),
                    "state": state,
                    "channel": self.cfg.get("channel", ""),
                    "sqlite_path": self.cfg.get("sqlite_path", ""),
                    "pid": os.getpid(),
                    "updated_at": datetime.now(timezone.utc).replace(tzinfo=None).isoformat() + "Z",
                    "cycle_id": self._cycle_id,
                    "cycle_started_at": self._last_cycle_started_at,
                    "cycle_completed_at": self._last_cycle_completed_at,
                    "symbols_requested": list(self.cfg.get("symbols", [])),
                    "last_results": self._last_results[-32:],
                }
                with open(tmp_path, "w", encoding="utf-8") as f:
                    json.dump(status, f, indent=2)
                os.replace(tmp_path, out_path)
                write_shadowmaster_lock(self.cfg, state)
                if state != self._last_heartbeat_state:
                    logging.info("Heartbeat state -> %s | file=%s", state, out_path)
                    self._last_heartbeat_state = state
        except Exception as exc:
            logging.warning("Heartbeat write failed: %s", exc)

    def start_heartbeat_pump(self) -> None:
        if self._heartbeat_thread and self._heartbeat_thread.is_alive():
            return

        self._heartbeat_stop.clear()

        def pump() -> None:
            while not self._heartbeat_stop.wait(30):
                self.write_heartbeat(self._heartbeat_state or "RUNNING")

        self._heartbeat_thread = threading.Thread(target=pump, name="ShadowMasterHeartbeat", daemon=True)
        self._heartbeat_thread.start()

    def stop_heartbeat_pump(self) -> None:
        self._heartbeat_stop.set()
        if self._heartbeat_thread and self._heartbeat_thread.is_alive():
            self._heartbeat_thread.join(timeout=5)

    def fetch_data(self, sym: str, timeframe: int, days: int) -> pd.DataFrame:
        if not mt5.symbol_select(sym, True):
            logging.warning("Symbol select failed: %s", sym)
            return pd.DataFrame()

        logging.info("Fetching %s history | timeframe=%s lookback_days=%s", sym, timeframe, days)
        utc_to = datetime.now(timezone.utc)
        utc_from = utc_to - timedelta(days=days)
        rates = mt5.copy_rates_range(sym, timeframe, utc_from, utc_to)
        if rates is None or len(rates) == 0:
            logging.warning("No MT5 rates returned for %s", sym)
            return pd.DataFrame()
        df = pd.DataFrame(rates)
        df["time"] = pd.to_datetime(df["time"], unit="s")
        df.set_index("time", inplace=True)
        logging.info("Fetched %s bars for %s | first=%s last=%s", len(df), sym, df.index[0], df.index[-1])
        return df

    def fetch_news_sentiment(
        self,
        symbol: str,
        market_snapshot: Optional[Dict[str, Any]] = None,
    ) -> Tuple[bool, Dict[str, Any]]:
        base_curr = symbol[0:3]
        quote_curr = symbol[3:6]

        scores: List[float] = []
        ai_report: Dict[str, Any] = {}
        try:
            if self.cfg.get("hybrid_sentiment", True):
                rss_headlines: List[str] = []
                if self.cfg.get("rss_enabled", True):
                    rss_headlines = self._rss_headlines(base_curr, quote_curr)
                    scores.extend(self._score_headlines(rss_headlines))
                external_scores: List[float] = []
                if self.cfg.get("external_enabled", True):
                    external_scores = self._external_scores(base_curr, quote_curr)
                    scores.extend(external_scores)

                ai_report = self._openai_sentiment_report(
                    symbol=symbol,
                    base_curr=base_curr,
                    quote_curr=quote_curr,
                    market_snapshot=market_snapshot or {},
                    rss_headlines=rss_headlines,
                    external_scores=external_scores,
                )
                if ai_report:
                    scores.append(to_float(ai_report.get("sentiment_score"), 0.0))

            if not scores:
                return False, ai_report

            avg = float(np.mean(scores))
            threshold = to_float(self.cfg.get("sentiment_threshold", -0.4), -0.4)
            killswitch = avg <= threshold

            if ai_report and to_bool(ai_report.get("killswitch"), False):
                killswitch = True

            if killswitch:
                logging.warning(
                    "NLP KILLSWITCH ACTIVATED for %s (sentiment %.2f)",
                    symbol,
                    avg,
                )
                return True, ai_report
            return False, ai_report

        except Exception as e:
            logging.error("NLP Engine Error: %s", e)
            return False, ai_report

    def _openai_settings(self) -> Dict[str, Any]:
        settings = self.cfg.get("openai", {})
        return settings if isinstance(settings, dict) else {}

    def _openai_enabled(self) -> bool:
        return to_bool(self._openai_settings().get("enabled"), False)

    def _openai_api_key(self) -> str:
        env_name = str(self._openai_settings().get("api_key_env", "OPENAI_API_KEY"))
        return os.getenv(env_name, "").strip()

    def _extract_response_text(self, payload: Dict[str, Any]) -> str:
        output_text = payload.get("output_text")
        if isinstance(output_text, str) and output_text.strip():
            return output_text.strip()

        pieces: List[str] = []
        for item in payload.get("output", []):
            if not isinstance(item, dict):
                continue
            for content in item.get("content", []):
                if not isinstance(content, dict):
                    continue
                if content.get("type") not in {"output_text", "text"}:
                    continue
                text_value = content.get("text")
                if isinstance(text_value, str):
                    pieces.append(text_value)
                elif isinstance(text_value, dict):
                    candidate = text_value.get("value")
                    if isinstance(candidate, str):
                        pieces.append(candidate)
        return "\n".join(piece for piece in pieces if piece).strip()

    def _extract_first_json_object(self, text: str) -> Dict[str, Any]:
        decoder = json.JSONDecoder()
        candidate = text.strip()
        if not candidate:
            return {}
        try:
            parsed = json.loads(candidate)
            return parsed if isinstance(parsed, dict) else {}
        except Exception:
            pass

        idx = candidate.find("{")
        while idx >= 0:
            try:
                parsed, _ = decoder.raw_decode(candidate[idx:])
                if isinstance(parsed, dict):
                    return parsed
            except Exception:
                pass
            idx = candidate.find("{", idx + 1)
        return {}

    def _summarize_market_snapshot(self, df: pd.DataFrame) -> Dict[str, Any]:
        if df.empty:
            return {}

        closes = df["close"]
        highs = df["high"]
        lows = df["low"]

        def pct_change(bars: int) -> Optional[float]:
            if len(closes) <= bars:
                return None
            previous = float(closes.iloc[-(bars + 1)])
            if abs(previous) < 1e-12:
                return None
            latest = float(closes.iloc[-1])
            return round(((latest - previous) / previous) * 100.0, 4)

        atr_value: Optional[float] = None
        atr_series = indicator_atr(highs, lows, closes, length=14)
        if atr_series is not None:
            atr_series = atr_series.dropna()
            if len(atr_series) > 0:
                atr_value = round(float(atr_series.iloc[-1]), 6)

        log_returns = np.log(closes / closes.shift(1)).replace([np.inf, -np.inf], np.nan).dropna()
        intraday_vol = None
        if len(log_returns) > 1:
            intraday_vol = round(float(log_returns.tail(min(len(log_returns), 240)).std()), 6)

        day_window = min(len(df), 1440)
        return {
            "bars": int(len(df)),
            "last_close": round(float(closes.iloc[-1]), 6),
            "high_24h": round(float(highs.tail(day_window).max()), 6),
            "low_24h": round(float(lows.tail(day_window).min()), 6),
            "change_1h_pct": pct_change(60),
            "change_4h_pct": pct_change(240),
            "change_1d_pct": pct_change(1440),
            "atr_14": atr_value,
            "log_return_vol_240": intraday_vol,
        }

    def _headline_matches_symbol(self, title: str, base_curr: str, quote_curr: str) -> bool:
        title_upper = title.upper()
        return (
            base_curr.upper() in title_upper
            or quote_curr.upper() in title_upper
            or "CRYPTO" in title_upper
            or "BITCOIN" in title_upper
        )

    def _score_headlines(self, headlines: List[str]) -> List[float]:
        if not self.sia:
            return []
        scores: List[float] = []
        for headline in headlines:
            if headline:
                scores.append(self.sia.polarity_scores(headline)["compound"])
        return scores

    def _rss_headlines(self, base_curr: str, quote_curr: str) -> List[str]:
        url = self.cfg.get("rss_url", "")
        if not url:
            return []
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            xml_data = urllib.request.urlopen(req, timeout=10).read()
            root = ET.fromstring(xml_data)
            headlines: List[str] = []
            seen = set()
            for item in root.findall("./channel/item"):
                title_el = item.find("title")
                title = title_el.text.strip() if title_el is not None and title_el.text else ""
                if not title or title in seen:
                    continue
                if self._headline_matches_symbol(title, base_curr, quote_curr):
                    seen.add(title)
                    headlines.append(title)
            return headlines[:8]
        except Exception:
            return []

    def _rss_scores(self, base_curr: str, quote_curr: str) -> List[float]:
        return self._score_headlines(self._rss_headlines(base_curr, quote_curr))

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

    def _openai_sentiment_report(
        self,
        symbol: str,
        base_curr: str,
        quote_curr: str,
        market_snapshot: Dict[str, Any],
        rss_headlines: List[str],
        external_scores: List[float],
    ) -> Dict[str, Any]:
        if not self._openai_enabled():
            return {}

        api_key = self._openai_api_key()
        if not api_key:
            if not self._openai_warning_emitted:
                logging.warning(
                    "OpenAI integration is enabled but %s is not set. Falling back to local sentiment providers.",
                    self._openai_settings().get("api_key_env", "OPENAI_API_KEY"),
                )
                self._openai_warning_emitted = True
            return {}

        settings = self._openai_settings()
        model = str(settings.get("model", "gpt-5.5")).strip() or "gpt-5.5"
        reasoning_effort = str(settings.get("reasoning_effort", "low")).strip() or "low"
        timeout_seconds = max(5, int(to_float(settings.get("timeout_seconds", 25), 25)))
        max_output_tokens = max(120, int(to_float(settings.get("max_output_tokens", 220), 220)))
        base_url_env = str(settings.get("base_url_env", "OPENAI_BASE_URL"))
        base_url = os.getenv(base_url_env, "https://api.openai.com/v1").strip().rstrip("/")
        endpoint = base_url if base_url.endswith("/responses") else f"{base_url}/responses"

        prompt_payload = {
            "task": "Assess short-horizon adverse-news and sentiment risk for the trading symbol.",
            "symbol": symbol,
            "base_currency": base_curr,
            "quote_currency": quote_curr,
            "market_snapshot": market_snapshot,
            "rss_headlines": rss_headlines[:8],
            "external_sentiment_scores": [round(float(x), 4) for x in external_scores[:12]],
            "timestamp_utc": datetime.now(timezone.utc).replace(tzinfo=None).isoformat() + "Z",
        }

        request_payload: Dict[str, Any] = {
            "model": model,
            "input": json.dumps(prompt_payload, ensure_ascii=False),
            "instructions": (
                "You are a risk analyst for an automated MetaTrader strategy. "
                "Return only a compact JSON object with keys "
                "sentiment_score, killswitch, confidence, risk_bias, summary. "
                "sentiment_score must be between -1 and 1. confidence must be between 0 and 1. "
                "risk_bias must be one of bullish, bearish, neutral, mixed. "
                "Use neutral sentiment when evidence is weak or sparse."
            ),
            "max_output_tokens": max_output_tokens,
            "store": to_bool(settings.get("store"), False),
        }
        if reasoning_effort:
            request_payload["reasoning"] = {"effort": reasoning_effort}

        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        }
        project_env = str(settings.get("project_env", "OPENAI_PROJECT"))
        project_name = os.getenv(project_env, "").strip()
        if project_name:
            headers["OpenAI-Project"] = project_name

        org_env = str(settings.get("organization_env", "OPENAI_ORG_ID"))
        organization = os.getenv(org_env, "").strip()
        if organization:
            headers["OpenAI-Organization"] = organization

        try:
            body = json.dumps(request_payload).encode("utf-8")
            req = urllib.request.Request(endpoint, data=body, headers=headers, method="POST")
            raw = urllib.request.urlopen(req, timeout=timeout_seconds).read().decode("utf-8")
            response_payload = json.loads(raw)
            text = self._extract_response_text(response_payload)
            parsed = self._extract_first_json_object(text)
            if not parsed:
                logging.warning("OpenAI response for %s did not contain parseable JSON.", symbol)
                return {}

            summary = str(parsed.get("summary", "")).strip()
            return {
                "provider": "openai_responses",
                "model": model,
                "reasoning_effort": reasoning_effort,
                "sentiment_score": max(-1.0, min(1.0, to_float(parsed.get("sentiment_score"), 0.0))),
                "killswitch": to_bool(parsed.get("killswitch"), False),
                "confidence": max(0.0, min(1.0, to_float(parsed.get("confidence"), 0.0))),
                "risk_bias": str(parsed.get("risk_bias", "neutral")).strip().lower() or "neutral",
                "summary": summary[:180],
            }
        except Exception as exc:
            logging.warning("OpenAI sentiment call failed for %s: %s", symbol, exc)
            return {}

    def precompute_indicators(self, df: pd.DataFrame, params: Dict) -> Dict[str, Dict[float, pd.Series]]:
        cache = {"ema": {}, "adx": {}, "box": {}}

        all_ma = sorted(set(gen_range(params["MA1"]) + gen_range(params["MA2"])) )
        for p in all_ma:
            cache["ema"][p] = indicator_ema(df["close"], length=int(p))

        for p in gen_range(params["ADX_P"]):
            cache["adx"][p] = indicator_adx(df["high"], df["low"], df["close"], length=int(p))

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
            logging.warning("Optimization skipped for %s: no market data", symbol)
            return SymbolResult(symbol, {}, -9999.0)

        params = self.cfg["param_ranges"]
        cache = self.precompute_indicators(df, params)
        logging.info("Indicators precomputed for %s", symbol)
        market_snapshot = self._summarize_market_snapshot(df)
        nlp_killswitch, ai_report = self.fetch_news_sentiment(symbol, market_snapshot)
        logging.info("Sentiment complete for %s | killswitch=%s provider=%s",
                     symbol, nlp_killswitch, ai_report.get("provider", "") if ai_report else "")

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
            logging.warning("Optimization skipped for %s: parameter grid is empty", symbol)
            return SymbolResult(symbol, {}, -9999.0)

        logging.info("Optimization grid ready for %s | combinations=%s", symbol, total)

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

        if best and ai_report:
            best["AI_Provider"] = str(ai_report.get("provider", ""))
            best["AI_Model"] = str(ai_report.get("model", ""))
            best["AI_ReasoningEffort"] = str(ai_report.get("reasoning_effort", ""))
            best["AI_SentimentScore"] = round(to_float(ai_report.get("sentiment_score"), 0.0), 4)
            best["AI_Confidence"] = round(to_float(ai_report.get("confidence"), 0.0), 4)
            best["AI_RiskBias"] = str(ai_report.get("risk_bias", "neutral"))
            best["AI_Killswitch"] = to_bool(ai_report.get("killswitch"), False)
            best["AI_Summary"] = str(ai_report.get("summary", ""))[:180]

        sys.stdout.write("\r" + " " * 100 + "\r")
        if best:
            logging.info(
                "Optimization result ready for %s | score=%.4f trades=%s max_dd=%s ma=%s/%s adx=%s min=%.2f box=%s delta=%.2f grid=%.2f killswitch=%s",
                symbol,
                best_score,
                best.get("Trades", 0),
                best.get("MaxDrawdown", 0),
                best.get("MA1_Period", 0),
                best.get("MA2_Period", 0),
                best.get("ADX_Period", 0),
                float(best.get("ADX_MinLevel", 0.0)),
                best.get("Box_Lookback", 0),
                float(best.get("CurrencyStrengthDelta", 0.0)),
                float(best.get("GridMultiplier", 0.0)),
                best.get("NLP_Killswitch", False),
            )
        else:
            logging.warning("Optimization completed for %s but no viable parameter set was found", symbol)

        return SymbolResult(symbol, best, best_score)

    def write_outputs(self, result: SymbolResult) -> None:
        if not result.best_params:
            return

        data_dir = self.cfg["mt5_data_dir"] or os.getcwd()
        os.makedirs(data_dir, exist_ok=True)
        prefix = self.cfg.get("shadow_config_prefix", "ShadowConfig")
        out_path = os.path.join(data_dir, f"{prefix}_{result.symbol}.json")
        tmp_path = f"{out_path}.{os.getpid()}.tmp"

        with open(tmp_path, "w", encoding="utf-8") as f:
            json.dump(result.best_params, f, indent=2)
        os.replace(tmp_path, out_path)
        logging.info("Shadow config written for %s | file=%s", result.symbol, out_path)

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
            logging.info("SQLite shadow_params inserted for %s | db=%s score=%.4f",
                         symbol, db, float(params.get("Score", -9999.0)))
        finally:
            conn.close()

    def run_cycle(self) -> None:
        self._cycle_id = int(time.time())
        self._last_cycle_started_at = datetime.now(timezone.utc).replace(tzinfo=None).isoformat() + "Z"
        self._last_cycle_completed_at = ""
        self._last_results = []
        logging.info("STARTING SHADOW MASTER OPTIMIZATION CYCLE | pid=%s symbols=%s max_workers=%s",
                     os.getpid(), self.cfg.get("symbols", []), self.cfg.get("max_workers", 4))
        self.write_heartbeat("RUNNING")
        if not mt5.initialize():
            logging.error("MT5 initialize failed")
            self.write_heartbeat("MT5_INIT_FAILED")
            return

        try:
            logging.info("MT5 initialized successfully")
            futures = []
            results: List[SymbolResult] = []
            with ThreadPoolExecutor(max_workers=int(self.cfg.get("max_workers", 4))) as ex:
                for sym in self.cfg["symbols"]:
                    logging.info("Submitting optimization job for %s", sym)
                    futures.append(ex.submit(self.optimize_symbol, sym))

                for fut in as_completed(futures):
                    try:
                        res = fut.result()
                    except Exception:
                        logging.exception("Optimization job failed")
                        continue
                    results.append(res)
                    self.write_outputs(res)
                    self._last_results.append(
                        {
                            "symbol": res.symbol,
                            "has_result": bool(res.best_params),
                            "score": round(float(res.score), 4),
                            "config_file": f"{self.cfg.get('shadow_config_prefix', 'ShadowConfig')}_{res.symbol}.json"
                                           if res.best_params else "",
                            "trades": int(res.best_params.get("Trades", 0)) if res.best_params else 0,
                            "updated_at": res.best_params.get("Updated", "") if res.best_params else "",
                        }
                    )
                    self.write_heartbeat("SYMBOL_COMPLETE")
                    logging.info("Optimization job finalized for %s | has_result=%s score=%.4f",
                                 res.symbol, bool(res.best_params), res.score)

            data_dir = self.cfg["mt5_data_dir"] or os.getcwd()
            os.makedirs(data_dir, exist_ok=True)
            self._last_cycle_completed_at = datetime.now(timezone.utc).replace(tzinfo=None).isoformat() + "Z"
            logging.info("ShadowMaster runtime status updated | file=%s symbols=%s",
                         os.path.join(data_dir, "ShadowMasterRuntime.json"),
                         [r.symbol for r in results])

            print("\n" + "=" * 60)
            print("SHADOW MASTER FULL CYCLE COMPLETE")
            print("=" * 60 + "\n")
            self.write_heartbeat("CYCLE_COMPLETE")

        finally:
            mt5.shutdown()
            self.write_heartbeat("IDLE")


def main() -> None:
    config_path = ""
    if len(sys.argv) > 1:
        config_path = sys.argv[1]

    cfg = load_config(config_path)
    setup_logging(cfg)
    validate_runtime_contract(cfg)
    logging.info("ShadowMaster runtime loaded | config=%s mt5_data_dir=%s sqlite=%s cycle_hours=%s",
                 config_path or "default", cfg.get("mt5_data_dir"), cfg.get("sqlite_path"), cfg.get("cycle_hours"))
    if not acquire_shadowmaster_lock(cfg):
        return

    bot = ShadowMasterV3(cfg)
    bot.start_heartbeat_pump()
    try:
        bot.run_cycle()

        hours = int(cfg.get("cycle_hours", 6))
        if hours > 0:
            interval_seconds = max(1, hours) * 3600
            while True:
                next_run = time.time() + interval_seconds
                while time.time() < next_run:
                    bot.write_heartbeat("IDLE")
                    time.sleep(30)
                bot.run_cycle()
    finally:
        bot.stop_heartbeat_pump()


if __name__ == "__main__":
    main()

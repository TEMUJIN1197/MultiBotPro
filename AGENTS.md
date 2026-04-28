# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

MultiBotPro is a multi-symbol, multi-timeframe trading bot for MetaTrader 5 supporting three operating modes: **Standalone**, **Master**, and **Slave**. It integrates MQL5, Python AI, C++ DLL acceleration, and SQLite-based inter-process communication.

## Build Commands

```powershell
# MQL5: Compile via MetaEditor (no CLI available)
# Open .mq5/.mqh in MetaEditor and press F7

# Python: Build executables (requires PyInstaller)
pyinstaller ShadowMaster.spec          # AI backend
pyinstaller renko_fallback.spec        # Renko chart generator
pyinstaller init_database.spec         # SQLite initializer

# Installer: Requires Inno Setup 6
powershell -ExecutionPolicy Bypass -File build_installer.ps1
```

## System Architecture

### Operating Modes

| Mode | Entry Point | Role |
|------|-------------|------|
| **STANDALONE** | `MultiBotPro.mq5` | Independent single-instance trading |
| **MASTER** | `MultiBotPro.mq5` | Coordinates signals, manages risk limits, broadcasts state |
| **SLAVE** | `hedge_slave.mq5` | Mirrors Master trades, reports P/L back |

Mode is selected via `BotSystemMode` input parameter (enum: `BOT_MODE_STANDALONE`, `BOT_MODE_MASTER`, `BOT_MODE_SLAVE`).

### Component Integration Map

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         MASTER INSTANCE                                 │
│  MultiBotPro.mq5 (BOT_MODE_MASTER)                                      │
│                                                                         │
│  ┌─────────────┐    ┌──────────────┐    ┌─────────────────┐            │
│  │ OnTick()    │───▶│ CheckEntry   │───▶│ OpenTrade()    │            │
│  │ OnTimer()   │    │ Signals()    │    │ + Bridge Send   │            │
│  └─────────────┘    └──────────────┘    └─────────────────┘            │
│         │                   │                     │                      │
│         ▼                   ▼                     ▼                      │
│  ┌─────────────┐    ┌──────────────┐    ┌─────────────────┐            │
│  │ ChartFactory│    │ SignalEngine │    │ HedgeBridge     │            │
│  │ (Renko/HA)  │    │ (MA/VWAP/ADX)│    │ (SQLite/Files)  │            │
│  └─────────────┘    └──────────────┘    └─────────────────┘            │
│         │                   │                     │                      │
│         │                   │                     ▼                      │
│         │                   │         ┌─────────────────────┐          │
│         │                   │         │ MultiBotPro_v3.db   │          │
│         │                   │         │ (SQLite WAL Mode)    │          │
│         │                   │         └─────────────────────┘          │
│         │                   │                     │                      │
└─────────┼───────────────────┼─────────────────────┼──────────────────────┘
          │                   │                     │
          │                   │ IPC                 │ IPC
          ▼                   ▼                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         SLAVE INSTANCE                                  │
│  hedge_slave.mq5 (BOT_MODE_SLAVE)                                       │
│                                                                         │
│  ┌─────────────┐    ┌──────────────┐    ┌─────────────────┐            │
│  │ OnTimer()   │───▶│ Poll SQLite  │───▶│ Mirror Trade    │            │
│  │ (50ms)      │    │ / Files      │    │ + Send Feedback │            │
│  └─────────────┘    └──────────────┘    └─────────────────┘            │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                      PYTHON AI BACKEND                                  │
│  PythonApp/ShadowMaster.exe (spawned by Master on boot)                 │
│                                                                         │
│  ┌─────────────┐    ┌──────────────┐    ┌─────────────────┐            │
│  │ MT5 API     │───▶│ Indicator    │───▶│ Grid Search     │            │
│  │ (History)   │    │ Computation  │    │ Optimization    │            │
│  └─────────────┘    └──────────────┘    └─────────────────┘            │
│         │                                       │                       │
│         │              ┌──────────────────────┐│                       │
│         │              │ NLTK Sentiment (RSS) ││                       │
│         │              └──────────────────────┘│                       │
│         │                                       ▼                       │
│         │                          ┌─────────────────────┐            │
│         │                          │ shadow_params table  │            │
│         │                          │ (SQLite)             │            │
│         │                          └─────────────────────┘            │
│         │                                       │                       │
└─────────┼───────────────────────────────────────┼───────────────────────┘
          │                                       │
          ▼                                       ▼
    Master polls SQLite                 Master reads params
    every 5 seconds                    via LoadShadowConfig()
```

## Core Module Integration

### Module Dependency Graph

```
MultiBotPro.mq5
    │
    ├── MultiBotPro_Defines.mqh ──────────────────┐
    │      (enums, structs, globals)              │
    │                                              │
    ├── MultiBotPro_MasterRuntime.mqh            │
    │      (Master mode event loop)               │
    │                                              │
    ├── MultiBotPro_SlaveRuntime.mqh              │
    │      (Slave mode event loop)                │
    │                                              │
    ├── hedgeBridge.mqh ◀────────────────────────┤
    │      (shared bridge structs, SQLite API)    │
    │                                              │
    ├── MultiBotPro_Helpers.mqh                   │
    │      (time, symbol, price utils)            │
    │                                              │
    ├── MultiBotPro_ChartFactory.mqh              │
    │      ├── MultiBotPro_Renko.mqh              │
    │      ├── MultiBotPro_HeikenAshi.mqh         │
    │      ├── MultiBotPro_HeikenRenko.mqh        │
    │      └── MultiBotPro_CustomTime.mqh         │
    │                                              │
    ├── MultiBotPro_Indicators.mqh                │
    │      (MA, ATR, VWAP, ADX calculations)      │
    │                                              │
    ├── MultiBotPro_SignalEngine.mqh               │
    │      (entry signal aggregation)             │
    │                                              │
    ├── MultiBotPro_TradeEntry.mqh                 │
    │      (signal validation → execution)        │
    │                                              │
    ├── MultiBotPro_GridZone.mqh                   │
    │      (grid/zone recovery management)        │
    │                                              │
    ├── MultiBotPro_Risk.mqh                       │
    │      (position sizing, lot calculation)    │
    │                                              │
    ├── MultiBotPro_TradeManager.mqh               │
    │      (trailing, SL/TP management)           │
    │                                              │
    ├── MultiBotPro_Dashboard.mqh                  │
    │      (GUI panel rendering)                  │
    │                                              │
    ├── MultiBotPro_GUI.mqh                        │
    │      (manual trading controls)              │
    │                                              │
    ├── MultiBotPro_VisualOverlay.mqh              │
    │      (chart drawings, lines)               │
    │                                              │
    ├── MultiBotPro_HedgeBridge.mqh                │
    │      (extended bridge, V3 SQLite)          │
    │                                              │
    └── MultiBotPro_PythonBridge.mqh              
           (ShadowMaster spawn/IPC)
```

### Data Flow: Tick to Trade

```
OnTick(symbol)
    │
    ├── Gate Checks
    │   ├── G_BridgePending.active/approved? ──▶ Return (waiting on Slave)
    │   ├── G_Cache_SystemBlocked? ──▶ Return (hedge limit hit)
    │   ├── G_Cache_IsTradingTime? ──▶ Return (outside hours)
    │   └── G_Cache_IsNewsTime? ──▶ Return (news blackout)
    │
    ├── Tick Gatekeeper
    │   └── MasterPrepareSymbolTick() ──▶ Check for new price data
    │
    ├── Chart Processing (if synthetic mode)
    │   └── CChartFactory.ProcessTick() ──▶ Update Renko/Heiken bars
    │
    ├── Indicator Update
    │   ├── UpdateBoxLevels() ──▶ Swing high/low tracking
    │   ├── UpdateVWAP() ──▶ VWAP 1/2/3 calculation
    │   └── UpdateCurrencyStrength() ──▶ Cross-currency matrix
    │
    ├── Position Tracking
    │   └── UpdatePositionTracking() ──▶ Sync SymbolData with MT5 positions
    │
    ├── Signal Detection
    │   └── CheckEntrySignals(symbolIndex)
    │       ├── CheckMABuySignal() / CheckMASellSignal()
    │       │   └── 5-MA cascade (fast→slow alignment check)
    │       ├── CheckVWAPBuySignal() / CheckVWAPSellSignal()
    │       ├── CheckADXFilter() ──▶ Trend strength threshold
    │       ├── CheckBoxTrend() ──▶ Breakout confirmation
    │       ├── GetCurrencyStrength() ──▶ Pair strength delta
    │       └── AI Override (if ShadowMaster active)
    │           ├── Dyn_CurrencyStrengthDelta
    │           ├── Dyn_GridMultiplier
    │           ├── Dyn_NLP_Killswitch (sentiment block)
    │           └── Dyn_ADX_MinLevel
    │
    ├── Trade Execution
    │   └── OpenTrade()
    │       ├── CalculateLotSize() [Risk.mqh]
    │       │   ├── Risk type: FIXED_MONEY, PERCENT_EQUITY, PERCENT_BALANCE
    │       │   ├── Grid mode: Use RawNextGridLot
    │       │   └── Zone mode: FixedLot × CurrentStakeMultiplier
    │       ├── CTrade.PositionOpen()
    │       └── Bridge Signal Send (if Master mode)
    │           ├── V3_InsertSignalRow() ──▶ SQLite
    │           └── G_SignalQueue[] push
    │
    └── Trade Management (per-symbol loop)
        ├── ManageAllPositionsOnTick()
        │   ├── Normal mode: Trailing SL/TP
        │   ├── Grid mode: Phase 1/Phase 2 management
        │   └── Zone mode: Recovery sequence
        ├── CheckStackTradesOnTick() ──▶ Add positions on SL distance
        └── ManageRisk() ──▶ Daily loss limits
```

## Master/Slave Bridge Protocol

### SQLite Schema (see `sqlite_schema.sql`)

| Table | Purpose |
|-------|---------|
| `signals` | Trade signals (Master → Slave) |
| `proposals` | Async handshake proposals |
| `replies` | Slave approvals/rejections |
| `feedback` | Execution results (Slave → Master) |
| `state_master` | Master equity, P/L, limits |
| `state_slave` | Slave equity, P/L |
| `shadow_params` | AI-optimized parameters per symbol |
| `debt_ledger` | Pruning loss tracking |

### Async Handshake Flow

```
Master wants to open trade:
    │
    ├── Create HedgeSignal struct
    ├── Write to proposals table
    ├── Set G_BridgePending.active = true
    │
    ▼
Slave polls proposals (50ms interval):
    │
    ├── Read proposal from SQLite
    ├── Validate (equity, risk limits)
    ├── Write approval/rejection to replies
    │
    ▼
Master reads reply:
    │
    ├── If approved: Execute trade, clear pending
    └── If rejected: Abort, clear pending
```

### State Synchronization

Master writes to `state_master` every timer tick (500ms):
- `master_current_equity`
- `master_start_equity`
- `master_daily_limit`
- `is_daily_stopped`
- `is_total_stopped`
- `is_paused`

Slave reads and mirrors these limits, applying local risk controls.

## Python ShadowMaster Integration

### Boot Sequence

1. Master calls `BootShadowMaster()` in `OnInit`
2. Spawns `PythonApp/ShadowMaster.exe` via `ShellExecuteW`
3. Python loads config from `runtime_v3.json`
4. Connects to MT5 via `MetaTrader5` Python package
5. Runs optimization cycle every `cycle_hours`

### Parameter Injection

ShadowMaster writes to `shadow_params` table:

```sql
INSERT INTO shadow_params (symbol, payload_json, score, updated_at)
VALUES ('EURUSD_ATR', '{"MA1":15,"MA2":40,"BOX":4,"ADX_P":14,"ADX_L":25.0,"DELTA":6.0}', 0.85, datetime('now'))
```

Master reads via `LoadShadowConfig()`:

```mql5
// MultiBotPro.mq5, OnTimer
if(InpEnableShadowMaster && TimeCurrent() - G_LastShadowSyncCheck > 5) {
    for(int i = 0; i < TradingSymbolsCount; i++) {
        LoadShadowConfig(TradingSymbols[i]);
    }
}
```

Dynamic parameters stored in `SymbolData[symbolIndex].Dyn_*` fields:
- `Dyn_MA1_Period`, `Dyn_MA2_Period`
- `Dyn_Box_Lookback`
- `Dyn_ADX_Period`, `Dyn_ADX_MinLevel`
- `Dyn_CurrencyStrengthDelta`
- `Dyn_GridMultiplier`
- `Dyn_NLP_Killswitch`

### NLP Killswitch

When sentiment analysis detects adverse news:

```mql5
// MultiBotPro_TradeEntry.mqh
if(aiActive && nlpBlocked) {
    Comment("🧠 NLP killswitch: adverse news sentiment detected. Trading halted.");
    return;
}
```

## C++ DLL Integration

### Import Declaration

```mql5
// MultiBotPro_Defines.mqh
#import "::Libraries\\accel.dll"
   int TestConnection(int value);
   bool ProcessRenkoTicks(const double &pTicks[], int tickCount, 
                          double boxSize, double &pOutBoxesKey[], 
                          int &pOutCount[], int maxBoxes);
   double CalculateGridMath(double startLevel, double multiplier, int maxLevels);
#import
```

### Usage

- **ProcessRenkoTicks**: Batch tick-to-brick conversion for Renko charts
- **CalculateGridMath**: Grid lot progression math
- **TestConnection**: DLL heartbeat check

**Note**: Native MQL5 implementations in `MultiBotPro_Renko.mqh` serve as primary; DLL is optional acceleration.

## Synthetic Chart Engines

### Chart Factory

```mql5
// MultiBotPro_ChartFactory.mqh
class CChartFactory {
    ENUM_CHART_MODE m_chartType;
    
    void ProcessTick(const string symbol, const MqlTick &tick, int cpuBudgetMs = 10);
    bool GetBar(int shift, SMBPCustomBar &outBar);
    void FlushBuffers();
};
```

### Chart Modes

| Mode | Engine | Description |
|------|--------|-------------|
| `MBP_CHART_STANDARD` | None | Live MT5 data |
| `MBP_CHART_RENKO` | `CRenkoEngine` | Box-based price movement |
| `MBP_CHART_HEIKEN_ASHI` | `CHeikenAshiEngine` | Smoothed candles |
| `MBP_CHART_HEIKEN_RENKO` | `CHeikenRenkoEngine` | Combined HA+Renko |
| `MBP_CHART_CUSTOM_TIME` | `CCustomTimeEngine` | Custom timeframe synthesis |

### Per-Symbol Mode

Each symbol can have independent chart mode:

```mql5
SymbolData[symbolIndex].DataMode = InpAnalysisDataMode;
```

Analysis mode enum (`ANALYSIS_NORMAL`, `ANALYSIS_SHADOW_MASTER`, `ANALYSIS_CUSTOM_ONLY`) controls whether signals come from live data, AI, or synthetic charts.

## Risk Management Strategies

### Normal Mode (`RISK_MODE_NONE`)

- Standard SL/TP
- Trailing stop activation after TP hit
- Stack positions (add on SL distance movement)

### Grid Mode (`RISK_MODE_GRID`)

- No initial SL/TP
- Martingale-style lot progression
- Basket take-profit triggers Phase 2 (trailing)
- Pruning mechanism for loss management

### Zone Recovery (`RISK_MODE_ZONE_RECOVERY`)

- Price zone boundaries (`ZoneTopPrice`, `ZoneBottomPrice`)
- Hedging positions within zone
- Profit target triggers zone resolution

### Position Sizing

```mql5
// MultiBotPro_Risk.mqh
double CalculateLotSize(int symbolIndex, double entryPrice, double stopLoss, ENUM_ORDER_TYPE orderType) {
    switch(RiskType) {
        case RISK_PERCENT_EQUITY:
            return (AccountEquity * RiskPercent / 100) / (stopDistance * tickValue);
        case RISK_PERCENT_BALANCE:
            return (AccountBalance * RiskPercent / 100) / (stopDistance * tickValue);
        case RISK_FIXED_LOT:
            return FixedLot;
        case RISK_FIXED_MONEY:
            return RiskMoney / (stopDistance * tickValue);
    }
}
```

## Event Handlers

### OnTimer (500ms interval)

```mql5
void OnTimer() {
    // 1. Bank state persistence
    // 2. License verification (every 8 hours)
    // 3. Strategy tester chart management
    // 4. Reset processing
    // 5. Dashboard UI refresh
    // 6. VWAP daily rollover (5 PM NY)
    // 7. Shadow Master config sync (every 5 seconds)
    // 8. Hedge Master state processing
    // 9. System state caching
}
```

### OnChartEvent

- Button clicks: `MAN_BTN_BUY`, `MAN_BTN_SELL`, `MAN_BTN_CLOSE`
- Keyboard: 'L' toggles trade list, 'P' toggles pause
- Drag-and-drop: Dashboard panel repositioning

### OnTradeTransaction

- Captures MT5 trade events
- Creates `HedgeSignal` for Master→Slave communication
- Updates position tracking

## Key Data Structures

### SSymbolData (Per-Symbol State)

```mql5
struct SSymbolData {
    // Identity
    string symbol;
    int BasketId;
    ENUM_CHART_MODE DataMode;
    
    // Indicators
    int MA_Handles[5][7];  // 5 MAs × 7 timeframes
    int ATR_Handle, ADX_Handle;
    SVWAPData VWAP1, VWAP2_High, VWAP2_Low, VWAP3;
    
    // Grid State
    int GridLevels;
    double GridEntries[100];
    bool GridPhase1Active, GridPhase2Active;
    double RawNextGridLot, LastUsedGridRawLot;
    
    // Zone State
    bool ZoneActive;
    double ZoneTopPrice, ZoneBottomPrice;
    int ZoneSeqCount;
    
    // AI Parameters (ShadowMaster)
    int Dyn_MA1_Period, Dyn_MA2_Period;
    int Dyn_Box_Lookback, Dyn_ADX_Period;
    double Dyn_ADX_MinLevel, Dyn_CurrencyStrengthDelta;
    double Dyn_GridMultiplier;
    bool Dyn_NLP_Killswitch;
    
    // Tracking
    ulong MasterTicket;
    double MasterSL, MasterEntry;
    SStackTracker NonGridStack, GridStack;
};
```

### HedgeState (Master→Slave State)

```mql5
struct HedgeState {
    double master_current_equity;
    double master_start_equity;
    double master_target_risk;
    double master_daily_limit;
    double master_pnl;
    double slave_pnl;
    bool is_daily_stopped;
    bool is_total_stopped;
    bool is_paused;
    ulong last_heartbeat;
    ulong reset_id;
};
```

## Input Parameter Groups

| Group | Purpose |
|-------|---------|
| 0 | Bot mode, analysis mode, compute backend |
| 0a | Synthetic chart settings (Renko/Heiken) |
| 0b | Slave mode channel, heartbeat, SQLite path |
| 1 | License key |
| 2 | Symbols, timeframes, magic number |
| 3 | Multi-basket configuration |
| 4 | Position sizing, risk type, lot limits |
| 5 | SL/TP types, trailing configuration |
| 6 | MA periods, ADX, Box, Currency Strength |
| 7 | VWAP configuration |

## File Locations

| File | Location |
|------|----------|
| Compiled EAs | Same directory as source (.ex5) |
| SQLite DB | `MQL5/Files/MultiBotPro_v3.db` |
| Bridge files | `MQL5/Files/Hedge*.bin` |
| Shadow config | `MQL5/Files/ShadowSync.json` |
| Python EXEs | `PythonApp/ShadowMaster.exe` |
| C++ DLL | `Libraries/accel.dll` (relative to MQL5) |

## External Dependencies

- **accel.dll**: C++ acceleration for Renko/Grid calculations
- **kernel32.dll**: Windows file operations
- **MetaTrader5 (Python)**: MT5 API for ShadowMaster
- **pandas_ta**: Technical indicators in Python
- **nltk**: Sentiment analysis (VADER)
- **SQLite3**: Inter-process communication
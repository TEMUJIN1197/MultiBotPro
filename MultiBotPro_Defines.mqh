#ifndef __MULTIBOTPRO_DEFINES_MQH__
#define __MULTIBOTPRO_DEFINES_MQH__
//+------------------------------------------------------------------+
//|                                          MultiBotPro_Defines.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://discord.com/channels/929723953415589918/929723953415589920"

#include <Arrays\ArrayObj.mqh>

#ifndef MBP_MAX_BASKETS
#define MBP_MAX_BASKETS 100
#endif

#define DASH_BUTTON_HANDOFF_MS 250
#define DASH_HEARTBEAT_CYCLE_MS 3000
#define DASH_HEARTBEAT_ACTIVE_MS 1500
#define DASH_HEARTBEAT_BLINK_MS 250
#define DASH_DRAG_THRESHOLD_PX 5

class CChartFactory;

// --- ENGINE ENUMS (Canonical definitions) ---
enum ENUM_BOT_MODE {
   BOT_MODE_STANDALONE, // Standalone Mode
   BOT_MODE_MASTER,     // Master Mode
   BOT_MODE_SLAVE       // Slave Mode
};

enum ENUM_MBP_RUNTIME_ROLE
{
   MBP_RUNTIME_LEGACY,      // Direct trading runtime
   MBP_RUNTIME_COORDINATOR, // Coordinator switch runtime, no trading loop
   MBP_RUNTIME_WORKER       // Internal spawned worker runtime
};

enum ENUM_ANALYSIS_DATA_MODE {
   ANALYSIS_NORMAL,        // Live Market Data
   ANALYSIS_SHADOW_MASTER, // AI Shadow Master Signals
   ANALYSIS_CUSTOM_ONLY    // Synthetic Chart Only
};

enum ENUM_MBP_DATA_MODE
{
   MBP_DATA_LIVE,          // Base/live broker chart
   MBP_DATA_RENKO,         // Classic Renko
   MBP_DATA_MEDIAN_RENKO,  // Median Renko
   MBP_DATA_TURBO_RENKO,   // Turbo Renko
   MBP_DATA_HYBRID_RENKO,  // Hybrid Renko
   MBP_DATA_HEIKEN_ASHI,   // Heiken Ashi
   MBP_DATA_HEIKEN_RENKO,  // Heiken Renko
   MBP_DATA_CUSTOM_TIME    // Custom timeframe
};

enum ENUM_COMPUTE_BACKEND {
   COMPUTE_BACKEND_DLL,    // C++ Optimized DLL
   COMPUTE_BACKEND_PYTHON, // Shadow Master AI
   COMPUTE_BACKEND_NATIVE  // Native MQL5
};

enum ENUM_APP_MODE {  // Legacy Alias support
   APP_MODE_MASTER,
   APP_MODE_SLAVE
};

enum ENUM_START_MODE 
{ 
   MODE_DAYS_BACK, // Days Back
   MODE_FIXED_DATE // Fixed Date
};

enum ENUM_HISTORY_DATA_TYPE 
{ 
   DATA_M1,   // M1 OHLC (Fast)
   DATA_TICK, // Real Ticks (Accurate but Slow)
   DATA_HYBRID // M1 Deep + Ticks Recent (Best of both)
};

enum ENUM_BLOCK_MODE 
{ 
   BLOCK_MODE_POINTS,      // Points
   BLOCK_MODE_PIPS,        // Pips
   BLOCK_MODE_ATR_PERCENT  // ATR %
};

// Global Safety Flag moved to Globals.mqh

// --- SYNTHETIC CHART RATE STRUCTURE ---
struct SMBPCustomBar
{
   datetime time;
   double   open;
   double   high;
   double   low;
   double   close;
   long     tick_volume;
};

// --- MANUAL TRADING GLOBALS ---
#define PREFIX_MANUAL   "MAN_"
#define MAN_BTN_BUY     "MAN_BTN_BUY"
#define MAN_BTN_SELL    "MAN_BTN_SELL"
#define MAN_BTN_CLOSE   "MAN_BTN_CLOSE"
#define MAN_BTN_LOT_P   "MAN_BTN_LOT_P"   // Plus
#define MAN_BTN_LOT_M   "MAN_BTN_LOT_M"   // Minus
#define MAN_EDIT_LOT    "MAN_EDIT_LOT"    // Display
#define BTN_PREFIX_LIST "TRD_LST_"        // Prefix for the list of trades
#define BTN_PREFIX_MOD  "TRD_MOD_"        // Prefix for the modification UI
#define MBV_PREFIX      "MBV_"            // Prefix for indicator overlay objects

// Definitions for the Modifier UI Buttons
#define MP_BTN_SL_P    "MP_BTN_SL_P"
#define MP_BTN_SL_M    "MP_BTN_SL_M"
#define MP_BTN_SL_PP   "MP_BTN_SL_PP"
#define MP_BTN_SL_MM   "MP_BTN_SL_MM"
#define MP_BTN_TP_P    "MP_BTN_TP_P"
#define MP_BTN_TP_M    "MP_BTN_TP_M"
#define MP_BTN_TP_PP   "MP_BTN_TP_PP"
#define MP_BTN_TP_MM   "MP_BTN_TP_MM"
#define MP_BTN_CONFIRM "MP_BTN_CONFIRM"
#define MP_BTN_CANCEL  "MP_BTN_CANCEL"
#define MP_HL_SL       "MP_HL_SL"
#define MP_HL_TP       "MP_HL_TP"

// --- ENUMS --- //

// --- CHART MODE ENUM ---
enum ENUM_MBP_CHART_MODE
{
   MBP_CHART_STANDARD,      // Standard Chart
   MBP_CHART_RENKO,         // Renko Chart
   MBP_CHART_HEIKEN_ASHI,   // Heiken Ashi Chart
   MBP_CHART_HEIKEN_RENKO,  // Heiken Renko Chart
   MBP_CHART_CUSTOM_TIME,   // Custom Timeframe Chart
   MBP_CHART_MEDIAN_TURBO,  // AZ-Invest Style (Filters Phantom/Gap Bars)
   MBP_CHART_AUTO           // Auto-detect based on volume patterns (Advanced)
};

#define ENUM_RENKO_MODE ENUM_MBP_CHART_MODE
#define RENKO_MODE_AUTO MBP_CHART_AUTO
#define RENKO_MODE_STANDARD MBP_CHART_STANDARD
#define RENKO_MODE_MEDIAN_TURBO MBP_CHART_MEDIAN_TURBO

enum ENUM_MBP_RENKO_FAMILY
{
   MBP_RENKO_CLASSIC,
   MBP_RENKO_MEDIAN,
   MBP_RENKO_TURBO,
   MBP_RENKO_HYBRID
};

enum ENUM_MBP_RENKO_LIVE_STYLE
{
   MBP_RENKO_LIVE_SMALL_PHANTOM = 0,
   MBP_RENKO_LIVE_LARGE_DIRECT = 1
};

// --- ENUMS FOR HEDGE MASTER ---
enum ENUM_RISK_MODE_MASTER {
   RISK_STATIC,      // Static Max Drawdown
   RISK_TRAILING     // Trailing Max Loss
};

enum ENUM_TRAIL_BASE {
   TRAIL_BALANCE,    // Based on Balance
   TRAIL_EQUITY,     // Based on Equity
   TRAIL_MAX_BAL_EQ  // Max of Balance or Equity
};

enum ENUM_MY_MA_SOURCE 
   {
   MY_SRC_CLOSE,  //Close
   MY_SRC_OPEN,   //Open
   MY_SRC_HIGH,   //High
   MY_SRC_LOW,    //Low
   MY_SRC_HL2,    //HL/2
   MY_SRC_HLC3,   //HLC/3
   MY_SRC_OHLC4   //OHLC/4
   };
enum ENUM_MY_MA_METHOD 
   {
   MY_MODE_EMA,   //EMA
   MY_MODE_SMA,   //SMA
   MY_MODE_SMMA,  //SMMA
   MY_MODE_LWMA,  //LWMA
   MY_MODE_VWMA   //VMWMA
   };
enum ENUM_RISK_MODE
  {
   RISK_MODE_NONE,          // Normal SL/TP
   RISK_MODE_GRID,          // Grid Mode
   RISK_MODE_ZONE_RECOVERY  // Zone Recovery
  };

enum ENUM_GRID_STRATEGY
   {
   GRID_STRAT_CONSERVATIVE, // Standard Multiplier
   GRID_STRAT_AGGRESSIVE    // Math-based Retracement Target
   };

enum ENUM_ZONE_GAP_TYPE
  {
   ZONE_GAP_POINTS,        // Fixed Points
   ZONE_GAP_ATR            // ATR Multiplier
  };

enum ENUM_TP_TYPE 
   {
   TP_FIXED,               // Take Profit Points
   TP_RR,                  // Take profit R/R
   TP_ATR                  // Take profit ATR
   };
   
enum ENUM_SL_TYPE 
   {
   SL_NONE,                // No Stop Loss
   SL_ATR,                 // Use ATR Stop-Loss
   SL_BOX,                 // Use Swing Stop-Loss
   SL_MA                   // Use Moving Average Stop-Loss
   };

enum ENUM_TRAIL_TYPE 
   {
   TRAIL_BOX,              // Trail with Swings
   TRAIL_ATR,              // Trail with ATR
   TRAIL_POINTS            // Trail with Points
   };

enum ENUM_RISK_TYPE
{
   RISK_PERCENT_EQUITY,
   RISK_PERCENT_BALANCE,
   RISK_FIXED_LOT,
   RISK_FIXED_MONEY
};

enum ENUM_GRID_DISTANCE_TYPE
{
   GRID_DIST_POINTS,       // Points
   GRID_DIST_ATR           // ATR multiples
};

// --- NEW BASKET SL SETTINGS (CONSOLIDATED) ---
enum ENUM_GRID_BASKET_CALC
{
   GRID_BASKET_ATR,        // Calculate using ATR Multiplier
   GRID_BASKET_POINTS      // Calculate using Points
};

enum ENUM_LOCK_TRAIL
{
   LOCK_TRAIL_NONE,        // No Lock
   LOCK_TRAIL_BREAK_EVEN,  // Lock until Break Even
   LOCK_TRAIL_TP_HIT       // Lock until TP Hit
};

enum ENUM_OP_MODE
{
   MODE_AUTO,              // Bot takes entries & manages trades (Default)
   MODE_SEMI_AUTO,         // User enters manually, Bot manages risk/grid/zone
   MODE_MIXED              // Bot can enter, User can enter, Bot manages all
};

enum ENUM_ENTRY_GATE_REASON
{
   ENTRY_GATE_UNKNOWN,
   ENTRY_GATE_READY,
   ENTRY_GATE_NO_SYMBOLS,
   ENTRY_GATE_NOT_TRACKED,
   ENTRY_GATE_SYSTEM_BLOCKED,
   ENTRY_GATE_HARD_BLOCK,
   ENTRY_GATE_SESSION_BLOCKED,
   ENTRY_GATE_NEWS_BLOCKED,
   ENTRY_GATE_SEMI_AUTO,
   ENTRY_GATE_BRIDGE_PENDING,
   ENTRY_GATE_HEDGE_BLOCKED,
   ENTRY_GATE_GLOBAL_COOLDOWN,
   ENTRY_GATE_FILTER_STOP,
   ENTRY_GATE_MAX_OPEN_TRADES,
   ENTRY_GATE_PAUSED,
   ENTRY_GATE_NLP_BLOCK,
   ENTRY_GATE_POSITION_ACTIVE,
   ENTRY_GATE_NOT_PRIMARY_BASKET,
   ENTRY_GATE_SPREAD_BLOCKED,
   ENTRY_GATE_MA_SIGNAL,
   ENTRY_GATE_VWAP_SIGNAL,
   ENTRY_GATE_ADX_FILTER,
   ENTRY_GATE_BOX_FILTER,
   ENTRY_GATE_MACRO_FILTER,
   ENTRY_GATE_SIGNAL_STACK,
   ENTRY_GATE_BASKET_LIMIT,
   ENTRY_GATE_BASKET_DIRECTION,
   ENTRY_GATE_BASKET_DISTANCE
};

enum ENUM_FILTER_RESET
{
   FILTER_RESET_DAILY,   // Reset every new day (00:00)
   FILTER_RESET_SESSION  // Reset at Session Start
};

enum ENUM_PRUNING_STYLE
{
   PRUNING_SOFT, // Close only the oldest trade (FIFO)
   PRUNING_HARD  // Close entire sequence/basket (Reset)
};

enum ENUM_BOX_BREAKOUT_SRC
{
   BOX_BREAK_CLOSE,    // Close Price (Standard)
   BOX_BREAK_HIGHLOW   // High/Low (Wicks)
};
      
// --- STRUCTS --- //

// Stack Tracking Structure
struct SStackTracker
{
   int               Counter;                    // Current stack counter value
   int               LastProcessedCounter;       // Last counter value we processed
   bool              SLMovedThisTick;           // Flag if SL moved this tick
   datetime          LastSLMoveTime;        // Last time SL moved
   double            LastSLPrice;             // Last SL price
};

// VWAP Data Structure
struct SVWAPData
{
   double            Value;                   // Current VWAP value
   double            CumulativeVolume;        // Cumulative volume
   double            CumulativePV;            // Cumulative price * volume
   datetime          LastResetTime;         // Last reset time
   datetime          StartTime;             // Start time for this VWAP session
   double            SessionHigh;             // Session high (for VWAP2)
   double            SessionLow;              // Session low (for VWAP2)
   bool              Initialized;               // Flag if VWAP is initialized
};

// Trade position structure
struct STradePosition
{
   ulong             ticket;
   double            entry_price;
   double            stop_loss;
   double            take_profit;
   double            volume;
   ENUM_POSITION_TYPE type;
   datetime          open_time;
   double            current_profit;
};

// ============================================================================
// BASKET-LEVEL STATE TRACKING CLASS (NEW - Phase 1)
// ============================================================================
// Tracks grid phases and zone state per (BasketId, Symbol) combination.
// Stored as pointer array in SSymbolData so individual basket states can be
// referenced via SBasketState* pointers (MQL5 requires class for pointer semantics).
class SBasketState
{
public:
   int    BasketId;              // Unique basket identifier
   bool   GridPhase1Active;      // True when in initial grid mode (no SL/TP)
   bool   GridPhase2Active;      // True when grid basket profit reached and in trailing mode
   double ZoneTopPrice;          // Upper Boundary (Buy Trigger) for zone recovery
   double ZoneBottomPrice;       // Lower Boundary (Sell Trigger) for zone recovery
   double ZoneNextLot;           // Calculated lot for the next hedge in zone recovery
   int    ZoneSeqCount;          // Number of recovery trades placed in zone sequence
   bool   ZoneActive;            // Is a Zone Recovery sequence running?
   bool   ZoneResolved;          // Flag when zone target logic is met
   double CurrentRecoveryPortion;// Portion of accumulated pruning loss allocated to this basket
   double GridTargetProfit;      // Profit target for this basket (including recovery portion)
   bool   GridTPHit;             // Has the zone/grid impulse or dollar target been hit?
   double GridTPHitPrice;        // The price where the zone/grid TP was marked
   bool   GridTargetReached;     // True when grid target was hit and transition is pending/complete
   bool   GridInTrailing;        // Basket-specific phase 2 trailing switch
   bool   GridInStacking;        // Basket-specific phase 2 stacking switch
   double GridBasketStopLoss;    // Basket-specific secured/trailing SL
   double PendingTrailSL;        // Pending SL calculated for this basket
   bool   HasPendingTrail;       // True when PendingTrailSL must be applied
   int    GridStackLevels;       // Number of stack trades opened for this basket
   int    GridTrailUpdates;      // Number of basket SL trail updates
   double LastStackLot;          // Previous grid/zone stack lot for this basket
   double LastStackMult;         // Previous grid/zone stack multiplier
   SStackTracker GridStack;      // Basket-specific grid/zone stack counter

   // Constructor — zero-initializes all fields
   SBasketState()
   {
      BasketId              = -1;
      GridPhase1Active      = false;
      GridPhase2Active      = false;
      ZoneTopPrice          = 0.0;
      ZoneBottomPrice       = 0.0;
      ZoneNextLot           = 0.0;
      ZoneSeqCount          = 0;
      ZoneActive            = false;
      ZoneResolved          = false;
      CurrentRecoveryPortion = 0.0;
      GridTargetProfit      = 0.0;
      GridTPHit             = false;
      GridTPHitPrice        = 0.0;
      GridTargetReached     = false;
      GridInTrailing        = false;
      GridInStacking        = false;
      GridBasketStopLoss    = 0.0;
      PendingTrailSL        = 0.0;
      HasPendingTrail       = false;
      GridStackLevels       = 0;
      GridTrailUpdates      = 0;
      LastStackLot          = 0.0;
      LastStackMult         = 1.0;
      GridStack.Counter = 0;
      GridStack.LastProcessedCounter = 0;
      GridStack.SLMovedThisTick = false;
      GridStack.LastSLMoveTime = 0;
      GridStack.LastSLPrice = 0.0;
   }
};

// ============================================================================
// WORKER/COORDINATOR COMMUNICATION STRUCTS (NEW - Phase 1)
// ============================================================================

// Worker Assignment (Coordinator → Worker via global variable)
struct SWorkerAssignment
{
   string symbol;                 // Assigned symbol (e.g., "EURUSD")
   int    workerChartId;          // Chart ID of the worker EA
   int    workerIndex;            // Index in coordinator's worker list (0-based)
   int    totalWorkers;           // Total number of workers spawned
   bool   isMultiSymbol;          // True if this worker handles multiple symbols
};

// Worker Status Report (Worker → Coordinator via global variable)
struct SWorkerStatus
{
   int    workerId;               // Worker chart ID or identifier
   string symbol;                 // Primary assigned symbol
   bool   isAlive;                // Heartbeat flag
   double equity;                 // Current equity of worker
   double pnl;                    // Current P&L of worker
   int    activePositions;        // Number of open positions
   int    gridLevel;              // Current grid level (0 if no grid active)
   int    zoneSeqCount;           // Current zone sequence count (0 if no zone active)
   ulong  lastHeartbeat;          // Timestamp of last status update (Unix milliseconds)
};

// Coordinator System State (Coordinator → All Workers via global variable)
struct SCoordinatorState
{
   double totalEquity;            // Aggregated equity across all workers
   double totalBalance;           // Aggregated balance
   double dailyLoss;              // Current daily P&L (negative = loss)
   double maxDrawdown;            // Maximum observed drawdown from session start
   bool   isPaused;               // Pause all workers flag
   bool   isDailyLimitHit;        // Daily loss limit breached
   bool   isTotalLimitHit;        // Total system limit breached
   ulong  lastUpdate;             // Timestamp of last coordinator update (Unix milliseconds)
};

// --- Step 2b: Shard constants (centralize the 6 hardcoded [100] caps) ---
#ifndef MBP_MAX_BOX_LEVELS
#define MBP_MAX_BOX_LEVELS 100
#endif
#ifndef MBP_MAX_GRID_LEVELS
#define MBP_MAX_GRID_LEVELS 100
#endif
#ifndef MBP_MAX_OPEN_POSITIONS
#define MBP_MAX_OPEN_POSITIONS 100
#endif

// Box warmup phase (replaces flat 9 bool/int/ulong fields with one enum + struct)
enum ENUM_MBP_BOX_WARMUP_PHASE
{
   MBP_WARMUP_IDLE = 0,
   MBP_WARMUP_QUEUED = 1,
   MBP_WARMUP_IN_PROGRESS = 2,
   MBP_WARMUP_DONE = 3
};

// Step 2b: Named sub-views of SSymbolData (header-only, binary-compatible).
// SSymbolData keeps legacy flat members for compat; these structs give
// a stable domain API for Coordinator/Indicator/Grid call sites.
// Layout intentionally mirrors the flat member order for 1:1 future migration.
struct SMarketIdentity { string symbol; string BaseSymbol; string AnalysisSymbol; bool active; int BasketId; bool IsPrimaryBasket; bool BasketActive; ENUM_MBP_DATA_MODE DataMode; ENUM_MBP_RENKO_FAMILY RenkoFamily; };
struct SIndicatorHandles { int MA_Handles[5][7]; int ATR_Handle; int MA_SL_Handle; int ADX_Handle; };
struct SVWAPBundle { SVWAPData VWAP1; SVWAPData VWAP2_High; SVWAPData VWAP2_Low; SVWAPData VWAP3; };
struct SBoxLevelState { double BoxHigh[MBP_MAX_BOX_LEVELS]; double BoxLow[MBP_MAX_BOX_LEVELS]; int BoxHighCount; int BoxLowCount; datetime BoxHighStartTime; datetime BoxLowStartTime; };
struct SGridTradeState { double OriginalBalance; double CurrentStakeMultiplier; int GridLevels; double GridEntries[MBP_MAX_GRID_LEVELS]; double StackMultiplier; int StackUpdates; int TrailUpdateCount; double LastSLPrice; STradePosition OpenPositions[MBP_MAX_OPEN_POSITIONS]; int PositionCount; datetime LastTradeTime; double DailyProfitLoss; datetime LastDailyReset; };
struct SGridPhaseState { bool GridTargetReached; bool GridInTrailing; bool GridInStacking; double GridBasketStopLoss; double GridBasketTakeProfit; double GridBasketEntry; double GridBasketVolume; double GridTargetProfit; double RawNextGridLot; double LastUsedGridRawLot; double RawNextStackLot; double LastUsedStackRawLot; int GridStackLevels; int GridTrailUpdates; double GridStackMultiplier; bool StackLastTrailUpdate; datetime LastStackTime; double LastStackSL; bool TrailLocked; double LockBreakEvenPrice; bool LockTPReached; SStackTracker NonGridStack; SStackTracker GridStack; double StackPrevSL; bool StackSLInitialized; double GridStackPrevSL; bool GridStackSLInitialized; int StackLastOpenedCounter; int GridStackLastOpenedCounter; int CurrentGridSequence; datetime LastGridReset; double GridStakeMultiplier; double LastStackLot; double LastStackMult; int GridSequenceDepth; bool GridPhase1Active; bool GridPhase2Active; double PendingTrailSL; bool HasPendingTrail; bool GridTPHit; double GridTPHitPrice; bool GridStackAlreadyAddedThisUpdate; bool StackAlreadyAddedThisUpdate; datetime LastGridCheckTime; double GridAggressiveTargetPrice; bool PruningOccurredThisSequence; };
struct SZoneRecoveryState { bool ZoneActive; double ZoneTopPrice; double ZoneBottomPrice; int ZoneSeqCount; double ZoneNextLot; bool ZoneResolved; };
struct SLedgerRecoveryState { double AccumulatedPruningLoss; double AccumulatedCriticalLoss; double CurrentRecoveryPortion; int RecoveryIteration; double LedgerPruningIn; double LedgerPruningOut; double LedgerCriticalIn; double LedgerCriticalOut; ulong LastDebtEventId; };
struct SShadowAIState { int Dyn_MA1_Period; int Dyn_MA2_Period; int Dyn_Box_Lookback; int Dyn_ADX_Period; double Dyn_ADX_MinLevel; double Dyn_CurrencyStrengthDelta; double Dyn_GridMultiplier; bool Dyn_NLP_Killswitch; datetime LastShadowUpdate; int Handle_MA1; int Handle_MA2; int Handle_ADX; };
struct SBoxWarmupState { ENUM_MBP_BOX_WARMUP_PHASE phase; bool BoxHistoryWarmupQueued; bool BoxHistoryWarmupDone; ulong BoxHistoryWarmupNextAttemptMs; bool BoxHistoryWarmupInProgress; int BoxHistoryWarmupCursor; int BoxHistoryWarmupBarsToCheck; double BoxHistoryWarmupPrevHigh; double BoxHistoryWarmupPrevLow; int BoxHistoryWarmupLastTotalBars; };
struct SOpeningRangeState { bool OR_Active; datetime OR_ExpiryTime; double OR_High; double OR_Low; bool OR_WasBullish; bool OR_BreakoutOccurred; datetime OR_LastCheckedBar; int OR_LastDay; };
struct SAlertState { datetime LastAlertTime; string LastSignal; double PreviousMasterSL; double PreviousBasketSL; bool MasterSLMoved; bool BasketSLMoved; bool SmartHedgeFirstLockSeen; bool SmartHedgeReleased; datetime SmartHedgeReleasedAt; bool TPActivated; double InitialTP; ulong MasterTicket; double MasterSL; double MasterEntry; ENUM_POSITION_TYPE MasterType; bool MasterHasValidSL; bool NonGridSLMovedThisTick; bool GridSLMovedThisTick; };
struct STickCursor { datetime LastTickTime; datetime LastCandleTime; bool ProcessedThisCandle; long LastTickMsc; long LastProcessedSourceTickMsc; int LastProcessedSourceTickCountAtMsc; datetime LastVWAPUpdate; bool NewVWAPHighLowSet; long lastUpdate; };

// Symbol data structure
struct SSymbolData
{
   string            symbol;
   string            BaseSymbol;
   string            AnalysisSymbol;
   bool              active;
   int               BasketId;
   bool              IsPrimaryBasket;
   bool              BasketActive;
   double            BasketInitialEntry;
   ENUM_POSITION_TYPE BasketDirection;
   ENUM_MBP_DATA_MODE DataMode;
   ENUM_MBP_RENKO_FAMILY RenkoFamily;

   CArrayObj         *ChartFactories; // Collection of CChartFactory instances

   // Indicator handles
   int               MA_Handles[5][7]; // 5 MAs for 7 timeframes
   int               ATR_Handle;
   int               MA_SL_Handle; // Separate handle for MA stop loss
   int               ADX_Handle;

   // VWAP data
   SVWAPData         VWAP1;      // Continuous VWAP (6PM NY reset)
   SVWAPData         VWAP2_High; // Anchored at highest high of day
   SVWAPData         VWAP2_Low;  // Anchored at lowest low of day
   SVWAPData         VWAP3;      // Session VWAP (9:30AM NY start)

   // Box variables
   double            BoxHigh[100];
   double            BoxLow[100];
   int               BoxHighCount;
   int               BoxLowCount;

   // Trade tracking
   double            OriginalBalance;
   double            CurrentStakeMultiplier;
   int               GridLevels;
   double            GridEntries[100];
   double            StackMultiplier;
   int               StackUpdates;
   int               TrailUpdateCount;
   double            LastSLPrice;
   STradePosition    OpenPositions[100];
   int               PositionCount;
   datetime          LastTradeTime;
   double            DailyProfitLoss;
   datetime          LastDailyReset;

   // Grid state tracking
   bool              GridTargetReached;
   bool              GridInTrailing;
   bool              GridInStacking;
   double            GridBasketStopLoss;
   double            GridBasketTakeProfit;
   double            GridBasketEntry;
   double            GridBasketVolume;
   double            GridTargetProfit;    // Raw lot tracking (new)
   double            RawNextGridLot;      // raw (un-normalized) next grid lot to use (keeps precision for next calc)
   double            LastUsedGridRawLot;  // last used raw grid lot (useful for progression reset)
   double            RawNextStackLot;     // raw (un-normalized) next stack lot to use
   double            LastUsedStackRawLot; // last used raw stack lot


   // Stack tracking for grid
   int               GridStackLevels;
   int               GridTrailUpdates;
   double            GridStackMultiplier;

   // Stack tracking variables
   bool              StackLastTrailUpdate;
   datetime          LastStackTime;
   double            LastStackSL;

   // Lock trail tracking
   bool              TrailLocked;
   double            LockBreakEvenPrice;
   bool              LockTPReached;

   // Candle tracking
   datetime          LastCandleTime;
   bool              ProcessedThisCandle;

   // Alert variables
   datetime          LastAlertTime;
   string            LastSignal;

   // Trail update tracking
   double            PreviousMasterSL;   // Previous candle's master SL
   double            PreviousBasketSL;   // Previous candle's basket SL
   bool              MasterSLMoved;        // Flag if master SL moved this candle
   bool              BasketSLMoved;        // Flag if basket SL moved this candle

   // Smart hedge release tracking
   bool              SmartHedgeFirstLockSeen;
   bool              SmartHedgeReleased;
   datetime          SmartHedgeReleasedAt;

   // TP tracking
   bool              TPActivated;          // TP level reached (for trailing commencement)
   double            InitialTP;          // Initial TP level for reference

   // Grid tracking
   datetime          LastGridCheckTime; // Last time grid was checked (for tick-based checks)

   // Stack control variables
   bool              StackAlreadyAddedThisUpdate;  // Flag to prevent multiple stacks per SL update
   bool              GridStackAlreadyAddedThisUpdate; // Flag for grid stacking

   // Master position tracking
   ulong             MasterTicket;        // Ticket of master position
   double            MasterSL;           // Current master SL
   double            MasterEntry;        // Master entry price
   ENUM_POSITION_TYPE MasterType; // Master position type
   bool              MasterHasValidSL;     // Flag if master has valid stop loss

   // Grid phase tracking
   bool              GridPhase1Active;     // True when in initial grid mode (no SL/TP)
   bool              GridPhase2Active;     // True when grid basket profit reached and in trailing mode

   // Temporary trail storage (for end-of-candle execution)
   double            PendingTrailSL;     // SL to apply at end of candle
   bool              HasPendingTrail;      // Flag indicating pending trail update

   // New grid sequence tracking
   int               CurrentGridSequence;   // Current grid sequence number
   datetime          LastGridReset;    // Last time grid was reset

   // Grid stake tracking
   double            GridStakeMultiplier;  // Current grid stake multiplier

   // Stack counter tracking - NEW IMPROVED
   SStackTracker     NonGridStack;  // Non-grid mode stack tracker
   SStackTracker     GridStack;     // Grid mode stack tracker

   // Last processed tick time
   datetime          LastTickTime;

   // New VWAP tracking
   datetime          LastVWAPUpdate;
   bool              NewVWAPHighLowSet;    // Flag if daily high/low has been set for VWAP2

   // Stack SL movement flags (NEW)
   bool              NonGridSLMovedThisTick;    // For immediate detection
   bool              GridSLMovedThisTick;       // For immediate detection

   // --- CLEAN STACK ENGINE ---
   double            StackPrevSL;                  // previous SL for non-grid stacking
   bool              StackSLInitialized;           // did we initialize SL?

   double            GridStackPrevSL;              // previous SL for grid stacking
   bool              GridStackSLInitialized;       // did we initialize SL?

   int               StackLastOpenedCounter;       // last normal stack opened
   int               GridStackLastOpenedCounter;   // last grid stack opened

   // --- OPENING RANGE TRACKING ---
   bool              OR_Active;              // Is the strategy active for today?
   datetime          OR_ExpiryTime;          // When does the window close?
   double            OR_High;                // High of the 15m Opening Candle
   double            OR_Low;                 // Low of the 15m Opening Candle
   bool              OR_WasBullish;          // Was the 15m candle bullish?
   bool              OR_BreakoutOccurred;    // Has price moved beyond the range (trigger condition)?
   datetime          OR_LastCheckedBar;      // To ensure we only check each entry candle once
   int               OR_LastDay;

   // --- NEW GRID TP TRACKING ---
   bool              GridTPHit;          // Has the dollar target been hit?
   double            GridTPHitPrice;     // The price where the target was hit

   // In struct SSymbolData (Add this near the end)
   int               GridSequenceDepth;  // Cumulative count of trades in current sequence (ignores pruning)
   // ... existing members ...

   // --- ZONE RECOVERY TRACKING ---
   bool              ZoneActive;              // Is a Zone Recovery sequence running?
   double            ZoneTopPrice;            // Upper Boundary (Buy Trigger)
   double            ZoneBottomPrice;         // Lower Boundary (Sell Trigger)
   int               ZoneSeqCount;            // Number of recovery trades placed
   double            ZoneNextLot;             // Calculated lot for the next hedge
   bool              ZoneResolved;            // Flag when target logic is met
   // ------------------------------

   // --- NEW: PRUNING RECOVERY TRACKING ---
   double            AccumulatedPruningLoss; // Total loss from pruned trades waiting to be recovered
   double            CurrentRecoveryPortion; // The portion of the loss assigned to the CURRENT grid cycle
   //
   
   // Update inside struct SSymbolData
   double            LastStackLot;       // Tracks lot size of the previous stack trade
   double            LastStackMult;      // Tracks multiplier used in the previous stack trade
   
   // [Add this inside struct SSymbolData]
   int RecoveryIteration; // Tracks 1x, 2x, 3x of recovery percentage
   
   // [Inside struct SSymbolData]
   double            GridAggressiveTargetPrice; // The price target used for the last aggressive calc
   bool              PruningOccurredThisSequence; // Flag to prevent incrementing if pruned
   double            AccumulatedCriticalLoss; // <--- NEW: Secondary "Loss Bank"
   // --- V3 Ledger Metrics ---
   double            LedgerPruningIn;
   double            LedgerPruningOut;
   double            LedgerCriticalIn;
   double            LedgerCriticalOut;
   ulong             LastDebtEventId;
   
   // ADD THESE TWO LINES:
   datetime BoxHighStartTime; // Tracks when the current High level began
   datetime BoxLowStartTime;  // Tracks when the current Low level began
   
   // Inside struct SSymbolData in MultiBotPro_Defines.mqh

   // --- Shadow Master AI Parameters ---
   int      Dyn_MA1_Period;
   int      Dyn_MA2_Period;
   int      Dyn_Box_Lookback;
   int      Dyn_ADX_Period;
   double   Dyn_ADX_MinLevel;
   double   Dyn_CurrencyStrengthDelta;
   double   Dyn_GridMultiplier;
   bool     Dyn_NLP_Killswitch;
   
   // --- Tracking for dynamic updates ---
   datetime LastShadowUpdate;
   
   // --- Indicator Handles (Must be stored per-symbol) ---
   int      Handle_MA1;
   int      Handle_MA2;
   int      Handle_ADX;
   
   long LastTickMsc; // <-- Add this line to track the exact millisecond of the last price update
   long LastProcessedSourceTickMsc; // Ordered source-tick cursor for synthetic chart replay
   int  LastProcessedSourceTickCountAtMsc; // Number of source ticks already consumed at the current cursor millisecond
   bool BoxHistoryWarmupQueued;
   bool BoxHistoryWarmupDone;
   ulong BoxHistoryWarmupNextAttemptMs;
   bool BoxHistoryWarmupInProgress;
   int  BoxHistoryWarmupCursor;
   int  BoxHistoryWarmupBarsToCheck;
   double BoxHistoryWarmupPrevHigh;
   double BoxHistoryWarmupPrevLow;
   int  BoxHistoryWarmupLastTotalBars;

   // ============================================================================
   // BASKET-LEVEL STATE TRACKING (NEW - Phase 1 Coordinator/Worker Refactor)
   // ============================================================================
   // Per-(BasketId, Symbol) tracking for grid phases and zone boundaries.
   // Stored as pointer array so individual states can be returned by pointer.
   SBasketState* BasketStates[MBP_MAX_BASKETS];        // Max 100 concurrent baskets per symbol (heap-allocated)
   int           BasketStateCount;         // Current number of basket states tracked

};

void MBP_ResetSymbolPointerState(SSymbolData &symbolData)
{
   // Step 2a fix: delete live baskets before clearing (was leak: just NULLed).
   for(int i = 0; i < symbolData.BasketStateCount; i++)
   {
      if(CheckPointer(symbolData.BasketStates[i]) != POINTER_INVALID)
         delete symbolData.BasketStates[i];
      symbolData.BasketStates[i] = NULL;
   }
   for(int i = symbolData.BasketStateCount; i < MBP_MAX_BASKETS; i++)
      symbolData.BasketStates[i] = NULL;
   symbolData.ChartFactories = NULL;
   symbolData.BasketStateCount = 0;
}

// Step 2a: free all baskets for a symbol — canonical cleanup for deinit/wipe
void MBP_FreeAllBasketStates(SSymbolData &symbolData)
{
   for(int i = 0; i < symbolData.BasketStateCount; i++)
   {
      if(CheckPointer(symbolData.BasketStates[i]) != POINTER_INVALID)
         delete symbolData.BasketStates[i];
      symbolData.BasketStates[i] = NULL;
   }
   for(int i = symbolData.BasketStateCount; i < MBP_MAX_BASKETS; i++)
      symbolData.BasketStates[i] = NULL;
   symbolData.BasketStateCount = 0;
}
  
// --- FILTER TRACKING STRUCTURE ---
struct SFilterData
{
   double   SessionStartEquity;
   double   SessionNetProfit;
   int      DailyWins;
   int      DailyLosses;
   int      WinStreak;
   int      LossStreak;
   int      BlockWins;
   int      BlockLosses;
   double   LastBlockHigh;
   double   LastBlockLow;
   datetime LastResetTime;
   bool     StopTrading;
   string   StopReason;
};

// --- Global System Controls definitions shifted to Globals.mqh ---
// (Variables like Timeframes, SymbolData, etc. moved to avoid redefinition errors)

// Helper: Resize Filter Array (Call this in InitializeSymbolData)
void InitFilterTracker(int index)
{
   if(ArraySize(FilterTracker) <= index)
      ArrayResize(FilterTracker, index + 1);

   FilterTracker[index].SessionStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   FilterTracker[index].LastResetTime = TimeCurrent();
   FilterTracker[index].StopTrading = false;
}

// ============================================================================
// BASKET STATE MANAGEMENT HELPERS (NEW - Phase 1)
// ============================================================================

/// Find basket state pointer by BasketId within a symbol's tracking array
/// @param symbolData Reference to the SSymbolData struct for the symbol
/// @param basketId The basket ID to search for
/// @return Pointer to SBasketState, or NULL if not found
SBasketState* FindBasketState(SSymbolData &symbolData, int basketId)
{
   for(int i = 0; i < symbolData.BasketStateCount; i++)
   {
      if(CheckPointer(symbolData.BasketStates[i]) != POINTER_INVALID &&
         symbolData.BasketStates[i].BasketId == basketId)
         return symbolData.BasketStates[i];
   }
   return NULL; // Not found
}

/// Get or create basket state by BasketId (returns pointer for in-place mutation).
/// Creates a new SBasketState on the heap if none exists for this basketId.
/// @param symbolData Reference to the SSymbolData struct for the symbol
/// @param basketId The basket ID to get or create
/// @return Pointer to SBasketState (valid), or NULL on overflow
SBasketState* GetOrCreateBasketState(SSymbolData &symbolData, int basketId)
{
   SBasketState* existing = FindBasketState(symbolData, basketId);
   if(existing != NULL)
      return existing;

   // Overflow guard
   if(symbolData.BasketStateCount >= MBP_MAX_BASKETS)
   {
      if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print("ERROR: Maximum basket states (MBP_MAX_BASKETS) exceeded for symbol ", symbolData.symbol);
      return NULL;
   }

   // Allocate and initialize
   SBasketState* bs = new SBasketState();
   bs.BasketId = basketId;

   symbolData.BasketStates[symbolData.BasketStateCount] = bs;
   symbolData.BasketStateCount++;

   return bs;
}

/// Reset (delete + remove) basket state when a basket closes.
/// @param symbolData Reference to the SSymbolData struct for the symbol
/// @param basketId The basket ID to reset
void ResetBasketState(SSymbolData &symbolData, int basketId)
{
   for(int i = 0; i < symbolData.BasketStateCount; i++)
   {
      if(CheckPointer(symbolData.BasketStates[i]) != POINTER_INVALID &&
         symbolData.BasketStates[i].BasketId == basketId)
      {
         delete symbolData.BasketStates[i];
         symbolData.BasketStates[i] = NULL;

         // Compact array: move last element into this slot
         if(i < symbolData.BasketStateCount - 1)
            symbolData.BasketStates[i] = symbolData.BasketStates[symbolData.BasketStateCount - 1];

         symbolData.BasketStates[symbolData.BasketStateCount - 1] = NULL;
         symbolData.BasketStateCount--;
         return;
      }
   }
}

// NOTE: A second overload GetOrCreateBasketState(int symbolIndex, int basketId)
// is defined in MultiBotPro_Helpers.mqh (after SymbolData[] is declared).

// --- V3 Bridge Pending Request (Async Handshake) ---
struct SBridgePendingRequest
{
   bool              active;
   bool             approved;
   int              symbolIndex;
   ENUM_ORDER_TYPE  orderType;
   double           totalLot;
   datetime         createdAt;
   datetime         expiresAt;
   datetime         approvedAt;
   ulong            lastExecAttemptMs;
   int              executionAttempts;
   string           proposalFile;
   string           replyFile;
   long             requestId;
};

SBridgePendingRequest G_BridgePending;

// --- STANDALONE RUNTIME STRUCTS ---
struct SystemSnapshot
{
   double overall_equity;
   double overall_balance;
   int    active_symbol_count;
};

struct SymbolRuntime
{
   string symbol;
   string analysis_symbol;
   int    handle_count;
};

struct RuntimeServiceManager
{
   bool   is_active;
   long   last_cycle_ms;
};

//+------------------------------------------------------------------+
//|                                     MultiBotPro API IMPORTS      |
//+------------------------------------------------------------------+
// accel.dll is intentionally opt-in. The default build is DLL-free so
// live trading never requires a native acceleration module before OnInit.
// To compile with DLL acceleration, uncomment the line below or define
// MBP_COMPILE_ACCEL_DLL externally before including this file. At runtime
// the user input InpEnableAccelDll controls whether DLL paths are used —
// if the toggle is off (or DLLs are blocked on the VPS/market), synthetic
// engines route to Python/Native via BuildMasterConfigSnapshot fallback.
//#define MBP_COMPILE_ACCEL_DLL

#ifdef MBP_COMPILE_ACCEL_DLL
   #import "accel.dll"
      int TestConnection(int value);
      bool ProcessRenkoTicks(const double &pTicks[], int tickCount, double boxSize, double &pOutBoxesKeys[], int &pOutCount[], int maxBoxes);
      double CalculateGridMath(double startLevel, double multiplier, int maxLevels);
      int MBP_BoxBuildPayloadW(string filePath, const double &values[], int valueCount);
      int MBP_EnsureWorkersW(string runtimeRoot, string requestedBackend);
      int MBP_FileExistsW(string path);
      int MBP_IsWorkerProcessRunningW(string workerRole, string sessionKey, string reserved);
      int MBP_QueryRenkoBackendW(string runtimeRoot, string requestedBackend);
      int MBP_QueryWorkerStatusW(string runtimeRoot, string workerRole, string sessionKey, int timeoutMs);
      int MBP_StopWorkersW(string runtimeRoot, string workerRole);
      int MBP_RenkoOpenSessionW(string sessionKey, string customSymbol, int renkoFamily, double pointSize, int digits);
      int MBP_RenkoResetSessionW(string sessionKey, string customSymbol);
      int MBP_RenkoCloseSessionW(string sessionKey, string customSymbol);
      int MBP_RenkoSeedSessionW(string sessionKey, string customSymbol,
                                double anchorPrice, int trendUp, double blockSize,
                                double openOffsetPct, double reversalShadowPct, double reversalPct,
                                int applyOffsetToFirstBar, int offsetDigits, int resetOpenOnNewDay);
      int MBP_RenkoFeedRatesW(string sessionKey, string customSymbol, const double &prices[], const long &timesMsc[], int rateCount);
      int MBP_RenkoFeedM1RatesW(string sessionKey, string customSymbol,
                                const double &opens[], const double &highs[], const double &lows[],
                                const double &closes[], const long &timesMsc[], int rateCount);
      int MBP_RenkoFeedTicksW(string sessionKey, string customSymbol, const double &prices[], const long &timesMsc[], int tickCount);
      int MBP_RenkoReadSnapshotW(string sessionKey, string customSymbol, double &outDoubles[], long &outLongs[]);
      int MBP_RenkoGetHistoryInfoW(string sessionKey, string customSymbol, long &outLongs[]);
      int MBP_RenkoReadHistoryBarsW(string sessionKey, string customSymbol, double &outDoubles[], long &outLongs[], int maxBars);
      int MBP_RenkoReadClosedBarsW(string sessionKey, string customSymbol, double &outDoubles[], long &outLongs[], int maxBars);
   #import

   bool MBP_IsAccelDllCompiled() { return true; }
#else
   bool MBP_IsAccelDllCompiled() { return false; }
   int TestConnection(int value) { return 0; }
   bool ProcessRenkoTicks(const double &pTicks[], int tickCount, double boxSize, double &pOutBoxesKeys[], int &pOutCount[], int maxBoxes) { return false; }
   double CalculateGridMath(double startLevel, double multiplier, int maxLevels) { return 0.0; }
   int MBP_BoxBuildPayloadW(string filePath, const double &values[], int valueCount) { return 0; }
   int MBP_EnsureWorkersW(string runtimeRoot, string requestedBackend) { return 0; }
   int MBP_FileExistsW(string path) { return 0; }
   int MBP_IsWorkerProcessRunningW(string workerRole, string sessionKey, string reserved) { return 0; }
   int MBP_QueryRenkoBackendW(string runtimeRoot, string requestedBackend) { return 0; }
   int MBP_QueryWorkerStatusW(string runtimeRoot, string workerRole, string sessionKey, int timeoutMs) { return 0; }
   int MBP_StopWorkersW(string runtimeRoot, string workerRole) { return 0; }
   int MBP_RenkoOpenSessionW(string sessionKey, string customSymbol, int renkoFamily, double pointSize, int digits) { return 0; }
   int MBP_RenkoResetSessionW(string sessionKey, string customSymbol) { return 0; }
   int MBP_RenkoCloseSessionW(string sessionKey, string customSymbol) { return 0; }
   int MBP_RenkoSeedSessionW(string sessionKey, string customSymbol,
                             double anchorPrice, int trendUp, double blockSize,
                             double openOffsetPct, double reversalShadowPct, double reversalPct,
                             int applyOffsetToFirstBar, int offsetDigits, int resetOpenOnNewDay) { return 0; }
   int MBP_RenkoFeedRatesW(string sessionKey, string customSymbol, const double &prices[], const long &timesMsc[], int rateCount) { return 0; }
   int MBP_RenkoFeedM1RatesW(string sessionKey, string customSymbol,
                             const double &opens[], const double &highs[], const double &lows[],
                             const double &closes[], const long &timesMsc[], int rateCount) { return 0; }
   int MBP_RenkoFeedTicksW(string sessionKey, string customSymbol, const double &prices[], const long &timesMsc[], int tickCount) { return 0; }
   int MBP_RenkoReadSnapshotW(string sessionKey, string customSymbol, double &outDoubles[], long &outLongs[]) { return 0; }
   int MBP_RenkoGetHistoryInfoW(string sessionKey, string customSymbol, long &outLongs[]) { return 0; }
   int MBP_RenkoReadHistoryBarsW(string sessionKey, string customSymbol, double &outDoubles[], long &outLongs[], int maxBars) { return 0; }
   int MBP_RenkoReadClosedBarsW(string sessionKey, string customSymbol, double &outDoubles[], long &outLongs[], int maxBars) { return 0; }
#endif

#import "kernel32.dll"
  int  CreateFileW(string lpFileName, uint dwDesiredAccess, uint dwShareMode, uint lpSecurityAttributes, uint dwCreationDisposition, uint dwFlagsAndAttributes, int hTemplateFile);
  bool WriteFile(int hFile, const uchar &lpBuffer[], uint nNumberOfBytesToWrite, uint &lpNumberOfBytesWritten, uint lpOverlapped);
  bool CloseHandle(int hObject);
  bool MoveFileW(string lpExistingFileName, string lpNewFileName);
  uint GetFileAttributesW(string lpFileName);   // Used as accel.dll-free file-existence check
#import

#endif // __MULTIBOTPRO_DEFINES_MQH__


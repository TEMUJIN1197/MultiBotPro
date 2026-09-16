//+------------------------------------------------------------------+
//|                                                  MultiBotPro.mq5 |
//|                               Copyright 2023, Expert Advisor Pro |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Expert Advisor Pro"
#property link      "https://discord.com/channels/929723953415589918/929723953415589920"
#property version   "1.00"
#property icon      "romeo.ico"
#property description "Advanced Multi-Timeframe Multi-Symbol Trading Bot"
#property description "Features: MA Cascade, VWAP Bands, Grid/Stack Modes"
#property description "Multi-Symbol: Trade multiple symbols concurrently"
#property description "Risk Management: Global TP/SL, Dynamic Stake, Box Stops"
#resource "\\Experts\\MultiBotPro\\romeo.bmp"
#resource "\\Experts\\MultiBotPro\\romeo_panel.bmp"
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+

// --- MODIFICATION PANEL GLOBALS ---

bool  ShowManualSection       = false;      // Toggle for Secondary Panel
bool  ShowTradeList           = false;      // Toggled by "L" (New)
bool   Panel_IsModifying      = false;      // Are we currently editing a specific trade?
ulong  Panel_SelectedTicket   = 0;          // The ticket currently being edited
double Panel_ManualLot        = 0.01;       // Current Manual Lot Size
int    Panel_SlowPts          = 10;         // Modification step slow
int    Panel_FastPts          = 100;        // Modification step fast


// Global Authorization Flags
bool   G_LicenseValid = false;
bool   G_LicenseExpiredExplicit = false;
string G_LicenseMsg   = "Unverified";
// --- HANDSHAKE STATE LOCKS ---
bool  G_HandshakePending   = false;
ulong G_HandshakeStartTime = 0;
ulong G_PendingProposalTicket = 0;

// --- HEDGE MASTER GLOBALS ---
double MasterStartEquity = 0;
double g_HighWaterMark = 0.0;
double g_TrailingStopLevel = 0.0;
double m_day_start_equity = 0.0;
int    m_current_day_of_year = -1;
bool   m_daily_stop_hit = false;
bool   m_total_stop_hit = false;
long   CurrentResetID = 0;
double EffectiveMasterRisk = 0;

// ==================================================================
// --- CACHED STATE GLOBALS (Updated via OnTimer) ---
// ==================================================================
bool   G_Cache_SystemBlocked = false;
bool   G_Cache_IsTradingTime = true;
bool   G_Cache_IsNewsTime    = false;
bool   G_Cache_IsHardBlock   = false;
string G_Cache_BlockReason   = "";
ulong  G_LastShadowConfigPollMs = 0;
ulong  G_LastShadowSupervisorCheckMs = 0;
ulong  G_LastShadowRuntimeWriteMs = 0;
ulong  G_LastShadowLaunchAttemptMs = 0;
string G_LastShadowRuntimeSignature = "";

// Add these two new globals:
bool   G_Cache_IsDailyCloseBlock = false;
bool   G_SLTP_Hidden = false;

bool   G_IS_DEINIT = false;
bool   G_InitInProgress = false;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+

// Include libraries
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\HistoryOrderInfo.mqh>
#include <Arrays\ArrayObj.mqh>
bool MBP_ShouldAllowBlockingTradeWait(const string reason = "");
#include "hedgeBridge.mqh" // Ensure Bridge definitions exist
// --- BRIDGE DECOUPLING QUEUE ---
HedgeSignal G_SignalQueue[];

struct SBridgeSignalStamp
{
   ulong    masterTicket;
   int      action;
   datetime seenAt;
};

SBridgeSignalStamp G_BridgeSignalStamps[];

struct SSmartHedgeProtectedTrade
{
   ulong    masterTicket;
   string   baseSymbol;
   int      basketId;
   double   totalBaselinePnl;
   double   dailyBaselinePnl;
   double   lastSeenPnl;
   datetime releasedAt;
};

SSmartHedgeProtectedTrade G_SmartHedgeProtectedTrades[];
double G_SmartHedgeClosedTotalAdjustment = 0.0;
double G_SmartHedgeClosedDailyAdjustment = 0.0;

#define MBP_MAX_FEEDBACK_ROWS_PER_TIMER 4
#define MBP_MAX_FILE_FEEDBACK_PER_TIMER 4
#define MBP_MAX_SIGNAL_FLUSH_PER_TIMER  4

bool SmartHedge_IsEnabled();
double SmartHedge_GetTicketNetPnl(const ulong masterTicket);
int SmartHedge_FindProtectedTicketIndex(const ulong masterTicket);
bool SmartHedge_IsProtectedTicket(const ulong masterTicket);
void SmartHedge_RegisterProtectedTicket(const int symbolIndex, const ulong masterTicket, const double baselinePnl = EMPTY_VALUE);
void SmartHedge_ReconcileProtectedTrades();
void SmartHedge_ResetDailyBaselines();
void SmartHedge_ResetAll();
void SmartHedge_ResetSymbol(const int symbolIndex);
int Master_FindSymbolIndexForBridgeTrade(const string baseSymbol, const string comment, const int fallbackIndex = -1);
void SmartHedge_QueueSlaveClose(const ulong masterTicket, const string baseSymbol);
void SmartHedge_ReleaseSequence(const int symbolIndex, const string reason);
void SmartHedge_OnProtectedStopMove(const int symbolIndex, const bool isBasket);
bool SmartHedge_ShouldBypassSlaveForSymbol(const int symbolIndex);
void SmartHedge_ApplyPnLAdjustments(double &totalPnL, double &dailyPnL);
bool Master_HasRecentBridgeSignal(const ulong masterTicket, const int action, const int ttlSec);
void Master_RememberBridgeSignal(const ulong masterTicket, const int action);
void TouchLicenseReloadGrace(const long account, const int reason);

datetime MBP_RuntimeServerNow()
{
   datetime tradeServerTime = TimeTradeServer();
   if(tradeServerTime > 0)
      return tradeServerTime;

   datetime quoteTime = TimeCurrent();
   if(quoteTime > 0)
      return quoteTime;

   return TimeGMT();
}

bool MBP_DetectServerGMTOffset(int &outOffsetHours, string &outReason)
{
   outOffsetHours = MathMax(-12, MathMin(14, InpServerGMTOffset));
   outReason = "";

   datetime gmt = TimeGMT();
   datetime quoteTime = TimeCurrent();
   datetime tradeServerTime = TimeTradeServer();
   datetime srv = (tradeServerTime > 0) ? tradeServerTime : quoteTime;
   if(gmt <= 0 || srv <= 0)
   {
      outReason = "clock unavailable";
      return false;
   }

   long diffSeconds = (long)srv - (long)gmt;
   double diffHours = (double)diffSeconds / 3600.0;
   int roundedOffset = (int)MathRound(diffHours);
   double roundingError = MathAbs(diffHours - (double)roundedOffset);

   if(tradeServerTime <= 0 && quoteTime > 0)
      outReason = "TimeTradeServer unavailable; used last quote time";
   else if(quoteTime > 0 && MathAbs((long)tradeServerTime - (long)quoteTime) > 3600)
      outReason = StringFormat("last quote time differs from trade-server time by %.2fh",
                               MathAbs((double)((long)tradeServerTime - (long)quoteTime)) / 3600.0);

   if(roundedOffset < -12 || roundedOffset > 14)
   {
      string detail = StringFormat("raw offset %.2fh is outside valid UTC offset range", diffHours);
      outReason = (outReason == "") ? detail : (outReason + "; " + detail);
      return false;
   }

   if(roundingError > 0.25)
   {
      string detail = StringFormat("raw offset %.2fh is not close to a whole-hour broker offset", diffHours);
      outReason = (outReason == "") ? detail : (outReason + "; " + detail);
      return false;
   }

   outOffsetHours = roundedOffset;
   return true;
}

// 1. INCLUDE DEFINITIONS (Enums & Structs)
#include "MultiBotPro_Defines.mqh"
#include "MultiBotPro_SlaveRuntime.mqh" // RESTORED

// Global trade object shared by Master and embedded Slave runtimes.
CTrade Trade;

// --- NEW GLOBAL ---
class CChartFactory;
string RealSymbol; // The actual symbol we trade (e.g. "USTEC")
long MyChartIDs[]; // We will store the ID of every chart we open here
SystemSnapshot G_SystemSnapshot;
SymbolRuntime  G_RuntimeSymbols[];
RuntimeServiceManager G_ServiceManager;
ENUM_COMPUTE_BACKEND G_ActiveComputeBackend = COMPUTE_BACKEND_NATIVE;
ENUM_MBP_CHART_MODE ChartMode = MBP_CHART_STANDARD;
SFilterData FilterTracker[];
string G_DashboardFocusBaseSymbol = "";
double Dash_Scale = 1.0;
CChartFactory *G_ChartFactory = NULL;
ulong G_MasterUiPriorityUntilMs = 0;
int   G_RuntimePumpCursor = 0;
int   G_TimerPumpCursor = 0;
int   G_TickPumpCursor = 0;
ENUM_MBP_RUNTIME_ROLE G_RuntimeRole = MBP_RUNTIME_LEGACY;

// Per-worker magic-number isolation (Fix #13).
// Workers stamp their trades with MagicNumber + workerIndex*MBP_WORKER_MAGIC_STRIDE
// so a "close-by-magic" emergency on worker N doesn't kill worker M's positions.
// Coordinator's IsAppTrade still recognises every offset for system-wide enforcement.
#define MBP_WORKER_MAGIC_STRIDE 1000
#define MBP_WORKER_MAGIC_MAX_OFFSETS 100
int  G_RuntimeWorkerIndex     = -1;
long G_EffectiveMagicNumber   = 0;
ulong G_LastWorkerHeartbeatPublishMs = 0;
ulong G_LastWorkerEnsureMs = 0;
ulong G_LastWorkerTemplateSaveMs = 0;
bool  G_WorkerBootstrapCompleted = false;
bool  G_InTimerCycle = false;
string G_WorkerHeartbeatStateOverride = "";
string G_LastWorkerTemplateSignature = "";
string G_RuntimeCoordinatorKey = "";
string G_RuntimeAssignedWorkerSymbol = "";
string G_RuntimeAssignedChartSymbol = "";
string G_RuntimeAssignedSymbolsCsv = "";
string G_RuntimeAssignedWorkerSignature = "";
string G_RuntimeAssignedSymbols[];

#define MBP_WORKER_LAUNCH_GRACE_SEC      600
#define MBP_WORKER_TEMPLATE_RETRY_MS     300000
#define MBP_WORKER_CHART_OPEN_COOLDOWN_MS 300000
#define MBP_WORKER_ENSURE_INTERVAL_MS    2500
#define MBP_WORKER_READY_STALE_SEC       120
#define MBP_WORKER_GRACE_STALE_SEC       900
#define MBP_WORKER_HEARTBEAT_TIME_SKEW_SEC 300

#define MBP_UI_COMMAND_QUEUE_CAPACITY 16

struct SMbpWorkerSlot
{
   string symbol;
   string symbolsCsv;
   string chartSymbol;
   string assignmentSignature;
   int    assignedCount;
   long   chartId;
   ulong  lastLaunchAttemptMs;
   datetime lastHeartbeat;
   long   lastLoggedChartId;
   string lastLoggedHeartbeatState;
};

SMbpWorkerSlot G_WorkerSlots[];

enum ENUM_MBP_UI_COMMAND
{
   MBP_UI_CMD_NONE = 0,
   MBP_UI_CMD_MASTER_RESET,
   MBP_UI_CMD_TOGGLE_PAUSE,
   MBP_UI_CMD_TOGGLE_COLLAPSE,
   MBP_UI_CMD_DASH_SCALE_UP,
   MBP_UI_CMD_DASH_SCALE_DOWN,
   MBP_UI_CMD_TOGGLE_MANUAL_SECTION,
   MBP_UI_CMD_TOGGLE_TRADE_LIST,
   MBP_UI_CMD_CLOSE_ALL,
   MBP_UI_CMD_CLOSE_SYMBOL,
   MBP_UI_CMD_OPEN_SETTINGS_PANEL,
   MBP_UI_CMD_CLOSE_SETTINGS_PANEL,
   MBP_UI_CMD_SETTINGS_SCALE_UP,
   MBP_UI_CMD_SETTINGS_SCALE_DOWN,
   MBP_UI_CMD_SETTINGS_MODE_NEXT,
   MBP_UI_CMD_SETTINGS_APPLY_MODE
};

enum ENUM_MBP_CONTROL_JOB_TYPE
{
   MBP_CONTROL_JOB_NONE = 0,
   MBP_CONTROL_JOB_RESET,
   MBP_CONTROL_JOB_CLOSE_ALL,
   MBP_CONTROL_JOB_CLOSE_SYMBOL
};

enum ENUM_MBP_CONTROL_JOB_PHASE
{
   MBP_CONTROL_PHASE_IDLE = 0,
   MBP_CONTROL_PHASE_PREPARE,
   MBP_CONTROL_PHASE_CLOSE_SYMBOLS,
   MBP_CONTROL_PHASE_CLOSE_GLOBALS,
   MBP_CONTROL_PHASE_WIPE_SYMBOLS,
   MBP_CONTROL_PHASE_FINALIZE
};

struct SMasterUiCommand
{
   int    type;
   int    symbolIndex;
   string buttonName;
};

// --- FORWARD DECLARATIONS ---
void ResetSystemSnapshot();
void RefreshSystemSnapshot(bool blocked, bool tradeTime, bool newsTime, bool hardBlock, string reason);
void TouchMasterAnalysisEngineOnTimer();
void RefreshIndicatorOverlay(bool force);
void RefreshCurrentChartBoxLines(bool force);
bool InitializeMasterAnalysisEngine();
bool MBP_IsSyntheticChartMode(ENUM_MBP_CHART_MODE mode);
bool MBP_IsRenkoDataMode(ENUM_MBP_DATA_MODE mode);
string ResolveSyntheticChartSymbolName(string baseSymbol, ENUM_MBP_DATA_MODE mode);
bool PrepareSymbolStartupChart(int symbolIndex, ENUM_MBP_DATA_MODE requestedMode, string &analysisSymbol);
bool EnsureAssociatedChartVisibleForSymbol(const int symbolIndex, const ENUM_MBP_DATA_MODE requestedMode, string &outChartSymbol);
void RestoreMasterHostChartFocus();
void Master_RefreshChartVisualPackages(const bool allowFullRedraw);
void MasterPumpRuntimeServices();
bool MasterPublishWorkerHeartbeatState(const string runtimeState, const bool forcePublish = false);
void MasterPublishWorkerHeartbeat();
void MasterPumpTimerServices();
int  Master_OnInit_Runtime();
void ShutdownMasterRuntime();
void EnsureMasterDashboardReady(const bool forceRebuild = false);
void ResetDashboardHeartbeat();
void UpdateDashboard(long chart_id);
void CreateDashboard();
void DestroyDashboard();
void InitReferenceEquity();
void SaveBankState(int idx);
void WipeBankState(int idx);
string ShadowMaster_BuildRuntimeConfigJson();
string ShadowMaster_BuildRuntimeSignature();
bool ShadowMaster_WriteRuntimeConfig(const bool forceWrite = false);
bool ShadowMaster_ReadHeartbeat(datetime &outHeartbeat, string &outState);
bool ShadowMaster_IsAiRuntimeEnabled();
void ShadowMaster_Supervise(const bool forceLaunch = false);
void ShadowMaster_PollConfigUpdates(const bool forcePoll = false);
ENUM_MBP_RUNTIME_ROLE ResolveRuntimeRoleForCurrentChart();
string MBP_SanitizeRuntimeToken(string value);
int    MBP_StableStringHash(const string value);
string MBP_DefaultCoordinatorKey();
string MBP_GetActiveCoordinatorKey();
bool IsParallelLegacyMode();
bool IsParallelCoordinatorMode();
bool IsParallelWorkerMode();
string MBP_CoordPausedGVName(const string coordinatorKey);
string MBP_CoordResetGVName(const string coordinatorKey);
void MBP_SetCoordinatorPaused(const string coordinatorKey, const bool paused);
void MBP_SetCoordinatorResetting(const string coordinatorKey, const bool resetting);
bool MBP_IsCoordinatorPaused(const string coordinatorKey);
bool MBP_IsCoordinatorResetting(const string coordinatorKey);
bool IsBotPaused();
string RuntimeRoleToText(const ENUM_MBP_RUNTIME_ROLE role);
bool ShadowMaster_ShouldOwnRuntime();
void MasterEnsureRuntimeWorkers();
void WipeAllTerminalGlobalVariables();
void CloseAllGridPositions(int symbolIndex, string reason);
void CloseAllGlobalPositions(string reason);
void MarkIndicatorOverlayDirty();
int  ResolveDashboardFocusSymbolIndex();
bool MasterIsUiPriorityWindowActive();
bool MasterHasQueuedUiCommands();
bool MasterHasPendingTradeControlJob();
bool MasterEnqueueUiCommand(const int commandType, const int symbolIndex = -1, const string buttonName = "");
void MasterConsumeUiCommands();
void MasterPollDashboardButtons();
void MasterProcessTradeControlLane();
bool StartAsyncControlJob(const int jobType, const int symbolIndex = -1, const string reason = "");
ENUM_MBP_CHART_MODE MBP_DataModeToChartMode(ENUM_MBP_DATA_MODE mode);
ENUM_MBP_RENKO_FAMILY MBP_DataModeToRenkoFamily(ENUM_MBP_DATA_MODE mode);
bool MBP_IsSyntheticDataMode(ENUM_MBP_DATA_MODE mode);
string MBP_DataModeToText(ENUM_MBP_DATA_MODE mode);
string ResolveManagedAnalysisSymbol(const int symbolIndex);
bool IsBridgeRuntimeEnabled();
void MasterProcessBridgeFeedback();
void MasterPublishBridgeState();
void SaveFastChartSwitchDashboardState();
void RestoreFastChartSwitchDashboardState();

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
// NOTE: BotSystemMode controls external terminal-to-terminal behavior only.
// Standalone trades local signals directly. Master requires slave agreement through IPC.
// InpEnableCoordinator controls internal coordinator/worker execution topology.
// Internal worker charts ignore inputs and receive configuration from the coordinator chart.

// === 00. Security & License ===
input group "=== 00. Security & License ==="
input string InpLicenseKey = "testkey1"; // License key

// === 01. Symbols, Timeframes & Entries ===
input group "=== 01. Symbols, Timeframes & Entries ==="
sinput string DIV_SYMBOLS = "--- Traded Symbols ---";
input string ManualSymbols = "AUDNZD,CHFJPY,EURGBP,USDCAD"; // Manual symbol list
input bool TradeAllMarketWatch = false; // Use all Market Watch symbols
input bool UseChartSymbol = true; // Include current chart symbol
input string ExcludeSymbols = ""; // Symbols to exclude

sinput string DIV_TIMEFRAMES = "--- Active Timeframes ---";
input bool UseM1  = true; // Enable M1
input bool UseM3  = false; // Enable M3
input bool UseM15 = false; // Enable M15
input bool UseH1  = false; // Enable H1
input bool UseH4  = false; // Enable H4
input bool UseD1  = false; // Enable D1
input bool UseW1  = false; // Enable W1

sinput string DIV_TRADE_OPS = "--- Trade Operations ---";
input int    MagicNumber          = 12345; // Magic number
input string TradeComment         = "MultiBotPro"; // Order comment
input int    Slippage             = 3; // Max slippage (points)
input bool   ReverseStrategy      = false; // Reverse buy and sell signals

sinput string DIV_SIGNAL_OPS = "--- Signal Timing ---";
input bool   InpProcessSignalsPerBar = false; // Process once per bar

// === 01. Runtime, Data & Backend ===
input group "=== 01. Runtime, Data & Backend ==="
input ENUM_BOT_MODE BotSystemMode = BOT_MODE_STANDALONE; // Bot role
input bool InpEnableCoordinator = false; // Coordinator only; spawn worker EAs
input int InpParallelMaxWorkerCharts = 8; // Max worker charts (overflow stays on last worker)
input ENUM_MBP_DATA_MODE InpDataMode = MBP_DATA_LIVE; // Price engine
input ENUM_COMPUTE_BACKEND InpPrimaryComputeBackend = COMPUTE_BACKEND_DLL; // Primary compute backend
input bool InpAutoFailoverToPython = true; // Auto fallback to Python
input int InpParallelWorkerHeartbeatMs = 1000; // Worker state publish cadence (ms)

// === 00A. Synthetic Chart Engines ===
input group "=== 00A. Synthetic Chart Engines ==="
sinput string DIV_DATA_CUSTOM_TIME = "--- Custom Time Bars ---";
input int    InpCustomTimeValue = 45; // Bar interval value
input bool   InpCustomTimeUseSeconds = true; // Use seconds instead of minutes
input int    InpCustomTimeHistoryDays = 5; // History lookback (days)
input string InpCustomTimeSuffix = "CT"; // Custom symbol suffix

sinput string DIV_DATA_RENKO_CORE = "--- Renko Core ---";
input ENUM_BLOCK_MODE InpRenkoBlockMode = BLOCK_MODE_ATR_PERCENT; // Brick size mode
input double InpRenkoBlockValue = 0.4; // Brick size value
input bool   InpRenkoShowWicks = false; // Show Renko wicks
input ENUM_MBP_RENKO_LIVE_STYLE InpRenkoLiveStyle = MBP_RENKO_LIVE_SMALL_PHANTOM; // Live Renko mode
input int    InpRenkoLivePoolMs = 200; // Live tick pooling (ms, 0 = realtime)

sinput string DIV_DATA_RENKO_SYMBOLS = "--- Renko Symbols ---";
input string InpRenkoSuffix = "R"; // Classic Renko suffix
input string InpMedianRenkoSuffix = "MR"; // Median Renko suffix
input string InpTurboRenkoSuffix = "TR"; // Turbo Renko suffix
input string InpHybridRenkoSuffix = "HYR"; // Hybrid Renko suffix

sinput string DIV_DATA_RENKO_ATR = "--- Renko ATR Sizing ---";
input ENUM_TIMEFRAMES InpRenkoATRTimeframe = PERIOD_D1; // ATR timeframe
input int    InpRenkoATRPeriod = 14; // ATR period
input bool   InpRenkoAdaptiveATR = true; // Adaptive ATR sizing
input int    InpRenkoATRRefreshMs = 250; // ATR refresh cadence (ms)

sinput string DIV_DATA_RENKO_GEOM = "--- Renko Geometry ---";
input double InpRenkoOpenOffsetPct = 50.0; // Continuation open offset (%)
input double InpRenkoReversalShadowPct = 50.0; // Reversal shadow size (%)
input double InpRenkoReversalPct = 150.0; // Reversal size (%)
input bool   InpRenkoApplyOffsetToFirstBar = false; // Apply offset to first bar
input int    InpRenkoOffsetDigits = 0; // First-bar offset digits
input bool   InpRenkoResetOpenOnNewDay = false; // Reset open on new day

sinput string DIV_DATA_RENKO_HISTORY = "--- Renko History Build ---";
input int    InpRenkoHistoryDays = 2; // History lookback (days)
input ENUM_START_MODE InpRenkoStartMode = MODE_DAYS_BACK; // History start mode
input ENUM_HISTORY_DATA_TYPE InpRenkoHistType = DATA_M1; // History source data
input datetime InpRenkoFixedDate = 0; // Fixed start date
input bool   InpRenkoForceRebuild = false; // Force rebuild on init

sinput string DIV_DATA_HEIKEN_ASHI = "--- Heiken Ashi ---";
input string InpHeikenAshiSuffix = "HA"; // Custom symbol suffix
input int    InpHeikenAshiHistoryDays = 5; // History lookback (days)

sinput string DIV_DATA_HEIKEN_RENKO = "--- Heiken Renko ---";
input int    InpHeikenRenkoBlockSizePoints = 100; // Block size (points)
input string InpHeikenRenkoSuffix = "HARenko"; // Custom symbol suffix
input int    InpHeikenRenkoHistoryDays = 5; // History lookback (days)

// === 00B. Slave Mode ===
input group "=== 00B. Slave Mode ==="
sinput string DIV_SLAVE_CORE = "--- Slave Core ---";
input string Slave_InpChannelName = "HEDGE_A"; // Channel name
input string Slave_InpSymbolMap = ""; // Symbol map
input int    Slave_InpHeartbeat = 250; // Heartbeat (ms)
input long   Slave_InpSlaveMagic = 123456; // Slave magic number
input int    Slave_FailsafeTimeoutSeconds = 30; // Failsafe timeout (s)

sinput string DIV_SLAVE_TIME = "--- Slave Timezone ---";
input int    Slave_InpNYManualShift = 2; // New York manual shift

sinput string DIV_SLAVE_SQLITE = "--- Slave Bridge Runtime ---";
input bool   Slave_InpV3_EnableSQLiteBridge = true; // Use SQLite bridge
input bool   Slave_InpV3_EnableFileFallback = true; // Allow file fallback
input string Slave_InpV3_SQLitePath = "MultiBotPro_v3.db"; // SQLite file name

sinput string DIV_SLAVE_HEDGE = "--- Slave Hedge Model ---";
input double Slave_InpEstCommCost = 8.0; // Estimated commission
input bool   Slave_InpEnableLateStageSingleSymbolLock = false; // Late-stage symbol lock
input int    Slave_InpMaxConcurrentSymbols = 0; // Max concurrent slave symbols (0 = unlimited)

// === 03. Multi-Basket Entries ===
input group "=== 03. Multi-Basket Entries ==="
sinput string DIV_MULTI_BASKET = "--- Basket Controls ---";
input bool   InpEnableMultiBaskets = false; // Enable multiple baskets
input int    InpMaxBasketsPerSymbol = 2; // Max baskets per symbol
input double InpMinBasketDistanceATR = 5.0; // Min ATR spacing between baskets
input bool   InpAllowOppositeDirectionBaskets = true; // Allow buy and sell baskets together

// === 04. Position Sizing & Risk ===
input group "=== 04. Position Sizing & Risk ==="
sinput string DIV_BASE_RISK = "--- Base Risk Settings ---";
input ENUM_RISK_TYPE RiskType     = RISK_FIXED_MONEY;  // Risk model
input double RiskPercent          = 2.0; // Risk percent
input double FixedLot             = 0.01; // Fixed lot size
input double RiskMoney            = 50.0; // Fixed money risk

sinput string DIV_SAFETY_CAPS = "--- Safety Caps ---";
input double MaxLotSizePerTrade   = 50.0; // Max lot per trade
input int    MaxSplitTrades       = 10; // Max split orders
input double MaxSpreadATR         = 0.5; // Max spread (xATR, 0 = off)

// === 05. Exits, Stops & Trailing ===
input group "=== 05. Exits, Stops & Trailing ==="
sinput string DIV_SL_MAIN = "--- Stop Loss Core ---";
input ENUM_SL_TYPE StopLossType   = SL_ATR; // Stop-loss model
input ENUM_TIMEFRAMES ATR_Timeframe = PERIOD_CURRENT; // Stop-loss ATR timeframe

sinput string DIV_TP = "--- Take Profit ---";
input ENUM_TP_TYPE TakeProfitType = TP_ATR; // Take-profit model
input double TP_Ratio             = 1.5; // Risk/reward ratio
input double FixedTP              = 100.0; // Fixed take profit (points)
input double TP_ATR_Multiplier    = 5.0; // ATR take-profit multiplier

sinput string DIV_SL_ATR = "--- ATR Stop ---";
input int    ATR_Period           = 100; // ATR period
input double ATR_Multiplier       = 5.0; // ATR multiplier

sinput string DIV_SL_BOX = "--- Box Pivot Stop ---";
input int    Box_Lookback         = 2; // Pivot lookback
input int    Box_SL_Levels        = 2; // Box levels to keep
input ENUM_BOX_BREAKOUT_SRC BoxBreakoutMethod = BOX_BREAK_HIGHLOW; // Box breakout source

sinput string DIV_SL_MA = "--- MA Stop ---";
input int    MA_SL_Period         = 20; // Stop MA period
input ENUM_MY_MA_METHOD MA_SL_Method = MY_MODE_EMA; // Stop MA method
input ENUM_MY_MA_SOURCE MA_SL_Source = MY_SRC_CLOSE; // Stop MA source

sinput string DIV_TRAIL_STOP = "--- Trailing Stop ---";
input bool   UseTrailing          = true; // Enable trailing stop
input ENUM_TRAIL_TYPE TrailType   = TRAIL_ATR; // Trailing model
input int    TrailBox_Levels      = 2; // Trail box levels
input int    TrailBox_StepLevels  = 1; // Box trail step levels
input double TrailATR_Multiplier  = 1.5; // Trail ATR multiplier
input double TrailATR_Update      = 0.5; // Trail step (ATR multiplier)
input double TrailPoints          = 500.0; // Trail distance (points)
input double TrailPointsStep      = 250.0; // Trail step (points)
input ENUM_LOCK_TRAIL LockTrail   = LOCK_TRAIL_TP_HIT; // Lock trailing until

// === 06. Strategy Filters & Indicators ===
input group "=== 06. Strategy Filters & Indicators ==="
sinput string DIV_MA_1 = "--- Moving Average 1 ---";
input ENUM_MY_MA_SOURCE MA1_Source = MY_SRC_CLOSE; // MA1 source
input int MA1_Period = 5; // MA1 period
input ENUM_MY_MA_METHOD MA1_Method = MY_MODE_EMA; // MA1 method

sinput string DIV_MA_2 = "--- Moving Average 2 ---";
input ENUM_MY_MA_SOURCE MA2_Source = MY_SRC_CLOSE; // MA2 source
input int MA2_Period = 10; // MA2 period
input ENUM_MY_MA_METHOD MA2_Method = MY_MODE_EMA; // MA2 method

sinput string DIV_MA_3 = "--- Moving Average 3 ---";
input ENUM_MY_MA_SOURCE MA3_Source = MY_SRC_CLOSE; // MA3 source
input int MA3_Period = 20; // MA3 period
input ENUM_MY_MA_METHOD MA3_Method = MY_MODE_EMA; // MA3 method

sinput string DIV_MA_4 = "--- Moving Average 4 ---";
input ENUM_MY_MA_SOURCE MA4_Source = MY_SRC_CLOSE; // MA4 source
input int MA4_Period = 50; // MA4 period
input ENUM_MY_MA_METHOD MA4_Method = MY_MODE_EMA; // MA4 method

sinput string DIV_MA_5 = "--- Moving Average 5 ---";
input ENUM_MY_MA_SOURCE MA5_Source = MY_SRC_CLOSE; // MA5 source
input int MA5_Period = 200; // MA5 period
input ENUM_MY_MA_METHOD MA5_Method = MY_MODE_EMA; // MA5 method

sinput string DIV_MACRO = "--- Macro Strength Filter ---";
input bool   UseCurrencyStrength       = false; // Enable strength matrix
input double CurrencyStrengthDelta     = 5.0; // Min base-vs-quote delta

sinput string DIV_ADX = "--- ADX Filter ---";
input bool   UseADX               = false; // Enable ADX filter
input int    ADX_Period           = 14; // ADX period
input double ADX_MinLevel         = 25.0; // ADX threshold
input bool   ADX_TradeAbove       = true; // Trade when ADX is above threshold

sinput string DIV_BOX_TREND = "--- Box Trend Filter ---";
input bool   UseBoxTrendFilter    = false; // Enable box trend filter
input int    BoxTrend_TFs_Count   = 2; // Timeframes to compare
input bool   BoxTrend_ReqBreakout = false; // Require breakout on lowest timeframe

// === 07. VWAP Strategy ===
input group "=== 07. VWAP Strategy ==="
sinput string DIV_VWAP_MAIN = "--- Global VWAP ---";
input bool   UseVWAP              = false; // Enable VWAP signals
input bool   RequireVWAPConfirmation = true; // Require VWAP confirmation

sinput string DIV_VWAP_CONT = "--- Continuous VWAP ---";
input bool   UseVWAP1             = true; // Enable continuous VWAP
input ENUM_APPLIED_PRICE VWAP1_PriceSource = PRICE_TYPICAL; // Continuous VWAP price source
input int    VWAP1_ResetHour      = 18; // Reset hour (NY)
input int    VWAP1_ResetMinute    = 0; // Reset minute (NY)

sinput string DIV_VWAP_ANCH = "--- Anchored VWAP (High/Low) ---";
input bool   UseVWAP2             = true; // Enable anchored VWAP
input ENUM_APPLIED_PRICE VH_Source = PRICE_HIGH; // High anchor source
input ENUM_APPLIED_PRICE VL_Source = PRICE_LOW; // Low anchor source

sinput string DIV_VWAP_SESS = "--- Session VWAP ---";
input bool   UseVWAP3             = false; // Enable session VWAP
input ENUM_APPLIED_PRICE VWAP3_PriceSource = PRICE_TYPICAL; // Session VWAP price source
input int    VWAP3_StartHour      = 9; // Session start hour (NY)
input int    VWAP3_StartMinute    = 30; // Session start minute (NY)

// === 08. Opening Range Reversal ===
input group "=== 08. Opening Range Reversal ==="
sinput string DIV_OR_REVERSAL = "--- Opening Range Reversal ---";
input bool   UseORReversal        = false; // Enable OR reversal
input ENUM_TIMEFRAMES OR_EntryTF  = PERIOD_M5; // Entry timeframe
input int    OR_StartHour         = 9; // Start hour (NY)
input int    OR_StartMinute       = 30; // Start minute (NY)
input int    OR_WindowMinutes     = 60; // Trading window (minutes)
input double OR_ATR_Threshold     = 0.2; // Min range vs daily ATR

// === 09. Sessions, Time & News ===
input group "=== 09. Sessions, Time & News ==="
sinput string DIV_SESSION_MAIN = "--- Trading Sessions ---";
input bool   UseTimeFilter        = false; // Enable session filter
input bool   CloseTradesOnSessionExit = false; // Close trades when session ends

sinput string DIV_SESS_1 = "--- Session 1 ---";
input bool   UseSession1          = true; // Enable session 1
input int    Session1_StartHour   = 8; // Start hour
input int    Session1_StartMinute = 0; // Start minute
input int    Session1_EndHour     = 12; // End hour
input int    Session1_EndMinute   = 0; // End minute

sinput string DIV_SESS_2 = "--- Session 2 ---";
input bool   UseSession2          = false; // Enable session 2
input int    Session2_StartHour   = 13; // Start hour
input int    Session2_StartMinute = 0; // Start minute
input int    Session2_EndHour     = 16; // End hour
input int    Session2_EndMinute   = 0; // End minute

sinput string DIV_SESS_3 = "--- Session 3 ---";
input bool   UseSession3          = false; // Enable session 3
input int    Session3_StartHour   = 19; // Start hour
input int    Session3_StartMinute = 0; // Start minute
input int    Session3_EndHour     = 23; // End hour
input int    Session3_EndMinute   = 0; // End minute

sinput string DIV_DAYS = "--- Days of Week ---";
input bool   TradeMonday          = true; // Monday
input bool   TradeTuesday         = true; // Tuesday
input bool   TradeWednesday       = true; // Wednesday
input bool   TradeThursday        = true; // Thursday
input bool   TradeFriday          = true; // Friday
input bool   TradeSaturday        = true; // Saturday
input bool   TradeSunday          = true; // Sunday

sinput string DIV_HARD_STOPS = "--- Scheduled Hard Stops ---";
input bool   ClosePositionsAtBlockStart = false; // Close positions at block start
input bool   UseCloseBlock        = false; // Enable daily hard-stop block
input bool   HideSLTPDuringCloseBlock = false; // Hide SL/TP during block
input int    CloseBlock_StartHour = 16; // Block start hour
input int    CloseBlock_StartMinute = 30; // Block start minute
input int    CloseBlock_EndHour   = 18; // Block end hour
input int    CloseBlock_EndMinute = 0; // Block end minute
input bool   UseFridayHardStop    = false; // Enable Friday hard-stop block
input int    FridayStop_StartHour = 16; // Friday start hour
input int    FridayStop_StartMinute = 30; // Friday start minute
input int    FridayStop_EndHour   = 18; // Friday end hour
input int    FridayStop_EndMinute = 0; // Friday end minute

sinput string DIV_NEWS_MAIN = "--- Economic Calendar Filter ---";
input bool   UseNewsFilter        = true; // Enable news filter
input bool   NewsIncludeHigh      = true; // Include high-impact news
input bool   NewsIncludeMedium    = true; // Include medium-impact news
input bool   NewsIncludeLow       = false; // Include low-impact news
input bool   NewsIncludeHolidays  = true; // Include holidays
input bool   NewsFilterSymbolCurrency = true; // Limit to symbol currencies
input int    NewsMinutesBefore    = 5; // Pause before news (minutes)
input int    NewsMinutesAfter     = 5; // Resume after news (minutes)
input bool   CloseOnNews          = false; // Close positions for news

sinput string DIV_NEWS_VISUAL = "--- News Visuals ---";
input bool   ShowNewsLines        = true; // Draw news lines
input color  NewsColorHigh        = (color)255; // High-impact color
input color  NewsColorMed         = (color)42495; // Medium-impact color
input color  NewsColorLow         = (color)65535; // Low-impact color
input color  NewsColorHoliday     = (color)16777215; // Holiday color
input ENUM_LINE_STYLE NewsLineStyle = STYLE_DASHDOTDOT; // News line style
input bool   NewsWindowColorEnable = true; // Tint chart during news window
input color  NewsWindowColor      = (color)16711935; // News window color

// === 10. Recovery, Grid & Stacking ===
input group "=== 10. Recovery, Grid & Stacking ==="
sinput string DIV_GRID_CORE = "--- Grid/Zone Core ---";
input ENUM_RISK_MODE RiskMode     = RISK_MODE_GRID;    // Recovery mode
input ENUM_GRID_STRATEGY GridStrategy = GRID_STRAT_AGGRESSIVE; // Grid strategy
input bool   UseDynamicProfitScaling = true;           // Dynamic profit scaling
input double GridTP_Amount        = 2.0; // Grid target profit ($)
input double GridImpulseATR       = 2.0; // Phase 1 distance (ATR)
input double GridTransitionDist   = 1.0; // Phase 2 distance (ATR)

sinput string DIV_GRID_AGGR = "--- Aggressive Grid Mode ---";
input ENUM_GRID_DISTANCE_TYPE GridAggressiveDistType = GRID_DIST_ATR; // Distance unit
input double GridAggressiveRecovDist = 2.0; // Base recovery distance
input double GridAggressiveRecovMult = 1.5; // Distance multiplier

sinput string DIV_GRID_CONS = "--- Conservative Grid Mode ---";
input ENUM_GRID_DISTANCE_TYPE GridTransitionType = GRID_DIST_ATR; // Transition distance unit
input double GridStakeMultiplier  = 2.0; // Stake multiplier per level
input int    GridStakeStartLevel  = 1; // Stake start level
input double GridMaxStake         = 0.0; // Max stake (0 = no limit)

sinput string DIV_GRID_DIST = "--- Grid Distances ---";
input ENUM_GRID_DISTANCE_TYPE GridDistanceType = GRID_DIST_ATR; // Grid spacing unit
input double GridDistance         = 5.0; // Base grid spacing
input double GridMultiplier       = 1.5; // Grid spacing multiplier
input int    GridDistanceStartLevel = 1; // Distance multiplier start level
input double MinGridDistance      = 20.0; // Min grid spacing (points)
input double MaxGridDistance      = 20000.0; // Max grid spacing (points)

sinput string DIV_GRID_LOTS = "--- Grid Lot Sizing ---";
input bool   UseGridLotPerEquity  = false; // Use lot-per-equity model
input double GridLot_Per_Equity_Size = 0.01; // Lots per balance step
input double GridLot_Per_Equity_Step = 10000.0; // Balance step size
input ENUM_RISK_TYPE GridRiskType = RISK_FIXED_MONEY; // Fallback risk model
input double GridRiskPercent      = 0.2; // Fallback risk percent
input double GridFixedLot         = 0.01; // Fallback fixed lot
input double GridRiskMoney        = 10.0; // Fallback fixed money risk
input bool   GridCloseOnTP        = false; // Close grid at target

sinput string DIV_ZONE_RECOV = "--- Zone Recovery ---";
input ENUM_ZONE_GAP_TYPE ZoneGapType = ZONE_GAP_ATR; // Zone gap unit
input double ZoneTP_Amount        = 2.0; // Zone target profit ($)
input double ZoneGapPoints        = 50.0; // Zone gap (points)
input double ZoneGapATR           = 5.0; // Zone gap (ATR)
input double ZoneTargetMult       = 2.0; // Target distance multiplier
input double ZoneImpulseATR       = 2.0; // Phase 1 distance (ATR)
input double ZoneTransitionDist   = 2.0; // Phase 2 distance (ATR)
input bool   ZoneCloseOnTP        = false; // Close zone at target

sinput string DIV_DYN_STAKE = "--- Dynamic Staking ---";
input bool   UseDynamicStake      = false; // Enable dynamic stake sizing
input double EquityThreshold      = 2.0; // Equity change threshold (%)
input double StakeMultiplier      = 2.0; // Stake multiplier
input double MaxStakeMultiplier   = 20.0; // Max stake multiplier
input double lotCap               = 50.0; // Lot cap multiplier

sinput string DIV_STACK_MODE = "--- Stack Mode ---";
input bool   StackMode            = true; // Enable stack mode
input int    StackStart           = 1; // Stack start level
input double StackInitial         = 1.0; // Initial stack multiplier
input double StackBoost           = 0.25; // Stack boost per level
input double MinStackMultiplier   = 0.1; // Min stack multiplier
input double MaxStackMultiplier   = 64.0; // Max stack multiplier

// === 11. Grid Pruning (FIFO) ===
input group "=== 11. Grid Pruning (FIFO) ==="
sinput string DIV_PRUNE_CORE = "--- Pruning Engine ---";
input bool   UseGridPruning       = false; // Enable pruning
input ENUM_PRUNING_STYLE PruningStyle = PRUNING_SOFT; // Pruning style
input int    PruningLevel         = 5; // Start pruning after level
input bool   UsePruningRecovery   = false; // Recover pruned losses
input double PruningRecovPercent  = 25.0; // Recovery percent per cycle

// === 12. Circuit Breakers & Limits ===
input group "=== 12. Circuit Breakers & Limits ==="
sinput string DIV_PERF_FILTER = "--- Performance Breakers ---";
input ENUM_FILTER_RESET FilterResetMode = FILTER_RESET_DAILY; // Counter reset mode
input int    Filter_MaxOpenTrades = 2; // Max open trades
input bool   Filter_GlobalTradeCount = false; // Use global trade count
input bool   InpGridZoneRecycleSmallestAtMaxTrades = false; // Grid/zone: close smallest sequence trade when max open trades is reached
input int    Filter_MaxWins       = 0; // Max wins
input int    Filter_MaxLosses     = 0; // Max losses
input int    Filter_MaxWinStreak  = 0; // Max win streak
input int    Filter_MaxLossStreak = 0; // Max loss streak
input double Filter_MaxPctLoss    = 0.0; // Max session loss (%)
input double Filter_MaxPctGain    = 0.0; // Max session gain (%)
input int    Filter_BlockWins     = 0; // Max wins per block
input int    Filter_BlockLosses   = 0; // Max losses per block

sinput string DIV_MONEY_LIMITS = "--- Hard Money Limits ---";
input double GlobalTP_Amount      = 0.0; // Global take profit ($)
input double GlobalSL_Amount      = 0.0; // Global stop loss ($)
input bool   UseAccountLimits     = true; // Enable equity limits
input double AccountProfitLimitPct = 1.0; // Account profit cap (%)
input double AccountLossLimitPct  = 2.5; // Account loss cap (%)
input bool   RestartAfterLimit    = true; // Restart after limit hit
input int    AccountLimitCooldownMinutes = 2; // Cooldown (minutes)

// === 13. Engine, Bridge & Integrations ===
input group "=== 13. Engine, Bridge & Integrations ==="
sinput string DIV_OP_MODE = "--- Core Engine ---";
input ENUM_OP_MODE OperationMode = MODE_MIXED; // Operation mode
input bool ForceTimerExecution = false; // Force timer-driven execution
#define InpCustomTimeSeconds ((InpCustomTimeUseSeconds) ? (InpCustomTimeValue) : ((InpCustomTimeValue) * 60))
#define InpHeikenRenkoPoints InpHeikenRenkoBlockSizePoints
#define InpShowSyntheticVisuals false
#define InpCustomNameTag ""

sinput string DIV_TIMEZONE = "--- Timezone Adjustments ---";
input int InpServerGMTOffset  = 2; // Server GMT offset
input int InpNYManualShift    = 0; // New York manual shift

sinput string DIV_BRIDGE_COMMS = "--- Communication Bridge ---";
input string InpSignalPrefix      = "Signal"; // Signal prefix
input string InpHedgeChannel      = "HEDGE_A"; // Hedge channel name

sinput string DIV_BRIDGE_V3     = "--- Bridge V3 Runtime ---";
input bool   InpV3_EnableSQLiteBridge = true; // Use SQLite IPC
input string InpV3_SQLitePath    = "MultiBotPro_v3.db"; // SQLite file name
input bool   InpV3_AsyncHandshake = true; // Async handshake
input int    InpV3_HandshakeTimeoutMs = 3000; // Handshake timeout (ms)
input int    InpV3_HandshakePollMs = 100; // Handshake poll (ms)
input int    InpV3_AsyncExecTimeoutSec = 5; // Async execution timeout (s)
input int    InpV3_PauseCooldownMinutes = 2; // Pause cooldown (minutes)
input int    InpV3_SpreadCheckMs = 1000; // Spread check cadence (ms)
input int    InpV3_HeartbeatIntervalMs = 1000; // Bridge heartbeat (ms)
input int    InpSlaveMirrorGraceSec = 60; // Slave mirror grace period (s)

// === 13B. Diagnostics ===
input group "=== 13B. Diagnostics ==="
sinput string DIV_LOG_TIERS = "--- Journal Print Tiers ---";
input bool   InpLogCritical = true; // Tier 1: critical/safety/failure prints
input bool   InpLogImportant = true; // Tier 2: operational/trade lifecycle prints
input bool   InpLogDebug = true; // Tier 3: debug/trace/noisy prints

sinput string DIV_HEDGE_MAIN = "--- Risk Limits ---";
input ENUM_RISK_MODE_MASTER InpMasterRiskMode = RISK_TRAILING; // Master risk mode
input double   InpMasterRisk       = 1000.0; // Max master risk
input double   InpMasterTargetProfit = 800.0; // Master target profit
input double   InpMasterDailyLoss  = 300.0; // Daily loss limit
input double   InpMasterDailyProfit= 400.0; // Daily profit target
input double   InpStartingBalance  = 5000.0; // Starting balance (0 = auto)
input double   InpSlaveGain        = 100.0; // Slave gain target

sinput string DIV_HEDGE_TRAIL = "--- Trailing Stop Settings ---";
input double   InpTrailPercent     = 10.0; // Trailing percent
input ENUM_TRAIL_BASE InpTrailBase = TRAIL_EQUITY; // Trailing base
input bool     InpEnableSmartHedge = false; // Release slave hedge after second protected SL move

sinput string DIV_SHADOW_AI = "--- AI Configuration ---";
input bool   InpEnableShadowMaster = true; // Enable Shadow Master
input int    InpShadowMasterCycleHours = 6; // Shadow refresh interval (hours)
input string InpShadowConfigName   = "ShadowConfig"; // Shadow config prefix

// === 14. Visuals, UX & Defensive Filters ===
input group "=== 14. Visuals, UX & Defensive Filters ==="
sinput string DIV_DASHBOARD = "--- Dashboard Visuals ---";
input bool   ShowDashboard        = true; // Show dashboard
input bool   InpLiveDragging      = false; // Live drag dashboard
input bool   InpOpaquePanel       = false; // Opaque panel blocks chart objects behind it
input int    InpSyntheticPumpIntervalMs = 100; // Synthetic update cadence (ms, 0 = every cycle)
input bool   ShowBoxLines         = true; // Show box lines
input int    BoxLines_History     = 200; // Box-line history bars
input color  BoxLines_ColorHigh   = (color)32768; // High box-line color
input color  BoxLines_ColorLow    = (color)255; // Low box-line color
input int    BoxLines_Width       = 1; // Box-line width
input ENUM_LINE_STYLE BoxLines_Style = STYLE_DASHDOTDOT; // Box-line style

sinput string DIV_INDICATOR_VISUALS = "--- Indicator Overlays ---";
input bool   InpShowIndicatorOverlay = true; // Show indicator overlay
input bool   InpOverlayUseChartSymbol = true; // Overlay source uses chart symbol
input bool   InpShowMA1Overlay      = false; // Show MA1 overlay
input color  InpMA1OverlayColor     = (color)65280; // MA1 color
input ENUM_LINE_STYLE InpMA1OverlayStyle = STYLE_SOLID; // MA1 style
input int    InpMA1OverlayWidth     = 1; // MA1 width
input bool   InpShowMA2Overlay      = false; // Show MA2 overlay
input color  InpMA2OverlayColor     = (color)32768; // MA2 color
input ENUM_LINE_STYLE InpMA2OverlayStyle = STYLE_SOLID; // MA2 style
input int    InpMA2OverlayWidth     = 1; // MA2 width
input bool   InpShowMA3Overlay      = true; // Show MA3 overlay
input color  InpMA3OverlayColor     = (color)16711680; // MA3 color
input ENUM_LINE_STYLE InpMA3OverlayStyle = STYLE_SOLID; // MA3 style
input int    InpMA3OverlayWidth     = 1; // MA3 width
input bool   InpShowMA4Overlay      = true; // Show MA4 overlay
input color  InpMA4OverlayColor     = (color)2330219; // MA4 color
input ENUM_LINE_STYLE InpMA4OverlayStyle = STYLE_SOLID; // MA4 style
input int    InpMA4OverlayWidth     = 2; // MA4 width
input bool   InpShowMA5Overlay      = false; // Show MA5 overlay
input color  InpMA5OverlayColor     = (color)255; // MA5 color
input ENUM_LINE_STYLE InpMA5OverlayStyle = STYLE_SOLID; // MA5 style
input int    InpMA5OverlayWidth     = 2; // MA5 width
input bool   InpShowVWAP1Overlay    = false; // Show VWAP1 overlay
input color  InpVWAP1OverlayColor   = (color)16776960; // VWAP1 color
input ENUM_LINE_STYLE InpVWAP1OverlayStyle = STYLE_DASHDOT; // VWAP1 style
input int    InpVWAP1OverlayWidth   = 2; // VWAP1 width
input bool   InpShowVWAP3Overlay    = true; // Show VWAP3 overlay
input color  InpVWAP3OverlayColor   = (color)55295; // VWAP3 color
input ENUM_LINE_STYLE InpVWAP3OverlayStyle = STYLE_SOLID; // VWAP3 style
input int    InpVWAP3OverlayWidth   = 2; // VWAP3 width
input bool   InpShowVWAPHighOverlay = true; // Show high VWAP overlay
input color  InpVWAPHighOverlayColor = (color)16711935; // High VWAP color
input ENUM_LINE_STYLE InpVWAPHighOverlayStyle = STYLE_DOT; // High VWAP style
input int    InpVWAPHighOverlayWidth = 1; // High VWAP width
input bool   InpShowVWAPLowOverlay  = true; // Show low VWAP overlay
input color  InpVWAPLowOverlayColor = (color)16711935; // Low VWAP color
input ENUM_LINE_STYLE InpVWAPLowOverlayStyle = STYLE_DOT; // Low VWAP style
input int    InpVWAPLowOverlayWidth = 1; // Low VWAP width
input bool   InpShowVWAPCloud       = false; // Show VWAP cloud
input color  InpVWAPCloudColor      = (color)16775408; // VWAP cloud color
input bool   InpShowIndicatorOverlayLabels = true; // Show overlay labels
input int    InpIndicatorOverlayLabelOffsetPts = 100; // Label offset (points)
input int    InpIndicatorOverlayLabelShiftBars = 3; // Label shift (bars)
input int    InpIndicatorOverlayLabelFontSize = 9; // Label font size

sinput string DIV_NOTIFICATIONS = "--- Notifications ---";
input bool   EnableAlerts         = true; // Popup alerts
input bool   EnableEmailAlerts    = true; // Email alerts
input bool   EnablePushAlerts     = true; // Push alerts

sinput string VELOCITY_PAUSE      = "--- Velocity Pausing ---";
input bool   InpUseVelocityPause  = true; // Enable velocity pause
input int    InpVelocityTicksPerSec = 80; // Pause trigger (ticks/sec)
input int    InpVelocityPauseSeconds = 10; // Pause length (seconds)

sinput string FRACTAL_GRID        = "--- Fractal Elastic Grid ---";
input bool   InpUseFractalGrid    = true; // Enable fractal grid
input int    InpHurstPeriod       = 30; // Hurst lookback
input double InpHurstTrendingThreshold = 0.6; // Trending threshold
input double InpHurstRangingThreshold  = 0.4; // Ranging threshold
input double InpHurstStretchMult  = 1.5; // Trending stretch multiplier
input double InpHurstContractMult = 0.8; // Ranging contract multiplier
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+

// --- NEW RESET GLOBALS ---
bool IsPaused = false;
bool  G_ResetPending   = false;
int   G_ResetCycleCount = 0;
ulong G_ResetTimestamp = 0;
ulong G_LastLossTime   = 0;
ulong G_ResetTickets[];
bool  G_FastChartSwitchMode = false;
bool  G_ForceDashboardRefresh = false;
SMasterUiCommand G_MasterUiCommandQueue[];
int   G_MasterUiCommandHead = 0;
int   G_MasterUiCommandTail = 0;
int   G_MasterUiCommandCount = 0;
int   G_TradeControlJobType = MBP_CONTROL_JOB_NONE;
int   G_TradeControlJobPhase = MBP_CONTROL_PHASE_IDLE;
int   G_TradeControlJobCursor = 0;
int   G_TradeControlJobSymbolIndex = -1;
string G_TradeControlJobReason = "";
// -------------------------
// --- THE REAL SYSTEM VARIABLES ---
// The bot will use these G_ variables for all logic.
int    G_MA1_Period;
int    G_MA2_Period;
int    G_Box_Lookback;
int    G_ADX_Period;
double G_ADX_MinLevel;
double G_CurrencyStrengthDelta;
double G_GridMultiplier;

// --- DASHBOARD GLOBALS ---
bool DashboardCollapsed = false;
bool TemplatesApplied = false;
int  DashboardX = 10;
int  DashboardY = 50;
bool G_DashboardSettingsOpen = false;
int  G_DashboardSettingsModeCursor = 0;
bool G_DataModeOverrideEnabled = false;
ENUM_MBP_DATA_MODE G_DataModeOverride = MBP_DATA_LIVE;
bool IsDragging = false;
int  DragInteractionX = 0;
int  DragInteractionY = 0;
uint G_DashboardHeartbeatStartMs = 0;
bool G_DashboardHeartbeatWasEligible = false;
int G_EntryGateReason[];
string G_EntryGateMessage[];

bool G_DashboardDragArmed = false;
int  G_DashboardDragStartX = 0;
int  G_DashboardDragStartY = 0;
string G_LastDashboardButtonHandled = "";
ulong  G_LastDashboardButtonHandledMs = 0;
bool ConsumeDashboardButtonState(const string btnName);
void RememberDashboardButtonHandled(const string btnName);
bool WasDashboardButtonHandledRecently(const string btnName);
ENUM_MBP_DATA_MODE MBP_EffectiveDataMode();
ENUM_MBP_DATA_MODE MBP_DashboardModeAtCursor(const int cursor);
string MBP_DashboardModeCursorText(const int cursor);
void MasterApplyDashboardDataModeSelection();

// Enum for signal types
enum ENUM_SIGNAL_TYPE
  {
   SIGNAL_NONE,
   SIGNAL_BUY,
   SIGNAL_SELL
  };

// Enum for price position relative to VWAP
enum ENUM_PRICE_POSITION
  {
   POSITION_ABOVE_HIGH,
   POSITION_BELOW_LOW,
   POSITION_ABOVE_VWAP,
   POSITION_BELOW_VWAP,
   POSITION_AT_VWAP
  };

double ReferenceEquity = 0.0;

void InitReferenceEquity()
{
   ReferenceEquity = AccountInfoDouble(ACCOUNT_EQUITY);
}

string GetFastChartSwitchMarkerName()
{
   return StringFormat("MBP_FastSwitch_%I64d", ChartID());
}

void MarkFastChartSwitchPending()
{
   GlobalVariableSet(GetFastChartSwitchMarkerName(), (double)TimeLocal());
}

bool ConsumeFastChartSwitchPending()
{
   string marker = GetFastChartSwitchMarkerName();
   if(!GlobalVariableCheck(marker))
      return false;

   datetime stamp = (datetime)GlobalVariableGet(marker);
   GlobalVariableDel(marker);
   return (stamp > 0 && (TimeLocal() - stamp) <= 10);
}

string GetFastChartSwitchStateFileName()
{
   return StringFormat("MBP_FastSwitch_State_%I64d.bin", ChartID());
}

ENUM_MBP_CHART_MODE MBP_DataModeToChartMode(ENUM_MBP_DATA_MODE mode)
{
   switch(mode)
   {
      case MBP_DATA_RENKO:
      case MBP_DATA_MEDIAN_RENKO:
      case MBP_DATA_TURBO_RENKO:
      case MBP_DATA_HYBRID_RENKO:
         return MBP_CHART_RENKO;
      case MBP_DATA_HEIKEN_ASHI:
         return MBP_CHART_HEIKEN_ASHI;
      case MBP_DATA_HEIKEN_RENKO:
         return MBP_CHART_HEIKEN_RENKO;
      case MBP_DATA_CUSTOM_TIME:
         return MBP_CHART_CUSTOM_TIME;
      default:
         return MBP_CHART_STANDARD;
   }
}

ENUM_MBP_RENKO_FAMILY MBP_DataModeToRenkoFamily(ENUM_MBP_DATA_MODE mode)
{
   switch(mode)
   {
      case MBP_DATA_MEDIAN_RENKO:
         return MBP_RENKO_MEDIAN;
      case MBP_DATA_TURBO_RENKO:
         return MBP_RENKO_TURBO;
      case MBP_DATA_HYBRID_RENKO:
         return MBP_RENKO_HYBRID;
      default:
         return MBP_RENKO_CLASSIC;
   }
}

bool MBP_IsSyntheticDataMode(ENUM_MBP_DATA_MODE mode)
{
   return (mode != MBP_DATA_LIVE);
}

bool MBP_IsRenkoDataMode(ENUM_MBP_DATA_MODE mode)
{
   return (mode == MBP_DATA_RENKO ||
           mode == MBP_DATA_MEDIAN_RENKO ||
           mode == MBP_DATA_TURBO_RENKO ||
           mode == MBP_DATA_HYBRID_RENKO);
}

string MBP_DataModeToText(ENUM_MBP_DATA_MODE mode)
{
   switch(mode)
   {
      case MBP_DATA_RENKO:        return "RENKO";
      case MBP_DATA_MEDIAN_RENKO: return "MEDIAN_RENKO";
      case MBP_DATA_TURBO_RENKO:  return "TURBO_RENKO";
      case MBP_DATA_HYBRID_RENKO: return "HYBRID_RENKO";
      case MBP_DATA_HEIKEN_ASHI:  return "HEIKEN_ASHI";
      case MBP_DATA_HEIKEN_RENKO: return "HEIKEN_RENKO";
      case MBP_DATA_CUSTOM_TIME:  return "CUSTOM_TIME";
      default:                    return "LIVE";
   }
}

ENUM_MBP_DATA_MODE MBP_EffectiveDataMode()
{
   return G_DataModeOverrideEnabled ? G_DataModeOverride : InpDataMode;
}

ENUM_MBP_DATA_MODE MBP_DashboardModeAtCursor(const int cursor)
{
   switch(cursor)
   {
      case 1: return MBP_DATA_LIVE;
      case 2: return MBP_DATA_RENKO;
      case 3: return MBP_DATA_MEDIAN_RENKO;
      case 4: return MBP_DATA_TURBO_RENKO;
      case 5: return MBP_DATA_HYBRID_RENKO;
      case 6: return MBP_DATA_HEIKEN_ASHI;
      case 7: return MBP_DATA_HEIKEN_RENKO;
      case 8: return MBP_DATA_CUSTOM_TIME;
      default: return InpDataMode;
   }
}

string MBP_DashboardModeCursorText(const int cursor)
{
   if(cursor <= 0)
      return "DEFAULT (" + MBP_DataModeToText(InpDataMode) + ")";

   return MBP_DataModeToText(MBP_DashboardModeAtCursor(cursor));
}

bool IsBridgeRuntimeEnabled()
{
   return (BotSystemMode == BOT_MODE_MASTER);
}

string ResolveManagedAnalysisSymbol(const int symbolIndex)
{
   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return "";

   ENUM_MBP_DATA_MODE effectiveMode = SymbolData[symbolIndex].DataMode;
   if(effectiveMode == MBP_DATA_LIVE)
      effectiveMode = MBP_EffectiveDataMode();

   string baseSym = SymbolData[symbolIndex].BaseSymbol;
   if(baseSym == "")
      baseSym = GetBaseSymbol(SymbolData[symbolIndex].symbol);
   if(baseSym == "")
      baseSym = SymbolData[symbolIndex].symbol;

   if(MBP_IsSyntheticDataMode(effectiveMode))
   {
      string syntheticSym = ResolveSyntheticChartSymbolName(baseSym, effectiveMode);
      if(syntheticSym != "")
         return syntheticSym;
   }

   if(SymbolData[symbolIndex].AnalysisSymbol != "")
      return SymbolData[symbolIndex].AnalysisSymbol;

   if(SymbolData[symbolIndex].symbol != "")
      return SymbolData[symbolIndex].symbol;

   return baseSym;
}

void SaveFastChartSwitchDashboardState()
{
   int handle = FileOpen(GetFastChartSwitchStateFileName(), FILE_COMMON|FILE_WRITE|FILE_BIN);
   if(handle == INVALID_HANDLE)
      return;

   FileWriteInteger(handle, DashboardX, INT_VALUE);
   FileWriteInteger(handle, DashboardY, INT_VALUE);
   FileWriteDouble(handle, Dash_Scale);
   FileWriteInteger(handle, DashboardCollapsed ? 1 : 0, INT_VALUE);
   FileWriteInteger(handle, ShowManualSection ? 1 : 0, INT_VALUE);
   FileWriteInteger(handle, ShowTradeList ? 1 : 0, INT_VALUE);
   FileWriteDouble(handle, Panel_ManualLot);
   FileWriteString(handle, G_DashboardFocusBaseSymbol);
   FileClose(handle);
}

void RestoreFastChartSwitchDashboardState()
{
   string fileName = GetFastChartSwitchStateFileName();
   if(!FileIsExist(fileName, FILE_COMMON))
      return;

   int handle = FileOpen(fileName, FILE_COMMON|FILE_READ|FILE_BIN);
   if(handle == INVALID_HANDLE)
      return;

   DashboardX = FileReadInteger(handle, INT_VALUE);
   DashboardY = FileReadInteger(handle, INT_VALUE);
   Dash_Scale = FileReadDouble(handle);
   DashboardCollapsed = (FileReadInteger(handle, INT_VALUE) != 0);
   ShowManualSection = (FileReadInteger(handle, INT_VALUE) != 0);
   ShowTradeList = (FileReadInteger(handle, INT_VALUE) != 0);
   Panel_ManualLot = FileReadDouble(handle);
   G_DashboardFocusBaseSymbol = FileReadString(handle);
   FileClose(handle);

   G_DashboardDragArmed = false;
   IsDragging = false;
   DragInteractionX = 0;
   DragInteractionY = 0;
   G_LastDashboardButtonHandled = "";
   G_LastDashboardButtonHandledMs = 0;
   Panel_IsModifying = false;
   Panel_SelectedTicket = 0;

   FileDelete(fileName, FILE_COMMON);
}

void ResetDashboardHeartbeat()
{
   G_DashboardHeartbeatStartMs = GetTickCount();
   G_DashboardHeartbeatWasEligible = false;
}

void EnsureMasterDashboardReady(const bool forceRebuild = false)
{
   if(!ShowDashboard)
      return;

   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);

   if(IsDragging || G_DashboardDragArmed)
      return;

   bool missingCorePanel = (ObjectFind(0, "Dash_BG") < 0);
   if(forceRebuild || missingCorePanel)
   {
      if(missingCorePanel && !forceRebuild)
         if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("Dashboard core objects missing on the EA chart. Recreating dashboard.");

      DestroyDashboard();
      CreateDashboard();
   }

   UpdateDashboard(0);
}

bool HasManagedBotPositionsGlobal()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
         return true;
   }

   return false;
}

bool IsDashboardEligibleToSearch()
{
   if(IsPaused || G_Cache_SystemBlocked || G_Cache_IsHardBlock)
      return false;

   if(!G_Cache_IsTradingTime || G_Cache_IsNewsTime)
      return false;

   return true;
}

bool IsDashboardHeartbeatVisibleNow()
{
   bool eligibleToSearch = IsDashboardEligibleToSearch();

   if(!eligibleToSearch)
   {
      G_DashboardHeartbeatWasEligible = false;
      return false;
   }

   if(HasManagedBotPositionsGlobal())
   {
      G_DashboardHeartbeatWasEligible = false;
      return false;
   }

   uint nowMs = GetTickCount();
   if(G_DashboardHeartbeatStartMs == 0 || !G_DashboardHeartbeatWasEligible)
      G_DashboardHeartbeatStartMs = nowMs;

   G_DashboardHeartbeatWasEligible = true;

   uint cycleOffset = (nowMs - G_DashboardHeartbeatStartMs) % DASH_HEARTBEAT_CYCLE_MS;
   if(cycleOffset >= DASH_HEARTBEAT_ACTIVE_MS)
      return false;

   uint blinkPhase = cycleOffset / DASH_HEARTBEAT_BLINK_MS;
   return ((blinkPhase % 2) == 0);
}

// Global variables
CPositionInfo PositionInfo;
CAccountInfo AccountInfo;
CHistoryOrderInfo HistoryOrder;

// Arrays for timeframes
ENUM_TIMEFRAMES Timeframes[7];
bool TimeframeEnabled[7];

// Multi-symbol management
SSymbolData SymbolData[];
string TradingSymbols[];
int TradingSymbolsCount = 0;
string ExcludedSymbols[];
bool GlobalTradingEnabled = true;
double GlobalTotalProfit = 0;
double GlobalTotalLoss = 0;
datetime LastGlobalCheck = 0;
double DailyGlobalProfit = 0;
double DailyGlobalLoss = 0;
datetime LastGlobalDailyReset = 0;

enum ENUM_MBP_LOG_TIER
{
   MBP_LOG_TIER_CRITICAL = 1,
   MBP_LOG_TIER_IMPORTANT = 2,
   MBP_LOG_TIER_DEBUG = 3
};

bool MBP_LogTierEnabled(const ENUM_MBP_LOG_TIER tier)
{
   if(tier == MBP_LOG_TIER_CRITICAL)
      return InpLogCritical;
   if(tier == MBP_LOG_TIER_IMPORTANT)
      return InpLogImportant;
   if(tier == MBP_LOG_TIER_DEBUG)
      return InpLogDebug;
   return true;
}


// 2. INCLUDE DASHBOARD ELEMENTS
#include "MultiBotPro_SymbolContext.mqh"
#include "MultiBotPro_BundleHelpers.mqh"
#include "MultiBotPro_AIBridge.mqh"
#include "MultiBotPro_Dashboard.mqh"
#include "MultiBotPro_Helpers.mqh"
#include "MultiBotPro_Indicators.mqh"
#include "MultiBotPro_VisualOverlay.mqh"
#include "MultiBotPro_Risk.mqh"
#include "MultiBotPro_TradeEntry.mqh"
#include "MultiBotPro_GridZone_State.mqh"
#include "MultiBotPro_GridZone_Positions.mqh"
#include "MultiBotPro_GridZone_Analysis.mqh"
#include "MultiBotPro_GridZone_Recovery.mqh"
#include "MultiBotPro_GUI.mqh"
#include "MultiBotPro_MasterRuntime.mqh"
#include "MultiBotPro_ChartFactory.mqh"
#include "MultiBotPro_Renko.mqh"
#include "MultiBotPro_HeikenRenko.mqh"
#include "MultiBotPro_HeikenAshi.mqh"
#include "MultiBotPro_CustomTime.mqh"

// === NEW MODULAR COMPONENTS ===
#include "MultiBotPro_SystemState.mqh"
#include "MultiBotPro_MessageQueue.mqh"
#include "MultiBotPro_RiskEngine.mqh"
#include "MultiBotPro_BoundsChecking.mqh"
#include "MultiBotPro_SystemTests.mqh"
#include "MultiBotPro_Coordinator.mqh"

// Global System State Instance
CSystemState G_SystemState;

// Global Message Queue for Coordinator↔Worker Communication
CMbpMessageQueue G_CoordinatorQueue;
CMbpMessageQueue G_WorkerQueue;

// Global Risk Engine Instance
CRiskEngine G_RiskEngine(&G_SystemState);

// Global Coordinator Instance (Master orchestration)
CCoordinator G_Coordinator(&G_SystemState, &G_CoordinatorQueue, &G_WorkerQueue, &G_RiskEngine);

string MBP_PathJoin(string leftPath, string rightPath)
{
   if(leftPath == "")
      return rightPath;
   if(rightPath == "")
      return leftPath;

   string tail = StringSubstr(leftPath, StringLen(leftPath) - 1, 1);
   if(tail == "\\" || tail == "/")
      return leftPath + rightPath;

   return leftPath + "\\" + rightPath;
}

string ShadowMaster_JsonEscape(string value)
{
   string escaped = value;
   StringReplace(escaped, "\\", "\\\\");
   StringReplace(escaped, "\"", "\\\"");
   StringReplace(escaped, "\r", "");
   StringReplace(escaped, "\n", "\\n");
   StringReplace(escaped, "\t", "\\t");
   return escaped;
}

bool ShadowMaster_IsAiRuntimeEnabled()
{
   return InpEnableShadowMaster;
}

string MBP_GetTerminalFilesPath()
{
   return TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files";
}

string MBP_DefaultCoordinatorKey()
{
   string serverName = AccountInfoString(ACCOUNT_SERVER);
   if(serverName == "")
      serverName = TerminalInfoString(TERMINAL_COMPANY);

   string channel = MBP_SanitizeRuntimeToken(InpHedgeChannel);
   if(StringLen(channel) > 12)
      channel = StringSubstr(channel, 0, 12);

   uint serverHash = (uint)MBP_StableStringHash(serverName);

   return StringFormat("%s_%I64d_%08X",
                       channel,
                       (long)AccountInfoInteger(ACCOUNT_LOGIN),
                       serverHash);
}

string MBP_GetActiveCoordinatorKey()
{
   if(G_RuntimeCoordinatorKey != "")
      return G_RuntimeCoordinatorKey;

   return MBP_DefaultCoordinatorKey();
}

bool MBP_CoordinatorKeyMatchesRuntime(const string assignedKey, const string activeKey)
{
   if(activeKey == "" || assignedKey == "")
      return true;
   if(StringCompare(assignedKey, activeKey, false) == 0)
      return true;

   string channel = MBP_SanitizeRuntimeToken(InpHedgeChannel);
   if(StringLen(channel) > 12)
      channel = StringSubstr(channel, 0, 12);
   string channelPrefix = channel + "_";
   return (StringFind(assignedKey, channelPrefix) == 0 &&
           StringFind(activeKey, channelPrefix) == 0);
}

string MBP_WorkerLaunchMarkerName(const long chartId)
{
   return StringFormat("MBP_WorkerToken_%I64d", chartId);
}

void MBP_WriteWorkerLaunchMarker(const long workerChartId)
{
   if(workerChartId <= 0)
      return;

   string tokenName = MBP_WorkerLaunchMarkerName(workerChartId);
   GlobalVariableSet(tokenName, (double)ChartID());
   GlobalVariableSet(tokenName + "_exp", (double)(MBP_RuntimeServerNow() + MBP_WORKER_LAUNCH_GRACE_SEC));
}

void MBP_ClearWorkerLaunchMarker(const long workerChartId)
{
   if(workerChartId <= 0)
      return;

   string tokenName = MBP_WorkerLaunchMarkerName(workerChartId);
   if(GlobalVariableCheck(tokenName))
      GlobalVariableDel(tokenName);
   if(GlobalVariableCheck(tokenName + "_exp"))
      GlobalVariableDel(tokenName + "_exp");
}

// Non-consuming check used by chart-reuse logic: returns true if the marker exists
// AND has not yet expired. Does not delete the marker.
bool MBP_HasWorkerLaunchMarker(const long workerChartId)
{
   if(workerChartId <= 0)
      return false;

   string tokenName = MBP_WorkerLaunchMarkerName(workerChartId);
   if(!GlobalVariableCheck(tokenName))
      return false;

   double expiry = GlobalVariableCheck(tokenName + "_exp") ? GlobalVariableGet(tokenName + "_exp") : 0.0;
   if(expiry <= 0.0 || (double)MBP_RuntimeServerNow() >= expiry)
      return false;

   return true;
}

bool MBP_ConsumeWorkerLaunchMarker(const long workerChartId, double &coordinatorChartId)
{
   string tokenName = MBP_WorkerLaunchMarkerName(workerChartId);
   if(!GlobalVariableCheck(tokenName))
      return false;

   coordinatorChartId = GlobalVariableGet(tokenName);
   double expiry = GlobalVariableCheck(tokenName + "_exp") ? GlobalVariableGet(tokenName + "_exp") : 0.0;
   if(coordinatorChartId <= 0.0 || expiry <= 0.0 || (double)MBP_RuntimeServerNow() >= expiry)
   {
      MBP_ClearWorkerLaunchMarker(workerChartId);
      return false;
   }

   MBP_ClearWorkerLaunchMarker(workerChartId);
   return true;
}

void MBP_PurgeWorkerLaunchMarkers()
{
   string prefix = "MBP_WorkerToken_";
   for(int i = GlobalVariablesTotal() - 1; i >= 0; i--)
   {
      string name = GlobalVariableName(i);
      if(StringFind(name, prefix) == 0)
         GlobalVariableDel(name);
   }
}

string ShadowMaster_GetRuntimeConfigPath()
{
   return TerminalInfoString(TERMINAL_COMMONDATA_PATH) + "\\Files\\MultiBotPro2\\runtime_v3.json";
}

string ShadowMaster_RuntimeStatusFileName()
{
   return "ShadowMasterRuntime.json";
}

string MBP_SanitizeRuntimeToken(string value)
{
   string cleaned = value;
   string badChars[] = {"\\", "/", ":", "*", "?", "\"", "<", ">", "|", " ", "\t", "\r", "\n"};
   for(int i = 0; i < ArraySize(badChars); i++)
      StringReplace(cleaned, badChars[i], "_");

   return cleaned;
}

string MBP_WorkerTemplateName()
{
   return "MultiBotPro_Worker_" + MBP_SanitizeRuntimeToken(MBP_GetActiveCoordinatorKey()) + ".tpl";
}

string MBP_WorkerAssignmentFile(const long chartId)
{
   return StringFormat("MBP_WorkerAssign_%s_%I64d.txt",
                       MBP_SanitizeRuntimeToken(InpHedgeChannel),
                       chartId);
}

string MBP_WorkerHeartbeatFile(const string symbol, const string coordinatorKey = "")
{
   string activeKey = coordinatorKey;
   if(activeKey == "")
      activeKey = MBP_GetActiveCoordinatorKey();

   return StringFormat("MBP_WorkerHeartbeat_%s_%s.txt",
                       MBP_SanitizeRuntimeToken(activeKey),
                       MBP_SanitizeRuntimeToken(symbol));
}

string MBP_WorkerHeartbeatGlobalBase(const string symbol, const string coordinatorKey = "")
{
   string activeKey = coordinatorKey;
   if(activeKey == "")
      activeKey = MBP_GetActiveCoordinatorKey();

   return StringFormat("MBP_WH_%s_%s",
                       MBP_SanitizeRuntimeToken(activeKey),
                       MBP_SanitizeRuntimeToken(symbol));
}

int MBP_StableStringHash(const string value)
{
   long hash = 2166136261;
   for(int i = 0; i < StringLen(value); i++)
   {
      hash = (hash ^ StringGetCharacter(value, i)) * 16777619;
      hash = MathAbs(hash % 1000000007);
   }

   return (int)MathAbs(hash);
}

string MBP_WorkerHeartbeatSignatureHashMarker(const string assignmentSignature)
{
   if(assignmentSignature == "")
      return "";

   return "hash:" + IntegerToString(MBP_StableStringHash(assignmentSignature));
}

bool MBP_WorkerHeartbeatSignatureMatches(const string heartbeatSignature,
                                         const string assignmentSignature)
{
   if(assignmentSignature == "")
      return true;
   if(heartbeatSignature == "")
      return false;

   if(StringCompare(heartbeatSignature, assignmentSignature, false) == 0)
      return true;

   string expectedHash = MBP_WorkerHeartbeatSignatureHashMarker(assignmentSignature);
   return (expectedHash != "" && StringCompare(heartbeatSignature, expectedHash, false) == 0);
}

int MBP_WorkerHeartbeatStateCode(const string state)
{
   if(StringCompare(state, "RUNNING", false) == 0)
      return 1;
   if(StringCompare(state, "RELOADING", false) == 0)
      return 2;
   if(StringCompare(state, "STOPPED", false) == 0)
      return 3;
   if(StringCompare(state, "BUILDING_RENKO", false) == 0)
      return 4;
   if(StringCompare(state, "SYNCING_HISTORY", false) == 0)
      return 5;
   if(StringCompare(state, "STOPPING", false) == 0)
      return 6;
   if(StringCompare(state, "ERROR", false) == 0)
      return 7;
   return 0;
}

string MBP_WorkerHeartbeatStateFromCode(const int stateCode)
{
   if(stateCode == 1)
      return "RUNNING";
   if(stateCode == 2)
      return "RELOADING";
   if(stateCode == 3)
      return "STOPPED";
   if(stateCode == 4)
      return "BUILDING_RENKO";
   if(stateCode == 5)
      return "SYNCING_HISTORY";
   if(stateCode == 6)
      return "STOPPING";
   if(stateCode == 7)
      return "ERROR";
   return "BOOTING";
}

bool MBP_IsWorkerHeartbeatGraceState(const string state)
{
   return (StringCompare(state, "RELOADING", false) == 0 ||
           StringCompare(state, "BOOTING", false) == 0 ||
           StringCompare(state, "BUILDING_RENKO", false) == 0 ||
           StringCompare(state, "SYNCING_HISTORY", false) == 0);
}

bool MBP_IsWorkerRenkoBuildState(const string state)
{
   return (StringCompare(state, "BUILDING_RENKO", false) == 0);
}

int MBP_WorkerHeartbeatAgeSeconds(const datetime heartbeat)
{
   if(heartbeat <= 0)
      return 2147483647;

   datetime now = MBP_RuntimeServerNow();
   if(now <= 0 || now < heartbeat)
      return 0;

   return (int)(now - heartbeat);
}

bool MBP_IsWorkerHeartbeatFreshForState(const datetime heartbeat, const string state)
{
   if(heartbeat <= 0)
      return false;

   datetime now = MBP_RuntimeServerNow();
   if(now <= 0)
      return true;

   // A broker/server clock can move backwards or temporarily lag while the worker
   // continues publishing. Do not reject a future heartbeat as stale; only reject
   // genuinely old records. The bounded skew also prevents corrupt timestamps from
   // being treated as permanently fresh.
   if(heartbeat > now)
      return ((heartbeat - now) <= MBP_WORKER_HEARTBEAT_TIME_SKEW_SEC);

   int ageSec = (int)(now - heartbeat);
   int maxAgeSec = MBP_IsWorkerHeartbeatGraceState(state) ? MBP_WORKER_GRACE_STALE_SEC : MBP_WORKER_READY_STALE_SEC;
   return (ageSec <= maxAgeSec);
}

string MBP_ReadTextFileCommon(const string fileName)
{
   int handle = FileOpen(fileName, FILE_READ|FILE_BIN|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(handle == INVALID_HANDLE)
      return "";

   int payloadSize = (int)FileSize(handle);
   if(payloadSize <= 0)
   {
      FileClose(handle);
      return "";
   }

   uchar payloadBytes[];
   ArrayResize(payloadBytes, payloadSize);
   int bytesRead = (int)FileReadArray(handle, payloadBytes, 0, payloadSize);
   FileClose(handle);
   if(bytesRead <= 0)
      return "";

   return CharArrayToString(payloadBytes, 0, bytesRead, CP_ACP);
}

string MBP_ReadKeyValue(const string payload, const string key)
{
   string needle = key + "=";
   int start = StringFind(payload, needle);
   if(start < 0)
      return "";

   start += StringLen(needle);
   int end = StringFind(payload, "\n", start);
   if(end < 0)
      end = StringLen(payload);

   string value = StringSubstr(payload, start, end - start);
   StringReplace(value, "\r", "");
   return value;
}

bool MBP_IsChartAlive(const long chartId)
{
   if(chartId <= 0)
      return false;

   string chartSymbol = ChartSymbol(chartId);
   return (chartSymbol != "");
}

string MBP_CoordAliveGVName(const string coordinatorKey)
{
   return "MBP_COORD_ALIVE_" + coordinatorKey;
}

string MBP_CoordOwnerGVName(const string coordinatorKey)
{
   return "MBP_COORD_OWNER_" + coordinatorKey;
}

string MBP_CoordOwnerHighGVName(const string coordinatorKey)
{
   return "MBP_COORD_OWNER_HI_" + coordinatorKey;
}

string MBP_CoordOwnerLowGVName(const string coordinatorKey)
{
   return "MBP_COORD_OWNER_LO_" + coordinatorKey;
}

string MBP_CoordPausedGVName(const string coordinatorKey)
{
   return "MBP_COORD_PAUSED_" + coordinatorKey;
}

string MBP_CoordResetGVName(const string coordinatorKey)
{
   return "MBP_COORD_RESET_" + coordinatorKey;
}

void MBP_SetCoordinatorPaused(const string coordinatorKey, const bool paused)
{
   if(coordinatorKey == "")
      return;

   GlobalVariableSet(MBP_CoordPausedGVName(coordinatorKey), paused ? 1.0 : 0.0);
}

void MBP_SetCoordinatorResetting(const string coordinatorKey, const bool resetting)
{
   if(coordinatorKey == "")
      return;

   GlobalVariableSet(MBP_CoordResetGVName(coordinatorKey), resetting ? 1.0 : 0.0);
}

bool MBP_IsCoordinatorPaused(const string coordinatorKey)
{
   if(coordinatorKey == "")
      return false;

   string gvName = MBP_CoordPausedGVName(coordinatorKey);
   if(!GlobalVariableCheck(gvName))
      return false;

   return (GlobalVariableGet(gvName) > 0.5);
}

bool MBP_IsCoordinatorResetting(const string coordinatorKey)
{
   if(coordinatorKey == "")
      return false;

   string gvName = MBP_CoordResetGVName(coordinatorKey);
   if(!GlobalVariableCheck(gvName))
      return false;

   return (GlobalVariableGet(gvName) > 0.5);
}

bool IsBotPaused()
{
   if(IsPaused)
      return true;

   if(IsParallelWorkerMode() && G_RuntimeCoordinatorKey != "")
   {
      if(MBP_IsCoordinatorPaused(G_RuntimeCoordinatorKey) || MBP_IsCoordinatorResetting(G_RuntimeCoordinatorKey))
         return true;
   }

   return false;
}

void MBP_WriteCoordinatorAliveHeartbeat(const string coordinatorKey, const long chartId)
{
   if(coordinatorKey == "" || chartId <= 0)
      return;

   static ulong lastCoordHbMs = 0;
   ulong now = GetTickCount64();
   if(lastCoordHbMs > 0 && (now - lastCoordHbMs) < 250)
      return;
   lastCoordHbMs = now;

   GlobalVariableSet(MBP_CoordAliveGVName(coordinatorKey), (double)now);

   // Keep the legacy owner GV for diagnostics, but store an exact split id too:
   // MT5 chart ids exceed double's exact integer range and otherwise round-trip
   // to a different id, making ChartSymbol(ownerChart) fail spuriously.
   GlobalVariableSet(MBP_CoordOwnerGVName(coordinatorKey), (double)chartId);
   long high = chartId / 1000000;
   long low = chartId - (high * 1000000);
   GlobalVariableSet(MBP_CoordOwnerHighGVName(coordinatorKey), (double)high);
   GlobalVariableSet(MBP_CoordOwnerLowGVName(coordinatorKey), (double)low);
}

long MBP_ReadCoordinatorOwnerChartId(const string coordinatorKey)
{
   if(coordinatorKey == "")
      return 0;

   string highName = MBP_CoordOwnerHighGVName(coordinatorKey);
   string lowName = MBP_CoordOwnerLowGVName(coordinatorKey);
   if(GlobalVariableCheck(highName) && GlobalVariableCheck(lowName))
   {
      long high = (long)GlobalVariableGet(highName);
      long low = (long)GlobalVariableGet(lowName);
      if(high > 0 || low > 0)
         return (high * 1000000) + low;
   }

   string legacyName = MBP_CoordOwnerGVName(coordinatorKey);
   return GlobalVariableCheck(legacyName) ? (long)GlobalVariableGet(legacyName) : 0;
}

void MBP_DeleteCoordinatorAliveHeartbeat(const string coordinatorKey)
{
   if(coordinatorKey == "")
      return;

   string names[6];
   names[0] = MBP_CoordAliveGVName(coordinatorKey);
   names[1] = MBP_CoordOwnerGVName(coordinatorKey);
   names[2] = MBP_CoordOwnerHighGVName(coordinatorKey);
   names[3] = MBP_CoordOwnerLowGVName(coordinatorKey);
   names[4] = MBP_CoordPausedGVName(coordinatorKey);
   names[5] = MBP_CoordResetGVName(coordinatorKey);
   for(int i = 0; i < 6; i++)
      if(GlobalVariableCheck(names[i]))
         GlobalVariableDel(names[i]);
}

bool MBP_WaitForChartTargetReady(const long chartId,
                                 const string expectedSymbol,
                                 const uint timeoutMs = 4000)
{
   if(chartId <= 0)
      return false;

   // ChartOpen/ChartApplyTemplate settle through the target chart's own queue.
   // Keep coordinator timers non-blocking and let later ensure passes observe readiness.
   if(!MBP_IsChartAlive(chartId))
      return false;

   string chartSymbol = ChartSymbol(chartId);
   return (expectedSymbol == "" || StringCompare(chartSymbol, expectedSymbol, false) == 0);
}

bool MBP_WriteWorkerHeartbeatRecord(const string workerSymbol,
                                    const string coordinatorKey,
                                    const string assignedChartSymbol,
                                    const string assignedSymbolsCsv,
                                    const string assignmentSignature,
                                    const string state,
                                    const int linkedPositions,
                                    const datetime heartbeatTime,
                                    const long chartId)
{
   if(workerSymbol == "" || chartId <= 0)
      return false;

   datetime effectiveHeartbeat = (heartbeatTime > 0) ? heartbeatTime : MBP_RuntimeServerNow();
   bool sqlitePublished = false;
   if(InpV3_EnableSQLiteBridge && V3_RuntimeEnabled(InpV3_EnableSQLiteBridge, InpV3_SQLitePath))
   {
      sqlitePublished = V3_UpsertWorkerStatus(InpV3_SQLitePath,
                                              coordinatorKey,
                                              workerSymbol,
                                              chartId,
                                              assignedChartSymbol,
                                              assignedSymbolsCsv,
                                              assignmentSignature,
                                              state,
                                              linkedPositions,
                                              effectiveHeartbeat);
   }

   string globalBase = MBP_WorkerHeartbeatGlobalBase(workerSymbol, coordinatorKey);
   bool globalPublished = (GlobalVariableSet(globalBase + "_ts", (double)effectiveHeartbeat) != 0);
   GlobalVariableSet(globalBase + "_chart", (double)chartId);
   long chartHigh = chartId / 1000000;
   long chartLow = chartId - (chartHigh * 1000000);
   GlobalVariableSet(globalBase + "_chart_hi", (double)chartHigh);
   GlobalVariableSet(globalBase + "_chart_lo", (double)chartLow);
   GlobalVariableSet(globalBase + "_state", (double)MBP_WorkerHeartbeatStateCode(state));
   if(assignmentSignature != "")
      GlobalVariableSet(globalBase + "_sig", (double)MBP_StableStringHash(assignmentSignature));

   static ulong lastWorkerFileWriteMs = 0;
   static string lastWorkerFileState = "";
   ulong nowMs = GetTickCount();
   bool stateChanged = (state != lastWorkerFileState);
   bool fileCadenceDue = (lastWorkerFileWriteMs == 0 || (nowMs - lastWorkerFileWriteMs) >= 2000);

   if(!stateChanged && !fileCadenceDue)
      return (sqlitePublished || globalPublished);

   lastWorkerFileWriteMs = nowMs;
   lastWorkerFileState = state;

   int handle = FileOpen(MBP_WorkerHeartbeatFile(workerSymbol, coordinatorKey), FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(handle == INVALID_HANDLE)
   {
      static ulong lastHeartbeatWriteFailLogMs = 0;
      ulong nowMs = GetTickCount();
      if(lastHeartbeatWriteFailLogMs == 0 || (nowMs - lastHeartbeatWriteFailLogMs) >= 10000)
      {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(EmojiWarning(), " Worker heartbeat file write failed for ", workerSymbol,
               " key=", coordinatorKey, " Error=", _LastError,
               ". Global heartbeat fallback is ", (globalPublished ? "active" : "unavailable"), ".");
         lastHeartbeatWriteFailLogMs = nowMs;
      }
      return (sqlitePublished || globalPublished);
   }

   FileWriteString(handle, "symbol=" + workerSymbol + "\r\n");
   if(assignedChartSymbol != "")
      FileWriteString(handle, "chart_symbol=" + assignedChartSymbol + "\r\n");
   if(assignedSymbolsCsv != "")
      FileWriteString(handle, "symbols=" + assignedSymbolsCsv + "\r\n");
   if(assignmentSignature != "")
      FileWriteString(handle, "signature=" + assignmentSignature + "\r\n");
   FileWriteString(handle, StringFormat("chart_id=%I64d\r\n", chartId));
   FileWriteString(handle, "heartbeat=" + IntegerToString((int)effectiveHeartbeat) + "\r\n");
   FileWriteString(handle, "state=" + state + "\r\n");
   FileWriteString(handle, "positions=" + IntegerToString(MathMax(0, linkedPositions)) + "\r\n");
   FileWriteString(handle, "role=WORKER\r\n");
   FileClose(handle);
   return true;
}

bool MBP_ShouldMarkWorkerReloadingOnDeinit(const int reason)
{
   return (reason == REASON_TEMPLATE ||
           reason == REASON_PARAMETERS ||
           reason == REASON_CHARTCHANGE ||
           reason == REASON_RECOMPILE);
}

long MBP_FindReusableChartBySymbol(const string symbol, const long excludedChartId = 0)
{
   // SAFETY: Only reuse charts that already carry a worker launch marker — i.e. charts
   // we previously spawned and lost track of. Reusing arbitrary charts with a matching
   // symbol could hijack the user's analysis charts (overwrite their template and turn
   // them into workers).
   long chartId = ChartFirst();
   while(chartId >= 0)
   {
      if(chartId != excludedChartId && StringCompare(ChartSymbol(chartId), symbol, false) == 0)
      {
         string assignedSymbol = "";
         string assignedSymbolsCsv = "";
         string assignedChartSymbol = "";
         string assignedCoordinatorKey = "";
         long assignedCoordinatorChartId = 0;
         string assignedSignature = "";
         datetime assignedAt = 0;
         bool hasAssignment = MBP_ReadWorkerAssignment(chartId,
                                                       assignedSymbol,
                                                       assignedSymbolsCsv,
                                                       assignedChartSymbol,
                                                       assignedCoordinatorKey,
                                                       assignedCoordinatorChartId,
                                                       assignedSignature,
                                                       assignedAt);
         // Only reuse if the chart carries our launch marker (i.e. we created it).
         // User-opened charts with a matching symbol but no marker are skipped.
         if(!hasAssignment && MBP_HasWorkerLaunchMarker(chartId))
            return chartId;
      }
      chartId = ChartNext(chartId);
   }

   return 0;
}

long MBP_FindProtectedWorkerChartBySymbol(const string chartSymbol,
                                          const string workerSymbol,
                                          const string coordinatorKey,
                                          const string assignmentSignature,
                                          const long excludedChartId = 0)
{
   if(chartSymbol == "")
      return 0;

   string targetBase = GetBaseSymbol(workerSymbol);
   if(targetBase == "")
      targetBase = workerSymbol;
   if(targetBase == "")
      targetBase = GetBaseSymbol(chartSymbol);
   if(targetBase == "")
      targetBase = chartSymbol;

   long chartId = ChartFirst();
   while(chartId >= 0)
   {
      if(chartId != excludedChartId &&
         StringCompare(ChartSymbol(chartId), chartSymbol, false) == 0)
      {
         string assignedSymbol = "";
         string assignedSymbolsCsv = "";
         string assignedChartSymbol = "";
         string assignedCoordinatorKey = "";
         long assignedCoordinatorChartId = 0;
         string chartAssignedSignature = "";
         datetime assignedAt = 0;
         bool hasAssignment = MBP_ReadWorkerAssignment(chartId,
                                                       assignedSymbol,
                                                       assignedSymbolsCsv,
                                                       assignedChartSymbol,
                                                       assignedCoordinatorKey,
                                                       assignedCoordinatorChartId,
                                                       chartAssignedSignature,
                                                       assignedAt);

         if(hasAssignment &&
            MBP_CoordinatorKeyMatchesRuntime(assignedCoordinatorKey, coordinatorKey))
         {
            bool signatureMatches = (assignmentSignature != "" &&
                                     chartAssignedSignature != "" &&
                                     StringCompare(chartAssignedSignature, assignmentSignature, false) == 0);
            string assignedBase = GetBaseSymbol(assignedSymbol);
            if(assignedBase == "")
               assignedBase = assignedSymbol;
            bool symbolMatches = (targetBase != "" &&
                                  StringCompare(assignedBase, targetBase, false) == 0);
            bool chartSymbolMatches = (assignedChartSymbol == "" ||
                                       StringCompare(assignedChartSymbol, chartSymbol, false) == 0);

            if(chartSymbolMatches && (signatureMatches || symbolMatches) &&
               MBP_IsWorkerAssignmentInLaunchGrace(assignedAt, 0))
               return chartId;
         }

         datetime heartbeat = 0;
         long heartbeatChartId = 0;
         string heartbeatSymbolsCsv = "";
         string heartbeatSignature = "";
         string heartbeatState = "";
         if(MBP_ReadWorkerHeartbeat(targetBase,
                                    coordinatorKey,
                                    heartbeat,
                                    heartbeatChartId,
                                    heartbeatSymbolsCsv,
                                    heartbeatSignature,
                                    heartbeatState) &&
            heartbeatChartId == chartId &&
            MBP_WorkerHeartbeatSignatureMatches(heartbeatSignature, assignmentSignature) &&
            MBP_IsWorkerHeartbeatFreshForState(heartbeat, heartbeatState))
         {
            return chartId;
         }

         if(!hasAssignment && MBP_HasWorkerLaunchMarker(chartId))
            return chartId;
      }

      chartId = ChartNext(chartId);
   }

   return 0;
}

long MBP_FindAssignedWorkerChart(const string symbol,
                                 const string coordinatorKey,
                                 const string assignmentSignature,
                                 const long excludedChartId = 0)
{
   string targetBase = GetBaseSymbol(symbol);
   if(targetBase == "")
      targetBase = symbol;

   datetime heartbeat = 0;
   long heartbeatChartId = 0;
   string heartbeatSymbolsCsv = "";
   string heartbeatSignature = "";
   string heartbeatState = "";
   if(MBP_ReadWorkerHeartbeat(symbol,
                              coordinatorKey,
                              heartbeat,
                              heartbeatChartId,
                              heartbeatSymbolsCsv,
                              heartbeatSignature,
                              heartbeatState))
   {
      bool heartbeatSignatureOk = MBP_WorkerHeartbeatSignatureMatches(heartbeatSignature,
                                                                      assignmentSignature);
      bool heartbeatFresh = MBP_IsWorkerHeartbeatFreshForState(heartbeat, heartbeatState);
      if(heartbeatChartId > 0 &&
         heartbeatChartId != excludedChartId &&
         heartbeatSignatureOk &&
         heartbeatFresh &&
         MBP_IsAssignedWorkerChart(heartbeatChartId, symbol, coordinatorKey, assignmentSignature))
      {
         return heartbeatChartId;
      }

      // During template apply/reload, the heartbeat can be newer than the
      // assignment file. A fresh heartbeat from a live worker chart is a valid
      // ownership signal; the coordinator will restamp the assignment below.
      if(heartbeatChartId > 0 &&
         heartbeatChartId != excludedChartId &&
         heartbeatSignatureOk &&
         heartbeatFresh &&
         MBP_IsChartAlive(heartbeatChartId))
      {
         string heartbeatChartSymbol = ChartSymbol(heartbeatChartId);
         string expectedChartSymbol = MBP_IsSyntheticDataMode(MBP_EffectiveDataMode())
                                      ? ResolveSyntheticChartSymbolName(targetBase, MBP_EffectiveDataMode())
                                      : targetBase;
         if(expectedChartSymbol == "" ||
            StringCompare(heartbeatChartSymbol, expectedChartSymbol, false) == 0)
         {
            return heartbeatChartId;
         }
      }
   }

   long bestChartId = 0;
   int bestRank = -1;
   datetime bestAssignedAt = 0;

   long chartId = ChartFirst();
   while(chartId >= 0)
   {
      if(chartId != excludedChartId)
      {
         string assignedSymbol = "";
         string assignedSymbolsCsv = "";
         string assignedChartSymbol = "";
         string assignedCoordinatorKey = "";
         long assignedCoordinatorChartId = 0;
         string chartAssignedSignature = "";
         datetime assignedAt = 0;
         if(MBP_ReadWorkerAssignment(chartId,
                                     assignedSymbol,
                                     assignedSymbolsCsv,
                                     assignedChartSymbol,
                                     assignedCoordinatorKey,
                                     assignedCoordinatorChartId,
                                     chartAssignedSignature,
                                     assignedAt))
         {
            string assignedBase = GetBaseSymbol(assignedSymbol);
            if(assignedBase == "")
               assignedBase = assignedSymbol;

            bool coordinatorMatches = MBP_CoordinatorKeyMatchesRuntime(assignedCoordinatorKey, coordinatorKey);
            int rank = -1;
            if(coordinatorMatches && assignmentSignature != "" &&
               chartAssignedSignature != "" &&
               StringCompare(chartAssignedSignature, assignmentSignature, false) == 0)
            {
               rank = 2;
            }
            else if(coordinatorMatches &&
                    targetBase != "" &&
                    StringCompare(assignedBase, targetBase, false) == 0)
            {
               rank = 1;
            }

             if(rank >= 0)
             {
                bool betterCandidate = (rank > bestRank);
                if(rank == bestRank)
                {
                   if(bestChartId <= 0)
                      betterCandidate = true;
                   else if(assignedAt > 0 && (bestAssignedAt <= 0 || assignedAt < bestAssignedAt))
                      betterCandidate = true;
                }

                if(betterCandidate)
                {
                   bestRank = rank;
                   bestAssignedAt = assignedAt;
                   bestChartId = chartId;
                }
            }
         }
      }

      chartId = ChartNext(chartId);
   }

   return bestChartId;
}

int MBP_CloseDuplicateAssignedWorkerCharts(const string symbol,
                                           const string coordinatorKey,
                                           const string assignmentSignature,
                                           const long keepChartId,
                                           const long excludedChartId = 0)
{
   if(keepChartId <= 0 || assignmentSignature == "")
      return 0;

   int closed = 0;
   long chartId = ChartFirst();
   while(chartId >= 0)
   {
      long nextChartId = ChartNext(chartId);
      if(chartId != keepChartId && chartId != excludedChartId)
      {
         string assignedSymbol = "";
         string assignedSymbolsCsv = "";
         string assignedChartSymbol = "";
         string assignedCoordinatorKey = "";
         long assignedCoordinatorChartId = 0;
         string chartAssignedSignature = "";
         datetime assignedAt = 0;
         if(MBP_ReadWorkerAssignment(chartId,
                                     assignedSymbol,
                                     assignedSymbolsCsv,
                                     assignedChartSymbol,
                                     assignedCoordinatorKey,
                                     assignedCoordinatorChartId,
                                     chartAssignedSignature,
                                     assignedAt))
         {
            bool coordinatorMatches = MBP_CoordinatorKeyMatchesRuntime(assignedCoordinatorKey, coordinatorKey);
            bool sameAssignment = (chartAssignedSignature != "" &&
                                   assignmentSignature != "" &&
                                   StringCompare(chartAssignedSignature, assignmentSignature, false) == 0);
            if(coordinatorMatches && sameAssignment)
            {
               datetime heartbeat = 0;
               long heartbeatChartId = 0;
               string heartbeatSymbolsCsv = "";
               string heartbeatSignature = "";
               string heartbeatState = "";
               if(MBP_ReadWorkerHeartbeat(symbol,
                                          coordinatorKey,
                                          heartbeat,
                                          heartbeatChartId,
                                          heartbeatSymbolsCsv,
                                          heartbeatSignature,
                                          heartbeatState) &&
                  heartbeatChartId == chartId &&
                  MBP_IsWorkerHeartbeatFreshForState(heartbeat, heartbeatState))
               {
                  chartId = nextChartId;
                  continue;
               }

               if(MBP_IsHeartbeatOwnedByChart(symbol, coordinatorKey, assignmentSignature, chartId) &&
                  !MBP_IsHeartbeatOwnedByChart(symbol, coordinatorKey, assignmentSignature, keepChartId))
               {
                  string heartbeatFile = MBP_WorkerHeartbeatFile(symbol, coordinatorKey);
                  if(FileIsExist(heartbeatFile, FILE_COMMON))
                     FileDelete(heartbeatFile, FILE_COMMON);
               }

               ResetLastError();
               if(ChartClose(chartId))
               {
                  string assignmentFile = MBP_WorkerAssignmentFile(chartId);
                  if(FileIsExist(assignmentFile, FILE_COMMON))
                     FileDelete(assignmentFile, FILE_COMMON);
                  closed++;
                  if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiWarning(), " Closed duplicate worker chart for ", symbol,
                        " on chart ", chartId, "; keeping chart ", keepChartId, ".");
               }
               else
               {
                  int closeError = _LastError;
                  if(closeError == 4102)
                  {
                     string assignmentFile = MBP_WorkerAssignmentFile(chartId);
                     if(FileIsExist(assignmentFile, FILE_COMMON))
                        FileDelete(assignmentFile, FILE_COMMON);
                     closed++;
                     if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiWarning(), " Cleared stale duplicate worker assignment for ", symbol,
                           " on missing chart ", chartId, ".");
                  }
                  else
                  {
                     if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(EmojiWarning(), " Duplicate worker chart close failed for ", symbol,
                           " on chart ", chartId, " Error=", closeError);
                  }
               }
            }
         }
      }

      chartId = nextChartId;
   }

   return closed;
}

int MBP_CloseDuplicateWorkerChartsForChartSymbol(const string chartSymbol,
                                                 const string coordinatorKey,
                                                 const long keepChartId,
                                                 const long excludedChartId = 0)
{
   if(chartSymbol == "" || keepChartId <= 0)
      return 0;

   int closed = 0;
   long chartId = ChartFirst();
   while(chartId >= 0)
   {
      long nextChartId = ChartNext(chartId);
      if(chartId != keepChartId && chartId != excludedChartId &&
         StringCompare(ChartSymbol(chartId), chartSymbol, false) == 0)
      {
         string assignedSymbol = "";
         string assignedSymbolsCsv = "";
         string assignedChartSymbol = "";
         string assignedCoordinatorKey = "";
         long assignedCoordinatorChartId = 0;
         string chartAssignedSignature = "";
         datetime assignedAt = 0;
         bool hasAssignment = MBP_ReadWorkerAssignment(chartId,
                                                       assignedSymbol,
                                                       assignedSymbolsCsv,
                                                       assignedChartSymbol,
                                                       assignedCoordinatorKey,
                                                       assignedCoordinatorChartId,
                                                       chartAssignedSignature,
                                                       assignedAt);
         bool ours = false;
         if(hasAssignment)
         {
            ours = MBP_CoordinatorKeyMatchesRuntime(assignedCoordinatorKey, coordinatorKey);
            if(assignedChartSymbol != "" && StringCompare(assignedChartSymbol, chartSymbol, false) != 0)
               ours = false;
         }
         else
         {
            ours = MBP_HasWorkerLaunchMarker(chartId);
         }

         if(ours)
         {
            string heartbeatSymbol = assignedSymbol;
            if(heartbeatSymbol == "")
               heartbeatSymbol = GetBaseSymbol(chartSymbol);
            if(heartbeatSymbol == "")
               heartbeatSymbol = chartSymbol;

            datetime heartbeat = 0;
            long heartbeatChartId = 0;
            string heartbeatSymbolsCsv = "";
            string heartbeatSignature = "";
            string heartbeatState = "";
            if(MBP_ReadWorkerHeartbeat(heartbeatSymbol,
                                       coordinatorKey,
                                       heartbeat,
                                       heartbeatChartId,
                                       heartbeatSymbolsCsv,
                                       heartbeatSignature,
                                       heartbeatState) &&
               heartbeatChartId == chartId &&
               MBP_IsWorkerHeartbeatFreshForState(heartbeat, heartbeatState))
            {
               chartId = nextChartId;
               continue;
            }

            ResetLastError();
            if(ChartClose(chartId))
            {
               string assignmentFile = MBP_WorkerAssignmentFile(chartId);
               if(FileIsExist(assignmentFile, FILE_COMMON))
                  FileDelete(assignmentFile, FILE_COMMON);
               MBP_ClearWorkerLaunchMarker(chartId);
               closed++;
               if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiWarning(), " Closed duplicate worker chart for ", chartSymbol,
                     " on chart ", chartId, "; keeping chart ", keepChartId, ".");
            }
            else if(_LastError == 4102)
            {
               string assignmentFile = MBP_WorkerAssignmentFile(chartId);
               if(FileIsExist(assignmentFile, FILE_COMMON))
                  FileDelete(assignmentFile, FILE_COMMON);
               MBP_ClearWorkerLaunchMarker(chartId);
               closed++;
            }
            else
            {
               if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(EmojiWarning(), " Duplicate worker chart close failed for ", chartSymbol,
                     " on chart ", chartId, " Error=", _LastError);
            }
         }
      }

      chartId = nextChartId;
   }

   return closed;
}

bool MBP_IsAssignedWorkerChart(const long chartId,
                               const string symbol,
                               const string coordinatorKey,
                               const string assignmentSignature)
{
   if(!MBP_IsChartAlive(chartId))
      return false;

   string assignedSymbol = "";
   string assignedSymbolsCsv = "";
   string assignedChartSymbol = "";
   string assignedCoordinatorKey = "";
   long assignedCoordinatorChartId = 0;
   string chartAssignedSignature = "";
   datetime assignedAt = 0;
   if(!MBP_ReadWorkerAssignment(chartId,
                                assignedSymbol,
                                assignedSymbolsCsv,
                                assignedChartSymbol,
                                assignedCoordinatorKey,
                                assignedCoordinatorChartId,
                                chartAssignedSignature,
                                assignedAt))
   {
      return false;
   }

   bool coordinatorMatches = MBP_CoordinatorKeyMatchesRuntime(assignedCoordinatorKey, coordinatorKey);
   if(!coordinatorMatches)
      return false;

   if(assignmentSignature != "" &&
      chartAssignedSignature != "" &&
      StringCompare(chartAssignedSignature, assignmentSignature, false) == 0)
      return true;

   string assignedBase = GetBaseSymbol(assignedSymbol);
   if(assignedBase == "")
      assignedBase = assignedSymbol;

   string targetBase = GetBaseSymbol(symbol);
   if(targetBase == "")
      targetBase = symbol;

   return (targetBase != "" && StringCompare(assignedBase, targetBase, false) == 0);
}

int MBP_GetParallelWorkerCap()
{
   return MathMax(1, InpParallelMaxWorkerCharts);
}

int MBP_ParseSymbolCsv(const string csv, string &outSymbols[])
{
   ArrayResize(outSymbols, 0);

   if(csv == "")
      return 0;

   string parts[];
   int count = StringSplit(csv, ',', parts);
   for(int i = 0; i < count; i++)
   {
      string symbol = TrimString(parts[i]);
      if(symbol == "")
         continue;

      bool duplicate = false;
      for(int j = 0; j < ArraySize(outSymbols); j++)
      {
         if(StringCompare(outSymbols[j], symbol, false) == 0)
         {
            duplicate = true;
            break;
         }
      }
      if(duplicate)
         continue;

      int next = ArraySize(outSymbols);
      ArrayResize(outSymbols, next + 1);
      outSymbols[next] = symbol;
   }

   return ArraySize(outSymbols);
}

string MBP_JoinSymbolSlice(string &symbols[], const int startIndex, const int endIndex)
{
   string csv = "";
   int total = ArraySize(symbols);
   if(total <= 0)
      return csv;

   int safeStart = MathMax(0, startIndex);
   int safeEnd = MathMin(total - 1, endIndex);
   for(int i = safeStart; i <= safeEnd; i++)
   {
      string symbol = TrimString(symbols[i]);
      if(symbol == "")
         continue;

      if(csv != "")
         csv += ",";
      csv += symbol;
   }

   return csv;
}

string MBP_GetAssignedWorkerHeartbeatSymbol()
{
   string workerSymbol = G_RuntimeAssignedWorkerSymbol;
   if(workerSymbol == "" && ArraySize(G_RuntimeAssignedSymbols) > 0)
      workerSymbol = G_RuntimeAssignedSymbols[0];
   if(workerSymbol == "")
      workerSymbol = GetBaseSymbol(G_RuntimeAssignedChartSymbol);
   if(workerSymbol == "")
      workerSymbol = GetBaseSymbol(_Symbol);
   if(workerSymbol == "")
      workerSymbol = _Symbol;

   return workerSymbol;
}

string MBP_GetAssignedWorkerSymbolsCsv()
{
   if(G_RuntimeAssignedSymbolsCsv != "")
      return G_RuntimeAssignedSymbolsCsv;

   string workerSymbol = MBP_GetAssignedWorkerHeartbeatSymbol();
   return workerSymbol;
}

bool MBP_RuntimeWorkerOwnsSymbol(const string symbol)
{
   string target = GetBaseSymbol(symbol);
   if(target == "")
      target = symbol;
   if(target == "")
      return false;

   if(ArraySize(G_RuntimeAssignedSymbols) > 0)
   {
      for(int i = 0; i < ArraySize(G_RuntimeAssignedSymbols); i++)
      {
         string owned = GetBaseSymbol(G_RuntimeAssignedSymbols[i]);
         if(owned == "")
            owned = G_RuntimeAssignedSymbols[i];
         if(StringCompare(owned, target, false) == 0)
            return true;
      }
      return false;
   }

   string workerSymbol = MBP_GetAssignedWorkerHeartbeatSymbol();
   return (StringCompare(workerSymbol, target, false) == 0);
}

string MBP_BuildWorkerAssignmentSignature(const string primarySymbol,
                                         const string chartSymbol,
                                         const string symbolsCsv)
{
   return MBP_SanitizeRuntimeToken(primarySymbol) + "|" +
          MBP_SanitizeRuntimeToken(chartSymbol) + "|" +
          MBP_SanitizeRuntimeToken(symbolsCsv) + "|" +
          IntegerToString((int)MBP_EffectiveDataMode());
}

int MBP_FindWorkerSlot(const string symbol)
{
   string target = GetBaseSymbol(symbol);
   if(target == "")
      target = symbol;

   for(int i = 0; i < ArraySize(G_WorkerSlots); i++)
   {
      if(StringCompare(G_WorkerSlots[i].symbol, target, false) == 0)
         return i;
   }

   return -1;
}

void MBP_EnsureWorkerSlots()
{
   string requestedSymbols[];
   ArrayResize(requestedSymbols, 0);

   if(ArraySize(TradingSymbols) <= 0)
   {
      ArrayResize(G_WorkerSlots, 0);
      return;
   }

   for(int i = 0; i < ArraySize(TradingSymbols); i++)
   {
      string baseSymbol = GetBaseSymbol(TradingSymbols[i]);
      if(baseSymbol == "")
         baseSymbol = TradingSymbols[i];
      if(baseSymbol == "")
         continue;

      bool duplicate = false;
      for(int j = 0; j < ArraySize(requestedSymbols); j++)
      {
         if(StringCompare(requestedSymbols[j], baseSymbol, false) == 0)
         {
            duplicate = true;
            break;
         }
      }
      if(duplicate)
         continue;

      int next = ArraySize(requestedSymbols);
      ArrayResize(requestedSymbols, next + 1);
      requestedSymbols[next] = baseSymbol;
   }

   int requestedCount = ArraySize(requestedSymbols);
   if(requestedCount <= 0)
   {
      ArrayResize(G_WorkerSlots, 0);
      return;
   }

   SMbpWorkerSlot previousSlots[];
   ArrayResize(previousSlots, ArraySize(G_WorkerSlots));
   for(int i = 0; i < ArraySize(G_WorkerSlots); i++)
      previousSlots[i] = G_WorkerSlots[i];

   int maxWorkerCharts = MBP_GetParallelWorkerCap();
   int slotCount = MathMin(requestedCount, maxWorkerCharts);
   ArrayResize(G_WorkerSlots, slotCount);

   for(int slotIndex = 0; slotIndex < slotCount; slotIndex++)
   {
      int startIndex = slotIndex;
      int endIndex = slotIndex;
      if(slotIndex == slotCount - 1)
         endIndex = requestedCount - 1;

      string primarySymbol = requestedSymbols[startIndex];
      string symbolsCsv = MBP_JoinSymbolSlice(requestedSymbols, startIndex, endIndex);
      ENUM_MBP_DATA_MODE effectiveMode = MBP_EffectiveDataMode();
      string chartSymbol = MBP_IsSyntheticDataMode(effectiveMode)
                           ? ResolveSyntheticChartSymbolName(primarySymbol, effectiveMode)
                           : primarySymbol;
      string signature = MBP_BuildWorkerAssignmentSignature(primarySymbol, chartSymbol, symbolsCsv);

      int previousIndex = -1;
      for(int j = 0; j < ArraySize(previousSlots); j++)
      {
         if(previousSlots[j].assignmentSignature == signature)
         {
            previousIndex = j;
            break;
         }
      }
      if(previousIndex < 0)
      {
         for(int j = 0; j < ArraySize(previousSlots); j++)
         {
            if(StringCompare(previousSlots[j].symbol, primarySymbol, false) == 0)
            {
               previousIndex = j;
               break;
            }
         }
      }

      G_WorkerSlots[slotIndex].symbol = primarySymbol;
      G_WorkerSlots[slotIndex].symbolsCsv = symbolsCsv;
      G_WorkerSlots[slotIndex].chartSymbol = chartSymbol;
      G_WorkerSlots[slotIndex].assignmentSignature = signature;
      G_WorkerSlots[slotIndex].assignedCount = (endIndex - startIndex + 1);

      if(previousIndex >= 0)
      {
         G_WorkerSlots[slotIndex].chartId = previousSlots[previousIndex].chartId;
         G_WorkerSlots[slotIndex].lastLaunchAttemptMs = previousSlots[previousIndex].lastLaunchAttemptMs;
         G_WorkerSlots[slotIndex].lastHeartbeat = previousSlots[previousIndex].lastHeartbeat;
         G_WorkerSlots[slotIndex].lastLoggedChartId = previousSlots[previousIndex].lastLoggedChartId;
         G_WorkerSlots[slotIndex].lastLoggedHeartbeatState = previousSlots[previousIndex].lastLoggedHeartbeatState;
      }
      else
      {
         G_WorkerSlots[slotIndex].chartId = 0;
         G_WorkerSlots[slotIndex].lastLaunchAttemptMs = 0;
         G_WorkerSlots[slotIndex].lastHeartbeat = 0;
         G_WorkerSlots[slotIndex].lastLoggedChartId = 0;
         G_WorkerSlots[slotIndex].lastLoggedHeartbeatState = "";
      }
   }
}

bool MBP_WriteWorkerAssignment(const long chartId,
                              const string symbol,
                              const string symbolsCsv,
                              const string chartSymbol,
                              const string coordinatorKey,
                              const string assignmentSignature,
                              const int workerIndex = 0)
{
   // Note: an earlier "atomic rename" experiment broke worker boot — MT5's FileMove
   // can fail silently when a reader holds the destination open (no FILE_SHARE_DELETE).
   // Direct overwrite with shared-read is the safe path; partial-read race is mitigated
   // by the launch marker fallback in ResolveRuntimeRoleForCurrentChart.
   int handle = FileOpen(MBP_WorkerAssignmentFile(chartId), FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(handle == INVALID_HANDLE)
      return false;

   FileWriteString(handle, "symbol=" + symbol + "\r\n");
   FileWriteString(handle, "symbols=" + symbolsCsv + "\r\n");
   FileWriteString(handle, "chart_symbol=" + chartSymbol + "\r\n");
   FileWriteString(handle, "signature=" + assignmentSignature + "\r\n");
   FileWriteString(handle, StringFormat("chart_id=%I64d\r\n", chartId));
   FileWriteString(handle, StringFormat("coordinator_chart=%I64d\r\n", ChartID()));
   FileWriteString(handle, "coordinator_key=" + coordinatorKey + "\r\n");
   FileWriteString(handle, "assigned_at=" + IntegerToString((int)MBP_RuntimeServerNow()) + "\r\n");
   FileWriteString(handle, "worker_index=" + IntegerToString(workerIndex) + "\r\n");
   FileClose(handle);
   return true;
}

// Lightweight helper to read just the worker index from the assignment file.
// Returns -1 if not assigned or the index is missing/invalid.
int MBP_ReadWorkerIndexFromAssignment(const long chartId)
{
   string payload = MBP_ReadTextFileCommon(MBP_WorkerAssignmentFile(chartId));
   if(payload == "")
      return -1;
   string indexValue = MBP_ReadKeyValue(payload, "worker_index");
   if(indexValue == "")
      return -1;
   int parsed = (int)StringToInteger(indexValue);
   if(parsed < 0 || parsed >= MBP_WORKER_MAGIC_MAX_OFFSETS)
      return -1;
   return parsed;
}

bool MBP_ReadWorkerAssignment(const long chartId,
                              string &outSymbol,
                              string &outSymbolsCsv,
                              string &outChartSymbol,
                              string &outCoordinatorKey,
                              long &outCoordinatorChartId,
                              string &outAssignmentSignature,
                              datetime &outAssignedAt)
{
   outSymbol = "";
   outSymbolsCsv = "";
   outChartSymbol = "";
   outCoordinatorKey = "";
   outCoordinatorChartId = 0;
   outAssignmentSignature = "";
   outAssignedAt = 0;
   string payload = MBP_ReadTextFileCommon(MBP_WorkerAssignmentFile(chartId));
   if(payload == "")
      return false;

   outSymbol = MBP_ReadKeyValue(payload, "symbol");
   outSymbolsCsv = MBP_ReadKeyValue(payload, "symbols");
   if(outSymbolsCsv == "")
      outSymbolsCsv = outSymbol;
   outChartSymbol = MBP_ReadKeyValue(payload, "chart_symbol");
   outAssignmentSignature = MBP_ReadKeyValue(payload, "signature");
   outCoordinatorKey = MBP_ReadKeyValue(payload, "coordinator_key");
   string coordinatorChartValue = MBP_ReadKeyValue(payload, "coordinator_chart");
   if(coordinatorChartValue != "")
      outCoordinatorChartId = (long)StringToInteger(coordinatorChartValue);
   string assignedAtValue = MBP_ReadKeyValue(payload, "assigned_at");
   if(assignedAtValue != "")
      outAssignedAt = (datetime)StringToInteger(assignedAtValue);

   if(outAssignmentSignature == "")
      outAssignmentSignature = MBP_BuildWorkerAssignmentSignature(outSymbol, outChartSymbol, outSymbolsCsv);

   return (outSymbol != "");
}

bool MBP_ReadWorkerHeartbeat(const string symbol,
                             const string coordinatorKey,
                             datetime &outHeartbeat,
                             long &outChartId,
                             string &outSymbolsCsv,
                             string &outAssignmentSignature,
                             string &outState)
{
   outHeartbeat = 0;
   outChartId = 0;
   outSymbolsCsv = "";
   outAssignmentSignature = "";
   outState = "";

   if(InpV3_EnableSQLiteBridge && V3_RuntimeEnabled(InpV3_EnableSQLiteBridge, InpV3_SQLitePath))
   {
      datetime sqliteHeartbeat = 0;
      long sqliteChartId = 0;
      string sqliteSymbolsCsv = "";
      string sqliteAssignmentSignature = "";
      string sqliteState = "";
      if(V3_ReadWorkerStatus(InpV3_SQLitePath,
                             coordinatorKey,
                             symbol,
                             sqliteHeartbeat,
                             sqliteChartId,
                             sqliteSymbolsCsv,
                             sqliteAssignmentSignature,
                             sqliteState))
      {
         outHeartbeat = sqliteHeartbeat;
         outChartId = sqliteChartId;
         outSymbolsCsv = sqliteSymbolsCsv;
         outAssignmentSignature = sqliteAssignmentSignature;
         outState = sqliteState;
         return true;
      }
   }

   datetime fileHeartbeat = 0;
   long fileChartId = 0;
   string fileSymbolsCsv = "";
   string fileAssignmentSignature = "";
   string fileState = "";
   string payload = MBP_ReadTextFileCommon(MBP_WorkerHeartbeatFile(symbol, coordinatorKey));
   if(payload != "")
   {
      string heartbeatValue = MBP_ReadKeyValue(payload, "heartbeat");
      string chartIdValue = MBP_ReadKeyValue(payload, "chart_id");
      if(heartbeatValue != "" && chartIdValue != "")
      {
         fileHeartbeat = (datetime)StringToInteger(heartbeatValue);
         fileChartId = (long)StringToInteger(chartIdValue);
         fileSymbolsCsv = MBP_ReadKeyValue(payload, "symbols");
         fileAssignmentSignature = MBP_ReadKeyValue(payload, "signature");
         fileState = MBP_ReadKeyValue(payload, "state");
      }
   }

   string globalBase = MBP_WorkerHeartbeatGlobalBase(symbol, coordinatorKey);
   datetime globalHeartbeat = 0;
   long globalChartId = 0;
   string globalState = "";
   string globalAssignmentSignature = "";
   if(GlobalVariableCheck(globalBase + "_ts") && GlobalVariableCheck(globalBase + "_chart"))
   {
      globalHeartbeat = (datetime)(long)GlobalVariableGet(globalBase + "_ts");
      string chartHighName = globalBase + "_chart_hi";
      string chartLowName = globalBase + "_chart_lo";
      if(GlobalVariableCheck(chartHighName) && GlobalVariableCheck(chartLowName))
      {
         long high = (long)GlobalVariableGet(chartHighName);
         long low = (long)GlobalVariableGet(chartLowName);
         globalChartId = (high * 1000000) + low;
      }
      else
      {
         globalChartId = (long)GlobalVariableGet(globalBase + "_chart");
      }
      int stateCode = GlobalVariableCheck(globalBase + "_state") ? (int)GlobalVariableGet(globalBase + "_state") : 0;
      globalState = MBP_WorkerHeartbeatStateFromCode(stateCode);
      if(GlobalVariableCheck(globalBase + "_sig"))
         globalAssignmentSignature = "hash:" + IntegerToString((int)GlobalVariableGet(globalBase + "_sig"));
   }

   bool sameHeartbeatOwner = (fileChartId > 0 && globalChartId > 0 && fileChartId == globalChartId);
   bool fileHasComparableState = (fileHeartbeat > 0 && fileState != "" && sameHeartbeatOwner);
   bool useGlobal = (globalHeartbeat > 0 && globalChartId > 0 &&
                     (fileHeartbeat <= 0 || globalHeartbeat > fileHeartbeat ||
                      (globalHeartbeat == fileHeartbeat && !fileHasComparableState)));
   if(useGlobal)
   {
      outHeartbeat = globalHeartbeat;
      outChartId = globalChartId;
      // Global variables are the durable timestamp source, but the heartbeat
      // file carries the full assignment metadata. Preserve that metadata when
      // both records belong to the same chart instead of returning a partial
      // global record that later fails signature/state validation.
      if(fileAssignmentSignature != "" && fileChartId == globalChartId)
         outAssignmentSignature = fileAssignmentSignature;
      else
         outAssignmentSignature = globalAssignmentSignature;
      if(fileSymbolsCsv != "" && fileChartId == globalChartId)
         outSymbolsCsv = fileSymbolsCsv;
      else
         outSymbolsCsv = "";
      if(fileState != "" && fileChartId == globalChartId)
         outState = fileState;
      else
         outState = globalState;
      return true;
   }

   outHeartbeat = fileHeartbeat;
   outChartId = fileChartId;
   outSymbolsCsv = fileSymbolsCsv;
   outAssignmentSignature = fileAssignmentSignature;
   outState = fileState;
   return (outHeartbeat > 0 && outChartId > 0);
}

bool MBP_IsHeartbeatOwnedByChart(const string symbol,
                                 const string coordinatorKey,
                                 const string assignmentSignature,
                                 const long chartId)
{
   if(chartId <= 0)
      return false;

   datetime heartbeat = 0;
   long heartbeatChartId = 0;
   string heartbeatSymbolsCsv = "";
   string heartbeatSignature = "";
   string heartbeatState = "";
   if(!MBP_ReadWorkerHeartbeat(symbol,
                               coordinatorKey,
                               heartbeat,
                               heartbeatChartId,
                               heartbeatSymbolsCsv,
                               heartbeatSignature,
                               heartbeatState))
   {
      return false;
   }

   if(heartbeatChartId > 0 && heartbeatChartId != chartId)
      return false;

   if(!MBP_WorkerHeartbeatSignatureMatches(heartbeatSignature, assignmentSignature))
   {
      return false;
   }

   return true;
}

bool MBP_IsWorkerAssignmentInLaunchGrace(const datetime assignedAt,
                                         const ulong launchAttemptMs)
{
   datetime nowServer = MBP_RuntimeServerNow();
   if(assignedAt > 0 && nowServer > 0 && nowServer >= assignedAt &&
      (nowServer - assignedAt) <= MBP_WORKER_LAUNCH_GRACE_SEC)
   {
      return true;
   }

   ulong nowMs = GetTickCount();
   return (launchAttemptMs > 0 &&
           nowMs >= launchAttemptMs &&
           (nowMs - launchAttemptMs) <= MBP_WORKER_TEMPLATE_RETRY_MS);
}

void MBP_RefreshWorkerAssignment()
{
   if(!IsParallelWorkerMode())
      return;

   string assignedSymbol = "";
   string assignedSymbolsCsv = "";
   string assignedChartSymbol = "";
   string assignedCoordinatorKey = "";
   long assignedCoordinatorChartId = 0;
   string assignedSignature = "";
   datetime assignedAt = 0;
   bool hasAssignment = MBP_ReadWorkerAssignment(ChartID(),
                                                 assignedSymbol,
                                                 assignedSymbolsCsv,
                                                 assignedChartSymbol,
                                                 assignedCoordinatorKey,
                                                 assignedCoordinatorChartId,
                                                 assignedSignature,
                                                 assignedAt);

   if(!hasAssignment)
      return;

   if(!MBP_CoordinatorKeyMatchesRuntime(assignedCoordinatorKey, G_RuntimeCoordinatorKey))
      return;

   bool changed = false;
   if(assignedSymbol != "" && StringCompare(G_RuntimeAssignedWorkerSymbol, assignedSymbol, false) != 0)
   {
      G_RuntimeAssignedWorkerSymbol = assignedSymbol;
      changed = true;
   }
   if(assignedSymbolsCsv != "" && StringCompare(G_RuntimeAssignedSymbolsCsv, assignedSymbolsCsv, false) != 0)
   {
      G_RuntimeAssignedSymbolsCsv = assignedSymbolsCsv;
      MBP_ParseSymbolCsv(G_RuntimeAssignedSymbolsCsv, G_RuntimeAssignedSymbols);
      changed = true;
   }
   if(assignedChartSymbol != "" && StringCompare(G_RuntimeAssignedChartSymbol, assignedChartSymbol, false) != 0)
   {
      G_RuntimeAssignedChartSymbol = assignedChartSymbol;
      changed = true;
   }
   if(assignedSignature != "" && StringCompare(G_RuntimeAssignedWorkerSignature, assignedSignature, false) != 0)
      G_RuntimeAssignedWorkerSignature = assignedSignature;

   int refreshedIndex = MBP_ReadWorkerIndexFromAssignment(ChartID());
   if(refreshedIndex >= 0 && refreshedIndex != G_RuntimeWorkerIndex)
   {
      bool wasInitialised = (G_RuntimeWorkerIndex >= 0);
      G_RuntimeWorkerIndex = refreshedIndex;

      // CRITICAL: First learning (boot via launch marker → file becomes readable later)
      // is NOT a reassignment. Updating the magic in place is enough; a full reapply
      // here would loop forever because OnInit ran before the file was visible.
      if(!wasInitialised)
      {
         if(refreshedIndex < MBP_WORKER_MAGIC_MAX_OFFSETS)
         {
            G_EffectiveMagicNumber = (long)MagicNumber + (long)refreshedIndex * MBP_WORKER_MAGIC_STRIDE;
            Trade.SetExpertMagicNumber(G_EffectiveMagicNumber);
            if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiBrain(), " Worker ", refreshedIndex,
                  " learned its slot — magic updated in-place to ", G_EffectiveMagicNumber, ".");
         }
      }
      else
      {
         changed = true;
      }
   }

   if(changed)
   {
      if(G_InitInProgress || !G_WorkerBootstrapCompleted)
         return;

      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiBrain(), " Worker assignment refreshed in-place: ",
            G_RuntimeAssignedSymbolsCsv, " on ", G_RuntimeAssignedChartSymbol, ".");

      if(ShowDashboard)
      {
         UpdateDashboard(0);
      }
   }
}

void MBP_LockWorkerChartSymbol()
{
   if(!IsParallelWorkerMode())
      return;

   string targetSymbol = G_RuntimeAssignedChartSymbol;
   if(targetSymbol == "")
      return;

   string currentSymbol = ChartSymbol(0);
   if(StringCompare(currentSymbol, targetSymbol, false) == 0)
      return;

   static ulong lastLockAttemptMs = 0;
   ulong nowMs = GetTickCount();
   if(lastLockAttemptMs > 0 && (nowMs - lastLockAttemptMs) < 5000)
      return;
   lastLockAttemptMs = nowMs;

   ResetLastError();
   if(!ChartSetSymbolPeriod(0, targetSymbol, (ENUM_TIMEFRAMES)ChartPeriod(0)))
      if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(EmojiWarning(), " Worker chart symbol lock failed. Expected ", targetSymbol,
            ", current ", currentSymbol, " Error=", _LastError);
}

ENUM_MBP_RUNTIME_ROLE ResolveRuntimeRoleForCurrentChart()
{
   G_RuntimeCoordinatorKey = "";
   G_RuntimeAssignedWorkerSymbol = "";
   G_RuntimeAssignedChartSymbol = "";
   G_RuntimeAssignedSymbolsCsv = "";
   G_RuntimeAssignedWorkerSignature = "";
   G_RuntimeWorkerIndex = -1;
   ArrayResize(G_RuntimeAssignedSymbols, 0);

   string assignedSymbol = "";
   string assignedSymbolsCsv = "";
   string assignedChartSymbol = "";
   string assignedCoordinatorKey = "";
   long assignedCoordinatorChartId = 0;
   string assignedSignature = "";
   datetime assignedAt = 0;
   if(MBP_ReadWorkerAssignment(ChartID(),
                               assignedSymbol,
                               assignedSymbolsCsv,
                               assignedChartSymbol,
                               assignedCoordinatorKey,
                               assignedCoordinatorChartId,
                               assignedSignature,
                               assignedAt))
   {
      string currentChartSymbol = ChartSymbol(0);
      G_RuntimeAssignedWorkerSymbol = assignedSymbol;
      G_RuntimeAssignedSymbolsCsv = assignedSymbolsCsv;
      G_RuntimeAssignedChartSymbol = assignedChartSymbol;
      G_RuntimeAssignedWorkerSignature = assignedSignature;
      MBP_ParseSymbolCsv(G_RuntimeAssignedSymbolsCsv, G_RuntimeAssignedSymbols);
      if(G_RuntimeAssignedWorkerSymbol == "" && ArraySize(G_RuntimeAssignedSymbols) > 0)
         G_RuntimeAssignedWorkerSymbol = G_RuntimeAssignedSymbols[0];
      if(G_RuntimeAssignedChartSymbol == "")
         G_RuntimeAssignedChartSymbol = currentChartSymbol;
      if(ArraySize(G_RuntimeAssignedSymbols) <= 0 && G_RuntimeAssignedWorkerSymbol != "")
      {
         ArrayResize(G_RuntimeAssignedSymbols, 1);
         G_RuntimeAssignedSymbols[0] = G_RuntimeAssignedWorkerSymbol;
      }
      if(assignedCoordinatorKey == "" || assignedCoordinatorChartId > 0)
         assignedCoordinatorKey = MBP_DefaultCoordinatorKey();
      G_RuntimeCoordinatorKey = assignedCoordinatorKey;
      G_RuntimeWorkerIndex    = MBP_ReadWorkerIndexFromAssignment(ChartID());
      return MBP_RUNTIME_WORKER;
   }

   double coordinatorChartId = 0.0;
   if(MBP_ConsumeWorkerLaunchMarker(ChartID(), coordinatorChartId))
   {
      string currentChartSymbol = ChartSymbol(0);
      string workerSymbol = GetBaseSymbol(currentChartSymbol);
      if(workerSymbol == "")
         workerSymbol = currentChartSymbol;

      G_RuntimeCoordinatorKey = MBP_DefaultCoordinatorKey();
      G_RuntimeAssignedWorkerSymbol = workerSymbol;
      G_RuntimeAssignedChartSymbol = currentChartSymbol;
      G_RuntimeAssignedSymbolsCsv = workerSymbol;
      G_RuntimeAssignedWorkerSignature = MBP_BuildWorkerAssignmentSignature(workerSymbol,
                                                                            currentChartSymbol,
                                                                            workerSymbol);
      if(workerSymbol != "")
      {
         ArrayResize(G_RuntimeAssignedSymbols, 1);
         G_RuntimeAssignedSymbols[0] = workerSymbol;
      }

      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("[WorkerLaunchMarker] Assumed WORKER role via coordinator launch marker for chart ", ChartID());
      return MBP_RUNTIME_WORKER;
   }

   if(!InpEnableCoordinator || BotSystemMode == BOT_MODE_SLAVE)
   {
      G_RuntimeCoordinatorKey = MBP_DefaultCoordinatorKey();
      return MBP_RUNTIME_LEGACY;
   }

   if(InpEnableCoordinator && BotSystemMode != BOT_MODE_SLAVE)
   {
      G_RuntimeCoordinatorKey = MBP_DefaultCoordinatorKey();

      // Singleton guard: refuse coordinator role if a DIFFERENT chart already owns
      // this key and its heartbeat is fresh (< 5 seconds old). The owner GV stores
      // the chart ID so a chart re-initialising (REASON_PARAMETERS, CHARTCHANGE,
      // RECOMPILE, TEMPLATE) can re-claim its own role instead of being blocked
      // by its own pre-deinit heartbeat.
      string coordAliveGV = MBP_CoordAliveGVName(G_RuntimeCoordinatorKey);
      long myChartId = ChartID();

      // CRITICAL: MT5 chart IDs (e.g. 134221287195433199) exceed 2^53 — they cannot
      // round-trip exactly through a double. To compare against the GV-stored value
      // we must apply the same lossy round-trip to both sides; otherwise the same
      // chart's pre-deinit GV blocks its own re-claim because the stored long has
      // been rounded to the nearest multiple of 16 or 32.
      if(GlobalVariableCheck(coordAliveGV))
      {
         ulong lastBeat = (ulong)GlobalVariableGet(coordAliveGV);
         ulong nowMs    = GetTickCount64();
         if(lastBeat > 0 && nowMs >= lastBeat && (nowMs - lastBeat) < 5000)
         {
            long ownerChartId = MBP_ReadCoordinatorOwnerChartId(G_RuntimeCoordinatorKey);
            if(ownerChartId != 0 && ownerChartId != myChartId)
            {
               if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiWarning(), " Another coordinator is already running for key '",
                     G_RuntimeCoordinatorKey, "' on chart ", ownerChartId,
                     " (mine=", myChartId, ", heartbeat ", (nowMs - lastBeat),
                     "ms ago). This chart will run as LEGACY (no worker spawning).");
               return MBP_RUNTIME_LEGACY;
            }
            // Same-chart re-init: fall through and re-claim.
         }
      }

      // Stamp our claim — both timestamp and owner — so siblings see us and step down.
      MBP_WriteCoordinatorAliveHeartbeat(G_RuntimeCoordinatorKey, myChartId);
      return MBP_RUNTIME_COORDINATOR;
   }

   G_RuntimeCoordinatorKey = MBP_DefaultCoordinatorKey();
   return MBP_RUNTIME_LEGACY;
}

bool IsParallelLegacyMode()
{
   return (G_RuntimeRole == MBP_RUNTIME_LEGACY);
}

bool IsParallelCoordinatorMode()
{
   return (G_RuntimeRole == MBP_RUNTIME_COORDINATOR);
}

bool IsParallelWorkerMode()
{
   return (G_RuntimeRole == MBP_RUNTIME_WORKER);
}

string RuntimeRoleToText(const ENUM_MBP_RUNTIME_ROLE role)
{
   if(role == MBP_RUNTIME_LEGACY) return "DIRECT";
   if(role == MBP_RUNTIME_COORDINATOR) return "COORDINATOR";
   if(role == MBP_RUNTIME_WORKER) return "WORKER";
   return "UNKNOWN";
}

bool ShadowMaster_ShouldOwnRuntime()
{
   return (IsParallelCoordinatorMode() || IsParallelLegacyMode());
}

bool ShadowMaster_IsAnalysisSuffix(const string suffix)
{
   string s = suffix;
   StringToUpper(s);
   return (s == "R" ||
           s == "ATR" ||
           s == "RENKO" ||
           s == "MEDIANRENKO" ||
           s == "TURBORENKO" ||
           s == "HEIKENRENKO" ||
           s == "HA" ||
           s == "CUSTOM");
}

string ShadowMaster_NormalizeOptimizerSymbol(string symbolName)
{
   StringTrimLeft(symbolName);
   StringTrimRight(symbolName);
   if(symbolName == "")
      return "";

   string baseSymbol = GetBaseSymbol(symbolName);
   if(baseSymbol != "" && StringCompare(baseSymbol, symbolName, false) != 0)
      return baseSymbol;

   string parts[];
   if(StringSplit(symbolName, '_', parts) > 1 && ShadowMaster_IsAnalysisSuffix(parts[1]))
      return parts[0];

   return symbolName;
}

string ShadowMaster_RuntimeSymbolForIndex(const int index)
{
   string symbolName = "";
   if(index >= 0 && index < ArraySize(SymbolData))
   {
      symbolName = SymbolData[index].symbol;
      if(SymbolData[index].BaseSymbol != "")
         symbolName = SymbolData[index].BaseSymbol;
   }

   if(symbolName == "" && index >= 0 && index < ArraySize(TradingSymbols))
      symbolName = TradingSymbols[index];

   return ShadowMaster_NormalizeOptimizerSymbol(symbolName);
}

bool ShadowMaster_SymbolSeen(const string &seen[], const string symbolName)
{
   for(int i = 0; i < ArraySize(seen); i++)
   {
      if(StringCompare(seen[i], symbolName, false) == 0)
         return true;
   }
   return false;
}

int ShadowMaster_CountRuntimeSymbols()
{
   string seen[];

   for(int i = 0; i < ArraySize(SymbolData); i++)
   {
      if(!SymbolData[i].active)
         continue;

      string symbolName = ShadowMaster_RuntimeSymbolForIndex(i);
      if(symbolName == "" || ShadowMaster_SymbolSeen(seen, symbolName))
         continue;

      int next = ArraySize(seen);
      ArrayResize(seen, next + 1);
      seen[next] = symbolName;
   }

   return ArraySize(seen);
}

string ShadowMaster_BuildRuntimeSymbolsJson()
{
   string parts = "";
   string seen[];

   for(int i = 0; i < ArraySize(SymbolData); i++)
   {
      if(!SymbolData[i].active)
         continue;

      string symbolName = ShadowMaster_RuntimeSymbolForIndex(i);
      if(symbolName == "")
         continue;

      if(ShadowMaster_SymbolSeen(seen, symbolName))
         continue;

      int next = ArraySize(seen);
      ArrayResize(seen, next + 1);
      seen[next] = symbolName;

      if(parts != "")
         parts += ",";
      parts += "\"" + ShadowMaster_JsonEscape(symbolName) + "\"";
   }

   return "[" + parts + "]";
}

string ShadowMaster_BuildRuntimeSignature()
{
   return IntegerToString((int)ShadowMaster_IsAiRuntimeEnabled()) + "|" +
          IntegerToString(MathMax(1, InpShadowMasterCycleHours)) + "|" +
          InpShadowConfigName + "|" +
          ShadowMaster_BuildRuntimeSymbolsJson();
}

string ShadowMaster_BuildRuntimeConfigJson()
{
   string sqlitePath = InpV3_SQLitePath;
   if(StringFind(sqlitePath, ":") < 0 && StringSubstr(sqlitePath, 0, 2) != "\\\\")
      sqlitePath = MBP_PathJoin(MBP_GetProgramDirectoryPath(), sqlitePath);

   string mt5FilesPath = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files";
   string symbolsJson = ShadowMaster_BuildRuntimeSymbolsJson();
   int cycleHours = MathMax(1, InpShadowMasterCycleHours);
   int runtimeSymbolCount = MathMax(1, ShadowMaster_CountRuntimeSymbols());
   int maxWorkers = MathMax(1, MathMin(MBP_GetParallelWorkerCap(), runtimeSymbolCount));

   string json = "{\r\n";
   json += "  \"version\": \"1.1\",\r\n";
   json += "  \"runtime_contract\": {\r\n";
   json += "    \"name\": \"MultiBotPro.ShadowMaster\",\r\n";
   json += "    \"version\": \"1.0\",\r\n";
   json += "    \"transport\": \"file-json\",\r\n";
   json += "    \"command_file\": \"MultiBotPro2\\\\runtime_v3.json\",\r\n";
   json += "    \"status_file\": \"ShadowMasterRuntime.json\",\r\n";
   json += "    \"shadow_config_prefix\": \"" + ShadowMaster_JsonEscape(InpShadowConfigName) + "\"\r\n";
   json += "  },\r\n";
   json += "  \"sqlite_path\": \"" + ShadowMaster_JsonEscape(sqlitePath) + "\",\r\n";
   json += "  \"mt5_data_dir\": \"" + ShadowMaster_JsonEscape(mt5FilesPath) + "\",\r\n";
   json += "  \"network\": {\r\n";
   json += "    \"channel\": \"" + ShadowMaster_JsonEscape(InpHedgeChannel) + "\",\r\n";
   json += "    \"port\": 5555\r\n";
   json += "  },\r\n";
   json += "  \"ai_engine\": {\r\n";
   json += "    \"enabled\": " + (ShadowMaster_IsAiRuntimeEnabled() ? "true" : "false") + ",\r\n";
   json += "    \"mode\": \"SHADOW_MASTER\",\r\n";
   json += "    \"model_path\": \"models/v3_main.h5\"\r\n";
   json += "  },\r\n";
   json += "  \"shadowmaster\": {\r\n";
   json += "    \"enabled\": " + (ShadowMaster_IsAiRuntimeEnabled() ? "true" : "false") + ",\r\n";
   json += "    \"cycle_hours\": " + IntegerToString(cycleHours) + ",\r\n";
   json += "    \"lookback_days\": 7,\r\n";
   json += "    \"max_workers\": " + IntegerToString(maxWorkers) + ",\r\n";
   json += "    \"transaction_cost_bps\": 2.0,\r\n";
   json += "    \"shadow_config_prefix\": \"" + ShadowMaster_JsonEscape(InpShadowConfigName) + "\",\r\n";
   json += "    \"mt5_data_dir\": \"" + ShadowMaster_JsonEscape(mt5FilesPath) + "\",\r\n";
   json += "    \"symbols\": " + symbolsJson + "\r\n";
   json += "  },\r\n";
   json += "  \"logging\": {\r\n";
   json += "    \"level\": \"INFO\",\r\n";
   json += "    \"file\": \"logs/runtime.log\"\r\n";
   json += "  }\r\n";
   json += "}\r\n";

   return json;
}

bool ShadowMaster_WriteRuntimeConfig(const bool forceWrite = false)
{
   if(!ShadowMaster_IsAiRuntimeEnabled() || !ShadowMaster_ShouldOwnRuntime())
      return false;

   string signature = ShadowMaster_BuildRuntimeSignature();
   ulong nowMs = GetTickCount();
   if(!forceWrite && signature == G_LastShadowRuntimeSignature && (nowMs - G_LastShadowRuntimeWriteMs) < 900000)
      return true;

   string payloadText = ShadowMaster_BuildRuntimeConfigJson();
   ResetLastError();
   FolderCreate("MultiBotPro2", FILE_COMMON);
   int handle = FileOpen("MultiBotPro2\\runtime_v3.json", FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(handle == INVALID_HANDLE)
   {
      if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(EmojiWarning(), " Failed to write ShadowMaster runtime config: MultiBotPro2\\runtime_v3.json | error=", GetLastError());
      return false;
   }

   uint written = FileWriteString(handle, payloadText);
   FileClose(handle);
   if(written != (uint)StringLen(payloadText))
   {
      if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(EmojiWarning(), " ShadowMaster runtime config write incomplete: MultiBotPro2\\runtime_v3.json");
      return false;
   }

   G_LastShadowRuntimeSignature = signature;
   G_LastShadowRuntimeWriteMs = nowMs;
   return true;
}

bool ShadowMaster_ReadHeartbeat(datetime &outHeartbeat, string &outState)
{
   outHeartbeat = 0;
   outState = "";

   string json = "";
   string statusFile = ShadowMaster_RuntimeStatusFileName();
   if(FileIsExist(statusFile))
   {
      int handle = FileOpen(statusFile, FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE);
      if(handle != INVALID_HANDLE)
      {
         while(!FileIsEnding(handle))
            json += FileReadString(handle);
         FileClose(handle);
      }
   }

   if(json != "")
   {
      string heartbeatRaw = V3_ExtractJSONValue(json, "last_heartbeat");
      if(heartbeatRaw != "")
         outHeartbeat = (datetime)StringToInteger(heartbeatRaw);

      outState = V3_ExtractJSONValue(json, "state");
      if(outHeartbeat > 0)
         return true;
   }

   return false;
}

void ShadowMaster_PollConfigUpdates(const bool forcePoll)
{
   if(!ShadowMaster_IsAiRuntimeEnabled() || !ShadowMaster_ShouldOwnRuntime())
      return;

   ulong nowMs = GetTickCount64();
   if(!forcePoll && G_LastShadowConfigPollMs > 0 && (nowMs - G_LastShadowConfigPollMs) < 60000)
      return;
   G_LastShadowConfigPollMs = nowMs;

   int activeCount = 0;
   string seen[];
   for(int i = 0; i < ArraySize(SymbolData); i++)
   {
      if(!SymbolData[i].active)
         continue;

      string symbolName = ShadowMaster_RuntimeSymbolForIndex(i);
      if(symbolName == "" || ShadowMaster_SymbolSeen(seen, symbolName))
         continue;

      int next = ArraySize(seen);
      ArrayResize(seen, next + 1);
      seen[next] = symbolName;

      activeCount++;
      datetime previousUpdate = SymbolData[i].LastShadowUpdate;
      LoadShadowConfig(i);
      if(SymbolData[i].LastShadowUpdate > 0 && SymbolData[i].LastShadowUpdate >= previousUpdate)
      {
         for(int j = 0; j < ArraySize(SymbolData); j++)
         {
            if(j == i || !SymbolData[j].active)
               continue;

            string duplicateSymbol = ShadowMaster_RuntimeSymbolForIndex(j);
            if(StringCompare(duplicateSymbol, symbolName, false) == 0)
               CopyShadowTuningState(i, j, true);
         }
      }
   }

   if(MBP_LogTierEnabled(MBP_LOG_TIER_DEBUG)) Print(EmojiBrain(), " ShadowMaster config poll complete. Unique symbols checked=", activeCount, ".");
}

string MasterBuildWorkerTemplateSignature()
{
   return RuntimeRoleToText(G_RuntimeRole) + "|" +
          IntegerToString((int)MBP_EffectiveDataMode()) + "|" +
          IntegerToString((int)InpPrimaryComputeBackend) + "|" +
          ManualSymbols + "|" +
          IntegerToString((int)TradeAllMarketWatch) + "|" +
          IntegerToString((int)UseChartSymbol) + "|" +
          IntegerToString((int)InpEnableShadowMaster) + "|" +
          InpShadowConfigName + "|" +
          ShadowMaster_BuildRuntimeSignature();
}

bool MasterSaveWorkerTemplate(const bool forceSave = false)
{
   if(!IsParallelCoordinatorMode())
      return false;

   ulong nowMs = GetTickCount();
   const ulong templateSettleMs = 1500;
   string signature = MasterBuildWorkerTemplateSignature();
   if(!forceSave &&
      G_LastWorkerTemplateSignature != "" &&
      signature == G_LastWorkerTemplateSignature)
   {
      if(G_LastWorkerTemplateSaveMs > 0 &&
         (nowMs - G_LastWorkerTemplateSaveMs) < templateSettleMs)
      {
         return true;
      }
      return true;
   }

   string templateName = MBP_WorkerTemplateName();
   if(!ChartSaveTemplate(0, templateName))
   {
      if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(EmojiWarning(), " Failed to save worker template: ", templateName);
      return false;
   }

   G_LastWorkerTemplateSignature = signature;
   G_LastWorkerTemplateSaveMs = nowMs;
   if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiBrain(), " Worker EA template ready: ", templateName, ".");
   return true;
}

bool MasterApplyWorkerTemplateWithRecovery(const long chartId,
                                           const string baseSymbol,
                                           string &templateName)
{
   if(chartId <= 0 || chartId == ChartID())
      return false;

   if(templateName == "")
      templateName = MBP_WorkerTemplateName();

   // Allow newly opened chart a brief moment to settle in MT5 GUI queue
   for(int attempt = 0; attempt < 2; attempt++)
   {
      ResetLastError();
      if(ChartApplyTemplate(chartId, templateName))
         return true;
      if(attempt < 1)
         Sleep(25);
   }

   int firstErr = _LastError;
   if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(EmojiWarning(), " Failed to apply worker template to ", baseSymbol,
         " on chart ", chartId, " (error=", firstErr,
         "). Rebuilding template and retrying.");

   if(!MasterSaveWorkerTemplate(true))
   {
      if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(EmojiWarning(), " Worker template rebuild failed; cannot launch ", baseSymbol,
            " on chart ", chartId, ".");
      return false;
   }

   templateName = MBP_WorkerTemplateName();
   ResetLastError();
   if(ChartApplyTemplate(chartId, templateName))
   {
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiBrain(), " Worker template reapplied after rebuild for ", baseSymbol,
            " on chart ", chartId, ".");
      return true;
   }

   if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(EmojiWarning(), " Failed to apply rebuilt worker template to ", baseSymbol,
         " on chart ", chartId, " (error=", _LastError, ").");
   return false;
}

bool MasterPublishWorkerHeartbeatState(const string runtimeState, const bool forcePublish)
{
   if(!IsParallelWorkerMode())
      return false;

   ulong nowMs = GetTickCount();
   uint heartbeatIntervalMs = (uint)MathMax(250, InpParallelWorkerHeartbeatMs);
   if(!forcePublish &&
      G_WorkerBootstrapCompleted &&
      (nowMs - G_LastWorkerHeartbeatPublishMs) < heartbeatIntervalMs)
      return false;

   MBP_RefreshWorkerAssignment();
   MBP_LockWorkerChartSymbol();

   string workerSymbol = G_RuntimeAssignedWorkerSymbol;
   if(workerSymbol == "")
      workerSymbol = GetBaseSymbol(_Symbol);
   if(workerSymbol == "")
      workerSymbol = _Symbol;

   int linkedPositions = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(!IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
         continue;

      string posSymbol = GetBaseSymbol(PositionGetString(POSITION_SYMBOL));
      if(posSymbol == "")
         posSymbol = PositionGetString(POSITION_SYMBOL);
      if(StringCompare(posSymbol, workerSymbol, false) != 0)
         continue;

      linkedPositions++;
   }

   string assignedSymbolsCsv = MBP_GetAssignedWorkerSymbolsCsv();
   string assignedChartSymbol = G_RuntimeAssignedChartSymbol;
   if(assignedChartSymbol == "")
      assignedChartSymbol = ChartSymbol(0);
   string assignmentSignature = G_RuntimeAssignedWorkerSignature;
   if(assignmentSignature == "")
      assignmentSignature = MBP_BuildWorkerAssignmentSignature(workerSymbol, assignedChartSymbol, assignedSymbolsCsv);
   string effectiveState = runtimeState;
   if(effectiveState == "")
      effectiveState = (G_WorkerBootstrapCompleted ? "RUNNING" : "BOOTING");

   bool heartbeatPublished = MBP_WriteWorkerHeartbeatRecord(workerSymbol,
                                                            G_RuntimeCoordinatorKey,
                                                            assignedChartSymbol,
                                                            assignedSymbolsCsv,
                                                            assignmentSignature,
                                                            effectiveState,
                                                            linkedPositions,
                                                            MBP_RuntimeServerNow(),
                                                            ChartID());
   if(!heartbeatPublished)
      return false;

   G_LastWorkerHeartbeatPublishMs = nowMs;
   return true;
}

void MasterPublishWorkerHeartbeat()
{
   string overrideState = G_WorkerHeartbeatStateOverride;
   MasterPublishWorkerHeartbeatState(overrideState, false);
}

bool MasterRuntimeShouldHandleTradeSymbol(const string symbol)
{
   if(IsParallelCoordinatorMode())
      return false;

   if(!IsParallelWorkerMode())
      return true;

   return MBP_RuntimeWorkerOwnsSymbol(symbol);
}

bool MBP_WorkerTradingPausedForRenkoBuild()
{
   return (IsParallelWorkerMode() &&
           MBP_IsWorkerRenkoBuildState(G_WorkerHeartbeatStateOverride));
}

bool MBP_IsActiveWorkerSlotSignature(const string signature)
{
   if(signature == "")
      return false;

   for(int i = 0; i < ArraySize(G_WorkerSlots); i++)
   {
      if(StringCompare(G_WorkerSlots[i].assignmentSignature, signature, false) == 0)
         return true;
   }
   return false;
}

void MBP_CloseInactiveWorkerCharts(const string coordinatorKey)
{
   // Reimagined worker ownership rule:
   // the coordinator may clean up charts whose assignment signature is no
   // longer part of the desired worker set, but an active worker is never
   // closed here just because its heartbeat is stale. Synthetic builders can
   // legitimately go quiet while rebuilding or while MT5 is hydrating history.
   // Recovery/replacement is handled by MasterEnsureRuntimeWorkers after the
   // slot lease expires; this function is only a stale-signature janitor.
   long chartId = ChartFirst();
   while(chartId >= 0)
   {
      long nextChartId = ChartNext(chartId);
      if(chartId != ChartID())
      {
         string assignedSymbol = "";
         string assignedSymbolsCsv = "";
         string assignedChartSymbol = "";
         string assignedCoordinatorKey = "";
         long assignedCoordinatorChartId = 0;
         string assignedSignature = "";
         datetime assignedAt = 0;
         bool hasAssignment = MBP_ReadWorkerAssignment(chartId,
                                                       assignedSymbol,
                                                       assignedSymbolsCsv,
                                                       assignedChartSymbol,
                                                       assignedCoordinatorKey,
                                                       assignedCoordinatorChartId,
                                                       assignedSignature,
                                                       assignedAt);

         if(hasAssignment && MBP_CoordinatorKeyMatchesRuntime(assignedCoordinatorKey, coordinatorKey))
         {
            string closeReason = "";
            bool shouldClose = false;

            // Stale signature: coordinator's slot list no longer contains this assignment
            if(!MBP_IsActiveWorkerSlotSignature(assignedSignature))
            {
               shouldClose = true;
               closeReason = "stale signature " + assignedSignature;
            }

            if(shouldClose)
            {
               ResetLastError();
               if(ChartClose(chartId))
               {
                  string assignmentFile = MBP_WorkerAssignmentFile(chartId);
                  if(FileIsExist(assignmentFile, FILE_COMMON))
                     FileDelete(assignmentFile, FILE_COMMON);
                  string workerHbFile = MBP_WorkerHeartbeatFile(assignedSymbol, coordinatorKey);
                  if(FileIsExist(workerHbFile, FILE_COMMON))
                     FileDelete(workerHbFile, FILE_COMMON);
                  if(InpV3_EnableSQLiteBridge && V3_RuntimeEnabled(InpV3_EnableSQLiteBridge, InpV3_SQLitePath))
                     V3_DeleteWorkerStatus(InpV3_SQLitePath, coordinatorKey, assignedSymbol, chartId);
                  if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiWarning(), " Closed worker chart ", chartId,
                        " — reason: ", closeReason, ".");
               }
               else if(_LastError == 4102)
               {
                  string assignmentFile = MBP_WorkerAssignmentFile(chartId);
                  if(FileIsExist(assignmentFile, FILE_COMMON))
                     FileDelete(assignmentFile, FILE_COMMON);
                  string workerHbFile = MBP_WorkerHeartbeatFile(assignedSymbol, coordinatorKey);
                  if(FileIsExist(workerHbFile, FILE_COMMON))
                     FileDelete(workerHbFile, FILE_COMMON);
                  if(InpV3_EnableSQLiteBridge && V3_RuntimeEnabled(InpV3_EnableSQLiteBridge, InpV3_SQLitePath))
                     V3_DeleteWorkerStatus(InpV3_SQLitePath, coordinatorKey, assignedSymbol, chartId);
               }
            }
         }
      }
      chartId = nextChartId;
   }
}

void MasterEnsureRuntimeWorkers()
{
   if(!IsParallelCoordinatorMode())
      return;

   ulong nowMs = GetTickCount();
   uint ensureIntervalMs = MBP_WORKER_ENSURE_INTERVAL_MS;
   if((nowMs - G_LastWorkerEnsureMs) < ensureIntervalMs)
      return;

   G_LastWorkerEnsureMs = nowMs;
   MBP_EnsureWorkerSlots();
   if(ArraySize(G_WorkerSlots) <= 0)
      return;

   if(!MasterSaveWorkerTemplate(false))
      return;

   string templateName = MBP_WorkerTemplateName();
   ENUM_TIMEFRAMES targetPeriod = (ENUM_TIMEFRAMES)ChartPeriod(0);
   string coordinatorKey = MBP_GetActiveCoordinatorKey();
   MBP_CloseInactiveWorkerCharts(coordinatorKey);

   // After the close pass, invalidate any slot whose tracked chart is no longer
   // alive. This prevents the ensure loop below from "re-assigning" to a chart
   // that was just closed (it can remain MBP_IsChartAlive for a few seconds
   // while its EA is still deinitializing), which would block opening a fresh one.
   for(int j = 0; j < ArraySize(G_WorkerSlots); j++)
   {
      long tracked = G_WorkerSlots[j].chartId;
      if(tracked > 0 && !MBP_IsChartAlive(tracked))
      {
         string trackedAssignedSymbol = "";
         string trackedAssignedSymbolsCsv = "";
         string trackedAssignedChartSymbol = "";
         string trackedAssignedCoordinatorKey = "";
         long trackedAssignedCoordinatorChartId = 0;
         string trackedAssignedSignature = "";
         datetime trackedAssignedAt = 0;
         bool trackedHasAssignment = MBP_ReadWorkerAssignment(tracked,
                                                              trackedAssignedSymbol,
                                                              trackedAssignedSymbolsCsv,
                                                              trackedAssignedChartSymbol,
                                                              trackedAssignedCoordinatorKey,
                                                              trackedAssignedCoordinatorChartId,
                                                              trackedAssignedSignature,
                                                              trackedAssignedAt);
         bool protectedByLaunchGrace = (trackedHasAssignment &&
                                        MBP_CoordinatorKeyMatchesRuntime(trackedAssignedCoordinatorKey, coordinatorKey) &&
                                        StringCompare(trackedAssignedSignature,
                                                      G_WorkerSlots[j].assignmentSignature,
                                                      false) == 0 &&
                                        MBP_IsWorkerAssignmentInLaunchGrace(trackedAssignedAt,
                                                                           G_WorkerSlots[j].lastLaunchAttemptMs));
         if(!protectedByLaunchGrace)
            G_WorkerSlots[j].chartId = 0;
      }
   }

   for(int i = 0; i < ArraySize(G_WorkerSlots); i++)
   {
      string baseSymbol = G_WorkerSlots[i].symbol;
      if(baseSymbol == "")
         continue;

      string workerChartSymbol = G_WorkerSlots[i].chartSymbol;
      if(workerChartSymbol == "")
         workerChartSymbol = baseSymbol;
      if(MBP_IsSyntheticDataMode(MBP_EffectiveDataMode()))
      {
         bool customReady = (bool)SymbolInfoInteger(workerChartSymbol, SYMBOL_CUSTOM);
         if(!customReady)
         {
            ResetLastError();
            if(!CustomSymbolCreate(workerChartSymbol, "MultiBotPro", baseSymbol))
            {
               if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(EmojiWarning(), " Worker synthetic symbol create failed for ", workerChartSymbol, " Error=", _LastError);
               G_WorkerSlots[i].lastLaunchAttemptMs = nowMs;
               continue;
            }
         }

         CustomSymbolSetInteger(workerChartSymbol, SYMBOL_DIGITS, (int)SymbolInfoInteger(baseSymbol, SYMBOL_DIGITS));
         CustomSymbolSetDouble(workerChartSymbol, SYMBOL_POINT, SymbolInfoDouble(baseSymbol, SYMBOL_POINT));
         CustomSymbolSetDouble(workerChartSymbol, SYMBOL_TRADE_TICK_SIZE, SymbolInfoDouble(baseSymbol, SYMBOL_TRADE_TICK_SIZE));

         // Ensure the synthetic symbol has seed history before ChartOpen
         // so MT5 can open the chart and apply the template without failing/stalling
         if(Bars(workerChartSymbol, PERIOD_M1) == 0)
         {
            MqlRates seedRates[];
            int seedCount = CopyRates(baseSymbol, PERIOD_M1, 0, 100, seedRates);
            if(seedCount > 0)
            {
               CustomRatesUpdate(workerChartSymbol, seedRates, seedCount);
            }
         }
      }

      if(!SymbolSelect(baseSymbol, true))
      {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(EmojiWarning(), " Worker base symbol selection failed for ", baseSymbol);
         continue;
      }
      if(!SymbolSelect(workerChartSymbol, true))
      {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(EmojiWarning(), " Worker chart symbol selection failed for ", workerChartSymbol);
         continue;
      }

      long targetChartId = 0;
      bool newlyAssigned = false;
      bool templateRequired = false;

      long trackedChartId = G_WorkerSlots[i].chartId;
      if(trackedChartId > 0 && trackedChartId != ChartID() && MBP_IsChartAlive(trackedChartId))
      {
         string trackedChartSymbol = ChartSymbol(trackedChartId);
         if(workerChartSymbol == "" || StringCompare(trackedChartSymbol, workerChartSymbol, false) == 0)
            targetChartId = trackedChartId;
      }

      if(targetChartId <= 0 && trackedChartId > 0 && trackedChartId != ChartID())
      {
         datetime trackedHeartbeat = 0;
         long trackedHeartbeatChartId = 0;
         string trackedHeartbeatSymbolsCsv = "";
         string trackedHeartbeatSignature = "";
         string trackedHeartbeatState = "";
         if(MBP_ReadWorkerHeartbeat(baseSymbol,
                                    coordinatorKey,
                                    trackedHeartbeat,
                                    trackedHeartbeatChartId,
                                    trackedHeartbeatSymbolsCsv,
                                    trackedHeartbeatSignature,
                                    trackedHeartbeatState) &&
            trackedHeartbeatChartId == trackedChartId &&
            MBP_WorkerHeartbeatSignatureMatches(trackedHeartbeatSignature, G_WorkerSlots[i].assignmentSignature) &&
            MBP_IsWorkerHeartbeatFreshForState(trackedHeartbeat, trackedHeartbeatState) &&
            MBP_IsWorkerHeartbeatGraceState(trackedHeartbeatState))
         {
            G_WorkerSlots[i].lastHeartbeat = trackedHeartbeat;
            if(StringCompare(G_WorkerSlots[i].lastLoggedHeartbeatState, trackedHeartbeatState, false) != 0)
            {
               if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiBrain(), " Coordinator holding worker slot ", i,
                     " for ", G_WorkerSlots[i].symbolsCsv,
                     " on chart ", trackedChartId,
                     " while heartbeat=", trackedHeartbeatState, ".");
               G_WorkerSlots[i].lastLoggedChartId = trackedChartId;
               G_WorkerSlots[i].lastLoggedHeartbeatState = trackedHeartbeatState;
            }
            continue;
         }

         string trackedAssignedSymbol = "";
         string trackedAssignedSymbolsCsv = "";
         string trackedAssignedChartSymbol = "";
         string trackedAssignedCoordinatorKey = "";
         long trackedAssignedCoordinatorChartId = 0;
         string trackedAssignedSignature = "";
         datetime trackedAssignedAt = 0;
         bool trackedHasAssignment = MBP_ReadWorkerAssignment(trackedChartId,
                                                              trackedAssignedSymbol,
                                                              trackedAssignedSymbolsCsv,
                                                              trackedAssignedChartSymbol,
                                                              trackedAssignedCoordinatorKey,
                                                              trackedAssignedCoordinatorChartId,
                                                              trackedAssignedSignature,
                                                              trackedAssignedAt);
         if(trackedHasAssignment &&
            MBP_CoordinatorKeyMatchesRuntime(trackedAssignedCoordinatorKey, coordinatorKey) &&
            StringCompare(trackedAssignedSignature, G_WorkerSlots[i].assignmentSignature, false) == 0 &&
            MBP_IsWorkerAssignmentInLaunchGrace(trackedAssignedAt, G_WorkerSlots[i].lastLaunchAttemptMs))
         {
            if(StringCompare(G_WorkerSlots[i].lastLoggedHeartbeatState, "LAUNCH_GRACE", false) != 0)
            {
               if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiBrain(), " Coordinator holding worker slot ", i,
                     " for ", G_WorkerSlots[i].symbolsCsv,
                     " on chart ", trackedChartId,
                     " during launch grace.");
               G_WorkerSlots[i].lastLoggedChartId = trackedChartId;
               G_WorkerSlots[i].lastLoggedHeartbeatState = "LAUNCH_GRACE";
            }
            continue;
         }
      }

      if(targetChartId <= 0)
      {
         long assignedChartId = MBP_FindAssignedWorkerChart(baseSymbol,
                                                            coordinatorKey,
                                                            G_WorkerSlots[i].assignmentSignature,
                                                            ChartID());
         if(assignedChartId > 0 && assignedChartId != ChartID() && MBP_IsChartAlive(assignedChartId))
            targetChartId = assignedChartId;
      }

      if(targetChartId <= 0)
      {
         long protectedChartId = MBP_FindProtectedWorkerChartBySymbol(workerChartSymbol,
                                                                      baseSymbol,
                                                                      coordinatorKey,
                                                                      G_WorkerSlots[i].assignmentSignature,
                                                                      ChartID());
         if(protectedChartId > 0 && MBP_IsChartAlive(protectedChartId))
            targetChartId = protectedChartId;
      }

      if(targetChartId <= 0)
      {
         long reusableChartId = MBP_FindReusableChartBySymbol(workerChartSymbol, ChartID());
         if(reusableChartId > 0 && MBP_IsChartAlive(reusableChartId))
         {
            targetChartId = reusableChartId;
            templateRequired = true;
         }
      }

      if(targetChartId <= 0)
      {
         // Throttle: don't open a new chart within the launch grace window.
         // This prevents rapid open/close churn when a worker is repeatedly killed
         // before it can publish its first heartbeat (e.g. during history replay).
         if(G_WorkerSlots[i].lastLaunchAttemptMs > 0 &&
            (nowMs - G_WorkerSlots[i].lastLaunchAttemptMs) < MBP_WORKER_CHART_OPEN_COOLDOWN_MS)
         {
            continue;
         }

         // The template can be deleted/corrupted after the coordinator cached its
         // signature. Force a fresh template immediately before opening a new
         // worker chart so the following ChartApplyTemplate has a valid payload.
         if(!MasterSaveWorkerTemplate(true))
         {
            if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiWarning(), " Worker launch skipped for ", baseSymbol,
                  " because the worker template could not be rebuilt.");
            G_WorkerSlots[i].lastLaunchAttemptMs = nowMs;
            continue;
         }
         templateName = MBP_WorkerTemplateName();

         targetChartId = ChartOpen(workerChartSymbol, targetPeriod);
         newlyAssigned = true;
         templateRequired = true;
      }

      if(targetChartId <= 0 || targetChartId == ChartID())
      {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiWarning(), " Worker launch skipped for ", baseSymbol, " because no safe chart target was available.");
         continue;
      }

      if(newlyAssigned && !MBP_WaitForChartTargetReady(targetChartId, workerChartSymbol, 1500))
      {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiWarning(), " Worker chart target is still settling for ", baseSymbol,
               " on chart ", targetChartId, ". Keeping this chart assigned.");
      }

      ApplyChartStyles(targetChartId);

      string targetAssignedSymbol = "";
      string targetAssignedSymbolsCsv = "";
      string targetAssignedChartSymbol = "";
      string targetAssignedCoordinatorKey = "";
      long targetAssignedCoordinatorChartId = 0;
      string targetAssignedSignature = "";
      datetime targetAssignedAt = 0;
      bool targetHadAssignment = MBP_ReadWorkerAssignment(targetChartId,
                                                          targetAssignedSymbol,
                                                          targetAssignedSymbolsCsv,
                                                          targetAssignedChartSymbol,
                                                          targetAssignedCoordinatorKey,
                                                          targetAssignedCoordinatorChartId,
                                                          targetAssignedSignature,
                                                          targetAssignedAt);
      bool targetCoordinatorMatches = (targetHadAssignment &&
                                       MBP_CoordinatorKeyMatchesRuntime(targetAssignedCoordinatorKey, coordinatorKey));
      bool targetSignatureMatches = (targetHadAssignment &&
                                     targetAssignedSignature != "" &&
                                     StringCompare(targetAssignedSignature,
                                                   G_WorkerSlots[i].assignmentSignature,
                                                   false) == 0);
      bool targetSymbolsMatch = (targetHadAssignment &&
                                 StringCompare(targetAssignedSymbolsCsv,
                                               G_WorkerSlots[i].symbolsCsv,
                                               false) == 0);
      bool targetChartSymbolMatches = (targetHadAssignment &&
                                       StringCompare(targetAssignedChartSymbol,
                                                     workerChartSymbol,
                                                     false) == 0);
      bool needsAssignmentStamp = (newlyAssigned ||
                                   !targetHadAssignment ||
                                   !targetCoordinatorMatches ||
                                   !targetSignatureMatches ||
                                   !targetSymbolsMatch ||
                                   !targetChartSymbolMatches);

      if(needsAssignmentStamp &&
         !MBP_WriteWorkerAssignment(targetChartId,
                                    G_WorkerSlots[i].symbol,
                                    G_WorkerSlots[i].symbolsCsv,
                                    workerChartSymbol,
                                    coordinatorKey,
                                    G_WorkerSlots[i].assignmentSignature,
                                    i))
      {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(EmojiWarning(), " Failed to stamp worker assignment for ", baseSymbol, " on chart ", targetChartId);
         continue;
      }

      if(!templateRequired)
      {
         datetime targetHeartbeat = 0;
         long targetHeartbeatChartId = 0;
         string targetHeartbeatSymbolsCsv = "";
         string targetHeartbeatSignature = "";
         string targetHeartbeatState = "";
         bool targetHeartbeatOk = MBP_ReadWorkerHeartbeat(baseSymbol,
                                                          coordinatorKey,
                                                          targetHeartbeat,
                                                          targetHeartbeatChartId,
                                                          targetHeartbeatSymbolsCsv,
                                                          targetHeartbeatSignature,
                                                          targetHeartbeatState) &&
                                  targetHeartbeatChartId == targetChartId &&
                                  MBP_WorkerHeartbeatSignatureMatches(targetHeartbeatSignature,
                                                                      G_WorkerSlots[i].assignmentSignature) &&
                                  MBP_IsWorkerHeartbeatFreshForState(targetHeartbeat, targetHeartbeatState);
         bool targetInLaunchGrace = targetHadAssignment &&
                                    MBP_IsWorkerAssignmentInLaunchGrace(targetAssignedAt,
                                                                        G_WorkerSlots[i].lastLaunchAttemptMs);

         if(!targetHeartbeatOk &&
            !targetInLaunchGrace)
         {
            if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiWarning(), " Worker chart ", targetChartId,
                  " for ", baseSymbol,
                  " has assignment but no live heartbeat; preserving lease and waiting instead of reapplying template.");
         }
      }

      if(templateRequired)
      {
         MBP_WriteWorkerLaunchMarker(targetChartId);
         if(!MasterApplyWorkerTemplateWithRecovery(targetChartId, baseSymbol, templateName))
         {
            MBP_ClearWorkerLaunchMarker(targetChartId);
            string assignmentFile = MBP_WorkerAssignmentFile(targetChartId);
            if(FileIsExist(assignmentFile, FILE_COMMON))
               FileDelete(assignmentFile, FILE_COMMON);
            if(newlyAssigned && MBP_IsChartAlive(targetChartId))
               ChartClose(targetChartId);
            G_WorkerSlots[i].lastLaunchAttemptMs = nowMs;
            continue;
         }
      }

      G_WorkerSlots[i].chartId = targetChartId;
      if(newlyAssigned || templateRequired)
      {
         G_WorkerSlots[i].lastLaunchAttemptMs = nowMs;
         ScheduleMasterHostVisibilityHeal(5000);
         RestoreMasterHostChartFocus();
      }

      datetime heartbeat = 0;
      long heartbeatChartId = 0;
      string heartbeatSymbolsCsv = "";
      string heartbeatSignature = "";
      string heartbeatState = "";
      bool hasHeartbeat = MBP_ReadWorkerHeartbeat(baseSymbol,
                                                  coordinatorKey,
                                                  heartbeat,
                                                  heartbeatChartId,
                                                  heartbeatSymbolsCsv,
                                                  heartbeatSignature,
                                                  heartbeatState);
      if(hasHeartbeat && heartbeatChartId > 0 && heartbeatChartId != targetChartId)
         hasHeartbeat = false;
      if(hasHeartbeat &&
         !MBP_WorkerHeartbeatSignatureMatches(heartbeatSignature, G_WorkerSlots[i].assignmentSignature))
         hasHeartbeat = false;
      if(hasHeartbeat && !MBP_IsWorkerHeartbeatFreshForState(heartbeat, heartbeatState))
         hasHeartbeat = false;
      if(hasHeartbeat)
      {
         G_WorkerSlots[i].lastHeartbeat = heartbeat;
         if(StringCompare(heartbeatState, "RUNNING", false) == 0)
         {
            MBP_CloseDuplicateWorkerChartsForChartSymbol(workerChartSymbol,
                                                         coordinatorKey,
                                                         targetChartId,
                                                         ChartID());
         }
      }

      string loggedHeartbeatState = hasHeartbeat ? heartbeatState : "";
      bool shouldLogAssignment = (newlyAssigned ||
                                  templateRequired ||
                                  needsAssignmentStamp ||
                                  G_WorkerSlots[i].lastLoggedChartId != targetChartId ||
                                  StringCompare(G_WorkerSlots[i].lastLoggedHeartbeatState,
                                                loggedHeartbeatState,
                                                false) != 0);
      if(shouldLogAssignment)
      {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiBrain(), " Coordinator assigned worker slot ", i,
               " to ", G_WorkerSlots[i].symbolsCsv,
               " on chart ", targetChartId, " (", workerChartSymbol, ").",
               hasHeartbeat ? (" Heartbeat=" + heartbeatState) : "");
         G_WorkerSlots[i].lastLoggedChartId = targetChartId;
         G_WorkerSlots[i].lastLoggedHeartbeatState = loggedHeartbeatState;
      }
   }
}

void ShadowMaster_Supervise(const bool forceLaunch = false)
{
   if(!ShadowMaster_IsAiRuntimeEnabled() || !ShadowMaster_ShouldOwnRuntime())
      return;

   ulong nowMs = GetTickCount();
   if(!forceLaunch && (nowMs - G_LastShadowSupervisorCheckMs) < 30000)
      return;

   G_LastShadowSupervisorCheckMs = nowMs;
   ShadowMaster_WriteRuntimeConfig(forceLaunch);

   datetime heartbeat = 0;
   string state = "";
   bool hasHeartbeat = ShadowMaster_ReadHeartbeat(heartbeat, state);
   datetime nowGmt = TimeGMT();
   int heartbeatAgeSec = (hasHeartbeat && nowGmt >= heartbeat) ? (int)(nowGmt - heartbeat) : 0;
   bool heartbeatFresh = (hasHeartbeat && heartbeat > 0 && nowGmt > 0 &&
                          nowGmt >= heartbeat && heartbeatAgeSec <= 180);

   static string lastLoggedState = "";
   static bool lastLoggedFresh = false;
   static ulong lastShadowStatusLogMs = 0;
   bool stateChanged = (StringCompare(lastLoggedState, state, false) != 0 ||
                        lastLoggedFresh != heartbeatFresh);
   if(stateChanged || nowMs - lastShadowStatusLogMs >= 60000)
   {
      if(hasHeartbeat)
      {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiBrain(), " ShadowMaster monitor: state=", (state != "" ? state : "UNKNOWN"),
               " heartbeat_age=", heartbeatAgeSec, "s fresh=", (heartbeatFresh ? "true" : "false"), ".");
      }
      else
      {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiWarning(), " ShadowMaster monitor: no runtime status yet. Waiting for ",
               ShadowMaster_RuntimeStatusFileName(), ".");
      }
      lastLoggedState = state;
      lastLoggedFresh = heartbeatFresh;
      lastShadowStatusLogMs = nowMs;
   }

   if(heartbeatFresh)
   {
      MarkShadowMasterPulse(true, "Shadow runtime: " + ((state != "") ? state : "alive"));
      return;
   }

   const ulong shadowLaunchCooldownMs = 900000;
   if(!forceLaunch && G_LastShadowLaunchAttemptMs > 0 &&
      (nowMs - G_LastShadowLaunchAttemptMs) < shadowLaunchCooldownMs)
   {
      MarkShadowMasterPulse(false, "Shadow runtime boot pending");
      return;
   }

   string runtimePath = ShadowMaster_GetRuntimeConfigPath();
   if(!ShadowMaster_WriteRuntimeConfig(true))
      return;

   // CRITICAL: stamp the launch attempt BEFORE invoking the launcher. Whether the
   // .exe is healthy or not, we should engage the 15-min cooldown so a broken
   // binary (LFS pointer, stub, etc.) doesn't trigger relaunch every 30 seconds.
   // Previously this was set only on success, so any persistent launch failure
   // produced a continuous spam of "Starting standalone ShadowMaster..." lines.
   G_LastShadowLaunchAttemptMs = nowMs;

   if(G_AIBridge.BootShadowMaster(runtimePath))
      MarkShadowMasterPulse(false, "Shadow runtime launch requested");
   else
      MarkShadowMasterPulse(false, "Shadow runtime launch failed (see log for details)");
}

bool SmartHedge_IsEnabled()
{
   return (InpEnableSmartHedge && UseTrailing && IsBridgeRuntimeEnabled());
}

double SmartHedge_GetTicketNetPnl(const ulong masterTicket)
{
   if(masterTicket == 0 || !PositionSelectByTicket(masterTicket))
      return 0.0;

   return PositionGetDouble(POSITION_PROFIT) +
          PositionGetDouble(POSITION_SWAP) +
          GetPositionCommission(PositionGetInteger(POSITION_IDENTIFIER));
}

int SmartHedge_FindProtectedTicketIndex(const ulong masterTicket)
{
   for(int i = 0; i < ArraySize(G_SmartHedgeProtectedTrades); i++)
   {
      if(G_SmartHedgeProtectedTrades[i].masterTicket == masterTicket)
         return i;
   }

   return -1;
}

bool SmartHedge_IsProtectedTicket(const ulong masterTicket)
{
   return (SmartHedge_FindProtectedTicketIndex(masterTicket) >= 0);
}

void SmartHedge_RegisterProtectedTicket(const int symbolIndex, const ulong masterTicket, const double baselinePnl = EMPTY_VALUE)
{
   if(masterTicket == 0)
      return;

   double currentPnl = baselinePnl;
   if(currentPnl == EMPTY_VALUE)
      currentPnl = SmartHedge_GetTicketNetPnl(masterTicket);

   int idx = SmartHedge_FindProtectedTicketIndex(masterTicket);
   if(idx < 0)
   {
      idx = ArraySize(G_SmartHedgeProtectedTrades);
      ArrayResize(G_SmartHedgeProtectedTrades, idx + 1);
      G_SmartHedgeProtectedTrades[idx].masterTicket = masterTicket;
      G_SmartHedgeProtectedTrades[idx].totalBaselinePnl = currentPnl;
      G_SmartHedgeProtectedTrades[idx].dailyBaselinePnl = currentPnl;
      G_SmartHedgeProtectedTrades[idx].lastSeenPnl = currentPnl;
      G_SmartHedgeProtectedTrades[idx].releasedAt = TimeCurrent();
      G_SmartHedgeProtectedTrades[idx].basketId = 0;
      G_SmartHedgeProtectedTrades[idx].baseSymbol = "";
   }
   else
   {
      G_SmartHedgeProtectedTrades[idx].lastSeenPnl = currentPnl;
   }

   if(symbolIndex >= 0 && symbolIndex < ArraySize(SymbolData))
   {
      G_SmartHedgeProtectedTrades[idx].basketId = SymbolData[symbolIndex].BasketId;
      G_SmartHedgeProtectedTrades[idx].baseSymbol = GetBaseSymbol(SymbolData[symbolIndex].symbol);
   }
   else if(PositionSelectByTicket(masterTicket))
   {
      G_SmartHedgeProtectedTrades[idx].baseSymbol = PositionGetString(POSITION_SYMBOL);
   }
}

void SmartHedge_ReconcileProtectedTrades()
{
   for(int i = ArraySize(G_SmartHedgeProtectedTrades) - 1; i >= 0; i--)
   {
      ulong masterTicket = G_SmartHedgeProtectedTrades[i].masterTicket;
      if(masterTicket > 0 && PositionSelectByTicket(masterTicket))
      {
         G_SmartHedgeProtectedTrades[i].lastSeenPnl = SmartHedge_GetTicketNetPnl(masterTicket);
         continue;
      }

      G_SmartHedgeClosedTotalAdjustment += (G_SmartHedgeProtectedTrades[i].lastSeenPnl - G_SmartHedgeProtectedTrades[i].totalBaselinePnl);
      G_SmartHedgeClosedDailyAdjustment += (G_SmartHedgeProtectedTrades[i].lastSeenPnl - G_SmartHedgeProtectedTrades[i].dailyBaselinePnl);

      int size = ArraySize(G_SmartHedgeProtectedTrades);
      for(int j = i; j < size - 1; j++)
         G_SmartHedgeProtectedTrades[j] = G_SmartHedgeProtectedTrades[j + 1];
      ArrayResize(G_SmartHedgeProtectedTrades, size - 1);
   }
}

void SmartHedge_ResetDailyBaselines()
{
   G_SmartHedgeClosedDailyAdjustment = 0.0;

   for(int i = 0; i < ArraySize(G_SmartHedgeProtectedTrades); i++)
   {
      double currentPnl = SmartHedge_GetTicketNetPnl(G_SmartHedgeProtectedTrades[i].masterTicket);
      G_SmartHedgeProtectedTrades[i].dailyBaselinePnl = currentPnl;
      G_SmartHedgeProtectedTrades[i].lastSeenPnl = currentPnl;
   }
}

void SmartHedge_ResetAll()
{
   ArrayResize(G_SmartHedgeProtectedTrades, 0);
   G_SmartHedgeClosedTotalAdjustment = 0.0;
   G_SmartHedgeClosedDailyAdjustment = 0.0;

   for(int i = 0; i < ArraySize(SymbolData); i++)
      SmartHedge_ResetSymbol(i);
}

void SmartHedge_ResetSymbol(const int symbolIndex)
{
   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return;

   SymbolData[symbolIndex].SmartHedgeFirstLockSeen = false;
   SymbolData[symbolIndex].SmartHedgeReleased = false;
   SymbolData[symbolIndex].SmartHedgeReleasedAt = 0;
}

int Master_FindSymbolIndexForBridgeTrade(const string baseSymbol, const string comment, const int fallbackIndex = -1)
{
   int basketId = ExtractBasketId(comment);
   if(basketId >= 0)
   {
      for(int i = 0; i < ArraySize(SymbolData); i++)
      {
         if(StringCompare(GetBaseSymbol(SymbolData[i].symbol), baseSymbol, false) != 0)
            continue;
         if(SymbolData[i].BasketId == basketId)
            return i;
      }
   }

   if(fallbackIndex >= 0 && fallbackIndex < ArraySize(SymbolData))
   {
      if(StringCompare(GetBaseSymbol(SymbolData[fallbackIndex].symbol), baseSymbol, false) == 0)
         return fallbackIndex;
   }

   return GetPrimarySymbolIndexByBase(baseSymbol, false);
}

void SmartHedge_QueueSlaveClose(const ulong masterTicket, const string baseSymbol)
{
   if(!IsBridgeRuntimeEnabled())
      return;

   if(masterTicket == 0)
      return;

   if(Master_HasRecentBridgeSignal(masterTicket, 2))
      return;

   HedgeSignal signal;
   ZeroMemory(signal);
   signal.time_msc = GetTickCount();
   signal.ticket = masterTicket;
   signal.action = 2;
   StringToCharArray(baseSymbol, signal.symbol);

   Master_RememberBridgeSignal(masterTicket, signal.action);

   int qSize = ArraySize(G_SignalQueue);
   ArrayResize(G_SignalQueue, qSize + 1);
   G_SignalQueue[qSize] = signal;
}

bool SmartHedge_ShouldBypassSlaveForSymbol(const int symbolIndex)
{
   return (SmartHedge_IsEnabled() &&
           symbolIndex >= 0 &&
           symbolIndex < ArraySize(SymbolData) &&
           SymbolData[symbolIndex].SmartHedgeReleased);
}

void SmartHedge_ReleaseSequence(const int symbolIndex, const string reason)
{
   if(!SmartHedge_IsEnabled() || symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return;
   if(SymbolData[symbolIndex].SmartHedgeReleased)
      return;

   string baseSymbol = GetBaseSymbol(SymbolData[symbolIndex].symbol);
   int protectedCount = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong masterTicket = PositionGetTicket(i);
      if(!PositionSelectByTicket(masterTicket))
         continue;
      if(!IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
         continue;
      if(StringCompare(PositionGetString(POSITION_SYMBOL), baseSymbol, false) != 0)
         continue;

      string comment = PositionGetString(POSITION_COMMENT);
      if(InpEnableMultiBaskets && !IsPositionInBasket(symbolIndex, comment))
         continue;

      double baselinePnl = SmartHedge_GetTicketNetPnl(masterTicket);
      SmartHedge_RegisterProtectedTicket(symbolIndex, masterTicket, baselinePnl);
      SmartHedge_QueueSlaveClose(masterTicket, baseSymbol);
      protectedCount++;
   }

   SymbolData[symbolIndex].SmartHedgeFirstLockSeen = true;
   SymbolData[symbolIndex].SmartHedgeReleased = true;
   SymbolData[symbolIndex].SmartHedgeReleasedAt = TimeCurrent();

   if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) PrintFormat(EmojiShield() + " Smart hedge released for %s | basket=%d | scope=%s | protected_tickets=%d",
               baseSymbol,
               MathMax(1, SymbolData[symbolIndex].BasketId),
               reason,
               protectedCount);
}

void SmartHedge_OnProtectedStopMove(const int symbolIndex, const bool isBasket)
{
   if(!SmartHedge_IsEnabled() || symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return;
   if(SymbolData[symbolIndex].SmartHedgeReleased)
      return;

   if(!SymbolData[symbolIndex].SmartHedgeFirstLockSeen)
   {
      SymbolData[symbolIndex].SmartHedgeFirstLockSeen = true;
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) PrintFormat(EmojiShield() + " Smart hedge armed for %s after the first protected %s SL move.",
                  GetBaseSymbol(SymbolData[symbolIndex].symbol),
                  (isBasket ? "basket" : "master"));
      return;
   }

   SmartHedge_ReleaseSequence(symbolIndex, (isBasket ? "basket" : "master"));
}

void SmartHedge_ApplyPnLAdjustments(double &totalPnL, double &dailyPnL)
{
   if(ArraySize(G_SmartHedgeProtectedTrades) == 0 &&
      G_SmartHedgeClosedTotalAdjustment == 0.0 &&
      G_SmartHedgeClosedDailyAdjustment == 0.0)
      return;

   double liveTotalAdjustment = 0.0;
   double liveDailyAdjustment = 0.0;

   for(int i = 0; i < ArraySize(G_SmartHedgeProtectedTrades); i++)
   {
      ulong masterTicket = G_SmartHedgeProtectedTrades[i].masterTicket;
      if(masterTicket == 0 || !PositionSelectByTicket(masterTicket))
         continue;

      double currentPnl = SmartHedge_GetTicketNetPnl(masterTicket);
      G_SmartHedgeProtectedTrades[i].lastSeenPnl = currentPnl;
      liveTotalAdjustment += (currentPnl - G_SmartHedgeProtectedTrades[i].totalBaselinePnl);
      liveDailyAdjustment += (currentPnl - G_SmartHedgeProtectedTrades[i].dailyBaselinePnl);
   }

   totalPnL -= (G_SmartHedgeClosedTotalAdjustment + liveTotalAdjustment);
   dailyPnL -= (G_SmartHedgeClosedDailyAdjustment + liveDailyAdjustment);
}

void EnsureEntryGateDiagnosticCapacity(int requiredSize = -1)
{
   int targetSize = requiredSize;
   if(targetSize < 0)
      targetSize = ArraySize(SymbolData);
   if(targetSize < 0)
      targetSize = 0;

   int currentSize = ArraySize(G_EntryGateReason);
   if(currentSize >= targetSize)
      return;

   ArrayResize(G_EntryGateReason, targetSize);
   ArrayResize(G_EntryGateMessage, targetSize);

   for(int i = currentSize; i < targetSize; i++)
   {
      G_EntryGateReason[i] = ENTRY_GATE_UNKNOWN;
      G_EntryGateMessage[i] = "Waiting for setup";
   }
}

void ResetEntryGateDiagnostics()
{
   ArrayResize(G_EntryGateReason, 0);
   ArrayResize(G_EntryGateMessage, 0);
   EnsureEntryGateDiagnosticCapacity();
}

string EntryGateReasonToText(ENUM_ENTRY_GATE_REASON reason)
{
   switch(reason)
   {
      case ENTRY_GATE_READY: return "Ready to trade";
      case ENTRY_GATE_NO_SYMBOLS: return "No symbols configured";
      case ENTRY_GATE_NOT_TRACKED: return "Chart symbol not tracked";
      case ENTRY_GATE_SYSTEM_BLOCKED: return "System block active";
      case ENTRY_GATE_HARD_BLOCK: return "Hard block active";
      case ENTRY_GATE_SESSION_BLOCKED: return "Outside trading session";
      case ENTRY_GATE_NEWS_BLOCKED: return "News filter active";
      case ENTRY_GATE_SEMI_AUTO: return "Semi-auto mode";
      case ENTRY_GATE_BRIDGE_PENDING: return "Bridge approval pending";
      case ENTRY_GATE_HEDGE_BLOCKED: return "Hedge block active";
      case ENTRY_GATE_GLOBAL_COOLDOWN: return "Global cooldown active";
      case ENTRY_GATE_FILTER_STOP: return "Performance filter stopped";
      case ENTRY_GATE_MAX_OPEN_TRADES: return "Max open trades reached";
      case ENTRY_GATE_PAUSED: return "Bot paused";
      case ENTRY_GATE_NLP_BLOCK: return "Shadow NLP halt";
      case ENTRY_GATE_POSITION_ACTIVE: return "Existing position active";
      case ENTRY_GATE_NOT_PRIMARY_BASKET: return "Primary basket routes new signals";
      case ENTRY_GATE_SPREAD_BLOCKED: return "Spread filter blocked";
      case ENTRY_GATE_MA_SIGNAL: return "MA cascade not aligned";
      case ENTRY_GATE_VWAP_SIGNAL: return "VWAP confirmation missing";
      case ENTRY_GATE_ADX_FILTER: return "ADX filter blocked";
      case ENTRY_GATE_BOX_FILTER: return "Box trend blocked";
      case ENTRY_GATE_MACRO_FILTER: return "Currency strength blocked";
      case ENTRY_GATE_SIGNAL_STACK: return "Signal stack incomplete";
      case ENTRY_GATE_BASKET_LIMIT: return "Basket limit reached";
      case ENTRY_GATE_BASKET_DIRECTION: return "Basket direction blocked";
      case ENTRY_GATE_BASKET_DISTANCE: return "Basket spacing blocked";
      default: return "Waiting for setup";
   }
}

string FormatEntryGateMessage(ENUM_ENTRY_GATE_REASON reason, string detail = "")
{
   string base = EntryGateReasonToText(reason);
   if(detail == "" || detail == base)
      return base;

   return base + " - " + detail;
}

void SetEntryGateDiagnostic(int symbolIndex, ENUM_ENTRY_GATE_REASON reason, string detail = "", bool writeLog = true)
{
   if(symbolIndex < 0)
      return;

   EnsureEntryGateDiagnosticCapacity(symbolIndex + 1);

   string message = FormatEntryGateMessage(reason, detail);
   bool changed = (G_EntryGateReason[symbolIndex] != (int)reason || G_EntryGateMessage[symbolIndex] != message);

   G_EntryGateReason[symbolIndex] = (int)reason;
   G_EntryGateMessage[symbolIndex] = message;

   if(writeLog && changed && symbolIndex < ArraySize(SymbolData))
   {
      bool loggableBasket = (!InpEnableMultiBaskets || SymbolData[symbolIndex].IsPrimaryBasket);
      if(loggableBasket)
         if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(GetBaseSymbol(SymbolData[symbolIndex].symbol), " entry gate: ", message);
   }
}

ENUM_ENTRY_GATE_REASON GetEntryGateDiagnosticReason(int symbolIndex)
{
   if(symbolIndex < 0 || symbolIndex >= ArraySize(G_EntryGateReason))
      return ENTRY_GATE_UNKNOWN;

   return (ENUM_ENTRY_GATE_REASON)G_EntryGateReason[symbolIndex];
}

string GetEntryGateDiagnosticMessage(int symbolIndex)
{
   if(symbolIndex < 0)
      return EntryGateReasonToText(ENTRY_GATE_NOT_TRACKED);

   EnsureEntryGateDiagnosticCapacity(symbolIndex + 1);
   return G_EntryGateMessage[symbolIndex];
}

color GetEntryGateDiagnosticColor(int symbolIndex)
{
   switch(GetEntryGateDiagnosticReason(symbolIndex))
   {
      case ENTRY_GATE_READY:
         return clrLime;
      case ENTRY_GATE_MA_SIGNAL:
      case ENTRY_GATE_VWAP_SIGNAL:
      case ENTRY_GATE_ADX_FILTER:
      case ENTRY_GATE_BOX_FILTER:
      case ENTRY_GATE_MACRO_FILTER:
      case ENTRY_GATE_SIGNAL_STACK:
         return clrSilver;
      case ENTRY_GATE_NOT_PRIMARY_BASKET:
         return clrAqua;
      case ENTRY_GATE_UNKNOWN:
         return clrGray;
      default:
         return clrOrange;
   }
}

string GetDashboardEntryGateMessage(int symbolIndex)
{
   if(TradingSymbolsCount == 0)
      return "Entry: " + EntryGateReasonToText(ENTRY_GATE_NO_SYMBOLS);
   if(symbolIndex < 0)
      return "Entry: " + EntryGateReasonToText(ENTRY_GATE_NOT_TRACKED);

   return "Entry: " + GetEntryGateDiagnosticMessage(symbolIndex);
}

//+------------------------------------------------------------------+
//| Convert custom MA method to built-in MA method                   |
//+------------------------------------------------------------------+
ENUM_MA_METHOD GetMAMethod(ENUM_MY_MA_METHOD my_method)
  {
   switch(my_method)
     {
      case MY_MODE_EMA:
        {
         return MODE_EMA;
        }
      case MY_MODE_SMA:
        {
         return MODE_SMA;
        }
      case MY_MODE_SMMA:
        {
         return MODE_SMMA;
        }
      case MY_MODE_LWMA:
        {
         return MODE_LWMA;
        }
      case MY_MODE_VWMA:
        {
         return MODE_LWMA; // Fallback for VWMA (not built-in)
        }
      default:
        {
         return MODE_EMA;
        }
     }
  }

//+------------------------------------------------------------------+
//| Convert custom MA source to applied price                        |
//+------------------------------------------------------------------+
ENUM_APPLIED_PRICE GetMASource(ENUM_MY_MA_SOURCE my_source)
  {
   switch(my_source)
     {
      case MY_SRC_CLOSE:
        {
         return PRICE_CLOSE;
        }
      case MY_SRC_OPEN:
        {
         return PRICE_OPEN;
        }
      case MY_SRC_HIGH:
        {
         return PRICE_HIGH;
        }
      case MY_SRC_LOW:
        {
         return PRICE_LOW;
        }
      case MY_SRC_HL2:
        {
         return PRICE_MEDIAN;
        }
      case MY_SRC_HLC3:
        {
         return PRICE_TYPICAL;
        }
      case MY_SRC_OHLC4:
        {
         return PRICE_WEIGHTED;
        }
      default:
        {
         return PRICE_CLOSE;
        }
     }
  }



bool WasDashboardButtonHandledRecently(const string btnName)
{
   if(btnName == "" || G_LastDashboardButtonHandled != btnName)
      return false;

   ulong nowMs = GetTickCount();
   return (nowMs >= G_LastDashboardButtonHandledMs) && ((nowMs - G_LastDashboardButtonHandledMs) <= DASH_BUTTON_HANDOFF_MS);
}

void RememberDashboardButtonHandled(const string btnName)
{
   if(btnName == "")
      return;

   G_LastDashboardButtonHandled = btnName;
   G_LastDashboardButtonHandledMs = GetTickCount();

   if(ObjectFind(0, btnName) >= 0)
      ObjectSetInteger(0, btnName, OBJPROP_STATE, false);
}

bool ConsumeDashboardButtonState(const string btnName)
{
   if(btnName == "" || ObjectFind(0, btnName) < 0)
      return false;

   if(WasDashboardButtonHandledRecently(btnName))
   {
      ObjectSetInteger(0, btnName, OBJPROP_STATE, false);
      return false;
   }

   if(!ObjectGetInteger(0, btnName, OBJPROP_STATE))
      return false;

   ObjectSetInteger(0, btnName, OBJPROP_STATE, false);
   return true;
}

void MasterPollDashboardButtons()
{
   if(ConsumeDashboardButtonState("Btn_MasterReset"))
      MasterEnqueueUiCommand(MBP_UI_CMD_MASTER_RESET, -1, "Btn_MasterReset");

   if(ConsumeDashboardButtonState("Btn_Pause"))
      MasterEnqueueUiCommand(MBP_UI_CMD_TOGGLE_PAUSE, -1, "Btn_Pause");

   if(ConsumeDashboardButtonState("Btn_Collapse"))
      MasterEnqueueUiCommand(MBP_UI_CMD_TOGGLE_COLLAPSE, -1, "Btn_Collapse");

   if(ConsumeDashboardButtonState("Btn_Dash_Scale_P"))
      MasterEnqueueUiCommand(MBP_UI_CMD_DASH_SCALE_UP, -1, "Btn_Dash_Scale_P");

   if(ConsumeDashboardButtonState("Btn_Dash_Scale_M"))
      MasterEnqueueUiCommand(MBP_UI_CMD_DASH_SCALE_DOWN, -1, "Btn_Dash_Scale_M");

   if(ConsumeDashboardButtonState("Btn_ToggleMan"))
      MasterEnqueueUiCommand(MBP_UI_CMD_TOGGLE_MANUAL_SECTION, -1, "Btn_ToggleMan");

   if(ConsumeDashboardButtonState("Btn_ToggleList"))
      MasterEnqueueUiCommand(MBP_UI_CMD_TOGGLE_TRADE_LIST, -1, "Btn_ToggleList");

   if(ConsumeDashboardButtonState("Btn_CloseAll"))
      MasterEnqueueUiCommand(MBP_UI_CMD_CLOSE_ALL, -1, "Btn_CloseAll");

   if(ConsumeDashboardButtonState("Btn_CloseChart"))
   {
      int symbolIndex = ResolveDashboardFocusSymbolIndex();
      if(symbolIndex < 0)
      {
         symbolIndex = GetSymbolIndex(_Symbol);
         if(symbolIndex == -1)
            symbolIndex = GetSymbolIndex(RealSymbol);
      }

      MasterEnqueueUiCommand(MBP_UI_CMD_CLOSE_SYMBOL, symbolIndex, "Btn_CloseChart");
   }

   if(ConsumeDashboardButtonState("Btn_Settings_Open"))
      MasterEnqueueUiCommand(MBP_UI_CMD_OPEN_SETTINGS_PANEL, -1, "Btn_Settings_Open");

   if(ConsumeDashboardButtonState("Btn_Settings_Close"))
      MasterEnqueueUiCommand(MBP_UI_CMD_CLOSE_SETTINGS_PANEL, -1, "Btn_Settings_Close");

   if(ConsumeDashboardButtonState("Btn_Settings_Scale_P"))
      MasterEnqueueUiCommand(MBP_UI_CMD_SETTINGS_SCALE_UP, -1, "Btn_Settings_Scale_P");

   if(ConsumeDashboardButtonState("Btn_Settings_Scale_M"))
      MasterEnqueueUiCommand(MBP_UI_CMD_SETTINGS_SCALE_DOWN, -1, "Btn_Settings_Scale_M");

   if(ConsumeDashboardButtonState("Btn_Settings_Mode_Select"))
      MasterEnqueueUiCommand(MBP_UI_CMD_SETTINGS_MODE_NEXT, -1, "Btn_Settings_Mode_Select");

   if(ConsumeDashboardButtonState("Btn_Settings_Mode_OK"))
      MasterEnqueueUiCommand(MBP_UI_CMD_SETTINGS_APPLY_MODE, -1, "Btn_Settings_Mode_OK");
}

bool MasterHasQueuedUiCommands()
{
   return (G_MasterUiCommandCount > 0);
}

bool MasterHasPendingTradeControlJob()
{
   return (G_TradeControlJobType != MBP_CONTROL_JOB_NONE);
}

void MasterRaiseUiPriorityWindow(const ulong holdMs = 750)
{
   ulong untilMs = GetTickCount() + holdMs;
   if(untilMs > G_MasterUiPriorityUntilMs)
      G_MasterUiPriorityUntilMs = untilMs;
   G_ForceDashboardRefresh = true;
}

bool MasterDequeueUiCommand(SMasterUiCommand &cmd)
{
   if(G_MasterUiCommandCount <= 0)
      return false;

   cmd = G_MasterUiCommandQueue[G_MasterUiCommandHead];
   G_MasterUiCommandHead = (G_MasterUiCommandHead + 1) % MBP_UI_COMMAND_QUEUE_CAPACITY;
   G_MasterUiCommandCount--;
   return true;
}

bool MasterEnqueueUiCommand(const int commandType, const int symbolIndex, const string buttonName)
{
   if(commandType == MBP_UI_CMD_NONE)
      return false;

   if(ArraySize(G_MasterUiCommandQueue) != MBP_UI_COMMAND_QUEUE_CAPACITY)
      ArrayResize(G_MasterUiCommandQueue, MBP_UI_COMMAND_QUEUE_CAPACITY);

   if(buttonName != "")
      RememberDashboardButtonHandled(buttonName);

   if(G_MasterUiCommandCount >= MBP_UI_COMMAND_QUEUE_CAPACITY)
   {
      G_MasterUiCommandHead = (G_MasterUiCommandHead + 1) % MBP_UI_COMMAND_QUEUE_CAPACITY;
      G_MasterUiCommandCount--;
      if(MBP_LogTierEnabled(MBP_LOG_TIER_DEBUG)) Print("[UI] Dashboard command queue full. Dropping oldest command.");
   }

   G_MasterUiCommandQueue[G_MasterUiCommandTail].type = commandType;
   G_MasterUiCommandQueue[G_MasterUiCommandTail].symbolIndex = symbolIndex;
   G_MasterUiCommandQueue[G_MasterUiCommandTail].buttonName = buttonName;
   G_MasterUiCommandTail = (G_MasterUiCommandTail + 1) % MBP_UI_COMMAND_QUEUE_CAPACITY;
   G_MasterUiCommandCount++;

   MasterRaiseUiPriorityWindow(1000);
   return true;
}

void MasterApplyDashboardDataModeSelection()
{
   bool useDefault = (G_DashboardSettingsModeCursor <= 0);
   ENUM_MBP_DATA_MODE selectedMode = MBP_DashboardModeAtCursor(G_DashboardSettingsModeCursor);
   ENUM_MBP_DATA_MODE previousMode = MBP_EffectiveDataMode();

   G_DataModeOverrideEnabled = !useDefault;
   G_DataModeOverride = selectedMode;
   ENUM_MBP_DATA_MODE effectiveMode = MBP_EffectiveDataMode();

   if(previousMode == effectiveMode)
   {
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiBrain(), " Chart type unchanged: ", MBP_DataModeToText(effectiveMode), ".");
      return;
   }

   if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiBrain(), " Applying dashboard chart type: ",
         MBP_DataModeToText(effectiveMode), useDefault ? " (default input)." : " (runtime override).");

   ChartMode = MBP_DataModeToChartMode(effectiveMode);
   ShutdownMasterRuntime();

   int total = MathMax(ArraySize(SymbolData), TradingSymbolsCount);
   if(ArraySize(SymbolData) < total)
      ArrayResize(SymbolData, total);

   for(int i = 0; i < total; i++)
   {
      string baseSymbol = GetManagedBaseSymbol(i);
      if(baseSymbol == "")
         baseSymbol = GetBaseSymbol(SymbolData[i].symbol);
      if(baseSymbol == "" && i < TradingSymbolsCount)
         baseSymbol = GetBaseSymbol(TradingSymbols[i]);
      if(baseSymbol == "" && i < TradingSymbolsCount)
         baseSymbol = TradingSymbols[i];
      if(baseSymbol == "")
         baseSymbol = SymbolData[i].symbol;
      if(baseSymbol == "")
         continue;

      int basketId = MathMax(1, SymbolData[i].BasketId);
      bool isPrimaryBasket = (SymbolData[i].IsPrimaryBasket || !InpEnableMultiBaskets);
      bool basketActive = SymbolData[i].BasketActive;
      double basketInitialEntry = SymbolData[i].BasketInitialEntry;
      ENUM_POSITION_TYPE basketDirection = SymbolData[i].BasketDirection;
      double pruningLoss = SymbolData[i].AccumulatedPruningLoss;
      double criticalLoss = SymbolData[i].AccumulatedCriticalLoss;

      bool ok = IsParallelCoordinatorMode()
                ? InitializeCoordinatorSymbolState(baseSymbol, i)
                : InitializeSymbolData(baseSymbol, i, effectiveMode);

      if(!ok)
      {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(EmojiWarning(), " Dashboard chart type switch failed for ", baseSymbol,
               " in mode ", MBP_DataModeToText(effectiveMode), ". Keeping symbol visible on base chart.");
         SymbolData[i].active = true;
         SymbolData[i].BaseSymbol = baseSymbol;
         SymbolData[i].AnalysisSymbol = baseSymbol;
         SymbolData[i].symbol = baseSymbol;
         SymbolData[i].DataMode = MBP_DATA_LIVE;
         SymbolData[i].RenkoFamily = MBP_RENKO_CLASSIC;
         SymbolData[i].BasketId = basketId;
         SymbolData[i].IsPrimaryBasket = isPrimaryBasket;
         SymbolData[i].BasketActive = basketActive;
         SymbolData[i].BasketInitialEntry = basketInitialEntry;
         SymbolData[i].BasketDirection = basketDirection;
         SymbolData[i].AccumulatedPruningLoss = pruningLoss;
         SymbolData[i].AccumulatedCriticalLoss = criticalLoss;
         continue;
      }

      SymbolData[i].BasketId = basketId;
      SymbolData[i].IsPrimaryBasket = isPrimaryBasket;
      SymbolData[i].BasketActive = basketActive;
      SymbolData[i].BasketInitialEntry = basketInitialEntry;
      SymbolData[i].BasketDirection = basketDirection;
      SymbolData[i].AccumulatedPruningLoss = pruningLoss;
      SymbolData[i].AccumulatedCriticalLoss = criticalLoss;
      SymbolData[i].DataMode = effectiveMode;
      SymbolData[i].RenkoFamily = MBP_DataModeToRenkoFamily(effectiveMode);
   }

   Master_OnInit_Runtime();
   if(ShadowMaster_IsAiRuntimeEnabled() && ShadowMaster_ShouldOwnRuntime())
      ShadowMaster_WriteRuntimeConfig(true);
}

bool MasterIsHeavyUiCommand(const int commandType)
{
   return (commandType == MBP_UI_CMD_MASTER_RESET ||
           commandType == MBP_UI_CMD_CLOSE_ALL ||
           commandType == MBP_UI_CMD_CLOSE_SYMBOL);
}

void ResetSymbolStateForMasterReset(const int symbolIndex)
{
   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return;
   if(!SymbolData[symbolIndex].active)
      return;

   WipeBankState(symbolIndex);

   SymbolData[symbolIndex].DailyProfitLoss = 0;
   SymbolData[symbolIndex].PositionCount = 0;
   SymbolData[symbolIndex].AccumulatedPruningLoss = 0.0;
   SymbolData[symbolIndex].AccumulatedCriticalLoss = 0.0;
   SymbolData[symbolIndex].CurrentRecoveryPortion = 0.0;
   SymbolData[symbolIndex].RecoveryIteration = 1;
   SymbolData[symbolIndex].PruningOccurredThisSequence = false;
   SymbolData[symbolIndex].GridTPHit = false;
   SymbolData[symbolIndex].GridTPHitPrice = 0.0;
   SymbolData[symbolIndex].LedgerPruningIn = 0.0;
   SymbolData[symbolIndex].LedgerPruningOut = 0.0;
   SymbolData[symbolIndex].LedgerCriticalIn = 0.0;
   SymbolData[symbolIndex].LedgerCriticalOut = 0.0;
   SymbolData[symbolIndex].LastDebtEventId = 0;

   if(ArraySize(FilterTracker) > symbolIndex)
   {
      FilterTracker[symbolIndex].DailyWins = 0;
      FilterTracker[symbolIndex].DailyLosses = 0;
      FilterTracker[symbolIndex].WinStreak = 0;
      FilterTracker[symbolIndex].LossStreak = 0;
      FilterTracker[symbolIndex].SessionNetProfit = 0;
      FilterTracker[symbolIndex].BlockWins = 0;
      FilterTracker[symbolIndex].BlockLosses = 0;
      FilterTracker[symbolIndex].StopTrading = false;
      FilterTracker[symbolIndex].StopReason = "";
      FilterTracker[symbolIndex].LastResetTime = TimeCurrent();
   }
}

void FinishAsyncControlJob()
{
   if(G_TradeControlJobType == MBP_CONTROL_JOB_RESET)
   {
      GlobalTotalProfit = 0.0;
      GlobalTotalLoss = 0.0;
      DailyGlobalProfit = 0.0;
      DailyGlobalLoss = 0.0;
      LastGlobalDailyReset = TimeCurrent();
      InitReferenceEquity();
      IsPaused = true;

      if(IsParallelCoordinatorMode())
      {
         MBP_SetCoordinatorPaused(G_RuntimeCoordinatorKey, true);
         MBP_SetCoordinatorResetting(G_RuntimeCoordinatorKey, false);
      }

      if(GlobalVariableCheck(InpHedgeChannel + "_STOP_FLAG"))
         GlobalVariableDel(InpHedgeChannel + "_STOP_FLAG");
      if(GlobalVariableCheck(InpHedgeChannel + "_COOLDOWN_TIMER"))
         GlobalVariableDel(InpHedgeChannel + "_COOLDOWN_TIMER");
      if(GlobalVariableCheck(InpHedgeChannel + "_PAUSE_FLAG"))
         GlobalVariableDel(InpHedgeChannel + "_PAUSE_FLAG");

      ResetBridgePendingRequest();
      GlobalTradingEnabled = true;
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiCheck(), " Reset sequence finished asynchronously. System locked in pause until user resumes.");
   }
   else if(G_TradeControlJobType == MBP_CONTROL_JOB_CLOSE_ALL)
   {
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiBroom(), " Manual global close finished.");
   }
   else if(G_TradeControlJobType == MBP_CONTROL_JOB_CLOSE_SYMBOL)
   {
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiBroom(), " Manual chart close finished.");
   }

   G_TradeControlJobType = MBP_CONTROL_JOB_NONE;
   G_TradeControlJobPhase = MBP_CONTROL_PHASE_IDLE;
   G_TradeControlJobCursor = 0;
   G_TradeControlJobSymbolIndex = -1;
   G_TradeControlJobReason = "";
   G_ResetPending = false;
   G_ResetTimestamp = 0;
   MasterRaiseUiPriorityWindow(500);
   MarkIndicatorOverlayDirty();
   ChartRedraw(0);
}

bool StartAsyncControlJob(const int jobType, const int symbolIndex, const string reason)
{
   if(jobType == MBP_CONTROL_JOB_NONE)
      return true;

   if(MasterHasPendingTradeControlJob())
      return false;

   G_TradeControlJobType = jobType;
   G_TradeControlJobPhase = MBP_CONTROL_PHASE_PREPARE;
   G_TradeControlJobCursor = 0;
   G_TradeControlJobSymbolIndex = symbolIndex;
   G_TradeControlJobReason = reason;
   G_ResetPending = (jobType == MBP_CONTROL_JOB_RESET);
   G_ResetTimestamp = GetTickCount();

   if(jobType == MBP_CONTROL_JOB_RESET)
   {
      if(MBP_LogTierEnabled(MBP_LOG_TIER_DEBUG)) Print(EmojiReset(), " Master reset queued. Processing asynchronously.");
      IsPaused = true;
      GlobalTradingEnabled = false;
      if(IsParallelCoordinatorMode())
      {
         MBP_SetCoordinatorPaused(G_RuntimeCoordinatorKey, true);
         MBP_SetCoordinatorResetting(G_RuntimeCoordinatorKey, true);
      }
      WipeAllTerminalGlobalVariables();
      if(IsParallelCoordinatorMode())
      {
         MBP_WriteCoordinatorAliveHeartbeat(G_RuntimeCoordinatorKey, ChartID());
         MBP_SetCoordinatorPaused(G_RuntimeCoordinatorKey, true);
         MBP_SetCoordinatorResetting(G_RuntimeCoordinatorKey, true);
      }
   }
   else if(jobType == MBP_CONTROL_JOB_CLOSE_ALL)
   {
      if(MBP_LogTierEnabled(MBP_LOG_TIER_DEBUG)) Print(EmojiBroom(), " Manual global close queued.");
   }
   else if(jobType == MBP_CONTROL_JOB_CLOSE_SYMBOL)
   {
      if(MBP_LogTierEnabled(MBP_LOG_TIER_DEBUG)) Print(EmojiBroom(), " Manual chart close queued.");
   }

   MasterRaiseUiPriorityWindow(1500);
   return true;
}

void MasterExecuteUiCommand(const SMasterUiCommand &cmd)
{
   switch(cmd.type)
   {
      case MBP_UI_CMD_TOGGLE_PAUSE:
         IsPaused = !IsPaused;
         if(IsParallelCoordinatorMode())
            MBP_SetCoordinatorPaused(G_RuntimeCoordinatorKey, IsPaused);
         if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(IsPaused ? (EmojiPause() + " Bot paused.") : (EmojiCheck() + " Bot resumed."));
         break;

      case MBP_UI_CMD_TOGGLE_COLLAPSE:
         DashboardCollapsed = !DashboardCollapsed;
         DestroyDashboard();
         CreateDashboard();
         break;

      case MBP_UI_CMD_DASH_SCALE_UP:
         if(Dash_Scale < 2.5)
            Dash_Scale += 0.1;
         DestroyDashboard();
         CreateDashboard();
         break;

      case MBP_UI_CMD_DASH_SCALE_DOWN:
         if(Dash_Scale > 0.5)
            Dash_Scale -= 0.1;
         DestroyDashboard();
         CreateDashboard();
         break;

      case MBP_UI_CMD_TOGGLE_MANUAL_SECTION:
         ShowManualSection = !ShowManualSection;
         if(ObjectFind(0, "Btn_ToggleMan") >= 0)
         {
            ObjectSetInteger(0, "Btn_ToggleMan", OBJPROP_STATE, false);
            ObjectSetInteger(0, "Btn_ToggleMan", OBJPROP_BGCOLOR, ShowManualSection ? clrRoyalBlue : clrMidnightBlue);
         }
         DestroyDashboard();
         CreateDashboard();
         MasterRaiseUiPriorityWindow(1000);
         break;

      case MBP_UI_CMD_TOGGLE_TRADE_LIST:
         ShowTradeList = !ShowTradeList;
         if(ObjectFind(0, "Btn_ToggleList") >= 0)
         {
            ObjectSetInteger(0, "Btn_ToggleList", OBJPROP_STATE, false);
            ObjectSetInteger(0, "Btn_ToggleList", OBJPROP_BGCOLOR, ShowTradeList ? clrRoyalBlue : clrMidnightBlue);
         }
         if(!ShowTradeList)
            ObjectsDeleteAll(0, BTN_PREFIX_LIST);
         DestroyDashboard();
         CreateDashboard();
         if(ShowTradeList && !DashboardCollapsed && !Panel_IsModifying)
            ManageTradeListMode();
         MasterRaiseUiPriorityWindow(1000);
         break;

      case MBP_UI_CMD_OPEN_SETTINGS_PANEL:
         G_DashboardSettingsOpen = true;
         DashboardCollapsed = false;
         DestroyDashboard();
         CreateDashboard();
         MasterRaiseUiPriorityWindow(1000);
         break;

      case MBP_UI_CMD_CLOSE_SETTINGS_PANEL:
         G_DashboardSettingsOpen = false;
         DestroyDashboard();
         CreateDashboard();
         MasterRaiseUiPriorityWindow(1000);
         break;

      case MBP_UI_CMD_SETTINGS_SCALE_UP:
         if(Dash_Scale < 2.5)
            Dash_Scale += 0.1;
         DestroyDashboard();
         CreateDashboard();
         MasterRaiseUiPriorityWindow(1000);
         break;

      case MBP_UI_CMD_SETTINGS_SCALE_DOWN:
         if(Dash_Scale > 0.5)
            Dash_Scale -= 0.1;
         DestroyDashboard();
         CreateDashboard();
         MasterRaiseUiPriorityWindow(1000);
         break;

      case MBP_UI_CMD_SETTINGS_MODE_NEXT:
         G_DashboardSettingsModeCursor++;
         if(G_DashboardSettingsModeCursor > 8)
            G_DashboardSettingsModeCursor = 0;
         DestroyDashboard();
         CreateDashboard();
         MasterRaiseUiPriorityWindow(1000);
         break;

      case MBP_UI_CMD_SETTINGS_APPLY_MODE:
         MasterApplyDashboardDataModeSelection();
         DestroyDashboard();
         CreateDashboard();
         MasterRaiseUiPriorityWindow(1500);
         break;

      case MBP_UI_CMD_MASTER_RESET:
         if(!StartAsyncControlJob(MBP_CONTROL_JOB_RESET, -1, "Master Reset"))
            MasterEnqueueUiCommand(cmd.type, cmd.symbolIndex, cmd.buttonName);
         break;

      case MBP_UI_CMD_CLOSE_ALL:
         if(!StartAsyncControlJob(MBP_CONTROL_JOB_CLOSE_ALL, -1, "Manual Global Close"))
            MasterEnqueueUiCommand(cmd.type, cmd.symbolIndex, cmd.buttonName);
         break;

      case MBP_UI_CMD_CLOSE_SYMBOL:
         if(!StartAsyncControlJob(MBP_CONTROL_JOB_CLOSE_SYMBOL, cmd.symbolIndex, "Manual Chart Close"))
            MasterEnqueueUiCommand(cmd.type, cmd.symbolIndex, cmd.buttonName);
         break;
   }

   G_ForceDashboardRefresh = true;
   ChartRedraw(0);
}

void MasterConsumeUiCommands()
{
   int budget = 4;
   while(budget-- > 0 && MasterHasQueuedUiCommands())
   {
      SMasterUiCommand cmd;
      if(!MasterDequeueUiCommand(cmd))
         break;

      if(MasterHasPendingTradeControlJob() && MasterIsHeavyUiCommand(cmd.type))
      {
         MasterEnqueueUiCommand(cmd.type, cmd.symbolIndex, cmd.buttonName);
         break;
      }

      MasterExecuteUiCommand(cmd);
      if(MasterIsHeavyUiCommand(cmd.type))
         break;
   }
}

void MasterProcessTradeControlLane()
{
   if(!MasterHasPendingTradeControlJob())
      return;

   MasterRaiseUiPriorityWindow(750);

   switch(G_TradeControlJobPhase)
   {
      case MBP_CONTROL_PHASE_PREPARE:
         G_TradeControlJobCursor = 0;
         G_TradeControlJobPhase = MBP_CONTROL_PHASE_CLOSE_SYMBOLS;
         return;

      case MBP_CONTROL_PHASE_CLOSE_SYMBOLS:
      {
         if(G_TradeControlJobType == MBP_CONTROL_JOB_CLOSE_SYMBOL)
         {
            if(G_TradeControlJobSymbolIndex >= 0 && G_TradeControlJobSymbolIndex < ArraySize(SymbolData) &&
               SymbolData[G_TradeControlJobSymbolIndex].active)
            {
               CloseAllGridPositions(G_TradeControlJobSymbolIndex, G_TradeControlJobReason);
            }
            G_TradeControlJobPhase = MBP_CONTROL_PHASE_FINALIZE;
            return;
         }

         while(G_TradeControlJobCursor < ArraySize(SymbolData) && !SymbolData[G_TradeControlJobCursor].active)
            G_TradeControlJobCursor++;

         if(G_TradeControlJobCursor < ArraySize(SymbolData))
         {
            CloseAllGridPositions(G_TradeControlJobCursor, G_TradeControlJobReason);
            G_TradeControlJobCursor++;
            return;
         }

         G_TradeControlJobPhase = MBP_CONTROL_PHASE_CLOSE_GLOBALS;
         return;
      }

      case MBP_CONTROL_PHASE_CLOSE_GLOBALS:
         CloseAllGlobalPositions(G_TradeControlJobReason);
         if(G_TradeControlJobType == MBP_CONTROL_JOB_RESET)
         {
            G_TradeControlJobCursor = 0;
            G_TradeControlJobPhase = MBP_CONTROL_PHASE_WIPE_SYMBOLS;
         }
         else
         {
            G_TradeControlJobPhase = MBP_CONTROL_PHASE_FINALIZE;
         }
         return;

      case MBP_CONTROL_PHASE_WIPE_SYMBOLS:
         while(G_TradeControlJobCursor < ArraySize(SymbolData) && !SymbolData[G_TradeControlJobCursor].active)
            G_TradeControlJobCursor++;

         if(G_TradeControlJobCursor < ArraySize(SymbolData))
         {
            ResetSymbolStateForMasterReset(G_TradeControlJobCursor);
            G_TradeControlJobCursor++;
            return;
         }

         G_TradeControlJobPhase = MBP_CONTROL_PHASE_FINALIZE;
         return;

      case MBP_CONTROL_PHASE_FINALIZE:
         FinishAsyncControlJob();
         return;
   }
}

bool MBP_ShouldAllowBlockingTradeWait(const string reason)
{
   if(reason == "bridge_sqlite" || reason == "bridge_file")
      return false;

   if(G_InTimerCycle || IsStopped())
      return false;

   if(MasterHasQueuedUiCommands() || MasterHasPendingTradeControlJob())
      return false;

   if(MasterIsUiPriorityWindowActive())
      return false;

   if(reason != "")
   {
      if(StringFind(reason, "Master Reset") >= 0 ||
         StringFind(reason, "Manual Global Close") >= 0 ||
         StringFind(reason, "Manual Chart Close") >= 0 ||
         StringFind(reason, "Global Close") >= 0)
         return false;
   }

   return true;
}


bool SelectOpenPositionByIdentifier(ulong positionId)
{
   if(positionId == 0)
      return false;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong positionTicket = PositionGetTicket(i);
      if(positionTicket == 0)
         continue;
      if(!PositionSelectByTicket(positionTicket))
         continue;
      if((ulong)PositionGetInteger(POSITION_IDENTIFIER) == positionId)
         return true;
   }

   return false;
}

int ResolveExecutedMasterSignalType(ulong dealTicket, ulong positionId, string &resolvedSource)
{
   resolvedSource = "unknown";

   if(SelectOpenPositionByIdentifier(positionId))
   {
      long positionType = PositionGetInteger(POSITION_TYPE);
      if(positionType == POSITION_TYPE_BUY)
      {
         resolvedSource = "position";
         return 0;
      }
      if(positionType == POSITION_TYPE_SELL)
      {
         resolvedSource = "position";
         return 1;
      }
   }

   ulong sourceOrder = (ulong)HistoryDealGetInteger(dealTicket, DEAL_ORDER);
   if(sourceOrder > 0 && HistoryOrderSelect(sourceOrder))
   {
      long orderType = HistoryOrderGetInteger(sourceOrder, ORDER_TYPE);
      if(orderType == ORDER_TYPE_BUY)
      {
         resolvedSource = "order";
         return 0;
      }
      if(orderType == ORDER_TYPE_SELL)
      {
         resolvedSource = "order";
         return 1;
      }
   }

   long dealType = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
   if(dealType == DEAL_TYPE_BUY)
   {
      resolvedSource = "deal";
      return 0;
   }
   if(dealType == DEAL_TYPE_SELL)
   {
      resolvedSource = "deal";
      return 1;
   }

   return -1;
}

string GetMasterReinitFile()
{
   return "HedgeMasterReinit_" + InpHedgeChannel + ".bin";
}

void DeleteExpiredMasterReinitMarker()
{
   string reinitFile = GetMasterReinitFile();
   if(!FileIsExist(reinitFile, FILE_COMMON))
      return;

   int h = FileOpenRobust(reinitFile, FILE_READ|FILE_BIN|FILE_COMMON);
   if(h == INVALID_HANDLE)
      return;

   long expiresAt = FileReadLong(h);
   FileClose(h);

   ulong nowGmt = (ulong)TimeGMT();
   if(expiresAt <= 0 || nowGmt >= (ulong)expiresAt)
      FileDelete(reinitFile, FILE_COMMON);
}

void ClearMasterReinitMarker()
{
   string reinitFile = GetMasterReinitFile();
   if(FileIsExist(reinitFile, FILE_COMMON))
      FileDelete(reinitFile, FILE_COMMON);
}

bool InitializeCoordinatorSymbolState(const string symbol, const int index)
{
   string baseSymbol = GetBaseSymbol(symbol);
   if(baseSymbol == "")
      baseSymbol = symbol;

   if(!SymbolSelect(baseSymbol, true))
   {
      if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print("Error: Failed to select coordinator symbol ", baseSymbol, ". Removed from list.");
      return false;
   }

   SymbolData[index].active = true;
   SymbolData[index].BasketId = 1;
   SymbolData[index].IsPrimaryBasket = true;
   SymbolData[index].BasketActive = false;
   SymbolData[index].BasketInitialEntry = 0.0;
   SymbolData[index].BasketDirection = POSITION_TYPE_BUY;
   ENUM_MBP_DATA_MODE effectiveMode = MBP_EffectiveDataMode();
   SymbolData[index].DataMode = effectiveMode;
   SymbolData[index].RenkoFamily = MBP_DataModeToRenkoFamily(effectiveMode);
   SymbolData[index].BaseSymbol = baseSymbol;
   SymbolData[index].AnalysisSymbol = MBP_IsSyntheticDataMode(effectiveMode)
                                     ? ResolveSyntheticChartSymbolName(baseSymbol, effectiveMode)
                                     : baseSymbol;
   SymbolData[index].symbol = SymbolData[index].AnalysisSymbol;

   for(int ma = 0; ma < 5; ma++)
      for(int tf = 0; tf < 7; tf++)
         SymbolData[index].MA_Handles[ma][tf] = INVALID_HANDLE;

   SymbolData[index].ATR_Handle = INVALID_HANDLE;
   SymbolData[index].ADX_Handle = INVALID_HANDLE;
   SymbolData[index].MA_SL_Handle = INVALID_HANDLE;
   SymbolData[index].LastShadowUpdate = 0;

   return true;
}
//+------------------------------------------------------------------+
//| Expert initialization function                                  |
//+------------------------------------------------------------------+
int Master_OnInit()
  {
    ResetSystemSnapshot();
    G_WorkerBootstrapCompleted = false;
    if(IsParallelWorkerMode())
      {
       G_LicenseValid = true;
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiLock(), " Worker runtime detected. Reusing coordinator license session.");
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiWarning(), " Note: Input parameters on worker charts are ignored. Configuration is coordinated by the Coordinator/Master chart.");
     }
   else if(!VerifyLicense())
   {
      if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print("FATAL: MultiBotPro initialization aborted due to invalid license.");
      return INIT_FAILED;
   }
   G_IS_DEINIT = false;
   G_InitInProgress = true;
   Comment("... loading ...");
   SmartHedge_ResetAll();
  // FIX: Set a shorter timeout (e.g., 10 seconds)
   Trade.SetAsyncMode(false);
   Trade.SetDeviationInPoints(50); // Allow some slippage to avoid rejections
   Trade.SetTypeFilling(ORDER_FILLING_IOC); 
   
   // Add this line if your CTrade object supports it (Standard Library):
   // Trade.SetTimeout(2000); // 10 Seconds (if using custom CTrade class)
  
// 1. Initialize Timeframe Array
   Timeframes[0] = PERIOD_M1;
   TimeframeEnabled[0] = UseM1;
   Timeframes[1] = PERIOD_M3;
   TimeframeEnabled[1] = UseM3;
   Timeframes[2] = PERIOD_M15;
   TimeframeEnabled[2] = UseM15;
   Timeframes[3] = PERIOD_H1;
   TimeframeEnabled[3] = UseH1;
   Timeframes[4] = PERIOD_H4;
   TimeframeEnabled[4] = UseH4;
   Timeframes[5] = PERIOD_D1;
   TimeframeEnabled[5] = UseD1;
   Timeframes[6] = PERIOD_W1;
   TimeframeEnabled[6] = UseW1;

// 1b. Prime active strategy globals before symbol handles are created
   G_MA1_Period = MA1_Period;
   G_MA2_Period = MA2_Period;
   G_Box_Lookback = Box_Lookback;
   G_ADX_Period = ADX_Period;
   G_ADX_MinLevel = ADX_MinLevel;
   G_CurrencyStrengthDelta = CurrencyStrengthDelta;
   G_GridMultiplier = GridMultiplier;

// 1c. Ensure SQLite runtime schema is initialized before any worker/coordinator IPC
   if(InpV3_EnableSQLiteBridge)
      V3_EnsureRuntimeSchema(InpV3_SQLitePath);

// 2. Build symbol list
    BuildSymbolList();
    if(IsParallelCoordinatorMode())
       MBP_EnsureWorkerSlots();
    else
       ArrayResize(G_WorkerSlots, 0);

    if(IsParallelWorkerMode())
       MasterPublishWorkerHeartbeatState("BOOTING", true);

// 3. DETERMINE REAL SYMBOL
   string parts[];
   if(StringSplit(_Symbol, '_', parts) > 0)
     {
      RealSymbol = parts[0];
     }
   else
     {
      RealSymbol = _Symbol;
     }

   G_FastChartSwitchMode = ConsumeFastChartSwitchPending();
   if(G_FastChartSwitchMode)
      RestoreFastChartSwitchDashboardState();

   if(!IsParallelWorkerMode())
      G_Coordinator.Initialize();

   if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiBrain(), " Analysis symbol: ", _Symbol);
   if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiBrain(), " Execution symbol: ", RealSymbol);
   if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiBrain(), " Data mode: ", MBP_DataModeToText(MBP_EffectiveDataMode()),
         G_DataModeOverrideEnabled ? " (dashboard override)" : "");

   if(TradingSymbolsCount == 0)
     {
      string noSymbolsMsg = "No symbols configured. Set ManualSymbols, enable TradeAllMarketWatch, or turn on UseChartSymbol.";
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(noSymbolsMsg);
      Comment(noSymbolsMsg);
      return INIT_FAILED;
     }

// 4. Initialize symbol data array
   ArrayResize(SymbolData, TradingSymbolsCount);
   for(int i = 0; i < TradingSymbolsCount; i++)
   {
      MBP_ResetSymbolPointerState(SymbolData[i]);

      string seededSymbol = TradingSymbols[i];
      if(i >= 0 && i < ArraySize(G_RuntimeSymbols) && G_RuntimeSymbols[i].analysis_symbol != "")
         seededSymbol = G_RuntimeSymbols[i].analysis_symbol;

      string seededBaseSymbol = GetBaseSymbol(TradingSymbols[i]);
      if(seededBaseSymbol == "")
         seededBaseSymbol = GetBaseSymbol(seededSymbol);
      if(seededBaseSymbol == "")
         seededBaseSymbol = TradingSymbols[i];

      SymbolData[i].symbol = TradingSymbols[i];
      SymbolData[i].BaseSymbol = seededBaseSymbol;
      SymbolData[i].AnalysisSymbol = seededBaseSymbol;
      ENUM_MBP_DATA_MODE effectiveMode = MBP_EffectiveDataMode();
      SymbolData[i].DataMode = effectiveMode;
      SymbolData[i].RenkoFamily = MBP_DataModeToRenkoFamily(effectiveMode);
      SymbolData[i].active = false;
      SymbolData[i].LastTickMsc = 0;
      SymbolData[i].LastProcessedSourceTickMsc = 0;
      SymbolData[i].LastProcessedSourceTickCountAtMsc = 0;
      SymbolData[i].BoxHistoryWarmupQueued = false;
      SymbolData[i].BoxHistoryWarmupDone = false;
      SymbolData[i].BoxHistoryWarmupNextAttemptMs = 0;
      SymbolData[i].BoxHistoryWarmupInProgress = false;
      SymbolData[i].BoxHistoryWarmupCursor = 0;
      SymbolData[i].BoxHistoryWarmupBarsToCheck = 0;
      SymbolData[i].BoxHistoryWarmupPrevHigh = 0.0;
      SymbolData[i].BoxHistoryWarmupPrevLow = 0.0;
      SymbolData[i].BoxHistoryWarmupLastTotalBars = 0;
   }

   // Coordinator and standalone master own the analysis engine. Worker charts
   // are execution-only runtimes and must not initialize a second master engine
   // or compete for shared ShadowMaster/chart state.
   if(!IsParallelWorkerMode())
   {
      if(!InitializeMasterAnalysisEngine())
         return INIT_FAILED;
   }

   int activeSymbolsInitialized = 0;
   for(int i = 0; i < TradingSymbolsCount; i++)
   {
      string initialSymbol = TradingSymbols[i];
      if(i >= 0 && i < ArraySize(G_RuntimeSymbols) && G_RuntimeSymbols[i].analysis_symbol != "")
         initialSymbol = G_RuntimeSymbols[i].analysis_symbol;

      if(IsParallelWorkerMode() && !MBP_RuntimeWorkerOwnsSymbol(initialSymbol))
      {
         SymbolData[i].active = false;
         continue;
      }

      bool symbolInitialized = IsParallelCoordinatorMode()
                               ? InitializeCoordinatorSymbolState(initialSymbol, i)
                               : InitializeSymbolData(initialSymbol, i, MBP_EffectiveDataMode());
      if(!symbolInitialized) 
      {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print("Failed to initialize symbol: ", TradingSymbols[i]);
         SymbolData[i].active = false;
         continue;
      }

      SymbolData[i].BasketId = 1;
      SymbolData[i].IsPrimaryBasket = true;
      SymbolData[i].BasketActive = false;
      SymbolData[i].BasketInitialEntry = 0.0;
      SymbolData[i].BasketDirection = POSITION_TYPE_BUY;
      LoadBankState(i);
      activeSymbolsInitialized++;
   }
   G_FastChartSwitchMode = false;

   if(activeSymbolsInitialized == 0)
   {
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("No symbols initialized successfully. Aborting startup.");
      return INIT_FAILED;
   }

// 5. Initialize excluded symbols array
   if(ExcludeSymbols != "")
     {
      StringSplit(ExcludeSymbols, ',', ExcludedSymbols);
     }

// 6. Set trade parameters
   Trade.SetDeviationInPoints(Slippage);

   // Compute effective magic — workers offset by index*STRIDE so each worker's
   // CloseByMagic only touches its own positions. Coordinator/legacy keep base magic.
   if(IsParallelWorkerMode() && G_RuntimeWorkerIndex >= 0 &&
      G_RuntimeWorkerIndex < MBP_WORKER_MAGIC_MAX_OFFSETS)
   {
      G_EffectiveMagicNumber = (long)MagicNumber + (long)G_RuntimeWorkerIndex * MBP_WORKER_MAGIC_STRIDE;
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiBrain(), " Worker ", G_RuntimeWorkerIndex,
            " effective magic: ", G_EffectiveMagicNumber, " (base ", MagicNumber, ").");
   }
   else
   {
      G_EffectiveMagicNumber = (long)MagicNumber;
   }
   Trade.SetExpertMagicNumber(G_EffectiveMagicNumber);

   if(IsParallelWorkerMode())
   {
      LastGlobalDailyReset = TimeCurrent();
      GlobalTotalProfit = 0;
      GlobalTotalLoss = 0;
      DailyGlobalProfit = 0;
      DailyGlobalLoss = 0;
      GlobalTradingEnabled = true;
      IsPaused = false;
      ResetBridgePendingRequest();
      ResetDashboardHeartbeat();
      ResetEntryGateDiagnostics();

      for(int i = 0; i < TradingSymbolsCount; i++)
      {
         if(SymbolData[i].active)
            AdoptExistingPositionsOnStartup(i);
      }

      ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
      if(ShowDashboard)
      {
         DestroyDashboard();
         CreateDashboard();
      }
      InitIndicatorOverlay();
      RefreshIndicatorOverlay(true);
      RefreshCurrentChartBoxLines(true);

      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("MultiBotPro EA Initialized Successfully");
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("Account: ", AccountInfoDouble(ACCOUNT_BALANCE), " ", AccountInfoString(ACCOUNT_CURRENCY));
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("Grid Distance Type: ", EnumToString(GridDistanceType));
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("Lock Trail: ", EnumToString(LockTrail));
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("Stack Mode: ", StackMode ? "ON" : "OFF", " | Stack Start: ", StackStart);
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("Grid Lot Size Mode: ", EnumToString(GridRiskType));
      ApplyPanelChartForegroundMode();
      InitReferenceEquity();

      MasterStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      m_day_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(InpMasterRiskMode == RISK_TRAILING)
      {
         double base = (InpStartingBalance > 0) ? InpStartingBalance : MasterStartEquity;
         EffectiveMasterRisk = base * (InpTrailPercent / 100.0);
      }
      else
      {
         EffectiveMasterRisk = InpMasterRisk;
      }

      G_WorkerBootstrapCompleted = true;
      G_InitInProgress = false;
      MasterPublishWorkerHeartbeatState("RUNNING", true);
      EventSetMillisecondTimer(125);
      Comment("");
      return INIT_SUCCEEDED;
   }

// 7. Initialize Global Tracking
   LastGlobalDailyReset = TimeCurrent();
   GlobalTotalProfit = 0;
   GlobalTotalLoss = 0;
   DailyGlobalProfit = 0;
   DailyGlobalLoss = 0;
   GlobalTradingEnabled = true;
   IsPaused = false;
   ResetBridgePendingRequest();
   ResetDashboardHeartbeat();
   ResetEntryGateDiagnostics();

   if(!IsParallelCoordinatorMode())
   {
      for(int i = 0; i < TradingSymbolsCount; i++)
         AdoptExistingPositionsOnStartup(i);
   }

// 8. Chart/UI preparation
   // Timer is armed only after all startup state is fully initialized below.

// Force cleanup of old visual lines
   ObjectsDeleteAll(0, "BoxSeg_");
   ObjectsDeleteAll(0, "BoxVert_");
   ObjectsDeleteAll(0, MBV_PREFIX);

// Enable dragging
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);

// Create Dashboard
   if(ShowDashboard)
     {
      DestroyDashboard();
      CreateDashboard();
     }
// Initialize Manual Panel State (Hidden by default)
//ShowManualPanel = true;

// Force Initial Calculation (Box Levels)
    if(!IsParallelCoordinatorMode())
    {
       for(int i = 0; i < TradingSymbolsCount; i++)
       {
          if(SymbolData[i].active && SymbolData[i].symbol == _Symbol)
             UpdateBoxLevels(i);
       }

       InitIndicatorOverlay();
       RefreshIndicatorOverlay(true);
       RefreshCurrentChartBoxLines(true);
    }

// 9. LOGGING & DEBUG PRINTS
   if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("MultiBotPro EA Initialized Successfully");
   if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("Account: ", AccountInfoDouble(ACCOUNT_BALANCE), " ", AccountInfoString(ACCOUNT_CURRENCY));
   if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("Grid Distance Type: ", EnumToString(GridDistanceType));
   if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("Lock Trail: ", EnumToString(LockTrail));
   if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("Stack Mode: ", StackMode ? "ON" : "OFF", " | Stack Start: ", StackStart);
   if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("Grid Lot Size Mode: ", EnumToString(GridRiskType));
   ApplyPanelChartForegroundMode();

// Timezone Check (Live Only)
   if(MQLInfoInteger(MQL_TESTER) == 0)
     {
      datetime gmt = TimeGMT();
      datetime srv = TimeCurrent();
      int offset = 0;
      string offsetReason = "";
      bool detectedOffsetOk = MBP_DetectServerGMTOffset(offset, offsetReason);

      if(MBP_LogTierEnabled(MBP_LOG_TIER_DEBUG)) Print("--- TIMEZONE CHECK ---");
      if(MBP_LogTierEnabled(MBP_LOG_TIER_DEBUG)) Print("GMT Time: ", gmt);
      if(MBP_LogTierEnabled(MBP_LOG_TIER_DEBUG)) Print("Trade Server Time: ", TimeTradeServer());
      if(MBP_LogTierEnabled(MBP_LOG_TIER_DEBUG)) Print("Server Time: ", srv);
      if(detectedOffsetOk)
      {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_DEBUG)) Print("Detected Server Offset: UTC ", (offset >= 0 ? "+" : ""), offset);
         if(offsetReason != "")
            if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("Timezone note: ", offsetReason);
      }
      else
      {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print("Detected Server Offset invalid (", offsetReason,
               "). Using configured InpServerGMTOffset: UTC ",
               (offset >= 0 ? "+" : ""), offset);
      }
     }
     
   InitReferenceEquity();
   
   // 1. Default to user inputs initially
   G_MA1_Period = MA1_Period;
   G_MA2_Period = MA2_Period;
   G_Box_Lookback = Box_Lookback;
   G_ADX_Period = ADX_Period;
   G_ADX_MinLevel = ADX_MinLevel;
   G_CurrencyStrengthDelta = CurrencyStrengthDelta;
   G_GridMultiplier = GridMultiplier;

   if(ShadowMaster_IsAiRuntimeEnabled() && ShadowMaster_ShouldOwnRuntime())
   {
      ShadowMaster_WriteRuntimeConfig(true);
      ShadowMaster_Supervise(true);
      ShadowMaster_PollConfigUpdates(true);
   }
   
// --- CRITICAL FIX FOR LAZY LOADER ---
// We reset the array to 0. This signals OnTimer to open the charts.
   ArrayResize(MyChartIDs, 0);
   
   // --- PERSISTENT MASTER EQUITY (Survives Property Changes) ---
   MasterStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(GlobalVariableCheck(InpHedgeChannel+"_MasterStartEq")) {
       double savedEq = GlobalVariableGet(InpHedgeChannel+"_MasterStartEq");
       if(savedEq > 0) MasterStartEquity = savedEq;
   }
   GlobalVariableSet(InpHedgeChannel+"_MasterStartEq", MasterStartEquity);

   // --- ALIGN STARTUP TO 5 PM NY TRADING DAY ---
   datetime gmtTimeInit = TimeGMT();
   int ny_offset_init = (-5 + InpNYManualShift) * 3600; 
   datetime sessionTimeInit = gmtTimeInit + ny_offset_init + (7 * 3600); // +7 hours maps Midnight to 5 PM NY
   
   MqlDateTime dt_session_init; 
   TimeToStruct(sessionTimeInit, dt_session_init);
   
   m_current_day_of_year = dt_session_init.day_of_year;
   m_day_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   if(GlobalVariableCheck(InpHedgeChannel+"_MasterDayEq") && GlobalVariableCheck(InpHedgeChannel+"_MasterDayOfYear")) {
       int savedDay = (int)GlobalVariableGet(InpHedgeChannel+"_MasterDayOfYear");
       if(savedDay == m_current_day_of_year) {
           double savedDayEq = GlobalVariableGet(InpHedgeChannel+"_MasterDayEq");
           if(savedDayEq > 0) m_day_start_equity = savedDayEq;
       }
   }
   GlobalVariableSet(InpHedgeChannel+"_MasterDayEq", m_day_start_equity);
   GlobalVariableSet(InpHedgeChannel+"_MasterDayOfYear", m_current_day_of_year);
         if (InpMasterRiskMode == RISK_TRAILING) {
          double base = (InpStartingBalance > 0) ? InpStartingBalance : MasterStartEquity;
          EffectiveMasterRisk = base * (InpTrailPercent / 100.0);
       } else {
          EffectiveMasterRisk = InpMasterRisk;
       }
   
   // if(!MasterGUI.CreatePanel("HedgeMaster", true)) return INIT_FAILED;
   // -----------------------------------
   // --- INITIALIZE SQLITE BRIDGE ---
   if(InpV3_EnableSQLiteBridge)
   {
      if(V3_EnsureRuntimeSchema(InpV3_SQLitePath))
      {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiBrain(), " SQLite bridge initialized: ", InpV3_SQLitePath);
         if(IsBridgeRuntimeEnabled())
            V3_InsertEventRow(InpV3_SQLitePath, InpHedgeChannel, "master_init", "{\"status\":\"ready\"}");
      }
      else
      {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(EmojiWarning(), " SQLite runtime schema init failed. Falling back to the file bridge.");
      }
   }

    if(IsBridgeRuntimeEnabled())
    {
       DeleteExpiredMasterReinitMarker();
    }

    if(IsParallelWorkerMode())
    {
       G_WorkerBootstrapCompleted = true;
       MasterPublishWorkerHeartbeatState("RUNNING", true);
    }

    //EventSetTimer(60); // Set a 60-second timer
    G_InitInProgress = false;
    int timerIntervalMs = IsParallelCoordinatorMode() ? 250 : 125;
    EventSetMillisecondTimer(timerIntervalMs);
   Comment("");
   return INIT_SUCCEEDED;
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void Master_OnDeinit(const int reason)
  {
    ShutdownMasterAnalysisEngine();
    SaveAllBankStates();
    G_WorkerBootstrapCompleted = false;
     
    G_IS_DEINIT = true; // Raise the flag first
   DestroyIndicatorOverlay();
   ForceDeleteAllBotObjects();
   
// 1. Deinitialize all symbol data (Releases Indicators)

   for(int i = 0; i < ArraySize(SymbolData); i++)
      {
       DeinitializeSymbolData(i);
      }

   ReleaseCurrencyStrengthHandles();

   if(IsParallelWorkerMode())
   {
      string workerSymbol = G_RuntimeAssignedWorkerSymbol;
      if(workerSymbol == "")
         workerSymbol = GetBaseSymbol(G_RuntimeAssignedChartSymbol);
      if(workerSymbol == "")
         workerSymbol = GetBaseSymbol(_Symbol);
      if(workerSymbol == "")
         workerSymbol = _Symbol;

      string assignedSymbolsCsv = MBP_GetAssignedWorkerSymbolsCsv();
      string assignedChartSymbol = G_RuntimeAssignedChartSymbol;
      if(assignedChartSymbol == "")
         assignedChartSymbol = ChartSymbol(0);
      string assignmentSignature = G_RuntimeAssignedWorkerSignature;
      if(assignmentSignature == "")
         assignmentSignature = MBP_BuildWorkerAssignmentSignature(workerSymbol, assignedChartSymbol, assignedSymbolsCsv);

      if(MBP_ShouldMarkWorkerReloadingOnDeinit(reason))
      {
         MBP_WriteWorkerHeartbeatRecord(workerSymbol,
                                       G_RuntimeCoordinatorKey,
                                       assignedChartSymbol,
                                       assignedSymbolsCsv,
                                       assignmentSignature,
                                       "RELOADING",
                                       0,
                                       MBP_RuntimeServerNow(),
                                       ChartID());
      }
      else
      {
         MBP_WriteWorkerHeartbeatRecord(workerSymbol,
                                       G_RuntimeCoordinatorKey,
                                       assignedChartSymbol,
                                       assignedSymbolsCsv,
                                       assignmentSignature,
                                       "STOPPING",
                                       0,
                                       MBP_RuntimeServerNow(),
                                       ChartID());
         if(InpV3_EnableSQLiteBridge && V3_RuntimeEnabled(InpV3_EnableSQLiteBridge, InpV3_SQLitePath))
            V3_DeleteWorkerStatus(InpV3_SQLitePath, G_RuntimeCoordinatorKey, workerSymbol, ChartID());

         string heartbeatFile = MBP_WorkerHeartbeatFile(workerSymbol, G_RuntimeCoordinatorKey);
         if(FileIsExist(heartbeatFile, FILE_COMMON) &&
            MBP_IsHeartbeatOwnedByChart(workerSymbol,
                                        G_RuntimeCoordinatorKey,
                                        assignmentSignature,
                                        ChartID()))
         {
            FileDelete(heartbeatFile, FILE_COMMON);
         }
      }
   }

   if(IsBridgeRuntimeEnabled() && !IsParallelWorkerMode())
   {
      HedgeState deinitState;
      ZeroMemory(deinitState);

      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double totalPnL = currentEquity - MasterStartEquity;
      double dailyPnL = currentEquity - m_day_start_equity;
      SmartHedge_ReconcileProtectedTrades();
      SmartHedge_ApplyPnLAdjustments(totalPnL, dailyPnL);

      deinitState.master_current_equity = currentEquity;
      deinitState.master_start_equity = MasterStartEquity;
      deinitState.master_pnl = totalPnL;
      deinitState.master_balance_pnl = totalPnL;
      deinitState.master_daily_pnl = dailyPnL;
      deinitState.master_target_risk = EffectiveMasterRisk;
      deinitState.master_target_profit = InpMasterTargetProfit;
      deinitState.master_daily_limit = InpMasterDailyLoss;
      deinitState.master_daily_target = InpMasterDailyProfit;
      deinitState.slave_target_gain = InpSlaveGain;
      deinitState.is_daily_stopped = m_daily_stop_hit;
      deinitState.is_total_stopped = m_total_stop_hit;
      deinitState.is_paused = true;
      deinitState.reset_id = CurrentResetID;
      deinitState.last_heartbeat = (ulong)TimeGMT();

      if(InpV3_EnableSQLiteBridge)
         V3_WriteMasterStateRow(InpV3_SQLitePath, InpHedgeChannel, deinitState);

      string masterFile = GetMasterFile(InpHedgeChannel);
      int hMaster = FileOpen(masterFile, FILE_WRITE|FILE_BIN|FILE_COMMON);
      if(hMaster != INVALID_HANDLE)
      {
         FileWriteStruct(hMaster, deinitState);
         FileClose(hMaster);
      }

      string reinitFile = GetMasterReinitFile();
      int hReinit = FileOpen(reinitFile, FILE_WRITE|FILE_BIN|FILE_COMMON);
      if(hReinit != INVALID_HANDLE)
      {
         FileWriteLong(hReinit, (long)(TimeGMT() + 120));
         FileClose(hReinit);
      }
   }

   if(IsParallelCoordinatorMode())
   {
      MBP_PurgeWorkerLaunchMarkers();

      // Skip chart-cleanup on hot reloads so we don't tear the system down
      // for a recompile/template reapply that will return immediately.
      if(!MBP_ShouldMarkWorkerReloadingOnDeinit(reason))
      {
         // Close every worker chart we spawned so the user doesn't have to.
         for(int wi = 0; wi < ArraySize(G_WorkerSlots); wi++)
         {
            long workerChartId = G_WorkerSlots[wi].chartId;
            if(workerChartId <= 0 || workerChartId == ChartID())
               continue;
            if(!MBP_IsChartAlive(workerChartId))
               continue;

            ResetLastError();
            if(ChartClose(workerChartId))
            {
               string assignmentFile = MBP_WorkerAssignmentFile(workerChartId);
               if(FileIsExist(assignmentFile, FILE_COMMON))
                  FileDelete(assignmentFile, FILE_COMMON);
               if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiBrain(), " Coordinator closed worker chart ", workerChartId, ".");
            }
            else
            {
               if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(EmojiWarning(), " Coordinator could not close worker chart ",
                     workerChartId, " (error=", _LastError, ").");
            }
         }

         long chartId = ChartFirst();
         while(chartId >= 0)
         {
            long nextChartId = ChartNext(chartId);
            if(chartId != ChartID())
            {
               string assignedSymbol = "";
               string assignedSymbolsCsv = "";
               string assignedChartSymbol = "";
               string assignedCoordinatorKey = "";
               long assignedCoordinatorChartId = 0;
               string assignedSignature = "";
               datetime assignedAt = 0;
               if(MBP_ReadWorkerAssignment(chartId,
                                           assignedSymbol,
                                           assignedSymbolsCsv,
                                           assignedChartSymbol,
                                           assignedCoordinatorKey,
                                           assignedCoordinatorChartId,
                                           assignedSignature,
                                           assignedAt) &&
                  MBP_CoordinatorKeyMatchesRuntime(assignedCoordinatorKey, G_RuntimeCoordinatorKey))
               {
                  ResetLastError();
                  if(ChartClose(chartId))
                  {
                     string assignmentFile = MBP_WorkerAssignmentFile(chartId);
                     if(FileIsExist(assignmentFile, FILE_COMMON))
                        FileDelete(assignmentFile, FILE_COMMON);
                     MBP_ClearWorkerLaunchMarker(chartId);
                     if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiBrain(), " Coordinator closed assigned worker chart ", chartId, ".");
                  }
                  else if(_LastError == 4102)
                  {
                     string assignmentFile = MBP_WorkerAssignmentFile(chartId);
                     if(FileIsExist(assignmentFile, FILE_COMMON))
                        FileDelete(assignmentFile, FILE_COMMON);
                     MBP_ClearWorkerLaunchMarker(chartId);
                  }
               }
            }
            chartId = nextChartId;
         }

         // Drop the coordinator-alive heartbeat AND owner stamp so a sibling chart
         // can reclaim the role immediately rather than waiting 5 seconds for staleness.
         MBP_DeleteCoordinatorAliveHeartbeat(G_RuntimeCoordinatorKey);
      }
   }

// 2. Remove timer
   EventKillTimer();
   V3_CloseCachedDatabase();
   ResetBridgePendingRequest();

// 3. Destroy Dashboard (Panel, Labels, & Buttons)
   DestroyDashboard();

// Insert this:
   DestroyManualPanel();

   ForceDeleteAllBotObjects();
    
// Final safety redraw
   ChartRedraw(0);

   if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("MultiBotPro EA Deinitialized");
  }

//+------------------------------------------------------------------+
//| Timer function for periodic updates                              |
//+------------------------------------------------------------------+
bool MasterIsUiPriorityWindowActive()
{
   ulong nowMs = GetTickCount();
   if(nowMs < G_MasterUiPriorityUntilMs)
      return true;
   if(MasterHasQueuedUiCommands() || MasterHasPendingTradeControlJob())
      return true;
   if(IsDragging || G_DashboardDragArmed || Panel_IsModifying || ShowManualSection || ShowTradeList)
      return true;
   return false;
}

void MasterPublishCoordinatorAliveHeartbeatFast()
{
   if(!IsParallelCoordinatorMode() || G_RuntimeCoordinatorKey == "")
      return;

   MBP_WriteCoordinatorAliveHeartbeat(G_RuntimeCoordinatorKey, ChartID());
}

bool MBP_WorkerShouldStopForMissingCoordinator(const string context)
{
   if(!IsParallelWorkerMode() || G_RuntimeCoordinatorKey == "")
      return false;

   static ulong missingStartedMs = 0;
   static ulong lastWarnMs = 0;
   string coordAliveGV = MBP_CoordAliveGVName(G_RuntimeCoordinatorKey);
   ulong nowMs = GetTickCount64();

   if(!GlobalVariableCheck(coordAliveGV))
   {
      if(missingStartedMs == 0)
         missingStartedMs = nowMs;
      if((nowMs - missingStartedMs) <= 15000)
         return false;

      if(nowMs - lastWarnMs >= 30000)
      {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_DEBUG)) Print(EmojiWarning(), " Worker removing itself: coordinator heartbeat missing for key=",
               G_RuntimeCoordinatorKey, " context=", context, ".");
         lastWarnMs = nowMs;
      }
      ExpertRemove();
      ChartClose(ChartID());
      return true;
   }

   missingStartedMs = 0;
   ulong lastBeat = (ulong)GlobalVariableGet(coordAliveGV);
   if(lastBeat <= 0 || nowMs < lastBeat)
      return false;

   ulong staleMs = nowMs - lastBeat;
   if(staleMs <= 10000)
      return false;

   long ownerChartId = MBP_ReadCoordinatorOwnerChartId(G_RuntimeCoordinatorKey);
   bool ownerAlive = (ownerChartId > 0 && MBP_IsChartAlive(ownerChartId));
   if(ownerAlive)
   {
      if(staleMs <= 300000)
         return false;

      if(nowMs - lastWarnMs >= 30000)
      {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_DEBUG)) Print(EmojiWarning(), " Worker pausing: coordinator heartbeat stale (",
               staleMs / 1000, "s). Key=", G_RuntimeCoordinatorKey,
               " ownerChart=", ownerChartId,
               " ownerAlive=true. Halting trades until coordinator returns.");
         lastWarnMs = nowMs;
      }

      return true;
   }

   if(!ownerAlive && staleMs > 15000)
   {
      if(nowMs - lastWarnMs >= 30000)
      {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiWarning(), " Worker removing itself: coordinator owner is gone (",
               staleMs / 1000, "s stale). Key=", G_RuntimeCoordinatorKey,
               " ownerChart=", ownerChartId, " context=", context, ".");
         lastWarnMs = nowMs;
      }
      ExpertRemove();
      ChartClose(ChartID());
      return true;
   }

   if(nowMs - lastWarnMs >= 30000)
   {
      if(MBP_LogTierEnabled(MBP_LOG_TIER_DEBUG)) Print(EmojiWarning(), " Worker pausing: coordinator heartbeat stale (",
            staleMs / 1000, "s). Key=", G_RuntimeCoordinatorKey,
            " ownerChart=", ownerChartId,
            " ownerAlive=", (ownerAlive ? "true" : "false"),
            ". Halting trades until coordinator returns.");
      lastWarnMs = nowMs;
   }

   return true;
}

void Master_OnTimer()
{
   if(IsParallelWorkerMode())
   {
      if(MBP_WorkerShouldStopForMissingCoordinator("timer"))
         return;

      if(G_RuntimeCoordinatorKey != "")
      {
         bool coordPaused = MBP_IsCoordinatorPaused(G_RuntimeCoordinatorKey) || MBP_IsCoordinatorResetting(G_RuntimeCoordinatorKey);
         IsPaused = coordPaused;
      }

      MasterPublishWorkerHeartbeat();
      MasterPumpTimerServices();

      if(ShowDashboard && !DashboardCollapsed)
         UpdateDashboard(0);

      RefreshIndicatorOverlay(false);
      RefreshCurrentChartBoxLines(false);

      return;
   }

   MasterPublishCoordinatorAliveHeartbeatFast();
   G_Coordinator.ProcessCycle();
}


//+------------------------------------------------------------------+
//| Expert tick function (ULTRA-OPTIMIZED WITH SYMBOL FILTERING)     |
//+------------------------------------------------------------------+
void Master_OnTick()
{
   if(G_IS_DEINIT || IsStopped()) return;
   if(!G_LicenseValid) return;

   MasterPublishCoordinatorAliveHeartbeatFast();

   if(MBP_WorkerShouldStopForMissingCoordinator("tick"))
      return;

   if(IsParallelWorkerMode() && G_RuntimeCoordinatorKey != "")
   {
      bool coordPaused = MBP_IsCoordinatorPaused(G_RuntimeCoordinatorKey) || MBP_IsCoordinatorResetting(G_RuntimeCoordinatorKey);
      IsPaused = coordPaused;
   }

   if(MBP_WorkerTradingPausedForRenkoBuild())
   {
      MasterPublishWorkerHeartbeatState("BUILDING_RENKO", false);
      return;
   }

   ulong tickStartMs = GetTickCount();
   bool uiPanelActive = (ShowManualSection || ShowTradeList || Panel_IsModifying ||
                         IsDragging || G_DashboardDragArmed ||
                         tickStartMs < G_MasterUiPriorityUntilMs);

   // --- SAFETY VALVE (DEATH SPIRAL PREVENTION) ---
   static bool wasPaused = false;
   if(GetTickCount() - G_LastLossTime < 5000) 
   {
      Comment(EmojiWarning() + " Safety pause: cooling down after loss...");
       wasPaused = true; 
       return;
   }
   else if(wasPaused)
   {
      Comment("");
      wasPaused = false;
   }

   // --- FORCE CHART APPEARANCE IN CODE ---
   if(!TemplatesApplied && MQLInfoInteger(MQL_TESTER))
   {
      long currChart = ChartFirst();
      while(currChart >= 0)
      {
         ApplyChartStyles(currChart);
         ChartRedraw(currChart);
         currChart = ChartNext(currChart);
      }
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("Charts forced to Candles/Colors via Code.");
      TemplatesApplied = true;
   }

   // ==================================================================
   // GLOBAL CALCULATIONS (Run regardless of block)
   // ==================================================================
   
   // --- Hide/Restore SL & TP Logic ---
   if(HideSLTPDuringCloseBlock)
     {
      if(G_Cache_IsDailyCloseBlock && !G_SLTP_Hidden)
        {
         HideAllStops();
         G_SLTP_Hidden = true;
        }
      else if(!G_Cache_IsDailyCloseBlock && G_SLTP_Hidden)
        {
         RestoreAllStops();
         G_SLTP_Hidden = false;
        }
     }
   if(!IsParallelWorkerMode())
   {
      CheckGlobalDollarLimits();
      CheckAccountEquityLimits();

      if(TimeCurrent() - LastGlobalCheck > 60)
      {
         CheckGlobalLimits();
         LastGlobalCheck = TimeCurrent();
      }
   }

   // ==================================================================
   // EMERGENCY MASTER LIMIT OVERRIDE 
   // ==================================================================
   if(!IsParallelWorkerMode() && IsBridgeRuntimeEnabled() && (m_daily_stop_hit || m_total_stop_hit))
   {
      if(PositionsTotal() > 0)
      {
        if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiShield(), " Master limit breached with the bridge on. Closing all active positions.");
         for(int i = 0; i < ArraySize(SymbolData); i++)
         {
            if(SymbolData[i].active)
            {
               CloseAllGridPositions(i, "Daily/Total Limit Hit");
               ResetGridTracking(i);
            }
         }
         CloseAllGlobalPositions("Daily/Total Limit Hit");
         FlushBridgeSignalQueue();
      }
      return; 
   }

   static ulong lastTickBridgeServiceMs = 0;
   ulong nowBridgeMs = GetTickCount();
   if(!uiPanelActive &&
      (lastTickBridgeServiceMs == 0 ||
       nowBridgeMs <= lastTickBridgeServiceMs ||
       (nowBridgeMs - lastTickBridgeServiceMs) >= 250))
   {
      ProcessBridgePendingRequest();
      FlushBridgeSignalQueue();
      lastTickBridgeServiceMs = nowBridgeMs;
   }

   if(IsParallelCoordinatorMode())
   {
      return;
   }

   // ==================================================================
   // MAIN LOOP 
   // ==================================================================
   int totalSymbols = ArraySize(SymbolData);
   int minSymbolsThisTick = uiPanelActive ? 1 : MathMin(2, totalSymbols);
   int maxSymbolsThisTick = uiPanelActive ? MathMin(2, totalSymbols) : totalSymbols;
   uint tickBudgetMs = uiPanelActive ? 8 : 25;
   int processedSymbols = 0;
   int nextTickCursor = G_TickPumpCursor;

   for(int step = 0; step < totalSymbols; step++)
   {
      int symbolIndex = (G_TickPumpCursor + step) % totalSymbols;
      nextTickCursor = (symbolIndex + 1) % MathMax(1, totalSymbols);

      if(!SymbolData[symbolIndex].active) continue;
      processedSymbols++;
      
      string symbol = GetAnalysisSymbolByIndex(symbolIndex);

      // ========================================================
      // ?? THE TICK GATEKEEPER ??
      // Check if this specific symbol has received new price data
      // ========================================================
      MqlTick currentTick;
      bool hasNewTick = false;
      if(!MasterPrepareSymbolTick(symbolIndex, currentTick, hasNewTick))
         continue;

      // --------------------------------------------------------
// ZONE 1: CRITICAL EXITS (Always Execute - Time/Block Based)
// --------------------------------------------------------
if(G_Cache_IsHardBlock)
{
   SetEntryGateDiagnostic(symbolIndex, ENTRY_GATE_HARD_BLOCK, G_Cache_BlockReason);
   if(ClosePositionsAtBlockStart && PositionsTotal() > 0)
   {
      // FIX: Unconditionally close if trades exist. 
      // Do not rely on cached trackers which are paused during a block.
      CloseAllGridPositions(symbolIndex, G_Cache_BlockReason);
      CloseAllGlobalPositions(G_Cache_BlockReason);
   }
   continue; // Prevent new entries
}

      if(UseTimeFilter && !G_Cache_IsTradingTime && CloseTradesOnSessionExit)
      {
         if(PositionsTotal() > 0)
         {
            CloseAllGridPositions(symbolIndex, "Session Ended - Auto Close");
            CloseAllGlobalPositions("Session Ended - Auto Close");
         }
      }

      if(G_Cache_IsNewsTime && CloseOnNews)
      {
         if(PositionsTotal() > 0)
         {
            CloseAllGridPositions(symbolIndex, "News/Holiday - Auto Close");
            CloseAllGlobalPositions("News/Holiday - Auto Close");
         }
      }

      // ========================================================
      // ?? SYSTEM BLOCK CHECK ??
      // If blocked by Hedge Master or Bridge, stop further processing
      // ========================================================
      if(G_BridgePending.active || G_BridgePending.approved)
      {
         SetEntryGateDiagnostic(symbolIndex, ENTRY_GATE_BRIDGE_PENDING, "Bridge approval pending");
         continue;
      }

      if(G_Cache_SystemBlocked)
      {
         SetEntryGateDiagnostic(symbolIndex, ENTRY_GATE_SYSTEM_BLOCKED, "Master risk block");
         continue;
      }

      // --------------------------------------------------------
      // ZONE 2: PRICE DEPENDENT LOGIC (Only Execute on New Tick)
      // --------------------------------------------------------
      if(hasNewTick)
      {
         // --- A. Indicator & Signal Updates ---
         SymbolData[symbolIndex].NonGridSLMovedThisTick = false;
         SymbolData[symbolIndex].GridSLMovedThisTick = false;

         datetime currentTime = iTime(symbol, PERIOD_CURRENT, 0);
         bool isNewBar = (SymbolData[symbolIndex].LastCandleTime != currentTime);
         bool isPrimaryBasket = (!InpEnableMultiBaskets) || SymbolData[symbolIndex].IsPrimaryBasket;

         if(isNewBar)
         {
            SymbolData[symbolIndex].LastCandleTime = currentTime;
            SymbolData[symbolIndex].ProcessedThisCandle = false;

            if(isPrimaryBasket)
            {
               UpdateBoxLevels(symbolIndex);
               if(ShouldUpdateVWAPRuntime()) UpdateVWAP(symbolIndex);
            }
         }

         UpdatePositionTracking(symbolIndex);

         // --- B. Entry Signals ---
         bool allowEntry = !IsBotPaused() && G_Cache_IsTradingTime && !G_Cache_IsNewsTime;
         if(IsBotPaused())
         {
            SetEntryGateDiagnostic(symbolIndex, ENTRY_GATE_SYSTEM_BLOCKED, "Bot is paused");
         }
         else if(OperationMode == MODE_SEMI_AUTO)
         {
            SetEntryGateDiagnostic(symbolIndex, ENTRY_GATE_SEMI_AUTO, "Auto-entry disabled");
            allowEntry = false;
         }
         else if(!G_Cache_IsTradingTime)
         {
            SetEntryGateDiagnostic(symbolIndex, ENTRY_GATE_SESSION_BLOCKED, "Outside trading window");
         }
         else if(G_Cache_IsNewsTime)
         {
            SetEntryGateDiagnostic(symbolIndex, ENTRY_GATE_NEWS_BLOCKED, "News or holiday window");
         }
         else if(!isPrimaryBasket)
         {
            SetEntryGateDiagnostic(symbolIndex, ENTRY_GATE_NOT_PRIMARY_BASKET, "Primary basket routes new signals");
         }

         bool doSignalCheck = allowEntry && isPrimaryBasket;
         if(doSignalCheck)
         {
            if(InpProcessSignalsPerBar && !isNewBar)
            {
               SetEntryGateDiagnostic(symbolIndex, ENTRY_GATE_SIGNAL_STACK, "Waiting for a new bar", false);
            }
            else
            {
               if(UseORReversal) CheckORReversalSignals(symbolIndex);
               else CheckEntrySignals(symbolIndex);
            }
         }
         // --- C. Trade Management (Trailing, Grids, Stacks) ---
         ManageAllPositionsOnTick(symbolIndex);
         if(SymbolData[symbolIndex].HasPendingTrail) ApplyPendingTrail(symbolIndex);

         if(!IsBotPaused())
         {
            CheckStackTradesOnTick(symbolIndex);

            bool gridAllowed = true;
            if(UseORReversal && !SymbolData[symbolIndex].GridInTrailing) gridAllowed = false;
            
            if(RiskMode == RISK_MODE_GRID && gridAllowed && (SymbolData[symbolIndex].GridLevels > 0 || SymbolData[symbolIndex].GridPhase1Active))
            {
               CheckGridOnTick(symbolIndex);
               if(!SymbolData[symbolIndex].GridTargetReached && SymbolData[symbolIndex].GridPhase1Active)
                  CheckGridTargetOnTick(symbolIndex);
            }

            if(RiskMode == RISK_MODE_ZONE_RECOVERY) CheckZoneRecovery(symbolIndex);
         }
         ManageRisk(symbolIndex);
      }

      if(processedSymbols >= maxSymbolsThisTick)
         break;

      if(processedSymbols >= minSymbolsThisTick && (GetTickCount() - tickStartMs) >= tickBudgetMs)
         break;
   }

   if(totalSymbols > 0)
      G_TickPumpCursor = nextTickCursor;

   if(!uiPanelActive)
   {
      RefreshIndicatorOverlay(false);
      RefreshCurrentChartBoxLines(false);
   }

   if(InpShowSyntheticVisuals && !uiPanelActive)
      Master_RefreshChartVisualPackages(false);
}

//+------------------------------------------------------------------+
//| Trade transaction handler (FIXED: Handles Debt Repayment)        |
//+------------------------------------------------------------------+
void Master_OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
{
   if(IsParallelCoordinatorMode())
      return;

   // WORKER COORDINATOR HEARTBEAT GUARD (mirrors the gate in Master_OnTick).
   // If we're a worker and the coordinator is silent, suppress trade-transaction
   // processing too — otherwise a paused worker still emits bridge signals for
   // trades placed by another chart that filled in for the missing coordinator,
   // producing the duplicate-emit pattern seen in the log.
   if(MBP_WorkerShouldStopForMissingCoordinator("trade"))
      return;

   if(MBP_WorkerTradingPausedForRenkoBuild())
      return;

   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      ulong dealTicket = trans.deal;
      if(HistoryDealSelect(dealTicket))
      {
         long magic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
         if(!IsAppTrade(magic))
            return;

         ENUM_DEAL_ENTRY entryType = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);

         // We only care when trades CLOSE (Entry Out)
         if(entryType == DEAL_ENTRY_OUT)
         {
            double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
            double swap   = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
            double comm   = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
            double netProfit = profit + swap + comm;
            
            string symbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
            if(!MasterRuntimeShouldHandleTradeSymbol(symbol))
               return;

            int symbolIndex = GetSymbolIndex(symbol);

            if(symbolIndex >= 0)
            {
               // Update Global Stats
               SymbolData[symbolIndex].DailyProfitLoss += netProfit;
               DailyGlobalProfit += (netProfit > 0 ? netProfit : 0);
               DailyGlobalLoss += (netProfit < 0 ? MathAbs(netProfit) : 0);

               // --- BRIDGE SIGNAL ---
               if(IsBridgeRuntimeEnabled())
               {
                  ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(dealTicket, DEAL_TYPE);
                  bool wasBuy = (dealType == DEAL_TYPE_SELL); // Closing a Buy creates a Sell deal
                  SendBridgeClose(wasBuy);
               }

               // ==================================================================
               // --- NEW: AUTOMATIC DEBT REPAYMENT (CATCHES BROKER SL/TP) ---
               // ==================================================================
               if(UsePruningRecovery)// && !G_ResetPending)
               {
                  long magic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
                  string comment = HistoryDealGetString(dealTicket, DEAL_COMMENT);
                  ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(dealTicket, DEAL_REASON);

                  // 1. Filter: Must be our Grid/Zone Trade
                  if(IsAppTrade(magic) && (StringFind(comment, "Grid") >= 0 || StringFind(comment, "Zone") >= 0 || StringFind(comment, "Stack") >= 0))
                  {
                     // 2. Identify if this was an "Expert" close (handled by CloseAllGridPositions) 
                     //    or a "Broker" close (SL/TP/Client).
                     //    If it's EXPERT, we skip logic here to avoid double-counting 
                     //    (assuming CloseAllGridPositions does the math). 
                     //    BUT for safety, we process SL/TP/CLIENT here.
                     
                     if(reason == DEAL_REASON_SL || reason == DEAL_REASON_TP || reason == DEAL_REASON_CLIENT || reason == DEAL_REASON_MOBILE)
                     {
                        // A. PROFIT -> PAY DEBT
                        if(netProfit > 0)
                        {
                           if(SymbolData[symbolIndex].AccumulatedPruningLoss > 0)
                           {
                              SymbolData[symbolIndex].AccumulatedPruningLoss -= netProfit;
                              if(SymbolData[symbolIndex].AccumulatedPruningLoss < 0) 
                                 SymbolData[symbolIndex].AccumulatedPruningLoss = 0;
                              AppendDebtLedgerEvent(symbol, "PRUNING_REPAY", -netProfit, SymbolData[symbolIndex].AccumulatedPruningLoss, SymbolData[symbolIndex].AccumulatedCriticalLoss);
                                 // --- ADD THIS ---
                                 SaveBankState(symbolIndex);
                                 // ----------------
                                 
                              if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(symbol, " [Auto-Repay] Broker Closed Trade in Profit ($", DoubleToString(netProfit, 2), 
                                    "). Debt Reduced to: $", DoubleToString(SymbolData[symbolIndex].AccumulatedPruningLoss, 2));
                           }
                        }
                        // B. LOSS -> ADD TO CRITICAL (Unless it's a Pruning event, handled elsewhere)
                        else if(netProfit < 0)
                        {
                           // Standard losses (e.g. Basket SL hit in negative) go to Critical Bank
                           SymbolData[symbolIndex].AccumulatedCriticalLoss += MathAbs(netProfit);
                           AppendDebtLedgerEvent(symbol, "CRITICAL_ADD", MathAbs(netProfit), SymbolData[symbolIndex].AccumulatedPruningLoss, SymbolData[symbolIndex].AccumulatedCriticalLoss);
                           
                           // --- FIX: TRIGGER SAFETY VALVE ---
                           // We just lost money. Stop EVERYTHING immediately.
                           G_LastLossTime = GetTickCount(); 
                           // ---------------------------------

                           // --- ADD THIS ---
                           SaveBankState(symbolIndex);
                           // ----------------
                           if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(symbol, " [Loss-Capture] Broker Closed Trade in Loss ($", DoubleToString(netProfit, 2), 
                                 "). Added to Critical Bank.");
                        }
                     }
                  }
               }
               // ==================================================================

               // Check if all trades are closed to reset flags
               if(RiskMode == RISK_MODE_GRID && SymbolData[symbolIndex].GridPhase2Active)
               {
                  if(CountGridPositions(symbolIndex, true) == 0)
                  {
                     if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(symbol, " All Grid Positions Closed (Detected in OnTradeTransaction). Resetting Tracking.");
                     ResetGridTracking(symbolIndex);
                  }
               }
            }
         }
      }
   }
   
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      ulong dealTicket = trans.deal;
      if(HistoryDealSelect(dealTicket))
      {
         long magic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
         if(!IsAppTrade(magic))
            return;

         long entry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
         ulong posID = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID); // <--- GET POSITION ID

         // Avoid processing if Master Limits are breached
         if(m_daily_stop_hit || m_total_stop_hit) return; 

         string sym = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
         if(!MasterRuntimeShouldHandleTradeSymbol(sym))
            return;
         if(!IsBridgeRuntimeEnabled())
            return;

         HedgeSignal signal;
         ZeroMemory(signal);
         string baseSym = GetBaseSymbol(sym);
         signal.time_msc = GetTickCount();
         signal.ticket = posID; // <--- FIX 2: ALWAYS USE POSITION ID
         StringToCharArray(baseSym, signal.symbol);

         // CASE 1: NEW TRADE OPENED
         if(entry == DEAL_ENTRY_IN) {
            signal.action = 1;
            signal.lots = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);

            string signalTypeSource = "";
            int signalType = ResolveExecutedMasterSignalType(dealTicket, posID, signalTypeSource);
            if(signalType < 0)
            {
               if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) PrintFormat(EmojiWarning() + " Bridge signal ignored: unable to resolve the executed master side for ticket=%I64u symbol=%s",
                           posID,
                           baseSym);
               return;
            }

            signal.type = signalType;

            if((G_BridgePending.active || G_BridgePending.approved) &&
               G_BridgePending.requestId != 0 &&
               G_BridgePending.symbolIndex >= 0 &&
               G_BridgePending.symbolIndex < ArraySize(SymbolData))
            {
               string pendingBaseSymbol = GetBaseSymbol(SymbolData[G_BridgePending.symbolIndex].symbol);
               int queuedSignalType = (G_BridgePending.orderType == ORDER_TYPE_BUY) ? 0 : 1;
               if(StringCompare(pendingBaseSymbol, baseSym, false) == 0 && queuedSignalType != signal.type)
               {
                  if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) PrintFormat(EmojiShield() + " Bridge side mismatch: req=%I64d ticket=%I64u queued=%s executed=%s source=%s symbol=%s. Using the executed master side.",
                              G_BridgePending.requestId,
                              posID,
                              (queuedSignalType == 0 ? "BUY" : "SELL"),
                              (signal.type == 0 ? "BUY" : "SELL"),
                              signalTypeSource,
                              baseSym);
                  G_BridgePending.orderType = (signal.type == 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
               }
            }
            
            string cmt = HistoryDealGetString(dealTicket, DEAL_COMMENT);
            StringToCharArray(cmt, signal.comment);

            double sl = 0, tp = 0;
            if(SelectOpenPositionByIdentifier(posID)) {
               sl = PositionGetDouble(POSITION_SL);
               tp = PositionGetDouble(POSITION_TP);
            }
            double openPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
            double pt = SymbolInfoDouble(sym, SYMBOL_POINT); if(pt == 0) pt = 1.0;
            signal.tp_dist_points = (tp > 0) ? MathAbs(openPrice - tp) / pt : 0;

            int bridgeSymbolIndex = GetPrimarySymbolIndexByBase(baseSym, false);
            if((G_BridgePending.active || G_BridgePending.approved) &&
               G_BridgePending.symbolIndex >= 0 &&
               G_BridgePending.symbolIndex < ArraySize(SymbolData))
            {
               string pendingBaseSymbol = GetBaseSymbol(SymbolData[G_BridgePending.symbolIndex].symbol);
               if(StringCompare(pendingBaseSymbol, baseSym, false) == 0)
                  bridgeSymbolIndex = G_BridgePending.symbolIndex;
            }

            int commentSymbolIndex = Master_FindSymbolIndexForBridgeTrade(baseSym, cmt, bridgeSymbolIndex);
            if(commentSymbolIndex >= 0)
               bridgeSymbolIndex = commentSymbolIndex;

            if(SmartHedge_ShouldBypassSlaveForSymbol(bridgeSymbolIndex))
            {
               double baselinePnl = 0.0;
               if(SelectOpenPositionByIdentifier(posID))
                  baselinePnl = PositionGetDouble(POSITION_PROFIT) +
                                PositionGetDouble(POSITION_SWAP) +
                                GetPositionCommission(PositionGetInteger(POSITION_IDENTIFIER));
               SmartHedge_RegisterProtectedTicket(bridgeSymbolIndex, posID, baselinePnl);
               if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) PrintFormat(EmojiShield() + " Smart hedge bypass active: ticket=%I64u symbol=%s basket=%d | slave mirror skipped.",
                           posID,
                           baseSym,
                           ((bridgeSymbolIndex >= 0 && bridgeSymbolIndex < ArraySize(SymbolData)) ? MathMax(1, SymbolData[bridgeSymbolIndex].BasketId) : 1));
               return;
            }

            double effectiveStop = 0.0;
            double slDistPoints = 0.0;
            double riskMoney = 0.0;
            string riskSource = "";
            string failureReason = "";
            ENUM_ORDER_TYPE executedOrderType = (signal.type == 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
            if(!ResolveEffectiveBridgeRisk(bridgeSymbolIndex, sym, executedOrderType, openPrice, sl, signal.lots, true,
                                           effectiveStop, slDistPoints, riskMoney, riskSource, failureReason))
            {
               if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) PrintFormat(EmojiWarning() + " Bridge signal skipped: ticket=%I64u symbol=%s reason=%s",
                           posID,
                           baseSym,
                           failureReason);
               return;
            }

            signal.sl_dist_points = slDistPoints;
            signal.risk_money = riskMoney;

            if(Master_HasRecentBridgeSignal(posID, signal.action))
            {
               if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) PrintFormat(EmojiShield() + " Duplicate bridge open signal ignored: ticket=%I64u symbol=%s",
                           posID,
                           baseSym);
               return;
            }
            Master_RememberBridgeSignal(posID, signal.action);
            
            // Queue the signal instead of writing synchronously
            int qSize = ArraySize(G_SignalQueue);
            ArrayResize(G_SignalQueue, qSize + 1);
            G_SignalQueue[qSize] = signal;

            if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) PrintFormat(EmojiShield() + " Bridge signal emitted: ticket=%I64u | executed master %s | source=%s | symbol=%s | risk_source=%s | stop=%.5f | sl_pts=%.1f | risk=%.2f",
                        posID,
                        (signal.type == 0 ? "BUY" : "SELL"),
                        signalTypeSource,
                        baseSym,
                        riskSource,
                        effectiveStop,
                        signal.sl_dist_points,
                        signal.risk_money);
         }
         // CASE 2: TRADE CLOSED
         else if(entry == DEAL_ENTRY_OUT) {
            if(SmartHedge_IsProtectedTicket(posID))
               return;

            signal.action = 2; // CLOSE
            if(Master_HasRecentBridgeSignal(posID, signal.action))
               return;
            Master_RememberBridgeSignal(posID, signal.action);
            // Queue the signal
            int qSize = ArraySize(G_SignalQueue);
            ArrayResize(G_SignalQueue, qSize + 1);
            G_SignalQueue[qSize] = signal;
            if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) PrintFormat(EmojiShield() + " Bridge close signal emitted: ticket=%I64u | symbol=%s",
                        posID,
                        baseSym);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| EVENT HANDLER: Button Clicks & Dragging (OPTIMIZED)              |
//+------------------------------------------------------------------+
void Master_OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   G_Coordinator.OnChartEvent(id, lparam, dparam, sparam);
}

//+------------------------------------------------------------------+
//| HELPER: Save all symbol bank state                               |
//+------------------------------------------------------------------+
void SaveAllBankStates()
{
   if(G_ResetPending) return;

   for(int i = 0; i < ArraySize(SymbolData); i++)
   {
      if(SymbolData[i].active)
         SaveBankState(i);
   }
}

//+------------------------------------------------------------------+
//| HELPER: Persistence for Prune & Crit Banks                       |
//+------------------------------------------------------------------+
struct SBankSaveCache
{
   double lastPrune;
   double lastCrit;
   bool   initialized;
};
static SBankSaveCache g_BankSaveCache[];

void SaveBankState(int idx)
{
   // --- FIX START: BLOCK SAVING DURING RESET ---
   if(G_ResetPending) return;
   // --- FIX END ---
   
   if(idx < 0 || idx >= ArraySize(SymbolData) || !SymbolData[idx].active) return;

   if(idx >= ArraySize(g_BankSaveCache))
      ArrayResize(g_BankSaveCache, idx + 1, 16);

   double curPrune = SymbolData[idx].AccumulatedPruningLoss;
   double curCrit  = SymbolData[idx].AccumulatedCriticalLoss;

   if(g_BankSaveCache[idx].initialized &&
      g_BankSaveCache[idx].lastPrune == curPrune &&
      g_BankSaveCache[idx].lastCrit == curCrit)
   {
      return;
   }

   g_BankSaveCache[idx].lastPrune = curPrune;
   g_BankSaveCache[idx].lastCrit  = curCrit;
   g_BankSaveCache[idx].initialized = true;

   string sym = SymbolData[idx].symbol;
   string pName = StringFormat("MBP_%d_%s_Prune", MagicNumber, sym);
   string cName = StringFormat("MBP_%d_%s_Crit", MagicNumber, sym);
   
   GlobalVariableSet(pName, curPrune);
   GlobalVariableSet(cName, curCrit);
}

void LoadBankState(int idx)
{
   // --- BUG FIX: STOP SAVING DURING RESET ---
   // If a reset is pending, do not write anything to disk.
   if(G_ResetPending) return;
   // -----------------------------------------
   
   if(!SymbolData[idx].active) return;
   string sym = SymbolData[idx].symbol;
   string pName = StringFormat("MBP_%d_%s_Prune", MagicNumber, sym);
   string cName = StringFormat("MBP_%d_%s_Crit", MagicNumber, sym);
   
   // Load if exists, otherwise keep default 0
   if(GlobalVariableCheck(pName)) 
      SymbolData[idx].AccumulatedPruningLoss = GlobalVariableGet(pName);
   if(GlobalVariableCheck(cName)) 
      SymbolData[idx].AccumulatedCriticalLoss = GlobalVariableGet(cName);

   if(idx >= 0 && idx < ArraySize(g_BankSaveCache))
   {
      g_BankSaveCache[idx].lastPrune = SymbolData[idx].AccumulatedPruningLoss;
      g_BankSaveCache[idx].lastCrit = SymbolData[idx].AccumulatedCriticalLoss;
      g_BankSaveCache[idx].initialized = true;
   }
}

void WipeBankState(int idx)
{
   // 1. Clear RAM
   SymbolData[idx].AccumulatedPruningLoss = 0;
   SymbolData[idx].AccumulatedCriticalLoss = 0;

   if(idx >= 0 && idx < ArraySize(g_BankSaveCache))
   {
      g_BankSaveCache[idx].lastPrune = 0.0;
      g_BankSaveCache[idx].lastCrit = 0.0;
      g_BankSaveCache[idx].initialized = true;
   }
   
   // 2. Clear Global Variable Memory (The "Deep Clean")
   string sym = SymbolData[idx].symbol;
   
   // A. New Format (Magic Number Safe)
   string pName = StringFormat("MBP_%d_%s_Prune", MagicNumber, sym);
   string cName = StringFormat("MBP_%d_%s_Crit", MagicNumber, sym);
   
   // B. Legacy Format (Legacy code artifact)
   string legacyName = "Debt_" + sym;
   
   // C. Delete ALL
   if(GlobalVariableCheck(pName)) GlobalVariableDel(pName);
   if(GlobalVariableCheck(cName)) GlobalVariableDel(cName);
   if(GlobalVariableCheck(legacyName)) GlobalVariableDel(legacyName);
   
   if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiBroom(), " Wiped bank state for ", sym, " (RAM and disk).");
}

//+------------------------------------------------------------------+
//| Helper: Perform the Full Reset Sequence (Close -> Wipe -> Unlock)|
//+------------------------------------------------------------------+
void ExecuteFullReset()
{
   StartAsyncControlJob(MBP_CONTROL_JOB_RESET, -1, "Master Reset");
}

// Rebuilds the obfuscated URL at runtime
string GetAuthURL()
  {
   // Example: "https://script.google.com/macros/s/..."
   // Replace these numbers with the ASCII values of your actual Apps Script URL
   uchar secret_url[] = {104, 116, 116, 112, 115, 58, 47, 47, 115, 99, 114, 105, 112, 116, 46, 103, 111, 111, 103, 108, 101, 46, 99, 111, 109, 47, 109, 97, 99, 114, 111, 115, 47, 115, 47, 65, 75, 102, 121, 99, 98, 122, 95, 54, 57, 71, 75, 45, 68, 99, 81, 86, 70, 78, 50, 109, 66, 97, 86, 74, 78, 67, 121, 122, 121, 54, 71, 76, 107, 51, 111, 120, 51, 55, 115, 105, 68, 86, 87, 114, 102, 45, 71, 97, 102, 110, 53, 108, 79, 71, 65, 99, 103, 119, 106, 108, 107, 81, 75, 84, 71, 49, 73, 87, 56, 118, 52, 111, 65, 47, 101, 120, 101, 99}; 
   return CharArrayToString(secret_url);
  }

// Hardware ID Generation (Combines CPU architecture and Terminal Path)
string GetHWID()
  {
   string base_str = TerminalInfoString(TERMINAL_CPU_ARCHITECTURE) + 
                     TerminalInfoString(TERMINAL_DATA_PATH);
   
   // Native custom hash generation
   long hash = 0;
   for(int i = 0; i < StringLen(base_str); i++)
     {
      // Multiply by a prime number (31) and add the ASCII value of the character
      hash = (hash * 31) + StringGetCharacter(base_str, i);
     }
     
   // Return as a positive string number
   return IntegerToString(MathAbs(hash));
  }

#define LICENSE_FAST_CACHE_SECONDS 120
#define LICENSE_RELOAD_GRACE_SECONDS 300

string GetLicenseCacheKey(const long account)
  {
   return "MBP_" + IntegerToString(MagicNumber) + "_" + IntegerToString((int)account) + "_LicenseCache";
  }

string GetLicenseReloadGraceKey(const long account)
  {
   return "MBP_" + IntegerToString(MagicNumber) + "_" + IntegerToString((int)account) + "_LicenseReloadGrace";
  }

bool UseRecentLicenseCache(const long account)
  {
   if(account <= 0)
      return false;

   string key = GetLicenseCacheKey(account);
   if(!GlobalVariableCheck(key))
      return false;

   datetime cached_at = (datetime)GlobalVariableGet(key);
   if(cached_at <= 0)
     {
      GlobalVariableDel(key);
      return false;
     }

   if((TimeCurrent() - cached_at) > LICENSE_FAST_CACHE_SECONDS)
     {
      GlobalVariableDel(key);
      return false;
     }

   G_LicenseValid = true;
   return true;
  }

bool IsHotReloadDeinitReason(const int reason)
  {
   return (reason == REASON_CHARTCHANGE ||
           reason == REASON_PARAMETERS ||
           reason == REASON_TEMPLATE ||
           reason == REASON_RECOMPILE);
  }

bool UseLicenseReloadGrace(const long account)
  {
   if(account <= 0)
      return false;

   string key = GetLicenseReloadGraceKey(account);
   if(!GlobalVariableCheck(key))
      return false;

   datetime cached_at = (datetime)GlobalVariableGet(key);
   if(cached_at <= 0)
     {
      GlobalVariableDel(key);
      return false;
     }

   if((TimeCurrent() - cached_at) > LICENSE_RELOAD_GRACE_SECONDS)
     {
      GlobalVariableDel(key);
      return false;
     }

   G_LicenseValid = true;
   TouchLicenseCache(account);
   if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiLock(), " Reusing verified license during chart reload.");
   return true;
  }

void TouchLicenseCache(const long account)
  {
   if(account <= 0)
      return;

   GlobalVariableSet(GetLicenseCacheKey(account), (double)TimeCurrent());
  }

void TouchLicenseReloadGrace(const long account, const int reason)
  {
   if(account <= 0 || !G_LicenseValid || !IsHotReloadDeinitReason(reason))
      return;

   GlobalVariableSet(GetLicenseReloadGraceKey(account), (double)TimeCurrent());
   TouchLicenseCache(account);
  }

void ClearLicenseCache(const long account)
  {
   if(account <= 0)
      return;

   string key = GetLicenseCacheKey(account);
   if(GlobalVariableCheck(key))
      GlobalVariableDel(key);
  }

bool VerifyLicense()
  {
   G_LicenseExpiredExplicit = false;

   if(IsParallelWorkerMode())
     {
      G_LicenseValid = true;
      return true;
     }

   // --- STRATEGY TESTER BYPASS ---
   if(MQLInfoInteger(MQL_TESTER))
     {
      if(MBP_LogTierEnabled(MBP_LOG_TIER_DEBUG)) Print(EmojiTest(), " Strategy Tester mode detected. Bypassing license verification.");
      G_LicenseValid = true;
      return true;
     }

   // --- CACHE BUSTER FIX ---
   // We append "?cb=" and the current tick count to the URL.
   // This forces MT5 to fetch a fresh Google Redirect token every hour!
   string url = GetAuthURL() + "?cb=" + IntegerToString(GetTickCount());
   
   string cookie = NULL, headers;
   char post[], result[];

   // --- MIDNIGHT ROLLOVER FIX ---
   // We cache the account and HWID in static memory so a brief broker 
   // disconnect never accidentally returns '0' to the security server.
   static long cached_account = 0;
   static string cached_hwid = "";

   if(cached_account == 0)
     {
      cached_account = AccountInfoInteger(ACCOUNT_LOGIN);
      cached_hwid = GetHWID();
     }

   if(UseRecentLicenseCache(cached_account))
      return true;

   if(UseLicenseReloadGrace(cached_account))
      return true;
     
   if(cached_account == 0)
     {
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiWarning(), " Terminal disconnected from the broker. Delaying the background license check.");
      return true; 
     }
   // -----------------------------
   
   // Prepare POST payload
   string post_data = "key=" + InpLicenseKey + "&account=" + IntegerToString(cached_account) + "&hwid=" + cached_hwid;
   StringToCharArray(post_data, post);
   
   // Timeout set to 8000ms. 
   ResetLastError();
   int res = WebRequest("POST", url, cookie, NULL, 8000, post, ArraySize(post), result, headers);
   int webErr = GetLastError();

   if(res == 200)
     {
      string responseStr = CharArrayToString(result);

      // Use our new lightweight parser!
      string status  = ExtractJSONValue(responseStr, "status");
      string message = ExtractJSONValue(responseStr, "message");
      string expires = ExtractJSONValue(responseStr, "expires");
      
      if(status == "valid")
        {
         G_LicenseValid = true;
         G_LicenseExpiredExplicit = false;
         TouchLicenseCache(cached_account);
         if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiLock(), " MultiBotPro license verified. Expires: ", expires);
         return true;
        }
      else if(status == "expired")
        {
         G_LicenseValid = false;
         G_LicenseExpiredExplicit = true;
         ClearLicenseCache(cached_account);
         if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(EmojiWarning(), " Subscription expired: ", message);
         return false;
        }
      else
        {
         G_LicenseValid = false;
         G_LicenseExpiredExplicit = true;
         ClearLicenseCache(cached_account);
         if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(EmojiWarning(), " License error: ", message);
         return false;
        }
     }
   else
     {
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT))
         Print(EmojiWarning(), " License server request failed. HTTP code: ", res, " | Error: ", webErr);

      if(UseLicenseReloadGrace(cached_account))
         return true;

      // Mid-session network tolerance: If already running and verified in this session,
      // a temporary connection/timeout glitch (e.g. error 5203) must not kill the bot or close positions.
      if(G_LicenseValid)
        {
         G_LicenseExpiredExplicit = false;
         if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT))
            Print(EmojiWarning(), " Operating under mid-session network grace period. Retaining active license.");
         return true;
        }

      G_LicenseValid = false;
      G_LicenseExpiredExplicit = false;
      return false;
     }
  }
  
//+------------------------------------------------------------------+
//| Extract a specific value from a flat JSON string                 |
//+------------------------------------------------------------------+
string ExtractJSONValue(string json, string key)
  {
   // Look for the key wrapped in quotes, followed by a colon
   string search_key = "\"" + key + "\":";
   int key_pos = StringFind(json, search_key);
   
   // If the key doesn't exist in the server response, return nothing
   if(key_pos < 0) return ""; 
   
   // Find where the actual value starts
   int val_start = key_pos + StringLen(search_key);
   
   // Skip any formatting spaces between the colon and the value
   while(val_start < StringLen(json) && StringSubstr(json, val_start, 1) == " ")
      val_start++;
      
   string result = "";
   
   // Check if the server sent a string (wrapped in quotes)
   if(StringSubstr(json, val_start, 1) == "\"")
     {
      val_start++; // Skip the opening quote
      int val_end = StringFind(json, "\"", val_start); // Find the closing quote
      if(val_end > val_start)
         result = StringSubstr(json, val_start, val_end - val_start);
     }
   else
     {
      // It's a number or boolean, read until the next comma or closing brace
      int end_comma = StringFind(json, ",", val_start);
      int end_brace = StringFind(json, "}", val_start);
      
      int val_end = end_comma;
      if(val_end < 0 || (end_brace > 0 && end_brace < val_end))
         val_end = end_brace;
         
      if(val_end > val_start)
         result = StringSubstr(json, val_start, val_end - val_start);
     }
     
   // Clean up any stray spaces
   StringTrimLeft(result);
   StringTrimRight(result);
   
   return result;
  }

bool WriteSignal(HedgeSignal &sig)
{
   if(IsBridgeRuntimeEnabled() && InpV3_EnableSQLiteBridge)
   {
      if(V3_InsertSignalRow(InpV3_SQLitePath, InpHedgeChannel, sig))
         return true;
      if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(EmojiWarning(), " SQLite write failed. Falling back to the binary file bridge.");
   }

   string sf = GetSignalFile(InpHedgeChannel);
   int h = FileOpenRobust(sf, FILE_READ|FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(h != INVALID_HANDLE) {
      FileSeek(h, 0, SEEK_END);
      FileWriteStruct(h, sig);
      FileClose(h);
      return true;
   }

    if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(EmojiWarning(), " Bridge signal write failed: could not open the fallback signal file.");
   return false;
}

bool ValidateBridgeSignalForWrite(const HedgeSignal &sig, string &reason)
{
   reason = "";

   string symbol = CharArrayToString(sig.symbol);
   if(sig.ticket == 0)
   {
      reason = "missing_ticket";
      return false;
   }

   if(symbol == "")
   {
      reason = "missing_symbol";
      return false;
   }

   if(sig.action == 1)
   {
      if(sig.type != 0 && sig.type != 1)
      {
         reason = "invalid_side";
         return false;
      }
      if(sig.lots <= 0.0)
      {
         reason = "invalid_lots";
         return false;
      }
      if(sig.sl_dist_points <= 0.0)
      {
         reason = "invalid_sl_distance";
         return false;
      }
      if(sig.risk_money <= 0.0)
      {
         reason = "invalid_risk";
         return false;
      }
      return true;
   }

   if(sig.action == 2)
      return true;

   reason = "unsupported_action";
   return false;
}

void FlushBridgeSignalQueue(const int maxSignals = 16)
{
   int qSize = ArraySize(G_SignalQueue);
   if(qSize <= 0 || maxSignals <= 0)
      return;

   if(!IsBridgeRuntimeEnabled())
   {
      ArrayResize(G_SignalQueue, 0);
      return;
   }

   int processedCount = 0;
   int writeLimit = MathMin(qSize, maxSignals);
   for(int i = 0; i < writeLimit; i++)
   {
      HedgeSignal sig = G_SignalQueue[i];
      string rejectReason = "";
      if(!ValidateBridgeSignalForWrite(sig, rejectReason))
      {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) PrintFormat(EmojiWarning() + " Bridge signal discarded before write: ticket=%I64u action=%d symbol=%s reason=%s lots=%.2f sl_pts=%.2f risk=%.2f",
                     sig.ticket,
                     sig.action,
                     CharArrayToString(sig.symbol),
                     rejectReason,
                     sig.lots,
                     sig.sl_dist_points,
                     sig.risk_money);
         processedCount++;
         continue;
      }

      if(!WriteSignal(sig))
         break;
      processedCount++;
   }

   if(processedCount > 0)
      TrimBridgeSignalQueue(processedCount);
}

bool Master_HasRecentBridgeSignal(const ulong masterTicket, const int action, const int ttlSec = 30)
{
   datetime now = TimeCurrent();
   int writeIdx = 0;
   bool found = false;

   for(int i = 0; i < ArraySize(G_BridgeSignalStamps); i++)
   {
      if((now - G_BridgeSignalStamps[i].seenAt) > ttlSec)
         continue;

      if(writeIdx != i)
         G_BridgeSignalStamps[writeIdx] = G_BridgeSignalStamps[i];

      if(G_BridgeSignalStamps[writeIdx].masterTicket == masterTicket &&
         G_BridgeSignalStamps[writeIdx].action == action)
      {
         found = true;
      }

      writeIdx++;
   }

   if(writeIdx != ArraySize(G_BridgeSignalStamps))
      ArrayResize(G_BridgeSignalStamps, writeIdx);

   return found;
}

void Master_RememberBridgeSignal(const ulong masterTicket, const int action)
{
   int idx = ArraySize(G_BridgeSignalStamps);
   ArrayResize(G_BridgeSignalStamps, idx + 1);
   G_BridgeSignalStamps[idx].masterTicket = masterTicket;
   G_BridgeSignalStamps[idx].action = action;
   G_BridgeSignalStamps[idx].seenAt = TimeCurrent();
}

void TrimBridgeSignalQueue(int processedCount)
{
   int qSize = ArraySize(G_SignalQueue);
   if(processedCount <= 0 || qSize <= 0)
      return;

   if(processedCount >= qSize)
   {
      ArrayResize(G_SignalQueue, 0);
      return;
   }

   for(int i = processedCount; i < qSize; i++)
      G_SignalQueue[i - processedCount] = G_SignalQueue[i];

   ArrayResize(G_SignalQueue, qSize - processedCount);
}

void ProcessBridgeFeedbackRecord(HedgeFeedback &fb, const string feedbackNote)
{
   if(fb.action == 1)
   {
      if(SmartHedge_IsProtectedTicket(fb.master_ticket))
      {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiShield(), " Smart hedge ignored slave kill for protected master ticket #", fb.master_ticket,
               (StringLen(feedbackNote) > 0 ? " | Note: " + feedbackNote : ""));
         return;
      }

      if(PositionSelectByTicket(fb.master_ticket))
      {
         Trade.PositionClose(fb.master_ticket);
         if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiShield(), " Slave commanded kill. Closed master ticket #", fb.master_ticket);
      }
      int cooldownMinutes = (InpV3_PauseCooldownMinutes > 0) ? InpV3_PauseCooldownMinutes : ((AccountLimitCooldownMinutes > 0) ? AccountLimitCooldownMinutes : 2);
      double resumeAt = (double)(TimeCurrent() + (cooldownMinutes * 60));
      GlobalVariableSet(InpHedgeChannel + "_COOLDOWN_TIMER", resumeAt);
      GlobalVariableSet(InpHedgeChannel + "_PAUSE_FLAG", 1.0);
   }
   else if(fb.action == 2)
   {
      if(StringLen(feedbackNote) > 0)
         if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiShield(), " Slave close acknowledged: master ticket #", fb.master_ticket, " | Note: ", feedbackNote);
      else
         if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiShield(), " Slave close acknowledged: master ticket #", fb.master_ticket);
   }
}

void ProcessBridgeFeedbackFileBatch(const string feedbackFile, const int maxItems)
{
   int hf = FileOpenRobust(feedbackFile, FILE_READ|FILE_BIN|FILE_COMMON);
   if(hf == INVALID_HANDLE)
      return;

   HedgeFeedback pending[];
   while(!FileIsEnding(hf))
   {
      HedgeFeedback fb;
      if(FileReadStruct(hf, fb) <= 0)
         break;

      int idx = ArraySize(pending);
      ArrayResize(pending, idx + 1, 32);
      pending[idx] = fb;
   }
   FileClose(hf);

   int total = ArraySize(pending);
   if(total <= 0)
   {
      FileDelete(feedbackFile, FILE_COMMON);
      return;
   }

   int processCount = MathMin(total, maxItems);
   for(int i = 0; i < processCount; i++)
      ProcessBridgeFeedbackRecord(pending[i], "");

   if(processCount >= total)
   {
      FileDelete(feedbackFile, FILE_COMMON);
      return;
   }

   int hw = FileOpenRobust(feedbackFile, FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(hw == INVALID_HANDLE)
      return;

   for(int i = processCount; i < total; i++)
      FileWriteStruct(hw, pending[i]);

   FileClose(hw);
}

void MasterProcessBridgeFeedback()
{
   if(!IsBridgeRuntimeEnabled() || IsParallelWorkerMode())
      return;

   bool sqliteEnabled = V3_RuntimeEnabled(InpV3_EnableSQLiteBridge, InpV3_SQLitePath);
   if(sqliteEnabled)
   {
      long rowId = -1;
      HedgeFeedback fb;
      string note = "";
      while(V3_SelectPendingFeedbackRow(InpV3_SQLitePath, InpHedgeChannel, rowId, fb, note))
      {
         ProcessBridgeFeedbackRecord(fb, note);
         V3_MarkFeedbackConsumed(InpV3_SQLitePath, rowId);
      }
   }

   string feedbackFile = GetFeedbackFile(InpHedgeChannel);
   if(FileIsExist(feedbackFile, FILE_COMMON))
   {
      ProcessBridgeFeedbackFileBatch(feedbackFile, 4);
   }
}

void MasterPublishBridgeState()
{
   if(!IsBridgeRuntimeEnabled() || IsParallelWorkerMode())
      return;

   static ulong lastStatePublishMs = 0;
   ulong nowMs = GetTickCount();
   if(lastStatePublishMs > 0 && (nowMs - lastStatePublishMs) < 250)
      return;
   lastStatePublishMs = nowMs;

   HedgeState state;
   ZeroMemory(state);

   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double totalPnL = currentEquity - MasterStartEquity;
   double dailyPnL = currentEquity - m_day_start_equity;
   SmartHedge_ReconcileProtectedTrades();
   SmartHedge_ApplyPnLAdjustments(totalPnL, dailyPnL);

   double slavePnL = 0.0;
   string slaveFile = GetSlaveFile(InpHedgeChannel);
   if(FileIsExist(slaveFile, FILE_COMMON))
   {
      int hs = FileOpen(slaveFile, FILE_READ|FILE_BIN|FILE_COMMON);
      if(hs != INVALID_HANDLE)
      {
         HedgeState slaveSt;
         ZeroMemory(slaveSt);
         FileReadStruct(hs, slaveSt);
         FileClose(hs);
         slavePnL = slaveSt.slave_pnl;
      }
   }

   state.master_current_equity = currentEquity;
   state.master_start_equity   = MasterStartEquity;
   state.master_pnl            = totalPnL;
   state.master_balance_pnl    = totalPnL;
   state.master_daily_pnl      = dailyPnL;
   state.master_target_risk    = EffectiveMasterRisk;
   state.master_target_profit  = InpMasterTargetProfit;
   state.master_daily_limit    = InpMasterDailyLoss;
   state.master_daily_target   = InpMasterDailyProfit;
   state.slave_target_gain     = InpSlaveGain;
   state.slave_pnl             = slavePnL;
   state.is_daily_stopped      = m_daily_stop_hit;
   state.is_total_stopped      = m_total_stop_hit;
   state.is_paused             = IsPaused;
   state.reset_id              = CurrentResetID;
   state.last_heartbeat        = (ulong)TimeGMT();

   if(InpV3_EnableSQLiteBridge && V3_RuntimeEnabled(InpV3_EnableSQLiteBridge, InpV3_SQLitePath))
      V3_WriteMasterStateRow(InpV3_SQLitePath, InpHedgeChannel, state);

   string masterFile = GetMasterFile(InpHedgeChannel);
   int hMaster = FileOpen(masterFile, FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(hMaster != INVALID_HANDLE)
   {
      FileWriteStruct(hMaster, state);
      FileClose(hMaster);
   }
}

 //+------------------------------------------------------------------+
//| Initiates the Async Handshake and Locks the State Machine        |
//+------------------------------------------------------------------+
bool SendAsyncBridgeProposal(int symbolIndex, int type, double lots, string sym, double riskMoney)
{
   // 1. Prevent overlapping requests (Double-check)
   if(G_BridgePending.active || G_BridgePending.approved) 
   {
      if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(EmojiShield(), " Async handshake blocked: another request is already active.");
       return false;
   }

   // 2. Generate a unique request ID (using TickCount64 for uniqueness)
   ulong mockTicket = GetTickCount64(); 

   // 3. Create the payload (Must match BridgeProposal struct)
   BridgeProposal prop;
   ZeroMemory(prop);
   prop.ticket     = mockTicket;
   prop.lots       = lots;
   prop.type       = type;
   prop.action     = 10; // 10 = Proposal Request
   prop.time_msc   = (long)TimeCurrent();
   prop.risk_money = riskMoney;
   StringToCharArray(sym, prop.symbol);

   // 4. Define file names
   string propFile = GetProposalFile(InpHedgeChannel);
   string repFile  = GetReplyFile(InpHedgeChannel);

   // 5. Write to common file securely
   int h = FileOpenRobust(propFile, FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(h != INVALID_HANDLE) 
   {
      FileWriteStruct(h, prop);
      FileClose(h);
      
      // 6. Lock the Async State Machine
      G_BridgePending.active       = true;
      G_BridgePending.approved     = false;
      G_BridgePending.orderType = (ENUM_ORDER_TYPE)type;
      G_BridgePending.requestId = (long)mockTicket;
      G_BridgePending.symbolIndex  = symbolIndex;
      G_BridgePending.totalLot     = lots;
      G_BridgePending.proposalFile = propFile;
      G_BridgePending.replyFile    = repFile;
      
      // Calculate expiration time (fallback to 3 seconds if input is missing/0)
      int timeoutSecs = (InpV3_HandshakeTimeoutMs > 0) ? (InpV3_HandshakeTimeoutMs / 1000) : 3;
      G_BridgePending.expiresAt    = TimeCurrent() + timeoutSecs; 
      
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiShield(), " Async handshake sent for ", sym, ". State machine locked.");
      return true;
   }
   if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(EmojiWarning(), " Async handshake file write failed.");
   return false;
}

//+------------------------------------------------------------------+
//| SECURITY: Check if Master trades have a running Slave counterpart|
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Unified Runtime Router                                           |
//+------------------------------------------------------------------+
bool IsSlaveModeSelected()
{
   return (BotSystemMode == BOT_MODE_SLAVE);
}

int OnInit()
{
   ChartMode = MBP_DataModeToChartMode(MBP_EffectiveDataMode());
   G_RuntimeRole = ResolveRuntimeRoleForCurrentChart();
   ResetSystemSnapshot();

   // Initialize System State with current account equity
   G_SystemState.SetDayStartEquity(AccountInfoDouble(ACCOUNT_EQUITY));
   G_SystemState.SetHighWaterMark(AccountInfoDouble(ACCOUNT_EQUITY));
   G_SystemState.SetMasterStartEquity(AccountInfoDouble(ACCOUNT_EQUITY));
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   G_SystemState.SetCurrentDayOfYear(dt.day_of_year);

   if(IsSlaveModeSelected())
   {
      SlaveConfig slaveCfg;
      BuildSlaveConfigSnapshot(slaveCfg);
      G_ActiveComputeBackend = COMPUTE_BACKEND_PYTHON;
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiBrain(), " MultiBotPro booting in ", AppModeToText(BotSystemMode),
            " mode | Channel=", slaveCfg.channel);
      return Slave_OnInit();
   }

   MasterConfig masterCfg;
   BuildMasterConfigSnapshot(masterCfg);
   G_ActiveComputeBackend = masterCfg.preferred_backend;
   if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(EmojiBrain(), " MultiBotPro booting in ", AppModeToText(BotSystemMode),
         " | Runtime=", RuntimeRoleToText(G_RuntimeRole),
         " mode | Data=", MBP_DataModeToText(MBP_EffectiveDataMode()),
         " | Backend=", ComputeBackendToText(masterCfg.preferred_backend));
   return Master_OnInit();
}

string AppModeToText(ENUM_BOT_MODE mode)
{
   if(mode == BOT_MODE_STANDALONE) return "STANDALONE";
   if(mode == BOT_MODE_MASTER) return "MASTER";
   if(mode == BOT_MODE_SLAVE) return "SLAVE";
   return "UNKNOWN";
}

string ComputeBackendToText(ENUM_COMPUTE_BACKEND backend)
{
   if(backend == COMPUTE_BACKEND_DLL) return MBP_IsAccelDllCompiled() ? "DLL" : "DLL_DISABLED";
   if(backend == COMPUTE_BACKEND_PYTHON) return "PYTHON";
   if(backend == COMPUTE_BACKEND_NATIVE) return "NATIVE";
   return "UNKNOWN";
}

void OnDeinit(const int reason)
{
   TouchLicenseReloadGrace((long)AccountInfoInteger(ACCOUNT_LOGIN), reason);

   if(IsSlaveModeSelected())
      Slave_OnDeinit(reason);
   else
      Master_OnDeinit(reason);
}

void OnTimer()
{
   if(G_InitInProgress || G_IS_DEINIT || IsStopped())
      return;

   if(G_InTimerCycle)
      return;

   G_InTimerCycle = true;

   if(IsSlaveModeSelected())
   {
      RefreshSystemSnapshot(false, true, false, false, "");
      Slave_OnTimer();
   }
   else
   {
      Master_OnTimer();
   }

   G_InTimerCycle = false;
}

void OnTick()
{
   if(G_InitInProgress || G_IS_DEINIT || IsStopped())
      return;

   if(IsSlaveModeSelected())
      Slave_OnTick();
   else
      Master_OnTick();
}

void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
{
   if(G_InitInProgress || G_IS_DEINIT || IsStopped())
      return;

   if(IsSlaveModeSelected())
      Slave_OnTradeTransaction(trans, request, result);
   else
      Master_OnTradeTransaction(trans, request, result);
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(G_InitInProgress || G_IS_DEINIT || IsStopped())
      return;

   if(IsSlaveModeSelected())
      Slave_OnChartEvent(id, lparam, dparam, sparam);
   else
      Master_OnChartEvent(id, lparam, dparam, sparam);
}

// --- Telemetry Stubs (Ported/Restored) ---
void ResetSystemSnapshot() { /* Telemetry Init */ }
void RefreshSystemSnapshot(bool a, bool b, bool c, bool d, string e) { /* Telemetry Refresh */ }

void TouchMasterAnalysisEngineOnTimer()
{
   // Runtime/timer services are now pumped exclusively from Master_OnTimer()
   // to avoid bursty double-processing and UI starvation.
}

bool InitializeMasterAnalysisEngine()
{
   return (Master_OnInit_Runtime() == INIT_SUCCEEDED);
}


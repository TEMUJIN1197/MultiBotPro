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
#resource "romeo.bmp"
#resource "romeo_panel.bmp"
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
ulong  G_LastShadowSyncCheck = 0;
ulong  G_LastShadowSupervisorCheckMs = 0;
ulong  G_LastShadowRuntimeWriteMs = 0;
ulong  G_LastShadowLaunchAttemptMs = 0;
string G_LastShadowRuntimeSignature = "";

// Add these two new globals:
bool   G_Cache_IsDailyCloseBlock = false;
bool   G_SLTP_Hidden = false;

bool   G_IS_DEINIT = false;
bool   G_InitInProgress = false;
int    G_NextBasketId = 1;

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
ENUM_COMPUTE_BACKEND G_ActiveComputeBackend = COMPUTE_BACKEND_DLL;
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
ulong G_LastWorkerHeartbeatPublishMs = 0;
ulong G_LastWorkerEnsureMs = 0;
ulong G_LastWorkerTemplateSaveMs = 0;
bool  G_WorkerBootstrapCompleted = false;
string G_LastWorkerTemplateSignature = "";
string G_RuntimeCoordinatorKey = "";
string G_RuntimeAssignedWorkerSymbol = "";
string G_RuntimeAssignedChartSymbol = "";
string G_RuntimeAssignedSymbolsCsv = "";
string G_RuntimeAssignedWorkerSignature = "";
string G_RuntimeAssignedSymbols[];

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
   MBP_UI_CMD_CLOSE_SYMBOL
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
void WriteActiveTrades();
void CheckSlaveConnection();
void CheckMasterOrphans();
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
void MasterPumpTimerServices();
int  Master_OnInit_Runtime();
void ShutdownMasterRuntime();
void EnsureMasterDashboardReady(const bool forceRebuild = false);
void ResetDashboardHeartbeat();
void UpdateDashboard(long chart_id);
void CreateDashboard();
void DestroyDashboard();
void InitReferenceEquity();
void WipeBankState(int idx);
string ShadowMaster_BuildRuntimeConfigJson();
string ShadowMaster_BuildRuntimeSignature();
bool ShadowMaster_WriteRuntimeConfig(const bool forceWrite = false);
bool ShadowMaster_ReadHeartbeat(datetime &outHeartbeat, string &outState);
bool ShadowMaster_IsAiRuntimeEnabled();
void ShadowMaster_Supervise(const bool forceLaunch = false);
ENUM_MBP_RUNTIME_ROLE ResolveRuntimeRoleForCurrentChart();
string MBP_SanitizeRuntimeToken(string value);
string MBP_DefaultCoordinatorKey();
string MBP_GetActiveCoordinatorKey();
bool IsParallelLegacyMode();
bool IsParallelCoordinatorMode();
bool IsParallelWorkerMode();
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
void SaveFastChartSwitchDashboardState();
void RestoreFastChartSwitchDashboardState();

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+

// === 00. RUNTIME, DATA & BACKEND ===
input group "=== 00. Runtime, Data & Backend ==="
input ENUM_BOT_MODE BotSystemMode = BOT_MODE_STANDALONE; // Bot role
input bool InpAutoSpawnWorkerCharts = true; // Deprecated: runtime auto-resolves
input int InpParallelMaxWorkerCharts = 8; // Max worker charts (overflow stays on last worker)
input ENUM_MBP_DATA_MODE InpDataMode = MBP_DATA_LIVE; // Price engine
input ENUM_COMPUTE_BACKEND InpPrimaryComputeBackend = COMPUTE_BACKEND_DLL; // Primary compute backend
input bool InpAutoFailoverToPython = true; // Auto fallback to Python
input int InpParallelWorkerHeartbeatMs = 1000; // Worker state publish cadence (ms)

input group "=== 00A. Synthetic Chart Engines ==="
sinput string DIV_DATA_CUSTOM_TIME = "--- Custom Time Bars ---";
input int    InpCustomTimeValue = 45; // Bar interval value
input bool   InpCustomTimeUseSeconds = true; // Use seconds instead of minutes
input int    InpCustomTimeHistoryDays = 5; // History lookback (days)
input string InpCustomTimeSuffix = "CT"; // Custom symbol suffix

sinput string DIV_DATA_RENKO_CORE = "--- Renko Core ---";
input ENUM_BLOCK_MODE InpRenkoBlockMode = BLOCK_MODE_ATR_PERCENT; // Brick size mode
input double InpRenkoBlockValue = 2; // Brick size value
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
input int    InpRenkoHistoryDays = 5; // History lookback (days)
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

input group "=== 00B. Slave Mode ==="
sinput string DIV_SLAVE_CORE = "--- Slave Core ---";
input string Slave_InpChannelName = "HEDGE_A"; // Channel name
input string Slave_InpSymbolMap = ""; // Symbol map
input int    Slave_InpHeartbeat = 50; // Heartbeat (ms)
input long   Slave_InpSlaveMagic = 123456; // Slave magic number
input int    Slave_FailsafeTimeoutSeconds = 30; // Failsafe timeout (s)

sinput string DIV_SLAVE_TIME = "--- Slave Timezone ---";
input int    Slave_InpNYManualShift = 2; // New York manual shift

sinput string DIV_SLAVE_SQLITE = "--- Slave Bridge Runtime ---";
input bool   Slave_InpBridgeEnabled = true; // Enable slave bridge
input bool   Slave_InpV3_EnableSQLiteBridge = true; // Use SQLite bridge
input bool   Slave_InpV3_EnableFileFallback = true; // Allow file fallback
input string Slave_InpV3_SQLitePath = "MultiBotPro_v3.db"; // SQLite file name
input int    Slave_InpV3_HeartbeatIntervalMs = 1000; // SQLite heartbeat (ms)

sinput string DIV_SLAVE_HEDGE = "--- Slave Hedge Model ---";
input double Slave_InpEstCommCost = 8.0; // Estimated commission
input bool   Slave_InpEnableLateStageSingleSymbolLock = false; // Late-stage symbol lock
input int    Slave_InpMaxConcurrentSymbols = 0; // Max concurrent slave symbols (0 = unlimited)

input group "=== 01. Security & License ==="
input string InpLicenseKey = "ENTER_YOUR_KEY"; // License key

input group "=== 02. Symbols, Timeframes & Execution ==="
sinput string DIV_SYMBOLS = "--- Symbol Universe ---";
input string ManualSymbols = ""; // Manual symbol list
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

sinput string DIV_TRADE_OPS = "--- Trade Metadata ---";
input int    MagicNumber          = 12345; // Magic number
input string TradeComment         = "MultiBotPro"; // Order comment
input int    Slippage             = 3; // Max slippage (points)
input bool   ReverseStrategy      = false; // Reverse buy and sell signals

sinput string DIV_SIGNAL_OPS = "--- Signal Timing ---";
input bool   InpProcessSignalsPerBar = false; // Process once per bar

input group "=== 03. Multi-Basket Entries ==="
sinput string DIV_MULTI_BASKET = "--- Basket Controls ---";
input bool   InpEnableMultiBaskets = false; // Enable multiple baskets
input int    InpMaxBasketsPerSymbol = 1; // Max baskets per symbol
input double InpMinBasketDistanceATR = 1.0; // Min ATR spacing between baskets
input ENUM_BASKET_DIR_POLICY InpBasketDirectionPolicy = BASKET_DIR_BOTH; // Basket direction policy

input group "=== 04. Position Sizing & Risk ==="
sinput string DIV_BASE_RISK = "--- Primary Risk Model ---";
input ENUM_RISK_TYPE RiskType     = RISK_FIXED_MONEY;  // Risk model
input double RiskPercent          = 2; // Risk percent
input double FixedLot             = 0.01; // Fixed lot size
input double RiskMoney            = 50.0; // Fixed money risk

sinput string DIV_SAFETY_CAPS = "--- Safety Caps ---";
input double MaxLotSizePerTrade   = 50; // Max lot per trade
input int    MaxSplitTrades       = 10; // Max split orders
input double MaxSpreadATR         = 0.5; // Max spread (xATR, 0 = off)

input group "=== 05. Exits, Stops & Trailing ==="
sinput string DIV_SL_MAIN = "--- Stop Loss Core ---";
input ENUM_SL_TYPE StopLossType   = SL_ATR; // Stop-loss model
input ENUM_TIMEFRAMES ATR_Timeframe = PERIOD_CURRENT; // Stop-loss ATR timeframe

sinput string DIV_TP = "--- Take Profit ---";
input ENUM_TP_TYPE TakeProfitType = TP_ATR; // Take-profit model
input double TP_Ratio             = 1.5; // Risk/reward ratio
input double FixedTP              = 100; // Fixed take profit (points)
input double TP_ATR_Multiplier    = 5; // ATR take-profit multiplier

sinput string DIV_SL_ATR = "--- ATR Stop ---";
input int    ATR_Period           = 100; // ATR period
input double ATR_Multiplier       = 5; // ATR multiplier

sinput string DIV_SL_BOX = "--- Box Pivot Stop ---";
input int    Box_Lookback         = 2; // Pivot lookback
input int    Box_SL_Levels        = 2; // Box levels to keep
input ENUM_BOX_BREAKOUT_SRC BoxBreakoutMethod = BOX_BREAK_HIGHLOW; // Box breakout source

sinput string DIV_SL_MA = "--- Moving Average Stop ---";
input int    MA_SL_Period         = 20; // Stop MA period
input ENUM_MY_MA_METHOD MA_SL_Method = MY_MODE_EMA; // Stop MA method
input ENUM_MY_MA_SOURCE MA_SL_Source = MY_SRC_CLOSE; // Stop MA source

sinput string DIV_TRAIL_STOP = "--- Trailing Stop ---";
input bool   UseTrailing          = false; // Enable trailing stop
input ENUM_TRAIL_TYPE TrailType   = TRAIL_ATR; // Trailing model
input int    TrailBox_Levels      = 6; // Trail box levels
input double TrailATR_Multiplier  = 1; // Trail ATR multiplier
input double TrailATR_Update      = 2; // Trail update distance
input ENUM_LOCK_TRAIL LockTrail   = LOCK_TRAIL_TP_HIT; // Lock trailing until

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

sinput string DIV_MACRO = "--- Currency Strength ---";
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

input group "=== 07. VWAP Strategy ==="
sinput string DIV_VWAP_MAIN = "--- Global VWAP Logic ---";
input bool   UseVWAP              = false; // Enable VWAP signals
input bool   RequireVWAPConfirmation = true; // Require VWAP confirmation

sinput string DIV_VWAP_CONT = "--- Continuous VWAP ---";
input bool   UseVWAP1             = true; // Enable continuous VWAP
input ENUM_APPLIED_PRICE VWAP1_PriceSource = PRICE_TYPICAL; // Continuous VWAP price source
input int    VWAP1_ResetHour      = 18; // Reset hour (NY)
input int    VWAP1_ResetMinute    = 0; // Reset minute (NY)

sinput string DIV_VWAP_ANCH = "--- Anchored VWAP ---";
input bool   UseVWAP2             = true; // Enable anchored VWAP
input ENUM_APPLIED_PRICE VH_Source = PRICE_HIGH; // High anchor source
input ENUM_APPLIED_PRICE VL_Source = PRICE_LOW; // Low anchor source

sinput string DIV_VWAP_SESS = "--- Session VWAP ---";
input bool   UseVWAP3             = false; // Enable session VWAP
input ENUM_APPLIED_PRICE VWAP3_PriceSource = PRICE_TYPICAL; // Session VWAP price source
input int    VWAP3_StartHour      = 9; // Session start hour (NY)
input int    VWAP3_StartMinute    = 30; // Session start minute (NY)

input group "=== 08. Opening Range Reversal ==="
sinput string DIV_OR_REVERSAL = "--- OR Reversal ---";
input bool   UseORReversal        = false; // Enable OR reversal
input ENUM_TIMEFRAMES OR_EntryTF  = PERIOD_M5; // Entry timeframe
input int    OR_StartHour         = 9; // Start hour (NY)
input int    OR_StartMinute       = 30; // Start minute (NY)
input int    OR_WindowMinutes     = 60; // Trading window (minutes)
input double OR_ATR_Threshold     = 0.20; // Min range vs daily ATR

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

sinput string DIV_DAYS = "--- Trading Days ---";
input bool   TradeMonday          = true; // Monday
input bool   TradeTuesday         = true; // Tuesday
input bool   TradeWednesday       = true; // Wednesday
input bool   TradeThursday        = true; // Thursday
input bool   TradeFriday          = true; // Friday
input bool   TradeSaturday        = true; // Saturday
input bool   TradeSunday          = true; // Sunday

sinput string DIV_HARD_STOPS = "--- Hard Stop Windows ---";
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

sinput string DIV_NEWS_MAIN = "--- News Filter ---";
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
input color  NewsColorHigh        = clrRed; // High-impact color
input color  NewsColorMed         = clrOrange; // Medium-impact color
input color  NewsColorLow         = clrYellow; // Low-impact color
input color  NewsColorHoliday     = clrWhite; // Holiday color
input ENUM_LINE_STYLE NewsLineStyle = STYLE_DASHDOTDOT; // News line style
input bool   NewsWindowColorEnable = true; // Tint chart during news window
input color  NewsWindowColor      = clrMagenta; // News window color

input group "=== 10. Recovery, Grid & Stacking ==="
sinput string DIV_GRID_CORE = "--- Grid / Zone Core ---";
input ENUM_RISK_MODE RiskMode     = RISK_MODE_NONE;    // Recovery mode
input ENUM_GRID_STRATEGY GridStrategy = GRID_STRAT_AGGRESSIVE; // Grid strategy
input bool   UseDynamicProfitScaling = true;           // Dynamic profit scaling
input double GridTP_Amount        = 2; // Grid target profit ($)
input double GridImpulseATR       = 2; // Phase 1 distance (ATR)
input double GridTransitionDist   = 1; // Phase 2 distance (ATR)

sinput string DIV_GRID_AGGR = "--- Aggressive Grid ---";
input ENUM_GRID_DISTANCE_TYPE GridAggressiveDistType = GRID_DIST_ATR; // Distance unit
input double GridAggressiveRecovDist = 2; // Base recovery distance
input double GridAggressiveRecovMult = 1.5; // Distance multiplier

sinput string DIV_GRID_CONS = "--- Conservative Grid ---";
input ENUM_GRID_DISTANCE_TYPE GridTransitionType = GRID_DIST_ATR; // Transition distance unit
input double GridStakeMultiplier  = 2; // Stake multiplier per level
input int    GridStakeStartLevel  = 1; // Stake start level
input double GridMaxStake         = 0; // Max stake (0 = no limit)

sinput string DIV_GRID_DIST = "--- Grid Spacing ---";
input ENUM_GRID_DISTANCE_TYPE GridDistanceType = GRID_DIST_ATR; // Grid spacing unit
input double GridDistance         = 4; // Base grid spacing
input double GridMultiplier       = 1.5; // Grid spacing multiplier
input int    GridDistanceStartLevel = 1; // Distance multiplier start level
input double MinGridDistance      = 20; // Min grid spacing (points)
input double MaxGridDistance      = 20000; // Max grid spacing (points)

sinput string DIV_GRID_LOTS = "--- Grid Lot Sizing ---";
input bool   UseGridLotPerEquity  = true; // Use lot-per-equity model
input double GridLot_Per_Equity_Size = 0.01; // Lots per balance step
input double GridLot_Per_Equity_Step = 10000; // Balance step size
input ENUM_RISK_TYPE GridRiskType = RISK_PERCENT_EQUITY; // Fallback risk model
input double GridRiskPercent      = 0.2; // Fallback risk percent
input double GridFixedLot         = 0.01; // Fallback fixed lot
input bool   GridCloseOnTP        = false; // Close grid at target

sinput string DIV_ZONE_RECOV = "--- Zone Recovery ---";
input ENUM_ZONE_GAP_TYPE ZoneGapType = ZONE_GAP_ATR; // Zone gap unit
input double ZoneTP_Amount        = 2; // Zone target profit ($)
input double ZoneGapPoints        = 50; // Zone gap (points)
input double ZoneGapATR           = 5; // Zone gap (ATR)
input double ZoneTargetMult       = 2; // Target distance multiplier
input double ZoneImpulseATR       = 2; // Phase 1 distance (ATR)
input double ZoneTransitionDist   = 2; // Phase 2 distance (ATR)
input bool   ZoneCloseOnTP        = false; // Close zone at target

sinput string DIV_DYN_STAKE = "--- Dynamic Staking ---";
input bool   UseDynamicStake      = false; // Enable dynamic stake sizing
input double EquityThreshold      = 2; // Equity change threshold (%)
input double StakeMultiplier      = 2; // Stake multiplier
input double MaxStakeMultiplier   = 20; // Max stake multiplier
input double lotCap               = 50; // Lot cap multiplier

sinput string DIV_STACK_MODE = "--- Stack Mode ---";
input bool   StackMode            = false; // Enable stack mode
input int    StackStart           = 1; // Stack start level
input double StackInitial         = 1; // Initial stack multiplier
input double StackBoost           = 0.25; // Stack boost per level
input double MinStackMultiplier   = 0.1; // Min stack multiplier
input double MaxStackMultiplier   = 64; // Max stack multiplier

input group "=== 11. Grid Pruning (FIFO) ==="
sinput string DIV_PRUNE_CORE = "--- Pruning ---";
input bool   UseGridPruning       = false; // Enable pruning
input ENUM_PRUNING_STYLE PruningStyle = PRUNING_SOFT; // Pruning style
input int    PruningLevel         = 5; // Start pruning after level
input bool   UsePruningRecovery   = false; // Recover pruned losses
input double PruningRecovPercent  = 25.0; // Recovery percent per cycle

input group "=== 12. Circuit Breakers & Limits ==="
sinput string DIV_PERF_FILTER = "--- Performance Breakers ---";
input ENUM_FILTER_RESET FilterResetMode = FILTER_RESET_DAILY; // Counter reset mode
input int    Filter_MaxOpenTrades = 0; // Max open trades
input bool   Filter_GlobalTradeCount = false; // Use global trade count
input int    Filter_MaxWins       = 0; // Max wins
input int    Filter_MaxLosses     = 0; // Max losses
input int    Filter_MaxWinStreak  = 0; // Max win streak
input int    Filter_MaxLossStreak = 0; // Max loss streak
input double Filter_MaxPctLoss    = 0; // Max session loss (%)
input double Filter_MaxPctGain    = 0; // Max session gain (%)
input int    Filter_BlockWins     = 0; // Max wins per block
input int    Filter_BlockLosses   = 0; // Max losses per block

sinput string DIV_MONEY_LIMITS = "--- Hard Money Limits ---";
input double GlobalTP_Amount      = 0; // Global take profit ($)
input double GlobalSL_Amount      = 0; // Global stop loss ($)
input bool   UseAccountLimits     = true; // Enable equity limits
input double AccountProfitLimitPct = 1; // Account profit cap (%)
input double AccountLossLimitPct  = 2.5; // Account loss cap (%)
input bool   RestartAfterLimit    = true; // Restart after limit hit
input int    AccountLimitCooldownMinutes = 2; // Cooldown (minutes)

input group "=== 13. Engine, Bridge & Integrations ==="
sinput string DIV_OP_MODE = "--- Core Engine ---";
input ENUM_OP_MODE OperationMode = MODE_MIXED; // Operation mode
input bool ForceTimerExecution = false; // Force timer-driven execution
#define InpCustomTimeSeconds ((InpCustomTimeUseSeconds) ? (InpCustomTimeValue) : ((InpCustomTimeValue) * 60))
#define InpHeikenRenkoPoints InpHeikenRenkoBlockSizePoints
#define InpShowSyntheticVisuals false
#define InpCustomNameTag ""

sinput string DIV_TIMEZONE = "--- Timezone ---";
input int InpServerGMTOffset  = 2; // Server GMT offset
input int InpNYManualShift    = 0; // New York manual shift

sinput string DIV_BRIDGE_COMMS = "--- Bridge Channels ---";
input bool   InpEnableBridge      = true; // Enable bridge mode
input bool   InpUseHedgeBridge    = true; // Use hedge bridge checks
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

sinput string DIV_HEDGE_MAIN = "--- Master Risk Limits ---";
input ENUM_RISK_MODE_MASTER InpMasterRiskMode = RISK_TRAILING; // Master risk mode
input double   InpMasterRisk       = 1000.0; // Max master risk
input double   InpMasterTargetProfit = 800.0; // Master target profit
input double   InpMasterDailyLoss  = 300.0; // Daily loss limit
input double   InpMasterDailyProfit= 400.0; // Daily profit target
input double   InpStartingBalance  = 5000; // Starting balance (0 = auto)
input double   InpSlaveGain        = 100.0; // Slave gain target

sinput string DIV_HEDGE_TRAIL = "--- Master Trailing ---";
input double   InpTrailPercent     = 10.0; // Trailing percent
input ENUM_TRAIL_BASE InpTrailBase = TRAIL_EQUITY; // Trailing base
input bool     InpEnableSmartHedge = false; // Release slave hedge after second protected SL move

sinput string DIV_SHADOW_AI = "--- Shadow AI ---";
input bool   InpEnableShadowMaster = true; // Enable Shadow Master
input int    InpShadowMasterCycleHours = 6; // Shadow refresh interval (hours)
input string InpShadowConfigName   = "ShadowConfig"; // Shadow config prefix

input group "=== 14. Visuals, UX & Defensive Filters ==="
sinput string DIV_DASHBOARD = "--- Dashboard & Synthetic Refresh ---";
input bool   ShowDashboard        = true; // Show dashboard
input bool   InpLiveDragging      = false; // Live drag dashboard
input int    InpSyntheticPumpIntervalMs = 100; // Synthetic update cadence (ms, 0 = every cycle)
input bool   ShowBoxLines         = true; // Show box lines
input int    BoxLines_History     = 200; // Box-line history bars
input color  BoxLines_ColorHigh   = clrGreen; // High box-line color
input color  BoxLines_ColorLow    = clrRed; // Low box-line color
input int    BoxLines_Width       = 1; // Box-line width
input ENUM_LINE_STYLE BoxLines_Style = STYLE_DASHDOTDOT; // Box-line style

sinput string DIV_INDICATOR_VISUALS = "--- Indicator Overlays ---";
input bool   InpShowIndicatorOverlay = true; // Show indicator overlay
input bool   InpOverlayUseChartSymbol = true; // Overlay source uses chart symbol
input bool   InpShowMA1Overlay      = false; // Show MA1 overlay
input color  InpMA1OverlayColor     = clrLime; // MA1 color
input ENUM_LINE_STYLE InpMA1OverlayStyle = STYLE_SOLID; // MA1 style
input int    InpMA1OverlayWidth     = 1; // MA1 width
input bool   InpShowMA2Overlay      = false; // Show MA2 overlay
input color  InpMA2OverlayColor     = clrGreen; // MA2 color
input ENUM_LINE_STYLE InpMA2OverlayStyle = STYLE_SOLID; // MA2 style
input int    InpMA2OverlayWidth     = 1; // MA2 width
input bool   InpShowMA3Overlay      = true; // Show MA3 overlay
input color  InpMA3OverlayColor     = clrBlue; // MA3 color
input ENUM_LINE_STYLE InpMA3OverlayStyle = STYLE_SOLID; // MA3 style
input int    InpMA3OverlayWidth     = 1; // MA3 width
input bool   InpShowMA4Overlay      = true; // Show MA4 overlay
input color  InpMA4OverlayColor     = clrOliveDrab; // MA4 color
input ENUM_LINE_STYLE InpMA4OverlayStyle = STYLE_SOLID; // MA4 style
input int    InpMA4OverlayWidth     = 2; // MA4 width
input bool   InpShowMA5Overlay      = false; // Show MA5 overlay
input color  InpMA5OverlayColor     = clrRed; // MA5 color
input ENUM_LINE_STYLE InpMA5OverlayStyle = STYLE_SOLID; // MA5 style
input int    InpMA5OverlayWidth     = 2; // MA5 width
input bool   InpShowVWAP1Overlay    = false; // Show VWAP1 overlay
input color  InpVWAP1OverlayColor   = clrAqua; // VWAP1 color
input ENUM_LINE_STYLE InpVWAP1OverlayStyle = STYLE_DASHDOT; // VWAP1 style
input int    InpVWAP1OverlayWidth   = 2; // VWAP1 width
input bool   InpShowVWAP3Overlay    = true; // Show VWAP3 overlay
input color  InpVWAP3OverlayColor   = clrGold; // VWAP3 color
input ENUM_LINE_STYLE InpVWAP3OverlayStyle = STYLE_SOLID; // VWAP3 style
input int    InpVWAP3OverlayWidth   = 2; // VWAP3 width
input bool   InpShowVWAPHighOverlay = true; // Show high VWAP overlay
input color  InpVWAPHighOverlayColor = clrMagenta; // High VWAP color
input ENUM_LINE_STYLE InpVWAPHighOverlayStyle = STYLE_DOT; // High VWAP style
input int    InpVWAPHighOverlayWidth = 1; // High VWAP width
input bool   InpShowVWAPLowOverlay  = true; // Show low VWAP overlay
input color  InpVWAPLowOverlayColor = clrMagenta; // Low VWAP color
input ENUM_LINE_STYLE InpVWAPLowOverlayStyle = STYLE_DOT; // Low VWAP style
input int    InpVWAPLowOverlayWidth = 1; // Low VWAP width
input bool   InpShowVWAPCloud       = false; // Show VWAP cloud
input color  InpVWAPCloudColor      = clrAliceBlue; // VWAP cloud color
input bool   InpShowIndicatorOverlayLabels = true; // Show overlay labels
input int    InpIndicatorOverlayLabelOffsetPts = 100; // Label offset (points)
input int    InpIndicatorOverlayLabelShiftBars = 3; // Label shift (bars)
input int    InpIndicatorOverlayLabelFontSize = 9; // Label font size

sinput string DIV_NOTIFICATIONS = "--- Notifications ---";
input bool   EnableAlerts         = true; // Popup alerts
input bool   EnableEmailAlerts    = true; // Email alerts
input bool   EnablePushAlerts     = true; // Push alerts

sinput string VELOCITY_PAUSE      = "--- Velocity Pause ---";
input bool   InpUseVelocityPause  = false; // Enable velocity pause
input int    InpVelocityTicksPerSec = 80; // Pause trigger (ticks/sec)
input int    InpVelocityPauseSeconds = 10; // Pause length (seconds)

sinput string FRACTAL_GRID        = "--- Fractal Elastic Grid ---";
input bool   InpUseFractalGrid    = false; // Enable fractal grid
input int    InpHurstPeriod       = 30; // Hurst lookback
input double InpHurstTrendingThreshold = 0.60; // Trending threshold
input double InpHurstRangingThreshold  = 0.40; // Ranging threshold
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

bool IsBridgeRuntimeEnabled()
{
   return (BotSystemMode != BOT_MODE_STANDALONE) && InpEnableBridge;
}

string ResolveManagedAnalysisSymbol(const int symbolIndex)
{
   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return "";

   if(SymbolData[symbolIndex].AnalysisSymbol != "")
      return SymbolData[symbolIndex].AnalysisSymbol;

   if(SymbolData[symbolIndex].symbol != "")
      return SymbolData[symbolIndex].symbol;

   return SymbolData[symbolIndex].BaseSymbol;
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
         Print("Dashboard core objects missing on the EA chart. Recreating dashboard.");

      DestroyDashboard();
      CreateDashboard();
   }

   UpdateDashboard(0);
   ChartRedraw(0);
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


// 2. INCLUDE DASHBOARD ELEMENTS
#include "MultiBotPro_SymbolContext.mqh"
#include "MultiBotPro_BundleHelpers.mqh"
#include "MultiBotPro_PythonBridge.mqh"
#include "MultiBotPro_Dashboard.mqh"
#include "MultiBotPro_Helpers.mqh"
#include "MultiBotPro_Indicators.mqh"
#include "MultiBotPro_VisualOverlay.mqh"
#include "MultiBotPro_Risk.mqh"
#include "MultiBotPro_TradeEntry.mqh"
#include "MultiBotPro_GridZone.mqh"
#include "MultiBotPro_GUI.mqh"
// #include "MultiBotPro_ServiceManager.mqh" // REMOVED
// #include "MultiBotPro_AnalysisEngine.mqh" // REMOVED
#include "MultiBotPro_MasterRuntime.mqh"
// #include "MultiBotPro_SlaveRuntime.mqh"   // REMOVED
#include "MultiBotPro_ChartFactory.mqh"
#include "MultiBotPro_Renko.mqh"
#include "MultiBotPro_HeikenRenko.mqh"
#include "MultiBotPro_HeikenAshi.mqh"
#include "MultiBotPro_CustomTime.mqh"

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
   return StringFormat("%s_%I64d",
                       MBP_SanitizeRuntimeToken(InpHedgeChannel),
                       ChartID());
}

string MBP_GetActiveCoordinatorKey()
{
   if(G_RuntimeCoordinatorKey != "")
      return G_RuntimeCoordinatorKey;

   return MBP_DefaultCoordinatorKey();
}

string ShadowMaster_GetRuntimeConfigPath()
{
   return MBP_GetTerminalFilesPath() + "\\runtime_v3.json";
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

bool MBP_WaitForChartTargetReady(const long chartId,
                                 const string expectedSymbol,
                                 const uint timeoutMs = 4000)
{
   if(chartId <= 0)
      return false;

   ulong startMs = GetTickCount();
   while((GetTickCount() - startMs) <= timeoutMs)
   {
      if(MBP_IsChartAlive(chartId))
      {
         string chartSymbol = ChartSymbol(chartId);
         if(expectedSymbol == "" || StringCompare(chartSymbol, expectedSymbol, false) == 0)
            return true;
      }

      Sleep(100);
   }

   return false;
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

   int handle = FileOpen(MBP_WorkerHeartbeatFile(workerSymbol, coordinatorKey), FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(handle == INVALID_HANDLE)
      return false;

   FileWriteString(handle, "symbol=" + workerSymbol + "\r\n");
   if(assignedChartSymbol != "")
      FileWriteString(handle, "chart_symbol=" + assignedChartSymbol + "\r\n");
   if(assignedSymbolsCsv != "")
      FileWriteString(handle, "symbols=" + assignedSymbolsCsv + "\r\n");
   if(assignmentSignature != "")
      FileWriteString(handle, "signature=" + assignmentSignature + "\r\n");
   FileWriteString(handle, StringFormat("chart_id=%I64d\r\n", chartId));
   FileWriteString(handle, "heartbeat=" + IntegerToString((int)((heartbeatTime > 0) ? heartbeatTime : TimeCurrent())) + "\r\n");
   FileWriteString(handle, "state=" + state + "\r\n");
   FileWriteString(handle, "positions=" + IntegerToString(MathMax(0, linkedPositions)) + "\r\n");
   FileWriteString(handle, "role=WORKER\r\n");
   FileClose(handle);
   return true;
}

bool MBP_ShouldPreserveWorkerHeartbeatOnDeinit(const int reason)
{
   return (reason == REASON_TEMPLATE ||
           reason == REASON_PARAMETERS ||
           reason == REASON_CHARTCHANGE ||
           reason == REASON_RECOMPILE);
}

long MBP_FindReusableChartBySymbol(const string symbol, const long excludedChartId = 0)
{
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
         if(!MBP_ReadWorkerAssignment(chartId,
                                      assignedSymbol,
                                      assignedSymbolsCsv,
                                      assignedChartSymbol,
                                      assignedCoordinatorKey,
                                      assignedCoordinatorChartId,
                                      assignedSignature,
                                      assignedAt))
         {
            return chartId;
         }
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
         string assignedSignature = "";
         datetime assignedAt = 0;
         if(MBP_ReadWorkerAssignment(chartId,
                                     assignedSymbol,
                                     assignedSymbolsCsv,
                                     assignedChartSymbol,
                                     assignedCoordinatorKey,
                                     assignedCoordinatorChartId,
                                     assignedSignature,
                                     assignedAt))
         {
            string assignedBase = GetBaseSymbol(assignedSymbol);
            if(assignedBase == "")
               assignedBase = assignedSymbol;

            bool coordinatorMatches = (coordinatorKey == "" ||
                                       assignedCoordinatorKey == "" ||
                                       StringCompare(assignedCoordinatorKey, coordinatorKey, false) == 0);
            int rank = -1;
            if(coordinatorMatches && assignmentSignature != "" &&
               assignedSignature != "" &&
               StringCompare(assignedSignature, assignmentSignature, false) == 0)
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
         string assignedSignature = "";
         datetime assignedAt = 0;
         if(MBP_ReadWorkerAssignment(chartId,
                                     assignedSymbol,
                                     assignedSymbolsCsv,
                                     assignedChartSymbol,
                                     assignedCoordinatorKey,
                                     assignedCoordinatorChartId,
                                     assignedSignature,
                                     assignedAt))
         {
            bool coordinatorMatches = (coordinatorKey == "" ||
                                       assignedCoordinatorKey == "" ||
                                       StringCompare(assignedCoordinatorKey, coordinatorKey, false) == 0);
            bool sameAssignment = (assignedSignature != "" &&
                                   StringCompare(assignedSignature, assignmentSignature, false) == 0);
            if(coordinatorMatches && sameAssignment)
            {
               if(MBP_IsHeartbeatOwnedByChart(symbol, coordinatorKey, assignmentSignature, chartId))
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
                  Print(EmojiWarning(), " Closed duplicate worker chart for ", symbol,
                        " on chart ", chartId, "; keeping chart ", keepChartId, ".");
               }
               else
               {
                  Print(EmojiWarning(), " Duplicate worker chart close failed for ", symbol,
                        " on chart ", chartId, " Error=", _LastError);
               }
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
   string assignedSignature = "";
   datetime assignedAt = 0;
   if(!MBP_ReadWorkerAssignment(chartId,
                                assignedSymbol,
                                assignedSymbolsCsv,
                                assignedChartSymbol,
                                assignedCoordinatorKey,
                                assignedCoordinatorChartId,
                                assignedSignature,
                                assignedAt))
   {
      return false;
   }

   bool coordinatorMatches = (coordinatorKey == "" ||
                              assignedCoordinatorKey == "" ||
                              StringCompare(assignedCoordinatorKey, coordinatorKey, false) == 0);
   if(!coordinatorMatches)
      return false;

   if(assignmentSignature != "" &&
      assignedSignature != "" &&
      StringCompare(assignedSignature, assignmentSignature, false) == 0)
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
          IntegerToString((int)InpDataMode);
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
      int endIndex = (slotIndex == slotCount - 1) ? (requestedCount - 1) : slotIndex;

      string primarySymbol = requestedSymbols[startIndex];
      string symbolsCsv = MBP_JoinSymbolSlice(requestedSymbols, startIndex, endIndex);
      string chartSymbol = MBP_IsSyntheticDataMode(InpDataMode)
                           ? ResolveSyntheticChartSymbolName(primarySymbol, InpDataMode)
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
      }
      else
      {
         G_WorkerSlots[slotIndex].chartId = 0;
         G_WorkerSlots[slotIndex].lastLaunchAttemptMs = 0;
         G_WorkerSlots[slotIndex].lastHeartbeat = 0;
      }
   }
}

bool MBP_WriteWorkerAssignment(const long chartId,
                              const string symbol,
                              const string symbolsCsv,
                              const string chartSymbol,
                              const string coordinatorKey,
                              const string assignmentSignature)
{
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
   FileWriteString(handle, "assigned_at=" + IntegerToString((int)TimeCurrent()) + "\r\n");
   FileClose(handle);
   return true;
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

   string payload = MBP_ReadTextFileCommon(MBP_WorkerHeartbeatFile(symbol, coordinatorKey));
   if(payload == "")
      return false;

   string heartbeatValue = MBP_ReadKeyValue(payload, "heartbeat");
   string chartIdValue = MBP_ReadKeyValue(payload, "chart_id");
   if(heartbeatValue == "" || chartIdValue == "")
      return false;

   outHeartbeat = (datetime)StringToInteger(heartbeatValue);
   outChartId = (long)StringToInteger(chartIdValue);
   outSymbolsCsv = MBP_ReadKeyValue(payload, "symbols");
   outAssignmentSignature = MBP_ReadKeyValue(payload, "signature");
   outState = MBP_ReadKeyValue(payload, "state");
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

   if(assignmentSignature != "" &&
      heartbeatSignature != "" &&
      StringCompare(heartbeatSignature, assignmentSignature, false) != 0)
   {
      return false;
   }

   return true;
}

ENUM_MBP_RUNTIME_ROLE ResolveRuntimeRoleForCurrentChart()
{
   G_RuntimeCoordinatorKey = "";
   G_RuntimeAssignedWorkerSymbol = "";
   G_RuntimeAssignedChartSymbol = "";
   G_RuntimeAssignedSymbolsCsv = "";
   G_RuntimeAssignedWorkerSignature = "";
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
      bool coordinatorAlive = (assignedCoordinatorChartId > 0 &&
                               assignedCoordinatorChartId != ChartID() &&
                               MBP_IsChartAlive(assignedCoordinatorChartId));
      bool assignmentFresh = (assignedAt > 0 && (TimeCurrent() - assignedAt) <= 300);

      if(coordinatorAlive || assignmentFresh)
      {
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
         if(assignedCoordinatorKey == "" && assignedCoordinatorChartId > 0)
            assignedCoordinatorKey = StringFormat("%s_%I64d",
                                                  MBP_SanitizeRuntimeToken(InpHedgeChannel),
                                                  assignedCoordinatorChartId);
         G_RuntimeCoordinatorKey = assignedCoordinatorKey;
         return MBP_RUNTIME_WORKER;
      }

      if(!coordinatorAlive && !assignmentFresh)
      {
         string staleAssignmentFile = MBP_WorkerAssignmentFile(ChartID());
         if(FileIsExist(staleAssignmentFile, FILE_COMMON))
            FileDelete(staleAssignmentFile, FILE_COMMON);
      }
   }

   if(BotSystemMode != BOT_MODE_SLAVE)
   {
      G_RuntimeCoordinatorKey = MBP_DefaultCoordinatorKey();
      return MBP_RUNTIME_COORDINATOR;
   }

   G_RuntimeCoordinatorKey = MBP_SanitizeRuntimeToken(InpHedgeChannel);
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
   if(role == MBP_RUNTIME_LEGACY) return "LEGACY";
   if(role == MBP_RUNTIME_COORDINATOR) return "COORDINATOR";
   if(role == MBP_RUNTIME_WORKER) return "WORKER";
   return "UNKNOWN";
}

bool ShadowMaster_ShouldOwnRuntime()
{
   return (!IsParallelWorkerMode());
}

string ShadowMaster_BuildRuntimeSymbolsJson()
{
   string parts = "";
   string seen[];

   for(int i = 0; i < ArraySize(SymbolData); i++)
   {
      if(!SymbolData[i].active)
         continue;

      string symbolName = SymbolData[i].symbol;
      if(symbolName == "" && i < ArraySize(TradingSymbols))
         symbolName = TradingSymbols[i];
      if(symbolName == "")
         continue;

      bool duplicate = false;
      for(int j = 0; j < ArraySize(seen); j++)
      {
         if(seen[j] == symbolName)
         {
            duplicate = true;
            break;
         }
      }
      if(duplicate)
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
   int maxWorkers = MathMax(1, MathMin(MBP_GetParallelWorkerCap(), ArraySize(SymbolData)));

   string json = "{\r\n";
   json += "  \"version\": \"1.0\",\r\n";
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

   string runtimePath = ShadowMaster_GetRuntimeConfigPath();
   string payloadText = ShadowMaster_BuildRuntimeConfigJson();
   uchar payload[];
   StringToCharArray(payloadText, payload, 0, WHOLE_ARRAY, CP_UTF8);
   if(ArraySize(payload) > 0 && payload[ArraySize(payload) - 1] == 0)
      ArrayResize(payload, ArraySize(payload) - 1);

   uint genericWrite = 0x40000000;
   uint shareRead = 0x00000001;
   uint createAlways = 2;
   uint fileAttributeNormal = 0x00000080;

   int handle = CreateFileW(runtimePath, genericWrite, shareRead, 0, createAlways, fileAttributeNormal, 0);
   if(handle == -1)
   {
      Print(EmojiWarning(), " Failed to write ShadowMaster runtime config at ", runtimePath);
      return false;
   }

   uint written = 0;
   bool ok = WriteFile(handle, payload, (uint)ArraySize(payload), written, 0);
   CloseHandle(handle);

   if(!ok || written != (uint)ArraySize(payload))
   {
      Print(EmojiWarning(), " ShadowMaster runtime config write incomplete at ", runtimePath);
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

   if(!FileIsExist("ShadowMasterRuntime.json"))
      return false;

   int handle = FileOpen("ShadowMasterRuntime.json", FILE_READ|FILE_TXT|FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return false;

   string json = "";
   while(!FileIsEnding(handle))
      json += FileReadString(handle);
   FileClose(handle);

   string heartbeatRaw = V3_ExtractJSONValue(json, "last_heartbeat");
   if(heartbeatRaw != "")
      outHeartbeat = (datetime)StringToInteger(heartbeatRaw);

   outState = V3_ExtractJSONValue(json, "state");
   return (outHeartbeat > 0);
}

string MasterBuildWorkerTemplateSignature()
{
   return RuntimeRoleToText(G_RuntimeRole) + "|" +
          IntegerToString((int)InpDataMode) + "|" +
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
         return false;
      }
      return true;
   }

   string templateName = MBP_WorkerTemplateName();
   if(!ChartSaveTemplate(0, templateName))
   {
      Print(EmojiWarning(), " Failed to save worker template: ", templateName);
      return false;
   }

   G_LastWorkerTemplateSignature = signature;
   G_LastWorkerTemplateSaveMs = nowMs;
   Print(EmojiBrain(), " Worker EA template queued: ", templateName,
         ". Waiting briefly before attaching workers.");
   return false;
}

void MasterPublishWorkerHeartbeat()
{
   if(!IsParallelWorkerMode())
      return;

   ulong nowMs = GetTickCount();
   uint heartbeatIntervalMs = (uint)MathMax(250, InpParallelWorkerHeartbeatMs);
   if(G_WorkerBootstrapCompleted &&
      (nowMs - G_LastWorkerHeartbeatPublishMs) < heartbeatIntervalMs)
      return;

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
   string runtimeState = G_WorkerBootstrapCompleted ? "RUNNING" : "BOOTING";

   if(!MBP_WriteWorkerHeartbeatRecord(workerSymbol,
                                      G_RuntimeCoordinatorKey,
                                      assignedChartSymbol,
                                      assignedSymbolsCsv,
                                      assignmentSignature,
                                      runtimeState,
                                      linkedPositions,
                                      TimeCurrent(),
                                      ChartID()))
      return;

   G_LastWorkerHeartbeatPublishMs = nowMs;
}

bool MasterRuntimeShouldHandleTradeSymbol(const string symbol)
{
   if(IsParallelCoordinatorMode())
      return false;

   if(!IsParallelWorkerMode())
      return true;

   return MBP_RuntimeWorkerOwnsSymbol(symbol);
}

void MasterEnsureRuntimeWorkers()
{
   if(!IsParallelCoordinatorMode())
      return;

   ulong nowMs = GetTickCount();
   uint ensureIntervalMs = (uint)MathMax(2000, MathMax(250, InpParallelWorkerHeartbeatMs) * 2);
   if((nowMs - G_LastWorkerEnsureMs) < ensureIntervalMs)
      return;

   G_LastWorkerEnsureMs = nowMs;
   MBP_EnsureWorkerSlots();
   if(ArraySize(G_WorkerSlots) <= 0)
      return;

   if(!MasterSaveWorkerTemplate(false))
      return;

   uint heartbeatTtlSec = (uint)MathMax(15, (MathMax(250, InpParallelWorkerHeartbeatMs) * 8 + 999) / 1000);
   uint bootingTtlSec = (uint)MathMax(60, heartbeatTtlSec * 2);
   ulong relaunchGraceMs = (ulong)MathMax(6000, MathMax(250, InpParallelWorkerHeartbeatMs) * 6);
   string templateName = MBP_WorkerTemplateName();
   ENUM_TIMEFRAMES targetPeriod = (ENUM_TIMEFRAMES)ChartPeriod(0);
   string coordinatorKey = MBP_GetActiveCoordinatorKey();

   for(int i = 0; i < ArraySize(G_WorkerSlots); i++)
   {
      string baseSymbol = G_WorkerSlots[i].symbol;
      if(baseSymbol == "")
         continue;

      string workerChartSymbol = G_WorkerSlots[i].chartSymbol;
      if(workerChartSymbol == "")
         workerChartSymbol = baseSymbol;
      if(MBP_IsSyntheticDataMode(InpDataMode))
      {
         bool customReady = (bool)SymbolInfoInteger(workerChartSymbol, SYMBOL_CUSTOM);
         if(!customReady)
         {
            ResetLastError();
            if(!CustomSymbolCreate(workerChartSymbol, "MultiBotPro", baseSymbol))
            {
               Print(EmojiWarning(), " Worker synthetic symbol create failed for ", workerChartSymbol, " Error=", _LastError);
               G_WorkerSlots[i].lastLaunchAttemptMs = nowMs;
               continue;
            }
         }

         CustomSymbolSetInteger(workerChartSymbol, SYMBOL_DIGITS, (int)SymbolInfoInteger(baseSymbol, SYMBOL_DIGITS));
         CustomSymbolSetDouble(workerChartSymbol, SYMBOL_POINT, SymbolInfoDouble(baseSymbol, SYMBOL_POINT));
         CustomSymbolSetDouble(workerChartSymbol, SYMBOL_TRADE_TICK_SIZE, SymbolInfoDouble(baseSymbol, SYMBOL_TRADE_TICK_SIZE));
      }

      if(!SymbolSelect(workerChartSymbol, true))
      {
         Print(EmojiWarning(), " Worker chart symbol selection failed for ", workerChartSymbol);
         G_WorkerSlots[i].lastLaunchAttemptMs = nowMs;
         continue;
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
      long assignedChartId = MBP_FindAssignedWorkerChart(baseSymbol,
                                                         coordinatorKey,
                                                         G_WorkerSlots[i].assignmentSignature,
                                                         ChartID());
      if(heartbeatChartId <= 0 && assignedChartId > 0)
         heartbeatChartId = assignedChartId;

      bool chartAlive = (heartbeatChartId > 0 && MBP_IsChartAlive(heartbeatChartId));
      bool assignmentMatches = true;
      if(hasHeartbeat)
      {
         if(heartbeatSignature != "")
            assignmentMatches = (StringCompare(heartbeatSignature, G_WorkerSlots[i].assignmentSignature, false) == 0);
         else if(heartbeatSymbolsCsv != "")
            assignmentMatches = (StringCompare(heartbeatSymbolsCsv, G_WorkerSlots[i].symbolsCsv, false) == 0);
      }
      bool workerBooting = (StringCompare(heartbeatState, "BOOTING", false) == 0 ||
                            StringCompare(heartbeatState, "RELOADING", false) == 0);
      int heartbeatAgeSec = hasHeartbeat ? (int)(TimeCurrent() - heartbeat) : INT_MAX;
      bool heartbeatFresh = (hasHeartbeat &&
                             assignmentMatches &&
                             chartAlive &&
                             (heartbeatAgeSec <= (workerBooting ? (int)bootingTtlSec : (int)heartbeatTtlSec)));

      if(hasHeartbeat && assignmentMatches)
      {
         G_WorkerSlots[i].lastHeartbeat = heartbeat;
         if(chartAlive)
            G_WorkerSlots[i].chartId = heartbeatChartId;
      }

      if(heartbeatFresh)
      {
         G_WorkerSlots[i].chartId = heartbeatChartId;
         G_WorkerSlots[i].lastHeartbeat = heartbeat;
         MBP_CloseDuplicateAssignedWorkerCharts(baseSymbol,
                                                coordinatorKey,
                                                G_WorkerSlots[i].assignmentSignature,
                                                heartbeatChartId,
                                                ChartID());
         continue;
      }

      bool slotChartAlive = (G_WorkerSlots[i].chartId > 0 &&
                             MBP_IsAssignedWorkerChart(G_WorkerSlots[i].chartId,
                                                       baseSymbol,
                                                       coordinatorKey,
                                                       G_WorkerSlots[i].assignmentSignature));
      bool assignedChartAlive = (assignedChartId > 0 &&
                                 MBP_IsAssignedWorkerChart(assignedChartId,
                                                           baseSymbol,
                                                           coordinatorKey,
                                                           G_WorkerSlots[i].assignmentSignature));

      long liveChartId = 0;
      if(slotChartAlive)
         liveChartId = G_WorkerSlots[i].chartId;
      else if(assignedChartAlive)
         liveChartId = assignedChartId;

      if(liveChartId > 0)
      {
         G_WorkerSlots[i].chartId = liveChartId;
         MBP_CloseDuplicateAssignedWorkerCharts(baseSymbol,
                                                coordinatorKey,
                                                G_WorkerSlots[i].assignmentSignature,
                                                liveChartId,
                                                ChartID());
      }

      long targetChartId = 0;
      bool targetIsAssignedChart = false;
      bool launchGraceActive = (G_WorkerSlots[i].lastLaunchAttemptMs > 0 &&
                                (nowMs - G_WorkerSlots[i].lastLaunchAttemptMs) < relaunchGraceMs);
      if(liveChartId > 0)
      {
         if(launchGraceActive)
            continue;

         targetChartId = liveChartId;
         targetIsAssignedChart = true;
         Print(EmojiWarning(), " Worker chart for ", baseSymbol,
               " is open but not heartbeating. Reapplying worker EA template on chart ", targetChartId, ".");
      }
      else
      {
         if(launchGraceActive)
            continue;

         targetChartId = MBP_FindReusableChartBySymbol(workerChartSymbol, ChartID());
      }

      if(targetChartId <= 0)
         targetChartId = ChartOpen(workerChartSymbol, targetPeriod);

      if(targetChartId <= 0 || targetChartId == ChartID())
      {
         Print(EmojiWarning(), " Worker launch skipped for ", baseSymbol, " because no safe chart target was available.");
         G_WorkerSlots[i].lastLaunchAttemptMs = nowMs;
         continue;
      }

      string expectedReadySymbol = targetIsAssignedChart ? "" : workerChartSymbol;
      if(!MBP_WaitForChartTargetReady(targetChartId, expectedReadySymbol))
      {
         Print(EmojiWarning(), " Worker chart target was not ready for ", baseSymbol, " on chart ", targetChartId, ".");
         G_WorkerSlots[i].lastLaunchAttemptMs = nowMs;
         continue;
      }

      ApplyChartStyles(targetChartId);

      if(!MBP_WriteWorkerAssignment(targetChartId,
                                    G_WorkerSlots[i].symbol,
                                    G_WorkerSlots[i].symbolsCsv,
                                    workerChartSymbol,
                                    coordinatorKey,
                                    G_WorkerSlots[i].assignmentSignature))
      {
         Print(EmojiWarning(), " Failed to stamp worker assignment for ", baseSymbol, " on chart ", targetChartId);
         G_WorkerSlots[i].lastLaunchAttemptMs = nowMs;
         continue;
      }

      if(!ChartApplyTemplate(targetChartId, templateName))
      {
         Print(EmojiWarning(), " Failed to apply worker template to ", baseSymbol, " on chart ", targetChartId);
         string assignmentFile = MBP_WorkerAssignmentFile(targetChartId);
         if(FileIsExist(assignmentFile, FILE_COMMON))
            FileDelete(assignmentFile, FILE_COMMON);
         G_WorkerSlots[i].lastLaunchAttemptMs = nowMs;
         continue;
      }

      G_WorkerSlots[i].chartId = targetChartId;
      G_WorkerSlots[i].lastLaunchAttemptMs = nowMs;
      MBP_CloseDuplicateAssignedWorkerCharts(baseSymbol,
                                             coordinatorKey,
                                             G_WorkerSlots[i].assignmentSignature,
                                             targetChartId,
                                             ChartID());
      Print(EmojiBrain(), " Coordinator launched worker for ", baseSymbol, " on chart ", targetChartId, " (", workerChartSymbol, ").");
      break;
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
   bool heartbeatFresh = (hasHeartbeat && ((TimeCurrent() - heartbeat) <= 180));

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

   if(G_PythonBridge.BootShadowMaster(runtimePath))
   {
      G_LastShadowLaunchAttemptMs = nowMs;
      MarkShadowMasterPulse(false, "Shadow runtime launch requested");
   }
   else
   {
      MarkShadowMasterPulse(false, "Shadow runtime launch failed");
   }
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

   PrintFormat(EmojiShield() + " Smart hedge released for %s | basket=%d | scope=%s | protected_tickets=%d",
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
      PrintFormat(EmojiShield() + " Smart hedge armed for %s after the first protected %s SL move.",
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
         Print(GetBaseSymbol(SymbolData[symbolIndex].symbol), " entry gate: ", message);
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
      Print("[UI] Dashboard command queue full. Dropping oldest command.");
   }

   G_MasterUiCommandQueue[G_MasterUiCommandTail].type = commandType;
   G_MasterUiCommandQueue[G_MasterUiCommandTail].symbolIndex = symbolIndex;
   G_MasterUiCommandQueue[G_MasterUiCommandTail].buttonName = buttonName;
   G_MasterUiCommandTail = (G_MasterUiCommandTail + 1) % MBP_UI_COMMAND_QUEUE_CAPACITY;
   G_MasterUiCommandCount++;

   MasterRaiseUiPriorityWindow(1000);
   return true;
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

      if(GlobalVariableCheck(InpHedgeChannel + "_STOP_FLAG"))
         GlobalVariableDel(InpHedgeChannel + "_STOP_FLAG");
      if(GlobalVariableCheck(InpHedgeChannel + "_COOLDOWN_TIMER"))
         GlobalVariableDel(InpHedgeChannel + "_COOLDOWN_TIMER");
      if(GlobalVariableCheck(InpHedgeChannel + "_PAUSE_FLAG"))
         GlobalVariableDel(InpHedgeChannel + "_PAUSE_FLAG");

      ResetBridgePendingRequest();
      GlobalTradingEnabled = true;
      Print(EmojiCheck(), " Reset sequence finished asynchronously. System unlocked.");
   }
   else if(G_TradeControlJobType == MBP_CONTROL_JOB_CLOSE_ALL)
   {
      Print(EmojiBroom(), " Manual global close finished.");
   }
   else if(G_TradeControlJobType == MBP_CONTROL_JOB_CLOSE_SYMBOL)
   {
      Print(EmojiBroom(), " Manual chart close finished.");
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
      Print(EmojiReset(), " Master reset queued. Processing asynchronously.");
      IsPaused = true;
      GlobalTradingEnabled = false;
      WipeAllTerminalGlobalVariables();
   }
   else if(jobType == MBP_CONTROL_JOB_CLOSE_ALL)
   {
      Print(EmojiBroom(), " Manual global close queued.");
   }
   else if(jobType == MBP_CONTROL_JOB_CLOSE_SYMBOL)
   {
      Print(EmojiBroom(), " Manual chart close queued.");
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
         Print(IsPaused ? (EmojiPause() + " Bot paused.") : (EmojiCheck() + " Bot resumed."));
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
      Print("Error: Failed to select coordinator symbol ", baseSymbol, ". Removed from list.");
      return false;
   }

   SymbolData[index].active = true;
   SymbolData[index].BasketId = 1;
   SymbolData[index].IsPrimaryBasket = true;
   SymbolData[index].BasketActive = false;
   SymbolData[index].BasketInitialEntry = 0.0;
   SymbolData[index].BasketDirection = POSITION_TYPE_BUY;
   SymbolData[index].BaseSymbol = baseSymbol;
   SymbolData[index].AnalysisSymbol = baseSymbol;
   SymbolData[index].symbol = baseSymbol;
   SymbolData[index].DataMode = InpDataMode;
   SymbolData[index].RenkoFamily = MBP_DataModeToRenkoFamily(InpDataMode);

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
      Print(EmojiLock(), " Worker runtime detected. Reusing coordinator license session.");
     }
   else if(!VerifyLicense())
   {
      Print("FATAL: MultiBotPro initialization aborted due to invalid license.");
      return INIT_FAILED;
   }
   G_IS_DEINIT = false;
   G_InitInProgress = true;
   Comment("... loading ...");
   G_NextBasketId = 1;
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

// 2. Build symbol list
    BuildSymbolList();
    if(IsParallelCoordinatorMode())
       MBP_EnsureWorkerSlots();
    else
       ArrayResize(G_WorkerSlots, 0);

    if(IsParallelWorkerMode())
       MasterPublishWorkerHeartbeat();

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

   Print(EmojiBrain(), " Analysis symbol: ", _Symbol);
   Print(EmojiBrain(), " Execution symbol: ", RealSymbol);
   Print(EmojiBrain(), " Data mode: ", MBP_DataModeToText(InpDataMode));

   if(TradingSymbolsCount == 0)
     {
      string noSymbolsMsg = "No symbols configured. Set ManualSymbols, enable TradeAllMarketWatch, or turn on UseChartSymbol.";
      Print(noSymbolsMsg);
      Comment(noSymbolsMsg);
      return INIT_FAILED;
     }

// 4. Initialize symbol data array
   ArrayResize(SymbolData, TradingSymbolsCount);
   for(int i = 0; i < TradingSymbolsCount; i++)
   {
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
      SymbolData[i].DataMode = InpDataMode;
      SymbolData[i].RenkoFamily = MBP_DataModeToRenkoFamily(InpDataMode);
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

   if(!InitializeMasterAnalysisEngine())
      return INIT_FAILED;

   int activeSymbolsInitialized = 0;
   for(int i = 0; i < TradingSymbolsCount; i++)
   {
      string initialSymbol = TradingSymbols[i];
      if(i >= 0 && i < ArraySize(G_RuntimeSymbols) && G_RuntimeSymbols[i].analysis_symbol != "")
         initialSymbol = G_RuntimeSymbols[i].analysis_symbol;

      bool symbolInitialized = IsParallelCoordinatorMode()
                               ? InitializeCoordinatorSymbolState(initialSymbol, i)
                               : InitializeSymbolData(initialSymbol, i, InpDataMode);
      if(!symbolInitialized) 
      {
         Print("Failed to initialize symbol: ", TradingSymbols[i]);
         SymbolData[i].active = false;
         continue;
      }

      SymbolData[i].BasketId = G_NextBasketId++;
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
      Print("No symbols initialized successfully. Aborting startup.");
      return INIT_FAILED;
   }

// 5. Initialize excluded symbols array
   if(ExcludeSymbols != "")
     {
      StringSplit(ExcludeSymbols, ',', ExcludedSymbols);
     }

// 6. Set trade parameters
   Trade.SetDeviationInPoints(Slippage);
   Trade.SetExpertMagicNumber(MagicNumber);

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

// 8. Event listening
   // EventSetTimer(1);
   int timerIntervalMs = IsParallelCoordinatorMode() ? 250 : 125;
   EventSetMillisecondTimer(timerIntervalMs);

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
   Print("MultiBotPro EA Initialized Successfully");
   Print("Account: ", AccountInfoDouble(ACCOUNT_BALANCE), " ", AccountInfoString(ACCOUNT_CURRENCY));
   Print("Grid Distance Type: ", EnumToString(GridDistanceType));
   Print("Lock Trail: ", EnumToString(LockTrail));
   Print("Stack Mode: ", StackMode ? "ON" : "OFF", " | Stack Start: ", StackStart);
   Print("Grid Lot Size Mode: ", EnumToString(GridRiskType));

// Timezone Check (Live Only)
   if(MQLInfoInteger(MQL_TESTER) == 0)
     {
      datetime gmt = TimeGMT();
      datetime srv = TimeCurrent();
      int offset = (int)((long)srv - (long)gmt) / 3600;

      Print("--- TIMEZONE CHECK ---");
      Print("Server Time: ", srv);
      Print("Detected Server Offset: UTC ", (offset >= 0 ? "+" : ""), offset);
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

   if(ShadowMaster_IsAiRuntimeEnabled())
   {
      ShadowMaster_WriteRuntimeConfig(true);
      ShadowMaster_Supervise(true);
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
   if(IsBridgeRuntimeEnabled() && InpV3_EnableSQLiteBridge)
   {
      if(V3_EnsureRuntimeSchema(InpV3_SQLitePath))
      {
         Print(EmojiBrain(), " SQLite bridge initialized: ", InpV3_SQLitePath);
         V3_InsertEventRow(InpV3_SQLitePath, InpHedgeChannel, "master_init", "{\"status\":\"ready\"}");
      }
      else
      {
         Print(EmojiWarning(), " SQLite runtime schema init failed. Falling back to the file bridge.");
      }
   }

    if(IsBridgeRuntimeEnabled())
    {
       DeleteExpiredMasterReinitMarker();
    }

    if(IsParallelWorkerMode())
    {
       G_WorkerBootstrapCompleted = true;
       MasterPublishWorkerHeartbeat();
    }

    //EventSetTimer(60); // Set a 60-second timer
    G_InitInProgress = false;
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

      if(MBP_ShouldPreserveWorkerHeartbeatOnDeinit(reason))
      {
         MBP_WriteWorkerHeartbeatRecord(workerSymbol,
                                       G_RuntimeCoordinatorKey,
                                       assignedChartSymbol,
                                       assignedSymbolsCsv,
                                       assignmentSignature,
                                       "RELOADING",
                                       0,
                                       TimeCurrent(),
                                       ChartID());
      }
      else
      {
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

// 2. Remove timer
   EventKillTimer();
   ResetBridgePendingRequest();

// 3. Destroy Dashboard (Panel, Labels, & Buttons)
   DestroyDashboard();

// Insert this:
   DestroyManualPanel();

   ForceDeleteAllBotObjects();
    
// Final safety redraw
   ChartRedraw(0);

   Print("MultiBotPro EA Deinitialized");
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

void Master_OnTimer()
{
   static ulong lastBankSaveMs = 0;
   static ulong lastSyntheticPumpMs = 0;
   static ulong lastDeferredHousekeepingMs = 0;
   ulong timerNowMs = GetTickCount();
   bool coordinatorMode = IsParallelCoordinatorMode();
   bool workerMode = IsParallelWorkerMode();

   MasterPublishWorkerHeartbeat();
   MasterConsumeUiCommands();
   if(coordinatorMode)
      MasterEnsureRuntimeWorkers();

   bool shouldManageDashboardUi = (!workerMode &&
                                   (ShowManualSection || ShowTradeList || Panel_IsModifying || MQLInfoInteger(MQL_TESTER)));
   bool uiPriorityActive = MasterIsUiPriorityWindowActive() || shouldManageDashboardUi;

   if(ShowDashboard && !IsDragging && !G_DashboardDragArmed)
   {
      if(workerMode)
      {
         UpdateDashboard(0);
      }
      else if(shouldManageDashboardUi)
      {
         ManageManualSystem();
      }
      else
      {
         UpdateDashboard(0);
         if(!DashboardCollapsed)
         {
            if(Panel_IsModifying) ManageModificationMode();
            else ManageTradeListMode();
         }
         else if(!Panel_IsModifying)
         {
            ObjectsDeleteAll(0, BTN_PREFIX_LIST);
         }
      }
   }

   MasterProcessTradeControlLane();
   ProcessBridgePendingRequest();
   FlushBridgeSignalQueue();

   uint bankSaveIntervalMs = uiPriorityActive ? 5000 : 1000;
   if(timerNowMs - lastBankSaveMs >= bankSaveIntervalMs)
   {
      SaveAllBankStates();
      lastBankSaveMs = timerNowMs;
   }

   if(!uiPriorityActive || (timerNowMs - lastDeferredHousekeepingMs) >= 5000)
   {
      if(ShadowMaster_ShouldOwnRuntime())
         ShadowMaster_Supervise(false);
      lastDeferredHousekeepingMs = timerNowMs;
   }

   int configuredPumpMs = MBP_IsRenkoDataMode(InpDataMode)
                          ? InpRenkoLivePoolMs
                          : InpSyntheticPumpIntervalMs;
   uint syntheticPumpIntervalMs = (configuredPumpMs <= 0) ? 0 : (uint)configuredPumpMs;
   uint effectivePumpIntervalMs = syntheticPumpIntervalMs;
   if(uiPriorityActive)
   {
      if(effectivePumpIntervalMs == 0)
         effectivePumpIntervalMs = 250;
      else
         effectivePumpIntervalMs = MathMax((uint)250, effectivePumpIntervalMs * 4);
   }

   if(!coordinatorMode &&
      (effectivePumpIntervalMs == 0 ||
       lastSyntheticPumpMs == 0 ||
       (timerNowMs - lastSyntheticPumpMs) >= effectivePumpIntervalMs))
   {
      MasterPumpRuntimeServices();
      MasterPumpTimerServices();
      lastSyntheticPumpMs = timerNowMs;
   }

   if(!coordinatorMode &&
      !MasterIsUiPriorityWindowActive() &&
      !MasterHasPendingTradeControlJob())
      ProcessDeferredBoxHistoryWarmup();

   // --- CONTINUOUS LICENSE VERIFICATION ---
   if(!workerMode)
   {
      static int auth_timer_ticks = 0;
      auth_timer_ticks++;
      if(auth_timer_ticks >= 28800) 
      {
         Print(EmojiBrain(), " Running background license verification...");
         if(!VerifyLicense())
         {
            Print(EmojiWarning(), " Subscription expired mid-session. Executing a hard shutdown.");
            // ... (keep the rest of the shutdown loop)
            for(int i=0; i<ArraySize(SymbolData); i++)
            {
               if(SymbolData[i].active)
               {
                  CloseAllGridPositions(i, "License Expired");
                  ResetGridTracking(i);
               }
            }
            CloseAllGlobalPositions("License Expired");
            ExpertRemove(); 
         }
         auth_timer_ticks = 0;
      }
   }
     
   // --- STRATEGY TESTER CHART MANAGER ---
   MasterHandleTesterCharts();

   if(MQLInfoInteger(MQL_TESTER) && !workerMode)
      MasterPollDashboardButtons();

   if(ForceTimerExecution && !MasterIsUiPriorityWindowActive() && !coordinatorMode)
      Master_OnTick();

   // ==================================================================
   // VWAP & GLOBAL DAILY UPDATES (Synchronized to NY Time)
   // ==================================================================
   
   // 1. Calculate Core Times
   datetime gmtTime = TimeGMT();
   int ny_offset_seconds = (-5 + InpNYManualShift) * 3600; 
   datetime nyTime = gmtTime + ny_offset_seconds;
   
   MqlDateTime dt_ny;
   TimeToStruct(nyTime, dt_ny);

   // 2. Calculate "Trading Session" Time (Maps Midnight to 5 PM NY)
   datetime sessionTime = nyTime + (7 * 3600);
   MqlDateTime dt_session;
   TimeToStruct(sessionTime, dt_session);

   static int last_minute = -1;
   static int last_trading_day = -1;

   if(!coordinatorMode && dt_ny.min != last_minute)
   {
      last_minute = dt_ny.min;
      
      for(int i = 0; i < ArraySize(SymbolData); i++)
      {
         if(SymbolData[i].active && ShouldUpdateVWAPRuntime()) UpdateVWAP(i);
      }

      // Initialize the tracking day on the very first run
      if(last_trading_day == -1) last_trading_day = dt_session.day_of_year;

      // 3. 5 PM NY Rollover Check
      if(dt_session.day_of_year != last_trading_day)
      {
         last_trading_day = dt_session.day_of_year;
         
         for(int i = 0; i < ArraySize(SymbolData); i++)
         {
            if(SymbolData[i].active)
            {
               SymbolData[i].DailyProfitLoss = 0;
               SymbolData[i].LastDailyReset = TimeCurrent(); // Internal timestamp can remain server time
               SymbolData[i].NewVWAPHighLowSet = false; 
            }
         }

         DailyGlobalProfit = 0;
         DailyGlobalLoss = 0;
         LastGlobalDailyReset = TimeCurrent();
      }
   }

   // ==================================================================
   // MOVED FROM ONTICK: SHADOW MASTER SYNC HANDSHAKE 
   // ==================================================================
   if(InpEnableShadowMaster && !workerMode && GetTickCount() - G_LastShadowSyncCheck > 5000) 
   {
       static datetime lastSyncDetected = 0;
       string syncFile = "ShadowSync.json";

       if(FileIsExist(syncFile))
       {
           datetime fileTime = (datetime)FileGetInteger(syncFile, FILE_MODIFY_DATE);
           if(fileTime > lastSyncDetected)
           {
               Print(EmojiBrain(), " Shadow master sync detected. Reloading configs...");
               for(int i = 0; i < ArraySize(SymbolData); i++) 
               {
                   if(SymbolData[i].active) LoadShadowConfig(i);
               }
               MarkIndicatorOverlayDirty();
               lastSyncDetected = fileTime;
               MarkShadowMasterPulse(true, "Shadow sync refreshed");
           }
       }
       else
       {
           MarkShadowMasterPulse(false, "Shadow sync file not found");
       }
       G_LastShadowSyncCheck = GetTickCount();
   }

   // ==================================================================
   // MOVED FROM ONTICK: HEDGE MASTER & SYSTEM BLOCK CHECKS
   // ==================================================================
   bool isSystemBlocked = false;

   // A. Check Hedge HARD Block (Limits)
   if(GlobalVariableCheck(InpHedgeChannel + "_STOP_FLAG") && GlobalVariableGet(InpHedgeChannel + "_STOP_FLAG") > 0.0)
   {
      static long last_warn_stop = 0;
      if(GetTickCount() - last_warn_stop > 86400000) {
         Print(EmojiWarning(), " Trading blocked: master limits reached.");
         last_warn_stop = GetTickCount();
      }
      RemoveSignalArrows();
      isSystemBlocked = true;
   }

   // B. Check Hedge PAUSE (Cooldown/Security)
   if(!isSystemBlocked && GlobalVariableCheck(InpHedgeChannel + "_PAUSE_FLAG") && GlobalVariableGet(InpHedgeChannel + "_PAUSE_FLAG") > 0.0)
   {
      static long last_warn_pause = 0;
      if(GetTickCount() - last_warn_pause > 7200000) { 
         Print(EmojiWarning(), " Trading paused: master security cooldown.");
         Comment(EmojiWarning() + " Master cooldown active");
          last_warn_pause = GetTickCount();
      }
      isSystemBlocked = true;
   }
   else if(!isSystemBlocked) {
      string c = "";
      ChartGetString(0, CHART_COMMENT, c);
      string cu = c;
      StringToUpper(cu);
          Comment("");
   }

   // C. Global Safety Checks
   if(!isSystemBlocked && !GlobalTradingEnabled) isSystemBlocked = true;
   
   G_Cache_SystemBlocked = isSystemBlocked; // Update Cache

   // ==================================================================
   // ?? MOVED FROM ONTICK: TIME & NEWS CALCULATIONS
   // ==================================================================
   bool isFridayStop = false;
   if(UseFridayHardStop && dt_ny.day_of_week == 5)
   {
      if(IsInsideInterval(FridayStop_StartHour, FridayStop_StartMinute, FridayStop_EndHour, FridayStop_EndMinute, dt_ny))
         isFridayStop = true;
   }

   // Evaluate scheduled blocks strictly against New York Time
   G_Cache_IsDailyCloseBlock = IsInsideInterval(CloseBlock_StartHour, CloseBlock_StartMinute, CloseBlock_EndHour, CloseBlock_EndMinute, dt_ny);
// Update the G_Cache_IsHardBlock assignment to use the new variable:
   G_Cache_IsHardBlock = (UseCloseBlock && G_Cache_IsDailyCloseBlock) || isFridayStop;
   G_Cache_BlockReason = isFridayStop ? "Friday Hard Stop Activated" : "Hard Close Block Activated";
   
   G_Cache_IsTradingTime = IsTradingTime();
   G_Cache_IsNewsTime = IsNewsTime(); 

   // Visual Updates
   if(NewsWindowColorEnable && G_Cache_IsNewsTime) HighlightActiveNewsBar();
   DrawNewsLines();

   // ==================================================================
   // --- INTEGRATED HEDGE MASTER ENGINE (Existing Logic) ---
   // ==================================================================
   string MasterFile = GetMasterFile(InpHedgeChannel);
   string SlaveFile  = GetSlaveFile(InpHedgeChannel);
   string ResetFile  = "HedgeReset_" + InpHedgeChannel + ".bin";
   string FeedbackFile = GetFeedbackFile(InpHedgeChannel);

   // A0. Consume slave feedback
   if(IsBridgeRuntimeEnabled() && InpV3_EnableSQLiteBridge)
   {
      int feedbackProcessed = 0;
      while(feedbackProcessed < MBP_MAX_FEEDBACK_ROWS_PER_TIMER)
      {
         long feedbackRowId = -1;
         HedgeFeedback fb;
         string feedbackNote = "";
         if(!V3_SelectPendingFeedbackRow(InpV3_SQLitePath, InpHedgeChannel, feedbackRowId, fb, feedbackNote))
            break;

         ProcessBridgeFeedbackRecord(fb, feedbackNote);
         V3_MarkFeedbackConsumed(InpV3_SQLitePath, feedbackRowId);
         feedbackProcessed++;
      }
   }

   if(FileIsExist(FeedbackFile, FILE_COMMON))
      ProcessBridgeFeedbackFileBatch(FeedbackFile, MBP_MAX_FILE_FEEDBACK_PER_TIMER);

   // A0b. Cooldown timer lifecycle
   bool bridgePaused = false;
   string pauseVar = InpHedgeChannel + "_PAUSE_FLAG";
   string cooldownVar = InpHedgeChannel + "_COOLDOWN_TIMER";
   if(GlobalVariableCheck(cooldownVar))
   {
      double resumeAt = GlobalVariableGet(cooldownVar);
      if((double)TimeCurrent() < resumeAt)
      {
         bridgePaused = true;
         GlobalVariableSet(pauseVar, 1.0);
      }
      else
      {
         GlobalVariableDel(cooldownVar);
         if(GlobalVariableCheck(pauseVar)) GlobalVariableDel(pauseVar);
      }
   }
   else if(GlobalVariableCheck(pauseVar)) GlobalVariableDel(pauseVar);

   // A. Check if Slave sent a Reset Command
   if(FileIsExist(ResetFile, FILE_COMMON)) {
       int hRst = FileOpenRobust(ResetFile, FILE_READ|FILE_BIN|FILE_COMMON);
       if(hRst != INVALID_HANDLE) {
           CurrentResetID = FileReadLong(hRst);
           FileClose(hRst);
           FileDelete(ResetFile, FILE_COMMON);
           MasterStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
           m_day_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
                          
           if (InpMasterRiskMode == RISK_TRAILING) {
               double base = (InpStartingBalance > 0) ? InpStartingBalance : MasterStartEquity;
               EffectiveMasterRisk = base * (InpTrailPercent / 100.0);
           }
           
           GlobalVariableSet(InpHedgeChannel+"_MasterStartEq", MasterStartEquity);
           GlobalVariableSet(InpHedgeChannel+"_MasterDayEq", m_day_start_equity);
           
           m_daily_stop_hit = false;
           m_total_stop_hit = false;
           g_HighWaterMark = (InpStartingBalance > 0) ? InpStartingBalance : MasterStartEquity;
           g_TrailingStopLevel = g_HighWaterMark * (1.0 - (InpTrailPercent / 100.0));
           SmartHedge_ResetAll();
       }
   }

   // B. Daily Rollover Check (5 PM NY Time via dt_session)
   if(dt_session.day_of_year != m_current_day_of_year) {
       m_current_day_of_year = dt_session.day_of_year;
       m_day_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
       m_daily_stop_hit = false;
       GlobalVariableSet(InpHedgeChannel+"_MasterDayEq", m_day_start_equity);
       GlobalVariableSet(InpHedgeChannel+"_MasterDayOfYear", m_current_day_of_year);
       SmartHedge_ResetDailyBaselines();
   }
   if(!workerMode)
   {
      // C. Update Stop Flags
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double totalPnL = currentEquity - MasterStartEquity;
      double dailyPnL = currentEquity - m_day_start_equity;
      SmartHedge_ReconcileProtectedTrades();
      SmartHedge_ApplyPnLAdjustments(totalPnL, dailyPnL);

      // ?? ONLY trigger limits if the Bridge is ON ??
      if(IsBridgeRuntimeEnabled())
        {
         if (totalPnL <= -InpMasterRisk) m_total_stop_hit = true;
         if (dailyPnL <= -InpMasterDailyLoss) m_daily_stop_hit = true;
         
         if (InpMasterRiskMode == RISK_TRAILING) {
             if (currentEquity > g_HighWaterMark) {
                 g_HighWaterMark = currentEquity;
                 g_TrailingStopLevel = g_HighWaterMark * (1.0 - (InpTrailPercent / 100.0));
             }
             if (currentEquity <= g_TrailingStopLevel) m_total_stop_hit = true;
         }
        }
      else
        {
         // Bridge is OFF: Ensure flags stay false so local grids are never blocked
         m_total_stop_hit = false;
         m_daily_stop_hit = false;
         
         // Keep HighWaterMark updating silently in the background just in case you turn the Bridge ON mid-session
         if (InpMasterRiskMode == RISK_TRAILING && currentEquity > g_HighWaterMark) {
             g_HighWaterMark = currentEquity;
             g_TrailingStopLevel = g_HighWaterMark * (1.0 - (InpTrailPercent / 100.0));
         }
        }

      GlobalVariableSet(InpHedgeChannel + "_STOP_FLAG", (m_total_stop_hit || m_daily_stop_hit) ? 1.0 : 0.0);
      
      // D. Write State for Slave to Read
      HedgeState state;
      ZeroMemory(state);
      state.master_current_equity = currentEquity;
      state.master_start_equity = MasterStartEquity;
      state.master_pnl = totalPnL;
      state.master_balance_pnl = totalPnL;
      state.master_daily_pnl = dailyPnL;
      state.master_target_risk = EffectiveMasterRisk;
      state.master_target_profit = InpMasterTargetProfit;
      state.master_daily_limit = InpMasterDailyLoss;
      state.master_daily_target = InpMasterDailyProfit;
      state.slave_target_gain = InpSlaveGain;
      state.is_daily_stopped = m_daily_stop_hit;
      state.is_total_stopped = m_total_stop_hit;
      state.is_paused = (IsPaused || bridgePaused);
      state.reset_id = CurrentResetID;
      state.last_heartbeat = (ulong)TimeGMT();

      if(IsBridgeRuntimeEnabled() && InpV3_EnableSQLiteBridge)
         V3_WriteMasterStateRow(InpV3_SQLitePath, InpHedgeChannel, state);

      int hOut = FileOpen(MasterFile, FILE_WRITE|FILE_BIN|FILE_COMMON);
      if(hOut != INVALID_HANDLE) { FileWriteStruct(hOut, state); FileClose(hOut); }

      RefreshSystemSnapshot(G_Cache_SystemBlocked, G_Cache_IsTradingTime, G_Cache_IsNewsTime, G_Cache_IsHardBlock, G_Cache_BlockReason);
      TouchMasterAnalysisEngineOnTimer();
      WriteActiveTrades();
      if(!coordinatorMode)
      {
         CheckSlaveConnection();
         CheckMasterOrphans();
      }
      if(!coordinatorMode)
      {
         RefreshIndicatorOverlay(true);
         RefreshCurrentChartBoxLines(false);
      }
   }
   else if(workerMode)
   {
      RefreshIndicatorOverlay(false);
      RefreshCurrentChartBoxLines(false);
   }
}


//+------------------------------------------------------------------+
//| Expert tick function (ULTRA-OPTIMIZED WITH SYMBOL FILTERING)     |
//+------------------------------------------------------------------+
void Master_OnTick()
{
   if(G_IS_DEINIT || IsStopped()) return;
   if(!G_LicenseValid) return;

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
      Print("Charts forced to Candles/Colors via Code.");
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
        Print(EmojiShield(), " Master limit breached with the bridge on. Closing all active positions.");
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

   ProcessBridgePendingRequest();
   FlushBridgeSignalQueue();

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

      if(symbol == _Symbol && hasNewTick)
      {
         RefreshCurrentChartBoxLines(false);
      }

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
         bool allowEntry = G_Cache_IsTradingTime && !G_Cache_IsNewsTime;
         if(OperationMode == MODE_SEMI_AUTO)
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
                                 
                              Print(symbol, " [Auto-Repay] Broker Closed Trade in Profit ($", DoubleToString(netProfit, 2), 
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
                           Print(symbol, " [Loss-Capture] Broker Closed Trade in Loss ($", DoubleToString(netProfit, 2), 
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
                     Print(symbol, " All Grid Positions Closed (Detected in OnTradeTransaction). Resetting Tracking.");
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
               PrintFormat(EmojiWarning() + " Bridge signal ignored: unable to resolve the executed master side for ticket=%I64u symbol=%s",
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
                  PrintFormat(EmojiShield() + " Bridge side mismatch: req=%I64d ticket=%I64u queued=%s executed=%s source=%s symbol=%s. Using the executed master side.",
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
               PrintFormat(EmojiShield() + " Smart hedge bypass active: ticket=%I64u symbol=%s basket=%d | slave mirror skipped.",
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
               PrintFormat(EmojiWarning() + " Bridge signal skipped: ticket=%I64u symbol=%s reason=%s",
                           posID,
                           baseSym,
                           failureReason);
               return;
            }

            signal.sl_dist_points = slDistPoints;
            signal.risk_money = riskMoney;

            if(Master_HasRecentBridgeSignal(posID, signal.action))
            {
               PrintFormat(EmojiShield() + " Duplicate bridge open signal ignored: ticket=%I64u symbol=%s",
                           posID,
                           baseSym);
               return;
            }
            Master_RememberBridgeSignal(posID, signal.action);
            
            // Queue the signal instead of writing synchronously
            int qSize = ArraySize(G_SignalQueue);
            ArrayResize(G_SignalQueue, qSize + 1);
            G_SignalQueue[qSize] = signal;

            PrintFormat(EmojiShield() + " Bridge signal emitted: ticket=%I64u | executed master %s | source=%s | symbol=%s | risk_source=%s | stop=%.5f | sl_pts=%.1f | risk=%.2f",
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
         }
      }
   }
}

//+------------------------------------------------------------------+
//| EVENT HANDLER: Button Clicks & Dragging (OPTIMIZED)              |
//+------------------------------------------------------------------+
void Master_OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   G_MasterUiPriorityUntilMs = GetTickCount() + 250;

   if(id == CHARTEVENT_OBJECT_DRAG)
   {
      OnPanelDrag(sparam);
      return;
   }

   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(G_DashboardDragArmed && !IsDragging)
      {
         G_DashboardDragArmed = false;
         DragInteractionX = 0;
         DragInteractionY = 0;
         ChartSetInteger(0, CHART_MOUSE_SCROLL, true);
      }

      if(StringFind(sparam, "Btn_") == 0)
      {
         int queuedSymbolIndex = -1;
         int queuedCommand = MBP_UI_CMD_NONE;

         if(sparam == "Btn_MasterReset") queuedCommand = MBP_UI_CMD_MASTER_RESET;
         else if(sparam == "Btn_Pause") queuedCommand = MBP_UI_CMD_TOGGLE_PAUSE;
         else if(sparam == "Btn_Collapse") queuedCommand = MBP_UI_CMD_TOGGLE_COLLAPSE;
         else if(sparam == "Btn_Dash_Scale_P") queuedCommand = MBP_UI_CMD_DASH_SCALE_UP;
         else if(sparam == "Btn_Dash_Scale_M") queuedCommand = MBP_UI_CMD_DASH_SCALE_DOWN;
         else if(sparam == "Btn_ToggleMan") queuedCommand = MBP_UI_CMD_TOGGLE_MANUAL_SECTION;
         else if(sparam == "Btn_ToggleList") queuedCommand = MBP_UI_CMD_TOGGLE_TRADE_LIST;
         else if(sparam == "Btn_CloseAll") queuedCommand = MBP_UI_CMD_CLOSE_ALL;
         else if(sparam == "Btn_CloseChart")
         {
            queuedCommand = MBP_UI_CMD_CLOSE_SYMBOL;
            queuedSymbolIndex = ResolveDashboardFocusSymbolIndex();
            if(queuedSymbolIndex < 0)
            {
               queuedSymbolIndex = GetSymbolIndex(_Symbol);
               if(queuedSymbolIndex == -1)
                  queuedSymbolIndex = GetSymbolIndex(RealSymbol);
            }
         }

         if(queuedCommand != MBP_UI_CMD_NONE)
         {
            bool isImmediateUiCommand = (queuedCommand == MBP_UI_CMD_TOGGLE_PAUSE ||
                                         queuedCommand == MBP_UI_CMD_TOGGLE_COLLAPSE ||
                                         queuedCommand == MBP_UI_CMD_DASH_SCALE_UP ||
                                         queuedCommand == MBP_UI_CMD_DASH_SCALE_DOWN ||
                                         queuedCommand == MBP_UI_CMD_TOGGLE_MANUAL_SECTION ||
                                         queuedCommand == MBP_UI_CMD_TOGGLE_TRADE_LIST);

            if(!MQLInfoInteger(MQL_TESTER) && isImmediateUiCommand)
            {
               RememberDashboardButtonHandled(sparam);
               MasterRaiseUiPriorityWindow(1200);

               SMasterUiCommand immediateCmd;
               ZeroMemory(immediateCmd);
               immediateCmd.type = queuedCommand;
               immediateCmd.symbolIndex = queuedSymbolIndex;
               immediateCmd.buttonName = sparam;
               MasterExecuteUiCommand(immediateCmd);
            }
            else
            {
               MasterEnqueueUiCommand(queuedCommand, queuedSymbolIndex, sparam);
               ChartRedraw(0);
            }
            return;
         }

         RememberDashboardButtonHandled(sparam);
      }

      if(StringFind(sparam, "NewsLine_") >= 0 || StringFind(sparam, "NewsIcon_") >= 0)
      {
         string idStr = StringSubstr(sparam, 9);
         ShowNewsDetails("NewsLine_" + idStr);
      }
      else if(StringFind(sparam, "Row_Sym_") == 0)
      {
         static string lastClickedSymObj = "";
         static uint lastClickTimeSym = 0;
         uint currentTime = GetTickCount();

         if(sparam == lastClickedSymObj && (currentTime - lastClickTimeSym) < 500)
         {
            int idx = (int)StringToInteger(StringSubstr(sparam, 8));

            if(idx >= 0 && idx < ArraySize(SymbolData))
            {
               string targetSymbol = ResolveManagedAnalysisSymbol(idx);
               string targetBaseSymbol = (SymbolData[idx].BaseSymbol != "") ? SymbolData[idx].BaseSymbol : GetBaseSymbol(targetSymbol);
               SetDashboardFocusSymbol(targetBaseSymbol);
               if(targetSymbol == _Symbol)
               {
                  lastClickedSymObj = "";
                  lastClickTimeSym = 0;
                  return;
               }
               Print(EmojiMouse(), " Double click detected. Saving runtime state before the chart switch...");

               for(int i = 0; i < ArraySize(SymbolData); i++)
               {
                  if(SymbolData[i].active)
                     SaveBankState(i);
               }

               SaveBoxHistoryCache();
               SaveFastChartSwitchDashboardState();
               MarkFastChartSwitchPending();

               Print(EmojiMouse(), " Runtime state saved. Switching chart to: ", targetSymbol);
               if(G_LicenseValid)
                  TouchLicenseCache((long)AccountInfoInteger(ACCOUNT_LOGIN));
               MarkIndicatorOverlayDirty();
               ChartSetSymbolPeriod(0, targetSymbol, _Period);
            }
            lastClickedSymObj = "";
         }
         else
         {
            lastClickedSymObj = sparam;
            lastClickTimeSym = currentTime;
         }
      }
   }

   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      if(sparam == "0" && !IsDragging && !G_DashboardDragArmed)
         return;

      static uint lastDraw = 0;
      bool allowRedraw = (GetTickCount() - lastDraw > 30);

      int mouseX = (int)lparam;
      int mouseY = (int)dparam;
      int mouseState = (int)StringToInteger(sparam);

      if(!IsWorkerDashboardMode() && !DashboardCollapsed && !IsDragging && !G_DashboardDragArmed)
      {
         bool hoverChanged = false;

         for(int i = 0; i < ArraySize(SymbolData); i++)
         {
            string symObj = "Row_Sym_" + IntegerToString(i);
            if(ObjectFind(0, symObj) >= 0)
            {
               int objX = (int)ObjectGetInteger(0, symObj, OBJPROP_XDISTANCE);
               int objY = (int)ObjectGetInteger(0, symObj, OBJPROP_YDISTANCE);
               color currentColor = (color)ObjectGetInteger(0, symObj, OBJPROP_COLOR);

               if(mouseX >= objX && mouseX <= objX + S_Dash(60) &&
                  mouseY >= objY && mouseY <= objY + S_Dash(15))
               {
                  if(currentColor != clrWhite)
                  {
                     ObjectSetInteger(0, symObj, OBJPROP_COLOR, clrWhite);
                     hoverChanged = true;
                  }
               }
               else if(currentColor != clrYellow)
               {
                  ObjectSetInteger(0, symObj, OBJPROP_COLOR, clrYellow);
                  hoverChanged = true;
               }
            }
         }

         if(hoverChanged && allowRedraw)
         {
            ChartRedraw(0);
            lastDraw = GetTickCount();
         }
      }

      int panelHeight = GetDashboardBottomY() - DashboardY;
      if(panelHeight < S_Dash(30))
         panelHeight = S_Dash(30);
      int panelWidth = GetDashboardWidth();
      bool mouseInPanel = (mouseX >= DashboardX && mouseX <= (DashboardX + panelWidth) &&
                           mouseY >= DashboardY && mouseY <= (DashboardY + panelHeight));

      if((mouseState & 1) == 1)
      {
         if(mouseInPanel)
            ChartSetInteger(0, CHART_MOUSE_SCROLL, false);

         if(mouseInPanel && !IsDragging && !G_DashboardDragArmed)
         {
            G_DashboardDragArmed = true;
            G_DashboardDragStartX = mouseX;
            G_DashboardDragStartY = mouseY;
            DragInteractionX = mouseX - DashboardX;
            DragInteractionY = mouseY - DashboardY;
         }

         if(G_DashboardDragArmed && !IsDragging)
         {
            int dragDistance = (int)MathMax(MathAbs(mouseX - G_DashboardDragStartX), MathAbs(mouseY - G_DashboardDragStartY));
            if(dragDistance >= DASH_DRAG_THRESHOLD_PX)
               IsDragging = true;
         }

         if(IsDragging)
         {
            int newX = mouseX - DragInteractionX;
            int newY = mouseY - DragInteractionY;

            if(newX < 0) newX = 0;
            if(newY < 0) newY = 0;

            DashboardX = newX;
            DashboardY = newY;

            if(allowRedraw)
            {
               if(InpLiveDragging)
                  MoveDashboard(DashboardX, DashboardY);
               else
                  MoveDashboardFrameOnly(DashboardX, DashboardY);
               ChartRedraw(0);
               lastDraw = GetTickCount();
            }
         }
      }
      else
      {
         bool wasDragging = IsDragging;
         if(IsDragging || G_DashboardDragArmed)
         {
            IsDragging = false;
            G_DashboardDragArmed = false;
            ChartSetInteger(0, CHART_MOUSE_SCROLL, true);

            if(wasDragging)
            {
               MoveDashboard(DashboardX, DashboardY);
               ChartRedraw();
            }
         }
      }
   }
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
void SaveBankState(int idx)
{
   // --- FIX START: BLOCK SAVING DURING RESET ---
   if(G_ResetPending) return;
   // --- FIX END ---
   
   if(!SymbolData[idx].active) return;
   string sym = SymbolData[idx].symbol;
   // Create unique names using Magic Number + Symbol
   string pName = StringFormat("MBP_%d_%s_Prune", MagicNumber, sym);
   string cName = StringFormat("MBP_%d_%s_Crit", MagicNumber, sym);
   
   GlobalVariableSet(pName, SymbolData[idx].AccumulatedPruningLoss);
   GlobalVariableSet(cName, SymbolData[idx].AccumulatedCriticalLoss);
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
}

void WipeBankState(int idx)
{
   // 1. Clear RAM
   SymbolData[idx].AccumulatedPruningLoss = 0;
   SymbolData[idx].AccumulatedCriticalLoss = 0;
   
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
   
   Print(EmojiBroom(), " Wiped bank state for ", sym, " (RAM and disk).");
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

string GetLicenseCacheKey(const long account)
  {
   return "MBP_" + IntegerToString(MagicNumber) + "_" + IntegerToString((int)account) + "_LicenseCache";
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

void TouchLicenseCache(const long account)
  {
   if(account <= 0)
      return;

   GlobalVariableSet(GetLicenseCacheKey(account), (double)TimeCurrent());
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
   if(IsParallelWorkerMode())
     {
      G_LicenseValid = true;
      return true;
     }

   // --- STRATEGY TESTER BYPASS ---
   if(MQLInfoInteger(MQL_TESTER))
     {
      Print(EmojiTest(), " Strategy Tester mode detected. Bypassing license verification.");
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
     
   if(cached_account == 0)
     {
      Print(EmojiWarning(), " Terminal disconnected from the broker. Delaying the background license check.");
      return true; 
     }
   // -----------------------------
   
   // Prepare POST payload
   string post_data = "key=" + InpLicenseKey + "&account=" + IntegerToString(cached_account) + "&hwid=" + cached_hwid;
   StringToCharArray(post_data, post);
   
   // Timeout set to 5000ms. 
   int res = WebRequest("POST", url, cookie, NULL, 5000, post, ArraySize(post), result, headers);

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
         TouchLicenseCache(cached_account);
         Print(EmojiLock(), " MultiBotPro license verified. Expires: ", expires);
         return true;
        }
      else if(status == "expired")
        {
         G_LicenseValid = false;
         ClearLicenseCache(cached_account);
         Print(EmojiWarning(), " Subscription expired: ", message);
         return false;
        }
      else
        {
         G_LicenseValid = false;
         ClearLicenseCache(cached_account);
         Print(EmojiWarning(), " License error: ", message);
         return false;
        }
     }
   else
     {
      ClearLicenseCache(cached_account);
      Print(EmojiWarning(), " License server request failed. HTTP code: ", res, " | Error: ", GetLastError());
      // Fail-closed security
      G_LicenseValid = false; 
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
      Print(EmojiWarning(), " SQLite write failed. Falling back to the binary file bridge.");
   }

   string sf = GetSignalFile(InpHedgeChannel);
   int h = FileOpenRobust(sf, FILE_READ|FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(h != INVALID_HANDLE) {
      FileSeek(h, 0, SEEK_END);
      FileWriteStruct(h, sig);
      FileClose(h);
      return true;
   }

    Print(EmojiWarning(), " Bridge signal write failed: could not open the fallback signal file.");
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

   int processedCount = 0;
   int writeLimit = MathMin(qSize, maxSignals);
   for(int i = 0; i < writeLimit; i++)
   {
      HedgeSignal sig = G_SignalQueue[i];
      string rejectReason = "";
      if(!ValidateBridgeSignalForWrite(sig, rejectReason))
      {
         PrintFormat(EmojiWarning() + " Bridge signal discarded before write: ticket=%I64u action=%d symbol=%s reason=%s lots=%.2f sl_pts=%.2f risk=%.2f",
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
         Print(EmojiShield(), " Smart hedge ignored slave kill for protected master ticket #", fb.master_ticket,
               (StringLen(feedbackNote) > 0 ? " | Note: " + feedbackNote : ""));
         return;
      }

      if(PositionSelectByTicket(fb.master_ticket))
      {
         Trade.PositionClose(fb.master_ticket);
         Print(EmojiShield(), " Slave commanded kill. Closed master ticket #", fb.master_ticket);
      }
      int cooldownMinutes = (InpV3_PauseCooldownMinutes > 0) ? InpV3_PauseCooldownMinutes : ((AccountLimitCooldownMinutes > 0) ? AccountLimitCooldownMinutes : 2);
      double resumeAt = (double)(TimeCurrent() + (cooldownMinutes * 60));
      GlobalVariableSet(InpHedgeChannel + "_COOLDOWN_TIMER", resumeAt);
      GlobalVariableSet(InpHedgeChannel + "_PAUSE_FLAG", 1.0);
   }
   else if(fb.action == 2)
   {
      if(StringLen(feedbackNote) > 0)
         Print(EmojiShield(), " Slave close acknowledged: master ticket #", fb.master_ticket, " | Note: ", feedbackNote);
      else
         Print(EmojiShield(), " Slave close acknowledged: master ticket #", fb.master_ticket);
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
      ArrayResize(pending, idx + 1);
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

   int hw = FileOpen(feedbackFile, FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(hw == INVALID_HANDLE)
      return;

   for(int i = processCount; i < total; i++)
      FileWriteStruct(hw, pending[i]);

   FileClose(hw);
}

 //+------------------------------------------------------------------+
//| Initiates the Async Handshake and Locks the State Machine        |
//+------------------------------------------------------------------+
bool SendAsyncBridgeProposal(int symbolIndex, int type, double lots, string sym, double riskMoney)
{
   // 1. Prevent overlapping requests (Double-check)
   if(G_BridgePending.active || G_BridgePending.approved) 
   {
      Print(EmojiShield(), " Async handshake blocked: another request is already active.");
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
      
      Print(EmojiShield(), " Async handshake sent for ", sym, ". State machine locked.");
      return true;
   }
   Print(EmojiWarning(), " Async handshake file write failed.");
   return false;
}

//+------------------------------------------------------------------+
//| SECURITY: Check if Master trades have a running Slave counterpart|
//+------------------------------------------------------------------+
bool ReadSlaveTrackedTickets(const string fileName, ulong &tickets[])
{
   ArrayResize(tickets, 0);

   if(!FileIsExist(fileName, FILE_COMMON))
      return false;

   int h = FileOpenRobust(fileName, FILE_READ|FILE_BIN|FILE_COMMON);
   if(h == INVALID_HANDLE)
      return false;

   const int maxTickets = 4096;
   ulong fileSize = FileSize(h);
   bool ok = false;

   if(fileSize >= 4)
   {
      int count = FileReadInteger(h, INT_VALUE);
      ulong remaining = fileSize - FileTell(h);
      ulong expectedBytes = (ulong)count * (ulong)sizeof(ulong);
      if(count >= 0 && count <= maxTickets && remaining == expectedBytes)
      {
         if(count > 0)
         {
            ArrayResize(tickets, count);
            ok = (FileReadArray(h, tickets) == count);
         }
         else
         {
            ok = true;
         }
      }
      FileSeek(h, 0, SEEK_SET);
   }

   if(!ok && fileSize >= 0 && (fileSize % sizeof(ulong)) == 0)
   {
      int legacyCount = (int)(fileSize / sizeof(ulong));
      if(legacyCount >= 0 && legacyCount <= maxTickets)
      {
         ArrayResize(tickets, legacyCount);
         ok = (legacyCount == 0 || FileReadArray(h, tickets) == legacyCount);
      }
   }

   FileClose(h);

   if(!ok)
   {
      Print(EmojiWarning(), " Ignoring malformed slave-active file: ", fileName, " (size=", fileSize, ")");
      FileDelete(fileName, FILE_COMMON);
      ArrayResize(tickets, 0);
   }

   return ok;
}

void CheckMasterOrphans()
{
   if(!IsBridgeRuntimeEnabled()) return; // Only execute if Bridge is ON

   string activeSlaveFile = "HedgeSlaveActive_" + InpHedgeChannel + ".bin";
   ulong slaveTrackedTickets[];
   bool readSuccess = ReadSlaveTrackedTickets(activeSlaveFile, slaveTrackedTickets);

   if(!readSuccess) return; // Wait until file is available

   // Loop through all active Master positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong masterTicket = PositionGetTicket(i);
      if(PositionSelectByTicket(masterTicket))
      {
         if(IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
         {
            if(SmartHedge_IsProtectedTicket(masterTicket))
               continue;

            long openTime = PositionGetInteger(POSITION_TIME);
            
            // GRACE PERIOD: Give the Slave 15 seconds to receive the signal, 
            // open the trade, and write the file before we start judging it.
            int grace = (InpSlaveMirrorGraceSec > 0 ? InpSlaveMirrorGraceSec : 60);
            if(TimeCurrent() - openTime < grace) continue; 

            bool foundInSlave = false;
            for(int j = 0; j < ArraySize(slaveTrackedTickets); j++)
            {
               if(slaveTrackedTickets[j] == masterTicket)
               {
                  foundInSlave = true;
                  break;
               }
            }

            if(!foundInSlave)
            {
               Print(EmojiShield(), " Orphaned master trade detected. The slave did not mirror ticket #", masterTicket, ". Closing the master trade.");
               Trade.PositionClose(masterTicket);
               
               // Optional: Reset grid tracking if needed
               // int symIdx = GetSymbolIndex(PositionGetString(POSITION_SYMBOL));
               // if(symIdx >= 0) ResetGridTracking(symIdx); 
            }
         }
      }
   }
}
 
//+------------------------------------------------------------------+
//| Unified Runtime Router                                           |
//+------------------------------------------------------------------+
bool IsSlaveModeSelected()
{
   return (BotSystemMode == BOT_MODE_SLAVE);
}

int OnInit()
{
   ChartMode = MBP_DataModeToChartMode(InpDataMode);
   G_RuntimeRole = ResolveRuntimeRoleForCurrentChart();
   ResetSystemSnapshot();

   if(IsSlaveModeSelected())
   {
      SlaveConfig slaveCfg;
      BuildSlaveConfigSnapshot(slaveCfg);
      G_ActiveComputeBackend = COMPUTE_BACKEND_PYTHON;
      Print(EmojiBrain(), " MultiBotPro booting in ", AppModeToText(BotSystemMode),
            " mode | Channel=", slaveCfg.channel);
      return Slave_OnInit();
   }

   MasterConfig masterCfg;
   BuildMasterConfigSnapshot(masterCfg);
   G_ActiveComputeBackend = masterCfg.preferred_backend;
   Print(EmojiBrain(), " MultiBotPro booting in ", AppModeToText(BotSystemMode),
         " | Runtime=", RuntimeRoleToText(G_RuntimeRole),
         " mode | Data=", MBP_DataModeToText(InpDataMode),
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
   if(backend == COMPUTE_BACKEND_DLL) return "DLL";
   if(backend == COMPUTE_BACKEND_PYTHON) return "PYTHON";
   if(backend == COMPUTE_BACKEND_NATIVE) return "NATIVE";
   return "UNKNOWN";
}

void OnDeinit(const int reason)
{
   if(IsSlaveModeSelected())
      Slave_OnDeinit(reason);
   else
      Master_OnDeinit(reason);
}

void OnTimer()
{
   if(IsSlaveModeSelected())
   {
      RefreshSystemSnapshot(false, true, false, false, "");
      Slave_OnTimer();
   }
   else
   {
      Master_OnTimer();
   }
}

void OnTick()
{
   if(IsSlaveModeSelected())
      Slave_OnTick();
   else
      Master_OnTick();
}

void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
{
   if(IsSlaveModeSelected())
      Slave_OnTradeTransaction(trans, request, result);
   else
      Master_OnTradeTransaction(trans, request, result);
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
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


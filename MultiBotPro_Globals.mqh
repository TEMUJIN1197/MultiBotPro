#ifndef MULTIBOTPRO_GLOBALS_MQH
#define MULTIBOTPRO_GLOBALS_MQH

#property copyright "Copyright 2024, MultiBotPro Team"
#property link      "https://multibot.pro"
#property strict

// --- CORE SYSTEM STATE ---
bool   G_IS_DEINIT = false;
bool   G_InitInProgress = false;
bool   IsPaused = false;
bool   GlobalTradingEnabled = true;
bool   G_FastChartSwitchMode = false;

// --- RESET & RECOVERY ---
bool   G_ResetPending = false;
int    G_ResetCycleCount = 0;
ulong  G_ResetTimestamp = 0;
ulong  G_LastLossTime = 0;
ulong  G_ResetTickets[];

// --- FINANCIAL TRACKING ---
double GlobalTotalProfit = 0;
double GlobalTotalLoss = 0;
double DailyGlobalProfit = 0;
double DailyGlobalLoss = 0;
datetime LastGlobalDailyReset = 0;
datetime LastGlobalCheck = 0;

// --- SHARED DATA ---
int    TradingSymbolsCount = 0;
string TradingSymbols[];
string ExcludedSymbols[];
ENUM_TIMEFRAMES Timeframes[7];
bool   TimeframeEnabled[7];
int    G_NextBasketId = 1;

// --- GLOBAL TRACKING ARRAYS ---
SSymbolData   SymbolData[];
SFilterData   FilterTracker[]; // Parallel array to SymbolData

// --- STRATEGY GLOBALS ---
int    G_MA1_Period = 200;
int    G_MA2_Period = 50;
int    G_Box_Lookback = 50;
int    G_ADX_Period = 14;
double G_ADX_MinLevel = 25.0;
double G_CurrencyStrengthDelta = 2.0;
double G_GridMultiplier = 1.0;

// --- UI STATE ---
bool   DashboardCollapsed = false;
bool   TemplatesApplied = false;
bool   ShowManualSection = false;
bool   ShowTradeList = false;
string G_DashboardFocusBaseSymbol = "";
int    DashboardX = 10;
int    DashboardY = 50;
bool   IsDragging = false;
int    DragInteractionX = 0;
int    DragInteractionY = 0;

uint   G_DashboardHeartbeatStartMs = 0;
bool   G_DashboardHeartbeatWasEligible = false;
int    G_EntryGateReason[];
string G_EntryGateMessage[];

bool   G_DashboardDragArmed = false;
int    G_DashboardDragStartX = 0;
int    G_DashboardDragStartY = 0;
string G_LastDashboardButtonHandled = "";
ulong  G_LastDashboardButtonHandledMs = 0;
double Panel_ManualLot = 0.01;
double Dash_Scale = 1.0;
bool   Panel_IsModifying = false;
ulong  Panel_SelectedTicket = 0;
double Panel_SlowPts = 10;
double Panel_FastPts = 100;

// --- GLOBAL POINTERS ---
CChartFactory *G_ChartFactory = NULL;

#endif // MULTIBOTPRO_GLOBALS_MQH

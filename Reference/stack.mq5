//+------------------------------------------------------------------+
//|                                                  MultiBotPro.mq5 |
//|                               Copyright 2023, Expert Advisor Pro |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Expert Advisor Pro"
#property link      "https://discord.com/channels/929723953415589918/929723953415589920"
#property version   "1.00"
#property description "Advanced Multi-Timeframe Multi-Symbol Trading Bot"
#property description "Features: MA Cascade, VWAP Bands, Grid/Stack Modes"
#property description "Multi-Symbol: Trade multiple symbols concurrently"
#property description "Risk Management: Global TP/SL, Dynamic Stake, Box Stops"
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

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+

// Include libraries
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\HistoryOrderInfo.mqh>
#include <Arrays\ArrayObj.mqh>

// 1. INCLUDE DEFINITIONS (Enums & Structs)
#include "MultiBotPro_Defines.mqh"

// --- NEW GLOBAL ---
string RealSymbol; // The actual symbol we trade (e.g. "USTEC")
long MyChartIDs[]; // We will store the ID of every chart we open here


input group "0. Operational Mode and and Timezone Settings"
input ENUM_OP_MODE OperationMode = MODE_MIXED; // Operational Mode
input bool   ForceTimerExecution = false;     // Force OnTick execution every second? (Higher CPU)
input int InpServerGMTOffset  = 2;   // Server Offset from UTC (e.g. 2 for EET)
input int InpNYManualShift    = 0;   // Manual Shift (e.g. +1 or -1 for DST)
input ENUM_RENKO_MODE RenkoMode = RENKO_MODE_AUTO; // Renko Data Mode

// Input parameters for Entry Signals
input group "1. Symbol Settings"
input string ManualSymbols = "";         // Manual Symbols (comma separated)
input bool TradeAllMarketWatch = false;  // Trade All MarketWatch Symbols
input bool UseChartSymbol = false;        // Trade Chart Symbol (if not in list)
input string ExcludeSymbols = "";        // Exclude Symbols (comma separated)

input group "2. Timeframe Settings"
input bool UseM1  = true;           // Use M1
input bool UseM3  = false;          // Use M3 (Default)
input bool UseM15 = false;          // Use M15 (Default)
input bool UseH1  = false;          // Use H1 (Default)
input bool UseH4  = false;          // Use H4 (Default)
input bool UseD1  = false;          // Use D1 (Default)
input bool UseW1  = false;          // Use W1 (Default)

input group "3. Moving Average Settings"
input ENUM_MY_MA_SOURCE MA1_Source = MY_SRC_CLOSE;   // MA1 Source
input int MA1_Period = 5;                     // MA1 Period
input ENUM_MY_MA_METHOD MA1_Method = MY_MODE_EMA;    // MA1 Method

input ENUM_MY_MA_SOURCE MA2_Source = MY_SRC_CLOSE;   // MA2 Source
input int MA2_Period = 10;                     // MA2 Period
input ENUM_MY_MA_METHOD MA2_Method = MY_MODE_EMA;    // MA2 Method

input ENUM_MY_MA_SOURCE MA3_Source = MY_SRC_CLOSE;   // MA3 Source
input int MA3_Period = 20;                     // MA3 Period
input ENUM_MY_MA_METHOD MA3_Method = MY_MODE_EMA;    // MA3 Method

input ENUM_MY_MA_SOURCE MA4_Source = MY_SRC_CLOSE;   // MA4 Source
input int MA4_Period = 50;                    // MA4 Period
input ENUM_MY_MA_METHOD MA4_Method = MY_MODE_EMA;    // MA4 Method

input ENUM_MY_MA_SOURCE MA5_Source = MY_SRC_CLOSE;   // MA5 Source
input int MA5_Period = 200;                    // MA5 Period
input ENUM_MY_MA_METHOD MA5_Method = MY_MODE_EMA;    // MA5 Method

//+------------------------------------------------------------------+
//| 1. General & Bridge Settings                                     |
//+------------------------------------------------------------------+
input group "4. General & Bridge"
input int    MagicNumber          = 12345;           // Magic Number
input string TradeComment         = "MultiBotPro";   // Trade Comment
input int    Slippage             = 3;               // Slippage in Points
input bool   ReverseStrategy      = false;           // Master Switch: Reverse all Buy/Sell signals

sinput string BRIDGE_SETTINGS     = "";
input bool   InpEnableBridge      = true;            // Enable Bridge Mode (Sends Signals)
input bool   InpUseHedgeBridge    = true;            // Enable Limit Checking
input string InpSignalPrefix      = "Signal";        // MUST match RenkoBuilder Input
input string InpHedgeChannel      = "HEDGE_A";       // Must match Master Channel Name

//+------------------------------------------------------------------+
//| 2. Strategy & Entry Signals                                      |
//+------------------------------------------------------------------+
input group "5. Strategy: VWAP Settings"
input bool   UseVWAP              = false;           // Enable VWAP Signals
input bool   RequireVWAPConfirmation = true;         // Require VWAP for entry (if VWAP enabled)

sinput string VWAP_1_CONTINUOUS   = "";
input bool   UseVWAP1             = true;            // Use Continuous VWAP (6PM NY Reset)
input ENUM_APPLIED_PRICE VWAP1_PriceSource = PRICE_TYPICAL; // VWAP1 Price Source
input int    VWAP1_ResetHour      = 18;              // VWAP1 Reset Hour (NY Time)
input int    VWAP1_ResetMinute    = 0;               // VWAP1 Reset Minute

sinput string VWAP_2_ANCHORED     = "";
input bool   UseVWAP2             = true;       // Enable Dynamic VWAP (High/Low)
input ENUM_APPLIED_PRICE VH_Source = PRICE_HIGH; // Source for High VWAP [cite: 3020]
input ENUM_APPLIED_PRICE VL_Source = PRICE_LOW;  // Source for Low VWAP [cite: 3021]

sinput string VWAP_3_SESSION      = "";
input bool   UseVWAP3             = false;           // Use Session VWAP (9:30AM NY Start)
input ENUM_APPLIED_PRICE VWAP3_PriceSource = PRICE_TYPICAL; // VWAP3 Price Source
input int    VWAP3_StartHour      = 9;               // VWAP3 Start Hour (NY Time)
input int    VWAP3_StartMinute    = 30;              // VWAP3 Start Minute

input group "6. Strategy: Filters & Other Modes"
sinput string ADX_FILTER          = "";
input bool   UseADX               = false;           // Use ADX Filter
input int    ADX_Period           = 14;              // ADX Period
input double ADX_MinLevel         = 25.0;            // ADX Threshold Level
input bool   ADX_TradeAbove       = true;            // True = Trend (ADX > Level), False = Range (ADX < Level)

sinput string BOX_TREND_FILTER    = "";
input bool   UseBoxTrendFilter    = false;           // Enable Box Trend Filter
input int    BoxTrend_TFs_Count   = 2;               // Check Lowest X Timeframes (e.g., 2 = M1 & M3)
input bool   BoxTrend_ReqBreakout = false;           // Require Price Breakout on Lowest TF?

sinput string OPENING_RANGE_REVERSAL              = "";
input bool   UseORReversal        = false;           // Enable OR Reversal Strategy
input ENUM_TIMEFRAMES OR_EntryTF  = PERIOD_M5;       // Entry Timeframe for Reversal Patterns
input int    OR_StartHour         = 9;               // Start Hour (NY Time)
input int    OR_StartMinute       = 30;              // Start Minute (NY Time)
input int    OR_WindowMinutes     = 60;              // Trading Window Duration (Minutes)
input double OR_ATR_Threshold     = 0.20;            // Min Range Size (% of Daily ATR)

//+------------------------------------------------------------------+
//| 3. Position Sizing & Stacking                                    |
//+------------------------------------------------------------------+
input group "7. Position Sizing & Risk"
sinput string BASE_RISK           = "";
input ENUM_RISK_TYPE RiskType     = RISK_FIXED_MONEY; // Risk Calculation Type
input double RiskPercent          = 2;             // Risk Percentage (for % modes)
input double FixedLot             = 0.01;          // Fixed Lot Size
input double RiskMoney            = 50.0;          // Risk: Fixed Amount ($)

sinput string SAFETY_CAPS         = "";
input double MaxLotSizePerTrade   = 50;              // Maximum lot size per single trade
input int    MaxSplitTrades       = 10;              // Maximum number of trades to split into
input double MaxSpreadATR         = 0.5;             // Max Spread (xATR) (0=Disabled)

input group "8. Dynamic Stake & Stack Mode"
sinput string DYNAMIC_STAKING     = "";
input bool   UseDynamicStake      = false;            // Enable Dynamic Stake Adjustment
input double EquityThreshold      = 2;               // Equity Change % for Stake Adjustment
input double StakeMultiplier      = 2;               // Stake Multiplier Factor
input double MaxStakeMultiplier   = 20;              // Maximum Stake Multiplier
input double lotCap               = 50;              // Lot Cap Multiplier

sinput string STACK_MODE           = "";
input bool   StackMode            = true;            // Enable Stack Mode
input int    StackStart           = 1;               // Stack Start After Updates
input double StackInitial         = 1;               // Stack Initial Multiplier
input double StackBoost           = 0.25;            // Stack Boost per Level
input double MinStackMultiplier   = 0.1;             // Minimum Stack Multiplier
input double MaxStackMultiplier   = 64;              // Maximum Stack Multiplier

//+------------------------------------------------------------------+
//| 4. Standard Exit Settings                                        |
//+------------------------------------------------------------------+
input group "9. Stop Loss Settings"
input ENUM_SL_TYPE StopLossType   = SL_ATR;          // Stop Loss Type
input ENUM_TIMEFRAMES ATR_Timeframe = PERIOD_CURRENT; // ATR Timeframe (Default: Current)

sinput string ATR_STOP            = "";
input int    ATR_Period           = 100;             // ATR Period
input double ATR_Multiplier       = 5;             // ATR Multiplier

sinput string BOX_PIVOT_STOP        = "";
input int    Box_Lookback         = 2;               // Box Pivot Lookback
input int    Box_SL_Levels        = 2;               // Box SL Levels to Keep
input ENUM_BOX_BREAKOUT_SRC BoxBreakoutMethod = BOX_BREAK_HIGHLOW; // Breakout Detection Source

sinput string MA_STOP             = "";
input int    MA_SL_Period         = 20;              // MA Stop Loss Period
input ENUM_MY_MA_METHOD MA_SL_Method = MY_MODE_EMA;  // MA Stop Loss Method
input ENUM_MY_MA_SOURCE MA_SL_Source = MY_SRC_CLOSE; // MA Stop Loss Source

input group "10. Take Profit Settings"
sinput string TAKE_PROFIT         = "";
input ENUM_TP_TYPE TakeProfitType = TP_ATR;          // Take Profit Type
input double TP_Ratio             = 1.5;             // Risk/Reward Ratio
input double FixedTP              = 100;             // Fixed TP in Points
input double TP_ATR_Multiplier    = 5;             // Take Profit ATR Multiplier

input group "11. Trailing Stop Settings"
sinput string TRAILING_ENABLE     = "";
input bool   UseTrailing          = false;            // Enable Trailing Stop

sinput string TRAILING_CONFIG     = "";
input ENUM_TRAIL_TYPE TrailType   = TRAIL_ATR;       // Trailing Type
input int    TrailBox_Levels      = 6;               // Trail Box Levels
input double TrailATR_Multiplier  = 1;               // Trail ATR Multiplier
input double TrailATR_Update      = 2;               // Trail ATR Update Distance
input ENUM_LOCK_TRAIL LockTrail   = LOCK_TRAIL_TP_HIT; // Lock Trail Until

//+------------------------------------------------------------------+
//| 5. Advanced Recovery (Grid/Zone)                                 |
//+------------------------------------------------------------------+
input group "12. Advanced Grid/Recovery"
sinput string GENERAL_GRID        = "";
input ENUM_RISK_MODE RiskMode     = RISK_MODE_NONE;  // Risk Management Mode
input ENUM_GRID_STRATEGY GridStrategy = GRID_STRAT_AGGRESSIVE;
input bool   UseDynamicProfitScaling = true;
input double GridTP_Amount        = 2;               // Grid Target Profit ($ Amount)
input double GridImpulseATR       = 2;               // Phase 1 Transition Distance (ATR)
input double GridTransitionDist   = 1;               // Phase 2 Transition Distance (ATR)

sinput string AGGRESSIVE_MODE      = "";
input ENUM_GRID_DISTANCE_TYPE GridAggressiveDistType = GRID_DIST_ATR; // Aggressive Grid: Distance Type
input double GridAggressiveRecovDist = 2;            // Aggressive Grid: Base Distance (Points or ATR Mult)
input double GridAggressiveRecovMult = 1.5;          // Aggressive Grid: Distance Multiplier per Level

sinput string CONSERVATIVE_MODE      = "";
input ENUM_GRID_DISTANCE_TYPE GridTransitionType = GRID_DIST_ATR; // Transition Distance Type 
input double GridStakeMultiplier  = 2;               // Grid Stake Multiplier (per level)
input int    GridStakeStartLevel  = 1;               // Grid Stake Start Level (0=from first level)
input double GridMaxStake         = 0;               // Grid Max Stake (0=no limit)

sinput string GRID_DISTANCE      = "";
input ENUM_GRID_DISTANCE_TYPE GridDistanceType = GRID_DIST_ATR; // Grid Distance Type
input double GridDistance         = 4;               // Grid Distance (points or ATR multiples)
input double GridMultiplier       = 1.5;             // Grid Distance Multiplier
input int    GridDistanceStartLevel = 1;             // Grid Distance Start (0 = never)

sinput string GRID_LOT_SIZING      = "";
input bool   UseGridLotPerEquity  = true;            // Use Lot per Equity/Balance?
input double GridLot_Per_Equity_Size = 0.01;         // Lots to use (e.g. 0.01)
input double GridLot_Per_Equity_Step = 10000;        // Per Amount of Balance (e.g. 10000)
// Fallback if above is false:
input ENUM_RISK_TYPE GridRiskType = RISK_PERCENT_EQUITY; // Grid Risk Calculation Type
input double GridRiskPercent      = 0.2;             // Grid Risk Percentage (for % modes)
input double GridFixedLot         = 0.01;            // Grid Fixed Lot Size
input double MinGridDistance      = 20;              // Minimum Grid Distance (points only)
input double MaxGridDistance      = 20000;           // Maximum Grid Distance (points only)
input bool   GridCloseOnTP        = false;           // Close Grid on TP Reach

sinput string ZONE_RECOVERY       = "";
input ENUM_ZONE_GAP_TYPE ZoneGapType = ZONE_GAP_ATR; // Zone Gap Unit
input double ZoneTP_Amount        = 2;               // Zone Target Profit ($)
input double ZoneGapPoints        = 50;              // Zone Gap (Points)
input double ZoneGapATR           = 5;               // Zone Gap (ATR Multiplier)
input double ZoneTargetMult       = 2;               // Recovery Target Distance (x Gap)
input double ZoneImpulseATR       = 2;               // Phase 1 Transition Distance (ATR)
input double ZoneTransitionDist   = 2;               // Transition Distance (ATR) for Phase 2
input bool   ZoneCloseOnTP        = false;           // Close All on Target Reach?

input group "13. Grid Pruning (FIFO)"
sinput string PRUNING_SETTINGS         = "";
input bool   UseGridPruning       = true;           // Enable Trade Pruning
input ENUM_PRUNING_STYLE PruningStyle = PRUNING_SOFT; // Pruning Style (Soft=Oldest, Hard=All)
input int    PruningLevel         = 5;               // Max Grid Levels before pruning(BTCUSD=3)
input bool   UsePruningRecovery   = true;            // Recover Pruned Losses?
input double PruningRecovPercent  = 25.0;            // Recovery % per cycle

//+------------------------------------------------------------------+
//| 6. Time & Scheduling                                             |
//+------------------------------------------------------------------+
input group "14. Trading Sessions"
input bool   UseTimeFilter        = false;           // Enable Timed Trading Windows
input bool   CloseTradesOnSessionExit = false;       // Close all trades when session ends?

sinput string Session1            = ":: SESSION 1 ::";
input bool   UseSession1          = true;
input int    Session1_StartHour   = 8;
input int    Session1_StartMinute = 0;
input int    Session1_EndHour     = 12;
input int    Session1_EndMinute   = 0;

sinput string Session2            = ":: SESSION 2 ::";
input bool   UseSession2          = false;
input int    Session2_StartHour   = 13;
input int    Session2_StartMinute = 0;
input int    Session2_EndHour     = 16;
input int    Session2_EndMinute   = 0;

sinput string Session3            = ":: SESSION 3 ::";
input bool   UseSession3          = false;
input int    Session3_StartHour   = 19;
input int    Session3_StartMinute = 0;
input int    Session3_EndHour     = 23;
input int    Session3_EndMinute   = 0;

input group "15. Days of Week"
sinput string Sep_Days            = ":: TRADE DAYS ::";
input bool   TradeMonday          = true;
input bool   TradeTuesday         = true;
input bool   TradeWednesday       = true;
input bool   TradeThursday        = true;
input bool   TradeFriday          = true;
input bool   TradeSaturday        = true;
input bool   TradeSunday          = true;

input group "16. Scheduled Hard Stops"
input bool   ClosePositionsAtBlockStart = false;     // Close all trades when Hard Block starts?

sinput string DAILY_HARD_BLOCK = "";
input bool   UseCloseBlock        = false;           // Enable Daily Hard Close Block
input int    CloseBlock_StartHour = 16;              // Block Start Hour (e.g. 16 = 4 PM)
input int    CloseBlock_StartMinute = 30;            // Block Start Minute (30)
input int    CloseBlock_EndHour   = 18;              // Block End Hour (18 = 6 PM)
input int    CloseBlock_EndMinute = 0;               // Block End Minute

sinput string FRIDAY_EXIT = "";
input bool   UseFridayHardStop    = false;           // Enable Friday Hard Stop Window
input int    FridayStop_StartHour = 16;              // Window START Hour
input int    FridayStop_StartMinute = 30;            // Window START Minute
input int    FridayStop_EndHour   = 18;              // Window END Hour (Resume after this)
input int    FridayStop_EndMinute = 0;               // Window END Minute

//+------------------------------------------------------------------+
//| 7. News & Event Filters                                          |
//+------------------------------------------------------------------+
input group "17. News Filter (Calendar)"
sinput string NEWS_FILTERS      = "";
input bool   UseNewsFilter        = true;            // Enable Economic Calendar Filter
input bool   NewsIncludeHigh      = true;            // Filter High Impact
input bool   NewsIncludeMedium    = true;            // Filter Medium Impact
input bool   NewsIncludeLow       = false;           // Filter Low Impact
input bool   NewsIncludeHolidays  = true;            // Filter Bank Holidays (All Day Pause)
input bool   NewsFilterSymbolCurrency = true;        // Only filter news for Symbol's currency (Recommended)
input int    NewsMinutesBefore    = 5;               // Minutes Before News to Stop
input int    NewsMinutesAfter     = 5;               // Minutes After News to Resume
input bool   CloseOnNews          = false;           // Close positions before news?

sinput string NEWS_VISUALS     = "";
input bool   ShowNewsLines        = true;            // Show Visual News Lines
input color  NewsColorHigh        = clrRed;          // High Impact (Red)
input color  NewsColorMed         = clrOrange;       // Medium Impact (Orange)
input color  NewsColorLow         = clrYellow;       // Low Impact (Yellow)
input color  NewsColorHoliday     = clrWhite;        // Holiday (White)
input ENUM_LINE_STYLE NewsLineStyle = STYLE_DASHDOTDOT; // Line Style
input bool   NewsWindowColorEnable = true;           // Change Bar Color during News?
input color  NewsWindowColor      = clrMagenta;      // Color during News Window

//+------------------------------------------------------------------+
//| 8. Safety, Limits & Circuit Breakers                             |
//+------------------------------------------------------------------+
input group "18. Circuit Breakers & Limits"
sinput string PERFORMANCE_FILTER      = "";
input ENUM_FILTER_RESET FilterResetMode = FILTER_RESET_DAILY; // Reset Counters Mode
// --- NEW INPUTS START ---
input int    Filter_MaxOpenTrades = 0;       // Max Open Trades Filter (0=Disabled)
input bool   Filter_GlobalTradeCount = false; // Toggle: ON=Global Limit, OFF=Per Symbol Limit
// --- NEW INPUTS END ---
input int    Filter_MaxWins       = 0;               // Max Wins (0=Disabled)
input int    Filter_MaxLosses     = 0;               // Max Losses
input int    Filter_MaxWinStreak  = 0;               // Max Wins in a Row
input int    Filter_MaxLossStreak = 0;               // Max Losses in a Row
input double Filter_MaxPctLoss    = 0;               // Max % Account Loss (Session)
input double Filter_MaxPctGain    = 0;               // Max % Account Gain (Session)
input int    Filter_BlockWins     = 0;               // Max Wins per HTF Block
input int    Filter_BlockLosses   = 0;               // Max Losses per HTF Block

sinput string HARD_MONEY_LIMITS      = "";
input double GlobalTP_Amount      = 0;               // Global Take Profit ($) (0 = Disabled)
input double GlobalSL_Amount      = 0;               // Global Stop Loss ($) (0 = Disabled)
input bool   UseAccountLimits     = true;           // Enable Account Equity Limits
input double AccountProfitLimitPct = 1;           // Max Profit % (of Start Equity)
input double AccountLossLimitPct  = 2.5;            // Max Loss % (of Start Equity)
input bool   RestartAfterLimit    = true;           // Restart Cycle after Limit Hit?
input int AccountLimitCooldownMinutes = 2;        // Cool-Down period (minutes)

//+------------------------------------------------------------------+
//| 9. Visuals & Notifications                                       |
//+------------------------------------------------------------------+
input group "19. Visuals & Dashboard"
sinput string DASHBOARD            = "";
input bool   ShowDashboard        = true;

sinput string BOX_LINE_VISUALS      = "";
input bool   ShowBoxLines         = true;
input int    BoxLines_History     = 200;             // Box Lines: History Bars to Draw
input color  BoxLines_ColorHigh   = clrGreen;        // Box Lines: High Color
input color  BoxLines_ColorLow    = clrRed;          // Box Lines: Low Color
input int    BoxLines_Width       = 1;               // Box Lines: Width (Must be 1 for Styles)
input ENUM_LINE_STYLE BoxLines_Style = STYLE_DASHDOTDOT; // Box Lines: Style

input group "20. Alerts & Notifications"
input bool   EnableAlerts         = true;            // Enable Popup Alerts
input bool   EnableEmailAlerts    = true;            // Enable Email Alerts
input bool   EnablePushAlerts     = true;            // Enable Push Notifications

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
// -------------------------

// --- DASHBOARD GLOBALS ---
bool DashboardCollapsed = false;
bool TemplatesApplied = false;
int  DashboardX = 10;
int  DashboardY = 50;
bool IsDragging = false;
int  DragInteractionX = 0;
int  DragInteractionY = 0;

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

// Global variables
CTrade Trade;
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
#include "MultiBotPro_Dashboard.mqh"
#include "MultiBotPro_Helpers.mqh"
#include "MultiBotPro_Indicators.mqh"
#include "MultiBotPro_Risk.mqh"
#include "MultiBotPro_TradeEntry.mqh"
#include "MultiBotPro_GridZone.mqh"
#include "MultiBotPro_GUI.mqh"

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



//+------------------------------------------------------------------+
//| Expert initialization function (MERGED & UPDATED)                |
//+------------------------------------------------------------------+
int OnInit()
  {
  
  G_IS_DEINIT = false;
  
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

// 2. Build symbol list
   BuildSymbolList();

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

   Print("Analysis Symbol: ", _Symbol);
   Print("Execution Symbol: ", RealSymbol);

   if(TradingSymbolsCount == 0)
     {
      Print("Error: No symbols to trade!");
      return INIT_FAILED;
     }

// 4. Initialize symbol data array
  ArrayResize(SymbolData, TradingSymbolsCount);
   for(int i = 0; i < TradingSymbolsCount; i++)
   {
      // Pass the global RenkoMode setting to the symbol initializer
      if(!InitializeSymbolData(TradingSymbols[i], i, RenkoMode)) 
      {
         Print("Failed to initialize symbol: ", TradingSymbols[i]);
         return INIT_FAILED;
      }
      LoadBankState(i);
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

// 8. Event listening
   // EventSetTimer(1);
   EventSetMillisecondTimer(500);

// Force cleanup of old visual lines
   ObjectsDeleteAll(0, "BoxSeg_");
   ObjectsDeleteAll(0, "BoxVert_");

// Enable dragging
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);

// Create Dashboard
   if(ShowDashboard)
     {
      DestroyDashboard();
      ChartRedraw();
      CreateDashboard();
     }
// Initialize Manual Panel State (Hidden by default)
//ShowManualPanel = true;

// Force Initial Calculation (Box Levels)
   for(int i = 0; i < TradingSymbolsCount; i++)
     {
      if(SymbolData[i].active && SymbolData[i].symbol == _Symbol)
        {
         UpdateBoxLevels(i);
        }
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
   
// --- CRITICAL FIX FOR LAZY LOADER ---
// We reset the array to 0. This signals OnTimer to open the charts.
   ArrayResize(MyChartIDs, 0);
// -----------------------------------

   return INIT_SUCCEEDED;
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
    
   G_IS_DEINIT = true; // Raise the flag first
   ForceDeleteAllBotObjects();
   
// 1. Deinitialize all symbol data (Releases Indicators)
   for(int i = 0; i < ArraySize(SymbolData); i++)
     {
      DeinitializeSymbolData(i);
     }

// 2. Remove timer
   EventKillTimer();

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
void OnTimer()
  {
// --- STRATEGY TESTER CHART MANAGER ---
   if(MQLInfoInteger(MQL_TESTER))
     {
      // 1. OPENING PHASE: If array is empty, open the charts
      if(ArraySize(MyChartIDs) == 0 && TradingSymbolsCount > 0)
        {
         Print(">>> OPENING SECONDARY CHARTS...");
         ArrayResize(MyChartIDs, TradingSymbolsCount);

         for(int i = 0; i < TradingSymbolsCount; i++)
           {
            string sym = TradingSymbols[i];

            if(sym == _Symbol)
              {
               MyChartIDs[i] = ChartID(); // Main chart
              }
            else
              {
               long newID = ChartOpen(sym, PERIOD_CURRENT);
               if(newID > 0)
                 {
                  MyChartIDs[i] = newID;
                  Print("   + Opened: ", sym, " (ID: ", newID, ")");
                 }
               else
                 {
                  MyChartIDs[i] = -1;
                 }
              }
           }
        }

      // 2. ENFORCEMENT PHASE: Check EVERY 3 SECONDS (OPTIMIZED)
      // This ensures that as soon as a chart opens (even late), it gets styled,
      // but we don't waste CPU checking 60 times a minute.
      
      static int styleCheckCounter = 0; // Keeps count between calls
      styleCheckCounter++;
      
      // MODIFIED: Modulo 6 (6 * 0.5s = 3.0s) to maintain original timing
      if(styleCheckCounter % 6 == 0) // Only run when counter is 3, 6, 9...
      {
         for(int i = 0; i < ArraySize(MyChartIDs); i++)
           {
            long id = MyChartIDs[i];

            // Check valid secondary charts
            if(id > 0)
              {
               // Detect if it looks like "Factory Defaults"
               // (Bar Chart [0] is default, or Grid is On)
               long mode = ChartGetInteger(id, CHART_MODE);
               bool grid = (bool)ChartGetInteger(id, CHART_SHOW_GRID);

               // If it is NOT Candlesticks (1) OR the Grid is Visible -> FORCE STYLE
               if(mode != CHART_CANDLES || grid)
                 {
                  // Print("Enforcing Style on Chart: ", id); // Debug
                  ApplyChartStyles(id);
                  ChartRedraw(id);
                 }
              }
           }
      }
     }
   // ---------------------------------------------------------
   // MASTER RESET: SECOND PASS (500ms Later)
   // ---------------------------------------------------------
   if(G_ResetPending && GetTickCount() >= G_ResetTimestamp)
   {
       Print(">>> MASTER RESET: Running Pass 2 (Cleanup)... <<<");
       
       // PASS 2: Run everything again
       ExecuteFullReset();
       
       // STOP
       G_ResetPending = false;
       Print(">>> DOUBLE RESET COMPLETE. <<<");
   }
   
  // ---------------------------------------------------------
   // OPTIONAL: Force Logic Execution (Heartbeat)
   // ---------------------------------------------------------
   if(ForceTimerExecution)
   {
      OnTick();
   }
   
   // ---------------------------------------------------------
   // DASHBOARD UI UPDATE (Throttled via Timer)
   // ---------------------------------------------------------
   if(ShowDashboard)
   {
      // Only update if not dragging to prevent visual stutter
      if(!IsDragging) 
      {
         UpdateDashboard(0); // Index 0 is dummy, dashboard loops itself
      }
   }

// Update VWAP calculations on timer
   static int last_minute = -1;
   MqlDateTime dt;
   TimeCurrent(dt);

   if(dt.min != last_minute)
     {
      last_minute = dt.min;

      // Update VWAP for all symbols
      for(int i = 0; i < ArraySize(SymbolData); i++)
        {
         if(SymbolData[i].active && UseVWAP)
           {
            UpdateVWAP(i);
           }
        }

      // Check for daily reset for each symbol
      for(int i = 0; i < ArraySize(SymbolData); i++)
        {
         if(SymbolData[i].active)
           {
            MqlDateTime last_dt;
            TimeToStruct(SymbolData[i].LastDailyReset, last_dt);
            if(dt.day != last_dt.day)
              {
               SymbolData[i].DailyProfitLoss = 0;
               SymbolData[i].LastDailyReset = TimeCurrent();
               SymbolData[i].NewVWAPHighLowSet = false; // Reset daily high/low flag
              }
           }
        }

      // Check for global daily reset
      MqlDateTime last_global_dt;
      TimeToStruct(LastGlobalDailyReset, last_global_dt);
      if(dt.day != last_global_dt.day)
        {
         DailyGlobalProfit = 0;
         DailyGlobalLoss = 0;
         LastGlobalDailyReset = TimeCurrent();
        }
     }

   for(int i = 0; i < ArraySize(SymbolData); i++)
     {
      if(SymbolData[i].active)
        {
         //PrintDebugValues(i);
        }
     }
  }


//+------------------------------------------------------------------+
//| Expert tick function (FINAL ADJUSTED VERSION)                    |
//+------------------------------------------------------------------+
void OnTick()
{
   // BLOCK EXECUTION if we are shutting down
   if(G_IS_DEINIT || IsStopped()) return;
   
   // --- FIX: SAFETY VALVE (DEATH SPIRAL PREVENTION) ---
   // If we just took a loss, FREEZE logic for 5 seconds.
   // This gives the Hedge Master time to update Global Flags/Locks
   // before we attempt to calculate a recovery trade.
   
   static bool wasPaused = false;
   if(GetTickCount() - G_LastLossTime < 5000) 
   {
       // Optional: Display status on chart
       Comment("⛔ SAFETY PAUSE: Cooling down after loss...");
       wasPaused = true; // Set the flag
       return; 
   }
   else 
   {
      // Only clear it if it was actually showing the warning previously
      if(wasPaused)
      {
         Comment(""); 
         wasPaused = false;
      }
   }
   // ----------------------------------------------------

   // --- FIX: FORCE CHART APPEARANCE IN CODE (Bypass Templates) ---
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
   // --------------------------------------------------------------

   // ==================================================================
   // 1. DETERMINE SYSTEM BLOCK STATUS
   // ==================================================================
   bool systemBlocked = false;

   // A. Check Hedge HARD Block (Limits)
   if(GlobalVariableCheck(InpHedgeChannel + "_STOP_FLAG"))
   {
      if(GlobalVariableGet(InpHedgeChannel + "_STOP_FLAG") > 0.0)
      {
         static long last_warn_stop = 0;
         if(GetTickCount() - last_warn_stop > 86400000) {
            Print("⛔ TRADING BLOCKED: Master Limits Reached (Daily Loss / Max DD).");
            last_warn_stop = GetTickCount();
         }
         RemoveSignalArrows();
         systemBlocked = true;
      }
   }

   // B. Check Hedge PAUSE (Cooldown/Security)
   if(!systemBlocked && GlobalVariableCheck(InpHedgeChannel + "_PAUSE_FLAG"))
   {
      if(GlobalVariableGet(InpHedgeChannel + "_PAUSE_FLAG") > 0.0)
      {
         static long last_warn_pause = 0;
         if(GetTickCount() - last_warn_pause > 10000) { // Warn less frequently
             Print("⚠️ TRADING PAUSED: Master Security Cooldown (Slave Rejected Trade or Close Event).");
             Comment("⚠️ PAUSED: Master Cooldown Active");
             last_warn_pause = GetTickCount();
         }
         systemBlocked = true;
      }
   }
   else if(!systemBlocked) {
       // Clear comment if we were previously paused
       string c = ChartGetString(0, CHART_COMMENT);
       if(StringFind(c, "PAUSED") >= 0) Comment("");
   }

   // C. Global Safety Checks
   if(!systemBlocked && !GlobalTradingEnabled)
   {
      systemBlocked = true;
   }

   // ==================================================================
   // 2. GLOBAL CALCULATIONS (Run regardless of block)
   // ==================================================================
   
   // Check Global Dollar Limits
   CheckGlobalDollarLimits();
   CheckAccountEquityLimits();

   // Check global profit/loss limits periodically
   if(TimeCurrent() - LastGlobalCheck > 60)
   {
      CheckGlobalLimits();
      LastGlobalCheck = TimeCurrent();
   }

   // GLOBAL TIME & NEWS CALCULATIONS
   MqlDateTime dt;
   TimeCurrent(dt);

   // Check Statuses
   bool isFridayStop = false;
   if(UseFridayHardStop && dt.day_of_week == 5)
   {
      if(IsInsideInterval(FridayStop_StartHour, FridayStop_StartMinute, FridayStop_EndHour, FridayStop_EndMinute, dt))
      {
         isFridayStop = true;
      }
   }

   bool isHardBlock = (UseCloseBlock && IsInsideInterval(CloseBlock_StartHour, CloseBlock_StartMinute, CloseBlock_EndHour, CloseBlock_EndMinute, dt)) || isFridayStop;
   string blockReason = isFridayStop ? "Friday Hard Stop Activated" : "Hard Close Block Activated";

   bool isTradingTime = IsTradingTime();
   bool isNews = IsNewsTime(); 

   // Handle Bar Color Toggle
   if(NewsWindowColorEnable)
   {
      if(isNews) HighlightActiveNewsBar();
   }

   // Draw News Lines (Visual)
   DrawNewsLines();

   ManageManualSystem();

   // ==================================================================
   // 3. MAIN LOOP (Refactored for Visual Independence)
   // ==================================================================
   for(int symbolIndex = 0; symbolIndex < ArraySize(SymbolData); symbolIndex++)
   {
      if(!SymbolData[symbolIndex].active)
         continue;
      string symbol = SymbolData[symbolIndex].symbol;
      
      // [OPTIMIZED CODE]
      /*
      if(ShowDashboard && (symbol == _Symbol || symbol == RealSymbol))
      {
         // Static variable retains value between ticks
         static uint lastDashUpdate = 0; 
         
         // Only update if 250ms has passed (4 times per second)
         if(GetTickCount() - lastDashUpdate > 250) 
         {
            UpdateDashboard(symbolIndex);
            lastDashUpdate = GetTickCount();
         }
      }*/

      // --------------------------------------------------------
      // C. STANDARD INDICATOR UPDATES (MOVED UP)
      // We run this BEFORE checking systemBlocked so lines update
      // --------------------------------------------------------
      // Reset flags
      SymbolData[symbolIndex].NonGridSLMovedThisTick = false;
      SymbolData[symbolIndex].GridSLMovedThisTick = false;

      datetime currentTime = iTime(symbol, PERIOD_CURRENT, 0);
      bool isNewBar = (SymbolData[symbolIndex].LastCandleTime != currentTime);

      if(isNewBar)
      {
         SymbolData[symbolIndex].LastCandleTime = currentTime;
         SymbolData[symbolIndex].ProcessedThisCandle = false;
         
         // *** THIS IS THE LOGIC YOU WANTED TO KEEP RUNNING ***
         UpdateBoxLevels(symbolIndex); 
         if(UseVWAP) UpdateVWAP(symbolIndex);
         
         // Run signal logic here instead of every tick
         if(OperationMode != MODE_SEMI_AUTO && !isHardBlock) 
            CheckEntrySignals(symbolIndex);
      }

      UpdatePositionTracking(symbolIndex); // Track positions for Dashboard

      // ========================================================
      // ⛔ GATEKEEPER: STOP HERE IF BLOCKED ⛔
      // ========================================================
      // If we are Hedge Blocked, Global Stopped, or Disabled, 
      // we 'continue' to the next symbol, skipping all Trade Logic below.
      if(systemBlocked) continue; 
      // ========================================================


      // --------------------------------------------------------
      // A. HARD CLOSE BLOCK (Highest Priority)
      // --------------------------------------------------------
      if(isHardBlock)
      {
         if(ClosePositionsAtBlockStart)
         {
            if(PositionsTotal() > 0)
            {
               if(SymbolData[symbolIndex].GridLevels > 0)
                  CloseAllGridPositions(symbolIndex, blockReason);
               if(SymbolData[symbolIndex].PositionCount > 0)
                  CloseAllGlobalPositions(blockReason);
            }
         }
         continue; // Prevent new entries
      }

      // --------------------------------------------------------
      // B. SESSION EXIT & NEWS CLOSE LOGIC
      // --------------------------------------------------------
      if(UseTimeFilter && !isTradingTime && CloseTradesOnSessionExit)
      {
         if(PositionsTotal() > 0)
         {
            CloseAllGridPositions(symbolIndex, "Session Ended - Auto Close");
            CloseAllGlobalPositions("Session Ended - Auto Close");
         }
      }

      if(isNews && CloseOnNews)
      {
         if(PositionsTotal() > 0)
         {
            CloseAllGridPositions(symbolIndex, "News/Holiday - Auto Close");
            CloseAllGlobalPositions("News/Holiday - Auto Close");
         }
      }

      // --------------------------------------------------------
      // D. ENTRY SIGNALS
      // --------------------------------------------------------
      bool allowEntry = isTradingTime && !isNews;

      if(OperationMode == MODE_SEMI_AUTO)
         allowEntry = false;

      if(SymbolData[symbolIndex].PositionCount == 0 && allowEntry)
      {
         if(UseORReversal)
            CheckORReversalSignals(symbolIndex);
         else
            CheckEntrySignals(symbolIndex);
      }

      // --------------------------------------------------------
      // E. MANAGEMENT LOGIC
      // --------------------------------------------------------

      // 1. Calc Trailing & TPs
      ManageAllPositionsOnTick(symbolIndex);

      // 2. Apply Pending Trail
      if(SymbolData[symbolIndex].HasPendingTrail)
         ApplyPendingTrail(symbolIndex);

      // 3. Stack Trades
      CheckStackTradesOnTick(symbolIndex);

      // 4. Grid Logic
      bool gridAllowed = true;
      if(UseORReversal && !SymbolData[symbolIndex].GridInTrailing)
         gridAllowed = false;

      if(RiskMode == RISK_MODE_GRID && gridAllowed && (SymbolData[symbolIndex].GridLevels > 0 || SymbolData[symbolIndex].GridPhase1Active))
      {
         CheckGridOnTick(symbolIndex);
         if(!SymbolData[symbolIndex].GridTargetReached && SymbolData[symbolIndex].GridPhase1Active)
            CheckGridTargetOnTick(symbolIndex);
      }

      // 5. Zone Recovery
      if(RiskMode == RISK_MODE_ZONE_RECOVERY)
         CheckZoneRecovery(symbolIndex);

      // 6. Dynamic Risk
      ManageRisk(symbolIndex);
   }
}

//+------------------------------------------------------------------+
//| Trade transaction handler (FIXED: Handles Debt Repayment)        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      ulong dealTicket = trans.deal;
      if(HistoryDealSelect(dealTicket))
      {
         ENUM_DEAL_ENTRY entryType = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
         
         // We only care when trades CLOSE (Entry Out)
         if(entryType == DEAL_ENTRY_OUT)
         {
            double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
            double swap   = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
            double comm   = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
            double netProfit = profit + swap + comm;
            
            string symbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
            int symbolIndex = GetSymbolIndex(symbol);

            if(symbolIndex >= 0)
            {
               // Update Global Stats
               SymbolData[symbolIndex].DailyProfitLoss += netProfit;
               DailyGlobalProfit += (netProfit > 0 ? netProfit : 0);
               DailyGlobalLoss += (netProfit < 0 ? MathAbs(netProfit) : 0);

               // --- BRIDGE SIGNAL ---
               if(InpEnableBridge)
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
}

//+------------------------------------------------------------------+
//| EVENT HANDLER: Button Clicks & Dragging (OPTIMIZED)              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   // 1. Optimized Drag Handling (Native Object Drag for Manual Panel)
   if(id == CHARTEVENT_OBJECT_DRAG)
   {
      OnPanelDrag(sparam);
      return; 
   }

   // 2. Button Clicks
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      // --- NEWS CLICKS ---
      if(StringFind(sparam, "NewsLine_") >= 0 || StringFind(sparam, "NewsIcon_") >= 0)
      {
         string idStr = StringSubstr(sparam, 9);
         ShowNewsDetails("NewsLine_" + idStr);
      }
      // --- BUTTON: CLOSE ALL (GLOBAL) ---
      else if(sparam == "Btn_CloseAll")
      {
         for(int i=0; i<ArraySize(SymbolData); i++)
         {
            if(SymbolData[i].active)
            {
               CloseAllGridPositions(i, "Manual Global Close");
               ResetGridTracking(i);
            }
         }
         CloseAllGlobalPositions("Manual Global Close");
         Print("Manual Global Close Triggered.");
         ObjectSetInteger(0, "Btn_CloseAll", OBJPROP_STATE, false);
         ChartRedraw(); 
      }
      // --- BUTTON: CLOSE CHART (LOCAL) ---
      else if(sparam == "Btn_CloseChart")
      {
         int idx = GetSymbolIndex(_Symbol);
         if(idx == -1) idx = GetSymbolIndex(RealSymbol);

         if(idx >= 0)
         {
            CloseAllGridPositions(idx, "Manual Chart Close");
            ResetGridTracking(idx);
            Print("Manual Close Triggered for: ", SymbolData[idx].symbol);
         }
         ObjectSetInteger(0, "Btn_CloseChart", OBJPROP_STATE, false);
         ChartRedraw(); 
      }
      // --- BUTTON: MASTER RESET ---
      else if(sparam == "Btn_MasterReset")
      {
         Print(">>> MASTER RESET CLICKED: Running Pass 1 (Immediate)... <<<");
         
         // PASS 1: Run immediately
         ExecuteFullReset(); 
         
         // SETUP PASS 2: Schedule for 500ms later
         G_ResetPending = true;
         G_ResetTimestamp = GetTickCount() + 500; // Target time
         
         // UI Feedback
         ObjectSetInteger(0, "Btn_MasterReset", OBJPROP_STATE, false);         
         ChartRedraw();
      }
      // --- BUTTON: PAUSE ---
      else if(sparam == "Btn_Pause")
      {
         IsPaused = !IsPaused;
         Print(IsPaused ? ">>> BOT PAUSED <<<" : ">>> BOT RESUMED <<<");
         ObjectSetInteger(0, "Btn_Pause", OBJPROP_STATE, false);
         // Force a UI update immediately to reflect color change
         UpdateDashboard(0);
         ChartRedraw(); 
      }
      // --- BUTTON: COLLAPSE ---
      else if(sparam == "Btn_Collapse")
      {
         DashboardCollapsed = !DashboardCollapsed;
         DestroyDashboard();
         CreateDashboard();
         ObjectSetInteger(0, "Btn_Collapse", OBJPROP_STATE, false);
         ChartRedraw();
      }
   }

   // 3. OPTIMIZED MAIN DASHBOARD DRAG (Ghost Dragging)
   if(id == CHARTEVENT_MOUSE_MOVE)
   {  
      // [OPTIMIZATION] Exit immediately if mouse is just hovering
      if(sparam == "0" && !IsDragging) return;

      // --- THROTTLE FIX: Limit Redraws to ~30 FPS ---
      // This prevents the "Laggy" feeling on Renko charts
      static uint lastDraw = 0;
      bool allowRedraw = (GetTickCount() - lastDraw > 30);
      // ----------------------------------------------
      
      int mouseX = (int)lparam;
      int mouseY = (int)dparam;
      int mouseState = (int)StringToInteger(sparam);

      // Recalculate panel dimensions for hit testing
      int rowH = 20;
      int fullHeight = 45 + 20 + (ArraySize(SymbolData) * rowH) + 40 + 60 + 15;
      int panelHeight = DashboardCollapsed ? 30 : fullHeight;
      int panelWidth = 350; // Matched to your dashboard width

      // --- MOUSE BUTTON DOWN (Left Click Held) ---
      if((mouseState & 1) == 1)
      {
         // 1. PRIORITY LOCK: Check Hit Test BEFORE anything else
         // This fixes the "Chart moves instead of panel" issue
         if(mouseX >= DashboardX && mouseX <= (DashboardX + panelWidth) &&
            mouseY >= DashboardY && mouseY <= (DashboardY + panelHeight))
         {
            // Lock chart immediately if we are hovering over the panel while clicking
            ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
         }

         // 2. INITIALIZE DRAG
         if(!IsDragging)
         {
            if(mouseX >= DashboardX && mouseX <= (DashboardX + panelWidth) &&
               mouseY >= DashboardY && mouseY <= (DashboardY + panelHeight))
            {
               IsDragging = true;
               DragInteractionX = mouseX - DashboardX;
               DragInteractionY = mouseY - DashboardY;
            }
         }

         // 3. PROCESS DRAG
         if(IsDragging)
         {
            int newX = mouseX - DragInteractionX;
            int newY = mouseY - DragInteractionY;

            // Boundary Checks
            if(newX < 0) newX = 0;
            if(newY < 0) newY = 0;

            // Update Global Coords
            DashboardX = newX;
            DashboardY = newY;

            // --- PERFORMANCE FIX: GHOST DRAGGING ---
            // MoveDashboard(DashboardX, DashboardY);
            
            ObjectSetInteger(0, "Dash_BG", OBJPROP_XDISTANCE, DashboardX);
            ObjectSetInteger(0, "Dash_BG", OBJPROP_YDISTANCE, DashboardY);
            
            ObjectSetInteger(0, "Dash_Title", OBJPROP_XDISTANCE, DashboardX + 10);
            ObjectSetInteger(0, "Dash_Title", OBJPROP_YDISTANCE, DashboardY + 5);
            
            ChartRedraw();
            lastDraw = GetTickCount(); // Reset timer
         }
      }
      else
      {
         // --- MOUSE BUTTON RELEASED ---
         if(IsDragging)
         {
            IsDragging = false;
            
            // 4. SNAP TO POSITION
            // Now that drag is done, move all the heavy buttons once
            MoveDashboard(DashboardX, DashboardY);
            
            // Unlock Chart
            ChartSetInteger(0, CHART_MOUSE_SCROLL, true); 
            ChartRedraw();
         }
      }
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
   
   Print(">>> Wiped Bank State for ", sym, " (RAM & Disk).");
}

//+------------------------------------------------------------------+
//| Helper: Perform the Full Reset Sequence (Close -> Wipe -> Unlock)|
//+------------------------------------------------------------------+
void ExecuteFullReset()
{
   Print(">>> EXECUTING RESET SEQUENCE (Force Clean) <<<");

   // 1. CLOSE TRADES
   for(int i=0; i<ArraySize(SymbolData); i++)
   {
      if(SymbolData[i].active)
      {
         CloseAllGridPositions(i, "Master Reset");
         ResetGridTracking(i);
      }
   }
   CloseAllGlobalPositions("Master Reset");

   // 2. WIPE MEMORY (Financials & Flags)
   GlobalTotalProfit    = 0.0;
   GlobalTotalLoss      = 0.0;
   DailyGlobalProfit    = 0.0;
   DailyGlobalLoss      = 0.0;
   LastGlobalDailyReset = TimeCurrent();
   InitReferenceEquity();
   IsPaused = false;

   // 3. WIPE PER-SYMBOL STATE
   for(int i=0; i<ArraySize(SymbolData); i++)
   {
      if(SymbolData[i].active)
      {
         WipeBankState(i); // Nuke Debt
         
         SymbolData[i].DailyProfitLoss = 0;
         SymbolData[i].PositionCount   = 0; 
         
         if(ArraySize(FilterTracker) > i) 
         {
             FilterTracker[i].DailyWins        = 0;
             FilterTracker[i].DailyLosses      = 0;
             FilterTracker[i].WinStreak        = 0;
             FilterTracker[i].LossStreak       = 0;
             FilterTracker[i].SessionNetProfit = 0;
             FilterTracker[i].BlockWins        = 0;
             FilterTracker[i].BlockLosses      = 0;
             FilterTracker[i].StopTrading      = false;
             FilterTracker[i].StopReason       = "";
             FilterTracker[i].LastResetTime    = TimeCurrent();
         }
      }
   }

   // 4. CLEAR EXTERNAL LOCKS
   if(GlobalVariableCheck(InpHedgeChannel + "_STOP_FLAG")) 
      GlobalVariableDel(InpHedgeChannel + "_STOP_FLAG");
   if(GlobalVariableCheck(InpHedgeChannel + "_COOLDOWN_TIMER")) 
      GlobalVariableDel(InpHedgeChannel + "_COOLDOWN_TIMER");

   // 5. UNLOCK
   GlobalTradingEnabled = true;
   Print(">>> RESET SEQUENCE FINISHED: System Unlocked. <<<");
   ChartRedraw();
}

//+------------------------------------------------------------------+

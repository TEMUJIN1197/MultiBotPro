//+------------------------------------------------------------------+
//|                                                  HedgeSender.mq5 |
//|                     Master Node (MT4 & MT5 Compatible)           |
//+------------------------------------------------------------------+
#property copyright "Hedge Sender"
#property strict

// Required by hedgeBridge.mqh – allow blocking waits in standalone hedge mode
bool MBP_ShouldAllowBlockingTradeWait(const string reason = "") { return true; }

#include "hedgeBridge.mqh"

#ifdef __MQL5__
#include <Trade\Trade.mqh>
CTrade Trade;
#endif

// --- ENUMS ---
enum ENUM_RISK_MODE_MASTER {
   RISK_STATIC,      // Static Max Drawdown
   RISK_TRAILING     // Trailing Max Loss
};

enum ENUM_TRAIL_BASE {
   TRAIL_BALANCE,    // Based on Balance
   TRAIL_EQUITY,     // Based on Equity
   TRAIL_MAX_BAL_EQ  // Max of Balance or Equity
};

// Global Authorization Flags
bool   G_LicenseValid = false;
string G_LicenseMsg   = "Unverified";

// --- SECURITY INPUTS ---
input group "0. Hedge Master Security"
input string InpLicenseKey = "ENTER_YOUR_KEY"; // Subscription Key

// --- INPUTS ---
input group "1. Risk Settings"
input ENUM_RISK_MODE_MASTER InpRiskMode = RISK_STATIC; // Risk Mode
input double   InpMasterRisk       = 1000.0; // Static: Max Total Drawdown ($)
input double   InpMasterTargetProfit = 2000.0; // Static: Master Profit Target ($)
input double   InpMasterDailyLoss  = 500.0;    // Daily: Max Loss Per Day ($)
input double   InpMasterDailyProfit= 500.0; // Daily Profit Target ($)

input group "2. Trailing Settings (New)"
input double   InpStartingBalance  = 0;      // Starting Balance (0 = Auto-Detect)
input double   InpTrailPercent     = 10.0;   // Trailing Percent (%)
input ENUM_TRAIL_BASE InpTrailBase = TRAIL_BALANCE; // Trailing Basis
input int      InpServerGMTOffset  = 2;      // Server GMT Offset (usually 2 or 3)

input group "3. Slave Settings"
input double   InpSlaveGain        = 100.0;
input string   InpChannelName      = "HEDGE_A";
input int      InpHeartbeat        = 50;     // Heartbeat(ms)
input int      InpKillCooldown     = 3600;   // Slave kill cooldown(s)

// --- GLOBALS ---
CHedgePanel GUI;
string      SignalFileName;
string      StateFileName;
string      FeedbackFileName;
string      ActiveFileName;

double      StartEquity = 0;
double      StartBalance = 0;
int         LastOrdersCount = 0;
long        CurrentResetID = 0;
ulong       m_stop_trading_until = 0;

// Daily Tracking
double      m_day_start_equity = 0.0;
int         m_current_day_of_year = -1;
bool        m_daily_stop_hit = false;
bool        m_total_stop_hit = false;

// Trailing Tracking
double      g_HighWaterMark = 0.0;
double      g_TrailingStopLevel = 0.0;
bool        g_RolloverCheck_00 = false; 
bool        g_RolloverCheck_01 = false; 

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   #ifdef __MQL5__
   Trade.SetTypeFilling(ORDER_FILLING_IOC);
   Trade.SetAsyncMode(false);
   #endif
   
   // --- LICENSE VERIFICATION ---
   if(!VerifyLicense())
   {
      Print("FATAL: Hedge Master initialization aborted due to invalid license.");
      return INIT_FAILED;
   }
   // ----------------------------
   
   SignalFileName   = "HedgeSignal_" + InpChannelName + ".bin";
   StateFileName    = "HedgeState_" + InpChannelName + ".bin";
   FeedbackFileName = "HedgeFeedback_" + InpChannelName + ".bin";
   ActiveFileName   = "HedgeActive_" + InpChannelName + ".bin";

   // 1. Reset ID
   CurrentResetID = (long)GlobalVariableGet(InpChannelName+"_ResetID");
   // FIX: Reload Cooldown Timer from Global Variable to survive restarts
   if(GlobalVariableCheck(InpChannelName + "_COOLDOWN_TIMER")) {
       m_stop_trading_until = (ulong)GlobalVariableGet(InpChannelName + "_COOLDOWN_TIMER");
   }
   if(CurrentResetID == 0) {
      CurrentResetID = GetTickCount();
      GlobalVariableSet(InpChannelName+"_ResetID", (double)CurrentResetID);
   }

   // 2. Equity & Balance Baselines
   if(GlobalVariableCheck(InpChannelName+"_StartEq")) {
      StartEquity = GlobalVariableGet(InpChannelName+"_StartEq");
   } else {
      StartEquity = (InpStartingBalance > 0) ? InpStartingBalance : AccountInfoDouble(ACCOUNT_EQUITY);
      GlobalVariableSet(InpChannelName+"_StartEq", StartEquity);
   }
   
   if(GlobalVariableCheck(InpChannelName+"_StartBal")) {
      StartBalance = GlobalVariableGet(InpChannelName+"_StartBal");
   } else {
      StartBalance = (InpStartingBalance > 0) ? InpStartingBalance : AccountInfoDouble(ACCOUNT_BALANCE);
      GlobalVariableSet(InpChannelName+"_StartBal", StartBalance);
   }
   
   // 3. Trailing
   if(GlobalVariableCheck(InpChannelName+"_HWM")) {
      g_HighWaterMark = GlobalVariableGet(InpChannelName+"_HWM");
      g_TrailingStopLevel = GlobalVariableGet(InpChannelName+"_TrailStop");
   } else {
      g_HighWaterMark = StartEquity;
      g_TrailingStopLevel = g_HighWaterMark * (1.0 - (InpTrailPercent / 100.0));
      GlobalVariableSet(InpChannelName+"_HWM", g_HighWaterMark);
      GlobalVariableSet(InpChannelName+"_TrailStop", g_TrailingStopLevel);
   }

   // 4. Daily
   MqlDateTime dt;
   TimeCurrent(dt);
   m_current_day_of_year = dt.day_of_year;
   if(GlobalVariableCheck(InpChannelName+"_DayStartEq_" + (string)m_current_day_of_year)) {
      m_day_start_equity = GlobalVariableGet(InpChannelName+"_DayStartEq_" + (string)m_current_day_of_year);
   } else {
      m_day_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      GlobalVariableSet(InpChannelName+"_DayStartEq_" + (string)m_current_day_of_year, m_day_start_equity);
   }

   #ifdef __MQL4__
   LastOrdersCount = OrdersTotal();
   #endif
   
   if(!GUI.CreatePanel("HedgeMaster", true)) return(INIT_FAILED);
   GUI.Run();
   
   EventSetMillisecondTimer(InpHeartbeat);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { GUI.Destroy(); EventKillTimer(); }

//+------------------------------------------------------------------+
//| Trailing Update                                                  |
//+------------------------------------------------------------------+
void CheckTrailingUpdate()
{
   if(InpRiskMode != RISK_TRAILING) return;
   double currentVal = 0.0;
   if(InpTrailBase == TRAIL_BALANCE)      currentVal = AccountInfoDouble(ACCOUNT_BALANCE);
   else if(InpTrailBase == TRAIL_EQUITY)  currentVal = AccountInfoDouble(ACCOUNT_EQUITY);
   else                                   currentVal = MathMax(AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY));

   if(currentVal > g_HighWaterMark) {
      g_HighWaterMark = currentVal;
      double newStop = g_HighWaterMark * (1.0 - (InpTrailPercent / 100.0));
      if(newStop > g_TrailingStopLevel) {
         g_TrailingStopLevel = newStop;
         GlobalVariableSet(InpChannelName+"_HWM", g_HighWaterMark);
         GlobalVariableSet(InpChannelName+"_TrailStop", g_TrailingStopLevel);
         Print(">>> TRAILING UPDATE: New HWM: ", g_HighWaterMark, " | New Hard Stop: ", g_TrailingStopLevel);
      }
   }
}

//+------------------------------------------------------------------+
//| OnTimer                                                          |
//+------------------------------------------------------------------+
void OnTimer()
{
   // --- CONTINUOUS LICENSE VERIFICATION ---
   static ulong last_auth_time = 0;
   // Check every 1 Hour (3,600,000 ms)
   if(GetTickCount() - last_auth_time > 21600000) 
   {
      Print("🔄 Running background license verification...");
      if(!VerifyLicense())
      {
         Print("⛔ SUBSCRIPTION EXPIRED MID-SESSION. Executing hard shutdown.");
         CloseAllMasterTrades(); // Protect equity
         ExpertRemove();         // Remove EA from chart
         return;
      }
      last_auth_time = GetTickCount();
   }
   // ---------------------------------------
   
   if(CurrentResetID == 0) CurrentResetID = GetTickCount();
   string MasterFile = "HedgeMaster_" + InpChannelName + ".bin";
   string SlaveFile  = "HedgeSlave_" + InpChannelName + ".bin";

   // --- 1. HANDLE FEEDBACK (KILL SWITCH) ---
   if(FileIsExist(FeedbackFileName, FILE_COMMON)) 
   {
       int h = FileOpenRobust(FeedbackFileName, FILE_READ|FILE_BIN|FILE_COMMON);
       if(h != INVALID_HANDLE) 
       {
           HedgeFeedback fb;
           ZeroMemory(fb);
           if(FileReadStruct(h, fb) > 0) 
           {
               FileClose(h);
               bool deleteFile = false;
               if(fb.action == 1) 
               {
                   Print(">>> [CRITICAL] SLAVE REJECTED TRADE (Ticket: ", fb.master_ticket, "). CLOSING NOW.");
                   
                   // FIX: ENFORCE LONG PENALTY PAUSE (5 Minutes)
                   // This prevents MultiBotPro from immediately re-opening the invalid trade
                   m_stop_trading_until = GetTickCount() + 300000; 
                   
                   // Trigger the Pause Flag Immediately
                   GlobalVariableSet(InpChannelName + "_PAUSE_FLAG", 1.0);
                   GlobalVariableSet(InpChannelName + "_COOLDOWN_TIMER", (double)m_stop_trading_until);
                   
                   #ifdef __MQL5__
                   if(PositionSelectByTicket(fb.master_ticket)) {
                       Trade.SetTypeFilling(ORDER_FILLING_IOC);
                       if(Trade.PositionClose(fb.master_ticket)) deleteFile = true;
                   } else deleteFile = true;
                   #else
                   if(OrderSelect((int)fb.master_ticket, SELECT_BY_TICKET)) {
                       if(OrderClose(OrderTicket(), OrderLots(), OrderClosePrice(), 3, clrRed)) deleteFile = true;
                   } else deleteFile = true;
                   #endif
               }
               if(deleteFile) FileDelete(FeedbackFileName, FILE_COMMON);
           }
           else FileClose(h);
       }
   }

   // --- 2. TRAILING ROLLOVER ---
   if(InpRiskMode == RISK_TRAILING)
   {
      MqlDateTime dt;
      TimeCurrent(dt);
      if(dt.hour == 0 && !g_RolloverCheck_00) { CheckTrailingUpdate(); g_RolloverCheck_00 = true; }
      if(dt.hour != 0) g_RolloverCheck_00 = false;
      if(dt.hour == 1 && !g_RolloverCheck_01) { CheckTrailingUpdate(); g_RolloverCheck_01 = true; }
      if(dt.hour != 1) g_RolloverCheck_01 = false;
   }

   // --- 3. LIMITS & STATE ---
   CheckLimits(); // Run Limit Logic first

   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.day_of_year != m_current_day_of_year) {
      m_current_day_of_year = dt.day_of_year;
      m_day_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      m_daily_stop_hit = false;
      // Clear flags on new day
      GlobalVariableSet(InpChannelName + "_STOP_FLAG", 0.0);
      GlobalVariableSet(InpChannelName + "_PAUSE_FLAG", 0.0);
      GlobalVariableSet(InpChannelName+"_DayStartEq_" + IntegerToString(m_current_day_of_year), m_day_start_equity);
   }

   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double totalPnL = currentEquity - StartEquity;
   double balancePnL = currentBalance - StartBalance;
   double dailyPnL = currentEquity - m_day_start_equity;
   
   double slave_pnl_read = 0.0;
   if(FileIsExist(SlaveFile, FILE_COMMON)) {
       int h = FileOpen(SlaveFile, FILE_READ|FILE_BIN|FILE_COMMON);
       if(h != INVALID_HANDLE) {
           HedgeState slaveSt;
           ZeroMemory(slaveSt);
           FileReadStruct(h, slaveSt);
           FileClose(h);
           slave_pnl_read = slaveSt.slave_pnl;
       }
   }

   static HedgeState state;
   state.master_current_equity = currentEquity;
   state.master_start_equity   = StartEquity;
   // --- FIX: DECOUPLE RISK FROM EQUITY ---
   if(InpRiskMode == RISK_STATIC) {
      state.master_target_risk = InpMasterRisk;
   } 
   else { // RISK_TRAILING
      // If user defined a manual balance (e.g. 5000), calculate risk on THAT.
      if(InpStartingBalance > 0) {
          state.master_target_risk = InpStartingBalance * (InpTrailPercent / 100.0);
      } 
      else {
          // Otherwise use the standard mathematical trail distance
          state.master_target_risk = StartEquity - g_TrailingStopLevel;
      }
   }
   // --------------------------------------
   
   state.master_target_profit  = InpMasterTargetProfit;
   state.master_daily_limit    = InpMasterDailyLoss;
   state.master_daily_target   = InpMasterDailyProfit;
   state.master_daily_pnl      = dailyPnL;
   state.master_pnl            = totalPnL;
   state.master_balance_pnl    = balancePnL;
   state.master_pnl            = totalPnL;
   state.slave_target_gain     = InpSlaveGain;
   state.slave_pnl             = slave_pnl_read;
   state.last_heartbeat        = GetTickCount();
   state.reset_id              = CurrentResetID;
   state.is_daily_stopped      = m_daily_stop_hit;
   state.is_total_stopped      = m_total_stop_hit;
   
   // --- NEW: SEND PAUSE STATUS ---
   // If we are in a Cooldown (Rogue trade penalty or startup), tell the Slave!
   state.is_paused = (GetTickCount() < m_stop_trading_until); 
   // ------------------------------

   // WRITE STATE
   int h = FileOpen(MasterFile, FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(h != INVALID_HANDLE) { FileWriteStruct(h, state); FileClose(h); }
   
   // HANDLE RESET
   if(GUI.CheckResetRequest()) {
      // 1. RESET PnL TO 0 (Always use Current Equity)
      StartEquity = currentEquity;
      GlobalVariableSet(InpChannelName+"_StartEq", StartEquity);
      
      StartBalance = currentBalance; 
      GlobalVariableSet(InpChannelName+"_StartBal", StartBalance); 
      
      m_day_start_equity = currentEquity;
      GlobalVariableSet(InpChannelName+"_DayStartEq_" + IntegerToString(m_current_day_of_year), m_day_start_equity);
      
      // 2. RESET TRAILING STOPS
      // If using Manual Balance, we set the HWM relative to that, 
      // effectively giving you a "fresh" 10% buffer starting now.
      double trailBase = (InpStartingBalance > 0) ? InpStartingBalance : StartEquity;
      
      g_HighWaterMark = trailBase; 
      g_TrailingStopLevel = g_HighWaterMark * (1.0 - (InpTrailPercent / 100.0));
      
      GlobalVariableSet(InpChannelName+"_HWM", g_HighWaterMark);
      GlobalVariableSet(InpChannelName+"_TrailStop", g_TrailingStopLevel);
      
      // 3. CLEAR FLAGS
      m_daily_stop_hit = false;
      m_total_stop_hit = false;
      m_stop_trading_until = 0;
      
      GlobalVariableDel(InpChannelName + "_COOLDOWN_TIMER");
      GlobalVariableSet(InpChannelName + "_STOP_FLAG", 0.0);
      GlobalVariableSet(InpChannelName + "_PAUSE_FLAG", 0.0);
      
      state.is_daily_stopped = false;
      state.is_total_stopped = false;
      
      // 4. FORCE IMMEDIATE STATE UPDATE (Visual Fix)
      state.master_pnl = 0; // Visual 0
      state.master_daily_pnl = 0;
      
      // Update Risk in State immediately so panel doesn't flicker
      if(InpRiskMode == RISK_STATIC) state.master_target_risk = InpMasterRisk;
      else {
          if(InpStartingBalance > 0) state.master_target_risk = InpStartingBalance * (InpTrailPercent / 100.0);
          else state.master_target_risk = StartEquity - g_TrailingStopLevel;
      }

      // 5. INCREMENT RESET ID
      long newID = (long)TimeCurrent();
      if(newID <= CurrentResetID) newID = CurrentResetID + 1;
      CurrentResetID = newID;
      state.reset_id = CurrentResetID;
      GlobalVariableSet(InpChannelName+"_ResetID", (double)CurrentResetID);
      
      // 6. SAVE TO FILE
      int hFlush = FileOpenRobust(MasterFile, FILE_WRITE|FILE_BIN|FILE_COMMON);
      if(hFlush != INVALID_HANDLE) { 
         FileWriteStruct(hFlush, state); 
         FileClose(hFlush); 
      }
      
      //PlaySound("Ok.wav");
      Print(" >> MASTER RESET. PnL Reset to 0. Risk Calculation Base: ", (InpStartingBalance > 0) ? InpStartingBalance : StartEquity);
   }

   GUI.UpdateStats(state);
   #ifdef __MQL4__
   if(OrdersTotal() != LastOrdersCount) { ScanMT4Trades(); LastOrdersCount = OrdersTotal(); }
   #endif
   BroadcastActiveTrades();
   UpdateActiveTradeList();
}

//+------------------------------------------------------------------+
//| MT5 Trade Detection (Event Based) - HARDENED ROGUE SECURITY      |
//+------------------------------------------------------------------+
#ifdef __MQL5__
void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      ulong dealTicket = trans.deal;
      if(HistoryDealSelect(dealTicket))
      {
         long entry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
         ulong orderTicket = (ulong)HistoryDealGetInteger(dealTicket, DEAL_ORDER);

         // --- ROGUE TRADE SECURITY (HARDENED) ---
         if(entry == DEAL_ENTRY_IN) 
         {
             // Check internal state
             bool isStopped = (m_daily_stop_hit || m_total_stop_hit || GetTickCount() < m_stop_trading_until);
             
             // Check external flag (Double verify)
             if(!isStopped && GlobalVariableCheck(InpChannelName + "_STOP_FLAG")) {
                 if(GlobalVariableGet(InpChannelName + "_STOP_FLAG") > 0.1) isStopped = true;
             }

             if(isStopped) {
                 Print(" >>> SECURITY ALERT: Rogue Trade Detected during Cooldown! Closing Ticket: ", orderTicket);
                 
                 // 1. RE-ENFORCE LOCK IMMEDIATELY (Fix race condition)
                 // We set this BEFORE closing to ensure any parallel threads see it instantly.
                 GlobalVariableSet(InpChannelName + "_STOP_FLAG", 1.0);
                 
                 // 2. EXTEND COOLDOWN (Punishment)
                 // Add 10 seconds penalty to prevent CPU spikes from rapid loops
                 ulong penaltyTime = GetTickCount() + 10000; 
                 if(penaltyTime > m_stop_trading_until) {
                     m_stop_trading_until = penaltyTime;
                     GlobalVariableSet(InpChannelName + "_COOLDOWN_TIMER", (double)m_stop_trading_until);
                 }

                 // 3. Close the Rogue Trade
                 Trade.PositionClose(orderTicket);
                 return; 
             }
         }

         // Normal Signal Processing
         if(m_daily_stop_hit || m_total_stop_hit || GetTickCount() < m_stop_trading_until) return;

         string sym = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
         HedgeSignal signal;
         ZeroMemory(signal);
         
         signal.time_msc = GetTickCount();
         signal.ticket   = orderTicket;
         StringToCharArray(sym, signal.symbol);

         // --- CASE 1: NEW TRADE OPENED ---
         if(entry == DEAL_ENTRY_IN) 
         {
            signal.action = 1; // OPEN
            signal.lots   = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
            long type     = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
            signal.type   = (type == DEAL_TYPE_BUY) ? 0 : 1;
            
            // Capture Comment
            string cmt = HistoryDealGetString(dealTicket, DEAL_COMMENT);
            if(cmt == "" || cmt == "0" || StringFind(cmt, "sl") >= 0 || StringFind(cmt, "tp") >= 0)
            {
               if(HistoryOrderSelect(orderTicket)) {
                  string orderCmt = HistoryOrderGetString(orderTicket, ORDER_COMMENT);
                  if(orderCmt != "") cmt = orderCmt;
               }
            }
            StringToCharArray(cmt, signal.comment);
            
            // Get SL/TP
            double sl = 0, tp = 0;
            if(PositionSelectByTicket(orderTicket)) {
               sl = PositionGetDouble(POSITION_SL);
               tp = PositionGetDouble(POSITION_TP);
            }
            else if(HistoryOrderSelect(orderTicket)) {
               sl = HistoryOrderGetDouble(orderTicket, ORDER_SL);
               tp = HistoryOrderGetDouble(orderTicket, ORDER_TP); 
            }

            double openPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
            double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
            if(pt == 0) pt = 1.0;

            if(sl > 0) signal.sl_dist_points = MathAbs(openPrice - sl) / pt;
            else       signal.sl_dist_points = 0;
            
            if(tp > 0) signal.tp_dist_points = MathAbs(openPrice - tp) / pt;
            else       signal.tp_dist_points = 0;

            // Risk Money Calc
            if(sl > 0) {
                double tickVal  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
                double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
                if(tickSize == 0) tickSize = pt;
                double riskPoints = MathAbs(openPrice - sl);
                signal.risk_money = (riskPoints / tickSize) * tickVal * signal.lots;
            } else {
                signal.risk_money = 0;
            }
            
            WriteSignal(signal);
         }
         
         // --- CASE 2: TRADE CLOSED ---
         else if(entry == DEAL_ENTRY_OUT) 
         {
            signal.action = 2; // CLOSE
            WriteSignal(signal);
         }
      }
   }
}
#endif
//+------------------------------------------------------------------+
//| Helper: Broadcast Active Trades (Fixed for Multibot)             |
//+------------------------------------------------------------------+
void BroadcastActiveTrades()
{
   // 1. Safety Checks
   if(m_daily_stop_hit || m_total_stop_hit || GetTickCount() < m_stop_trading_until) return;

   int total = PositionsTotal();
   if(total == 0) return;

   // --- FIX: SEARCH FOR THE CORRECT POSITION ---
   // Instead of grabbing the last one, we look for the one matching our Symbol
   // and (optional) Magic Number if you have one.
   
   ulong targetTicket = 0;
   
   // Loop through all positions to find the relevant one
   for(int i = total-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         string sym = PositionGetString(POSITION_SYMBOL);
         
         // Filter: Only broadcast trades for the symbol this Master is running on
         // (Or remove this check if you want to broadcast the 'latest' of any symbol)
         //if(sym == _Symbol) 
         //{
            targetTicket = ticket;
            break; // Found the most recent trade for THIS symbol
         //}
      }
   }
   
   // If no relevant trade found, exit
   if(targetTicket == 0) return;
   // -------------------------------------------

   if(PositionSelectByTicket(targetTicket))
   {
      HedgeSignal sig;
      sig.ticket = targetTicket;
      sig.lots   = PositionGetDouble(POSITION_VOLUME);
      sig.type   = (int)PositionGetInteger(POSITION_TYPE);
      
      string sym = PositionGetString(POSITION_SYMBOL);
      StringToCharArray(sym, sig.symbol);
      
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      
      // Calculate Distances
      sig.sl_dist_points = (sl > 0) ? MathAbs(open - sl) / SymbolInfoDouble(sym, SYMBOL_POINT) : 0;
      sig.tp_dist_points = (tp > 0) ? MathAbs(open - tp) / SymbolInfoDouble(sym, SYMBOL_POINT) : 0;
      
      // Calculate Money Risk
      if(sl > 0) {
         double riskPoints = MathAbs(open - sl);
         double tickVal    = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
         double tickSize   = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
         if(tickSize == 0) tickSize = _Point;
         
         sig.risk_money = (riskPoints / tickSize) * tickVal * sig.lots;
      } else {
         sig.risk_money = 0; 
      }
      
      sig.time_msc = PositionGetInteger(POSITION_TIME_MSC);
      sig.action = 1; // OPEN/UPDATE
      
      // --- FIX: CAPTURE POSITION COMMENT ---
      string cmt = PositionGetString(POSITION_COMMENT);
      StringToCharArray(cmt, sig.comment);
      // -------------------------------------
      
      // USE ROBUST WRITER
      int h = FileOpenRobust(SignalFileName, FILE_WRITE|FILE_BIN|FILE_COMMON);
      if(h != INVALID_HANDLE) {
         FileWriteStruct(h, sig);
         FileClose(h);
      }
   }
}

//+------------------------------------------------------------------+
//| MT4 Trade Detection (Polling Helper)                             |
//+------------------------------------------------------------------+
#ifdef __MQL4__
void ScanMT4Trades()
{
   // 1. CRITICAL: STRICT BLOCK
   if(m_daily_stop_hit || m_total_stop_hit) return;
   
   // --- NEW: COOLDOWN CHECK ---
   if(GetTickCount() < m_stop_trading_until) return;
   // ---------------------------
   // Check for New Orders
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         // You would need a tracking array to know if this specific ticket is new.
         // For this example, we assume if OrdersTotal changed, the last one is new.
         // In production, track tickets in an array.
         
         if(OrderOpenTime() > TimeCurrent()-2) // Just opened
         {
             HedgeSignal signal;
             signal.time_msc = GetTickCount();
             signal.ticket   = (ulong)OrderTicket();
             signal.action   = 1;
             // NEW
             signal.lots     = OrderLots();
             signal.type     = (OrderType() == OP_BUY) ? 0 : 1;
             string sym = OrderSymbol();
             StringToCharArray(sym, signal.symbol);
             
             // --- FIX: CAPTURE MT4 COMMENT ---
             string cmt = OrderComment();
             StringToCharArray(cmt, signal.comment);
             // --------------------------------
             
             double price = OrderOpenPrice();
            if(OrderStopLoss() > 0) 
            {
                signal.sl_dist_points = MathAbs(price - OrderStopLoss());
                
                // Calculate MT4 Dollar Risk
                double tickVal  = MarketInfo(sym, MODE_TICKVALUE);
                double tickSize = MarketInfo(sym, MODE_TICKSIZE);
                if(tickSize == 0) tickSize = Point;
                
                signal.risk_money = (signal.sl_dist_points / tickSize) * tickVal * signal.lots;
            } 
            else 
            {
                signal.sl_dist_points = 0;
                signal.risk_money = 0.0;
            }
            
            if(OrderTakeProfit() > 0) signal.tp_dist_points = MathAbs(price - OrderTakeProfit());
            else signal.tp_dist_points = 0;
            
            WriteSignal(signal);
             return;
             // Only process one change at a time
         }
      }
   }
   
   // Check History for Closed (Simplified)
   int histTotal = OrdersHistoryTotal();
   if(OrderSelect(histTotal-1, SELECT_BY_POS, MODE_HISTORY))
   {
      if(OrderCloseTime() > TimeCurrent()-2) 
      {
         HedgeSignal signal;
         signal.time_msc = GetTickCount();
         signal.ticket   = (ulong)OrderTicket();
         signal.action   = 2;
         // CLOSE
         string sym = OrderSymbol();
         StringToCharArray(sym, signal.symbol);
         WriteSignal(signal);
      }
   }
}
#endif

//+------------------------------------------------------------------+
//| Helper: Write Signal (Queue Mode - Append, don't Overwrite)      |
//+------------------------------------------------------------------+
void WriteSignal(HedgeSignal &sig)
{
   // 1. Try to open with READ|WRITE to allow Appending
   int handle = FileOpen(SignalFileName, FILE_READ|FILE_WRITE|FILE_BIN|FILE_COMMON);
   
   // 2. If file doesn't exist, create it
   if(handle == INVALID_HANDLE) {
      handle = FileOpen(SignalFileName, FILE_WRITE|FILE_BIN|FILE_COMMON);
   }

   if(handle != INVALID_HANDLE) { 
      // 3. Move pointer to the end of the file to APPEND
      FileSeek(handle, 0, SEEK_END);
      
      FileWriteStruct(handle, sig); 
      FileClose(handle);
   }
}

//+------------------------------------------------------------------+
//| EVENT HANDLER: REQUIRED FOR MOVING THE PANEL & BUTTON CLICKS     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   GUI.ChartEvent(id, lparam, dparam, sparam);
}

//+------------------------------------------------------------------+
//| Helper: Close All Master Trades (Smart Pause for Market Closed)  |
//+------------------------------------------------------------------+
void CloseAllMasterTrades()
{
   // 1. SMART RETRY TIMER
   // Use a static variable to remember when we are allowed to try again
   static ulong next_attempt_time = 0;
   if(GetTickCount() < next_attempt_time) return; 

   // Default: Set next attempt to 1 second from now
   next_attempt_time = GetTickCount() + 1000;
   
   bool any_closed = false;
   bool critical_error = false;

#ifdef __MQL5__
   for(int i=PositionsTotal()-1; i>=0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0) {
         // Attempt Close
         if(!Trade.PositionClose(ticket)) {
            int err = GetLastError();
            
            // 2. DETECT MARKET CLOSED (10018) OR DISABLED (10027)
            if(err == 10018 || err == 10027 || err == 4756) {
               Print(" >> WARN: Market Closed/Disabled for Ticket ", ticket, ". Pausing Emergency Close for 5 MINUTES.");
               critical_error = true;
               break; // Stop looping, wait for timeout
            }
            else {
               Print("Order Close Failed (", err, "). Retrying shortly...");
            }
         } else {
            any_closed = true;
         }
      }
   }
#else
   for(int i=OrdersTotal()-1; i>=0; i--) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         int type = OrderType();
         if(type <= 1) { // Buy or Sell
            double price = (type==OP_BUY) ? SymbolInfoDouble(OrderSymbol(),SYMBOL_BID) : SymbolInfoDouble(OrderSymbol(),SYMBOL_ASK);
            
            if(!OrderClose(OrderTicket(), OrderLots(), price, 3, clrRed)) {
               int err = GetLastError();
               // MT4 Market Closed Errors
               if(err == 132 || err == 133) { 
                   Print(" >> WARN: Market Closed for Ticket ", OrderTicket(), ". Pausing Emergency Close for 5 MINUTES.");
                   critical_error = true;
                   break;
               }
            } else {
               any_closed = true;
            }
         }
      }
   }
#endif
   
   // 3. SET LONG PAUSE IF MARKET IS CLOSED
   if(critical_error) {
      // Pause for 5 minutes (300,000 ms) to stop log spam
      next_attempt_time = GetTickCount() + 300000; 
   }
   
   if(any_closed) Print(" >> LIMIT ENFORCEMENT: Master Trades Closed.");
}
//+------------------------------------------------------------------+
//| CheckLimits (FIXED: Separated Hard Stop from Pause)              |
//+------------------------------------------------------------------+
void CheckLimits()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double totalPnL = currentEquity - StartEquity;
   double dailyPnL = currentEquity - m_day_start_equity;
   
   // 1. Check Hard Limits
   // A. DAILY LOSS
   if(!m_daily_stop_hit && dailyPnL <= -InpMasterDailyLoss) {
      m_daily_stop_hit = true;
      Print(" !! DAILY LOSS LIMIT HIT. STOPPING.");
      CloseAllMasterTrades();
   }
   
   // B. NEW: DAILY PROFIT TARGET
   if(!m_daily_stop_hit && dailyPnL >= InpMasterDailyProfit) {
      m_daily_stop_hit = true;
      Print(" $$ DAILY PROFIT TARGET HIT. STOPPING.");
      CloseAllMasterTrades();
   }

   if(!m_total_stop_hit) {
      if(totalPnL >= InpMasterTargetProfit) {
         m_total_stop_hit = true;
         Print(" $$ PROFIT TARGET HIT. STOPPING.");
         CloseAllMasterTrades();
      }
      else {
         if(InpRiskMode == RISK_STATIC) {
             if(totalPnL <= -InpMasterRisk) {
                m_total_stop_hit = true;
                Print(" !! MAX DRAWDOWN HIT. STOPPING.");
                CloseAllMasterTrades();
             }
         } else {
             if(currentEquity <= g_TrailingStopLevel) {
                 m_total_stop_hit = true;
                 Print(" !! TRAILING STOP HIT. STOPPING.");
                 CloseAllMasterTrades();
             }
         }
      }
   }

   // 2. Set HARD STOP Flag (Only for Limits)
   if(m_daily_stop_hit || m_total_stop_hit) {
      GlobalVariableSet(InpChannelName + "_STOP_FLAG", 1.0);
   } else {
      // FIX: Do not clear flag if it was set by SECURITY (Rogue Trade)
      // We check if the PAUSE flag is also active. If paused, we assume a security event 
      // is in progress and KEEP the Stop Flag.
      if(GlobalVariableGet(InpChannelName + "_PAUSE_FLAG") == 0.0) 
      {
          if(GlobalVariableGet(InpChannelName + "_STOP_FLAG") > 0.0)
             GlobalVariableSet(InpChannelName + "_STOP_FLAG", 0.0);
      }
   }

   // 3. Set PAUSE Flag (For Cooldowns/Kill Switch)
   if(GetTickCount() < m_stop_trading_until) {
      GlobalVariableSet(InpChannelName + "_PAUSE_FLAG", 1.0);
   } else {
      if(GlobalVariableGet(InpChannelName + "_PAUSE_FLAG") > 0.0)
         GlobalVariableSet(InpChannelName + "_PAUSE_FLAG", 0.0);
   }
}

void OnTick()
{
   // 1. Run Limit Check First (Sets the Global Flag)
   CheckLimits();
   
   // 2. Strict Exit
   if(m_daily_stop_hit || m_total_stop_hit) return;
   
   #ifdef __MQL4__
   ScanMT4Trades(); 
   #endif
}

//+------------------------------------------------------------------+
//| HELPER: Update Active Trade List (For Slave Security Check)      |
//+------------------------------------------------------------------+
void UpdateActiveTradeList()
{
   // 1. Collect All Open Tickets on Master
   ulong tickets[];
   int total = PositionsTotal();
   int count = 0;
   
   for(int i=0; i<total; i++) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket)) {
         // Optional: Filter by Symbol if Master runs multiple strats on same account
         // if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         
         count++;
         ArrayResize(tickets, count);
         tickets[count-1] = ticket;
      }
   }
   
   // 2. Write to "HedgeActive_CHANNEL.bin"
   // The Slave reads this to verify trades still exist.
   int h = FileOpenRobust(ActiveFileName, FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(h != INVALID_HANDLE) {
      FileWriteInteger(h, count);           // Write Count
      if(count > 0) FileWriteArray(h, tickets); // Write Array
      FileClose(h);
   }
}

//+------------------------------------------------------------------+
//| LICENSE VERIFICATION HELPERS                                     |
//+------------------------------------------------------------------+

// Rebuilds the obfuscated URL at runtime
string GetAuthURL()
{
   uchar secret_url[] = {104, 116, 116, 112, 115, 58, 47, 47, 115, 99, 114, 105, 112, 116, 46, 103, 111, 111, 103, 108, 101, 46, 99, 111, 109, 47, 109, 97, 99, 114, 111, 115, 47, 115, 47, 65, 75, 102, 121, 99, 98, 122, 95, 54, 57, 71, 75, 45, 68, 99, 81, 86, 70, 78, 50, 109, 66, 97, 86, 74, 78, 67, 121, 122, 121, 54, 71, 76, 107, 51, 111, 120, 51, 55, 115, 105, 68, 86, 87, 114, 102, 45, 71, 97, 102, 110, 53, 108, 79, 71, 65, 99, 103, 119, 106, 108, 107, 81, 75, 84, 71, 49, 73, 87, 56, 118, 52, 111, 65, 47, 101, 120, 101, 99};
   return CharArrayToString(secret_url);
}

// Hardware ID Generation
string GetHWID()
{
   string base_str = TerminalInfoString(TERMINAL_CPU_ARCHITECTURE) + TerminalInfoString(TERMINAL_DATA_PATH);
   long hash = 0;
   for(int i = 0; i < StringLen(base_str); i++) {
      hash = (hash * 31) + StringGetCharacter(base_str, i);
   }
   return IntegerToString(MathAbs(hash));
}

bool VerifyLicense()
{
   string url = GetAuthURL() + "?cb=" + IntegerToString(GetTickCount());
   string cookie = NULL, headers;
   char post[], result[];
   
   static long cached_account = 0;
   static string cached_hwid = "";
   if(cached_account == 0) {
      cached_account = AccountInfoInteger(ACCOUNT_LOGIN);
      cached_hwid = GetHWID();
   }
     
   if(cached_account == 0) {
      Print("⚠️ Terminal disconnected from Broker. Delaying background license check...");
      return true; 
   }
   
   string post_data = "key=" + InpLicenseKey + "&account=" + IntegerToString(cached_account) + "&hwid=" + cached_hwid;
   StringToCharArray(post_data, post);
   
   int res = WebRequest("POST", url, cookie, NULL, 5000, post, ArraySize(post), result, headers);
   if(res == 200)
   {
      string responseStr = CharArrayToString(result);
      string status  = ExtractJSONValue(responseStr, "status");
      string message = ExtractJSONValue(responseStr, "message");
      string expires = ExtractJSONValue(responseStr, "expires");
      
      if(status == "valid") {
         G_LicenseValid = true;
         Print("✅ Hedge Master License Verified! Expires: ", expires);
         return true;
      }
      else if(status == "expired") {
         G_LicenseValid = false;
         Print("❌ Subscription Expired: ", message);
         return false;
      }
      else {
         G_LicenseValid = false;
         Print("❌ License Error: ", message);
         return false;
      }
   }
   else
   {
      Print("⚠️ Connection to Google Server failed. HTTP Code: ", res, " | Error: ", GetLastError());
      G_LicenseValid = false; 
      return false;
   }
}

string ExtractJSONValue(string json, string key)
{
   string search_key = "\"" + key + "\":";
   int key_pos = StringFind(json, search_key);
   if(key_pos < 0) return ""; 
   
   int val_start = key_pos + StringLen(search_key);
   while(val_start < StringLen(json) && StringSubstr(json, val_start, 1) == " ") val_start++;
      
   string result = "";
   if(StringSubstr(json, val_start, 1) == "\"") {
      val_start++; 
      int val_end = StringFind(json, "\"", val_start); 
      if(val_end > val_start) result = StringSubstr(json, val_start, val_end - val_start);
   } else {
      int end_comma = StringFind(json, ",", val_start);
      int end_brace = StringFind(json, "}", val_start);
      int val_end = end_comma;
      if(val_end < 0 || (end_brace > 0 && end_brace < val_end)) val_end = end_brace;
      if(val_end > val_start) result = StringSubstr(json, val_start, val_end - val_start);
   }
   StringTrimLeft(result);
   StringTrimRight(result);
   return result;
}

//+------------------------------------------------------------------+
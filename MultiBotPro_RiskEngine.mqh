//+------------------------------------------------------------------+
//|                                          MultiBotPro_RiskEngine.mqh |
//|                               Copyright 2025, Expert Advisor Pro |
//|                              Risk Management & Equity Enforcement |
//+------------------------------------------------------------------+
#ifndef __MULTIBOTPRO_RISKENGINE_MQH__
#define __MULTIBOTPRO_RISKENGINE_MQH__

#include "MultiBotPro_SystemState.mqh"

// Risk engine handles equity-based constraints, daily limits, and stop-loss enforcement
class CRiskEngine
{
private:
   CSystemState *m_systemState;
   double m_accountProfitLimitPct;
   double m_accountLossLimitPct;
   bool m_useAccountLimits;

public:
   CRiskEngine(CSystemState *sysState, double profitLimitPct = 1.0,
               double lossLimitPct = 2.5, bool useAccountLimits = true) :
      m_systemState(sysState),
      m_accountProfitLimitPct(profitLimitPct),
      m_accountLossLimitPct(lossLimitPct),
      m_useAccountLimits(useAccountLimits)
   {}

   ~CRiskEngine() {}

   // --- EQUITY CHECKS ---

   // Check if current equity has hit the daily loss limit
   bool CheckDailyLossLimit(double &currentEquity, double &dailyLoss)
   {
      if(!m_useAccountLimits) return false;
      if(!m_systemState) return false;

      currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double dayStart = m_systemState.GetDayStartEquity();
      dailyLoss = dayStart - currentEquity;

      if(dailyLoss <= 0) return false; // No loss yet

      double dailyLimitAmount = (dayStart * m_accountLossLimitPct) / 100.0;
      return (dailyLoss >= dailyLimitAmount);
   }

   // Check if current equity has hit the daily profit target
   bool CheckDailyProfitTarget(double &currentEquity, double &dailyProfit)
   {
      if(!m_useAccountLimits) return false;
      if(!m_systemState) return false;

      currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double dayStart = m_systemState.GetDayStartEquity();
      dailyProfit = currentEquity - dayStart;

      if(dailyProfit <= 0) return false; // No profit yet

      double profitTargetAmount = (dayStart * m_accountProfitLimitPct) / 100.0;
      return (dailyProfit >= profitTargetAmount);
   }

   // Update high-water mark (equity peak for trailing stop)
   void UpdateHighWaterMark()
   {
      if(!m_systemState) return;

      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double hwm = m_systemState.GetHighWaterMark();

      if(hwm == 0 || currentEquity > hwm)
      {
         m_systemState.SetHighWaterMark(currentEquity);
      }
   }

   // Check trailing stop level against high-water mark
   bool CheckTrailingStop(double trailingStopPct, double &drawdown)
   {
      if(!m_systemState || trailingStopPct <= 0) return false;

      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double hwm = m_systemState.GetHighWaterMark();

      if(hwm == 0) return false;

      drawdown = hwm - currentEquity;
      double trailingStopLevel = (hwm * trailingStopPct) / 100.0;
      m_systemState.SetTrailingStopLevel(trailingStopLevel);

      return (drawdown >= trailingStopLevel);
   }

   // --- DAILY RESET LOGIC ---

   // Check if new day has started and reset daily counters
   bool CheckAndResetDailyMetrics()
   {
      if(!m_systemState) return false;

      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int todayDayOfYear = dt.year * 366 + dt.day_of_year;
      int lastDayOfYear = m_systemState.GetCurrentDayOfYear();

      if(lastDayOfYear == -1 || lastDayOfYear != todayDayOfYear)
      {
         m_systemState.SetCurrentDayOfYear(todayDayOfYear);
         m_systemState.SetDayStartEquity(AccountInfoDouble(ACCOUNT_EQUITY));
         m_systemState.SetDailyStopHit(false);
         m_systemState.SetDailyStopHit(false);
         return true;
      }

      return false;
   }

   // --- POSITION-LEVEL RISK ---

   // Validate position stops are within broker limits
   // Returns true if SL/TP are valid for given symbol
   bool ValidatePositionStops(string symbol, double entryPrice,
                              double stopLoss, double takeProfit)
   {
      double minStopDistance = (double)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(symbol, SYMBOL_POINT);

      if(minStopDistance <= 0)
      {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("MBP RiskEngine: Cannot get stop distance for " + symbol);
         return true; // Assume valid if can't query
      }

      if(stopLoss > 0)
      {
         double slDistance = MathAbs(entryPrice - stopLoss);
         if(slDistance > 0 && slDistance < minStopDistance)
         {
            if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("MBP RiskEngine: Stop loss too close for " + symbol +
                  " (distance=" + DoubleToString(slDistance, 5) +
                  " min=" + DoubleToString(minStopDistance, 5) + ")");
            return false;
         }
      }

      if(takeProfit > 0)
      {
         double tpDistance = MathAbs(takeProfit - entryPrice);
         if(tpDistance > 0 && tpDistance < minStopDistance)
         {
            if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("MBP RiskEngine: Take profit too close for " + symbol +
                  " (distance=" + DoubleToString(tpDistance, 5) +
                  " min=" + DoubleToString(minStopDistance, 5) + ")");
            return false;
         }
      }

      return true;
   }

   // --- RISK LIMIT ENFORCEMENT ---

   // Set hard block due to equity breach
   void SetEquityBlock(string reason)
   {
      if(!m_systemState) return;
      m_systemState.SetCacheSystemBlocked(true);
      m_systemState.SetCacheBlockReason(reason);
      if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print("MBP RiskEngine: System blocked - " + reason);
   }

   // Clear block if conditions allow
   bool TryClearEquityBlock()
   {
      if(!m_systemState) return false;

      if(!m_systemState.GetCacheSystemBlocked())
         return true;

      // Simple clearance: system was blocked, now check if we can continue
      // This is called after user confirms continuation or reset occurs
      m_systemState.SetCacheSystemBlocked(false);
      m_systemState.SetCacheBlockReason("");
      if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print("MBP RiskEngine: System unblocked");
      return true;
   }

   // --- DIAGNOSTIC ---

   string GetRiskStatus()
   {
      string status = "RiskEngine [";
      if(!m_systemState)
      {
         status += "NO_STATE]";
         return status;
      }

      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double dayStart = m_systemState.GetDayStartEquity();
      double hwm = m_systemState.GetHighWaterMark();
      bool isDailyStop = m_systemState.GetDailyStopHit();
      bool isTotalStop = m_systemState.GetTotalStopHit();

      status += "Equity=" + DoubleToString(currentEquity, 2) +
               " DayStart=" + DoubleToString(dayStart, 2) +
               " HWM=" + DoubleToString(hwm, 2) +
               " DailyStop=" + (isDailyStop ? "Yes" : "No") +
               " TotalStop=" + (isTotalStop ? "Yes" : "No") + "]";

      return status;
   }
};

#endif


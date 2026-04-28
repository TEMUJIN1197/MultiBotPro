#ifndef __MULTIBOTPRO_CHARTFACTORY_MQH__
#define __MULTIBOTPRO_CHARTFACTORY_MQH__

//+------------------------------------------------------------------+
//|                                     MultiBotPro_ChartFactory.mqh |
//+------------------------------------------------------------------+
#include "MultiBotPro_Defines.mqh"
#include "MultiBotPro_Renko.mqh"
#include "MultiBotPro_HeikenRenko.mqh"
#include "MultiBotPro_HeikenAshi.mqh"
#include "MultiBotPro_CustomTime.mqh"

class CChartFactory : public CObject
{
private:
   string               m_symbol;
   string               m_customSymbol;
   ENUM_MBP_CHART_MODE  m_chartType;
   ENUM_MBP_RENKO_FAMILY m_renkoFamily;
   int                  m_historyDays;
   long                 m_chartID;
   bool                 m_isPrepared;
   
   CRenkoEngine         m_renko;
   CHeikenRenkoEngine   m_heikenRenko;
   CHeikenAshiEngine    m_heikenAshi;
   CCustomTimeEngine    m_customTime;

public:
   CChartFactory() : m_chartType(MBP_CHART_STANDARD), m_renkoFamily(MBP_RENKO_CLASSIC), m_historyDays(5), m_chartID(0), m_isPrepared(false) {}
   
   // Initialize the specific engine based on type
   void Init(string symbol, ENUM_MBP_CHART_MODE type, string suffix,
            ENUM_BLOCK_MODE renkoMode = BLOCK_MODE_POINTS, double renkoVal = 100, 
            ENUM_TIMEFRAMES atrTf = PERIOD_D1, int atrPeriod = 14, bool wicks = false,
            bool adaptAtr = true, int atrRefreshIdx = 250, ENUM_START_MODE startMode = MODE_DAYS_BACK,
            ENUM_HISTORY_DATA_TYPE histType = DATA_M1, int histDays = 5, datetime fixedDate = 0,
            bool forceRebuild = false,
            ENUM_MBP_RENKO_FAMILY renkoFamily = MBP_RENKO_CLASSIC,
            double renkoOpenOffsetPct = 0.50,
            double renkoReversalShadowPct = 0.50,
            double renkoReversalPct = 1.50,
            bool applyOffsetToFirstBar = false,
            int offsetDigits = 0,
            bool resetOpenOnNewDay = false,
            ENUM_MBP_RENKO_LIVE_STYLE liveStyle = MBP_RENKO_LIVE_SMALL_PHANTOM,
            int livePoolMs = 250)
   {
      m_symbol = symbol;
      m_chartType = type;
      m_renkoFamily = renkoFamily;
      m_historyDays = histDays;
      m_chartID = 0;
      m_isPrepared = false;
      
      // Standardize Suffix Handling
      string actualSuffix = suffix;
      if(actualSuffix != "") {
         if(StringSubstr(actualSuffix, 0, 1) != "_" && StringSubstr(actualSuffix, 0, 1) != ".")
            actualSuffix = "_" + actualSuffix;
      } else {
         // Fallback default suffixes if none provided
         switch(m_chartType) {
            case MBP_CHART_RENKO: actualSuffix = "_R"; break;
            case MBP_CHART_HEIKEN_RENKO: actualSuffix = "_HR"; break;
            case MBP_CHART_HEIKEN_ASHI: actualSuffix = "_HA"; break;
            case MBP_CHART_CUSTOM_TIME: actualSuffix = "_C"; break;
         }
      }
         
      // Determine Custom Symbol Name
      m_customSymbol = (m_chartType == MBP_CHART_STANDARD) ? m_symbol : (m_symbol + actualSuffix);
      if(m_customSymbol == m_symbol && m_chartType != MBP_CHART_STANDARD)
         m_customSymbol = m_symbol + "_Custom";

      switch(m_chartType)
      {
         case MBP_CHART_RENKO:
            m_renko.Init(m_symbol, m_customSymbol, renkoMode, renkoVal, wicks,
                         atrTf, atrPeriod, adaptAtr, atrRefreshIdx,
                         startMode, histType, histDays, fixedDate, forceRebuild,
                         renkoFamily, renkoOpenOffsetPct, renkoReversalShadowPct,
                         renkoReversalPct, applyOffsetToFirstBar, offsetDigits,
                         resetOpenOnNewDay, liveStyle, livePoolMs);
            break;
            
         case MBP_CHART_HEIKEN_RENKO:
            m_heikenRenko.Init(m_symbol, m_customSymbol, (int)renkoVal);
            break;
            
         case MBP_CHART_HEIKEN_ASHI:
            m_heikenAshi.Init(m_symbol, m_customSymbol, _Period);
            break;
            
         case MBP_CHART_CUSTOM_TIME:
            m_customTime.Init(m_symbol, m_customSymbol, (int)renkoVal);
            break;
      }
   }

   bool EnsureStartupShell(const int openAttempts = 5, const bool openChart = true)
   {
      if(m_chartType == MBP_CHART_STANDARD)
         return true;

      if(!EnsureCustomSymbol(m_symbol, m_customSymbol))
         return false;

      if(openChart)
         EnsureChartOpen(openAttempts);
      else
         m_chartID = (ChartSymbol(0) == m_customSymbol) ? ChartID() : 0;
      BindChartToEngine();
      return true;
   }

   bool PrepareStartup(const int openAttempts = 5,
                       const int historyAttempts = 5,
                       const bool openChart = true)
   {
      if(m_chartType == MBP_CHART_STANDARD) return true;
      if(m_isPrepared && HasUsableHistory())
      {
         EnsureStartupShell(openAttempts, openChart);
         return true;
      }

      if(!EnsureStartupShell(openAttempts, openChart))
         return false;

      bool success = false;
      switch(m_chartType)
      {
         case MBP_CHART_RENKO:        success = m_renko.PrepareStartup(); break;
         case MBP_CHART_HEIKEN_RENKO: success = m_heikenRenko.PrepareStartup(m_historyDays); break;
         case MBP_CHART_HEIKEN_ASHI:  success = m_heikenAshi.PrepareStartup(m_historyDays); break;
         case MBP_CHART_CUSTOM_TIME:  success = m_customTime.PrepareStartup(m_historyDays); break;
         default:                     success = true; break;
      }

      if(!success)
      {
         Print("[ChartFactory] Startup preparation failed for ", m_customSymbol, " (", EnumToString(m_chartType), ")");
         m_isPrepared = false;
         return false;
      }

      m_isPrepared = true;
      if(m_chartID > 0)
         ChartRedraw(m_chartID);
      return true;
   }

   bool BuildHistory(int daysBack)
   {
      if(m_chartType == MBP_CHART_STANDARD) return true;
      int historyDays = (daysBack > 0) ? daysBack : m_historyDays;
      
      switch(m_chartType)
      {
         case MBP_CHART_RENKO:        return m_renko.BuildHistory();
         case MBP_CHART_HEIKEN_RENKO: return m_heikenRenko.BuildHistory(historyDays);
         case MBP_CHART_HEIKEN_ASHI:  return m_heikenAshi.BuildHistory(historyDays);
         case MBP_CHART_CUSTOM_TIME:  return m_customTime.BuildHistory(historyDays);
      }
      return false;
   }

   void ProcessTick(const MqlTick &tick)
   {
      if(m_chartType == MBP_CHART_STANDARD) return;
      
      switch(m_chartType)
      {
         case MBP_CHART_RENKO:        m_renko.ProcessTick(tick); break;
         case MBP_CHART_HEIKEN_RENKO: m_heikenRenko.ProcessTick(tick); break;
         case MBP_CHART_HEIKEN_ASHI:  m_heikenAshi.ProcessTick(tick); break;
         case MBP_CHART_CUSTOM_TIME:  m_customTime.ProcessTick(tick); break;
      }
   }

   int ProcessTickBatch(const MqlTick &ticks[], const int startIndex, const int count)
   {
      if(m_chartType == MBP_CHART_STANDARD || count <= 0 || startIndex < 0)
         return 0;

      switch(m_chartType)
      {
         case MBP_CHART_RENKO:
            return m_renko.ProcessTickBatch(ticks, startIndex, count);

         case MBP_CHART_HEIKEN_RENKO:
         case MBP_CHART_HEIKEN_ASHI:
         case MBP_CHART_CUSTOM_TIME:
         default:
         {
            int processed = 0;
            int limit = MathMin(count, ArraySize(ticks) - startIndex);
            for(int i = 0; i < limit; i++)
            {
               ProcessTick(ticks[startIndex + i]);
               processed++;
            }
            return processed;
         }
      }
   }

   void ProcessTimer(const MqlTick &tick, const bool hasLiveTick)
   {
      if(m_chartType == MBP_CHART_STANDARD) return;

      switch(m_chartType)
      {
         case MBP_CHART_RENKO:        m_renko.ProcessTimer(tick, hasLiveTick); break;
         case MBP_CHART_HEIKEN_RENKO: m_heikenRenko.ProcessTimer(tick, hasLiveTick); break;
         case MBP_CHART_HEIKEN_ASHI:  m_heikenAshi.ProcessTimer(tick, hasLiveTick); break;
         case MBP_CHART_CUSTOM_TIME:  m_customTime.ProcessTimer(tick, hasLiveTick); break;
         default: break;
      }
   }

   void ProcessTimer()
   {
      MqlTick emptyTick;
      ZeroMemory(emptyTick);
      ProcessTimer(emptyTick, false);
   }

   void Deinit()
   {
      m_isPrepared = false;
      if(m_chartType != MBP_CHART_STANDARD && m_chartID > 0)
      {
         DestroyIndicatorOverlayForChart(m_chartID);
         DeleteBoxObjectsForChart(m_chartID);
      }
      if(m_chartType == MBP_CHART_RENKO) m_renko.Deinit();
   }

   void RefreshNativeVisuals(const bool allowFullRedraw = false)
   {
      SyncNativeVisuals(allowFullRedraw);
   }
   
   void DrawVisuals(long magic)
   {
      if(m_chartType == MBP_CHART_STANDARD) return;
      SyncNativeVisuals(false);
      
      switch(m_chartType)
      {
         case MBP_CHART_RENKO:        m_renko.DrawVisuals(magic); break;
         case MBP_CHART_HEIKEN_RENKO: m_heikenRenko.DrawVisuals(magic); break;
         case MBP_CHART_CUSTOM_TIME:  m_customTime.DrawVisuals(magic); break;
      }
   }

   bool GetBar(int shift, SMBPCustomBar &outBar)
   {
      switch(m_chartType)
      {
         case MBP_CHART_RENKO:        return m_renko.GetBar(shift, outBar);
         case MBP_CHART_HEIKEN_RENKO: return m_heikenRenko.GetBar(shift, outBar);
         case MBP_CHART_HEIKEN_ASHI:  return m_heikenAshi.GetBar(shift, outBar);
         case MBP_CHART_CUSTOM_TIME:  return m_customTime.GetBar(shift, outBar);
         default:
            return GetStandardBar(m_symbol, shift, outBar);
      }
   }

   string GetCustomSymbol() { return m_customSymbol; }
   ENUM_MBP_CHART_MODE GetChartType() { return m_chartType; }
   ENUM_MBP_RENKO_FAMILY GetRenkoFamily() { return m_renkoFamily; }
   long GetChartID() { return m_chartID; }

private:
   bool EnsureCustomSymbol(string base, string custom)
   {
      bool isCustom = (bool)SymbolInfoInteger(custom, SYMBOL_CUSTOM);
      if(!isCustom)
      {
         ResetLastError();
         if(!CustomSymbolCreate(custom, "MultiBotPro", base))
         {
            Print("[ChartFactory] CustomSymbolCreate failed for ", custom, " Error: ", _LastError);
            return false;
         }
      }
      CustomSymbolSetInteger(custom, SYMBOL_DIGITS, (int)SymbolInfoInteger(base, SYMBOL_DIGITS));
      CustomSymbolSetDouble(custom, SYMBOL_POINT, SymbolInfoDouble(base, SYMBOL_POINT));
      CustomSymbolSetDouble(custom, SYMBOL_TRADE_TICK_SIZE, SymbolInfoDouble(base, SYMBOL_TRADE_TICK_SIZE));
      return SymbolSelect(custom, true);
   }

   bool EnsureChartOpen(const int maxAttempts = 5)
   {
      long previousChartID = m_chartID;
      if(ChartSymbol(0) == m_customSymbol)
         m_chartID = ChartID();
      else
         m_chartID = FindChartBySymbol(m_customSymbol);
      if(m_chartID == 0)
      {
         ResetLastError();
         long openedChartID = ChartOpen(m_customSymbol, PERIOD_M1);
         if(openedChartID > 0)
            m_chartID = openedChartID;
      }

      if(m_chartID > 0)
      {
         if(m_chartID != previousChartID)
            ApplyChartStyles(m_chartID);
         return true;
      }

      return false;
   }

   void BindChartToEngine()
   {
      switch(m_chartType)
      {
         case MBP_CHART_RENKO:        m_renko.SetChartID(m_chartID); break;
         case MBP_CHART_HEIKEN_RENKO: m_heikenRenko.SetChartID(m_chartID); break;
         case MBP_CHART_HEIKEN_ASHI:  m_heikenAshi.SetChartID(m_chartID); break;
         case MBP_CHART_CUSTOM_TIME:  m_customTime.SetChartID(m_chartID); break;
      }
   }

   bool HasUsableHistory()
   {
      MqlRates rates[];
      if(CopyRates(m_customSymbol, PERIOD_M1, 0, 1, rates) > 0)
         return true;
      if(m_chartType == MBP_CHART_HEIKEN_ASHI && CopyRates(m_customSymbol, _Period, 0, 1, rates) > 0)
         return true;
      return false;
   }

   long FindChartBySymbol(string sym)
   {
      long curr = ChartFirst();
      while(curr >= 0)
      {
         if(ChartSymbol(curr) == sym) return curr;
         curr = ChartNext(curr);
      }
      return 0;
   }

   int ResolveVisualSymbolIndex()
   {
      int idx = GetPrimarySymbolIndex(m_customSymbol);
      if(idx >= 0)
         return idx;

      idx = GetPrimarySymbolIndex(m_symbol);
      if(idx >= 0)
         return idx;

      string base = GetBaseSymbol(m_symbol);
      if(base != "" && base != m_symbol)
         return GetPrimarySymbolIndex(base);

      return -1;
   }

   void SyncNativeVisuals(const bool allowFullRedraw)
   {
      if(m_chartType == MBP_CHART_STANDARD)
         return;

      if(m_chartID <= 0 || ChartSymbol(m_chartID) != m_customSymbol)
         m_chartID = FindChartBySymbol(m_customSymbol);
      if(m_chartID <= 0)
         return;

      ApplyChartStyles(m_chartID);
      int symbolIndex = ResolveVisualSymbolIndex();
      if(symbolIndex >= 0 && symbolIndex < ArraySize(SymbolData) && SymbolData[symbolIndex].active)
      {
         if(ShowBoxLines)
            UpdateBoxLevelsForChart(symbolIndex, m_chartID, SymbolData[symbolIndex].symbol, PERIOD_M1);
         else
            DeleteBoxObjectsForChart(m_chartID);
         RefreshIndicatorOverlayForChart(m_chartID, SymbolData[symbolIndex].symbol, PERIOD_M1, symbolIndex, allowFullRedraw);
      }
      else
      {
         DeleteBoxObjectsForChart(m_chartID);
         DestroyIndicatorOverlayForChart(m_chartID);
      }

      ChartRedraw(m_chartID);
   }

   bool GetStandardBar(string sym, int shift, SMBPCustomBar &outBar)
   {
      MqlRates rates[];
      if(CopyRates(sym, _Period, shift, 1, rates) <= 0) return false;
      outBar.open = rates[0].open;
      outBar.high = rates[0].high;
      outBar.low = rates[0].low;
      outBar.close = rates[0].close;
      outBar.time = rates[0].time;
      outBar.tick_volume = rates[0].tick_volume;
      return true;
   }
};

#endif // __MULTIBOTPRO_CHARTFACTORY_MQH__

#ifndef __MULTIBOTPRO_HEIKENASHI_MQH__
#define __MULTIBOTPRO_HEIKENASHI_MQH__
//+------------------------------------------------------------------+
//|                                     MultiBotPro_HeikenAshi.mqh   |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//+------------------------------------------------------------------+
#include "MultiBotPro_Defines.mqh"

class CHeikenAshiEngine
{
private:
   string          m_symbol;
   string          m_customSymbol;
   ENUM_TIMEFRAMES m_timeframe;
   long            m_chartID;

   double          m_prevOpen;
   double          m_prevClose;
   double          m_liveOpen;
   double          m_liveHigh;
   double          m_liveLow;
   double          m_liveClose;
   double          m_lastSourceBid;
   double          m_lastSourceAsk;
   datetime        m_currentBarTime;
   long            m_lastLiveTickMsc;
   bool            m_tickMirroringEnabled;
   bool            m_tickMirrorWarningLogged;
   int             m_tickMirrorFailureCount;
   ulong           m_tickMirrorRetryAfterMs;

public:
   CHeikenAshiEngine() : m_timeframe(PERIOD_M1), m_chartID(0), m_prevOpen(0), m_prevClose(0),
                         m_liveOpen(0), m_liveHigh(0), m_liveLow(0), m_liveClose(0),
                         m_lastSourceBid(0), m_lastSourceAsk(0), m_currentBarTime(0),
                         m_lastLiveTickMsc(0), m_tickMirroringEnabled(true),
                         m_tickMirrorWarningLogged(false), m_tickMirrorFailureCount(0),
                         m_tickMirrorRetryAfterMs(0) {}

   void Init(string symbol, string customSymbol, ENUM_TIMEFRAMES timeframe)
   {
      m_symbol = symbol;
      m_customSymbol = customSymbol;
      m_timeframe = timeframe;
      m_chartID = 0;
      m_prevOpen = 0;
      m_prevClose = 0;
      m_liveOpen = 0;
      m_liveHigh = 0;
      m_liveLow = 0;
      m_liveClose = 0;
      m_lastSourceBid = 0;
      m_lastSourceAsk = 0;
      m_currentBarTime = 0;
      m_lastLiveTickMsc = 0;
      m_tickMirroringEnabled = true;
      m_tickMirrorWarningLogged = false;
      m_tickMirrorFailureCount = 0;
      m_tickMirrorRetryAfterMs = 0;
   }

   void SetChartID(long chartID) { m_chartID = chartID; }

   bool PrepareStartup(int daysBack)
   {
      if(!BuildHistory(daysBack))
         return false;

      MqlTick tick;
      if(SymbolInfoTick(m_symbol, tick))
         SyncFromTick(tick, false);
      else
         PublishCurrentLiveState((long)m_currentBarTime * 1000, false);

      return true;
   }

   bool BuildHistory(int daysBack)
   {
      Print("Heiken Ashi Build: ", m_symbol, " -> ", m_customSymbol, " (TF: ", EnumToString(m_timeframe), ")");

      CustomRatesDelete(m_customSymbol, 0, LONG_MAX);
      CustomTicksDelete(m_customSymbol, 0, LONG_MAX);

      MqlRates src[];
      datetime start = TimeCurrent() - (daysBack * 86400);
      int total = CopyRates(m_symbol, m_timeframe, start, TimeCurrent(), src);
      if(total <= 0)
         return false;

      MqlRates haRates[];
      ArrayResize(haRates, total);

      double prevHaOpen = 0.0;
      double prevHaClose = 0.0;

      for(int i = 0; i < total; i++)
      {
         double haClose = (src[i].open + src[i].high + src[i].low + src[i].close) / 4.0;
         double haOpen = (i == 0) ? ((src[i].open + src[i].close) / 2.0) : ((prevHaOpen + prevHaClose) / 2.0);
         double haHigh = MathMax(src[i].high, MathMax(haOpen, haClose));
         double haLow = MathMin(src[i].low, MathMin(haOpen, haClose));

         haRates[i].time = src[i].time;
         haRates[i].open = haOpen;
         haRates[i].high = haHigh;
         haRates[i].low = haLow;
         haRates[i].close = haClose;
         haRates[i].tick_volume = src[i].tick_volume;
         haRates[i].spread = src[i].spread;
         haRates[i].real_volume = src[i].real_volume;

         prevHaOpen = haOpen;
         prevHaClose = haClose;
      }

      if(!CustomRatesUpdate(m_customSymbol, haRates, total))
      {
         Print("[HeikenAshi] ERROR: CustomRatesUpdate failed for ", m_customSymbol, " (Err: ", _LastError, ")");
         return false;
      }

      m_currentBarTime = haRates[total - 1].time;
      m_liveOpen = haRates[total - 1].open;
      m_liveHigh = haRates[total - 1].high;
      m_liveLow = haRates[total - 1].low;
      m_liveClose = haRates[total - 1].close;

      if(total > 1)
      {
         m_prevOpen = haRates[total - 2].open;
         m_prevClose = haRates[total - 2].close;
      }
      else
      {
         m_prevOpen = m_liveOpen;
         m_prevClose = m_liveClose;
      }

      double lastBid = src[total - 1].close;
      double lastAsk = lastBid;
      m_lastSourceBid = lastBid;
      m_lastSourceAsk = lastAsk;
      m_lastLiveTickMsc = 0;
      m_tickMirroringEnabled = true;
      m_tickMirrorWarningLogged = false;
      m_tickMirrorFailureCount = 0;
      m_tickMirrorRetryAfterMs = 0;
      PublishCurrentLiveState((long)m_currentBarTime * 1000, false);
      return true;
   }

   void ProcessTick(const MqlTick &tick)
   {
      SyncFromTick(tick, true);
   }

   void ProcessTimer(const MqlTick &tick, const bool hasLiveTick)
   {
      if(hasLiveTick)
         CacheSourceTick(tick);

      PublishCurrentLiveState(hasLiveTick ? tick.time_msc : ((long)m_currentBarTime * 1000), false);

      if(m_chartID > 0)
         ChartRedraw(m_chartID);
   }

   bool GetBar(int shift, SMBPCustomBar &outBar)
   {
      MqlRates rates[];
      if(CopyRates(m_customSymbol, m_timeframe, shift, 1, rates) <= 0)
         return false;

      outBar.open = rates[0].open;
      outBar.high = rates[0].high;
      outBar.low = rates[0].low;
      outBar.close = rates[0].close;
      outBar.time = rates[0].time;
      outBar.tick_volume = rates[0].tick_volume;
      return true;
   }

private:
   void CacheSourceTick(const MqlTick &tick)
   {
      double liveBid = (tick.bid > 0) ? tick.bid : ((tick.last > 0) ? tick.last : 0.0);
      if(liveBid > 0)
         m_lastSourceBid = liveBid;

      if(tick.ask > liveBid)
         m_lastSourceAsk = tick.ask;
      else if(m_lastSourceBid > 0 && m_lastSourceAsk <= m_lastSourceBid)
         m_lastSourceAsk = m_lastSourceBid;
   }

   void SyncFromTick(const MqlTick &tick, const bool allowMirrorDegrade)
   {
      MqlRates src[];
      ArraySetAsSeries(src, true);
      if(CopyRates(m_symbol, m_timeframe, 0, 1, src) <= 0)
         return;

      datetime barTime = src[0].time;
      if(m_currentBarTime != 0 && barTime != m_currentBarTime)
      {
         m_prevOpen = m_liveOpen;
         m_prevClose = m_liveClose;
      }

      double haClose = (src[0].open + src[0].high + src[0].low + src[0].close) / 4.0;
      double haOpen = (m_prevOpen == 0 && m_prevClose == 0) ? ((src[0].open + src[0].close) / 2.0) : ((m_prevOpen + m_prevClose) / 2.0);
      double haHigh = MathMax(src[0].high, MathMax(haOpen, haClose));
      double haLow = MathMin(src[0].low, MathMin(haOpen, haClose));

      m_currentBarTime = barTime;
      m_liveOpen = haOpen;
      m_liveHigh = haHigh;
      m_liveLow = haLow;
      m_liveClose = haClose;

      CacheSourceTick(tick);
      if(m_lastSourceBid <= 0)
         m_lastSourceBid = src[0].close;
      if(m_lastSourceAsk <= m_lastSourceBid)
         m_lastSourceAsk = m_lastSourceBid;

      PublishCurrentLiveState((tick.time_msc > 0) ? tick.time_msc : ((long)barTime * 1000), allowMirrorDegrade);
   }

   void PublishCurrentLiveState(long tickTimeMsc, const bool allowMirrorDegrade)
   {
      if(m_currentBarTime <= 0)
         return;

      MqlRates rate[1];
      rate[0].time = m_currentBarTime;
      rate[0].open = m_liveOpen;
      rate[0].high = m_liveHigh;
      rate[0].low = m_liveLow;
      rate[0].close = m_liveClose;
      rate[0].tick_volume = 1;
      rate[0].spread = 0;
      rate[0].real_volume = 0;

      ResetLastError();
      if(!CustomRatesUpdate(m_customSymbol, rate, 1))
      {
         Print("[HeikenAshi] WARNING: Live rate update failed for ", m_customSymbol, " (Err: ", _LastError, ")");
         return;
      }

      double sourceBid = (m_lastSourceBid > 0) ? m_lastSourceBid : m_liveClose;
      double sourceAsk = (m_lastSourceAsk > sourceBid) ? m_lastSourceAsk : sourceBid;
      PublishLiveState(m_currentBarTime, tickTimeMsc, sourceBid, sourceAsk, m_liveClose, allowMirrorDegrade);
   }

   void PublishLiveState(datetime syntheticTime, long tickTimeMsc, double sourceBid, double sourceAsk, double syntheticLast, bool allowMirrorDegrade = true)
   {
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(point <= 0)
         point = _Point;

      double last = NormalizePrice(m_customSymbol, syntheticLast);
      double bid = last;
      double baseBid = (sourceBid > 0) ? sourceBid : last;
      double baseAsk = (sourceAsk > baseBid) ? sourceAsk : SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double spread = (baseAsk > baseBid) ? (baseAsk - baseBid) : (10.0 * point);
      double ask = NormalizePrice(m_customSymbol, last + spread);

      CustomSymbolSetDouble(m_customSymbol, SYMBOL_BID, bid);
      CustomSymbolSetDouble(m_customSymbol, SYMBOL_ASK, ask);
      CustomSymbolSetDouble(m_customSymbol, SYMBOL_LAST, last);

      if(!m_tickMirroringEnabled)
      {
         if(!allowMirrorDegrade)
            return;

         if(GetTickCount() < m_tickMirrorRetryAfterMs)
            return;

         m_tickMirroringEnabled = true;
      }

      long liveTickMsc = ReserveCustomTickTimeMsc((tickTimeMsc > 0) ? tickTimeMsc : ((long)syntheticTime * 1000));

      MqlTick liveTick[1];
      ZeroMemory(liveTick);
      liveTick[0].time = (datetime)(liveTickMsc / 1000);
      liveTick[0].time_msc = liveTickMsc;
      liveTick[0].bid = bid;
      liveTick[0].ask = ask;
      liveTick[0].last = last;
      liveTick[0].volume = 1;
      liveTick[0].volume_real = 0.0;
      liveTick[0].flags = TICK_FLAG_BID | TICK_FLAG_ASK | TICK_FLAG_LAST;

      ResetLastError();
      if(!CustomTicksAdd(m_customSymbol, liveTick, 1))
      {
         int tickError = _LastError;
         if(!allowMirrorDegrade)
            return;

         m_tickMirrorFailureCount++;
         if(m_tickMirrorFailureCount >= 3)
         {
            m_tickMirrorRetryAfterMs = GetTickCount() + 5000;
            DisableTickMirroring("live update", tickError);
         }
         return;
      }

      m_tickMirroringEnabled = true;
      m_tickMirrorFailureCount = 0;
      m_tickMirrorWarningLogged = false;
      m_lastLiveTickMsc = liveTickMsc;
   }

   long ReserveCustomTickTimeMsc(long candidateTimeMsc)
   {
      long normalizedTimeMsc = candidateTimeMsc;
      if(normalizedTimeMsc <= 0)
         normalizedTimeMsc = (long)TimeCurrent() * 1000;

      long minTimeMsc = m_lastLiveTickMsc + 1;
      if(normalizedTimeMsc < minTimeMsc)
         normalizedTimeMsc = minTimeMsc;

      return normalizedTimeMsc;
   }

   void DisableTickMirroring(string stage, int errorCode)
   {
      m_tickMirroringEnabled = false;
      if(m_tickMirrorWarningLogged)
         return;

      m_tickMirrorWarningLogged = true;
      Print("[HeikenAshi] WARNING: Custom tick mirroring disabled for ", m_customSymbol,
            " after ", stage, " failed (Err: ", errorCode, "). Rates-only mode will continue.");
   }
};

#endif // __MULTIBOTPRO_HEIKENASHI_MQH__

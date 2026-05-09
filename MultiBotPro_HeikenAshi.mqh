#ifndef __MULTIBOTPRO_HEIKENASHI_MQH__
#define __MULTIBOTPRO_HEIKENASHI_MQH__
//+------------------------------------------------------------------+
//|                                     MultiBotPro_HeikenAshi.mqh   |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//+------------------------------------------------------------------+
#include "MultiBotPro_Defines.mqh"
#include "MultiBotPro_CustomSymbolPublisher.mqh"

class CHeikenAshiEngine : public CCustomSymbolPublisher
{
private:
   string          m_symbol;
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

public:
   CHeikenAshiEngine() : m_timeframe(PERIOD_M1), m_chartID(0), m_prevOpen(0), m_prevClose(0),
                         m_liveOpen(0), m_liveHigh(0), m_liveLow(0), m_liveClose(0),
                         m_lastSourceBid(0), m_lastSourceAsk(0), m_currentBarTime(0) {}

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
      ResetPublisherState();
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

      MqlRates src[];
      int periodSec = PeriodSeconds(m_timeframe);
      datetime fullStart = TimeCurrent() - (daysBack * 86400);
      datetime start = fullStart;
      bool incremental = false;
      double seedOpen = 0.0;
      double seedClose = 0.0;

      if(Bars(m_customSymbol, m_timeframe) > 2)
      {
         MqlRates lastRates[];
         int copiedLast = CopyRates(m_customSymbol, m_timeframe, 0, 3, lastRates);
         if(copiedLast >= 2)
         {
            MqlRates last = lastRates[copiedLast - 1];
            datetime deleteFrom = MathMax(fullStart, last.time - 7200);
            MqlRates seedRates[];
            int copiedSeed = CopyRates(m_customSymbol, m_timeframe, fullStart, deleteFrom - 1, seedRates);
            if(copiedSeed > 0)
            {
               MqlRates seed = seedRates[copiedSeed - 1];
               seedOpen = seed.open;
               seedClose = seed.close;
               start = MathMax(fullStart, deleteFrom - periodSec);
               CustomRatesDelete(m_customSymbol, deleteFrom, LONG_MAX);
               CustomTicksDelete(m_customSymbol, (long)deleteFrom * 1000, LONG_MAX);
               incremental = true;
               Print("[HeikenAshi] Incremental build for ", m_customSymbol,
                     ": replaying from ", start, " after retained bar ", seed.time);
            }
         }
      }

      if(!incremental)
      {
         CustomRatesDelete(m_customSymbol, 0, LONG_MAX);
         CustomTicksDelete(m_customSymbol, 0, LONG_MAX);
      }

      int total = CopyRates(m_symbol, m_timeframe, start, TimeCurrent(), src);
      if(total <= 0)
         return false;

      MqlRates haRates[];
      ArrayResize(haRates, total);

      double prevHaOpen = seedOpen;
      double prevHaClose = seedClose;

      for(int i = 0; i < total; i++)
      {
         double haClose = (src[i].open + src[i].high + src[i].low + src[i].close) / 4.0;
         double haOpen = (prevHaOpen == 0.0 && prevHaClose == 0.0) ? ((src[i].open + src[i].close) / 2.0) : ((prevHaOpen + prevHaClose) / 2.0);
         double haHigh = MathMax(src[i].high, MathMax(haOpen, haClose));
         double haLow = MathMin(src[i].low, MathMin(haOpen, haClose));
         // Guarantee MT5 OHLC validity
         haHigh = MathMax(haHigh, MathMax(haOpen, haClose));
         haLow  = MathMin(haLow,  MathMin(haOpen, haClose));

         // Bar time = last tick of the underlying bar (bar open + period - 1s).
         // For committed history bars this gives last-tick semantics consistent
         // with Renko types. The live bar keeps the current-bar open time.
         haRates[i].time = (i < total - 1) ? (src[i].time + periodSec - 1) : src[i].time;
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

   void BackfillGap(datetime fromTime, datetime toTime)
   {
      MqlRates src[];
      int total = CopyRates(m_symbol, m_timeframe, fromTime + PeriodSeconds(m_timeframe), toTime - 1, src);
      if(total <= 0)
         return;

      MqlRates haRates[];
      ArrayResize(haRates, total);

      int periodSec = PeriodSeconds(m_timeframe);
      for(int i = 0; i < total; i++)
      {
         double haClose = (src[i].open + src[i].high + src[i].low + src[i].close) / 4.0;
         double haOpen = (m_prevOpen + m_prevClose) / 2.0;
         double haHigh = MathMax(src[i].high, MathMax(haOpen, haClose));
         double haLow = MathMin(src[i].low, MathMin(haOpen, haClose));
         haHigh = MathMax(haHigh, MathMax(haOpen, haClose));
         haLow  = MathMin(haLow,  MathMin(haOpen, haClose));

         // Committed gap bars use last-tick time (bar open + period - 1s).
         haRates[i].time = src[i].time + periodSec - 1;
         haRates[i].open = haOpen;
         haRates[i].high = haHigh;
         haRates[i].low = haLow;
         haRates[i].close = haClose;
         haRates[i].tick_volume = src[i].tick_volume;
         haRates[i].spread = src[i].spread;
         haRates[i].real_volume = src[i].real_volume;

         m_prevOpen = haOpen;
         m_prevClose = haClose;
      }

      SafeCustomRatesUpdate(haRates, total);
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
         int periodSec = PeriodSeconds(m_timeframe);

         // Commit the just-closed bar with last-tick timestamp before rolling state.
         // We use tick.time (the first tick of the new bar) - 1 as the close time
         // of the previous bar, clamped so it doesn't overlap.
         datetime committedTime = (tick.time > 0 && tick.time > m_currentBarTime)
                                  ? (tick.time - 1)
                                  : (m_currentBarTime + periodSec - 1);
         MqlRates committed[1];
         committed[0].time = committedTime;
         committed[0].open = m_liveOpen;
         committed[0].high = m_liveHigh;
         committed[0].low = m_liveLow;
         committed[0].close = m_liveClose;
         committed[0].tick_volume = 1;
         committed[0].spread = 0;
         committed[0].real_volume = 0;
         SafeCustomRatesUpdate(committed, 1);

         if(barTime > m_currentBarTime + periodSec)
         {
            Print("[HeikenAshi] Gap detected! Backfilling missing bars from ", m_currentBarTime, " to ", barTime);
            BackfillGap(m_currentBarTime, barTime);
         }

         m_prevOpen = m_liveOpen;
         m_prevClose = m_liveClose;
      }

      double haClose = (src[0].open + src[0].high + src[0].low + src[0].close) / 4.0;
      double haOpen = (m_prevOpen == 0 && m_prevClose == 0) ? ((src[0].open + src[0].close) / 2.0) : ((m_prevOpen + m_prevClose) / 2.0);
      double haHigh = MathMax(src[0].high, MathMax(haOpen, haClose));
      double haLow = MathMin(src[0].low, MathMin(haOpen, haClose));
      haHigh = MathMax(haHigh, MathMax(haOpen, haClose));
      haLow  = MathMin(haLow,  MathMin(haOpen, haClose));

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

      // Guarantee OHLC validity before publishing the live bar.
      double safeHigh = MathMax(m_liveHigh, MathMax(m_liveOpen, m_liveClose));
      double safeLow  = MathMin(m_liveLow,  MathMin(m_liveOpen, m_liveClose));

      MqlRates rate[1];
      rate[0].time = m_currentBarTime;
      rate[0].open = m_liveOpen;
      rate[0].high = safeHigh;
      rate[0].low = safeLow;
      rate[0].close = m_liveClose;
      rate[0].tick_volume = 1;
      rate[0].spread = 0;
      rate[0].real_volume = 0;

      ResetLastError();
      if(!SafeCustomRatesUpdate(rate, 1))
      {
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

      long liveTickMsc = ReserveCustomTickTimeMsc((tickTimeMsc > 0) ? tickTimeMsc : ((long)syntheticTime * 1000));
      PublishLiveStateTick(syntheticTime, liveTickMsc, bid, ask, last, allowMirrorDegrade);
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
};

#endif // __MULTIBOTPRO_HEIKENASHI_MQH__

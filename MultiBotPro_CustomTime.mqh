#ifndef __MULTIBOTPRO_CUSTOMTIME_MQH__
#define __MULTIBOTPRO_CUSTOMTIME_MQH__
//+------------------------------------------------------------------+
//|                                     MultiBotPro_CustomTime.mqh   |
//|                     Ported from CustomChartCreator_v3            |
//+------------------------------------------------------------------+
#include "MultiBotPro_Defines.mqh"
#include "MultiBotPro_CustomSymbolPublisher.mqh"

class CCustomTimeEngine : public CCustomSymbolPublisher
{
private:
   string   m_symbol;
   long     m_secondsPerBar;
   datetime m_lastBarTime;

   long     m_chartID;
   datetime m_lastVisualUpdate;

   double   m_liveOpen;
   double   m_liveHigh;
   double   m_liveLow;
   double   m_liveClose;
   long     m_liveTickVolume;
   double   m_lastSourceBid;
   double   m_lastSourceAsk;

public:
   CCustomTimeEngine() : m_secondsPerBar(60), m_lastBarTime(0), m_chartID(0),
                         m_lastVisualUpdate(0),
                         m_liveOpen(0), m_liveHigh(0), m_liveLow(0), m_liveClose(0),
                         m_liveTickVolume(0),
                         m_lastSourceBid(0), m_lastSourceAsk(0) {}

   void Init(string symbol, string customSymbol, int seconds)
   {
      m_symbol = symbol;
      m_customSymbol = customSymbol;
      m_secondsPerBar = (seconds > 0) ? seconds : 60;
      m_lastBarTime = 0;
      m_chartID = FindChartBySymbol(m_customSymbol);
      m_lastVisualUpdate = 0;
      ResetPublisherState();
      m_liveOpen = 0;
      m_liveHigh = 0;
      m_liveLow = 0;
      m_liveClose = 0;
      m_liveTickVolume = 0;
      m_lastSourceBid = 0;
      m_lastSourceAsk = 0;
   }

   void SetChartID(long chartID) { m_chartID = chartID; }

   bool PrepareStartup(int daysBack)
   {
      if(!BuildHistory(daysBack))
         return false;

      MqlTick tick;
      if(SymbolInfoTick(m_symbol, tick))
         ProcessTickInternal(tick, false);
      else
         PublishCurrentLiveState((long)m_lastBarTime * 1000, false);

      return true;
   }

   bool BuildHistory(int daysBack)
   {
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("Custom Timeframe Build: ", m_symbol, " -> ", m_customSymbol, " (", m_secondsPerBar, "s)");

      MqlTick ticks[];
      datetime fullStart = TimeCurrent() - (daysBack * 86400);
      datetime start = fullStart;
      bool incremental = false;
      if(Bars(m_customSymbol, PERIOD_M1) > 2)
      {
         MqlRates existing[];
         int copied = CopyRates(m_customSymbol, PERIOD_M1, 0, 2, existing);
         if(copied > 0)
         {
            datetime lastTime = existing[copied - 1].time;
            start = MathMax(fullStart, lastTime - 7200);
            CustomRatesDelete(m_customSymbol, start, LONG_MAX);
            CustomTicksDelete(m_customSymbol, (long)start * 1000, LONG_MAX);
            incremental = true;
            if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("[CustomTime] Incremental build for ", m_customSymbol,
                  ": replaying from ", start, " after existing bar ", lastTime);
         }
      }

      if(!incremental)
      {
         CustomRatesDelete(m_customSymbol, 0, LONG_MAX);
         CustomTicksDelete(m_customSymbol, 0, LONG_MAX);
      }

      int totalTicks = CopyTicksRange(m_symbol, ticks, COPY_TICKS_ALL,
                                      (ulong)start * 1000, (ulong)TimeCurrent() * 1000);
      if(totalTicks <= 0)
      {
         // Fallback: build from M1 rates when tick data is unavailable.
         return BuildHistoryFromRates(daysBack, start, incremental);
      }

      MqlRates rates[];
      ArrayResize(rates, totalTicks);
      int barIndex = 0;
      datetime currentBarStart = 0;
      datetime lastTickTime = 0;

      for(int i = 0; i < totalTicks; i++)
      {
         double tickPrice = (ticks[i].bid > 0) ? ticks[i].bid : ticks[i].last;
         if(tickPrice <= 0)
            continue;

         datetime barBucket = (datetime)(ticks[i].time - (ticks[i].time % m_secondsPerBar));
         if(barBucket != currentBarStart)
         {
            if(currentBarStart != 0)
            {
               // Commit the previous bar: bar time = the last tick that fell in it.
               rates[barIndex].time = lastTickTime;
               barIndex++;
            }

            currentBarStart = barBucket;
            lastTickTime = ticks[i].time;
            rates[barIndex].time = ticks[i].time; // provisional; updated each tick
            rates[barIndex].open = tickPrice;
            rates[barIndex].high = tickPrice;
            rates[barIndex].low = tickPrice;
            rates[barIndex].close = tickPrice;
            rates[barIndex].tick_volume = 1;
            rates[barIndex].spread = 0;
            rates[barIndex].real_volume = 0;
         }
         else
         {
            lastTickTime = ticks[i].time;
            if(tickPrice > rates[barIndex].high) rates[barIndex].high = tickPrice;
            if(tickPrice < rates[barIndex].low)  rates[barIndex].low  = tickPrice;
            rates[barIndex].close = tickPrice;
            rates[barIndex].tick_volume++;
         }
      }
      // The last bar (live) stays with its provisional last-tick time.
      rates[barIndex].time = lastTickTime;

      int barCount = barIndex + 1;
      if(!CustomRatesUpdate(m_customSymbol, rates, barCount))
      {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print("[CustomTime] ERROR: CustomRatesUpdate failed for ", m_customSymbol, " (Err: ", _LastError, ")");
         return false;
      }

      m_lastBarTime = currentBarStart;
      m_lastLiveTickMsc = 0;
      m_tickMirroringEnabled = true;
      m_tickMirrorWarningLogged = false;
      m_tickMirrorFailureCount = 0;
      m_tickMirrorRetryAfterMs = 0;
      m_liveOpen = rates[barIndex].open;
      m_liveHigh = rates[barIndex].high;
      m_liveLow = rates[barIndex].low;
      m_liveClose = rates[barIndex].close;
      m_liveTickVolume = rates[barIndex].tick_volume;

      double lastBid = (ticks[totalTicks - 1].bid > 0) ? ticks[totalTicks - 1].bid : ticks[totalTicks - 1].last;
      double lastAsk = (ticks[totalTicks - 1].ask > lastBid) ? ticks[totalTicks - 1].ask : lastBid;
      m_lastSourceBid = lastBid;
      m_lastSourceAsk = lastAsk;
      PublishCurrentLiveState(ticks[totalTicks - 1].time_msc, false);
      return true;
   }

   // Fallback history build using M1 rates when tick data is unavailable.
   // Bar time = last second of the M1 bar that closes within the custom bucket.
   bool BuildHistoryFromRates(int daysBack, datetime requestedStart = 0, bool incremental = false)
   {
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("[CustomTime] No tick data — building from M1 rates for ", m_customSymbol);
      MqlRates src[];
      datetime start = (requestedStart > 0) ? requestedStart : (TimeCurrent() - (daysBack * 86400));
      if(!incremental)
      {
         CustomRatesDelete(m_customSymbol, 0, LONG_MAX);
         CustomTicksDelete(m_customSymbol, 0, LONG_MAX);
      }
      int total = CopyRates(m_symbol, PERIOD_M1, start, TimeCurrent(), src);
      if(total <= 0)
         return false;

      MqlRates rates[];
      ArrayResize(rates, total);
      int barIndex = 0;
      datetime currentBarStart = 0;

      for(int i = 0; i < total; i++)
      {
         datetime barBucket = (datetime)(src[i].time - (src[i].time % m_secondsPerBar));
         if(barBucket != currentBarStart)
         {
            if(currentBarStart != 0)
            {
               // Commit with last-tick time = last second of previous M1 bar.
               rates[barIndex].time = src[i].time - 1;
               barIndex++;
            }
            currentBarStart = barBucket;
            rates[barIndex].time = src[i].time + 59; // provisional
            rates[barIndex].open = src[i].open;
            rates[barIndex].high = src[i].high;
            rates[barIndex].low = src[i].low;
            rates[barIndex].close = src[i].close;
            rates[barIndex].tick_volume = src[i].tick_volume;
            rates[barIndex].spread = 0;
            rates[barIndex].real_volume = 0;
         }
         else
         {
            if(src[i].high > rates[barIndex].high) rates[barIndex].high = src[i].high;
            if(src[i].low  < rates[barIndex].low)  rates[barIndex].low  = src[i].low;
            rates[barIndex].close = src[i].close;
            rates[barIndex].tick_volume += src[i].tick_volume;
            rates[barIndex].time = src[i].time + 59; // keep updating to last M1 bar end
         }
      }

      int barCount = barIndex + 1;
      if(!CustomRatesUpdate(m_customSymbol, rates, barCount))
      {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print("[CustomTime] ERROR: CustomRatesUpdate (rates fallback) failed. Err=", _LastError);
         return false;
      }

      m_lastBarTime = currentBarStart;
      m_lastLiveTickMsc = 0;
      m_tickMirroringEnabled = true;
      m_tickMirrorWarningLogged = false;
      m_tickMirrorFailureCount = 0;
      m_tickMirrorRetryAfterMs = 0;
      m_liveOpen = rates[barIndex].open;
      m_liveHigh = rates[barIndex].high;
      m_liveLow = rates[barIndex].low;
      m_liveClose = rates[barIndex].close;
      m_liveTickVolume = rates[barIndex].tick_volume;

      double lastBid = src[total - 1].close;
      m_lastSourceBid = lastBid;
      m_lastSourceAsk = lastBid;
      PublishCurrentLiveState((long)(src[total - 1].time + 59) * 1000, false);
      return true;
   }

   void ProcessTick(const MqlTick &tick)
   {
      ProcessTickInternal(tick, true);
   }

   void ProcessTimer(const MqlTick &tick, const bool hasLiveTick)
   {
      if(hasLiveTick)
         CacheSourceTick(tick);
      else if(m_secondsPerBar > 0 && m_lastBarTime > 0 && m_liveOpen > 0)
      {
         datetime nowBucket = (datetime)(TimeCurrent() - (TimeCurrent() % m_secondsPerBar));
         if(nowBucket > m_lastBarTime)
         {
            double carryClose = (m_liveClose > 0) ? m_liveClose : m_lastSourceBid;
            if(carryClose > 0)
            {
               m_lastBarTime = nowBucket;
               m_liveOpen = carryClose;
               m_liveHigh = carryClose;
               m_liveLow = carryClose;
               m_liveClose = carryClose;
               m_liveTickVolume = 1;
            }
         }
      }

      long publishMsc = (hasLiveTick && tick.time_msc > 0) ? tick.time_msc : ((long)TimeCurrent() * 1000);
      PublishCurrentLiveState(publishMsc, false);

      if(m_chartID > 0)
         ChartRedraw(m_chartID);
   }

   bool GetBar(int shift, SMBPCustomBar &outBar)
   {
      if(shift == 0 && m_lastBarTime > 0 && m_liveOpen > 0)
      {
         outBar.open = m_liveOpen;
         outBar.high = m_liveHigh;
         outBar.low = m_liveLow;
         outBar.close = m_liveClose;
         outBar.time = m_lastBarTime;
         outBar.tick_volume = MathMax((long)1, m_liveTickVolume);
         return true;
      }

      int committedShift = shift;
      if(shift > 0 && m_lastBarTime > 0 && m_liveOpen > 0)
         committedShift = shift - 1;

      MqlRates rates[];
      if(CopyRates(m_customSymbol, PERIOD_M1, committedShift, 1, rates) <= 0)
         return false;

      outBar.open = rates[0].open;
      outBar.high = rates[0].high;
      outBar.low = rates[0].low;
      outBar.close = rates[0].close;
      outBar.time = rates[0].time;
      outBar.tick_volume = rates[0].tick_volume;
      return true;
   }

   void DrawVisuals(long magic)
   {
      if(m_chartID <= 0)
         return;
      if(TimeCurrent() - m_lastVisualUpdate < 1)
         return;

      m_lastVisualUpdate = TimeCurrent();
   }

private:
   void CacheSourceTick(const MqlTick &tick)
   {
      double tickPrice = (tick.bid > 0) ? tick.bid : tick.last;
      if(tickPrice > 0)
         m_lastSourceBid = tickPrice;

      if(tick.ask > tickPrice)
         m_lastSourceAsk = tick.ask;
      else if(m_lastSourceBid > 0 && m_lastSourceAsk <= m_lastSourceBid)
         m_lastSourceAsk = m_lastSourceBid;
   }

   void ProcessTickInternal(const MqlTick &tick, const bool allowMirrorDegrade)
   {
      double tickPrice = (tick.bid > 0) ? tick.bid : tick.last;
      if(tickPrice <= 0)
         return;

      CacheSourceTick(tick);

      datetime barTime = (datetime)(tick.time - (tick.time % m_secondsPerBar));

      bool newBar = (m_lastBarTime <= 0 || barTime != m_lastBarTime || m_liveOpen <= 0);
      if(newBar)
      {
         m_lastBarTime = barTime;
         m_liveOpen = tickPrice;
         m_liveHigh = tickPrice;
         m_liveLow = tickPrice;
         m_liveClose = tickPrice;
         m_liveTickVolume = 1;
      }
      else
      {
         if(tickPrice > m_liveHigh)
            m_liveHigh = tickPrice;
         if(tickPrice < m_liveLow)
            m_liveLow = tickPrice;
         m_liveClose = tickPrice;
         m_liveTickVolume++;
      }

      PublishCurrentLiveState(tick.time_msc, allowMirrorDegrade);
   }

   void PublishCurrentLiveState(long tickTimeMsc, const bool allowMirrorDegrade)
   {
      if(m_lastBarTime <= 0)
         return;

      MqlRates rate[1];
      rate[0].time = m_lastBarTime;
      rate[0].open = m_liveOpen;
      rate[0].high = m_liveHigh;
      rate[0].low = m_liveLow;
      rate[0].close = m_liveClose;
      rate[0].tick_volume = MathMax((long)1, m_liveTickVolume);
      rate[0].spread = 0;
      rate[0].real_volume = 0;

      ResetLastError();
      if(!SafeCustomRatesUpdate(rate, 1))
      {
         return;
      }

      double sourceBid = (m_lastSourceBid > 0) ? m_lastSourceBid : m_liveClose;
      double sourceAsk = (m_lastSourceAsk > sourceBid) ? m_lastSourceAsk : sourceBid;
      PublishLiveState(m_lastBarTime, tickTimeMsc, sourceBid, sourceAsk, m_liveClose, allowMirrorDegrade);
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

   long FindChartBySymbol(string sym)
   {
      long curr = ChartFirst();
      while(curr >= 0)
      {
         if(ChartSymbol(curr) == sym)
            return curr;
         curr = ChartNext(curr);
      }
      return 0;
   }
};

#endif // __MULTIBOTPRO_CUSTOMTIME_MQH__


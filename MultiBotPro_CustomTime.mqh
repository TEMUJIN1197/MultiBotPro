#ifndef __MULTIBOTPRO_CUSTOMTIME_MQH__
#define __MULTIBOTPRO_CUSTOMTIME_MQH__
//+------------------------------------------------------------------+
//|                                     MultiBotPro_CustomTime.mqh   |
//|                     Ported from CustomChartCreator_v3            |
//+------------------------------------------------------------------+
#include "MultiBotPro_Defines.mqh"

class CCustomTimeEngine
{
private:
   string   m_symbol;
   string   m_customSymbol;
   long     m_secondsPerBar;
   datetime m_lastBarTime;

   long     m_chartID;
   datetime m_lastVisualUpdate;
   long     m_lastLiveTickMsc;
   bool     m_tickMirroringEnabled;
   bool     m_tickMirrorWarningLogged;
   int      m_tickMirrorFailureCount;
   ulong    m_tickMirrorRetryAfterMs;

   double   m_liveOpen;
   double   m_liveHigh;
   double   m_liveLow;
   double   m_liveClose;
   long     m_liveTickVolume;
   double   m_lastSourceBid;
   double   m_lastSourceAsk;

public:
   CCustomTimeEngine() : m_secondsPerBar(60), m_lastBarTime(0), m_chartID(0),
                         m_lastVisualUpdate(0), m_lastLiveTickMsc(0),
                         m_tickMirroringEnabled(true), m_tickMirrorWarningLogged(false),
                         m_tickMirrorFailureCount(0), m_tickMirrorRetryAfterMs(0),
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
      m_lastLiveTickMsc = 0;
      m_tickMirroringEnabled = true;
      m_tickMirrorWarningLogged = false;
      m_tickMirrorFailureCount = 0;
      m_tickMirrorRetryAfterMs = 0;
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
      Print("Custom Timeframe Build: ", m_symbol, " -> ", m_customSymbol, " (", m_secondsPerBar, "s)");
      CustomRatesDelete(m_customSymbol, 0, LONG_MAX);
      CustomTicksDelete(m_customSymbol, 0, LONG_MAX);

      MqlTick ticks[];
      datetime start = TimeCurrent() - (daysBack * 86400);
      int totalTicks = CopyTicksRange(m_symbol, ticks, COPY_TICKS_ALL, start * 1000, TimeCurrent() * 1000);
      if(totalTicks <= 0)
         return false;

      MqlRates rates[];
      ArrayResize(rates, totalTicks);
      int barIndex = 0;
      datetime currentBarStart = 0;

      for(int i = 0; i < totalTicks; i++)
      {
         double tickPrice = (ticks[i].bid > 0) ? ticks[i].bid : ticks[i].last;
         if(tickPrice <= 0)
            continue;

         datetime barTime = (datetime)(ticks[i].time - (ticks[i].time % m_secondsPerBar));
         if(barTime != currentBarStart)
         {
            if(currentBarStart != 0)
               barIndex++;

            currentBarStart = barTime;
            rates[barIndex].time = currentBarStart;
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
            if(tickPrice > rates[barIndex].high)
               rates[barIndex].high = tickPrice;
            if(tickPrice < rates[barIndex].low)
               rates[barIndex].low = tickPrice;
            rates[barIndex].close = tickPrice;
            rates[barIndex].tick_volume++;
         }
      }

      if(!CustomRatesUpdate(m_customSymbol, rates, barIndex + 1))
      {
         Print("[CustomTime] ERROR: CustomRatesUpdate failed for ", m_customSymbol, " (Err: ", _LastError, ")");
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

      PublishCurrentLiveState(hasLiveTick ? tick.time_msc : ((long)m_lastBarTime * 1000), false);

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
      if(!CustomRatesUpdate(m_customSymbol, rate, 1))
      {
         Print("[CustomTime] WARNING: Live rate update failed for ", m_customSymbol, " (Err: ", _LastError, ")");
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
      Print("[CustomTime] WARNING: Custom tick mirroring disabled for ", m_customSymbol,
            " after ", stage, " failed (Err: ", errorCode, "). Rates-only mode will continue.");
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

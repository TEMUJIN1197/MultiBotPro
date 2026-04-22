#ifndef __MULTIBOTPRO_HEIKENRENKO_MQH__
#define __MULTIBOTPRO_HEIKENRENKO_MQH__
//+------------------------------------------------------------------+
//|                                     MultiBotPro_HeikenRenko.mqh |
//|                     Ported from HeikenAshiRenko_Builder_v4      |
//+------------------------------------------------------------------+
#include "MultiBotPro_Defines.mqh"

class CHeikenRenkoEngine
{
private:
   string   m_symbol;
   string   m_customSymbol;
   double   m_boxSize;
   double   m_anchorPrice;
   bool     m_isTrendUp;
   datetime m_lastSyntheticTime;

   double   m_prevHAOpen;
   double   m_prevHAClose;

   long     m_chartID;
   datetime m_lastVisualUpdate;
   long     m_lastLiveTickMsc;
   bool     m_tickMirroringEnabled;
   bool     m_tickMirrorWarningLogged;
   int      m_tickMirrorFailureCount;
   ulong    m_tickMirrorRetryAfterMs;

   datetime m_liveBarTime;
   double   m_liveOpen;
   double   m_liveHigh;
   double   m_liveLow;
   double   m_liveClose;
   double   m_lastLivePrice;
   double   m_lastSourceBid;
   double   m_lastSourceAsk;

public:
   CHeikenRenkoEngine() : m_boxSize(0), m_anchorPrice(0), m_isTrendUp(true),
                          m_lastSyntheticTime(0), m_prevHAOpen(0),
                          m_prevHAClose(0), m_chartID(0), m_lastVisualUpdate(0),
                          m_lastLiveTickMsc(0), m_tickMirroringEnabled(true),
                          m_tickMirrorWarningLogged(false), m_tickMirrorFailureCount(0),
                          m_tickMirrorRetryAfterMs(0), m_liveBarTime(0),
                          m_liveOpen(0), m_liveHigh(0), m_liveLow(0), m_liveClose(0),
                          m_lastLivePrice(0), m_lastSourceBid(0), m_lastSourceAsk(0) {}

   void Init(string symbol, string customSymbol, double boxSize)
   {
      m_symbol = symbol;
      m_customSymbol = customSymbol;
      m_boxSize = boxSize;
      m_anchorPrice = 0;
      m_isTrendUp = true;
      m_lastSyntheticTime = 0;
      m_prevHAOpen = 0;
      m_prevHAClose = 0;
      m_chartID = FindChartBySymbol(m_customSymbol);
      m_lastVisualUpdate = 0;
      m_lastLiveTickMsc = 0;
      m_tickMirroringEnabled = true;
      m_tickMirrorWarningLogged = false;
      m_tickMirrorFailureCount = 0;
      m_tickMirrorRetryAfterMs = 0;
      m_liveBarTime = 0;
      m_liveOpen = 0;
      m_liveHigh = 0;
      m_liveLow = 0;
      m_liveClose = 0;
      m_lastLivePrice = 0;
      m_lastSourceBid = 0;
      m_lastSourceAsk = 0;

      string gvPrefix = m_customSymbol + "_HA_";
      if(GlobalVariableCheck(gvPrefix + "Anchor"))
      {
         m_anchorPrice = GlobalVariableGet(gvPrefix + "Anchor");
         m_isTrendUp = (bool)GlobalVariableGet(gvPrefix + "Trend");
         m_prevHAOpen = GlobalVariableGet(gvPrefix + "PrevOpen");
         m_prevHAClose = GlobalVariableGet(gvPrefix + "PrevClose");
         m_lastSyntheticTime = (datetime)GlobalVariableGet(gvPrefix + "LastTime");
         m_lastLiveTickMsc = (long)m_lastSyntheticTime * 1000;
      }
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
         PublishCurrentLiveState((long)m_liveBarTime * 1000, false);

      return true;
   }

   bool BuildHistory(int daysBack)
   {
      Print("Heiken Renko Build: ", m_symbol, " -> ", m_customSymbol);
      CustomRatesDelete(m_customSymbol, 0, LONG_MAX);
      CustomTicksDelete(m_customSymbol, 0, LONG_MAX);

      datetime start = TimeCurrent() - (daysBack * 86400);
      MqlRates src[];
      int total = CopyRates(m_symbol, PERIOD_M1, start, TimeCurrent(), src);
      if(total <= 0)
         return false;

      m_anchorPrice = src[0].open;
      m_isTrendUp = true;
      m_prevHAOpen = 0;
      m_prevHAClose = 0;
      m_lastSyntheticTime = TimeCurrent() - (total * 60);
      m_lastLiveTickMsc = 0;
      m_tickMirroringEnabled = true;
      m_tickMirrorWarningLogged = false;
      m_tickMirrorFailureCount = 0;
      m_tickMirrorRetryAfterMs = 0;
      m_liveBarTime = 0;
      m_liveOpen = 0;
      m_liveHigh = 0;
      m_liveLow = 0;
      m_liveClose = 0;
      m_lastLivePrice = 0;
      m_lastSourceBid = src[total - 1].close;
      m_lastSourceAsk = src[total - 1].close;

      for(int i = 0; i < total; i++)
      {
         long baseTimeMsc = (long)src[i].time * 1000;
         if(src[i].close >= src[i].open)
         {
            ProcessPrice(src[i].open,  src[i].time, baseTimeMsc,     src[i].close, src[i].close, false);
            ProcessPrice(src[i].low,   src[i].time, baseTimeMsc + 1, src[i].close, src[i].close, false);
            ProcessPrice(src[i].high,  src[i].time, baseTimeMsc + 2, src[i].close, src[i].close, false);
            ProcessPrice(src[i].close, src[i].time, baseTimeMsc + 3, src[i].close, src[i].close, false);
         }
         else
         {
            ProcessPrice(src[i].open,  src[i].time, baseTimeMsc,     src[i].close, src[i].close, false);
            ProcessPrice(src[i].high,  src[i].time, baseTimeMsc + 1, src[i].close, src[i].close, false);
            ProcessPrice(src[i].low,   src[i].time, baseTimeMsc + 2, src[i].close, src[i].close, false);
            ProcessPrice(src[i].close, src[i].time, baseTimeMsc + 3, src[i].close, src[i].close, false);
         }
      }

      double lastPrice = src[total - 1].close;
      datetime lastTime = src[total - 1].time;
      UpdateLiveBrick(lastPrice, lastTime, (long)lastTime * 1000, lastPrice, lastPrice, false);
      SaveState();
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

      long publishMsc = hasLiveTick ? tick.time_msc : ((long)m_liveBarTime * 1000);
      PublishCurrentLiveState(publishMsc, false);

      if(m_chartID > 0)
         ChartRedraw(m_chartID);
   }

   bool GetBar(int shift, SMBPCustomBar &outBar)
   {
      MqlRates rates[];
      if(CopyRates(m_customSymbol, PERIOD_M1, shift, 1, rates) <= 0)
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
      double liveBid = (tick.bid > 0) ? tick.bid : ((tick.last > 0) ? tick.last : 0.0);
      if(liveBid > 0)
         m_lastSourceBid = liveBid;

      if(tick.ask > liveBid)
         m_lastSourceAsk = tick.ask;
      else if(m_lastSourceBid > 0 && m_lastSourceAsk <= m_lastSourceBid)
         m_lastSourceAsk = m_lastSourceBid;
   }

   void ProcessTickInternal(const MqlTick &tick, const bool allowMirrorDegrade)
   {
      double livePrice = (tick.bid > 0) ? tick.bid : ((tick.last > 0) ? tick.last : 0.0);
      if(livePrice <= 0)
         return;

      CacheSourceTick(tick);
      ProcessPrice(livePrice, tick.time, tick.time_msc, m_lastSourceBid, m_lastSourceAsk, true, allowMirrorDegrade);
   }

   bool ProcessPrice(double price, datetime tickTime, long tickTimeMsc, double sourceBid, double sourceAsk, bool publishLive, bool allowMirrorDegrade = true)
   {
      if(tickTime <= 0)
         tickTime = TimeCurrent();
      if(tickTimeMsc <= 0)
         tickTimeMsc = (long)tickTime * 1000;
      if(sourceBid <= 0)
         sourceBid = price;
      if(sourceAsk <= 0)
         sourceAsk = sourceBid;

      m_lastLivePrice = price;
      m_lastSourceBid = sourceBid;
      m_lastSourceAsk = sourceAsk;

      if(m_anchorPrice == 0)
         m_anchorPrice = price;

      bool newBrick = false;
      while(true)
      {
         bool emitted = false;
         double rOpen = 0.0;
         double rClose = 0.0;
         double rHigh = 0.0;
         double rLow = 0.0;

         if(m_isTrendUp)
         {
            if(price >= m_anchorPrice + m_boxSize)
            {
               rOpen = m_anchorPrice;
               rClose = m_anchorPrice + m_boxSize;
               rHigh = rClose;
               rLow = rOpen;
               m_anchorPrice = rClose;
               emitted = true;
            }
            else if(price <= m_anchorPrice - (2.0 * m_boxSize))
            {
               rOpen = m_anchorPrice - m_boxSize;
               rClose = m_anchorPrice - (2.0 * m_boxSize);
               rHigh = rOpen;
               rLow = rClose;
               m_anchorPrice = rClose;
               m_isTrendUp = false;
               emitted = true;
            }
         }
         else
         {
            if(price <= m_anchorPrice - m_boxSize)
            {
               rOpen = m_anchorPrice;
               rClose = m_anchorPrice - m_boxSize;
               rHigh = rOpen;
               rLow = rClose;
               m_anchorPrice = rClose;
               emitted = true;
            }
            else if(price >= m_anchorPrice + (2.0 * m_boxSize))
            {
               rOpen = m_anchorPrice + m_boxSize;
               rClose = m_anchorPrice + (2.0 * m_boxSize);
               rHigh = rClose;
               rLow = rOpen;
               m_anchorPrice = rClose;
               m_isTrendUp = true;
               emitted = true;
            }
         }

         if(!emitted)
            break;

         PushHeikenAshiBar(rOpen, rHigh, rLow, rClose);
         newBrick = true;
      }

      if(publishLive)
         UpdateLiveBrick(price, tickTime, tickTimeMsc, sourceBid, sourceAsk, allowMirrorDegrade);

      if(newBrick)
         SaveState();

      return newBrick;
   }

   void PushHeikenAshiBar(double rOpen, double rHigh, double rLow, double rClose)
   {
      double haClose = (rOpen + rHigh + rLow + rClose) / 4.0;
      double haOpen = (m_prevHAOpen == 0 && m_prevHAClose == 0) ? ((rOpen + rClose) / 2.0) : ((m_prevHAOpen + m_prevHAClose) / 2.0);
      double haHigh = MathMax(rHigh, MathMax(haOpen, haClose));
      double haLow = MathMin(rLow, MathMin(haOpen, haClose));

      m_prevHAOpen = haOpen;
      m_prevHAClose = haClose;
      m_lastSyntheticTime += 60;

      MqlRates rate[1];
      rate[0].time = m_lastSyntheticTime;
      rate[0].open = haOpen;
      rate[0].high = haHigh;
      rate[0].low = haLow;
      rate[0].close = haClose;
      rate[0].tick_volume = 1;
      rate[0].spread = 0;
      rate[0].real_volume = 0;

      CustomRatesUpdate(m_customSymbol, rate, 1);
   }

   void UpdateLiveBrick(double currentPrice, datetime tickTime, long tickTimeMsc, double sourceBid, double sourceAsk, bool allowMirrorDegrade = true)
   {
      double rOpen = m_anchorPrice;
      double rClose = currentPrice;
      double rHigh = MathMax(rOpen, rClose);
      double rLow = MathMin(rOpen, rClose);

      double haClose = (rOpen + rHigh + rLow + rClose) / 4.0;
      double haOpen = (m_prevHAOpen == 0 && m_prevHAClose == 0) ? ((rOpen + rClose) / 2.0) : ((m_prevHAOpen + m_prevHAClose) / 2.0);
      double haHigh = MathMax(rHigh, MathMax(haOpen, haClose));
      double haLow = MathMin(rLow, MathMin(haOpen, haClose));

      m_liveBarTime = (m_lastSyntheticTime > 0) ? (m_lastSyntheticTime + 60) : tickTime;
      m_liveOpen = haOpen;
      m_liveHigh = haHigh;
      m_liveLow = haLow;
      m_liveClose = haClose;
      m_lastLivePrice = currentPrice;

      PublishCurrentLiveState(tickTimeMsc, allowMirrorDegrade);
   }

   void PublishCurrentLiveState(long tickTimeMsc, const bool allowMirrorDegrade)
   {
      if(m_liveBarTime <= 0)
         return;

      MqlRates rate[1];
      rate[0].time = m_liveBarTime;
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
         Print("[HeikenRenko] WARNING: Live rate update failed for ", m_customSymbol, " (Err: ", _LastError, ")");
         return;
      }

      double sourceBid = (m_lastSourceBid > 0) ? m_lastSourceBid : m_liveClose;
      double sourceAsk = (m_lastSourceAsk > sourceBid) ? m_lastSourceAsk : sourceBid;
      PublishLiveState(rate[0].time, tickTimeMsc, sourceBid, sourceAsk, rate[0].close, allowMirrorDegrade);
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
      Print("[HeikenRenko] WARNING: Custom tick mirroring disabled for ", m_customSymbol,
            " after ", stage, " failed (Err: ", errorCode, "). Rates-only mode will continue.");
   }

   void SaveState()
   {
      string gvPrefix = m_customSymbol + "_HA_";
      GlobalVariableSet(gvPrefix + "Anchor", m_anchorPrice);
      GlobalVariableSet(gvPrefix + "Trend", (double)m_isTrendUp);
      GlobalVariableSet(gvPrefix + "PrevOpen", m_prevHAOpen);
      GlobalVariableSet(gvPrefix + "PrevClose", m_prevHAClose);
      GlobalVariableSet(gvPrefix + "LastTime", (double)m_lastSyntheticTime);
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

#endif // __MULTIBOTPRO_HEIKENRENKO_MQH__

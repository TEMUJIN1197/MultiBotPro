#ifndef __MULTIBOTPRO_HEIKENRENKO_MQH__
#define __MULTIBOTPRO_HEIKENRENKO_MQH__
//+------------------------------------------------------------------+
//|                                     MultiBotPro_HeikenRenko.mqh |
//|                     Ported from HeikenAshiRenko_Builder_v4      |
//+------------------------------------------------------------------+
#include "MultiBotPro_Defines.mqh"
#include "MultiBotPro_CustomSymbolPublisher.mqh"

class CHeikenRenkoEngine : public CCustomSymbolPublisher
{
private:
   string   m_symbol;
   double   m_boxSize;
   double   m_anchorPrice;
   bool     m_isTrendUp;
   datetime m_lastSyntheticTime;
   bool     m_isBuildingHistory;
   MqlRates m_historyBuffer[];
   datetime m_liveBarStartTime;

   double   m_prevHAOpen;
   double   m_prevHAClose;

   long     m_chartID;
   datetime m_lastVisualUpdate;

   datetime m_liveBarTime;
   double   m_liveOpen;
   double   m_liveHigh;
   double   m_liveLow;
   double   m_liveClose;
   double   m_lastLivePrice;
   double   m_lastSourceBid;
   double   m_lastSourceAsk;

   bool     m_dllDisabled;
   string   m_dllSessionKey;

public:
   CHeikenRenkoEngine() : m_boxSize(0), m_anchorPrice(0), m_isTrendUp(true),
                          m_lastSyntheticTime(0), m_isBuildingHistory(false),
                          m_liveBarStartTime(0), m_prevHAOpen(0),
                          m_prevHAClose(0), m_chartID(0), m_lastVisualUpdate(0),
                          m_liveBarTime(0),
                          m_liveOpen(0), m_liveHigh(0), m_liveLow(0), m_liveClose(0),
                          m_lastLivePrice(0), m_lastSourceBid(0), m_lastSourceAsk(0),
                          m_dllDisabled(false), m_dllSessionKey("") {}

   void Init(string symbol, string customSymbol, double boxSize)
   {
      m_symbol = symbol;
      m_customSymbol = customSymbol;
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point <= 0.0)
         point = _Point;
      m_boxSize = MathMax(boxSize * point, point);
      m_anchorPrice = 0;
      m_isTrendUp = true;
      m_lastSyntheticTime = 0;
      m_isBuildingHistory = false;
      m_liveBarStartTime = 0;
      ArrayFree(m_historyBuffer);
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
      m_dllDisabled = false;
      m_dllSessionKey = customSymbol;

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
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("Heiken Renko Build: ", m_symbol, " -> ", m_customSymbol);

      datetime fullStart = TimeCurrent() - (daysBack * 86400);
      datetime start = fullStart;
      datetime skipBefore = 0;
      bool incremental = (Bars(m_customSymbol, PERIOD_M1) > 10 && m_lastSyntheticTime > 0);
      if(incremental)
      {
         skipBefore = m_lastSyntheticTime;
         start = MathMax(fullStart, skipBefore - 7200);
         CustomRatesDelete(m_customSymbol, skipBefore + 1, LONG_MAX);
         CustomTicksDelete(m_customSymbol, ((long)skipBefore + 1) * 1000, LONG_MAX);
         if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("[HeikenRenko] Incremental build for ", m_customSymbol,
               ": replaying from ", start, " after retained brick ", skipBefore);
      }
      else
      {
         CustomRatesDelete(m_customSymbol, 0, LONG_MAX);
         CustomTicksDelete(m_customSymbol, 0, LONG_MAX);
      }

      MqlRates src[];
      int total = CopyRates(m_symbol, PERIOD_M1, start, TimeCurrent(), src);
      if(total <= 0)
         return false;

      if(!incremental)
      {
         m_anchorPrice = src[0].open;
         m_isTrendUp = true;
         m_prevHAOpen = 0;
         m_prevHAClose = 0;
         m_lastSyntheticTime = 0;
      }
      m_isBuildingHistory = true;
      m_liveBarStartTime = 0;
      ArrayFree(m_historyBuffer);
      ResetPublisherState();
      m_liveBarTime = 0;
      m_liveOpen = 0;
      m_liveHigh = 0;
      m_liveLow = 0;
      m_liveClose = 0;
      m_lastLivePrice = 0;
      m_lastSourceBid = src[total - 1].close;
      m_lastSourceAsk = src[total - 1].close;

      // --- DLL-accelerated path ---
      if(!incremental && !m_dllDisabled && TryDllBuild(src, total))
      {
         m_isBuildingHistory = false;
         double lastPrice = src[total - 1].close;
         datetime lastTime = src[total - 1].time;
         UpdateLiveBrick(lastPrice, lastTime, (long)lastTime * 1000, lastPrice, lastPrice, false);
         SaveState();
         return true;
      }

      // --- MQL5 fallback ---
      for(int i = 0; i < total; i++)
      {
         if(incremental && src[i].time + 59 <= skipBefore)
            continue;

         long baseTimeMsc = (long)src[i].time * 1000;

         // Spread OHLC sub-ticks at 0, 20, 40, 59 seconds within the M1 window.
         // This gives each completing brick the timestamp of the sub-tick that closed it
         // (last-tick semantics) and matches the DLL path exactly.
         ProcessPrice(src[i].open, src[i].time,      baseTimeMsc,          src[i].close, src[i].close, false);
         if(src[i].close >= src[i].open)
         {
            ProcessPrice(src[i].low,  src[i].time + 20, baseTimeMsc + 20000,  src[i].close, src[i].close, false);
            ProcessPrice(src[i].high, src[i].time + 40, baseTimeMsc + 40000,  src[i].close, src[i].close, false);
         }
         else
         {
            ProcessPrice(src[i].high, src[i].time + 20, baseTimeMsc + 20000,  src[i].close, src[i].close, false);
            ProcessPrice(src[i].low,  src[i].time + 40, baseTimeMsc + 40000,  src[i].close, src[i].close, false);
         }
         ProcessPrice(src[i].close, src[i].time + 59, baseTimeMsc + 59000,  src[i].close, src[i].close, false);
         // m_lastSyntheticTime is updated inside ProcessPrice for each committed brick,
         // so no outer time-override loop is required.
      }

      if(ArraySize(m_historyBuffer) > 0)
         CustomRatesUpdate(m_customSymbol, m_historyBuffer, ArraySize(m_historyBuffer));

      m_isBuildingHistory = false;
      ArrayFree(m_historyBuffer);

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

      long publishMsc = (hasLiveTick && tick.time_msc > 0) ? tick.time_msc : ((long)TimeCurrent() * 1000);
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

   datetime ResolveNextLiveBarTime(const datetime tickTime) const
   {
      datetime resolved = (tickTime > 0) ? tickTime : TimeCurrent();
      if(resolved <= 0)
         resolved = TimeCurrent();
      if(m_lastSyntheticTime > 0 && resolved <= m_lastSyntheticTime)
         resolved = m_lastSyntheticTime + 1;
      return resolved;
   }

   void DeleteLivePreviewRate(const datetime barTime)
   {
      if(barTime <= 0)
         return;

      CustomRatesDelete(m_customSymbol, barTime, barTime);
      CustomTicksDelete(m_customSymbol, (long)barTime * 1000, ((long)barTime * 1000) + 999);
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

      if(m_liveBarStartTime <= 0)
         m_liveBarStartTime = ResolveNextLiveBarTime(tickTime);

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

         // Commit at the source tick time that completed the brick, clamped only
         // when multiple bricks complete in the same second.
         datetime completionTime = ResolveNextLiveBarTime(tickTime);

         if(!m_isBuildingHistory)
         {
            if(m_liveBarStartTime > 0)
               DeleteLivePreviewRate(m_liveBarStartTime);
            if(completionTime != m_liveBarStartTime)
               DeleteLivePreviewRate(completionTime);
         }

         PushHeikenAshiBar(rOpen, rHigh, rLow, rClose, completionTime);
         m_lastSyntheticTime = completionTime; // always update to preserve monotonicity

         newBrick = true;
         m_liveBarStartTime = 0;
      }

      if(publishLive)
         UpdateLiveBrick(price, tickTime, tickTimeMsc, sourceBid, sourceAsk, allowMirrorDegrade);

      if(newBrick)
         SaveState();

      return newBrick;
   }

   void PushHeikenAshiBar(double rOpen, double rHigh, double rLow, double rClose, datetime barTime)
   {
      double haClose = (rOpen + rHigh + rLow + rClose) / 4.0;
      double haOpen = (m_prevHAOpen == 0 && m_prevHAClose == 0) ? ((rOpen + rClose) / 2.0) : ((m_prevHAOpen + m_prevHAClose) / 2.0);
      double haHigh = MathMax(rHigh, MathMax(haOpen, haClose));
      double haLow = MathMin(rLow, MathMin(haOpen, haClose));
      // Guarantee MT5 OHLC validity
      haHigh = MathMax(haHigh, MathMax(haOpen, haClose));
      haLow  = MathMin(haLow,  MathMin(haOpen, haClose));

      m_prevHAOpen = haOpen;
      m_prevHAClose = haClose;

      MqlRates rate;
      rate.time = barTime;
      rate.open = haOpen;
      rate.high = haHigh;
      rate.low = haLow;
      rate.close = haClose;
      rate.tick_volume = 1;
      rate.spread = 0;
      rate.real_volume = 0;

      if(m_isBuildingHistory)
      {
         int size = ArraySize(m_historyBuffer);
         ArrayResize(m_historyBuffer, size + 1, 10000);
         m_historyBuffer[size] = rate;
      }
      else
      {
         MqlRates updateRate[1];
         updateRate[0] = rate;
         CustomRatesUpdate(m_customSymbol, updateRate, 1);
      }
   }

   // DLL-accelerated history build: uses the Renko DLL (CLASSIC family) to generate
   // Renko bricks in a background thread, then applies the Heiken Ashi formula on each
   // brick. Falls back to the MQL5 loop if the DLL is unavailable or returns 0 bars.
   bool TryDllBuild(const MqlRates &src[], int total)
   {
      if(G_ActiveComputeBackend != COMPUTE_BACKEND_DLL || !MBP_IsAccelDllCompiled() || !InpEnableAccelDll)
      {
         m_dllDisabled = true;
         return false;
      }

      if(MBP_QueryRenkoBackendW("", "session") <= 0)
      {
         m_dllDisabled = true;
         return false;
      }

      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(point <= 0.0) point = _Point;
      int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);

      if(MBP_RenkoOpenSessionW(m_dllSessionKey, m_customSymbol,
                               (int)MBP_RENKO_CLASSIC, point, digits) <= 0)
      {
         m_dllDisabled = true;
         return false;
      }

      if(MBP_RenkoSeedSessionW(m_dllSessionKey, m_customSymbol,
                               m_anchorPrice, m_isTrendUp ? 1 : 0, m_boxSize,
                               0.0, 0.5, 2.0, 0, 0, 0) <= 0)
      {
         MBP_RenkoCloseSessionW(m_dllSessionKey, m_customSymbol);
         m_dllDisabled = true;
         return false;
      }

      // Build the price/time arrays using the same 0/20/40/59-second sub-tick
      // spread used by CRenkoEngine so timestamps are consistent across all types.
      int bufferSize = total * 4;
      double prices[];
      long   times[];
      ArrayResize(prices, bufferSize);
      ArrayResize(times,  bufferSize);

      int validCount = 0;
      for(int i = 0; i < total; i++)
      {
         long baseTimeMsc = (long)src[i].time * 1000;
         prices[validCount] = src[i].open;  times[validCount] = baseTimeMsc;          validCount++;
         if(src[i].close >= src[i].open)
         {
            prices[validCount] = src[i].low;  times[validCount] = baseTimeMsc + 20000; validCount++;
            prices[validCount] = src[i].high; times[validCount] = baseTimeMsc + 40000; validCount++;
         }
         else
         {
            prices[validCount] = src[i].high; times[validCount] = baseTimeMsc + 20000; validCount++;
            prices[validCount] = src[i].low;  times[validCount] = baseTimeMsc + 40000; validCount++;
         }
         prices[validCount] = src[i].close; times[validCount] = baseTimeMsc + 59000; validCount++;
      }

      ArrayResize(prices, validCount);
      ArrayResize(times,  validCount);
      long lastFedTimeMsc = times[validCount - 1];

      if(MBP_RenkoFeedRatesW(m_dllSessionKey, m_customSymbol, prices, times, validCount) <= 0)
      {
         MBP_RenkoCloseSessionW(m_dllSessionKey, m_customSymbol);
         m_dllDisabled = true;
         return false;
      }

      // Poll until the DLL worker thread has processed all fed data.
      long histInfo[];
      ArrayResize(histInfo, 4);
      ulong pollStart = GetTickCount64();
      const ulong pollTimeoutMs = 3000;
      while((GetTickCount64() - pollStart) < pollTimeoutMs)
      {
         if(!MBP_ShouldAllowBlockingTradeWait("heiken_renko_dll_history"))
            break;
         if(MBP_RenkoGetHistoryInfoW(m_dllSessionKey, m_customSymbol, histInfo) > 0)
         {
            if(histInfo[3] >= lastFedTimeMsc)
               break;
         }
         Sleep(5);
      }

      // Drain raw Renko bricks and apply the Heiken Ashi formula.
      int totalDrained = 0;
      while(true)
      {
         double closedDoubles[];
         long   closedLongs[];
         ArrayResize(closedDoubles, 64 * 4);
         ArrayResize(closedLongs,   64 * 3);
         int count = MBP_RenkoReadClosedBarsW(m_dllSessionKey, m_customSymbol,
                                              closedDoubles, closedLongs, 64);
         if(count <= 0)
            break;

         for(int i = 0; i < count; i++)
         {
            datetime barTime = (datetime)closedLongs[i * 3 + 0];
            if(m_lastSyntheticTime > 0 && barTime <= m_lastSyntheticTime)
               barTime = m_lastSyntheticTime + 1;

            double rOpen  = closedDoubles[i * 4 + 0];
            double rHigh  = closedDoubles[i * 4 + 1];
            double rLow   = closedDoubles[i * 4 + 2];
            double rClose = closedDoubles[i * 4 + 3];

            // Guard against zero-body bricks from DLL precision faults.
            if(MathAbs(rClose - rOpen) < point * 0.5)
            {
               m_lastSyntheticTime = barTime;
               continue;
            }

            // Enforce OHLC validity on the raw Renko brick before HA transform.
            double bodyHigh = MathMax(rOpen, rClose);
            double bodyLow  = MathMin(rOpen, rClose);
            rHigh = MathMax(rHigh, bodyHigh);
            rLow  = MathMin(rLow,  bodyLow);

            PushHeikenAshiBar(rOpen, rHigh, rLow, rClose, barTime);
            m_lastSyntheticTime = barTime;
            totalDrained++;
         }
      }

      MBP_RenkoCloseSessionW(m_dllSessionKey, m_customSymbol);

      if(totalDrained == 0)
      {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_DEBUG)) Print("[HeikenRenko] DLL produced 0 bricks for ", m_customSymbol, ". Falling back to MQL5 loop.");
         ArrayFree(m_historyBuffer);
         m_prevHAOpen = 0;
         m_prevHAClose = 0;
         m_lastSyntheticTime = 0;
         m_anchorPrice = src[0].open;
         m_isTrendUp = true;
         m_dllDisabled = true;
         return false;
      }

      if(ArraySize(m_historyBuffer) > 0)
         CustomRatesUpdate(m_customSymbol, m_historyBuffer, ArraySize(m_historyBuffer));

      ArrayFree(m_historyBuffer);
      if(MBP_LogTierEnabled(MBP_LOG_TIER_DEBUG)) Print("[HeikenRenko] DLL built ", totalDrained, " HA-Renko bricks for ", m_customSymbol);
      return true;
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
      haHigh = MathMax(haHigh, MathMax(haOpen, haClose));
      haLow  = MathMin(haLow,  MathMin(haOpen, haClose));

      m_liveBarTime = m_liveBarStartTime;
      if(m_liveBarTime <= 0) m_liveBarTime = (datetime)MathMax((long)m_lastSyntheticTime + 1, (long)tickTime);

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
      if(!SafeCustomRatesUpdate(rate, 1))
         return;

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


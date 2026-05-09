#ifndef __MULTIBOTPRO_RENKO_MQH__
#define __MULTIBOTPRO_RENKO_MQH__
//+------------------------------------------------------------------+
//|                                           MultiBotPro_Renko.mqh |
//|        Internal AZ-style Renko engine built on custom symbols    |
//+------------------------------------------------------------------+
#include "MultiBotPro_Defines.mqh"
#include "MultiBotPro_CustomSymbolPublisher.mqh"

class CRenkoEngine : public CCustomSymbolPublisher
{
private:
   struct SAZRenkoProfile
   {
      double continuationOpenPct;
      double reversalOpenPct;
      double reversalDistancePct;
   };

   string   m_symbol;
   string   m_gvPrefix;

   double   m_anchorPrice;
   double   m_boxHigh;
   double   m_boxLow;
   bool     m_isTrendUp;
   datetime m_lastCommittedTime;
   datetime m_lastCommittedCloseTime;
   datetime m_hardCommittedTime;
   datetime m_brickStartTime;
   datetime m_liveLogicalStartTime;
   double   m_liveBarOpen;
   bool     m_liveCandidateActive;
   bool     m_liveCandidateIsReversal;
   bool     m_liveCandidateBullish;
   double   m_liveCandidateTargetClose;
   double   m_liveCandidateClose;
   double   m_lastClosePrice;
   double   m_currentBlockSizePoint;
   double   m_lockedBlockSize;
   double   m_currentATR;
   double   m_lastLivePrice;
   double   m_lastSourceBid;
   double   m_lastSourceAsk;
   long     m_chartID;
   int      m_atrHandle;
   bool     m_isInitialized;
   long     m_tickVolBuffer;
   ulong    m_lastFlushTime;
   datetime m_lastVisualUpdate;
   datetime m_livePreviewEndTime;
   datetime m_lastPublishedLiveBarTime;
   ulong    m_lastDirectPreviewPublishUs;
   long     m_lastLiveQuoteTickMsc;
   long     m_lastCommittedQuoteTickMsc;
   ulong    m_lastAtrFetchMs;
   int      m_lastBrickDayOfYear;
   bool     m_isReplayingHistory;
   bool     m_workerSessionEnabled;
   bool     m_workerSessionReady;
   bool     m_workerSessionDisabled;
   bool     m_workerFailureLogged;
   string   m_workerSessionKey;
   double   m_workerSeedBlockSize;
   ulong    m_workerLastReseedMs;
   long     m_workerLastSnapshotTickMsc;
   int      m_workerStallCount;
   ulong    m_livePreviewGeneration;

   MqlRates m_ramRateBuffer[];

   ENUM_MBP_RENKO_FAMILY m_renkoFamily;
   ENUM_MBP_RENKO_LIVE_STYLE m_liveStyle;
   double   m_openOffsetPct;
   double   m_reversalShadowPct;
   double   m_reversalPct;
   bool     m_applyOffsetToFirstBar;
   int      m_offsetDigits;
   bool     m_resetOpenOnNewDay;

   ENUM_BLOCK_MODE        m_blockMode;
   double                 m_blockSizeValue;
   bool                   m_showWicks;
   ENUM_TIMEFRAMES        m_atrTimeframe;
   int                    m_atrPeriod;
   bool                   m_adaptiveATR;
   int                    m_atrRefreshMs;
   int                    m_livePoolMs;
   ENUM_START_MODE        m_startMode;
   ENUM_HISTORY_DATA_TYPE m_histDataType;
   int                    m_historyDays;
   datetime               m_fixedStartDate;
   bool                   m_forceRebuild;

public:
   CRenkoEngine();
   ~CRenkoEngine();

   void Init(string symbol, string customSymbol,
             ENUM_BLOCK_MODE mode, double val, bool wicks,
             ENUM_TIMEFRAMES atrTf, int atrPeriod, bool adaptAtr, int atrRefresh,
             ENUM_START_MODE startMode, ENUM_HISTORY_DATA_TYPE histType, int histDays,
             datetime fixedDate, bool forceRebuild,
             ENUM_MBP_RENKO_FAMILY renkoFamily, double openOffsetPct,
             double reversalShadowPct, double reversalPct,
             bool applyOffsetToFirstBar, int offsetDigits,
             bool resetOpenOnNewDay,
             ENUM_MBP_RENKO_LIVE_STYLE liveStyle,
             int livePoolMs);

   bool PrepareStartup();
   void SetChartID(long chartID);
   void Deinit();
   void ProcessTick(const MqlTick &tick);
   int ProcessTickBatch(const MqlTick &ticks[], const int startIndex, const int count);
   void ProcessTimer(const MqlTick &tick, const bool hasLiveTick);
   void DrawVisuals(long magic);
   bool BuildHistory();
   bool GetBar(int shift, SMBPCustomBar &outBar);

private:
   void ResetRuntimeState();
   string RenkoFamilyToString(const ENUM_MBP_RENKO_FAMILY family) const;
   void EnsureAtrHandle();
   void RefreshChartHandle();
   bool EnsureCustomSymbolReady();
   datetime ResolveHistoryStart() const;
   SAZRenkoProfile ResolveFamilyProfile() const;
   bool HasCleanRecentHistory();
   double NormalizePrice(double price) const;
   double GetPipSize() const;
   void RefreshBlockSize(const datetime timeRef, const bool force);
   double CalculateBlockSize(const datetime timeRef);
   double NormalizeFirstBrickAnchor(double price) const;
   void ResetSessionOpenIfNeeded(const datetime tickTime);
   void SeedFromFirstPrice(const double price, const datetime tickTime);
   double CalculateContinuationOpen(const bool bullishBrick, const double anchorPrice, const double blockSize) const;
   double CalculateReversalDistance(const double blockSize) const;
   double CalculateReversalOpen(const bool bullishReversal, const double anchorPrice, const double blockSize) const;
   double CalculateReversalClose(const bool bullishReversal, const double anchorPrice, const double blockSize) const;
   datetime ResolveCandidateStartTime(const datetime tickTime) const;
   datetime ResolvePublishedCandidateTime(const datetime logicalStartTime) const;
   datetime ResolveLiveBarTime(const datetime fallbackTickTime) const;
   datetime ResolveCompletedBrickTime(const datetime tickTime) const;
   void ClearLiveCandidate(const bool clearStartTime = true);
   void RefreshLiveCandidateState(const double price, const datetime tickTime, const bool preserveStartTime = false);
   datetime NextBrickStart(const datetime currentStart, const datetime tickTime) const;
   bool ProcessRenkoTick(double price, datetime tickTime, long tickVol, long tickTimeMsc = 0);
   void PushCompletedBrick(datetime startTime, double open, double close,
                           double high, double low, long volume, long eventTimeMsc);
   void BuildLiveBrick(double &brickOpen, double &brickClose, double &brickHigh, double &brickLow);
   void UpdateLiveBlock(double price, datetime tickTime, long tickTimeMsc, double sourceBid, double sourceAsk, bool forcePublish = false);
   void PublishLivePreviewRate();
   void DeletePublishedLivePreviewRate(const datetime barTime = 0);
   void UpdateCustomQuoteFields(const double bid, const double ask);
   void PublishLiveQuoteTick(const double bid, const double ask, long requestedTimeMsc);
   void PublishCommittedQuote(const double closePrice, const long eventTimeMsc);
   void DrawLivePreviewOverlay();
   void DrawLivePreviewOverlayOnChart(const long chartId);
   void DeleteLivePreviewOverlay();
   void DeleteLivePreviewOverlayOnChart(const long chartId) const;
   bool UseSmallPhantomLiveMode() const;
   bool UseLargeDirectLiveMode() const;
   bool ShouldPublishDirectPreview(const bool forcePublish);
   string LivePreviewBodyName() const;
   string LivePreviewWickName() const;
   color ResolveLivePreviewColor(const long chartId, const bool bullish) const;
   long ReserveLiveQuoteTickTimeMsc(long requestedTimeMsc) const;
   void DisableTickMirroring(string stage, int errorCode);
   void FlushRamToDisk(bool force = false);
   bool ReplayRatesFrom(const datetime fromTime, const bool skipCommitted);
   bool ReplayTicksFrom(const datetime fromTime, const bool skipCommitted);
   bool ConnectHistoryToLive();
   bool SyncLiveStateWithCurrentTick();
   void PrimeLiveStateFromHistory();
   bool UseWorkerSession() const;
   bool EnsureWorkerSession();
   void CloseWorkerSession();
   void DisableWorkerSession(string reason);
   bool WorkerSessionNeedsReseed() const;
   bool FeedWorkerTick(const MqlTick &tick);
    int FeedWorkerTicksBatch(const MqlTick &ticks[], const int startIndex, const int count);
   bool PullWorkerSnapshot();
   int DrainWorkerClosedBars();
   void BumpLivePreviewGeneration();
   void SaveState();
   void ReconstructStateFromRatePair(const MqlRates &prev, const MqlRates &last);
   bool ReconstructStateFromCustomSymbol();
   bool LoadState();
   void DrawActiveTradeLines(long magic);
   void DrawHistoryTrendLines();
   long FindChartBySymbol(string sym);
};

CRenkoEngine::CRenkoEngine() :
   m_anchorPrice(0.0),
   m_boxHigh(0.0),
   m_boxLow(0.0),
   m_isTrendUp(true),
   m_lastCommittedTime(0),
   m_lastCommittedCloseTime(0),
   m_hardCommittedTime(0),
   m_brickStartTime(0),
   m_liveLogicalStartTime(0),
   m_liveBarOpen(0.0),
   m_liveCandidateActive(false),
   m_liveCandidateIsReversal(false),
   m_liveCandidateBullish(true),
   m_liveCandidateTargetClose(0.0),
   m_liveCandidateClose(0.0),
   m_lastClosePrice(0.0),
   m_currentBlockSizePoint(0.0),
   m_lockedBlockSize(0.0),
   m_currentATR(0.0),
   m_lastLivePrice(0.0),
   m_lastSourceBid(0.0),
   m_lastSourceAsk(0.0),
   m_chartID(0),
   m_atrHandle(INVALID_HANDLE),
   m_isInitialized(false),
   m_tickVolBuffer(0),
   m_lastFlushTime(0),
   m_lastVisualUpdate(0),
   m_livePreviewEndTime(0),
   m_lastPublishedLiveBarTime(0),
   m_lastDirectPreviewPublishUs(0),
   m_lastLiveQuoteTickMsc(0),
   m_lastCommittedQuoteTickMsc(0),
   m_lastAtrFetchMs(0),
   m_lastBrickDayOfYear(-1),
   m_isReplayingHistory(false),
   m_workerSessionEnabled(true),
   m_workerSessionReady(false),
   m_workerSessionDisabled(false),
   m_workerFailureLogged(false),
   m_workerSessionKey(""),
   m_workerSeedBlockSize(0.0),
   m_workerLastReseedMs(0),
   m_workerLastSnapshotTickMsc(0),
   m_workerStallCount(0),
   m_livePreviewGeneration(1),
   m_renkoFamily(MBP_RENKO_CLASSIC),
   m_liveStyle(MBP_RENKO_LIVE_SMALL_PHANTOM),
   m_openOffsetPct(0.0),
   m_reversalShadowPct(1.0),
   m_reversalPct(2.0),
   m_applyOffsetToFirstBar(false),
   m_offsetDigits(0),
   m_resetOpenOnNewDay(false),
   m_blockMode(BLOCK_MODE_POINTS),
   m_blockSizeValue(100.0),
   m_showWicks(false),
   m_atrTimeframe(PERIOD_D1),
   m_atrPeriod(14),
   m_adaptiveATR(true),
   m_atrRefreshMs(250),
   m_livePoolMs(250),
   m_startMode(MODE_DAYS_BACK),
   m_histDataType(DATA_M1),
   m_historyDays(5),
   m_fixedStartDate(0),
   m_forceRebuild(false)
{
}

CRenkoEngine::~CRenkoEngine()
{
   Deinit();
}

void CRenkoEngine::Init(string symbol, string customSymbol,
                        ENUM_BLOCK_MODE mode, double val, bool wicks,
                        ENUM_TIMEFRAMES atrTf, int atrPeriod, bool adaptAtr, int atrRefresh,
                        ENUM_START_MODE startMode, ENUM_HISTORY_DATA_TYPE histType, int histDays,
                        datetime fixedDate, bool forceRebuild,
                        ENUM_MBP_RENKO_FAMILY renkoFamily, double openOffsetPct,
                        double reversalShadowPct, double reversalPct,
                        bool applyOffsetToFirstBar, int offsetDigits,
                        bool resetOpenOnNewDay,
                        ENUM_MBP_RENKO_LIVE_STYLE liveStyle,
                        int livePoolMs)
{
   m_symbol = symbol;
   m_customSymbol = customSymbol;
   m_gvPrefix = m_customSymbol;

   m_blockMode = mode;
   m_blockSizeValue = val;
   // This Renko feed is intended to render clean, body-only blocks.
   m_showWicks = false;
   m_atrTimeframe = atrTf;
   m_atrPeriod = atrPeriod;
   m_adaptiveATR = adaptAtr;
   m_atrRefreshMs = atrRefresh;
   m_startMode = startMode;
   m_histDataType = histType;
   m_historyDays = histDays;
   m_fixedStartDate = fixedDate;
   m_forceRebuild = forceRebuild;

   m_renkoFamily = renkoFamily;
   m_liveStyle = liveStyle;
   m_openOffsetPct = MathMax(0.0, openOffsetPct);
   m_reversalShadowPct = MathMax(0.01, reversalShadowPct);
   m_reversalPct = MathMax(1.0, reversalPct);
   m_applyOffsetToFirstBar = applyOffsetToFirstBar;
   m_offsetDigits = MathMax(0, offsetDigits);
   m_resetOpenOnNewDay = resetOpenOnNewDay;
   m_livePoolMs = MathMax(0, livePoolMs);

   m_chartID = FindChartBySymbol(m_customSymbol);
   m_isInitialized = false;
   m_lastDirectPreviewPublishUs = 0;
}

bool CRenkoEngine::PrepareStartup()
{
   ResetRuntimeState();
   EnsureAtrHandle();
   RefreshBlockSize(TimeCurrent(), true);

   if(!EnsureCustomSymbolReady())
      return false;

   bool resumed = false;
   if(!m_forceRebuild && HasCleanRecentHistory() && LoadState())
   {
      if(ConnectHistoryToLive())
      {
         resumed = true;
         Print("[Renko] AZ-style resume loaded for ", m_customSymbol,
               " (", Bars(m_customSymbol, PERIOD_M1), " bars found)");
      }
      else
      {
         ResetRuntimeState();
         EnsureAtrHandle();
         RefreshBlockSize(TimeCurrent(), true);
      }
   }

   if(!resumed && !m_forceRebuild && HasCleanRecentHistory())
   {
      if(ReconstructStateFromCustomSymbol())
      {
         if(ConnectHistoryToLive())
         {
            resumed = true;
            Print("[Renko] AZ-style self-healing resume for ", m_customSymbol);
         }
      }
   }

   if(!resumed)
   {
      if(!BuildHistory())
         return false;
   }

   if(!SyncLiveStateWithCurrentTick())
      PrimeLiveStateFromHistory();

   if(UseWorkerSession())
      EnsureWorkerSession();

   RefreshChartHandle();
   m_isInitialized = true;
   return true;
}

void CRenkoEngine::SetChartID(long chartID)
{
   m_chartID = chartID;
}

void CRenkoEngine::Deinit()
{
   DeleteLivePreviewOverlay();
   DeletePublishedLivePreviewRate();
   CloseWorkerSession();
   FlushRamToDisk(true);
   if(m_atrHandle != INVALID_HANDLE)
   {
      IndicatorRelease(m_atrHandle);
      m_atrHandle = INVALID_HANDLE;
   }
   m_isInitialized = false;
}

void CRenkoEngine::ProcessTick(const MqlTick &tick)
{
   if(!m_isInitialized)
      return;

   if(tick.bid <= 0)
      return;

   m_lastSourceBid = tick.bid;
   m_lastSourceAsk = tick.ask;
   RefreshBlockSize(tick.time, false);

   if(UseWorkerSession() && FeedWorkerTick(tick))
      return;

   bool newBrick = ProcessRenkoTick(tick.bid, tick.time, (long)MathMax(1, tick.volume), tick.time_msc);
   if(newBrick)
      FlushRamToDisk(true);

   UpdateLiveBlock(tick.bid, tick.time, tick.time_msc, tick.bid, tick.ask, newBrick);
}

int CRenkoEngine::ProcessTickBatch(const MqlTick &ticks[], const int startIndex, const int count)
{
   if(!m_isInitialized || count <= 0 || startIndex < 0)
      return 0;

   int available = ArraySize(ticks) - startIndex;
   if(available <= 0)
      return 0;

   int actualCount = MathMin(count, available);
   if(actualCount <= 0)
      return 0;

   MqlTick lastTick = ticks[startIndex + actualCount - 1];
   if(lastTick.bid > 0)
   {
      m_lastSourceBid = lastTick.bid;
      m_lastSourceAsk = lastTick.ask;
      RefreshBlockSize(lastTick.time, false);
   }

   if(UseWorkerSession())
   {
      int fed = FeedWorkerTicksBatch(ticks, startIndex, actualCount);
      if(fed > 0)
         return fed;
   }

   int processed = 0;
   for(int i = 0; i < actualCount; i++)
   {
      ProcessTick(ticks[startIndex + i]);
      processed++;
   }
   return processed;
}

void CRenkoEngine::ProcessTimer(const MqlTick &tick, const bool hasLiveTick)
{
   if(!m_isInitialized)
      return;

   if(hasLiveTick)
   {
      if(tick.bid > 0.0)
         m_lastSourceBid = tick.bid;
      if(tick.ask > tick.bid)
         m_lastSourceAsk = tick.ask;
      if(m_lastLivePrice <= 0.0)
      {
         double livePrice = (tick.bid > 0.0) ? tick.bid : tick.last;
         if(livePrice > 0.0)
            m_lastLivePrice = NormalizePrice(livePrice);
      }

      if(UseLargeDirectLiveMode())
      {
         double livePrice = (tick.bid > 0.0) ? tick.bid : tick.last;
         if(livePrice > 0.0)
         {
            RefreshLiveCandidateState(livePrice, tick.time, true);
            UpdateLiveBlock(livePrice, tick.time, tick.time_msc, m_lastSourceBid, m_lastSourceAsk, false);
         }
      }
   }

   RefreshBlockSize(TimeCurrent(), false);
   if(m_flushPending && (GetTickCount() - m_lastFlushTryMs) > 1000)
   {
      FlushRamToDisk(true);
   }

   if(m_lastFlushTime == 0 || (GetMicrosecondCount() - m_lastFlushTime) >= 1000000)
      FlushRamToDisk();
}

void CRenkoEngine::DrawVisuals(long magic)
{
   if(m_chartID <= 0)
      return;
   if(TimeCurrent() - m_lastVisualUpdate < 1)
      return;

   m_lastVisualUpdate = TimeCurrent();
   DrawActiveTradeLines(magic);
   DrawHistoryTrendLines();
}

bool CRenkoEngine::BuildHistory()
{
   Print("🧠 AZ-style Renko build: ", m_symbol, " -> ", m_customSymbol,
         " | Family=", RenkoFamilyToString(m_renkoFamily));

   // SMART PROTECTION: If not forcing rebuild and we have data, try to resume instead of wiping.
   if(!m_forceRebuild && Bars(m_customSymbol, PERIOD_M1) > 10)
   {
      if(HasCleanRecentHistory() && ReconstructStateFromCustomSymbol())
      {
         datetime incrementalFrom = MathMax((datetime)0, m_lastCommittedTime - 7200);
         Print("[Renko] Incremental build: existing history found for ", m_customSymbol,
               ". Replaying from ", incrementalFrom, " (last brick ", m_lastCommittedTime, ")");
         return ConnectHistoryToLive();
      }
      Print("[Renko] Existing custom history failed clean-brick validation for ", m_customSymbol,
            ". Rebuilding once to restore fixed-size staircase bars.");
   }

   ResetRuntimeState();
   EnsureAtrHandle();
   RefreshBlockSize(TimeCurrent(), true);

   Print("[Renko] Hard Rebuild: Wiping custom symbol ", m_customSymbol);
   CustomRatesDelete(m_customSymbol, 0, LONG_MAX);
   CustomTicksDelete(m_customSymbol, 0, LONG_MAX);

   datetime startTime = ResolveHistoryStart();
   m_lastCommittedTime = startTime - (startTime % 60);
   m_hardCommittedTime = m_lastCommittedTime;

   bool replayOk = true;
   if(m_histDataType == DATA_M1)
   {
      replayOk = ReplayRatesFrom(startTime, false);
   }
   else if(m_histDataType == DATA_TICK)
   {
      replayOk = ReplayTicksFrom(startTime, false);
   }
   else // DATA_HYBRID
   {
      datetime transitionTime = TimeCurrent() - 86400; // 24h
      if(startTime < transitionTime)
      {
         Print("[Renko] Hybrid Stage 1: M1 deep history from ", startTime);
         replayOk = ReplayRatesFrom(startTime, false);
         if(replayOk)
            m_lastCommittedTime = transitionTime - (transitionTime % 60);
      }
      
      if(replayOk)
      {
         Print("[Renko] Hybrid Stage 2: Tick precision from ", transitionTime);
         replayOk = ReplayTicksFrom(transitionTime, true);
      }
   }

   if(!replayOk)
   {
      Print("[Renko] WARNING: Failed to build history for ", m_symbol,
            " using ", (m_histDataType == DATA_M1 ? "M1" : (m_histDataType == DATA_TICK ? "Ticks" : "Hybrid")));
      return false;
   }

   FlushRamToDisk(true);
   SyncLiveStateWithCurrentTick();
   SaveState();
   return true;
}

bool CRenkoEngine::GetBar(int shift, SMBPCustomBar &outBar)
{
   if(shift == 0 && m_liveCandidateActive)
   {
      BuildLiveBrick(outBar.open, outBar.close, outBar.high, outBar.low);
      datetime liveTickTime = (m_livePreviewEndTime > 0) ? m_livePreviewEndTime : TimeCurrent();
      outBar.time = ResolveLiveBarTime(liveTickTime);
      if(outBar.time <= 0)
         outBar.time = TimeCurrent();
      outBar.tick_volume = MathMax(1, m_tickVolBuffer);
      return true;
   }

   int committedShift = shift;
   if(m_liveCandidateActive && shift > 0)
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

void CRenkoEngine::ResetRuntimeState()
{
   ArrayFree(m_ramRateBuffer);
   m_anchorPrice = 0.0;
   m_boxHigh = 0.0;
   m_boxLow = 0.0;
   m_isTrendUp = true;
   m_lastCommittedTime = 0;
   m_lastCommittedCloseTime = 0;
   m_hardCommittedTime = 0;
   m_brickStartTime = 0;
   m_liveLogicalStartTime = 0;
   m_liveBarOpen = 0.0;
   m_liveCandidateActive = false;
   m_liveCandidateIsReversal = false;
   m_liveCandidateBullish = true;
   m_liveCandidateTargetClose = 0.0;
   m_liveCandidateClose = 0.0;
   m_lastClosePrice = 0.0;
   m_currentBlockSizePoint = 0.0;
   m_lockedBlockSize = 0.0;
   m_currentATR = 0.0;
   m_lastLivePrice = 0.0;
   m_lastSourceBid = 0.0;
   m_lastSourceAsk = 0.0;
   m_tickVolBuffer = 0;
   m_lastFlushTime = 0;
   m_lastVisualUpdate = 0;
   m_livePreviewEndTime = 0;
   ResetPublisherState();
      
   m_lastLiveQuoteTickMsc = 0;
   m_lastCommittedQuoteTickMsc = 0;
   m_lastAtrFetchMs = 0;
   m_lastBrickDayOfYear = -1;
   m_isReplayingHistory = false;
   // m_workerSessionEnabled is explicitly NOT reset here so the EA doesn't drop the setting inherited from configuration.
   m_workerSessionReady = false;
   m_workerSessionDisabled = false;
   m_workerFailureLogged = false;
   m_workerSeedBlockSize = 0.0;
   m_workerLastSnapshotTickMsc = 0;
   m_workerStallCount = 0;
   m_livePreviewGeneration = 1;
   ArrayFree(m_ramRateBuffer);
}

string CRenkoEngine::RenkoFamilyToString(const ENUM_MBP_RENKO_FAMILY family) const
{
   switch(family)
   {
      case MBP_RENKO_MEDIAN: return "MEDIAN";
      case MBP_RENKO_TURBO:  return "TURBO";
      case MBP_RENKO_HYBRID: return "HYBRID";
      default:               return "CLASSIC";
   }
}

void CRenkoEngine::EnsureAtrHandle()
{
   if(m_atrHandle != INVALID_HANDLE)
   {
      IndicatorRelease(m_atrHandle);
      m_atrHandle = INVALID_HANDLE;
   }

   if(m_blockMode == BLOCK_MODE_ATR_PERCENT)
   {
      m_atrHandle = iATR(m_symbol, m_atrTimeframe, m_atrPeriod);
      if(m_atrHandle != INVALID_HANDLE)
      {
         // Warmup loop: wait for indicator thread to catch up during hard rebuilds
         for(int i = 0; i < 5; i++)
         {
            if(BarsCalculated(m_atrHandle) > 0)
               break;
            Sleep(50);
         }
      }
   }
}

void CRenkoEngine::RefreshChartHandle()
{
   if(m_chartID <= 0 || ChartSymbol(m_chartID) != m_customSymbol)
      m_chartID = FindChartBySymbol(m_customSymbol);
}

bool CRenkoEngine::EnsureCustomSymbolReady()
{
   bool exists = (bool)SymbolInfoInteger(m_customSymbol, SYMBOL_CUSTOM);
   if(!exists)
   {
      ResetLastError();
      if(!CustomSymbolCreate(m_customSymbol, "MultiBotPro", m_symbol))
      {
         Print("[Renko] CRITICAL: CustomSymbolCreate failed for ", m_customSymbol,
               " Error: ", _LastError);
         return false;
      }
   }

   CustomSymbolSetInteger(m_customSymbol, SYMBOL_DIGITS, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS));
   CustomSymbolSetDouble(m_customSymbol, SYMBOL_POINT, SymbolInfoDouble(m_symbol, SYMBOL_POINT));
   CustomSymbolSetDouble(m_customSymbol, SYMBOL_TRADE_TICK_SIZE, SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE));
   return SymbolSelect(m_customSymbol, true);
}

datetime CRenkoEngine::ResolveHistoryStart() const
{
   if(m_startMode == MODE_FIXED_DATE && m_fixedStartDate > 0)
      return m_fixedStartDate;
   return TimeCurrent() - (m_historyDays * 86400);
}

CRenkoEngine::SAZRenkoProfile CRenkoEngine::ResolveFamilyProfile() const
{
   SAZRenkoProfile profile;
   profile.continuationOpenPct = 0.0;
   profile.reversalOpenPct = 1.0;
   profile.reversalDistancePct = 2.0;
   return profile;
}

bool CRenkoEngine::HasCleanRecentHistory()
{
   MqlRates rates[];
   int copied = CopyRates(m_customSymbol, PERIOD_M1, 0, 240, rates);
   if(copied < 10)
      return false;

   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = _Point;

   RefreshBlockSize(TimeCurrent(), true);
   double expectedBlock = (m_lockedBlockSize > 0.0) ? m_lockedBlockSize : m_currentBlockSizePoint;
   if(expectedBlock <= 0.0)
      expectedBlock = point;

   double tolerance = MathMax(point * 2.0, expectedBlock * 0.02);
   datetime newestTime = 0;
   for(int j = 0; j < copied; j++)
      if(rates[j].time > newestTime)
         newestTime = rates[j].time;

   int checked = 0;
   for(int i = 0; i < copied - 1; i++)
   {
      double brickOpen = NormalizePrice(rates[i].open);
      double brickClose = NormalizePrice(rates[i].close);
      double body = MathAbs(brickClose - brickOpen);
      if(body < point * 0.5)
         continue;

      double bodyHigh = MathMax(brickOpen, brickClose);
      double bodyLow = MathMin(brickOpen, brickClose);
      bool bodyMismatch = (MathAbs(body - expectedBlock) > tolerance);
      bool highMismatch = (MathAbs(NormalizePrice(rates[i].high) - bodyHigh) > tolerance);
      bool lowMismatch = (MathAbs(NormalizePrice(rates[i].low) - bodyLow) > tolerance);
      if(bodyMismatch || highMismatch || lowMismatch)
      {
         // The newest bar may be the live preview persisted by MT5. It is allowed
         // to be partial; committed history behind it must still be fixed-size.
         if(rates[i].time == newestTime)
            continue;
         return false;
      }
      checked++;
   }

   return (checked >= 5);
}

double CRenkoEngine::NormalizePrice(double price) const
{
   double tickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0.0)
      tickSize = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
   if(tickSize <= 0.0)
      return NormalizeDouble(price, digits);

   return NormalizeDouble(MathRound(price / tickSize) * tickSize, digits);
}

double CRenkoEngine::GetPipSize() const
{
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
   if(digits == 3 || digits == 5)
      return point * 10.0;
   return point;
}

void CRenkoEngine::RefreshBlockSize(const datetime timeRef, const bool force)
{
   if(m_blockMode == BLOCK_MODE_ATR_PERCENT && m_atrHandle != INVALID_HANDLE)
   {
      ulong nowMs = GetTickCount();
      if(force || m_currentATR <= 0.0 || !m_adaptiveATR ||
         (nowMs - m_lastAtrFetchMs) >= (ulong)MathMax(50, m_atrRefreshMs))
      {
         double atrBuffer[];
         if(CopyBuffer(m_atrHandle, 0, 0, 1, atrBuffer) > 0)
            m_currentATR = atrBuffer[0];
         m_lastAtrFetchMs = nowMs;
      }
   }

   m_currentBlockSizePoint = CalculateBlockSize(timeRef);

   // --- PYTHON AI SHADOW MASTER IPC HOOK ---
   // Allows the external Python backend to dynamically override block sizes (e.g., expanding before news)
   string pyGvName = "MBP_PY_BLOCKSIZE_" + m_symbol;
   if(GlobalVariableCheck(pyGvName))
   {
      double pyOverrideSize = GlobalVariableGet(pyGvName);
      if(pyOverrideSize > 0.0)
      {
         double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
         if(point <= 0.0) point = _Point;
         m_currentBlockSizePoint = MathMax(NormalizePrice(pyOverrideSize * point), point);
      }
   }
}

double CRenkoEngine::CalculateBlockSize(const datetime timeRef)
{
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = _Point;

   double size = 0.0;
   switch(m_blockMode)
   {
      case BLOCK_MODE_ATR_PERCENT:
         if(m_currentATR <= 0.0 && m_atrHandle != INVALID_HANDLE)
         {
            double atrBuffer[];
            if(CopyBuffer(m_atrHandle, 0, 0, 1, atrBuffer) > 0)
               m_currentATR = atrBuffer[0];
         }
         size = m_currentATR * (m_blockSizeValue / 100.0);
         break;

      case BLOCK_MODE_PIPS:
         size = m_blockSizeValue * GetPipSize();
         break;

      case BLOCK_MODE_POINTS:
      default:
         size = m_blockSizeValue * point;
         break;
   }

   if(size <= 0.0)
      size = point;

   return MathMax(NormalizePrice(size), point);
}

double CRenkoEngine::NormalizeFirstBrickAnchor(double price) const
{
   double normalized = NormalizePrice(price);
   if(!m_applyOffsetToFirstBar || m_offsetDigits <= 0)
      return normalized;

   int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
   int trimDigits = MathMin(m_offsetDigits, digits);
   if(trimDigits <= 0)
      return normalized;

   double factor = MathPow(10.0, trimDigits);
   if(factor <= 0.0)
      return normalized;

   double truncated = MathFloor(normalized * factor) / factor;
   return NormalizePrice(truncated);
}

void CRenkoEngine::ResetSessionOpenIfNeeded(const datetime tickTime)
{
   if(!m_resetOpenOnNewDay || tickTime <= 0)
      return;

   MqlDateTime ts;
   TimeToStruct(tickTime, ts);
   if(m_lastBrickDayOfYear < 0)
   {
      m_lastBrickDayOfYear = ts.day_of_year;
      return;
   }

   if(m_lastBrickDayOfYear == ts.day_of_year)
      return;

   m_lastBrickDayOfYear = ts.day_of_year;
   m_anchorPrice = NormalizeFirstBrickAnchor(m_anchorPrice);
   m_boxHigh = m_anchorPrice;
   m_boxLow = m_anchorPrice;
   m_tickVolBuffer = 0;
   ClearLiveCandidate();
}

void CRenkoEngine::SeedFromFirstPrice(const double price, const datetime tickTime)
{
   RefreshBlockSize(tickTime, true);
   if(m_lockedBlockSize <= 0.0)
      m_lockedBlockSize = m_currentBlockSizePoint;
   m_anchorPrice = NormalizeFirstBrickAnchor(price);
   m_lastClosePrice = m_anchorPrice;
   m_boxHigh = m_anchorPrice;
   m_boxLow = m_anchorPrice;
   m_liveLogicalStartTime = ResolveCandidateStartTime(tickTime);
   m_brickStartTime = ResolvePublishedCandidateTime(m_liveLogicalStartTime);
   m_liveBarOpen = m_anchorPrice;
   m_lastLivePrice = m_anchorPrice;
   m_liveCandidateActive = true;
   m_liveCandidateIsReversal = false;
   m_liveCandidateBullish = true;
   m_liveCandidateTargetClose = 0.0;
   m_liveCandidateClose = m_anchorPrice;
   m_livePreviewEndTime = tickTime;

   if(tickTime > 0)
   {
      MqlDateTime ts;
      TimeToStruct(tickTime, ts);
      m_lastBrickDayOfYear = ts.day_of_year;
   }
}

double CRenkoEngine::CalculateContinuationOpen(const bool bullishBrick, const double anchorPrice, const double blockSize) const
{
   SAZRenkoProfile profile = ResolveFamilyProfile();
   if(profile.continuationOpenPct <= 0.0)
      return NormalizePrice(anchorPrice);

   double offset = NormalizePrice(blockSize * profile.continuationOpenPct);
   return NormalizePrice(anchorPrice + (bullishBrick ? -offset : offset));
}

double CRenkoEngine::CalculateReversalDistance(const double blockSize) const
{
   SAZRenkoProfile profile = ResolveFamilyProfile();
   return NormalizePrice(blockSize * profile.reversalDistancePct);
}

double CRenkoEngine::CalculateReversalOpen(const bool bullishReversal, const double anchorPrice, const double blockSize) const
{
   SAZRenkoProfile profile = ResolveFamilyProfile();
   double offset = NormalizePrice(blockSize * profile.reversalOpenPct);
   if(offset <= 0.0)
      offset = NormalizePrice(blockSize);

   return NormalizePrice(anchorPrice + (bullishReversal ? offset : -offset));
}

double CRenkoEngine::CalculateReversalClose(const bool bullishReversal, const double anchorPrice, const double blockSize) const
{
   double distance = CalculateReversalDistance(blockSize);
   return NormalizePrice(anchorPrice + (bullishReversal ? distance : -distance));
}

datetime CRenkoEngine::ResolveCandidateStartTime(const datetime tickTime) const
{
   datetime resolved = tickTime;
   if(resolved <= 0)
      resolved = TimeCurrent();

   return resolved;
}

datetime CRenkoEngine::ResolvePublishedCandidateTime(const datetime logicalStartTime) const
{
   datetime published = (logicalStartTime > 0) ? logicalStartTime : TimeCurrent();
   
   if(m_lastCommittedTime > 0 && published <= m_lastCommittedTime)
      published = m_lastCommittedTime + 1;

   return published;
}

datetime CRenkoEngine::ResolveLiveBarTime(const datetime fallbackTickTime) const
{
   if(m_brickStartTime > 0)
      return m_brickStartTime;

   datetime logicalTime = m_liveLogicalStartTime;
   if(logicalTime <= 0)
      logicalTime = fallbackTickTime;
   if(logicalTime <= 0)
      return 0;

   return ResolvePublishedCandidateTime(logicalTime);
}

datetime CRenkoEngine::ResolveCompletedBrickTime(const datetime tickTime) const
{
   // Bar time = the timestamp of the last tick that completed this brick.
   // This is consistent with the DLL path (which returns the completing-tick
   // timestamp) and ensures history and live bars carry identical semantics.
   datetime completing = (tickTime > 0) ? tickTime : TimeCurrent();
   return ResolvePublishedCandidateTime(completing);
}

void CRenkoEngine::ClearLiveCandidate(const bool clearStartTime)
{
   m_liveCandidateActive = false;
   m_liveCandidateIsReversal = false;
   m_liveCandidateBullish = m_isTrendUp;
   m_liveBarOpen = 0.0;
   m_liveCandidateTargetClose = 0.0;
   m_liveCandidateClose = 0.0;
   m_livePreviewEndTime = 0;
   if(clearStartTime)
   {
      m_brickStartTime = 0;
      m_liveLogicalStartTime = 0;
   }
}

void CRenkoEngine::RefreshLiveCandidateState(const double price, const datetime tickTime, const bool preserveStartTime)
{
   if(m_anchorPrice == 0.0)
   {
      ClearLiveCandidate();
      return;
   }

   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = _Point;

   double normalizedPrice = NormalizePrice(price);
   double blockSize = MathMax((m_lockedBlockSize > 0.0 ? m_lockedBlockSize : m_currentBlockSizePoint), point);
   bool useReversalCandidate = m_isTrendUp
                               ? (normalizedPrice < (m_anchorPrice - point / 2.0))
                               : (normalizedPrice > (m_anchorPrice + point / 2.0));
   bool bullishCandidate = useReversalCandidate ? (!m_isTrendUp) : m_isTrendUp;

   double candidateOpen = useReversalCandidate
                          ? CalculateReversalOpen(bullishCandidate, m_anchorPrice, blockSize)
                          : CalculateContinuationOpen(bullishCandidate, m_anchorPrice, blockSize);
   double candidateTarget = useReversalCandidate
                            ? CalculateReversalClose(bullishCandidate, m_anchorPrice, blockSize)
                            : NormalizePrice(m_anchorPrice + (bullishCandidate ? blockSize : -blockSize));
   candidateOpen = NormalizePrice(candidateOpen);
   candidateTarget = NormalizePrice(candidateTarget);

   double closeMin = MathMin(candidateOpen, candidateTarget);
   double closeMax = MathMax(candidateOpen, candidateTarget);
   double candidateClose = normalizedPrice;
   if(candidateClose < closeMin)
      candidateClose = closeMin;
   if(candidateClose > closeMax)
      candidateClose = closeMax;

   bool candidateChanged = !m_liveCandidateActive
                           || (m_liveCandidateIsReversal != useReversalCandidate)
                           || (m_liveCandidateBullish != bullishCandidate)
                           || (MathAbs(m_liveBarOpen - candidateOpen) > point / 2.0)
                           || (MathAbs(m_liveCandidateTargetClose - candidateTarget) > point / 2.0);

   if(candidateChanged)
   {
      datetime logicalStart = ResolveCandidateStartTime(tickTime);
      if(preserveStartTime && m_liveCandidateActive && m_liveLogicalStartTime > 0)
         logicalStart = m_liveLogicalStartTime;

      m_liveLogicalStartTime = logicalStart;
      m_brickStartTime = ResolvePublishedCandidateTime(m_liveLogicalStartTime);

      m_boxHigh = normalizedPrice;
      m_boxLow = normalizedPrice;
   }
   else
   {
      if(m_liveLogicalStartTime <= 0)
         m_liveLogicalStartTime = ResolveCandidateStartTime(tickTime);
      if(m_brickStartTime <= 0)
         m_brickStartTime = ResolvePublishedCandidateTime(m_liveLogicalStartTime);

      m_boxHigh = MathMax(m_boxHigh, normalizedPrice);
      m_boxLow = MathMin(m_boxLow, normalizedPrice);
   }

   m_liveCandidateActive = true;
   m_liveCandidateIsReversal = useReversalCandidate;
   m_liveCandidateBullish = bullishCandidate;
   m_liveBarOpen = candidateOpen;
   m_liveCandidateTargetClose = candidateTarget;
   m_liveCandidateClose = NormalizePrice(candidateClose);
}

datetime CRenkoEngine::NextBrickStart(const datetime currentStart, const datetime tickTime) const
{
   if(currentStart <= 0)
      return tickTime;
   return (currentStart >= tickTime) ? (currentStart + 1) : tickTime;
}

bool CRenkoEngine::ProcessRenkoTick(double price, datetime tickTime, long tickVol, long tickTimeMsc)
{
   ResetSessionOpenIfNeeded(tickTime);
   double normalizedPrice = NormalizePrice(price);
   m_lastLivePrice = normalizedPrice;

   if(m_anchorPrice == 0.0)
   {
      m_tickVolBuffer = MathMax(1, tickVol);
      SeedFromFirstPrice(normalizedPrice, tickTime);
      return false;
   }

   m_tickVolBuffer += MathMax(1, tickVol);

   RefreshBlockSize(tickTime, false);
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = _Point;

   if(m_lockedBlockSize <= 0.0)
      m_lockedBlockSize = MathMax(m_currentBlockSizePoint, point);

   double blockSize = m_lockedBlockSize;
   double reversalDistance = CalculateReversalDistance(blockSize);
   bool created = false;
   int loops = 0;
   datetime nextStartTime = (m_liveLogicalStartTime > 0) ? m_liveLogicalStartTime : ResolveCandidateStartTime(tickTime);

   if(m_boxHigh == 0.0 && m_boxLow == 0.0)
   {
      m_boxHigh = normalizedPrice;
      m_boxLow = normalizedPrice;
   }
   else
   {
      m_boxHigh = MathMax(m_boxHigh, normalizedPrice);
      m_boxLow = MathMin(m_boxLow, normalizedPrice);
   }

   if(m_liveLogicalStartTime <= 0)
      m_liveLogicalStartTime = ResolveCandidateStartTime(tickTime);
   if(m_brickStartTime <= 0)
      m_brickStartTime = ResolvePublishedCandidateTime(m_liveLogicalStartTime);
   if(m_liveBarOpen <= 0.0)
      m_liveBarOpen = NormalizePrice(m_anchorPrice);
   nextStartTime = m_liveLogicalStartTime;

   while(loops++ < 1000)
   {
      bool action = false;
      double upTarget = NormalizePrice(m_anchorPrice + blockSize);
      double downTarget = NormalizePrice(m_anchorPrice - blockSize);
      double reversalUpTarget = NormalizePrice(m_anchorPrice + reversalDistance);
      double reversalDownTarget = NormalizePrice(m_anchorPrice - reversalDistance);

      if(m_isTrendUp)
      {
        if(normalizedPrice >= upTarget - point / 2.0)
        {
            double open = CalculateContinuationOpen(true, m_anchorPrice, blockSize);
            datetime completedStart = ResolveCompletedBrickTime(tickTime);
            if(!m_isReplayingHistory)
            {
               DeletePublishedLivePreviewRate();
               DeleteLivePreviewOverlay();
            }
            PushCompletedBrick(completedStart, open, upTarget, m_boxHigh, m_boxLow, m_tickVolBuffer, tickTimeMsc);
            m_anchorPrice = upTarget;
            action = true;
         }
        else if(normalizedPrice <= reversalDownTarget + point / 2.0)
        {
            double open = CalculateReversalOpen(false, m_anchorPrice, blockSize);
            double close = CalculateReversalClose(false, m_anchorPrice, blockSize);
            datetime completedStart = ResolveCompletedBrickTime(tickTime);
            if(!m_isReplayingHistory)
            {
               DeletePublishedLivePreviewRate();
               DeleteLivePreviewOverlay();
            }
            PushCompletedBrick(completedStart, open, close, m_boxHigh, m_boxLow, m_tickVolBuffer, tickTimeMsc);
            m_anchorPrice = close;
            m_isTrendUp = false;
            action = true;
         }
      }
      else
      {
        if(normalizedPrice <= downTarget + point / 2.0)
        {
            double open = CalculateContinuationOpen(false, m_anchorPrice, blockSize);
            datetime completedStart = ResolveCompletedBrickTime(tickTime);
            if(!m_isReplayingHistory)
            {
               DeletePublishedLivePreviewRate();
               DeleteLivePreviewOverlay();
            }
            PushCompletedBrick(completedStart, open, downTarget, m_boxHigh, m_boxLow, m_tickVolBuffer, tickTimeMsc);
            m_anchorPrice = downTarget;
            action = true;
         }
        else if(normalizedPrice >= reversalUpTarget - point / 2.0)
        {
            double open = CalculateReversalOpen(true, m_anchorPrice, blockSize);
            double close = CalculateReversalClose(true, m_anchorPrice, blockSize);
            datetime completedStart = ResolveCompletedBrickTime(tickTime);
            if(!m_isReplayingHistory)
            {
               DeletePublishedLivePreviewRate();
               DeleteLivePreviewOverlay();
            }
            PushCompletedBrick(completedStart, open, close, m_boxHigh, m_boxLow, m_tickVolBuffer, tickTimeMsc);
            m_anchorPrice = close;
            m_isTrendUp = true;
            action = true;
         }
      }

      if(!action)
         break;

      created = true;
      // BUG-R1 FIX: Carry the actual tick price into the next brick's wick tracking
      // instead of resetting to anchor (which discards the real high/low).
      m_boxHigh = MathMax(m_anchorPrice, normalizedPrice);
      m_boxLow = MathMin(m_anchorPrice, normalizedPrice);
      if(m_isReplayingHistory)
      {
         ClearLiveCandidate();
      }
      else
      {
         nextStartTime = NextBrickStart(nextStartTime, tickTime);
         m_liveLogicalStartTime = nextStartTime;
         m_brickStartTime = ResolvePublishedCandidateTime(m_liveLogicalStartTime);
         m_liveBarOpen = NormalizePrice(m_anchorPrice);
         m_liveCandidateActive = true;
         m_liveCandidateIsReversal = false;
         m_liveCandidateBullish = m_isTrendUp;
         m_liveCandidateTargetClose = 0.0;
         m_liveCandidateClose = m_anchorPrice;
      }
      if(m_lockedBlockSize <= 0.0)
         m_lockedBlockSize = MathMax(m_currentBlockSizePoint, point);
      blockSize = m_lockedBlockSize;
      reversalDistance = CalculateReversalDistance(blockSize);
      m_tickVolBuffer = 0;
   }

   RefreshLiveCandidateState(normalizedPrice, tickTime, false);
   if(tickTime > 0)
      m_livePreviewEndTime = tickTime;

   return created;
}

void CRenkoEngine::PushCompletedBrick(datetime startTime, double open, double close,
                                      double high, double low, long volume, long eventTimeMsc)
{
   if(startTime <= m_lastCommittedTime)
      startTime = m_lastCommittedTime + 1;

   int idx = ArraySize(m_ramRateBuffer);
   // Optimization: Increase reserve to handle history/spikes efficiently
   int reserve = m_isReplayingHistory ? 10000 : 512;
   ArrayResize(m_ramRateBuffer, idx + 1, reserve);

   double brickOpen = NormalizePrice(open);
   double brickClose = NormalizePrice(close);
   double bodyHigh = MathMax(brickOpen, brickClose);
   double bodyLow = MathMin(brickOpen, brickClose);

   m_ramRateBuffer[idx].time = startTime;
   m_ramRateBuffer[idx].open = brickOpen;
   m_ramRateBuffer[idx].high = NormalizePrice(bodyHigh);
   m_ramRateBuffer[idx].low = NormalizePrice(bodyLow);
   m_ramRateBuffer[idx].close = brickClose;
   m_ramRateBuffer[idx].tick_volume = MathMax(1, volume);
   m_ramRateBuffer[idx].spread = 0;
   m_ramRateBuffer[idx].real_volume = 0;

   m_lastClosePrice = brickClose;
   m_lastCommittedTime = startTime;
   m_lastLivePrice = brickClose;
   if(!m_isReplayingHistory)
      BumpLivePreviewGeneration();

   if(!m_isReplayingHistory)
      PublishCommittedQuote(brickClose, eventTimeMsc);
}

void CRenkoEngine::BuildLiveBrick(double &brickOpen, double &brickClose, double &brickHigh, double &brickLow)
{
   // Live-only rendering uses the same one-brick candidate as the committed
   // engine, so the preview never stretches beyond the current block.
   double liveOpen = (m_liveBarOpen > 0.0) ? m_liveBarOpen : ((m_anchorPrice > 0.0) ? m_anchorPrice : m_lastLivePrice);
   double liveClose = (m_liveCandidateClose > 0.0) ? m_liveCandidateClose : ((m_lastLivePrice > 0.0) ? m_lastLivePrice : liveOpen);
   brickOpen = NormalizePrice(liveOpen);
   brickClose = NormalizePrice(liveClose);

   if(m_showWicks)
   {
      brickHigh = MathMax(NormalizePrice(m_boxHigh), MathMax(brickOpen, brickClose));
      brickLow = MathMin(NormalizePrice(m_boxLow), MathMin(brickOpen, brickClose));
   }
   else
   {
      brickHigh = MathMax(brickOpen, brickClose);
      brickLow = MathMin(brickOpen, brickClose);
   }
}

void CRenkoEngine::UpdateLiveBlock(double price, datetime tickTime, long tickTimeMsc, double sourceBid, double sourceAsk, bool forcePublish)
{
   m_lastLivePrice = NormalizePrice(price);
   if(tickTime > 0)
      m_livePreviewEndTime = tickTime;
   long candidateTickMsc = tickTimeMsc;
   if(candidateTickMsc <= 0 && tickTime > 0)
      candidateTickMsc = (long)tickTime * 1000;
   if(candidateTickMsc > 0 && candidateTickMsc >= m_lastLiveTickMsc)
      m_lastLiveTickMsc = candidateTickMsc;

   if(UseLargeDirectLiveMode())
   {
      DeleteLivePreviewOverlay();
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(point <= 0.0)
         point = _Point;
      double bid = (sourceBid > 0.0) ? NormalizePrice(sourceBid) : m_lastLivePrice;
      double ask = (sourceAsk > bid) ? NormalizePrice(sourceAsk) : NormalizePrice(bid + point);
      UpdateCustomQuoteFields(bid, ask);
      PublishLiveQuoteTick(bid, ask, candidateTickMsc);

      if(!ShouldPublishDirectPreview(forcePublish))
         return;

      DeletePublishedLivePreviewRate();
      PublishLivePreviewRate();
   }
   else if(m_liveStyle == MBP_RENKO_LIVE_SMALL_PHANTOM)
   {
      // Phantom mode: ONLY visual overlay. NO history deletions.
      DrawLivePreviewOverlay();
   }
}

void CRenkoEngine::PublishLivePreviewRate()
{
   if(!m_liveCandidateActive)
   {
      DeletePublishedLivePreviewRate();
      return;
   }

   double brickOpen, brickClose, brickHigh, brickLow;
   BuildLiveBrick(brickOpen, brickClose, brickHigh, brickLow);

   // Don't publish a zero-body preview bar — it renders as a horizontal line and
   // adds no directional information. This happens at the very start of a new brick
   // before price has moved away from the anchor.
   {
      double pt = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(pt <= 0.0) pt = _Point;
      if(MathAbs(brickClose - brickOpen) < pt * 0.5)
      {
         DeletePublishedLivePreviewRate();
         return;
      }
   }

   datetime liveTickTime = (m_livePreviewEndTime > 0) ? m_livePreviewEndTime : TimeCurrent();
   datetime previewTime = ResolveLiveBarTime(liveTickTime);
   if(previewTime <= 0)
      previewTime = TimeCurrent();
   if(previewTime <= m_lastCommittedTime)
      previewTime = m_lastCommittedTime + 1;

   if(m_lastPublishedLiveBarTime > 0 &&
      m_lastPublishedLiveBarTime != previewTime &&
      m_lastPublishedLiveBarTime > m_lastCommittedTime)
   {
      DeletePublishedLivePreviewRate(m_lastPublishedLiveBarTime);
   }

   MqlRates previewRate[1];
   previewRate[0].time = previewTime;
   previewRate[0].open = brickOpen;
   previewRate[0].high = brickHigh;
   previewRate[0].low = brickLow;
   previewRate[0].close = brickClose;
   previewRate[0].tick_volume = MathMax((long)1, m_tickVolBuffer);
   previewRate[0].spread = 0;
   previewRate[0].real_volume = 0;

   ResetLastError();
   if(!CustomRatesUpdate(m_customSymbol, previewRate, 1))
   {
      Print("[Renko] WARNING: Live preview rate update failed for ", m_customSymbol,
            " (Err: ", _LastError, ")");
      return;
   }

   m_lastPublishedLiveBarTime = previewTime;
   RefreshChartHandle();
   if(m_chartID > 0 && ChartSymbol(m_chartID) == m_customSymbol)
      ChartRedraw(m_chartID);
}

void CRenkoEngine::DeletePublishedLivePreviewRate(const datetime barTime)
{
   datetime deleteTime = (barTime > 0) ? barTime : m_lastPublishedLiveBarTime;
   if(deleteTime <= 0)
      return;

   if(deleteTime > m_lastCommittedTime)
   {
      CustomRatesDelete(m_customSymbol, deleteTime, deleteTime);
      CustomTicksDelete(m_customSymbol, (long)deleteTime * 1000, ((long)deleteTime * 1000) + 999);
   }

   if(deleteTime == m_lastPublishedLiveBarTime)
      m_lastPublishedLiveBarTime = 0;

   RefreshChartHandle();
   if(m_chartID > 0 && ChartSymbol(m_chartID) == m_customSymbol)
      ChartRedraw(m_chartID);
}

void CRenkoEngine::UpdateCustomQuoteFields(const double bid, const double ask)
{
   CustomSymbolSetDouble(m_customSymbol, SYMBOL_BID, NormalizePrice(bid));
   CustomSymbolSetDouble(m_customSymbol, SYMBOL_ASK, NormalizePrice(ask));
   CustomSymbolSetDouble(m_customSymbol, SYMBOL_LAST, NormalizePrice(bid));
}

void CRenkoEngine::PublishLiveQuoteTick(const double bid, const double ask, long requestedTimeMsc)
{
   if(bid <= 0.0 || ask <= 0.0)
      return;

   ulong nowMs = GetTickCount();
   if(!m_tickMirroringEnabled)
   {
      if(m_tickMirrorRetryAfterMs == 0 || nowMs < m_tickMirrorRetryAfterMs)
         return;

      m_tickMirroringEnabled = true;
      m_tickMirrorFailureCount = 0;
   }

   if(requestedTimeMsc <= 0)
      requestedTimeMsc = (m_lastLiveTickMsc > 0) ? m_lastLiveTickMsc : ((long)TimeCurrent() * 1000);
   if(m_lastLiveQuoteTickMsc > 0 && requestedTimeMsc <= m_lastLiveQuoteTickMsc)
      requestedTimeMsc = m_lastLiveQuoteTickMsc + 1;
   if(m_lastCommittedQuoteTickMsc > 0 && requestedTimeMsc <= m_lastCommittedQuoteTickMsc)
      requestedTimeMsc = m_lastCommittedQuoteTickMsc + 1;

   long liveTickMsc = ReserveLiveQuoteTickTimeMsc(requestedTimeMsc);
   if(liveTickMsc <= 0)
      return;

   MqlTick liveTick[1];
   liveTick[0].time = (datetime)(liveTickMsc / 1000);
   liveTick[0].time_msc = liveTickMsc;
   liveTick[0].bid = NormalizePrice(bid);
   liveTick[0].ask = NormalizePrice(ask);
   liveTick[0].last = NormalizePrice(bid);
   liveTick[0].volume = 0;
   liveTick[0].volume_real = 0.0;
   liveTick[0].flags = TICK_FLAG_BID | TICK_FLAG_ASK | TICK_FLAG_LAST;

   ResetLastError();
   if(!CustomTicksAdd(m_customSymbol, liveTick, 1))
   {
      int err = _LastError;
      if(err != 0)
      {
         m_tickMirrorFailureCount++;
         if(m_tickMirrorFailureCount >= 10)
         {
            m_tickMirrorRetryAfterMs = nowMs + 60000;
            DisableTickMirroring("live quote publish", err);
         }
      }
      return;
   }

   m_tickMirrorFailureCount = 0;
   m_lastLiveQuoteTickMsc = liveTickMsc;
}

void CRenkoEngine::PublishCommittedQuote(const double closePrice, const long eventTimeMsc)
{
   double bid = NormalizePrice(closePrice);
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = _Point;

   double spread = (m_lastSourceAsk > m_lastSourceBid && m_lastSourceBid > 0.0)
                   ? (m_lastSourceAsk - m_lastSourceBid)
                   : point;
   double ask = NormalizePrice(bid + spread);
   UpdateCustomQuoteFields(bid, ask);

   long requestedTickMsc = eventTimeMsc;
   if(requestedTickMsc <= 0)
      requestedTickMsc = (m_lastLiveTickMsc > 0) ? m_lastLiveTickMsc : ((long)TimeCurrent() * 1000);
   if(m_lastCommittedQuoteTickMsc > 0 && requestedTickMsc <= m_lastCommittedQuoteTickMsc)
      requestedTickMsc = m_lastCommittedQuoteTickMsc + 1;

   MqlTick committedTick[1];
   committedTick[0].time = (datetime)(requestedTickMsc / 1000);
   committedTick[0].time_msc = requestedTickMsc;
   committedTick[0].bid = bid;
   committedTick[0].ask = ask;
   committedTick[0].flags = TICK_FLAG_BID | TICK_FLAG_ASK;

   ResetLastError();
   if(!CustomTicksAdd(m_customSymbol, committedTick, 1) && _LastError != 0)
   {
      Print("[Renko] WARNING: Confirmed quote tick publish failed for ", m_customSymbol,
            " (Err: ", _LastError, ")");
      return;
   }

   m_lastCommittedQuoteTickMsc = requestedTickMsc;
}

bool CRenkoEngine::UseSmallPhantomLiveMode() const
{
   return (m_liveStyle == MBP_RENKO_LIVE_SMALL_PHANTOM);
}

bool CRenkoEngine::UseLargeDirectLiveMode() const
{
   return (m_liveStyle == MBP_RENKO_LIVE_LARGE_DIRECT);
}

bool CRenkoEngine::ShouldPublishDirectPreview(const bool forcePublish)
{
   if(forcePublish || m_livePoolMs <= 0)
   {
      m_lastDirectPreviewPublishUs = GetMicrosecondCount();
      return true;
   }

   ulong nowUs = GetMicrosecondCount();
   if(m_lastDirectPreviewPublishUs == 0 ||
      nowUs <= m_lastDirectPreviewPublishUs ||
      (nowUs - m_lastDirectPreviewPublishUs) >= (ulong)m_livePoolMs * 1000)
   {
      m_lastDirectPreviewPublishUs = nowUs;
      return true;
   }
   return false;
}

string CRenkoEngine::LivePreviewBodyName() const
{
   return "PhantomRenko";
}

string CRenkoEngine::LivePreviewWickName() const
{
   return "PhantomRenkoWick";
}

color CRenkoEngine::ResolveLivePreviewColor(const long chartId, const bool bullish) const
{
   long colorValue = 0;
   if(ChartGetInteger(chartId, bullish ? CHART_COLOR_CANDLE_BULL : CHART_COLOR_CANDLE_BEAR, 0, colorValue))
      return (color)colorValue;
   return bullish ? clrLime : clrTomato;
}

void CRenkoEngine::DrawLivePreviewOverlay()
{
   if(!UseSmallPhantomLiveMode())
      return;

   long chartId = ChartFirst();
   while(chartId >= 0)
   {
      if(ChartSymbol(chartId) == m_customSymbol)
         DrawLivePreviewOverlayOnChart(chartId);
      chartId = ChartNext(chartId);
   }
}

void CRenkoEngine::DrawLivePreviewOverlayOnChart(const long chartId)
{
   if(chartId <= 0)
      return;

   if(!m_liveCandidateActive)
   {
      DeleteLivePreviewOverlayOnChart(chartId);
      return;
   }

   double brickOpen, brickClose, brickHigh, brickLow;
   BuildLiveBrick(brickOpen, brickClose, brickHigh, brickLow);

   color barColor = ResolveLivePreviewColor(chartId, brickClose >= brickOpen);
   string bodyName = LivePreviewBodyName();

   // Positioning: Start exactly 1s after the last committed bar.
   // End is set to +60s to ensure visibility on M1 charts.
   datetime tStart = (m_lastCommittedTime > 0) ? (m_lastCommittedTime + 1) : TimeCurrent();
   datetime tEnd = tStart + 60; 

   if(ObjectFind(chartId, bodyName) < 0)
   {
      ObjectCreate(chartId, bodyName, OBJ_RECTANGLE, 0, 0, 0, 0, 0);
      ObjectSetInteger(chartId, bodyName, OBJPROP_BACK, false);
      ObjectSetInteger(chartId, bodyName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(chartId, bodyName, OBJPROP_FILL, true);
      ObjectSetInteger(chartId, bodyName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(chartId, bodyName, OBJPROP_HIDDEN, true);
      ObjectSetInteger(chartId, bodyName, OBJPROP_ZORDER, 100);
   }

   ObjectSetInteger(chartId, bodyName, OBJPROP_TIME, 0, tStart);
   ObjectSetDouble(chartId, bodyName, OBJPROP_PRICE, 0, brickOpen);
   ObjectSetInteger(chartId, bodyName, OBJPROP_TIME, 1, tEnd);
   ObjectSetDouble(chartId, bodyName, OBJPROP_PRICE, 1, brickClose);
   ObjectSetInteger(chartId, bodyName, OBJPROP_COLOR, barColor);

   ChartRedraw(chartId);
}

void CRenkoEngine::DeleteLivePreviewOverlay()
{
   long chartId = ChartFirst();
   while(chartId >= 0)
   {
      if(ChartSymbol(chartId) == m_customSymbol)
         DeleteLivePreviewOverlayOnChart(chartId);
      chartId = ChartNext(chartId);
   }
}

void CRenkoEngine::DeleteLivePreviewOverlayOnChart(const long chartId) const
{
   if(chartId <= 0)
      return;

   string bodyName = LivePreviewBodyName();
   string wickName = LivePreviewWickName();
   ObjectDelete(chartId, bodyName);
   ObjectDelete(chartId, wickName);

   ChartRedraw(chartId);
}

long CRenkoEngine::ReserveLiveQuoteTickTimeMsc(long requestedTimeMsc) const
{
   if(requestedTimeMsc <= 0)
      return 0;
   if(m_lastLiveTickMsc > 0 && requestedTimeMsc < m_lastLiveTickMsc)
      return 0;
   return requestedTimeMsc;
}

void CRenkoEngine::DisableTickMirroring(string stage, int errorCode)
{
   m_tickMirroringEnabled = false;
   if(m_tickMirrorWarningLogged)
      return;

   m_tickMirrorWarningLogged = true;
   Print("[Renko] WARNING: Custom tick mirroring disabled for ", m_customSymbol,
         " after repeated ", stage, " failures (Err: ", errorCode,
         "). Rates-only mode will continue until the next retry window.");
}

void CRenkoEngine::FlushRamToDisk(bool force)
{
   int total = ArraySize(m_ramRateBuffer);
   if(total <= 0)
      return;

   if(!force && total < 50 && (GetMicrosecondCount() - m_lastFlushTime) < 250000)
      return;

   DeletePublishedLivePreviewRate();
   for(int i = 0; i < total; i++)
   {
      double bodyHigh = MathMax(m_ramRateBuffer[i].open, m_ramRateBuffer[i].close);
      double bodyLow = MathMin(m_ramRateBuffer[i].open, m_ramRateBuffer[i].close);
      m_ramRateBuffer[i].high = NormalizePrice(bodyHigh);
      m_ramRateBuffer[i].low = NormalizePrice(bodyLow);
   }
   ResetLastError();
   m_lastFlushTryMs = GetTickCount();

   bool ratesOk = CustomRatesUpdate(m_customSymbol, m_ramRateBuffer, total);
   int rateErr = _LastError;
   
   if(!ratesOk)
   {
      if(!m_flushPending)
      {
         Print("[Renko] WARNING: Buffered rate flush failed for ", m_customSymbol,
               " | Bars: ", total, " (Err: ", rateErr, "). Flagged for retry.");
      }
      m_flushPending = true;
      return;
   }

   m_flushPending = false;
   m_hardCommittedTime = m_ramRateBuffer[total - 1].time;
   SaveState();
   ArrayFree(m_ramRateBuffer);
   m_lastFlushTime = GetMicrosecondCount();

   RefreshChartHandle();
   if(m_chartID > 0 && ChartSymbol(m_chartID) == m_customSymbol)
      ChartRedraw(m_chartID);
}

bool CRenkoEngine::ReplayRatesFrom(const datetime fromTime, const bool skipCommitted)
{
   m_isReplayingHistory = true;
   MqlRates src[];
   CopyRates(m_symbol, PERIOD_M1, 0, 10, src);

   int total = CopyRates(m_symbol, PERIOD_M1, fromTime, TimeCurrent(), src);
   if(total <= 0)
   {
      total = CopyRates(m_symbol, PERIOD_M1, 0, 1000, src);
      if(total <= 0)
      {
         m_isReplayingHistory = false;
         return false;
      }
   }

   if(m_anchorPrice == 0.0 && total > 0)
      SeedFromFirstPrice(src[0].open, src[0].time);

   if(UseWorkerSession())
   {
      if(EnsureWorkerSession())
      {
         // Deep M1 history is handled by the DLL. Pass one real M1 OHLC row per
         // source bar; the backend expands it into deterministic sub-ticks.
         double opens[];
         double highs[];
         double lows[];
         double closes[];
         long times[];
         ArrayResize(opens, total);
         ArrayResize(highs, total);
         ArrayResize(lows, total);
         ArrayResize(closes, total);
         ArrayResize(times, total);

         int validCount = 0;
         datetime lastBarTimeTmp = (total > 0) ? src[0].time : 0;
         for(int i = 0; i < total; i++)
         {
            if(skipCommitted && src[i].time <= m_lastCommittedTime)
               continue;

            if(src[i].time - lastBarTimeTmp > 14400)
            {
               datetime snapped = src[i].time - (src[i].time % 60);
               if(snapped > m_lastCommittedTime)
                  m_lastCommittedTime = snapped - 60;
            }
            lastBarTimeTmp = src[i].time;

            long baseTimeMsc = (long)src[i].time * 1000;
            opens[validCount] = src[i].open;
            highs[validCount] = src[i].high;
            lows[validCount] = src[i].low;
            closes[validCount] = src[i].close;
            times[validCount] = baseTimeMsc;
            validCount++;

            /*
            // so bricks that complete at different ticks receive distinct second-level
            // timestamps. This prevents all bricks from an M1 bar clustering at t+0,
            // which would produce narrow bars separated by 57-second visual gaps on the
            // Renko chart.  The ordering (open → adverse → favourable → close) mirrors
            // the BUG-R2 MQL5 fallback so the DLL sees the same brick sequence.
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
            */
         }

         if(validCount > 0)
         {
            ArrayResize(opens, validCount);
            ArrayResize(highs, validCount);
            ArrayResize(lows, validCount);
            ArrayResize(closes, validCount);
            ArrayResize(times, validCount);
            long lastFedTimeMsc = times[validCount - 1] + 59000;
            int queuedTicks = MBP_RenkoFeedM1RatesW(m_workerSessionKey, m_customSymbol,
                                                   opens, highs, lows, closes, times, validCount);
            if(queuedTicks > 0)
            {
               // MBP_RenkoFeedM1RatesW is asynchronous: it enqueues and signals the
               // background DLL worker thread. We must poll until lastTickMsc reaches
               // the last fed timestamp before draining, or we'll get 0 bars back.
               long histInfo[];
               ArrayResize(histInfo, 4);
               ulong pollStart = GetTickCount();
               const ulong pollTimeoutMs = 30000; // 30s max wait
               while((GetTickCount() - pollStart) < pollTimeoutMs)
               {
                  if(MBP_RenkoGetHistoryInfoW(m_workerSessionKey, m_customSymbol, histInfo) > 0)
                  {
                     if(histInfo[3] >= lastFedTimeMsc)
                        break;
                  }
                  Sleep(5);
               }
               int totalDrained = 0;
               int drainBatch;
               while((drainBatch = DrainWorkerClosedBars()) > 0)
                  totalDrained += drainBatch;
               PullWorkerSnapshot();

               if(totalDrained == 0)
               {
                  Print("[Renko] DLL M1 history produced 0 bricks for ", m_customSymbol,
                        ". Falling back to MQL5 loop.");
                  DisableWorkerSession("DLL M1 history produced 0 bricks");
                  // fall through to MQL5 loop below
               }
               else
               {
                  Print("[Renko] DLL M1 history generated ", totalDrained,
                        " bricks for ", m_customSymbol, ".");
                  m_isReplayingHistory = false;
                  return true;
               }
            }
            else
            {
               Print("[Renko] WARNING: DLL deep M1 history feed failed for ", m_customSymbol,
                     ". Falling back to MQL5 ProcessRenkoTick loop.");
               DisableWorkerSession("deep M1 history feed failed");
            }
         }
      }
   }

   datetime lastBarTime = (total > 0) ? src[0].time : 0;
   for(int i = 0; i < total; i++)
   {
      if(skipCommitted && src[i].time <= m_lastCommittedTime)
         continue;

      if(src[i].time - lastBarTime > 14400)
      {
         datetime snapped = src[i].time - (src[i].time % 60);
         if(snapped > m_lastCommittedTime)
            m_lastCommittedTime = snapped - 60;
      }
      lastBarTime = src[i].time;

      long volPart = MathMax(1, src[i].tick_volume / 4);
      long baseTimeMsc = (long)src[i].time * 1000;

      // Spread the 4 synthetic sub-ticks across the 60-second M1 window at 0, 20, 40,
      // and 59 seconds. This mirrors the DLL path exactly so completed bricks carry the
      // timestamp of the sub-tick that triggered completion (last-tick semantics).
      // PushCompletedBrick updates m_lastCommittedTime for each brick, enforcing
      // monotonicity without any outer time-override loop.
      ProcessRenkoTick(src[i].open,  src[i].time,      volPart, baseTimeMsc);
      if(src[i].close >= src[i].open)
      {
         ProcessRenkoTick(src[i].low,  src[i].time + 20, volPart, baseTimeMsc + 20000);
         ProcessRenkoTick(src[i].high, src[i].time + 40, volPart, baseTimeMsc + 40000);
      }
      else
      {
         ProcessRenkoTick(src[i].high, src[i].time + 20, volPart, baseTimeMsc + 20000);
         ProcessRenkoTick(src[i].low,  src[i].time + 40, volPart, baseTimeMsc + 40000);
      }
      ProcessRenkoTick(src[i].close, src[i].time + 59, volPart, baseTimeMsc + 59000);
   }

   m_isReplayingHistory = false;
   return true;
}

bool CRenkoEngine::ReplayTicksFrom(const datetime fromTime, const bool skipCommitted)
{
   m_isReplayingHistory = true;
   MqlTick ticks[];
   int total = CopyTicksRange(m_symbol, ticks, COPY_TICKS_ALL, (ulong)fromTime * 1000, (ulong)TimeCurrent() * 1000);
   if(total <= 0)
   {
      m_isReplayingHistory = false;
      return false;
   }

   if(m_anchorPrice == 0.0)
   {
      int seedIdx = 0;
      while(seedIdx < total && ticks[seedIdx].bid <= 0.0)
         seedIdx++;
      if(seedIdx >= total)
      {
         m_isReplayingHistory = false;
         return false;
      }
      SeedFromFirstPrice(ticks[seedIdx].bid, ticks[seedIdx].time);
   }

   if(UseWorkerSession())
   {
      if(EnsureWorkerSession())
      {
         double prices[];
         long times[];
         ArrayResize(prices, total);
         ArrayResize(times, total);
         
         int validCount = 0;
         datetime lastTickTimeTmp = 0;
         for(int i = 0; i < total; i++)
         {
            if(ticks[i].bid <= 0.0)
               continue;
            if(skipCommitted && ticks[i].time <= m_lastCommittedTime)
               continue;

            if(lastTickTimeTmp > 0 && ticks[i].time - lastTickTimeTmp > 14400)
            {
               datetime snapped = ticks[i].time - (ticks[i].time % 60);
               if(snapped > m_lastCommittedTime)
                  m_lastCommittedTime = snapped - 60;
            }
            lastTickTimeTmp = ticks[i].time;

            long tickMsc = (ticks[i].time_msc > 0) ? ticks[i].time_msc : ((long)ticks[i].time * 1000);
            if(tickMsc <= 0)
               tickMsc = (long)TimeCurrent() * 1000;

            prices[validCount] = ticks[i].bid;
            times[validCount] = tickMsc;
            validCount++;
         }
         
         if(validCount > 0)
         {
            ArrayResize(prices, validCount);
            ArrayResize(times, validCount);
            long lastFedTimeMsc = times[validCount - 1];
            if(MBP_RenkoFeedTicksW(m_workerSessionKey, m_customSymbol, prices, times, validCount) > 0)
            {
               // MBP_RenkoFeedTicksW is asynchronous: poll until the DLL worker thread
               // has consumed all queued ticks (lastTickMsc reaches lastFedTimeMsc).
               long histInfo[];
               ArrayResize(histInfo, 4);
               ulong pollStart = GetTickCount();
               const ulong pollTimeoutMs = 30000;
               while((GetTickCount() - pollStart) < pollTimeoutMs)
               {
                  if(MBP_RenkoGetHistoryInfoW(m_workerSessionKey, m_customSymbol, histInfo) > 0)
                  {
                     if(histInfo[3] >= lastFedTimeMsc)
                        break;
                  }
                  Sleep(5);
               }
               int totalDrainedT = 0;
               int drainBatchT;
               while((drainBatchT = DrainWorkerClosedBars()) > 0)
                  totalDrainedT += drainBatchT;
               PullWorkerSnapshot();

               if(totalDrainedT == 0)
               {
                  Print("[Renko] DLL tick history produced 0 bricks for ", m_customSymbol,
                        ". Falling back to MQL5 loop.");
                  DisableWorkerSession("DLL tick history produced 0 bricks");
                  // fall through to MQL5 loop below
               }
               else
               {
                  Print("[Renko] DLL tick history generated ", totalDrainedT,
                        " bricks for ", m_customSymbol, ".");
                  m_isReplayingHistory = false;
                  return true;
               }
            }
            else
            {
               Print("[Renko] WARNING: DLL bulk ticks feed failed. Falling back to MQL5 loop.");
               DisableWorkerSession("bulk tick feed failed");
            }
         }
      }
   }

   datetime lastTickTime = 0;
   for(int i = 0; i < total; i++)
   {
      if(ticks[i].bid <= 0.0)
         continue;
      if(skipCommitted && ticks[i].time <= m_lastCommittedTime)
         continue;

      if(lastTickTime > 0 && ticks[i].time - lastTickTime > 14400)
      {
         datetime snapped = ticks[i].time - (ticks[i].time % 60);
         if(snapped > m_lastCommittedTime)
            m_lastCommittedTime = snapped - 60;
      }
      lastTickTime = ticks[i].time;

      ProcessRenkoTick(ticks[i].bid, ticks[i].time, 1, ticks[i].time_msc);
   }

   m_isReplayingHistory = false;
   return true;
}

bool CRenkoEngine::ConnectHistoryToLive()
{
   m_lastPublishedLiveBarTime = 0;
   datetime replayFrom = (m_lastCommittedTime > 0) ? MathMax((datetime)0, m_lastCommittedTime - 7200) : (TimeCurrent() - 172800);

   if(m_lastCommittedTime > 0)
   {
      MqlRates seedRates[];
      int copied = CopyRates(m_customSymbol, PERIOD_M1, 0, 5000, seedRates);
      int seedIndex = -1;
      for(int i = 1; i < copied; i++)
      {
         if(seedRates[i].time < replayFrom)
            seedIndex = i;
      }

      if(seedIndex >= 1)
      {
         ReconstructStateFromRatePair(seedRates[seedIndex - 1], seedRates[seedIndex]);
         Print("[Renko] Incremental seed retained at ", m_lastCommittedTime,
               "; rebuilding overlap from ", replayFrom);
      }

      CustomRatesDelete(m_customSymbol, m_lastCommittedTime + 1, LONG_MAX);
      CustomTicksDelete(m_customSymbol, ((long)m_lastCommittedTime + 1) * 1000, LONG_MAX);
   }

   bool replayOk = (m_histDataType == DATA_M1)
                   ? ReplayRatesFrom(replayFrom, true)
                   : ReplayTicksFrom(replayFrom, true);

   if(!replayOk)
      return false;

   FlushRamToDisk(true);
   SyncLiveStateWithCurrentTick();
   SaveState();
   return true;
}

bool CRenkoEngine::SyncLiveStateWithCurrentTick()
{
   MqlTick liveTick;
   if(SymbolInfoTick(m_symbol, liveTick) && liveTick.bid > 0)
   {
      if(liveTick.time_msc <= 0 && liveTick.time > 0)
         liveTick.time_msc = (long)liveTick.time * 1000;
      m_lastSourceBid = liveTick.bid;
      m_lastSourceAsk = liveTick.ask;
      m_lastLivePrice = NormalizePrice(liveTick.bid);
      RefreshBlockSize(liveTick.time, false);
      bool newBrick = ProcessRenkoTick(liveTick.bid, liveTick.time, (long)MathMax(1, liveTick.volume), liveTick.time_msc);
      if(newBrick)
         FlushRamToDisk(true);
      UpdateLiveBlock(liveTick.bid, liveTick.time, liveTick.time_msc, liveTick.bid, liveTick.ask, newBrick);
      return true;
   }

   return false;
}

void CRenkoEngine::PrimeLiveStateFromHistory()
{
   if(m_anchorPrice == 0.0)
      return;

   m_lastPublishedLiveBarTime = 0;

   if(m_lastLivePrice <= 0.0)
      m_lastLivePrice = (m_lastClosePrice > 0.0) ? m_lastClosePrice : m_anchorPrice;

   double bid = (m_lastSourceBid > 0.0) ? m_lastSourceBid : m_lastLivePrice;
   double ask = (m_lastSourceAsk > bid) ? m_lastSourceAsk : (bid + SymbolInfoDouble(m_symbol, SYMBOL_POINT));

   RefreshBlockSize(TimeCurrent(), false);
   if(m_liveLogicalStartTime <= 0)
      m_liveLogicalStartTime = TimeCurrent();
   if(m_brickStartTime <= 0)
      m_brickStartTime = ResolvePublishedCandidateTime(m_liveLogicalStartTime);
   m_liveBarOpen = NormalizePrice(m_anchorPrice);
   m_liveCandidateActive = true;
   m_liveCandidateIsReversal = false;
   m_liveCandidateBullish = (m_lastLivePrice >= m_liveBarOpen);
   m_liveCandidateTargetClose = 0.0;
   m_liveCandidateClose = m_lastLivePrice;
   m_boxHigh = MathMax(m_anchorPrice, m_lastLivePrice);
   m_boxLow = MathMin(m_anchorPrice, m_lastLivePrice);
   m_livePreviewEndTime = m_liveLogicalStartTime;
   UpdateCustomQuoteFields(bid, ask);
   UpdateLiveBlock(m_lastLivePrice, 0, 0, bid, ask, true);
}

bool CRenkoEngine::UseWorkerSession() const
{
   return m_workerSessionEnabled && !m_workerSessionDisabled;
}

bool CRenkoEngine::WorkerSessionNeedsReseed() const
{
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = _Point;

   if(m_workerSeedBlockSize <= 0.0)
      return true;

   return false;
}

void CRenkoEngine::BumpLivePreviewGeneration()
{
   m_livePreviewGeneration++;
   if(m_livePreviewGeneration > 1000000)
      m_livePreviewGeneration = 1;
}

bool CRenkoEngine::EnsureWorkerSession()
{
   if(!UseWorkerSession())
      return false;

   if(MBP_QueryRenkoBackendW("", "session") <= 0)
   {
      DisableWorkerSession("session backend unavailable");
      return false;
   }

   if(m_workerSessionKey == "")
      m_workerSessionKey = m_customSymbol;

   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = _Point;
   int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);

   if(!m_workerSessionReady)
   {
      if(MBP_RenkoOpenSessionW(m_workerSessionKey, m_customSymbol, (int)MBP_RENKO_CLASSIC, point, digits) <= 0)
      {
         DisableWorkerSession("open session failed");
         return false;
      }
      m_workerSessionReady = true;
      Print("[Renko] DLL session opened for ", m_customSymbol,
            " from ", m_symbol, " (key=", m_workerSessionKey, ").");
   }

   if(WorkerSessionNeedsReseed())
   {
      if(MBP_RenkoResetSessionW(m_workerSessionKey, m_customSymbol) <= 0)
      {
         DisableWorkerSession("reset session failed");
         return false;
      }
      double seedBlockSize = (m_lockedBlockSize > 0.0) ? m_lockedBlockSize : m_currentBlockSizePoint;
      if(MBP_RenkoSeedSessionW(m_workerSessionKey, m_customSymbol,
                              m_anchorPrice, m_isTrendUp ? 1 : 0, seedBlockSize,
                              m_openOffsetPct, m_reversalShadowPct, m_reversalPct,
                              m_applyOffsetToFirstBar ? 1 : 0, m_offsetDigits,
                              m_resetOpenOnNewDay ? 1 : 0) <= 0)
      {
         DisableWorkerSession("seed session failed");
         return false;
      }
      m_workerSeedBlockSize = seedBlockSize;
      m_workerLastReseedMs = GetTickCount();
      m_workerSessionEnabled = true;
      m_workerStallCount = 0;
      Print("[Renko] DLL acceleration active for ", m_customSymbol,
            " block=", DoubleToString(seedBlockSize, digits),
            " anchor=", DoubleToString(m_anchorPrice, digits),
            " direction=", (m_isTrendUp ? "UP" : "DOWN"), ".");
   }

   return true;
}

void CRenkoEngine::CloseWorkerSession()
{
   if(m_workerSessionReady && m_workerSessionKey != "")
      MBP_RenkoCloseSessionW(m_workerSessionKey, m_customSymbol);
   m_workerSessionReady = false;
   m_workerSessionEnabled = false;
   m_workerSeedBlockSize = 0.0;
   m_workerLastReseedMs = 0;
   m_workerLastSnapshotTickMsc = 0;
   m_workerStallCount = 0;
}

void CRenkoEngine::DisableWorkerSession(string reason)
{
   if(!m_workerFailureLogged)
   {
      Print("[Renko] Worker session disabled for ", m_customSymbol, ": ", reason, ". Falling back to native live engine.");
      m_workerFailureLogged = true;
   }
   CloseWorkerSession();
   m_workerSessionDisabled = true;
}

bool CRenkoEngine::PullWorkerSnapshot()
{
   if(!m_workerSessionReady)
      return false;

   double snapshotDoubles[];
   long snapshotLongs[];
   ArrayResize(snapshotDoubles, 9);
   ArrayResize(snapshotLongs, 10);
   if(MBP_RenkoReadSnapshotW(m_workerSessionKey, m_customSymbol, snapshotDoubles, snapshotLongs) <= 0)
      return false;

   m_anchorPrice = snapshotDoubles[0];
   m_boxHigh = snapshotDoubles[1];
   m_boxLow = snapshotDoubles[2];
   m_liveBarOpen = snapshotDoubles[3];
   m_liveCandidateClose = snapshotDoubles[4];
   m_liveCandidateTargetClose = snapshotDoubles[5];
   m_lastClosePrice = snapshotDoubles[6];
   m_lastLivePrice = snapshotDoubles[7];
   m_currentBlockSizePoint = snapshotDoubles[8];

   m_isTrendUp = (snapshotLongs[2] != 0);
   m_liveCandidateActive = (snapshotLongs[3] != 0);
   m_liveCandidateBullish = (snapshotLongs[4] != 0);
   m_liveCandidateIsReversal = (snapshotLongs[5] != 0);
   m_liveLogicalStartTime = (datetime)snapshotLongs[6];
   m_livePreviewEndTime = (datetime)snapshotLongs[7];
   m_workerLastSnapshotTickMsc = snapshotLongs[8];
   if(m_liveLogicalStartTime > 0)
      m_brickStartTime = ResolvePublishedCandidateTime(m_liveLogicalStartTime);

   return true;
}

int CRenkoEngine::DrainWorkerClosedBars()
{
   if(!m_workerSessionReady)
      return 0;

   double closedDoubles[];
   long closedLongs[];
   ArrayResize(closedDoubles, 64 * 4);
   ArrayResize(closedLongs, 64 * 3);
   int count = MBP_RenkoReadClosedBarsW(m_workerSessionKey, m_customSymbol, closedDoubles, closedLongs, 64);
   if(count <= 0)
      return 0;

   DeletePublishedLivePreviewRate();
   DeleteLivePreviewOverlay();
   BumpLivePreviewGeneration();

   for(int i = 0; i < count; i++)
   {
      datetime startTime = (datetime)closedLongs[i * 3 + 0];
      // Use the actual tick-based timestamp emitted by the engine; only
      // synthesise +1 when needed to enforce monotonicity.
      if(m_lastCommittedTime > 0 && startTime <= m_lastCommittedTime)
         startTime = m_lastCommittedTime + 1;

      int idx = ArraySize(m_ramRateBuffer);
      ArrayResize(m_ramRateBuffer, idx + 1, 128);
      double brickOpen = NormalizePrice(closedDoubles[i * 4 + 0]);
      double brickClose = NormalizePrice(closedDoubles[i * 4 + 3]);

      // A Renko brick must always have a body. Zero-body bars indicate a DLL
      // precision fault — skip them to prevent horizontal-line artefacts on the chart.
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(point <= 0.0) point = _Point;
      if(MathAbs(brickClose - brickOpen) < point * 0.5)
      {
         m_lastCommittedTime = startTime;
         continue;
      }

      double bodyHigh = MathMax(brickOpen, brickClose);
      double bodyLow = MathMin(brickOpen, brickClose);
      m_ramRateBuffer[idx].time = startTime;
      m_ramRateBuffer[idx].open = brickOpen;
      m_ramRateBuffer[idx].high = NormalizePrice(bodyHigh);
      m_ramRateBuffer[idx].low = NormalizePrice(bodyLow);
      m_ramRateBuffer[idx].close = brickClose;
      m_ramRateBuffer[idx].tick_volume = MathMax((long)1, closedLongs[i * 3 + 1]);
      m_ramRateBuffer[idx].spread = 0;
      m_ramRateBuffer[idx].real_volume = 0;

      m_lastCommittedTime = startTime;
      m_lastClosePrice = m_ramRateBuffer[idx].close;
      m_lastLivePrice = m_lastClosePrice;
      PublishCommittedQuote(m_lastClosePrice, closedLongs[i * 3 + 2]);
   }

   return count;
}

bool CRenkoEngine::FeedWorkerTick(const MqlTick &tick)
{
   MqlTick batch[];
   ArrayResize(batch, 1);
   batch[0] = tick;
   return (FeedWorkerTicksBatch(batch, 0, 1) > 0);
}

int CRenkoEngine::FeedWorkerTicksBatch(const MqlTick &ticks[], const int startIndex, const int count)
{
   if(!EnsureWorkerSession() || count <= 0 || startIndex < 0)
      return 0;

   int available = ArraySize(ticks) - startIndex;
   if(available <= 0)
      return 0;

   int actualCount = MathMin(count, available);
   if(actualCount <= 0)
      return 0;

   double prices[];
   long times[];
   int valid = 0;
   double lastMirrorBid = 0.0;
   double lastMirrorAsk = 0.0;
   long lastMirrorTimeMsc = 0;
   ArrayResize(prices, actualCount);
   ArrayResize(times, actualCount);
   for(int i = 0; i < actualCount; i++)
   {
      const MqlTick tick = ticks[startIndex + i];
      if(tick.bid <= 0.0)
         continue;

      long tickMsc = (tick.time_msc > 0) ? tick.time_msc : ((long)tick.time * 1000);
      if(tickMsc <= 0)
         tickMsc = (long)TimeCurrent() * 1000;

      prices[valid] = tick.bid;
      times[valid] = tickMsc;
      lastMirrorBid = tick.bid;
      lastMirrorAsk = tick.ask;
      lastMirrorTimeMsc = tickMsc;
      valid++;
   }

   if(valid <= 0)
      return actualCount;

   ArrayResize(prices, valid);
   ArrayResize(times, valid);

   if(MBP_RenkoFeedTicksW(m_workerSessionKey, m_customSymbol, prices, times, valid) <= 0)
   {
      DisableWorkerSession("feed tick batch failed");
      return 0;
   }

   if(UseLargeDirectLiveMode() && lastMirrorBid > 0.0)
   {
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(point <= 0.0)
         point = _Point;
      double liveAsk = (lastMirrorAsk > lastMirrorBid) ? lastMirrorAsk : (lastMirrorBid + point);
      UpdateCustomQuoteFields(lastMirrorBid, liveAsk);
      PublishLiveQuoteTick(lastMirrorBid, liveAsk, lastMirrorTimeMsc);
   }

   int closed = 0;
   long previousSnapshotTickMsc = m_workerLastSnapshotTickMsc;
   bool freshSnapshot = false;
   for(int attempt = 0; attempt < 2; attempt++)
   {
      closed += DrainWorkerClosedBars();
      if(!PullWorkerSnapshot())
      {
         DisableWorkerSession("snapshot read failed");
         return 0;
      }

      if(m_workerLastSnapshotTickMsc >= times[valid - 1] ||
         m_workerLastSnapshotTickMsc > previousSnapshotTickMsc)
      {
         freshSnapshot = true;
         break;
      }
   }

   if(!freshSnapshot)
   {
      m_workerStallCount++;
      if(m_workerStallCount >= 10)
      {
         DisableWorkerSession("snapshot stalled");
         return 0;
      }
   }
   else
   {
      m_workerStallCount = 0;
   }

   if(closed > 0)
      FlushRamToDisk(true);

   if(m_liveCandidateActive)
   {
      double liveBid = (m_lastSourceBid > 0.0) ? m_lastSourceBid : ((m_lastLivePrice > 0.0) ? m_lastLivePrice : m_anchorPrice);
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(point <= 0.0)
         point = _Point;
      double liveAsk = (m_lastSourceAsk > liveBid) ? m_lastSourceAsk : (liveBid + point);
      UpdateLiveBlock(m_liveCandidateClose, m_livePreviewEndTime, m_workerLastSnapshotTickMsc, liveBid, liveAsk, (closed > 0));
   }
   else
   {
      DeletePublishedLivePreviewRate();
      DeleteLivePreviewOverlay();
   }

   return actualCount;
}

void CRenkoEngine::SaveState()
{
   GlobalVariableSet(m_gvPrefix + "_Anchor", m_anchorPrice);
   GlobalVariableSet(m_gvPrefix + "_Trend", (double)m_isTrendUp);
   GlobalVariableSet(m_gvPrefix + "_LastTime", (double)m_lastCommittedTime);
   GlobalVariableSet(m_gvPrefix + "_LastCloseTime", (double)m_lastCommittedCloseTime);
   GlobalVariableSet(m_gvPrefix + "_High", m_boxHigh);
   GlobalVariableSet(m_gvPrefix + "_Low", m_boxLow);
   GlobalVariableSet(m_gvPrefix + "_LastClose", m_lastClosePrice);
   GlobalVariableSet(m_gvPrefix + "_BlockSize", m_lockedBlockSize);
   GlobalVariableSet(m_gvPrefix + "_BrickStart", (double)m_brickStartTime);
   GlobalVariableSet(m_gvPrefix + "_LogicalStart", (double)m_liveLogicalStartTime);
   GlobalVariableSet(m_gvPrefix + "_LiveOpen", m_liveBarOpen);
   GlobalVariableSet(m_gvPrefix + "_TrendDay", (double)m_lastBrickDayOfYear);
}

bool CRenkoEngine::LoadState()
{
   if(!GlobalVariableCheck(m_gvPrefix + "_Anchor"))
      return false;

   m_anchorPrice = GlobalVariableGet(m_gvPrefix + "_Anchor");
   m_isTrendUp = (bool)GlobalVariableGet(m_gvPrefix + "_Trend");
   m_lastCommittedTime = (datetime)GlobalVariableGet(m_gvPrefix + "_LastTime");
   m_hardCommittedTime = m_lastCommittedTime;
   m_lastCommittedCloseTime = GlobalVariableCheck(m_gvPrefix + "_LastCloseTime")
                              ? (datetime)GlobalVariableGet(m_gvPrefix + "_LastCloseTime")
                              : m_lastCommittedTime; // Fallback for sessions saved before this field existed
   m_boxHigh = GlobalVariableGet(m_gvPrefix + "_High");
   m_boxLow = GlobalVariableGet(m_gvPrefix + "_Low");
   m_lastClosePrice = GlobalVariableGet(m_gvPrefix + "_LastClose");
   m_lockedBlockSize = GlobalVariableCheck(m_gvPrefix + "_BlockSize")
                       ? GlobalVariableGet(m_gvPrefix + "_BlockSize")
                       : 0.0;
   if(m_lockedBlockSize <= 0.0)
   {
      RefreshBlockSize(TimeCurrent(), true);
      m_lockedBlockSize = m_currentBlockSizePoint;
   }
   m_brickStartTime = GlobalVariableCheck(m_gvPrefix + "_BrickStart")
                      ? (datetime)GlobalVariableGet(m_gvPrefix + "_BrickStart")
                      : 0;
   m_liveLogicalStartTime = GlobalVariableCheck(m_gvPrefix + "_LogicalStart")
                            ? (datetime)GlobalVariableGet(m_gvPrefix + "_LogicalStart")
                            : m_brickStartTime;
   m_liveBarOpen = GlobalVariableCheck(m_gvPrefix + "_LiveOpen")
                   ? GlobalVariableGet(m_gvPrefix + "_LiveOpen")
                   : 0.0;
   m_liveCandidateActive = false;
   m_liveCandidateIsReversal = false;
   m_liveCandidateBullish = m_isTrendUp;
   m_liveCandidateTargetClose = 0.0;
   m_liveCandidateClose = 0.0;
   m_lastBrickDayOfYear = GlobalVariableCheck(m_gvPrefix + "_TrendDay")
                          ? (int)GlobalVariableGet(m_gvPrefix + "_TrendDay")
                          : -1;
   m_livePreviewEndTime = m_liveLogicalStartTime;
   m_lastLiveTickMsc = 0;
   m_lastLiveQuoteTickMsc = 0;
   m_lastLivePrice = (m_lastClosePrice > 0.0) ? m_lastClosePrice : m_anchorPrice;
   return true;
}

void CRenkoEngine::DrawActiveTradeLines(long magic)
{
   // Intentionally minimal. MultiBotPro draws the main overlays natively.
}

void CRenkoEngine::DrawHistoryTrendLines()
{
   // Intentionally minimal. MultiBotPro draws the main overlays natively.
}

long CRenkoEngine::FindChartBySymbol(string sym)
{
   long chartId = ChartFirst();
   while(chartId >= 0)
   {
      if(ChartSymbol(chartId) == sym)
         return chartId;
      chartId = ChartNext(chartId);
   }
   return 0;
}

bool CRenkoEngine::ReconstructStateFromCustomSymbol()
{
   MqlRates rates[];
   if(CopyRates(m_customSymbol, PERIOD_M1, 0, 2, rates) < 2)
      return false;

   // Element with index 1 is newer than index 0 in MT5 CopyRates
   ReconstructStateFromRatePair(rates[0], rates[1]);
   return true;
}

void CRenkoEngine::ReconstructStateFromRatePair(const MqlRates &prev, const MqlRates &last)
{
   m_lastClosePrice = last.close;
   m_anchorPrice = last.close;
   m_lastCommittedTime = last.time;
   m_lockedBlockSize = MathAbs(NormalizePrice(last.close) - NormalizePrice(last.open));
   if(m_lockedBlockSize <= 0.0)
   {
      RefreshBlockSize(last.time, true);
      m_lockedBlockSize = m_currentBlockSizePoint;
   }
   
   // Reconstruct trend: if newest close > previous close, trend is UP.
   if(last.close > prev.close) m_isTrendUp = true;
   else if(last.close < prev.close) m_isTrendUp = false;
   else m_isTrendUp = (last.close >= last.open);

   m_liveCandidateActive = false;
}


#endif // __MULTIBOTPRO_RENKO_MQH__

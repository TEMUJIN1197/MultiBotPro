#ifndef __MULTIBOTPRO_MASTERRUNTIME_MQH__
#define __MULTIBOTPRO_MASTERRUNTIME_MQH__

//+------------------------------------------------------------------+
//|                                   MultiBotPro_MasterRuntime.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//+------------------------------------------------------------------+

#include "MultiBotPro_Defines.mqh"
#include "MultiBotPro_ChartFactory.mqh"

// --- GLOBALS ---
static datetime G_MasterLastCheckTime = 0;
static double   G_MasterDayStartEquity = 0.0;
static int      G_MasterCurrentDayOfYear = -1;
static bool     G_MasterDailyStopHit = false;
static bool     G_MasterTotalStopHit = false;
static ulong    G_MasterStopTradingUntil = 0;
static long     G_MasterHostChartID = 0;
static ulong    G_MasterHostVisibilityHealUntil = 0;

// Shadow master pulse tracking
static bool    G_ShadowMasterActive = false;
static string  G_ShadowMasterStatus = "";

bool MBP_IsSyntheticChartMode(ENUM_MBP_CHART_MODE mode)
{
   return (mode == MBP_CHART_RENKO ||
           mode == MBP_CHART_HEIKEN_RENKO ||
           mode == MBP_CHART_HEIKEN_ASHI ||
           mode == MBP_CHART_CUSTOM_TIME);
}

string MBP_ResolveDataModeSuffix(const ENUM_MBP_DATA_MODE mode)
{
   switch(mode)
   {
      case MBP_DATA_RENKO:         return InpRenkoSuffix;
      case MBP_DATA_MEDIAN_RENKO:  return InpMedianRenkoSuffix;
      case MBP_DATA_TURBO_RENKO:   return InpTurboRenkoSuffix;
      case MBP_DATA_HYBRID_RENKO:  return InpHybridRenkoSuffix;
      case MBP_DATA_HEIKEN_RENKO:  return InpHeikenRenkoSuffix;
      case MBP_DATA_HEIKEN_ASHI:   return InpHeikenAshiSuffix;
      case MBP_DATA_CUSTOM_TIME:   return InpCustomTimeSuffix;
      default:                     return "";
   }
}

string ResolveSyntheticChartSymbolName(string baseSymbol, ENUM_MBP_DATA_MODE mode)
{
   string suffix = MBP_ResolveDataModeSuffix(mode);
   if(suffix != "" && StringSubstr(suffix, 0, 1) != "_" && StringSubstr(suffix, 0, 1) != ".")
      suffix = "_" + suffix;

   return (suffix == "") ? (baseSymbol + "_Custom") : (baseSymbol + suffix);
}

bool MBP_InitFactoryForDataMode(CChartFactory &factory, const string baseSym, const ENUM_MBP_DATA_MODE dataMode)
{
   ENUM_MBP_CHART_MODE chartMode = MBP_DataModeToChartMode(dataMode);
   if(!MBP_IsSyntheticChartMode(chartMode))
      return false;

   ENUM_MBP_RENKO_FAMILY renkoFamily = MBP_DataModeToRenkoFamily(dataMode);
   double openOffsetPct = MathAbs(InpRenkoOpenOffsetPct) / 100.0;
   double reversalShadowPct = MathMax(0.01, MathAbs(InpRenkoReversalShadowPct) / 100.0);
   double reversalPct = MathMax(1.0, MathAbs(InpRenkoReversalPct) / 100.0);

   switch(dataMode)
   {
      case MBP_DATA_RENKO:
         renkoFamily = MBP_RENKO_CLASSIC;
         openOffsetPct = 0.0;
         reversalShadowPct = 1.0;
         reversalPct = 2.0;
         break;
      case MBP_DATA_MEDIAN_RENKO:
         renkoFamily = MBP_RENKO_MEDIAN;
         if(openOffsetPct <= 0.0) openOffsetPct = 0.50;
         if(reversalShadowPct <= 0.01) reversalShadowPct = 0.50;
         if(reversalPct <= 1.0) reversalPct = 1.50;
         break;
      case MBP_DATA_TURBO_RENKO:
         renkoFamily = MBP_RENKO_TURBO;
         openOffsetPct = 0.75;
         reversalShadowPct = 0.75;
         reversalPct = 1.50;
         break;
      case MBP_DATA_HYBRID_RENKO:
         renkoFamily = MBP_RENKO_HYBRID;
         openOffsetPct = 0.75;
         reversalShadowPct = 0.50;
         reversalPct = 1.50;
         break;
      default:
         break;
   }

   switch(chartMode)
   {
      case MBP_CHART_RENKO:
         factory.Init(baseSym, chartMode, MBP_ResolveDataModeSuffix(dataMode),
                      InpRenkoBlockMode, InpRenkoBlockValue,
                      InpRenkoATRTimeframe, InpRenkoATRPeriod, InpRenkoShowWicks,
                      InpRenkoAdaptiveATR, InpRenkoATRRefreshMs, InpRenkoStartMode,
                      InpRenkoHistType, InpRenkoHistoryDays, InpRenkoFixedDate,
                      InpRenkoForceRebuild, renkoFamily, openOffsetPct,
                      reversalShadowPct, reversalPct, InpRenkoApplyOffsetToFirstBar,
                      InpRenkoOffsetDigits, InpRenkoResetOpenOnNewDay,
                      InpRenkoLiveStyle, InpRenkoLivePoolMs);
         return true;
      case MBP_CHART_HEIKEN_RENKO:
         factory.Init(baseSym, chartMode, MBP_ResolveDataModeSuffix(dataMode),
                      BLOCK_MODE_POINTS, InpHeikenRenkoPoints,
                      PERIOD_D1, 14, false, true, 250, MODE_DAYS_BACK,
                      DATA_M1, InpHeikenRenkoHistoryDays, 0, false);
         return true;
      case MBP_CHART_HEIKEN_ASHI:
         factory.Init(baseSym, chartMode, MBP_ResolveDataModeSuffix(dataMode),
                      BLOCK_MODE_POINTS, 0,
                      PERIOD_D1, 14, false, true, 250, MODE_DAYS_BACK,
                      DATA_M1, InpHeikenAshiHistoryDays, 0, false);
         return true;
      case MBP_CHART_CUSTOM_TIME:
         factory.Init(baseSym, chartMode, MBP_ResolveDataModeSuffix(dataMode),
                      BLOCK_MODE_POINTS, InpCustomTimeSeconds,
                      PERIOD_D1, 14, false, true, 250, MODE_DAYS_BACK,
                      DATA_M1, InpCustomTimeHistoryDays, 0, false);
         return true;
      default:
         return false;
   }
}

CChartFactory *GetStartupFactoryForMode(const int symbolIndex, const ENUM_MBP_DATA_MODE requestedMode)
{
   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return NULL;
   if(CheckPointer(SymbolData[symbolIndex].ChartFactories) == POINTER_INVALID)
      return NULL;

   for(int i = 0; i < SymbolData[symbolIndex].ChartFactories.Total(); i++)
   {
      CChartFactory *factory = (CChartFactory*)SymbolData[symbolIndex].ChartFactories.At(i);
      if(CheckPointer(factory) == POINTER_INVALID)
         continue;
      if(factory.GetChartType() != MBP_DataModeToChartMode(requestedMode))
         continue;
      if(factory.GetChartType() == MBP_CHART_RENKO &&
         factory.GetRenkoFamily() != MBP_DataModeToRenkoFamily(requestedMode))
         continue;
      if(factory.GetChartType() == MBP_CHART_RENKO || factory.GetChartType() == MBP_DataModeToChartMode(requestedMode))
         return factory;
   }

   return NULL;
}

void MBP_DestroyChartFactoryArray(const int symbolIndex)
{
   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return;
   if(CheckPointer(SymbolData[symbolIndex].ChartFactories) == POINTER_INVALID)
      return;

   for(int j = 0; j < SymbolData[symbolIndex].ChartFactories.Total(); j++)
   {
      CChartFactory *factory = (CChartFactory*)SymbolData[symbolIndex].ChartFactories.At(j);
      if(CheckPointer(factory) != POINTER_INVALID)
         factory.Deinit();
   }

   delete SymbolData[symbolIndex].ChartFactories;
   SymbolData[symbolIndex].ChartFactories = NULL;
}

long MBP_FindChartBySymbol(const string sym)
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

bool MBP_BringChartToFront(const long chartID)
{
   if(chartID <= 0)
      return false;

   ChartSetInteger(chartID, CHART_BRING_TO_TOP, true);
   ChartRedraw(chartID);
   return true;
}

void ScheduleMasterHostVisibilityHeal(const uint durationMs = 5000)
{
   ulong deadline = (ulong)GetTickCount64() + (ulong)MathMax(500, (int)durationMs);
   if(deadline > G_MasterHostVisibilityHealUntil)
      G_MasterHostVisibilityHealUntil = deadline;
}

bool EnsureAssociatedChartVisibleForSymbol(const int symbolIndex,
                                           const ENUM_MBP_DATA_MODE requestedMode,
                                           string &outChartSymbol)
{
   outChartSymbol = "";

   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return false;

   int primaryIndex = symbolIndex;
   string focusBaseSymbol = GetBaseSymbol(SymbolData[symbolIndex].symbol);
   if(focusBaseSymbol != "")
   {
      int basePrimaryIndex = GetPrimarySymbolIndexByBase(focusBaseSymbol, true);
      if(basePrimaryIndex >= 0)
         primaryIndex = basePrimaryIndex;
   }

   string baseSym = GetManagedBaseSymbol(primaryIndex);
   if(baseSym == "")
      baseSym = GetBaseSymbol(SymbolData[primaryIndex].symbol);
   if(baseSym == "")
      baseSym = SymbolData[primaryIndex].symbol;

   if(MBP_IsSyntheticDataMode(requestedMode))
   {
      CChartFactory *factory = GetStartupFactoryForMode(primaryIndex, requestedMode);
      if(CheckPointer(factory) == POINTER_INVALID)
      {
         outChartSymbol = ResolveSyntheticChartSymbolName(baseSym, requestedMode);
         long existingChartID = MBP_FindChartBySymbol(outChartSymbol);
         if(existingChartID > 0)
         {
            ApplyChartStyles(existingChartID);
            ScheduleMasterHostVisibilityHeal();
            RestoreMasterHostChartFocus();
            return true;
         }

         Print("[MasterRuntime] WARNING: No startup factory found for ", baseSym, " in mode ", MBP_DataModeToText(requestedMode), ".");
         return false;
      }

      if(!factory.PrepareStartup(5, 8))
      {
         Print("[MasterRuntime] WARNING: Unable to prepare associated chart for ", factory.GetCustomSymbol(), ".");
         return false;
      }

      outChartSymbol = factory.GetCustomSymbol();
      long chartID = factory.GetChartID();
      if(chartID <= 0)
         chartID = MBP_FindChartBySymbol(outChartSymbol);
      if(chartID <= 0)
         return false;

      ApplyChartStyles(chartID);
      ChartRedraw(chartID);
      ScheduleMasterHostVisibilityHeal();
      RestoreMasterHostChartFocus();
      return true;
   }

   outChartSymbol = baseSym;
   if(!SymbolSelect(baseSym, true))
      return false;

   long chartID = MBP_FindChartBySymbol(baseSym);
   if(chartID <= 0)
   {
      ResetLastError();
      ENUM_TIMEFRAMES targetPeriod = (G_MasterHostChartID > 0) ? (ENUM_TIMEFRAMES)ChartPeriod(G_MasterHostChartID) : _Period;
      chartID = ChartOpen(baseSym, targetPeriod);
      if(chartID > 0)
         ApplyChartStyles(chartID);
   }

   if(chartID <= 0)
   {
      Print("[MasterRuntime] WARNING: Unable to open live chart window for ", baseSym, ".");
      return false;
   }

   ApplyChartStyles(chartID);
   ChartRedraw(chartID);
   ScheduleMasterHostVisibilityHeal();
   RestoreMasterHostChartFocus();
   return true;
}

void RestoreMasterHostChartFocus()
{
   if(G_MasterHostChartID <= 0)
      return;

   ChartSetInteger(G_MasterHostChartID, CHART_BRING_TO_TOP, true);
   ChartRedraw(G_MasterHostChartID);
}

void MaintainMasterHostChartVisibility()
{
   if(G_MasterHostChartID <= 0 || G_MasterHostVisibilityHealUntil == 0)
      return;

   RestoreMasterHostChartFocus();

   if(ShowDashboard)
   {
      if(IsDragging || G_DashboardDragArmed)
      {
         ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
      }
      else
      {
         bool missingCorePanel = (ObjectFind(0, "Dash_BG") < 0);
         if(missingCorePanel)
         {
            ResetDashboardHeartbeat();
            EnsureMasterDashboardReady(true);
         }
         else
         {
            ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
            UpdateDashboard(0);
            ChartRedraw(0);
         }
      }
   }

   if((ulong)GetTickCount64() >= G_MasterHostVisibilityHealUntil)
      G_MasterHostVisibilityHealUntil = 0;
}

void BatchOpenSyntheticChartWindows(const ENUM_MBP_DATA_MODE requestedMode)
{
   if(!MBP_IsSyntheticDataMode(requestedMode))
      return;
   if(IsParallelWorkerMode())
      return;

   bool openedVisibleChart = false;
   for(int i = 0; i < ArraySize(SymbolData); i++)
   {
      CChartFactory *factory = GetStartupFactoryForMode(i, requestedMode);
      if(CheckPointer(factory) == POINTER_INVALID)
         continue;

      string baseSym = GetManagedBaseSymbol(i);
      if(baseSym == "")
         baseSym = GetBaseSymbol(SymbolData[i].symbol);
      if(baseSym == "")
         baseSym = SymbolData[i].symbol;
      bool shouldOpenDedicatedChart = WorkerShouldOpenDedicatedSyntheticChart(baseSym);

      if(factory.EnsureStartupShell(1, shouldOpenDedicatedChart))
      {
         if(shouldOpenDedicatedChart)
         {
            openedVisibleChart = true;
            Print("[MasterRuntime] Startup chart shell ready for ", factory.GetCustomSymbol(), ".");
         }
         else
            Print("[MasterRuntime] Startup chart shell ready for ", factory.GetCustomSymbol(), " (headless worker assignment).");
      }
      else
         Print("[MasterRuntime] WARNING: Failed to prepare startup shell for ", factory.GetCustomSymbol(), ".");
   }

   if(openedVisibleChart)
   {
      ScheduleMasterHostVisibilityHeal(8000);
      RestoreMasterHostChartFocus();
   }
}

void BatchPrepareSyntheticCharts(const ENUM_MBP_DATA_MODE requestedMode)
{
   if(!MBP_IsSyntheticDataMode(requestedMode))
      return;

   bool openedVisibleChart = false;
   for(int i = 0; i < ArraySize(SymbolData); i++)
   {
      CChartFactory *factory = GetStartupFactoryForMode(i, requestedMode);
      if(CheckPointer(factory) == POINTER_INVALID)
         continue;

      string baseSym = GetManagedBaseSymbol(i);
      if(baseSym == "")
         baseSym = GetBaseSymbol(SymbolData[i].symbol);
      if(baseSym == "")
         baseSym = SymbolData[i].symbol;
      bool shouldOpenDedicatedChart = WorkerShouldOpenDedicatedSyntheticChart(baseSym);

      if(factory.PrepareStartup(1, 1, shouldOpenDedicatedChart))
      {
         if(shouldOpenDedicatedChart)
         {
            openedVisibleChart = true;
            Print("[MasterRuntime] Synthetic startup ready for ", factory.GetCustomSymbol(), ".");
         }
         else
            Print("[MasterRuntime] Synthetic startup ready for ", factory.GetCustomSymbol(), " (headless worker assignment).");
      }
      else
         Print("[MasterRuntime] WARNING: Synthetic startup exhausted retries for ", factory.GetCustomSymbol(), ".");
   }

   if(openedVisibleChart)
   {
      ScheduleMasterHostVisibilityHeal(8000);
      RestoreMasterHostChartFocus();
   }
}

bool WorkerShouldOpenDedicatedSyntheticChart(const string baseSymbol)
{
   if(!IsParallelWorkerMode())
      return true;

   return false;
}

bool PrepareSymbolStartupChart(int symbolIndex, ENUM_MBP_DATA_MODE requestedMode, string &analysisSymbol)
{
   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return false;

   string baseSym = GetManagedBaseSymbol(symbolIndex);
   if(baseSym == "")
      baseSym = GetBaseSymbol(SymbolData[symbolIndex].symbol);
   analysisSymbol = baseSym;
   if(!MBP_IsSyntheticDataMode(requestedMode))
      return true;

   if(IsParallelCoordinatorMode())
   {
      analysisSymbol = baseSym;
      return true;
   }

   analysisSymbol = ResolveSyntheticChartSymbolName(baseSym, requestedMode);
   bool shouldOpenDedicatedChart = WorkerShouldOpenDedicatedSyntheticChart(baseSym);

   CChartFactory *factory = GetStartupFactoryForMode(symbolIndex, requestedMode);
   if(CheckPointer(factory) != POINTER_INVALID)
   {
      if(factory.PrepareStartup(1, 1, shouldOpenDedicatedChart))
      {
         analysisSymbol = factory.GetCustomSymbol();
         if(SymbolSelect(analysisSymbol, true))
         {
            MqlTick startupTick;
            ZeroMemory(startupTick);
            bool hasStartupTick = SymbolInfoTick(baseSym, startupTick);
            if(hasStartupTick && startupTick.time_msc <= 0 && startupTick.time > 0)
               startupTick.time_msc = (long)startupTick.time * 1000;
            factory.ProcessTimer(startupTick, hasStartupTick);
            long startupTickMsc = hasStartupTick ? startupTick.time_msc : 0;
            SymbolData[symbolIndex].LastTickMsc = startupTickMsc;
            SymbolData[symbolIndex].LastProcessedSourceTickMsc = startupTickMsc;
            SymbolData[symbolIndex].LastProcessedSourceTickCountAtMsc = (startupTickMsc > 0) ? 1 : 0;
            if(shouldOpenDedicatedChart)
               Print("[MasterRuntime] Analysis symbol ready for ", baseSym, " -> ", analysisSymbol, ".");
            else
               Print("[MasterRuntime] Analysis symbol ready for ", baseSym, " -> ", analysisSymbol, " (headless worker assignment).");
            return true;
         }
         Print("[MasterRuntime] WARNING: Analysis symbol activation failed for ", analysisSymbol, ".");
      }
      else
         Print("[MasterRuntime] WARNING: Synthetic startup preparation failed for ", factory.GetCustomSymbol(), ".");
      return false;
   }

   if(!SymbolInfoInteger(analysisSymbol, SYMBOL_CUSTOM))
      return false;

   return SymbolSelect(analysisSymbol, true);
}

long MBP_NormalizeManagedTickMsc(MqlTick &tick)
{
   if(tick.time_msc <= 0 && tick.time > 0)
      tick.time_msc = (long)tick.time * 1000;
   return tick.time_msc;
}

int MBP_RuntimeTickBatchLimit()
{
   return MasterIsUiPriorityWindowActive() ? 16 : 96;
}

int MBP_ProcessSyntheticTickBatch(const int symbolIndex, const MqlTick &ticks[])
{
   if(IsParallelCoordinatorMode())
      return 0;

   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return 0;
   if(CheckPointer(SymbolData[symbolIndex].ChartFactories) == POINTER_INVALID)
      return 0;

   long initialCursorMsc = SymbolData[symbolIndex].LastProcessedSourceTickMsc;
   int initialCursorCount = MathMax(0, SymbolData[symbolIndex].LastProcessedSourceTickCountAtMsc);
   int skippedAtInitialCursor = 0;
   long finalCursorMsc = initialCursorMsc;
   int finalCursorCount = initialCursorCount;
   int firstProcessIndex = -1;
   int processed = 0;
   for(int i = 0; i < ArraySize(ticks); i++)
   {
      MqlTick tick = ticks[i];
      long tickMsc = MBP_NormalizeManagedTickMsc(tick);
      if(tickMsc <= 0)
         continue;
      if(initialCursorMsc > 0)
      {
         if(tickMsc < initialCursorMsc)
            continue;
         if(tickMsc == initialCursorMsc && skippedAtInitialCursor < initialCursorCount)
         {
            skippedAtInitialCursor++;
            continue;
         }
      }
      if(firstProcessIndex < 0)
         firstProcessIndex = i;

      if(finalCursorMsc == tickMsc)
         finalCursorCount++;
      else
      {
         finalCursorMsc = tickMsc;
         finalCursorCount = 1;
      }

      processed++;
   }

   if(processed <= 0 || firstProcessIndex < 0)
      return 0;

   for(int j = 0; j < SymbolData[symbolIndex].ChartFactories.Total(); j++)
   {
      CChartFactory *factory = (CChartFactory*)SymbolData[symbolIndex].ChartFactories.At(j);
      if(CheckPointer(factory) != POINTER_INVALID)
         factory.ProcessTickBatch(ticks, firstProcessIndex, processed);
   }

   SymbolData[symbolIndex].LastProcessedSourceTickMsc = finalCursorMsc;
   SymbolData[symbolIndex].LastProcessedSourceTickCountAtMsc = finalCursorCount;
   SymbolData[symbolIndex].LastTickMsc = finalCursorMsc;

   return processed;
}

void MasterServiceSyntheticSymbol(const int symbolIndex, const bool withHeartbeat)
{
   if(IsParallelCoordinatorMode())
      return;

   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return;
   if(!SymbolData[symbolIndex].active)
      return;
   if(CheckPointer(SymbolData[symbolIndex].ChartFactories) == POINTER_INVALID)
      return;

   string baseSym = GetManagedBaseSymbol(symbolIndex);
   if(baseSym == "")
      baseSym = GetBaseSymbol(SymbolData[symbolIndex].symbol);
   if(baseSym == "")
      return;

   MqlTick heartbeatTick;
   ZeroMemory(heartbeatTick);
   bool hasLiveTick = SymbolInfoTick(baseSym, heartbeatTick);
   long latestTickMsc = hasLiveTick ? MBP_NormalizeManagedTickMsc(heartbeatTick) : 0;

   if(SymbolData[symbolIndex].LastProcessedSourceTickMsc <= 0 && latestTickMsc > 0)
   {
      SymbolData[symbolIndex].LastProcessedSourceTickMsc = latestTickMsc;
      SymbolData[symbolIndex].LastProcessedSourceTickCountAtMsc = 0;
   }

   bool processedNewTicks = false;
   if(latestTickMsc >= SymbolData[symbolIndex].LastProcessedSourceTickMsc && latestTickMsc > 0)
   {
      int copyLimit = MBP_RuntimeTickBatchLimit() + MathMax(4, SymbolData[symbolIndex].LastProcessedSourceTickCountAtMsc);
      int maxPasses = MasterIsUiPriorityWindowActive() ? 1 : 2;
      for(int pass = 0; pass < maxPasses; pass++)
      {
         MqlTick sourceTicks[];
         int copied = CopyTicks(baseSym, sourceTicks, COPY_TICKS_ALL,
                                (ulong)MathMax(0, SymbolData[symbolIndex].LastProcessedSourceTickMsc),
                                copyLimit);
         if(copied <= 0)
            break;

         int processedCount = MBP_ProcessSyntheticTickBatch(symbolIndex, sourceTicks);
         if(processedCount <= 0)
            break;

         processedNewTicks = true;
         heartbeatTick = sourceTicks[MathMin(ArraySize(sourceTicks) - 1,
                            MathMax(0, copied - 1))];
         MBP_NormalizeManagedTickMsc(heartbeatTick);
         hasLiveTick = true;

         long processedCursorMsc = SymbolData[symbolIndex].LastProcessedSourceTickMsc;
         if(processedCursorMsc >= latestTickMsc && processedCount < copied)
            break;
         if(copied < copyLimit)
            break;

         MqlTick newestTick = sourceTicks[ArraySize(sourceTicks) - 1];
         long newestTickMsc = MBP_NormalizeManagedTickMsc(newestTick);
         if(newestTickMsc >= latestTickMsc)
            break;
      }
   }

   if(!withHeartbeat && !processedNewTicks)
      return;

   for(int j = 0; j < SymbolData[symbolIndex].ChartFactories.Total(); j++)
   {
      CChartFactory *factory = (CChartFactory*)SymbolData[symbolIndex].ChartFactories.At(j);
      if(CheckPointer(factory) == POINTER_INVALID)
         continue;

      if(withHeartbeat)
         factory.ProcessTimer(heartbeatTick, hasLiveTick);
   }
}

//+------------------------------------------------------------------+
//| STUB: Mark the shadow master sync pulse (for overlay display)    |
//+------------------------------------------------------------------+
void MarkShadowMasterPulse(bool isActive, string status)
{
   G_ShadowMasterActive = isActive;
   G_ShadowMasterStatus = status;
}

//+------------------------------------------------------------------+
//| LEGACY COMPATIBILITY: Shutdown analyzed engine                   |
//+------------------------------------------------------------------+
void ShutdownMasterAnalysisEngine()
{
   ShutdownMasterRuntime();
   G_MasterDailyStopHit = false;
   G_MasterTotalStopHit = false;
   G_ShadowMasterActive = false;
}

//+------------------------------------------------------------------+
//| Pump background runtime services (heartbeat, state sync)         |
//+------------------------------------------------------------------+
void MasterPumpRuntimeServices()
{
   if(IsParallelCoordinatorMode())
      return;

   int total = ArraySize(SymbolData);
   if(total <= 0)
      return;

   int budget = MasterIsUiPriorityWindowActive() ? 1 : MathMin(4, total);
   for(int step = 0; step < budget; step++)
   {
      int index = (G_RuntimePumpCursor + step) % total;
      MasterServiceSyntheticSymbol(index, false);
   }
   G_RuntimePumpCursor = (G_RuntimePumpCursor + budget) % total;
}

//+------------------------------------------------------------------+
//| Pump background timer services (Adaptive ATR, visuals)           |
//+------------------------------------------------------------------+
void MasterPumpTimerServices()
{
   if(IsParallelCoordinatorMode())
   {
      MaintainMasterHostChartVisibility();
      return;
   }

   int total = ArraySize(SymbolData);
   if(total > 0)
   {
      int budget = MasterIsUiPriorityWindowActive() ? 1 : MathMin(2, total);
      for(int step = 0; step < budget; step++)
      {
         int index = (G_TimerPumpCursor + step) % total;
         MasterServiceSyntheticSymbol(index, true);
      }
      G_TimerPumpCursor = (G_TimerPumpCursor + budget) % total;
   }

   MaintainMasterHostChartVisibility();
}

//+------------------------------------------------------------------+
//| Orchestrate Visual Drawing across all active factories           |
//+------------------------------------------------------------------+
void Master_DrawVisuals(long magic)
{
   for(int i = 0; i < ArraySize(SymbolData); i++)
   {
      if(!SymbolData[i].active) continue;
      if(CheckPointer(SymbolData[i].ChartFactories) != POINTER_INVALID)
      {
         for(int j=0; j<SymbolData[i].ChartFactories.Total(); j++)
         {
            CChartFactory *factory = (CChartFactory*)SymbolData[i].ChartFactories.At(j);
            if(CheckPointer(factory) != POINTER_INVALID)
               factory.DrawVisuals(magic);
         }
      }
   }
}

void Master_RefreshChartVisualPackages(const bool allowFullRedraw)
{
   for(int i = 0; i < ArraySize(SymbolData); i++)
   {
      if(!SymbolData[i].active) continue;
      if(CheckPointer(SymbolData[i].ChartFactories) == POINTER_INVALID)
         continue;

      for(int j = 0; j < SymbolData[i].ChartFactories.Total(); j++)
      {
         CChartFactory *factory = (CChartFactory*)SymbolData[i].ChartFactories.At(j);
         if(CheckPointer(factory) != POINTER_INVALID)
            factory.RefreshNativeVisuals(allowFullRedraw);
      }
   }
}

//+------------------------------------------------------------------+
//| STUB: Strategy tester multi-chart management                     |
//+------------------------------------------------------------------+
void MasterHandleTesterCharts()
{
   // In live mode, do nothing.
}

//+------------------------------------------------------------------+
//| Get the analysis/synthetic symbol for a given symbol index       |
//+------------------------------------------------------------------+
string GetAnalysisSymbolByIndex(int symbolIndex)
{
   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return _Symbol;
   return SymbolData[symbolIndex].symbol;
}

//+------------------------------------------------------------------+
//| Prepare the current tick data for a symbol                       |
//+------------------------------------------------------------------+
bool MasterPrepareSymbolTick(int symbolIndex, MqlTick &outTick, bool &outHasNewTick)
{
   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return false;

   string sym = SymbolData[symbolIndex].symbol;
   string execSym = GetManagedBaseSymbol(symbolIndex);
   if(execSym != "")
      sym = execSym;
   if(!SymbolInfoTick(sym, outTick))
      return false;

   long currentMs = MBP_NormalizeManagedTickMsc(outTick);
   outHasNewTick = (currentMs != SymbolData[symbolIndex].LastTickMsc);
   if(outHasNewTick)
      SymbolData[symbolIndex].LastTickMsc = currentMs;

   return true;
}

//+------------------------------------------------------------------+
//| Core Master initializer                                          |
//+------------------------------------------------------------------+
void ShutdownMasterRuntime()
{
   Print("🧠 Shutting down Master Runtime...");
   for(int i = 0; i < ArraySize(SymbolData); i++)
   {
      MBP_DestroyChartFactoryArray(i);
   }
}   

int Master_OnInit_Runtime()
{
   Print(EmojiBrain(), " Initializing Master Runtime...");
   G_MasterHostChartID = ChartID();
   ScheduleMasterHostVisibilityHeal(10000);
   
   Bundle_SetupEnvironment();
   
   G_MasterDayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   MqlDateTime dt;
   TimeCurrent(dt);
   G_MasterCurrentDayOfYear = dt.day_of_year;
   
   if(GlobalVariableCheck(InpHedgeChannel + "_COOLDOWN_TIMER"))
      G_MasterStopTradingUntil = (ulong)GlobalVariableGet(InpHedgeChannel + "_COOLDOWN_TIMER");

   for(int i = 0; i < ArraySize(SymbolData); i++)
   {
      MBP_DestroyChartFactoryArray(i);
      SymbolData[i].ChartFactories = new CArrayObj();
      SymbolData[i].ChartFactories.FreeMode(true);
      SymbolData[i].LastTickMsc = 0;
      SymbolData[i].LastProcessedSourceTickMsc = 0;
      SymbolData[i].LastProcessedSourceTickCountAtMsc = 0;

      string baseSym = SymbolData[i].BaseSymbol;
      if(baseSym == "")
         baseSym = GetManagedBaseSymbol(i);
      if(baseSym == "")
         baseSym = GetBaseSymbol(SymbolData[i].symbol);
      if(baseSym == "")
         baseSym = SymbolData[i].symbol;
      ENUM_MBP_DATA_MODE activeDataMode = SymbolData[i].DataMode;
      bool prepareOnlyActiveMode = MBP_IsSyntheticDataMode(activeDataMode);

      if(!IsParallelCoordinatorMode() && prepareOnlyActiveMode)
      {
         CChartFactory *f = new CChartFactory();
         if(MBP_InitFactoryForDataMode(f, baseSym, activeDataMode))
         {
            SymbolData[i].ChartFactories.Add(f);
            Print("[MasterRuntime] Startup factory created for ", baseSym, " in mode ", MBP_DataModeToText(activeDataMode), ".");
         }
         else
         {
            Print("[MasterRuntime] WARNING: Failed to create startup factory for ", baseSym, " in mode ", MBP_DataModeToText(activeDataMode), ".");
            delete f;
         }
      }
      else
      {
         // LIVE mode analyzes the base symbol directly.
      }
   }

   if(MBP_IsSyntheticDataMode(InpDataMode) && !IsParallelCoordinatorMode())
   {
      BatchOpenSyntheticChartWindows(InpDataMode);
      BatchPrepareSyntheticCharts(InpDataMode);
   }

   return INIT_SUCCEEDED;
}

#endif // __MULTIBOTPRO_MASTERRUNTIME_MQH__

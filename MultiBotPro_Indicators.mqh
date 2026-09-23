#ifndef __MULTIBOTPRO_INDICATORS_MQH__
#define __MULTIBOTPRO_INDICATORS_MQH__
//+------------------------------------------------------------------+
//|                                       MultiBotPro_Indicators.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://discord.com/channels/929723953415589918/929723953415589920"
int GetDefaultMAPeriod(const int maSlot)
  {
   switch(maSlot)
     {
      case 0:
         return (G_MA1_Period > 0) ? G_MA1_Period : ((MA1_Period > 0) ? MA1_Period : 14);
      case 1:
         return (G_MA2_Period > 0) ? G_MA2_Period : ((MA2_Period > 0) ? MA2_Period : 21);
      case 2:
         return (MA3_Period > 0) ? MA3_Period : 50;
      case 3:
         return (MA4_Period > 0) ? MA4_Period : 100;
      case 4:
         return (MA5_Period > 0) ? MA5_Period : 200;
     }
   return 14;
  }

int GetActiveMAPeriod(const int symbolIndex, const int maSlot)
  {
   int fallback = GetDefaultMAPeriod(maSlot);
   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return fallback;
   if(!InpEnableShadowMaster)
      return fallback;

   switch(maSlot)
     {
      case 0:
         return (SymbolData[symbolIndex].Dyn_MA1_Period > 0) ? SymbolData[symbolIndex].Dyn_MA1_Period : fallback;
      case 1:
         return (SymbolData[symbolIndex].Dyn_MA2_Period > 0) ? SymbolData[symbolIndex].Dyn_MA2_Period : fallback;
     }

   return fallback;
  }

bool NeedVWAP1Runtime()
  {
   return (UseVWAP1 && (UseVWAP || (InpShowIndicatorOverlay && InpShowVWAP1Overlay)));
  }

bool NeedVWAP3Runtime()
  {
   return (UseVWAP3 && (UseVWAP || (InpShowIndicatorOverlay && InpShowVWAP3Overlay)));
  }

bool NeedVWAP2Runtime()
  {
   return (UseVWAP2 &&
           (UseVWAP || (InpShowIndicatorOverlay &&
                        (InpShowVWAPHighOverlay || InpShowVWAPLowOverlay || InpShowVWAPCloud))));
  }

bool ShouldUpdateVWAPRuntime()
  {
   return (NeedVWAP1Runtime() || NeedVWAP3Runtime() || NeedVWAP2Runtime());
  }

bool ShouldRenderBoxObjectsForIndex(const int symbolIndex)
  {
   if(!ShowBoxLines)
      return false;

   int chartIndex = ResolveDashboardHostFocusSymbolIndex(_Symbol);
   if(chartIndex < 0)
      return (symbolIndex >= 0 && symbolIndex < ArraySize(SymbolData) &&
              GetManagedAnalysisSymbol(symbolIndex) == _Symbol);

   return (chartIndex == symbolIndex);
  }

void DeleteBoxObjectsForChart(const long chartID)
{
   ObjectsDeleteAll(chartID, "BoxSeg_", -1, -1);
   ObjectsDeleteAll(chartID, "BoxVert_", -1, -1);
   ObjectDelete(chartID, "BoxLine_H_Live");
   ObjectDelete(chartID, "BoxLine_L_Live");
}

void SyncSharedSymbolRuntimeToBasketClones(const int sourceIndex)
  {
   if(!InpEnableMultiBaskets)
      return;

   if(sourceIndex < 0 || sourceIndex >= ArraySize(SymbolData))
      return;

   if(!SymbolData[sourceIndex].IsPrimaryBasket)
      return;

   string symbol = SymbolData[sourceIndex].symbol;
   for(int i = 0; i < ArraySize(SymbolData); i++)
     {
      if(i == sourceIndex)
         continue;
      if(!SymbolData[i].active)
         continue;
      if(SymbolData[i].IsPrimaryBasket)
         continue;
      if(SymbolData[i].symbol != symbol)
         continue;

      SymbolData[i].VWAP1 = SymbolData[sourceIndex].VWAP1;
      SymbolData[i].VWAP2_High = SymbolData[sourceIndex].VWAP2_High;
      SymbolData[i].VWAP2_Low = SymbolData[sourceIndex].VWAP2_Low;
      SymbolData[i].VWAP3 = SymbolData[sourceIndex].VWAP3;
      SymbolData[i].LastVWAPUpdate = SymbolData[sourceIndex].LastVWAPUpdate;
      SymbolData[i].NewVWAPHighLowSet = SymbolData[sourceIndex].NewVWAPHighLowSet;
      SymbolData[i].BoxHighCount = SymbolData[sourceIndex].BoxHighCount;
      SymbolData[i].BoxLowCount = SymbolData[sourceIndex].BoxLowCount;

      for(int j = 0; j < 100; j++)
        {
         SymbolData[i].BoxHigh[j] = SymbolData[sourceIndex].BoxHigh[j];
         SymbolData[i].BoxLow[j] = SymbolData[sourceIndex].BoxLow[j];
        }
     }
  }

string GetBoxHistoryCacheFileName()
  {
   return StringFormat("MBP_BoxCache_%d_%s_%I64d.bin", MagicNumber, InpHedgeChannel, ChartID());
  }

bool SaveBoxHistoryCache()
  {
   int handle = FileOpen(GetBoxHistoryCacheFileName(), FILE_WRITE|FILE_BIN);
   if(handle == INVALID_HANDLE)
      return false;

   int symbolCount = ArraySize(SymbolData);
   FileWriteInteger(handle, symbolCount, INT_VALUE);
   for(int i = 0; i < symbolCount; i++)
     {
      string symbol = SymbolData[i].symbol;
      int nameLen = StringLen(symbol);
      FileWriteInteger(handle, nameLen, INT_VALUE);
      if(nameLen > 0)
         FileWriteString(handle, symbol, nameLen);

      FileWriteInteger(handle, SymbolData[i].BoxHighCount, INT_VALUE);
      for(int j = 0; j < 100; j++)
         FileWriteDouble(handle, SymbolData[i].BoxHigh[j]);

      FileWriteInteger(handle, SymbolData[i].BoxLowCount, INT_VALUE);
      for(int j = 0; j < 100; j++)
         FileWriteDouble(handle, SymbolData[i].BoxLow[j]);
     }

   FileClose(handle);
   return true;
  }

bool LoadBoxHistoryCacheForSymbol(const string symbol, const int symbolIndex)
  {
   string fileName = GetBoxHistoryCacheFileName();
   if(!FileIsExist(fileName))
      return false;

   int handle = FileOpen(fileName, FILE_READ|FILE_BIN);
   if(handle == INVALID_HANDLE)
      return false;

   bool found = false;
   int recordCount = FileReadInteger(handle, INT_VALUE);
   for(int i = 0; i < recordCount && !FileIsEnding(handle); i++)
     {
      int nameLen = FileReadInteger(handle, INT_VALUE);
      string cachedSymbol = "";
      if(nameLen > 0)
         cachedSymbol = FileReadString(handle, nameLen);

      int highCount = FileReadInteger(handle, INT_VALUE);
      double cachedHigh[100];
      ArrayInitialize(cachedHigh, 0.0);
      for(int j = 0; j < 100 && !FileIsEnding(handle); j++)
         cachedHigh[j] = FileReadDouble(handle);

      int lowCount = FileReadInteger(handle, INT_VALUE);
      double cachedLow[100];
      ArrayInitialize(cachedLow, 0.0);
      for(int j = 0; j < 100 && !FileIsEnding(handle); j++)
         cachedLow[j] = FileReadDouble(handle);

      if(cachedSymbol == symbol)
        {
         SymbolData[symbolIndex].BoxHighCount = MathMax(0, MathMin(highCount, 100));
         SymbolData[symbolIndex].BoxLowCount = MathMax(0, MathMin(lowCount, 100));
         for(int j = 0; j < 100; j++)
           {
            SymbolData[symbolIndex].BoxHigh[j] = cachedHigh[j];
            SymbolData[symbolIndex].BoxLow[j] = cachedLow[j];
           }
         found = true;
         break;
        }
     }

   FileClose(handle);
   return found;
  }

void BackfillBoxHistory(int symbolIndex);

void QueueBoxHistoryWarmup(const int symbolIndex, const ulong delayMs = 0)
  {
   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return;

   if(!SymbolData[symbolIndex].BoxHistoryWarmupQueued || SymbolData[symbolIndex].BoxHistoryWarmupDone)
     {
      SymbolData[symbolIndex].BoxHistoryWarmupInProgress = false;
      SymbolData[symbolIndex].BoxHistoryWarmupCursor = 0;
      SymbolData[symbolIndex].BoxHistoryWarmupBarsToCheck = 0;
      SymbolData[symbolIndex].BoxHistoryWarmupPrevHigh = 0.0;
      SymbolData[symbolIndex].BoxHistoryWarmupPrevLow = 0.0;
      SymbolData[symbolIndex].BoxHistoryWarmupLastTotalBars = 0;
     }

   SymbolData[symbolIndex].BoxHistoryWarmupQueued = true;
   SymbolData[symbolIndex].BoxHistoryWarmupDone = false;
   SymbolData[symbolIndex].BoxHistoryWarmupNextAttemptMs = GetTickCount() + delayMs;
  }

void ProcessDeferredBoxHistoryWarmup()
  {
   static int nextSymbolIndex = 0;
   int totalSymbols = ArraySize(SymbolData);
   if(totalSymbols <= 0)
      return;

   ulong nowMs = GetTickCount();
   for(int offset = 0; offset < totalSymbols; offset++)
     {
      int symbolIndex = (nextSymbolIndex + offset) % totalSymbols;
      if(symbolIndex < 0 || symbolIndex >= totalSymbols)
         continue;
      if(!SymbolData[symbolIndex].active)
         continue;
      if(SymbolData[symbolIndex].BoxHistoryWarmupDone || !SymbolData[symbolIndex].BoxHistoryWarmupQueued)
         continue;
      if(nowMs < SymbolData[symbolIndex].BoxHistoryWarmupNextAttemptMs)
         continue;

      BackfillBoxHistory(symbolIndex);
      nextSymbolIndex = (symbolIndex + 1) % totalSymbols;
      break;
     }
  }

//+------------------------------------------------------------------+
//| Initialize symbol data (FIXED: Force Data Load & Valid Handles)  |
//+------------------------------------------------------------------+
bool InitializeSymbolData(string symbol, int index, ENUM_MBP_DATA_MODE globalMode)
  {
   string baseSymbol = GetBaseSymbol(symbol);

// 1. Force Symbol Selection to trigger data download
   if(!SymbolSelect(baseSymbol, true))
     {
      if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print("Error: Failed to select symbol ", baseSymbol, ". Removed from list.");
      return false;
     }

   SymbolData[index].active = true;
   SymbolData[index].BasketId = 1;
   SymbolData[index].IsPrimaryBasket = true;
   SymbolData[index].BasketActive = false;
   SymbolData[index].BasketInitialEntry = 0.0;
   SymbolData[index].BasketDirection = POSITION_TYPE_BUY;
   SymbolData[index].BaseSymbol = baseSymbol;
   SymbolData[index].AnalysisSymbol = baseSymbol;
   SymbolData[index].RenkoFamily = MBP_DataModeToRenkoFamily(globalMode);
   for(int i = 0; i < 5; i++)
      for(int tf = 0; tf < 7; tf++)
         SymbolData[index].MA_Handles[i][tf] = INVALID_HANDLE;
   SymbolData[index].ATR_Handle = INVALID_HANDLE;
   SymbolData[index].ADX_Handle = INVALID_HANDLE;
   SymbolData[index].MA_SL_Handle = INVALID_HANDLE;
   
   // ==========================================================
   // --- PRE-LOAD SHADOW MASTER CONFIG ---
   // Pull AI variables immediately so indicators don't fail with 4002
   // ==========================================================
   SymbolData[index].symbol = baseSymbol; // Temp assignment for ShadowConfig lookup (uses base symbol)
   LoadShadowConfig(index);
   
   // --- LOGIC: SET DATA MODE ---
   SymbolData[index].DataMode = globalMode;
   if(false)
   {
      int phantomCount = 0;
      for(int i=1; i<=10; i++) {
         if(iTickVolume(baseSymbol, PERIOD_CURRENT, i) == 0) phantomCount++;
      }
      
      if(phantomCount > 0) {
         SymbolData[index].DataMode = MBP_DATA_MEDIAN_RENKO;
         if(!G_FastChartSwitchMode)
            if(MBP_LogTierEnabled(MBP_LOG_TIER_DEBUG)) Print("🧠 ", symbol, " auto-detected Median/Turbo Renko (phantom bars found). Filter enabled.");
      } else {
         SymbolData[index].DataMode = MBP_DATA_LIVE;
         if(!G_FastChartSwitchMode)
            if(MBP_LogTierEnabled(MBP_LOG_TIER_DEBUG)) Print("🧠 ", symbol, " auto-detected Standard/Renko_Large (no phantom bars).");
      }
   }
    else
    {
    }
    
    string analysisSymbol = baseSymbol;
    bool usesSyntheticChart = MBP_IsSyntheticDataMode(SymbolData[index].DataMode);
    bool lightweightCoordinator = IsParallelCoordinatorMode();
    if(usesSyntheticChart && !lightweightCoordinator)
    {
       if(!PrepareSymbolStartupChart(index, SymbolData[index].DataMode, analysisSymbol))
       {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print("Warning: Synthetic chart startup failed for ", baseSymbol,
               " in mode ", MBP_DataModeToText(SymbolData[index].DataMode),
               ". Skipping symbol.");
         SymbolData[index].active = false;
         SymbolData[index].AnalysisSymbol = baseSymbol;
         SymbolData[index].symbol = baseSymbol;
         return false;
      }
    }
    SymbolData[index].AnalysisSymbol = analysisSymbol;
    SymbolData[index].symbol = analysisSymbol; // Final assignment for Analysis tracking

// 2. Initialize MA handles for each timeframe
    for(int tf = 0; tf < 7; tf++)
      {
       if(!lightweightCoordinator && TimeframeEnabled[tf])
         {
         // Safely resolve the active periods (Use AI if valid, else use Inputs, else hard-fallback to 14/21)
         int activeMA1 = GetActiveMAPeriod(index, 0);
         int activeMA2 = GetActiveMAPeriod(index, 1);
         int activeMA3 = GetActiveMAPeriod(index, 2);
         int activeMA4 = GetActiveMAPeriod(index, 3);
         int activeMA5 = GetActiveMAPeriod(index, 4);

         // Create Handles using the analysisSymbol
         SymbolData[index].MA_Handles[0][tf] = iMA(analysisSymbol, Timeframes[tf], activeMA1, 0, GetMAMethod(MA1_Method), GetMASource(MA1_Source));
         SymbolData[index].MA_Handles[1][tf] = iMA(analysisSymbol, Timeframes[tf], activeMA2, 0, GetMAMethod(MA2_Method), GetMASource(MA2_Source));
         SymbolData[index].MA_Handles[2][tf] = iMA(analysisSymbol, Timeframes[tf], activeMA3, 0, GetMAMethod(MA3_Method), GetMASource(MA3_Source));
         SymbolData[index].MA_Handles[3][tf] = iMA(analysisSymbol, Timeframes[tf], activeMA4, 0, GetMAMethod(MA4_Method), GetMASource(MA4_Source));
         SymbolData[index].MA_Handles[4][tf] = iMA(analysisSymbol, Timeframes[tf], activeMA5, 0, GetMAMethod(MA4_Method), GetMASource(MA4_Source));
         
         // Check for INVALID_HANDLE (Critical Fix)
         for(int k=0; k<5; k++)
           {
            if(SymbolData[index].MA_Handles[k][tf] == INVALID_HANDLE)
              {
               if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print("Warning: Failed to create MA handle for ", analysisSymbol, " TF index ", tf);
              }
           }
        }
      else
        {
         for(int i = 0; i < 5; i++)
            SymbolData[index].MA_Handles[i][tf] = INVALID_HANDLE;
        }
     }

   // Initialize ATR handle
    if(!lightweightCoordinator)
    {
       ENUM_TIMEFRAMES atrTF = ATR_Timeframe;
       if(atrTF == PERIOD_CURRENT && baseSymbol != _Symbol)
       {
          if(Period() > PERIOD_MN1 || (int)Period() == 2 || (int)Period() == 3 || (int)Period() == 4 || (int)Period() == 6)
          {
             if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print("Warning: ATR_Timeframe=CURRENT is invalid for secondary symbol ", baseSymbol, " on this custom chart. Falling back to M1.");
             atrTF = PERIOD_M1; 
          }
       }
    
       SymbolData[index].ATR_Handle = iATR(analysisSymbol, atrTF, ATR_Period);
       if(SymbolData[index].ATR_Handle == INVALID_HANDLE)
          if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print("Error: Failed to create ATR Handle for ", analysisSymbol, " on TF: ", EnumToString(atrTF));

       // --- NEW ADX INITIALIZATION ---
       if(UseADX)
       {
          // Safe Fallback for ADX
          int activeADX = (InpEnableShadowMaster && SymbolData[index].Dyn_ADX_Period > 0) ? SymbolData[index].Dyn_ADX_Period : ((G_ADX_Period > 0) ? G_ADX_Period : 14);
          SymbolData[index].ADX_Handle = iADX(analysisSymbol, PERIOD_CURRENT, activeADX);
          if(SymbolData[index].ADX_Handle == INVALID_HANDLE)
             if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print("Warning: Failed to create ADX handle for ", analysisSymbol);
       }
       else
       {
          SymbolData[index].ADX_Handle = INVALID_HANDLE;
       }

       // Initialize MA stop loss handle
       if(StopLossType == SL_MA)
       {
          SymbolData[index].MA_SL_Handle = iMA(analysisSymbol, PERIOD_CURRENT, MA_SL_Period, 0, GetMAMethod(MA_SL_Method), GetMASource(MA_SL_Source));
       }
       else
       {
          SymbolData[index].MA_SL_Handle = INVALID_HANDLE;
       }
    }
    else
    {
       SymbolData[index].ATR_Handle = INVALID_HANDLE;
       SymbolData[index].ADX_Handle = INVALID_HANDLE;
       SymbolData[index].MA_SL_Handle = INVALID_HANDLE;
    }

// Initialize VWAP data
   SymbolData[index].VWAP1.Value = 0;
   SymbolData[index].VWAP1.CumulativeVolume = 0;
   SymbolData[index].VWAP1.CumulativePV = 0;
   SymbolData[index].VWAP1.LastResetTime = 0;
   SymbolData[index].VWAP1.StartTime = 0;
   SymbolData[index].VWAP1.SessionHigh = 0;
   SymbolData[index].VWAP1.SessionLow = 0;
   SymbolData[index].VWAP1.Initialized = false;

   SymbolData[index].VWAP2_High = SymbolData[index].VWAP1;
   SymbolData[index].VWAP2_Low = SymbolData[index].VWAP1;
   SymbolData[index].VWAP3 = SymbolData[index].VWAP1;
   
   // --- FIX: Force State Backfill Immediately ---
    if(!lightweightCoordinator)
       BackfillVWAPState(index); 
   // --------------------------------------------

// Initialize arrays and variables
   SymbolData[index].BoxHighCount = 0;
   SymbolData[index].BoxLowCount = 0;
   SymbolData[index].OriginalBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   SymbolData[index].CurrentStakeMultiplier = 1.0;
   SymbolData[index].GridLevels = 0;
   SymbolData[index].StackMultiplier = 1.0;
   SymbolData[index].StackUpdates = 0;
   SymbolData[index].TrailUpdateCount = 0;
   SymbolData[index].LastSLPrice = 0;
   SymbolData[index].PositionCount = 0;
   SymbolData[index].LastTradeTime = 0;
   SymbolData[index].DailyProfitLoss = 0;
   SymbolData[index].LastDailyReset = TimeCurrent();
   SymbolData[index].GridTargetReached = false;
   SymbolData[index].GridInTrailing = false;
   SymbolData[index].GridInStacking = false;
   SymbolData[index].GridBasketStopLoss = 0;
   SymbolData[index].GridBasketTakeProfit = 0;
   SymbolData[index].GridBasketEntry = 0;
   SymbolData[index].GridBasketVolume = 0;
   SymbolData[index].GridTargetProfit = 0;
   SymbolData[index].GridStackLevels = 0;
   SymbolData[index].GridTrailUpdates = 0;
   SymbolData[index].GridStackMultiplier = 1.0;
   SymbolData[index].StackLastTrailUpdate = false;
   SymbolData[index].LastStackTime = 0;
   SymbolData[index].LastStackSL = 0;
   SymbolData[index].TrailLocked = (LockTrail != LOCK_TRAIL_NONE);
   SymbolData[index].LockBreakEvenPrice = 0;
   SymbolData[index].LockTPReached = false;
   SymbolData[index].LastCandleTime = 0;
   SymbolData[index].ProcessedThisCandle = false;
   SymbolData[index].LastAlertTime = 0;
   SymbolData[index].LastSignal = "";
   SymbolData[index].PreviousMasterSL = 0;
   SymbolData[index].PreviousBasketSL = 0;
   SymbolData[index].MasterSLMoved = false;
   SymbolData[index].BasketSLMoved = false;
   SymbolData[index].TPActivated = false;
   SymbolData[index].InitialTP = 0;
   SymbolData[index].LastGridCheckTime = 0;
   SymbolData[index].StackAlreadyAddedThisUpdate = false;
   SymbolData[index].GridStackAlreadyAddedThisUpdate = false;
   SymbolData[index].MasterTicket = 0;
   SymbolData[index].MasterSL = 0;
   SymbolData[index].MasterEntry = 0;
   SymbolData[index].MasterType = POSITION_TYPE_BUY;
   SymbolData[index].MasterHasValidSL = false;
   SymbolData[index].GridPhase1Active = false;
   SymbolData[index].GridPhase2Active = false;
   SymbolData[index].PendingTrailSL = 0;
   SymbolData[index].HasPendingTrail = false;
   SymbolData[index].CurrentGridSequence = 0;
   SymbolData[index].LastGridReset = TimeCurrent();
   SymbolData[index].GridStakeMultiplier = 1.0;

// Initialize stack trackers
   SymbolData[index].NonGridStack.Counter = 0;
   SymbolData[index].NonGridStack.LastProcessedCounter = 0;
   SymbolData[index].NonGridStack.SLMovedThisTick = false;
   SymbolData[index].NonGridStack.LastSLMoveTime = 0;
   SymbolData[index].NonGridStack.LastSLPrice = 0;

   SymbolData[index].GridStack.Counter = 0;
   SymbolData[index].GridStack.LastProcessedCounter = 0;
   SymbolData[index].GridStack.SLMovedThisTick = false;
   SymbolData[index].GridStack.LastSLMoveTime = 0;
   SymbolData[index].GridStack.LastSLPrice = 0;

// Initialize other variables
   SymbolData[index].LastTickTime = 0;
   SymbolData[index].LastVWAPUpdate = 0;
   SymbolData[index].NewVWAPHighLowSet = false;
   SymbolData[index].NonGridSLMovedThisTick = false;
   SymbolData[index].GridSLMovedThisTick = false;
   SymbolData[index].BoxHistoryWarmupQueued = false;
   SymbolData[index].BoxHistoryWarmupDone = false;
   SymbolData[index].BoxHistoryWarmupNextAttemptMs = 0;
   SymbolData[index].BoxHistoryWarmupInProgress = false;
   SymbolData[index].BoxHistoryWarmupCursor = 0;
   SymbolData[index].BoxHistoryWarmupBarsToCheck = 0;
   SymbolData[index].BoxHistoryWarmupPrevHigh = 0.0;
   SymbolData[index].BoxHistoryWarmupPrevLow = 0.0;
   SymbolData[index].BoxHistoryWarmupLastTotalBars = 0;

// Initialize Raw Lot Trackers
   SymbolData[index].RawNextGridLot      = 0.0;
   SymbolData[index].LastUsedGridRawLot  = 0.0;
   SymbolData[index].RawNextStackLot     = 0.0;
   SymbolData[index].LastUsedStackRawLot = 0.0;

// Initialize OR Reversal
   SymbolData[index].OR_Active = false;
   SymbolData[index].OR_ExpiryTime = 0;
   SymbolData[index].OR_High = 0;
   SymbolData[index].OR_Low = 0;
   SymbolData[index].OR_WasBullish = false;
   SymbolData[index].OR_BreakoutOccurred = false;
   SymbolData[index].OR_LastCheckedBar = 0;
   SymbolData[index].OR_LastDay = -1;

// Initialize Grid TP Tracking
   SymbolData[index].GridTPHit = false;
   SymbolData[index].GridTPHitPrice = 0;
   SymbolData[index].GridSequenceDepth = 0;

// --- FIX: POPULATE BOX DATA IMMEDIATELY ---
    bool restoredBoxHistory = false;
    if(!lightweightCoordinator)
    {
       if(G_FastChartSwitchMode)
          restoredBoxHistory = LoadBoxHistoryCacheForSymbol(analysisSymbol, index);

       if(restoredBoxHistory)
       {
          SymbolData[index].BoxHistoryWarmupQueued = false;
          SymbolData[index].BoxHistoryWarmupDone = true;
          SymbolData[index].BoxHistoryWarmupNextAttemptMs = 0;
       }
       else
       {
          QueueBoxHistoryWarmup(index, 0);
       }
    }
    else
    {
       SymbolData[index].BoxHistoryWarmupQueued = false;
       SymbolData[index].BoxHistoryWarmupDone = true;
       SymbolData[index].BoxHistoryWarmupNextAttemptMs = 0;
    }
// ------------------------------------------

// Initialize Grid TP Tracking
   SymbolData[index].GridTPHit = false;
   SymbolData[index].GridTPHitPrice = 0;
   SymbolData[index].GridSequenceDepth = 0;
   SymbolData[index].ZoneActive = false;
   SymbolData[index].ZoneTopPrice = 0.0;
   SymbolData[index].ZoneBottomPrice = 0.0;
   SymbolData[index].ZoneSeqCount = 0;
   SymbolData[index].ZoneNextLot = 0.0;
   SymbolData[index].ZoneResolved = false;
   SymbolData[index].BasketStateCount = 0;
   for(int basketStateIndex = 0; basketStateIndex < MBP_MAX_BASKETS; basketStateIndex++)
      SymbolData[index].BasketStates[basketStateIndex] = NULL;

// --- NEW: INIT RECOVERY ---
   SymbolData[index].AccumulatedPruningLoss = 0.0;
   SymbolData[index].AccumulatedCriticalLoss = 0.0; // <--- Initialize New Bank
   SymbolData[index].CurrentRecoveryPortion = 0.0;
   SymbolData[index].RecoveryIteration = 1;

// [Inside InitializeSymbolData]
   SymbolData[index].RecoveryIteration = 1;

    if(!lightweightCoordinator)
       InitFilterTracker(index);
   
   return true;
  }

//+------------------------------------------------------------------+
//| Helper: Brute Force Delete by Prefix                             |
//+------------------------------------------------------------------+
void DeleteObjectsByPrefix(string prefix)
{
   // Loop backwards to safely delete
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, prefix) == 0) // If name STARTS with prefix
      {
         ObjectDelete(0, name);
      }
   }
}

//+------------------------------------------------------------------+
//| Deinitialize symbol data (Fixed: Native Prefix Deletion)         |
//+------------------------------------------------------------------+
void DeinitializeSymbolData(int index)
{
   // 1. Release Indicators (Standard Logic)
   for(int i = 0; i < 5; i++) {
      for(int tf = 0; tf < 7; tf++) {
         if(SymbolData[index].MA_Handles[i][tf] != INVALID_HANDLE)
            IndicatorRelease(SymbolData[index].MA_Handles[i][tf]);
      }
   }
   if(SymbolData[index].ATR_Handle != INVALID_HANDLE) IndicatorRelease(SymbolData[index].ATR_Handle);
   if(SymbolData[index].ADX_Handle != INVALID_HANDLE) IndicatorRelease(SymbolData[index].ADX_Handle);
   if(SymbolData[index].MA_SL_Handle != INVALID_HANDLE) IndicatorRelease(SymbolData[index].MA_SL_Handle);

   // 2. --- CHART CLEANUP ---
   // We only perform visual cleanup if this index corresponds to the chart symbol
   // or if we want to ensure a global wipe of bot objects.
   
   string symbol = SymbolData[index].symbol;
   string execSymbol = GetBaseSymbol(symbol);

   // A. Remove Box Segments (Global objects on the chart)
   // Parameters: ChartID(0), Prefix, SubWindow(-1=All), Type(-1=All)
   ObjectsDeleteAll(0, "BoxSeg_", -1, -1);
   ObjectsDeleteAll(0, "BoxVert_", -1, -1);

   // B. Remove Zone & Grid Lines (Symbol Specific)
   ObjectsDeleteAll(0, "ZoneTop_" + symbol, -1, -1);
   ObjectsDeleteAll(0, "ZoneBot_" + symbol, -1, -1);
   ObjectsDeleteAll(0, "ZoneTop_" + execSymbol, -1, -1);
   ObjectsDeleteAll(0, "ZoneBot_" + execSymbol, -1, -1);
   
   ObjectsDeleteAll(0, "Grid_NextLevel_", -1, -1); 

   // C. Remove OR Reversal Lines
   ObjectsDeleteAll(0, "OR_High_", -1, -1);
   ObjectsDeleteAll(0, "OR_Low_", -1, -1);

   // D. Remove News & GUI
   ObjectsDeleteAll(0, "NewsLine_", -1, -1);
   ObjectsDeleteAll(0, "NewsPaint_", -1, -1);
   ObjectsDeleteAll(0, "MAN_", -1, -1);
   ObjectsDeleteAll(0, BTN_PREFIX_LIST, -1, -1);

   // E. BUG-B3 FIX: Free heap-allocated basket states to prevent memory leaks
   MBP_FreeAllBasketStates(SymbolData[index]);

   // 3. Force Redraw
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Update VWAP for symbol (Optimized: Incremental State Machine)    |
//| Matches "Assistant.mq5" Logic exactly                            |
//+------------------------------------------------------------------+
void UpdateVWAP(int symbolIndex)
{
   // Use 'idx' to access the specific symbol's DataMode
   // Get Bar 0 (Live) - Uses Smart Getters for Renko Compatibility
   double close0 = GetClose(symbolIndex, 0);
   double high0  = GetHigh(symbolIndex, 0);
   double low0   = GetLow(symbolIndex, 0);
   
   // Volume is trickier; for Median Renko we rely on the resolved index
   long   vol0   = GetManagedVolume(symbolIndex, 0);
   
   string symbol = SymbolData[symbolIndex].symbol;
   datetime current_time = TimeCurrent();
   
   // Prepare Prices
   double price1 = 0, price3 = 0;
   switch(VWAP1_PriceSource) { 
      case PRICE_TYPICAL: price1 = (high0+low0+close0)/3.0; break; 
      default: price1 = close0;
   }
   switch(VWAP3_PriceSource) { 
      case PRICE_TYPICAL: price3 = (high0+low0+close0)/3.0; break;
      default: price3 = close0; 
   }

   // ---------------------------------------------------
   // VWAP 1 (Daily) & VWAP 3 (Session) - Standard Logic
   // ---------------------------------------------------
   if(NeedVWAP1Runtime()) {
      if(CheckVWAPReset(current_time, SymbolData[symbolIndex].VWAP1, 1))
         ResetVWAPData(SymbolData[symbolIndex].VWAP1, current_time, 1);
      CalculateVWAPValue(price1, vol0, SymbolData[symbolIndex].VWAP1);
   }
   if(NeedVWAP3Runtime()) {
       if(CheckVWAPReset(current_time, SymbolData[symbolIndex].VWAP3, 3))
         ResetVWAPData(SymbolData[symbolIndex].VWAP3, current_time, 3);
      CalculateVWAPValue(price3, vol0, SymbolData[symbolIndex].VWAP3);
   }

   // -----------------------------------------------------------------
   // VWAP 2: OPTIMIZED DYNAMIC LOGIC (Matches Assistant.mq5)
   // -----------------------------------------------------------------
   if(NeedVWAP2Runtime())
   {
      double c1 = GetClose(symbolIndex, 1);
      double h1 = GetHigh(symbolIndex, 1);
      double l1 = GetLow(symbolIndex, 1);
      long   v1 = GetManagedVolume(symbolIndex, 1);
         
       // A. Check for New Bar or Uninitialized State
      datetime barTime = GetTime(symbolIndex, 0);
      bool isNewBar = (barTime != SymbolData[symbolIndex].LastVWAPUpdate);
      
      if(!SymbolData[symbolIndex].VWAP2_High.Initialized || !SymbolData[symbolIndex].VWAP2_Low.Initialized) {
         // Force full recalculation from history if not ready
         BackfillVWAPState(symbolIndex);
         SymbolData[symbolIndex].LastVWAPUpdate = barTime;
         SyncSharedSymbolRuntimeToBasketClones(symbolIndex);
         return; // Backfill handles the current state
      }

      // B. Handle New Bar Event (Commit Bar 1 to History)
      if(isNewBar)
      {
         double p1 = 0; 
         
         // --- HIGH VWAP COMMIT (Bar 1) ---
         // 1. Check Breakout on Bar 1
         bool resetH = false;
         if(SymbolData[symbolIndex].VWAP2_High.CumulativeVolume > 0) {
            double prevVWAP = SymbolData[symbolIndex].VWAP2_High.CumulativePV / SymbolData[symbolIndex].VWAP2_High.CumulativeVolume;
            if(c1 > prevVWAP) resetH = true;
         }
         
         if(resetH) {
            SymbolData[symbolIndex].VWAP2_High.CumulativePV = 0;
            SymbolData[symbolIndex].VWAP2_High.CumulativeVolume = 0;
            SymbolData[symbolIndex].VWAP2_High.SessionHigh = -DBL_MAX; // Reset Extreme
         }
         
         // 2. Update Extreme
         if(h1 > SymbolData[symbolIndex].VWAP2_High.SessionHigh) 
            SymbolData[symbolIndex].VWAP2_High.SessionHigh = h1;
            
         // 3. Accumulate Bar 1
         switch(VH_Source) {
            case PRICE_HIGH: p1 = h1; break;
            case PRICE_LOW:  p1 = l1; break;
            case PRICE_CLOSE:p1 = c1; break;
            default:         p1 = (h1+l1+c1)/3.0;
         }
         SymbolData[symbolIndex].VWAP2_High.CumulativePV += p1 * (double)v1;
         SymbolData[symbolIndex].VWAP2_High.CumulativeVolume += (double)v1;


         // --- LOW VWAP COMMIT (Bar 1) ---
         // 1. Check Breakout on Bar 1
         bool resetL = false;
         if(SymbolData[symbolIndex].VWAP2_Low.CumulativeVolume > 0) {
            double prevVWAP = SymbolData[symbolIndex].VWAP2_Low.CumulativePV / SymbolData[symbolIndex].VWAP2_Low.CumulativeVolume;
            if(c1 < prevVWAP) resetL = true;
         }
         
         if(resetL) {
            SymbolData[symbolIndex].VWAP2_Low.CumulativePV = 0;
            SymbolData[symbolIndex].VWAP2_Low.CumulativeVolume = 0;
            SymbolData[symbolIndex].VWAP2_Low.SessionLow = DBL_MAX; // Reset Extreme
         }
         
         // 2. Update Extreme
         if(l1 < SymbolData[symbolIndex].VWAP2_Low.SessionLow) 
            SymbolData[symbolIndex].VWAP2_Low.SessionLow = l1;
            
         // 3. Accumulate Bar 1
         switch(VL_Source) {
            case PRICE_HIGH: p1 = h1; break;
            case PRICE_LOW:  p1 = l1; break;
            case PRICE_CLOSE:p1 = c1; break;
            default:         p1 = (h1+l1+c1)/3.0;
         }
         SymbolData[symbolIndex].VWAP2_Low.CumulativePV += p1 * (double)v1;
         SymbolData[symbolIndex].VWAP2_Low.CumulativeVolume += (double)v1;
         
         // Update Timestamp
         SymbolData[symbolIndex].LastVWAPUpdate = barTime;
      }

      // C. Calculate LIVE Value (Bar 0) - Without Committing State
      // We take the committed state and add Bar 0 temporarily
      
      // -- High Live --
      double liveH_Ext = MathMax(high0, SymbolData[symbolIndex].VWAP2_High.SessionHigh);
      double liveH_P   = 0;
      switch(VH_Source) {
         case PRICE_HIGH: liveH_P = high0; break;
         case PRICE_LOW:  liveH_P = low0; break;
         case PRICE_CLOSE:liveH_P = close0; break;
         default:         liveH_P = (high0+low0+close0)/3.0;
      }
      double liveH_PV  = SymbolData[symbolIndex].VWAP2_High.CumulativePV + (liveH_P * (double)vol0);
      double liveH_Vol = SymbolData[symbolIndex].VWAP2_High.CumulativeVolume + (double)vol0;
      
      if(liveH_Vol > 0) SymbolData[symbolIndex].VWAP2_High.Value = liveH_PV / liveH_Vol;
      else              SymbolData[symbolIndex].VWAP2_High.Value = liveH_P;

      // -- Low Live --
      double liveL_Ext = MathMin(low0, SymbolData[symbolIndex].VWAP2_Low.SessionLow);
      double liveL_P   = 0;
      switch(VL_Source) {
         case PRICE_HIGH: liveL_P = high0; break;
         case PRICE_LOW:  liveL_P = low0; break;
         case PRICE_CLOSE:liveL_P = close0; break;
         default:         liveL_P = (high0+low0+close0)/3.0;
      }
      double liveL_PV  = SymbolData[symbolIndex].VWAP2_Low.CumulativePV + (liveL_P * (double)vol0);
      double liveL_Vol = SymbolData[symbolIndex].VWAP2_Low.CumulativeVolume + (double)vol0;
      
      if(liveL_Vol > 0) SymbolData[symbolIndex].VWAP2_Low.Value = liveL_PV / liveL_Vol;
      else              SymbolData[symbolIndex].VWAP2_Low.Value = liveL_P;
   }

   SyncSharedSymbolRuntimeToBasketClones(symbolIndex);
}

//+------------------------------------------------------------------+
//| Backfill VWAP State (Runs once on Init)                          |
//+------------------------------------------------------------------+
void BackfillVWAPState(int symbolIndex)
{
   string symbol = SymbolData[symbolIndex].symbol;
   
   // 1. Reset State
   SymbolData[symbolIndex].VWAP2_High.CumulativePV = 0;
   SymbolData[symbolIndex].VWAP2_High.CumulativeVolume = 0;
   SymbolData[symbolIndex].VWAP2_High.SessionHigh = -DBL_MAX;
   SymbolData[symbolIndex].VWAP2_High.Initialized = true;

   SymbolData[symbolIndex].VWAP2_Low.CumulativePV = 0;
   SymbolData[symbolIndex].VWAP2_Low.CumulativeVolume = 0;
   SymbolData[symbolIndex].VWAP2_Low.SessionLow = DBL_MAX;
   SymbolData[symbolIndex].VWAP2_Low.Initialized = true;

   // 2. Determine Lookback (Start of today or Max 1000 bars)
   ENUM_TIMEFRAMES seriesTF = GetManagedSeriesTimeframe(symbolIndex);
   int totalBars = iBars(symbol, seriesTF);
   if(totalBars < 2)
      return;

   int startIdx = MathMin(1000, totalBars - 1);
   
   // Optional: Align to start of day if preferred, but 1000 bars is safe for Renko
   
   // 3. Forward Loop to build state up to Bar 1
   for(int k = startIdx; k >= 1; k--)
   {
      double c = GetClose(symbolIndex, k); // Uses Smart Getter
      double h = GetHigh(symbolIndex, k);
      double l = GetLow(symbolIndex, k);
      long   v = GetManagedVolume(symbolIndex, k);
      
      // --- HIGH LOGIC ---
      bool resetH = false;
      if(SymbolData[symbolIndex].VWAP2_High.CumulativeVolume > 0) {
         double prevVWAP = SymbolData[symbolIndex].VWAP2_High.CumulativePV / SymbolData[symbolIndex].VWAP2_High.CumulativeVolume;
         if(c > prevVWAP) resetH = true;
      }
      
      if(resetH) {
         SymbolData[symbolIndex].VWAP2_High.CumulativePV = 0;
         SymbolData[symbolIndex].VWAP2_High.CumulativeVolume = 0;
         SymbolData[symbolIndex].VWAP2_High.SessionHigh = -DBL_MAX;
      }
      
      if(h > SymbolData[symbolIndex].VWAP2_High.SessionHigh) 
         SymbolData[symbolIndex].VWAP2_High.SessionHigh = h;
         
      double pH = 0;
      switch(VH_Source) {
         case PRICE_HIGH: pH = h; break;
         case PRICE_LOW:  pH = l; break;
         case PRICE_CLOSE:pH = c; break;
         default:         pH = (h+l+c)/3.0;
      }
      SymbolData[symbolIndex].VWAP2_High.CumulativePV += pH * (double)v;
      SymbolData[symbolIndex].VWAP2_High.CumulativeVolume += (double)v;

      // --- LOW LOGIC ---
      bool resetL = false;
      if(SymbolData[symbolIndex].VWAP2_Low.CumulativeVolume > 0) {
         double prevVWAP = SymbolData[symbolIndex].VWAP2_Low.CumulativePV / SymbolData[symbolIndex].VWAP2_Low.CumulativeVolume;
         if(c < prevVWAP) resetL = true;
      }
      
      if(resetL) {
         SymbolData[symbolIndex].VWAP2_Low.CumulativePV = 0;
         SymbolData[symbolIndex].VWAP2_Low.CumulativeVolume = 0;
         SymbolData[symbolIndex].VWAP2_Low.SessionLow = DBL_MAX;
      }
      
      if(l < SymbolData[symbolIndex].VWAP2_Low.SessionLow) 
         SymbolData[symbolIndex].VWAP2_Low.SessionLow = l;
         
      double pL = 0;
      switch(VL_Source) {
         case PRICE_HIGH: pL = h; break;
         case PRICE_LOW:  pL = l; break;
         case PRICE_CLOSE:pL = c; break;
         default:         pL = (h+l+c)/3.0;
      }
      SymbolData[symbolIndex].VWAP2_Low.CumulativePV += pL * (double)v;
      SymbolData[symbolIndex].VWAP2_Low.CumulativeVolume += (double)v;
   }
}

//+------------------------------------------------------------------+
//| Calculate VWAP value                                             |
//+------------------------------------------------------------------+
double CalculateVWAPValue(double price, long volume, SVWAPData &vwap_data)
  {
   if(volume <= 0)
      return vwap_data.Value;

   vwap_data.CumulativePV += price * (double)volume;
   vwap_data.CumulativeVolume += (double)volume;

   if(vwap_data.CumulativeVolume > 0)
      vwap_data.Value = vwap_data.CumulativePV / vwap_data.CumulativeVolume;

   return vwap_data.Value;
  }

//+------------------------------------------------------------------+
//| Check VWAP reset conditions                                      |
//+------------------------------------------------------------------+
bool CheckVWAPReset(datetime current_time, SVWAPData &vwap_data, int vwap_type, double current_high = 0, double current_low = 0)
  {
   MqlDateTime current_ny, last_ny;
   ConvertToNYTime(current_time, current_ny);

   if(vwap_data.LastResetTime > 0)
      ConvertToNYTime(vwap_data.LastResetTime, last_ny);
   else
      return true; // First time initialization

   switch(vwap_type)
     {
      case 1: // VWAP1 - Continuous, resets at specified NY time
        {
         // Check if reset hour passed
         bool reset_condition = false;

         // If current time is at or after reset time, and last reset was before reset time
         if(current_ny.hour == VWAP1_ResetHour && current_ny.min >= VWAP1_ResetMinute)
           {
            if(last_ny.hour < VWAP1_ResetHour ||
               (last_ny.hour == VWAP1_ResetHour && last_ny.min < VWAP1_ResetMinute))
              {
               reset_condition = true;
              }
           }
         // If current time is after reset hour (next hour)
         else
            if(current_ny.hour > VWAP1_ResetHour)
              {
               if(last_ny.hour <= VWAP1_ResetHour)
                 {
                  reset_condition = true;
                 }
              }

         return reset_condition;
        }

      case 2: // VWAP2 - Anchored to daily high/low
        {
         // Reset at start of NY trading day (assume 00:00 NY time)
         return (current_ny.day != last_ny.day);
        }

      case 3: // VWAP3 - Session VWAP starting at specified time
        {
         // Check if we're in a new session (start time has passed since last reset)
         if(current_ny.hour == VWAP3_StartHour && current_ny.min >= VWAP3_StartMinute)
           {
            if(last_ny.hour < VWAP3_StartHour ||
               (last_ny.hour == VWAP3_StartHour && last_ny.min < VWAP3_StartMinute))
              {
               return true;
              }
           }
         return false;
        }
     }

   return false;
  }

//+------------------------------------------------------------------+
//| Reset VWAP data                                                  |
//+------------------------------------------------------------------+
void ResetVWAPData(SVWAPData &vwap_data, datetime current_time, int vwap_type, double current_high = 0, double current_low = 0)
  {
   vwap_data.CumulativePV = 0;
   vwap_data.CumulativeVolume = 0;
   vwap_data.Value = 0;
   vwap_data.LastResetTime = current_time;
   vwap_data.StartTime = current_time;
   vwap_data.Initialized = true;

   if(vwap_type == 2) // VWAP2 - anchored
     {
      vwap_data.SessionHigh = current_high;
      vwap_data.SessionLow = current_low;
     }
  }

//+------------------------------------------------------------------+
//| Helper: Check for Fractal High (Bar i is higher than neighbors)  |
//+------------------------------------------------------------------+
bool IsFractalHigh(string symbol, int i)
{
   // Needs valid neighbors (i+1 and i-1)
   // Since we scan pBar > currentIdx (where currentIdx=0), i is at least 1.
   double h = iHigh(symbol, PERIOD_CURRENT, i);
   double hL = iHigh(symbol, PERIOD_CURRENT, i+1);
   double hR = iHigh(symbol, PERIOD_CURRENT, i-1);
   return (h > hL && h > hR);
}

//+------------------------------------------------------------------+
//| Helper: Check for Fractal Low (Bar i is lower than neighbors)    |
//+------------------------------------------------------------------+
bool IsFractalLow(string symbol, int i)
{
   double l = iLow(symbol, PERIOD_CURRENT, i);
   double lL = iLow(symbol, PERIOD_CURRENT, i+1);
   double lR = iLow(symbol, PERIOD_CURRENT, i-1);
   return (l < lL && l < lR);
}

//+------------------------------------------------------------------+
//| Helper: Check if a specific bar is a valid Pivot (High/Low)      |
//| Includes "Right Side Check" to prevent Renko Stair-stepping      |
//+------------------------------------------------------------------+
bool IsPivotBar(string symbol, ENUM_TIMEFRAMES tf, int barIndex, bool isHigh, int lookback)
{
   int totalBars = iBars(symbol, tf);
   if(barIndex >= totalBars - lookback || barIndex < 1) return false;

   // 1. Pivot Value Candidate
   double pivotVal = isHigh ? iHigh(symbol, tf, barIndex) : iLow(symbol, tf, barIndex);

   // 2. Left Side Check (Older bars)
   for(int i = 1; i <= lookback; i++)
   {
      if(barIndex + i >= totalBars) break;
      double neighbor = isHigh ? iHigh(symbol, tf, barIndex + i) : iLow(symbol, tf, barIndex + i);
      
      if(isHigh && neighbor >= pivotVal) return false; // Not a high
      if(!isHigh && neighbor <= pivotVal) return false; // Not a low
   }

   // 3. Right Side Check (Newer bars)
   for(int i = 1; i <= lookback; i++)
   {
      int checkIndex = barIndex - i;
      if(checkIndex < 0) break; 

      double neighbor = isHigh ? iHigh(symbol, tf, checkIndex) : iLow(symbol, tf, checkIndex);
      
      if(isHigh && neighbor > pivotVal) return false; // Newer bar is higher
      if(!isHigh && neighbor < pivotVal) return false; // Newer bar is lower
   }

   return true;
}

//+------------------------------------------------------------------+
//| Update box levels (Seamless Visuals + User Selectable Breakout)  |
//+------------------------------------------------------------------+
void UpdateBoxLevelsForChart(int symbolIndex,
                             const long chartID,
                             string sourceSymbol = "",
                             ENUM_TIMEFRAMES sourcePeriod = PERIOD_CURRENT)
{
   string symbol = (sourceSymbol == "") ? SymbolData[symbolIndex].symbol : sourceSymbol;
   if(sourcePeriod == PERIOD_CURRENT)
      sourcePeriod = (chartID > 0) ? PERIOD_M1 : (ENUM_TIMEFRAMES)ChartPeriod(0);

   int historyDepth = BoxLines_History;
   int lookback = (InpEnableShadowMaster && SymbolData[symbolIndex].Dyn_Box_Lookback > 0) ? SymbolData[symbolIndex].Dyn_Box_Lookback : G_Box_Lookback;
   int totalBars = iBars(symbol, sourcePeriod);

   // Safety check for data availability, but clamp to whatever the chart has loaded.
   if(totalBars <= lookback + 2)
      return;

   int maxDrawableHistory = totalBars - lookback - 2;
   if(maxDrawableHistory < 1)
      return;

   if(historyDepth > maxDrawableHistory)
      historyDepth = maxDrawableHistory;

   // --- TEMPORARY STORAGE ---
   double tempHighs[];
   double tempLows[];
   ArrayResize(tempHighs, 0);
   ArrayResize(tempLows, 0);

   // --- INITIAL STATE ---
   double activeHighLine = iHigh(symbol, sourcePeriod, historyDepth);
   double activeLowLine  = iLow(symbol, sourcePeriod, historyDepth);
   int periodSeconds = PeriodSeconds(sourcePeriod);
   if(periodSeconds <= 0)
      periodSeconds = 60;
   
   // Visual Trackers
   double drawHighVal = activeHighLine;
   double drawLowVal  = activeLowLine;
   datetime drawStartH = iTime(symbol, sourcePeriod, historyDepth);
   datetime drawStartL = iTime(symbol, sourcePeriod, historyDepth);
   int segCountH = 0;
   int segCountL = 0;
   bool drawOnChart = (chartID >= 0);

   // =================================================================
   // 1. MAIN LOGIC LOOP (PAST -> PRESENT -> LIVE)
   // =================================================================
   for(int i = historyDepth; i >= 0; i--)
   {
      // A. GET DATA FOR THIS BAR
      double currClose = iClose(symbol, sourcePeriod, i);
      double currHigh  = iHigh(symbol, sourcePeriod, i);
      double currLow   = iLow(symbol, sourcePeriod, i);
      datetime currTime = iTime(symbol, sourcePeriod, i);

      // ----------------------------------------------------------------
      // B. DETERMINE BREAKOUT PRICES (NEW FEATURE)
      // ----------------------------------------------------------------
      double priceToCheckHigh;
      double priceToCheckLow;

      if(BoxBreakoutMethod == BOX_BREAK_CLOSE)
      {
         // Standard: Candle body must close outside
         priceToCheckHigh = currClose;
         priceToCheckLow  = currClose;
      }
      else
      {
         // Wick: Just the High/Low touching the level triggers expansion
         priceToCheckHigh = currHigh;
         priceToCheckLow  = currLow;
      }

      // ----------------------------------------------------------------
      // C. APPLY "EXPAND & SNAP" LOGIC
      // ----------------------------------------------------------------
      
      // --- CHECK HIGH LINE ---
      if(priceToCheckHigh > activeHighLine)
      {
         activeHighLine = currHigh; // Always expand to the absolute High
         
         // Snap the Low Line to the last valid Pivot Low
         for(int k=1; k<200; k++) {
            if(IsPivotBar(symbol, sourcePeriod, i+k, false, lookback)) {
               activeLowLine = iLow(symbol, sourcePeriod, i+k);
               break;
            }
         }
      }

      // --- CHECK LOW LINE ---
      if(priceToCheckLow < activeLowLine)
      {
         activeLowLine = currLow; // Always expand to the absolute Low
         
         // Snap the High Line to the last valid Pivot High
         for(int k=1; k<200; k++) {
             if(IsPivotBar(symbol, sourcePeriod, i+k, true, lookback)) {
               activeHighLine = iHigh(symbol, sourcePeriod, i+k);
               break;
            }
         }
      }

      // =================================================================
      // D. DRAWING LOGIC (Seamless Visuals)
      // =================================================================
      if(drawOnChart)
      {
         // --- DRAW HIGH SEGMENTS ---
         if(activeHighLine != drawHighVal || i == 0)
         {
            datetime endTime = (i == 0) ? (currTime + periodSeconds) : currTime;
            
            DrawSteplineSegmentOnChart(chartID, "BoxSeg_H_" + IntegerToString(segCountH), drawStartH, endTime, drawHighVal, BoxLines_ColorHigh);
            
            if(activeHighLine != drawHighVal)
            {
               DrawVerticalSegmentOnChart(chartID, "BoxVert_H_" + IntegerToString(segCountH), currTime, drawHighVal, activeHighLine, BoxLines_ColorHigh);
               drawHighVal = activeHighLine;
               drawStartH  = currTime;
               segCountH++;
            }
            if(i==0) segCountH++;
         }

         // --- DRAW LOW SEGMENTS ---
         if(activeLowLine != drawLowVal || i == 0)
         {
            datetime endTime = (i == 0) ? (currTime + periodSeconds) : currTime;
            
            if(drawLowVal < 999999) 
               DrawSteplineSegmentOnChart(chartID, "BoxSeg_L_" + IntegerToString(segCountL), drawStartL, endTime, drawLowVal, BoxLines_ColorLow);
            
            if(activeLowLine != drawLowVal)
            {
               if(drawLowVal < 999999 && activeLowLine < 999999)
                  DrawVerticalSegmentOnChart(chartID, "BoxVert_L_" + IntegerToString(segCountL), currTime, drawLowVal, activeLowLine, BoxLines_ColorLow);
               
               drawLowVal = activeLowLine;
               drawStartL = currTime;
               segCountL++;
            }
            if(i==0) segCountL++;
         }
      }

      // =================================================================
      // E. STORE DATA (CONDENSED SEGMENTS ONLY)
      // =================================================================
      
      // Highs
      int sH = ArraySize(tempHighs);
      if(sH == 0 || activeHighLine != tempHighs[sH - 1]) 
      {
         ArrayResize(tempHighs, sH + 1);
         tempHighs[sH] = activeHighLine;
      }

      // Lows
      int sL = ArraySize(tempLows);
      if(sL == 0 || activeLowLine != tempLows[sL - 1]) 
      {
         ArrayResize(tempLows, sL + 1);
         tempLows[sL] = activeLowLine;
      }
   }

   // =================================================================
   // 2. POPULATE MAIN ARRAYS FOR EA (Newest -> [0])
   // =================================================================
   
   SymbolData[symbolIndex].BoxHighCount = ArraySize(tempHighs);
   for(int k = 0; k < ArraySize(tempHighs); k++)
   {
      int reverseIdx = ArraySize(tempHighs) - 1 - k;
      if(k < 100)
         SymbolData[symbolIndex].BoxHigh[k] = tempHighs[reverseIdx];
   }

   SymbolData[symbolIndex].BoxLowCount = ArraySize(tempLows);
   for(int k = 0; k < ArraySize(tempLows); k++)
   {
      int reverseIdx = ArraySize(tempLows) - 1 - k;
      if(k < 100)
         SymbolData[symbolIndex].BoxLow[k] = tempLows[reverseIdx];
   }
   
   if(drawOnChart)
   {
      ObjectDelete(chartID, "BoxLine_H_Live");
      ObjectDelete(chartID, "BoxLine_L_Live");
      ChartRedraw(chartID);
   }

   SyncSharedSymbolRuntimeToBasketClones(symbolIndex);

   bool hasBoxHistory = (SymbolData[symbolIndex].BoxHighCount > 0 || SymbolData[symbolIndex].BoxLowCount > 0);
   if(hasBoxHistory)
     {
      SymbolData[symbolIndex].BoxHistoryWarmupQueued = false;
      SymbolData[symbolIndex].BoxHistoryWarmupDone = true;
      SymbolData[symbolIndex].BoxHistoryWarmupNextAttemptMs = 0;
     }
}

void UpdateBoxLevels(int symbolIndex)
{
   UpdateBoxLevelsForChart(symbolIndex, 0, SymbolData[symbolIndex].symbol, (ENUM_TIMEFRAMES)ChartPeriod(0));
}

void RefreshCurrentChartBoxLines(const bool force = false)
{
   if(G_IS_DEINIT || !ShowBoxLines)
   {
      DeleteBoxObjectsForChart(0);
      return;
   }

   int symbolIndex = ResolveDashboardHostFocusSymbolIndex(_Symbol);
   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return;

   if(!SymbolData[symbolIndex].active)
      return;

   static string lastChartSymbol = "";
   static string lastFocusSymbol = "";
   static uint lastRefreshMs = 0;
   string focusSymbol = SymbolData[symbolIndex].symbol;
   bool symbolChanged = (lastChartSymbol != _Symbol || lastFocusSymbol != focusSymbol);
   uint now = GetTickCount();

   if(!force && !symbolChanged && (now - lastRefreshMs) < 500)
      return;

   lastChartSymbol = _Symbol;
   lastFocusSymbol = focusSymbol;
   lastRefreshMs = now;
   UpdateBoxLevelsForChart(symbolIndex, 0, focusSymbol, (ENUM_TIMEFRAMES)ChartPeriod(0));
}
   
//+------------------------------------------------------------------+
//| Backfill Box History (Safe Version)                              |
//+------------------------------------------------------------------+
void BackfillBoxHistory(int symbolIndex)
  {
   string symbol = SymbolData[symbolIndex].symbol;

   ENUM_TIMEFRAMES boxTF = GetManagedSeriesTimeframe(symbolIndex);
   int totalBars = iBars(symbol, boxTF);
   if(totalBars < G_Box_Lookback + 5)
     {
      SymbolData[symbolIndex].BoxHistoryWarmupInProgress = false;
      QueueBoxHistoryWarmup(symbolIndex, 1000);
      return;
      }

   int barsToCheck = 500;
   if(barsToCheck > totalBars - 2)
      barsToCheck = totalBars - 2;
   if(barsToCheck <= 1)
     {
      SymbolData[symbolIndex].BoxHistoryWarmupQueued = false;
      SymbolData[symbolIndex].BoxHistoryWarmupDone = true;
      SymbolData[symbolIndex].BoxHistoryWarmupNextAttemptMs = 0;
      SymbolData[symbolIndex].BoxHistoryWarmupInProgress = false;
      return;
     }

   bool restartWarmup = (!SymbolData[symbolIndex].BoxHistoryWarmupInProgress ||
                         SymbolData[symbolIndex].BoxHistoryWarmupBarsToCheck != barsToCheck ||
                         SymbolData[symbolIndex].BoxHistoryWarmupLastTotalBars != totalBars);
   if(restartWarmup)
     {
      SymbolData[symbolIndex].BoxHighCount = 0;
      SymbolData[symbolIndex].BoxLowCount = 0;
      SymbolData[symbolIndex].BoxHistoryWarmupInProgress = true;
      SymbolData[symbolIndex].BoxHistoryWarmupCursor = barsToCheck;
      SymbolData[symbolIndex].BoxHistoryWarmupBarsToCheck = barsToCheck;
      SymbolData[symbolIndex].BoxHistoryWarmupPrevHigh = GetBoxLevelAtBar(symbolIndex, boxTF, barsToCheck + 1, true);
      SymbolData[symbolIndex].BoxHistoryWarmupPrevLow = GetBoxLevelAtBar(symbolIndex, boxTF, barsToCheck + 1, false);
      SymbolData[symbolIndex].BoxHistoryWarmupLastTotalBars = totalBars;
     }

   double prevHighVal = SymbolData[symbolIndex].BoxHistoryWarmupPrevHigh;
   double prevLowVal  = SymbolData[symbolIndex].BoxHistoryWarmupPrevLow;
   int cursor = MathMax(1, SymbolData[symbolIndex].BoxHistoryWarmupCursor);
   int endCursor = MathMax(1, cursor - 39);

   for(int k = cursor; k >= endCursor; k--)
     {

      // 1. Calculate the "Visual Box Level" for this specific historical bar
      double currHighVal = GetBoxLevelAtBar(symbolIndex, boxTF, k, true);
      double currLowVal  = GetBoxLevelAtBar(symbolIndex, boxTF, k, false);

      // 2. DETECT HIGH CHANGE (New Segment Formed)
      if(currHighVal > 0 && currHighVal != prevHighVal)
        {
         // Shift Array Down (Newest goes to [0])
         for(int m = 99; m > 0; m--)
            SymbolData[symbolIndex].BoxHigh[m] = SymbolData[symbolIndex].BoxHigh[m-1];

         // Insert New Segment Value
         SymbolData[symbolIndex].BoxHigh[0] = currHighVal;

         if(SymbolData[symbolIndex].BoxHighCount < 100)
            SymbolData[symbolIndex].BoxHighCount++;

         // Update Previous tracker
         prevHighVal = currHighVal;
        }

      // 3. DETECT LOW CHANGE (New Segment Formed)
      if(currLowVal > 0 && currLowVal < 999999 && currLowVal != prevLowVal)
        {
         // Shift Array Down
         for(int m = 99; m > 0; m--)
            SymbolData[symbolIndex].BoxLow[m] = SymbolData[symbolIndex].BoxLow[m-1];

         // Insert New Segment Value
         SymbolData[symbolIndex].BoxLow[0] = currLowVal;

         if(SymbolData[symbolIndex].BoxLowCount < 100)
            SymbolData[symbolIndex].BoxLowCount++;

         // Update Previous tracker
         prevLowVal = currLowVal;
        }
     }

   SymbolData[symbolIndex].BoxHistoryWarmupPrevHigh = prevHighVal;
   SymbolData[symbolIndex].BoxHistoryWarmupPrevLow = prevLowVal;
   SymbolData[symbolIndex].BoxHistoryWarmupCursor = endCursor - 1;

   if(SymbolData[symbolIndex].BoxHistoryWarmupCursor >= 1)
     {
      SymbolData[symbolIndex].BoxHistoryWarmupQueued = true;
      SymbolData[symbolIndex].BoxHistoryWarmupDone = false;
      SymbolData[symbolIndex].BoxHistoryWarmupNextAttemptMs = GetTickCount() + 25;
      return;
     }

   SyncSharedSymbolRuntimeToBasketClones(symbolIndex);

   SymbolData[symbolIndex].BoxHistoryWarmupQueued = false;
   SymbolData[symbolIndex].BoxHistoryWarmupDone = true;
   SymbolData[symbolIndex].BoxHistoryWarmupNextAttemptMs = 0;
   SymbolData[symbolIndex].BoxHistoryWarmupInProgress = false;

   if(!G_FastChartSwitchMode)
      if(MBP_LogTierEnabled(MBP_LOG_TIER_DEBUG)) Print("📦 ", symbol, " Box History Backfilled. Segments Found -> Highs: ", SymbolData[symbolIndex].BoxHighCount, " Lows: ", SymbolData[symbolIndex].BoxLowCount);
  }
   
//+------------------------------------------------------------------+
//| Helper: Calculate Safe Box Level for a specific past bar         |
//+------------------------------------------------------------------+
double GetBoxLevelAtBar(int symbolIndex, ENUM_TIMEFRAMES tf, int barIndex, bool isHigh)
{
   string symbol = SymbolData[symbolIndex].symbol;
   if(tf == PERIOD_CURRENT)
      tf = GetManagedSeriesTimeframe(symbolIndex);
   
   int lookback = (InpEnableShadowMaster && SymbolData[symbolIndex].Dyn_Box_Lookback > 0) ? SymbolData[symbolIndex].Dyn_Box_Lookback : G_Box_Lookback;
   
   int foundCount = 0;
   double extremeVal = isHigh ? 0 : 999999; 

   int totalBars = iBars(symbol, tf);
   if(totalBars == 0) return 0;

   int limit = 200;
   if(barIndex + limit >= totalBars) limit = totalBars - barIndex - 1;
   if(limit <= 0) return 0;

   // Check if we can use Smart Getters (Only works on Current Timeframe)
   bool useSmart = (tf == GetManagedSeriesTimeframe(symbolIndex));

   for(int k = barIndex; k < barIndex + limit; k++)
   {
      bool isPivot = true;
      double val = 0;

      if(k + lookback >= totalBars) break;
      
      if(isHigh)
      {
         // USE SMART GETTER IF ON CURRENT TF
         val = useSmart ? GetHigh(symbolIndex, k) : iHigh(symbol, tf, k);
         
         if(k == barIndex) {
            isPivot = false;
         } else {
            for(int j = 1; j <= lookback; j++) {
               int checkIndex = k - j;
               if(checkIndex < barIndex) break;
               
               double rightVal = useSmart ? GetHigh(symbolIndex, checkIndex) : iHigh(symbol, tf, checkIndex);
               if(val <= rightVal) { isPivot = false; break; }
            }
         }
         
         if(isPivot) {
            for(int j = 1; j <= lookback; j++) {
               double leftVal = useSmart ? GetHigh(symbolIndex, k + j) : iHigh(symbol, tf, k + j);
               if(val <= leftVal) { isPivot = false; break; }
            }
         }
      }
      else // Low Logic
      {
         val = useSmart ? GetLow(symbolIndex, k) : iLow(symbol, tf, k);

         if(k == barIndex) {
            isPivot = false;
         } else {
            for(int j = 1; j <= lookback; j++) {
               int checkIndex = k - j;
               if(checkIndex < barIndex) break;

               double rightVal = useSmart ? GetLow(symbolIndex, checkIndex) : iLow(symbol, tf, checkIndex);
               if(val >= rightVal) { isPivot = false; break; }
            }
         }

         if(isPivot) {
            for(int j = 1; j <= lookback; j++) {
               double leftVal = useSmart ? GetLow(symbolIndex, k + j) : iLow(symbol, tf, k + j);
               if(val >= leftVal) { isPivot = false; break; }
            }
         }
      }

      if(isPivot) {
         if(isHigh) { if(val > extremeVal) extremeVal = val; }
         else       { if(val < extremeVal) extremeVal = val; }
         foundCount++;
         if(foundCount >= Box_SL_Levels) break;
      }
   }

   if(foundCount == 0) return 0;
   return extremeVal;
}

//+------------------------------------------------------------------+
//| Check Box Trend Direction & Breakout (Multi-Timeframe)           |
//+------------------------------------------------------------------+
bool CheckBoxTrend(int symbolIndex, ENUM_ORDER_TYPE type)
  {
   if(!UseBoxTrendFilter)
      return true;

   string symbol = SymbolData[symbolIndex].symbol;
   string execSymbol = GetBaseSymbol(symbol);
   int tfsChecked = 0;

   for(int i = 0; i < 7; i++)
     {
      if(!TimeframeEnabled[i])
         continue;

      // Stop if we have checked the required number of lowest timeframes
      if(tfsChecked >= BoxTrend_TFs_Count)
         break;

      ENUM_TIMEFRAMES tf = Timeframes[i];

      // We need 3 distinct COMPLETED levels:
      // levels[0] = The most recent completed segment
      // levels[1] = The one before that
      // levels[2] = The one before that
      double levels[3] = {0, 0, 0};
      int found = 0;

      // 1. Scan back to find distinct COMPLETED levels
      // We start scanning at k=1 (closed bar) to find the first stable level
      double lastVal = 0;

      for(int k = 1; k < 500; k++)
        {
         double val = GetBoxLevelAtBar(symbolIndex, tf, k, (type == ORDER_TYPE_BUY));

         // Logic: We are looking for distinct steps.
         // If this is the first one found, store it.
         // If it's different from the last stored one, store it.
         if(val != 0)
           {
            if(found == 0)
              {
               levels[found] = val;
               found++;
              }
            else
               if(val != levels[found-1])
                 {
                  levels[found] = val;
                  found++;
                 }
           }

         if(found >= 3)
            break;
        }

      if(found < 3)
         return false; // Not enough history

      // 2. Evaluate Trend Direction (Stepping logic)
      bool trendCorrect = false;
      if(type == ORDER_TYPE_BUY)
        {
         // BUY Trend: Recent High > Older High > Oldest High
         if(levels[0] > levels[1] && levels[1] > levels[2])
            trendCorrect = true;
        }
      else
        {
         // SELL Trend: Recent Low < Older Low < Oldest Low
         if(levels[0] < levels[1] && levels[1] < levels[2])
            trendCorrect = true;
        }

      if(!trendCorrect)
         return false; // Trend failed on this TF

      // 3. --- BREAKOUT CHECK (Lowest TF Only) ---
      // We compare Current Price against levels[0] (The most recent COMPLETED box level)
      if(BoxTrend_ReqBreakout && tfsChecked == 0) // tfsChecked=0 is the lowest selected TF
        {
         double currentPrice = (type == ORDER_TYPE_BUY) ?
                               SymbolInfoDouble(execSymbol, SYMBOL_ASK) :
                               SymbolInfoDouble(execSymbol, SYMBOL_BID);

         if(type == ORDER_TYPE_BUY)
           {
            // Must have broken ABOVE the most recent completed Box High
            if(currentPrice <= levels[0])
               return false;
           }
         else
           {
            // Must have broken BELOW the most recent completed Box Low
            if(currentPrice >= levels[0])
               return false;
           }
        }
      // -----------------------------------------------------------

      tfsChecked++;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| Check ADX Filter (Shadow Master Compatible)                      |
//+------------------------------------------------------------------+
bool CheckADXFilter(int symbolIndex)
{
   if(!UseADX) return true;
   if(SymbolData[symbolIndex].ADX_Handle == INVALID_HANDLE) return true;

   double adxBuff[1];
   if(CopyBuffer(SymbolData[symbolIndex].ADX_Handle, 0, 0, 1, adxBuff) < 1)
      return false; // Data not ready

   double adxValue = adxBuff[0];

   // --- FALLBACK CHECK FOR ADX ---
   bool aiActive = false;
   if(InpEnableShadowMaster && SymbolData[symbolIndex].LastShadowUpdate > 0 && 
     (TimeCurrent() - SymbolData[symbolIndex].LastShadowUpdate < 172800))
   {
       if(SymbolData[symbolIndex].Dyn_ADX_MinLevel > 0) aiActive = true;
   }
   
   double activeADXMin = aiActive ? SymbolData[symbolIndex].Dyn_ADX_MinLevel : ADX_MinLevel;

   // Evaluate Logic
   if(ADX_TradeAbove)
   {
      // TREND MODE: Pass if ADX is Strong (Above Level)
      if(adxValue >= activeADXMin) return true;
   }
   else
   {
      // RANGE MODE: Pass if ADX is Weak (Below Level)
      if(adxValue <= activeADXMin) return true;
   }

   return false;
}
   
//+------------------------------------------------------------------+
//| Check for Hammer Candle (Reversal Buy)                           |
//+------------------------------------------------------------------+
bool IsHammer(int symbolIndex, ENUM_TIMEFRAMES tf, int index)
{
   // Use Smart Getters if on Current Timeframe (Renko Support)
   bool useSmart = (tf == PERIOD_CURRENT);
   string symbol = SymbolData[symbolIndex].symbol;

   double open  = useSmart ? GetOpen(symbolIndex, index)  : iOpen(symbol, tf, index);
   double close = useSmart ? GetClose(symbolIndex, index) : iClose(symbol, tf, index);
   double high  = useSmart ? GetHigh(symbolIndex, index)  : iHigh(symbol, tf, index);
   double low   = useSmart ? GetLow(symbolIndex, index)   : iLow(symbol, tf, index);

   double body      = MathAbs(close - open);
   double upperWick = high - MathMax(open, close);
   double lowerWick = MathMin(open, close) - low;
   
   if(body == 0) return false;
   return (lowerWick >= 2.0 * body) && (upperWick <= 0.5 * body);
}

//+------------------------------------------------------------------+
//| Check for Shooting Star (Reversal Sell)                          |
//+------------------------------------------------------------------+
bool IsShootingStar(int symbolIndex, ENUM_TIMEFRAMES tf, int index)
{
   bool useSmart = (tf == PERIOD_CURRENT);
   string symbol = SymbolData[symbolIndex].symbol;

   double open  = useSmart ? GetOpen(symbolIndex, index)  : iOpen(symbol, tf, index);
   double close = useSmart ? GetClose(symbolIndex, index) : iClose(symbol, tf, index);
   double high  = useSmart ? GetHigh(symbolIndex, index)  : iHigh(symbol, tf, index);
   double low   = useSmart ? GetLow(symbolIndex, index)   : iLow(symbol, tf, index);

   double body      = MathAbs(close - open);
   double upperWick = high - MathMax(open, close);
   double lowerWick = MathMin(open, close) - low;
   
   if(body == 0) return false;
   return (upperWick >= 2.0 * body) && (lowerWick <= 0.5 * body);
}

//+------------------------------------------------------------------+
//| Check for Bullish Engulfing                                      |
//+------------------------------------------------------------------+
bool IsBullishEngulfing(int symbolIndex, ENUM_TIMEFRAMES tf, int index)
{
   bool useSmart = (tf == PERIOD_CURRENT);
   string symbol = SymbolData[symbolIndex].symbol;

   double currOpen  = useSmart ? GetOpen(symbolIndex, index)   : iOpen(symbol, tf, index);
   double currClose = useSmart ? GetClose(symbolIndex, index)  : iClose(symbol, tf, index);
   double prevOpen  = useSmart ? GetOpen(symbolIndex, index+1) : iOpen(symbol, tf, index+1);
   double prevClose = useSmart ? GetClose(symbolIndex, index+1): iClose(symbol, tf, index+1);
   
   if(prevClose >= prevOpen) return false;
   if(currClose <= currOpen) return false;
   return (currClose > prevOpen && currOpen < prevClose);
}

//+------------------------------------------------------------------+
//| Check for Bearish Engulfing                                      |
//+------------------------------------------------------------------+
bool IsBearishEngulfing(int symbolIndex, ENUM_TIMEFRAMES tf, int index)
{
   bool useSmart = (tf == PERIOD_CURRENT);
   string symbol = SymbolData[symbolIndex].symbol;

   double currOpen  = useSmart ? GetOpen(symbolIndex, index)   : iOpen(symbol, tf, index);
   double currClose = useSmart ? GetClose(symbolIndex, index)  : iClose(symbol, tf, index);
   double prevOpen  = useSmart ? GetOpen(symbolIndex, index+1) : iOpen(symbol, tf, index+1);
   double prevClose = useSmart ? GetClose(symbolIndex, index+1): iClose(symbol, tf, index+1);
   
   if(prevClose <= prevOpen) return false;
   if(currClose >= currOpen) return false;
   return (currClose < prevOpen && currOpen > prevClose);
}

//+------------------------------------------------------------------+
//| DEBUG: Print Indicator Values                                    |
//+------------------------------------------------------------------+
void PrintDebugValues(int symbolIndex)
  {
   string symbol = SymbolData[symbolIndex].symbol;
   string debugOutput = symbol + " | ";

// 1. Check MAs for the enabled timeframes
// We loop through timeframes to see which ones are working
   for(int tf = 0; tf < 7; tf++)
     {
      if(!TimeframeEnabled[tf])
         continue;

      string tfName = EnumToString(Timeframes[tf]);
      debugOutput += tfName + ": [";

      // Loop through the 5 MAs
      for(int i = 0; i < 5; i++)
        {
         double buffer[];
         int handle = SymbolData[symbolIndex].MA_Handles[i][tf];

         if(handle == INVALID_HANDLE)
           {
            debugOutput += "InvH, "; // Invalid Handle
            continue;
           }

         // Try to copy the latest value (index 0)
         if(CopyBuffer(handle, 0, 0, 1, buffer) > 0)
           {
            debugOutput += "MA" + IntegerToString(i+1) + "=" + DoubleToString(buffer[0], _Digits) + ", ";
           }
         else
           {
            // This implies the indicator cannot calculate (likely no history for this TF)
            debugOutput += "EMPTY, ";
           }
        }
      debugOutput += "] ";
     }

// 2. Check ATR
   double atrBuf[];
   if(CopyBuffer(SymbolData[symbolIndex].ATR_Handle, 0, 0, 1, atrBuf) > 0)
     {
      debugOutput += "| ATR: " + DoubleToString(atrBuf[0], _Digits);
     }
   else
     {
      debugOutput += "| ATR: FAIL";
     }

   if(MBP_LogTierEnabled(MBP_LOG_TIER_DEBUG)) Print(debugOutput);
  }

//+------------------------------------------------------------------+
//| Currency Strength Co-Integration Matrix                          |
//+------------------------------------------------------------------+
string g_CacheStrengthPairs[];
int    g_CacheStrengthHandles[];

int GetCurrencyStrengthHandle(string activePair)
{
   for(int i = 0; i < ArraySize(g_CacheStrengthPairs); i++)
   {
      if(g_CacheStrengthPairs[i] == activePair)
         return g_CacheStrengthHandles[i];
   }

   int handle = iRSI(activePair, PERIOD_CURRENT, 14, PRICE_CLOSE);
   if(handle == INVALID_HANDLE)
      return INVALID_HANDLE;

   int s = ArraySize(g_CacheStrengthPairs);
   ArrayResize(g_CacheStrengthPairs, s + 1);
   ArrayResize(g_CacheStrengthHandles, s + 1);
   g_CacheStrengthPairs[s] = activePair;
   g_CacheStrengthHandles[s] = handle;
   return handle;
}

void ReleaseCurrencyStrengthHandles()
{
   for(int i = 0; i < ArraySize(g_CacheStrengthHandles); i++)
   {
      if(g_CacheStrengthHandles[i] != INVALID_HANDLE)
         IndicatorRelease(g_CacheStrengthHandles[i]);
   }
   ArrayResize(g_CacheStrengthPairs, 0);
   ArrayResize(g_CacheStrengthHandles, 0);
}

//+------------------------------------------------------------------+
//| Currency Strength Co-Integration Matrix (OPTIMIZED)              |
//+------------------------------------------------------------------+
double GetCurrencyStrength(string currency)
{
   // --- ADD THIS LINE TO ABORT ON METALS/CRYPTO ---
    if(!IsStandardFiat(currency)) return 50.0;
    
   string majors[8] = {"USD", "EUR", "GBP", "JPY", "AUD", "NZD", "CAD", "CHF"};
   
   // FOREX HIERARCHY: Mathematically prevents fake pairs like "USDEUR"
   string order[8]  = {"EUR", "GBP", "AUD", "NZD", "USD", "CAD", "CHF", "JPY"};
   
   double totalStrength = 0.0;
   int validPairs = 0;

   // Auto-Detect Broker Suffixes (e.g., "EURUSD.pro" -> ".pro")
   string suffix = "";
   if(StringLen(_Symbol) > 6)
   {
       suffix = StringSubstr(_Symbol, 6);
       // Ignore your custom Renko generator suffixes during extraction
       if(StringFind(suffix, "_ATR") >= 0 || StringFind(suffix, "Renko") >= 0) suffix = "";
   }

   for(int i = 0; i < 8; i++)
   {
      if(currency == majors[i]) continue;

      // Determine the correct standard pair order
      int rank1 = -1, rank2 = -1;
      for(int j=0; j<8; j++) {
         if(currency == order[j]) rank1 = j;
         if(majors[i] == order[j]) rank2 = j;
      }
      
      string activePair = "";
      bool inverted = false;
      
      // Build the string based on interbank hierarchy
      if(rank1 < rank2) { 
         activePair = currency + majors[i]; 
         inverted = false; 
      } else { 
         activePair = majors[i] + currency; 
         inverted = true; 
      }
      
      // Attach the broker's suffix
      string finalPair = activePair + suffix;

      // Select the symbol in the MarketWatch
      if(!SymbolSelect(finalPair, true)) 
      {
          // Fallback: If suffix fails, try the raw pair just in case
          if(SymbolSelect(activePair, true)) {
              finalPair = activePair;
          } else {
              continue; // Symbol truly doesn't exist on this broker
          }
      }

      int handle = GetCurrencyStrengthHandle(finalPair);
      if(handle == INVALID_HANDLE) continue;

      double rsi[1];
      if(CopyBuffer(handle, 0, 0, 1, rsi) > 0)
      {
         // If we are looking at the quote currency, invert the momentum
         double strength = inverted ? (100.0 - rsi[0]) : rsi[0];
         totalStrength += strength;
         validPairs++;
      }
   }

   // Return the average strength (Scale of 0 to 100)
   return (validPairs > 0) ? (totalStrength / validPairs) : 50.0;
}

void RefreshIndicator_MA1(int index)
{
   int activePeriod = GetActiveMAPeriod(index, 0);
   for(int tf = 0; tf < 7; tf++)
   {
       if(!TimeframeEnabled[tf]) continue;
       if(SymbolData[index].MA_Handles[0][tf] != INVALID_HANDLE)
          IndicatorRelease(SymbolData[index].MA_Handles[0][tf]);
          
       // FIXED: Replaced MODE_SMA with GetMAMethod(MA1_Method)
       SymbolData[index].MA_Handles[0][tf] = iMA(SymbolData[index].symbol, Timeframes[tf], activePeriod, 0, GetMAMethod(MA1_Method), GetMASource(MA1_Source));
   }
}

void RefreshIndicator_MA2(int index)
{
   int activePeriod = GetActiveMAPeriod(index, 1);
   for(int tf = 0; tf < 7; tf++)
   {
       if(!TimeframeEnabled[tf]) continue;
       if(SymbolData[index].MA_Handles[1][tf] != INVALID_HANDLE)
          IndicatorRelease(SymbolData[index].MA_Handles[1][tf]);
          
       // FIXED: Replaced MODE_SMA with GetMAMethod(MA2_Method)
       SymbolData[index].MA_Handles[1][tf] = iMA(SymbolData[index].symbol, Timeframes[tf], activePeriod, 0, GetMAMethod(MA2_Method), GetMASource(MA2_Source));
   }
}

void RefreshIndicator_ADX(int index)
{
   if(SymbolData[index].ADX_Handle != INVALID_HANDLE)
      IndicatorRelease(SymbolData[index].ADX_Handle);
      
   int activePeriod = (InpEnableShadowMaster && SymbolData[index].Dyn_ADX_Period > 0) ? SymbolData[index].Dyn_ADX_Period : ((G_ADX_Period > 0) ? G_ADX_Period : 14);
      
   SymbolData[index].ADX_Handle = iADX(SymbolData[index].symbol, PERIOD_CURRENT, activePeriod);
}

//+------------------------------------------------------------------+
//| Check if currency is standard fiat                               |
//+------------------------------------------------------------------+
bool IsStandardFiat(string curr)
{
    if(curr == "USD" || curr == "EUR" || curr == "GBP" || curr == "JPY" || 
       curr == "AUD" || curr == "NZD" || curr == "CAD" || curr == "CHF") return true;
    return false;
}

//+------------------------------------------------------------------+

#endif // __MULTIBOTPRO_INDICATORS_MQH__


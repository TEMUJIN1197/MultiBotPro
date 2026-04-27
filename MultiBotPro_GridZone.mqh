#ifndef __MULTIBOTPRO_GRIDZONE_MQH__
#define __MULTIBOTPRO_GRIDZONE_MQH__
//+------------------------------------------------------------------+
//|                                         MultiBotPro_GridZone.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://discord.com/channels/929723953415589918/929723953415589920"

// 1. Define a global or static variable for safety
static ulong LastTradeAttemptTime = 0;

struct SBridgeChannelLock
{
   long     requestId;
   datetime expiresAt;
};

string MBP_BasketRuntimeLegacyStateFileName(const int symbolIndex)
{
   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return "";

   string baseSymbol = GetBaseSymbol(SymbolData[symbolIndex].symbol);
   if(baseSymbol == "")
      baseSymbol = SymbolData[symbolIndex].symbol;
   if(baseSymbol == "")
      baseSymbol = _Symbol;

   return StringFormat("MBP_BasketState_%s_%d_%s_B%d.txt",
                       MBP_SanitizeRuntimeToken(MBP_GetActiveCoordinatorKey()),
                       MagicNumber,
                       MBP_SanitizeRuntimeToken(baseSymbol),
                       SymbolData[symbolIndex].BasketId);
}

string MBP_BasketRuntimeStateFileName(const int symbolIndex)
{
   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return "";

   string baseSymbol = GetBaseSymbol(SymbolData[symbolIndex].symbol);
   if(baseSymbol == "")
      baseSymbol = SymbolData[symbolIndex].symbol;
   if(baseSymbol == "")
      baseSymbol = _Symbol;

   string coordinatorKey = MBP_GetActiveCoordinatorKey();
   string slotScope = "COORD";
   if(IsParallelWorkerMode() && G_RuntimeAssignedSlotId >= 0)
      slotScope = "S" + IntegerToString(G_RuntimeAssignedSlotId);
   else if(IsParallelLegacyMode())
      slotScope = "LEGACY";

   return StringFormat("MBP_BasketState_%s_%s_%s_%d_%s_B%d.txt",
                       MBP_SanitizeRuntimeToken(InpHedgeChannel),
                       MBP_SanitizeRuntimeToken(coordinatorKey),
                       MBP_SanitizeRuntimeToken(slotScope),
                       MagicNumber,
                       MBP_SanitizeRuntimeToken(baseSymbol),
                       SymbolData[symbolIndex].BasketId);
}

string MBP_StateReadKeyValue(const string payload, const string key, const string fallback = "")
{
   string needle = key + "=";
   int start = StringFind(payload, needle);
   if(start < 0)
      return fallback;

   start += StringLen(needle);
   int end = StringFind(payload, "\n", start);
   if(end < 0)
      end = StringLen(payload);

   string value = StringSubstr(payload, start, end - start);
   StringReplace(value, "\r", "");
   return value;
}

double MBP_StateReadDouble(const string payload, const string key, const double fallback = 0.0)
{
   string value = MBP_StateReadKeyValue(payload, key, "");
   if(value == "")
      return fallback;
   return StringToDouble(value);
}

int MBP_StateReadInteger(const string payload, const string key, const int fallback = 0)
{
   string value = MBP_StateReadKeyValue(payload, key, "");
   if(value == "")
      return fallback;
   return (int)StringToInteger(value);
}

bool MBP_StateReadBool(const string payload, const string key, const bool fallback = false)
{
   string value = MBP_StateReadKeyValue(payload, key, "");
   if(value == "")
      return fallback;
   return (StringToInteger(value) != 0);
}

bool MBP_IsBasketRuntimePosition(const int symbolIndex, const string positionSymbol, const string comment)
{
   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return false;

   string trackingSymbol = GetBaseSymbol(SymbolData[symbolIndex].symbol);
   if(trackingSymbol == "")
      trackingSymbol = SymbolData[symbolIndex].symbol;

   if(StringCompare(positionSymbol, trackingSymbol, false) != 0)
      return false;
   if(InpEnableMultiBaskets && !IsPositionInBasket(symbolIndex, comment))
      return false;

   return (StringFind(comment, "Grid") >= 0 ||
           StringFind(comment, "Zone") >= 0 ||
           StringFind(comment, "Stack") >= 0);
}

bool BasketRuntimeHasLivePositions(const int symbolIndex)
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(!IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
         continue;

      if(MBP_IsBasketRuntimePosition(symbolIndex,
                                     PositionGetString(POSITION_SYMBOL),
                                     PositionGetString(POSITION_COMMENT)))
         return true;
   }

   return false;
}

void ClearBasketRuntimeState(const int symbolIndex)
{
   string stateFile = MBP_BasketRuntimeStateFileName(symbolIndex);
   if(stateFile != "" && FileIsExist(stateFile, FILE_COMMON))
      FileDelete(stateFile, FILE_COMMON);
}

bool SaveBasketRuntimeState(const int symbolIndex)
{
   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return false;
   if(!SymbolData[symbolIndex].active)
      return false;
   if(RiskMode != RISK_MODE_GRID && RiskMode != RISK_MODE_ZONE_RECOVERY)
   {
      ClearBasketRuntimeState(symbolIndex);
      return true;
   }
   if(!BasketRuntimeHasLivePositions(symbolIndex))
   {
      ClearBasketRuntimeState(symbolIndex);
      return true;
   }

   string stateFile = MBP_BasketRuntimeStateFileName(symbolIndex);
   if(stateFile == "")
      return false;

   int handle = FileOpen(stateFile, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(handle == INVALID_HANDLE)
   {
      Print(EmojiWarning(), " Failed to save basket runtime state for ", SymbolData[symbolIndex].symbol,
            ". Error=", GetLastError());
      return false;
   }

   FileWriteString(handle, "version=1\r\n");
   FileWriteString(handle, "updated_at=" + IntegerToString((int)TimeCurrent()) + "\r\n");
   FileWriteString(handle, "risk_mode=" + IntegerToString((int)RiskMode) + "\r\n");
   FileWriteString(handle, "basket_id=" + IntegerToString(SymbolData[symbolIndex].BasketId) + "\r\n");
   FileWriteString(handle, "last_grid_reset=" + IntegerToString((int)SymbolData[symbolIndex].LastGridReset) + "\r\n");
   FileWriteString(handle, "basket_active=" + IntegerToString(SymbolData[symbolIndex].BasketActive ? 1 : 0) + "\r\n");
   FileWriteString(handle, "basket_initial_entry=" + DoubleToString(SymbolData[symbolIndex].BasketInitialEntry, 16) + "\r\n");
   FileWriteString(handle, "basket_direction=" + IntegerToString((int)SymbolData[symbolIndex].BasketDirection) + "\r\n");
   FileWriteString(handle, "grid_levels=" + IntegerToString(SymbolData[symbolIndex].GridLevels) + "\r\n");
   FileWriteString(handle, "grid_phase1=" + IntegerToString(SymbolData[symbolIndex].GridPhase1Active ? 1 : 0) + "\r\n");
   FileWriteString(handle, "grid_phase2=" + IntegerToString(SymbolData[symbolIndex].GridPhase2Active ? 1 : 0) + "\r\n");
   FileWriteString(handle, "grid_target_reached=" + IntegerToString(SymbolData[symbolIndex].GridTargetReached ? 1 : 0) + "\r\n");
   FileWriteString(handle, "grid_in_trailing=" + IntegerToString(SymbolData[symbolIndex].GridInTrailing ? 1 : 0) + "\r\n");
   FileWriteString(handle, "grid_in_stacking=" + IntegerToString(SymbolData[symbolIndex].GridInStacking ? 1 : 0) + "\r\n");
   FileWriteString(handle, "grid_basket_sl=" + DoubleToString(SymbolData[symbolIndex].GridBasketStopLoss, 16) + "\r\n");
   FileWriteString(handle, "grid_basket_tp=" + DoubleToString(SymbolData[symbolIndex].GridBasketTakeProfit, 16) + "\r\n");
   FileWriteString(handle, "grid_basket_entry=" + DoubleToString(SymbolData[symbolIndex].GridBasketEntry, 16) + "\r\n");
   FileWriteString(handle, "grid_basket_volume=" + DoubleToString(SymbolData[symbolIndex].GridBasketVolume, 16) + "\r\n");
   FileWriteString(handle, "grid_target_profit=" + DoubleToString(SymbolData[symbolIndex].GridTargetProfit, 16) + "\r\n");
   FileWriteString(handle, "raw_next_grid_lot=" + DoubleToString(SymbolData[symbolIndex].RawNextGridLot, 16) + "\r\n");
   FileWriteString(handle, "last_used_grid_raw_lot=" + DoubleToString(SymbolData[symbolIndex].LastUsedGridRawLot, 16) + "\r\n");
   FileWriteString(handle, "raw_next_stack_lot=" + DoubleToString(SymbolData[symbolIndex].RawNextStackLot, 16) + "\r\n");
   FileWriteString(handle, "last_used_stack_raw_lot=" + DoubleToString(SymbolData[symbolIndex].LastUsedStackRawLot, 16) + "\r\n");
   FileWriteString(handle, "grid_tp_hit=" + IntegerToString(SymbolData[symbolIndex].GridTPHit ? 1 : 0) + "\r\n");
   FileWriteString(handle, "grid_tp_hit_price=" + DoubleToString(SymbolData[symbolIndex].GridTPHitPrice, 16) + "\r\n");
   FileWriteString(handle, "grid_sequence_depth=" + IntegerToString(SymbolData[symbolIndex].GridSequenceDepth) + "\r\n");
   FileWriteString(handle, "zone_active=" + IntegerToString(SymbolData[symbolIndex].ZoneActive ? 1 : 0) + "\r\n");
   FileWriteString(handle, "zone_top=" + DoubleToString(SymbolData[symbolIndex].ZoneTopPrice, 16) + "\r\n");
   FileWriteString(handle, "zone_bottom=" + DoubleToString(SymbolData[symbolIndex].ZoneBottomPrice, 16) + "\r\n");
   FileWriteString(handle, "zone_seq_count=" + IntegerToString(SymbolData[symbolIndex].ZoneSeqCount) + "\r\n");
   FileWriteString(handle, "zone_resolved=" + IntegerToString(SymbolData[symbolIndex].ZoneResolved ? 1 : 0) + "\r\n");
   FileWriteString(handle, "current_recovery_portion=" + DoubleToString(SymbolData[symbolIndex].CurrentRecoveryPortion, 16) + "\r\n");
   FileWriteString(handle, "pruning_occurred=" + IntegerToString(SymbolData[symbolIndex].PruningOccurredThisSequence ? 1 : 0) + "\r\n");
   FileWriteString(handle, "recovery_iteration=" + IntegerToString((int)MathMax(1, SymbolData[symbolIndex].RecoveryIteration)) + "\r\n");
   FileClose(handle);

   return true;
}

bool RebuildBasketRuntimeStateFromOpenPositions(const int symbolIndex, const bool persistAfter = true)
{
   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return false;
   if(RiskMode != RISK_MODE_GRID && RiskMode != RISK_MODE_ZONE_RECOVERY)
      return false;

   string trackingSymbol = GetBaseSymbol(SymbolData[symbolIndex].symbol);
   if(trackingSymbol == "")
      trackingSymbol = SymbolData[symbolIndex].symbol;

   int liveCount = 0;
   int logicCount = 0;
   double totalVolume = 0.0;
   double totalValue = 0.0;
   double firstNonZeroSL = 0.0;
   double firstNonZeroTP = 0.0;
   double minEntry = 0.0;
   double maxEntry = 0.0;
   bool haveEntry = false;
   datetime oldestTime = 0;
   double oldestEntry = 0.0;
   ENUM_POSITION_TYPE oldestType = POSITION_TYPE_BUY;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(!IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
         continue;

      string comment = PositionGetString(POSITION_COMMENT);
      if(!MBP_IsBasketRuntimePosition(symbolIndex, PositionGetString(POSITION_SYMBOL), comment))
         continue;

      bool isStack = (StringFind(comment, "Stack") >= 0);
      bool isGrid = (StringFind(comment, "Grid") >= 0);
      bool isZone = (StringFind(comment, "Zone") >= 0);
      if(!isGrid && !isZone && !isStack)
         continue;

      double volume = PositionGetDouble(POSITION_VOLUME);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);

      liveCount++;
      totalVolume += volume;
      totalValue += volume * entry;
      if((isGrid || isZone) && !isStack)
         logicCount++;
      if(firstNonZeroSL <= 0.0 && sl > 0.0)
         firstNonZeroSL = sl;
      if(firstNonZeroTP <= 0.0 && tp > 0.0)
         firstNonZeroTP = tp;

      if(!haveEntry)
      {
         minEntry = entry;
         maxEntry = entry;
         haveEntry = true;
      }
      else
      {
         if(entry < minEntry)
            minEntry = entry;
         if(entry > maxEntry)
            maxEntry = entry;
      }

      if(oldestTime == 0 || openTime < oldestTime)
      {
         oldestTime = openTime;
         oldestEntry = entry;
         oldestType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      }
   }

   if(liveCount <= 0 || totalVolume <= 0.0)
   {
      ClearBasketRuntimeState(symbolIndex);
      return false;
   }

   if(logicCount <= 0)
      logicCount = liveCount;

   SymbolData[symbolIndex].BasketActive = true;
   if(SymbolData[symbolIndex].BasketInitialEntry <= 0.0)
      SymbolData[symbolIndex].BasketInitialEntry = oldestEntry;
   SymbolData[symbolIndex].BasketDirection = oldestType;
   SymbolData[symbolIndex].GridBasketEntry = totalValue / totalVolume;
   SymbolData[symbolIndex].GridBasketVolume = totalVolume;
   SymbolData[symbolIndex].GridBasketTakeProfit = firstNonZeroTP;
   SymbolData[symbolIndex].GridBasketStopLoss = firstNonZeroSL;
   SymbolData[symbolIndex].GridLevels = logicCount;
   SymbolData[symbolIndex].GridSequenceDepth = (int)MathMax(SymbolData[symbolIndex].GridSequenceDepth, logicCount);

   bool phase2 = (firstNonZeroSL > 0.0);
   SymbolData[symbolIndex].GridTargetReached = phase2;
   SymbolData[symbolIndex].GridPhase2Active = phase2;
   SymbolData[symbolIndex].GridPhase1Active = !phase2;
   SymbolData[symbolIndex].GridInTrailing = (phase2 && UseTrailing);
   SymbolData[symbolIndex].GridInStacking = (phase2 && UseTrailing && StackMode);
   if(phase2)
   {
      SymbolData[symbolIndex].GridTPHit = true;
      SymbolData[symbolIndex].GridTPHitPrice = firstNonZeroSL;
      SymbolData[symbolIndex].PreviousBasketSL = firstNonZeroSL;
   }

   if(RiskMode == RISK_MODE_ZONE_RECOVERY)
   {
      SymbolData[symbolIndex].ZoneActive = !phase2;
      SymbolData[symbolIndex].ZoneSeqCount = (int)MathMax(1, logicCount);
      if(SymbolData[symbolIndex].ZoneTopPrice <= 0.0 || SymbolData[symbolIndex].ZoneBottomPrice <= 0.0)
      {
         if(haveEntry && maxEntry > minEntry)
         {
            SymbolData[symbolIndex].ZoneTopPrice = maxEntry;
            SymbolData[symbolIndex].ZoneBottomPrice = minEntry;
         }
         else
         {
            double point = SymbolInfoDouble(trackingSymbol, SYMBOL_POINT);
            double gapSize = ZoneGapPoints * point;
            if(ZoneGapType == ZONE_GAP_ATR)
            {
               double atr[1];
               if(CopyBuffer(SymbolData[symbolIndex].ATR_Handle, 0, 0, 1, atr) > 0 && atr[0] > 0.0)
                  gapSize = atr[0] * ZoneGapATR;
            }
            if(gapSize <= 0.0)
               gapSize = 50.0 * point;

            if(oldestType == POSITION_TYPE_BUY)
            {
               SymbolData[symbolIndex].ZoneTopPrice = oldestEntry;
               SymbolData[symbolIndex].ZoneBottomPrice = oldestEntry - gapSize;
            }
            else
            {
               SymbolData[symbolIndex].ZoneBottomPrice = oldestEntry;
               SymbolData[symbolIndex].ZoneTopPrice = oldestEntry + gapSize;
            }
         }
      }
   }
   else
   {
      SymbolData[symbolIndex].ZoneActive = false;
      SymbolData[symbolIndex].ZoneSeqCount = 0;
   }

   if(SymbolData[symbolIndex].GridTargetProfit <= 0.0)
      SymbolData[symbolIndex].GridTargetProfit = GetDynamicProfitTarget(symbolIndex);
   if(SymbolData[symbolIndex].RecoveryIteration < 1)
      SymbolData[symbolIndex].RecoveryIteration = 1;

   Print(trackingSymbol, " Rebuilt basket runtime state from ", liveCount,
         " live positions. Phase2=", (phase2 ? "true" : "false"),
         " BasketSL=", DoubleToString(SymbolData[symbolIndex].GridBasketStopLoss,
                                      (int)SymbolInfoInteger(trackingSymbol, SYMBOL_DIGITS)));

   if(persistAfter)
      SaveBasketRuntimeState(symbolIndex);

   return true;
}

bool LoadBasketRuntimeState(const int symbolIndex)
{
   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return false;
   if(!SymbolData[symbolIndex].active)
      return false;
   if(RiskMode != RISK_MODE_GRID && RiskMode != RISK_MODE_ZONE_RECOVERY)
      return false;

   bool hasLivePositions = BasketRuntimeHasLivePositions(symbolIndex);
   if(!hasLivePositions)
   {
      ClearBasketRuntimeState(symbolIndex);
      return false;
   }

   string stateFile = MBP_BasketRuntimeStateFileName(symbolIndex);
   bool loadedLegacyState = false;
   if(stateFile == "" || !FileIsExist(stateFile, FILE_COMMON))
   {
      string legacyStateFile = MBP_BasketRuntimeLegacyStateFileName(symbolIndex);
      if(legacyStateFile == "" || !FileIsExist(legacyStateFile, FILE_COMMON))
         return RebuildBasketRuntimeStateFromOpenPositions(symbolIndex, true);

      stateFile = legacyStateFile;
      loadedLegacyState = true;
   }

   int handle = FileOpen(stateFile, FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(handle == INVALID_HANDLE)
      return RebuildBasketRuntimeStateFromOpenPositions(symbolIndex, true);

   string payload = "";
   while(!FileIsEnding(handle))
      payload += FileReadString(handle) + "\n";
   FileClose(handle);

   if(payload == "")
      return RebuildBasketRuntimeStateFromOpenPositions(symbolIndex, true);

   int savedRiskMode = MBP_StateReadInteger(payload, "risk_mode", -1);
   if(savedRiskMode != (int)RiskMode)
      return RebuildBasketRuntimeStateFromOpenPositions(symbolIndex, true);

   SymbolData[symbolIndex].BasketActive = MBP_StateReadBool(payload, "basket_active", true);
   SymbolData[symbolIndex].BasketInitialEntry = MBP_StateReadDouble(payload, "basket_initial_entry", SymbolData[symbolIndex].BasketInitialEntry);
   SymbolData[symbolIndex].BasketDirection = (ENUM_POSITION_TYPE)MBP_StateReadInteger(payload, "basket_direction", (int)SymbolData[symbolIndex].BasketDirection);
   SymbolData[symbolIndex].LastGridReset = (datetime)MBP_StateReadInteger(payload, "last_grid_reset", (int)SymbolData[symbolIndex].LastGridReset);
   SymbolData[symbolIndex].GridLevels = (int)MathMax(0, MBP_StateReadInteger(payload, "grid_levels", SymbolData[symbolIndex].GridLevels));
   SymbolData[symbolIndex].GridPhase1Active = MBP_StateReadBool(payload, "grid_phase1", SymbolData[symbolIndex].GridPhase1Active);
   SymbolData[symbolIndex].GridPhase2Active = MBP_StateReadBool(payload, "grid_phase2", SymbolData[symbolIndex].GridPhase2Active);
   SymbolData[symbolIndex].GridTargetReached = MBP_StateReadBool(payload, "grid_target_reached", SymbolData[symbolIndex].GridTargetReached);
   SymbolData[symbolIndex].GridInTrailing = MBP_StateReadBool(payload, "grid_in_trailing", SymbolData[symbolIndex].GridInTrailing);
   SymbolData[symbolIndex].GridInStacking = MBP_StateReadBool(payload, "grid_in_stacking", SymbolData[symbolIndex].GridInStacking);
   SymbolData[symbolIndex].GridBasketStopLoss = MBP_StateReadDouble(payload, "grid_basket_sl", SymbolData[symbolIndex].GridBasketStopLoss);
   SymbolData[symbolIndex].GridBasketTakeProfit = MBP_StateReadDouble(payload, "grid_basket_tp", SymbolData[symbolIndex].GridBasketTakeProfit);
   SymbolData[symbolIndex].GridBasketEntry = MBP_StateReadDouble(payload, "grid_basket_entry", SymbolData[symbolIndex].GridBasketEntry);
   SymbolData[symbolIndex].GridBasketVolume = MBP_StateReadDouble(payload, "grid_basket_volume", SymbolData[symbolIndex].GridBasketVolume);
   SymbolData[symbolIndex].GridTargetProfit = MBP_StateReadDouble(payload, "grid_target_profit", SymbolData[symbolIndex].GridTargetProfit);
   SymbolData[symbolIndex].RawNextGridLot = MBP_StateReadDouble(payload, "raw_next_grid_lot", SymbolData[symbolIndex].RawNextGridLot);
   SymbolData[symbolIndex].LastUsedGridRawLot = MBP_StateReadDouble(payload, "last_used_grid_raw_lot", SymbolData[symbolIndex].LastUsedGridRawLot);
   SymbolData[symbolIndex].RawNextStackLot = MBP_StateReadDouble(payload, "raw_next_stack_lot", SymbolData[symbolIndex].RawNextStackLot);
   SymbolData[symbolIndex].LastUsedStackRawLot = MBP_StateReadDouble(payload, "last_used_stack_raw_lot", SymbolData[symbolIndex].LastUsedStackRawLot);
   SymbolData[symbolIndex].GridTPHit = MBP_StateReadBool(payload, "grid_tp_hit", SymbolData[symbolIndex].GridTPHit);
   SymbolData[symbolIndex].GridTPHitPrice = MBP_StateReadDouble(payload, "grid_tp_hit_price", SymbolData[symbolIndex].GridTPHitPrice);
   SymbolData[symbolIndex].GridSequenceDepth = (int)MathMax(SymbolData[symbolIndex].GridLevels, MBP_StateReadInteger(payload, "grid_sequence_depth", SymbolData[symbolIndex].GridSequenceDepth));
   SymbolData[symbolIndex].ZoneActive = MBP_StateReadBool(payload, "zone_active", SymbolData[symbolIndex].ZoneActive);
   SymbolData[symbolIndex].ZoneTopPrice = MBP_StateReadDouble(payload, "zone_top", SymbolData[symbolIndex].ZoneTopPrice);
   SymbolData[symbolIndex].ZoneBottomPrice = MBP_StateReadDouble(payload, "zone_bottom", SymbolData[symbolIndex].ZoneBottomPrice);
   SymbolData[symbolIndex].ZoneSeqCount = (int)MathMax(0, MBP_StateReadInteger(payload, "zone_seq_count", SymbolData[symbolIndex].ZoneSeqCount));
   SymbolData[symbolIndex].ZoneResolved = MBP_StateReadBool(payload, "zone_resolved", SymbolData[symbolIndex].ZoneResolved);
   SymbolData[symbolIndex].CurrentRecoveryPortion = MBP_StateReadDouble(payload, "current_recovery_portion", SymbolData[symbolIndex].CurrentRecoveryPortion);
   SymbolData[symbolIndex].PruningOccurredThisSequence = MBP_StateReadBool(payload, "pruning_occurred", SymbolData[symbolIndex].PruningOccurredThisSequence);
   SymbolData[symbolIndex].RecoveryIteration = (int)MathMax(1, MBP_StateReadInteger(payload, "recovery_iteration", SymbolData[symbolIndex].RecoveryIteration));

   CalculateGridBasket(symbolIndex);
   if(SymbolData[symbolIndex].GridTargetProfit <= 0.0)
      SymbolData[symbolIndex].GridTargetProfit = GetDynamicProfitTarget(symbolIndex);
   if(SymbolData[symbolIndex].GridPhase2Active && SymbolData[symbolIndex].GridBasketStopLoss <= 0.0)
      return RebuildBasketRuntimeStateFromOpenPositions(symbolIndex, true);

   string trackingSymbol = GetBaseSymbol(SymbolData[symbolIndex].symbol);
   if(trackingSymbol == "")
      trackingSymbol = SymbolData[symbolIndex].symbol;
   Print(trackingSymbol, " Loaded basket runtime state. Phase1=",
         (SymbolData[symbolIndex].GridPhase1Active ? "true" : "false"),
         " Phase2=", (SymbolData[symbolIndex].GridPhase2Active ? "true" : "false"),
         " TargetHit=", (SymbolData[symbolIndex].GridTPHit ? "true" : "false"));

   if(loadedLegacyState)
      SaveBasketRuntimeState(symbolIndex);

   return true;
}

//+------------------------------------------------------------------+
//| Manage all positions on tick - FIXED (Delayed Trail Integration) |
//+------------------------------------------------------------------+
void ManageAllPositionsOnTick(int symbolIndex)
  {
// 1. Define Context
   string analysisSymbol = SymbolData[symbolIndex].symbol;
   string trackingSymbol = GetBaseSymbol(analysisSymbol);
   bool filterByBasket = InpEnableMultiBaskets;

// =============================================================================
// BRANCH A: GRID OR ZONE RECOVERY MODE
// =============================================================================
   if(RiskMode == RISK_MODE_GRID || RiskMode == RISK_MODE_ZONE_RECOVERY)
     {
      if(SymbolData[symbolIndex].GridPhase2Active)
        {
         ManageGridPhase2(symbolIndex);
         return;
        }
      else
         if(RiskMode == RISK_MODE_GRID && SymbolData[symbolIndex].GridTargetReached)
           {
            TransitionToGridPhase2(symbolIndex);
            return;
           }
     }

// =============================================================================
// BRANCH B: NORMAL MODE (Standard SL/TP & Trailing)
// =============================================================================
   if(RiskMode == RISK_MODE_NONE)
     {
      ulong masterTicket = SymbolData[symbolIndex].MasterTicket;
      bool hasMaster = (masterTicket != 0 && PositionSelectByTicket(masterTicket));

      // 1. Find Master if missing (Recovery check)
      if(!hasMaster)
        {
         for(int i = 0; i < PositionsTotal(); i++)
           {
            ulong ticket = PositionGetTicket(i);
            if(PositionSelectByTicket(ticket))
              {
               if(PositionGetString(POSITION_SYMBOL) == trackingSymbol &&
                  IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
                 {
         string comment = PositionGetString(POSITION_COMMENT);
         if(filterByBasket && !IsPositionInBasket(symbolIndex, comment))
            continue;
                  if(StringFind(comment, "Stack") < 0)
                    {
                     SymbolData[symbolIndex].MasterTicket = ticket;
                     masterTicket = ticket;
                     hasMaster = true;

                     SymbolData[symbolIndex].MasterSL = PositionGetDouble(POSITION_SL);
                     SymbolData[symbolIndex].MasterEntry = PositionGetDouble(POSITION_PRICE_OPEN);
                     SymbolData[symbolIndex].MasterType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                     SymbolData[symbolIndex].MasterHasValidSL = (SymbolData[symbolIndex].MasterSL != 0);
                     break;
                    }
                 }
              }
           }
        }

      if(hasMaster)
        {
         // 2. CHECK TP / TRAILING ACTIVATION
         // We use the "InitialTP" stored in SymbolData
         
         double targetPrice = SymbolData[symbolIndex].InitialTP;
         
         // A. IF TRAILING IS ENABLED: Use Delayed Trail Logic
         if(UseTrailing)
           {
            // The logic for waiting and activating is entirely inside ManageTrailingStop
            ManageTrailingStop(symbolIndex);
           }
         // B. IF TRAILING IS DISABLED: Use TP as Hard Close (Hidden TP)
         else
           {
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            ENUM_POSITION_TYPE type = SymbolData[symbolIndex].MasterType;
            bool tpReached = false;

            if(targetPrice > 0)
              {
               if(type == POSITION_TYPE_BUY && currentPrice >= targetPrice)
                  tpReached = true;
               if(type == POSITION_TYPE_SELL && currentPrice <= targetPrice)
                  tpReached = true;
              }

            if(tpReached)
              {
               if(HideSLTPDuringCloseBlock && G_Cache_IsDailyCloseBlock) 
                 { /* Block closure */ }
               else if(CheckSpread(symbolIndex))
                 {
                  ClosePosition(symbolIndex, masterTicket, "Take Profit Hit (Manual Monitor)");
                 }
              }
           }
        }
     }
  }

void ResetBridgePendingRequest()
{
   if(G_BridgePending.requestId != 0)
      ReleaseBridgeChannelLock(InpHedgeChannel, G_BridgePending.requestId);

   G_BridgePending.active = false;
   G_BridgePending.approved = false;
   G_BridgePending.symbolIndex = -1;
   G_BridgePending.orderType = ORDER_TYPE_BUY;
   G_BridgePending.totalLot = 0.0;
   G_BridgePending.createdAt = 0;
   G_BridgePending.expiresAt = 0;
   G_BridgePending.approvedAt = 0;
   G_BridgePending.lastExecAttemptMs = 0;
   G_BridgePending.executionAttempts = 0;
   G_BridgePending.proposalFile = "";
   G_BridgePending.replyFile = "";
   G_BridgePending.requestId = 0;
}

string GetBridgeChannelLockFile(const string channel)
{
   return StringFormat("HedgeBridgePending_%s.bin", channel);
}

int GetBridgeChannelLockTimeoutSec()
{
   int handshakeTimeoutMs = (InpV3_HandshakeTimeoutMs > 0) ? InpV3_HandshakeTimeoutMs : 3000;
   int handshakeTimeoutSec = (int)MathMax(1, MathCeil((double)handshakeTimeoutMs / 1000.0));
   int execTimeoutSec = (InpV3_AsyncExecTimeoutSec > 0) ? InpV3_AsyncExecTimeoutSec : 5;
   return (int)MathMax(5, handshakeTimeoutSec + execTimeoutSec + 2);
}

bool ReadBridgeChannelLock(const string channel, SBridgeChannelLock &lockState)
{
   ZeroMemory(lockState);

   string lockFile = GetBridgeChannelLockFile(channel);
   if(!FileIsExist(lockFile, FILE_COMMON))
      return false;

   int h = FileOpen(lockFile, FILE_READ|FILE_BIN|FILE_COMMON);
   if(h == INVALID_HANDLE)
      return false;

   bool ok = FileReadStruct(h, lockState);
   FileClose(h);

   if(!ok)
   {
      FileDelete(lockFile, FILE_COMMON);
      ZeroMemory(lockState);
      return false;
   }

   return true;
}

bool IsBridgeChannelLockActive(const string channel, long &requestId, datetime &expiresAt)
{
   requestId = 0;
   expiresAt = 0;

   SBridgeChannelLock lockState;
   if(!ReadBridgeChannelLock(channel, lockState))
      return false;

   if(lockState.requestId == 0 || lockState.expiresAt <= TimeCurrent())
   {
      FileDelete(GetBridgeChannelLockFile(channel), FILE_COMMON);
      return false;
   }

   requestId = lockState.requestId;
   expiresAt = lockState.expiresAt;
   return true;
}

bool TryAcquireBridgeChannelLock(const string channel, const long requestId)
{
   long activeRequestId = 0;
   datetime activeUntil = 0;
   if(IsBridgeChannelLockActive(channel, activeRequestId, activeUntil) && activeRequestId != requestId)
      return false;

   string lockFile = GetBridgeChannelLockFile(channel);
   int h = FileOpen(lockFile, FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(h == INVALID_HANDLE)
      return false;

   SBridgeChannelLock lockState;
   lockState.requestId = requestId;
   lockState.expiresAt = TimeCurrent() + GetBridgeChannelLockTimeoutSec();

   bool ok = FileWriteStruct(h, lockState);
   FileClose(h);

   if(!ok)
   {
      FileDelete(lockFile, FILE_COMMON);
      return false;
   }

   return true;
}

void ReleaseBridgeChannelLock(const string channel, const long requestId)
{
   string lockFile = GetBridgeChannelLockFile(channel);
   if(!FileIsExist(lockFile, FILE_COMMON))
      return;

   if(requestId != 0)
   {
      SBridgeChannelLock lockState;
      if(ReadBridgeChannelLock(channel, lockState) && lockState.requestId != 0 && lockState.requestId != requestId)
         return;
   }

   FileDelete(lockFile, FILE_COMMON);
}

long BuildUniqueBridgeRequestId(const int symbolIndex)
{
   ulong tickPart = GetTickCount64();
   ulong chartPart = ((ulong)ChartID()) % 65536;
   ulong symbolPart = ((ulong)MathMax(0, symbolIndex)) % 256;
   ulong requestId = (tickPart * 100000) + (chartPart * 256) + symbolPart;
   return (long)requestId;
}

double ComputeBridgeRiskMoneyFromStop(string execSymbol, ENUM_ORDER_TYPE orderType, double entryPrice, double stopPrice, double totalLot)
{
   if(stopPrice <= 0.0 || totalLot <= 0.0)
      return 0.0;

   double dist = MathAbs(entryPrice - stopPrice);
   if(dist <= 0.0)
      return 0.0;

   SymbolSelect(execSymbol, true);

   double orderCalcProfit = 0.0;
   if(OrderCalcProfit(orderType, execSymbol, totalLot, entryPrice, stopPrice, orderCalcProfit))
   {
      double derivedRisk = MathAbs(orderCalcProfit);
      if(derivedRisk > 0.0)
         return derivedRisk;
   }

   double tickVal = SymbolInfoDouble(execSymbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(execSymbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0.0 || tickVal <= 0.0)
      return 0.0;

   return totalLot * (dist / tickSize) * tickVal;
}

bool IsBridgeAdverseStopLevel(ENUM_ORDER_TYPE orderType, double entryPrice, double stopPrice)
{
   if(entryPrice <= 0.0 || stopPrice <= 0.0)
      return false;

   double tolerance = MathMax(MathAbs(entryPrice) * 1.0e-10, 0.0000001);

   if(orderType == ORDER_TYPE_BUY)
      return (stopPrice + tolerance) < entryPrice;

   return (stopPrice - tolerance) > entryPrice;
}

double ComputeBridgeGridDistance(const int symbolIndex, const string execSymbol, const int gridCountAfterEntry)
{
   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return 0.0;

   double point = SymbolInfoDouble(execSymbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = 1.0;

   double currentGridDist = 0.0;
   if(GridDistanceType == GRID_DIST_POINTS)
   {
      currentGridDist = GridDistance * point;
   }
   else
   {
      double atr[1];
      if(CopyBuffer(SymbolData[symbolIndex].ATR_Handle, 0, 1, 1, atr) > 0)
         currentGridDist = atr[0] * GridDistance;
      else
         currentGridDist = MinGridDistance * point;
   }

   bool aiActive = false;
   if(InpEnableShadowMaster && SymbolData[symbolIndex].LastShadowUpdate > 0 &&
      (TimeCurrent() - SymbolData[symbolIndex].LastShadowUpdate < 172800))
   {
      if(SymbolData[symbolIndex].Dyn_GridMultiplier > 0)
         aiActive = true;
   }

   double activeGridMult = aiActive ? SymbolData[symbolIndex].Dyn_GridMultiplier : GridMultiplier;
   if(activeGridMult == 0.0)
      return 0.0;

   if(GridDistanceStartLevel >= 0 && gridCountAfterEntry >= GridDistanceStartLevel)
   {
      int exponent = gridCountAfterEntry - GridDistanceStartLevel;
      currentGridDist *= MathPow(activeGridMult, exponent);
   }

   double minPriceDist = MinGridDistance * point;
   if(currentGridDist < minPriceDist)
      currentGridDist = minPriceDist;

   return currentGridDist;
}

int CountLiveBridgeGridTrades(const int symbolIndex, const string execSymbol)
{
   int liveCount = 0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != execSymbol)
         continue;
      if(!IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
         continue;

      string comment = PositionGetString(POSITION_COMMENT);
      if(InpEnableMultiBaskets && !IsPositionInBasket(symbolIndex, comment))
         continue;
      if(StringFind(comment, "Stack") >= 0)
         continue;

      liveCount++;
   }

   return liveCount;
}

double ComputeBridgeZoneGapSize(const int symbolIndex, const string execSymbol)
{
   double point = SymbolInfoDouble(execSymbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = 1.0;

   double gapSize = 0.0;
   if(ZoneGapType == ZONE_GAP_POINTS)
   {
      gapSize = ZoneGapPoints * point;
   }
   else
   {
      double atr[1];
      if(CopyBuffer(SymbolData[symbolIndex].ATR_Handle, 0, 0, 1, atr) > 0)
         gapSize = atr[0] * ZoneGapATR;
      else
         gapSize = ZoneGapPoints * point;
   }

   double tickSize = SymbolInfoDouble(execSymbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0.0)
      tickSize = point;

   double minTickDist = 10.0 * tickSize;
   if(gapSize < minTickDist)
      gapSize = 50.0 * point;

   return gapSize;
}

bool ResolveEffectiveBridgeRisk(const int symbolIndex,
                                const string execSymbol,
                                ENUM_ORDER_TYPE orderType,
                                const double entryPrice,
                                const double brokerSl,
                                const double totalLot,
                                const bool entryAlreadyLive,
                                double &outStopPrice,
                                double &outSlDistPoints,
                                double &outRiskMoney,
                                string &outSource,
                                string &outFailureReason)
{
   outStopPrice = 0.0;
   outSlDistPoints = 0.0;
   outRiskMoney = 0.0;
   outSource = "";
   outFailureReason = "";

   if(execSymbol == "" || entryPrice <= 0.0 || totalLot <= 0.0)
   {
      outFailureReason = "invalid entry price, lots, or symbol";
      return false;
   }

   double point = SymbolInfoDouble(execSymbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = 1.0;

   double stopPrice = 0.0;
   string source = "";

   if(IsBridgeAdverseStopLevel(orderType, entryPrice, brokerSl))
   {
      stopPrice = brokerSl;
      source = "broker_sl";
   }
   else if(symbolIndex >= 0 && symbolIndex < ArraySize(SymbolData))
   {
      if(RiskMode == RISK_MODE_GRID)
      {
         int liveCount = CountLiveBridgeGridTrades(symbolIndex, execSymbol);
         int gridCountAfterEntry = liveCount + (entryAlreadyLive ? 0 : 1);
         if(gridCountAfterEntry < 1)
            gridCountAfterEntry = MathMax(1, SymbolData[symbolIndex].GridLevels + (entryAlreadyLive ? 0 : 1));

         double gridDist = ComputeBridgeGridDistance(symbolIndex, execSymbol, gridCountAfterEntry);
         if(gridDist > 0.0)
         {
            stopPrice = (orderType == ORDER_TYPE_BUY) ? (entryPrice - gridDist) : (entryPrice + gridDist);
            source = "grid_level";
         }
         else
         {
            outFailureReason = "grid distance unavailable";
         }
      }
      else if(RiskMode == RISK_MODE_ZONE_RECOVERY)
      {
         double top = SymbolData[symbolIndex].ZoneTopPrice;
         double bottom = SymbolData[symbolIndex].ZoneBottomPrice;
         if(top <= 0.0 || bottom <= 0.0 || top <= bottom)
         {
            double gapSize = ComputeBridgeZoneGapSize(symbolIndex, execSymbol);
            if(orderType == ORDER_TYPE_BUY)
            {
               top = entryPrice;
               bottom = entryPrice - gapSize;
            }
            else
            {
               bottom = entryPrice;
               top = entryPrice + gapSize;
            }
         }

         stopPrice = (orderType == ORDER_TYPE_BUY) ? bottom : top;
         source = "zone_level";
      }
      else if(RiskMode == RISK_MODE_NONE && SymbolData[symbolIndex].MasterHasValidSL &&
              IsBridgeAdverseStopLevel(orderType, entryPrice, SymbolData[symbolIndex].MasterSL))
      {
         stopPrice = SymbolData[symbolIndex].MasterSL;
         source = "virtual_stop";
      }
   }

   if(!IsBridgeAdverseStopLevel(orderType, entryPrice, stopPrice))
   {
      if(outFailureReason == "")
         outFailureReason = (source == "" ? "no valid broker or strategy stop" : source + " is not on the adverse side");
      return false;
   }

   double riskMoney = ComputeBridgeRiskMoneyFromStop(execSymbol, orderType, entryPrice, stopPrice, totalLot);
   if(riskMoney <= 0.0)
   {
      outFailureReason = source + " produced non-positive risk";
      return false;
   }

   outStopPrice = stopPrice;
   outSlDistPoints = MathAbs(entryPrice - stopPrice) / point;
   outRiskMoney = riskMoney;
   outSource = source;
   return true;
}

// Keep risk-money math centralized so sync and async paths use the same payload quality.
double ComputeBridgeProposalRisk(string execSymbol, ENUM_ORDER_TYPE orderType, double execPrice, double sl, double totalLot)
{
   if(!IsBridgeAdverseStopLevel(orderType, execPrice, sl))
      return 0.0;

   return ComputeBridgeRiskMoneyFromStop(execSymbol, orderType, execPrice, sl, totalLot);
}

bool QueueBridgeProposalAsync(int symbolIndex,
                              ENUM_ORDER_TYPE orderType,
                              string execSymbol,
                              double execPrice,
                              double sl,
                              double tp,
                              double totalLot,
                              string comment)
{
   BridgeProposal prop;
   ZeroMemory(prop);
   prop.time_msc = BuildUniqueBridgeRequestId(symbolIndex);
   prop.action   = 99;
   prop.type     = (orderType == ORDER_TYPE_BUY) ? 0 : 1;
   prop.lots     = totalLot;
   prop.ticket   = 0;
   double effectiveStop = 0.0;
   double slDistPoints = 0.0;
   double riskMoney = 0.0;
   string riskSource = "";
   string failureReason = "";
   if(!ResolveEffectiveBridgeRisk(symbolIndex, execSymbol, orderType, execPrice, sl, totalLot, false,
                                  effectiveStop, slDistPoints, riskMoney, riskSource, failureReason))
   {
      PrintFormat(EmojiWarning() + " Bridge proposal aborted: symbol=%s type=%s reason=%s",
                  execSymbol,
                  (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL"),
                  failureReason);
      return false;
   }
   prop.risk_money = riskMoney;

   ArrayInitialize(prop.symbol, 0);
   StringToCharArray(execSymbol, prop.symbol, 0, ArraySize(prop.symbol));

   ArrayInitialize(prop.comment, 0);
   StringToCharArray(comment, prop.comment, 0, ArraySize(prop.comment));

   double pt = SymbolInfoDouble(execSymbol, SYMBOL_POINT);
   if(pt <= 0.0) pt = 1.0;
   prop.sl_dist_points = slDistPoints;
   prop.tp_dist_points = (tp > 0.0) ? (MathAbs(execPrice - tp) / pt) : 0.0;

   PrintFormat(EmojiShield() + " Bridge proposal risk: symbol=%s type=%s source=%s stop=%.5f sl_pts=%.1f risk=%.2f",
               execSymbol,
               (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL"),
               riskSource,
               effectiveStop,
               prop.sl_dist_points,
               prop.risk_money);

   string proposalFile = GetProposalFile(InpHedgeChannel);
   string replyFile    = GetReplyFile(InpHedgeChannel);
   string requestId    = StringFormat("%I64d", prop.time_msc);
   bool sqliteEnabled  = V3_RuntimeEnabled(InpV3_EnableSQLiteBridge, InpV3_SQLitePath);

   if(!TryAcquireBridgeChannelLock(InpHedgeChannel, prop.time_msc))
   {
      long activeRequestId = 0;
      datetime activeUntil = 0;
      IsBridgeChannelLockActive(InpHedgeChannel, activeRequestId, activeUntil);
      PrintFormat(EmojiShield() + " Bridge proposal suppressed: channel lock active for %s (req=%I64d until=%s)",
                  execSymbol,
                  activeRequestId,
                  TimeToString(activeUntil, TIME_SECONDS));
      return true;
   }

   if(FileIsExist(replyFile, FILE_COMMON))
      FileDelete(replyFile, FILE_COMMON);
   if(FileIsExist(proposalFile, FILE_COMMON))
      FileDelete(proposalFile, FILE_COMMON);

   if(sqliteEnabled)
   {
      if(!V3_InsertProposalRow(InpV3_SQLitePath, InpHedgeChannel, requestId, prop))
      {
         Print("⚠️ Could not write the async proposal to SQLite. Falling back to the file bridge.");
         sqliteEnabled = false;
      }
      else
      {
         V3_InsertEventRow(InpV3_SQLitePath, InpHedgeChannel, "proposal_enqueued", V3_BuildProposalPayload(prop));
      }
   }

   if(!sqliteEnabled)
   {
      if(FileIsExist(replyFile, FILE_COMMON))
         FileDelete(replyFile, FILE_COMMON);

      int h = FileOpen(proposalFile, FILE_WRITE|FILE_BIN|FILE_COMMON);
      if(h == INVALID_HANDLE)
      {
         ReleaseBridgeChannelLock(InpHedgeChannel, prop.time_msc);
         return false;
      }

      FileWriteStruct(h, prop);
      FileClose(h);
   }

   G_BridgePending.active = true;
   G_BridgePending.approved = false;
   G_BridgePending.symbolIndex = symbolIndex;
   G_BridgePending.orderType = orderType;
   G_BridgePending.totalLot = totalLot;
   G_BridgePending.createdAt = TimeCurrent();

   int timeoutMs = (InpV3_HandshakeTimeoutMs > 0) ? InpV3_HandshakeTimeoutMs : 3000;
   int timeoutSec = (int)MathMax(1, MathCeil((double)timeoutMs / 1000.0));
   G_BridgePending.expiresAt = TimeCurrent() + timeoutSec;

   G_BridgePending.approvedAt = 0;
   G_BridgePending.lastExecAttemptMs = 0;
   G_BridgePending.executionAttempts = 0;
   G_BridgePending.proposalFile = proposalFile;
   G_BridgePending.replyFile = replyFile;
   G_BridgePending.requestId = prop.time_msc;

   PrintFormat("🛡️ Async handshake queued: req=%I64d symbol=%s lots=%.2f", G_BridgePending.requestId, execSymbol, totalLot);
   return true;
}

void ProcessBridgePendingRequest()
{
   if(!IsBridgeRuntimeEnabled() || !InpV3_AsyncHandshake)
      return;

   bool sqliteEnabled = V3_RuntimeEnabled(InpV3_EnableSQLiteBridge, InpV3_SQLitePath);
   string requestId = StringFormat("%I64d", G_BridgePending.requestId);

   if(G_BridgePending.active)
   {
      if(TimeCurrent() > G_BridgePending.expiresAt)
      {
         PrintFormat("🛡️ Async handshake timed out: req=%I64d", G_BridgePending.requestId);
         if(sqliteEnabled)
         {
            long proposalRowId = -1;
            string pendingRequestId = "";
            BridgeProposal pendingProp;
            ZeroMemory(pendingProp);
            if(V3_SelectPendingProposalRow(InpV3_SQLitePath, InpHedgeChannel, proposalRowId, pendingRequestId, pendingProp) && pendingRequestId == requestId)
               V3_UpdateProposalState(InpV3_SQLitePath, proposalRowId, "TIMEOUT");
            V3_InsertEventRow(InpV3_SQLitePath, InpHedgeChannel, "proposal_timeout", V3_BuildReplyPayload("timeout"));
         }
         else
         {
            if(G_BridgePending.proposalFile != "") FileDelete(G_BridgePending.proposalFile, FILE_COMMON);
            if(G_BridgePending.replyFile != "") FileDelete(G_BridgePending.replyFile, FILE_COMMON);
         }
         ResetBridgePendingRequest();
         return;
      }

      if(sqliteEnabled)
      {
         long replyRowId = -1;
         int replyAction = -1;
         string payloadJson = "";
         if(V3_SelectReplyRow(InpV3_SQLitePath, InpHedgeChannel, requestId, replyRowId, replyAction, payloadJson))
         {
            V3_DeleteReplyRow(InpV3_SQLitePath, replyRowId);

           if(replyAction == 1)
           {
              G_BridgePending.active = false;
              G_BridgePending.approved = true;
               G_BridgePending.approvedAt = TimeCurrent();
               G_BridgePending.lastExecAttemptMs = 0;
               G_BridgePending.executionAttempts = 0;
               V3_InsertEventRow(InpV3_SQLitePath, InpHedgeChannel, "proposal_approved", payloadJson);
               PrintFormat("🛡️ Async handshake approved: req=%I64d", G_BridgePending.requestId);
           }
           else
           {
               string denialNote = V3_ExtractJSONValue(payloadJson, "note");
               if(denialNote == "")
                  denialNote = "denied";
               PrintFormat("⚠️ Async handshake denied: req=%I64d reason=%s", G_BridgePending.requestId, denialNote);
               int cooldownMinutes = (InpV3_PauseCooldownMinutes > 0) ? InpV3_PauseCooldownMinutes : 2;
               double resumeAt = (double)(TimeCurrent() + (cooldownMinutes * 60));
               GlobalVariableSet(InpHedgeChannel + "_COOLDOWN_TIMER", resumeAt);
               GlobalVariableSet(InpHedgeChannel + "_PAUSE_FLAG", 1.0);
               V3_InsertEventRow(InpV3_SQLitePath, InpHedgeChannel, "proposal_denied", payloadJson);
               ResetBridgePendingRequest();
            }
         }
         return;
      }

      if(FileIsExist(G_BridgePending.replyFile, FILE_COMMON))
      {
         int hr = FileOpen(G_BridgePending.replyFile, FILE_READ|FILE_BIN|FILE_COMMON);
         if(hr != INVALID_HANDLE)
         {
            BridgeReply reply;
            ZeroMemory(reply);
            FileReadStruct(hr, reply);
            FileClose(hr);

            FileDelete(G_BridgePending.replyFile, FILE_COMMON);
            if(G_BridgePending.proposalFile != "") FileDelete(G_BridgePending.proposalFile, FILE_COMMON);

            if(reply.action == 1)
            {
               G_BridgePending.active = false;
               G_BridgePending.approved = true;
               G_BridgePending.approvedAt = TimeCurrent();
               G_BridgePending.lastExecAttemptMs = 0;
               G_BridgePending.executionAttempts = 0;
               PrintFormat("🛡️ Async handshake approved: req=%I64d", G_BridgePending.requestId);
            }
            else
            {
               PrintFormat("⚠️ Async handshake denied: req=%I64d", G_BridgePending.requestId);
               int cooldownMinutes = (InpV3_PauseCooldownMinutes > 0) ? InpV3_PauseCooldownMinutes : 2;
               double resumeAt = (double)(TimeCurrent() + (cooldownMinutes * 60));
               GlobalVariableSet(InpHedgeChannel + "_COOLDOWN_TIMER", resumeAt);
               GlobalVariableSet(InpHedgeChannel + "_PAUSE_FLAG", 1.0);
               ResetBridgePendingRequest();
            }
         }
      }
      return;
   }

   if(!G_BridgePending.approved)
      return;

   int symbolIndex = G_BridgePending.symbolIndex;
   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData) || !SymbolData[symbolIndex].active)
   {
      Print("⚠️ Async execution dropped: symbol state is invalid.");
      ResetBridgePendingRequest();
      return;
   }

   int execTimeout = (InpV3_AsyncExecTimeoutSec > 0 ? InpV3_AsyncExecTimeoutSec : 5);
   if((TimeCurrent() - G_BridgePending.approvedAt) > execTimeout)
   {
      PrintFormat("⚠️ Async execution expired: req=%I64d", G_BridgePending.requestId);
      if(sqliteEnabled)
         V3_InsertEventRow(InpV3_SQLitePath, InpHedgeChannel, "proposal_exec_expired", V3_BuildReplyPayload("execution_timeout"));
      ResetBridgePendingRequest();
      return;
   }

   int pollMs = (InpV3_HandshakePollMs > 0) ? InpV3_HandshakePollMs : 100;
   ulong nowMs = GetTickCount();
   if((nowMs - G_BridgePending.lastExecAttemptMs) < (ulong)MathMax(50, pollMs))
      return;

   datetime prevTradeTime = SymbolData[symbolIndex].LastTradeTime;
   G_BridgePending.executionAttempts++;
   G_BridgePending.lastExecAttemptMs = nowMs;

   OpenTrade(symbolIndex, G_BridgePending.orderType, G_BridgePending.totalLot, true);

   if(SymbolData[symbolIndex].LastTradeTime != prevTradeTime)
   {
      PrintFormat("🛡️ Async handshake executed: req=%I64d", G_BridgePending.requestId);
      if(sqliteEnabled)
         V3_InsertEventRow(InpV3_SQLitePath, InpHedgeChannel, "proposal_executed", V3_BuildReplyPayload("executed"));
      ResetBridgePendingRequest();
      return;
   }

   if(G_BridgePending.executionAttempts >= 5)
   {
      PrintFormat("⚠️ Async execution failed after retries: req=%I64d", G_BridgePending.requestId);
      if(sqliteEnabled)
         V3_InsertEventRow(InpV3_SQLitePath, InpHedgeChannel, "proposal_exec_failed", V3_BuildReplyPayload("retry_limit"));
      ResetBridgePendingRequest();
   }
}

//+------------------------------------------------------------------+
//| OpenTrade - FULL VERSION (Fixed: Captures Margin Rescue Loss)    |
//| FIX: Properly calculates RawNextGridLot during the initial entry |
//| so the first Grid Trade (Level 1) uses the correct multiplier.   |
//| UPDATE: Added Normal Mode Recovery Logic (Debt Repayment Math)   |
//+------------------------------------------------------------------+
void OpenTrade(int symbolIndex, ENUM_ORDER_TYPE orderType, double overrideLot = 0.0, bool bypassBridge = false, bool isManualTrade = false)
  {
   // --- FIX: RAPID FIRE PREVENTION ---
   if(!bypassBridge)
   {
      static ulong lastAttemptTime = 0;
      if(GetTickCount() - lastAttemptTime < 2000) return;
      lastAttemptTime = GetTickCount();
   }
  // ---------------------------------- 
   string analysisSymbol = SymbolData[symbolIndex].symbol;
   string execSymbol     = GetBaseSymbol(analysisSymbol);

   if(IsBridgeRuntimeEnabled() && InpV3_AsyncHandshake && !bypassBridge)
   {
      long activeRequestId = 0;
      datetime activeUntil = 0;
      if(IsBridgeChannelLockActive(InpHedgeChannel, activeRequestId, activeUntil))
      {
         static ulong lastBridgeLockLog = 0;
         ulong nowMs = GetTickCount();
         if((nowMs - lastBridgeLockLog) >= 1000)
         {
            PrintFormat(EmojiShield() + " Bridge entry suppressed: channel lock is active (req=%I64d until=%s)",
                        activeRequestId,
                        TimeToString(activeUntil, TIME_SECONDS));
            lastBridgeLockLog = nowMs;
         }
         return;
      }
   }

   // LAST RESORT CHECK (FIX: Added Hard Block Check)
   if(IsHedgeBlocked() || G_Cache_IsHardBlock) {
      Print("⚠️ Trade entry blocked: hedge master block or hard close block is active.");
      return;
   }
   
   // --- FIX: EXPLICIT BRIDGE STOP CHECK ---
   // This breaks the "Rogue Trade" loop by checking the flag BEFORE the handshake.
   if(IsBridgeRuntimeEnabled())
   {
       string stopVar = InpHedgeChannel + "_STOP_FLAG";
       if(GlobalVariableCheck(stopVar)) 
       {
           if(GlobalVariableGet(stopVar) > 0.1) 
           {
               // Print only once per second to avoid log spam if looped
               static uint lastLog = 0;
               if(GetTickCount() - lastLog > 60000) {
                   Print("⚠️ Trading blocked by the hedge master stop flag. Trade entry aborted.");
                   lastLog = GetTickCount();
               }
               return; // EXIT IMMEDIATELY - DO NOT TRADE
           }
       }
   }
   // -----------------------------------

// ---------------------------------------------------------
// 1. GET EXECUTION PRICE (Market Price for filling)
// ---------------------------------------------------------
// We use the current Ask/Bid to ensure immediate execution by the broker.
   double execPrice = (orderType == ORDER_TYPE_BUY) ?
                      SymbolInfoDouble(execSymbol, SYMBOL_ASK) :
                      SymbolInfoDouble(execSymbol, SYMBOL_BID);

// ---------------------------------------------------------
// 2. DEFINE REFERENCE PRICE (Static Anchor for Logic)
// ---------------------------------------------------------
// This price is used for Grid Levels and Zone boundaries calculations.
   double refPrice = execPrice;

// STRICT ZONE LOGIC: Ignore market price drift, lock to Zone Lines
// If the Zone is already active, we MUST base calculations on the fixed lines,
// not the current market price, to ensure mathematical precision.
   if(RiskMode == RISK_MODE_ZONE_RECOVERY && SymbolData[symbolIndex].ZoneActive)
     {
      if(SymbolData[symbolIndex].ZoneTopPrice != 0 && SymbolData[symbolIndex].ZoneBottomPrice != 0)
        {
         if(orderType == ORDER_TYPE_BUY)
            refPrice = SymbolData[symbolIndex].ZoneTopPrice;
         else
            refPrice = SymbolData[symbolIndex].ZoneBottomPrice;
        }
     }

   double sl = 0;
   double tp = 0;
   double brokerTP = 0; // New variable for what we actually send
   string comment = TradeComment;
   int basketId = SymbolData[symbolIndex].BasketId;
// ---------------------------------------------------------
// 3. MODE SPECIFIC SETUP (SL/TP)
// ---------------------------------------------------------
   if(RiskMode == RISK_MODE_GRID)
     {
      if(SymbolData[symbolIndex].GridTargetReached)
        {
         sl = 0;
         tp = 0;
         comment += " Grid";
        }
      else
        {
         sl = 0;
         tp = 0;
         comment += " Grid";
         SymbolData[symbolIndex].GridPhase1Active = true;
        }

      // Initialize Grid Tracking on first trade
      if(SymbolData[symbolIndex].GridLevels == 0)
        {
         SymbolData[symbolIndex].RawNextGridLot = 0.0;
         SymbolData[symbolIndex].LastUsedGridRawLot = 0.0;
        }
     }
   else
      if(RiskMode == RISK_MODE_ZONE_RECOVERY)
        {
         // Zone trades usually have no Broker SL/TP (Managed virtually/Hidden)
         sl = 0;
         tp = 0;
         comment += " Zone";
        }
      else // RISK_MODE_NONE (Normal Strategy)
        {
         // Check for Stacking opportunity first
         if(StackMode && SymbolData[symbolIndex].MasterHasValidSL && SymbolData[symbolIndex].MasterTicket != 0)
           {
            OpenStackTrade(symbolIndex);
            return;
           }
         // Calculate Standard SL/TP
         sl = CalculateInitialStopLoss(symbolIndex, orderType, refPrice);
         tp = CalculateTakeProfit(symbolIndex, orderType, refPrice, sl);
         
         // *** STORE FOR TRAILING LOGIC ***
         // Crucial for "Delayed Trailing" which references this InitialTP
         SymbolData[symbolIndex].InitialTP = tp;
         SymbolData[symbolIndex].TPActivated = false; // Reset flag

         // Logic: If Trailing is ON, we want trade to run PAST the TP.
         // ... existing ...
         if(UseTrailing)
            brokerTP = 0;
         else
            brokerTP = tp;
        }

   // ADD THIS BLOCK HERE:
   if(HideSLTPDuringCloseBlock && G_Cache_IsDailyCloseBlock)
     {
      sl = 0;
      brokerTP = 0;
     }

   // Normalize Prices to Tick Size...
   refPrice  = NormalizePrice(execSymbol, refPrice);
   execPrice = NormalizePrice(execSymbol, execPrice);
   sl        = NormalizePrice(execSymbol, sl);
   brokerTP  = NormalizePrice(execSymbol, brokerTP);

// ---------------------------------------------------------
// 4. CALCULATE LOT SIZE
// ---------------------------------------------------------
   double totalLotSize = 0;
// PRIORITY: If overrideLot is provided (e.g., from Zone Math in CheckZoneRecovery), use it.
// Otherwise, calculate based on standard Money Management settings.
   if(overrideLot > 0)
      totalLotSize = overrideLot;
   else
      totalLotSize = CalculateLotSize(symbolIndex, refPrice, sl, orderType);
      
   // -----------------------------------------------------------------------
   // NEW: NORMAL MODE RECOVERY LOGIC (UPDATED)
   // -----------------------------------------------------------------------
   // Only applies if: Normal Mode + Recovery Enabled + We have Debt + TP is set
   if(RiskMode == RISK_MODE_NONE && UsePruningRecovery && SymbolData[symbolIndex].AccumulatedPruningLoss > 0 && tp > 0)
   {
      // A. Calculate Debt Portion to Recover
      // Formula: Base Percentage * Iteration Multiplier
      double mult = SymbolData[symbolIndex].RecoveryIteration;
      double pct  = PruningRecovPercent * mult;
      if(pct > 100.0) pct = 100.0; // Cap at 100%

      // Target amount ($) to earn back on this specific trade
      double recoveryTarget = SymbolData[symbolIndex].AccumulatedPruningLoss * (pct / 100.0);
      
      // Ignore insignificant amounts
      if(recoveryTarget < 0.01) recoveryTarget = 0;

      if(recoveryTarget > 0)
      {
         // B. Calculate Extra Lot needed to earn 'recoveryTarget' over 'TP Distance'
         // Distance = Abs(Entry - TP)
         double dist = MathAbs(execPrice - tp);
         double tickVal = SymbolInfoDouble(execSymbol, SYMBOL_TRADE_TICK_VALUE);
         double tickSize = SymbolInfoDouble(execSymbol, SYMBOL_TRADE_TICK_SIZE);

         if(tickSize > 0 && tickVal > 0)
         {
             // Calculate how much 1.0 Lot earns over this distance
             // Formula: (Distance / TickSize) * TickValue
             double profitPerLot = (dist / tickSize) * tickVal;
    
             if(profitPerLot > 0.00001)
             {
                // C. Calculate Exact Extra Volume Needed
                double extraLot = recoveryTarget / profitPerLot;
                
                // Safety Cap: Prevent lot from exploding on tight TPs. 
                // Cap extra lot at 200% of the base calculated lot.
                //if(extraLot > totalLotSize * 2.0) extraLot = totalLotSize * 2.0;
    
                Print(execSymbol, " [Recovery Math] Debt: $", DoubleToString(SymbolData[symbolIndex].AccumulatedPruningLoss, 2), 
                      " | Target: $", DoubleToString(recoveryTarget, 2), 
                      " | Profit/Lot: $", DoubleToString(profitPerLot, 2),
                      " | Adding Lot: ", DoubleToString(extraLot, 2));
    
                // Add to total request
                totalLotSize += extraLot;
                
                // Store what we are attempting to recover (for logging/debugging)
                SymbolData[symbolIndex].CurrentRecoveryPortion = recoveryTarget;
             }
         }
      }
   }
   // -----------------------------------------------------------------------

// Broker Constraints
   double minLot = SymbolInfoDouble(execSymbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(execSymbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(execSymbol, SYMBOL_VOLUME_STEP);

// Round total request to nearest step
   totalLotSize = NormalizeDouble(totalLotSize / lotStep, 0) * lotStep;
   if(totalLotSize < minLot)
      totalLotSize = minLot;
   // Ensure we don't exceed broker maximum (splitting logic handles effective limits later)
   if(totalLotSize > maxLot)
      totalLotSize = maxLot;

// ---------------------------------------------------------
// 5. MARGIN SAFETY CHECK & RESCUE LOGIC (FIXED)
// ---------------------------------------------------------
   double marginRequired = 0;
   if(!OrderCalcMargin(orderType, execSymbol, totalLotSize, execPrice, marginRequired))
     {
      Print("Error calculating margin: ", GetLastError());
      return;
     }

// Check Free Margin. If insufficient, try to close losing trades on the OPPOSITE side.
   int attempts = 0;
   while(AccountInfoDouble(ACCOUNT_MARGIN_FREE) < marginRequired && attempts < 20)
     {
      // Only attempt rescue if we are in a Grid/Zone sequence (protects account from blowing up)
      if((RiskMode == RISK_MODE_ZONE_RECOVERY && SymbolData[symbolIndex].ZoneActive) ||
         (RiskMode == RISK_MODE_GRID && SymbolData[symbolIndex].GridLevels > 0))
        {
         Print("⚠️ Margin alert: free margin (", AccountInfoDouble(ACCOUNT_MARGIN_FREE),
               ") is below required (", marginRequired, "). Attempting rescue.");

         // Determine Opposite Side (The side we sacrifice)
         ENUM_POSITION_TYPE oppType = (orderType == ORDER_TYPE_BUY) ?
                                      POSITION_TYPE_SELL : POSITION_TYPE_BUY;

         // --- FIX: CLOSE AND CAPTURE LOSS ---
         // We use the updated CloseLargestOppositePosition which returns double (loss amount)
         double rescueLoss = CloseLargestOppositePosition(symbolIndex, oppType);

         if(rescueLoss > 0)
           {
            // Bank this loss immediately into the Critical Bank
            SymbolData[symbolIndex].AccumulatedCriticalLoss += rescueLoss;
            Print("💥 Rescue loss captured: $", DoubleToString(rescueLoss, 2), " added to the critical bank.");
           }

         // Loop continues to check Margin again...
         // If we failed to close anything (rescueLoss == 0) and margin is still low,
         // the loop will eventually hit 'attempts' limit and break.
        }
      else
        {
         // Normal mode: No rescue logic, just exit
         break;
        }

      attempts++;
     }

// Final Margin Check after rescue attempts
   if(AccountInfoDouble(ACCOUNT_MARGIN_FREE) < marginRequired)
     {
      Print("⚠️ Critical margin failure: insufficient margin remained after rescue attempts.");
      // If we stripped the hedge and STILL can't trade, abort sequence to save remainder of account.
      if((RiskMode == RISK_MODE_ZONE_RECOVERY && SymbolData[symbolIndex].ZoneActive) ||
         (RiskMode == RISK_MODE_GRID && SymbolData[symbolIndex].GridLevels > 0))
        {
         Print("🧹 Closing remaining trades and resetting sequence logic.");
         CloseAllGridPositions(symbolIndex, "Insufficient Margin - Sequence Failed");
         ResetGridTracking(symbolIndex);
        }
      return;
     }

// ---------------------------------------------------------
// 6. SPLITTING LOGIC (Broker Max Lot Handling)
// ---------------------------------------------------------
// Determine the effective maximum per ticket
   double effectiveMax = maxLot;
   if(MaxLotSizePerTrade > 0 && MaxLotSizePerTrade < maxLot)
      effectiveMax = MaxLotSizePerTrade; // User setting overrides broker if smaller

   int numTrades = 1;
   double lotPerTrade = totalLotSize;

// If requested lot > allowed max, calculate how many trades we need
   if(totalLotSize > effectiveMax)
     {
      numTrades = (int)MathCeil(totalLotSize / effectiveMax);
      // Cap number of splits to prevent server spam (e.g., max 20 splits)
      if(numTrades > 20)
         numTrades = 20;

      // Recalculate lot per trade (evenly distributed)
      lotPerTrade = totalLotSize / numTrades;
      // Re-normalize the chunk size
      lotPerTrade = NormalizeDouble(lotPerTrade / lotStep, 0) * lotStep;
      if(lotPerTrade < minLot)
         lotPerTrade = minLot;
     }
     
   // =========================================================
   // 6.b HANDSHAKE PROTOCOL (v4: async queue + compatibility fallback)
   // =========================================================
   if(IsBridgeRuntimeEnabled() && !bypassBridge)
   {
      if(InpV3_AsyncHandshake)
      {
         // Single pending request gate avoids overlapping handshakes from parallel symbols.
         if(G_BridgePending.active || G_BridgePending.approved)
         {
            if(isManualTrade)
               Print("⚠️ Manual trade waiting: another bridge request is already pending.");
            return;
         }

         if(!QueueBridgeProposalAsync(symbolIndex, orderType, execSymbol, execPrice, sl, tp, totalLotSize, comment))
         {
            Print("⚠️ Failed to queue the async handshake proposal. Trade entry aborted.");
         }
         return; // Non-blocking path: execution is resumed by ProcessBridgePendingRequest().
      }

      // Legacy blocking fallback (kept for compatibility)
      BridgeProposal prop;
      ZeroMemory(prop);
      prop.time_msc = BuildUniqueBridgeRequestId(symbolIndex);
      prop.action   = 99;
      prop.type     = (orderType == ORDER_TYPE_BUY) ? 0 : 1;
      prop.lots     = totalLotSize;
      prop.ticket   = 0;
      double effectiveStop = 0.0;
      double slDistPoints = 0.0;
      double riskMoney = 0.0;
      string riskSource = "";
      string failureReason = "";
      if(!ResolveEffectiveBridgeRisk(symbolIndex, execSymbol, orderType, execPrice, sl, totalLotSize, false,
                                     effectiveStop, slDistPoints, riskMoney, riskSource, failureReason))
      {
         PrintFormat(EmojiWarning() + " Bridge proposal aborted: symbol=%s type=%s reason=%s",
                     execSymbol,
                     (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL"),
                     failureReason);
         return;
      }
      prop.risk_money = riskMoney;

      ArrayInitialize(prop.symbol, 0);
      StringToCharArray(execSymbol, prop.symbol, 0, ArraySize(prop.symbol));

      ArrayInitialize(prop.comment, 0);
      StringToCharArray(comment, prop.comment, 0, ArraySize(prop.comment));

      double pt = SymbolInfoDouble(execSymbol, SYMBOL_POINT);
      if(pt <= 0.0) pt = 1.0;
      prop.sl_dist_points = slDistPoints;
      prop.tp_dist_points = (tp > 0.0) ? (MathAbs(execPrice - tp) / pt) : 0.0;

      Print("🛡️ Bridge proposal risk: symbol=", execSymbol,
            " type=", (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL"),
            " source=", riskSource,
            " stop=", DoubleToString(effectiveStop, _Digits),
            " sl_pts=", DoubleToString(prop.sl_dist_points, 1),
            " risk=$", DoubleToString(prop.risk_money, 2));

      string proposalFile = GetProposalFile(InpHedgeChannel);
      string replyFile    = GetReplyFile(InpHedgeChannel);

      if(FileIsExist(replyFile, FILE_COMMON)) FileDelete(replyFile, FILE_COMMON);

      int h = FileOpen(proposalFile, FILE_WRITE|FILE_BIN|FILE_COMMON);
      if(h != INVALID_HANDLE)
      {
         FileWriteStruct(h, prop);
         FileClose(h);
      }
      else
      {
         Print("⚠️ Failed to write the handshake proposal. Trade entry aborted.");
         return;
      }

      Print("🛡️ Handshake sent. Lots: ", DoubleToString(totalLotSize, 2), " | waiting for slave approval.");

      bool confirmed = false;
      int timeout = 30; // 30 * 100ms = 3 seconds

      while(timeout > 0)
      {
         if(MBP_ShouldAllowBlockingTradeWait("bridge_handshake"))
            Sleep(100);
         else
            break;

         if(FileIsExist(replyFile, FILE_COMMON))
         {
            int hr = FileOpen(replyFile, FILE_READ|FILE_BIN|FILE_COMMON);
            if(hr != INVALID_HANDLE)
            {
               BridgeReply reply;
               ZeroMemory(reply);
               FileReadStruct(hr, reply);
               FileClose(hr);

               if(reply.action == 1)
               {
                  confirmed = true;
                  Print("🛡️ Handshake confirmed by the slave. Executing trade.");
               }
               else
               {
                  Print("⚠️ Handshake denied by the slave. Trade entry aborted.");
               }

               FileDelete(replyFile, FILE_COMMON);
               FileDelete(proposalFile, FILE_COMMON);
               break;
            }
         }
         timeout--;
      }

      if(timeout <= 0)
      {
         Print("⚠️ Handshake timed out. Slave did not respond.");
         FileDelete(proposalFile, FILE_COMMON);
         return;
      }

      if(!confirmed) return;
   }
   
if(InpEnableMultiBaskets && !isManualTrade && basketId > 0)
   comment += StringFormat(" B#%d", basketId);
// ---------------------------------------------------------
// 7. EXECUTION LOOP
// ---------------------------------------------------------

   // --- FIX: DEFINE THE VARIABLE HERE (Before the loop) ---
   int currentLevelBeforeTrade = SymbolData[symbolIndex].GridLevels;
   // -------------------------------------------------------
   
   for(int i = 0; i < numTrades; i++)
     {
      // Tiny delay between splits to prevent sequence errors/broker rejection
      if(i > 0 && MBP_ShouldAllowBlockingTradeWait("split_trade"))
         Sleep(100);

      string tradeComment = comment;
      if(numTrades > 1)
         tradeComment += StringFormat(" [%d/%d]", i+1, numTrades);

      bool success = false;
      // Execute at MARKET PRICE (execPrice) to ensure fill
      if(orderType == ORDER_TYPE_BUY)
         success = Trade.Buy(lotPerTrade, execSymbol, SymbolInfoDouble(execSymbol, SYMBOL_ASK), sl, brokerTP, tradeComment);
      else
         success = Trade.Sell(lotPerTrade, execSymbol, SymbolInfoDouble(execSymbol, SYMBOL_BID), sl, brokerTP, tradeComment);
      
      // --- FIX: GHOST FILL CHECK (TIMEOUT HANDLING) ---
      if(!success)
      {
          ulong retCode = Trade.ResultRetcode();
          // Check for Timeout (10005) or Connection Error (10031)
          if(retCode == TRADE_RETCODE_TIMEOUT || retCode == TRADE_RETCODE_CONNECTION)
          {
              Print("⚠️ Order timeout detected. Pausing 2 seconds to check for ghost fills.");
              if(MBP_ShouldAllowBlockingTradeWait("ghost_fill"))
                 Sleep(2000); // Wait for broker to maybe fill it
              
              // Force a scan of open positions to see if it actually opened
              UpdatePositionTracking(symbolIndex); 
              
              // If the grid level count is HIGHER now than it was BEFORE the loop, the trade worked!
              if(SymbolData[symbolIndex].GridLevels > currentLevelBeforeTrade)
              {
                  Print("🛡️ Ghost fill detected. Marking the trade as successful.");
                  success = true;
              }
          }
      }
      // ------------------------------------------------/
       
      if(success)
        {
         SymbolData[symbolIndex].LastTradeTime = TimeCurrent();

         // --- LOGIC UPDATES (Only on the FIRST split trade) ---
         // We update the tracking logic only once per "logical" trade.
         if(i == 0)
           {
            if(InpEnableMultiBaskets && SymbolData[symbolIndex].BasketInitialEntry <= 0.0)
              {
               SymbolData[symbolIndex].BasketInitialEntry = refPrice;
               SymbolData[symbolIndex].BasketDirection = (orderType == ORDER_TYPE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
               SymbolData[symbolIndex].BasketActive = true;
              }
            // A. GRID MODE UPDATE (Standard)
            if(RiskMode == RISK_MODE_GRID && !SymbolData[symbolIndex].GridTargetReached)
              {
               SymbolData[symbolIndex].GridEntries[SymbolData[symbolIndex].GridLevels] = refPrice;

               if(SymbolData[symbolIndex].GridLevels == 0)
                 {
                  SymbolData[symbolIndex].GridSequenceDepth = 1;
                  SymbolData[symbolIndex].GridBasketEntry = refPrice;
                  SymbolData[symbolIndex].GridBasketVolume = 0;

                  // Store this total lot for next progression base
                  SymbolData[symbolIndex].LastUsedGridRawLot = totalLotSize;

                  // --- FIX: Pre-calculate the NEXT grid lot for Level 1 ---
                  // Logic: If GridStakeStartLevel is 1 (default), we apply multiplier immediately for the next trade.
                  double nextMult = (GridStakeStartLevel <= 1) ? GridStakeMultiplier : 1.0;

                  double nextLot = totalLotSize * nextMult;
                  if(GridMaxStake > 0.0 && nextLot > GridMaxStake)
                     nextLot = GridMaxStake;

                  SymbolData[symbolIndex].RawNextGridLot = nextLot;
                  // ---------------------------------------------------------

                  // *** DO NOT ADD DEBT YET ***
                  // Initial Trade targets only the base profit.
                  // We save the debt logic for when we actually need recovery (Level 2).
                  SymbolData[symbolIndex].GridTargetProfit = GridTP_Amount;
                  SymbolData[symbolIndex].CurrentRecoveryPortion = 0.0;

                  SymbolData[symbolIndex].GridLevels++;
                 }
               else
                 {
                  // Next Grid Level
                  SymbolData[symbolIndex].GridSequenceDepth++;
                  double currentRaw = (SymbolData[symbolIndex].RawNextGridLot > 0) ? SymbolData[symbolIndex].RawNextGridLot : totalLotSize;
                  SymbolData[symbolIndex].LastUsedGridRawLot = currentRaw;

                  double mult = (SymbolData[symbolIndex].GridSequenceDepth >= GridStakeStartLevel) ?
                                GridStakeMultiplier : 1.0;

                  double next = currentRaw * mult;
                  if(GridMaxStake > 0.0 && next > GridMaxStake)
                     next = GridMaxStake;

                  SymbolData[symbolIndex].RawNextGridLot = next;
                  SymbolData[symbolIndex].GridLevels++;
                 }
              }

            // B. ZONE RECOVERY UPDATE
            if(RiskMode == RISK_MODE_ZONE_RECOVERY)
              {
               // --- SCENARIO 1: INITIAL ENTRY (Trade #1) ---
               if(!SymbolData[symbolIndex].ZoneActive)
                 {
                  double point = SymbolInfoDouble(execSymbol, SYMBOL_POINT);
                  double gapSize = 0.0;

                  if(ZoneGapType == ZONE_GAP_POINTS)
                     gapSize = ZoneGapPoints * point;
                  else
                    {
                     double atr[1];
                     if(CopyBuffer(SymbolData[symbolIndex].ATR_Handle, 0, 0, 1, atr) > 0)
                        gapSize = atr[0] * ZoneGapATR;
                     else
                        gapSize = ZoneGapPoints * point;
                    }

                  // Force gapSize to at least 10 ticks to avoid calculation errors
                  double minTickDist = 10 * SymbolInfoDouble(execSymbol, SYMBOL_TRADE_TICK_SIZE);
                  if(gapSize < minTickDist)
                     gapSize = 50.0 * point;

                  // LOCK STATIC BOUNDARIES
                  if(orderType == ORDER_TYPE_BUY)
                    {
                     SymbolData[symbolIndex].ZoneTopPrice    = refPrice;
                     SymbolData[symbolIndex].ZoneBottomPrice = refPrice - gapSize;
                    }
                  else
                    {
                     SymbolData[symbolIndex].ZoneBottomPrice = refPrice;
                     SymbolData[symbolIndex].ZoneTopPrice    = refPrice + gapSize;
                    }

                  SymbolData[symbolIndex].ZoneActive = true;
                  SymbolData[symbolIndex].ZoneSeqCount = 1;
                  SymbolData[symbolIndex].ZoneResolved = false;

                  // CLEAN START: Set Base Target only.
                  SymbolData[symbolIndex].GridTargetProfit = ZoneTP_Amount;
                  SymbolData[symbolIndex].CurrentRecoveryPortion = 0.0;

                  DrawGridLine(BasketScopedObjectName(symbolIndex, "ZoneTop_", execSymbol), SymbolData[symbolIndex].ZoneTopPrice, clrGreen);
                  DrawGridLine(BasketScopedObjectName(symbolIndex, "ZoneBot_", execSymbol), SymbolData[symbolIndex].ZoneBottomPrice, clrRed);

                  Print(execSymbol, " Zone Started. Top: ", SymbolData[symbolIndex].ZoneTopPrice, " Bot: ", SymbolData[symbolIndex].ZoneBottomPrice, " Target: $", SymbolData[symbolIndex].GridTargetProfit);
                 }
               else
                 {
                  // --- SCENARIO 2: RECOVERY HEDGE (Trade #2+) ---
                  SymbolData[symbolIndex].ZoneSeqCount++;
                  Print(execSymbol, " Zone Recovery #", SymbolData[symbolIndex].ZoneSeqCount, " Executed.");
                 }
              }

            // C. NORMAL MODE UPDATE (RECOVERY TRACKING)
            if(RiskMode == RISK_MODE_NONE && SymbolData[symbolIndex].MasterTicket == 0)
              {
               SymbolData[symbolIndex].MasterTicket = Trade.ResultOrder();
               // --- FIX: CACHE THE TYPE & SL IMMEDIATELY ---
               SymbolData[symbolIndex].MasterType = (orderType == ORDER_TYPE_BUY ? POSITION_TYPE_BUY : POSITION_TYPE_SELL);
               SymbolData[symbolIndex].MasterEntry = execPrice;
               SymbolData[symbolIndex].MasterSL = sl;
               SymbolData[symbolIndex].MasterHasValidSL = (sl != 0);
              }
           } // End Logic Update (i==0)

         // Add Volume to Trackers (For EVERY split trade)
         if(RiskMode == RISK_MODE_ZONE_RECOVERY || RiskMode == RISK_MODE_GRID)
         {
            SymbolData[symbolIndex].GridBasketVolume += lotPerTrade;
            SaveBasketRuntimeState(symbolIndex);
         }

        } // End Success
     } // End Loop
  }

//+------------------------------------------------------------------+
//| Close position for symbol                                        |
//+------------------------------------------------------------------+
void ClosePosition(int symbolIndex, ulong ticket, string reason)
  {
   string symbol = SymbolData[symbolIndex].symbol;

   if(Trade.PositionClose(ticket))
     {
      Print(symbol, " Position closed: ", reason);
      SendAlert(symbol + " Position Closed", reason);

      if(ticket == SymbolData[symbolIndex].MasterTicket)
        {
         SymbolData[symbolIndex].MasterTicket = 0;
         SymbolData[symbolIndex].MasterSL = 0;
         SymbolData[symbolIndex].MasterEntry = 0;
         SymbolData[symbolIndex].MasterHasValidSL = false;
        }

      UpdatePositionTracking(symbolIndex);
     }
  }

//+------------------------------------------------------------------+
//| Check grid on tick (price level monitoring)                     |
//+------------------------------------------------------------------+
void CheckGridOnTick(int symbolIndex)
  {
   string symbol = SymbolData[symbolIndex].symbol;

// Limit grid checks to avoid too frequent operations
   if(TimeCurrent() - SymbolData[symbolIndex].LastGridCheckTime < 1) // Check at most once per second
      return;

   SymbolData[symbolIndex].LastGridCheckTime = TimeCurrent();

// Check for new grid levels ONLY if target not reached
   if(!SymbolData[symbolIndex].GridTargetReached)
     {
      CheckNewGridLevel(symbolIndex);
     }
  }

//+------------------------------------------------------------------+
//| Check for new grid level (Fixed: Transparency in Debt deferral)  |
//+------------------------------------------------------------------+
void CheckNewGridLevel(int symbolIndex)
  {
   // 1. BRIDGE SAFETY CHECK (Highest Priority)
   if(IsBridgeRuntimeEnabled())
   {
      string stopVar = InpHedgeChannel + "_STOP_FLAG";
      if(GlobalVariableCheck(stopVar)) {
         if(GlobalVariableGet(stopVar) > 0.1) return; // EXIT IMMEDIATELY
      }
   }
   
   // GLOBAL COOLDOWN BLOCK
   if(IsGlobalCooldownActive()) return;
   
   // ---------------------------------------------------------
   // 2. BRIDGE SAFETY CHECK (BLOCK NEW LEVELS/SEQUENCES)
   // ---------------------------------------------------------
   if(IsBridgeRuntimeEnabled())
   {
      string stopVar = InpHedgeChannel + "_STOP_FLAG";
      // We check if the variable exists AND if it is set to "1" (Blocked)
      if(GlobalVariableCheck(stopVar)) 
      {
         if(GlobalVariableGet(stopVar) > 0.1) 
         {
             // Optional: Print once per minute to avoid log spam
             static uint lastLog = 0;
             if(GetTickCount() - lastLog > 60000) {
                 Print("🛡️ Grid sequencing blocked by the hedge master. Skipping the next grid-level check.");
                 lastLog = GetTickCount();
             }
             return; // EXIT: Do not calculate levels, do not trade.
         }
      }
   }
   // ---------------------------------------------------------
   
  // Only block if we are at Level 0 (starting a new sequence)
   if(SymbolData[symbolIndex].GridLevels == 0)
  {
   UpdateFilterStats(symbolIndex);
   if(!CheckFilters(symbolIndex)) return;
  }
   if(IsPaused)
      return;

// Execution Cooldown: Prevent double-checking while broker processes order
   if(TimeCurrent() - SymbolData[symbolIndex].LastTradeTime < 5)
      return;

   string symbol = SymbolData[symbolIndex].symbol;    // Renko (Analysis)
   string execSymbol = GetBaseSymbol(symbol);         // Real Market (Execution)
   string lineName = BasketScopedObjectName(symbolIndex, "Grid_NextLevel_", symbol);

// 0. CLEANUP CHECK
   if(SymbolData[symbolIndex].GridPhase2Active)
     {
      ObjectDelete(0, lineName);
      return;
     }

// 1. SCAN FOR LAST GRID PRICE (The "Worst" Entry)
   double lastGridPrice = 0;
   int currentGridCount = 0;
   ENUM_POSITION_TYPE gridType = POSITION_TYPE_BUY; // Default
   bool foundAny = false;

   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetString(POSITION_SYMBOL) == execSymbol &&
            IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
           {
            string comment = PositionGetString(POSITION_COMMENT);
            if(InpEnableMultiBaskets && !IsPositionInBasket(symbolIndex, comment))
               continue;
            // Filter: Grid trades only (ignore Stack)
            bool isStack = (StringFind(comment, "Stack") >= 0);

            if(!isStack)
              {
               double price = PositionGetDouble(POSITION_PRICE_OPEN);
               ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

               if(!foundAny)
                 {
                  lastGridPrice = price;
                  gridType = type;
                  foundAny = true;
                 }
               else
                 {
                  // Find "Worst" Price (Lowest for Buy, Highest for Sell)
                  if(type == POSITION_TYPE_BUY)
                    {
                     if(price < lastGridPrice)
                        lastGridPrice = price;
                    }
                  else
                    {
                     if(price > lastGridPrice)
                        lastGridPrice = price;
                    }
                 }
               currentGridCount++;
              }
           }
        }
     }

// If no trades found on the ACTUAL execution symbol, reset and exit
   if(!foundAny)
     {
      ObjectDelete(0, lineName);
      SymbolData[symbolIndex].GridLevels = 0;
      return;
     }

// Sync Memory
   SymbolData[symbolIndex].GridLevels = currentGridCount;

// 2. CALCULATE REQUIRED DISTANCE (Standard Grid Logic)
   double point = SymbolInfoDouble(execSymbol, SYMBOL_POINT);
   double currentGridDist = 0;

// A. Base Distance Calculation
   if(GridDistanceType == GRID_DIST_POINTS)
     {
      currentGridDist = GridDistance * point;
     }
   else // GRID_DIST_ATR
     {
      double atr[1];
      if(CopyBuffer(SymbolData[symbolIndex].ATR_Handle, 0, 1, 1, atr) > 0)
        {
         currentGridDist = atr[0] * GridDistance;
        }
      else
        {
         currentGridDist = MinGridDistance * point; // Fallback
        }
     }

// B. Apply Grid Multiplier
// ==========================================================
// --- SHADOW MASTER FALLBACK MECHANISM ---
// ==========================================================
   bool aiActive = false;
   if(InpEnableShadowMaster && SymbolData[symbolIndex].LastShadowUpdate > 0 && 
     (TimeCurrent() - SymbolData[symbolIndex].LastShadowUpdate < 172800)) // 48-hour crash limit
   {
       // Sanity Check: Ensure valid data was actually parsed
       if(SymbolData[symbolIndex].Dyn_GridMultiplier > 0) 
           aiActive = true;
   }
   
   // Apply dynamic AI value if live, otherwise fallback to standard static input
   double activeGridMult = aiActive ? SymbolData[symbolIndex].Dyn_GridMultiplier : GridMultiplier;
// ==========================================================

   // --- NO GRID OPTION ENFORCER ---
   if(activeGridMult == 0.0) 
      return; // Do not stretch the grid, do not open recovery trades
   // -------------------------------

   double distMultiplier = 1.0;
   if(GridDistanceStartLevel >= 0 && currentGridCount >= GridDistanceStartLevel)
     {
      int exponent = currentGridCount - GridDistanceStartLevel;
      distMultiplier = MathPow(activeGridMult, exponent);
      currentGridDist *= distMultiplier;
     }

// C. Clamp Distance
   double minPriceDist = MinGridDistance * point;
   if(currentGridDist < minPriceDist)
      currentGridDist = minPriceDist;

// 3. CALCULATE TARGET PRICE
   double targetPrice = 0;
   if(gridType == POSITION_TYPE_BUY)
      targetPrice = lastGridPrice - currentGridDist;
   else
      targetPrice = lastGridPrice + currentGridDist;

// --- VISUAL UPDATE ---
   if(_Symbol == symbol || _Symbol == execSymbol)
      DrawGridLine(lineName, targetPrice, clrOrange);

// 4. CHECK TRIGGER
   double currentPrice = (gridType == POSITION_TYPE_BUY) ?
                         SymbolInfoDouble(execSymbol, SYMBOL_BID) :
                         SymbolInfoDouble(execSymbol, SYMBOL_ASK);

   bool createNewLevel = false;

   if(gridType == POSITION_TYPE_BUY)
     {
      if(currentPrice <= targetPrice)
         createNewLevel = true;
     }
   else
     {
      if(currentPrice >= targetPrice)
         createNewLevel = true;
     }

// 5. EXECUTE NEW LEVEL
   if(createNewLevel)
     {
      // --- SPREAD CHECK ---
      if(!CheckSpread(symbolIndex))
         return;

      Print("📈 Grid entry triggered: ", execSymbol);
      Print(" - Level: ", currentGridCount + 1);

      // =================================================================
      // STRATEGY BRANCHING (DEBT & LOT SIZING WITH REALITY CHECK)
      // =================================================================
      double tradeLot = 0.0;
      double pendingPortion = 0.0;
      bool recoveryActive = false;
      
      // --- NEW: Calculate Dynamic Target ---
      double currentBaseTarget = GetDynamicProfitTarget(symbolIndex) ;

      // --- STEP A: OPTIMISTIC DEBT ALLOCATION ---
      // We calculate what we WANT to recover based on the Bank and Percentage
      if(UsePruningRecovery && SymbolData[symbolIndex].AccumulatedPruningLoss > 0 && SymbolData[symbolIndex].CurrentRecoveryPortion == 0)
        {
         double mult = SymbolData[symbolIndex].RecoveryIteration;
         double pct = PruningRecovPercent * mult;
         if(pct > 100.0)
            pct = 100.0;

         pendingPortion = SymbolData[symbolIndex].AccumulatedPruningLoss * (pct / 100.0);
         if(pendingPortion < 0.01)
            pendingPortion = SymbolData[symbolIndex].AccumulatedPruningLoss;

         // Set Target = Dynamic Base + Debt
         SymbolData[symbolIndex].GridTargetProfit = currentBaseTarget + pendingPortion;
         recoveryActive = true;
        }
      else
        {
         // No debt? Just set the Dynamic Base
         SymbolData[symbolIndex].GridTargetProfit = currentBaseTarget;
        }

      // --- STEP B: LOT CALCULATION & CAPPING ---
      ENUM_ORDER_TYPE calcOrderType = (gridType == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

      if(GridStrategy == GRID_STRAT_AGGRESSIVE)
        {
         // AGGRESSIVE MODE: Use Math to calculate lot.
         // NOTE: This function returns a CAPPED lot if the math demands too much.
         tradeLot = CalculateAggressiveGridLot(symbolIndex, calcOrderType, currentPrice);
         Print("   [AGGRESSIVE] Calculated Lot: ", tradeLot);
        }
      else
        {
         // CONSERVATIVE MODE: Standard Multiplier
         tradeLot = 0.0; // OpenTrade will handle the default multiplier logic
         Print("   [CONSERVATIVE] Using Standard Multiplier");
        }

      // --- STEP C: REALITY CHECK (Adjust Debt if Lot was Capped) ---
      // If we are in Aggressive Mode AND Recovery is active, we check if the capped lot
      // is actually enough to recover the full 'pendingPortion'.
      if(recoveryActive && GridStrategy == GRID_STRAT_AGGRESSIVE)
        {
         double tickVal = SymbolInfoDouble(execSymbol, SYMBOL_TRADE_TICK_VALUE);
         double tickSize = SymbolInfoDouble(execSymbol, SYMBOL_TRADE_TICK_SIZE);

         // Get the Target Price used in calculation (set inside CalculateAggressiveGridLot)
         double aggrTarget = SymbolData[symbolIndex].GridAggressiveTargetPrice;

         // Calculate PROJECTED total profit at that target
         double projectedTotalProfit = 0.0;

         // 1. Existing Trades Equity
         for(int i = 0; i < PositionsTotal(); i++)
           {
            if(PositionSelectByTicket(PositionGetTicket(i)))
              {
               if(PositionGetString(POSITION_SYMBOL) == execSymbol && IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
                 {
                  string c = PositionGetString(POSITION_COMMENT);
            if(InpEnableMultiBaskets && !IsPositionInBasket(symbolIndex, c))
               continue;
            if(StringFind(c, "Grid") >= 0 || StringFind(c, "Stack") >= 0)
                    {
                     double vol = PositionGetDouble(POSITION_VOLUME);
                     double open = PositionGetDouble(POSITION_PRICE_OPEN);
                     ENUM_POSITION_TYPE pType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                     double diff = (pType == POSITION_TYPE_BUY) ? (aggrTarget - open) : (open - aggrTarget);
                     projectedTotalProfit += (diff / tickSize) * tickVal * vol;
                     projectedTotalProfit += PositionGetDouble(POSITION_SWAP) + GetPositionCommission(PositionGetInteger(POSITION_IDENTIFIER));
                    }
                 }
              }
           }

         // 2. New Trade Profit
         double dist = MathAbs(aggrTarget - currentPrice);
         double newTradeProfit = (dist / tickSize) * tickVal * tradeLot;
         projectedTotalProfit += newTradeProfit;

         // 3. Compare Projected vs Target
         // If Projected is less than the required (Base + Debt), we must reduce the debt portion
         if(projectedTotalProfit < (currentBaseTarget + pendingPortion))
           {
            double maxPossibleRecovery = projectedTotalProfit - currentBaseTarget;
            if(maxPossibleRecovery < 0)
               maxPossibleRecovery = 0;

            // --- FIX: EXPLICIT LOGGING OF DEFERRAL ---
            double deferredAmount = pendingPortion - maxPossibleRecovery;

            Print("   [REALITY CHECK] Lot Capped (", tradeLot, ").");
            Print("   > Reduced Target from $", DoubleToString(pendingPortion, 2), " to $", DoubleToString(maxPossibleRecovery, 2));
            Print("   > Deferred $", DoubleToString(deferredAmount, 2), " back to Bank.");

            pendingPortion = maxPossibleRecovery;
            SymbolData[symbolIndex].GridTargetProfit = currentBaseTarget + pendingPortion;
           }
        }

      // --- STEP D: FINALIZE DEBT TRACKING ---
      if(recoveryActive)
        {
         SymbolData[symbolIndex].CurrentRecoveryPortion = pendingPortion;
         Print(execSymbol, " Grid Recovery Active. Final Portion: $", DoubleToString(pendingPortion, 2));
        }

      // Execute Trade
      if(gridType == POSITION_TYPE_BUY)
         OpenTrade(symbolIndex, ORDER_TYPE_BUY, tradeLot);
      else
         OpenTrade(symbolIndex, ORDER_TYPE_SELL, tradeLot);

      ObjectDelete(0, lineName);

      // =========================================================
      // --- PRUNING LOGIC (SOFT vs HARD) ---
      // =========================================================
      if(UseGridPruning && SymbolData[symbolIndex].GridLevels >= PruningLevel) // Changed > to >= for immediate action
        {
         if(PruningStyle == PRUNING_SOFT)
           {
            // --- EXISTING SOFT PRUNING (Close Oldest) ---
            ulong oldestTicket = 0;
            datetime oldestTime = TimeCurrent();
            
            // [Insert existing Soft Pruning Search Logic here...]
            for(int k=0; k<PositionsTotal(); k++)
              {
               ulong t = PositionGetTicket(k);
               if(PositionSelectByTicket(t))
                 {
                  if(PositionGetString(POSITION_SYMBOL) == execSymbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
                    {
                     string c = PositionGetString(POSITION_COMMENT);
            if(InpEnableMultiBaskets && !IsPositionInBasket(symbolIndex, c))
               continue;
            if(StringFind(c, "Grid") >= 0 && StringFind(c, "Stack") < 0)
                       {
                        datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
                        if(openTime < oldestTime) { oldestTime = openTime; oldestTicket = t; }
                       }
                    }
                 }
              }

            if(oldestTicket > 0)
              {
               double pruneLoss = 0.0;
               // Calculate Loss...
               if(PositionSelectByTicket(oldestTicket))
                 {
                  double netPL = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP) + GetPositionCommission(PositionGetInteger(POSITION_IDENTIFIER));
                  if(netPL < 0) pruneLoss = MathAbs(netPL);
                 }

               Print(execSymbol, " Soft Pruning: Closing oldest grid trade: ", oldestTicket);
               if(Trade.PositionClose(oldestTicket))
                 {
                  SymbolData[symbolIndex].GridLevels--;
                  if(UsePruningRecovery && pruneLoss > 0)
                    {
                     SymbolData[symbolIndex].AccumulatedPruningLoss += pruneLoss;
                     SymbolData[symbolIndex].RecoveryIteration = 1;
                     SymbolData[symbolIndex].PruningOccurredThisSequence = true;
                    }
                 }
              }
           }
         else // PRUNING_HARD
           {
            // --- NEW HARD PRUNING (Close Entire Basket) ---
            Print(execSymbol, " ⚠️ Hard pruning triggered at level count ", SymbolData[symbolIndex].GridLevels, ".");
            CloseAllGridPositions(symbolIndex, "Hard Pruning (Limit Reached)");
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Check grid target on tick (Impulse Mark/Wait + Dollar Target)    |
//+------------------------------------------------------------------+
void CheckGridTargetOnTick(int symbolIndex)
  {
   if(!CheckSpread(symbolIndex))
      return;
   string trackingSymbol = GetBaseSymbol(SymbolData[symbolIndex].symbol);
   bool filterByBasket = InpEnableMultiBaskets;

   if(SymbolData[symbolIndex].GridPhase2Active)
      return;

// 1. GATHER DATA
   double totalGridProfit = 0;
   int gridCount = 0;
   double initialEntry = 0;
   ENUM_POSITION_TYPE direction = POSITION_TYPE_BUY;

   if(TimeCurrent() - SymbolData[symbolIndex].LastTradeTime < 1)
      return;

   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetString(POSITION_SYMBOL) == trackingSymbol &&
            IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
           {
         string comment = PositionGetString(POSITION_COMMENT);
         if(filterByBasket && !IsPositionInBasket(symbolIndex, comment))
            continue;
            if(StringFind(comment, "Grid") >= 0 && StringFind(comment, "GridStack") < 0)
              {
               ulong posID = PositionGetInteger(POSITION_IDENTIFIER);
               double p = PositionGetDouble(POSITION_PROFIT);
               double s = PositionGetDouble(POSITION_SWAP);
               double c = GetPositionCommission(posID);
               totalGridProfit += (p + s + c);
               gridCount++;

               if(gridCount == 1)
                 {
                  direction = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                  initialEntry = PositionGetDouble(POSITION_PRICE_OPEN);
                 }
              }
           }
        }
     }

   if(gridCount == 0)
      return;

   double currentPrice = (direction == POSITION_TYPE_BUY) ?
                         SymbolInfoDouble(trackingSymbol, SYMBOL_BID) :
                         SymbolInfoDouble(trackingSymbol, SYMBOL_ASK);

   bool readyToTransition = false;

// =================================================================
// LOGIC A: IMPULSE TRANSITION (Single Trade Phase 1)
// =================================================================
// If we only have 1 trade, we use the "Price X" logic
   if(gridCount == 1)
     {
      double atr[1];
      double atrVal = 0;
      if(CopyBuffer(SymbolData[symbolIndex].ATR_Handle, 0, 0, 1, atr) > 0)
         atrVal = atr[0];
      if(atrVal == 0)
         atrVal = SymbolInfoDouble(trackingSymbol, SYMBOL_POINT) * 50;

      // 1. Calculate Distances
      double impulseDist = atrVal * GridImpulseATR;
      double bufferDist  = 0.0;

      if(GridTransitionType == GRID_DIST_POINTS)
         bufferDist = GridTransitionDist * SymbolInfoDouble(trackingSymbol, SYMBOL_POINT);
      else
         bufferDist = atrVal * GridTransitionDist;

      // 2. Determine "Price X" (Impulse Price)
      double priceX = (direction == POSITION_TYPE_BUY) ? (initialEntry + impulseDist) : (initialEntry - impulseDist);

      // 3. STEP 1: MARK PRICE X (If not marked)
      if(!SymbolData[symbolIndex].GridTPHit)
        {
         bool hitX = (direction == POSITION_TYPE_BUY && currentPrice >= priceX) ||
                     (direction == POSITION_TYPE_SELL && currentPrice <= priceX);

         if(hitX)
           {
            SymbolData[symbolIndex].GridTPHit = true;
            SymbolData[symbolIndex].GridTPHitPrice = priceX; // Lock SL at Impulse Price
            SaveBasketRuntimeState(symbolIndex);
             Print(trackingSymbol, " Grid Phase 2 impulse marker hit at ",
                   DoubleToString(priceX, (int)SymbolInfoInteger(trackingSymbol, SYMBOL_DIGITS)),
                   ". Waiting for transition buffer.");
           }
        }

      // 4. STEP 2: CHECK BUFFER
      if(SymbolData[symbolIndex].GridTPHit)
        {
         bool bufferCleared = false;
         double triggerPrice = 0.0;

         if(direction == POSITION_TYPE_BUY)
           {
            triggerPrice = SymbolData[symbolIndex].GridTPHitPrice + bufferDist;
            if(currentPrice >= triggerPrice)
               bufferCleared = true;
           }
         else
           {
            triggerPrice = SymbolData[symbolIndex].GridTPHitPrice - bufferDist;
            if(currentPrice <= triggerPrice)
               bufferCleared = true;
           }

         if(bufferCleared)
           {
            readyToTransition = true;
            Print(trackingSymbol, " Grid Buffer Cleared! Locking SL at Price X.");
           }
        }
     }

// =================================================================
// LOGIC B: DOLLAR TARGET (Recovery / Multiple Trades)
// =================================================================
// Only run if we aren't already transitioning from Impulse
   if(!readyToTransition && totalGridProfit >= SymbolData[symbolIndex].GridTargetProfit)
     {
      // A. Mark the spot
      if(!SymbolData[symbolIndex].GridTPHit)
        {
         SymbolData[symbolIndex].GridTPHit = true;
         SymbolData[symbolIndex].GridTPHitPrice = currentPrice; // Lock SL at Current Price (Dollar Hit)
         SaveBasketRuntimeState(symbolIndex);
          Print(trackingSymbol, " Grid profit target hit ($",
                DoubleToString(totalGridProfit, 2), " / $",
                DoubleToString(SymbolData[symbolIndex].GridTargetProfit, 2),
                "). Waiting for transition buffer.");
         }

      // B. Calculate Buffer
      double buffer = 0;
      double point = SymbolInfoDouble(trackingSymbol, SYMBOL_POINT);

      if(GridTransitionType == GRID_DIST_POINTS)
         buffer = GridTransitionDist * point;
      else
        {
         double atr[1];
         if(CopyBuffer(SymbolData[symbolIndex].ATR_Handle, 0, 0, 1, atr) > 0)
            buffer = atr[0] * GridTransitionDist;
         else
            buffer = 50 * point;
        }

      // C. Check transition
      double hitPrice = SymbolData[symbolIndex].GridTPHitPrice;

      if(direction == POSITION_TYPE_BUY)
        {
         if(currentPrice >= (hitPrice + buffer))
            readyToTransition = true;
        }
      else
        {
         if(currentPrice <= (hitPrice - buffer))
            readyToTransition = true;
        }
     }
   else
     {
      // Reset hit flag if profit drops back down significantly (Only for Dollar Logic)
      if(!readyToTransition && SymbolData[symbolIndex].GridTPHit && gridCount > 1 && totalGridProfit < (SymbolData[symbolIndex].GridTargetProfit * 0.8))
        {
         SymbolData[symbolIndex].GridTPHit = false;
         SymbolData[symbolIndex].GridTPHitPrice = 0;
         SaveBasketRuntimeState(symbolIndex);
        }
     }

// EXECUTE TRANSITION
   if(readyToTransition)
     {
      if(HideSLTPDuringCloseBlock && G_Cache_IsDailyCloseBlock && GridCloseOnTP) return; // Wait to close
      SymbolData[symbolIndex].GridTargetReached = true;
      SaveBasketRuntimeState(symbolIndex);
      Print(trackingSymbol, " Grid Phase 2 transition trigger confirmed. GridCloseOnTP=",
            (GridCloseOnTP ? "true" : "false"), " | UseTrailing=",
            (UseTrailing ? "true" : "false"), " | LockTrail=",
            EnumToString(LockTrail));
      TransitionToGridPhase2(symbolIndex);
      }
   }


//+------------------------------------------------------------------+
//| Transition to grid phase 2 - UPDATED (Fixed: Bank Merger Logic)  |
//+------------------------------------------------------------------+
void TransitionToGridPhase2(int symbolIndex)
  {
   string symbol = SymbolData[symbolIndex].symbol;
   string trackingSymbol = GetBaseSymbol(SymbolData[symbolIndex].symbol);

// =======================================================
// --- 1. CALCULATE REALIZED PROFIT & COUNT TRADES ---
// We need to know if this was a Single Trade (Impulse) or a Recovery Basket
// to decide if we should pay off the debt.
// =======================================================
   double basketNetProfit = 0.0;
   int activeTradeCount = 0;

   for(int i = 0; i < PositionsTotal(); i++)
     {
      if(PositionSelectByTicket(PositionGetTicket(i)))
        {
         if(PositionGetString(POSITION_SYMBOL) == trackingSymbol && IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
           {
            string comment = PositionGetString(POSITION_COMMENT);
            if(InpEnableMultiBaskets && !IsPositionInBasket(symbolIndex, comment))
               continue;
            // We count everything in the "Basket" logic
            if(StringFind(comment, "Grid") >= 0 || StringFind(comment, "Stack") >= 0 || StringFind(comment, "Zone") >= 0)
              {
               double p = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP) + GetPositionCommission(PositionGetInteger(POSITION_IDENTIFIER));
               basketNetProfit += p;
               activeTradeCount++; // Count this trade
              }
           }
        }
     }

// =======================================================
// --- 2. CONFIRM RECOVERY PAYMENT (LOCK IN) ---
// Logic: Only pay debt if we actually needed recovery logic (Count > 1)
// AND we hit the profit target.
// =======================================================
   if(UsePruningRecovery && SymbolData[symbolIndex].CurrentRecoveryPortion > 0)
     {
      Print(trackingSymbol, " Phase 2 Transition. Recovery Portion ($", DoubleToString(SymbolData[symbolIndex].CurrentRecoveryPortion, 2), ") will be reconciled on Close.");
      /*      double target = SymbolData[symbolIndex].GridTargetProfit;

            // Condition A: Did we make enough profit? (With small tolerance for slippage)
            bool profitMet = (basketNetProfit >= (target * 0.9));

            // Condition B: Did we actually use Recovery logic? (More than 1 trade)
            // If activeTradeCount == 1, it was just the initial entry running to profit (Impulse).
            bool recoveryUsed = (activeTradeCount > 1);

            if(profitMet && recoveryUsed)
              {
               // --- DEDUCT DEBT (Only if Recovery Used + Target Met) ---
               SymbolData[symbolIndex].AccumulatedPruningLoss -= SymbolData[symbolIndex].CurrentRecoveryPortion;

               // Safety clamp
               if(SymbolData[symbolIndex].AccumulatedPruningLoss < 0)
                  SymbolData[symbolIndex].AccumulatedPruningLoss = 0;

               Print(trackingSymbol, " Grid Target Reached! Debt Paid: $", DoubleToString(SymbolData[symbolIndex].CurrentRecoveryPortion, 2),
                     ". Remaining Debt: $", DoubleToString(SymbolData[symbolIndex].AccumulatedPruningLoss, 2));

               // --- ITERATION LOGIC ---
               if(SymbolData[symbolIndex].AccumulatedPruningLoss > 1.0)
                 {
                  // Only increment if NO pruning happened during this sequence
                  if(!SymbolData[symbolIndex].PruningOccurredThisSequence)
                    {
                     SymbolData[symbolIndex].RecoveryIteration++;
                     Print(symbol, " Clean Success! Increasing Recovery Speed -> Next Iteration: ", SymbolData[symbolIndex].RecoveryIteration);
                    }
                  else
                    {
                     Print(symbol, " Success (with Pruning). Keeping Recovery Speed at Base (Iteration 1).");
                    }
                 }
               else
                 {
                  SymbolData[symbolIndex].RecoveryIteration = 1; // Debt Cleared, Reset
                 }
              }
            else
              {
               // --- NO DEDUCTION ---
               if(!recoveryUsed)
                  Print(trackingSymbol, " Transitioned via Single Entry (Impulse). Debt preserved in Bank.");
               else
                  if(!profitMet)
                     Print(trackingSymbol, " Profit Target Missed ($", DoubleToString(basketNetProfit, 2), " < ", DoubleToString(target, 2), "). Debt preserved.");
              }
      */
      // Always reset current portion so we don't double count it or refund it later
      SymbolData[symbolIndex].CurrentRecoveryPortion = 0.0;
      // Reset Flag for next sequence
      //SymbolData[symbolIndex].PruningOccurredThisSequence = false;
     }

// ==================================================================
// --- FIX: ALWAYS CHECK BANK MERGER AFTER SUCCESS ---
// If the Main Bank is empty (or we just paid it off), pull from the Critical Bank.
// ==================================================================
   if(SymbolData[symbolIndex].AccumulatedCriticalLoss > 0)
     {
      // We allow merging if PruningBank is empty OR if we just want to consolidate.
      // Best practice: If Pruning Bank is empty, move Critical over immediately.
      if(SymbolData[symbolIndex].AccumulatedPruningLoss < 1.0) // "Empty" tolerance
        {
         double transferAmount = SymbolData[symbolIndex].AccumulatedCriticalLoss;
         SymbolData[symbolIndex].AccumulatedPruningLoss += transferAmount;
         SymbolData[symbolIndex].AccumulatedCriticalLoss = 0.0;

         Print(trackingSymbol, " 💥 Critical bank merge: transferred $", DoubleToString(transferAmount, 2),
               " to the main debt bank. Recovery restarts next cycle.");

         // Reset iteration to 1 to prevent aggressive multipliers immediately after taking a massive hit
         SymbolData[symbolIndex].RecoveryIteration = 1;
        }
     }
// ==================================================================


// OPTION A: Close Everything (Default)
   if(GridCloseOnTP)
     {
      Print(trackingSymbol, " Grid target reached but GridCloseOnTP=true, so Phase 2 trailing is bypassed and basket will close.");
      CloseAllGridPositions(symbolIndex, "Grid TP Reached - Closing All");
      SymbolData[symbolIndex].GridPhase1Active = false;
      SymbolData[symbolIndex].GridPhase2Active = false;
      ResetGridTracking(symbolIndex);
     }
// OPTION B: Secure and Trail (Basket SL Mode)
   else
     {
      // 1. Calculate grid basket metrics (Average Entry, etc.)
      CalculateGridBasket(symbolIndex);

      // 2. Set Basket SL to the Hit Price (Guarantees the GridTP_Amount)
      // Note: We use the stored GridTPHitPrice because that represents where we hit the dollar target.
      if(SymbolData[symbolIndex].GridTPHitPrice > 0)
        {
         SymbolData[symbolIndex].GridBasketStopLoss = SymbolData[symbolIndex].GridTPHitPrice;
        }
      else
        {
         // Fallback
         SymbolData[symbolIndex].GridBasketStopLoss = SymbolData[symbolIndex].GridBasketEntry; // Break Even fallback
        }

      // Normalize SL
      SymbolData[symbolIndex].GridBasketStopLoss = NormalizePrice(trackingSymbol, SymbolData[symbolIndex].GridBasketStopLoss);

      // 3. Set Phase Flags before applying protection.
      // Zone phase 2 only applies SL/TP while GridPhase2Active is true.
      SymbolData[symbolIndex].GridPhase1Active = false;
      SymbolData[symbolIndex].GridPhase2Active = true;

      // 4. Enable Trailing (Uses Standard Non-Grid settings)
      SymbolData[symbolIndex].GridInTrailing = UseTrailing;
      if(!UseTrailing)
         Print(trackingSymbol, " Grid Phase 2 secured, but trailing is disabled because UseTrailing=false.");
      // Enable Stacking (Uses Standard Non-Grid settings)
      SymbolData[symbolIndex].GridInStacking = (StackMode && UseTrailing);

      // 5. Apply Basket SL to all grid/zone positions
      UpdateAllGridStopLosses(symbolIndex);

      SymbolData[symbolIndex].PreviousBasketSL = SymbolData[symbolIndex].GridBasketStopLoss;
      SymbolData[symbolIndex].GridTrailUpdates = 0;

      // RESET GRID STACK COUNTER (CRITICAL for Stacking to work)
      SymbolData[symbolIndex].GridStack.Counter = 0;
      SymbolData[symbolIndex].GridStack.LastProcessedCounter = 0;
      SymbolData[symbolIndex].GridStack.SLMovedThisTick = false;

      Print(trackingSymbol, " Transitioned to Grid Phase 2 (Basket Secured at Hit Price)");
      Print("  - Basket SL: ", SymbolData[symbolIndex].GridBasketStopLoss);
      SmartHedge_OnProtectedStopMove(symbolIndex, true);
      SaveBasketRuntimeState(symbolIndex);
     }
  }

//+------------------------------------------------------------------+
//| Manage grid phase 2 positions - FIXED FOR BROKER CLOSE           |
//+------------------------------------------------------------------+
void ManageGridPhase2(int symbolIndex)
{
   string trackingSymbol = GetBaseSymbol(SymbolData[symbolIndex].symbol);

// 1. Calculate Open Volume (Live Check)
   double buyVol = 0;
   double sellVol = 0;
   int liveGridCount = 0; // Local count

   for(int i = 0; i < PositionsTotal(); i++)
     {
      if(PositionSelectByTicket(PositionGetTicket(i)))
        {
         if(PositionGetString(POSITION_SYMBOL) == trackingSymbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
           {
            string c = PositionGetString(POSITION_COMMENT);
            if(InpEnableMultiBaskets && !IsPositionInBasket(symbolIndex, c))
               continue;
            if(StringFind(c, "Grid") >= 0 || StringFind(c, "Stack") >= 0 || StringFind(c, "Zone") >= 0)
              {
               if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                  buyVol += PositionGetDouble(POSITION_VOLUME);
               else
                  sellVol += PositionGetDouble(POSITION_VOLUME);

               liveGridCount++;
              }
           }
        }
     }

// 2. DETECT BROKER CLOSURE (The Fix)
// If the logic thinks we have active levels (GridLevels > 0) but we find 0 live trades,
// it means the Broker (SL/TP) closed them between ticks.
   if(liveGridCount == 0 && SymbolData[symbolIndex].GridLevels > 0)
     {
      Print(trackingSymbol, " Phase 2: All trades disappeared (Broker Close). Processing Result...");

      // Calculate profit from History instead of Open Trades
      ProcessClosedSequence(symbolIndex);
      // FALSE = Do NOT skip reconciliation. Run history scan.
      ResetGridTracking(symbolIndex, true);

      // Reset Everything
      SymbolData[symbolIndex].GridPhase1Active = false;
      SymbolData[symbolIndex].GridPhase2Active = false;
      ResetGridTracking(symbolIndex);
      return;
     }

// 3. Normal Monitoring (Trades are still open)
   if(SymbolData[symbolIndex].GridInTrailing)
     {
      CheckGridTrailingConditions(symbolIndex); // 1. Calculate new SL
     }

// =============================================================================
// --- FIX START: CRITICAL ORDER OF OPERATIONS FOR STACKING ---
// =============================================================================
   // 2. Commit Pending SL -> Active SL (This sets 'GridSLMovedThisTick' to true)
   ApplyPendingTrail(symbolIndex);       

   // 3. Check Stacking (This reads 'GridSLMovedThisTick' and opens trades)
   CheckStackTradesOnTick(symbolIndex);  
// =============================================================================
// --- FIX END ---
// =============================================================================

   UpdateAllGridStopLosses(symbolIndex); // 4. Send new SL to Broker

// 4. Active Hard-Close Monitor (Bot-side trigger)
   bool basketHit = false;
   double currentBid = SymbolInfoDouble(trackingSymbol, SYMBOL_BID);
   double currentAsk = SymbolInfoDouble(trackingSymbol, SYMBOL_ASK);
   double basketSL = SymbolData[symbolIndex].GridBasketStopLoss;

   if(basketSL > 0)
     {
      if(buyVol >= sellVol)
        {
         if(currentBid <= basketSL)
            basketHit = true;
        }
      else
        {
         if(currentAsk >= basketSL)
            basketHit = true;
        }
     }

   if(basketHit)
     {
      if(HideSLTPDuringCloseBlock && G_Cache_IsDailyCloseBlock)
        { /* Block closure */ }
      else
        {
         Print(trackingSymbol, " BASKET SL HIT (Active Monitor). Closing Everything.");
      // This works because trades are still open
      CloseAllGridPositions(symbolIndex, "Basket SL Hit");

      SymbolData[symbolIndex].GridPhase1Active = false;
      SymbolData[symbolIndex].GridPhase2Active = false;
      ResetGridTracking(symbolIndex);
     }     
    }
}

//+------------------------------------------------------------------+
//| Check and calculate trailing stop conditions (Fixed Full Version)|
//+------------------------------------------------------------------+
void CheckGridTrailingConditions(int symbolIndex)
{
   string trackingSymbol = GetBaseSymbol(SymbolData[symbolIndex].symbol);
   if(trackingSymbol == "")
      trackingSymbol = SymbolData[symbolIndex].symbol;
   bool filterByBasket = InpEnableMultiBaskets;

   // --- FIX 1: SYMBOL SPECIFIC PRECISION ---
   // We must use the specific symbol's Point/Digits, not the Chart's.
   // This is critical for Cross-Pairs (e.g. trading CHFJPY on a USTEC chart).
   int symDigits = (int)SymbolInfoInteger(trackingSymbol, SYMBOL_DIGITS);
   double symPoint = SymbolInfoDouble(trackingSymbol, SYMBOL_POINT);
   // ----------------------------------------

// 1. Determine Net Direction
   double buyVolume = 0;
   double sellVolume = 0;
   bool foundAny = false;

   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetString(POSITION_SYMBOL) == trackingSymbol &&
            IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
           {
         string comment = PositionGetString(POSITION_COMMENT);
         if(filterByBasket && !IsPositionInBasket(symbolIndex, comment))
            continue;
            if(StringFind(comment, "Grid") >= 0 || StringFind(comment, "Zone") >= 0)
              {
               if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                  buyVolume += PositionGetDouble(POSITION_VOLUME);
               else
                  sellVolume += PositionGetDouble(POSITION_VOLUME);

               foundAny = true;
              }
           }
        }
     }

   if(!foundAny)
      return;

// The winning side is the one with more volume (or defaults to Buy if equal)
   ENUM_POSITION_TYPE trailDirection = (buyVolume >= sellVolume) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;

// 2. Setup Prices
   double currentPrice = (trailDirection == POSITION_TYPE_BUY) ?
                         SymbolInfoDouble(trackingSymbol, SYMBOL_BID) :
                         SymbolInfoDouble(trackingSymbol, SYMBOL_ASK);

   double currentSL = SymbolData[symbolIndex].GridBasketStopLoss;
   double newSL = currentSL;

// 3. Trailing Logic (ATR or BOX)
   if(TrailType == TRAIL_BOX)
     {
      if(trailDirection == POSITION_TYPE_BUY)
        {
         // BUY: Scan 'TrailBox_Levels' Segments. Pick LOWEST.
         int count = MathMin(SymbolData[symbolIndex].BoxLowCount, TrailBox_Levels);
         if(count > 0)
           {
            double safestLow = SymbolData[symbolIndex].BoxLow[0];
            for(int i = 1; i < count; i++)
              {
               if(SymbolData[symbolIndex].BoxLow[i] < safestLow)
                  safestLow = SymbolData[symbolIndex].BoxLow[i];
              }
            
            // Normalize Box Level before comparing
            safestLow = NormalizeDouble(safestLow, symDigits);

            // Trail Logic: Move UP
            // Logic: If current SL is 0 (First Run) OR SafestLow is better than Current SL
            if((currentSL == 0 || safestLow > currentSL) && safestLow < currentPrice)
               newSL = safestLow;
           }
        }
      else
        {
         // SELL: Scan 'TrailBox_Levels' Segments. Pick HIGHEST.
         int count = MathMin(SymbolData[symbolIndex].BoxHighCount, TrailBox_Levels);
         if(count > 0)
           {
            double safestHigh = SymbolData[symbolIndex].BoxHigh[0];
            for(int i = 1; i < count; i++)
              {
               if(SymbolData[symbolIndex].BoxHigh[i] > safestHigh)
                  safestHigh = SymbolData[symbolIndex].BoxHigh[i];
              }

            // Normalize Box Level before comparing
            safestHigh = NormalizeDouble(safestHigh, symDigits);

            // Trail Logic: Move DOWN
            // Logic: If current SL is 0 (First Run) OR SafestHigh is lower than Current SL
            if((currentSL == 0 || safestHigh < currentSL) && safestHigh > currentPrice)
               newSL = safestHigh;
           }
        }
     }
   else if(TrailType == TRAIL_ATR)
     {
      double atr[1];
      bool atrOk = false;
      double atrValue = 0.0;

      if(SymbolData[symbolIndex].ATR_Handle != INVALID_HANDLE &&
         CopyBuffer(SymbolData[symbolIndex].ATR_Handle, 0, 0, 1, atr) > 0 &&
         atr[0] > 0)
      {
         atrValue = atr[0];
         atrOk = true;
      }

      if(!atrOk)
      {
         long stopsLevelPoints = SymbolInfoInteger(trackingSymbol, SYMBOL_TRADE_STOPS_LEVEL);
         atrValue = MathMax(500 * symPoint, (stopsLevelPoints + 10) * symPoint);
         if(SymbolData[symbolIndex].GridPhase2Active && TimeCurrent() % 30 == 0)
            Print(trackingSymbol, " Warning: ATR unavailable for Phase 2 trail. Using point fallback distance ",
                  DoubleToString(atrValue, symDigits), ".");
      }

      double stepDist = MathMax(symPoint, atrValue * TrailATR_Update);
      double requiredDist = MathMax(symPoint, atrValue * TrailATR_Multiplier);

      if(trailDirection == POSITION_TYPE_BUY)
      {
         double candidateSL = NormalizeDouble(currentPrice - requiredDist, symDigits);
         if(currentSL == 0 || candidateSL > (currentSL + stepDist))
            newSL = candidateSL;
      }
      else
      {
         double candidateSL = NormalizeDouble(currentPrice + requiredDist, symDigits);
         if(currentSL == 0 || candidateSL < (currentSL - stepDist))
            newSL = candidateSL;
      }
      }

// 4. Submit Update
   // Ensure final value is normalized
   newSL = NormalizeDouble(newSL, symDigits);

   // Only update if value changed and is non-zero
   if(newSL != 0 && MathAbs(newSL - currentSL) > symPoint)
     {
      // Verify Logic Safety (Don't set SL on wrong side of price)
      bool safe = false;
      if(trailDirection == POSITION_TYPE_BUY && newSL < currentPrice) safe = true;
      if(trailDirection == POSITION_TYPE_SELL && newSL > currentPrice) safe = true;

      if(safe)
      {
         SymbolData[symbolIndex].PendingTrailSL = newSL;
         SymbolData[symbolIndex].HasPendingTrail = true;
      }
     }
}

//+------------------------------------------------------------------+
//| Update all grid/zone stop losses (FIXED: StopsLevel Safety Check)|
//+------------------------------------------------------------------+
void UpdateAllGridStopLosses(int symbolIndex)
{
   if(HideSLTPDuringCloseBlock && G_Cache_IsDailyCloseBlock) return;
   string trackingSymbol = GetBaseSymbol(SymbolData[symbolIndex].symbol);
   bool filterByBasket = InpEnableMultiBaskets;
   double gridBasketSL   = SymbolData[symbolIndex].GridBasketStopLoss;

   // If no Basket SL is defined yet, we cannot update anything.
   if(gridBasketSL == 0)
      return;

   double validLevel = NormalizePrice(trackingSymbol, gridBasketSL);
   double bid = SymbolInfoDouble(trackingSymbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(trackingSymbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(trackingSymbol, SYMBOL_POINT);

   // --- FIX: GET BROKER STOPS LEVEL ---
   // Get the minimum distance required by broker (in points)
   long stopsLevelPoints = SymbolInfoInteger(trackingSymbol, SYMBOL_TRADE_STOPS_LEVEL);
   // Add a small safety buffer (e.g., 2 points) to prevent borderline rejections
   double minDistance = (stopsLevelPoints + 2) * point; 
   // -----------------------------------

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == trackingSymbol &&
            IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
         {
         string comment = PositionGetString(POSITION_COMMENT);
         if(filterByBasket && !IsPositionInBasket(symbolIndex, comment))
            continue;
            // Check if trade belongs to our basket system
            if(StringFind(comment, "Grid") >= 0 || StringFind(comment, "Stack") >= 0 || StringFind(comment, "Zone") >= 0)
            {
               double currentSL = PositionGetDouble(POSITION_SL);
               double currentTP = PositionGetDouble(POSITION_TP);
               ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

               double newSL = currentSL;
               double newTP = currentTP;
               bool modify = false;

               // =================================================================
               // LOGIC FOR GRID MODE (Same Direction Basket)
               // =================================================================
               if(RiskMode == RISK_MODE_GRID)
               {
                  // In standard Grid Mode, all trades are usually in the same direction.
                  // The Basket SL serves as the HARD EXIT for everything.
                  
                  // --- SAFETY CHECK ---
                  // Only modify if price is far enough away
                  double dist = (type == POSITION_TYPE_BUY) ? (bid - validLevel) : (validLevel - ask);
                  
                  // We only update if the SL is "below" price for Buy or "above" price for Sell
                  // AND the distance is valid.
                  if(dist > minDistance) 
                  {
                      if(MathAbs(currentSL - validLevel) > point)
                     {
                        newSL = validLevel;
                        modify = true;
                     }
                  }
               }
               // =================================================================
               // LOGIC FOR ZONE RECOVERY (Phase 2 - Hedged Basket)
               // =================================================================
               else if(RiskMode == RISK_MODE_ZONE_RECOVERY && SymbolData[symbolIndex].GridPhase2Active)
               {
                  // In Zone Phase 2, we have Buys AND Sells.
                  // The Basket SL is a specific price level (Price X).
                  
                  if(type == POSITION_TYPE_BUY)
                  {
                     // BUY: If Level < Bid, it's an SL.
                     if(validLevel < bid)
                     {
                        // Check distance: Bid must be higher than SL by minDistance
                        if((bid - validLevel) > minDistance)
                        {
                            if(MathAbs(currentSL - validLevel) > point)
                           {
                              newSL = validLevel;
                              modify = true;
                           }
                        }
                     }
                     // BUY: If Level > Bid, it's a TP.
                     else 
                     {
                        // Check distance: Level must be higher than Bid by minDistance
                        if((validLevel - bid) > minDistance)
                        {
                            if(MathAbs(currentTP - validLevel) > point)
                           {
                              newTP = validLevel;
                              modify = true;
                           }
                        }
                     }
                  }
                  else // SELL
                  {
                     // SELL: If Level > Ask, it's an SL.
                     if(validLevel > ask)
                     {
                        // Check distance: SL must be higher than Ask by minDistance
                        if((validLevel - ask) > minDistance)
                        {
                            if(MathAbs(currentSL - validLevel) > point)
                           {
                              newSL = validLevel;
                              modify = true;
                           }
                        }
                     }
                     // SELL: If Level < Ask, it's a TP.
                     else
                     {
                        // Check distance: Ask must be higher than Level by minDistance
                        if((ask - validLevel) > minDistance)
                        {
                            if(MathAbs(currentTP - validLevel) > point)
                           {
                              newTP = validLevel;
                              modify = true;
                           }
                        }
                     }
                  }
               }

               // =================================================================
               // EXECUTE MODIFICATION
               // =================================================================
                if(modify)
                {
                   ResetLastError();
                   if(!Trade.PositionModify(ticket, newSL, newTP))
                   {
                      Print(trackingSymbol, " Phase 2 SL/TP modify failed. Ticket=", ticket,
                            " SL=", DoubleToString(newSL, (int)SymbolInfoInteger(trackingSymbol, SYMBOL_DIGITS)),
                            " TP=", DoubleToString(newTP, (int)SymbolInfoInteger(trackingSymbol, SYMBOL_DIGITS)),
                            " Bid=", DoubleToString(bid, (int)SymbolInfoInteger(trackingSymbol, SYMBOL_DIGITS)),
                            " Ask=", DoubleToString(ask, (int)SymbolInfoInteger(trackingSymbol, SYMBOL_DIGITS)),
                            " MinDistance=", DoubleToString(minDistance, (int)SymbolInfoInteger(trackingSymbol, SYMBOL_DIGITS)),
                            " Retcode=", Trade.ResultRetcode(),
                            " Error=", _LastError);
                   }
                }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Close all grid/zone/stack positions for symbol                   |
//+------------------------------------------------------------------+
void CloseAllGridPositions(int symbolIndex, string reason)
  {
   string symbol = GetBaseSymbol(SymbolData[symbolIndex].symbol);
   double basketNetProfit = 0.0;
   bool hasTrades = false;
   bool allowBlockingWait = MBP_ShouldAllowBlockingTradeWait(reason);

// 1. Calculate Profit Snapshot (For Manual/Bot Closes)
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionSelectByTicket(PositionGetTicket(i)))
        {
         if(PositionGetString(POSITION_SYMBOL) == symbol && IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
           {
            string c = PositionGetString(POSITION_COMMENT);
            if(InpEnableMultiBaskets && !IsPositionInBasket(symbolIndex, c))
               continue;
            if(StringFind(c, "Grid") >= 0 || StringFind(c, "Stack") >= 0 || StringFind(c, "Zone") >= 0)
              {
               basketNetProfit += (PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP) + GetPositionCommission(PositionGetInteger(POSITION_IDENTIFIER)));
               hasTrades = true;
              }
           }
        }
     }

// 2. APPLY DEBT LOGIC (Immediate Application)
   if(UsePruningRecovery && hasTrades)
     {      
      if(StringFind(reason, "Hard Pruning") >= 0)
        {
         // Flag that pruning occurred. Reconcile will see this and route the loss to Pruning Bank.
         SymbolData[symbolIndex].PruningOccurredThisSequence = true;
         SymbolData[symbolIndex].RecoveryIteration = 1; // Reset iteration on failure
        }
     }

// 3. Close Trades
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetString(POSITION_SYMBOL) == symbol && IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
           {
            string comment = PositionGetString(POSITION_COMMENT);
            if(InpEnableMultiBaskets && !IsPositionInBasket(symbolIndex, comment))
               continue;
            if(StringFind(comment, "Grid") >= 0 || StringFind(comment, "Stack") >= 0 || StringFind(comment, "Zone") >= 0)
              {
               bool protectedTicket = SmartHedge_IsProtectedTicket(ticket);
               if(Trade.PositionClose(ticket))
                 {
                  if(!protectedTicket && IsBridgeRuntimeEnabled())
                     SmartHedge_QueueSlaveClose(ticket, symbol);
                 }
              }

           }
        }
     }
   // Give the broker/server time to write the closed deals to history.
   // Without this, Reconcile() runs too fast and misses the losses.
   if(hasTrades && allowBlockingWait)
      Sleep(1000); 
   // 4. Reset Logic & Debt Bank Protection
   bool skipReconciliation = !allowBlockingWait;

   // ONLY wipe the debt if the Bridge is ON and a Master limit/reset was triggered
   if(IsBridgeRuntimeEnabled() && (StringFind(reason, "Limit Hit") >= 0 || StringFind(reason, "Master Reset") >= 0 || StringFind(reason, "Global Close") >= 0))
     {
      skipReconciliation = true;
      
      // Explicitly wipe the recovery banks so tomorrow is a 100% clean slate
      SymbolData[symbolIndex].AccumulatedPruningLoss = 0.0;
      SymbolData[symbolIndex].AccumulatedCriticalLoss = 0.0;
      SymbolData[symbolIndex].RecoveryIteration = 1;
      
      Print(symbol, " [SYSTEM CLEARED] Master Limit Hit (Bridge ON). Debt Banks wiped to prevent revenge trading.");
     }
     
   // Call ResetGridTracking (Will skip history scan if skipReconciliation is true)
   ResetGridTracking(symbolIndex, skipReconciliation);
   }
  
//+------------------------------------------------------------------+
//| ResetGridTracking - UPDATED with Timestamp Protection            |
//+------------------------------------------------------------------+
void ResetGridTracking(int symbolIndex, bool skipReconciliation = false)
  {
   // 1. Reconcile (Only if not skipped AND not poisoned)
   if(!skipReconciliation)
     {
      // If Poisoned, Reconcile will auto-abort anyway, but skipping check saves a function call.
      if(SymbolData[symbolIndex].LastGridReset <= TimeCurrent())
      {
         if(SymbolData[symbolIndex].GridLevels > 0 || SymbolData[symbolIndex].GridPhase2Active)
         {
            ReconcileSequenceFromHistory(symbolIndex);
         }
      }
     }

   // 2. Standard Resets
   SymbolData[symbolIndex].GridLevels = 0;
   SymbolData[symbolIndex].GridBasketVolume = 0.0;
   SymbolData[symbolIndex].GridBasketEntry = 0.0;
   SymbolData[symbolIndex].GridBasketStopLoss = 0.0;
   SymbolData[symbolIndex].GridBasketTakeProfit = 0.0;
   SymbolData[symbolIndex].GridTargetReached = false;
   SymbolData[symbolIndex].GridInTrailing = false;
   SymbolData[symbolIndex].GridInStacking = false;
   SymbolData[symbolIndex].GridPhase1Active = false;
   SymbolData[symbolIndex].GridPhase2Active = false;
   SymbolData[symbolIndex].CurrentGridSequence = 0;

   SymbolData[symbolIndex].GridEntries[0] = 0.0;
   for(int i = 0; i < 100; i++)
      SymbolData[symbolIndex].GridEntries[i] = 0.0;

   SymbolData[symbolIndex].GridStackLevels = 0;
   SymbolData[symbolIndex].GridTrailUpdates = 0;
   SymbolData[symbolIndex].RawNextGridLot = 0.0;
   SymbolData[symbolIndex].LastUsedGridRawLot = 0.0;
   SymbolData[symbolIndex].RawNextStackLot = 0.0;
   SymbolData[symbolIndex].LastUsedStackRawLot = 0.0;

   SymbolData[symbolIndex].GridTPHit = false;
   SymbolData[symbolIndex].GridTPHitPrice = 0;
   SymbolData[symbolIndex].GridSequenceDepth = 0;

   SymbolData[symbolIndex].ZoneTopPrice = 0.0;
   SymbolData[symbolIndex].ZoneBottomPrice = 0.0;
   SymbolData[symbolIndex].ZoneActive = false;
   SymbolData[symbolIndex].ZoneSeqCount = 0;
   SymbolData[symbolIndex].ZoneResolved = false;

   SymbolData[symbolIndex].CurrentRecoveryPortion = 0.0;
   SymbolData[symbolIndex].PruningOccurredThisSequence = false;
   SmartHedge_ResetSymbol(symbolIndex);
   
   // 3. CRITICAL: UPDATE TIMESTAMP SAFELY
   // Only update LastGridReset if it is NOT in the future.
   // If it IS in the future (poisoned), keep it that way to blind the logic from the crash.
   if(SymbolData[symbolIndex].LastGridReset <= TimeCurrent())
   {
      SymbolData[symbolIndex].LastGridReset = TimeCurrent();
   }

   ClearBasketRuntimeState(symbolIndex);
  }

//+------------------------------------------------------------------+
//| Check Zone Recovery Logic (Delayed Recovery + Target Math)       |
//+------------------------------------------------------------------+
void CheckZoneRecovery(int symbolIndex)
  {
  // 1. GLOBAL COOLDOWN BLOCK
   if(IsGlobalCooldownActive()) return;
   
   // ---------------------------------------------------------
   // 2. BRIDGE SAFETY CHECK (BLOCK RECOVERY HEDGES)
   // ---------------------------------------------------------
   if(IsBridgeRuntimeEnabled())
   {
      string stopVar = InpHedgeChannel + "_STOP_FLAG";
      // Prevent opening a new Hedge leg if the bridge is blocked
      if(GlobalVariableCheck(stopVar)) 
      {
         if(GlobalVariableGet(stopVar) > 0.1) 
         {
             // Optional: Print once to debug
             // Print("? ZONE RECOVERY BLOCKED by Hedge Master.");
             return;
         }
      }
   }
   // ---------------------------------------------------------
   
   if(SymbolData[symbolIndex].GridPhase2Active)
      return;

   string symbol = SymbolData[symbolIndex].symbol;
   string execSymbol = GetBaseSymbol(symbol);

// Safety: Ensure Zone Levels exist
   if(SymbolData[symbolIndex].ZoneTopPrice == 0)
     {
      SymbolData[symbolIndex].ZoneActive = false;
      ObjectDelete(0, BasketScopedObjectName(symbolIndex, "ZoneTop_", execSymbol));
      ObjectDelete(0, BasketScopedObjectName(symbolIndex, "ZoneBot_", execSymbol));
      return;
     }

// Visuals
   if(SymbolData[symbolIndex].ZoneActive)
     {
      DrawGridLine(BasketScopedObjectName(symbolIndex, "ZoneTop_", execSymbol), SymbolData[symbolIndex].ZoneTopPrice, clrGreen);
      DrawGridLine(BasketScopedObjectName(symbolIndex, "ZoneBot_", execSymbol), SymbolData[symbolIndex].ZoneBottomPrice, clrRed);
     }

   double bid = SymbolInfoDouble(execSymbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(execSymbol, SYMBOL_ASK);

   ENUM_POSITION_TYPE lastType = POSITION_TYPE_BUY;
   datetime lastTime = 0;

// Find Last Trade Type
   for(int i=0; i<PositionsTotal(); i++)
     {
      if(PositionSelectByTicket(PositionGetTicket(i)))
        {
         if(PositionGetString(POSITION_SYMBOL) == execSymbol && IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
           {
            string comment = PositionGetString(POSITION_COMMENT);
            if(InpEnableMultiBaskets && !IsPositionInBasket(symbolIndex, comment))
               continue;
            if((datetime)PositionGetInteger(POSITION_TIME) > lastTime)
              {
               lastTime = (datetime)PositionGetInteger(POSITION_TIME);
               lastType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
              }
           }
        }
     }

   if(TimeCurrent() - lastTime < 2)
      return;

// Helper to identify if this is the transition from Entry -> Zone (First Hedge)
// Logic: If ZoneActive is false (Entry only) OR ZoneSeqCount is 1 (Entry Only)
   bool isFirstHedgeTrigger = (!SymbolData[symbolIndex].ZoneActive || SymbolData[symbolIndex].ZoneSeqCount == 1);

// ---------------------------------------------------------
// TRIGGER LOGIC
// ---------------------------------------------------------

   bool triggerBuy = (ask >= SymbolData[symbolIndex].ZoneTopPrice && lastType == POSITION_TYPE_SELL);
   bool triggerSell = (bid <= SymbolData[symbolIndex].ZoneBottomPrice && lastType == POSITION_TYPE_BUY);

   if(triggerBuy || triggerSell)
     {
      if(!CheckSpread(symbolIndex))
         return; // Spread Filter

      ENUM_ORDER_TYPE orderType = triggerBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

      // A. PRUNE FIRST (if limit reached)
      // Note: ManageZonePruning resets RecoveryIteration to 1 if it prunes.
      double prunedLoss = ManageZonePruning(symbolIndex, orderType);

      // B. CALCULATE TARGET & DEBT (Only on First Hedge of the Sequence)
      // This logic sets the "Goal" for the entire zone sequence.
      if(isFirstHedgeTrigger)
        {
         double portion = 0.0;

         if(UsePruningRecovery && SymbolData[symbolIndex].AccumulatedPruningLoss > 0)
           {
            // 1. Determine Multiplier (Iteration)
            double mult = SymbolData[symbolIndex].RecoveryIteration;

            // 2. Calculate Percentage
            double pct = PruningRecovPercent * mult;
            if(pct > 100.0)
               pct = 100.0;

            // 3. Calculate Amount
            portion = SymbolData[symbolIndex].AccumulatedPruningLoss * (pct / 100.0);
            if(portion < 0.01)
               portion = SymbolData[symbolIndex].AccumulatedPruningLoss; // Clear small remainders

            // 4. DO NOT DEDUCT YET - Just Allocate
            // We leave the debt in the bank. It will be deducted in TransitionToGridPhase2.

            Print(execSymbol, " 🎯 Recovery target set. Iteration: ", (int)mult,
                  " | Portion allocated: $", DoubleToString(portion, 2),
                  " | Pending deduction on success.");
           }

         // 5. Set The Fixed Target Profit for this Sequence
         // --- NEW: Calculate Dynamic Target for Zone ---
         double dynamicTarget = GetDynamicProfitTarget(symbolIndex);
         SymbolData[symbolIndex].CurrentRecoveryPortion = portion;
         SymbolData[symbolIndex].GridTargetProfit = dynamicTarget + portion;

         // Ensure Zone Active Flag is Set
         SymbolData[symbolIndex].ZoneActive = true;
         SaveBasketRuntimeState(symbolIndex);
        }

      // C. CALCULATE LOT SIZE
      // We pass the NEXT order type to solve for the lot size that achieves the target
      double lot = CalculateZoneRecoveryLot(symbolIndex, orderType);

      Print(execSymbol, " Zone Trigger! Opening ", EnumToString(orderType), " | Calc Lot: ", lot);

      // D. EXECUTE
      OpenTrade(symbolIndex, orderType, lot);
      // ZoneSeqCount is advanced inside OpenTrade on a successful zone leg.

      // Balance Check
      EnforceVolumeBalance(symbolIndex, (triggerBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL));
     }

   CheckZoneTarget(symbolIndex);
  }

//+------------------------------------------------------------------+
//| Check Zone Target (Impulse Mark & Wait + Phase 2 Transition)     |
//+------------------------------------------------------------------+
void CheckZoneTarget(int symbolIndex)
  {
   if(SymbolData[symbolIndex].GridPhase2Active)
      return;

// --- SPREAD FILTER ---
   if(!CheckSpread(symbolIndex))
      return;
// ---------------------

   string trackingSymbol = GetBaseSymbol(SymbolData[symbolIndex].symbol);
   double totalProfit = 0;
   double buyVolume = 0;
   double sellVolume = 0;
   int tradeCount = 0;

// Variables for Impulse Logic
   double initialEntryPrice = 0;
   ENUM_POSITION_TYPE initialType = POSITION_TYPE_BUY;

   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetString(POSITION_SYMBOL) == trackingSymbol && IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
           {
            string comment = PositionGetString(POSITION_COMMENT);
            if(InpEnableMultiBaskets && !IsPositionInBasket(symbolIndex, comment))
               continue;
            if(StringFind(comment, "Zone") >= 0)
              {
               ulong posID = PositionGetInteger(POSITION_IDENTIFIER);
               double p = PositionGetDouble(POSITION_PROFIT);
               double s = PositionGetDouble(POSITION_SWAP);
               double c = GetPositionCommission(posID);
               totalProfit += (p + s + c);
               tradeCount++;

               ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
               double vol = PositionGetDouble(POSITION_VOLUME);
               double entry = PositionGetDouble(POSITION_PRICE_OPEN);

               if(type == POSITION_TYPE_BUY)
                  buyVolume += vol;
               if(type == POSITION_TYPE_SELL)
                  sellVolume += vol;

               // Capture initial trade data
               initialEntryPrice = entry;
               initialType = type;
              }
           }
        }
     }

   if(tradeCount == 0)
     {
      if(SymbolData[symbolIndex].ZoneActive)
        {
         SymbolData[symbolIndex].ZoneActive = false;
         ObjectDelete(0, BasketScopedObjectName(symbolIndex, "ZoneTop_", trackingSymbol));
         ObjectDelete(0, BasketScopedObjectName(symbolIndex, "ZoneBot_", trackingSymbol));
        }
      return;
     }

   double currentPrice = SymbolInfoDouble(trackingSymbol, SYMBOL_BID); // Default to Bid
   if(initialType == POSITION_TYPE_SELL)
      currentPrice = SymbolInfoDouble(trackingSymbol, SYMBOL_ASK);

   bool readyToTransition = false;
   bool winningIsBuy = (buyVolume >= sellVolume);

// =======================================================================
// LOGIC A: INITIAL TRADE (Mark Price X -> Wait for Buffer)
// =======================================================================
   if(SymbolData[symbolIndex].ZoneSeqCount == 1)
     {
      double atr[1];
      double atrValue = 0;
      if(CopyBuffer(SymbolData[symbolIndex].ATR_Handle, 0, 0, 1, atr) > 0)
         atrValue = atr[0];
      if(atrValue == 0)
         atrValue = SymbolInfoDouble(trackingSymbol, SYMBOL_POINT) * 50;

      // 1. Calculate Distances
      double impulseDist = atrValue * ZoneImpulseATR;
      double bufferDist  = 0.0;

      // Calculate Buffer (ATR or Points) based on ZoneTransitionDist input
      // Note: Assuming logic similar to GridTransitionType exists, or defaulting to ATR
      if(ZoneTransitionDist > 0)
         bufferDist = atrValue * ZoneTransitionDist;
      else
         bufferDist = 50 * SymbolInfoDouble(trackingSymbol, SYMBOL_POINT); // Fallback

      // 2. Determine "Price X" (The Impulse Trigger Price)
      double priceX = 0.0;
      if(initialType == POSITION_TYPE_BUY)
         priceX = initialEntryPrice + impulseDist;
      else
         priceX = initialEntryPrice - impulseDist;

      // 3. STEP 1: MARK PRICE X (If not already marked)
      if(!SymbolData[symbolIndex].GridTPHit)
        {
         bool hitX = (initialType == POSITION_TYPE_BUY && currentPrice >= priceX) ||
                     (initialType == POSITION_TYPE_SELL && currentPrice <= priceX);

         if(hitX)
           {
            SymbolData[symbolIndex].GridTPHit = true;
            SymbolData[symbolIndex].GridTPHitPrice = priceX; // Lock SL exactly at Price X
            SaveBasketRuntimeState(symbolIndex);
            //Print(trackingSymbol, " Zone Impulse Hit at ", priceX, ". Waiting for Buffer (", DoubleToString(bufferDist/_Point,0), " pts)...");
           }
        }

      // 4. STEP 2: CHECK BUFFER (If Marked)
      if(SymbolData[symbolIndex].GridTPHit)
        {
         bool bufferCleared = false;
         double triggerPrice = 0.0;

         if(initialType == POSITION_TYPE_BUY)
           {
            triggerPrice = SymbolData[symbolIndex].GridTPHitPrice + bufferDist;
            if(currentPrice >= triggerPrice)
               bufferCleared = true;
           }
         else
           {
            triggerPrice = SymbolData[symbolIndex].GridTPHitPrice - bufferDist;
            if(currentPrice <= triggerPrice)
               bufferCleared = true;
           }

         if(bufferCleared)
           {
            readyToTransition = true;
            Print(trackingSymbol, " Zone Buffer Cleared! Locking SL at Price X.");
           }
        }
     }
// =======================================================================
// LOGIC B: RECOVERY MODE (Standard Dollar Target)
// =======================================================================
   else
     {
      if(totalProfit >= SymbolData[symbolIndex].GridTargetProfit)
        {
         if(ZoneCloseOnTP)
           {
            // ... (Existing Close Logic) ...
            Print(trackingSymbol, " Zone TP Hit ($", totalProfit, ") - Closing All.");
            CloseAllGridPositions(symbolIndex, "Zone TP Hit");
            SymbolData[symbolIndex].ZoneActive = false;
            SymbolData[symbolIndex].ZoneResolved = true;
            // Clear objects...
            ObjectDelete(0, BasketScopedObjectName(symbolIndex, "ZoneTop_", trackingSymbol));
            ObjectDelete(0, BasketScopedObjectName(symbolIndex, "ZoneBot_", trackingSymbol));

            // Clean up debt tracking
            if(UsePruningRecovery && SymbolData[symbolIndex].CurrentRecoveryPortion > 0)
              {
               SymbolData[symbolIndex].AccumulatedPruningLoss -= SymbolData[symbolIndex].CurrentRecoveryPortion;
               if(SymbolData[symbolIndex].AccumulatedPruningLoss < 0)
                  SymbolData[symbolIndex].AccumulatedPruningLoss = 0;
               SymbolData[symbolIndex].CurrentRecoveryPortion = 0.0;
               if(SymbolData[symbolIndex].AccumulatedPruningLoss > 1.0)
                  SymbolData[symbolIndex].RecoveryIteration++;
               else
                  SymbolData[symbolIndex].RecoveryIteration = 1;
              }
            return;
           }
         else
           {
            // Transition Logic for Recovery (Uses standard Dollar Hit -> Buffer)
            if(!SymbolData[symbolIndex].GridTPHit)
              {
               SymbolData[symbolIndex].GridTPHit = true;
               SymbolData[symbolIndex].GridTPHitPrice = currentPrice; // Here we lock at CURRENT price because it's dollar based
               SaveBasketRuntimeState(symbolIndex);
               Print(trackingSymbol, " Zone Recovery TP Met. Marked Price: ", currentPrice);
              }

            double point = SymbolInfoDouble(trackingSymbol, SYMBOL_POINT);
            double buffer = 50 * point;
            double atr[1];
            if(ZoneTransitionDist > 0 && CopyBuffer(SymbolData[symbolIndex].ATR_Handle, 0, 0, 1, atr) > 0 && atr[0] > 0)
               buffer = atr[0] * ZoneTransitionDist;

            if(winningIsBuy && currentPrice >= (SymbolData[symbolIndex].GridTPHitPrice + buffer))
               readyToTransition = true;
            if(!winningIsBuy && currentPrice <= (SymbolData[symbolIndex].GridTPHitPrice - buffer))
               readyToTransition = true;
           }
        }
     }

// =======================================================================
// EXECUTE TRANSITION
// =======================================================================
   if(readyToTransition)
     {
      Print(trackingSymbol, " 🔄 Zone phase 2 transition.");

      // Note: TransitionToGridPhase2 uses SymbolData[symbolIndex].GridTPHitPrice as the SL.
      // In Logic A, we set this to "Price X" (Entry + Impulse).
      // In Logic B, we set this to "TP Hit Price".

      TransitionToGridPhase2(symbolIndex);

      // Cleanup Zone Specifics
      SymbolData[symbolIndex].ZoneActive = false;
      ObjectDelete(0, BasketScopedObjectName(symbolIndex, "ZoneTop_", trackingSymbol));
      ObjectDelete(0, BasketScopedObjectName(symbolIndex, "ZoneBot_", trackingSymbol));
      SaveBasketRuntimeState(symbolIndex);
     }
  }

//+------------------------------------------------------------------+
//| Manage Zone Pruning (Updated: Smart Routing & Hard/Soft Logic)   |
//+------------------------------------------------------------------+
double ManageZonePruning(int symbolIndex, ENUM_ORDER_TYPE pendingOrderType)
  {
   // 1. Safety Check: Is pruning enabled globally?
   if(!UseGridPruning) return 0.0;

   // 2. Count Trades: Have we reached the user-defined limit?
   // 'true' in CountGridPositions ensures we only count Grid/Zone trades, not Manual ones.
   int currentCount = CountGridPositions(symbolIndex, true);
   
   // If we haven't hit the limit (PruningLevel), do nothing.
   if(currentCount < PruningLevel) return 0.0;

   string execSymbol = GetBaseSymbol(SymbolData[symbolIndex].symbol);

   // =================================================================================
   // CASE A: SOFT PRUNING (FIFO / Strategic Reduction)
   // Logic: Close only the single largest losing trade in the opposite direction
   // to free up margin and reduce exposure without killing the whole sequence.
   // =================================================================================
   if(PruningStyle == PRUNING_SOFT)
     {
      // Determine the target direction to prune.
      // If we are placing a BUY pending order, we look to prune a SELL (and vice versa).
      ENUM_POSITION_TYPE targetType = (pendingOrderType == ORDER_TYPE_BUY) ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;
      
      ulong targetTicket = 0;
      double maxVol = -1.0;
      double targetNetProfit = 0.0;

      // Scan positions backwards (standard safety practice when working with lists)
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(ticket))
           {
            // Filter: Must match Symbol and Magic Number
            if(PositionGetString(POSITION_SYMBOL) == execSymbol && IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
              {
               string c = PositionGetString(POSITION_COMMENT);
               if(InpEnableMultiBaskets && !IsPositionInBasket(symbolIndex, c))
                  continue;
               // Filter: Must be part of the Zone or Grid strategy
               if(StringFind(c, "Zone") >= 0 || StringFind(c, "Grid") >= 0)
                 {
                  // Filter: Must match the opposite direction we determined above
                  if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == targetType)
                    {
                     // Heuristic: Find the trade with the largest Volume (Lot Size)
                     // This frees up the most margin.
                     double v = PositionGetDouble(POSITION_VOLUME);
                     if(v > maxVol)
                       {
                        maxVol = v;
                        targetTicket = ticket;
                        // Calculate Net Profit (Swap + Commission + Profit)
                        targetNetProfit = PositionGetDouble(POSITION_PROFIT) + 
                                          PositionGetDouble(POSITION_SWAP) + 
                                          GetPositionCommission(PositionGetInteger(POSITION_IDENTIFIER));
                       }
                    }
                 }
              }
           }
        }

      // If a suitable candidate was found, close it.
      if(targetTicket > 0)
        {
         Print(execSymbol, " Soft Pruning (Zone): Closing Largest Opposite Trade: #", targetTicket);
         
         if(Trade.PositionClose(targetTicket))
           {
            // Calculate the realized loss to add to the recovery bank
            double realizedLoss = (targetNetProfit < 0) ? MathAbs(targetNetProfit) : 0.0;
            
            if(UsePruningRecovery && realizedLoss > 0)
              {
               // Add loss to the Pruning Bank
               SymbolData[symbolIndex].AccumulatedPruningLoss += realizedLoss;
               
               // Reset iteration to 1 to ensure the next recovery trade isn't too aggressive immediately
               SymbolData[symbolIndex].RecoveryIteration = 1; 
               SymbolData[symbolIndex].PruningOccurredThisSequence = true;
              }
            return realizedLoss;
           }
        }
     }
   
   // =================================================================================
   // CASE B: HARD PRUNING (Reset / Wipeout)
   // Logic: The Zone has grown too large. Close ALL trades in this sequence, 
   // bank the total loss, and wait for a fresh entry signal.
   // =================================================================================
   else 
     {
      Print(execSymbol, " ⚠️ Hard zone pruning triggered.");
      
      // 1. Close Everything
      // We pass the specific reason "Hard Pruning".
      // The updated CloseAllGridPositions function detects this string and automatically
      // routes the loss to 'AccumulatedPruningLoss' instead of 'AccumulatedCriticalLoss'.
      // This prevents the "Double Counting" issue.
      CloseAllGridPositions(symbolIndex, "Hard Pruning (Zone Limit)");
      
      // 2. Return 0.0 
      // We return 0 here because the accounting is handled inside CloseAllGridPositions.
      // Returning a value here is only necessary if the caller needs to know the specific
      // loss amount immediately, but for the logic flow, the side-effects are already handled.
      return 0.0;
     }

   return 0.0;
  }
  
//+------------------------------------------------------------------+
//| Enforce Volume Balance for Zone Recovery                         |
//| Ensures the last trade direction has more volume than the opposite|
//+------------------------------------------------------------------+
void EnforceVolumeBalance(int symbolIndex, ENUM_POSITION_TYPE winningDirection)
  {
// 1. Check Spread Condition first
   if(!CheckSpread(symbolIndex))
     {
      Print("Volume Correction Skipped: Spread too high.");
      return;
     }

   string execSymbol = GetBaseSymbol(SymbolData[symbolIndex].symbol);
   double winningVol = 0.0;
   double losingVol  = 0.0;

// 2. Calculate Current Volumes
   for(int i = 0; i < PositionsTotal(); i++)
     {
      if(PositionSelectByTicket(PositionGetTicket(i)))
        {
         if(PositionGetString(POSITION_SYMBOL) == execSymbol && IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
           {
            string c = PositionGetString(POSITION_COMMENT);
            if(InpEnableMultiBaskets && !IsPositionInBasket(symbolIndex, c))
               continue;
            if(StringFind(c, "Zone") >= 0)
              {
               double v = PositionGetDouble(POSITION_VOLUME);
               if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == winningDirection)
                  winningVol += v;
               else
                  losingVol += v;
              }
           }
        }
     }

// 3. Check Imbalance
// We want Winning Side > Losing Side.
// If Winning <= Losing, we must shed weight from the losing side.
   if(winningVol <= losingVol)
     {
      Print("⚠️ Zone imbalance detected.");
      Print("Winning (", EnumToString(winningDirection), ") Vol: ", winningVol, " | Losing Vol: ", losingVol);
      Print("Correcting balance by closing smallest opposite trades...");

      int maxLoops = 20; // Safety break

      while(winningVol <= losingVol && maxLoops > 0)
        {
         ulong smallestTicket = 0;
         double smallestVol = 999999.0;

         // Find smallest trade on the LOSING side
         for(int i = 0; i < PositionsTotal(); i++)
           {
            ulong t = PositionGetTicket(i);
            if(PositionSelectByTicket(t))
              {
               if(PositionGetString(POSITION_SYMBOL) == execSymbol && IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
                 {
                  string c = PositionGetString(POSITION_COMMENT);
                  if(InpEnableMultiBaskets && !IsPositionInBasket(symbolIndex, c))
                     continue;
                  // Only target Zone trades on the opposite side
                  if(StringFind(c, "Zone") >= 0 && (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != winningDirection)
                    {
                     double v = PositionGetDouble(POSITION_VOLUME);
                     if(v < smallestVol)
                       {
                        smallestVol = v;
                        smallestTicket = t;
                       }
                    }
                 }
              }
           }

         // Execute Close
         if(smallestTicket > 0)
           {
            if(Trade.PositionClose(smallestTicket))
              {
               Print("Closed adjustment trade: ", smallestTicket, " (", smallestVol, " lots)");
               losingVol -= smallestVol; // Update local tracker
               if(MBP_ShouldAllowBlockingTradeWait("adjustment_close"))
                  Sleep(100); // Small delay for broker sync
              }
            else
              {
               Print("Failed to close adjustment trade: ", GetLastError());
               break; // Stop if we can't close
              }
           }
         else
           {
            break; // No more trades found to close
           }

         maxLoops--;
        }

      Print("Volume Correction Complete. New Status -> Win: ", winningVol, " vs Lose: ", losingVol);
     }
  }

//+------------------------------------------------------------------+
//| Check stack trades on tick (FIXED: Removed TrailLocked Block)    |
//+------------------------------------------------------------------+
void CheckStackTradesOnTick(int symbolIndex)
  {
   if(!StackMode)
      return;
   string symbol = SymbolData[symbolIndex].symbol;

// 1. NORMAL MODE STACKING
   if(RiskMode == RISK_MODE_NONE)
     {
      // This flag is set TRUE only when SL actually moves in ApplyPendingTrail
      if(SymbolData[symbolIndex].NonGridSLMovedThisTick)
        {
         int currentCounter = SymbolData[symbolIndex].NonGridStack.Counter;
         int lastProcessed = SymbolData[symbolIndex].NonGridStack.LastProcessedCounter;

         // Only stack if counter incremented (meaning SL moved to a new level)
         // And ensure we respect the "StackStart" level
         if(currentCounter >= StackStart && currentCounter > lastProcessed)
           {
            // --- FIX START ---
            // REMOVED: if(SymbolData[symbolIndex].TrailLocked) return;
            // Reason: This flag was permanently true if LockTrail was enabled, blocking all stacks.
            // Since NonGridSLMovedThisTick is true, we know the SL moved, so the Lock is already broken/satisfied.
            // --- FIX END ---

            if(!CheckLastTradeLockedInProfit(symbolIndex, false))
               return;

            OpenStackTrade(symbolIndex);

            // Mark as processed so we don't open multiple times for the same level
            SymbolData[symbolIndex].NonGridStack.LastProcessedCounter = currentCounter;
           }

         // Reset Flag immediately
         SymbolData[symbolIndex].NonGridSLMovedThisTick = false;
        }
     }
// 2. GRID/ZONE PHASE 2 STACKING
   else
      if((RiskMode == RISK_MODE_GRID || RiskMode == RISK_MODE_ZONE_RECOVERY) && SymbolData[symbolIndex].GridPhase2Active)
        {
         if(SymbolData[symbolIndex].GridSLMovedThisTick)
           {
            int currentCounter = SymbolData[symbolIndex].GridStack.Counter;
            int lastProcessed = SymbolData[symbolIndex].GridStack.LastProcessedCounter;

            if(currentCounter >= StackStart && currentCounter > lastProcessed)
              {
               bool isFirstStack = (SymbolData[symbolIndex].GridStackLevels == 0);

               if(!isFirstStack)
                 {
                  if(!CheckLastTradeLockedInProfit(symbolIndex, true))
                    {
                     SymbolData[symbolIndex].GridSLMovedThisTick = false;
                     return;
                    }
                 }

               OpenGridStackTrade(symbolIndex);
               SymbolData[symbolIndex].GridStack.LastProcessedCounter = currentCounter;
              }
            SymbolData[symbolIndex].GridSLMovedThisTick = false;
           }
        }
  }

//+------------------------------------------------------------------+
//| OpenStackTrade - FIXED (Reads Live Direction)                    |
//+------------------------------------------------------------------+
void OpenStackTrade(int symbolIndex)
  {
   // 1. BRIDGE SAFETY CHECK
   if(IsBridgeRuntimeEnabled())
   {
      string stopVar = InpHedgeChannel + "_STOP_FLAG";
      if(GlobalVariableCheck(stopVar)) {
          if(GlobalVariableGet(stopVar) > 0.1) return;
      }
   }
   
   string analysisSymbol = SymbolData[symbolIndex].symbol;
   string execSymbol     = GetBaseSymbol(analysisSymbol);

// 1. Validate Master Position
   if(!PositionSelectByTicket(SymbolData[symbolIndex].MasterTicket))
     {
      Print(analysisSymbol, " Error: Master ticket invalid/closed. Cannot stack.");
      return;
     }

// --- FIX START: READ LIVE DATA ---
// We get the type directly from the position to avoid cache errors
   ENUM_POSITION_TYPE masterType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double masterVolume = PositionGetDouble(POSITION_VOLUME);
   double masterSL     = PositionGetDouble(POSITION_SL); // Use live SL as well
// --- FIX END ---

// 2. Calculate Stack Multiplier
   int stackLevel = SymbolData[symbolIndex].NonGridStack.Counter - StackStart + 1;
   double newMultiplier = StackInitial + (StackBoost * (stackLevel - 1));
   newMultiplier = MathMax(MinStackMultiplier, MathMin(MaxStackMultiplier, newMultiplier));

   if(newMultiplier != SymbolData[symbolIndex].StackMultiplier)
     {
      SymbolData[symbolIndex].StackMultiplier = newMultiplier;
      SymbolData[symbolIndex].StackUpdates++;
     }

// 3. LOT SIZE CALCULATION
   double baseRawStack = SymbolData[symbolIndex].LastUsedStackRawLot;
   if(baseRawStack <= 0.000001)
      baseRawStack = masterVolume;

   double rawStackLot = baseRawStack * SymbolData[symbolIndex].StackMultiplier;

   if(GridMaxStake > 0.0 && rawStackLot > GridMaxStake)
      rawStackLot = GridMaxStake;

   SymbolData[symbolIndex].LastUsedStackRawLot = rawStackLot;
   SymbolData[symbolIndex].RawNextStackLot = rawStackLot;

// 4. Broker Normalization
   double minLot = SymbolInfoDouble(execSymbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(execSymbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(execSymbol, SYMBOL_VOLUME_STEP);

   double lotSize = MathMax(minLot, MathMin(maxLot, rawStackLot));
   lotSize = NormalizeDouble(lotSize / lotStep, 0) * lotStep;

   if(lotSize < minLot)
      lotSize = minLot;
   if(lotSize > MaxLotSizePerTrade)
      lotSize = MaxLotSizePerTrade;

// 5. Execution Setup
   double price = (masterType == POSITION_TYPE_BUY) ?
                  SymbolInfoDouble(execSymbol, SYMBOL_ASK) :
                  SymbolInfoDouble(execSymbol, SYMBOL_BID);

   string comment = TradeComment + " Stack";
   if(InpEnableMultiBaskets && SymbolData[symbolIndex].BasketId > 0)
      comment += StringFormat(" B#%d", SymbolData[symbolIndex].BasketId);

   price    = NormalizePrice(execSymbol, price);
   masterSL = NormalizePrice(execSymbol, masterSL);

// 6. Send Trade
   bool tradeResult = false;
   if(masterType == POSITION_TYPE_BUY)
      tradeResult = Trade.Buy(lotSize, execSymbol, price, masterSL, 0, comment);
   else
      tradeResult = Trade.Sell(lotSize, execSymbol, price, masterSL, 0, comment);

   if(tradeResult)
     {
      if(IsBridgeRuntimeEnabled())
         SendBridgeSignal((masterType == POSITION_TYPE_BUY), lotSize);
      SymbolData[symbolIndex].LastStackSL = masterSL;

      Print(execSymbol, " Stack Trade Opened Successfully!");
      Print("  - Level: ", stackLevel, " | Type: ", EnumToString(masterType));
      Print("  - Multiplier: ", SymbolData[symbolIndex].StackMultiplier);
      Print("  - Exec Lot: ", lotSize);
     }
   else
     {
      Print(analysisSymbol, " FAILED to open stack trade. Error: ", GetLastError());
      SymbolData[symbolIndex].StackUpdates--;
      SymbolData[symbolIndex].LastUsedStackRawLot = baseRawStack;
      SymbolData[symbolIndex].NonGridStack.Counter--;
      SymbolData[symbolIndex].NonGridStack.LastProcessedCounter = SymbolData[symbolIndex].NonGridStack.Counter - 1;
     }
  }

//+------------------------------------------------------------------+
//| OpenGridStackTrade - FIXED DIRECTION LOGIC FOR ZONE              |
//+------------------------------------------------------------------+
void OpenGridStackTrade(int symbolIndex)
  {
   // 1. BRIDGE SAFETY CHECK
   if(IsBridgeRuntimeEnabled())
   {
      string stopVar = InpHedgeChannel + "_STOP_FLAG";
      if(GlobalVariableCheck(stopVar)) {
          if(GlobalVariableGet(stopVar) > 0.1) return;
      }
   }
   
   string analysisSymbol = SymbolData[symbolIndex].symbol;
   string execSymbol     = GetBaseSymbol(analysisSymbol);

// ---------------------------------------------------------
// 1. DETERMINE DIRECTION (Fix: Based on Net Volume, not Master)
// ---------------------------------------------------------
   ENUM_POSITION_TYPE gridType = POSITION_TYPE_BUY;
   double totalBuyVol = 0;
   double totalSellVol = 0;
   bool foundAny = false;

// Scan ALL open positions for this symbol/magic to determine the winning side
   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetString(POSITION_SYMBOL) == execSymbol &&
            IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
           {
            string c = PositionGetString(POSITION_COMMENT);
            if(InpEnableMultiBaskets && !IsPositionInBasket(symbolIndex, c))
               continue;
            // Check if trade belongs to the basket (Grid, Zone, or previous Stacks)
            if(StringFind(c, "Grid") >= 0 || StringFind(c, "Zone") >= 0 || StringFind(c, "Stack") >= 0)
              {
               if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                  totalBuyVol += PositionGetDouble(POSITION_VOLUME);
               else
                  totalSellVol += PositionGetDouble(POSITION_VOLUME);

               foundAny = true;
              }
           }
        }
     }

   if(!foundAny)
     {
      Print(execSymbol, " Error: Cannot open Grid Stack - No active basket found.");
      return;
     }

//
// Logic: If Sell Volume > Buy Volume, we are recovering DOWN. Stack SELL.
// If Buy Volume >= Sell Volume, we are recovering UP. Stack BUY.
   if(totalSellVol > totalBuyVol)
      gridType = POSITION_TYPE_SELL;
   else
      gridType = POSITION_TYPE_BUY;

// ---------------------------------------------------------
// 2. CALCULATE LOT SIZE (Recursive Math)
// Formula: NewLot = PreviousLot * (PreviousMult + Boost)
// ---------------------------------------------------------

   double calculatedLot = 0.0;
   double currentMult = 1.0;

// Is this the VERY FIRST Stack trade for this sequence?
   if(SymbolData[symbolIndex].GridStackLevels == 0)
     {
      // --- TRADE 1 ---
      // Base = The TOTAL volume of the winning side of the basket
      // This ensures the stack is proportional to the heavy side of the zone
      double baseVol = (gridType == POSITION_TYPE_BUY) ? totalBuyVol : totalSellVol;

      currentMult = StackInitial; // Usually 1.0
      calculatedLot = baseVol * currentMult;

      // Initialize Tracking Variables
      SymbolData[symbolIndex].LastStackLot = calculatedLot;
      SymbolData[symbolIndex].LastStackMult = currentMult;

      Print(execSymbol, " Stack [Start]: Direction=", EnumToString(gridType), " BaseVol=", baseVol, " * InitMult=", currentMult, " = ", calculatedLot);
     }
   else
     {
      // --- SUBSEQUENT TRADES ---
      // Retrieve history
      double prevLot = SymbolData[symbolIndex].LastStackLot;
      double prevMult = SymbolData[symbolIndex].LastStackMult;

      // Apply Formula: Multiplier = PreviousMultiplier + Boost
      currentMult = prevMult + StackBoost;

      // Apply Formula: Lot = PreviousLot * NewMultiplier
      calculatedLot = prevLot * currentMult;

      Print(execSymbol, " Stack [Next]: PrevLot=", prevLot, " * (PrevMult=", prevMult, " + Boost=", StackBoost, ") = ", calculatedLot);

      // Update Tracking for NEXT time
      SymbolData[symbolIndex].LastStackLot = calculatedLot;
      SymbolData[symbolIndex].LastStackMult = currentMult;
     }

// ---------------------------------------------------------
// 3. BROKER NORMALIZATION & SAFETY CAPS
// ---------------------------------------------------------
   double minLot = SymbolInfoDouble(execSymbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(execSymbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(execSymbol, SYMBOL_VOLUME_STEP);

// Step 1: Clip to Min/Max raw
   double lotSize = MathMax(minLot, MathMin(maxLot, calculatedLot));

// Step 2: Normalize to Step
   lotSize = NormalizeDouble(lotSize / lotStep, 0) * lotStep;

// Step 3: Global Max Cap
   if(lotSize > MaxLotSizePerTrade)
      lotSize = MaxLotSizePerTrade;

// ---------------------------------------------------------
// 4. EXECUTION SETUP
// ---------------------------------------------------------
   double price = (gridType == POSITION_TYPE_BUY) ?
                  SymbolInfoDouble(execSymbol, SYMBOL_ASK) :
                  SymbolInfoDouble(execSymbol, SYMBOL_BID);

   string comment = TradeComment + " GridStack";
   if(InpEnableMultiBaskets && SymbolData[symbolIndex].BasketId > 0)
      comment += StringFormat(" B#%d", SymbolData[symbolIndex].BasketId);

// Basket SL is the "Safety Line" (Break Even or Profit Lock price)
   double basketSL = SymbolData[symbolIndex].GridBasketStopLoss;

   price    = NormalizePrice(execSymbol, price);
   basketSL = NormalizePrice(execSymbol, basketSL);

// CRITICAL SAFETY: Do not open stack if price has already crossed the Safety Line
   if(basketSL > 0)
     {
      if(gridType == POSITION_TYPE_BUY && basketSL >= price)
        {
         Print(execSymbol, " Stack Aborted: Price below Basket SL.");
         return;
        }
      if(gridType == POSITION_TYPE_SELL && basketSL <= price)
        {
         Print(execSymbol, " Stack Aborted: Price above Basket SL.");
         return;
        }
     }

// ---------------------------------------------------------
// 5. SEND TRADE
// ---------------------------------------------------------
   bool tradeResult = false;
   if(gridType == POSITION_TYPE_BUY)
      tradeResult = Trade.Buy(lotSize, execSymbol, price, basketSL, 0, comment);
   else
      tradeResult = Trade.Sell(lotSize, execSymbol, price, basketSL, 0, comment);

   if(tradeResult)
     {
      SymbolData[symbolIndex].GridStackLevels++;
      SaveBasketRuntimeState(symbolIndex);
      // Note: We do NOT add this to GridBasketVolume to avoid messing up the original Zone calculations

      Print(execSymbol, " ✅ Stack trade opened. Level: ", SymbolData[symbolIndex].GridStackLevels,
            " | Lot: ", lotSize, " | Mult: ", currentMult);
     }
   else
     {
      Print(execSymbol, " FAILED to open stack trade. Error: ", GetLastError());
     }
  }
  
//+------------------------------------------------------------------+
//| Apply pending trail updates - UPDATED FOR STACKING TRIGGER       |
//+------------------------------------------------------------------+
void ApplyPendingTrail(int symbolIndex)
  {
   if(HideSLTPDuringCloseBlock && G_Cache_IsDailyCloseBlock) return;
   string symbol = SymbolData[symbolIndex].symbol;

   if(SymbolData[symbolIndex].HasPendingTrail && SymbolData[symbolIndex].PendingTrailSL != 0)
     {
      // 1. Master SL Update (Normal Mode Only)
      if(SymbolData[symbolIndex].MasterTicket != 0 && PositionSelectByTicket(SymbolData[symbolIndex].MasterTicket))
        {
         double currentSL = PositionGetDouble(POSITION_SL);
         if(currentSL != SymbolData[symbolIndex].PendingTrailSL)
           {
            if(Trade.PositionModify(SymbolData[symbolIndex].MasterTicket, SymbolData[symbolIndex].PendingTrailSL, 0))
              {
               SymbolData[symbolIndex].MasterSL = SymbolData[symbolIndex].PendingTrailSL;
               SymbolData[symbolIndex].MasterHasValidSL = true;
               SymbolData[symbolIndex].TrailUpdateCount++;
               SymbolData[symbolIndex].MasterSLMoved = true;
               SmartHedge_OnProtectedStopMove(symbolIndex, false);

               // Trigger Normal Mode Stack
               if(RiskMode == RISK_MODE_NONE)
                 {
                  SymbolData[symbolIndex].NonGridStack.Counter++;
                  SymbolData[symbolIndex].NonGridSLMovedThisTick = true;
                 }

               if(StackMode && RiskMode == RISK_MODE_NONE)
                 {
                  ApplyMasterSLToStacks(symbolIndex, SymbolData[symbolIndex].MasterTicket, SymbolData[symbolIndex].PendingTrailSL);
                 }
              }
           }
        }

      // 2. Grid/Zone Basket SL Update (Phase 2)
      if(SymbolData[symbolIndex].GridPhase2Active)
        {
         SymbolData[symbolIndex].GridBasketStopLoss = SymbolData[symbolIndex].PendingTrailSL;

         // Execute the modification on all trades (Smart SL/TP)
         UpdateAllGridStopLosses(symbolIndex);

         SymbolData[symbolIndex].GridTrailUpdates++;
         SymbolData[symbolIndex].BasketSLMoved = true;
         SmartHedge_OnProtectedStopMove(symbolIndex, true);

         // Trigger Grid/Zone Stack
         SymbolData[symbolIndex].GridStack.Counter++;
         SymbolData[symbolIndex].GridSLMovedThisTick = true;

         Print(symbol, " BASKET SL MOVED! Stack Signal Sent. New Level: ", SymbolData[symbolIndex].GridBasketStopLoss);
         SaveBasketRuntimeState(symbolIndex);
        }

      SymbolData[symbolIndex].HasPendingTrail = false;
      SymbolData[symbolIndex].PendingTrailSL = 0;
     }
  }

//+------------------------------------------------------------------+
//| Apply master SL to all stack trades                              |
//+------------------------------------------------------------------+
void ApplyMasterSLToStacks(int symbolIndex, ulong masterTicket, double masterSL)
  {
// --- FIX: USE DYNAMIC SYMBOL ---
   string trackingSymbol = GetBaseSymbol(SymbolData[symbolIndex].symbol);
   bool filterByBasket = InpEnableMultiBaskets;

   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(ticket == masterTicket)
            continue;

         if(PositionGetString(POSITION_SYMBOL) == trackingSymbol &&
            IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
           {
         string comment = PositionGetString(POSITION_COMMENT);
         if(filterByBasket && !IsPositionInBasket(symbolIndex, comment))
            continue;
            bool isStackTrade = (StringFind(comment, "Stack") >= 0);

            if(isStackTrade)
              {
               double currentSL = PositionGetDouble(POSITION_SL);

               if(currentSL != masterSL)
                 {
                  Trade.PositionModify(ticket, masterSL, 0);
                 }
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Helper: Scan History to Reconcile Profit (Broker Close Fix)      |
//+------------------------------------------------------------------+
void ReconcileSequenceFromHistory(int symbolIndex)
  {
   // --- FIX: POISON GUARD ---
   // If LastGridReset is in the future, abort.
   if(SymbolData[symbolIndex].LastGridReset > TimeCurrent())
      return; 
   // -------------------------
  
   string symbol = GetBaseSymbol(SymbolData[symbolIndex].symbol);
   // 1. Define Range
   datetime start = SymbolData[symbolIndex].LastGridReset;
   // --- SAFETY FALLBACK ---
   if(start == 0) start = TimeCurrent() - 3600 ;//86400;
   
   // --- CPU FIX ---
   if(TimeCurrent() - start > 259200) 
      start = TimeCurrent() - 259200; 
   // ---------------
   
   datetime end   = TimeCurrent() + 60; // Buffer

   // 2. Select History
   if(!HistorySelect(start, end))
      return;

   double sequenceNetProfit = 0.0;
   bool foundTrades = false;
   int total = HistoryDealsTotal();

   // 3. Sum up profit
   for(int i = 0; i < total; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > 0)
        {
         string dealSymbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
         long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
         
         if(dealSymbol == symbol && IsAppTrade(magic))
           {
            double p = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            double s = HistoryDealGetDouble(ticket, DEAL_SWAP);
            double c = HistoryDealGetDouble(ticket, DEAL_COMMISSION);

            sequenceNetProfit += (p + s + c);
            foundTrades = true;
           }
        }
     }

   if(!foundTrades)
      return; 

   Print(symbol, " [Reconcile] Broker-Closed Sequence Found. Net Result: $", DoubleToString(sequenceNetProfit, 2));

   // 4. APPLY TO BANKS
   if(UsePruningRecovery)
     {
      if(sequenceNetProfit > 0)
        {
         // --- SCENARIO A: PROFIT (Recovery) ---
         if(SymbolData[symbolIndex].AccumulatedPruningLoss > 0)
           {
            double oldDebt = SymbolData[symbolIndex].AccumulatedPruningLoss;
            SymbolData[symbolIndex].AccumulatedPruningLoss -= sequenceNetProfit;

            if(SymbolData[symbolIndex].AccumulatedPruningLoss < 0)
               SymbolData[symbolIndex].AccumulatedPruningLoss = 0;

            Print("💸 Debt repayment: $", DoubleToString(oldDebt, 2), " -> $", DoubleToString(SymbolData[symbolIndex].AccumulatedPruningLoss, 2));

            if(SymbolData[symbolIndex].AccumulatedPruningLoss == 0)
               SymbolData[symbolIndex].RecoveryIteration = 1;
            else
               if(!SymbolData[symbolIndex].PruningOccurredThisSequence)
                  SymbolData[symbolIndex].RecoveryIteration++;
               else
                  SymbolData[symbolIndex].RecoveryIteration = 1;
           }
        }
      else 
        {
         // --- SCENARIO B: NET LOSS ---
         double realizedLoss = MathAbs(sequenceNetProfit);

         if(SymbolData[symbolIndex].CurrentRecoveryPortion > 0)
         {
            SymbolData[symbolIndex].AccumulatedPruningLoss += SymbolData[symbolIndex].CurrentRecoveryPortion;
            Print("⚠️ Recovery failed. Returned the active portion ($", DoubleToString(SymbolData[symbolIndex].CurrentRecoveryPortion, 2), ") to the debt bank.");
         }

         if(SymbolData[symbolIndex].PruningOccurredThisSequence)
         {
            SymbolData[symbolIndex].AccumulatedPruningLoss += realizedLoss;
            Print("⚠️ Hard pruning verified: loss of $", DoubleToString(realizedLoss, 2), " added to the pruning bank.");
         }
         else
         {
            SymbolData[symbolIndex].AccumulatedCriticalLoss += realizedLoss;
            Print("💥 Critical loss recorded: $", DoubleToString(realizedLoss, 2));
         }
        }

      SymbolData[symbolIndex].CurrentRecoveryPortion = 0.0;
     }
     
   // --- UPDATE TRACKER (Guarded) ---
   if(SymbolData[symbolIndex].LastGridReset <= TimeCurrent())
      SymbolData[symbolIndex].LastGridReset = TimeCurrent();
  }

//+------------------------------------------------------------------+
//| Reconcile Normal Mode Trade (Capture Loss & Manage Prune Bank)   |
//+------------------------------------------------------------------+
void ReconcileNormalTrade(int symbolIndex)
{
   if(RiskMode != RISK_MODE_NONE || !UsePruningRecovery) return;

   if(SymbolData[symbolIndex].MasterTicket > 0 && !PositionSelectByTicket(SymbolData[symbolIndex].MasterTicket))
   {
      ulong ticket = SymbolData[symbolIndex].MasterTicket;
      
      if(HistorySelect(TimeCurrent() - 86400, TimeCurrent() + 60))
      {
         double netPL = 0;
         bool found = false;
         
         int total = HistoryDealsTotal();
         for(int i = 0; i < total; i++)
         {
            ulong dealTicket = HistoryDealGetTicket(i);
            if(dealTicket > 0)
            {
               if(HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID) == ticket)
               {
                  double p = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                  double s = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
                  double c = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
                  netPL += (p + s + c);
                  found = true;
               }
            }
         }

         if(found)
         {
            Print(SymbolData[symbolIndex].symbol, " [Reconcile] Trade Closed. Net PL: $", DoubleToString(netPL, 2));

            if(netPL > 0)
            {
               // --- PROFIT: Repay Debt ---
               // We deduct the total Net Profit from the debt.
               // Since we sized up specifically to cover debt, this works correctly.
               
               if(SymbolData[symbolIndex].AccumulatedPruningLoss > 0)
               {
                  double oldDebt = SymbolData[symbolIndex].AccumulatedPruningLoss;
                  SymbolData[symbolIndex].AccumulatedPruningLoss -= netPL;
                  
                  if(SymbolData[symbolIndex].AccumulatedPruningLoss < 0) 
                     SymbolData[symbolIndex].AccumulatedPruningLoss = 0;

                  Print("💸 Debt repaid: $", DoubleToString(oldDebt, 2), " -> $", DoubleToString(SymbolData[symbolIndex].AccumulatedPruningLoss, 2));
                  
                  // Reset Iteration if debt is fully cleared
                  if(SymbolData[symbolIndex].AccumulatedPruningLoss == 0)
                     SymbolData[symbolIndex].RecoveryIteration = 1;
               }
            }
            else
            {
               // --- LOSS: Add to Bank ---
               double loss = MathAbs(netPL);
               SymbolData[symbolIndex].AccumulatedPruningLoss += loss;
               
               Print("💥 Loss captured in the debt bank. Total debt: $", DoubleToString(SymbolData[symbolIndex].AccumulatedPruningLoss, 2));
               
               // Reset iteration to prevent spiraling risk after a loss
               SymbolData[symbolIndex].RecoveryIteration = 1; 
            }
         }
      }

      // Final Cleanup
      SymbolData[symbolIndex].MasterTicket = 0;
      SymbolData[symbolIndex].CurrentRecoveryPortion = 0.0;
      SymbolData[symbolIndex].MasterSL = 0;
      SymbolData[symbolIndex].MasterEntry = 0;
      SymbolData[symbolIndex].MasterHasValidSL = false;
   }
}

//+------------------------------------------------------------------+
//| NEW HELPER: Process profit from trades closed by Broker (SL/TP)  |
//+------------------------------------------------------------------+
void ProcessClosedSequence(int symbolIndex)
  {
   // --- FIX: POISON GUARD ---
   // If LastGridReset is in the future (set by Equity Limit wipe), 
   // we MUST NOT process any trades or update the timestamp.
   if(SymbolData[symbolIndex].LastGridReset > TimeCurrent())
      return; 
   // -------------------------

   string symbol = GetBaseSymbol(SymbolData[symbolIndex].symbol);
   double sequenceProfit = 0.0;
   bool foundTrades = false;

   // 1. Define Range: From the start of this grid cycle to NOW
   datetime scanStart = SymbolData[symbolIndex].LastGridReset;
   
   // --- SAFETY FALLBACK ---
   if(scanStart == 0) scanStart = TimeCurrent() - 86400; 
   
   // --- CPU FIX: CAP HISTORY SCAN ---
   // Prevent scanning months of history if the bot has been running a long time.
   // We limit the lookback to 3 days (259200 seconds) max.
   if(TimeCurrent() - scanStart > 259200) 
      scanStart = TimeCurrent() - 259200;
   // ---------------------------------

   // 2. Select History
   if(HistorySelect(scanStart, TimeCurrent() + 60))
     {
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
        {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket > 0)
           {
            string dealSymbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
            long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
            
            // We sum ALL deals (IN and OUT) to capture Entry Commissions correctly
            if(dealSymbol == symbol && IsAppTrade(magic)) 
              {
               datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);

               // Double Check: Only count trades that occurred AFTER our scan start
               if(dealTime >= scanStart)
                 {
                  double p = HistoryDealGetDouble(ticket, DEAL_PROFIT);
                  double s = HistoryDealGetDouble(ticket, DEAL_SWAP);
                  double c = HistoryDealGetDouble(ticket, DEAL_COMMISSION);

                  sequenceProfit += (p + s + c);
                  foundTrades = true;
                 }
              }
           }
        }
     }

   if(!foundTrades)
      return; 

   Print(SymbolData[symbolIndex].symbol, " Broker Closure Detected. Realized Profit: $", DoubleToString(sequenceProfit, 2));

   // 3. APPLY DEBT LOGIC (Bookkeeping)
   if(UsePruningRecovery)
     {
      if(sequenceProfit > 0)
        {
         // --- PROFIT: Repay Debt ---
         if(SymbolData[symbolIndex].AccumulatedPruningLoss > 0)
           {
            double oldDebt = SymbolData[symbolIndex].AccumulatedPruningLoss;
            SymbolData[symbolIndex].AccumulatedPruningLoss -= sequenceProfit;

            // Floor at 0
            if(SymbolData[symbolIndex].AccumulatedPruningLoss < 0)
               SymbolData[symbolIndex].AccumulatedPruningLoss = 0;

            Print("💸 Debt repayment success: $", DoubleToString(oldDebt, 2), " -> $", DoubleToString(SymbolData[symbolIndex].AccumulatedPruningLoss, 2));

            // Iteration Logic
            if(SymbolData[symbolIndex].AccumulatedPruningLoss == 0)
               SymbolData[symbolIndex].RecoveryIteration = 1;
            else
               if(!SymbolData[symbolIndex].PruningOccurredThisSequence)
                  SymbolData[symbolIndex].RecoveryIteration++;
               else
                  SymbolData[symbolIndex].RecoveryIteration = 1;
           }
        }
      else 
        {
         // --- LOSS: Add to Critical (Unless we are wiping!) ---
         SymbolData[symbolIndex].AccumulatedCriticalLoss += MathAbs(sequenceProfit);
         Print("💥 Critical loss recorded: $", DoubleToString(MathAbs(sequenceProfit), 2));

         // --- LEAK FIX: RETURN ACTIVE DEBT TO BANK ---
         if(SymbolData[symbolIndex].CurrentRecoveryPortion > 0)
           {
            SymbolData[symbolIndex].AccumulatedPruningLoss += SymbolData[symbolIndex].CurrentRecoveryPortion;
            Print("⚠️ Recovery failed. Returned the active portion ($", DoubleToString(SymbolData[symbolIndex].CurrentRecoveryPortion, 2), ") to the debt bank.");
           }
        }

      // Reset Pointer
      SymbolData[symbolIndex].CurrentRecoveryPortion = 0.0;
     }

   // 4. CRITICAL UPDATE: Close the Book
   // Only update if we are NOT in a poisoned state (Redundant check but safe)
   if(SymbolData[symbolIndex].LastGridReset <= TimeCurrent())
      SymbolData[symbolIndex].LastGridReset = TimeCurrent(); 
  }
  
//+------------------------------------------------------------------+
//| Helper: Close Largest Opposite Trade (Fixed to Return Loss)      |
//+------------------------------------------------------------------+
double CloseLargestOppositePosition(int symbolIndex, ENUM_POSITION_TYPE targetType)
  {
   string trackingSymbol = GetBaseSymbol(SymbolData[symbolIndex].symbol);
   bool filterByBasket = InpEnableMultiBaskets;
   ulong maxTicket = 0;
   double maxVol = -1.0;
   double realizedLoss = 0.0;

// Scan for the largest volume trade of the 'targetType' (Opposite side)
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetString(POSITION_SYMBOL) == trackingSymbol &&
            IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
           {
         string comment = PositionGetString(POSITION_COMMENT);
         if(filterByBasket && !IsPositionInBasket(symbolIndex, comment))
            continue;
            if(StringFind(comment, "Grid") >= 0 || StringFind(comment, "Zone") >= 0)
              {
               if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == targetType)
                 {
                  double v = PositionGetDouble(POSITION_VOLUME);
                  if(v > maxVol)
                    {
                     maxVol = v;
                     maxTicket = ticket;
                    }
                 }
              }
           }
        }
     }

// If found, close it
   if(maxTicket > 0)
     {
      // --- CALC LOSS BEFORE CLOSE ---
      if(PositionSelectByTicket(maxTicket))
        {
         double p = PositionGetDouble(POSITION_PROFIT);
         double s = PositionGetDouble(POSITION_SWAP);
         double c = GetPositionCommission(PositionGetInteger(POSITION_IDENTIFIER));
         double net = p + s + c;
         if(net < 0)
            realizedLoss = MathAbs(net);
        }
      // -----------------------------

      Print(trackingSymbol, " Margin Rescue: Closing Largest Opposite Trade (", maxVol, " lots) | Ticket: ", maxTicket);

      if(Trade.PositionClose(maxTicket))
        {
         if(MBP_ShouldAllowBlockingTradeWait("rescue_close"))
            Sleep(100); // Broker sync delay
         return realizedLoss; // Return the amount lost
        }
      else
        {
         Print("Failed to close rescue trade: ", GetLastError());
         return 0.0;
        }
     }

   return 0.0; // No trade found
  }

//+------------------------------------------------------------------+
//| Manage Trailing Stop (Normal Mode Only)                          |
//| FIX: Uses TrailType (ATR/BOX) instead of undeclared TrailPoints. |
//| Logic: 1. Waits for Price > TP + Buffer (ATR based).             |
//|        2. Snaps SL to TP (TPActivated = true).                   |
//|        3. Trails using Box or ATR logic thereafter.              |
//+------------------------------------------------------------------+
void ManageTrailingStop(int symbolIndex)
{
   // 1. Basic Checks
   if(!UseTrailing || IsPaused) return;
   if(RiskMode != RISK_MODE_NONE) return; 

   ulong ticket = SymbolData[symbolIndex].MasterTicket;
   if(ticket == 0 || !PositionSelectByTicket(ticket)) return;

   string symbol = SymbolData[symbolIndex].symbol;
   long type = PositionGetInteger(POSITION_TYPE);
   
   double currentPrice = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);
   double openPrice    = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL    = PositionGetDouble(POSITION_SL);
   double hardTP       = SymbolData[symbolIndex].InitialTP; 
   double point        = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int digits          = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   // -------------------------------------------------------
   // PART 1: CALCULATE DISTANCE / BUFFER
   // -------------------------------------------------------
   // Since TrailPoints is not defined, we use ATR * Multiplier as the standard distance.
   // If TrailType is BOX, we still use ATR for the "Snap to TP" buffer calculation 
   // because Box levels don't provide a linear distance value.
   
   double trailDist = 0.0;
   double atr[1];
   
   if(SymbolData[symbolIndex].ATR_Handle != INVALID_HANDLE && CopyBuffer(SymbolData[symbolIndex].ATR_Handle, 0, 0, 1, atr) > 0)
   {
      // Valid ATR: Use Multiplier
      trailDist = atr[0] * TrailATR_Multiplier;
   }
   else
   {
      // Fallback if ATR fails: Use a hardcoded safety net (e.g. 50 pips) since TrailPoints isn't available
      trailDist = 500 * point; 
   }

   // Safety: Ensure min stop distance
   long stopLevel = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(trailDist < stopLevel * point) trailDist = stopLevel * point;

   // -------------------------------------------------------
   // PART 2: DELAYED ACTIVATION (SNAP TO TP)
   // -------------------------------------------------------
   // Logic: Wait for Price to exceed (TP + Buffer). 
   // If triggered, move SL to TP and enable standard trailing.
   
   if(!SymbolData[symbolIndex].TPActivated)
   {
      bool activate = false;

      if(type == POSITION_TYPE_BUY)
      {
         // Buy: Price must go ABOVE (TP + Buffer)
         if(currentPrice >= (hardTP + trailDist)) 
            activate = true;
      }
      else
      {
         // Sell: Price must go BELOW (TP - Buffer)
         if(currentPrice <= (hardTP - trailDist)) 
            activate = true;
      }

      if(activate)
      {
         if(HideSLTPDuringCloseBlock && G_Cache_IsDailyCloseBlock) return; // Suppress snap to TP
         // ACTION: Snap SL to the TP Level (Lock Profit)
         // Note: We use NormalizeDouble to ensure the price is valid for the broker
         if(Trade.PositionModify(ticket, NormalizeDouble(hardTP, digits), 0))
         {
            SymbolData[symbolIndex].TPActivated = true; // Unlock Phase B
            SymbolData[symbolIndex].LastSLPrice = hardTP;
            SymbolData[symbolIndex].MasterSL = hardTP;
            SymbolData[symbolIndex].MasterHasValidSL = true;
            SymbolData[symbolIndex].TrailUpdateCount++;
            SymbolData[symbolIndex].MasterSLMoved = true;
            Print(symbol, " 🔒 Delayed trail triggered. Snap SL to TP: ", hardTP);
            
            SmartHedge_OnProtectedStopMove(symbolIndex, false);
            // Update local var for immediate use in Phase B
            currentSL = hardTP; 
         }
      }
   }

   // -------------------------------------------------------
   // PART 3: STANDARD TRAILING (Active Phase)
   // -------------------------------------------------------
   // Only run if Activated OR if user didn't request TP_HIT Lock
   // (If LockTrail == TP_HIT, we strictly wait for TPActivated. If NONE, we might trail earlier depending on logic).
   
   // Check if we are allowed to calculate a new SL
   bool canTrail = true;
   if(LockTrail == LOCK_TRAIL_TP_HIT && !SymbolData[symbolIndex].TPActivated) 
      canTrail = false;

   if(canTrail)
   {
      double newSL = 0.0;
      bool modify = false;

      // --- A. BOX TRAILING LOGIC ---
      if(TrailType == TRAIL_BOX)
      {
         if(type == POSITION_TYPE_BUY)
         {
            // Find lowest of last N segments
            int count = MathMin(SymbolData[symbolIndex].BoxLowCount, TrailBox_Levels);
            if(count > 0)
            {
               double safestLow = SymbolData[symbolIndex].BoxLow[0];
               for(int i = 1; i < count; i++) {
                  if(SymbolData[symbolIndex].BoxLow[i] < safestLow) safestLow = SymbolData[symbolIndex].BoxLow[i];
               }
               // Move UP Only
               if(safestLow > currentSL && safestLow < currentPrice) { 
                  newSL = safestLow; 
                  modify = true; 
               }
            }
         }
         else // SELL
         {
            // Find highest of last N segments
            int count = MathMin(SymbolData[symbolIndex].BoxHighCount, TrailBox_Levels);
            if(count > 0)
            {
               double safestHigh = SymbolData[symbolIndex].BoxHigh[0];
               for(int i = 1; i < count; i++) {
                  if(SymbolData[symbolIndex].BoxHigh[i] > safestHigh) safestHigh = SymbolData[symbolIndex].BoxHigh[i];
               }
               // Move DOWN Only
               if(safestHigh < currentSL && safestHigh > currentPrice) { 
                  newSL = safestHigh; 
                  modify = true; 
               }
            }
         }
      }
      // --- B. ATR TRAILING LOGIC ---
      else // TRAIL_ATR
      {
         if(type == POSITION_TYPE_BUY)
         {
            double potentialSL = currentPrice - trailDist;
            if(potentialSL > currentSL + point) { 
               newSL = potentialSL; 
               modify = true; 
            }
         }
         else // SELL
         {
            double potentialSL = currentPrice + trailDist;
            // For Sell, CurrentSL 0 is considered "Higher" (Infinite loss), so any SL is an improvement
            if(currentSL == 0 || potentialSL < currentSL - point) { 
               newSL = potentialSL; 
               modify = true; 
            }
         }
      }

      // --- C. APPLY FILTERS & EXECUTE ---
      if(modify)
      {
         // Lock Trail: Break Even Check
         // If set, we ONLY allow SL to move if it secures profit (Better than Entry)
         if(LockTrail == LOCK_TRAIL_BREAK_EVEN)
         {
            if(type == POSITION_TYPE_BUY && newSL < openPrice) modify = false;
            if(type == POSITION_TYPE_SELL && newSL > openPrice) modify = false;
         }

         if(modify)
         {
            newSL = NormalizeDouble(newSL, digits);
            
            // Prevent spamming the broker with same-price updates
            if(MathAbs(newSL - currentSL) > point)
            {
               if(Trade.PositionModify(ticket, newSL, 0))
               {
                  SymbolData[symbolIndex].LastSLPrice = newSL;
                  SymbolData[symbolIndex].MasterSL = newSL;
                  SymbolData[symbolIndex].MasterHasValidSL = true;
                  SymbolData[symbolIndex].TrailUpdateCount++;
                  SymbolData[symbolIndex].MasterSLMoved = true;
                  SmartHedge_OnProtectedStopMove(symbolIndex, false);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check trailing conditions - FIXED (Added Lock Trail Logic)       |
//+------------------------------------------------------------------+
void CheckTrailingConditions(int symbolIndex, ulong ticketToTrail = 0)
  {
   string symbol = SymbolData[symbolIndex].symbol;
   string execSymbol = GetBaseSymbol(symbol);

// --- VARIABLES SETUP ---
   double currentPrice = 0;
   double currentSL = 0;
   double newSL = 0;
   double entryPrice = 0; // Needed for Lock Logic
   bool isBuy = false;

// A. NORMAL MODE SETUP
   if(RiskMode == RISK_MODE_NONE)
     {
      if(ticketToTrail == 0)
         return;
      if(!PositionSelectByTicket(ticketToTrail))
         return;

      isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
      currentSL = PositionGetDouble(POSITION_SL);
      entryPrice = PositionGetDouble(POSITION_PRICE_OPEN); // Get Entry Price
      newSL = currentSL;
     }
// B. GRID/ZONE PHASE 2 SETUP
   else
     {
      // Net Direction Logic for Basket
      double buyVol = 0, sellVol = 0;
      bool found = false;
      double totalProd = 0;
      double totalVol = 0;

      for(int i=0; i<PositionsTotal(); i++)
        {
         if(PositionSelectByTicket(PositionGetTicket(i)))
           {
            if(PositionGetString(POSITION_SYMBOL) == execSymbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
              {
               string c = PositionGetString(POSITION_COMMENT);
            if(InpEnableMultiBaskets && !IsPositionInBasket(symbolIndex, c))
               continue;
            if(StringFind(c, "Grid") >= 0 || StringFind(c, "Zone") >= 0)
                 {
                  double v = PositionGetDouble(POSITION_VOLUME);
                  double p = PositionGetDouble(POSITION_PRICE_OPEN);

                  if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                     buyVol += v;
                  else
                     sellVol += v;

                  totalProd += (v * p);
                  totalVol += v;
                  found = true;
                 }
              }
           }
        }
      if(!found)
         return;

      isBuy = (buyVol >= sellVol);
      currentPrice = isBuy ? SymbolInfoDouble(execSymbol, SYMBOL_BID) : SymbolInfoDouble(execSymbol, SYMBOL_ASK);
      currentSL = SymbolData[symbolIndex].GridBasketStopLoss;
      newSL = currentSL;

      // Calculate Weighted Average Entry for Lock Logic
      if(totalVol > 0)
         entryPrice = totalProd / totalVol;
     }

// --- TRAILING CALCULATION (SHARED) ---
   if(TrailType == TRAIL_BOX)
     {
      if(isBuy)
        {
         // Look at the lowest of the last N segments (TrailBox_Levels)
         int count = MathMin(SymbolData[symbolIndex].BoxLowCount, TrailBox_Levels);
         if(count > 0)
           {
            double safest = SymbolData[symbolIndex].BoxLow[0];
            for(int i=1; i<count; i++)
              {
               if(SymbolData[symbolIndex].BoxLow[i] < safest)
                  safest = SymbolData[symbolIndex].BoxLow[i];
              }
            // Move UP only
            if(safest > currentSL && safest < currentPrice)
               newSL = safest;
           }
        }
      else
        {
         // Look at the highest of the last N segments (TrailBox_Levels)
         int count = MathMin(SymbolData[symbolIndex].BoxHighCount, TrailBox_Levels);
         if(count > 0)
           {
            double safest = SymbolData[symbolIndex].BoxHigh[0];
            for(int i=1; i<count; i++)
              {
               if(SymbolData[symbolIndex].BoxHigh[i] > safest)
                  safest = SymbolData[symbolIndex].BoxHigh[i];
              }
            // Move DOWN only
            if(safest < currentSL && safest > currentPrice)
               newSL = safest;
           }
        }
     }
   else
      if(TrailType == TRAIL_ATR)
        {
         double atr[1];
         if(CopyBuffer(SymbolData[symbolIndex].ATR_Handle, 0, 0, 1, atr) > 0)
           {
            double val = atr[0];
            if(isBuy)
              {
               double dist = currentPrice - currentSL;
               if(dist >= val * (TrailATR_Multiplier + TrailATR_Update))
                 {
                  double calc = currentPrice - (val * TrailATR_Multiplier);
                  if(calc > currentSL)
                     newSL = calc;
                 }
              }
            else
              {
               double dist = currentSL - currentPrice;
               if(dist >= val * (TrailATR_Multiplier + TrailATR_Update))
                 {
                  double calc = currentPrice + (val * TrailATR_Multiplier);
                  if(calc < currentSL)
                     newSL = calc;
                 }
              }
           }
        }

// --- LOCK TRAIL LOGIC (CRITICAL FIX) ---
// If Lock is enabled, we prevent the "newSL" from being applied if it isn't "better" than Entry
   if(LockTrail == LOCK_TRAIL_BREAK_EVEN)
     {
      if(isBuy)
        {
         // For Buy: New SL must be >= Entry to be allowed
         if(newSL < entryPrice)
            newSL = currentSL;
        }
      else
        {
         // For Sell: New SL must be <= Entry to be allowed
         if(newSL > entryPrice)
            newSL = currentSL;
        }
     }
   else
      if(LockTrail == LOCK_TRAIL_TP_HIT)
        {
         // Only trail if TP has been hit/activated
         if(RiskMode == RISK_MODE_NONE && !SymbolData[symbolIndex].TPActivated)
            newSL = currentSL;
        }

// --- UPDATE ---
   if(newSL != currentSL && newSL != 0)
     {
      SymbolData[symbolIndex].PendingTrailSL = NormalizePrice(execSymbol, newSL);
      SymbolData[symbolIndex].HasPendingTrail = true;
     }
  }

//+------------------------------------------------------------------+
//| Update position tracking (FIXED: Preserves Ticket for Reconcile) |
//+------------------------------------------------------------------+
void UpdatePositionTracking(int symbolIndex)
{
   string trackingSymbol = GetBaseSymbol(SymbolData[symbolIndex].symbol);
   SymbolData[symbolIndex].PositionCount = 0;
   int liveGridCount = 0;
   int liveZoneCount = 0;
   double currentGridProfit = 0.0;

   datetime oldestTime = 0;
   double oldestEntry = 0.0;

   bool filterByBasket = InpEnableMultiBaskets;
   // 1. Scan Open Positions
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == trackingSymbol &&
            IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
         {
            string comment = PositionGetString(POSITION_COMMENT);
            if(filterByBasket && !IsPositionInBasket(symbolIndex, comment))
               continue;

            SymbolData[symbolIndex].OpenPositions[SymbolData[symbolIndex].PositionCount].ticket = ticket;
            SymbolData[symbolIndex].OpenPositions[SymbolData[symbolIndex].PositionCount].entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
            SymbolData[symbolIndex].OpenPositions[SymbolData[symbolIndex].PositionCount].stop_loss = PositionGetDouble(POSITION_SL);
            SymbolData[symbolIndex].OpenPositions[SymbolData[symbolIndex].PositionCount].take_profit = PositionGetDouble(POSITION_TP);
            SymbolData[symbolIndex].OpenPositions[SymbolData[symbolIndex].PositionCount].volume = PositionGetDouble(POSITION_VOLUME);
            SymbolData[symbolIndex].OpenPositions[SymbolData[symbolIndex].PositionCount].type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            SymbolData[symbolIndex].OpenPositions[SymbolData[symbolIndex].PositionCount].open_time = (datetime)PositionGetInteger(POSITION_TIME);
            SymbolData[symbolIndex].OpenPositions[SymbolData[symbolIndex].PositionCount].current_profit = PositionGetDouble(POSITION_PROFIT);

            datetime ot = (datetime)PositionGetInteger(POSITION_TIME);
            if(oldestTime == 0 || ot < oldestTime)
              {
               oldestTime = ot;
               oldestEntry = SymbolData[symbolIndex].OpenPositions[SymbolData[symbolIndex].PositionCount].entry_price;
              }

            SymbolData[symbolIndex].PositionCount++;

            bool isGridTrade = (StringFind(comment, "Grid") >= 0 && StringFind(comment, "GridStack") < 0);
            bool isZoneTrade = (StringFind(comment, "Zone") >= 0);
            if(isGridTrade)
              {
               liveGridCount++;
               currentGridProfit += (PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP));
              }
            if(isZoneTrade)
               liveZoneCount++;
         }
      }
   }

   if(RiskMode == RISK_MODE_GRID)
      SymbolData[symbolIndex].GridLevels = liveGridCount;
   else if(RiskMode == RISK_MODE_ZONE_RECOVERY)
     {
      SymbolData[symbolIndex].ZoneSeqCount = liveZoneCount;
      if(liveZoneCount > 0)
         SymbolData[symbolIndex].ZoneActive = true;
     }

   bool hasLiveSequence = false;
   if(RiskMode == RISK_MODE_GRID)
      hasLiveSequence = (SymbolData[symbolIndex].PositionCount > 0 || liveGridCount > 0 || SymbolData[symbolIndex].GridPhase1Active || SymbolData[symbolIndex].GridPhase2Active || SymbolData[symbolIndex].GridBasketVolume > 0.0 || SymbolData[symbolIndex].GridBasketEntry > 0.0 || SymbolData[symbolIndex].GridTargetReached);
   else if(RiskMode == RISK_MODE_ZONE_RECOVERY)
      hasLiveSequence = (SymbolData[symbolIndex].PositionCount > 0 || liveZoneCount > 0 || SymbolData[symbolIndex].ZoneActive || SymbolData[symbolIndex].ZoneTopPrice != 0.0 || SymbolData[symbolIndex].ZoneBottomPrice != 0.0);
   else
      hasLiveSequence = (SymbolData[symbolIndex].PositionCount > 0 || SymbolData[symbolIndex].MasterTicket > 0 || SymbolData[symbolIndex].InitialTP > 0.0 || SymbolData[symbolIndex].MasterHasValidSL || SymbolData[symbolIndex].NonGridStack.Counter > 0 || SymbolData[symbolIndex].StackLastOpenedCounter > 0);

   if(hasLiveSequence)
      SymbolData[symbolIndex].BasketActive = true;

   if(InpEnableMultiBaskets && SymbolData[symbolIndex].BasketInitialEntry <= 0.0 && oldestEntry > 0.0)
      SymbolData[symbolIndex].BasketInitialEntry = oldestEntry;

   if(SymbolData[symbolIndex].PositionCount == 0)
   {
      bool keepNormalSequenceState = (RiskMode == RISK_MODE_NONE && UsePruningRecovery && SymbolData[symbolIndex].MasterTicket > 0);

      if(InpEnableMultiBaskets)
      {
         SymbolData[symbolIndex].BasketActive = keepNormalSequenceState;
         if(!keepNormalSequenceState)
            SymbolData[symbolIndex].BasketInitialEntry = 0.0;
      }

      ResetGridTracking(symbolIndex);

      if(keepNormalSequenceState)
      {
         // Keep MasterTicket alive until reconciliation consumes the closed trade.
      }
      else
      {
         SymbolData[symbolIndex].MasterTicket = 0;
         SymbolData[symbolIndex].MasterSL = 0;
         SymbolData[symbolIndex].MasterEntry = 0;
         SymbolData[symbolIndex].MasterHasValidSL = false;
      }

      SymbolData[symbolIndex].StackMultiplier = StackInitial;
      SymbolData[symbolIndex].StackUpdates = 0;
      SymbolData[symbolIndex].TrailUpdateCount = 0;
      SymbolData[symbolIndex].LastSLPrice = 0;
      SymbolData[symbolIndex].PreviousMasterSL = 0;
      SymbolData[symbolIndex].MasterSLMoved = false;
      SymbolData[symbolIndex].StackAlreadyAddedThisUpdate = false;
      SymbolData[symbolIndex].StackLastTrailUpdate = false;
      SymbolData[symbolIndex].TPActivated = false;
      SymbolData[symbolIndex].InitialTP = 0;
      SymbolData[symbolIndex].TrailLocked = (LockTrail != LOCK_TRAIL_NONE);
      SymbolData[symbolIndex].LockBreakEvenPrice = 0;
      SymbolData[symbolIndex].LockTPReached = false;
      SymbolData[symbolIndex].HasPendingTrail = false;
      SymbolData[symbolIndex].PendingTrailSL = 0;

      SymbolData[symbolIndex].NonGridStack.Counter = 0;
      SymbolData[symbolIndex].NonGridStack.LastProcessedCounter = 0;
      SymbolData[symbolIndex].NonGridStack.SLMovedThisTick = false;
      SymbolData[symbolIndex].NonGridStack.LastSLMoveTime = 0;
      SymbolData[symbolIndex].NonGridStack.LastSLPrice = 0;

      SymbolData[symbolIndex].GridStack.Counter = 0;
      SymbolData[symbolIndex].GridStack.LastProcessedCounter = 0;
      SymbolData[symbolIndex].GridStack.SLMovedThisTick = false;
      SymbolData[symbolIndex].GridStack.LastSLMoveTime = 0;
      SymbolData[symbolIndex].GridStack.LastSLPrice = 0;

      SymbolData[symbolIndex].NonGridSLMovedThisTick = false;
      SymbolData[symbolIndex].GridSLMovedThisTick = false;
      SmartHedge_ResetSymbol(symbolIndex);

      if(!keepNormalSequenceState)
         SymbolData[symbolIndex].ZoneActive = false;
   }
}

//+------------------------------------------------------------------+

































#endif // __MULTIBOTPRO_GRIDZONE_MQH__

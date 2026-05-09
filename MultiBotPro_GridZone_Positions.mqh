#ifndef __MULTIBOTPRO_GRIDZONE_POSITIONS_MQH__
#define __MULTIBOTPRO_GRIDZONE_POSITIONS_MQH__
//+------------------------------------------------------------------+
//|                              MultiBotPro_GridZone_Positions.mqh   |
//|                         Trade execution, bridge helpers, position |
//|                         tracking and management                   |
//|                                  Copyright 2025, MetaQuotes Ltd.  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://discord.com/channels/929723953415589918/929723953415589920"

// 1. Define a global or static variable for safety
static ulong LastTradeAttemptTime = 0;

//+------------------------------------------------------------------+
//| Manage all positions on tick - FIXED (Delayed Trail Integration) |
//+------------------------------------------------------------------+
void ManageAllPositionsOnTick(int symbolIndex)
  {
// 1. Define Context
   string analysisSymbol = SymbolData[symbolIndex].symbol;
   string trackingSymbol = GetBaseSymbol(analysisSymbol);
   bool filterByBasket = InpEnableMultiBaskets;

// 2. Extract basketId from current positions for this symbol
   int basketId = BasketRuntimeIdForIndex(symbolIndex);
   ulong masterTicket = SymbolData[symbolIndex].MasterTicket;
   string comment = "";
   if(masterTicket != 0 && PositionSelectByTicket(masterTicket))
     {
      comment = PositionGetString(POSITION_COMMENT);
      basketId = BasketIdFromCommentOrDefault(comment, basketId);
     }
   SBasketState* basketState = GetOrCreateBasketState(symbolIndex, basketId);
   if(basketState != NULL && basketState.BasketId >= 0)
      MirrorBasketStateToSymbol(symbolIndex, basketState);

// =============================================================================
// BRANCH A: GRID OR ZONE RECOVERY MODE
// =============================================================================
   if(RiskMode == RISK_MODE_GRID || RiskMode == RISK_MODE_ZONE_RECOVERY)
     {
      if(basketState != NULL && (basketState.GridPhase2Active || SymbolData[symbolIndex].GridPhase2Active))
        {
         ManageGridPhase2(symbolIndex, basketId);
         return;
        }
      else
         if(RiskMode == RISK_MODE_GRID && (SymbolData[symbolIndex].GridTargetReached || (basketState != NULL && basketState.GridTargetReached)))
           {
            TransitionToGridPhase2(symbolIndex, basketId);
            return;
           }
     }

// =============================================================================
// BRANCH B: NORMAL MODE (Standard SL/TP & Trailing)
// =============================================================================
   if(RiskMode == RISK_MODE_NONE)
     {
      // BUG-B1 FIX: Reuse outer-scope masterTicket instead of shadowing it
      masterTicket = SymbolData[symbolIndex].MasterTicket;
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
         // BUG-B2 FIX: Reuse outer-scope comment instead of shadowing it
         comment = PositionGetString(POSITION_COMMENT);
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
   int basketId = BasketRuntimeIdForIndex(symbolIndex);
   SBasketState* basketState = GetOrCreateBasketState(symbolIndex, basketId);
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
         if(basketState != NULL)
            basketState.GridPhase1Active = true;
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
                  SymbolData[symbolIndex].GridPhase1Active = true;
                  SymbolData[symbolIndex].GridPhase2Active = false;
                  SymbolData[symbolIndex].GridTargetReached = false;
                  SymbolData[symbolIndex].GridTPHit = false;
                  SymbolData[symbolIndex].GridTPHitPrice = 0.0;
                  if(basketState != NULL)
                    {
                     basketState.GridPhase1Active = true;
                     basketState.GridPhase2Active = false;
                     basketState.GridTargetReached = false;
                     basketState.GridTargetProfit = SymbolData[symbolIndex].GridTargetProfit;
                     basketState.CurrentRecoveryPortion = 0.0;
                     basketState.GridTPHit = false;
                     basketState.GridTPHitPrice = 0.0;
                    }

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
                  if(basketState != NULL)
                    {
                     basketState.GridPhase1Active = true;
                     basketState.GridPhase2Active = false;
                    }
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
                  SymbolData[symbolIndex].GridPhase1Active = true;
                  SymbolData[symbolIndex].GridPhase2Active = false;
                  SymbolData[symbolIndex].GridTargetReached = false;

                  // CLEAN START: Set Base Target only.
                  SymbolData[symbolIndex].GridTargetProfit = ZoneTP_Amount;
                  SymbolData[symbolIndex].CurrentRecoveryPortion = 0.0;
                  SymbolData[symbolIndex].GridTPHit = false;
                  SymbolData[symbolIndex].GridTPHitPrice = 0.0;
                  if(basketState != NULL)
                    {
                     basketState.ZoneTopPrice = SymbolData[symbolIndex].ZoneTopPrice;
                     basketState.ZoneBottomPrice = SymbolData[symbolIndex].ZoneBottomPrice;
                     basketState.ZoneActive = true;
                     basketState.ZoneSeqCount = SymbolData[symbolIndex].ZoneSeqCount;
                     basketState.ZoneResolved = false;
                     basketState.GridPhase1Active = true;
                     basketState.GridPhase2Active = false;
                     basketState.GridTargetReached = false;
                     basketState.GridTargetProfit = SymbolData[symbolIndex].GridTargetProfit;
                     basketState.CurrentRecoveryPortion = 0.0;
                     basketState.GridTPHit = false;
                     basketState.GridTPHitPrice = 0.0;
                    }

                  DrawGridLine(BasketScopedObjectName(symbolIndex, "ZoneTop_", execSymbol), SymbolData[symbolIndex].ZoneTopPrice, clrGreen);
                  DrawGridLine(BasketScopedObjectName(symbolIndex, "ZoneBot_", execSymbol), SymbolData[symbolIndex].ZoneBottomPrice, clrRed);

                  Print(execSymbol, " Zone Started. Top: ", SymbolData[symbolIndex].ZoneTopPrice, " Bot: ", SymbolData[symbolIndex].ZoneBottomPrice, " Target: $", SymbolData[symbolIndex].GridTargetProfit);
                 }
               else
                 {
                  // --- SCENARIO 2: RECOVERY HEDGE (Trade #2+) ---
                  SymbolData[symbolIndex].ZoneSeqCount++;
                  if(basketState != NULL)
                    {
                     basketState.ZoneSeqCount = SymbolData[symbolIndex].ZoneSeqCount;
                     basketState.ZoneActive = true;
                    }
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
            SymbolData[symbolIndex].GridBasketVolume += lotPerTrade;

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

#endif // __MULTIBOTPRO_GRIDZONE_POSITIONS_MQH__

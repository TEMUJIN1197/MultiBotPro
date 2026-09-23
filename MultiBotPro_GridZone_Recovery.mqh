#ifndef __MULTIBOTPRO_GRIDZONE_RECOVERY_MQH__
#define __MULTIBOTPRO_GRIDZONE_RECOVERY_MQH__
//+------------------------------------------------------------------+
//|                             MultiBotPro_GridZone_Recovery.mqh    |
//|                Phase transitions, zone recovery, volume balance   |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://discord.com/channels/929723953415589918/929723953415589920"

//+------------------------------------------------------------------+
//| Transition to grid phase 2 - UPDATED (Fixed: Bank Merger Logic)  |
//+------------------------------------------------------------------+
void TransitionToGridPhase2(int symbolIndex, int basketId)
  {
   SBasketState* basketState = GetOrCreateBasketState(symbolIndex, basketId);
   if(basketState == NULL) return;
   if(basketState.GridTargetProfit > 0.0)
      SymbolData[symbolIndex].GridTargetProfit = basketState.GridTargetProfit;
   if(basketState.CurrentRecoveryPortion > 0.0)
      SymbolData[symbolIndex].CurrentRecoveryPortion = basketState.CurrentRecoveryPortion;
   if(basketState.GridTPHitPrice > 0.0)
      SymbolData[symbolIndex].GridTPHitPrice = basketState.GridTPHitPrice;

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
   double activeRecoveryPortion = MathMax(SymbolData[symbolIndex].CurrentRecoveryPortion, basketState.CurrentRecoveryPortion);
   if(UsePruningRecovery && activeRecoveryPortion > 0)
     {
      if(MBP_LogTierEnabled(MBP_LOG_TIER_DEBUG)) Print(trackingSymbol, " Phase 2 Transition. Recovery Portion ($", DoubleToString(activeRecoveryPortion, 2), ") will be reconciled on Close.");
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

               if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(trackingSymbol, " Grid Target Reached! Debt Paid: $", DoubleToString(SymbolData[symbolIndex].CurrentRecoveryPortion, 2),
                     ". Remaining Debt: $", DoubleToString(SymbolData[symbolIndex].AccumulatedPruningLoss, 2));

               // --- ITERATION LOGIC ---
               if(SymbolData[symbolIndex].AccumulatedPruningLoss > 1.0)
                 {
                  // Only increment if NO pruning happened during this sequence
                  if(!SymbolData[symbolIndex].PruningOccurredThisSequence)
                    {
                     SymbolData[symbolIndex].RecoveryIteration++;
                     if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(symbol, " Clean Success! Increasing Recovery Speed -> Next Iteration: ", SymbolData[symbolIndex].RecoveryIteration);
                    }
                  else
                    {
                     if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(symbol, " Success (with Pruning). Keeping Recovery Speed at Base (Iteration 1).");
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
                  if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(trackingSymbol, " Transitioned via Single Entry (Impulse). Debt preserved in Bank.");
               else
                  if(!profitMet)
                     if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(trackingSymbol, " Profit Target Missed ($", DoubleToString(basketNetProfit, 2), " < ", DoubleToString(target, 2), "). Debt preserved.");
              }
      */
      // Always reset current portion so we don't double count it or refund it later
      SymbolData[symbolIndex].CurrentRecoveryPortion = 0.0;
      basketState.CurrentRecoveryPortion = 0.0;
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
         SaveBankState(symbolIndex);

         if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(trackingSymbol, " 💥 Critical bank merge: transferred $", DoubleToString(transferAmount, 2),
               " to the main debt bank. Recovery restarts next cycle.");

         // Reset iteration to 1 to prevent aggressive multipliers immediately after taking a massive hit
         SymbolData[symbolIndex].RecoveryIteration = 1;
        }
     }
// ==================================================================


// OPTION A: Close Everything (Default)
   if(GridCloseOnTP)
     {
      CloseAllGridPositions(symbolIndex, "Grid TP Reached - Closing All");
      basketState.GridPhase1Active = false;
      basketState.GridPhase2Active = false;
      SymbolData[symbolIndex].GridPhase1Active = false;
      SymbolData[symbolIndex].GridPhase2Active = false;
      ResetGridTracking(symbolIndex, false, basketId);
     }
// OPTION B: Secure and Trail (Basket SL Mode)
   else
     {
      // 1. Calculate grid basket metrics (Average Entry, etc.)
      CalculateGridBasket(symbolIndex);

      // 2. Set Basket SL to the Hit Price (Guarantees the GridTP_Amount)
      // Note: We use the stored GridTPHitPrice because that represents where we hit the dollar target.
      double basketHitPrice = basketState.GridTPHitPrice;
      if(basketHitPrice <= 0.0)
         basketHitPrice = SymbolData[symbolIndex].GridTPHitPrice;

      if(basketHitPrice > 0)
        {
         SymbolData[symbolIndex].GridBasketStopLoss = basketHitPrice;
        }
      else
        {
         // Fallback
         SymbolData[symbolIndex].GridBasketStopLoss = SymbolData[symbolIndex].GridBasketEntry; // Break Even fallback
        }

      // Normalize SL
      SymbolData[symbolIndex].GridBasketStopLoss = NormalizePrice(trackingSymbol, SymbolData[symbolIndex].GridBasketStopLoss);
      basketState.GridBasketStopLoss = SymbolData[symbolIndex].GridBasketStopLoss;

      // 3. Set Phase Flags before applying stops; zone mode uses this gate.
      basketState.GridPhase1Active = false;
      basketState.GridPhase2Active = true;
      basketState.GridTargetReached = true;
      SymbolData[symbolIndex].GridPhase1Active = false;
      SymbolData[symbolIndex].GridPhase2Active = true;
      SymbolData[symbolIndex].GridTargetReached = true;
      SymbolData[symbolIndex].GridTPHit = basketState.GridTPHit;
      SymbolData[symbolIndex].GridTPHitPrice = basketHitPrice;

      // 4. Apply Basket SL to all grid/zone positions
      UpdateAllGridStopLosses(symbolIndex);

      // Enable Trailing (Uses Standard Non-Grid settings)
      SymbolData[symbolIndex].GridInTrailing = UseTrailing;
      // Enable Stacking (Uses Standard Non-Grid settings)
      SymbolData[symbolIndex].GridInStacking = (StackMode && UseTrailing);
      basketState.GridInTrailing = SymbolData[symbolIndex].GridInTrailing;
      basketState.GridInStacking = SymbolData[symbolIndex].GridInStacking;

      SymbolData[symbolIndex].PreviousBasketSL = SymbolData[symbolIndex].GridBasketStopLoss;
      SymbolData[symbolIndex].GridTrailUpdates = 0;
      basketState.GridTrailUpdates = 0;
      basketState.GridStackLevels = 0;
      basketState.LastStackLot = 0.0;
      basketState.LastStackMult = 1.0;

      // RESET GRID STACK COUNTER (CRITICAL for Stacking to work)
      SymbolData[symbolIndex].GridStack.Counter = 0;
      SymbolData[symbolIndex].GridStack.LastProcessedCounter = 0;
      SymbolData[symbolIndex].GridStack.SLMovedThisTick = false;
      SymbolData[symbolIndex].GridSLMovedThisTick = false;
      basketState.GridStack = SymbolData[symbolIndex].GridStack;
      basketState.HasPendingTrail = false;
      basketState.PendingTrailSL = 0.0;

      if(MBP_LogTierEnabled(MBP_LOG_TIER_DEBUG)) Print(trackingSymbol, " Transitioned to Grid Phase 2 (Basket Secured at Hit Price)");
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("  - Basket SL: ", SymbolData[symbolIndex].GridBasketStopLoss);
      SmartHedge_OnProtectedStopMove(symbolIndex, true);
     }
  }

//+------------------------------------------------------------------+
//| Manage grid phase 2 positions - FIXED FOR BROKER CLOSE           |
//+------------------------------------------------------------------+
void ManageGridPhase2(int symbolIndex, int basketId)
{
   SBasketState* basketState = GetOrCreateBasketState(symbolIndex, basketId);
   if(basketState == NULL) return;
   MirrorBasketStateToSymbol(symbolIndex, basketState);

   string trackingSymbol = GetBaseSymbol(SymbolData[symbolIndex].symbol);

// 1. Calculate Open Volume (Live Check)
   double buyVol = 0;
   double sellVol = 0;
   int liveGridCount = 0; // Local count

   for(int i = 0; i < PositionsTotal(); i++)
     {
      if(PositionSelectByTicket(PositionGetTicket(i)))
        {
         // BUG-B4 FIX: Use IsAppTrade() for worker-mode compatibility
         if(PositionGetString(POSITION_SYMBOL) == trackingSymbol && IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
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
// If the sequence reached Phase 2 but we find 0 live trades,
// it means the Broker (SL/TP) closed them between ticks.
   bool hadActiveSequence = (SymbolData[symbolIndex].GridLevels > 0 ||
                             SymbolData[symbolIndex].ZoneSeqCount > 0 ||
                             basketState.ZoneSeqCount > 0 ||
                             SymbolData[symbolIndex].GridPhase2Active ||
                             basketState.GridPhase2Active);

   if(liveGridCount == 0 && hadActiveSequence)
     {
      if(MBP_LogTierEnabled(MBP_LOG_TIER_DEBUG)) Print(trackingSymbol, " Phase 2: All trades disappeared (Broker Close). Processing Result...");

      // Calculate profit from History instead of Open Trades
      ProcessClosedSequence(symbolIndex);

      // Reset Everything
      basketState.GridPhase1Active = false;
      basketState.GridPhase2Active = false;
      SymbolData[symbolIndex].GridPhase1Active = false;
      SymbolData[symbolIndex].GridPhase2Active = false;
      // BUG-B7 FIX: Single ResetGridTracking call (was duplicated before)
      ResetGridTracking(symbolIndex, false, basketId);
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
   MirrorSymbolToBasketState(symbolIndex, basketState);

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
         if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(trackingSymbol, " BASKET SL HIT (Active Monitor). Closing Everything.");
      // This works because trades are still open
      CloseAllGridPositions(symbolIndex, "Basket SL Hit");

      basketState.GridPhase1Active = false;
      basketState.GridPhase2Active = false;
      SymbolData[symbolIndex].GridPhase1Active = false;
      SymbolData[symbolIndex].GridPhase2Active = false;
      ResetGridTracking(symbolIndex, false, basketId);
     }
    }
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

   string symbol = SymbolData[symbolIndex].symbol;
   string execSymbol = GetBaseSymbol(symbol);

   double bid = SymbolInfoDouble(execSymbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(execSymbol, SYMBOL_ASK);

   ENUM_POSITION_TYPE lastType = POSITION_TYPE_BUY;
   datetime lastTime = 0;
   int lastBasketId = BasketRuntimeIdForIndex(symbolIndex);

// Find Last Trade Type and extract its basketId
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
               lastBasketId = BasketIdFromCommentOrDefault(comment, lastBasketId);
              }
           }
        }
     }

   if(TimeCurrent() - lastTime < 2 || lastBasketId < 0)
      return;

   SBasketState* basketState = GetOrCreateBasketState(symbolIndex, lastBasketId);
   if(basketState == NULL) return;
   MirrorBasketStateToSymbol(symbolIndex, basketState);

   if(basketState.GridPhase2Active)
      return;

// Safety: Ensure Zone Levels exist
   if(basketState.ZoneTopPrice == 0)
     {
      basketState.ZoneActive = false;
      ObjectDelete(0, BasketScopedObjectName(symbolIndex, "ZoneTop_", execSymbol));
      ObjectDelete(0, BasketScopedObjectName(symbolIndex, "ZoneBot_", execSymbol));
      return;
     }

// Visuals
   if(basketState.ZoneActive)
     {
      DrawGridLine(BasketScopedObjectName(symbolIndex, "ZoneTop_", execSymbol), basketState.ZoneTopPrice, clrGreen);
      DrawGridLine(BasketScopedObjectName(symbolIndex, "ZoneBot_", execSymbol), basketState.ZoneBottomPrice, clrRed);
     }

// Helper to identify if this is the transition from Entry -> Zone (First Hedge)
// Logic: If ZoneActive is false (Entry only) OR ZoneSeqCount is 1 (Entry Only)
   bool isFirstHedgeTrigger = (!basketState.ZoneActive || basketState.ZoneSeqCount == 1);

// ---------------------------------------------------------
// TRIGGER LOGIC
// ---------------------------------------------------------

   bool triggerBuy = (ask >= basketState.ZoneTopPrice && lastType == POSITION_TYPE_SELL);
   bool triggerSell = (bid <= basketState.ZoneBottomPrice && lastType == POSITION_TYPE_BUY);

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

            if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(execSymbol, " 🎯 Recovery target set. Iteration: ", (int)mult,
                  " | Portion allocated: $", DoubleToString(portion, 2),
                  " | Pending deduction on success.");
           }

         // 5. Set The Fixed Target Profit for this Sequence
         // --- NEW: Calculate Dynamic Target for Zone ---
         double dynamicTarget = GetDynamicProfitTarget(symbolIndex);
         basketState.CurrentRecoveryPortion = portion;
         basketState.GridTargetProfit = dynamicTarget + portion;
         SymbolData[symbolIndex].CurrentRecoveryPortion = basketState.CurrentRecoveryPortion;
         SymbolData[symbolIndex].GridTargetProfit = basketState.GridTargetProfit;

         // Ensure Zone Active Flag is Set
         basketState.ZoneActive = true;
         SymbolData[symbolIndex].ZoneActive = true;
        }

      // C. CALCULATE LOT SIZE
      // We pass the NEXT order type to solve for the lot size that achieves the target
      double lot = CalculateZoneRecoveryLot(symbolIndex, orderType);

      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(execSymbol, " Zone Trigger! Opening ", EnumToString(orderType), " | Calc Lot: ", lot);

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

// Extract basketId from zone positions
   int lastBasketId = BasketRuntimeIdForIndex(symbolIndex);
   datetime lastTime = 0;

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

               // Track most recent position to extract basketId
               datetime posTime = (datetime)PositionGetInteger(POSITION_TIME);
               if(posTime > lastTime)
                 {
                  lastTime = posTime;
                  lastBasketId = BasketIdFromCommentOrDefault(comment, lastBasketId);
                 }
              }
           }
        }
     }

   if(tradeCount == 0 || lastBasketId < 0)
     {
      // No zone positions; nothing to manage
      return;
     }

   // Resolve basket state for this zone sequence
   SBasketState* basketState = GetOrCreateBasketState(symbolIndex, lastBasketId);
   if(basketState == NULL) return;
   MirrorBasketStateToSymbol(symbolIndex, basketState);

   // Already in Phase 2 — CheckZoneTarget is not needed
   if(basketState.GridPhase2Active)
      return;

   if(tradeCount == 0)
     {
      if(basketState.ZoneActive)
        {
         basketState.ZoneActive = false;
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
   if(basketState.ZoneSeqCount == 1)
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
      if(!basketState.GridTPHit)
        {
         bool hitX = (initialType == POSITION_TYPE_BUY && currentPrice >= priceX) ||
                     (initialType == POSITION_TYPE_SELL && currentPrice <= priceX);

         if(hitX)
           {
            basketState.GridTPHit = true;
            basketState.GridTPHitPrice = priceX; // Lock SL exactly at Price X
            SymbolData[symbolIndex].GridTPHit = true;
            SymbolData[symbolIndex].GridTPHitPrice = priceX;
            //Print(trackingSymbol, " Zone Impulse Hit at ", priceX, ". Waiting for Buffer (", DoubleToString(bufferDist/_Point,0), " pts)...");
           }
        }

      // 4. STEP 2: CHECK BUFFER (If Marked)
      if(basketState.GridTPHit)
        {
         bool bufferCleared = false;
         double triggerPrice = 0.0;

         if(initialType == POSITION_TYPE_BUY)
           {
            triggerPrice = basketState.GridTPHitPrice + bufferDist;
            if(currentPrice >= triggerPrice)
               bufferCleared = true;
           }
         else
           {
            triggerPrice = basketState.GridTPHitPrice - bufferDist;
            if(currentPrice <= triggerPrice)
               bufferCleared = true;
           }

         if(bufferCleared)
           {
            readyToTransition = true;
            if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(trackingSymbol, " Zone Buffer Cleared! Locking SL at Price X.");
           }
        }
     }
// =======================================================================
// LOGIC B: RECOVERY MODE (Standard Dollar Target)
// =======================================================================
   else
     {
      if(totalProfit >= basketState.GridTargetProfit)
        {
         if(ZoneCloseOnTP)
           {
            if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(trackingSymbol, " Zone TP Hit ($", totalProfit, ") - Closing All.");
            CloseAllGridPositions(symbolIndex, "Zone TP Hit");
            basketState.ZoneActive = false;
            basketState.ZoneResolved = true;
            SymbolData[symbolIndex].ZoneActive = false;
            SymbolData[symbolIndex].ZoneResolved = true;
            // Clear objects
            ObjectDelete(0, BasketScopedObjectName(symbolIndex, "ZoneTop_", trackingSymbol));
            ObjectDelete(0, BasketScopedObjectName(symbolIndex, "ZoneBot_", trackingSymbol));

            // Clean up debt tracking (AccumulatedPruningLoss and RecoveryIteration remain symbol-level)
            if(UsePruningRecovery && basketState.CurrentRecoveryPortion > 0)
              {
               SymbolData[symbolIndex].AccumulatedPruningLoss -= basketState.CurrentRecoveryPortion;
               if(SymbolData[symbolIndex].AccumulatedPruningLoss < 0)
                  SymbolData[symbolIndex].AccumulatedPruningLoss = 0;
               basketState.CurrentRecoveryPortion = 0.0;
               SymbolData[symbolIndex].CurrentRecoveryPortion = 0.0;
               if(SymbolData[symbolIndex].AccumulatedPruningLoss > 1.0)
                  SymbolData[symbolIndex].RecoveryIteration++;
               else
                  SymbolData[symbolIndex].RecoveryIteration = 1;
               SaveBankState(symbolIndex);
              }
            return;
           }
         else
           {
            // Transition Logic for Recovery (Uses standard Dollar Hit -> Buffer)
            if(!basketState.GridTPHit)
              {
               basketState.GridTPHit = true;
               basketState.GridTPHitPrice = currentPrice; // Lock at current price (dollar-based)
               SymbolData[symbolIndex].GridTPHit = true;
               SymbolData[symbolIndex].GridTPHitPrice = currentPrice;
               if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(trackingSymbol, " Zone Recovery TP Met. Marked Price: ", currentPrice);
              }

            double point = SymbolInfoDouble(trackingSymbol, SYMBOL_POINT);
            double buffer = ZoneTransitionDist * point;

            if(winningIsBuy && currentPrice >= (basketState.GridTPHitPrice + buffer))
               readyToTransition = true;
            if(!winningIsBuy && currentPrice <= (basketState.GridTPHitPrice - buffer))
               readyToTransition = true;
           }
        }
     }

// =======================================================================
// EXECUTE TRANSITION
// =======================================================================
   if(readyToTransition)
     {
      if(MBP_LogTierEnabled(MBP_LOG_TIER_DEBUG)) Print(trackingSymbol, " 🔄 Zone phase 2 transition.");

      // Note: TransitionToGridPhase2 uses basketState.GridTPHitPrice as the SL.
      // In Logic A, we set this to "Price X" (Entry + Impulse).
      // In Logic B, we set this to "TP Hit Price".

      TransitionToGridPhase2(symbolIndex, lastBasketId);

      // Cleanup Zone Specifics
      basketState.ZoneActive = false;
      SymbolData[symbolIndex].ZoneActive = false;
      ObjectDelete(0, BasketScopedObjectName(symbolIndex, "ZoneTop_", trackingSymbol));
      ObjectDelete(0, BasketScopedObjectName(symbolIndex, "ZoneBot_", trackingSymbol));
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
         if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(execSymbol, " Soft Pruning (Zone): Closing Largest Opposite Trade: #", targetTicket);

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
               SaveBankState(symbolIndex);
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
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(execSymbol, " ⚠️ Hard zone pruning triggered.");

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
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("Volume Correction Skipped: Spread too high.");
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
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("⚠️ Zone imbalance detected.");
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("Winning (", EnumToString(winningDirection), ") Vol: ", winningVol, " | Losing Vol: ", losingVol);
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("Correcting balance by closing smallest opposite trades...");

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
               if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("Closed adjustment trade: ", smallestTicket, " (", smallestVol, " lots)");
               losingVol -= smallestVol; // Update local tracker
               if(MBP_ShouldAllowBlockingTradeWait("adjustment_close"))
                  Sleep(100); // Small delay for broker sync
              }
            else
              {
               if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print("Failed to close adjustment trade: ", GetLastError());
               break; // Stop if we can't close
              }
           }
         else
           {
            break; // No more trades found to close
           }

         maxLoops--;
        }

      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("Volume Correction Complete. New Status -> Win: ", winningVol, " vs Lose: ", losingVol);
     }
  }

#endif // __MULTIBOTPRO_GRIDZONE_RECOVERY_MQH__


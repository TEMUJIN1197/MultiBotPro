#ifndef __MULTIBOTPRO_GRIDZONE_ANALYSIS_MQH__
#define __MULTIBOTPRO_GRIDZONE_ANALYSIS_MQH__
//+------------------------------------------------------------------+
//|                              MultiBotPro_GridZone_Analysis.mqh   |
//|                Grid analysis, trailing, stacking, reconciliation  |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://discord.com/channels/929723953415589918/929723953415589920"

//+------------------------------------------------------------------+
//| Check grid on tick (throttled entry point)                       |
//+------------------------------------------------------------------+
void CheckGridOnTick(int symbolIndex)
  {
// Limit grid checks to avoid too frequent operations
   if(TimeCurrent() - SymbolData[symbolIndex].LastGridCheckTime < 1) // Check at most once per second
      return;

   SymbolData[symbolIndex].LastGridCheckTime = TimeCurrent();

   // Phase 2 / target-reached gate is enforced inside CheckNewGridLevel
   // via basketState.GridPhase2Active — no symbol-level flag needed here.
   CheckNewGridLevel(symbolIndex);
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

// 0. SCAN FOR LAST GRID PRICE (The "Worst" Entry) & extract basketId
   double lastGridPrice = 0;
   int currentGridCount = 0;
   ENUM_POSITION_TYPE gridType = POSITION_TYPE_BUY; // Default
   bool foundAny = false;
   int lastBasketId = BasketRuntimeIdForIndex(symbolIndex);
   datetime lastGridTime = 0;

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
               datetime posTime = (datetime)PositionGetInteger(POSITION_TIME);

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

               // Track most recent for basketId extraction
               if(posTime > lastGridTime)
                 {
                  lastGridTime = posTime;
                  lastBasketId = BasketIdFromCommentOrDefault(comment, lastBasketId);
                 }

               currentGridCount++;
              }
           }
        }
     }

// If no trades found on the ACTUAL execution symbol, reset and exit
   if(!foundAny || lastBasketId < 0)
     {
      ObjectDelete(0, lineName);
      SymbolData[symbolIndex].GridLevels = 0;
      return;
     }

   // Resolve basket state
   SBasketState* basketState = GetOrCreateBasketState(symbolIndex, lastBasketId);
   if(basketState == NULL) return;

// CLEANUP CHECK - already in Phase 2
   if(basketState.GridPhase2Active)
     {
      ObjectDelete(0, lineName);
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
      if(UsePruningRecovery && SymbolData[symbolIndex].AccumulatedPruningLoss > 0 && basketState.CurrentRecoveryPortion == 0)
        {
         double mult = SymbolData[symbolIndex].RecoveryIteration;
         double pct = PruningRecovPercent * mult;
         if(pct > 100.0)
            pct = 100.0;

         pendingPortion = SymbolData[symbolIndex].AccumulatedPruningLoss * (pct / 100.0);
         if(pendingPortion < 0.01)
            pendingPortion = SymbolData[symbolIndex].AccumulatedPruningLoss;

         // Set Target = Dynamic Base + Debt
         basketState.GridTargetProfit = currentBaseTarget + pendingPortion;
         SymbolData[symbolIndex].GridTargetProfit = basketState.GridTargetProfit;
         recoveryActive = true;
        }
      else
        {
         // No debt? Just set the Dynamic Base
         basketState.GridTargetProfit = currentBaseTarget;
         SymbolData[symbolIndex].GridTargetProfit = basketState.GridTargetProfit;
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
            basketState.GridTargetProfit = currentBaseTarget + pendingPortion;
            SymbolData[symbolIndex].GridTargetProfit = basketState.GridTargetProfit;
           }
        }

      // --- STEP D: FINALIZE DEBT TRACKING ---
      if(recoveryActive)
        {
         basketState.CurrentRecoveryPortion = pendingPortion;
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
                  // BUG-B5 FIX: Use IsAppTrade() for worker-mode compatibility
                  if(PositionGetString(POSITION_SYMBOL) == execSymbol && IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
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
                     SaveBankState(symbolIndex);
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

   if(TimeCurrent() - SymbolData[symbolIndex].LastTradeTime < 1)
      return;

// 1. GATHER DATA & extract basketId
   double totalGridProfit = 0;
   int gridCount = 0;
   double initialEntry = 0;
   ENUM_POSITION_TYPE direction = POSITION_TYPE_BUY;
   int lastBasketId = BasketRuntimeIdForIndex(symbolIndex);
   datetime lastGridTime = 0;

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

               // Track most recent for basketId
               datetime posTime = (datetime)PositionGetInteger(POSITION_TIME);
               if(posTime > lastGridTime)
                 {
                  lastGridTime = posTime;
                  lastBasketId = BasketIdFromCommentOrDefault(comment, lastBasketId);
                 }
              }
           }
        }
     }

   if(gridCount == 0 || lastBasketId < 0)
      return;

   // Resolve basket state
   SBasketState* basketState = GetOrCreateBasketState(symbolIndex, lastBasketId);
   if(basketState == NULL) return;

   // Already in Phase 2 — nothing to do here
   if(basketState.GridPhase2Active)
      return;

   double currentPrice = (direction == POSITION_TYPE_BUY) ?
                         SymbolInfoDouble(trackingSymbol, SYMBOL_BID) :
                         SymbolInfoDouble(trackingSymbol, SYMBOL_ASK);

   bool readyToTransition = false;

// =================================================================
// LOGIC A: IMPULSE TRANSITION (Single Trade Phase 1)
// =================================================================
   if(gridCount == 1)
     {
      double atr[1];
      double atrVal = 0;
      if(CopyBuffer(SymbolData[symbolIndex].ATR_Handle, 0, 0, 1, atr) > 0)
         atrVal = atr[0];
      if(atrVal == 0)
         atrVal = SymbolInfoDouble(trackingSymbol, SYMBOL_POINT) * 50;

      double impulseDist = atrVal * GridImpulseATR;
      double bufferDist  = 0.0;

      if(GridTransitionType == GRID_DIST_POINTS)
         bufferDist = GridTransitionDist * SymbolInfoDouble(trackingSymbol, SYMBOL_POINT);
      else
         bufferDist = atrVal * GridTransitionDist;

      double priceX = (direction == POSITION_TYPE_BUY) ? (initialEntry + impulseDist) : (initialEntry - impulseDist);

      // STEP 1: MARK PRICE X
      if(!basketState.GridTPHit)
        {
         bool hitX = (direction == POSITION_TYPE_BUY && currentPrice >= priceX) ||
                     (direction == POSITION_TYPE_SELL && currentPrice <= priceX);

         if(hitX)
           {
            basketState.GridTPHit = true;
            basketState.GridTPHitPrice = priceX;
            SymbolData[symbolIndex].GridTPHit = true;
            SymbolData[symbolIndex].GridTPHitPrice = priceX;
           }
        }

      // STEP 2: CHECK BUFFER
      if(basketState.GridTPHit)
        {
         bool bufferCleared = false;
         double triggerPrice = 0.0;

         if(direction == POSITION_TYPE_BUY)
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
            Print(trackingSymbol, " Grid Buffer Cleared! Locking SL at Price X.");
           }
        }
     }

// =================================================================
// LOGIC B: DOLLAR TARGET (Recovery / Multiple Trades)
// =================================================================
   if(!readyToTransition && totalGridProfit >= basketState.GridTargetProfit)
     {
      if(!basketState.GridTPHit)
        {
         basketState.GridTPHit = true;
         basketState.GridTPHitPrice = currentPrice;
         SymbolData[symbolIndex].GridTPHit = true;
         SymbolData[symbolIndex].GridTPHitPrice = currentPrice;
        }

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

      double hitPrice = basketState.GridTPHitPrice;

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
      // Reset hit flag if profit drops back significantly (Dollar Logic only)
      if(!readyToTransition && basketState.GridTPHit && gridCount > 1 &&
         totalGridProfit < (basketState.GridTargetProfit * 0.8))
        {
         basketState.GridTPHit = false;
         basketState.GridTPHitPrice = 0;
         SymbolData[symbolIndex].GridTPHit = false;
         SymbolData[symbolIndex].GridTPHitPrice = 0;
        }
     }

// EXECUTE TRANSITION
   if(readyToTransition)
     {
      if(HideSLTPDuringCloseBlock && G_Cache_IsDailyCloseBlock && GridCloseOnTP) return;
      basketState.GridTargetReached = true;
      SymbolData[symbolIndex].GridTargetReached = true;
      TransitionToGridPhase2(symbolIndex, lastBasketId);
     }
  }

//+------------------------------------------------------------------+
//| Check and calculate trailing stop conditions (Fixed Full Version)|
//+------------------------------------------------------------------+
void CheckGridTrailingConditions(int symbolIndex)
{
   string trackingSymbol = SymbolData[symbolIndex].symbol;
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
         // ATR Safety Check: Ensure Handle is valid and we get data
         if(SymbolData[symbolIndex].ATR_Handle != INVALID_HANDLE &&
            CopyBuffer(SymbolData[symbolIndex].ATR_Handle, 0, 0, 1, atr) > 0)
           {
            double atrValue = atr[0];

            // Proceed only if ATR is valid
            if(atrValue > 0)
            {
               double stepDist = atrValue * TrailATR_Update;

               if(trailDirection == POSITION_TYPE_BUY)
                 {
                  double requiredDist = atrValue * TrailATR_Multiplier;

                  // Calculate raw candidate
                  double candidateSL = currentPrice - requiredDist;

                  // FIX: Normalize candidate to symbol digits immediately
                  candidateSL = NormalizeDouble(candidateSL, symDigits);

                  // --- FIX 2: HANDLE INITIALIZATION (CurrentSL == 0) ---
                  // If SL is 0, we accept the first valid calculation immediately.
                  // Otherwise, we require the move to be larger than 'stepDist'.
                  if(currentSL == 0 || candidateSL > (currentSL + stepDist))
                    {
                     newSL = candidateSL;
                    }
                 }
               else // SELL
                 {
                  double requiredDist = atrValue * TrailATR_Multiplier;

                  // Calculate raw candidate
                  double candidateSL = currentPrice + requiredDist;

                  // FIX: Normalize candidate to symbol digits immediately
                  candidateSL = NormalizeDouble(candidateSL, symDigits);

                  // --- FIX 2: HANDLE INITIALIZATION (CurrentSL == 0) ---
                  // If SL is 0, we accept the first valid calculation immediately.
                  // Otherwise, we require the move to be lower than 'currentSL - stepDist'.
                  if(currentSL == 0 || candidateSL < (currentSL - stepDist))
                    {
                     newSL = candidateSL;
                    }
                 }
            }
           }
         else
           {
            // Debug throttle to avoid spamming logs if ATR fails
            if(SymbolData[symbolIndex].GridPhase2Active && TimeCurrent() % 10 == 0)
               Print(trackingSymbol, " Warning: ATR CopyBuffer Failed. Trailing Stopped.");
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
                     if(MathAbs(currentSL - validLevel) > _Point)
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
                           if(MathAbs(currentSL - validLevel) > _Point)
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
                           if(MathAbs(currentTP - validLevel) > _Point)
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
                           if(MathAbs(currentSL - validLevel) > _Point)
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
                           if(MathAbs(currentTP - validLevel) > _Point)
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
                  Trade.PositionModify(ticket, newSL, newTP);
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
   ResetGridTracking(symbolIndex, skipReconciliation, BasketRuntimeIdForIndex(symbolIndex));
   }

//+------------------------------------------------------------------+
//| ResetGridTracking - UPDATED with Timestamp Protection            |
//+------------------------------------------------------------------+
void ResetGridTracking(int symbolIndex, bool skipReconciliation = false, int basketId = -1)
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

   // 2. Standard symbol-level resets
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
   if(InpEnableMultiBaskets && SymbolData[symbolIndex].PositionCount == 0 && CountGridPositions(symbolIndex, true) == 0)
     {
      SymbolData[symbolIndex].BasketActive = false;
      SymbolData[symbolIndex].BasketInitialEntry = 0.0;
     }

   // 3. Reset basket-level state
   if(basketId >= 0)
     {
      // Reset specific basket — keep object, just zero its fields
      SBasketState* bs = GetOrCreateBasketState(symbolIndex, basketId);
      if(bs != NULL)
        {
         bs.GridPhase1Active       = false;
         bs.GridPhase2Active       = false;
         bs.GridTargetReached      = false;
         bs.GridTPHit              = false;
         bs.GridTPHitPrice         = 0.0;
         bs.GridTargetProfit       = 0.0;
         bs.CurrentRecoveryPortion = 0.0;
         bs.ZoneActive             = false;
         bs.ZoneResolved           = false;
         bs.ZoneTopPrice           = 0.0;
         bs.ZoneBottomPrice        = 0.0;
         bs.ZoneNextLot            = 0.0;
         bs.ZoneSeqCount           = 0;
        }
     }
   else
     {
      // Global reset (basketId = -1): free ALL basket states for this symbol
      for(int i = 0; i < SymbolData[symbolIndex].BasketStateCount; i++)
        {
         if(CheckPointer(SymbolData[symbolIndex].BasketStates[i]) != POINTER_INVALID)
           {
            delete SymbolData[symbolIndex].BasketStates[i];
            SymbolData[symbolIndex].BasketStates[i] = NULL;
           }
        }
      SymbolData[symbolIndex].BasketStateCount = 0;
     }

   // 4. CRITICAL: UPDATE TIMESTAMP SAFELY
   if(SymbolData[symbolIndex].LastGridReset <= TimeCurrent())
   {
      SymbolData[symbolIndex].LastGridReset = TimeCurrent();
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
            SaveBankState(symbolIndex);
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
         SaveBankState(symbolIndex);
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
            SaveBankState(symbolIndex);
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
            SaveBankState(symbolIndex);
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
         SaveBankState(symbolIndex);
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

#endif // __MULTIBOTPRO_GRIDZONE_ANALYSIS_MQH__

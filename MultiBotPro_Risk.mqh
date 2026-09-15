#ifndef __MULTIBOTPRO_RISK_MQH__
#define __MULTIBOTPRO_RISK_MQH__
//+------------------------------------------------------------------+
//|                                             MultiBotPro_Risk.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://discord.com/channels/929723953415589918/929723953415589920"

double CalculateGridStartLotFromRisk(string execSymbol, int symbolIndex, double entryPrice,
                                      double stopLoss, ENUM_ORDER_TYPE orderType)
  {
   double lotSize = (GridFixedLot > 0.0) ? GridFixedLot : FixedLot;

   if(GridRiskType == RISK_FIXED_LOT)
      return lotSize;

   if(GridRiskType == RISK_PERCENT_EQUITY ||
      GridRiskType == RISK_PERCENT_BALANCE ||
      GridRiskType == RISK_FIXED_MONEY)
     {
      double tickVal  = SymbolInfoDouble(execSymbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(execSymbol, SYMBOL_TRADE_TICK_SIZE);

      // When no explicit SL is provided, derive the risk distance from the
      // grid step — the distance the price would need to move against the trade
      // to reach the next grid level. This gives a meaningful lot size even when
      // the user has not set a hard stop loss on grid entries.
      if(stopLoss <= 0 && symbolIndex >= 0 && tickSize > 0 && tickVal > 0)
        {
         double point = SymbolInfoDouble(execSymbol, SYMBOL_POINT);
         if(point <= 0.0) point = 1.0;

         double gridDist = 0.0;
         if(GridDistanceType == GRID_DIST_POINTS)
           {
            gridDist = GridDistance * point;
           }
         else // GRID_DIST_ATR
           {
            double atr[1];
            if(symbolIndex < ArraySize(SymbolData) &&
               CopyBuffer(SymbolData[symbolIndex].ATR_Handle, 0, 1, 1, atr) > 0)
               gridDist = atr[0] * GridDistance;
            else
               gridDist = MinGridDistance * point;
           }

         double minDist = MinGridDistance * point;
         if(gridDist < minDist) gridDist = minDist;

         // One grid step against the direction acts as the effective SL distance
         stopLoss = (orderType == ORDER_TYPE_BUY)
                    ? entryPrice - gridDist
                    : entryPrice + gridDist;

         if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(execSymbol, " [GridRisk] No SL set — using grid step (",
               DoubleToString(gridDist / point, 0), " pts) as effective SL distance for lot sizing.");
        }

      if(tickSize <= 0 || tickVal <= 0 || stopLoss <= 0)
        {
         if(GridRiskType == RISK_FIXED_MONEY && stopLoss <= 0)
            if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print("ERROR: Grid fixed money risk: could not derive SL distance. Reverting to GridFixedLot.");
         return lotSize;
        }

      double priceDist = MathAbs(entryPrice - stopLoss);
      double profitPerLot = (priceDist / tickSize) * tickVal;
      if(profitPerLot <= 0.000001)
         return lotSize;

      double riskAmt = 0.0;
      if(GridRiskType == RISK_FIXED_MONEY)
         riskAmt = GridRiskMoney;
      else if(GridRiskType == RISK_PERCENT_EQUITY)
         riskAmt = AccountInfoDouble(ACCOUNT_EQUITY) * (GridRiskPercent / 100.0);
      else
         riskAmt = AccountInfoDouble(ACCOUNT_BALANCE) * (GridRiskPercent / 100.0);

      if(riskAmt > 0.0)
         lotSize = riskAmt / profitPerLot;

      string typeStr = (GridRiskType == RISK_FIXED_MONEY) ? "FixedMoney" : "Percent";
      if(MBP_LogTierEnabled(MBP_LOG_TIER_DEBUG)) Print(execSymbol, " Grid ", typeStr, " Calc: Dist=", DoubleToString(priceDist, 5),
            " | Val/Lot=$", DoubleToString(profitPerLot, 2),
            " | TargetRisk=$", DoubleToString(riskAmt, 2),
            " -> Lots: ", DoubleToString(lotSize, 2));
     }

   return lotSize;
  }

//+------------------------------------------------------------------+
//| Calculate lot size for symbol (UPDATED with Fixed Money Risk)    |
//+------------------------------------------------------------------+
double CalculateLotSize(int symbolIndex, double entryPrice, double stopLoss, ENUM_ORDER_TYPE orderType = ORDER_TYPE_BUY)
  {
   // 1. Get Symbol Names
   string analysisSymbol = SymbolData[symbolIndex].symbol;
   string execSymbol     = GetBaseSymbol(analysisSymbol); // The symbol we actually trade on
   
   // 2. Get Broker Limits for this specific symbol
   double minLot = SymbolInfoDouble(execSymbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(execSymbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(execSymbol, SYMBOL_VOLUME_STEP);

   // 3. Determine Context (What "Mode" is the bot in?)
   bool isGridActive = (RiskMode == RISK_MODE_GRID) && SymbolData[symbolIndex].GridLevels > 0;
   bool isGridStart  = (RiskMode == RISK_MODE_GRID) && SymbolData[symbolIndex].GridLevels == 0;
   bool isZoneStart  = (RiskMode == RISK_MODE_ZONE_RECOVERY) && !SymbolData[symbolIndex].ZoneActive;

   // ==============================================================================
   // CASE 1: Active Grid (Levels > 0) -> Use Stored Next Lot
   // ==============================================================================
   if(isGridActive && SymbolData[symbolIndex].RawNextGridLot > 0)
     {
      double finalLot = SymbolData[symbolIndex].RawNextGridLot;
      
      // Normalize to valid step
      finalLot = NormalizeDouble(finalLot / lotStep, 0) * lotStep;
      
      // Check limits
      if(finalLot < minLot) finalLot = minLot;
      if(finalLot > maxLot) finalLot = maxLot;
      
      return finalLot;
     }

   double lotSize = 0.0;

   // ==============================================================================
   // CASE 2: Zone Recovery Start (Explicit Logic)
   // ==============================================================================
   if(isZoneStart)
     {
      // Zone Start always uses FixedLot + Dynamic Stake Multiplier
      lotSize = FixedLot;

      if(UseDynamicStake)
        {
         lotSize *= SymbolData[symbolIndex].CurrentStakeMultiplier;
        }

      // Note: We deliberately do NOT apply StackMultiplier here
     }
   // ==============================================================================
   // CASE 3: Grid Start (Uses Grid Specific Inputs)
   // ==============================================================================
   else
      if(isGridStart)
        {
         // Grid Lot per Equity Logic
         if(UseGridLotPerEquity)
           {
            double balance = AccountInfoDouble(ACCOUNT_BALANCE); 
            
            // Avoid division by zero
            if(GridLot_Per_Equity_Step > 0)
              {
               // Example: Balance 20k / Step 10k = Ratio 2.0 -> 2.0 * 0.01 = 0.02 Lots
               double ratio = balance / GridLot_Per_Equity_Step;
               lotSize = ratio * GridLot_Per_Equity_Size;
              }
            else
              {
               // Safety fallback if step is invalid
               lotSize = CalculateGridStartLotFromRisk(execSymbol, symbolIndex, entryPrice, stopLoss, orderType);
              }
           }
         else
           {
            // Standard grid fallback model: fixed lot, percent risk, or fixed money risk.
            lotSize = CalculateGridStartLotFromRisk(execSymbol, symbolIndex, entryPrice, stopLoss, orderType);
           }
        }
      // ==============================================================================
      // CASE 4: Standard (Non-Grid/Non-Zone) Trade Logic  <-- MODIFIED SECTION
      // ==============================================================================
      else
        {
         // Default to Fixed Lot initially
         lotSize = FixedLot;

         // --- RISK CALCULATION BLOCK ---
         // We check for Percent Equity, Percent Balance, OR the new Fixed Money mode
         if(RiskType == RISK_PERCENT_EQUITY || RiskType == RISK_PERCENT_BALANCE || RiskType == RISK_FIXED_MONEY)
           {
            // A. Get Account Data
            double balance = AccountInfoDouble(ACCOUNT_BALANCE);
            double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
            
            // B. Get Tick Data for Accuracy
            double tickVal  = SymbolInfoDouble(execSymbol, SYMBOL_TRADE_TICK_VALUE);
            double tickSize = SymbolInfoDouble(execSymbol, SYMBOL_TRADE_TICK_SIZE);

            // C. Validate Data (Risk Calc requires a valid StopLoss and valid broker data)
            if(tickSize <= 0)
               if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print("WARNING: CalculateLotSize() for ", execSymbol, " — tickSize is ", tickSize, " (invalid). Unable to calculate lot size.");

            if(tickVal <= 0)
               if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print("WARNING: CalculateLotSize() for ", execSymbol, " — tickVal is ", tickVal, " (invalid). Unable to calculate lot size.");

            if(tickSize > 0 && tickVal > 0 && stopLoss > 0)
              {
               // 1. Calculate Distance in Price Units (e.g., 1.1000 - 1.0900 = 0.0100)
               double priceDist = MathAbs(entryPrice - stopLoss);
               
               // 2. Determine the Risk Amount ($) based on type
               double riskAmt = 0.0;
               
               if(RiskType == RISK_FIXED_MONEY)
                 {
                  // NEW: Use the direct dollar amount input
                  // (Make sure 'RiskMoney' matches your input variable name)
                  riskAmt = RiskMoney; 
                 }
               else if(RiskType == RISK_PERCENT_EQUITY)
                 {
                  // Existing: Equity %
                  riskAmt = equity * (RiskPercent/100.0);
                 }
               else
                 {
                  // Existing: Balance %
                  riskAmt = balance * (RiskPercent/100.0);
                 }

               // 3. Calculate value of 1.0 Lot over this distance
               // Formula: (PriceDistance / TickSize) * TickValue
               double profitPerLot = (priceDist / tickSize) * tickVal;

               // 4. Calculate Final Lots
               // If 1 lot loses $10, and we want to risk $50, we need 5 lots.
               if(profitPerLot > 0.000001)
                 {
                  lotSize = riskAmt / profitPerLot;
                  
                  // Debug Print to verify calculation
                  string typeStr = (RiskType == RISK_FIXED_MONEY) ? "FixedMoney" : "Percent";
                  if(MBP_LogTierEnabled(MBP_LOG_TIER_DEBUG)) Print(execSymbol, " ", typeStr, " Calc: Dist=", DoubleToString(priceDist, 5), 
                        " | Val/Lot=$", DoubleToString(profitPerLot, 2), 
                        " | TargetRisk=$", DoubleToString(riskAmt, 2), 
                        " -> Lots: ", DoubleToString(lotSize, 2));
                 }
              }
            else
              {
               // Error handling: If StopLoss is 0, we cannot calculate risk based on distance.
               if(stopLoss <= 0 && RiskType == RISK_FIXED_MONEY)
                   if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print("ERROR: Fixed Money Risk requires a valid StopLoss > 0. Reverting to FixedLot.");
              }
           }

         // Apply Dynamic Stake Multiplier (e.g. Martingale or Custom logic)
         if(UseDynamicStake)
            lotSize *= SymbolData[symbolIndex].CurrentStakeMultiplier;

         // Apply Stack Multiplier (Only for Normal Mode)
         if(StackMode)
            lotSize *= SymbolData[symbolIndex].StackMultiplier;
        }

   // ==============================================================================
   // FINAL NORMALIZATION
   // ==============================================================================
   
   // 1. Round to nearest Broker Step (e.g., 0.01)
   lotSize = NormalizeDouble(lotSize / lotStep, 0) * lotStep;
   
   // 2. Clamp to Min/Max
   if(lotSize < minLot)
      lotSize = minLot;
   if(lotSize > maxLot)
      lotSize = maxLot;
      
   // 3. Clamp to User defined Max
   if(lotSize > MaxLotSizePerTrade)
      lotSize = MaxLotSizePerTrade;

   return lotSize;
  }
  
//+------------------------------------------------------------------+
//| Calculate Aggressive Grid Lot (Retracement Math: Points or ATR)  |
//+------------------------------------------------------------------+
double CalculateAggressiveGridLot(int symbolIndex, ENUM_ORDER_TYPE type, double entryPrice)
  {
   string symbol = SymbolData[symbolIndex].symbol;
   string execSymbol = GetBaseSymbol(symbol);

   double tickVal  = SymbolInfoDouble(execSymbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(execSymbol, SYMBOL_TRADE_TICK_SIZE);
   double point    = SymbolInfoDouble(execSymbol, SYMBOL_POINT);

   if(tickSize == 0 || tickVal == 0)
      return GridFixedLot;

// ----------------------------------------------------------------
// 1. CALCULATE BASE RECOVERY DISTANCE (ATR or POINTS)
// ----------------------------------------------------------------
   double baseRecovDist = 0.0;

   if(GridAggressiveDistType == GRID_DIST_POINTS)
     {
      // Value is treated as Points (e.g., 50)
      baseRecovDist = GridAggressiveRecovDist * point;
     }
   else // GRID_DIST_ATR
     {
      // Value is treated as Multiplier (e.g., 5.0 * ATR)
      double atr[1];
      // Get ATR (Shift 1 to get closed bar value for stability)
      if(CopyBuffer(SymbolData[symbolIndex].ATR_Handle, 0, 1, 1, atr) > 0)
        {
         baseRecovDist = atr[0] * GridAggressiveRecovDist;
        }
      else
        {
         // Fallback if ATR fails
         baseRecovDist = 50 * point;
         if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print("Error: ATR copy failed for Aggressive Calc. Using 50 pts fallback.");
        }
     }

// ----------------------------------------------------------------
// 2. APPLY LEVEL MULTIPLIER
// Formula: Base * (Mult ^ Level)
// ----------------------------------------------------------------
   int levelIndex = SymbolData[symbolIndex].GridLevels; // 0-based index relative to grid adds
   if(levelIndex < 0)
      levelIndex = 0;

   double distMult = MathPow(GridAggressiveRecovMult, levelIndex);
   double finalRecoveryDist = baseRecovDist * distMult;

// Safety clamp (Min 10 points)
   if(finalRecoveryDist < 10 * point)
      finalRecoveryDist = 10 * point;

// ----------------------------------------------------------------
// 3. DETERMINE TARGET PRICE (Retracement Point)
// ----------------------------------------------------------------
   double targetPrice = 0.0;
   if(type == ORDER_TYPE_BUY)
      targetPrice = entryPrice + finalRecoveryDist; // Retrace UP
   else
      targetPrice = entryPrice - finalRecoveryDist; // Retrace DOWN

   SymbolData[symbolIndex].GridAggressiveTargetPrice = targetPrice; // Store for visuals

// ----------------------------------------------------------------
// 4. PROJECT EQUITY OF EXISTING TRADES AT TARGET PRICE
// ----------------------------------------------------------------
   double projectedEquity = 0.0;
   double maxPreviousLot  = 0.0;

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
            // Include Main, Grid, and Stack trades
            // Exclude Zone trades if running in Grid Mode (safety check)
            if(StringFind(c, "Grid") >= 0 || StringFind(c, "Stack") >= 0)
              {
               double vol = PositionGetDouble(POSITION_VOLUME);
               if(vol > maxPreviousLot)
                  maxPreviousLot = vol;
               double open = PositionGetDouble(POSITION_PRICE_OPEN);
               ENUM_POSITION_TYPE pType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

               double diff = 0;
               if(pType == POSITION_TYPE_BUY)
                  diff = targetPrice - open;
               else
                  diff = open - targetPrice;

               double profit = (diff / tickSize) * tickVal * vol;
               profit += PositionGetDouble(POSITION_SWAP) + GetPositionCommission(PositionGetInteger(POSITION_IDENTIFIER));

               projectedEquity += profit;
              }
           }
        }
     }

// ----------------------------------------------------------------
// 5. SOLVE FOR NEW LOT
// Equation: Projected + (NewLot * DistProfit) = TargetProfit
// Note: GridTargetProfit already includes the Debt Portion (added in CheckNewGridLevel)
// ----------------------------------------------------------------
   double requiredProfit = SymbolData[symbolIndex].GridTargetProfit - projectedEquity;

// Profit of 1.0 Lot over the Recovery Distance
   double profitPerLot = (finalRecoveryDist / tickSize) * tickVal;

   if(profitPerLot <= 0.00001)
      return GridFixedLot;

   double calculatedLot = requiredProfit / profitPerLot;

// --- SAFETY CAP LOGIC ---
// Prevent the new lot from being more than X times the previous largest trade.
// Using 'MaxStakeMultiplier' from inputs (e.g., 5x or 10x).
// If MaxStakeMultiplier is 2.0, and prev lot is 1.0, max next lot is 2.0.

   double safetyCap = (maxPreviousLot > 0) ? (maxPreviousLot * lotCap) : MaxLotSizePerTrade; // Default 2.5x hard limit if input missing
   if(MaxStakeMultiplier > 0)
      safetyCap = maxPreviousLot * MaxStakeMultiplier;

   if(calculatedLot > safetyCap)
     {
      if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(execSymbol, " WARNING: Aggressive Math requested ", calculatedLot, " lots. Capped at ", safetyCap, " (Safety Limit).");
      calculatedLot = safetyCap;
     }
// ------------------------

// 6. Normalize & Cap
   double min = SymbolInfoDouble(execSymbol, SYMBOL_VOLUME_MIN);
   double max = SymbolInfoDouble(execSymbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(execSymbol, SYMBOL_VOLUME_STEP);

   if(calculatedLot < min)
      calculatedLot = min;
   if(calculatedLot > max)
      calculatedLot = max;
   if(calculatedLot > MaxLotSizePerTrade)
      calculatedLot = MaxLotSizePerTrade; // Global Cap

   calculatedLot = NormalizeDouble(calculatedLot / step, 0) * step;

   string typeStr = (GridAggressiveDistType == GRID_DIST_POINTS) ? "Pts" : "ATR";

   if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(execSymbol, " Aggressive Grid (", typeStr, ") | Lvl: ", levelIndex,
         " | RecovDist: ", DoubleToString(finalRecoveryDist/point, 0),
         "pts | Need: $", DoubleToString(requiredProfit, 2),
         " | Lot: ", calculatedLot);

   return calculatedLot;
  }

//+------------------------------------------------------------------+
//| Calculate Zone Recovery Lot (Target Price Projection)            |
//+------------------------------------------------------------------+
double CalculateZoneRecoveryLot(int symbolIndex, ENUM_ORDER_TYPE nextType)
  {
   string symbol = SymbolData[symbolIndex].symbol;
   string execSymbol = GetBaseSymbol(symbol);

   double tickVal  = SymbolInfoDouble(execSymbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(execSymbol, SYMBOL_TRADE_TICK_SIZE);
   double currentAsk = SymbolInfoDouble(execSymbol, SYMBOL_ASK);
   double currentBid = SymbolInfoDouble(execSymbol, SYMBOL_BID);
   double spread     = currentAsk - currentBid;

   if(tickSize == 0 || tickVal == 0)
      return FixedLot;

// 1. DETERMINE TARGET PRICE GEOMETRY
   double zoneTop    = SymbolData[symbolIndex].ZoneTopPrice;
   double zoneBottom = SymbolData[symbolIndex].ZoneBottomPrice;

// Safety
   if(zoneTop == 0 || zoneBottom == 0)
      return FixedLot;

   double gapPrice = MathAbs(zoneTop - zoneBottom);
// Distance from Zone Edge to Target Line
   double distanceToTravel = gapPrice * ZoneTargetMult;

// Define The Exact Price where we want to exit
   double targetPriceLevel = 0.0;

   if(nextType == ORDER_TYPE_BUY)
     {
      // Recovering UP. Target is above Zone Top.
      targetPriceLevel = zoneTop + distanceToTravel;
     }
   else
     {
      // Recovering DOWN. Target is below Zone Bottom.
      targetPriceLevel = zoneBottom - distanceToTravel;
     }

// 2. PROJECT EQUITY OF EXISTING TRADES AT TARGET PRICE
   double projectedEquity = 0.0;

   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetString(POSITION_SYMBOL) == execSymbol &&
            IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
           {
            // Only count Zone trades involved in the hedge
            string c = PositionGetString(POSITION_COMMENT);
            if(InpEnableMultiBaskets && !IsPositionInBasket(symbolIndex, c))
               continue;
            if(StringFind(c, "Zone") >= 0)
              {
               double vol = PositionGetDouble(POSITION_VOLUME);
               double entry = PositionGetDouble(POSITION_PRICE_OPEN);
               ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

               double profitPoints = 0;

               // Calculate profit based on where price WILL be
               if(type == POSITION_TYPE_BUY)
                 {
                  // Buy closes at Bid. At target, Bid ~ TargetPriceLevel
                  // (Simplified: We assume TargetPriceLevel is the reference price)
                  profitPoints = (targetPriceLevel - entry);
                 }
               else
                 {
                  // Sell closes at Ask. At target, Ask ~ TargetPriceLevel + Spread (or just Target if conservative)
                  // For safety, let's assume worst case exit logic
                  profitPoints = (entry - targetPriceLevel);
                 }

               double profitMoney = (profitPoints / tickSize) * tickVal * vol;

               // Subtract estimated swap/commissions
               profitMoney += PositionGetDouble(POSITION_SWAP);
               profitMoney += GetPositionCommission(PositionGetInteger(POSITION_IDENTIFIER));

               projectedEquity += profitMoney;
              }
           }
        }
     }

// 3. SOLVE FOR NEW LOT
// Target Equation: ProjectedEquity + NewTradeProfit = GridTargetProfit
// NewTradeProfit = GridTargetProfit - ProjectedEquity

   double requiredFromNewTrade = SymbolData[symbolIndex].GridTargetProfit - projectedEquity;

// Calculate profit of 1.0 Lot for the new trade traveling the full distance
// Distance is from Entry (Current Price) to Target Price
   double travelDistance = 0;

   if(nextType == ORDER_TYPE_BUY)
      travelDistance = targetPriceLevel - currentAsk;
   else
      travelDistance = currentBid - targetPriceLevel; // Selling at Bid, Target is lower

   if(travelDistance <= 0)
      travelDistance = tickSize; // Safety calc

   double profitPerLot = (travelDistance / tickSize) * tickVal;

   double calculatedLot = requiredFromNewTrade / profitPerLot;

// 4. NORMALIZE
   double minLot = SymbolInfoDouble(execSymbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(execSymbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(execSymbol, SYMBOL_VOLUME_STEP);

// Check limits
   if(calculatedLot < minLot)
      calculatedLot = minLot;
   if(calculatedLot > MaxLotSizePerTrade)
      calculatedLot = MaxLotSizePerTrade; // Global Cap

// Rounding
   calculatedLot = NormalizeDouble(calculatedLot / lotStep, 0) * lotStep;

   if(MBP_LogTierEnabled(MBP_LOG_TIER_DEBUG)) Print(execSymbol, " Zone Math | TargetPrice: ", targetPriceLevel,
         " | Projected Equity: $", DoubleToString(projectedEquity, 2),
         " | Need: $", DoubleToString(requiredFromNewTrade, 2),
         " | Dist: ", DoubleToString(travelDistance, _Digits),
         " | Calc Lot: ", calculatedLot);

   return calculatedLot;
  }
  
//+------------------------------------------------------------------+
//| Calculate Initial Stop Loss (Robust Swing Logic)                 |
//+------------------------------------------------------------------+
double CalculateInitialStopLoss(int symbolIndex, ENUM_ORDER_TYPE orderType, double entryPrice)
  {
   string symbol      = SymbolData[symbolIndex].symbol;
   string execSymbol  = GetBaseSymbol(symbol);
   double sl          = 0;

   switch(StopLossType)
     {
      case SL_ATR:
        {
         double atr[1];
         if(CopyBuffer(SymbolData[symbolIndex].ATR_Handle, 0, 0, 1, atr) > 0)
           {
            double atrValue = atr[0];
            sl = (orderType == ORDER_TYPE_BUY) ?
                 entryPrice - (atrValue * ATR_Multiplier) :
                 entryPrice + (atrValue * ATR_Multiplier);
           }
         break;
        }

      case SL_BOX:
        {
         // 1. DATA VALIDATION
         // If arrays are empty, force a history scan immediately
         if(SymbolData[symbolIndex].BoxLowCount == 0 || SymbolData[symbolIndex].BoxHighCount == 0)
           {
            if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(symbol, " [Box SL] Warning: Arrays empty. Forcing Backfill...");
            BackfillBoxHistory(symbolIndex);
           }

         if(orderType == ORDER_TYPE_BUY)
           {
            // --- BUY STOP LOSS (Lowest of the last N Low Segments) ---
            int available = SymbolData[symbolIndex].BoxLowCount;
            int limit     = MathMin(available, Box_SL_Levels); // Use user setting, capped by available data

            if(limit > 0)
              {
               double lowestFound = DBL_MAX; // Start with max value so any price is lower
               string scanStr = ""; // For debug log

               for(int i = 0; i < limit; i++)
                 {
                  double val = SymbolData[symbolIndex].BoxLow[i];

                  // Accumulate debug string
                  scanStr += DoubleToString(val, _Digits) + ", ";

                  // Check for lowest valid price
                  if(val > 0 && val < lowestFound)
                    {
                     lowestFound = val;
                    }
                 }

               // Verify we found a valid price (still not DBL_MAX)
               if(lowestFound != DBL_MAX)
                 {
                  sl = lowestFound;
                  if(MBP_LogTierEnabled(MBP_LOG_TIER_DEBUG)) Print(symbol, " [Box SL Buy] Scanned(", limit, "): [", scanStr, "] -> Selected Lowest: ", sl);

                  // Safety: SL cannot be above entry
                  if(sl >= entryPrice)
                    {
                     sl = entryPrice - SymbolInfoDouble(execSymbol, SYMBOL_POINT) * 10;
                     if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(symbol, " [Box SL] Adjustment: Swing SL was above Entry. Adjusted to Entry - 10pts.");
                    }
                 }
               else
                 {
                  if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(symbol, " [Box SL] Error: Segments found but values were 0. Using Entry.");
                  sl = entryPrice;
                 }
              }
            else
              {
               if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(symbol, " [Box SL] Error: No Low Segments found even after backfill. Using Entry.");
               sl = entryPrice;
              }
           }
         else // SELL
           {
            // --- SELL STOP LOSS (Highest of the last N High Segments) ---
            int available = SymbolData[symbolIndex].BoxHighCount;
            int limit     = MathMin(available, Box_SL_Levels);

            if(limit > 0)
              {
               double highestFound = 0.0; // Start with 0 so any price is higher
               string scanStr = "";

               for(int i = 0; i < limit; i++)
                 {
                  double val = SymbolData[symbolIndex].BoxHigh[i];

                  scanStr += DoubleToString(val, _Digits) + ", ";

                  if(val > 0 && val > highestFound)
                    {
                     highestFound = val;
                    }
                 }

               if(highestFound > 0)
                 {
                  sl = highestFound;
                  if(MBP_LogTierEnabled(MBP_LOG_TIER_DEBUG)) Print(symbol, " [Box SL Sell] Scanned(", limit, "): [", scanStr, "] -> Selected Highest: ", sl);

                  // Safety: SL cannot be below entry
                  if(sl <= entryPrice)
                    {
                     sl = entryPrice + SymbolInfoDouble(execSymbol, SYMBOL_POINT) * 10;
                     if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(symbol, " [Box SL] Adjustment: Swing SL was below Entry. Adjusted to Entry + 10pts.");
                    }
                 }
               else
                 {
                  sl = entryPrice;
                 }
              }
            else
              {
               if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(symbol, " [Box SL] Error: No High Segments found. Using Entry.");
               sl = entryPrice;
              }
           }
         break;
        }

      case SL_MA:
        {
         double ma[1];
         // Use index 0 for current dynamic value, or 1 for closed bar value
         if(CopyBuffer(SymbolData[symbolIndex].MA_SL_Handle, 0, 0, 1, ma) > 0)
           {
            sl = ma[0];
           }
         break;
        }
     }

// 2. FINAL BROKER COMPLIANCE CHECK
   if(sl != 0)
     {
      double point = SymbolInfoDouble(execSymbol, SYMBOL_POINT);
      int stopLvl  = (int)SymbolInfoInteger(execSymbol, SYMBOL_TRADE_STOPS_LEVEL);
      double minDist = (stopLvl + 5) * point; // Add padding

      double dist = MathAbs(entryPrice - sl);

      if(dist < minDist)
        {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(symbol, " [Risk] Calculated SL too close (", DoubleToString(dist,5), "). Pushing to min distance (", DoubleToString(minDist,5), ").");
         if(orderType == ORDER_TYPE_BUY)
            sl = entryPrice - minDist;
         else
            sl = entryPrice + minDist;
        }

      sl = NormalizePrice(execSymbol, sl);
     }

   return sl;
  }
  
//+------------------------------------------------------------------+
//| Check Global Dollar Limits (TP/SL)                               |
//+------------------------------------------------------------------+
void CheckGlobalDollarLimits()
  {
// 1. Check if features are enabled
   if(GlobalTP_Amount <= 0 && GlobalSL_Amount <= 0)
      return;

   double currentTotalProfit = 0.0;
   int count = 0;

// 2. Sum up Profit across ALL positions managed by this bot
   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         // Check Magic Number to ensure we only count OUR trades
         if(IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
           {
            ulong posID = PositionGetInteger(POSITION_IDENTIFIER);
            double p = PositionGetDouble(POSITION_PROFIT);
            double s = PositionGetDouble(POSITION_SWAP);
            double c = GetPositionCommission(posID);

            currentTotalProfit += (p + s + c);
            count++;
           }
        }
     }

// If no trades open, nothing to check
   if(count == 0)
      return;

// 3. Check Global Take Profit
   if(GlobalTP_Amount > 0 && currentTotalProfit >= GlobalTP_Amount)
     {
      if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(">>> GLOBAL TP HIT ($", currentTotalProfit, ") - Closing All Trades <<<");
      CloseAllGlobalPositions("Global TP Hit");
      return; // Exit after triggering close
     }

// 4. Check Global Stop Loss
// Note: GlobalSL_Amount should be entered as a positive number (e.g., 100 for -$100 loss)
// We check if current profit is less than or equal to negative limit
   if(GlobalSL_Amount > 0 && currentTotalProfit <= (-1 * GlobalSL_Amount))
     {
      if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(">>> GLOBAL SL HIT ($", currentTotalProfit, ") - Closing All Trades <<<");
      CloseAllGlobalPositions("Global SL Hit");
      return;
     }
  }
  
//+------------------------------------------------------------------+
//| Check global limits                                              |
//+------------------------------------------------------------------+
void CheckGlobalLimits()
  {
   double totalProfit = 0;
   double totalLoss = 0;

   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
           {
            double profit = PositionGetDouble(POSITION_PROFIT);
            if(profit >= 0)
               totalProfit += profit;
            else
               totalLoss += MathAbs(profit);
           }
        }
     }

   GlobalTotalProfit = totalProfit;
   GlobalTotalLoss = totalLoss;
   // DailyGlobalProfit/Loss are maintained from realized close events in OnTradeTransaction.
   // Keep this function focused on floating exposure snapshot only.
  }

//+------------------------------------------------------------------+
//| Check Account Equity Limits (Profit/Loss hard stop)              |
//+------------------------------------------------------------------+
void CheckAccountEquityLimits()
{
   if(!UseAccountLimits || ReferenceEquity <= 0) return;

   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   // Calculate Thresholds
   double profitTarget = ReferenceEquity * (1.0 + (AccountProfitLimitPct / 100.0));
   double lossLimit    = ReferenceEquity * (1.0 - (AccountLossLimitPct / 100.0));

   bool hitProfit = (currentEquity >= profitTarget);
   bool hitLoss   = (currentEquity <= lossLimit);

   if(hitProfit || hitLoss)
   {
      string reason = hitProfit ?
                      "Account Profit Limit Hit (+"+DoubleToString(AccountProfitLimitPct,2)+"%)" 
                                : "Account Loss Limit Hit (-"+DoubleToString(AccountLossLimitPct,2)+"%)";
                                
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(">>> ", reason, " | Current: ", DoubleToString(currentEquity, 2), " | Ref: ", DoubleToString(ReferenceEquity, 2));

      // 1. PRE-EMPTIVE WIPE & POISONING
      for(int i=0; i<ArraySize(SymbolData); i++)
      {
         // A. Reset Banks
         SymbolData[i].AccumulatedPruningLoss  = 0.0;
         SymbolData[i].AccumulatedCriticalLoss = 0.0;
         SymbolData[i].CurrentRecoveryPortion  = 0.0;
         SymbolData[i].RecoveryIteration       = 1;

         // B. Poison History Scan
         SymbolData[i].LastGridReset = TimeCurrent() + 10; 

         // C. Reset Logic
         ResetGridTracking(i, true);

         // D. Delete Disk Debt
         string gvName = "Debt_" + SymbolData[i].symbol;
         if(GlobalVariableCheck(gvName)) GlobalVariableDel(gvName);
      }

      // 2. Close ALL Trades
      CloseAllGlobalPositions(reason);
      
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(">>> FRESH START EXECUTED: Banks Wiped, History Poisoned, Trades Closed.");

      // 3. Handle Restart or Stop (WITH COOLDOWN)
      if(RestartAfterLimit)
      {
         // --- COOLDOWN LOGIC START ---
         if(AccountLimitCooldownMinutes > 0)
         {
            GlobalCooldownEndTime = TimeCurrent() + (AccountLimitCooldownMinutes * 60);
            if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(">>> COOLDOWN INITIATED: Bot will sleep for ", AccountLimitCooldownMinutes, " minutes.");
            if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(">>> Resumption Time: ", TimeToString(GlobalCooldownEndTime, TIME_DATE|TIME_MINUTES));
         }
         else
         {
            if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(">>> Restarting Cycle Immediately (No Cooldown).");
         }
         // -----------------------------

         if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(">>> Resetting Reference Equity to: ", DoubleToString(currentEquity, 2));
         ReferenceEquity = currentEquity; // Reset Baseline
      }
      else
      {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(">>> Trading Disabled (Restart Toggle OFF).");
         GlobalTradingEnabled = false; // Stop Bot
      }
   }
}

//+------------------------------------------------------------------+
//| Manage risk for symbol                                           |
//+------------------------------------------------------------------+
void ManageRisk(int symbolIndex)
  {
   if(!UseDynamicStake)
      return;

   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double equityChange = ((currentEquity - SymbolData[symbolIndex].OriginalBalance) / SymbolData[symbolIndex].OriginalBalance) * 100;

   int multiplierSteps = (int)(equityChange / EquityThreshold);

   if(multiplierSteps > 0)
     {
      SymbolData[symbolIndex].CurrentStakeMultiplier = MathPow(StakeMultiplier, multiplierSteps);
     }
   else
      if(multiplierSteps < 0)
        {
         SymbolData[symbolIndex].CurrentStakeMultiplier = MathPow(1.0/StakeMultiplier, MathAbs(multiplierSteps));
        }

   SymbolData[symbolIndex].CurrentStakeMultiplier = MathMin(MaxStakeMultiplier, MathMax(0.1, SymbolData[symbolIndex].CurrentStakeMultiplier));
  }

//+------------------------------------------------------------------+
//| Save Debt to Risk                                                |
//+------------------------------------------------------------------+
void SaveDebtToDisk(int symbolIndex)
{
   string name = "Debt_" + SymbolData[symbolIndex].symbol;
   GlobalVariableSet(name, SymbolData[symbolIndex].AccumulatedPruningLoss);
}

//+------------------------------------------------------------------+
//| Load Debt from Risk                                              |
//+------------------------------------------------------------------+
void LoadDebtFromDisk(int symbolIndex)
{
   string name = "Debt_" + SymbolData[symbolIndex].symbol;
   if(GlobalVariableCheck(name))
   {
      SymbolData[symbolIndex].AccumulatedPruningLoss = GlobalVariableGet(name);
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("Loaded Saved Debt for ", SymbolData[symbolIndex].symbol, ": $", DoubleToString(SymbolData[symbolIndex].AccumulatedPruningLoss, 2));
   }
} 

//+------------------------------------------------------------------+
//| COOL DOWN LOGIC GLOBALS                                          |
//+------------------------------------------------------------------+
datetime GlobalCooldownEndTime = 0; 

bool IsGlobalCooldownActive()
{
   if(GlobalCooldownEndTime > 0)
   {
      if(TimeCurrent() < GlobalCooldownEndTime)
      {
         // Optional: Print throttle could be added here to avoid log spam
         return true; // Still cooling down
      }
      else
      {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(">>> Global Cooldown Expired. Resuming Trading Operations.");
         GlobalCooldownEndTime = 0; // Reset
         return false;
      }
   }
   return false;
} 
 
//+------------------------------------------------------------------+
#endif // __MULTIBOTPRO_RISK_MQH__


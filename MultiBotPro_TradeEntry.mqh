#ifndef __MULTIBOTPRO_TRADEENTRY_MQH__
#define __MULTIBOTPRO_TRADEENTRY_MQH__
//+------------------------------------------------------------------+
//|                                            MultiBotPro_Entry.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://discord.com/channels/929723953415589918/929723953415589920"

#define MBP_AI_PARAM_MAX_AGE_SEC 172800

bool MBP_ShouldLogEntrySignalDiagnostic(const int symbolIndex, const string direction)
  {
   if(symbolIndex < 0 || symbolIndex >= 100)
      return false;

   static ulong lastLogMs[100] = {0};
   static string lastDirection[100];

   ulong nowMs = GetTickCount64();
   bool directionChanged = (StringCompare(lastDirection[symbolIndex], direction, false) != 0);
   if(!directionChanged && lastLogMs[symbolIndex] > 0 && (nowMs - lastLogMs[symbolIndex]) < 60000)
      return false;

   lastLogMs[symbolIndex] = nowMs;
   lastDirection[symbolIndex] = direction;
   return true;
  }

//+------------------------------------------------------------------+
//| Check entry signals (FIXED: Reverse Logic + MA Sell Fix)         |
//+------------------------------------------------------------------+
void CheckEntrySignals(int symbolIndex)
  {   
   // --- FIX: CHECK HEDGE BLOCK FIRST ---
   if(IsHedgeBlocked()) return;
   
   // ==========================================================
   // --- NEW: ASYNC BRIDGE HANDSHAKE LOCK ---
   // Stop processing new signals if we are waiting on the Slave
   // ==========================================================
   if(G_BridgePending.active || G_BridgePending.approved) return;

   // 1. GLOBAL COOLDOWN BLOCK
   if(IsGlobalCooldownActive()) return;

   // 2. FORCE THROTTLE (Prevents Machine-Gun Effect)
   // Array ensures every symbol gets its own independent 2-second timer.
   static ulong lastCheckArr[100] = {0};
   if(symbolIndex < 0 || symbolIndex >= 100) return;
   if(GetTickCount64() - lastCheckArr[symbolIndex] < 2000) return;
   lastCheckArr[symbolIndex] = GetTickCount64();

   // --- NEW: MAX TRADES FILTER ---
   if(!CheckMaxOpenTrades(symbolIndex)) return;
   // ------------------------------
   
  UpdateFilterStats(symbolIndex);
  
   if(!CheckFilters(symbolIndex)) return;
   
   // --- NEW: RECONCILE PREVIOUS TRADES BEFORE NEW SIGNAL ---
   ReconcileNormalTrade(symbolIndex);
   // --------------------------------------------------------
   
   if(IsPaused)
      return;
   string symbol = SymbolData[symbolIndex].symbol;
   
   // ==========================================================
   // --- SHADOW MASTER FALLBACK MECHANISM ---
   // ==========================================================
   bool aiActive = false;
   bool nlpBlocked = false;
   if(InpEnableShadowMaster)
   {
       if(SymbolData[symbolIndex].LastShadowUpdate > 0 &&
         (TimeCurrent() - SymbolData[symbolIndex].LastShadowUpdate < MBP_AI_PARAM_MAX_AGE_SEC))
       {
           if(SymbolData[symbolIndex].Dyn_CurrencyStrengthDelta > 0) 
               aiActive = true;
               
           nlpBlocked = SymbolData[symbolIndex].Dyn_NLP_Killswitch;
       }
   }

   // --- THE NLP KILLSWITCH ---
   if(aiActive && nlpBlocked)
   {
       Comment("🧠 NLP killswitch: adverse news sentiment detected. Trading halted.");
       return; 
   }

   // Assign Active Variables: Use Dynamic AI values if live, otherwise fallback to standard inputs
   double activeGridMult = aiActive ? SymbolData[symbolIndex].Dyn_GridMultiplier : GridMultiplier;
   double activeADXMin   = aiActive ? SymbolData[symbolIndex].Dyn_ADX_MinLevel : ADX_MinLevel;
   double activeDelta    = aiActive ? SymbolData[symbolIndex].Dyn_CurrencyStrengthDelta : CurrencyStrengthDelta;
   // ==========================================================

   // ==========================================================
   // --- HOTFIX: BULLETPROOF POSITION TALLY ---
   // Forcibly scans MT5 for active trades to prevent double-entries
   // ==========================================================
   string execSym = GetBaseSymbol(SymbolData[symbolIndex].symbol);
   int actualPositions = 0;
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
       ulong ticket = PositionGetTicket(i);
       if(PositionSelectByTicket(ticket))
       {
if(PositionGetString(POSITION_SYMBOL) == execSym)
           {
               string posComment = PositionGetString(POSITION_COMMENT);
               if(InpEnableMultiBaskets && !IsPositionInBasket(symbolIndex, posComment))
                  continue;
               long posMagic = PositionGetInteger(POSITION_MAGIC);
               if(!IsAppTrade(posMagic))
                  continue;

               // In MULTIBASKET mode the magic alone isn't enough — many baskets
               // share the magic. Require the "B#<id>" tag in the comment so we
               // only count positions belonging to THIS basket.
               // In single-basket mode the magic-match is sufficient (per-worker
               // magic offset already isolates workers from each other).
               if(InpEnableMultiBaskets)
               {
                   int expectedBasketId = SymbolData[symbolIndex].BasketId;
                   int actualBasketId = ExtractBasketId(posComment);
                   if(actualBasketId != expectedBasketId)
                       continue;
               }
               actualPositions++;
           }
       }
   }
   SymbolData[symbolIndex].PositionCount = actualPositions;
   
   // 1. Position Check (Now using the guaranteed true count)
   if(!InpEnableMultiBaskets)
     {
      if(SymbolData[symbolIndex].PositionCount > 0)
         return;
     }
   else
     {
      if(!SymbolData[symbolIndex].IsPrimaryBasket)
         return;
     }
   // ==========================================================

// --- NEW: SPREAD CHECK ---
   if(!CheckSpread(symbolIndex))
      return;
// -------------------------

// 2. MA Logic
   bool maBuy = CheckMABuySignal(symbolIndex);
   bool maSell = CheckMASellSignal(symbolIndex);

// ... (Rest of the function remains the same) ...

// 3. VWAP Logic
   bool vwapBuy = true;
   bool vwapSell = true;

   if(UseVWAP && RequireVWAPConfirmation)
     {
      double price = SymbolInfoDouble(symbol, SYMBOL_BID);
      vwapBuy = CheckVWAPBuySignal(symbolIndex, price);
      vwapSell = CheckVWAPSellSignal(symbolIndex, price);
     }

// Inside MultiBotPro_TradeEntry.mqh -> CheckEntrySignals()

// ... Existing Indicator Checks ...
   bool adxPass = CheckADXFilter(symbolIndex);
   bool boxBuy  = CheckBoxTrend(symbolIndex, ORDER_TYPE_BUY);
   bool boxSell = CheckBoxTrend(symbolIndex, ORDER_TYPE_SELL);

// ==========================================================
   // --- CURRENCY STRENGTH MATRIX FILTER (Using activeDelta) ---
   // ==========================================================
   bool macroBuy  = true;
   bool macroSell = true;

    if(UseCurrencyStrength)
   {
      string baseCurrency  = StringSubstr(symbol, 0, 3);
      string quoteCurrency = StringSubstr(symbol, 3, 3);

      double baseStrength  = GetCurrencyStrength(baseCurrency);
      double quoteStrength = GetCurrencyStrength(quoteCurrency);

      // ==========================================================
      // --- NEW FAILSAFE: Bypass for Metals/Crypto or Missing Data ---
      // If the matrix returns exactly 50.0 for both, it means the asset 
      // is not a standard fiat pair. We bypass the macro block!
      // ==========================================================
      if(baseStrength == 50.0 && quoteStrength == 50.0)
      {
          // Do nothing. Leave macroBuy and macroSell as true so the 
          // standard moving averages can take the trade.
      }
      else
      {
          // A valid Buy requires the Base to be stronger than the Quote by the active threshold
          if(baseStrength < quoteStrength + activeDelta) macroBuy = false;

          // A valid Sell requires the Base to be weaker than the Quote
          if(baseStrength > quoteStrength - activeDelta) macroSell = false;
      }
   }
   // ==========================================================

   // 4. Combine Signals (Final Gatekeeper)
   bool finalBuySignal  = (maBuy && vwapBuy && adxPass && boxBuy && macroBuy);
   bool finalSellSignal = (maSell && vwapSell && adxPass && boxSell && macroSell);
   
// 5. MASTER REVERSE LOGIC
   if(ReverseStrategy)
     {
      bool temp = finalBuySignal;
      finalBuySignal = finalSellSignal;
      finalSellSignal = temp;
     }

// 6. Execution
   if(finalBuySignal)
     {
      string dir = ReverseStrategy ? "REVERSED BUY (Original Sell)" : "BUY";
      if(MBP_ShouldLogEntrySignalDiagnostic(symbolIndex, dir))
        {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("🎯 ", symbol, " entry signal: ", dir);
         if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("🧮 Execution check: RiskMode=", EnumToString(RiskMode), " | StackMode=", (StackMode ? "true" : "false"));
        }
      
      // RECONCILED: Delegate all lot calculations, recovery math, and bridge 
      // handshakes strictly to the OpenTrade function.
      int targetIndex = ResolveBasketIndexForSignal(symbolIndex, ORDER_TYPE_BUY, SymbolInfoDouble(execSym, SYMBOL_ASK));
      if(targetIndex >= 0) OpenTrade(targetIndex, ORDER_TYPE_BUY);
     }
   else
      if(finalSellSignal)
        {
         string dir = ReverseStrategy ? "REVERSED SELL (Original Buy)" : "SELL";
         if(MBP_ShouldLogEntrySignalDiagnostic(symbolIndex, dir))
           {
            if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("🎯 ", symbol, " entry signal: ", dir);
            if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("🧮 Execution check: RiskMode=", EnumToString(RiskMode), " | StackMode=", (StackMode ? "true" : "false"));
           }
         
         // RECONCILED: Delegate all lot calculations, recovery math, and bridge 
         // handshakes strictly to the OpenTrade function.
         int targetIndex = ResolveBasketIndexForSignal(symbolIndex, ORDER_TYPE_SELL, SymbolInfoDouble(execSym, SYMBOL_BID));
         if(targetIndex >= 0) OpenTrade(targetIndex, ORDER_TYPE_SELL);
        }
  }

//+------------------------------------------------------------------+
//| Check MA buy signal (FIXED: AI vs Manual Logic)                  |
//+------------------------------------------------------------------+
bool CheckMABuySignal(int symbolIndex)
  {
   string symbol = SymbolData[symbolIndex].symbol;
   for(int tf = 0; tf < 7; tf++)
     {
      if(!TimeframeEnabled[tf])
         continue;

      double maValues[5];
      for(int i = 0; i < 5; i++)
        {
         // --- SELF-REPAIR LOGIC ---
         if(SymbolData[symbolIndex].MA_Handles[i][tf] == INVALID_HANDLE)
           {
            SymbolData[symbolIndex].MA_Handles[i][tf] = iMA(symbol, Timeframes[tf],
                  GetActiveMAPeriod(symbolIndex, i),
                  0,
                  GetMAMethod(i==0?MA1_Method : i==1?MA2_Method : i==2?MA3_Method : i==3?MA4_Method : MA5_Method),
                  GetMASource(i==0?MA1_Source : i==1?MA2_Source : i==2?MA3_Source : i==3?MA4_Source : MA5_Source));

            if(SymbolData[symbolIndex].MA_Handles[i][tf] == INVALID_HANDLE)
              {
               if(TimeCurrent() % 60 == 0) return false;
              }
           }

         double ma[1];
         if(CopyBuffer(SymbolData[symbolIndex].MA_Handles[i][tf], 0, 0, 1, ma) < 1)
           {
            return false;
           }
         maValues[i] = ma[0];
        }

      // ==========================================================
      // --- AI VS MANUAL CASCADE LOGIC ---
      // ==========================================================
      bool aiActive = false;
      if(InpEnableShadowMaster && SymbolData[symbolIndex].LastShadowUpdate > 0)
          aiActive = true;

      if(aiActive)
      {
         // PYTHON STRATEGY: Only check if Fast > Slow (Matches AI Backtest exactly)
         if(!(maValues[0] > maValues[1])) 
            return false;
      }
      else
      {
         // STANDARD STRATEGY: Full 5-MA Cascade
         if(!(maValues[0] >= maValues[1] && maValues[1] >= maValues[2] &&
              maValues[2] >= maValues[3] && maValues[3] >= maValues[4]))
           {
            return false;
           }
      }
      // ==========================================================
     }

   return true;
  }
  
//+------------------------------------------------------------------+
//| Check MA sell signal (FIXED: AI vs Manual Logic)                 |
//+------------------------------------------------------------------+
bool CheckMASellSignal(int symbolIndex)
  {
   string symbol = SymbolData[symbolIndex].symbol;
   for(int tf = 0; tf < 7; tf++)
     {
      if(!TimeframeEnabled[tf])
         continue;

      double maValues[5];
      for(int i = 0; i < 5; i++)
        {
         // --- SELF-REPAIR LOGIC ---
         if(SymbolData[symbolIndex].MA_Handles[i][tf] == INVALID_HANDLE)
           {
            SymbolData[symbolIndex].MA_Handles[i][tf] = iMA(symbol, Timeframes[tf],
                  GetActiveMAPeriod(symbolIndex, i),
                  0,
                  GetMAMethod(i==0?MA1_Method : i==1?MA2_Method : i==2?MA3_Method : i==3?MA4_Method : MA5_Method),
                  GetMASource(i==0?MA1_Source : i==1?MA2_Source : i==2?MA3_Source : i==3?MA4_Source : MA5_Source));

            if(SymbolData[symbolIndex].MA_Handles[i][tf] == INVALID_HANDLE)
              {
               if(TimeCurrent() % 60 == 0) return false;
              }
           }

         double ma[1];
         if(CopyBuffer(SymbolData[symbolIndex].MA_Handles[i][tf], 0, 0, 1, ma) < 1)
           {
            return false;
           }
         maValues[i] = ma[0];
        }

      // ==========================================================
      // --- AI VS MANUAL CASCADE LOGIC ---
      // ==========================================================
      bool aiActive = false;
      if(InpEnableShadowMaster && SymbolData[symbolIndex].LastShadowUpdate > 0)
          aiActive = true;

      if(aiActive)
      {
         // PYTHON STRATEGY: Only check if Fast < Slow (Matches AI Backtest exactly)
         if(!(maValues[0] < maValues[1])) 
            return false;
      }
      else
      {
         // STANDARD STRATEGY: Full 5-MA Cascade
         if(!(maValues[0] <= maValues[1] && maValues[1] <= maValues[2] &&
              maValues[2] <= maValues[3] && maValues[3] <= maValues[4]))
           {
            return false;
           }
      }
      // ==========================================================
     }

   return true;
  }

//+------------------------------------------------------------------+
//| Check VWAP buy signal - UPDATED (CROSSOVER LOGIC)                |
//+------------------------------------------------------------------+
bool CheckVWAPBuySignal(int symbolIndex, double currentPrice)
  {
   string symbol = SymbolData[symbolIndex].symbol;
   bool signal = true;

   if(UseVWAP1)
     {
      signal = signal && (currentPrice > SymbolData[symbolIndex].VWAP1.Value);
     }

   if(UseVWAP2)
     {
      // LOGIC: Buy if price CROSSES ABOVE the High VWAP
      // We compare Current Price vs Current VWAP, and Previous Close vs Current VWAP
      // (Using current VWAP for both simplifies the check and avoids history lag issues)

      double prevPrice = iClose(symbol, PERIOD_CURRENT, 1);
      double vwapHigh = SymbolData[symbolIndex].VWAP2_High.Value;

      // 1. Currently Above
      bool isAbove = (currentPrice > vwapHigh);

      // 2. Previously Below or Equal
      bool wasBelow = (prevPrice <= vwapHigh);

      if(isAbove && wasBelow)
        {
         // Valid Crossover
         signal = signal && true;
         // Print(symbol, " VWAP2 Buy Crossover Detected");
        }
      else
        {
         // No crossover this tick
         // If you want "State" (just being above), remove '&& wasBelow'.
         // But for "Cross", this is required.
         signal = false;
        }
     }

   if(UseVWAP3)
     {
      signal = signal && (currentPrice > SymbolData[symbolIndex].VWAP3.Value);
     }

   return signal;
  }
  
//+------------------------------------------------------------------+
//| Check VWAP sell signal - UPDATED (CROSSOVER LOGIC)               |
//+------------------------------------------------------------------+
bool CheckVWAPSellSignal(int symbolIndex, double currentPrice)
  {
   string symbol = SymbolData[symbolIndex].symbol;
   bool signal = true;

   if(UseVWAP1)
     {
      signal = signal && (currentPrice < SymbolData[symbolIndex].VWAP1.Value);
     }

   if(UseVWAP2)
     {
      // LOGIC: Sell if price CROSSES BELOW the Low VWAP

      double prevPrice = iClose(symbol, PERIOD_CURRENT, 1);
      double vwapLow = SymbolData[symbolIndex].VWAP2_Low.Value;

      // 1. Currently Below
      bool isBelow = (currentPrice < vwapLow);

      // 2. Previously Above or Equal
      bool wasAbove = (prevPrice >= vwapLow);

      if(isBelow && wasAbove)
        {
         // Valid Crossover
         signal = signal && true;
         // Print(symbol, " VWAP2 Sell Crossover Detected");
        }
      else
        {
         signal = false;
        }
     }

   if(UseVWAP3)
     {
      signal = signal && (currentPrice < SymbolData[symbolIndex].VWAP3.Value);
     }

   return signal;
  }

//+------------------------------------------------------------------+
//| Check Opening Range Reversal Signals (FIXED)                     |
//+------------------------------------------------------------------+
void CheckORReversalSignals(int symbolIndex)
  {
   string symbol = SymbolData[symbolIndex].symbol;
   MqlDateTime ny_time;
   ConvertToNYTime(TimeCurrent(), ny_time);

// -------------------------------------------------------------
// 1. PER-SYMBOL DAY RESET
// -------------------------------------------------------------
   if(ny_time.day != SymbolData[symbolIndex].OR_LastDay)
     {
      SymbolData[symbolIndex].OR_Active = false;
      SymbolData[symbolIndex].OR_BreakoutOccurred = false;
      SymbolData[symbolIndex].OR_LastDay = ny_time.day;

      // Cleanup visual lines specific to this symbol
      ObjectDelete(0, "OR_High_" + symbol);
      ObjectDelete(0, "OR_Low_" + symbol);
     }

// -------------------------------------------------------------
// 2. IDENTIFY AND MEASURE RANGE
// -------------------------------------------------------------
   if(!SymbolData[symbolIndex].OR_Active)
     {
      // We need to find the specific 15m candle that started at OR_StartHour:OR_StartMinute
      int shift = -1;

      // Look back up to 24 hours (96 x 15m bars) to find the start bar
      for(int k=1; k<=96; k++)
        {
         datetime barTime = iTime(symbol, PERIOD_M15, k);
         if(barTime == 0)
            break;

         MqlDateTime barNY;
         ConvertToNYTime(barTime, barNY);

         if(barNY.hour == OR_StartHour && barNY.min == OR_StartMinute)
           {
            shift = k;
            break;
           }
        }

      // If we found the start bar
      if(shift != -1)
        {
         datetime barOpenTime = iTime(symbol, PERIOD_M15, shift);
         datetime barCloseTime = barOpenTime + PeriodSeconds(PERIOD_M15);

         // Ensure the bar has actually closed
         if(TimeCurrent() >= barCloseTime)
           {
            double high  = iHigh(symbol, PERIOD_M15, shift);
            double low   = iLow(symbol, PERIOD_M15, shift);
            double open  = iOpen(symbol, PERIOD_M15, shift);
            double close = iClose(symbol, PERIOD_M15, shift);
            double range = high - low;

            // Check ATR Threshold
            double atr[1];
            if(CopyBuffer(SymbolData[symbolIndex].ATR_Handle, 0, 0, 1, atr) > 0)
              {
               if(range >= (atr[0] * OR_ATR_Threshold))
                 {
                  // FIX 2: Calculate Expiry based on the BAR CLOSE time, not current time
                  datetime expiry = barCloseTime + (OR_WindowMinutes * 60);

                  // Only activate if we are CURRENTLY within the allowed window
                  if(TimeCurrent() < expiry)
                    {
                     SymbolData[symbolIndex].OR_Active = true;
                     SymbolData[symbolIndex].OR_High = high;
                     SymbolData[symbolIndex].OR_Low = low;
                     SymbolData[symbolIndex].OR_WasBullish = (close > open);
                     SymbolData[symbolIndex].OR_ExpiryTime = expiry;
                     SymbolData[symbolIndex].OR_BreakoutOccurred = false;

                     // Draw unique lines for this symbol
                     DrawBoxLine("OR_High_" + symbol, high, clrGreen);
                     DrawBoxLine("OR_Low_" + symbol, low, clrRed);

                     if(MBP_LogTierEnabled(MBP_LOG_TIER_DEBUG)) Print(symbol, " OR Active. Range: ", DoubleToString(range, _Digits),
                           " | Expires: ", TimeToString(expiry));
                    }
                 }
              }
           }
        }
     }

// -------------------------------------------------------------
// 3. MONITOR FOR TRADES
// -------------------------------------------------------------
   if(SymbolData[symbolIndex].OR_Active)
     {
      // Check Expiry
      if(TimeCurrent() > SymbolData[symbolIndex].OR_ExpiryTime)
        {
         SymbolData[symbolIndex].OR_Active = false;
         if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(symbol, " OR Window Expired.");
         ObjectDelete(0, "OR_High_" + symbol);
         ObjectDelete(0, "OR_Low_" + symbol);
         return;
        }

      double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);

      // --- SCENARIO A: 15m Was BULLISH -> Look for REVERSAL SELL ---
      if(SymbolData[symbolIndex].OR_WasBullish)
        {
         // 1. Check for Breakout ABOVE High (Bull Trap)
         if(currentPrice > SymbolData[symbolIndex].OR_High)
            SymbolData[symbolIndex].OR_BreakoutOccurred = true;

         if(SymbolData[symbolIndex].OR_BreakoutOccurred)
           {
            datetime barTime = iTime(symbol, OR_EntryTF, 1);
            if(barTime != SymbolData[symbolIndex].OR_LastCheckedBar)
              {
               bool signal = false;
               if(IsShootingStar(symbolIndex, OR_EntryTF, 1))
                 {
                  signal = true;
                 }
               else
                  if(IsBearishEngulfing(symbolIndex, OR_EntryTF, 1))
                    {
                     signal = true;
                    }

               if(signal && !IsPaused)
                 {
                  OpenTrade(symbolIndex, ORDER_TYPE_SELL);

                  SymbolData[symbolIndex].OR_Active = false;
                  ObjectDelete(0, "OR_High_" + symbol);
                  ObjectDelete(0, "OR_Low_" + symbol);
                 }
               SymbolData[symbolIndex].OR_LastCheckedBar = barTime;
              }
           }
        }
      // --- SCENARIO B: 15m Was BEARISH -> Look for REVERSAL BUY ---
      else
        {
         // 1. Check for Breakout BELOW Low (Bear Trap)
         if(currentPrice < SymbolData[symbolIndex].OR_Low)
            SymbolData[symbolIndex].OR_BreakoutOccurred = true;

         if(SymbolData[symbolIndex].OR_BreakoutOccurred)
           {
            datetime barTime = iTime(symbol, OR_EntryTF, 1);
            if(barTime != SymbolData[symbolIndex].OR_LastCheckedBar)
              {
               bool signal = false;
               if(IsHammer(symbolIndex, OR_EntryTF, 1))
                 {
                  signal = true;
                 }
               else
                  if(IsBullishEngulfing(symbolIndex, OR_EntryTF, 1))
                    {
                     signal = true;
                    }

               if(signal && !IsPaused)
                 {
                  OpenTrade(symbolIndex, ORDER_TYPE_BUY);

                  SymbolData[symbolIndex].OR_Active = false;
                  ObjectDelete(0, "OR_High_" + symbol);
                  ObjectDelete(0, "OR_Low_" + symbol);
                 }
               SymbolData[symbolIndex].OR_LastCheckedBar = barTime;
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Check Spread vs ATR Filter                                       |
//+------------------------------------------------------------------+
bool CheckSpread(int symbolIndex)
  {
   if(MaxSpreadATR <= 0.0)
      return true; // Filter disabled

   // V3 throttle: avoid recalculating spread gate every tick per symbol.
   static long s_lastSpreadCheckMs[200];
   static bool s_lastSpreadPass[200];

   long nowMs = (long)GetTickCount64();
   if(symbolIndex < 200)
     {
      int intervalMs = (InpV3_SpreadCheckMs > 0) ? InpV3_SpreadCheckMs : 1000;
      if((nowMs - s_lastSpreadCheckMs[symbolIndex]) < intervalMs)
         return s_lastSpreadPass[symbolIndex];
      s_lastSpreadCheckMs[symbolIndex] = nowMs;
     }

   string analysisSymbol = SymbolData[symbolIndex].symbol;
   string execSymbol = GetBaseSymbol(analysisSymbol);

   double ask = SymbolInfoDouble(execSymbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(execSymbol, SYMBOL_BID);
   double spread = ask - bid;

   double atr[1];
   if(CopyBuffer(SymbolData[symbolIndex].ATR_Handle, 0, 0, 1, atr) <= 0)
     {
      if(symbolIndex < 200) s_lastSpreadPass[symbolIndex] = true;
      return true;
     }

   double maxAllowed = atr[0] * MaxSpreadATR;
   bool pass = (spread <= maxAllowed);

   if(symbolIndex < 200) s_lastSpreadPass[symbolIndex] = pass;
   return pass;
  }

//+------------------------------------------------------------------+
//| Check Max Open Trades Filter (UPDATED)                           |
//+------------------------------------------------------------------+
bool CheckMaxOpenTrades(int symbolIndex)
{
   // 0 = Disabled
   if(Filter_MaxOpenTrades <= 0) return true;

   int count = 0;
   // Determine which symbol we are checking (Base Symbol handles suffixes like _Renko)
   string checkSymbol = GetBaseSymbol(SymbolData[symbolIndex].symbol);
   if(checkSymbol == "") checkSymbol = SymbolData[symbolIndex].symbol;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         long magic = PositionGetInteger(POSITION_MAGIC);
         // Check if trade belongs to this bot (standalone, coordinator, or any worker)
         if(IsAppTrade(magic) || IsAnyBotTrade(magic))
         {
            string sym = PositionGetString(POSITION_SYMBOL);

            if(Filter_GlobalTradeCount || sym == checkSymbol)
               count++;
         }
      }
   }

   if(count >= Filter_MaxOpenTrades)
   {
      // Limit reached, block new entries
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Update Filter Statistics (Run in OnTick)                         |
//+------------------------------------------------------------------+
void UpdateFilterStats(int symbolIndex)
  {
   // 1. Initialize if needed
   if(ArraySize(FilterTracker) <= symbolIndex) InitFilterTracker(symbolIndex);

   // 2. Throttle expensive work in hot path
   static datetime s_lastRun[200];
   static datetime s_lastProcessedDealTime[200];
   datetime now = TimeCurrent();

   if(symbolIndex < 200)
     {
      if((now - s_lastRun[symbolIndex]) < 5)
         return;
      s_lastRun[symbolIndex] = now;
     }

   // 3. CHECK FOR RESET
   bool reset = false;
   if(FilterResetMode == FILTER_RESET_DAILY)
     {
      MqlDateTime curr, last;
      TimeCurrent(curr);
      TimeToStruct(FilterTracker[symbolIndex].LastResetTime, last);
      if(curr.day != last.day) reset = true;
     }

   if(reset)
     {
      FilterTracker[symbolIndex].DailyWins = 0;
      FilterTracker[symbolIndex].DailyLosses = 0;
      FilterTracker[symbolIndex].WinStreak = 0;
      FilterTracker[symbolIndex].LossStreak = 0;
      FilterTracker[symbolIndex].SessionNetProfit = 0;
      FilterTracker[symbolIndex].SessionStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      FilterTracker[symbolIndex].LastResetTime = now;
      FilterTracker[symbolIndex].StopTrading = false;
      FilterTracker[symbolIndex].StopReason = "";
      if(symbolIndex < 200) s_lastProcessedDealTime[symbolIndex] = FilterTracker[symbolIndex].LastResetTime;
      if(MBP_LogTierEnabled(MBP_LOG_TIER_DEBUG)) Print("Filters Reset (New Cycle)");
     }

   // 4. CHECK HIGHER TIMEFRAME BLOCK
   ENUM_TIMEFRAMES filterTF = GetFilterTimeframe();
   string symbol = SymbolData[symbolIndex].symbol;
   double currentBlockHigh = GetBoxLevelAtBar(symbolIndex, filterTF, 1, true);
   double currentBlockLow  = GetBoxLevelAtBar(symbolIndex, filterTF, 1, false);

   if(currentBlockHigh != FilterTracker[symbolIndex].LastBlockHigh ||
      currentBlockLow != FilterTracker[symbolIndex].LastBlockLow)
     {
      FilterTracker[symbolIndex].BlockWins = 0;
      FilterTracker[symbolIndex].BlockLosses = 0;
      FilterTracker[symbolIndex].LastBlockHigh = currentBlockHigh;
      FilterTracker[symbolIndex].LastBlockLow = currentBlockLow;
     }

   // 5. INCREMENTAL HISTORY SCAN
   datetime scanFrom = FilterTracker[symbolIndex].LastResetTime;
   if(symbolIndex < 200 && s_lastProcessedDealTime[symbolIndex] > scanFrom)
      scanFrom = s_lastProcessedDealTime[symbolIndex];

   if(!HistorySelect(scanFrom, now))
      return;

   int total = HistoryDealsTotal();
   datetime newestSeen = scanFrom;

   for(int i = 0; i < total; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT)
         continue;

      datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      if(symbolIndex < 200 && dealTime <= s_lastProcessedDealTime[symbolIndex])
         continue;

      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != GetBaseSymbol(symbol))
         continue;
      if(!IsAppTrade(HistoryDealGetInteger(ticket, DEAL_MAGIC)))
         continue;

      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                      HistoryDealGetDouble(ticket, DEAL_SWAP) +
                      HistoryDealGetDouble(ticket, DEAL_COMMISSION);

      FilterTracker[symbolIndex].SessionNetProfit += profit;

      if(profit > 0)
        {
         FilterTracker[symbolIndex].DailyWins++;
         FilterTracker[symbolIndex].WinStreak++;
         FilterTracker[symbolIndex].LossStreak = 0;
        }
      else if(profit < 0)
        {
         FilterTracker[symbolIndex].DailyLosses++;
         FilterTracker[symbolIndex].LossStreak++;
         FilterTracker[symbolIndex].WinStreak = 0;
        }

      if(dealTime > newestSeen) newestSeen = dealTime;
     }

   if(symbolIndex < 200) s_lastProcessedDealTime[symbolIndex] = newestSeen;

   // 6. CHECK LIMITS
   FilterTracker[symbolIndex].StopTrading = false;

   double startEq = FilterTracker[symbolIndex].SessionStartEquity;
   if(startEq > 0)
     {
      double pctChange = (FilterTracker[symbolIndex].SessionNetProfit / startEq) * 100.0;

      if(Filter_MaxPctLoss > 0 && pctChange <= -Filter_MaxPctLoss)
        {
         FilterTracker[symbolIndex].StopTrading = true;
         FilterTracker[symbolIndex].StopReason = "Max % Loss Hit: " + DoubleToString(pctChange, 2) + "%";
        }
      if(Filter_MaxPctGain > 0 && pctChange >= Filter_MaxPctGain)
        {
         FilterTracker[symbolIndex].StopTrading = true;
         FilterTracker[symbolIndex].StopReason = "Max % Gain Hit: " + DoubleToString(pctChange, 2) + "%";
        }
     }

   if(Filter_MaxWins > 0 && FilterTracker[symbolIndex].DailyWins >= Filter_MaxWins)
      { FilterTracker[symbolIndex].StopTrading = true; FilterTracker[symbolIndex].StopReason = "Max Wins Hit"; }
   if(Filter_MaxLosses > 0 && FilterTracker[symbolIndex].DailyLosses >= Filter_MaxLosses)
      { FilterTracker[symbolIndex].StopTrading = true; FilterTracker[symbolIndex].StopReason = "Max Losses Hit"; }
   if(Filter_MaxWinStreak > 0 && FilterTracker[symbolIndex].WinStreak >= Filter_MaxWinStreak)
      { FilterTracker[symbolIndex].StopTrading = true; FilterTracker[symbolIndex].StopReason = "Max Win Streak Hit"; }
   if(Filter_MaxLossStreak > 0 && FilterTracker[symbolIndex].LossStreak >= Filter_MaxLossStreak)
      { FilterTracker[symbolIndex].StopTrading = true; FilterTracker[symbolIndex].StopReason = "Max Loss Streak Hit"; }
  }

//+------------------------------------------------------------------+
//| Check Filters (Call before OpenTrade)                            |
//+------------------------------------------------------------------+
bool CheckFilters(int symbolIndex)
  {
   if(ArraySize(FilterTracker) <= symbolIndex) return true;

   if(FilterTracker[symbolIndex].StopTrading)
     {
      // Optional: Print once
      // Print("Trading Paused: ", FilterTracker[symbolIndex].StopReason);
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Get Next Higher Timeframe (Block Filter)                         |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES GetFilterTimeframe()
  {
   // 1. If multiple TFs selected, find the one higher than current
   int currentIdx = -1;
   int enabledCount = 0;
   
   for(int i=0; i<7; i++)
     {
      if(TimeframeEnabled[i])
        {
         enabledCount++;
         if(Timeframes[i] == _Period) currentIdx = i;
        }
     }

   // If only 1 selected or current not found, return current
   if(enabledCount <= 1 || currentIdx == -1) return _Period;

   // Find next enabled index
   for(int i = currentIdx + 1; i < 7; i++)
     {
      if(TimeframeEnabled[i]) return Timeframes[i];
     }

   return _Period; // Fallback
  }
//+------------------------------------------------------------------+






#endif // __MULTIBOTPRO_TRADEENTRY_MQH__


//+------------------------------------------------------------------+
//|                                     CustomChartCreator_v3.mq5    |
//|                                  Copyright 2025, Gemini AI       |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Gemini AI"
#property link      "https://www.mql5.com"
#property version   "1.03"
#property strict

//--- INCLUDES
#include <Trade\Trade.mqh>

//--- INPUTS
input group "1. Chart Settings"
input int      InpPeriodSize     = 45;          // Timeframe Value (e.g., 45)
input bool     InpIsSeconds      = true;        // Is Value in Seconds? (false = Minutes)
input int      InpDaysHistory    = 5;           // Days of History to Load

input group "2. Trade Bridge (Robot Link)"
input bool     InpEnableTradeBridge = true;     // Enable Bridge?
input string   InpSignalPrefix      = "Signal"; // Arrow Name Prefix (e.g. "SignalBuy")
input double   InpDefaultVolume     = 0.01;     // Default Lot Size
input int      InpScanDepth         = 5;        // How many recent arrows to check
input bool     InpReverseSignals    = false;    // Reverse Logic (Buy becomes Sell)

//--- GLOBALS
string         sourceSymbol;
string         customSymbolName;
long           secondsPerBar;
long           chartID = 0; 
CTrade         Trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   sourceSymbol = _Symbol;
   secondsPerBar = InpIsSeconds ? InpPeriodSize : InpPeriodSize * 60;
   
   if(secondsPerBar <= 0) { Print("Error: Invalid timeframe."); return(INIT_FAILED); }

   // Generate Custom Symbol Name
   string suffix = InpIsSeconds ? "s" : "m";
   customSymbolName = sourceSymbol + "_" + IntegerToString(InpPeriodSize) + suffix;

   // 1. Create/Reset Custom Symbol
   if(!SymbolInfoInteger(customSymbolName, SYMBOL_CUSTOM))
   {
      CustomSymbolCreate(customSymbolName, "CustomCharts", sourceSymbol);
   }
   
   // Sync properties
   CustomSymbolSetInteger(customSymbolName, SYMBOL_DIGITS, (long)SymbolInfoInteger(sourceSymbol, SYMBOL_DIGITS));
   CustomSymbolSetDouble(customSymbolName, SYMBOL_POINT, SymbolInfoDouble(sourceSymbol, SYMBOL_POINT));
   CustomSymbolSetDouble(customSymbolName, SYMBOL_TRADE_TICK_SIZE, SymbolInfoDouble(sourceSymbol, SYMBOL_TRADE_TICK_SIZE));
   
   // Sync Trading Permissions for the Bridge
   CustomSymbolSetInteger(customSymbolName, SYMBOL_TRADE_MODE, (long)SYMBOL_TRADE_MODE_FULL);
   CustomSymbolSetDouble(customSymbolName, SYMBOL_VOLUME_MIN, SymbolInfoDouble(sourceSymbol, SYMBOL_VOLUME_MIN));
   CustomSymbolSetDouble(customSymbolName, SYMBOL_VOLUME_MAX, SymbolInfoDouble(sourceSymbol, SYMBOL_VOLUME_MAX));
   CustomSymbolSetDouble(customSymbolName, SYMBOL_VOLUME_STEP, SymbolInfoDouble(sourceSymbol, SYMBOL_VOLUME_STEP));

   SymbolSelect(customSymbolName, true); 

   // 2. Generate History
   GenerateHistory();

   // 3. Open Chart
   chartID = ChartOpen(customSymbolName, PERIOD_M1);
   if(chartID != 0)
   {
      ChartSetInteger(chartID, CHART_SHOW_BID_LINE, true);
      ChartSetInteger(chartID, CHART_SHOW_ASK_LINE, true);
      ChartRedraw(chartID);
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   MqlTick ticks[];
   int copied = CopyTicks(sourceSymbol, ticks, COPY_TICKS_ALL, 0, 1);
   
   if(copied > 0)
   {
      // 1. Feed Tick to Custom Symbol
      MqlTick customTick[1];
      customTick[0] = ticks[0];
      customTick[0].time = TimeCurrent(); 
      CustomTicksAdd(customSymbolName, customTick); 

      // 2. Update Bar Logic
      UpdateCustomBar(ticks[0]); 
      
      // 3. Scan for Trade Signals on the Custom Chart
      if(InpEnableTradeBridge && chartID != 0) 
      {
         ScanForSignals();
      }
   }
}

//+------------------------------------------------------------------+
//| Helper: Trade Bridge Logic                                       |
//+------------------------------------------------------------------+
void ScanForSignals()
{
   int total = ObjectsTotal(chartID, 0, OBJ_ARROW);
   if(total == 0) return;

   // Limit scan depth to save CPU
   int start = total - InpScanDepth;
   if(start < 0) start = 0;
   
   for(int i = total - 1; i >= start; i--)
   {
      string name = ObjectName(chartID, i, 0, OBJ_ARROW);

      // 1. Check Prefix match
      if(StringFind(name, InpSignalPrefix) < 0) continue;

      // 2. Strict Direction Logic
      bool isBuy  = (StringFind(name, "Buy") >= 0 || StringFind(name, "Up") >= 0 || StringFind(name, "Long") >= 0);
      bool isSell = (StringFind(name, "Sell") >= 0 || StringFind(name, "Down") >= 0 || StringFind(name, "Short") >= 0);

      if(!isBuy && !isSell) continue; // Skip ambiguous arrows

      // Reverse Logic Toggle
      if(InpReverseSignals)
      {
         bool temp = isBuy;
         isBuy = isSell;
         isSell = temp;
      }

      // 3. Signal Type: CLOSE Position
      if(StringFind(name, "Close") >= 0) 
      {
         ENUM_POSITION_TYPE typeToClose = isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
         
         for(int j = PositionsTotal() - 1; j >= 0; j--) 
         {
            ulong ticket = PositionGetTicket(j);
            if(PositionSelectByTicket(ticket)) 
            {
               // Only close positions for THIS symbol matching direction
               if(PositionGetInteger(POSITION_TYPE) == typeToClose && PositionGetString(POSITION_SYMBOL) == _Symbol)
               {
                  Trade.PositionClose(ticket);
               }
            }
         }
         ObjectDelete(chartID, name); // Clean up
      }
      // 4. Signal Type: OPEN Position
      else if(StringFind(name, "SL") < 0 && StringFind(name, "TP") < 0) 
      { 
         // Read Volume from Description
         string textObj = ObjectGetString(chartID, name, OBJPROP_TEXT);
         double tradeLot = (StringToDouble(textObj) > 0) ? StringToDouble(textObj) : InpDefaultVolume;

         if(isBuy)  
         {
            Trade.Buy(tradeLot, _Symbol, 0, 0, 0, "CustomChart_Bridge");
            ObjectDelete(chartID, name);
         }
         else if(isSell) 
         {
            Trade.Sell(tradeLot, _Symbol, 0, 0, 0, "CustomChart_Bridge");
            ObjectDelete(chartID, name);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Helper: Update The Bar (Candle Shape)                            |
//+------------------------------------------------------------------+
void UpdateCustomBar(MqlTick &tick)
{
   long barTime = tick.time - (tick.time % secondsPerBar);
   
   MqlRates rate[1];
   MqlRates currentRates[];
   
   if(CopyRates(customSymbolName, PERIOD_M1, 0, 1, currentRates) > 0 && currentRates[0].time == barTime)
   {
       rate[0] = currentRates[0];
       if(tick.bid > rate[0].high) rate[0].high = tick.bid;
       if(tick.bid < rate[0].low)  rate[0].low  = tick.bid;
       rate[0].close = tick.bid;
       rate[0].tick_volume++;
       rate[0].real_volume += (long)tick.volume;
   }
   else
   {
       rate[0].time = (datetime)barTime;
       rate[0].open = tick.bid;
       rate[0].high = tick.bid;
       rate[0].low  = tick.bid;
       rate[0].close = tick.bid;
       rate[0].tick_volume = 1;
       rate[0].real_volume = (long)tick.volume;
   }
   CustomRatesUpdate(customSymbolName, rate, 1);
}

//+------------------------------------------------------------------+
//| Helper: Generate History                                         |
//+------------------------------------------------------------------+
void GenerateHistory()
{
   Print("Generating history...");
   MqlTick ticks[];
   datetime start = TimeCurrent() - (InpDaysHistory * 86400);
   int totalTicks = CopyTicksRange(sourceSymbol, ticks, COPY_TICKS_ALL, start * 1000, TimeCurrent() * 1000);
   
   if(totalTicks <= 0) return;

   MqlRates rates[];
   ArrayResize(rates, totalTicks); 
   int barIndex = 0;
   datetime currentBarStart = 0;
   
   for(int i = 0; i < totalTicks; i++)
   {
      long barTime = ticks[i].time - (ticks[i].time % secondsPerBar);
      
      if(barTime != currentBarStart)
      {
         if(currentBarStart != 0) barIndex++;
         currentBarStart = (datetime)barTime;
         rates[barIndex].time = currentBarStart;
         rates[barIndex].open = ticks[i].bid;
         rates[barIndex].high = ticks[i].bid;
         rates[barIndex].low = ticks[i].bid;
         rates[barIndex].close = ticks[i].bid;
         rates[barIndex].tick_volume = 1;
         rates[barIndex].real_volume = (long)ticks[i].volume;
      }
      else
      {
         if(ticks[i].bid > rates[barIndex].high) rates[barIndex].high = ticks[i].bid;
         if(ticks[i].bid < rates[barIndex].low) rates[barIndex].low = ticks[i].bid;
         rates[barIndex].close = ticks[i].bid;
         rates[barIndex].tick_volume++;
         rates[barIndex].real_volume += (long)ticks[i].volume;
      }
   }
   CustomRatesUpdate(customSymbolName, rates, barIndex + 1);
}
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|                                  HeikenAshiRenko_Builder_v4.mq5  |
//|                                  Copyright 2025, Gemini AI       |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Gemini AI"
#property link      "https://www.mql5.com"
#property version   "4.00"
#property strict

//--- INCLUDES
#include <Trade\Trade.mqh>

//--- INPUTS
input group "1. Renko Settings"
input int      InpBlockSize      = 100;         // Block Size (Points)
input string   InpCustomSymbol   = "HARenko";   // Custom Symbol Suffix

input group "2. History Settings"
input int      InpHistoryDays    = 5;           // Days of History to generate

input group "3. Trade Bridge"
input bool     InpEnableBridge   = true;        // Enable Trade Bridge?
input string   InpSignalPrefix   = "Signal";    // Signal Arrow Prefix
input double   InpDefaultVolume  = 0.01;        // Default Lot Size

//--- GLOBALS
string         CustomSymbolName;
double         BlockSize;
double         RenkoAnchorPrice = 0;
bool           IsTrendUp = true;
long           customChartID = 0; 
CTrade         Trade;

// Heiken Ashi & Time Management
double         Prev_HA_Open = 0;
double         Prev_HA_Close = 0;
datetime       LastSyntheticTime = 0; 

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   CustomSymbolName = _Symbol + "_" + InpCustomSymbol;
   BlockSize = InpBlockSize * _Point;
   
   // 1. Create Custom Symbol
   if(!SymbolInfoInteger(CustomSymbolName, SYMBOL_CUSTOM))
      CustomSymbolCreate(CustomSymbolName, "CustomCharts", _Symbol);
   
   // 2. Sync Properties
   CustomSymbolSetInteger(CustomSymbolName, SYMBOL_DIGITS, (long)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   CustomSymbolSetDouble(CustomSymbolName, SYMBOL_POINT, SymbolInfoDouble(_Symbol, SYMBOL_POINT));
   CustomSymbolSetDouble(CustomSymbolName, SYMBOL_TRADE_TICK_SIZE, SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE));
   CustomSymbolSetInteger(CustomSymbolName, SYMBOL_TRADE_MODE, (long)SYMBOL_TRADE_MODE_FULL);
   
   // Sync Volume Limits for Bridge
   CustomSymbolSetDouble(CustomSymbolName, SYMBOL_VOLUME_MIN, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
   CustomSymbolSetDouble(CustomSymbolName, SYMBOL_VOLUME_MAX, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));
   CustomSymbolSetDouble(CustomSymbolName, SYMBOL_VOLUME_STEP, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP));
   
   SymbolSelect(CustomSymbolName, true);

   // 3. Build History (Nuclear Clean first)
   GenerateHistory();

   // 4. Open Chart
   customChartID = ChartOpen(CustomSymbolName, PERIOD_M1);
   if(customChartID != 0)
   {
      ChartSetInteger(customChartID, CHART_SHOW_BID_LINE, true);
      ChartSetInteger(customChartID, CHART_SHOW_ASK_LINE, true);
      ChartSetInteger(customChartID, CHART_MODE, CHART_CANDLES);
      ChartRedraw(customChartID);
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   
   // 1. Feed Tick to Custom Symbol (Keeps Price Lines moving)
   MqlTick customTick[1];
   customTick[0] = tick;
   // Important: Force tick time to "Next Synthetic Bar" so it updates the ghost candle
   customTick[0].time = LastSyntheticTime + 60; 
   CustomTicksAdd(CustomSymbolName, customTick);

   // 2. Process Renko Logic
   bool brickConfirmed = ProcessPrice(tick.bid);
   
   // 3. Update LIVE Ghost Brick (Visual Only) if no new brick was confirmed
   if(!brickConfirmed)
   {
      UpdateLiveBrick(tick.bid);
   }

   // 4. Trade Bridge Scan
   if(InpEnableBridge && customChartID != 0) ScanForSignals();
}

//+------------------------------------------------------------------+
//| Core Logic: Renko -> Heiken Ashi Transformation                  |
//+------------------------------------------------------------------+
bool ProcessPrice(double price)
{
   if(RenkoAnchorPrice == 0) { RenkoAnchorPrice = price; return false; }

   bool newBrick = false;
   double rOpen, rClose, rHigh, rLow; 

   // --- UP Trend Logic ---
   if(IsTrendUp)
   {
      if(price >= RenkoAnchorPrice + BlockSize)
      {
         rOpen = RenkoAnchorPrice;
         rClose = RenkoAnchorPrice + BlockSize;
         rHigh = rClose; rLow = rOpen;
         RenkoAnchorPrice += BlockSize;
         PushHeikenAshiBar(rOpen, rHigh, rLow, rClose); 
         newBrick = true;
      }
      else if(price <= RenkoAnchorPrice - (2 * BlockSize))
      {
         rOpen = RenkoAnchorPrice - BlockSize; 
         rClose = RenkoAnchorPrice - (2 * BlockSize);
         rHigh = rOpen; rLow = rClose;
         RenkoAnchorPrice = rClose;
         IsTrendUp = false;
         PushHeikenAshiBar(rOpen, rHigh, rLow, rClose);
         newBrick = true;
      }
   }
   // --- DOWN Trend Logic ---
   else 
   {
      if(price <= RenkoAnchorPrice - BlockSize)
      {
         rOpen = RenkoAnchorPrice;
         rClose = RenkoAnchorPrice - BlockSize;
         rHigh = rOpen; rLow = rClose;
         RenkoAnchorPrice -= BlockSize;
         PushHeikenAshiBar(rOpen, rHigh, rLow, rClose);
         newBrick = true;
      }
      else if(price >= RenkoAnchorPrice + (2 * BlockSize))
      {
         rOpen = RenkoAnchorPrice + BlockSize;
         rClose = RenkoAnchorPrice + (2 * BlockSize);
         rHigh = rClose; rLow = rOpen;
         RenkoAnchorPrice = rClose;
         IsTrendUp = true;
         PushHeikenAshiBar(rOpen, rHigh, rLow, rClose);
         newBrick = true;
      }
   }
   
   if(newBrick) ProcessPrice(price); // Recursion for big moves
   return newBrick;
}

//+------------------------------------------------------------------+
//| Helper: Update "Ghost" Brick (The flashing live candle)          |
//+------------------------------------------------------------------+
void UpdateLiveBrick(double currentPrice)
{
   // This function draws the current state of the brick WITHOUT
   // locking it in or advancing the time.
   
   double rOpen, rClose, rHigh, rLow;
   
   // Estimate where the "Standard Renko" would be right now
   // We use the AnchorPrice as the "Floor" or "Ceiling" depending on trend
   
   if(IsTrendUp)
   {
      rOpen = RenkoAnchorPrice;
      rClose = currentPrice; // The close is just where price is NOW
      rHigh = MathMax(rOpen, rClose);
      rLow  = MathMin(rOpen, rClose);
   }
   else
   {
      rOpen = RenkoAnchorPrice;
      rClose = currentPrice;
      rHigh = MathMax(rOpen, rClose);
      rLow  = MathMin(rOpen, rClose);
   }
   
   // Calculate LIVE Heiken Ashi values
   double ha_Open, ha_Close, ha_High, ha_Low;
   
   ha_Close = (rOpen + rHigh + rLow + rClose) / 4.0;
   
   // HA Open is FIXED based on the PREVIOUS locked bar
   if(Prev_HA_Open == 0) ha_Open = (rOpen + rClose) / 2.0; 
   else ha_Open = (Prev_HA_Open + Prev_HA_Close) / 2.0;
   
   ha_High = MathMax(rHigh, MathMax(ha_Open, ha_Close));
   ha_Low  = MathMin(rLow,  MathMin(ha_Open, ha_Close));

   // Draw it at the FUTURE time slot
   MqlRates rate[1];
   rate[0].time = LastSyntheticTime + 60; // Next Minute Slot
   rate[0].open = ha_Open;
   rate[0].high = ha_High;
   rate[0].low  = ha_Low;
   rate[0].close = ha_Close;
   rate[0].tick_volume = 1;
   rate[0].real_volume = 0;
   
   CustomRatesUpdate(CustomSymbolName, rate, 1);
}

//+------------------------------------------------------------------+
//| Helper: Lock in a Completed Brick                                |
//+------------------------------------------------------------------+
void PushHeikenAshiBar(double rOpen, double rHigh, double rLow, double rClose)
{
   double ha_Open, ha_Close, ha_High, ha_Low;
   
   ha_Close = (rOpen + rHigh + rLow + rClose) / 4.0;
   
   if(Prev_HA_Open == 0) ha_Open = (rOpen + rClose) / 2.0; 
   else ha_Open = (Prev_HA_Open + Prev_HA_Close) / 2.0;
   
   ha_High = MathMax(rHigh, MathMax(ha_Open, ha_Close));
   ha_Low  = MathMin(rLow,  MathMin(ha_Open, ha_Close));

   Prev_HA_Open = ha_Open;
   Prev_HA_Close = ha_Close;

   LastSyntheticTime += 60; // Advance Time

   MqlRates rate[1];
   rate[0].time = LastSyntheticTime; 
   rate[0].open = ha_Open;
   rate[0].high = ha_High;
   rate[0].low  = ha_Low;
   rate[0].close = ha_Close;
   rate[0].tick_volume = 1;
   rate[0].real_volume = 0;
   
   CustomRatesUpdate(CustomSymbolName, rate, 1);
}

//+------------------------------------------------------------------+
//| Helper: Generate History (Nuclear Option)                        |
//+------------------------------------------------------------------+
void GenerateHistory()
{
   Print("Generating Heiken Ashi Renko History...");
   
   // 1. DELETE EVERYTHING from 1970 to 2038 (Fixes Overlap)
   CustomRatesDelete(CustomSymbolName, D'1970.01.01', D'2038.01.01');
   
   datetime start = TimeCurrent() - (InpHistoryDays * 1440 * 60);
   MqlRates src[];
   int total = CopyRates(_Symbol, PERIOD_M1, start, TimeCurrent(), src);
   
   if(total <= 0) return;
   
   // Reset
   RenkoAnchorPrice = src[0].open;
   Prev_HA_Open = 0; 
   Prev_HA_Close = 0;
   
   // Start Synthetic Time in the past so the "Live" chart catches up to Now
   LastSyntheticTime = TimeCurrent() - (total * 60); 

   for(int i=0; i<total; i++)
   {
      if(src[i].close > src[i].open) 
      {
         ProcessPrice(src[i].open); ProcessPrice(src[i].low);
         ProcessPrice(src[i].high); ProcessPrice(src[i].close);
      }
      else 
      {
         ProcessPrice(src[i].open); ProcessPrice(src[i].high);
         ProcessPrice(src[i].low); ProcessPrice(src[i].close);
      }
   }
}

//+------------------------------------------------------------------+
//| Trade Bridge Scanner                                             |
//+------------------------------------------------------------------+
void ScanForSignals()
{
   int total = ObjectsTotal(customChartID, 0, OBJ_ARROW);
   if(total == 0) return;
   
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(customChartID, i, 0, OBJ_ARROW);
      if(StringFind(name, InpSignalPrefix) < 0) continue;
      
      bool isBuy = (StringFind(name, "Buy") >= 0);
      bool isSell = (StringFind(name, "Sell") >= 0);
      
      if(!isBuy && !isSell) continue;
      
      string text = ObjectGetString(customChartID, name, OBJPROP_TEXT);
      double lots = (StringToDouble(text) > 0) ? StringToDouble(text) : InpDefaultVolume;
      
      if(isBuy) { Trade.Buy(lots, _Symbol, 0, 0, 0, "HARenko_Bridge"); ObjectDelete(customChartID, name); }
      if(isSell) { Trade.Sell(lots, _Symbol, 0, 0, 0, "HARenko_Bridge"); ObjectDelete(customChartID, name); }
   }
}
//+------------------------------------------------------------------+
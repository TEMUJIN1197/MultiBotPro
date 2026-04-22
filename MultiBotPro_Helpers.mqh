#ifndef __MULTIBOTPRO_HELPERS_MQH__
#define __MULTIBOTPRO_HELPERS_MQH__
//+------------------------------------------------------------------+
//|                                          MultiBotPro_Helpers.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://discord.com/channels/929723953415589918/929723953415589920"

string GetManagedAnalysisSymbol(const int index)
  {
   if(index < 0 || index >= ArraySize(SymbolData))
      return "";

   if(SymbolData[index].AnalysisSymbol != "")
      return SymbolData[index].AnalysisSymbol;

   return SymbolData[index].symbol;
  }

string GetManagedExecutionSymbol(const int index)
  {
   if(index < 0 || index >= ArraySize(SymbolData))
      return "";

   if(SymbolData[index].BaseSymbol != "")
      return SymbolData[index].BaseSymbol;

   return GetBaseSymbol(GetManagedAnalysisSymbol(index));
  }

string GetManagedBaseSymbol(const int index)
  {
   string base = GetManagedExecutionSymbol(index);
   return (base == "") ? GetManagedAnalysisSymbol(index) : base;
  }

//+------------------------------------------------------------------+
//| Get symbol index from array                                      |
//+------------------------------------------------------------------+
int GetSymbolIndex(string symbol)
  {
   for(int i = 0; i < ArraySize(SymbolData); i++)
     {
      if(GetManagedAnalysisSymbol(i) == symbol || GetManagedExecutionSymbol(i) == symbol)
         return i;
     }
   return -1;
  }

int GetPrimarySymbolIndex(string symbol)
  {
   int fallback = -1;

   for(int i = 0; i < ArraySize(SymbolData); i++)
     {
      if(SymbolData[i].symbol != symbol)
         continue;

      if(fallback < 0)
         fallback = i;

      if(!InpEnableMultiBaskets || SymbolData[i].IsPrimaryBasket)
         return i;
     }

   return fallback;
  }

int GetPrimarySymbolIndexByBase(string baseSymbol, const bool activeOnly = true)
  {
   string targetBase = GetBaseSymbol(baseSymbol);
   if(targetBase == "")
      targetBase = baseSymbol;

   int fallback = -1;

   for(int i = 0; i < ArraySize(SymbolData); i++)
     {
      string symbolBase = GetManagedBaseSymbol(i);
      if(symbolBase == "")
         symbolBase = GetManagedAnalysisSymbol(i);

      if(StringCompare(symbolBase, targetBase, false) != 0)
         continue;
      if(activeOnly && !SymbolData[i].active)
         continue;

      if(fallback < 0)
         fallback = i;

      if(!InpEnableMultiBaskets || SymbolData[i].IsPrimaryBasket)
         return i;
     }

   return fallback;
  }

void ClearDashboardFocusSymbol()
  {
   G_DashboardFocusBaseSymbol = "";
  }

bool SetDashboardFocusSymbol(string symbol)
  {
   string targetBase = GetBaseSymbol(symbol);
   if(targetBase == "")
      targetBase = symbol;

   if(targetBase == "")
     {
      ClearDashboardFocusSymbol();
      return false;
     }

   int idx = GetPrimarySymbolIndexByBase(targetBase, true);
   if(idx < 0 || idx >= ArraySize(SymbolData) || !SymbolData[idx].active)
      return false;

   string resolvedBase = GetManagedBaseSymbol(idx);
   G_DashboardFocusBaseSymbol = (resolvedBase == "") ? GetManagedAnalysisSymbol(idx) : resolvedBase;
   return true;
  }

int ResolveExplicitDashboardFocusSymbolIndex()
  {
   if(G_DashboardFocusBaseSymbol == "")
      return -1;

   int idx = GetPrimarySymbolIndexByBase(G_DashboardFocusBaseSymbol, true);
   if(idx >= 0 && idx < ArraySize(SymbolData) && SymbolData[idx].active)
      return idx;

   ClearDashboardFocusSymbol();
   return -1;
  }

int ResolveChartSymbolIndex(string chartSymbol = "")
  {
   string targetSymbol = chartSymbol;
   if(targetSymbol == "")
      targetSymbol = _Symbol;

   int idx = GetPrimarySymbolIndex(targetSymbol);
   if(idx >= 0)
      return idx;

   if(RealSymbol != "" && RealSymbol != targetSymbol)
     {
      idx = GetPrimarySymbolIndex(RealSymbol);
      if(idx >= 0)
         return idx;
     }

   string baseSymbol = GetBaseSymbol(targetSymbol);
   if(baseSymbol != "" && baseSymbol != targetSymbol)
     {
      idx = GetPrimarySymbolIndex(baseSymbol);
      if(idx >= 0)
         return idx;
     }

   if(RealSymbol != "")
     {
      string realBase = GetBaseSymbol(RealSymbol);
      if(realBase != "" && realBase != RealSymbol)
        {
         idx = GetPrimarySymbolIndex(realBase);
         if(idx >= 0)
            return idx;
        }
     }

   return GetSymbolIndex(targetSymbol);
  }

int GetFirstActivePrimarySymbolIndex()
  {
   for(int i = 0; i < ArraySize(SymbolData); i++)
     {
      if(!SymbolData[i].active)
         continue;
      if(!InpEnableMultiBaskets || SymbolData[i].IsPrimaryBasket)
         return i;
     }

   for(int i = 0; i < ArraySize(SymbolData); i++)
     {
      if(SymbolData[i].active)
         return i;
     }

   return -1;
  }

int ResolveVisualFocusSymbolIndex(string chartSymbol = "")
  {
   int idx = ResolveChartSymbolIndex(chartSymbol);
   if(idx >= 0 && idx < ArraySize(SymbolData) && SymbolData[idx].active)
      return idx;

   return GetFirstActivePrimarySymbolIndex();
  }

int ResolveDashboardHostFocusSymbolIndex(string chartSymbol = "")
  {
   int idx = ResolveExplicitDashboardFocusSymbolIndex();
   if(idx >= 0)
      return idx;

   idx = ResolveVisualFocusSymbolIndex(chartSymbol);
   if(idx >= 0 && idx < ArraySize(SymbolData) && SymbolData[idx].active)
      return idx;

   return GetFirstActivePrimarySymbolIndex();
  }

string ResolveDashboardHostFocusManagedSymbol(string chartSymbol = "")
  {
   int idx = ResolveDashboardHostFocusSymbolIndex(chartSymbol);
   if(idx >= 0 && idx < ArraySize(SymbolData))
      return GetManagedAnalysisSymbol(idx);

   return (chartSymbol == "") ? _Symbol : chartSymbol;
  }
//+------------------------------------------------------------------+
//| Trim string helper function                                      |
//+------------------------------------------------------------------+
string TrimString(string str)
  {
   string result = str;
   StringTrimLeft(result);
   StringTrimRight(result);
   return result;
  }

bool TradingSymbolExists(string symbol)
  {
   string target = TrimString(symbol);
   if(target == "")
      return false;

   for(int i = 0; i < TradingSymbolsCount; i++)
     {
      if(StringCompare(TradingSymbols[i], target, false) == 0)
         return true;
     }

   return false;
  }

bool AppendTradingSymbolIfMissing(string symbol)
  {
   string target = TrimString(symbol);
   if(target == "" || TradingSymbolExists(target))
      return false;

   ArrayResize(TradingSymbols, TradingSymbolsCount + 1);
   TradingSymbols[TradingSymbolsCount] = target;
   TradingSymbolsCount++;
   return true;
  }
  
//+------------------------------------------------------------------+
//| Convert Server Time to NY Time (Robust)                          |
//+------------------------------------------------------------------+
void ConvertToNYTime(datetime server_time, MqlDateTime &ny_time)
  {
// 1. Standard NY Time is UTC - 5
   int target_offset = -5;

// 2. Calculate removing the Server Offset to get to UTC 0
// If Server is UTC+2, we subtract 2 hours to get base UTC.
   int to_utc = -InpServerGMTOffset;

// 3. Combine: (To UTC) + (To NY) + (Manual Adjustments)
   int total_shift_hours = to_utc + target_offset + InpNYManualShift;

// 4. Apply shift in seconds (Hours * 3600)
   datetime ny_calc = server_time + (total_shift_hours * 3600);

// 5. Convert result to struct
   TimeToStruct(ny_calc, ny_time);
  }
  
//+------------------------------------------------------------------+
//| Helper: Normalize Price to Symbol Tick Size                      |
//+------------------------------------------------------------------+
double NormalizePrice(string symbol, double price)
  {
   if(price == 0)
      return 0;
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE); // Checks the passed symbol
   if(tickSize == 0)
      return NormalizeDouble(price, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));

   return NormalizeDouble(MathRound(price / tickSize) * tickSize, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
  }
  
//+------------------------------------------------------------------+
//| Check Trading Time Permission (SYNCHRONIZED TO NY TIME)          |
//+------------------------------------------------------------------+
bool IsTradingTime()
  {
   MqlDateTime dt_ny;
   ConvertToNYTime(TimeCurrent(), dt_ny); // Converts Server Time to NY Time Struct

// 1. Day of Week Check
   if(dt_ny.day_of_week == 0 && !TradeSunday)
      return false;
   if(dt_ny.day_of_week == 1 && !TradeMonday)
      return false;
   if(dt_ny.day_of_week == 2 && !TradeTuesday)
      return false;
   if(dt_ny.day_of_week == 3 && !TradeWednesday)
      return false;
   if(dt_ny.day_of_week == 4 && !TradeThursday)
      return false;
   if(dt_ny.day_of_week == 5 && !TradeFriday)
      return false;
   if(dt_ny.day_of_week == 6 && !TradeSaturday)
      return false;

// --- FRIDAY HARD STOP WINDOW CHECK ---
   if(UseFridayHardStop && dt_ny.day_of_week == 5)
     {
      if(IsInsideInterval(FridayStop_StartHour, FridayStop_StartMinute, FridayStop_EndHour, FridayStop_EndMinute, dt_ny))
        {
         return false; // STOP ENTRY
        }
     }

// 2. Hard Close Block Check
   if(UseCloseBlock)
     {
      if(IsInsideInterval(CloseBlock_StartHour, CloseBlock_StartMinute, CloseBlock_EndHour, CloseBlock_EndMinute, dt_ny))
         return false;
     }

// 3. Session Windows Check
   if(UseTimeFilter)
     {
      bool inSession1 = UseSession1 && IsInsideInterval(Session1_StartHour, Session1_StartMinute, Session1_EndHour, Session1_EndMinute, dt_ny);
      bool inSession2 = UseSession2 && IsInsideInterval(Session2_StartHour, Session2_StartMinute, Session2_EndHour, Session2_EndMinute, dt_ny);
      bool inSession3 = UseSession3 && IsInsideInterval(Session3_StartHour, Session3_StartMinute, Session3_EndHour, Session3_EndMinute, dt_ny);

      if(!inSession1 && !inSession2 && !inSession3)
         return false;
     }

   return true;
  }
  
//+------------------------------------------------------------------+
//| Check if we are inside a specific time window                    |
//+------------------------------------------------------------------+
bool IsInsideInterval(int startH, int startM, int endH, int endM, MqlDateTime &dt)
  {
   int currTime = dt.hour * 60 + dt.min;
   int startTime = startH * 60 + startM;
   int endTime = endH * 60 + endM;

   if(startTime < endTime)
      return (currTime >= startTime && currTime < endTime);
   else // Spans midnight (e.g. 22:00 to 02:00)
      return (currTime >= startTime || currTime < endTime);
  }
  
//+------------------------------------------------------------------+
//| Check Economic Calendar for News & Holidays (REAL TIME SYNC)     |
//+------------------------------------------------------------------+
bool IsNewsTime()
  {
   if(!UseNewsFilter) return false;

   // --- CPU FIX START: CACHE RESULTS ---
   static bool _cachedResult = false;
   static ulong _lastCheckTick = 0;
   
   // Only query the database once every 60 seconds (60000 ms)
   if(GetTickCount() - _lastCheckTick < 60000) 
      return _cachedResult;
      
   _lastCheckTick = GetTickCount();
   // --- CPU FIX END ---

   // CRITICAL: Use Server Time (Real World)
   datetime checkTime = TimeTradeServer();

// 1. CHECK ALL-DAY HOLIDAYS
   if(NewsIncludeHolidays)
     {
      // Holidays are defined by the day, so we check the full 24h of 'checkTime'
      MqlDateTime dt;
      TimeToStruct(checkTime, dt);
      dt.hour=0;
      dt.min=0;
      dt.sec=0;
      datetime dayStart = StructToTime(dt);
      datetime dayEnd   = dayStart + 86400;

      MqlCalendarValue values[];
      if(CalendarValueHistory(values, dayStart, dayEnd))
        {
         for(int i=0; i<ArraySize(values); i++)
           {
            MqlCalendarEvent event;
            if(CalendarEventById(values[i].event_id, event))
              {
               if(event.type != CALENDAR_TYPE_HOLIDAY)
                  continue;

               // Currency Filter
               MqlCalendarCountry country;
               if(!CalendarCountryById(event.country_id, country))
                  continue;

               if(NewsFilterSymbolCurrency)
                 {
                  if(StringFind(_Symbol, country.currency) < 0 &&
                     country.currency != "USD" &&
                     country.currency != "EUR")
                     continue;
                 }

               return true; // It is a Holiday today
              }
           }
        }
     }

// 2. CHECK IMPACT NEWS (Time Window)
   if(NewsIncludeHigh || NewsIncludeMedium || NewsIncludeLow)
     {
      datetime timeFrom = checkTime - NewsMinutesAfter * 60;
      datetime timeTo   = checkTime + NewsMinutesBefore * 60;

      MqlCalendarValue values[];
      if(CalendarValueHistory(values, timeFrom, timeTo))
        {
         for(int i=0; i<ArraySize(values); i++)
           {
            MqlCalendarEvent event;
            if(CalendarEventById(values[i].event_id, event))
              {
               if(event.type == CALENDAR_TYPE_HOLIDAY)
                  continue;

               // Filter Importance
               bool impactMatch = false;
               if(event.importance == CALENDAR_IMPORTANCE_HIGH && NewsIncludeHigh)
                  impactMatch = true;
               if(event.importance == CALENDAR_IMPORTANCE_MODERATE && NewsIncludeMedium)
                  impactMatch = true;
               if(event.importance == CALENDAR_IMPORTANCE_LOW && NewsIncludeLow)
                  impactMatch = true;

               if(!impactMatch)
                  continue;

               // Currency Filter
               MqlCalendarCountry country;
               if(!CalendarCountryById(event.country_id, country))
                  continue;

               if(NewsFilterSymbolCurrency)
                 {
                  if(StringFind(_Symbol, country.currency) < 0 &&
                     country.currency != "USD" &&
                     country.currency != "EUR")
                     continue;
                 }

               return true; // We are inside a news window
              }
           }
        }
     }

   return false;
  }
  
//+------------------------------------------------------------------+
//| Helper: Calculate Commission from History Deals                  |
//+------------------------------------------------------------------+
double GetPositionCommission(ulong pos_id)
  {
   double comm = 0;
   if(HistorySelectByPosition(pos_id))
     {
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
        {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket > 0)
           {
            // Sum up commissions (Entry + Exit deals if any)
            comm += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
           }
        }
     }
   return comm;
  }
  
//+------------------------------------------------------------------+
//| Helper: Force Chart Appearance (Direct Property Set)             |
//+------------------------------------------------------------------+
void ApplyChartStyles(long chartID)
  {
// 1. Basic Settings
   ChartSetInteger(chartID, CHART_MODE, CHART_CANDLES);            // Candlesticks
   ChartSetInteger(chartID, CHART_SHOW_GRID, false);               // No Grid
   ChartSetInteger(chartID, CHART_SHOW_PERIOD_SEP, false);          // Show Period Separators
   ChartSetInteger(chartID, CHART_SHOW_ASK_LINE, true);            // Show Ask
   ChartSetInteger(chartID, CHART_SHOW_BID_LINE, true);            // Show Bid
   ChartSetInteger(chartID, CHART_SHOW_OHLC, true);                // Show OHLC in corner
   ChartSetInteger(chartID, CHART_SHOW_ONE_CLICK, false);          // Hide One-Click trading (clutter)

// 2. Color Scheme (Standard Dark Mode / Tester Look)
   ChartSetInteger(chartID, CHART_COLOR_BACKGROUND, clrBlack);     // Background
   ChartSetInteger(chartID, CHART_COLOR_FOREGROUND, clrWhite);     // Text/Axes
   ChartSetInteger(chartID, CHART_COLOR_GRID, clrDimGray);         // Grid (if enabled)
   ChartSetInteger(chartID, CHART_COLOR_VOLUME, clrLimeGreen);     // Volume bars

// Candle Colors
   ChartSetInteger(chartID, CHART_COLOR_CHART_UP, clrLime);        // Bull Candle Outline
   ChartSetInteger(chartID, CHART_COLOR_CHART_DOWN, clrTomato);       // Bear Candle Outline
   ChartSetInteger(chartID, CHART_COLOR_CHART_LINE, clrLime);      // Line Chart Color

   ChartSetInteger(chartID, CHART_COLOR_CANDLE_BEAR, clrTomato);      // Bear Body (Solid Red)
   ChartSetInteger(chartID, CHART_COLOR_CANDLE_BULL, clrLime);    // Bull Body (Hollow/Black)
// NOTE: If you want solid Green candles, change clrBlack to clrLime above.

// Price Line Colors
   ChartSetInteger(chartID, CHART_COLOR_BID, clrGray);             // Bid Line
   ChartSetInteger(chartID, CHART_COLOR_ASK, clrRed);              // Ask Line
   ChartSetInteger(chartID, CHART_COLOR_LAST, clrOrange);          // Last Price
   ChartSetInteger(chartID, CHART_COLOR_STOP_LEVEL, clrRed);       // SL/TP Levels

// 3. Force Update
   ChartRedraw(chartID);
  }

//+------------------------------------------------------------------+
//| Helper: Switch Chart Colors (News vs Normal)                     |
//+------------------------------------------------------------------+
void UpdateChartNewsColor(long chartID, bool isNewsActive)
  {
   if(isNewsActive)
     {
      // Set to News Color (Alert Mode)
      ChartSetInteger(chartID, CHART_COLOR_CHART_UP, NewsWindowColor);
      ChartSetInteger(chartID, CHART_COLOR_CHART_DOWN, NewsWindowColor);
      ChartSetInteger(chartID, CHART_COLOR_CANDLE_BEAR, NewsWindowColor);
      ChartSetInteger(chartID, CHART_COLOR_CANDLE_BULL, NewsWindowColor);
      ChartSetInteger(chartID, CHART_COLOR_CHART_LINE, NewsWindowColor);
     }
   else
     {
      // Revert to Standard Colors (Calls your existing style function)
      ApplyChartStyles(chartID);
     }
   ChartRedraw(chartID);
  }

//+------------------------------------------------------------------+
//| Helper: Paint the Current Bar (Overlay)                          |
//+------------------------------------------------------------------+
void HighlightActiveNewsBar()
  {
   if(!NewsWindowColorEnable)
      return;

// 1. Check if we are inside a News Window (Real Time Check)
   if(!IsNewsTime())
      return;

// 2. Get Current Bar Data (Renko Chart Time)
   datetime time = iTime(_Symbol, PERIOD_CURRENT, 0);
   double high   = iHigh(_Symbol, PERIOD_CURRENT, 0);
   double low    = iLow(_Symbol, PERIOD_CURRENT, 0);

// 3. Create Unique Name for THIS specific bar
   string objName = "NewsPaint_" + IntegerToString(time);

// 4. Draw/Update Overlay
   if(ObjectFind(0, objName) < 0)
     {
      // USE RECTANGLE instead of Trendline for better visibility
      // We assume the bar width is 1 period (e.g. 60 seconds for M1 Renko)
      if(ObjectCreate(0, objName, OBJ_RECTANGLE, 0, time, high, time + PeriodSeconds(), low))
        {
         ObjectSetInteger(0, objName, OBJPROP_COLOR, NewsWindowColor);
         ObjectSetInteger(0, objName, OBJPROP_FILL, true);   // Make it a solid block
         ObjectSetInteger(0, objName, OBJPROP_BACK, false);  // Draw ON TOP of the candle
         ObjectSetString(0, objName, OBJPROP_TOOLTIP, "News Window Bar");
         ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);

         // Debug print to confirm it triggered
         //Print(">>> NEWS ACTIVE: Painting Bar at ChartTime: ", TimeToString(time));
        }
     }
   else
     {
      // If the bar is still forming (growing), update the rectangle height
      // Point 1: Top-Left
      ObjectMove(0, objName, 0, time, high);
      // Point 2: Bottom-Right
      ObjectMove(0, objName, 1, time + PeriodSeconds(), low);
     }

// 5. FORCE UPDATE
   ChartRedraw(0);
  }
  
//+------------------------------------------------------------------+
//| Send alert                                                       |
//+------------------------------------------------------------------+
void SendAlert(string subject, string message)
  {
   if(EnableAlerts)
      Alert(subject + ": " + message);

   if(EnableEmailAlerts)
      SendMail(subject, message);

   if(EnablePushAlerts)
      SendNotification(subject + ": " + message);
  }
  
//+------------------------------------------------------------------+
//| Helper: Send Signal to RenkoBuilder Bridge                       |
//+------------------------------------------------------------------+
void SendBridgeSignal(bool isBuy, double volume)
  {
// 1. Generate Unique Name
   string dir    = isBuy ? "Buy" : "Sell";
// Use microsecond precision to prevent name collisions during split trades
   string name   = InpSignalPrefix + "_" + dir + "_" + TimeToString(TimeCurrent(), TIME_SECONDS) + "_" + IntegerToString(GetTickCount());

// 2. Determine Price for Visual Placement
   double price = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);

// 3. Create Arrow
   ENUM_OBJECT type = isBuy ? OBJ_ARROW_UP : OBJ_ARROW_DOWN;

   if(ObjectCreate(0, name, type, 0, TimeCurrent(), price))
     {
      // 4. EMBED LOT SIZE
      ObjectSetString(0, name, OBJPROP_TEXT, DoubleToString(volume, 2));
      ObjectSetInteger(0, name, OBJPROP_COLOR, isBuy ? clrGreen : clrRed);

      //Print("Bridge Signal Sent: ", name, " | Lot: ", volume);
     }
  }
  
//+------------------------------------------------------------------+
//| Helper: Send CLOSE Signal                                        |
//+------------------------------------------------------------------+
void SendBridgeClose(bool isBuy)
  {
// Name format: "Signal_Close_Buy_Time_Tick"
   string dir    = isBuy ? "Buy" : "Sell";
   string name   = InpSignalPrefix + "_Close_" + dir + "_" + TimeToString(TimeCurrent(), TIME_SECONDS) + "_" + IntegerToString(GetTickCount());

// Create Arrow (using different color for visual clarity, e.g., Gray)
   if(ObjectCreate(0, name, isBuy ? OBJ_ARROW_DOWN : OBJ_ARROW_UP, 0, TimeCurrent(), 0)) // Price 0 is fine, it just needs to exist
     {
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrGray);
      //Print("Bridge Exit Signal Sent: ", name);
     }
  }

//+------------------------------------------------------------------+
//| Helper: Send SL UPDATE Signal                                    |
//+------------------------------------------------------------------+
void SendBridgeSL(bool isBuy, double newSL)
  {
// Name format: "Signal_SL_Buy_Time_Tick"
   string dir    = isBuy ? "Buy" : "Sell";
   string name   = InpSignalPrefix + "_SL_" + dir + "_" + TimeToString(TimeCurrent(), TIME_SECONDS) + "_" + IntegerToString(GetTickCount());

   double price = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(ObjectCreate(0, name, OBJ_ARROW_RIGHT_PRICE, 0, TimeCurrent(), price))
     {
      // WRITE THE NEW SL PRICE INTO DESCRIPTION
      ObjectSetString(0, name, OBJPROP_TEXT, DoubleToString(newSL, _Digits));
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrBlue); // Blue for modification
      Print("Bridge SL Update Sent: ", newSL);
     }
  }
  

//+------------------------------------------------------------------+
//| VISUAL HELPER: Draw Stepline Box                                 |
//+------------------------------------------------------------------+
string GetBoxObjectTooltip(const string name)
  {
   if(StringFind(name, "BoxSeg_H_") >= 0 || StringFind(name, "BoxVert_H_") >= 0 || StringFind(name, "BoxLine_H_") >= 0)
      return "Rolling Resistance";
   if(StringFind(name, "BoxSeg_L_") >= 0 || StringFind(name, "BoxVert_L_") >= 0 || StringFind(name, "BoxLine_L_") >= 0)
      return "Rolling Support";
   if(StringFind(name, "OR_High_") >= 0)
      return "Opening Range High";
   if(StringFind(name, "OR_Low_") >= 0)
      return "Opening Range Low";
   return "Box Level";
  }

void DrawBoxLine(string name, double price, color clr, string tooltipText = "")
  {
   DrawBoxLineOnChart(0, name, price, clr, tooltipText);
  }

void DrawBoxLineOnChart(long chartID, string name, double price, color clr, string tooltipText = "")
  {
   string tooltip = (tooltipText == "") ? GetBoxObjectTooltip(name) : tooltipText;

   if(ObjectFind(chartID, name) < 0)
     {
      ObjectCreate(chartID, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(chartID, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(chartID, name, OBJPROP_WIDTH, 2);
      ObjectSetInteger(chartID, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(chartID, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(chartID, name, OBJPROP_SELECTED, false);
      ObjectSetInteger(chartID, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(chartID, name, OBJPROP_BACK, false);
      ObjectSetInteger(chartID, name, OBJPROP_ZORDER, 12);
      ObjectSetString(chartID, name, OBJPROP_TOOLTIP, tooltip);
     }
   else
     {
      ObjectMove(chartID, name, 0, 0, price);
      ObjectSetInteger(chartID, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(chartID, name, OBJPROP_WIDTH, 2);
      ObjectSetInteger(chartID, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(chartID, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(chartID, name, OBJPROP_SELECTED, false);
      ObjectSetInteger(chartID, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(chartID, name, OBJPROP_BACK, false);
      ObjectSetInteger(chartID, name, OBJPROP_ZORDER, 12);
      ObjectSetString(chartID, name, OBJPROP_TOOLTIP, tooltip);
     }
  }
  
//+------------------------------------------------------------------+
//| VISUAL HELPER: Draw Next Grid Level Line                         |
//+------------------------------------------------------------------+
void DrawGridLine(string name, double price, color clr)
  {
// Check if object exists
   if(ObjectFind(0, name) < 0)
     {
      // Create the line
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT); // Dashed/Dot line
      ObjectSetString(0, name, OBJPROP_TOOLTIP, "Next Grid Entry");
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, true); // Draw behind candles
     }
   else
     {
      // Update price
      ObjectMove(0, name, 0, 0, price);
     }
  }
  
//+------------------------------------------------------------------+
//| Helper: Draw Horizontal Stepline Segment (Long Segment)          |
//+------------------------------------------------------------------+
void DrawSteplineSegment(string name, datetime time1, datetime time2, double price, color clr)
  {
   DrawSteplineSegmentOnChart(0, name, time1, time2, price, clr);
  }

void DrawSteplineSegmentOnChart(long chartID, string name, datetime time1, datetime time2, double price, color clr)
  {
   int finalWidth = (BoxLines_Style == STYLE_SOLID) ? BoxLines_Width : 1;
   string tooltip = GetBoxObjectTooltip(name);

   if(ObjectFind(chartID, name) < 0)
     {
      ObjectCreate(chartID, name, OBJ_TREND, 0, time1, price, time2, price);
      ObjectSetInteger(chartID, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(chartID, name, OBJPROP_WIDTH, finalWidth);
      ObjectSetInteger(chartID, name, OBJPROP_STYLE, BoxLines_Style);
      ObjectSetInteger(chartID, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(chartID, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(chartID, name, OBJPROP_SELECTED, false);
      ObjectSetInteger(chartID, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(chartID, name, OBJPROP_BACK, false);
      ObjectSetInteger(chartID, name, OBJPROP_ZORDER, 12);
      ObjectSetString(chartID, name, OBJPROP_TOOLTIP, tooltip);
     }
   else
     {
      ObjectMove(chartID, name, 0, time1, price);
      ObjectMove(chartID, name, 1, time2, price);
      ObjectSetInteger(chartID, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(chartID, name, OBJPROP_WIDTH, finalWidth);
      ObjectSetInteger(chartID, name, OBJPROP_STYLE, BoxLines_Style);
      ObjectSetInteger(chartID, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(chartID, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(chartID, name, OBJPROP_SELECTED, false);
      ObjectSetInteger(chartID, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(chartID, name, OBJPROP_BACK, false);
      ObjectSetInteger(chartID, name, OBJPROP_ZORDER, 12);
      ObjectSetString(chartID, name, OBJPROP_TOOLTIP, tooltip);
     }
  }

//+------------------------------------------------------------------+
//| Helper: Draw Vertical Connector (Ladder Step)                    |
//+------------------------------------------------------------------+
void DrawVerticalSegment(string name, int barIndex, double price1, double price2, color clr)
  {
   datetime time = iTime(_Symbol, PERIOD_CURRENT, barIndex);
   DrawVerticalSegmentOnChart(0, name, time, price1, price2, clr);
  }

void DrawVerticalSegmentOnChart(long chartID, string name, datetime time, double price1, double price2, color clr)
  {
   int finalWidth = (BoxLines_Style == STYLE_SOLID) ? BoxLines_Width : 1;
   string tooltip = GetBoxObjectTooltip(name);

   if(ObjectFind(chartID, name) < 0)
     {
      ObjectCreate(chartID, name, OBJ_TREND, 0, time, price1, time, price2);
      ObjectSetInteger(chartID, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(chartID, name, OBJPROP_WIDTH, finalWidth);
      ObjectSetInteger(chartID, name, OBJPROP_STYLE, BoxLines_Style);
      ObjectSetInteger(chartID, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(chartID, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(chartID, name, OBJPROP_SELECTED, false);
      ObjectSetInteger(chartID, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(chartID, name, OBJPROP_BACK, false);
      ObjectSetInteger(chartID, name, OBJPROP_ZORDER, 12);
      ObjectSetString(chartID, name, OBJPROP_TOOLTIP, tooltip);
     }
   else
     {
      ObjectMove(chartID, name, 0, time, price1);
      ObjectMove(chartID, name, 1, time, price2);
      ObjectSetInteger(chartID, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(chartID, name, OBJPROP_WIDTH, finalWidth);
      ObjectSetInteger(chartID, name, OBJPROP_STYLE, BoxLines_Style);
      ObjectSetInteger(chartID, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(chartID, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(chartID, name, OBJPROP_SELECTED, false);
      ObjectSetInteger(chartID, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(chartID, name, OBJPROP_BACK, false);
      ObjectSetInteger(chartID, name, OBJPROP_ZORDER, 12);
      ObjectSetString(chartID, name, OBJPROP_TOOLTIP, tooltip);
     }
  }

//+------------------------------------------------------------------+
//| Draw News Events (Real-Time Stamper)                             |
//+------------------------------------------------------------------+
void DrawNewsLines()
  {
   if(!UseNewsFilter || !ShowNewsLines)
      return;

// 1. TIMING CONTROL
// We only check for news once per minute to save resources
   static datetime lastCheckTime = 0;
   datetime realTimeNow = TimeTradeServer(); // Get REAL WORLD time (e.g., 2025), not Chart time

   if(realTimeNow - lastCheckTime < 60)
      return;
   lastCheckTime = realTimeNow;

// 2. DEFINE SEARCH WINDOW (Look at the last minute of Real Time)
// We look for events that happened since our last check
   datetime start = realTimeNow - 60;
   datetime end   = realTimeNow;

   MqlCalendarValue values[];

// 3. FETCH REAL NEWS
   if(CalendarValueHistory(values, start, end))
     {
      for(int i=0; i<ArraySize(values); i++)
        {
         MqlCalendarEvent event;
         if(CalendarEventById(values[i].event_id, event))
           {
            // --- FILTERING ---
            bool isRelevant = false;
            if(event.importance == CALENDAR_IMPORTANCE_HIGH && NewsIncludeHigh)
               isRelevant = true;
            if(event.importance == CALENDAR_IMPORTANCE_MODERATE && NewsIncludeMedium)
               isRelevant = true;
            if(event.importance == CALENDAR_IMPORTANCE_LOW && NewsIncludeLow)
               isRelevant = true;
            if(event.type == CALENDAR_TYPE_HOLIDAY && NewsIncludeHolidays)
               isRelevant = true;

            if(!isRelevant)
               continue;

            // Currency Filter
            MqlCalendarCountry country;
            if(CalendarCountryById(event.country_id, country))
              {
               if(NewsFilterSymbolCurrency)
                 {
                  if(StringFind(_Symbol, country.currency) < 0 &&
                     country.currency != "USD" &&
                     country.currency != "EUR")
                     continue;
                 }
              }

            // --- COLOR SELECTION ---
            color finalColor = clrGray;
            if(event.type == CALENDAR_TYPE_HOLIDAY)
               finalColor = NewsColorHoliday;
            else
              {
               switch(event.importance)
                 {
                  case CALENDAR_IMPORTANCE_HIGH:
                     finalColor = NewsColorHigh;
                     break;
                  case CALENDAR_IMPORTANCE_MODERATE:
                     finalColor = NewsColorMed;
                     break;
                  case CALENDAR_IMPORTANCE_LOW:
                     finalColor = NewsColorLow;
                     break;
                 }
              }

            // --- DRAWING LOGIC (THE FIX) ---
            // We cannot use 'values[i].time' (2025) because the chart is in 2020.
            // Instead, we mark the CURRENT RENKO BAR as the spot where news happened.
            datetime chartTime = TimeCurrent();

            // Unique Name: "NewsLine_" + RealID
            string lineName = "NewsLine_" + IntegerToString(values[i].id);

            if(ObjectFind(0, lineName) < 0)
              {
               ObjectCreate(0, lineName, OBJ_VLINE, 0, chartTime, 0);
               ObjectSetInteger(0, lineName, OBJPROP_COLOR, finalColor);
               ObjectSetInteger(0, lineName, OBJPROP_STYLE, NewsLineStyle);
               ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 1); // Keep it thin
               ObjectSetInteger(0, lineName, OBJPROP_BACK, true);

               // Store Metadata for the Click Popup
               ObjectSetString(0, lineName, OBJPROP_TOOLTIP, event.name);
               ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, true);

               // OPTIONAL: Store the REAL time in the object so popup shows 2025, not 2020
               // (OBJPROP_CREATETIME is read-only, but we can rely on the ID lookup in ShowNewsDetails)

               Print("News Event Stamped: ", event.name, " @ Renko Time ", chartTime);
              }
           }
        }
      ChartRedraw();
     }
  }


//+------------------------------------------------------------------+
//| Helper: Check if trade belongs to Bot or User (based on Mode)    |
//+------------------------------------------------------------------+
bool IsAppTrade(long tradeMagic)
  {
// 1. Always accept the Bot's own trades
   if(tradeMagic == (long)MagicNumber)
      return true;

// 2. If Mode is Semi-Auto or Mixed, accept Manual Trades (Magic 0)
   if(OperationMode != MODE_AUTO && tradeMagic == 0)
      return true;

   return false;
  }

//+------------------------------------------------------------------+
//| Helper: Parse Real Symbol from Analysis Symbol (Dynamic)         |
//+------------------------------------------------------------------+
// (GetBaseSymbol moved to MultiBotPro_SymbolContext.mqh)
//+------------------------------------------------------------------+
//| Basket helpers (multi-basket mode)                              |
//+------------------------------------------------------------------+
int ExtractBasketId(string comment)
  {
   int pos = StringFind(comment, "B#");
   if(pos < 0) return -1;
   pos += 2;
   string num = "";
   int len = StringLen(comment);
   while(pos < len)
     {
      int ch = StringGetCharacter(comment, pos);
      if(ch < 48 || ch > 57) break;
      num += StringSubstr(comment, pos, 1);
      pos++;
     }
   if(num == "") return -1;
   return (int)StringToInteger(num);
  }

bool IsPositionInBasket(int symbolIndex, string comment)
  {
   if(!InpEnableMultiBaskets) return true;
   int bid = ExtractBasketId(comment);
   if(bid < 0) return SymbolData[symbolIndex].IsPrimaryBasket;
   return (bid == SymbolData[symbolIndex].BasketId);
  }

string BasketScopedObjectName(int symbolIndex, string prefix, string symbol)
  {
   if(!InpEnableMultiBaskets) return prefix + symbol;
   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData)) return prefix + symbol;
   return prefix + symbol + StringFormat("_B%d", SymbolData[symbolIndex].BasketId);
  }

bool HasActiveGridBasketState(int idx)
  {
   if(idx < 0 || idx >= ArraySize(SymbolData)) return false;
   return (SymbolData[idx].PositionCount > 0 ||
           SymbolData[idx].BasketActive ||
           SymbolData[idx].GridLevels > 0 ||
           SymbolData[idx].GridPhase1Active ||
           SymbolData[idx].GridPhase2Active ||
           SymbolData[idx].GridBasketVolume > 0.0 ||
           SymbolData[idx].GridBasketEntry > 0.0 ||
           SymbolData[idx].GridTargetReached);
  }

bool HasActiveZoneBasketState(int idx)
  {
   if(idx < 0 || idx >= ArraySize(SymbolData)) return false;
   return (SymbolData[idx].PositionCount > 0 ||
           SymbolData[idx].BasketActive ||
           SymbolData[idx].ZoneActive ||
           SymbolData[idx].ZoneSeqCount > 0 ||
           SymbolData[idx].ZoneTopPrice != 0.0 ||
           SymbolData[idx].ZoneBottomPrice != 0.0 ||
           SymbolData[idx].ZoneResolved);
  }

bool HasActiveNormalBasketState(int idx)
  {
   if(idx < 0 || idx >= ArraySize(SymbolData)) return false;
   return (SymbolData[idx].PositionCount > 0 ||
           SymbolData[idx].BasketActive ||
           SymbolData[idx].MasterTicket > 0 ||
           SymbolData[idx].MasterEntry > 0.0 ||
           SymbolData[idx].InitialTP > 0.0 ||
           SymbolData[idx].MasterHasValidSL ||
           SymbolData[idx].NonGridStack.Counter > 0 ||
           SymbolData[idx].StackLastOpenedCounter > 0);
  }

bool IsBasketActiveIndex(int idx)
  {
   if(idx < 0 || idx >= ArraySize(SymbolData)) return false;
   if(RiskMode == RISK_MODE_GRID)
      return HasActiveGridBasketState(idx);
   if(RiskMode == RISK_MODE_ZONE_RECOVERY)
      return HasActiveZoneBasketState(idx);
   return HasActiveNormalBasketState(idx);
  }

int CountActiveBasketsForSymbol(string symbol)
  {
   int count = 0;
   for(int i = 0; i < ArraySize(SymbolData); i++)
     {
      if(SymbolData[i].symbol != symbol) continue;
      if(IsBasketActiveIndex(i)) count++;
     }
   return count;
  }

bool HasAnyActiveBasketForSymbol(string symbol)
  {
   return (CountActiveBasketsForSymbol(symbol) > 0);
  }

int GetNextBasketIdForSymbol(string symbol)
  {
   int nextId = 1;
   for(int i = 0; i < ArraySize(SymbolData); i++)
     {
      if(GetManagedAnalysisSymbol(i) != symbol && GetManagedExecutionSymbol(i) != symbol)
         continue;
      if(!IsBasketActiveIndex(i))
         continue;

      int currentId = SymbolData[i].BasketId;
      if(currentId < 1)
         currentId = 1;

      if(currentId >= nextId)
         nextId = currentId + 1;
     }
   return nextId;
  }

bool BasketDirectionAllowed(string symbol, ENUM_ORDER_TYPE orderType)
  {
   if(!InpEnableMultiBaskets) return true;
   ENUM_POSITION_TYPE dir = (orderType == ORDER_TYPE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;

   for(int i = 0; i < ArraySize(SymbolData); i++)
     {
      if(SymbolData[i].symbol != symbol) continue;
      if(!IsBasketActiveIndex(i)) continue;

      ENUM_POSITION_TYPE existing = SymbolData[i].BasketDirection;
      if(InpBasketDirectionPolicy == BASKET_DIR_BOTH) continue;
      if(InpBasketDirectionPolicy == BASKET_DIR_SAME && existing != dir) return false;
      if(InpBasketDirectionPolicy == BASKET_DIR_SINGLE && existing != dir) return false;
     }
   return true;
  }

bool BasketDistanceOk(int symbolIndex, double entryPrice)
  {
   if(!InpEnableMultiBaskets) return true;
   string symbol = SymbolData[symbolIndex].symbol;
   string execSymbol = GetBaseSymbol(symbol);

   double atrVal = 0.0;
   double atr[1];
   if(CopyBuffer(SymbolData[symbolIndex].ATR_Handle, 0, 0, 1, atr) > 0)
      atrVal = atr[0];
   if(atrVal <= 0)
      atrVal = SymbolInfoDouble(execSymbol, SYMBOL_POINT) * 50.0;

   double minDist = atrVal * InpMinBasketDistanceATR;

   for(int i = 0; i < ArraySize(SymbolData); i++)
     {
      if(SymbolData[i].symbol != symbol) continue;
      if(!IsBasketActiveIndex(i)) continue;

      double otherEntry = SymbolData[i].BasketInitialEntry;
      if(otherEntry > 0 && MathAbs(entryPrice - otherEntry) < minDist)
         return false;
     }
   return true;
  }

int CreateBasketClone(int baseIndex, ENUM_ORDER_TYPE orderType)
  {
   int newIndex = ArraySize(SymbolData);
   ArrayResize(SymbolData, newIndex + 1);

   string sym = GetManagedBaseSymbol(baseIndex);
   if(sym == "")
      sym = SymbolData[baseIndex].symbol;
   ENUM_MBP_DATA_MODE mode = SymbolData[baseIndex].DataMode;
   if(!InitializeSymbolData(sym, newIndex, mode))
      return -1;

   // Carry over dynamic tuning state (Shadow Master)
   SymbolData[newIndex].Dyn_MA1_Period = SymbolData[baseIndex].Dyn_MA1_Period;
   SymbolData[newIndex].Dyn_MA2_Period = SymbolData[baseIndex].Dyn_MA2_Period;
   SymbolData[newIndex].Dyn_Box_Lookback = SymbolData[baseIndex].Dyn_Box_Lookback;
   SymbolData[newIndex].Dyn_ADX_Period = SymbolData[baseIndex].Dyn_ADX_Period;
   SymbolData[newIndex].Dyn_ADX_MinLevel = SymbolData[baseIndex].Dyn_ADX_MinLevel;
   SymbolData[newIndex].Dyn_CurrencyStrengthDelta = SymbolData[baseIndex].Dyn_CurrencyStrengthDelta;
   SymbolData[newIndex].Dyn_GridMultiplier = SymbolData[baseIndex].Dyn_GridMultiplier;
   SymbolData[newIndex].Dyn_NLP_Killswitch = SymbolData[baseIndex].Dyn_NLP_Killswitch;
   SymbolData[newIndex].LastShadowUpdate = SymbolData[baseIndex].LastShadowUpdate;

   SymbolData[newIndex].BasketId = GetNextBasketIdForSymbol(sym);
   SymbolData[newIndex].IsPrimaryBasket = false;
   SymbolData[newIndex].BasketActive = false;
   SymbolData[newIndex].BasketInitialEntry = 0.0;
   SymbolData[newIndex].BasketDirection = (orderType == ORDER_TYPE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;

   return newIndex;
  }

int ResolveBasketIndexForSignal(int symbolIndex, ENUM_ORDER_TYPE orderType, double entryPrice)
  {
   if(!InpEnableMultiBaskets)
      return symbolIndex;

   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return -1;

   if(!SymbolData[symbolIndex].IsPrimaryBasket)
      return -1;

   string symbol = SymbolData[symbolIndex].symbol;
   string direction = (orderType == ORDER_TYPE_BUY) ? "BUY" : "SELL";

   int maxBaskets = InpMaxBasketsPerSymbol;
   if(maxBaskets < 1) maxBaskets = 1;

   int activeCount = CountActiveBasketsForSymbol(symbol);
   if(activeCount >= maxBaskets)
      return -1;

   if(!BasketDirectionAllowed(symbol, orderType))
      return -1;

   if(!BasketDistanceOk(symbolIndex, entryPrice))
      return -1;

   if(!HasAnyActiveBasketForSymbol(symbol))
     {
      if(RiskMode == RISK_MODE_NONE)
         PrintFormat("[Basket] %s %s routed to primary basket B#%d.", symbol, direction, MathMax(1, SymbolData[symbolIndex].BasketId));
      return symbolIndex;
     }

   int cloneIndex = CreateBasketClone(symbolIndex, orderType);
   if(cloneIndex >= 0)
     {
      if(RiskMode == RISK_MODE_NONE)
         PrintFormat("[Basket] %s %s routed to clone B#%d.", symbol, direction, SymbolData[cloneIndex].BasketId);
     }
   else
     {
      PrintFormat("Warning: Failed to create a basket clone for %s %s.", symbol, direction);
     }

   return cloneIndex;
  }

//+------------------------------------------------------------------+
//| Build symbol list                                                |
//+------------------------------------------------------------------+
void BuildSymbolList()
  {
// Clear existing symbols
   TradingSymbolsCount = 0;
   ArrayResize(TradingSymbols, 0);

   if(IsParallelWorkerMode())
     {
      string workerSymbol = G_RuntimeAssignedWorkerSymbol;
      if(workerSymbol == "")
         workerSymbol = GetBaseSymbol(G_RuntimeAssignedChartSymbol);
      if(workerSymbol == "")
         workerSymbol = GetBaseSymbol(_Symbol);
      if(workerSymbol == "")
         workerSymbol = _Symbol;

      if(workerSymbol != "")
         AppendTradingSymbolIfMissing(workerSymbol);

      TradingSymbolsCount = ArraySize(TradingSymbols);
      return;
     }

   {
      if(ManualSymbols != "")
        {
         string symbols[];
         int count = StringSplit(ManualSymbols, ',', symbols);
         for(int i = 0; i < count; i++)
           {
            string requestedSymbol = TrimString(symbols[i]);
            if(requestedSymbol == "")
               continue;

            long wasSelected = 0;
            bool exactWasSelected = SymbolInfoInteger(requestedSymbol, SYMBOL_SELECT, wasSelected) && (wasSelected != 0);

            string resolvedSymbol = "";
            bool usedVariant = false;
            if(ResolveRequestedTradingSymbol(requestedSymbol, resolvedSymbol, usedVariant))
              {
               AppendTradingSymbolIfMissing(resolvedSymbol);

               if(usedVariant)
                  Print("[Symbols] Manual symbol ", requestedSymbol, " mapped to broker symbol ", resolvedSymbol, " and added to Market Watch.");
               else if(!exactWasSelected)
                  Print("[Symbols] Manual symbol ", resolvedSymbol, " auto-added to Market Watch.");
              }
            else
              {
               Print("[Symbols] Manual symbol ", requestedSymbol, " was not found in terminal symbols and was skipped.");
              }
           }
        }

      if(TradeAllMarketWatch)
        {
         for(int i = 0; i < SymbolsTotal(true); i++)
           {
            string symbol = SymbolName(i, true);

            bool excluded = false;
            if(ExcludeSymbols != "")
              {
               string excludeList[];
               int excludeCount = StringSplit(ExcludeSymbols, ',', excludeList);
               for(int j = 0; j < excludeCount; j++)
                 {
                  if(TrimString(excludeList[j]) == symbol)
                    {
                     excluded = true;
                     break;
                    }
                 }
              }

            if(!excluded)
               AppendTradingSymbolIfMissing(symbol);
           }
        }

      if(UseChartSymbol)
         AppendTradingSymbolIfMissing(_Symbol);

      return;
   }

// Add manual symbols
   if(ManualSymbols != "")
     {
      string symbols[];
      int count = StringSplit(ManualSymbols, ',', symbols);
      for(int i = 0; i < count; i++)
        {
         string symbol = TrimString(symbols[i]);
         if(SymbolInfoInteger(symbol, SYMBOL_SELECT))
           {
            ArrayResize(TradingSymbols, TradingSymbolsCount + 1);
            TradingSymbols[TradingSymbolsCount] = symbol;
            TradingSymbolsCount++;
           }
         else
           {
            Print("⚠️ Symbol ", symbol, " is not available in Market Watch.");
           }
        }
     }

// Add all MarketWatch symbols
   if(TradeAllMarketWatch)
     {
      for(int i = 0; i < SymbolsTotal(true); i++)
        {
         string symbol = SymbolName(i, true);

         // Check if symbol is excluded
         bool excluded = false;
         if(ExcludeSymbols != "")
           {
            string excludeList[];
            int excludeCount = StringSplit(ExcludeSymbols, ',', excludeList);
            for(int j = 0; j < excludeCount; j++)
              {
               if(TrimString(excludeList[j]) == symbol)
                 {
                  excluded = true;
                  break;
                 }
              }
           }

         if(!excluded)
           {
            ArrayResize(TradingSymbols, TradingSymbolsCount + 1);
            TradingSymbols[TradingSymbolsCount] = symbol;
            TradingSymbolsCount++;
           }
        }
     }

// Add chart symbol if not in list and UseChartSymbol is true
   if(UseChartSymbol)
     {
      string chartSymbol = _Symbol;
      bool found = false;
      for(int i = 0; i < TradingSymbolsCount; i++)
        {
         if(TradingSymbols[i] == chartSymbol)
           {
            found = true;
            break;
           }
        }
      if(!found)
        {
         ArrayResize(TradingSymbols, TradingSymbolsCount + 1);
         TradingSymbols[TradingSymbolsCount] = chartSymbol;
         TradingSymbolsCount++;
        }
     }
  }

//+------------------------------------------------------------------+
//| Check if last trade has locked-in profit - FIXED FOR ZONE        |
//+------------------------------------------------------------------+
bool CheckLastTradeLockedInProfit(int symbolIndex, bool isBasketMode)
  {
// 1. Define Context
   string trackingSymbol = GetBaseSymbol(SymbolData[symbolIndex].symbol);

// 2. Find the last opened position on the REAL SYMBOL
   ulong lastTicket = 0;
   datetime lastOpenTime = 0;
   ENUM_POSITION_TYPE lastType = POSITION_TYPE_BUY;

   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         // CRITICAL CHECK: Look at Real Symbol
         if(PositionGetString(POSITION_SYMBOL) == trackingSymbol &&
            IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
           {
            string comment = PositionGetString(POSITION_COMMENT);
            if(InpEnableMultiBaskets && !IsPositionInBasket(symbolIndex, comment))
               continue;

            // FIX: Check for "Grid" OR "Zone" OR "Stack" when in Basket Mode
            bool isBasketTrade = (StringFind(comment, "Grid") >= 0 || StringFind(comment, "Zone") >= 0);

            // Filter: Are we checking Basket trades (Grid/Zone) or Normal trades?
            if(isBasketMode == isBasketTrade)
              {
               datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
               // Find the most recent one
               if(openTime > lastOpenTime)
                 {
                  lastOpenTime = openTime;
                  lastTicket = ticket;
                  lastType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                 }
              }
           }
        }
     }

   if(lastTicket == 0)
      return false; // No position found

// 3. Get Current Price
   double currentPrice = (lastType == POSITION_TYPE_BUY) ?
                         SymbolInfoDouble(trackingSymbol, SYMBOL_BID) :
                         SymbolInfoDouble(trackingSymbol, SYMBOL_ASK);

// 4. Get Current Stop Loss
   double currentSL = 0;
   if(!isBasketMode)
     {
      // For standard trades, use the Master SL
      currentSL = SymbolData[symbolIndex].MasterSL;
     }
   else
     {
      // For Grid/Zone trades, use the Basket SL
      currentSL = SymbolData[symbolIndex].GridBasketStopLoss;
     }

   if(currentSL == 0)
      return false; // No SL set, definitely not locked in

// 5. Check Safety Condition
   if(lastType == POSITION_TYPE_BUY)
     {
      // For Buy: Price must be ABOVE SL
      if(currentPrice <= currentSL)
         return false;
     }
   else
     {
      // For Sell: Price must be BELOW SL
      if(currentPrice >= currentSL)
         return false;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| Get Dynamic Profit Target (Scales with Grid/Zone Level)          |
//+------------------------------------------------------------------+
double GetDynamicProfitTarget(int symbolIndex)
  {
   // 1. Determine Base Profit based on Mode
   double baseProfit = 0.0;
   int currentLevel = 0;

   if(RiskMode == RISK_MODE_ZONE_RECOVERY)
     {
      baseProfit = ZoneTP_Amount;
      // For Zone, use Sequence Count. If 0 (Entry), next is 1.
      currentLevel = SymbolData[symbolIndex].ZoneSeqCount; 
     }
   else
     {
      baseProfit = GridTP_Amount;
      // For Grid, use GridLevels.
      currentLevel = SymbolData[symbolIndex].GridLevels;
     }

   // 2. If Scaling is OFF, return static base
   if(!UseDynamicProfitScaling) 
      return baseProfit;

   // 3. Calculate Scaled Target for the NEXT trade
   // Example: If we are at Level 2, we are opening Level 3. Target = Base * 3.
   int nextLevel = currentLevel + 1;
   
   if(nextLevel < 1) nextLevel = 1;

   return baseProfit * nextLevel;
  }

//+------------------------------------------------------------------+
//| Calculate take profit (FIXED FOR REAL EXECUTION)                 |
//+------------------------------------------------------------------+
double CalculateTakeProfit(int symbolIndex, ENUM_ORDER_TYPE orderType, double entryPrice, double sl)
  {
// --- FIX: USE DYNAMIC EXECUTION SYMBOL ---
   string execSymbol = GetBaseSymbol(SymbolData[symbolIndex].symbol);
   string symbol     = SymbolData[symbolIndex].symbol;
   double tp         = 0;
   double renkoPoint = SymbolInfoDouble(symbol, SYMBOL_POINT); // Use Renko point for FixedTP calc

// 1. FIXED POINTS
   if(TakeProfitType == TP_FIXED)
     {
      tp = (orderType == ORDER_TYPE_BUY) ?
           entryPrice + (FixedTP * renkoPoint) :
           entryPrice - (FixedTP * renkoPoint);
     }
// 2. RISK : REWARD RATIO
   else
      if(TakeProfitType == TP_RR)
        {
         if(sl != 0)
           {
            double risk = MathAbs(entryPrice - sl);
            tp = (orderType == ORDER_TYPE_BUY) ?
                 entryPrice + (risk * TP_Ratio) :
                 entryPrice - (risk * TP_Ratio);
           }
        }
      // 3. ATR MULTIPLE (NEW)
      else
         if(TakeProfitType == TP_ATR)
           {
            double atr[1];
            if(CopyBuffer(SymbolData[symbolIndex].ATR_Handle, 0, 0, 1, atr) > 0)
              {
               double atrVal = atr[0];
               tp = (orderType == ORDER_TYPE_BUY) ?
                    entryPrice + (atrVal * TP_ATR_Multiplier) :
                    entryPrice - (atrVal * TP_ATR_Multiplier);
              }
           }

// VALIDATE AGAINST REAL SYMBOL RULES
   if(tp != 0)
     {
      int stopsLevel = (int)SymbolInfoInteger(execSymbol, SYMBOL_TRADE_STOPS_LEVEL);
      double realPoint = SymbolInfoDouble(execSymbol, SYMBOL_POINT);
      double minDistance = (stopsLevel + 2) * realPoint;

      // Ensure TP is not too close to entry (Broker restriction)
      if(MathAbs(entryPrice - tp) < minDistance)
        {
         tp = (orderType == ORDER_TYPE_BUY) ?
              entryPrice + minDistance :
              entryPrice - minDistance;
        }

      // Normalize to Real Symbol Tick Size
      tp = NormalizePrice(execSymbol, tp);
     }

   return tp;
  }
  
//+------------------------------------------------------------------+
//| Count grid/zone positions                                        |
//+------------------------------------------------------------------+
int CountGridPositions(int symbolIndex, bool includeStackTrades = true)
  {
   string trackingSymbol = GetBaseSymbol(SymbolData[symbolIndex].symbol);
   int count = 0;

   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetString(POSITION_SYMBOL) == trackingSymbol &&
            IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
           {
            string comment = PositionGetString(POSITION_COMMENT);
            if(InpEnableMultiBaskets && !IsPositionInBasket(symbolIndex, comment))
               continue;
            // FIX: logic handles Zone trades too
            bool isRelevant = (StringFind(comment, "Grid") >= 0 || StringFind(comment, "Zone") >= 0);

            if(includeStackTrades)
              {
               if(isRelevant || StringFind(comment, "Stack") >= 0)
                  count++;
              }
            else
              {
               // Count only original levels (Grid/Zone), not Stacks
               if(isRelevant && StringFind(comment, "Stack") < 0)
                  count++;
              }
           }
        }
     }
   return count;
  }

//+------------------------------------------------------------------+
//| Calculate grid/zone basket metrics                               |
//+------------------------------------------------------------------+
void CalculateGridBasket(int symbolIndex)
  {
   string symbol = SymbolData[symbolIndex].symbol;
// Use Real Symbol
   string execSymbol = GetBaseSymbol(symbol);

   double totalVolume = 0;
   double totalValue = 0;

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
            // FIX: Added "Zone" to calculation
            if(StringFind(comment, "Grid") >= 0 ||
               StringFind(comment, "Stack") >= 0 ||
               StringFind(comment, "Zone") >= 0)
              {
               double volume = PositionGetDouble(POSITION_VOLUME);
               double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);

               totalVolume += volume;
               totalValue += volume * entryPrice;
              }
           }
        }
     }

   if(totalVolume > 0)
     {
      SymbolData[symbolIndex].GridBasketEntry = totalValue / totalVolume;
      SymbolData[symbolIndex].GridBasketVolume = totalVolume;
     }
  }

//+------------------------------------------------------------------+
//| Check take profit                                                |
//+------------------------------------------------------------------+
bool CheckTakeProfit(ENUM_POSITION_TYPE posType, double currentPrice, double tpPrice)
  {
   if(posType == POSITION_TYPE_BUY)
     {
      return currentPrice >= tpPrice;
     }
   else
     {
      return currentPrice <= tpPrice;
     }
  }

//+------------------------------------------------------------------+
//| Close all global positions                                       |
//+------------------------------------------------------------------+
void CloseAllGlobalPositions(string reason)
  {
   int closed = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
           {
            string execSymbol = GetBaseSymbol(PositionGetString(POSITION_SYMBOL));
            bool protectedTicket = SmartHedge_IsProtectedTicket(ticket);
            if(Trade.PositionClose(ticket))
              {
               if(!protectedTicket && IsBridgeRuntimeEnabled())
                  SmartHedge_QueueSlaveClose(ticket, execSymbol);
               closed++;
              }
           }
        }
     }

   if(closed > 0)
     {
      Print("Closed ", closed, " global positions: ", reason);
      //SendAlert("All Global Positions Closed", reason);
     }
  }

//+------------------------------------------------------------------+
//| Helper: Check if the last opened trade was a BUY                 |
//+------------------------------------------------------------------+
bool IsLastTradeBuy(int symbolIndex)
  {
   string execSymbol = GetBaseSymbol(SymbolData[symbolIndex].symbol);
   datetime lastTime = 0;
   bool wasBuy = false;
   bool found = false;

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
            datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
            if(openTime > lastTime)
              {
               lastTime = openTime;
               wasBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
               found = true;
              }
           }
        }
     }
   return (
             found && wasBuy);
  }

//+------------------------------------------------------------------+
//| Helper: Check if the last opened trade was a SELL                |
//+------------------------------------------------------------------+
bool IsLastTradeSell(int symbolIndex)
  {
   string execSymbol = GetBaseSymbol(SymbolData[symbolIndex].symbol);
   datetime lastTime = 0;
   bool wasSell = false;
   bool found = false;

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
            datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
            if(openTime > lastTime)
              {
               lastTime = openTime;
               wasSell = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL);
               found = true;
              }
           }
        }
     }
   return (found && wasSell);
  }

//+------------------------------------------------------------------+
//| Helper: Calculate Total Net Profit for Symbol                    |
//+------------------------------------------------------------------+
double GetTotalProfit(int symbolIndex)
  {
   string execSymbol = GetBaseSymbol(SymbolData[symbolIndex].symbol);
   double totalProfit = 0.0;

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
            ulong posID = PositionGetInteger(POSITION_IDENTIFIER);
            double p = PositionGetDouble(POSITION_PROFIT);
            double s = PositionGetDouble(POSITION_SWAP);
            double c = GetPositionCommission(posID);

            totalProfit += (p + s + c);
           }
        }
     }
   return totalProfit;
  }

//+------------------------------------------------------------------+
//| V3 Bridge Runtime Helpers                                        |
//+------------------------------------------------------------------+
bool V3_SqliteBridgeEnabled()
{
   return (InpV3_EnableSQLiteBridge && StringLen(InpV3_SQLitePath) > 0);
}

void V3_PumpBridgeService()
{
   if(!V3_SqliteBridgeEnabled()) return;

   static bool schemaReady = false;
   if(!schemaReady)
      schemaReady = V3_EnsureRuntimeSchema(InpV3_SQLitePath);

   static ulong lastHbMs = 0;
   int intervalMs = (InpV3_HeartbeatIntervalMs > 0) ? InpV3_HeartbeatIntervalMs : 1000;
   ulong nowMs = GetTickCount();
   if(nowMs - lastHbMs < (ulong)intervalMs) return;
   lastHbMs = nowMs;

   string hb = "V3BridgeHeartbeat_" + InpHedgeChannel;
   GlobalVariableSet(hb, (double)TimeCurrent());
}

void AppendDebtLedgerEvent(string symbol, string eventType, double deltaAmount, double pruningBal, double criticalBal)
{
   if(V3_SqliteBridgeEnabled())
   {
      string metadata = StringFormat("{\"source\":\"master\",\"symbol\":\"%s\"}", symbol);
      V3_InsertDebtLedgerRow(InpV3_SQLitePath,
                             InpHedgeChannel,
                             symbol,
                             eventType,
                             deltaAmount,
                             pruningBal,
                             criticalBal,
                             metadata);
   }

   string ledgerFile = "DebtLedger_" + InpHedgeChannel + ".csv";
   int h = FileOpen(ledgerFile, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h == INVALID_HANDLE)
      h = FileOpen(ledgerFile, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);

   if(h == INVALID_HANDLE)
      return;

   FileSeek(h, 0, SEEK_END);
   string row = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "," +
                symbol + "," + eventType + "," +
                DoubleToString(deltaAmount, 2) + "," +
                DoubleToString(pruningBal, 2) + "," +
                DoubleToString(criticalBal, 2);
   FileWriteString(h, row + "\r\n");
   FileClose(h);
}

//+------------------------------------------------------------------+
//| Helper: Check if Hedge Master has blocked trading                |
//+------------------------------------------------------------------+
bool IsHedgeBlocked()
{
   if(!InpUseHedgeBridge) return false;

   // Stop flag (hard block)
   string stopVar = InpHedgeChannel + "_STOP_FLAG";
   if(GlobalVariableCheck(stopVar) && GlobalVariableGet(stopVar) > 0.1)
      return true;

   // Pause flag (cooldown / temporary block)
   string pauseVar = InpHedgeChannel + "_PAUSE_FLAG";
   if(GlobalVariableCheck(pauseVar) && GlobalVariableGet(pauseVar) > 0.1)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| Helper: Remove Signal Arrows (Stops Infinite Re-entry Loop)      |
//+------------------------------------------------------------------+
void RemoveSignalArrows()
{
   // Adjust object names based on what your bot actually draws
   ObjectsDeleteAll(0, "SignalArrow", 0, OBJ_ARROW);
   ObjectsDeleteAll(0, "Arrow", 0, OBJ_ARROW); 
   // If your bot uses specific prefixes, add them here
} 

//+------------------------------------------------------------------+
//| NUCLEAR CLEANUP: Force Delete All Bot Objects                    |
//+------------------------------------------------------------------+
void ForceDeleteAllBotObjects()
{
   // 1. Define keywords to wipe
   // ADDED: "BoxLine_", "MP_", "NewsIcon_", "Signal_" to catch missing objects
   string targetPrefixes[] = {
      "BoxSeg_", "BoxVert_", "BoxLine_", // Box Indicator
      "ZoneTop_", "ZoneBot_",            // Zone Lines
      "Grid_NextLevel_",                 // Grid Lines
      "OR_High_", "OR_Low_",             // OR Lines
      "NewsLine_", "NewsPaint_", "NewsIcon_", // News
      "MAN_", "BTN_",                    // GUI Panel & Buttons
      "MP_",                             // Modification Lines (SL/TP Draggers)
      "SignalArrow", "Arrow", "Signal_", // Signal Arrows
      "Debt_",                           // Visual Debt debugs
      MBV_PREFIX                           // Indicator overlay visuals
   };

   // 2. Scan ALL objects on the chart
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, -1, -1);
      
      // Check for match
      for(int k = 0; k < ArraySize(targetPrefixes); k++)
      {
         // Use StringFind to catch anything containing these tags
         if(StringFind(name, targetPrefixes[k]) >= 0) 
         {
            ObjectDelete(0, name);
            break; 
         }
      }
   }
   
   // 3. Force strict redraw to clear "ghost" pixels
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| CORE: Phantom Bar Check (Syntax from Renko_EA_Logic)             |
//+------------------------------------------------------------------+
bool IsPhantomBar(string symbol, int index)
{
   // In AZ-Invest/Median Renko, 'Filler' bars have 0 volume.
   // We must skip these to find the true Renko brick.
   ENUM_TIMEFRAMES tf = (bool)SymbolInfoInteger(symbol, SYMBOL_CUSTOM) ? PERIOD_M1 : (ENUM_TIMEFRAMES)ChartPeriod(0);
   long tickVol = iTickVolume(symbol, tf, index);
   long realVol = iRealVolume(symbol, tf, index);
   
   return (tickVol == 0 && realVol == 0);
}

//+------------------------------------------------------------------+
//| CORE: Get Valid Bar Index (Skips Phantoms)                       |
//+------------------------------------------------------------------+
int GetRealBarIndex(int symbolIdx, int requestedIndex)
{
   // If Standard Mode, return index directly
   if(SymbolData[symbolIdx].DataMode == MBP_DATA_LIVE ||
      SymbolData[symbolIdx].DataMode == MBP_DATA_HEIKEN_ASHI ||
      SymbolData[symbolIdx].DataMode == MBP_DATA_HEIKEN_RENKO ||
      SymbolData[symbolIdx].DataMode == MBP_DATA_CUSTOM_TIME)
      return requestedIndex;
   
   string sym = SymbolData[symbolIdx].symbol;
   int limit = 100; // Search depth limit
   int validCount = 0;
   
   // Scan backwards from 0 to find the 'requestedIndex'th REAL bar
   for(int i=0; i<1000; i++)
   {
      if(!IsPhantomBar(sym, i))
      {
         if(validCount == requestedIndex) return i;
         validCount++;
      }
   }
   return requestedIndex; // Fallback
}

ENUM_TIMEFRAMES GetManagedSeriesTimeframe(int symbolIdx)
{
   if(symbolIdx < 0 || symbolIdx >= ArraySize(SymbolData))
      return (ENUM_TIMEFRAMES)ChartPeriod(0);

   if(MBP_IsSyntheticDataMode(SymbolData[symbolIdx].DataMode))
      return PERIOD_M1;

   return (ENUM_TIMEFRAMES)ChartPeriod(0);
}

bool GetManagedSyntheticBarFromFactory(int symbolIdx, int index, SMBPCustomBar &bar)
{
   if(symbolIdx < 0 || symbolIdx >= ArraySize(SymbolData))
      return false;
   if(!MBP_IsSyntheticDataMode(SymbolData[symbolIdx].DataMode))
      return false;
   if(CheckPointer(SymbolData[symbolIdx].ChartFactories) == POINTER_INVALID)
      return false;

   for(int i = 0; i < SymbolData[symbolIdx].ChartFactories.Total(); i++)
   {
      CChartFactory *factory = (CChartFactory*)SymbolData[symbolIdx].ChartFactories.At(i);
      if(CheckPointer(factory) == POINTER_INVALID)
         continue;
      if(factory.GetBar(index, bar))
         return true;
   }

   return false;
}

bool GetManagedBar(int symbolIdx, int index, SMBPCustomBar &bar)
{
   if(symbolIdx < 0 || symbolIdx >= ArraySize(SymbolData))
      return false;

   string symbol = SymbolData[symbolIdx].symbol;
   if(symbol == "")
      return false;

   if(GetManagedSyntheticBarFromFactory(symbolIdx, index, bar))
      return true;

   ENUM_TIMEFRAMES tf = GetManagedSeriesTimeframe(symbolIdx);
   int barIndex = MBP_IsSyntheticDataMode(SymbolData[symbolIdx].DataMode) ? GetRealBarIndex(symbolIdx, index) : index;
   MqlRates rates[];
   if(CopyRates(symbol, tf, barIndex, 1, rates) <= 0)
      return false;

   bar.open = rates[0].open;
   bar.high = rates[0].high;
   bar.low = rates[0].low;
   bar.close = rates[0].close;
   bar.time = rates[0].time;
   bar.tick_volume = rates[0].tick_volume;
   return true;
}

long GetManagedVolume(int symbolIdx, int index)
{
   if(symbolIdx < 0 || symbolIdx >= ArraySize(SymbolData))
      return 0;

   SMBPCustomBar bar;
   if(GetManagedSyntheticBarFromFactory(symbolIdx, index, bar))
      return bar.tick_volume;

   ENUM_TIMEFRAMES tf = GetManagedSeriesTimeframe(symbolIdx);
   int barIndex = MBP_IsSyntheticDataMode(SymbolData[symbolIdx].DataMode) ? GetRealBarIndex(symbolIdx, index) : index;
   return iVolume(SymbolData[symbolIdx].symbol, tf, barIndex);
}

//+------------------------------------------------------------------+
//| DATA ABSTRACTION LAYER: Smart Getters                            |
//| Replaces direct iClose/iHigh calls throughout the bot            |
//+------------------------------------------------------------------+
double GetClose(int symbolIdx, int index)
{
   SMBPCustomBar bar;
   if(GetManagedBar(symbolIdx, index, bar))
      return bar.close;

   return SymbolInfoDouble(SymbolData[symbolIdx].symbol, SYMBOL_BID);
}

double GetOpen(int symbolIdx, int index)
{
   SMBPCustomBar bar;
   if(GetManagedBar(symbolIdx, index, bar))
      return bar.open;

   return SymbolInfoDouble(SymbolData[symbolIdx].symbol, SYMBOL_ASK);
}

double GetHigh(int symbolIdx, int index)
{
   SMBPCustomBar bar;
   if(GetManagedBar(symbolIdx, index, bar))
      return bar.high;

   return SymbolInfoDouble(SymbolData[symbolIdx].symbol, SYMBOL_ASK);
}

double GetLow(int symbolIdx, int index)
{
   SMBPCustomBar bar;
   if(GetManagedBar(symbolIdx, index, bar))
      return bar.low;

   return SymbolInfoDouble(SymbolData[symbolIdx].symbol, SYMBOL_BID);
}

datetime GetTime(int symbolIdx, int index)
{
   SMBPCustomBar bar;
   if(GetManagedBar(symbolIdx, index, bar))
      return bar.time;

   return TimeCurrent();
}

//+------------------------------------------------------------------+
//| Load Shadow Master Config from JSON                              |
//+------------------------------------------------------------------+
void LoadShadowConfig(int symbolIndex)
{
   if(!InpEnableShadowMaster) return;

   string sym = SymbolData[symbolIndex].symbol;
   string filename = InpShadowConfigName + "_" + sym + ".json";

   // Check if the Python script has generated the file
   if(FileIsExist(filename)) 
   {
      int h = FileOpen(filename, FILE_READ|FILE_TXT|FILE_ANSI);
      if(h != INVALID_HANDLE) 
      {
         string json = "";
         while(!FileIsEnding(h)) 
         {
            json += FileReadString(h);
         }
         FileClose(h);

         // Track old values to see if handles need refreshing
         int old_ma1 = SymbolData[symbolIndex].Dyn_MA1_Period;
         int old_ma2 = SymbolData[symbolIndex].Dyn_MA2_Period;
         int old_adx = SymbolData[symbolIndex].Dyn_ADX_Period;
         int old_box = SymbolData[symbolIndex].Dyn_Box_Lookback;
         // Extract and Assign (Using your existing V3_ExtractJSONValue func)
         string str_ma1 = V3_ExtractJSONValue(json, "MA1_Period");
         if(str_ma1 != "") SymbolData[symbolIndex].Dyn_MA1_Period = (int)StringToInteger(str_ma1);

         string str_ma2 = V3_ExtractJSONValue(json, "MA2_Period");
         if(str_ma2 != "") SymbolData[symbolIndex].Dyn_MA2_Period = (int)StringToInteger(str_ma2);

         string str_box = V3_ExtractJSONValue(json, "Box_Lookback");
         if(str_box != "") SymbolData[symbolIndex].Dyn_Box_Lookback = (int)StringToInteger(str_box);

         string str_adx_p = V3_ExtractJSONValue(json, "ADX_Period");
         if(str_adx_p != "") SymbolData[symbolIndex].Dyn_ADX_Period = (int)StringToInteger(str_adx_p);

         string str_adx_min = V3_ExtractJSONValue(json, "ADX_MinLevel");
         if(str_adx_min != "") SymbolData[symbolIndex].Dyn_ADX_MinLevel = StringToDouble(str_adx_min);

         string str_delta = V3_ExtractJSONValue(json, "CurrencyStrengthDelta");
         if(str_delta != "") SymbolData[symbolIndex].Dyn_CurrencyStrengthDelta = StringToDouble(str_delta);

         string str_grid = V3_ExtractJSONValue(json, "GridMultiplier");
         if(str_grid != "") SymbolData[symbolIndex].Dyn_GridMultiplier = StringToDouble(str_grid);

         string str_nlp = V3_ExtractJSONValue(json, "NLP_Killswitch");
         if(str_nlp != "") SymbolData[symbolIndex].Dyn_NLP_Killswitch = (str_nlp == "True" || str_nlp == "true");
         // ---------------------------

         SymbolData[symbolIndex].LastShadowUpdate = TimeCurrent();

         // --- DYNAMIC HANDLE REFRESH ---
         // If Python changed the periods, rebuild the indicators
         if(old_ma1 != SymbolData[symbolIndex].Dyn_MA1_Period) RefreshIndicator_MA1(symbolIndex);
         if(old_ma2 != SymbolData[symbolIndex].Dyn_MA2_Period) RefreshIndicator_MA2(symbolIndex);
         if(old_adx != SymbolData[symbolIndex].Dyn_ADX_Period) RefreshIndicator_ADX(symbolIndex);
         if(old_box != SymbolData[symbolIndex].Dyn_Box_Lookback) BackfillBoxHistory(symbolIndex);
      }
   }
}

//+------------------------------------------------------------------+
//| Write Active Trades for Slave's Orphan Checker                   |
//+------------------------------------------------------------------+
void WriteActiveTrades()
{
   string activeFile = "HedgeActive_" + InpHedgeChannel + ".bin";
   int hOut = FileOpen(activeFile, FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(hOut != INVALID_HANDLE)
   {
      ulong tickets[];
      int count = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(ticket))
         {
            if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            {
               if(SmartHedge_IsProtectedTicket(ticket))
                  continue;

               count++;
               ArrayResize(tickets, count);
               tickets[count-1] = ticket;
            }
         }
      }
      FileWriteInteger(hOut, count, INT_VALUE);
      if(count > 0) FileWriteArray(hOut, tickets);
      
      FileClose(hOut);
   }
}

//+------------------------------------------------------------------+
//| Disconnect Safety: Close Master if Slave dies (Universal Time)   |
//+------------------------------------------------------------------+
bool IsPlausibleBridgeHeartbeat(const ulong heartbeat)
{
   if(heartbeat == 0)
      return false;

   ulong now = (ulong)TimeGMT();
   const ulong earliestAllowed = 1577836800; // 2020-01-01 UTC
   const ulong futureTolerance = 86400;      // 1 day

   if(heartbeat < earliestAllowed)
      return false;
   if(heartbeat > (now + futureTolerance))
      return false;

   return true;
}

void CheckSlaveConnection()
{
   if(!IsBridgeRuntimeEnabled()) return;
   
   string slaveFile = GetSlaveFile(InpHedgeChannel);
   if(FileIsExist(slaveFile, FILE_COMMON))
   {
       int h = FileOpenRobust(slaveFile, FILE_READ|FILE_BIN|FILE_COMMON);
       if(h != INVALID_HANDLE)
       {
           HedgeState sState;
           if(FileReadStruct(h, sState) > 0)
           {
               if(!IsPlausibleBridgeHeartbeat(sState.last_heartbeat))
               {
                  static datetime last_invalid_slave_state_log = 0;
                  if((last_invalid_slave_state_log == 0) || ((TimeCurrent() - last_invalid_slave_state_log) >= 600))
                  {
                     Print(EmojiWarning(), " Ignoring malformed slave heartbeat state. Waiting for slave to rewrite its bridge file.");
                     last_invalid_slave_state_log = TimeCurrent();
                  }
                  FileClose(h);
                  FileDelete(slaveFile, FILE_COMMON);
                  return;
               }

               ulong myTime = (ulong)TimeGMT();
               ulong diff = (myTime >= sState.last_heartbeat) ? (myTime - sState.last_heartbeat) : 0;

                              // If Slave hasn't updated in 30 seconds
               if(diff > 30 && sState.last_heartbeat > 0)
               {
                   static datetime last_slave_disconnect_log = 0;
                   if((last_slave_disconnect_log == 0) || ((TimeCurrent() - last_slave_disconnect_log) >= 600))
                   {
                      Print("⚠️ Slave heartbeat lost (diff: ", diff, "s). Closing master trades.");
                      last_slave_disconnect_log = TimeCurrent();
                   }
                   for(int i=0; i<ArraySize(SymbolData); i++) {
                       if(SymbolData[i].active) CloseAllGridPositions(i, "Slave Disconnected");
                   }
                   CloseAllGlobalPositions("Slave Disconnected");
               }
           }
           FileClose(h);
       }
   }
}

//+------------------------------------------------------------------+
//| Sends a Proposal to the Slave and Locks the Master               |
//+------------------------------------------------------------------+
bool SendBridgeProposal(ulong mockTicket, double lots, int type, string sym, double riskMoney)
{
   if(G_HandshakePending) return false; // Block multiple requests

   BridgeProposal prop;
   ZeroMemory(prop);
   prop.ticket     = mockTicket; // A generated ID to track this proposal
   prop.lots       = lots;
   prop.type       = type;
   prop.action     = 10;         // 10 = Proposal Request
   prop.time_msc   = GetTickCount();
   prop.risk_money = riskMoney;
   StringToCharArray(sym, prop.symbol);

   string propFile = GetProposalFile(InpHedgeChannel);
   int h = FileOpenRobust(propFile, FILE_WRITE|FILE_BIN|FILE_COMMON);
   
   if(h != INVALID_HANDLE) 
   {
      FileWriteStruct(h, prop);
      FileClose(h);
      
      // Lock the Master
      G_HandshakePending = true;
      G_HandshakeStartTime = GetTickCount();
      G_PendingProposalTicket = mockTicket;
      
      Print("🛡️ Handshake sent for ", sym, ". Waiting for slave approval.");
      return true;
   }
   
   Print("⚠️ Could not write the handshake proposal file.");
   return false;
}

//+------------------------------------------------------------------+
//| Hide All Stops During Close Block                                |
//+------------------------------------------------------------------+
void HideAllStops()
{
    Print("🔒 Close block started: hiding broker SL/TP.");
    for(int i = PositionsTotal()-1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
            {
                double currentSL = PositionGetDouble(POSITION_SL);
                double currentTP = PositionGetDouble(POSITION_TP);
                if(currentSL != 0 || currentTP != 0)
                {
                    Trade.PositionModify(ticket, 0, 0); // Zero out SL/TP
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Restore All Stops After Close Block                              |
//+------------------------------------------------------------------+
void RestoreAllStops()
{
    Print("🔓 Close block ended: restoring broker SL/TP.");
    for(int i = 0; i < ArraySize(SymbolData); i++)
    {
        if(!SymbolData[i].active) continue;
        
        // 1. Grid/Zone Mode: Reapply Basket SL natively
        if(RiskMode == RISK_MODE_GRID || RiskMode == RISK_MODE_ZONE_RECOVERY)
        {
            if(SymbolData[i].GridPhase2Active)
            {
                UpdateAllGridStopLosses(i);
            }
        }
        // 2. Normal Mode: Reapply Master & Stack SL/TP
        else if(RiskMode == RISK_MODE_NONE)
        {
            string trackingSymbol = GetBaseSymbol(SymbolData[i].symbol);
            double restoreSL = SymbolData[i].MasterSL;
            double restoreTP = UseTrailing ? 0 : SymbolData[i].InitialTP;

            for(int p=PositionsTotal()-1; p>=0; p--)
            {
                ulong ticket = PositionGetTicket(p);
                if(PositionSelectByTicket(ticket))
                {
                   if(PositionGetString(POSITION_SYMBOL) == trackingSymbol && IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
                   {
                       string comment = PositionGetString(POSITION_COMMENT);
                       if(ticket == SymbolData[i].MasterTicket)
                       {
                           Trade.PositionModify(ticket, restoreSL, restoreTP);
                       }
                       else if(StringFind(comment, "Stack") >= 0)
                       {
                           Trade.PositionModify(ticket, restoreSL, 0); // Stacks inherit SL only
                       }
                   }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| NUCLEAR CLEANUP: Completely Delete Terminal Global Variables     |
//+------------------------------------------------------------------+
void WipeAllTerminalGlobalVariables()
  {
   int total = GlobalVariablesTotal();
   int deletedCount = 0;

   // List all prefixes your bot uses to store data
   string targetPrefixes[] = {
      "MBP_",                // Pruning/Critical Banks
      "Debt_",               // Legacy Banks
      "Hedge",               // Hedge state files/flags
      InpHedgeChannel,       // Master Hedge Limits (STOP_FLAG, PAUSE_FLAG, etc)
      "V3BridgeHeartbeat"    // Bridge Communications
   };

   // Loop BACKWARDS when deleting from the global terminal array
   for(int i = total - 1; i >= 0; i--)
     {
      string varName = GlobalVariableName(i);
      
      // Check if the variable contains any of our bot's prefixes
      for(int p = 0; p < ArraySize(targetPrefixes); p++)
        {
         if(StringFind(varName, targetPrefixes[p]) >= 0)
           {
            GlobalVariableDel(varName);
            deletedCount++;
            break; // Stop checking prefixes and move to the next variable
           }
        }
     }
   
   Print("🧹 Cleared ", deletedCount, " bot terminal global variables.");
  }
  
//+------------------------------------------------------------------+






#endif // __MULTIBOTPRO_HELPERS_MQH__

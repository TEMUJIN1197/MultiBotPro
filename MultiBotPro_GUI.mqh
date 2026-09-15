#ifndef __MULTIBOTPRO_GUI_MQH__
#define __MULTIBOTPRO_GUI_MQH__
//+------------------------------------------------------------------+
//|                                              MultiBotPro_GUI.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://discord.com/channels/929723953415589918/929723953415589920"

// --- MANUAL PANEL SCALING GLOBALS ---
double Panel_Scale = 1.0;
int    Panel_ManX  = 10;
int    Panel_ManY  = 330;

int S_Man(int value) { return (int)MathRound(value * Panel_Scale); }

//+------------------------------------------------------------------+
//| 1. DRAW MANUAL ENTRY PANEL (Dynamic Scale & Layering)            |
//+------------------------------------------------------------------+
void DrawManualEntryPanel()
  {
   // Remember position if it was dragged
   if(ObjectFind(0, "MAN_BG") >= 0) {
       Panel_ManX = (int)ObjectGetInteger(0, "MAN_BG", OBJPROP_XDISTANCE);
       Panel_ManY = (int)ObjectGetInteger(0, "MAN_BG", OBJPROP_YDISTANCE);
   }
   
   int x = Panel_ManX;
   int y = Panel_ManY;

// Background Panel
   if(ObjectFind(0, "MAN_BG") < 0)
      ObjectCreate(0, "MAN_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
      
   ObjectSetInteger(0, "MAN_BG", OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, "MAN_BG", OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, "MAN_BG", OBJPROP_XSIZE, S_Man(230));
   ObjectSetInteger(0, "MAN_BG", OBJPROP_YSIZE, S_Man(110));
   ObjectSetInteger(0, "MAN_BG", OBJPROP_BGCOLOR, clrBlack);
   ObjectSetInteger(0, "MAN_BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, "MAN_BG", OBJPROP_COLOR, clrDimGray);
   ObjectSetInteger(0, "MAN_BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ApplyPanelBackgroundLayer("MAN_BG");

// --- ROW 1: LOT SIZE ---
   CreateBtnObj(MAN_BTN_LOT_M, x + S_Man(10),  y + S_Man(10), S_Man(30), S_Man(25), "-", clrGray);
   
// Lot Display (ReadOnly Button)
   if(ObjectFind(0, MAN_EDIT_LOT) < 0)
      CreateBtnObj(MAN_EDIT_LOT, x + S_Man(45), y + S_Man(10), S_Man(60), S_Man(25), DoubleToString(Panel_ManualLot, 2), clrBlack);
   else {
      ObjectSetString(0, MAN_EDIT_LOT, OBJPROP_TEXT, DoubleToString(Panel_ManualLot, 2));
      ObjectSetInteger(0, MAN_EDIT_LOT, OBJPROP_XDISTANCE, x + S_Man(45));
      ObjectSetInteger(0, MAN_EDIT_LOT, OBJPROP_YDISTANCE, y + S_Man(10));
      ObjectSetInteger(0, MAN_EDIT_LOT, OBJPROP_XSIZE, S_Man(60));
      ObjectSetInteger(0, MAN_EDIT_LOT, OBJPROP_YSIZE, S_Man(25));
   }
   
   CreateBtnObj(MAN_BTN_LOT_P, x + S_Man(110), y + S_Man(10), S_Man(30), S_Man(25), "+", clrGray);
   CreateLabelObj("MAN_LBL_LOT", x + S_Man(145), y + S_Man(15), "Lots", clrWhite);

// --- SCALE BUTTONS (Top Right) ---
   CreateBtnObj("MAN_BTN_SCALE_M", x + S_Man(180), y + S_Man(10), S_Man(20), S_Man(20), "-", clrDarkGray);
   CreateBtnObj("MAN_BTN_SCALE_P", x + S_Man(202), y + S_Man(10), S_Man(20), S_Man(20), "+", clrDarkGray);

// --- ROW 2: BUY / SELL ---
   CreateBtnObj(MAN_BTN_BUY,  x + S_Man(10),  y + S_Man(45), S_Man(100), S_Man(30), "BUY", clrGreen);
   CreateBtnObj(MAN_BTN_SELL, x + S_Man(120), y + S_Man(45), S_Man(100), S_Man(30), "SELL", clrRed);

// --- ROW 3: PANIC CLOSE ---
   CreateBtnObj(MAN_BTN_CLOSE, x + S_Man(10), y + S_Man(80), S_Man(210), S_Man(20), "CLOSE ALL (PANIC)", clrMaroon);
  }

//+------------------------------------------------------------------+
//| 2. CHECK MANUAL ACTIONS (Polling OnTick with Debugging)          |
//+------------------------------------------------------------------+
void CheckManualEntryActions()
  {
  // --- SCALE PANEL ---
   if(ConsumeDashboardButtonState("MAN_BTN_SCALE_P"))
     {
      if(Panel_Scale < 2.5) Panel_Scale += 0.1;
      
      // Save pos and force full redraw by deleting objects
      Panel_ManX = (int)ObjectGetInteger(0, "MAN_BG", OBJPROP_XDISTANCE);
      Panel_ManY = (int)ObjectGetInteger(0, "MAN_BG", OBJPROP_YDISTANCE);
      ObjectsDeleteAll(0, "MAN_"); 
      
      DrawManualEntryPanel();
      ChartRedraw();
     }
     
   if(ConsumeDashboardButtonState("MAN_BTN_SCALE_M"))
     {
      if(Panel_Scale > 0.5) Panel_Scale -= 0.1;
      
      Panel_ManX = (int)ObjectGetInteger(0, "MAN_BG", OBJPROP_XDISTANCE);
      Panel_ManY = (int)ObjectGetInteger(0, "MAN_BG", OBJPROP_YDISTANCE);
      ObjectsDeleteAll(0, "MAN_"); 
      
      DrawManualEntryPanel();
      ChartRedraw();
     }
     
// --- LOT SIZE ---
   if(ConsumeDashboardButtonState(MAN_BTN_LOT_P))
     {
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP); // Use _Symbol for safety in tester
      Panel_ManualLot += step;
      Panel_ManualLot = NormalizeDouble(Panel_ManualLot, 2);
      if(ObjectFind(0, MAN_EDIT_LOT) >= 0)
         ObjectSetString(0, MAN_EDIT_LOT, OBJPROP_TEXT, DoubleToString(Panel_ManualLot, 2));
      ChartRedraw();
     }

   if(ConsumeDashboardButtonState(MAN_BTN_LOT_M))
     {
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double min  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      Panel_ManualLot -= step;
      if(Panel_ManualLot < min)
         Panel_ManualLot = min;
      Panel_ManualLot = NormalizeDouble(Panel_ManualLot, 2);
      if(ObjectFind(0, MAN_EDIT_LOT) >= 0)
         ObjectSetString(0, MAN_EDIT_LOT, OBJPROP_TEXT, DoubleToString(Panel_ManualLot, 2));
      ChartRedraw();
     }

// --- TRADING ---
// 1. Determine correct symbol index for execution
   int idx = -1;

// A. Try RealSymbol (from Global)
   if(RealSymbol != "")
      idx = GetSymbolIndex(RealSymbol);

// B. Fallback to Chart Symbol (Robust for Strategy Tester)
   if(idx == -1)
      idx = GetSymbolIndex(_Symbol);

// C. Emergency Fallback (If array populated but names mismatch)
   if(idx == -1 && ArraySize(SymbolData) > 0)
      idx = 0;

   bool buyPressed  = ConsumeDashboardButtonState(MAN_BTN_BUY);
   bool sellPressed = ConsumeDashboardButtonState(MAN_BTN_SELL);
   bool closePressed = ConsumeDashboardButtonState(MAN_BTN_CLOSE);

   if(idx >= 0)
     {
      // --- BUY ---
      if(buyPressed)
        {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(">>> MANUAL BUY BUTTON CLICKED for Index ", idx, " (", SymbolData[idx].symbol, ")");

         // Force Open
         OpenTrade(idx, ORDER_TYPE_BUY, Panel_ManualLot, false, true);
         ChartRedraw();
        }

      // --- SELL ---
      if(sellPressed)
        {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print(">>> MANUAL SELL BUTTON CLICKED for Index ", idx, " (", SymbolData[idx].symbol, ")");

         // Force Open
         OpenTrade(idx, ORDER_TYPE_SELL, Panel_ManualLot, false, true);
         ChartRedraw();
        }

      // --- CLOSE ALL ---
      if(closePressed)
        {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print(">>> MANUAL PANIC CLOSE CLICKED");
         CloseAllGlobalPositions("Manual Button");
         CloseAllGridPositions(idx, "Manual Button");
         ResetGridTracking(idx);
         ChartRedraw();
        }
     }
   else
     {
      // Debug if index fails (should not happen in Tester with fallback)
      if(buyPressed || sellPressed)
        {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print("Error: Could not find valid Symbol Index for Manual Trade.");
        }
     }
  }

//+------------------------------------------------------------------+
//| MANAGE TRADE LIST (Display Open Trades for ALL Symbols)          |
//+------------------------------------------------------------------+
void ManageTradeListMode()
  {
// 1. VISIBILITY CHECK
   if(!ShowTradeList)
     {
      // Ensure UI is clean
      ObjectsDeleteAll(0, BTN_PREFIX_LIST);
      return;
     }

// DYNAMIC START POSITION (Attached to bottom of dashboard)
   int startY = GetDashboardBottomY() + 5;
   int rowHeight = 25;
   int count = 0;

// 2. Loop and Draw Rows
   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         // --- FIX: Filter by app magic instead of chart symbol ---
         if(IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
           {
            string btnInfo  = BTN_PREFIX_LIST + "INFO_" + (string)ticket;
            string btnClose = BTN_PREFIX_LIST + "CLOSE_" + (string)ticket;
            string btnEdit  = BTN_PREFIX_LIST + "EDIT_" + (string)ticket;
            int y = startY + (count * rowHeight);

            // --- CLICK CHECKS (Polled cleanly during Strategy Tester OnTick) ---
            if(ConsumeDashboardButtonState(btnClose))
              {
               Trade.PositionClose(ticket);
               ObjectDelete(0, btnInfo);
               ObjectDelete(0, btnClose);
               ObjectDelete(0, btnEdit);
               return; // Exit immediately to prevent array index shifting errors
              }

            if(ConsumeDashboardButtonState(btnEdit))
              {
               Panel_SelectedTicket = ticket;
               Panel_IsModifying = true;

               // Initialize Modification Lines
               double sl = PositionGetDouble(POSITION_SL);
               double tp = PositionGetDouble(POSITION_TP);
               double pr = PositionGetDouble(POSITION_PRICE_OPEN);
               if(sl == 0) sl = pr;
               if(tp == 0) tp = pr;

               CreateLineObj(MP_HL_SL, sl, clrRed);
               CreateLineObj(MP_HL_TP, tp, clrLime);

               ObjectsDeleteAll(0, BTN_PREFIX_LIST);
               return;
              }

            // --- DRAWING THE LIST BUTTON ---
            string type = (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY) ? "BUY" : "SELL";
            double profit = PositionGetDouble(POSITION_PROFIT);
            
            // NEW: Get the actual symbol to display on the button
            string tradeSymbol = PositionGetString(POSITION_SYMBOL); 
            
            // Format: EURUSD BUY 0.10 ($15.50)
            string infoText = tradeSymbol + " " + type + " " + DoubleToString(PositionGetDouble(POSITION_VOLUME), 2) + " ($" + DoubleToString(profit, 2) + ")";
            color bg = (profit >= 0) ? clrDarkGreen : clrMaroon;

            int xBase = DashboardX;
            CreateBtnObj(btnInfo, xBase, y, 160, 20, infoText, bg);
            CreateBtnObj(btnClose, xBase + 165, y, 25, 20, "X", clrRed);
            CreateBtnObj(btnEdit, xBase + 195, y, 35, 20, "EDIT", clrOrange);

            count++;
           }
        }
     }

   CleanupGhostButtons(count, BTN_PREFIX_LIST);
  }

//+------------------------------------------------------------------+
//| Show News Details                                                |
//+------------------------------------------------------------------+
void ShowNewsDetails(string objName)
  {
   string idStr = StringSubstr(objName, StringLen("NewsLine_"));
   ulong valueID = StringToInteger(idStr);

   MqlCalendarValue value;
   MqlCalendarEvent event;

// Lookup the REAL data using the ID embedded in the object name
   if(CalendarValueById(valueID, value))
     {
      if(CalendarEventById(value.event_id, event))
        {
         string priority = "None";
         if(event.importance == CALENDAR_IMPORTANCE_HIGH)
            priority = "High";
         else
            if(event.importance == CALENDAR_IMPORTANCE_MODERATE)
               priority = "Moderate";
            else
               if(event.importance == CALENDAR_IMPORTANCE_LOW)
                  priority = "Low";
         if(event.type == CALENDAR_TYPE_HOLIDAY)
            priority = "Holiday";

         string currency = "ALL";
         MqlCalendarCountry country;
         if(CalendarCountryById(event.country_id, country))
            currency = country.currency;

         // This gets the REAL 2025 time from the database
         string timeStr = TimeToString(value.time, TIME_DATE|TIME_MINUTES);

         string dataStr = "";
         if(value.actual_value != -9223372036854775808)
            dataStr += "\nActual: " + DoubleToString(value.actual_value, 2);
         if(value.forecast_value != -9223372036854775808)
            dataStr += "\nForecast: " + DoubleToString(value.forecast_value, 2);

         string text = "Event: " + event.name + "\n" +
                       "Real Time: " + timeStr + "\n" +
                       "Priority: " + priority + "\n" +
                       "Currency: " + currency +
                       dataStr;

         MessageBox(text, "News Detail", MB_OK|MB_ICONINFORMATION);
        }
     }
  }

//+------------------------------------------------------------------+
//| OPTIMIZED EVENT HANDLER: Sync Panel Objects                      |
//+------------------------------------------------------------------+
void OnPanelDrag(string sparam)
{
   // 1. Filter: Only react if the Background ("MAN_BG") is being dragged
   if(sparam != "MAN_BG") return;

   // 2. Get New Background Coordinates
   long bgX = ObjectGetInteger(0, "MAN_BG", OBJPROP_XDISTANCE);
   long bgY = ObjectGetInteger(0, "MAN_BG", OBJPROP_YDISTANCE);

   // 3. Batch Update Child Objects (Relative Scaled Offsets)
   
   // --- Row 1: Lot Size & Scale Buttons ---
   ObjectSetInteger(0, MAN_BTN_LOT_M, OBJPROP_XDISTANCE, bgX + S_Man(10));
   ObjectSetInteger(0, MAN_BTN_LOT_M, OBJPROP_YDISTANCE, bgY + S_Man(10));
   
   ObjectSetInteger(0, MAN_EDIT_LOT,  OBJPROP_XDISTANCE, bgX + S_Man(45));
   ObjectSetInteger(0, MAN_EDIT_LOT,  OBJPROP_YDISTANCE, bgY + S_Man(10));
   
   ObjectSetInteger(0, MAN_BTN_LOT_P, OBJPROP_XDISTANCE, bgX + S_Man(110));
   ObjectSetInteger(0, MAN_BTN_LOT_P, OBJPROP_YDISTANCE, bgY + S_Man(10));
   
   ObjectSetInteger(0, "MAN_LBL_LOT", OBJPROP_XDISTANCE, bgX + S_Man(145));
   ObjectSetInteger(0, "MAN_LBL_LOT", OBJPROP_YDISTANCE, bgY + S_Man(15));
   
   ObjectSetInteger(0, "MAN_BTN_SCALE_M", OBJPROP_XDISTANCE, bgX + S_Man(180));
   ObjectSetInteger(0, "MAN_BTN_SCALE_M", OBJPROP_YDISTANCE, bgY + S_Man(10));
   ObjectSetInteger(0, "MAN_BTN_SCALE_P", OBJPROP_XDISTANCE, bgX + S_Man(202));
   ObjectSetInteger(0, "MAN_BTN_SCALE_P", OBJPROP_YDISTANCE, bgY + S_Man(10));

   // --- Row 2: Buy/Sell ---
   ObjectSetInteger(0, MAN_BTN_BUY,   OBJPROP_XDISTANCE, bgX + S_Man(10));
   ObjectSetInteger(0, MAN_BTN_BUY,   OBJPROP_YDISTANCE, bgY + S_Man(45));
   
   ObjectSetInteger(0, MAN_BTN_SELL,  OBJPROP_XDISTANCE, bgX + S_Man(120));
   ObjectSetInteger(0, MAN_BTN_SELL,  OBJPROP_YDISTANCE, bgY + S_Man(45));

   // --- Row 3: Close ---
   ObjectSetInteger(0, MAN_BTN_CLOSE, OBJPROP_XDISTANCE, bgX + S_Man(10));
   ObjectSetInteger(0, MAN_BTN_CLOSE, OBJPROP_YDISTANCE, bgY + S_Man(80));

   // 4. Force Redraw
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
#endif // __MULTIBOTPRO_GUI_MQH__


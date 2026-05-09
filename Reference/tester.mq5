//+------------------------------------------------------------------+
//|                                                   Tester Pro Mod |
//|                                      Copyright 2020, CompanyName |
//|                                       http://www.companyname.net |
//+------------------------------------------------------------------+
#property copyright "Copyright 2020, CompanyName"
#property link      "http://www.companyname.net"
#property version   "1.01"

#define BTN_BUY "BTN BUY"
#define BTN_SELL "BTN SELL"
#define BTN_CLOSE "BTN CLOSE"
#define BTN_LOT "BTN LOT"
#define BTN_P "BTN P"
#define BTN_M "BTN M"

#define BTN_SL1M "BTN SL 1M"
#define BTN_SL2M "BTN SL 2M"
#define BTN_SL1P "BTN SL 1P"
#define BTN_SL2P "BTN SL 2P"
#define BTN_SL "BTN SL"
#define BTN_TP "BTN TP"
#define HL_SL "HL SL"
#define HL_TP "HL TP"
#define BTN_TP1M "BTN TP 1M"
#define BTN_TP2M "BTN TP 2M"
#define BTN_TP1P "BTN TP 1P"
#define BTN_TP2P "BTN TP 2P"
#define BTN_YES "BTN YES"
#define BTN_NO "BTN NO"
#define BTN_IDLE "BTN IDLE"

// Prefix for dynamic buttons
#define PREFIX_TRADE_BTN "TRD_BTN_" 

#include <Trade/Trade.mqh>
CTrade obj_Trade;

// Logic Flags
bool tradeInAction = false;
bool isHaveTradeLevels = false;
bool isModifying = false;      // New flag: Are we editing an existing trade?
ulong selectedTicket = 0;      // New var: Which ticket are we editing?

input int sl_tp = 300;
input double init_lot = 0.03;
input int slow_pts = 10;
input int fast_pts = 100;

// Helper Functions
int GetState(string Name) {return (int)ObjectGetInteger(0, Name, OBJPROP_STATE);}
string GetValue(string Name) {return ObjectGetString(0, Name, OBJPROP_TEXT);}
double GetValueHL(string Name) {return NormalizeDouble(ObjectGetDouble(0, Name, OBJPROP_PRICE), _Digits);}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   createBtn(BTN_P, 150, 45, 40, 25, CharToString(217), 15, clrBlack, clrWhite, clrGray, "Wingdings");
   createBtn(BTN_LOT, 190, 45, 60, 25, string(init_lot), 12, clrWhite, clrNONE, clrWhite);
   createBtn(BTN_M, 250, 45, 40, 25, CharToString(218), 15, clrBlack, clrWhite, clrGray, "Wingdings");
   createBtn(BTN_BUY, 110, 70, 110, 30, "BUY", 15, clrWhite, clrGreen, clrWhite);
   createBtn(BTN_SELL, 220, 70, 110, 30, "SELL", 15, clrWhite, clrRed, clrWhite);
   createBtn(BTN_CLOSE, 110, 100, 220, 30, "PANIC BUTTON (X)", 15, clrWhite, clrBlack, clrWhite);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Manage Dynamic Buttons for Open Trades
   ManageTradeButtons();

   // 2. Main Logic: If User clicked Buy/Sell OR is in Modification Mode
   if(GetState(BTN_BUY) || GetState(BTN_SELL) || isModifying)
   {
      tradeInAction = true;

      // Create Lines if they don't exist
      if(!isHaveTradeLevels)
      {
         // If modifying, pass the existing ticket values, else use 0 defaults
         if(isModifying) 
            createModificationLevels(selectedTicket);
         else 
            createTradeLevels();
            
         isHaveTradeLevels = true;
      }

      if(tradeInAction)
      {
         // --- SL ADJUSTMENT LOGIC ---
         if(GetState(BTN_SL1M)) AdjustLine(HL_SL, -slow_pts, BTN_SL, "SL", BTN_SL1M);
         if(GetState(BTN_SL2M)) AdjustLine(HL_SL, -fast_pts, BTN_SL, "SL", BTN_SL2M);
         if(GetState(BTN_SL1P)) AdjustLine(HL_SL, slow_pts, BTN_SL, "SL", BTN_SL1P);
         if(GetState(BTN_SL2P)) AdjustLine(HL_SL, fast_pts, BTN_SL, "SL", BTN_SL2P);

         // --- TP ADJUSTMENT LOGIC ---
         if(GetState(BTN_TP1M)) AdjustLine(HL_TP, -slow_pts, BTN_TP, "TP", BTN_TP1M);
         if(GetState(BTN_TP2M)) AdjustLine(HL_TP, -fast_pts, BTN_TP, "TP", BTN_TP2M);
         if(GetState(BTN_TP1P)) AdjustLine(HL_TP, slow_pts, BTN_TP, "TP", BTN_TP1P);
         if(GetState(BTN_TP2P)) AdjustLine(HL_TP, fast_pts, BTN_TP, "TP", BTN_TP2P);

         // --- EXECUTION LOGIC (YES BUTTON) ---
         if(GetState(BTN_YES))
         {
            if(isModifying)
            {
               // MODIFY EXISTING TRADE
               double newSL = GetValueHL(HL_SL);
               double newTP = GetValueHL(HL_TP);
               obj_Trade.PositionModify(selectedTicket, newSL, newTP);
               ResetUI();
            }
            else 
            {
               // OPEN NEW TRADE
               if(GetState(BTN_BUY))
               {
                  obj_Trade.Buy(double(GetValue(BTN_LOT)), _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_ASK), GetValueHL(HL_SL), GetValueHL(HL_TP));
                  ResetUI();
               }
               else if(GetState(BTN_SELL))
               {
                  obj_Trade.Sell(double(GetValue(BTN_LOT)), _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_BID), GetValueHL(HL_SL), GetValueHL(HL_TP));
                  ResetUI();
               }
            }
         }

         // --- CANCEL LOGIC (NO BUTTON) ---
         if(GetState(BTN_NO))
         {
            ResetUI();
         }
      }
   }
   
   // --- LOT SIZE ADJUSTMENT LOGIC (Existing code cleaned up) ---
   HandleLotButtons();

   // --- PANIC CLOSE LOGIC ---
   if(GetState(BTN_CLOSE))
   {
      closeAllPositions();
      ObjectSetInteger(0, BTN_CLOSE, OBJPROP_STATE, false);
      ChartRedraw(0);
   }
}

//+------------------------------------------------------------------+
//| Refactored: Adjust Line Helper                                   |
//+------------------------------------------------------------------+
void AdjustLine(string lineObj, int points, string labelObj, string prefix, string btnObj)
{
   double currentPrice = GetValueHL(lineObj);
   // If line is at 0 (undefined), set it to current price first
   if (currentPrice == 0) currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   ObjectSetDouble(0, lineObj, OBJPROP_PRICE, currentPrice + points * _Point);
   ObjectSetString(0, labelObj, OBJPROP_TEXT, prefix + ": " + string(GetValueHL(lineObj)));
   ObjectSetInteger(0, btnObj, OBJPROP_STATE, false);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Reset UI State                                                   |
//+------------------------------------------------------------------+
void ResetUI()
{
   DeleteObjects_SLTP();
   isHaveTradeLevels = false;
   tradeInAction = false;
   isModifying = false;
   selectedTicket = 0;
   ObjectSetInteger(0, BTN_YES, OBJPROP_STATE, false);
   ObjectSetInteger(0, BTN_BUY, OBJPROP_STATE, false);
   ObjectSetInteger(0, BTN_SELL, OBJPROP_STATE, false);
   ObjectSetInteger(0, BTN_NO, OBJPROP_STATE, false);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Manage Trade Buttons (Create/Delete based on open positions)     |
//+------------------------------------------------------------------+
void ManageTradeButtons()
{
   // 1. Loop through positions and create/update buttons
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetString(POSITION_SYMBOL) == _Symbol)
      {
         string btnInfo = PREFIX_TRADE_BTN + "INFO_" + (string)ticket;
         string btnClose = PREFIX_TRADE_BTN + "CLOSE_" + (string)ticket;
         string btnEdit = PREFIX_TRADE_BTN + "EDIT_" + (string)ticket;
         
         int yPos = 140 + (i * 30); // Dynamic Y position
         
         // Info Button (Type + Profit)
         string type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? "BUY" : "SELL";
         double profit = PositionGetDouble(POSITION_PROFIT);
         string text = string(ticket) + " " + type + " " + DoubleToString(profit, 2);
         color bg = (profit >= 0) ? clrGreen : clrRed;
         
         if(ObjectFind(0, btnInfo) < 0) createBtn(btnInfo, 110, yPos, 140, 25, text, 10, clrWhite, bg, clrWhite);
         else {
             ObjectSetString(0, btnInfo, OBJPROP_TEXT, text); // Update profit in real time
             ObjectSetInteger(0, btnInfo, OBJPROP_BGCOLOR, bg);
             ObjectSetInteger(0, btnInfo, OBJPROP_YDISTANCE, yPos); // Update position if list shrinks
         }

         // Close Button [X]
         if(ObjectFind(0, btnClose) < 0) createBtn(btnClose, 255, yPos, 35, 25, "X", 10, clrWhite, clrRed, clrWhite);
         else ObjectSetInteger(0, btnClose, OBJPROP_YDISTANCE, yPos);

         // Edit Button [E]
         if(ObjectFind(0, btnEdit) < 0) createBtn(btnEdit, 295, yPos, 35, 25, "Edit", 9, clrBlack, clrYellow, clrWhite);
         else ObjectSetInteger(0, btnEdit, OBJPROP_YDISTANCE, yPos);

         // --- Handle Clicks for these buttons ---
         
         // Click Close
         if(GetState(btnClose))
         {
            obj_Trade.PositionClose(ticket);
            ObjectSetInteger(0, btnClose, OBJPROP_STATE, false);
            // Objects will be cleaned up in next tick's cleanup loop
         }
         
         // Click Edit
         if(GetState(btnEdit))
         {
            // If we are already doing something, reset first
            if(tradeInAction) ResetUI();
            
            selectedTicket = ticket;
            isModifying = true;
            tradeInAction = true; // Trigger the main loop
            ObjectSetInteger(0, btnEdit, OBJPROP_STATE, false); // Reset button state
         }
      }
   }

   // 2. Cleanup "Ghost" buttons (trades that closed)
   // We scan all objects. If it's a trade button but the ticket no longer exists, delete it.
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, PREFIX_TRADE_BTN) >= 0)
      {
         // Extract ticket from name
         string parts[];
         StringSplit(name, '_', parts);
         ulong ticketObj = (ulong)StringToInteger(parts[ArraySize(parts)-1]);
         
         if(!PositionSelectByTicket(ticketObj)) // Trade no longer exists
         {
            ObjectDelete(0, name);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Prepare Modification Levels (Existing SL/TP)                     |
//+------------------------------------------------------------------+
void createModificationLevels(ulong ticket)
{
   if(PositionSelectByTicket(ticket))
   {
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double price = PositionGetDouble(POSITION_PRICE_OPEN);
      
      // If SL/TP are 0, initialize them somewhere visual but safe (e.g. 500 points away) or at entry
      if(sl == 0) sl = price; 
      if(tp == 0) tp = price;

      createHL(HL_SL, 0, sl, clrRed);
      createHL(HL_TP, 0, tp, clrLime);

      createCommonButtons();
   }
}

//+------------------------------------------------------------------+
//| Standard Trade Levels (New Trade)                                |
//+------------------------------------------------------------------+
void createTradeLevels()
{
   double Ask = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
   double Bid = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);

   string level_Sl, level_TP;
   
   if(GetState(BTN_BUY))
   {
      level_Sl = string(Bid - sl_tp * _Point);
      level_TP = string(Bid + sl_tp * _Point);
   }
   else if(GetState(BTN_SELL))
   {
      level_Sl = string(Ask + sl_tp * _Point);
      level_TP = string(Ask - sl_tp * _Point);
   }
   
   createHL(HL_SL, 0, double(level_Sl), clrRed);
   createHL(HL_TP, 0, double(level_TP), clrLime);

   createCommonButtons();
}

//+------------------------------------------------------------------+
//| Create the +/- Buttons (Shared by New and Mod)                   |
//+------------------------------------------------------------------+
void createCommonButtons()
{
   createBtn(BTN_SL, 110, 135, 110, 23, "SL: " + string(GetValueHL(HL_SL)), 13, clrRed, clrWhite, clrRed);
   createBtn(BTN_TP, 220, 135, 110, 23, "TP: " + string(GetValueHL(HL_TP)), 13, clrGreen, clrWhite, clrGreen);

   createBtn(BTN_SL1M, 110, 158, 27, 20, "-", 17, clrBlack, clrWhite, clrGray);
   createBtn(BTN_SL2M, 137, 158, 27, 20, "--", 17, clrBlack, clrWhite, clrGray);
   createBtn(BTN_SL2P, 164, 158, 27, 20, "++", 17, clrBlack, clrWhite, clrGray);
   createBtn(BTN_SL1P, 191, 158, 27, 20, "+", 17, clrBlack, clrWhite, clrGray);

   createBtn(BTN_TP1P, 222, 158, 27, 20, "+", 17, clrBlack, clrWhite, clrGray);
   createBtn(BTN_TP2P, 249, 158, 27, 20, "++", 17, clrBlack, clrWhite, clrGray);
   createBtn(BTN_TP2M, 276, 158, 27, 20, "--", 17, clrBlack, clrWhite, clrGray);
   createBtn(BTN_TP1M, 303, 158, 27, 20, "-", 17, clrBlack, clrWhite, clrGray);

   createBtn(BTN_YES, 110, 178, 70, 30, CharToString(254), 20, clrWhite, clrDarkGreen, clrWhite, "Wingdings");
   createBtn(BTN_NO, 260, 178, 70, 30, CharToString(253), 20, clrWhite, clrDarkRed, clrWhite, "Wingdings");
   createBtn(BTN_IDLE, 180, 183, 80, 25, CharToString(40), 20, clrWhite, clrBlack, clrWhite, "Wingdings");
}

//+------------------------------------------------------------------+
//| Refactored: Lot Button Logic                                     |
//+------------------------------------------------------------------+
void HandleLotButtons()
{
   if(GetState(BTN_P))
   {
      double newLot = (double)GetValue(BTN_LOT);
      double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      newLot += lotStep;
      newLot = NormalizeDouble(newLot, 2);
      ObjectSetString(0, BTN_LOT, OBJPROP_TEXT, string(newLot));
      ObjectSetInteger(0, BTN_P, OBJPROP_STATE, false);
      ChartRedraw(0);
   }
   if(GetState(BTN_M))
   {
      double newLot = (double)GetValue(BTN_LOT);
      double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      newLot -= lotStep;
      newLot = NormalizeDouble(newLot, 2);
      if(newLot < lotStep) newLot = lotStep;
      ObjectSetString(0, BTN_LOT, OBJPROP_TEXT, string(newLot));
      ObjectSetInteger(0, BTN_M, OBJPROP_STATE, false);
      ChartRedraw(0);
   }
}

//+------------------------------------------------------------------+
//| Original Button Creator                                          |
//+------------------------------------------------------------------+
void createBtn(string objName, int xD, int yD, int xS, int yS, string txt, int fs = 13, color clrTxt = clrWhite, color clrBg = clrBlack, color clrBd = clrBlack, string font = "Calibri")
{
   if(ObjectFind(0, objName) < 0) ObjectCreate(0, objName, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, xD);
   ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, yD);
   ObjectSetInteger(0, objName, OBJPROP_XSIZE, xS);
   ObjectSetInteger(0, objName, OBJPROP_YSIZE, yS);
   ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetString(0, objName, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, fs);
   ObjectSetInteger(0, objName, OBJPROP_COLOR, clrTxt);
   ObjectSetInteger(0, objName, OBJPROP_BGCOLOR, clrBg);
   ObjectSetInteger(0, objName, OBJPROP_BORDER_COLOR, clrBd);
   ObjectSetString(0, objName, OBJPROP_FONT, font);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Original HL Creator                                              |
//+------------------------------------------------------------------+
void createHL(string objName, datetime time1, double price1, color clr)
{
   if(ObjectFind(0, objName) < 0)
   {
      ObjectCreate(0, objName, OBJ_HLINE, 0, time1, price1);
      ObjectSetInteger(0, objName, OBJPROP_TIME, time1);
      ObjectSetDouble(0, objName, OBJPROP_PRICE, price1);
      ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_DASHDOTDOT);
      ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, true); // Allow user to drag lines
      ChartRedraw(0);
   }
}

//+------------------------------------------------------------------+
//| Original Cleanup                                                 |
//+------------------------------------------------------------------+
void DeleteObjects_SLTP()
{
   ObjectDelete(0, HL_SL);
   ObjectDelete(0, HL_TP);
   ObjectDelete(0, BTN_SL);
   ObjectDelete(0, BTN_TP);
   ObjectDelete(0, BTN_SL1M);
   ObjectDelete(0, BTN_SL2M);
   ObjectDelete(0, BTN_SL1P);
   ObjectDelete(0, BTN_SL2P);
   ObjectDelete(0, BTN_TP1M);
   ObjectDelete(0, BTN_TP2M);
   ObjectDelete(0, BTN_TP1P);
   ObjectDelete(0, BTN_TP2P);
   ObjectDelete(0, BTN_YES);
   ObjectDelete(0, BTN_NO);
   ObjectDelete(0, BTN_IDLE);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Original Close All                                               |
//+------------------------------------------------------------------+
void closeAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket) && PositionGetString(POSITION_SYMBOL) == _Symbol)
      {
         obj_Trade.PositionClose(ticket);
      }
   }
}
//+------------------------------------------------------------------+
//|                     RenkoBuilderPro_v2.mq5                       |
//|      "Gap Filler, Anti-Dash, Lite Version (No Bridge)"           |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Renko Builder Pro"
#property link      "https://discord.com"
#property version   "1.02" 
#property description "Renko Builder with Interactive Dashboard & Gap Protection"

//--- INCLUDES
#include <Trade\Trade.mqh>

//--- ENUMS
enum ENUM_START_MODE {
   MODE_DAYS_BACK, // Days Back
   MODE_FIXED_DATE // Fixed Date
};
enum ENUM_BLOCK_MODE { 
   BLOCK_MODE_POINTS, // Points
   BLOCK_MODE_PIPS, // Pips
   BLOCK_MODE_ATR_PERCENT // ATR %
};

//--- INPUTS
input group "0. Global Visuals"
input bool           InpEnableLineDrawing = false;
input group "1. Renko Settings"
input string         InpCustomNameTag     = "";
input ENUM_BLOCK_MODE InpBlockMode        = BLOCK_MODE_ATR_PERCENT;
input double         InpBlockSizeValue    = 2;
input bool           InpShowWicks         = false;
input group "1b. ATR Settings"
input ENUM_TIMEFRAMES InpATRTimeframe     = PERIOD_D1;
input int            InpATRPeriod         = 14;
input group "2. History & Repair"
input ENUM_START_MODE InpStartMode        = MODE_DAYS_BACK;
input int            InpHistoryDays       = 5;
input datetime       InpFixedStartDate    = D'2026.01.01 00:00:00';
input bool           InpForceRebuild      = true;
input group "3. Market Lines (Bid/Ask/Last)"
input bool           InpShowBid          = true;
input color          InpBidColor         = clrLightSlateGray;
input ENUM_LINE_STYLE InpBidStyle        = STYLE_SOLID;
input bool           InpShowAsk          = true;
input color          InpAskColor         = clrRed;
input ENUM_LINE_STYLE InpAskStyle        = STYLE_SOLID;
input bool           InpShowLast         = true;
input color          InpLastColor        = clrLightSlateGray;
input ENUM_LINE_STYLE InpLastStyle       = STYLE_SOLID;
input group "4. Active Trade Lines"
input bool           InpShowEntry        = true;
input color          InpEntryColor       = clrLime;
input ENUM_LINE_STYLE InpEntryStyle      = STYLE_DOT;
input bool           InpShowSL           = true;
input color          InpSLColor          = clrRed;
input ENUM_LINE_STYLE InpSLStyle         = STYLE_DASHDOT;
input bool           InpShowTP           = true;
input color          InpTPColor          = clrGreen;
input ENUM_LINE_STYLE InpTPStyle         = STYLE_DASHDOT;
input group "5. History Lines"
input bool           InpShowHistory      = true;
input color          InpHistWinColor     = clrBlue;
input color          InpHistLossColor    = clrRed;
input ENUM_LINE_STYLE InpHistStyle       = STYLE_DOT;

//--- GLOBALS
CTrade   Trade;
string   UnderlyingSymbol = ""; 
string   CustomSymbol;
string   GV_Prefix;
double   RenkoAnchorPrice = 0;
double   RenkoBoxHigh = 0;
double   RenkoBoxLow = 0;
bool     IsTrendUp = true;
datetime LastCommittedBarTime = 0;
double   CurrentBlockSizePoint = 0;
long     RenkoChartID = 0;
int      ATR_Handle = INVALID_HANDLE;
bool     isInitialized = false;
long     TickVolBuffer = 0;

// --- NEW RAM BUFFERS (The "Cache") ---
MqlRates g_RamRateBuffer[];
MqlTick  g_RamTickBuffer[];
ulong    g_LastFlushTime = 0;
// -------------------------------------

//--- TRACKERS
double   g_LastClosePrice = 0; // Fixes Gaps
int      g_LastHistoryDeals = -1;
datetime g_LastTradeTime    = 0;
bool     g_LinesCleared     = false;
double   g_CachedATR = 0;
datetime g_LastATRTime = 0;
int      g_LastPosCount = 0;

//+------------------------------------------------------------------+
//| CLASS: INTERACTIVE DASHBOARD (Bridge Removed)                    |
//+------------------------------------------------------------------+
class CRenkoGUI
{
private:
   string   m_prefix;
   int      m_x, m_y;
   int      m_w, m_h;
   bool     m_minimized;
   bool     m_dragging;
   int      m_drag_x, m_drag_y;
   
   color    c_bg, c_head, c_card, c_txt, c_lbl, c_warn;
public:
   CRenkoGUI() { 
      m_prefix="RenkoDash_"; m_x=20; m_y=20; m_w=260; 
      m_h=135; // Reduced Height since Bridge is gone
      m_minimized=false; m_dragging=false;
      c_bg = C'30,35,40'; c_head = C'40,80,160';
      c_card = C'40,45,50';
      c_txt = clrWhite;   c_lbl = C'180,180,180';
      c_warn = C'220,180,60';
   }
   ~CRenkoGUI() { Destroy(); }

   void Create() {
      Destroy();
      CreateRect("BG", m_w, m_h, c_bg, c_bg);
      CreateRect("Head", m_w, 25, c_head, c_head);
      CreateLabel("Title", "RENKO BUILDER LITE", 10, 5, 9, clrWhite, true);
      CreateBtn("Min", "_", m_w-25, 2, 20, 20);
      int y = 35;
      CreateLabel("L_Mode", "Block Mode:", 10, y, 8, c_lbl);
      CreateLabel("V_Mode", "--", 100, y, 8, c_txt); y+=15;
      CreateLabel("L_Size", "Input Size:", 10, y, 8, c_lbl);
      CreateLabel("V_Size", "--", 100, y, 8, c_txt); y+=15;

      CreateLabel("L_Hist", "History:", 10, y, 8, c_lbl);
      CreateLabel("V_Hist", "--", 100, y, 8, c_txt); y+=20; 
      
      CreateRect("Div1", m_w-20, 1, C'60,65,70', C'60,65,70', 10, y);
      y+=10;
      CreateLabel("L_Act", "Actual Size:", 10, y, 8, c_lbl);
      CreateLabel("V_Act", "--", 100, y, 8, c_warn, true); y+=15;
      CreateLabel("L_Anc", "Anchor:", 10, y, 8, c_lbl);
      CreateLabel("V_Anc", "--", 100, y, 8, c_txt);
      
      UpdatePos();
      ChartRedraw();
   }
   
   void Destroy() { ObjectsDeleteAll(0, m_prefix); }
   
   void OnEvent(int id, long lparam, double dparam, string sparam) {
       if(id == CHARTEVENT_OBJECT_CLICK && sparam == m_prefix+"Min") {
         m_minimized = !m_minimized;
         UpdatePos();
         ChartRedraw();
      }
      else if(id == CHARTEVENT_MOUSE_MOVE) {
         int x=(int)lparam;
         int y=(int)dparam; int state=(int)sparam;
         if(state==1) { 
            if(!m_dragging && x>=m_x && x<=m_x+m_w && y>=m_y && y<=m_y+25) {
               m_dragging=true;
               m_drag_x=x-m_x; m_drag_y=y-m_y;
               ChartSetInteger(0,CHART_MOUSE_SCROLL,false);
            }
            if(m_dragging) { m_x=x-m_drag_x; m_y=y-m_drag_y; if(m_x<0)m_x=0;
            if(m_y<0)m_y=0; UpdatePos(); ChartRedraw(); }
         } else {
            if(m_dragging) { m_dragging=false;
            ChartSetInteger(0,CHART_MOUSE_SCROLL,true); }
         }
      }
   }

   void Update(string mode, double inSize, double actSize, double anchor, string historyMsg) {
      if(m_minimized) return;
      SetText("V_Mode", mode);
      SetText("V_Size", DoubleToString(inSize, 2));
      SetText("V_Hist", historyMsg); 
      SetText("V_Act",  DoubleToString(actSize/_Point, 1)+" pts");
      SetText("V_Anc",  DoubleToString(anchor, _Digits));
      ChartRedraw();
   }

private:
   void UpdatePos() {
      int h = m_minimized ? 25 : m_h;
      SetGeom("BG", m_x, m_y, m_w, h);
      SetGeom("Head", m_x, m_y, m_w, 25);
      SetGeom("Title", m_x+10, m_y+5);
      SetGeom("Min", m_x+m_w-25, m_y+2);

      bool vis = !m_minimized;
      SetVis("L_Mode", vis); SetVis("V_Mode", vis); 
      SetVis("L_Size", vis); SetVis("V_Size", vis);
      SetVis("L_Hist", vis); SetVis("V_Hist", vis); 
      SetVis("Div1", vis);
      SetVis("L_Act", vis); SetVis("V_Act", vis); 
      SetVis("L_Anc", vis);
      SetVis("V_Anc", vis);

      if(vis) {
         int y = m_y + 35;
         SetGeom("L_Mode", m_x+10, y); SetGeom("V_Mode", m_x+100, y); y+=15;
         SetGeom("L_Size", m_x+10, y); SetGeom("V_Size", m_x+100, y); y+=15;
         SetGeom("L_Hist", m_x+10, y); SetGeom("V_Hist", m_x+100, y);
         y+=20; 
         SetGeom("Div1", m_x+10, y);
         y+=10;
         SetGeom("L_Act", m_x+10, y); SetGeom("V_Act", m_x+100, y); y+=15;
         SetGeom("L_Anc", m_x+10, y); SetGeom("V_Anc", m_x+100, y); 
      }
   }
   
   void CreateRect(string n, int w, int h, color bg, color bord, int dx=0, int dy=0) {
      string obj = m_prefix+n;
      if(ObjectFind(0,obj)<0) ObjectCreate(0,obj,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,obj,OBJPROP_XSIZE,w); ObjectSetInteger(0,obj,OBJPROP_YSIZE,h);
      ObjectSetInteger(0,obj,OBJPROP_BGCOLOR,bg); ObjectSetInteger(0,obj,OBJPROP_BORDER_COLOR,bord);
      ObjectSetInteger(0,obj,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,obj,OBJPROP_ZORDER,10);
      if(dx!=0||dy!=0) SetGeom(n, m_x+dx, m_y+dy);
   }
   void CreateLabel(string n, string txt, int dx, int dy, int sz, color c, bool bold=false) {
      string obj = m_prefix+n;
      if(ObjectFind(0,obj)<0) ObjectCreate(0,obj,OBJ_LABEL,0,0,0);
      ObjectSetString(0,obj,OBJPROP_TEXT,txt); ObjectSetInteger(0,obj,OBJPROP_FONTSIZE,sz);
      ObjectSetInteger(0,obj,OBJPROP_COLOR,c); ObjectSetString(0,obj,OBJPROP_FONT,bold?"Arial check":"Arial");
      ObjectSetInteger(0,obj,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,obj,OBJPROP_ZORDER,15);
      SetGeom(n, m_x+dx, m_y+dy);
   }
   void CreateBtn(string n, string txt, int dx, int dy, int w, int h) {
      string obj = m_prefix+n;
      if(ObjectFind(0,obj)<0) ObjectCreate(0,obj,OBJ_BUTTON,0,0,0);
      ObjectSetString(0,obj,OBJPROP_TEXT,txt); ObjectSetInteger(0,obj,OBJPROP_XSIZE,w); ObjectSetInteger(0,obj,OBJPROP_YSIZE,h);
      ObjectSetInteger(0,obj,OBJPROP_CORNER,CORNER_LEFT_UPPER); ObjectSetInteger(0,obj,OBJPROP_ZORDER,20);
      ObjectSetInteger(0,obj,OBJPROP_BGCOLOR,c_head); ObjectSetInteger(0,obj,OBJPROP_COLOR,c_txt);
      SetGeom(n, m_x+dx, m_y+dy);
   }
   void SetGeom(string n, int x, int y, int w=-1, int h=-1) {
      string obj = m_prefix+n;
      ObjectSetInteger(0,obj,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,obj,OBJPROP_YDISTANCE,y);
      if(w>0) ObjectSetInteger(0,obj,OBJPROP_XSIZE,w); if(h>0) ObjectSetInteger(0,obj,OBJPROP_YSIZE,h);
   }
   void SetText(string n, string txt) { ObjectSetString(0,m_prefix+n,OBJPROP_TEXT,txt); }
   void SetVis(string n, bool v) { ObjectSetInteger(0,m_prefix+n,OBJPROP_TIMEFRAMES, v?OBJ_ALL_PERIODS:OBJ_NO_PERIODS); }
};

CRenkoGUI GUI;

//+------------------------------------------------------------------+
//| Helpers: Price & Block Calc                                      |
//+------------------------------------------------------------------+
double NormalizePrice(double price)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize == 0) return(NormalizeDouble(price, _Digits));
   return(MathRound(price / tickSize) * tickSize);
}

double GetPipSize()
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(digits == 3 || digits == 5) return point * 10;
   return point;
}

double CalculateBlockSize(datetime timeRef)
{
   double size = 0;
   
   if(InpBlockMode == BLOCK_MODE_ATR_PERCENT)
   {
      if(ATR_Handle == INVALID_HANDLE) return 100 * _Point;
      long atrPeriodSeconds = PeriodSeconds(InpATRTimeframe);
      datetime currentBarTime = (datetime)(timeRef - (timeRef % atrPeriodSeconds));

      if(currentBarTime > g_LastATRTime || g_CachedATR == 0) {
         double atrBuffer[];
         if(CopyBuffer(ATR_Handle, 0, 0, 1, atrBuffer) > 0) { 
             g_CachedATR = atrBuffer[0];
             g_LastATRTime = currentBarTime;
         }
      }
      
      double calculatedSize = g_CachedATR * (InpBlockSizeValue / 100.0);
      if(calculatedSize < _Point) calculatedSize = _Point;
      size = NormalizePrice(calculatedSize);
   }
   else if(InpBlockMode == BLOCK_MODE_POINTS) 
      size = InpBlockSizeValue * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   else if(InpBlockMode == BLOCK_MODE_PIPS)
      size = InpBlockSizeValue * GetPipSize();
   else 
      size = InpBlockSizeValue * _Point;

   return size;
}

//+------------------------------------------------------------------+
//| Helper: State Management                                         |
//+------------------------------------------------------------------+
void SaveState()
{
   GlobalVariableSet(GV_Prefix + "_Anchor", RenkoAnchorPrice);
   GlobalVariableSet(GV_Prefix + "_Trend", (double)IsTrendUp);
   GlobalVariableSet(GV_Prefix + "_LastTime", (double)LastCommittedBarTime);
   GlobalVariableSet(GV_Prefix + "_High", RenkoBoxHigh);
   GlobalVariableSet(GV_Prefix + "_Low", RenkoBoxLow);
   GlobalVariableSet(GV_Prefix + "_LastClose", g_LastClosePrice); // Save Close to prevent gaps
}

bool LoadState()
{
   if(!GlobalVariableCheck(GV_Prefix + "_Anchor")) return false;
   RenkoAnchorPrice     = GlobalVariableGet(GV_Prefix + "_Anchor");
   IsTrendUp            = (bool)GlobalVariableGet(GV_Prefix + "_Trend");
   LastCommittedBarTime = (datetime)GlobalVariableGet(GV_Prefix + "_LastTime");
   if(GlobalVariableCheck(GV_Prefix + "_High")) RenkoBoxHigh = GlobalVariableGet(GV_Prefix + "_High");
   if(GlobalVariableCheck(GV_Prefix + "_Low"))  RenkoBoxLow  = GlobalVariableGet(GV_Prefix + "_Low");
   if(GlobalVariableCheck(GV_Prefix + "_LastClose")) g_LastClosePrice = GlobalVariableGet(GV_Prefix + "_LastClose");
   else g_LastClosePrice = RenkoAnchorPrice;
   return true;
}

//+------------------------------------------------------------------+
//| Helper: Update Market Watch                                      |
//+------------------------------------------------------------------+
void UpdateMarketWatch()
{
   MqlTick tick;
   if(SymbolInfoTick(_Symbol, tick)) {
      CustomSymbolSetDouble(CustomSymbol, SYMBOL_BID, NormalizePrice(tick.bid));
      CustomSymbolSetDouble(CustomSymbol, SYMBOL_ASK, NormalizePrice(tick.ask));
      double last = (tick.last > 0) ? tick.last : tick.bid;
      CustomSymbolSetDouble(CustomSymbol, SYMBOL_LAST, NormalizePrice(last));
   }
}

//+------------------------------------------------------------------+
//| Renko Core Logic                                                 |
//+------------------------------------------------------------------+
datetime GetNextBarTime()
{
   if(MQLInfoInteger(MQL_TESTER))
   {
      if(LastCommittedBarTime == 0) return TimeCurrent();
      return LastCommittedBarTime + 60; 
   }
   datetime next = TimeCurrent();
   if(next <= LastCommittedBarTime) next = LastCommittedBarTime + 1;
   return next;
}

//+------------------------------------------------------------------+
//| FIX: Live Update logic handles phantom bars safely               |
//+------------------------------------------------------------------+
void UpdateLiveBlock(double currentPrice)
{
   if(LastCommittedBarTime == 0) return;
   
   static double lastWrittenPrice = 0;
   static ulong lastWriteTime = 0;
   
   // Throttle excessive updates
   if(MathAbs(currentPrice - lastWrittenPrice) < _Point * 0.1 && 
      GetMicrosecondCount() - lastWriteTime < 500000) return; // 0.5 sec throttle
      
   datetime liveBarTime = GetNextBarTime();
   
   // GAP FIX: Always start live bar from the last confirmed close
   double open = (g_LastClosePrice > 0) ? g_LastClosePrice : RenkoAnchorPrice;
   double close = NormalizePrice(currentPrice);

   if(MathAbs(open - close) < _Point) return;
   
   // IMPORTANT: Delete the specific phantom bar area before writing
   CustomRatesDelete(CustomSymbol, LastCommittedBarTime + 1, LONG_MAX);

   MqlRates rate[1];
   rate[0].time = liveBarTime;
   rate[0].open = open; 
   rate[0].close = close;
   if(InpShowWicks) {
      rate[0].high = MathMax(RenkoBoxHigh, MathMax(rate[0].open, rate[0].close));
      rate[0].low  = MathMin(RenkoBoxLow,  MathMin(rate[0].open, rate[0].close));
   } else {
      rate[0].high = MathMax(rate[0].open, rate[0].close);
      rate[0].low  = MathMin(rate[0].open, rate[0].close);
   }
   
   rate[0].tick_volume = (TickVolBuffer > 0) ? TickVolBuffer : 1;
   rate[0].spread = 0; 
   rate[0].real_volume = 0;
   
   CustomRatesUpdate(CustomSymbol, rate, 1);
   
   double realAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double realBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double currentSpread = realAsk - realBid;

   MqlTick renkoTick;
   renkoTick.time = liveBarTime;
   renkoTick.time_msc = (long)liveBarTime * 1000;
   renkoTick.bid = rate[0].close;
   renkoTick.ask = rate[0].close + currentSpread;
   renkoTick.flags = TICK_FLAG_BID | TICK_FLAG_ASK;
   
   MqlTick tickArray[1];
   tickArray[0] = renkoTick;
   CustomTicksAdd(CustomSymbol, tickArray);
   UpdateMarketWatch();
   lastWrittenPrice = currentPrice;
   lastWriteTime = GetMicrosecondCount();
}

//+------------------------------------------------------------------+
//| Optimized: Buffer bars in memory & ENFORCE CONTINUITY            |
//+------------------------------------------------------------------+
void PushRenkoBarBuffered(double open, double close, double boxHigh, double boxLow, datetime eventTime, long volume, 
                          MqlRates &resultRates[], MqlTick &resultTicks[])
{
   // 1. Time Synchronization Logic
   // We use the LastCommittedBarTime as a strict anchor to prevent gaps or overlaps
   if(LastCommittedBarTime == 0 && eventTime > 0) LastCommittedBarTime = eventTime - 60;
   
   datetime newBarTime;
   if(MQLInfoInteger(MQL_TESTER)) newBarTime = LastCommittedBarTime + 60;
   else {
      newBarTime = eventTime;
      // Force strict sequential time (at least +1 second from last bar)
      if(newBarTime <= LastCommittedBarTime) newBarTime = LastCommittedBarTime + 1;
   }
   
   LastCommittedBarTime = newBarTime;

   // 2. Resize Buffers
   int currentSize = ArraySize(resultRates);
   ArrayResize(resultRates, currentSize + 1);
   ArrayResize(resultTicks, currentSize + 1);
   
   // 3. Fill Rate Data
   resultRates[currentSize].time = newBarTime;
   
   // USER FIX: Strict Open/Close Levels
   // We trust the passed 'open' and 'close' values completely now (calculated in ProcessRenkoTick)
   // This allows the reversal bars to start from the specific "Open" level you requested.
   resultRates[currentSize].open  = NormalizePrice(open);
   resultRates[currentSize].close = NormalizePrice(close);
   
   // Update the global continuity tracker
   g_LastClosePrice = resultRates[currentSize].close;

   // 4. Wick Logic
   if(InpShowWicks) {
      resultRates[currentSize].high = MathMax(boxHigh, MathMax(resultRates[currentSize].open, resultRates[currentSize].close));
      resultRates[currentSize].low  = MathMin(boxLow,  MathMin(resultRates[currentSize].open, resultRates[currentSize].close));
   } else {
      resultRates[currentSize].high = MathMax(resultRates[currentSize].open, resultRates[currentSize].close);
      resultRates[currentSize].low  = MathMin(resultRates[currentSize].open, resultRates[currentSize].close);
   }

   resultRates[currentSize].tick_volume = (volume > 0) ? volume : 1; 
   resultRates[currentSize].spread = 0;
   resultRates[currentSize].real_volume = 0;
   
   // 5. Fill Tick Data (required for chart to tick)
   double realAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double realBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double currentSpread = realAsk - realBid;

   resultTicks[currentSize].time = newBarTime;
   resultTicks[currentSize].time_msc = (long)newBarTime * 1000;
   resultTicks[currentSize].bid = resultRates[currentSize].close;
   resultTicks[currentSize].ask = resultRates[currentSize].close + currentSpread;
   resultTicks[currentSize].flags = TICK_FLAG_BID | TICK_FLAG_ASK;
}

bool ProcessRenkoTick(double price, datetime tickTime, long tickVol)
{
   TickVolBuffer += tickVol;
   
   // Initial Anchor Setup
   if(RenkoAnchorPrice == 0) { 
      RenkoAnchorPrice = NormalizePrice(price);
      g_LastClosePrice = RenkoAnchorPrice; 
      RenkoBoxHigh = RenkoAnchorPrice;
      RenkoBoxLow = RenkoAnchorPrice;
      if(LastCommittedBarTime == 0) LastCommittedBarTime = (tickTime > 0) ? tickTime - 60 : TimeCurrent() - 60; 
      return false;
   }

   RenkoBoxHigh = MathMax(RenkoBoxHigh, price);
   RenkoBoxLow  = MathMin(RenkoBoxLow, price);

   CurrentBlockSizePoint = CalculateBlockSize(tickTime);
   double BS = CurrentBlockSizePoint;
   if(BS < _Point) BS = _Point;

   // --- OPTIMIZATION BUFFERS ---
   MqlRates newRates[];
   MqlTick  newTicks[];
   // ----------------------------

   int maxLoops = 1000; 
   int loopCount = 0;
   bool boxCreated = false;
   datetime cleanUpTimeStart = LastCommittedBarTime; // Track where to start deleting
   
   while(loopCount < maxLoops)
   {
      bool loopAction = false;
      loopCount++;
      
      // Calculate Targets
      double upTarget   = NormalizePrice(RenkoAnchorPrice + BS);
      double downTarget = NormalizePrice(RenkoAnchorPrice - BS);
      double revDownTarget = RenkoAnchorPrice - (2 * BS);
      double revUpTarget = RenkoAnchorPrice + (2 * BS);

      if(IsTrendUp) {
         // CONTINUATION (Up)
         if(price >= upTarget - (_Point/2)) {
            PushRenkoBarBuffered(RenkoAnchorPrice, upTarget, RenkoBoxHigh, RenkoBoxLow, tickTime, TickVolBuffer, newRates, newTicks);
            RenkoAnchorPrice = upTarget;
            loopAction = true;
         }
         // REVERSAL (Down)
         else if(price <= revDownTarget + (_Point/2)) {
            // USER REQUEST FIX: Start from Open, not Close.
            // Old Anchor was Top. Prev Open was (Anchor - BS).
            // We want the bar to be: Open = (Anchor - BS), Close = (Anchor - 2*BS).
            // This visually creates a 1-block size bar starting from the previous Open.
            
            double open  = NormalizePrice(RenkoAnchorPrice - BS); 
            double close = NormalizePrice(RenkoAnchorPrice - (2 * BS));
            
            PushRenkoBarBuffered(open, close, RenkoBoxHigh, RenkoBoxLow, tickTime, TickVolBuffer, newRates, newTicks);
            RenkoAnchorPrice = close; 
            IsTrendUp = false; // Trend Flip
            loopAction = true;
         }
      }
      else {
         // CONTINUATION (Down)
         if(price <= downTarget + (_Point/2)) {
            PushRenkoBarBuffered(RenkoAnchorPrice, downTarget, RenkoBoxHigh, RenkoBoxLow, tickTime, TickVolBuffer, newRates, newTicks);
            RenkoAnchorPrice = downTarget;
            loopAction = true;
         }
         // REVERSAL (Up)
         else if(price >= revUpTarget - (_Point/2)) {
            // USER REQUEST FIX: Start from Open.
            // Old Anchor was Bottom. Prev Open was (Anchor + BS).
            // We want bar: Open = (Anchor + BS), Close = (Anchor + 2*BS).
            
            double open  = NormalizePrice(RenkoAnchorPrice + BS);
            double close = NormalizePrice(RenkoAnchorPrice + (2 * BS));
            
            PushRenkoBarBuffered(open, close, RenkoBoxHigh, RenkoBoxLow, tickTime, TickVolBuffer, newRates, newTicks);
            RenkoAnchorPrice = close;            
            IsTrendUp = true; // Trend Flip
            loopAction = true;
         }
      }
        
      if(loopAction) {
         boxCreated = true;
         TickVolBuffer = 0;
         RenkoBoxHigh = RenkoAnchorPrice;
         RenkoBoxLow  = RenkoAnchorPrice;
      }
      else break;
   }

   // --- BATCH BUFFERING (RAM ONLY) ---
   int count = ArraySize(newRates);
   if(count > 0) {
       // 1. Move Local Data to Global RAM Cache
       int currentTotal = ArraySize(g_RamRateBuffer);
       ArrayResize(g_RamRateBuffer, currentTotal + count);
       ArrayResize(g_RamTickBuffer, currentTotal + count);
       
       // Efficient Memory Copy (Very Fast CPU operation)
       ArrayCopy(g_RamRateBuffer, newRates, currentTotal, 0, count);
       ArrayCopy(g_RamTickBuffer, newTicks, currentTotal, 0, count);
   }
   
   return boxCreated;
}

//+------------------------------------------------------------------+
//| Initialization & System                                          |
//+------------------------------------------------------------------+
bool BuildHistory()
{
   Print("Building Standard Renko History...");
   datetime start;
   if(InpStartMode == MODE_DAYS_BACK) start = TimeCurrent() - (InpHistoryDays * 86400);
   else start = InpFixedStartDate;
   if(start <= 0) start = D'2020.01.01';

   LastCommittedBarTime = start; 
   MqlRates src[];
   int total = CopyRates(_Symbol, PERIOD_M1, start, TimeCurrent(), src);
   if(total > 0) {
      RenkoAnchorPrice = NormalizePrice(src[0].open);
      g_LastClosePrice = RenkoAnchorPrice; // Init Continuity
      RenkoBoxHigh = RenkoAnchorPrice;
      RenkoBoxLow = RenkoAnchorPrice;
      IsTrendUp = (src[0].close > src[0].open);
      for(int i=0; i<total; i++) {
         if(src[i].time > TimeCurrent()) break;
         long volPart = src[i].tick_volume / 3;
         if(volPart < 1) volPart = 1;
         if(src[i].close > src[i].open) {
            ProcessRenkoTick(src[i].low, src[i].time, volPart);
            ProcessRenkoTick(src[i].high, src[i].time, volPart);
         } else {
            ProcessRenkoTick(src[i].high, src[i].time, volPart);
            ProcessRenkoTick(src[i].low, src[i].time, volPart);
         }
         ProcessRenkoTick(src[i].close, src[i].time, volPart);
      }
   }
   
   SaveState();
   if(RenkoChartID > 0) {
      ChartSetSymbolPeriod(RenkoChartID, CustomSymbol, PERIOD_M1);
      ChartRedraw(RenkoChartID);
   }
   Print("History Build Complete.");
   return true;
}

void ConnectHistoryToLive()
{
   datetime lookback = TimeCurrent() - 86400; 
   MqlRates src[];
   int total = CopyRates(_Symbol, PERIOD_M1, lookback, TimeCurrent(), src);
   if(total > 0) {
      Print("Connecting History to Live...");
      for(int i=0; i<total; i++) {
         if(src[i].time <= LastCommittedBarTime) continue;
         long volPart = src[i].tick_volume / 3; 
         if(volPart < 1) volPart = 1;
         if(src[i].close > src[i].open) {
            ProcessRenkoTick(src[i].low, src[i].time, volPart);
            ProcessRenkoTick(src[i].high, src[i].time, volPart);
         } else {
            ProcessRenkoTick(src[i].high, src[i].time, volPart);
            ProcessRenkoTick(src[i].low, src[i].time, volPart);
         }
         ProcessRenkoTick(src[i].close, src[i].time, volPart);
      }
   }
   
   MqlTick tick;
   if(SymbolInfoTick(_Symbol, tick)) {
      ProcessRenkoTick(tick.bid, TimeCurrent(), (long)tick.volume);
   }
}

int OnInit()
{
   string suffix = (InpCustomNameTag == "") ?
      ((InpBlockMode==BLOCK_MODE_ATR_PERCENT)?"_ATR":"_"+IntegerToString((int)InpBlockSizeValue)) : 
      "_"+InpCustomNameTag;
   CustomSymbol = _Symbol + suffix;
   UnderlyingSymbol = _Symbol;
   GV_Prefix = CustomSymbol;
   if(InpBlockMode == BLOCK_MODE_ATR_PERCENT) {
      ATR_Handle = iATR(_Symbol, InpATRTimeframe, InpATRPeriod);
      if(ATR_Handle == INVALID_HANDLE) return INIT_FAILED;
   }
   
   CurrentBlockSizePoint = CalculateBlockSize(TimeCurrent());
   
   bool doRebuild = InpForceRebuild;
   if(doRebuild) {
      if(SymbolInfoInteger(CustomSymbol, SYMBOL_CUSTOM)) CustomSymbolDelete(CustomSymbol);
   }

   if(!SymbolInfoInteger(CustomSymbol, SYMBOL_CUSTOM)) {
      CustomSymbolCreate(CustomSymbol, "RenkoPro_v1", _Symbol);
      doRebuild = true;
   }
   
   CustomSymbolSetInteger(CustomSymbol, SYMBOL_TRADE_MODE, (long)SYMBOL_TRADE_MODE_FULL); 
   CustomSymbolSetInteger(CustomSymbol, SYMBOL_DIGITS, (long)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   CustomSymbolSetDouble(CustomSymbol, SYMBOL_POINT, SymbolInfoDouble(_Symbol, SYMBOL_POINT));
   CustomSymbolSetDouble(CustomSymbol, SYMBOL_TRADE_TICK_SIZE, SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE));
   SymbolSelect(CustomSymbol, true);

   bool stateLoaded = false;
   if(!InpForceRebuild) {
      if(LoadState() && LastCommittedBarTime > 0) {
         ConnectHistoryToLive();
         stateLoaded = true;
      } 
   }

   if(!stateLoaded) {
      if(!BuildHistory()) return(INIT_FAILED);
      ConnectHistoryToLive();
   }
   
   RenkoChartID = 0;
   long currID = ChartFirst();
   while(currID >= 0) {
      if(ChartSymbol(currID) == CustomSymbol) { 
         RenkoChartID = currID;
         break; 
      }
      currID = ChartNext(currID);
   }
   
  if(RenkoChartID == 0) {
      RenkoChartID = ChartOpen(CustomSymbol, PERIOD_M1);
   }
   
   if(RenkoChartID > 0) {
      ChartSetInteger(RenkoChartID, CHART_MODE, CHART_CANDLES);
      ChartSetInteger(RenkoChartID, CHART_FOREGROUND, 0);
      
      ChartSetInteger(RenkoChartID, CHART_SHOW_ASK_LINE, InpShowAsk);
      ChartSetInteger(RenkoChartID, CHART_COLOR_ASK, InpAskColor);
      ChartSetInteger(RenkoChartID, CHART_SHOW_BID_LINE, InpShowBid);
      ChartSetInteger(RenkoChartID, CHART_COLOR_BID, InpBidColor);
      ChartSetInteger(RenkoChartID, CHART_SHOW_LAST_LINE, InpShowLast);
      ChartSetInteger(RenkoChartID, CHART_COLOR_LAST, InpLastColor);
      
      ChartRedraw(RenkoChartID);
   }
   
   GUI.Create();
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   
   isInitialized = true;
   EventSetTimer(1); 
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   CleanUpRenkoChart();
   GUI.Destroy();
   FlushRamToDisk(true);
   if(ATR_Handle != INVALID_HANDLE) IndicatorRelease(ATR_Handle);
   Comment(""); 
}

void OnTimer()
{
   if(!isInitialized) return;

   // --- OPTIMIZED DRAWING LOGIC ---
   if(RenkoChartID > 0) {
      if(!InpEnableLineDrawing) {
         if(!g_LinesCleared) {
             CleanUpRenkoChart();
             g_LinesCleared = true;
         }
      } 
      else {
         g_LinesCleared = false;
         if(InpShowEntry || InpShowSL || InpShowTP) {
             DrawActiveTradeLines();
         }

         if(InpShowHistory) {
             int currentDeals = HistoryDealsTotal();
             if(currentDeals != g_LastHistoryDeals) {
                 DrawHistoryTrendLines();
                 g_LastHistoryDeals = currentDeals;
             }
         }

         ChartSetInteger(RenkoChartID, CHART_SHOW_ASK_LINE, InpShowAsk);
         ChartSetInteger(RenkoChartID, CHART_COLOR_ASK, InpAskColor);
         ChartSetInteger(RenkoChartID, CHART_SHOW_BID_LINE, InpShowBid);
         ChartSetInteger(RenkoChartID, CHART_COLOR_BID, InpBidColor);
         ChartSetInteger(RenkoChartID, CHART_SHOW_LAST_LINE, InpShowLast);
         ChartSetInteger(RenkoChartID, CHART_COLOR_LAST, InpLastColor);
      }
   }

   string histInfo = "";
   if(InpStartMode == MODE_DAYS_BACK) {
      histInfo = IntegerToString(InpHistoryDays) + " Days";
   } else {
      histInfo = TimeToString(InpFixedStartDate, TIME_DATE);
   }

   GUI.Update(
      EnumToString(InpBlockMode),
      InpBlockSizeValue,
      CurrentBlockSizePoint,
      RenkoAnchorPrice,
      histInfo 
   );
}

void OnTrade()
{
   if(!InpEnableLineDrawing) return;
   if(RenkoChartID > 0) {
      DrawActiveTradeLines();
      g_LastHistoryDeals = -1;
   }
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   GUI.OnEvent(id, lparam, dparam, sparam);
}

void OnTick()
{
   if(!isInitialized) return;
   
   MqlTick tick;
   if(SymbolInfoTick(_Symbol, tick)) {
      if(tick.bid <= 0) return;
      UpdateMarketWatch();
      
      long vol = (tick.volume > 0) ? (long)tick.volume : 1;
      
      bool newBoxCreated = ProcessRenkoTick(tick.bid, TimeCurrent(), vol);
      
      // Attempt to Flush (Will only execute if threshold met)
      FlushRamToDisk(false); 

      if(RenkoChartID > 0) {
         if(!newBoxCreated) UpdateLiveBlock(tick.bid);
         // Note: We moved ChartRedraw inside FlushRamToDisk to save CPU
      }
   }
}

//+------------------------------------------------------------------+
//| Optimized: Draw HISTORY (O(N) Complexity - No Context Thrashing) |
//+------------------------------------------------------------------+
struct DealInfo {
   ulong ticket;
   long posID;
   double price;
   datetime time;
   long type;
};

void DrawHistoryTrendLines()
{
   if(!InpShowHistory) return;
   datetime end = TimeCurrent();
   datetime start = end - (InpHistoryDays * 24 * 3600); 
   
   if(!HistorySelect(start, end)) return;
   int totalDeals = HistoryDealsTotal();
   
   DealInfo openDeals[];
   ArrayResize(openDeals, totalDeals); 
   int openCount = 0;

   for(int i = 0; i < totalDeals; i++) {
      ulong ticket = HistoryDealGetTicket(i);
      long entryType = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      long posID = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
      string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
      
      if(symbol != UnderlyingSymbol) continue;

      if(entryType == DEAL_ENTRY_IN) {
         openDeals[openCount].ticket = ticket;
         openDeals[openCount].posID = posID;
         openDeals[openCount].price = HistoryDealGetDouble(ticket, DEAL_PRICE);
         openDeals[openCount].time = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         openDeals[openCount].type = HistoryDealGetInteger(ticket, DEAL_TYPE);
         openCount++;
      }
      else if(entryType == DEAL_ENTRY_OUT) {
         string lineName = "HistTrd_" + (string)posID;
         string arrowIn = "ArrIn_" + (string)posID;
         string arrowOut = "ArrOut_" + (string)posID;

         if(ObjectFind(RenkoChartID, lineName) >= 0) continue;

         int matchIdx = -1;
         for(int k = 0; k < openCount; k++) {
            if(openDeals[k].posID == posID) {
               matchIdx = k;
               break;
            }
         }

         double priceIn = 0;
         datetime timeIn = 0;
         long dealType = -1;
         
         if(matchIdx != -1) {
            priceIn = openDeals[matchIdx].price;
            timeIn = openDeals[matchIdx].time;
            dealType = openDeals[matchIdx].type;
         } 
         else {
             continue; // Skip rare incomplete data
         }

         if(timeIn > 0) {
            double priceOut = HistoryDealGetDouble(ticket, DEAL_PRICE);
            datetime timeOut = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            ObjectCreate(RenkoChartID, lineName, OBJ_TREND, 0, timeIn, priceIn, timeOut, priceOut);
            bool isWin = (profit >= 0);
            color c = isWin ? InpHistWinColor : InpHistLossColor; 
            
            ObjectSetInteger(RenkoChartID, lineName, OBJPROP_COLOR, c);
            ObjectSetInteger(RenkoChartID, lineName, OBJPROP_STYLE, InpHistStyle);
            ObjectSetInteger(RenkoChartID, lineName, OBJPROP_WIDTH, 1);
            ObjectSetInteger(RenkoChartID, lineName, OBJPROP_RAY_RIGHT, false);
            
            int points = (int)(MathAbs(priceOut - priceIn) / _Point);
            string typeStr = (dealType == DEAL_TYPE_BUY) ? "BUY" : "SELL";
            string tooltip = StringFormat("%s #%d\nIn: %s @ %s\nOut: %s @ %s\nProfit: %.2f\nPoints: %d", 
                                          typeStr, posID,
                                          TimeToString(timeIn, TIME_DATE|TIME_MINUTES), 
                                          DoubleToString(priceIn, _Digits),
                                          TimeToString(timeOut, TIME_DATE|TIME_MINUTES), DoubleToString(priceOut, _Digits),
                                          profit, points);
            ObjectSetString(RenkoChartID, lineName, OBJPROP_TOOLTIP, tooltip);
            
            if(ObjectCreate(RenkoChartID, arrowIn, OBJ_ARROW, 0, timeIn, priceIn)) {
                ObjectSetInteger(RenkoChartID, arrowIn, OBJPROP_ARROWCODE, 159);
                ObjectSetInteger(RenkoChartID, arrowIn, OBJPROP_COLOR, c);
            }
            ObjectSetString(RenkoChartID, arrowIn, OBJPROP_TOOLTIP, "Open " + typeStr);

            if(ObjectCreate(RenkoChartID, arrowOut, OBJ_ARROW, 0, timeOut, priceOut)) {
                ObjectSetInteger(RenkoChartID, arrowOut, OBJPROP_ARROWCODE, 159);
                ObjectSetInteger(RenkoChartID, arrowOut, OBJPROP_COLOR, c);
            }
            ObjectSetString(RenkoChartID, arrowOut, OBJPROP_TOOLTIP, "Close " + typeStr + "\nP: " + DoubleToString(profit, 2));
         }
      }
   }
   ChartRedraw(RenkoChartID);
}

//+------------------------------------------------------------------+
//| Optimized: Draw ACTIVE Trade Levels (Mark & Sweep Algorithm)     |
//+------------------------------------------------------------------+
void DrawActiveTradeLines()
{
   if(!InpEnableLineDrawing) return;
   string activeTickets = ";";
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket)) {
         if(PositionGetString(POSITION_SYMBOL) == UnderlyingSymbol) {
            
            activeTickets += (string)ticket + ";";
            long type   = PositionGetInteger(POSITION_TYPE);
            double open = PositionGetDouble(POSITION_PRICE_OPEN);
            double sl   = PositionGetDouble(POSITION_SL);
            double tp   = PositionGetDouble(POSITION_TP);
            double vol  = PositionGetDouble(POSITION_VOLUME); 
            double calc_profit = 0.0;

            if(InpShowEntry) {
               string name = "OpenLine_" + (string)ticket;
               if(ObjectFind(RenkoChartID, name) < 0) { 
                  ObjectCreate(RenkoChartID, name, OBJ_HLINE, 0, 0, open);
                  ObjectSetInteger(RenkoChartID, name, OBJPROP_COLOR, InpEntryColor);
                  ObjectSetInteger(RenkoChartID, name, OBJPROP_STYLE, InpEntryStyle);
                  ObjectSetString(RenkoChartID, name, OBJPROP_TEXT, "Buy #" + (string)ticket);
               }
               ObjectSetString(RenkoChartID, name, OBJPROP_TOOLTIP, "Entry #" + (string)ticket + "\nVol: " + DoubleToString(vol, 2));
            }

            if(InpShowSL && sl > 0) {
               string name = "SLLine_" + (string)ticket;
               if(ObjectFind(RenkoChartID, name) < 0) {
                  ObjectCreate(RenkoChartID, name, OBJ_HLINE, 0, 0, sl);
                  ObjectSetInteger(RenkoChartID, name, OBJPROP_COLOR, InpSLColor);
                  ObjectSetInteger(RenkoChartID, name, OBJPROP_STYLE, InpSLStyle);
               } else if(MathAbs(ObjectGetDouble(RenkoChartID, name, OBJPROP_PRICE) - sl) > _Point) {
                  ObjectSetDouble(RenkoChartID, name, OBJPROP_PRICE, sl);
               }
               if(OrderCalcProfit((ENUM_ORDER_TYPE)type, UnderlyingSymbol, vol, open, sl, calc_profit)) {
                   int pts = (int)(MathAbs(open - sl) / _Point);
                   ObjectSetString(RenkoChartID, name, OBJPROP_TOOLTIP, "SL Loss: " + DoubleToString(calc_profit, 2) + " ("+IntegerToString(pts)+" pts)");
               }
            }
            
            if(InpShowTP && tp > 0) {
               string name = "TPLine_" + (string)ticket;
               if(ObjectFind(RenkoChartID, name) < 0) {
                  ObjectCreate(RenkoChartID, name, OBJ_HLINE, 0, 0, tp);
                  ObjectSetInteger(RenkoChartID, name, OBJPROP_COLOR, InpTPColor);
                  ObjectSetInteger(RenkoChartID, name, OBJPROP_STYLE, InpTPStyle);
               } else if(MathAbs(ObjectGetDouble(RenkoChartID, name, OBJPROP_PRICE) - tp) > _Point) {
                  ObjectSetDouble(RenkoChartID, name, OBJPROP_PRICE, tp);
               }
               if(OrderCalcProfit((ENUM_ORDER_TYPE)type, UnderlyingSymbol, vol, open, tp, calc_profit)) {
                   int pts = (int)(MathAbs(open - tp) / _Point);
                   ObjectSetString(RenkoChartID, name, OBJPROP_TOOLTIP, "TP Profit: +" + DoubleToString(calc_profit, 2) + " ("+IntegerToString(pts)+" pts)");
               }
            }
         }
      }
   }

   int currentPosCount = PositionsTotal();
   if(currentPosCount < g_LastPosCount || g_LastPosCount == 0) {
      int totalObj = ObjectsTotal(RenkoChartID, 0, -1);
      for(int k = totalObj - 1; k >= 0; k--) {
         string name = ObjectName(RenkoChartID, k, 0, -1);
         if(StringFind(name, "OpenLine_") != 0 && 
            StringFind(name, "SLLine_") != 0 && 
            StringFind(name, "TPLine_") != 0) continue;
         string parts[];
         StringSplit(name, '_', parts);
         if(ArraySize(parts) > 1) {
            string ticketID = parts[1];
            if(StringFind(activeTickets, ";" + ticketID + ";") < 0) {
               ObjectDelete(RenkoChartID, name);
            }
         }
      }
   }
   g_LastPosCount = currentPosCount;
   ChartRedraw(RenkoChartID);
}

//+------------------------------------------------------------------+
//| NEW: Intelligent Disk Flushing (The Gatekeeper)                  |
//+------------------------------------------------------------------+
void FlushRamToDisk(bool force = false)
{
   int total = ArraySize(g_RamRateBuffer);
   if(total == 0) return;

   // DECISION LOGIC: Only write to disk if:
   // 1. We are forced (e.g. closing the bot)
   // 2. Buffer is getting huge (> 50 bars)
   // 3. It's been more than 250ms since last write (Latency limit)
   if(!force) {
      if(total < 50 && (GetMicrosecondCount() - g_LastFlushTime) < 250000) return; 
   }

   // --- EXECUTE DISK WRITE ---
   // 1. Phantom Protection (Delete future overlap based on the first bar in RAM)
   CustomRatesDelete(CustomSymbol, g_RamRateBuffer[0].time, LONG_MAX);
   
   // 2. Bulk Write from RAM to Disk
   CustomRatesUpdate(CustomSymbol, g_RamRateBuffer, total);
   CustomTicksAdd(CustomSymbol, g_RamTickBuffer);
   
   // 3. Update State & UI
   SaveState();
   UpdateMarketWatch();
   
   // 4. Clear RAM Buffer
   ArrayResize(g_RamRateBuffer, 0);
   ArrayResize(g_RamTickBuffer, 0);
   
   // 5. Update Timer
   g_LastFlushTime = GetMicrosecondCount();
   
   // Force a redraw only when we actually write data
   if(RenkoChartID > 0) ChartRedraw(RenkoChartID);
}

//+------------------------------------------------------------------+
//| Helper: Clean Up All Renko Visuals                               |
//+------------------------------------------------------------------+
void CleanUpRenkoChart()
{
   if(RenkoChartID <= 0) return;
   ObjectsDeleteAll(RenkoChartID, "HistTrd_");
   ObjectsDeleteAll(RenkoChartID, "ArrIn_");
   ObjectsDeleteAll(RenkoChartID, "ArrOut_");
   ObjectsDeleteAll(RenkoChartID, "OpenLine_");
   ObjectsDeleteAll(RenkoChartID, "SLLine_");
   ObjectsDeleteAll(RenkoChartID, "TPLine_");
   ChartRedraw(RenkoChartID);
}
//+------------------------------------------------------------------+
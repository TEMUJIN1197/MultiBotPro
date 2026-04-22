//+------------------------------------------------------------------+
//|                     RenkoBuilderPro_v1.mq5                       |
//|      "Gap Filler, Anti-Dash, Lite Version (No Bridge)"           |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Renko Builder Pro"
#property link      "https://discord.com"
#property version   "1.00" 
#property description "Renko Builder with Smart Symbol Swapping"

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
enum ENUM_HISTORY_DATA_TYPE {
   DATA_M1,   // M1 OHLC (Fast)
   DATA_TICK  // Real Ticks (Accurate but Slow)
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
input bool           InpAdaptiveATRRefresh = true;
input int            InpATRRefreshMs      = 250;
input group "2. History & Repair"
input ENUM_START_MODE InpStartMode        = MODE_DAYS_BACK;
input ENUM_HISTORY_DATA_TYPE InpHistDataType = DATA_M1;
input int            InpHistoryDays       = 5;
input datetime       InpFixedStartDate    = D'2026.01.01 00:00:00';
// CHANGE: Defaulted to false to allow Smart Resume on symbol swap
input bool           InpForceRebuild      = false; 
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
input group "6. Auto Trading (MA Crossover)"
input bool     InpEnableAutoTrade = false;
input double   InpLotSize         = 0.1;
input int      InpFastMAPeriod    = 9;
input int      InpSlowMAPeriod    = 21;
input int      InpMaxSpreadPoints = 50;     // Max allowed spread in points
input ulong    InpMagicNumber     = 888888;

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
int      g_FastMA_Handle = INVALID_HANDLE;
int      g_SlowMA_Handle = INVALID_HANDLE;
bool     g_IsAutoTradeMode = false;

// --- NEW RAM BUFFERS (The "Cache") ---
MqlRates g_RamRateBuffer[];
MqlTick  g_RamTickBuffer[];
ulong    g_LastFlushTime = 0;
// FIX: "Hard" cursor tracks what is physically on disk to prevent phantom overlap
datetime g_HardCommittedTime = 0; 
// -------------------------------------
//--- TRACKERS
double   g_LastClosePrice = 0;
// Fixes Gaps
int      g_LastHistoryDeals = -1;
datetime g_LastTradeTime    = 0;
bool     g_LinesCleared     = false;
double   g_CachedATR = 0;
datetime g_LastATRTime = 0;
ulong    g_LastATRFetchMs = 0;
int      g_LastPosCount = 0;
double   g_CurrentATR = 0;
datetime g_LastPhantomBarTime = 0;

datetime g_BrickStartTime = 0;          // start time of the current forming brick
double   g_LiveBarOpen    = 0;           // open price of the current brick

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
      m_h=155; // Height increased to accommodate Rebuild info
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
      CreateLabel("V_Hist", "--", 100, y, 8, c_txt); y+=15; 

      CreateLabel("L_Reb", "Rebuild:", 10, y, 8, c_lbl);
      CreateLabel("V_Reb", "--", 100, y, 8, c_txt); y+=20;
      
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

   void Update(string mode, double inSize, double actSize, double anchor, string historyMsg, bool isRebuild) {
      if(m_minimized) return;
      SetText("V_Mode", mode);
      SetText("V_Size", DoubleToString(inSize, 2));
      SetText("V_Hist", historyMsg); 
      
      string rebStatus = isRebuild ? "TRUE (Reset)" : "FALSE (Append)";
      SetText("V_Reb", rebStatus);
      ObjectSetInteger(0, m_prefix+"V_Reb", OBJPROP_COLOR, isRebuild ? clrOrange : clrLime);
      
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
      SetVis("L_Reb", vis);  SetVis("V_Reb", vis);
      SetVis("Div1", vis);
      SetVis("L_Act", vis); SetVis("V_Act", vis); 
      SetVis("L_Anc", vis);
      SetVis("V_Anc", vis);

      if(vis) {
         int y = m_y + 35;
         SetGeom("L_Mode", m_x+10, y); SetGeom("V_Mode", m_x+100, y); y+=15;
         SetGeom("L_Size", m_x+10, y); SetGeom("V_Size", m_x+100, y); y+=15;
         SetGeom("L_Hist", m_x+10, y); SetGeom("V_Hist", m_x+100, y); y+=15;
         SetGeom("L_Reb", m_x+10, y); SetGeom("V_Reb", m_x+100, y);
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

      // FIX: If timeRef is 0 (Initialization), FORCE a fresh read, ignoring cache.
      if(g_CurrentATR == 0 || timeRef == 0) {
         double atrBuffer[];
         if(CopyBuffer(ATR_Handle, 0, 0, 1, atrBuffer) > 0) { 
             g_CurrentATR = atrBuffer[0];
         }
      }
      
      double calculatedSize = g_CurrentATR * (InpBlockSizeValue / 100.0);
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
   static double lastSavedAnchor = 0;
   static datetime lastSaveTime = 0;
   // OPTIMIZATION: Only write to disk if Anchor changed or 5+ seconds passed
   if(RenkoAnchorPrice == lastSavedAnchor && 
      TimeCurrent() - lastSaveTime < 5) return;
   GlobalVariableSet(GV_Prefix + "_Anchor", RenkoAnchorPrice);
   GlobalVariableSet(GV_Prefix + "_Trend", (double)IsTrendUp);
   GlobalVariableSet(GV_Prefix + "_LastTime", (double)LastCommittedBarTime);
   GlobalVariableSet(GV_Prefix + "_High", RenkoBoxHigh);
   GlobalVariableSet(GV_Prefix + "_Low", RenkoBoxLow);
   GlobalVariableSet(GV_Prefix + "_LastClose", g_LastClosePrice); // Save Close to prevent gaps
   
   lastSavedAnchor = RenkoAnchorPrice;
   lastSaveTime = TimeCurrent();
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
   // FIX: Sync hard cursor with loaded state
   g_HardCommittedTime = LastCommittedBarTime;
   
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
   if(MQLInfoInteger(MQL_TESTER)) {
      if(LastCommittedBarTime == 0) return TimeCurrent() - (TimeCurrent() % 60);
      return LastCommittedBarTime + 60; 
   }
   
   // Snap current time strictly to the minute boundary
   datetime next = TimeCurrent() - (TimeCurrent() % 60);
   if(next <= LastCommittedBarTime) next = LastCommittedBarTime + 60;
   
   return next;
}

void UpdateLiveBlock(double currentPrice, datetime tickTime)
{
   if(g_BrickStartTime == 0) return;
   
   // Throttle updates (optional)
   static double lastPrice = 0;
   static ulong lastWrite = 0;
   if(MathAbs(currentPrice - lastPrice) < _Point * 0.1 &&
      GetMicrosecondCount() - lastWrite < 500000) return;
   
   MqlRates liveRate[1];
   liveRate[0].time = g_BrickStartTime;
   liveRate[0].open = g_LiveBarOpen;
   liveRate[0].close = NormalizePrice(currentPrice);
   
   if(InpShowWicks) {
      liveRate[0].high = MathMax(RenkoBoxHigh, MathMax(liveRate[0].open, liveRate[0].close));
      liveRate[0].low  = MathMin(RenkoBoxLow,  MathMin(liveRate[0].open, liveRate[0].close));
   } else {
      liveRate[0].high = MathMax(liveRate[0].open, liveRate[0].close);
      liveRate[0].low  = MathMin(liveRate[0].open, liveRate[0].close);
   }
   liveRate[0].tick_volume = (TickVolBuffer > 0) ? TickVolBuffer : 1;
   liveRate[0].spread = 0;
   liveRate[0].real_volume = 0;
   
   // Update (or insert) the bar – using the fixed timestamp, MT5 replaces any existing bar
   CustomRatesUpdate(CustomSymbol, liveRate, 1);
   
   // Update tick data for the same timestamp (optional)
   MqlTick liveTick[1];
   double realAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double realBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   liveTick[0].time     = g_BrickStartTime;
   liveTick[0].time_msc = (long)g_BrickStartTime * 1000;
   liveTick[0].bid      = liveRate[0].close;
   liveTick[0].ask      = liveRate[0].close + (realAsk - realBid);
   liveTick[0].flags    = TICK_FLAG_BID | TICK_FLAG_ASK;
   CustomTicksAdd(CustomSymbol, liveTick);
   
   lastPrice = currentPrice;
   lastWrite = GetMicrosecondCount();
}

//+------------------------------------------------------------------+
//| Optimized: Buffer bars in memory & ENFORCE CONTINUITY            |
//+------------------------------------------------------------------+
void PushRenkoBarBuffered(double open, double close, double boxHigh, double boxLow, datetime eventTime, long volume, 
                          MqlRates &resultRates[], MqlTick &resultTicks[])
{
   // 1. Time Synchronization Logic
   datetime newBarTime;
   if(MQLInfoInteger(MQL_TESTER)) {
      newBarTime = LastCommittedBarTime + 60;
   } else {
      // Snap event time strictly to the nearest minute boundary (00 seconds)
      newBarTime = eventTime - (eventTime % 60); 
      
      // CRITICAL FIX: Enforce minimum 60-second spacing. 
      // Anything less causes MT5 to squash multiple bars into one visual slot
      // and eventually corrupts/deletes the custom symbol history database.
      if(newBarTime <= LastCommittedBarTime) {
         newBarTime = LastCommittedBarTime + 60;
      }
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
   
   if(RenkoAnchorPrice == 0) {
      RenkoAnchorPrice = NormalizePrice(price);
      g_LastClosePrice = RenkoAnchorPrice;
      RenkoBoxHigh = RenkoAnchorPrice;
      RenkoBoxLow  = RenkoAnchorPrice;
      g_BrickStartTime = tickTime;          // first brick starts now
      g_LiveBarOpen = RenkoAnchorPrice;
      return false;
   }

   RenkoBoxHigh = MathMax(RenkoBoxHigh, price);
   RenkoBoxLow  = MathMin(RenkoBoxLow,  price);
   
   CurrentBlockSizePoint = CalculateBlockSize(tickTime);
   double BS = MathMax(CurrentBlockSizePoint, _Point);
   
   int maxLoops = 1000, loopCount = 0;
   bool boxCreated = false;
   datetime nextStartTime = g_BrickStartTime;   // start time for the next brick (if any)
   
   while(loopCount < maxLoops)
   {
      bool action = false;
      loopCount++;
      
      double upTarget   = NormalizePrice(RenkoAnchorPrice + BS);
      double downTarget = NormalizePrice(RenkoAnchorPrice - BS);
      double revUpTarget   = NormalizePrice(RenkoAnchorPrice + 2*BS);
      double revDownTarget = NormalizePrice(RenkoAnchorPrice - 2*BS);
      
      if(IsTrendUp)
      {
         // Continuation up
         if(price >= upTarget - _Point/2)
         {
            PushCompletedBrick(nextStartTime, RenkoAnchorPrice, upTarget,
                               RenkoBoxHigh, RenkoBoxLow, TickVolBuffer);
            RenkoAnchorPrice = upTarget;
            nextStartTime = (nextStartTime >= tickTime) ? nextStartTime + 1 : tickTime;
            g_LiveBarOpen = RenkoAnchorPrice;
            action = true;
         }
         // Reversal down
         else if(price <= revDownTarget + _Point/2)
         {
            double open  = NormalizePrice(RenkoAnchorPrice - BS);
            double close = NormalizePrice(RenkoAnchorPrice - 2*BS);
            PushCompletedBrick(nextStartTime, open, close,
                               RenkoBoxHigh, RenkoBoxLow, TickVolBuffer);
            RenkoAnchorPrice = close;
            IsTrendUp = false;
            nextStartTime = (nextStartTime >= tickTime) ? nextStartTime + 1 : tickTime;
            g_LiveBarOpen = RenkoAnchorPrice;
            action = true;
         }
      }
      else // trend down
      {
         // Continuation down
         if(price <= downTarget + _Point/2)
         {
            PushCompletedBrick(nextStartTime, RenkoAnchorPrice, downTarget,
                               RenkoBoxHigh, RenkoBoxLow, TickVolBuffer);
            RenkoAnchorPrice = downTarget;
            nextStartTime = (nextStartTime >= tickTime) ? nextStartTime + 1 : tickTime;
            g_LiveBarOpen = RenkoAnchorPrice;
            action = true;
         }
         // Reversal up
         else if(price >= revUpTarget - _Point/2)
         {
            double open  = NormalizePrice(RenkoAnchorPrice + BS);
            double close = NormalizePrice(RenkoAnchorPrice + 2*BS);
            PushCompletedBrick(nextStartTime, open, close,
                               RenkoBoxHigh, RenkoBoxLow, TickVolBuffer);
            RenkoAnchorPrice = close;
            IsTrendUp = true;
            nextStartTime = (nextStartTime >= tickTime) ? nextStartTime + 1 : tickTime;
            g_LiveBarOpen = RenkoAnchorPrice;
            action = true;
         }
      }
      
      if(action)
      {
         boxCreated = true;
         TickVolBuffer = 0;
         RenkoBoxHigh = RenkoAnchorPrice;
         RenkoBoxLow  = RenkoAnchorPrice;
      }
      else break;
   }
   
   // Update the start time of the current forming brick
   g_BrickStartTime = nextStartTime;
   
   // Update the live bar with the latest price
   UpdateLiveBlock(price, tickTime);
   return boxCreated;
}

void PushCompletedBrick(datetime startTime, double open, double close,
                        double high, double low, long volume)
{
   // Ensure strictly increasing timestamps
   if(startTime <= LastCommittedBarTime)
      startTime = LastCommittedBarTime + 1;
   
   int idx = ArraySize(g_RamRateBuffer);
   ArrayResize(g_RamRateBuffer, idx + 1);
   ArrayResize(g_RamTickBuffer,  idx + 1);
   
   g_RamRateBuffer[idx].time  = startTime;
   g_RamRateBuffer[idx].open  = NormalizePrice(open);
   g_RamRateBuffer[idx].close = NormalizePrice(close);
   g_RamRateBuffer[idx].high  = (InpShowWicks) ? MathMax(high, MathMax(open, close))
                                                : MathMax(open, close);
   g_RamRateBuffer[idx].low   = (InpShowWicks) ? MathMin(low,  MathMin(open, close))
                                                : MathMin(open, close);
   g_RamRateBuffer[idx].tick_volume = (volume > 0) ? volume : 1;
   g_RamRateBuffer[idx].spread = 0;
   g_RamRateBuffer[idx].real_volume = 0;
   
   // Create a corresponding tick (for bid/ask lines)
   double realAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double realBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   g_RamTickBuffer[idx].time     = startTime;
   g_RamTickBuffer[idx].time_msc = (long)startTime * 1000;
   g_RamTickBuffer[idx].bid      = g_RamRateBuffer[idx].close;
   g_RamTickBuffer[idx].ask      = g_RamRateBuffer[idx].close + (realAsk - realBid);
   g_RamTickBuffer[idx].flags    = TICK_FLAG_BID | TICK_FLAG_ASK;
   
   g_LastClosePrice = g_RamRateBuffer[idx].close;
   LastCommittedBarTime = startTime;
}

bool BuildHistory()
{
   Print("Building Standard Renko History...");
   
   // --- FIX 1: CLEAR OLD DATA ---
   // This prevents "Double Bars" by wiping the specific custom symbol history first
   CustomRatesDelete(CustomSymbol, 0, LONG_MAX);
   CustomTicksDelete(CustomSymbol, 0, LONG_MAX);
   if(RenkoChartID > 0) ChartRedraw(RenkoChartID);
   
   datetime start;
   if(InpStartMode == MODE_DAYS_BACK) start = TimeCurrent() - (InpHistoryDays * 86400);
   else start = InpFixedStartDate;
   if(start <= 0) start = D'2020.01.01';
   
   // Snap the initial start time to a clean minute
   LastCommittedBarTime = start - (start % 60); 
   int total = 0;
   
   // --- FORCE DATA LOAD ---
   int retry = 0;

   if (InpHistDataType == DATA_M1) 
   {
      MqlRates src[];
      while(retry < 15) {
         total = CopyRates(_Symbol, PERIOD_M1, start, TimeCurrent(), src);
         if(total > 100) break; // We got good data
         Print("Waiting for M1 history data... Attempt: ", retry+1);
         Sleep(1000); // Wait 1 second for terminal to catch up
         retry++;
      }
      
      if(total == 0) {
         Print("Error: Could not load M1 history. Please restart bot or check internet.");
         return false;
      }
      
      if(total > 0) {
         RenkoAnchorPrice = NormalizePrice(src[0].open);
         g_LastClosePrice = RenkoAnchorPrice; // Init Continuity
         RenkoBoxHigh = RenkoAnchorPrice;
         RenkoBoxLow = RenkoAnchorPrice;
         IsTrendUp = (src[0].close > src[0].open);
         
         datetime lastM1Time = src[0].time;
   
         for(int i=0; i<total; i++) {
            if(src[i].time > TimeCurrent()) break;
            
            // --- FIX 2: WEEKEND / SESSION GAP DETECTOR ---
            if(src[i].time - lastM1Time > 14400) { 
                datetime snappedTime = src[i].time - (src[i].time % 60);
                if(snappedTime > LastCommittedBarTime) {
                    LastCommittedBarTime = snappedTime - 60; 
                }
            }
            lastM1Time = src[i].time;
   
            long volPart = src[i].tick_volume / 3;
            if(volPart < 1) volPart = 1;
   
            // Simulate intra-bar price movement
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
   } 
   else 
   {
      MqlTick ticks[];
      ulong startMs = (ulong)start * 1000;
      ulong endMs = (ulong)TimeCurrent() * 1000;
      
      while(retry < 15) {
         total = CopyTicksRange(_Symbol, ticks, COPY_TICKS_ALL, startMs, endMs);
         if(total > 100) break; // We got good data
         Print("Waiting for Tick history data... Attempt: ", retry+1);
         Sleep(1000); 
         retry++;
      }
      
      if(total == 0) {
         Print("Error: Could not load Tick history. Please switch to M1 data or restart bot.");
         return false;
      }
      
      if(total > 0) {
         RenkoAnchorPrice = NormalizePrice(ticks[0].bid);
         g_LastClosePrice = RenkoAnchorPrice; 
         RenkoBoxHigh = RenkoAnchorPrice;
         RenkoBoxLow = RenkoAnchorPrice;
         IsTrendUp = true; 
         
         datetime lastTickTime = ticks[0].time;
   
         for(int i=0; i<total; i++) {
            if(ticks[i].time > TimeCurrent()) break;
            if(ticks[i].bid <= 0.0) continue; 
            
            if(ticks[i].time - lastTickTime > 14400) { 
                datetime snappedTime = ticks[i].time - (ticks[i].time % 60);
                if(snappedTime > LastCommittedBarTime) {
                    LastCommittedBarTime = snappedTime - 60; 
                }
            }
            lastTickTime = ticks[i].time;
            
            ProcessRenkoTick(ticks[i].bid, ticks[i].time, 1);
         }
      }
   }
   
   // Sync hard cursor after build
   g_HardCommittedTime = LastCommittedBarTime;
   
   // Ensure RAM is completely flushed to disk with our new true memory cleanup
   FlushRamToDisk(true);
   SaveState();
   
   if(RenkoChartID > 0) {
      ChartSetSymbolPeriod(RenkoChartID, CustomSymbol, PERIOD_M1);
      ChartRedraw(RenkoChartID);
   }
   Print("History Build Complete. Weekend gaps aligned.");
   return true;
}

void ConnectHistoryToLive()
{
   Print("Connecting History to Live...");
   
   // Start lookback EXACTLY from the last committed time to prevent gaps.
   datetime lookback = (LastCommittedBarTime > 0) ? LastCommittedBarTime : (TimeCurrent() - 172800);
   int total = 0;
   
   if (InpHistDataType == DATA_M1) 
   {
      MqlRates src[];
      total = CopyRates(_Symbol, PERIOD_M1, lookback, TimeCurrent(), src);
      
      if(total > 0) {
         Print("Gap Fill: Processing ", total, " M1 bars...");
         datetime lastM1Time = src[0].time; // Initialize gap tracker
         
         for(int i=0; i<total; i++) {
            if(src[i].time <= LastCommittedBarTime) {
                lastM1Time = src[i].time;
                continue;
            }
            
            if(src[i].time - lastM1Time > 14400) { 
                datetime snappedTime = src[i].time - (src[i].time % 60);
                if(snappedTime > LastCommittedBarTime) {
                    LastCommittedBarTime = snappedTime - 60; 
                }
            }
            lastM1Time = src[i].time;
   
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
   }
   else 
   {
      MqlTick ticks[];
      ulong startMs = (ulong)lookback * 1000;
      ulong endMs = (ulong)TimeCurrent() * 1000;
      
      total = CopyTicksRange(_Symbol, ticks, COPY_TICKS_ALL, startMs, endMs);
      
      if(total > 0) {
         Print("Gap Fill: Processing ", total, " Ticks...");
         datetime lastTickTime = ticks[0].time; 
         
         for(int i=0; i<total; i++) {
            if(ticks[i].time <= LastCommittedBarTime) {
                lastTickTime = ticks[i].time;
                continue;
            }
            if(ticks[i].bid <= 0.0) continue;
            
            if(ticks[i].time - lastTickTime > 14400) { 
                datetime snappedTime = ticks[i].time - (ticks[i].time % 60);
                if(snappedTime > LastCommittedBarTime) {
                    LastCommittedBarTime = snappedTime - 60; 
                }
            }
            lastTickTime = ticks[i].time;
            
            ProcessRenkoTick(ticks[i].bid, ticks[i].time, 1);
         }
      }
   }
   
   // NUCLEAR CLEANUP
   // Remove any 'future' or phantom bars that might exist beyond our newly caught-up time.
   if(LastCommittedBarTime > 0) {
       CustomRatesDelete(CustomSymbol, LastCommittedBarTime + 1, LONG_MAX);
   }

   // FORCE FLUSH TO DISK IMMEDIATELY
   // Ensures the "Gap Fill" bars appear on the chart instantly before the first live tick arrives.
   FlushRamToDisk(true);

   // Process the current tick to sync live state
   MqlTick tick;
   if(SymbolInfoTick(_Symbol, tick)) {
      ProcessRenkoTick(tick.bid, TimeCurrent(), (long)tick.volume);
   }
}

int OnInit()
{
   UnderlyingSymbol = _Symbol; // Set this early for the trade functions

   // --- DETERMINE OPERATING MODE ---
   // Force Auto-Trade if enabled by user OR if running in the Strategy Tester
   g_IsAutoTradeMode = (InpEnableAutoTrade || MQLInfoInteger(MQL_TESTER));

   // --- HIJACK: AUTO-TRADE MODE ON BASE SYMBOL ---
   if(g_IsAutoTradeMode) {
      if(MQLInfoInteger(MQL_TESTER)) {
         Print("Strategy Tester Detected: Forcing Auto-Trade Mode (Renko Bypass).");
      } else {
         Print("Auto-Trade Enabled: Bypassing Renko Simulator. Running standard MA Crossover on base symbol.");
      }
      
      Trade.SetExpertMagicNumber(InpMagicNumber);
      
      // Attach to the base symbol and current chart timeframe
      g_FastMA_Handle = iMA(_Symbol, _Period, InpFastMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
      g_SlowMA_Handle = iMA(_Symbol, _Period, InpSlowMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
      
      if(g_FastMA_Handle == INVALID_HANDLE || g_SlowMA_Handle == INVALID_HANDLE) {
         Print("Error: Failed to create MA handles for base symbol.");
         return INIT_FAILED;
      }
      
      isInitialized = true;
      return INIT_SUCCEEDED; // EXIT HERE: Skip all Custom Symbol and Renko setup
   }
   // ----------------------------------------------
   // --- 1. HARD STATE RESET (CRITICAL FOR SYMBOL SWAPS) ---
   // Force all internal tracking variables to zero immediately.
   // This ensures no "ghost" data from the previous symbol persists.
   RenkoAnchorPrice      = 0;
   RenkoBoxHigh          = 0;
   RenkoBoxLow           = 0;
   LastCommittedBarTime  = 0;
   g_HardCommittedTime   = 0;
   g_LastClosePrice      = 0;
   g_CurrentATR          = 0;   // Clear cached ATR so it recalculates for new symbol
   g_LastHistoryDeals    = -1;  // Force history redraw
   g_LinesCleared        = false;
   TickVolBuffer         = 0;
   
   ArrayResize(g_RamRateBuffer, 0);
   ArrayResize(g_RamTickBuffer, 0);
   // --------------------------------------------------------

   string suffix = (InpCustomNameTag == "") ?
      ((InpBlockMode==BLOCK_MODE_ATR_PERCENT)?"_ATR":"_"+IntegerToString((int)InpBlockSizeValue)) : 
      "_"+InpCustomNameTag;
   
   CustomSymbol = _Symbol + suffix;
   UnderlyingSymbol = _Symbol;
   GV_Prefix = CustomSymbol; // Keeps Global Variables unique per symbol

   // Initialize Indicators
   if(InpBlockMode == BLOCK_MODE_ATR_PERCENT) {
      if(ATR_Handle != INVALID_HANDLE) IndicatorRelease(ATR_Handle); // Release old handle if exists
      ATR_Handle = iATR(_Symbol, InpATRTimeframe, InpATRPeriod);
      if(ATR_Handle == INVALID_HANDLE) {
         Print("Error: Failed to create ATR handle for ", _Symbol);
         return INIT_FAILED;
      }
   }
   
   // Calculate fresh block size immediately (using 0 passed as time forces fresh read)
   CurrentBlockSizePoint = CalculateBlockSize(0); 
   
   // --- SMART SYMBOL DETECTION LOGIC ---
   bool symbolExists = SymbolInfoInteger(CustomSymbol, SYMBOL_CUSTOM);
   bool successResume = false;
   
   // A. Try to Resume (Only if symbol exists and we are not forced to rebuild)
   if(symbolExists && !InpForceRebuild) {
       // Attempt to load previous state specific to THIS CustomSymbol
       if(LoadState() && LastCommittedBarTime > 0) {
           Print("Smart Init: Found existing symbol ", CustomSymbol, ". Resuming live feed.");
           ConnectHistoryToLive();
           successResume = true;
       } else {
           Print("Smart Init: Symbol ", CustomSymbol, " exists but state is invalid/stale. Rebuilding.");
           // If load fails, we MUST reset Anchor/Time again to be safe
           RenkoAnchorPrice = 0;
           LastCommittedBarTime = 0;
       }
   }
   
   // B. Fresh Build (New Symbol OR Resume Failed)
   if(!successResume) {
       if(symbolExists) {
           Print("Smart Init: Deleting old symbol data for ", CustomSymbol);
           CustomSymbolDelete(CustomSymbol); 
       }
       
       Print("Smart Init: Creating new custom symbol ", CustomSymbol);
       CustomSymbolCreate(CustomSymbol, "RenkoPro_v1", _Symbol);
       
       CustomSymbolSetInteger(CustomSymbol, SYMBOL_TRADE_MODE, (long)SYMBOL_TRADE_MODE_FULL); 
       CustomSymbolSetInteger(CustomSymbol, SYMBOL_DIGITS, (long)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
       CustomSymbolSetDouble(CustomSymbol, SYMBOL_POINT, SymbolInfoDouble(_Symbol, SYMBOL_POINT));
       CustomSymbolSetDouble(CustomSymbol, SYMBOL_TRADE_TICK_SIZE, SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE));
       SymbolSelect(CustomSymbol, true);

       // Explicitly ensure variables are clean for the build
       RenkoAnchorPrice = 0; 
       LastCommittedBarTime = 0;

       if(!BuildHistory()) return(INIT_FAILED);
       
       // Connect to live immediately after build to catch up any seconds lost during build
       ConnectHistoryToLive();
   }
   
   // --- CHART WINDOW MANAGEMENT ---
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
   
   Trade.SetExpertMagicNumber(InpMagicNumber);
  
   
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

   // --- 1. OPTIMIZED ATR FETCH ---
   // We update the ATR here (once per second) instead of inside every tick.
   if(InpBlockMode == BLOCK_MODE_ATR_PERCENT && ATR_Handle != INVALID_HANDLE) {
      double atrBuffer[];
      // Copy the latest closed bar ATR
      if(CopyBuffer(ATR_Handle, 0, 0, 1, atrBuffer) > 0) {
         g_CurrentATR = atrBuffer[0];
      }
   }

   // --- 2. DRAWING LOGIC (Standard) ---
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
         
         // Keep chart colors persistent
         ChartSetInteger(RenkoChartID, CHART_SHOW_ASK_LINE, InpShowAsk);
         ChartSetInteger(RenkoChartID, CHART_COLOR_ASK, InpAskColor);
         ChartSetInteger(RenkoChartID, CHART_SHOW_BID_LINE, InpShowBid);
         ChartSetInteger(RenkoChartID, CHART_COLOR_BID, InpBidColor);
         ChartSetInteger(RenkoChartID, CHART_SHOW_LAST_LINE, InpShowLast);
         ChartSetInteger(RenkoChartID, CHART_COLOR_LAST, InpLastColor);
      }
   }

   // --- 3. CONDITIONAL GUI UPDATE (Memory Optimization) ---
   // We use static variables to remember the last state.
   // We only burn CPU cycles converting strings if something actually changed.
   static int    lastDeals     = -1;
   static double lastBlockSize = -1;
   static double lastAnchor    = -1;
   
   if(g_LastHistoryDeals != lastDeals || 
      CurrentBlockSizePoint != lastBlockSize || 
      RenkoAnchorPrice != lastAnchor) 
   {
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
          histInfo,
          InpForceRebuild
       );
       // Update the static cache
       lastDeals     = g_LastHistoryDeals;
       lastBlockSize = CurrentBlockSizePoint;
       lastAnchor    = RenkoAnchorPrice;
   }
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
   
   // --- HIJACK: AUTO-TRADE MODE ---
   if(g_IsAutoTradeMode) {
      CheckTradeSignalsBase();
      return; // EXIT HERE: Stop Renko ticks from processing
   }
   // -------------------------------
   
   MqlTick tick;
   if(SymbolInfoTick(_Symbol, tick) && tick.bid > 0) {
      // --- ADDED ATR ADAPTIVE FETCH FROM ATTACHED FILE ---
      if(InpAdaptiveATRRefresh && InpBlockMode == BLOCK_MODE_ATR_PERCENT && ATR_Handle != INVALID_HANDLE)
      {
         if(GetTickCount() - g_LastATRFetchMs >= (ulong)MathMax(50, InpATRRefreshMs))
         {
            double atrBuffer[];
            if(CopyBuffer(ATR_Handle, 0, 0, 1, atrBuffer) > 0)
               g_CurrentATR = atrBuffer[0];
            g_LastATRFetchMs = GetTickCount();
         }
      }
      // ---------------------------------------------------

      UpdateMarketWatch();
      bool newBox = ProcessRenkoTick(tick.bid, TimeCurrent(), (long)tick.volume);
      if(newBox) {
         FlushRamToDisk(true);   // immediately write completed bricks
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
             continue;
             // Skip rare incomplete data
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
//| NEW: Robust Disk Flushing with Hard Cursor                       |
//+------------------------------------------------------------------+
void FlushRamToDisk(bool force = false)
{
   int total = ArraySize(g_RamRateBuffer);
   if(total == 0) return;
   
   if(!force && total < 50 && (GetMicrosecondCount() - g_LastFlushTime) < 250000)
      return;
   
   // Write all completed bricks at once
   CustomRatesUpdate(CustomSymbol, g_RamRateBuffer, total);
   CustomTicksAdd(CustomSymbol, g_RamTickBuffer);
   
   // Update hard cursor to the latest brick time
   g_HardCommittedTime = g_RamRateBuffer[total-1].time;
   
   SaveState();
   ArrayFree(g_RamRateBuffer);
   ArrayFree(g_RamTickBuffer);
   g_LastFlushTime = GetMicrosecondCount();
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
//| Auto Trading: MA Signal Check (Base Symbol with Spread Check)    |
//+------------------------------------------------------------------+
void CheckTradeSignalsBase()
{
   if(g_FastMA_Handle == INVALID_HANDLE || g_SlowMA_Handle == INVALID_HANDLE) return;

   // 1. Only allow one execution per candlestick
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == lastBarTime) return;

   // 2. Fetch the MA values
   double fastMA[2], slowMA[2];
   if(CopyBuffer(g_FastMA_Handle, 0, 1, 2, fastMA) < 2) return;
   if(CopyBuffer(g_SlowMA_Handle, 0, 1, 2, slowMA) < 2) return;

   // Index [0] is the older bar, Index [1] is the recently closed bar
   bool isBuySignal  = (fastMA[0] <= slowMA[0] && fastMA[1] > slowMA[1]);
   bool isSellSignal = (fastMA[0] >= slowMA[0] && fastMA[1] < slowMA[1]);

   // If there is no signal at all, just exit
   if(!isBuySignal && !isSellSignal) return;

   // 3. SPREAD CHECK LOGIC
   long currentSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(currentSpread > InpMaxSpreadPoints) {
       // We print a warning but do NOT update lastBarTime. 
       // This allows the bot to check again on the very next tick.
       Print("MA Crossover delayed: Current spread (", currentSpread, ") exceeds Max Spread (", InpMaxSpreadPoints, "). Waiting...");
       return; 
   }

   // 4. Execute the trade and lock the bar
   if(isBuySignal) {
       ExecuteTrade(1);
       lastBarTime = currentBarTime; // Lock out further trades for this candlestick
   }
   else if(isSellSignal) {
       ExecuteTrade(-1);
       lastBarTime = currentBarTime; // Lock out further trades for this candlestick
   }
}

//+------------------------------------------------------------------+
//| Auto Trading: Pure Stop-and-Reverse Execution                    |
//+------------------------------------------------------------------+
void ExecuteTrade(int direction) // 1 for Buy, -1 for Sell
{
   // STEP 1: CLOSE PRIOR TRADE IN THE OPPOSITE DIRECTION
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket)) {
         if(PositionGetString(POSITION_SYMBOL) == UnderlyingSymbol && 
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
            
            long currentType = PositionGetInteger(POSITION_TYPE);
            
            // If we have a Buy signal but a Sell is open -> Close the Sell
            if(direction == 1 && currentType == POSITION_TYPE_SELL) {
               Trade.PositionClose(ticket);
               Print("MA Crossover: Closed previous SELL trade.");
            }
            // If we have a Sell signal but a Buy is open -> Close the Buy
            else if(direction == -1 && currentType == POSITION_TYPE_BUY) {
               Trade.PositionClose(ticket);
               Print("MA Crossover: Closed previous BUY trade.");
            }
         }
      }
   }

   // STEP 2: CHECK IF WE ALREADY HAVE A TRADE IN THE NEW DIRECTION
   bool hasPosition = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket)) {
         if(PositionGetString(POSITION_SYMBOL) == UnderlyingSymbol && 
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
            
            long currentType = PositionGetInteger(POSITION_TYPE);
            if((direction == 1 && currentType == POSITION_TYPE_BUY) || 
               (direction == -1 && currentType == POSITION_TYPE_SELL)) {
               hasPosition = true; 
               break;
            }
         }
      }
   }

   // STEP 3: OPEN THE NEW TRADE
   if(!hasPosition) {
      double ask = SymbolInfoDouble(UnderlyingSymbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(UnderlyingSymbol, SYMBOL_BID);
      
      // Calculate the safest, affordable lot size
      double safeLots = GetSafeAndAffordableLots(InpLotSize, UnderlyingSymbol, direction);
      
      // Only execute if we can afford it
      if(safeLots > 0.0) {
         if(direction == 1) {
            Trade.Buy(safeLots, UnderlyingSymbol, ask, 0, 0, "MA Crossover Buy");
            Print("MA Crossover: Opened new BUY trade. Lots: ", safeLots);
         }
         else if(direction == -1) {
            Trade.Sell(safeLots, UnderlyingSymbol, bid, 0, 0, "MA Crossover Sell");
            Print("MA Crossover: Opened new SELL trade. Lots: ", safeLots);
         }
      } else {
         Print("MA Crossover: Not enough free margin to open trade. Skipping to avoid errors.");
      }
   }
}

//+------------------------------------------------------------------+
//| Helper: Calculate max affordable lots to pass MQL5 Validation    |
//+------------------------------------------------------------------+
double GetSafeAndAffordableLots(double desiredLots, string symbol, int direction)
{
   double minVolume  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxVolume  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double volumeStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   
   ENUM_ORDER_TYPE type = (direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double price = (direction == 1) ? SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID);

   // 1. Clamp to max broker limit
   double calcLots = desiredLots;
   if(calcLots > maxVolume) calcLots = maxVolume;

   // 2. Step down until we have enough margin
   int loop_guard = 0; // Prevent infinite loops
   while(calcLots >= minVolume && loop_guard < 1000)
   {
      loop_guard++;
      
      // Normalize to the broker's step size
      calcLots = MathRound(calcLots / volumeStep) * volumeStep;
      
      // Final clamp before checking margin
      if(calcLots < minVolume) return 0.0;

      double marginRequired = 0.0;
      if(OrderCalcMargin(type, symbol, calcLots, price, marginRequired))
      {
         // Do we have enough free margin? (Using 95% of free margin for safety)
         if(marginRequired <= AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.95)
         {
            return calcLots; // Found a valid, affordable lot size!
         }
      }
      
      // If we don't have enough margin, reduce by one step and try again
      calcLots -= volumeStep;
   }
   
   // If the loop finishes and we are here, we can't even afford the minimum lot size
   return 0.0; 
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|                  RenkoBuilderPro_GUI.mq5                         |
//|   Elastic Renko + RAM Disk + Trade Lines + Interactive Dashboard |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Renko Builder Pro"
#property link      "https://discord.com/channels/929723953415589918/929723953415589920"
#property version   "1.00"
#property description "Complete System: Elastic Renko, RAM Disk, Visuals & Dashboard"

#include <Trade\Trade.mqh>

//--- ENUMS
enum ENUM_START_MODE { MODE_DAYS_BACK, MODE_FIXED_DATE };
enum ENUM_BLOCK_MODE { BLOCK_MODE_POINTS, BLOCK_MODE_PIPS, BLOCK_MODE_ATR_PERCENT };

//--- INPUTS
input group "0. Performance & System"
input bool           InpUseRamDisk        = true;  // RAM Disk (State)
input bool           InpUseBatchWrite     = true; // Batch Write (Disk I/O Opt)
input bool           InpEnableLineDrawing = false; // Enable Trade Lines & History

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

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
input group "3. Visuals (Phantom)"
input color          InpUpColor           = clrLime;
input color          InpDnColor           = clrRed;
input int            InpPhantomWidth      = 1;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
input group "4. Visuals (Trade Lines)"
input bool           InpShowEntry         = true;
input color          InpEntryColor        = clrLime;
input bool           InpShowSL            = true;
input color          InpSLColor           = clrRed;
input bool           InpShowTP            = true;
input color          InpTPColor           = clrGreen;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
input group "5. Visuals (History)"
input bool           InpShowHistory       = true;
input color          InpHistWinColor      = clrBlue;
input color          InpHistLossColor     = clrRed;

//--- GLOBALS
CTrade   Trade;
string   UnderlyingSymbol = "";
string   CustomSymbol;
string   GV_Prefix;

//--- RENKO STATE
double   RenkoAnchorPrice = 0;
double   RenkoBoxHigh = 0;
double   RenkoBoxLow = 0;
bool     IsTrendUp = true;
datetime LastCommittedBarTime = 0;
datetime CurrentBlockStartTime = 0;
double   CurrentBlockSizePoint = 0;
long     RenkoChartID = 0;
int      ATR_Handle = INVALID_HANDLE;
bool     isInitialized = false;
long     TickVolBuffer = 0;

//--- RAM DISK CACHE (State)
double   RAM_Anchor = 0;
bool     RAM_Trend = true;
datetime RAM_LastTime = 0;
double   RAM_High = 0;
double   RAM_Low = 0;

//--- BATCH BUFFER CACHE (Data)
MqlRates g_RamRateBuffer[];
MqlTick  g_RamTickBuffer[];
ulong    g_LastFlushTime = 0;

//--- VISUAL CACHE
int      g_LastHistoryDeals = -1;
double   g_CachedATR = 0;
datetime g_LastATRTime = 0;
bool     g_LinesCleared = false;

//+------------------------------------------------------------------+
//| CLASS: INTERACTIVE DASHBOARD (Optimized: Anti-Lag)               |
//+------------------------------------------------------------------+
class CRenkoGUI
  {
private:
   string            m_prefix;
   int               m_x, m_y;
   int               m_w, m_h;
   bool              m_minimized;
   bool              m_dragging;
   int               m_drag_x, m_drag_y;
   color             c_bg, c_head, c_card, c_txt, c_lbl, c_warn;
public:
                     CRenkoGUI()
     {
      m_prefix="RenkoDash_";
      m_x=20;
      m_y=20;
      m_w=260;
      m_h=155;
      m_minimized=false;
      m_dragging=false;
      c_bg = C'30,35,40';
      c_head = C'40,80,160';
      c_card = C'40,45,50';
      c_txt = clrWhite;
      c_lbl = C'180,180,180';
      c_warn = C'220,180,60';
     }
                    ~CRenkoGUI() { Destroy(); }

   void              Create()
     {
      Destroy();
      CreateRect("BG", m_w, m_h, c_bg, c_bg);
      CreateRect("Head", m_w, 25, c_head, c_head);
      CreateLabel("Title", "RENKO BUILDER PRO", 10, 5, 9, clrWhite, true);
      CreateBtn("Min", "_", m_w-25, 2, 20, 20);
      int y = 35;
      CreateLabel("L_Mode", "Block Mode:", 10, y, 8, c_lbl);
      CreateLabel("V_Mode", "--", 100, y, 8, c_txt);
      y+=15;
      CreateLabel("L_Size", "Input Size:", 10, y, 8, c_lbl);
      CreateLabel("V_Size", "--", 100, y, 8, c_txt);
      y+=15;
      CreateLabel("L_Hist", "History:", 10, y, 8, c_lbl);
      CreateLabel("V_Hist", "--", 100, y, 8, c_txt);
      y+=15;
      CreateLabel("L_Reb", "Rebuild:", 10, y, 8, c_lbl);
      CreateLabel("V_Reb", "--", 100, y, 8, c_txt);
      y+=20;
      CreateRect("Div1", m_w-20, 1, C'60,65,70', C'60,65,70', 10, y);
      y+=10;
      CreateLabel("L_Act", "Actual Size:", 10, y, 8, c_lbl);
      CreateLabel("V_Act", "--", 100, y, 8, c_warn, true);
      y+=15;
      CreateLabel("L_Anc", "Anchor:", 10, y, 8, c_lbl);
      CreateLabel("V_Anc", "--", 100, y, 8, c_txt);
      UpdatePos();
      ChartRedraw();
     }

   void              Destroy() { ObjectsDeleteAll(0, m_prefix); }

   void              OnEvent(int id, long lparam, double dparam, string sparam)
     {
      if(id == CHARTEVENT_OBJECT_CLICK && sparam == m_prefix+"Min")
        {
         m_minimized = !m_minimized;
         UpdatePos();
         ChartRedraw();
        }
      else
         if(id == CHARTEVENT_MOUSE_MOVE)
           {
            int x = (int)lparam;
            int y = (int)dparam;
            int state = (int)StringToInteger(sparam);
            if((state & 1) == 1)
              {
               if(!m_dragging && x >= m_x && x <= m_x + m_w && y >= m_y && y <= m_y + 25)
                 {
                  m_dragging = true;
                  m_drag_x = x - m_x;
                  m_drag_y = y - m_y;
                  ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
                 }
               if(m_dragging)
                 {
                  int new_x = x - m_drag_x;
                  int new_y = y - m_drag_y;
                  if(new_x < 0)
                     new_x = 0;
                  if(new_y < 0)
                     new_y = 0;
                  if(new_x != m_x || new_y != m_y)
                    {
                     m_x = new_x;
                     m_y = new_y;
                     UpdatePos();
                     ChartRedraw();
                    }
                 }
              }
            else
              {
               if(m_dragging)
                 {
                  m_dragging = false;
                  ChartSetInteger(0, CHART_MOUSE_SCROLL, true);
                 }
              }
           }
     }

   void              Update(string mode, double inSize, double actSize, double anchor, string historyMsg, bool isRebuild)
     {
      if(m_minimized)
         return;
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
   void              UpdatePos()
     {
      int h = m_minimized ? 25 : m_h;
      SetGeom("BG", m_x, m_y, m_w, h);
      SetGeom("Head", m_x, m_y, m_w, 25);
      SetGeom("Title", m_x+10, m_y+5);
      SetGeom("Min", m_x+m_w-25, m_y+2);
      bool vis = !m_minimized;
      SetVis("L_Mode", vis);
      SetVis("V_Mode", vis);
      SetVis("L_Size", vis);
      SetVis("V_Size", vis);
      SetVis("L_Hist", vis);
      SetVis("V_Hist", vis);
      SetVis("L_Reb", vis);
      SetVis("V_Reb", vis);
      SetVis("Div1", vis);
      SetVis("L_Act", vis);
      SetVis("V_Act", vis);
      SetVis("L_Anc", vis);
      SetVis("V_Anc", vis);
      if(vis)
        {
         int y = m_y + 35;
         SetGeom("L_Mode", m_x+10, y);
         SetGeom("V_Mode", m_x+100, y);
         y+=15;
         SetGeom("L_Size", m_x+10, y);
         SetGeom("V_Size", m_x+100, y);
         y+=15;
         SetGeom("L_Hist", m_x+10, y);
         SetGeom("V_Hist", m_x+100, y);
         y+=15;
         SetGeom("L_Reb", m_x+10, y);
         SetGeom("V_Reb", m_x+100, y);
         y+=20;
         SetGeom("Div1", m_x+10, y);
         y+=10;
         SetGeom("L_Act", m_x+10, y);
         SetGeom("V_Act", m_x+100, y);
         y+=15;
         SetGeom("L_Anc", m_x+10, y);
         SetGeom("V_Anc", m_x+100, y);
        }
     }
   void              CreateRect(string n, int w, int h, color bg, color bord, int dx=0, int dy=0)
     {
      string obj = m_prefix+n;
      if(ObjectFind(0,obj)<0)
         ObjectCreate(0,obj,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,obj,OBJPROP_XSIZE,w);
      ObjectSetInteger(0,obj,OBJPROP_YSIZE,h);
      ObjectSetInteger(0,obj,OBJPROP_BGCOLOR,bg);
      ObjectSetInteger(0,obj,OBJPROP_BORDER_COLOR,bord);
      ObjectSetInteger(0,obj,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,obj,OBJPROP_ZORDER,10);
      if(dx!=0||dy!=0)
         SetGeom(n, m_x+dx, m_y+dy);
     }
   void              CreateLabel(string n, string txt, int dx, int dy, int sz, color c, bool bold=false)
     {
      string obj = m_prefix+n;
      if(ObjectFind(0,obj)<0)
         ObjectCreate(0,obj,OBJ_LABEL,0,0,0);
      ObjectSetString(0,obj,OBJPROP_TEXT,txt);
      ObjectSetInteger(0,obj,OBJPROP_FONTSIZE,sz);
      ObjectSetInteger(0,obj,OBJPROP_COLOR,c);
      ObjectSetString(0,obj,OBJPROP_FONT,bold?"Arial check":"Arial");
      ObjectSetInteger(0,obj,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,obj,OBJPROP_ZORDER,15);
      SetGeom(n, m_x+dx, m_y+dy);
     }
   void              CreateBtn(string n, string txt, int dx, int dy, int w, int h)
     {
      string obj = m_prefix+n;
      if(ObjectFind(0,obj)<0)
         ObjectCreate(0,obj,OBJ_BUTTON,0,0,0);
      ObjectSetString(0,obj,OBJPROP_TEXT,txt);
      ObjectSetInteger(0,obj,OBJPROP_XSIZE,w);
      ObjectSetInteger(0,obj,OBJPROP_YSIZE,h);
      ObjectSetInteger(0,obj,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,obj,OBJPROP_ZORDER,100);
      ObjectSetInteger(0,obj,OBJPROP_BGCOLOR,c_head);
      ObjectSetInteger(0,obj,OBJPROP_COLOR,c_txt);
      SetGeom(n, m_x+dx, m_y+dy);
     }
   void              SetGeom(string n, int x, int y, int w=-1, int h=-1)
     {
      string obj = m_prefix+n;
      ObjectSetInteger(0,obj,OBJPROP_XDISTANCE,x);
      ObjectSetInteger(0,obj,OBJPROP_YDISTANCE,y);
      if(w>0)
         ObjectSetInteger(0,obj,OBJPROP_XSIZE,w);
      if(h>0)
         ObjectSetInteger(0,obj,OBJPROP_YSIZE,h);
     }
   void              SetText(string n, string txt) { ObjectSetString(0,m_prefix+n,OBJPROP_TEXT,txt); }
   void              SetVis(string n, bool v) { ObjectSetInteger(0,m_prefix+n,OBJPROP_TIMEFRAMES, v?OBJ_ALL_PERIODS:OBJ_NO_PERIODS); }
  };

CRenkoGUI GUI;

struct DealInfo
  {
   ulong             ticket;
   long              posID;
   double            price;
   datetime          time;
   long              type;
   double            profit;
  };

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
double NormalizePrice(double price)
  {
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize == 0)
      return(NormalizeDouble(price, _Digits));
   return(MathRound(price / tickSize) * tickSize);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetPipSize()
  {
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return (digits == 3 || digits == 5) ? point * 10 : point;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double CalculateBlockSize(datetime timeRef)
  {
   double size = 0;
   if(InpBlockMode == BLOCK_MODE_ATR_PERCENT)
     {
      if(ATR_Handle == INVALID_HANDLE)
         return 100 * _Point;
      long atrPeriodSeconds = PeriodSeconds(InpATRTimeframe);
      datetime currentBarTime = (datetime)(timeRef - (timeRef % atrPeriodSeconds));
      if(currentBarTime > g_LastATRTime || g_CachedATR == 0)
        {
         double atrBuffer[];
         if(CopyBuffer(ATR_Handle, 0, 0, 1, atrBuffer) > 0)
           {
            g_CachedATR = atrBuffer[0];
            g_LastATRTime = currentBarTime;
           }
        }
      double calculatedSize = g_CachedATR * (InpBlockSizeValue / 100.0);
      if(calculatedSize < _Point)
         calculatedSize = _Point;
      size = NormalizePrice(calculatedSize);
     }
   else
      if(InpBlockMode == BLOCK_MODE_POINTS)
         size = InpBlockSizeValue * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      else
         if(InpBlockMode == BLOCK_MODE_PIPS)
            size = InpBlockSizeValue * GetPipSize();
         else
            size = InpBlockSizeValue * _Point;
   return size;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SaveState()
  {
   if(InpUseRamDisk)
     {
      RAM_Anchor = RenkoAnchorPrice;
      RAM_Trend = IsTrendUp;
      RAM_LastTime = LastCommittedBarTime;
      RAM_High = RenkoBoxHigh;
      RAM_Low = RenkoBoxLow;
     }
   else
     {
      GlobalVariableSet(GV_Prefix + "_Anchor", RenkoAnchorPrice);
      GlobalVariableSet(GV_Prefix + "_Trend", (double)IsTrendUp);
      GlobalVariableSet(GV_Prefix + "_LastTime", (double)LastCommittedBarTime);
      GlobalVariableSet(GV_Prefix + "_High", RenkoBoxHigh);
      GlobalVariableSet(GV_Prefix + "_Low", RenkoBoxLow);
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool LoadState()
  {
   if(InpUseRamDisk)
     {
      if(RAM_Anchor == 0)
         return false;
      RenkoAnchorPrice = RAM_Anchor;
      IsTrendUp = RAM_Trend;
      LastCommittedBarTime = RAM_LastTime;
      RenkoBoxHigh = RAM_High;
      RenkoBoxLow = RAM_Low;
      return true;
     }
   else
     {
      if(!GlobalVariableCheck(GV_Prefix + "_Anchor"))
         return false;
      RenkoAnchorPrice = GlobalVariableGet(GV_Prefix + "_Anchor");
      IsTrendUp = (bool)GlobalVariableGet(GV_Prefix + "_Trend");
      LastCommittedBarTime = (datetime)GlobalVariableGet(GV_Prefix + "_LastTime");
      if(GlobalVariableCheck(GV_Prefix + "_High"))
         RenkoBoxHigh = GlobalVariableGet(GV_Prefix + "_High");
      if(GlobalVariableCheck(GV_Prefix + "_Low"))
         RenkoBoxLow = GlobalVariableGet(GV_Prefix + "_Low");
      return true;
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void UpdatePhantomBar(double currentPrice)
  {
   long currID = ChartFirst();
   while(currID >= 0)
     {
      if(ChartSymbol(currID) == CustomSymbol)
        {
         double phantomOpen  = RenkoAnchorPrice;
         double phantomClose = currentPrice;
         color barColor = (phantomClose >= phantomOpen) ? InpUpColor : InpDnColor;
         string name = "PhantomRenko";
         if(ObjectFind(RenkoChartID, name) < 0)
           {
            ObjectCreate(RenkoChartID, name, OBJ_RECTANGLE, 0, 0, 0, 0, 0);
            ObjectSetInteger(RenkoChartID, name, OBJPROP_BACK, false);
            ObjectSetInteger(RenkoChartID, name, OBJPROP_WIDTH, InpPhantomWidth);
            ObjectSetInteger(RenkoChartID, name, OBJPROP_FILL, true);
           }
         datetime tStart = LastCommittedBarTime + 60;
         datetime tEnd = tStart + 60;
         ObjectSetInteger(RenkoChartID, name, OBJPROP_TIME, 0, tStart);
         ObjectSetDouble(RenkoChartID, name, OBJPROP_PRICE, 0, phantomOpen);
         ObjectSetInteger(RenkoChartID, name, OBJPROP_TIME, 1, tEnd);
         ObjectSetDouble(RenkoChartID, name, OBJPROP_PRICE, 1, phantomClose);
         ObjectSetInteger(RenkoChartID, name, OBJPROP_COLOR, barColor);
         ChartRedraw(RenkoChartID);
        }
      currID = ChartNext(currID);
     }
  }

//+------------------------------------------------------------------+
//| BATCH WRITE LOGIC (New)                                          |
//+------------------------------------------------------------------+
void FlushRamToDisk(bool force = false)
  {
   int total = ArraySize(g_RamRateBuffer);
   if(total == 0)
      return;

// Gatekeeper: Only write if buffer is full (50 bars) OR time threshold met (250ms)
   if(!force)
     {
      if(total < 50 && (GetMicrosecondCount() - g_LastFlushTime) < 250000)
         return;
     }

// 1. Commit to Disk
   CustomRatesUpdate(CustomSymbol, g_RamRateBuffer, total);
   CustomTicksAdd(CustomSymbol, g_RamTickBuffer);

// 2. Clear Buffer
   ArrayResize(g_RamRateBuffer, 0);
   ArrayResize(g_RamTickBuffer, 0);

// 3. Update State
   SaveState();
   g_LastFlushTime = GetMicrosecondCount();

   if(RenkoChartID > 0)
      ChartRedraw(RenkoChartID);
  }

//+------------------------------------------------------------------+
//| RENKO CORE LOGIC (Commit) - Updated for Batching                 |
//+------------------------------------------------------------------+
void PushRenkoBar(double open, double close, double high, double low, datetime barTime, long volume)
  {
// Common Time Calc
   datetime newBarTime = barTime;
   if(LastCommittedBarTime == 0)
      LastCommittedBarTime = newBarTime - 60;
   if(newBarTime <= LastCommittedBarTime)
      newBarTime = LastCommittedBarTime + 1;
   LastCommittedBarTime = newBarTime;

// 1. Prepare Data
   MqlRates rate;
   rate.time = newBarTime;
   rate.open = NormalizePrice(open);
   rate.close= NormalizePrice(close);
   if(InpShowWicks)
     {
      rate.high = MathMax(high, MathMax(open, close));
      rate.low  = MathMin(low,  MathMin(open, close));
     }
   else
     {
      rate.high = MathMax(open, close);
      rate.low  = MathMin(open, close);
     }
   rate.tick_volume = (volume > 0) ? volume : 1;
   rate.spread = 0;
   rate.real_volume = 0;

   MqlTick renkoTick;
   renkoTick.time = newBarTime;
   renkoTick.time_msc = (long)newBarTime * 1000;
   renkoTick.bid = rate.close;
   renkoTick.ask = rate.close + (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID));
   renkoTick.flags = TICK_FLAG_BID | TICK_FLAG_ASK;

// 2. Clear Phantom from all charts (Visual Logic)
   long currID = ChartFirst();
   while(currID >= 0)
     {
      if(ChartSymbol(currID) == CustomSymbol)
        {
         ObjectDelete(currID, "PhantomRenko");
        }
      currID = ChartNext(currID);
     }

// 3. STORAGE LOGIC
   if(InpUseBatchWrite)
     {
      // --- BATCH MODE (BUFFERED) ---
      int s = ArraySize(g_RamRateBuffer);
      ArrayResize(g_RamRateBuffer, s+1);
      ArrayResize(g_RamTickBuffer, s+1);
      g_RamRateBuffer[s] = rate;
      g_RamTickBuffer[s] = renkoTick;
      // State is saved in FlushRamToDisk
     }
   else
     {
      // --- DIRECT MODE (ORIGINAL) ---
      MqlRates rates[1];
      rates[0] = rate;
      MqlTick ticks[1];
      ticks[0] = renkoTick;
      CustomRatesUpdate(CustomSymbol, rates, 1);
      CustomTicksAdd(CustomSymbol, ticks);
      SaveState();
      if(RenkoChartID > 0)
         ChartRedraw(RenkoChartID);
     }
  }

//+------------------------------------------------------------------+
//| RENKO PROCESS LOOP                                               |
//+------------------------------------------------------------------+
bool ProcessRenkoTick(double price, datetime tickTime, long tickVol)
  {
   if(RenkoAnchorPrice == 0)
     {
      RenkoAnchorPrice = NormalizePrice(price);
      RenkoBoxHigh = RenkoAnchorPrice;
      RenkoBoxLow = RenkoAnchorPrice;
      CurrentBlockStartTime = tickTime;
      TickVolBuffer = tickVol;
      return false;
     }

   RenkoBoxHigh = MathMax(RenkoBoxHigh, price);
   RenkoBoxLow  = MathMin(RenkoBoxLow, price);
   TickVolBuffer += tickVol;
   if(CurrentBlockStartTime == 0)
      CurrentBlockStartTime = tickTime;

   CurrentBlockSizePoint = CalculateBlockSize(tickTime);
   double BS = CurrentBlockSizePoint;
   if(BS < _Point)
      BS = _Point;

   double upTarget   = NormalizePrice(RenkoAnchorPrice + BS);
   double downTarget = NormalizePrice(RenkoAnchorPrice - BS);
   double revUpTarget   = NormalizePrice(RenkoAnchorPrice + (2 * BS));
   double revDownTarget = NormalizePrice(RenkoAnchorPrice - (2 * BS));

   bool boxCreated = false;
   if(IsTrendUp)
     {
      if(price >= upTarget - (_Point/2))
        {
         PushRenkoBar(RenkoAnchorPrice, upTarget, RenkoBoxHigh, RenkoBoxLow, CurrentBlockStartTime, TickVolBuffer);
         RenkoAnchorPrice = upTarget;
         RenkoBoxHigh = RenkoAnchorPrice;
         RenkoBoxLow = RenkoAnchorPrice;
         CurrentBlockStartTime = 0;
         TickVolBuffer = 0;
         boxCreated = true;
        }
      else
         if(price <= revDownTarget + (_Point/2))
           {
            double open  = NormalizePrice(RenkoAnchorPrice - BS);
            double close = NormalizePrice(RenkoAnchorPrice - (2 * BS));
            PushRenkoBar(open, close, RenkoBoxHigh, RenkoBoxLow, CurrentBlockStartTime, TickVolBuffer);
            RenkoAnchorPrice = close;
            IsTrendUp = false;
            RenkoBoxHigh = RenkoAnchorPrice;
            RenkoBoxLow = RenkoAnchorPrice;
            CurrentBlockStartTime = 0;
            TickVolBuffer = 0;
            boxCreated = true;
           }
     }
   else
     {
      if(price <= downTarget + (_Point/2))
        {
         PushRenkoBar(RenkoAnchorPrice, downTarget, RenkoBoxHigh, RenkoBoxLow, CurrentBlockStartTime, TickVolBuffer);
         RenkoAnchorPrice = downTarget;
         RenkoBoxHigh = RenkoAnchorPrice;
         RenkoBoxLow = RenkoAnchorPrice;
         CurrentBlockStartTime = 0;
         TickVolBuffer = 0;
         boxCreated = true;
        }
      else
         if(price >= revUpTarget - (_Point/2))
           {
            double open  = NormalizePrice(RenkoAnchorPrice + BS);
            double close = NormalizePrice(RenkoAnchorPrice + (2 * BS));
            PushRenkoBar(open, close, RenkoBoxHigh, RenkoBoxLow, CurrentBlockStartTime, TickVolBuffer);
            RenkoAnchorPrice = close;
            IsTrendUp = true;
            RenkoBoxHigh = RenkoAnchorPrice;
            RenkoBoxLow = RenkoAnchorPrice;
            CurrentBlockStartTime = 0;
            TickVolBuffer = 0;
            boxCreated = true;
           }
     }
   return boxCreated;
  }

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
bool BuildHistory()
  {
   CustomRatesDelete(CustomSymbol, 0, LONG_MAX);
   CustomTicksDelete(CustomSymbol, 0, LONG_MAX);
   ChartRedraw(RenkoChartID);

   RenkoAnchorPrice = 0;
   LastCommittedBarTime = 0;
   datetime start = (InpStartMode == MODE_DAYS_BACK) ? TimeCurrent() - (InpHistoryDays * 86400) : InpFixedStartDate;
   int retry = 0;
   MqlRates src[];
   int total = 0;

   while(retry < 3)
     {
      total = CopyRates(_Symbol, PERIOD_M1, start, TimeCurrent(), src);
      if(total > 100)
         break;
      Print("Waiting for history data... Attempt: ", retry+1);
      Sleep(1000);
      retry++;
     }

   if(total == 0)
     {
      Print("Error: Could not load M1 history.");
      return false;
     }

   if(total > 0)
     {
      for(int i=0; i<total; i++)
        {
         long vol = src[i].tick_volume/3;
         if(vol<1)
            vol=1;
         ProcessRenkoTick(src[i].open, src[i].time, vol);
         if(src[i].close > src[i].open)
           {
            ProcessRenkoTick(src[i].low, src[i].time, vol);
            ProcessRenkoTick(src[i].high, src[i].time, vol);
           }
         else
           {
            ProcessRenkoTick(src[i].high, src[i].time, vol);
            ProcessRenkoTick(src[i].low, src[i].time, vol);
           }
         ProcessRenkoTick(src[i].close, src[i].time, vol);
        }
     }

// FLUSH BATCHED HISTORY (Crucial step)
   if(InpUseBatchWrite)
      FlushRamToDisk(true);
   else
      SaveState();

   if(RenkoChartID > 0)
     {
      ChartSetSymbolPeriod(RenkoChartID, CustomSymbol, PERIOD_M1);
      ChartRedraw(RenkoChartID);
     }
   return true;
  }

void ConnectHistoryToLive() { BuildHistory(); }

//+------------------------------------------------------------------+
//| Main Functions                                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   string suffix = (InpCustomNameTag == "") ? ((InpBlockMode==BLOCK_MODE_ATR_PERCENT)?"_ATR":"_"+IntegerToString((int)InpBlockSizeValue)) : "_"+InpCustomNameTag;
   CustomSymbol = _Symbol + suffix;
   UnderlyingSymbol = _Symbol;
   GV_Prefix = CustomSymbol;

   if(InpBlockMode == BLOCK_MODE_ATR_PERCENT)
     {
      ATR_Handle = iATR(_Symbol, InpATRTimeframe, InpATRPeriod);
      if(ATR_Handle == INVALID_HANDLE)
         return INIT_FAILED;
     }

   CurrentBlockSizePoint = CalculateBlockSize(TimeCurrent());
   if(SymbolInfoInteger(CustomSymbol, SYMBOL_CUSTOM) && InpForceRebuild)
      CustomSymbolDelete(CustomSymbol);
   if(!SymbolInfoInteger(CustomSymbol, SYMBOL_CUSTOM))
     {
      CustomSymbolCreate(CustomSymbol, "RenkoPro", _Symbol);
      CustomSymbolSetInteger(CustomSymbol, SYMBOL_TRADE_MODE, (long)SYMBOL_TRADE_MODE_FULL);
      CustomSymbolSetInteger(CustomSymbol, SYMBOL_DIGITS, (long)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
      CustomSymbolSetDouble(CustomSymbol, SYMBOL_POINT, SymbolInfoDouble(_Symbol, SYMBOL_POINT));
      CustomSymbolSetDouble(CustomSymbol, SYMBOL_TRADE_TICK_SIZE, SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE));
      SymbolSelect(CustomSymbol, true);
      BuildHistory();
     }
   else
     {
      if(!LoadState())
         BuildHistory();
      else
         ConnectHistoryToLive();
     }

   RenkoChartID = 0;
   long currID = ChartFirst();
   while(currID >= 0)
     {
      if(ChartSymbol(currID) == CustomSymbol)
        {
         RenkoChartID = currID;
         break;
        }
      currID = ChartNext(currID);
     }
   if(RenkoChartID == 0)
      RenkoChartID = ChartOpen(CustomSymbol, PERIOD_M1);
   if(RenkoChartID > 0)
     {
      ChartSetInteger(RenkoChartID, CHART_MODE, CHART_CANDLES);
      ChartRedraw(RenkoChartID);
     }

   GUI.Create();
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   isInitialized = true;
   EventSetTimer(1);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   CleanUpRenkoChart();
   GUI.Destroy();
   if(InpUseBatchWrite)
      FlushRamToDisk(true); // Force flush
   if(RenkoChartID > 0)
      ObjectDelete(RenkoChartID, "PhantomRenko");
   if(ATR_Handle != INVALID_HANDLE)
      IndicatorRelease(ATR_Handle);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTimer()
  {
   if(!isInitialized || RenkoChartID <= 0)
      return;

   if(InpEnableLineDrawing)
     {
      DrawActiveTradeLines();
      if(InpShowHistory)
        {
         int currentDeals = HistoryDealsTotal();
         if(currentDeals != g_LastHistoryDeals)
           {
            DrawHistoryTrendLines();
            g_LastHistoryDeals = currentDeals;
           }
        }
     }
   else
      if(!g_LinesCleared)
        {
         CleanUpRenkoChart();
         g_LinesCleared = true;
        }

   string histInfo = (InpStartMode == MODE_DAYS_BACK) ? IntegerToString(InpHistoryDays) + " Days" : TimeToString(InpFixedStartDate, TIME_DATE);
   GUI.Update(EnumToString(InpBlockMode), InpBlockSizeValue, CurrentBlockSizePoint, RenkoAnchorPrice, histInfo, InpForceRebuild);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTrade()
  {
   if(InpEnableLineDrawing)
     {
      DrawActiveTradeLines();
      g_LastHistoryDeals = -1;
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   GUI.OnEvent(id, lparam, dparam, sparam);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!isInitialized)
      return;
   MqlTick tick;
   if(SymbolInfoTick(_Symbol, tick))
     {
      if(tick.bid <= 0)
         return;
      long vol = (tick.volume > 0) ? (long)tick.volume : 1;

      int loopSafe = 0;
      bool barCreated = false;
      while(loopSafe < 1000)
        {
         if(ProcessRenkoTick(tick.bid, TimeCurrent(), vol))
           {
            barCreated = true;
            loopSafe++;
            vol = 0;
           }
         else
            break;
        }

      // Batch Flushing
      if(InpUseBatchWrite)
         FlushRamToDisk(false);

      if(RenkoChartID > 0)
        {
         if(barCreated && !InpUseBatchWrite)
            ChartRedraw(RenkoChartID); // Redraw immediately only if direct mode
         UpdatePhantomBar(tick.bid);
        }
     }
  }

//+------------------------------------------------------------------+
//| VISUAL DRAWING FUNCTIONS (Same as before)                        |
//+------------------------------------------------------------------+
void DrawActiveTradeLines()
  {
   if(!InpEnableLineDrawing || RenkoChartID <= 0)
      return;

   string activeTickets = ";";
   string accountCurrency = AccountInfoString(ACCOUNT_CURRENCY); // Get currency (e.g., USD)

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetString(POSITION_SYMBOL) == UnderlyingSymbol)
           {

            activeTickets += (string)ticket + ";";
            long type   = PositionGetInteger(POSITION_TYPE);
            double open = PositionGetDouble(POSITION_PRICE_OPEN);
            double sl   = PositionGetDouble(POSITION_SL);
            double tp   = PositionGetDouble(POSITION_TP);
            double vol  = PositionGetDouble(POSITION_VOLUME);
            double calc_profit = 0.0;

            // A. Entry Line
            if(InpShowEntry)
              {
               string name = "OpenLine_" + (string)ticket;
               if(ObjectFind(RenkoChartID, name) < 0)
                 {
                  ObjectCreate(RenkoChartID, name, OBJ_HLINE, 0, 0, open);
                  ObjectSetInteger(RenkoChartID, name, OBJPROP_COLOR, InpEntryColor);
                  ObjectSetInteger(RenkoChartID, name, OBJPROP_STYLE, STYLE_DOT);
                 }
               // Detailed Entry Tooltip
               string typeStr = (type == POSITION_TYPE_BUY) ? "BUY" : "SELL";
               ObjectSetString(RenkoChartID, name, OBJPROP_TOOLTIP,
                               StringFormat("%s #%d\nVolume: %.2f\nPrice: %s", typeStr, ticket, vol, DoubleToString(open, _Digits)));
              }

            // B. Stop Loss (SL)
            if(InpShowSL && sl > 0)
              {
               string name = "SLLine_" + (string)ticket;
               if(ObjectFind(RenkoChartID, name) < 0)
                 {
                  ObjectCreate(RenkoChartID, name, OBJ_HLINE, 0, 0, sl);
                  ObjectSetInteger(RenkoChartID, name, OBJPROP_COLOR, InpSLColor);
                  ObjectSetInteger(RenkoChartID, name, OBJPROP_STYLE, STYLE_DASHDOT);
                 }
               else
                  if(MathAbs(ObjectGetDouble(RenkoChartID, name, OBJPROP_PRICE) - sl) > _Point)
                    {
                     ObjectSetDouble(RenkoChartID, name, OBJPROP_PRICE, sl);
                    }

               // Calculate Exact Risk in Currency
               if(OrderCalcProfit((ENUM_ORDER_TYPE)type, UnderlyingSymbol, vol, open, sl, calc_profit))
                 {
                  int pts = (int)(MathAbs(open - sl) / _Point);
                  string tooltip = StringFormat("SL Risk: %.2f %s\nDistance: %d pts\nPrice: %s",
                                                calc_profit, accountCurrency, pts, DoubleToString(sl, _Digits));
                  ObjectSetString(RenkoChartID, name, OBJPROP_TOOLTIP, tooltip);
                 }
              }

            // C. Take Profit (TP)
            if(InpShowTP && tp > 0)
              {
               string name = "TPLine_" + (string)ticket;
               if(ObjectFind(RenkoChartID, name) < 0)
                 {
                  ObjectCreate(RenkoChartID, name, OBJ_HLINE, 0, 0, tp);
                  ObjectSetInteger(RenkoChartID, name, OBJPROP_COLOR, InpTPColor);
                  ObjectSetInteger(RenkoChartID, name, OBJPROP_STYLE, STYLE_DASHDOT);
                 }
               else
                  if(MathAbs(ObjectGetDouble(RenkoChartID, name, OBJPROP_PRICE) - tp) > _Point)
                    {
                     ObjectSetDouble(RenkoChartID, name, OBJPROP_PRICE, tp);
                    }

               // Calculate Potential Profit in Currency
               if(OrderCalcProfit((ENUM_ORDER_TYPE)type, UnderlyingSymbol, vol, open, tp, calc_profit))
                 {
                  int pts = (int)(MathAbs(open - tp) / _Point);
                  string tooltip = StringFormat("TP Target: +%.2f %s\nDistance: %d pts\nPrice: %s",
                                                calc_profit, accountCurrency, pts, DoubleToString(tp, _Digits));
                  ObjectSetString(RenkoChartID, name, OBJPROP_TOOLTIP, tooltip);
                 }
              }
           }
        }
     }

// Sweep (Delete lines for closed trades)
   int totalObj = ObjectsTotal(RenkoChartID, 0, -1);
   for(int k = totalObj - 1; k >= 0; k--)
     {
      string name = ObjectName(RenkoChartID, k, 0, -1);
      if(StringFind(name, "OpenLine_") == 0 || StringFind(name, "SLLine_") == 0 || StringFind(name, "TPLine_") == 0)
        {
         string parts[];
         StringSplit(name, '_', parts);
         if(ArraySize(parts) > 1)
           {
            string ticketID = parts[1];
            if(StringFind(activeTickets, ";" + ticketID + ";") < 0)
              {
               ObjectDelete(RenkoChartID, name);
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| VISUAL 3: History Trends (Optimized O(N)) - Enhanced Tooltips    |
//+------------------------------------------------------------------+
void DrawHistoryTrendLines()
  {
   if(!InpShowHistory || !InpEnableLineDrawing || RenkoChartID <= 0)
      return;

   datetime end = TimeCurrent();
   datetime start = end - (InpHistoryDays * 24 * 3600);
   string accountCurrency = AccountInfoString(ACCOUNT_CURRENCY);

   if(!HistorySelect(start, end))
      return;
   int totalDeals = HistoryDealsTotal();

   DealInfo openDeals[];
   ArrayResize(openDeals, totalDeals);
   int openCount = 0;

   for(int i = 0; i < totalDeals; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      long entryType = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      long posID = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
      string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);

      if(symbol != UnderlyingSymbol)
         continue;

      // Store ENTRY deals
      if(entryType == DEAL_ENTRY_IN)
        {
         openDeals[openCount].ticket = ticket;
         openDeals[openCount].posID = posID;
         openDeals[openCount].price = HistoryDealGetDouble(ticket, DEAL_PRICE);
         openDeals[openCount].time = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         openDeals[openCount].type = HistoryDealGetInteger(ticket, DEAL_TYPE);
         openCount++;
        }
      // Process EXIT deals
      else
         if(entryType == DEAL_ENTRY_OUT)
           {
            string lineName = "HistTrd_" + (string)posID;
            string arrowIn = "ArrIn_" + (string)posID;
            string arrowOut = "ArrOut_" + (string)posID;

            if(ObjectFind(RenkoChartID, lineName) >= 0)
               continue;

            // Find matching Entry
            int matchIdx = -1;
            for(int k = 0; k < openCount; k++)
              {
               if(openDeals[k].posID == posID)
                 {
                  matchIdx = k;
                  break;
                 }
              }

            double priceIn = 0;
            datetime timeIn = 0;
            long dealType = -1;

            if(matchIdx != -1)
              {
               priceIn = openDeals[matchIdx].price;
               timeIn = openDeals[matchIdx].time;
               dealType = openDeals[matchIdx].type;
              }
            else
              {
               // Rare Case: Deal opened before history start
               if(HistorySelectByPosition(posID))
                 {
                  int deals = HistoryDealsTotal();
                  for(int d=0; d<deals; d++)
                    {
                     ulong dt = HistoryDealGetTicket(d);
                     if(HistoryDealGetInteger(dt, DEAL_ENTRY) == DEAL_ENTRY_IN)
                       {
                        priceIn = HistoryDealGetDouble(dt, DEAL_PRICE);
                        timeIn = (datetime)HistoryDealGetInteger(dt, DEAL_TIME);
                        dealType = HistoryDealGetInteger(dt, DEAL_TYPE);
                        break;
                       }
                    }
                  HistorySelect(start, end); // Restore context
                 }
              }

            if(timeIn > 0)
              {
               double priceOut = HistoryDealGetDouble(ticket, DEAL_PRICE);
               datetime timeOut = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
               double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
               int points = (int)(MathAbs(priceOut - priceIn) / _Point);

               // 1. Create Trend Line
               ObjectCreate(RenkoChartID, lineName, OBJ_TREND, 0, timeIn, priceIn, timeOut, priceOut);
               bool isWin = (profit >= 0);
               color c = isWin ? InpHistWinColor : InpHistLossColor;

               ObjectSetInteger(RenkoChartID, lineName, OBJPROP_COLOR, c);
               ObjectSetInteger(RenkoChartID, lineName, OBJPROP_STYLE, STYLE_DOT);
               ObjectSetInteger(RenkoChartID, lineName, OBJPROP_RAY_RIGHT, false);

               string typeStr = (dealType == DEAL_TYPE_BUY) ? "BUY" : "SELL";

               // --- DETAILED TOOLTIP ---
               string tooltip = StringFormat("%s #%d\nIn: %s @ %s\nOut: %s @ %s\nProfit: %.2f %s\nPoints: %d",
                                             typeStr, posID,
                                             TimeToString(timeIn, TIME_DATE|TIME_MINUTES), DoubleToString(priceIn, _Digits),
                                             TimeToString(timeOut, TIME_DATE|TIME_MINUTES), DoubleToString(priceOut, _Digits),
                                             profit, accountCurrency, points);

               ObjectSetString(RenkoChartID, lineName, OBJPROP_TOOLTIP, tooltip);

               // 2. Arrow In
               if(ObjectCreate(RenkoChartID, arrowIn, OBJ_ARROW, 0, timeIn, priceIn))
                 {
                  ObjectSetInteger(RenkoChartID, arrowIn, OBJPROP_ARROWCODE, 159);
                  ObjectSetInteger(RenkoChartID, arrowIn, OBJPROP_COLOR, c);
                  ObjectSetString(RenkoChartID, arrowIn, OBJPROP_TOOLTIP, "Open " + typeStr + "\n" + TimeToString(timeIn));
                 }

               // 3. Arrow Out
               if(ObjectCreate(RenkoChartID, arrowOut, OBJ_ARROW, 0, timeOut, priceOut))
                 {
                  ObjectSetInteger(RenkoChartID, arrowOut, OBJPROP_ARROWCODE, 159);
                  ObjectSetInteger(RenkoChartID, arrowOut, OBJPROP_COLOR, c);
                  ObjectSetString(RenkoChartID, arrowOut, OBJPROP_TOOLTIP, "Close " + typeStr + "\nP: " + DoubleToString(profit, 2) + " " + accountCurrency);
                 }
              }
           }
     }
   ChartRedraw(RenkoChartID);
  }

//+------------------------------------------------------------------+
//| Clean up                                                         |
//+------------------------------------------------------------------+
void CleanUpRenkoChart()
  {
   if(RenkoChartID <= 0)
      return;
   ObjectsDeleteAll(RenkoChartID, "HistTrd_");
   ObjectsDeleteAll(RenkoChartID, "ArrIn_");
   ObjectsDeleteAll(RenkoChartID, "ArrOut_");
   ObjectsDeleteAll(RenkoChartID, "OpenLine_");
   ObjectsDeleteAll(RenkoChartID, "SLLine_");
   ObjectsDeleteAll(RenkoChartID, "TPLine_");
   ChartRedraw(RenkoChartID);
  }
  
//+------------------------------------------------------------------+

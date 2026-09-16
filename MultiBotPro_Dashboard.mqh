#ifndef __MULTIBOTPRO_DASHBOARD_MQH__
#define __MULTIBOTPRO_DASHBOARD_MQH__
//+------------------------------------------------------------------+
//|                                        MultiBotPro_Dashboard.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://discord.com/channels/929723953415589918/929723953415589920"

// 1. INCLUDE DEFINITIONS (Enums & Structs)
#include "MultiBotPro_Defines.mqh"

#define DASH_HEARTBEAT_DOT  "Dash_Heartbeat_Dot"
#define DASH_HEARTBEAT_TEXT "Dash_Heartbeat_Text"
#define DASH_SETTINGS_PREFIX "Set2_"

// Dash_Scale is defined centrally in Globals.mqh
int S_Dash(int value) { return (int)MathRound(value * Dash_Scale); }

int PanelBackgroundZOrder()
{
   return 150;
}

int PanelForegroundZOrder()
{
   return 200;
}

color PanelBackgroundColor(const color fallback)
{
   return fallback;
}

void ApplyPanelChartForegroundMode()
{
   ChartSetInteger(0, CHART_FOREGROUND, false);
}

void ApplyPanelBackgroundAppearance(const string name, const color fallbackBg, const color fallbackBorder)
{
   color bgColor = PanelBackgroundColor(fallbackBg);
   color borderColor = fallbackBorder;

   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
   ObjectSetInteger(0, name, OBJPROP_COLOR, borderColor);
}

void ApplyPanelBackgroundLayer(const string name)
{
   ApplyPanelChartForegroundMode();

   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, PanelBackgroundZOrder());
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
}

int GetDashboardHeartbeatDotSize() { return S_Dash(6); }
int GetDashboardHeartbeatDotX() { return DashboardX + S_Dash(250); }
int GetDashboardHeartbeatDotY() { return DashboardY + S_Dash(30); }
int GetDashboardHeartbeatTextX() { return DashboardX + S_Dash(262); }
int GetDashboardHeartbeatTextY() { return DashboardY + S_Dash(24); }
int GetDashboardBitmapSize()
{
   int topPadding = S_Dash(5);
   int timeRowY = S_Dash(25);
   int minSize = MathMax(8, S_Dash(12));
   int maxFit = timeRowY - topPadding - S_Dash(2);
   if(maxFit < minSize)
      maxFit = minSize;

   int preferred = S_Dash(20);
   return MathMin(preferred, maxFit);
}
string GetDashboardBitmapResource()
{
   return "Experts\\MultiBotPro\\romeo.bmp";
}
void ApplyDashboardBitmapLayout(const int x, const int y)
{
   int dashboardBitmapSize = GetDashboardBitmapSize();
   string bitmapResource = GetDashboardBitmapResource();
   ObjectSetInteger(0, "Dash_RobotPic", OBJPROP_XDISTANCE, x + S_Dash(10));
   ObjectSetInteger(0, "Dash_RobotPic", OBJPROP_YDISTANCE, y + S_Dash(5));
   ObjectSetInteger(0, "Dash_RobotPic", OBJPROP_XSIZE, dashboardBitmapSize);
   ObjectSetInteger(0, "Dash_RobotPic", OBJPROP_YSIZE, dashboardBitmapSize);
   ObjectSetString(0, "Dash_RobotPic", OBJPROP_BMPFILE, 0, "::" + bitmapResource);
   ObjectSetString(0, "Dash_RobotPic", OBJPROP_BMPFILE, 1, "::" + bitmapResource);
}
int GetDashboardTitleX() { return DashboardX + S_Dash(10) + GetDashboardBitmapSize() + S_Dash(5); }
int GetDashboardTitleY()
{
   int titleBaseY = DashboardY + S_Dash(5);
   int iconSize = GetDashboardBitmapSize();
   int fontSize = MathMax(8, S_Dash(9));
   int verticalAdjust = MathMax(0, (iconSize - fontSize) / 2);
   return titleBaseY + verticalAdjust;
}

void SyncDashboardHeartbeatLayout()
{
   if(ObjectFind(0, DASH_HEARTBEAT_DOT) >= 0)
   {
      ObjectSetInteger(0, DASH_HEARTBEAT_DOT, OBJPROP_XDISTANCE, GetDashboardHeartbeatDotX());
      ObjectSetInteger(0, DASH_HEARTBEAT_DOT, OBJPROP_YDISTANCE, GetDashboardHeartbeatDotY());
      ObjectSetInteger(0, DASH_HEARTBEAT_DOT, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, DASH_HEARTBEAT_DOT, OBJPROP_BGCOLOR, clrOrange);
      ObjectSetInteger(0, DASH_HEARTBEAT_DOT, OBJPROP_COLOR, clrOrange);
      ObjectSetInteger(0, DASH_HEARTBEAT_DOT, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, DASH_HEARTBEAT_DOT, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, DASH_HEARTBEAT_DOT, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, DASH_HEARTBEAT_DOT, OBJPROP_ZORDER, 10);
   }

   if(ObjectFind(0, DASH_HEARTBEAT_TEXT) >= 0)
   {
      ObjectSetInteger(0, DASH_HEARTBEAT_TEXT, OBJPROP_XDISTANCE, GetDashboardHeartbeatTextX());
      ObjectSetInteger(0, DASH_HEARTBEAT_TEXT, OBJPROP_YDISTANCE, GetDashboardHeartbeatTextY());
      ObjectSetInteger(0, DASH_HEARTBEAT_TEXT, OBJPROP_FONTSIZE, S_Dash(8));
      ObjectSetInteger(0, DASH_HEARTBEAT_TEXT, OBJPROP_COLOR, clrOrange);
   }
}

void SetDashboardHeartbeatVisible(bool visible)
{
   if(ObjectFind(0, DASH_HEARTBEAT_DOT) >= 0)
   {
      int dotSize = visible ? GetDashboardHeartbeatDotSize() : 0;
      ObjectSetInteger(0, DASH_HEARTBEAT_DOT, OBJPROP_XSIZE, dotSize);
      ObjectSetInteger(0, DASH_HEARTBEAT_DOT, OBJPROP_YSIZE, dotSize);
      
      // FIX: Toggle colors to transparent and move off-screen to kill the 1x1 pixel artifact
      color dotColor = visible ? clrOrange : clrNONE;
      ObjectSetInteger(0, DASH_HEARTBEAT_DOT, OBJPROP_BGCOLOR, dotColor);
      ObjectSetInteger(0, DASH_HEARTBEAT_DOT, OBJPROP_COLOR, dotColor);
      
      ObjectSetInteger(0, DASH_HEARTBEAT_DOT, OBJPROP_XDISTANCE, visible ? GetDashboardHeartbeatDotX() : -100);
      ObjectSetInteger(0, DASH_HEARTBEAT_DOT, OBJPROP_YDISTANCE, visible ? GetDashboardHeartbeatDotY() : -100);
   }

   if(ObjectFind(0, DASH_HEARTBEAT_TEXT) >= 0)
   {
      ObjectSetString(0, DASH_HEARTBEAT_TEXT, OBJPROP_TEXT, visible ? "working.." : "");
      
      // FIX: Move text completely off-screen when hidden to avoid any remnants
      ObjectSetInteger(0, DASH_HEARTBEAT_TEXT, OBJPROP_XDISTANCE, visible ? GetDashboardHeartbeatTextX() : -100);
      ObjectSetInteger(0, DASH_HEARTBEAT_TEXT, OBJPROP_YDISTANCE, visible ? GetDashboardHeartbeatTextY() : -100);
   }
}

int ResolveDashboardFocusSymbolIndex()
{
   return ResolveDashboardHostFocusSymbolIndex(_Symbol);
}

int GetDashboardRowCount()
{
   int count = 0;
   for(int i = 0; i < ArraySize(SymbolData); i++)
   {
      if(!SymbolData[i].active)
         continue;
      if(InpEnableMultiBaskets && !SymbolData[i].IsPrimaryBasket)
         continue;
      count++;
   }

   return count;
}

int GetDashboardSymbolIndexByRow(const int row)
{
   if(row < 0)
      return -1;

   int currentRow = 0;
   for(int i = 0; i < ArraySize(SymbolData); i++)
   {
      if(!SymbolData[i].active)
         continue;
      if(InpEnableMultiBaskets && !SymbolData[i].IsPrimaryBasket)
         continue;

      if(currentRow == row)
         return i;

      currentRow++;
   }

   return -1;
}

double GetDashboardSymbolFloatingProfit(const int symbolIndex)
{
   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return 0.0;

   string execSymbol = GetBaseSymbol(SymbolData[symbolIndex].symbol);
   double totalProfit = 0.0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(!IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != execSymbol)
         continue;

      ulong posID = PositionGetInteger(POSITION_IDENTIFIER);
      totalProfit += PositionGetDouble(POSITION_PROFIT) +
                     PositionGetDouble(POSITION_SWAP) +
                     GetPositionCommission(posID);
   }

   return totalProfit;
}

double GetDashboardSymbolDebt(const int symbolIndex, const bool critical)
{
   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return 0.0;

   string trackedSymbol = GetManagedBaseSymbol(symbolIndex);
   if(trackedSymbol == "")
      trackedSymbol = GetBaseSymbol(SymbolData[symbolIndex].symbol);
   if(trackedSymbol == "")
      trackedSymbol = SymbolData[symbolIndex].symbol;
   double totalDebt = 0.0;

   for(int i = 0; i < ArraySize(SymbolData); i++)
   {
      if(!SymbolData[i].active)
         continue;

      string symbolKey = GetManagedBaseSymbol(i);
      if(symbolKey == "")
         symbolKey = GetBaseSymbol(SymbolData[i].symbol);
      if(symbolKey == "")
         symbolKey = SymbolData[i].symbol;

      if(StringCompare(symbolKey, trackedSymbol, false) != 0)
         continue;

      totalDebt += critical ? SymbolData[i].AccumulatedCriticalLoss : SymbolData[i].AccumulatedPruningLoss;
   }

   return totalDebt;
}

bool DashboardSymbolHasManagedPosition(const int symbolIndex)
{
   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return false;

   string execSymbol = GetBaseSymbol(SymbolData[symbolIndex].symbol);
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(!IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
         continue;
      if(PositionGetString(POSITION_SYMBOL) == execSymbol)
         return true;
   }

   return false;
}

void ResolveDashboardStatus(const int symbolIndex, string &statusStr, color &statColor)
{
   statusStr = "Idle";
   statColor = clrGray;

   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return;

   if(IsPaused)
   {
      statusStr = "Paused";
      statColor = clrRed;
      return;
   }

   string trackedSymbol = SymbolData[symbolIndex].symbol;

   if(RiskMode == RISK_MODE_GRID)
   {
      int maxGridLevel = 0;
      bool trailing = false;
      for(int i = 0; i < ArraySize(SymbolData); i++)
      {
         if(!SymbolData[i].active || SymbolData[i].symbol != trackedSymbol)
            continue;

         if(SymbolData[i].GridPhase2Active)
            trailing = true;
         if(SymbolData[i].GridLevels > maxGridLevel)
            maxGridLevel = SymbolData[i].GridLevels;
      }

      if(trailing)
      {
         statusStr = "Trail Basket";
         statColor = clrLime;
         return;
      }

      if(maxGridLevel > 0)
      {
         statusStr = "Grid Lvl " + IntegerToString(maxGridLevel);
         statColor = clrAqua;
         return;
      }
   }
   else if(RiskMode == RISK_MODE_ZONE_RECOVERY)
   {
      int maxZoneSeq = 0;
      for(int i = 0; i < ArraySize(SymbolData); i++)
      {
         if(!SymbolData[i].active || SymbolData[i].symbol != trackedSymbol)
            continue;
         if(SymbolData[i].ZoneActive && SymbolData[i].ZoneSeqCount > maxZoneSeq)
            maxZoneSeq = SymbolData[i].ZoneSeqCount;
      }

      if(maxZoneSeq > 0)
      {
         statusStr = "Zone Seq " + IntegerToString(maxZoneSeq);
         statColor = clrOrange;
         return;
      }
   }

   int activeBaskets = CountActiveBasketsForSymbol(trackedSymbol);
   if(activeBaskets > 1)
   {
      statusStr = "Basket " + IntegerToString(activeBaskets);
      statColor = clrDeepSkyBlue;
   }
   else if(activeBaskets == 1 || DashboardSymbolHasManagedPosition(symbolIndex))
   {
      statusStr = "Active";
      statColor = clrLime;
   }
}

bool IsWorkerDashboardMode()
{
   return IsParallelWorkerMode();
}

int GetDashboardWidth()
{
   return IsWorkerDashboardMode() ? S_Dash(300) : S_Dash(350);
}

int GetDashboardSettingsHeight()
{
   return S_Dash(180);
}

void CreateDashboardSettingsPanel()
{
   int panelWidth = GetDashboardWidth();
   int panelHeight = GetDashboardSettingsHeight();
   string bgName = "Dash_BG";
   if(ObjectFind(0, bgName) < 0) ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, DashboardX);
   ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, DashboardY);
   ObjectSetInteger(0, bgName, OBJPROP_XSIZE, panelWidth);
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, panelHeight);
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ApplyPanelBackgroundAppearance(bgName, clrBlack, clrGray);
   ApplyPanelBackgroundLayer(bgName);

   CreateBtnObj("Btn_Settings_Close", DashboardX + S_Dash(6), DashboardY + S_Dash(5), S_Dash(20), S_Dash(20), "X", clrMaroon);
   CreateLabelObj("Dash_Title", DashboardX + S_Dash(34), DashboardY + S_Dash(7), "MultiBotPro Settings", clrWhite);
   CreateBtnObj("Btn_Settings_Scale_M", DashboardX + panelWidth - S_Dash(50), DashboardY + S_Dash(5), S_Dash(20), S_Dash(20), "-", clrDarkGray);
   CreateBtnObj("Btn_Settings_Scale_P", DashboardX + panelWidth - S_Dash(25), DashboardY + S_Dash(5), S_Dash(20), S_Dash(20), "+", clrDarkGray);

   int rowY = DashboardY + S_Dash(48);
   CreateLabelObj(DASH_SETTINGS_PREFIX + "LblMode", DashboardX + S_Dash(12), rowY + S_Dash(5), "Chart type", clrSilver);
   CreateBtnObj("Btn_Settings_Mode_Select", DashboardX + S_Dash(92), rowY, S_Dash(160), S_Dash(24), MBP_DashboardModeCursorText(G_DashboardSettingsModeCursor), clrMidnightBlue);
   CreateBtnObj("Btn_Settings_Mode_OK", DashboardX + S_Dash(262), rowY, S_Dash(54), S_Dash(24), "OK", clrRoyalBlue);

   CreateLabelObj(DASH_SETTINGS_PREFIX + "LblActive", DashboardX + S_Dash(12), rowY + S_Dash(36),
                  "Active: " + MBP_DataModeToText(MBP_EffectiveDataMode()), clrCyan);
   CreateLabelObj(DASH_SETTINGS_PREFIX + "LblSpace", DashboardX + S_Dash(12), rowY + S_Dash(72),
                  "More settings can be added here.", clrDimGray);
}

int ResolveWorkerDashboardSymbolIndex()
{
   string workerBase = G_RuntimeAssignedWorkerSymbol;
   if(workerBase == "")
      workerBase = GetBaseSymbol(G_RuntimeAssignedChartSymbol);
   if(workerBase == "")
      workerBase = GetBaseSymbol(_Symbol);
   if(workerBase == "")
      workerBase = _Symbol;

   int idx = GetPrimarySymbolIndexByBase(workerBase, false);
   if(idx < 0 && ArraySize(SymbolData) > 0)
      idx = 0;

   return idx;
}

int GetWorkerDashboardPositionCount(const int symbolIndex)
{
   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return 0;

   string execSymbol = GetManagedBaseSymbol(symbolIndex);
   if(execSymbol == "")
      execSymbol = GetBaseSymbol(_Symbol);

   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(!IsAppTrade(PositionGetInteger(POSITION_MAGIC)))
         continue;

      string posBase = GetBaseSymbol(PositionGetString(POSITION_SYMBOL));
      if(posBase == "")
         posBase = PositionGetString(POSITION_SYMBOL);
      if(StringCompare(posBase, execSymbol, false) == 0)
         count++;
   }

   return count;
}

int GetWorkerDashboardMaxGridLevel(const int symbolIndex)
{
   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return 0;

   string trackedBase = GetManagedBaseSymbol(symbolIndex);
   if(trackedBase == "")
      trackedBase = GetBaseSymbol(_Symbol);

   int maxGridLevel = 0;
   for(int i = 0; i < ArraySize(SymbolData); i++)
   {
      string symbolBase = GetManagedBaseSymbol(i);
      if(symbolBase == "")
         symbolBase = GetBaseSymbol(SymbolData[i].symbol);
      if(StringCompare(symbolBase, trackedBase, false) != 0)
         continue;

      if(SymbolData[i].GridLevels > maxGridLevel)
         maxGridLevel = SymbolData[i].GridLevels;
   }

   return maxGridLevel;
}

int GetWorkerDashboardActiveBasketCount(const int symbolIndex)
{
   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return 0;

   string trackedSymbol = GetManagedAnalysisSymbol(symbolIndex);
   if(trackedSymbol == "")
      trackedSymbol = SymbolData[symbolIndex].symbol;

   return CountActiveBasketsForSymbol(trackedSymbol);
}

string GetWorkerDashboardTrailLabel(const int symbolIndex)
{
   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return "--";

   if(SymbolData[symbolIndex].GridPhase2Active || SymbolData[symbolIndex].GridInTrailing)
      return "Basket";
   if(SymbolData[symbolIndex].TrailLocked || SymbolData[symbolIndex].MasterSLMoved)
      return "Master";
   if(UseTrailing)
      return "Armed";
   return "Off";
}

string GetWorkerDashboardSmartLabel(const int symbolIndex)
{
   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return "--";

   if(SymbolData[symbolIndex].SmartHedgeReleased)
      return "Released";
   if(SymbolData[symbolIndex].SmartHedgeFirstLockSeen)
      return "Locked";
   if(SmartHedge_IsEnabled())
      return "Armed";
   return "Off";
}

void CreateWorkerDashboard()
{
   int totalHeight = DashboardCollapsed ? S_Dash(30) : S_Dash(190);
   string bgName = "Dash_BG";
   if(ObjectFind(0, bgName) < 0) ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, DashboardX);
   ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, DashboardY);
   ObjectSetInteger(0, bgName, OBJPROP_XSIZE, GetDashboardWidth());
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, totalHeight);
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ApplyPanelBackgroundAppearance(bgName, clrDarkSlateGray, clrSlateGray);
   ApplyPanelBackgroundLayer(bgName);

   int dashboardBitmapSize = GetDashboardBitmapSize();
   CreateBitmapObj("Dash_RobotPic", DashboardX + S_Dash(10), DashboardY + S_Dash(5), GetDashboardBitmapResource(), dashboardBitmapSize, dashboardBitmapSize);
   ApplyDashboardBitmapLayout(DashboardX, DashboardY);
   CreateLabelObj("Dash_Title", GetDashboardTitleX(), GetDashboardTitleY(), "MultiBotPro [WORKER]", clrWhite);
   CreateBtnObj("Btn_Collapse", DashboardX + S_Dash(270), DashboardY + S_Dash(5), S_Dash(20), S_Dash(20), DashboardCollapsed ? "+" : "-", clrDimGray);
   CreateBtnObj("Btn_Dash_Scale_P", DashboardX + S_Dash(245), DashboardY + S_Dash(5), S_Dash(20), S_Dash(20), "+", clrDarkGray);
   CreateBtnObj("Btn_Dash_Scale_M", DashboardX + S_Dash(220), DashboardY + S_Dash(5), S_Dash(20), S_Dash(20), "-", clrDarkGray);
   CreateBtnObj("Btn_Settings_Open", DashboardX + S_Dash(195), DashboardY + S_Dash(5), S_Dash(20), S_Dash(20), "S", clrDarkSlateGray);
   ObjectSetString(0, "Btn_Settings_Open", OBJPROP_TOOLTIP, "Chart type settings");

   if(DashboardCollapsed)
   {
      ObjectsDeleteAll(0, "WK_");
      ChartRedraw();
      return;
   }

   int symbolIndex = ResolveWorkerDashboardSymbolIndex();
   string chartSymbol = (_Symbol != "") ? _Symbol : G_RuntimeAssignedChartSymbol;
   string execSymbol = (symbolIndex >= 0) ? GetManagedBaseSymbol(symbolIndex) : G_RuntimeAssignedWorkerSymbol;
   if(execSymbol == "")
      execSymbol = GetBaseSymbol(chartSymbol);

   int startY = DashboardY + S_Dash(38);
   CreateLabelObj("WK_Chart", DashboardX + S_Dash(10), startY, "Chart: " + chartSymbol, clrAqua);
   CreateLabelObj("WK_Exec", DashboardX + S_Dash(10), startY + S_Dash(16), "Exec: " + execSymbol, clrWhite);
   CreateLabelObj("WK_Mode", DashboardX + S_Dash(10), startY + S_Dash(32), "Mode: " + MBP_DataModeToText(MBP_EffectiveDataMode()), clrSilver);
   CreateLabelObj("WK_State", DashboardX + S_Dash(10), startY + S_Dash(56), "State: --", clrAqua);
   CreateLabelObj("WK_Grid", DashboardX + S_Dash(10), startY + S_Dash(74), "Grid Level: --", clrGold);
   CreateLabelObj("WK_Basket", DashboardX + S_Dash(10), startY + S_Dash(92), "Baskets: --", clrDeepSkyBlue);
   CreateLabelObj("WK_Pos", DashboardX + S_Dash(10), startY + S_Dash(110), "Positions: --", clrOrange);
   CreateLabelObj("WK_PnL", DashboardX + S_Dash(150), startY + S_Dash(56), "Float: --", clrWhite);
   CreateLabelObj("WK_Equity", DashboardX + S_Dash(150), startY + S_Dash(74), "Equity: --", clrWhite);
   CreateLabelObj("WK_Trail", DashboardX + S_Dash(150), startY + S_Dash(92), "Trail: --", clrSilver);
   CreateLabelObj("WK_Smart", DashboardX + S_Dash(150), startY + S_Dash(110), "Smart: --", clrSilver);
   ChartRedraw();
}

void MoveWorkerDashboard(int x, int y)
{
   ObjectSetInteger(0, "Dash_BG", OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, "Dash_BG", OBJPROP_YDISTANCE, y);
   ApplyDashboardBitmapLayout(x, y);
   ObjectSetInteger(0, "Dash_Title", OBJPROP_XDISTANCE, x + S_Dash(10) + GetDashboardBitmapSize() + S_Dash(5));
   ObjectSetInteger(0, "Dash_Title", OBJPROP_YDISTANCE, y + (GetDashboardTitleY() - DashboardY));
   ObjectSetInteger(0, "Btn_Collapse", OBJPROP_XDISTANCE, x + S_Dash(270));
   ObjectSetInteger(0, "Btn_Collapse", OBJPROP_YDISTANCE, y + S_Dash(5));
   ObjectSetInteger(0, "Btn_Dash_Scale_P", OBJPROP_XDISTANCE, x + S_Dash(245));
   ObjectSetInteger(0, "Btn_Dash_Scale_P", OBJPROP_YDISTANCE, y + S_Dash(5));
   ObjectSetInteger(0, "Btn_Dash_Scale_M", OBJPROP_XDISTANCE, x + S_Dash(220));
   ObjectSetInteger(0, "Btn_Dash_Scale_M", OBJPROP_YDISTANCE, y + S_Dash(5));
   ObjectSetInteger(0, "Btn_Settings_Open", OBJPROP_XDISTANCE, x + S_Dash(195));
   ObjectSetInteger(0, "Btn_Settings_Open", OBJPROP_YDISTANCE, y + S_Dash(5));

   if(DashboardCollapsed)
   {
      ChartRedraw();
      return;
   }

   int startY = y + S_Dash(38);
   ObjectSetInteger(0, "WK_Chart", OBJPROP_XDISTANCE, x + S_Dash(10));
   ObjectSetInteger(0, "WK_Chart", OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, "WK_Exec", OBJPROP_XDISTANCE, x + S_Dash(10));
   ObjectSetInteger(0, "WK_Exec", OBJPROP_YDISTANCE, startY + S_Dash(16));
   ObjectSetInteger(0, "WK_Mode", OBJPROP_XDISTANCE, x + S_Dash(10));
   ObjectSetInteger(0, "WK_Mode", OBJPROP_YDISTANCE, startY + S_Dash(32));
   ObjectSetInteger(0, "WK_State", OBJPROP_XDISTANCE, x + S_Dash(10));
   ObjectSetInteger(0, "WK_State", OBJPROP_YDISTANCE, startY + S_Dash(56));
   ObjectSetInteger(0, "WK_Grid", OBJPROP_XDISTANCE, x + S_Dash(10));
   ObjectSetInteger(0, "WK_Grid", OBJPROP_YDISTANCE, startY + S_Dash(74));
   ObjectSetInteger(0, "WK_Basket", OBJPROP_XDISTANCE, x + S_Dash(10));
   ObjectSetInteger(0, "WK_Basket", OBJPROP_YDISTANCE, startY + S_Dash(92));
   ObjectSetInteger(0, "WK_Pos", OBJPROP_XDISTANCE, x + S_Dash(10));
   ObjectSetInteger(0, "WK_Pos", OBJPROP_YDISTANCE, startY + S_Dash(110));
   ObjectSetInteger(0, "WK_PnL", OBJPROP_XDISTANCE, x + S_Dash(150));
   ObjectSetInteger(0, "WK_PnL", OBJPROP_YDISTANCE, startY + S_Dash(56));
   ObjectSetInteger(0, "WK_Equity", OBJPROP_XDISTANCE, x + S_Dash(150));
   ObjectSetInteger(0, "WK_Equity", OBJPROP_YDISTANCE, startY + S_Dash(74));
   ObjectSetInteger(0, "WK_Trail", OBJPROP_XDISTANCE, x + S_Dash(150));
   ObjectSetInteger(0, "WK_Trail", OBJPROP_YDISTANCE, startY + S_Dash(92));
   ObjectSetInteger(0, "WK_Smart", OBJPROP_XDISTANCE, x + S_Dash(150));
   ObjectSetInteger(0, "WK_Smart", OBJPROP_YDISTANCE, startY + S_Dash(110));
   ChartRedraw();
}

void UpdateWorkerDashboard()
{
   int symbolIndex = ResolveWorkerDashboardSymbolIndex();
   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
      return;

   string statusStr = "Idle";
   color statusColor = clrGray;
   ResolveDashboardStatus(symbolIndex, statusStr, statusColor);

   double floatingProfit = GetDashboardSymbolFloatingProfit(symbolIndex);
   int gridLevel = GetWorkerDashboardMaxGridLevel(symbolIndex);
   int basketCount = GetWorkerDashboardActiveBasketCount(symbolIndex);
   int positionCount = GetWorkerDashboardPositionCount(symbolIndex);

   if(ObjectFind(0, "WK_State") >= 0)
   {
      ObjectSetString(0, "WK_State", OBJPROP_TEXT, "State: " + statusStr);
      ObjectSetInteger(0, "WK_State", OBJPROP_COLOR, statusColor);
   }
   if(ObjectFind(0, "WK_Grid") >= 0)
      ObjectSetString(0, "WK_Grid", OBJPROP_TEXT, "Grid Level: " + IntegerToString(gridLevel));
   if(ObjectFind(0, "WK_Basket") >= 0)
      ObjectSetString(0, "WK_Basket", OBJPROP_TEXT, "Baskets: " + IntegerToString(basketCount));
   if(ObjectFind(0, "WK_Pos") >= 0)
      ObjectSetString(0, "WK_Pos", OBJPROP_TEXT, "Positions: " + IntegerToString(positionCount));
   if(ObjectFind(0, "WK_PnL") >= 0)
   {
      ObjectSetString(0, "WK_PnL", OBJPROP_TEXT, "Float: " + DoubleToString(floatingProfit, 2));
      ObjectSetInteger(0, "WK_PnL", OBJPROP_COLOR, floatingProfit >= 0.0 ? clrLime : clrTomato);
   }
   if(ObjectFind(0, "WK_Equity") >= 0)
      ObjectSetString(0, "WK_Equity", OBJPROP_TEXT, "Equity: " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));
   if(ObjectFind(0, "WK_Trail") >= 0)
      ObjectSetString(0, "WK_Trail", OBJPROP_TEXT, "Trail: " + GetWorkerDashboardTrailLabel(symbolIndex));
   if(ObjectFind(0, "WK_Smart") >= 0)
      ObjectSetString(0, "WK_Smart", OBJPROP_TEXT, "Smart: " + GetWorkerDashboardSmartLabel(symbolIndex));
}

//+------------------------------------------------------------------+
//| DASHBOARD HELPER: Create Merged Panel                            |
//+------------------------------------------------------------------+
void CreateDashboard()
{
   if(G_DashboardSettingsOpen)
   {
      CreateDashboardSettingsPanel();
      return;
   }

   if(IsWorkerDashboardMode())
   {
      CreateWorkerDashboard();
      return;
   }

   // --- CALCULATE DIMENSIONS ---
   int rowHeight = S_Dash(20);
   int headerHeight = S_Dash(45); 
   int tableHeaderHeight = S_Dash(20);
   int indicatorHeight = S_Dash(55); 
   int buttonAreaHeight = S_Dash(60); 
   int bottomPadding = S_Dash(15);    
   
   // Base Height
   int rowCount = GetDashboardRowCount();
   int baseHeight = headerHeight + tableHeaderHeight + (rowCount * rowHeight) + indicatorHeight + buttonAreaHeight + bottomPadding;
   int manualSectionHeight = ShowManualSection ? S_Dash(100) : 0; 
   int totalHeight = baseHeight + manualSectionHeight;
   if(DashboardCollapsed) totalHeight = S_Dash(30);

   // 1. Main Background Panel (Width 350)
   string bgName = "Dash_BG";
   if(ObjectFind(0, bgName) < 0) ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, DashboardX);
   ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, DashboardY);
   ObjectSetInteger(0, bgName, OBJPROP_XSIZE, GetDashboardWidth()); 
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, totalHeight);
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ApplyPanelBackgroundAppearance(bgName, clrBlack, clrGray);
   ApplyPanelBackgroundLayer(bgName);

   // 2. Main Title & Controls
   string modeSuffix = "";
   if(BotSystemMode == BOT_MODE_MASTER) modeSuffix = " [MASTER]";
   else if(BotSystemMode == BOT_MODE_SLAVE) modeSuffix = " [SLAVE]";
   if(IsParallelCoordinatorMode()) modeSuffix += " [COORD]";
   else if(IsParallelWorkerMode()) modeSuffix += " [WORKER]";
   
   int dashboardBitmapSize = GetDashboardBitmapSize();
   CreateBitmapObj("Dash_RobotPic", DashboardX + S_Dash(10), DashboardY + S_Dash(5), GetDashboardBitmapResource(), dashboardBitmapSize, dashboardBitmapSize);
   ApplyDashboardBitmapLayout(DashboardX, DashboardY);
   CreateLabelObj("Dash_Title", GetDashboardTitleX(), GetDashboardTitleY(), "MultiBotPro" + modeSuffix, clrWhite);
   CreateBtnObj("Btn_Collapse", DashboardX + S_Dash(320), DashboardY + S_Dash(5), S_Dash(20), S_Dash(20), DashboardCollapsed ? "+" : "-", clrDimGray);
   CreateBtnObj("Btn_ToggleMan", DashboardX + S_Dash(295), DashboardY + S_Dash(5), S_Dash(20), S_Dash(20), "M", ShowManualSection ? clrRoyalBlue : clrMidnightBlue);
   ObjectSetString(0, "Btn_ToggleMan", OBJPROP_TOOLTIP, "Toggle Manual Trading Section");
   CreateBtnObj("Btn_ToggleList", DashboardX + S_Dash(270), DashboardY + S_Dash(5), S_Dash(20), S_Dash(20), "L", ShowTradeList ? clrRoyalBlue : clrMidnightBlue);
   ObjectSetString(0, "Btn_ToggleList", OBJPROP_TOOLTIP, "Toggle Trade List Visibility");

   // --- NEW: DASHBOARD SCALE BUTTONS ---
   CreateBtnObj("Btn_Dash_Scale_P", DashboardX + S_Dash(245), DashboardY + S_Dash(5), S_Dash(20), S_Dash(20), "+", clrDarkGray);
   CreateBtnObj("Btn_Dash_Scale_M", DashboardX + S_Dash(220), DashboardY + S_Dash(5), S_Dash(20), S_Dash(20), "-", clrDarkGray);
   CreateBtnObj("Btn_Settings_Open", DashboardX + S_Dash(195), DashboardY + S_Dash(5), S_Dash(20), S_Dash(20), "S", clrDarkSlateGray);
   ObjectSetString(0, "Btn_Settings_Open", OBJPROP_TOOLTIP, "Chart type settings");

   if(DashboardCollapsed) {
      DestroyManualElements(); 
      ObjectsDeleteAll(0, BTN_PREFIX_LIST);
      return;
   }

   // 3. Time Label
   MqlDateTime ny_time;
   ConvertToNYTime(TimeCurrent(), ny_time);
   string timeStr = StringFormat("Time: %02d:%02d", ny_time.hour, ny_time.min);
   CreateLabelObj("Dash_Time", DashboardX + S_Dash(10), DashboardY + S_Dash(25), timeStr, clrLime);
   if(ObjectFind(0, DASH_HEARTBEAT_DOT) < 0) ObjectCreate(0, DASH_HEARTBEAT_DOT, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   CreateLabelObj(DASH_HEARTBEAT_TEXT, GetDashboardHeartbeatTextX(), GetDashboardHeartbeatTextY(), "", clrOrange);
   SyncDashboardHeartbeatLayout();
   SetDashboardHeartbeatVisible(false);

   // 4. Symbol Table Headers
   int startY = DashboardY + S_Dash(45);
   CreateLabelObj("Header_Sym",  DashboardX + S_Dash(10),  startY, "SYMBOL", clrGray);
   CreateLabelObj("Header_PL",   DashboardX + S_Dash(70),  startY, "P/L ($)", clrGray);
   CreateLabelObj("Header_Bank", DashboardX + S_Dash(130), startY, "BANK", clrGray);
   CreateLabelObj("Header_Crit", DashboardX + S_Dash(190), startY, "CRIT", clrGray);
   CreateLabelObj("Header_Stat", DashboardX + S_Dash(250), startY, "STATUS", clrGray); 

   int currentY = startY + S_Dash(20);
   for(int row = 0; row < rowCount; row++)
   {
      int symbolIndex = GetDashboardSymbolIndexByRow(row);
      string idx = IntegerToString(row);
      string rowSymbol = (symbolIndex >= 0) ? GetBaseSymbol(SymbolData[symbolIndex].symbol) : "";
      CreateLabelObj("Row_Sym_" + idx,  DashboardX + S_Dash(10),  currentY, TruncateString(rowSymbol, 6), clrYellow);
      CreateLabelObj("Row_PL_" + idx,   DashboardX + S_Dash(70),  currentY, "0.00", clrWhite);
      CreateLabelObj("Row_Bank_" + idx, DashboardX + S_Dash(130), currentY, "0.00", clrOrange);
      CreateLabelObj("Row_Crit_" + idx, DashboardX + S_Dash(190), currentY, "0.00", clrRed);
      CreateLabelObj("Row_Stat_" + idx, DashboardX + S_Dash(250), currentY, "Idle", clrAqua); 
      currentY += S_Dash(20);
   }

   // 5. Indicators & Standard Buttons
   int indY = currentY + S_Dash(10);
   string chartModeName = MBP_DataModeToText(MBP_EffectiveDataMode());
   CreateLabelObj("Dash_Mode", DashboardX + S_Dash(10), indY, "Mode: " + chartModeName, clrCyan);
   
   CreateLabelObj("Dash_MA", DashboardX + S_Dash(10), indY + S_Dash(15), "MA: --", clrGray);
   CreateLabelObj("Dash_VWAP", DashboardX + S_Dash(10), indY + S_Dash(30), "VWAP: --", clrGray);
   
   int btnY1 = indY + S_Dash(55); 
   CreateBtnObj("Btn_CloseAll", DashboardX + S_Dash(10), btnY1, S_Dash(160), S_Dash(22), "Close ALL", clrRed);
   CreateBtnObj("Btn_CloseChart", DashboardX + S_Dash(180), btnY1, S_Dash(160), S_Dash(22), "Close Chart", clrBlue);

   int btnY2 = btnY1 + S_Dash(30);
   CreateBtnObj("Btn_MasterReset", DashboardX + S_Dash(10), btnY2, S_Dash(160), S_Dash(22), "Master Reset", clrCrimson);
   CreateBtnObj("Btn_Pause", DashboardX + S_Dash(180), btnY2, S_Dash(160), S_Dash(22), IsPaused?"Resume":"Pause Bot", IsPaused?clrGreen:clrOrange);

   // 6. MANUAL SECTION
   if(ShowManualSection)
   {
      int manY = btnY2 + S_Dash(30) + S_Dash(10);
      string sepName = "Dash_Sep";
      if(ObjectFind(0, sepName) < 0) ObjectCreate(0, sepName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, sepName, OBJPROP_XDISTANCE, DashboardX + S_Dash(5));
      ObjectSetInteger(0, sepName, OBJPROP_YDISTANCE, manY);
      ObjectSetInteger(0, sepName, OBJPROP_XSIZE, S_Dash(340));
      ObjectSetInteger(0, sepName, OBJPROP_YSIZE, S_Dash(2));
      ObjectSetInteger(0, sepName, OBJPROP_BGCOLOR, clrDimGray);
      ObjectSetInteger(0, sepName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ApplyPanelBackgroundLayer(sepName);
      
      manY += S_Dash(10);
      
      // --- Row 1: Lot Size Controls ---
      int startX = DashboardX + S_Dash(10);
      int btnSmallW = S_Dash(35);
      int editW = S_Dash(60);
      int gap = S_Dash(5);
      int btnH = S_Dash(25);
      
      CreateBtnObj(MAN_BTN_LOT_MM, startX, manY, btnSmallW, btnH, "--", clrDimGray);
      startX += btnSmallW + gap;
      
      CreateBtnObj(MAN_BTN_LOT_M, startX, manY, btnSmallW, btnH, "-", clrGray);
      startX += btnSmallW + gap;
      
      CreateBtnObj(MAN_EDIT_LOT,  startX, manY, editW, btnH, DoubleToString(Panel_ManualLot, 2), clrBlack);
      startX += editW + gap;
      
      CreateBtnObj(MAN_BTN_LOT_P, startX, manY, btnSmallW, btnH, "+", clrGray);
      startX += btnSmallW + gap;
      
      CreateBtnObj(MAN_BTN_LOT_PP, startX, manY, btnSmallW, btnH, "++", clrDimGray);
      startX += btnSmallW + gap + S_Dash(10);
      
      CreateLabelObj("MAN_LBL_LOT", startX, manY+S_Dash(5), "Lots", clrWhite);
      
      // --- Row 2: Trading Buttons ---
      int tradeY = manY + S_Dash(35);
      int tradeBtnW = S_Dash(100);
      int tradeGap = S_Dash(15);
      
      int bX = DashboardX + S_Dash(10);
      
      CreateBtnObj(MAN_BTN_BUY,  bX, tradeY, tradeBtnW, btnH, "BUY", clrGreen);
      bX += tradeBtnW + tradeGap;
      
      CreateBtnObj(MAN_BTN_CLOSE, bX, tradeY, tradeBtnW, btnH, "PANIC", clrMaroon);
      bX += tradeBtnW + tradeGap;
      
      CreateBtnObj(MAN_BTN_SELL, bX, tradeY, tradeBtnW, btnH, "SELL", clrRed);
   }
   else
   {
      DestroyManualElements();
   }
   
   G_ForceDashboardRefresh = true;
   UpdateDashboard(0);
   ChartRedraw();
}
//+------------------------------------------------------------------+
void MoveDashboardFrameOnly(int x, int y)
{
   if(G_DashboardSettingsOpen)
   {
      DashboardX = x;
      DashboardY = y;
      CreateDashboardSettingsPanel();
      return;
   }

   if(IsWorkerDashboardMode())
   {
      MoveWorkerDashboard(x, y);
      return;
   }

   ObjectSetInteger(0, "Dash_BG", OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, "Dash_BG", OBJPROP_YDISTANCE, y);
   ApplyDashboardBitmapLayout(x, y);
   ObjectSetInteger(0, "Dash_Title", OBJPROP_XDISTANCE, x + S_Dash(10) + GetDashboardBitmapSize() + S_Dash(5));
   ObjectSetInteger(0, "Dash_Title", OBJPROP_YDISTANCE, y + (GetDashboardTitleY() - DashboardY));
}

void MoveDashboard(int x, int y)
{
   if(G_DashboardSettingsOpen)
   {
      DashboardX = x;
      DashboardY = y;
      CreateDashboardSettingsPanel();
      return;
   }

   if(IsWorkerDashboardMode())
   {
      MoveWorkerDashboard(x, y);
      return;
   }

   // Background & Title
   ObjectSetInteger(0, "Dash_BG", OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, "Dash_BG", OBJPROP_YDISTANCE, y);
   int dashboardBitmapSize = GetDashboardBitmapSize();
   ApplyDashboardBitmapLayout(x, y);
   ObjectSetInteger(0, "Dash_Title", OBJPROP_XDISTANCE, x + S_Dash(10) + dashboardBitmapSize + S_Dash(5));
   ObjectSetInteger(0, "Dash_Title", OBJPROP_YDISTANCE, y + (GetDashboardTitleY() - DashboardY));
   
   // Controls
   ObjectSetInteger(0, "Btn_Collapse", OBJPROP_XDISTANCE, x + S_Dash(320));
   ObjectSetInteger(0, "Btn_Collapse", OBJPROP_YDISTANCE, y + S_Dash(5));
   ObjectSetInteger(0, "Btn_ToggleMan", OBJPROP_XDISTANCE, x + S_Dash(295)); 
   ObjectSetInteger(0, "Btn_ToggleMan", OBJPROP_YDISTANCE, y + S_Dash(5));
   ObjectSetInteger(0, "Btn_ToggleList", OBJPROP_XDISTANCE, x + S_Dash(270));
   ObjectSetInteger(0, "Btn_ToggleList", OBJPROP_YDISTANCE, y + S_Dash(5));
   
   // Scale Buttons
   ObjectSetInteger(0, "Btn_Dash_Scale_P", OBJPROP_XDISTANCE, x + S_Dash(245));
   ObjectSetInteger(0, "Btn_Dash_Scale_P", OBJPROP_YDISTANCE, y + S_Dash(5));
   ObjectSetInteger(0, "Btn_Dash_Scale_M", OBJPROP_XDISTANCE, x + S_Dash(220));
   ObjectSetInteger(0, "Btn_Dash_Scale_M", OBJPROP_YDISTANCE, y + S_Dash(5));
   ObjectSetInteger(0, "Btn_Settings_Open", OBJPROP_XDISTANCE, x + S_Dash(195));
   ObjectSetInteger(0, "Btn_Settings_Open", OBJPROP_YDISTANCE, y + S_Dash(5));

   if(DashboardCollapsed) {
      ChartRedraw();
      return;
   }

   // Time
   ObjectSetInteger(0, "Dash_Time", OBJPROP_XDISTANCE, x + S_Dash(10));
   ObjectSetInteger(0, "Dash_Time", OBJPROP_YDISTANCE, y + S_Dash(25));
   SyncDashboardHeartbeatLayout();

   // Headers
   int startY = y + S_Dash(45);
   ObjectSetInteger(0, "Header_Sym",  OBJPROP_XDISTANCE, x + S_Dash(10));
   ObjectSetInteger(0, "Header_Sym",  OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, "Header_PL",   OBJPROP_XDISTANCE, x + S_Dash(70));
   ObjectSetInteger(0, "Header_PL",   OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, "Header_Bank", OBJPROP_XDISTANCE, x + S_Dash(130));
   ObjectSetInteger(0, "Header_Bank", OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, "Header_Crit", OBJPROP_XDISTANCE, x + S_Dash(190));
   ObjectSetInteger(0, "Header_Crit", OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, "Header_Stat", OBJPROP_XDISTANCE, x + S_Dash(250));
   ObjectSetInteger(0, "Header_Stat", OBJPROP_YDISTANCE, startY);

   // Rows
   int rowH = S_Dash(20);
   int currentY = startY + S_Dash(20);
   int rowCount = GetDashboardRowCount();
   for(int row = 0; row < rowCount; row++)
   {
      string idx = IntegerToString(row);
      ObjectSetInteger(0, "Row_Sym_" + idx,  OBJPROP_XDISTANCE, x + S_Dash(10));
      ObjectSetInteger(0, "Row_Sym_" + idx,  OBJPROP_YDISTANCE, currentY);
      ObjectSetInteger(0, "Row_PL_" + idx,   OBJPROP_XDISTANCE, x + S_Dash(70));
      ObjectSetInteger(0, "Row_PL_" + idx,   OBJPROP_YDISTANCE, currentY);
      ObjectSetInteger(0, "Row_Bank_" + idx, OBJPROP_XDISTANCE, x + S_Dash(130));
      ObjectSetInteger(0, "Row_Bank_" + idx, OBJPROP_YDISTANCE, currentY);
      ObjectSetInteger(0, "Row_Crit_" + idx, OBJPROP_XDISTANCE, x + S_Dash(190));
      ObjectSetInteger(0, "Row_Crit_" + idx, OBJPROP_YDISTANCE, currentY);
      ObjectSetInteger(0, "Row_Stat_" + idx, OBJPROP_XDISTANCE, x + S_Dash(250));
      ObjectSetInteger(0, "Row_Stat_" + idx, OBJPROP_YDISTANCE, currentY);
      
      currentY += rowH;
   }

   // Indicators
   int indY = currentY + S_Dash(10);
   ObjectSetInteger(0, "Dash_Mode", OBJPROP_XDISTANCE, x + S_Dash(10));
   ObjectSetInteger(0, "Dash_Mode", OBJPROP_YDISTANCE, indY);
   ObjectSetInteger(0, "Dash_MA", OBJPROP_XDISTANCE, x + S_Dash(10));
   ObjectSetInteger(0, "Dash_MA", OBJPROP_YDISTANCE, indY + S_Dash(15));
   ObjectSetInteger(0, "Dash_VWAP", OBJPROP_XDISTANCE, x + S_Dash(10));
   ObjectSetInteger(0, "Dash_VWAP", OBJPROP_YDISTANCE, indY + S_Dash(30));
   
   // Main Buttons
   int btnY1 = indY + S_Dash(55); 
   ObjectSetInteger(0, "Btn_CloseAll", OBJPROP_XDISTANCE, x + S_Dash(10));
   ObjectSetInteger(0, "Btn_CloseAll", OBJPROP_YDISTANCE, btnY1);
   ObjectSetInteger(0, "Btn_CloseChart", OBJPROP_XDISTANCE, x + S_Dash(180));
   ObjectSetInteger(0, "Btn_CloseChart", OBJPROP_YDISTANCE, btnY1);

   int btnY2 = btnY1 + S_Dash(30);
   ObjectSetInteger(0, "Btn_MasterReset", OBJPROP_XDISTANCE, x + S_Dash(10));
   ObjectSetInteger(0, "Btn_MasterReset", OBJPROP_YDISTANCE, btnY2);
   ObjectSetInteger(0, "Btn_Pause", OBJPROP_XDISTANCE, x + S_Dash(180));
   ObjectSetInteger(0, "Btn_Pause", OBJPROP_YDISTANCE, btnY2);

    // Reposition manual section elements (no recursion — just move existing objects)
    if(ShowManualSection)
    {
       int manY = btnY2 + S_Dash(30) + S_Dash(10);
       if(ObjectFind(0, "Dash_Sep") >= 0)
       {
          ObjectSetInteger(0, "Dash_Sep", OBJPROP_XDISTANCE, x + S_Dash(5));
          ObjectSetInteger(0, "Dash_Sep", OBJPROP_YDISTANCE, manY);
       }
       manY += S_Dash(10);

       int startX_m = x + S_Dash(10);
       int btnSmallW = S_Dash(35);
       int editW = S_Dash(60);
       int gap_m = S_Dash(5);
       int btnH_m = S_Dash(25);

       int cx = startX_m;
       if(ObjectFind(0, MAN_BTN_LOT_MM) >= 0) { ObjectSetInteger(0, MAN_BTN_LOT_MM, OBJPROP_XDISTANCE, cx); ObjectSetInteger(0, MAN_BTN_LOT_MM, OBJPROP_YDISTANCE, manY); }
       cx += btnSmallW + gap_m;
       if(ObjectFind(0, MAN_BTN_LOT_M) >= 0)  { ObjectSetInteger(0, MAN_BTN_LOT_M, OBJPROP_XDISTANCE, cx); ObjectSetInteger(0, MAN_BTN_LOT_M, OBJPROP_YDISTANCE, manY); }
       cx += btnSmallW + gap_m;
       if(ObjectFind(0, MAN_EDIT_LOT) >= 0)   { ObjectSetInteger(0, MAN_EDIT_LOT, OBJPROP_XDISTANCE, cx); ObjectSetInteger(0, MAN_EDIT_LOT, OBJPROP_YDISTANCE, manY); }
       cx += editW + gap_m;
       if(ObjectFind(0, MAN_BTN_LOT_P) >= 0)  { ObjectSetInteger(0, MAN_BTN_LOT_P, OBJPROP_XDISTANCE, cx); ObjectSetInteger(0, MAN_BTN_LOT_P, OBJPROP_YDISTANCE, manY); }
       cx += btnSmallW + gap_m;
       if(ObjectFind(0, MAN_BTN_LOT_PP) >= 0) { ObjectSetInteger(0, MAN_BTN_LOT_PP, OBJPROP_XDISTANCE, cx); ObjectSetInteger(0, MAN_BTN_LOT_PP, OBJPROP_YDISTANCE, manY); }
       cx += btnSmallW + gap_m + S_Dash(10);
       if(ObjectFind(0, "MAN_LBL_LOT") >= 0) { ObjectSetInteger(0, "MAN_LBL_LOT", OBJPROP_XDISTANCE, cx); ObjectSetInteger(0, "MAN_LBL_LOT", OBJPROP_YDISTANCE, manY + S_Dash(5)); }

       int tradeY = manY + S_Dash(35);
       int tradeBtnW = S_Dash(100);
       int tradeGap = S_Dash(15);
       int bX = x + S_Dash(10);
       if(ObjectFind(0, MAN_BTN_BUY) >= 0)   { ObjectSetInteger(0, MAN_BTN_BUY, OBJPROP_XDISTANCE, bX); ObjectSetInteger(0, MAN_BTN_BUY, OBJPROP_YDISTANCE, tradeY); }
       bX += tradeBtnW + tradeGap;
       if(ObjectFind(0, MAN_BTN_CLOSE) >= 0) { ObjectSetInteger(0, MAN_BTN_CLOSE, OBJPROP_XDISTANCE, bX); ObjectSetInteger(0, MAN_BTN_CLOSE, OBJPROP_YDISTANCE, tradeY); }
       bX += tradeBtnW + tradeGap;
       if(ObjectFind(0, MAN_BTN_SELL) >= 0)  { ObjectSetInteger(0, MAN_BTN_SELL, OBJPROP_XDISTANCE, bX); ObjectSetInteger(0, MAN_BTN_SELL, OBJPROP_YDISTANCE, tradeY); }
    }

    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Helper: Destroy Manual Elements                                  |
//+------------------------------------------------------------------+
void DestroyManualElements()
{
   ObjectDelete(0, "Dash_Sep");
   ObjectDelete(0, MAN_BTN_LOT_MM); // New
   ObjectDelete(0, MAN_BTN_LOT_M);
   ObjectDelete(0, MAN_EDIT_LOT);
   ObjectDelete(0, MAN_BTN_LOT_P);
   ObjectDelete(0, MAN_BTN_LOT_PP); // New
   ObjectDelete(0, "MAN_LBL_LOT");
   ObjectDelete(0, MAN_BTN_BUY);
   ObjectDelete(0, MAN_BTN_SELL);
   ObjectDelete(0, MAN_BTN_CLOSE);
}

//+------------------------------------------------------------------+
//| LOCAL HELPER: Check Manual Lot Buttons                           |
//+------------------------------------------------------------------+
void CheckManualLotChange()
{
   double stepSmall = 0.01;
   double stepLarge = 0.10; // "Points" equivalent of 10x
   bool changed = false;

   if(ConsumeDashboardButtonState(MAN_BTN_LOT_MM)) {
      Panel_ManualLot -= stepLarge;
      changed = true;
   }
   if(ConsumeDashboardButtonState(MAN_BTN_LOT_M)) {
      Panel_ManualLot -= stepSmall;
      changed = true;
   }
   if(ConsumeDashboardButtonState(MAN_BTN_LOT_P)) {
      Panel_ManualLot += stepSmall;
      changed = true;
   }
   if(ConsumeDashboardButtonState(MAN_BTN_LOT_PP)) {
      Panel_ManualLot += stepLarge;
      changed = true;
   }

   if(changed) {
      if(Panel_ManualLot < 0.01) Panel_ManualLot = 0.01;
      ObjectSetString(0, MAN_EDIT_LOT, OBJPROP_TEXT, DoubleToString(Panel_ManualLot, 2));
   }
}

//+------------------------------------------------------------------+
//| UI MANAGER: Updated to Poll Buttons                              |
//+------------------------------------------------------------------+
void ManageManualSystem()
{
   // ==================================================================
   // 1. MANUAL TRADING PANEL ACTIONS
   // ==================================================================
   if(ShowManualSection)
   {
      CheckManualLotChange();
      CheckManualEntryActions();
   }
   
   // ==================================================================
   // 2. TRADE LIST & MODIFICATION ACTIONS
   // ==================================================================
   if(!DashboardCollapsed)
   {
      if(Panel_IsModifying) ManageModificationMode();
      else ManageTradeListMode();
   }
   else
   {
      if(!Panel_IsModifying) ObjectsDeleteAll(0, BTN_PREFIX_LIST);
   }
   
   UpdateDashboard(0);
}

void DestroyDashboard()
{
   ObjectsDeleteAll(0, "WK_");
   ObjectDelete(0, "Dash_BG");
   ObjectDelete(0, "Dash_RobotPic");
   ObjectDelete(0, "Dash_Title");
   ObjectDelete(0, "Dash_Time");
   ObjectDelete(0, "Dash_Mode");
   ObjectDelete(0, "Dash_MA");
   ObjectDelete(0, "Dash_VWAP");
   ObjectDelete(0, "Btn_CloseAll");
   ObjectDelete(0, "Btn_CloseChart"); 
   ObjectDelete(0, "Btn_MasterReset");
   ObjectDelete(0, "Btn_Pause");
   ObjectDelete(0, "Btn_Collapse");
   ObjectDelete(0, "Btn_ToggleMan"); 
   ObjectDelete(0, "Btn_ToggleList");
   ObjectDelete(0, "Btn_Dash_Scale_P"); // Cleanup Scale +
   ObjectDelete(0, "Btn_Dash_Scale_M"); // Cleanup Scale -
   ObjectDelete(0, "Btn_Settings_Open");
   ObjectDelete(0, "Btn_Settings_Close");
   ObjectDelete(0, "Btn_Settings_Scale_P");
   ObjectDelete(0, "Btn_Settings_Scale_M");
   ObjectDelete(0, "Btn_Settings_Mode_Select");
   ObjectDelete(0, "Btn_Settings_Mode_OK");
   ObjectsDeleteAll(0, DASH_SETTINGS_PREFIX);
   ObjectDelete(0, DASH_HEARTBEAT_DOT);
   ObjectDelete(0, DASH_HEARTBEAT_TEXT);
   
   ObjectDelete(0, "Header_Sym");
   ObjectDelete(0, "Header_PL");
   ObjectDelete(0, "Header_Bank");
   ObjectDelete(0, "Header_Crit");
   ObjectDelete(0, "Header_Stat");

   for(int i = 0; i < 50; i++) 
   {
      ObjectDelete(0, "Row_Sym_" + IntegerToString(i));
      ObjectDelete(0, "Row_PL_" + IntegerToString(i));
      ObjectDelete(0, "Row_Bank_" + IntegerToString(i));
      ObjectDelete(0, "Row_Crit_" + IntegerToString(i)); 
      ObjectDelete(0, "Row_Stat_" + IntegerToString(i));
   }
   
   DestroyManualElements();
}

struct SDashRowCache
{
   string sym;
   string pl;
   color  plClr;
   string bank;
   color  bankClr;
   string crit;
   color  critClr;
   string stat;
   color  statClr;
};
static SDashRowCache g_DashRowCache[];

//+------------------------------------------------------------------+
//| DASHBOARD HELPER: Update Panel                                   |
//+------------------------------------------------------------------+
void UpdateDashboard(int dummyIndex)
{
   if(DashboardCollapsed || G_IS_DEINIT) return;

   // [OPTIONAL] Throttle Redraws internally if called from multiple sources
   static uint lastDraw = 0;
   uint redrawThrottleMs = (ShowManualSection || ShowTradeList || Panel_IsModifying || IsWorkerDashboardMode()) ? 50 : 75;
   if(!G_ForceDashboardRefresh && GetTickCount() - lastDraw < redrawThrottleMs) return;
   bool forceDashboardRefresh = G_ForceDashboardRefresh;
   G_ForceDashboardRefresh = false;
   lastDraw = GetTickCount();

   if(IsWorkerDashboardMode())
   {
      UpdateWorkerDashboard();
      RequestChartRedraw(0);
      return;
   }

   // 2. Update Time
   MqlDateTime ny_time;
   ConvertToNYTime(TimeCurrent(), ny_time);
   string timeStr = StringFormat("Time: %02d:%02d (%s)", ny_time.hour, ny_time.min, EnumToString((ENUM_DAY_OF_WEEK)ny_time.day_of_week));
   if(ObjectFind(0, "Dash_Time") >= 0) ObjectSetString(0, "Dash_Time", OBJPROP_TEXT, timeStr);
   SyncDashboardHeartbeatLayout();
   SetDashboardHeartbeatVisible(IsDashboardHeartbeatVisibleNow());

   // 3. Update Multi-Symbol Table
   int rowCount = GetDashboardRowCount();
   for(int row = 0; row < rowCount; row++)
   {
      int symbolIndex = GetDashboardSymbolIndexByRow(row);
      if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData))
         continue;

      string idx = IntegerToString(row);
      string sym = SymbolData[symbolIndex].symbol;
      string displaySym = GetBaseSymbol(sym); 
      
      // Calculate P/L
      double profit = GetDashboardSymbolFloatingProfit(symbolIndex);

      // Status
      string statusStr;
      color statColor;
      ResolveDashboardStatus(symbolIndex, statusStr, statColor);

      if(row >= ArraySize(g_DashRowCache))
         ArrayResize(g_DashRowCache, row + 1, 16);

      string plStr = DoubleToString(profit, 2);
      color plClr = (profit >= 0 ? clrLime : clrRed);
      double debt = GetDashboardSymbolDebt(symbolIndex, false);
      string bankStr = DoubleToString(debt, 2);
      color bankClr = (debt > 0 ? clrOrange : clrDarkGray);
      double crit = GetDashboardSymbolDebt(symbolIndex, true);
      string critStr = DoubleToString(crit, 2);
      color critClr = (crit > 0 ? clrRed : clrDarkGray);
      string symStr = TruncateString(displaySym, 6);

      // Only touch GUI objects if values changed or refresh forced
      if(forceDashboardRefresh ||
         g_DashRowCache[row].sym != symStr ||
         g_DashRowCache[row].pl != plStr ||
         g_DashRowCache[row].plClr != plClr ||
         g_DashRowCache[row].bank != bankStr ||
         g_DashRowCache[row].bankClr != bankClr ||
         g_DashRowCache[row].crit != critStr ||
         g_DashRowCache[row].critClr != critClr ||
         g_DashRowCache[row].stat != statusStr ||
         g_DashRowCache[row].statClr != statColor)
      {
         g_DashRowCache[row].sym = symStr;
         g_DashRowCache[row].pl = plStr;
         g_DashRowCache[row].plClr = plClr;
         g_DashRowCache[row].bank = bankStr;
         g_DashRowCache[row].bankClr = bankClr;
         g_DashRowCache[row].crit = critStr;
         g_DashRowCache[row].critClr = critClr;
         g_DashRowCache[row].stat = statusStr;
         g_DashRowCache[row].statClr = statColor;

         if(ObjectFind(0, "Row_Sym_" + idx) >= 0) {
            ObjectSetString(0, "Row_Sym_" + idx, OBJPROP_TEXT, symStr);
            ObjectSetString(0, "Row_PL_" + idx, OBJPROP_TEXT, plStr);
            ObjectSetInteger(0, "Row_PL_" + idx, OBJPROP_COLOR, plClr);
            ObjectSetString(0, "Row_Bank_" + idx, OBJPROP_TEXT, bankStr);
            ObjectSetInteger(0, "Row_Bank_" + idx, OBJPROP_COLOR, bankClr);
            ObjectSetString(0, "Row_Crit_" + idx, OBJPROP_TEXT, critStr);
            ObjectSetInteger(0, "Row_Crit_" + idx, OBJPROP_COLOR, critClr);
            ObjectSetString(0, "Row_Stat_" + idx, OBJPROP_TEXT, statusStr);
            ObjectSetInteger(0, "Row_Stat_" + idx, OBJPROP_COLOR, statColor);
         }
      }
   }

   static uint lastIndicatorDraw = 0;
   bool uiBusy = (ShowManualSection || ShowTradeList || Panel_IsModifying);
   uint nowDraw = GetTickCount();
   bool refreshIndicators = forceDashboardRefresh ||
                            (!uiBusy && (lastIndicatorDraw == 0 ||
                                         nowDraw <= lastIndicatorDraw ||
                                         (nowDraw - lastIndicatorDraw) >= 1000));

   if(refreshIndicators)
   {
      int chartIdx = ResolveDashboardFocusSymbolIndex();

      if(chartIdx >= 0 && !IsParallelCoordinatorMode())
      {
         bool maBuy = CheckMABuySignal(chartIdx);
         bool maSell = CheckMASellSignal(chartIdx);
         string maStr = "Chart MA: NEUTRAL";
         color maColor = clrGray;
         if(maBuy) { maStr = "Chart MA: BUY"; maColor = clrLime; }
         else if(maSell) { maStr = "Chart MA: SELL"; maColor = clrRed; }

         ObjectSetString(0, "Dash_MA", OBJPROP_TEXT, maStr);
         ObjectSetInteger(0, "Dash_MA", OBJPROP_COLOR, maColor);

         double price = SymbolInfoDouble(SymbolData[chartIdx].symbol, SYMBOL_BID);
         bool vwapBuy = CheckVWAPBuySignal(chartIdx, price);
         bool vwapSell = CheckVWAPSellSignal(chartIdx, price);
         string vwapStr = "Chart VWAP: NEUTRAL";
         color vwapColor = clrGray;
         if(vwapBuy && !vwapSell) { vwapStr = "Chart VWAP: BUY ZONE"; vwapColor = clrLime; }
         else if(vwapSell && !vwapBuy) { vwapStr = "Chart VWAP: SELL ZONE"; vwapColor = clrRed; }

         ObjectSetString(0, "Dash_VWAP", OBJPROP_TEXT, vwapStr);
         ObjectSetInteger(0, "Dash_VWAP", OBJPROP_COLOR, vwapColor);
      }

      lastIndicatorDraw = nowDraw;
   }

   if(IsPaused) {
      ObjectSetString(0, "Btn_Pause", OBJPROP_TEXT, "Resume");
      ObjectSetInteger(0, "Btn_Pause", OBJPROP_BGCOLOR, clrGreen);
   } else {
      ObjectSetString(0, "Btn_Pause", OBJPROP_TEXT, "Pause Bot");
      ObjectSetInteger(0, "Btn_Pause", OBJPROP_BGCOLOR, clrOrange);
   }

   RequestChartRedraw(0);
}

//+------------------------------------------------------------------+
//| MANAGE MODIFICATION MODE (Redesigned & Clean Layout)             |
//+------------------------------------------------------------------+
void ManageModificationMode()
{
   // Safety Check: Ensure the position still exists
   if(!PositionSelectByTicket(Panel_SelectedTicket)) {
      Panel_IsModifying = false;
      DestroyModificationPanel();
      return;
   }

   // --- LAYOUT CONSTANTS ---
   int yBase = GetDashboardBottomY() + 5;
   int xBase = DashboardX;
   int panelWidth = 350; 
   int panelHeight = 135; 
   int rowHeight = 30;
   int btnW = 35;
   int btnH = 22; 
   int gap = 2;

   // 1. Background Panel
   if(ObjectFind(0, "MP_BG") < 0) {
       CreateBtnObj("MP_BG", xBase, yBase, panelWidth, panelHeight, "", clrDarkGray);
       ObjectSetInteger(0, "MP_BG", OBJPROP_ZORDER, PanelBackgroundZOrder());
       ObjectSetInteger(0, "MP_BG", OBJPROP_BORDER_TYPE, BORDER_RAISED);
       ObjectSetInteger(0, "MP_BG", OBJPROP_BACK, false);
   } else {
       ObjectSetInteger(0, "MP_BG", OBJPROP_XDISTANCE, xBase);
       ObjectSetInteger(0, "MP_BG", OBJPROP_YDISTANCE, yBase);
       ObjectSetInteger(0, "MP_BG", OBJPROP_XSIZE, panelWidth); 
   }
   ApplyPanelBackgroundAppearance("MP_BG", clrBlack, clrGray);
   ApplyPanelBackgroundLayer("MP_BG");
   
   // 2. Title Header
   CreateLabelObj("MP_LBL_TITLE", xBase + 10, yBase + 10, "MODIFY ORDER #" + (string)Panel_SelectedTicket, clrWhite);
   ObjectSetInteger(0, "MP_LBL_TITLE", OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, "MP_LBL_TITLE", OBJPROP_ZORDER, PanelForegroundZOrder());

   // =================================================================
   // STOP LOSS ROW
   // =================================================================
   int slY = yBase + 35;
   double slVal = ObjectGetDouble(0, MP_HL_SL, OBJPROP_PRICE);
   CreateLabelObj("MP_LBL_SL_TXT", xBase + 10, slY, "SL:", clrRed);
   CreateLabelObj("MP_LBL_SL_VAL", xBase + 35, slY, DoubleToString(slVal, _Digits), clrWhite);
   
   // Controls (Centered relative to new width)
   int startX = xBase + 160; 
   CreateBtnObj(MP_BTN_SL_MM, startX,             slY, btnW, btnH, "<<", clrMaroon);
   CreateBtnObj(MP_BTN_SL_M,  startX + btnW + gap, slY, btnW, btnH, "<",  clrRed);
   CreateBtnObj(MP_BTN_SL_P,  startX + (btnW+gap)*2, slY, btnW, btnH, ">",  clrRed);
   CreateBtnObj(MP_BTN_SL_PP, startX + (btnW+gap)*3, slY, btnW, btnH, ">>", clrMaroon);
   
   // =================================================================
   // TAKE PROFIT ROW
   // =================================================================
   int tpY = yBase + 65;
   double tpVal = ObjectGetDouble(0, MP_HL_TP, OBJPROP_PRICE);
   CreateLabelObj("MP_LBL_TP_TXT", xBase + 10, tpY, "TP:", clrLime);
   CreateLabelObj("MP_LBL_TP_VAL", xBase + 35, tpY, DoubleToString(tpVal, _Digits), clrWhite);
   
   CreateBtnObj(MP_BTN_TP_MM, startX,             tpY, btnW, btnH, "<<", clrDarkGreen);
   CreateBtnObj(MP_BTN_TP_M,  startX + btnW + gap, tpY, btnW, btnH, "<",  clrGreen);
   CreateBtnObj(MP_BTN_TP_P,  startX + (btnW+gap)*2, tpY, btnW, btnH, ">",  clrGreen);
   CreateBtnObj(MP_BTN_TP_PP, startX + (btnW+gap)*3, tpY, btnW, btnH, ">>", clrDarkGreen);

   // =================================================================
   // ACTION BUTTONS (Bottom Row)
   // =================================================================
   int actY = yBase + 100;
   int actW = 120;
   
   CreateBtnObj(MP_BTN_CONFIRM, xBase + 25, actY, actW, 25, "UPDATE ORDER", clrRoyalBlue);
   CreateBtnObj(MP_BTN_CANCEL,  xBase + 185, actY, actW, 25, "CANCEL", clrDimGray);

   // =================================================================
   // EVENT LOGIC (Clicks)
   // =================================================================
   if(ConsumeDashboardButtonState(MP_BTN_CANCEL)) {
      Panel_IsModifying = false;
      DestroyModificationPanel();
      return;
   }

   if(ConsumeDashboardButtonState(MP_BTN_CONFIRM)) {
      double newSL = ObjectGetDouble(0, MP_HL_SL, OBJPROP_PRICE);
      double newTP = ObjectGetDouble(0, MP_HL_TP, OBJPROP_PRICE);
      
      if(Trade.PositionModify(Panel_SelectedTicket, newSL, newTP))
      {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("Order #", Panel_SelectedTicket, " Modified. SL: ", newSL, " TP: ", newTP);
         Panel_IsModifying = false;
         DestroyModificationPanel();
      }
      else
      {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print("Modify Failed: ", GetLastError());
         ObjectSetInteger(0, MP_BTN_CONFIRM, OBJPROP_BGCOLOR, clrRed);
         ChartRedraw(0);
         ObjectSetInteger(0, MP_BTN_CONFIRM, OBJPROP_BGCOLOR, clrRoyalBlue);
      }
      return;
   }

   CheckLineMove(MP_BTN_SL_P,  MP_HL_SL, (int)Panel_SlowPts);
   CheckLineMove(MP_BTN_SL_M,  MP_HL_SL, -(int)Panel_SlowPts);
   CheckLineMove(MP_BTN_SL_PP, MP_HL_SL, (int)Panel_FastPts);
   CheckLineMove(MP_BTN_SL_MM, MP_HL_SL, -(int)Panel_FastPts);

   CheckLineMove(MP_BTN_TP_P,  MP_HL_TP, (int)Panel_SlowPts);
   CheckLineMove(MP_BTN_TP_M,  MP_HL_TP, -(int)Panel_SlowPts);
   CheckLineMove(MP_BTN_TP_PP, MP_HL_TP, (int)Panel_FastPts);
   CheckLineMove(MP_BTN_TP_MM, MP_HL_TP, -(int)Panel_FastPts);
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| HELPER FUNCTIONS (Creation/Cleanup)                              |
//+------------------------------------------------------------------+
void CreateBtnObj(string name, int x, int y, int w, int h, string text, color bg)
{
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, S_Dash(8)); // <-- Added Scaling
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, PanelForegroundZOrder());
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, PanelForegroundZOrder());
}

void CreateLabelObj(string name, int x, int y, string text, color clr)
{
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, S_Dash(9)); // <-- Added Scaling
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, PanelForegroundZOrder());
}

void CreateBitmapObj(string name, int x, int y, string fileOn, int w = 0, int h = 0)
{
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_BITMAP_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, PanelForegroundZOrder());
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   if(w > 0) ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   if(h > 0) ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_BMPFILE, 0, "::" + fileOn);
   ObjectSetString(0, name, OBJPROP_BMPFILE, 1, "::" + fileOn);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, PanelForegroundZOrder());
}

void CreateLineObj(string name, double price, color clr)
{
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASHDOT);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
   }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
}

void CheckLineMove(string btnName, string lineName, int points)
{
   if(ConsumeDashboardButtonState(btnName))
   {
      double price = ObjectGetDouble(0, lineName, OBJPROP_PRICE);
      double tickSize = SymbolInfoDouble(RealSymbol, SYMBOL_TRADE_TICK_SIZE);
      double move = points * SymbolInfoDouble(RealSymbol, SYMBOL_POINT);
      double newPrice = NormalizeDouble(MathRound((price + move) / tickSize) * tickSize, _Digits);
      
      ObjectSetDouble(0, lineName, OBJPROP_PRICE, newPrice);
      ChartRedraw();
   }
}

void DestroyManualPanel()
{
   ObjectsDeleteAll(0, PREFIX_MANUAL);
   ObjectsDeleteAll(0, BTN_PREFIX_LIST);
   DestroyModificationPanel();
   ObjectDelete(0, "MAN_BG");
}

void DestroyModificationPanel()
{
   ObjectsDeleteAll(0, BTN_PREFIX_MOD);
   ObjectsDeleteAll(0, "MP_");
   ChartRedraw();
}

void CleanupGhostButtons(int currentCount, string prefix)
{
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, prefix) >= 0)
      {
         string parts[];
         StringSplit(name, '_', parts);
         if(ArraySize(parts) > 0)
         {
             ulong t = StringToInteger(parts[ArraySize(parts)-1]);
             if(!PositionSelectByTicket(t)) ObjectDelete(0, name);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| HELPER: Truncate String for Dashboard                            |
//+------------------------------------------------------------------+
string TruncateString(string text, int length)
{
   if(StringLen(text) <= length) return text;
   return StringSubstr(text, 0, length-1) + "..";
}

//+------------------------------------------------------------------+
//| HELPER: Get Bottom Y Coordinate of Dashboard                     |
//+------------------------------------------------------------------+
int GetDashboardBottomY()
{
   // 1. Collapsed State
   if(DashboardCollapsed) return DashboardY + S_Dash(30);

   if(IsWorkerDashboardMode())
      return DashboardY + S_Dash(190);

   // 2. Base Height (Main Panel)
   int rowHeight = S_Dash(20);
   int headerHeight = S_Dash(45); 
   int tableHeaderHeight = S_Dash(20);
   int indicatorHeight = S_Dash(55); 
   int buttonAreaHeight = S_Dash(60); 
   int bottomPadding = S_Dash(15);    
   
   int baseHeight = headerHeight + tableHeaderHeight + (GetDashboardRowCount() * rowHeight) + indicatorHeight + buttonAreaHeight + bottomPadding;
   
   // 3. Manual Section Height
   int manualHeight = ShowManualSection ? S_Dash(100) : 0;
   
   return DashboardY + baseHeight + manualHeight;
}

//+------------------------------------------------------------------+

#endif // __MULTIBOTPRO_DASHBOARD_MQH__


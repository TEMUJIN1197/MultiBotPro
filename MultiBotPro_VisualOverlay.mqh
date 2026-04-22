#ifndef __MULTIBOTPRO_VISUALOVERLAY_MQH__
#define __MULTIBOTPRO_VISUALOVERLAY_MQH__
//+------------------------------------------------------------------+
//|                                  MultiBotPro_VisualOverlay_v2.mqh |
//|                        Chart overlay for MultiBotPro EA visuals   |
//+------------------------------------------------------------------+

struct SIndicatorOverlayState
{
   long              chartID;
   bool              initialized;
   bool              dirty;
   string            chartSymbol;
   ENUM_TIMEFRAMES   chartPeriod;
   int               chartSymbolIndex;
   int               firstVisibleBar;
   int               visibleBars;
   int               activeMAPeriods[5];
   int               maHandles[5];
   int               atrHandle;
   datetime          lastBarTime;
   uint              lastFullRedrawTick;
};

enum ENUM_OVERLAY_SERIES
{
   OVERLAY_SERIES_MA1 = 0,
   OVERLAY_SERIES_MA2,
   OVERLAY_SERIES_MA3,
   OVERLAY_SERIES_MA4,
   OVERLAY_SERIES_MA5,
   OVERLAY_SERIES_VWAP1,
   OVERLAY_SERIES_VWAP3,
   OVERLAY_SERIES_VWAP_HIGH,
   OVERLAY_SERIES_VWAP_LOW
};

SIndicatorOverlayState G_IndicatorOverlay;
SIndicatorOverlayState G_IndicatorOverlayStates[];
long G_IndicatorOverlayContextChartID = 0;
string G_IndicatorOverlayForcedSymbol = "";
ENUM_TIMEFRAMES G_IndicatorOverlayForcedPeriod = PERIOD_CURRENT;
int G_IndicatorOverlayForcedSymbolIndex = -1;

long GetIndicatorOverlayChartID()
{
   return G_IndicatorOverlayContextChartID;
}

int FindIndicatorOverlayStateIndex(const long chartID)
{
   for(int i = 0; i < ArraySize(G_IndicatorOverlayStates); i++)
   {
      if(G_IndicatorOverlayStates[i].chartID == chartID)
         return i;
   }

   return -1;
}

void SaveIndicatorOverlayContext()
{
   int idx = FindIndicatorOverlayStateIndex(G_IndicatorOverlay.chartID);
   if(idx < 0)
   {
      idx = ArraySize(G_IndicatorOverlayStates);
      ArrayResize(G_IndicatorOverlayStates, idx + 1);
   }

   G_IndicatorOverlayStates[idx] = G_IndicatorOverlay;
}

void BeginIndicatorOverlayContext(const long chartID,
                                  const string forcedSymbol = "",
                                  const ENUM_TIMEFRAMES forcedPeriod = PERIOD_CURRENT,
                                  const int forcedSymbolIndex = -1)
{
   G_IndicatorOverlayContextChartID = chartID;
   G_IndicatorOverlayForcedSymbol = forcedSymbol;
   G_IndicatorOverlayForcedPeriod = forcedPeriod;
   G_IndicatorOverlayForcedSymbolIndex = forcedSymbolIndex;

   int idx = FindIndicatorOverlayStateIndex(chartID);
   if(idx >= 0)
      G_IndicatorOverlay = G_IndicatorOverlayStates[idx];
   else
      ResetIndicatorOverlayState();

   G_IndicatorOverlay.chartID = chartID;
}

void EndIndicatorOverlayContext()
{
   SaveIndicatorOverlayContext();
   G_IndicatorOverlayContextChartID = 0;
   G_IndicatorOverlayForcedSymbol = "";
   G_IndicatorOverlayForcedPeriod = PERIOD_CURRENT;
   G_IndicatorOverlayForcedSymbolIndex = -1;
}

string OverlaySeriesToken(const int seriesId)
{
   switch(seriesId)
   {
      case OVERLAY_SERIES_MA1:       return "MA1";
      case OVERLAY_SERIES_MA2:       return "MA2";
      case OVERLAY_SERIES_MA3:       return "MA3";
      case OVERLAY_SERIES_MA4:       return "MA4";
      case OVERLAY_SERIES_MA5:       return "MA5";
      case OVERLAY_SERIES_VWAP1:     return "VWAP1";
      case OVERLAY_SERIES_VWAP3:     return "VWAP3";
      case OVERLAY_SERIES_VWAP_HIGH: return "VWAPH";
      case OVERLAY_SERIES_VWAP_LOW:  return "VWAPL";
   }
   return "UNK";
}

string OverlaySeriesDescription(const int seriesId)
{
   int symbolIndex = G_IndicatorOverlay.chartSymbolIndex;

   switch(seriesId)
   {
      case OVERLAY_SERIES_MA1:       return "Moving Average 1 : period " + IntegerToString(GetActiveMAPeriod(symbolIndex, 0));
      case OVERLAY_SERIES_MA2:       return "Moving Average 2 : period " + IntegerToString(GetActiveMAPeriod(symbolIndex, 1));
      case OVERLAY_SERIES_MA3:       return "Moving Average 3 : period " + IntegerToString(GetActiveMAPeriod(symbolIndex, 2));
      case OVERLAY_SERIES_MA4:       return "Moving Average 4 : period " + IntegerToString(GetActiveMAPeriod(symbolIndex, 3));
      case OVERLAY_SERIES_MA5:       return "Moving Average 5 : period " + IntegerToString(GetActiveMAPeriod(symbolIndex, 4));
      case OVERLAY_SERIES_VWAP1:     return "VWAP 1";
      case OVERLAY_SERIES_VWAP3:     return "VWAP 3";
      case OVERLAY_SERIES_VWAP_HIGH: return "VWAP High Band";
      case OVERLAY_SERIES_VWAP_LOW:  return "VWAP Low Band";
   }

   return "Indicator Overlay";
}

string OverlayCloudDescription()
{
   return "VWAP Cloud : dynamic high/low band";
}
bool OverlayVWAPCloudEnabled()
{
   return (UseVWAP2 && InpShowVWAPCloud);
}

bool OverlaySeriesEnabled(const int seriesId)
{
   switch(seriesId)
   {
      case OVERLAY_SERIES_MA1:       return InpShowMA1Overlay;
      case OVERLAY_SERIES_MA2:       return InpShowMA2Overlay;
      case OVERLAY_SERIES_MA3:       return InpShowMA3Overlay;
      case OVERLAY_SERIES_MA4:       return InpShowMA4Overlay;
      case OVERLAY_SERIES_MA5:       return InpShowMA5Overlay;
      case OVERLAY_SERIES_VWAP1:     return (UseVWAP1 && InpShowVWAP1Overlay);
      case OVERLAY_SERIES_VWAP3:     return (UseVWAP3 && InpShowVWAP3Overlay);
      case OVERLAY_SERIES_VWAP_HIGH: return (UseVWAP2 && InpShowVWAPHighOverlay);
      case OVERLAY_SERIES_VWAP_LOW:  return (UseVWAP2 && InpShowVWAPLowOverlay);
   }
   return false;
}

color OverlaySeriesColor(const int seriesId)
{
   switch(seriesId)
   {
      case OVERLAY_SERIES_MA1:       return InpMA1OverlayColor;
      case OVERLAY_SERIES_MA2:       return InpMA2OverlayColor;
      case OVERLAY_SERIES_MA3:       return InpMA3OverlayColor;
      case OVERLAY_SERIES_MA4:       return InpMA4OverlayColor;
      case OVERLAY_SERIES_MA5:       return InpMA5OverlayColor;
      case OVERLAY_SERIES_VWAP1:     return InpVWAP1OverlayColor;
      case OVERLAY_SERIES_VWAP3:     return InpVWAP3OverlayColor;
      case OVERLAY_SERIES_VWAP_HIGH: return InpVWAPHighOverlayColor;
      case OVERLAY_SERIES_VWAP_LOW:  return InpVWAPLowOverlayColor;
   }
   return clrWhite;
}

ENUM_LINE_STYLE OverlaySeriesStyle(const int seriesId)
{
   switch(seriesId)
   {
      case OVERLAY_SERIES_MA1:       return InpMA1OverlayStyle;
      case OVERLAY_SERIES_MA2:       return InpMA2OverlayStyle;
      case OVERLAY_SERIES_MA3:       return InpMA3OverlayStyle;
      case OVERLAY_SERIES_MA4:       return InpMA4OverlayStyle;
      case OVERLAY_SERIES_MA5:       return InpMA5OverlayStyle;
      case OVERLAY_SERIES_VWAP1:     return InpVWAP1OverlayStyle;
      case OVERLAY_SERIES_VWAP3:     return InpVWAP3OverlayStyle;
      case OVERLAY_SERIES_VWAP_HIGH: return InpVWAPHighOverlayStyle;
      case OVERLAY_SERIES_VWAP_LOW:  return InpVWAPLowOverlayStyle;
   }
   return STYLE_SOLID;
}

int OverlaySeriesWidth(const int seriesId)
{
   switch(seriesId)
   {
      case OVERLAY_SERIES_MA1:       return InpMA1OverlayWidth;
      case OVERLAY_SERIES_MA2:       return InpMA2OverlayWidth;
      case OVERLAY_SERIES_MA3:       return InpMA3OverlayWidth;
      case OVERLAY_SERIES_MA4:       return InpMA4OverlayWidth;
      case OVERLAY_SERIES_MA5:       return InpMA5OverlayWidth;
      case OVERLAY_SERIES_VWAP1:     return InpVWAP1OverlayWidth;
      case OVERLAY_SERIES_VWAP3:     return InpVWAP3OverlayWidth;
      case OVERLAY_SERIES_VWAP_HIGH: return InpVWAPHighOverlayWidth;
      case OVERLAY_SERIES_VWAP_LOW:  return InpVWAPLowOverlayWidth;
   }
   return 1;
}

ENUM_MY_MA_METHOD OverlaySeriesMAMethod(const int maSlot)
{
   switch(maSlot)
   {
      case 0: return MA1_Method;
      case 1: return MA2_Method;
      case 2: return MA3_Method;
      case 3: return MA4_Method;
      case 4: return MA5_Method;
   }
   return MA1_Method;
}

ENUM_MY_MA_SOURCE OverlaySeriesMASource(const int maSlot)
{
   switch(maSlot)
   {
      case 0: return MA1_Source;
      case 1: return MA2_Source;
      case 2: return MA3_Source;
      case 3: return MA4_Source;
      case 4: return MA5_Source;
   }
   return MA1_Source;
}

void ResetIndicatorOverlayState()
{
   G_IndicatorOverlay.chartID = GetIndicatorOverlayChartID();
   G_IndicatorOverlay.initialized = false;
   G_IndicatorOverlay.dirty = false;
   G_IndicatorOverlay.chartSymbol = "";
   G_IndicatorOverlay.chartPeriod = PERIOD_CURRENT;
   G_IndicatorOverlay.chartSymbolIndex = -1;
   G_IndicatorOverlay.firstVisibleBar = -1;
   G_IndicatorOverlay.visibleBars = -1;
   G_IndicatorOverlay.atrHandle = INVALID_HANDLE;
   G_IndicatorOverlay.lastBarTime = 0;
   G_IndicatorOverlay.lastFullRedrawTick = 0;

   for(int i = 0; i < 5; i++)
   {
      G_IndicatorOverlay.activeMAPeriods[i] = 0;
      G_IndicatorOverlay.maHandles[i] = INVALID_HANDLE;
   }
}

void ReleaseIndicatorOverlayHandles()
{
   for(int i = 0; i < 5; i++)
   {
      if(G_IndicatorOverlay.maHandles[i] != INVALID_HANDLE)
      {
         IndicatorRelease(G_IndicatorOverlay.maHandles[i]);
         G_IndicatorOverlay.maHandles[i] = INVALID_HANDLE;
      }
   }

   if(G_IndicatorOverlay.atrHandle != INVALID_HANDLE)
   {
      IndicatorRelease(G_IndicatorOverlay.atrHandle);
      G_IndicatorOverlay.atrHandle = INVALID_HANDLE;
   }
}

void DeleteIndicatorOverlayObjects()
{
   ObjectsDeleteAll(GetIndicatorOverlayChartID(), MBV_PREFIX, -1, -1);
}

string ResolveOverlaySymbol()
{
   if(G_IndicatorOverlayForcedSymbol != "")
      return G_IndicatorOverlayForcedSymbol;

   string chartSymbol = ChartSymbol(GetIndicatorOverlayChartID());
   int visualIndex = ResolveVisualFocusSymbolIndex(chartSymbol);
   if(visualIndex >= 0 && visualIndex < ArraySize(SymbolData))
      return SymbolData[visualIndex].symbol;

   if(InpOverlayUseChartSymbol || chartSymbol == "")
      return chartSymbol;

   string baseSymbol = GetBaseSymbol(chartSymbol);
   if(baseSymbol != "")
      return baseSymbol;

   return chartSymbol;
}

int ResolveOverlayChartSymbolIndex()
{
   if(G_IndicatorOverlayForcedSymbolIndex >= 0)
      return G_IndicatorOverlayForcedSymbolIndex;

   string overlaySymbol = ResolveOverlaySymbol();
   int idx = ResolveVisualFocusSymbolIndex(overlaySymbol);
   if(idx >= 0)
      return idx;

   string baseSymbol = GetBaseSymbol(overlaySymbol);
   if(baseSymbol != "" && baseSymbol != overlaySymbol)
   {
      idx = ResolveVisualFocusSymbolIndex(baseSymbol);
      if(idx >= 0)
         return idx;
   }

   string chartSymbol = ChartSymbol(GetIndicatorOverlayChartID());
   if(InpOverlayUseChartSymbol && chartSymbol != "" && chartSymbol != overlaySymbol)
   {
      idx = ResolveVisualFocusSymbolIndex(chartSymbol);
      if(idx >= 0)
         return idx;

      baseSymbol = GetBaseSymbol(chartSymbol);
      if(baseSymbol != "" && baseSymbol != chartSymbol)
      {
         idx = ResolveVisualFocusSymbolIndex(baseSymbol);
         if(idx >= 0)
            return idx;
      }
   }

   return ResolveVisualFocusSymbolIndex(chartSymbol);
}

int OverlayGetPeriodSeconds(const ENUM_TIMEFRAMES tf)
{
   int seconds = PeriodSeconds(tf);
   if(seconds <= 0)
      seconds = 60;
   return seconds;
}

double OverlayAppliedPrice(const MqlRates &rate, const ENUM_APPLIED_PRICE source)
{
   switch(source)
   {
      case PRICE_CLOSE:    return rate.close;
      case PRICE_OPEN:     return rate.open;
      case PRICE_HIGH:     return rate.high;
      case PRICE_LOW:      return rate.low;
      case PRICE_MEDIAN:   return (rate.high + rate.low) / 2.0;
      case PRICE_TYPICAL:  return (rate.high + rate.low + rate.close) / 3.0;
      case PRICE_WEIGHTED: return (rate.high + rate.low + rate.close + rate.close) / 4.0;
   }
   return rate.close;
}

bool OverlayIsDrawableValue(const double value)
{
   return (value != EMPTY_VALUE);
}

bool OverlayCopyIndicatorValues(const int handle, const int barsToCopy, double &buffer[])
{
   ArrayResize(buffer, barsToCopy);
   ArraySetAsSeries(buffer, true);
   ArrayInitialize(buffer, EMPTY_VALUE);

   if(handle == INVALID_HANDLE)
      return false;

   int copied = CopyBuffer(handle, 0, 0, barsToCopy, buffer);
   if(copied <= 0)
      return false;

   for(int i = copied; i < barsToCopy; i++)
      buffer[i] = EMPTY_VALUE;

   return true;
}

void OverlayUpsertTrendSegment(const string name,
                               const datetime time1,
                               const double price1,
                               const datetime time2,
                               const double price2,
                               const color lineColor,
                               const ENUM_LINE_STYLE lineStyle,
                               const int lineWidth,
                               const string tooltipText = "")
{
   string tooltip = (tooltipText == "") ? name : tooltipText;
   long chartID = GetIndicatorOverlayChartID();

   if(ObjectFind(chartID, name) < 0)
      ObjectCreate(chartID, name, OBJ_TREND, 0, time1, price1, time2, price2);
   else
   {
      ObjectMove(chartID, name, 0, time1, price1);
      ObjectMove(chartID, name, 1, time2, price2);
   }

   ObjectSetInteger(chartID, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(chartID, name, OBJPROP_COLOR, lineColor);
   ObjectSetInteger(chartID, name, OBJPROP_STYLE, lineStyle);
   ObjectSetInteger(chartID, name, OBJPROP_WIDTH, MathMax(1, lineWidth));
   ObjectSetInteger(chartID, name, OBJPROP_BACK, true);
   ObjectSetInteger(chartID, name, OBJPROP_ZORDER, 0);
   ObjectSetInteger(chartID, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(chartID, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(chartID, name, OBJPROP_HIDDEN, true);
   ObjectSetString(chartID, name, OBJPROP_TOOLTIP, tooltip);
}

void OverlayUpsertFillSegment(const string name,
                              const datetime time1,
                              const datetime time2,
                              double topPrice,
                              double bottomPrice,
                              const color fillColor,
                              const string tooltipText = "")
{
   string tooltip = (tooltipText == "") ? name : tooltipText;
   long chartID = GetIndicatorOverlayChartID();

   if(bottomPrice > topPrice)
   {
      double temp = topPrice;
      topPrice = bottomPrice;
      bottomPrice = temp;
   }

   if(ObjectFind(chartID, name) < 0)
      ObjectCreate(chartID, name, OBJ_RECTANGLE, 0, time1, topPrice, time2, bottomPrice);
   else
   {
      ObjectMove(chartID, name, 0, time1, topPrice);
      ObjectMove(chartID, name, 1, time2, bottomPrice);
   }

   ObjectSetInteger(chartID, name, OBJPROP_COLOR, ColorToARGB(fillColor, 45));
   ObjectSetInteger(chartID, name, OBJPROP_FILL, true);
   ObjectSetInteger(chartID, name, OBJPROP_BACK, true);
   ObjectSetInteger(chartID, name, OBJPROP_ZORDER, 0);
   ObjectSetInteger(chartID, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(chartID, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(chartID, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(chartID, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(chartID, name, OBJPROP_HIDDEN, true);
   ObjectSetString(chartID, name, OBJPROP_TOOLTIP, tooltip);
}

void OverlayUpdateTextLabel(const string name,
                            const string text,
                            const datetime labelTime,
                            const double labelPrice,
                            const color labelColor,
                            const int fontSize,
                            const ENUM_ANCHOR_POINT anchor)
{
   long chartID = GetIndicatorOverlayChartID();

   if(ObjectFind(chartID, name) < 0)
      ObjectCreate(chartID, name, OBJ_TEXT, 0, labelTime, labelPrice);
   else
      ObjectMove(chartID, name, 0, labelTime, labelPrice);

   ObjectSetString(chartID, name, OBJPROP_TEXT, text);
   ObjectSetInteger(chartID, name, OBJPROP_COLOR, labelColor);
   ObjectSetInteger(chartID, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(chartID, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(chartID, name, OBJPROP_BACK, true);
   ObjectSetInteger(chartID, name, OBJPROP_ZORDER, 0);
   ObjectSetInteger(chartID, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(chartID, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(chartID, name, OBJPROP_HIDDEN, true);
}

void RefreshIndicatorOverlayHandles()
{
   string chartSymbol = ResolveOverlaySymbol();
   ENUM_TIMEFRAMES chartPeriod = G_IndicatorOverlayForcedPeriod;
   if(chartPeriod == PERIOD_CURRENT)
      chartPeriod = (ENUM_TIMEFRAMES)ChartPeriod(GetIndicatorOverlayChartID());
   int symbolIndex = ResolveOverlayChartSymbolIndex();

   int resolvedPeriods[5];
   for(int i = 0; i < 5; i++)
      resolvedPeriods[i] = GetActiveMAPeriod(symbolIndex, i);

   bool needsRebuild = !G_IndicatorOverlay.initialized;
   needsRebuild = needsRebuild || (chartSymbol != G_IndicatorOverlay.chartSymbol);
   needsRebuild = needsRebuild || (chartPeriod != G_IndicatorOverlay.chartPeriod);
   needsRebuild = needsRebuild || (symbolIndex != G_IndicatorOverlay.chartSymbolIndex);

   for(int i = 0; i < 5 && !needsRebuild; i++)
   {
      if(resolvedPeriods[i] != G_IndicatorOverlay.activeMAPeriods[i])
         needsRebuild = true;
   }

   if(!needsRebuild)
      return;

   ReleaseIndicatorOverlayHandles();

   G_IndicatorOverlay.chartSymbol = chartSymbol;
   G_IndicatorOverlay.chartPeriod = chartPeriod;
   G_IndicatorOverlay.chartSymbolIndex = symbolIndex;

   for(int i = 0; i < 5; i++)
      G_IndicatorOverlay.activeMAPeriods[i] = resolvedPeriods[i];

   if(symbolIndex < 0 || chartSymbol == "")
   {
      G_IndicatorOverlay.dirty = true;
      return;
   }

   for(int i = 0; i < 5; i++)
   {
      int period = MathMax(1, resolvedPeriods[i]);
      G_IndicatorOverlay.maHandles[i] = iMA(chartSymbol,
                                            chartPeriod,
                                            period,
                                            0,
                                            GetMAMethod(OverlaySeriesMAMethod(i)),
                                            GetMASource(OverlaySeriesMASource(i)));
   }

   G_IndicatorOverlay.atrHandle = iATR(chartSymbol, chartPeriod, ATR_Period);
   G_IndicatorOverlay.dirty = true;
}

void MarkIndicatorOverlayDirty()
{
   G_IndicatorOverlay.dirty = true;
   for(int i = 0; i < ArraySize(G_IndicatorOverlayStates); i++)
      G_IndicatorOverlayStates[i].dirty = true;
}

void InitIndicatorOverlay()
{
   ResetIndicatorOverlayState();
   G_IndicatorOverlay.initialized = true;
   G_IndicatorOverlay.dirty = true;
}

void DestroyIndicatorOverlayForChart(const long chartID)
{
   BeginIndicatorOverlayContext(chartID);
   ReleaseIndicatorOverlayHandles();
   DeleteIndicatorOverlayObjects();
   ResetIndicatorOverlayState();
   SaveIndicatorOverlayContext();
   G_IndicatorOverlayContextChartID = 0;
   G_IndicatorOverlayForcedSymbol = "";
   G_IndicatorOverlayForcedPeriod = PERIOD_CURRENT;
   G_IndicatorOverlayForcedSymbolIndex = -1;
}

void DestroyIndicatorOverlay()
{
   DestroyIndicatorOverlayForChart(0);
}

void ComputeOverlayVWAPSeries(const MqlRates &rates[],
                              const int barsCount,
                              double &bufferVWAP1[],
                              double &bufferVWAP3[],
                              double &bufferVWAPHigh[],
                              double &bufferVWAPLow[])
{
   ArrayResize(bufferVWAP1, barsCount);
   ArrayResize(bufferVWAP3, barsCount);
   ArrayResize(bufferVWAPHigh, barsCount);
   ArrayResize(bufferVWAPLow, barsCount);

   ArrayInitialize(bufferVWAP1, EMPTY_VALUE);
   ArrayInitialize(bufferVWAP3, EMPTY_VALUE);
   ArrayInitialize(bufferVWAPHigh, EMPTY_VALUE);
   ArrayInitialize(bufferVWAPLow, EMPTY_VALUE);

   bool needVWAP1 = OverlaySeriesEnabled(OVERLAY_SERIES_VWAP1);
   bool needVWAP3 = OverlaySeriesEnabled(OVERLAY_SERIES_VWAP3);
   bool needDynamic = OverlaySeriesEnabled(OVERLAY_SERIES_VWAP_HIGH) ||
                      OverlaySeriesEnabled(OVERLAY_SERIES_VWAP_LOW) ||
                      OverlayVWAPCloudEnabled();

   SVWAPData stateVWAP1;
   SVWAPData stateVWAP3;

   stateVWAP1.Value = 0.0;
   stateVWAP1.CumulativePV = 0.0;
   stateVWAP1.CumulativeVolume = 0.0;
   stateVWAP1.LastResetTime = 0;
   stateVWAP1.StartTime = 0;
   stateVWAP1.SessionHigh = 0.0;
   stateVWAP1.SessionLow = 0.0;
   stateVWAP1.Initialized = false;

   stateVWAP3 = stateVWAP1;

   double cumPVHigh = 0.0;
   double cumVolHigh = 0.0;
   double cumPVLow = 0.0;
   double cumVolLow = 0.0;

   for(int shift = barsCount - 1; shift >= 0; shift--)
   {
      double volume = (double)rates[shift].tick_volume;
      datetime barTime = rates[shift].time;

      if(needVWAP1)
      {
         if(CheckVWAPReset(barTime, stateVWAP1, 1))
            ResetVWAPData(stateVWAP1, barTime, 1);

         CalculateVWAPValue(OverlayAppliedPrice(rates[shift], VWAP1_PriceSource), (long)volume, stateVWAP1);
         bufferVWAP1[shift] = stateVWAP1.Value;
      }

      if(needVWAP3)
      {
         if(CheckVWAPReset(barTime, stateVWAP3, 3))
            ResetVWAPData(stateVWAP3, barTime, 3);

         CalculateVWAPValue(OverlayAppliedPrice(rates[shift], VWAP3_PriceSource), (long)volume, stateVWAP3);
         bufferVWAP3[shift] = stateVWAP3.Value;
      }

      if(needDynamic)
      {
         if(shift < barsCount - 1)
         {
            double prevHighVWAP = bufferVWAPHigh[shift + 1];
            double prevLowVWAP = bufferVWAPLow[shift + 1];
            double prevClose = rates[shift + 1].close;

            if(OverlayIsDrawableValue(prevHighVWAP) && prevClose > prevHighVWAP)
            {
               cumPVHigh = 0.0;
               cumVolHigh = 0.0;
            }

            if(OverlayIsDrawableValue(prevLowVWAP) && prevClose < prevLowVWAP)
            {
               cumPVLow = 0.0;
               cumVolLow = 0.0;
            }
         }

         double priceHigh = OverlayAppliedPrice(rates[shift], VH_Source);
         double priceLow = OverlayAppliedPrice(rates[shift], VL_Source);

         cumPVHigh += priceHigh * volume;
         cumVolHigh += volume;
         cumPVLow += priceLow * volume;
         cumVolLow += volume;

         bufferVWAPHigh[shift] = (cumVolHigh > 0.0) ? (cumPVHigh / cumVolHigh) : priceHigh;
         bufferVWAPLow[shift] = (cumVolLow > 0.0) ? (cumPVLow / cumVolLow) : priceLow;
      }
   }
}

void DrawOverlaySeriesHistory(const int seriesId,
                              const MqlRates &rates[],
                              double &values[],
                              const int barsCount,
                              const int leftShift,
                              const int rightShift)
{
   if(!OverlaySeriesEnabled(seriesId))
      return;

   color lineColor = OverlaySeriesColor(seriesId);
   ENUM_LINE_STYLE lineStyle = OverlaySeriesStyle(seriesId);
   int lineWidth = OverlaySeriesWidth(seriesId);
   string token = OverlaySeriesToken(seriesId);

   for(int shift = leftShift; shift > rightShift; shift--)
   {
      if(shift >= barsCount || (shift - 1) < 0)
         continue;

      if(!OverlayIsDrawableValue(values[shift]) || !OverlayIsDrawableValue(values[shift - 1]))
         continue;

      string name = MBV_PREFIX + "SEG_" + token + "_" + IntegerToString(shift);
      OverlayUpsertTrendSegment(name,
                                rates[shift].time,
                                values[shift],
                                rates[shift - 1].time,
                                values[shift - 1],
                                lineColor,
                                lineStyle,
                                lineWidth,
                                OverlaySeriesDescription(seriesId));
   }
}

void DrawOverlayCloudHistory(const MqlRates &rates[],
                             double &bufferHigh[],
                             double &bufferLow[],
                             const int barsCount,
                             const int leftShift,
                             const int rightShift)
{
   if(!OverlayVWAPCloudEnabled())
      return;

   for(int shift = leftShift; shift > rightShift; shift--)
   {
      if(shift >= barsCount || (shift - 1) < 0)
         continue;

      if(!OverlayIsDrawableValue(bufferHigh[shift]) ||
         !OverlayIsDrawableValue(bufferHigh[shift - 1]) ||
         !OverlayIsDrawableValue(bufferLow[shift]) ||
         !OverlayIsDrawableValue(bufferLow[shift - 1]))
      {
         continue;
      }

      double topPrice = MathMax(bufferHigh[shift], bufferHigh[shift - 1]);
      double bottomPrice = MathMin(bufferLow[shift], bufferLow[shift - 1]);
      string name = MBV_PREFIX + "FILL_" + IntegerToString(shift);

      OverlayUpsertFillSegment(name,
                               rates[shift].time,
                               rates[shift - 1].time,
                               topPrice,
                               bottomPrice,
                               InpVWAPCloudColor,
                               OverlayCloudDescription());
   }
}

void UpdateIndicatorOverlayTail()
{
   if(!InpShowIndicatorOverlay || G_IndicatorOverlay.chartSymbolIndex < 0)
      return;

   long chartID = GetIndicatorOverlayChartID();

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(G_IndicatorOverlay.chartSymbol, G_IndicatorOverlay.chartPeriod, 0, 2, rates);
   if(copied < 2)
      return;

   int periodSeconds = OverlayGetPeriodSeconds(G_IndicatorOverlay.chartPeriod);
   datetime tailEndTime = rates[0].time + periodSeconds;

   for(int i = 0; i < 5; i++)
   {
      string token = OverlaySeriesToken(i);
      string name = MBV_PREFIX + "TAIL_" + token;

      if(!OverlaySeriesEnabled(i))
      {
         ObjectDelete(chartID, name);
         continue;
      }

      double values[];
      if(!OverlayCopyIndicatorValues(G_IndicatorOverlay.maHandles[i], 2, values))
      {
         ObjectDelete(chartID, name);
         continue;
      }

      if(!OverlayIsDrawableValue(values[1]) || !OverlayIsDrawableValue(values[0]))
      {
         ObjectDelete(chartID, name);
         continue;
      }

      OverlayUpsertTrendSegment(name,
                                rates[1].time,
                                values[1],
                                tailEndTime,
                                values[0],
                                OverlaySeriesColor(i),
                                OverlaySeriesStyle(i),
                                OverlaySeriesWidth(i),
                                OverlaySeriesDescription(i));
   }

   int chartIdx = G_IndicatorOverlay.chartSymbolIndex;

   int tailSeries[4] =
      {
         OVERLAY_SERIES_VWAP1,
         OVERLAY_SERIES_VWAP3,
         OVERLAY_SERIES_VWAP_HIGH,
         OVERLAY_SERIES_VWAP_LOW
      };

   double tailValues[4] =
      {
         SymbolData[chartIdx].VWAP1.Value,
         SymbolData[chartIdx].VWAP3.Value,
         SymbolData[chartIdx].VWAP2_High.Value,
         SymbolData[chartIdx].VWAP2_Low.Value
      };

   for(int j = 0; j < 4; j++)
   {
      string token = OverlaySeriesToken(tailSeries[j]);
      string name = MBV_PREFIX + "TAIL_" + token;

      if(!OverlaySeriesEnabled(tailSeries[j]) || tailValues[j] <= 0.0)
      {
         ObjectDelete(chartID, name);
         continue;
      }

      OverlayUpsertTrendSegment(name,
                                rates[1].time,
                                tailValues[j],
                                tailEndTime,
                                tailValues[j],
                                OverlaySeriesColor(tailSeries[j]),
                                OverlaySeriesStyle(tailSeries[j]),
                                OverlaySeriesWidth(tailSeries[j]),
                                OverlaySeriesDescription(tailSeries[j]));
   }

   string fillName = MBV_PREFIX + "TAIL_FILL";
   if(OverlayVWAPCloudEnabled() &&
      SymbolData[chartIdx].VWAP2_High.Value > 0.0 &&
      SymbolData[chartIdx].VWAP2_Low.Value > 0.0)
   {
      OverlayUpsertFillSegment(fillName,
                               rates[1].time,
                               tailEndTime,
                               SymbolData[chartIdx].VWAP2_High.Value,
                               SymbolData[chartIdx].VWAP2_Low.Value,
                               InpVWAPCloudColor,
                               OverlayCloudDescription());
   }
   else
   {
      ObjectDelete(chartID, fillName);
   }
}

void UpdateIndicatorOverlayLabels()
{
   string labelAtr = MBV_PREFIX + "LBL_ATR";
   string labelTrend = MBV_PREFIX + "LBL_TREND";
   long chartID = GetIndicatorOverlayChartID();

   if(!InpShowIndicatorOverlay || !InpShowIndicatorOverlayLabels || G_IndicatorOverlay.chartSymbolIndex < 0)
   {
      ObjectDelete(chartID, labelAtr);
      ObjectDelete(chartID, labelTrend);
      return;
   }

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(G_IndicatorOverlay.chartSymbol, G_IndicatorOverlay.chartPeriod, 0, 1, rates);
   if(copied < 1)
      return;

   double atrValues[];
   double atrValue = 0.0;
   if(OverlayCopyIndicatorValues(G_IndicatorOverlay.atrHandle, 1, atrValues))
      atrValue = atrValues[0];

   double maCurrent[5];
   ArrayInitialize(maCurrent, 0.0);

   for(int i = 0; i < 5; i++)
   {
      double values[];
      if(OverlayCopyIndicatorValues(G_IndicatorOverlay.maHandles[i], 1, values))
         maCurrent[i] = values[0];
   }

   string trendText = "CHOPPY";
   color trendColor = clrGray;

   if(maCurrent[0] > 0.0 && maCurrent[1] > 0.0 && maCurrent[2] > 0.0 &&
      maCurrent[3] > 0.0 && maCurrent[4] > 0.0)
   {
      if(maCurrent[0] > maCurrent[1] &&
         maCurrent[1] > maCurrent[2] &&
         maCurrent[2] > maCurrent[3] &&
         maCurrent[3] > maCurrent[4])
      {
         trendText = "STRONG BULLISH";
         trendColor = clrLime;
      }
      else if(maCurrent[0] < maCurrent[1] &&
              maCurrent[1] < maCurrent[2] &&
              maCurrent[2] < maCurrent[3] &&
              maCurrent[3] < maCurrent[4])
      {
         trendText = "STRONG BEARISH";
         trendColor = clrRed;
      }
   }

   double point = SymbolInfoDouble(G_IndicatorOverlay.chartSymbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(G_IndicatorOverlay.chartSymbol, SYMBOL_DIGITS);
   int periodSeconds = OverlayGetPeriodSeconds(G_IndicatorOverlay.chartPeriod);
   datetime labelTime = rates[0].time + (periodSeconds * MathMax(0, InpIndicatorOverlayLabelShiftBars));
   double offset = InpIndicatorOverlayLabelOffsetPts * point;

   OverlayUpdateTextLabel(labelAtr,
                          "ATR: " + DoubleToString(atrValue, digits),
                          labelTime,
                          rates[0].high + offset,
                          clrWhite,
                          InpIndicatorOverlayLabelFontSize,
                          ANCHOR_LEFT_LOWER);

   OverlayUpdateTextLabel(labelTrend,
                          trendText,
                          labelTime,
                          rates[0].low - offset,
                          trendColor,
                          InpIndicatorOverlayLabelFontSize,
                          ANCHOR_LEFT_UPPER);
}

void RedrawIndicatorOverlayHistory()
{
   if(!InpShowIndicatorOverlay || G_IndicatorOverlay.chartSymbolIndex < 0)
   {
      DeleteIndicatorOverlayObjects();
      return;
   }

   int totalBars = Bars(G_IndicatorOverlay.chartSymbol, G_IndicatorOverlay.chartPeriod);
   if(totalBars < 3)
      return;

   int leftVisible = (G_IndicatorOverlay.firstVisibleBar >= 0) ? G_IndicatorOverlay.firstVisibleBar : 0;
   int visibleBars = (G_IndicatorOverlay.visibleBars > 0) ? G_IndicatorOverlay.visibleBars : 150;
   int historyMargin = 25;
   int historyDepth = MathMin(totalBars, MathMax(leftVisible + historyMargin + 2, 2500));

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(G_IndicatorOverlay.chartSymbol, G_IndicatorOverlay.chartPeriod, 0, historyDepth, rates);
   if(copied < 3)
      return;

   int leftShift = MathMin(copied - 1, leftVisible + historyMargin);
   int rightShift = MathMax(1, leftVisible - visibleBars - historyMargin);

   DeleteIndicatorOverlayObjects();

   double ma1[];
   double ma2[];
   double ma3[];
   double ma4[];
   double ma5[];

   OverlayCopyIndicatorValues(G_IndicatorOverlay.maHandles[0], copied, ma1);
   OverlayCopyIndicatorValues(G_IndicatorOverlay.maHandles[1], copied, ma2);
   OverlayCopyIndicatorValues(G_IndicatorOverlay.maHandles[2], copied, ma3);
   OverlayCopyIndicatorValues(G_IndicatorOverlay.maHandles[3], copied, ma4);
   OverlayCopyIndicatorValues(G_IndicatorOverlay.maHandles[4], copied, ma5);

   double vwap1[];
   double vwap3[];
   double vwapHigh[];
   double vwapLow[];
   ComputeOverlayVWAPSeries(rates, copied, vwap1, vwap3, vwapHigh, vwapLow);

   DrawOverlaySeriesHistory(OVERLAY_SERIES_MA1, rates, ma1, copied, leftShift, rightShift);
   DrawOverlaySeriesHistory(OVERLAY_SERIES_MA2, rates, ma2, copied, leftShift, rightShift);
   DrawOverlaySeriesHistory(OVERLAY_SERIES_MA3, rates, ma3, copied, leftShift, rightShift);
   DrawOverlaySeriesHistory(OVERLAY_SERIES_MA4, rates, ma4, copied, leftShift, rightShift);
   DrawOverlaySeriesHistory(OVERLAY_SERIES_MA5, rates, ma5, copied, leftShift, rightShift);
   DrawOverlaySeriesHistory(OVERLAY_SERIES_VWAP1, rates, vwap1, copied, leftShift, rightShift);
   DrawOverlaySeriesHistory(OVERLAY_SERIES_VWAP3, rates, vwap3, copied, leftShift, rightShift);
   DrawOverlaySeriesHistory(OVERLAY_SERIES_VWAP_HIGH, rates, vwapHigh, copied, leftShift, rightShift);
   DrawOverlaySeriesHistory(OVERLAY_SERIES_VWAP_LOW, rates, vwapLow, copied, leftShift, rightShift);
   DrawOverlayCloudHistory(rates, vwapHigh, vwapLow, copied, leftShift, rightShift);

   UpdateIndicatorOverlayTail();
   UpdateIndicatorOverlayLabels();
}

void RefreshIndicatorOverlayForChart(const long chartID,
                                     const string preferredSymbol,
                                     const ENUM_TIMEFRAMES preferredPeriod,
                                     const int preferredSymbolIndex,
                                     const bool allowFullRedraw)
{
   BeginIndicatorOverlayContext(chartID, preferredSymbol, preferredPeriod, preferredSymbolIndex);

   if(G_IS_DEINIT)
   {
      EndIndicatorOverlayContext();
      return;
   }

   if(!InpShowIndicatorOverlay)
   {
      DestroyIndicatorOverlayForChart(chartID);
      return;
   }

   if(!G_IndicatorOverlay.initialized)
      InitIndicatorOverlay();

   RefreshIndicatorOverlayHandles();

   string chartSymbol = ResolveOverlaySymbol();
   ENUM_TIMEFRAMES chartPeriod = preferredPeriod;
   if(chartPeriod == PERIOD_CURRENT)
      chartPeriod = (ENUM_TIMEFRAMES)ChartPeriod(chartID);
   datetime currentBarTime = iTime(chartSymbol, chartPeriod, 0);
   int firstVisible = (int)ChartGetInteger(chartID, CHART_FIRST_VISIBLE_BAR);
   int visibleBars = (int)ChartGetInteger(chartID, CHART_VISIBLE_BARS);

   if(firstVisible != G_IndicatorOverlay.firstVisibleBar ||
      visibleBars != G_IndicatorOverlay.visibleBars)
   {
      G_IndicatorOverlay.firstVisibleBar = firstVisible;
      G_IndicatorOverlay.visibleBars = visibleBars;
      G_IndicatorOverlay.dirty = true;
   }

   if(currentBarTime != 0 && currentBarTime != G_IndicatorOverlay.lastBarTime)
   {
      G_IndicatorOverlay.lastBarTime = currentBarTime;
      G_IndicatorOverlay.dirty = true;
   }

   if(allowFullRedraw && G_IndicatorOverlay.dirty)
   {
      uint now = GetTickCount();
      if(now - G_IndicatorOverlay.lastFullRedrawTick >= 250)
      {
         RedrawIndicatorOverlayHistory();
         G_IndicatorOverlay.lastFullRedrawTick = now;
         G_IndicatorOverlay.dirty = false;
      }
   }

   UpdateIndicatorOverlayTail();
   UpdateIndicatorOverlayLabels();
   EndIndicatorOverlayContext();
}

void RefreshIndicatorOverlay(const bool allowFullRedraw)
{
   int focusIndex = ResolveDashboardHostFocusSymbolIndex(ChartSymbol(0));
   string focusSymbol = "";
   if(focusIndex >= 0 && focusIndex < ArraySize(SymbolData))
      focusSymbol = SymbolData[focusIndex].symbol;

   RefreshIndicatorOverlayForChart(0, focusSymbol, PERIOD_CURRENT, focusIndex, allowFullRedraw);
}




#endif // __MULTIBOTPRO_VISUALOVERLAY_MQH__

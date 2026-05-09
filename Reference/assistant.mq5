//+------------------------------------------------------------------+
//|                                        MultiBot_Companion_v7.mq5 |
//|                      Companion Indicator for MultiBotPro EA      |
//|                    Optimized: Incremental State (No Lag)         |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Expert Advisor Pro"
#property description "Visualizes MAs and Standard VWAPs (Daily & Session)."
#property indicator_chart_window
// INCREASED BUFFERS TO STORE INTERNAL STATE (Calculations)
#property indicator_buffers 17
#property indicator_plots   10

// --- PLOT DEFINITIONS ---
#property indicator_label1  "MA 1"
#property indicator_type1   DRAW_LINE
#property indicator_label2  "MA 2"
#property indicator_type2   DRAW_LINE
#property indicator_label3  "MA 3"
#property indicator_type3   DRAW_LINE
#property indicator_label4  "MA 4"
#property indicator_type4   DRAW_LINE
#property indicator_label5  "MA 5"
#property indicator_type5   DRAW_LINE
#property indicator_label6  "VWAP 1 (Continuous)"
#property indicator_type6   DRAW_LINE
#property indicator_label7  "VWAP 3 (Session)"
#property indicator_type7   DRAW_LINE
#property indicator_label8  "VWAP High (Dynamic)"
#property indicator_type8   DRAW_LINE
#property indicator_label9  "VWAP Low (Dynamic)"
#property indicator_type9   DRAW_LINE
#property indicator_label10 "VWAP Cloud"
#property indicator_type10  DRAW_FILLING

// --- ENUMS ---
enum ENUM_MY_MA_METHOD {
   MY_MODE_EMA,   // EMA
   MY_MODE_SMA,   // SMA
   MY_MODE_SMMA,  // SMMA
   MY_MODE_LWMA,  // LWMA
   MY_MODE_VWMA   // VWMA
};

// --- INPUTS ---
input group "=== TIME & DATE SETTINGS ==="
input int      Broker_GMT_Offset = 2;      // Broker Offset (e.g., +2 Winter, +3 Summer)
input bool     NY_DST_Mode       = false;  // Daylight Savings? (True = GMT-4, False = GMT-5)

input group "=== MA 1 SETTINGS ==="
input bool     ShowMA1           = false;
input int      MA1_Period        = 5;
input ENUM_MY_MA_METHOD MA1_Method = MY_MODE_EMA;
input color    MA1_Color         = clrLime;
input ENUM_LINE_STYLE MA1_Style  = STYLE_SOLID;
input int      MA1_Width         = 1;

input group "=== MA 2 SETTINGS ==="
input bool     ShowMA2           = false;
input int      MA2_Period        = 10;
input ENUM_MY_MA_METHOD MA2_Method = MY_MODE_EMA;
input color    MA2_Color         = clrGreen;
input ENUM_LINE_STYLE MA2_Style  = STYLE_SOLID;
input int      MA2_Width         = 1;

input group "=== MA 3 SETTINGS ==="
input bool     ShowMA3           = true;
input int      MA3_Period        = 20;
input ENUM_MY_MA_METHOD MA3_Method = MY_MODE_EMA;
input color    MA3_Color         = clrBlue;
input ENUM_LINE_STYLE MA3_Style  = STYLE_SOLID;
input int      MA3_Width         = 1;

input group "=== MA 4 SETTINGS ==="
input bool     ShowMA4           = true;
input int      MA4_Period        = 50;
input ENUM_MY_MA_METHOD MA4_Method = MY_MODE_EMA;
input color    MA4_Color         = clrOliveDrab;
input ENUM_LINE_STYLE MA4_Style  = STYLE_SOLID;
input int      MA4_Width         = 2;

input group "=== MA 5 SETTINGS ==="
input bool     ShowMA5           = false;
input int      MA5_Period        = 200;
input ENUM_MY_MA_METHOD MA5_Method = MY_MODE_EMA;
input color    MA5_Color         = clrRed;
input ENUM_LINE_STYLE MA5_Style  = STYLE_SOLID;
input int      MA5_Width         = 2;

input group "=== VWAP 1 (Daily/Reset) ==="
input bool     ShowVWAP1         = false;
input ENUM_APPLIED_PRICE V1_Source = PRICE_TYPICAL;
input color    V1_Color          = clrAqua;
input ENUM_LINE_STYLE V1_Style   = STYLE_DASHDOT;
input int      V1_Width          = 2;

input group "=== VWAP High (Dynamic) ==="
input bool     ShowVWAP_High     = true;
input ENUM_APPLIED_PRICE VH_Source = PRICE_HIGH;
input color    VH_Color          = clrMagenta;
input ENUM_LINE_STYLE VH_Style   = STYLE_DOT;
input int      VH_Width          = 1;

input group "=== VWAP Low (Dynamic) ==="
input bool     ShowVWAP_Low      = true;
input ENUM_APPLIED_PRICE VL_Source = PRICE_LOW;
input color    VL_Color          = clrMagenta;
input ENUM_LINE_STYLE VL_Style   = STYLE_DOT;
input int      VL_Width          = 1;

input group "=== VWAP Cloud Fill ==="
input bool     ShowVWAP_Fill     = false;
input color    VWAP_Fill_Color   = clrAliceBlue;

input group "=== VWAP 3 (NY Session) ==="
input bool     ShowVWAP3         = true;
input ENUM_APPLIED_PRICE V3_Source = PRICE_TYPICAL;
input color    V3_Color          = clrGold;
input ENUM_LINE_STYLE V3_Style   = STYLE_SOLID;
input int      V3_Width          = 2;

input group "=== ON-CHART LABELS ==="
input int      ATR_Period        = 100;
input int      Label_Offset_Pts  = 100;

// --- BUFFERS ---
double BufferMA1[];
double BufferMA2[];
double BufferMA3[];
double BufferMA4[];
double BufferMA5[];
double BufferVWAP1[];
double BufferVWAP3[];
double BufferVWAP2_H[];
double BufferVWAP2_L[];
double BufferFillH[];
double BufferFillL[];

// --- INTERNAL STATE BUFFERS (Optimization) ---
// These buffers store the running math so we don't have to recalculate history
double Buf_H_PV[];
double Buf_H_Vol[];
double Buf_H_Ext[]; // Extreme High Tracker
double Buf_L_PV[];
double Buf_L_Vol[];
double Buf_L_Ext[]; // Extreme Low Tracker

// --- HANDLES ---
int hMA1, hMA2, hMA3, hMA4, hMA5;
int hATR;

// --- GLOBALS ---
int ServerResetHour1 = 0;
int ServerResetHour3 = 0;
int NY_Min_3         = 30;
string ObjNameTop = "MB_Label_Top";
string ObjNameBot = "MB_Label_Bot";

// --- VWAP STRUCTURES ---
struct SVWAPCalc {
   double cumPV;
   double cumVol;
};

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // 1. Calculate Time Offsets
   int nyOffset = NY_DST_Mode ? -4 : -5;
   int gmtHour1 = 17 - nyOffset;
   ServerResetHour1 = (gmtHour1 + Broker_GMT_Offset) % 24;
   int gmtHour3 = 9 - nyOffset;
   ServerResetHour3 = (gmtHour3 + Broker_GMT_Offset) % 24;
   
   if(ServerResetHour1 < 0) ServerResetHour1 += 24;
   if(ServerResetHour3 < 0) ServerResetHour3 += 24;

   // 2. Map Buffers
   SetIndexBuffer(0, BufferMA1, INDICATOR_DATA);
   SetIndexBuffer(1, BufferMA2, INDICATOR_DATA);
   SetIndexBuffer(2, BufferMA3, INDICATOR_DATA);
   SetIndexBuffer(3, BufferMA4, INDICATOR_DATA);
   SetIndexBuffer(4, BufferMA5, INDICATOR_DATA);
   SetIndexBuffer(5, BufferVWAP1, INDICATOR_DATA);
   SetIndexBuffer(6, BufferVWAP3, INDICATOR_DATA);
   SetIndexBuffer(7, BufferVWAP2_H, INDICATOR_DATA);
   SetIndexBuffer(8, BufferVWAP2_L, INDICATOR_DATA);
   SetIndexBuffer(9, BufferFillH, INDICATOR_DATA);
   SetIndexBuffer(10, BufferFillL, INDICATOR_DATA);

   // Map State Buffers (Hidden calculations)
   SetIndexBuffer(11, Buf_H_PV, INDICATOR_CALCULATIONS);
   SetIndexBuffer(12, Buf_H_Vol, INDICATOR_CALCULATIONS);
   SetIndexBuffer(13, Buf_H_Ext, INDICATOR_CALCULATIONS);
   SetIndexBuffer(14, Buf_L_PV, INDICATOR_CALCULATIONS);
   SetIndexBuffer(15, Buf_L_Vol, INDICATOR_CALCULATIONS);
   SetIndexBuffer(16, Buf_L_Ext, INDICATOR_CALCULATIONS);

   // 3. Apply Visual Styles
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, MA1_Color); PlotIndexSetInteger(0, PLOT_LINE_STYLE, MA1_Style); PlotIndexSetInteger(0, PLOT_LINE_WIDTH, MA1_Width);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, MA2_Color); PlotIndexSetInteger(1, PLOT_LINE_STYLE, MA2_Style); PlotIndexSetInteger(1, PLOT_LINE_WIDTH, MA2_Width);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, MA3_Color); PlotIndexSetInteger(2, PLOT_LINE_STYLE, MA3_Style); PlotIndexSetInteger(2, PLOT_LINE_WIDTH, MA3_Width);
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, MA4_Color); PlotIndexSetInteger(3, PLOT_LINE_STYLE, MA4_Style); PlotIndexSetInteger(3, PLOT_LINE_WIDTH, MA4_Width);
   PlotIndexSetInteger(4, PLOT_LINE_COLOR, MA5_Color); PlotIndexSetInteger(4, PLOT_LINE_STYLE, MA5_Style); PlotIndexSetInteger(4, PLOT_LINE_WIDTH, MA5_Width);
   
   PlotIndexSetInteger(5, PLOT_LINE_COLOR, V1_Color);  PlotIndexSetInteger(5, PLOT_LINE_STYLE, V1_Style);  PlotIndexSetInteger(5, PLOT_LINE_WIDTH, V1_Width);
   PlotIndexSetInteger(6, PLOT_LINE_COLOR, V3_Color);  PlotIndexSetInteger(6, PLOT_LINE_STYLE, V3_Style);  PlotIndexSetInteger(6, PLOT_LINE_WIDTH, V3_Width);
   PlotIndexSetInteger(7, PLOT_LINE_COLOR, VH_Color);  PlotIndexSetInteger(7, PLOT_LINE_STYLE, VH_Style);  PlotIndexSetInteger(7, PLOT_LINE_WIDTH, VH_Width);
   PlotIndexSetInteger(8, PLOT_LINE_COLOR, VL_Color);  PlotIndexSetInteger(8, PLOT_LINE_STYLE, VL_Style);  PlotIndexSetInteger(8, PLOT_LINE_WIDTH, VL_Width);
   PlotIndexSetInteger(9, PLOT_LINE_COLOR, VWAP_Fill_Color); PlotIndexSetInteger(9, PLOT_SHOW_DATA, false);
   
   // 4. Initialize Handles
   hMA1 = CreateMAHandle(MA1_Period, MA1_Method);
   hMA2 = CreateMAHandle(MA2_Period, MA2_Method);
   hMA3 = CreateMAHandle(MA3_Period, MA3_Method);
   hMA4 = CreateMAHandle(MA4_Period, MA4_Method);
   hMA5 = CreateMAHandle(MA5_Period, MA5_Method);
   hATR = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);

   // 5. Initialize Empties
   for(int i=0; i<17; i++) PlotIndexSetDouble(i, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Iteration (Optimized - Incremental Calculation)                  |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < MA5_Period) return 0;

   // 1. Process MAs
   ProcessMA(hMA1, BufferMA1, ShowMA1, rates_total, prev_calculated);
   ProcessMA(hMA2, BufferMA2, ShowMA2, rates_total, prev_calculated);
   ProcessMA(hMA3, BufferMA3, ShowMA3, rates_total, prev_calculated);
   ProcessMA(hMA4, BufferMA4, ShowMA4, rates_total, prev_calculated);
   ProcessMA(hMA5, BufferMA5, ShowMA5, rates_total, prev_calculated);

   // 2. Process VWAPs (Merged Logic)
   int start = (prev_calculated > 0) ? prev_calculated - 1 : 0;
   if(start < 0) start = 0;

   static SVWAPCalc V1, V3;

   // Initialization Block
   if(start == 0) {
      ResetVWAP(V1);
      ResetVWAP(V3);
      ArrayInitialize(BufferVWAP1, EMPTY_VALUE);
      ArrayInitialize(BufferVWAP3, EMPTY_VALUE);
      ArrayInitialize(BufferVWAP2_H, EMPTY_VALUE);
      ArrayInitialize(BufferVWAP2_L, EMPTY_VALUE);
      ArrayInitialize(BufferFillH, EMPTY_VALUE);
      ArrayInitialize(BufferFillL, EMPTY_VALUE);
      // Init State Buffers
      ArrayInitialize(Buf_H_PV, 0); ArrayInitialize(Buf_H_Vol, 0); ArrayInitialize(Buf_H_Ext, -DBL_MAX);
      ArrayInitialize(Buf_L_PV, 0); ArrayInitialize(Buf_L_Vol, 0); ArrayInitialize(Buf_L_Ext, DBL_MAX);
   }

   // --- SINGLE PASS LOOP FOR ALL INDICATORS ---
   // We now calculate everything incrementally in one pass, ensuring O(1) speed per tick.
   for(int i = start; i < rates_total; i++)
   {
      MqlDateTime dt;
      TimeToStruct(time[i], dt);
      
      double priceV1 = GetPrice(i, V1_Source, open, high, low, close);
      double priceV3 = GetPrice(i, V3_Source, open, high, low, close);
      double vol = (double)tick_volume[i];

      // --- VWAP 1 (Daily) ---
      if(ShowVWAP1) {
         if(IsResetTime(i, dt, ServerResetHour1, 0, time)) ResetVWAP(V1);
         UpdateVWAPStruct(V1, priceV1, vol);
         BufferVWAP1[i] = (V1.cumVol > 0) ? V1.cumPV / V1.cumVol : priceV1;
      } else BufferVWAP1[i] = EMPTY_VALUE;

      // --- VWAP 3 (Session) ---
      if(ShowVWAP3) {
         if(IsResetTime(i, dt, ServerResetHour3, NY_Min_3, time)) ResetVWAP(V3);
         UpdateVWAPStruct(V3, priceV3, vol);
         BufferVWAP3[i] = (V3.cumVol > 0) ? V3.cumPV / V3.cumVol : priceV3;
      } else BufferVWAP3[i] = EMPTY_VALUE;

      // --- DYNAMIC VWAP (High/Low) - OPTIMIZED ---
      // Instead of recalculating 1000 bars, we pick up the state from [i-1].
      if(ShowVWAP_High) {
         double prevPV = (i > 0) ? Buf_H_PV[i-1] : 0;
         double prevVol = (i > 0) ? Buf_H_Vol[i-1] : 0;
         double prevExt = (i > 0) ? Buf_H_Ext[i-1] : -DBL_MAX;

         // Check for Breakout on the PREVIOUS bar (Completed history)
         // If i-1 closed ABOVE its VWAP, we reset starting at i.
         bool reset = false;
         if(i > 0) {
             double prevVWAP = (prevVol > 0) ? prevPV / prevVol : 0;
             if(prevVWAP > 0 && close[i-1] > prevVWAP) reset = true;
         }
         
         if(reset) {
             prevPV = 0; prevVol = 0; prevExt = -DBL_MAX;
         }

         // Current Calculation
         if(high[i] > prevExt) prevExt = high[i];
         
         double price = GetPrice(i, VH_Source, open, high, low, close);
         double curPV = prevPV + (price * vol);
         double curVol = prevVol + vol;
         double vwap = (curVol > 0) ? curPV / curVol : price;

         // Store State for next bar
         Buf_H_PV[i] = curPV;
         Buf_H_Vol[i] = curVol;
         Buf_H_Ext[i] = prevExt;
         BufferVWAP2_H[i] = vwap;
      } else BufferVWAP2_H[i] = EMPTY_VALUE;

      if(ShowVWAP_Low) {
         double prevPV = (i > 0) ? Buf_L_PV[i-1] : 0;
         double prevVol = (i > 0) ? Buf_L_Vol[i-1] : 0;
         double prevExt = (i > 0) ? Buf_L_Ext[i-1] : DBL_MAX;

         // Check for Breakout on the PREVIOUS bar
         bool reset = false;
         if(i > 0) {
             double prevVWAP = (prevVol > 0) ? prevPV / prevVol : 0;
             if(prevVWAP > 0 && close[i-1] < prevVWAP) reset = true;
         }
         
         if(reset) {
             prevPV = 0; prevVol = 0; prevExt = DBL_MAX;
         }

         // Current Calculation
         if(low[i] < prevExt) prevExt = low[i];
         
         double price = GetPrice(i, VL_Source, open, high, low, close);
         double curPV = prevPV + (price * vol);
         double curVol = prevVol + vol;
         double vwap = (curVol > 0) ? curPV / curVol : price;

         // Store State
         Buf_L_PV[i] = curPV;
         Buf_L_Vol[i] = curVol;
         Buf_L_Ext[i] = prevExt;
         BufferVWAP2_L[i] = vwap;
      } else BufferVWAP2_L[i] = EMPTY_VALUE;

      // Fill Logic
      if(ShowVWAP_Fill && ShowVWAP_High && ShowVWAP_Low) {
          if(BufferVWAP2_H[i] != EMPTY_VALUE && BufferVWAP2_L[i] != EMPTY_VALUE) {
              BufferFillH[i] = BufferVWAP2_H[i];
              BufferFillL[i] = BufferVWAP2_L[i];
          } else {
              BufferFillH[i] = EMPTY_VALUE; BufferFillL[i] = EMPTY_VALUE;
          }
      } else {
          BufferFillH[i] = EMPTY_VALUE; BufferFillL[i] = EMPTY_VALUE;
      }
   }

   UpdateChartLabels(rates_total - 1, time, high, low);
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
bool IsResetTime(int i, MqlDateTime &dt, int targetHour, int targetMin, const datetime &time[]) {
   if(dt.hour == targetHour && dt.min >= targetMin) {
      if(i > 0) {
         MqlDateTime prevDt;
         TimeToStruct(time[i-1], prevDt);
         if(prevDt.hour != targetHour || prevDt.min < targetMin) return true;
      } else return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Process MA with Robust Anti-Flicker for Custom Charts            |
//+------------------------------------------------------------------+
void ProcessMA(int handle, double &buf[], bool show, int total, int prev) 
{
   if(!show) {
      ArrayInitialize(buf, EMPTY_VALUE);
      return;
   }

   // 1. Determine how many bars we need to update
   int start = (prev > 1) ? prev - 2 : 0;
   int amountNeeded = total - start;
   
   if(amountNeeded <= 0) return;

   double val[];
   // 2. Try to copy the required amount from the handle
   int copied = CopyBuffer(handle, 0, 0, amountNeeded, val);

   // 3. Apply data with Anti-Flicker Logic
   if(copied > 0) {
      // A. Fill what we definitely have
      for(int i = 0; i < copied; i++) {
         int targetIdx = (total - copied) + i;
         if(targetIdx >= 0 && targetIdx < total) {
            buf[targetIdx] = val[i];
         }
      }

      // B. GAP FIX: If we requested more than we got, project the last valid value forward
      if(copied < amountNeeded) {
         int lastValidIdx = total - copied - 1;
         double lastVal = (lastValidIdx >= 0) ? buf[lastValidIdx] : val[copied-1];
         for(int k = (total - copied); k < total; k++) {
             if(k >= 0) buf[k] = lastVal;
         }
      }
   }
   else 
   {
      // C. BLINK FIX: If CopyBuffer failed completely (lag), hold the existing line
      if(prev > 0) {
         int lastValidIdx = start - 1;
         // Find the last known valid value in our own buffer
         if(lastValidIdx >= 0 && lastValidIdx < total) {
            double lastVal = buf[lastValidIdx];
            // Project it forward to fill the void
            for(int k = start; k < total; k++) {
               buf[k] = lastVal;
            }
         }
      }
   }
}

double GetPrice(int i, ENUM_APPLIED_PRICE mode, const double& O[], const double& H[], const double& L[], const double& C[]) {
   switch(mode) {
      case PRICE_CLOSE: return C[i];
      case PRICE_OPEN: return O[i];
      case PRICE_HIGH: return H[i];
      case PRICE_LOW: return L[i];
      case PRICE_MEDIAN: return (H[i]+L[i])/2.0;
      case PRICE_TYPICAL: return (H[i]+L[i]+C[i])/3.0;
      case PRICE_WEIGHTED: return (H[i]+L[i]+C[i]+C[i])/4.0;
   }
   return C[i];
}

void ResetVWAP(SVWAPCalc &v) { v.cumPV=0; v.cumVol=0; }
void UpdateVWAPStruct(SVWAPCalc &v, double p, double vol) { v.cumPV+=p*vol; v.cumVol+=vol; }

int CreateMAHandle(int period, ENUM_MY_MA_METHOD method) {
   ENUM_MA_METHOD mqlMethod = MODE_EMA;
   switch(method) {
      case MY_MODE_EMA: mqlMethod = MODE_EMA; break;
      case MY_MODE_SMA: mqlMethod = MODE_SMA; break;
      case MY_MODE_SMMA: mqlMethod = MODE_SMMA; break;
      case MY_MODE_LWMA: mqlMethod = MODE_LWMA; break;
      case MY_MODE_VWMA: mqlMethod = MODE_LWMA; break;
   }
   return iMA(_Symbol, PERIOD_CURRENT, period, 0, mqlMethod, PRICE_CLOSE);
}

//+------------------------------------------------------------------+
//| Chart Label Logic                                                |
//+------------------------------------------------------------------+
void UpdateChartLabels(int lastIdx, const datetime &time[], const double &high[], const double &low[])
{
   double atrArgs[];
   double atrVal = 0;
   
   // ATR is an external handle, so we must still CopyBuffer
   if(CopyBuffer(hATR, 0, 0, 1, atrArgs) > 0) atrVal = atrArgs[0];

   double m1=0, m2=0, m3=0, m4=0, m5=0;
   
   // FIX: Read directly from our internal buffers
   if(ShowMA1 && lastIdx < ArraySize(BufferMA1)) m1 = (BufferMA1[lastIdx] != EMPTY_VALUE) ? BufferMA1[lastIdx] : 0;
   if(ShowMA2 && lastIdx < ArraySize(BufferMA2)) m2 = (BufferMA2[lastIdx] != EMPTY_VALUE) ? BufferMA2[lastIdx] : 0;
   if(ShowMA3 && lastIdx < ArraySize(BufferMA3)) m3 = (BufferMA3[lastIdx] != EMPTY_VALUE) ? BufferMA3[lastIdx] : 0;
   if(ShowMA4 && lastIdx < ArraySize(BufferMA4)) m4 = (BufferMA4[lastIdx] != EMPTY_VALUE) ? BufferMA4[lastIdx] : 0;
   if(ShowMA5 && lastIdx < ArraySize(BufferMA5)) m5 = (BufferMA5[lastIdx] != EMPTY_VALUE) ? BufferMA5[lastIdx] : 0;

   string trend = "CHOPPY";
   color trendColor = clrGray;

   // Only calculate trend if we have valid non-zero MA values
   if(ShowMA1 && ShowMA2 && ShowMA3 && ShowMA4 && ShowMA5 && m1!=0 && m5!=0) {
      if(m1>m2 && m2>m3 && m3>m4 && m4>m5) { trend="STRONG BULLISH"; trendColor=clrLime; }
      else if(m1<m2 && m2<m3 && m3<m4 && m4<m5) { trend="STRONG BEARISH"; trendColor=clrRed; }
   }
   
   if(ObjectFind(0, ObjNameTop) < 0) ObjectCreate(0, ObjNameTop, OBJ_TEXT, 0, 0, 0);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double offset = Label_Offset_Pts * point;
   
   // --- NEW: FORWARD SHIFT CALCULATION ---
   // Shifts the text 3 bars into the future to clear the candle
   int shift_bars = 3; 
   datetime time_fwd = time[lastIdx] + (PeriodSeconds() * shift_bars);
   // --------------------------------------
   
   ObjectSetString(0, ObjNameTop, OBJPROP_TEXT, "ATR: " + DoubleToString(atrVal, _Digits));
   ObjectSetInteger(0, ObjNameTop, OBJPROP_TIME, time_fwd); // <--- Updated Time
   ObjectSetDouble(0, ObjNameTop, OBJPROP_PRICE, high[lastIdx] + offset);
   ObjectSetInteger(0, ObjNameTop, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, ObjNameTop, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, ObjNameTop, OBJPROP_ANCHOR, ANCHOR_BOTTOM); // Anchored to bottom of text (sits on top of price)

   if(ObjectFind(0, ObjNameBot) < 0) ObjectCreate(0, ObjNameBot, OBJ_TEXT, 0, 0, 0);
   
   ObjectSetString(0, ObjNameBot, OBJPROP_TEXT, trend);
   ObjectSetInteger(0, ObjNameBot, OBJPROP_TIME, time_fwd); // <--- Updated Time
   ObjectSetDouble(0, ObjNameBot, OBJPROP_PRICE, low[lastIdx] - offset);
   ObjectSetInteger(0, ObjNameBot, OBJPROP_COLOR, trendColor);
   ObjectSetInteger(0, ObjNameBot, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, ObjNameBot, OBJPROP_ANCHOR, ANCHOR_TOP); // Anchored to top of text (hangs below price)
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(hMA1); IndicatorRelease(hMA2); IndicatorRelease(hMA3);
   IndicatorRelease(hMA4); IndicatorRelease(hMA5); IndicatorRelease(hATR);
   ObjectDelete(0, ObjNameTop);
   ObjectDelete(0, ObjNameBot);
}
//+------------------------------------------------------------------+
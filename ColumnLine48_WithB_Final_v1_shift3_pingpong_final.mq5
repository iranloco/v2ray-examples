//+------------------------------------------------------------------+
//|  ColumnLine48_WithB_Final_v1_shift3_pingpong_final.mq5          |
//|  Ported from MT4 to MT5                                         |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_plots 1
#property indicator_buffers 1
#property strict

//--- plot 0 settings (EMA line for visual reference)
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrOrange
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//================ MT4->MT5 INPUTS =================//
//--- MA settings
input int    MA_Method         = MODE_EMA;      // ENUM_MA_METHOD
input int    MA_Price          = PRICE_CLOSE;   // ENUM_APPLIED_PRICE

//--- selectable periods
int    MA_Periods[]            = {12,26,15,30,60,240};
int    g_maIndex               = 0;
int    g_MA_Period             = MA_Periods[0];

//--- Shift step (new)
input int    ShiftStep         = 50;
#define SHIFT_MIN     1
#define SHIFT_MAX   500

//--- Shift state for object "3" (ping-pong)
int    g_shift3_pos            = 0;    // current absolute shift (0 .. SHIFT3_MAX)
int    g_shift3_dir            = 1;    // direction: 1 => move RIGHT (increase pos), -1 => move LEFT (decrease pos)
#define SHIFT3_MAX   100

//--- NEW: Shift B (move B candle-by-candle to the right)
int    g_shiftB_right          = 0;  // number of right-shifts applied to B
#define SHIFTB_STEP     1
#define SHIFTB_MAX_RIGHT 100

//--- NEW: double SL toggle
bool   g_doubleSL              = false; // false = normal, true = double distance

//--- NEW: shift entry label by v toggle
bool   g_shiftEntryByV         = false; // false = no shift, true = shift lbl_BE by v_len_atB

//--- Trend‐extend bars
int    ExtendBars              = 50;
#define EXT_STEP      50
#define EXT_MIN       0
#define EXT_MAX     400
bool   g_extInc                = true;

//--- Label offset in pips (kept but no button shown)
input int    OffsetStepPips    = 50;
#define OFFSET_MIN_PIPS  0
#define OFFSET_MAX_PIPS 2000
int    g_LabelOffsetPips       = 900;
bool   g_offInc                = true;

//--- Style settings
input color  LineD_Color       = clrOrange;
input int    LineD_Width       = 2;

input color  LineE_Color       = clrYellow;
input int    LineE_Width       = 2;

input color  Gap_Color         = clrMagenta;
input int    Gap_Width         = 1;

input color  LineA_Color       = clrSilver;
input int    LineA_Width       = 1;

input color  Line0_Color       = clrSilver;
input int    Line0_Width       = 1;

input color  LineB_Color       = clrSilver;
input int    LineB_Width       = 1;

input color  Line3_Color       = clrLime;
input int    Line3_Width       = 3;

#define DASHED_COLOR   clrSilver
#define DASHED_WIDTH   1

input color  Line01_Color      = clrMagenta;
input int    Line01_Width      = 4;

input color  LineA2_Color      = clrSilver;
input int    LineA2_Width      = 2;

input color  Label_Color       = clrBlue;
input bool   ShowB             = true;

//--- NEW: toggle for v / v_ext visibility
input bool   ShowV             = true;   // true => نمایش v و v_ext ؛ false => مخفی

//--- label font size control (new)
input int    LabelFontSize     = 10;     // default font size for all labels/text
#define LABEL_MIN      6
#define LABEL_MAX      10   // max = 10 as requested

//====================  افزودنی برای چینش منو  ====================//
//--- Menu placement (editable from indicator properties)
input int MenuStartX = 10;   // فاصله از گوشه (پیکسل)
input int MenuStartY = 10;   // فاصله از بالا/پایین (پیکسل)

// --- NEW: offset to avoid overlapping symbol name/header (in pixels)
//         used for Top-L, Left vertical, and now Bot-L as well (as requested)
input int MenuHeaderOffset = 40; // تنظیم کنید به 30 یا 40 اگر لازم بود

//--- Menu layout state (چرخه محدود به سه حالت: Top-L, Bot-L, Left-v)
int g_menuLayoutState = 0; // 0=Top-L horiz, 1=Bot-L horiz, 2=Left vertical
//===============================================================//

//--- state flags & buffers
bool   g_manualA               = false;
bool   g_manual0               = false;
bool   g_manualB               = false;
bool   g_useLow                = false;
double MA_Buffer[];
bool   g_needRedraw            = false;

//--- label toggle state
int    g_labelToggleState      = 1; // default: hide H1/H2/H3

//--- label increase direction flag (when reaches max it reverses)
bool   g_lblInc                = true; // true => BtnPlus increases, false => BtnPlus decreases
bool   g_zigActive             = false; // when true, clicking chart advances A to next high/low (zigzag)

//--- preserved horizontal lengths (in seconds) for tp and sl
long   g_tp_len_seconds = 0;
long   g_sl_len_seconds = 0;

//--- manual TP/SL override flags & stored prices (new)
bool   g_manualTP = false;
bool   g_manualSL = false;
double g_tp_price = 0.0;
double g_sl_price = 0.0;

//--- scroll-protect variable (new)
int    g_lastWindowFirst = -1;

//--- series caches (to emulate MT4 Time/High/Low/Bars access)
datetime TimeSeries[];
double   HighSeries[];
double   LowSeries[];
int      gBars = 0;  // current bars count on this symbol/timeframe
#define Bars gBars   // allow MT4-style "Bars" usage in the legacy code below

//--- MA handle for MT5
int      g_maHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
bool   ObjExists(string name)            { return(ObjectFind(0,name)>=0); }
datetime GetObjTimeSafe(string name)     { return(ObjExists(name)?(datetime)ObjectGetInteger(0,name,OBJPROP_TIME1):0); }

// MQL5 replacement for WindowFirstVisibleBar / WindowBarsPerChart
int WindowFirstVisibleBar()
{
   long first=0;
   if(ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR, 0, first)) return (int)first;
   return 0;
}
int WindowBarsPerChart()
{
   long visible=0;
   if(ChartGetInteger(0, CHART_VISIBLE_BARS, 0, visible)) return (int)visible;
   return Bars;
}

void SafeDelete(string name)
  {
   if(ObjExists(name))
     {
      ObjectDelete(0,name);
      g_needRedraw = true;
     }
  }

void SetIfDifferent_Int(string name,int prop,long value)
  {
   long cur = ObjExists(name)?ObjectGetInteger(0,name,prop):0;
   if(!ObjExists(name) || cur!=value)
     {
      ObjectSetInteger(0,name,prop,value);
      g_needRedraw = true;
     }
  }

void SetIfDifferent_Double(string name,int prop,double value)
  {
   double cur = ObjExists(name)?ObjectGetDouble(0,name,prop):0.0;
   double tol = MathMax(MathAbs(value)*1e-12,1e-12);
   if(!ObjExists(name) || MathAbs(cur-value)>tol)
     {
      ObjectSetDouble(0,name,prop,value);
      g_needRedraw = true;
     }
  }

void SetIfDifferent_String(string name,int prop,string value)
  {
   string cur = ObjExists(name)?ObjectGetString(0,name,prop):"";
   if(!ObjExists(name) || cur!=value)
     {
      ObjectSetString(0,name,prop,value);
      g_needRedraw = true;
     }
  }

//+------------------------------------------------------------------+
//| Primitives creation                                              |
//+------------------------------------------------------------------+
void EnsureVLine(string name,datetime t,color clr,int w,int style,int z,int preserve_time)
  {
   if(!ObjExists(name))
     {
      ObjectCreate(0,name,OBJ_VLINE,0,t,0);
      g_needRedraw = true;
     }
   if(!preserve_time)
     SetIfDifferent_Int   (name,OBJPROP_TIME1,(long)t);
   SetIfDifferent_Int   (name,OBJPROP_COLOR,clr);
   SetIfDifferent_Int   (name,OBJPROP_WIDTH,w);
   SetIfDifferent_Int   (name,OBJPROP_STYLE,style);
   SetIfDifferent_Int   (name,OBJPROP_RAY_LEFT,false);
   SetIfDifferent_Int   (name,OBJPROP_RAY_RIGHT,false);
   SetIfDifferent_Int   (name,OBJPROP_ZORDER,z);
  }

void EnsureTrend(string name,datetime t1,double p1,datetime t2,double p2,color clr,int w,int style,int z)
  {
   if(!ObjExists(name))
     {
      ObjectCreate(0,name,OBJ_TREND,0,t1,p1,t2,p2);
      g_needRedraw = true;
     }
   SetIfDifferent_Int   (name,OBJPROP_TIME1,(long)t1);
   SetIfDifferent_Double(name,OBJPROP_PRICE1,p1);
   SetIfDifferent_Int   (name,OBJPROP_TIME2,(long)t2);
   SetIfDifferent_Double(name,OBJPROP_PRICE2,p2);
   SetIfDifferent_Int   (name,OBJPROP_COLOR,clr);
   SetIfDifferent_Int   (name,OBJPROP_WIDTH,w);
   SetIfDifferent_Int   (name,OBJPROP_STYLE,style);
   SetIfDifferent_Int   (name,OBJPROP_RAY_LEFT,false);
   SetIfDifferent_Int   (name,OBJPROP_RAY_RIGHT,false);
   SetIfDifferent_Int   (name,OBJPROP_ZORDER,z);
   // ensure trend is selectable/draggable
   SetIfDifferent_Int   (name,OBJPROP_SELECTABLE,1);
   SetIfDifferent_Int   (name,OBJPROP_HIDDEN,0);
  }

void EnsureText(string name,datetime t,double price,string txt,color clr,int fs,int anchor,int z)
  {
   if(!ObjExists(name))
     {
      ObjectCreate(0,name,OBJ_TEXT,0,t,price);
      g_needRedraw = true;
     }
   SetIfDifferent_Int   (name,OBJPROP_TIME1,(long)t);
   SetIfDifferent_Double(name,OBJPROP_PRICE1,price);
   SetIfDifferent_String(name,OBJPROP_TEXT,txt);
   SetIfDifferent_Int   (name,OBJPROP_COLOR,clr);
   SetIfDifferent_Int   (name,OBJPROP_FONTSIZE,fs);
   SetIfDifferent_Int   (name,OBJPROP_ANCHOR,anchor);
   SetIfDifferent_Int   (name,OBJPROP_ZORDER,z);
  }

// compact button creator: smaller size and flexible corner
void CreateButtonIfMissing(string name,string txt,int corner,int x,int y,int w=90,int h=18,int z=2)
  {
   if(!ObjExists(name))
     {
      ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,corner);
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
      ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
      ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
      // make sure button is selectable and on top so clicks register
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,1);
      ObjectSetInteger(0,name,OBJPROP_SELECTED,0);
      ObjectSetInteger(0,name,OBJPROP_ZORDER,1000); // high z-order
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,0);
      g_needRedraw = true;
     }
   SetIfDifferent_String(name,OBJPROP_TEXT,txt);
  }

//+------------------------------------------------------------------+
//| تابع چینش دکمه‌ها — فقط سه حالت: Top-L (h), Bot-L (h), Left (v) |
//+------------------------------------------------------------------+
void ArrangeButtons(int layout)
  {
   string btns[] = {
      "btnSwitch","btnMASelect","btnExtend","btnShowB","btnToggleV",
      "btnDoubleSL","btnShiftEntry","btnResetB","btnShiftLeft","btnShiftRight",
      "btnShiftStep","btnShiftB","btnShift3","btnZig","btnZigNext",
      "btnToggleLabels","btnLblMinus","btnLblSize","btnLblPlus","btnArrange"
   };

   int gapX = 95;
   int gapY = 22;
   int maxPerRow = 10;

   for(int i=0; i<ArraySize(btns); i++)
     {
      int corner = 0;
      int x = MenuStartX;
      int y = MenuStartY;

      if(layout==0) // top-left horizontal
        {
         corner = 0;
         x = MenuStartX + (i % maxPerRow) * gapX;
         y = MenuStartY + (i / maxPerRow) * gapY;
         // add header offset so menu doesn't overlap symbol name
         y += MenuHeaderOffset + 10;

        }
      else if(layout==1) // bottom-left horizontal
        {
         corner = 2;
         x = MenuStartX + (i % maxPerRow) * gapX;
         y = MenuStartY + (i / maxPerRow) * gapY;
         // shift bottom menus up by the same amount as top-left
         y += MenuHeaderOffset + 10;

        }
      else if(layout==2) // left vertical (top-left corner)
        {
         corner = 0;
         x = MenuStartX;
         y = MenuStartY + i * gapY;
         // vertical left should also avoid header
         y += MenuHeaderOffset + 10;

        }

      if(ObjExists(btns[i]))
        {
         // update corner and distances
         SetIfDifferent_Int(btns[i], OBJPROP_CORNER, corner);
         SetIfDifferent_Int(btns[i], OBJPROP_XDISTANCE, x);
         SetIfDifferent_Int(btns[i], OBJPROP_YDISTANCE, y);
        }
      else
        {
         // create with default text placeholder; actual text will be set elsewhere
         CreateButtonIfMissing(btns[i], btns[i], corner, x, y, 90, 18);
        }
     }

   string labs[] = {"Top-L (h)","Bot-L (h)","Left (v)"};
   if(ObjExists("btnArrange"))
     SetIfDifferent_String("btnArrange", OBJPROP_TEXT, "Arrange: "+labs[layout]);
   g_needRedraw = true;
  }

//+------------------------------------------------------------------+
//| Helper: Shift a single object by given number of bars            |
//+------------------------------------------------------------------+
void ShiftObjectByBars(string name,int barsShift)
  {
   if(!ObjExists(name)) return;
   datetime t = GetObjTimeSafe(name);
   if(t==0) return;
   int idx = iBarShift(_Symbol,_Period,t,false);
   if(idx<0)
     {
      int best = 0;
      long bestDiff = (long)MathAbs((long)(TimeSeries[0] - t));
      for(int i=1; i<Bars; i++)
        {
         long d = (long)MathAbs((long)(TimeSeries[i] - t));
         if(d < bestDiff) { best = i; bestDiff = d; }
        }
      idx = best;
     }
   int newIdx = idx + barsShift; // positive => older (left), negative => newer (right)
   if(newIdx < 0) newIdx = 0;
   if(newIdx > Bars-1) newIdx = Bars-1;
   datetime newTime = TimeSeries[newIdx];
   SetIfDifferent_Int(name, OBJPROP_TIME1, (long)newTime);

   // Mark manual so object isn't auto-removed
   if(name=="A") g_manualA = true;
   else if(name=="0") g_manual0 = true;
   else if(name=="B") g_manualB = true;
  }

//+------------------------------------------------------------------+
//| Helper: Shift A,0,B all together and redraw                      |
//+------------------------------------------------------------------+
void ShiftAllByBars(int barsShift)
  {
   ShiftObjectByBars("A", barsShift);
   ShiftObjectByBars("0", barsShift);
   if(ObjExists("B")) ShiftObjectByBars("B", barsShift);
   UpdateAll();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Helper: move A to next local high/low (zigzag-like)              |
//+------------------------------------------------------------------+
void MoveAtoNextExtreme(bool searchHigh)
  {
   if(!ObjExists("A")) return;
   datetime tA = GetObjTimeSafe("A");
   int sA = iBarShift(_Symbol,_Period,tA,false);
   if(sA<0)
     {
      int bestA = 0;
      long bestDiffA = (long)MathAbs((long)(TimeSeries[0] - tA));
      for(int i=1; i<Bars; i++)
        {
         long d = (long)MathAbs((long)(TimeSeries[i] - tA));
         if(d < bestDiffA) { bestA = i; bestDiffA = d; }
        }
      sA = bestA;
     }

   int found = -1;
   // search left (older bars) for the next local extreme
   if(searchHigh)
     {
      for(int i=sA-1; i>=1; i--)
        {
         // local peak: higher than neighbor(s)
         if(HighSeries[i] >= HighSeries[i-1] && HighSeries[i] > HighSeries[i+1]) { found = i; break; }
        }
     }
   else
     {
      for(int i=sA-1; i>=1; i--)
        {
         if(LowSeries[i] <= LowSeries[i-1] && LowSeries[i] < LowSeries[i+1]) { found = i; break; }
        }
     }

   if(found >= 0)
     {
      datetime tNew = TimeSeries[found];
      SetIfDifferent_Int("A", OBJPROP_TIME1, (long)tNew);
      g_manualA = true;
      g_needRedraw = true;
      UpdateAll();
      ChartRedraw();
     }
  }

//+------------------------------------------------------------------+
//| MA helpers                                                       |
//+------------------------------------------------------------------+
void ResetMAHandle()
{
   if(g_maHandle!=INVALID_HANDLE) { IndicatorRelease(g_maHandle); g_maHandle = INVALID_HANDLE; }
   g_maHandle = iMA(_Symbol, _Period, g_MA_Period, 0, (ENUM_MA_METHOD)MA_Method, (ENUM_APPLIED_PRICE)MA_Price);
   string lbl = "EMA("+IntegerToString(g_MA_Period)+")";
   PlotIndexSetString(0, PLOT_LABEL, lbl);
   IndicatorSetString(INDICATOR_SHORTNAME, lbl);
}

double GetMAAtShift(int shift)
{
   if(g_maHandle==INVALID_HANDLE) return 0.0;
   double tmp[1];
   int copied = CopyBuffer(g_maHandle, 0, shift, 1, tmp);
   if(copied<=0) return 0.0;
   return tmp[0];
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   // indicator buffer
   SetIndexBuffer(0, MA_Buffer, INDICATOR_DATA);
   ArraySetAsSeries(MA_Buffer, true); // use MT4-like indexing for convenience

   // initial MA handle
   ResetMAHandle();

   // Objects: A, 0, B
   if(ObjExists("A")) g_manualA = true;
   datetime oldA = GetObjTimeSafe("A");
   EnsureVLine("A", oldA>0?oldA:TimeCurrent(), LineA_Color, LineA_Width, STYLE_DASH, 0, g_manualA?1:0);

   if(ObjExists("0")) g_manual0 = true;
   datetime old0 = GetObjTimeSafe("0");
   // defer t_for_0 until we have series in first OnCalculate

   if(ObjExists("B")) g_manualB = true;
   datetime oldB = GetObjTimeSafe("B");
   EnsureVLine("B", oldB>0?oldB:TimeCurrent(), LineB_Color, LineB_Width, STYLE_DASH, 3, g_manualB?1:0);

   // Buttons (compact)
   int startX = MenuStartX;
   int startY = MenuStartY;
   int gapX = 95;
   int gapY = 22;
   int maxPerRow = 10;
   int count = 0;

   string btns[] = {
      "btnSwitch",
      "btnMASelect",
      "btnExtend",
      "btnShowB",
      "btnToggleV",
      "btnDoubleSL",
      "btnShiftEntry",
      "btnResetB",
      "btnShiftLeft",
      "btnShiftRight",
      "btnShiftStep",
      "btnShiftB",
      "btnShift3",
      "btnZig",
      "btnZigNext",
      "btnToggleLabels",
      "btnLblMinus",
      "btnLblSize",
      "btnLblPlus",
      "btnArrange"
   };

   for(int i=0;i<ArraySize(btns);i++){
      int x = startX + (count % maxPerRow) * gapX;
      int y = startY + (count / maxPerRow) * gapY;
      if(g_menuLayoutState==0) y += MenuHeaderOffset + 10; // top-left
      else if(g_menuLayoutState==1) y += MenuHeaderOffset + 10; // bottom-left (same offset)
      else if(g_menuLayoutState==2) y += MenuHeaderOffset + 10; // left vertical

      string txt;
      if(ObjExists(btns[i])) txt = ObjectGetString(0, btns[i], OBJPROP_TEXT);
      else
        {
         if(btns[i]=="btnSwitch") txt = g_useLow?"Use High":"Use Low";
         else if(btns[i]=="btnMASelect") txt = "EMA:"+IntegerToString(g_MA_Period);
         else if(btns[i]=="btnExtend") txt = "Ext:"+IntegerToString(ExtendBars);
         else if(btns[i]=="btnShowB") txt = ShowB?"Hide B":"Show B";
         else if(btns[i]=="btnToggleV") txt = ShowV?"Hide v":"Show v";
         else if(btns[i]=="btnDoubleSL") txt = g_doubleSL?"Double SL: On":"Double SL: Off";
         else if(btns[i]=="btnShiftEntry") txt = g_shiftEntryByV?"ShiftEntry: On":"ShiftEntry: Off";
         else if(btns[i]=="btnResetB") txt = "Reset B";
         else if(btns[i]=="btnShiftLeft") txt = "Shift << ("+IntegerToString(ShiftStep)+")";
         else if(btns[i]=="btnShiftRight") txt = "Shift >> ("+IntegerToString(ShiftStep)+")";
         else if(btns[i]=="btnShiftStep") txt = "ShiftStep:"+IntegerToString(ShiftStep);
         else if(btns[i]=="btnShiftB") txt = "ShiftB >> (0/100)";
         else if(btns[i]=="btnShift3") txt = "Shift3 >> (0/"+IntegerToString(SHIFT3_MAX)+")";
         else if(btns[i]=="btnZig") txt = g_zigActive?"Zig:On":"Zig:Off";
         else if(btns[i]=="btnZigNext") txt = "ZigNext";
         else if(btns[i]=="btnToggleLabels") txt = g_labelToggleState==1?"Hide H1/H2/H3":"Labels: All";
         else if(btns[i]=="btnLblMinus") txt = "Lbl-";
         else if(btns[i]=="btnLblSize") txt = "LblSize:"+IntegerToString(LabelFontSize);
         else if(btns[i]=="btnLblPlus") txt = "Lbl+";
         else if(btns[i]=="btnArrange") txt = "Arrange";
         else txt = btns[i];
        }
      CreateButtonIfMissing(btns[i], txt, 0, x, y, 90, 18);
      count++;
   }

   // Arrange according to current layout (places buttons properly)
   ArrangeButtons(g_menuLayoutState);

   EventSetTimer(2);
   g_lastWindowFirst = WindowFirstVisibleBar();  // init scroll-protect
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| OnCalculate                                                      |
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
   // cache series (MT4-like indexing: 0 = current bar)
   gBars = rates_total;
   ArrayResize(TimeSeries, rates_total);
   ArrayResize(HighSeries, rates_total);
   ArrayResize(LowSeries,  rates_total);
   // Copy from provided arrays
   for(int i=0;i<rates_total;i++){
      TimeSeries[i] = time[i];
      HighSeries[i] = high[i];
      LowSeries[i]  = low[i];
   }
   ArraySetAsSeries(TimeSeries, true);
   ArraySetAsSeries(HighSeries, true);
   ArraySetAsSeries(LowSeries,  true);

   // initialize object "0" default position once we have bars
   if(!ObjExists("0"))
     {
      datetime tA = GetObjTimeSafe("A");
      int idxA = (tA>0)? iBarShift(_Symbol,_Period,tA,false):0;
      if(idxA<0) idxA = 0;
      int idx0 = MathMin(Bars-1, idxA + 48);
      EnsureVLine("0", TimeSeries[idx0], Line0_Color, Line0_Width, STYLE_DASH, 1, g_manual0?1:0);
     }

   // MA buffer from handle
   if(g_maHandle==INVALID_HANDLE) ResetMAHandle();
   if(g_maHandle!=INVALID_HANDLE)
     {
      CopyBuffer(g_maHandle, 0, 0, rates_total, MA_Buffer);
      ArraySetAsSeries(MA_Buffer, true); // make MA_Buffer[0] the newest
     }

   UpdateAll();
   return(rates_total);
  }

//+------------------------------------------------------------------+
//| OnChartEvent                                                     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {
   if(id==CHARTEVENT_OBJECT_DRAG)
     {
      if(sparam=="A")  g_manualA = true;
      if(sparam=="0")  g_manual0 = true;
      if(sparam=="B")
        {
         g_manualB = true;
         // reset B-right-shift counter if user manually drags B
         g_shiftB_right = 0;
         SetIfDifferent_String("btnShiftB", OBJPROP_TEXT, "ShiftB >> (0/100)");
        }
      // if user manually drags object "3" we reset its shift state
      if(sparam=="3")
        {
         g_shift3_pos = 0;
         g_shift3_dir = 1;
         SetIfDifferent_String("btnShift3", OBJPROP_TEXT, "Shift3 >> (0/"+IntegerToString(SHIFT3_MAX)+")");
         SafeDelete("dbg_shift3");
        }

      // --- NEW: handle TP/SL manual dragging ---
      if(sparam=="tp" || sparam=="sl")
        {
         // determine one_candle_seconds and max_seconds (same policy as UpdateAll)
         int one_candle_seconds = (Bars>1)?(int)(TimeSeries[0]-TimeSeries[1]):(int)PeriodSeconds(_Period);
         long max_seconds = (long)one_candle_seconds * 24;

         // read times and price from the trend object
         if(ObjExists(sparam))
           {
            long t1 = ObjectGetInteger(0, sparam, OBJPROP_TIME1);
            long t2 = ObjectGetInteger(0, sparam, OBJPROP_TIME2);
            double p1 = ObjectGetDouble(0, sparam, OBJPROP_PRICE1);
            // ensure valid
            if(t2 <= t1) t2 = t1 + one_candle_seconds;

            long len = t2 - t1;
            if(len <= 0) len = one_candle_seconds;
            len = MathMin(len, max_seconds);

            if(sparam=="tp")
              {
               g_manualTP = true;
               g_tp_len_seconds = len;
               g_tp_price = p1;
              }
            else // sl
              {
               g_manualSL = true;
               g_sl_len_seconds = len;
               g_sl_price = p1;
              }

            // update labels immediately
            UpdateAll();
            ChartRedraw();
           }
        }

      UpdateAll();
     }
   else if(id==CHARTEVENT_OBJECT_CLICK)
     {
      if(sparam=="btnSwitch")
        {
         g_useLow = !g_useLow;
         SetIfDifferent_String("btnSwitch",OBJPROP_TEXT,
                               g_useLow?"Use High":"Use Low");
        }
      else if(sparam=="btnMASelect")
        {
         g_maIndex = (g_maIndex+1) % ArraySize(MA_Periods);
         g_MA_Period = MA_Periods[g_maIndex];
         SetIfDifferent_String("btnMASelect",OBJPROP_TEXT,
                               "EMA("+IntegerToString(g_MA_Period)+")");
         ResetMAHandle();
        }
      else if(sparam=="btnExtend")
        {
         if(g_extInc)
           { ExtendBars += EXT_STEP; if(ExtendBars>=EXT_MAX){ ExtendBars=EXT_MAX; g_extInc=false; } }
         else
           { ExtendBars -= EXT_STEP; if(ExtendBars<=EXT_MIN){ ExtendBars=EXT_MIN; g_extInc=true; } }
         SetIfDifferent_String("btnExtend",OBJPROP_TEXT,"Ext:"+IntegerToString(ExtendBars));
        }
      else if(sparam=="btnShowB")
        {
         ShowB = !ShowB;
         SetIfDifferent_String("btnShowB",OBJPROP_TEXT,ShowB?"Hide B":"Show B");
        }
      else if(sparam=="btnToggleV")
        {
         // new handler: toggle visibility of v and v_ext
         ShowV = !ShowV;
         SetIfDifferent_String("btnToggleV", OBJPROP_TEXT, ShowV? "Hide v":"Show v");
         if(!ShowV)
           {
            SafeDelete("v");
            SafeDelete("v_ext");
           }
         UpdateAll();
         ChartRedraw();
        }
      else if(sparam=="btnToggleLabels")
        {
         g_labelToggleState = (g_labelToggleState + 1) % 3;
         if(g_labelToggleState==0)
           SetIfDifferent_String("btnToggleLabels",OBJPROP_TEXT,"Labels: All");
         else if(g_labelToggleState==1)
           SetIfDifferent_String("btnToggleLabels",OBJPROP_TEXT,"Hide H1/H2/H3");
         else if(g_labelToggleState==2)
           SetIfDifferent_String("btnToggleLabels",OBJPROP_TEXT,"Hide A/0/B");
        }
      else if(sparam=="btnResetB")
        {
         g_manualB = false;
         SafeDelete("B");
         // reset preserved lengths as B was reset by user
         g_tp_len_seconds = 0;
         g_sl_len_seconds = 0;
         // reset ShiftB counter
         g_shiftB_right = 0;
         SetIfDifferent_String("btnShiftB", OBJPROP_TEXT, "ShiftB >> (0/100)");

         // reset manual TP/SL overrides when B is reset
         g_manualTP = false;
         g_manualSL = false;
         g_tp_price = 0.0;
         g_sl_price = 0.0;
        }
      else if(sparam=="btnLblPlus")
        {
         if(g_lblInc) LabelFontSize++;
         else LabelFontSize--;

         if(LabelFontSize > LABEL_MAX) LabelFontSize = LABEL_MAX;
         if(LabelFontSize < LABEL_MIN) LabelFontSize = LABEL_MIN;
         if(LabelFontSize >= LABEL_MAX) g_lblInc = false;
         if(LabelFontSize <= LABEL_MIN) g_lblInc = true;

         SetIfDifferent_String("btnLblSize",OBJPROP_TEXT,"LblSize:"+IntegerToString(LabelFontSize));
        }
      else if(sparam=="btnLblMinus")
        {
         LabelFontSize--;
         if(LabelFontSize < LABEL_MIN) LabelFontSize = LABEL_MIN;
         if(LabelFontSize <= LABEL_MIN) g_lblInc = true;
         SetIfDifferent_String("btnLblSize",OBJPROP_TEXT,"LblSize:"+IntegerToString(LabelFontSize));
        }

      // --- Shift left/right buttons ---
      else if(sparam=="btnShiftLeft")
        {
         int step = MathMax(SHIFT_MIN, MathMin(SHIFT_MAX, ShiftStep));
         ShiftAllByBars(step);
         SetIfDifferent_String("btnShiftLeft", OBJPROP_TEXT, "Shift << ("+IntegerToString(step)+")");
         SetIfDifferent_String("btnShiftRight", OBJPROP_TEXT, "Shift >> ("+IntegerToString(step)+")");
        }
      else if(sparam=="btnShiftRight")
        {
         int step = MathMax(SHIFT_MIN, MathMin(SHIFT_MAX, ShiftStep));
         ShiftAllByBars(-step);
         SetIfDifferent_String("btnShiftLeft", OBJPROP_TEXT, "Shift << ("+IntegerToString(step)+")");
         SetIfDifferent_String("btnShiftRight", OBJPROP_TEXT, "Shift >> ("+IntegerToString(step)+")");
        }
      else if(sparam=="btnShiftStep")
        {
         int vals[] = {10,25,50,100,200};
         int pos = -1;
         for(int i=0;i<ArraySize(vals);i++) if(ShiftStep==vals[i]) { pos=i; break; }
         if(pos==-1) ShiftStep = 50;
         else ShiftStep = vals[(pos+1) % ArraySize(vals)];
         SetIfDifferent_String("btnShiftStep", OBJPROP_TEXT, "ShiftStep:"+IntegerToString(ShiftStep));
         SetIfDifferent_String("btnShiftLeft", OBJPROP_TEXT, "Shift << ("+IntegerToString(ShiftStep)+")");
         SetIfDifferent_String("btnShiftRight", OBJPROP_TEXT, "Shift >> ("+IntegerToString(ShiftStep)+")");
        }

      // Zigzag controls
      else if(sparam=="btnZig")
        {
         g_zigActive = !g_zigActive;
         SetIfDifferent_String("btnZig", OBJPROP_TEXT, g_zigActive?"Zig:On":"Zig:Off");
        }
      else if(sparam=="btnZigNext")
        {
         MoveAtoNextExtreme(!g_useLow);
        }

      // --- btnDoubleSL handler ---
      else if(sparam=="btnDoubleSL")
        {
         g_doubleSL = !g_doubleSL;
         SetIfDifferent_String("btnDoubleSL", OBJPROP_TEXT, g_doubleSL? "Double SL: On":"Double SL: Off");
         UpdateAll();
         ChartRedraw();
        }

      // --- btnShiftEntry handler ---
      else if(sparam=="btnShiftEntry")
        {
         g_shiftEntryByV = !g_shiftEntryByV;
         SetIfDifferent_String("btnShiftEntry", OBJPROP_TEXT, g_shiftEntryByV? "ShiftEntry: On":"ShiftEntry: Off");
         UpdateAll();
         ChartRedraw();
        }

      // --- btnShiftB handler (move B one candle to the RIGHT per click) ---
      else if(sparam=="btnShiftB")
        {
         if(!ObjExists("B"))
           {
            g_shiftB_right = 0;
            SetIfDifferent_String("btnShiftB", OBJPROP_TEXT, "ShiftB >> (0/100)");
           }
         else
           {
            if(g_shiftB_right >= SHIFTB_MAX_RIGHT)
              {
               SetIfDifferent_String("btnShiftB", OBJPROP_TEXT, "ShiftB >> ("+IntegerToString(SHIFTB_MAX_RIGHT)+"/100)");
              }
            else
              {
               ShiftObjectByBars("B", -SHIFTB_STEP);
               g_shiftB_right += SHIFTB_STEP;
               if(g_shiftB_right > SHIFTB_MAX_RIGHT) g_shiftB_right = SHIFTB_MAX_RIGHT;
               SetIfDifferent_String("btnShiftB", OBJPROP_TEXT, "ShiftB >> ("+IntegerToString(g_shiftB_right)+"/100)");
               UpdateAll();
               ChartRedraw();
              }
           }
        }

      // --- NEW: btnShift3 handler (ping-pong AND apply IMMEDIATELY to object "3" ONLY) ---
      else if(sparam=="btnShift3")
        {
         if(!ObjExists("3"))
           {
            EnsureText("dbg_shift3", TimeSeries[0], HighSeries[0], "Object '3' not found", clrRed, LabelFontSize, ANCHOR_RIGHT, 10);
            SetIfDifferent_String("btnShift3", OBJPROP_TEXT, "Shift3 (no 3)");
           }
         else
           {
            int step = MathMax(1, MathMin(SHIFT3_MAX, ShiftStep)); // use ShiftStep but clamp
            // update position by direction
            g_shift3_pos += g_shift3_dir * step;
            // clamp and flip direction at bounds
            if(g_shift3_pos >= SHIFT3_MAX)
              {
               g_shift3_pos = SHIFT3_MAX;
               g_shift3_dir = -1; // reverse
              }
            else if(g_shift3_pos <= 0)
              {
               g_shift3_pos = 0;
               g_shift3_dir = 1; // reverse
              }

            // update button label
            string dirSym = g_shift3_dir==1 ? ">>" : "<<";
            SetIfDifferent_String("btnShift3", OBJPROP_TEXT, "Shift3 "+dirSym+" ("+IntegerToString(g_shift3_pos)+"/"+IntegerToString(SHIFT3_MAX)+")");

            // compute new time positions for object "3" based on current A and 0
            datetime tA = GetObjTimeSafe("A");
            datetime t0 = GetObjTimeSafe("0");
            int sA = iBarShift(_Symbol,_Period,tA,false);
            int s0 = iBarShift(_Symbol,_Period,t0,false);
            if(sA<0 || s0<0)
              {
               // fallback search
               if(sA<0)
                 {
                  int bestA = 0; long bestDiffA = (long)MathAbs((long)(TimeSeries[0] - tA));
                  for(int i=1;i<Bars;i++){ long d=(long)MathAbs((long)(TimeSeries[i]-tA)); if(d<bestDiffA){bestA=i;bestDiffA=d;} }
                  sA = bestA;
                 }
               if(s0<0)
                 {
                  int best0 = 0; long bestDiff0 = (long)MathAbs((long)(TimeSeries[0] - t0));
                  for(int i=1;i<Bars;i++){ long d=(long)MathAbs((long)(TimeSeries[i]-t0)); if(d<bestDiff0){best0=i;bestDiff0=d;} }
                  s0 = best0;
                 }
              }
            // ensure ordering
            if(sA > s0)
              {
               int tmpi = sA; sA = s0; s0 = tmpi;
               datetime tmpt = tA; tA = t0; t0 = tmpt;
              }

            // apply shift only to object "3" immediately
            int computed_forward = -g_shift3_pos; // positive forward = left; negative => right
            int newLeftIndex  = sA - computed_forward;
            int newRightIndex = s0 - computed_forward;
            if(newLeftIndex < 0) newLeftIndex = 0;
            if(newLeftIndex > Bars-1) newLeftIndex = Bars-1;
            if(newRightIndex < 0) newRightIndex = 0;
            if(newRightIndex > Bars-1) newRightIndex = Bars-1;

            SetIfDifferent_Int("3", OBJPROP_TIME1, (long)TimeSeries[newLeftIndex]);
            SetIfDifferent_Int("3", OBJPROP_TIME2, (long)TimeSeries[newRightIndex]);

            // update debug text
            string dbgTxt = "Shift3_pos="+IntegerToString(g_shift3_pos)+" dir="+IntegerToString(g_shift3_dir);
            EnsureText("dbg_shift3", TimeSeries[0], HighSeries[0], dbgTxt, Label_Color, LabelFontSize, ANCHOR_RIGHT, 10);

            UpdateAll();
            ChartRedraw();
           }
        }

      // --- NEW: btnArrange handler (چرخهٔ سه‌حالت) ---
      else if(sparam=="btnArrange")
        {
         g_menuLayoutState = (g_menuLayoutState + 1) % 3; // cycle 0..2
         ArrangeButtons(g_menuLayoutState);
         UpdateAll();
         ChartRedraw();
        }

      UpdateAll();
     }
   else if(id==CHARTEVENT_CLICK)
     {
      // user clicked on chart area (not an object). If zig mode active, advance A to next extreme.
      if(g_zigActive)
        {
         MoveAtoNextExtreme(!g_useLow);
        }
     }
  }

//+------------------------------------------------------------------+
//| OnTimer                                                          |
//+------------------------------------------------------------------+
void OnTimer()
  {
   UpdateAll();
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   // لیست کامل آبجکت‌هایی که این اندیکاتور ممکن است بسازد
   string objs[] = {
     "A","0","A0","B","d","e","1","2","3",
     "ab","lblBA","lblOC",
     "btnSwitch","btnMASelect","btnExtend","btnShowB",
     "H1","H2","H3","4","01","A2","lbl01","lblA2","CmpLabel",
     "lbl_A","lbl_0","lbl_B","btnToggleLabels","btnResetB",
     "btnLblMinus","btnLblPlus","btnLblSize",
     "v","v_ext","tp","sl","lbl_tp","lbl_sl","entry",
     // shift / zig buttons
     "btnShiftLeft","btnShiftRight","btnShiftStep",
     "btnZig","btnZigNext",
     // buy/sell label
     "lbl_BE",
     // NEW buttons
     "btnDoubleSL","btnShiftEntry",
     // NEW ShiftB button
     "btnShiftB",
     // NEW Shift3 button
     "btnShift3",
     // btnToggleV
     "btnToggleV",
     // debug text
     "dbg_shift3",
     // arrange button
     "btnArrange",
     // diffs label
     "lbl_diffs"
   };

   // حذف با تابع امن
   for(int i=0; i<ArraySize(objs); i++)
     {
      SafeDelete(objs[i]);
     }

   // پاک‌سازی تایمر
   EventKillTimer();

   // آزادسازی هندل MA
   if(g_maHandle!=INVALID_HANDLE) { IndicatorRelease(g_maHandle); g_maHandle = INVALID_HANDLE; }

   // اطمینان از رفرش چارت تا هیچ شبح / سایه‌ای باقی نماند
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| UpdateAll: main drawing/update routine                           |
//+------------------------------------------------------------------+
void UpdateAll()
  {
   // Protect updates while the user is actively scrolling the chart.
   int curVF = WindowFirstVisibleBar();
   if(curVF != g_lastWindowFirst)
     {
      // record the new visible-first index and skip heavy redraws while scrolling
      g_lastWindowFirst = curVF;
      return; // skip update while scrolling
     }

   g_needRedraw = false;
   if(!ObjExists("A") || !ObjExists("0")) return;

   // If object "3" was removed externally, reset our counter
   if(!ObjExists("3") && g_shift3_pos != 0)
     {
      g_shift3_pos = 0;
      g_shift3_dir = 1;
     }

   // pip size (MQL5 replacement)
   double pip = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(digits%2==1) pip *= 10.0;

   // --- get times and bar indices for A and 0, with fallback if iBarShift fails
   datetime tA = GetObjTimeSafe("A");
   int      sA = iBarShift(_Symbol,_Period,tA,false);
   if(sA<0)
     {
      int bestA = 0;
      long bestDiffA = (long)MathAbs((long)(TimeSeries[0] - tA));
      for(int i=1; i<Bars; i++)
        {
         long d = (long)MathAbs((long)(TimeSeries[i] - tA));
         if(d < bestDiffA) { bestA = i; bestDiffA = d; }
        }
      sA = bestA;
     }

   datetime t0 = GetObjTimeSafe("0");
   int      s0 = iBarShift(_Symbol,_Period,t0,false);
   if(s0<0)
     {
      int best0 = 0;
      long bestDiff0 = (long)MathAbs((long)(TimeSeries[0] - t0));
      for(int i=1; i<Bars; i++)
        {
         long d = (long)MathAbs((long)(TimeSeries[i] - t0));
         if(d < bestDiff0) { best0 = i; bestDiff0 = d; }
        }
      s0 = best0;
     }

   // ensure ordering: sA should be earlier (left) and s0 later (right)
   if(sA > s0)
     {
      int tmpi = sA; sA = s0; s0 = tmpi;
      datetime tmpt = tA; tA = t0; t0 = tmpt;
     }

   if(sA<0 || s0<0) return;

   int span = s0 - sA; if(span==0) span=1;

   // highest between A and 0
   int ih = iHighest(_Symbol,_Period,MODE_HIGH, span+1, sA);
   double ph = HighSeries[ih];

   // A0 dashed
   EnsureTrend("A0", tA, ph, t0, ph, DASHED_COLOR, DASHED_WIDTH, STYLE_DASH, 0);

   // bars between A and 0
   int distA0  = MathAbs(s0 - sA);
   datetime tMid = (tA + t0)/2;
   EnsureText("lblOC", tMid, ph, IntegerToString(distA0)+" bars", Label_Color,LabelFontSize,ANCHOR_LEFT,2);

   // length in pips for "01"
   double v0   = g_useLow?LowSeries[s0]:HighSeries[s0];
   double len01 = MathAbs(ph - v0) / pip;
   double mid01 = (ph + v0)/2;
   EnsureTrend("01", t0, ph, t0, v0, LineA2_Color, LineA2_Width, STYLE_SOLID, 1);
   EnsureText("lbl01", t0, mid01, IntegerToString((int)MathRound(len01))+" pips",
              Label_Color,LabelFontSize,ANCHOR_LEFT,2);

   // EMA trend (from MA handle)
   double maA = GetMAAtShift(sA);
   double ma0 = GetMAAtShift(s0);
   DrawExtendedTrend("d", sA, maA, s0, ma0, LineD_Color, LineD_Width, 1);

   // High/Low trend
   double vA  = g_useLow?LowSeries[sA]:HighSeries[sA];
   DrawExtendedTrend("e", sA, vA, s0, v0, LineE_Color, LineE_Width, 1);

   // connectors gap
   EnsureTrend("1", t0, ma0, t0, v0, Gap_Color, Gap_Width, STYLE_SOLID, 1);
   EnsureTrend("2", tA, maA, tA, vA, Gap_Color, Gap_Width, STYLE_SOLID, 1);

   // mid trend
   double midA = (maA+vA)/2, mid0 = (ma0+v0)/2;
   DrawExtendedTrend("3", sA, midA, s0, mid0, Line3_Color, Line3_Width, 2);

   // --- APPLY SHIFT FOR "3" (if any) --- 
   if(g_shift3_pos != 0 && ObjExists("3"))
     {
      int computed_forward = -g_shift3_pos; // positive forward = left; negative => right
      int newLeftIndex  = sA - computed_forward;
      int newRightIndex = s0 - computed_forward;
      if(newLeftIndex < 0) newLeftIndex = 0;
      if(newLeftIndex > Bars-1) newLeftIndex = Bars-1;
      if(newRightIndex < 0) newRightIndex = 0;
      if(newRightIndex > Bars-1) newRightIndex = Bars-1;
      SetIfDifferent_Int("3", OBJPROP_TIME1, (long)TimeSeries[newLeftIndex]);
      SetIfDifferent_Int("3", OBJPROP_TIME2, (long)TimeSeries[newRightIndex]);
     }

   // intersection & A2 & comparison label
   if(s0!=sA)
     {
      double slope = (v0 - vA)/double(s0 - sA);
      int found = -1;
      for(int i=sA-1; i>=0; i--)
        {
         double p = vA + slope*(i - sA);
         if(HighSeries[i]>=p && LowSeries[i]<=p) { found = i; break; }
        }

      // Determine whether we should treat B as present:
      if( (found>=0 && ShowB) || (g_manualB && ObjExists("B") && ShowB) )
        {
         datetime tB;
         int     idxB = -1;
         double  pB;

         if(g_manualB && ObjExists("B"))
           {
            tB = GetObjTimeSafe("B");
            idxB = iBarShift(_Symbol,_Period,tB,false);
            if(idxB<0)
              {
               int bestB = 0;
               long bestDiffB = (long)MathAbs((long)(TimeSeries[0] - tB));
               for(int i=1; i<Bars; i++)
                 {
                  long d = (long)MathAbs((long)(TimeSeries[i] - tB));
                  if(d < bestDiffB) { bestB = i; bestDiffB = d; }
                 }
               idxB = bestB;
              }
            pB = vA + slope*(idxB - sA);
           }
         else
           {
            tB = TimeSeries[found];
            idxB = found;
            pB = vA + slope*(found - sA);
           }

         // EnsureB
         EnsureVLine("B", tB, LineB_Color, LineB_Width, STYLE_DASH, 3, g_manualB?1:0);
         EnsureTrend("ab", tB, pB, tA, pB, DASHED_COLOR, DASHED_WIDTH, STYLE_DASH, 2);

         double slopeD = (ma0 - maA)/double(s0 - sA);
         double pDB    = maA + slopeD*(idxB - sA);
         EnsureTrend("4", tB, pDB, tB, pB, Gap_Color, Gap_Width, STYLE_SOLID, 1);

         EnsureTrend("A2", tA, pB, tA, vA, LineA2_Color, LineA2_Width, STYLE_SOLID, 1);
         double lenA2 = MathAbs(pB - vA) / pip;
         double midA2 = (pB + vA)/2;
         EnsureText("lblA2", tA, midA2, IntegerToString((int)MathRound(lenA2))+" pips",
                    Label_Color,LabelFontSize,ANCHOR_LEFT,2);

         int distBA      = MathAbs(idxB - sA);
         datetime tMidBA = (tB + tA)/2;
         EnsureText("lblBA", tMidBA, pB, IntegerToString(distBA)+" bars", Label_Color,LabelFontSize,ANCHOR_LEFT,2);

         // comparison label
         string cmpTxt;
         color  cmpClr;
         if(lenA2 < len01)
           { cmpTxt="PIP A2 < PIP A0"; cmpClr=clrGreen; }
         else
           { cmpTxt="PIP A2 >= PIP A0"; cmpClr=clrRed; }
         if(!ObjExists("CmpLabel"))
           {
            ObjectCreate(0,"CmpLabel",OBJ_LABEL,0,0,0);
            g_needRedraw = true;
           }
         SetIfDifferent_String("CmpLabel",OBJPROP_TEXT,cmpTxt);
         SetIfDifferent_Int   ("CmpLabel",OBJPROP_CORNER,2);
         SetIfDifferent_Int   ("CmpLabel",OBJPROP_XDISTANCE,10);
         SetIfDifferent_Int   ("CmpLabel",OBJPROP_YDISTANCE,20);
         SetIfDifferent_Int   ("CmpLabel",OBJPROP_COLOR,cmpClr);
         SetIfDifferent_Int   ("CmpLabel",OBJPROP_FONTSIZE,LabelFontSize);
         SetIfDifferent_Int   ("CmpLabel",OBJPROP_BACK,1);
        }
      else
        {
         if(!g_manualB)
           {
            SafeDelete("B"); SafeDelete("ab"); SafeDelete("lblBA");
            SafeDelete("4"); SafeDelete("A2"); SafeDelete("lblA2");
            SafeDelete("CmpLabel");
           }
        }
     }

   // --------- reconnect from 0 to B ----------
   if(ObjExists("B") && s0!=sA)
     {
      // B index & time
      datetime tB_check = GetObjTimeSafe("B");
      int idxB_check = iBarShift(_Symbol,_Period,tB_check,false);
      if(idxB_check<0)
        {
         int bestB = 0;
         long bestDiffB = (long)MathAbs((long)(TimeSeries[0] - tB_check));
         for(int i=1; i<Bars; i++)
           {
            long d = (long)MathAbs((long)(TimeSeries[i] - tB_check));
            if(d < bestDiffB) { bestB = i; bestDiffB = d; }
           }
         idxB_check = bestB;
        }

      // compute e, d, mid at B
      double slope_v = (v0 - vA)/double(s0 - sA);
      double pB_v = v0 + slope_v*(idxB_check - s0);    // مقدار e در زمان B (نقطهٔ بالایی v)
      double slope_ma = (ma0 - maA)/double(s0 - sA);
      double pB_ma = ma0 + slope_ma*(idxB_check - s0);

      double midA_local = (maA + vA)/2;
      double mid0_local = (ma0 + v0)/2;
      double slope_mid = (mid0_local - midA_local)/double(s0 - sA);
      double pB_mid = mid0_local + slope_mid*(idxB_check - s0); // مقدار mid (پایین v) در B

      // reconnect d,e,3 to B
      EnsureTrend("d", TimeSeries[s0], ma0, TimeSeries[idxB_check], pB_ma, LineD_Color, LineD_Width, STYLE_SOLID, 1);
      EnsureTrend("e", TimeSeries[s0], v0,   TimeSeries[idxB_check], pB_v,   LineE_Color, LineE_Width, STYLE_SOLID, 1);
      EnsureTrend("3", TimeSeries[s0], mid0_local, TimeSeries[idxB_check], pB_mid, Line3_Color, Line3_Width, STYLE_SOLID, 2);

      // draw/maintain v: vertical segment BETWEEN line 3 (pB_mid) and line e (pB_v) at B
      // only draw if ShowV == true
      if(ShowV)
        {
         EnsureTrend("v",
                     TimeSeries[idxB_check], pB_mid,
                     TimeSeries[idxB_check], pB_v,
                     clrMagenta, 2, STYLE_SOLID, 2);
        }
      else
        {
         SafeDelete("v");
        }

      // اندازه v در B
      double v_len_atB = MathAbs(pB_v - pB_mid);        // اندازهٔ v

      // نقاط انتهای v_ext برای دو حالت (بالا یا پایین)
      double pB_v_ext_top    = pB_v + v_len_atB;       // بالا (حالت قبلی)
      double pB_v_ext_bottom = pB_v - v_len_atB;       // پایین (حالت Use Low)

      // determine one-candle seconds and max (24 candles)
      int one_candle_seconds = (Bars>1)?(int)(TimeSeries[0]-TimeSeries[1]):(int)PeriodSeconds(_Period);
      long max_seconds = (long)one_candle_seconds * 24;

      // رسم v_ext بر اساس وضعیت g_useLow:
      // اگر use low فعال باشد امتداد به سمت پایین رسم شود، در غیر اینصورت به سمت بالا
      if(ShowV)
        {
         if(!g_useLow)
           {
            // continuation v_ext start at pB_v and extend UP by same length as v
            EnsureTrend("v_ext",
                        TimeSeries[idxB_check], pB_v,
                        TimeSeries[idxB_check], pB_v_ext_top,
                        clrMagenta, 2, STYLE_SOLID, 2);
           }
         else
           {
            EnsureTrend("v_ext",
                        TimeSeries[idxB_check], pB_v,
                        TimeSeries[idxB_check], pB_v_ext_bottom,
                        clrMagenta, 2, STYLE_SOLID, 2);
           }
        }
      else
        {
         SafeDelete("v_ext");
        }

      // ---------- TP / SL: preserve horizontal length in seconds (capped to 24 candles) ----------
      long current_right_seconds = (long)(TimeSeries[0] - TimeSeries[idxB_check]); // positive
      if(g_tp_len_seconds==0) g_tp_len_seconds = MathMin(current_right_seconds, max_seconds);
      else g_tp_len_seconds = MathMin(g_tp_len_seconds, max_seconds);
      if(g_sl_len_seconds==0) g_sl_len_seconds = MathMin(current_right_seconds, max_seconds);
      else g_sl_len_seconds = MathMin(g_sl_len_seconds, max_seconds);

      // compute end times using preserved seconds
      datetime tp_end_time = TimeSeries[idxB_check] + g_tp_len_seconds;
      datetime sl_end_time = TimeSeries[idxB_check] + g_sl_len_seconds;

      // Compute SL price: normally pB_v_ext_top/bottom depending on g_useLow, but if double enabled adjust
      double sl_price;
      if(!g_doubleSL)
        {
         sl_price = (!g_useLow) ? pB_v_ext_top : pB_v_ext_bottom;
        }
      else
        {
         if(!g_useLow) sl_price = pB_v + 2.0 * v_len_atB;
         else sl_price = pB_v - 2.0 * v_len_atB;
        }

      // --- OVERRIDE WITH MANUAL PRICES IF USER DRAGGED TP/SL ---
      double tp_price_final = pB_mid;
      double sl_price_final = sl_price;

      if(g_manualTP)
        {
         // if user set manual TP price, use it (and ensure label text uses that price)
         tp_price_final = g_tp_price;
        }
      if(g_manualSL)
        {
         sl_price_final = g_sl_price;
        }

      // Ensure horizontal TP: from Time[idxB_check] at price tp_price_final to tp_end_time same price
      EnsureTrend("tp", TimeSeries[idxB_check], tp_price_final, tp_end_time, tp_price_final, clrGreen, 1, STYLE_SOLID, 2);
      // Ensure horizontal SL: from Time[idxB_check] at price sl_price_final to sl_end_time same price
      EnsureTrend("sl", TimeSeries[idxB_check], sl_price_final, sl_end_time, sl_price_final, clrRed, 1, STYLE_SOLID, 2);

      // labels: place at the end (right) of each horizontal line, anchor LEFT
      datetime lbl_tp_time = tp_end_time + one_candle_seconds; // یک کندل جلوتر
      EnsureText("lbl_tp", lbl_tp_time, tp_price_final, "TP="+DoubleToString(tp_price_final,(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS)), clrGreen, LabelFontSize, ANCHOR_LEFT, 3);

      datetime lbl_sl_time = sl_end_time + one_candle_seconds; // جلوتر یک کندل
      EnsureText("lbl_sl", lbl_sl_time, sl_price_final, "SL="+DoubleToString(sl_price_final,(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS)), clrRed, LabelFontSize, ANCHOR_LEFT, 3);

      // --------------------------------------------------------------------

      // --- NEW: draw BUY/SELL entry line and MOVE lbl_BE to front of it ---
      // If g_useLow==false => using HIGH => treat as SELL (red). If g_useLow==true => BUY (blue).
      string sigName = "lbl_BE";
      string sigTxt;
      color  sigClr;

      // compute shifted price for entry label if toggle enabled
      double entry_price = pB_v;
      if(g_shiftEntryByV)
        {
         // if SELL -> shift up by v_len_atB, if BUY -> shift down by v_len_atB
         if(!g_useLow) // SELL
            entry_price = pB_v + v_len_atB;
         else // BUY
            entry_price = pB_v - v_len_atB;
        }

      if(!g_useLow)
        {
         sigTxt = "SELL " + DoubleToString(entry_price, (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS));
         sigClr = clrRed;
        }
      else
        {
         sigTxt = "BUY " + DoubleToString(entry_price, (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS));
         sigClr = clrBlue;
        }

      // ensure g_tp_len_seconds initialized like TP/SL block above
      if(g_tp_len_seconds==0) g_tp_len_seconds = MathMin((long)(TimeSeries[0] - TimeSeries[idxB_check]), max_seconds);
      else g_tp_len_seconds = MathMin(g_tp_len_seconds, max_seconds);

      // draw horizontal "entry" line with same duration as TP (g_tp_len_seconds)
      datetime entry_end_time = TimeSeries[idxB_check] + g_tp_len_seconds;
      EnsureTrend("entry", TimeSeries[idxB_check], entry_price, entry_end_time, entry_price, sigClr, 1, STYLE_SOLID, 2);

      // Move the existing buy/sell label (lbl_BE) to be in front of the entry line
      datetime lbl_be_time = entry_end_time + one_candle_seconds;
      EnsureText(sigName, lbl_be_time, entry_price, "Entry="+DoubleToString(entry_price,(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS)), sigClr, LabelFontSize, ANCHOR_LEFT, 4);

      // ----------------- NEW: محاسبه و نمایش اختلاف پیپ (سمت راست پایین) -----------------
      // محاسبهٔ اختلاف پیپ بین Entry و TP و Entry و SL و نمایش در یک برچسب گوشهٔ پایین-راست
      int pipsTP = (int)MathRound(MathAbs(tp_price_final - entry_price) / pip);
      int pipsSL = (int)MathRound(MathAbs(sl_price_final - entry_price) / pip);

      string diffs = "Entry="+DoubleToString(entry_price,(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS))+"  TP="+IntegerToString(pipsTP)+"p  SL="+IntegerToString(pipsSL)+"p";

      if(!ObjExists("lbl_diffs"))
        {
         ObjectCreate(0,"lbl_diffs",OBJ_LABEL,0,0,0);
         g_needRedraw = true;
        }
      SetIfDifferent_String("lbl_diffs", OBJPROP_TEXT, diffs);
      SetIfDifferent_Int   ("lbl_diffs", OBJPROP_CORNER, 3); // bottom-right
      SetIfDifferent_Int   ("lbl_diffs", OBJPROP_XDISTANCE, 300);
      SetIfDifferent_Int   ("lbl_diffs", OBJPROP_YDISTANCE, 20);
      SetIfDifferent_Int   ("lbl_diffs", OBJPROP_COLOR, Label_Color);
      SetIfDifferent_Int   ("lbl_diffs", OBJPROP_FONTSIZE, LabelFontSize);
      SetIfDifferent_Int   ("lbl_diffs", OBJPROP_BACK, 1);
      // -------------------------------------------------------------------------------

     }
   else
     {
      // اگر B وجود ندارد و B دستی نیست، حذف کن و طول‌های ذخیره‌شده را صفر کن
      if(!g_manualB)
        {
         SafeDelete("tp"); SafeDelete("sl");
         SafeDelete("lbl_tp"); SafeDelete("lbl_sl");
         SafeDelete("v"); SafeDelete("v_ext");
         SafeDelete("lbl_BE"); // remove buy/sell label when B removed
         SafeDelete("entry");
         SafeDelete("lbl_diffs"); // پاک کن برچسب اختلاف‌ها وقتی B نیست
         g_tp_len_seconds = 0;
         g_sl_len_seconds = 0;

         // also reset manual TP/SL flags when B gone
         g_manualTP = false;
         g_manualSL = false;
         g_tp_price = 0.0;
         g_sl_price = 0.0;
        }
     }
   // ---------------------------------------------------------

   // H‐labels ...
   double yOff = g_LabelOffsetPips * pip;

   double winTop=0.0, winBottom=0.0;
   int vf = WindowFirstVisibleBar();
   int vb = WindowBarsPerChart();
   if(vf<0) vf = 0;
   if(vb<=0) vb = Bars;
   int lastVis = MathMin(Bars-1, vf + vb - 1);
   if(lastVis < vf) lastVis = vf;
   winTop = HighSeries[vf];
   winBottom = LowSeries[vf];
   for(int vi = vf; vi<=lastVis; vi++)
     {
      if(HighSeries[vi] > winTop) winTop = HighSeries[vi];
      if(LowSeries[vi] < winBottom) winBottom = LowSeries[vi];
     }
   double margin = (winTop - winBottom) * 0.02;
   if(margin <= 0) margin = pip * 10;

   // H2
   if(g_labelToggleState != 1)
     {
      double h2price = HighSeries[sA] + 2*SymbolInfoDouble(_Symbol,SYMBOL_POINT) + yOff;
      if(h2price > winTop - margin) h2price = winTop - margin;
      if(h2price < winBottom + margin) h2price = winBottom + margin;
      EnsureText("H2", TimeSeries[sA], h2price, "H2", Label_Color, LabelFontSize, ANCHOR_CENTER, 3);
     }
   else SafeDelete("H2");

   // H1
   if(g_labelToggleState != 1)
     {
      double h1price = HighSeries[s0] + 2*SymbolInfoDouble(_Symbol,SYMBOL_POINT) + yOff;
      if(h1price > winTop - margin) h1price = winTop - margin;
      if(h1price < winBottom + margin) h1price = winBottom + margin;
      EnsureText("H1", TimeSeries[s0], h1price, "H1", Label_Color, LabelFontSize, ANCHOR_CENTER, 3);
     }
   else SafeDelete("H1");

   // H3
   if(g_labelToggleState != 1)
     {
      if(ObjExists("B"))
        {
         datetime tB = GetObjTimeSafe("B");
         int iB = iBarShift(_Symbol,_Period,tB,false);
         if(iB<0)
           {
            int bestB = 0;
            long bestDiffB = (long)MathAbs((long)(TimeSeries[0] - tB));
            for(int i=1; i<Bars; i++)
              {
               long d = (long)MathAbs((long)(TimeSeries[i] - tB));
               if(d < bestDiffB) { bestB = i; bestDiffB = d; }
              }
            iB = bestB;
           }
         if(iB>=0 && iB<Bars)
           {
            double h3price = HighSeries[iB] + 2*SymbolInfoDouble(_Symbol,SYMBOL_POINT) + yOff;
            if(h3price > winTop - margin) h3price = winTop - margin;
            if(h3price < winBottom + margin) h3price = winBottom + margin;
            EnsureText("H3", TimeSeries[iB], h3price, "H3", Label_Color, LabelFontSize, ANCHOR_CENTER, 3);
           }
         else SafeDelete("H3");
        }
      else SafeDelete("H3");
     }
   else SafeDelete("H3");

   // Labels on lines A,0,B
   double topLabelPrice = winTop - margin/4;
   if(topLabelPrice > winTop) topLabelPrice = winTop - margin;
   if(topLabelPrice < winBottom) topLabelPrice = winBottom + margin;

   if(g_labelToggleState != 2)
     EnsureText("lbl_A", TimeSeries[sA], topLabelPrice, "A", Label_Color, LabelFontSize, ANCHOR_CENTER, 5);
   else SafeDelete("lbl_A");

   if(g_labelToggleState != 2)
     EnsureText("lbl_0", TimeSeries[s0], topLabelPrice, "0", Label_Color, LabelFontSize, ANCHOR_CENTER, 5);
   else SafeDelete("lbl_0");

   if(g_labelToggleState != 2 && ObjExists("B"))
     {
      datetime tB_lbl = GetObjTimeSafe("B");
      EnsureText("lbl_B", tB_lbl, topLabelPrice, "B", Label_Color, LabelFontSize, ANCHOR_CENTER, 5);
     }
   else SafeDelete("lbl_B");

   SetIfDifferent_String("btnLblSize",OBJPROP_TEXT,"LblSize:"+IntegerToString(LabelFontSize));

   if(g_needRedraw) ChartRedraw();
  }

//+------------------------------------------------------------------+
//| DrawExtendedTrend                                                |
//+------------------------------------------------------------------+
void DrawExtendedTrend(string name,int i1,double p1,int i2,double p2,color clr,int w,int z)
  {
   if(i1==i2)
     {
      EnsureTrend(name, TimeSeries[i1], p1, TimeSeries[i1], p2, clr, w, STYLE_SOLID, z);
      return;
     }
   if(i1>i2)
     {
      int    ti = i1;  i1 = i2;  i2 = ti;
      double tp = p1;  p1 = p2;  p2 = tp;
     }
   double slope = (p2 - p1)/double(i2 - i1);
   int left  = MathMax(0,      i1 - ExtendBars);
   int right = MathMin(Bars-1, i2 + ExtendBars);
   EnsureTrend(name,
               TimeSeries[left],  p1 + slope*(left - i1),
               TimeSeries[right], p1 + slope*(right - i1),
               clr, w, STYLE_SOLID, z);
  }
//+------------------------------------------------------------------+

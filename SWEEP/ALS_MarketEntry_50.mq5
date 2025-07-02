//+------------------------------------------------------------------+
//|         ALS 1.17 – Market Entry on 50% Leg Touch                 |
//|     © 2024 Greaterwaves Coder for MT5 – www.greaterwaves.com     |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

//--- Inputs
sinput group "Session & Risk"
input ulong   MagicNumber             = 777;
input string  AsianSessionStartStr    = "03:00";
input string  AsianSessionEndStr      = "07:00";
input double  RiskPercentPerTrade     = 1.0;
input double  RiskRewardRatio         = 3.0;
input int     SLBufferPips            = 0;
input int     MaxDistanceFromAsianBox = 25;
input int     MaxBuysPerDay           = 3;
input int     MaxSellsPerDay          = 3;

sinput group "Fractals & BOS"
input int     FractalLookback         = 3;
enum ENUM_CONFIRM_TYPE { WickOnly, BodyBreak, Either };
input ENUM_CONFIRM_TYPE BOSConfirmType = Either;

sinput group "Visuals"
input bool    ShowAsianBox            = true;
input bool    ShowFractals            = true;
input bool    ShowLines               = true;
input color   FractalBullColor        = clrDodgerBlue;
input color   FractalBearColor        = clrOrange;
input color   SweepColor              = clrRed;
input color   BOSColor                = clrLime;
input color   EntryLineColor          = clrYellow;
input color   AsianBoxColor           = clrAqua;
input bool    EnableDebug             = true;

//--- Globals
CTrade trade;
datetime glLastBarTime;
int glLastProcessedDay = -1;
datetime asianStart, asianEnd;
double asianHigh, asianLow;
bool asianBoxDrawn = false;
int buyCount = 0;
int sellCount = 0;
double dailyHigh = 0.0;
double dailyLow  = 0.0;

struct FractalPoint
{
   double price;    // extreme value of the fractal
   double high;     // candle high
   double low;      // candle low
   datetime time;
};
FractalPoint lastBullFractal, lastBearFractal;
FractalPoint triggerBuyFractal, triggerSellFractal;

struct SetupState
{
   bool sweepDetected;
   bool bosConfirmed;
   bool entryTriggered;
   double legHigh;
   double legLow;
   double entryPrice;
   double bosFractalPrice; // price of the fractal that confirmed BOS
   double fractalHigh;
   double fractalLow;
   datetime fractalTime;
};
SetupState buyState, sellState;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   glLastBarTime = 0;
   ObjectsDeleteAll(0, "", 0);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "", 0);
}
//+------------------------------------------------------------------+
void OnTick()
{

   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if (glLastProcessedDay != dt.day)
   {
      glLastProcessedDay = dt.day;
      asianBoxDrawn = false;
      buyState = SetupState();
      sellState = SetupState();
      buyCount = 0;
      sellCount = 0;
      dailyHigh = 0.0;
      dailyLow  = 0.0;
      ObjectsDeleteAll(0, "", 0);
   }

   UpdateAsianSession();
   if (!asianBoxDrawn) return;

   // update daily extremes after Asian box is available
   double curHigh = iHigh(_Symbol, _Period, 0);
   double curLow  = iLow(_Symbol, _Period, 0);
   if(curHigh > dailyHigh)
   {
      dailyHigh = curHigh;
      if(EnableDebug) Print("📈 New dailyHigh=", dailyHigh);
   }
   if(curLow < dailyLow)
   {
      dailyLow = curLow;
      if(EnableDebug) Print("📉 New dailyLow=", dailyLow);
   }

   DetectFractals();
   if (ShowFractals) DrawFractals();

   UpdateTriggerFractals();

   RunSetup(false, buyState, triggerBuyFractal);
   RunSetup(true, sellState, triggerSellFractal);
}
//+------------------------------------------------------------------+
void UpdateAsianSession()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   string dateStr = StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day);
   asianStart = StringToTime(dateStr + " " + AsianSessionStartStr);
   asianEnd   = StringToTime(dateStr + " " + AsianSessionEndStr);

   if (TimeCurrent() < asianEnd || asianBoxDrawn) return;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, _Period, asianStart, asianEnd, rates);
   if (copied < 2) return;

   asianHigh = rates[0].high;
   asianLow  = rates[0].low;
   for (int i = 1; i < copied; i++)
   {
      if (rates[i].high > asianHigh) asianHigh = rates[i].high;
      if (rates[i].low  < asianLow)  asianLow  = rates[i].low;
   }

   if (ShowAsianBox)
   {
      ObjectDelete(0, "ASIAN_BOX");
      ObjectCreate(0, "ASIAN_BOX", OBJ_RECTANGLE, 0, asianStart, asianHigh, asianEnd, asianLow);
      ObjectSetInteger(0, "ASIAN_BOX", OBJPROP_COLOR, AsianBoxColor);
      ObjectSetInteger(0, "ASIAN_BOX", OBJPROP_BACK, true);
   }

   if (EnableDebug)
      Print("✅ Asian Box: High=", asianHigh, " Low=", asianLow);

   dailyHigh = asianHigh;
   dailyLow  = asianLow;

   asianBoxDrawn = true;
}
//+------------------------------------------------------------------+
void DetectFractals()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   CopyRates(_Symbol, _Period, 0, 50, rates);

   lastBullFractal = FractalPoint();
   lastBearFractal = FractalPoint();

   for (int i = 2; i < ArraySize(rates) - 2; i++)
   {
      if (rates[i].low < rates[i - 1].low && rates[i].low < rates[i + 1].low)
      {
         lastBullFractal.price = rates[i].low;
         lastBullFractal.high  = rates[i].high;
         lastBullFractal.low   = rates[i].low;
         lastBullFractal.time  = rates[i].time;
         break;
      }
   }

   for (int i = 2; i < ArraySize(rates) - 2; i++)
   {
      if (rates[i].high > rates[i - 1].high && rates[i].high > rates[i + 1].high)
      {
         lastBearFractal.price = rates[i].high;
         lastBearFractal.high  = rates[i].high;
         lastBearFractal.low   = rates[i].low;
         lastBearFractal.time  = rates[i].time;
         break;
      }
   }

   static datetime lastLogBarTime = 0;
   if (rates[0].time != lastLogBarTime)
   {
      if (EnableDebug)
         Print("Fractals: Bull=", lastBullFractal.price, " Bear=", lastBearFractal.price);
      lastLogBarTime = rates[0].time;
   }
}
//+------------------------------------------------------------------+
void DrawFractals()
{
   if (lastBullFractal.price > 0.0)
      DrawArrow("BullFractal", lastBullFractal.time, lastBullFractal.price, FractalBullColor, 241);
   if (lastBearFractal.price > 0.0)
      DrawArrow("BearFractal", lastBearFractal.time, lastBearFractal.price, FractalBearColor, 242);
}
void DrawArrow(string name, datetime time, double price, color clr, int code)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_ARROW, 0, time, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, code);
}
void DrawLine(string name, double price, color clr)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_HLINE, 0, TimeCurrent(), price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
}
//+------------------------------------------------------------------+
void UpdateTriggerFractals()
{
   if(TimeCurrent() < asianEnd) return;

   if(lastBearFractal.time > 0 && lastBearFractal.time > asianEnd && lastBearFractal.high >= dailyHigh && lastBearFractal.time != triggerSellFractal.time)
   {
      triggerSellFractal = lastBearFractal;
      sellState = SetupState();
      if(EnableDebug) Print("🔔 New SELL fractal at ", triggerSellFractal.high);
   }

   if(lastBullFractal.time > 0 && lastBullFractal.time > asianEnd && lastBullFractal.low <= dailyLow && lastBullFractal.time != triggerBuyFractal.time)
   {
      triggerBuyFractal = lastBullFractal;
      buyState = SetupState();
      if(EnableDebug) Print("🔔 New BUY fractal at ", triggerBuyFractal.low);
   }
}
//+------------------------------------------------------------------+
void RunSetup(bool forSell, SetupState &state, FractalPoint &fract)
{
   string side = forSell ? "SELL" : "BUY";
   if(forSell && sellCount >= MaxSellsPerDay) return;
   if(!forSell && buyCount >= MaxBuysPerDay) return;
   double high = iHigh(_Symbol, _Period, 0);
   double low  = iLow(_Symbol, _Period, 0);
   double close = iClose(_Symbol, _Period, 0);

   if(fract.price <= 0.0) return;

   // register new fractal
   if(state.fractalTime != fract.time)
   {
      state = SetupState();
      state.sweepDetected = true;
      state.fractalTime   = fract.time;
      state.fractalHigh   = fract.high;
      state.fractalLow    = fract.low;
      state.legHigh       = fract.high;
      state.legLow        = fract.low;
      state.bosFractalPrice = forSell ? fract.low : fract.high;
      if(EnableDebug) Print("📍 ", side, " fractal registered at ", state.bosFractalPrice);
   }

   // 1. BOS detectie
   if(!state.bosConfirmed)
   {
      bool bos = false;
      if(forSell)
      {
         if (BOSConfirmType == WickOnly) bos = low < state.fractalLow;
         else if (BOSConfirmType == BodyBreak) bos = close < state.fractalLow;
         else bos = low < state.fractalLow || close < state.fractalLow;
         if(bos) state.legLow = low;
      }
      else
      {
         if (BOSConfirmType == WickOnly) bos = high > state.fractalHigh;
         else if (BOSConfirmType == BodyBreak) bos = close > state.fractalHigh;
         else bos = high > state.fractalHigh || close > state.fractalHigh;
         if(bos) state.legHigh = high;
      }

      if(bos)
      {
         state.bosConfirmed = true;
         state.entryPrice = (state.legHigh + state.legLow)/2.0;
         if(EnableDebug) Print("✅ ", side, " BOS confirmed. Entry=", state.entryPrice);
         if(ShowLines) DrawLine("BOS_"+side, forSell ? low : high, BOSColor);
      }
      return;
   }

   // 2. Na BOS: volg leg verder
   if(!state.entryTriggered)
   {
      bool updated=false;
      if(forSell)
      {
         if(low < state.legLow)
         {
            state.legLow = low;
            updated = true;
         }
      }
      else
      {
         if(high > state.legHigh)
         {
            state.legHigh = high;
            updated = true;
         }
      }
      if(updated)
      {
         state.entryPrice = (state.legHigh + state.legLow)/2.0;
         if(EnableDebug) Print("🔄 ", side, " leg updated. New entry=", state.entryPrice);
      }

      double entry = state.entryPrice;

      if(ShowLines)
         DrawLine("ENTRY_" + side, entry, EntryLineColor);

      double price = (forSell ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK));
      bool trigger = forSell ? (price >= entry) : (price <= entry);
      if(trigger)
      {
         double sl = forSell ? dailyHigh + SLBufferPips*_Point : dailyLow - SLBufferPips*_Point;
         double tp = forSell ? entry - (sl - entry) * RiskRewardRatio : entry + (entry - sl) * RiskRewardRatio;
         double lot = CalculateLots(MathAbs(entry - sl) / _Point);
         if(lot <= 0.0) return;

         bool sent = forSell ? trade.Sell(lot, _Symbol, 0, sl, tp, "ALS_17_SELL")
                             : trade.Buy(lot, _Symbol, 0, sl, tp, "ALS_17_BUY");

         if(sent)
         {
            if(forSell) sellCount++; else buyCount++;
            state.entryTriggered = true;
            if(EnableDebug) Print("📥 ", side, " MARKET order at ", entry, " SL=", sl, " TP=", tp, " Lot=", lot);
         }
      }
   }
}
//+------------------------------------------------------------------+
double CalculateLots(double slPips)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk = balance * RiskPercentPerTrade / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if (tickValue <= 0.0 || tickSize <= 0.0) return 0.01;

   double sl = slPips * point;
   double lossPerLot = (sl / tickSize) * tickValue;
   if (lossPerLot <= 0.0) return 0.01;

   double rawLots = risk / lossPerLot;
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   double lots = MathFloor(rawLots / step) * step;
   return NormalizeDouble(MathMax(min, MathMin(max, lots)), 2);
}

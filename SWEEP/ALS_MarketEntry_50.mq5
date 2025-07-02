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
input int     MaxTradesPerDay         = 3;

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
int  tradeCount = 0;
double lastBuyTradeLow = 0.0;
double lastSellTradeHigh = 0.0;
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

struct SetupState
{
   bool sweepDetected;
   bool bosConfirmed;
   bool orderPlaced;
   datetime sweepTime;
   FractalPoint fractal;
   FractalPoint potential;
   double bosPrice;
   double entryPrice;
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
      tradeCount = 0;
      lastBuyTradeLow = 0.0;
      lastSellTradeHigh = 0.0;
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

   RunSetup(false, buyState); // BUY
   RunSetup(true, sellState); // SELL
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
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   string dateStr = StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day);
   datetime dayStart = StringToTime(dateStr + " 00:00");

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, _Period, dayStart, TimeCurrent(), rates);
   if(copied < 5) return;

   lastBullFractal = FractalPoint();
   lastBearFractal = FractalPoint();

   for(int i=2; i<copied-2; i++)
   {
      if(rates[i].low < rates[i-1].low && rates[i].low < rates[i+1].low)
      {
         bool isNew = true;
         for(int j=i+1; j<copied; j++)
            if(rates[j].low <= rates[i].low){ isNew=false; break; }
         if(isNew)
         {
            lastBullFractal.price = rates[i].low;
            lastBullFractal.high  = rates[i].high;
            lastBullFractal.low   = rates[i].low;
            lastBullFractal.time  = rates[i].time;
         }
      }
   }

   for(int i=2; i<copied-2; i++)
   {
      if(rates[i].high > rates[i-1].high && rates[i].high > rates[i+1].high)
      {
         bool isNew = true;
         for(int j=i+1; j<copied; j++)
            if(rates[j].high >= rates[i].high){ isNew=false; break; }
         if(isNew)
         {
            lastBearFractal.price = rates[i].high;
            lastBearFractal.high  = rates[i].high;
            lastBearFractal.low   = rates[i].low;
            lastBearFractal.time  = rates[i].time;
         }
      }
   }

   static datetime lastLogBarTime = 0;
   if(rates[0].time != lastLogBarTime)
   {
      if(EnableDebug)
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
void RunSetup(bool forSell, SetupState &state)
{
   string side = forSell ? "SELL" : "BUY";
   if(tradeCount >= MaxTradesPerDay) return;
   double high = iHigh(_Symbol, _Period, 0);
   double low  = iLow(_Symbol, _Period, 0);

   // Wait for new extreme after a trade has been placed
   if(state.orderPlaced)
   {
      if(forSell)
      {
         if(dailyHigh > lastSellTradeHigh)
         {
            state = SetupState();
            lastSellTradeHigh = 0.0;
         }
         return;
      }
      else
      {
         if(dailyLow < lastBuyTradeLow)
         {
            state = SetupState();
            lastBuyTradeLow = 0.0;
         }
         return;
      }
   }

   // 1. Detect sweep of the Asian range
   if(!state.sweepDetected)
   {
      bool swept = forSell ? (high > asianHigh) : (low < asianLow);
      if(swept)
      {
         state.sweepDetected = true;
         state.sweepTime = TimeCurrent();
         state.potential.price = forSell ? high : low;
         state.potential.high  = high;
         state.potential.low   = low;
         state.potential.time  = TimeCurrent();
         if(EnableDebug) Print("🔻 ", side, " SWEEP detected");
         if(ShowLines) DrawLine("SWEEP_" + side, forSell ? high : low, SweepColor);
      }
      return;
   }

   // update latest extreme after the sweep
   if(forSell)
   {
      if(high > state.potential.high)
      {
         state.potential.price = high;
         state.potential.high  = high;
         state.potential.low   = low;
         state.potential.time  = TimeCurrent();
      }
   }
   else
   {
      if(state.potential.price==0 || low < state.potential.low)
      {
         state.potential.price = low;
         state.potential.high  = high;
         state.potential.low   = low;
         state.potential.time  = TimeCurrent();
      }
   }

   // 2. Track fractals forming new daily extremes after the sweep
   FractalPoint latest = forSell ? lastBearFractal : lastBullFractal;
   if(latest.price > 0 && latest.time >= state.sweepTime && !state.bosConfirmed)
   {
      if(state.fractal.time == 0 || (forSell ? latest.price > state.fractal.price : latest.price < state.fractal.price))
      {
         state.fractal = latest;
         if(EnableDebug) Print("📌 ", side, " fractal at ", state.fractal.price);
      }
   }

   FractalPoint checkFractal = state.fractal;
   if(checkFractal.price <= 0 && BOSConfirmType == WickOnly)
      checkFractal = state.potential;

   if(checkFractal.price <= 0) return;

   // 3. Break of structure when fractal is broken
   if(!state.bosConfirmed)
   {
      static datetime lastWaitLog=0;
      bool bos = forSell ? (low < checkFractal.low) : (high > checkFractal.high);
      if(bos)
      {
        state.bosConfirmed = true;
        state.bosPrice = forSell ? low : high;
         if(state.fractal.price <= 0)
            state.fractal = checkFractal;

         state.entryPrice = forSell ? (state.fractal.high + state.bosPrice) / 2.0
                                    : (state.fractal.low + state.bosPrice) / 2.0;
         if(EnableDebug) Print("✅ ", side, " BOS confirmed. Entry=", state.entryPrice);
         if(ShowLines) DrawLine("BOS_" + side, state.bosPrice, BOSColor);

         double sl = forSell ? dailyHigh + SLBufferPips * _Point
                             : dailyLow  - SLBufferPips * _Point;
         double tp = forSell ? state.entryPrice - (sl - state.entryPrice) * RiskRewardRatio
                             : state.entryPrice + (state.entryPrice - sl) * RiskRewardRatio;
         double lot = CalculateLots(MathAbs(state.entryPrice - sl) / _Point);
         if(lot <= 0.0) return;

         double distPips = MathAbs(state.entryPrice - (forSell ? asianHigh : asianLow)) / _Point;
         if(distPips > MaxDistanceFromAsianBox)
         {
            if(EnableDebug) Print("❌ ", side, " entry too far from Asian box: ", distPips);
            state = SetupState();
            return;
         }

         bool sent = forSell
            ? trade.SellLimit(lot, state.entryPrice, _Symbol, sl, tp)
            : trade.BuyLimit(lot, state.entryPrice, _Symbol, sl, tp);

         if(sent)
         {
            tradeCount++;
            state.orderPlaced = true;
            if(forSell) lastSellTradeHigh = dailyHigh; else lastBuyTradeLow = dailyLow;
            if(EnableDebug) Print("📥 Pending ", side, " order @", state.entryPrice, " SL=", sl, " TP=", tp, " Lot=", lot);
            if(ShowLines) DrawLine("ENTRY_" + side, state.entryPrice, EntryLineColor);
         }
      }
      else if(EnableDebug && lastWaitLog!=TimeCurrent())
      {
         Print("⏳ Waiting BOS ", side, " fractal=", checkFractal.price,
               " dailyHigh=", dailyHigh, " dailyLow=", dailyLow);
         lastWaitLog = TimeCurrent();
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

//+------------------------------------------------------------------+
//|         ALS 1.17 – Market Entry on 50% Leg Touch                 |
//|     © 2024 Greaterwaves Coder for MT5 – www.greaterwaves.com     |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

//--- Inputs
sinput group "Session & Risk"
input ulong   MagicNumber             = 777;
input string  AsianSessionStartStr    = "02:00";
input string  AsianSessionEndStr      = "06:00";
input double  RiskPercentPerTrade     = 1.0;
input double  RiskRewardRatio         = 2.0;
input int     SLBufferPips            = 10;
input int     MaxDistanceFromAsianBox = 25;

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
   bool entryTriggered;
   double legHigh;
   double legLow;
   double entryPrice;
   double bosFractalPrice; // price of the fractal that confirmed BOS
   datetime sweepFractalTime; // time of fractal used for sweep detection
   datetime bosFractalTime;   // time of fractal that confirmed BOS
   datetime lastEntryBOSTime; // time of BOS fractal used for last entry
};
SetupState buyState, sellState;


bool PositionExists(bool forSell)
{
   if(!PositionSelect(_Symbol))
      return false;

   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   if(forSell && type == POSITION_TYPE_SELL)
      return true;
   if(!forSell && type == POSITION_TYPE_BUY)
      return true;
   return false;
}

void ResetSetup(SetupState &state, string side)
{
   state = SetupState();
   if(ShowLines)
   {
      ObjectDelete(0, "SWEEP_" + side);
      ObjectDelete(0, "BOS_" + side);
      ObjectDelete(0, "ENTRY_" + side);
   }
}


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
      ResetSetup(buyState, "BUY");
      ResetSetup(sellState, "SELL");
      ObjectsDeleteAll(0, "", 0);
   }

   if(buyState.entryTriggered && !PositionExists(false))
      ResetSetup(buyState, "BUY");
   if(sellState.entryTriggered && !PositionExists(true))
      ResetSetup(sellState, "SELL");

   UpdateAsianSession();
   if (!asianBoxDrawn) return;

   DetectFractals();
   if (ShowFractals) DrawFractals();

   RunSetup(false, buyState, lastBullFractal, lastBearFractal); // BUY
   RunSetup(true, sellState, lastBearFractal, lastBullFractal); // SELL
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

   for (int i = FractalLookback; i < ArraySize(rates) - FractalLookback; i++)
   {
      bool isFractal = true;
      for(int j=1; j<=FractalLookback; j++)
      {
         if(!(rates[i].low < rates[i-j].low && rates[i].low < rates[i+j].low))
         {
            isFractal = false;
            break;
         }
      }
      if(isFractal)
      {
         lastBullFractal.price = rates[i].low;
         lastBullFractal.high  = rates[i].high;
         lastBullFractal.low   = rates[i].low;
         lastBullFractal.time  = rates[i].time;
         break;
      }
   }

   for (int i = FractalLookback; i < ArraySize(rates) - FractalLookback; i++)
   {
      bool isFractal = true;
      for(int j=1; j<=FractalLookback; j++)
      {
         if(!(rates[i].high > rates[i-j].high && rates[i].high > rates[i+j].high))
         {
            isFractal = false;
            break;
         }
      }
      if(isFractal)
      {
         lastBearFractal.price = rates[i].high;
         lastBearFractal.high  = rates[i].high;
         lastBearFractal.low   = rates[i].low;
         lastBearFractal.time  = rates[i].time;
         break;
      }
   }

   if (EnableDebug)
      Print("Fractals: Bull=", lastBullFractal.price, " Bear=", lastBearFractal.price);
}
//+------------------------------------------------------------------+
void DrawFractals()
{
   if (lastBullFractal.price > 0.0)
      DrawLine("BullFractal", lastBullFractal.price, FractalBullColor);
   if (lastBearFractal.price > 0.0)
      DrawLine("BearFractal", lastBearFractal.price, FractalBearColor);
}
void DrawLine(string name, double price, color clr)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_HLINE, 0, TimeCurrent(), price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
}
//+------------------------------------------------------------------+
void RunSetup(bool forSell, SetupState &state, FractalPoint &sweepFractal, FractalPoint &bosFractal)
{
   string side = forSell ? "SELL" : "BUY";
   double high = iHigh(_Symbol, _Period, 0);
   double low  = iLow(_Symbol, _Period, 0);
   double close = iClose(_Symbol, _Period, 0);

   // skip setup if an opposite position exists
   if(PositionExists(!forSell))
      return;

   // Tijdens een actieve setup blijft de leg lopen
   if (state.sweepDetected && !state.bosConfirmed)
   {
      if (forSell && high > state.legHigh)  state.legHigh = high;
      if (!forSell && low  < state.legLow)  state.legLow  = low;
   }

   // 1. Sweep detectie
   if (!state.sweepDetected)
   {
      double distAsian = forSell ? high - asianHigh : asianLow - low;
      double distFractal = forSell
         ? MathAbs(sweepFractal.price - asianHigh)
         : MathAbs(sweepFractal.price - asianLow);
      bool swept = forSell
         ? (high > asianHigh && sweepFractal.price > 0 && high >= sweepFractal.price)
         : (low < asianLow && sweepFractal.price > 0 && low <= sweepFractal.price);

      if(swept && distAsian <= MaxDistanceFromAsianBox * _Point && distFractal <= MaxDistanceFromAsianBox * _Point)
      {
         state.sweepDetected = true;
         state.sweepFractalTime = sweepFractal.time;
         state.legHigh = forSell ? high : state.legHigh;
         state.legLow  = !forSell ? low : state.legLow;
         if (EnableDebug) Print("🔻 ", side, " SWEEP detected.");
         if (ShowLines) DrawLine("SWEEP_" + side, forSell ? high : low, SweepColor);
      }
      return;
   }

   // 2. BOS detectie
   if (!state.bosConfirmed && state.sweepDetected)
   {
      if (bosFractal.price <= 0.0) return;
      if (bosFractal.time == state.lastEntryBOSTime) return;

      bool bos = false;
      if (forSell)
      {
         if (BOSConfirmType == WickOnly) bos = low < bosFractal.price;
         else if (BOSConfirmType == BodyBreak) bos = close < bosFractal.price;
         else bos = low < bosFractal.price || close < bosFractal.price;
         if (bos) state.legLow = low;
      }
      else
      {
         if (BOSConfirmType == WickOnly) bos = high > bosFractal.price;
         else if (BOSConfirmType == BodyBreak) bos = close > bosFractal.price;
         else bos = high > bosFractal.price || close > bosFractal.price;
         if (bos) state.legHigh = high;
      }

      if (bos)
      {
         state.bosConfirmed = true;
         state.entryTriggered = false; // nieuwe BOS reset entry
         state.bosFractalPrice = forSell ? bosFractal.high : bosFractal.low;
         state.bosFractalTime  = bosFractal.time;
         if (EnableDebug) Print("✅ ", side, " BOS confirmed. Leg High=", state.legHigh, " Low=", state.legLow);
         if (ShowLines) DrawLine("BOS_" + side, forSell ? low : high, BOSColor);
      }
      return;
   }

   // 3. Na BOS: volg leg verder
   if (state.bosConfirmed)
   {
        double price = (forSell ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK));
      if (forSell && price < state.legLow) state.legLow = price;
      if (!forSell && price > state.legHigh) state.legHigh = price;

      double entryPrice = (state.legHigh + state.legLow) / 2.0;
      state.entryPrice = entryPrice;

      // Visuele lijn
      if (ShowLines)
         DrawLine(forSell ? "ENTRY_SELL" : "ENTRY_BUY", entryPrice, EntryLineColor);

      // Als prijs de 50% raakt, plaats MARKET-order
      bool trigger = !state.entryTriggered && (forSell ? (price >= entryPrice) : (price <= entryPrice));
      if (trigger)
      {
         double sl;
         if(forSell)
            sl = state.bosFractalPrice + SLBufferPips * _Point;
         else
            sl = state.bosFractalPrice - SLBufferPips * _Point;
         double tp = forSell ? entryPrice - (sl - entryPrice) * RiskRewardRatio : entryPrice + (entryPrice - sl) * RiskRewardRatio;
         double lot = CalculateLots(MathAbs(entryPrice - sl) / _Point);
         if (lot <= 0.0) return;

         bool sent = forSell
            ? trade.Sell(lot, _Symbol, 0, sl, tp, "ALS_17_SELL")
            : trade.Buy(lot, _Symbol, 0, sl, tp, "ALS_17_BUY");

         if (sent)
         {
            state.entryTriggered = true;
            state.bosConfirmed = false;          // wacht op nieuwe BOS
            state.lastEntryBOSTime = state.bosFractalTime;
            if (EnableDebug)
               Print("📥 ", side, " MARKET order at ", entryPrice, " SL=", sl, " TP=", tp, " Lot=", lot);
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

//+------------------------------------------------------------------+
//| Calculate lot size from a stop price                              |
//+------------------------------------------------------------------+
double CalculateLotsFromPrice(double stopLossPrice,
                              ENUM_ORDER_TYPE orderType,
                              double ask = 0.0,
                              double bid = 0.0)
{
   if(ask == 0.0) ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid == 0.0) bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double slDistance;
   if(orderType == ORDER_TYPE_BUY)
      slDistance = ask - stopLossPrice;
   else if(orderType == ORDER_TYPE_SELL)
      slDistance = stopLossPrice - bid;
   else
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   slDistance = MathAbs(slDistance) + SLBufferPips * _Point;
   double slPips = slDistance / _Point;
   return CalculateLots(slPips);
}

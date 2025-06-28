//+------------------------------------------------------------------+
//|         ALS 1.44 – Market Entry on 50% Leg Touch                 |
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
   bool entryReady;    // price moved beyond entry level, waiting for retrace
   double legHigh;
   double legLow;
   double entryPrice;
   double bosFractalPrice; // price of the fractal that confirmed BOS
   double lockedFractalForSL; // fractal used to place stop loss
   int      tradesCount;
   datetime lastBOSFractalTime;
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
      ObjectsDeleteAll(0, "", 0);
   }

   UpdateAsianSession();
   if (!asianBoxDrawn) return;

   DetectFractals();
   // Re-arm setups when a new opposite fractal appears after a BOS
   if(sellState.entryTriggered &&
      sellState.lastBOSFractalTime > 0 &&
      lastBullFractal.time > 0 &&
      lastBullFractal.time > sellState.lastBOSFractalTime)
   {
      sellState.entryTriggered = false;
      sellState.bosConfirmed = false;
      sellState.entryReady = false;
   }
   if(buyState.entryTriggered &&
      buyState.lastBOSFractalTime > 0 &&
      lastBearFractal.time > 0 &&
      lastBearFractal.time > buyState.lastBOSFractalTime)
   {
      buyState.entryTriggered = false;
      buyState.bosConfirmed = false;
      buyState.entryReady = false;
   }
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

   // 1. Sweep detectie
   if (!state.sweepDetected)
   {
      bool swept = forSell
         ? (high > asianHigh && sweepFractal.price > 0 && high >= sweepFractal.price)
         : (low < asianLow && sweepFractal.price > 0 && low <= sweepFractal.price);

      if (swept)
      {
         state.sweepDetected = true;
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

      // BOS fractal must exist prior to the swept fractal
      if (bosFractal.time > sweepFractal.time)
      {
         if (EnableDebug) Print("\xF0\x9F\x9A\xAB Ongeldige BOS fractal \xE2\x80\x93 tegenovergestelde fractal niet uitgenomen.");
         return;
      }

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
         state.lastBOSFractalTime = bosFractal.time;
         state.tradesCount++;
         // store SL reference from BOS fractal (high for sell, low for buy)
         state.bosFractalPrice = forSell ? bosFractal.high : bosFractal.low;
         // lock fractal for stop loss based on last fractal before BOS
         if(state.lockedFractalForSL == 0.0)
            state.lockedFractalForSL = sweepFractal.price;
         if (EnableDebug) Print("✅ ", side, " BOS confirmed. Leg High=", state.legHigh, " Low=", state.legLow);
         if (ShowLines) DrawLine("BOS_" + side, forSell ? low : high, BOSColor);
      }
      return;
   }

   // 3. Na BOS: volg leg verder
   if (state.bosConfirmed)
   {
      double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double price = forSell ? bid : ask;

      if (forSell && price < state.legLow) state.legLow = price;
      if (!forSell && price > state.legHigh) state.legHigh = price;

      double entryPrice = (state.legHigh + state.legLow) / 2.0;
      state.entryPrice = entryPrice;

      // Visuele lijn
      if (ShowLines)
         DrawLine(forSell ? "ENTRY_SELL" : "ENTRY_BUY", entryPrice, EntryLineColor);

      // Wacht op pullback nadat prijs voorbij de entry-lijn is geweest
      if (!state.entryReady)
      {
         if (forSell && price < entryPrice) state.entryReady = true;
         if (!forSell && price > entryPrice) state.entryReady = true;
      }

      bool trigger = false;
      if (state.entryReady && !state.entryTriggered)
         trigger = forSell ? (bid >= entryPrice) : (ask <= entryPrice);

      if (trigger)
      {
         double midPrice = (asianHigh + asianLow) / 2.0;
         if ((forSell && price < midPrice) || (!forSell && price > midPrice))
         {
            if (EnableDebug) Print("\xF0\x9F\x9A\xAB Entry skipped due to Asian range bias filter");
            state.entryTriggered = true;
            return;
         }

         double sl;
         if(forSell)
            sl = state.lockedFractalForSL + SLBufferPips * _Point;
         else
            sl = state.lockedFractalForSL - SLBufferPips * _Point;
         double tp = forSell ? entryPrice - (sl - entryPrice) * RiskRewardRatio : entryPrice + (entryPrice - sl) * RiskRewardRatio;
         double lot = CalculateLots(MathAbs(entryPrice - sl) / _Point);
         if (lot <= 0.0) return;

         bool sent = forSell
            ? trade.Sell(lot, _Symbol, 0, sl, tp, "ALS_17_SELL")
            : trade.Buy(lot, _Symbol, 0, sl, tp, "ALS_17_BUY");

        if (sent)
        {
           state.entryTriggered = true;
           if (EnableDebug)
              Print("📥 ", side, " MARKET order at ", entryPrice, " SL=", sl, " TP=", tp, " Lot=", lot);
            // state will be re-armed when a new fractal forms
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

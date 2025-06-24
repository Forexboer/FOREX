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

struct FractalPoint { double price; datetime time; };
FractalPoint lastBullFractal, lastBearFractal;
FractalPoint prevBullFractal, prevBearFractal;

struct SetupState
{
   bool sweepDetected;
   bool bosConfirmed;
   bool entryTriggered;
   double slFractal;
   double legHigh;
   double legLow;
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
      ObjectsDeleteAll(0, "", 0);
   }

   UpdateAsianSession();
   if (!asianBoxDrawn) return;

   DetectFractals();
   if (ShowFractals) DrawFractals();

   bool hasPos = HasOpenPosition();
   if(!hasPos)
   {
      if(buyState.entryTriggered) buyState = SetupState();
      if(sellState.entryTriggered) sellState = SetupState();
      RunSetup(false, buyState, lastBullFractal, lastBearFractal, prevBearFractal); // BUY
      RunSetup(true, sellState, lastBearFractal, lastBullFractal, prevBullFractal); // SELL
   }
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
   CopyRates(_Symbol, _Period, 0, 60, rates);

   lastBullFractal = FractalPoint();
   lastBearFractal = FractalPoint();
   prevBullFractal = FractalPoint();
   prevBearFractal = FractalPoint();

   FractalPoint bulls[2];
   int bullCount = 0;
   FractalPoint bears[2];
   int bearCount = 0;

   for (int i = 2; i < ArraySize(rates) - 2 && (bullCount < 2 || bearCount < 2); i++)
   {
      if (bullCount < 2 && rates[i].low < rates[i - 1].low && rates[i].low < rates[i + 1].low)
      {
         bulls[bullCount].price = rates[i].low;
         bulls[bullCount].time  = rates[i].time;
         bullCount++;
      }
      if (bearCount < 2 && rates[i].high > rates[i - 1].high && rates[i].high > rates[i + 1].high)
      {
         bears[bearCount].price = rates[i].high;
         bears[bearCount].time  = rates[i].time;
         bearCount++;
      }
   }

   if (bullCount > 0) lastBullFractal = bulls[0];
   if (bullCount > 1) prevBullFractal = bulls[1];
   if (bearCount > 0) lastBearFractal = bears[0];
   if (bearCount > 1) prevBearFractal = bears[1];

   if (EnableDebug)
      Print("Fractals: Bull=", lastBullFractal.price, " PrevBull=", prevBullFractal.price,
            " Bear=", lastBearFractal.price, " PrevBear=", prevBearFractal.price);
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
void RunSetup(bool forSell, SetupState &state, FractalPoint &sweepFractal, FractalPoint &bosFractal, FractalPoint &prevBosFractal)
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
         state.slFractal = sweepFractal.price;
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

      double bosPrice = bosFractal.price;
      if(prevBosFractal.price > 0)
      {
         if((forSell && bosPrice >= prevBosFractal.price) ||
            (!forSell && bosPrice <= prevBosFractal.price))
            bosPrice = prevBosFractal.price;
      }

      bool bos = false;
      if (forSell)
      {
         if (BOSConfirmType == WickOnly) bos = low < bosPrice;
         else if (BOSConfirmType == BodyBreak) bos = close < bosPrice;
         else bos = low < bosPrice || close < bosPrice;
         if (bos) state.legLow = low;
      }
      else
      {
         if (BOSConfirmType == WickOnly) bos = high > bosPrice;
         else if (BOSConfirmType == BodyBreak) bos = close > bosPrice;
         else bos = high > bosPrice || close > bosPrice;
         if (bos) state.legHigh = high;
      }

      if (bos)
      {
         state.bosConfirmed = true;
         if (EnableDebug) Print("✅ ", side, " BOS confirmed. Leg High=", state.legHigh, " Low=", state.legLow);
         if (ShowLines) DrawLine("BOS_" + side, forSell ? low : high, BOSColor);
      }
      return;
   }

   // 3. Na BOS: volg leg verder
   if (!state.entryTriggered && state.bosConfirmed)
   {
        double price = (forSell ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK));
      if (forSell && price < state.legLow) state.legLow = price;
      if (!forSell && price > state.legHigh) state.legHigh = price;

      double entry = (state.legHigh + state.legLow) / 2.0;
      state.entryPrice = entry;

      // Visuele lijn
      if (ShowLines)
         DrawLine("ENTRY_" + side, entry, EntryLineColor);

      // Als prijs de 50% raakt, plaats MARKET-order
      bool trigger = forSell ? (price >= entry) : (price <= entry);
      if (trigger)
      {
         double sl = forSell ? state.slFractal + SLBufferPips * _Point : state.slFractal - SLBufferPips * _Point;
         double tp = forSell ? entry - (sl - entry) * RiskRewardRatio : entry + (entry - sl) * RiskRewardRatio;
         double lot = CalculateLots(MathAbs(entry - sl) / _Point);
         if (lot <= 0.0) return;

         bool sent = forSell
            ? trade.Sell(lot, _Symbol, 0, sl, tp, "ALS_17_SELL")
            : trade.Buy(lot, _Symbol, 0, sl, tp, "ALS_17_BUY");

         if (sent)
         {
            state.entryTriggered = true;
            if (EnableDebug)
               Print("📥 ", side, " MARKET order at ", entry, " SL=", sl, " TP=", tp, " Lot=", lot);
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

bool HasOpenPosition()
{
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)==MagicNumber &&
         PositionGetString(POSITION_SYMBOL)==_Symbol)
         return true;
   }
   return false;
}

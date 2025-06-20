//+------------------------------------------------------------------+
//|            ALS 1.15 – Asian Liquidity Sweep EA                   |
//|     Copyright 2024, Greaterwaves Coder for MT5 (MQL5)            |
//|     https://www.greaterwaves.com                                 |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

//--- Inputs
sinput group "Session & Risk"
input ulong   MagicNumber             = 777;
input string  AsianSessionStartStr    = "02:00";
input string  AsianSessionEndStr      = "06:00";
input double  RiskPercentPerTrade     = 1.0;
input double  RiskRewardRatio         = 3.0;
input int     SLBufferPips            = 10;
input int     MaxDistanceFromAsianBox = 25;
input int     TP_SL_StopLevelPips     = 10;   // minimum allowed distance between TP and SL

sinput group "Fractals & BOS"
input int     FractalLookback = 3; // bars to look back/forward when detecting fractals
enum ENUM_CONFIRM_TYPE { WickOnly, BodyBreak, Either };
input ENUM_CONFIRM_TYPE SweepConfirmType = WickOnly;
input ENUM_CONFIRM_TYPE BOSConfirmType   = BodyBreak;
sinput group "Entry Settings"
enum ENUM_ENTRY_TYPE { Entry_Stop, Entry_Limit, Entry_Both };
input ENUM_ENTRY_TYPE EntryType      = Entry_Both; // which type of entries to place
input int     EntryOffsetPips        = 2;          // distance beyond BOS for stop orders
input bool    EnableMidLegSellLimit  = true;       // enable 50% pullback limit entry
input int     MinLegSizePips         = 5;          // minimum leg size to allow limit
input int     SellLimitOffsetPips    = 0;          // optional offset from 50% level

sinput group "Fibonacci Entry"
input double  FibEntryLevel = 50.0;  // Only this level will be used
input bool    EnableDynamicPullbackLeg = true;

sinput group "Execution Filters"
input bool    TradeBuySetups   = true;
input bool    TradeSellSetups  = true;
input bool    AddSpreadToEntry = true;
enum ENUM_SPREAD_MODE { Spread_None, Spread_Fixed, Spread_Dynamic };
input ENUM_SPREAD_MODE SpreadAdjustmentType = Spread_Dynamic;
input double  FixedSpreadValue = 2.0;

sinput group "Visual Settings"
input bool  ShowAsianBox          = true;
input color AsianBoxColor         = clrAqua;
input bool  ShowFib               = true;
input bool  ShowSweepLines        = true;
input bool  ShowBOSLines          = true;
input bool  ShowFractalsOnChart   = true;
input color FractalBullColor      = clrBlue;
input color FractalBearColor      = clrOrange;
input color SweepColor            = clrRed;
input color BOSColor              = clrLime;
input color FibLineColor          = clrYellow;

sinput group "ZigZag Settings"
input bool  UseZigZag       = true;
input int   ZigZagDepth     = 12;
input int   ZigZagDeviation = 5;
input int   ZigZagBackstep  = 3;

sinput group "Debugging"
input bool EnableDebug = true;

//--- Globals
CTrade trade;
datetime glTimeBarOpen;
datetime asianStartTime, asianEndTime;
double asianHigh = 0.0, asianLow = 0.0;
bool asianSessionRecorded = false;
int glLastProcessedDay = -1;
int zigzagHandle = INVALID_HANDLE;

struct FractalPoint { int index; double price; datetime time; };
FractalPoint lastBearishFractal, lastBullishFractal;

struct SetupState
{
   bool sweepDetected;
   bool bosConfirmed;
   bool fibLocked;
   bool allowLegAdjust;
   bool stopLocked;
   ulong orderTicket;
   ulong stopTicket;
   double fibHigh;
   double fibLow;
   double bosPrice;
   string label;
};
SetupState buyState, sellState;

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(30);
   glTimeBarOpen = D'1970.01.01 00:00';
   ObjectsDeleteAll(0, "", 0);
   if (UseZigZag)
   {
      zigzagHandle = iCustom(_Symbol, _Period, "Examples\\ZigZag", ZigZagDepth, ZigZagDeviation, ZigZagBackstep);
      if (zigzagHandle != INVALID_HANDLE)
         ChartIndicatorAdd(0,0,zigzagHandle);
   }
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason)
{
   if (zigzagHandle != INVALID_HANDLE)
      IndicatorRelease(zigzagHandle);
   ObjectsDeleteAll(0, "", 0);
}

//+------------------------------------------------------------------+
//| OnTick Handler                                                   |
//+------------------------------------------------------------------+
void OnTick()
{
   if (glTimeBarOpen == iTime(_Symbol, _Period, 0))
      return;
   glTimeBarOpen = iTime(_Symbol, _Period, 0);

   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if (glLastProcessedDay != dt.day)
   {
      glLastProcessedDay = dt.day;
      asianSessionRecorded = false;
      buyState = SetupState();  buyState.label = "BUY";
      sellState = SetupState(); sellState.label = "SELL";
      ObjectsDeleteAll(0, "", 0);
   }

   UpdateAsianSessionTimes();

   if (!asianSessionRecorded && TimeCurrent() >= asianEndTime)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(_Symbol, _Period, asianStartTime, asianEndTime, rates);

      if (copied >= 2)
      {
         asianHigh = rates[0].high;
         asianLow  = rates[0].low;
         for (int i = 1; i < copied; i++)
         {
            if (rates[i].high > asianHigh) asianHigh = rates[i].high;
            if (rates[i].low  < asianLow ) asianLow  = rates[i].low;
         }

         if (asianHigh == asianLow)
         {
            if (EnableDebug) Print("❌ Invalid Asian range: High == Low == ", asianHigh);
            return;
         }

         asianSessionRecorded = true;
         if (EnableDebug)
            Print("✅ Asian Session High: ", asianHigh, " Low: ", asianLow);

         if (ShowAsianBox)
            DrawAsianBox();
      }
      else if (EnableDebug)
         Print("❌ Not enough bars to calculate Asian session.");
   }

   if (!asianSessionRecorded) return;

   DetectFractals();
   if (ShowFractalsOnChart) DrawFractals();

   if (TradeBuySetups)
      RunSetup(false, buyState, lastBullishFractal, lastBearishFractal);
   if (TradeSellSetups)
      RunSetup(true, sellState, lastBearishFractal, lastBullishFractal);
}

//+------------------------------------------------------------------+
//| Asian Time Parser                                                |
//+------------------------------------------------------------------+
void UpdateAsianSessionTimes()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   string d = StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day);
   asianStartTime = StringToTime(d + " " + AsianSessionStartStr);
   asianEndTime   = StringToTime(d + " " + AsianSessionEndStr);
}

//+------------------------------------------------------------------+
//| Detect Fractals                                                  |
//+------------------------------------------------------------------+
void DetectFractals()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   CopyRates(_Symbol, _Period, 0, 50, rates);

   lastBearishFractal = FractalPoint();
   lastBullishFractal = FractalPoint();

   int total = ArraySize(rates);
   for (int i = FractalLookback; i < total - FractalLookback; i++)
   {
      bool bear = true, bull = true;
      for (int j = 1; j <= FractalLookback; j++)
      {
         if (bear && (rates[i].high <= rates[i - j].high || rates[i].high <= rates[i + j].high))
            bear = false;
         if (bull && (rates[i].low >= rates[i - j].low || rates[i].low >= rates[i + j].low))
            bull = false;
         if (!bear && !bull)
            break;
      }

      if (bear && lastBearishFractal.time == 0)
      {
         lastBearishFractal.index = i;
         lastBearishFractal.price = rates[i].high;
         lastBearishFractal.time  = rates[i].time;
      }

      if (bull && lastBullishFractal.time == 0)
      {
         lastBullishFractal.index = i;
         lastBullishFractal.price = rates[i].low;
         lastBullishFractal.time  = rates[i].time;
      }

      if (lastBearishFractal.time != 0 && lastBullishFractal.time != 0)
         break;
   }
}
//+------------------------------------------------------------------+
//| Run Setup                                                        |
//+------------------------------------------------------------------+
void RunSetup(bool forSell, SetupState &state, FractalPoint &sweepFractal, FractalPoint &bosFractal)
{
   string prefix = state.label;
   double high = iHigh(_Symbol, _Period, 1);
   double low  = iLow(_Symbol, _Period, 1);
   double close = iClose(_Symbol, _Period, 1);

   if (!state.sweepDetected)
   {
      bool swept = forSell
         ? (high > asianHigh && high >= sweepFractal.price)
         : (low < asianLow && low <= sweepFractal.price);

      if (swept)
      {
         state.sweepDetected = true;
         state.fibHigh = forSell ? high : state.fibHigh;
         state.fibLow  = !forSell ? low : state.fibLow;
         if (EnableDebug) Print(prefix, " sweep detected at ", (forSell ? high : low));
         if (ShowSweepLines)
            DrawHorizontalLine("SWEEP_" + prefix, forSell ? high : low, SweepColor);
      }
   }

   if (state.sweepDetected && !state.bosConfirmed)
   {
      if (bosFractal.price == 0.0) return;

      bool bos = false;
      if (forSell)
      {
         if (BOSConfirmType == WickOnly) bos = low < bosFractal.price;
         else if (BOSConfirmType == BodyBreak) bos = close < bosFractal.price;
         else bos = low < bosFractal.price || close < bosFractal.price;
         if (bos) state.fibLow = low;
      }
      else
      {
         if (BOSConfirmType == WickOnly) bos = high > bosFractal.price;
         else if (BOSConfirmType == BodyBreak) bos = close > bosFractal.price;
         else bos = high > bosFractal.price || close > bosFractal.price;
         if (bos) state.fibHigh = high;
      }

      if (bos)
      {
         state.bosConfirmed = true;
         state.bosPrice = forSell ? low : high;
         if (EnableDebug)
         {
            Print(prefix, " BOS confirmed at ", (forSell ? low : high));
            Print("Fib Range → High: ", state.fibHigh, " Low: ", state.fibLow);
         }

         if (ShowBOSLines)
            DrawHorizontalLine("BOS_" + prefix, forSell ? low : high, BOSColor);
      }
   }

   if (state.bosConfirmed && !state.stopLocked && (EntryType==Entry_Stop || EntryType==Entry_Both))
   {
      if (state.stopTicket > 0 && !OrderSelect(state.stopTicket))
      {
         state.stopLocked = true;
         state.stopTicket = 0;
      }

      if (!state.stopLocked && state.stopTicket == 0)
      {
         double stopEntry = forSell
            ? state.bosPrice - EntryOffsetPips * _Point
            : state.bosPrice + EntryOffsetPips * _Point;

         double sl = forSell ? state.fibHigh + SLBufferPips * _Point
                              : state.fibLow - SLBufferPips * _Point;
         double tp = forSell
            ? stopEntry - (sl - stopEntry) * RiskRewardRatio
            : stopEntry + (stopEntry - sl) * RiskRewardRatio;

         long stoplevel = 0;
         SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL, stoplevel);
         double minDistPoints = (double)stoplevel * _Point;

         if (MathAbs(stopEntry - sl) >= minDistPoints && MathAbs(stopEntry - tp) >= minDistPoints)
         {
            double stopPips = MathAbs(sl - stopEntry) / _Point;
            double lot = CalculateLots(stopPips);
            if (lot > 0.0)
            {
               bool placed = forSell
                  ? trade.SellStop(lot, stopEntry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "ALS_SELL_STOP")
                  : trade.BuyStop(lot, stopEntry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "ALS_BUY_STOP");
               if (placed)
               {
                  state.stopTicket = trade.ResultOrder();
               }
            }
         }
      }
   }

   if (state.bosConfirmed && !state.fibLocked && (EntryType==Entry_Limit || EntryType==Entry_Both) && EnableMidLegSellLimit)
   {
      if (state.orderTicket > 0 && !OrderSelect(state.orderTicket))
      {
         state.fibLocked = true;
         state.allowLegAdjust = false;
         state.orderTicket = 0;
         return;
      }

      if (EnableDynamicPullbackLeg && state.allowLegAdjust)
      {
         if (forSell && high > state.fibHigh)  state.fibHigh = high;
         if (!forSell && low < state.fibLow)   state.fibLow  = low;
      }

      double fibPrice = state.fibHigh - (state.fibHigh - state.fibLow) * (FibEntryLevel / 100.0);
      double legSize = forSell
         ? MathAbs(state.fibHigh - state.bosPrice) / _Point
         : MathAbs(state.bosPrice - state.fibLow) / _Point;
      if (legSize < MinLegSizePips)
         return;

      fibPrice += (forSell ? -SellLimitOffsetPips : SellLimitOffsetPips) * _Point;
      double sl = forSell ? state.fibHigh + SLBufferPips * _Point : state.fibLow - SLBufferPips * _Point;
      double tp = forSell
         ? fibPrice - (sl - fibPrice) * RiskRewardRatio
         : fibPrice + (fibPrice - sl) * RiskRewardRatio;

      double spreadAdjust = 0.0;
      if (AddSpreadToEntry)
      {
         if (SpreadAdjustmentType == Spread_Fixed)
            spreadAdjust = FixedSpreadValue * _Point;
         else if (SpreadAdjustmentType == Spread_Dynamic)
         {
            long spread = 0;
            SymbolInfoInteger(_Symbol, SYMBOL_SPREAD, spread);
            spreadAdjust = spread * _Point;
         }
         // Spread_None results in no adjustment
      }

      fibPrice += (forSell ? spreadAdjust : -spreadAdjust);

      double dist = MathAbs(fibPrice - (forSell ? asianHigh : asianLow)) / _Point;
      if (dist > MaxDistanceFromAsianBox) return;

      //--- Ensure stop distances respect broker limits
      long stoplevel = 0;
      SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL, stoplevel);
      double minDistPoints = (double)stoplevel * _Point;

      if (MathAbs(fibPrice - sl) < minDistPoints || MathAbs(fibPrice - tp) < minDistPoints)
      {
         if (EnableDebug) Print("❌ ", prefix, " entry skipped: stop distances below broker stoplevel");
         return;
      }

      //--- Ensure TP and SL have sufficient distance between them
      double sltpDistance = MathAbs(tp - sl) / _Point;
      if (sltpDistance < TP_SL_StopLevelPips)
      {
         if (EnableDebug) Print("❌ ", prefix, " entry skipped: TP-SL distance ", sltpDistance, " < ", TP_SL_StopLevelPips);
         return;
      }

      double stopPips = MathAbs(sl - fibPrice) / _Point;
      double lot = CalculateLots(stopPips);
      if (lot <= 0.0)
      {
         if (EnableDebug) Print("❌ ", prefix, " entry skipped: Lot size = 0");
         return;
      }

      if (EnableDebug)
      {
         Print("📐 ", prefix, " Entry = ", fibPrice, " | SL = ", sl, " | TP = ", tp, " | Lot = ", lot);
      }

      if (state.orderTicket > 0)
         trade.OrderDelete(state.orderTicket);

      bool placed = forSell
         ? trade.SellLimit(lot, fibPrice, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "ALS_SELL")
         : trade.BuyLimit(lot, fibPrice, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "ALS_BUY");

      if (placed)
      {
         state.orderTicket = trade.ResultOrder();
         if (ShowFib)
            DrawHorizontalLine("FIB_" + prefix, fibPrice, FibLineColor);
         state.allowLegAdjust = EnableDynamicPullbackLeg;
         if (!EnableDynamicPullbackLeg)
            state.fibLocked = true;
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate Lot Size with Fallback                                 |
//+------------------------------------------------------------------+
double CalculateLots(double slPips)
{
   double accBal = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk = accBal * RiskPercentPerTrade / 100.0;

   double tickVal = 0.0, tickSize = 0.0;
   SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE, tickVal);
   SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE, tickSize);

   if (tickVal <= 0 || tickSize <= 0)
   {
      if (EnableDebug) Print("⚠️ Tick values invalid -> fallback to min lot (0.01)");
      return 0.01;
   }

   double slPrice = slPips * _Point;
   double perLotLoss = (slPrice / tickSize) * tickVal;
   if (perLotLoss <= 0.0) return 0.01;

   double rawLots = risk / perLotLoss;
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   double lots = MathFloor(rawLots / step) * step;
   lots = NormalizeDouble(lots, 2);

   if (lots < min) return min;
   if (lots > max) return max;

   return lots;
}

//+------------------------------------------------------------------+
//| Drawing Helpers                                                  |
//+------------------------------------------------------------------+
void DrawHorizontalLine(string name, double price, color clr)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_HLINE, 0, TimeCurrent(), price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
}

void DrawFractals()
{
   if (lastBullishFractal.price > 0.0)
      DrawHorizontalLine("BullFractal", lastBullishFractal.price, FractalBullColor);
   if (lastBearishFractal.price > 0.0)
      DrawHorizontalLine("BearFractal", lastBearishFractal.price, FractalBearColor);
}

void DrawAsianBox()
{
   ObjectDelete(0, "ASIAN_BOX");
   ObjectCreate(0, "ASIAN_BOX", OBJ_RECTANGLE, 0, asianStartTime, asianHigh, asianEndTime, asianLow);
   ObjectSetInteger(0, "ASIAN_BOX", OBJPROP_COLOR, AsianBoxColor);
   ObjectSetInteger(0, "ASIAN_BOX", OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, "ASIAN_BOX", OBJPROP_BACK, true);
}

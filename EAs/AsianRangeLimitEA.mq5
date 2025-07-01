//+------------------------------------------------------------------+
//| Asian Range Fractal Limit Entry EA                               |
//| Implements trading logic based on an Asian session sweep,        |
//| fractal BOS confirmation and 50% limit order entry.              |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

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
datetime asianStart, asianEnd;
double asianHigh=0.0, asianLow=0.0;
bool   asianBoxDrawn=false;
int    tradesToday=0;
int    lastProcessedDay=-1;

double dailyHigh=0.0, dailyLow=0.0;

struct FractalPoint
{
   double price;
   double high;
   double low;
   datetime time;
};
FractalPoint lastBullFractal,lastBearFractal;

struct SetupState
{
   bool    sweepDetected;
   bool    bosConfirmed;
   bool    orderPlaced;
   ulong   ticket;
   double  entryPrice;
   double  bosFractalPrice;
};
SetupState buyState,sellState;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   ObjectsDeleteAll(0,"",0);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0,"",0);
}

//+------------------------------------------------------------------+
void OnTick()
{
   MqlDateTime cur; TimeToStruct(TimeCurrent(),cur);
   if(cur.day!=lastProcessedDay)
   {
      lastProcessedDay=cur.day;
      asianBoxDrawn=false;
      tradesToday=0;
      buyState=SetupState();
      sellState=SetupState();
      dailyHigh=0.0; dailyLow=0.0;
      ObjectsDeleteAll(0,"",0);
   }

   UpdateAsianSession();
   if(!asianBoxDrawn) return;

   double h=iHigh(_Symbol,_Period,0);
   double l=iLow(_Symbol,_Period,0);
   if(h>dailyHigh) dailyHigh=h;
   if(l<dailyLow || dailyLow==0.0) dailyLow=l;

   DetectFractals();
   if(ShowFractals) DrawFractals();

   RunSetup(false,buyState,lastBullFractal,lastBearFractal); //BUY
   RunSetup(true,sellState,lastBearFractal,lastBullFractal); //SELL
}

//+------------------------------------------------------------------+
void UpdateAsianSession()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   string dateStr=StringFormat("%04d.%02d.%02d",dt.year,dt.mon,dt.day);
   asianStart=StringToTime(dateStr+" "+AsianSessionStartStr);
   asianEnd  =StringToTime(dateStr+" "+AsianSessionEndStr);
   if(TimeCurrent()<asianEnd || asianBoxDrawn) return;

   MqlRates rates[]; ArraySetAsSeries(rates,true);
   int copied=CopyRates(_Symbol,_Period,asianStart,asianEnd,rates);
   if(copied<2) return;

   asianHigh=rates[0].high; asianLow=rates[0].low;
   for(int i=1;i<copied;i++)
   {
      if(rates[i].high>asianHigh) asianHigh=rates[i].high;
      if(rates[i].low<asianLow)   asianLow=rates[i].low;
   }
   if(ShowAsianBox)
   {
      ObjectDelete(0,"ASIAN_BOX");
      ObjectCreate(0,"ASIAN_BOX",OBJ_RECTANGLE,0,asianStart,asianHigh,asianEnd,asianLow);
      ObjectSetInteger(0,"ASIAN_BOX",OBJPROP_COLOR,AsianBoxColor);
      ObjectSetInteger(0,"ASIAN_BOX",OBJPROP_BACK,true);
   }
   dailyHigh=asianHigh; dailyLow=asianLow;
   asianBoxDrawn=true;
   if(EnableDebug) Print("Asian Box: ",asianHigh," - ",asianLow);
}

//+------------------------------------------------------------------+
void DetectFractals()
{
   MqlRates rates[]; ArraySetAsSeries(rates,true);
   CopyRates(_Symbol,_Period,0,50,rates);

   lastBullFractal=FractalPoint();
   lastBearFractal=FractalPoint();

   int total=ArraySize(rates);
   for(int i=FractalLookback;i<total-FractalLookback;i++)
   {
      bool bull=true;
      for(int j=1;j<=FractalLookback;j++)
         if(rates[i].low>=rates[i-j].low || rates[i].low>=rates[i+j].low) { bull=false; break; }
      if(bull && rates[i].low<dailyLow)
      {
         lastBullFractal.price=rates[i].low;
         lastBullFractal.high=rates[i].high;
         lastBullFractal.low =rates[i].low;
         lastBullFractal.time=rates[i].time;
         break;
      }
   }
   for(int i=FractalLookback;i<total-FractalLookback;i++)
   {
      bool bear=true;
      for(int j=1;j<=FractalLookback;j++)
         if(rates[i].high<=rates[i-j].high || rates[i].high<=rates[i+j].high) { bear=false; break; }
      if(bear && rates[i].high>dailyHigh)
      {
         lastBearFractal.price=rates[i].high;
         lastBearFractal.high=rates[i].high;
         lastBearFractal.low =rates[i].low;
         lastBearFractal.time=rates[i].time;
         break;
      }
   }
}

//+------------------------------------------------------------------+
void DrawFractals()
{
   if(lastBullFractal.price>0.0)
      DrawArrow("BullFractal",lastBullFractal.time,lastBullFractal.price,FractalBullColor,241);
   if(lastBearFractal.price>0.0)
      DrawArrow("BearFractal",lastBearFractal.time,lastBearFractal.price,FractalBearColor,242);
}

void DrawArrow(string name, datetime t,double p,color clr,int code)
{
   ObjectDelete(0,name);
   ObjectCreate(0,name,OBJ_ARROW,0,t,p);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_ARROWCODE,code);
}

void DrawLine(string name,double price,color clr)
{
   ObjectDelete(0,name);
   ObjectCreate(0,name,OBJ_HLINE,0,TimeCurrent(),price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
}

//+------------------------------------------------------------------+
void RunSetup(bool forSell,SetupState &state,FractalPoint &sweepFractal,FractalPoint &bosFractal)
{
   string side=forSell?"SELL":"BUY";
   if(tradesToday>=MaxTradesPerDay) return;

   double high=iHigh(_Symbol,_Period,0);
   double low =iLow(_Symbol,_Period,0);
   double close=iClose(_Symbol,_Period,0);

   // sweep detection
   if(!state.sweepDetected)
   {
      bool swept=forSell? (high>asianHigh && sweepFractal.price>0 && high>=sweepFractal.price)
                        : (low<asianLow && sweepFractal.price>0 && low<=sweepFractal.price);
      if(swept)
      {
         state.sweepDetected=true;
         if(ShowLines) DrawLine("SWEEP_"+side,forSell?high:low,SweepColor);
         if(EnableDebug) Print(side," sweep detected");
      }
      return;
   }

   // BOS detection
   if(!state.bosConfirmed)
   {
      if(bosFractal.price<=0.0) return;
      bool bos=false;
      if(forSell)
      {
         if(BOSConfirmType==WickOnly) bos=low<bosFractal.price;
         else if(BOSConfirmType==BodyBreak) bos=close<bosFractal.price;
         else bos=(low<bosFractal.price || close<bosFractal.price);
      }
      else
      {
         if(BOSConfirmType==WickOnly) bos=high>bosFractal.price;
         else if(BOSConfirmType==BodyBreak) bos=close>bosFractal.price;
         else bos=(high>bosFractal.price || close>bosFractal.price);
      }
      if(bos)
      {
         state.bosConfirmed=true;
         state.bosFractalPrice=forSell?bosFractal.high:bosFractal.low;
         double legLow = forSell? low : bosFractal.low;
         double legHigh= forSell? bosFractal.high : high;
         state.entryPrice=(legHigh+legLow)/2.0;
         if(ShowLines) DrawLine("BOS_"+side,forSell?low:high,BOSColor);
         PlaceLimitOrder(forSell,state,side);
         if(EnableDebug) Print(side," BOS confirmed. Entry=",state.entryPrice);
      }
      return;
   }

   // after BOS - pending order active, no further updates
}

//+------------------------------------------------------------------+
void PlaceLimitOrder(bool forSell,SetupState &state,string side)
{
   double entry=state.entryPrice;
   if(MaxDistanceFromAsianBox>0)
   {
      double dist=forSell? ((entry>asianHigh)?(entry-asianHigh)/_Point:0)
                         : ((entry<asianLow)?(asianLow-entry)/_Point:0);
      if(dist>MaxDistanceFromAsianBox)
      {
         if(EnableDebug) Print(side," entry too far from Asian range" );
         state=SetupState();
         return;
      }
   }

   double sl=forSell? state.bosFractalPrice + SLBufferPips*_Point
                    : state.bosFractalPrice - SLBufferPips*_Point;
   double risk=MathAbs(entry-sl);
   double tp=forSell? entry - risk*RiskRewardRatio
                    : entry + risk*RiskRewardRatio;
   double lots=CalculateLots(risk/_Point);
   if(lots<=0.0) return;

   bool sent=forSell?
      trade.SellLimit(lots,_Symbol,entry,sl,tp,ORDER_TIME_GTC,0,"ASIAN_SELL"):
      trade.BuyLimit(lots,_Symbol,entry,sl,tp,ORDER_TIME_GTC,0,"ASIAN_BUY");
   if(sent)
   {
      state.orderPlaced=true;
      state.ticket=trade.ResultOrder();
      tradesToday++;
      if(ShowLines) DrawLine("ENTRY_"+(forSell?"SELL":"BUY"),entry,EntryLineColor);
      if(EnableDebug) Print("Limit order placed ",side," ",entry);
   }
}

//+------------------------------------------------------------------+
double CalculateLots(double slPips)
{
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double risk=bal*RiskPercentPerTrade/100.0;
   double tickVal=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(tickVal<=0.0||tickSize<=0.0) return 0.01;
   double sl=slPips*point;
   double lossPerLot=(sl/tickSize)*tickVal;
   if(lossPerLot<=0.0) return 0.01;
   double raw=risk/lossPerLot;
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double lots=MathFloor(raw/step)*step;
   lots=MathMax(minLot,MathMin(maxLot,lots));
   return NormalizeDouble(lots,2);
}



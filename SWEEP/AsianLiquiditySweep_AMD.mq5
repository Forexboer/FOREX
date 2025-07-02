//+------------------------------------------------------------------+
//| Asian Liquidity Sweep – AMD Model EA                           |
//| Example implementation for MetaTrader 5                          |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

//--- input parameters
sinput group "General Strategy"
input ulong   MagicNumber             = 1701;          // magic number
input string  AsianSessionStart       = "03:00";      // Asian range start
input string  AsianSessionEnd         = "07:00";      // Asian range end
input bool    ConfirmSweepWithFractal = true;          // require fractal sweep
input int     FractalLookback         = 3;             // bars for fractal
enum ENUM_BOS_CONFIRM { WickOnly, BodyBreak };
input ENUM_BOS_CONFIRM BOSConfirmationType = WickOnly; // BOS confirmation type
input bool    UseDynamic50Percent     = true;          // adaptive entry
input bool    InvalidateOnNewSweep    = true;          // reset on new sweep
input bool    UseDailyHighLowSL       = true;          // SL from daily extremes
input string  DailyExtStart           = "07:00";      // start time for extremes
input string  DailyExtEnd             = "23:59";      // end time for extremes
input bool    UseTakeProfit           = true;          // place TP
input double  RiskRewardRatio         = 3.0;           // RR ratio
input bool    TradeBuySetups          = true;          // enable buys
input bool    TradeSellSetups         = true;          // enable sells
enum ENUM_ENTRY_TYPE { Market, Limit };
input ENUM_ENTRY_TYPE EntryOrderType  = Limit;         // entry order type

sinput group "Risk Management"
enum ENUM_LOT_MODE { Fixed, PercentBalance };
input ENUM_LOT_MODE LotSizingMode     = PercentBalance;// lot sizing mode
input double FixedLotSize             = 0.10;          // fixed lot size
input double RiskPercentPerTrade      = 1.0;           // risk per trade
input int     Slippage                = 3;             // slippage

//--- global variables
CTrade trade;
datetime asianStart, asianEnd;
double   asianHigh=0, asianLow=0;
bool     asianBoxDrawn=false;

struct FractalPoint
{
   double high;
   double low;
   datetime time;
};

enum SETUP_STATUS { NONE, WAIT_BOS, BOS_TRIGGERED };
struct Setup
{
   bool      isSell;
   SETUP_STATUS status;
   FractalPoint sweep;
   FractalPoint bos;
   double    entry50;
   double    sl;
   double    tp;
   ulong     ticket;
};
Setup current;
datetime lastBarTime=0;
datetime dailyExtStartTime, dailyExtEndTime;
double dailyHigh=0, dailyLow=0;
string  asianBoxName="";
string  sweepArrowName="";
string  bosArrowName="";

void DrawArrow(string name, datetime t, double price, color clr, int code)
{
   ObjectDelete(0,name);
   ObjectCreate(0,name,OBJ_ARROW,0,t,price);
   ObjectSetInteger(0,name,OBJPROP_ARROWCODE,code);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
}

void DeleteNonBoxObjects()
{
   int total=ObjectsTotal(0,-1,-1);
   for(int i=total-1;i>=0;i--)
   {
      string nm=ObjectName(0,i);
      if(StringFind(nm,"ASIAN_BOX_")==0) continue;
      ObjectDelete(0,nm);
   }
}

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   DeleteNonBoxObjects();
   current.status = NONE;
   current.ticket = 0;
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   DeleteNonBoxObjects();
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime barTime=iTime(_Symbol,_Period,0);
   if(barTime!=lastBarTime)
   {
      lastBarTime=barTime;
      ProcessNewBar();
   }

   if(!asianBoxDrawn)
      return;

   UpdateDailyExtremes();
   ManageSetup();
}

//+------------------------------------------------------------------+
void ProcessNewBar()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   string dateStr=StringFormat("%04d.%02d.%02d",dt.year,dt.mon,dt.day);

   // reset on new day
   static int storedDay=-1;
   if(storedDay!=dt.day)
   {
      storedDay=dt.day;
      asianBoxDrawn=false;
      current.status=NONE;
      DeleteNonBoxObjects();
      sweepArrowName="";
      bosArrowName="";
      current.ticket=0;
      asianHigh=0; asianLow=0;
      dailyHigh=0; dailyLow=0;
      dailyExtStartTime=StringToTime(dateStr+" "+DailyExtStart);
      dailyExtEndTime=StringToTime(dateStr+" "+DailyExtEnd);
   }

   UpdateAsianRange();

   if(!asianBoxDrawn)
      return;

   DetectSweep();
}

//+------------------------------------------------------------------+
void UpdateAsianRange()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   string dateStr=StringFormat("%04d.%02d.%02d",dt.year,dt.mon,dt.day);
   asianStart=StringToTime(dateStr+" "+AsianSessionStart);
   asianEnd  =StringToTime(dateStr+" "+AsianSessionEnd);

   if(TimeCurrent()<asianEnd || asianBoxDrawn)
      return;

   MqlRates rates[]; ArraySetAsSeries(rates,true);
   int copied=CopyRates(_Symbol,_Period,asianStart,asianEnd,rates);
   if(copied<2) return;

   asianHigh=rates[0].high;
   asianLow =rates[0].low;
   for(int i=1;i<copied;i++)
   {
      if(rates[i].high>asianHigh) asianHigh=rates[i].high;
      if(rates[i].low <asianLow)  asianLow =rates[i].low;
   }

   asianBoxName=StringFormat("ASIAN_BOX_%04d%02d%02d",dt.year,dt.mon,dt.day);
   ObjectCreate(0,asianBoxName,OBJ_RECTANGLE,0,asianStart,asianHigh,asianEnd,asianLow);
   ObjectSetInteger(0,asianBoxName,OBJPROP_COLOR,clrAqua);
   ObjectSetInteger(0,asianBoxName,OBJPROP_BACK,true);
   asianBoxDrawn=true;

   dailyHigh=asianHigh;
   dailyLow =asianLow;
   Print("✅ Asian Box: High=",DoubleToString(asianHigh,_Digits)," Low=",DoubleToString(asianLow,_Digits));
}

//+------------------------------------------------------------------+
void UpdateDailyExtremes()
{
   if(TimeCurrent()<dailyExtStartTime || TimeCurrent()>dailyExtEndTime)
      return;

   double h=iHigh(_Symbol,_Period,0);
   double l=iLow(_Symbol,_Period,0);
   if(h>dailyHigh) dailyHigh=h;
   if(l<dailyLow)  dailyLow=l;
}

//+------------------------------------------------------------------+
void DetectSweep()
{
   if(current.status!=NONE && !InvalidateOnNewSweep)
      return;

   if(current.status!=NONE && InvalidateOnNewSweep)
   {
      if(sweepArrowName!="") ObjectDelete(0,sweepArrowName);
      if(bosArrowName!="") { ObjectDelete(0,bosArrowName); bosArrowName=""; }
      Print("Previous setup invalidated by new sweep fractal.");
   }

   MqlRates r[]; ArraySetAsSeries(r,true);
   if(CopyRates(_Symbol,_Period,0,3,r)!=3) return;

   // check previous completed bar for fractal
   double h1=r[1].high, h0=r[0].high, h2=r[2].high;
   double l1=r[1].low,  l0=r[0].low,  l2=r[2].low;

   bool bearFractal=(h1>h0 && h1>h2);
   bool bullFractal=(l1<l0 && l1<l2);

   if(TradeSellSetups && bearFractal && h1>=asianHigh+_Point)
   {
      current.isSell=true;
      current.status=WAIT_BOS;
      current.sweep.high=h1;
      current.sweep.low =l1;
      current.sweep.time=r[1].time;
      current.bos.time=0;
      MqlDateTime t; TimeToStruct(r[1].time,t);
      sweepArrowName=StringFormat("SWEEP_FRCT_%04d%02d%02d_%02d%02d",t.year,t.mon,t.day,t.hour,t.min);
      DrawArrow(sweepArrowName,r[1].time,h1,clrRed,242);
      Print("Sweep fractal detected SELL @",DoubleToString(h1,_Digits));
   }
   else if(TradeBuySetups && bullFractal && l1<=asianLow-_Point)
   {
      current.isSell=false;
      current.status=WAIT_BOS;
      current.sweep.high=h1;
      current.sweep.low =l1;
      current.sweep.time=r[1].time;
      current.bos.time=0;
      MqlDateTime t; TimeToStruct(r[1].time,t);
      sweepArrowName=StringFormat("SWEEP_FRCT_%04d%02d%02d_%02d%02d",t.year,t.mon,t.day,t.hour,t.min);
      DrawArrow(sweepArrowName,r[1].time,l1,clrGreen,241);
      Print("Sweep fractal detected BUY @",DoubleToString(l1,_Digits));
   }
}

//+------------------------------------------------------------------+
void ManageSetup()
{
   if(current.status==NONE)
      return;

   if(current.status==WAIT_BOS)
   {
      TrackLeg();
      CheckBOS();
   }
   else if(current.status==BOS_TRIGGERED)
   {
      PlaceOrder();
   }
}

//+------------------------------------------------------------------+
void TrackLeg()
{
   // update extremes for dynamic entry
   double h=iHigh(_Symbol,_Period,0);
   double l=iLow(_Symbol,_Period,0);
   if(current.isSell)
   {
      if(h>current.sweep.high) current.sweep.high=h;
   }
   else
   {
      if(l<current.sweep.low) current.sweep.low=l;
   }

   // update entry if BOS fractal known
   if(current.bos.time>0)
   {
      if(current.isSell)
         current.entry50=(current.sweep.high+current.bos.low)/2.0;
      else
         current.entry50=(current.sweep.low+current.bos.high)/2.0;
   }
}

//+------------------------------------------------------------------+
void CheckBOS()
{
   // find opposite fractal after sweep
   MqlRates r[]; ArraySetAsSeries(r,true);
   if(CopyRates(_Symbol,_Period,0,3,r)!=3) return;

   double h1=r[1].high, h0=r[0].high, h2=r[2].high;
   double l1=r[1].low,  l0=r[0].low,  l2=r[2].low;
   bool bear=(h1>h0 && h1>h2);
   bool bull=(l1<l0 && l1<l2);

   if(current.isSell && bull && l1>current.sweep.low && current.bos.time==0)
   {
      current.bos.high=h1; current.bos.low=l1; current.bos.time=r[1].time;
      current.entry50=(current.sweep.high+current.bos.low)/2.0;
      MqlDateTime b; TimeToStruct(r[1].time,b);
      bosArrowName=StringFormat("BOS_FRCT_%04d%02d%02d_%02d%02d",b.year,b.mon,b.day,b.hour,b.min);
      DrawArrow(bosArrowName,r[1].time,l1,clrGreen,241);
      Print("BOS fractal found: high=",DoubleToString(h1,_Digits)," low=",DoubleToString(l1,_Digits));
      return;
   }
   if(!current.isSell && bear && h1<current.sweep.high && current.bos.time==0)
   {
      current.bos.high=h1; current.bos.low=l1; current.bos.time=r[1].time;
      current.entry50=(current.sweep.low+current.bos.high)/2.0;
      MqlDateTime b; TimeToStruct(r[1].time,b);
      bosArrowName=StringFormat("BOS_FRCT_%04d%02d%02d_%02d%02d",b.year,b.mon,b.day,b.hour,b.min);
      DrawArrow(bosArrowName,r[1].time,h1,clrRed,242);
      Print("BOS fractal found: high=",DoubleToString(h1,_Digits)," low=",DoubleToString(l1,_Digits));
      return;
   }

   if(current.bos.time==0) return;

   // check break of structure
   bool broken=false;
   if(current.isSell)
   {
      if(l1<=current.bos.low-_Point)
      {
         if(BOSConfirmationType==BodyBreak)
            broken=(r[1].close<current.bos.low);
         else
            broken=true;
      }
   }
   else
   {
      if(h1>=current.bos.high+_Point)
      {
         if(BOSConfirmationType==BodyBreak)
            broken=(r[1].close>current.bos.high);
         else
            broken=true;
      }
   }

   if(broken)
   {
      Print("Price broke ",current.isSell?"below":"above"," BOS fractal -> BOS triggered");
      current.status=BOS_TRIGGERED;
   }
}

//+------------------------------------------------------------------+
void PlaceOrder()
{
   if(current.ticket!=0) return; // already

   double entry=current.entry50;

   double slPrice, tpPrice;
   if(current.isSell)
   {
      slPrice=UseDailyHighLowSL ? dailyHigh : current.sweep.high;
      tpPrice=entry - (slPrice-entry)*RiskRewardRatio;
   }
   else
   {
      slPrice=UseDailyHighLowSL ? dailyLow : current.sweep.low;
      tpPrice=entry + (entry-slPrice)*RiskRewardRatio;
   }

   double stopPips=fabs(entry-slPrice)/_Point;
   double lots=CalculateLots(stopPips);

   bool sent=false;
   trade.SetDeviationInPoints(Slippage);
   if(EntryOrderType==Market)
   {
      if(current.isSell)
         sent=trade.Sell(lots,_Symbol,0,slPrice,(UseTakeProfit?tpPrice:0),"");
      else
         sent=trade.Buy(lots,_Symbol,0,slPrice,(UseTakeProfit?tpPrice:0),"");
   }
   else
   {
      if(current.isSell)
         sent=trade.SellLimit(lots,entry,_Symbol,slPrice,(UseTakeProfit?tpPrice:0));
      else
         sent=trade.BuyLimit(lots,entry,_Symbol,slPrice,(UseTakeProfit?tpPrice:0));
   }

   if(sent)
   {
      current.ticket=trade.ResultOrder();
      current.sl=slPrice;
      current.tp=tpPrice;
      Print("Order placed: ",current.isSell?"SELL":"BUY"," ",DoubleToString(lots,2),
            " @",DoubleToString(entry,_Digits)," SL=",DoubleToString(slPrice,_Digits),
            " TP=",DoubleToString(tpPrice,_Digits)," (Ticket ",current.ticket,")");
      current.status=NONE; // one setup at a time
   }
}

//+------------------------------------------------------------------+
double CalculateLots(double stopPips)
{
   if(LotSizingMode==Fixed)
      return(FixedLotSize);

   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double risk=balance*RiskPercentPerTrade/100.0;
   double tickVal=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double sl=stopPips*_Point;
   double lossPerLot=(sl/tickSize)*tickVal;
   if(lossPerLot<=0) return(0.01);
   double raw=risk/lossPerLot;
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double lots=MathFloor(raw/step)*step;
   lots=MathMax(minLot,MathMin(maxLot,lots));
   return(NormalizeDouble(lots,2));
}
//+------------------------------------------------------------------+

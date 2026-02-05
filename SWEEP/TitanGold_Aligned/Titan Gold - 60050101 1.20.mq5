#property strict
#property copyright ""
#property link      ""
#property version   "1.20"
#property description "Titan Gold - 60050101 1.20"

#include <Trade/Trade.mqh>

CTrade trade;

//--- enums
enum ENUM_ATTACH_MODE
  {
   AttachMode_IfOneSideSweptOpposite_IfNoneBoth=0
  };

//--- inputs (order must match screenshot)
input bool     InpEnableEA = true;
input ulong    InpMagicNumber = 55501;
input bool     InpUseRiskPercent = false; // true = risk % sizing, false = fixed lot
input double   InpRiskPercent = 0.5; // % of equity per trade (0.50 = 0.5%)
input double   InpFixedLots = 5.0; // used if InpUseRiskPercent=false
input int      InpStopLossPoints = 1000; // SL in points
input int      InpTakeProfitPoints = 1000; // TP in points
input int      InpBufferPoints = 20; // BuyStop = High+Buffer, SellStop = Low-Buffer
input int      InpTrailStepPoints = 150; // step size & first activation level (profit points)
input int      InpTrailOffsetPoints = 100; // offset (locks level*step - offset)
input int      InpHoldTimeSeconds = 120; // hold time in seconds
input bool     InpDisableProtectionDuringHold = false; // false = protection works even during hold (recommended)
input bool     InpUseSpreadFilter = true;
input int      InpMaxSpreadPoints = 60; // block placing/canceling if spread > this
input bool     InpUseRolloverBlock = true;
input int      InpRolloverBlockStart = 2350; // broker time HHMM
input int      InpRolloverBlockEnd = 10; // broker time HHMM (can cross midnight)
input int      InpWaitAfterNewD1Seconds = 600; // wait after new D1 bar before placing orders
input ENUM_ATTACH_MODE InpAttachMode = AttachMode_IfOneSideSweptOpposite_IfNoneBoth;
input bool     InpEnableRequestLimitProtection = true;
input int      InpRequestRetryWaitSeconds = 10; // wait before retrying after a failed place
input int      InpMaxOrderPlacementAttempts = 5; // max order placement attempts per D1 bar/day
input bool     InpUseGapFilter = true;
input int      InpGapSkipPoints = 1000; // if abs(D1 open - prev close) > this => skip day
input bool     InpDeletePendingsOnGap = true; // delete pendings if a big gap is detected
input bool     InpSkipDayOnGap = true; // if true => do not place orders that day
input bool     InpDeleteOppositePendingOnEntry = true;
input int      InpSlippagePoints = 30;

//--- state
static datetime g_lastD1OpenTime = 0;
static datetime g_lastFailedPlaceTime = 0;
static int      g_failedPlaceAttempts = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!InpEnableEA)
      return;

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);

   double pdh=0.0, pdl=0.0, prevClose=0.0, todayOpen=0.0;
   datetime todayOpenTime=0;

   if(!GetPreviousDayLevels(pdh,pdl,prevClose,todayOpen,todayOpenTime))
      return;

   if(g_lastD1OpenTime!=todayOpenTime)
     {
      g_lastD1OpenTime = todayOpenTime;
      g_failedPlaceAttempts = 0;
      g_lastFailedPlaceTime = 0;
     }

   if(!IsAfterD1Wait(todayOpenTime))
      return;

   if(InpUseRolloverBlock && IsWithinRolloverWindow())
      return;

   if(InpUseSpreadFilter && GetSpreadPoints()>InpMaxSpreadPoints)
      return;

   bool gapDetected=false;
   if(InpUseGapFilter)
     {
      double gapPoints = MathAbs(todayOpen - prevClose) / _Point;
      gapDetected = (gapPoints > InpGapSkipPoints);
      if(gapDetected && InpDeletePendingsOnGap)
         DeleteAllPendings();
      if(gapDetected && InpSkipDayOnGap)
         return;
     }

   ManageOpenPositions();

   if(HasOpenPosition())
      return;

   if(InpEnableRequestLimitProtection)
     {
      if(g_failedPlaceAttempts>=InpMaxOrderPlacementAttempts)
         return;
      if(g_lastFailedPlaceTime>0 && (TimeCurrent()-g_lastFailedPlaceTime)<InpRequestRetryWaitSeconds)
         return;
     }

   PlaceDailyPendings(pdh,pdl);
  }

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
bool GetPreviousDayLevels(double &pdh,double &pdl,double &prevClose,double &todayOpen,datetime &todayOpenTime)
  {
   MqlRates rates[2];
   int copied = CopyRates(_Symbol,PERIOD_D1,0,2,rates);
   if(copied<2)
     {
      MqlTick tick;
      SymbolInfoTick(_Symbol,tick);
      copied = CopyRates(_Symbol,PERIOD_D1,0,2,rates);
     }
   if(copied<2)
      return false;

   todayOpenTime = rates[0].time;
   todayOpen = rates[0].open;
   pdh = rates[1].high;
   pdl = rates[1].low;
   prevClose = rates[1].close;
   return true;
  }

bool IsAfterD1Wait(datetime todayOpenTime)
  {
   return(TimeCurrent() >= (todayOpenTime + InpWaitAfterNewD1Seconds));
  }

int GetSpreadPoints()
  {
   double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(ask<=0.0 || bid<=0.0)
      return 0;
   return (int)MathRound((ask-bid)/_Point);
  }

bool IsWithinRolloverWindow()
  {
   datetime nowTime = TimeCurrent();
   int nowMinutes = TimeHour(nowTime)*60 + TimeMinute(nowTime);
   int startMinutes = (InpRolloverBlockStart/100)*60 + (InpRolloverBlockStart%100);
   int endMinutes = (InpRolloverBlockEnd/100)*60 + (InpRolloverBlockEnd%100);

   if(startMinutes==endMinutes)
      return false;
   if(startMinutes<endMinutes)
      return (nowMinutes>=startMinutes && nowMinutes<endMinutes);
   return (nowMinutes>=startMinutes || nowMinutes<endMinutes);
  }

bool HasOpenPosition()
  {
   for(int i=PositionsTotal()-1; i>=0; --i)
     {
      if(PositionSelectByIndex(i))
        {
         if(PositionGetInteger(POSITION_MAGIC)==(long)InpMagicNumber && PositionGetString(POSITION_SYMBOL)==_Symbol)
            return true;
        }
     }
   return false;
  }

void ManageOpenPositions()
  {
   for(int i=PositionsTotal()-1; i>=0; --i)
     {
      if(!PositionSelectByIndex(i))
         continue;
      if(PositionGetInteger(POSITION_MAGIC)!=(long)InpMagicNumber || PositionGetString(POSITION_SYMBOL)!=_Symbol)
         continue;

      long type = PositionGetInteger(POSITION_TYPE);
      datetime entryTime = (datetime)PositionGetInteger(POSITION_TIME);
      if(InpDisableProtectionDuringHold && (TimeCurrent()-entryTime)<InpHoldTimeSeconds)
         continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double profitPoints = (type==POSITION_TYPE_BUY) ? ((bid-openPrice)/_Point) : ((openPrice-ask)/_Point);

      if(profitPoints < InpTrailStepPoints)
         continue;

      int level = (int)MathFloor(profitPoints / InpTrailStepPoints);
      double newSl = sl;
      if(type==POSITION_TYPE_BUY)
        {
         newSl = openPrice + (level*InpTrailStepPoints - InpTrailOffsetPoints) * _Point;
         if(newSl > sl && newSl < bid)
            trade.PositionModify(_Symbol,newSl,PositionGetDouble(POSITION_TP));
        }
      else if(type==POSITION_TYPE_SELL)
        {
         newSl = openPrice - (level*InpTrailStepPoints - InpTrailOffsetPoints) * _Point;
         if((sl==0.0 || newSl < sl) && newSl > ask)
            trade.PositionModify(_Symbol,newSl,PositionGetDouble(POSITION_TP));
        }

      if(InpDeleteOppositePendingOnEntry)
         DeleteOppositePendings(type);
     }
  }

void DeleteOppositePendings(long positionType)
  {
   for(int i=OrdersTotal()-1; i>=0; --i)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket==0)
         continue;
      if(!OrderSelect(ticket))
         continue;
      if(OrderGetInteger(ORDER_MAGIC)!=(long)InpMagicNumber || OrderGetString(ORDER_SYMBOL)!=_Symbol)
         continue;

      long type = OrderGetInteger(ORDER_TYPE);
      if(positionType==POSITION_TYPE_BUY && type==ORDER_TYPE_SELL_STOP)
         trade.OrderDelete(ticket);
      else if(positionType==POSITION_TYPE_SELL && type==ORDER_TYPE_BUY_STOP)
         trade.OrderDelete(ticket);
     }
  }

void DeleteAllPendings()
  {
   for(int i=OrdersTotal()-1; i>=0; --i)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket==0)
         continue;
      if(!OrderSelect(ticket))
         continue;
      if(OrderGetInteger(ORDER_MAGIC)!=(long)InpMagicNumber || OrderGetString(ORDER_SYMBOL)!=_Symbol)
         continue;
      long type = OrderGetInteger(ORDER_TYPE);
      if(type==ORDER_TYPE_BUY_STOP || type==ORDER_TYPE_SELL_STOP)
         trade.OrderDelete(ticket);
     }
  }

bool HasPendingOrder(long orderType)
  {
   for(int i=OrdersTotal()-1; i>=0; --i)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket==0)
         continue;
      if(!OrderSelect(ticket))
         continue;
      if(OrderGetInteger(ORDER_MAGIC)!=(long)InpMagicNumber || OrderGetString(ORDER_SYMBOL)!=_Symbol)
         continue;
      if(OrderGetInteger(ORDER_TYPE)==orderType)
         return true;
     }
   return false;
  }

void PlaceDailyPendings(double pdh,double pdl)
  {
   double buyStopPrice = pdh + (InpBufferPoints * _Point);
   double sellStopPrice = pdl - (InpBufferPoints * _Point);

   bool buySwept = (SymbolInfoDouble(_Symbol,SYMBOL_BID) > pdh);
   bool sellSwept = (SymbolInfoDouble(_Symbol,SYMBOL_BID) < pdl);

   bool allowBuy = true;
   bool allowSell = true;

   if(InpAttachMode==AttachMode_IfOneSideSweptOpposite_IfNoneBoth)
     {
      if(buySwept && !sellSwept)
        {
         allowBuy = false;
         allowSell = true;
        }
      else if(sellSwept && !buySwept)
        {
         allowBuy = true;
         allowSell = false;
        }
     }

   double lots = CalculateLots(InpStopLossPoints);

   bool placedAny = false;

   if(allowBuy && !HasPendingOrder(ORDER_TYPE_BUY_STOP))
     {
      double sl = (InpStopLossPoints>0) ? (buyStopPrice - InpStopLossPoints*_Point) : 0.0;
      double tp = (InpTakeProfitPoints>0) ? (buyStopPrice + InpTakeProfitPoints*_Point) : 0.0;
      if(!trade.BuyStop(lots,buyStopPrice,_Symbol,sl,tp))
         RecordFailedPlace();
      else
         placedAny = true;
     }

   if(allowSell && !HasPendingOrder(ORDER_TYPE_SELL_STOP))
     {
      double sl = (InpStopLossPoints>0) ? (sellStopPrice + InpStopLossPoints*_Point) : 0.0;
      double tp = (InpTakeProfitPoints>0) ? (sellStopPrice - InpTakeProfitPoints*_Point) : 0.0;
      if(!trade.SellStop(lots,sellStopPrice,_Symbol,sl,tp))
         RecordFailedPlace();
      else
         placedAny = true;
     }

   if(placedAny)
     {
      g_failedPlaceAttempts = 0;
      g_lastFailedPlaceTime = 0;
     }
  }

void RecordFailedPlace()
  {
   if(!InpEnableRequestLimitProtection)
      return;
   g_failedPlaceAttempts++;
   g_lastFailedPlaceTime = TimeCurrent();
  }

double CalculateLots(int slPoints)
  {
   if(!InpUseRiskPercent)
      return NormalizeLots(InpFixedLots);

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * (InpRiskPercent/100.0);
   if(riskMoney<=0.0 || slPoints<=0)
      return NormalizeLots(InpFixedLots);

   double tickValue = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickValue<=0.0 || tickSize<=0.0)
      return NormalizeLots(InpFixedLots);

   double valuePerPoint = tickValue * (_Point / tickSize);
   if(valuePerPoint<=0.0)
      return NormalizeLots(InpFixedLots);

   double lots = riskMoney / (slPoints * valuePerPoint);
   return NormalizeLots(lots);
  }

double NormalizeLots(double lots)
  {
   double minLot = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(lots<minLot)
      lots = minLot;
   if(lots>maxLot)
      lots = maxLot;
   if(step>0)
      lots = MathFloor(lots/step)*step;
   return lots;
  }

/*
Mapping: Screenshot Input -> Code Variable -> Internal usage
- InpEnableEA -> InpEnableEA -> master enable gate in OnTick
- InpMagicNumber -> InpMagicNumber -> trade magic number for orders/positions
- true = risk % sizing, false = fixed lot -> InpUseRiskPercent -> CalculateLots routing
- % of equity per trade (0.50 = 0.5%) -> InpRiskPercent -> CalculateLots riskMoney
- used if InpUseRiskPercent=false -> InpFixedLots -> CalculateLots fixed sizing
- SL in points -> InpStopLossPoints -> SL distance & risk calculation
- TP in points -> InpTakeProfitPoints -> TP distance
- BuyStop = High+Buffer, SellStop = Low-Buffer -> InpBufferPoints -> PDH/PDL buffer for pending prices
- step size & first activation level (profit points) -> InpTrailStepPoints -> trailing activation/step
- offset (locks level*step - offset) -> InpTrailOffsetPoints -> trailing lock offset
- hold time in seconds -> InpHoldTimeSeconds -> hold window for protection
- false = protection works even during hold (recommended) -> InpDisableProtectionDuringHold -> trailing hold behavior
- InpUseSpreadFilter -> InpUseSpreadFilter -> spread blocking
- block placing/canceling if spread > this -> InpMaxSpreadPoints -> max spread points
- InpUseRolloverBlock -> InpUseRolloverBlock -> rollover blocking
- broker time HHMM -> InpRolloverBlockStart -> rollover start time
- broker time HHMM (can cross midnight) -> InpRolloverBlockEnd -> rollover end time
- wait after new D1 bar before placing orders -> InpWaitAfterNewD1Seconds -> daily placement delay
- InpAttachMode -> InpAttachMode -> sweeping attachment mode selection
- InpEnableRequestLimitProtection -> InpEnableRequestLimitProtection -> failed request throttling
- wait before retrying after a failed place -> InpRequestRetryWaitSeconds -> retry delay
- max order placement attempts per D1 bar/day -> InpMaxOrderPlacementAttempts -> attempt cap
- InpUseGapFilter -> InpUseGapFilter -> gap detection
- if abs(D1 open - prev close) > this => skip day -> InpGapSkipPoints -> gap skip threshold
- delete pendings if a big gap is detected -> InpDeletePendingsOnGap -> pending cleanup on gap
- if true => do not place orders that day -> InpSkipDayOnGap -> gap day skip
- InpDeleteOppositePendingOnEntry -> InpDeleteOppositePendingOnEntry -> pending cleanup on entry
- InpSlippagePoints -> InpSlippagePoints -> trade slippage

Checklist for MT5 Inputs tab
1) Verify EA name shows as "Titan Gold - 60050101 1.20".
2) Confirm the input order matches the screenshot top-to-bottom.
3) Check each input name matches exactly (including Inp* prefixes).
4) Confirm comments match the screenshot text exactly.
5) Verify default values match the screenshot values.
6) Ensure InpBufferPoints default = 20 and is labeled "BuyStop = High+Buffer, SellStop = Low-Buffer".
7) Confirm all numeric inputs are in POINTS or SECONDS (no pips).
8) Verify InpAttachMode dropdown shows the screenshot wording.
*/

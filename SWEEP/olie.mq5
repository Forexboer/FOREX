//+------------------------------------------------------------------+
//|                    OneShot Box EA for MetaTrader 5               |
//| Breakout trading strategy for oil markets                        |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

//--- Input parameters
sinput group "Box Settings"
input string   BoxStartTime            = "00:00";   // Time the box starts
input string   BoxEndTime              = "16:30";   // Time the box ends

sinput group "Trade Settings"
input int      StopLossPips            = 50;        // Stop loss in pips
input int      TakeProfitPips          = 25;        // Take profit in pips
input bool     UseLockProfit           = true;      // Move SL to breakeven
input int      LockProfitTriggerPips   = 15;        // Trigger for lock profit
input int      LockProfitBufferPips    = 1;         // Breakeven buffer
input bool     UseTrailingStop         = true;      // Enable trailing stop
input int      TrailingStartPips       = 20;        // Trailing start
input int      TrailingDistancePips    = 15;        // Trailing distance
input double   RiskPerTradePercent     = 1.0;       // Risk per trade
input bool     UseSpreadCorrection     = true;      // Adjust for spread
input bool     UseDirectCounterTrade   = false;     // Immediate counter trade
input int      MagicNumber             = 1111;      // Magic number

//--- Global variables
CTrade trade;
datetime g_box_start, g_box_end;
double   g_box_high, g_box_low;
bool     g_box_drawn = false;
bool     g_buy_traded = false;
bool     g_sell_traded = false;
ulong    g_buy_pos = 0;
ulong    g_sell_pos = 0;
int      g_last_day = -1;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   ResetDay();
   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "", 0);
}
//+------------------------------------------------------------------+
void OnTick()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.day != g_last_day)
   {
      g_last_day = dt.day;
      ResetDay();
   }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = ask - bid;

   if(TimeCurrent() <= g_box_end)
   {
      UpdateBox();
      DrawBox();
      return;
   }
   else if(!g_box_drawn)
   {
      DrawBox();
      g_box_drawn = true;
   }

   if(!g_buy_traded && ask > g_box_high)
      OpenTrade(true, ask, bid, spread);
   if(!g_sell_traded && bid < g_box_low)
      OpenTrade(false, ask, bid, spread);

   ManagePositions(ask, bid);
}
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   if(!UseDirectCounterTrade) return;
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD || trans.entry!=DEAL_ENTRY_OUT)
      return;
   if(trans.magic!=MagicNumber || trans.position==0)
      return;
   if((int)HistoryDealGetInteger(trans.deal, DEAL_REASON)!=DEAL_REASON_SL)
      return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = ask - bid;

   if(trans.position_type==POSITION_TYPE_BUY && !g_sell_traded)
      OpenTrade(false, ask, bid, spread);
   if(trans.position_type==POSITION_TYPE_SELL && !g_buy_traded)
      OpenTrade(true, ask, bid, spread);
}
//+------------------------------------------------------------------+
void ResetDay()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   string date_str = StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day);
   g_box_start = StringToTime(date_str + " " + BoxStartTime);
   g_box_end   = StringToTime(date_str + " " + BoxEndTime);
   g_box_high  = -DBL_MAX;
   g_box_low   = DBL_MAX;
   g_box_drawn = false;
   g_buy_traded = false;
   g_sell_traded = false;
   g_buy_pos = 0;
   g_sell_pos = 0;
   ObjectsDeleteAll(0, "", 0);

   // preload history if EA attached mid-day
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, PERIOD_M15, g_box_start, TimeCurrent(), rates);
   for(int i=0;i<copied;i++)
   {
      if(rates[i].high > g_box_high) g_box_high = rates[i].high;
      if(rates[i].low  < g_box_low)  g_box_low  = rates[i].low;
   }
}
//+------------------------------------------------------------------+
void UpdateBox()
{
   double h = iHigh(_Symbol, PERIOD_M15, 0);
   double l = iLow(_Symbol, PERIOD_M15, 0);
   if(h > g_box_high) g_box_high = h;
   if(l < g_box_low)  g_box_low  = l;
}
//+------------------------------------------------------------------+
void DrawBox()
{
   ObjectDelete(0, "BOX");
   ObjectDelete(0, "Box High");
   ObjectDelete(0, "Box Low");
   ObjectCreate(0, "BOX", OBJ_RECTANGLE, 0, g_box_start, g_box_high, g_box_end, g_box_low);
   ObjectSetInteger(0, "BOX", OBJPROP_COLOR, clrAqua);
   ObjectSetInteger(0, "BOX", OBJPROP_BACK, true);
   ObjectCreate(0, "Box High", OBJ_HLINE, 0, TimeCurrent(), g_box_high);
   ObjectSetInteger(0, "Box High", OBJPROP_COLOR, clrGreen);
   ObjectCreate(0, "Box Low", OBJ_HLINE, 0, TimeCurrent(), g_box_low);
   ObjectSetInteger(0, "Box Low", OBJPROP_COLOR, clrRed);
}
//+------------------------------------------------------------------+
void OpenTrade(bool buy, double ask, double bid, double spread)
{
   double entry = buy ? ask : bid;
   double sl = buy ? entry - StopLossPips*_Point : entry + StopLossPips*_Point;
   double tp = buy ? entry + TakeProfitPips*_Point : entry - TakeProfitPips*_Point;

   if(UseSpreadCorrection)
   {
      if(buy)
      {
         sl -= spread;
         tp += spread;
      }
      else
      {
         sl += spread;
         tp -= spread;
      }
   }

   double lot = CalculateLotSize();
   bool sent = buy ? trade.Buy(lot, _Symbol, entry, sl, tp)
                   : trade.Sell(lot, _Symbol, entry, sl, tp);
   if(sent)
   {
      ulong pos_id = trade.ResultDeal();
      if(buy)
      {
         g_buy_traded = true;
         g_buy_pos = pos_id;
      }
      else
      {
         g_sell_traded = true;
         g_sell_pos = pos_id;
      }
   }
}
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk = balance * RiskPerTradePercent / 100.0;
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_value<=0.0 || tick_size<=0.0) return(0.01);
   double pip_value = tick_value * _Point / tick_size;
   double raw_lots = risk / (StopLossPips * pip_value);
   double step  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   raw_lots = MathFloor(raw_lots/step)*step;
   raw_lots = MathMax(minLot, MathMin(maxLot, raw_lots));
   int prec = (int)MathMax(0, -MathLog10(step));
   return(NormalizeDouble(raw_lots, prec));
}
//+------------------------------------------------------------------+
void ManagePositions(double ask, double bid)
{
   for(int i=PositionsTotal()-1; i>=0; --i)
   {
      ulong posTicket = PositionGetTicket(i);
      if(!PositionSelectByTicket(posTicket)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;

      ulong ticket = PositionGetInteger(POSITION_IDENTIFIER);
      bool isBuy = PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double profit_pips = (isBuy ? bid - open : open - ask) / _Point;

      // Lock profit to breakeven
      if(UseLockProfit && profit_pips >= LockProfitTriggerPips)
      {
         double new_sl = open + (isBuy ? LockProfitBufferPips : -LockProfitBufferPips)*_Point;
         if(isBuy && new_sl > sl) trade.PositionModify(ticket, new_sl, tp);
         if(!isBuy && new_sl < sl) trade.PositionModify(ticket, new_sl, tp);
      }

      // Trailing stop
      if(UseTrailingStop && profit_pips >= TrailingStartPips)
      {
         double trail = isBuy ? bid - TrailingDistancePips*_Point
                              : ask + TrailingDistancePips*_Point;
         if(isBuy && trail > sl) trade.PositionModify(ticket, trail, tp);
         if(!isBuy && trail < sl) trade.PositionModify(ticket, trail, tp);
      }
   }
}
//+------------------------------------------------------------------+

#property strict
#property script_show_inputs

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Expert Advisor: News Windows Manager (Broker Time)               |
//| Platform: MetaTrader 5                                          |
//| Closes open trades and removes pending stop orders during       |
//| pre-defined news windows (broker time).                         |
//+------------------------------------------------------------------+

enum TradeCloseScopeEnum
{
   TradeCloseOff = 0,
   TradeCloseAll = 1,
   TradeCloseByMagic = 2
};

enum StopScopeEnum
{
   StopScopeAll = 0,
   StopScopeByMagic = 1
};

enum DeleteModeEnum
{
   DeleteOnce = 0,
   EnforceNoStops = 1
};

input string MondayWindows   = "";
input string TuesdayWindows  = "";
input string WednesdayWindows= "14:00-15:00";
input string ThursdayWindows = "";
input string FridayWindows   = "14:00-15:00";

input int    PreBufferMinutes  = 5;
input int    PostBufferMinutes = 0;
input string FridayHardCleanupTime = "";

input bool   UseSymbolsFilter    = true;
input string SymbolsToManage     = "EURUSD,GBPUSD";

input TradeCloseScopeEnum TradeCloseScope = TradeCloseByMagic;
input string TradeMagicNumbers   = "3,7";
input bool   TradeCloseSymbolsOnly = true;

input bool   ManageStops         = true;
input StopScopeEnum StopScope    = StopScopeAll;
input string StopMagicNumbers    = "";
input DeleteModeEnum DeleteMode  = EnforceNoStops;
input int    SpreadMaxPoints     = 0;

input bool   DryRunMode          = true;
input bool   LogAlerts           = true;

//--- structures -----------------------------------------------------
struct NewsWindow
{
   int  start;           // minutes from midnight
   int  end;             // minutes from midnight
   bool trades_closed;   // trade closure done
   bool stops_deleted;   // stop deletion done (for DeleteOnce)
};

//--- arrays for days (0=Sunday,1=Monday,...,6=Saturday)
NewsWindow Monday[];
NewsWindow Tuesday[];
NewsWindow Wednesday[];
NewsWindow Thursday[];
NewsWindow Friday[];

//--- other globals --------------------------------------------------
string symbols[];
int    trade_magics[];
int    stop_magics[];
int    friday_cleanup_minute = -1;
bool   friday_cleanup_done = false;
int    current_day = -1;
CTrade trade;

//+------------------------------------------------------------------+
//| Utility: trim string                                             |
//+------------------------------------------------------------------+
string Trim(string s)
{
   StringTrimLeft(s);
   StringTrimRight(s);
   return s;
}

//+------------------------------------------------------------------+
//| Parse HH:MM string to minutes from midnight                      |
//+------------------------------------------------------------------+
int ParseTimeToMinutes(const string text)
{
   string parts[];
   if(StringSplit(Trim(text), ':', parts) != 2)
      return -1;
   int h = (int)StringToInteger(parts[0]);
   int m = (int)StringToInteger(parts[1]);
   if(h < 0 || h > 23 || m < 0 || m > 59)
      return -1;
   return h*60 + m;
}

//+------------------------------------------------------------------+
//| Parse windows string for a day                                   |
//+------------------------------------------------------------------+
void ParseWindows(const string src, NewsWindow &windows[])
{
   ArrayResize(windows, 0);
   string entries[];
   int n = StringSplit(src, ',', entries);
   for(int i=0; i<n; i++)
   {
      string item = Trim(entries[i]);
      if(item == "")
         continue;
      string range[2];
      if(StringSplit(item, '-', range) != 2)
      {
         if(LogAlerts) Print("Invalid window entry: ", item);
         continue;
      }
      int start = ParseTimeToMinutes(range[0]);
      int end   = ParseTimeToMinutes(range[1]);
      if(start < 0 || end < 0 || end <= start)
      {
         if(LogAlerts) Print("Invalid time range: ", item);
         continue;
      }
      int idx = ArraySize(windows);
      ArrayResize(windows, idx+1);
      windows[idx].start = start;
      windows[idx].end   = end;
      windows[idx].trades_closed = false;
      windows[idx].stops_deleted = false;
   }
}

//+------------------------------------------------------------------+
//| Parse comma separated list of symbols                            |
//+------------------------------------------------------------------+
void ParseSymbols(const string src)
{
   ArrayResize(symbols, 0);
   string entries[];
   int n = StringSplit(src, ',', entries);
   for(int i=0; i<n; i++)
   {
      string sym = Trim(entries[i]);
      if(sym == "")
         continue;
      int idx = ArraySize(symbols);
      ArrayResize(symbols, idx+1);
      symbols[idx] = sym;
   }
}

//+------------------------------------------------------------------+
//| Parse comma separated list of magic numbers                      |
//+------------------------------------------------------------------+
void ParseMagics(const string src, int &magics[])
{
   ArrayResize(magics, 0);
   string entries[];
   int n = StringSplit(src, ',', entries);
   for(int i=0; i<n; i++)
   {
      string s = Trim(entries[i]);
      if(s == "")
         continue;
      int val = (int)StringToInteger(s);
      bool exists = false;
      for(int j=0; j<ArraySize(magics); j++)
         if(magics[j] == val)
            exists = true;
      if(!exists)
      {
         int idx = ArraySize(magics);
         ArrayResize(magics, idx+1);
         magics[idx] = val;
      }
   }
}

//+------------------------------------------------------------------+
//| Helper: check if symbol is allowed                               |
//+------------------------------------------------------------------+
bool IsSymbolAllowed(const string sym)
{
   if(!UseSymbolsFilter)
      return true;
   for(int i=0; i<ArraySize(symbols); i++)
      if(symbols[i] == sym)
         return true;
   return false;
}

//+------------------------------------------------------------------+
//| Helper: check if magic in list                                   |
//+------------------------------------------------------------------+
bool MagicInList(const long magic, const int &list[])
{
   for(int i=0; i<ArraySize(list); i++)
      if(list[i] == magic)
         return true;
   return false;
}

//+------------------------------------------------------------------+
//| Close trades according to scope                                   |
//+------------------------------------------------------------------+
void CloseTrades()
{
   if(TradeCloseScope == TradeCloseOff)
      return;
   bool byMagic = (TradeCloseScope == TradeCloseByMagic);
   bool needMagics = (byMagic && ArraySize(trade_magics) == 0);
   if(needMagics)
      return; // empty list

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      long magic  = PositionGetInteger(POSITION_MAGIC);

      if(byMagic && !MagicInList(magic, trade_magics))
         continue;
      if(UseSymbolsFilter && TradeCloseScope == TradeCloseAll && TradeCloseSymbolsOnly && !IsSymbolAllowed(sym))
         continue;
      if(UseSymbolsFilter && (TradeCloseScope == TradeCloseByMagic) && !IsSymbolAllowed(sym))
         continue;
      double volume = PositionGetDouble(POSITION_VOLUME);
      int attempts = 0;
      bool success = false;
      while(attempts < 3 && !success)
      {
         if(DryRunMode)
         {
            if(LogAlerts) Print("DryRun: close position ", ticket, " ", sym, " magic=", magic);
            success = true;
         }
         else
         {
            trade.PositionClose(ticket);
            if(trade.ResultRetcode() == TRADE_RETCODE_DONE)
            {
               if(LogAlerts) Print("Closed position ", ticket, " ", sym, " magic=", magic);
               success = true;
            }
            else
            {
               if(LogAlerts) Print("Failed close ", ticket, " retcode=", trade.ResultRetcode());
               Sleep(100);
            }
         }
         attempts++;
      }
   }
}

//+------------------------------------------------------------------+
//| Delete pending stop orders according to scope                    |
//+------------------------------------------------------------------+
void DeleteStopOrders()
{
   if(!ManageStops)
      return;
   bool byMagic = (StopScope == StopScopeByMagic);
   bool needMagics = (byMagic && ArraySize(stop_magics) == 0);
   if(needMagics)
      return; // nothing to do

   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket))
         continue;
      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(type != ORDER_TYPE_BUY_STOP && type != ORDER_TYPE_SELL_STOP)
         continue;
      string sym = OrderGetString(ORDER_SYMBOL);
      long magic  = OrderGetInteger(ORDER_MAGIC);
      if(byMagic && !MagicInList(magic, stop_magics))
         continue;
      if(UseSymbolsFilter && !IsSymbolAllowed(sym))
         continue;
      if(SpreadMaxPoints > 0)
      {
         long spread = SymbolInfoInteger(sym, SYMBOL_SPREAD);
         if(spread <= SpreadMaxPoints)
            continue;
      }
      int attempts = 0;
      bool success = false;
      while(attempts < 3 && !success)
      {
         if(DryRunMode)
         {
            if(LogAlerts) Print("DryRun: delete order ", ticket, " ", sym, " magic=", magic);
            success = true;
         }
         else
         {
            trade.OrderDelete(ticket);
            if(trade.ResultRetcode() == TRADE_RETCODE_DONE)
            {
               if(LogAlerts) Print("Deleted order ", ticket, " ", sym, " magic=", magic);
               success = true;
            }
            else
            {
               if(LogAlerts) Print("Failed delete ", ticket, " retcode=", trade.ResultRetcode());
               Sleep(100);
            }
         }
         attempts++;
      }
   }
}

//+------------------------------------------------------------------+
//| Reset daily flags                                                |
//+------------------------------------------------------------------+
void ResetDailyFlags()
{
   for(int i=0; i<ArraySize(Monday); i++)     { Monday[i].trades_closed=false; Monday[i].stops_deleted=false; }
   for(int i=0; i<ArraySize(Tuesday); i++)    { Tuesday[i].trades_closed=false; Tuesday[i].stops_deleted=false; }
   for(int i=0; i<ArraySize(Wednesday); i++)  { Wednesday[i].trades_closed=false; Wednesday[i].stops_deleted=false; }
   for(int i=0; i<ArraySize(Thursday); i++)   { Thursday[i].trades_closed=false; Thursday[i].stops_deleted=false; }
   for(int i=0; i<ArraySize(Friday); i++)     { Friday[i].trades_closed=false; Friday[i].stops_deleted=false; }
   friday_cleanup_done = false;
}

//+------------------------------------------------------------------+
//| Process windows for a specific day                               |
//+------------------------------------------------------------------+
void ProcessDayWindows(NewsWindow &arr[], int minutes)
{
   for(int i=0; i<ArraySize(arr); i++)
   {
      int start = arr[i].start - PreBufferMinutes;
      int end   = arr[i].end   + PostBufferMinutes;
      if(start < 0) start = 0;
      if(end > 1440) end = 1440;
      if(minutes >= start && minutes < end)
      {
         if(!arr[i].trades_closed)
         {
            CloseTrades();
            arr[i].trades_closed = true;
         }
         bool need_delete = false;
         if(DeleteMode == EnforceNoStops)
            need_delete = true;
         else if(DeleteMode == DeleteOnce && !arr[i].stops_deleted)
            need_delete = true;
         bool spread_trigger = (SpreadMaxPoints > 0);
         if(need_delete || spread_trigger)
         {
            DeleteStopOrders();
            if(DeleteMode == DeleteOnce && need_delete)
               arr[i].stops_deleted = true;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check windows for today                                          |
//+------------------------------------------------------------------+
void CheckWindows()
{
   datetime now = TimeCurrent();
   int day = TimeDayOfWeek(now); // 0=Sunday
   if(day != current_day)
   {
      current_day = day;
      ResetDailyFlags();
   }
   int minutes = TimeHour(now)*60 + TimeMinute(now);

   switch(day)
   {
      case 1: ProcessDayWindows(Monday,    minutes); break;
      case 2: ProcessDayWindows(Tuesday,   minutes); break;
      case 3: ProcessDayWindows(Wednesday, minutes); break;
      case 4: ProcessDayWindows(Thursday,  minutes); break;
      case 5: ProcessDayWindows(Friday,    minutes); break;
      default: break; // non-handled days
   }

   // Friday hard cleanup
   if(day == 5 && friday_cleanup_minute >= 0 && !friday_cleanup_done && minutes >= friday_cleanup_minute)
   {
      CloseTrades();
      DeleteStopOrders();
      friday_cleanup_done = true;
   }
}

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   ParseWindows(MondayWindows, Monday);
   ParseWindows(TuesdayWindows, Tuesday);
   ParseWindows(WednesdayWindows, Wednesday);
   ParseWindows(ThursdayWindows, Thursday);
   ParseWindows(FridayWindows, Friday);

   ParseSymbols(SymbolsToManage);
   ParseMagics(TradeMagicNumbers, trade_magics);
   ParseMagics(StopMagicNumbers, stop_magics);

   if(FridayHardCleanupTime != "")
      friday_cleanup_minute = ParseTimeToMinutes(FridayHardCleanupTime);
   else
      friday_cleanup_minute = -1;

   current_day = -1;
   EventSetTimer(30); // check every 30 seconds
   if(LogAlerts) Print("News Windows Manager initialized");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(LogAlerts) Print("News Windows Manager deinitialized");
}

//+------------------------------------------------------------------+
//| Timer event                                                      |
//+------------------------------------------------------------------+
void OnTimer()
{
   CheckWindows();
}

//+------------------------------------------------------------------+
//| No trading on ticks                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // no action on ticks
}

//+------------------------------------------------------------------+

#property copyright ""
#property link      ""
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

enum ENUM_ENTRY_MODE
  {
   ENTRY_ON_BREAK_TOUCH = 0,
   ENTRY_ON_CLOSE       = 1
  };

enum ENUM_SL_MODE
  {
   SL_MODE_ATR = 0,
   SL_MODE_FIXED_POINTS = 1
  };

enum ENUM_TP_MODE
  {
   TP_MODE_RR = 0,
   TP_MODE_FIXED_POINTS = 1
  };

struct NewsEvent
  {
   datetime time;
   string   currency;
   string   impact;
  };

input int               MagicNumber              = 20241013;
input bool              InpEnableEA              = true;
input bool              InpUseRiskPercent        = true;
input double            InpRiskPercentPerTrade   = 1.0;         // percent of equity if risk sizing enabled
input double            InpFixedLot              = 0.10;        // used only when InpUseRiskPercent == false
input ENUM_ENTRY_MODE   EntryMode                = ENTRY_ON_BREAK_TOUCH;
input ENUM_SL_MODE      SLMode                   = SL_MODE_ATR;
input ENUM_TP_MODE      TPMode                   = TP_MODE_RR;
input double            RiskReward               = 1.5;
input bool              IncludeCommissionsInRisk = true;
input double            CommissionPerLot         = 0.0;
input string            TradingHours             = "07:00-22:00";
input bool              InpUseSpreadFilter       = true;
input double            InpMaxSpreadPoints       = 60;
input bool              InpUseRolloverBlock      = true;
input string            InpRolloverBlockHours    = "23:50-00:10";
input bool              InpUseWaitAfterNewD1     = false;
input int               InpWaitAfterNewD1Seconds = 120;
input bool              InpUseGapFilter          = false;
input double            InpMaxGapPoints          = 200;
input bool              InpSkipDayOnGap          = true;
input bool              InpUseSlippageControl    = true;
input int               InpSlippagePoints        = 30;

input bool              ShowPDH                  = true;
input bool              ShowPDL                  = true;
input bool              ShowPWH                  = true;
input bool              ShowPWL                  = true;
input bool              TradePDH_Enabled         = true;
input bool              TradePDL_Enabled         = true;
input bool              TradePWH_Enabled         = true;
input bool              TradePWL_Enabled         = true;

input ENUM_TIMEFRAMES   ATRTimeframe             = PERIOD_H1;
input int               ATRPeriod                = 14;
input double            ATRMultiplier            = 1.8;
input int               FixedSLPoints            = 500;
input int               FixedTPPoints            = 750;
input double            BufferPoints             = 10.0;
input bool              PlotLevels               = true;
input int               NewsRefreshMinutes       = 15;
input bool              TimeStop_Enabled         = true;
input int               TimeStop_MaxMinutes      = 90;

input bool              LockProfit_Enabled       = true;
input double            LockProfit_TriggerPoints = 120.0;
input double            LockProfit_LockPoints    = 20.0;
input bool              LockProfit_UseBEPlus     = true;
input bool              TrailingStop_Enabled     = true;
input bool              TrailingAfterLock_Only   = true;
input double            TrailingDistancePoints   = 100.0;
input bool              InpUseHoldAfterEntry     = false;
input int               InpHoldSecondsAfterEntry = 30;

input color             ChartBackgroundColor     = clrWhite;
input color             ChartForegroundColor     = clrBlack;
input color             ChartGridColor           = clrLightGray;
input color             ChartBullCandleColor     = clrGreen;
input color             ChartBearCandleColor     = clrRed;

input bool              NewsFilterEnabled        = true;
input int               NewsWindowBeforeMinutes  = 30;
input int               NewsWindowAfterMinutes   = 30;
input string            NewsImpactAllowed        = "High";
input bool              LogNewsDecisions         = true;

CTrade                  trade;

NewsEvent               g_newsEvents[];
datetime                g_lastNewsDownload       = 0;

double                  g_PDH = 0.0;
double                  g_PDL = 0.0;
double                  g_PWH = 0.0;
double                  g_PWL = 0.0;

bool                    g_PDHTradeExecuted = false;
bool                    g_PDLTradeExecuted = false;
bool                    g_PWHTradeExecuted = false;
bool                    g_PWLTradeExecuted = false;
bool                    g_rolloverWasBlocking = false;

datetime                g_lastDailyReference = 0;
datetime                g_lastWeeklyReference = 0;
datetime                g_lastD1OpenTime = 0;
bool                    g_skipTodayEntries = false;

datetime                g_lastBarSignalTime[4];

int                     g_tradingStartMinutes = -1;
int                     g_tradingEndMinutes   = -1;
int                     g_rolloverStartMinutes = -1;
int                     g_rolloverEndMinutes   = -1;

int                     g_atrHandle           = INVALID_HANDLE;
double                  g_lastMarginRequired  = 0.0;
double                  g_lastMarginFree      = 0.0;

const string            ECON_CALENDAR_URL      = "http://nfs.faireconomy.media/ff_calendar_thisweek.xml";

//--- helper forward declarations
void   ApplyChartStyle();
void   UpdateTradingHours();
void   UpdateRolloverHours();
bool   ParseTradingHours(const string hours, int &startMinutes, int &endMinutes);
bool   IsMinutesInWindow(const int minutes, const int startMinutes, const int endMinutes);
void   RefreshLevels(bool forceDaily, bool forceWeekly);
void   UpdateDailyLevels();
void   UpdateWeeklyLevels();
void   ResetDailyFlags();
void   ResetWeeklyFlags();
void   UpdateLevelObjects();
void   UpdateLevelObject(const string name, double price, color clr, ENUM_LINE_STYLE style);
void   DeleteLevelObjects();
void   CheckBreakouts();
bool   CheckTradingWindow();
bool   ShouldBlockForNews();
void   UpdateDailyEntryControls(bool force);
bool   ShouldBlockNewEntries();
bool   ExecuteTrade(const string levelName, bool isBuy, double levelPrice, bool &flag);
double ClampVolumeByMargin(bool isBuy, double requestedVolume, double price);
double CalculateStopDistancePoints();
double CalculateTakeProfitDistancePoints(double stopDistancePoints);
double CalculateVolume(double riskDistance);
double CalculateVolumeFromStopLoss(bool isBuy, double entryPrice, double stopLossPrice);
bool   IsValidSLTP(bool isBuy, double sl, double tp, double bid, double ask);
bool   RespectsStopsAndFreeze(bool isBuy, double sl, double bid, double ask, double point, int stopLevelPts, int freezeLevelPts);
bool   ImpactAllowed(const string impact);
bool   MatchesSymbolCurrencies(const string symbol, const string eventCurrency);
bool   IsHighImpactNewsNear(int beforeMinutes, int afterMinutes);
void   DownloadNews(bool force);
void   ParseNewsXML(const string xml);
string ExtractTagValue(const string &source, const string &tag);
string ToUpper(const string text);
string Trim(const string text);
string NormalizeSymbol(const string symbol);
void   Log(const string message);
void   ApplyTimeBasedExit();
void   ApplyLockProfitAndTrailing();

double ClampVolumeByMargin(bool isBuy, double requestedVolume, double price)
  {
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   double clampedVolume = requestedVolume;

   if(maxLot > 0)
      clampedVolume = MathMin(clampedVolume, maxLot);

   int precision = 2;
   if(step > 0)
     {
      double logValue = -MathLog10(step);
      if(MathIsValidNumber(logValue))
        {
         precision = (int)MathRound(logValue);
         if(precision < 0)
            precision = 2;
        }
     }

   if(step > 0)
      clampedVolume = MathFloor(clampedVolume / step + 0.0000001) * step;

   if(minLot > 0 && clampedVolume < minLot)
     {
      g_lastMarginFree = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      g_lastMarginRequired = 0.0;
      return(0.0);
     }

   clampedVolume = NormalizeDouble(clampedVolume, precision);

   g_lastMarginFree = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

   double requiredMargin = 0.0;
   ENUM_ORDER_TYPE orderType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcMargin(orderType, _Symbol, clampedVolume, price, requiredMargin))
     {
      g_lastMarginRequired = 0.0;
      return(0.0);
     }

   while(requiredMargin > g_lastMarginFree)
     {
      if(step <= 0.0)
         break;

      clampedVolume = MathFloor((clampedVolume - step) / step + 0.0000001) * step;
      if(minLot > 0 && clampedVolume < minLot)
         break;

      clampedVolume = NormalizeDouble(clampedVolume, precision);

      if(!OrderCalcMargin(orderType, _Symbol, clampedVolume, price, requiredMargin))
        {
         g_lastMarginRequired = 0.0;
         return(0.0);
        }
     }

   g_lastMarginRequired = requiredMargin;

   if(requiredMargin > g_lastMarginFree)
      return(0.0);
   if(minLot > 0 && clampedVolume < minLot)
      return(0.0);
   if(clampedVolume <= 0.0)
      return(0.0);

   return(clampedVolume);
  }

bool IsValidSLTP(bool isBuy, double sl, double tp, double bid, double ask)
  {
   if(sl <= 0.0)
      return(false);

   if(isBuy)
     {
      if(sl >= bid)
         return(false);
      if(tp > 0.0 && tp <= bid)
         return(false);
     }
   else
     {
      if(sl <= ask)
         return(false);
      if(tp > 0.0 && tp >= ask)
         return(false);
     }

   return(true);
  }

bool RespectsStopsAndFreeze(bool isBuy, double sl, double bid, double ask, double point, int stopLevelPts, int freezeLevelPts)
  {
   if(sl <= 0.0)
      return(false);

   double distance = isBuy ? (bid - sl) : (sl - ask);

   if(stopLevelPts > 0 && distance < stopLevelPts * point)
      return(false);

   if(freezeLevelPts > 0 && distance < freezeLevelPts * point)
      return(false);

   return(true);
  }

//--- initialization
int OnInit()
  {
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(10);
   ApplyChartStyle();
   UpdateTradingHours();
   UpdateRolloverHours();
   ArrayInitialize(g_lastBarSignalTime, (datetime)0);
   RefreshLevels(true, true);
   UpdateDailyEntryControls(true);

   g_atrHandle = iATR(_Symbol, ATRTimeframe, ATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
     {
      Print("Failed to create ATR handle");
      return(INIT_FAILED);
     }

   EventSetTimer(60);
   DownloadNews(true);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   DeleteLevelObjects();
  }

void OnTimer()
  {
   DownloadNews(false);
  }

void OnTick()
  {
   RefreshLevels(false, false);
   UpdateDailyEntryControls(false);

   if(LockProfit_Enabled || TrailingStop_Enabled)
      ApplyLockProfitAndTrailing();

   ApplyTimeBasedExit();
   if(!ShouldBlockNewEntries())
      CheckBreakouts();
  }

void ApplyChartStyle()
  {
   long chartID = ChartID();
   ChartSetInteger(chartID, CHART_COLOR_BACKGROUND, 0, ChartBackgroundColor);
   ChartSetInteger(chartID, CHART_COLOR_FOREGROUND, 0, ChartForegroundColor);
   ChartSetInteger(chartID, CHART_COLOR_GRID, 0, ChartGridColor);
   ChartSetInteger(chartID, CHART_COLOR_CANDLE_BULL, 0, ChartBullCandleColor);
   ChartSetInteger(chartID, CHART_COLOR_CANDLE_BEAR, 0, ChartBearCandleColor);
   ChartRedraw(chartID);
  }

void UpdateTradingHours()
  {
   if(!ParseTradingHours(TradingHours, g_tradingStartMinutes, g_tradingEndMinutes))
     {
      g_tradingStartMinutes = 0;
      g_tradingEndMinutes   = 24 * 60 - 1;
      Print("TradingHours input invalid, defaulting to 24h trading");
     }
  }

void UpdateRolloverHours()
  {
   if(!ParseTradingHours(InpRolloverBlockHours, g_rolloverStartMinutes, g_rolloverEndMinutes))
     {
      g_rolloverStartMinutes = -1;
      g_rolloverEndMinutes   = -1;
      Print("InpRolloverBlockHours input invalid, rollover block disabled");
     }
  }

bool ParseTradingHours(const string hours, int &startMinutes, int &endMinutes)
  {
   string parts[];
   int    partsCount = StringSplit(hours, (ushort)'-', parts);
   if(partsCount != 2)
      return(false);

   string startStr = Trim(parts[0]);
   string endStr   = Trim(parts[1]);
   if(StringLen(startStr) < 4 || StringLen(endStr) < 4)
      return(false);

   int startHour = (int)StringToInteger(StringSubstr(startStr, 0, 2));
   int startMin  = (int)StringToInteger(StringSubstr(startStr, 3, 2));
   int endHour   = (int)StringToInteger(StringSubstr(endStr, 0, 2));
   int endMin    = (int)StringToInteger(StringSubstr(endStr, 3, 2));

   if(startHour < 0 || startHour > 23 || endHour < 0 || endHour > 23 || startMin < 0 || startMin > 59 || endMin < 0 || endMin > 59)
      return(false);

   startMinutes = startHour * 60 + startMin;
   endMinutes   = endHour * 60 + endMin;
   return(true);
  }

bool IsMinutesInWindow(const int minutes, const int startMinutes, const int endMinutes)
  {
   if(startMinutes < 0 || endMinutes < 0)
      return(false);

   if(startMinutes == endMinutes)
      return(true);

   if(startMinutes <= endMinutes)
      return(minutes >= startMinutes && minutes <= endMinutes);

   if(minutes >= startMinutes || minutes <= endMinutes)
      return(true);

   return(false);
  }

void RefreshLevels(bool forceDaily, bool forceWeekly)
  {
   datetime dailyRef = iTime(_Symbol, PERIOD_D1, 0);
   if(forceDaily || dailyRef != g_lastDailyReference)
     {
      g_lastDailyReference = dailyRef;
      UpdateDailyLevels();
      ResetDailyFlags();
     }

   datetime weeklyRef = iTime(_Symbol, PERIOD_W1, 1);
   if(forceWeekly || weeklyRef != g_lastWeeklyReference)
     {
      g_lastWeeklyReference = weeklyRef;
      UpdateWeeklyLevels();
      ResetWeeklyFlags();
     }

   if(PlotLevels)
      UpdateLevelObjects();
  }

void UpdateDailyLevels()
  {
   g_PDH = iHigh(_Symbol, PERIOD_D1, 1);
   g_PDL = iLow(_Symbol, PERIOD_D1, 1);
  }

void UpdateWeeklyLevels()
  {
   g_PWH = iHigh(_Symbol, PERIOD_W1, 1);
   g_PWL = iLow(_Symbol, PERIOD_W1, 1);
  }

void ResetDailyFlags()
  {
   g_PDHTradeExecuted = false;
   g_PDLTradeExecuted = false;
   g_lastBarSignalTime[0] = 0;
   g_lastBarSignalTime[1] = 0;
  }

void ResetWeeklyFlags()
  {
   g_PWHTradeExecuted = false;
   g_PWLTradeExecuted = false;
   g_lastBarSignalTime[2] = 0;
   g_lastBarSignalTime[3] = 0;
  }

void UpdateLevelObjects()
  {
   if(ShowPDH)
      UpdateLevelObject("PDH_Level", g_PDH, clrDodgerBlue, STYLE_SOLID);
   else
      ObjectDelete(ChartID(), "PDH_Level");

   if(ShowPDL)
      UpdateLevelObject("PDL_Level", g_PDL, clrOrangeRed, STYLE_SOLID);
   else
      ObjectDelete(ChartID(), "PDL_Level");

   if(ShowPWH)
      UpdateLevelObject("PWH_Level", g_PWH, clrMediumSeaGreen, STYLE_DASH);
   else
      ObjectDelete(ChartID(), "PWH_Level");

   if(ShowPWL)
      UpdateLevelObject("PWL_Level", g_PWL, clrCrimson, STYLE_DASH);
   else
      ObjectDelete(ChartID(), "PWL_Level");
  }

void UpdateLevelObject(const string name, double price, color clr, ENUM_LINE_STYLE style)
  {
   if(price <= 0)
      return;

   if(ObjectFind(ChartID(), name) < 0)
     {
      ObjectCreate(ChartID(), name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(ChartID(), name, OBJPROP_COLOR, clr);
      ObjectSetInteger(ChartID(), name, OBJPROP_STYLE, style);
      ObjectSetInteger(ChartID(), name, OBJPROP_WIDTH, 1);
     }
   else
     {
      ObjectSetDouble(ChartID(), name, OBJPROP_PRICE, price);
      ObjectSetInteger(ChartID(), name, OBJPROP_COLOR, clr);
      ObjectSetInteger(ChartID(), name, OBJPROP_STYLE, style);
     }
  }

void DeleteLevelObjects()
  {
   ObjectDelete(ChartID(), "PDH_Level");
   ObjectDelete(ChartID(), "PDL_Level");
   ObjectDelete(ChartID(), "PWH_Level");
   ObjectDelete(ChartID(), "PWL_Level");
  }

int MinutesFromDatetime(const datetime value)
  {
   MqlDateTime dt;
   if(!TimeToStruct(value, dt))
      return(0);
   return(dt.hour * 60 + dt.min);
  }

bool CheckTradingWindow()
  {
   datetime current_time = TimeCurrent();
   int minutes  = MinutesFromDatetime(current_time);
   return(IsMinutesInWindow(minutes, g_tradingStartMinutes, g_tradingEndMinutes));
  }

bool ShouldBlockForNews()
  {
   if(!NewsFilterEnabled)
      return(false);

   bool block = IsHighImpactNewsNear(NewsWindowBeforeMinutes, NewsWindowAfterMinutes);
   if(block && LogNewsDecisions)
      Log("News filter active - trade blocked");
   return(block);
  }

void UpdateDailyEntryControls(bool force)
  {
   datetime currentD1Open = iTime(_Symbol, PERIOD_D1, 0);
   if(currentD1Open == 0)
      return;

   if(!force && currentD1Open == g_lastD1OpenTime)
      return;

   g_lastD1OpenTime = currentD1Open;
   g_skipTodayEntries = false;

   if(!InpUseGapFilter)
      return;

   double todayOpen = iOpen(_Symbol, PERIOD_D1, 0);
   double prevClose = iClose(_Symbol, PERIOD_D1, 1);
   if(todayOpen <= 0.0 || prevClose <= 0.0)
      return;

   double gapPoints = MathAbs(todayOpen - prevClose) / _Point;
   if(gapPoints > InpMaxGapPoints && InpSkipDayOnGap)
      g_skipTodayEntries = true;
  }

bool ShouldBlockNewEntries()
  {
   if(!InpEnableEA)
     {
      Log("Entries blocked: EA disabled");
      return(true);
     }

   if(!CheckTradingWindow())
     {
      Log("Entries blocked: outside trading hours");
      return(true);
     }

   if(NewsFilterEnabled && ShouldBlockForNews())
     {
      Log("Entries blocked: news filter active");
      return(true);
     }

   if(InpUseSpreadFilter)
     {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(ask > 0.0 && bid > 0.0)
        {
         double spreadPoints = (ask - bid) / _Point;
         if(spreadPoints > InpMaxSpreadPoints)
           {
            Log(StringFormat("Entries blocked: spread too high (%.2f > %.2f points)", spreadPoints, InpMaxSpreadPoints));
            return(true);
           }
        }
     }

   if(InpUseRolloverBlock && g_rolloverStartMinutes >= 0 && g_rolloverEndMinutes >= 0)
     {
      int minutes = MinutesFromDatetime(TimeCurrent());
      bool inRollover = IsMinutesInWindow(minutes, g_rolloverStartMinutes, g_rolloverEndMinutes);
      if(inRollover)
        {
         if(!g_rolloverWasBlocking)
           {
            Log("Entries blocked: rollover block STARTED");
            g_rolloverWasBlocking = true;
           }
         return(true);
        }
      if(g_rolloverWasBlocking)
        {
         Log("Entries allowed: rollover block ENDED");
         g_rolloverWasBlocking = false;
        }
     }

   if(InpUseWaitAfterNewD1 && g_lastD1OpenTime > 0)
     {
      if((TimeCurrent() - g_lastD1OpenTime) < InpWaitAfterNewD1Seconds)
        {
         Log("Entries blocked: wait-after-new-D1 active");
         return(true);
        }
     }

   if(InpUseGapFilter && g_skipTodayEntries)
     {
      Log("Entries blocked: gap filter skip-day active");
      return(true);
     }

   return(false);
  }

void CheckBreakouts()
  {
   double buffer = BufferPoints * _Point;

   if(TradePDH_Enabled && !g_PDHTradeExecuted)
     {
      if(EntryMode == ENTRY_ON_BREAK_TOUCH)
        {
         if(SymbolInfoDouble(_Symbol, SYMBOL_ASK) > g_PDH + buffer)
            ExecuteTrade("PDH", true, g_PDH, g_PDHTradeExecuted);
        }
      else
        {
         datetime lastBarTime = iTime(_Symbol, _Period, 1);
         if(lastBarTime != 0 && lastBarTime != g_lastBarSignalTime[0])
           {
            if(iClose(_Symbol, _Period, 1) > g_PDH + buffer)
               if(ExecuteTrade("PDH", true, g_PDH, g_PDHTradeExecuted))
                  g_lastBarSignalTime[0] = lastBarTime;
           }
        }
     }

   if(TradePDL_Enabled && !g_PDLTradeExecuted)
     {
      if(EntryMode == ENTRY_ON_BREAK_TOUCH)
        {
         if(SymbolInfoDouble(_Symbol, SYMBOL_BID) < g_PDL - buffer)
            ExecuteTrade("PDL", false, g_PDL, g_PDLTradeExecuted);
        }
      else
        {
         datetime lastBarTime = iTime(_Symbol, _Period, 1);
         if(lastBarTime != 0 && lastBarTime != g_lastBarSignalTime[1])
           {
            if(iClose(_Symbol, _Period, 1) < g_PDL - buffer)
               if(ExecuteTrade("PDL", false, g_PDL, g_PDLTradeExecuted))
                  g_lastBarSignalTime[1] = lastBarTime;
           }
        }
     }

   if(TradePWH_Enabled && !g_PWHTradeExecuted)
     {
      if(EntryMode == ENTRY_ON_BREAK_TOUCH)
        {
         if(SymbolInfoDouble(_Symbol, SYMBOL_ASK) > g_PWH + buffer)
            ExecuteTrade("PWH", true, g_PWH, g_PWHTradeExecuted);
        }
      else
        {
         datetime lastBarTime = iTime(_Symbol, _Period, 1);
         if(lastBarTime != 0 && lastBarTime != g_lastBarSignalTime[2])
           {
            if(iClose(_Symbol, _Period, 1) > g_PWH + buffer)
               if(ExecuteTrade("PWH", true, g_PWH, g_PWHTradeExecuted))
                  g_lastBarSignalTime[2] = lastBarTime;
           }
        }
     }

   if(TradePWL_Enabled && !g_PWLTradeExecuted)
     {
      if(EntryMode == ENTRY_ON_BREAK_TOUCH)
        {
         if(SymbolInfoDouble(_Symbol, SYMBOL_BID) < g_PWL - buffer)
            ExecuteTrade("PWL", false, g_PWL, g_PWLTradeExecuted);
        }
      else
        {
         datetime lastBarTime = iTime(_Symbol, _Period, 1);
         if(lastBarTime != 0 && lastBarTime != g_lastBarSignalTime[3])
           {
            if(iClose(_Symbol, _Period, 1) < g_PWL - buffer)
               if(ExecuteTrade("PWL", false, g_PWL, g_PWLTradeExecuted))
                  g_lastBarSignalTime[3] = lastBarTime;
           }
        }
     }
  }

bool ExecuteTrade(const string levelName, bool isBuy, double levelPrice, bool &flag)
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
     {
      Print("Failed to get tick data");
      return(false);
     }

   double entryPriceRef = isBuy ? tick.ask : tick.bid;
   double stopDistancePoints = CalculateStopDistancePoints();
   if(stopDistancePoints <= 0)
     {
      Print("Stop distance invalid");
      return(false);
     }

   double tpDistancePoints = CalculateTakeProfitDistancePoints(stopDistancePoints);
   if(tpDistancePoints <= 0)
     {
      Print("TP distance invalid");
      return(false);
     }

   double stopDistancePrice = stopDistancePoints * _Point;
   double tpDistancePrice = tpDistancePoints * _Point;
   double stopLossPriceRef = isBuy ? entryPriceRef - stopDistancePrice : entryPriceRef + stopDistancePrice;
   double takeProfitPriceRef = isBuy ? entryPriceRef + tpDistancePrice : entryPriceRef - tpDistancePrice;

   stopLossPriceRef   = NormalizeDouble(stopLossPriceRef, _Digits);
   takeProfitPriceRef = NormalizeDouble(takeProfitPriceRef, _Digits);

   double volume = 0.0;
   if(InpUseRiskPercent)
      volume = CalculateVolumeFromStopLoss(isBuy, entryPriceRef, stopLossPriceRef);
   else
      volume = CalculateVolume(0.0);
   if(volume <= 0)
     {
      Print("Calculated volume invalid");
      return(false);
     }

   double marginPrice    = isBuy ? tick.ask : tick.bid;
   double clampedVolume  = ClampVolumeByMargin(isBuy, volume, marginPrice);
   if(clampedVolume <= 0.0)
     {
      PrintFormat("Trade skipped due to margin limits (%s %s). free=%.2f required=%.2f wanted=%.2f",
                  _Symbol, isBuy ? "BUY" : "SELL", g_lastMarginFree, g_lastMarginRequired, volume);
      return(false);
     }

   if(MathAbs(clampedVolume - volume) > 0.0000001)
      PrintFormat("Volume adjusted to fit margin limits (%s %s): wanted=%.2f used=%.2f free=%.2f required=%.2f",
                  _Symbol, isBuy ? "BUY" : "SELL", volume, clampedVolume, g_lastMarginFree, g_lastMarginRequired);

   volume = clampedVolume;

   int stopLevelPts = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double stopDist = stopLevelPts * _Point;
   double bid = tick.bid;
   double ask = tick.ask;
   bool stopsValid = true;
   if(isBuy)
     {
      if(!(stopLossPriceRef < (bid - stopDist) && takeProfitPriceRef > (ask + stopDist)))
         stopsValid = false;
     }
   else
     {
      if(!(stopLossPriceRef > (ask + stopDist) && takeProfitPriceRef < (bid - stopDist)))
         stopsValid = false;
     }

   if(!stopsValid)
     {
      PrintFormat("Trade skipped (invalid stops) %s %s: bid=%.5f ask=%.5f stopLevelPts=%d stopDist=%.5f SL=%.5f TP=%.5f",
                  _Symbol,
                  isBuy ? "BUY" : "SELL",
                  bid,
                  ask,
                  stopLevelPts,
                  stopDist,
                  stopLossPriceRef,
                  takeProfitPriceRef);
      return(false);
     }

   if(InpUseSlippageControl)
      trade.SetDeviationInPoints((int)MathMax(0, InpSlippagePoints));
   else
      trade.SetDeviationInPoints(3);

   bool result = false;
   if(isBuy)
      result = trade.Buy(volume, _Symbol, 0.0, 0.0, 0.0, levelName + "_Buy");
   else
      result = trade.Sell(volume, _Symbol, 0.0, 0.0, 0.0, levelName + "_Sell");

   if(result)
     {
      flag = true;
      if(!PositionSelect(_Symbol))
        {
         PrintFormat("Trade placed but position not found for %s (%s).", _Symbol, isBuy ? "BUY" : "SELL");
         return(true);
        }

      long posMagic = (long)PositionGetInteger(POSITION_MAGIC);
      if(posMagic != MagicNumber)
        {
         PrintFormat("Trade placed but magic mismatch for %s (%s).", _Symbol, isBuy ? "BUY" : "SELL");
         return(true);
        }

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double finalSL = isBuy
                       ? openPrice - stopDistancePoints * _Point
                       : openPrice + stopDistancePoints * _Point;
      double finalTP = isBuy
                       ? openPrice + tpDistancePoints * _Point
                       : openPrice - tpDistancePoints * _Point;

      finalSL = NormalizeDouble(finalSL, _Digits);
      finalTP = NormalizeDouble(finalTP, _Digits);

      int freezeLevelPoints = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
      bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      bool canModify = IsValidSLTP(isBuy, finalSL, finalTP, bid, ask)
                       && RespectsStopsAndFreeze(isBuy, finalSL, bid, ask, _Point, stopLevelPts, freezeLevelPoints);

      if(canModify)
        {
         ResetLastError();
         if(!trade.PositionModify(_Symbol, finalSL, finalTP))
           {
            int error = GetLastError();
            PrintFormat("Failed to set SL/TP after fill for %s (%s). Error=%d. %s",
                        _Symbol,
                        isBuy ? "BUY" : "SELL",
                        error,
                        trade.ResultRetcodeDescription());
           }
        }
      else
        {
         PrintFormat("SL/TP modify skipped for %s (%s): invalid or stop/freeze. open=%.5f SL=%.5f TP=%.5f stopLevelPts=%d freezeLevelPts=%d",
                     _Symbol,
                     isBuy ? "BUY" : "SELL",
                     openPrice,
                     finalSL,
                     finalTP,
                     stopLevelPts,
                     freezeLevelPoints);
        }

      Log(StringFormat("Trade placed (%s %s) lots=%.2f level=%.5f open=%.5f SL=%.5f TP=%.5f stopPts=%.1f tpPts=%.1f stopLevelPts=%d freezeLevelPts=%d",
                       _Symbol,
                       levelName,
                       volume,
                       levelPrice,
                       openPrice,
                       finalSL,
                       finalTP,
                       stopDistancePoints,
                       tpDistancePoints,
                       stopLevelPts,
                       freezeLevelPoints));
      return(true);
     }

   Print("Order send failed: ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   return(false);
  }

double CalculateStopDistancePoints()
  {
   if(SLMode == SL_MODE_FIXED_POINTS)
      return(FixedSLPoints);

   double atrBuffer[];
   if(CopyBuffer(g_atrHandle, 0, 1, 1, atrBuffer) != 1)
      return(0.0);

   double atrValue = atrBuffer[0];
   if(atrValue <= 0.0)
      return(0.0);

   double atrPoints = atrValue / _Point;
   return(atrPoints * ATRMultiplier);
  }

double CalculateTakeProfitDistancePoints(double stopDistancePoints)
  {
   if(TPMode == TP_MODE_FIXED_POINTS)
      return(FixedTPPoints);

   return(stopDistancePoints * RiskReward);
  }

double CalculateVolume(double riskDistance)
  {
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double minLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(!InpUseRiskPercent)
     {
      double volume = InpFixedLot;
      if(step > 0)
         volume = MathRound(volume / step) * step;
      if(minLot > 0)
         volume = MathMax(volume, minLot);
      if(maxLot > 0)
         volume = MathMin(volume, maxLot);

      int precision = 2;
      if(step > 0)
        {
         double logValue = -MathLog10(step);
         if(MathIsValidNumber(logValue))
           {
            precision = (int)MathRound(logValue);
            if(precision < 0)
               precision = 2;
           }
        }
      return(NormalizeDouble(volume, precision));
     }

   if(tickValue <= 0 || tickSize <= 0)
      return(0.0);

   double riskAmount = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPercentPerTrade / 100.0;

   double commissionPerLot = 0.0;
   static bool commissionWarningShown = false;
   if(IncludeCommissionsInRisk)
     {
      commissionPerLot = MathMax(CommissionPerLot, 0.0);
      if(commissionPerLot == 0.0 && !commissionWarningShown)
        {
         Print("CommissionPerLot is zero while IncludeCommissionsInRisk is enabled. No commission will be included in risk calculations.");
         commissionWarningShown = true;
        }
     }

   double lossPerLot = riskDistance / tickSize * tickValue;
   double totalPerLot = lossPerLot + commissionPerLot;

   if(totalPerLot <= 0)
      return(0.0);

   double volume = riskAmount / totalPerLot;

   if(step > 0)
     {
      volume = MathFloor(volume / step + 0.0000001) * step;
     }

   if(minLot > 0)
      volume = MathMax(volume, minLot);
   if(maxLot > 0)
      volume = MathMin(volume, maxLot);

   int precision = 2;
   if(step > 0)
     {
      double logValue = -MathLog10(step);
      if(MathIsValidNumber(logValue))
        {
         precision = (int)MathRound(logValue);
         if(precision < 0)
            precision = 2;
        }
     }
   volume = NormalizeDouble(volume, precision);

   return(volume);
  }

double CalculateVolumeFromStopLoss(bool isBuy, double entryPrice, double stopLossPrice)
  {
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   double riskAmount = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPercentPerTrade / 100.0;
   if(riskAmount <= 0.0)
      return(0.0);

   double profit = 0.0;
   ENUM_ORDER_TYPE orderType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcProfit(orderType, _Symbol, 1.0, entryPrice, stopLossPrice, profit))
      return(0.0);

   double lossPerLot = -profit;
   if(lossPerLot <= 0.0)
      return(0.0);

   double commissionPerLot = 0.0;
   static bool commissionWarningShown = false;
   if(IncludeCommissionsInRisk)
     {
      commissionPerLot = MathMax(CommissionPerLot, 0.0);
      if(commissionPerLot == 0.0 && !commissionWarningShown)
        {
         Print("CommissionPerLot is zero while IncludeCommissionsInRisk is enabled. No commission will be included in risk calculations.");
         commissionWarningShown = true;
        }
     }

   double totalPerLot = lossPerLot + commissionPerLot;
   if(totalPerLot <= 0.0)
      return(0.0);

   double volume = riskAmount / totalPerLot;

   if(step > 0.0)
      volume = MathFloor(volume / step + 0.0000001) * step;

   if(minLot > 0)
      volume = MathMax(volume, minLot);
   if(maxLot > 0)
      volume = MathMin(volume, maxLot);

   int precision = 2;
   if(step > 0.0)
     {
      double logValue = -MathLog10(step);
      if(MathIsValidNumber(logValue))
        {
         precision = (int)MathRound(logValue);
         if(precision < 0)
            precision = 2;
        }
     }

   return(NormalizeDouble(volume, precision));
  }

bool IsHighImpactNewsNear(int beforeMinutes, int afterMinutes)
  {
   datetime current_time = TimeCurrent();
   for(int i = 0; i < ArraySize(g_newsEvents); ++i)
     {
      if(!ImpactAllowed(g_newsEvents[i].impact))
         continue;

      if(!MatchesSymbolCurrencies(_Symbol, g_newsEvents[i].currency))
         continue;

      datetime eventTime = g_newsEvents[i].time;
      if(eventTime == 0)
         continue;

      if(current_time <= eventTime)
        {
         if((eventTime - current_time) <= beforeMinutes * 60)
            return(true);
        }
      else
        {
         if((current_time - eventTime) <= afterMinutes * 60)
            return(true);
        }
     }
   return(false);
  }

void DownloadNews(bool force)
  {
   if(!NewsFilterEnabled)
      return;

   datetime current_time = TimeCurrent();
   if(!force && (current_time - g_lastNewsDownload) < NewsRefreshMinutes * 60)
      return;

   uchar requestBody[];
   uchar response[];
   string headers;
   ArrayResize(requestBody, 0);

   ResetLastError();
   int status = WebRequest("GET", ECON_CALENDAR_URL, "", 5000, requestBody, response, headers);
   if(status != 200)
     {
      int error = GetLastError();
      Print("WebRequest failed. Status=", status, " error=", error);
      return;
     }

   string xml = CharArrayToString(response, 0, -1, CP_UTF8);
   if(StringLen(xml) == 0)
     {
      Print("News download returned empty response");
      return;
     }

   ParseNewsXML(xml);
   g_lastNewsDownload = current_time;
  }

void ParseNewsXML(const string xml)
  {
   ArrayResize(g_newsEvents, 0);
   int position = 0;
   while(true)
     {
      int start = StringFind(xml, "<event>", position);
      if(start == -1)
         break;
      int end = StringFind(xml, "</event>", start);
      if(end == -1)
         break;

      int length = end - start;
      if(length <= 0)
         break;

      string block = StringSubstr(xml, start, length);
      position = end + StringLen("</event>");

      string impact = Trim(ExtractTagValue(block, "impact"));
      string country = Trim(ExtractTagValue(block, "country"));
      string timestamp = Trim(ExtractTagValue(block, "timestamp"));

      if(StringLen(timestamp) == 0 || StringLen(country) == 0)
         continue;

      if(!ImpactAllowed(impact))
         continue;

      datetime eventTime = (datetime)StringToInteger(timestamp);
      int newIndex = ArraySize(g_newsEvents);
      ArrayResize(g_newsEvents, newIndex + 1);
      g_newsEvents[newIndex].impact = impact;
      g_newsEvents[newIndex].currency = country;
      g_newsEvents[newIndex].time = eventTime;
     }
  }

string ExtractTagValue(const string &source, const string &tag)
  {
   string openTag = "<" + tag + ">";
   string closeTag = "</" + tag + ">";
   int start = StringFind(source, openTag);
   if(start == -1)
      return("");
   start += StringLen(openTag);
   int end = StringFind(source, closeTag, start);
   if(end == -1)
      return("");
   return(StringSubstr(source, start, end - start));
  }

bool ImpactAllowed(const string impact)
  {
   string allowed = ToUpper(NewsImpactAllowed);
   string eventImpact = ToUpper(impact);
   if(StringLen(eventImpact) == 0)
      return(false);

   string tokens[];
   int    count = StringSplit(allowed, (ushort)',', tokens);
   if(count <= 0)
     {
      string trimmed = Trim(allowed);
      return(eventImpact == trimmed);
     }

   for(int i = 0; i < count; ++i)
     {
      string token = Trim(tokens[i]);
      if(StringLen(token) == 0)
         continue;
      if(eventImpact == token)
         return(true);
     }
   return(false);
  }

string ToUpper(const string text)
  {
   string result = text;
   StringToUpper(result);
   return(result);
  }

string Trim(const string text)
  {
   string s = text;
   StringTrimLeft(s);
   StringTrimRight(s);
   return(s);
  }

string NormalizeSymbol(const string symbol)
  {
   string upper = ToUpper(symbol);
   string result = "";
   for(int i = 0; i < StringLen(upper); ++i)
      {
       int ch = (int)StringGetCharacter(upper, i);
        if(ch >= 'A' && ch <= 'Z')
           result += CharToString((uchar)ch);
      }
   return(result);
  }

bool MatchesSymbolCurrencies(const string symbol, const string eventCurrency)
  {
   string normalized = NormalizeSymbol(symbol);
   if(StringLen(normalized) < 6)
     {
      if(StringLen(normalized) >= 3)
         return(StringSubstr(normalized, 0, 3) == Trim(ToUpper(eventCurrency)));
      return(false);
     }

   string baseCurrency  = StringSubstr(normalized, 0, 3);
   string quoteCurrency = StringSubstr(normalized, 3, 3);
   string event = Trim(ToUpper(eventCurrency));

   if(event == baseCurrency || event == quoteCurrency)
      return(true);

   if(StringLen(normalized) >= 7)
     {
      string third = StringSubstr(normalized, 6, 3);
      if(event == third)
         return(true);
     }

   return(false);
  }

void Log(const string message)
  {
   Print(TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), " ", message);
  }

void ApplyLockProfitAndTrailing()
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return;

   double bid = tick.bid;
   double ask = tick.ask;
   int stopLevelPts = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int freezeLevelPts = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double lockOffsetPoints = LockProfit_UseBEPlus ? LockProfit_LockPoints : 0.0;

   for(int positionIndex = PositionsTotal() - 1; positionIndex >= 0; --positionIndex)
     {
      ulong posTicket = PositionGetTicket(positionIndex);
      if(!PositionSelectByTicket(posTicket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      if(symbol != _Symbol)
         continue;

      long magic = (long)PositionGetInteger(POSITION_MAGIC);
      if(magic != MagicNumber)
         continue;

      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      if(InpUseHoldAfterEntry && openTime > 0)
        {
         if((TimeCurrent() - openTime) < InpHoldSecondsAfterEntry)
            continue;
        }

      ENUM_POSITION_TYPE positionType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      bool isBuy = (positionType == POSITION_TYPE_BUY);
      if(!isBuy && positionType != POSITION_TYPE_SELL)
         continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double oldSL = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double profitPoints = isBuy ? (bid - openPrice) / _Point : (openPrice - ask) / _Point;
      double newSL = oldSL;
      bool lockActive = false;

      if(LockProfit_Enabled && LockProfit_TriggerPoints > 0.0)
        {
         if(profitPoints >= LockProfit_TriggerPoints)
           {
            double desiredSL = isBuy
                               ? openPrice + lockOffsetPoints * _Point
                               : openPrice - lockOffsetPoints * _Point;
            desiredSL = NormalizeDouble(desiredSL, _Digits);
            bool improves = (oldSL == 0.0) ? true : (isBuy ? desiredSL > oldSL : desiredSL < oldSL);

            if(improves)
              {
               bool valid = IsValidSLTP(isBuy, desiredSL, tp, bid, ask)
                            && RespectsStopsAndFreeze(isBuy, desiredSL, bid, ask, _Point, stopLevelPts, freezeLevelPts);
               if(valid)
                 {
                  newSL = desiredSL;
                  lockActive = true;
                 }
               else
                 {
                  PrintFormat("LockProfit skipped for %s (ticket %I64u): invalid or stop/freeze. SL=%.5f TP=%.5f stopLevelPts=%d freezeLevelPts=%d",
                              _Symbol,
                              posTicket,
                              desiredSL,
                              tp,
                              stopLevelPts,
                              freezeLevelPts);
                 }
              }
           }

         if(!lockActive && oldSL > 0.0)
           {
            double lockThreshold = isBuy
                                   ? openPrice + lockOffsetPoints * _Point
                                   : openPrice - lockOffsetPoints * _Point;
            lockActive = isBuy ? (oldSL >= lockThreshold) : (oldSL <= lockThreshold);
           }
        }

      if(TrailingStop_Enabled && TrailingDistancePoints > 0.0)
        {
         if(!TrailingAfterLock_Only || lockActive)
           {
            double desiredTrailSL = isBuy
                                    ? bid - TrailingDistancePoints * _Point
                                    : ask + TrailingDistancePoints * _Point;
            desiredTrailSL = NormalizeDouble(desiredTrailSL, _Digits);
            bool improves = (newSL == 0.0) ? true : (isBuy ? desiredTrailSL > newSL : desiredTrailSL < newSL);

            if(improves)
              {
               bool valid = IsValidSLTP(isBuy, desiredTrailSL, tp, bid, ask)
                            && RespectsStopsAndFreeze(isBuy, desiredTrailSL, bid, ask, _Point, stopLevelPts, freezeLevelPts);
               if(valid)
                 {
                  newSL = desiredTrailSL;
                 }
               else
                 {
                  PrintFormat("Trailing stop skipped for %s (ticket %I64u): invalid or stop/freeze. SL=%.5f TP=%.5f stopLevelPts=%d freezeLevelPts=%d",
                              _Symbol,
                              posTicket,
                              desiredTrailSL,
                              tp,
                              stopLevelPts,
                              freezeLevelPts);
                 }
              }
           }
        }

      if(newSL > 0.0 && newSL != oldSL)
        {
         ResetLastError();
         if(!trade.PositionModify(_Symbol, newSL, tp))
           {
            PrintFormat("Failed to modify position %I64u for %s. SL=%.5f TP=%.5f. %s",
                        posTicket,
                        _Symbol,
                        newSL,
                        tp,
                        trade.ResultRetcodeDescription());
           }
        }
     }
  }

void ApplyTimeBasedExit()
  {
   if(!TimeStop_Enabled || TimeStop_MaxMinutes <= 0)
      return;

   for(int positionIndex = PositionsTotal() - 1; positionIndex >= 0; --positionIndex)
     {
      ulong posTicket = PositionGetTicket(positionIndex);
      if(!PositionSelectByTicket(posTicket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      if(symbol != _Symbol)
         continue;

      long magic = (long)PositionGetInteger(POSITION_MAGIC);
      if(magic != MagicNumber)
         continue;

      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      if(openTime <= 0)
         continue;

      int minutesInTrade = (int)((TimeCurrent() - openTime) / 60);
      if(minutesInTrade < TimeStop_MaxMinutes)
         continue;

      if(trade.PositionClose(posTicket))
         Log(StringFormat("Time-based exit closed %s after %d minutes", _Symbol, minutesInTrade));
      else
         Log(StringFormat("Time-based exit failed to close %s after %d minutes. %s", _Symbol, minutesInTrade, trade.ResultRetcodeDescription()));
     }
  }

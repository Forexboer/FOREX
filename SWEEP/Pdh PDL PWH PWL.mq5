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
   SL_MODE_FIXED_PIPS = 1
  };

enum ENUM_TP_MODE
  {
   TP_MODE_RR = 0,
   TP_MODE_FIXED_PIPS = 1
  };

struct NewsEvent
  {
   datetime time;
   string   currency;
   string   impact;
  };

input int               MagicNumber              = 20241013;
input double            RiskPercentPerTrade      = 1.0;
input ENUM_ENTRY_MODE   EntryMode                = ENTRY_ON_BREAK_TOUCH;
input ENUM_SL_MODE      SLMode                   = SL_MODE_ATR;
input ENUM_TP_MODE      TPMode                   = TP_MODE_RR;
input double            RiskReward               = 1.5;
input bool              IncludeCommissionsInRisk = true;
input double            CommissionPerLot         = 0.0;
input string            TradingHours             = "07:00-22:00";

input ENUM_TIMEFRAMES   ATRTimeframe             = PERIOD_H1;
input int               ATRPeriod                = 14;
input double            ATRMultiplier            = 1.8;
input int               FixedSLPips              = 50;
input int               FixedTPPips              = 75;
input double            BufferPips               = 1.0;
input bool              PlotLevels               = true;
input int               NewsRefreshMinutes       = 15;

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

datetime                g_lastDailyReference = 0;
datetime                g_lastWeeklyReference = 0;

datetime                g_lastBarSignalTime[4];

int                     g_tradingStartMinutes = -1;
int                     g_tradingEndMinutes   = -1;

int                     g_atrHandle           = INVALID_HANDLE;

const string            NEWS_URL               = "http://nfs.faireconomy.media/ff_calendar_thisweek.xml";

//--- helper forward declarations
void   ApplyChartStyle();
void   UpdateTradingHours();
bool   ParseTradingHours(const string hours, int &startMinutes, int &endMinutes);
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
bool   ExecuteTrade(const string levelName, bool isBuy, double levelPrice, bool &flag);
double CalculateStopDistance();
double CalculateTakeProfitDistance(double stopDistance);
double CalculateVolume(double riskDistance);
double GetPipSize();
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

//--- initialization
int OnInit()
  {
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(10);
   ApplyChartStyle();
   UpdateTradingHours();
   ArrayInitialize(g_lastBarSignalTime, (datetime)0);
   RefreshLevels(true, true);

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

   if(!CheckTradingWindow())
      return;

   if(NewsFilterEnabled && ShouldBlockForNews())
      return;

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

void RefreshLevels(bool forceDaily, bool forceWeekly)
  {
   datetime dailyRef = iTime(_Symbol, PERIOD_D1, 1);
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
   UpdateLevelObject("PDH_Level", g_PDH, clrDodgerBlue, STYLE_SOLID);
   UpdateLevelObject("PDL_Level", g_PDL, clrOrangeRed, STYLE_SOLID);
   UpdateLevelObject("PWH_Level", g_PWH, clrMediumSeaGreen, STYLE_DASH);
   UpdateLevelObject("PWL_Level", g_PWL, clrCrimson, STYLE_DASH);
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
   if(g_tradingStartMinutes == g_tradingEndMinutes)
      return(true);

   datetime current_time = TimeCurrent();
   int minutes  = MinutesFromDatetime(current_time);

   if(g_tradingStartMinutes <= g_tradingEndMinutes)
      return(minutes >= g_tradingStartMinutes && minutes <= g_tradingEndMinutes);

   // Overnight window
   if(minutes >= g_tradingStartMinutes || minutes <= g_tradingEndMinutes)
      return(true);

   return(false);
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

void CheckBreakouts()
  {
   double buffer = BufferPips * GetPipSize();

   if(!g_PDHTradeExecuted)
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

   if(!g_PDLTradeExecuted)
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

   if(!g_PWHTradeExecuted)
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

   if(!g_PWLTradeExecuted)
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

   double spread          = (tick.ask - tick.bid);
   double slippage        = 0.5 * spread;
   double entryPrice      = isBuy ? tick.ask + slippage : tick.bid - slippage;

   double stopDistance    = CalculateStopDistance();
   if(stopDistance <= 0)
     {
      Print("Stop distance invalid");
      return(false);
     }

   double tpDistance      = CalculateTakeProfitDistance(stopDistance);
   if(tpDistance <= 0)
     {
      Print("TP distance invalid");
      return(false);
     }

   double riskDistance    = stopDistance + spread + slippage;
   double volume          = CalculateVolume(riskDistance);
   if(volume <= 0)
     {
      Print("Calculated volume invalid");
      return(false);
     }

   double stopLossPrice   = isBuy ? entryPrice - stopDistance - spread : entryPrice + stopDistance + spread;
   double takeProfitPrice = isBuy ? entryPrice + tpDistance : entryPrice - tpDistance;

   stopLossPrice   = NormalizeDouble(stopLossPrice, _Digits);
   takeProfitPrice = NormalizeDouble(takeProfitPrice, _Digits);

   trade.SetDeviationInPoints((int)MathMax(3, MathCeil(spread / _Point)));

   bool result = false;
   if(isBuy)
      result = trade.Buy(volume, _Symbol, 0.0, stopLossPrice, takeProfitPrice, levelName + "_Buy");
   else
      result = trade.Sell(volume, _Symbol, 0.0, stopLossPrice, takeProfitPrice, levelName + "_Sell");

   if(result)
     {
      flag = true;
      Log(StringFormat("Trade placed (%s %s) lots=%.2f level=%.5f SL=%.5f TP=%.5f", _Symbol, levelName, volume, levelPrice, stopLossPrice, takeProfitPrice));
      return(true);
     }

   Print("Order send failed: ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   return(false);
  }

double CalculateStopDistance()
  {
   if(SLMode == SL_MODE_FIXED_PIPS)
      return(FixedSLPips * GetPipSize());

   double atrBuffer[];
   if(CopyBuffer(g_atrHandle, 0, 0, 1, atrBuffer) != 1)
      return(0.0);

   double atrValue = atrBuffer[0];
   return(atrValue * ATRMultiplier);
  }

double CalculateTakeProfitDistance(double stopDistance)
  {
   if(TPMode == TP_MODE_FIXED_PIPS)
      return(FixedTPPips * GetPipSize());

   return(stopDistance * RiskReward);
  }

double CalculateVolume(double riskDistance)
  {
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double minLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(tickValue <= 0 || tickSize <= 0)
      return(0.0);

   double riskAmount = AccountInfoDouble(ACCOUNT_EQUITY) * RiskPercentPerTrade / 100.0;

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

double GetPipSize()
  {
   if(_Digits == 3 || _Digits == 5)
      return(_Point * 10.0);
   if(_Digits == 1)
      return(_Point * 10.0);
   return(_Point);
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
   int status = WebRequest("GET", NEWS_URL, "", 5000, requestBody, response, headers);
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
          result += CharToString(ch);
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

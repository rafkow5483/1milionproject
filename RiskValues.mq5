
#define VERSION "1.0"
#property version VERSION

#define PROJECT_NAME MQLInfoString(MQL_PROGRAM_NAME)

#include <Trade/Trade.mqh>

input double Lots = 1.0;
input double RiskPercent = 2.0; //RiskPercent (0 = Fix)
input int OrderOffsetPoints = 3; // Dystans od high/low w punktach
input bool enableTimePeriod1 = true; // Domyślnie włączone
input bool enableTimePeriod2 = true; // Domyślnie włączone


// Definicja zmiennych input dla czasów startu i końca
input int startHour1 = 6;
input int startMinute1 = 0;
input int endHour1 = 13;
input int endMinute1 = 0;

input int startHour2 = 15;
input int startMinute2 = 0;
input int endHour2 = 22;
input int endMinute2 = 0;

input int OrderDistPoints = 200;
input int TpPoints = 200;
input int SlPoints = 200;
input int TslPoints = 5;
input int TslTriggerPoints = 5;

input ENUM_TIMEFRAMES Timeframe = PERIOD_H1;
input int BarsN = 5;
input int ExpirationMinute = 15;

input int Magic = 111;

CTrade trade;

ulong buyPos, sellPos;
int totalBars;

int OnInit(){
   trade.SetExpertMagicNumber(Magic);
   if(!trade.SetTypeFillingBySymbol(_Symbol)){
      trade.SetTypeFilling(ORDER_FILLING_RETURN);
   }

   static bool isInit = false;
   if(!isInit){
      isInit = true;
      Print(__FUNCTION__," > EA (re)start...");
      Print(__FUNCTION__," > EA version ",VERSION,"...");
       
      for(int i = PositionsTotal()-1; i >= 0; i--){
         CPositionInfo pos;
         if(pos.SelectByIndex(i)){
            if(pos.Magic() != Magic) continue;
            if(pos.Symbol() != _Symbol) continue;

            Print(__FUNCTION__," > Found open position with ticket #",pos.Ticket(),"...");
            if(pos.PositionType() == POSITION_TYPE_BUY) buyPos = pos.Ticket();
            if(pos.PositionType() == POSITION_TYPE_SELL) sellPos = pos.Ticket();
         }
      }

      for(int i = OrdersTotal()-1; i >= 0; i--){
         COrderInfo order;
         if(order.SelectByIndex(i)){
            if(order.Magic() != Magic) continue;
            if(order.Symbol() != _Symbol) continue;

            Print(__FUNCTION__," > Found pending order with ticket #",order.Ticket(),"...");
            if(order.OrderType() == ORDER_TYPE_BUY_STOP) buyPos = order.Ticket();
            if(order.OrderType() == ORDER_TYPE_SELL_STOP) sellPos = order.Ticket();
         }
      }
   }

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason){

}

// Funkcja sprawdzająca, czy obecny czas mieści się w określonym przedziale
bool IsTimeToTrade() {
    MqlDateTime time;
    TimeToStruct(TimeCurrent(), time);

    // Konwersja do minut od północy
    int startTime1 = startHour1 * 60 + startMinute1;
    int endTime1 = endHour1 * 60 + endMinute1;
    int startTime2 = startHour2 * 60 + startMinute2;
    int endTime2 = endHour2 * 60 + endMinute2;
    int currentTime = time.hour * 60 + time.min;

    bool inTimePeriod1 = (currentTime >= startTime1 && currentTime <= endTime1) && enableTimePeriod1;
    bool inTimePeriod2 = (currentTime >= startTime2 && currentTime <= endTime2) && enableTimePeriod2;

    // Sprawdzenie czy bieżący czas mieści się w aktywnych przedziałach
    return inTimePeriod1 || inTimePeriod2;
}


void OnTick(){

   // Sprawdzenie, czy jest odpowiedni czas na handel
   if(!IsTimeToTrade()) return;

   processPos(buyPos);
   processPos(sellPos);

   int bars = iBars(_Symbol,Timeframe);
   if(totalBars != bars){
      totalBars = bars;
      
      // Zmienne do przechowywania wyszukiwanych wartości high i low
      double high = findHigh();
      double low = findLow();

      // Warunki wywołania funkcji executeBuy i executeSell
      if(buyPos <= 0 && high > 0){
         executeBuy(high);
      }
      
      if(sellPos <= 0 && low > 0){
         executeSell(low);
      }
   }
}


void  OnTradeTransaction(
   const MqlTradeTransaction&    trans,
   const MqlTradeRequest&        request,
   const MqlTradeResult&         result
   ){
   
   if(trans.type == TRADE_TRANSACTION_ORDER_ADD){
      COrderInfo order;
      if(order.Select(trans.order)){
         if(order.Magic() == Magic){
            if(order.OrderType() == ORDER_TYPE_BUY_STOP){
               buyPos = order.Ticket();
            }else if(order.OrderType() == ORDER_TYPE_SELL_STOP){
               sellPos = order.Ticket();
            }
         }
      }
   }
}

void processPos(ulong &posTicket){
   if(posTicket <= 0) return;
   if(OrderSelect(posTicket)) return;
   
   CPositionInfo pos;
   if(!pos.SelectByTicket(posTicket)){
      posTicket = 0;
      return;
   } else {
      double newSl = 0;
      double profitPoints = 0;

      if(pos.PositionType() == POSITION_TYPE_BUY){
         double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
         profitPoints = (bid - pos.OpenPrice()) / _Point;

         if(profitPoints > TslTriggerPoints){
            newSl = pos.OpenPrice() + _Point; // Ustawienie SL na 1 punkt zysku
            newSl = bid - TslPoints * _Point; // Przesunięcie SL o TslPoints dla dalszego zabezpieczania zysku
            newSl = NormalizeDouble(newSl, _Digits);
            
            if(newSl > pos.StopLoss()){
               trade.PositionModify(pos.Ticket(), newSl, pos.TakeProfit());
            }
         }
      } else if(pos.PositionType() == POSITION_TYPE_SELL){
         double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
         profitPoints = (pos.OpenPrice() - ask) / _Point;

         if(profitPoints > TslTriggerPoints){
            newSl = pos.OpenPrice() - _Point; // Ustawienie SL na 1 punkt zysku
            newSl = ask + TslPoints * _Point; // Przesunięcie SL o TslPoints dla dalszego zabezpieczania zysku
            newSl = NormalizeDouble(newSl, _Digits);
            
            if(newSl < pos.StopLoss() || pos.StopLoss() == 0){
               trade.PositionModify(pos.Ticket(), newSl, pos.TakeProfit());
            }
         }
      }
   }
}


void executeBuy(double high){
   double entry = NormalizeDouble(high - OrderOffsetPoints * _Point, _Digits); 
   
   double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   if(ask > entry - OrderDistPoints * _Point) return;
   
   double tp = entry + TpPoints * _Point;
   tp = NormalizeDouble(tp,_Digits);
   
   double sl = entry - SlPoints * _Point;
   sl = NormalizeDouble(sl,_Digits);

   double lots = Lots;
   if(RiskPercent > 0) lots = calcLots(entry-sl);
   
   datetime expiration = iTime(_Symbol,Timeframe,0) + ExpirationMinute * PeriodSeconds(PERIOD_M1);

   trade.BuyStop(lots,entry,_Symbol,sl,tp,ORDER_TIME_SPECIFIED,expiration);
   
   buyPos = trade.ResultOrder();
}

 void executeSell(double low){
   double entry = NormalizeDouble(low + OrderOffsetPoints * _Point, _Digits);   

   double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(bid < entry + OrderDistPoints * _Point) return;

   double tp = entry - TpPoints * _Point;
   tp = NormalizeDouble(tp,_Digits);
   
   double sl = entry + SlPoints * _Point;
   sl = NormalizeDouble(sl,_Digits);
   
   double lots = Lots;
   if(RiskPercent > 0) lots = calcLots(sl-entry);
  
   datetime expiration = iTime(_Symbol,Timeframe,0) + ExpirationMinute * PeriodSeconds(PERIOD_M1);

   trade.SellStop(lots,entry,_Symbol,sl,tp,ORDER_TIME_SPECIFIED,expiration);
   
   sellPos = trade.ResultOrder();
}

double calcLots(double slPoints){
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100;
   
   double ticksize = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double tickvalue = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double lotstep = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   
   double moneyPerLotstep = slPoints / ticksize * tickvalue * lotstep;   
   double lots = MathFloor(risk / moneyPerLotstep) * lotstep;
   
   lots = MathMin(lots,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX));
   lots = MathMax(lots,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN));
   
   return lots;
}

double findHigh(){
   double highestHigh = 0;
   for(int i = 0; i < 200; i++){
      double high = iHigh(_Symbol, Timeframe, i);
      if(i > BarsN && iHighest(_Symbol, Timeframe, MODE_HIGH, BarsN*3+1, i-BarsN) == i){
         // Sprawdzanie, czy obecna wartość high minus dystans jest większa niż dotychczasowe najwyższe high
         if(high - OrderOffsetPoints * _Point > highestHigh){
            highestHigh = high;
         }
      }
   }
   // Jeśli nie znaleziono nowego high, zwróć -1
   if(highestHigh == 0){
      return -1;
   }
   // Zwróć znalezioną najwyższą wartość z uwzględnieniem dystansu
   return highestHigh - OrderOffsetPoints * _Point;
}

double findLow(){
   double lowestLow = DBL_MAX;
   for(int i = 0; i < 200; i++){
      double low = iLow(_Symbol, Timeframe, i);
      if(i > BarsN && iLowest(_Symbol, Timeframe, MODE_LOW, BarsN*3+1, i-BarsN) == i){
         // Sprawdzanie, czy obecna wartość low plus dystans jest mniejsza niż dotychczasowe najniższe low
         if(low + OrderOffsetPoints * _Point < lowestLow){
            lowestLow = low;
         }
      }
   }
   // Jeśli nie znaleziono nowego low, zwróć -1
   if(lowestLow == DBL_MAX){
      return -1;
   }
   // Zwróć znalezioną najniższą wartość z uwzględnieniem dystansu
   return lowestLow + OrderOffsetPoints * _Point;
}

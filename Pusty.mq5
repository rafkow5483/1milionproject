/*
   BuySellEma.mq5
   Copyright 2022, Orchard Forex
   https://www.orchardforex.com
*/

#property copyright "Copyright 2022, Orchard Forex"
#property link "https://www.orchardforex.com"
#property version "1.00"



//
//	Inputs
//
//
//	Fast MA
//
input int                InpFastMABars         = 20;          // Fast MA Bars
input ENUM_MA_METHOD     InpFastMAMethod       = MODE_EMA;    // Fast MA Method
input ENUM_APPLIED_PRICE InpFastMAAppliedPrice = PRICE_CLOSE; // Fast MA Applied Price

//
//	Slow MA
//
input int                InpSlowMABars         = 50;          // Slow MA Bars
input ENUM_MA_METHOD     InpSlowMAMethod       = MODE_EMA;    // Slow MA Method
input ENUM_APPLIED_PRICE InpSlowMAAppliedPrice = PRICE_CLOSE; // Slow MA Applied Price
input int                InpSlowMAShift        = 0;           // Slow MA shift

//
//	The basic expert uses fixed take profit, stop loss and order size
//
input double             InpOrderSize          = 0.01;  // Order size in lots
input double             InpTakeProfitPips     = 100.0; // Take profit in pips
input double             InpStopLossPips       = 100.0; // Stop loss in pips
input double             InpTrailingStopPips   = 20.0;  // Trailing stop pips

//
//	Trades also have a magic number and a comment
//
input int                InpMagic              = 222222;                     // Magic number
input string             InpTradeComment       = "Example MA Cross with TS"; // Trade comment

// Some global values
double                   TakeProfit;
double                   StopLoss;
double                   TrailingStop;

//
//	Pips, points conversion
//
double                   PipSize() { return ( PipSize( Symbol() ) ); }
double                   PipSize( string symbol ) {
   double point  = SymbolInfoDouble( symbol, SYMBOL_POINT );
   int    digits = ( int )SymbolInfoInteger( symbol, SYMBOL_DIGITS );
   return ( ( ( digits % 2 ) == 1 ) ? point * 10 : point );
}

double PipsToDouble( double pips ) { return ( pips * PipSize( Symbol() ) ); }
double PipsToDouble( double pips, string symbol ) { return ( pips * PipSize( symbol ) ); }

bool   IsMarketOpen() { return IsMarketOpen( Symbol(), TimeCurrent() ); }
bool   IsMarketOpen( datetime time ) { return IsMarketOpen( Symbol(), time ); }
bool   IsMarketOpen( string symbol, datetime time ) {

   static string   lastSymbol   = "";
   static bool     isOpen       = false;
   static datetime sessionStart = 0;
   static datetime sessionEnd   = 0;

   if ( lastSymbol == symbol && sessionEnd > sessionStart ) {
      if ( ( isOpen && time >= sessionStart && time <= sessionEnd ) || ( !isOpen && time > sessionStart && time < sessionEnd ) ) return isOpen;
   }

   lastSymbol = symbol;

   MqlDateTime mtime;
   TimeToStruct( time, mtime );
   datetime seconds  = mtime.hour * 3600 + mtime.min * 60 + mtime.sec;

   mtime.hour        = 0;
   mtime.min         = 0;
   mtime.sec         = 0;
   datetime dayStart = StructToTime( mtime );
   datetime dayEnd   = dayStart + 86400;

   datetime fromTime;
   datetime toTime;

   sessionStart = dayStart;
   sessionEnd   = dayEnd;

   for ( int session = 0;; session++ ) {

      if ( !SymbolInfoSessionTrade( symbol, ( ENUM_DAY_OF_WEEK )mtime.day_of_week, session, fromTime, toTime ) ) {
         sessionEnd = dayEnd;
         isOpen     = false;
         return isOpen;
      }

      if ( seconds < fromTime ) { // not inside a session
         sessionEnd = dayStart + fromTime;
         isOpen     = false;
         return isOpen;
      }

      if ( seconds > toTime ) { // maybe a later session
         sessionStart = dayStart + toTime;
         continue;
      }

      // at this point must be inside a session
      sessionStart = dayStart + fromTime;
      sessionEnd   = dayStart + toTime;
      isOpen       = true;
      return isOpen;
   }

   return false;
}

bool IsNewBar( bool first_call = false ) {

   static bool result = false;
   if ( !first_call ) return ( result );

   static datetime previous_time = 0;
   datetime        current_time  = iTime( Symbol(), Period(), 0 );
   result                        = false;
   if ( previous_time != current_time ) {
      previous_time = current_time;
      result        = true;
   }
   return ( result );
}

// Bring in the trade class to make trading easier
#include <Trade/Trade.mqh>
CTrade        Trade;
CPositionInfo Position;

// Handles and buffers for the moving averages
int           FastHandle;
double        FastBuffer[];
int           SlowHandle;
double        SlowBuffer[];

;
//
//	Initialisation
//
int OnInit() {

   TakeProfit   = PipsToDouble( InpTakeProfitPips );
   StopLoss     = PipsToDouble( InpStopLossPips );
   TrailingStop = PipsToDouble( InpTrailingStopPips );

   Trade.SetExpertMagicNumber( InpMagic );

   FastHandle = iMA( Symbol(), Period(), InpFastMABars, 0, InpFastMAMethod, InpFastMAAppliedPrice );
   ArraySetAsSeries( FastBuffer, true );

   //	I could use the shift here but I won't
   SlowHandle = iMA( Symbol(), Period(), InpSlowMABars, 0, InpSlowMAMethod, InpSlowMAAppliedPrice );
   ArraySetAsSeries( SlowBuffer, true );

   if ( FastHandle == INVALID_HANDLE || SlowHandle == INVALID_HANDLE ) {
      Print( "Error creating handles to moving averages" );
      return INIT_FAILED;
   }

   // In case of starting the expert mid bar block the new bar result
   //	https://youtu.be/XHJPpvI2h50
   IsNewBar( true );

   return ( INIT_SUCCEEDED );
}

void OnDeinit( const int reason ) {
   IndicatorRelease( FastHandle );
   IndicatorRelease( SlowHandle );
}


// Funkcja sprawdzająca, czy obecny czas mieści się w określonym przedziale
bool IsTimeToTrade() {
   MqlDateTime time;
   TimeToStruct(TimeCurrent(), time);

   // Ustawianie godzin rozpoczęcia i zakończenia handlu
   int startHour = 10;
   int startMinute = 30;
   int endHour = 14;
   int endMinute = 30;

   // Konwersja do minut od północy
   int startTime = startHour * 60 + startMinute;
   int endTime = endHour * 60 + endMinute;
   int currentTime = time.hour * 60 + time.min;

   return (currentTime >= startTime && currentTime <= endTime);


void OnTick() {

   // This expert looks for a cross of fast ma over slow ma
   //	That can happen mid bar but if you check mid bar then
   //		the price often reverses and goes back and forth many times
   //	I prefer to wait for the bar to close
   //	That means I only need to run once per bar and I am looking
   //		at values from bar 1, not 0

   // Quick check if trading is possible
   if ( !IsTradeAllowed() ) return;
   // Also exit if the market may be closed
   //	https://youtu.be/GejPt5odJow
   if ( !IsMarketOpen() ) return;

   // I want to apply the trailing stop to every tick
   // so it goes here before the new bar test
   if ( TrailingStop > 0 ) ApplyTrailingStop();

   //	Next exit if this is not a new bar
   //	https://youtu.be/XHJPpvI2h50
   if ( !IsNewBar( true ) ) return;

   // Get the fast and slow ma values for bar 1 and bar 2
   if ( CopyBuffer( FastHandle, 0, 0, 3, FastBuffer ) < 3 ) {
      Print( "Insufficient results from fast MA" );
      return;
   }
   // This is where I apply the shift
   if ( CopyBuffer( SlowHandle, 0, InpSlowMAShift, 3, SlowBuffer ) < 3 ) {
      Print( "Insufficient results from slow MA" );
      return;
   }

// Sprawdzenie, czy jest to odpowiedni czas do handlu
   if (!IsTimeToTrade()) return;

   // Compare, if Fast 1 is above Slow 1 and Fast 2 is not above Slow 2 then
   // there is a cross up
   if ( ( FastBuffer[1] > SlowBuffer[1] ) && !( FastBuffer[2] > SlowBuffer[2] ) ) {
      OpenTrade( ORDER_TYPE_BUY );
   }
   
   if ( ( FastBuffer[1] < SlowBuffer[1] ) && !( FastBuffer[2] < SlowBuffer[2] ) ) {
      OpenTrade( ORDER_TYPE_SELL );
   }


   //
}

void OpenTrade( ENUM_ORDER_TYPE type ) {

   double price;
   double sl;
   double tp;

   if ( type == ORDER_TYPE_BUY ) {
      price = SymbolInfoDouble( Symbol(), SYMBOL_ASK );
      sl    = price - StopLoss;
      tp    = price + TakeProfit;
   }
   else {
      price = SymbolInfoDouble( Symbol(), SYMBOL_BID );
      sl    = price + StopLoss;
      tp    = price - TakeProfit;
   }

   price = NormalizeDouble( price, Digits() );
   sl    = NormalizeDouble( sl, Digits() );
   tp    = NormalizeDouble( tp, Digits() );

   //-	8.	Allow tp and sl = 0
   if ( StopLoss == 0 ) sl = 0;
   if ( TakeProfit == 0 ) tp = 0;

   if ( !Trade.PositionOpen( Symbol(), type, InpOrderSize, price, sl, tp, InpTradeComment ) ) {
      Print( "Open failed for %s, %s, price=%f, sl=%f, tp=%f", Symbol(), EnumToString( type ), price, sl, tp );
   }
}

bool IsTradeAllowed() {

   return ( ( bool )MQLInfoInteger( MQL_TRADE_ALLOWED )              // Trading allowed in input dialog
            && ( bool )TerminalInfoInteger( TERMINAL_TRADE_ALLOWED ) // Trading allowed in terminal
            && ( bool )AccountInfoInteger( ACCOUNT_TRADE_ALLOWED )   // Is account able to trade, not locked out
            && ( bool )AccountInfoInteger( ACCOUNT_TRADE_EXPERT )    // Is account able to auto trade
   );
}

//-	9.	The trailing stop function
void ApplyTrailingStop() {

   double ask                   = SymbolInfoDouble( Symbol(), SYMBOL_ASK );
   double bid                   = SymbolInfoDouble( Symbol(), SYMBOL_BID );
   double buyTrailingStopPrice  = ask - TrailingStop;
   double sellTrailingStopPrice = bid + TrailingStop;
   int    err;

   //	https://youtu.be/u9qFvriLQnU
   // For hedging accounts, not netting
   for ( int i = PositionsTotal() - 1; i >= 0; i-- ) {
      ulong ticket = PositionGetTicket( i );
      if ( !PositionSelectByTicket( ticket ) ) continue;
      if ( Position.Symbol() != Symbol() || Position.Magic() != InpMagic ) continue;

      if ( Position.PositionType() == POSITION_TYPE_BUY && buyTrailingStopPrice > Position.PriceOpen() &&
           ( Position.StopLoss() == 0 || buyTrailingStopPrice > Position.StopLoss() ) ) {
         ResetLastError();
         if ( !Trade.PositionModify( ticket, buyTrailingStopPrice, Position.TakeProfit() ) ) {
            err = GetLastError();
            PrintFormat( "Failed to update ts on ticket %I64u to %f, err=%i", ticket, buyTrailingStopPrice, err );
         }
      }

      if ( Position.PositionType() == POSITION_TYPE_SELL && sellTrailingStopPrice < Position.PriceOpen() &&
           ( Position.StopLoss() == 0 || sellTrailingStopPrice < Position.StopLoss() ) ) {
         ResetLastError();
         if ( !Trade.PositionModify( ticket, sellTrailingStopPrice, Position.TakeProfit() ) ) {
            err = GetLastError();
            PrintFormat( "Failed to update ts on ticket %I64u to %f, err=%i", ticket, sellTrailingStopPrice, err );
            }
        }
   }
}



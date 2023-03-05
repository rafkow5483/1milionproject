#property copyright "Copyright 2012-2020, Orchard Forex"
#property link "https://www.orchardforex.com"
#property version "1.00"
#property strict

//
//	Compatibility Functions
//
void OnStart() {

   Test( "EURJPY" );
   Test( "EURGBP" );
   Test( "AUDNZD" );
   Test( "XAUUSD" );
}

void Test( string symbol ) {

   PrintFormat( "Base currency is %s", AccountInfoString( ACCOUNT_CURRENCY ) );
   PrintFormat( "Testing for symbol %s", symbol );

   double pointValue = PointValue( symbol );

   PrintFormat( "ValuePerPoint for %s is %f", symbol, pointValue );

   //	Situation 1, fixed lots and stop loss points, how much is at risk
   double riskPoints = 75; //	0.075 for EURJPY, 0.00075 for EURGBP and AUDNZD
   double riskLots   = 0.60;
   double riskAmount = pointValue * riskLots * riskPoints;
   PrintFormat( "Risk amount for %s trading %f lots with risk of %f points is %f",
                symbol, riskLots, riskPoints, riskAmount );

   //	Situation 2, fixed lots and risk amount, how many points to set stop loss
   riskLots   = 0.60;
   riskAmount = 100;
   riskPoints = riskAmount / ( pointValue * riskLots );
   PrintFormat( "Risk points for %s trading %f lots placing %f at risk is %f",
                symbol, riskLots, riskAmount, riskPoints );

   //	Situation 3, fixed risk amount and stop loss, how many lots to trade
   riskAmount = 100;
   riskPoints = 50;
   riskLots   = riskAmount / ( pointValue * riskPoints );
   PrintFormat( "Risk lots for %s value %f and stop loss at %f points is %f",
                symbol, riskAmount, riskPoints, riskLots );
}

double PointValue( string symbol ) {

   double tickSize      = SymbolInfoDouble( symbol, SYMBOL_TRADE_TICK_SIZE );
   double tickValue     = SymbolInfoDouble( symbol, SYMBOL_TRADE_TICK_SIZE );
   double point         = SymbolInfoDouble( symbol, SYMBOL_POINT );
   double ticksPerPoint = tickSize / point;
   double pointValue    = tickValue / ticksPerPoint;

   PrintFormat( "tickSize=%f, tickValue=%f, point=%f, ticksPerPoint=%f, pointValue=%f",
                tickSize, tickValue, point, ticksPerPoint, pointValue );

   return ( pointValue );
}

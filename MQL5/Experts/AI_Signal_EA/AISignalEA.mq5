//+------------------------------------------------------------------+
//|                                                   AISignalEA.mq5 |
//|                                  Copyright 2024, AI Signal Server|
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, AI Signal Server"
#property link      "https://github.com/bizkut/AI-Telegram-Signal"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include "JAson.mqh"

// Inputs
input string   InpServerHost = "127.0.0.1";  // Server Host (localhost)
input int      InpServerPort = 8888;         // Server Port
input int      InpMagic      = 123456;       // Magic Number
input double   InpFixedLot   = 0.01;         // Fixed Lot Size
input int      InpSlippage   = 20;           // Max Slippage (points)
input int      InpPendingExpiry = 30;        // Pending Order Expiry (minutes)

// Globals
int socket = INVALID_HANDLE;
CTrade trade;
string partial_data = "";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippage);
   
   EventSetTimer(1); // Check socket every second
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(socket != INVALID_HANDLE) SocketClose(socket);
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
   // 1. Connect if needed
   if(socket == INVALID_HANDLE) {
      socket = SocketCreate();
      if(socket != INVALID_HANDLE) {
         if(!SocketConnect(socket, InpServerHost, InpServerPort, 1000)) {
            Print("Failed to connect to ", InpServerHost, ":", InpServerPort);
            SocketClose(socket);
            socket = INVALID_HANDLE;
            return;
         }
         Print("Connected to Signal Server!");
      } else {
         Print("Failed to create socket");
         return;
      }
   }

   // 2. Read Data
   uint len = SocketIsReadable(socket);
   if(len > 0) {
      char buffer[];
      int rsp_len = SocketRead(socket, buffer, len, 500);
      if(rsp_len > 0) {
         string raw_msg = CharArrayToString(buffer, 0, rsp_len);
         ProcessData(raw_msg);
      }
   }
}

//+------------------------------------------------------------------+
//| Process Incoming Data Stream                                     |
//+------------------------------------------------------------------+
void ProcessData(string data)
{
   // TCP stream might be fragmented or concatenated. 
   // Server sends newline \n as delimiter.
   partial_data += data;
   
   int idx;
   while((idx = StringFind(partial_data, "\n")) >= 0) {
      string json_str = StringSubstr(partial_data, 0, idx);
      partial_data = StringSubstr(partial_data, idx + 1);
      
      if(StringLen(json_str) > 0) {
         ParseAndExecute(json_str);
      }
   }
}

//+------------------------------------------------------------------+
//| Parse JSON and Execute Signal                                    |
//+------------------------------------------------------------------+
void ParseAndExecute(string json_str)
{
   Print("Received Signal: ", json_str);
   
   CJAVal* json = CJAson::Parse(json_str);
   if(json == NULL) {
      Print("Error parsing JSON");
      return;
   }
   
   string action = json["action"].ToStr();
   string symbol = json["symbol"].ToStr();
   
   // Select Symbol for Trade
   if(!SymbolInfoDouble(symbol, SYMBOL_BID, 0)) {
      Print("Symbol not found: ", symbol);
      delete json;
      return;
   }
   
   if(action == "NEW") {
      string type = json["order_type"].ToStr();
      double entry_min = json["entry_min"].ToDbl();
      double entry_max = json["entry_max"].ToDbl();
      double sl = json["sl"].ToDbl();
      
      // Determine TP (First one)
      double tp = 0;
      CJAVal* tp_arr = json["tp"];
      if(tp_arr != NULL && tp_arr.Size() > 0) tp = tp_arr[0].ToDbl();
      
      double current_bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double current_ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      
      // Calculate expiration time for pending orders
      datetime expiry = TimeCurrent() + InpPendingExpiry * 60;
      
      if(type == "BUY") {
         // If current price is within entry range, open market order
         if(current_ask >= entry_min && current_ask <= entry_max) {
            Print("Price ", current_ask, " within entry range [", entry_min, "-", entry_max, "], opening Market Buy");
            trade.Buy(InpFixedLot, symbol, 0, sl, tp);
         }
         else if(current_ask > entry_max) {
            // Price above range, use BuyLimit at entry_max
            Print("Price ", current_ask, " above entry range, placing BuyLimit at ", entry_max, " expiry ", expiry);
            trade.BuyLimit(InpFixedLot, entry_max, symbol, sl, tp, ORDER_TIME_SPECIFIED, expiry);
         }
         else {
            // Price below range, use BuyStop at entry_min
            Print("Price ", current_ask, " below entry range, placing BuyStop at ", entry_min, " expiry ", expiry);
            trade.BuyStop(InpFixedLot, entry_min, symbol, sl, tp, ORDER_TIME_SPECIFIED, expiry);
         }
      }
      else if(type == "SELL") {
         // If current price is within entry range, open market order
         if(current_bid >= entry_min && current_bid <= entry_max) {
            Print("Price ", current_bid, " within entry range [", entry_min, "-", entry_max, "], opening Market Sell");
            trade.Sell(InpFixedLot, symbol, 0, sl, tp);
         }
         else if(current_bid < entry_min) {
            // Price below range, use SellLimit at entry_min
            Print("Price ", current_bid, " below entry range, placing SellLimit at ", entry_min, " expiry ", expiry);
            trade.SellLimit(InpFixedLot, entry_min, symbol, sl, tp, ORDER_TIME_SPECIFIED, expiry);
         }
         else {
            // Price above range, use SellStop at entry_max
            Print("Price ", current_bid, " above entry range, placing SellStop at ", entry_max, " expiry ", expiry);
            trade.SellStop(InpFixedLot, entry_max, symbol, sl, tp, ORDER_TIME_SPECIFIED, expiry);
         }
      }
   }
   else if(action == "CLOSE") {
      CloseAllPositions(symbol); 
   }
   else if(action == "CLOSE_PARTIAL") {
      double ratio = json["close_ratio"].ToDbl();
      if(ratio > 0) ClosePartialPositions(symbol, ratio);
   }
   else if(action == "MODIFY") {
       double sl = json["sl"].ToDbl();
       double tp = 0; // Assuming we only modify SL based on current requirements usually
       // If TP is provided, extract it
       CJAVal* tp_arr = json["tp"];
       if(tp_arr != NULL && tp_arr.Size() > 0) tp = tp_arr[0].ToDbl();
       
       ModifyPositions(symbol, sl, tp);
   }
   else if(action == "CLOSE_PARTIAL_AND_BREAKEVEN") {
       // 1. Close 50%
       double ratio = json["close_ratio"].ToDbl();
       if(ratio <= 0) ratio = 0.5; // Default safe
       ClosePartialPositions(symbol, ratio);
       
       // 2. Set Breakeven for remaining
       SetBreakeven(symbol);
   }
   
   delete json;
}

//+------------------------------------------------------------------+
//| Helper: Close All Positions for Symbol (Only if in profit)       |
//+------------------------------------------------------------------+
void CloseAllPositions(string symbol)
{
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(PositionGetSymbol(i) == symbol) {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagic || InpMagic == 0) {
            ulong ticket = PositionGetTicket(i);
            double profit = PositionGetDouble(POSITION_PROFIT);
            
            if(profit > 0) {
               Print("Position ", ticket, " in profit (", profit, "), closing...");
               trade.PositionClose(ticket);
            }
            else {
               // Not in profit - ensure SL and TP are set
               double sl = PositionGetDouble(POSITION_SL);
               double tp = PositionGetDouble(POSITION_TP);
               
               if(sl == 0 || tp == 0) {
                  Print("Position ", ticket, " not in profit (", profit, "), SL/TP missing. Please set manually.");
               }
               else {
                  Print("Position ", ticket, " not in profit (", profit, "), keeping open with SL=", sl, " TP=", tp);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Helper: Close Partial Positions                                  |
//+------------------------------------------------------------------+
void ClosePartialPositions(string symbol, double ratio)
{
   double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(PositionGetSymbol(i) == symbol) {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagic || InpMagic == 0) {
            ulong ticket = PositionGetTicket(i);
            double vol = PositionGetDouble(POSITION_VOLUME);
            
            // 1. If we are already at minimum lot, close full
            if(vol <= min_lot) {
               Print("Volume at minimum (" + DoubleToString(vol, 2) + "), Closing FULL position " + IntegerToString(ticket));
               trade.PositionClose(ticket);
               continue;
            }
            
            // 2. Calculate Partial Volume
            double close_vol = vol * ratio;
            
            // Align with Step
            close_vol = MathFloor(close_vol / lot_step) * lot_step;
            
            // Ensure close_vol is at least min_lot
            if(close_vol < min_lot) close_vol = min_lot;
            
            // Ensure we don't accidentally close more than we have (or equal, if handled above)
            if(close_vol >= vol) {
               trade.PositionClose(ticket);
            } else {
               trade.PositionClosePartial(ticket, close_vol);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Helper: Modify SL/TP                                             |
//+------------------------------------------------------------------+
void ModifyPositions(string symbol, double sl, double tp)
{
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(PositionGetSymbol(i) == symbol) {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagic || InpMagic == 0) {
             ulong ticket = PositionGetTicket(i);
             double curr_sl = PositionGetDouble(POSITION_SL);
             double curr_tp = PositionGetDouble(POSITION_TP);
             
             if(sl == 0) sl = curr_sl;
             if(tp == 0) tp = curr_tp;
             
             trade.PositionModify(ticket, sl, tp);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Helper: Set Breakeven                                            |
//+------------------------------------------------------------------+
void SetBreakeven(string symbol)
{
    // Moves SL to Open Price + approx 20-30 points (approx spread coverage)
    // Or just Open Price. Let's use Open Price for simplicity.
    for(int i=PositionsTotal()-1; i>=0; i--) {
      if(PositionGetSymbol(i) == symbol) {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagic || InpMagic == 0) {
             ulong ticket = PositionGetTicket(i);
             double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
             double tp = PositionGetDouble(POSITION_TP);
             
             // Move SL to Open Price
             trade.PositionModify(ticket, open_price, tp);
             Print("Moved SL to Breakeven for ", ticket);
         }
      }
   }
}

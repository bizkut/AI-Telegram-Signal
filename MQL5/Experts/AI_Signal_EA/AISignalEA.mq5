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
      double entry = json["entry"].ToDbl(); // Market orders usually ignore this, strictly speaking
      double sl = json["sl"].ToDbl();
      
      // Determine TP (First one)
      double tp = 0;
      CJAVal* tp_arr = json["tp"];
      if(tp_arr != NULL && tp_arr.Size() > 0) tp = tp_arr[0].ToDbl();
      
      if(type == "SELL") trade.Sell(InpFixedLot, symbol, 0, sl, tp);
      else if(type == "BUY") trade.Buy(InpFixedLot, symbol, 0, sl, tp);
      
      // Note: Limits/Stops require more logic matching "entry" to current price
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
//| Helper: Close All Positions for Symbol                           |
//+------------------------------------------------------------------+
void CloseAllPositions(string symbol)
{
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(PositionGetSymbol(i) == symbol) {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagic || InpMagic == 0) {
            trade.PositionClose(PositionGetTicket(i));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Helper: Close Partial Positions                                  |
//+------------------------------------------------------------------+
void ClosePartialPositions(string symbol, double ratio)
{
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(PositionGetSymbol(i) == symbol) {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagic || InpMagic == 0) {
            ulong ticket = PositionGetTicket(i);
            double vol = PositionGetDouble(POSITION_VOLUME);
            double close_vol = NormalizeDouble(vol * ratio, 2);
            // Minimum lot check needed here usually, simplified for now
            trade.PositionClosePartial(ticket, close_vol);
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

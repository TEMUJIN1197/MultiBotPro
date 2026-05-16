//+------------------------------------------------------------------+
//|                                     MultiBotPro_SlaveRuntime.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//+------------------------------------------------------------------+
#ifndef __MULTIBOTPRO_SLAVE_RUNTIME_MQH__
#define __MULTIBOTPRO_SLAVE_RUNTIME_MQH__

#include "MultiBotPro_Defines.mqh"
#include "hedgeBridge.mqh"

// --- GLOBALS ---
bool     g_SlaveInitialized     = false;
long     g_SlaveLastProcessedTime = 0;
ulong    g_SlaveLocalResetID      = 0;
double   g_SlaveStartEquity       = 0;
double   g_SlaveStartBalance      = 0;
bool     g_MasterStopped          = false;
ulong    g_SlaveLastProcessedMasterTicket = 0;
string   g_SlaveSignalFileName    = "";
string   g_SlaveStateFileName     = "";
string   g_SlaveFeedbackFileName  = "";
string   g_SlaveActiveFileName    = "";
CHedgePanel g_SlavePanel;

enum ENUM_MBP_SLAVE_MASTER_STATE_SOURCE
{
   MBP_SLAVE_MASTER_STATE_NONE = 0,
   MBP_SLAVE_MASTER_STATE_SQLITE,
   MBP_SLAVE_MASTER_STATE_FILE
};

HedgeState g_SlaveCachedMasterState;
bool g_SlaveHasCachedMasterState = false;
ENUM_MBP_SLAVE_MASTER_STATE_SOURCE g_SlavePreferredMasterStateSource = MBP_SLAVE_MASTER_STATE_SQLITE;

#define MBP_SLAVE_MAX_SQLITE_SIGNALS_PER_TIMER 4
#define MBP_SLAVE_MAX_FILE_SIGNALS_PER_TIMER   4
#define MBP_SLAVE_MAX_TRADE_LINKS              4096
#define MBP_SLAVE_MAX_ACTIVE_TICKETS           4096
#define MBP_FEEDBACK_ACTION_FAIL 1
#define MBP_FEEDBACK_ACTION_ACK  2
#define MBP_CLOSE_REASON_MASTER_CLOSE 1
#define MBP_CLOSE_REASON_OPEN_FAILURE 6

struct SlaveFeedbackState
{
   ulong masterTicket;
   int   lastAction;
};
SlaveFeedbackState g_SlaveFeedbackStates[];

struct SlaveConfig {
   string channel;
   int magic;
};

void BuildSlaveConfigSnapshot(SlaveConfig &cfg) {
   cfg.channel = Slave_InpChannelName;
   cfg.magic = (int)Slave_InpSlaveMagic;
}

struct MasterConfig {
   ENUM_MBP_DATA_MODE analysis_mode;
   ENUM_COMPUTE_BACKEND preferred_backend;
};

void BuildMasterConfigSnapshot(MasterConfig &cfg) {
   cfg.analysis_mode = InpDataMode;
   cfg.preferred_backend = COMPUTE_BACKEND_DLL;
}

// --- MAPPING STRUCT (Shadow Link) ---
struct TradeLink {
   ulong slaveTicket;
   ulong masterTicket;
};
TradeLink TradeMap[];
string    MapFileName;

// Internal helpers ported from hedge_slave.mq5
void Slave_LoadMap();
void Slave_SaveMap();
void Slave_AddLink(ulong slaveT, ulong masterT);
void Slave_RemoveLink(ulong slaveT);
ulong Slave_GetLinkedMaster(ulong slaveT);
string Slave_GetMappedSymbol(string in);
string Slave_GetBaseSymbol(string analysisSymbol);
bool Slave_LoadLatestMasterState(HedgeState &state);
void Slave_ProcessSignal(HedgeSignal &sig);
void Slave_CheckProposals();
void Slave_SendFeedback(ulong ticket, int action, string note = "");
bool Slave_IsReasonableHeartbeat(const ulong heartbeat);
void Slave_WriteRuntimeState(HedgeState &state);
void Slave_WriteActiveMasterTickets();
bool Slave_IsBridgeEnabled();
bool Slave_IsSQLiteRuntimeEnabled();
string BuildSlavePanelStatusText();
datetime Slave_GetNewYorkTime();
bool Slave_CanUseFileFallback(const bool sqliteEnabled);
double Slave_ClampDouble(const double value, const double minValue, const double maxValue);
int Slave_VolumeDigitsFromStep(double step);
double Slave_NormalizeVolumeDown(double volume, double minVolume, double step);
bool Slave_TryGetOrderType(const int masterType, ENUM_ORDER_TYPE &slaveType);
string Slave_SignalTypeToText(const int signalType);
string Slave_OrderTypeToText(const ENUM_ORDER_TYPE orderType);
string Slave_GetCloseReasonNote(const int reasonCode);
int Slave_FindFeedbackStateIndex(const ulong masterTicket);
bool Slave_HasFeedbackState(const ulong masterTicket);
void Slave_ClearFeedbackState(const ulong masterTicket);
void Slave_RememberFeedbackState(const ulong masterTicket, const int action);
ulong Slave_ExtractTicketFromComment(const string comment);
ulong Slave_ResolveMasterTicketForOpenPosition(const ulong positionTicket);
bool Slave_HasActiveLinkedSymbol(const string symbol);
int Slave_CountActiveLinkedSymbols();
bool Slave_IsSymbolCapacityAvailable(const string requestedSymbol);
double Slave_EstimateSplitMargin(string symbol, ENUM_ORDER_TYPE orderType, double totalLots, double minVolume, double maxVolume, double step, double price);
double Slave_FitLotsToMargin(string symbol, ENUM_ORDER_TYPE orderType, double totalLots, double minVolume, double maxVolume, double step, double price);
double Slave_CalculateRobustLots(HedgeSignal &sig, string mySym, HedgeState &state, ENUM_ORDER_TYPE slaveType, string stageLabel);
bool Slave_OpenTrade(string sym, ENUM_ORDER_TYPE type, double lots, double sl_pts, double tp_pts, string comment, ulong masterTicket, ulong &slaveTicket);
bool Slave_OpenLinkedHedgeTrades(string sym, ENUM_ORDER_TYPE type, double totalLots, double sl_pts, double tp_pts, string comment, ulong masterTicket);
bool Slave_CloseTrackedPosition(ulong slaveTicket, ulong masterTicket, int feedbackAction, int reasonCode);
void Slave_CloseLinkedSlaveTradesByMaster(ulong masterTicket, int feedbackAction, int reasonCode);
void Slave_ProcessSignalFileBatch(const string procFileName, const int maxSignals);

//+------------------------------------------------------------------+
//| Slave_OnInit                                                    |
//+------------------------------------------------------------------+
int Slave_OnInit()
{
   if(BotSystemMode != BOT_MODE_SLAVE)
      return INIT_SUCCEEDED;

   if(!VerifyLicense())
   {
      Print("FATAL: MultiBotPro slave initialization aborted due to invalid license.");
      return INIT_FAILED;
   }

   if(Slave_IsBridgeEnabled() && !Slave_InpV3_EnableSQLiteBridge && !Slave_InpV3_EnableFileFallback)
   {
      Print(EmojiWarning(), " Slave bridge is enabled, but both SQLite and file fallback are disabled.");
      return INIT_FAILED;
   }

   SlaveConfig cfg;
   BuildSlaveConfigSnapshot(cfg);
   Print(">>> Initializing Slave Runtime (Mode: ", BotSystemMode, ", Channel: ", cfg.channel, ")");
   
   g_SlaveStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_SlaveStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_SlaveSignalFileName = GetSignalFile(cfg.channel);
   g_SlaveStateFileName = GetSlaveFile(cfg.channel);
   g_SlaveFeedbackFileName = GetFeedbackFile(cfg.channel);
   g_SlaveActiveFileName = "HedgeSlaveActive_" + cfg.channel + ".bin";

   if(Slave_IsSQLiteRuntimeEnabled())
   {
      if(V3_EnsureRuntimeSchema(Slave_InpV3_SQLitePath))
         Print(EmojiBrain(), " Slave SQLite bridge ready: ", Slave_InpV3_SQLitePath);
      else
         Print(EmojiWarning(), " Slave SQLite schema init failed. Using file fallback where available.");
   }

   if(GlobalVariableCheck(cfg.channel + "_SlaveStartEq"))
   {
      double savedEq = GlobalVariableGet(cfg.channel + "_SlaveStartEq");
      if(savedEq > 0 && savedEq < 100000000)
         g_SlaveStartEquity = savedEq;
   }
   GlobalVariableSet(cfg.channel + "_SlaveStartEq", g_SlaveStartEquity);

   if(GlobalVariableCheck(cfg.channel + "_SlaveStartBal"))
   {
      double savedBal = GlobalVariableGet(cfg.channel + "_SlaveStartBal");
      if(savedBal > 0 && savedBal < 100000000)
         g_SlaveStartBalance = savedBal;
   }
   GlobalVariableSet(cfg.channel + "_SlaveStartBal", g_SlaveStartBalance);

   if(GlobalVariableCheck(cfg.channel + "_SlaveResetID"))
      g_SlaveLocalResetID = (ulong)GlobalVariableGet(cfg.channel + "_SlaveResetID");

   Slave_LoadMap();

   if(!g_SlavePanel.CreatePanel("HedgeSlave", false))
   {
      Print("FATAL: failed to create slave panel.");
      return INIT_FAILED;
   }
   g_SlavePanel.Run();
   g_SlavePanel.SetStatusText(BuildSlavePanelStatusText());

   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   EventSetMillisecondTimer((Slave_InpHeartbeat > 0) ? Slave_InpHeartbeat : 50);

   g_SlaveInitialized = true;
   Print("MultiBotPro Slave Initialized Successfully");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Slave_OnDeinit                                                  |
//+------------------------------------------------------------------+
void Slave_OnDeinit(const int reason)
{
   Slave_SaveMap();
   g_SlaveInitialized = false;
   g_SlavePanel.Destroy();
   EventKillTimer();
}

//+------------------------------------------------------------------+
//| Slave_OnTimer                                                   |
//+------------------------------------------------------------------+
void Slave_OnTimer()
{
   if(!g_SlaveInitialized || BotSystemMode == BOT_MODE_MASTER)
      return;

   if(MQLInfoInteger(MQL_TESTER))
      g_SlavePanel.PollButtonStates();

   if(Slave_IsBridgeEnabled())
      Slave_CheckProposals();

   if(g_SlavePanel.CheckResetRequest())
   {
      g_SlaveStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      GlobalVariableSet(Slave_InpChannelName + "_SlaveStartEq", g_SlaveStartEquity);
      g_SlaveStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      GlobalVariableSet(Slave_InpChannelName + "_SlaveStartBal", g_SlaveStartBalance);

      g_SlaveLocalResetID = (ulong)TimeCurrent();
      GlobalVariableSet(Slave_InpChannelName + "_SlaveResetID", (double)g_SlaveLocalResetID);

      string resetFile = "HedgeReset_" + Slave_InpChannelName + ".bin";
      int hRst = FileOpen(resetFile, FILE_WRITE|FILE_BIN|FILE_COMMON);
      if(hRst != INVALID_HANDLE)
      {
         FileWriteLong(hRst, (long)g_SlaveLocalResetID);
         FileClose(hRst);
      }

      Print(EmojiReset(), " Slave initiated reset. Command sent to MultiBotPro.");
   }

   HedgeState state;
   ZeroMemory(state);
   bool stateLoaded = false;

   if(Slave_IsBridgeEnabled())
   {
      bool sqliteEnabled = Slave_IsSQLiteRuntimeEnabled();
      if(sqliteEnabled)
      {
         int processedSignals = 0;
         while(processedSignals < MBP_SLAVE_MAX_SQLITE_SIGNALS_PER_TIMER)
         {
            long signalRowId = -1;
            HedgeSignal sig;
            if(!V3_SelectPendingSignalRow(Slave_InpV3_SQLitePath, Slave_InpChannelName, signalRowId, sig))
               break;

            if(sig.time_msc > g_SlaveLastProcessedTime)
               g_SlaveLastProcessedTime = sig.time_msc;

            Slave_ProcessSignal(sig);
            V3_MarkSignalProcessed(Slave_InpV3_SQLitePath, signalRowId);
            processedSignals++;
         }
      }

      string procFileName = "HedgeSignal_" + Slave_InpChannelName + "_PROC.bin";
      if(Slave_CanUseFileFallback(sqliteEnabled) && FileIsExist(g_SlaveSignalFileName, FILE_COMMON))
      {
         if(!FileIsExist(procFileName, FILE_COMMON))
            FileMove(g_SlaveSignalFileName, FILE_COMMON, procFileName, FILE_COMMON);
      }

      if(Slave_CanUseFileFallback(sqliteEnabled) && FileIsExist(procFileName, FILE_COMMON))
         Slave_ProcessSignalFileBatch(procFileName, MBP_SLAVE_MAX_FILE_SIGNALS_PER_TIMER);

      stateLoaded = Slave_LoadLatestMasterState(state);
   }

   if(stateLoaded && state.reset_id > g_SlaveLocalResetID)
   {
      g_SlaveLocalResetID = state.reset_id;
      GlobalVariableSet(Slave_InpChannelName + "_SlaveResetID", (double)g_SlaveLocalResetID);
      g_SlaveStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      GlobalVariableSet(Slave_InpChannelName + "_SlaveStartEq", g_SlaveStartEquity);
      g_SlaveStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      GlobalVariableSet(Slave_InpChannelName + "_SlaveStartBal", g_SlaveStartBalance);
      state.slave_pnl = 0.0;
   }

   state.slave_pnl = AccountInfoDouble(ACCOUNT_EQUITY) - g_SlaveStartEquity;
   state.last_heartbeat = (ulong)TimeGMT();
   state.reset_id = g_SlaveLocalResetID;

    if(Slave_IsBridgeEnabled())
    {
       Slave_WriteRuntimeState(state);
       Slave_WriteActiveMasterTickets();
    }

   g_SlavePanel.UpdateStats(state);
   g_SlavePanel.SetStatusText(BuildSlavePanelStatusText());

   if(stateLoaded)
      ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Slave_OnTick                                                    |
//+------------------------------------------------------------------+
void Slave_OnTick()
{
   if (!g_SlaveInitialized || BotSystemMode == BOT_MODE_MASTER) return;
}

//+------------------------------------------------------------------+
//| Slave_OnTradeTransaction                                         |
//+------------------------------------------------------------------+
void Slave_OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
{
   if (!g_SlaveInitialized || BotSystemMode == BOT_MODE_MASTER) return;
}

//+------------------------------------------------------------------+
//| Slave_OnChartEvent                                              |
//+------------------------------------------------------------------+
void Slave_OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(!g_SlaveInitialized || BotSystemMode == BOT_MODE_MASTER)
      return;

   g_SlavePanel.ChartEvent(id, lparam, dparam, sparam);
}

// --- Logic Implementation ---

bool Slave_IsBridgeEnabled()
{
   return Slave_InpBridgeEnabled;
}

bool Slave_IsReasonableHeartbeat(const ulong heartbeat)
{
   if(heartbeat == 0)
      return false;

   ulong now = (ulong)TimeGMT();
   const ulong earliestAllowed = 1577836800; // 2020-01-01 UTC
   const ulong futureTolerance = 86400;      // 1 day

   if(heartbeat < earliestAllowed)
      return false;
   if(heartbeat > (now + futureTolerance))
      return false;

   return true;
}

bool Slave_IsSQLiteRuntimeEnabled()
{
   return (Slave_InpBridgeEnabled && V3_RuntimeEnabled(Slave_InpV3_EnableSQLiteBridge, Slave_InpV3_SQLitePath));
}

bool Slave_CanUseFileFallback(const bool sqliteEnabled)
{
   return (Slave_InpBridgeEnabled && (!sqliteEnabled || Slave_InpV3_EnableFileFallback));
}

double Slave_ClampDouble(const double value, const double minValue, const double maxValue)
{
   if(value < minValue) return minValue;
   if(value > maxValue) return maxValue;
   return value;
}

int Slave_VolumeDigitsFromStep(double step)
{
   if(step <= 0.0) return 2;

   for(int digits = 0; digits < 8; digits++)
   {
      if(MathAbs(step - NormalizeDouble(step, digits)) <= 1e-8)
         return digits;
   }

   return 8;
}

double Slave_NormalizeVolumeDown(double volume, double minVolume, double step)
{
   if(step <= 0.0) step = minVolume;
   if(step <= 0.0) step = 0.01;
   if(volume <= 0.0) return 0.0;

   int digits = Slave_VolumeDigitsFromStep(step);
   double normalized = MathFloor((volume + 1e-12) / step) * step;
   normalized = NormalizeDouble(normalized, digits);

   if(normalized < minVolume - (step * 0.5))
      return 0.0;

   return normalized;
}

bool Slave_TryGetOrderType(const int masterType, ENUM_ORDER_TYPE &slaveType)
{
   if(masterType == 0)
   {
      slaveType = ORDER_TYPE_SELL;
      return true;
   }

   if(masterType == 1)
   {
      slaveType = ORDER_TYPE_BUY;
      return true;
   }

   return false;
}

string Slave_SignalTypeToText(const int signalType)
{
   if(signalType == 0) return "BUY";
   if(signalType == 1) return "SELL";
   return "UNKNOWN";
}

string Slave_OrderTypeToText(const ENUM_ORDER_TYPE orderType)
{
   if(orderType == ORDER_TYPE_BUY) return "BUY";
   if(orderType == ORDER_TYPE_SELL) return "SELL";
   return "UNKNOWN";
}

string Slave_GetCloseReasonNote(const int reasonCode)
{
   switch(reasonCode)
   {
      case MBP_CLOSE_REASON_MASTER_CLOSE: return "master_close_ack";
      case MBP_CLOSE_REASON_OPEN_FAILURE: return "slave_open_failed";
   }
   return "";
}

int Slave_FindFeedbackStateIndex(const ulong masterTicket)
{
   for(int i = 0; i < ArraySize(g_SlaveFeedbackStates); i++)
   {
      if(g_SlaveFeedbackStates[i].masterTicket == masterTicket)
         return i;
   }

   return -1;
}

bool Slave_HasFeedbackState(const ulong masterTicket)
{
   return (Slave_FindFeedbackStateIndex(masterTicket) >= 0);
}

void Slave_ClearFeedbackState(const ulong masterTicket)
{
   int idx = Slave_FindFeedbackStateIndex(masterTicket);
   if(idx < 0)
      return;

   int size = ArraySize(g_SlaveFeedbackStates);
   for(int i = idx; i < size - 1; i++)
      g_SlaveFeedbackStates[i] = g_SlaveFeedbackStates[i + 1];

   ArrayResize(g_SlaveFeedbackStates, size - 1);
}

void Slave_RememberFeedbackState(const ulong masterTicket, const int action)
{
   int idx = Slave_FindFeedbackStateIndex(masterTicket);
   if(idx < 0)
   {
      idx = ArraySize(g_SlaveFeedbackStates);
      ArrayResize(g_SlaveFeedbackStates, idx + 1);
      g_SlaveFeedbackStates[idx].masterTicket = masterTicket;
   }

   g_SlaveFeedbackStates[idx].lastAction = action;
}

datetime Slave_GetNewYorkTime()
{
   datetime gmtTime = TimeGMT();
   int nyOffsetSeconds = (-5 + Slave_InpNYManualShift) * 3600;
   return gmtTime + nyOffsetSeconds;
}

string BuildSlavePanelStatusText()
{
   string modeText = Slave_IsBridgeEnabled() ? "Bridge On" : "Bridge Off";
   return modeText + " | " + TimeToString(Slave_GetNewYorkTime(), TIME_SECONDS) + " NY";
}

void Slave_LoadMap() 
{
   MapFileName = "HedgeMap_" + Slave_InpChannelName + ".bin";
   if(FileIsExist(MapFileName, FILE_COMMON)) {
      int h = FileOpen(MapFileName, FILE_READ|FILE_BIN|FILE_COMMON);
      if(h != INVALID_HANDLE) {
         ulong fileSize = FileSize(h);
         int recordSize = (int)(sizeof(ulong) * 2);
         if(fileSize <= 0)
         {
            ArrayResize(TradeMap, 0);
         }
         else if(recordSize <= 0 || (fileSize % recordSize) != 0)
         {
            Print(EmojiWarning(), " Ignoring malformed slave trade map: ", MapFileName, " (size=", fileSize, ")");
            ArrayResize(TradeMap, 0);
            FileClose(h);
            FileDelete(MapFileName, FILE_COMMON);
            return;
         }
         else
         {
            int recordCount = (int)(fileSize / recordSize);
            if(recordCount < 0 || recordCount > MBP_SLAVE_MAX_TRADE_LINKS)
            {
               Print(EmojiWarning(), " Ignoring oversized slave trade map: ", MapFileName, " (records=", recordCount, ")");
               ArrayResize(TradeMap, 0);
               FileClose(h);
               FileDelete(MapFileName, FILE_COMMON);
               return;
            }

            ArrayResize(TradeMap, recordCount);
            uint loaded = (recordCount > 0) ? FileReadArray(h, TradeMap) : 0;
            if(recordCount > 0 && loaded != (uint)recordCount)
            {
               Print(EmojiWarning(), " Incomplete slave trade map read. Resetting map cache.");
               ArrayResize(TradeMap, 0);
               FileClose(h);
               FileDelete(MapFileName, FILE_COMMON);
               return;
            }
         }
         FileClose(h);
      }
   }
}

void Slave_SaveMap() 
{
   int h = FileOpen(MapFileName, FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(h != INVALID_HANDLE) {
      FileWriteArray(h, TradeMap);
      FileClose(h);
   }
}

void Slave_AddLink(ulong slaveT, ulong masterT) {
   int s = ArraySize(TradeMap);
   ArrayResize(TradeMap, s+1, 512);
   TradeMap[s].slaveTicket  = slaveT;
   TradeMap[s].masterTicket = masterT;
   Slave_SaveMap(); 
}

void Slave_RemoveLink(ulong slaveT) {
   int s = ArraySize(TradeMap);
   bool found = false;
   for(int i=0; i<s; i++) {
      if(TradeMap[i].slaveTicket == slaveT) {
         found = true;
         for(int j=i; j<s-1; j++) TradeMap[j] = TradeMap[j+1];
         break;
      }
   }
   if(found) {
      ArrayResize(TradeMap, s-1);
      Slave_SaveMap();
   }
}

ulong Slave_GetLinkedMaster(ulong slaveT) {
   for(int i=0; i<ArraySize(TradeMap); i++) {
      if(TradeMap[i].slaveTicket == slaveT) return TradeMap[i].masterTicket;
   }
   return 0;
}

bool Slave_HasLinkedTradesForMaster(const ulong masterTicket)
{
   if(masterTicket == 0)
      return false;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong slaveTicket = PositionGetTicket(i);
      if(!PositionSelectByTicket(slaveTicket))
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != Slave_InpSlaveMagic)
         continue;
      if(Slave_ResolveMasterTicketForOpenPosition(slaveTicket) == masterTicket)
         return true;
   }

   return false;
}

ulong Slave_ExtractTicketFromComment(const string comment)
{
   return 0;
}

ulong Slave_ResolveMasterTicketForOpenPosition(const ulong positionTicket)
{
   ulong linkedMaster = Slave_GetLinkedMaster(positionTicket);
   if(linkedMaster > 0)
      return linkedMaster;

   return 0;
}

bool Slave_HasActiveLinkedSymbol(const string symbol)
{
   if(symbol == "")
      return false;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != Slave_InpSlaveMagic)
         continue;
      if(Slave_ResolveMasterTicketForOpenPosition(ticket) == 0)
         continue;

      string currentSymbol = PositionGetString(POSITION_SYMBOL);
      if(StringCompare(currentSymbol, symbol, false) == 0)
         return true;
   }

   return false;
}

int Slave_CountActiveLinkedSymbols()
{
   string activeSymbols[];
   int uniqueCount = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != Slave_InpSlaveMagic)
         continue;
      if(Slave_ResolveMasterTicketForOpenPosition(ticket) == 0)
         continue;

      string currentSymbol = PositionGetString(POSITION_SYMBOL);
      bool exists = false;
      for(int j = 0; j < uniqueCount; j++)
      {
         if(StringCompare(activeSymbols[j], currentSymbol, false) == 0)
         {
            exists = true;
            break;
         }
      }

      if(exists)
         continue;

      ArrayResize(activeSymbols, uniqueCount + 1, 128);
      activeSymbols[uniqueCount] = currentSymbol;
      uniqueCount++;
   }

   return uniqueCount;
}

bool Slave_IsSymbolCapacityAvailable(const string requestedSymbol)
{
   if(Slave_InpMaxConcurrentSymbols <= 0 || requestedSymbol == "")
      return true;

   if(Slave_HasActiveLinkedSymbol(requestedSymbol))
      return true;

   return (Slave_CountActiveLinkedSymbols() < Slave_InpMaxConcurrentSymbols);
}

string Slave_GetMappedSymbol(string in) {
   return Slave_GetBaseSymbol(in);
}

string Slave_GetBaseSymbol(string analysisSymbol) {
   string candidates[];
   string guess = "";
   if(StringSplit(analysisSymbol, '_', candidates) > 1) {
      guess = candidates[0];
      if(SymbolSelect(guess, true)) return guess;
   }
   if(SymbolSelect(analysisSymbol, true)) return analysisSymbol;
   return analysisSymbol;
}

bool Slave_LoadLatestMasterState(HedgeState &state)
{
   ZeroMemory(state);
   if(!Slave_IsBridgeEnabled())
      return false;

   HedgeState sqliteState;
   HedgeState fileState;
   ZeroMemory(sqliteState);
   ZeroMemory(fileState);

   bool haveSqliteState = (Slave_IsSQLiteRuntimeEnabled() &&
                           V3_ReadLatestMasterState(Slave_InpV3_SQLitePath, Slave_InpChannelName, sqliteState));
   bool haveFileState = false;

   string masterFile = GetMasterFile(Slave_InpChannelName);
   int h = FileOpenRobust(masterFile, FILE_READ|FILE_BIN|FILE_COMMON);
   if(h != INVALID_HANDLE)
   {
      haveFileState = (FileReadStruct(h, fileState) > 0);
      FileClose(h);
   }

   if(haveSqliteState && !Slave_IsReasonableHeartbeat(sqliteState.last_heartbeat))
      haveSqliteState = false;

   if(haveFileState && !Slave_IsReasonableHeartbeat(fileState.last_heartbeat))
      haveFileState = false;

   const ulong sourceSwitchLeadSec = 3;
   const ulong cacheHoldSec = 15;

   ENUM_MBP_SLAVE_MASTER_STATE_SOURCE chosenSource = MBP_SLAVE_MASTER_STATE_NONE;
   HedgeState chosenState;
   ZeroMemory(chosenState);

   if(haveSqliteState && haveFileState)
   {
      chosenSource = MBP_SLAVE_MASTER_STATE_SQLITE;
      chosenState = sqliteState;

      if(g_SlavePreferredMasterStateSource == MBP_SLAVE_MASTER_STATE_FILE)
      {
         if(fileState.last_heartbeat >= (sqliteState.last_heartbeat + sourceSwitchLeadSec))
         {
            chosenSource = MBP_SLAVE_MASTER_STATE_FILE;
            chosenState = fileState;
         }
      }
      else
      {
         if(sqliteState.last_heartbeat + sourceSwitchLeadSec < fileState.last_heartbeat)
         {
            chosenSource = MBP_SLAVE_MASTER_STATE_FILE;
            chosenState = fileState;
         }
      }
   }
   else if(haveSqliteState)
   {
      chosenSource = MBP_SLAVE_MASTER_STATE_SQLITE;
      chosenState = sqliteState;
   }
   else if(haveFileState)
   {
      chosenSource = MBP_SLAVE_MASTER_STATE_FILE;
      chosenState = fileState;
   }

   if(chosenSource != MBP_SLAVE_MASTER_STATE_NONE)
   {
      if(!g_SlaveHasCachedMasterState || chosenState.last_heartbeat >= g_SlaveCachedMasterState.last_heartbeat || chosenSource == g_SlavePreferredMasterStateSource)
      {
         g_SlaveCachedMasterState = chosenState;
         g_SlaveHasCachedMasterState = true;
         g_SlavePreferredMasterStateSource = chosenSource;
      }

      state = g_SlaveCachedMasterState;
      return true;
   }

   if(g_SlaveHasCachedMasterState && Slave_IsReasonableHeartbeat(g_SlaveCachedMasterState.last_heartbeat))
   {
      ulong now = (ulong)TimeGMT();
      if(now >= g_SlaveCachedMasterState.last_heartbeat && (now - g_SlaveCachedMasterState.last_heartbeat) <= cacheHoldSec)
      {
         state = g_SlaveCachedMasterState;
         return true;
      }
   }

   return false;
}

void Slave_WriteRuntimeState(HedgeState &state)
{
   if(Slave_IsSQLiteRuntimeEnabled())
      V3_WriteSlaveStateRow(Slave_InpV3_SQLitePath, Slave_InpChannelName, state);

   int h = FileOpen(g_SlaveStateFileName, FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(h != INVALID_HANDLE)
   {
      FileWriteStruct(h, state);
      FileClose(h);
   }
}

void Slave_WriteActiveMasterTickets()
{
   int hOut = FileOpen(g_SlaveActiveFileName, FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(hOut == INVALID_HANDLE)
      return;

   ulong tickets[];
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != Slave_InpSlaveMagic)
         continue;

      ulong linkedMasterTicket = Slave_GetLinkedMaster(ticket);
      if(linkedMasterTicket == 0)
         continue;
      if(count >= MBP_SLAVE_MAX_ACTIVE_TICKETS)
         break;

      ArrayResize(tickets, count + 1, 128);
      tickets[count] = linkedMasterTicket;
      count++;
   }

   FileWriteInteger(hOut, count, INT_VALUE);
   if(count > 0)
      FileWriteArray(hOut, tickets);
   FileClose(hOut);
}

double Slave_EstimateSplitMargin(string symbol, ENUM_ORDER_TYPE orderType, double totalLots, double minVolume, double maxVolume, double step, double price)
{
   double remaining = Slave_NormalizeVolumeDown(totalLots, minVolume, step);
   double totalMargin = 0.0;

   while(remaining >= minVolume)
   {
      double chunk = MathMin(maxVolume, remaining);
      chunk = Slave_NormalizeVolumeDown(chunk, minVolume, step);
      if(chunk < minVolume)
         break;

      double chunkMargin = 0.0;
      if(!OrderCalcMargin(orderType, symbol, chunk, price, chunkMargin))
         return -1.0;

      totalMargin += chunkMargin;
      remaining = Slave_NormalizeVolumeDown(remaining - chunk, minVolume, step);
   }

   return totalMargin;
}

double Slave_FitLotsToMargin(string symbol, ENUM_ORDER_TYPE orderType, double totalLots, double minVolume, double maxVolume, double step, double price)
{
   double freeMarginCap = AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.98;
   double fittedLots = Slave_NormalizeVolumeDown(totalLots, minVolume, step);
   int guard = 0;

   while(fittedLots >= minVolume && guard < 5000)
   {
      guard++;
      double requiredMargin = Slave_EstimateSplitMargin(symbol, orderType, fittedLots, minVolume, maxVolume, step, price);
      if(requiredMargin >= 0.0 && requiredMargin <= freeMarginCap)
         return fittedLots;

      fittedLots = Slave_NormalizeVolumeDown(fittedLots - step, minVolume, step);
   }

   return 0.0;
}

double Slave_CalculateRobustLots(HedgeSignal &sig, string mySym, HedgeState &state, ENUM_ORDER_TYPE slaveType, string stageLabel)
{
   if(!SymbolSelect(mySym, true))
   {
      Print(EmojiWarning(), " Slave could not select symbol '", mySym, "'. Hedge denied.");
      return -1.0;
   }

   if(state.master_target_risk <= 0.0 || state.slave_target_gain <= 0.0)
   {
      PrintFormat(EmojiWarning() + " Hedge sizing failed: invalid master/slave state. master_risk=%.2f slave_target=%.2f signal_risk=%.2f ticket=%I64u symbol=%s",
                  state.master_target_risk, state.slave_target_gain, sig.risk_money, sig.ticket, mySym);
      return -1.0;
   }

   if(sig.risk_money <= 0.0)
   {
      PrintFormat(EmojiWarning() + " Hedge sizing failed: zero-risk payload from master. signal_risk=%.2f sl_dist=%.2f lots=%.2f ticket=%I64u symbol=%s",
                  sig.risk_money, sig.sl_dist_points, sig.lots, sig.ticket, mySym);
      return -1.0;
   }

   double baseRatio = state.slave_target_gain / state.master_target_risk;
   double baselineCash = sig.risk_money * baseRatio;
   if(baselineCash <= 0.0)
      return -1.0;

   double masterDD = MathMax(0.0, -state.master_pnl);
   double masterProgress = Slave_ClampDouble(masterDD / state.master_target_risk, 0.0, 1.0);
   double targetSlavePnL = state.slave_target_gain * masterProgress;
   double progressGap = targetSlavePnL - state.slave_pnl;
   double desiredTradeCash = baselineCash;

   if(state.slave_pnl < state.slave_target_gain)
   {
      double signalWeight = Slave_ClampDouble(sig.risk_money / state.master_target_risk, 0.08, 0.18);
      double rawCorrection = progressGap * signalWeight * 0.40;
      double correction = Slave_ClampDouble(rawCorrection, -0.20 * baselineCash, 0.30 * baselineCash);
      desiredTradeCash = MathMax(0.0, baselineCash + correction);
   }

   if(desiredTradeCash <= 0.0)
      return -1.0;

   double point = SymbolInfoDouble(mySym, SYMBOL_POINT);
   if(point <= 0.0) point = 0.00001;
   double tickVal = SymbolInfoDouble(mySym, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(mySym, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0.0) tickSize = point;

   long liveSpreadPoints = SymbolInfoInteger(mySym, SYMBOL_SPREAD);
   double spreadCostPerLot = 0.0;
   if(tickVal > 0.0 && tickSize > 0.0)
      spreadCostPerLot = (liveSpreadPoints * point / tickSize) * tickVal;

   double totalLots = 0.0;
   double actualPhysicalDist = (sig.sl_dist_points > 0.0) ? (sig.sl_dist_points * point) : 0.0;
   if(actualPhysicalDist > 0.0 && tickVal > 0.0 && tickSize > 0.0)
   {
      double costPerLot = ((actualPhysicalDist / tickSize) * tickVal) + spreadCostPerLot + Slave_InpEstCommCost;
      if(costPerLot > 0.0)
         totalLots = desiredTradeCash / costPerLot;
   }

   if(totalLots <= 0.0)
   {
      if(sig.lots <= 0.0)
         return -1.0;
      totalLots = sig.lots * (desiredTradeCash / sig.risk_money);
   }

   double minVolume = SymbolInfoDouble(mySym, SYMBOL_VOLUME_MIN);
   double maxVolume = SymbolInfoDouble(mySym, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(mySym, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = minVolume;
   if(step <= 0.0) step = 0.01;

   totalLots = Slave_NormalizeVolumeDown(totalLots, minVolume, step);
   if(totalLots < minVolume)
      return -1.0;

   double entryPrice = (slaveType == ORDER_TYPE_BUY) ? SymbolInfoDouble(mySym, SYMBOL_ASK) : SymbolInfoDouble(mySym, SYMBOL_BID);
   double fittedLots = Slave_FitLotsToMargin(mySym, slaveType, totalLots, minVolume, maxVolume, step, entryPrice);
   if(fittedLots < minVolume)
      return -1.0;

   PrintFormat(EmojiCalc() + " Hedge sizing [%s]: ticket=%I64u | master=%s -> slave=%s | Desired=$%.2f -> Total Lots: %.2f",
               stageLabel, sig.ticket, Slave_SignalTypeToText(sig.type), Slave_OrderTypeToText(slaveType), desiredTradeCash, fittedLots);
   return fittedLots;
}

bool Slave_OpenTrade(string sym, ENUM_ORDER_TYPE type, double lots, double sl_pts, double tp_pts, string comment, ulong masterTicket, ulong &slaveTicket)
{
   slaveTicket = 0;
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID);

   Trade.SetExpertMagicNumber(Slave_InpSlaveMagic);
   if(!Trade.PositionOpen(sym, type, lots, price, 0.0, 0.0, comment))
   {
      PrintFormat(EmojiWarning() + " Hedge order failed: sym=%s side=%s lots=%.2f retcode=%u err=%d",
                  sym, Slave_OrderTypeToText(type), lots, Trade.ResultRetcode(), GetLastError());
      return false;
   }

   slaveTicket = Trade.ResultOrder();
   if(slaveTicket == 0)
   {
      PrintFormat(EmojiWarning() + " Hedge order opened, but no slave ticket was returned for master %I64u.", masterTicket);
      return false;
   }

   Slave_AddLink(slaveTicket, masterTicket);
   Print(EmojiShield(), " Hedge child opened. Linked slave #", slaveTicket, " to master #", masterTicket);
   return true;
}

bool Slave_OpenLinkedHedgeTrades(string sym, ENUM_ORDER_TYPE type, double totalLots, double sl_pts, double tp_pts, string comment, ulong masterTicket)
{
   double minVolume = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxVolume = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = minVolume;
   if(step <= 0.0) step = 0.01;

   double remaining = Slave_NormalizeVolumeDown(totalLots, minVolume, step);
   if(remaining < minVolume)
      return false;

   double executedLots = 0.0;
   ulong openedTickets[];

   while(remaining >= minVolume)
   {
      double chunk = MathMin(maxVolume, remaining);
      chunk = Slave_NormalizeVolumeDown(chunk, minVolume, step);
      if(chunk < minVolume)
         break;

      ulong slaveTicket = 0;
      if(!Slave_OpenTrade(sym, type, chunk, sl_pts, tp_pts, comment, masterTicket, slaveTicket))
      {
         if(ArraySize(openedTickets) == 0)
         {
            Slave_SendFeedback(masterTicket, MBP_FEEDBACK_ACTION_FAIL, Slave_GetCloseReasonNote(MBP_CLOSE_REASON_OPEN_FAILURE));
         }
         else
         {
            for(int i = 0; i < ArraySize(openedTickets); i++)
               Slave_CloseTrackedPosition(openedTickets[i], masterTicket, MBP_FEEDBACK_ACTION_FAIL, MBP_CLOSE_REASON_OPEN_FAILURE);
         }
         return false;
      }

      int openedCount = ArraySize(openedTickets);
      ArrayResize(openedTickets, openedCount + 1);
      openedTickets[openedCount] = slaveTicket;
      executedLots += chunk;
      remaining = Slave_NormalizeVolumeDown(remaining - chunk, minVolume, step);
   }

   return (executedLots > 0.0);
}

bool Slave_CloseTrackedPosition(ulong slaveTicket, ulong masterTicket, int feedbackAction, int reasonCode)
{
   if(slaveTicket == 0)
      return false;

   if(!PositionSelectByTicket(slaveTicket))
      return false;

   if(!Trade.PositionClose(slaveTicket))
   {
      PrintFormat(EmojiWarning() + " Slave close request failed: slave=%I64u master=%I64u err=%d",
                  slaveTicket, masterTicket, GetLastError());
      return false;
   }

   Slave_RemoveLink(slaveTicket);
   if(masterTicket > 0)
      Slave_SendFeedback(masterTicket, feedbackAction, Slave_GetCloseReasonNote(reasonCode));
   return true;
}

void Slave_CloseLinkedSlaveTradesByMaster(ulong masterTicket, int feedbackAction, int reasonCode)
{
   if(masterTicket == 0)
      return;

   int matches = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong slaveTicket = PositionGetTicket(i);
      if(!PositionSelectByTicket(slaveTicket))
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != Slave_InpSlaveMagic)
         continue;
      if(Slave_ResolveMasterTicketForOpenPosition(slaveTicket) != masterTicket)
         continue;

      matches++;
      Slave_CloseTrackedPosition(slaveTicket, masterTicket, feedbackAction, reasonCode);
   }

   if(matches == 0 && feedbackAction == MBP_FEEDBACK_ACTION_ACK && !Slave_HasFeedbackState(masterTicket))
      Slave_SendFeedback(masterTicket, feedbackAction, Slave_GetCloseReasonNote(reasonCode));
}

void Slave_ProcessSignal(HedgeSignal &sig)
{
   if(!Slave_IsBridgeEnabled())
      return;

   string masterSym = CharArrayToString(sig.symbol);
   string mySym = Slave_GetMappedSymbol(masterSym);

   if(sig.action == 1)
   {
      if(sig.ticket == g_SlaveLastProcessedMasterTicket)
         return;

      bool alreadyLinked = Slave_HasLinkedTradesForMaster(sig.ticket);
      if(alreadyLinked)
      {
         PrintFormat(EmojiShield() + " Duplicate hedge open signal ignored: master ticket=%I64u symbol=%s",
                     sig.ticket,
                     mySym);
         g_SlaveLastProcessedMasterTicket = sig.ticket;
         return;
      }

      ENUM_ORDER_TYPE slaveType;
      if(!Slave_TryGetOrderType(sig.type, slaveType))
      {
         Slave_SendFeedback(sig.ticket, MBP_FEEDBACK_ACTION_FAIL, "invalid_master_side");
         return;
      }

      if(sig.lots <= 0.0 || sig.risk_money <= 0.0 || sig.sl_dist_points <= 0.0)
      {
         PrintFormat(EmojiWarning() + " Discarding malformed hedge signal from master. signal_risk=%.2f sl_dist=%.2f lots=%.2f ticket=%I64u symbol=%s",
                     sig.risk_money, sig.sl_dist_points, sig.lots, sig.ticket, mySym);
         if(sig.ticket > 0)
            g_SlaveLastProcessedMasterTicket = sig.ticket;
         return;
      }

      HedgeState state;
      if(!Slave_LoadLatestMasterState(state))
      {
         Slave_SendFeedback(sig.ticket, MBP_FEEDBACK_ACTION_FAIL, "master_state_unavailable");
         return;
      }

      if(state.is_paused || state.is_daily_stopped || state.is_total_stopped)
      {
         Slave_SendFeedback(sig.ticket, MBP_FEEDBACK_ACTION_FAIL, "master_blocked");
         return;
      }

      if(!Slave_IsSymbolCapacityAvailable(mySym))
      {
         PrintFormat(EmojiWarning() + " Slave symbol cap reached. Rejected hedge open for master ticket %I64u | symbol=%s | active_symbols=%d | limit=%d",
                     sig.ticket,
                     mySym,
                     Slave_CountActiveLinkedSymbols(),
                     Slave_InpMaxConcurrentSymbols);
         Slave_SendFeedback(sig.ticket, MBP_FEEDBACK_ACTION_FAIL, "symbol_limit");
         return;
      }

      double myLots = Slave_CalculateRobustLots(sig, mySym, state, slaveType, "executed");
      if(myLots <= 0.0)
      {
         Slave_SendFeedback(sig.ticket, MBP_FEEDBACK_ACTION_FAIL, "lot_calc_failed");
         return;
      }

      string masterCmt = CharArrayToString(sig.comment);
      string finalCmt = masterCmt;
      PrintFormat(EmojiShield() + " Hedge open: executed master %s -> slave %s | ticket=%I64u | symbol=%s | lots=%.2f",
                  Slave_SignalTypeToText(sig.type), Slave_OrderTypeToText(slaveType), sig.ticket, mySym, myLots);
      if(Slave_OpenLinkedHedgeTrades(mySym, slaveType, myLots, sig.sl_dist_points, sig.tp_dist_points, finalCmt, sig.ticket))
         g_SlaveLastProcessedMasterTicket = sig.ticket;
   }
   else if(sig.action == 2)
   {
      Slave_CloseLinkedSlaveTradesByMaster(sig.ticket, MBP_FEEDBACK_ACTION_ACK, MBP_CLOSE_REASON_MASTER_CLOSE);
   }
}

void Slave_ProcessSignalFileBatch(const string procFileName, const int maxSignals)
{
   int h = FileOpenRobust(procFileName, FILE_READ|FILE_BIN|FILE_COMMON);
   if(h == INVALID_HANDLE)
      return;

   HedgeSignal pending[];
   while(!FileIsEnding(h))
   {
      HedgeSignal sig;
      if(FileReadStruct(h, sig) <= 0)
         break;

      int idx = ArraySize(pending);
      ArrayResize(pending, idx + 1);
      pending[idx] = sig;
   }
   FileClose(h);

   int total = ArraySize(pending);
   if(total <= 0)
   {
      FileDelete(procFileName, FILE_COMMON);
      return;
   }

   int processCount = MathMin(total, maxSignals);
   for(int i = 0; i < processCount; i++)
   {
      if(pending[i].time_msc > g_SlaveLastProcessedTime)
         g_SlaveLastProcessedTime = pending[i].time_msc;
      Slave_ProcessSignal(pending[i]);
   }

   if(processCount >= total)
   {
      FileDelete(procFileName, FILE_COMMON);
      return;
   }

   int hw = FileOpenRobust(procFileName, FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(hw == INVALID_HANDLE)
      return;

   for(int i = processCount; i < total; i++)
      FileWriteStruct(hw, pending[i]);

   FileClose(hw);
}

void Slave_CheckProposals()
{
   if(!Slave_IsBridgeEnabled())
      return;

   string proposalFile = GetProposalFile(Slave_InpChannelName);
   string replyFile    = GetReplyFile(Slave_InpChannelName);
   bool sqliteEnabled  = Slave_IsSQLiteRuntimeEnabled();

   BridgeProposal prop;
   ZeroMemory(prop);
   bool hasProposal = false;
   bool sqliteProposal = false;
   long proposalRowId = -1;
   string requestId = "";

   if(sqliteEnabled)
   {
      if(V3_SelectPendingProposalRow(Slave_InpV3_SQLitePath, Slave_InpChannelName, proposalRowId, requestId, prop))
      {
         hasProposal = true;
         sqliteProposal = true;
      }
   }

   if(!hasProposal && Slave_CanUseFileFallback(sqliteEnabled) && FileIsExist(proposalFile, FILE_COMMON))
   {
      int h = FileOpenRobust(proposalFile, FILE_READ|FILE_BIN|FILE_COMMON);
      if(h == INVALID_HANDLE)
         return;

      FileReadStruct(h, prop);
      FileClose(h);
      FileDelete(proposalFile, FILE_COMMON);
      requestId = StringFormat("%I64u", prop.ticket);
      hasProposal = true;
   }

   if(!hasProposal)
      return;

   string proposalSymbol = CharArrayToString(prop.symbol);
   if(prop.lots <= 0.0 || prop.risk_money <= 0.0 || prop.sl_dist_points <= 0.0 || proposalSymbol == "")
   {
      PrintFormat(EmojiWarning() + " Discarding malformed hedge proposal from master. signal_risk=%.2f sl_dist=%.2f lots=%.2f ticket=%I64u symbol=%s",
                  prop.risk_money,
                  prop.sl_dist_points,
                  prop.lots,
                  prop.ticket,
                  proposalSymbol);

      if(sqliteProposal)
         V3_UpdateProposalState(Slave_InpV3_SQLitePath, proposalRowId, "INVALID");

      return;
   }

   HedgeSignal sig;
   ZeroMemory(sig);
   sig.time_msc = prop.time_msc;
   sig.ticket = prop.ticket;
   sig.action = prop.action;
   sig.type = prop.type;
   sig.lots = prop.lots;
   sig.sl_dist_points = prop.sl_dist_points;
   sig.tp_dist_points = prop.tp_dist_points;
   sig.risk_money = prop.risk_money;
   ArrayCopy(sig.symbol, prop.symbol);

   string masterSym = proposalSymbol;
   string mySym = Slave_GetMappedSymbol(masterSym);

   HedgeState state;
   bool stateLoaded = Slave_LoadLatestMasterState(state);

   BridgeReply reply;
   ZeroMemory(reply);
   reply.master_ticket = prop.ticket;
   string replyNote = "denied";

   if(!stateLoaded)
   {
      reply.action = 0;
      replyNote = "master_state_unavailable";
   }
   else if(state.is_paused || state.is_daily_stopped || state.is_total_stopped)
   {
      reply.action = 0;
      replyNote = "master_blocked";
   }
   else if(!Slave_IsSymbolCapacityAvailable(mySym))
   {
      reply.action = 0;
      replyNote = "symbol_limit";
      PrintFormat(EmojiWarning() + " Handshake denied: slave symbol cap reached for %s. active_symbols=%d limit=%d",
                  mySym,
                  Slave_CountActiveLinkedSymbols(),
                  Slave_InpMaxConcurrentSymbols);
   }
   else
   {
      ENUM_ORDER_TYPE slaveType;
      if(!Slave_TryGetOrderType(sig.type, slaveType))
      {
         reply.action = 0;
         replyNote = "invalid_master_side";
      }
      else
      {
         double myLots = Slave_CalculateRobustLots(sig, mySym, state, slaveType, "estimated");
         if(myLots > 0.0)
         {
            reply.action = 1;
            replyNote = "approved";
            PrintFormat(EmojiShield() + " Hedge handshake approved: ticket=%I64u | estimated master %s -> slave %s | symbol=%s | lots=%.2f",
                        sig.ticket, Slave_SignalTypeToText(sig.type), Slave_OrderTypeToText(slaveType), mySym, myLots);
         }
         else
         {
            reply.action = 0;
            replyNote = "lot_calc_failed";
         }
      }
   }

   if(sqliteProposal)
   {
      V3_InsertReplyRow(Slave_InpV3_SQLitePath, Slave_InpChannelName, requestId, reply.action, V3_BuildReplyPayload(replyNote));
      V3_UpdateProposalState(Slave_InpV3_SQLitePath, proposalRowId, (reply.action == 1) ? "APPROVED" : "DENIED");
   }
   else
   {
      int rh = FileOpenRobust(replyFile, FILE_WRITE|FILE_BIN|FILE_COMMON);
      if(rh != INVALID_HANDLE)
      {
         FileWriteStruct(rh, reply);
         FileClose(rh);
      }
   }
}

void Slave_SendFeedback(ulong ticket, int action, string note = "")
{
   if(!Slave_IsBridgeEnabled() || ticket == 0)
      return;

   if(Slave_HasFeedbackState(ticket))
      return;

   bool sqliteEnabled = Slave_IsSQLiteRuntimeEnabled();
   if(sqliteEnabled)
   {
      if(V3_InsertFeedbackRow(Slave_InpV3_SQLitePath, Slave_InpChannelName, ticket, action, note))
      {
         Slave_RememberFeedbackState(ticket, action);
         PrintFormat(EmojiShield() + " Feedback sent to SQLite: ticket=%I64u action=%d note=%s", ticket, action, note);
         return;
      }

      if(!Slave_CanUseFileFallback(sqliteEnabled))
         return;
   }
   else if(!Slave_CanUseFileFallback(sqliteEnabled))
   {
      return;
   }

   HedgeFeedback fb;
   fb.master_ticket = ticket;
   fb.action = action;

   int h = FileOpenRobust(g_SlaveFeedbackFileName, FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(h != INVALID_HANDLE)
   {
      FileWriteStruct(h, fb);
      FileClose(h);
      Slave_RememberFeedbackState(ticket, action);
      PrintFormat(EmojiShield() + " Feedback sent via the file bridge: ticket=%I64u action=%d", ticket, action);
   }
}

#endif // __MULTIBOTPRO_SLAVE_RUNTIME_MQH__

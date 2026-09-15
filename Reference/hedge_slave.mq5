//+------------------------------------------------------------------+
//|                                                HedgeReceiver.mq5 |
//|                      Slave Node (MT4 & MT5 Compatible)           |
//+------------------------------------------------------------------+
#property copyright "Hedge Receiver"
#property strict
#property version   "1.00"
#property icon      "romeo.ico"
#resource           "romeo.bmp"

// Required by hedgeBridge.mqh – allow blocking waits in standalone hedge mode
bool MBP_ShouldAllowBlockingTradeWait(const string reason = "") { return true; }

#include "hedgeBridge.mqh"

// MT5 Needs CTrade
#ifdef __MQL5__
#include <Trade\Trade.mqh>
CTrade Trade;
#endif

// --- MAPPING STRUCT (Shadow Link) ---
struct TradeLink {
   ulong slaveTicket;
   ulong masterTicket;
};
TradeLink TradeMap[];
string    MapFileName;

// --- INPUTS ---
input string   InpChannelName    = "HEDGE_A";
input string   InpSymbolMap      = "";
input int      InpHeartbeat      = 50;
input long     InpSlaveMagic     = 123456;
input int      FailsafeTimeoutSeconds = 30; // Max allowed seconds without Master ping

// --- TIMEZONE SETTINGS ---
input group "--- TIMEZONE SETTINGS ---"
input int    InpNYManualShift       = 1;  // Manual NY Shift (e.g. +1 for DST)

// --- SQLITE V3 RUNTIME ---
input bool     InpBridgeEnabled = true;
input bool     InpV3_EnableSQLiteBridge = true;
input bool     InpV3_EnableFileFallback = true;
input string   InpV3_SQLitePath = "MultiBotPro_v3.db";
input int      InpV3_HeartbeatIntervalMs = 1000;

// --- HEDGE MODEL ---
input double   InpEstCommCost = 8.0;  // Est. Commission Cost ($) per 1.0 Lot
input bool     InpEnableLateStageSingleSymbolLock = false;
input int      InpMaxConcurrentSymbols = 0; // Max concurrent slave symbols (0 = unlimited)

input group "--- AUTO TRADE / VALIDATOR MODE ---"
input bool     InpEnableAutoTrade = false;
input double   InpLotSize         = 0.1;
input int      InpFastMAPeriod    = 9;
input int      InpSlowMAPeriod    = 21;
input int      InpMaxSpreadPoints = 50;

// --------------------------------------

// --- PANEL ---
CHedgePanel  GUI;

// --- GLOBAL VARIABLES (CORRECTED TYPES) ---
string   SignalFileName;
string   StateFileName;
string   FeedbackFileName;
string   ActiveFileName;

bool     isInitialized     = false;
long     LastProcessedTime = 0;
ulong    LocalResetID      = 0;
double   StartEquity       = 0;
double   StartBalance      = 0;
bool     m_master_stopped  = false;
ulong    LastProcessedMasterTicket = 0;

// --- HEDGE STATE ---
string   G_LateStageLockedSymbol = "";
ulong    G_LateStageLockResetID = 0;
bool     G_LateStageModeLatched = false;

struct PendingCloseTicket {
   ulong slaveTicket;
   ulong masterTicket;
   int   feedbackAction;
   int   reasonCode;
};

struct PendingMasterFeedback {
   ulong masterTicket;
   int   feedbackAction;
   int   reasonCode;
   int   remaining;
};

PendingCloseTicket    G_PendingCloseTickets[];
PendingMasterFeedback G_PendingMasterFeedbacks[];

int      g_FastMA_Handle = INVALID_HANDLE;
int      g_SlowMA_Handle = INVALID_HANDLE;
bool     g_IsAutoTradeMode = false;

#define FEEDBACK_ACTION_FAIL 1
#define FEEDBACK_ACTION_ACK  2

#define CLOSE_REASON_MASTER_CLOSE       1
#define CLOSE_REASON_MASTER_STOP        2
#define CLOSE_REASON_FAILSAFE_HEARTBEAT 3
#define CLOSE_REASON_FAILSAFE_STATE     4
#define CLOSE_REASON_UNEXPECTED_CLOSE   5
#define CLOSE_REASON_OPEN_FAILURE       6
#define CLOSE_REASON_ORPHANED_MASTER    7

#define SLAVE_MAX_SQLITE_SIGNALS_PER_TIMER 4
#define SLAVE_MAX_FILE_SIGNALS_PER_TIMER   4
#define SLAVE_ORPHAN_CONFIRM_SECONDS       3

struct MasterFeedbackState {
   ulong masterTicket;
   int   lastAction;
};

struct OrphanCandidate {
   ulong    slaveTicket;
   ulong    masterTicket;
   datetime firstMissingAt;
};

MasterFeedbackState G_MasterFeedbackStates[];
OrphanCandidate     G_OrphanCandidates[];

string BuildSlavePanelStatusText()
{
   return "Active | " + TimeToString(GetNewYorkTime(), TIME_SECONDS) + " NY";
}

bool IsBridgeModeEnabled()
{
   return InpBridgeEnabled;
}

bool IsSQLiteRuntimeEnabled()
{
   return (InpBridgeEnabled && V3_RuntimeEnabled(InpV3_EnableSQLiteBridge, InpV3_SQLitePath));
}

bool CanUseFileFallback(bool sqliteEnabled)
{
   return (InpBridgeEnabled && (!sqliteEnabled || InpV3_EnableFileFallback));
}

double ClampDouble(double value, double minValue, double maxValue)
{
   if(value < minValue) return minValue;
   if(value > maxValue) return maxValue;
   return value;
}

int VolumeDigitsFromStep(double step)
{
   if(step <= 0.0) return 2;

   for(int digits = 0; digits < 8; digits++)
   {
      if(MathAbs(step - NormalizeDouble(step, digits)) <= 1e-8)
         return digits;
   }

   return 8;
}

double NormalizeVolumeDown(double volume, double minVolume, double step)
{
   if(step <= 0.0) step = minVolume;
   if(step <= 0.0) step = 0.01;
   if(volume <= 0.0) return 0.0;

   int digits = VolumeDigitsFromStep(step);
   double normalized = MathFloor((volume + 1e-12) / step) * step;
   normalized = NormalizeDouble(normalized, digits);

   if(normalized < minVolume - (step * 0.5))
      return 0.0;

   return normalized;
}

bool TryGetSlaveOrderType(int masterType, ENUM_ORDER_TYPE &slaveType)
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

string SignalTypeToText(int signalType)
{
   if(signalType == 0)
      return "BUY";
   if(signalType == 1)
      return "SELL";
   return "UNKNOWN";
}

string OrderTypeToText(ENUM_ORDER_TYPE orderType)
{
   if(orderType == ORDER_TYPE_BUY)
      return "BUY";
   if(orderType == ORDER_TYPE_SELL)
      return "SELL";
   return "UNKNOWN";
}

string GetCloseReasonNote(int reasonCode)
{
   switch(reasonCode)
   {
      case CLOSE_REASON_MASTER_CLOSE:       return "master_close_ack";
      case CLOSE_REASON_MASTER_STOP:        return "master_stopped";
      case CLOSE_REASON_FAILSAFE_HEARTBEAT: return "failsafe_heartbeat";
      case CLOSE_REASON_FAILSAFE_STATE:     return "failsafe_state_read";
      case CLOSE_REASON_UNEXPECTED_CLOSE:   return "slave_closed_unexpected";
      case CLOSE_REASON_OPEN_FAILURE:       return "slave_open_failed";
      case CLOSE_REASON_ORPHANED_MASTER:    return "master_orphaned";
   }

   return "";
}

ulong ResolveMasterTicketForOpenPosition(ulong positionTicket)
{
   ulong linkedMaster = GetLinkedMaster(positionTicket);
   if(linkedMaster > 0)
      return linkedMaster;

   return 0;
}

bool LoadLatestMasterState(bool sqliteEnabled, HedgeState &state)
{
   ZeroMemory(state);
   if(!InpBridgeEnabled)
      return false;

   HedgeState sqliteState;
   HedgeState fileState;
   ZeroMemory(sqliteState);
   ZeroMemory(fileState);

   bool haveSqliteState = (sqliteEnabled && V3_ReadLatestMasterState(InpV3_SQLitePath, InpChannelName, sqliteState));
   bool haveFileState = false;

   // Always read the master state file as a heartbeat fallback, even when FILE_COMMON trade fallback is disabled.
   string masterFile = GetMasterFile(InpChannelName);
   int h = FileOpenRobust(masterFile, FILE_READ|FILE_BIN|FILE_COMMON);
   if(h != INVALID_HANDLE)
   {
      haveFileState = (FileReadStruct(h, fileState) > 0);
      FileClose(h);
   }

   if(haveSqliteState && haveFileState)
   {
      state = (fileState.last_heartbeat > sqliteState.last_heartbeat) ? fileState : sqliteState;
      return true;
   }

   if(haveSqliteState)
   {
      state = sqliteState;
      return true;
   }

   if(haveFileState)
   {
      state = fileState;
      return true;
   }

   return false;
}

void ResetLateStageLockState(ulong resetId = 0)
{
   G_LateStageLockedSymbol = "";
   G_LateStageModeLatched = false;
   G_LateStageLockResetID = resetId;
}

string GetActiveLinkedSlaveSymbol()
{
   string activeSymbol = "";

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpSlaveMagic)
         continue;
      if(ResolveMasterTicketForOpenPosition(ticket) == 0)
         continue;

      string currentSymbol = PositionGetString(POSITION_SYMBOL);
      if(activeSymbol == "")
         activeSymbol = currentSymbol;
   }

   return activeSymbol;
}

bool HasActiveLinkedSymbol(string symbol)
{
   if(symbol == "")
      return false;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpSlaveMagic)
         continue;
      if(ResolveMasterTicketForOpenPosition(ticket) == 0)
         continue;

      string currentSymbol = PositionGetString(POSITION_SYMBOL);
      if(StringCompare(currentSymbol, symbol, false) == 0)
         return true;
   }

   return false;
}

int CountActiveLinkedSymbols()
{
   string activeSymbols[];
   int uniqueCount = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpSlaveMagic)
         continue;
      if(ResolveMasterTicketForOpenPosition(ticket) == 0)
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

      ArrayResize(activeSymbols, uniqueCount + 1);
      activeSymbols[uniqueCount] = currentSymbol;
      uniqueCount++;
   }

   return uniqueCount;
}

bool IsSymbolCapacityAvailable(string requestedSymbol)
{
   if(InpMaxConcurrentSymbols <= 0 || requestedSymbol == "")
      return true;

   if(HasActiveLinkedSymbol(requestedSymbol))
      return true;

   return (CountActiveLinkedSymbols() < InpMaxConcurrentSymbols);
}

void RefreshLateStageLockState(HedgeState &state)
{
   if(!InpEnableLateStageSingleSymbolLock)
   {
      ResetLateStageLockState();
      return;
   }

   ulong currentReset = (state.reset_id > 0) ? state.reset_id : LocalResetID;
   if(currentReset != G_LateStageLockResetID)
      ResetLateStageLockState(currentReset);

   double profitProgress = 0.0;
   if(state.master_target_profit > 0.0)
      profitProgress = ClampDouble(MathMax(0.0, state.master_pnl) / state.master_target_profit, 0.0, 1.0);

   double drawdownProgress = 0.0;
   if(state.master_target_risk > 0.0)
      drawdownProgress = ClampDouble(MathMax(0.0, -state.master_pnl) / state.master_target_risk, 0.0, 1.0);

   bool lateStageNow = (MathMax(profitProgress, drawdownProgress) >= 0.75);
   if(lateStageNow)
      G_LateStageModeLatched = true;

   if(!G_LateStageModeLatched)
   {
      G_LateStageLockedSymbol = "";
      return;
   }

   G_LateStageLockedSymbol = GetActiveLinkedSlaveSymbol();
}

bool IsLateStageSymbolAllowed(HedgeState &state, string newSymbol)
{
   if(!InpEnableLateStageSingleSymbolLock)
      return true;

   RefreshLateStageLockState(state);
   if(!G_LateStageModeLatched)
      return true;

   if(G_LateStageLockedSymbol == "")
   {
      G_LateStageLockedSymbol = newSymbol;
      return true;
   }

   return (StringCompare(G_LateStageLockedSymbol, newSymbol, false) == 0);
}

int FindMasterFeedbackStateIndex(ulong masterTicket)
{
   for(int i = 0; i < ArraySize(G_MasterFeedbackStates); i++)
   {
      if(G_MasterFeedbackStates[i].masterTicket == masterTicket)
         return i;
   }

   return -1;
}

bool HasMasterFeedbackState(ulong masterTicket)
{
   return (FindMasterFeedbackStateIndex(masterTicket) >= 0);
}

void ClearMasterFeedbackState(ulong masterTicket)
{
   int idx = FindMasterFeedbackStateIndex(masterTicket);
   if(idx < 0)
      return;

   int size = ArraySize(G_MasterFeedbackStates);
   for(int i = idx; i < size - 1; i++)
      G_MasterFeedbackStates[i] = G_MasterFeedbackStates[i + 1];

   ArrayResize(G_MasterFeedbackStates, size - 1);
}

void RememberMasterFeedbackState(ulong masterTicket, int action)
{
   int idx = FindMasterFeedbackStateIndex(masterTicket);
   if(idx < 0)
   {
      idx = ArraySize(G_MasterFeedbackStates);
      ArrayResize(G_MasterFeedbackStates, idx + 1);
      G_MasterFeedbackStates[idx].masterTicket = masterTicket;
   }

   G_MasterFeedbackStates[idx].lastAction = action;
}

int FindOrphanCandidateIndex(ulong slaveTicket)
{
   for(int i = 0; i < ArraySize(G_OrphanCandidates); i++)
   {
      if(G_OrphanCandidates[i].slaveTicket == slaveTicket)
         return i;
   }

   return -1;
}

void RemoveOrphanCandidate(ulong slaveTicket)
{
   int idx = FindOrphanCandidateIndex(slaveTicket);
   if(idx < 0)
      return;

   int size = ArraySize(G_OrphanCandidates);
   for(int i = idx; i < size - 1; i++)
      G_OrphanCandidates[i] = G_OrphanCandidates[i + 1];

   ArrayResize(G_OrphanCandidates, size - 1);
}

void ClearOrphanCandidates()
{
   ArrayResize(G_OrphanCandidates, 0);
}

void MarkOrphanCandidate(ulong slaveTicket, ulong masterTicket)
{
   int idx = FindOrphanCandidateIndex(slaveTicket);
   if(idx < 0)
   {
      idx = ArraySize(G_OrphanCandidates);
      ArrayResize(G_OrphanCandidates, idx + 1);
      G_OrphanCandidates[idx].slaveTicket = slaveTicket;
   }

   if(G_OrphanCandidates[idx].masterTicket != masterTicket)
   {
      G_OrphanCandidates[idx].masterTicket = masterTicket;
      G_OrphanCandidates[idx].firstMissingAt = TimeCurrent();
      return;
   }

   if(G_OrphanCandidates[idx].firstMissingAt == 0)
      G_OrphanCandidates[idx].firstMissingAt = TimeCurrent();
}

bool IsMasterStateFresh(HedgeState &state)
{
   if(state.last_heartbeat == 0)
      return false;

   ulong myTime = (ulong)TimeGMT();
   ulong diff = (myTime >= state.last_heartbeat) ? (myTime - state.last_heartbeat) : (state.last_heartbeat - myTime);
   return (diff <= (ulong)MathMax(FailsafeTimeoutSeconds, 5));
}

bool IsMasterReinitGraceActive(int &secondsRemaining)
{
   secondsRemaining = 0;

   string reinitFile = "HedgeMasterReinit_" + InpChannelName + ".bin";
   if(!FileIsExist(reinitFile, FILE_COMMON))
      return false;

   int h = FileOpenRobust(reinitFile, FILE_READ|FILE_BIN|FILE_COMMON);
   if(h == INVALID_HANDLE)
      return false;

   long expiresAt = FileReadLong(h);
   FileClose(h);

   ulong nowGmt = (ulong)TimeGMT();
   if(expiresAt <= 0 || nowGmt >= (ulong)expiresAt)
   {
      FileDelete(reinitFile, FILE_COMMON);
      return false;
   }

   secondsRemaining = (int)((ulong)expiresAt - nowGmt);
   return true;
}

int FindPendingCloseTicketIndex(ulong slaveTicket)
{
   for(int i = 0; i < ArraySize(G_PendingCloseTickets); i++)
   {
      if(G_PendingCloseTickets[i].slaveTicket == slaveTicket)
         return i;
   }

   return -1;
}

int FindPendingMasterFeedbackIndex(ulong masterTicket, int feedbackAction, int reasonCode)
{
   for(int i = 0; i < ArraySize(G_PendingMasterFeedbacks); i++)
   {
      if(G_PendingMasterFeedbacks[i].masterTicket == masterTicket &&
         G_PendingMasterFeedbacks[i].feedbackAction == feedbackAction &&
         G_PendingMasterFeedbacks[i].reasonCode == reasonCode)
      {
         return i;
      }
   }

   return -1;
}

void RemovePendingCloseTicketAt(int index)
{
   int size = ArraySize(G_PendingCloseTickets);
   if(index < 0 || index >= size)
      return;

   for(int i = index; i < size - 1; i++)
      G_PendingCloseTickets[i] = G_PendingCloseTickets[i + 1];

   ArrayResize(G_PendingCloseTickets, size - 1);
}

void RemovePendingMasterFeedbackAt(int index)
{
   int size = ArraySize(G_PendingMasterFeedbacks);
   if(index < 0 || index >= size)
      return;

   for(int i = index; i < size - 1; i++)
      G_PendingMasterFeedbacks[i] = G_PendingMasterFeedbacks[i + 1];

   ArrayResize(G_PendingMasterFeedbacks, size - 1);
}

bool AddPendingCloseTicket(ulong slaveTicket, ulong masterTicket, int feedbackAction, int reasonCode)
{
   if(slaveTicket == 0 || masterTicket == 0)
      return false;

   if(FindPendingCloseTicketIndex(slaveTicket) >= 0)
      return false;

   int closeIndex = ArraySize(G_PendingCloseTickets);
   ArrayResize(G_PendingCloseTickets, closeIndex + 1);
   G_PendingCloseTickets[closeIndex].slaveTicket = slaveTicket;
   G_PendingCloseTickets[closeIndex].masterTicket = masterTicket;
   G_PendingCloseTickets[closeIndex].feedbackAction = feedbackAction;
   G_PendingCloseTickets[closeIndex].reasonCode = reasonCode;

   int feedbackIndex = FindPendingMasterFeedbackIndex(masterTicket, feedbackAction, reasonCode);
   if(feedbackIndex < 0)
   {
      feedbackIndex = ArraySize(G_PendingMasterFeedbacks);
      ArrayResize(G_PendingMasterFeedbacks, feedbackIndex + 1);
      G_PendingMasterFeedbacks[feedbackIndex].masterTicket = masterTicket;
      G_PendingMasterFeedbacks[feedbackIndex].feedbackAction = feedbackAction;
      G_PendingMasterFeedbacks[feedbackIndex].reasonCode = reasonCode;
      G_PendingMasterFeedbacks[feedbackIndex].remaining = 0;
   }

   G_PendingMasterFeedbacks[feedbackIndex].remaining++;
   return true;
}

void CancelPendingCloseTicket(ulong slaveTicket)
{
   int closeIndex = FindPendingCloseTicketIndex(slaveTicket);
   if(closeIndex < 0)
      return;

   PendingCloseTicket info = G_PendingCloseTickets[closeIndex];
   RemovePendingCloseTicketAt(closeIndex);

   int feedbackIndex = FindPendingMasterFeedbackIndex(info.masterTicket, info.feedbackAction, info.reasonCode);
   if(feedbackIndex >= 0)
   {
      G_PendingMasterFeedbacks[feedbackIndex].remaining--;
      if(G_PendingMasterFeedbacks[feedbackIndex].remaining <= 0)
         RemovePendingMasterFeedbackAt(feedbackIndex);
   }
}

void ResolvePendingCloseTicket(ulong slaveTicket)
{
   int closeIndex = FindPendingCloseTicketIndex(slaveTicket);
   if(closeIndex < 0)
      return;

   PendingCloseTicket info = G_PendingCloseTickets[closeIndex];
   RemovePendingCloseTicketAt(closeIndex);

   int feedbackIndex = FindPendingMasterFeedbackIndex(info.masterTicket, info.feedbackAction, info.reasonCode);
   if(feedbackIndex < 0)
      return;

   G_PendingMasterFeedbacks[feedbackIndex].remaining--;
   if(G_PendingMasterFeedbacks[feedbackIndex].remaining <= 0)
   {
      ulong masterTicket = G_PendingMasterFeedbacks[feedbackIndex].masterTicket;
      int feedbackAction = G_PendingMasterFeedbacks[feedbackIndex].feedbackAction;
      int reasonCode = G_PendingMasterFeedbacks[feedbackIndex].reasonCode;
      RemovePendingMasterFeedbackAt(feedbackIndex);
      SendFeedback(masterTicket, feedbackAction, GetCloseReasonNote(reasonCode));
   }
}

bool CloseTrackedPosition(ulong slaveTicket, ulong masterTicket, int feedbackAction, int reasonCode)
{
   if(slaveTicket == 0)
      return false;

   if(FindPendingCloseTicketIndex(slaveTicket) >= 0)
      return true;

   if(!AddPendingCloseTicket(slaveTicket, masterTicket, feedbackAction, reasonCode))
      return false;

   if(Trade.PositionClose(slaveTicket))
      return true;

   CancelPendingCloseTicket(slaveTicket);
   PrintFormat("Close request failed: slave=%I64u master=%I64u action=%d reason=%d err=%d", slaveTicket, masterTicket, feedbackAction, reasonCode, GetLastError());
   return false;
}

void CloseLinkedSlaveTradesByMaster(ulong masterTicket, int feedbackAction, int reasonCode)
{
   if(masterTicket == 0)
      return;

   int matches = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong slaveTicket = PositionGetTicket(i);
      if(!PositionSelectByTicket(slaveTicket))
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpSlaveMagic)
         continue;
      if(ResolveMasterTicketForOpenPosition(slaveTicket) != masterTicket)
         continue;

      matches++;
      CloseTrackedPosition(slaveTicket, masterTicket, feedbackAction, reasonCode);
   }

   if(matches == 0 && feedbackAction == FEEDBACK_ACTION_ACK && !HasMasterFeedbackState(masterTicket))
      SendFeedback(masterTicket, feedbackAction, GetCloseReasonNote(reasonCode));
}

void CloseAllLinkedSlaveTrades(int feedbackAction, int reasonCode)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong slaveTicket = PositionGetTicket(i);
      if(!PositionSelectByTicket(slaveTicket))
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpSlaveMagic)
         continue;

      ulong masterTicket = ResolveMasterTicketForOpenPosition(slaveTicket);
      if(masterTicket > 0)
      {
         CloseTrackedPosition(slaveTicket, masterTicket, feedbackAction, reasonCode);
      }
      else
      {
         Trade.PositionClose(slaveTicket);
      }
   }
}

double EstimateSplitMargin(string symbol, ENUM_ORDER_TYPE orderType, double totalLots, double minVolume, double maxVolume, double step, double price)
{
   double remaining = NormalizeVolumeDown(totalLots, minVolume, step);
   double totalMargin = 0.0;

   while(remaining >= minVolume)
   {
      double chunk = MathMin(maxVolume, remaining);
      chunk = NormalizeVolumeDown(chunk, minVolume, step);
      if(chunk < minVolume)
         break;

      double chunkMargin = 0.0;
      if(!OrderCalcMargin(orderType, symbol, chunk, price, chunkMargin))
         return -1.0;

      totalMargin += chunkMargin;
      remaining = NormalizeVolumeDown(remaining - chunk, minVolume, step);
   }

   return totalMargin;
}

double FitLotsToMargin(string symbol, ENUM_ORDER_TYPE orderType, double totalLots, double minVolume, double maxVolume, double step, double price)
{
   double freeMarginCap = AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.98;
   double fittedLots = NormalizeVolumeDown(totalLots, minVolume, step);
   int guard = 0;

   while(fittedLots >= minVolume && guard < 5000)
   {
      guard++;
      double requiredMargin = EstimateSplitMargin(symbol, orderType, fittedLots, minVolume, maxVolume, step, price);
      if(requiredMargin >= 0.0 && requiredMargin <= freeMarginCap)
         return fittedLots;

      fittedLots = NormalizeVolumeDown(fittedLots - step, minVolume, step);
   }

   return 0.0;
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   bool isTester = (bool)MQLInfoInteger(MQL_TESTER);
   g_IsAutoTradeMode = (isTester || (!InpBridgeEnabled && InpEnableAutoTrade));

   if(InpBridgeEnabled && !InpV3_EnableSQLiteBridge && !InpV3_EnableFileFallback)
   {
      Print(EmojiWarning(), " Bridge is enabled, but both SQLite and file fallback are disabled. Initialization failed.");
      return INIT_FAILED;
   }

   if(g_IsAutoTradeMode)
   {
      if(isTester)
      {
         Print(EmojiTest(), " Strategy Tester detected. Running local auto-trade mode for validation.");
      }
      else
      {
         Print(EmojiBrain(), " Bridge disabled. Running the slave local auto-trader.");
      }

      Trade.SetExpertMagicNumber(InpSlaveMagic);
      g_FastMA_Handle = iMA(_Symbol, _Period, InpFastMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
      g_SlowMA_Handle = iMA(_Symbol, _Period, InpSlowMAPeriod, 0, MODE_SMA, PRICE_CLOSE);

      if(g_FastMA_Handle == INVALID_HANDLE || g_SlowMA_Handle == INVALID_HANDLE)
         return INIT_FAILED;

      EventSetMillisecondTimer(InpHeartbeat);
      isInitialized = true;
      return INIT_SUCCEEDED;
   }

   SignalFileName   = GetSignalFile(InpChannelName);
   StateFileName    = "HedgeState_" + InpChannelName + ".bin";
   FeedbackFileName = GetFeedbackFile(InpChannelName);
   ActiveFileName   = "HedgeActive_" + InpChannelName + ".bin";

   if(InpBridgeEnabled && IsSQLiteRuntimeEnabled())
   {
      if(V3_EnsureRuntimeSchema(InpV3_SQLitePath))
         Print(EmojiBrain(), " Slave SQLite bridge ready: ", InpV3_SQLitePath);
      else
         Print(EmojiWarning(), " Slave SQLite schema init failed. Using the file fallback.");
   }
   else if(!InpBridgeEnabled)
   {
      Print(EmojiBrain(), " Bridge disabled. Slave bridge I/O is off.");
   }

   StartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(GlobalVariableCheck(InpChannelName + "_SlaveStartEq"))
   {
      double savedEq = GlobalVariableGet(InpChannelName + "_SlaveStartEq");
      if(savedEq > 0 && savedEq < 100000000)
         StartEquity = savedEq;
   }
   GlobalVariableSet(InpChannelName + "_SlaveStartEq", StartEquity);

   StartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(GlobalVariableCheck(InpChannelName + "_SlaveStartBal"))
   {
      double savedBal = GlobalVariableGet(InpChannelName + "_SlaveStartBal");
      if(savedBal > 0 && savedBal < 100000000)
         StartBalance = savedBal;
   }
   GlobalVariableSet(InpChannelName + "_SlaveStartBal", StartBalance);

   if(GlobalVariableCheck(InpChannelName + "_SlaveResetID"))
      LocalResetID = (ulong)GlobalVariableGet(InpChannelName + "_SlaveResetID");
   ResetLateStageLockState(LocalResetID);

   if(!GUI.CreatePanel("HedgeSlave", false))
      return INIT_FAILED;
   GUI.Run();

   LoadMap();
   EventSetMillisecondTimer(InpHeartbeat);

   isInitialized = true;
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeInit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) { 
   if(g_FastMA_Handle != INVALID_HANDLE) IndicatorRelease(g_FastMA_Handle);
   if(g_SlowMA_Handle != INVALID_HANDLE) IndicatorRelease(g_SlowMA_Handle);
   GUI.Destroy(); 
   EventKillTimer(); 
}

//+------------------------------------------------------------------+
//| OnTimer (Queue Processing + Fixed Timestamp Logic)               |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(!isInitialized) return;

   if(g_IsAutoTradeMode)
   {
      CheckTradeSignalsBase();
      return;
   }

   static HedgeState st;
   bool sqliteEnabled = IsSQLiteRuntimeEnabled();
   m_master_stopped = false;
   int reinitGraceRemaining = 0;
   bool masterReinitGrace = IsMasterReinitGraceActive(reinitGraceRemaining);

   if(!InpBridgeEnabled)
   {
      st.slave_pnl = AccountInfoDouble(ACCOUNT_EQUITY) - StartEquity;
      GUI.UpdateStats(st);
      GUI.SetStatusText(BuildSlavePanelStatusText());
      return;
   }

   CheckProposals();

   if(GUI.CheckResetRequest())
   {
      StartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      GlobalVariableSet(InpChannelName + "_SlaveStartEq", StartEquity);
      StartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      GlobalVariableSet(InpChannelName + "_SlaveStartBal", StartBalance);
      st.slave_pnl = 0.0;

      long newID = (long)TimeCurrent();
      LocalResetID = newID;
      GlobalVariableSet(InpChannelName + "_SlaveResetID", (double)LocalResetID);
      ResetLateStageLockState(LocalResetID);

      string resetFile = "HedgeReset_" + InpChannelName + ".bin";
      int hRst = FileOpen(resetFile, FILE_WRITE|FILE_BIN|FILE_COMMON);
      if(hRst != INVALID_HANDLE)
      {
         FileWriteLong(hRst, newID);
         FileClose(hRst);
      }
      Print(EmojiReset(), " Slave initiated reset. Command sent to MultiBotPro.");
   }

   string slaveFile    = GetSlaveFile(InpChannelName);
   string sigFileName  = GetSignalFile(InpChannelName);
   string procFileName = "HedgeSignal_" + InpChannelName + "_PROC.bin";

   if(sqliteEnabled)
   {
      int processedSignals = 0;
      while(processedSignals < SLAVE_MAX_SQLITE_SIGNALS_PER_TIMER)
      {
         long signalRowId = -1;
         HedgeSignal sig;
         if(!V3_SelectPendingSignalRow(InpV3_SQLitePath, InpChannelName, signalRowId, sig))
            break;

         if(sig.time_msc > LastProcessedTime)
            LastProcessedTime = sig.time_msc;
         ProcessSignal(sig);
         V3_MarkSignalProcessed(InpV3_SQLitePath, signalRowId);
         processedSignals++;
      }
   }

   if(CanUseFileFallback(sqliteEnabled) && FileIsExist(sigFileName, FILE_COMMON))
   {
      if(!FileIsExist(procFileName, FILE_COMMON))
         FileMove(sigFileName, FILE_COMMON, procFileName, FILE_COMMON);
   }

   if(CanUseFileFallback(sqliteEnabled) && FileIsExist(procFileName, FILE_COMMON))
      ProcessSignalFileBatch(procFileName, SLAVE_MAX_FILE_SIGNALS_PER_TIMER);

   bool stateReadSuccess = LoadLatestMasterState(sqliteEnabled, st);
   if(stateReadSuccess && st.reset_id > LocalResetID)
   {
      Print(EmojiReset(), " Reset command accepted. MasterID=", st.reset_id, " | LocalID=", LocalResetID);
      LocalResetID = st.reset_id;
      GlobalVariableSet(InpChannelName + "_SlaveResetID", (double)LocalResetID);
      ResetLateStageLockState(LocalResetID);

      StartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      GlobalVariableSet(InpChannelName + "_SlaveStartEq", StartEquity);
      StartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      GlobalVariableSet(InpChannelName + "_SlaveStartBal", StartBalance);
      st.slave_pnl = 0.0;
   }

   static ulong lastValidReadTime = (ulong)TimeGMT();
   if(stateReadSuccess)
   {
      lastValidReadTime = (ulong)TimeGMT();
      ulong myTime = (ulong)TimeGMT();
      ulong diff = (myTime >= st.last_heartbeat) ? (myTime - st.last_heartbeat) : (st.last_heartbeat - myTime);
      bool masterStopFlag = (GlobalVariableCheck(InpChannelName + "_STOP_FLAG") && GlobalVariableGet(InpChannelName + "_STOP_FLAG") > 0.5);
      m_master_stopped = (st.is_daily_stopped || st.is_total_stopped || masterStopFlag);

      if(m_master_stopped)
         CloseAllLinkedSlaveTrades(FEEDBACK_ACTION_ACK, CLOSE_REASON_MASTER_STOP);

      if(diff > (ulong)FailsafeTimeoutSeconds && st.last_heartbeat > 0)
      {
         if(masterReinitGrace && !m_master_stopped)
         {
            static datetime lastReinitHeartbeatLog = 0;
            if(TimeCurrent() - lastReinitHeartbeatLog >= 900)
            {
               PrintFormat(EmojiShield() + " Master reinit grace active [%s NY Time]: heartbeat is stale by %ds. Keeping slave hedges alive for %ds.",
                           TimeToString(GetNewYorkTime(), TIME_DATE|TIME_MINUTES),
                           diff,
                           reinitGraceRemaining);
               lastReinitHeartbeatLog = TimeCurrent();
            }
         }
         else
         {
            static datetime lastHeartbeatLog = 0;
            if(TimeCurrent() - lastHeartbeatLog >= 3600)
            {
               PrintFormat(EmojiWarning() + " Critical [%s NY Time]: master heartbeat stale (diff: %ds). Closing slave trades.", 
                           TimeToString(GetNewYorkTime(), TIME_DATE|TIME_MINUTES), diff);
               lastHeartbeatLog = TimeCurrent();
            }

            CloseAllLinkedSlaveTrades(FEEDBACK_ACTION_FAIL, CLOSE_REASON_FAILSAFE_HEARTBEAT);
         }
      }
   }
   else
   {
      ulong myTime = (ulong)TimeGMT();
      ulong readDiff = (myTime >= lastValidReadTime) ? (myTime - lastValidReadTime) : (lastValidReadTime - myTime);
      if(readDiff > (ulong)FailsafeTimeoutSeconds)
      {
         if(masterReinitGrace)
         {
            static datetime lastReinitReadLog = 0;
            if(TimeCurrent() - lastReinitReadLog >= 900)
            {
               PrintFormat(EmojiShield() + " Master reinit grace active [%s NY Time]: master state is unavailable for %ds. Keeping slave hedges alive for %ds.",
                           TimeToString(GetNewYorkTime(), TIME_DATE|TIME_MINUTES),
                           readDiff,
                           reinitGraceRemaining);
               lastReinitReadLog = TimeCurrent();
            }
            lastValidReadTime = (ulong)TimeGMT();
         }
         else
         {
            static datetime lastReadLog = 0;
            if(TimeCurrent() - lastReadLog >= 3600)
            {
               PrintFormat(EmojiWarning() + " Critical [%s NY Time]: cannot read master state for %ds. Closing slave trades.", 
                           TimeToString(GetNewYorkTime(), TIME_DATE|TIME_MINUTES), readDiff);
               lastReadLog = TimeCurrent();
            }

            CloseAllLinkedSlaveTrades(FEEDBACK_ACTION_FAIL, CLOSE_REASON_FAILSAFE_STATE);
            lastValidReadTime = (ulong)TimeGMT();
         }
      }
   }

   st.slave_pnl = AccountInfoDouble(ACCOUNT_EQUITY) - StartEquity;

   HedgeState myStats;
   ZeroMemory(myStats);
   myStats.slave_pnl = st.slave_pnl;
   myStats.last_heartbeat = (ulong)TimeGMT();
   myStats.reset_id = LocalResetID;

   if(sqliteEnabled)
      V3_WriteSlaveStateRow(InpV3_SQLitePath, InpChannelName, myStats);

   if(CanUseFileFallback(sqliteEnabled))
   {
      int h = FileOpen(slaveFile, FILE_WRITE|FILE_BIN|FILE_COMMON);
      if(h != INVALID_HANDLE)
      {
         FileWriteStruct(h, myStats);
         FileClose(h);
      }
   }

   WriteSlaveActiveTrades();
   GUI.UpdateStats(st);
   GUI.SetStatusText(BuildSlavePanelStatusText());
   CheckOrphans(stateReadSuccess, st);
}
//+------------------------------------------------------------------+
//| Write Active Trades for Master's Orphan Checker                |
//+------------------------------------------------------------------+
void WriteSlaveActiveTrades()
{
   string activeSlaveFile = "HedgeSlaveActive_" + InpChannelName + ".bin";
   int hOut = FileOpen(activeSlaveFile, FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(hOut != INVALID_HANDLE)
   {
      ulong tickets[];
      int count = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(ticket))
         {
            if(PositionGetInteger(POSITION_MAGIC) == InpSlaveMagic)
            {
               ulong linkedMasterTicket = GetLinkedMaster(ticket);
               if(linkedMasterTicket == 0)
                  continue;

               count++;
               ArrayResize(tickets, count);
               tickets[count-1] = linkedMasterTicket;
            }
         }
      }
      FileWriteInteger(hOut, count, INT_VALUE);
      if(count > 0) FileWriteArray(hOut, tickets);
      FileClose(hOut);
   }
}
//+------------------------------------------------------------------+
//| Compare my trades against Master's Active List                   |
//+------------------------------------------------------------------+
void CheckOrphans(bool stateReadSuccess, HedgeState &state)
{
   int reinitGraceRemaining = 0;
   if(IsMasterReinitGraceActive(reinitGraceRemaining) ||
      !stateReadSuccess || !IsMasterStateFresh(state) || state.is_daily_stopped || state.is_total_stopped || m_master_stopped)
   {
      ClearOrphanCandidates();
      return;
   }

   ulong masterTickets[];
   bool readSuccess = false;
   if(FileIsExist(ActiveFileName, FILE_COMMON)) {
      int h = FileOpenRobust(ActiveFileName, FILE_READ|FILE_BIN|FILE_COMMON);
      if(h != INVALID_HANDLE) {
         int count = FileReadInteger(h);
         if(count > 0) {
            ArrayResize(masterTickets, count);
            FileReadArray(h, masterTickets);
         }
         FileClose(h);
         readSuccess = true;
      }
   }
   if(!readSuccess)
   {
      ClearOrphanCandidates();
      return;
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong slaveTicket = PositionGetTicket(i);
      if(!PositionSelectByTicket(slaveTicket))
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpSlaveMagic)
         continue;

      long openTime = PositionGetInteger(POSITION_TIME);
      if(TimeCurrent() - openTime < 10)
         continue;

      ulong linkedMasterTicket = ResolveMasterTicketForOpenPosition(slaveTicket);
      if(linkedMasterTicket == 0)
      {
         RemoveOrphanCandidate(slaveTicket);
         continue;
      }

      bool stillActive = false;
      for(int j = 0; j < ArraySize(masterTickets); j++)
      {
         if(masterTickets[j] == linkedMasterTicket)
         {
            stillActive = true;
            break;
         }
      }

      if(stillActive)
      {
         RemoveOrphanCandidate(slaveTicket);
         continue;
      }

      MarkOrphanCandidate(slaveTicket, linkedMasterTicket);
      int orphanIndex = FindOrphanCandidateIndex(slaveTicket);
      if(orphanIndex < 0)
         continue;

      if((TimeCurrent() - G_OrphanCandidates[orphanIndex].firstMissingAt) < SLAVE_ORPHAN_CONFIRM_SECONDS)
         continue;

      Print(EmojiShield(), " Orphaned trade detected. Master trade ", linkedMasterTicket, " is gone. Closing slave ", slaveTicket);
      CloseTrackedPosition(slaveTicket, linkedMasterTicket, FEEDBACK_ACTION_FAIL, CLOSE_REASON_ORPHANED_MASTER);
      RemoveOrphanCandidate(slaveTicket);
   }

   for(int i = ArraySize(G_OrphanCandidates) - 1; i >= 0; i--)
   {
      if(!PositionSelectByTicket(G_OrphanCandidates[i].slaveTicket))
         RemoveOrphanCandidate(G_OrphanCandidates[i].slaveTicket);
   }
}

//+------------------------------------------------------------------+
//| Helper: Extract Ticket safely from comment                       |
//+------------------------------------------------------------------+
ulong ExtractTicketFromComment(string comment)
{
   return 0;
}

//+------------------------------------------------------------------+
//| EVENT HANDLER: REQUIRED FOR MOVING THE PANEL & BUTTON CLICKS     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   GUI.ChartEvent(id, lparam, dparam, sparam);
}

//+------------------------------------------------------------------+
//| FEEDBACK LOOP: Detect Slave Close -> Tell Master                 |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;

   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
      return;

   ulong posID = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   ulong masterTicket = GetLinkedMaster(posID);
   if(masterTicket == 0)
      masterTicket = GetMasterTicketFromPosition(posID);

   if(masterTicket == 0)
   {
      RemoveLink(posID);
      return;
   }

   Print(EmojiShield(), " Slave trade closed. Linked master ticket: ", masterTicket);
   if(FindPendingCloseTicketIndex(posID) >= 0)
      ResolvePendingCloseTicket(posID);
   else
      SendFeedback(masterTicket, FEEDBACK_ACTION_FAIL, GetCloseReasonNote(CLOSE_REASON_UNEXPECTED_CLOSE));

   RemoveLink(posID);
}
ulong GetMasterTicketFromPosition(ulong positionID)
{
   if(!HistorySelectByPosition(positionID))
      return 0;

   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_IN)
         continue;
   }

   return 0;
}
void ProcessSignal(HedgeSignal &sig)
{
   if(!InpBridgeEnabled)
      return;

   string masterSym = CharArrayToString(sig.symbol);
   string mySym = GetMappedSymbol(masterSym);

   if(sig.action == 1)
   {
      if(sig.ticket == LastProcessedMasterTicket)
         return;

      ENUM_ORDER_TYPE slaveType;
      if(!TryGetSlaveOrderType(sig.type, slaveType))
      {
         PrintFormat(EmojiWarning() + " Invalid bridge side for master ticket %I64u (type=%d). Rejecting the hedge.", sig.ticket, sig.type);
         SendFeedback(sig.ticket, FEEDBACK_ACTION_FAIL, "invalid_master_side");
         return;
      }

      bool sqliteEnabled = IsSQLiteRuntimeEnabled();
      HedgeState state;
      if(!LoadLatestMasterState(sqliteEnabled, state))
      {
         Print(EmojiWarning(), " Unable to load the master state. Rejecting the slave hedge for ticket ", sig.ticket);
         SendFeedback(sig.ticket, FEEDBACK_ACTION_FAIL, "master_state_unavailable");
         return;
      }

      if(state.is_paused || state.is_daily_stopped || state.is_total_stopped)
      {
         Print(EmojiWarning(), " Master is paused or stopped. Rejecting the slave hedge for ticket ", sig.ticket);
         SendFeedback(sig.ticket, FEEDBACK_ACTION_FAIL, "master_blocked");
         return;
      }

      if(!IsLateStageSymbolAllowed(state, mySym))
      {
         Print(EmojiWarning(), " Late-stage symbol lock rejected ", mySym, " for master ticket ", sig.ticket);
         SendFeedback(sig.ticket, FEEDBACK_ACTION_FAIL, "symbol_lock");
         return;
      }

      if(!IsSymbolCapacityAvailable(mySym))
      {
         PrintFormat(EmojiWarning() + " Slave symbol cap reached. Rejected hedge open for master ticket %I64u | symbol=%s | active_symbols=%d | limit=%d",
                     sig.ticket, mySym, CountActiveLinkedSymbols(), InpMaxConcurrentSymbols);
         SendFeedback(sig.ticket, FEEDBACK_ACTION_FAIL, "symbol_limit");
         return;
      }

      double myLots = CalculateRobustLots(sig, mySym, state, slaveType, "executed");
      if(myLots <= 0.0)
      {
         Print(EmojiWarning(), " Slave hedge lot calculation failed for master ticket ", sig.ticket);
         SendFeedback(sig.ticket, FEEDBACK_ACTION_FAIL, "lot_calc_failed");
         return;
      }

      string masterCmt = CharArrayToString(sig.comment);
      string finalCmt = masterCmt;

      PrintFormat(EmojiShield() + " Hedge open: executed master %s -> slave %s | ticket=%I64u | symbol=%s | lots=%.2f",
                  SignalTypeToText(sig.type), OrderTypeToText(slaveType), sig.ticket, mySym, myLots);
      if(OpenLinkedHedgeTrades(mySym, slaveType, myLots, sig.sl_dist_points, sig.tp_dist_points, finalCmt, sig.ticket))
         LastProcessedMasterTicket = sig.ticket;
   }
   else if(sig.action == 2)
   {
      CloseLinkedSlaveTradesByMaster(sig.ticket, FEEDBACK_ACTION_ACK, CLOSE_REASON_MASTER_CLOSE);
   }
}
double CalculateRobustLots(HedgeSignal &sig, string mySym, HedgeState &st, ENUM_ORDER_TYPE slaveType, string stageLabel)
{
   if(!SymbolSelect(mySym, true))
   {
      Print(EmojiWarning(), " Slave could not select symbol '", mySym, "'. Hedge denied.");
      return -1.0;
   }

   if(st.master_target_risk <= 0.0 || st.slave_target_gain <= 0.0 || sig.risk_money <= 0.0)
   {
      PrintFormat(EmojiWarning() + " Hedge sizing failed: invalid state values. master_risk=%.2f slave_target=%.2f signal_risk=%.2f",
                  st.master_target_risk, st.slave_target_gain, sig.risk_money);
      return -1.0;
   }

   double baseRatio = st.slave_target_gain / st.master_target_risk;
   double baselineCash = sig.risk_money * baseRatio;
   if(baselineCash <= 0.0)
      return -1.0;

   double masterDD = MathMax(0.0, -st.master_pnl);
   double masterProgress = ClampDouble(masterDD / st.master_target_risk, 0.0, 1.0);
   double targetSlavePnL = st.slave_target_gain * masterProgress;
   double progressGap = targetSlavePnL - st.slave_pnl;

   double desiredTradeCash = baselineCash;
   if(st.slave_pnl < st.slave_target_gain)
   {
      double signalWeight = ClampDouble(sig.risk_money / st.master_target_risk, 0.08, 0.18);
      double rawCorrection = progressGap * signalWeight * 0.40;
      double correction = ClampDouble(rawCorrection, -0.20 * baselineCash, 0.30 * baselineCash);
      desiredTradeCash = MathMax(0.0, baselineCash + correction);
   }

   if(desiredTradeCash <= 0.0)
   {
      PrintFormat(EmojiWarning() + " Hedge sizing failed: desired hedge cash is non-positive. baseline=%.2f gap=%.2f", baselineCash, progressGap);
      return -1.0;
   }

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
      double costPerLot = ((actualPhysicalDist / tickSize) * tickVal) + spreadCostPerLot + InpEstCommCost;
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

   totalLots = NormalizeVolumeDown(totalLots, minVolume, step);
   if(totalLots < minVolume)
   {
      PrintFormat(EmojiWarning() + " Hedge sizing failed: calculated lots %.4f is below the broker minimum %.2f", totalLots, minVolume);
      return -1.0;
   }

   double entryPrice = (slaveType == ORDER_TYPE_BUY) ? SymbolInfoDouble(mySym, SYMBOL_ASK) : SymbolInfoDouble(mySym, SYMBOL_BID);
   double fittedLots = FitLotsToMargin(mySym, slaveType, totalLots, minVolume, maxVolume, step, entryPrice);
   if(fittedLots < minVolume)
   {
      PrintFormat(EmojiWarning() + " Hedge sizing failed on margin: unable to fund the minimum lot %.2f. Free margin: %.2f",
                  minVolume, AccountInfoDouble(ACCOUNT_MARGIN_FREE));
      return -1.0;
   }

   PrintFormat(EmojiCalc() + " Hedge sizing [%s]: ticket=%I64u | master=%s -> slave=%s | BaseCash=$%.2f | TargetNow=$%.2f | Gap=$%.2f | Desired=$%.2f -> Total Lots: %.2f",
               stageLabel,
               sig.ticket,
               SignalTypeToText(sig.type),
               OrderTypeToText(slaveType),
               baselineCash,
               targetSlavePnL,
               progressGap,
               desiredTradeCash,
               fittedLots);
   return fittedLots;
}

bool OpenTrade(string sym, ENUM_ORDER_TYPE type, double lots, double sl_pts, double tp_pts, string comment, ulong masterTicket, ulong &slaveTicket)
{
   slaveTicket = 0;

   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID);
   double sl = 0.0;
   double tp = 0.0;

   CTrade tradeObj;
   tradeObj.SetExpertMagicNumber(InpSlaveMagic);
   if(!tradeObj.PositionOpen(sym, type, lots, price, sl, tp, comment))
   {
      PrintFormat(EmojiWarning() + " Hedge order failed: sym=%s side=%s lots=%.2f retcode=%u err=%d", sym, OrderTypeToText(type), lots, tradeObj.ResultRetcode(), GetLastError());
      return false;
   }

   slaveTicket = tradeObj.ResultOrder();
   if(slaveTicket == 0)
   {
      PrintFormat(EmojiWarning() + " Hedge order opened, but no slave ticket was returned for master %I64u.", masterTicket);
      return false;
   }

   AddLink(slaveTicket, masterTicket);
   Print(EmojiShield(), " Hedge child opened. Linked slave #", slaveTicket, " to master #", masterTicket, " (hidden map)");
   return true;
}

bool OpenLinkedHedgeTrades(string sym, ENUM_ORDER_TYPE type, double totalLots, double sl_pts, double tp_pts, string comment, ulong masterTicket)
{
   double minVolume = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxVolume = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = minVolume;
   if(step <= 0.0) step = 0.01;

   double remaining = NormalizeVolumeDown(totalLots, minVolume, step);
   if(remaining < minVolume)
      return false;

   double executedLots = 0.0;
   ulong openedTickets[];

   while(remaining >= minVolume)
   {
      double chunk = MathMin(maxVolume, remaining);
      chunk = NormalizeVolumeDown(chunk, minVolume, step);
      if(chunk < minVolume)
         break;

      ulong slaveTicket = 0;
      if(!OpenTrade(sym, type, chunk, sl_pts, tp_pts, comment, masterTicket, slaveTicket))
      {
         if(ArraySize(openedTickets) == 0)
         {
            SendFeedback(masterTicket, FEEDBACK_ACTION_FAIL, GetCloseReasonNote(CLOSE_REASON_OPEN_FAILURE));
         }
         else
         {
            for(int i = 0; i < ArraySize(openedTickets); i++)
               CloseTrackedPosition(openedTickets[i], masterTicket, FEEDBACK_ACTION_FAIL, CLOSE_REASON_OPEN_FAILURE);
         }
         return false;
      }

      int openedCount = ArraySize(openedTickets);
      ArrayResize(openedTickets, openedCount + 1);
      openedTickets[openedCount] = slaveTicket;
      executedLots += chunk;
      remaining = NormalizeVolumeDown(remaining - chunk, minVolume, step);
   }

   double residual = totalLots - executedLots;
   if(residual > (step * 0.5))
      PrintFormat(EmojiWarning() + " Split hedge residual omitted: %.4f lots on %s", residual, sym);

   return (executedLots > 0.0);
}

void CloseByMasterTicket(string masterTicketStr)
{
   CloseLinkedSlaveTradesByMaster((ulong)StringToInteger(masterTicketStr), FEEDBACK_ACTION_ACK, CLOSE_REASON_MASTER_CLOSE);
}

//+------------------------------------------------------------------+
//| Wrapper: GetMappedSymbol (Now with Auto-Detect Fallback)         |
//+------------------------------------------------------------------+
string GetMappedSymbol(string in)
{
   if(StringLen(InpSymbolMap) > 0)
   {
       string map[];
       StringSplit(InpSymbolMap, ',', map);
       for(int i=0; i<ArraySize(map); i++) {
          string pair[];
          StringSplit(map[i], '=', pair);
          if(ArraySize(pair)==2) {
             if(StringCompare(pair[0], in, false)==0) return pair[1];
          }
       }
   }
   return GetBaseSymbol(in);
}

//+------------------------------------------------------------------+
//| Helper: Parse Real Symbol from Analysis Symbol (Dynamic)         |
//+------------------------------------------------------------------+
string GetBaseSymbol(string analysisSymbol)
{
   string candidates[];
   string guess = "";
   
   if(StringSplit(analysisSymbol, '_', candidates) > 1)
   {
      guess = candidates[0];
      if(SymbolSelect(guess, true)) return guess;
   }
   
   if(StringSplit(analysisSymbol, '.', candidates) > 1)
   {
      guess = candidates[0];
      if(SymbolSelect(guess, true)) return guess;
   }
   
   if(StringSplit(analysisSymbol, ' ', candidates) > 1)
   {
      guess = candidates[0];
      if(SymbolSelect(guess, true)) return guess;
   }

   if(SymbolSelect(analysisSymbol, true)) return analysisSymbol;
   return analysisSymbol;
}

//+------------------------------------------------------------------+
//| HELPER: Send Feedback to Master (e.g. Kill Command)              |
//+------------------------------------------------------------------+
void SendFeedback(ulong ticket, int action, string note = "")
{
   if(!InpBridgeEnabled || ticket == 0)
      return;

   if(HasMasterFeedbackState(ticket))
      return;

   bool sqliteEnabled = IsSQLiteRuntimeEnabled();
   if(sqliteEnabled)
   {
      if(V3_InsertFeedbackRow(InpV3_SQLitePath, InpChannelName, ticket, action, note))
      {
         RememberMasterFeedbackState(ticket, action);
         PrintFormat(EmojiShield() + " Feedback sent to SQLite: ticket=%I64u action=%d note=%s", ticket, action, note);
         return;
      }

      if(!CanUseFileFallback(sqliteEnabled))
      {
         Print(EmojiWarning(), " Feedback write failed in SQLite and the file fallback is disabled.");
         return;
      }

      Print(EmojiWarning(), " Feedback write failed in SQLite. Falling back to the file bridge.");
   }
   else if(!CanUseFileFallback(sqliteEnabled))
   {
      Print(EmojiWarning(), " Feedback failed: no bridge transport is available.");
      return;
   }

   HedgeFeedback fb;
   fb.master_ticket = ticket;
   fb.action = action;

   int h = FileOpenRobust(FeedbackFileName, FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(h != INVALID_HANDLE)
   {
      FileWriteStruct(h, fb);
      FileClose(h);
      RememberMasterFeedbackState(ticket, action);
      PrintFormat(EmojiShield() + " Feedback sent via the file bridge: ticket=%I64u action=%d", ticket, action);
   }
   else
   {
      Print(EmojiWarning(), " Feedback failed: the file bridge was unavailable after 10 retries.");
   }
}
void ProcessSignalFileBatch(const string procFileName, const int maxSignals)
{
   int h = FileOpen(procFileName, FILE_READ|FILE_BIN|FILE_COMMON);
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
      if(pending[i].time_msc > LastProcessedTime)
         LastProcessedTime = pending[i].time_msc;
      ProcessSignal(pending[i]);
   }

   if(processCount >= total)
   {
      FileDelete(procFileName, FILE_COMMON);
      return;
   }

   int hw = FileOpen(procFileName, FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(hw == INVALID_HANDLE)
      return;

   for(int i = processCount; i < total; i++)
      FileWriteStruct(hw, pending[i]);

   FileClose(hw);
}

void CheckProposals()
{
   if(!InpBridgeEnabled)
      return;

   string proposalFile = GetProposalFile(InpChannelName);
   string replyFile    = GetReplyFile(InpChannelName);
   bool sqliteEnabled  = IsSQLiteRuntimeEnabled();

   BridgeProposal prop;
   ZeroMemory(prop);
   bool hasProposal = false;
   bool sqliteProposal = false;
   long proposalRowId = -1;
   string requestId = "";

   if(sqliteEnabled)
   {
      if(V3_SelectPendingProposalRow(InpV3_SQLitePath, InpChannelName, proposalRowId, requestId, prop))
      {
         hasProposal = true;
         sqliteProposal = true;
      }
   }

   if(!hasProposal && CanUseFileFallback(sqliteEnabled) && FileIsExist(proposalFile, FILE_COMMON))
   {
      int h = FileOpen(proposalFile, FILE_READ|FILE_BIN|FILE_COMMON);
      if(h == INVALID_HANDLE) return;

      FileReadStruct(h, prop);
      FileClose(h);
      FileDelete(proposalFile, FILE_COMMON);

      requestId = StringFormat("%I64u", prop.ticket);
      hasProposal = true;
   }

   if(!hasProposal)
      return;

   HedgeSignal sig;
   ZeroMemory(sig);
   sig.time_msc = prop.time_msc;
   sig.ticket   = prop.ticket;
   sig.action   = prop.action;
   sig.type     = prop.type;
   sig.lots     = prop.lots;
   sig.sl_dist_points = prop.sl_dist_points;
   sig.tp_dist_points = prop.tp_dist_points;
   sig.risk_money = prop.risk_money;
   ArrayCopy(sig.symbol, prop.symbol);

   string masterSym = CharArrayToString(sig.symbol);
   string mySym = GetMappedSymbol(masterSym);

   HedgeState state;
   bool stateLoaded = LoadLatestMasterState(sqliteEnabled, state);

   BridgeReply reply;
   ZeroMemory(reply);
   reply.master_ticket = prop.ticket;
   string replyNote = "denied";

   static datetime lastDenyLog = 0;
   bool canLogDenial = (TimeCurrent() - lastDenyLog >= 3600);

   if(!stateLoaded)
   {
      reply.action = 0;
      replyNote = "master_state_unavailable";
      if(canLogDenial)
      {
         Print(EmojiWarning(), " Handshake denied: the master state is unavailable.");
         lastDenyLog = TimeCurrent();
      }
   }
   else if(state.is_paused || state.is_daily_stopped || state.is_total_stopped)
   {
      reply.action = 0;
      replyNote = "master_blocked";
      if(canLogDenial)
      {
         Print(EmojiWarning(), " Handshake denied: the master cooldown or stop mode is active.");
         lastDenyLog = TimeCurrent();
      }
   }
   else if(!IsLateStageSymbolAllowed(state, mySym))
   {
      reply.action = 0;
      replyNote = "symbol_lock";
      if(canLogDenial)
      {
         Print(EmojiWarning(), " Handshake denied: the late-stage symbol lock is active for ", mySym);
         lastDenyLog = TimeCurrent();
      }
   }
   else if(!IsSymbolCapacityAvailable(mySym))
   {
      reply.action = 0;
      replyNote = "symbol_limit";
      if(canLogDenial)
      {
         PrintFormat(EmojiWarning() + " Handshake denied: slave symbol cap reached for %s. active_symbols=%d limit=%d",
                     mySym, CountActiveLinkedSymbols(), InpMaxConcurrentSymbols);
         lastDenyLog = TimeCurrent();
      }
   }
   else
   {
      ENUM_ORDER_TYPE slaveType;
      if(!TryGetSlaveOrderType(sig.type, slaveType))
      {
         reply.action = 0;
         replyNote = "invalid_master_side";
         if(canLogDenial)
         {
            PrintFormat(EmojiWarning() + " Handshake denied: invalid master side for ticket %I64u (type=%d).", sig.ticket, sig.type);
            lastDenyLog = TimeCurrent();
         }
      }
      else
      {
         double myLots = CalculateRobustLots(sig, mySym, state, slaveType, "estimated");
         if(myLots > 0.0)
         {
            reply.action = 1;
            replyNote = "approved";
            PrintFormat(EmojiShield() + " Hedge handshake approved: ticket=%I64u | estimated master %s -> slave %s | symbol=%s | lots=%.2f",
                        sig.ticket, SignalTypeToText(sig.type), OrderTypeToText(slaveType), mySym, myLots);
         }
         else
         {
            reply.action = 0;
            replyNote = "lot_calc_failed";
            if(canLogDenial)
            {
               PrintFormat(EmojiWarning() + " Handshake denied: symbol=%s | master=%s | slave=%s | calculated lots=%.2f | master lots=%.2f | free margin=%.2f",
                           mySym, SignalTypeToText(sig.type), OrderTypeToText(slaveType), myLots, sig.lots, AccountInfoDouble(ACCOUNT_MARGIN_FREE));
               lastDenyLog = TimeCurrent();
            }
         }
      }
   }

   if(sqliteProposal)
   {
      V3_InsertReplyRow(InpV3_SQLitePath, InpChannelName, requestId, reply.action, V3_BuildReplyPayload(replyNote));
      V3_UpdateProposalState(InpV3_SQLitePath, proposalRowId, (reply.action == 1) ? "APPROVED" : "DENIED");
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
//+------------------------------------------------------------------+
//| MAP MANAGER: Load/Save Hidden Links                              |
//+------------------------------------------------------------------+
void LoadMap()
{
   MapFileName = "HedgeMap_" + InpChannelName + ".bin";
   if(FileIsExist(MapFileName, FILE_COMMON)) {
      int h = FileOpen(MapFileName, FILE_READ|FILE_BIN|FILE_COMMON);
      if(h != INVALID_HANDLE) {
         FileReadArray(h, TradeMap);
         FileClose(h);
      }
   }
}

void SaveMap()
{
   int h = FileOpen(MapFileName, FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(h != INVALID_HANDLE) {
      FileWriteArray(h, TradeMap);
      FileClose(h);
   }
}

void AddLink(ulong slaveT, ulong masterT)
{
   ClearMasterFeedbackState(masterT);

   int s = ArraySize(TradeMap);
   ArrayResize(TradeMap, s+1);
   TradeMap[s].slaveTicket  = slaveT;
   TradeMap[s].masterTicket = masterT;
   SaveMap(); 
}

void RemoveLink(ulong slaveT)
{
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
      SaveMap();
   }
}

ulong GetLinkedMaster(ulong slaveT)
{
   for(int i=0; i<ArraySize(TradeMap); i++) {
      if(TradeMap[i].slaveTicket == slaveT) return TradeMap[i].masterTicket;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| ON TICK: Used strictly for Auto-Trade / Validator Mode           |
//+------------------------------------------------------------------+
void OnTick()
{
   // Auto-trade runs on timer to avoid tick dependency.
   return;
}

//+------------------------------------------------------------------+
//| Helper: Calculate max affordable lots to pass MQL5 Validation    |
//+------------------------------------------------------------------+
double GetSafeAndAffordableLots(double desiredLots, string symbol, int direction)
{
   double minVolume  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxVolume  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double volumeStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   
   ENUM_ORDER_TYPE type = (direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double price = (direction == 1) ? SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID);

   double calcLots = desiredLots;
   if(calcLots > maxVolume) calcLots = maxVolume;

   int loop_guard = 0; 
   while(calcLots >= minVolume && loop_guard < 1000)
   {
      loop_guard++;
      calcLots = MathRound(calcLots / volumeStep) * volumeStep;
      if(calcLots < minVolume) return 0.0;

      double marginRequired = 0.0;
      if(OrderCalcMargin(type, symbol, calcLots, price, marginRequired)) {
         if(marginRequired <= AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.95) {
            return calcLots; 
         }
      }
      calcLots -= volumeStep;
   }
   return 0.0; 
}

//+------------------------------------------------------------------+
//| Auto Trading: Pure Stop-and-Reverse Execution                    |
//+------------------------------------------------------------------+
void ExecuteTrade(int direction)
{
   // 1. Close opposites
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket)) {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpSlaveMagic) {
            long currentType = PositionGetInteger(POSITION_TYPE);
            if(direction == 1 && currentType == POSITION_TYPE_SELL) Trade.PositionClose(ticket);
            else if(direction == -1 && currentType == POSITION_TYPE_BUY) Trade.PositionClose(ticket);
         }
      }
   }

   // 2. Prevent duplicates
   bool hasPosition = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket)) {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpSlaveMagic) {
            long currentType = PositionGetInteger(POSITION_TYPE);
            if((direction == 1 && currentType == POSITION_TYPE_BUY) || (direction == -1 && currentType == POSITION_TYPE_SELL)) {
               hasPosition = true; 
               break;
            }
         }
      }
   }

   // 3. Open New Trade
   if(!hasPosition) {
      double safeLots = GetSafeAndAffordableLots(InpLotSize, _Symbol, direction);
      if(safeLots > 0.0) {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(direction == 1) Trade.Buy(safeLots, _Symbol, ask, 0, 0, "Validator Buy");
         if(direction == -1) Trade.Sell(safeLots, _Symbol, bid, 0, 0, "Validator Sell");
      }
   }
}

//+------------------------------------------------------------------+
//| Auto Trading: MA Signal Check                                    |
//+------------------------------------------------------------------+
void CheckTradeSignalsBase()
{
   if(g_FastMA_Handle == INVALID_HANDLE || g_SlowMA_Handle == INVALID_HANDLE) return;

   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == lastBarTime) return;

   double fastMA[2], slowMA[2];
   if(CopyBuffer(g_FastMA_Handle, 0, 1, 2, fastMA) < 2) return;
   if(CopyBuffer(g_SlowMA_Handle, 0, 1, 2, slowMA) < 2) return;

   bool isBuySignal  = (fastMA[0] <= slowMA[0] && fastMA[1] > slowMA[1]);
   bool isSellSignal = (fastMA[0] >= slowMA[0] && fastMA[1] < slowMA[1]);

   if(!isBuySignal && !isSellSignal) return;

   long currentSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(currentSpread > InpMaxSpreadPoints) return; 

   if(isBuySignal) {
       ExecuteTrade(1);
       lastBarTime = currentBarTime; 
   }
   else if(isSellSignal) {
       ExecuteTrade(-1);
       lastBarTime = currentBarTime; 
   }
}

//+------------------------------------------------------------------+
//| Calculate New York Time dynamically based on GMT and Server Time |
//+------------------------------------------------------------------+
datetime GetNewYorkTime()
{
   datetime serverTime = TimeCurrent();
   datetime gmtTime = TimeGMT();
   
   // Get server offset in seconds (for reference if needed)
   int serverOffset = (int)(serverTime - gmtTime);
   
   // Calculate NY Time: GMT - 5 hours (+ user shift for DST)
   int nyOffsetSecs = (-5 + InpNYManualShift) * 3600;
   
   return gmtTime + nyOffsetSecs;
}
//+------------------------------------------------------------------+


















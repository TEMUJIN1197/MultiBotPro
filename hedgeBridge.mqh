//+------------------------------------------------------------------+
//| Canonical hedge bridge include                                   |
//+------------------------------------------------------------------+
#ifndef __MBP_CANONICAL_HEDGEBRIDGE_MQH__
#define __MBP_CANONICAL_HEDGEBRIDGE_MQH__

//+------------------------------------------------------------------+
//|                                                  HedgeBridge.mqh |
//|           Robust Dragging (Anywhere) + Z-Order Fix               |
//+------------------------------------------------------------------+
#property strict

// --- FILE NAMES ---
string GetMasterFile(string channel) { return "HedgeMaster_" + channel + ".bin"; }
string GetSlaveFile(string channel)  { return "HedgeSlave_" + channel + ".bin"; }
string GetSignalFile(string channel) { return "HedgeSignal_" + channel + ".bin"; }
string GetFeedbackFile(string channel) { return "HedgeFeedback_" + channel + ".bin"; }
string GetProposalFile(string channel) { return "HedgeProp_" + channel + ".bin"; }
string GetReplyFile(string channel) { return "HedgeReply_" + channel + ".bin"; } 

string EmojiBrain() { ushort code[] = {0xD83E,0xDDE0,0}; return ShortArrayToString(code); }
string EmojiWarning() { ushort code[] = {0x26A0,0xFE0F,0}; return ShortArrayToString(code); }
string EmojiShield() { ushort code[] = {0xD83D,0xDEE1,0xFE0F,0}; return ShortArrayToString(code); }
string EmojiBroom() { ushort code[] = {0xD83E,0xDDF9,0}; return ShortArrayToString(code); }
string EmojiMouse() { ushort code[] = {0xD83D,0xDDB1,0xFE0F,0}; return ShortArrayToString(code); }
string EmojiReset() { ushort code[] = {0xD83D,0xDD04,0}; return ShortArrayToString(code); }
string EmojiCheck() { ushort code[] = {0x2705,0}; return ShortArrayToString(code); }
string EmojiPause() { ushort code[] = {0x23F8,0xFE0F,0}; return ShortArrayToString(code); }
string EmojiLock() { ushort code[] = {0xD83D,0xDD10,0}; return ShortArrayToString(code); }
string EmojiTest() { ushort code[] = {0xD83E,0xDDEA,0}; return ShortArrayToString(code); }
string EmojiCalc() { ushort code[] = {0xD83E,0xDDEE,0}; return ShortArrayToString(code); }
// --- 1. SHARED DATA STRUCTURES ---
struct HedgeSignal {
   ulong  ticket; 
   double lots; 
   int    type; 
   char   symbol[32];
   double sl_dist_points; 
   double tp_dist_points; 
   long   time_msc; 
   int    action;
   double risk_money; 
   char   comment[64]; 
};


// Handshake proposal payload (kept binary-compatible with HedgeSignal layout).
struct BridgeProposal {
   ulong  ticket;
   double lots;
   int    type;
   char   symbol[32];
   double sl_dist_points;
   double tp_dist_points;
   long   time_msc;
   int    action;
   double risk_money;
   char   comment[64];
};

struct BridgeReply {
   ulong  master_ticket;
   int    action;
};
struct HedgeFeedback {
   ulong master_ticket; 
   int   action;        
};

struct HedgeState
{
   double master_current_equity;
   double master_start_equity;
   double master_target_risk;
   double master_target_profit;
   double master_daily_limit;
   double master_daily_target;
   double master_daily_pnl;
   double master_pnl;
   double master_balance_pnl;
   double slave_pnl; 
   double slave_target_gain; 
   
   bool   is_daily_stopped;
   bool   is_total_stopped;
   bool   is_paused;
   
   ulong  last_heartbeat;
   ulong  reset_id;
};

bool V3_RuntimeEnabled(const bool enabled, const string sqlitePath)
{
   return (enabled && StringLen(sqlitePath) > 0);
}

string V3_GetDbFileName(string sqlitePath)
{
   if(StringLen(sqlitePath) == 0)
      return "MultiBotPro_v3.db";

   int lastSep = -1;
   for(int i = 0; i < StringLen(sqlitePath); i++)
   {
      string ch = StringSubstr(sqlitePath, i, 1);
      if(ch == "\\" || ch == "/")
         lastSep = i;
   }

   if(lastSep >= 0 && (lastSep + 1) < StringLen(sqlitePath))
      return StringSubstr(sqlitePath, lastSep + 1);

   return sqlitePath;
}

string V3_SqlEscape(string value)
{
   string out = value;
   StringReplace(out, "'", "''");
   return out;
}

string V3_JsonEscape(string value)
{
   string out = value;
   StringReplace(out, "\\", "\\\\");
   StringReplace(out, "\"", "\\\"");
   StringReplace(out, "\r", "\\r");
   StringReplace(out, "\n", "\\n");
   return out;
}

string V3_NowIso()
{
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   return StringFormat("%04d-%02d-%02dT%02d:%02d:%02dZ", dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec);
}

#define V3_SQLITE_RETRY_ATTEMPTS 10
#define V3_SQLITE_RETRY_SLEEP_MS 20
#define V3_SQLITE_LOCK_LOG_INTERVAL_SEC 180
#define V3_SQLITE_BACKOFF_MS 1000

datetime g_V3_LastSqliteLogTime = 0;
ulong    g_V3_SqliteBackoffUntilMs = 0;

bool V3_SqliteBackoffActive()
{
   if(g_V3_SqliteBackoffUntilMs == 0)
      return false;

   ulong nowMs = GetTickCount();
   if(nowMs >= g_V3_SqliteBackoffUntilMs)
   {
      g_V3_SqliteBackoffUntilMs = 0;
      return false;
   }

   return true;
}

void V3_RegisterSqliteFailure(const string stage)
{
   g_V3_SqliteBackoffUntilMs = GetTickCount() + (ulong)V3_SQLITE_BACKOFF_MS;

   datetime now = TimeCurrent();
   if((g_V3_LastSqliteLogTime == 0) || ((now - g_V3_LastSqliteLogTime) >= V3_SQLITE_LOCK_LOG_INTERVAL_SEC))
   {
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("⚠️ SQLite bridge backoff: ", stage, " is busy or locked. Retrying with fallback protection.");
      g_V3_LastSqliteLogTime = now;
   }
}

int V3_DatabaseOpenWithRetry(const string dbName, const int flags)
{
   if(V3_SqliteBackoffActive())
      return INVALID_HANDLE;

   for(int attempt = 0; attempt < V3_SQLITE_RETRY_ATTEMPTS; attempt++)
   {
      ResetLastError();
      int db = DatabaseOpen(dbName, flags);
      if(db != INVALID_HANDLE)
      {
         g_V3_SqliteBackoffUntilMs = 0;
         return db;
      }

      if(attempt + 1 < V3_SQLITE_RETRY_ATTEMPTS)
      {
         if(MBP_ShouldAllowBlockingTradeWait("bridge_sqlite"))
            Sleep(V3_SQLITE_RETRY_SLEEP_MS);
         else
            break;
      }
   }

   V3_RegisterSqliteFailure("DatabaseOpen");
   return INVALID_HANDLE;
}

bool V3_DatabaseExecuteWithRetry(const int db, const string query)
{
   if(V3_SqliteBackoffActive())
      return false;

   for(int attempt = 0; attempt < V3_SQLITE_RETRY_ATTEMPTS; attempt++)
   {
      ResetLastError();
      if(DatabaseExecute(db, query))
      {
         g_V3_SqliteBackoffUntilMs = 0;
         return true;
      }

      if(attempt + 1 < V3_SQLITE_RETRY_ATTEMPTS)
      {
         if(MBP_ShouldAllowBlockingTradeWait("bridge_sqlite"))
            Sleep(V3_SQLITE_RETRY_SLEEP_MS);
         else
            break;
      }
   }

   V3_RegisterSqliteFailure("DatabaseExecute");
   return false;
}

int V3_DatabasePrepareWithRetry(const int db, const string query)
{
   if(V3_SqliteBackoffActive())
      return INVALID_HANDLE;

   for(int attempt = 0; attempt < V3_SQLITE_RETRY_ATTEMPTS; attempt++)
   {
      ResetLastError();
      int stmt = DatabasePrepare(db, query);
      if(stmt != INVALID_HANDLE)
      {
         g_V3_SqliteBackoffUntilMs = 0;
         return stmt;
      }

      if(attempt + 1 < V3_SQLITE_RETRY_ATTEMPTS)
      {
         if(MBP_ShouldAllowBlockingTradeWait("bridge_sqlite"))
            Sleep(V3_SQLITE_RETRY_SLEEP_MS);
         else
            break;
      }
   }

   V3_RegisterSqliteFailure("DatabasePrepare");
   return INVALID_HANDLE;
}

string V3_ExtractJSONValue(string json, string key)
{
   string search_key = "\"" + key + "\":";
   int key_pos = StringFind(json, search_key);
   if(key_pos < 0)
      return "";

   int val_start = key_pos + StringLen(search_key);
   while(val_start < StringLen(json) && StringSubstr(json, val_start, 1) == " ")
      val_start++;

   string result = "";
   if(StringSubstr(json, val_start, 1) == "\"")
   {
      val_start++;
      int val_end = StringFind(json, "\"", val_start);
      if(val_end > val_start)
         result = StringSubstr(json, val_start, val_end - val_start);
   }
   else
   {
      int end_comma = StringFind(json, ",", val_start);
      int end_brace = StringFind(json, "}", val_start);
      int val_end = end_comma;
      if(val_end < 0 || (end_brace > 0 && end_brace < val_end))
         val_end = end_brace;
      if(val_end > val_start)
         result = StringSubstr(json, val_start, val_end - val_start);
   }

   StringTrimLeft(result);
   StringTrimRight(result);
   return result;
}

int V3_OpenRuntimeDatabase(const string sqlitePath, const bool createIfMissing = true)
{
   string dbName = V3_GetDbFileName(sqlitePath);
   int flags = DATABASE_OPEN_READWRITE | DATABASE_OPEN_COMMON;
   if(createIfMissing)
      flags |= DATABASE_OPEN_CREATE;

   int db = V3_DatabaseOpenWithRetry(dbName, flags);
   if(db == INVALID_HANDLE)
      return INVALID_HANDLE;

   if(!V3_DatabaseExecuteWithRetry(db, "PRAGMA busy_timeout = 5000"))
   {
      DatabaseClose(db);
      return INVALID_HANDLE;
   }

   return db;
}

bool V3_TableExists(const int db, const string tableName)
{
   string query = StringFormat("SELECT name FROM sqlite_master WHERE type='table' AND lower(name)=lower('%s') LIMIT 1",
                               V3_SqlEscape(tableName));
   int stmt = V3_DatabasePrepareWithRetry(db, query);
   bool exists = false;
   if(stmt != INVALID_HANDLE)
   {
      exists = DatabaseRead(stmt);
      DatabaseFinalize(stmt);
   }
   return exists;
}

bool V3_TableHasColumn(const int db, const string tableName, const string columnName)
{
   int stmt = V3_DatabasePrepareWithRetry(db, StringFormat("PRAGMA table_info(%s)", tableName));
   bool found = false;
   if(stmt != INVALID_HANDLE)
   {
      while(DatabaseRead(stmt))
      {
         string name = "";
         if(DatabaseColumnText(stmt, 1, name) && name == columnName)
         {
            found = true;
            break;
         }
      }
      DatabaseFinalize(stmt);
   }
   return found;
}

bool V3_MigrateLegacySignalsTable(const int db, bool &migratedLegacySignals)
{
   migratedLegacySignals = false;
   if(!V3_TableExists(db, "signals"))
      return true;

   if(V3_TableHasColumn(db, "signals", "channel") && V3_TableHasColumn(db, "signals", "processed"))
      return true;

   bool ok = true;
   if(V3_TableExists(db, "signals_legacy"))
      ok = ok && V3_DatabaseExecuteWithRetry(db, "DROP TABLE signals_legacy");

   ok = ok && V3_DatabaseExecuteWithRetry(db, "ALTER TABLE Signals RENAME TO signals_legacy");
   migratedLegacySignals = ok;
   return ok;
}

bool V3_EnsureRuntimeSchema(const string sqlitePath)
{
   int db = V3_OpenRuntimeDatabase(sqlitePath, true);
   if(db == INVALID_HANDLE)
      return false;

   bool ok = true;
   bool migratedLegacySignals = false;
   ok = ok && V3_DatabaseExecuteWithRetry(db, "PRAGMA journal_mode = WAL");
   ok = ok && V3_DatabaseExecuteWithRetry(db, "PRAGMA synchronous = NORMAL");
   ok = ok && V3_MigrateLegacySignalsTable(db, migratedLegacySignals);
   ok = ok && V3_DatabaseExecuteWithRetry(db, "CREATE TABLE IF NOT EXISTS signals (id INTEGER PRIMARY KEY AUTOINCREMENT, channel TEXT NOT NULL, ticket INTEGER, symbol TEXT, action INTEGER, type INTEGER NOT NULL DEFAULT 0, lots REAL, sl_dist_points REAL, tp_dist_points REAL, risk_money REAL, payload_json TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now')), processed INTEGER NOT NULL DEFAULT 0)");
   if(ok && !V3_TableHasColumn(db, "signals", "type"))
      ok = ok && V3_DatabaseExecuteWithRetry(db, "ALTER TABLE signals ADD COLUMN type INTEGER NOT NULL DEFAULT 0");
   ok = ok && V3_DatabaseExecuteWithRetry(db, "CREATE INDEX IF NOT EXISTS idx_signals_channel_processed ON signals(channel, processed, id)");
   if(ok && migratedLegacySignals && V3_TableExists(db, "signals_legacy"))
   {
      ok = ok && V3_DatabaseExecuteWithRetry(db, "INSERT INTO signals(channel, ticket, symbol, action, type, lots, sl_dist_points, tp_dist_points, risk_money, payload_json, created_at, processed) SELECT 'legacy', ticket, symbol, action, 0, lots, sl_dist_points, tp_dist_points, risk_money, '', datetime('now'), 1 FROM signals_legacy");
   }
   ok = ok && V3_DatabaseExecuteWithRetry(db, "CREATE TABLE IF NOT EXISTS proposals (id INTEGER PRIMARY KEY AUTOINCREMENT, channel TEXT NOT NULL, request_id TEXT NOT NULL, payload_json TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'PENDING', created_at TEXT NOT NULL DEFAULT (datetime('now')), updated_at TEXT)");
   ok = ok && V3_DatabaseExecuteWithRetry(db, "CREATE INDEX IF NOT EXISTS idx_proposals_channel_state ON proposals(channel, state, id)");
   ok = ok && V3_DatabaseExecuteWithRetry(db, "CREATE TABLE IF NOT EXISTS replies (id INTEGER PRIMARY KEY AUTOINCREMENT, channel TEXT NOT NULL, request_id TEXT NOT NULL, action INTEGER NOT NULL, payload_json TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now')))");
   ok = ok && V3_DatabaseExecuteWithRetry(db, "CREATE INDEX IF NOT EXISTS idx_replies_channel_request ON replies(channel, request_id, id)");
   ok = ok && V3_DatabaseExecuteWithRetry(db, "CREATE TABLE IF NOT EXISTS feedback (id INTEGER PRIMARY KEY AUTOINCREMENT, channel TEXT NOT NULL, master_ticket INTEGER, action INTEGER NOT NULL, note TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now')), consumed INTEGER NOT NULL DEFAULT 0)");
   ok = ok && V3_DatabaseExecuteWithRetry(db, "CREATE INDEX IF NOT EXISTS idx_feedback_channel_consumed ON feedback(channel, consumed, id)");
   ok = ok && V3_DatabaseExecuteWithRetry(db, "CREATE TABLE IF NOT EXISTS state_master (id INTEGER PRIMARY KEY AUTOINCREMENT, channel TEXT NOT NULL, payload_json TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT (datetime('now')))");
   ok = ok && V3_DatabaseExecuteWithRetry(db, "CREATE INDEX IF NOT EXISTS idx_state_master_channel ON state_master(channel, id)");
   ok = ok && V3_DatabaseExecuteWithRetry(db, "CREATE TABLE IF NOT EXISTS state_slave (id INTEGER PRIMARY KEY AUTOINCREMENT, channel TEXT NOT NULL, payload_json TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT (datetime('now')))");
   ok = ok && V3_DatabaseExecuteWithRetry(db, "CREATE INDEX IF NOT EXISTS idx_state_slave_channel ON state_slave(channel, id)");
   ok = ok && V3_DatabaseExecuteWithRetry(db, "CREATE TABLE IF NOT EXISTS events (id INTEGER PRIMARY KEY AUTOINCREMENT, channel TEXT NOT NULL, event_type TEXT NOT NULL, payload_json TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now')))");
   ok = ok && V3_DatabaseExecuteWithRetry(db, "CREATE INDEX IF NOT EXISTS idx_events_channel ON events(channel, id)");
   ok = ok && V3_DatabaseExecuteWithRetry(db, "CREATE TABLE IF NOT EXISTS debt_ledger (id INTEGER PRIMARY KEY AUTOINCREMENT, channel TEXT NOT NULL, symbol TEXT NOT NULL, event_type TEXT NOT NULL, delta_amount REAL NOT NULL, pruning_balance REAL NOT NULL, critical_balance REAL NOT NULL, metadata_json TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now')))");
   ok = ok && V3_DatabaseExecuteWithRetry(db, "CREATE INDEX IF NOT EXISTS idx_debt_ledger_channel ON debt_ledger(channel, id)");
   ok = ok && V3_DatabaseExecuteWithRetry(db, "CREATE TABLE IF NOT EXISTS shadow_params (id INTEGER PRIMARY KEY AUTOINCREMENT, symbol TEXT NOT NULL, payload_json TEXT NOT NULL, score REAL, updated_at TEXT NOT NULL)");
   ok = ok && V3_DatabaseExecuteWithRetry(db, "CREATE INDEX IF NOT EXISTS idx_shadow_params_symbol ON shadow_params(symbol, updated_at)");
   ok = ok && V3_DatabaseExecuteWithRetry(db, "CREATE TABLE IF NOT EXISTS worker_status (channel TEXT NOT NULL, symbol TEXT NOT NULL, chart_id TEXT NOT NULL, chart_id_hi INTEGER NOT NULL DEFAULT 0, chart_id_lo INTEGER NOT NULL DEFAULT 0, chart_symbol TEXT, symbols_csv TEXT, assignment_signature TEXT, state TEXT NOT NULL, linked_positions INTEGER NOT NULL DEFAULT 0, heartbeat INTEGER NOT NULL, updated_at TEXT NOT NULL, PRIMARY KEY(channel, symbol))");
   ok = ok && V3_DatabaseExecuteWithRetry(db, "CREATE INDEX IF NOT EXISTS idx_worker_status_channel_symbol ON worker_status(channel, symbol)");
   ok = ok && V3_DatabaseExecuteWithRetry(db, "CREATE INDEX IF NOT EXISTS idx_worker_status_channel_updated ON worker_status(channel, updated_at)");

   DatabaseClose(db);
   return ok;
}

bool V3_UpsertWorkerStatus(const string sqlitePath,
                           const string channel,
                           const string symbol,
                           const long chartId,
                           const string chartSymbol,
                           const string symbolsCsv,
                           const string assignmentSignature,
                           const string state,
                           const int linkedPositions,
                           const datetime heartbeat)
{
   if(channel == "" || symbol == "" || chartId <= 0 || heartbeat <= 0)
      return false;

   int db = V3_OpenRuntimeDatabase(sqlitePath, true);
   if(db == INVALID_HANDLE)
      return false;

   long chartHigh = chartId / 1000000;
   long chartLow = chartId - (chartHigh * 1000000);
   string query = StringFormat("INSERT OR REPLACE INTO worker_status(channel, symbol, chart_id, chart_id_hi, chart_id_lo, chart_symbol, symbols_csv, assignment_signature, state, linked_positions, heartbeat, updated_at) VALUES('%s','%s','%I64d',%I64d,%I64d,'%s','%s','%s','%s',%d,%d,'%s')",
                               V3_SqlEscape(channel),
                               V3_SqlEscape(symbol),
                               chartId,
                               chartHigh,
                               chartLow,
                               V3_SqlEscape(chartSymbol),
                               V3_SqlEscape(symbolsCsv),
                               V3_SqlEscape(assignmentSignature),
                               V3_SqlEscape(state),
                               MathMax(0, linkedPositions),
                               (int)heartbeat,
                               V3_NowIso());
   bool ok = V3_DatabaseExecuteWithRetry(db, query);
   DatabaseClose(db);
   return ok;
}

bool V3_ReadWorkerStatus(const string sqlitePath,
                         const string channel,
                         const string symbol,
                         datetime &outHeartbeat,
                         long &outChartId,
                         string &outSymbolsCsv,
                         string &outAssignmentSignature,
                         string &outState)
{
   outHeartbeat = 0;
   outChartId = 0;
   outSymbolsCsv = "";
   outAssignmentSignature = "";
   outState = "";

   if(channel == "" || symbol == "")
      return false;

   int db = V3_OpenRuntimeDatabase(sqlitePath, true);
   if(db == INVALID_HANDLE)
      return false;

   string query = StringFormat("SELECT heartbeat, chart_id, chart_id_hi, chart_id_lo, symbols_csv, assignment_signature, state FROM worker_status WHERE channel='%s' AND symbol='%s' LIMIT 1",
                               V3_SqlEscape(channel),
                               V3_SqlEscape(symbol));
   int stmt = V3_DatabasePrepareWithRetry(db, query);
   if(stmt == INVALID_HANDLE)
   {
      DatabaseClose(db);
      return false;
   }

   bool ok = false;
   if(DatabaseRead(stmt))
   {
      int heartbeatInt = 0;
      string chartIdText = "";
      DatabaseColumnInteger(stmt, 0, heartbeatInt);
      DatabaseColumnText(stmt, 1, chartIdText);
      DatabaseColumnText(stmt, 4, outSymbolsCsv);
      DatabaseColumnText(stmt, 5, outAssignmentSignature);
      DatabaseColumnText(stmt, 6, outState);

      outHeartbeat = (datetime)heartbeatInt;
      if(chartIdText != "")
         outChartId = (long)StringToInteger(chartIdText);

      ok = (outHeartbeat > 0 && outChartId > 0);
   }

   DatabaseFinalize(stmt);
   DatabaseClose(db);
   return ok;
}

bool V3_DeleteWorkerStatus(const string sqlitePath,
                           const string channel,
                           const string symbol,
                           const long chartId = 0)
{
   if(channel == "" || symbol == "")
      return false;

   int db = V3_OpenRuntimeDatabase(sqlitePath, true);
   if(db == INVALID_HANDLE)
      return false;

   string filter = StringFormat("channel='%s' AND symbol='%s'",
                                V3_SqlEscape(channel),
                                V3_SqlEscape(symbol));
   if(chartId > 0)
      filter += StringFormat(" AND chart_id='%I64d'", chartId);

   bool ok = V3_DatabaseExecuteWithRetry(db, "DELETE FROM worker_status WHERE " + filter);
   DatabaseClose(db);
   return ok;
}

string V3_BuildSignalPayload(HedgeSignal &sig)
{
   string symbol = V3_JsonEscape(CharArrayToString(sig.symbol));
   string comment = V3_JsonEscape(CharArrayToString(sig.comment));
   return StringFormat("{\"ticket\":%I64u,\"action\":%d,\"type\":%d,\"lots\":%.8f,\"symbol\":\"%s\",\"sl_dist_points\":%.5f,\"tp_dist_points\":%.5f,\"risk_money\":%.5f,\"time_msc\":%I64d,\"comment\":\"%s\"}",
                       sig.ticket,
                       sig.action,
                       sig.type,
                       sig.lots,
                       symbol,
                       sig.sl_dist_points,
                       sig.tp_dist_points,
                       sig.risk_money,
                       sig.time_msc,
                       comment);
}

bool V3_ParseSignalPayload(string payload, HedgeSignal &sig)
{
   string raw = V3_ExtractJSONValue(payload, "ticket");
   if(raw != "")
      sig.ticket = (ulong)StringToInteger(raw);

   raw = V3_ExtractJSONValue(payload, "action");
   if(raw != "")
      sig.action = (int)StringToInteger(raw);

   raw = V3_ExtractJSONValue(payload, "type");
   if(raw != "")
      sig.type = (int)StringToInteger(raw);

   raw = V3_ExtractJSONValue(payload, "lots");
   if(raw != "")
      sig.lots = StringToDouble(raw);

   raw = V3_ExtractJSONValue(payload, "sl_dist_points");
   if(raw != "")
      sig.sl_dist_points = StringToDouble(raw);

   raw = V3_ExtractJSONValue(payload, "tp_dist_points");
   if(raw != "")
      sig.tp_dist_points = StringToDouble(raw);

   raw = V3_ExtractJSONValue(payload, "risk_money");
   if(raw != "")
      sig.risk_money = StringToDouble(raw);

   raw = V3_ExtractJSONValue(payload, "symbol");
   if(raw != "")
   {
      ArrayInitialize(sig.symbol, 0);
      StringToCharArray(raw, sig.symbol, 0, ArraySize(sig.symbol));
   }

   string rawTime = V3_ExtractJSONValue(payload, "time_msc");
   if(rawTime != "")
      sig.time_msc = (long)StringToInteger(rawTime);

   string rawComment = V3_ExtractJSONValue(payload, "comment");
   if(rawComment != "")
   {
      ArrayInitialize(sig.comment, 0);
      StringToCharArray(rawComment, sig.comment, 0, ArraySize(sig.comment));
   }

   return true;
}

string V3_BuildProposalPayload(BridgeProposal &prop)
{
   string symbol = V3_JsonEscape(CharArrayToString(prop.symbol));
   string comment = V3_JsonEscape(CharArrayToString(prop.comment));
   return StringFormat("{\"ticket\":%I64u,\"action\":%d,\"type\":%d,\"lots\":%.8f,\"symbol\":\"%s\",\"sl_dist_points\":%.5f,\"tp_dist_points\":%.5f,\"risk_money\":%.5f,\"time_msc\":%I64d,\"comment\":\"%s\"}",
                       prop.ticket,
                       prop.action,
                       prop.type,
                       prop.lots,
                       symbol,
                       prop.sl_dist_points,
                       prop.tp_dist_points,
                       prop.risk_money,
                       prop.time_msc,
                       comment);
}

bool V3_ParseProposalPayload(string payload, BridgeProposal &prop)
{
   ZeroMemory(prop);
   string raw = V3_ExtractJSONValue(payload, "ticket");
   if(raw != "") prop.ticket = (ulong)StringToInteger(raw);
   raw = V3_ExtractJSONValue(payload, "action");
   if(raw != "") prop.action = (int)StringToInteger(raw);
   raw = V3_ExtractJSONValue(payload, "type");
   if(raw != "") prop.type = (int)StringToInteger(raw);
   raw = V3_ExtractJSONValue(payload, "lots");
   if(raw != "") prop.lots = StringToDouble(raw);
   raw = V3_ExtractJSONValue(payload, "sl_dist_points");
   if(raw != "") prop.sl_dist_points = StringToDouble(raw);
   raw = V3_ExtractJSONValue(payload, "tp_dist_points");
   if(raw != "") prop.tp_dist_points = StringToDouble(raw);
   raw = V3_ExtractJSONValue(payload, "risk_money");
   if(raw != "") prop.risk_money = StringToDouble(raw);
   raw = V3_ExtractJSONValue(payload, "time_msc");
   if(raw != "") prop.time_msc = (long)StringToInteger(raw);
   raw = V3_ExtractJSONValue(payload, "symbol");
   if(raw != "") StringToCharArray(raw, prop.symbol, 0, ArraySize(prop.symbol));
   raw = V3_ExtractJSONValue(payload, "comment");
   if(raw != "") StringToCharArray(raw, prop.comment, 0, ArraySize(prop.comment));
   return true;
}

string V3_BuildReplyPayload(const string note)
{
   return StringFormat("{\"note\":\"%s\"}", V3_JsonEscape(note));
}

string V3_BuildStatePayload(HedgeState &state)
{
   return StringFormat("{\"master_current_equity\":%.5f,\"master_start_equity\":%.5f,\"master_target_risk\":%.5f,\"master_target_profit\":%.5f,\"master_daily_limit\":%.5f,\"master_daily_target\":%.5f,\"master_daily_pnl\":%.5f,\"master_pnl\":%.5f,\"master_balance_pnl\":%.5f,\"slave_pnl\":%.5f,\"slave_target_gain\":%.5f,\"is_daily_stopped\":%d,\"is_total_stopped\":%d,\"is_paused\":%d,\"last_heartbeat\":%I64u,\"reset_id\":%I64u}",
                       state.master_current_equity,
                       state.master_start_equity,
                       state.master_target_risk,
                       state.master_target_profit,
                       state.master_daily_limit,
                       state.master_daily_target,
                       state.master_daily_pnl,
                       state.master_pnl,
                       state.master_balance_pnl,
                       state.slave_pnl,
                       state.slave_target_gain,
                       state.is_daily_stopped ? 1 : 0,
                       state.is_total_stopped ? 1 : 0,
                       state.is_paused ? 1 : 0,
                       state.last_heartbeat,
                       state.reset_id);
}

bool V3_ParseStatePayload(string payload, HedgeState &state)
{
   ZeroMemory(state);
   string raw = V3_ExtractJSONValue(payload, "master_current_equity");
   if(raw != "") state.master_current_equity = StringToDouble(raw);
   raw = V3_ExtractJSONValue(payload, "master_start_equity");
   if(raw != "") state.master_start_equity = StringToDouble(raw);
   raw = V3_ExtractJSONValue(payload, "master_target_risk");
   if(raw != "") state.master_target_risk = StringToDouble(raw);
   raw = V3_ExtractJSONValue(payload, "master_target_profit");
   if(raw != "") state.master_target_profit = StringToDouble(raw);
   raw = V3_ExtractJSONValue(payload, "master_daily_limit");
   if(raw != "") state.master_daily_limit = StringToDouble(raw);
   raw = V3_ExtractJSONValue(payload, "master_daily_target");
   if(raw != "") state.master_daily_target = StringToDouble(raw);
   raw = V3_ExtractJSONValue(payload, "master_daily_pnl");
   if(raw != "") state.master_daily_pnl = StringToDouble(raw);
   raw = V3_ExtractJSONValue(payload, "master_pnl");
   if(raw != "") state.master_pnl = StringToDouble(raw);
   raw = V3_ExtractJSONValue(payload, "master_balance_pnl");
   if(raw != "") state.master_balance_pnl = StringToDouble(raw);
   raw = V3_ExtractJSONValue(payload, "slave_pnl");
   if(raw != "") state.slave_pnl = StringToDouble(raw);
   raw = V3_ExtractJSONValue(payload, "slave_target_gain");
   if(raw != "") state.slave_target_gain = StringToDouble(raw);
   raw = V3_ExtractJSONValue(payload, "is_daily_stopped");
   if(raw != "") state.is_daily_stopped = (StringToInteger(raw) != 0);
   raw = V3_ExtractJSONValue(payload, "is_total_stopped");
   if(raw != "") state.is_total_stopped = (StringToInteger(raw) != 0);
   raw = V3_ExtractJSONValue(payload, "is_paused");
   if(raw != "") state.is_paused = (StringToInteger(raw) != 0);
   raw = V3_ExtractJSONValue(payload, "last_heartbeat");
   if(raw != "") state.last_heartbeat = (ulong)StringToInteger(raw);
   raw = V3_ExtractJSONValue(payload, "reset_id");
   if(raw != "") state.reset_id = (ulong)StringToInteger(raw);
   return true;
}

bool V3_InsertEventRow(const string sqlitePath, const string channel, const string eventType, string payloadJson)
{
   int db = V3_OpenRuntimeDatabase(sqlitePath, true);
   if(db == INVALID_HANDLE)
      return false;

   string query = StringFormat("INSERT INTO events(channel, event_type, payload_json, created_at) VALUES('%s','%s','%s','%s')",
                               V3_SqlEscape(channel),
                               V3_SqlEscape(eventType),
                               V3_SqlEscape(payloadJson),
                               V3_NowIso());
   bool ok = V3_DatabaseExecuteWithRetry(db, query);
   DatabaseClose(db);
   return ok;
}

bool V3_WriteStateRow(const string sqlitePath, const string tableName, const string channel, string payloadJson)
{
   int db = V3_OpenRuntimeDatabase(sqlitePath, true);
   if(db == INVALID_HANDLE)
      return false;

   bool ok = V3_DatabaseExecuteWithRetry(db,
                             StringFormat("INSERT INTO %s(channel, payload_json, created_at) VALUES('%s','%s','%s')",
                                          tableName,
                                          V3_SqlEscape(channel),
                                          V3_SqlEscape(payloadJson),
                                          V3_NowIso()));

   DatabaseClose(db);
   return ok;
}

bool V3_WriteMasterStateRow(const string sqlitePath, const string channel, HedgeState &state)
{
   string payload = V3_BuildStatePayload(state);
   return V3_WriteStateRow(sqlitePath, "state_master", channel, payload);
}

bool V3_WriteSlaveStateRow(const string sqlitePath, const string channel, HedgeState &state)
{
   string payload = V3_BuildStatePayload(state);
   return V3_WriteStateRow(sqlitePath, "state_slave", channel, payload);
}

bool V3_ReadLatestStatePayload(const string sqlitePath, const string tableName, const string channel, string &payloadJson)
{
   payloadJson = "";
   int db = V3_OpenRuntimeDatabase(sqlitePath, true);
   if(db == INVALID_HANDLE)
      return false;

   string query = StringFormat("SELECT payload_json FROM %s WHERE channel='%s' ORDER BY id DESC LIMIT 1", tableName, V3_SqlEscape(channel));
   int stmt = V3_DatabasePrepareWithRetry(db, query);
   bool found = false;
   if(stmt != INVALID_HANDLE)
   {
      if(DatabaseRead(stmt))
      {
         string payload = "";
         if(DatabaseColumnText(stmt, 0, payload))
         {
            payloadJson = payload;
            found = true;
         }
      }
      DatabaseFinalize(stmt);
   }

   DatabaseClose(db);
   return found;
}

bool V3_ReadLatestMasterState(const string sqlitePath, const string channel, HedgeState &state)
{
   string payload = "";
   if(!V3_ReadLatestStatePayload(sqlitePath, "state_master", channel, payload))
      return false;
   return V3_ParseStatePayload(payload, state);
}

bool V3_InsertSignalRow(const string sqlitePath, const string channel, HedgeSignal &sig)
{
   int db = V3_OpenRuntimeDatabase(sqlitePath, true);
   if(db == INVALID_HANDLE)
      return false;

   string symbol = CharArrayToString(sig.symbol);
   string payload = V3_BuildSignalPayload(sig);
   string query = StringFormat("INSERT INTO signals(channel, ticket, symbol, action, type, lots, sl_dist_points, tp_dist_points, risk_money, payload_json, created_at, processed) VALUES('%s', %I64u, '%s', %d, %d, %.8f, %.5f, %.5f, %.5f, '%s', '%s', 0)",
                               V3_SqlEscape(channel),
                               sig.ticket,
                               V3_SqlEscape(symbol),
                               sig.action,
                               sig.type,
                               sig.lots,
                               sig.sl_dist_points,
                               sig.tp_dist_points,
                               sig.risk_money,
                               V3_SqlEscape(payload),
                               V3_NowIso());
   bool ok = V3_DatabaseExecuteWithRetry(db, query);
   DatabaseClose(db);
   return ok;
}

bool V3_SelectPendingSignalRow(const string sqlitePath, const string channel, long &rowId, HedgeSignal &sig)
{
   rowId = -1;
   ZeroMemory(sig);

   int db = V3_OpenRuntimeDatabase(sqlitePath, true);
   if(db == INVALID_HANDLE)
      return false;

   string query = StringFormat("SELECT id, CAST(ticket AS TEXT), symbol, action, type, lots, sl_dist_points, tp_dist_points, risk_money, payload_json FROM signals WHERE channel='%s' AND processed=0 ORDER BY id ASC LIMIT 1", V3_SqlEscape(channel));
   int stmt = V3_DatabasePrepareWithRetry(db, query);
   bool found = false;

   if(stmt != INVALID_HANDLE)
   {
      if(DatabaseRead(stmt))
      {
         int rowInt = 0;
         string ticketText = "";
         string symbol = "";
         int actionInt = 0;
         int typeInt = 0;
         double lots = 0.0;
         double slDist = 0.0;
         double tpDist = 0.0;
         double riskMoney = 0.0;
         string payload = "";

         DatabaseColumnInteger(stmt, 0, rowInt);
         DatabaseColumnText(stmt, 1, ticketText);
         DatabaseColumnText(stmt, 2, symbol);
         DatabaseColumnInteger(stmt, 3, actionInt);
         DatabaseColumnInteger(stmt, 4, typeInt);
         DatabaseColumnDouble(stmt, 5, lots);
         DatabaseColumnDouble(stmt, 6, slDist);
         DatabaseColumnDouble(stmt, 7, tpDist);
         DatabaseColumnDouble(stmt, 8, riskMoney);
         DatabaseColumnText(stmt, 9, payload);

         rowId = rowInt;
         sig.ticket = (ulong)StringToInteger(ticketText);
         sig.action = actionInt;
         sig.type = typeInt;
         sig.lots = lots;
         sig.sl_dist_points = slDist;
         sig.tp_dist_points = tpDist;
         sig.risk_money = riskMoney;
         StringToCharArray(symbol, sig.symbol, 0, ArraySize(sig.symbol));
         V3_ParseSignalPayload(payload, sig);
         found = true;
      }
      DatabaseFinalize(stmt);
   }

   DatabaseClose(db);
   return found;
}

bool V3_MarkSignalProcessed(const string sqlitePath, const long rowId)
{
   int db = V3_OpenRuntimeDatabase(sqlitePath, true);
   if(db == INVALID_HANDLE)
      return false;
   bool ok = V3_DatabaseExecuteWithRetry(db, StringFormat("UPDATE signals SET processed=1 WHERE id=%I64d", rowId));
   DatabaseClose(db);
   return ok;
}

bool V3_InsertProposalRow(const string sqlitePath, const string channel, const string requestId, BridgeProposal &prop)
{
   int db = V3_OpenRuntimeDatabase(sqlitePath, true);
   if(db == INVALID_HANDLE)
      return false;

   string payload = V3_BuildProposalPayload(prop);
   string query = StringFormat("INSERT INTO proposals(channel, request_id, payload_json, state, created_at, updated_at) VALUES('%s','%s','%s','PENDING','%s','%s')",
                               V3_SqlEscape(channel),
                               V3_SqlEscape(requestId),
                               V3_SqlEscape(payload),
                               V3_NowIso(),
                               V3_NowIso());
   bool ok = V3_DatabaseExecuteWithRetry(db, query);
   DatabaseClose(db);
   return ok;
}

bool V3_SelectPendingProposalRow(const string sqlitePath, const string channel, long &rowId, string &requestId, BridgeProposal &prop)
{
   rowId = -1;
   requestId = "";
   ZeroMemory(prop);

   int db = V3_OpenRuntimeDatabase(sqlitePath, true);
   if(db == INVALID_HANDLE)
      return false;

   string query = StringFormat("SELECT id, request_id, payload_json FROM proposals WHERE channel='%s' AND state='PENDING' ORDER BY id ASC LIMIT 1", V3_SqlEscape(channel));
   int stmt = V3_DatabasePrepareWithRetry(db, query);
   bool found = false;

   if(stmt != INVALID_HANDLE)
   {
      if(DatabaseRead(stmt))
      {
         int rowInt = 0;
         string payload = "";
         DatabaseColumnInteger(stmt, 0, rowInt);
         DatabaseColumnText(stmt, 1, requestId);
         DatabaseColumnText(stmt, 2, payload);
         rowId = rowInt;
         V3_ParseProposalPayload(payload, prop);
         found = true;
      }
      DatabaseFinalize(stmt);
   }

   DatabaseClose(db);
   return found;
}

bool V3_UpdateProposalState(const string sqlitePath, const long rowId, const string state)
{
   int db = V3_OpenRuntimeDatabase(sqlitePath, true);
   if(db == INVALID_HANDLE)
      return false;
   bool ok = V3_DatabaseExecuteWithRetry(db, StringFormat("UPDATE proposals SET state='%s', updated_at='%s' WHERE id=%I64d", V3_SqlEscape(state), V3_NowIso(), rowId));
   DatabaseClose(db);
   return ok;
}

bool V3_InsertReplyRow(const string sqlitePath, const string channel, const string requestId, const int action, string payloadJson)
{
   int db = V3_OpenRuntimeDatabase(sqlitePath, true);
   if(db == INVALID_HANDLE)
      return false;
   string query = StringFormat("INSERT INTO replies(channel, request_id, action, payload_json, created_at) VALUES('%s','%s',%d,'%s','%s')",
                               V3_SqlEscape(channel),
                               V3_SqlEscape(requestId),
                               action,
                               V3_SqlEscape(payloadJson),
                               V3_NowIso());
   bool ok = V3_DatabaseExecuteWithRetry(db, query);
   DatabaseClose(db);
   return ok;
}

bool V3_SelectReplyRow(const string sqlitePath, const string channel, const string requestId, long &rowId, int &action, string &payloadJson)
{
   rowId = -1;
   action = -1;
   payloadJson = "";

   int db = V3_OpenRuntimeDatabase(sqlitePath, true);
   if(db == INVALID_HANDLE)
      return false;

   string query = StringFormat("SELECT id, action, payload_json FROM replies WHERE channel='%s' AND request_id='%s' ORDER BY id ASC LIMIT 1", V3_SqlEscape(channel), V3_SqlEscape(requestId));
   int stmt = V3_DatabasePrepareWithRetry(db, query);
   bool found = false;
   if(stmt != INVALID_HANDLE)
   {
      if(DatabaseRead(stmt))
      {
         int rowInt = 0;
         int actionInt = -1;
         DatabaseColumnInteger(stmt, 0, rowInt);
         DatabaseColumnInteger(stmt, 1, actionInt);
         DatabaseColumnText(stmt, 2, payloadJson);
         rowId = rowInt;
         action = actionInt;
         found = true;
      }
      DatabaseFinalize(stmt);
   }
   DatabaseClose(db);
   return found;
}

bool V3_DeleteReplyRow(const string sqlitePath, const long rowId)
{
   int db = V3_OpenRuntimeDatabase(sqlitePath, true);
   if(db == INVALID_HANDLE)
      return false;
   bool ok = V3_DatabaseExecuteWithRetry(db, StringFormat("DELETE FROM replies WHERE id=%I64d", rowId));
   DatabaseClose(db);
   return ok;
}

bool V3_InsertFeedbackRow(const string sqlitePath, const string channel, const ulong masterTicket, const int action, const string note)
{
   int db = V3_OpenRuntimeDatabase(sqlitePath, true);
   if(db == INVALID_HANDLE)
      return false;
   string query = StringFormat("INSERT INTO feedback(channel, master_ticket, action, note, created_at, consumed) VALUES('%s', %I64u, %d, '%s', '%s', 0)",
                               V3_SqlEscape(channel),
                               masterTicket,
                               action,
                               V3_SqlEscape(note),
                               V3_NowIso());
   bool ok = V3_DatabaseExecuteWithRetry(db, query);
   DatabaseClose(db);
   return ok;
}

bool V3_SelectPendingFeedbackRow(const string sqlitePath, const string channel, long &rowId, HedgeFeedback &feedback, string &note)
{
   rowId = -1;
   ZeroMemory(feedback);
   note = "";

   int db = V3_OpenRuntimeDatabase(sqlitePath, true);
   if(db == INVALID_HANDLE)
      return false;

   string query = StringFormat("SELECT id, CAST(master_ticket AS TEXT), action, note FROM feedback WHERE channel='%s' AND consumed=0 ORDER BY id ASC LIMIT 1", V3_SqlEscape(channel));
   int stmt = V3_DatabasePrepareWithRetry(db, query);
   bool found = false;
   if(stmt != INVALID_HANDLE)
   {
      if(DatabaseRead(stmt))
      {
         int rowInt = 0;
         string ticketText = "";
         int actionInt = 0;
         DatabaseColumnInteger(stmt, 0, rowInt);
         DatabaseColumnText(stmt, 1, ticketText);
         DatabaseColumnInteger(stmt, 2, actionInt);
         DatabaseColumnText(stmt, 3, note);
         rowId = rowInt;
         feedback.master_ticket = (ulong)StringToInteger(ticketText);
         feedback.action = actionInt;
         found = true;
      }
      DatabaseFinalize(stmt);
   }
   DatabaseClose(db);
   return found;
}

bool V3_MarkFeedbackConsumed(const string sqlitePath, const long rowId)
{
   int db = V3_OpenRuntimeDatabase(sqlitePath, true);
   if(db == INVALID_HANDLE)
      return false;
   bool ok = V3_DatabaseExecuteWithRetry(db, StringFormat("UPDATE feedback SET consumed=1 WHERE id=%I64d", rowId));
   DatabaseClose(db);
   return ok;
}

bool V3_InsertDebtLedgerRow(const string sqlitePath,
                            const string channel,
                            const string symbol,
                            const string eventType,
                            const double deltaAmount,
                            const double pruningBal,
                            const double criticalBal,
                            const string metadataJson)
{
   int db = V3_OpenRuntimeDatabase(sqlitePath, true);
   if(db == INVALID_HANDLE)
      return false;

   string query = StringFormat("INSERT INTO debt_ledger(channel, symbol, event_type, delta_amount, pruning_balance, critical_balance, metadata_json, created_at) VALUES('%s','%s','%s',%.5f,%.5f,%.5f,'%s','%s')",
                               V3_SqlEscape(channel),
                               V3_SqlEscape(symbol),
                               V3_SqlEscape(eventType),
                               deltaAmount,
                               pruningBal,
                               criticalBal,
                               V3_SqlEscape(metadataJson),
                               V3_NowIso());
   bool ok = V3_DatabaseExecuteWithRetry(db, query);
   DatabaseClose(db);
   return ok;
}


//+------------------------------------------------------------------+
//| 2. PANEL CLASS (Fixed: High Contrast, Neatness & Dynamic Scale)  |
//+------------------------------------------------------------------+
class CHedgePanel
{
private:
   string   m_prefix;
   bool     m_is_master;
   bool     m_reset_req;
   
   // Position State
   int      m_x, m_y;
   bool     m_minimized;
   int      m_height;
   int      m_width;
   
   // Dynamic Scaling
   double   m_scale;
   int      S(int value) { return (int)MathRound(value * m_scale); } // Scale Helper
   
   // Dragging State
   bool     m_dragging;
   int      m_drag_off_x;
   int      m_drag_off_y;
   
   // Theme Colors
   color    c_bg_main, c_bg_card, c_accent, c_text_main, c_text_dim;
   color    c_bar_bg, c_bar_master, c_bar_slave, c_bar_sync_good, c_bar_sync_bad;
   string   m_status_text;

public:
   CHedgePanel() { 
      m_reset_req = false;
      m_dragging = false; 
      m_minimized = false;
      m_scale = 1.0; // Default Scale
      m_x = 20; m_y = 20;
      m_width = 300;
      m_status_text = "";
   }
   
   ~CHedgePanel() { Destroy(); }

   //+------------------------------------------------------------------+
   //| 1. INITIALIZATION                                                |
   //+------------------------------------------------------------------+
   
   int HeaderHeight() { return S(30); }
   int HeaderBitmapX() { return S(5); }
   int HeaderBitmapY() { return S(4); }
   int PanelMinWidth() { return S(300); }
   int PanelInnerPadding() { return S(10); }
   int PanelInnerWidth() { return MathMax(S(160), m_width - (PanelInnerPadding() * 2)); }
   int HeaderBitmapSize()
   {
      int fit = HeaderHeight() - (HeaderBitmapY() * 2);
      int minSize = S(14);
      if(fit < minSize)
         fit = minSize;
      return fit;
   }
   string HeaderBitmapResource() { return "::Experts\\MultiBotPro\\romeo.bmp"; }
   int HeaderTitleX()  { return HeaderBitmapX() + HeaderBitmapSize() + S(10); }
   int HeaderTitleY()  { return S(8); }
   int HeaderMinBtnX() { return m_width - S(30); }
   int HeaderScaleIncX() { return HeaderMinBtnX() - S(25); }
   int HeaderScaleDecX() { return HeaderScaleIncX() - S(25); }

   int EstimateTextWidth(const string text, const int fontSize, const bool mono = false)
   {
      double factor = mono ? 0.64 : 0.58;
      return (int)MathCeil(StringLen(text) * fontSize * factor);
   }

   void CreateBitmap(string n, int dx, int dy, string resName, int w = 0, int h = 0) {
      string obj = m_prefix+n;
      if(ObjectFind(0,obj)<0) ObjectCreate(0,obj,OBJ_BITMAP_LABEL,0,0,0);
      ObjectSetString(0,obj,OBJPROP_BMPFILE,0,resName);
      ObjectSetString(0,obj,OBJPROP_BMPFILE,1,resName);
      ObjectSetInteger(0,obj,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,obj,OBJPROP_ZORDER,25);
      ObjectSetInteger(0,obj,OBJPROP_HIDDEN,false);
      ObjectSetInteger(0,obj,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,obj,OBJPROP_BACK,false);
      if(w > 0) ObjectSetInteger(0,obj,OBJPROP_XSIZE,w);
      if(h > 0) ObjectSetInteger(0,obj,OBJPROP_YSIZE,h);
      SetGeom(n, m_x+dx, m_y+dy);
   }
bool CreatePanel(string name, bool isMaster)
   {
      m_prefix    = name + "_";
      m_is_master = isMaster;
      m_height    = isMaster ? 340 : 320;
      m_width     = PanelMinWidth();
      
      // Define Theme (Darker, Professional Look)
      if(isMaster) {
         c_bg_main   = C'35,25,27';    // Deep Red-Grey
         c_bg_card   = C'50,35,37';
         c_accent    = C'200,50,50';   // Red Accent
      } else {
         c_bg_main   = C'20,30,30';    // Deep Green-Grey
         c_bg_card   = C'30,45,45';
         c_accent    = C'40,160,90';   // Green Accent
      }
      
      c_text_main  = clrWhite;
      c_text_dim   = C'160,160,160';
      
      // Progress Bar Palette
      c_bar_bg     = C'15,15,15';      // Very Dark Slot Background
      c_bar_master = C'180,60,60';     // Dark Red
      c_bar_slave  = C'60,160,80';     // Dark Green
      c_bar_sync_good = C'60,100,180'; // Dark Royal Blue
      c_bar_sync_bad  = C'180,60,60';  // Dark Red (Warning)

      CreateObjects();
      MovePanel(m_x, m_y);
      
      ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
      return true;
   }

   //+------------------------------------------------------------------+
   //| 2. CREATE OBJECTS (Scaled)                                       |
   //+------------------------------------------------------------------+
   void CreateObjects()
   {
      // A. Backgrounds
      CreateRect("BG",     m_width, S(m_height), c_bg_main, c_bg_main);
      CreateRect("Header", m_width, HeaderHeight(), c_accent, c_accent);

      // B. Static Text & Buttons
      int headerBitmapSize = HeaderBitmapSize();
      CreateBitmap("Logo", HeaderBitmapX(), HeaderBitmapY(), HeaderBitmapResource(), headerBitmapSize, headerBitmapSize);
      CreateLabel("Title",  m_is_master?"MASTER NODE":"SLAVE NODE", S(10), c_text_main, "Trebuchet MS", true);
      
      // Dynamic Scaling Buttons
      CreateBtn("ScaleDec", "-", S(20), S(20), c_bg_card);
      CreateBtn("ScaleInc", "+", S(20), S(20), c_bg_card);
      CreateBtn("MinBtn",   "_", S(25), S(25), c_accent);
      
      CreateLabel("Status", "Initializing...", S(8), c_text_dim, "Calibri");

      // C. Cards
      CreateRect("CardM", PanelInnerWidth(), S(60), c_bg_card, c_bg_card);
      CreateLabel("TitM", "     MASTER RISK (PnL)", S(8), c_text_dim, "Calibri");
      CreateLabel("ValM", "--", S(12), c_text_main, "Consolas");
      
      CreateRect("CardS", PanelInnerWidth(), S(60), c_bg_card, c_bg_card);
      CreateLabel("TitS", "SLAVE GAIN (PnL)", S(8), c_text_dim, "Calibri");
      CreateLabel("ValS", "--", S(12), c_text_main, "Consolas");
      
      // D. Progress Bars
      int barH = S(14);
      
      // 1. Master DD
      CreateRect("P1_Bg",  PanelInnerWidth(), barH, c_bar_bg, (color)-1);
      CreateRect("P1_Fil", S(1),   barH, c_bar_master, (color)-1); 
      CreateLabel("P1_Txt", "Master DD: 0%", S(8), clrWhite, "Calibri Bold");

      // 2. Slave Target
      CreateRect("P2_Bg",  PanelInnerWidth(), barH, c_bar_bg, (color)-1);
      CreateRect("P2_Fil", S(1),   barH, c_bar_slave, (color)-1); 
      CreateLabel("P2_Txt", "Slave Tgt: 0%", S(8), clrWhite, "Calibri Bold");

      // 3. Agreement
      CreateRect("P3_Bg",  PanelInnerWidth(), barH, c_bar_bg, (color)-1);
      CreateRect("P3_Fil", S(1),   barH, c_bar_sync_good, (color)-1); 
      CreateLabel("P3_Txt", "Sync Health: 0%", S(8), clrWhite, "Calibri Bold");

      // E. Reset Button
      if(!m_is_master) {
         CreateBtn("RstBtn", "RESET COUNTERS", PanelInnerWidth(), S(30), C'180,50,50');
      }
      
      RefreshAdaptiveWidth();
      ChartRedraw();
   }

   //+------------------------------------------------------------------+
   //| 3. MOVE PANEL (Scaled)                                           |
   //+------------------------------------------------------------------+
   void MovePanel(int x, int y)
   {
      m_x = x;
      m_y = y;

      if(m_minimized) {
         UpdateObj("BG", x, y, m_width, HeaderHeight());
         UpdateObj("Header", x, y, m_width, HeaderHeight());
         int headerBitmapSize = HeaderBitmapSize();
         UpdateObj("Logo", x+HeaderBitmapX(), y+HeaderBitmapY(), headerBitmapSize, headerBitmapSize);
         UpdateObj("Title", x+HeaderTitleX(), y+HeaderTitleY());
         UpdateObj("ScaleDec", x+HeaderScaleDecX(), y+S(5));
         UpdateObj("ScaleInc", x+HeaderScaleIncX(), y+S(5));
         UpdateObj("MinBtn", x+HeaderMinBtnX(), y+S(2));
         SetHidden(true);
      } 
      else {
         UpdateObj("BG", x, y, m_width, S(m_height));
         UpdateObj("Header", x, y, m_width, HeaderHeight());
         int headerBitmapSize = HeaderBitmapSize();
         UpdateObj("Logo", x+HeaderBitmapX(), y+HeaderBitmapY(), headerBitmapSize, headerBitmapSize);
         UpdateObj("Title", x+HeaderTitleX(), y+HeaderTitleY());
         UpdateObj("ScaleDec", x+HeaderScaleDecX(), y+S(5));
         UpdateObj("ScaleInc", x+HeaderScaleIncX(), y+S(5));
         UpdateObj("MinBtn", x+HeaderMinBtnX(), y+S(2));
         SetHidden(false);

         int innerPadding = PanelInnerPadding();
         int innerWidth = PanelInnerWidth();
         UpdateObj("Status", x+innerPadding, y+S(40));
         
         UpdateObj("CardM", x+innerPadding, y+S(60), innerWidth, S(60));
         UpdateObj("TitM",  x+innerPadding+S(10), y+S(65));
         UpdateObj("ValM",  x+innerPadding+S(10), y+S(80));
         
         UpdateObj("CardS", x+innerPadding, y+S(130), innerWidth, S(60));
         UpdateObj("TitS",  x+innerPadding+S(10), y+S(135));
         UpdateObj("ValS",  x+innerPadding+S(10), y+S(150));

         // Progress Bars Layout
         int yBar = y + S(205);
         int gap  = S(24);

         UpdateBar("P1", x+innerPadding, yBar);
         UpdateBar("P2", x+innerPadding, yBar + gap);
         UpdateBar("P3", x+innerPadding, yBar + gap*2);
         
         if(!m_is_master) UpdateObj("RstBtn", x+innerPadding, yBar + gap*3, innerWidth, S(30));
      }
      ChartRedraw();
   }

   void UpdateBar(string p, int x, int y) {
      UpdateObj(p+"_Bg",  x, y);
      UpdateObj(p+"_Fil", x, y);
      UpdateObj(p+"_Txt", x+S(5), y);
   }

   //+------------------------------------------------------------------+
   //| 4. UPDATE STATS                                                  |
   //+------------------------------------------------------------------+
   void UpdateStats(HedgeState &st)
   {
      if(m_minimized) return;

      // PnL Values
      string m_txt = "Tot: $" + DoubleToString(st.master_pnl, 2) + "  Day: $" + DoubleToString(st.master_daily_pnl, 2);
      color m_color = clrWhite;
      if(st.is_daily_stopped)      m_color = C'255,50,50';
      else if(st.is_total_stopped) m_color = C'255,140,0';
      else if(st.master_pnl < 0)   m_color = C'255,100,100';
      else if(st.master_pnl > 0)   m_color = C'100,255,100';

      ObjectSetString(0, m_prefix+"ValM", OBJPROP_TEXT, m_txt);
      ObjectSetInteger(0, m_prefix+"ValM", OBJPROP_COLOR, m_color);

      // Title Details
      string m_title = "MASTER (Risk:" + IntegerToString((int)st.master_target_risk) + 
                       " | DL:"        + IntegerToString((int)st.master_daily_limit) + 
                       " | DT:"        + IntegerToString((int)st.master_daily_target) + ")";
      ObjectSetString(0, m_prefix+"TitM", OBJPROP_TEXT, m_title);
      
      // Slave Stats
      if(st.slave_target_gain > 0) {
         string s_prefix = (st.slave_pnl >= 0) ? "+$" : "-$";
         string s_txt = s_prefix + DoubleToString(MathAbs(st.slave_pnl), 2) + " / $" + IntegerToString((int)st.slave_target_gain);
         ObjectSetString(0, m_prefix+"ValS", OBJPROP_TEXT, s_txt);
         ObjectSetInteger(0, m_prefix+"ValS", OBJPROP_COLOR, st.slave_pnl >= 0 ? C'120,255,120' : C'255,100,100');
         
         // 3-METRIC PROGRESS LOGIC
         double m_risk_limit = -(st.master_target_risk);
         double m_pct = 0.0;
         if(m_risk_limit != 0) m_pct = st.master_pnl / m_risk_limit;

         double s_target = st.slave_target_gain;
         double s_pct = 0.0;
         if(s_target != 0) s_pct = st.slave_pnl / s_target;

         double diff = MathAbs(m_pct - s_pct);
         double agree_pct = 1.0 - diff;
         
         SetBarState("P1", "Master DD", m_pct, c_bar_master);
         SetBarState("P2", "Slave Tgt", s_pct, c_bar_slave);
         SetBarState("P3", "Sync Health", agree_pct, c_bar_sync_good, true);
         
      } else {
         ObjectSetString(0, m_prefix+"ValS", OBJPROP_TEXT, "Waiting...");
         ObjectSetInteger(0, m_prefix+"ValS", OBJPROP_COLOR, clrGray);
         ObjectSetInteger(0, m_prefix+"P1_Fil", OBJPROP_XSIZE, S(1));
         ObjectSetInteger(0, m_prefix+"P2_Fil", OBJPROP_XSIZE, S(1));
         ObjectSetInteger(0, m_prefix+"P3_Fil", OBJPROP_XSIZE, S(1));
      }

      ObjectSetString(0, m_prefix+"Status", OBJPROP_TEXT, (StringLen(m_status_text) > 0 ? m_status_text : "Active | " + TimeToString(TimeCurrent(), TIME_SECONDS)));
      RefreshAdaptiveWidth();
      ChartRedraw(0); 
   }
   
   void SetStatusText(const string statusText)
   {
      m_status_text = statusText;
      ObjectSetString(0, m_prefix+"Status", OBJPROP_TEXT, statusText);
      RefreshAdaptiveWidth();
   }
   
   void SetBarState(string id, string label, double pct, color filCol, bool isSync=false)
   {
      double displayPct = pct * 100.0;
      double widthPct = pct;
      if(widthPct < 0) widthPct = 0;
      if(widthPct > 1) widthPct = 1;
      
      int w = (int)(PanelInnerWidth() * widthPct); 
      if(w < S(1)) w = S(1);
      ObjectSetInteger(0, m_prefix+id+"_Fil", OBJPROP_XSIZE, w);
      
      color finalColor = filCol;
      if(isSync) {
         if(displayPct < 80.0) finalColor = c_bar_sync_bad;
         else finalColor = c_bar_sync_good;
      }
      ObjectSetInteger(0, m_prefix+id+"_Fil", OBJPROP_BGCOLOR, finalColor);
      
      string txt = label + ": " + DoubleToString(displayPct, 1) + "%";
      ObjectSetString(0, m_prefix+id+"_Txt", OBJPROP_TEXT, txt);
   }

   //+------------------------------------------------------------------+
   //| 5. EVENT HANDLER (With Scale Interactions)                       |
   //+------------------------------------------------------------------+
   void ChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
   {
      if(id == CHARTEVENT_OBJECT_CLICK) {
         if(StringFind(sparam, m_prefix) == 0) {
             if(StringFind(sparam, "MinBtn") > 0) {
                m_minimized = !m_minimized;
                MovePanel(m_x, m_y);
             }
             else if(StringFind(sparam, "ScaleInc") > 0) {
                if(m_scale < 2.5) { 
                   m_scale += 0.1; 
                   Destroy(); CreateObjects(); MovePanel(m_x, m_y); 
                }
                ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
             }
             else if(StringFind(sparam, "ScaleDec") > 0) {
                if(m_scale > 0.5) { 
                   m_scale -= 0.1; 
                   Destroy(); CreateObjects(); MovePanel(m_x, m_y); 
                }
                ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
             }
             else if(StringFind(sparam, "RstBtn") > 0) {
                m_reset_req = true;
                //PlaySound("Ok.wav");
                ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
             }
         }
      }
      else if(id == CHARTEVENT_MOUSE_MOVE) {
         int x = (int)lparam;
         int y = (int)dparam; int buttons = (int)sparam;
         
         if (buttons == 1 && !m_dragging) {
            if (x >= m_x && x <= m_x + m_width && y >= m_y && y <= m_y + S(40)) {
               m_dragging = true;
               m_drag_off_x = x - m_x; m_drag_off_y = y - m_y;
               ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
            }
         }
         else if (buttons == 1 && m_dragging) {
            int newX = x - m_drag_off_x;
            int newY = y - m_drag_off_y;
            if(newX < 0) newX = 0; if(newY < 0) newY = 0;
            MovePanel(newX, newY);
         }
         else if (buttons == 0 && m_dragging) {
            m_dragging = false;
            ChartSetInteger(0, CHART_MOUSE_SCROLL, true);
         }
      }
   }

   void PollButtonStates()
   {
      if(ConsumeButtonState("MinBtn"))
      {
         m_minimized = !m_minimized;
         MovePanel(m_x, m_y);
      }

      if(ConsumeButtonState("ScaleInc"))
      {
         if(m_scale < 2.5)
         {
            m_scale += 0.1;
            Destroy();
            CreateObjects();
            MovePanel(m_x, m_y);
         }
      }

      if(ConsumeButtonState("ScaleDec"))
      {
         if(m_scale > 0.5)
         {
            m_scale -= 0.1;
            Destroy();
            CreateObjects();
            MovePanel(m_x, m_y);
         }
      }

      if(ConsumeButtonState("RstBtn"))
         m_reset_req = true;
   }
   
   bool CheckResetRequest() { 
      if(m_reset_req) { m_reset_req=false; return true; } 
      return false;
   }
   
   void Run() { MovePanel(m_x, m_y); }
   void Destroy() { ObjectsDeleteAll(0, m_prefix); }

private:
   // --- INTERNAL HELPERS ---
   void UpdateObj(string suffix, int x, int y, int w=-1, int h=-1) {
      string n = m_prefix+suffix;
      ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
      if(w > 0) ObjectSetInteger(0, n, OBJPROP_XSIZE, w);
      if(h > 0) ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
   }

   void SetGeom(string suffix, int x, int y) {
      string n = m_prefix+suffix;
      ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   }

   string GetObjText(string suffix)
   {
      string n = m_prefix + suffix;
      if(ObjectFind(0, n) < 0)
         return "";
      return ObjectGetString(0, n, OBJPROP_TEXT);
   }

   void RefreshAdaptiveWidth()
   {
      int desired = PanelMinWidth();
      int titleFont = S(10);
      int smallFont = S(8);
      int valueFont = S(12);
      int rightButtonsWidth = S(95);
      int rightPad = S(12);

      desired = MathMax(desired, HeaderTitleX() + EstimateTextWidth(GetObjText("Title"), titleFont) + rightButtonsWidth);
      desired = MathMax(desired, PanelInnerPadding() + EstimateTextWidth(GetObjText("Status"), smallFont) + rightPad);
      desired = MathMax(desired, PanelInnerPadding() + S(10) + EstimateTextWidth(GetObjText("TitM"), smallFont) + rightPad);
      desired = MathMax(desired, PanelInnerPadding() + S(10) + EstimateTextWidth(GetObjText("ValM"), valueFont, true) + rightPad);
      desired = MathMax(desired, PanelInnerPadding() + S(10) + EstimateTextWidth(GetObjText("TitS"), smallFont) + rightPad);
      desired = MathMax(desired, PanelInnerPadding() + S(10) + EstimateTextWidth(GetObjText("ValS"), valueFont, true) + rightPad);
      desired = MathMax(desired, PanelInnerPadding() + S(5) + EstimateTextWidth(GetObjText("P1_Txt"), smallFont) + rightPad);
      desired = MathMax(desired, PanelInnerPadding() + S(5) + EstimateTextWidth(GetObjText("P2_Txt"), smallFont) + rightPad);
      desired = MathMax(desired, PanelInnerPadding() + S(5) + EstimateTextWidth(GetObjText("P3_Txt"), smallFont) + rightPad);

      if(!m_is_master)
         desired = MathMax(desired, PanelInnerPadding() + EstimateTextWidth("RESET COUNTERS", S(10)) + S(30));

      if(desired != m_width)
      {
         m_width = desired;
         MovePanel(m_x, m_y);
      }
   }

   bool ConsumeButtonState(string suffix)
   {
      string n = m_prefix + suffix;
      if(ObjectFind(0, n) < 0)
         return false;
      if(!ObjectGetInteger(0, n, OBJPROP_STATE))
         return false;

      ObjectSetInteger(0, n, OBJPROP_STATE, false);
      return true;
   }

   void SetHidden(bool hidden) {
      bool vis = !hidden;
      SetVis("Logo", true);
      SetVis("Status", vis); SetVis("CardM", vis); SetVis("TitM", vis); SetVis("ValM", vis);
      SetVis("CardS", vis); SetVis("TitS", vis); SetVis("ValS", vis);
      
      // 3-Bar Visibility
      SetVis("P1_Bg", vis); SetVis("P1_Fil", vis); SetVis("P1_Txt", vis);
      SetVis("P2_Bg", vis); SetVis("P2_Fil", vis); SetVis("P2_Txt", vis);
      SetVis("P3_Bg", vis); SetVis("P3_Fil", vis); SetVis("P3_Txt", vis);

     if(!m_is_master) SetVis("RstBtn", vis);
   }
   
   void SetVis(string s, bool v) { 
      ObjectSetInteger(0, m_prefix+s, OBJPROP_TIMEFRAMES, v ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
   }

   void CreateRect(string s, int w, int h, color bg, color border) {
      string n = m_prefix+s;
      if(ObjectFind(0, n)<0) ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_XSIZE, w); ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
      ObjectSetInteger(0, n, OBJPROP_BGCOLOR, bg); ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, border);
      ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, n, OBJPROP_ZORDER, 10);
   }
   void CreateLabel(string s, string txt, int sz, color c, string font, bool bold=false) {
      string n = m_prefix+s;
      if(ObjectFind(0, n)<0) ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString(0, n, OBJPROP_TEXT, txt); ObjectSetInteger(0, n, OBJPROP_FONTSIZE, sz);
      ObjectSetInteger(0, n, OBJPROP_COLOR, c); ObjectSetString(0, n, OBJPROP_FONT, font);
      ObjectSetInteger(0, n, OBJPROP_ZORDER, 15);
   }
   void CreateBtn(string s, string txt, int w, int h, color bg) {
      string n = m_prefix+s;
      if(ObjectFind(0, n)<0) ObjectCreate(0, n, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString(0, n, OBJPROP_TEXT, txt); ObjectSetInteger(0, n, OBJPROP_XSIZE, w);
      ObjectSetInteger(0, n, OBJPROP_YSIZE, h); ObjectSetInteger(0, n, OBJPROP_BGCOLOR, bg);
      ObjectSetInteger(0, n, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, n, OBJPROP_ZORDER, 20); 
   }
};

//+------------------------------------------------------------------+
//| HELPER: Robust File Opening (Retries if file is locked)          |
//+------------------------------------------------------------------+
int FileOpenRobust(string filename, int flags)
{
   int handle = INVALID_HANDLE;
   int attempts = 0;
   while(attempts < 10) {
      handle = FileOpen(filename, flags);
      if(handle != INVALID_HANDLE) return handle;
      if(GetLastError() != 5004 && GetLastError() != 5002) break;
      if(MBP_ShouldAllowBlockingTradeWait("bridge_file"))
         Sleep(10);
      else
         break;
      attempts++;
   }
   return INVALID_HANDLE;
}
//+------------------------------------------------------------------+

#endif // __MBP_CANONICAL_HEDGEBRIDGE_MQH__


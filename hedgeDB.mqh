//+------------------------------------------------------------------+
//|                                                  HedgeDB.mqh     |
//|                 SQLite database helper for hedge communication  |
//+------------------------------------------------------------------+
#property strict

int HedgeDB = INVALID_HANDLE;

// Open (or create) the database for the given channel
bool OpenHedgeDB(string channel)
{
   string dbname = "Hedge_" + channel + ".db";
   HedgeDB = DatabaseOpen(dbname, DATABASE_OPEN_READWRITE | DATABASE_OPEN_CREATE | DATABASE_OPEN_COMMON);
   if(HedgeDB == INVALID_HANDLE)
   {
      Print("Failed to open database: ", GetLastError());
      return false;
   }

   // Create tables if they don't exist
   string create_signals = "CREATE TABLE IF NOT EXISTS signals("
                           "id INTEGER PRIMARY KEY AUTOINCREMENT,"
                           "ticket INTEGER, lots REAL, type INTEGER, symbol TEXT,"
                           "sl_dist_points REAL, tp_dist_points REAL, time_msc INTEGER,"
                           "action INTEGER, risk_money REAL, comment TEXT,"
                           "processed INTEGER DEFAULT 0)";
   DatabaseExecute(HedgeDB, create_signals);

   string create_state = "CREATE TABLE IF NOT EXISTS state("
                         "id INTEGER PRIMARY KEY CHECK (id=1),"
                         "master_pnl REAL, master_daily_pnl REAL, master_target_risk REAL,"
                         "master_target_profit REAL, master_daily_limit REAL, master_daily_target REAL,"
                         "is_daily_stopped INTEGER, is_total_stopped INTEGER, is_paused INTEGER,"
                         "reset_id INTEGER, slave_pnl REAL, slave_target_gain REAL,"
                         "last_heartbeat INTEGER)";
   DatabaseExecute(HedgeDB, create_state);

   string create_feedback = "CREATE TABLE IF NOT EXISTS feedback("
                            "id INTEGER PRIMARY KEY AUTOINCREMENT,"
                            "master_ticket INTEGER, action INTEGER)";
   DatabaseExecute(HedgeDB, create_feedback);

   string create_proposals = "CREATE TABLE IF NOT EXISTS proposals("
                             "id INTEGER PRIMARY KEY AUTOINCREMENT,"
                             "master_ticket INTEGER, lots REAL, type INTEGER, symbol TEXT,"
                             "sl_dist_points REAL, tp_dist_points REAL, time_msc INTEGER,"
                             "action INTEGER, risk_money REAL, comment TEXT,"
                             "status INTEGER DEFAULT 0)"; // 0=pending, 1=approved, 2=denied
   DatabaseExecute(HedgeDB, create_proposals);

   string create_map = "CREATE TABLE IF NOT EXISTS map("
                       "slave_ticket INTEGER PRIMARY KEY,"
                       "master_ticket INTEGER)";
   DatabaseExecute(HedgeDB, create_map);

   return true;
}

void CloseHedgeDB()
{
   if(HedgeDB != INVALID_HANDLE)
      DatabaseClose(HedgeDB);
}
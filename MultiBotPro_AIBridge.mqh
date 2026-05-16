#ifndef __MULTIBOTPRO_AIBRIDGE_MQH__
#define __MULTIBOTPRO_AIBRIDGE_MQH__
//+------------------------------------------------------------------+
//|                                      MultiBotPro_AIBridge.mqh     |
//| ShadowMaster AI Integration with JSON File Communication         |
//+------------------------------------------------------------------+
#property strict

#import "shell32.dll"
int ShellExecuteW(int hwnd, string lpOperation, string lpFile, string lpParameters, string lpDirectory, int nShowCmd);
#import

// === INPUT PARAMETERS ===
input group "=== AI & ShadowMaster Settings ==="
input bool    InpAIModeEnabled = false;                    // Enable AI mode
input int     InpAIUpdateIntervalHours = 1;                // AI analysis rerun interval (hours)
input int     InpAICheckIntervalMinutes = 5;               // Check for AI updates (minutes)
input bool    InpAIOverrideUserDefaults = true;            // Use AI settings instead of defaults

// === GLOBAL STATE ===
struct SAISettings
{
   double GridDistance;
   double ZoneGapSize;
   double RiskPercentage;
   double MaxDailyLossPercent;
   int    MaxGridLevels;
   double GridMultiplier;
   bool   UseGridMode;
   bool   UseZoneRecovery;
   datetime AppliedAt;
};

static SAISettings G_CurrentAISettings;
static ulong G_LastAICheckTime = 0;
static ulong G_LastAISyncTime = 0;
static bool  G_AISettingsLoaded = false;
static string G_AIDataDir = "";
static string G_AIInputFile = "";
static string G_AIOutputFile = "";

// Returns true if the file exists at the given absolute Windows path
bool MBP_AIFileExists(const string path)
{
   return (GetFileAttributesW(path) != 0xFFFFFFFF);
}

string MBP_GetProgramDirectoryPath()
{
   string programPath = MQLInfoString(MQL_PROGRAM_PATH);
   int lastSep = -1;
   for(int i = StringLen(programPath) - 1; i >= 0; i--)
   {
      string ch = StringSubstr(programPath, i, 1);
      if(ch == "\\" || ch == "/")
      {
         lastSep = i;
         break;
      }
   }
   if(lastSep < 0)
      return programPath;
   return StringSubstr(programPath, 0, lastSep);
}

string MBP_GetShadowMasterExecutablePath()
{
   return MBP_GetProgramDirectoryPath() + "\\PythonApp\\ShadowMaster.exe";
}

string MBP_GetShadowMasterWorkingDirectory()
{
   return MBP_GetProgramDirectoryPath() + "\\PythonApp";
}

string MBP_GetAIDataDirectory()
{
   return MBP_GetProgramDirectoryPath() + "\\PythonApp\\AIData";
}

string MBP_GetAIInputFilePath()
{
   return MBP_GetAIDataDirectory() + "\\market_state.json";
}

string MBP_GetAIOutputFilePath()
{
   return MBP_GetAIDataDirectory() + "\\ai_settings.json";
}

class CAIBridge
{
private:
   string m_aiDataDir;
   string m_inputFile;
   string m_outputFile;

public:
   CAIBridge() : m_aiDataDir(MBP_GetAIDataDirectory()),
                 m_inputFile(MBP_GetAIInputFilePath()),
                 m_outputFile(MBP_GetAIOutputFilePath())
   {
   }

   bool Initialize()
   {
      if(!InpAIModeEnabled)
         return false;

      if(!MBP_AIFileExists(MBP_GetShadowMasterExecutablePath()))
      {
         Print("AI Bridge: ShadowMaster.exe not found at ", MBP_GetShadowMasterExecutablePath());
         return false;
      }

      G_AIDataDir = m_aiDataDir;
      G_AIInputFile = m_inputFile;
      G_AIOutputFile = m_outputFile;
      G_AISettingsLoaded = false;

      Print("AI Bridge: Initialized (Update interval: ", InpAIUpdateIntervalHours, " hours, Check interval: ", InpAICheckIntervalMinutes, " minutes)");
      return true;
   }

   bool BootShadowMaster(string runtime_config_path)
   {
      if(!InpAIModeEnabled)
         return false;

      if(runtime_config_path == "" || !MBP_AIFileExists(runtime_config_path))
      {
         Print("AI Bridge: ShadowMaster launch skipped - runtime config not found at ", runtime_config_path);
         return false;
      }

      string exePath = MBP_GetShadowMasterExecutablePath();
      string workingDir = MBP_GetShadowMasterWorkingDirectory();

      if(exePath == "" || !MBP_AIFileExists(exePath))
      {
         Print("AI Bridge: ShadowMaster launch skipped - executable not found at ", exePath);
         return false;
      }

      Print("AI Bridge: Starting ShadowMaster with AI mode enabled...");
      string args = "\"" + runtime_config_path + "\"";
      int result = ShellExecuteW(0, "open", exePath, args, workingDir, 0);

      if(result <= 32)
      {
         string hint = "";
         if(result == 8)
            hint = " (BAD_FORMAT — likely Git LFS pointer. Restore real ShadowMaster.exe)";
         else if(result == 2 || result == 3)
            hint = " (file/path not found)";
         else if(result == 31)
            hint = " (no associated application)";
         Print("AI Bridge: ShadowMaster launch FAILED. ShellExecuteW returned ", result, hint);
         return false;
      }

      Print("AI Bridge: ShadowMaster process started successfully");
      return true;
   }

   bool ShouldCheckForUpdate()
   {
      if(!InpAIModeEnabled)
         return false;

      ulong now = GetTickCount64();
      ulong intervalMs = (ulong)InpAICheckIntervalMinutes * 60 * 1000;

      if(G_LastAICheckTime == 0 || (now - G_LastAICheckTime) >= intervalMs)
      {
         G_LastAICheckTime = now;
         return true;
      }
      return false;
   }

   bool CheckAndLoadAISettings()
   {
      if(!InpAIModeEnabled || !InpAIOverrideUserDefaults)
         return false;

      if(!ShouldCheckForUpdate())
         return false;

      // Try to read output file
      int fileHandle = FileOpen(G_AIOutputFile, FILE_READ | FILE_TXT);
      if(fileHandle == INVALID_HANDLE)
         return false; // File doesn't exist yet

      string jsonContent = FileReadString(fileHandle);
      FileClose(fileHandle);

      if(jsonContent == "")
         return false;

      if(!ParseAISettings(jsonContent))
         return false;

      G_AISettingsLoaded = true;
      G_LastAISyncTime = GetTickCount64();
      Print("AI Bridge: Successfully loaded new AI settings at ", TimeToString(TimeCurrent()));
      return true;
   }

   bool ParseAISettings(const string jsonContent)
   {
      // Simple JSON parsing (assumes well-formed JSON)
      // Format: {"GridDistance": 100.5, "ZoneGapSize": 50.2, "RiskPercentage": 2.0, ...}

      SAISettings tempSettings = {0};

      // Parse GridDistance
      int pos = StringFind(jsonContent, "\"GridDistance\"");
      if(pos >= 0)
         tempSettings.GridDistance = ExtractDoubleValue(jsonContent, pos);

      // Parse ZoneGapSize
      pos = StringFind(jsonContent, "\"ZoneGapSize\"");
      if(pos >= 0)
         tempSettings.ZoneGapSize = ExtractDoubleValue(jsonContent, pos);

      // Parse RiskPercentage
      pos = StringFind(jsonContent, "\"RiskPercentage\"");
      if(pos >= 0)
         tempSettings.RiskPercentage = ExtractDoubleValue(jsonContent, pos);

      // Parse MaxDailyLossPercent
      pos = StringFind(jsonContent, "\"MaxDailyLossPercent\"");
      if(pos >= 0)
         tempSettings.MaxDailyLossPercent = ExtractDoubleValue(jsonContent, pos);

      // Parse MaxGridLevels
      pos = StringFind(jsonContent, "\"MaxGridLevels\"");
      if(pos >= 0)
         tempSettings.MaxGridLevels = (int)ExtractDoubleValue(jsonContent, pos);

      // Parse GridMultiplier
      pos = StringFind(jsonContent, "\"GridMultiplier\"");
      if(pos >= 0)
         tempSettings.GridMultiplier = ExtractDoubleValue(jsonContent, pos);

      // Parse UseGridMode
      pos = StringFind(jsonContent, "\"UseGridMode\"");
      if(pos >= 0)
         tempSettings.UseGridMode = ExtractBoolValue(jsonContent, pos);

      // Parse UseZoneRecovery
      pos = StringFind(jsonContent, "\"UseZoneRecovery\"");
      if(pos >= 0)
         tempSettings.UseZoneRecovery = ExtractBoolValue(jsonContent, pos);

      tempSettings.AppliedAt = TimeCurrent();
      G_CurrentAISettings = tempSettings;
      return true;
   }

   double ExtractDoubleValue(const string json, int startPos)
   {
      int colonPos = StringFind(json, ":", startPos);
      if(colonPos < 0)
         return 0.0;

      int commaPos = StringFind(json, ",", colonPos);
      if(commaPos < 0)
         commaPos = StringFind(json, "}", colonPos);

      if(commaPos < 0)
         return 0.0;

      string numStr = StringSubstr(json, colonPos + 1, commaPos - colonPos - 1);
      StringTrimLeft(numStr);
      StringTrimRight(numStr);
      return StringToDouble(numStr);
   }

   bool ExtractBoolValue(const string json, int startPos)
   {
      int colonPos = StringFind(json, ":", startPos);
      if(colonPos < 0)
         return false;

      int endPos = StringFind(json, ",", colonPos);
      if(endPos < 0)
         endPos = StringFind(json, "}", colonPos);

      if(endPos < 0)
         return false;

      string boolStr = StringSubstr(json, colonPos + 1, endPos - colonPos - 1);
      StringTrimLeft(boolStr); StringTrimRight(boolStr);
      return (boolStr == "true");
   }

   bool WriteMarketStateFile(const string symbol, double currentPrice, double equity, int openPositions)
   {
      if(!InpAIModeEnabled)
         return false;

      // Create JSON: {"symbol": "EURUSD", "price": 1.0850, "timestamp": "2025-05-04 12:30:45", ...}
      string json = "{";
      json += "\"symbol\": \"" + symbol + "\", ";
      json += "\"price\": " + DoubleToString(currentPrice, 5) + ", ";
      json += "\"equity\": " + DoubleToString(equity, 2) + ", ";
      json += "\"open_positions\": " + IntegerToString(openPositions) + ", ";
      json += "\"timestamp\": \"" + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES) + "\"";
      json += "}";

      int fileHandle = FileOpen(G_AIInputFile, FILE_WRITE | FILE_TXT);
      if(fileHandle == INVALID_HANDLE)
         return false;

      FileWriteString(fileHandle, json);
      FileClose(fileHandle);
      return true;
   }

   SAISettings GetCurrentSettings()
   {
      return G_CurrentAISettings;
   }

   bool IsSettingsLoaded()
   {
      return G_AISettingsLoaded;
   }

   datetime GetLastSyncTime()
   {
      return (datetime)(G_LastAISyncTime / 1000);
   }
};

CAIBridge G_AIBridge;

#endif // __MULTIBOTPRO_AIBRIDGE_MQH__

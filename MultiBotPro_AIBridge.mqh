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

bool MBP_IsShadowMasterProcessRunning()
{
   string roles[] = {"ShadowMaster", "ShadowMaster.exe", "shadowmaster", "shadow"};
   for(int i = 0; i < ArraySize(roles); i++)
   {
      ResetLastError();
      int running = MBP_IsWorkerProcessRunningW(roles[i], "", "");
      if(running > 0)
         return true;
   }

   return false;
}

class CAIBridge
{
public:
   CAIBridge()
   {
   }

   bool Initialize()
   {
      if(!InpEnableShadowMaster)
         return false;

      bool hasExe = MBP_AIFileExists(MBP_GetShadowMasterExecutablePath());
      if(!hasExe)
      {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("AI Bridge: ShadowMaster runtime not found at ", MBP_GetShadowMasterExecutablePath());
         return false;
      }

      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("AI Bridge: Initialized. ShadowMaster.exe is controlled by InpEnableShadowMaster and runtime_v3.json.");
      return true;
   }

   bool BootShadowMaster(string runtime_config_path)
   {
      if(!InpEnableShadowMaster)
         return false;

      string exePath = MBP_GetShadowMasterExecutablePath();
      string workingDir = MBP_GetShadowMasterWorkingDirectory();

      if(MBP_IsShadowMasterProcessRunning())
         if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("AI Bridge: ShadowMaster process exists, but runtime heartbeat is stale; launch recovery will proceed.");

      bool canLaunchExe = (exePath != "" && MBP_AIFileExists(exePath));
      if(!canLaunchExe)
      {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("AI Bridge: ShadowMaster launch skipped - runtime not found at ", exePath);
         return false;
      }

      string target = exePath;
      string args = "\"" + runtime_config_path + "\"";
      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("AI Bridge: Starting ShadowMaster executable | config=", runtime_config_path);
      int result = ShellExecuteW(0, "open", target, args, workingDir, 0);

      if(result <= 32)
      {
         string hint = "";
         if(result == 8)
            hint = " (BAD_FORMAT — likely Git LFS pointer. Restore real ShadowMaster.exe)";
         else if(result == 5)
            hint = " (access denied)";
         else if(result == 2 || result == 3)
            hint = " (file/path not found)";
         else if(result == 31)
            hint = " (no associated application)";
         if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print("AI Bridge: ShadowMaster launch FAILED. ShellExecuteW returned ", result, hint);
         return false;
      }

      if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("AI Bridge: ShadowMaster executable launch accepted by Windows.");
      return true;
   }

};

CAIBridge G_AIBridge;

#endif // __MULTIBOTPRO_AIBRIDGE_MQH__


#ifndef __MULTIBOTPRO_PYTHONBRIDGE_MQH__
#define __MULTIBOTPRO_PYTHONBRIDGE_MQH__
//+------------------------------------------------------------------+
//|                                     MultiBotPro_PythonBridge.mqh |
//|                                     Headless WinPython Launcher  |
//+------------------------------------------------------------------+
#property strict

#import "shell32.dll"
int ShellExecuteW(int hwnd, string lpOperation, string lpFile, string lpParameters, string lpDirectory, int nShowCmd);
#import

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

class CPythonBridge
{
public:
   CPythonBridge() {}
   
   bool BootShadowMaster(string runtime_config_path)
   {
      string exePath = MBP_GetShadowMasterExecutablePath();
      string workingDir = MBP_GetShadowMasterWorkingDirectory();

      if(exePath == "" || MBP_FileExistsW(exePath) <= 0)
      {
         Print("ShadowMaster launch skipped: executable not found at ", exePath);
         return false;
      }

      Print("Starting standalone ShadowMaster Artificial Intelligence engine...");
      string args = "\"" + runtime_config_path + "\"";
      int result = ShellExecuteW(0, "open", exePath, args, workingDir, 0);
      return (result > 32);
   }
};

CPythonBridge G_PythonBridge;

#endif // __MULTIBOTPRO_PYTHONBRIDGE_MQH__

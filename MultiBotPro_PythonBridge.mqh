#ifndef __MULTIBOTPRO_PYTHONBRIDGE_MQH__
#define __MULTIBOTPRO_PYTHONBRIDGE_MQH__
//+------------------------------------------------------------------+
//|                                     MultiBotPro_PythonBridge.mqh |
//|                                                                  |
//| ShadowMaster launcher. As of the self-contained PyInstaller build,|
//| no separate Python runtime is required — the .exe ships its own  |
//| interpreter and all dependencies. WinPython folder is no longer  |
//| bundled by build_installer.ps1 / MultiBotInstaller.iss.          |
//+------------------------------------------------------------------+
#property strict

#import "shell32.dll"
int ShellExecuteW(int hwnd, string lpOperation, string lpFile, string lpParameters, string lpDirectory, int nShowCmd);
#import

// Returns true if the file exists at the given absolute Windows path.
// Uses kernel32 GetFileAttributesW (declared in MultiBotPro_Defines.mqh) so it
// works even when accel.dll is not loaded.
bool MBP_NativeFileExists(const string path)
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

class CPythonBridge
{
public:
   CPythonBridge() {}
   
   bool BootShadowMaster(string runtime_config_path)
   {
      string exePath = MBP_GetShadowMasterExecutablePath();
      string workingDir = MBP_GetShadowMasterWorkingDirectory();

      if(exePath == "" || !MBP_NativeFileExists(exePath))
      {
         Print("ShadowMaster launch skipped: executable not found at ", exePath);
         return false;
      }

      Print("Starting standalone ShadowMaster Artificial Intelligence engine...");
      string args = "\"" + runtime_config_path + "\"";
      int result = ShellExecuteW(0, "open", exePath, args, workingDir, 0);
      if(result <= 32)
      {
         // ShellExecuteW returns <=32 on failure. Common codes:
         //   0  = out of memory
         //   2  = ERROR_FILE_NOT_FOUND
         //   3  = ERROR_PATH_NOT_FOUND
         //   8  = ERROR_BAD_FORMAT  (our LFS pointer / corrupt PE case)
         //   31 = no application is associated
         string hint = "";
         if(result == 8)
            hint = " (BAD_FORMAT — likely a Git LFS pointer or stub. Restore the real PyInstaller-built ShadowMaster.exe.)";
         else if(result == 2 || result == 3)
            hint = " (file/path not found)";
         else if(result == 31)
            hint = " (no associated application)";
         Print("ShadowMaster launch FAILED. ShellExecuteW returned ", result, hint);
         return false;
      }
      return true;
   }
};

CPythonBridge G_PythonBridge;

#endif // __MULTIBOTPRO_PYTHONBRIDGE_MQH__

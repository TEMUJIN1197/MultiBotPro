#ifndef __MULTIBOTPRO_BUNDLEHELPERS_MQH__
#define __MULTIBOTPRO_BUNDLEHELPERS_MQH__

//+------------------------------------------------------------------+
//|                                     MultiBotPro_BundleHelpers.mqh |
//|                     Handles runtime extraction of bundled assets |
//+------------------------------------------------------------------+
#property strict

// Define Global Resource Arrays (linked from MultiBotPro.mq5 via the "as uchar" method)
// Note: These must be reachable in the global scope where they are declared.

bool SaveBinaryAsset(const uchar &data[], string subPath)
{
   if(ArraySize(data) <= 0)
   {
      Print("Bundle Error: Resource data is empty for ", subPath);
      return false;
   }

   string commonPath = TerminalInfoString(TERMINAL_COMMONDATA_PATH);
   string fullPath = commonPath + "\\MQL5\\Files\\MultiBotPro2\\" + subPath;
   
   // Ensure directories exist (MQL5 FolderCreate only works in Sandbox, 
   // but for Common folder it often needs standard file ops or ShellExecute if blocked).
   // However, FileOpen with FILE_COMMON handles path creation in MQL5 for standard subfolders.
   
   ResetLastError();
   int h = FileOpen("MultiBotPro2\\" + subPath, FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(h == INVALID_HANDLE)
   {
      Print("Bundle Error: Could not open file for writing: ", subPath, " | Error: ", GetLastError());
      return false;
   }
   
   FileWriteArray(h, data);
   FileClose(h);
   
   Print("Bundle Success: Extracted ", subPath, " (", ArraySize(data), " bytes) to common folder.");
   return true;
}

// Accessors for external pathing
string GetCommonDataPath()
{
   return TerminalInfoString(TERMINAL_COMMONDATA_PATH) + "\\MQL5\\Files\\MultiBotPro2\\";
}

// Orchestration function to extract all bundled assets
// Note: G_Res_* arrays are defined in MultiBotPro.mq5 via #resource

void Bundle_SetupEnvironment()
{
   Print("Bundle: Setting up environment in common folder...");
   
   // Create subdirectories if needed (Files folder handles this via FileOpen)
   // SaveBinaryAsset(G_Res_AccelDLL, "accel.dll");
   // SaveBinaryAsset(G_Res_ShadowMasterEXE, "PythonApp\\ShadowMaster.exe");
   // SaveBinaryAsset(G_Res_InitDbEXE, "PythonApp\\init_database.exe");
   // SaveBinaryAsset(G_Res_RenkoFallbackEXE, "PythonApp\\renko_fallback.exe");
   
   Print("Bundle: Environment setup complete.");
}

#endif // __MULTIBOTPRO_BUNDLEHELPERS_MQH__

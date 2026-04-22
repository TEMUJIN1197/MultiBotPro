[Setup]
AppName=MultiBotPro Unification Suite
AppVersion=2.0
DefaultDirName={autopf}\MultiBotPro
DisableProgramGroupPage=yes
OutputBaseFilename=MultiBotPro_Installer
Compression=lzma
SolidCompression=yes
PrivilegesRequired=lowest
WizardStyle=modern

[Files]
; Compiled MT5 Executable Robot
Source: "MultiBotPro.ex5"; DestDir: "{tmp}\Payload\Experts\MultiBotPro2"; Flags: ignoreversion skipifsourcedoesntexist
Source: "romeo.bmp"; DestDir: "{tmp}\Payload\Experts\MultiBotPro2"; Flags: ignoreversion skipifsourcedoesntexist
Source: "romeo.ico"; DestDir: "{tmp}\Payload\Experts\MultiBotPro2"; Flags: ignoreversion skipifsourcedoesntexist
Source: "accel.bmp"; DestDir: "{tmp}\Payload\Experts\MultiBotPro2"; Flags: ignoreversion skipifsourcedoesntexist

; Native C++ Worker DLL (Extracted to Libraries for system-wide access)
Source: "accel.dll"; DestDir: "{tmp}\Payload\Libraries"; Flags: ignoreversion skipifsourcedoesntexist

; Python Headless Standalone EXEs (One-File builds)
Source: "PythonApp\ShadowMaster.exe"; DestDir: "{tmp}\Payload\Experts\MultiBotPro2\PythonApp"; Flags: ignoreversion skipifsourcedoesntexist
Source: "PythonApp\renko_fallback.exe"; DestDir: "{tmp}\Payload\Experts\MultiBotPro2\PythonApp"; Flags: ignoreversion skipifsourcedoesntexist
Source: "PythonApp\init_database.exe"; DestDir: "{tmp}\Payload\Experts\MultiBotPro2\PythonApp"; Flags: ignoreversion skipifsourcedoesntexist
Source: "PythonApp\ShadowMaster.bmp"; DestDir: "{tmp}\Payload\Experts\MultiBotPro2\PythonApp"; Flags: ignoreversion skipifsourcedoesntexist
Source: "PythonApp\README.txt"; DestDir: "{tmp}\Payload\Experts\MultiBotPro2\PythonApp"; Flags: ignoreversion skipifsourcedoesntexist

; Full Python Environment (If needed for fallback or advanced extensions)
Source: "PythonApp\WinPython\*"; DestDir: "{tmp}\Payload\Experts\MultiBotPro2\PythonApp\WinPython"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist


[Code]
var
  TerminalsPage: TInputOptionWizardPage;
  FoundHashes: TArrayOfString;
  SelectAllIdx: Integer;
  ErrorCode: Integer;

procedure CheckListBoxClickCheck(Sender: TObject);
var
  i: Integer;
  IsChecked: Boolean;
begin
  if TerminalsPage.CheckListBox.ItemIndex = SelectAllIdx then
  begin
    IsChecked := TerminalsPage.CheckListBox.Checked[SelectAllIdx];
    for i := 1 to TerminalsPage.CheckListBox.Items.Count - 1 do
    begin
      TerminalsPage.CheckListBox.Checked[i] := IsChecked;
    end;
  end;
end;

procedure InitializeWizard;
var
  AppDataPath: string;
  FindRec: TFindRec;
  OriginPathArr: TArrayOfString;
  TerminalName: string;
  Index: Integer;
begin
  TerminalsPage := CreateInputOptionPage(wpSelectDir,
    'Select MetaTrader 5 Terminals',
    'Where would you like to install MultiBotPro?',
    'The installer found the following MetaTrader 5 instances on your system. Please select the terminals you want to install the bot to.',
    False, False);

  SelectAllIdx := TerminalsPage.Add('Install to ALL Terminals');
  TerminalsPage.CheckListBox.Checked[SelectAllIdx] := False;
  TerminalsPage.CheckListBox.OnClickCheck := @CheckListBoxClickCheck;

  AppDataPath := ExpandConstant('{userappdata}\MetaQuotes\Terminal\');
  
  if FindFirst(AppDataPath + '*', FindRec) then
  begin
    try
      repeat
        if (FindRec.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
        begin
          // Terminal folders are 32 character hex strings
          if (FindRec.Name <> '.') and (FindRec.Name <> '..') and (FindRec.Name <> 'Common') and (Length(FindRec.Name) = 32) then
          begin
            TerminalName := FindRec.Name;
            
            // Read origin.txt for friendly name using LoadStringsFromFile which handles Unicode BOM properly
            if LoadStringsFromFile(AppDataPath + FindRec.Name + '\origin.txt', OriginPathArr) then
            begin
              if GetArrayLength(OriginPathArr) > 0 then
                TerminalName := OriginPathArr[0];
            end;
            
            Index := TerminalsPage.Add(TerminalName + ' [' + FindRec.Name + ']');
            SetArrayLength(FoundHashes, GetArrayLength(FoundHashes) + 1);
            FoundHashes[GetArrayLength(FoundHashes) - 1] := FindRec.Name;
          end;
        end;
      until not FindNext(FindRec);
    finally
      FindClose(FindRec);
    end;
  end;
end;

procedure CopyDir(const SourcePath, DestPath: String);
var
  FindRec: TFindRec;
  SourceFilePath, DestFilePath: String;
begin
  if not DirExists(DestPath) then ForceDirectories(DestPath);

  if FindFirst(SourcePath + '\*', FindRec) then
  begin
    try
      repeat
        if (FindRec.Name <> '.') and (FindRec.Name <> '..') then
        begin
          SourceFilePath := SourcePath + '\' + FindRec.Name;
          DestFilePath := DestPath + '\' + FindRec.Name;
          if (FindRec.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
            CopyDir(SourceFilePath, DestFilePath)
          else
            FileCopy(SourceFilePath, DestFilePath, False);
        end;
      until not FindNext(FindRec);
    finally
      FindClose(FindRec);
    end;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  i: Integer;
  DestBase: string;
  PayloadSrc: string;
  InitDbExe: string;
begin
  if CurStep = ssPostInstall then
  begin
    PayloadSrc := ExpandConstant('{tmp}\Payload');
    
    for i := 1 to TerminalsPage.CheckListBox.Items.Count - 1 do
    begin
      if TerminalsPage.CheckListBox.Checked[i] then
      begin
        DestBase := ExpandConstant('{userappdata}\MetaQuotes\Terminal\') + FoundHashes[i - 1];
        
        CopyDir(PayloadSrc + '\Experts', DestBase + '\MQL5\Experts');
        CopyDir(PayloadSrc + '\Libraries', DestBase + '\MQL5\Libraries');

        // Run database initialization script
        InitDbExe := DestBase + '\MQL5\Experts\MultiBotPro2\PythonApp\init_database.exe';
        if FileExists(InitDbExe) then
        begin
          ShellExec('open', InitDbExe, '"' + DestBase + '\MQL5\Files"', '', SW_HIDE, ewWaitUntilTerminated, ErrorCode);
        end;

        // Launch Terminal
        ShellExec('open', DestBase + '\terminal64.exe', '', '', SW_SHOW, ewNoWait, ErrorCode);
      end;
    end;
  end;
end;

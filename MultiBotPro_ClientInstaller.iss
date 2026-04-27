#ifndef StageRoot
  #define StageRoot "S"
#endif

[Setup]
AppName=MultiBotPro Standalone
AppVersion=1.0
DefaultDirName={autopf}\MultiBotPro
DisableProgramGroupPage=yes
OutputBaseFilename=MultiBotPro_v1.0_Setup
OutputDir=Output
SetupIconFile=romeo.ico
Compression=lzma
SolidCompression=yes
PrivilegesRequired=lowest
WizardStyle=modern

[Files]
Source: "{#StageRoot}\E\*"; DestDir: "{tmp}\Payload\Experts\MultiBotPro2"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#StageRoot}\L\*"; DestDir: "{tmp}\Payload\Libraries"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#StageRoot}\P\*"; DestDir: "{tmp}\Payload\Presets"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist
Source: "{#StageRoot}\T\*"; DestDir: "{tmp}\Payload\Profiles\Templates"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist

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
      TerminalsPage.CheckListBox.Checked[i] := IsChecked;
  end;
end;

procedure InitializeWizard;
var
  AppDataPath: string;
  FindRec: TFindRec;
  TerminalName: string;
begin
  TerminalsPage := CreateInputOptionPage(wpSelectDir,
    'Select MetaTrader 5 Terminals',
    'Where would you like to install MultiBotPro?',
    'Select the terminal folders you want to install the fully bundled bot to.',
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
          if (FindRec.Name <> '.') and (FindRec.Name <> '..') and (FindRec.Name <> 'Common') and (Length(FindRec.Name) = 32) then
          begin
            TerminalName := AppDataPath + FindRec.Name;

            SetArrayLength(FoundHashes, GetArrayLength(FoundHashes) + 1);
            FoundHashes[GetArrayLength(FoundHashes) - 1] := FindRec.Name;
            TerminalsPage.Add(TerminalName);
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
  if not DirExists(SourcePath) then exit;
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
            CopyFile(SourceFilePath, DestFilePath, False);
        end;
      until not FindNext(FindRec);
    finally
      FindClose(FindRec);
    end;
  end;
end;

procedure DeployPayloadToTerminal(const DestBase: string; const PayloadSrc: string);
var
  InitDbExe: string;
  InitDbArg: string;
begin
  CopyDir(PayloadSrc + '\Experts', DestBase + '\MQL5\Experts');
  CopyDir(PayloadSrc + '\Libraries', DestBase + '\MQL5\Libraries');
  CopyDir(PayloadSrc + '\Presets', DestBase + '\MQL5\Presets');
  CopyDir(PayloadSrc + '\Profiles', DestBase + '\MQL5\Profiles');

  InitDbExe := DestBase + '\MQL5\Experts\MultiBotPro2\PythonApp\init_database.exe';
  InitDbArg := '"' + DestBase + '\MQL5\Files"';
  if FileExists(InitDbExe) then
    ShellExec('open', InitDbExe, InitDbArg, '', SW_HIDE, ewWaitUntilTerminated, ErrorCode);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  i: Integer;
  DestBase: string;
  PayloadSrc: string;
  InstallAll: Boolean;
begin
  if CurStep = ssPostInstall then
  begin
    PayloadSrc := ExpandConstant('{tmp}\Payload');
    InstallAll := TerminalsPage.CheckListBox.Checked[SelectAllIdx];

    for i := 1 to TerminalsPage.CheckListBox.Items.Count - 1 do
    begin
      if InstallAll or TerminalsPage.CheckListBox.Checked[i] then
      begin
        DestBase := ExpandConstant('{userappdata}\MetaQuotes\Terminal\') + FoundHashes[i - 1];
        Log('Deploying bundled payload to: ' + DestBase);
        DeployPayloadToTerminal(DestBase, PayloadSrc);
      end;
    end;
  end;
end;

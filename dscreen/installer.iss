; D-Screen's installer (docs/shareable_pet_plan.md step 8). Built by tools/pet_export.py --dscreen
; (Inno Setup 6, ISCC) from build/dscreen/app/ into build/dscreen/D-Screen-Setup-<version>.exe.
; Per user, no admin rights: Claude Code's settings and DuckStation's cards are the user's own.

#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
#ifndef AppDir
  #define AppDir "..\build\dscreen\app"
#endif

[Setup]
AppId={{6B0E4C1D-7A3F-4E52-9C8B-D5C2E1F0A417}
AppName=D-Screen
AppVersion={#AppVersion}
AppVerName=D-Screen {#AppVersion}
AppComments=A desktop partner for Digimon World 1. An unofficial fan project.
DefaultDirName={autopf}\D-Screen
DefaultGroupName=D-Screen
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\build\dscreen
OutputBaseFilename=D-Screen-Setup-{#AppVersion}
SetupIconFile=..\engine\dscreen\icon.ico
UninstallDisplayIcon={app}\D-Screen.exe
UninstallDisplayName=D-Screen
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no

[Messages]
WelcomeLabel1=D-Screen
WelcomeLabel2=A desktop partner for Digimon World 1.%n%nD-Screen is an unofficial fan project, not affiliated with or endorsed by Bandai Namco or Toei Animation. Digimon is their trademark. No game data is included: it reads your own copy of Digimon World 1.%n%nYou need your own Digimon World (USA) disc image. If you play it in DuckStation, they're the partner from your memory card save.

[Tasks]
Name: "claude"; Description: "React to Claude Code: adds 5 small hooks to Claude Code's settings (~/.claude/settings.json), so your partner cheers when a long task finishes and looks up when it asks for permission. A backup of the file is kept; uninstalling D-Screen removes the hooks."; GroupDescription: "Claude Code (found on this PC):"; Check: HasClaude
Name: "startup"; Description: "Start D-Screen when I sign in to Windows"; Flags: unchecked
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#AppDir}\D-Screen.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppDir}\dscreen-hook.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "README.txt"; DestDir: "{app}"; Flags: ignoreversion isreadme
Source: "{#AppDir}\THIRD-PARTY-NOTICES.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\D-Screen"; Filename: "{app}\D-Screen.exe"
Name: "{group}\D-Screen README"; Filename: "{app}\README.txt"
Name: "{group}\Uninstall D-Screen"; Filename: "{uninstallexe}"
Name: "{autodesktop}\D-Screen"; Filename: "{app}\D-Screen.exe"; Tasks: desktopicon
Name: "{userstartup}\D-Screen"; Filename: "{app}\D-Screen.exe"; Tasks: startup

[Run]
Filename: "{app}\D-Screen.exe"; Description: "Start D-Screen"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{app}\dscreen-hook.exe"; Parameters: "--uninstall"; Flags: runhidden waituntilterminated; RunOnceId: "RemoveHooks"

[Code]
function HasClaude: Boolean;
var
  Dir: String;
begin
  Dir := GetEnv('CLAUDE_CONFIG_DIR');
  if Dir = '' then
    Dir := ExpandConstant('{%USERPROFILE}\.claude');
  Result := DirExists(Dir);
end;

// The Claude Code hooks (DS8-10): a merge the hook exe refuses (settings.json not valid JSON, or
// changed meanwhile) is said, not hidden.
procedure CurStepChanged(CurStep: TSetupStep);
var
  Code: Integer;
begin
  if (CurStep = ssPostInstall) and WizardIsTaskSelected('claude') then
    if not Exec(ExpandConstant('{app}\dscreen-hook.exe'), '--install', '', SW_HIDE, ewWaitUntilTerminated, Code) or (Code <> 0) then
      SuppressibleMsgBox('The Claude Code hooks weren''t added (code ' + IntToStr(Code) + '): settings.json was left as it was.' #13#10#13#10 +
        'You can add them later with:' #13#10 + ExpandConstant('"{app}\dscreen-hook.exe" --install'), mbInformation, MB_OK, IDOK);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Data: String;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    Data := ExpandConstant('{userappdata}\D-Screen');
    if DirExists(Data) and not UninstallSilent then
      if MsgBox('Also delete your partner''s files in ' + Data + '?' #13#10#13#10 +
                'They hold their settings, their desktop progress and the card backups. Keep them if your partner has desktop gains you haven''t applied to your DW1 save yet.',
                mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
        DelTree(Data, True, True, True);
  end;
end;

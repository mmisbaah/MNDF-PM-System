#ifndef ReleaseSource
  #error ReleaseSource must identify the prepared immutable release directory
#endif
#ifndef ReleaseId
  #error ReleaseId is required
#endif
#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef ReleasePublicKey
  #error ReleasePublicKey is required
#endif
#ifndef NodeRuntimeSource
  #error NodeRuntimeSource must identify the approved portable Node.js runtime
#endif

[Setup]
AppId={{9A6D70E4-672D-4B1C-8C40-828942719A1A}
AppName=Performance Tracker
AppVersion={#AppVersion}
AppPublisher=Performance Tracker
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DefaultDirName={sd}\PerformanceTracker
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputBaseFilename=PerformanceTracker-{#AppVersion}-x64-setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
Uninstallable=yes
CloseApplications=yes
RestartApplications=no
SetupLogging=yes

[Dirs]
Name: "{app}\config"
Name: "{app}\evidence"
Name: "{app}\quarantine"
Name: "{app}\logs"
Name: "{app}\releases"

[Files]
Source: "{#ReleaseSource}\.next\standalone\*"; DestDir: "{app}\releases\{#ReleaseId}\.next\standalone"; Flags: ignoreversion recursesubdirs createallsubdirs uninsneveruninstall
Source: "{#ReleaseSource}\scripts\*"; DestDir: "{app}\releases\{#ReleaseId}\scripts"; Flags: ignoreversion recursesubdirs createallsubdirs uninsneveruninstall
Source: "{#ReleaseSource}\database\migrations\*"; DestDir: "{app}\releases\{#ReleaseId}\database\migrations"; Flags: ignoreversion recursesubdirs createallsubdirs uninsneveruninstall
Source: "{#ReleaseSource}\deploy\*"; DestDir: "{app}\releases\{#ReleaseId}\deploy"; Flags: ignoreversion recursesubdirs createallsubdirs uninsneveruninstall
Source: "{#ReleasePublicKey}"; DestDir: "{app}\config"; DestName: "release-signing-public.pem"; Flags: onlyifdoesntexist uninsneveruninstall
Source: "{#NodeRuntimeSource}\*"; DestDir: "{app}\runtime"; Flags: ignoreversion recursesubdirs createallsubdirs uninsneveruninstall
Source: "assets\complete-installation.ps1"; DestDir: "{app}\installer"; Flags: ignoreversion
Source: "assets\repair-installation.ps1"; DestDir: "{app}\installer"; Flags: ignoreversion
Source: "assets\remove-installation.ps1"; DestDir: "{app}\installer"; Flags: ignoreversion

[Run]
Filename: "powershell.exe"; Parameters: "-NoLogo -NoProfile -ExecutionPolicy AllSigned -File ""{app}\installer\complete-installation.ps1"" -InstallRoot ""{app}"" -ReleaseId ""{#ReleaseId}"" -TrustedPublicKeySha256 ""{#TrustedPublicKeySha256}"""; Description: "Complete secure deployment configuration"; Flags: postinstall waituntilterminated skipifsilent

[UninstallRun]
Filename: "powershell.exe"; Parameters: "-NoLogo -NoProfile -ExecutionPolicy AllSigned -File ""{app}\installer\remove-installation.ps1"" -InstallRoot ""{app}"""; Flags: runhidden waituntilterminated; RunOnceId: "PerformanceTrackerRemoveRuntime"

[Icons]
Name: "{autoprograms}\Performance Tracker\Repair installation"; Filename: "powershell.exe"; Parameters: "-NoLogo -NoProfile -ExecutionPolicy AllSigned -File ""{app}\installer\repair-installation.ps1"" -InstallRoot ""{app}"""; WorkingDir: "{app}"

[Code]
function InitializeSetup(): Boolean;
begin
  Result := IsAdminInstallMode;
  if not Result then
    MsgBox('Performance Tracker must be installed by an approved deployment administrator.', mbError, MB_OK);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if FileExists(ExpandConstant('{app}\config\.env.production.local')) then
    Log('Existing protected configuration detected; setup will not replace it.');
end;

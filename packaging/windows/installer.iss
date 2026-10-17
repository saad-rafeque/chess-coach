; Inno Setup script for the Windows installer.
; Built in CI: iscc /DAppVersion=x.y.z packaging\windows\installer.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{5ABD0F0A-015E-4407-ADF2-CC03E024333D}
AppName=Chess Coach
AppVersion={#AppVersion}
AppVerName=Chess Coach {#AppVersion}
AppPublisher=saad-rafeque
DefaultDirName={autopf}\Chess Coach
DefaultGroupName=Chess Coach
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\chess_coach.exe
UninstallDisplayName=Chess Coach
LicenseFile=..\..\LICENSE
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
OutputDir=..\..\build\installer
OutputBaseFilename=ChessCoach-{#AppVersion}-Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes
; Same file dates in every timezone, so the installer is reproducible.
TimeStampsInUTC=yes

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Chess Coach"; Filename: "{app}\chess_coach.exe"
Name: "{autodesktop}\Chess Coach"; Filename: "{app}\chess_coach.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\chess_coach.exe"; Description: "{cm:LaunchProgram,Chess Coach}"; Flags: nowait postinstall

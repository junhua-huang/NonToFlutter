#define MyAppName "南图 NonTo"
#define MyAppPublisher "南图 NonTo"
#define MyAppURL "https://www.nonto.online"
#ifndef MyAppVersion
  #define MyAppVersion "1.0.1"
#endif
#ifndef MyAppSourceDir
  #define MyAppSourceDir "..\\..\\build\\windows\\x64\\runner\\Release"
#endif
#ifndef MyAppOutputDir
  #define MyAppOutputDir "..\\..\\build\\windows\\installer"
#endif
#ifndef MyAppIcon
  #define MyAppIcon "..\\runner\\resources\\app_icon.ico"
#endif

[Setup]
AppId={{A7C3E5B1-4D2F-4C8A-9E21-6F8B1D4A90C3}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\NonTo
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir={#MyAppOutputDir}
OutputBaseFilename=nonto-setup
SetupIconFile={#MyAppIcon}
UninstallDisplayIcon={app}\nonto.exe
UninstallDisplayName={#MyAppName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no
ChangesAssociations=no

[Languages]
Name: "chinesesimplified"; MessagesFile: "ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务:"; Flags: checkedonce

[Files]
Source: "{#MyAppSourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\nonto.exe"; WorkingDir: "{app}"
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\nonto.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\nonto.exe"; Description: "立即启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

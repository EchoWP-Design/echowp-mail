; Inno-Setup-Skript für den Windows-Installer von EchoWP-Mail
[Setup]
AppId={{8C3F2A1E-5B7D-4E9A-A1C2-3D4E5F607182}
AppName=EchoWP-Mail
AppVersion=5.2.1
AppPublisher=EchoWP
DefaultDirName={autopf}\EchoWP-Mail
DefaultGroupName=EchoWP-Mail
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=EchoWP-Mail-Setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\echowp_mail.exe
WizardStyle=modern

[Languages]
Name: "german"; MessagesFile: "compiler:Languages\German.isl"

[Tasks]
Name: "desktopicon"; Description: "Verknüpfung auf dem Desktop erstellen"; GroupDescription: "Zusätzliche Verknüpfungen:"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\EchoWP-Mail"; Filename: "{app}\echowp_mail.exe"
Name: "{autodesktop}\EchoWP-Mail"; Filename: "{app}\echowp_mail.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\echowp_mail.exe"; Description: "EchoWP-Mail starten"; Flags: nowait postinstall skipifsilent

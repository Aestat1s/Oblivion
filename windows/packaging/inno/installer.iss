[Setup]
AppId={{com.oblivion.launcher}
AppName=Oblivion Launcher
AppVersion=1.0.3
AppVerName=Oblivion Launcher 1.0.3
AppPublisher=Aestat1s Team
AppPublisherURL=https://github.com/Aestat1s
DefaultDirName={autopf}\Oblivion
DefaultGroupName=Oblivion Launcher
DisableProgramGroupPage=yes
OutputDir=..\..\..\dist\1.0.3+3
OutputBaseFilename=oblivion_launcher-1.0.3+3-windows-setup
SetupIconFile=..\..\runner\resources\app_icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Oblivion Launcher"; Filename: "{app}\oblivion_launcher.exe"
Name: "{group}\{cm:UninstallProgram,Oblivion Launcher}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Oblivion Launcher"; Filename: "{app}\oblivion_launcher.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\oblivion_launcher.exe"; Description: "{cm:LaunchProgram,Oblivion Launcher}"; Flags: nowait postinstall skipifsilent

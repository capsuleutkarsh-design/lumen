; Gleo installer (Inno Setup 6). Build with installer\build_installer.ps1, which passes the
; version from pubspec.yaml and makes ..\build\LICENSE.txt from LICENSE.md.
#ifndef AppVersion
  #error Build with installer\build_installer.ps1 (it reads the version from pubspec.yaml)
#endif
#define AppName "Gleo"
; The repository; renamed only at release time (GitHub redirects the old name).
#define AppURL "https://github.com/capsuleutkarsh-design/lumen"
#define SrcDir "..\build\windows\x64\runner\Release"

[Setup]
; A new id for Gleo (Lumen 0.3 and older used {6E3F5A2C-...}), so it installs as its own app.
AppId={{82310E11-6B4C-405C-96FB-5A68751146C2}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Utkarsh Tripathi
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/issues
AppCopyright=Copyright (C) 2026 Utkarsh Tripathi - UT Community Licence 2.0
VersionInfoVersion={#FileVersion}
VersionInfoProductTextVersion={#AppVersion}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
; installs for the current user without admin; "all users" is offered in a dialog
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
LicenseFile=..\build\LICENSE.txt
OutputDir=..\build\installer
OutputBaseFilename=Gleo-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\gleo.exe
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
WizardImageFile=wizard.bmp,wizard@2x.bmp
WizardSmallImageFile=wizard_small.bmp,wizard_small@2x.bmp
; gleo.exe holds this mutex (windows\runner\main.cpp): setup and uninstall ask to close Gleo first.
AppMutex=Gleo.SingleInstance
CloseApplications=no

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SrcDir}\gleo.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SrcDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SrcDir}\*.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SrcDir}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\LICENSE.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\THIRD_PARTY_NOTICES.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\assets\fonts\Inter-OFL.txt"; DestDir: "{app}"; Flags: ignoreversion

[InstallDelete]
; old files from an earlier version
Type: filesandordirs; Name: "{app}\data"

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\gleo.exe"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\gleo.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\gleo.exe"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[Code]
// The library data (database, cover thumbnails, log) is kept on uninstall unless the user says otherwise.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Data: String;
begin
  Data := ExpandConstant('{userappdata}\Utkarsh Tripathi\Gleo');
  if (CurUninstallStep <> usPostUninstall) or UninstallSilent or not DirExists(Data) then
    Exit;
  if MsgBox('Also delete your Gleo library data?' + #13#10#13#10 +
            'This is your library list, playlists, favourites, play counts and cover thumbnails in' + #13#10 +
            Data + #13#10#13#10 +
            'Your music files are never touched. Choose No to keep the data for a later install.',
            mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
  begin
    DelTree(Data, True, True, True);
    RemoveDir(ExpandConstant('{userappdata}\Utkarsh Tripathi'));
  end;
end;

; The Windows installer: rooster-<tag>-windows-x64-setup.exe, built by
; .github/workflows/installers.yml with
;   iscc /DVersion=<tag> /DSource=<release bundle> /DOutput=<dir> /DOutputName=<name> rooster.iss
;
; Per user, no elevation, into %LOCALAPPDATA%\Programs\Rooster: the same place
; the updater moves a build run from a zip to, and one it can replace without
; asking for admin rights. The updater swaps that whole directory for the new
; release (docs/updating.md), so nothing of the installer's own may live in
; it: the uninstaller is kept beside it, and uninstalling removes the
; directory whole rather than the files this installed.

#ifndef Version
  #define Version "v0.0.0"
#endif

[Setup]
AppId={{9DBFC31E-1799-4A7A-AC6E-A7973C1837B3}
AppName=Rooster
AppVersion={#Copy(Version, 2)}
AppPublisher=PondLabs
AppPublisherURL=https://github.com/PondLabs/roosterchat
DefaultDirName={localappdata}\Programs\Rooster
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallFilesDir={localappdata}\Programs\.rooster-uninstall
UninstallDisplayIcon={app}\rooster.exe
UninstallDisplayName=Rooster
SetupIconFile=..\runner\resources\app_icon.ico
WizardStyle=modern
OutputDir={#Output}
OutputBaseFilename={#OutputName}
Compression=lzma2/max
SolidCompression=yes
CloseApplications=yes

[Tasks]
Name: desktopicon; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#Source}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; The name the updater's own Start menu shortcut has (updateTargetFor).
Name: "{userprograms}\Rooster"; Filename: "{app}\rooster.exe"; WorkingDir: "{app}"
Name: "{userdesktop}\Rooster"; Filename: "{app}\rooster.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\rooster.exe"; Description: "{cm:LaunchProgram,Rooster}"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
Type: filesandordirs; Name: "{localappdata}\Programs\.rooster-update"

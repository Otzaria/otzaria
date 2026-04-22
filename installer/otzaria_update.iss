; קובץ עדכון קטן — מכיל רק את קבצי הקוד המשתנים בין גרסאות
; לא כולל: flutter_windows.dll, plugin DLLs, icudtl.dat
; מיועד להורדה אוטומטית מתוך האפליקציה דרך מנגנון updat

#define MyAppName "אוצריא"
#define MyAppVersion "0.9.90"
#define MyAppPublisher "sivan22"
#define MyAppURL "https://github.com/Y-PLONI/otzaria"
#define MyAppExeName "otzaria.exe"

[Setup]
AppId={{EEC4F712-CD05-4D15-A753-509E840A51A5}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; עדכון דורש הרשאות זהות להתקנה המקורית — אין דיאלוג
PrivilegesRequired=lowest
DefaultDirName={code:GetInstallDir}
DisableDirPage=yes
DisableProgramGroupPage=yes
OutputDir=.
OutputBaseFilename=otzaria-{#MyAppVersion}-windows-update
SetupIconFile=white_sketch128x128.ico
Compression=lzma
SolidCompression=yes
CompressionThreads=1
WizardStyle=modern
; אין צורך בהפעלה מחדש
RestartIfNeededByRun=no

[Languages]
Name: "hebrew"; MessagesFile: "compiler:Languages\Hebrew.isl"

[Files]
; רק הקבצים שמשתנים בין גרסאות:
; — otzaria.exe: הקוד הראשי
; — data\flutter_assets: assets מהדר Dart
; — data\app.so: קוד AOT מהודר
; לא כולל: *.dll, flutter_windows.dll, icudtl.dat (אינם משתנים בין גרסאות)
Source: "..\build\windows\x64\runner\Release\otzaria.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "הפעל את {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Code]
function GetInstallDir(Param: String): String;
var
  InstallDir: String;
  UninstallKey: String;
begin
  UninstallKey := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{EEC4F712-CD05-4D15-A753-509E840A51A5}_is1';

  // חיפוש תיקיית ההתקנה הקיימת (admin)
  if RegQueryStringValue(HKLM64, UninstallKey, 'Inno Setup: App Path', InstallDir) and DirExists(InstallDir) then
  begin
    Result := InstallDir;
    exit;
  end;

  // חיפוש תיקיית ההתקנה הקיימת (user)
  if RegQueryStringValue(HKCU, UninstallKey, 'Inno Setup: App Path', InstallDir) and DirExists(InstallDir) then
  begin
    Result := InstallDir;
    exit;
  end;

  // אם לא נמצאה התקנה קיימת — ברירת מחדל
  Result := ExpandConstant('{autopf}\אוצריא');
end;

function InitializeSetup(): Boolean;
var
  InstallDir: String;
begin
  InstallDir := GetInstallDir('');
  if not DirExists(InstallDir) then
  begin
    MsgBox('לא נמצאה התקנה קיימת של אוצריא.' + #13#10 +
           'קובץ זה מיועד לעדכון בלבד. להתקנה ראשונה — הורד את הגרסה המלאה.',
           mbCriticalError, MB_OK);
    Result := False;
  end
  else
    Result := True;
end;

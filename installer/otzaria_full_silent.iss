; מתקין FULL שקט עבור אוצריא.
; משלב את הגרסה השקטה (שיגור-מחדש ב-/VERYSILENT, שימור הגדרות) עם
; תכולת ה-FULL — חילוץ ספריית seforim.db + קטלוג + תלמוד בבלי, והתקנה
; שקטה של WebView2 Runtime אם הוא חסר. אין דפי אשף, אין דיאלוגים.
; אם רץ עם הרשאות מנהל — התקנה לכל המשתמשים; אחרת — למשתמש הנוכחי בלבד.
; הגדרות המשתמש נשמרות (הערות, בוקמרקים, היסטוריה). תיקיית הספרים
; מוחלפת בחבילה החדשה — זהה ל-FULL הרגיל. סיום ההתקנה משיק את אוצריא.

#define MyAppName "אוצריא"
#define MyAppVersion "0.9.94"
#define MyAppPublisher "sivan22"
#define MyAppURL "https://github.com/otzaria/otzaria"
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
; lowest = לא מבקש UAC כשמפעילים רגיל; אם המשתמש בחר "Run as administrator"
; התהליך כבר מורם, IsAdmin=True, ואז משגרים מחדש עם /ALLUSERS.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=commandline
DefaultDirName={code:GetDefaultInstallDir}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=.\
OutputBaseFilename=otzaria-{#MyAppVersion}-windows-full-silent
SetupIconFile=white_sketch128x128.ico
Compression=lzma
SolidCompression=yes
; Disable compression for DLL files to prevent corruption
CompressionThreads=1
WizardStyle=modern
DisableDirPage=yes
DisableReadyPage=yes
DisableFinishedPage=yes
DisableWelcomePage=yes
; ChangesEnvironment=yes נדרש כדי שעדכון ה-PATH (registration אוטומטית של
; otzaria pack-plugin) ייכנס לתוקף מיד עבור תהליכים חדשים ללא logoff.
ChangesEnvironment=yes
; לוג אוטומטי ל-%TEMP% של המשתמש המריץ — חיוני לאבחון התקנות שקטות שנכשלות בשטח.
SetupLogging=yes

[InstallDelete]
; ניקוי מסד הנתונים הישן של Isar שהוחלף על ידי hive_ce — מחיקה מכוונת בעת שדרוג.
Type: filesandordirs; Name: "{app}\default.isar";
; ניקוי תיקיית הספרים הישנה לפני פריסת מסד הנתונים החדש (זהה ל-FULL הרגיל)
Type: filesandordirs; Name: "{code:GetSelectedBooksPath}"

[Dirs]
Name: "{code:GetDataDir}"; Permissions: users-modify
Name: "{code:GetDataDir}\books"; Permissions: users-modify
Name: "{code:GetDataDir}\index"; Permissions: users-modify

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"

[Registry]
Root: HKA; Subkey: "Software\Classes\otzaria"; ValueType: string; ValueName: ""; ValueData: "URL:Otzaria Protocol"; Flags: uninsdeletekeyifempty
Root: HKA; Subkey: "Software\Classes\otzaria"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\otzaria\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName}"; Flags: uninsdeletekeyifempty
Root: HKA; Subkey: "Software\Classes\otzaria\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Flags: uninsdeletekeyifempty
; הוספת {app} ל-PATH של המשתמש — אוטומטית במתקין השקט (אין tasks אופציונליים).
Root: HKCU; Subkey: "Environment"; ValueType: expandsz; ValueName: "Path"; ValueData: "{olddata};{app}"; Flags: preservestringtype; Check: NeedsAddPath(ExpandConstant('{app}'))

[Run]
; התקנה שקטה של WebView2 Runtime אם הוא חסר. waituntilterminated כדי
; לוודא שאוצריא לא מופעלת לפני שה-runtime מוכן.
Filename: "{tmp}\MicrosoftEdgeWebview2Setup.exe"; Parameters: "/silent /install"; StatusMsg: "מתקין Microsoft WebView2 Runtime..."; Flags: waituntilterminated; Check: ShouldInstallWV2
; אין כאן השקת אוצריא: ב-VERYSILENT רשומות [Run] רצות לפני ssPostInstall,
; אז ההשקה הייתה פותחת על ספרייה ריקה. במקום זה משיקים בקוד בסוף החילוץ.

[Languages]
Name: "hebrew"; MessagesFile: "compiler:Languages\Hebrew.isl"

[Files]
; Copy DLL files without compression to prevent corruption
Source: "..\build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion nocompression
; Copy all other app files
Source: "..\build\windows\x64\runner\Release\*"; \
  Excludes: "*.dll"; \
    DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

; Compressed library assets + extraction tools staged in the setup temp dir —
; {tmp} is always writable by the installer process (unlike {app} under Program Files)
; and is auto-deleted when setup exits, even on abort
Source: "library_db\seforim.db.zst"; DestDir: "{tmp}"; Flags: deleteafterinstall nocompression
Source: "library_db\otzar-HB_catalog.db.zst"; DestDir: "{tmp}"; Flags: deleteafterinstall nocompression
Source: "library_db\talmud_bavli_latest.tar.zst"; DestDir: "{tmp}"; Flags: deleteafterinstall nocompression
Source: "zstd.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "7za.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

; MicrosoftEdgeWebview2Setup.exe — bootstrapper קטן (~2MB) שמוריד ומתקין WebView2
Source: "MicrosoftEdgeWebview2Setup.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall; Check: ShouldInstallWV2

; צילומי מסך להצגה בדף ההתקנה (כאשר השיגור מחדש נכשל — fallback בלבד)
Source: "feature1.bmp"; Flags: dontcopy
Source: "feature2.bmp"; Flags: dontcopy
Source: "feature3.bmp"; Flags: dontcopy
Source: "feature4.bmp"; Flags: dontcopy

[INI]
Filename: "{app}\system_install.marker"; Section: "Install"; Key: "Mode"; String: "Admin"; Check: IsAdminInstallMode

[Code]
var
  SlideshowImage: TBitmapImage;
  SlideshowTimerId: LongWord;
  SlideshowTimerCallback: LongWord;
  SlideshowIndex: Integer;

  InstallWV2: Boolean;
  SelectedBooksPath: String;

  // אם המשתמש בחר במהלך ההסרה למחוק גם את כל הנתונים והספרים, לא רק את
  // קבצי האפליקציה. ברירת המחדל False — נשמר כדי לא לאבד נתונים בעדכון
  // שקט (Inno Setup מריץ את ה-uninstaller הישן עם /SILENT).
  DeleteUserDataOnUninstall: Boolean;

// TTimer לא זמין ב-Pascal Script של Inno Setup; נשתמש ב-Windows API.
function SetTimer(hWnd, nIDEvent, uElapse, lpTimerFunc: LongWord): LongWord;
  external 'SetTimer@user32.dll stdcall';
function KillTimer(hWnd, nIDEvent: LongWord): LongWord;
  external 'KillTimer@user32.dll stdcall';

function TryGetInstallDirFromRegistry(RootKey: Integer; const SubKey: String; var InstallDir: String): Boolean;
begin
  Result := RegQueryStringValue(RootKey, SubKey, 'Inno Setup: App Path', InstallDir);
  if (not Result) or (InstallDir = '') then
    Result := RegQueryStringValue(RootKey, SubKey, 'InstallLocation', InstallDir);

  if Result and DirExists(InstallDir) then
    exit;

  InstallDir := '';
  Result := False;
end;

function PathStartsWith(PathValue: String; Prefix: String): Boolean;
var
  NormalizedPath: String;
  NormalizedPrefix: String;
begin
  NormalizedPath := Lowercase(PathValue);
  if (NormalizedPath <> '') and (Copy(NormalizedPath, Length(NormalizedPath), 1) <> '\') then
    NormalizedPath := NormalizedPath + '\';

  NormalizedPrefix := Lowercase(Prefix);
  if (NormalizedPrefix <> '') and (Copy(NormalizedPrefix, Length(NormalizedPrefix), 1) <> '\') then
    NormalizedPrefix := NormalizedPrefix + '\';

  Result := Pos(NormalizedPrefix, NormalizedPath) = 1;
end;

// מזהה נתיבים מערכתיים שמחייבים UAC לשדרוג. זה נותן לנו לבקש הרשאות
// מראש עבור התקנות ישנות שנרשמו ב-HKCU אבל הותקנו בפועל תחת Program Files.
function PathLikelyRequiresAdmin(PathDir: String): Boolean;
begin
  Result :=
    PathStartsWith(PathDir, ExpandConstant('{commonpf}')) or
    PathStartsWith(PathDir, ExpandConstant('{commonpf32}')) or
    PathStartsWith(PathDir, ExpandConstant('{commonpf64}'));
end;

// Exec/ShellExec המובנות מסרבות להריץ את קובץ ה-Setup עצמו מתוך InitializeSetup;
// ייבוא ישיר של ה-API עוקף זאת, וכך ה-UAC מציג את מתקין אוצריא ולא את cmd.exe.
function ShellExecuteW(hwnd: HWND; lpOperation, lpFile, lpParameters,
  lpDirectory: String; nShowCmd: Integer): THandle;
  external 'ShellExecuteW@shell32.dll stdcall';

function RelaunchSetupElevated(Params: String; var ErrorCode: Integer): Boolean;
var
  InstanceHandle: THandle;
begin
  InstanceHandle :=
    ShellExecuteW(0, 'runas', ExpandConstant('{srcexe}'), Params, '', SW_HIDE);
  // ערך מעל 32 = הצלחה; אחרת זהו קוד שגיאת SE_ERR, נשמר לדיווח הכשל.
  Result := InstanceHandle > 32;
  if not Result then
    ErrorCode := InstanceHandle;
end;

// מחזירה את תיקיית ההתקנה הקודמת. RequiresAdmin נקבע לפי מקור הזיהוי
// ובמקרי HKCU גם לפי הנתיב בפועל, כדי לבקש UAC לפני כשל בכתיבה.
function FindPreviousInstallDir(var RequiresAdmin: Boolean): String;
var
  InstallDir: String;
  LegacyDir: String;
  UninstallKey: String;
begin
  RequiresAdmin := False;
  UninstallKey := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{EEC4F712-CD05-4D15-A753-509E840A51A5}_is1';

  // HKLM64 = התקנה מערכתית קודמת ⇒ דורשת מנהל לשדרוג.
  if TryGetInstallDirFromRegistry(HKLM64, UninstallKey, InstallDir) then
  begin
    Result := InstallDir;
    RequiresAdmin := True;
    exit;
  end;

  // בדרך כלל HKCU = התקנת משתמש. אם הנתיב בפועל תחת Program Files,
  // מבקשים UAC מראש כדי לא ליפול לכשל כתיבה מאוחר יותר.
  if TryGetInstallDirFromRegistry(HKCU, UninstallKey, InstallDir) then
  begin
    Result := InstallDir;
    RequiresAdmin := PathLikelyRequiresAdmin(InstallDir);
    exit;
  end;

  // C:\אוצריא = שורש דרייב מערכתי ⇒ יצירה/שכתוב דורשים מנהל.
  LegacyDir := 'C:\אוצריא';
  if DirExists(LegacyDir) then
  begin
    Result := LegacyDir;
    RequiresAdmin := True;
    exit;
  end;

  LegacyDir := ExpandConstant('{autopf}\אוצריא');
  if DirExists(LegacyDir) then
  begin
    Result := LegacyDir;
    exit;
  end;

  LegacyDir := ExpandConstant('{autopf}\Otzaria');
  if DirExists(LegacyDir) then
  begin
    Result := LegacyDir;
    exit;
  end;

  Result := '';
end;

function GetDefaultInstallDir(Param: String): String;
var
  Dummy: Boolean;
begin
  Result := FindPreviousInstallDir(Dummy);
  if Result = '' then
    Result := ExpandConstant('{autopf}\Otzaria');
end;

function GetDataDir(Param: String): String;
begin
  if IsAdminInstallMode then
    Result := ExpandConstant('{commonappdata}\otzaria')
  else
    Result := ExpandConstant('{userappdata}\otzaria');
end;

function GetSelectedBooksPath(Param: String): String;
begin
  if SelectedBooksPath <> '' then
    Result := SelectedBooksPath
  else
    Result := GetDataDir('') + '\books';
end;

// ─── בדיקת WebView2 ────────────────────────────────────────────────────────

function GetWebView2Version: String;
var
  Version: String;
begin
  if RegQueryStringValue(HKLM64,
      'SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
      'pv', Version) then
  begin
    Result := Version;
    exit;
  end;
  if RegQueryStringValue(HKCU,
      'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
      'pv', Version) then
    Result := Version
  else
    Result := '';
end;

function WebView2NeedsInstall: Boolean;
begin
  Result := GetWebView2Version = '';
end;

function ShouldInstallWV2: Boolean;
begin
  Result := InstallWV2;
end;

// ─── כתיבת נתיב הספרים ל-shared_preferences.json ───────────────────────────

function EscapeJsonString(const Value: String): String;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(Value) do
  begin
    if Value[i] = '\' then
      Result := Result + '\\'
    else if Value[i] = '"' then
      Result := Result + '\"'
    else
      Result := Result + Value[i];
  end;
end;

function LoadTextFile(const FileName: String): String;
var
  Lines: TArrayOfString;
  i: Integer;
begin
  Result := '';
  if not LoadStringsFromFile(FileName, Lines) then
    exit;

  for i := 0 to GetArrayLength(Lines) - 1 do
  begin
    if i > 0 then
      Result := Result + #13#10;
    Result := Result + Lines[i];
  end;
end;

function FindJsonStringEnd(const Text: String; StartPos: Integer): Integer;
begin
  Result := StartPos;
  while Result <= Length(Text) do
  begin
    if (Text[Result] = '"') and ((Result = StartPos) or (Text[Result - 1] <> '\')) then
      exit;
    Result := Result + 1;
  end;

  Result := 0;
end;

procedure WriteLibraryPathToPrefs(const LibraryPath: String);
var
  PrefsDir, PrefsFile, JsonContent, NewEntry: String;
  SharedPrefsKey, LegacyPrefsKey: String;
  KeyPos, ValueStart, ValueEnd, PairEnd, LastBrace, ExistingLength: Integer;
begin
  SharedPrefsKey := '"flutter.key-library-path":';
  LegacyPrefsKey := '"key-library-path":';
  PrefsDir := ExpandConstant('{userappdata}\otzaria');
  PrefsFile := PrefsDir + '\shared_preferences.json';

  ForceDirectories(PrefsDir);

  NewEntry := SharedPrefsKey + '"' + EscapeJsonString(LibraryPath) + '"';

  if FileExists(PrefsFile) then
    JsonContent := Trim(LoadTextFile(PrefsFile))
  else
    JsonContent := '';

  if JsonContent = '' then
  begin
    SaveStringToFile(PrefsFile, '{' + NewEntry + '}', False);
    exit;
  end;

  KeyPos := Pos(SharedPrefsKey, JsonContent);
  ExistingLength := Length(SharedPrefsKey);
  if KeyPos = 0 then
  begin
    KeyPos := Pos(LegacyPrefsKey, JsonContent);
    ExistingLength := Length(LegacyPrefsKey);
  end;

  if KeyPos > 0 then
  begin
    ValueStart := KeyPos + ExistingLength;
    while (ValueStart <= Length(JsonContent)) and (JsonContent[ValueStart] = ' ') do
      ValueStart := ValueStart + 1;

    if (ValueStart <= Length(JsonContent)) and (JsonContent[ValueStart] = '"') then
    begin
      ValueEnd := FindJsonStringEnd(JsonContent, ValueStart + 1);
      if ValueEnd > 0 then
      begin
        PairEnd := ValueEnd + 1;
        while (PairEnd <= Length(JsonContent)) and (JsonContent[PairEnd] = ' ') do
          PairEnd := PairEnd + 1;
        JsonContent :=
          Copy(JsonContent, 1, KeyPos - 1) +
          NewEntry +
          Copy(JsonContent, PairEnd, Length(JsonContent) - PairEnd + 1);
        SaveStringToFile(PrefsFile, JsonContent, False);
        exit;
      end;
    end;
  end;

  LastBrace := Length(JsonContent);
  while (LastBrace > 0) and (JsonContent[LastBrace] <> '}') do
    LastBrace := LastBrace - 1;

  if (LastBrace = 0) or (Trim(JsonContent) = '{}') then
    JsonContent := '{' + NewEntry + '}'
  else
  begin
    PairEnd := LastBrace - 1;
    while (PairEnd > 0) and (JsonContent[PairEnd] <= ' ') do
      PairEnd := PairEnd - 1;

    if (PairEnd > 0) and (JsonContent[PairEnd] <> '{') and (JsonContent[PairEnd] <> ',') then
      JsonContent :=
        Copy(JsonContent, 1, LastBrace - 1) + ',' + NewEntry +
        Copy(JsonContent, LastBrace, Length(JsonContent) - LastBrace + 1)
    else
      JsonContent :=
        Copy(JsonContent, 1, LastBrace - 1) + NewEntry +
        Copy(JsonContent, LastBrace, Length(JsonContent) - LastBrace + 1);
  end;

  SaveStringToFile(PrefsFile, JsonContent, False);
end;

// ─── חילוץ הספריה המצורפת ──────────────────────────────────────────────────

// מריץ קובץ הרצה ולוכד את פלט ה-stderr/stdout שלו, כדי שב-Log יופיע
// טעם הכשל האמיתי (אין מקום בדיסק / קובץ נעול / פגום) במקום קוד יציאה בלבד.
// מחזיר False רק אם ההרצה עצמה נכשלה; קוד היציאה מוחזר ב-ResultCode.
function RunAndCaptureErrors(const Exe, Params: String;
  var ResultCode: Integer; var CapturedOutput: String): Boolean;
var
  Output: TExecOutput;
  I: Integer;
begin
  CapturedOutput := '';
  Result := ExecAndCaptureOutput(Exe, Params, '', SW_HIDE,
    ewWaitUntilTerminated, ResultCode, Output);
  if not Result then
    exit;
  for I := 0 to GetArrayLength(Output.StdErr) - 1 do
    if Trim(Output.StdErr[I]) <> '' then
      CapturedOutput := CapturedOutput + Output.StdErr[I] + ' ';
  for I := 0 to GetArrayLength(Output.StdOut) - 1 do
    if Trim(Output.StdOut[I]) <> '' then
      CapturedOutput := CapturedOutput + Output.StdOut[I] + ' ';
end;

procedure ExtractBundledDatabase(const ArchiveName, DatabaseName: String);
var
  ArchivePath, DatabasePath, ZstdPath, Params, ErrOutput: String;
  ResultCode: Integer;
begin
  ArchivePath := ExpandConstant('{tmp}\' + ArchiveName);
  if not FileExists(ArchivePath) then
  begin
    Log('Bundled database archive not found, skipping: ' + ArchivePath);
    exit;
  end;

  DatabasePath := SelectedBooksPath + '\' + DatabaseName;
  ZstdPath := ExpandConstant('{tmp}\zstd.exe');

  ForceDirectories(ExtractFileDir(DatabasePath));

  Log('Extracting bundled database from ' + ArchivePath);
  Params := '-d -f -T0 --long=31 "' + ArchivePath + '" -o "' + DatabasePath + '"';

  if (not RunAndCaptureErrors(ZstdPath, Params, ResultCode, ErrOutput)) or (ResultCode <> 0) then
  begin
    // במצב שקט אין מי שיראה את MsgBox — מתעדים ב-Log ויוצאים בכשל.
    Log('Database extraction failed with code ' + IntToStr(ResultCode) + ': '
      + ArchivePath + ' | zstd: ' + ErrOutput);
    Abort;
  end;

  DeleteFile(ArchivePath);
end;

procedure ExtractBundledTarArchive(const ArchiveName, TargetDirName: String);
var
  ArchivePath, TarPath, ParentDir, TargetDir, ZstdPath, SevenZipPath, Params, ErrOutput: String;
  ResultCode: Integer;
begin
  ArchivePath := ExpandConstant('{tmp}\' + ArchiveName);
  if not FileExists(ArchivePath) then
  begin
    Log('Bundled archive not found, skipping: ' + ArchivePath);
    exit;
  end;

  ParentDir := SelectedBooksPath;
  TarPath := ParentDir + '\' + ChangeFileExt(ArchiveName, '');
  TargetDir := SelectedBooksPath + '\' + TargetDirName;
  ZstdPath := ExpandConstant('{tmp}\zstd.exe');
  SevenZipPath := ExpandConstant('{tmp}\7za.exe');

  if DirExists(TargetDir) then
  begin
    DelTree(TargetDir, True, True, True);
  end;

  Log('Extracting bundled tar archive from ' + ArchivePath);
  Params := '-d -f -T0 --long=31 "' + ArchivePath + '" -o "' + TarPath + '"';

  if (not RunAndCaptureErrors(ZstdPath, Params, ResultCode, ErrOutput)) or (ResultCode <> 0) then
  begin
    Log('Tar zstd extraction failed with code ' + IntToStr(ResultCode) + ': '
      + ArchivePath + ' | zstd: ' + ErrOutput);
    Abort;
  end;

  Params := 'x -y "' + TarPath + '" "-o' + ParentDir + '"';
  if (not RunAndCaptureErrors(SevenZipPath, Params, ResultCode, ErrOutput)) or
     (ResultCode <> 0) then
  begin
    Log('7za extraction failed with code ' + IntToStr(ResultCode) + ': '
      + TarPath + ' | 7za: ' + ErrOutput);
    Abort;
  end;

  DeleteFile(TarPath);
  DeleteFile(ArchivePath);
end;

// ─── slideshow (גלוי רק אם השיגור-מחדש נכשל) ───────────────────────────────

procedure OnSlideshowTimer(H: LongWord; Msg: LongWord; IdEvent: LongWord; Time: LongWord);
var
  NextFile: String;
begin
  if SlideshowImage = nil then
    exit;
  SlideshowIndex := (SlideshowIndex + 1) mod 4;
  case SlideshowIndex of
    0: NextFile := 'feature1.bmp';
    1: NextFile := 'feature2.bmp';
    2: NextFile := 'feature3.bmp';
    3: NextFile := 'feature4.bmp';
  end;
  SlideshowImage.Bitmap.LoadFromFile(ExpandConstant('{tmp}\') + NextFile);
end;

procedure InitializeSlideshow;
var
  GaugeBottom, AvailH, ImgH: Integer;
begin
  if WizardForm = nil then
    exit;
  SlideshowIndex := 0;
  ExtractTemporaryFile('feature1.bmp');
  ExtractTemporaryFile('feature2.bmp');
  ExtractTemporaryFile('feature3.bmp');
  ExtractTemporaryFile('feature4.bmp');
  GaugeBottom := WizardForm.ProgressGauge.Top + WizardForm.ProgressGauge.Height;
  AvailH := WizardForm.InstallingPage.Height - GaugeBottom;
  if AvailH < ScaleY(60) then
    exit;
  ImgH := AvailH - ScaleY(10);
  SlideshowImage := TBitmapImage.Create(WizardForm.InstallingPage);
  SlideshowImage.Parent := WizardForm.InstallingPage;
  SlideshowImage.Stretch := True;
  SlideshowImage.Left := 0;
  SlideshowImage.Top := GaugeBottom + ScaleY(8);
  SlideshowImage.Width := WizardForm.InstallingPage.Width;
  SlideshowImage.Height := ImgH;
  SlideshowImage.Bitmap.LoadFromFile(ExpandConstant('{tmp}\feature1.bmp'));
  SlideshowTimerCallback := CreateCallback(@OnSlideshowTimer);
end;

procedure InitializeWizard;
begin
  // ערכי ברירת מחדל עבור הריצה השקטה (אין דפי אשף לקבוע אותם).
  InstallWV2 := WebView2NeedsInstall;
  SelectedBooksPath := GetDataDir('') + '\books';
  InitializeSlideshow;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if SlideshowTimerCallback = 0 then
    exit;
  if CurPageID = wpInstalling then
  begin
    if SlideshowTimerId = 0 then
      SlideshowTimerId := SetTimer(0, 0, 1500, SlideshowTimerCallback);
  end
  else if SlideshowTimerId <> 0 then
  begin
    KillTimer(0, SlideshowTimerId);
    SlideshowTimerId := 0;
  end;
end;

function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
  PrivilegeFlag: String;
  Launched: Boolean;
  RequiresAdmin: Boolean;
  PreviousDir: String;
begin
  Result := True;

  // הגדרת SelectedBooksPath כברירת מחדל כבר עכשיו, כדי ש-GetSelectedBooksPath
  // (שמשמש ב-[InstallDelete]) יחזיר ערך תקין גם בריצה הקצרה (קוד שיגור-מחדש).
  SelectedBooksPath := GetDataDir('') + '\books';
  InstallWV2 := WebView2NeedsInstall;

  // אם המשתמש פתח את ה-EXE רגיל (לא דרך command-line שקט), משגרים את
  // עצמנו מחדש ב-/VERYSILENT. בריצה השנייה WizardSilent יהיה True
  // והקוד הזה לא ירוץ שוב.
  if not WizardSilent then
  begin
    PreviousDir := FindPreviousInstallDir(RequiresAdmin);

    if IsAdmin then
    begin
      PrivilegeFlag := '/ALLUSERS';
    end
    else if RequiresAdmin then
    begin
      PrivilegeFlag := '/ALLUSERS';
      Launched := RelaunchSetupElevated(
        '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART ' + PrivilegeFlag,
        ResultCode);

      if Launched then
      begin
        Result := False;
        exit;
      end;

      MsgBox(
        'אוצריא הותקנה בעבר בנתיב הדורש הרשאות מנהל:' + #13#10 +
        PreviousDir + #13#10 + #13#10 +
        'כדי לשדרג, יש להפעיל את המתקין כמנהל' + #13#10 +
        '(קליק ימני על קובץ ההתקנה ↦ "Run as administrator").',
        mbError, MB_OK);
      Result := False;
      exit;
    end
    else
    begin
      PrivilegeFlag := '/CURRENTUSER';
    end;

    Launched := Exec(ExpandConstant('{srcexe}'),
         '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART ' + PrivilegeFlag,
         '', SW_HIDE, ewNoWait, ResultCode);

    if Launched then
    begin
      Result := False;
      exit;
    end;

    Launched := ShellExec('open', ExpandConstant('{srcexe}'),
         '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART ' + PrivilegeFlag,
         '', SW_HIDE, ewNoWait, ResultCode);

    if Launched then
    begin
      Result := False;
      exit;
    end;

    // השיגור מחדש נכשל לחלוטין — ממשיכים בתהליך הנוכחי (Result נשאר True).
    // כל עמודי האשף מנוטרלים, אז המשתמש יראה רק את חלון ההתקדמות עד לסיום.
  end;
end;

// ─── ניהול PATH ─────────────────────────────────────────────────────────────

function NeedsAddPath(NewPath: String): Boolean;
var
  CurrentPath: String;
  Needle1, Needle2, Haystack: String;
begin
  Result := True;
  if not RegQueryStringValue(HKCU, 'Environment', 'Path', CurrentPath) then
    exit;

  Haystack  := ';' + Lowercase(CurrentPath) + ';';
  Needle1   := ';' + Lowercase(NewPath) + ';';
  Needle2   := ';' + Lowercase(NewPath) + '\;';
  if (Pos(Needle1, Haystack) > 0) or (Pos(Needle2, Haystack) > 0) then
    Result := False;
end;

procedure RemoveAppFromUserPath(PathToRemove: String);
var
  CurrentPath, LowerCurrent: String;
  Needles: array[0..1] of String;
  LowerNeedle: String;
  P, i: Integer;
  Changed: Boolean;
begin
  if not RegQueryStringValue(HKCU, 'Environment', 'Path', CurrentPath) then
    exit;

  Changed := False;
  CurrentPath := ';' + CurrentPath + ';';

  Needles[0] := ';' + Lowercase(PathToRemove) + ';';
  Needles[1] := ';' + Lowercase(PathToRemove) + '\;';

  for i := 0 to 1 do
  begin
    LowerNeedle := Needles[i];
    LowerCurrent := Lowercase(CurrentPath);
    P := Pos(LowerNeedle, LowerCurrent);
    while P > 0 do
    begin
      Delete(CurrentPath, P, Length(LowerNeedle) - 1);
      LowerCurrent := Lowercase(CurrentPath);
      Changed := True;
      P := Pos(LowerNeedle, LowerCurrent);
    end;
  end;

  if not Changed then
    exit;

  if (Length(CurrentPath) > 0) and (CurrentPath[1] = ';') then
    Delete(CurrentPath, 1, 1);
  if (Length(CurrentPath) > 0) and (CurrentPath[Length(CurrentPath)] = ';') then
    Delete(CurrentPath, Length(CurrentPath), 1);

  RegWriteExpandStringValue(HKCU, 'Environment', 'Path', CurrentPath);
end;

// מחזיר את נתיב תיקיית הספרים שהמשתמש בחר (אם שונה מברירת המחדל),
// כפי שנשמר ב-shared_preferences.json תחת המפתח flutter.key-library-path.
// משתמש בעוזרי ה-JSON הקיימים (LoadTextFile, FindJsonStringEnd) ובפענוח
// escapes ה-JSON בסיסי שתואם ל-EscapeJsonString.
function GetCustomLibraryPath(): String;
var
  PrefsFile, JsonContent, KeyStr, Value: String;
  KeyPos, ValueStart, ValueEnd: Integer;
begin
  Result := '';
  PrefsFile := ExpandConstant('{userappdata}\otzaria\shared_preferences.json');
  if not FileExists(PrefsFile) then
    exit;

  JsonContent := LoadTextFile(PrefsFile);
  if JsonContent = '' then
    exit;

  KeyStr := '"flutter.key-library-path":';
  KeyPos := Pos(KeyStr, JsonContent);
  if KeyPos = 0 then
  begin
    KeyStr := '"key-library-path":';
    KeyPos := Pos(KeyStr, JsonContent);
  end;
  if KeyPos = 0 then
    exit;

  ValueStart := KeyPos + Length(KeyStr);
  while (ValueStart <= Length(JsonContent)) and
        (JsonContent[ValueStart] <> '"') do
    ValueStart := ValueStart + 1;
  if ValueStart > Length(JsonContent) then
    exit;
  ValueStart := ValueStart + 1;

  ValueEnd := FindJsonStringEnd(JsonContent, ValueStart);
  if ValueEnd <= 0 then
    exit;

  Value := Copy(JsonContent, ValueStart, ValueEnd - ValueStart);
  StringChangeEx(Value, '\\', '\', True);
  StringChangeEx(Value, '\"', '"', True);
  Result := Value;
end;

// בודק שהתיקייה נראית כמו תיקיית ספרים של אוצריא — כלומר מכילה לפחות
// אחד מהסימנים הייחודיים שמותקנים ע"י המתקין FULL. נחוץ לפני DelTree על
// נתיב שמגיע מהמשתמש (prefs), כדי שלא נמחק תיקייה אישית רחבה שהמשתמש
// בחר בטעות כנתיב ספרים (למשל D:\, Downloads, Documents).
function IsOtzariaBooksFolder(const Path: String): Boolean;
begin
  Result := False;
  // אורך מינימלי 6 פוסל גם 'C:\' וגם 'C:\X'; מונע מחיקה בקרבת שורש כונן.
  if (Path = '') or (Length(Path) < 6) then
    exit;
  if not DirExists(Path) then
    exit;
  if FileExists(Path + '\seforim.db') or
     FileExists(Path + '\otzar-HB_catalog.db') or
     DirExists(Path + '\תלמוד בבלי') then
    Result := True;
end;

// מוחק את כל הנתונים והספרים של אוצריא: ספריית הספרים המותאמת אישית
// (רק אם היא מזוהה כתיקיית אוצריא — ראה IsOtzariaBooksFolder), כל תיקיות
// הנתונים הסטנדרטיות וגם נתיבי legacy. קוראים את הנתיב המותאם מה-prefs
// לפני שמוחקים את ה-prefs עצמו.
procedure DeleteAllUserData();
var
  Path: String;
begin
  Path := GetCustomLibraryPath();
  if IsOtzariaBooksFolder(Path) then
    DelTree(Path, True, True, True);

  Path := ExpandConstant('{commonappdata}\otzaria');
  if DirExists(Path) then
    DelTree(Path, True, True, True);

  Path := ExpandConstant('{userappdata}\otzaria');
  if DirExists(Path) then
    DelTree(Path, True, True, True);

  Path := ExpandConstant('{localappdata}\otzaria');
  if DirExists(Path) then
    DelTree(Path, True, True, True);

  // נתיבים ישנים: מזהה חבילה לפני שינוי (com.example) ושמות עבריים.
  Path := ExpandConstant('{userappdata}\com.example');
  if DirExists(Path) then
    DelTree(Path, True, True, True);

  Path := ExpandConstant('{localappdata}\אוצריא');
  if DirExists(Path) then
    DelTree(Path, True, True, True);

  // הערה: C:\אוצריא לא נמחק כאן כי זה היה נתיב התקנה legacy (לא נתונים).
  // אם נשארה שם התקנה ישנה — היא תוסר על ידי ה-uninstaller שלה.
end;

// שאלה בתחילת ההסרה: האם למחוק גם את הנתונים והספרים?
// בהסרה שקטה (כולל עדכון שמריץ unins000.exe /SILENT) MsgBox מחזיר אוטומטית
// את ברירת המחדל; MB_DEFBUTTON2 דואג שברירת המחדל היא "לא" כך שנתוני
// המשתמש נשמרים אם הוא לא בחר במפורש למחוק.
function InitializeUninstall(): Boolean;
var
  CustomPath, Msg: String;
begin
  Result := True;
  DeleteUserDataOnUninstall := False;

  CustomPath := GetCustomLibraryPath();

  Msg := 'האם למחוק גם את הספרים וכל הנתונים של אוצריא?' + #13#10 + #13#10 +
         'בכל מקרה תוסר התוכנה. בחירה ב"כן" תמחק בנוסף:' + #13#10;

  // אם יש נתיב ספרים מותאם והוא מזוהה כתיקיית אוצריא — נציג אותו במפורש.
  // אחרת לא מציינים נתיב חיצוני; תיקיית הספרים שתחת AppData ממילא נמחקת
  // כחלק מ-{userappdata}\otzaria / {commonappdata}\otzaria.
  if IsOtzariaBooksFolder(CustomPath) then
    Msg := Msg + '• תיקיית הספרים:' + #13#10 +
                 '   ' + CustomPath + #13#10
  else
    Msg := Msg + '• תיקיית הספרים שתחת תיקיית הנתונים' + #13#10;

  Msg := Msg +
         '• מסדי הנתונים, אינדקס החיפוש, הגדרות,' + #13#10 +
         '   סימניות, היסטוריה והערות אישיות' + #13#10 + #13#10 +
         'בחר "לא" כדי לשמור את הנתונים לקראת התקנה עתידית.';

  if MsgBox(Msg, mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
  begin
    if MsgBox(
         'שים לב: לא ניתן יהיה לשחזר את הנתונים לאחר המחיקה.' + #13#10 + #13#10 +
         'האם אתה בטוח שברצונך למחוק את כל הספרים והנתונים?',
         mbCriticalError, MB_YESNO or MB_DEFBUTTON2) = IDYES then
      DeleteUserDataOnUninstall := True;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
  begin
    RemoveAppFromUserPath(ExpandConstant('{app}'));
    if DeleteUserDataOnUninstall then
      DeleteAllUserData();
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ErrorLogPath: string;
  ZstdPath, SevenZipPath: String;
  ResultCode: Integer;
begin
  if CurStep = ssInstall then
  begin
    // מחק את לוג השגיאות הישן בכל התקנה/עדכון.
    // הערה: זו אינה הגדרת משתמש — זה לוג מצטבר שמתנקה בכל עדכון.
    // המתקין השקט אינו מאפס הגדרות אחרות (הערות, בוקמרקים, היסטוריה וכו').
    ErrorLogPath := ExpandConstant('{userappdata}\otzaria\logs\errors.txt');
    if FileExists(ErrorLogPath) then
      DeleteFile(ErrorLogPath);
    ErrorLogPath := ExpandConstant('{commonappdata}\otzaria\logs\errors.txt');
    if FileExists(ErrorLogPath) then
      DeleteFile(ErrorLogPath);
  end;

  if CurStep <> ssPostInstall then
    exit;

  // ─── חילוץ הספריה המצורפת ─────────────────────────────────────────────
  ZstdPath := ExpandConstant('{tmp}\zstd.exe');
  SevenZipPath := ExpandConstant('{tmp}\7za.exe');

  if not FileExists(ZstdPath) then
  begin
    Log('zstd.exe not found - cannot extract bundled library');
    Abort;
  end;

  if not FileExists(SevenZipPath) then
  begin
    Log('7za.exe not found - cannot extract bundled PDF archive');
    Abort;
  end;

  WizardForm.ProgressGauge.Style := npbstMarquee;

  WizardForm.StatusLabel.Caption := 'מחלץ מסד הנתונים seforim.db...';
  WizardForm.StatusLabel.Update;
  ExtractBundledDatabase('seforim.db.zst', 'seforim.db');

  WizardForm.StatusLabel.Caption := 'מחלץ קטלוג אוצר החכמה...';
  WizardForm.StatusLabel.Update;
  ExtractBundledDatabase('otzar-HB_catalog.db.zst', 'otzar-HB_catalog.db');

  WizardForm.StatusLabel.Caption := 'מחלץ ספרי תלמוד בבלי...';
  WizardForm.StatusLabel.Update;
  ExtractBundledTarArchive('talmud_bavli_latest.tar.zst', 'תלמוד בבלי');

  WizardForm.ProgressGauge.Style := npbstNormal;
  WizardForm.ProgressGauge.Position := WizardForm.ProgressGauge.Max;

  if SelectedBooksPath <> '' then
  begin
    ForceDirectories(SelectedBooksPath);
    WriteLibraryPathToPrefs(SelectedBooksPath);
  end;

  // משיקים את אוצריא רק עכשיו — אחרי שהחילוץ הסתיים — כדי שלא תיפתח על ספרייה
  // ריקה. ExecAsOriginalUser מוריד הרשאות כמו דגל runasoriginaluser בהתקנה מורמת.
  ExecAsOriginalUser(ExpandConstant('{app}\{#MyAppExeName}'), '',
    ExpandConstant('{app}'), SW_SHOWNORMAL, ewNoWait, ResultCode);
end;

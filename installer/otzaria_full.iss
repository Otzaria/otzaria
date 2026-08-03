; המתקין המלא (FULL) של אוצריא — כולל ספריית הספרים המצורפת.
; שדרוג מגרסה 0.9.88 ומעלה מזוהה אוטומטית ומותקן ללא שאלות, עם חלון התקדמות.
; ההגדרות וקיצורי הדרך נשמרים, והספרייה מוחלפת בחבילה
; החדשה בנתיב הספרים הקיים של המשתמש. התקנה חדשה או שדרוג מגרסה ישנה
; מקבלים את האשף המלא (בחירת רכיבים, תיקיית ספרים וכו').
; עמוד "סוג ההתקנה" מציע: למשתמש הנוכחי (ברירת מחדל, ללא UAC), לכל
; המשתמשים (שיגור-מחדש מורם עם /ALLUSERS), והתקנה ניידת. בהתקנה ניידת
; נכתב portable.marker ליד ה-EXE, הספרייה מחולצת ל-otzaria_data\books
; בתוך תיקיית ההתקנה (הנתיב שהאפליקציה גוזרת בעצמה במצב נייד — אין צורך
; בכתיבת הגדרות), ואין שום רישום במערכת. הפרמטר /PORTABLE פותח את האשף
; במצב נייד גם כשמותקנת גרסה מודרנית (שאחרת הייתה משודרגת בשקט).

#define MyAppName "אוצריא"
#define MyAppVersion "0.9.96"
#define MyAppPublisher "sivan22"
#define MyAppURL "https://github.com/otzaria/otzaria"
#define MyAppExeName "otzaria.exe"

#ifdef IndexedSplitFull
  #ifndef IndexedReleaseTag
    #define IndexedReleaseTag MyAppVersion
  #endif
  #define IndexedArchiveName "otzaria-" + MyAppVersion + "-library-full-indexed.tar.zst"
  #define IndexedEmbeddedManifestName "indexed_library.manifest.json"
  #define IndexedReleaseBaseUrl "https://github.com/Otzaria/otzaria/releases/download/" + IndexedReleaseTag
#endif

[Setup]
; NOTE: The value of AppId uniquely identifies this application. Do not use the same AppId value in installers for other applications.
; (To generate a new GUID, click Tools | Generate GUID inside the IDE.)
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
OutputDir=.
#ifdef IndexedSplitFull
OutputBaseFilename=otzaria-{#MyAppVersion}-windows-full-indexed
#else
OutputBaseFilename=otzaria-{#MyAppVersion}-windows-full
#endif
SetupIconFile=white_sketch128x128.ico
; תמונת האשף בעמודי "ברוכים הבאים" ו"סיום" (אנכית, 164x314 + רזולוציות @2x/@3x ל-HiDPI)
WizardImageFile=wizard_large.bmp,wizard_large@2x.bmp,wizard_large@3x.bmp
; תמונה קטנה בפינת כל עמוד אחר (55x58 + רזולוציות גבוהות)
WizardSmallImageFile=wizard_small.bmp,wizard_small@2x.bmp,wizard_small@3x.bmp
Compression=lzma
SolidCompression=yes
; Disable compression for DLL files to prevent corruption
CompressionThreads=1
WizardStyle=modern
DisableDirPage=no
; התקנה ניידת אינה נרשמת במערכת — בלי uninstaller ובלי רשומה ב"הוספה או
; הסרה של תוכניות"; להסרה מוחקים את התיקייה.
Uninstallable=not IsPortableInstall
CreateUninstallRegKey=not IsPortableInstall
; ChangesEnvironment=yes נדרש כדי שעדכון ה-PATH ייכנס לתוקף מיד עבור
; תהליכים חדשים ללא צורך ב-logoff. שולח WM_SETTINGCHANGE.
ChangesEnvironment=yes
; לוג אוטומטי ל-%TEMP% של המשתמש המריץ — חיוני לאבחון התקנות שקטות שנכשלות בשטח.
SetupLogging=yes

[InstallDelete]
; ניקוי מסד הנתונים הישן של Isar שהוחלף על ידי hive_ce — מחיקה מכוונת בעת שדרוג.
Type: filesandordirs; Name: "{app}\default.isar";
; המסמן נכתב רק בהתקנת מנהל (ראה [INI]) והאפליקציה גוזרת ממנו את מיקום
; ברירת המחדל של הספרייה — מסמן ששרד מעבר להתקנת משתמש מפנה אותה ל-ProgramData.
Type: files; Name: "{app}\system_install.marker"; Check: (not IsAdminInstallMode) or IsPortableInstall
; במתקין המשובץ מוחקים לפני הפריסה; במתקין המפוצל מחליפים רק אחרי אימות וחילוץ מלא.
#ifndef IndexedSplitFull
Type: filesandordirs; Name: "{code:GetSelectedBooksPath}"
#endif

[Dirs]
; במצב נייד הנתונים יושבים ב-otzaria_data ליד ה-EXE — האפליקציה יוצרת אותה בעצמה.
Name: "{code:GetDataDir}"; Permissions: users-modify; Check: not IsPortableInstall
Name: "{code:GetDataDir}\books"; Permissions: users-modify; Check: not IsPortableInstall
Name: "{code:GetDataDir}\index"; Permissions: users-modify; Check: not IsPortableInstall

[Registry]
Root: HKA; Subkey: "Software\Classes\otzaria"; ValueType: string; ValueName: ""; ValueData: "URL:Otzaria Protocol"; Flags: uninsdeletekeyifempty; Check: not IsPortableInstall
Root: HKA; Subkey: "Software\Classes\otzaria"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""; Flags: uninsdeletevalue; Check: not IsPortableInstall
Root: HKA; Subkey: "Software\Classes\otzaria\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName}"; Flags: uninsdeletekeyifempty; Check: not IsPortableInstall
Root: HKA; Subkey: "Software\Classes\otzaria\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Flags: uninsdeletekeyifempty; Check: not IsPortableInstall
; הוספת {app} ל-PATH אוטומטית (מאפשר ‎`otzaria pack-plugin`‎ מהטרמינל):
; התקנת מנהל → PATH המערכתי; התקנת משתמש → PATH של המשתמש. ה-Check מונע
; כפילויות בהתקנה חוזרת; ההסרה מתבצעת ב-CurUninstallStepChanged (לא ניתן
; להשתמש ב-uninsdelete* על expandsz "מצטבר" כי הוא ידרוס את הערך כולו).
Root: HKLM; Subkey: "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"; ValueType: expandsz; ValueName: "Path"; ValueData: "{olddata};{app}"; Flags: preservestringtype; Check: ShouldAddToSystemPath
Root: HKCU; Subkey: "Environment"; ValueType: expandsz; ValueName: "Path"; ValueData: "{olddata};{app}"; Flags: preservestringtype; Check: ShouldAddToUserPath

[Languages]
Name: "hebrew"; MessagesFile: "compiler:Languages\Hebrew.isl"

[Code]

const
  // קבועי פריסה לדף "תכונות עיקריות" - Inno Setup לא תומך ב-const מקומי בתוך פרוצדורה.
  FEATURES_GAP_X = 14;
  FEATURES_GAP_Y = 8;
  FEATURES_LABEL_H = 18;
  UninstallRegKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{EEC4F712-CD05-4D15-A753-509E840A51A5}_is1';
  SystemEnvironmentKey = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment';
  UserEnvironmentKey = 'Environment';

var
  CompPage: TWizardPage;
  WV2Check: TCheckBox;
  WV2Label: TLabel;
  InstallWV2: Boolean;

  BooksPage: TWizardPage;
  BooksPathEdit: TEdit;
  BooksPathBrowseBtn: TButton;
  BooksWarnLabel: TLabel;
  SelectedBooksPath: String;

  ModePage: TWizardPage;
  CurrentUserModeRadio: TNewRadioButton;
  AllUsersModeRadio: TNewRadioButton;
  PortableModeRadio: TNewRadioButton;
  PortableMode: Boolean;
  // מסמן שהאשף נסגר לטובת שיגור-מחדש במצב התקנה אחר — הסגירה שקטה,
  // בלי שאלת האישור של ביטול התקנה.
  RelaunchingForModeChange: Boolean;
  RegularInstallDirDefault: String;
  PortableInstallDirDefault: String;

  FeaturesPage: TWizardPage;
  SlideshowImage: TBitmapImage;
  SlideshowTimerId: LongWord;
  SlideshowTimerCallback: LongWord;
  SlideshowIndex: Integer;

  // אם המשתמש בחר במהלך ההסרה למחוק גם את כל הנתונים והספרים, לא רק את
  // קבצי האפליקציה. ברירת המחדל False — נשמר כדי לא לאבד נתונים בעדכון
  // שקט (Inno Setup מריץ את ה-uninstaller הישן עם /SILENT).
  DeleteUserDataOnUninstall: Boolean;

#ifdef IndexedSplitFull
  IndexedDownloadPage: TDownloadWizardPage;
  IndexedManifestPath: String;
  IndexedPartsDir: String;
  IndexedPreparedArchivePath: String;
  IndexedArchiveName: String;
  IndexedArchiveHash: String;
  IndexedPartNames: TArrayOfString;
  IndexedPartHashes: TArrayOfString;
#endif

// משמש גם את Uninstallable/CreateUninstallRegKey וגם רשומות Check.
function IsPortableInstall(): Boolean;
begin
  Result := PortableMode;
end;

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

function CmdLineParamExists(const Value: String): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if CompareText(ParamStr(I), Value) = 0 then
    begin
      Result := True;
      exit;
    end;
end;

// Exec/ShellExec המובנות מסרבות להריץ את קובץ ה-Setup עצמו לפני תחילת ההתקנה;
// ייבוא ישיר של ה-API עוקף זאת, וכך ה-UAC מציג את מתקין אוצריא ולא את cmd.exe.
function ShellExecuteW(hwnd: HWND; lpOperation, lpFile, lpParameters,
  lpDirectory: String; nShowCmd: Integer): THandle;
  external 'ShellExecuteW@shell32.dll stdcall';

function RelaunchSetup(Verb, Params: String; ShowCmd: Integer; var ErrorCode: Integer): Boolean;
var
  InstanceHandle: THandle;
begin
  InstanceHandle :=
    ShellExecuteW(0, Verb, ExpandConstant('{srcexe}'), Params, '', ShowCmd);
  // ערך מעל 32 = הצלחה; אחרת זהו קוד שגיאת SE_ERR, נשמר לדיווח הכשל.
  Result := InstanceHandle > 32;
  if not Result then
    ErrorCode := InstanceHandle;
end;

function RelaunchSetupElevated(Params: String; ShowCmd: Integer; var ErrorCode: Integer): Boolean;
begin
  Result := RelaunchSetup('runas', Params, ShowCmd, ErrorCode);
end;

// מחזירה את תיקיית ההתקנה הקודמת. RequiresAdmin נקבע לפי מקור הזיהוי
// ובמקרי HKCU גם לפי הנתיב בפועל, כדי לבקש UAC לפני כשל בכתיבה.
function FindPreviousInstallDir(var RequiresAdmin: Boolean): String;
var
  InstallDir: String;
  LegacyDir: String;
begin
  RequiresAdmin := False;

  // HKLM64 = התקנה מערכתית קודמת ⇒ דורשת מנהל לשדרוג.
  if TryGetInstallDirFromRegistry(HKLM64, UninstallRegKey, InstallDir) then
  begin
    Result := InstallDir;
    RequiresAdmin := True;
    exit;
  end;

  // בדרך כלל HKCU = התקנת משתמש. אם הנתיב בפועל תחת Program Files,
  // מבקשים UAC מראש כדי לא ליפול לכשל כתיבה מאוחר יותר.
  if TryGetInstallDirFromRegistry(HKCU, UninstallRegKey, InstallDir) then
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

  // {autopf} בריצת non-admin מתפענח ל-%LocalAppData%\Programs (נתיב משתמש).
  // בריצת admin זה Program Files, אבל אז IsAdmin=True ב-InitializeSetup
  // ולא נכנסים לענף ההסלמה ממילא — כך ש-RequiresAdmin נשאר False בבטחה.
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
  // במצב נייד הספרייה תמיד בתוך תיקיית הנתונים הניידת שליד ה-EXE — הנתיב
  // שהאפליקציה גוזרת בעצמה במצב נייד, ולכן אין צורך בכתיבת הגדרות.
  if PortableMode then
    Result := ExpandConstant('{app}') + '\otzaria_data\books'
  else if SelectedBooksPath <> '' then
    Result := SelectedBooksPath
  else
    Result := GetDataDir('') + '\books';
end;

// חותך רכיב מספרי מתחילת S ומקדם אותה הלאה. תו שאינו ספרה או '.'
// (כמו '+' של מספר build) מסיים את הפירוק.
function NextVersionComponent(var S: String): Integer;
var
  i: Integer;
  Digits: String;
begin
  Digits := '';
  i := 1;
  while (i <= Length(S)) and (S[i] >= '0') and (S[i] <= '9') do
  begin
    Digits := Digits + S[i];
    i := i + 1;
  end;
  if (i <= Length(S)) and (S[i] = '.') then
    S := Copy(S, i + 1, Length(S))
  else
    S := '';
  Result := StrToIntDef(Digits, 0);
end;

function VersionAtLeast(VersionStr, MinimumStr: String): Boolean;
var
  A, B: Integer;
begin
  while (VersionStr <> '') or (MinimumStr <> '') do
  begin
    A := NextVersionComponent(VersionStr);
    B := NextVersionComponent(MinimumStr);
    if A <> B then
    begin
      Result := A > B;
      exit;
    end;
  end;
  Result := True;
end;

// גרסת ההתקנה הקודמת (DisplayVersion מרישום ה-uninstall), או '' אם אין.
function GetPreviousDisplayVersion(): String;
begin
  if RegQueryStringValue(HKLM64, UninstallRegKey, 'DisplayVersion', Result) and (Result <> '') then
    exit;
  if RegQueryStringValue(HKCU, UninstallRegKey, 'DisplayVersion', Result) and (Result <> '') then
    exit;
  Result := '';
end;

// שדרוג מגרסה 0.9.88 ומעלה — האשף מיותר: אין צורך באיפוס הגדרות, קיצורי
// הדרך הקיימים נשמרים, והספרייה מוחלפת בנתיב הספרים הקיים. מתקינים מיידית.
function IsUpgradeFromModernVersion(): Boolean;
var
  PreviousVersion: String;
begin
  PreviousVersion := GetPreviousDisplayVersion();
  Result := (PreviousVersion <> '') and VersionAtLeast(PreviousVersion, '0.9.88');
end;

// משמר את backups באיפוס הגדרות — כדי שקובצי גיבוי ישרדו ויאפשרו שחזור
// הערות/סימניות/נתוני תוספים דרך "שחזור מגיבוי". books נמחק כי מותקן מחדש.
procedure DelTreeExceptBackups(Path: String);
var
  FindRec: TFindRec;
  ChildPath: String;
begin
  if not DirExists(Path) then
    exit;

  if FindFirst(Path + '\*', FindRec) then
  begin
    try
      repeat
        if (FindRec.Name <> '.') and (FindRec.Name <> '..') then
        begin
          ChildPath := Path + '\' + FindRec.Name;

          if (FindRec.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
          begin
            if Lowercase(FindRec.Name) <> 'backups' then
            begin
              DelTreeExceptBackups(ChildPath);
              RemoveDir(ChildPath);
            end;
          end
          else
            DeleteFile(ChildPath);
        end;
      until not FindNext(FindRec);
    finally
      FindClose(FindRec);
    end;
  end;

  RemoveDir(Path);
end;

// ─── בדיקות רכיבי מערכת ───────────────────────────────────────────────────

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

procedure WriteStringPreferenceToPrefs(const PreferenceKey, Value: String);
var
  PrefsDir, PrefsFile, JsonContent, NewEntry: String;
  SharedPrefsKey, LegacyPrefsKey: String;
  KeyPos, ValueStart, ValueEnd, PairEnd, LastBrace, ExistingLength: Integer;
begin
  SharedPrefsKey := '"flutter.' + PreferenceKey + '":';
  LegacyPrefsKey := '"' + PreferenceKey + '":';
  PrefsDir := ExpandConstant('{userappdata}\otzaria');
  PrefsFile := PrefsDir + '\shared_preferences.json';

  ForceDirectories(PrefsDir);

  NewEntry := SharedPrefsKey + '"' + EscapeJsonString(Value) + '"';

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

// כותב את נתיב הספרייה, ובמתקין המאונדקס גם את האינדקס הצמוד שהותקן איתה.
procedure WriteLibraryPathToPrefs(const LibraryPath: String);
begin
  WriteStringPreferenceToPrefs('key-library-path', LibraryPath);
#ifdef IndexedSplitFull
  WriteStringPreferenceToPrefs('key-index-path',
    ExtractFileDir(LibraryPath) + '\index');
#endif
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

// ברירות מחדל להתקנה שקטה (אין דפי אשף לקבוע אותן). נתיב הספרים: הנתיב
// הקיים של המשתמש אם הוא מזוהה כתיקיית אוצריא — כך הספרייה מוחלפת במקומה
// ולא עוברת לנתיב ברירת המחדל; אחרת ברירת המחדל.
procedure InitializeSilentDefaults();
var
  CustomPath: String;
begin
  InstallWV2 := WebView2NeedsInstall;
  SelectedBooksPath := GetDataDir('') + '\books';
  CustomPath := GetCustomLibraryPath();
  if IsOtzariaBooksFolder(CustomPath) then
    SelectedBooksPath := CustomPath;
end;

function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
  PrivilegeFlag: String;
  Launched: Boolean;
  RequiresAdmin: Boolean;
  PreviousDir, DataPath, OldPath: String;
begin
  Result := True;

  // אתחול ברירות מחדל כבר עכשיו, כדי ש-GetSelectedBooksPath (שמשמש
  // ב-[InstallDelete]) יחזיר ערך תקין בכל מסלול ריצה.
  InstallWV2 := WebView2NeedsInstall;
  SelectedBooksPath := GetDataDir('') + '\books';

  if WizardSilent then
  begin
    InitializeSilentDefaults();
    // התקנה ניידת שקטה (‎/VERYSILENT /PORTABLE /DIR=...‎): /DIR חובה —
    // בלעדיו ברירת המחדל היא תיקיית ההתקנה הקיימת, וה-marker היה הופך
    // אותה לניידת.
    PortableMode := CmdLineParamExists('/PORTABLE') and
      (ExpandConstant('{param:DIR|}') <> '');
    exit;
  end;

  // כבר שוגרנו מחדש עם מצב התקנה מפורש — ממשיכים ישירות (מונע לולאת שיגור).
  if CmdLineParamExists('/ALLUSERS') or CmdLineParamExists('/CURRENTUSER') then
    exit;
  // ‎/PORTABLE — ישר לאשף במצב נייד: בלי שדרוג שקט (המשתמש רוצה עותק נייד,
  // לא עדכון של ההתקנה הקיימת) ובלי הסלמת הרשאות.
  if CmdLineParamExists('/PORTABLE') then
    exit;

  PreviousDir := FindPreviousInstallDir(RequiresAdmin);

  if IsUpgradeFromModernVersion() then
  begin
    // ‎/SILENT מדלג על האשף אך משאיר חלון התקדמות; בריצה השנייה
    // WizardSilent יהיה True והקוד הזה לא ירוץ שוב.
    if IsAdmin then
    begin
      PrivilegeFlag := '/ALLUSERS';
    end
    else if RequiresAdmin then
    begin
      // ההתקנה הקודמת בנתיב הדורש הרשאות מנהל. משגרים מחדש עם 'runas'
      // כדי לקבל UAC; המתקין המורם ירוץ עם /ALLUSERS.
      Launched := RelaunchSetupElevated(
        '/SILENT /SUPPRESSMSGBOXES /NORESTART /ALLUSERS',
        SW_SHOWNORMAL, ResultCode);

      if Launched then
      begin
        Result := False;
        exit;
      end;

      // אם גם השיגור המורם נכשל, המשתמש דחה את ה-UAC (ERROR_CANCELLED)
      // או שהייתה שגיאת מערכת. לא נופלים ל-/CURRENTUSER, כי ההתקנה
      // הייתה נכשלת בכתיבה לנתיב המוגן.
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

    Launched := RelaunchSetup('open',
         '/SILENT /SUPPRESSMSGBOXES /NORESTART ' + PrivilegeFlag,
         SW_SHOWNORMAL, ResultCode);

    if Launched then
    begin
      // השיגור הצליח — יוצאים מהריצה הנוכחית בשקט (Result := False
      // יוצא ללא הודעת ביטול), והעותק השקט ימשיך מכאן.
      Result := False;
      exit;
    end;

    // השיגור מחדש נכשל לחלוטין — ממשיכים בתהליך הנוכחי עם האשף המלא.
    exit;
  end;

  // התקנה חדשה או שדרוג מגרסה ישנה — אשף מלא.

  // בדיקה אם יש התקנה ישנה בנתיב העברי
  DataPath := GetDataDir('');
  OldPath := 'C:\אוצריא';
  if DirExists(OldPath) then
  begin
    if MsgBox('נמצאה התקנה ישנה ב-' + OldPath + #13#10 +
              'ספריית הספרים עוברת לנתיב חדש: ' + DataPath + #13#10#13#10 +
              'האם להעביר את הנתונים למיקום החדש?',
              mbConfirmation, MB_YESNO) = IDYES then
    begin
      MsgBox('לאחר ההתקנה, תוכל להעביר את הנתונים מ-' + OldPath + ' ל-' + DataPath, mbInformation, MB_OK);
    end;
  end;

  // הבחירה בין משתמש-נוכחי / כל-המשתמשים / ניידת נעשית בעמוד "סוג ההתקנה"
  // (כשהתהליך מורם העמוד מסומן מראש על כל-המשתמשים והשיגור-מחדש משם עובר
  // ללא UAC).
  if (not IsAdmin) and RequiresAdmin then
  begin
    // ההתקנה הקודמת (הישנה) בנתיב מוגן — אשף מורם עם UAC.
    Launched := RelaunchSetupElevated('/ALLUSERS', SW_SHOWNORMAL, ResultCode);
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
  end;
end;

// ─── עמוד סוג ההתקנה ───────────────────────────────────────────────────────

procedure CreateModePage();
var
  CurrentUserDesc, AllUsersDesc, PortableDesc: TNewStaticText;
begin
  ModePage := CreateCustomPage(FeaturesPage.ID,
    'סוג ההתקנה',
    'בחר עבור מי ואיך להתקין את אוצריא');

  CurrentUserModeRadio := TNewRadioButton.Create(ModePage);
  CurrentUserModeRadio.Parent := ModePage.Surface;
  CurrentUserModeRadio.Left := 0;
  CurrentUserModeRadio.Top := ScaleY(4);
  CurrentUserModeRadio.Width := ModePage.SurfaceWidth;
  CurrentUserModeRadio.Caption := 'התקנה למשתמש הנוכחי (מומלץ)';
  CurrentUserModeRadio.Checked := True;

  CurrentUserDesc := TNewStaticText.Create(ModePage);
  CurrentUserDesc.Parent := ModePage.Surface;
  CurrentUserDesc.Left := ScaleX(18);
  CurrentUserDesc.Top := CurrentUserModeRadio.Top + ScaleY(20);
  CurrentUserDesc.Width := ModePage.SurfaceWidth - ScaleX(18);
  CurrentUserDesc.AutoSize := False;
  CurrentUserDesc.WordWrap := True;
  CurrentUserDesc.Height := ScaleY(28);
  CurrentUserDesc.Caption :=
    'מותקנת בפרופיל המשתמש המחובר, ללא צורך בהרשאות מנהל.';

  AllUsersModeRadio := TNewRadioButton.Create(ModePage);
  AllUsersModeRadio.Parent := ModePage.Surface;
  AllUsersModeRadio.Left := 0;
  AllUsersModeRadio.Top := CurrentUserDesc.Top + CurrentUserDesc.Height + ScaleY(10);
  AllUsersModeRadio.Width := ModePage.SurfaceWidth;
  AllUsersModeRadio.Caption := 'התקנה לכל המשתמשים במחשב';

  AllUsersDesc := TNewStaticText.Create(ModePage);
  AllUsersDesc.Parent := ModePage.Surface;
  AllUsersDesc.Left := ScaleX(18);
  AllUsersDesc.Top := AllUsersModeRadio.Top + ScaleY(20);
  AllUsersDesc.Width := ModePage.SurfaceWidth - ScaleX(18);
  AllUsersDesc.AutoSize := False;
  AllUsersDesc.WordWrap := True;
  AllUsersDesc.Height := ScaleY(28);
  AllUsersDesc.Caption :=
    'מותקנת ב-Program Files וזמינה לכל חשבונות המשתמש (יידרש אישור מנהל).';

  PortableModeRadio := TNewRadioButton.Create(ModePage);
  PortableModeRadio.Parent := ModePage.Surface;
  PortableModeRadio.Left := 0;
  PortableModeRadio.Top := AllUsersDesc.Top + AllUsersDesc.Height + ScaleY(10);
  PortableModeRadio.Width := ModePage.SurfaceWidth;
  PortableModeRadio.Caption := 'התקנה ניידת';

  PortableDesc := TNewStaticText.Create(ModePage);
  PortableDesc.Parent := ModePage.Surface;
  PortableDesc.Left := ScaleX(18);
  PortableDesc.Top := PortableModeRadio.Top + ScaleY(20);
  PortableDesc.Width := ModePage.SurfaceWidth - ScaleX(18);
  PortableDesc.AutoSize := False;
  PortableDesc.WordWrap := True;
  PortableDesc.Height := ScaleY(58);
  PortableDesc.Caption :=
    'מתאימה לכונן חיצוני או דיסק-און-קי: בוחרים תיקייה, והתוכנה, הספרייה ' +
    'המצורפת וכל הנתונים (הגדרות, הערות) נשמרים בתוכה — אוצריא נודדת יחד ' +
    'עם הכונן. ללא קיצורי דרך ורישום במערכת; להסרה פשוט מוחקים את התיקייה.';
end;

// ─── בניית עמוד בחירת רכיבים ───────────────────────────────────────────────

procedure CreateComponentsPage;
var
  WV2Version: String;
  WV2Status: String;
  WV2Color: TColor;
  TopY: Integer;
  HeaderLabel: TLabel;
begin
  CompPage := CreateCustomPage(wpSelectDir,
    'בחירת רכיבי מערכת להתקנה',
    'בדיקת הרכיבים הנדרשים לאפליקציה');

  WV2Version := GetWebView2Version;

  // כותרת הסבר
  HeaderLabel := TLabel.Create(CompPage);
  HeaderLabel.Parent := CompPage.Surface;
  HeaderLabel.Left   := 0;
  HeaderLabel.Top    := 0;
  HeaderLabel.Width  := CompPage.SurfaceWidth;
  HeaderLabel.AutoSize := False;
  HeaderLabel.WordWrap := True;
  HeaderLabel.Caption :=
    'בדיקת רכיבי Microsoft הנדרשים לאוצריא.' + #13#10 +
    'בכתום: חסר — מומלץ להתקין.' + #13#10 +
    'בירוק: קיים — אין צורך בפעולה.';
  HeaderLabel.Height := ScaleY(60);  // 3 שורות קצרות, בלי עודף ריפוד

  TopY := HeaderLabel.Height + ScaleY(6);

  // ─── WebView2 Runtime ─────────────────────────────────────────────────────
  // הערה: Visual C++ Runtime כבר לא מותקן ע"י המתקין — ה-DLLs נארזים
  // app-local ליד otzaria.exe (ראה .github/workflows/build-and-announce.yml
  // והשלב "Bundle latest VC++ Redistributable runtime DLLs"), כך שאין
  // צורך לבדוק / להתקין אותו בזמן ההתקנה. המתקין FULL מציג עכשיו רק
  // את ה-WebView2 בדף בחירת רכיבי המערכת.
  WV2Check := TCheckBox.Create(CompPage);
  WV2Check.Parent  := CompPage.Surface;
  WV2Check.Left    := 0;
  WV2Check.Top     := TopY;
  WV2Check.Width   := CompPage.SurfaceWidth;
  WV2Check.Height  := ScaleY(20);
  WV2Check.Caption := 'Microsoft WebView2 Runtime';

  // WebView2 אינו חובה — משמש רק למערכת הפלאגינים (לא לקריאה/חיפוש/סימניות)
  if WV2Version = '' then
  begin
    WV2Status := '⚠ חסר — מומלץ להתקין. ללא רכיב זה מערכת הפלאגינים לא תפעל,' +
                 ' אך שאר האפליקציה תעבוד כרגיל.';
    WV2Color  := $007FFF;  // כתום — אזהרה, לא שגיאה ($BBGGRR: B=00, G=7F, R=FF)
    WV2Check.Checked := True;
    WV2Check.Enabled := True;  // אופציונלי — ניתן לבטל
  end
  else
  begin
    WV2Status := '✓ קיים (גרסה: ' + WV2Version + ') — לא נדרשת פעולה.';
    WV2Color  := $006400;
    WV2Check.Checked := False;
    WV2Check.Enabled := False;  // קיים — נעול כדי למנוע התקנה מיותרת
  end;

  WV2Label := TLabel.Create(CompPage);
  WV2Label.Parent   := CompPage.Surface;
  WV2Label.Left     := ScaleX(20);
  WV2Label.Top      := TopY + ScaleY(18);
  WV2Label.Width    := CompPage.SurfaceWidth - ScaleX(20);
  WV2Label.AutoSize := False;
  WV2Label.WordWrap := True;
  WV2Label.Caption  := WV2Status;
  WV2Label.Font.Color := WV2Color;
  WV2Label.Height   := ScaleY(34);
end;

// ─── דף בחירת תיקיית הספרים ─────────────────────────────────────────────────

procedure UpdateBooksWarning(const Path: String);
begin
  if BooksWarnLabel = nil then exit;
  if DirExists(Path) then
    BooksWarnLabel.Caption :=
      '⚠ שים לב: תיקייה קיימת כבר בנתיב זה.' + #13#10 +
      'התקנה זו תמחק את תוכנה ותחליף בספרים החדשים שבחבילה.'
  else
    BooksWarnLabel.Caption := '';
end;

procedure BrowseBooksFolder(Sender: TObject);
var
  Dir: String;
begin
  Dir := BooksPathEdit.Text;
  if BrowseForFolder('בחר תיקיית ספרים:', Dir, False) then
  begin
    BooksPathEdit.Text := Dir;
    UpdateBooksWarning(Dir);
  end;
end;

procedure CreateBooksPage;
var
  DefaultPath, CustomPath: String;
  DescLabel, PathLabel: TLabel;
begin
  BooksPage := CreateCustomPage(CompPage.ID,
    'תיקיית הספרים',
    'בחר היכן יישמרו ספרי הספרייה');

  // ספרייה קיימת מנצחת את ברירת המחדל (כמו ב-InitializeSilentDefaults): אחרת
  // מעבר בין מנהל למשתמש מזיז את מיקום החילוץ בעוד האפליקציה קוראת מהישן.
  DefaultPath := GetDataDir('') + '\books';
  CustomPath := GetCustomLibraryPath();
  if IsOtzariaBooksFolder(CustomPath) then
    DefaultPath := CustomPath;
  SelectedBooksPath := DefaultPath;

  DescLabel := TLabel.Create(BooksPage);
  DescLabel.Parent   := BooksPage.Surface;
  DescLabel.Left     := 0;
  DescLabel.Top      := 0;
  DescLabel.Width    := BooksPage.SurfaceWidth;
  DescLabel.AutoSize := False;
  DescLabel.WordWrap := True;
  DescLabel.Caption  :=
    'כאן יישמרו קבצי הספרים שמגיעים עם ההתקנה וכל ספר שתוסיף בעתיד.' + #13#10 +
    'הנתיב שתבחר יוגדר אוטומטית בהגדרות התוכנה.';
  DescLabel.Height := ScaleY(42);  // 2 שורות צמודות יותר

  PathLabel := TLabel.Create(BooksPage);
  PathLabel.Parent   := BooksPage.Surface;
  PathLabel.Left     := 0;
  PathLabel.Top      := DescLabel.Height + ScaleY(2);
  PathLabel.Width    := BooksPage.SurfaceWidth;
  PathLabel.AutoSize := False;
  PathLabel.Caption  := 'נתיב תיקיית הספרים:';
  PathLabel.Height   := ScaleY(20);

  BooksPathEdit := TEdit.Create(BooksPage);
  BooksPathEdit.Parent := BooksPage.Surface;
  BooksPathEdit.Left   := 0;
  BooksPathEdit.Top    := PathLabel.Top + ScaleY(26);
  BooksPathEdit.Width  := BooksPage.SurfaceWidth - ScaleX(84);
  BooksPathEdit.Height := ScaleY(22);
  BooksPathEdit.Text   := DefaultPath;

  BooksPathBrowseBtn := TButton.Create(BooksPage);
  BooksPathBrowseBtn.Parent  := BooksPage.Surface;
  BooksPathBrowseBtn.Left    := BooksPage.SurfaceWidth - ScaleX(78);
  BooksPathBrowseBtn.Top     := BooksPathEdit.Top - ScaleY(1);
  BooksPathBrowseBtn.Width   := ScaleX(78);
  BooksPathBrowseBtn.Height  := ScaleY(23);
  BooksPathBrowseBtn.Caption := 'עיון...';
  BooksPathBrowseBtn.OnClick := @BrowseBooksFolder;

  BooksWarnLabel := TLabel.Create(BooksPage);
  BooksWarnLabel.Parent     := BooksPage.Surface;
  BooksWarnLabel.Left       := 0;
  BooksWarnLabel.Top        := BooksPathEdit.Top + BooksPathEdit.Height + ScaleY(8);
  BooksWarnLabel.Width      := BooksPage.SurfaceWidth;
  BooksWarnLabel.AutoSize   := False;
  BooksWarnLabel.WordWrap   := True;
  BooksWarnLabel.Height     := ScaleY(42);
  BooksWarnLabel.Font.Color := clRed;

  UpdateBooksWarning(DefaultPath);
end;

procedure CreateFeaturesPage();
var
  i, col, row: Integer;
  thumbW, thumbH, cellH, x, y, totalH, startY: Integer;
  img: TBitmapImage;
  lbl: TNewStaticText;
  files: array[0..3] of String;
  captions: array[0..3] of String;
begin
  FeaturesPage := CreateCustomPage(wpWelcome,
    'תכונות עיקריות באוצריא',
    'הצצה למה שמחכה לכם בתוכנה');

  files[0] := 'feature1.bmp';  captions[0] := 'ספר עם מפרשים';
  files[1] := 'feature2.bmp';  captions[1] := 'לוח שנה';
  files[2] := 'feature3.bmp';  captions[2] := 'ספרי PDF';
  files[3] := 'feature4.bmp';  captions[3] := 'חיפוש מתקדם';

  // יחס תמונה 210/400. גודל דינמי לפי שטח העמוד.
  thumbW := (FeaturesPage.SurfaceWidth - FEATURES_GAP_X) div 2;
  thumbH := (thumbW * 210) div 400;
  cellH := thumbH + FEATURES_LABEL_H;
  totalH := 2 * cellH + FEATURES_GAP_Y;
  startY := (FeaturesPage.SurfaceHeight - totalH) div 2;
  if startY < 0 then startY := 0;

  for i := 0 to 3 do
  begin
    col := i mod 2;
    row := i div 2;
    x := col * (thumbW + FEATURES_GAP_X);
    y := startY + row * (cellH + FEATURES_GAP_Y);

    ExtractTemporaryFile(files[i]);
    img := TBitmapImage.Create(FeaturesPage);
    img.Parent := FeaturesPage.Surface;
    img.Stretch := True;
    img.Left := x;
    img.Top := y;
    img.Width := thumbW;
    img.Height := thumbH;
    img.Bitmap.LoadFromFile(ExpandConstant('{tmp}\' + files[i]));

    lbl := TNewStaticText.Create(FeaturesPage);
    lbl.Parent := FeaturesPage.Surface;
    lbl.Left := x;
    lbl.Top := y + thumbH + 2;
    lbl.Width := thumbW;
    lbl.Height := FEATURES_LABEL_H;
    lbl.Alignment := taCenter;
    lbl.Caption := captions[i];
  end;
end;

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
#ifdef IndexedSplitFull
  IndexedDownloadPage := CreateDownloadPage(
    'מוריד ספרייה מלאה עם אינדקס מוכן',
    'הקבצים החסרים יורדו ויאומתו לפני תחילת ההתקנה', nil);
  IndexedDownloadPage.ShowBaseNameInsteadOfUrl := True;
#endif
  if WizardSilent then
    // אין דפי אשף בהתקנה שקטה — רק ברירות המחדל (נקבעות גם ב-InitializeSetup).
    InitializeSilentDefaults()
  else
  begin
    InstallWV2 := WebView2NeedsInstall;
    CreateFeaturesPage;
    CreateModePage;
    CreateComponentsPage;
    CreateBooksPage;

    RegularInstallDirDefault := WizardForm.DirEdit.Text;
    PortableInstallDirDefault := ExpandConstant('{userdocs}\OtzariaPortable');

    // בחירה מוקדמת בעמוד סוג ההתקנה: ‎/PORTABLE — מצב נייד; ריצה במצב מנהל
    // (שיגור-מחדש עם /ALLUSERS) או תהליך מורם — לכל המשתמשים.
    // ‎/CURRENTUSER = שיגור-מחדש מתהליך מורם שבחר במפורש התקנת משתמש.
    if CmdLineParamExists('/PORTABLE') then
      PortableModeRadio.Checked := True
    else if IsAdminInstallMode or
      (IsAdmin and not CmdLineParamExists('/CURRENTUSER')) then
      AllUsersModeRadio.Checked := True;
  end;
  InitializeSlideshow;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if not PortableMode then
    exit;
  // במצב נייד: אין קיצורי דרך/איפוס (עמוד המשימות), והספרייה תמיד בתוך
  // התיקייה הניידת (עמוד בחירת תיקיית הספרים).
  Result := (PageID = wpSelectTasks) or
    ((BooksPage <> nil) and (PageID = BooksPage.ID));
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

#ifdef IndexedSplitFull
function PrepareIndexedLibrary(): Boolean; forward;
#endif

// שמירת בחירות בלחיצת "הבא". בעמוד סוג ההתקנה: קיבוע המצב, התאמת ברירת
// המחדל של תיקיית היעד, ובמעבר בין משתמש-נוכחי לכל-המשתמשים — שיגור-מחדש
// במצב ההתקנה המתאים (מצב ההתקנה של Inno נקבע בעליית התהליך).
// בהתקנה שקטה Inno "מדפדף" בין העמודים ומפעיל גם את הפונקציה הזו — שם
// אסור לגעת בכלום: המצב כבר נקבע ב-InitializeSetup ו-/DIR חייב להישמר.
function NextButtonClick(CurPageID: Integer): Boolean;
var
  ResultCode: Integer;
  Launched: Boolean;
begin
  Result := True;
  if WizardSilent then
  begin
#ifdef IndexedSplitFull
    if CurPageID = wpReady then
      Result := PrepareIndexedLibrary();
#endif
    exit;
  end;

  if (ModePage <> nil) and (CurPageID = ModePage.ID) then
  begin
    PortableMode := PortableModeRadio.Checked;

    // התאמת ברירת המחדל של תיקיית היעד בלי לדרוס נתיב שהמשתמש הקליד בעצמו.
    if PortableMode and (WizardForm.DirEdit.Text = RegularInstallDirDefault) then
      WizardForm.DirEdit.Text := PortableInstallDirDefault
    else if (not PortableMode) and (WizardForm.DirEdit.Text = PortableInstallDirDefault) then
      WizardForm.DirEdit.Text := RegularInstallDirDefault;

    // התקנה ניידת אדישה למצב ההתקנה — כל מה שתלוי-מצב ממילא מנוטרל בה.
    if PortableMode then
      exit;

    if AllUsersModeRadio.Checked and (not IsAdminInstallMode) then
    begin
      if IsAdmin then
        // התהליך כבר מורם אבל במצב משתמש — שיגור-מחדש עם /ALLUSERS, בלי UAC.
        Launched := RelaunchSetup('open', '/ALLUSERS', SW_SHOWNORMAL, ResultCode)
      else
        Launched := RelaunchSetupElevated('/ALLUSERS', SW_SHOWNORMAL, ResultCode);

      if Launched then
      begin
        RelaunchingForModeChange := True;
        WizardForm.Close;
      end
      else
        MsgBox('להתקנה לכל המשתמשים נדרש אישור הרשאות מנהל.' + #13#10 +
               'ניתן לבחור "התקנה למשתמש הנוכחי" ולהמשיך ללא הרשאות.',
               mbError, MB_OK);
      Result := False;
      exit;
    end;

    if CurrentUserModeRadio.Checked and IsAdminInstallMode then
    begin
      // התהליך כבר במצב מנהל — חזרה להתקנת משתמש דורשת שיגור-מחדש.
      Launched := RelaunchSetup('open', '/CURRENTUSER', SW_SHOWNORMAL, ResultCode);
      if Launched then
      begin
        RelaunchingForModeChange := True;
        WizardForm.Close;
      end
      else
        MsgBox('לא ניתן היה לעבור להתקנה למשתמש הנוכחי.', mbError, MB_OK);
      Result := False;
    end;
    exit;
  end;

  if (CompPage <> nil) and (CurPageID = CompPage.ID) then
  begin
    InstallWV2 := WV2Check.Checked;
  end;
  if (BooksPage <> nil) and (CurPageID = BooksPage.ID) then
  begin
    SelectedBooksPath := BooksPathEdit.Text;
    if SelectedBooksPath = '' then
    begin
      MsgBox('יש לבחור נתיב לתיקיית הספרים.', mbError, MB_OK);
      Result := False;
    end;
  end;
#ifdef IndexedSplitFull
  if (CurPageID = wpReady) and Result then
    Result := PrepareIndexedLibrary();
#endif
end;

procedure CancelButtonClick(CurPageID: Integer; var Cancel, Confirm: Boolean);
begin
  // סגירה לטובת שיגור-מחדש במצב אחר — בלי שאלת "האם לבטל את ההתקנה?".
  if RelaunchingForModeChange then
    Confirm := False;
end;

// מריץ קובץ הרצה ולוכד את פלט ה-stderr/stdout שלו, כדי שבמקרה כשל
// נוכל להציג את הודעת השגיאה האמיתית (למשל "אין מקום בדיסק" / "הקובץ נעול")
// במקום קוד יציאה אטום כמו "קוד יציאה: 1".
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
      CapturedOutput := CapturedOutput + Output.StdErr[I] + #13#10;
  for I := 0 to GetArrayLength(Output.StdOut) - 1 do
    if Trim(Output.StdOut[I]) <> '' then
      CapturedOutput := CapturedOutput + Output.StdOut[I] + #13#10;
end;

#ifdef IndexedSplitFull
function ParseIndexedManifestLine(const Line, ExpectedKind: String;
  var FileName, FileHash: String): Boolean;
var
  FirstSeparator, SecondSeparator: Integer;
begin
  Result := False;
  FirstSeparator := Pos('|', Line);
  if FirstSeparator = 0 then
    exit;
  SecondSeparator := Pos('|', Copy(Line, FirstSeparator + 1, Length(Line)));
  if SecondSeparator = 0 then
    exit;
  SecondSeparator := SecondSeparator + FirstSeparator;

  if Copy(Line, 1, FirstSeparator - 1) <> ExpectedKind then
    exit;
  FileName := Copy(Line, FirstSeparator + 1,
    SecondSeparator - FirstSeparator - 1);
  FileHash := Copy(Line, SecondSeparator + 1, Length(Line));
  Result := (FileName <> '') and (Length(FileHash) = 64);
end;

function ReadIndexedManifest(const ManifestPath: String): Boolean;
var
  PowerShellPath, ParserPath, OutputPath, Params, CapturedOutput: String;
  Lines: TArrayOfString;
  ResultCode, I: Integer;
begin
  Result := False;
  ExtractTemporaryFile('read_indexed_library_manifest.ps1');
  PowerShellPath := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  ParserPath := ExpandConstant('{tmp}\read_indexed_library_manifest.ps1');
  OutputPath := ExpandConstant('{tmp}\indexed-library-manifest.txt');
  DeleteFile(OutputPath);
  Params := '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
    ParserPath + '" -ManifestPath "' + ManifestPath + '" -OutputPath "' +
    OutputPath + '"';

  if (not RunAndCaptureErrors(PowerShellPath, Params, ResultCode,
      CapturedOutput)) or (ResultCode <> 0) then
  begin
    Log('Indexed manifest parsing failed: ' + CapturedOutput);
    exit;
  end;
  if (not LoadStringsFromFile(OutputPath, Lines)) or
    (GetArrayLength(Lines) < 2) then
  begin
    Log('Indexed manifest parser returned no parts');
    exit;
  end;
  if not ParseIndexedManifestLine(Lines[0], 'archive', IndexedArchiveName,
      IndexedArchiveHash) then
    exit;
  if CompareText(IndexedArchiveName, '{#IndexedArchiveName}') <> 0 then
  begin
    Log('Unexpected indexed archive name: ' + IndexedArchiveName);
    exit;
  end;

  SetArrayLength(IndexedPartNames, GetArrayLength(Lines) - 1);
  SetArrayLength(IndexedPartHashes, GetArrayLength(Lines) - 1);
  for I := 1 to GetArrayLength(Lines) - 1 do
    if not ParseIndexedManifestLine(Lines[I], 'part',
      IndexedPartNames[I - 1], IndexedPartHashes[I - 1]) then
      exit;
  Result := True;
end;

function LocalIndexedPartsAreComplete(const PartsDir: String): Boolean;
var
  I: Integer;
  PartPath: String;
begin
  Result := False;
  for I := 0 to GetArrayLength(IndexedPartNames) - 1 do
  begin
    PartPath := AddBackslash(PartsDir) + IndexedPartNames[I];
    if not FileExists(PartPath) then
    begin
      Log('Local indexed part is missing: ' + PartPath);
      exit;
    end;
  end;
  Result := True;
end;

function DownloadIndexedParts(): Boolean;
var
  I: Integer;
  ErrorMessage: String;
begin
  Result := False;
  IndexedDownloadPage.Clear;
  for I := 0 to GetArrayLength(IndexedPartNames) - 1 do
    IndexedDownloadPage.Add(
      '{#IndexedReleaseBaseUrl}/' + IndexedPartNames[I],
      IndexedPartNames[I], IndexedPartHashes[I]);

  IndexedDownloadPage.Show;
  try
    try
      IndexedDownloadPage.Download;
      IndexedPartsDir := ExpandConstant('{tmp}');
      Result := True;
    except
      if IndexedDownloadPage.AbortedByUser then
        ErrorMessage := 'ההורדה בוטלה.'
      else
        ErrorMessage := GetExceptionMessage;
      Log('Indexed library download failed: ' + ErrorMessage);
      SuppressibleMsgBox('הורדת הספרייה המלאה נכשלה.' +
        #13#10#13#10 + ErrorMessage, mbCriticalError, MB_OK, IDOK);
    end;
  finally
    IndexedDownloadPage.Hide;
  end;
end;

function AssembleIndexedArchive(): Boolean;
var
  PowerShellPath, AssemblerPath, Params, CapturedOutput: String;
  ResultCode: Integer;
begin
  Result := False;
  ExtractTemporaryFile('assemble_split_asset.ps1');
  PowerShellPath := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  AssemblerPath := ExpandConstant('{tmp}\assemble_split_asset.ps1');
  IndexedPreparedArchivePath := ExpandConstant('{tmp}\') + IndexedArchiveName;
  DeleteFile(IndexedPreparedArchivePath);
  Params := '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
    AssemblerPath + '" "' + IndexedManifestPath + '" "' +
    IndexedPreparedArchivePath + '" "' + IndexedPartsDir + '"';

  WizardForm.StatusLabel.Caption := 'מרכיב ומאמת את ארכיון הספרייה...';
  if (not RunAndCaptureErrors(PowerShellPath, Params, ResultCode,
      CapturedOutput)) or (ResultCode <> 0) then
  begin
    Log('Indexed archive assembly failed: ' + CapturedOutput);
    DeleteFile(IndexedPreparedArchivePath);
    exit;
  end;
  Result := True;
end;

function PrepareIndexedLibrary(): Boolean;
var
  SourceDir: String;
  UsingLocalParts: Boolean;
begin
  Result := False;
  if (IndexedPreparedArchivePath <> '') and
    FileExists(IndexedPreparedArchivePath) then
  begin
    Result := True;
    exit;
  end;

  SourceDir := ExtractFileDir(ExpandConstant('{srcexe}'));
  ExtractTemporaryFile('{#IndexedEmbeddedManifestName}');
  IndexedManifestPath := ExpandConstant(
    '{tmp}\{#IndexedEmbeddedManifestName}');

  if not ReadIndexedManifest(IndexedManifestPath) then
  begin
    SuppressibleMsgBox('קובץ רשימת חלקי הספרייה אינו תקין.',
      mbCriticalError, MB_OK, IDOK);
    exit;
  end;

  UsingLocalParts := LocalIndexedPartsAreComplete(SourceDir);
  if UsingLocalParts then
  begin
    IndexedPartsDir := SourceDir;
    Log('Using verified indexed library parts next to the installer');
  end
  else
  begin
    if not DownloadIndexedParts() then
      exit;
  end;

  if not AssembleIndexedArchive() then
  begin
    SuppressibleMsgBox('אימות והרכבת ארכיון הספרייה נכשלו.',
      mbCriticalError, MB_OK, IDOK);
    exit;
  end;
  Result := True;
end;
#endif

// ממפה מחרוזות שגיאה נפוצות מ-zstd/7za (תמיד באנגלית) להסבר קצר בעברית.
// מחזיר מחרוזת ריקה אם לא זוהה דפוס מוכר - אז מוצג רק הפלט הגולמי.
function FriendlyErrorHint(const ErrOutput: String): String;
var
  LowerOutput: String;
begin
  LowerOutput := Lowercase(ErrOutput);
  Result := '';
  if Pos('no space left on device', LowerOutput) > 0 then
    Result := 'אין מספיק מקום פנוי בכונן. פנה מקום ונסה להתקין שוב.'
  else if Pos('permission denied', LowerOutput) > 0 then
    Result := 'אין הרשאה לכתוב לנתיב היעד. נסה להריץ את ההתקנה כמנהל או לבחור מיקום התקנה אחר.'
  else if Pos('sharing violation', LowerOutput) > 0 then
    Result := 'קובץ היעד נעול על ידי תהליך אחר. סגור את אוצריא ותוכנות אחרות שעשויות להשתמש בקבצים ונסה שוב.';
end;

procedure ExtractBundledDatabase(const ArchiveName, DatabaseName: String);
var
  ArchivePath, DatabasePath, ZstdPath, Params, ErrOutput, Hint: String;
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
    // בהתקנה שקטה MsgBox מדוכא (/SUPPRESSMSGBOXES) — ה-Log הוא הפידבק היחיד.
    Log('zstd database extraction failed (' + IntToStr(ResultCode) + '): ' + ErrOutput);
    Hint := FriendlyErrorHint(ErrOutput);
    if Hint <> '' then Hint := #13#10#13#10 + Hint;
    MsgBox('חילוץ מסד הנתונים נכשל. קוד יציאה: ' + IntToStr(ResultCode)
      + Hint + #13#10#13#10 + ErrOutput, mbCriticalError, MB_OK);
    Abort;
  end;

  DeleteFile(ArchivePath);
end;

procedure ExtractBundledTarArchive(const ArchiveName, TargetDirName: String);
var
  ArchivePath, TarPath, ParentDir, TargetDir, ZstdPath, SevenZipPath, Params, ErrOutput, Hint: String;
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
    Log('zstd PDF archive extraction failed (' + IntToStr(ResultCode) + '): ' + ErrOutput);
    Hint := FriendlyErrorHint(ErrOutput);
    if Hint <> '' then Hint := #13#10#13#10 + Hint;
    MsgBox('חילוץ ארכיון ה-PDF נכשל. קוד יציאה: ' + IntToStr(ResultCode)
      + Hint + #13#10#13#10 + ErrOutput, mbCriticalError, MB_OK);
    Abort;
  end;

  Params := 'x -y "' + TarPath + '" "-o' + ParentDir + '"';
  if (not RunAndCaptureErrors(SevenZipPath, Params, ResultCode, ErrOutput)) or
     (ResultCode <> 0) then
  begin
    Log('7za PDF archive extraction failed (' + IntToStr(ResultCode) + '): ' + ErrOutput);
    Hint := FriendlyErrorHint(ErrOutput);
    if Hint <> '' then Hint := #13#10#13#10 + Hint;
    MsgBox('פתיחת ארכיון ה-PDF נכשלה. קוד יציאה: ' + IntToStr(ResultCode)
      + Hint + #13#10#13#10 + ErrOutput, mbCriticalError, MB_OK);
    Abort;
  end;

  DeleteFile(TarPath);
  DeleteFile(ArchivePath);
end;

#ifdef IndexedSplitFull
procedure ExtractIndexedLibraryArchive();
var
  TarPath, LibraryRoot, StagingRoot, PackageRoot: String;
  SourceBooks, SourceIndex, TargetIndex, BooksBackup, IndexBackup: String;
  ZstdPath, SevenZipPath, Params, ErrOutput, Hint: String;
  ResultCode: Integer;
  BooksBackedUp, IndexBackedUp, NewBooksMoved: Boolean;
begin
  TarPath := ExpandConstant('{tmp}\otzaria-indexed-library.tar');
  LibraryRoot := ExtractFileDir(SelectedBooksPath);
  StagingRoot := LibraryRoot + '\.otzaria-indexed-install';
  PackageRoot := StagingRoot + '\otzaria-library-full-indexed';
  SourceBooks := PackageRoot + '\books';
  SourceIndex := PackageRoot + '\index';
  TargetIndex := LibraryRoot + '\index';
  BooksBackup := LibraryRoot + '\.otzaria-books-backup';
  IndexBackup := LibraryRoot + '\.otzaria-index-backup';
  ZstdPath := ExpandConstant('{tmp}\zstd.exe');
  SevenZipPath := ExpandConstant('{tmp}\7za.exe');

  ForceDirectories(LibraryRoot);
  DelTree(StagingRoot, True, True, True);
  DeleteFile(TarPath);
  ForceDirectories(StagingRoot);

  Params := '-d -f -T0 "' + IndexedPreparedArchivePath + '" -o "' +
    TarPath + '"';
  if (not RunAndCaptureErrors(ZstdPath, Params, ResultCode, ErrOutput)) or
    (ResultCode <> 0) then
  begin
    Hint := FriendlyErrorHint(ErrOutput);
    if Hint <> '' then Hint := #13#10#13#10 + Hint;
    MsgBox('פתיחת ארכיון הספרייה נכשלה.' + Hint + #13#10#13#10 +
      ErrOutput, mbCriticalError, MB_OK);
    Abort;
  end;

  Params := 'x -y "' + TarPath + '" "-o' + StagingRoot + '"';
  if (not RunAndCaptureErrors(SevenZipPath, Params, ResultCode, ErrOutput)) or
    (ResultCode <> 0) then
  begin
    Hint := FriendlyErrorHint(ErrOutput);
    if Hint <> '' then Hint := #13#10#13#10 + Hint;
    MsgBox('חילוץ הספרייה והאינדקס נכשל.' + Hint + #13#10#13#10 +
      ErrOutput, mbCriticalError, MB_OK);
    Abort;
  end;

  if (not FileExists(SourceBooks + '\seforim.db')) or
    (not FileExists(SourceIndex + '\.otzaria_prebuilt_index')) then
  begin
    Log('Indexed package is missing its database or index marker');
    MsgBox('מבנה חבילת הספרייה אינו תקין.', mbCriticalError, MB_OK);
    Abort;
  end;

  DelTree(BooksBackup, True, True, True);
  DelTree(IndexBackup, True, True, True);
  BooksBackedUp := (not DirExists(SelectedBooksPath)) or
    RenameFile(SelectedBooksPath, BooksBackup);
  if not BooksBackedUp then
  begin
    MsgBox('לא ניתן להחליף את תיקיית הספרים הקיימת. ודא שאוצריא סגורה.',
      mbCriticalError, MB_OK);
    Abort;
  end;
  IndexBackedUp := (not DirExists(TargetIndex)) or
    RenameFile(TargetIndex, IndexBackup);
  if not IndexBackedUp then
  begin
    if DirExists(BooksBackup) then
      RenameFile(BooksBackup, SelectedBooksPath);
    MsgBox('לא ניתן להחליף את תיקיית האינדקס הקיימת. ודא שאוצריא סגורה.',
      mbCriticalError, MB_OK);
    Abort;
  end;

  NewBooksMoved := RenameFile(SourceBooks, SelectedBooksPath);
  if (not NewBooksMoved) or (not RenameFile(SourceIndex, TargetIndex)) then
  begin
    if NewBooksMoved then
      DelTree(SelectedBooksPath, True, True, True);
    if DirExists(TargetIndex) then
      DelTree(TargetIndex, True, True, True);
    if DirExists(BooksBackup) then
      RenameFile(BooksBackup, SelectedBooksPath);
    if DirExists(IndexBackup) then
      RenameFile(IndexBackup, TargetIndex);
    MsgBox('העברת הספרייה למיקום שנבחר נכשלה.', mbCriticalError, MB_OK);
    Abort;
  end;

  DelTree(BooksBackup, True, True, True);
  DelTree(IndexBackup, True, True, True);
  DelTree(StagingRoot, True, True, True);
  DeleteFile(TarPath);
  DeleteFile(IndexedPreparedArchivePath);
end;
#endif

// ─── ניהול PATH ─────────────────────────────────────────────────────────────

// בודק האם SearchPath כבר נמצא בערך ה-Path שבמפתח הנתון. מטפל גם בגרסה
// עם backslash סופי. ההשוואה case-insensitive כי Windows מתייחס ל-PATH ככזה.
function PathValueContains(RootKey: Integer; const SubKey, SearchPath: String): Boolean;
var
  CurrentPath: String;
  Needle1, Needle2, Haystack: String;
begin
  Result := False;
  if not RegQueryStringValue(RootKey, SubKey, 'Path', CurrentPath) then
    exit;

  Haystack  := ';' + Lowercase(CurrentPath) + ';';
  Needle1   := ';' + Lowercase(SearchPath) + ';';
  Needle2   := ';' + Lowercase(SearchPath) + '\;';
  Result := (Pos(Needle1, Haystack) > 0) or (Pos(Needle2, Haystack) > 0);
end;

function ShouldAddToSystemPath(): Boolean;
begin
  Result := (not PortableMode) and IsAdminInstallMode and
    (not PathValueContains(HKLM, SystemEnvironmentKey, ExpandConstant('{app}')));
end;

function ShouldAddToUserPath(): Boolean;
begin
  Result := (not PortableMode) and (not IsAdminInstallMode) and
    (not PathValueContains(HKCU, UserEnvironmentKey, ExpandConstant('{app}')));
end;

// מסיר את PathToRemove מערך ה-Path שבמפתח הנתון (ב-uninstall). שומר את
// שאר הערך כמו שהוא. מטפל בשני הוריאנטים — עם וללא backslash סופי —
// **בנפרד**, כדי שכפילות היסטורית (גם 'C:\app' וגם 'C:\app\') תוסר
// במלואה. גם מסיר כל מופע חוזר, לא רק את הראשון.
procedure RemoveAppFromPathValue(RootKey: Integer; const SubKey, PathToRemove: String);
var
  CurrentPath, LowerCurrent: String;
  Needles: array[0..1] of String;
  LowerNeedle: String;
  P, i: Integer;
  Changed: Boolean;
begin
  if not RegQueryStringValue(RootKey, SubKey, 'Path', CurrentPath) then
    exit;

  Changed := False;
  // נורמליזציה: עוטפים ב-';...' כדי לטפל גם בקצוות.
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

  // הסרה של ה-';' שעטפנו בהתחלה ובסוף.
  if (Length(CurrentPath) > 0) and (CurrentPath[1] = ';') then
    Delete(CurrentPath, 1, 1);
  if (Length(CurrentPath) > 0) and (CurrentPath[Length(CurrentPath)] = ';') then
    Delete(CurrentPath, Length(CurrentPath), 1);

  RegWriteExpandStringValue(RootKey, SubKey, 'Path', CurrentPath);
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

  // com.example הוא מזהה ברירת המחדל של Flutter — מוחקים רק את תת-תיקיית
  // otzaria, אחרת נמחקים נתונים של אפליקציות Flutter אחרות.
  Path := ExpandConstant('{userappdata}\com.example\otzaria');
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
    // מ-PATH המשתמש מסירים תמיד (גם התקנות ישנות כתבו לשם); מהמערכתי רק
    // בהסרת התקנת מנהל — רק אז יש הרשאות כתיבה ל-HKLM.
    RemoveAppFromPathValue(HKCU, UserEnvironmentKey, ExpandConstant('{app}'));
    if IsAdminInstallMode then
      RemoveAppFromPathValue(HKLM, SystemEnvironmentKey, ExpandConstant('{app}'));
    if DeleteUserDataOnUninstall then
      DeleteAllUserData();
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ZstdPath, SevenZipPath: String;
  AppDataPath: string;
  ErrorLogPath: string;
  ResultCode: Integer;
begin
  if CurStep = ssInstall then
  begin
    // התקנה ניידת לא נוגעת בנתוני ההתקנה המקומית שבתיקיות המשתמש.
    if PortableMode then
      exit;

    // מחק את לוג השגיאות הישן בכל התקנה/עדכון
    ErrorLogPath := ExpandConstant('{userappdata}\otzaria\logs\errors.txt');
    if FileExists(ErrorLogPath) then
      DeleteFile(ErrorLogPath);
    ErrorLogPath := ExpandConstant('{commonappdata}\otzaria\logs\errors.txt');
    if FileExists(ErrorLogPath) then
      DeleteFile(ErrorLogPath);

    if WizardIsTaskSelected('resetsettings') then
    begin
      AppDataPath := GetDataDir('');
      if DirExists(AppDataPath) then
        DelTreeExceptBackups(AppDataPath);

      AppDataPath := ExpandConstant('{userappdata}\otzaria');
      if DirExists(AppDataPath) then
        DelTreeExceptBackups(AppDataPath);

      AppDataPath := ExpandConstant('{commonappdata}\otzaria');
      if DirExists(AppDataPath) then
        DelTreeExceptBackups(AppDataPath);

      AppDataPath := ExpandConstant('{localappdata}\otzaria');
      if DirExists(AppDataPath) then
        DelTreeExceptBackups(AppDataPath);

      // com.example הוא מזהה ברירת המחדל של Flutter — רק תת-תיקיית otzaria
      // שייכת לנו; מחיקת כל com.example תמחק נתונים של אפליקציות אחרות.
      AppDataPath := ExpandConstant('{userappdata}\com.example\otzaria');
      if DirExists(AppDataPath) then
        DelTreeExceptBackups(AppDataPath);

      // נתיבים ישנים מאוד: LocalAppData בעברית (לפני גרסה 0.9.x)
      AppDataPath := ExpandConstant('{localappdata}\אוצריא');
      if DirExists(AppDataPath) then
        DelTree(AppDataPath, True, True, True);

      AppDataPath := ExpandConstant('{localappdata}\אוצריא\Data');
      if DirExists(AppDataPath) then
        DelTree(AppDataPath, True, True, True);
    end;
  end;

  if CurStep <> ssPostInstall then
    exit;

  // במצב נייד GetSelectedBooksPath מחזיר את הנתיב שבתוך התיקייה הניידת —
  // מיישרים את המשתנה כדי שכל החילוץ בהמשך ילך לשם.
  SelectedBooksPath := GetSelectedBooksPath('');

  ZstdPath := ExpandConstant('{tmp}\zstd.exe');
  SevenZipPath := ExpandConstant('{tmp}\7za.exe');

  if not FileExists(ZstdPath) then
  begin
    Log('zstd.exe not found - cannot extract bundled library');
    MsgBox('קובץ החילוץ zstd.exe לא נמצא. ההתקנה לא יכולה לחלץ את קבצי הספרייה המצורפים.', mbCriticalError, MB_OK);
    Abort;
  end;

  if not FileExists(SevenZipPath) then
  begin
    Log('7za.exe not found - cannot extract bundled PDF archive');
    MsgBox('קובץ החילוץ 7za.exe לא נמצא. ההתקנה לא יכולה לחלץ את קבצי ה-PDF המצורפים.', mbCriticalError, MB_OK);
    Abort;
  end;

  WizardForm.ProgressGauge.Style := npbstMarquee;

#ifdef IndexedSplitFull
  WizardForm.StatusLabel.Caption := 'מחלץ ספרייה מלאה ואינדקס מוכן...';
  WizardForm.StatusLabel.Update;
  ExtractIndexedLibraryArchive();
#else
  WizardForm.StatusLabel.Caption := 'מחלץ מסד הנתונים seforim.db...';
  WizardForm.StatusLabel.Update;
  ExtractBundledDatabase('seforim.db.zst', 'seforim.db');

  WizardForm.StatusLabel.Caption := 'מחלץ קטלוג אוצר החכמה...';
  WizardForm.StatusLabel.Update;
  ExtractBundledDatabase('otzar-HB_catalog.db.zst', 'otzar-HB_catalog.db');

  WizardForm.StatusLabel.Caption := 'מחלץ ספרי תלמוד בבלי...';
  WizardForm.StatusLabel.Update;
  ExtractBundledTarArchive('talmud_bavli_latest.tar.zst', 'תלמוד בבלי');

  WizardForm.StatusLabel.Caption := 'מחלץ מילון לחיפוש המקורב...';
  WizardForm.StatusLabel.Update;
  ExtractBundledDatabase('lexical.db.zst', 'lexical.db');
#endif

  WizardForm.ProgressGauge.Style := npbstNormal;
  WizardForm.ProgressGauge.Position := WizardForm.ProgressGauge.Max;

  if PortableMode then
  begin
    // קובץ ה-marker מפעיל את המצב הנייד באפליקציה; נתיב הספרייה לא נכתב —
    // במצב נייד האפליקציה גוזרת אותו בעצמה (otzaria_data\books ליד ה-EXE).
    ForceDirectories(SelectedBooksPath);
    SaveStringToFile(ExpandConstant('{app}\portable.marker'), '', False);
  end
  else if SelectedBooksPath <> '' then
  begin
    // יצירת תיקיית הספרים בנתיב שבחר המשתמש (אם שונה מברירת המחדל)
    ForceDirectories(SelectedBooksPath);
    WriteLibraryPathToPrefs(SelectedBooksPath);
  end;

  // בהתקנה שקטה משיקים את אוצריא רק עכשיו — אחרי שהחילוץ הסתיים — כי רשומת
  // postinstall לא רצה ב-VERYSILENT, ורשומת [Run] רגילה הייתה רצה לפני
  // ssPostInstall (על ספרייה ריקה). ExecAsOriginalUser מוריד הרשאות כמו
  // דגל runasoriginaluser בהתקנה מורמת.
  if WizardSilent then
    ExecAsOriginalUser(ExpandConstant('{app}\{#MyAppExeName}'), '',
      ExpandConstant('{app}'), SW_SHOWNORMAL, ewNoWait, ResultCode);
end;

[Run]
; Visual C++ Redistributable כבר לא מותקן ע"י המתקין — ה-DLLs של ה-runtime
; נארזים app-local ליד otzaria.exe (ראה .github/workflows/build-and-announce.yml,
; השלב "Bundle latest VC++ Redistributable runtime DLLs"). זה פותר גם משתמשים
; שתקועים עם MSVCP140.dll 14.36.32532.0 הפגום, בלי הרצת installer נוסף.
Filename: "{tmp}\MicrosoftEdgeWebview2Setup.exe"; Parameters: "/silent /install"; StatusMsg: "מתקין Microsoft WebView2 Runtime..."; Flags: waituntilterminated; Check: ShouldInstallWV2
; בהתקנה שקטה ההשקה מתבצעת בקוד בסוף ssPostInstall (ראה CurStepChanged).
Filename: "{app}\{#MyAppExeName}"; Description: "הפעל את {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; AppUserModelID: "Otzaria.Otzaria"; Check: not IsPortableInstall
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon; AppUserModelID: "Otzaria.Otzaria"; Check: not IsPortableInstall
; קיצור דרך ישיר ללוח השנה — מעביר ל-otzaria.exe deep link כפרמטר; אוצריא מזהה
; ארגומנט שמתחיל ב-"otzaria:" וממסרת לראוטר הפנימי (ראה docs/deep_links.md לזרימה המלאה).
; AppUserModelID זהה לסמל הראשי כדי שהקיצור יתאחד עם הכפתור המוצמד בשורת המשימות.
Name: "{autodesktop}\לוח שנה - {#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Parameters: "otzaria://open/calendar"; Tasks: calendaricon; AppUserModelID: "Otzaria.Otzaria"; Check: not IsPortableInstall

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "calendaricon"; Description: "צור קיצור דרך ישירות ללוח שנה"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "resetsettings"; Description: "איפוס הגדרות משתמש והסרת התקנות קודמות (מומלץ למעדכנים מגרסה < 0.9.80, שים לב: זה ימחק הערות אישיות, סימניות, היסטוריה ונתוני תוספים! תיקיית הגיבויים נשמרת)"; Flags: unchecked

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
#ifndef IndexedSplitFull
Source: "library_db\seforim.db.zst"; DestDir: "{tmp}"; Flags: deleteafterinstall nocompression
Source: "library_db\otzar-HB_catalog.db.zst"; DestDir: "{tmp}"; Flags: deleteafterinstall nocompression
Source: "library_db\talmud_bavli_latest.tar.zst"; DestDir: "{tmp}"; Flags: deleteafterinstall nocompression
Source: "library_db\lexical.db.zst"; DestDir: "{tmp}"; Flags: deleteafterinstall nocompression
#endif
Source: "zstd.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "7za.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall
#ifdef IndexedSplitFull
Source: "read_indexed_library_manifest.ps1"; Flags: dontcopy
Source: "..\tool\release\assemble_split_asset.ps1"; Flags: dontcopy
Source: "indexed_library.manifest.json"; Flags: dontcopy
#endif

; MicrosoftEdgeWebview2Setup.exe — bootstrapper קטן (~2MB) שמוריד ומתקין WebView2
; נדרש על ידי flutter_inappwebview_windows; ב-Win10/11 עם Edge עדכני — כבר קיים
Source: "MicrosoftEdgeWebview2Setup.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall; Check: ShouldInstallWV2

; קבצי הצגה לדף "תכונות עיקריות" - dontcopy = נארזים בתוך המתקין אבל לא מותקנים אצל המשתמש
Source: "feature1.bmp"; Flags: dontcopy
Source: "feature2.bmp"; Flags: dontcopy
Source: "feature3.bmp"; Flags: dontcopy
Source: "feature4.bmp"; Flags: dontcopy

[INI]
Filename: "{app}\system_install.marker"; Section: "Install"; Key: "Mode"; String: "Admin"; Check: IsAdminInstallMode and not IsPortableInstall

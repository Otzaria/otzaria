; המתקין המלא (FULL) של אוצריא — כולל ספריית הספרים המצורפת.
; שדרוג מגרסה 0.9.88 ומעלה מזוהה אוטומטית ומותקן ללא שאלות, עם חלון התקדמות.
; ההגדרות וקיצורי הדרך נשמרים, והספרייה מוחלפת בחבילה
; החדשה בנתיב הספרים הקיים של המשתמש. התקנה חדשה או שדרוג מגרסה ישנה
; מקבלים את האשף המלא בשכבת התצוגה של אוצריא (otzaria_ui_installer.iss).
; עמוד "איך להתקין" מציע: רק בשבילי (ברירת מחדל, ללא UAC), לכל
; המשתמשים (שיגור-מחדש מורם עם /ALLUSERS), וגרסה ניידת. בהתקנה ניידת
; נכתב portable.marker ליד ה-EXE, הספרייה מחולצת ל-otzaria_data\books
; בתוך תיקיית ההתקנה (הנתיב שהאפליקציה גוזרת בעצמה במצב נייד — אין צורך
; בכתיבת הגדרות), ואין שום רישום במערכת. הפרמטר /PORTABLE פותח את האשף
; במצב נייד גם כשמותקנת גרסה מודרנית (שאחרת הייתה משודרגת בשקט).

#define MyAppName "אוצריא"
#define MyAppVersion "0.9.98"
#define MyAppPublisher "sivan22"
#define MyAppURL "https://github.com/otzaria/otzaria"
#define MyAppExeName "otzaria.exe"
; חייב להתאים ל-AppPaths.bundledPluginsFolderName.
#define BundledPluginsDirName "bundled_plugins"
; חנות התוספים — מועתקת רק כשיש רשת (bundled_plugins_network_check.iss).
#define NetworkGatedPlugin "otzaria.plugins_directory.otzplugin"
; החלקים של שכבת התצוגה שקיימים רק במתקין המלא (עמוד הספרים, WebView2, החילוץ).
#define InstallerFull

; ארכיטקטורת היעד כמו ב-otzaria.iss: "x64" (ברירת מחדל) או ‎ISCC /DAppArch=arm64‎.
#ifndef AppArch
  #define AppArch "x64"
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
#if AppArch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
; zstd ו-7za שמחלצים את הספרייה הם x64, ו-Windows 10 על ARM מאמלץ רק x86.
MinVersion=10.0.22000
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif
; lowest = לא מבקש UAC כשמפעילים רגיל; אם המשתמש בחר "Run as administrator"
; התהליך כבר מורם, IsAdmin=True, ואז משגרים מחדש עם /ALLUSERS.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=commandline
DefaultDirName={code:GetDefaultInstallDir}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=.
#if AppArch == "arm64"
; "full" בשם מונע מהעדכון שבתוך התוכנה לבחור בו כמתקין עדכון.
OutputBaseFilename=otzaria-{#MyAppVersion}-windows_arm64-full
#else
OutputBaseFilename=otzaria-{#MyAppVersion}-windows-full
#endif
SetupIconFile=white_sketch128x128.ico
; האשף מצויר כולו בשכבת התצוגה. התמונה הקטנה נשארת בשביל חלון ההסרה, שאין לו את העיצוב.
WizardImageFile=
WizardSmallImageFile=wizard_small.bmp,wizard_small@2x.bmp,wizard_small@3x.bmp
; עמוד הפתיחה הוא מסך הפתיחה המונפש של שכבת התצוגה.
DisableWelcomePage=no
Compression=lzma
SolidCompression=yes
; Disable compression for DLL files to prevent corruption
CompressionThreads=1
WizardStyle=modern
DisableDirPage=no
; השאלה על תיקייה קיימת נשאלת בדו-שיח המעוצב (DirExistsDifferentFromPrevious).
DirExistsWarning=no
; התקנה ניידת אינה נרשמת במערכת — בלי uninstaller ובלי רשומה ב"הוספה או
; הסרה של תוכניות"; להסרה מוחקים את התיקייה.
Uninstallable=not IsPortableInstall
CreateUninstallRegKey=not IsPortableInstall
; ChangesEnvironment=yes נדרש כדי שעדכון ה-PATH ייכנס לתוקף מיד עבור
; תהליכים חדשים ללא צורך ב-logoff. שולח WM_SETTINGCHANGE.
ChangesEnvironment=yes
; לוג אוטומטי ל-%TEMP% של המשתמש המריץ — חיוני לאבחון התקנות שקטות שנכשלות בשטח.
SetupLogging=yes
; בלי זה בחירת המשימות נשמרת ברישום — "איפוס הגדרות" שסומן פעם היה
; רץ שוב בכל שדרוג שקט ומוחק את נתוני המשתמש (issue #941).
UsePreviousTasks=no
; עברית כשממשק Windows בעברית, ואנגלית בכל שפה אחרת: english ראשונה ולכן היא הנסיגה.
; בשדרוג Inno שומר את שפת ההתקנה הקודמת (UsePreviousLanguage).
LanguageDetectionMethod=uilanguage
ShowLanguageDialog=no

[InstallDelete]
; ניקוי מסד הנתונים הישן של Isar שהוחלף על ידי hive_ce — מחיקה מכוונת בעת שדרוג.
Type: filesandordirs; Name: "{app}\default.isar";
; המסמן נכתב רק בהתקנת מנהל (ראה [INI]) והאפליקציה גוזרת ממנו את מיקום
; ברירת המחדל של הספרייה — מסמן ששרד מעבר להתקנת משתמש מפנה אותה ל-ProgramData.
Type: files; Name: "{app}\system_install.marker"; Check: (not IsAdminInstallMode) or IsPortableInstall
; המסמן מפעיל את המצב הנייד ומפנה את כל הנתונים ל-otzaria_data ליד ה-EXE — מסמן ששרד
; מעבר להתקנה רגילה משאיר את הנתונים תחת Program Files, שאינה כתיבה (issue #1031).
Type: files; Name: "{app}\portable.marker"; Check: not IsPortableInstall
; ניקוי ארכיוני תוספים של הגרסה הקודמת — הרשימה יכולה להשתנות בין גרסאות,
; והארכיונים כבר נרשמו ואינם נדרשים.
Type: filesandordirs; Name: "{app}\{#BundledPluginsDirName}"
; אין כאן מחיקה של תיקיית הספרים: הספרייה מוחלפת רק אחרי חילוץ מלא ומוצלח
; ל-staging — מחיקה מוקדמת השאירה משדרגים בלי ספרייה (issue #867).

[Dirs]
; במצב נייד הנתונים יושבים ב-otzaria_data ליד ה-EXE — האפליקציה יוצרת אותה בעצמה.
Name: "{code:GetDataDir}"; Permissions: users-modify; Check: not IsPortableInstall
Name: "{code:GetDataDir}\books"; Permissions: users-modify; Check: not IsPortableInstall
Name: "{code:GetDataDir}\index"; Permissions: users-modify; Check: not IsPortableInstall

[Registry]
; uninsdeletekey ולא ifempty: ערכי ברירת המחדל שכאן אינם נמחקים בהסרה, ולכן
; המפתח אינו מתרוקן לעולם ונשאר מצביע על EXE שהוסר.
Root: HKA; Subkey: "Software\Classes\otzaria"; ValueType: string; ValueName: ""; ValueData: "URL:Otzaria Protocol"; Flags: uninsdeletekey; Check: not IsPortableInstall
Root: HKA; Subkey: "Software\Classes\otzaria"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""; Flags: uninsdeletevalue; Check: not IsPortableInstall
Root: HKA; Subkey: "Software\Classes\otzaria\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName}"; Flags: uninsdeletekeyifempty; Check: not IsPortableInstall
Root: HKA; Subkey: "Software\Classes\otzaria\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Flags: uninsdeletekeyifempty; Check: not IsPortableInstall
; "פרוטוקול מהימן" באופיס — מונע את אזהרת האבטחה בלחיצה על קישור otzaria://
; במסמך. ההגדרה היא פר-משתמש, ולכן האפליקציה יוצרת את המפתחות בכל הפעלה
; (PluginProtocolRegistrationService) ולא המתקין; כאן רק ההסרה כדי שלא יישארו
; שאריות. 12.0=2007, 14.0=2010, 15.0=2013, 16.0=2016 ואילך.
Root: HKCU; Subkey: "Software\Policies\Microsoft\Office\12.0\Common\Security\Trusted Protocols\All Applications\otzaria:"; Flags: dontcreatekey uninsdeletekey; Check: not IsPortableInstall
Root: HKCU; Subkey: "Software\Policies\Microsoft\Office\14.0\Common\Security\Trusted Protocols\All Applications\otzaria:"; Flags: dontcreatekey uninsdeletekey; Check: not IsPortableInstall
Root: HKCU; Subkey: "Software\Policies\Microsoft\Office\15.0\Common\Security\Trusted Protocols\All Applications\otzaria:"; Flags: dontcreatekey uninsdeletekey; Check: not IsPortableInstall
Root: HKCU; Subkey: "Software\Policies\Microsoft\Office\16.0\Common\Security\Trusted Protocols\All Applications\otzaria:"; Flags: dontcreatekey uninsdeletekey; Check: not IsPortableInstall
; הוספת {app} ל-PATH אוטומטית (מאפשר ‎`otzaria pack-plugin`‎ מהטרמינל):
; התקנת מנהל → PATH המערכתי; התקנת משתמש → PATH של המשתמש. ה-Check מונע
; כפילויות בהתקנה חוזרת; ההסרה מתבצעת ב-CurUninstallStepChanged (לא ניתן
; להשתמש ב-uninsdelete* על expandsz "מצטבר" כי הוא ידרוס את הערך כולו).
Root: HKLM; Subkey: "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"; ValueType: expandsz; ValueName: "Path"; ValueData: "{olddata};{app}"; Flags: preservestringtype; Check: ShouldAddToSystemPath
Root: HKCU; Subkey: "Environment"; ValueType: expandsz; ValueName: "Path"; ValueData: "{olddata};{app}"; Flags: preservestringtype; Check: ShouldAddToUserPath

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "hebrew"; MessagesFile: "compiler:Languages\Hebrew.isl"

; העיצוב של שכבת התצוגה ראשון ב-[Files]: עם SolidCompression הפתיחה אינה ממתינה לפריסת
; האפליקציה והספרייה. הליבה לפני כל הקוד: היא מגדירה את EnglishUi ואת UiTell/UiAsk.
#define OtzariaUiProduct "installer"
#include "otzaria_ui_art.iss"
#include "otzaria_ui_core.iss"

[Code]
#include "bundled_plugins_network_check.iss"
#include "install_dir_length_check.iss"

const
  UninstallRegKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{EEC4F712-CD05-4D15-A753-509E840A51A5}_is1';
  SystemEnvironmentKey = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment';
  UserEnvironmentKey = 'Environment';
  // האפליקציה רושמת כאן את נתיב הספרייה הפעיל (lib/core/app_paths.dart).
  LibraryPathRecordFileName = 'library_path.txt';

var
  // מודל הנתונים של כרטיס WebView2 בעמוד האפשרויות.
  WV2Check: TCheckBox;
  WebView2Missing: Boolean;
  InstallWV2: Boolean;

  BooksPage: TWizardPage;
  BooksPathEdit: TEdit;
  BooksPathBrowseBtn: TNewButton;
  BooksWarnLabel: TLabel;
  SelectedBooksPath: String;

  // מודל הנתונים של כרטיסי "איך להתקין" בעמוד wpSelectDir.
  CurrentUserModeRadio: TNewRadioButton;
  AllUsersModeRadio: TNewRadioButton;
  PortableModeRadio: TNewRadioButton;
  PortableMode: Boolean;
  // מסמן שהאשף נסגר לטובת שיגור-מחדש במצב התקנה אחר — הסגירה שקטה,
  // בלי שאלת האישור של ביטול התקנה.
  RelaunchingForModeChange: Boolean;
  RegularInstallDirDefault: String;
  PortableInstallDirDefault: String;
  // המשתמש בחר לדלג על חילוץ הספרייה בהתקנה ניידת — קיימת ספרייה במחשב.
  PortableSkipLibrary: Boolean;
  // הספרייה הקודמת כבר הוזזה לגיבוי: מכאן כישלון כבר אינו מבטיח שהיא נשארה כפי שהייתה.
  LibrarySwapStarted: Boolean;

  // אם המשתמש בחר במהלך ההסרה למחוק גם את כל הנתונים והספרים, לא רק את
  // קבצי האפליקציה. ברירת המחדל False — נשמר כדי לא לאבד נתונים בעדכון
  // שקט (Inno Setup מריץ את ה-uninstaller הישן עם /SILENT).
  DeleteUserDataOnUninstall: Boolean;
  // נתיב ספרייה מותאם מה-prefs; איפוס הגדרות מדלג עליו כדי לא למחוק ספרים.
  ProtectedLibraryPath: String;

// משמש גם את Uninstallable/CreateUninstallRegKey וגם רשומות Check.
function IsPortableInstall(): Boolean;
begin
  Result := PortableMode;
end;

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

#include "otzaria_ui_installer.iss"

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

  // התקנות מנהל ממתקינים ישנים (32-ביט) נרשמו תחת WOW6432Node — גם מערכתיות.
  if TryGetInstallDirFromRegistry(HKLM32, UninstallRegKey, InstallDir) then
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

// נתוני החיפוש החכם שמסייע ההורדה הכין: ההורה של תיקיית הספרייה הוא
// SemanticPaths.root באפליקציה, ושם היא מחפשת את semantic-import.
function GetSemanticImportDir(Param: String): String;
begin
  Result := ExtractFileDir(GetSelectedBooksPath('')) + '\semantic-import';
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
  // התקנות מנהל ממתקינים ישנים (32-ביט) נרשמו תחת WOW6432Node.
  if RegQueryStringValue(HKLM32, UninstallRegKey, 'DisplayVersion', Result) and (Result <> '') then
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
  // הספרייה המוגנת עשויה להיות הנתיב הנמחק עצמו, לא רק תת-תיקייה שלו.
  if (ProtectedLibraryPath <> '') and
     (Lowercase(Path) = Lowercase(ProtectedLibraryPath)) then
    exit;

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
            if (Lowercase(FindRec.Name) <> 'backups') and
               ((ProtectedLibraryPath = '') or
                (Lowercase(ChildPath) <> Lowercase(ProtectedLibraryPath))) then
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

procedure WriteLibraryPathToPrefs(const LibraryPath: String);
begin
  WriteStringPreferenceToPrefs('key-library-path', LibraryPath);
  // ערך stale בשם תת-התיקייה מפנה את האפליקציה ל-<books>\<folder>\seforim.db
  // שאינו קיים בפריסה החדשה — והספרייה שהותקנה זה עתה "נעלמת" (issue #871).
  WriteStringPreferenceToPrefs('key-library-folder-name', '');
end;

// מחזיר את נתיב תיקיית הספרים שהמשתמש בחר (אם שונה מברירת המחדל),
// כפי שנשמר ב-shared_preferences.json תחת המפתח flutter.key-library-path.
// משתמש בעוזרי ה-JSON הקיימים (LoadTextFile, FindJsonStringEnd) ובפענוח
// escapes ה-JSON בסיסי שתואם ל-EscapeJsonString.
// קורא את נתיב הספרייה שהאפליקציה רשמה תחת [DataRoot]. ההגדרות עצמן
// יושבות ב-Hive בינארי שהמתקין אינו יכול לקרוא, ולכן זה המקור
// לנתיב שהמשתמש שינה מתוך התוכנה (issue #1020).
function ReadLibraryPathRecord(const DataRoot: String): String;
var
  RecordFile: String;
begin
  Result := '';
  if DataRoot = '' then
    exit;
  RecordFile := AddBackslash(DataRoot) + LibraryPathRecordFileName;
  if not FileExists(RecordFile) then
    exit;
  Result := Trim(LoadTextFile(RecordFile));
  if (Result <> '') and (Result[1] = #$FEFF) then
    Delete(Result, 1, 1);
end;

function GetCustomLibraryPath(): String;
var
  PrefsFile, JsonContent, KeyStr, Value: String;
  KeyPos, ValueStart, ValueEnd: Integer;
begin
  Result := ReadLibraryPathRecord(ExpandConstant('{userappdata}\otzaria'));
  if Result <> '' then
    exit;

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

// מאתר ספרייה קיימת במחשב: הנתיב המותאם מה-prefs, ואחריו נתיבי ברירת
// המחדל של התקנת משתמש ושל התקנת מנהל.
function FindExistingLibraryPath(): String;
begin
  Result := GetCustomLibraryPath();
  if IsOtzariaBooksFolder(Result) then
    exit;
  Result := ExpandConstant('{userappdata}\otzaria\books');
  if IsOtzariaBooksFolder(Result) then
    exit;
  Result := ExpandConstant('{commonappdata}\otzaria\books');
  if IsOtzariaBooksFolder(Result) then
    exit;
  Result := '';
end;

// בהתקנה ניידת עם ספרייה קיימת במחשב — שואל אם לחלץ עותק נוסף של
// גיגה-בייטים לתיקייה הניידת, או לדלג ולהשתמש בקיימת (issue #861).
procedure AskPortableLibraryChoice();
var
  ExistingPath: String;
begin
  PortableSkipLibrary := False;
  if not PortableMode then
    exit;
  ExistingPath := FindExistingLibraryPath();
  if ExistingPath = '' then
    exit;
  // "כן" (Enter) נשאר חילוץ: דילוג רק בבחירה מפורשת ב"לא" (Esc אינו עונה).
  PortableSkipLibrary := not InstAskYesNo(CustomMessage('PortableLibraryTitle'),
    Msg1('PortableLibraryFound', UiDialogPath(ExistingPath)), mbConfirmation, MB_YESNO);
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

  // אתחול ברירות מחדל כבר עכשיו, כדי ש-GetSelectedBooksPath יחזיר ערך
  // תקין בכל מסלול ריצה.
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
      InstTell(CustomMessage('AdminNeededTitle'),
        Msg1('ProtectedPreviousInstall', UiDialogPath(PreviousDir)), mbError);
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
    if InstAskYesNo(CustomMessage('LegacyFoundTitle'),
      FmtMessage(CustomMessage('LegacyFound'), [UiDialogPath(OldPath), UiDialogPath(DataPath)]), mbConfirmation,
      MB_YESNO) then
      InstTell(CustomMessage('LegacyFoundTitle'),
        FmtMessage(CustomMessage('LegacyMoveLater'), [UiDialogPath(OldPath), UiDialogPath(DataPath)]), mbInformation);
  end;

  // הבחירה בין משתמש-נוכחי / כל-המשתמשים / ניידת נעשית בעמוד "איך להתקין"
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

    InstTell(CustomMessage('AdminNeededTitle'),
      Msg1('ProtectedPreviousInstall', UiDialogPath(PreviousDir)), mbError);
    Result := False;
  end;
end;

// ─── "איך להתקין" ו-WebView2 ────────────────────────────────────────────────

// הרדיו מחוץ לחלון בקבוצה משלהם: חצים מסמנים, ו-OnClick מסנכרן את הכרטיסים.
procedure CreateInstallModeChoice();
var
  Group: TPanel;
begin
  // חצים עוברים רק בין הילדים של אותו הורה.
  Group := TPanel.Create(WizardForm);
  Group.Parent := WizardForm.SelectDirPage;
  Group.SetBounds(-ScaleX(4000), 0, ScaleX(200), ScaleY(80));
  CurrentUserModeRadio := TNewRadioButton.Create(WizardForm);
  CurrentUserModeRadio.Parent := Group;
  CurrentUserModeRadio.Caption := CustomMessage('ModeMeTitle');
  CurrentUserModeRadio.SetBounds(0, 0, ScaleX(200), ScaleY(20));
  CurrentUserModeRadio.Checked := True;
  CurrentUserModeRadio.OnClick := @UiModeRadioClick;
  AllUsersModeRadio := TNewRadioButton.Create(WizardForm);
  AllUsersModeRadio.Parent := Group;
  AllUsersModeRadio.Caption := CustomMessage('ModeAllTitle');
  AllUsersModeRadio.SetBounds(0, ScaleY(24), ScaleX(200), ScaleY(20));
  AllUsersModeRadio.OnClick := @UiModeRadioClick;
  PortableModeRadio := TNewRadioButton.Create(WizardForm);
  PortableModeRadio.Parent := Group;
  PortableModeRadio.Caption := CustomMessage('ModePortableTitle');
  PortableModeRadio.SetBounds(0, ScaleY(48), ScaleX(200), ScaleY(20));
  PortableModeRadio.OnClick := @UiModeRadioClick;
end;

// בחירה בכרטיס: המצב הנייד נקבע מיד, ותיקיית היעד מתחלפת לברירת המחדל של המצב
// בלי לדרוס נתיב שהמשתמש הקליד בעצמו.
procedure ApplyInstallModeChoice();
begin
  PortableMode := PortableModeRadio.Checked;
  if PortableMode and (WizardForm.DirEdit.Text = RegularInstallDirDefault) then
    WizardForm.DirEdit.Text := PortableInstallDirDefault
  else if (not PortableMode) and (WizardForm.DirEdit.Text = PortableInstallDirDefault) then
    WizardForm.DirEdit.Text := RegularInstallDirDefault;
end;

// מצב ההתקנה של Inno נקבע בעליית התהליך: מעבר בין משתמש-נוכחי לכל-המשתמשים
// מחייב שיגור-מחדש. התקנה ניידת אדישה למצב.
function ModeChangeNeedsRelaunch(): Boolean;
begin
  Result := (AllUsersModeRadio.Checked and (not IsAdminInstallMode)) or
    (CurrentUserModeRadio.Checked and IsAdminInstallMode);
end;

// WebView2 משמש רק את התוספים. חסר — מסומן ואפשר לבטל; קיים — נעול ולא מותקן שוב.
// Visual C++ Runtime נארז app-local ליד otzaria.exe ואינו מותקן כאן.
procedure CreateWebView2Choice();
begin
  WebView2Missing := WebView2NeedsInstall;
  WV2Check := TCheckBox.Create(WizardForm);
  WV2Check.Parent := WizardForm.SelectTasksPage;
  WV2Check.Caption := CustomMessage('WebView2Title');
  WV2Check.Left := -ScaleX(4000);
  WV2Check.Checked := WebView2Missing;
  WV2Check.Enabled := WebView2Missing;
end;

// ─── דף בחירת תיקיית הספרים ─────────────────────────────────────────────────

procedure UpdateBooksWarning(const Path: String);
begin
  if BooksWarnLabel = nil then exit;
  if DirExists(Path) then
    BooksWarnLabel.Caption := CustomMessage('BooksExists')
  else
    BooksWarnLabel.Caption := '';
  UiInstBooksWarningChanged();
end;

procedure BooksPathChanged(Sender: TObject);
begin
  UpdateBooksWarning(BooksPathEdit.Text);
end;

procedure BrowseBooksFolder(Sender: TObject);
var
  Dir: String;
begin
  Dir := BooksPathEdit.Text;
  if BrowseForFolder(CustomMessage('BooksBrowse'), Dir, False) then
  begin
    BooksPathEdit.Text := Dir;
    UpdateBooksWarning(Dir);
  end;
end;

procedure CreateBooksPage;
var
  DefaultPath, CustomPath: String;
begin
  BooksPage := CreateCustomPage(wpSelectDir, CustomMessage('BooksTitle'),
    CustomMessage('BooksDesc'));

  // ספרייה קיימת מנצחת את ברירת המחדל (כמו ב-InitializeSilentDefaults): אחרת
  // מעבר בין מנהל למשתמש מזיז את מיקום החילוץ בעוד האפליקציה קוראת מהישן.
  DefaultPath := GetDataDir('') + '\books';
  CustomPath := GetCustomLibraryPath();
  if IsOtzariaBooksFolder(CustomPath) then
    DefaultPath := CustomPath;
  SelectedBooksPath := DefaultPath;

  // שכבת התצוגה ממקמת את השדה והכפתור ומציגה את האזהרה.
  BooksPathEdit := TEdit.Create(BooksPage);
  BooksPathEdit.Parent := BooksPage.Surface;
  BooksPathEdit.Text := DefaultPath;
  BooksPathEdit.OnChange := @BooksPathChanged;

  BooksPathBrowseBtn := TNewButton.Create(BooksPage);
  BooksPathBrowseBtn.Parent := BooksPage.Surface;
  BooksPathBrowseBtn.OnClick := @BrowseBooksFolder;

  BooksWarnLabel := TLabel.Create(BooksPage);
  BooksWarnLabel.Parent := BooksPage.Surface;
  BooksWarnLabel.Visible := False;

  UpdateBooksWarning(DefaultPath);
end;

procedure InitializeWizard;
begin
  if WizardSilent then
    // אין דפי אשף בהתקנה שקטה — רק ברירות המחדל (נקבעות גם ב-InitializeSetup).
    InitializeSilentDefaults()
  else
  begin
    InstallWV2 := WebView2NeedsInstall;
    CreateInstallModeChoice();
    CreateWebView2Choice();
    CreateBooksPage;

    RegularInstallDirDefault := WizardForm.DirEdit.Text;
    // {userdocs} זורק כשלחשבון המנהל שאישר את ה-UAC אין פרופיל/Documents מלא.
    try
      PortableInstallDirDefault := ExpandConstant('{userdocs}\OtzariaPortable');
    except
      PortableInstallDirDefault := ExpandConstant('{sd}\OtzariaPortable');
    end;

    // בחירה מוקדמת בעמוד "איך להתקין": ‎/PORTABLE — מצב נייד; ריצה במצב מנהל
    // (שיגור-מחדש עם /ALLUSERS) או תהליך מורם — לכל המשתמשים.
    // ‎/CURRENTUSER = שיגור-מחדש מתהליך מורם שבחר במפורש התקנת משתמש.
    if CmdLineParamExists('/PORTABLE') then
      PortableModeRadio.Checked := True
    else if IsAdminInstallMode or
      (IsAdmin and not CmdLineParamExists('/CURRENTUSER')) then
      AllUsersModeRadio.Checked := True;
    ApplyInstallModeChoice();
  end;
  UiInstallerInitializeWizard();
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  // שיגור-מחדש עם מצב מפורש (מעמוד "איך להתקין") — הפתיחה כבר הוצגה בריצה
  // הקודמת; ממשיכים ישר ל"איך להתקין", שבו הבחירה מסומנת ונבחרת התיקייה.
  Result :=
    (CmdLineParamExists('/ALLUSERS') or CmdLineParamExists('/CURRENTUSER')) and
    (PageID = wpWelcome);
  if Result or (not PortableMode) then
    exit;
  // במצב נייד: אין קיצורי דרך/איפוס (בעמוד האפשרויות נשאר רק WebView2, כשהוא
  // חסר), והספרייה תמיד בתוך התיקייה הניידת (עמוד תיקיית הספרים).
  Result := ((PageID = wpSelectTasks) and not WebView2Missing) or
    ((BooksPage <> nil) and (PageID = BooksPage.ID));
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  UiCurPageChanged(CurPageID);
end;

procedure DeinitializeSetup();
begin
  UiDeinitializeSetup();
end;

function IsPathUnder(Target: String; Root: String): Boolean;
begin
  Result := (Root <> '') and (Pos(Lowercase(AddBackslash(Root)), Target) = 1);
end;

// תיקיות מערכת שאינן כתיבות למשתמש רגיל. במצב נייד כל הנתונים נשמרים
// בתיקיית התוכנה, ושם הם נחסמים — כולל תיקיית ה-WebView2 של התוספים
// (issue #1031).
function IsProtectedInstallDir(Path: String): Boolean;
var
  Target: String;
begin
  Target := Lowercase(AddBackslash(RemoveBackslash(Path)));
  Result := IsPathUnder(Target, ExpandConstant('{commonpf}')) or
            IsPathUnder(Target, ExpandConstant('{commonpf32}')) or
            IsPathUnder(Target, ExpandConstant('{win}')) or
            IsPathUnder(Target, ExpandConstant('{commonappdata}'));
end;

// כמו DirExistsWarning=auto של Inno: תיקייה קיימת שאינה תיקיית ההתקנה הקודמת.
function DirExistsDifferentFromPrevious(): Boolean;
begin
  Result := DirExists(WizardForm.DirEdit.Text) and
    (CompareText(RemoveBackslash(WizardForm.DirEdit.Text),
      RemoveBackslash(WizardForm.PrevAppDir)) <> 0);
end;

procedure WarnPortableProtectedDir();
begin
  InstTell(CustomMessage('PortableProtectedTitle'), CustomMessage('PortableProtected'),
    mbError);
end;

// שמירת בחירות בלחיצת "הבא". ב"איך להתקין" (wpSelectDir, אחרי הבדיקות של Inno
// לתיקייה): במעבר בין משתמש-נוכחי לכל-המשתמשים — שיגור-מחדש במצב ההתקנה המתאים
// (מצב ההתקנה של Inno נקבע בעליית התהליך).
// בהתקנה שקטה Inno "מדפדף" בין העמודים ומפעיל גם את הפונקציה הזו — שם
// אסור לגעת בכלום: המצב כבר נקבע ב-InitializeSetup ו-/DIR חייב להישמר.
function NextButtonClick(CurPageID: Integer): Boolean;
var
  ResultCode: Integer;
  Launched: Boolean;
begin
  Result := True;
  // גם בהתקנה שקטה עם /DIR: False עוצר כאן, לפני שנכתב קובץ כלשהו.
  if (CurPageID = wpSelectDir) and InstallDirTooLong() then
  begin
    Result := False;
    exit;
  end;
  if WizardSilent then
    exit;

  if (CurPageID = wpSelectDir) and DirExistsDifferentFromPrevious() and
     not ModeChangeNeedsRelaunch() and
     not InstAskYesNo(SetupMessage(msgDirExistsTitle),
       FmtMessage(SetupMessage(msgDirExists), [UiDialogPath(WizardForm.DirEdit.Text)]),
       mbConfirmation, MB_YESNO) then
  begin
    Result := False;
    exit;
  end;

  if (CurPageID = wpSelectDir) and PortableMode and
     IsProtectedInstallDir(WizardForm.DirEdit.Text) then
  begin
    WarnPortableProtectedDir();
    Result := False;
    exit;
  end;

  if (CurPageID = wpSelectDir) and ModeChangeNeedsRelaunch() then
  begin
    if AllUsersModeRadio.Checked then
    begin
      if IsAdmin then
        // התהליך כבר מורם אבל במצב משתמש — שיגור-מחדש עם /ALLUSERS, בלי UAC.
        Launched := RelaunchSetup('open', '/ALLUSERS', SW_SHOWNORMAL, ResultCode)
      else
        Launched := RelaunchSetupElevated('/ALLUSERS', SW_SHOWNORMAL, ResultCode);
      if not Launched then
        InstTell(CustomMessage('AdminNeededTitle'), CustomMessage('AllUsersRelaunchFailed'),
          mbError);
    end
    else
    begin
      // התהליך כבר במצב מנהל — חזרה להתקנת משתמש דורשת שיגור-מחדש.
      Launched := RelaunchSetup('open', '/CURRENTUSER', SW_SHOWNORMAL, ResultCode);
      if not Launched then
        InstTell(CustomMessage('ModeChangeFailedTitle'),
          CustomMessage('CurrentUserRelaunchFailed'), mbError);
    end;
    if Launched then
    begin
      // UiClosing: הסגירה אינה שואלת "לצאת?" גם בשכבת התצוגה.
      RelaunchingForModeChange := True;
      UiClosing := True;
      WizardForm.Close;
    end;
    Result := False;
    exit;
  end;

  if CurPageID = wpSelectTasks then
    InstallWV2 := WV2Check.Checked;
  if (BooksPage <> nil) and (CurPageID = BooksPage.ID) then
  begin
    SelectedBooksPath := BooksPathEdit.Text;
    if SelectedBooksPath = '' then
    begin
      InstTell(CustomMessage('BooksRequiredTitle'), CustomMessage('BooksRequired'), mbError);
      Result := False;
    end;
  end;
  if (CurPageID = wpReady) and Result then
    AskPortableLibraryChoice();
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

// ממפה מחרוזות שגיאה נפוצות מ-zstd/7za (תמיד באנגלית) להסבר קצר בשפת המתקין.
// מחזיר מחרוזת ריקה אם לא זוהה דפוס מוכר - אז מוצג רק הפלט הגולמי.
function FriendlyErrorHint(const ErrOutput: String): String;
var
  LowerOutput: String;
begin
  LowerOutput := Lowercase(ErrOutput);
  Result := '';
  if Pos('no space left on device', LowerOutput) > 0 then
    Result := CustomMessage('HintNoSpace')
  else if Pos('permission denied', LowerOutput) > 0 then
    Result := CustomMessage('HintPermission')
  else if Pos('sharing violation', LowerOutput) > 0 then
    Result := CustomMessage('HintSharing');
end;

procedure ExtractBundledDatabase(const ArchiveName, DatabaseName, TargetRoot: String);
var
  ArchivePath, DatabasePath, ZstdPath, Params, ErrOutput, Hint: String;
  ResultCode: Integer;
begin
  ArchivePath := ExpandConstant('{tmp}\' + ArchiveName);
  // ארכיון חסר = כשל (נמחק מ-{tmp} ע"י ניקוי דיסק וכד') — דילוג שקט השאיר
  // התקנה "מוצלחת" בלי ספרייה (issue #862).
  if not FileExists(ArchivePath) then
  begin
    Log('Bundled database archive not found: ' + ArchivePath);
    InstReportFailure(Msg1('DbArchiveMissing', ArchiveName), '', False);
    Abort;
  end;

  DatabasePath := TargetRoot + '\' + DatabaseName;
  ZstdPath := ExpandConstant('{tmp}\zstd.exe');

  ForceDirectories(ExtractFileDir(DatabasePath));

  Log('Extracting bundled database from ' + ArchivePath);
  Params := '-d -f -T0 --long=31 "' + ArchivePath + '" -o "' + DatabasePath + '"';

  if (not RunAndCaptureErrors(ZstdPath, Params, ResultCode, ErrOutput)) or (ResultCode <> 0) then
  begin
    Log('zstd database extraction failed (' + IntToStr(ResultCode) + '): ' + ErrOutput);
    Hint := FriendlyErrorHint(ErrOutput);
    if Hint <> '' then Hint := #13#10#13#10 + Hint;
    InstReportFailure(CustomMessage('DbExtractFailed') + Hint,
      Msg1('ExitCode', IntToStr(ResultCode)) + #13#10 + ErrOutput, True);
    Abort;
  end;

  DeleteFile(ArchivePath);
end;

procedure ExtractBundledTarArchive(const ArchiveName, TargetDirName, TargetRoot: String);
var
  ArchivePath, TarPath, ParentDir, TargetDir, ZstdPath, SevenZipPath, Params, ErrOutput, Hint: String;
  ResultCode: Integer;
begin
  ArchivePath := ExpandConstant('{tmp}\' + ArchiveName);
  if not FileExists(ArchivePath) then
  begin
    Log('Bundled archive not found: ' + ArchivePath);
    InstReportFailure(Msg1('ArchiveMissing', ArchiveName), '', False);
    Abort;
  end;

  ParentDir := TargetRoot;
  TarPath := ParentDir + '\' + ChangeFileExt(ArchiveName, '');
  TargetDir := TargetRoot + '\' + TargetDirName;
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
    InstReportFailure(CustomMessage('PdfExtractFailed') + Hint,
      Msg1('ExitCode', IntToStr(ResultCode)) + #13#10 + ErrOutput, True);
    Abort;
  end;

  Params := 'x -y "' + TarPath + '" "-o' + ParentDir + '"';
  if (not RunAndCaptureErrors(SevenZipPath, Params, ResultCode, ErrOutput)) or
     (ResultCode <> 0) then
  begin
    Log('7za PDF archive extraction failed (' + IntToStr(ResultCode) + '): ' + ErrOutput);
    Hint := FriendlyErrorHint(ErrOutput);
    if Hint <> '' then Hint := #13#10#13#10 + Hint;
    InstReportFailure(CustomMessage('PdfOpenFailed') + Hint,
      Msg1('ExitCode', IntToStr(ResultCode)) + #13#10 + ErrOutput, True);
    Abort;
  end;

  DeleteFile(TarPath);
  // בלי קובץ הגרסה בתיקייה, בדיקת העדכון הראשונה של האפליקציה מורידה את
  // התלמוד (~440MB) מחדש; ה-sha256 של הארכיון הוא ה-digest שהיא משווה מולו.
  // GetSHA256OfFile זורק חריגה על כשל קריאה — סימון חסר אינו מכשיל התקנה שהצליחה.
  try
    SaveStringToFile(TargetDir + '\.version',
      Lowercase(GetSHA256OfFile(ArchivePath)), False);
  except
    Log('Talmud version marker was not written: ' + GetExceptionMessage);
  end;
  DeleteFile(ArchivePath);
end;

// מחלץ את כל רכיבי הספרייה המשובצים לתיקיית staging, ומחליף את הספרייה
// הקיימת רק אחרי שהכל הצליח — כשל באמצע משאיר את הספרייה הישנה שלמה (issue #867).
procedure ExtractEmbeddedLibraryArchives();
var
  LibraryRoot, StagingBooks, BooksBackup: String;
  BooksBackedUp: Boolean;
begin
  LibraryRoot := ExtractFileDir(SelectedBooksPath);
  StagingBooks := LibraryRoot + '\.otzaria-books-staging';
  BooksBackup := LibraryRoot + '\.otzaria-books-backup';

  ForceDirectories(LibraryRoot);
  DelTree(StagingBooks, True, True, True);
  ForceDirectories(StagingBooks);

  WizardForm.StatusLabel.Caption := CustomMessage('StatusSeforim');
  WizardForm.StatusLabel.Update;
  ExtractBundledDatabase('seforim.db.zst', 'seforim.db', StagingBooks);

  WizardForm.StatusLabel.Caption := CustomMessage('StatusCatalog');
  WizardForm.StatusLabel.Update;
  ExtractBundledDatabase('otzar-HB_catalog.db.zst', 'otzar-HB_catalog.db',
    StagingBooks);

  WizardForm.StatusLabel.Caption := CustomMessage('StatusTalmud');
  WizardForm.StatusLabel.Update;
  ExtractBundledTarArchive('talmud_bavli_latest.tar.zst', 'תלמוד בבלי',
    StagingBooks);

  WizardForm.StatusLabel.Caption := CustomMessage('StatusLexical');
  WizardForm.StatusLabel.Update;
  ExtractBundledDatabase('lexical.db.zst', 'lexical.db', StagingBooks);
  // בלי קובץ הגרסה בדיקת העדכון הראשונה מורידה את המילון (~57MB) מחדש;
  // ה-sha256 של הקובץ הוא ה-digest של נכס ה-release שהאפליקציה משווה מולו.
  if FileExists(StagingBooks + '\lexical.db') then
  begin
    try
      SaveStringToFile(StagingBooks + '\lexical.db.version',
        Lowercase(GetSHA256OfFile(StagingBooks + '\lexical.db')), False);
    except
      Log('Lexical version marker was not written: ' + GetExceptionMessage);
    end;
  end;

  // אימות אחרון לפני ההחלפה: ספרייה בלי seforim.db אסור שתחליף ספרייה
  // קיימת ותוצג כהתקנה מוצלחת (issue #862).
  if not FileExists(StagingBooks + '\seforim.db') then
  begin
    Log('Staging library is missing seforim.db - aborting swap');
    InstReportFailure(CustomMessage('SeforimMissing'), '', False);
    Abort;
  end;

  WizardForm.StatusLabel.Caption := CustomMessage('StatusSwap');
  WizardForm.StatusLabel.Update;
  DelTree(BooksBackup, True, True, True);
  BooksBackedUp := (not DirExists(SelectedBooksPath)) or
    RenameFile(SelectedBooksPath, BooksBackup);
  if not BooksBackedUp then
  begin
    DelTree(StagingBooks, True, True, True);
    InstReportFailure(CustomMessage('BooksSwapFailed'), '', False);
    Abort;
  end;
  LibrarySwapStarted := True;
  if not RenameFile(StagingBooks, SelectedBooksPath) then
  begin
    if DirExists(BooksBackup) then
      RenameFile(BooksBackup, SelectedBooksPath);
    DelTree(StagingBooks, True, True, True);
    InstReportFailure(CustomMessage('BooksMoveFailed'), '', False);
    Abort;
  end;
  DelTree(BooksBackup, True, True, True);
end;

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

  Msg := CustomMessage('UninstallDeleteIntro');

  // אם יש נתיב ספרים מותאם והוא מזוהה כתיקיית אוצריא — נציג אותו במפורש.
  // אחרת לא מציינים נתיב חיצוני; תיקיית הספרים שתחת AppData ממילא נמחקת
  // כחלק מ-{userappdata}\otzaria / {commonappdata}\otzaria.
  if IsOtzariaBooksFolder(CustomPath) then
    Msg := Msg + Msg1('UninstallDeleteBooksAt', CustomPath)
  else
    Msg := Msg + CustomMessage('UninstallDeleteBooksDefault');

  Msg := Msg + CustomMessage('UninstallDeleteRest');

  if MsgBox(Msg, mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
  begin
    if MsgBox(CustomMessage('UninstallConfirmDelete'),
         mbCriticalError, MB_YESNO or MB_DEFBUTTON2) = IDYES then
      DeleteUserDataOnUninstall := True;
  end;
end;

// תיקיית ההתקנה של רשומת uninstall בהיקף הנתון — בלי לדרוש שהתיקייה קיימת.
function GetRegisteredInstallDir(RootKey: Integer): String;
begin
  if not RegQueryStringValue(RootKey, UninstallRegKey, 'Inno Setup: App Path', Result) then
    Result := '';
  if Result = '' then
    RegQueryStringValue(RootKey, UninstallRegKey, 'InstallLocation', Result);
end;

function SameInstallDir(PathA, PathB: String): Boolean;
begin
  Result := CompareText(RemoveBackslash(PathA), RemoveBackslash(PathB)) = 0;
end;

// מסיר התקנת אוצריא שנותרה רשומה בהיקף אחר (issue #886): רשומה בנתיב אחר
// מוסרת דרך ה-uninstaller שלה (מוחק גם קבצים וקיצורים שאחרת ימשיכו להריץ
// בינארי ישן); רשומה שמצביעה על {app} נמחקת מהרישום בלבד — הקבצים שלנו.
// /CROSSSCOPE מסמן ל-uninstaller שהוא הופעל מהיקף אחר — בלעדיו שני
// ה-uninstallers היו מנקים זה את רשומת זה ונתקעים זה על זה.
function IsCrossScopeUninstall(): Boolean;
begin
  Result := ExpandConstant('{param:CROSSSCOPE|0}') <> '0';
end;

// [Elevate] נדרש כשהרשומה שייכת להתקנת מנהל ואנחנו רצים כמשתמש רגיל —
// ה-uninstaller שלה דורש הגבהה, ו-Exec רגיל עליו נכשל.
procedure RemoveStaleScopeRegistration(RootKey: Integer; Elevate: Boolean);
var
  StaleDir, UninstallExe, Args: String;
  ResultCode: Integer;
  Started: Boolean;
begin
  if not RegKeyExists(RootKey, UninstallRegKey) then
    exit;

  StaleDir := GetRegisteredInstallDir(RootKey);
  if (StaleDir <> '') and
     (not SameInstallDir(StaleDir, ExpandConstant('{app}'))) and
     RegQueryStringValue(RootKey, UninstallRegKey, 'UninstallString', UninstallExe) then
  begin
    UninstallExe := RemoveQuotes(Trim(UninstallExe));
    Args := '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CROSSSCOPE=1';
    if FileExists(UninstallExe) then
    begin
      if Elevate then
        Started := ShellExec('runas', UninstallExe, Args, '',
          SW_HIDE, ewWaitUntilTerminated, ResultCode)
      else
        Started := Exec(UninstallExe, Args, '',
          SW_HIDE, ewWaitUntilTerminated, ResultCode);
      if Started then
      begin
        Log(Format('Removed stale install at %s (exit code %d)', [StaleDir, ResultCode]));
        exit;
      end;
    end;
  end;

  Log('Deleting stale uninstall registration for ' + StaleDir);
  RegDeleteKeyIncludingSubkeys(RootKey, UninstallRegKey);
end;

// התקנת מנהל מנקה רשומות שנותרו בהיקפים האחרים: HKCU (התקנת משתמש מקבילה,
// המצב של issue #886) ו-WOW6432Node (מתקיני מנהל 32-ביט ישנים). ההיקף
// הנגדי אינו מנוקה בהתקנת משתמש — מחיקה ב-HKLM דורשת הרשאות מנהל.
procedure RemoveOtherScopeInstalls();
begin
  if PortableMode then
    exit;
  if IsAdminInstallMode then
  begin
    RemoveStaleScopeRegistration(HKCU, False);
    RemoveStaleScopeRegistration(HKLM32, False);
  end
  else
  begin
    // הכיוון ההפוך (issue #1020): התקנת משתמש מעל התקנת מנהל השאירה עד
    // כה שתי רשומות מקבילות, והתוכנה הופיעה פעמיים.
    RemoveStaleScopeRegistration(HKLM64, True);
    RemoveStaleScopeRegistration(HKLM32, True);
  end;
end;

// אוצריא רושמת את otzaria:// גם ב-HKCU בכל הפעלה; בהתקנת מנהל המפתח הזה אינו
// של המתקין, ולכן נמחק רק כשהוא מצביע על {app} ולא על התקנה אחרת שנשארת.
procedure RemoveUserProtocolKeyIfOurs();
var
  ExePath: String;
begin
  if RegQueryStringValue(HKCU, 'Software\Classes\otzaria\DefaultIcon', '', ExePath) and
     SameInstallDir(ExtractFileDir(ExePath), ExpandConstant('{app}')) then
    RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Classes\otzaria');
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
    RemoveUserProtocolKeyIfOurs();
    if DeleteUserDataOnUninstall then
      DeleteAllUserData();
    // הסרה בהיקף אחד מסירה גם התקנה שנשארה בהיקף הנגדי (issue #1020).
    if not IsCrossScopeUninstall() then
    begin
      if IsAdminInstallMode then
        RemoveStaleScopeRegistration(HKCU, False)
      else
        RemoveStaleScopeRegistration(HKLM64, True);
    end;
  end;
end;


// איפוס הרסני לא רץ בשדרוג שקט מבחירה שנשמרה ברישום (issue #941) —
// בריצה שקטה הוא דורש /TASKS או /MERGETASKS מפורש בשורת הפקודה.
function ShouldResetSettings(): Boolean;
begin
  Result := WizardIsTaskSelected('resetsettings');
  if Result and WizardSilent then
    Result := Pos('resetsettings',
      Lowercase(ExpandConstant('{param:TASKS|}') + ' ' +
                ExpandConstant('{param:MERGETASKS|}'))) > 0;
end;

#include "installer_message_fallback.iss"

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

    if ShouldResetSettings() then
    begin
      // נקרא לפני מחיקת ה-prefs — מגן על ספרייה מותאמת שיושבת בתוך נתיב נמחק.
      ProtectedLibraryPath := RemoveBackslash(GetCustomLibraryPath());

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

      // נתיב ישן מאוד: LocalAppData בעברית (לפני גרסה 0.9.x) — גם כאן
      // גיבויים נשמרים; DelTree מלא מחק שם ספריות שלמות (issue #873).
      AppDataPath := ExpandConstant('{localappdata}\אוצריא');
      if DirExists(AppDataPath) then
        DelTreeExceptBackups(AppDataPath);
    end;
  end;

  if CurStep <> ssPostInstall then
    exit;

  // במצב נייד GetSelectedBooksPath מחזיר את הנתיב שבתוך התיקייה הניידת —
  // מיישרים את המשתנה כדי שכל החילוץ בהמשך ילך לשם.
  SelectedBooksPath := GetSelectedBooksPath('');

  // המשתמש בחר לדלג על חילוץ הספרייה: רק ה-marker נכתב, ומסך הפתיחה של
  // אוצריא יציע להצביע על הספרייה הקיימת.
  if PortableMode and PortableSkipLibrary then
  begin
    SaveStringToFile(ExpandConstant('{app}\portable.marker'), '', False);
    exit;
  end;

  ZstdPath := ExpandConstant('{tmp}\zstd.exe');
  SevenZipPath := ExpandConstant('{tmp}\7za.exe');

  if not FileExists(ZstdPath) then
  begin
    Log('zstd.exe not found - cannot extract bundled library');
    InstReportFailure(CustomMessage('ZstdMissing'), '', False);
    Abort;
  end;

  if not FileExists(SevenZipPath) then
  begin
    Log('7za.exe not found - cannot extract bundled PDF archive');
    InstReportFailure(CustomMessage('SevenZipMissing'), '', False);
    Abort;
  end;

  WizardForm.ProgressGauge.Style := npbstMarquee;

  ExtractEmbeddedLibraryArchives();

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

  RemoveOtherScopeInstalls();

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
Filename: "{tmp}\MicrosoftEdgeWebview2Setup.exe"; Parameters: "/silent /install"; StatusMsg: "{cm:InstallingWebView2}"; Flags: waituntilterminated; Check: ShouldInstallWV2
; בהתקנה שקטה ההשקה מתבצעת בקוד בסוף ssPostInstall (ראה CurStepChanged).
; runasoriginaluser: בלעדיו ההשקה מדף הסיום רצה מורמת ויוצרת את תיקיות הנתונים
; עם ACL של מנהל — WebView2 של התוספים נכשל אז בכתיבה (issue #1031).
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchApp}"; Flags: nowait postinstall skipifsilent runasoriginaluser

[Icons]
; שמות הקיצורים אינם מתורגמים: שדרוג בממשק אנגלי חייב לדרוס את אותם קבצים, לא ליצור כפולים.
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; AppUserModelID: "Otzaria.Otzaria"; Check: not IsPortableInstall
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon; AppUserModelID: "Otzaria.Otzaria"; Check: not IsPortableInstall
; קיצור דרך ישיר ללוח השנה — מעביר ל-otzaria.exe deep link כפרמטר; אוצריא מזהה
; ארגומנט שמתחיל ב-"otzaria:" וממסרת לראוטר הפנימי (ראה docs/deep_links.md לזרימה המלאה).
; AppUserModelID זהה לסמל הראשי כדי שהקיצור יתאחד עם הכפתור המוצמד בשורת המשימות.
Name: "{autodesktop}\לוח שנה - {#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Parameters: "otzaria://open/calendar"; Tasks: calendaricon; AppUserModelID: "Otzaria.Otzaria"; Check: not IsPortableInstall

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "calendaricon"; Description: "{cm:CalendarIconTask}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "resetsettings"; Description: "{cm:ResetSettingsTask}"; Flags: unchecked

[CustomMessages]
english.ResetSettingsTask=Reset user settings — warning: deletes personal notes, bookmarks, history and plugin data! (The backups folder is kept and the library is installed again. Needed only when upgrading from a version older than 0.9.80, or to fix problems)
hebrew.ResetSettingsTask=איפוס הגדרות משתמש — אזהרה: ימחק הערות אישיות, סימניות, היסטוריה ונתוני תוספים! (תיקיית הגיבויים נשמרת והספרייה מותקנת מחדש. נדרש רק בשדרוג מגרסה שקודמת ל-0.9.80, או לפתרון תקלות)

[Files]
; Copy DLL files without compression to prevent corruption
Source: "..\build\windows\{#AppArch}\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion nocompression
; ה-Excludes "*.dll" שלמטה חל על כל תת-תיקייה, ולכן ONNX Runtime נכלל כאן במפורש.
Source: "..\build\windows\{#AppArch}\runner\Release\onnxruntime\*.dll"; DestDir: "{app}\onnxruntime"; Flags: ignoreversion nocompression
; Copy all other app files
Source: "..\build\windows\{#AppArch}\runner\Release\*"; \
  Excludes: "*.dll"; \
    DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; ארכיוני התוספים שנארזו במתקין (ראה docs/bundled_plugins.md). התיקייה נוצרת
; ע"י ה-workflow ואינה קיימת בבנייה מקומית — skipifsourcedoesntexist.
Source: "bundled_plugins\*"; Excludes: "{#NetworkGatedPlugin}"; DestDir: "{app}\{#BundledPluginsDirName}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "bundled_plugins\{#NetworkGatedPlugin}"; DestDir: "{app}\{#BundledPluginsDirName}"; Flags: ignoreversion skipifsourcedoesntexist; Check: OtzariaSiteReachable

; Compressed library assets + extraction tools staged in the setup temp dir —
; {tmp} is always writable by the installer process (unlike {app} under Program Files)
; and is auto-deleted when setup exits, even on abort
Source: "library_db\seforim.db.zst"; DestDir: "{tmp}"; Flags: deleteafterinstall nocompression
Source: "library_db\otzar-HB_catalog.db.zst"; DestDir: "{tmp}"; Flags: deleteafterinstall nocompression
Source: "library_db\talmud_bavli_latest.tar.zst"; DestDir: "{tmp}"; Flags: deleteafterinstall nocompression
Source: "library_db\lexical.db.zst"; DestDir: "{tmp}"; Flags: deleteafterinstall nocompression
Source: "zstd.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "7za.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall
; התיקייה שמסייע ההורדה מכין לצד המתקין (semantic-import), ליד תיקיית הספרייה.
; האפליקציה מעבירה ממנה את הקבצים כשהחיפוש החכם מופעל, אחרי ההסכמה.
Source: "{src}\semantic-import\*"; DestDir: "{code:GetSemanticImportDir}"; \
  Flags: external recursesubdirs createallsubdirs skipifsourcedoesntexist ignoreversion uninsneveruninstall

; MicrosoftEdgeWebview2Setup.exe — bootstrapper קטן (~2MB) שמוריד ומתקין WebView2
; נדרש על ידי flutter_inappwebview_windows; ב-Win10/11 עם Edge עדכני — כבר קיים
Source: "MicrosoftEdgeWebview2Setup.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall; Check: ShouldInstallWV2

[INI]
Filename: "{app}\system_install.marker"; Section: "Install"; Key: "Mode"; String: "Admin"; Check: IsAdminInstallMode and not IsPortableInstall

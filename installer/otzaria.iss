; המתקין של אוצריא.
; שדרוג מגרסה 0.9.88 ומעלה מזוהה אוטומטית ומותקן ללא שאלות, עם חלון התקדמות.
; ההגדרות, קיצורי הדרך ונתיב ההתקנה הקודם נשמרים כפי שהם.
; התקנה חדשה או שדרוג מגרסה ישנה מקבלים את האשף המלא, בשכבת התצוגה של אוצריא
; (otzaria_ui_installer.iss). עמוד "איך להתקין" מציע שלוש אפשרויות: רק בשבילי
; (ברירת מחדל, ללא UAC), לכל המשתמשים (שיגור-מחדש מורם עם /ALLUSERS — מצב ההתקנה
; של Inno נקבע בעליית התהליך ולא ניתן להחלפה תוך כדי ריצה), וגרסה ניידת.
; בהתקנה ניידת (לכונן חיצוני): נכתב portable.marker ליד ה-EXE, כל הנתונים
; נשמרים ב-otzaria_data ליד התוכנה, ואין רישום במערכת — לא uninstaller,
; לא קיצורי דרך, לא PATH ולא פרוטוקול otzaria://. הפרמטר /PORTABLE פותח
; את האשף במצב נייד גם כשמותקנת כבר גרסה מודרנית (שאחרת הייתה משודרגת
; בשקט ללא אשף).

#define MyAppName "אוצריא"
#define MyAppVersion "0.9.98"
#define MyAppPublisher "sivan22"
#define MyAppURL "https://github.com/otzaria/otzaria"
#define MyAppExeName "otzaria.exe"
; חייב להתאים ל-AppPaths.bundledPluginsFolderName.
#define BundledPluginsDirName "bundled_plugins"
; חנות התוספים — מועתקת רק כשיש רשת (bundled_plugins_network_check.iss).
#define NetworkGatedPlugin "otzaria.plugins_directory.otzplugin"

; ארכיטקטורת היעד: "x64" (ברירת מחדל) או "arm64", נקבעת מבחוץ עם
; ‎ISCC /DAppArch=arm64‎. קובעת את תיקיית ה-build, את שם הקובץ ואת
; הגבלת הארכיטקטורה של המתקין.
#ifndef AppArch
  #define AppArch "x64"
#endif

; חלקי הספרייה ואינדקס החיפוש שמסייע ההורדה מכין לצד המתקין. ה-workflow מניח
; כאן את המניפסטים שלהם; בבנייה בלעדיהם המתקין אינו מכיר אותם כלל.
#if FileExists(AddBackslash(SourcePath) + "library.manifest.json")
  #define LibraryParts
  #define LibraryArchiveName "otzaria-" + MyAppVersion + "-library.tar.zst"
  #if FileExists(AddBackslash(SourcePath) + "library_index.manifest.json")
    #define LibraryIndexParts
    #define IndexArchiveName "otzaria-" + MyAppVersion + "-library-index.tar.zst"
  #endif
  #if FileExists(AddBackslash(SourcePath) + "zstd.exe") == 0
    #error zstd.exe must sit next to otzaria.iss to unpack the library parts
  #endif
  #if FileExists(AddBackslash(SourcePath) + "7za.exe") == 0
    #error 7za.exe must sit next to otzaria.iss to unpack the library parts
  #endif
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
OutputDir=.\
#if AppArch == "arm64"
; "_" ולא "-": הוא ממוין אחרי "-windows.exe", וגרסאות עד 0.9.96 בוחרות את ה-exe הראשון בשם.
OutputBaseFilename=otzaria-{#MyAppVersion}-windows_arm64
#else
OutputBaseFilename=otzaria-{#MyAppVersion}-windows
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
; לוג אוטומטי ל-%TEMP% של המשתמש המריץ — חיוני לאבחון עדכונים שקטים שנכשלים בשטח.
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

[Dirs]
; במצב נייד הנתונים יושבים ב-otzaria_data ליד ה-EXE — האפליקציה יוצרת אותה בעצמה.
Name: "{code:GetDataDir}"; Permissions: users-modify; Check: not IsPortableInstall
Name: "{code:GetDataDir}\books"; Permissions: users-modify; Check: not IsPortableInstall
Name: "{code:GetDataDir}\index"; Permissions: users-modify; Check: not IsPortableInstall

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "calendaricon"; Description: "{cm:CalendarIconTask}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "resetsettings"; Description: "{cm:ResetSettingsTask}"; Flags: unchecked

[CustomMessages]
english.ResetSettingsTask=Reset user settings — warning: deletes personal notes, bookmarks, history and plugin data! (The books and backups folders are kept. Needed only when upgrading from a version older than 0.9.80, or to fix problems)
hebrew.ResetSettingsTask=איפוס הגדרות משתמש — אזהרה: ימחק הערות אישיות, סימניות, היסטוריה ונתוני תוספים! (תיקיות הספרים והגיבויים נשמרות. נדרש רק בשדרוג מגרסה שקודמת ל-0.9.80, או לפתרון תקלות)

[Icons]
; שמות הקיצורים אינם מתורגמים: שדרוג בממשק אנגלי חייב לדרוס את אותם קבצים, לא ליצור כפולים.
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; AppUserModelID: "Otzaria.Otzaria"; Check: not IsPortableInstall
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon; AppUserModelID: "Otzaria.Otzaria"; Check: not IsPortableInstall
; קיצור דרך ישיר ללוח השנה — מעביר ל-otzaria.exe deep link כפרמטר; אוצריא מזהה
; ארגומנט שמתחיל ב-"otzaria:" וממסרת לראוטר הפנימי (ראה docs/deep_links.md לזרימה המלאה).
; AppUserModelID זהה לסמל הראשי כדי שהקיצור יתאחד עם הכפתור המוצמד בשורת המשימות.
Name: "{autodesktop}\לוח שנה - {#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Parameters: "otzaria://open/calendar"; Tasks: calendaricon; AppUserModelID: "Otzaria.Otzaria"; Check: not IsPortableInstall

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

[Run]
; אשף: הצעת הפעלה בדף הסיום. שקט: השקה ישירה — רשומת postinstall תלויה בדף
; הסיום שלא מוצג ב-VERYSILENT ולכן לא תרוץ שם לעולם. runasoriginaluser מונע
; הרצת אוצריא מורמת אחרי עדכון עם UAC. /NOLAUNCH=1 (מנגנון העדכון הפנימי,
; בעת התקנה בסגירת התוכנה) מדלג על ההשקה כדי שאוצריא לא תיפתח מחדש.
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchApp}"; Flags: nowait postinstall skipifsilent runasoriginaluser
Filename: "{app}\{#MyAppExeName}"; Flags: nowait runasoriginaluser; Check: ShouldLaunchAppAfterSilentInstall

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "hebrew"; MessagesFile: "compiler:Languages\Hebrew.isl"

; העיצוב של שכבת התצוגה ראשון ב-[Files]: עם SolidCompression הפתיחה אינה ממתינה לפריסת האפליקציה.
#define OtzariaUiProduct "installer"
#include "otzaria_ui_art.iss"

[Files]
#ifdef LibraryParts
; ראשונים בכוונה: ב-SolidCompression חילוץ קובץ זמני מפענח את כל מה שלפניו.
Source: "library.manifest.json"; Flags: dontcopy
#ifdef LibraryIndexParts
Source: "library_index.manifest.json"; Flags: dontcopy
#endif
Source: "read_split_manifest.ps1"; Flags: dontcopy
Source: "..\tool\release\assemble_split_asset.ps1"; Flags: dontcopy
Source: "zstd.exe"; Flags: dontcopy
Source: "7za.exe"; Flags: dontcopy
#endif
Source: "..\build\windows\{#AppArch}\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; ארכיוני התוספים שנארזו במתקין (ראה docs/bundled_plugins.md). התיקייה נוצרת
; ע"י ה-workflow ואינה קיימת בבנייה מקומית — skipifsourcedoesntexist.
Source: "bundled_plugins\*"; Excludes: "{#NetworkGatedPlugin}"; DestDir: "{app}\{#BundledPluginsDirName}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "bundled_plugins\{#NetworkGatedPlugin}"; DestDir: "{app}\{#BundledPluginsDirName}"; Flags: ignoreversion skipifsourcedoesntexist; Check: OtzariaSiteReachable
; נתוני החיפוש החכם שמסייע ההורדה מכין לצד המתקין, אל ליד תיקיית הספרייה.
Source: "{src}\semantic-import\*"; DestDir: "{code:GetSemanticImportDir}"; \
  Flags: external recursesubdirs createallsubdirs skipifsourcedoesntexist ignoreversion uninsneveruninstall

[INI]
Filename: "{app}\system_install.marker"; Section: "Install"; Key: "Mode"; String: "Admin"; Check: IsAdminInstallMode and not IsPortableInstall

; הליבה של שכבת התצוגה לפני כל הקוד: היא מגדירה את EnglishUi ואת UiTell/UiAsk.
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
  LibraryDatabasePathRecordFileName = 'library_database_path.txt';

var
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
  // אם המשתמש בחר במהלך ההסרה למחוק גם את כל הנתונים והספרים, לא רק את
  // קבצי האפליקציה. ברירת המחדל False — נשמר כדי לא לאבד נתונים בעדכון
  // שקט (Inno Setup מריץ את ה-uninstaller הישן עם /SILENT).
  DeleteUserDataOnUninstall: Boolean;
  // נתיב ספרייה מותאם מה-prefs; איפוס הגדרות מדלג עליו כדי לא למחוק ספרים.
  ProtectedLibraryPath: String;
#ifdef LibraryParts
  // הארכיונים שהורכבו ואומתו מהחלקים; ריק = אין (בלי ספרייה — התקנה רגילה).
  PreparedLibraryArchive, PreparedIndexArchive: String;
  LibraryNotInstalled: Boolean;
  // עמוד ההכנה (רק באשף) והארכיון שמורכב עכשיו, שההתקדמות נמדדת בגודלו.
  LibraryPrepPage: TOutputProgressWizardPage;
  LibraryPrepWhat, LibraryPrepArchive: String;
  LibraryPrepTotal: Int64;
#endif

// משמש גם את Uninstallable/CreateUninstallRegKey וגם רשומות Check.
function IsPortableInstall(): Boolean;
begin
  Result := PortableMode;
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

procedure InitializeWizard();
begin
  CreateInstallModeChoice();

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
  // בהתקנה שקטה המצב נקבע ב-InitializeSetup בלבד, ו-/DIR חייב להישמר.
  if not WizardSilent then
    ApplyInstallModeChoice();
#ifdef LibraryParts
  if not WizardSilent then
    LibraryPrepPage := CreateOutputProgressPage(CustomMessage('LibraryPrepTitle'),
      CustomMessage('LibraryPrepDesc'));
#endif
  UiInstallerInitializeWizard();
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  // שיגור-מחדש עם מצב מפורש (מעמוד "איך להתקין") — הפתיחה כבר הוצגה בריצה
  // הקודמת; ממשיכים ישר ל"איך להתקין", שבו הבחירה מסומנת ונבחרת התיקייה.
  Result :=
    (CmdLineParamExists('/ALLUSERS') or CmdLineParamExists('/CURRENTUSER')) and
    (PageID = wpWelcome);
  if Result then
    exit;
  // במצב נייד אין קיצורי דרך ואיפוס הגדרות — עמוד המשימות מיותר.
  Result := PortableMode and (PageID = wpSelectTasks);
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  UiCurPageChanged(CurPageID);
end;

procedure DeinitializeSetup();
begin
  UiDeinitializeSetup();
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
// הסיווג הוא לפי מיקום ידוע, לא לפי ניסיון כתיבה, כדי להימנע מ-false-positive
// בגלל AV / מנעולי קבצים / דיסק מלא.
function PathLikelyRequiresAdmin(PathDir: String): Boolean;
begin
  Result :=
    PathStartsWith(PathDir, ExpandConstant('{commonpf}')) or
    PathStartsWith(PathDir, ExpandConstant('{commonpf32}')) or
    PathStartsWith(PathDir, ExpandConstant('{commonpf64}'));
end;

// האם להפעיל את אוצריא בסיום התקנה שקטה (ראה הערה ב-[Run]).
function ShouldLaunchAppAfterSilentInstall(): Boolean;
begin
  Result := WizardSilent and (ExpandConstant('{param:NOLAUNCH|0}') <> '1');
#ifdef LibraryParts
  // רשומת [Run] רצה לפני ssPostInstall; עם ספרייה ההשקה היא אחרי הפריסה.
  Result := Result and (PreparedLibraryArchive = '');
#endif
end;

// פרמטרים שיש להעביר הלאה כשהמתקין משגר את עצמו מחדש ב-InitializeSetup,
// כדי ש-/NOLAUNCH=1 לא יאבד במעבר לריצה השקטה/המורמת. /PORTABLE בכוונה
// לא מועבר — כל מסלולי ה-/PORTABLE יוצאים לאשף לפני שיגור-מחדש כלשהו.
function PropagatedParams(): String;
begin
  Result := '';
  if ExpandConstant('{param:NOLAUNCH|0}') = '1' then
    Result := ' /NOLAUNCH=1';
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
// הדרך הקיימים נשמרים, והנתיב הקודם ידוע. מתקינים מיידית ברקע.
function IsUpgradeFromModernVersion(): Boolean;
var
  PreviousVersion: String;
begin
  PreviousVersion := GetPreviousDisplayVersion();
  Result := (PreviousVersion <> '') and VersionAtLeast(PreviousVersion, '0.9.88');
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

function GetLibraryBooksPath(): String; forward;

#ifdef LibraryParts
// מריץ קובץ ולוכד את הפלט שלו, כדי להציג בכשל את השגיאה האמיתית ולא רק קוד יציאה.
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

function ParseSplitManifestLine(const Line, ExpectedKind: String;
  var FileName: String): Boolean;
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
  Result := (FileName <> '') and
    (Length(Copy(Line, SecondSeparator + 1, Length(Line))) = 64);
end;

// שמות החלקים מהמניפסט המוטמע; שם הארכיון חייב להיות של גרסת המתקין.
function ReadSplitManifest(const ManifestPath, ExpectedArchive: String;
  var PartNames: TArrayOfString): Boolean;
var
  PowerShellPath, ParserPath, OutputPath, Params, CapturedOutput: String;
  ArchiveName: String;
  Lines: TArrayOfString;
  ResultCode, I: Integer;
begin
  Result := False;
  ExtractTemporaryFile('read_split_manifest.ps1');
  PowerShellPath := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  ParserPath := ExpandConstant('{tmp}\read_split_manifest.ps1');
  OutputPath := ManifestPath + '.txt';
  DeleteFile(OutputPath);
  Params := '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
    ParserPath + '" -ManifestPath "' + ManifestPath + '" -OutputPath "' +
    OutputPath + '"';

  if (not RunAndCaptureErrors(PowerShellPath, Params, ResultCode,
      CapturedOutput)) or (ResultCode <> 0) then
  begin
    Log('Split manifest parsing failed: ' + CapturedOutput);
    exit;
  end;
  if (not LoadStringsFromFile(OutputPath, Lines)) or
    (GetArrayLength(Lines) < 2) then
  begin
    Log('Split manifest parser returned no parts');
    exit;
  end;
  if not ParseSplitManifestLine(Lines[0], 'archive', ArchiveName) then
    exit;
  if CompareText(ArchiveName, ExpectedArchive) <> 0 then
  begin
    Log('Unexpected archive name: ' + ArchiveName);
    exit;
  end;

  SetArrayLength(PartNames, GetArrayLength(Lines) - 1);
  for I := 1 to GetArrayLength(Lines) - 1 do
    if not ParseSplitManifestLine(Lines[I], 'part', PartNames[I - 1]) then
      exit;
  Result := True;
end;

function LocalPartsAreComplete(const PartsDir: String;
  const PartNames: TArrayOfString): Boolean;
var
  I: Integer;
  PartPath: String;
begin
  Result := False;
  for I := 0 to GetArrayLength(PartNames) - 1 do
  begin
    PartPath := AddBackslash(PartsDir) + PartNames[I];
    if not FileExists(PartPath) then
    begin
      Log('Local part is missing: ' + PartPath);
      exit;
    end;
  end;
  Result := True;
end;

// מחבר את החלקים לארכיון אחד ב-{tmp} ומאמת כל חלק ואת הארכיון מול ה-SHA-256 שבמניפסט.
function AssembleSplitArchive(const ManifestPath, PartsDir,
  ArchivePath: String): Boolean;
var
  PowerShellPath, AssemblerPath, Params, CapturedOutput: String;
  ResultCode: Integer;
begin
  Result := False;
  ExtractTemporaryFile('assemble_split_asset.ps1');
  PowerShellPath := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  AssemblerPath := ExpandConstant('{tmp}\assemble_split_asset.ps1');
  DeleteFile(ArchivePath);
  // "E:\" בשורש כונן היה הופך את ה-\" למרכאה מילולית; "E:\." שקול ובטוח.
  Params := '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
    AssemblerPath + '" "' + ManifestPath + '" "' + ArchivePath + '" "' +
    AddBackslash(PartsDir) + '."';

  if (not RunAndCaptureErrors(PowerShellPath, Params, ResultCode,
      CapturedOutput)) or (ResultCode <> 0) then
  begin
    Log('Archive assembly failed: ' + CapturedOutput);
    DeleteFile(ArchivePath);
    exit;
  end;
  Result := True;
end;

// מאמת ומרכיב ארכיון אחד ([What] — שמו למשתמש); כשל מוצג ועוצר את ההתקנה.
function PrepareSplitArchive(const ManifestFile, ArchiveName, What,
  SourceDir: String; var ArchivePath: String): Boolean;
var
  ManifestPath: String;
  PartNames: TArrayOfString;
begin
  Result := False;
  ExtractTemporaryFile(ManifestFile);
  ManifestPath := ExpandConstant('{tmp}\') + ManifestFile;
  if not ReadSplitManifest(ManifestPath, ArchiveName, PartNames) then
  begin
    InstTellSuppressible(CustomMessage('LibraryPartsTitle'),
      Msg1('LibraryManifestInvalid', What));
    exit;
  end;
  if not LocalPartsAreComplete(SourceDir, PartNames) then
  begin
    InstTellSuppressible(CustomMessage('LibraryPartsTitle'),
      Msg1('LibraryPartsMissing', What));
    exit;
  end;
  UiLibraryPrepStart(What, ExpandConstant('{tmp}\') + ArchiveName, SourceDir, PartNames);
  if not AssembleSplitArchive(ManifestPath, SourceDir,
    ExpandConstant('{tmp}\') + ArchiveName) then
  begin
    InstTellSuppressible(CustomMessage('LibraryPartsTitle'),
      Msg1('LibraryPartsCorrupt', What));
    exit;
  end;
  ArchivePath := ExpandConstant('{tmp}\') + ArchiveName;
  Result := True;
end;

function HasSplitArchiveParts(const SourceDir, ArchiveName: String): Boolean;
var
  FindRec: TFindRec;
begin
  Result := FindFirst(AddBackslash(SourceDir) + ArchiveName + '.part-*', FindRec);
  if Result then
    FindClose(FindRec);
end;

// חלקי ספרייה או אינדקס של גרסה אחרת: שמם כולל את הגרסה, ולכן אינם נפרסים.
function OtherVersionPartsName(const SourceDir: String): String;
var
  FindRec: TFindRec;
begin
  Result := '';
  if FindFirst(AddBackslash(SourceDir) + 'otzaria-*-library*.tar.zst.part-*', FindRec) then
  try
    repeat
      if (Pos(Lowercase('{#LibraryArchiveName}.part-'), Lowercase(FindRec.Name)) <> 1) and
        (Pos(Lowercase('otzaria-{#MyAppVersion}-library-index.tar.zst.part-'), Lowercase(FindRec.Name)) <> 1) then
      begin
        Result := FindRec.Name;
        exit;
      end;
    until not FindNext(FindRec);
  finally
    FindClose(FindRec);
  end;
end;

// בלי חלקי ספרייה לצד המתקין זו התקנה רגילה: בלי PowerShell.
function PrepareLibraryParts(): Boolean;
var
  OtherParts: String;
var
  SourceDir: String;
begin
  Result := True;
  if PreparedLibraryArchive <> '' then
    exit;
  SourceDir := ExtractFileDir(ExpandConstant('{srcexe}'));
  if not HasSplitArchiveParts(SourceDir, '{#LibraryArchiveName}') then
  begin
#ifdef LibraryIndexParts
    // המסייע מוריד אינדקס רק עם הספרייה; אינדקס לבד אינו מותאם בהכרח לספרייה המותקנת.
    if HasSplitArchiveParts(SourceDir, '{#IndexArchiveName}') then
      Log('Search index parts without library parts are ignored');
#endif
    OtherParts := OtherVersionPartsName(SourceDir);
    if OtherParts <> '' then
    begin
      Log('Library parts of another version next to the installer: ' + OtherParts);
      // בהתקנה שקטה עוצרים: מי שהכין ספרייה לא מצפה להתקנה בלעדיה.
      Result := InstAskYesNoSuppressible(CustomMessage('OtherVersionPartsTitle'),
        Msg1('OtherVersionParts', UiDialogPath(OtherParts)), IDNO);
    end;
    exit;
  end;

  Result := False;
  Log('Library parts found next to the installer');
#if AppArch == "arm64"
  // zstd ו-7za שבמתקין הם x64, ו-Windows 10 על ARM מאמלץ רק x86.
  if GetWindowsVersion < $0A0055F0 then
  begin
    InstTellSuppressible(CustomMessage('LibraryPartsTitle'), CustomMessage('LibraryPartsArmWin10'));
    exit;
  end;
#endif
  if LibraryPrepPage <> nil then
    LibraryPrepPage.Show;
  try
    Result := PrepareSplitArchive('library.manifest.json',
      '{#LibraryArchiveName}', CustomMessage('LibraryWhat'), SourceDir, PreparedLibraryArchive);
#ifdef LibraryIndexParts
    if Result and HasSplitArchiveParts(SourceDir, '{#IndexArchiveName}') then
      Result := PrepareSplitArchive('library_index.manifest.json',
        '{#IndexArchiveName}', CustomMessage('IndexWhat'), SourceDir, PreparedIndexArchive);
#endif
  finally
    if LibraryPrepPage <> nil then
      LibraryPrepPage.Hide;
  end;
  if not Result then
  begin
    if PreparedLibraryArchive <> '' then
      DeleteFile(PreparedLibraryArchive);
    PreparedLibraryArchive := '';
  end;
end;
#endif

procedure WarnPortableProtectedDir();
begin
  InstTell(CustomMessage('PortableProtectedTitle'), CustomMessage('PortableProtected'),
    mbError);
end;

// "הבא" ב"איך להתקין" (wpSelectDir, אחרי הבדיקות של Inno לתיקייה): במעבר בין
// משתמש-נוכחי לכל-המשתמשים — שיגור-מחדש במצב ההתקנה המתאים (מצב ההתקנה של Inno
// נקבע בעליית התהליך ולא ניתן להחלפה תוך כדי ריצה).
// בהתקנה שקטה Inno "מדפדף" בין העמודים ומפעיל גם את הפונקציה הזו — שם
// אסור לגעת בכלום: המצב כבר נקבע ב-InitializeSetup ו-/DIR חייב להישמר.
function NextButtonClick(CurPageID: Integer): Boolean;
var
  ResultCode: Integer;
  Launched: Boolean;
  HasLibraryPayload: Boolean;
begin
  Result := True;
  // גם בהתקנה שקטה עם /DIR: False עוצר כאן, לפני שנכתב קובץ כלשהו.
  if (CurPageID = wpSelectDir) and InstallDirTooLong() then
  begin
    Result := False;
    exit;
  end;
  if CurPageID = wpReady then
  begin
    HasLibraryPayload := DirExists(ExpandConstant('{src}\semantic-import'));
#ifdef LibraryParts
    HasLibraryPayload := HasLibraryPayload or HasSplitArchiveParts(
      ExtractFileDir(ExpandConstant('{srcexe}')), '{#LibraryArchiveName}');
#endif
    if HasLibraryPayload and (GetLibraryBooksPath() = '') then
    begin
      InstTellSuppressible(CustomMessage('LibraryPartsTitle'), CustomMessage('UnsafeLibraryRoot'));
      Result := False;
      exit;
    end;
  end;
#ifdef LibraryParts
  // גם בהתקנה שקטה Inno "לוחץ" Next כאן, ו-False עוצר אותה לפני תחילת ההתקנה.
  if CurPageID = wpReady then
  begin
    Result := PrepareLibraryParts();
    exit;
  end;
#endif
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

  if (CurPageID <> wpSelectDir) or not ModeChangeNeedsRelaunch() then
    exit;

  if AllUsersModeRadio.Checked then
  begin
    // בכוונה בלי PropagatedParams: העברת /PORTABLE הייתה מסמנת שוב את
    // המצב הנייד במופע החדש ודורסת את הבחירה המפורשת של המשתמש.
    if IsAdmin then
      // התהליך כבר מורם אבל במצב משתמש — שיגור-מחדש עם /ALLUSERS, בלי UAC.
      Launched := RelaunchSetup('open', '/ALLUSERS', SW_SHOWNORMAL, ResultCode)
    else
      Launched := RelaunchSetupElevated('/ALLUSERS', SW_SHOWNORMAL, ResultCode);

    if Launched then
    begin
      // UiClosing: הסגירה אינה שואלת "לצאת?" גם בשכבת התצוגה.
      RelaunchingForModeChange := True;
      UiClosing := True;
      WizardForm.Close;
    end
    else
      InstTell(CustomMessage('AdminNeededTitle'), CustomMessage('AllUsersRelaunchFailed'),
        mbError);
    Result := False;
    exit;
  end;

  // התהליך כבר במצב מנהל — חזרה להתקנת משתמש דורשת שיגור-מחדש.
  Launched := RelaunchSetup('open', '/CURRENTUSER', SW_SHOWNORMAL, ResultCode);
  if Launched then
  begin
    RelaunchingForModeChange := True;
    UiClosing := True;
    WizardForm.Close;
  end
  else
    InstTell(CustomMessage('ModeChangeFailedTitle'),
      CustomMessage('CurrentUserRelaunchFailed'), mbError);
  Result := False;
end;

procedure CancelButtonClick(CurPageID: Integer; var Cancel, Confirm: Boolean);
begin
  // סגירה לטובת שיגור-מחדש במצב אחר — בלי שאלת "האם לבטל את ההתקנה?".
  if RelaunchingForModeChange then
    Confirm := False;
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

  if WizardSilent then
  begin
    // התקנה ניידת שקטה (‎/VERYSILENT /PORTABLE /DIR=...‎): המצב נקבע כאן כי
    // NextButtonClick לא רץ בהתקנה שקטה. /DIR חובה — בלעדיו ברירת המחדל היא
    // תיקיית ההתקנה הרגילה הקיימת, וה-marker היה הופך אותה לניידת.
    PortableMode := CmdLineParamExists('/PORTABLE') and
      (ExpandConstant('{param:DIR|}') <> '');
    exit;
  end;
  // כבר שוגרנו מחדש עם מצב התקנה מפורש — ממשיכים ישירות (מונע לולאת שיגור).
  if CmdLineParamExists('/ALLUSERS') or CmdLineParamExists('/CURRENTUSER') then
    exit;
  // ‎/PORTABLE — ישר לאשף במצב נייד: בלי שדרוג שקט (המשתמש רוצה עותק נייד,
  // לא עדכון של ההתקנה הקיימת) ובלי הסלמת הרשאות (אין כתיבה לנתיב מוגן).
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
        '/SILENT /SUPPRESSMSGBOXES /NORESTART /ALLUSERS' + PropagatedParams(),
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
         '/SILENT /SUPPRESSMSGBOXES /NORESTART ' + PrivilegeFlag +
         PropagatedParams(),
         SW_SHOWNORMAL, ResultCode);

    if Launched then
    begin
      // השיגור הצליח — יוצאים מהריצה הנוכחית בשקט (Result := False
      // יוצא ללא הודעת ביטול), והעותק השקט ימשיך מכאן.
      Result := False;
      exit;
    end;

    // השיגור מחדש נכשל לחלוטין — אל תיצא בשקט (אחרת המשתמש מקבל no-op
    // בלי שום פידבק). ממשיכים בתהליך הנוכחי עם האשף המלא.
    exit;
  end;

  // התקנה חדשה או שדרוג מגרסה ישנה — אשף מלא. הבחירה בין משתמש-נוכחי /
  // כל-המשתמשים / ניידת נעשית בעמוד "איך להתקין" (כשהתהליך מורם העמוד
  // מסומן מראש על כל-המשתמשים והשיגור-מחדש משם עובר ללא UAC).
  if (not IsAdmin) and RequiresAdmin then
  begin
    // ההתקנה הקודמת (הישנה) בנתיב מוגן — אשף מורם עם UAC.
    Launched := RelaunchSetupElevated('/ALLUSERS' + PropagatedParams(),
      SW_SHOWNORMAL, ResultCode);
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

// משמר את books (הספרייה) ואת backups — כדי שקובצי גיבוי ישרדו איפוס
// ויאפשרו שחזור הערות/סימניות/נתוני תוספים דרך "שחזור מגיבוי".
procedure DelTreeExceptBooksAndBackups(Path: String);
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
            if (Lowercase(FindRec.Name) <> 'books') and
               (Lowercase(FindRec.Name) <> 'backups') and
               ((ProtectedLibraryPath = '') or
                (Lowercase(ChildPath) <> Lowercase(ProtectedLibraryPath))) then
            begin
              DelTreeExceptBooksAndBackups(ChildPath);
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

// קריאת shared_preferences.json לקובץ טקסט אחד; משמש לחילוץ נתיב הספרים
// המותאם אישית של המשתמש לפני שמוחקים את ספריית הנתונים.
function UninstallReadTextFile(const FileName: String): String;
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

// ה-root נשאר נפרד מתיקיית ה-DB כדי לשמר את נתיבי האינדקס וההסרה.
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
  Result := Trim(UninstallReadTextFile(RecordFile));
  if (Result <> '') and (Result[1] = #$FEFF) then
    Delete(Result, 1, 1);
end;

function ReadLibraryPreference(const KeyName: String): String;
var
  PrefsFile, JsonContent, KeyStr, Value: String;
  KeyPos, ValueStart, ValueEnd: Integer;
begin
  Result := '';
  PrefsFile := ExpandConstant('{userappdata}\otzaria\shared_preferences.json');
  if not FileExists(PrefsFile) then
    exit;

  JsonContent := UninstallReadTextFile(PrefsFile);
  if JsonContent = '' then
    exit;

  KeyStr := '"flutter.' + KeyName + '":';
  KeyPos := Pos(KeyStr, JsonContent);
  if KeyPos = 0 then
  begin
    KeyStr := '"' + KeyName + '":';
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

  ValueEnd := ValueStart;
  while ValueEnd <= Length(JsonContent) do
  begin
    if (JsonContent[ValueEnd] = '"') and (JsonContent[ValueEnd - 1] <> '\') then
      Break;
    ValueEnd := ValueEnd + 1;
  end;
  if ValueEnd > Length(JsonContent) then
    exit;

  Value := Copy(JsonContent, ValueStart, ValueEnd - ValueStart);
  // ביטול escapes בסיסיים שנכתבו ע"י EscapeJsonString במתקין FULL.
  StringChangeEx(Value, '\\', '\', True);
  StringChangeEx(Value, '\"', '"', True);
  Result := Value;
end;

function GetCustomLibraryPath(): String;
begin
  Result := ReadLibraryPathRecord(ExpandConstant('{userappdata}\otzaria'));
  if Result = '' then
    Result := ReadLibraryPreference('key-library-path');
end;

function NormalizeLibraryPath(Path: String): String;
begin
  StringChangeEx(Path, '/', '\', True);
  Result := RemoveBackslash(Path);
end;

function IsSafeLibraryDirectory(const Path: String): Boolean;
var
  Drive: String;
begin
  Drive := ExtractFileDrive(Path);
  Result := (Length(Path) >= 6) and (Drive <> '') and
    (Pos(Lowercase(AddBackslash(Drive)), Lowercase(Path)) = 1);
end;

// סמני ספרייה נדרשים לפני DelTree כדי להגן על תיקייה אישית רחבה
// שנבחרה בטעות כנתיב ספרים.
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

// רשומות ישנות מכילות רק root; בלי הגדרה מפורשת מותר לאמץ רק DB יחיד.
function GetLibraryBooksPath(): String;
var
  CustomPath, RecordedPath, DatabasePath, FolderName, Candidate: String;
  CandidateCount: Integer;
  FindRec: TFindRec;
begin
  if PortableMode then
  begin
    Result := ExpandConstant('{app}') + '\otzaria_data\books';
    exit;
  end;
  RecordedPath := ReadLibraryPathRecord(GetDataDir(''));
  if RecordedPath = '' then
    RecordedPath := ReadLibraryPathRecord(ExpandConstant('{userappdata}\otzaria'));
  CustomPath := NormalizeLibraryPath(RecordedPath);
  if CustomPath = '' then
    CustomPath := NormalizeLibraryPath(GetCustomLibraryPath());
  Result := GetDataDir('') + '\books';
  if CustomPath = '' then
    exit;
  if not IsSafeLibraryDirectory(CustomPath) then
  begin
    Result := '';
    exit;
  end;
  DatabasePath := Trim(UninstallReadTextFile(AddBackslash(GetDataDir('')) +
    LibraryDatabasePathRecordFileName));
  if (DatabasePath <> '') and (DatabasePath[1] = #$FEFF) then
    Delete(DatabasePath, 1, 1);
  DatabasePath := NormalizeLibraryPath(DatabasePath);
  if FileExists(AddBackslash(DatabasePath) + 'seforim.db') and
    ((CompareText(DatabasePath, CustomPath) = 0) or
    (Pos(Lowercase(AddBackslash(CustomPath)), Lowercase(DatabasePath)) = 1)) then
  begin
    Result := DatabasePath;
    exit;
  end;
  // prefs נטושים אינם רשאים לבחור folderName מול רשומת Hive עדכנית.
  if (RecordedPath = '') and
    (CompareText(NormalizeLibraryPath(ReadLibraryPreference('key-library-path')),
    CustomPath) = 0) then
  begin
    FolderName := ReadLibraryPreference('key-library-folder-name');
    if FolderName <> '' then
    begin
      DatabasePath := NormalizeLibraryPath(AddBackslash(CustomPath) + FolderName);
      if (Pos(Lowercase(AddBackslash(CustomPath)), Lowercase(DatabasePath)) = 1) and
        (Pos('..', FolderName) = 0) and
        FileExists(AddBackslash(DatabasePath) + 'seforim.db') then
      begin
        Result := DatabasePath;
        exit;
      end;
    end;
  end;
  CandidateCount := 0;
  if IsOtzariaBooksFolder(CustomPath) then
    Result := CustomPath;
  if FileExists(AddBackslash(CustomPath) + 'seforim.db') then
    CandidateCount := 1;
  if FindFirst(AddBackslash(CustomPath) + '*', FindRec) then
  try
    repeat
      if ((FindRec.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0) and
        (FindRec.Name <> '.') and (FindRec.Name <> '..') and
        FileExists(AddBackslash(CustomPath) + FindRec.Name + '\seforim.db') then
      begin
        Candidate := AddBackslash(CustomPath) + FindRec.Name;
        CandidateCount := CandidateCount + 1;
      end;
    until not FindNext(FindRec);
  finally
    FindClose(FindRec);
  end;
  if (CandidateCount = 1) and (Candidate <> '') then
    Result := Candidate;
  if CandidateCount > 1 then
    Result := '';
end;

// האינדקס נצמד ל-root המוגדר; SemanticPaths נצמד להורה של ה-DB.
function GetLibraryIndexPath(const BooksPath: String): String;
var
  CustomPath: String;
begin
  CustomPath := NormalizeLibraryPath(GetCustomLibraryPath());
  if PortableMode then
    Result := ExtractFileDir(BooksPath) + '\index'
  else if IsAdminInstallMode then
    Result := GetDataDir('') + '\index'
  else if (CustomPath <> '') and ((CompareText(BooksPath, CustomPath) = 0) or
    (Pos(Lowercase(AddBackslash(CustomPath)), Lowercase(BooksPath)) = 1)) then
    Result := ExtractFileDir(CustomPath) + '\index'
  else
    Result := ExtractFileDir(BooksPath) + '\index';
end;

// ההורה של תיקיית הספרייה הוא SemanticPaths.root באפליקציה.
function GetSemanticImportDir(Param: String): String;
begin
  Result := ExtractFileDir(GetLibraryBooksPath()) + '\semantic-import';
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

#ifdef LibraryParts
// ממפה שגיאות נפוצות של zstd/7za (תמיד באנגלית) להסבר קצר; '' כשלא זוהו.
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

procedure LibraryInstallFailed(const Message, ErrOutput: String);
var
  Hint: String;
begin
  Log('Library was not installed: ' + Message + ' ' + ErrOutput);
  LibraryNotInstalled := True;
  Hint := FriendlyErrorHint(ErrOutput);
  if Hint <> '' then
    Hint := #13#10#13#10 + Hint;
  InstReportLibraryFailure(Message + ' ' + CustomMessage('LibraryNotInstalled') + Hint,
    ErrOutput);
end;

// עם /SUPPRESSMSGBOXES ההודעה נבלעת; קוד היציאה מסמן שהתוכנה הותקנה והספרייה לא.
function GetCustomSetupExitCode(): Integer;
begin
  Result := 0;
  if LibraryNotInstalled then
    Result := 9;
end;

// zstd ואז 7za אל [Dest]. כל ארכיון נמחק מיד אחרי שנפתח, כדי לפנות מקום.
function UnpackArchive(const ArchivePath, Dest: String;
  var ErrOutput: String): Boolean;
var
  TarPath, Params: String;
  ResultCode: Integer;
begin
  Result := False;
  TarPath := ExpandConstant('{tmp}\otzaria-library.tar');
  DeleteFile(TarPath);
  Params := '-d -f -T0 "' + ArchivePath + '" -o "' + TarPath + '"';
  if (not RunAndCaptureErrors(ExpandConstant('{tmp}\zstd.exe'), Params,
      ResultCode, ErrOutput)) or (ResultCode <> 0) then
  begin
    DeleteFile(TarPath);
    exit;
  end;
  DeleteFile(ArchivePath);
  Params := 'x -y "' + TarPath + '" "-o' + Dest + '"';
  Result := RunAndCaptureErrors(ExpandConstant('{tmp}\7za.exe'), Params,
    ResultCode, ErrOutput) and (ResultCode = 0);
  DeleteFile(TarPath);
end;

// מחליף את books (ואת index הצמודה, כשהוכן אינדקס) רק אחרי חילוץ מלא ל-staging;
// כשל משאיר את הקיימים. בלי אינדקס — index הקיימת אינה נוגעת, כמו במתקין ה-FULL.
procedure ExtractLibraryArchives(const BooksPath: String);
var
  LibraryRoot, StagingRoot, IndexStagingRoot, SourceBooks, SourceIndex, TargetIndex: String;
  BooksBackup, IndexBackup, ErrOutput: String;
  WithIndex, BooksBackedUp, IndexBackedUp, NewBooksMoved: Boolean;
begin
  WithIndex := PreparedIndexArchive <> '';
  LibraryRoot := ExtractFileDir(BooksPath);
  StagingRoot := LibraryRoot + '\.otzaria-library-install';
  SourceBooks := StagingRoot + '\books';
  TargetIndex := GetLibraryIndexPath(BooksPath);
  IndexStagingRoot := ExtractFileDir(TargetIndex) + '\.otzaria-index-install';
  SourceIndex := IndexStagingRoot + '\index';
  BooksBackup := LibraryRoot + '\.otzaria-books-backup';
  IndexBackup := TargetIndex + '.otzaria-install-backup';
  ExtractTemporaryFile('zstd.exe');
  ExtractTemporaryFile('7za.exe');

  ForceDirectories(LibraryRoot);
  DelTree(StagingRoot, True, True, True);
  ForceDirectories(StagingRoot);
  // גם כשספרים ואינדקס בכוננים שונים, ההחלפה נעשית ב-rename באותו כונן.
  if WithIndex then
  begin
    DelTree(IndexStagingRoot, True, True, True);
    ForceDirectories(IndexStagingRoot);
  end;

  if not UnpackArchive(PreparedLibraryArchive, StagingRoot, ErrOutput) then
  begin
    DelTree(StagingRoot, True, True, True);
    if WithIndex then
      DelTree(IndexStagingRoot, True, True, True);
    LibraryInstallFailed(CustomMessage('LibraryExtractFailed'), ErrOutput);
    exit;
  end;
  if WithIndex and not UnpackArchive(PreparedIndexArchive, IndexStagingRoot,
    ErrOutput) then
  begin
    DelTree(StagingRoot, True, True, True);
    if WithIndex then
      DelTree(IndexStagingRoot, True, True, True);
    LibraryInstallFailed(CustomMessage('IndexExtractFailed'), ErrOutput);
    exit;
  end;

  if (not FileExists(SourceBooks + '\seforim.db')) or (WithIndex and
    not FileExists(SourceIndex + '\.otzaria_prebuilt_index')) then
  begin
    DelTree(StagingRoot, True, True, True);
    if WithIndex then
      DelTree(IndexStagingRoot, True, True, True);
    LibraryInstallFailed(CustomMessage('LibraryPackageInvalid'), '');
    exit;
  end;

  DelTree(BooksBackup, True, True, True);
  DelTree(IndexBackup, True, True, True);
  BooksBackedUp := (not DirExists(BooksPath)) or
    RenameFile(BooksPath, BooksBackup);
  if not BooksBackedUp then
  begin
    DelTree(StagingRoot, True, True, True);
    if WithIndex then
      DelTree(IndexStagingRoot, True, True, True);
    LibraryInstallFailed(CustomMessage('BooksSwapFailed'), '');
    exit;
  end;
  IndexBackedUp := (not WithIndex) or (not DirExists(TargetIndex)) or
    RenameFile(TargetIndex, IndexBackup);
  if not IndexBackedUp then
  begin
    if DirExists(BooksBackup) then
      RenameFile(BooksBackup, BooksPath);
    DelTree(StagingRoot, True, True, True);
    if WithIndex then
      DelTree(IndexStagingRoot, True, True, True);
    LibraryInstallFailed(CustomMessage('IndexSwapFailed'), '');
    exit;
  end;

  NewBooksMoved := RenameFile(SourceBooks, BooksPath);
  if (not NewBooksMoved) or
    (WithIndex and not RenameFile(SourceIndex, TargetIndex)) then
  begin
    if NewBooksMoved then
      DelTree(BooksPath, True, True, True);
    if WithIndex and DirExists(TargetIndex) then
      DelTree(TargetIndex, True, True, True);
    if DirExists(BooksBackup) then
      RenameFile(BooksBackup, BooksPath);
    if DirExists(IndexBackup) then
      RenameFile(IndexBackup, TargetIndex);
    DelTree(StagingRoot, True, True, True);
    if WithIndex then
      DelTree(IndexStagingRoot, True, True, True);
    LibraryInstallFailed(CustomMessage('LibraryMoveFailed'), '');
    exit;
  end;

  DelTree(BooksBackup, True, True, True);
  DelTree(IndexBackup, True, True, True);
  DelTree(StagingRoot, True, True, True);
  if WithIndex then
    DelTree(IndexStagingRoot, True, True, True);
end;

// ב-ssPostInstall, אחרי ש-[Dirs] נתנה למשתמשים הרשאה על תיקיית הנתונים.
procedure InstallPreparedLibrary();
var
  ResultCode: Integer;
begin
  if PreparedLibraryArchive = '' then
    exit;
  if PreparedIndexArchive <> '' then
    WizardForm.StatusLabel.Caption := CustomMessage('StatusLibraryIndex')
  else
    WizardForm.StatusLabel.Caption := CustomMessage('StatusLibrary');
  WizardForm.StatusLabel.Update;
  WizardForm.ProgressGauge.Style := npbstMarquee;
  try
    ExtractLibraryArchives(GetLibraryBooksPath());
  finally
    WizardForm.ProgressGauge.Style := npbstNormal;
  end;
  if WizardSilent and (ExpandConstant('{param:NOLAUNCH|0}') <> '1') then
    ExecAsOriginalUser(ExpandConstant('{app}\{#MyAppExeName}'), '',
      ExpandConstant('{app}'), SW_SHOWNORMAL, ewNoWait, ResultCode);
end;
#endif

#include "installer_message_fallback.iss"

procedure CurStepChanged(CurStep: TSetupStep);
var
  AppDataPath: string;
  ErrorLogPath: string;
begin
  if CurStep = ssPostInstall then
  begin
    // קובץ ה-marker מפעיל את המצב הנייד באפליקציה: כל הנתונים נשמרים
    // ב-otzaria_data ליד ה-EXE (ראה lib/core/app_paths.dart → isPortable).
    if PortableMode then
      SaveStringToFile(ExpandConstant('{app}\portable.marker'), '', False);
    RemoveOtherScopeInstalls();
#ifdef LibraryParts
    InstallPreparedLibrary();
#endif
    exit;
  end;

  if CurStep <> ssInstall then
    exit;

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
      DelTreeExceptBooksAndBackups(AppDataPath);

    AppDataPath := ExpandConstant('{userappdata}\otzaria');
    if DirExists(AppDataPath) then
      DelTreeExceptBooksAndBackups(AppDataPath);

    AppDataPath := ExpandConstant('{commonappdata}\otzaria');
    if DirExists(AppDataPath) then
      DelTreeExceptBooksAndBackups(AppDataPath);

    AppDataPath := ExpandConstant('{localappdata}\otzaria');
    if DirExists(AppDataPath) then
      DelTreeExceptBooksAndBackups(AppDataPath);

    // com.example הוא מזהה ברירת המחדל של Flutter — רק תת-תיקיית otzaria
    // שייכת לנו; מחיקת כל com.example תמחק נתונים של אפליקציות אחרות.
    AppDataPath := ExpandConstant('{userappdata}\com.example\otzaria');
    if DirExists(AppDataPath) then
      DelTreeExceptBooksAndBackups(AppDataPath);

    // נתיב ישן מאוד: LocalAppData בעברית (לפני גרסה 0.9.x) — גם כאן ספרים
    // וגיבויים נשמרים; DelTree מלא מחק שם ספריות שלמות (issue #873).
    AppDataPath := ExpandConstant('{localappdata}\אוצריא');
    if DirExists(AppDataPath) then
      DelTreeExceptBooksAndBackups(AppDataPath);
  end;
end;

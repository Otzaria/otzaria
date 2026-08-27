; המתקין של אוצריא.
; שדרוג מגרסה 0.9.88 ומעלה מזוהה אוטומטית ומותקן ללא שאלות, עם חלון התקדמות.
; ההגדרות, קיצורי הדרך ונתיב ההתקנה הקודם נשמרים כפי שהם.
; התקנה חדשה או שדרוג מגרסה ישנה מקבלים את האשף המלא.
; עמוד "סוג ההתקנה" באשף מציע שלוש אפשרויות: למשתמש הנוכחי (ברירת מחדל,
; ללא UAC), לכל המשתמשים (שיגור-מחדש מורם עם /ALLUSERS — מצב ההתקנה של
; Inno נקבע בעליית התהליך ולא ניתן להחלפה תוך כדי ריצה), והתקנה ניידת.
; בהתקנה ניידת (לכונן חיצוני): נכתב portable.marker ליד ה-EXE, כל הנתונים
; נשמרים ב-otzaria_data ליד התוכנה, ואין רישום במערכת — לא uninstaller,
; לא קיצורי דרך, לא PATH ולא פרוטוקול otzaria://. הפרמטר /PORTABLE פותח
; את האשף במצב נייד גם כשמותקנת כבר גרסה מודרנית (שאחרת הייתה משודרגת
; בשקט ללא אשף).

#define MyAppName "אוצריא"
#define MyAppVersion "0.9.96"
#define MyAppPublisher "sivan22"
#define MyAppURL "https://github.com/otzaria/otzaria"
#define MyAppExeName "otzaria.exe"

; ארכיטקטורת היעד: "x64" (ברירת מחדל) או "arm64", נקבעת מבחוץ עם
; ‎ISCC /DAppArch=arm64‎. קובעת את תיקיית ה-build, את שם הקובץ ואת
; הגבלת הארכיטקטורה של המתקין.
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
OutputBaseFilename=otzaria-{#MyAppVersion}-windows-arm64
#else
OutputBaseFilename=otzaria-{#MyAppVersion}-windows
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
; לוג אוטומטי ל-%TEMP% של המשתמש המריץ — חיוני לאבחון עדכונים שקטים שנכשלים בשטח.
SetupLogging=yes
; בלי זה בחירת המשימות נשמרת ברישום — "איפוס הגדרות" שסומן פעם היה
; רץ שוב בכל שדרוג שקט ומוחק את נתוני המשתמש (issue #941).
UsePreviousTasks=no

[InstallDelete]
; ניקוי מסד הנתונים הישן של Isar שהוחלף על ידי hive_ce — מחיקה מכוונת בעת שדרוג.
Type: filesandordirs; Name: "{app}\default.isar";
; המסמן נכתב רק בהתקנת מנהל (ראה [INI]) והאפליקציה גוזרת ממנו את מיקום
; ברירת המחדל של הספרייה — מסמן ששרד מעבר להתקנת משתמש מפנה אותה ל-ProgramData.
Type: files; Name: "{app}\system_install.marker"; Check: (not IsAdminInstallMode) or IsPortableInstall

[Dirs]
; במצב נייד הנתונים יושבים ב-otzaria_data ליד ה-EXE — האפליקציה יוצרת אותה בעצמה.
Name: "{code:GetDataDir}"; Permissions: users-modify; Check: not IsPortableInstall
Name: "{code:GetDataDir}\books"; Permissions: users-modify; Check: not IsPortableInstall
Name: "{code:GetDataDir}\index"; Permissions: users-modify; Check: not IsPortableInstall

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "calendaricon"; Description: "צור קיצור דרך ישירות ללוח שנה"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "resetsettings"; Description: "איפוס הגדרות משתמש — אזהרה: ימחק הערות אישיות, סימניות, היסטוריה ונתוני תוספים! (תיקיות הספרים והגיבויים נשמרות. נדרש רק בשדרוג מגרסה ישנה מ-0.9.80 או לפתרון תקלות)"; Flags: unchecked

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; AppUserModelID: "Otzaria.Otzaria"; Check: not IsPortableInstall
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon; AppUserModelID: "Otzaria.Otzaria"; Check: not IsPortableInstall
; קיצור דרך ישיר ללוח השנה — מעביר ל-otzaria.exe deep link כפרמטר; אוצריא מזהה
; ארגומנט שמתחיל ב-"otzaria:" וממסרת לראוטר הפנימי (ראה docs/deep_links.md לזרימה המלאה).
; AppUserModelID זהה לסמל הראשי כדי שהקיצור יתאחד עם הכפתור המוצמד בשורת המשימות.
Name: "{autodesktop}\לוח שנה - {#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Parameters: "otzaria://open/calendar"; Tasks: calendaricon; AppUserModelID: "Otzaria.Otzaria"; Check: not IsPortableInstall

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

[Run]
; אשף: הצעת הפעלה בדף הסיום. שקט: השקה ישירה — רשומת postinstall תלויה בדף
; הסיום שלא מוצג ב-VERYSILENT ולכן לא תרוץ שם לעולם. runasoriginaluser מונע
; הרצת אוצריא מורמת אחרי עדכון עם UAC. /NOLAUNCH=1 (מנגנון העדכון הפנימי,
; בעת התקנה בסגירת התוכנה) מדלג על ההשקה כדי שאוצריא לא תיפתח מחדש.
Filename: "{app}\{#MyAppExeName}"; Description: "הפעל את {#MyAppName}"; Flags: nowait postinstall skipifsilent
Filename: "{app}\{#MyAppExeName}"; Flags: nowait runasoriginaluser; Check: ShouldLaunchAppAfterSilentInstall

[Languages]
Name: "hebrew"; MessagesFile: "compiler:Languages\Hebrew.isl"

[Files]
Source: "..\build\windows\{#AppArch}\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; קבצי הצגה לדף "תכונות עיקריות" - dontcopy = נארזים בתוך המתקין אבל לא מותקנים אצל המשתמש
Source: "feature1.bmp"; Flags: dontcopy
Source: "feature2.bmp"; Flags: dontcopy
Source: "feature3.bmp"; Flags: dontcopy
Source: "feature4.bmp"; Flags: dontcopy

[INI]
Filename: "{app}\system_install.marker"; Section: "Install"; Key: "Mode"; String: "Admin"; Check: IsAdminInstallMode and not IsPortableInstall

[Code]
const
  FEATURES_GAP_X = 14;
  FEATURES_GAP_Y = 8;
  FEATURES_LABEL_H = 18;
  UninstallRegKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{EEC4F712-CD05-4D15-A753-509E840A51A5}_is1';
  SystemEnvironmentKey = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment';
  UserEnvironmentKey = 'Environment';

var
  FeaturesPage: TWizardPage;
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
  SlideshowImage: TBitmapImage;
  SlideshowTimerId: LongWord;
  SlideshowTimerCallback: LongWord;
  SlideshowIndex: Integer;
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

// TTimer לא זמין ב-Pascal Script של Inno Setup; נשתמש ב-Windows API.
function SetTimer(hWnd, nIDEvent, uElapse, lpTimerFunc: LongWord): LongWord;
  external 'SetTimer@user32.dll stdcall';
function KillTimer(hWnd, nIDEvent: LongWord): LongWord;
  external 'KillTimer@user32.dll stdcall';

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

  // חישוב גודל ממוזער דינמי לפי שטח העמוד, כדי שיתאים גם ב-HiDPI.
  // יחס גובה/רוחב של התמונה: 210/400.
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
    'מתאימה לכונן חיצוני או דיסק-און-קי: בוחרים תיקייה, וכל הנתונים ' +
    '(ספרים, הגדרות, הערות) נשמרים בתוכה — כך שאוצריא נודדת יחד עם הכונן. ' +
    'ללא קיצורי דרך ורישום במערכת; להסרה פשוט מוחקים את התיקייה.';
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

procedure InitializeWizard();
begin
  CreateFeaturesPage();
  CreateModePage();
  InitializeSlideshow();

  RegularInstallDirDefault := WizardForm.DirEdit.Text;
  // {userdocs} זורק כשלחשבון המנהל שאישר את ה-UAC אין פרופיל/Documents מלא.
  try
    PortableInstallDirDefault := ExpandConstant('{userdocs}\OtzariaPortable');
  except
    PortableInstallDirDefault := ExpandConstant('{sd}\OtzariaPortable');
  end;

  // בחירה מוקדמת בעמוד סוג ההתקנה: ‎/PORTABLE — מצב נייד; ריצה במצב מנהל
  // (שיגור-מחדש עם /ALLUSERS) או תהליך מורם — לכל המשתמשים.
  // ‎/CURRENTUSER = שיגור-מחדש מתהליך מורם שבחר במפורש התקנת משתמש.
  if CmdLineParamExists('/PORTABLE') then
    PortableModeRadio.Checked := True
  else if IsAdminInstallMode or
    (IsAdmin and not CmdLineParamExists('/CURRENTUSER')) then
    AllUsersModeRadio.Checked := True;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  // שיגור-מחדש עם מצב מפורש (מעמוד "סוג ההתקנה") — עמודי הפתיחה והמצב כבר
  // נענו בריצה הקודמת; ממשיכים ישר לעמוד המיקום.
  Result :=
    (CmdLineParamExists('/ALLUSERS') or CmdLineParamExists('/CURRENTUSER')) and
    (((FeaturesPage <> nil) and (PageID = FeaturesPage.ID)) or
     ((ModePage <> nil) and (PageID = ModePage.ID)));
  if Result then
    exit;
  // במצב נייד אין קיצורי דרך ואיפוס הגדרות — עמוד המשימות מיותר.
  Result := PortableMode and (PageID = wpSelectTasks);
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

// בעזיבת עמוד סוג ההתקנה: קיבוע המצב, התאמת ברירת המחדל של תיקיית היעד,
// ובמעבר בין משתמש-נוכחי לכל-המשתמשים — שיגור-מחדש במצב ההתקנה המתאים
// (מצב ההתקנה של Inno נקבע בעליית התהליך ולא ניתן להחלפה תוך כדי ריצה).
// בהתקנה שקטה Inno "מדפדף" בין העמודים ומפעיל גם את הפונקציה הזו — שם
// אסור לגעת בכלום: המצב כבר נקבע ב-InitializeSetup ו-/DIR חייב להישמר.
function NextButtonClick(CurPageID: Integer): Boolean;
var
  ResultCode: Integer;
  Launched: Boolean;
begin
  Result := True;
  if WizardSilent then
    exit;
  if (ModePage = nil) or (CurPageID <> ModePage.ID) then
    exit;

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
    // בכוונה בלי PropagatedParams: העברת /PORTABLE הייתה מסמנת שוב את
    // המצב הנייד במופע החדש ודורסת את הבחירה המפורשת של המשתמש.
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
  // כל-המשתמשים / ניידת נעשית בעמוד "סוג ההתקנה" (כשהתהליך מורם העמוד
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

    MsgBox(
      'אוצריא הותקנה בעבר בנתיב הדורש הרשאות מנהל:' + #13#10 +
      PreviousDir + #13#10 + #13#10 +
      'כדי לשדרג, יש להפעיל את המתקין כמנהל' + #13#10 +
      '(קליק ימני על קובץ ההתקנה ↦ "Run as administrator").',
      mbError, MB_OK);
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

// מחזיר את נתיב תיקיית הספרים שהמשתמש בחר (אם שונה מברירת המחדל),
// כפי שנשמר ב-shared_preferences.json תחת המפתח flutter.key-library-path.
// המתקין FULL כותב נתיב זה אם המשתמש שינה את ברירת המחדל.
function GetCustomLibraryPath(): String;
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
procedure RemoveStaleScopeRegistration(RootKey: Integer);
var
  StaleDir, UninstallExe: String;
  ResultCode: Integer;
begin
  if not RegKeyExists(RootKey, UninstallRegKey) then
    exit;

  StaleDir := GetRegisteredInstallDir(RootKey);
  if (StaleDir <> '') and
     (not SameInstallDir(StaleDir, ExpandConstant('{app}'))) and
     RegQueryStringValue(RootKey, UninstallRegKey, 'UninstallString', UninstallExe) then
  begin
    UninstallExe := RemoveQuotes(Trim(UninstallExe));
    if FileExists(UninstallExe) and
       Exec(UninstallExe, '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART', '',
         SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    begin
      Log(Format('Removed stale install at %s (exit code %d)', [StaleDir, ResultCode]));
      exit;
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
  if PortableMode or (not IsAdminInstallMode) then
    exit;
  RemoveStaleScopeRegistration(HKCU);
  RemoveStaleScopeRegistration(HKLM32);
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

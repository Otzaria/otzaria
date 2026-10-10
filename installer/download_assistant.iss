; מסייע ההורדה של אוצריא — Otzaria-Download-Assistant-windows.exe
;
; הכלי הזה אינו מתקין את אוצריא ואינו מתקין שום דבר: הוא אינו כותב לרישום,
; אינו יוצר קיצורי דרך ואין לו מסיר. כל תפקידו להוריד את הקבצים הדרושים
; מ-release של אוצריא ב-GitHub, לאמת אותם, ולהכין מהם התקנה — במחשב הזה או
; בתיקייה שאפשר להעתיק למחשב מנותק.
;
; שתי אבני היסוד:
;   * מניפסט ה-release (tool/release/generate_release_manifest.dart) הוא מקור
;     האמת היחיד. שום שם נכס אינו מקודד כאן: הרכיבים, הגדלים וה-hash מגיעים
;     ממנו. תג ה-release נקבע פעם אחת בתחילת הריצה ונשמר עד סופה.
;   * הרכבת נכס מפוצל לקובץ אחד היא שרשור בתים טהור דרך TFileStream, בלי
;     PowerShell ובלי כלים חיצוניים. נמדד: 2.4GB ב-6.5 שניות.

; תג ה-release שממנו נבנה הכלי, דרך משתנה סביבה: ‎/D‎ עם מרכאות מ-pwsh הגיע
; ל-ISPP עטוף בלוכסנים (נמדד: ‎\0.10.0+139\‎). בלעדיו — נפילה ל-latest.
#ifndef AssistantReleaseTag
  #define AssistantReleaseTag GetEnv("OTZARIA_ASSISTANT_RELEASE_TAG")
#endif

; החלק ‎X.Y.Z‎ של התג, לתצוגה במאפייני הקובץ. בלי תג מוטבע אין מה להציג.
#define TagVersionPart AssistantReleaseTag
#if Pos("+", TagVersionPart) > 0
  #define TagVersionPart Copy(TagVersionPart, 1, Pos("+", TagVersionPart) - 1)
#endif

[Setup]
AppId={{9A6B5F2E-7C31-4E18-9D44-1F0B8C3A5D72}
AppName={cm:AppTitle}
; גרסת הכלי עצמו. היא אינה גרסת אוצריא: תג אוצריא מוטבע ב-AssistantReleaseTag
; בזמן הבנייה, ולכן tool/version/update_version אינו נוגע בקובץ הזה.
AppVersion=1.0
AppPublisher=sivan22
AppPublisherURL=https://github.com/otzaria/otzaria
; אינו מתקין: בלי תיקיית התקנה, בלי מסיר, בלי רישום ובלי קיצורי דרך.
CreateAppDir=no
Uninstallable=no
CreateUninstallRegKey=no
; עמוד הפתיחה הוא מסך הפתיחה המונפש של שכבת התצוגה (otzaria_ui_core.iss).
DisableWelcomePage=no
DisableProgramGroupPage=yes
DisableReadyPage=no
PrivilegesRequired=lowest
OutputDir=.\
; שם הנכס חייב להישאר ASCII: GitHub מוחק תווים שאינם ‎[A-Za-z0-9._-]‎ משם נכס
; שמועלה. הזיהוי העברי מגיע ממאפייני הקובץ שלמטה.
OutputBaseFilename=Otzaria-Download-Assistant-windows
; מאפייני הקובץ אחידים לכל שפה, ולכן בשתיהן; Inno קוטע כל ערך אחרי 60 תווים.
VersionInfoProductName=Otzaria Download Assistant · מסייע הורדה לאוצריא
VersionInfoDescription=Downloads, does not install · מוריד ומכין, אינו מתקין
VersionInfoCompany=sivan22
#if TagVersionPart != ""
VersionInfoProductTextVersion={#TagVersionPart}
#endif
SetupIconFile=white_sketch128x128.ico
; החלון כולו מצויר בשכבת התצוגה; תמונות האשף של Inno אינן מוצגות.
WizardImageFile=
WizardSmallImageFile=
WizardStyle=modern
Compression=lzma
SolidCompression=yes
SetupLogging=yes
; ההרכבה קוראת וכותבת קבצים של גיגה-בתים — אין טעם לאפשר 32-bit בלבד.
ArchitecturesAllowed=x64compatible or arm64
; עברית כשממשק Windows בעברית, ואנגלית בכל שפה אחרת: english ראשונה ולכן היא הנסיגה.
LanguageDetectionMethod=uilanguage
ShowLanguageDialog=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "hebrew"; MessagesFile: "compiler:Languages\Hebrew.isl"

; ברירות המחדל של Inno מנוסחות כמתקין ("מתקין את...", "תוכנת ההתקנה"), והכלי
; הזה אינו מתקין דבר. כל מחרוזת כזאת שמופיעה במסך כלשהו מוחלפת כאן, בשתי השפות.
[Messages]
english.SetupAppTitle=Otzaria Download Assistant
english.SetupWindowTitle=Otzaria Download Assistant
english.SetupLdrStartupMessage=This tool will download the Otzaria files and prepare an installation from them. Continue?
english.WelcomeLabel1=Otzaria Download Assistant
english.WelcomeLabel2=This tool doesn't install anything — it downloads the Otzaria files and prepares an installation from them, even for a computer without internet.
english.ButtonNext=&Continue
english.ButtonBack=&Back
english.ButtonFinish=&Finish
english.ButtonInstall=&Start
english.ButtonStopDownload=&Stop Download
english.WizardReady=Ready to start
english.ReadyLabel1=Everything is ready to download.
english.ReadyLabel2a=Click "Start" to download the files and prepare an installation from them, or "Back" to change your choice.
english.ReadyLabel2b=Click "Start" to download the files and prepare an installation from them.
english.WizardPreparing=Getting ready
english.PreparingDesc=The assistant is getting ready to download.
english.WizardInstalling=Downloading and preparing
english.InstallingLabel=The files are downloading from the Otzaria website and being checked. You can stop at any time.
english.StatusCreateDirs=Preparing the folder...
english.StatusExtractFiles=Copying files...
english.StatusSavingUninstall=Saving data...
english.StatusRunProgram=Finishing...
english.FinishedHeadingLabel=Everything's ready
english.FinishedLabel=All done.
english.FinishedLabelNoIcons=All done.
english.ClickFinish=Click "Finish" to close the assistant.
english.SetupAborted=The operation was not completed.%n%nYou can run the assistant again; whatever was already downloaded is kept.
english.ExitSetupTitle=Exit the assistant
english.ExitSetupMessage=The download isn't finished. Files that were already downloaded are kept, and running the assistant again continues from where you stopped.%n%nExit now?

hebrew.SetupAppTitle=אוצריא — מסייע הורדה
hebrew.SetupWindowTitle=אוצריא — מסייע הורדה
hebrew.SetupLdrStartupMessage=הכלי יוריד את קובצי אוצריא ויכין מהם התקנה. להמשיך?
hebrew.WelcomeLabel1=מסייע ההורדות של אוצריא
hebrew.WelcomeLabel2=הכלי אינו מתקין דבר — הוא מוריד את קובצי אוצריא ומכין מהם התקנה, גם למחשב בלי אינטרנט.
hebrew.ButtonNext=&המשך
hebrew.ButtonBack=&חזרה
hebrew.ButtonFinish=&סיום
hebrew.ButtonInstall=&התחל
hebrew.ButtonStopDownload=&עצור הורדה
hebrew.WizardReady=מוכנים להתחיל
hebrew.ReadyLabel1=הכול מוכן להורדה.
hebrew.ReadyLabel2a=לחץ "התחל" כדי להוריד את הקבצים ולהכין מהם התקנה, או "חזרה" כדי לשנות את הבחירה.
hebrew.ReadyLabel2b=לחץ "התחל" כדי להוריד את הקבצים ולהכין מהם התקנה.
hebrew.WizardPreparing=רגע לפני ההתחלה
hebrew.PreparingDesc=המסייע נערך להורדה.
hebrew.WizardInstalling=הורדה והכנה
hebrew.InstallingLabel=הקבצים יורדים מאתר אוצריא ונבדקים. אפשר לעצור בכל רגע.
hebrew.StatusCreateDirs=מכין את התיקייה...
hebrew.StatusExtractFiles=מעתיק קבצים...
hebrew.StatusSavingUninstall=שומר נתונים...
hebrew.StatusRunProgram=מסיים...
hebrew.FinishedHeadingLabel=הכול מוכן
hebrew.FinishedLabel=הפעולה הסתיימה.
hebrew.FinishedLabelNoIcons=הפעולה הסתיימה.
hebrew.ClickFinish=לחץ "סיום" לסגירת המסייע.
hebrew.SetupAborted=הפעולה לא הושלמה.%n%nאפשר להפעיל את המסייע שוב; מה שכבר ירד יישמר.
hebrew.ExitSetupTitle=יציאה מהמסייע
hebrew.ExitSetupMessage=ההורדה לא הושלמה. קבצים שכבר ירדו יישמרו, והפעלה חוזרת תמשיך מהמקום שבו הפסקת.%n%nלצאת עכשיו?

; כל טקסט שהלוגיקה מציגה. ‎%1‎ נמלא ב-FmtMessage, ו-‎%n‎ הוא מעבר שורה.
[CustomMessages]
; ב"כולל חיפוש חכם" / "Smart Search included" הרווחים קשיחים (U+00A0), כדי שהצירוף לא יישבר.
; שם תת-התיקייה בחוזה המשותף לשלושת המסייעים (expected-selections), זהה בכל שפה.
ContractSubfolder=אוצריא להתקנה ל-%1

english.AppTitle=Otzaria Download Assistant
english.OtzariaVersion=Otzaria %1
english.ErrorReadList=Can't read the list of Otzaria files.
english.ErrorConnect=Can't connect to the Otzaria downloads site.
english.PlatformWindows=Windows
english.PlatformMacos=macOS
english.PlatformLinux=Linux
english.PlatformAndroid=Android
english.FormatDeb=Ubuntu, Debian, Mint and similar distributions (DEB)
english.FormatRpm=Fedora, openSUSE and similar distributions (RPM)
english.FormatPortable=Another distribution — no installation needed
english.TargetArm=%1 · ARM processor
english.HintMac=Mac computers
english.HintAndroid=A phone or tablet
english.HintArm=For example, computers with a Snapdragon processor
english.HintX64=Intel or AMD processor — almost every computer
english.PresetFullIndexed=Full installation + search index
english.PresetFullIndexedDesc=For a computer without internet — search works right away. Smart Search included.
english.PresetFull=Full installation
english.PresetFullDesc=For a computer without internet — Otzaria builds the search index first. Smart Search included.
english.PresetBasic=Basic installation (recommended)
english.PresetBasicDesc=For a computer with internet — the library downloads from within Otzaria.
english.PresetUpdate=Update Otzaria only
english.PresetUpdateDesc=The installer of the new version, to update an existing installation.
english.PresetCustom=Custom selection
english.PresetCustomDesc=I want to choose what to download myself.
english.RequiredTag=(required)
english.OutputSubfolder=Otzaria setup for %1
english.FallbackFolder=Otzaria setup
english.DurationUnderMinute=less than a minute
english.DurationHour=1 hour
english.DurationTwoHours=2 hours
english.DurationHours=%1 hours
english.DurationMinute=1 minute
english.DurationMinutes=%1 minutes
english.DurationJoin=%1 %2
english.DownloadedOf=%1 of %2 downloaded
english.TimeLeft=%1 left
english.CheckingDownloadedFile=Checking the downloaded file
english.DownloadingItem=Downloading: %1 (%2 of %3)
english.DownloadingItemAgain=The download was interrupted, downloading again: %1 (try %2 of %3)
english.ErrorStopped=The download was stopped.
english.ErrorFileUnavailable=Can't prepare the installation because one of the required files isn't available.
english.ErrorDownloadDamaged=One of the downloaded files was damaged, so it wasn't saved.
english.ErrorDownloadIncomplete=The download of one of the files was interrupted before it finished.
english.JoiningFiles=Joining the files: %1
english.SizeOf=%1 of %2
english.ErrorWriteJoined=Couldn't write the joined file. There may not be enough free space.
english.ErrorJoinedDamaged=The joined file was damaged, so it wasn't saved.
english.CheckingJoined=Checking the joined file: %1
english.VerifyingJoined=Verifying the file against the release details
english.OpenHintExe=There, run it — no internet connection or other software is needed.
english.OpenHintDmg=There, double-click it and drag Otzaria to the Applications folder.
english.OpenHintPackage=There, double-click it to install Otzaria.
english.OpenHintApk=There, move it to the phone or tablet and open it to install Otzaria.
english.OpenHintArchive=There, extract it and run Otzaria from the folder that was created.
english.CopyingTo=Copying to the chosen folder: %1
english.ErrorCopy=Couldn't copy the files to the chosen folder.
english.ResultFileReady=The file is ready:
english.ResultFileIn=It's in the folder:
english.ResultFolderReady=The installation is ready in the folder:
english.GuideThisFile=You can install from it now, or copy it to another computer of the same kind and install there.
english.GuideOtherFile=Copy this file to a USB drive, and from there to the offline computer (%1).
english.GuideThisFolder=You can install from it now, or copy the whole folder to another computer of the same kind. The files must stay together in the same folder.
english.GuideOtherFolder=Copy this whole folder to a USB drive, and from there to the offline computer (%1). The files must stay together in the same folder.
english.GuideRunExe=On the offline computer, run %1 from it — no internet connection or other software is needed.
english.GuideJoin=Some files are too large to be a single file, so they were left in parts. On the target computer, join them in a terminal window, from inside the folder, with this command:
english.PreparedFiles=Prepared files:
english.LoadFailedBody=You can try again, or open the Otzaria downloads page in your browser and download manually from there (a limited option: the assistant won't be able to check the files or join them).
english.OfflineTitle=No internet connection
english.OfflineBody=Check your internet connection and try again. You can also open the Otzaria downloads page in your browser and download manually from there (a limited option: the assistant won't be able to check the files or join them).
english.StoppedBody=Files that were already downloaded are saved, and "Continue" picks up from the same point.
english.RunFailedBody=Files that were already downloaded are saved, and "Try Again" continues from where it stopped.
english.VersionToDownload=Version to download: %1
english.DownloadingVersion=Downloading %1…
english.RevealFile=Show the prepared file
english.RevealFolder=Show the prepared folder
english.NoTargetTitle=No computer selected
english.NoTargetText=Choose the kind of computer Otzaria will be installed on.
english.NothingTitle=Nothing selected
english.NothingText=Choose at least one item to download.
english.FolderBadTitle=Can't save in this folder
english.FolderBadFallback=The chosen folder can't be used for saving. This folder is suggested instead:%n%1%n%nYou can continue with it or choose another folder.
english.FolderBadText=The chosen folder can't be used for saving. Try another folder.
english.SpaceTitle=Not enough free space
english.SpaceText=There doesn't seem to be enough free space. About %1 is needed.%n%nContinue anyway?
english.SpaceYes=Continue
english.Cancel=Cancel
english.ErrorPrepare=Can't prepare the installation.
english.ModeTitle=Which computer is this for?
english.ModeDesc=The assistant downloads the installation files and saves them in a folder. It doesn't install anything itself.
english.ModeThis=Windows — like this computer
english.ModeOther=A different kind of computer
english.ModeThisArmDesc=For this computer and any Windows computer with an ARM processor, like Snapdragon. When the download finishes, you can install with one click.
english.ModeThisX64Desc=For this computer and any regular Windows computer with an Intel or AMD processor. When the download finishes, you can install with one click.
english.ModeOtherDesc=For %1. The files are saved in a folder, to copy to a USB drive.
english.OtherWindows=other Windows computers
english.ListOr=%1 or %2
english.OtherTitle=Which kind of computer?
english.OtherDesc=Choose the kind of computer Otzaria will be installed on.
english.OtherHint=On Linux, if you're not sure which distribution is installed, choose DEB — it fits most computers.
english.PresetTitle=What to download
english.PresetDesc=Choose how much to download.
english.PresetHint=You can change this later.
english.CustomDesc=Check the items you want to download.
english.CustomHint=Each item shows its download size.
english.FolderFallbackNote=The assistant can't save in the folder it was started from (for example, a read-only USB drive), so a different folder is suggested here.
english.FolderTitle=Where to save
english.FolderDesc=By default, the files are saved next to the assistant itself.
english.FolderHint=You can choose a different folder. You install from this folder — on this computer, or after copying it to a USB drive, also on a computer without internet.
english.ConnectTitle=Connecting to the Otzaria website
english.ConnectDesc=Getting the list of files for the latest version.
english.DownloadTitle=Downloading the files
english.DownloadDesc=The files are downloading from the Otzaria website. You can stop at any time — whatever was already downloaded is kept.
english.WorkTitle=Preparing the installation
english.WorkDesc=One moment, preparing the files.
english.CheckingCached=Checking files that were already downloaded

hebrew.AppTitle=אוצריא — מסייע הורדה
hebrew.OtzariaVersion=אוצריא %1
hebrew.ErrorReadList=לא ניתן לקרוא את רשימת הקבצים של אוצריא.
hebrew.ErrorConnect=לא ניתן להתחבר לאתר ההורדות של אוצריא.
hebrew.PlatformWindows=Windows
hebrew.PlatformMacos=macOS
hebrew.PlatformLinux=Linux
hebrew.PlatformAndroid=Android
hebrew.FormatDeb=Ubuntu, Debian, Mint והפצות דומות (DEB)
hebrew.FormatRpm=Fedora, openSUSE והפצות דומות (RPM)
hebrew.FormatPortable=הפצה אחרת — ללא התקנה
hebrew.TargetArm=%1 · מעבד ARM
hebrew.HintMac=מחשבי Mac
hebrew.HintAndroid=טלפון או טאבלט
hebrew.HintArm=למשל מחשבים עם מעבד Snapdragon
hebrew.HintX64=מעבד Intel או AMD — כמעט כל המחשבים
hebrew.PresetFullIndexed=התקנה מלאה + אינדקס חיפוש
hebrew.PresetFullIndexedDesc=למחשב שאין בו אינטרנט — אינדקס החיפוש מוכן, והחיפוש עובד מיד. כולל חיפוש חכם.
hebrew.PresetFull=התקנה מלאה
hebrew.PresetFullDesc=למחשב שאין בו אינטרנט — אינדקס החיפוש ייבנה בתוכנה, וזה לוקח זמן. כולל חיפוש חכם.
hebrew.PresetBasic=התקנה בסיסית (מומלצת)
hebrew.PresetBasicDesc=למחשב שיש בו אינטרנט — הספרייה תרד מתוך התוכנה.
hebrew.PresetUpdate=עדכון התוכנה בלבד
hebrew.PresetUpdateDesc=קובץ ההתקנה של הגרסה החדשה, לעדכון התקנה קיימת.
hebrew.PresetCustom=בחירה אישית
hebrew.PresetCustomDesc=אני רוצה לבחור בעצמי מה להוריד.
hebrew.RequiredTag=(נדרש)
hebrew.OutputSubfolder=אוצריא להתקנה ל-%1
hebrew.FallbackFolder=אוצריא-להתקנה
hebrew.DurationUnderMinute=פחות מדקה
hebrew.DurationHour=שעה
hebrew.DurationTwoHours=שעתיים
hebrew.DurationHours=%1 שעות
hebrew.DurationMinute=דקה
hebrew.DurationMinutes=%1 דקות
hebrew.DurationJoin=%1 ו-%2
hebrew.DownloadedOf=ירדו %1 מתוך %2
hebrew.TimeLeft=נותרו %1
hebrew.CheckingDownloadedFile=בודק את הקובץ שירד
hebrew.DownloadingItem=מוריד: %1 (%2 מתוך %3)
hebrew.DownloadingItemAgain=ההורדה נקטעה, מוריד שוב: %1 (ניסיון %2 מתוך %3)
hebrew.ErrorStopped=ההורדה הופסקה.
hebrew.ErrorFileUnavailable=לא ניתן להכין את ההתקנה משום שאחד הקבצים הדרושים אינו זמין.
hebrew.ErrorDownloadDamaged=אחד הקבצים שהורדו נמצא פגום ולא נשמר.
hebrew.ErrorDownloadIncomplete=ההורדה של אחד הקבצים נקטעה לפני שהסתיימה.
hebrew.JoiningFiles=מחבר את הקבצים: %1
hebrew.SizeOf=%1 מתוך %2
hebrew.ErrorWriteJoined=לא ניתן היה לכתוב את הקובץ המאוחד. ייתכן שאין מספיק מקום פנוי.
hebrew.ErrorJoinedDamaged=הקובץ המאוחד נמצא פגום ולכן לא נשמר.
hebrew.CheckingJoined=בודק את הקובץ המאוחד: %1
hebrew.VerifyingJoined=מאמת את תוכן הקובץ מול המניפסט
hebrew.OpenHintExe=שם הפעל אותו — אין צורך בחיבור לאינטרנט ואין צורך בתוכנות נוספות.
hebrew.OpenHintDmg=שם פתח אותו בלחיצה כפולה וגרור את אוצריא לתיקיית היישומים.
hebrew.OpenHintPackage=שם פתח אותו בלחיצה כפולה כדי להתקין את אוצריא.
hebrew.OpenHintApk=שם העבר אותו לטלפון או לטאבלט ופתח אותו כדי להתקין את אוצריא.
hebrew.OpenHintArchive=שם חלץ אותו והפעל את אוצריא מתוך התיקייה שנוצרה.
hebrew.CopyingTo=מעתיק לתיקייה שנבחרה: %1
hebrew.ErrorCopy=לא ניתן היה להעתיק את הקבצים לתיקייה שנבחרה.
hebrew.ResultFileReady=הקובץ מוכן:
hebrew.ResultFileIn=הוא נמצא בתיקייה:
hebrew.ResultFolderReady=ההתקנה מוכנה בתיקייה:
hebrew.GuideThisFile=אפשר להתקין ממנו עכשיו, או להעתיק אותו למחשב אחר מאותו סוג ולהתקין שם.
hebrew.GuideOtherFile=העתק את הקובץ הזה לדיסק-און-קי ומשם למחשב המנותק (%1).
hebrew.GuideThisFolder=אפשר להתקין ממנה עכשיו, או להעתיק את כל התיקייה למחשב אחר מאותו סוג. הקבצים חייבים להישאר יחד באותה תיקייה.
hebrew.GuideOtherFolder=העתק את כל התיקייה הזאת לדיסק-און-קי ומשם למחשב המנותק (%1). הקבצים חייבים להישאר יחד באותה תיקייה.
hebrew.GuideRunExe=במחשב המנותק הפעל מתוכה את %1 — אין צורך בחיבור לאינטרנט ואין צורך בתוכנות נוספות.
hebrew.GuideJoin=חלק מהקבצים גדולים מדי לקובץ אחד ולכן נשארו מחולקים. במחשב היעד מחברים אותם בחלון מסוף (טרמינל), מתוך התיקייה, בפקודה:
hebrew.PreparedFiles=הקבצים שהוכנו:
hebrew.LoadFailedBody=אפשר לנסות שוב, או לפתוח את עמוד ההורדות של אוצריא בדפדפן ולהוריד משם ידנית (אפשרות מוגבלת: המסייע לא יוכל לבדוק את הקבצים או לחבר אותם).
hebrew.OfflineTitle=אין חיבור לאינטרנט
hebrew.OfflineBody=בדוק את החיבור לאינטרנט ונסה שוב. אפשר גם לפתוח את עמוד ההורדות של אוצריא בדפדפן ולהוריד משם ידנית (אפשרות מוגבלת: המסייע לא יוכל לבדוק את הקבצים או לחבר אותם).
hebrew.StoppedBody=קבצים שכבר ירדו נשמרו, ו"המשך" ימשיך מאותו מקום.
hebrew.RunFailedBody=קבצים שכבר ירדו נשמרו, ו"נסה שוב" ימשיך מהמקום שבו נעצרה הפעולה.
hebrew.VersionToDownload=הגרסה שתורד: %1
hebrew.DownloadingVersion=מוריד את %1…
hebrew.RevealFile=הצג את הקובץ שהוכן
hebrew.RevealFolder=הצג את התיקייה שהוכנה
hebrew.NoTargetTitle=לא נבחר מחשב
hebrew.NoTargetText=יש לבחור את סוג המחשב שבו תותקן אוצריא.
hebrew.NothingTitle=לא נבחר רכיב
hebrew.NothingText=יש לבחור לפחות רכיב אחד להורדה.
hebrew.FolderBadTitle=אי אפשר לשמור בתיקייה הזאת
hebrew.FolderBadFallback=לא ניתן לשמור בתיקייה שנבחרה. במקומה מוצעת התיקייה:%n%1%n%nאפשר להמשיך איתה או לבחור תיקייה אחרת.
hebrew.FolderBadText=לא ניתן לשמור בתיקייה שנבחרה. נסה תיקייה אחרת.
hebrew.SpaceTitle=אין מספיק מקום פנוי
hebrew.SpaceText=נראה שאין מספיק מקום פנוי. דרושים בערך %1.%n%nלהמשיך בכל זאת?
hebrew.SpaceYes=להמשיך
hebrew.Cancel=ביטול
hebrew.ErrorPrepare=לא ניתן להכין את ההתקנה.
hebrew.ModeTitle=לאיזה מחשב מכינים את ההתקנה?
hebrew.ModeDesc=המסייע מוריד את קובצי ההתקנה ושומר אותם בתיקייה. הוא עצמו אינו מתקין דבר.
hebrew.ModeThis=Windows — כמו המחשב הזה
hebrew.ModeOther=סוג מחשב אחר
hebrew.ModeThisArmDesc=מתאים למחשב הזה ולכל מחשב Windows עם מעבד ARM, כמו Snapdragon. בסוף ההורדה אפשר להתקין בלחיצה.
hebrew.ModeThisX64Desc=מתאים למחשב הזה ולכל מחשב Windows רגיל, עם מעבד Intel או AMD. בסוף ההורדה אפשר להתקין בלחיצה.
hebrew.ModeOtherDesc=מתאים ל-%1. הקבצים נשמרים בתיקייה, להעתקה בדיסק-און-קי.
hebrew.OtherWindows=Windows מסוג אחר
hebrew.ListOr=%1 או %2
hebrew.OtherTitle=לאיזה סוג מחשב?
hebrew.OtherDesc=בחר את סוג המחשב שבו תותקן אוצריא.
hebrew.OtherHint=ב-Linux, אם אינך יודע איזו הפצה מותקנת, בחר DEB — היא מתאימה לרוב המחשבים.
hebrew.PresetTitle=מה להוריד
hebrew.PresetDesc=בחר את היקף ההורדה.
hebrew.PresetHint=אפשר לשנות את הבחירה בהמשך.
hebrew.CustomDesc=סמן את הרכיבים שברצונך להוריד.
hebrew.CustomHint=ליד כל רכיב מופיע גודל ההורדה שלו.
hebrew.FolderFallbackNote=אי אפשר לשמור בתיקייה שממנה הופעל המסייע (למשל דיסק-און-קי לקריאה בלבד), ולכן הוצעה כאן תיקייה אחרת.
hebrew.FolderTitle=לאן לשמור
hebrew.FolderDesc=כברירת מחדל הקבצים נשמרים ליד המסייע עצמו.
hebrew.FolderHint=אפשר לבחור תיקייה אחרת. מהתיקייה הזאת מתקינים — במחשב הזה, או אחרי העתקה לדיסק-און-קי גם במחשב בלי אינטרנט.
hebrew.ConnectTitle=מתחבר לאתר אוצריא
hebrew.ConnectDesc=מוריד את רשימת הקבצים של הגרסה העדכנית.
hebrew.DownloadTitle=הורדת הקבצים
hebrew.DownloadDesc=הקבצים יורדים מאתר אוצריא. אפשר לעצור בכל רגע — מה שכבר ירד יישמר.
hebrew.WorkTitle=הכנת ההתקנה
hebrew.WorkDesc=רגע, מכינים את הקבצים.
hebrew.CheckingCached=בודק קבצים שכבר הורדו

; שכבת התצוגה המשותפת לאוצריא: העיצוב ([Files]) והליבה, לפני כל הקוד שמשתמש בהם.
#include "otzaria_ui_art.iss"
#include "otzaria_ui_core.iss"

[Code]
type
  TByHandleFileInformation = record
    dwFileAttributes: LongWord;
    ftCreationTime, ftLastAccessTime, ftLastWriteTime: TFileTime;
    dwVolumeSerialNumber, nFileSizeHigh, nFileSizeLow, nNumberOfLinks,
      nFileIndexHigh, nFileIndexLow: LongWord;
  end;

function GetFileInformationByHandle(hFile: THandle;
  var Info: TByHandleFileInformation): BOOL;
  external 'GetFileInformationByHandle@kernel32.dll stdcall';
function SetEndOfFile(hFile: THandle): BOOL;
  external 'SetEndOfFile@kernel32.dll stdcall';
function CreateHardLink(lpFileName, lpExistingFileName: String;
  lpSecurityAttributes: Integer): BOOL;
  external 'CreateHardLinkW@kernel32.dll stdcall';
function GetTickCount(): LongWord;
  external 'GetTickCount@kernel32.dll stdcall';

const
  { מגבלת GitHub לנכס בודד. נכס גדול ממנה מתפרסם כחלקים. }
  GithubAssetLimit = 2147483648;
  { Windows מסרב להריץ exe בגודל 4 GiB ומעלה (ERROR_BAD_EXE_FORMAT), ו-FAT32
    אינו מחזיק קובץ כזה. }
  MaxSingleOutputFileSize = 4294967296;
  CopyChunkSize = 4194304;
  AppendSliceSize = 67108864;
  ManifestSchemaVersion = 1;
  SpeedWindowMs = 5000;
  { Inno אינו ממשיך הורדה מאמצע: חיבור שנקטע מחייב להוריד את הקובץ כולו שוב. }
  DownloadAttempts = 3;

  ModeThisComputer = 0;
  ModeOtherComputer = 1;

  FailureLoad = 1;
  FailureRun = 2;
  { עצירה של המשתמש אינה תקלה: מוצגת ברוגע, ו"המשך" ממשיך מאותו מקום. }
  RunStopped = 3;

  KnownPlatforms = 'windows,macos,linux,android';
  PortableFormat = 'portable';
  { השם שה-workflow כותב (--out). משמש לתג המוטבע בלי API: מגבלת הקצב של
    api.github.com (403/429) משותפת לכל מי שיוצא מאותה כתובת, למשל בנטפרי. }
  ReleaseManifestAsset = 'otzaria-release-manifest.json';
  { נתונים שהתוכנה המותקנת קוראת מתיקיית הפלט, ולכן חלק מ"מלאה" ומ"מלאה + אינדקס". }
  OfflineDataTypes = 'semantic-model,semantic-vectors,';
  { סדר ההצגה. סדר ההוספה ב-BuildPresets הוא שקובע איזו כפולה מושמטת. }
  PresetDisplayOrder = 'basic,full-indexed,full,update,';

type
  TInt64Array = array of Int64;

var
  { --- מה שנקרא מה-release --- }
  PinnedTag: String;
  ReleaseVersion: String;
  ManifestLoaded: Boolean;
  LoadErrorMsg: String;
  LoadErrorTech: String;
  LoadAttempts, LoadNetworkFailures: Integer;
  LoadOffline: Boolean;

  CompId, CompName, CompDesc, CompType, CompPlatform, CompArch, CompFormat,
    CompDependsOn, CompInstalledBy, CompPartOf, CompOutputFolder,
    CompOutputNote, CompOutputNoteEn: TArrayOfString;
  CompRequired, CompSelected: array of Boolean;
  CompDownloadSize: TInt64Array;
  CompAssetStart, CompAssetCount: array of Integer;

  AssetKind, AssetRepo, AssetTag, AssetName, AssetSha: TArrayOfString;
  AssetSize: TInt64Array;
  AssetPartStart, AssetPartCount, AssetComp: array of Integer;

  PartName, PartSha: TArrayOfString;
  PartSize: TInt64Array;

  { --- מחשב היעד: נקבע מהעמודים ב-UpdateTarget ונקרא רק מכאן --- }
  TargetPlatform, TargetArchitecture, TargetFormat: String;
  { שורות העמוד "סוג מחשב אחר", באותו סדר. }
  OtherPlatform, OtherArch, OtherFormat: TArrayOfString;

  { --- הצעות מוכנות, נגזרות מהמניפסט --- }
  PresetId, PresetLabel, PresetDesc, PresetSize, PresetMembers: TArrayOfString;

  { --- מצב האשף --- }
  ModePage: TInputOptionWizardPage;
  OtherPage: TInputOptionWizardPage;
  PresetPage: TInputOptionWizardPage;
  CustomPage: TInputOptionWizardPage;
  FolderPage: TInputDirWizardPage;
  ConnectPage: TDownloadWizardPage;
  DownloadPage: TDownloadWizardPage;
  WorkPage: TOutputProgressWizardPage;
  { עצירה שאושרה בחלון המעוצב; Inno עוצר רק כשפונקציית ההתקדמות מחזירה False. }
  StopRequested: Boolean;
  CustomIndex: array of Integer;
  CustomPresetIndex: Integer;
  ResultText: String;
  { חלקי ResultText לעמוד הסיום המצויר: הקובץ (כשנוצר אחד), התיקייה וההנחיה. }
  ResultFile, ResultFolder, ResultGuide: String;
  RunAfterExe: String;
  RevealPath: String;
  RevealIsFile: Boolean;
  RevealCheck: TNewCheckBox;

  { --- תור ההורדה של הריצה הנוכחית --- }
  QueueUrl, QueueFile, QueueSha, QueueLabel: TArrayOfString;
  { שורת "ירדו X מתוך Y" האחרונה: Inno כותב לאותה תווית גם את שם הקובץ. }
  DownloadStatus: String;
  { פקודות החיבור שבהנחיית הסיום, כדי שהתצוגה תבדיל אותן מטקסט רגיל. }
  ResultCommands: TArrayOfString;
  QueueSize: TInt64Array;
  ProgressCaption: String;
  ProgressDone, ProgressTotal: Int64;
  SampleTick, SampleBytes: TInt64Array;
  VerifyStartTick: Int64;

{ ============================ עזרי טקסט ============================ }

function EndsWithText(const S, Suffix: String): Boolean;
begin
  Result := (Length(Suffix) <= Length(S)) and
    (Lowercase(Copy(S, Length(S) - Length(Suffix) + 1, Length(Suffix))) =
      Lowercase(Suffix));
end;

{ "אוצריא 0.9.98" לפי releaseVersion של המניפסט — לא התג, שיש בו ‎+build. ריק כשאין. }
function OtzariaVersionLabel(): String;
begin
  Result := '';
  if ReleaseVersion <> '' then
    Result := Msg1('OtzariaVersion', LtrUnit(ReleaseVersion));
end;

{ אותן יחידות כמו בתוכנה עצמה: GB, MB, KB. רווח קשיח, כדי ששבירת שורה לא
  תפריד בין המספר ליחידה. }
function HumanSize(Bytes: Int64): String;
var
  Tenths: Int64;
begin
  if Bytes >= Int64(1073741824) then
  begin
    Tenths := (Bytes * 10) div Int64(1073741824);
    Result := LtrUnit(IntToStr(Tenths div 10) + '.' +
      IntToStr(Tenths mod 10) + #$00A0 + 'GB');
  end
  else if Bytes >= 1048576 then
    Result := LtrUnit(IntToStr(Bytes div 1048576) + #$00A0 + 'MB')
  else
    Result := LtrUnit(IntToStr((Bytes + 1023) div 1024) + #$00A0 + 'KB');
end;

{ נתיב לתצוגה בתוך עברית (LRE/PDF: פקדי Win32 אינם מכירים בידוד). לא לנתיב של
  פעולת קבצים ולא לפקודה להעתקה — התווים הסמויים מועתקים ושוברים אותה בטרמינל. }
function DisplayLtr(const Text: String): String;
begin
  Result := #$202A + Text + #$202C;
end;

{ שורת השם ומתחתיה התיאור: ה-SubItem של הרשימה הוא שורה אחת שאינה נשברת. }
function OptionCaption(const Title, Desc: String): String;
begin
  Result := Title;
  if Desc <> '' then
    Result := Result + #13#10 + Desc;
end;

function IsExecutableName(const Name: String): Boolean;
begin
  Result := EndsWithText(Name, '.exe');
end;

{ ====================== קורא JSON מינימלי ====================== }

{ תווי המבנה של JSON הם ASCII וכל בית ברצף UTF-8 הוא 80 ומעלה, ולכן סריקה
  בבתים בטוחה; רק הערכים שחולצו עוברים Utf8Decode. }

{ מיקום 0 הוא "לא נמצא" מכל העזרים כאן, ולכן הוא מתורגם למיקום שמעבר לסוף
  ולא לגישה מחוץ לתחום. }
function JSkipWs(const S: AnsiString; P: Integer): Integer;
begin
  if P < 1 then
  begin
    Result := Length(S) + 1;
    exit;
  end;
  while (P <= Length(S)) and (S[P] <= ' ') do
    P := P + 1;
  Result := P;
end;

{ P על מרכאות הפתיחה; מחזיר את המיקום שאחרי מרכאות הסגירה. }
function JSkipString(const S: AnsiString; P: Integer): Integer;
begin
  if P < 1 then
  begin
    Result := Length(S) + 1;
    exit;
  end;
  P := P + 1;
  while P <= Length(S) do
  begin
    if S[P] = '\' then
      P := P + 2
    else if S[P] = '"' then
    begin
      Result := P + 1;
      exit;
    end
    else
      P := P + 1;
  end;
  Result := P;
end;

function JSkipValue(const S: AnsiString; P: Integer): Integer;
var
  Depth: Integer;
begin
  P := JSkipWs(S, P);
  if P > Length(S) then
  begin
    Result := P;
    exit;
  end;
  if S[P] = '"' then
  begin
    Result := JSkipString(S, P);
    exit;
  end;
  if (S[P] = '{') or (S[P] = '[') then
  begin
    Depth := 0;
    while P <= Length(S) do
    begin
      if S[P] = '"' then
        P := JSkipString(S, P)
      else
      begin
        if (S[P] = '{') or (S[P] = '[') then
          Depth := Depth + 1
        else if (S[P] = '}') or (S[P] = ']') then
        begin
          Depth := Depth - 1;
          if Depth = 0 then
          begin
            Result := P + 1;
            exit;
          end;
        end;
        P := P + 1;
      end;
    end;
    Result := P;
    exit;
  end;
  while (P <= Length(S)) and (S[P] > ' ') and (S[P] <> ',') and
        (S[P] <> '}') and (S[P] <> ']') do
    P := P + 1;
  Result := P;
end;

{ ערך גולמי של מחרוזת JSON ש-P מצביע על מרכאות הפתיחה שלה. }
function JRawString(const S: AnsiString; P: Integer): AnsiString;
var
  C: AnsiChar;
begin
  Result := '';
  if P < 1 then
    exit;
  P := P + 1;
  while P <= Length(S) do
  begin
    C := S[P];
    if C = '"' then
      exit;
    if C = '\' then
    begin
      P := P + 1;
      if P > Length(S) then
        exit;
      C := S[P];
      if C = 'n' then
        Result := Result + #10
      else if C = 't' then
        Result := Result + #9
      else if C = 'r' then
        Result := Result + #13
      else if C = 'u' then
      begin
        { \uXXXX אינו מופיע בפלט של הגנרטור; נשמר כסימן שאלה ולא נבלע. }
        Result := Result + '?';
        P := P + 4;
      end
      else
        Result := Result + C;
    end
    else
      Result := Result + C;
    P := P + 1;
  end;
end;

{ ObjPos על '{'. מחזיר את מיקום הערך של Key, או 0. }
function JFind(const S: AnsiString; ObjPos: Integer; const Key: AnsiString): Integer;
var
  P: Integer;
begin
  Result := 0;
  P := JSkipWs(S, ObjPos);
  if (P > Length(S)) or (S[P] <> '{') then
    exit;
  P := P + 1;
  while True do
  begin
    P := JSkipWs(S, P);
    if (P > Length(S)) or (S[P] = '}') then
      exit;
    if S[P] <> '"' then
      exit;
    if JRawString(S, P) = Key then
    begin
      P := JSkipWs(S, JSkipString(S, P));
      if (P > Length(S)) or (S[P] <> ':') then
        exit;
      Result := JSkipWs(S, P + 1);
      exit;
    end;
    P := JSkipWs(S, JSkipString(S, P));
    if (P > Length(S)) or (S[P] <> ':') then
      exit;
    P := JSkipValue(S, P + 1);
    P := JSkipWs(S, P);
    if (P <= Length(S)) and (S[P] = ',') then
      P := P + 1
    else
      exit;
  end;
end;

function JArrFirst(const S: AnsiString; ArrPos: Integer): Integer;
var
  P: Integer;
begin
  Result := 0;
  P := JSkipWs(S, ArrPos);
  if (P > Length(S)) or (S[P] <> '[') then
    exit;
  P := JSkipWs(S, P + 1);
  if (P <= Length(S)) and (S[P] <> ']') then
    Result := P;
end;

function JArrNext(const S: AnsiString; ElemPos: Integer): Integer;
var
  P: Integer;
begin
  Result := 0;
  P := JSkipWs(S, JSkipValue(S, ElemPos));
  if (P > Length(S)) or (S[P] <> ',') then
    exit;
  P := JSkipWs(S, P + 1);
  if (P <= Length(S)) and (S[P] <> ']') then
    Result := P;
end;

function JStr(const S: AnsiString; ObjPos: Integer; const Key: AnsiString): String;
var
  P: Integer;
begin
  Result := '';
  P := JFind(S, ObjPos, Key);
  if (P > 0) and (P <= Length(S)) and (S[P] = '"') then
    Result := Utf8Decode(JRawString(S, P));
end;

function JInt(const S: AnsiString; ObjPos: Integer; const Key: AnsiString): Int64;
var
  P, E: Integer;
begin
  Result := -1;
  P := JFind(S, ObjPos, Key);
  if P = 0 then
    exit;
  E := JSkipValue(S, P);
  Result := StrToInt64Def(Trim(Copy(S, P, E - P)), -1);
end;

function JBool(const S: AnsiString; ObjPos: Integer; const Key: AnsiString): Boolean;
var
  P, E: Integer;
begin
  Result := False;
  P := JFind(S, ObjPos, Key);
  if P = 0 then
    exit;
  E := JSkipValue(S, P);
  Result := Trim(Copy(S, P, E - P)) = 'true';
end;

{ ========================= כתובות ומטמון ========================= }

{ כתובת נכס נבנית תמיד מ-repository + releaseTag + שם קובץ, לעולם לא
  מכתובת חופשית. רק מאגרים בארגון Otzaria ב-github.com. }
function IsOtzariaRepository(const Repository: String): Boolean;
begin
  Result := (Length(Repository) > 8) and (Copy(Repository, 1, 8) = 'Otzaria/') and
    (Pos('/', Copy(Repository, 9, Length(Repository))) = 0) and
    (Pos('..', Repository) = 0);
end;

{ ‎^[A-Za-z0-9._+-]+$‎, ולא נקודות בלבד: השם משמש גם כנתיב קובץ, ו-'..' או '\'
  היו כותבים מחוץ למטמון ולתיקיית היעד. }
function IsSafeName(const Name: String): Boolean;
var
  I: Integer;
  C: Char;
  OnlyDots: Boolean;
begin
  Result := False;
  if Name = '' then
    exit;
  OnlyDots := True;
  for I := 1 to Length(Name) do
  begin
    C := Name[I];
    if not (((C >= 'A') and (C <= 'Z')) or ((C >= 'a') and (C <= 'z')) or
            ((C >= '0') and (C <= '9')) or (C = '.') or (C = '_') or
            (C = '+') or (C = '-')) then
      exit;
    if C <> '.' then
      OnlyDots := False;
  end;
  Result := not OnlyDots;
end;

{ outputFolder: שמות ‎[A-Za-z0-9._-]‎ מופרדים ב-'/', בלי מקטע ריק או של
  נקודות בלבד — הוא הופך לנתיב כתיבה בתוך תיקיית הפלט. }
function IsSafeOutputFolder(const Folder: String): Boolean;
var
  Parts: TArrayOfString;
  I: Integer;
begin
  Result := False;
  if (Folder = '') or (Pos('+', Folder) > 0) then
    exit;
  Parts := StringSplitEx(Folder, ['/'], #0, stAll);
  for I := 0 to GetArrayLength(Parts) - 1 do
    if not IsSafeName(Parts[I]) then
      exit;
  Result := True;
end;

function AssetUrl(const Repository, Tag, Name: String): String;
begin
  Result := '';
  if not IsOtzariaRepository(Repository) or not IsSafeName(Tag) or
     not IsSafeName(Name) then
    exit;
  Result := 'https://github.com/' + Repository + '/releases/download/' + Tag +
    '/' + Name;
end;

function ReleaseApiUrl(const Path: String): String;
begin
#ifdef DevApiBase
  { פיתוח בלבד (/DDevApiBase=<url/>): מדמה API שאינו עונה. }
  Result := '{#DevApiBase}' + Path;
  exit;
#endif
  Result := 'https://api.github.com/repos/Otzaria/otzaria/releases/' + Path;
end;

{ החלק ה-X.Y.Z של תג. סיומת ‎+build‎ אינה משתתפת בהשוואה: שני תגים של אותה
  גרסה הם אותה גרסה, וסדר מספרי ה-run אינו סדר גרסאות. }
function VersionPart(const Tag: String): String;
var
  P: Integer;
begin
  Result := Trim(Tag);
  P := Pos('+', Result);
  if P > 0 then
    Result := Copy(Result, 1, P - 1);
  if (Result <> '') and ((Result[1] = 'v') or (Result[1] = 'V')) then
    Result := Copy(Result, 2, Length(Result));
end;

{ 1 אם A גדול מ-B, ‎-1‎ אם קטן, 0 אם שווה. }
function CompareVersionText(const A, B: String): Integer;
var
  PA, PB: TArrayOfString;
  I, N, NA, NB: Integer;
  VA, VB: Int64;
begin
  Result := 0;
  PA := StringSplitEx(VersionPart(A), ['.'], #0, stExcludeEmpty);
  PB := StringSplitEx(VersionPart(B), ['.'], #0, stExcludeEmpty);
  NA := GetArrayLength(PA);
  NB := GetArrayLength(PB);
  if NA > NB then
    N := NA
  else
    N := NB;
  for I := 0 to N - 1 do
  begin
    if I < NA then
      VA := StrToInt64Def(PA[I], 0)
    else
      VA := 0;
    if I < NB then
      VB := StrToInt64Def(PB[I], 0)
    else
      VB := 0;
    if VA > VB then
    begin
      Result := 1;
      exit;
    end;
    if VA < VB then
    begin
      Result := -1;
      exit;
    end;
  end;
end;

function CacheDir(): String;
begin
  Result := ExpandConstant('{localappdata}\Otzaria\DownloadAssistant\cache');
end;

function CachePath(const Name: String): String;
begin
  Result := CacheDir() + '\' + Name;
end;

{ התיקייה שממנה הופעל המסייע — ברירת המחדל לשמירה. }
function AssistantDir(): String;
begin
  Result := RemoveBackslashUnlessRoot(
    ExtractFileDir(ExpandConstant('{srcexe}')));
end;

function FallbackOutputBase(): String;
begin
  Result := ExpandConstant('{userdocs}\') + CustomMessage('FallbackFolder');
end;

{ כתיבה ממשית ולא ניחוש מהנתיב: דיסק-און-קי לקריאה בלבד, שיתוף רשת ותיקייה
  מוגנת נראים תקינים עד לניסיון הכתיבה הראשון. }
function DirIsWritable(const Dir: String): Boolean;
var
  Probe: String;
begin
  Result := False;
  if Dir = '' then
    exit;
  if not ForceDirectories(Dir) then
    exit;
  Probe := AddBackslash(Dir) + 'otzaria_write_test.tmp';
  DeleteFile(Probe);
  if not SaveStringToFile(Probe, 'otzaria', False) then
    exit;
  Result := FileExists(Probe);
  DeleteFile(Probe);
end;

{ ============================ זמן ו-hash ============================ }

function NowMs(): Int64;
begin
  Result := GetTickCount();
end;

{ מחשב hash ומתעד את משך הקריאה; הרכבה מחודשת מחייבת גם אימות של התוצר. }
function HashFile(const Path: String): String;
var
  Started: Int64;
begin
  Started := NowMs();
  Result := Lowercase(GetSHA256OfFile(Path));
  Log('DownloadAssistant: hashed ' + ExtractFileName(Path) + ' in ' +
    IntToStr(NowMs() - Started) + ' ms');
end;

function FileWriteTime(const Path: String; var Stamp: Int64): Boolean;
var
  Rec: TFindRec;
begin
  Result := FindFirst(Path, Rec);
  if not Result then
    exit;
  Stamp := Int64(Rec.LastWriteTime.dwHighDateTime) * 4294967296 +
    Int64(Rec.LastWriteTime.dwLowDateTime);
  FindClose(Rec);
end;

{ ============================ מטמון ============================ }

{ החותם `<name>.sha256` בפורמט sha256sum מעיד שהקובץ כבר אומת. }
function MarkerPath(const Name: String): String;
begin
  Result := CachePath(Name) + '.sha256';
end;

function ReadMarkerHex(const Name: String): String;
var
  Raw: AnsiString;
begin
  Result := '';
  if not LoadStringFromFile(MarkerPath(Name), Raw) then
    exit;
  if Length(Raw) >= 64 then
    Result := Lowercase(Copy(Raw, 1, 64));
end;

procedure WriteMarker(const Name, Sha: String);
begin
  if not SaveStringToFile(MarkerPath(Name),
    Utf8Encode(Lowercase(Sha) + '  ' + Name + #10), False) then
    Log('DownloadAssistant: cannot write marker for ' + Name);
end;

{ ‎-1‎ כשלא ניתן לדעת. }
function LinkCount(const Path: String): Integer;
var
  F: TFileStream;
  Info: TByHandleFileInformation;
begin
  Result := -1;
  try
    F := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
    try
      if GetFileInformationByHandle(F.Handle, Info) then
        Result := Info.nNumberOfLinks;
    finally
      F.Free;
    end;
  except
    Result := -1;
  end;
end;

{ קובץ שלא השתנה אחרי שנכתב לו חותם תואם — מוכן בלי hash. קובץ שחותמו מעיד
  על תוכן אחר אינו מוכן. בלי חותם (מטמון ישן) — hash אחד, ואז חותם. קישור
  קשיח נוסף ביעד יכול להידרס בלי לקדם את זמן השינוי, ולכן אז אין אמון בחותם. }
function FileMatchesMarker(const Path, Name: String; Size: Int64;
  const Sha: String): Boolean;
var
  Actual, FileStamp, MarkerStamp: Int64;
  Marker: String;
begin
  Result := False;
  if not FileSize64(Path, Actual) or (Actual <> Size) then
    exit;
  Marker := ReadMarkerHex(Name);
  if (Marker <> '') and (Marker <> Lowercase(Sha)) then
    exit;
  if (Marker <> '') and FileWriteTime(Path, FileStamp) and
     FileWriteTime(MarkerPath(Name), MarkerStamp) and
     (FileStamp <= MarkerStamp) and (LinkCount(Path) = 1) then
  begin
    Result := True;
    exit;
  end;
  Result := HashFile(Path) = Lowercase(Sha);
  if Result then
    WriteMarker(Name, Sha);
end;

function CachedFileIsGood(const Name: String; Size: Int64; const Sha: String): Boolean;
begin
  Result := FileMatchesMarker(CachePath(Name), Name, Size, Sha);
end;

{ עמוד ההורדה כבר אימת את ה-sha256 (הוא מועבר אליו תמיד), ולכן כאן נבדק
  גודל בלבד. הקובץ מקבל את שמו הסופי רק אחרי הבדיקה, והחותם — אחריו. }
function PromoteToCache(const TempPath, Name: String; Size: Int64;
  const Sha: String): Boolean;
var
  Staged: String;
  Actual: Int64;
begin
  Result := False;
  ForceDirectories(CacheDir());
  Staged := CachePath(Name) + '.download';
  DeleteFile(Staged);
  if not RenameFile(TempPath, Staged) then
    if not CopyFile(TempPath, Staged, False) then
      exit;
  if FileSize64(Staged, Actual) and (Actual = Size) then
  begin
    DeleteFile(MarkerPath(Name));
    DeleteFile(CachePath(Name));
    Result := RenameFile(Staged, CachePath(Name));
    if Result then
      WriteMarker(Name, Sha);
  end;
  if not Result then
    DeleteFile(Staged);
end;

{ ========================= קריאת המניפסט ========================= }

{ מערך JSON של מזהים כרשימה מופרדת בפסיקים ('' כשהמפתח חסר). }
function JIdList(const Raw: AnsiString; ObjPos: Integer;
  const Key: AnsiString): String;
var
  P: Integer;
begin
  Result := '';
  P := JArrFirst(Raw, JFind(Raw, ObjPos, Key));
  while P > 0 do
  begin
    if Raw[P] = '"' then
      Result := Result + Utf8Decode(JRawString(Raw, P)) + ',';
    P := JArrNext(Raw, P);
  end;
end;

{ פענוח המניפסט לוקח כמה שניות; עמוד החיבור מעבד בינתיים הודעות, כדי שהחלון
  לא ייראה תקוע. בלי אשף (DevSelectionDump) אין מה לעבד. }
procedure PumpMessages();
begin
  if Assigned(ConnectPage) then
    ConnectPage.SetProgress(0, 0);
end;

{ טקסט רכיב למשתמש, כמו componentText במימוש הייחוס: באנגלית `<Key>En`, ובהיעדרו
  (release ישן) — העברי. }
function ComponentText(const Raw: AnsiString; ObjPos: Integer; const Key: String;
  English: Boolean): String;
begin
  Result := '';
  if English then
    Result := JStr(Raw, ObjPos, Key + 'En');
  if Result = '' then
    Result := JStr(Raw, ObjPos, Key);
end;

function ParseManifest(const Raw: AnsiString): Boolean;
var
  CompPos, AssetPos, PartPos, ArrPos: Integer;
  NC, NA, NP: Integer;
  Schema: Int64;
begin
  Result := False;
  Schema := JInt(Raw, 1, 'schemaVersion');
  if Schema <> ManifestSchemaVersion then
  begin
    LoadErrorTech := 'schemaVersion=' + IntToStr(Schema);
    exit;
  end;
  PinnedTag := JStr(Raw, 1, 'releaseTag');
  ReleaseVersion := JStr(Raw, 1, 'releaseVersion');
  if (PinnedTag = '') or (ReleaseVersion = '') then
  begin
    LoadErrorTech := 'missing releaseTag/releaseVersion';
    exit;
  end;

  ArrPos := JFind(Raw, 1, 'components');
  if ArrPos = 0 then
  begin
    LoadErrorTech := 'no components';
    exit;
  end;

  NC := 0;
  NA := 0;
  NP := 0;
  CompPos := JArrFirst(Raw, ArrPos);
  while CompPos > 0 do
  begin
    SetArrayLength(CompId, NC + 1);
    SetArrayLength(CompName, NC + 1);
    SetArrayLength(CompDesc, NC + 1);
    SetArrayLength(CompType, NC + 1);
    SetArrayLength(CompPlatform, NC + 1);
    SetArrayLength(CompArch, NC + 1);
    SetArrayLength(CompFormat, NC + 1);
    SetArrayLength(CompDependsOn, NC + 1);
    SetArrayLength(CompInstalledBy, NC + 1);
    SetArrayLength(CompPartOf, NC + 1);
    SetArrayLength(CompOutputFolder, NC + 1);
    SetArrayLength(CompOutputNote, NC + 1);
    SetArrayLength(CompOutputNoteEn, NC + 1);
    SetArrayLength(CompRequired, NC + 1);
    SetArrayLength(CompSelected, NC + 1);
    SetArrayLength(CompDownloadSize, NC + 1);
    SetArrayLength(CompAssetStart, NC + 1);
    SetArrayLength(CompAssetCount, NC + 1);

    PumpMessages();
    CompId[NC] := JStr(Raw, CompPos, 'id');
    CompName[NC] := ComponentText(Raw, CompPos, 'name', EnglishUi());
    CompDesc[NC] := ComponentText(Raw, CompPos, 'description', EnglishUi());
    CompType[NC] := JStr(Raw, CompPos, 'type');
    CompPlatform[NC] := JStr(Raw, CompPos, 'platform');
    CompArch[NC] := JStr(Raw, CompPos, 'architecture');
    CompFormat[NC] := JStr(Raw, CompPos, 'packageFormat');
    CompRequired[NC] := JBool(Raw, CompPos, 'required');
    CompDownloadSize[NC] := JInt(Raw, CompPos, 'downloadSize');
    CompSelected[NC] := False;

    CompDependsOn[NC] := JIdList(Raw, CompPos, 'dependsOn');
    CompInstalledBy[NC] := JIdList(Raw, CompPos, 'installedBy');
    CompPartOf[NC] := JStr(Raw, CompPos, 'partOf');
    CompOutputFolder[NC] := JStr(Raw, CompPos, 'outputFolder');
    CompOutputNote[NC] := JStr(Raw, CompPos, 'outputNote');
    CompOutputNoteEn[NC] := JStr(Raw, CompPos, 'outputNoteEn');
    if (CompOutputFolder[NC] <> '') and
       not IsSafeOutputFolder(CompOutputFolder[NC]) then
    begin
      LoadErrorTech := 'bad outputFolder in component ' + CompId[NC];
      exit;
    end;

    CompAssetStart[NC] := NA;
    AssetPos := JArrFirst(Raw, JFind(Raw, CompPos, 'assets'));
    while AssetPos > 0 do
    begin
      SetArrayLength(AssetKind, NA + 1);
      SetArrayLength(AssetRepo, NA + 1);
      SetArrayLength(AssetTag, NA + 1);
      SetArrayLength(AssetName, NA + 1);
      SetArrayLength(AssetSha, NA + 1);
      SetArrayLength(AssetSize, NA + 1);
      SetArrayLength(AssetPartStart, NA + 1);
      SetArrayLength(AssetPartCount, NA + 1);
      SetArrayLength(AssetComp, NA + 1);

      AssetKind[NA] := JStr(Raw, AssetPos, 'kind');
      AssetRepo[NA] := JStr(Raw, AssetPos, 'repository');
      AssetTag[NA] := JStr(Raw, AssetPos, 'releaseTag');
      AssetName[NA] := JStr(Raw, AssetPos, 'name');
      AssetSha[NA] := JStr(Raw, AssetPos, 'sha256');
      AssetSize[NA] := JInt(Raw, AssetPos, 'size');
      AssetPartStart[NA] := NP;
      AssetComp[NA] := NC;

      PartPos := JArrFirst(Raw, JFind(Raw, AssetPos, 'parts'));
      while PartPos > 0 do
      begin
        SetArrayLength(PartName, NP + 1);
        SetArrayLength(PartSha, NP + 1);
        SetArrayLength(PartSize, NP + 1);
        PartName[NP] := JStr(Raw, PartPos, 'name');
        PartSha[NP] := JStr(Raw, PartPos, 'sha256');
        PartSize[NP] := JInt(Raw, PartPos, 'size');
        if not IsSafeName(PartName[NP]) or (Length(PartSha[NP]) <> 64) or
           (PartSize[NP] <= 0) then
        begin
          LoadErrorTech := 'bad part in component ' + CompId[NC];
          exit;
        end;
        NP := NP + 1;
        PartPos := JArrNext(Raw, PartPos);
      end;
      AssetPartCount[NA] := NP - AssetPartStart[NA];

      if (AssetName[NA] = '') or (Length(AssetSha[NA]) <> 64) or
         (AssetSize[NA] <= 0) or (AssetUrl(AssetRepo[NA], AssetTag[NA],
           AssetName[NA]) = '') then
      begin
        LoadErrorTech := 'bad asset in component ' + CompId[NC];
        exit;
      end;
      if (AssetKind[NA] = 'split') and (AssetPartCount[NA] = 0) then
      begin
        LoadErrorTech := 'split asset without parts: ' + AssetName[NA];
        exit;
      end;

      NA := NA + 1;
      AssetPos := JArrNext(Raw, AssetPos);
    end;
    CompAssetCount[NC] := NA - CompAssetStart[NC];

    if (CompId[NC] = '') or (JStr(Raw, CompPos, 'name') = '') or
       (CompAssetCount[NC] = 0) then
    begin
      LoadErrorTech := 'component without id/name/assets';
      exit;
    end;

    NC := NC + 1;
    CompPos := JArrNext(Raw, CompPos);
  end;

  Result := NC > 0;
  if not Result then
    LoadErrorTech := 'manifest has no components';
end;

{ WinHTTP: פג הזמן, השם לא נפתר, אין חיבור לשרת, החיבור נותק, החיבור אופס. }
function IsNetworkError(const Message: String): Boolean;
begin
  Result := (Pos('12002', Message) > 0) or (Pos('12007', Message) > 0) or
    (Pos('12029', Message) > 0) or (Pos('12030', Message) > 0) or
    (Pos('12031', Message) > 0);
end;

{ כל בקשה בלי hash עוברת כאן — רשימת ה-release והמניפסט בלבד — בעמוד שמעבד הודעות
  (בלי אשף: ישירות). כישלון רשת נספר, כדי להבחין בין "אין חיבור" למניפסט פגום. }
procedure FetchToTemp(const Url, FileName: String);
begin
  if StopRequested then
    RaiseException('stopped by user');
  LoadAttempts := LoadAttempts + 1;
  try
    if Assigned(ConnectPage) then
    begin
      ConnectPage.Clear;
      ConnectPage.Add(Url, FileName, '');
      ConnectPage.Download;
    end
    else
      DownloadTemporaryFile(Url, FileName, '', nil);
  except
    if IsNetworkError(GetExceptionMessage) then
      LoadNetworkFailures := LoadNetworkFailures + 1;
    RaiseException(GetExceptionMessage);
  end;
end;

{ JSON של release, או '' בכישלון הורדה/קריאה. }
function FetchReleaseJson(const Url, FileName: String): AnsiString;
var
  Raw: AnsiString;
begin
  Result := '';
  try
    FetchToTemp(Url, FileName);
  except
    LoadErrorTech := GetExceptionMessage;
    exit;
  end;
  if LoadStringFromFile(ExpandConstant('{tmp}\') + FileName, Raw) then
    Result := Raw
  else
    LoadErrorTech := 'cannot read ' + FileName;
end;

{ התג ננעל לכל הריצה — release שמתעדכן באמצע היה מערבב גרסאות. latest מדלג
  על prerelease, ולכן הוא גובר על התג המוטבע רק כשגרסתו גבוהה יותר. }
function LoadReleaseManifest(): Boolean;
var
  ApiRaw, ManifestRaw: AnsiString;
  ManifestPath, ManifestAsset, Url: String;
  EmbeddedTag, LatestTag: String;
  ElemPos: Integer;
  Name: String;
begin
  Result := False;
  LoadErrorMsg := CustomMessage('ErrorReadList');

#ifdef DevManifestFile
  { פיתוח בלבד (/DDevManifestFile=<path>): ה-CI לעולם אינו מגדיר את זה. }
  Log('DownloadAssistant: DEV manifest from {#DevManifestFile}');
  if LoadStringFromFile('{#DevManifestFile}', ManifestRaw) then
    Result := ParseManifest(ManifestRaw)
  else
    LoadErrorTech := 'cannot read {#DevManifestFile}';
  exit;
#endif

  EmbeddedTag := Trim('{#AssistantReleaseTag}');
  ApiRaw := FetchReleaseJson(ReleaseApiUrl('latest'), 'release.json');
  if ApiRaw <> '' then
    LatestTag := JStr(ApiRaw, 1, 'tag_name')
  else
    LatestTag := '';

  if EmbeddedTag = '' then
    PinnedTag := LatestTag
  else if (LatestTag <> '') and
          (CompareVersionText(LatestTag, EmbeddedTag) > 0) then
    PinnedTag := LatestTag
  else
    PinnedTag := EmbeddedTag;

  Log('DownloadAssistant: embedded=' + EmbeddedTag + ' latest=' + LatestTag +
    ' pinned=' + PinnedTag);
  if PinnedTag = '' then
  begin
    LoadErrorMsg := CustomMessage('ErrorConnect');
    if LoadErrorTech = '' then
      LoadErrorTech := 'release has no tag_name';
    exit;
  end;

  { התג המוטבע אינו צריך את ה-API: שם המניפסט קבוע, והכתובת הישירה אינה
    כפופה למגבלת הקצב. latest שנכשל פשוט אינו גובר עליו. }
  ManifestAsset := '';
  if PinnedTag <> LatestTag then
  begin
    ManifestAsset := ReleaseManifestAsset;
    Log('DownloadAssistant: manifest of ' + PinnedTag + ' by direct URL');
  end
  else
  begin
    ElemPos := JArrFirst(ApiRaw, JFind(ApiRaw, 1, 'assets'));
    while ElemPos > 0 do
    begin
      Name := JStr(ApiRaw, ElemPos, 'name');
      if EndsWithText(Name, 'release-manifest.json') then
      begin
        ManifestAsset := Name;
        Break;
      end;
      ElemPos := JArrNext(ApiRaw, ElemPos);
    end;
  end;
  if ManifestAsset = '' then
  begin
    LoadErrorTech := 'release ' + PinnedTag + ' has no release-manifest asset';
    exit;
  end;

  Url := AssetUrl('Otzaria/otzaria', PinnedTag, ManifestAsset);
  try
    FetchToTemp(Url, 'manifest.json');
  except
    LoadErrorTech := GetExceptionMessage;
    exit;
  end;
  ManifestPath := ExpandConstant('{tmp}\manifest.json');
  if not LoadStringFromFile(ManifestPath, ManifestRaw) then
  begin
    LoadErrorTech := 'cannot read manifest.json';
    exit;
  end;
  Result := ParseManifest(ManifestRaw);
end;

{ הנסיגה היחידה כשאין מניפסט: עמוד ההורדות בדפדפן. המסייע לא יוריד דבר בלי hash. }
procedure OpenDownloadsPage();
var
  ErrorCode: Integer;
begin
  ShellExecAsOriginalUser('open',
    'https://github.com/Otzaria/otzaria/releases/latest', '', '',
    SW_SHOWNORMAL, ewNoWait, ErrorCode);
end;

{ "התקן עכשיו" בעמוד הסיום: המסייע רק מפעיל את המתקין שהכין, ואינו מחכה לו. }
function RunInstaller(): Boolean;
var
  ErrorCode: Integer;
begin
  Result := ShellExec('', RunAfterExe, '', ExtractFileDir(RunAfterExe),
    SW_SHOWNORMAL, ewNoWait, ErrorCode);
  if not Result then
    Log('DownloadAssistant: cannot run ' + RunAfterExe + ': ' + IntToStr(ErrorCode));
end;

{ קובץ בודד מסומן בתוך התיקייה שלו; תיקייה נפתחת. }
procedure OpenOutputFolder();
var
  Params: String;
  ErrorCode: Integer;
begin
  if RevealIsFile then
    Params := '/select,"' + RevealPath + '"'
  else
    Params := '"' + RevealPath + '"';
  if not ExecAsOriginalUser(ExpandConstant('{win}\explorer.exe'), Params, '',
    SW_SHOWNORMAL, ewNoWait, ErrorCode) then
    Log('DownloadAssistant: explorer failed: ' + IntToStr(ErrorCode));
end;

{ ====================== מחשב היעד ====================== }

{ חוזה משותף לשלושת המסייעים; מימוש הייחוס הוא
  tool/release/download_assistant_selection.dart, ו-fixtures שלצדו. }

function IsWildcard(const Value: String): Boolean;
begin
  Result := (Value = '') or (Value = 'any');
end;

function ListIndex(const List: TArrayOfString; const Value: String): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to GetArrayLength(List) - 1 do
    if List[I] = Value then
    begin
      Result := I;
      exit;
    end;
end;

procedure ListAdd(var List: TArrayOfString; const Value: String);
var
  N: Integer;
begin
  if ListIndex(List, Value) >= 0 then
    exit;
  N := GetArrayLength(List);
  SetArrayLength(List, N + 1);
  List[N] := Value;
end;

procedure ListSort(var List: TArrayOfString);
var
  I, J: Integer;
  Value: String;
begin
  for I := 1 to GetArrayLength(List) - 1 do
  begin
    Value := List[I];
    J := I - 1;
    while (J >= 0) and (CompareStr(List[J], Value) > 0) do
    begin
      List[J + 1] := List[J];
      J := J - 1;
    end;
    List[J + 1] := Value;
  end;
end;

function PlatformDisplayName(const Platform: String): String;
begin
  if Platform = 'windows' then
    Result := CustomMessage('PlatformWindows')
  else if Platform = 'macos' then
    Result := CustomMessage('PlatformMacos')
  else if Platform = 'linux' then
    Result := CustomMessage('PlatformLinux')
  else if Platform = 'android' then
    Result := CustomMessage('PlatformAndroid')
  else
    Result := Platform;
end;

function FormatDisplayName(const Format: String): String;
begin
  if Format = 'deb' then
    Result := CustomMessage('FormatDeb')
  else if Format = 'rpm' then
    Result := CustomMessage('FormatRpm')
  else if Format = PortableFormat then
    Result := CustomMessage('FormatPortable')
  else
    Result := Format;
end;

{ רק פלטפורמות שיש להן רכיב ייעודי; רכיב 'any' לבדו אינו מספיק. }
function PlatformChoices(): TArrayOfString;
var
  Known: TArrayOfString;
  I: Integer;
begin
  SetArrayLength(Result, 0);
  Known := StringSplitEx(KnownPlatforms, [','], #0, stExcludeEmpty);
  for I := 0 to GetArrayLength(Known) - 1 do
    if ListIndex(CompPlatform, Known[I]) >= 0 then
      ListAdd(Result, Known[I]);
end;

function ArchitectureChoices(const Platform: String): TArrayOfString;
var
  I: Integer;
begin
  SetArrayLength(Result, 0);
  for I := 0 to GetArrayLength(CompId) - 1 do
    if (CompPlatform[I] = Platform) and not IsWildcard(CompArch[I]) then
      ListAdd(Result, CompArch[I]);
  ListSort(Result);
  I := ListIndex(Result, 'x64');
  while I > 0 do
  begin
    Result[I] := Result[I - 1];
    Result[I - 1] := 'x64';
    I := I - 1;
  end;
end;

{ 'portable' מוצע כשיש רכיב תוכנה שאינו תלוי מנהל חבילות. }
function PackageFormatChoices(const Platform, Architecture: String): TArrayOfString;
var
  I: Integer;
  Portable: Boolean;
begin
  SetArrayLength(Result, 0);
  Portable := False;
  for I := 0 to GetArrayLength(CompId) - 1 do
  begin
    if CompPlatform[I] <> Platform then
      Continue;
    if not IsWildcard(CompArch[I]) and (CompArch[I] <> Architecture) then
      Continue;
    if not IsWildcard(CompFormat[I]) then
      ListAdd(Result, CompFormat[I])
    else if Copy(CompType[I], 1, 11) = 'application' then
      Portable := True;
  end;
  if GetArrayLength(Result) = 0 then
    exit;
  ListSort(Result);
  if Portable then
    ListAdd(Result, PortableFormat);
end;

function DefaultIndex(const List: TArrayOfString; const Preferred: String): Integer;
begin
  Result := ListIndex(List, Preferred);
  if Result < 0 then
    Result := 0;
end;

function RunningArchitecture(): String;
begin
  if IsArm64 then
    Result := 'arm64'
  else
    Result := 'x64';
end;

function IsThisComputerMode(): Boolean;
begin
  Result := False;
  if Assigned(ModePage) then
    Result := ModePage.SelectedValueIndex = ModeThisComputer;
end;

{ "המחשב הזה" הוא Windows במעבד שעליו המסייע רץ; כל יעד אחר נבחר מהרשימה. }
procedure UpdateTarget();
var
  I: Integer;
begin
  if IsThisComputerMode() then
  begin
    TargetPlatform := 'windows';
    TargetArchitecture := RunningArchitecture();
    TargetFormat := '';
    exit;
  end;
  TargetPlatform := '';
  TargetArchitecture := '';
  TargetFormat := '';
  I := OtherPage.SelectedValueIndex;
  if (I < 0) or (I >= GetArrayLength(OtherPlatform)) then
    exit;
  TargetPlatform := OtherPlatform[I];
  TargetArchitecture := OtherArch[I];
  TargetFormat := OtherFormat[I];
end;

{ המעבד נזכר רק כשהוא ARM: Intel ו-AMD הם כמעט כל המחשבים. }
function TargetTitle(const Platform, Architecture: String): String;
begin
  Result := PlatformDisplayName(Platform);
  if Architecture = 'arm64' then
    Result := Msg1('TargetArm', Result);
end;

function TargetHint(const Platform, Architecture, Format: String): String;
begin
  if Format <> '' then
    Result := FormatDisplayName(Format)
  else if Platform = 'macos' then
    Result := CustomMessage('HintMac')
  else if Platform = 'android' then
    Result := CustomMessage('HintAndroid')
  else if Architecture = 'arm64' then
    Result := CustomMessage('HintArm')
  else if Architecture = 'x64' then
    Result := CustomMessage('HintX64')
  else
    Result := '';
end;

{ ====================== הצעות מוכנות מהמניפסט ====================== }

{ ההצעות נגזרות מ-type ומ-required, לא משמות קבצים — רכיב חדש נוחת בהצעה
  הנכונה בלי שינוי קוד. הצעה ריקה או זהה להצעה קודמת אינה מוצגת. }

{ שלושת השדות: חסר או 'any' מתאים לכל יעד; ערך לא מוכר אינו מתאים לאף יעד. }
function ComponentFitsTarget(Index: Integer): Boolean;
begin
  Result := False;
  if not IsWildcard(CompPlatform[Index]) and
     (CompPlatform[Index] <> TargetPlatform) then
    exit;
  if not IsWildcard(CompArch[Index]) and
     (CompArch[Index] <> TargetArchitecture) then
    exit;
  if not IsWildcard(CompFormat[Index]) and
     (CompFormat[Index] <> TargetFormat) then
    exit;
  Result := True;
end;

function IndexOfComponent(const Id: String): Integer;
begin
  Result := ListIndex(CompId, Id);
end;

function MembersContain(const Members, Id: String): Boolean;
begin
  Result := Pos(',' + Id + ',', ',' + Members) > 0;
end;

{ exe בגודל 4 GiB ומעלה אינו רץ, ולכן רכיב שנושא כזה אינו מוצע. }
function ComponentIsRunnable(Index: Integer): Boolean;
var
  A: Integer;
begin
  Result := True;
  for A := CompAssetStart[Index] to CompAssetStart[Index] + CompAssetCount[Index] - 1 do
    if IsExecutableName(AssetName[A]) and
       (AssetSize[A] >= MaxSingleOutputFileSize) then
      Result := False;
end;

{ המתקין הראשון ב-installedBy שמוצע ביעד, או -1. }
function InstallerFor(Index: Integer): Integer;
var
  Parts: TArrayOfString;
  J, Idx: Integer;
begin
  Result := -1;
  Parts := StringSplitEx(CompInstalledBy[Index], [','], #0, stExcludeEmpty);
  for J := 0 to GetArrayLength(Parts) - 1 do
  begin
    Idx := IndexOfComponent(Parts[J]);
    if (Idx >= 0) and ComponentFitsTarget(Idx) and ComponentIsRunnable(Idx) then
    begin
      Result := Idx;
      exit;
    end;
  end;
end;

{ מה שמוצע ביעד, בהצעות ובבחירה האישית: מתאים, ניתן להרצה, ואם מישהו אחר
  מתקין אותו (installedBy) — אחד מהם מוצע. }
function ComponentIsOffered(Index: Integer): Boolean;
begin
  Result := ComponentFitsTarget(Index) and ComponentIsRunnable(Index) and
    ((CompInstalledBy[Index] = '') or (InstallerFor(Index) >= 0));
end;

{ גודל השורה של רכיב בבחירה האישית: הוא והחלקים המוצעים שלו (partOf). }
function CustomChoiceSize(Index: Integer): Int64;
var
  J: Integer;
begin
  Result := CompDownloadSize[Index];
  for J := 0 to GetArrayLength(CompId) - 1 do
    if (CompPartOf[J] = CompId[Index]) and ComponentIsOffered(J) then
      Result := Result + CompDownloadSize[J];
end;

function AnyMember(const Members, Ids: String): Boolean;
var
  Parts: TArrayOfString;
  J: Integer;
begin
  Result := False;
  Parts := StringSplitEx(Ids, [','], #0, stExcludeEmpty);
  for J := 0 to GetArrayLength(Parts) - 1 do
    if MembersContain(Members, Parts[J]) then
      Result := True;
end;

{ סוגר את dependsOn (תלות שאינה מוצעת ביעד נדלגת), ולכל רכיב שמתקין שלו
  אינו בבחירה — את המתקין מ-InstallerFor. }
function WithDependencies(const Members: String): String;
var
  Changed: Boolean;
  I, J, Idx: Integer;
  Parts: TArrayOfString;
begin
  Result := Members;
  Changed := True;
  while Changed do
  begin
    Changed := False;
    for I := 0 to GetArrayLength(CompId) - 1 do
    begin
      if not MembersContain(Result, CompId[I]) then
        Continue;
      Parts := StringSplitEx(CompDependsOn[I], [','], #0, stExcludeEmpty);
      for J := 0 to GetArrayLength(Parts) - 1 do
      begin
        Idx := IndexOfComponent(Parts[J]);
        if (Idx >= 0) and ComponentIsOffered(Idx) and
           not MembersContain(Result, Parts[J]) then
        begin
          Result := Result + Parts[J] + ',';
          Changed := True;
        end;
      end;
      if (CompInstalledBy[I] <> '') and
         not AnyMember(Result, CompInstalledBy[I]) then
      begin
        Idx := InstallerFor(I);
        if Idx >= 0 then
        begin
          Result := Result + CompId[Idx] + ',';
          Changed := True;
        end;
      end;
    end;
  end;
end;

function MembersSize(const Members: String): Int64;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to GetArrayLength(CompId) - 1 do
    if MembersContain(Members, CompId[I]) then
      Result := Result + CompDownloadSize[I];
end;

{ צורה קנונית: כל מזהה פעם אחת, בסדר הרכיבים שבמניפסט. בלעדיה שתי הצעות
  שמכילות בדיוק את אותם רכיבים נראות שונות ושתיהן מוצגות. }
function CanonicalMembers(const Members: String): String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to GetArrayLength(CompId) - 1 do
    if MembersContain(Members, CompId[I]) then
      Result := Result + CompId[I] + ',';
end;

function DisplayRank(const Id: String): Integer;
begin
  Result := Pos(',' + Id + ',', ',' + PresetDisplayOrder);
end;

procedure AddPreset(const Id, Caption, Description, Members: String);
var
  N, I: Integer;
  Closed: String;
begin
  if Members = '' then
    exit;
  Closed := CanonicalMembers(WithDependencies(Members));
  if Closed = '' then
    exit;
  for I := 0 to GetArrayLength(PresetMembers) - 1 do
    if PresetMembers[I] = Closed then
      exit;
  N := GetArrayLength(PresetLabel);
  SetArrayLength(PresetId, N + 1);
  SetArrayLength(PresetLabel, N + 1);
  SetArrayLength(PresetDesc, N + 1);
  SetArrayLength(PresetSize, N + 1);
  SetArrayLength(PresetMembers, N + 1);
  { נכנסת למקומה בסדר ההצגה. }
  I := N;
  while (I > 0) and (DisplayRank(PresetId[I - 1]) > DisplayRank(Id)) do
  begin
    PresetId[I] := PresetId[I - 1];
    PresetLabel[I] := PresetLabel[I - 1];
    PresetDesc[I] := PresetDesc[I - 1];
    PresetSize[I] := PresetSize[I - 1];
    PresetMembers[I] := PresetMembers[I - 1];
    I := I - 1;
  end;
  PresetId[I] := Id;
  PresetLabel[I] := Caption;
  PresetSize[I] := HumanSize(MembersSize(Closed));
  PresetDesc[I] := Description;
  PresetMembers[I] := Closed;
end;

function CollectByTypes(const Types: String; RequiredOnly: Boolean): String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to GetArrayLength(CompId) - 1 do
  begin
    if not ComponentIsOffered(I) then
      Continue;
    if RequiredOnly and not CompRequired[I] then
      Continue;
    if (Types <> '') and not MembersContain(Types, CompType[I]) then
      Continue;
    Result := Result + CompId[I] + ',';
  end;
end;

{ החבילה וכל רכיב מוצע שהיא ב-installedBy שלו. }
function WithInstalled(Bundle: Integer): String;
var
  I: Integer;
begin
  Result := CompId[Bundle] + ',';
  for I := 0 to GetArrayLength(CompId) - 1 do
    if MembersContain(CompInstalledBy[I], CompId[Bundle]) and ComponentIsOffered(I) then
      Result := Result + CompId[I] + ',';
end;

{ החבילה של "מלאה": הגדולה ביותר שמוצעת ליעד, או -1. }
function FullPresetBundle(): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to GetArrayLength(CompId) - 1 do
    if ComponentIsOffered(I) and (CompType[I] = 'application-bundle') and
       ((Result < 0) or (CompDownloadSize[I] > CompDownloadSize[Result])) then
      Result := I;
end;

{ חבילה מאונדקסת: ספרייה מוצעת מותקנת על ידה. }
function InstallsLibrary(Bundle: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to GetArrayLength(CompId) - 1 do
    if (CompType[I] = 'library') and
       MembersContain(CompInstalledBy[I], CompId[Bundle]) and ComponentIsOffered(I) then
      Result := True;
end;

{ החבילה של "מלאה + אינדקס": המאונדקסת הגדולה ביותר עם מה שהיא מתקינה, או -1. }
function IndexedPresetBundle(): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to GetArrayLength(CompId) - 1 do
    if ComponentIsOffered(I) and (CompType[I] = 'application-bundle') and
       InstallsLibrary(I) and ((Result < 0) or
       (MembersSize(WithInstalled(I)) > MembersSize(WithInstalled(Result)))) then
      Result := I;
end;

procedure BuildPresets();
var
  Bundle: Integer;
  Members, Offline: String;
begin
  SetArrayLength(PresetId, 0);
  SetArrayLength(PresetLabel, 0);
  SetArrayLength(PresetDesc, 0);
  SetArrayLength(PresetSize, 0);
  SetArrayLength(PresetMembers, 0);
  Offline := CollectByTypes(OfflineDataTypes, False);

  { סדר ההוספה קובע איזו כפולה מושמטת: השם המפורט יותר נשאר. ב-Android, בלי
    חבילה — התוכנה עם הספרייה והאינדקס: בטלפון בניית האינדקס איטית מאוד. }
  Bundle := IndexedPresetBundle();
  if Bundle >= 0 then
    AddPreset('full-indexed', CustomMessage('PresetFullIndexed'),
      CustomMessage('PresetFullIndexedDesc'), WithInstalled(Bundle) + Offline)
  else if (TargetPlatform = 'android') and (FullPresetBundle() < 0) and
     (CollectByTypes('library,', False) <> '') then
    AddPreset('full-indexed', CustomMessage('PresetFullIndexed'),
      CustomMessage('PresetFullIndexedDesc'),
      CollectByTypes('application,library,dependency,', False) +
      CollectByTypes('library-index,', False) + Offline);

  { מלאה: החבילה הגדולה ביותר עם מה שהיא מתקינה, אחרת התוכנה עם הספרייה —
    ובלי ספרייה אין "מלאה". }
  Bundle := FullPresetBundle();
  if Bundle >= 0 then
    Members := WithInstalled(Bundle) + Offline
  else
  begin
    Members := CollectByTypes('application,library,dependency,', False);
    if CollectByTypes('library,', False) = '' then
      Members := ''
    else
      Members := Members + Offline;
  end;
  AddPreset('full', CustomMessage('PresetFull'), CustomMessage('PresetFullDesc'),
    Members);

  AddPreset('basic', CustomMessage('PresetBasic'), CustomMessage('PresetBasicDesc'),
    CollectByTypes('application,', False) + CollectByTypes('', True));

  AddPreset('update', CustomMessage('PresetUpdate'), CustomMessage('PresetUpdateDesc'),
    CollectByTypes('application,', False));

  { "בחירה אישית" אינה נגזרת מהמניפסט והיא תמיד האפשרות האחרונה. }
  CustomPresetIndex := GetArrayLength(PresetLabel);
end;

procedure ApplyPreset(Index: Integer);
var
  I: Integer;
begin
  for I := 0 to GetArrayLength(CompId) - 1 do
    CompSelected[I] := (Index >= 0) and (Index < GetArrayLength(PresetMembers)) and
      MembersContain(PresetMembers[Index], CompId[I]);
end;

{ ===================== הבחירה האישית (customChoices) ===================== }

function IsInstallerType(const CompTypeValue: String): Boolean;
begin
  Result := (CompTypeValue = 'application') or
    (CompTypeValue = 'application-bundle');
end;

{ המתקין הרגיל פורס ביעד ספרייה שלצדו — ואז החבילה המלאה מיותרת. }
function InstallerTakesLibrary(): Boolean;
var
  I, Idx: Integer;
begin
  Result := False;
  for I := 0 to GetArrayLength(CompId) - 1 do
    if ComponentIsOffered(I) then
    begin
      Idx := InstallerFor(I);
      if (Idx >= 0) and (CompType[Idx] = 'application') then
        Result := True;
    end;
end;

{ שורה בבחירה האישית: מוצע, לא גרסה ניידת, ולא חבילה מלאה כשהמתקין הרגיל
  פורס ספרייה. }
function IsCustomChoice(Index: Integer; TakesLibrary: Boolean): Boolean;
begin
  Result := ComponentIsOffered(Index) and (CompPartOf[Index] = '') and
    (CompType[Index] <> 'application-portable') and
    not (TakesLibrary and (CompType[Index] = 'application-bundle'));
end;

{ יותר מדרך אחת להתקין את התוכנה: בחירה אחת-מתוך, כדי שלא יורדו שתיהן. }
function CustomInstallersAreRadio(TakesLibrary: Boolean): Boolean;
var
  I, N: Integer;
begin
  N := 0;
  for I := 0 to GetArrayLength(CompId) - 1 do
    if IsCustomChoice(I, TakesLibrary) and IsInstallerType(CompType[I]) then
      N := N + 1;
  Result := N > 1;
end;

{ ========================= צורת הפלט ========================= }

{ יעד Windows: רק exe מתחת ל-4 GiB — ארכיון נשאר חלקים, כי המתקין שצורך
  אותו קורא אותם. כל יעד אחר: כל נכס מתחת ל-4 GiB, כי שם המשתמש פורס אותו. }
function ShouldAssembleSingleFile(AssetIndex: Integer): Boolean;
begin
  Result := False;
  if AssetSize[AssetIndex] >= MaxSingleOutputFileSize then
    exit;
  if TargetPlatform = 'windows' then
    Result := IsExecutableName(AssetName[AssetIndex])
  else
    Result := True;
end;

{ הפלטפורמה בשם, כדי שהכנה לשני יעדים באותו דיסק-און-קי לא תערבב קבצים. באנגלית
  השם באנגלית; ContractSubfolder הוא השם של החוזה המשותף. }
function OutputSubFolderName(): String;
begin
  Result := Msg1('OutputSubfolder', PlatformDisplayName(TargetPlatform));
end;

{ הקבצים שייווצרו ביעד, בסדר המניפסט — לפי אותם כללים שמריץ PrepareOutput.
  קובץ של רכיב עם outputFolder נקרא '<folder>/<name>', כמו במימוש הייחוס. }
function PlannedOutputNames(): TArrayOfString;
var
  C, A, P, N: Integer;
  Prefix: String;
begin
  SetArrayLength(Result, 0);
  N := 0;
  for C := 0 to GetArrayLength(CompId) - 1 do
  begin
    if not CompSelected[C] then
      Continue;
    Prefix := '';
    if CompOutputFolder[C] <> '' then
      Prefix := CompOutputFolder[C] + '/';
    for A := CompAssetStart[C] to CompAssetStart[C] + CompAssetCount[C] - 1 do
    begin
      if (AssetKind[A] = 'split') and not ShouldAssembleSingleFile(A) then
      begin
        for P := AssetPartStart[A] to AssetPartStart[A] + AssetPartCount[A] - 1 do
        begin
          SetArrayLength(Result, N + 1);
          Result[N] := Prefix + PartName[P];
          N := N + 1;
        end;
      end
      else
      begin
        SetArrayLength(Result, N + 1);
        Result[N] := Prefix + AssetName[A];
        N := N + 1;
      end;
    end;
  end;
end;

function ProducedFileCount(): Integer;
begin
  Result := GetArrayLength(PlannedOutputNames());
end;

{ ההסברים (outputNote) של הרכיבים שנבחרו, בסדר המניפסט ובלי כפולים — לפי הטקסט
  שמוצג, כמו plannedOutputNotes במימוש הייחוס. }
function PlannedOutputNotes(English: Boolean): TArrayOfString;
var
  C, N: Integer;
  Note: String;
begin
  SetArrayLength(Result, 0);
  N := 0;
  for C := 0 to GetArrayLength(CompId) - 1 do
  begin
    Note := CompOutputNote[C];
    if English and (CompOutputNoteEn[C] <> '') then
      Note := CompOutputNoteEn[C];
    if CompSelected[C] and (Note <> '') and (ListIndex(Result, Note) < 0) then
    begin
      SetArrayLength(Result, N + 1);
      Result[N] := Note;
      N := N + 1;
    end;
  end;
end;

#ifdef DevSelectionDump
{ פיתוח בלבד (/DDevSelectionDump=<path>): מריץ את כללי הבחירה על כל יעד
  ושומר אותם להשוואה מול expected-selections.json. ה-CI לעולם אינו מגדיר. }
procedure DumpSelections();
var
  Platforms, Archs, Formats, Names: TArrayOfString;
  P, A, F, I, J: Integer;
  Text, Line: String;
  TakesLibrary, Radio: Boolean;
begin
  Text := '';
  Platforms := PlatformChoices();
  for P := 0 to GetArrayLength(Platforms) - 1 do
  begin
    Archs := ArchitectureChoices(Platforms[P]);
    Text := Text + 'platform ' + Platforms[P] + ' archs=';
    for I := 0 to GetArrayLength(Archs) - 1 do
      Text := Text + Archs[I] + ',';
    Text := Text + #10;
    if GetArrayLength(Archs) = 0 then
    begin
      SetArrayLength(Archs, 1);
      Archs[0] := '';
    end;
    for A := 0 to GetArrayLength(Archs) - 1 do
    begin
      Formats := PackageFormatChoices(Platforms[P], Archs[A]);
      Text := Text + 'formats ' + Platforms[P] + '/' + Archs[A] + '=';
      for I := 0 to GetArrayLength(Formats) - 1 do
        Text := Text + Formats[I] + ',';
      Text := Text + #10;
      if GetArrayLength(Formats) = 0 then
      begin
        SetArrayLength(Formats, 1);
        Formats[0] := '';
      end;
      for F := 0 to GetArrayLength(Formats) - 1 do
      begin
        TargetPlatform := Platforms[P];
        TargetArchitecture := Archs[A];
        TargetFormat := Formats[F];
        Line := '';
        for I := 0 to GetArrayLength(CompId) - 1 do
          if ComponentIsOffered(I) then
            Line := Line + CompId[I] + ',';
        Text := Text + 'target ' + TargetPlatform + '/' + TargetArchitecture +
          '/' + TargetFormat + ' offered=' + Line + #10;
        { id:size:locked:group — כמו customChoices ב-expected-selections.json. }
        TakesLibrary := InstallerTakesLibrary();
        Radio := CustomInstallersAreRadio(TakesLibrary);
        Line := '';
        for I := 0 to GetArrayLength(CompId) - 1 do
          if IsCustomChoice(I, TakesLibrary) then
          begin
            Line := Line + CompId[I] + ':' + IntToStr(CustomChoiceSize(I)) + ':';
            if IsInstallerType(CompType[I]) and not Radio then
              Line := Line + 'locked';
            Line := Line + ':';
            if IsInstallerType(CompType[I]) and Radio then
              Line := Line + 'application';
            Line := Line + ',';
          end;
        Text := Text + 'custom ' + Line + #10;
        BuildPresets();
        for I := 0 to GetArrayLength(PresetId) - 1 do
        begin
          ApplyPreset(I);
          Names := PlannedOutputNames();
          Line := '';
          for J := 0 to GetArrayLength(Names) - 1 do
            Line := Line + Names[J] + '|';
          Text := Text + 'preset ' + PresetId[I] + ' members=' +
            PresetMembers[I] + ' files=' + Line + ' subfolder=';
          if GetArrayLength(Names) > 1 then
            Text := Text + Msg1('ContractSubfolder',
              PlatformDisplayName(TargetPlatform));
          Names := PlannedOutputNotes(False);
          Line := '';
          for J := 0 to GetArrayLength(Names) - 1 do
            Line := Line + Names[J] + '|';
          Text := Text + ' notes=' + Line + #10;
        end;
      end;
    end;
  end;
  SaveStringToFile('{#DevSelectionDump}', Utf8Encode(Text), False);
end;
#endif

{ ============================== עמודים ============================== }

procedure RefreshPresetPage();
var
  I: Integer;
begin
  BuildPresets();
  PresetPage.CheckListBox.Items.Clear;
  for I := 0 to GetArrayLength(PresetLabel) - 1 do
  begin
    PresetPage.Add(OptionCaption(PresetLabel[I], PresetDesc[I]));
    PresetPage.CheckListBox.ItemSubItem[I] := PresetSize[I];
  end;
  PresetPage.Add(OptionCaption(CustomMessage('PresetCustom'),
    CustomMessage('PresetCustomDesc')));
  if PresetPage.SelectedValueIndex < 0 then
  begin
    { בלי "בסיסית" — "מלאה", ולא "מלאה + אינדקס" הגדולה ממנה. }
    I := ListIndex(PresetId, 'basic');
    if I < 0 then
      I := DefaultIndex(PresetId, 'full');
    PresetPage.SelectedValueIndex := I;
  end;
end;

{ המתקין נעול כשאין לו חלופה; עם חלופה (חבילה מלאה) — כפתורי רדיו. }
procedure RefreshCustomPage();
var
  I, N, PickRow: Integer;
  TakesLibrary, Radio, Locked: Boolean;
  Caption: String;
begin
  CustomPage.CheckListBox.Items.Clear;
  SetArrayLength(CustomIndex, 0);
  TakesLibrary := InstallerTakesLibrary();
  Radio := CustomInstallersAreRadio(TakesLibrary);
  PickRow := -1;
  N := 0;
  for I := 0 to GetArrayLength(CompId) - 1 do
  begin
    if not IsCustomChoice(I, TakesLibrary) then
      Continue;
    Locked := IsInstallerType(CompType[I]) and not Radio;
    Caption := CompName[I];
    if Locked or (CompRequired[I] and not IsInstallerType(CompType[I])) then
      Caption := Caption + ' ' + CustomMessage('RequiredTag');
    if IsInstallerType(CompType[I]) and Radio then
    begin
      { הבחירה נקבעת בסוף: הוספת רדיו ראשון מסמנת אותו מעצמה. }
      CustomPage.CheckListBox.AddRadioButton(OptionCaption(Caption, CompDesc[I]),
        HumanSize(CustomChoiceSize(I)), 0, False, True, nil);
      if PickRow < 0 then
        PickRow := N
      else if not CompSelected[CustomIndex[PickRow]] and (CompSelected[I] or
         ((CompType[CustomIndex[PickRow]] <> 'application') and
         (CompType[I] = 'application'))) then
        PickRow := N;
    end
    else
      CustomPage.CheckListBox.AddCheckBox(OptionCaption(Caption, CompDesc[I]),
        HumanSize(CustomChoiceSize(I)), 0,
        CompSelected[I] or CompRequired[I] or Locked, not Locked, False, False, nil);
    SetArrayLength(CustomIndex, N + 1);
    CustomIndex[N] := I;
    N := N + 1;
  end;
  if PickRow >= 0 then
    CustomPage.Values[PickRow] := True;
end;

{ רכיב שסומן מסמן את תלויותיו, ורכיב שבוטל מבטל את מי שתלוי בו (אינדקס←ספרייה). }
procedure CustomChoiceClicked(Sender: TObject);
var
  Row, J: Integer;
begin
  Row := CustomPage.CheckListBox.ItemIndex;
  if (Row < 0) or (Row >= GetArrayLength(CustomIndex)) then
    exit;
  for J := 0 to GetArrayLength(CustomIndex) - 1 do
    if J <> Row then
    begin
      if CustomPage.Values[Row] and MembersContain(CompDependsOn[CustomIndex[Row]],
         CompId[CustomIndex[J]]) then
        CustomPage.Values[J] := True
      else if not CustomPage.Values[Row] and
         MembersContain(CompDependsOn[CustomIndex[J]], CompId[CustomIndex[Row]]) then
        CustomPage.Values[J] := False;
    end;
end;

{ "3 דקות", "שעה ו-10 דקות" — בלי שניות מדויקות, שממילא אינן יציבות. }
function HumanDuration(Seconds: Int64): String;
var
  Hours, Minutes: Int64;
  MinutesText: String;
begin
  if Seconds < 60 then
  begin
    Result := CustomMessage('DurationUnderMinute');
    exit;
  end;
  Hours := Seconds div 3600;
  Minutes := (Seconds mod 3600 + 30) div 60;
  if Minutes = 60 then
  begin
    Hours := Hours + 1;
    Minutes := 0;
  end;
  if Hours = 0 then
    Result := ''
  else if Hours = 1 then
    Result := CustomMessage('DurationHour')
  else if Hours = 2 then
    Result := CustomMessage('DurationTwoHours')
  else
    Result := Msg1('DurationHours', IntToStr(Hours));
  if Minutes = 0 then
    exit;
  if Minutes = 1 then
    MinutesText := CustomMessage('DurationMinute')
  else
    MinutesText := Msg1('DurationMinutes', IntToStr(Minutes));
  if Result = '' then
    Result := MinutesText
  else
    Result := FmtMessage(CustomMessage('DurationJoin'), [Result, MinutesText]);
end;

function HumanRate(BytesPerSecond: Int64): String;
var
  Tenths: Int64;
begin
  if BytesPerSecond >= 1048576 then
  begin
    Tenths := (BytesPerSecond * 10) div 1048576;
    Result := LtrUnit(IntToStr(Tenths div 10) + '.' + IntToStr(Tenths mod 10) +
      ' MB/s');
  end
  else
    Result := LtrUnit(IntToStr(BytesPerSecond div 1024) + ' KB/s');
end;

procedure ResetSpeed();
begin
  SetArrayLength(SampleTick, 0);
  SetArrayLength(SampleBytes, 0);
end;

{ ממוצע נע על ~5 שניות: נשמרת דגימה כל רבע שנייה, והישנות נזרקות. }
procedure AddSpeedSample(Bytes: Int64);
var
  N, I: Integer;
  Tick: Int64;
begin
  Tick := NowMs();
  N := GetArrayLength(SampleTick);
  if (N > 0) and (Tick < SampleTick[N - 1]) then
  begin
    ResetSpeed();
    N := 0;
  end;
  if (N > 0) and (Tick - SampleTick[N - 1] < 250) then
    exit;
  SetArrayLength(SampleTick, N + 1);
  SetArrayLength(SampleBytes, N + 1);
  SampleTick[N] := Tick;
  SampleBytes[N] := Bytes;
  N := N + 1;
  while (N > 2) and (Tick - SampleTick[1] >= SpeedWindowMs) do
  begin
    for I := 0 to N - 2 do
    begin
      SampleTick[I] := SampleTick[I + 1];
      SampleBytes[I] := SampleBytes[I + 1];
    end;
    N := N - 1;
    SetArrayLength(SampleTick, N);
    SetArrayLength(SampleBytes, N);
  end;
end;

{ בתים לשנייה, או ‎-1‎ כשעדיין אין מספיק דגימות. }
function CurrentSpeed(): Int64;
var
  N: Integer;
  Elapsed: Int64;
begin
  Result := -1;
  N := GetArrayLength(SampleTick);
  if N < 2 then
    exit;
  Elapsed := SampleTick[N - 1] - SampleTick[0];
  if Elapsed < 1000 then
    exit;
  Result := ((SampleBytes[N - 1] - SampleBytes[0]) * 1000) div Elapsed;
end;

{ הקבצים יורדים אחד-אחד כדי שכל קובץ שהושלם ייכנס למטמון מיד, ולכן הסכום
  הכולל, המהירות והזמן המשוער מחושבים כאן ולא בעמוד עצמו. }
function OnDownloadProgress(const Url, FileName: String;
  const Progress, ProgressMax: Int64): Boolean;
var
  Done, Speed: Int64;
  Status: String;
begin
  Done := ProgressDone + Progress;
  AddSpeedSample(Done);
  Status := FmtMessage(CustomMessage('DownloadedOf'), [HumanSize(Done),
    HumanSize(ProgressTotal)]);
  Speed := CurrentSpeed();
  if Speed > 0 then
    Status := Status + ' · ' + HumanRate(Speed) + ' · ' +
      Msg1('TimeLeft', HumanDuration((ProgressTotal - Done) div Speed));
  DownloadStatus := Status;
  { Inno מחשב את ה-hash אחרי הבית האחרון בלי לדווח התקדמות — הכותרת מסבירה
    למה הפס עומד. }
  if (ProgressMax > 0) and (Progress >= ProgressMax) then
  begin
    if VerifyStartTick = 0 then
    begin
      VerifyStartTick := NowMs();
      Log('DownloadAssistant: ' + FileName + ' received, download page verifies');
    end;
    DownloadPage.SetText(CustomMessage('CheckingDownloadedFile'), Status);
  end
  else
    DownloadPage.SetText(ProgressCaption, Status);
  Result := not StopRequested;
end;

{ בעמוד החיבור אין מה להציג; Inno עוצר כשהפונקציה מחזירה False. }
function OnConnectProgress(const Url, FileName: String;
  const Progress, ProgressMax: Int64): Boolean;
begin
  Result := not StopRequested;
end;

{ המתאם של שכבת התצוגה: קורא את העמודים שלמטה וכותב אליהם, ואינו משנה כלל. }
#include "download_assistant_ui.iss"

{ "macOS, Linux, Android או Windows מסוג אחר" — מתוך הרשימה עצמה. }
function OtherSummary(): String;
var
  Names: TArrayOfString;
  I, N: Integer;
begin
  SetArrayLength(Names, 0);
  for I := 0 to GetArrayLength(OtherPlatform) - 1 do
    if OtherPlatform[I] <> 'windows' then
      ListAdd(Names, PlatformDisplayName(OtherPlatform[I]));
  if ListIndex(OtherPlatform, 'windows') >= 0 then
    ListAdd(Names, CustomMessage('OtherWindows'));
  Result := '';
  N := GetArrayLength(Names);
  for I := 0 to N - 1 do
    if I = 0 then
      Result := Names[I]
    else if I = N - 1 then
      Result := FmtMessage(CustomMessage('ListOr'), [Result, Names[I]])
    else
      Result := Result + ', ' + Names[I];
end;

{ כל יעד שהמניפסט מציע בו משהו, חוץ מהמחשב הזה, בסדר שבו DumpSelections עובר
  עליהם. נבנה רק אחרי שהמניפסט נטען. }
procedure FillOtherPage();
var
  Platforms, Archs, Formats: TArrayOfString;
  P, A, F, I, N: Integer;
  Offered: Boolean;
begin
  N := 0;
  Platforms := PlatformChoices();
  for P := 0 to GetArrayLength(Platforms) - 1 do
  begin
    Archs := ArchitectureChoices(Platforms[P]);
    if GetArrayLength(Archs) = 0 then
    begin
      SetArrayLength(Archs, 1);
      Archs[0] := '';
    end;
    for A := 0 to GetArrayLength(Archs) - 1 do
    begin
      if (Platforms[P] = 'windows') and (Archs[A] = RunningArchitecture()) then
        Continue;
      Formats := PackageFormatChoices(Platforms[P], Archs[A]);
      if GetArrayLength(Formats) = 0 then
      begin
        SetArrayLength(Formats, 1);
        Formats[0] := '';
      end;
      for F := 0 to GetArrayLength(Formats) - 1 do
      begin
        TargetPlatform := Platforms[P];
        TargetArchitecture := Archs[A];
        TargetFormat := Formats[F];
        Offered := False;
        for I := 0 to GetArrayLength(CompId) - 1 do
          if ComponentIsOffered(I) then
            Offered := True;
        if not Offered then
          Continue;
        SetArrayLength(OtherPlatform, N + 1);
        SetArrayLength(OtherArch, N + 1);
        SetArrayLength(OtherFormat, N + 1);
        OtherPlatform[N] := Platforms[P];
        OtherArch[N] := Archs[A];
        OtherFormat[N] := Formats[F];
        OtherPage.Add(TargetTitle(Platforms[P], Archs[A]));
        OtherPage.CheckListBox.ItemSubItem[N] :=
          TargetHint(Platforms[P], Archs[A], Formats[F]);
        Log('DownloadAssistant: other target ' + Platforms[P] + '/' + Archs[A] +
          '/' + Formats[F]);
        N := N + 1;
      end;
    end;
  end;
  ModePage.CheckListBox.ItemSubItem[ModeOtherComputer] :=
    Msg1('ModeOtherDesc', OtherSummary());
end;

procedure InitializeWizard();
var
  DefaultBase, FolderNote: String;
begin
  ModePage := CreateInputOptionPage(wpWelcome, CustomMessage('ModeTitle'),
    CustomMessage('ModeDesc'), '', True, False);
  ModePage.Add(CustomMessage('ModeThis'));
  ModePage.Add(CustomMessage('ModeOther'));
  if RunningArchitecture() = 'arm64' then
    ModePage.CheckListBox.ItemSubItem[ModeThisComputer] :=
      CustomMessage('ModeThisArmDesc')
  else
    ModePage.CheckListBox.ItemSubItem[ModeThisComputer] :=
      CustomMessage('ModeThisX64Desc');
  ModePage.SelectedValueIndex := ModeThisComputer;

  { בלי בחירה מראש: אין יעד "אחר" שמתאים לרוב המשתמשים. }
  OtherPage := CreateInputOptionPage(ModePage.ID, CustomMessage('OtherTitle'),
    CustomMessage('OtherDesc'), CustomMessage('OtherHint'), True, False);

  PresetPage := CreateInputOptionPage(OtherPage.ID, CustomMessage('PresetTitle'),
    CustomMessage('PresetDesc'), CustomMessage('PresetHint'), True, False);

  CustomPage := CreateInputOptionPage(PresetPage.ID, CustomMessage('PresetCustom'),
    CustomMessage('CustomDesc'), CustomMessage('CustomHint'), False, True);
  CustomPage.CheckListBox.OnClickCheck := @CustomChoiceClicked;

  DefaultBase := AssistantDir();
  FolderNote := '';
  if not DirIsWritable(DefaultBase) then
  begin
    DefaultBase := FallbackOutputBase();
    FolderNote := #13#10#13#10 + CustomMessage('FolderFallbackNote');
  end;

  FolderPage := CreateInputDirPage(CustomPage.ID, CustomMessage('FolderTitle'),
    CustomMessage('FolderDesc'), CustomMessage('FolderHint') + FolderNote, False, '');
  FolderPage.Add('');
  FolderPage.Values[0] := DefaultBase;

  ConnectPage := CreateDownloadPage(CustomMessage('ConnectTitle'),
    CustomMessage('ConnectDesc'), @OnConnectProgress);
  DownloadPage := CreateDownloadPage(CustomMessage('DownloadTitle'),
    CustomMessage('DownloadDesc'), @OnDownloadProgress);
  WorkPage := CreateOutputProgressPage(CustomMessage('WorkTitle'),
    CustomMessage('WorkDesc'));
  UiAssistantInitializeWizard();
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if PageID = OtherPage.ID then
    Result := IsThisComputerMode()
  else if PageID = CustomPage.ID then
    Result := PresetPage.SelectedValueIndex <> CustomPresetIndex;
end;

{ ====================== בניית תור ההורדה ====================== }

procedure QueueAdd(const Url, FileName, Sha, Caption: String; Size: Int64);
var
  N: Integer;
begin
  N := GetArrayLength(QueueUrl);
  SetArrayLength(QueueUrl, N + 1);
  SetArrayLength(QueueFile, N + 1);
  SetArrayLength(QueueSha, N + 1);
  SetArrayLength(QueueLabel, N + 1);
  SetArrayLength(QueueSize, N + 1);
  QueueUrl[N] := Url;
  QueueFile[N] := FileName;
  QueueSha[N] := Sha;
  QueueLabel[N] := Caption;
  QueueSize[N] := Size;
end;

function OutputBaseDir(): String;
begin
  Result := RemoveBackslashUnlessRoot(FolderPage.Values[0]);
end;

{ קובץ בודד יושב ישירות בתיקייה שנבחרה; כמה קבצים שחייבים להישאר יחד מקבלים
  תיקייה משלהם. }
function OutputDir(): String;
begin
  Result := OutputBaseDir();
  if ProducedFileCount() > 1 then
    Result := Result + '\' + OutputSubFolderName();
end;

{ התיקייה של קובצי הרכיב: OutputDir, ובתוכה outputFolder כשיש. }
function AssetOutputDir(AssetIndex: Integer): String;
var
  Folder: String;
begin
  Result := OutputDir();
  Folder := CompOutputFolder[AssetComp[AssetIndex]];
  if Folder <> '' then
  begin
    StringChangeEx(Folder, '/', '\', True);
    Result := Result + '\' + Folder;
  end;
end;

{ הקובץ שכבר מורכב ביעד: גודל תואם וחותם מהמטמון שנכתב אחרי ההרכבה. }
function AssembledIsReady(AssetIndex: Integer): Boolean;
begin
  Result := FileMatchesMarker(AssetOutputDir(AssetIndex) + '\' + AssetName[AssetIndex],
    AssetName[AssetIndex], AssetSize[AssetIndex], AssetSha[AssetIndex]);
end;

function AssemblyTmpPath(AssetIndex: Integer): String;
begin
  Result := AssetOutputDir(AssetIndex) + '\' + AssetName[AssetIndex] + '.tmp';
end;

{ `<name>.tmp.sha256` נכתב לפני הבית הראשון. שם הנכס חוזר בין בניות של אותה
  גרסה, ובלעדיו .tmp של בנייה אחרת היה נספר כחלקים שכבר נבלעו. }
function AssemblyTmpBelongs(AssetIndex: Integer): Boolean;
var
  Raw: AnsiString;
begin
  Result := LoadStringFromFile(AssemblyTmpPath(AssetIndex) + '.sha256', Raw) and
    (Lowercase(Copy(Raw, 1, 64)) = Lowercase(AssetSha[AssetIndex]));
end;

{ כמה חלקים כבר נבלעו לתוך קובץ ההרכבה החלקי. חלק נמחק רק אחרי שהוספתו
  הושלמה, ולכן גודל הקובץ החלקי מזהה בדיוק היכן נעצרנו. }
function ConsumedPartCount(AssetIndex: Integer; var Prefix: Int64): Integer;
var
  TmpPath: String;
  Size, Acc: Int64;
  I: Integer;
begin
  Result := 0;
  Prefix := 0;
  TmpPath := AssemblyTmpPath(AssetIndex);
  if not FileExists(TmpPath) then
    exit;
  if not AssemblyTmpBelongs(AssetIndex) then
  begin
    Log('DownloadAssistant: discarding foreign partial ' + TmpPath);
    DeleteFile(TmpPath);
    DeleteFile(TmpPath + '.sha256');
    exit;
  end;
  if not FileSize64(TmpPath, Size) then
    exit;
  Acc := 0;
  for I := 0 to AssetPartCount[AssetIndex] - 1 do
  begin
    if Acc + PartSize[AssetPartStart[AssetIndex] + I] > Size then
      Break;
    Acc := Acc + PartSize[AssetPartStart[AssetIndex] + I];
    Result := Result + 1;
    Prefix := Acc;
  end;
end;

{ בונה את תור ההורדה: מה שכבר במטמון ומאומת אינו נכנס אליו. }
function BuildQueue(): Boolean;
var
  C, A, P, First, Consumed: Integer;
  Prefix: Int64;
  Url: String;
begin
  SetArrayLength(QueueUrl, 0);
  SetArrayLength(QueueFile, 0);
  SetArrayLength(QueueSha, 0);
  SetArrayLength(QueueLabel, 0);
  SetArrayLength(QueueSize, 0);
  Result := True;

  WorkPage.SetText(CustomMessage('CheckingCached'), '');
  WorkPage.Show;
  try
    for C := 0 to GetArrayLength(CompId) - 1 do
    begin
      if not CompSelected[C] then
        Continue;
      for A := CompAssetStart[C] to CompAssetStart[C] + CompAssetCount[C] - 1 do
      begin
        WorkPage.SetText(CustomMessage('CheckingCached'), CompName[C]);
        if AssetKind[A] = 'split' then
        begin
          if ShouldAssembleSingleFile(A) and AssembledIsReady(A) then
            Continue;
          if ShouldAssembleSingleFile(A) then
            Consumed := ConsumedPartCount(A, Prefix)
          else
            Consumed := 0;
          First := AssetPartStart[A];
          for P := First + Consumed to First + AssetPartCount[A] - 1 do
          begin
            if CachedFileIsGood(PartName[P], PartSize[P], PartSha[P]) then
              Continue;
            Url := AssetUrl(AssetRepo[A], AssetTag[A], PartName[P]);
            if Url = '' then
            begin
              Result := False;
              LoadErrorTech := 'refusing non-Otzaria url for ' + PartName[P];
              exit;
            end;
            QueueAdd(Url, PartName[P], PartSha[P], CompName[C], PartSize[P]);
          end;
        end
        else
        begin
          if CachedFileIsGood(AssetName[A], AssetSize[A], AssetSha[A]) then
            Continue;
          Url := AssetUrl(AssetRepo[A], AssetTag[A], AssetName[A]);
          if Url = '' then
          begin
            Result := False;
            LoadErrorTech := 'refusing non-Otzaria url for ' + AssetName[A];
            exit;
          end;
          QueueAdd(Url, AssetName[A], AssetSha[A], CompName[C], AssetSize[A]);
        end;
      end;
    end;
  finally
    WorkPage.Hide;
  end;
end;

{ ============================== הורדה ============================== }

function RunDownloads(): Boolean;
var
  I, Attempt: Integer;
  Started: Int64;
  Failure: String;
begin
  Result := True;
  if GetArrayLength(QueueUrl) = 0 then
    exit;

  ProgressTotal := 0;
  ProgressDone := 0;
  for I := 0 to GetArrayLength(QueueUrl) - 1 do
    ProgressTotal := ProgressTotal + QueueSize[I];

  DownloadPage.ShowBaseNameInsteadOfUrl := True;
  DownloadStatus := '';
  DownloadPage.Show;
  try
    for I := 0 to GetArrayLength(QueueUrl) - 1 do
    begin
      Attempt := 1;
      repeat
        if Attempt = 1 then
          ProgressCaption := FmtMessage(CustomMessage('DownloadingItem'), [QueueLabel[I],
            IntToStr(I + 1), IntToStr(GetArrayLength(QueueUrl))])
        else
          ProgressCaption := FmtMessage(CustomMessage('DownloadingItemAgain'), [QueueLabel[I],
            IntToStr(Attempt), IntToStr(DownloadAttempts)]);
        DownloadPage.SetText(ProgressCaption, '');
        DownloadPage.Clear;
        ResetSpeed();
        VerifyStartTick := 0;
        Started := NowMs();
        { ה-hash מהמניפסט מועבר תמיד — קובץ שאינו תואם נדחה כאן ולא נשמר. }
        DownloadPage.Add(QueueUrl[I], QueueFile[I], QueueSha[I]);
        try
          DownloadPage.Download;
          Failure := '';
        except
          if DownloadPage.AbortedByUser then
            StopRequested := True;
          Failure := GetExceptionMessage;
          Log('DownloadAssistant: ' + QueueFile[I] + ' attempt ' +
            IntToStr(Attempt) + ' failed: ' + Failure);
        end;
        Attempt := Attempt + 1;
      until (Failure = '') or StopRequested or (Attempt > DownloadAttempts);
      if Failure <> '' then
      begin
        if StopRequested then
          LoadErrorMsg := CustomMessage('ErrorStopped')
        else
        begin
          { כשה-hash מועבר Inno אינו משווה גודל, ולכן הורדה קטועה נכשלת כ-hash שגוי. }
          if Pos(SetupMessage(msgVerificationFileHashIncorrect), Failure) > 0 then
            LoadErrorMsg := CustomMessage('ErrorDownloadIncomplete')
          else
            LoadErrorMsg := CustomMessage('ErrorFileUnavailable');
          LoadErrorTech := QueueFile[I] + ': ' + Failure;
        end;
        Result := False;
        exit;
      end;
      if VerifyStartTick > 0 then
        Log('DownloadAssistant: ' + QueueFile[I] + ' downloaded in ' +
          IntToStr(VerifyStartTick - Started) + ' ms, verified by download page in ' +
          IntToStr(NowMs() - VerifyStartTick) + ' ms')
      else
        Log('DownloadAssistant: ' + QueueFile[I] + ' done in ' +
          IntToStr(NowMs() - Started) + ' ms');
      ProgressDone := ProgressDone + QueueSize[I];
      if not PromoteToCache(ExpandConstant('{tmp}\') + QueueFile[I],
        QueueFile[I], QueueSize[I], QueueSha[I]) then
      begin
        LoadErrorMsg := CustomMessage('ErrorDownloadDamaged');
        LoadErrorTech := 'size check failed for ' + QueueFile[I];
        Result := False;
        exit;
      end;
    end;
  finally
    DownloadPage.Hide;
  end;
end;

{ ============================== הרכבה ============================== }

function MegaBytes(Bytes: Int64): Integer;
begin
  Result := Bytes div 1048576;
end;

{ משרשר את Src (בדיוק Expected בתים) לסוף Dest ומדווח התקדמות בבתים.
  שרשור בתים טהור — התוצאה זהה בית-בית למקור. }
function AppendFileTo(const Dest, Src: String; Expected, DoneBefore,
  Total: Int64; const Caption: String): Boolean;
var
  Output, Input: TFileStream;
  Start, Copied, Slice, Got: Int64;
begin
  Result := False;
  try
    if FileExists(Dest) then
      Output := TFileStream.Create(Dest, fmOpenWrite)
    else
      Output := TFileStream.Create(Dest, fmCreate);
    try
      Start := Output.Seek(Int64(0), soFromEnd);
      Input := TFileStream.Create(Src, fmOpenRead or fmShareDenyWrite);
      try
        Copied := 0;
        while Copied < Expected do
        begin
          Slice := Expected - Copied;
          if Slice > AppendSliceSize then
            Slice := AppendSliceSize;
          Got := Output.CopyFrom(Input, Slice, CopyChunkSize);
          if Got <> Slice then
            Break;
          Copied := Copied + Got;
          WorkPage.SetText(Msg1('JoiningFiles', Caption),
            FmtMessage(CustomMessage('SizeOf'), [HumanSize(DoneBefore + Copied),
              HumanSize(Total)]));
          WorkPage.SetProgress(MegaBytes(DoneBefore + Copied), MegaBytes(Total));
        end;
      finally
        Input.Free;
      end;
      Result := (Copied = Expected) and
        (Output.Seek(Int64(0), soFromCurrent) = Start + Expected);
    finally
      Output.Free;
    end;
    if not Result then
      LoadErrorTech := 'append wrote a wrong byte count: ' + Src;
  except
    LoadErrorTech := 'append failed: ' + GetExceptionMessage;
  end;
end;

{ מקצץ קובץ חלקי חזרה לגבול חלק בין חלקים. Size של TStream הוא 32 סיביות
  ולכן הקיצוץ נעשה דרך Seek של 64 סיביות ו-SetEndOfFile. }
function TruncateFileTo(const Path: String; NewSize: Int64): Boolean;
var
  F: TFileStream;
begin
  Result := False;
  try
    F := TFileStream.Create(Path, fmOpenWrite);
    try
      F.Seek(NewSize, soFromBeginning);
      Result := SetEndOfFile(F.Handle);
    finally
      F.Free;
    end;
  except
    LoadErrorTech := 'truncate failed: ' + GetExceptionMessage;
  end;
end;

{ כל חלק נמחק מיד אחרי שנוסף: שיא הדיסק הוא הקובץ המורכב ועוד חלק אחד. }
function AssembleAsset(AssetIndex: Integer; const Caption: String): Boolean;
var
  TmpPath, FinalPath, PartPath: String;
  Consumed, I, First: Integer;
  Prefix, Actual, Done: Int64;
begin
  Result := False;
  FinalPath := AssetOutputDir(AssetIndex) + '\' + AssetName[AssetIndex];
  TmpPath := AssemblyTmpPath(AssetIndex);
  ForceDirectories(AssetOutputDir(AssetIndex));
  First := AssetPartStart[AssetIndex];
  Consumed := ConsumedPartCount(AssetIndex, Prefix);
  if FileExists(TmpPath) then
  begin
    if not TruncateFileTo(TmpPath, Prefix) then
      exit;
  end
  else if not SaveStringToFile(TmpPath + '.sha256',
    Lowercase(AssetSha[AssetIndex]) + #10, False) then
  begin
    LoadErrorMsg := CustomMessage('ErrorWriteJoined');
    LoadErrorTech := 'cannot write ' + TmpPath + '.sha256';
    exit;
  end;

  Done := Prefix;
  for I := Consumed to AssetPartCount[AssetIndex] - 1 do
  begin
    PartPath := CachePath(PartName[First + I]);
    if not CachedFileIsGood(PartName[First + I], PartSize[First + I],
      PartSha[First + I]) then
    begin
      LoadErrorMsg := CustomMessage('ErrorFileUnavailable');
      LoadErrorTech := 'part failed verification: ' + PartName[First + I];
      exit;
    end;
    if not AppendFileTo(TmpPath, PartPath, PartSize[First + I], Done,
      AssetSize[AssetIndex], Caption) then
    begin
      LoadErrorMsg := CustomMessage('ErrorWriteJoined');
      exit;
    end;
    DeleteFile(PartPath);
    DeleteFile(MarkerPath(PartName[First + I]));
    Done := Done + PartSize[First + I];
  end;

  if not FileSize64(TmpPath, Actual) or (Actual <> AssetSize[AssetIndex]) then
  begin
    LoadErrorMsg := CustomMessage('ErrorJoinedDamaged');
    LoadErrorTech := 'assembled size mismatch: ' + AssetName[AssetIndex];
    DeleteFile(TmpPath);
    DeleteFile(TmpPath + '.sha256');
    exit;
  end;
  WorkPage.SetText(Msg1('CheckingJoined', Caption), CustomMessage('VerifyingJoined'));
  WorkPage.SetProgress(0, 1);
  if HashFile(TmpPath) <> Lowercase(AssetSha[AssetIndex]) then
  begin
    LoadErrorMsg := CustomMessage('ErrorJoinedDamaged');
    LoadErrorTech := 'assembled sha256 mismatch: ' + AssetName[AssetIndex];
    DeleteFile(TmpPath);
    DeleteFile(TmpPath + '.sha256');
    exit;
  end;
  DeleteFile(FinalPath);
  Result := RenameFile(TmpPath, FinalPath);
  if Result then
  begin
    DeleteFile(TmpPath + '.sha256');
    WriteMarker(AssetName[AssetIndex], AssetSha[AssetIndex]);
  end
  else
    LoadErrorTech := 'rename failed: ' + TmpPath;
end;

{ קישור קשיח חוסך העתקה של גיגה-בתים; נכשל בין כוננים ועל FAT32/exFAT, ואז
  מעתיקים. }
function CopyToOutput(const Name, Dir: String): Boolean;
var
  Dest: String;
begin
  Result := True;
  if CompareText(Dir, CacheDir()) = 0 then
    exit;
  ForceDirectories(Dir);
  Dest := Dir + '\' + Name;
  DeleteFile(Dest);
  if CreateHardLink(Dest, CachePath(Name), 0) then
  begin
    Log('DownloadAssistant: linked ' + Name);
    exit;
  end;
  Result := CopyFile(CachePath(Name), Dest, False);
  if Result then
    Log('DownloadAssistant: copied ' + Name)
  else
    LoadErrorTech := 'copy failed: ' + Name;
end;

{ ==================== הרכבה והכנת תיקיית היעד ==================== }

{ מה עושים בקובץ במחשב היעד. נגזר מהסיומת, לא משם רכיב. }
function OpenHint(const Name: String): String;
begin
  if EndsWithText(Name, '.exe') then
    Result := CustomMessage('OpenHintExe')
  else if EndsWithText(Name, '.dmg') then
    Result := CustomMessage('OpenHintDmg')
  else if EndsWithText(Name, '.deb') or EndsWithText(Name, '.rpm') then
    Result := CustomMessage('OpenHintPackage')
  else if EndsWithText(Name, '.apk') then
    Result := CustomMessage('OpenHintApk')
  else
    Result := CustomMessage('OpenHintArchive');
  Result := ' ' + Result;
end;

{ חלקים שנשארו בנפרד ביעד שאינו Windows — המשתמש מחבר אותם בעצמו. }
function JoinCommand(AssetIndex: Integer): String;
var
  P, First: Integer;
  AllNamed: Boolean;
begin
  First := AssetPartStart[AssetIndex];
  AllNamed := True;
  for P := First to First + AssetPartCount[AssetIndex] - 1 do
    if Pos(AssetName[AssetIndex] + '.part-', PartName[P]) <> 1 then
      AllNamed := False;
  if AllNamed then
    Result := 'cat ' + AssetName[AssetIndex] + '.part-* > ' +
      AssetName[AssetIndex]
  else
  begin
    Result := 'cat';
    for P := First to First + AssetPartCount[AssetIndex] - 1 do
      Result := Result + ' ' + PartName[P];
    Result := Result + ' > ' + AssetName[AssetIndex];
  end;
end;

function PrepareOutput(): Boolean;
var
  C, A, P, Total: Integer;
  Notes, PartsNote, SingleName, JoinNote, FirstExe, Folder: String;
  Produced: Integer;
  OutputNotes: TArrayOfString;
begin
  Result := False;
  ForceDirectories(OutputDir());
  Notes := '';
  SingleName := '';
  JoinNote := '';
  FirstExe := '';
  Produced := 0;
  RunAfterExe := '';
  RevealPath := '';
  SetArrayLength(ResultCommands, 0);
  Total := ProducedFileCount();

  WorkPage.Show;
  try
    for C := 0 to GetArrayLength(CompId) - 1 do
    begin
      if not CompSelected[C] then
        Continue;
      Folder := '';
      if CompOutputFolder[C] <> '' then
      begin
        Folder := CompOutputFolder[C] + '\';
        StringChangeEx(Folder, '/', '\', True);
      end;
      for A := CompAssetStart[C] to CompAssetStart[C] + CompAssetCount[C] - 1 do
      begin
        if AssetKind[A] = 'split' then
        begin
          if ShouldAssembleSingleFile(A) then
          begin
            if not AssembledIsReady(A) then
              if not AssembleAsset(A, CompName[C]) then
                exit;
            Notes := Notes + '• ' + DisplayLtr(Folder + AssetName[A]) + #13#10;
            SingleName := Folder + AssetName[A];
            Produced := Produced + 1;
          end
          else
          begin
            { גדול מקובץ אחד, או ארכיון שמתקין Windows צורך כחלקים — החלקים
              נשארים כפי שהם. }
            PartsNote := '';
            for P := AssetPartStart[A] to AssetPartStart[A] + AssetPartCount[A] - 1 do
            begin
              WorkPage.SetText(Msg1('CopyingTo', CompName[C]), PartName[P]);
              WorkPage.SetProgress(Produced, Total);
              if not CopyToOutput(PartName[P], AssetOutputDir(A)) then
              begin
                LoadErrorMsg := CustomMessage('ErrorCopy');
                exit;
              end;
              PartsNote := PartsNote + '• ' +
                DisplayLtr(Folder + PartName[P]) + #13#10;
              SingleName := Folder + PartName[P];
              Produced := Produced + 1;
            end;
            Notes := Notes + PartsNote;
            if TargetPlatform <> 'windows' then
            begin
              JoinNote := JoinNote + JoinCommand(A) + #13#10;
              ListAdd(ResultCommands, JoinCommand(A));
            end;
          end;
        end
        else
        begin
          WorkPage.SetText(Msg1('CopyingTo', CompName[C]), AssetName[A]);
          WorkPage.SetProgress(Produced, Total);
          if not CopyToOutput(AssetName[A], AssetOutputDir(A)) then
          begin
            LoadErrorMsg := CustomMessage('ErrorCopy');
            exit;
          end;
          Notes := Notes + '• ' + DisplayLtr(Folder + AssetName[A]) + #13#10;
          SingleName := Folder + AssetName[A];
          Produced := Produced + 1;
        end;
        if IsExecutableName(AssetName[A]) and (FirstExe = '') and
           ((AssetKind[A] <> 'split') or ShouldAssembleSingleFile(A)) then
          FirstExe := AssetName[A];
        if IsThisComputerMode() and IsExecutableName(AssetName[A]) and
           (RunAfterExe = '') then
          RunAfterExe := AssetOutputDir(A) + '\' + AssetName[A];
      end;
    end;
  finally
    WorkPage.Hide;
  end;

  { הניסוח נגזר ממה שנוצר בפועל, ולא מהרכיב שנבחר. }
  ResultFile := '';
  ResultFolder := OutputDir();
  if Produced = 1 then
  begin
    RevealPath := OutputDir() + '\' + SingleName;
    RevealIsFile := True;
    ResultFile := SingleName;
    ResultText := CustomMessage('ResultFileReady') + #13#10 + SingleName + #13#10#13#10 +
      CustomMessage('ResultFileIn') + #13#10 + OutputDir() + #13#10#13#10;
    if IsThisComputerMode() then
      ResultGuide := CustomMessage('GuideThisFile')
    else
      ResultGuide := Msg1('GuideOtherFile', PlatformDisplayName(TargetPlatform)) +
        OpenHint(SingleName);
  end
  else if IsThisComputerMode() then
  begin
    RevealPath := OutputDir();
    RevealIsFile := False;
    ResultText := CustomMessage('ResultFolderReady') + #13#10 + OutputDir() + #13#10#13#10;
    ResultGuide := CustomMessage('GuideThisFolder') + #13#10#13#10 +
      CustomMessage('PreparedFiles') + #13#10 + Notes;
  end
  else
  begin
    RevealPath := OutputDir();
    RevealIsFile := False;
    ResultText := CustomMessage('ResultFolderReady') + #13#10 + OutputDir() + #13#10#13#10;
    ResultGuide := Msg1('GuideOtherFolder', PlatformDisplayName(TargetPlatform));
    if (TargetPlatform = 'windows') and (FirstExe <> '') then
      ResultGuide := ResultGuide + ' ' + Msg1('GuideRunExe', FirstExe);
    if JoinNote <> '' then
      ResultGuide := ResultGuide + #13#10#13#10 + CustomMessage('GuideJoin') + #13#10 +
        JoinNote;
    ResultGuide := ResultGuide + #13#10#13#10 + CustomMessage('PreparedFiles') + #13#10 +
      Notes;
  end;
  OutputNotes := PlannedOutputNotes(EnglishUi());
  for C := 0 to GetArrayLength(OutputNotes) - 1 do
    ResultGuide := ResultGuide + #13#10 + OutputNotes[C];
  ResultText := ResultText + ResultGuide;
  Result := True;
end;

{ ============================== זרימה ============================== }

{ כישלון נשאר בעמוד שבו קרה, ומוצג בעמוד שגיאה עם "נסה שוב": בטעינה — טעינה
  חוזרת; בהורדה — אותו תג ננעל ואותו מטמון, בדיוק כמו לחיצה חוזרת על "התחל". }
procedure ShowFailure(Stage: Integer);
var
  Title, Body: String;
begin
  if LoadErrorTech <> '' then
    Log('DownloadAssistant: ' + LoadErrorTech);
  Title := LoadErrorMsg;
  if Stage = FailureLoad then
  begin
    Body := CustomMessage('LoadFailedBody');
    if LoadOffline then
    begin
      Title := CustomMessage('OfflineTitle');
      Body := CustomMessage('OfflineBody');
    end;
  end
  else if Stage = RunStopped then
    Body := CustomMessage('StoppedBody')
  else
    Body := CustomMessage('RunFailedBody');
  UiShowFailure(Stage, Title, Body, LoadErrorTech, LoadOffline and (Stage = FailureLoad));
end;

{ הגרסה ידועה רק מהמניפסט: מעמוד הבחירה הראשון ועד ההורדה. }
procedure ShowReleaseVersion();
begin
  if ReleaseVersion = '' then
    exit;
  ModePage.SubCaptionLabel.Caption := Msg1('VersionToDownload', OtzariaVersionLabel());
  DownloadPage.Caption := Msg1('DownloadingVersion', OtzariaVersionLabel());
end;

{ אין נתונים מאומתים בלי מניפסט, ולכן כישלון כאן עוצר במסך הפתיחה ואינו מוריד
  דבר. הטעינה רצה בעמוד שמעבד הודעות, כך שהחלון נשאר חי ואפשר לבטל. }
function LoadManifestStep(): Boolean;
begin
  LoadErrorMsg := '';
  LoadErrorTech := '';
  LoadAttempts := 0;
  LoadNetworkFailures := 0;
  StopRequested := False;
  ConnectPage.Show;
  try
    ManifestLoaded := LoadReleaseManifest();
  finally
    ConnectPage.Hide;
  end;
  if ManifestLoaded then
  begin
    FillOtherPage();
    ShowReleaseVersion();
  end;
  { "ביטול" בזמן החיבור מחזיר למסך הפתיחה, בלי עמוד שגיאה. }
  if StopRequested then
  begin
    UiCloseIfRequested();
    Result := False;
    exit;
  end;
  Result := ManifestLoaded;
  if Result then
    exit;
  LoadOffline := (LoadAttempts > 0) and (LoadNetworkFailures = LoadAttempts);
  ShowFailure(FailureLoad);
end;

{ לפני הצגת החלון אין כאן שום פנייה לרשת: המניפסט נטען ב"בואו נתחיל". }
function InitializeSetup(): Boolean;
begin
  Result := True;
#ifdef DevSelectionDump
  if LoadReleaseManifest() then
    DumpSelections();
  Result := False;
#endif
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = PresetPage.ID then
  begin
    UpdateTarget();
    RefreshPresetPage();
  end
  else if CurPageID = CustomPage.ID then
  begin
    UpdateTarget();
    RefreshCustomPage();
  end
  else if CurPageID = wpFinished then
  begin
    WizardForm.FinishedLabel.Caption := ResultText;
    { במחשב הזה עמוד הסיום פותח את התיקייה בכפתור משלו. }
    if (RevealPath <> '') and not IsThisComputerMode() then
    begin
      if not Assigned(RevealCheck) then
      begin
        RevealCheck := TNewCheckBox.Create(WizardForm);
        RevealCheck.Parent := WizardForm.FinishedPage;
        RevealCheck.Checked := True;
      end;
      if RevealIsFile then
        RevealCheck.Caption := CustomMessage('RevealFile')
      else
        RevealCheck.Caption := CustomMessage('RevealFolder');
    end;
  end;
  UiCurPageChanged(CurPageID);
end;

{ פתיחת הסיירת היא נוחות בלבד: אם היא נכשלת, התוצאה כבר מוכנה ואין מה לומר. }
procedure DeinitializeSetup();
var
  ErrorCode: Integer;
begin
  UiDeinitializeSetup();
  if (RevealPath = '') or not Assigned(RevealCheck) or
     not RevealCheck.Checked then
    exit;
  if not ExecAsOriginalUser(ExpandConstant('{win}\explorer.exe'),
    '/select,"' + RevealPath + '"', '', SW_SHOWNORMAL, ewNoWait, ErrorCode) then
    Log('DownloadAssistant: explorer /select failed: ' + IntToStr(ErrorCode));
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  I: Integer;
  Selected: Boolean;
  Members: String;
  Free, Total, Needed: Int64;
begin
  Result := True;

  if CurPageID = wpWelcome then
  begin
    { התג ננעל בטעינה הראשונה שהצליחה: חזרה למסך הפתיחה אינה טוענת שוב. }
    if not ManifestLoaded then
      Result := LoadManifestStep();
    exit;
  end;

  if CurPageID = OtherPage.ID then
  begin
    if OtherPage.SelectedValueIndex < 0 then
    begin
      UiTell(CustomMessage('NoTargetTitle'), CustomMessage('NoTargetText'));
      Result := False;
    end;
    exit;
  end;

  if CurPageID = PresetPage.ID then
  begin
    if PresetPage.SelectedValueIndex <> CustomPresetIndex then
      ApplyPreset(PresetPage.SelectedValueIndex);
    exit;
  end;

  if CurPageID = CustomPage.ID then
  begin
    { רכיב של יעד קודם אינו מוצג ברשימה, ולכן אסור שיישאר מסומן. }
    for I := 0 to GetArrayLength(CompId) - 1 do
      CompSelected[I] := False;
    Selected := False;
    Members := '';
    for I := 0 to GetArrayLength(CustomIndex) - 1 do
      if CustomPage.Values[I] then
      begin
        Members := Members + CompId[CustomIndex[I]] + ',';
        Selected := True;
      end;
    if not Selected then
    begin
      UiTell(CustomMessage('NothingTitle'), CustomMessage('NothingText'));
      Result := False;
      exit;
    end;
    { ספרייה שנבחרה לבדה מגיעה עם המתקין שקורא אותה, כמו בהצעות. }
    Members := WithDependencies(Members);
    for I := 0 to GetArrayLength(CompId) - 1 do
      CompSelected[I] := MembersContain(Members, CompId[I]);
    exit;
  end;

  if CurPageID = FolderPage.ID then
  begin
    if DirIsWritable(FolderPage.Values[0]) then
      exit;
    if DirIsWritable(FallbackOutputBase()) then
    begin
      UiTell(CustomMessage('FolderBadTitle'),
        Msg1('FolderBadFallback', FallbackOutputBase()));
      FolderPage.Values[0] := FallbackOutputBase();
    end
    else
      UiTell(CustomMessage('FolderBadTitle'), CustomMessage('FolderBadText'));
    Result := False;
    exit;
  end;

  if CurPageID <> wpReady then
    exit;

  UpdateTarget();
  Log('DownloadAssistant: target=' + TargetPlatform + '/' + TargetArchitecture +
    '/' + TargetFormat);
  Needed := 0;
  for I := 0 to GetArrayLength(CompId) - 1 do
    if CompSelected[I] then
      Needed := Needed + CompDownloadSize[I] * 2;
  if GetSpaceOnDisk64(OutputBaseDir(), Free, Total) and (Free < Needed) then
    if not UiAsk(CustomMessage('SpaceTitle'), Msg1('SpaceText', HumanSize(Needed)),
      CustomMessage('SpaceYes'), CustomMessage('Cancel'), False) then
    begin
      Result := False;
      exit;
    end;

  LoadErrorMsg := '';
  LoadErrorTech := '';
  StopRequested := False;
  if not BuildQueue() or not RunDownloads() or not PrepareOutput() then
  begin
    if LoadErrorMsg = '' then
      LoadErrorMsg := CustomMessage('ErrorPrepare');
    if StopRequested then
      ShowFailure(RunStopped)
    else
      ShowFailure(FailureRun);
    Result := False;
  end;
end;

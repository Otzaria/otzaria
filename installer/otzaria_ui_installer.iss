{ שכבת התצוגה של מתקיני אוצריא (otzaria.iss ו-otzaria_full.iss): המתאם בין הליבה
  (otzaria_ui_core.iss) לעמודים של המתקין, שנשארים מודל הנתונים. אין כאן אף כלל התקנה.
  המתקין המלא מגדיר InstallerFull לפני ההכללה. }

[Messages]
; שם התוכנה (AppName) אינו מתורגם: שדרוג בממשק אנגלי חייב למצוא את אותה רשומה ואת אותם קיצורים.
english.SetupAppTitle=Otzaria Setup
english.SetupWindowTitle=Otzaria Setup
english.WelcomeLabel1=Otzaria Setup
english.ButtonNext=&Continue
english.ButtonBack=&Back
english.ButtonInstall=&Install
english.ButtonFinish=&Finish
english.WizardSelectDir=How to install
english.SelectDirDesc=Choose who Otzaria is for and where it goes.
english.WizardSelectTasks=Additional options
english.SelectTasksDesc=Choose what else to add.
english.WizardReady=Ready to install
english.ReadyLabel1=Here's how Otzaria will be installed.
english.ReadyLabel2a=Click "Install" to start, or "Back" to change something.
english.ReadyLabel2b=Click "Install" to start.
english.WizardPreparing=Almost ready
english.PreparingDesc=Preparing the installation...
english.WizardInstalling=Installing Otzaria
english.StatusExtractFiles=Copying files...
english.DiskSpaceGBLabel=Needs at least [gb] GB of free space.
english.DiskSpaceMBLabel=Needs at least [mb] MB of free space.
english.DirExistsTitle=This folder already exists
english.DirExists=This folder already exists:%n%1%n%nInstall into it anyway?
english.ExitSetupTitle=Exit setup
english.ExitSetupMessage=Setup isn't finished. You can run the setup file again at any time.%n%nExit now?
english.FinishedHeadingLabel=Otzaria is installed
english.FinishedLabel=Setup has finished installing Otzaria.
english.FinishedLabelNoIcons=Setup has finished installing Otzaria.
english.UninstallAppFullTitle=Otzaria Uninstall
english.ConfirmUninstall=Are you sure you want to completely remove Otzaria and all of its components?
english.UninstallStatusLabel=Please wait while Otzaria is removed from your computer.
english.UninstalledAll=Otzaria was successfully removed from your computer.
english.UninstalledMost=Otzaria uninstall complete.%n%nSome elements could not be removed. These can be removed manually.
english.UninstalledAndNeedsRestart=To complete the uninstallation of Otzaria, your computer must be restarted.%n%nWould you like to restart now?
english.UninstallAppRunningError=Uninstall has detected that Otzaria is currently running.%n%nPlease close all instances of it now, then click OK to continue, or Cancel to exit.
english.StatusUninstalling=Uninstalling Otzaria...

hebrew.SetupAppTitle=התקנת אוצריא
hebrew.SetupWindowTitle=התקנת אוצריא
hebrew.WelcomeLabel1=התקנת אוצריא
hebrew.ButtonNext=&המשך
hebrew.ButtonBack=&חזרה
hebrew.ButtonInstall=&התקן
hebrew.ButtonFinish=&סיום
hebrew.WizardSelectDir=איך להתקין
hebrew.SelectDirDesc=בחר עבור מי להתקין את אוצריא ולאן.
hebrew.WizardSelectTasks=אפשרויות נוספות
hebrew.SelectTasksDesc=סמן מה עוד להוסיף.
hebrew.WizardReady=מוכנים להתקין
hebrew.ReadyLabel1=כך תותקן אוצריא.
hebrew.ReadyLabel2a=לחץ "התקן" כדי להתחיל, או "חזרה" כדי לשנות משהו.
hebrew.ReadyLabel2b=לחץ "התקן" כדי להתחיל.
hebrew.WizardPreparing=רגע לפני ההתקנה
hebrew.PreparingDesc=מכין את ההתקנה...
hebrew.WizardInstalling=מתקין את אוצריא
; LRM לפני המספר: בלעדיו "313.9 MB" מוצג בסדר הפוך בתוך המשפט העברי.
hebrew.DiskSpaceGBLabel=נדרשים לפחות ‎[gb] GB פנויים בדיסק.
hebrew.DiskSpaceMBLabel=נדרשים לפחות ‎[mb] MB פנויים בדיסק.
hebrew.DirExistsTitle=התיקייה כבר קיימת
hebrew.DirExists=התיקייה הזאת כבר קיימת:%n%1%n%nלהתקין אליה בכל זאת?
hebrew.ExitSetupTitle=יציאה מההתקנה
hebrew.ExitSetupMessage=ההתקנה עוד לא הסתיימה. אפשר להפעיל את קובץ ההתקנה שוב בכל זמן.%n%nלצאת עכשיו?
hebrew.FinishedHeadingLabel=אוצריא הותקנה
hebrew.FinishedLabel=ההתקנה הסתיימה בהצלחה.
hebrew.FinishedLabelNoIcons=ההתקנה הסתיימה בהצלחה.

#ifdef InstallerFull
english.WelcomeLabel2=Version {#MyAppVersion} · with the full library
english.InstallingLabel=Unpacking the library can take a few minutes.
hebrew.WelcomeLabel2=גרסה {#MyAppVersion} · עם הספרייה המלאה
hebrew.InstallingLabel=חילוץ הספרייה עשוי להימשך כמה דקות.
#else
english.WelcomeLabel2=Version {#MyAppVersion}
english.InstallingLabel=This only takes a moment.
hebrew.WelcomeLabel2=גרסה {#MyAppVersion}
hebrew.InstallingLabel=זה ייקח רק כמה רגעים.
#endif

[CustomMessages]
; הטקסטים של המתקינים, כולל ההודעות של הלוגיקה.
english.InstallButton=Install
english.UpdateButton=Update
english.FinishUpdated=Otzaria is updated
english.PrepareAppsOpen=Otzaria is open right now and needs to close to finish the installation.
english.FailRetry=You can run setup again.
english.YesButton=Yes
english.NoButton=No
english.ChangeButton=Change
english.ModeMeTitle=Just for me (recommended)
english.ModeMeShort=Just for me
english.ModeMeDesc=Installed in your profile. No admin rights needed.
english.ModeAllTitle=For everyone on this computer
english.ModeAllDesc=For every account. Needs admin rights.
english.ModePortableTitle=Portable version
english.FolderCaption=Installation folder
english.RelaunchElevated=After you approve administrator rights, setup continues in a new window, where you choose the folder.
english.RelaunchCurrentUser=Setup continues in a new window, where you choose the folder.
english.CalendarIconTask=Create a shortcut directly to the calendar
english.LaunchApp=Open Otzaria
english.TaskDesktopTitle=Desktop shortcut
english.TaskDesktopDesc=Opens Otzaria with a double-click.
english.TaskCalendarTitle=Calendar shortcut
english.TaskCalendarDesc=Opens the Otzaria calendar directly.
english.TaskResetTitle=Reset user settings
english.TaskResetSide=Needed only when upgrading from a version older than 0.9.80, or to fix problems.
english.RowVersion=Version
english.RowUpgradeFrom=Updating from version
english.RowMode=Installation type
english.RowFolder=Installation folder
english.RowShortcuts=Shortcuts
english.ShortcutStart=Start menu
english.ShortcutDesktop=desktop
english.ShortcutCalendar=calendar
english.RowReset=User settings
english.ResetValue=Will be reset
english.PrepareApps=Open programs
english.PrepareCloseTitle=Close them automatically (recommended)
english.PrepareCloseDesc=Setup closes them and continues.
english.PrepareKeepTitle=Don't close them
english.PrepareKeepDesc=You may need to restart the computer afterwards.
english.OpenApp=Open Otzaria
english.FailTitle=Setup didn't finish
english.TechDetails=Technical details
english.HintSharing=A destination file is locked by another process. Close Otzaria and other programs that may use the files, and try again.
english.HintPermission=There's no permission to write to the destination. Try running setup as administrator, or choose another location.
english.HintNoSpace=There isn't enough free space on the drive. Free up some space and install again.
english.BooksSwapFailed=The existing books folder can't be replaced. Make sure Otzaria is closed.
english.FailLibraryKept=A library that was already on this computer wasn't changed.
english.CompactUpdating=Updating Otzaria %1
english.CompactInstalling=Installing Otzaria %1
english.PortableProtectedTitle=This folder can't be used
english.PortableProtected=A portable installation keeps all its data in the program folder, and regular users can't write to the selected folder.%nChoose another folder (for example in Documents or on a removable drive), or go back and choose a regular installation.
english.AdminNeededTitle=Administrator rights are needed
english.AllUsersRelaunchFailed=Installing for all users requires administrator approval.%nYou can choose "Just for me" and continue without it.
english.ModeChangeFailedTitle=Couldn't change the installation type
english.CurrentUserRelaunchFailed=Couldn't switch to installing just for you.
english.ProtectedPreviousInstall=Otzaria was previously installed in a folder that requires administrator rights:%n%1%n%nTo upgrade, run the installer as administrator%n(right-click the setup file ↦ "Run as administrator").
english.UninstallDeleteIntro=Also delete the books and all of Otzaria's data?%n%nThe program is removed either way. Choosing "Yes" also deletes:%n
english.UninstallDeleteBooksAt=• The books folder:%n   %1%n
english.UninstallDeleteBooksDefault=• The books folder inside the data folder%n
english.UninstallDeleteRest=• Databases, search index, settings,%n   bookmarks, history and personal notes%n%nChoose "No" to keep the data for a future installation.
english.UninstallConfirmDelete=Note: the data can't be recovered after it is deleted.%n%nAre you sure you want to delete all the books and data?

hebrew.InstallButton=התקנה
hebrew.UpdateButton=עדכון
hebrew.FinishUpdated=אוצריא עודכנה
hebrew.PrepareAppsOpen=אוצריא פתוחה כרגע, וצריך לסגור אותה כדי להשלים את ההתקנה.
hebrew.FailRetry=אפשר להריץ את ההתקנה שוב.
hebrew.YesButton=כן
hebrew.NoButton=לא
hebrew.ChangeButton=שינוי
hebrew.ModeMeTitle=רק בשבילי (מומלץ)
hebrew.ModeMeShort=רק בשבילי
hebrew.ModeMeDesc=מותקנת בפרופיל שלך, בלי הרשאות מנהל.
hebrew.ModeAllTitle=לכל המשתמשים במחשב
hebrew.ModeAllDesc=זמינה לכל חשבונות המשתמש. דורשת הרשאות מנהל.
hebrew.ModePortableTitle=גרסה ניידת
hebrew.FolderCaption=תיקיית ההתקנה
hebrew.RelaunchElevated=אחרי אישור הרשאות המנהל, ההתקנה תמשיך בחלון חדש ושם תבחר את התיקייה.
hebrew.RelaunchCurrentUser=ההתקנה תמשיך בחלון חדש, ושם תבחר את התיקייה.
hebrew.CalendarIconTask=צור קיצור דרך ישירות ללוח שנה
hebrew.LaunchApp=הפעל את אוצריא
hebrew.TaskDesktopTitle=קיצור דרך בשולחן העבודה
hebrew.TaskDesktopDesc=פותח את אוצריא בלחיצה כפולה.
hebrew.TaskCalendarTitle=קיצור דרך ללוח השנה
hebrew.TaskCalendarDesc=פותח ישירות את לוח השנה של אוצריא.
hebrew.TaskResetTitle=איפוס הגדרות משתמש
hebrew.TaskResetSide=נדרש רק בשדרוג מגרסה שקודמת ל-0.9.80, או לפתרון תקלות.
hebrew.RowVersion=גרסה
hebrew.RowUpgradeFrom=מעדכן מגרסה
hebrew.RowMode=סוג ההתקנה
hebrew.RowFolder=תיקיית ההתקנה
hebrew.RowShortcuts=קיצורי דרך
hebrew.ShortcutStart=תפריט התחל
hebrew.ShortcutDesktop=שולחן העבודה
hebrew.ShortcutCalendar=לוח השנה
hebrew.RowReset=הגדרות משתמש
hebrew.ResetValue=יאופסו
hebrew.PrepareApps=תוכנות פתוחות
hebrew.PrepareCloseTitle=סגור אותן אוטומטית (מומלץ)
hebrew.PrepareCloseDesc=ההתקנה תסגור אותן ותמשיך.
hebrew.PrepareKeepTitle=אל תסגור
hebrew.PrepareKeepDesc=ייתכן שיהיה צורך להפעיל מחדש את המחשב בסיום.
hebrew.OpenApp=פתח את אוצריא
hebrew.FailTitle=ההתקנה לא הושלמה
hebrew.TechDetails=פרטים טכניים
hebrew.HintSharing=קובץ היעד נעול על ידי תהליך אחר. סגור את אוצריא ותוכנות אחרות שעשויות להשתמש בקבצים ונסה שוב.
hebrew.HintPermission=אין הרשאה לכתוב לנתיב היעד. נסה להריץ את ההתקנה כמנהל או לבחור מיקום התקנה אחר.
hebrew.HintNoSpace=אין מספיק מקום פנוי בכונן. פנה מקום ונסה להתקין שוב.
hebrew.BooksSwapFailed=לא ניתן להחליף את תיקיית הספרים הקיימת. ודא שאוצריא סגורה.
hebrew.FailLibraryKept=ספרייה שכבר הייתה במחשב לא שונתה.
hebrew.CompactUpdating=מעדכן את אוצריא %1
hebrew.CompactInstalling=מתקין את אוצריא %1
hebrew.PortableProtectedTitle=אי אפשר להתקין בתיקייה הזאת
hebrew.PortableProtected=התקנה ניידת שומרת את כל הנתונים בתיקיית התוכנה, ולתיקייה שנבחרה אין הרשאת כתיבה למשתמש רגיל.%nבחר תיקייה אחרת — למשל בתיקיית המסמכים או בכונן נייד — או חזור ובחר התקנה רגילה.
hebrew.AdminNeededTitle=נדרשות הרשאות מנהל
hebrew.AllUsersRelaunchFailed=להתקנה לכל המשתמשים נדרש אישור הרשאות מנהל.%nניתן לבחור "רק בשבילי" ולהמשיך ללא הרשאות.
hebrew.ModeChangeFailedTitle=לא ניתן היה להחליף את סוג ההתקנה
hebrew.CurrentUserRelaunchFailed=לא ניתן היה לעבור להתקנה למשתמש הנוכחי.
hebrew.ProtectedPreviousInstall=אוצריא הותקנה בעבר בנתיב הדורש הרשאות מנהל:%n%1%n%nכדי לשדרג, יש להפעיל את המתקין כמנהל%n(קליק ימני על קובץ ההתקנה ↦ "Run as administrator").
hebrew.UninstallDeleteIntro=האם למחוק גם את הספרים וכל הנתונים של אוצריא?%n%nבכל מקרה תוסר התוכנה. בחירה ב"כן" תמחק בנוסף:%n
hebrew.UninstallDeleteBooksAt=• תיקיית הספרים:%n   %1%n
hebrew.UninstallDeleteBooksDefault=• תיקיית הספרים שתחת תיקיית הנתונים%n
hebrew.UninstallDeleteRest=• מסדי הנתונים, אינדקס החיפוש, הגדרות,%n   סימניות, היסטוריה והערות אישיות%n%nבחר "לא" כדי לשמור את הנתונים לקראת התקנה עתידית.
hebrew.UninstallConfirmDelete=שים לב: לא ניתן יהיה לשחזר את הנתונים לאחר המחיקה.%n%nהאם אתה בטוח שברצונך למחוק את כל הספרים והנתונים?

#ifdef InstallerFull
english.ModePortableDesc=No installation: the program, the library and all the data in one folder.
english.TaskResetDesc=Warning: deletes personal notes, bookmarks, history and plugin data. The backups folder is kept and the library is installed again.
english.WebView2Title=Microsoft WebView2 Runtime
english.WebView2Desc=Needed only for plugins; everything else works without it.
english.WebView2Installed=Already installed (version %1).
english.RowBooks=Books folder
english.RowComponents=System components
english.BooksTitle=Where to keep the books
english.BooksDesc=The library's books, and any you add later, are kept here.
english.BooksHint=Otzaria's settings will point to this folder automatically.
english.BooksBrowse=Choose a books folder:
english.BooksExists=Note: a folder already exists at this path.%nThis installation deletes its contents and replaces them with the books in the package.
english.BooksRequiredTitle=No books folder
english.BooksRequired=Choose a folder for the books.
english.InstallingWebView2=Installing Microsoft WebView2 Runtime...
english.LegacyFoundTitle=An old installation was found
english.LegacyFound=An old installation was found in %1%nThe books library is moving to a new path: %2%n%nMove the data to the new location?
english.LegacyMoveLater=After the installation, you can move the data from %1 to %2
english.PortableLibraryTitle=A library is already on this computer
english.PortableLibraryFound=A library was found on this computer:%n%1%n%nExtract another copy of the library into the portable folder?%nAnother copy takes several gigabytes of disk space.%n%nChoosing "No" skips the extraction; when you open the portable Otzaria you can point it to the existing library with "Use an existing library instead".
english.StatusSeforim=Extracting the seforim.db database...
english.StatusCatalog=Extracting the Otzar HaChochma catalog...
english.StatusTalmud=Extracting the Babylonian Talmud books...
english.StatusLexical=Extracting the dictionary for approximate search...
english.StatusSwap=Replacing the previous library...
english.DbArchiveMissing=The library file %1 is missing from the temporary setup files.%nA disk cleanup tool may have deleted it, or there isn't enough free space. Free up some space and install again.
english.ArchiveMissing=The archive %1 is missing from the temporary setup files.%nA disk cleanup tool may have deleted it, or there isn't enough free space. Free up some space and install again.
english.DbExtractFailed=Extracting the library database failed.
english.PdfExtractFailed=Extracting the Babylonian Talmud books failed.
english.PdfOpenFailed=Opening the Babylonian Talmud books archive failed.
english.ExitCode=Exit code: %1
english.SeforimMissing=Extracting the library didn't finish — the seforim.db database is missing.
english.BooksMoveFailed=Moving the library to the chosen location failed.
english.ZstdMissing=The extraction tool zstd.exe wasn't found. Setup can't extract the bundled library files.
english.SevenZipMissing=The extraction tool 7za.exe wasn't found. Setup can't extract the bundled PDF files.
hebrew.ModePortableDesc=בלי התקנה: התוכנה, הספרייה וכל הנתונים בתיקייה אחת, למשל בדיסק-און-קי.
hebrew.TaskResetDesc=אזהרה: ימחק הערות אישיות, סימניות, היסטוריה ונתוני תוספים. תיקיית הגיבויים נשמרת והספרייה מותקנת מחדש.
hebrew.WebView2Title=Microsoft WebView2 Runtime
hebrew.WebView2Desc=נדרש לתוספים בלבד. בלעדיו שאר התוכנה עובדת כרגיל.
hebrew.WebView2Installed=כבר מותקן במחשב (גרסה %1).
hebrew.RowBooks=תיקיית הספרים
hebrew.RowComponents=רכיבי מערכת
hebrew.BooksTitle=היכן לשמור את הספרים
hebrew.BooksDesc=כאן יישמרו ספרי הספרייה וכל ספר שתוסיף בעתיד.
hebrew.BooksHint=הנתיב יוגדר אוטומטית בהגדרות התוכנה.
hebrew.BooksBrowse=בחר תיקיית ספרים:
hebrew.BooksExists=שים לב: בנתיב הזה כבר יש תיקייה.%nההתקנה תמחק את התוכן שלה ותחליף אותו בספרים שבחבילה.
hebrew.BooksRequiredTitle=חסרה תיקיית ספרים
hebrew.BooksRequired=יש לבחור נתיב לתיקיית הספרים.
hebrew.InstallingWebView2=מתקין Microsoft WebView2 Runtime...
hebrew.LegacyFoundTitle=נמצאה התקנה ישנה
hebrew.LegacyFound=נמצאה התקנה ישנה ב-%1%nספריית הספרים עוברת לנתיב חדש: %2%n%nהאם להעביר את הנתונים למיקום החדש?
hebrew.LegacyMoveLater=לאחר ההתקנה, תוכל להעביר את הנתונים מ-%1 ל-%2
hebrew.PortableLibraryTitle=נמצאה ספרייה קיימת
hebrew.PortableLibraryFound=נמצאה ספרייה קיימת במחשב זה:%n%1%n%nהאם לחלץ עותק ספרייה נוסף לתיקייה הניידת?%nעותק נוסף תופס כמה גיגה-בייטים בדיסק.%n%nבחירה ב"לא" תדלג על החילוץ, ובפתיחת אוצריא הניידת ניתן יהיה להצביע על הספרייה הקיימת דרך "שימוש בספרייה קיימת במקומה".
hebrew.StatusSeforim=מחלץ מסד הנתונים seforim.db...
hebrew.StatusCatalog=מחלץ קטלוג אוצר החכמה...
hebrew.StatusTalmud=מחלץ ספרי תלמוד בבלי...
hebrew.StatusLexical=מחלץ מילון לחיפוש המקורב...
hebrew.StatusSwap=מחליף את הספרייה הקודמת...
hebrew.DbArchiveMissing=קובץ הספרייה %1 חסר בקבצי ההתקנה הזמניים.%nייתכן שתוכנת ניקוי דיסק מחקה אותו או שאין מספיק מקום פנוי. פנה מקום ונסה להתקין שוב.
hebrew.ArchiveMissing=ארכיון %1 חסר בקבצי ההתקנה הזמניים.%nייתכן שתוכנת ניקוי דיסק מחקה אותו או שאין מספיק מקום פנוי. פנה מקום ונסה להתקין שוב.
hebrew.DbExtractFailed=חילוץ מסד הנתונים של הספרייה נכשל.
hebrew.PdfExtractFailed=חילוץ ספרי התלמוד הבבלי נכשל.
hebrew.PdfOpenFailed=פתיחת ארכיון ספרי התלמוד הבבלי נכשלה.
hebrew.ExitCode=קוד יציאה: %1
hebrew.SeforimMissing=חילוץ הספרייה לא הושלם — מסד הנתונים seforim.db חסר.
hebrew.BooksMoveFailed=העברת הספרייה למיקום שנבחר נכשלה.
hebrew.ZstdMissing=קובץ החילוץ zstd.exe לא נמצא. ההתקנה לא יכולה לחלץ את קבצי הספרייה המצורפים.
hebrew.SevenZipMissing=קובץ החילוץ 7za.exe לא נמצא. ההתקנה לא יכולה לחלץ את קבצי ה-PDF המצורפים.
#else
english.ModePortableDesc=No installation: everything in one folder, e.g. on a USB drive.
english.TaskResetDesc=Warning: deletes personal notes, bookmarks, history and plugin data. The books and backups folders are kept.
hebrew.ModePortableDesc=בלי התקנה: התוכנה וכל הנתונים בתיקייה אחת, למשל בדיסק-און-קי.
hebrew.TaskResetDesc=אזהרה: ימחק הערות אישיות, סימניות, היסטוריה ונתוני תוספים. תיקיות הספרים והגיבויים נשמרות.
; הספרייה והאינדקס שמסייע ההורדה מכין לצד המתקין (חלקים, ‎#1890‎).
english.LibraryWhat=the library
english.IndexWhat=the search index
english.LibraryPartsTitle=The library can't be installed
english.LibraryManifestInvalid=The parts list of %1 inside the setup is invalid.
english.LibraryPartsMissing=Some parts of %1 are missing from the setup's folder.%n%nPrepare the folder again in the Download Assistant, or move the setup file to another folder to install only the program.
english.LibraryPartsCorrupt=Checking the parts of %1 failed: one of the files is damaged, or there isn't enough free disk space.%n%nPrepare the folder again in the Download Assistant, or move the setup file to another folder to install only the program.
english.LibraryPartsArmWin10=Installing the library from the parts next to the setup requires Windows 11 on an ARM computer.%n%nMove the setup file to another folder to install only the program.
english.UnsafeLibraryRoot=A single, safe library folder can't be determined. A library can't be installed at the root of a drive or share, or in a relative path. First update only the program from a folder without library files, choose the active library in it, and then run the setup again.
english.OtherVersionPartsTitle=Library files of another version
english.OtherVersionParts=Next to the setup there are library files of another version of Otzaria, so they won't be installed:%n%1%n%nTo install the library too, prepare the folder again in the Download Assistant.%n%nContinue and install only the program?
english.LibraryPrepTitle=Preparing the library
english.LibraryPrepDesc=Checking the library parts next to the setup. This can take a few minutes.
english.LibraryPrepCaption=Joining and checking %1...
english.LibraryPrepBytes=%1 of %2
english.StatusLibrary=Installing the full library...
english.LibraryInstallingDesc=Unpacking the library can take a few minutes.
english.StatusLibraryIndex=Installing the full library and the ready search index...
english.LibraryNotInstalled=The program was installed, but the library wasn't.
english.LibraryExtractFailed=Extracting the library failed.
english.IndexExtractFailed=Extracting the search index failed.
english.LibraryPackageInvalid=The library package structure is invalid.
english.IndexSwapFailed=The existing index folder can't be replaced. Make sure Otzaria is closed.
english.LibraryMoveFailed=Moving the library to its location failed.
hebrew.LibraryWhat=הספרייה
hebrew.IndexWhat=אינדקס החיפוש
hebrew.LibraryPartsTitle=לא ניתן להתקין את הספרייה
hebrew.LibraryManifestInvalid=קובץ רשימת החלקים של %1 שבתוך המתקין אינו תקין.
hebrew.LibraryPartsMissing=בתיקייה של המתקין חסרים חלקים של %1.%n%nהכינו את התיקייה מחדש במסייע ההורדה, או העבירו את המתקין לתיקייה אחרת כדי להתקין את התוכנה בלבד.
hebrew.LibraryPartsCorrupt=אימות החלקים של %1 נכשל: אחד הקבצים פגום, או שאין מספיק מקום פנוי בדיסק.%n%nהכינו את התיקייה מחדש במסייע ההורדה, או העבירו את המתקין לתיקייה אחרת כדי להתקין את התוכנה בלבד.
hebrew.LibraryPartsArmWin10=פריסת הספרייה מהחלקים שליד המתקין דורשת Windows 11 במחשב ARM.%n%nהעבירו את המתקין לתיקייה אחרת כדי להתקין את התוכנה בלבד.
hebrew.UnsafeLibraryRoot=לא ניתן לקבוע תיקיית ספרייה בטוחה ויחידה. אין להתקין ספרייה בשורש כונן או שיתוף, או בנתיב יחסי. עדכנו תחילה את התוכנה בלבד מתיקייה ללא קובצי ספרייה, בחרו בה את הספרייה הפעילה, ואז הפעילו שוב את המתקין.
hebrew.OtherVersionPartsTitle=קובצי ספרייה של גרסה אחרת
hebrew.OtherVersionParts=לצד המתקין יש קובצי ספרייה של גרסה אחרת של אוצריא, ולכן הם לא יותקנו:%n%1%n%nכדי להתקין גם את הספרייה, הכינו את התיקייה מחדש במסייע ההורדה.%n%nלהמשיך ולהתקין את התוכנה בלבד?
hebrew.LibraryPrepTitle=מכין את הספרייה
hebrew.LibraryPrepDesc=בודק את חלקי הספרייה שליד המתקין. הבדיקה עשויה להימשך כמה דקות.
hebrew.LibraryPrepCaption=מחבר ומאמת את חלקי %1...
hebrew.LibraryPrepBytes=%1 מתוך %2
hebrew.StatusLibrary=מתקין את הספרייה המלאה...
hebrew.LibraryInstallingDesc=חילוץ הספרייה עשוי להימשך כמה דקות.
hebrew.StatusLibraryIndex=מתקין את הספרייה המלאה ואת אינדקס החיפוש המוכן...
hebrew.LibraryNotInstalled=התוכנה הותקנה, אבל הספרייה לא.
hebrew.LibraryExtractFailed=חילוץ הספרייה נכשל.
hebrew.IndexExtractFailed=חילוץ אינדקס החיפוש נכשל.
hebrew.LibraryPackageInvalid=מבנה חבילת הספרייה אינו תקין.
hebrew.IndexSwapFailed=לא ניתן להחליף את תיקיית האינדקס הקיימת. ודא שאוצריא סגורה.
hebrew.LibraryMoveFailed=העברת הספרייה למיקום שלה נכשלה.
#endif


[Code]
const
  UiBtnOpenApp = UiBtnFirstAdapter;
  UiBtnDone = UiBtnFirstAdapter + 1;

  UiSrcFiles = UiSrcFirstAdapter;
  UiSrcLibraryPrep = UiSrcFirstAdapter + 1;

  { מה כל כרטיס מייצג במודל הנתונים (UiCardKind). }
  UiCardModeMe = 1;
  UiCardModeAll = 2;
  UiCardModePortable = 3;
  UiCardDesktop = 4;
  UiCardCalendar = 5;
  UiCardReset = 6;
  UiCardWebView2 = 7;
  UiCardCloseApps = 8;
  UiCardKeepApps = 9;
  UiCardRestartNow = 10;
  UiCardRestartLater = 11;

var
  UiCardKind: array of Integer;
  UiFolderCaption, UiDiskLabel, UiModeNote, UiBooksWarn: TNewStaticText;
  UiFinBadge: TBitmapImage;
  UiFinTitle: TNewStaticText;
  { כישלון אחרי העתקת הקבצים: Inno ממשיך לעמוד הסיום, וכאן הוא מוצג כמצב כישלון. }
  InstFailed: Boolean;
  InstFailText, InstFailTech: String;
  { הייתה התקנה קודמת כשהאשף נפתח; אחרי ההתקנה הרישום כבר מראה את הגרסה החדשה. }
  InstIsUpdate: Boolean;
  UiFailBody, UiFailLink: TNewStaticText;
  UiFailTech: TRichEditViewer;

{ מוגדרות בהמשך הסקריפט הראשי. }
function ShouldSkipPage(PageID: Integer): Boolean; forward;
function GetPreviousDisplayVersion(): String; forward;
function ModeChangeNeedsRelaunch(): Boolean; forward;
procedure ApplyInstallModeChoice(); forward;
#ifdef InstallerFull
function GetWebView2Version: String; forward;
function GetSelectedBooksPath(Param: String): String; forward;
#endif

{ ============================ הודעות ============================ }

{ באשף — דו-שיח מעוצב. בהתקנה שקטה — ה-MsgBox שהיה, באותם דגלים: /SILENT ו-/VERYSILENT
  אינם מציגים שום חלון חדש. }
procedure InstTell(const Title, Text: String; Typ: TMsgBoxType);
begin
  if WizardSilent then
    MsgBox(Text, Typ, MB_OK)
  else
    UiTell(Title, Text);
end;

{ נתיב בדו-שיח מעוצב: שורה אחת משמאל לימין, מקוצרת באמצע לרוחב הדו-שיח. בשקט —
  הנתיב כפי שהוא, כמו ב-MsgBox שהיה. }
function UiDialogPath(const Path: String): String;
begin
  Result := Path;
  if WizardSilent then
    exit;
  UiPrepare();
  UiSetFont(UiMeasure.Canvas, 14, False, 0);
  Result := LtrUnit(MinimizePathName(Path, UiMeasure.Canvas.Font, Px(336 - 48)));
end;

{ שאלת כן/לא; True ל"כן". כמו ב-MsgBox של כן/לא, Esc וסגירה אינם בוחרים ב"לא". }
function InstAskYesNo(const Title, Text: String; Typ: TMsgBoxType; Flags: Integer): Boolean;
begin
  if WizardSilent then
    Result := MsgBox(Text, Typ, Flags) = IDYES
  else
    Result := UiAskDialog(Title, Text, CustomMessage('YesButton'), CustomMessage('NoButton'),
      False, True);
end;

procedure InstTellSuppressible(const Title, Text: String);
begin
  if WizardSilent then
    SuppressibleMsgBox(Text, mbCriticalError, MB_OK, IDOK)
  else
    UiTell(Title, Text);
end;

{ כמו InstAskYesNo; בשקט SuppressibleMsgBox, ש-/SUPPRESSMSGBOXES עונה בו Default. }
function InstAskYesNoSuppressible(const Title, Text: String; Default: Integer): Boolean;
begin
  if WizardSilent then
    Result := SuppressibleMsgBox(Text, mbConfirmation, MB_YESNO, Default) = IDYES
  else
    Result := UiAskDialog(Title, Text, CustomMessage('YesButton'), CustomMessage('NoButton'),
      False, True);
end;

procedure UiFailLinkClick(Sender: TObject);
begin
  if Assigned(UiFailTech) then
    UiFailTech.Visible := not UiFailTech.Visible;
end;

{ כישלון אחרי העתקת הקבצים, לפני Abort. בשקט — ה-MsgBox שהיה; באשף — מצב כישלון בעמוד
  הסיום, והפלט הגולמי של הכלי (Output) מוסתר מאחורי "פרטים טכניים". }
procedure InstReportFailure(const Text, Output: String; WithOutput: Boolean);
var
  Full: String;
begin
  Full := Text;
  if WithOutput then
    Full := Text + #13#10#13#10 + Output;
  if WizardSilent or not UiReady or UiFailed then
    MsgBox(Full, mbCriticalError, MB_OK)
  else
  begin
    InstFailed := True;
    InstFailText := Text;
    InstFailTech := Output;
  end;
end;

#ifdef LibraryParts
{ הספרייה שליד המתקין הרגיל לא נפרסה (התוכנה כן): בשקט ה-SuppressibleMsgBox שהיה, באשף —
  מצב הכישלון בעמוד הסיום. }
procedure InstReportLibraryFailure(const Text, Output: String);
begin
  if WizardSilent or not UiReady or UiFailed then
    SuppressibleMsgBox(Text + #13#10#13#10 + Output, mbCriticalError, MB_OK, IDOK)
  else
  begin
    InstFailed := True;
    InstFailText := Text;
    InstFailTech := Output;
  end;
end;
#endif

{ ============================ כרטיסים ============================ }

function UiAdapterCardSelected(I: Integer): Boolean;
begin
  Result := False;
  case UiCardKind[I] of
    UiCardModeMe: Result := CurrentUserModeRadio.Checked;
    UiCardModeAll: Result := AllUsersModeRadio.Checked;
    UiCardModePortable: Result := PortableModeRadio.Checked;
    UiCardDesktop: Result := WizardIsTaskSelected('desktopicon');
    UiCardCalendar: Result := WizardIsTaskSelected('calendaricon');
    UiCardReset: Result := WizardIsTaskSelected('resetsettings');
#ifdef InstallerFull
    UiCardWebView2: Result := WV2Check.Checked;
#endif
    UiCardCloseApps: Result := WizardForm.PreparingYesRadio.Checked;
    UiCardKeepApps: Result := WizardForm.PreparingNoRadio.Checked;
    UiCardRestartNow: Result := WizardForm.YesRadio.Checked;
    UiCardRestartLater: Result := WizardForm.NoRadio.Checked;
  end;
end;

procedure UiToggleTask(const Name: String);
begin
  if WizardIsTaskSelected(Name) then
    WizardSelectTasks('!' + Name)
  else
    WizardSelectTasks(Name);
end;

{ בבחירה שמחייבת שיגור-מחדש התיקייה נבחרת בחלון החדש, ולכן השדה מתחלף בהסבר. }
procedure UiSyncModePage();
var
  Relaunch: Boolean;
begin
  if not Assigned(UiModeNote) then
    exit;
  Relaunch := ModeChangeNeedsRelaunch();
  if AllUsersModeRadio.Checked then
    UiModeNote.Caption := CustomMessage('RelaunchElevated')
  else
    UiModeNote.Caption := CustomMessage('RelaunchCurrentUser');
  UiModeNote.Visible := Relaunch;
  UiFolderCaption.Visible := not Relaunch;
  UiDiskLabel.Visible := not Relaunch;
  if Assigned(UiFolderField) then
    UiFolderField.Visible := not Relaunch;
  { השדה האמיתי מוצג או מוסתר יחד עם המצויר. }
  UiScrollTo(UiScrollY);
  UiSetButton(UiBtnBrowse, not Relaunch, True, UiStrip(WizardForm.DirBrowseButton.Caption));
end;

{ רדיו שמקבל מוקד מהמקלדת מסמן את עצמו: אותה בחירה כמו לחיצה על הכרטיס. }
procedure UiModeRadioClick(Sender: TObject);
begin
  if not UiReady or UiFailed or (UiPage <> wpSelectDir) then
    exit;
  ApplyInstallModeChoice();
  UiSyncModePage();
end;

procedure UiAdapterCardClick(I: Integer);
begin
  case UiCardKind[I] of
    UiCardModeMe, UiCardModeAll, UiCardModePortable:
      begin
        CurrentUserModeRadio.Checked := UiCardKind[I] = UiCardModeMe;
        AllUsersModeRadio.Checked := UiCardKind[I] = UiCardModeAll;
        PortableModeRadio.Checked := UiCardKind[I] = UiCardModePortable;
        ApplyInstallModeChoice();
        UiSyncModePage();
      end;
    UiCardDesktop: UiToggleTask('desktopicon');
    UiCardCalendar: UiToggleTask('calendaricon');
    UiCardReset: UiToggleTask('resetsettings');
#ifdef InstallerFull
    UiCardWebView2:
      if WV2Check.Enabled then
        WV2Check.Checked := not WV2Check.Checked;
#endif
    UiCardCloseApps: WizardForm.PreparingYesRadio.Checked := True;
    UiCardKeepApps: WizardForm.PreparingNoRadio.Checked := True;
    UiCardRestartNow: WizardForm.YesRadio.Checked := True;
    UiCardRestartLater: WizardForm.NoRadio.Checked := True;
  end;
end;

{ כרטיס אחד; Check — סימון, אחרת רדיו. מחזיר את ראש הכרטיס הבא. }
function UiInstCard(Kind: Integer; const Icon, Title, Desc, Side: String; Check: Boolean;
  Y: Integer): Integer;
var
  Card: TUiCard;
  N: Integer;
begin
  N := GetArrayLength(UiCardKind);
  SetArrayLength(UiCardKind, N + 1);
  UiCardKind[N] := Kind;
  Card.Icon := Icon;
  Card.Title := Title;
  Card.Desc := Desc;
  Card.Side := Side;
  Card.Check := Check;
  Card.Danger := Kind = UiCardReset;
  Result := UiAddCard(Card, Y);
end;

{ סוף רשימת כרטיסים שאחריה בא תוכן נוסף: בלי הרווח שאחרי האחרון. }
function UiCardsBottom(Y: Integer): Integer;
begin
  Result := Y - Px(UiCardGap - UiCardShadow);
end;

function UiSmallCaption(const Caption: String; Y: Integer): TNewStaticText;
begin
  Result := UiLabel(UiContent, 13, False, UiSecondaryColor, taLeftJustify);
  UiPlaceLabel(Result, Caption, 0, Y, Px(UiContentW));
end;

{ ============================ עמודים ============================ }

{ "איך להתקין": שלושת סוגי ההתקנה, ומתחתם תיקיית ההתקנה עם שורת המקום הפנוי של Inno. }
procedure UiBuildModePage();
var
  Y, FieldTop, BtnW: Integer;
begin
  Y := UiInstCard(UiCardModeMe, 'only_me', CustomMessage('ModeMeTitle'),
    CustomMessage('ModeMeDesc'), '', False, 0);
  Y := UiInstCard(UiCardModeAll, 'all_users', CustomMessage('ModeAllTitle'),
    CustomMessage('ModeAllDesc'), '', False, Y);
  Y := UiInstCard(UiCardModePortable, 'portable', CustomMessage('ModePortableTitle'),
    CustomMessage('ModePortableDesc'), '', False, Y);
  Y := UiCardsBottom(Y) + Px(14);
  UiFolderCaption := UiSmallCaption(CustomMessage('FolderCaption'), Y);
  FieldTop := UiFolderCaption.Top + UiFolderCaption.Height + Px(4);
  UiModeNote := UiLabel(UiContent, 13, False, UiSecondaryColor, taCenter);
  UiPlaceLabel(UiModeNote, CustomMessage('RelaunchElevated'), 0, Y, Px(UiContentW));
  UiModeNote.Visible := False;
  Y := UiBuildFolderField(WizardForm.DirEdit, WizardForm.DirBrowseButton, FieldTop);
  BtnW := UiButtons[UiBtnBrowse].Img.Width;
  { בצד שמול הכפתור, צמוד אליו. }
  if UiRtl then
    UiDiskLabel := UiLabel(UiContent, 12, False, UiFaintColor, taRightJustify)
  else
    UiDiskLabel := UiLabel(UiContent, 12, False, UiFaintColor, taLeftJustify);
  UiPlaceLabel(UiDiskLabel, WizardForm.DiskSpaceLabel.Caption,
    UiX(0, Px(UiContentW) - BtnW - Px(12), Px(UiContentW)), 0,
    Px(UiContentW) - BtnW - Px(12));
  UiDiskLabel.Top := UiButtons[UiBtnBrowse].Img.Top +
    (UiButtons[UiBtnBrowse].Img.Height - UiDiskLabel.Height) div 2;
  UiSetContentHeight(Y);
  UiSyncModePage();
end;

function UiTaskIndex(const Name: String): Integer;
begin
  if Name = 'desktopicon' then
    Result := WizardForm.TasksList.Items.IndexOf(CustomMessage('CreateDesktopIcon'))
  else if Name = 'calendaricon' then
    Result := WizardForm.TasksList.Items.IndexOf(CustomMessage('CalendarIconTask'))
  else
    Result := WizardForm.TasksList.Items.IndexOf(CustomMessage('ResetSettingsTask'));
end;

procedure UiBuildTasksPage();
var
  Y: Integer;
#ifdef InstallerFull
  Version, Side: String;
#endif
begin
  Y := 0;
  if not PortableMode then
  begin
    Y := UiInstCard(UiCardDesktop, 'desktop_shortcut', CustomMessage('TaskDesktopTitle'),
      CustomMessage('TaskDesktopDesc'), '', True, Y);
    Y := UiInstCard(UiCardCalendar, 'calendar_shortcut', CustomMessage('TaskCalendarTitle'),
      CustomMessage('TaskCalendarDesc'), '', True, Y);
  end;
#ifdef InstallerFull
  Side := '';
  Version := GetWebView2Version;
  if Version <> '' then
    Side := Msg1('WebView2Installed', LtrUnit(Version));
  Y := UiInstCard(UiCardWebView2, 'webview2', CustomMessage('WebView2Title'),
    CustomMessage('WebView2Desc'), Side, True, Y);
#endif
  if not PortableMode then
    Y := UiInstCard(UiCardReset, 'reset_settings', CustomMessage('TaskResetTitle'),
      CustomMessage('TaskResetDesc'), CustomMessage('TaskResetSide'), True, Y);
  UiEndCards(Y);
  { בנייד אין כרטיסי משימות: Space לא יסמן משימה שאינה על המסך. }
  WizardForm.TasksList.TabStop := not PortableMode;
  if not PortableMode and (WizardForm.TasksList.ItemIndex < 0) then
    WizardForm.TasksList.ItemIndex := UiTaskIndex('desktopicon');
end;

#ifdef InstallerFull
procedure UiInstBooksWarningChanged();
begin
  if Assigned(UiBooksWarn) then
    UiBooksWarn.Caption := BooksWarnLabel.Caption;
end;

procedure UiBuildBooksPage();
var
  Y: Integer;
begin
  UiFolderCaption := UiSmallCaption(CustomMessage('RowBooks'), 0);
  Y := UiBuildFolderField(BooksPathEdit, BooksPathBrowseBtn,
    UiFolderCaption.Height + Px(6));
  UiBooksWarn := UiLabel(UiContent, 13, False, UiErrorColor, taCenter);
  UiPlaceLabel(UiBooksWarn, ' ', 0, Y + Px(16), Px(UiContentW));
  UiBooksWarn.Height := UiBooksWarn.Height * 3;
  UiInstBooksWarningChanged();
  UiSetContentHeight(UiBooksWarn.Top + UiBooksWarn.Height);
end;
#endif

function UiModeShort(): String;
begin
  if PortableModeRadio.Checked then
    Result := CustomMessage('ModePortableTitle')
  else if AllUsersModeRadio.Checked then
    Result := CustomMessage('ModeAllTitle')
  else
    Result := CustomMessage('ModeMeShort');
end;

function UiModeIcon(): String;
begin
  if PortableModeRadio.Checked then
    Result := 'portable'
  else if AllUsersModeRadio.Checked then
    Result := 'all_users'
  else
    Result := 'only_me';
end;

function UiShortcutsText(): String;
begin
  Result := CustomMessage('ShortcutStart');
  if WizardIsTaskSelected('desktopicon') then
    Result := Result + ', ' + CustomMessage('ShortcutDesktop');
  if WizardIsTaskSelected('calendaricon') then
    Result := Result + ', ' + CustomMessage('ShortcutCalendar');
end;

procedure UiBuildReady();
var
  Previous: String;
begin
  UiAddRow('app', CustomMessage('RowVersion'), LtrUnit('{#MyAppVersion}'), False);
  Previous := GetPreviousDisplayVersion();
  if (Previous <> '') and not PortableMode then
    UiAddRow('update', CustomMessage('RowUpgradeFrom'), LtrUnit(Previous), False);
  UiAddRow(UiModeIcon(), CustomMessage('RowMode'), UiModeShort(), False);
  UiAddRow('install_folder', CustomMessage('RowFolder'), WizardDirValue, True);
#ifdef InstallerFull
  UiAddRow('books_folder', CustomMessage('RowBooks'), GetSelectedBooksPath(''), True);
  if WV2Check.Checked then
    UiAddRow('webview2', CustomMessage('RowComponents'), 'Microsoft WebView2 Runtime', False);
#endif
  if not PortableMode then
  begin
    UiAddRow('start_menu', CustomMessage('RowShortcuts'), UiShortcutsText(), False);
    if WizardIsTaskSelected('resetsettings') then
      UiAddRow('reset_settings', CustomMessage('RowReset'), CustomMessage('ResetValue'), False);
  end;
  UiSetContentHeight(UiPlaceSummary(0));
end;

{ Restart Manager מצא תוכנה שמחזיקה קבצים: הרשימה שלו, ובחירת הסגירה כשני כרטיסים. }
procedure UiBuildPreparing();
var
  Y: Integer;
  Apps: String;
begin
  { עד ש-Restart Manager ממלא אותה, ברשימה נשאר שם הפקד ("PreparingMemo"), והיא מוסתרת. }
  Apps := '';
  if WizardForm.PreparingMemo.Visible then
    Apps := Trim(WizardForm.PreparingMemo.Text);
  StringChangeEx(Apps, #13#10, ', ', True);
  Y := 0;
  if Apps <> '' then
  begin
    UiAddRow('app', CustomMessage('PrepareApps'), Apps, False);
    Y := UiPlaceSummary(0) + Px(UiCardGap);
  end;
  if WizardForm.PreparingYesRadio.Visible then
  begin
    Y := UiInstCard(UiCardCloseApps, 'update', CustomMessage('PrepareCloseTitle'),
      CustomMessage('PrepareCloseDesc'), '', False, Y);
    Y := UiInstCard(UiCardKeepApps, 'warning', CustomMessage('PrepareKeepTitle'),
      CustomMessage('PrepareKeepDesc'), '', False, Y);
    UiEndCards(Y);
  end
  else
    UiSetContentHeight(Y);
end;

{ ============================ התקדמות ============================ }


#ifdef LibraryParts
{ אותן יחידות כמו בתוכנה; בעברית עטופות ב-LtrUnit. }
function HumanSize(Bytes: Int64): String;
var
  Tenths: Int64;
begin
  if Bytes >= Int64(1073741824) then
  begin
    Tenths := (Bytes * 10) div Int64(1073741824);
    Result := LtrUnit(IntToStr(Tenths div 10) + '.' + IntToStr(Tenths mod 10) + #$00A0 + 'GB');
  end
  else
    Result := LtrUnit(IntToStr(Bytes div 1048576) + #$00A0 + 'MB');
end;

type
  TUiFileData = record
    Attributes: LongWord;
    CreationLow, CreationHigh, AccessLow, AccessHigh, WriteLow, WriteHigh: LongWord;
    SizeHigh, SizeLow: LongWord;
  end;

function UiGetFileAttributesEx(Name: String; Level: Integer; var Data: TUiFileData): BOOL;
  external 'GetFileAttributesExW@kernel32.dll stdcall';

{ החלקים מחוברים ברצף לארכיון אחד: ההתקדמות היא גודלו מול סכום החלקים. }
procedure UiLibraryPrepStart(const What, Archive, PartsDir: String;
  const PartNames: TArrayOfString);
var
  I: Integer;
  Size: Int64;
begin
  LibraryPrepWhat := What;
  LibraryPrepArchive := Archive;
  LibraryPrepTotal := 0;
  for I := 0 to GetArrayLength(PartNames) - 1 do
    if FileSize64(AddBackslash(PartsDir) + PartNames[I], Size) then
      LibraryPrepTotal := LibraryPrepTotal + Size;
end;

{ הגודל מרשומת הקובץ ולא מהתיקייה: הארכיון פתוח לכתיבה, ורשומת התיקייה מתעדכנת רק בסגירה. }
function UiAssembledBytes(): Int64;
var
  Data: TUiFileData;
begin
  Result := 0;
  if LibraryPrepArchive = '' then
    exit;
  if UiGetFileAttributesEx(LibraryPrepArchive, 0, Data) then
  begin
    Result := Data.SizeHigh;
    Result := Result * 65536 * 65536 + Data.SizeLow;
  end;
end;
#endif

function UiAdapterProgress(Source: Integer; var Caption, Speed, Bytes: String;
  var Bar: TNewProgressBar; var Fraction: Extended; var Known: Boolean): Boolean;
var
  FileName: String;
#ifdef LibraryParts
  Done: Int64;
#endif
begin
  Result := True;
  if Source = UiSrcFiles then
  begin
    Caption := WizardForm.StatusLabel.Caption;
    FileName := WizardForm.FilenameLabel.Caption;
    if FileName <> '' then
      Speed := LtrUnit(MinimizePathName(FileName, UiProgSpeed.Font, Px(UiContentW)));
    Bar := WizardForm.ProgressGauge;
  end;
#ifdef LibraryParts
  if (Source = UiSrcLibraryPrep) and (LibraryPrepWhat <> '') then
  begin
    Caption := Msg1('LibraryPrepCaption', LibraryPrepWhat);
    Done := UiAssembledBytes();
    if LibraryPrepTotal > 0 then
    begin
      Fraction := Done;
      Fraction := Fraction / LibraryPrepTotal;
      if Fraction > 1 then
        Fraction := 1;
      Known := True;
      Bytes := FmtMessage(CustomMessage('LibraryPrepBytes'), [HumanSize(Done),
        HumanSize(LibraryPrepTotal)]);
    end;
  end;
#endif
end;

{ ============================ שלבים ============================ }

function UiAdapterStepOf(PageID: Integer; var Total: Integer): Integer;
var
  Pages: array of Integer;
  I: Integer;
begin
  SetArrayLength(Pages, 3);
  Pages[0] := wpSelectDir;
  Pages[1] := wpSelectTasks;
  Pages[2] := wpReady;
#ifdef InstallerFull
  SetArrayLength(Pages, 4);
  Pages[1] := BooksPage.ID;
  Pages[2] := wpSelectTasks;
  Pages[3] := wpReady;
#endif
  Result := 0;
  Total := 0;
  for I := 0 to GetArrayLength(Pages) - 1 do
    if not ShouldSkipPage(Pages[I]) then
    begin
      Total := Total + 1;
      if Pages[I] = PageID then
        Result := Total;
    end;
  { ההכנה, הכנת הספרייה וההתקנה — שלב אחד. }
  Total := Total + 1;
  if (PageID = wpPreparing) or (PageID = wpInstalling) then
    Result := Total;
#ifdef LibraryParts
  if (LibraryPrepPage <> nil) and (PageID = LibraryPrepPage.ID) then
    Result := Total;
#endif
end;

{ ============================ סיום ============================ }

{ "פתח את אוצריא" ו"סגור" מסמנים או מנקים את רשומת ההפעלה של [Run], ולוחצים על "סיום". }
procedure UiFinish(Launch: Boolean);
var
  I: Integer;
begin
  for I := 0 to WizardForm.RunList.Items.Count - 1 do
    WizardForm.RunList.Checked[I] := Launch;
  UiClickReal(WizardForm.NextButton);
end;

procedure UiAdapterBuildFinish();
var
  Page: TNewNotebookPage;
  Y, Bottom, I: Integer;
  CanRun, Restart: Boolean;
  Body: String;
begin
  Page := WizardForm.FinishedPage;
  Restart := WizardForm.YesRadio.Visible;
  CanRun := (WizardForm.RunList.Items.Count > 0) and not Restart and not InstFailed;
  WizardForm.WizardBitmapImage2.Visible := False;
  WizardForm.FinishedHeadingLabel.Visible := False;
  WizardForm.FinishedLabel.Visible := False;
  WizardForm.RunList.Left := -Px(4000);
  WizardForm.RunList.TabStop := False;
  WizardForm.YesRadio.Left := -Px(4000);
  WizardForm.NoRadio.Left := -Px(4000);
  { בכישלון Enter ("סיום" האמיתי) לא יפעיל את התוכנה ולא יאתחל את המחשב בלי לשאול. }
  if InstFailed then
  begin
    for I := 0 to WizardForm.RunList.Items.Count - 1 do
      WizardForm.RunList.Checked[I] := False;
    if Restart then
      WizardForm.NoRadio.Checked := True;
  end;

  if not Assigned(UiFinBadge) then
  begin
    UiFinBadge := UiImage(Page);
    UiFinBadge.SetBounds(0, Px(UiBadgeTop - UiBarH), 1, 1);
    if InstFailed then
      UiShowArt(UiFinBadge, 'badge_err')
    else
      UiShowArt(UiFinBadge, 'badge_ok');
    UiFinBadge.Left := (Px(UiWidth) - UiFinBadge.Width) div 2;
    UiFinTitle := UiLabel(Page, 20, True, UiTextColor, taCenter);
    UiMakeButton(UiBtnOpenApp, Page, 'btn_primary', Px(UiMargin), 0);
    UiMakeButton(UiBtnDone, Page, 'btn_ghost', Px(UiMargin), 0);
    UiButtons[UiBtnOpenApp].Width := Px(UiContentW);
    UiButtons[UiBtnDone].Width := Px(UiContentW);
  end;
  if InstFailed then
    Y := UiPlaceLabel(UiFinTitle, CustomMessage('FailTitle'), Px(UiMargin),
      UiFinBadge.Top + UiFinBadge.Height + Px(16), Px(UiContentW))
  else if InstIsUpdate and not PortableMode then
    Y := UiPlaceLabel(UiFinTitle, CustomMessage('FinishUpdated'), Px(UiMargin),
      UiFinBadge.Top + UiFinBadge.Height + Px(16), Px(UiContentW))
  else
    Y := UiPlaceLabel(UiFinTitle, WizardForm.FinishedHeadingLabel.Caption, Px(UiMargin),
      UiFinBadge.Top + UiFinBadge.Height + Px(16), Px(UiContentW));

  UiButtons[UiBtnDone].Drawn := '';
  if CanRun then
  begin
    UiButtons[UiBtnOpenApp].Img.Top := Px(UiStackTop(0, 2) - UiBarH);
    UiButtons[UiBtnDone].Img.Top := Px(UiStackTop(1, 2) - UiBarH);
    UiButtons[UiBtnDone].Art := 'btn_ghost';
    UiSetButton(UiBtnDone, True, True, CustomMessage('Close'));
    Bottom := UiButtons[UiBtnOpenApp].Img.Top;
  end
  else
  begin
    UiButtons[UiBtnDone].Img.Top := Px(UiStackTop(0, 1) - UiBarH);
    UiButtons[UiBtnDone].Art := 'btn_primary';
    if InstFailed then
      UiSetButton(UiBtnDone, True, True, CustomMessage('Close'))
    else
      UiSetButton(UiBtnDone, True, True, UiStrip(WizardForm.NextButton.Caption));
    Bottom := UiButtons[UiBtnDone].Img.Top;
  end;
  UiSetButton(UiBtnOpenApp, CanRun, True, CustomMessage('OpenApp'));
  UiFooter.Visible := False;

  if InstFailed then
  begin
    UiPlaceHost(Page, Y + Px(8), Bottom - Px(12));
    { מה עכשיו: אפשר לנסות שוב; הספרייה הקודמת שלמה כל עוד ההחלפה לא התחילה (ברגיל —
      תמיד: כל כשל שם מחזיר אותה). }
    Body := InstFailText + #13#10#13#10 + CustomMessage('FailRetry');
#ifdef InstallerFull
    if not LibrarySwapStarted then
      Body := InstFailText + #13#10#13#10 + CustomMessage('FailLibraryKept') + ' ' +
        CustomMessage('FailRetry');
#endif
#ifdef LibraryParts
    Body := InstFailText + #13#10#13#10 + CustomMessage('FailLibraryKept') + ' ' +
      CustomMessage('FailRetry');
#endif
    UiFailBody := UiLabel(UiContent, 14, False, UiSecondaryColor, taCenter);
    Y := UiPlaceLabel(UiFailBody, Body, 0, 0, Px(UiContentW));
    if InstFailTech <> '' then
    begin
      UiFailLink := UiLabel(UiContent, 13, True, UiPrimaryColor, taCenter);
      UiFailLink.Cursor := crHand;
      UiFailLink.OnClick := @UiFailLinkClick;
      Y := UiPlaceLabel(UiFailLink, CustomMessage('TechDetails'), 0, Y + Px(14),
        Px(UiContentW)) + Px(10);
      UiFailTech := TRichEditViewer.Create(WizardForm);
      UiFailTech.Parent := UiContent;
      UiFailTech.ReadOnly := True;
      UiFailTech.BorderStyle := bsNone;
      UiFailTech.ScrollBars := ssVertical;
      UiFailTech.Color := UiCardColor;
      UiFailTech.UseRichEdit := True;
      UiFailTech.RTFText := UiRtf(InstFailTech);
      UiFailTech.SetBounds(0, Y, Px(UiContentW), UiHost.Height - Y);
      UiFailTech.Visible := False;
      Y := UiHost.Height;
    end;
    UiSetContentHeight(Y);
    exit;
  end;
  UiPlaceHost(Page, Y + Px(20), Bottom - Px(12));
  SetArrayLength(UiCardKind, 0);
  if Restart then
  begin
    Y := UiPlaceLabel(UiLabel(UiContent, 14, False, UiSecondaryColor, taCenter),
      WizardForm.FinishedLabel.Caption, 0, 0, Px(UiContentW)) + Px(12);
    Y := UiInstCard(UiCardRestartNow, 'update', UiStrip(WizardForm.YesRadio.Caption), '', '',
      False, Y);
    Y := UiInstCard(UiCardRestartLater, 'app', UiStrip(WizardForm.NoRadio.Caption), '', '',
      False, Y);
    UiEndCards(Y);
    exit;
  end;
  UiAddRow('app', CustomMessage('RowVersion'), LtrUnit('{#MyAppVersion}'), False);
  UiAddRow('install_folder', CustomMessage('RowFolder'), WizardDirValue, True);
#ifdef InstallerFull
  if not PortableMode or not PortableSkipLibrary then
    UiAddRow('books_folder', CustomMessage('RowBooks'), GetSelectedBooksPath(''), True);
#endif
  UiSetContentHeight(UiPlaceSummary(0));
end;

{ ============================ בניית עמוד ============================ }

procedure UiAdapterLeavePage();
begin
  SetArrayLength(UiCardKind, 0);
  UiFolderCaption := nil;
  UiDiskLabel := nil;
  UiModeNote := nil;
  UiBooksWarn := nil;
  UiFailBody := nil;
  UiFailLink := nil;
  UiFailTech := nil;
end;

function UiAdapterPageHint(PageID: Integer): String;
begin
  Result := '';
  if PageID = wpSelectDir then
  begin
    WizardForm.SelectDirLabel.Visible := False;
    WizardForm.SelectDirBitmapImage.Visible := False;
    WizardForm.SelectDirBrowseLabel.Visible := False;
    WizardForm.DiskSpaceLabel.Visible := False;
  end
  else if PageID = wpSelectTasks then
  begin
    WizardForm.SelectTasksLabel.Visible := False;
    WizardForm.TasksList.Left := -Px(4000);
  end
  else if PageID = wpReady then
  begin
    WizardForm.ReadyLabel.Visible := False;
    WizardForm.ReadyMemo.Visible := False;
    Result := WizardForm.ReadyLabel.Caption;
  end
  else if PageID = wpPreparing then
  begin
    WizardForm.PreparingLabel.Visible := False;
    WizardForm.PreparingErrorBitmapImage.Visible := False;
    WizardForm.PreparingMemo.Left := -Px(4000);
    { הרשימה מוצגת בסיכום; בלי מוקד בה, החצים נשארים בין שני הרדיו. }
    WizardForm.PreparingMemo.Enabled := False;
    WizardForm.PreparingYesRadio.Left := -Px(4000);
    WizardForm.PreparingNoRadio.Left := -Px(4000);
    { הכותרת מוצגת כבר בזמן ש-Restart Manager בודק: "אוצריא פתוחה" רק כשהוא מצא משהו. }
    if WizardForm.PreparingMemo.Visible then
      WizardForm.PageDescriptionLabel.Caption := CustomMessage('PrepareAppsOpen');
  end;
#ifdef LibraryParts
  if (PageID = wpInstalling) and (PreparedLibraryArchive <> '') then
    WizardForm.PageDescriptionLabel.Caption := CustomMessage('LibraryInstallingDesc');
#endif
#ifdef InstallerFull
  if PageID = BooksPage.ID then
    Result := CustomMessage('BooksHint');
#endif
end;

procedure UiAdapterBuildPage(PageID: Integer);
begin
  if PageID = wpSelectDir then
    UiBuildModePage()
  else if PageID = wpSelectTasks then
    UiBuildTasksPage()
  else if PageID = wpReady then
    UiBuildReady()
  else if PageID = wpPreparing then
    UiBuildPreparing()
  else if PageID = wpInstalling then
  begin
    WizardForm.StatusLabel.Left := -Px(4000);
    WizardForm.FilenameLabel.Left := -Px(4000);
    WizardForm.ProgressGauge.Left := -Px(4000);
    UiBuildProgress(UiSrcFiles);
  end;
#ifdef InstallerFull
  if PageID = BooksPage.ID then
    UiBuildBooksPage();
#endif
#ifdef LibraryParts
  if (LibraryPrepPage <> nil) and (PageID = LibraryPrepPage.ID) then
  begin
    UiHideProgressNative(LibraryPrepPage);
    UiBuildProgress(UiSrcLibraryPrep);
  end;
#endif
end;

{ ============================ כפתורים ============================ }

{ X: באשף — אותה שאלת יציאה כמו "ביטול"; בעמוד הסיום — "סגור". }
procedure UiRequestClose();
begin
  if UiPage = wpFinished then
    UiFinish(False)
  else if WizardForm.CancelButton.CanFocus then
    PostMessage(WizardForm.Handle, UiWmSysCommand, UiScClose, 0);
end;

procedure UiButtonClick(Sender: TObject);
var
  I: Integer;
begin
  { בזמן דו-שיח החלון מושבת; לחיצה שבכל זאת הגיעה הייתה פותחת שאלה שנייה. }
  if UiIsWindowEnabled(WizardForm.Handle) = 0 then
    exit;
  for I := 0 to GetArrayLength(UiButtons) - 1 do
    if (Sender = UiButtons[I].Img) and UiButtons[I].Shown and UiButtons[I].Enabled then
      case I of
        UiBtnOpenApp: UiFinish(True);
        UiBtnDone: UiFinish(False);
        UiBtnClose: UiRequestClose();
      else
        UiCoreButtonClick(I);
      end;
end;

{ ============================ עכבר וכותרת תחתונה ============================ }

procedure UiAdapterPollMouse(Wnd: Longint; const P: TUiPoint);
begin
end;

procedure UiAdapterSyncFooter();
begin
end;

{ הכרטיס שהפקד האמיתי שמאחוריו במוקד: רדיו, שורה ברשימת המשימות או תיבת סימון. }
function UiAdapterCardFocused(I: Integer): Boolean;
var
  List: TNewCheckListBox;
begin
  Result := False;
  List := WizardForm.TasksList;
  case UiCardKind[I] of
    UiCardModeMe: Result := CurrentUserModeRadio.Focused;
    UiCardModeAll: Result := AllUsersModeRadio.Focused;
    UiCardModePortable: Result := PortableModeRadio.Focused;
    UiCardDesktop: Result := List.Focused and (List.ItemIndex = UiTaskIndex('desktopicon'));
    UiCardCalendar: Result := List.Focused and (List.ItemIndex = UiTaskIndex('calendaricon'));
    UiCardReset: Result := List.Focused and (List.ItemIndex = UiTaskIndex('resetsettings'));
#ifdef InstallerFull
    UiCardWebView2: Result := WV2Check.Focused;
#endif
    UiCardCloseApps: Result := WizardForm.PreparingYesRadio.Focused;
    UiCardKeepApps: Result := WizardForm.PreparingNoRadio.Focused;
    UiCardRestartNow: Result := WizardForm.YesRadio.Focused;
    UiCardRestartLater: Result := WizardForm.NoRadio.Focused;
  end;
end;

{ בסיום המוקד עובר לפעולה הראשונה, כמו במסייע; Inno שם אותו ברשימת ההפעלה הנסתרת. }
function UiAdapterFocusTarget(Native: TWinControl; I: Integer): Integer;
var
  J: Integer;
begin
  Result := I;
  if Native = WizardForm.RunList then
    Result := UiBtnDone;
  if (Result < 0) or (UiPage <> wpFinished) then
    exit;
  Result := -1;
  for J := UiBtnOpenApp to UiBtnDone do
    if Assigned(UiButtons[J].Img) and UiButtons[J].Img.CanFocus then
    begin
      WizardForm.ActiveControl := UiButtons[J].Img;
      exit;
    end;
end;

function UiAdapterEnterGoesNext(): Boolean;
begin
  Result := True;
end;

{ ============================ חיבור לאשף ============================ }

{ /SILENT — חלון ההתקדמות המצומצם; /VERYSILENT — בלי שכבת התצוגה כלל, כמו קודם. }
procedure UiInstallerInitializeWizard();
var
  Title: String;
begin
  InstIsUpdate := (GetPreviousDisplayVersion() <> '') and not PortableMode;
  if WizardSilent then
  begin
    if CmdLineParamExists('/VERYSILENT') then
      exit;
    if InstIsUpdate then
      Title := Msg1('CompactUpdating', LtrUnit('{#MyAppVersion}'))
    else
      Title := Msg1('CompactInstalling', LtrUnit('{#MyAppVersion}'));
    UiInitializeCompact(Title);
    exit;
  end;
  WizardForm.DirBrowseButton.Caption := CustomMessage('ChangeButton');
#ifdef InstallerFull
  BooksPathBrowseBtn.Caption := CustomMessage('ChangeButton');
#endif
  if InstIsUpdate then
    UiInitializeWizard('title_inst_', 'title_inst_en_', CustomMessage('UpdateButton'))
  else
    UiInitializeWizard('title_inst_', 'title_inst_en_', CustomMessage('InstallButton'));
end;

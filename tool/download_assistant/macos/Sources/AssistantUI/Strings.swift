import Foundation

/// שפת הממשק: עברית כששפת macOS המועדפת היא עברית, אחרת אנגלית — כמו ב-Windows.
public enum UILanguage: String {
    case hebrew = "he"
    case english = "en"

    /// `OTZARIA_ASSISTANT_LANG=he|en` גובר על שפת המערכת (לבדיקה בלי לשנות את המערכת).
    public static func detect(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        preferred: [String] = Locale.preferredLanguages
    ) -> UILanguage {
        if let forced = environment["OTZARIA_ASSISTANT_LANG"].flatMap(UILanguage.init(rawValue:)) {
            return forced
        }
        return preferred.first.map { $0.hasPrefix("he") || $0.hasPrefix("iw") } == true ? .hebrew : .english
    }

    public var isEnglish: Bool { self == .english }
}

/// כל טקסט גלוי בממשק. הניסוח הוא של המסייע ל-Windows (CustomMessages ב-installer/download_assistant*.iss);
/// מפתחות שאינם שם הם ההבדלים של macOS (המחשב הזה, תפריטים, Finder).
public enum StringKey: String, CaseIterable {
    case appTitle, appShortName, welcomeSubtitle, welcomeNote, startButton
    case next, back, start, finish, cancel, close, ok, stopDownload, retry, resume, openDownloads
    case techDetails, stepOf
    case connectTitle, connectDesc, connectingProgress
    case modeTitle, modeDesc, modeThis, modeThisDesc, modeOther, modeOtherDesc, listOr
    case versionToDownload, otzariaVersion
    case otherTitle, otherDesc, otherHint, targetArm, hintMac, hintAndroid, hintArm, hintX64
    case formatDeb, formatRpm, formatPortable
    case presetTitle, presetDesc, presetHint
    case presetFullIndexed, presetFullIndexedDesc, presetFull, presetFullDesc
    case presetBasic, presetBasicDesc, presetUpdate, presetUpdateDesc, presetCustom, presetCustomDesc
    case cardSize, requiredTag, customDesc, customHint
    case folderTitle, folderDesc, folderHint, folderFallbackNote, browse, chooseFolderPrompt
    case readyTitle, readyDesc, readyHint
    case rowVersion, rowWhat, rowFor, rowSavedIn, rowFile, rowFolder
    case downloadingVersion, downloadDesc, downloadingItem, downloadedOf, timeLeft, sizeOf
    case workTitle, workDesc, preparing
    case finishedTitle, guideThisFile, guideOtherFile, guideThisFolder, guideOtherFolder, guideRunExe
    case guideJoin, preparedFiles, openHintExe, openHintDmg, openHintPackage, openHintApk
    case openHintArchive, revealFile, revealFolder, installNow, openFolder
    case offlineTitle, offlineBody, loadFailedBody, stoppedTitle, stoppedBody, runFailedBody
    case noTargetTitle, noTargetText, nothingTitle, nothingText
    case folderBadTitle, folderBadFallback, folderBadText
    case spaceTitle, spaceText, spaceYes
    case exitTitle, exitMessage, exitYes, exitNo
    case connectStopTitle, connectStopText, connectStopYes, connectStopNo
    case stopTitle, stopText, stopYes, stopNo
    case installFailedTitle, installFailedText
    case menuHide, menuHideOthers, menuShowAll, menuQuit, menuEdit, menuCopy, menuSelectAll
    case menuWindow, menuMinimize, menuCloseWindow
}

public struct Strings {
    public let language: UILanguage

    public init(_ language: UILanguage) {
        self.language = language
    }

    public var english: Bool { language.isEnglish }

    /// ‎%1‎, ‎%2‎… כמו FmtMessage של Inno.
    public func callAsFunction(_ key: StringKey, _ args: String...) -> String {
        var text = Strings.table(language)[key] ?? key.rawValue
        for (index, arg) in args.enumerated() {
            text = text.replacingOccurrences(of: "%\(index + 1)", with: arg)
        }
        return text
    }

    public static func table(_ language: UILanguage) -> [StringKey: String] {
        language == .english ? english : hebrew
    }

    static let hebrew: [StringKey: String] = [
        .appTitle: "מסייע ההורדות של אוצריא",
        .appShortName: "מסייע אוצריא",
        .welcomeSubtitle: "ספרייה תורנית חינמית",
        .welcomeNote: "הכלי אינו מתקין דבר — הוא מוריד את קובצי אוצריא ומכין מהם התקנה, גם למחשב בלי אינטרנט.",
        .startButton: "בואו נתחיל",
        .next: "המשך",
        .back: "חזרה",
        .start: "התחל",
        .finish: "סיום",
        .cancel: "ביטול",
        .close: "סגור",
        .ok: "אישור",
        .stopDownload: "עצור הורדה",
        .retry: "נסה שוב",
        .resume: "המשך",
        .openDownloads: "פתח את עמוד ההורדות",
        .techDetails: "פרטים טכניים",
        .stepOf: "שלב %1 מתוך %2",
        .connectTitle: "מתחבר לאתר אוצריא",
        .connectDesc: "מוריד את רשימת הקבצים של הגרסה העדכנית.",
        .connectingProgress: "מתחבר לאתר אוצריא…",
        .modeTitle: "לאיזה מחשב מכינים את ההתקנה?",
        .modeDesc: "המסייע מוריד את קובצי ההתקנה ושומר אותם בתיקייה. הוא עצמו אינו מתקין דבר.",
        .modeThis: "macOS — כמו המחשב הזה",
        .modeThisDesc: "מתאים למחשב הזה ולכל מחשב Mac אחר. הקבצים נשמרים בתיקייה, להתקנה כאן או להעתקה.",
        .modeOther: "סוג מחשב אחר",
        .modeOtherDesc: "מתאים ל-%1. הקבצים נשמרים בתיקייה, להעתקה בדיסק-און-קי.",
        .listOr: "%1 או %2",
        .versionToDownload: "הגרסה שתורד: %1",
        .otzariaVersion: "אוצריא %1",
        .otherTitle: "לאיזה סוג מחשב?",
        .otherDesc: "בחר את סוג המחשב שבו תותקן אוצריא.",
        .otherHint: "ב-Linux, אם אינך יודע איזו הפצה מותקנת, בחר DEB — היא מתאימה לרוב המחשבים.",
        .targetArm: "%1 · מעבד ARM",
        .hintMac: "מחשבי Mac",
        .hintAndroid: "טלפון או טאבלט",
        .hintArm: "למשל מחשבים עם מעבד Snapdragon",
        .hintX64: "מעבד Intel או AMD — כמעט כל המחשבים",
        .formatDeb: "Ubuntu, Debian, Mint והפצות דומות (DEB)",
        .formatRpm: "Fedora, openSUSE והפצות דומות (RPM)",
        .formatPortable: "הפצה אחרת — ללא התקנה",
        .presetTitle: "מה להוריד",
        .presetDesc: "בחר את היקף ההורדה.",
        .presetHint: "אפשר לשנות את הבחירה בהמשך.",
        .presetFullIndexed: "התקנה מלאה + אינדקס חיפוש",
        .presetFullIndexedDesc: "למחשב שאין בו אינטרנט — אינדקס החיפוש מוכן, והחיפוש עובד מיד. כולל\u{00A0}חיפוש\u{00A0}חכם.",
        .presetFull: "התקנה מלאה",
        .presetFullDesc: "למחשב שאין בו אינטרנט — אינדקס החיפוש ייבנה בתוכנה, וזה לוקח זמן. כולל\u{00A0}חיפוש\u{00A0}חכם.",
        .presetBasic: "התקנה בסיסית (מומלצת)",
        .presetBasicDesc: "למחשב שיש בו אינטרנט — הספרייה תרד מתוך התוכנה.",
        .presetUpdate: "עדכון התוכנה בלבד",
        .presetUpdateDesc: "קובץ ההתקנה של הגרסה החדשה, לעדכון התקנה קיימת.",
        .presetCustom: "בחירה אישית",
        .presetCustomDesc: "אני רוצה לבחור בעצמי מה להוריד.",
        .cardSize: "גודל ההורדה: %1",
        .requiredTag: "(נדרש)",
        .customDesc: "סמן את הרכיבים שברצונך להוריד.",
        .customHint: "ליד כל רכיב מופיע גודל ההורדה שלו.",
        .folderTitle: "לאן לשמור",
        .folderDesc: "כברירת מחדל הקבצים נשמרים ליד המסייע עצמו.",
        .folderHint: "אפשר לבחור תיקייה אחרת. מהתיקייה הזאת מתקינים — במחשב הזה, או אחרי העתקה לדיסק-און-קי גם במחשב בלי אינטרנט.",
        .folderFallbackNote: "אי אפשר לשמור ליד המסייע (macOS מריץ אותו מתיקייה זמנית שאין בה הרשאת כתיבה), ולכן הוצעה כאן תיקייה אחרת.",
        .browse: "עיון…",
        .chooseFolderPrompt: "בחר",
        .readyTitle: "מוכנים להתחיל",
        .readyDesc: "הכול מוכן להורדה.",
        .readyHint: "לחץ \"התחל\" כדי להוריד את הקבצים ולהכין מהם התקנה.",
        .rowVersion: "גרסה",
        .rowWhat: "מה יורד",
        .rowFor: "עבור",
        .rowSavedIn: "נשמר בתיקייה",
        .rowFile: "הקובץ",
        .rowFolder: "בתיקייה",
        .downloadingVersion: "מוריד את %1…",
        .downloadDesc: "הקבצים יורדים מאתר אוצריא. אפשר לעצור בכל רגע — מה שכבר ירד יישמר.",
        .downloadingItem: "מוריד: %1",
        .downloadedOf: "ירדו %1 מתוך %2",
        .timeLeft: "נותרו %1",
        .sizeOf: "%1 מתוך %2",
        .workTitle: "הכנת ההתקנה",
        .workDesc: "רגע, מכינים את הקבצים.",
        .preparing: "מתכונן…",
        .finishedTitle: "הכול מוכן",
        .guideThisFile: "אפשר להתקין ממנו עכשיו, או להעתיק אותו למחשב אחר מאותו סוג ולהתקין שם.",
        .guideOtherFile: "העתק את הקובץ הזה לדיסק-און-קי ומשם למחשב המנותק (%1).",
        .guideThisFolder: "אפשר להתקין ממנה עכשיו, או להעתיק את כל התיקייה למחשב אחר מאותו סוג. הקבצים חייבים להישאר יחד באותה תיקייה.",
        .guideOtherFolder: "העתק את כל התיקייה הזאת לדיסק-און-קי ומשם למחשב המנותק (%1). הקבצים חייבים להישאר יחד באותה תיקייה.",
        .guideRunExe: "במחשב המנותק הפעל מתוכה את %1 — אין צורך בחיבור לאינטרנט ואין צורך בתוכנות נוספות.",
        .guideJoin: "חלק מהקבצים גדולים מדי לקובץ אחד ולכן נשארו מחולקים. במחשב היעד מחברים אותם בחלון מסוף (טרמינל), מתוך התיקייה, בפקודה:",
        .preparedFiles: "הקבצים שהוכנו:",
        .openHintExe: "שם הפעל אותו — אין צורך בחיבור לאינטרנט ואין צורך בתוכנות נוספות.",
        .openHintDmg: "שם פתח אותו בלחיצה כפולה וגרור את אוצריא לתיקיית היישומים.",
        .openHintPackage: "שם פתח אותו בלחיצה כפולה כדי להתקין את אוצריא.",
        .openHintApk: "שם העבר אותו לטלפון או לטאבלט ופתח אותו כדי להתקין את אוצריא.",
        .openHintArchive: "שם חלץ אותו והפעל את אוצריא מתוך התיקייה שנוצרה.",
        .revealFile: "הצג את הקובץ שהוכן",
        .revealFolder: "הצג את התיקייה שהוכנה",
        .installNow: "התקן עכשיו במחשב הזה",
        .openFolder: "פתח את תיקיית ההתקנה",
        .offlineTitle: "אין חיבור לאינטרנט",
        .offlineBody: "בדוק את החיבור לאינטרנט ונסה שוב. אפשר גם לפתוח את עמוד ההורדות של אוצריא בדפדפן ולהוריד משם ידנית (אפשרות מוגבלת: המסייע לא יוכל לבדוק את הקבצים או לחבר אותם).",
        .loadFailedBody: "אפשר לנסות שוב, או לפתוח את עמוד ההורדות של אוצריא בדפדפן ולהוריד משם ידנית (אפשרות מוגבלת: המסייע לא יוכל לבדוק את הקבצים או לחבר אותם).",
        .stoppedTitle: "ההורדה הופסקה",
        .stoppedBody: "קבצים שכבר ירדו נשמרו, ו\"המשך\" ימשיך מאותו מקום.",
        .runFailedBody: "קבצים שכבר ירדו נשמרו, ו\"נסה שוב\" ימשיך מהמקום שבו נעצרה הפעולה.",
        .noTargetTitle: "לא נבחר מחשב",
        .noTargetText: "יש לבחור את סוג המחשב שבו תותקן אוצריא.",
        .nothingTitle: "לא נבחר רכיב",
        .nothingText: "יש לבחור לפחות רכיב אחד להורדה.",
        .folderBadTitle: "אי אפשר לשמור בתיקייה הזאת",
        .folderBadFallback: "לא ניתן לשמור בתיקייה שנבחרה. במקומה מוצעת התיקייה:\n%1\n\nאפשר להמשיך איתה או לבחור תיקייה אחרת.",
        .folderBadText: "לא ניתן לשמור בתיקייה שנבחרה. נסה תיקייה אחרת.",
        .spaceTitle: "אין מספיק מקום פנוי",
        .spaceText: "נראה שאין מספיק מקום פנוי. דרושים בערך %1.\n\nלהמשיך בכל זאת?",
        .spaceYes: "להמשיך",
        .exitTitle: "יציאה מהמסייע",
        .exitMessage: "ההורדה לא הושלמה. קבצים שכבר ירדו יישמרו, והפעלה חוזרת תמשיך מהמקום שבו הפסקת.\n\nלצאת עכשיו?",
        .exitYes: "יציאה",
        .exitNo: "המשך",
        .connectStopTitle: "להפסיק את ההתחברות?",
        .connectStopText: "אפשר להתחיל שוב מתי שתרצה.",
        .connectStopYes: "הפסק",
        .connectStopNo: "המשך להתחבר",
        .stopTitle: "לעצור את ההורדה?",
        .stopText: "קבצים שכבר ירדו יישמרו, והפעלה חוזרת תמשיך מאותו מקום.",
        .stopYes: "עצור",
        .stopNo: "המשך להוריד",
        .installFailedTitle: "לא ניתן היה לפתוח את קובץ ההתקנה",
        .installFailedText: "אפשר לפתוח אותו ידנית מתוך התיקייה:\n%1",
        .menuHide: "הסתר את %1",
        .menuHideOthers: "הסתר אחרים",
        .menuShowAll: "הצג הכול",
        .menuQuit: "צא מ%1",
        .menuEdit: "עריכה",
        .menuCopy: "העתק",
        .menuSelectAll: "בחר הכול",
        .menuWindow: "חלון",
        .menuMinimize: "מזער",
        .menuCloseWindow: "סגור",
    ]

    static let english: [StringKey: String] = [
        .appTitle: "Otzaria Download Assistant",
        .appShortName: "Otzaria Assistant",
        .welcomeSubtitle: "Free Torah Library",
        .welcomeNote: "This tool doesn't install anything — it downloads the Otzaria files and prepares an installation from them, even for a computer without internet.",
        .startButton: "Let's Get Started",
        .next: "Continue",
        .back: "Back",
        .start: "Start",
        .finish: "Finish",
        .cancel: "Cancel",
        .close: "Close",
        .ok: "OK",
        .stopDownload: "Stop Download",
        .retry: "Try Again",
        .resume: "Continue",
        .openDownloads: "Open the Downloads Page",
        .techDetails: "Technical details",
        .stepOf: "Step %1 of %2",
        .connectTitle: "Connecting to the Otzaria website",
        .connectDesc: "Getting the list of files for the latest version.",
        .connectingProgress: "Connecting to the Otzaria website…",
        .modeTitle: "Which computer is this for?",
        .modeDesc: "The assistant downloads the installation files and saves them in a folder. It doesn't install anything itself.",
        .modeThis: "macOS — like this computer",
        .modeThisDesc: "For this computer and any other Mac. The files are saved in a folder, to install here or to copy.",
        .modeOther: "A different kind of computer",
        .modeOtherDesc: "For %1. The files are saved in a folder, to copy to a USB drive.",
        .listOr: "%1 or %2",
        .versionToDownload: "Version to download: %1",
        .otzariaVersion: "Otzaria %1",
        .otherTitle: "Which kind of computer?",
        .otherDesc: "Choose the kind of computer Otzaria will be installed on.",
        .otherHint: "On Linux, if you're not sure which distribution is installed, choose DEB — it fits most computers.",
        .targetArm: "%1 · ARM processor",
        .hintMac: "Mac computers",
        .hintAndroid: "A phone or tablet",
        .hintArm: "For example, computers with a Snapdragon processor",
        .hintX64: "Intel or AMD processor — almost every computer",
        .formatDeb: "Ubuntu, Debian, Mint and similar distributions (DEB)",
        .formatRpm: "Fedora, openSUSE and similar distributions (RPM)",
        .formatPortable: "Another distribution — no installation needed",
        .presetTitle: "What to download",
        .presetDesc: "Choose how much to download.",
        .presetHint: "You can change this later.",
        .presetFullIndexed: "Full installation + search index",
        .presetFullIndexedDesc: "For a computer without internet — search works right away. Smart\u{00A0}Search\u{00A0}included.",
        .presetFull: "Full installation",
        .presetFullDesc: "For a computer without internet — Otzaria builds the search index first. Smart\u{00A0}Search\u{00A0}included.",
        .presetBasic: "Basic installation (recommended)",
        .presetBasicDesc: "For a computer with internet — the library downloads from within Otzaria.",
        .presetUpdate: "Update Otzaria only",
        .presetUpdateDesc: "The installer of the new version, to update an existing installation.",
        .presetCustom: "Custom selection",
        .presetCustomDesc: "I want to choose what to download myself.",
        .cardSize: "Download size: %1",
        .requiredTag: "(required)",
        .customDesc: "Check the items you want to download.",
        .customHint: "Each item shows its download size.",
        .folderTitle: "Where to save",
        .folderDesc: "By default, the files are saved next to the assistant itself.",
        .folderHint: "You can choose a different folder. You install from this folder — on this computer, or after copying it to a USB drive, also on a computer without internet.",
        .folderFallbackNote: "The assistant can't save next to itself (macOS runs it from a temporary folder without write access), so a different folder is suggested here.",
        .browse: "Browse…",
        .chooseFolderPrompt: "Choose",
        .readyTitle: "Ready to start",
        .readyDesc: "Everything is ready to download.",
        .readyHint: "Click \"Start\" to download the files and prepare an installation from them.",
        .rowVersion: "Version",
        .rowWhat: "What to download",
        .rowFor: "For",
        .rowSavedIn: "Saved in",
        .rowFile: "File",
        .rowFolder: "In folder",
        .downloadingVersion: "Downloading %1…",
        .downloadDesc: "The files are downloading from the Otzaria website. You can stop at any time — whatever was already downloaded is kept.",
        .downloadingItem: "Downloading: %1",
        .downloadedOf: "%1 of %2 downloaded",
        .timeLeft: "%1 left",
        .sizeOf: "%1 of %2",
        .workTitle: "Preparing the installation",
        .workDesc: "One moment, preparing the files.",
        .preparing: "Getting ready…",
        .finishedTitle: "Everything's ready",
        .guideThisFile: "You can install from it now, or copy it to another computer of the same kind and install there.",
        .guideOtherFile: "Copy this file to a USB drive, and from there to the offline computer (%1).",
        .guideThisFolder: "You can install from it now, or copy the whole folder to another computer of the same kind. The files must stay together in the same folder.",
        .guideOtherFolder: "Copy this whole folder to a USB drive, and from there to the offline computer (%1). The files must stay together in the same folder.",
        .guideRunExe: "On the offline computer, run %1 from it — no internet connection or other software is needed.",
        .guideJoin: "Some files are too large to be a single file, so they were left in parts. On the target computer, join them in a terminal window, from inside the folder, with this command:",
        .preparedFiles: "Prepared files:",
        .openHintExe: "There, run it — no internet connection or other software is needed.",
        .openHintDmg: "There, double-click it and drag Otzaria to the Applications folder.",
        .openHintPackage: "There, double-click it to install Otzaria.",
        .openHintApk: "There, move it to the phone or tablet and open it to install Otzaria.",
        .openHintArchive: "There, extract it and run Otzaria from the folder that was created.",
        .revealFile: "Show the prepared file",
        .revealFolder: "Show the prepared folder",
        .installNow: "Install Now on This Computer",
        .openFolder: "Open the Installation Folder",
        .offlineTitle: "No internet connection",
        .offlineBody: "Check your internet connection and try again. You can also open the Otzaria downloads page in your browser and download manually from there (a limited option: the assistant won't be able to check the files or join them).",
        .loadFailedBody: "You can try again, or open the Otzaria downloads page in your browser and download manually from there (a limited option: the assistant won't be able to check the files or join them).",
        .stoppedTitle: "The download was stopped",
        .stoppedBody: "Files that were already downloaded are saved, and \"Continue\" picks up from the same point.",
        .runFailedBody: "Files that were already downloaded are saved, and \"Try Again\" continues from where it stopped.",
        .noTargetTitle: "No computer selected",
        .noTargetText: "Choose the kind of computer Otzaria will be installed on.",
        .nothingTitle: "Nothing selected",
        .nothingText: "Choose at least one item to download.",
        .folderBadTitle: "Can't save in this folder",
        .folderBadFallback: "The chosen folder can't be used for saving. This folder is suggested instead:\n%1\n\nYou can continue with it or choose another folder.",
        .folderBadText: "The chosen folder can't be used for saving. Try another folder.",
        .spaceTitle: "Not enough free space",
        .spaceText: "There doesn't seem to be enough free space. About %1 is needed.\n\nContinue anyway?",
        .spaceYes: "Continue",
        .exitTitle: "Exit the assistant",
        .exitMessage: "The download isn't finished. Files that were already downloaded are kept, and running the assistant again continues from where you stopped.\n\nExit now?",
        .exitYes: "Exit",
        .exitNo: "Continue",
        .connectStopTitle: "Stop connecting?",
        .connectStopText: "You can start again whenever you like.",
        .connectStopYes: "Stop",
        .connectStopNo: "Keep Connecting",
        .stopTitle: "Stop the download?",
        .stopText: "Files that were already downloaded will be kept, and running the assistant again continues from the same point.",
        .stopYes: "Stop",
        .stopNo: "Keep Downloading",
        .installFailedTitle: "Couldn't open the installation file",
        .installFailedText: "You can open it yourself from the folder:\n%1",
        .menuHide: "Hide %1",
        .menuHideOthers: "Hide Others",
        .menuShowAll: "Show All",
        .menuQuit: "Quit %1",
        .menuEdit: "Edit",
        .menuCopy: "Copy",
        .menuSelectAll: "Select All",
        .menuWindow: "Window",
        .menuMinimize: "Minimize",
        .menuCloseWindow: "Close",
    ]
}

import Foundation

public enum OutputLocation {
    public static let fallbackFolderName = "אוצריא-להתקנה"
    /// בממשק באנגלית, כמו ב-Windows.
    public static let englishFallbackFolderName = "Otzaria setup"

    /// macOS מריץ אפליקציה שהורדה מהרשת מנתיב אקראי לקריאה בלבד (App Translocation).
    public static func isTranslocated(_ bundlePath: String) -> Bool {
        bundlePath.contains("/AppTranslocation/")
    }

    /// כתיבה ממשית של קובץ בדיקה: דיסק לקריאה בלבד או תיקייה מוגנת נראים תקינים עד הניסיון.
    public static func isWritable(_ directory: URL) -> Bool {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let probe = directory.appendingPathComponent("otzaria_write_test.tmp")
            try Data("ok".utf8).write(to: probe)
            try fileManager.removeItem(at: probe)
            return true
        } catch {
            return false
        }
    }

    public static func fallbackBase(english: Bool = false) -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
        return documents.appendingPathComponent(
            english ? englishFallbackFolderName : fallbackFolderName, isDirectory: true
        )
    }

    /// התיקייה שמכילה את ה-.app; כשאי אפשר לכתוב בה — `~/Documents/אוצריא-להתקנה`.
    /// usedFallback מסביר למשתמש למה הוצעה תיקייה אחרת.
    public static func defaultBase(
        bundleURL: URL, fallback: URL = OutputLocation.fallbackBase(),
        isWritable: (URL) -> Bool = OutputLocation.isWritable
    ) -> (url: URL, usedFallback: Bool) {
        let beside = bundleURL.deletingLastPathComponent()
        if !isTranslocated(bundleURL.path) && isWritable(beside) {
            return (beside, false)
        }
        return (fallback, true)
    }
}

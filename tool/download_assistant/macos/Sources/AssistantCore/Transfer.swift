import CryptoKit
import Foundation

/// מה עושים עם תשובת השרת לבקשה שנשלחה מ-`requestedOffset` (0 = בלי Range).
public enum ResponseAction: Equatable {
    /// 206 עם Content-Range תואם בדיוק — ממשיכים את הקובץ החלקי.
    case append(from: Int64)
    /// 200 — הקובץ החלקי מקוצץ לאפס והגוף של אותה תשובה נכתב מההתחלה.
    case writeFromStart
    /// תשובה אחרת לבקשת המשך — הקובץ החלקי נמחק ומנסים מההתחלה.
    case discardPartial
    /// כישלון. retryable רק ל-5xx.
    case fail(retryable: Bool)
}

public enum ResumeRules {
    public static func expectedContentRange(offset: Int64, size: Int64) -> String {
        "bytes \(offset)-\(size - 1)/\(size)"
    }

    /// ברשת המסוננת Range מתעלם ומוחזר 200 עם הקובץ כולו — ולכן 200 נכתב, לא נזרק.
    public static func action(
        requestedOffset: Int64, statusCode: Int, contentRange: String?, expectedSize: Int64
    ) -> ResponseAction {
        if statusCode >= 500 { return .fail(retryable: true) }
        if statusCode == 200 { return .writeFromStart }
        if requestedOffset > 0 {
            if statusCode == 206,
               contentRange?.trimmingCharacters(in: .whitespaces)
                   == expectedContentRange(offset: requestedOffset, size: expectedSize) {
                return .append(from: requestedOffset)
            }
            return .discardPartial
        }
        return .fail(retryable: false)
    }

    /// אחרי ה-hash מהדיסק ממשיכים רק אם המשימה עדיין הבעלים של הקובץ החלקי: אם היא
    /// הסתיימה בינתיים, ניסיון חוזר אולי כבר פתח אותו, ופתיחה שנייה הייתה מקצצת תחתיו.
    public static func mayContinueAfterPrefixHash(
        engineEnded: Bool, currentOwner: AnyObject?, transfer: AnyObject
    ) -> Bool {
        !engineEnded && currentOwner === transfer
    }

    /// Range נשלח רק כשיש קובץ חלקי שאפשר להמשיך.
    public static func rangeHeader(existing: Int64, size: Int64) -> String? {
        existing > 0 && existing < size ? "bytes=\(existing)-" : nil
    }
}

/// ניסיונות חוזרים: עד 3 לקובץ, בהמתנה 2/5/10 שניות, רק על שגיאת רשת או 5xx.
public enum RetryPolicy {
    public static let delays: [TimeInterval] = [2, 5, 10]

    /// ההמתנה לפני הניסיון החוזר ה-`retryIndex` (מ-0), או nil כשנגמרו הניסיונות.
    public static func delay(forRetry retryIndex: Int) -> TimeInterval? {
        retryIndex < delays.count ? delays[retryIndex] : nil
    }

    public static func isNetworkError(_ error: Error) -> Bool {
        let ns = error as NSError
        guard ns.domain == NSURLErrorDomain else { return false }
        switch ns.code {
        case NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet,
             NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed,
             NSURLErrorResourceUnavailable, NSURLErrorInternationalRoamingOff,
             NSURLErrorDataNotAllowed, NSURLErrorSecureConnectionFailed:
            return true
        default:
            return false
        }
    }
}

/// הקובץ החלקי `<name>.download` ו-hash שמתעדכן תוך כדי הכתיבה: כל בית עובר hash פעם אחת.
public final class TransferSink {
    public let url: URL
    public let expectedSize: Int64
    public let expectedSha256: String
    public private(set) var written: Int64 = 0
    private var hasher = SHA256()
    private var handle: FileHandle?

    public init(url: URL, expectedSize: Int64, expectedSha256: String) {
        self.url = url
        self.expectedSize = expectedSize
        self.expectedSha256 = expectedSha256
    }

    /// גודל הקובץ החלקי שכבר קיים (0 כשאין).
    public var existingSize: Int64 { fileSize(url) ?? 0 }

    /// פתיחה לפי ההכרעה. בהמשך, `prefix` הוא ה-hash של החלק הקיים, שחושב מהדיסק פעם אחת.
    public func begin(_ action: ResponseAction, prefix: SHA256? = nil) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw AssistantError(AssistantError.fileUnavailable, technical: "cannot create \(url.path)")
            }
        }
        let handle = try FileHandle(forWritingTo: url)
        self.handle = handle
        switch action {
        case .append(let offset):
            guard let prefix = prefix else {
                throw AssistantError(AssistantError.fileUnavailable, technical: "resume without prefix hash")
            }
            try handle.truncate(atOffset: UInt64(offset))
            try handle.seek(toOffset: UInt64(offset))
            hasher = prefix
            written = offset
        default:
            try handle.truncate(atOffset: 0)
            try handle.seek(toOffset: 0)
            hasher = SHA256()
            written = 0
        }
    }

    public func write(_ data: Data) throws {
        guard let handle = handle else {
            throw AssistantError(AssistantError.fileUnavailable, technical: "write before begin")
        }
        guard written + Int64(data.count) <= expectedSize else {
            throw AssistantError(
                AssistantError.downloadDamaged,
                technical: "\(url.lastPathComponent): more bytes than the expected \(expectedSize)"
            )
        }
        try handle.write(contentsOf: data)
        hasher.update(data: data)
        written += Int64(data.count)
    }

    public func close() {
        try? handle?.close()
        handle = nil
    }

    /// גודל ו-sha256 מול המניפסט, מה-hash שנצבר — בלי קריאה נוספת של הקובץ.
    public func finishAndVerify() -> Bool {
        close()
        guard written == expectedSize else { return false }
        return hexString(hasher.finalize()) == expectedSha256
    }

    public func discard() {
        close()
        try? FileManager.default.removeItem(at: url)
    }
}

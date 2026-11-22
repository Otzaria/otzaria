import CryptoKit
import Foundation

public func hexString<D: Sequence>(_ bytes: D) -> String where D.Element == UInt8 {
    bytes.map { String(format: "%02x", $0) }.joined()
}

/// חותם המטמון `<name>.sha256` בפורמט של sha256sum: `<hex>  <name>\n`.
public enum CacheMarker {
    public static func line(sha256: String, name: String) -> String {
        "\(sha256)  \(name)\n"
    }

    /// ה-hex שבחותם, או nil כשהוא אינו בצורה הצפויה.
    public static func parse(_ text: String) -> String? {
        guard let token = text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).first
        else { return nil }
        let hex = String(token).lowercased()
        return isSha256Hex(hex) ? hex : nil
    }
}

public enum CacheStatus: Equatable {
    /// אין קובץ.
    case missing
    /// קובץ בגודל הנכון בלי חותם תקף — נבדק ב-hash פעם אחת.
    case needsHash
    /// מוכן לשימוש בלי hash נוסף.
    case ready
    /// גודל שגוי — נמחק.
    case invalid
}

/// ההכרעה על קובץ במטמון — בלי מערכת קבצים, כדי שתיבדק ישירות.
public func cacheStatus(
    fileSize: Int64?, fileModified: Date?, markerText: String?, markerModified: Date?,
    expectedSize: Int64, expectedSha256: String
) -> CacheStatus {
    guard let fileSize = fileSize else { return .missing }
    guard fileSize == expectedSize else { return .invalid }
    guard let markerText = markerText, let markerHex = CacheMarker.parse(markerText) else {
        return .needsHash
    }
    // חותם תקף של hash אחר מוכיח שהתוכן שגוי — אין טעם לבדוק אותו שוב.
    guard markerHex == expectedSha256 else { return .invalid }
    // קובץ שנכתב אחרי החותם אינו הקובץ שהחותם מעיד עליו.
    if let fileModified = fileModified, let markerModified = markerModified,
       fileModified <= markerModified {
        return .ready
    }
    return .needsHash
}

/// קובץ בעבודה: ה-hash בשם מונע המשך של קובץ חלקי מגרסה אחרת שנושאת אותו שם.
public func versionedPartialName(name: String, sha256: String) -> String {
    "\(name).\(sha256.prefix(12)).download"
}

/// מטמון ההורדות: `<name>` מאומת, `<name>.<sha12>.download` בתהליך, `<name>.sha256` חותם.
public final class CacheStore {
    public let directory: URL
    private let fileManager = FileManager.default

    public init(directory: URL) {
        self.directory = directory
    }

    public static func defaultDirectory() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches")
        return caches.appendingPathComponent("Otzaria", isDirectory: true)
            .appendingPathComponent("DownloadAssistant", isDirectory: true)
    }

    public func prepare() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func fileURL(_ name: String) -> URL { directory.appendingPathComponent(name) }
    public func partialURL(_ name: String, sha256: String) -> URL {
        directory.appendingPathComponent(versionedPartialName(name: name, sha256: sha256))
    }
    public func markerURL(_ name: String) -> URL { directory.appendingPathComponent(name + ".sha256") }

    public func status(name: String, size: Int64, sha256: String) -> CacheStatus {
        let file = attributes(fileURL(name))
        let marker = attributes(markerURL(name))
        var markerText: String?
        if marker != nil {
            markerText = try? String(contentsOf: markerURL(name), encoding: .utf8)
        }
        return cacheStatus(
            fileSize: file?.size, fileModified: file?.modified,
            markerText: markerText, markerModified: marker?.modified,
            expectedSize: size, expectedSha256: sha256
        )
    }

    public func writeMarker(name: String, sha256: String) throws {
        try CacheMarker.line(sha256: sha256, name: name)
            .write(to: markerURL(name), atomically: true, encoding: .utf8)
    }

    /// מוחק קובץ וחותם (אחרי שחלק הורכב, או כשהקובץ נמצא פגום).
    public func remove(name: String) {
        try? fileManager.removeItem(at: markerURL(name))
        try? fileManager.removeItem(at: fileURL(name))
    }

    /// הקובץ החלקי אומת: מקבל את שמו הסופי, ורק אז נכתב לו חותם.
    /// כישלון בכתיבת החותם אינו מפיל את הריצה — בפעם הבאה הקובץ ייבדק ב-hash.
    public func promotePartial(name: String, sha256: String) throws {
        let final = fileURL(name)
        try? fileManager.removeItem(at: markerURL(name))
        if fileManager.fileExists(atPath: final.path) {
            try fileManager.removeItem(at: final)
        }
        try fileManager.moveItem(at: partialURL(name, sha256: sha256), to: final)
        try? writeMarker(name: name, sha256: sha256)
    }

    func attributes(_ url: URL) -> (size: Int64, modified: Date?)? {
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let size = (attrs[.size] as? NSNumber)?.int64Value
        else { return nil }
        return (size, attrs[.modificationDate] as? Date)
    }
}

public func fileSize(_ url: URL) -> Int64? {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
    return (attrs[.size] as? NSNumber)?.int64Value
}

public let ioChunkSize = 4 * 1024 * 1024

/// hash של `length` הבתים הראשונים בקובץ, בזרימה. progress מקבל את מספר הבתים שנקראו עד כה.
public func hashFilePrefix(
    _ url: URL, length: Int64, progress: ((Int64) -> Void)? = nil, isCancelled: () -> Bool = { false }
) throws -> SHA256 {
    var hasher = SHA256()
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var done: Int64 = 0
    while done < length {
        if isCancelled() { throw OperationCancelled() }
        let want = Int(min(Int64(ioChunkSize), length - done))
        guard let chunk = try handle.read(upToCount: want), !chunk.isEmpty else {
            throw AssistantError(AssistantError.fileUnavailable, technical: "short read in \(url.lastPathComponent)")
        }
        hasher.update(data: chunk)
        done += Int64(chunk.count)
        progress?(done)
    }
    return hasher
}

/// המשתמש עצר. אינו שגיאה שמוצגת לו.
public struct OperationCancelled: Error {
    public init() {}
}

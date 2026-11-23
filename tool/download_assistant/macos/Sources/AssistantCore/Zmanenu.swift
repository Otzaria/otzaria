import Foundation

// מחברי זמננו: העתקה של החלק המקביל ב-tool/release/download_assistant_selection.dart.
// הבדיקות משוות ל-tool/download_assistant/fixtures/expected-zmanenu.json.

public enum Zmanenu {
    public static let repository = "Otzaria/zmanenu-library"
    public static let archiveName = "zmanenu-offline.tar.zst"
    public static let partsManifestName = archiveName + ".manifest.json"
    /// יחסית לתיקיית הנתונים של אוצריא (AttachedLibraryUpdateService.defaultDropDirectory).
    public static let dropFolder = "מסדים אישיים/להתקנה"
    /// ב-Android בחירת התיקייה עוברת דרך SAF, והחבילה לא הייתה מותקנת.
    public static let platforms: Set<String> = ["windows", "macos", "linux"]
    public static let releaseApiURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!

    public static func isOffered(_ target: AssistantTarget) -> Bool {
        platforms.contains(target.platform)
    }

    /// תג ריק — ה-API לא ענה, והכתובת היא של ה-release האחרון.
    public static func assetURL(tag: String, name: String) -> URL? {
        guard Endpoints.isSafeName(name) else { return nil }
        if tag.isEmpty {
            return URL(string: "https://github.com/\(repository)/releases/latest/download/\(name)")
        }
        return Endpoints.assetURL(repository: repository, tag: tag, name: name)
    }

    private static func assets(_ release: [String: Any]) -> [[String: Any]] {
        release["assets"] as? [[String: Any]] ?? []
    }

    private static func int64(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double == double.rounded() else { return nil }
        return number.int64Value
    }

    /// ה-sha256 מתוך `digest` של נכס ב-API (`sha256:<hex>`).
    private static func assetSha256(_ asset: [String: Any]) -> String? {
        guard let digest = asset["digest"] as? String, digest.hasPrefix("sha256:") else { return nil }
        let hex = String(digest.dropFirst("sha256:".count))
        return isSha256Hex(hex) ? hex : nil
    }

    /// הנכס של הארכיון השלם; verified — רק עם sha256 ב-`digest`.
    private static func wholeAsset(_ release: [String: Any], verified: Bool = true) -> [String: Any]? {
        assets(release).first { asset in
            asset["name"] as? String == archiveName
                && (int64(asset["size"]) ?? 0) > 0 && (!verified || assetSha256(asset) != nil)
        }
    }

    /// sha256 ריק — בלי אימות ובלי מטמון (האפליקציה מאמתת בייבוא); size 0 — לא ידוע.
    private static func wholeOffer(tag: String, size: Int64, sha256: String, caption: String) -> ZmanenuOffer? {
        guard let url = assetURL(tag: tag, name: archiveName) else { return nil }
        return ZmanenuOffer(tag: tag, downloads: [
            DownloadItem(name: archiveName, size: size, sha256: sha256, url: url, caption: caption),
        ], partsManifest: nil)
    }

    private static func releaseTag(_ release: [String: Any]) -> String? {
        guard let tag = release["tag_name"] as? String, Endpoints.isSafeName(tag) else { return nil }
        return tag
    }

    /// מאיפה לקרוא את מניפסט החלקים; nil כשאין צורך או שאין כזה. release nil — ה-API לא ענה.
    public static func partsManifestURL(release: [String: Any]?) -> URL? {
        guard let release = release else { return assetURL(tag: "", name: partsManifestName) }
        guard let tag = releaseTag(release), wholeAsset(release) == nil else { return nil }
        guard assets(release).contains(where: { $0["name"] as? String == partsManifestName }) else { return nil }
        return assetURL(tag: tag, name: partsManifestName)
    }

    /// קובץ שלם עם sha256 מה-API; אחרת חלקים לפי מניפסט החלקים; בלעדיו — הקובץ השלם בלי sha256.
    /// אין פריסה ואין בדיקת חתימה: האפליקציה עושה זאת בייבוא.
    public static func offer(release: [String: Any]?, partsManifest: Data?, english: Bool = false) -> ZmanenuOffer? {
        let caption = displayName(english: english)
        var tag = ""
        if let release = release {
            guard let found = releaseTag(release) else { return nil }
            tag = found
            if let whole = wholeAsset(release), let size = int64(whole["size"]), let sha = assetSha256(whole) {
                return wholeOffer(tag: tag, size: size, sha256: sha, caption: caption)
            }
        }
        guard let data = partsManifest else {
            guard let release = release else { return wholeOffer(tag: tag, size: 0, sha256: "", caption: caption) }
            guard let whole = wholeAsset(release, verified: false), let size = int64(whole["size"]) else { return nil }
            return wholeOffer(tag: tag, size: size, sha256: "", caption: caption)
        }
        guard let manifest = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              manifest["archive"] as? String == archiveName,
              let parts = manifest["parts"] as? [Any], !parts.isEmpty
        else { return nil }
        var listed: [String: Int64]?
        if let release = release {
            var names: [String: Int64] = [:]
            for asset in assets(release) {
                if let name = asset["name"] as? String { names[name] = int64(asset["size"]) ?? -1 }
            }
            listed = names
        }
        var downloads: [DownloadItem] = []
        for (index, entry) in parts.enumerated() {
            guard let part = entry as? [String: Any],
                  let name = part["name"] as? String,
                  name == archiveName + ".part-" + String(format: "%03d", index),
                  let size = int64(part["size"]), size > 0,
                  let sha = part["sha256"] as? String, isSha256Hex(sha),
                  let url = assetURL(tag: tag, name: name)
            else { return nil }
            // החלק חייב להיות נכס באותו release ובאותו גודל.
            if let listed = listed, listed[name] != size { return nil }
            downloads.append(DownloadItem(name: name, size: size, sha256: sha, url: url, caption: caption))
        }
        guard let total = int64(manifest["size"]), total == downloads.reduce(0, { $0 + $1.size }) else {
            return nil
        }
        return ZmanenuOffer(tag: tag, downloads: downloads, partsManifest: data)
    }

    /// שם לתצוגה בשורת ההתקדמות.
    public static func displayName(english: Bool) -> String {
        english ? "Contemporary Authors" : "מחברי זמננו"
    }

    /// `~/Library/Application Support/otzaria/מסדים אישיים/להתקנה` — getDataRootPath באפליקציה.
    public static func dropDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/otzaria/" + dropFolder, isDirectory: true)
    }
}

/// מה שיורד. partsManifest — הבתים של מניפסט החלקים שכבר נקרא; nil לקובץ שלם.
public struct ZmanenuOffer: Equatable {
    public let tag: String
    public let downloads: [DownloadItem]
    public let partsManifest: Data?

    public var split: Bool { partsManifest != nil }
    public var downloadSize: Int64 { downloads.reduce(0) { $0 + $1.size } }

    /// בסדר הכתיבה: מניפסט החלקים אחרון, כדי שהאפליקציה לא תמצא חבילה חלקית.
    public var outputFiles: [String] {
        downloads.map { $0.name } + (split ? [Zmanenu.partsManifestName] : [])
    }
}

/// מוריד את פרטי ה-release. לעולם אינו נכשל: בלי release (404) או בלי חבילה — nil.
public final class ZmanenuLoader {
    private let session: URLSession

    public init() {
        session = URLSession(
            configuration: makeSessionConfiguration(timeout: 30),
            delegate: RedirectGuard(), delegateQueue: nil
        )
    }

    deinit {
        session.finishTasksAndInvalidate()
    }

    /// completion נקרא על ה-main thread.
    public func load(english: Bool, completion: @escaping (ZmanenuOffer?) -> Void) {
        let done: (ZmanenuOffer?) -> Void = { offer in DispatchQueue.main.async { completion(offer) } }
        fetch(Zmanenu.releaseApiURL, json: true) { result in
            var release: [String: Any]?
            switch result {
            case .notFound:
                // אין מאגר או אין בו release: הכתובת הישירה הייתה נכשלת גם היא.
                done(nil)
                return
            case .data(let data):
                release = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                if release == nil {
                    done(nil)
                    return
                }
            case .failed:
                release = nil
            }
            guard let url = Zmanenu.partsManifestURL(release: release) else {
                done(Zmanenu.offer(release: release, partsManifest: nil, english: english))
                return
            }
            self.fetch(url, json: false) { manifestResult in
                var data: Data?
                if case .data(let body) = manifestResult { data = body }
                done(Zmanenu.offer(release: release, partsManifest: data, english: english))
            }
        }
    }

    private enum FetchResult {
        case data(Data)
        case notFound
        case failed
    }

    private func fetch(_ url: URL, json: Bool, completion: @escaping (FetchResult) -> Void) {
        guard Endpoints.isAllowed(url) else {
            completion(.failed)
            return
        }
        var request = URLRequest(url: url)
        request.setValue(Endpoints.userAgent, forHTTPHeaderField: "User-Agent")
        if json {
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        }
        session.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if error == nil, status == 200, let data = data, data.count <= 4 * 1024 * 1024 {
                completion(.data(data))
            } else if error == nil, status == 404 {
                completion(.notFound)
            } else {
                completion(.failed)
            }
        }.resume()
    }
}

/// כותב את הקבצים ל-directory: קודם כולם בשמות זמניים, ואז שינוי שם בזה אחר זה ומניפסט
/// החלקים אחרון — האפליקציה סורקת את תיקיית האיסוף, ואסור שתמצא חבילה חלקית.
public func placeZmanenu(
    _ offer: ZmanenuOffer, in directory: URL, sourceURL: (DownloadItem) -> URL,
    progress: ((Int64) -> Void)? = nil, isCancelled: () -> Bool = { false }
) throws -> [URL] {
    let fileManager = FileManager.default
    do {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
        throw AssistantError(AssistantError.copyFailed, technical: "\(directory.path): \(error)")
    }
    func temporaryURL(_ name: String) -> URL {
        directory.appendingPathComponent("\(name).tmp")
    }
    var staged: [String] = []
    defer {
        for name in staged { try? fileManager.removeItem(at: temporaryURL(name)) }
    }
    var done: Int64 = 0
    for item in offer.downloads {
        if isCancelled() { throw OperationCancelled() }
        let base = done
        staged.append(item.name)
        do {
            try placeFile(
                from: sourceURL(item), to: temporaryURL(item.name),
                progress: { progress?(base + $0) }, isCancelled: isCancelled
            )
        } catch let error as OperationCancelled {
            throw error
        } catch {
            throw AssistantError(AssistantError.copyFailed, technical: "\(item.name): \(error)")
        }
        done += fileSize(sourceURL(item)) ?? item.size
        progress?(done)
    }
    if let manifest = offer.partsManifest {
        staged.append(Zmanenu.partsManifestName)
        do {
            try manifest.write(to: temporaryURL(Zmanenu.partsManifestName))
        } catch {
            throw AssistantError(AssistantError.copyFailed, technical: "\(Zmanenu.partsManifestName): \(error)")
        }
    }
    var produced: [URL] = []
    for name in offer.outputFiles {
        let destination = directory.appendingPathComponent(name)
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: temporaryURL(name), to: destination)
        } catch {
            throw AssistantError(AssistantError.copyFailed, technical: "\(name): \(error)")
        }
        produced.append(destination)
    }
    staged.removeAll()
    return produced
}

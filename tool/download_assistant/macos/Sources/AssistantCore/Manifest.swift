import Foundation

/// שגיאה שמוצגת למשתמש: משפט בעברית, ומאחורי "פרטים טכניים" — הסיבה האמיתית.
public struct AssistantError: Error, Equatable {
    public let message: String
    public let technical: String
    /// הבקשה לא הגיעה לשרת כלל (אין רשת, שם שאינו נפתר) — הממשק מציג "אין חיבור לאינטרנט".
    public let offline: Bool

    public init(_ message: String, technical: String, offline: Bool = false) {
        self.message = message
        self.technical = technical
        self.offline = offline
    }

    /// שגיאות URLSession שפירושן שאין חיבור — כמו קודי WinHTTP שהמסייע ל-Windows מזהה.
    public static func isOfflineError(_ error: Error) -> Bool {
        guard let code = (error as? URLError)?.code else { return false }
        return [
            .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
            .networkConnectionLost, .timedOut, .internationalRoamingOff, .dataNotAllowed,
        ].contains(code)
    }

    public static let fileUnavailable =
        "לא ניתן להכין את ההתקנה משום שאחד הקבצים הדרושים אינו זמין."
    public static let cannotConnect = "לא ניתן להתחבר לאתר ההורדות של אוצריא."
    public static let cannotReadList = "לא ניתן לקרוא את רשימת הקבצים של אוצריא."
    public static let cannotPrepare = "לא ניתן להכין את ההתקנה."
    public static let copyFailed = "לא ניתן היה להעתיק את הקבצים לתיקייה שנבחרה."
    public static let saveFailed = "לא ניתן היה לשמור את הקבצים. ייתכן שאין מספיק מקום פנוי."
    public static let downloadDamaged = "אחד הקבצים שהורדו נמצא פגום ולא נשמר."
    public static let writeJoinedFailed = "לא ניתן היה לכתוב את הקובץ המאוחד. ייתכן שאין מספיק מקום פנוי."
    public static let joinedDamaged = "הקובץ המאוחד נמצא פגום ולכן לא נשמר."

    /// כל משפט שהלוגיקה מציגה, ובאנגלית — בשביל ממשק באנגלית. משפט שאינו כאן מוצג כפי שהוא.
    public static let english: [String: String] = [
        fileUnavailable: "Can't prepare the installation because one of the required files isn't available.",
        cannotConnect: "Can't connect to the Otzaria downloads site.",
        cannotReadList: "Can't read the list of Otzaria files.",
        cannotPrepare: "Can't prepare the installation.",
        copyFailed: "Couldn't copy the files to the chosen folder.",
        saveFailed: "Couldn't save the files. There may not be enough free space.",
        downloadDamaged: "One of the downloaded files was damaged, so it wasn't saved.",
        writeJoinedFailed: "Couldn't write the joined file. There may not be enough free space.",
        joinedDamaged: "The joined file was damaged, so it wasn't saved.",
    ]

    public func message(english: Bool) -> String {
        english ? (Self.english[message] ?? message) : message
    }
}

public struct ManifestPart: Decodable, Equatable {
    public let name: String
    public let size: Int64
    public let sha256: String

    public init(name: String, size: Int64, sha256: String) {
        self.name = name
        self.size = size
        self.sha256 = sha256
    }
}

public struct ManifestAsset: Decodable, Equatable {
    public let kind: String
    public let repository: String
    public let releaseTag: String
    public let name: String
    public let size: Int64
    public let sha256: String
    public let parts: [ManifestPart]

    public var isSplit: Bool { kind == "split" }

    enum CodingKeys: String, CodingKey {
        case kind, repository, releaseTag, name, size, sha256, parts
    }

    public init(
        kind: String, repository: String, releaseTag: String, name: String,
        size: Int64, sha256: String, parts: [ManifestPart] = []
    ) {
        self.kind = kind
        self.repository = repository
        self.releaseTag = releaseTag
        self.name = name
        self.size = size
        self.sha256 = sha256
        self.parts = parts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "single"
        repository = try c.decode(String.self, forKey: .repository)
        releaseTag = try c.decode(String.self, forKey: .releaseTag)
        name = try c.decode(String.self, forKey: .name)
        size = try c.decode(Int64.self, forKey: .size)
        sha256 = try c.decode(String.self, forKey: .sha256)
        parts = try c.decodeIfPresent([ManifestPart].self, forKey: .parts) ?? []
    }
}

public struct ManifestComponent: Decodable, Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let type: String
    public let required: Bool
    public let platform: String
    public let architecture: String
    public let packageFormat: String
    public let dependsOn: [String]
    /// הרכיבים שמתקינים את הרכיב הזה (מתקין שקורא אותו מהתיקייה שלצדו).
    public let installedBy: [String]
    /// הרכיב שזה חלק ממנו ('' — אין): אינו שורה משלו בבחירה האישית ומגיע דרך dependsOn שלו.
    public let partOf: String
    /// תיקייה יחסית בתיקיית הפלט לקובצי הרכיב ('' — ישירות בה).
    public let outputFolder: String
    /// משפט לעמוד הסיום כשהרכיב הוכן ('' — אין).
    public let outputNote: String
    /// השדות באנגלית ('' ב-release ישן — אז מוצג העברי, כמו componentText במימוש הייחוס).
    public let nameEn: String
    public let descriptionEn: String
    public let outputNoteEn: String
    public let downloadSize: Int64
    public let assets: [ManifestAsset]

    enum CodingKeys: String, CodingKey {
        case id, name, description, type, required, platform, architecture
        case packageFormat, dependsOn, installedBy, partOf, outputFolder, outputNote
        case downloadSize, assets, nameEn, descriptionEn, outputNoteEn
    }

    public func displayName(english: Bool) -> String {
        english && !nameEn.isEmpty ? nameEn : name
    }

    public func displayDescription(english: Bool) -> String {
        english && !descriptionEn.isEmpty ? descriptionEn : description
    }

    public func displayOutputNote(english: Bool) -> String {
        english && !outputNoteEn.isEmpty ? outputNoteEn : outputNote
    }

    public init(
        id: String, name: String = "", description: String = "", type: String,
        required: Bool = false, platform: String = "", architecture: String = "",
        packageFormat: String = "", dependsOn: [String] = [], installedBy: [String] = [],
        partOf: String = "", outputFolder: String = "", outputNote: String = "",
        downloadSize: Int64 = 0, assets: [ManifestAsset] = [],
        nameEn: String = "", descriptionEn: String = "", outputNoteEn: String = ""
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.type = type
        self.required = required
        self.platform = platform
        self.architecture = architecture
        self.packageFormat = packageFormat
        self.dependsOn = dependsOn
        self.installedBy = installedBy
        self.partOf = partOf
        self.outputFolder = outputFolder
        self.outputNote = outputNote
        self.downloadSize = downloadSize
        self.assets = assets
        self.nameEn = nameEn
        self.descriptionEn = descriptionEn
        self.outputNoteEn = outputNoteEn
    }

    // שדות הסינון אופציונליים; חסר נקרא כמחרוזת ריקה, בדיוק כמו במימוש הייחוס.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        required = try c.decodeIfPresent(Bool.self, forKey: .required) ?? false
        platform = try c.decodeIfPresent(String.self, forKey: .platform) ?? ""
        architecture = try c.decodeIfPresent(String.self, forKey: .architecture) ?? ""
        packageFormat = try c.decodeIfPresent(String.self, forKey: .packageFormat) ?? ""
        dependsOn = try c.decodeIfPresent([String].self, forKey: .dependsOn) ?? []
        installedBy = try c.decodeIfPresent([String].self, forKey: .installedBy) ?? []
        partOf = try c.decodeIfPresent(String.self, forKey: .partOf) ?? ""
        outputFolder = try c.decodeIfPresent(String.self, forKey: .outputFolder) ?? ""
        outputNote = try c.decodeIfPresent(String.self, forKey: .outputNote) ?? ""
        downloadSize = try c.decodeIfPresent(Int64.self, forKey: .downloadSize) ?? 0
        assets = try c.decode([ManifestAsset].self, forKey: .assets)
        nameEn = try c.decodeIfPresent(String.self, forKey: .nameEn) ?? ""
        descriptionEn = try c.decodeIfPresent(String.self, forKey: .descriptionEn) ?? ""
        outputNoteEn = try c.decodeIfPresent(String.self, forKey: .outputNoteEn) ?? ""
    }
}

public struct ReleaseManifest: Decodable, Equatable {
    public static let supportedSchemaVersion = 1

    public let schemaVersion: Int
    public let releaseTag: String
    public let releaseVersion: String
    public let components: [ManifestComponent]

    public init(
        schemaVersion: Int = 1, releaseTag: String = "", releaseVersion: String = "",
        components: [ManifestComponent]
    ) {
        self.schemaVersion = schemaVersion
        self.releaseTag = releaseTag
        self.releaseVersion = releaseVersion
        self.components = components
    }

    public func component(withId id: String) -> ManifestComponent? {
        components.first { $0.id == id }
    }

    private struct Header: Decodable {
        let schemaVersion: Int
    }

    /// מפענח ומאמת. כל כשל זורק [AssistantError] — אין מניפסט חלקי ואין רכיב בלי hash.
    public static func parse(_ data: Data) throws -> ReleaseManifest {
        let decoder = JSONDecoder()
        let header: Header
        do {
            header = try decoder.decode(Header.self, from: data)
        } catch {
            throw invalid("cannot decode manifest header: \(error)")
        }
        // גרסה אחרת עלולה לשנות את משמעות השדות — לא מנחשים.
        guard header.schemaVersion == supportedSchemaVersion else {
            throw invalid("unsupported schemaVersion \(header.schemaVersion)")
        }
        let manifest: ReleaseManifest
        do {
            manifest = try decoder.decode(ReleaseManifest.self, from: data)
        } catch {
            throw invalid("cannot decode manifest: \(error)")
        }
        try manifest.validate()
        return manifest
    }

    func validate() throws {
        guard !components.isEmpty else { throw Self.invalid("manifest has no components") }
        for component in components {
            guard !component.id.isEmpty, !component.name.isEmpty, !component.assets.isEmpty else {
                throw Self.invalid("component without id/name/assets: \(component.id)")
            }
            guard component.outputFolder.isEmpty || isSafeOutputFolder(component.outputFolder) else {
                throw Self.invalid("unsafe outputFolder in component \(component.id)")
            }
            for asset in component.assets {
                try Self.validate(asset: asset, in: component.id)
            }
        }
    }

    private static func validate(asset: ManifestAsset, in componentId: String) throws {
        guard Endpoints.assetURL(repository: asset.repository, tag: asset.releaseTag, name: asset.name) != nil,
              isSha256Hex(asset.sha256), asset.size > 0
        else {
            throw invalid("bad asset in component \(componentId): \(asset.name)")
        }
        // כמו במימוש הייחוס: כל מה שאינו split הוא קובץ בודד.
        if asset.isSplit {
            guard !asset.parts.isEmpty else {
                throw invalid("split asset without parts: \(asset.name)")
            }
            var total: Int64 = 0
            for part in asset.parts {
                guard Endpoints.isSafeName(part.name), isSha256Hex(part.sha256), part.size > 0 else {
                    throw invalid("bad part of \(asset.name): \(part.name)")
                }
                total += part.size
            }
            // סכום החלקים חייב להתאים לגודל הנכס גם לפני אימות ה-hash של התוצר.
            guard total == asset.size else {
                throw invalid("parts of \(asset.name) sum to \(total), expected \(asset.size)")
            }
        }
    }

    static func invalid(_ technical: String) -> AssistantError {
        AssistantError(AssistantError.cannotReadList, technical: technical)
    }
}

/// שמות `[A-Za-z0-9._-]` מופרדים ב-`/`, בלי מקטע ריק או של נקודות בלבד — נתיב כתיבה בתוך הפלט.
public func isSafeOutputFolder(_ folder: String) -> Bool {
    guard !folder.isEmpty, !folder.contains("+") else { return false }
    return folder.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { segment in
        Endpoints.isSafeName(String(segment)) && segment.contains { $0 != "." }
    }
}

/// 64 תווי hex קטנים — הצורה שהגנרטור כותב.
public func isSha256Hex(_ value: String) -> Bool {
    value.utf8.count == 64 && value.utf8.allSatisfy { byte in
        (byte >= 0x30 && byte <= 0x39) || (byte >= 0x61 && byte <= 0x66)
    }
}

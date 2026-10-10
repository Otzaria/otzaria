import Foundation

// העתקה נאמנה של tool/release/download_assistant_selection.dart (מימוש הייחוס).
// הבדיקות משוות ל-tool/download_assistant/fixtures/expected-selections.json.

/// גבול הקובץ הבודד: Windows אינו מריץ exe בגודל 4 GiB ומעלה, ו-FAT32 אינו מחזיק קובץ כזה.
public let maxSingleOutputFileSize: Int64 = 4_294_967_296

public let assistantPlatforms = ["windows", "macos", "linux", "android"]

public let platformDisplayNames: [String: String] = [
    "windows": "Windows",
    "macos": "macOS",
    "linux": "Linux",
    "android": "Android",
]

public let portablePackageFormat = "portable"

/// ההצעה המסומנת מראש: במחשב עם אינטרנט הספרייה יורדת מתוך התוכנה.
public let defaultPresetId = "basic"

/// סדר ההצגה. אינו סדר ההערכה ב-buildPresets, שקובע איזו כפולה מושמטת.
public let presetDisplayOrder = ["basic", "full-indexed", "full", "update"]

/// נתוני החיפוש החכם, שהתוכנה קוראת מתיקיית הפלט: חלק מ"full" ומ"full-indexed" בלבד.
public let offlineDataTypes: Set<String> = ["semantic-model", "semantic-vectors"]

/// מחשב היעד. ארכיטקטורה ריקה כשלפלטפורמה אין רכיבים תלויי ארכיטקטורה; פורמט ריק מחוץ ל-Linux.
public struct AssistantTarget: Equatable {
    public var platform: String
    public var architecture: String
    public var packageFormat: String

    public init(platform: String, architecture: String = "", packageFormat: String = "") {
        self.platform = platform
        self.architecture = architecture
        self.packageFormat = packageFormat
    }
}

public struct AssistantPreset: Equatable {
    public let id: String
    public let caption: String
    public let description: String
    public let members: [String]
}

private func isWildcard(_ value: String) -> Bool {
    value.isEmpty || value == "any"
}

public func componentFitsTarget(_ component: ManifestComponent, _ target: AssistantTarget) -> Bool {
    if !isWildcard(component.platform) && component.platform != target.platform { return false }
    if !isWildcard(component.architecture) && component.architecture != target.architecture {
        return false
    }
    if !isWildcard(component.packageFormat) && component.packageFormat != target.packageFormat {
        return false
    }
    return true
}

/// Windows מסרב להריץ exe בגודל 4 GiB ומעלה.
private func componentIsRunnable(_ component: ManifestComponent) -> Bool {
    !component.assets.contains {
        $0.name.lowercased().hasSuffix(".exe") && $0.size >= maxSingleOutputFileSize
    }
}

/// המתקין שיתקין את [component] ביעד — הראשון ב-`installedBy` שמוצע בו, או nil.
public func installerFor(
    _ manifest: ReleaseManifest, _ component: ManifestComponent, _ target: AssistantTarget
) -> ManifestComponent? {
    for id in component.installedBy {
        if let installer = manifest.components.first(where: { $0.id == id }),
           componentFitsTarget(installer, target), componentIsRunnable(installer) {
            return installer
        }
    }
    return nil
}

/// מוצע ליעד (בהצעות ובבחירה האישית): מתאים, בלי exe שאי אפשר להריץ, ואם יש לו
/// `installedBy` — אחד ממתקיניו מוצע.
public func componentIsOffered(
    _ manifest: ReleaseManifest, _ component: ManifestComponent, _ target: AssistantTarget
) -> Bool {
    guard componentFitsTarget(component, target), componentIsRunnable(component) else { return false }
    return component.installedBy.isEmpty || installerFor(manifest, component, target) != nil
}

/// קבוצת הבחירה-אחת-מתוך בבחירה האישית: הדרכים החלופיות להתקין את התוכנה.
public let applicationChoiceGroup = "application"

/// שורה בבחירה האישית. `locked` — מסומנת תמיד; `group` — שורות עם אותה קבוצה הן
/// בחירה אחת-מתוך (רדיו), '' — תיבת סימון.
public struct CustomChoice: Equatable {
    public let component: ManifestComponent
    public let locked: Bool
    public let group: String
}

private func isInstallerType(_ component: ManifestComponent) -> Bool {
    component.type == "application" || component.type == "application-bundle"
}

/// השורות בבחירה האישית, בסדר המניפסט. גרסה ניידת אינה מוצגת; כשהמתקין הרגיל
/// פורס ספרייה שלצדו אין חבילה מלאה והמתקין נעול, ואחרת שניהם בחירה אחת-מתוך.
public func customChoices(_ manifest: ReleaseManifest, _ target: AssistantTarget) -> [CustomChoice] {
    let offered = manifest.components.filter {
        componentIsOffered(manifest, $0, target) && $0.type != "application-portable"
    }
    let takesLibrary = offered.contains { installerFor(manifest, $0, target)?.type == "application" }
    let rows = offered.filter { $0.partOf.isEmpty && !(takesLibrary && $0.type == "application-bundle") }
    let radio = rows.filter(isInstallerType).count > 1
    return rows.map { component in
        let installer = isInstallerType(component)
        return CustomChoice(
            component: component,
            locked: installer && !radio,
            group: installer && radio ? applicationChoiceGroup : "")
    }
}

/// גודל השורה: הרכיב יחד עם החלקים המוצעים שלו.
public func customChoiceSize(
    _ manifest: ReleaseManifest, _ component: ManifestComponent, _ target: AssistantTarget
) -> Int64 {
    manifest.components
        .filter { $0.partOf == component.id && componentIsOffered(manifest, $0, target) }
        .reduce(component.downloadSize) { $0 + $1.downloadSize }
}

/// הפלטפורמות שיש להן לפחות רכיב ייעודי אחד (רכיב `any` לבדו אינו מספיק).
public func platformChoices(_ manifest: ReleaseManifest) -> [String] {
    let present = Set(manifest.components.map { $0.platform })
    return assistantPlatforms.filter { present.contains($0) }
}

/// x64 תמיד ראשונה; העמוד מוצג רק כשיש יותר מאחת.
public func architectureChoices(_ manifest: ReleaseManifest, _ platform: String) -> [String] {
    var found = Set<String>()
    for component in manifest.components where component.platform == platform {
        if !isWildcard(component.architecture) { found.insert(component.architecture) }
    }
    var sorted = found.sorted()
    if let index = sorted.firstIndex(of: "x64") {
        sorted.remove(at: index)
        sorted.insert("x64", at: 0)
    }
    return sorted
}

/// `portable` מוצע כשיש רכיב תוכנה שאינו תלוי מנהל חבילות.
public func packageFormatChoices(
    _ manifest: ReleaseManifest, _ platform: String, _ architecture: String
) -> [String] {
    var formats = Set<String>()
    var portable = false
    for component in manifest.components where component.platform == platform {
        if !isWildcard(component.architecture) && component.architecture != architecture { continue }
        if !isWildcard(component.packageFormat) {
            formats.insert(component.packageFormat)
        } else if component.type.hasPrefix("application") {
            portable = true
        }
    }
    if formats.isEmpty { return [] }
    return formats.sorted() + (portable ? [portablePackageFormat] : [])
}

private let debFamily: Set<String> = [
    "debian", "ubuntu", "linuxmint", "pop", "elementary", "zorin", "raspbian",
    "kali", "neon", "deepin", "mx",
]

private let rpmFamily: Set<String> = [
    "fedora", "rhel", "centos", "rocky", "almalinux", "ol", "suse", "opensuse",
    "sles", "mageia", "openmandriva", "nobara",
]

/// פורמט ברירת המחדל מתוך `/etc/os-release` (nil = לא ב-Linux). ID נבדק לפני ID_LIKE.
public func defaultPackageFormat(_ osRelease: String?, _ choices: [String]) -> String {
    func pick(_ preferred: String) -> String {
        if choices.contains(preferred) { return preferred }
        return choices.first ?? ""
    }
    guard let osRelease = osRelease else { return pick("deb") }

    var values: [String: String] = [:]
    for line in osRelease.components(separatedBy: "\n") {
        guard let equals = line.firstIndex(of: "="), equals != line.startIndex else { continue }
        var value = String(line[line.index(after: equals)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if value.count >= 2, let first = value.first, first == "\"" || first == "'",
           value.last == first {
            value = String(value.dropFirst().dropLast())
        }
        let key = String(line[..<equals]).trimmingCharacters(in: .whitespacesAndNewlines)
        values[key] = value.lowercased()
    }
    let tokens = [values["ID"] ?? ""]
        + (values["ID_LIKE"] ?? "").split(whereSeparator: { $0.isWhitespace }).map(String.init)
    for token in tokens where !token.isEmpty {
        let family = token.hasPrefix("opensuse") ? "opensuse" : token
        if debFamily.contains(family) { return pick("deb") }
        if rpmFamily.contains(family) { return pick("rpm") }
    }
    return pick(portablePackageFormat)
}

private func collect(
    _ manifest: ReleaseManifest, _ target: AssistantTarget,
    types: Set<String>? = nil, requiredOnly: Bool = false
) -> [String] {
    manifest.components.filter { component in
        componentIsOffered(manifest, component, target)
            && (!requiredOnly || component.required)
            && (types == nil || types!.contains(component.type))
    }.map { $0.id }
}

/// סגירת הבחירה: כל `dependsOn` שמוצע ביעד (שאינו מוצע — מדולג), ולכל רכיב עם
/// `installedBy` שאף מתקין שלו אינו בבחירה — המתקין מ-installerFor. בסדר המניפסט.
public func withDependencies(
    _ manifest: ReleaseManifest, _ members: [String], _ target: AssistantTarget
) -> [String] {
    var byId: [String: ManifestComponent] = [:]
    for component in manifest.components {
        byId[component.id] = component
    }
    var closed = Set(members)
    var changed = true
    while changed {
        changed = false
        for id in Array(closed) {
            guard let component = byId[id] else { continue }
            for dependency in component.dependsOn {
                guard let required = byId[dependency], componentIsOffered(manifest, required, target) else {
                    continue
                }
                if closed.insert(dependency).inserted { changed = true }
            }
            if component.installedBy.isEmpty || component.installedBy.contains(where: { closed.contains($0) }) {
                continue
            }
            if let installer = installerFor(manifest, component, target),
               closed.insert(installer.id).inserted {
                changed = true
            }
        }
    }
    return manifest.components.filter { closed.contains($0.id) }.map { $0.id }
}

/// ההצעות ב-presetDisplayOrder. הצעה ריקה, או זהה להצעה שהוערכה לפניה (מלאה + אינדקס,
/// מלאה, בסיסית, עדכון — השם המפורט נשאר), מושמטת. "בחירה אישית" אינה כאן.
public func buildPresets(_ manifest: ReleaseManifest, _ target: AssistantTarget) -> [AssistantPreset] {
    let components = manifest.components
    let offline = collect(manifest, target, types: offlineDataTypes)

    // חבילה יחד עם כל רכיב מוצע שהיא ב-`installedBy` שלו.
    func withInstalled(_ bundle: ManifestComponent) -> [String] {
        [bundle.id] + components.filter {
            $0.installedBy.contains(bundle.id) && componentIsOffered(manifest, $0, target)
        }.map { $0.id }
    }
    func sizeOf(_ ids: [String]) -> Int64 {
        components.filter { ids.contains($0.id) }.reduce(Int64(0)) { $0 + $1.downloadSize }
    }

    var bundle: ManifestComponent?
    var indexed: ManifestComponent?
    for component in components
    where componentIsOffered(manifest, component, target) && component.type == "application-bundle" {
        if bundle == nil || component.downloadSize > bundle!.downloadSize {
            bundle = component
        }
        // החבילה המאונדקסת: ספרייה מוצעת מותקנת על ידה.
        let installsLibrary = components.contains {
            $0.type == "library" && $0.installedBy.contains(component.id)
                && componentIsOffered(manifest, $0, target)
        }
        if installsLibrary
            && (indexed == nil || sizeOf(withInstalled(component)) > sizeOf(withInstalled(indexed!))) {
            indexed = component
        }
    }

    // בלי חבילה, "מלאה" היא התוכנה עם ספרייה — ובלי ספרייה אין "מלאה". ב-Android
    // גם "מלאה + אינדקס": בטלפון בניית האינדקס איטית מאוד.
    let full: [String]
    var fullIndexed = indexed.map { withInstalled($0) + offline } ?? []
    if let bundle = bundle {
        full = withInstalled(bundle) + offline
    } else {
        let collected = collect(manifest, target, types: ["application", "library", "dependency"])
        let hasLibrary = components.contains { collected.contains($0.id) && $0.type == "library" }
        full = hasLibrary ? collected + offline : []
        if hasLibrary && target.platform == "android" {
            fullIndexed = collected + collect(manifest, target, types: ["library-index"]) + offline
        }
    }

    let candidates: [(id: String, caption: String, description: String, members: [String])] = [
        (
            "full-indexed",
            "התקנה מלאה + אינדקס חיפוש",
            "למחשב שאין בו אינטרנט — אינדקס החיפוש מוכן, והחיפוש עובד מיד. כולל חיפוש חכם.",
            fullIndexed
        ),
        (
            "full",
            "התקנה מלאה",
            "למחשב שאין בו אינטרנט — אינדקס החיפוש ייבנה בתוכנה, וזה לוקח זמן. כולל חיפוש חכם.",
            full
        ),
        (
            "basic",
            "התקנה בסיסית (מומלצת)",
            "למחשב שיש בו אינטרנט — הספרייה תרד מתוך התוכנה.",
            collect(manifest, target, types: ["application"])
                + collect(manifest, target, requiredOnly: true)
        ),
        (
            "update",
            "עדכון התוכנה בלבד",
            "קובץ ההתקנה של הגרסה החדשה, לעדכון התקנה קיימת.",
            collect(manifest, target, types: ["application"])
        ),
    ]

    var presets: [AssistantPreset] = []
    for candidate in candidates where !candidate.members.isEmpty {
        let closed = withDependencies(manifest, candidate.members, target)
        if closed.isEmpty { continue }
        if presets.contains(where: { $0.members == closed }) { continue }
        presets.append(AssistantPreset(
            id: candidate.id,
            caption: candidate.caption,
            description: candidate.description,
            members: closed
        ))
    }
    return presetDisplayOrder.compactMap { id in presets.first { $0.id == id } }
}

/// מזהה ההצעה המסומנת מראש: defaultPresetId, ובלעדיה "full" — לא "full-indexed" הגדולה ממנה;
/// בלי שתיהן — הראשונה. nil כשאין הצעות.
public func defaultPresetIdFor(_ presets: [AssistantPreset]) -> String? {
    for id in [defaultPresetId, "full"] where presets.contains(where: { $0.id == id }) {
        return id
    }
    return presets.first?.id
}

/// ל-Windows: רק exe מתחת ל-4 GiB (ארכיון נשאר חלקים — המתקין קורא אותם).
/// לכל יעד אחר: כל נכס מתחת ל-4 GiB, כי שם המשתמש פורס אותו בעצמו.
public func shouldAssembleSplitAsset(_ asset: ManifestAsset, _ targetPlatform: String) -> Bool {
    if asset.size >= maxSingleOutputFileSize { return false }
    if targetPlatform == "windows" {
        return asset.name.lowercased().hasSuffix(".exe")
    }
    return true
}

public func outputSubfolderName(_ targetPlatform: String) -> String {
    "אוצריא להתקנה ל-\(platformDisplayNames[targetPlatform] ?? targetPlatform)"
}

/// הקבצים שייווצרו בתיקיית היעד, בסדר המניפסט; קובץ של רכיב עם outputFolder — '<folder>/<name>'.
public func plannedOutputFiles(
    _ manifest: ReleaseManifest, _ selectedIds: [String], _ target: AssistantTarget
) -> [String] {
    let selected = Set(selectedIds)
    var files: [String] = []
    for component in manifest.components where selected.contains(component.id) {
        let prefix = component.outputFolder.isEmpty ? "" : component.outputFolder + "/"
        for asset in component.assets {
            if asset.isSplit && !shouldAssembleSplitAsset(asset, target.platform) {
                files.append(contentsOf: asset.parts.map { prefix + $0.name })
            } else {
                files.append(prefix + asset.name)
            }
        }
    }
    return files
}

/// ה-outputNote של הרכיבים שנבחרו, בסדר המניפסט ובלי כפולים.
public func plannedOutputNotes(
    _ manifest: ReleaseManifest, _ selectedIds: [String], english: Bool = false
) -> [String] {
    let selected = Set(selectedIds)
    var notes: [String] = []
    for component in manifest.components where selected.contains(component.id) {
        let note = component.displayOutputNote(english: english)
        if !note.isEmpty && !notes.contains(note) { notes.append(note) }
    }
    return notes
}

/// '' לקובץ יחיד, אחרת תת-התיקייה.
public func plannedOutputSubfolder(_ files: [String], _ targetPlatform: String) -> String {
    files.count > 1 ? outputSubfolderName(targetPlatform) : ""
}

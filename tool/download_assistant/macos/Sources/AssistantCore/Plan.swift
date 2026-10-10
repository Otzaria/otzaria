import Foundation

/// קובץ אחד שיורד למטמון: נכס בודד או חלק של נכס מפוצל.
public struct DownloadItem: Equatable {
    public let name: String
    public let size: Int64
    public let sha256: String
    public let url: URL
    /// שם הרכיב, לתצוגה.
    public let caption: String
}

/// `folder` — outputFolder של הרכיב, יחסית לתיקיית היעד ('' — ישירות בה).
public enum OutputAction: Equatable {
    /// קובץ מהמטמון לתיקיית היעד, באותו שם (קישור קשיח, ובכישלון העתקה).
    case place(DownloadItem, folder: String = "")
    /// חלקים שמחוברים לקובץ אחד ישר בתיקיית היעד.
    case assemble(
        name: String, size: Int64, sha256: String, caption: String, parts: [DownloadItem],
        folder: String = ""
    )

    /// הנתיב היחסי בתיקיית היעד, כמו ב-plannedOutputFiles.
    public var outputPath: String {
        switch self {
        case .place(let item, let folder): return folder.isEmpty ? item.name : folder + "/" + item.name
        case .assemble(let name, _, _, _, _, let folder): return folder.isEmpty ? name : folder + "/" + name
        }
    }
}

/// כל מה שהריצה עושה, מחושב מראש מהמניפסט ומהבחירה.
public struct PreparationPlan: Equatable {
    public let downloads: [DownloadItem]
    public let actions: [OutputAction]
    public let outputFiles: [String]
    public let outputSubfolder: String
    /// נכסים שנשארו חלקים ביעד שאינו Windows — עמוד הסיום מציג להם פקודת חיבור.
    public let keptSplitAssets: [String]
    /// ההסברים לעמוד הסיום (plannedOutputNotes).
    public var outputNotes: [String] = []

    public var totalDownloadSize: Int64 { downloads.reduce(0) { $0 + $1.size } }

    /// `english` — שמות הרכיבים והסברי הסיום באנגלית. `subfolderName` מחליף את שם תת-התיקייה
    /// של החוזה (ממשק באנגלית, כמו ב-Windows); הקבצים עצמם אינם משתנים.
    public static func make(
        manifest: ReleaseManifest, selectedIds: [String], target: AssistantTarget,
        english: Bool = false, subfolderName: String? = nil
    ) throws -> PreparationPlan {
        let selected = Set(selectedIds)
        var downloads: [DownloadItem] = []
        var actions: [OutputAction] = []
        var kept: [String] = []
        var seen = Set<String>()

        func item(_ name: String, _ size: Int64, _ sha: String, _ asset: ManifestAsset, _ caption: String)
            throws -> DownloadItem {
            guard let url = Endpoints.assetURL(repository: asset.repository, tag: asset.releaseTag, name: name)
            else {
                throw AssistantError(AssistantError.fileUnavailable, technical: "unsafe asset \(name)")
            }
            return DownloadItem(name: name, size: size, sha256: sha, url: url, caption: caption)
        }
        func add(_ download: DownloadItem) {
            if seen.insert(download.name).inserted { downloads.append(download) }
        }

        for component in manifest.components where selected.contains(component.id) {
            let folder = component.outputFolder
            let caption = component.displayName(english: english)
            for asset in component.assets {
                if asset.isSplit {
                    let parts = try asset.parts.map {
                        try item($0.name, $0.size, $0.sha256, asset, caption)
                    }
                    parts.forEach(add)
                    if shouldAssembleSplitAsset(asset, target.platform) {
                        actions.append(.assemble(
                            name: asset.name, size: asset.size, sha256: asset.sha256,
                            caption: caption, parts: parts, folder: folder
                        ))
                    } else {
                        actions.append(contentsOf: parts.map { OutputAction.place($0, folder: folder) })
                        if target.platform != "windows" { kept.append(asset.name) }
                    }
                } else {
                    let single = try item(asset.name, asset.size, asset.sha256, asset, caption)
                    add(single)
                    actions.append(.place(single, folder: folder))
                }
            }
        }

        let files = plannedOutputFiles(manifest, selectedIds, target)
        return PreparationPlan(
            downloads: downloads,
            actions: actions,
            outputFiles: files,
            outputSubfolder: subfolderName.map { files.count > 1 ? $0 : "" }
                ?? plannedOutputSubfolder(files, target.platform),
            keptSplitAssets: kept,
            outputNotes: plannedOutputNotes(manifest, selectedIds, english: english)
        )
    }
}

/// הרכבה שנקטעה: כמה חלקים שלמים כבר בקובץ המורכב, ולאיזה גודל לקצץ אותו.
public func assemblyResumePoint(partialSize: Int64, partSizes: [Int64]) -> (parts: Int, keepBytes: Int64) {
    var total: Int64 = 0
    var count = 0
    for size in partSizes {
        if total + size > partialSize { break }
        total += size
        count += 1
    }
    return (count, total)
}

/// שם הקובץ המורכב בזמן העבודה. ה-hash בשם מונע המשך הרכבה של גרסה אחרת באותו שם.
public func assemblyPartialName(name: String, sha256: String) -> String {
    versionedPartialName(name: name, sha256: sha256)
}

/// פקודת החיבור שמוצגת לנכס שנשאר חלקים.
public func joinCommand(assetName: String) -> String {
    "cat '\(assetName)'.part-* > '\(assetName)'"
}

/// מקום פנוי שדרוש: במטמון — להורדות שעוד אינן בו; ביעד — מה שייכתב שם בפועל.
public struct SpaceNeed: Equatable {
    public let cacheBytes: Int64
    public let outputBytes: Int64
}

/// באותו כרך קישור קשיח אינו תופס מקום, והרכבה מוחקת כל חלק אחרי שנוסף — השיא הוא חלק אחד.
public func spaceNeeded(
    plan: PreparationPlan, isCached: (DownloadItem) -> Bool, sameVolume: Bool
) -> SpaceNeed {
    let cacheBytes = plan.downloads.filter { !isCached($0) }.reduce(Int64(0)) { $0 + $1.size }
    var outputBytes: Int64 = 0
    for action in plan.actions {
        switch action {
        case .place(let item, _):
            if !sameVolume { outputBytes += item.size }
        case .assemble(_, let size, _, _, let parts, _):
            outputBytes += sameVolume ? (parts.map { $0.size }.max() ?? 0) : size
        }
    }
    return SpaceNeed(cacheBytes: cacheBytes, outputBytes: outputBytes)
}

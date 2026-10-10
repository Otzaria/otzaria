import Foundation

public enum PreparationPhase: Equatable {
    case checkingCache
    case downloading
    case assembling
    case verifyingAssembly
    case copying
}

/// מה שהממשק מציג: שלב עם כותרת בעברית, והתקדמות בבתים. אף שלב אינו נשאר קפוא בלי כותרת.
public struct PreparationStatus: Equatable {
    public var phase: PreparationPhase
    public var title: String
    public var detail: String
    public var doneBytes: Int64
    public var totalBytes: Int64
    public var bytesPerSecond: Double?
    public var secondsRemaining: TimeInterval?

    public init(
        phase: PreparationPhase, title: String, detail: String, doneBytes: Int64, totalBytes: Int64,
        bytesPerSecond: Double? = nil, secondsRemaining: TimeInterval? = nil
    ) {
        self.phase = phase
        self.title = title
        self.detail = detail
        self.doneBytes = doneBytes
        self.totalBytes = totalBytes
        self.bytesPerSecond = bytesPerSecond
        self.secondsRemaining = secondsRemaining
    }

    public var fraction: Double {
        totalBytes > 0 ? min(1, Double(doneBytes) / Double(totalBytes)) : 0
    }

    public static let checkingCacheTitle = "בודק קבצים שכבר הורדו"
    public static let verifyingPartialTitle = "בודק את החלק שכבר ירד"
    public static let downloadingTitle = "מוריד את הקבצים"
    public static let copyingTitle = "מעתיק לתיקייה שנבחרה"
    public static let assemblingTitle = "מחבר את הקבצים"
    public static let verifyingAssemblyTitle = "בודק את הקובץ המאוחד"

    public static let englishTitles: [String: String] = [
        checkingCacheTitle: "Checking files that were already downloaded",
        verifyingPartialTitle: "Checking the part that was already downloaded",
        downloadingTitle: "Downloading the files",
        copyingTitle: "Copying to the chosen folder",
        assemblingTitle: "Joining the files",
        verifyingAssemblyTitle: "Checking the joined file",
    ]

    public func title(english: Bool) -> String {
        english ? (Self.englishTitles[title] ?? title) : title
    }
}

public struct PreparationResult: Equatable {
    public let outputDirectory: URL
    public let producedFiles: [URL]
    /// הקובץ היחיד, או התיקייה כשנוצר יותר מקובץ אחד.
    public let revealTarget: URL
    public let keptSplitAssets: [String]
    /// ההסברים של הרכיבים שהוכנו, לעמוד הסיום.
    public var outputNotes: [String] = []

    public init(
        outputDirectory: URL, producedFiles: [URL], revealTarget: URL, keptSplitAssets: [String],
        outputNotes: [String] = []
    ) {
        self.outputDirectory = outputDirectory
        self.producedFiles = producedFiles
        self.revealTarget = revealTarget
        self.keptSplitAssets = keptSplitAssets
        self.outputNotes = outputNotes
    }
}

/// הכנת ההתקנה מקצה לקצה: מטמון ← הורדה ← הרכבה/העתקה לתיקיית היעד.
public final class PreparationRunner {
    private let plan: PreparationPlan
    private let outputBase: URL
    private let cache: CacheStore
    private let work = DispatchQueue(label: "org.otzaria.assistant.prepare", qos: .userInitiated)
    private var engine: DownloadEngine?
    private let cancelLock = NSLock()
    private var cancelledFlag = false
    private var update: ((PreparationStatus) -> Void)?

    public init(plan: PreparationPlan, outputBase: URL, cache: CacheStore = CacheStore(directory: CacheStore.defaultDirectory())) {
        self.plan = plan
        self.outputBase = outputBase
        self.cache = cache
    }

    public var outputDirectory: URL {
        plan.outputSubfolder.isEmpty
            ? outputBase : outputBase.appendingPathComponent(plan.outputSubfolder, isDirectory: true)
    }

    private var isCancelled: Bool {
        cancelLock.lock()
        defer { cancelLock.unlock() }
        return cancelledFlag
    }

    public func cancel() {
        cancelLock.lock()
        cancelledFlag = true
        let engine = self.engine
        cancelLock.unlock()
        engine?.cancel()
    }

    /// update ו-completion נקראים על ה-main thread.
    public func start(
        update: @escaping (PreparationStatus) -> Void,
        completion: @escaping (Result<PreparationResult, Error>) -> Void
    ) {
        self.update = update
        let finish: (Result<PreparationResult, Error>) -> Void = { result in
            DispatchQueue.main.async { completion(result) }
        }
        work.async {
            do {
                let downloads = try self.checkCache()
                self.download(downloads, finish: finish)
            } catch {
                finish(.failure(error))
            }
        }
    }

    private func post(_ status: PreparationStatus) {
        let update = self.update
        DispatchQueue.main.async { update?(status) }
    }

    // MARK: - מטמון

    /// הקבצים שעדיין צריך להוריד. קובץ בלי חותם נבדק ב-hash פעם אחת, ואז מקבל חותם.
    private func checkCache() throws -> [DownloadItem] {
        do {
            try cache.prepare()
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        } catch {
            throw AssistantError(AssistantError.copyFailed, technical: "\(error)")
        }
        let skipped = alreadyAssembledParts()
        var needed: [DownloadItem] = []
        let toHash = plan.downloads.filter { !skipped.contains($0.name) }
        let hashTotal = toHash.reduce(Int64(0)) { total, item in
            cache.status(name: item.name, size: item.size, sha256: item.sha256) == .needsHash
                ? total + item.size : total
        }
        var hashed: Int64 = 0
        for item in toHash {
            if isCancelled { throw OperationCancelled() }
            switch cache.status(name: item.name, size: item.size, sha256: item.sha256) {
            case .ready:
                continue
            case .missing:
                needed.append(item)
            case .invalid:
                cache.remove(name: item.name)
                needed.append(item)
            case .needsHash:
                let base = hashed
                var lastPost: Int64 = -1
                let hasher = try hashFilePrefix(
                    cache.fileURL(item.name), length: item.size,
                    progress: { done in
                        guard done - lastPost >= 32 * 1024 * 1024 || done == item.size else { return }
                        lastPost = done
                        self.post(PreparationStatus(
                            phase: .checkingCache, title: PreparationStatus.checkingCacheTitle, detail: item.caption,
                            doneBytes: base + done, totalBytes: hashTotal
                        ))
                    },
                    isCancelled: { self.isCancelled }
                )
                hashed += item.size
                if hexString(hasher.finalize()) == item.sha256 {
                    try? cache.writeMarker(name: item.name, sha256: item.sha256)
                } else {
                    cache.remove(name: item.name)
                    needed.append(item)
                }
            }
        }
        return needed
    }

    /// חלקים שכבר נבלעו בהרכבה שנקטעה — נמחקו מהמטמון ואין להוריד אותם שוב.
    private func alreadyAssembledParts() -> Set<String> {
        var names = Set<String>()
        for action in plan.actions {
            guard case let .assemble(name, _, sha256, _, parts, folder) = action else { continue }
            let working = directory(for: folder)
                .appendingPathComponent(assemblyPartialName(name: name, sha256: sha256))
            let resume = assemblyResumePoint(partialSize: fileSize(working) ?? 0, partSizes: parts.map { $0.size })
            parts.prefix(resume.parts).forEach { names.insert($0.name) }
        }
        return names
    }

    // MARK: - הורדה

    private func download(_ items: [DownloadItem], finish: @escaping (Result<PreparationResult, Error>) -> Void) {
        let engine = DownloadEngine(cache: cache)
        // אותו מנעול של cancel(): ביטול שמגיע עכשיו רואה את המנוע, או שהמנוע לא מתחיל.
        cancelLock.lock()
        let cancelled = cancelledFlag
        if !cancelled { self.engine = engine }
        cancelLock.unlock()
        if cancelled {
            finish(.failure(OperationCancelled()))
            return
        }
        var meter = SpeedMeter()
        engine.run(items, progress: { progress in
            meter.record(time: ProcessInfo.processInfo.systemUptime, bytes: progress.receivedBytes)
            let verifying = progress.verifyingTotal > 0 && progress.activeCaptions.isEmpty
            self.update?(PreparationStatus(
                phase: .downloading,
                title: verifying ? PreparationStatus.verifyingPartialTitle : PreparationStatus.downloadingTitle,
                detail: progress.activeCaptions.joined(separator: ", "),
                doneBytes: verifying ? progress.verifyingBytes : progress.presentBytes,
                totalBytes: verifying ? progress.verifyingTotal : progress.totalBytes,
                bytesPerSecond: verifying ? nil : meter.bytesPerSecond,
                secondsRemaining: verifying ? nil : meter.secondsRemaining(progress.totalBytes - progress.presentBytes)
            ))
        }, finish: { result in
            switch result {
            case .failure(let error):
                finish(.failure(error))
            case .success:
                self.work.async {
                    do {
                        finish(.success(try self.produceOutput()))
                    } catch {
                        finish(.failure(error))
                    }
                }
            }
        })
    }

    // MARK: - תיקיית היעד

    private func directory(for folder: String) -> URL {
        folder.isEmpty ? outputDirectory : outputDirectory.appendingPathComponent(folder, isDirectory: true)
    }

    private func produceOutput() throws -> PreparationResult {
        let directory = outputDirectory
        var produced: [URL] = []
        let total = plan.actions.reduce(Int64(0)) { sum, action in
            switch action {
            case .place(let item, _): return sum + item.size
            case .assemble(_, let size, _, _, _, _): return sum + size
            }
        }
        var done: Int64 = 0
        for action in plan.actions {
            if isCancelled { throw OperationCancelled() }
            switch action {
            case .place(let item, let folder):
                try FileManager.default.createDirectory(at: self.directory(for: folder), withIntermediateDirectories: true)
                let destination = self.directory(for: folder).appendingPathComponent(item.name)
                let base = done
                post(PreparationStatus(
                    phase: .copying, title: PreparationStatus.copyingTitle, detail: item.name,
                    doneBytes: base, totalBytes: total
                ))
                try placeWithProgress(item, to: destination) { copied in
                    self.post(PreparationStatus(
                        phase: .copying, title: PreparationStatus.copyingTitle, detail: item.name,
                        doneBytes: base + copied, totalBytes: total
                    ))
                }
                done += item.size
                produced.append(destination)
            case .assemble(let name, let size, let sha256, let caption, let parts, let folder):
                try FileManager.default.createDirectory(at: self.directory(for: folder), withIntermediateDirectories: true)
                let destination = self.directory(for: folder).appendingPathComponent(name)
                let base = done
                var lastPost: Int64 = -1
                do {
                    try assembleSplitAsset(
                        name: name, size: size, sha256: sha256, parts: parts, destination: destination,
                        partURL: { self.cache.fileURL($0.name) },
                        removePart: { self.cache.remove(name: $0.name) },
                        progress: { appended in
                            guard appended - lastPost >= 32 * 1024 * 1024 || appended == size else { return }
                            lastPost = appended
                            self.post(PreparationStatus(
                                phase: .assembling, title: PreparationStatus.assemblingTitle, detail: caption,
                                doneBytes: base + appended, totalBytes: total
                            ))
                        },
                        verificationProgress: { verified in
                            guard verified == 0 || verified - lastPost >= 32 * 1024 * 1024 || verified == size else { return }
                            lastPost = verified
                            self.post(PreparationStatus(
                                phase: .verifyingAssembly, title: PreparationStatus.verifyingAssemblyTitle, detail: caption,
                                doneBytes: verified, totalBytes: size
                            ))
                        },
                        isCancelled: { self.isCancelled }
                    )
                } catch let error as AssistantError {
                    throw error
                } catch let error as OperationCancelled {
                    throw error
                } catch {
                    throw AssistantError(
                        AssistantError.writeJoinedFailed,
                        technical: "\(name): \(error)"
                    )
                }
                done += size
                produced.append(destination)
            }
        }
        return PreparationResult(
            outputDirectory: directory,
            producedFiles: produced,
            revealTarget: produced.count == 1 ? produced[0] : directory,
            keptSplitAssets: plan.keptSplitAssets,
            outputNotes: plan.outputNotes
        )
    }

    private func placeWithProgress(_ item: DownloadItem, to destination: URL, progress: @escaping (Int64) -> Void) throws {
        do {
            try placeFile(
                from: cache.fileURL(item.name), to: destination,
                progress: progress, isCancelled: { self.isCancelled }
            )
        } catch let error as OperationCancelled {
            throw error
        } catch {
            throw AssistantError(
                AssistantError.copyFailed,
                technical: "\(item.name): \(error)"
            )
        }
        progress(item.size)
    }
}

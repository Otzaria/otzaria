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
    /// nil — בלי שורת זמן (בדיקת מטמון, בדיקת החלק שכבר ירד).
    public var eta: EtaReading?

    public init(
        phase: PreparationPhase, title: String, detail: String, doneBytes: Int64, totalBytes: Int64,
        bytesPerSecond: Double? = nil, eta: EtaReading? = nil
    ) {
        self.phase = phase
        self.title = title
        self.detail = detail
        self.doneBytes = doneBytes
        self.totalBytes = totalBytes
        self.bytesPerSecond = bytesPerSecond
        self.eta = eta
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
    private let clock: () -> TimeInterval
    // ההורדה מעדכנת מה-main thread וההרכבה מתור העבודה.
    private let etaLock = NSLock()
    private var eta = DownloadEta()
    private var phases: [String: EtaPhase] = [:]
    // main thread בלבד.
    private var userPaused = false
    private var lastStatus: PreparationStatus?
    private var refreshTimer: DispatchSourceTimer?
    private var runFinished = false

    public init(
        plan: PreparationPlan, outputBase: URL, cache: CacheStore = CacheStore(directory: CacheStore.defaultDirectory()),
        clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.plan = plan
        self.outputBase = outputBase
        self.cache = cache
        self.clock = clock
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
            DispatchQueue.main.async {
                self.stopRefreshTimer()
                completion(result)
            }
        }
        DispatchQueue.main.async { self.startRefreshTimer() }
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
        DispatchQueue.main.async {
            self.lastStatus = status
            self.update?(status)
        }
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
        let (skipped, joined) = alreadyAssembledParts()
        let planned = EtaPhase.phases(
            for: plan.actions, placeIsInstant: sameVolume(cache.directory, outputDirectory), alreadyJoined: joined
        )
        phases = Dictionary(uniqueKeysWithValues: planned.map { ($0.id, $0) })
        withEta { eta, _ in eta.planPhases(planned) }
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

    /// חלקים שכבר נבלעו בהרכבה שנקטעה — נמחקו מהמטמון ואין להוריד אותם שוב —
    /// והבתים שכבר חוברו לכל נכס.
    private func alreadyAssembledParts() -> (parts: Set<String>, joinedBytes: [String: Int64]) {
        var names = Set<String>()
        var joined: [String: Int64] = [:]
        for action in plan.actions {
            guard case let .assemble(name, _, sha256, _, parts, folder) = action else { continue }
            let working = directory(for: folder)
                .appendingPathComponent(assemblyPartialName(name: name, sha256: sha256))
            let resume = assemblyResumePoint(partialSize: fileSize(working) ?? 0, partSizes: parts.map { $0.size })
            parts.prefix(resume.parts).forEach { names.insert($0.name) }
            joined[name] = resume.keepBytes
        }
        return (names, joined)
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
        engine.run(items, progress: { progress in
            self.reportDownload(progress)
        }, finish: { result in
            switch result {
            case .failure(let error):
                finish(.failure(error))
            case .success:
                self.withEta { eta, _ in eta.finishDownload() }
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

    private func withEta<T>(_ body: (inout DownloadEta, TimeInterval) -> T) -> T {
        etaLock.lock()
        defer { etaLock.unlock() }
        return body(&eta, clock())
    }

    private func currentEta() -> EtaReading {
        withEta { eta, now in eta.displayReading(now: now) }
    }

    /// main thread בלבד.
    private func reportDownload(_ progress: DownloadProgress) {
        let verifying = progress.verifyingTotal > 0 && progress.activeCaptions.isEmpty
        let remaining = progress.totalBytes - progress.presentBytes
        let paused = progress.activeCaptions.isEmpty || userPaused
        let (reading, speed) = withEta { eta, now -> (EtaReading, Double?) in
            if paused {
                eta.pause(remainingBytes: remaining)
            } else {
                eta.report(receivedBytes: progress.receivedBytes, remainingBytes: remaining, now: now)
            }
            return (eta.displayReading(now: now), eta.displaySpeed)
        }
        let status = PreparationStatus(
            phase: .downloading,
            title: verifying ? PreparationStatus.verifyingPartialTitle : PreparationStatus.downloadingTitle,
            detail: progress.activeCaptions.joined(separator: ", "),
            doneBytes: verifying ? progress.verifyingBytes : progress.presentBytes,
            totalBytes: verifying ? progress.verifyingTotal : progress.totalBytes,
            bytesPerSecond: verifying ? nil : speed,
            eta: reading
        )
        lastStatus = status
        update?(status)
    }

    /// main thread בלבד. בלי נתונים חדשים אין דיווחים: הטיימר סופר לאחור ומזהה המתנה לחיבור.
    private func refresh() {
        guard var status = lastStatus, status.eta != nil else { return }
        let showsSpeed = status.phase == .downloading && status.title == PreparationStatus.downloadingTitle
        withEta { eta, now in
            status.eta = eta.displayReading(now: now)
            if showsSpeed { status.bytesPerSecond = eta.displaySpeed }
        }
        lastStatus = status
        update?(status)
    }

    /// main thread בלבד. שאלה פתוחה בזמן הורדה משהה את האומדן.
    public func setEstimatorPaused(_ paused: Bool) {
        userPaused = paused
        if paused { withEta { eta, _ in eta.pause() } }
        refresh()
    }

    /// main thread בלבד. רץ עד סוף כל העבודה, כולל ההרכבה וההעתקה.
    private func startRefreshTimer() {
        guard refreshTimer == nil, !runFinished else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.refresh() }
        refreshTimer = timer
        timer.resume()
    }

    /// main thread בלבד.
    private func stopRefreshTimer() {
        runFinished = true
        refreshTimer?.cancel()
        refreshTimer = nil
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
        for (index, action) in plan.actions.enumerated() {
            if isCancelled { throw OperationCancelled() }
            switch action {
            case .place(let item, let folder):
                try FileManager.default.createDirectory(at: self.directory(for: folder), withIntermediateDirectories: true)
                let destination = self.directory(for: folder).appendingPathComponent(item.name)
                let base = done
                // קישור קשיח מיידי אינו שלב: ההתקדמות שלו לא תנפח את קצב ההעתקה.
                let copyPhase = phases[EtaPhase.placeId(index)]
                if let phase = copyPhase { withEta { eta, now in eta.startPhase(phase, now: now) } }
                post(PreparationStatus(
                    phase: .copying, title: PreparationStatus.copyingTitle, detail: item.name,
                    doneBytes: base, totalBytes: total, eta: currentEta()
                ))
                try placeWithProgress(item, to: destination) { copied in
                    if copyPhase != nil { self.withEta { eta, _ in eta.phaseProgress(copied) } }
                    self.post(PreparationStatus(
                        phase: .copying, title: PreparationStatus.copyingTitle, detail: item.name,
                        doneBytes: base + copied, totalBytes: total, eta: self.currentEta()
                    ))
                }
                if copyPhase != nil { withEta { eta, now in eta.endPhase(now: now) } }
                done += item.size
                produced.append(destination)
            case .assemble(let name, let size, let sha256, let caption, let parts, let folder):
                try FileManager.default.createDirectory(at: self.directory(for: folder), withIntermediateDirectories: true)
                let destination = self.directory(for: folder).appendingPathComponent(name)
                let base = done
                var lastPost: Int64 = -1
                let joinPhase = phases[EtaPhase.joinId(index)]
                let verifyPhase = phases[EtaPhase.verifyId(index)]
                let joinedBefore = joinPhase.map { size - $0.bytes } ?? 0
                var verifying = false
                if let phase = joinPhase { withEta { eta, now in eta.startPhase(phase, now: now) } }
                do {
                    try assembleSplitAsset(
                        name: name, size: size, sha256: sha256, parts: parts, destination: destination,
                        partURL: { self.cache.fileURL($0.name) },
                        removePart: { self.cache.remove(name: $0.name) },
                        progress: { appended in
                            self.withEta { eta, _ in eta.phaseProgress(max(0, appended - joinedBefore)) }
                            guard appended - lastPost >= 32 * 1024 * 1024 || appended == size else { return }
                            lastPost = appended
                            self.post(PreparationStatus(
                                phase: .assembling, title: PreparationStatus.assemblingTitle, detail: caption,
                                doneBytes: base + appended, totalBytes: total, eta: self.currentEta()
                            ))
                        },
                        verificationProgress: { verified in
                            if !verifying {
                                verifying = true
                                if let phase = verifyPhase { self.withEta { eta, now in eta.startPhase(phase, now: now) } }
                            }
                            self.withEta { eta, _ in eta.phaseProgress(verified) }
                            guard verified == 0 || verified - lastPost >= 32 * 1024 * 1024 || verified == size else { return }
                            lastPost = verified
                            self.post(PreparationStatus(
                                phase: .verifyingAssembly, title: PreparationStatus.verifyingAssemblyTitle, detail: caption,
                                doneBytes: verified, totalBytes: size, eta: self.currentEta()
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
                withEta { eta, now in eta.endPhase(now: now) }
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

    /// קישור קשיח מהמטמון מצליח רק באותו כונן; אחרת ההנחה היא העתקה.
    private func sameVolume(_ first: URL, _ second: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.volumeIdentifierKey]
        guard let a = (try? first.resourceValues(forKeys: keys))?.volumeIdentifier as? NSObject,
              let b = (try? second.resourceValues(forKeys: keys))?.volumeIdentifier as? NSObject
        else { return false }
        return a.isEqual(b)
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

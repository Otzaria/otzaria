import CryptoKit
import Foundation

public struct DownloadProgress: Equatable {
    /// בתים שכבר על הדיסק מתוך totalBytes (כולל המשך של קובץ חלקי).
    public var presentBytes: Int64
    public var totalBytes: Int64
    /// בתים שירדו ברשת בריצה הזאת — בסיס המהירות.
    public var receivedBytes: Int64
    /// בדיקת החלק שכבר ירד לפני המשך הורדה (hash מהדיסק, פעם אחת).
    public var verifyingBytes: Int64
    public var verifyingTotal: Int64
    public var activeCaptions: [String]
}

/// עד `maxConcurrent` קבצים בו-זמנית, כל חיבור לקובץ אחר — בלי פיצול קובץ לקטעים,
/// כי ברשת המסוננת Range מתעלם ומוריד מפוצל היה מוריד את הקובץ כמה פעמים.
/// כל המצב נגיש רק מ-`queue` (תור ה-delegate הסדרתי).
public final class DownloadEngine: NSObject, URLSessionDataDelegate {
    private final class Job {
        let item: DownloadItem
        var retries = 0
        /// להתעלם מקובץ חלקי קיים (אחרי שנמצא שאינו שייך לקובץ הזה).
        var fresh = false
        init(item: DownloadItem) { self.item = item }
    }

    private final class Transfer {
        let job: Job
        let sink: TransferSink
        let requestedOffset: Int64
        var appended = false
        var blockedRedirect: URL?
        var fatal: AssistantError?
        var discard = false
        var httpStatus: Int?
        var retryableHTTP = false
        init(job: Job, sink: TransferSink, requestedOffset: Int64) {
            self.job = job
            self.sink = sink
            self.requestedOffset = requestedOffset
        }
    }

    private let cache: CacheStore
    private let maxConcurrent: Int
    private let queue: OperationQueue
    private let hashQueue = DispatchQueue(label: "org.otzaria.assistant.hash", qos: .userInitiated, attributes: .concurrent)
    private var session: URLSession?

    private var pending: [Job] = []
    private var running = 0
    private var transfers: [Int: Transfer] = [:]
    private var present: [String: Int64] = [:]
    private var verifying: [String: (done: Int64, total: Int64)] = [:]
    private var finishedBytes: Int64 = 0
    private var receivedBytes: Int64 = 0
    private var totalBytes: Int64 = 0
    // נקרא גם מתור ה-hash, ולכן מאחורי מנעול.
    private let endedLock = NSLock()
    private var endedFlag = false
    private var ended: Bool {
        get { endedLock.lock(); defer { endedLock.unlock() }; return endedFlag }
        set { endedLock.lock(); endedFlag = newValue; endedLock.unlock() }
    }
    private var lastReport: TimeInterval = 0

    private var onProgress: ((DownloadProgress) -> Void)?
    private var onFinish: ((Result<Void, Error>) -> Void)?

    public init(cache: CacheStore, maxConcurrent: Int = 3) {
        self.cache = cache
        self.maxConcurrent = maxConcurrent
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "org.otzaria.assistant.downloads"
        self.queue = queue
        super.init()
    }

    /// progress ו-finish נקראים על ה-main thread. finish נקרא פעם אחת בדיוק.
    public func run(
        _ items: [DownloadItem],
        progress: @escaping (DownloadProgress) -> Void,
        finish: @escaping (Result<Void, Error>) -> Void
    ) {
        queue.addOperation {
            self.onProgress = progress
            self.onFinish = finish
            self.session = URLSession(
                configuration: makeSessionConfiguration(timeout: 60), delegate: self, delegateQueue: self.queue
            )
            self.pending = items.map { Job(item: $0) }
            self.totalBytes = items.reduce(0) { $0 + $1.size }
            self.pump()
        }
    }

    public func cancel() {
        queue.addOperation {
            self.end(.failure(OperationCancelled()))
        }
    }

    // MARK: - תזמון

    private func pump() {
        guard !ended else { return }
        while running < maxConcurrent, !pending.isEmpty {
            running += 1
            start(pending.removeFirst())
        }
        if running == 0 && pending.isEmpty {
            end(.success(()))
        } else {
            report(force: true)
        }
    }

    private func jobDone(_ job: Job) {
        present[job.item.name] = nil
        finishedBytes += job.item.size
        running -= 1
        pump()
    }

    private func end(_ result: Result<Void, Error>) {
        guard !ended else { return }
        ended = true
        switch result {
        case .success:
            session?.finishTasksAndInvalidate()
        case .failure:
            session?.invalidateAndCancel()
        }
        for transfer in transfers.values { transfer.sink.close() }
        transfers.removeAll()
        let finish = onFinish
        onFinish = nil
        onProgress = nil
        DispatchQueue.main.async { finish?(result) }
    }

    private func fail(_ error: AssistantError) {
        end(.failure(error))
    }

    /// `message` הוא מה שיוצג כשהניסיונות נגמרו.
    private func retry(_ job: Job, technical: String, message: String = AssistantError.fileUnavailable) {
        guard let delay = RetryPolicy.delay(forRetry: job.retries) else {
            fail(AssistantError(message, technical: technical))
            return
        }
        job.retries += 1
        // המקום בתור נשמר בזמן ההמתנה: ניסיון חוזר אינו מוסיף חיבור רביעי.
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
            self.queue.addOperation {
                if !self.ended { self.start(job) }
            }
        }
    }

    // MARK: - קובץ אחד

    private func start(_ job: Job) {
        let item = job.item
        let sink = TransferSink(
            url: cache.partialURL(item.name, sha256: item.sha256), expectedSize: item.size, expectedSha256: item.sha256
        )
        if job.fresh {
            sink.discard()
            job.fresh = false
        }
        let existing = sink.existingSize
        if existing > item.size {
            sink.discard()
        } else if existing == item.size {
            verifyCompletePartial(job, sink: sink)
            return
        }
        let offset = sink.existingSize
        guard let session = session, Endpoints.isAllowed(item.url) else {
            fail(AssistantError(AssistantError.fileUnavailable, technical: "disallowed URL \(item.url)"))
            return
        }
        var request = URLRequest(url: item.url)
        request.setValue(Endpoints.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        if let range = ResumeRules.rangeHeader(existing: offset, size: item.size) {
            request.setValue(range, forHTTPHeaderField: "Range")
        }
        let task = session.dataTask(with: request)
        transfers[task.taskIdentifier] = Transfer(job: job, sink: sink, requestedOffset: offset)
        present[item.name] = offset
        task.resume()
    }

    /// קובץ חלקי בגודל המלא (הריצה הקודמת נעצרה לפני האימות) — hash מהדיסק, בלי בקשה.
    private func verifyCompletePartial(_ job: Job, sink: TransferSink) {
        let item = job.item
        hashPrefix(item, url: sink.url, length: item.size) { hasher in
            guard !self.ended else { return }
            if let hasher = hasher, hexString(hasher.finalize()) == item.sha256 {
                do {
                    try self.cache.promotePartial(name: item.name, sha256: item.sha256)
                    self.jobDone(job)
                } catch {
                    self.fail(AssistantError(AssistantError.fileUnavailable, technical: "\(error)"))
                }
            } else {
                job.fresh = true
                self.start(job)
            }
        }
    }

    /// hash של החלק הקיים על תור צדדי, כדי שהורדות אחרות לא ייעצרו בזמן הקריאה.
    /// completion נקרא תמיד על `queue` (nil בכישלון או כשהמנוע נעצר); הקורא בודק `ended`.
    private func hashPrefix(_ item: DownloadItem, url: URL, length: Int64, completion: @escaping (SHA256?) -> Void) {
        verifying[item.name] = (0, length)
        report(force: true)
        hashQueue.async {
            var lastUpdate: Int64 = 0
            let hasher = try? hashFilePrefix(url, length: length, progress: { done in
                guard done - lastUpdate >= 64 * 1024 * 1024 || done == length else { return }
                lastUpdate = done
                self.queue.addOperation {
                    self.verifying[item.name] = (done, length)
                    self.report(force: false)
                }
            }, isCancelled: { self.ended })
            self.queue.addOperation {
                self.verifying[item.name] = nil
                completion(hasher)
            }
        }
    }

    // MARK: - URLSession delegate (על `queue`)

    public func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if Endpoints.isAllowed(request.url) {
            completionHandler(request)
            return
        }
        transfers[task.taskIdentifier]?.blockedRedirect = request.url
        completionHandler(nil)
    }

    public func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let transfer = transfers[dataTask.taskIdentifier] else {
            completionHandler(.cancel)
            return
        }
        let item = transfer.job.item
        if let blocked = transfer.blockedRedirect {
            transfer.fatal = AssistantError(
                AssistantError.fileUnavailable, technical: "redirect to a disallowed address: \(blocked)"
            )
            completionHandler(.cancel)
            return
        }
        guard let http = response as? HTTPURLResponse else {
            transfer.fatal = AssistantError(AssistantError.fileUnavailable, technical: "not an HTTP response")
            completionHandler(.cancel)
            return
        }
        let action = ResumeRules.action(
            requestedOffset: transfer.requestedOffset, statusCode: http.statusCode,
            contentRange: http.value(forHTTPHeaderField: "Content-Range"), expectedSize: item.size
        )
        switch action {
        case .writeFromStart:
            do {
                try transfer.sink.begin(.writeFromStart)
                present[item.name] = 0
                completionHandler(.allow)
            } catch {
                transfer.fatal = AssistantError(AssistantError.fileUnavailable, technical: "\(error)")
                completionHandler(.cancel)
            }
        case .append(let offset):
            // ה-hash של החלק הקיים מחושב רק אחרי שהשרת הסכים להמשיך — לא לשווא על 200.
            let taskId = dataTask.taskIdentifier
            hashPrefix(item, url: transfer.sink.url, length: offset) { hasher in
                // המשימה הסתיימה בזמן ה-hash (timeout) וייתכן שניסיון חוזר כבר פתח את הקובץ.
                guard ResumeRules.mayContinueAfterPrefixHash(
                    engineEnded: self.ended, currentOwner: self.transfers[taskId], transfer: transfer
                ) else {
                    completionHandler(.cancel)
                    return
                }
                do {
                    guard let hasher = hasher else { throw OperationCancelled() }
                    try transfer.sink.begin(.append(from: offset), prefix: hasher)
                    transfer.appended = true
                    completionHandler(.allow)
                } catch {
                    transfer.discard = true
                    completionHandler(.cancel)
                }
            }
        case .discardPartial:
            transfer.discard = true
            completionHandler(.cancel)
        case .fail(let retryable):
            transfer.httpStatus = http.statusCode
            transfer.retryableHTTP = retryable
            completionHandler(.cancel)
        }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let transfer = transfers[dataTask.taskIdentifier], transfer.fatal == nil else { return }
        do {
            try transfer.sink.write(data)
        } catch let error as AssistantError {
            transfer.fatal = error
            transfer.discard = true
            dataTask.cancel()
            return
        } catch {
            transfer.fatal = AssistantError(
                AssistantError.saveFailed, technical: "\(error)"
            )
            dataTask.cancel()
            return
        }
        let name = transfer.job.item.name
        present[name] = (present[name] ?? 0) + Int64(data.count)
        receivedBytes += Int64(data.count)
        report(force: false)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let transfer = transfers.removeValue(forKey: task.taskIdentifier), !ended else { return }
        let job = transfer.job
        let item = job.item

        if let fatal = transfer.fatal {
            if transfer.discard { transfer.sink.discard() } else { transfer.sink.close() }
            fail(fatal)
            return
        }
        if transfer.discard {
            transfer.sink.discard()
            job.fresh = true
            retry(job, technical: "\(item.name): the partial file could not be resumed")
            return
        }
        if let status = transfer.httpStatus {
            transfer.sink.close()
            if transfer.retryableHTTP {
                retry(job, technical: "\(item.name): HTTP \(status)", message: AssistantError.cannotConnect)
            } else {
                fail(AssistantError(AssistantError.fileUnavailable, technical: "\(item.url): HTTP \(status)"))
            }
            return
        }
        if let error = error {
            // הקובץ החלקי נשמר: הניסיון הבא ימשיך ממנו.
            transfer.sink.close()
            if RetryPolicy.isNetworkError(error) {
                retry(
                    job, technical: "\(item.name): \(error.localizedDescription)",
                    message: AssistantError.cannotConnect
                )
            } else {
                fail(AssistantError(AssistantError.cannotConnect, technical: "\(item.url): \(error.localizedDescription)"))
            }
            return
        }

        if transfer.sink.finishAndVerify() {
            do {
                try cache.promotePartial(name: item.name, sha256: item.sha256)
                jobDone(job)
            } catch {
                fail(AssistantError(AssistantError.fileUnavailable, technical: "\(error)"))
            }
            return
        }
        transfer.sink.discard()
        // המשך של קובץ חלקי מגרסה אחרת באותו שם — הורדה אחת מלאה נוספת.
        if transfer.appended {
            job.fresh = true
            retry(job, technical: "\(item.name): resumed file failed verification")
            return
        }
        fail(AssistantError(
            AssistantError.downloadDamaged,
            technical: "\(item.name): size or sha256 mismatch"
        ))
    }

    // MARK: - התקדמות

    private func report(force: Bool) {
        guard let onProgress = onProgress else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if !force && now - lastReport < 0.2 { return }
        lastReport = now
        let activeNames = Set(
            transfers.values.filter { verifying[$0.job.item.name] == nil }.map { $0.job.item.caption }
        )
        let progress = DownloadProgress(
            presentBytes: finishedBytes + present.values.reduce(0, +),
            totalBytes: totalBytes,
            receivedBytes: receivedBytes,
            verifyingBytes: verifying.values.reduce(0) { $0 + $1.done },
            verifyingTotal: verifying.values.reduce(0) { $0 + $1.total },
            activeCaptions: activeNames.sorted()
        )
        DispatchQueue.main.async { onProgress(progress) }
    }
}

import Foundation

/// עוצר כל הפניה למארח שאינו ברשימה. חל גם על משימות עם completion handler:
/// ההפניה אינה מבוצעת, והמשימה מסתיימת בתשובת ה-3xx — שנכשלת בבדיקת הסטטוס.
final class RedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(Endpoints.isAllowed(request.url) ? request : nil)
    }
}

func makeSessionConfiguration(timeout: TimeInterval) -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.default
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = timeout
    configuration.httpAdditionalHeaders = ["User-Agent": Endpoints.userAgent]
    return configuration
}

/// מאיפה יורד המניפסט של release.
public enum ManifestSource: Equatable {
    case url(URL)
    case missing

    public static let assetName = "otzaria-release-manifest.json"

    /// עם רשימת הנכסים מה-API — הנכס שמסתיים ב-release-manifest.json. בלעדיה (API במגבלת קצב,
    /// נפוץ ב-IP משותף של נטפרי) — הכתובת הישירה של השם הקבוע, כדי שהתג המוטבע עדיין יספיק.
    public static func decide(tag: String, release: [String: Any]?) -> ManifestSource {
        guard let release = release else {
            return directURL(tag: tag).map { .url($0) } ?? .missing
        }
        let assets = release["assets"] as? [[String: Any]] ?? []
        let name = assets.compactMap { $0["name"] as? String }.first { $0.hasSuffix("release-manifest.json") }
        guard let found = name,
              let url = Endpoints.assetURL(repository: "Otzaria/otzaria", tag: tag, name: found)
        else { return .missing }
        return .url(url)
    }

    /// ה-`+` שבתג מקודד כ-%2B בכתובת הזאת.
    public static func directURL(tag: String) -> URL? {
        guard Endpoints.isSafeName(tag) else { return nil }
        let encoded = tag.replacingOccurrences(of: "+", with: "%2B")
        return URL(string: "https://github.com/Otzaria/otzaria/releases/download/\(encoded)/\(assetName)")
    }
}

public struct LoadedRelease {
    public let tag: String
    public let manifest: ReleaseManifest
}

/// קובע את התג (ננעל לכל הריצה), מאתר את נכס המניפסט באותו release ומוריד אותו.
public final class ReleaseLoader {
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
    public func load(embeddedTag: String, completion: @escaping (Result<LoadedRelease, AssistantError>) -> Void) {
        let done: (Result<LoadedRelease, AssistantError>) -> Void = { result in
            DispatchQueue.main.async { completion(result) }
        }
        fetch(Endpoints.releaseApiURL(latest: true), json: true) { latestResult in
            var latestRelease: [String: Any]?
            var latestTag: String?
            var latestError: AssistantError?
            switch latestResult {
            case .success(let data):
                latestRelease = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                latestTag = latestRelease?["tag_name"] as? String
            case .failure(let error):
                latestError = error
            }
            // /releases/latest שאינו זמין אינו כישלון: נשאר התג המוטבע.
            guard let tag = ReleaseTagChoice.choose(embedded: embeddedTag, latest: latestTag) else {
                done(.failure(AssistantError(
                    AssistantError.cannotConnect,
                    technical: latestError?.technical ?? "release has no tag_name",
                    offline: latestError?.offline ?? false
                )))
                return
            }
            if tag == latestTag, latestRelease != nil {
                self.loadManifest(tag: tag, release: latestRelease, completion: done)
                return
            }
            self.fetch(Endpoints.releaseApiURL(latest: false, tag: tag), json: true) { pinnedResult in
                var release: [String: Any]?
                if case .success(let data) = pinnedResult {
                    release = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                }
                self.loadManifest(tag: tag, release: release, completion: done)
            }
        }
    }

    /// release == nil = ה-API לא ענה (403/429 של מגבלת קצב, או חסום) — ניגשים ישר לנכס.
    private func loadManifest(
        tag: String, release: [String: Any]?,
        completion: @escaping (Result<LoadedRelease, AssistantError>) -> Void
    ) {
        let url: URL
        switch ManifestSource.decide(tag: tag, release: release) {
        case .url(let resolved):
            url = resolved
        case .missing:
            completion(.failure(AssistantError(
                AssistantError.cannotReadList, technical: "release \(tag) has no release-manifest asset"
            )))
            return
        }
        fetch(url, json: false) { result in
            switch result {
            case .failure(let error):
                completion(.failure(AssistantError(
                    AssistantError.cannotReadList, technical: error.technical, offline: error.offline
                )))
            case .success(let data):
                do {
                    completion(.success(LoadedRelease(tag: tag, manifest: try ReleaseManifest.parse(data))))
                } catch let error as AssistantError {
                    completion(.failure(error))
                } catch {
                    completion(.failure(AssistantError(
                        AssistantError.cannotReadList, technical: "\(error)"
                    )))
                }
            }
        }
    }

    private func fetch(_ url: URL?, json: Bool, completion: @escaping (Result<Data, AssistantError>) -> Void) {
        guard let url = url, Endpoints.isAllowed(url) else {
            completion(.failure(AssistantError(AssistantError.cannotConnect, technical: "invalid URL")))
            return
        }
        var request = URLRequest(url: url)
        request.setValue(Endpoints.userAgent, forHTTPHeaderField: "User-Agent")
        if json {
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        }
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(AssistantError(
                    AssistantError.cannotConnect, technical: "\(url): \(error.localizedDescription)",
                    offline: AssistantError.isOfflineError(error)
                )))
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200, let data = data else {
                completion(.failure(AssistantError(AssistantError.cannotConnect, technical: "\(url): HTTP \(status)")))
                return
            }
            completion(.success(data))
        }
        task.resume()
    }
}

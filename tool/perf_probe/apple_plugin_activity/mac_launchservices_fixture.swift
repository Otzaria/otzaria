import AppKit
import Foundation

// Diagnostic owner only: the separate, unchanged controller performs hide/activate.
let arguments = CommandLine.arguments
guard arguments.count == 5, arguments.dropFirst().allSatisfy({ $0.hasPrefix("/") }) else {
    fputs("Expected bundle, fixture ready, launch receipt and stop receipt paths\n", stderr)
    exit(64)
}
let bundleURL = URL(fileURLWithPath: arguments[1]).standardizedFileURL
let readyURL = URL(fileURLWithPath: arguments[2]).standardizedFileURL
let launchReceiptURL = URL(fileURLWithPath: arguments[3]).standardizedFileURL
let stopReceiptURL = URL(fileURLWithPath: arguments[4]).standardizedFileURL
let directory = bundleURL.deletingLastPathComponent()
let files = FileManager.default
guard bundleURL.pathExtension == "app",
      [bundleURL, readyURL, launchReceiptURL, stopReceiptURL].allSatisfy({
          $0.resolvingSymlinksInPath() == $0
      }),
      [readyURL, launchReceiptURL, stopReceiptURL].allSatisfy({
          $0.deletingLastPathComponent() == directory && !files.fileExists(atPath: $0.path)
      }),
      Set([readyURL.path, launchReceiptURL.path, stopReceiptURL.path]).count == 3,
      let bundle = Bundle(url: bundleURL),
      let bundleIdentifier = bundle.bundleIdentifier,
      bundleIdentifier == "org.otzaria.identitycontrol",
      let executableURL = bundle.executableURL?.standardizedFileURL,
      files.isExecutableFile(atPath: executableURL.path) else {
    fputs("Initial launch requires the owned fixture bundle and fresh sibling receipts\n", stderr)
    exit(64)
}

let ownerApplication = NSApplication.shared
_ = ownerApplication.setActivationPolicy(.accessory)
let ownerPid = ProcessInfo.processInfo.processIdentifier
let sessionToken = UUID().uuidString
let configuration: [String: Any] = [
    "createsNewApplicationInstance": true, "allowsRunningApplicationSubstitution": false,
    "hides": false, "hidesOthers": false, "activates": true,
    "addsToRecentItems": false, "promptsUserIfNeeded": false, "arguments": [readyURL.path]
]
var retainedApplication: NSRunningApplication?
var identity: [String: Any] = [:]
var identityEstablished = false
var primaryError: [String: Any]?
var cleanupErrors: [String] = []
var identityChecks: [[String: Any]] = []
var targetStateBeforeCleanup: [String: Any] = [:]
var terminateReturnValue: Bool?
var forceTerminateReturnValue: Bool?
var launchPending = false
var launchReceiptWritten = false
var launchObserved = false
var stopRequested = false
var stopReason = ""
var cleanupStarted = false
var finished = false
var cleanupTimer: Timer?

func nullableBool(_ value: Bool?) -> Any {
    if let value = value { return value }
    return NSNull()
}

func recordError(_ stage: String, _ message: String, cleanup: Bool = false,
                 nativeError: NSError? = nil) {
    var details: [String: Any] = [
        "stage": stage, "message": message, "atMs": Date().timeIntervalSince1970 * 1000
    ]
    if let nativeError = nativeError {
        details["domain"] = nativeError.domain
        details["code"] = nativeError.code
        details["description"] = nativeError.localizedDescription
    }
    if primaryError == nil { primaryError = details }
    if cleanup { cleanupErrors.append("\(stage): \(message)") }
    if let data = try? JSONSerialization.data(withJSONObject: details, options: [.sortedKeys]) {
        fputs(String(decoding: data, as: UTF8.self) + "\n", stderr)
    }
}

func snapshot(_ application: NSRunningApplication) -> [String: Any] {
    var launchMs: Any = NSNull()
    if let date = application.launchDate { launchMs = date.timeIntervalSince1970 * 1000 }
    return [
        "pid": application.processIdentifier, "executable": application.executableURL?.path ?? "unavailable",
        "bundleURL": application.bundleURL?.path ?? "unavailable",
        "bundleIdentifier": application.bundleIdentifier ?? "unavailable",
        "launchMs": launchMs,
        "launchDateAvailability": application.launchDate == nil ? "unavailable" : "available",
        "isTerminated": application.isTerminated, "isFinishedLaunching": application.isFinishedLaunching,
        "activationPolicy": application.activationPolicy.rawValue
    ]
}

func verifyIdentity(_ stage: String) -> Bool {
    guard let application = retainedApplication else { return false }
    var check = snapshot(application)
    check["stage"] = stage
    let current = NSRunningApplication(processIdentifier: application.processIdentifier)
    let matches = !application.isTerminated
        && application.bundleURL?.standardizedFileURL == bundleURL
        && application.executableURL?.standardizedFileURL == executableURL
        && application.bundleIdentifier == bundleIdentifier
        && current.map({ application.isEqual($0)
            && $0.executableURL?.standardizedFileURL == executableURL
            && $0.bundleURL?.standardizedFileURL == bundleURL }) == true
    check["sameApplication"] = matches
    identityChecks.append(check)
    return matches
}

func commonReceipt() -> [String: Any] {
    var result = identity
    result["schemaVersion"] = 1
    result["scope"] = "Owned fixture LaunchServices launch and cleanup; not an app quiet measurement"
    result["source"] = "NSWorkspace.openApplication"
    result["ownerPid"] = ownerPid
    result["sessionToken"] = sessionToken
    result["configuration"] = configuration
    result["identityMethod"] = "Retained NSWorkspace completion object and NSRunningApplication.isEqual"
    return result
}

func saveReceipt(_ result: [String: Any], at url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    guard data.count <= 65536 else {
        throw NSError(domain: "OwnedLaunchControl", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "The ownership receipt exceeds 64 KiB"])
    }
    try data.write(to: url, options: .atomic)
}

func recordFixtureLaunchId() {
    guard files.fileExists(atPath: readyURL.path), let pid = identity["pid"] as? Int32 else { return }
    do {
        let size = (try files.attributesOfItem(atPath: readyURL.path)[.size] as? NSNumber)?.intValue ?? 65537
        guard size <= 65536,
              let value = try JSONSerialization.jsonObject(with: Data(contentsOf: readyURL)) as? [String: Any],
              (value["pid"] as? NSNumber)?.int32Value == pid,
              let launchId = value["launchId"] as? String, UUID(uuidString: launchId) != nil else {
            throw NSError(domain: "OwnedLaunchControl", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Fixture ready does not identify the retained launch"])
        }
        identity["launchId"] = launchId
    } catch {
        recordError("fixtureReady", String(describing: error), cleanup: true)
    }
}

func finish() {
    guard !finished else { return }
    finished = true
    cleanupTimer?.invalidate()
    let exited = retainedApplication?.isTerminated == true
    if !exited && primaryError == nil {
        recordError("cleanup", "The retained target has not exited", cleanup: true)
    }
    recordFixtureLaunchId()
    var result = commonReceipt()
    let passed = primaryError == nil && cleanupErrors.isEmpty && exited && launchReceiptWritten
    result["status"] = passed ? "passed" : "failed"
    result["targetExited"] = exited
    result["stopReason"] = stopReason
    result["launchReceiptWritten"] = launchReceiptWritten
    result["targetStateBeforeCleanup"] = targetStateBeforeCleanup
    result["identityChecks"] = identityChecks
    result["terminateReturnValue"] = nullableBool(terminateReturnValue)
    result["forceTerminateReturnValue"] = nullableBool(forceTerminateReturnValue)
    result["cleanupErrors"] = cleanupErrors
    result["finishedAtMs"] = Date().timeIntervalSince1970 * 1000
    if let error = primaryError { result["error"] = error } else { result["error"] = NSNull() }
    do { try saveReceipt(result, at: stopReceiptURL) }
    catch {
        recordError("stopReceipt", String(describing: error), cleanup: true)
        exit(1)
    }
    exit(passed ? 0 : 1)
}

func cleanUpRetainedTarget() {
    guard !finished, !cleanupStarted else { return }
    guard let application = retainedApplication else {
        if !launchPending { finish() }
        return
    }
    cleanupStarted = true
    targetStateBeforeCleanup = snapshot(application)
    if application.isTerminated { finish(); return }
    guard identityEstablished, verifyIdentity("beforeTerminate") else {
        recordError("cleanupIdentity", "The completion object no longer identifies the owned target", cleanup: true)
        finish()
        return
    }
    terminateReturnValue = application.terminate()
    if terminateReturnValue != true {
        recordError("terminate", "The retained target refused normal termination", cleanup: true)
    }
    let deadline = ProcessInfo.processInfo.systemUptime + 5
    var forceDeadline: TimeInterval?
    let timer = Timer(timeInterval: 0.05, repeats: true) { timer in
        if application.isTerminated { timer.invalidate(); finish(); return }
        if let forceDeadline = forceDeadline {
            if ProcessInfo.processInfo.systemUptime >= forceDeadline {
                recordError("forceTerminate", "The retained target did not exit within two seconds", cleanup: true)
                timer.invalidate()
                finish()
            }
            return
        }
        if ProcessInfo.processInfo.systemUptime >= deadline {
            recordError("terminate", "Normal target cleanup exceeded five seconds", cleanup: true)
            guard verifyIdentity("beforeForceTerminate") else {
                recordError("cleanupIdentity", "Identity changed before forced owned-target cleanup", cleanup: true)
                timer.invalidate()
                finish()
                return
            }
            forceTerminateReturnValue = application.forceTerminate()
            if forceTerminateReturnValue != true {
                recordError("forceTerminate", "The retained target refused forced cleanup", cleanup: true)
            }
            forceDeadline = ProcessInfo.processInfo.systemUptime + 2
        }
    }
    cleanupTimer = timer
    RunLoop.main.add(timer, forMode: .common)
}

func requestStop(_ reason: String) {
    guard !finished else { return }
    if !stopRequested {
        stopRequested = true
        stopReason = reason
        if launchPending {
            // A late completion still belongs to us and must be cleaned up before exit.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if launchPending && !finished {
                    recordError("cleanup", "Launch completion never supplied an owned object", cleanup: true)
                    finish()
                }
            }
        }
    }
    cleanUpRetainedTarget()
}

func launchTarget() {
    let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        .filter { !$0.isTerminated && $0.bundleURL?.standardizedFileURL == bundleURL }
    guard existing.isEmpty else {
        recordError("launch", "An instance of the owned fixture was already running")
        requestStop("preexistingTarget")
        return
    }
    let options = NSWorkspace.OpenConfiguration()
    options.createsNewApplicationInstance = true
    options.allowsRunningApplicationSubstitution = false
    options.hides = false
    options.hidesOthers = false
    options.activates = true
    options.addsToRecentItems = false
    options.promptsUserIfNeeded = false
    options.arguments = [readyURL.path]
    launchPending = true
    NSWorkspace.shared.openApplication(at: bundleURL, configuration: options) { application, error in
        // AppKit invokes this completion on a concurrent queue.
        DispatchQueue.main.async {
            launchPending = false
            if let error = error {
                recordError("launch", "LaunchServices returned an error", nativeError: error as NSError)
            }
            if let application = application {
                retainedApplication = application
                if verifyIdentity("launchCompletion") {
                    identityEstablished = true
                    identity = snapshot(application)
                    identity["sameApplication"] = true
                } else {
                    recordError("launchIdentity", "The completion object does not identify the requested live fixture")
                }
            } else if error == nil {
                recordError("launch", "LaunchServices returned neither an application nor an error")
            }
            guard error == nil, identityEstablished else {
                requestStop("launchError")
                return
            }
            var result = commonReceipt()
            result["status"] = "launched"
            result["observedAtMs"] = Date().timeIntervalSince1970 * 1000
            do {
                try saveReceipt(result, at: launchReceiptURL)
                launchReceiptWritten = true
            } catch {
                recordError("launchReceipt", String(describing: error))
                requestStop("launchReceipt")
                return
            }
            if stopRequested { cleanUpRetainedTarget() }
        }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
        if launchPending && !finished {
            recordError("launch", "Initial LaunchServices launch exceeded 15 seconds")
            requestStop("launchTimeout")
        }
    }
}

let observer = NotificationCenter.default.addObserver(
    forName: NSApplication.didFinishLaunchingNotification, object: ownerApplication, queue: nil
) { _ in
    guard !launchObserved else { return }
    launchObserved = true
    DispatchQueue.main.async {
        guard Thread.isMainThread, ownerApplication.isRunning,
              ownerApplication.activationPolicy() == .accessory else {
            recordError("startup", "The ownership helper requires a running AppKit main loop")
            requestStop("startup")
            return
        }
        launchTarget()
        Thread.detachNewThread {
            let line = readLine()
            DispatchQueue.main.async {
                if let line = line, line != "stop" {
                    recordError("command", "The ownership helper accepts only stop or EOF")
                }
                requestStop(line == nil ? "EOF" : "stop")
            }
        }
    }
}
DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
    if !launchObserved {
        recordError("startup", "The ownership helper did not finish launching")
        requestStop("startupTimeout")
    }
}
DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
    if !finished {
        recordError("lifetime", "The diagnostic ownership lifetime exceeded 60 seconds")
        requestStop("lifetimeTimeout")
    }
}
ownerApplication.run()

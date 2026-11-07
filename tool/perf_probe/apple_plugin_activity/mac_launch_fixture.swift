import AppKit
import Foundation

// LaunchServices control of the SAME owned fixture bundle used by the direct
// control. This is not a fallback for Otzaria or evidence about its quiet run.
let arguments = CommandLine.arguments
guard arguments.count == 4 else { exit(64) }
let bundle = URL(fileURLWithPath: arguments[1]).standardizedFileURL
let receipt = URL(fileURLWithPath: arguments[3])
guard let executable = Bundle(url: bundle)?.executableURL else { exit(65) }
let application = NSApplication.shared
guard application.setActivationPolicy(.accessory) else { exit(65) }
var owned: NSRunningApplication?
var closing = false
var evidenceFailed = false

func write(_ values: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    fflush(stdout)
    do { try data.write(to: receipt, options: .atomic) }
    catch {
        evidenceFailed = true
        fputs("LaunchServices receipt failed: \(error)\n", stderr)
    }
}

func closeOwned(_ code: Int32 = 0) {
    if closing { return }
    closing = true
    guard let target = owned else { exit(code) }
    guard target.executableURL?.standardizedFileURL == executable.standardizedFileURL,
          let current = NSRunningApplication(processIdentifier: target.processIdentifier),
          target.isEqual(current) else {
        if target.isTerminated { exit(code) }
        fputs("Owned fixture identity changed; refusing replacement cleanup\n", stderr)
        exit(1)
    }
    _ = target.terminate()
    let deadline = ProcessInfo.processInfo.systemUptime + 5
    var forced = false
    func awaitExit() {
        if target.isTerminated {
            write(["stage": "closed", "pid": target.processIdentifier,
                   "sameApplication": true, "forced": forced, "terminated": true])
            exit(evidenceFailed ? 1 : code)
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - deadline
        if elapsed >= 0 && !forced { forced = true; _ = target.forceTerminate() }
        if elapsed >= 5 {
            write(["stage": "cleanupFailed", "pid": target.processIdentifier, "terminated": false])
            exit(1)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.025, execute: awaitExit)
    }
    awaitExit()
}

signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
term.setEventHandler { closeOwned(1) }
interrupt.setEventHandler { closeOwned(1) }
term.resume()
interrupt.resume()
let observer = NotificationCenter.default.addObserver(
    forName: NSApplication.didFinishLaunchingNotification, object: application, queue: nil
) { _ in
    DispatchQueue.main.async {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.allowsRunningApplicationSubstitution = false
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = false
        configuration.arguments = [arguments[2]]
        NSWorkspace.shared.openApplication(at: bundle, configuration: configuration) { target, error in
            DispatchQueue.main.async {
                guard let target = target, error == nil else {
                    fputs("LaunchServices failed: \(String(describing: error))\n", stderr)
                    exit(1)
                }
                owned = target
                guard target.bundleURL?.standardizedFileURL == bundle,
                      target.executableURL?.standardizedFileURL == executable.standardizedFileURL,
                      let launchDate = target.launchDate else {
                    closeOwned(1)
                    return
                }
                write(["stage": "launched", "pid": target.processIdentifier,
                       "launchMs": launchDate.timeIntervalSince1970 * 1000,
                       "executable": executable.path, "bundle": bundle.path,
                       "controllerEventLoopRunning": application.isRunning])
                DispatchQueue.global(qos: .userInitiated).async {
                    _ = readLine() // Closing the owner pipe ends only this retained app.
                    DispatchQueue.main.async { closeOwned() }
                }
            }
        }
    }
}
application.run()
withExtendedLifetime((observer, term, interrupt)) {}

import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 2 || arguments.count == 3 else { exit(64) }
let app = NSApplication.shared
let policyAccepted = app.setActivationPolicy(.regular)
let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 200, height: 100),
                      styleMask: [.titled, .closable], backing: .buffered, defer: false)
window.title = "Owned identity control"
var didFinishLaunchingObserved = false
var readyScheduled = false

func snapshot(_ stage: String) -> [String: Any] {
    let running = NSRunningApplication.current
    return [
        "stage": stage, "pid": ProcessInfo.processInfo.processIdentifier,
        "policyChangeAccepted": policyAccepted, "activationPolicy": app.activationPolicy().rawValue,
        "isRunning": app.isRunning, "isHidden": app.isHidden, "isActive": app.isActive,
        "didFinishLaunchingObserved": didFinishLaunchingObserved,
        "mainThread": Thread.isMainThread, "screenCount": NSScreen.screens.count,
        "windowCanHide": window.canHide, "windowVisible": window.isVisible,
        "runningApplicationPolicy": running.activationPolicy.rawValue,
        "isFinishedLaunching": running.isFinishedLaunching, "isTerminated": running.isTerminated,
        "bundleIdentifier": running.bundleIdentifier ?? "unavailable",
        "bundleURL": running.bundleURL?.path ?? "unavailable",
        "atMs": Date().timeIntervalSince1970 * 1000
    ]
}

func record(_ stage: String, path: String? = nil) {
    let data = try! JSONSerialization.data(withJSONObject: snapshot(stage), options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    fflush(stdout)
    if let path = path { try! data.write(to: URL(fileURLWithPath: path), options: .atomic) }
}

let launchObserver = NotificationCenter.default.addObserver(
    forName: NSApplication.didFinishLaunchingNotification, object: app, queue: nil
) { _ in
    didFinishLaunchingObserved = true
    record("didFinishLaunching")
    guard !readyScheduled else { return }
    readyScheduled = true
    DispatchQueue.main.async {
        guard Thread.isMainThread, app.isRunning, app.activationPolicy() == .regular,
              NSRunningApplication.current.isFinishedLaunching, !NSScreen.screens.isEmpty else {
            record("startupFailed", path: arguments[1])
            exit(65)
        }
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        record("ready", path: arguments[1])
        if arguments.count == 3 {
            DispatchQueue.main.async {
                record("beforeSelfHide")
                app.hide(nil)
                record("afterSelfHide")
            }
        }
    }
}
let hideObserver = NotificationCenter.default.addObserver(
    forName: NSApplication.didHideNotification, object: app, queue: nil
) { _ in
    record("didHide", path: arguments.count == 3 ? arguments[2] : nil)
}

DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
    if !readyScheduled {
        record("startupFailed", path: arguments[1])
        exit(65)
    }
}
app.run()

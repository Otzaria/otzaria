import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 2 || arguments.count == 3 else { exit(64) }
let app = NSApplication.shared
let policyAccepted = app.setActivationPolicy(.regular)
let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 200, height: 100),
                      styleMask: [.titled, .closable], backing: .buffered, defer: false)
window.title = "Owned identity control"

func snapshot(_ stage: String) -> [String: Any] {
    let running = NSRunningApplication.current
    return [
        "stage": stage, "pid": ProcessInfo.processInfo.processIdentifier,
        "policyChangeAccepted": policyAccepted, "activationPolicy": app.activationPolicy().rawValue,
        "isRunning": app.isRunning, "isHidden": app.isHidden, "isActive": app.isActive,
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
) { _ in record("didFinishLaunching") }
let hideObserver = NotificationCenter.default.addObserver(
    forName: NSApplication.didHideNotification, object: app, queue: nil
) { _ in
    record("didHide", path: arguments.count == 3 ? arguments[2] : nil)
}

window.makeKeyAndOrderFront(nil)
app.finishLaunching()
app.activate(ignoringOtherApps: true)
record("ready", path: arguments[1])
if arguments.count == 3 {
    DispatchQueue.main.async {
        record("beforeSelfHide")
        app.hide(nil)
        record("afterSelfHide")
    }
}
app.run()

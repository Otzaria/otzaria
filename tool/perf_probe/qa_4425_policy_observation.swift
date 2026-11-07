import AppKit
import Foundation
import Darwin

let application = NSApplication.shared
func emit(_ stage: String, _ extra: [String: Any] = [:]) {
    var value = extra
    value["stage"] = stage
    value["pid"] = ProcessInfo.processInfo.processIdentifier
    value["mainThread"] = Thread.isMainThread
    value["observedAtMs"] = Date().timeIntervalSince1970 * 1000
    let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    fflush(stdout)
}
func state() -> [String: Any] {
    [
        "activationPolicy": application.activationPolicy().rawValue,
        "isRunning": application.isRunning,
        "isActive": application.isActive,
        "isHidden": application.isHidden
    ]
}
emit("before-request", ["state": state()])
let first = application.setActivationPolicy(.prohibited)
emit("first-request", ["returned": first, "state": state()])
let repeated = application.setActivationPolicy(.prohibited)
emit("repeated-request", ["returned": repeated, "state": state()])
let observer = NotificationCenter.default.addObserver(
    forName: NSApplication.didFinishLaunchingNotification, object: application, queue: nil
) { _ in
    emit("did-finish-launching", ["state": state()])
    DispatchQueue.main.async {
        emit("event-loop-callback", ["state": state()])
        let requested = application.setActivationPolicy(.prohibited)
        emit("request-in-event-loop", ["returned": requested, "state": state()])
        let repeatedInLoop = application.setActivationPolicy(.prohibited)
        emit("repeat-in-event-loop", ["returned": repeatedInLoop, "state": state()])
        emit("owned-helper-terminating", ["state": state()])
        application.terminate(nil)
    }
}
DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 8) {
    emit("event-loop-deadline", ["seconds": 8])
    exit(124)
}
application.run()
withExtendedLifetime(observer) {}
emit("event-loop-returned", ["state": state()])

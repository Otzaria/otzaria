import AppKit
import Foundation

// External app control only. Never looks up a WKWebView or a WebContent PID.
let arguments = CommandLine.arguments
guard arguments.count == 3, let pid = Int32(arguments[2]),
      let app = NSRunningApplication(processIdentifier: pid),
      let launched = app.launchDate, let executable = app.executableURL else {
    fputs("No public running-application identity for the supplied PID\n", stderr)
    exit(1)
}
let action = arguments[1]
if action == "hide" {
    guard app.hide() else { exit(2) }
} else if action == "activate" {
    _ = app.unhide()
    guard app.activate(options: [.activateIgnoringOtherApps]) else { exit(3) }
} else if action != "info" {
    exit(4)
}
let deadline = ProcessInfo.processInfo.systemUptime + 5
while action != "info" && ProcessInfo.processInfo.systemUptime < deadline {
    if action == "hide" && app.isHidden { break }
    if action == "activate" && app.isActive && !app.isHidden { break }
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.025))
}
guard !app.isTerminated,
      action != "hide" || app.isHidden,
      action != "activate" || (app.isActive && !app.isHidden) else { exit(5) }
let observation: [String: Any] = [
    "pid": pid, "launchMs": launched.timeIntervalSince1970 * 1000,
    "executable": executable.path, "isHidden": app.isHidden,
    "isActive": app.isActive, "action": action,
    "observedAtMs": Date().timeIntervalSince1970 * 1000,
    "source": "NSRunningApplication public API"
]
let data = try JSONSerialization.data(withJSONObject: observation, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))

import AppKit
import Foundation

func fail(_ stage: String, _ reason: String, _ code: Int32 = 1,
          _ details: [String: Any] = [:]) -> Never {
    var message = details
    message["stage"] = stage
    message["error"] = reason
    let data = try! JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])
    fputs(String(decoding: data, as: UTF8.self) + "\n", stderr)
    exit(code)
}

let arguments = CommandLine.arguments
guard arguments.count == 2, let pid = Int32(arguments[1]), pid > 0 else {
    fail("arguments", "Expected one positive application PID", 64)
}
guard let app = NSRunningApplication(processIdentifier: pid) else {
    fail("application", "No running application for PID \(pid)")
}
guard let executable = app.executableURL else {
    fail("executable", "No public executable URL for PID \(pid)")
}
let controllerApplication = NSApplication.shared
guard controllerApplication.setActivationPolicy(.prohibited) else {
    fail("controller", "Unable to initialize the non-activating AppKit controller")
}
let sessionToken = UUID().uuidString
var expectedSequence = 1

func applicationState() -> [String: Any] {
    var result: [String: Any] = [
        "activationPolicy": app.activationPolicy.rawValue,
        "isFinishedLaunching": app.isFinishedLaunching, "isTerminated": app.isTerminated,
        "isHidden": app.isHidden, "isActive": app.isActive,
        "bundleIdentifier": app.bundleIdentifier ?? "unavailable",
        "bundleURL": app.bundleURL?.path ?? "unavailable",
        "controllerAppKitInitialized": NSApp != nil
    ]
    if let controllerApplication = NSApp {
        result["controllerActivationPolicy"] = controllerApplication.activationPolicy().rawValue
        result["controllerEventLoopRunning"] = controllerApplication.isRunning
    }
    return result
}

func verifyIdentity() {
    guard !app.isTerminated else {
        fail("identity", "The retained application terminated", 1, ["applicationState": applicationState()])
    }
    guard let current = NSRunningApplication(processIdentifier: pid) else {
        fail("identity", "No current running application for the retained PID")
    }
    guard app.isEqual(current) else { fail("identity", "The retained application was replaced") }
    guard let currentExecutable = current.executableURL else {
        fail("identity", "The current application has no public executable URL")
    }
    guard currentExecutable == executable else { fail("identity", "The executable URL changed") }
}

// readLine runs on a background thread. AppKit's main loop remains live,
// with no target query, command or scheduled probe timer between requests.
func handle(_ line: String, completed: @escaping () -> Void) {
    guard controllerApplication.isRunning else { fail("controller", "The AppKit event loop is stopped") }
    guard let data = line.data(using: .utf8),
          let value = try? JSONSerialization.jsonObject(with: data),
          let command = value as? [String: Any],
          let sequence = command["sequence"] as? Int, sequence == expectedSequence,
          let action = command["action"] as? String,
          ["info", "hide", "activate"].contains(action) else {
        fail("command", "Invalid command or sequence", 64)
    }
    verifyIdentity()
    let beforeAction = applicationState()
    let deadline = ProcessInfo.processInfo.systemUptime + 5
    var accepted: Any = NSNull()
    if action == "hide" {
        let hidden = app.hide()
        accepted = hidden
        guard hidden else {
            fail("hide", "The application refused hide", 2, [
                "pid": pid, "controllerPid": ProcessInfo.processInfo.processIdentifier,
                "sessionToken": sessionToken, "sequence": sequence, "returnValue": false,
                "beforeAction": beforeAction, "applicationState": applicationState()
            ])
        }
    } else if action == "activate" {
        _ = app.unhide()
        let activated = app.activate(options: [.activateIgnoringOtherApps])
        accepted = activated
        guard activated else { fail("activate", "The application refused activation", 3) }
    }
    func acknowledge() {
        verifyIdentity()
        guard action == "info" || ProcessInfo.processInfo.systemUptime <= deadline else {
            fail("acknowledgement", "The native action exceeded its five-second bound", 5,
                 ["beforeAction": beforeAction, "applicationState": applicationState()])
        }
        let acknowledged = action == "info" || (action == "hide" && app.isHidden) ||
            (action == "activate" && app.isActive && !app.isHidden)
        if !acknowledged {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                fail("acknowledgement", "The application did not acknowledge \(action)", 5,
                     ["beforeAction": beforeAction, "applicationState": applicationState()])
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.025, execute: acknowledge)
            return
        }
        let launchDate = app.launchDate
        var launchMs: Any = NSNull()
        if let launchDate = launchDate { launchMs = launchDate.timeIntervalSince1970 * 1000 }
        let observation: [String: Any] = [
            "pid": pid, "controllerPid": ProcessInfo.processInfo.processIdentifier,
            "sessionToken": sessionToken, "sequence": sequence, "action": action, "returnValue": accepted,
            "sameApplication": true, "identityMethod": "NSRunningApplication.isEqual",
            "launchMs": launchMs,
            "launchDateAvailability": launchDate == nil ? "unavailable" : "available",
            "executable": executable.path, "isHidden": app.isHidden, "isActive": app.isActive,
            "beforeAction": beforeAction, "applicationState": applicationState(),
            "observedAtMs": Date().timeIntervalSince1970 * 1000,
            "source": "NSRunningApplication public API"
        ]
        let result = try! JSONSerialization.data(withJSONObject: observation, options: [.sortedKeys])
        print(String(decoding: result, as: UTF8.self))
        fflush(stdout)
        expectedSequence += 1
        completed()
    }
    acknowledge()
}

let launchObserver = NotificationCenter.default.addObserver(
    forName: NSApplication.didFinishLaunchingNotification, object: controllerApplication, queue: nil
) { _ in
    DispatchQueue.main.async {
        guard controllerApplication.isRunning else { fail("controller", "No running AppKit event loop") }
        DispatchQueue.global(qos: .userInitiated).async {
            while let line = readLine() {
                let finished = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { handle(line) { finished.signal() } }
                finished.wait()
            }
            DispatchQueue.main.async { controllerApplication.terminate(nil) }
        }
    }
}
controllerApplication.run()
withExtendedLifetime(launchObserver) {}

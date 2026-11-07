import AppKit
import Foundation
import ApplicationServices

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

var retainedPSN = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: 0)
let processSerialLookupStatus = OQGetProcessForPID(pid, &retainedPSN)
guard processSerialLookupStatus == noErr else {
    fail("process-identity", "The target has no process serial number", 1, [
        "pid": pid, "nativeStatus": Int(processSerialLookupStatus)
    ])
}

let controllerApplication = NSApplication.shared
let initialControllerPolicy = controllerApplication.activationPolicy()
let controllerPolicyChangeAccepted = controllerApplication.setActivationPolicy(.prohibited)
// A controller that is already prohibited can decline an unnecessary change.
// The effective policy and inactive state, rather than a transition, are required.
guard controllerApplication.activationPolicy() == .prohibited,
      !controllerApplication.isActive else {
    fail("controller", "Unable to initialize the non-activating AppKit controller", 1, [
        "initialActivationPolicy": initialControllerPolicy.rawValue,
        "policyChangeAccepted": controllerPolicyChangeAccepted,
        "activationPolicy": controllerApplication.activationPolicy().rawValue,
        "isActive": controllerApplication.isActive
    ])
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
        "controllerAppKitInitialized": NSApp != nil,
        "processSerialHigh": retainedPSN.highLongOfPSN,
        "processSerialLow": retainedPSN.lowLongOfPSN,
        "processSerialLookupStatus": Int(processSerialLookupStatus)
    ]
    if let controllerApplication = NSApp {
        result["controllerInitialActivationPolicy"] = initialControllerPolicy.rawValue
        result["controllerPolicyChangeAccepted"] = controllerPolicyChangeAccepted
        result["controllerActivationPolicy"] = controllerApplication.activationPolicy().rawValue
        result["controllerIsActive"] = controllerApplication.isActive
        result["controllerEventLoopRunning"] = controllerApplication.isRunning
    }
    return result
}

@discardableResult
func verifyIdentity() -> [String: Any] {
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

    var serialPid: pid_t = 0
    let serialPidStatus = OQGetProcessPID(&retainedPSN, &serialPid)
    guard serialPidStatus == noErr, serialPid == pid else {
        fail("process-identity", "The retained process serial number belongs to another or dead process", 1, [
            "pid": pid, "serialPid": serialPid, "nativeStatus": Int(serialPidStatus),
            "processSerialHigh": retainedPSN.highLongOfPSN, "processSerialLow": retainedPSN.lowLongOfPSN
        ])
    }
    var currentPSN = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: 0)
    let currentSerialStatus = OQGetProcessForPID(pid, &currentPSN)
    var sameSerial = Int32(0)
    let serialComparisonStatus = OQSameProcess(&retainedPSN, &currentPSN, &sameSerial)
    guard currentSerialStatus == noErr, serialComparisonStatus == noErr, (sameSerial == 1) else {
        fail("process-identity", "The native process serial identity changed", 1, [
            "pid": pid, "lookupStatus": Int(currentSerialStatus),
            "comparisonStatus": Int(serialComparisonStatus), "sameSerial": (sameSerial == 1)
        ])
    }
    return [
        "pid": serialPid, "pidLookupStatus": Int(serialPidStatus),
        "serialLookupStatus": Int(currentSerialStatus),
        "serialComparisonStatus": Int(serialComparisonStatus), "sameProcess": (sameSerial == 1),
        "high": retainedPSN.highLongOfPSN, "low": retainedPSN.lowLongOfPSN
    ]
}

// readLine runs on a background thread. AppKit's main loop remains live,
// with no target query, command or scheduled probe timer between requests.
func handle(_ line: String, completed: @escaping () -> Void) {
    guard controllerApplication.isRunning else { fail("controller", "The AppKit event loop is stopped") }
    guard controllerApplication.activationPolicy() == .prohibited,
          !controllerApplication.isActive else {
        fail("controller", "The AppKit controller is no longer non-activating", 1,
             ["applicationState": applicationState()])
    }
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
    var nativeActionAPI = "NSRunningApplication identity"
    var nativeActionStatus: Any = NSNull()
    if action == "hide" {
        // This public legacy API is called through the ordinary C SDK bridge.
        // A native noErr result and a real hidden acknowledgement are both required.
        nativeActionAPI = "ApplicationServices.ShowHideProcess"
        let hideStatus = OQShowHideProcess(&retainedPSN, 0)
        nativeActionStatus = Int(hideStatus)
        let hidden = hideStatus == noErr
        accepted = hidden
        guard hidden else {
            fail("hide", "The application refused hide", 2, [
                "pid": pid, "controllerPid": ProcessInfo.processInfo.processIdentifier,
                "sessionToken": sessionToken, "sequence": sequence, "returnValue": false,
                "nativeActionAPI": nativeActionAPI, "nativeActionStatus": nativeActionStatus,
                "beforeAction": beforeAction, "applicationState": applicationState()
            ])
        }
    } else if action == "activate" {
        nativeActionAPI = "NSRunningApplication.unhide+activate"
        _ = app.unhide()
        let activated = app.activate(options: [.activateIgnoringOtherApps])
        accepted = activated
        guard activated else { fail("activate", "The application refused activation", 3) }
    }
    func acknowledge() {
        let processIdentity = verifyIdentity()
        guard action == "info" || ProcessInfo.processInfo.systemUptime <= deadline else {
            fail("acknowledgement", "The native action exceeded its five-second bound", 5,
                 ["beforeAction": beforeAction, "applicationState": applicationState(),
                  "nativeActionAPI": nativeActionAPI, "nativeActionStatus": nativeActionStatus])
        }
        let acknowledged = action == "info" || (action == "hide" && app.isHidden) ||
            (action == "activate" && app.isActive && !app.isHidden)
        if !acknowledged {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                fail("acknowledgement", "The application did not acknowledge \(action)", 5,
                     ["beforeAction": beforeAction, "applicationState": applicationState(),
                      "nativeActionAPI": nativeActionAPI, "nativeActionStatus": nativeActionStatus])
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
            "processIdentity": processIdentity,
            "launchMs": launchMs,
            "launchDateAvailability": launchDate == nil ? "unavailable" : "available",
            "executable": executable.path, "isHidden": app.isHidden, "isActive": app.isActive,
            "beforeAction": beforeAction, "applicationState": applicationState(),
            "observedAtMs": Date().timeIntervalSince1970 * 1000,
            "source": "NSRunningApplication identity and public ApplicationServices action",
            "nativeActionAPI": nativeActionAPI, "nativeActionStatus": nativeActionStatus
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

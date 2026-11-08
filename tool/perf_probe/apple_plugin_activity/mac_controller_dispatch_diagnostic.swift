// Diagnostic-only tail, compiled after the production controller's retained
// identity and snapshot functions. It is never selected by the actual-app run.
// The blocking stdin reader stays on a worker. Each boundary returns to the
// real NSApplication event loop while waiting for activation or acknowledgement.

#if ACTIVE_CONTROLLER
let diagnosticRequiresActive = true
let diagnosticPolicy: NSApplication.ActivationPolicy = .regular
#else
let diagnosticRequiresActive = false
let diagnosticPolicy: NSApplication.ActivationPolicy = .accessory
#endif

let diagnosticApplication = NSApplication.shared
let diagnosticPolicyAccepted = diagnosticApplication.setActivationPolicy(diagnosticPolicy)
var diagnosticLaunchObserved = false
var diagnosticMainQueueTurnDelivered = false
var diagnosticCommandInFlight = false
var diagnosticActiveBeforeHide = false

func diagnosticRecord(_ details: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: details, options: [.sortedKeys])
    fputs(String(decoding: data, as: UTF8.self) + "\n", stderr)
}

func diagnosticWait(_ stage: String, condition: @escaping () -> Bool,
                    then continuation: @escaping () -> Void) {
    let deadline = ProcessInfo.processInfo.systemUptime + 5
    let timer = Timer(timeInterval: 0.025, repeats: true) { timer in
        guard Thread.isMainThread else { fail("dispatch", "Boundary delivered off the main thread", 65) }
        verifyIdentity()
        if condition() {
            timer.invalidate()
            continuation()
        } else if ProcessInfo.processInfo.systemUptime >= deadline {
            timer.invalidate()
            fail(stage, "The application did not acknowledge \(stage)", 5,
                 ["applicationState": applicationState()])
        }
    }
    RunLoop.main.add(timer, forMode: .common)
}

func diagnosticReply(_ action: String, sequence: Int, beforeAction: [String: Any]) {
    verifyIdentity()
    guard action != "hide" || app.isHidden,
          action != "activate" || (app.isActive && !app.isHidden) else {
        fail("acknowledgement", "The application did not acknowledge \(action)", 5,
             ["beforeAction": beforeAction, "applicationState": applicationState()])
    }
    let launchDate = app.launchDate
    var launchMs: Any = NSNull()
    if let launchDate = launchDate { launchMs = launchDate.timeIntervalSince1970 * 1000 }
    var observation: [String: Any] = [
        "pid": pid, "controllerPid": ProcessInfo.processInfo.processIdentifier,
        "sessionToken": sessionToken, "sequence": sequence, "action": action,
        "sameApplication": true, "identityMethod": "NSRunningApplication.isEqual",
        "launchMs": launchMs,
        "launchDateAvailability": launchDate == nil ? "unavailable" : "available",
        "executable": executable.path, "isHidden": app.isHidden, "isActive": app.isActive,
        "beforeAction": beforeAction, "applicationState": applicationState(),
        "observedAtMs": Date().timeIntervalSince1970 * 1000,
        "source": "NSRunningApplication public API",
        "mainQueueTurnDelivered": diagnosticMainQueueTurnDelivered,
        "controllerBoundaryMode": "asynchronous-main-dispatch"
    ]
    if action == "hide" {
        observation["hideReturnValue"] = true
        observation["controllerActiveBeforeHide"] = diagnosticActiveBeforeHide
    }
    let data = try! JSONSerialization.data(withJSONObject: observation, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    fflush(stdout)
    expectedSequence += 1
    diagnosticCommandInFlight = false
}

func diagnosticCommand(_ line: String) {
    guard Thread.isMainThread, diagnosticApplication.isRunning,
          diagnosticLaunchObserved, diagnosticMainQueueTurnDelivered,
          !diagnosticCommandInFlight else {
        fail("dispatch", "A command requires an idle, dispatching AppKit main loop", 65)
    }
    guard let data = line.data(using: .utf8),
          let value = try? JSONSerialization.jsonObject(with: data),
          let command = value as? [String: Any],
          let sequence = command["sequence"] as? Int, sequence == expectedSequence,
          let action = command["action"] as? String,
          ["info", "hide", "activate"].contains(action) else {
        fail("command", "Invalid command or sequence", 64)
    }
    diagnosticCommandInFlight = true
    verifyIdentity()
    let beforeAction = applicationState()
    let perform = {
        verifyIdentity()
        if action == "hide" {
            diagnosticActiveBeforeHide = diagnosticApplication.isActive
            guard !diagnosticRequiresActive || diagnosticActiveBeforeHide else {
                fail("controllerActivation", "The controller lost activation before hide", 66,
                     ["applicationState": applicationState()])
            }
            guard app.hide() else {
                fail("hide", "The application refused hide", 2, [
                    "pid": pid, "controllerPid": ProcessInfo.processInfo.processIdentifier,
                    "sessionToken": sessionToken, "sequence": sequence, "returnValue": false,
                    "controllerActiveBeforeHide": diagnosticActiveBeforeHide,
                    "beforeAction": beforeAction, "applicationState": applicationState()
                ])
            }
            diagnosticWait("hide", condition: { app.isHidden }) {
                diagnosticReply(action, sequence: sequence, beforeAction: beforeAction)
            }
        } else if action == "activate" {
            _ = app.unhide()
            guard app.activate(options: [.activateIgnoringOtherApps]) else {
                fail("activate", "The application refused activation", 3)
            }
            diagnosticWait("activate", condition: { app.isActive && !app.isHidden }) {
                diagnosticReply(action, sequence: sequence, beforeAction: beforeAction)
            }
        } else {
            diagnosticReply(action, sequence: sequence, beforeAction: beforeAction)
        }
    }
    if action == "hide" && diagnosticRequiresActive {
        diagnosticApplication.activate(ignoringOtherApps: true)
        diagnosticWait("controllerActivation", condition: { diagnosticApplication.isActive }) {
            diagnosticRecord([
                "stage": "controllerActivation", "applicationState": applicationState(),
                "controllerPid": ProcessInfo.processInfo.processIdentifier
            ])
            perform()
        }
    } else {
        perform()
    }
}

let diagnosticObserver = NotificationCenter.default.addObserver(
    forName: NSApplication.didFinishLaunchingNotification, object: diagnosticApplication, queue: nil
) { _ in
    guard !diagnosticLaunchObserved else { return }
    diagnosticLaunchObserved = true
    DispatchQueue.main.async {
        guard diagnosticApplication.isRunning, Thread.isMainThread,
              diagnosticApplication.activationPolicy() == diagnosticPolicy else { exit(65) }
        diagnosticRecord([
            "didFinishLaunchingObserved": diagnosticLaunchObserved,
            "isRunning": diagnosticApplication.isRunning, "mainThread": Thread.isMainThread,
            "policyAccepted": diagnosticPolicyAccepted,
            "activationPolicy": diagnosticApplication.activationPolicy().rawValue,
            "controllerBoundaryMode": "asynchronous-main-dispatch"
        ])
        // This next main-queue turn cannot execute inside a non-returning
        // main-queue serveController/readLine closure.
        DispatchQueue.main.async { diagnosticMainQueueTurnDelivered = true }
        Thread.detachNewThread {
            while let line = readLine() {
                DispatchQueue.main.async { diagnosticCommand(line) }
            }
            DispatchQueue.main.async {
                guard !diagnosticCommandInFlight else {
                    fail("command", "Input closed before a command was acknowledged", 64)
                }
                exit(0)
            }
        }
    }
}
DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
    if !diagnosticLaunchObserved { exit(65) }
}
diagnosticApplication.run()

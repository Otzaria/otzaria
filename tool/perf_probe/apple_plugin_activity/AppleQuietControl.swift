import Foundation
import XCTest

// Built into a separate temporary UI-test bundle, never into Otzaria.
// ControlConfig is generated with this run's local coordinator and nonce.
final class AppleQuietControl: XCTestCase {
    private func now() -> Double { Date().timeIntervalSince1970 * 1000 }

    private func post(_ endpoint: String, _ value: [String: Any]) throws -> [String: Any] {
        var request = URLRequest(url: URL(string: ControlConfig.url + "/" + endpoint)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("close", forHTTPHeaderField: "Connection")
        request.setValue(ControlConfig.token, forHTTPHeaderField: "X-Apple-Quiet-Token")
        request.httpBody = try JSONSerialization.data(withJSONObject: value)
        let session = URLSession(configuration: .ephemeral)
        let completed = DispatchSemaphore(value: 0)
        var received: Result<Data, Error>?
        session.dataTask(with: request) { data, response, error in
            defer { completed.signal() }
            if let error = error { received = .failure(error); return }
            guard (response as? HTTPURLResponse)?.statusCode == 200, let data = data else {
                received = .failure(NSError(domain: "quiet.coordinator", code: 1)); return
            }
            received = .success(data)
        }.resume()
        defer { session.invalidateAndCancel() }
        guard completed.wait(timeout: .now() + 35) == .success,
              let received = received else { throw NSError(domain: "quiet.timeout", code: 1) }
        return try JSONSerialization.jsonObject(with: received.get()) as! [String: Any]
    }

    func testHomeAndActivateExistingOtzariaProcess() throws {
        continueAfterFailure = false
        let controllerSession = UUID().uuidString
        _ = try post("control-ready", [
            "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
            "controllerSession": controllerSession
        ])
        let preparationDeadline = ProcessInfo.processInfo.systemUptime + 2400
        var measurementDeadline: TimeInterval?
        while ProcessInfo.processInfo.systemUptime < (measurementDeadline ?? preparationDeadline) {
            let requestMs = now()
            let requestMonotonic = ProcessInfo.processInfo.systemUptime
            let command = try post("control", ["controllerSession": controllerSession])
            let replyMs = now()
            if command["stop"] as? Bool == true { return }
            if let challenge = command["prepare"] as? String {
                guard command["controllerSession"] as? String == controllerSession else {
                    throw NSError(domain: "quiet.changedController", code: 1)
                }
                _ = try post("control-prepared", [
                    "controllerSession": controllerSession, "challenge": challenge
                ])
                if measurementDeadline == nil {
                    measurementDeadline = ProcessInfo.processInfo.systemUptime + 1800
                }
                continue
            }
            guard let job = command["jobId"] as? String else {
                Thread.sleep(forTimeInterval: 0.25) // Before any quiet interval.
                continue
            }
            let app = XCUIApplication(bundleIdentifier: ControlConfig.bundleIdentifier)
            let useHome = command["action"] as? String == "iosHome"
            var result: [String: Any] = [
                "jobId": job, "status": "failed", "controllerSession": controllerSession
            ]
            do {
                guard app.state == .runningForeground else {
                    throw NSError(domain: "quiet.notForeground", code: 1)
                }
                let remaining = command["remainingMs"] as! Double / 1000
                let endDeadline = requestMonotonic + remaining
                let requested = command["seconds"] as! Double
                if useHome {
                    result["homeRequestedMs"] = now()
                    XCUIDevice.shared.press(.home)
                    let transitionDeadline = ProcessInfo.processInfo.systemUptime + 15
                    while app.state != .runningBackground && app.state != .runningBackgroundSuspended {
                        guard ProcessInfo.processInfo.systemUptime < transitionDeadline else {
                            throw NSError(domain: "quiet.homeFailed", code: 1)
                        }
                        Thread.sleep(forTimeInterval: 0.05) // Still before quiet.
                    }
                }
                result["stateBeforeQuiet"] = app.state.rawValue
                result["stateBeforeQuietName"] = String(describing: app.state)
                let startMono = ProcessInfo.processInfo.systemUptime
                let duration = endDeadline - startMono
                guard duration >= requested else { throw NSError(domain: "quiet.lateHome", code: 1) }
                result["deviceQuietStartMs"] = now()
                // No HTTP, state query, accessibility query, app command, JS,
                // process listing or polling until this interval has ended.
                Thread.sleep(forTimeInterval: duration)
                result["deviceQuietEndMs"] = now()
                result["quietElapsedMs"] = (ProcessInfo.processInfo.systemUptime - startMono) * 1000
                result["stateAfterQuiet"] = app.state.rawValue
                result["stateAfterQuietName"] = String(describing: app.state)
                if useHome {
                    result["activateRequestedMs"] = now()
                    // activate() can launch a dead app. The host PID + app boot +
                    // document/controller identity checks must reject that case.
                    app.activate()
                    guard app.wait(for: .runningForeground, timeout: 15) else {
                        throw NSError(domain: "quiet.activateFailed", code: 1)
                    }
                    result["activatedMs"] = now()
                }
                result["status"] = "passed"
            } catch {
                result["error"] = String(describing: error)
            }
            result["controlClock"] = [
                "requestMs": requestMs, "replyMs": replyMs,
                "serverReceivedMs": command["serverReceivedMs"]!,
                "serverReplyMs": command["serverReplyMs"]!
            ]
            _ = try post("control-result", result)
            XCTAssertEqual(result["status"] as? String, "passed", String(describing: result))
        }
        XCTFail("The app did not complete within the controller deadline")
    }
}

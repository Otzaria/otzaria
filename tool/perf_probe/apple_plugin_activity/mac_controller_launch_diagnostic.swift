// Diagnostic-only prefix before the retained controller's argument parsing.
// Audit every owned bundle launch, including an extra LaunchServices instance
// that exits immediately because it did not receive the original PID argument.
let diagnosticControllerBundle = Bundle.main.bundleURL.standardizedFileURL
let diagnosticControllerLaunchId = UUID().uuidString
let diagnosticControllerLaunchDirectory = diagnosticControllerBundle.deletingLastPathComponent()
guard diagnosticControllerBundle.pathExtension == "app",
      Bundle.main.bundleIdentifier == "org.otzaria.dispatchcontroller" else { exit(64) }
let diagnosticControllerLaunch: [String: Any] = [
    "launchId": diagnosticControllerLaunchId,
    "pid": ProcessInfo.processInfo.processIdentifier,
    "bundleURL": diagnosticControllerBundle.path,
    "executable": Bundle.main.executableURL?.path ?? "unavailable",
    "arguments": CommandLine.arguments,
    "atMs": Date().timeIntervalSince1970 * 1000
]
do {
    let data = try JSONSerialization.data(withJSONObject: diagnosticControllerLaunch, options: [.sortedKeys])
    try data.write(to: diagnosticControllerLaunchDirectory.appendingPathComponent(
        "controller-launch-\(diagnosticControllerLaunchId).json"), options: .atomic)
} catch {
    fputs("Could not record owned controller launch: \(error)\n", stderr)
    exit(65)
}

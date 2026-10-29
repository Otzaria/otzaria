
import Cocoa
import FlutterMacOS

final class SpyMessenger: NSObject, FlutterBinaryMessenger {
  var handlers: [String: FlutterBinaryMessageHandler] = [:]
  func send(onChannel channel: String, message: Data?) {}
  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) { callback?(nil) }
  func setMessageHandlerOnChannel(_ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection {
    handlers[channel] = handler
    return 1
  }
  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
  func call(_ method: String) -> Any? {
    let codec = FlutterStandardMethodCodec.sharedInstance()
    let bytes = codec.encode(FlutterMethodCall(methodName: method, arguments: nil))
    var replyValue: Any?
    handlers["otzaria/multiwindow"]!(bytes) { reply in
      if let reply = reply { replyValue = codec.decodeEnvelope(reply) }
    }
    return replyValue
  }
}
final class SpyWindow: NSWindow {
  var fakeMask: NSWindow.StyleMask = [.titled]
  var outs = 0
  var fronts = 0
  var toggles = 0
  override var styleMask: NSWindow.StyleMask { get { fakeMask } set { fakeMask = newValue } }
  override func orderOut(_ sender: Any?) { outs += 1 }
  override func makeKeyAndOrderFront(_ sender: Any?) { fronts += 1 }
  override func toggleFullScreen(_ sender: Any?) { toggles += 1 }
  func reset() { outs = 0; fronts = 0; toggles = 0 }
}

/* RUNNER_SOURCE */

final class OtzariaViewWindows {
  static let shared = OtzariaViewWindows()
  var requests = 0
  var handlesReopen = false
  func requestReopen(fallback: @escaping () -> Void) -> Bool {
    requests += 1
    if handlesReopen {
      if !OtzariaWindowManager.shared.restoreLastClosedWindow() { fallback() }
      return true
    }
    return false
  }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let messenger = SpyMessenger()
let window = SpyWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled], backing: .buffered, defer: true)
let manager = OtzariaWindowManager.shared
manager.registerMainWindow(window, messenger: messenger)
let delegate = ProbeAppDelegate()
var failures: [String] = []
func check(_ condition: Bool, _ message: String) {
  if !condition { failures.append(message) }
}
func drain() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03)) }
func reset(fullscreen: Bool) {
  manager.showMainWindow()
  window.fakeMask = fullscreen ? [.titled, .fullScreen] : [.titled]
  window.reset()
  OtzariaViewWindows.shared.requests = 0
  OtzariaViewWindows.shared.handlesReopen = false
}
func close() { _ = messenger.call("closeSelf"); drain() }
func exitFullscreen() {
  window.fakeMask = [.titled]
  NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: window)
}
reset(fullscreen: false)
close()
check(window.outs == 1, "regular close hides")
check(messenger.call("restoreLastClosedWindow") as? Bool == true, "hidden main restores")
check(messenger.call("restoreLastClosedWindow") as? Bool == false, "visible main does not restore")
check(window.fronts == 1, "restore presents the main window once")

reset(fullscreen: true)
close()
close()
check(window.toggles == 1 && window.outs == 0, "fullscreen close waits, repeated close does not reverse the transition")
exitFullscreen()
check(window.outs == 1, "didExit hides once")
exitFullscreen()
check(window.outs == 1, "duplicate didExit does not hide twice")

for method in ["raiseSelf", "restoreLastClosedWindow"] {
  reset(fullscreen: true)
  close()
  let result = messenger.call(method)
  if method == "restoreLastClosedWindow" {
    check(result as? Bool == true, "pending close remains restorable")
  }
  exitFullscreen()
  check(window.fronts == 1 && window.outs == 0, "\(method) cancels pending hide")
  check(messenger.call("restoreLastClosedWindow") as? Bool == false, "\(method) leaves the main window logically visible")
}

reset(fullscreen: true)
close()
manager.showMainWindow()
NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: window)
exitFullscreen()
check(window.outs == 0 && window.toggles == 1, "direct show cancels both pending notifications")

reset(fullscreen: true)
close()
NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: window)
check(window.toggles == 2 && window.outs == 0, "close during entry retries after didEnter")
exitFullscreen()
check(window.outs == 1, "retry hides after exit")

for handlesReopen in [false, true] {
  reset(fullscreen: true)
  OtzariaViewWindows.shared.handlesReopen = handlesReopen
  close()
  let normalReopen = delegate.applicationShouldHandleReopen(app, hasVisibleWindows: true)
  exitFullscreen()
  check(!normalReopen && window.outs == 0 && window.fronts == 1, "Dock cancels pending hide, Dart=\(handlesReopen)")
  check(OtzariaViewWindows.shared.requests == 1, "Dock preserves Dart restore ordering")
}
reset(fullscreen: false)
let normalReopen = delegate.applicationShouldHandleReopen(app, hasVisibleWindows: true)
check(normalReopen && OtzariaViewWindows.shared.requests == 0, "Dock leaves visible windows to AppKit")

reset(fullscreen: false)
close()
let hiddenReopen = delegate.applicationShouldHandleReopen(app, hasVisibleWindows: false)
check(!hiddenReopen && window.fronts == 1, "Dock still restores hidden main")

reset(fullscreen: true)
close()
exitFullscreen()
check(window.outs == 1, "exit without an animation completes pending close")
_ = messenger.call("raiseSelf")
check(window.fronts == 1, "main remains usable after exit")

if failures.isEmpty {
  print("PASS native fullscreen close, raise, restore and Dock scenarios")
} else {
  for failure in failures { print("FAIL: \(failure)") }
  exit(1)
}

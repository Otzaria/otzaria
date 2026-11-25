import Darwin
import Flutter
import UIKit
import XCTest
@testable import Runner

/// These tests use real UIKit presentation and real filesystem/engine resources.
/// Delegate callbacks are controlled here; Files UI is tested by PdfFileExportUITests.
@MainActor
final class PdfFileExportTests: XCTestCase {
  private var cache: URL!
  private var window: UIWindow!
  private var originalWindow: UIWindow?
  private var presenter: UIViewController!
  private var coordinators: [PdfFileExportCoordinator] = []
  private var heldDismissals: [() -> Void] = []

  override func setUpWithError() throws {
    try super.setUpWithError()
    continueAfterFailure = false
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    originalWindow = scene.windows.first(where: { $0.isKeyWindow })
    presenter = UIViewController()
    window = UIWindow(windowScene: scene)
    window.rootViewController = presenter
    window.makeKeyAndVisible()
    cache = try PdfExportStaging.cachesDirectory().appendingPathComponent("PdfExportTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
  }

  override func tearDown() async throws {
    for coordinator in coordinators {
      if let identifier = coordinator.activeOperationID { coordinator.cancel(operationID: identifier) }
    }
    for completion in heldDismissals { completion() }
    heldDismissals.removeAll()
    for coordinator in coordinators {
      await waitUntil { coordinator.activeOperationID == nil }
    }
    coordinators.removeAll()
    window.isHidden = true
    window.rootViewController = nil
    window = nil
    presenter = nil
    originalWindow?.makeKeyAndVisible()
    originalWindow = nil
    if let cache = cache, FileManager.default.fileExists(atPath: cache.path) {
      try FileManager.default.removeItem(at: cache)
    }
    cache = nil
    try await super.tearDown()
  }

  func testStagingCleanupPreservesRootAndOtherOperations() throws {
    let first = try fixture()
    let second = try fixture()
    let source = try validate(first)
    XCTAssertEqual(try Data(contentsOf: first.url), first.bytes)
    XCTAssertNil(source.cleanup())
    XCTAssertNil(source.cleanup())
    XCTAssertFalse(exists(first.directory))
    XCTAssertTrue(exists(first.directory.deletingLastPathComponent()))
    XCTAssertEqual(try Data(contentsOf: second.url), second.bytes)
  }

  func testInvalidIdentitiesAndSiblingPathsAreNotAdopted() throws {
    let file = try fixture()
    for identifier in ["", "../outside", String(repeating: "a", count: 31), file.id.uppercased()] {
      XCTAssertThrowsError(try PdfExportStaging.validate(
        operationID: identifier, sourcePath: file.url.path, fileName: file.name, cachesDirectory: cache
      ))
    }
    for name in ["../outside.pdf", "a/b.pdf", "a\\b.pdf", "bad\0.pdf", "bad\n.pdf"] {
      XCTAssertThrowsError(try PdfExportStaging.validate(
        operationID: file.id, sourcePath: file.url.path, fileName: name, cachesDirectory: cache
      ))
    }
    let outside = cache.appendingPathComponent("outside.pdf")
    try file.bytes.write(to: outside)
    XCTAssertThrowsError(try PdfExportStaging.validate(
      operationID: file.id, sourcePath: outside.path, fileName: "outside.pdf", cachesDirectory: cache
    ))
    XCTAssertEqual(try Data(contentsOf: file.url), file.bytes)
    XCTAssertEqual(try Data(contentsOf: outside), file.bytes)

    // ICU's $ can match before a final line terminator. A real directory with
    // that suffix must not turn the 32-byte identifier contract into a prefix.
    for suffix in ["\n", "\r\n", "\u{0085}", "\u{2028}"] {
      let identifier = file.id + suffix
      let directory = file.directory.deletingLastPathComponent().appendingPathComponent(identifier)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
      let source = directory.appendingPathComponent(file.name)
      try file.bytes.write(to: source)
      XCTAssertThrowsError(try PdfExportStaging.validate(
        operationID: identifier, sourcePath: source.path, fileName: file.name, cachesDirectory: cache
      ))
      XCTAssertEqual(try Data(contentsOf: source), file.bytes)
    }
  }

  func testSymlinkAndHardlinkSourcesAreNotAdopted() throws {
    let file = try fixture()
    let outside = cache.appendingPathComponent("outside.pdf")
    try FileManager.default.moveItem(at: file.url, to: outside)
    try FileManager.default.createSymbolicLink(at: file.url, withDestinationURL: outside)
    XCTAssertThrowsError(try validate(file))
    XCTAssertEqual(try Data(contentsOf: outside), file.bytes)
    try FileManager.default.removeItem(at: file.url)
    try FileManager.default.linkItem(at: outside, to: file.url)
    XCTAssertThrowsError(try validate(file))
    XCTAssertEqual(try Data(contentsOf: outside), file.bytes)
  }

  func testFifoSourceIsRejectedWithoutWaitingForAWriter() async throws {
    let file = try fixture()
    try FileManager.default.removeItem(at: file.url)
    XCTAssertEqual(mkfifo(file.url.path, 0o600), 0)
    let cachesDirectory = try XCTUnwrap(cache)
    let finished = expectation(description: "FIFO validation returned")
    DispatchQueue.global().async {
      let staging = try? PdfExportStaging.validate(
        operationID: file.id, sourcePath: file.url.path, fileName: file.name,
        cachesDirectory: cachesDirectory
      )
      XCTAssertNil(staging)
      finished.fulfill()
    }
    await fulfillment(of: [finished], timeout: 5)
  }

  func testRootAndOperationSymlinksAreNotFollowed() throws {
    let file = try fixture()
    let moved = cache.appendingPathComponent("moved-operation")
    try FileManager.default.moveItem(at: file.directory, to: moved)
    try FileManager.default.createSymbolicLink(at: file.directory, withDestinationURL: moved)
    XCTAssertThrowsError(try validate(file))
    XCTAssertEqual(try Data(contentsOf: moved.appendingPathComponent(file.name)), file.bytes)
    try FileManager.default.removeItem(at: file.directory)
    try FileManager.default.moveItem(at: moved, to: file.directory)
    let root = file.directory.deletingLastPathComponent()
    let movedRoot = cache.appendingPathComponent("moved-root")
    try FileManager.default.moveItem(at: root, to: movedRoot)
    try FileManager.default.createSymbolicLink(at: root, withDestinationURL: movedRoot)
    XCTAssertThrowsError(try validate(file))
    XCTAssertEqual(try Data(contentsOf: movedRoot.appendingPathComponent(file.id).appendingPathComponent(file.name)), file.bytes)
  }

  func testReplacingOperationDirectoryDoesNotDeleteTheReplacement() throws {
    let file = try fixture()
    let staging = try validate(file)
    let original = cache.appendingPathComponent("original-operation")
    try FileManager.default.moveItem(at: file.directory, to: original)
    try FileManager.default.createDirectory(at: file.directory, withIntermediateDirectories: false)
    let replacement = Data("replacement must survive".utf8)
    try replacement.write(to: file.url)
    XCTAssertEqual(staging.cleanup(), "staging_cleanup_failed: operation_directory_replaced")
    XCTAssertEqual(try Data(contentsOf: file.url), replacement)
    XCTAssertEqual(try Data(contentsOf: original.appendingPathComponent(file.name)), file.bytes)
  }

  func testCleanupDoesNotRecursivelyRemoveUnexpectedChildren() throws {
    let file = try fixture()
    let staging = try validate(file)
    let extra = file.directory.appendingPathComponent("unowned.txt")
    try Data("preserve".utf8).write(to: extra)
    XCTAssertNotNil(staging.cleanup())
    XCTAssertTrue(exists(extra))
    XCTAssertFalse(exists(file.url))
  }

  func testReplacingRootRefusesCleanupSoDartCannotDeleteTheReplacement() throws {
    let file = try fixture()
    let staging = try validate(file)
    let root = file.directory.deletingLastPathComponent()
    let original = cache.appendingPathComponent("original-root")
    try FileManager.default.moveItem(at: root, to: original)
    try FileManager.default.createDirectory(at: file.directory, withIntermediateDirectories: true)
    let replacement = Data("new root must survive".utf8)
    try replacement.write(to: file.url)
    XCTAssertEqual(staging.cleanup(), "staging_cleanup_failed: root_replaced")
    XCTAssertEqual(try Data(contentsOf: file.url), replacement)
    XCTAssertEqual(try Data(contentsOf: original.appendingPathComponent(file.id).appendingPathComponent(file.name)), file.bytes)
  }

  func testMissingPresenterIsTerminalAndCleansOnlyItsOwnFile() throws {
    let file = try fixture()
    let other = try fixture()
    let coordinator = makeCoordinator(presenter: { nil })
    let replies = Replies()
    start(file, coordinator: coordinator, replies: replies)
    XCTAssertEqual(replies.values.count, 1)
    XCTAssertEqual(replies.values.first?["errorCode"] as? String, "presenter_unavailable")
    XCTAssertFalse(exists(file.directory))
    XCTAssertTrue(exists(other.url))
  }

  func testBusyPresenterRejectsExportWithoutDismissingExistingPresentation() async throws {
    let existing = UIViewController()
    var presented = false
    presenter.present(existing, animated: false) { presented = true }
    await waitUntil { presented }
    let file = try fixture()
    let coordinator = makeCoordinator()
    let replies = Replies()
    start(file, coordinator: coordinator, replies: replies)
    XCTAssertEqual(replies.values.count, 1)
    XCTAssertEqual(replies.values[0]["errorCode"] as? String, "presenter_unavailable")
    XCTAssertNil(coordinator.activeOperationID)
    XCTAssertFalse(exists(file.directory))
    XCTAssertTrue(presenter.presentedViewController === existing)
    var dismissed = false
    existing.dismiss(animated: false) { dismissed = true }
    await waitUntil { dismissed }
  }

  func testCancelAcknowledgementRetainsStagingUntilDismissalCompletion() async throws {
    let file = try fixture()
    let coordinator = makeCoordinator(holdDismissal: true)
    let replies = Replies()
    start(file, coordinator: coordinator, replies: replies)
    let picker = try await presentedPicker(coordinator)
    XCTAssertTrue(coordinator.cancel(operationID: file.id))
    XCTAssertTrue(coordinator.cancel(operationID: file.id))
    XCTAssertTrue(replies.values.isEmpty)
    XCTAssertTrue(exists(file.url))
    await waitUntil { !self.heldDismissals.isEmpty }
    XCTAssertNil(picker.presentingViewController)
    XCTAssertTrue(exists(file.url))
    heldDismissals.removeFirst()()
    await waitUntil { replies.values.count == 1 }
    XCTAssertEqual(replies.values[0]["status"] as? String, "cancelled")
    XCTAssertEqual(replies.values[0]["cleanupStatus"] as? String, "notNeeded")
    XCTAssertNil(replies.values[0]["residualDocument"])
    XCTAssertFalse(exists(file.directory))
    XCTAssertFalse(coordinator.cancel(operationID: file.id))
  }

  func testCancelDuringPresentationWaitsForThePresentationAndDismissal() async throws {
    let deferred = DeferredPresenter()
    window.rootViewController = deferred
    await waitUntil { deferred.viewIfLoaded?.window === self.window }
    let file = try fixture()
    let coordinator = makeCoordinator(presenter: { deferred }, holdDismissal: true)
    let replies = Replies()
    start(file, coordinator: coordinator, replies: replies)
    let picker = try XCTUnwrap(coordinator.activePicker)
    XCTAssertNil(picker.presentingViewController)
    XCTAssertFalse(picker.isBeingPresented)
    XCTAssertTrue(coordinator.cancel(operationID: file.id))
    XCTAssertTrue(replies.values.isEmpty)
    XCTAssertTrue(exists(file.url))
    deferred.continuePresentation()
    await waitUntil { !self.heldDismissals.isEmpty }
    XCTAssertTrue(replies.values.isEmpty)
    XCTAssertTrue(exists(file.url))
    XCTAssertNil(picker.presentingViewController)
    heldDismissals.removeFirst()()
    await waitUntil { replies.values.count == 1 }
    XCTAssertEqual(replies.values[0]["status"] as? String, "cancelled")
    XCTAssertNil(picker.presentingViewController)
    XCTAssertFalse(exists(file.directory))
  }

  func testSaveAfterCancelAckWinsAndDuplicateCallbacksCannotChangeIt() async throws {
    let file = try fixture()
    let destination = cache.appendingPathComponent("provider-renamed.pdf")
    try file.bytes.write(to: destination)
    let coordinator = makeCoordinator(holdDismissal: true)
    let replies = Replies()
    start(file, coordinator: coordinator, replies: replies)
    let picker = try await presentedPicker(coordinator)
    XCTAssertTrue(coordinator.cancel(operationID: file.id))
    coordinator.documentPicker(picker, didPickDocumentsAt: [destination])
    XCTAssertFalse(coordinator.cancel(operationID: file.id))
    coordinator.documentPickerWasCancelled(picker)
    coordinator.documentPicker(picker, didPickDocumentsAt: [])
    await waitUntil { !self.heldDismissals.isEmpty }
    heldDismissals.removeFirst()()
    await waitUntil { replies.values.count == 1 }
    let result = replies.values[0]
    XCTAssertEqual(result["status"] as? String, "saved")
    XCTAssertEqual(result["displayName"] as? String, "provider-renamed.pdf")
    XCTAssertEqual(result["documentUri"] as? String, destination.absoluteString)
    XCTAssertEqual(result["cleanupStatus"] as? String, "notNeeded")
    XCTAssertNil(result["cleanupError"])
    XCTAssertFalse(exists(file.directory))
    XCTAssertEqual(try Data(contentsOf: destination), file.bytes)
    coordinator.documentPicker(picker, didPickDocumentsAt: [destination])
    XCTAssertEqual(replies.values.count, 1)
  }

  func testSavedResultDoesNotInventAnUnavailableDestinationName() async throws {
    let file = try fixture()
    let coordinator = makeCoordinator()
    let replies = Replies()
    start(file, coordinator: coordinator, replies: replies)
    let picker = try await presentedPicker(coordinator)
    coordinator.documentPicker(picker, didPickDocumentsAt: [cache.appendingPathComponent("does-not-exist.pdf")])
    await waitUntil { replies.values.count == 1 }
    XCTAssertEqual(replies.values[0]["status"] as? String, "saved")
    XCTAssertNil(replies.values[0]["documentUri"])
    XCTAssertNil(replies.values[0]["displayName"])
  }

  func testInvalidProviderResultIsNotRewrittenByLateCancellation() async throws {
    let file = try fixture()
    let coordinator = makeCoordinator(holdDismissal: true)
    let replies = Replies()
    start(file, coordinator: coordinator, replies: replies)
    let picker = try await presentedPicker(coordinator)
    coordinator.documentPicker(picker, didPickDocumentsAt: [])
    XCTAssertFalse(coordinator.cancel(operationID: file.id))
    coordinator.documentPickerWasCancelled(picker)
    XCTAssertTrue(replies.values.isEmpty)
    XCTAssertTrue(exists(file.url))
    await waitUntil { !self.heldDismissals.isEmpty }
    heldDismissals.removeFirst()()
    await waitUntil { replies.values.count == 1 }
    XCTAssertEqual(replies.values[0]["status"] as? String, "failed")
    XCTAssertEqual(replies.values[0]["errorCode"] as? String, "invalid_picker_result")
    XCTAssertFalse(exists(file.directory))
  }

  func testStagingCleanupFailureCannotTurnSavedIntoFailedOrInventResidualDocument() async throws {
    let file = try fixture()
    let destination = cache.appendingPathComponent("saved.pdf")
    try file.bytes.write(to: destination)
    let coordinator = makeCoordinator()
    let replies = Replies()
    start(file, coordinator: coordinator, replies: replies)
    let picker = try await presentedPicker(coordinator)
    let extra = file.directory.appendingPathComponent("unexpected.txt")
    try Data("preserve".utf8).write(to: extra)
    coordinator.documentPicker(picker, didPickDocumentsAt: [destination])
    await waitUntil { replies.values.count == 1 }
    XCTAssertEqual(replies.values[0]["status"] as? String, "saved")
    XCTAssertEqual(replies.values[0]["cleanupStatus"] as? String, "notNeeded")
    XCTAssertTrue((replies.values[0]["cleanupError"] as? String)?.hasPrefix("staging_cleanup_failed:") == true)
    XCTAssertNil(replies.values[0]["residualDocument"])
    XCTAssertTrue(exists(extra))
    XCTAssertEqual(try Data(contentsOf: destination), file.bytes)
  }

  func testBusyDuplicateAndStalePickerDoNotReleaseTheCurrentSource() async throws {
    let first = try fixture()
    let second = try fixture()
    let coordinator = makeCoordinator()
    let firstReplies = Replies()
    start(first, coordinator: coordinator, replies: firstReplies)
    let oldPicker = try await presentedPicker(coordinator)
    let duplicate = Replies()
    start(first, coordinator: coordinator, replies: duplicate)
    XCTAssertEqual(duplicate.values.first?["errorCode"] as? String, "duplicate_operation")
    XCTAssertTrue(exists(first.url))
    let busy = Replies()
    start(second, coordinator: coordinator, replies: busy)
    XCTAssertEqual(busy.values.first?["errorCode"] as? String, "export_busy")
    XCTAssertFalse(exists(second.directory))
    XCTAssertTrue(exists(first.url))
    coordinator.documentPickerWasCancelled(oldPicker)
    await waitUntil { firstReplies.values.count == 1 }
    let next = try fixture()
    let nextReplies = Replies()
    start(next, coordinator: coordinator, replies: nextReplies)
    _ = try await presentedPicker(coordinator)
    coordinator.documentPickerWasCancelled(oldPicker)
    coordinator.documentPicker(oldPicker, didPickDocumentsAt: [first.url])
    XCTAssertTrue(nextReplies.values.isEmpty)
    XCTAssertTrue(exists(next.url))
    XCTAssertTrue(coordinator.cancel(operationID: next.id))
    await waitUntil { nextReplies.values.count == 1 }
  }

  func testInteractiveDismissalCompletesOnlyAfterUIKitDismissed() async throws {
    let file = try fixture()
    let coordinator = makeCoordinator()
    let replies = Replies()
    start(file, coordinator: coordinator, replies: replies)
    let picker = try await presentedPicker(coordinator)
    let presentation = try XCTUnwrap(picker.presentationController)
    let finished = expectation(description: "UIKit dismissal")
    picker.dismiss(animated: false) { finished.fulfill() }
    await fulfillment(of: [finished], timeout: 10)
    // Programmatic dismissal does not synthesize the interactive delegate event.
    XCTAssertTrue(replies.values.isEmpty)
    XCTAssertTrue(exists(file.url))
    coordinator.presentationControllerDidDismiss(presentation)
    await waitUntil { replies.values.count == 1 }
    XCTAssertEqual(replies.values[0]["status"] as? String, "cancelled")
    XCTAssertFalse(exists(file.directory))
  }

  func testSceneDisconnectIsDeliveredByFlutterSceneDelegate() async throws {
    let file = try fixture()
    let coordinator = makeCoordinator()
    let plugin = PdfFileExportPlugin(coordinator: coordinator)
    let engine = FlutterEngine(name: "pdf-export-scene", project: nil, allowHeadlessExecution: true)
    XCTAssertTrue(engine.run(withEntrypoint: "pdfExportHeadlessProbe"))
    let registrar = try XCTUnwrap(engine.registrar(forPlugin: "PdfExportSceneTest"))
    registrar.publish(plugin)
    registrar.addSceneDelegate(plugin)
    let sceneDelegate = FlutterSceneDelegate()
    XCTAssertTrue(sceneDelegate.registerSceneLifeCycle(with: engine))
    defer {
      sceneDelegate.unregisterSceneLifeCycle(with: engine)
      engine.destroyContext()
    }
    let replies = Replies()
    start(file, coordinator: coordinator, replies: replies)
    _ = try await presentedPicker(coordinator)
    let scene = try XCTUnwrap(window.windowScene)
    let delegate: UISceneDelegate = sceneDelegate
    delegate.sceneDidEnterBackground?(scene)
    XCTAssertTrue(exists(file.url))
    XCTAssertTrue(replies.values.isEmpty)
    delegate.sceneDidDisconnect?(scene)
    await waitUntil { replies.values.count == 1 }
    XCTAssertEqual(replies.values[0]["status"] as? String, "cancelled")
    XCTAssertFalse(exists(file.directory))
  }

  func testDestroyContextDoesNotReleaseSourceBeforePickerTerminal() async throws {
    let file = try fixture()
    let coordinator = makeCoordinator()
    let plugin = PdfFileExportPlugin(coordinator: coordinator)
    let engine = FlutterEngine(name: "pdf-export-destroy", project: nil, allowHeadlessExecution: true)
    XCTAssertTrue(engine.run(withEntrypoint: "pdfExportHeadlessProbe"))
    let registrar = try XCTUnwrap(engine.registrar(forPlugin: "PdfExportDestroyTest"))
    registrar.publish(plugin)
    let replies = Replies()
    start(file, coordinator: coordinator, replies: replies)
    let picker = try await presentedPicker(coordinator)
    engine.destroyContext()
    XCTAssertTrue(replies.values.isEmpty)
    XCTAssertTrue(exists(file.url))
    XCTAssertEqual(coordinator.activeOperationID, file.id)
    coordinator.documentPickerWasCancelled(picker)
    await waitUntil { replies.values.count == 1 }
    XCTAssertFalse(exists(file.directory))
  }

  func testActualEngineDeallocationDismissesAndCleansWithoutADartReply() async throws {
    let file = try fixture()
    let coordinator = makeCoordinator(holdDismissal: true)
    let plugin = PdfFileExportPlugin(coordinator: coordinator)
    var engine: FlutterEngine? = FlutterEngine(name: "pdf-export-dealloc", project: nil, allowHeadlessExecution: true)
    weak var weakEngine = engine
    XCTAssertTrue(engine!.run(withEntrypoint: "pdfExportHeadlessProbe"))
    let registrar = try XCTUnwrap(engine!.registrar(forPlugin: "PdfExportDeallocTest"))
    registrar.publish(plugin)
    let replies = Replies()
    start(file, coordinator: coordinator, replies: replies)
    _ = try await presentedPicker(coordinator)
    autoreleasepool { engine = nil }
    await waitUntil { weakEngine == nil }
    await waitUntil { !self.heldDismissals.isEmpty }
    XCTAssertTrue(exists(file.url))
    XCTAssertTrue(replies.values.isEmpty)
    heldDismissals.removeFirst()()
    await waitUntil { coordinator.activeOperationID == nil }
    XCTAssertFalse(exists(file.directory))
    XCTAssertTrue(replies.values.isEmpty)
  }

  func testImplicitEngineRegistrationAndMethodContract() async throws {
    let root = try XCTUnwrap(originalWindow?.rootViewController as? FlutterViewController)
    let engine = try XCTUnwrap(root.engine)
    XCTAssertTrue(engine.hasPlugin(PdfFileExportPlugin.pluginKey))
    XCTAssertNotNil(engine.valuePublished(byPlugin: PdfFileExportPlugin.pluginKey) as? PdfFileExportPlugin)
    let plugin = PdfFileExportPlugin(coordinator: makeCoordinator())
    let invalidArguments: [[String: Any]] = [
      ["version": true, "operationId": String(repeating: "a", count: 32)],
      ["version": 2, "operationId": String(repeating: "a", count: 32)],
      ["version": 1, "operationId": "../outside"],
      ["version": 1, "operationId": String(repeating: "a", count: 32) + "\n"],
      ["version": 1, "operationId": String(repeating: "a", count: 32) + "\r\n"],
      ["version": 1, "operationId": String(repeating: "a", count: 32) + "\u{0085}"],
      ["version": 1, "operationId": String(repeating: "a", count: 32) + "\u{2028}"],
    ]
    for arguments in invalidArguments {
      var reply: Any?
      plugin.handle(FlutterMethodCall(methodName: "cancelExport", arguments: arguments)) { reply = $0 }
      XCTAssertEqual((reply as? FlutterError)?.code, "invalid_arguments")
    }
    var ack: [String: Any]?
    let identifier = String(repeating: "a", count: 32)
    plugin.handle(FlutterMethodCall(methodName: "cancelExport", arguments: ["version": 1, "operationId": identifier])) {
      ack = $0 as? [String: Any]
    }
    XCTAssertEqual(ack?["operationId"] as? String, identifier)
    XCTAssertEqual(ack?["accepted"] as? Bool, false)
  }

  private struct Fixture {
    let id: String
    let name: String
    let directory: URL
    let url: URL
    let bytes: Data
  }

  private final class Replies { var values: [[String: Any]] = [] }

  private func fixture() throws -> Fixture {
    let identifier = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    let name = "בדיקת-ייצוא.pdf"
    let directory = cache.appendingPathComponent(PdfExportStaging.rootName).appendingPathComponent(identifier)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(name)
    let bytes = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 240, height: 320)).pdfData { context in
      context.beginPage()
      UIColor.blue.setFill()
      UIRectFill(CGRect(x: 20, y: 20, width: 80, height: 60))
      ("PDF export ownership" as NSString).draw(at: CGPoint(x: 20, y: 100), withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
    }
    try bytes.write(to: url)
    return Fixture(id: identifier, name: name, directory: directory, url: url, bytes: bytes)
  }

  private func validate(_ file: Fixture) throws -> PdfExportStaging {
    try PdfExportStaging.validate(operationID: file.id, sourcePath: file.url.path, fileName: file.name, cachesDirectory: cache)
  }

  private func makeCoordinator(
    presenter suppliedPresenter: (() -> UIViewController?)? = nil,
    holdDismissal: Bool = false
  ) -> PdfFileExportCoordinator {
    let ownedCache = cache!
    let getPresenter = suppliedPresenter ?? { [weak self] in self?.presenter }
    let coordinator: PdfFileExportCoordinator
    if holdDismissal {
      coordinator = PdfFileExportCoordinator(presenter: getPresenter, cachesDirectory: { ownedCache }) { [weak self] picker, completion in
        picker.dismiss(animated: false) { self?.heldDismissals.append(completion) }
      }
    } else {
      coordinator = PdfFileExportCoordinator(presenter: getPresenter, cachesDirectory: { ownedCache })
    }
    coordinators.append(coordinator)
    return coordinator
  }

  private func start(_ file: Fixture, coordinator: PdfFileExportCoordinator, replies: Replies) {
    coordinator.export(operationID: file.id, sourcePath: file.url.path, fileName: file.name) { value in
      print("PDF export terminal: \(value)")
      replies.values.append(value)
    }
    print("PDF export presentation: \(presentationState(coordinator))")
  }

  private func presentedPicker(_ coordinator: PdfFileExportCoordinator) async throws -> UIDocumentPickerViewController {
    await waitUntil({
      guard let picker = coordinator.activePicker else { return false }
      return picker.presentingViewController != nil && !picker.isBeingPresented
    }, diagnostics: { self.presentationState(coordinator) })
    let picker = try XCTUnwrap(coordinator.activePicker)
    XCTAssertTrue(picker.presentationController?.delegate === coordinator)
    return picker
  }

  private func presentationState(_ coordinator: PdfFileExportCoordinator) -> String {
    let picker = coordinator.activePicker
    return [
      "active=\(coordinator.activeOperationID ?? "nil")",
      "ownerPresented=\(String(describing: presenter?.presentedViewController))",
      "pickerPresenter=\(String(describing: picker?.presentingViewController))",
      "pickerPresenting=\(String(describing: picker?.isBeingPresented))",
      "pickerWindow=\(picker?.viewIfLoaded?.window != nil)",
    ].joined(separator: "; ")
  }

  private func waitUntil(
    _ condition: @escaping () -> Bool, diagnostics: () -> String = { "" },
    file: StaticString = #filePath, line: UInt = #line
  ) async {
    let deadline = Date().addingTimeInterval(15)
    while !condition() && Date() < deadline {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertTrue(condition(), "Native condition did not complete before its deadline. \(diagnostics())", file: file, line: line)
  }

  private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

  private final class DeferredPresenter: UIViewController {
    private var pending: (UIViewController, Bool, (() -> Void)?)?

    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
      pending = (viewControllerToPresent, flag, completion)
    }

    func continuePresentation() {
      guard let (controller, animated, completion) = pending else { return }
      pending = nil
      super.present(controller, animated: animated, completion: completion)
    }
  }
}

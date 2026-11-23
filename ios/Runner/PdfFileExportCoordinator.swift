import Foundation
import UIKit

/// UIKit owns the source until a picker callback and dismissal have completed.
/// A cancel acknowledgement is deliberately separate from that terminal result.
final class PdfFileExportCoordinator: NSObject, UIDocumentPickerDelegate,
  UIAdaptivePresentationControllerDelegate
{
  typealias Reply = ([String: Any]) -> Void
  typealias Dismiss = (UIDocumentPickerViewController, @escaping () -> Void) -> Void

  private final class Operation {
    let staging: PdfExportStaging
    let picker: UIDocumentPickerViewController
    let sceneIdentifier: String?
    var reply: Reply?
    var presenting = true
    var dismissing = false
    var finishing = false
    var providerTerminal = false
    var outcome: Outcome?

    init(
      staging: PdfExportStaging, picker: UIDocumentPickerViewController,
      sceneIdentifier: String?, reply: @escaping Reply
    ) {
      self.staging = staging
      self.picker = picker
      self.sceneIdentifier = sceneIdentifier
      self.reply = reply
    }
  }

  private enum Outcome {
    case saved(URL)
    case cancelled
    case failed(String)

    var saved: Bool {
      if case .saved = self { return true }
      return false
    }

    func result(operationID: String, cleanupError: String?) -> [String: Any] {
      var result: [String: Any] = [
        "version": 1, "operationId": operationID, "cleanupStatus": "notNeeded",
      ]
      switch self {
      case .saved(let url):
        result["status"] = "saved"
        // The delegate confirms completion. Metadata is optional and must come
        // from the returned provider URL, never the requested file name.
        if url.isFileURL {
          let scoped = url.startAccessingSecurityScopedResource()
          defer { if scoped { url.stopAccessingSecurityScopedResource() } }
          if let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .nameKey]),
            values.isRegularFile == true
          {
            result["documentUri"] = url.absoluteString
            result["displayName"] = values.name
          }
        }
      case .cancelled:
        result["status"] = "cancelled"
      case .failed(let code):
        result["status"] = "failed"
        result["errorCode"] = code
      }
      if let cleanupError = cleanupError { result["cleanupError"] = cleanupError }
      return result
    }
  }

  private let presenter: () -> UIViewController?
  private let cachesDirectory: () throws -> URL
  private let dismissPicker: Dismiss
  private var active: Operation?
  private var detached = false

  var activeOperationID: String? { active?.staging.operationID }
  var activePicker: UIDocumentPickerViewController? { active?.picker }

  init(
    presenter: @escaping () -> UIViewController?,
    cachesDirectory: @escaping () throws -> URL = PdfExportStaging.cachesDirectory,
    dismissPicker: @escaping Dismiss = PdfFileExportCoordinator.dismiss
  ) {
    self.presenter = presenter
    self.cachesDirectory = cachesDirectory
    self.dismissPicker = dismissPicker
  }

  func export(
    operationID: String, sourcePath: String, fileName: String,
    reply: @escaping Reply
  ) {
    precondition(Thread.isMainThread)
    guard active?.staging.operationID != operationID else {
      reply(Outcome.failed("duplicate_operation").result(operationID: operationID, cleanupError: nil))
      return
    }
    let staging: PdfExportStaging
    do {
      staging = try PdfExportStaging.validate(
        operationID: operationID, sourcePath: sourcePath, fileName: fileName,
        cachesDirectory: cachesDirectory()
      )
    } catch {
      reply(Outcome.failed("invalid_source").result(operationID: operationID, cleanupError: nil))
      return
    }
    guard !detached, active == nil else {
      reply(Outcome.failed(detached ? "engine_detached" : "export_busy").result(
        operationID: operationID, cleanupError: staging.cleanup()
      ))
      return
    }
    guard let owner = presenter(), owner.viewIfLoaded?.window != nil,
      owner.presentedViewController == nil, !owner.isBeingDismissed,
      !owner.isBeingPresented, owner.transitionCoordinator == nil
    else {
      reply(Outcome.failed("presenter_unavailable").result(
        operationID: operationID, cleanupError: staging.cleanup()
      ))
      return
    }
    let picker = UIDocumentPickerViewController(forExporting: [staging.sourceURL], asCopy: true)
    picker.allowsMultipleSelection = false
    picker.delegate = self
    picker.presentationController?.delegate = self
    let operation = Operation(
      staging: staging, picker: picker,
      sceneIdentifier: owner.view.window?.windowScene?.session.persistentIdentifier,
      reply: reply
    )
    active = operation
    // UIKit can attach the picker asynchronously; only its completion ends presentation.
    owner.present(picker, animated: true) { [self, operation] in
      guard active === operation else { return }
      operation.presenting = false
      picker.presentationController?.delegate = self
      if operation.outcome != nil { dismissAndFinish(operation) }
    }
    picker.presentationController?.delegate = self
  }

  @discardableResult
  func cancel(operationID: String) -> Bool {
    precondition(Thread.isMainThread)
    guard let operation = active, operation.staging.operationID == operationID,
      !operation.finishing, !operation.providerTerminal, operation.outcome?.saved != true
    else { return false }
    operation.outcome = .cancelled
    dismissAndFinish(operation)
    return true
  }

  func detach() {
    precondition(Thread.isMainThread)
    detached = true
    // Do not retain a reply into a dying engine. The dismissal closure retains
    // this coordinator independently until native staging cleanup finishes.
    active?.reply = nil
    if let identifier = activeOperationID { cancel(operationID: identifier) }
  }

  func sceneDidDisconnect(_ scene: UIScene) {
    precondition(Thread.isMainThread)
    if let operation = active,
      operation.sceneIdentifier == scene.session.persistentIdentifier
    {
      cancel(operationID: operation.staging.operationID)
    }
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    precondition(Thread.isMainThread)
    guard let operation = active, operation.picker === controller,
      !operation.finishing, !operation.providerTerminal
    else { return }
    operation.providerTerminal = true
    guard urls.count == 1, let destination = urls.first else {
      operation.outcome = .failed("invalid_picker_result")
      dismissAndFinish(operation)
      return
    }
    // A provider completion received after cancel ACK but before dismissal is
    // still a completed save. A later cancel cannot turn it into cancellation.
    operation.outcome = .saved(destination)
    dismissAndFinish(operation)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    precondition(Thread.isMainThread)
    guard let operation = active, operation.picker === controller,
      !operation.finishing, !operation.providerTerminal
    else { return }
    operation.providerTerminal = true
    if operation.outcome == nil { operation.outcome = .cancelled }
    dismissAndFinish(operation)
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    precondition(Thread.isMainThread)
    guard let operation = active,
      presentationController.presentedViewController === operation.picker,
      !operation.finishing
    else { return }
    operation.presenting = false
    operation.providerTerminal = true
    if operation.outcome == nil { operation.outcome = .cancelled }
    finish(operation)
  }

  private func dismissAndFinish(_ operation: Operation) {
    guard active === operation, !operation.presenting, !operation.dismissing,
      !operation.finishing
    else { return }
    if operation.picker.presentingViewController == nil && !operation.picker.isBeingDismissed {
      finish(operation)
      return
    }
    operation.dismissing = true
    dismissPicker(operation.picker) { [self, operation] in
      finish(operation)
    }
  }

  private func finish(_ operation: Operation) {
    guard active === operation, !operation.finishing, let outcome = operation.outcome else { return }
    guard operation.picker.presentingViewController == nil else { return }
    operation.finishing = true
    operation.picker.delegate = nil
    operation.picker.presentationController?.delegate = nil
    // Provider metadata may perform I/O. No UIKit object is touched by this work.
    let staging = operation.staging
    DispatchQueue.global(qos: .userInitiated).async { [self, operation, staging] in
      let result = outcome.result(operationID: staging.operationID, cleanupError: staging.cleanup())
      DispatchQueue.main.async { [self, operation] in
        guard active === operation else { return }
        let reply = operation.reply
        operation.reply = nil
        active = nil
        reply?(result)
      }
    }
  }

  private static func dismiss(_ picker: UIDocumentPickerViewController, completion: @escaping () -> Void) {
    if picker.isBeingDismissed, let transition = picker.transitionCoordinator,
      transition.animate(alongsideTransition: nil, completion: { context in
        if context.isCancelled {
          picker.dismiss(animated: true, completion: completion)
        } else {
          completion()
        }
      })
    { return }
    picker.dismiss(animated: true, completion: completion)
  }
}

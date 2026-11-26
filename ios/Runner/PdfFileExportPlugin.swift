import CoreFoundation
import Flutter
import UIKit

final class PdfFileExportPlugin: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  static let pluginKey = "OtzariaPdfFileExport"
  static let channelName = "otzaria/pdf_file_export"
  let coordinator: PdfFileExportCoordinator

  init(coordinator: PdfFileExportCoordinator) {
    self.coordinator = coordinator
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let coordinator = PdfFileExportCoordinator(presenter: { [weak registrar] in
      registrar?.viewController
    })
    let plugin = PdfFileExportPlugin(coordinator: coordinator)
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(plugin, channel: channel)
    registrar.addSceneDelegate(plugin)
    registrar.publish(plugin)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    precondition(Thread.isMainThread)
    guard call.method == "exportFile" || call.method == "cancelExport" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let arguments = call.arguments as? [String: Any],
      let version = arguments["version"] as? NSNumber,
      CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 1,
      let identifier = arguments["operationId"] as? String,
      identifier.utf8.count == 32,
      identifier.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil
    else {
      result(FlutterError(code: "invalid_arguments", message: "Invalid PDF export request.", details: nil))
      return
    }
    if call.method == "cancelExport" {
      result(["operationId": identifier, "accepted": coordinator.cancel(operationID: identifier)])
      return
    }
    guard let sourcePath = arguments["sourcePath"] as? String,
      let fileName = arguments["fileName"] as? String
    else {
      result(FlutterError(code: "invalid_arguments", message: "Missing PDF export source.", details: nil))
      return
    }
    coordinator.export(operationID: identifier, sourcePath: sourcePath, fileName: fileName) { value in
      result(value)
    }
  }

  func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    let coordinator = self.coordinator
    if Thread.isMainThread {
      coordinator.detach()
    } else {
      DispatchQueue.main.async { coordinator.detach() }
    }
  }

  func sceneDidDisconnect(_ scene: UIScene) {
    coordinator.sceneDidDisconnect(scene)
  }
}

import CoreText
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "OtzariaNativeFonts") {
      NativeFontFamilies.register(with: registrar.messenger())
    }
  }
}

/// Names of the system font families that have Hebrew letters, for the font
/// picker (display only: iOS exposes no font files). The Dart side is
/// lib/utils/file/native_font_families.dart; the channel name and method must
/// match it.
enum NativeFontFamilies {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "otzaria/native_fonts", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      if call.method == "hebrewFamilies" {
        result(hebrewFamilies())
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func hebrewFamilies() -> [[String: Any]] {
    let alef = Unicode.Scalar(UInt32(0x05D0))!
    let taamim = Unicode.Scalar(UInt32(0x0591))!
    var families: [[String: Any]] = []
    for family in UIFont.familyNames {
      guard let name = UIFont.fontNames(forFamilyName: family).first else { continue }
      let font = CTFontCreateWithName(name as CFString, 12, nil)
      let characters = CTFontCopyCharacterSet(font) as CharacterSet
      if characters.contains(alef) {
        families.append(["family": family, "taamim": characters.contains(taamim)])
      }
    }
    return families
  }
}

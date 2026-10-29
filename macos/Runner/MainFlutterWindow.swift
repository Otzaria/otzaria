import Cocoa
import FlutterMacOS
import ImageIO
import Metal
import QuartzCore

/// Impeller (ברירת המחדל מ-Flutter 3.47) רק על GPU של Apple Silicon. על Intel, ובמיוחד
/// על GPU ישן תחת OCLP, העלייה נתקעת (#1898), ולכן שם Skia. `OTZARIA_RENDERER` עוקף לבדיקה.
final class OtzariaDartProject: FlutterDartProject {
  // דורס getter פנימי (FlutterDartProject_Internal.h); זו נקודת ההחלטה היחידה של המנוע.
  @objc var enableImpeller: Bool { OtzariaDartProject.useImpeller }

  // המנוע מחפש את icudtl.dat ב-bundle של [self class], שב-subclass הוא Runner.app.
  // בלי ICU אין הזדמנויות שבירה, והשורות נחתכות באמצע מילה (#3546).
  @objc var ICUDataPath: String? {
    Bundle(for: FlutterDartProject.self).path(forResource: "icudtl.dat", ofType: nil)
  }

  static let useImpeller: Bool = {
    assert(
      class_getInstanceMethod(FlutterDartProject.self, NSSelectorFromString("enableImpeller"))
        != nil, "FlutterDartProject.enableImpeller was renamed; the renderer override is dead")
    switch ProcessInfo.processInfo.environment["OTZARIA_RENDERER"] {
    case "impeller": return true
    case "skia": return false
    default: return MTLCreateSystemDefaultDevice()?.supportsFamily(.apple7) ?? false
    }
  }()
}

/// רק Flutter מחליט אם גרירה מזיזה את החלון: התוכן מצויר מתחת לשורת הכותרת
/// השקופה, ולכן החלון נעול קבוע ורק `startDragging` → `performDrag` משחרר.
///
/// ⚠️ הנעילה חייבת להיות מראש: AppKit מוסר ל-WindowServer את אזורי הגרירה
/// של החלון, והשרת גורר בעצמו בלי לשאול את האפליקציה. נעילה ב-mouseDown
/// מגיעה אחרי שהאזורים כבר נמסרו, וגרירת כרטיסיה עדיין מזיזה את החלון.
class OtzariaWindow: NSWindow {
  override init(
    contentRect: NSRect, styleMask style: NSWindow.StyleMask,
    backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool
  ) {
    super.init(
      contentRect: contentRect, styleMask: style,
      backing: backingStoreType, defer: flag)
    isMovable = false
  }

  // החלון הראשי נטען מ-xib ולא דרך ה-init שלמעלה.
  override func awakeFromNib() {
    super.awakeFromNib()
    isMovable = false
  }

  override func performDrag(with event: NSEvent) {
    isMovable = true
    super.performDrag(with: event)
    isMovable = false
  }
}

class MainFlutterWindow: OtzariaWindow {
  // חלון ה-splash הנייטיב (סמל צף שקוף) וערוץ הסגירה שלו.
  private var splashWindow: NSWindow?
  private var splashChannel: FlutterMethodChannel?
  private var splashShownAt: Date?
  private var terminationChannel: FlutterMethodChannel?
  private(set) var isDartCloseHandlingEnabled = false
  private var isDartTerminationAllowed = false

  // אטימות הסמל (~70%) וזמן תצוגה מינימלי (מונע הבזק אם החשיפה מוקדמת).
  private let splashAlpha: CGFloat = 0.70
  private let minDisplaySeconds: TimeInterval = 0.8

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController(project: OtzariaDartProject())
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    // אחרי שה-controller נרשם כתצוגה המרומזת (0): חלונות Dart יקבלו מזהים ≥1.
    OtzariaViewWindows.shared.attach(mainController: flutterViewController)

    // מציגים מיד את ה-splash הנייטיב (סמל צף) — משוב ויזואלי מיידי.
    showSplash()

    // ערוץ "otzaria/splash": Dart קורא "close" בעת חשיפת החלון הראשי → fade-out.
    let channel = FlutterMethodChannel(
      name: "otzaria/splash",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "close" {
        self?.revealMainWindowAndCloseSplash()
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    splashChannel = channel

    let terminationChannel = FlutterMethodChannel(
      name: "otzaria/macos_termination",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    terminationChannel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "enableCloseHandling":
        self?.isDartCloseHandlingEnabled = true
        result(nil)
      case "allowTermination":
        self?.isDartTerminationAllowed = true
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.terminationChannel = terminationChannel

    // ערוץ `otzaria/multiwindow` של החלון הראשי (הסתרה, הבאה לחזית ושחזור).
    OtzariaWindowManager.shared.registerMainWindow(
      self, messenger: flutterViewController.engine.binaryMessenger)

    // משאירים את החלון הראשי **שקוף לגמרי** (alpha 0) עד החשיפה, במקום
    // orderOut (שלא נדבק ב-macOS — המערכת מציגה את החלון מחדש אחרי awakeFromNib,
    // וכך נראה גם אוברליי ה-splash של Flutter במרכזו). שקוף-לגמרי: החלון נשאר
    // על המסך ומצייר את התוכן (ללא ציור-בזמן-הסתרה בעייתי), אך בלתי-נראה, ולכן
    // נראה רק ה-splash הצף. בחשיפה (ערוץ "close") מחזירים alpha=1.
    self.alphaValue = 0

    super.awakeFromNib()
  }

  /// ⌘Q ו-Quit שולחים `NSApplication.terminate`, שעוקף את ה-delegate של
  /// החלון. כל עוד Dart לא סיים את רצף היציאה, מבקשים ממנו לצאת, ולאחר
  /// ההיתר המפורש משלימים את אותה בקשת terminate.
  /// ⚠️ לא `performClose`: זו סגירת חלון, שבמק משאירה את האפליקציה ב-Dock,
  /// וגם אינה מגיעה ל-Dart כשהחלון הראשי מוסתר.
  func applicationShouldTerminate() -> NSApplication.TerminateReply {
    guard isDartCloseHandlingEnabled else { return .terminateNow }
    if isDartTerminationAllowed { return .terminateNow }
    terminationChannel?.invokeMethod("quitRequested", arguments: nil)
    return .terminateCancel
  }

  private func showSplash() {
    guard splashWindow == nil, let screen = NSScreen.main else { return }
    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
      showAnimatedSplash(on: screen)
    {
      return
    }
    showStaticSplash(on: screen)
  }

  private func showStaticSplash(on screen: NSScreen) {
    guard let image = loadSplashIcon() else { return }

    let size: CGFloat = 160
    let visible = screen.visibleFrame
    let rect = NSRect(
      x: visible.midX - size / 2, y: visible.midY - size / 2,
      width: size, height: size)

    let win = NSWindow(
      contentRect: rect, styleMask: .borderless, backing: .buffered,
      defer: false)
    win.isOpaque = false
    win.backgroundColor = .clear
    win.hasShadow = false
    win.level = .floating
    win.ignoresMouseEvents = true
    win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    win.alphaValue = 0  // מתחיל שקוף עבור fade-in

    let imageView = NSImageView(frame: NSRect(origin: .zero, size: rect.size))
    imageView.image = image
    imageView.imageScaling = .scaleProportionallyUpOrDown
    win.contentView = imageView

    win.orderFrontRegardless()
    splashWindow = win
    splashShownAt = Date()

    // fade-in הדרגתי ל-splashAlpha.
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.39
      win.animator().alphaValue = splashAlpha
    }
  }

  // ציר הזמן של native/splash/splash_timeline.h (משותף ל-Windows ול-Linux).
  private enum BookTimeline {
    static let framesPerSecond = 24.0
    static let frameSize: CGFloat = 177  // הספר הפתוח בגודל הסמל הסטטי
    static let fadeIn: CFTimeInterval = 0.195
    static let breathDelay: CFTimeInterval = 0.8
    static let breathPeriod: CFTimeInterval = 2.8
    static let breathDepth = 0.22
  }

  // הספר נפתח ב-Core Animation (שרת הרינדור, בלי טיימר באפליקציה). הפענוח ברקע;
  // החלון קיים כבר עכשיו (שקוף), כדי שזמן התצוגה המינימלי יימדד כמו קודם.
  private func showAnimatedSplash(on screen: NSScreen) -> Bool {
    let name = screen.backingScaleFactor >= 2 ? "splash_book_200" : "splash_book_100"
    guard let url = Bundle.main.url(forResource: name, withExtension: "png") else {
      return false
    }
    let size = BookTimeline.frameSize
    let visible = screen.visibleFrame
    let rect = NSRect(
      x: visible.midX - size / 2, y: visible.midY - size / 2,
      width: size, height: size)

    let win = NSWindow(
      contentRect: rect, styleMask: .borderless, backing: .buffered,
      defer: false)
    win.isOpaque = false
    win.backgroundColor = .clear
    win.hasShadow = false
    win.level = .floating
    win.ignoresMouseEvents = true
    win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    win.alphaValue = 0

    let view = NSView(frame: NSRect(origin: .zero, size: rect.size))
    view.wantsLayer = true
    win.contentView = view
    win.orderFrontRegardless()
    splashWindow = win
    splashShownAt = Date()

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let frames = MainFlutterWindow.decodeFrames(url)
      DispatchQueue.main.async {
        guard let self = self, self.splashWindow === win, let layer = view.layer
        else { return }
        guard let frames = frames, !frames.isEmpty else {
          // רצועה פגומה: הסמל הסטטי, כמו בהפחתת תנועה.
          win.orderOut(nil)
          self.splashWindow = nil
          self.showStaticSplash(on: screen)
          return
        }
        self.startBookAnimation(layer: layer, frames: frames)
        NSAnimationContext.runAnimationGroup { context in
          context.duration = BookTimeline.fadeIn
          win.animator().alphaValue = self.splashAlpha
        }
      }
    }
    return true
  }

  // כל פריים מצויר לביטמפ משלו ברקע — כך Core Animation לא מפענח על ה-main thread.
  private static func decodeFrames(_ url: URL) -> [CGImage]? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let strip = CGImageSourceCreateImageAtIndex(
        source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    else { return nil }
    let side = strip.width
    guard side > 0, strip.height % side == 0 else { return nil }
    let count = strip.height / side
    var frames: [CGImage] = []
    frames.reserveCapacity(count)
    for i in 0..<count {
      guard let crop = strip.cropping(to: CGRect(x: 0, y: i * side, width: side, height: side)),
        let context = CGContext(
          data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue)
      else { return nil }
      context.draw(crop, in: CGRect(x: 0, y: 0, width: side, height: side))
      guard let frame = context.makeImage() else { return nil }
      frames.append(frame)
    }
    return frames
  }

  private func startBookAnimation(layer: CALayer, frames: [CGImage]) {
    let start = CACurrentMediaTime() + BookTimeline.fadeIn
    let duration = Double(frames.count) / BookTimeline.framesPerSecond
    layer.contentsGravity = .resize
    layer.contentsScale = CGFloat(frames[0].width) / BookTimeline.frameSize
    layer.contents = frames[frames.count - 1]  // המצב הסופי: הספר פתוח

    let opening = CAKeyframeAnimation(keyPath: "contents")
    opening.values = frames
    opening.calculationMode = .discrete
    // ב-discrete נדרש keyTime אחד יותר מהערכים, מ-0 עד 1.
    opening.keyTimes = (0...frames.count).map {
      NSNumber(value: Double($0) / Double(frames.count))
    }
    opening.beginTime = start
    opening.duration = duration
    opening.fillMode = .both
    layer.add(opening, forKey: "opening")

    // עלייה איטית: "נשימה" — גל אטימות רדוד, מתחיל באטימות מלאה.
    let breath = CABasicAnimation(keyPath: "opacity")
    breath.fromValue = 1.0
    breath.toValue = 1.0 - BookTimeline.breathDepth
    breath.duration = BookTimeline.breathPeriod / 2
    breath.autoreverses = true
    breath.repeatCount = .infinity
    breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    breath.beginTime =
      start + duration - 1 / BookTimeline.framesPerSecond + BookTimeline.breathDelay
    layer.add(breath, forKey: "breath")
  }

  // חושף את החלון הראשי וסוגר את ה-splash *בו-זמנית* (crossfade), כך שהסמל אינו
  // "נשאר" אחרי שהחלון עלה. אוכף זמן תצוגה מינימלי: אם הסגירה הגיעה מוקדם
  // (טעינה מהירה), דוחה את כל החשיפה — לא רק את ה-fade — כדי שהחלון לא יקדים.
  private func revealMainWindowAndCloseSplash() {
    let elapsed = splashShownAt.map { Date().timeIntervalSince($0) } ?? 0
    let delay = max(0, minDisplaySeconds - elapsed)
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self = self else { return }
      let splash = self.splashWindow
      self.splashWindow = nil
      // crossfade: החלון הראשי נכנס (alpha 0→1) והסמל יוצא (→0) יחד, ומסתיימים
      // באותו רגע — אין "שהיית-יתר" של הסמל מעל החלון.
      NSAnimationContext.runAnimationGroup(
        { context in
          context.duration = 0.18
          self.animator().alphaValue = 1
          splash?.animator().alphaValue = 0
        },
        completionHandler: {
          splash?.orderOut(nil)
          // משחרר את הפריימים (עד 12MB ב-Retina) יחד עם החלון.
          splash?.contentView?.layer?.removeAllAnimations()
          splash?.contentView?.layer?.contents = nil
        })
    }
  }

  // טוען את icon.png מתוך flutter_assets (ב-macOS הם ב-App.framework/Resources).
  private func loadSplashIcon() -> NSImage? {
    let assetPath = "flutter_assets/assets/icon/icon.png"
    if let frameworksURL = Bundle.main.privateFrameworksURL,
      let appBundle = Bundle(
        url: frameworksURL.appendingPathComponent("App.framework")),
      let resourceURL = appBundle.resourceURL
    {
      let url = resourceURL.appendingPathComponent(assetPath)
      if let image = NSImage(contentsOf: url) { return image }
    }
    // גיבוי: משאבי ה-bundle הראשי.
    if let resourceURL = Bundle.main.resourceURL {
      let url = resourceURL.appendingPathComponent(assetPath)
      if let image = NSImage(contentsOf: url) { return image }
    }
    return nil
  }
}

// MARK: - החלון הראשי בערוץ otzaria/multiwindow

/// הסתרה, הבאה לחזית ושחזור של החלון הראשי. חלונות נוספים הם חלונות Dart
/// במנוע הראשי (`OtzariaViewWindows`), וה-runner אינו מחזיק עליהם רשומה.
final class OtzariaWindowManager {
  static let shared = OtzariaWindowManager()

  private weak var mainWindow: NSWindow?
  private var channel: FlutterMethodChannel?
  /// Dart הסתיר את הראשי (`closeSelf`); הוא חוזר ב-`raiseSelf` או בשחזור.
  private var isMainHidden = false
  /// סגירה ממתינה ליציאה ממסך מלא לפני ההסתרה.
  private var hidesAfterFullScreen = false

  private init() {}

  /// נקרא פעם אחת מ-`awakeFromNib`.
  func registerMainWindow(_ window: NSWindow, messenger: FlutterBinaryMessenger) {
    guard channel == nil else { return }
    mainWindow = window
    let channel = FlutterMethodChannel(
      name: "otzaria/multiwindow", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      self.handleCall(call, result: result)
    }
    self.channel = channel
    let center = NotificationCenter.default
    _ = center.addObserver(
      forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main
    ) { [weak self] _ in
      guard let self = self, self.hidesAfterFullScreen else { return }
      self.hidesAfterFullScreen = false
      self.hide()
    }
    // toggleFullScreen באמצע אנימציית הכניסה נבלע; מנסים שוב בסופה.
    _ = center.addObserver(
      forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main
    ) { [weak self] _ in
      guard let self = self, self.hidesAfterFullScreen else { return }
      self.mainWindow?.toggleFullScreen(nil)
    }
  }

  private func handleCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "closeSelf":
      DispatchQueue.main.async { [weak self] in
        self?.hide()
      }
      result(nil)

    case "raiseSelf":
      if isMainHidden {
        showMainWindow()
      } else {
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
      }
      result(nil)

    case "restoreLastClosedWindow":
      result(restoreLastClosedWindow())

    default:
      // ⚠️ כולל את מתודות הגרירה, שאינן ממומשות במק. הצד של Dart עוטף כל אחת
      // וממפה כשל ל"לא ידוע".
      result(FlutterMethodNotImplemented)
    }
  }

  private func hide() {
    guard !isMainHidden, let window = mainWindow else { return }
    // orderOut במסך מלא משאיר את ה-Space של החלון ריק (מסך שחור, #3551).
    if window.styleMask.contains(.fullScreen) {
      if !hidesAfterFullScreen {
        hidesAfterFullScreen = true
        window.toggleFullScreen(nil)
      }
      return
    }
    isMainHidden = true
    // גם כשזה החלון האחרון: האפליקציה נשארת ב-Dock, ולחיצה עליו משחזרת.
    window.orderOut(nil)
  }

  /// מציג את הראשי ומעביר אליו את הפוקוס, גם אם Dart הסתיר אותו.
  func showMainWindow() {
    guard let window = mainWindow else { return }
    isMainHidden = false
    hidesAfterFullScreen = false
    window.alphaValue = 1
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  /// מציג שוב את הראשי ש-Dart הסתיר; false כשלא הוסתר.
  func restoreLastClosedWindow() -> Bool {
    guard isMainHidden else { return false }
    showMainWindow()
    return true
  }
}

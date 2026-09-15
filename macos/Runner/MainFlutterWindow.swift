import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  // חלון ה-splash הנייטיב (סמל צף שקוף) וערוץ הסגירה שלו.
  private var splashWindow: NSWindow?
  private var splashChannel: FlutterMethodChannel?
  private var splashShownAt: Date?
  private var terminationChannel: FlutterMethodChannel?
  private var isDartCloseHandlingEnabled = false
  private var isDartTerminationAllowed = false

  // אטימות הסמל (~70%) וזמן תצוגה מינימלי (מונע הבזק אם החשיפה מוקדמת).
  private let splashAlpha: CGFloat = 0.70
  private let minDisplaySeconds: TimeInterval = 0.8

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

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

    // ריבוי חלונות: ערוץ `otzaria/multiwindow` על **כל** מנוע, כולל הראשי.
    // ה-isolate של כל חלון רואה רק את עצמו, ולכן הנייטיב הוא מקור האמת
    // לספירה, לנראות ולחלון הפעיל האחרון.
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
  /// החלון. כל עוד Dart לא סיים את ה-flush, מחזירים אותו ל-`performClose`,
  /// ש-window_manager מתרגם ל-onWindowClose. לאחר ההיתר המפורש מ-Dart
  /// אפשר להשלים את אותה בקשת terminate בלי להציג שוב את האישור.
  func applicationShouldTerminate() -> NSApplication.TerminateReply {
    guard isDartCloseHandlingEnabled else { return .terminateNow }
    if isDartTerminationAllowed { return .terminateNow }
    performClose(nil)
    return .terminateCancel
  }

  private func showSplash() {
    guard splashWindow == nil, let image = loadSplashIcon(),
      let screen = NSScreen.main
    else { return }

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
        })
    }
  }

  // טוען את iconnew.png מתוך flutter_assets (ב-macOS הם ב-App.framework/Resources).
  private func loadSplashIcon() -> NSImage? {
    let assetPath = "flutter_assets/assets/icon/iconnew.png"
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

// MARK: - ריבוי חלונות

/// תקרת חלונות. כל חלון הוא מנוע Flutter מלא, ולכן זו הגבלת משאבים.
private let kOtzariaMaxWindows = 4

/// חלון אוצריא יחיד — הראשי או משני — כפי שמנהל החלונות רואה אותו.
final class OtzariaWindowEntry {
  let window: NSWindow
  let isMain: Bool
  /// המנוע שההנדל מחזיק. nil בחלון הראשי, שם ה-`FlutterViewController`
  /// של ה-nib הוא הבעלים.
  let engine: FlutterEngine?
  var channel: FlutterMethodChannel?
  var splashChannel: FlutterMethodChannel?
  /// המשתמש סגר את החלון: הוא מוסתר ולא נהרס, והמנוע שלו נשאר חם.
  var isClosedByUser = false
  /// סידורי ההסתרה — קובע מי משוחזר ב"שחזר חלון אחרון".
  var hiddenAt: UInt64 = 0
  var busSlot: Int?
  var isRevealed: Bool

  init(window: NSWindow, isMain: Bool, engine: FlutterEngine?, isRevealed: Bool) {
    self.window = window
    self.isMain = isMain
    self.engine = engine
    self.isRevealed = isRevealed
  }
}

/// מנהל חלונות אוצריא בתהליך: מנוע `FlutterEngine` לכל חלון, כמו ב-Windows.
///
/// ⚠️ מכסה את **פתיחת החלונות בלבד**. גרירת כרטיסיה החוצה
/// (`dragOutToSystem` ואחיותיה) אינה ממומשת ב-macOS ומחזירה
/// `FlutterMethodNotImplemented`.
final class OtzariaWindowManager {
  static let shared = OtzariaWindowManager()

  private var entries: [OtzariaWindowEntry] = []
  private var hiddenSequence: UInt64 = 0
  /// מנועים שנוצרו. אינו יורד לעולם — מנוע אינו נהרס עם החלון, ולכן
  /// התקרה נאכפת גם עליו ולא רק על החלונות הגלויים.
  private var enginesCreated = 0
  private var spawnIndex = 0
  private weak var lastActiveWindow: NSWindow?
  private var keyWindowObserver: NSObjectProtocol?

  private init() {
    keyWindowObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
    ) { [weak self] note in
      guard let self = self, let window = note.object as? NSWindow else { return }
      guard self.entries.contains(where: { $0.window === window }) else { return }
      self.lastActiveWindow = window
    }
  }

  /// מספר החלונות שהמשתמש רואה כפתוחים. חלון שנסגר מוסתר ואינו נספר.
  private var liveWindowCount: Int {
    return entries.filter { !$0.isClosedByUser }.count
  }

  // MARK: רישום

  /// רושם את החלון הראשי ואת הערוץ שלו. נקרא פעם אחת מ-`awakeFromNib`.
  func registerMainWindow(_ window: NSWindow, messenger: FlutterBinaryMessenger) {
    guard !entries.contains(where: { $0.isMain }) else { return }
    let entry = OtzariaWindowEntry(
      window: window, isMain: true, engine: nil, isRevealed: true)
    entry.channel = makeMultiWindowChannel(messenger: messenger, entry: entry)
    entries.append(entry)
    enginesCreated = 1
  }

  private func makeMultiWindowChannel(
    messenger: FlutterBinaryMessenger, entry: OtzariaWindowEntry
  ) -> FlutterMethodChannel {
    let channel = FlutterMethodChannel(
      name: "otzaria/multiwindow", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak entry] call, result in
      guard let entry = entry else {
        result(nil)
        return
      }
      OtzariaWindowManager.shared.handleCall(call, result: result, for: entry)
    }
    return channel
  }

  /// ערוץ ה-splash של חלון משני. ההודעה מגיעה בסוף האתחול של Dart
  /// (`presentMainWindow`), וזהו הרגע שבו יש תוכן להציג.
  private func installSplashChannel(
    messenger: FlutterBinaryMessenger, entry: OtzariaWindowEntry
  ) {
    let channel = FlutterMethodChannel(
      name: "otzaria/splash", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak entry] call, result in
      guard let entry = entry else {
        result(nil)
        return
      }
      switch call.method {
      case "close":
        OtzariaWindowManager.shared.reveal(entry)
        result(nil)
      case "cloak":
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    entry.splashChannel = channel
  }

  // MARK: הערוץ

  private func handleCall(
    _ call: FlutterMethodCall, result: @escaping FlutterResult,
    for entry: OtzariaWindowEntry
  ) {
    switch call.method {
    case "windowCount":
      result([
        "count": liveWindowCount,
        "max": kOtzariaMaxWindows,
        "engines": enginesCreated,
      ])

    case "openWindow":
      let args = call.arguments as? [String: Any] ?? [:]
      let payload = args["payload"] as? String ?? ""
      let width = args["width"] as? Int ?? 0
      let height = args["height"] as? Int ?? 0
      // ⚠️ נדחה לסבב הבא של לולאת הריצה. הקריאה מגיעה מתוך טיפול בערוץ,
      // כלומר מתוך ריצת ה-Dart של החלון הזה, ויצירת מנוע נוסף משם היא
      // ריאנטרנטית. Dart מוחק את הכרטיסיה לפי התשובה, ולכן היא נשלחת רק
      // אחרי היצירה בפועל.
      // ⚠️ `originX`/`originY`/`bounds` נשלחים רק ממסלול הגרירה, שאינו
      // ממומש כאן — ולכן הם אינם מתורגמים לצירי macOS אלא מדולגים.
      DispatchQueue.main.async {
        let created = OtzariaWindowManager.shared.openWindow(
          payload: payload, width: width, height: height)
        result(created)
      }

    case "closeSelf":
      // ⚠️ מוסתר ולא נהרס: המנוע נשאר חם לשחזור ולמיחזור בפתיחה הבאה.
      DispatchQueue.main.async {
        OtzariaWindowManager.shared.hide(entry)
      }
      result(nil)

    case "raiseSelf":
      if entry.isClosedByUser {
        // ⚠️ חלון שהמשתמש סגר חוזר רק דרך `revive`, שמחזיר גם את הספירה.
        revive(entry, payload: "", width: 0, height: 0)
      } else {
        entry.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
      }
      result(nil)

    case "setBusSlot":
      if let slot = call.arguments as? Int {
        entry.busSlot = slot
      }
      result(nil)

    case "visibleSlots":
      result(
        entries.compactMap { candidate -> Int? in
          guard !candidate.isClosedByUser, candidate.window.isVisible else {
            return nil
          }
          return candidate.busSlot
        })

    case "lastActiveSlot":
      if let slot = lastActiveSlot() {
        result(slot)
      } else {
        result(nil)
      }

    case "restoreLastClosedWindow":
      result(restoreLastClosedWindow())

    default:
      // ⚠️ כולל את מתודות הגרירה ואת המתודות הפר-תהליכיות של Windows.
      // הצד של Dart עוטף כל אחת מהן וממפה כשל ל"לא ידוע", שהוא המצב כאן.
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: פתיחה, הסתרה ושחזור

  private func openWindow(payload: String, width: Int, height: Int) -> Bool {
    // ⚠️ מיחזור לפני יצירה. חלון שנסגר מוסתר והמנוע שלו חם, ושימוש חוזר
    // בו חוסך את כל האתחול וגם מונע גידול בזיכרון במחזורי פתיחה-סגירה.
    if let reusable = entries.filter({ $0.isClosedByUser })
      .max(by: { $0.hiddenAt < $1.hiddenAt })
    {
      revive(reusable, payload: payload, width: width, height: height)
      return true
    }
    if enginesCreated >= kOtzariaMaxWindows || liveWindowCount >= kOtzariaMaxWindows {
      return false
    }
    return createSecondaryWindow(payload: payload, width: width, height: height)
  }

  private func createSecondaryWindow(payload: String, width: Int, height: Int) -> Bool {
    let project = FlutterDartProject()
    // ⚠️ המטען עובר כארגומנט לנקודת הכניסה ולא בערוץ: החלון עוד לא קיים
    // בזמן הקריאה, ו-`secondaryWindowMain` קורא אותו לפני `runApp`.
    project.dartEntrypointArguments = [payload]

    let engine = FlutterEngine(
      name: "otzaria_window_\(enginesCreated)", project: project,
      allowHeadlessExecution: true)
    guard engine.run(withEntrypoint: "secondaryWindowMain") else {
      return false
    }
    enginesCreated += 1
    RegisterGeneratedPlugins(registry: engine)

    let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)

    // ⚠️ המידות מ-Dart הן נקודות לוגיות, וזו גם היחידה של `NSWindow` —
    // אין כאן המרת DPI כמו ב-Windows.
    let size = NSSize(
      width: width > 400 ? CGFloat(width) : 1100,
      height: height > 300 ? CGFloat(height) : 760)
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    window.title = "אוצריא"
    window.isReleasedWhenClosed = false
    window.contentViewController = controller
    placeCascading(window)

    // ⚠️ שקוף-לגמרי ולא מוסתר, בדיוק כמו החלון הראשי: חלון שאינו על המסך
    // אינו מקבל פריימים, והאתחול שממתין לפריים לא היה מסתיים לעולם.
    // `ignoresMouseEvents` כי חלון שקוף עדיין בולע לחיצות, ו-`orderFront`
    // ולא `makeKeyAndOrderFront` כדי לא לחטוף פוקוס לפני החשיפה.
    window.alphaValue = 0
    window.ignoresMouseEvents = true
    window.orderFront(nil)

    let entry = OtzariaWindowEntry(
      window: window, isMain: false, engine: engine, isRevealed: false)
    entry.channel = makeMultiWindowChannel(messenger: engine.binaryMessenger, entry: entry)
    installSplashChannel(messenger: engine.binaryMessenger, entry: entry)
    entries.append(entry)

    // רשת ביטחון: אם הודעת החשיפה לא הגיעה, חלון בלתי-נראה לתמיד גרוע
    // מחלון שמופיע מאוחר.
    DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
      OtzariaWindowManager.shared.reveal(entry)
    }
    return true
  }

  /// היסט מדורג מהחלון הפעיל, מהודק לאזור העבודה של המסך שתחתיו.
  private func placeCascading(_ window: NSWindow) {
    let reference = lastActiveWindow ?? entries.first(where: { !$0.isClosedByUser })?.window
    let screen = reference?.screen ?? NSScreen.main
    guard let visible = screen?.visibleFrame else {
      window.center()
      return
    }
    spawnIndex += 1
    let step = CGFloat(24 * (spawnIndex % 6))
    var frame = window.frame
    let base = reference?.frame ?? visible
    frame.origin = NSPoint(x: base.minX + step, y: base.maxY - frame.height - step)
    if frame.maxX > visible.maxX { frame.origin.x = visible.maxX - frame.width }
    if frame.minX < visible.minX { frame.origin.x = visible.minX }
    if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - frame.height }
    if frame.minY < visible.minY { frame.origin.y = visible.minY }
    window.setFrame(frame, display: false)
  }

  private func reveal(_ entry: OtzariaWindowEntry) {
    guard !entry.isRevealed, !entry.isClosedByUser else { return }
    entry.isRevealed = true
    entry.window.ignoresMouseEvents = false
    entry.window.alphaValue = 1
    entry.window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func hide(_ entry: OtzariaWindowEntry) {
    guard !entry.isClosedByUser else { return }
    entry.isClosedByUser = true
    hiddenSequence += 1
    entry.hiddenAt = hiddenSequence
    entry.window.orderOut(nil)
    guard liveWindowCount == 0 else { return }
    // ⚠️ נסגר החלון האחרון בלי שעבר את מסלול הסגירה של Dart (שם
    // `windowCount() <= 1` מוביל לכיבוי מלא). אין מה לשטוף, רק לצאת —
    // ו-`NSApp.terminate` היה חוזר ל-`performClose` דרך שער ה-⌘Q.
    exit(0)
  }

  private func revive(
    _ entry: OtzariaWindowEntry, payload: String, width: Int, height: Int
  ) {
    entry.isClosedByUser = false
    if width > 400 && height > 300 {
      // ⚠️ הפינה העליונה נשמרת: ראשית ה-frame ב-macOS היא הפינה התחתונה,
      // ושינוי גובה בלבד היה מזיז את החלון כלפי מעלה.
      var frame = entry.window.frame
      let top = frame.maxY
      frame.size = NSSize(width: CGFloat(width), height: CGFloat(height))
      frame.origin.y = top - frame.height
      entry.window.setFrame(frame, display: true)
    }
    entry.isRevealed = true
    entry.window.ignoresMouseEvents = false
    entry.window.alphaValue = 1
    entry.window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    // המנוע כבר רץ ונקודת הכניסה שלו הורצה מזמן, ולכן המטען מגיע בערוץ.
    if !payload.isEmpty {
      entry.channel?.invokeMethod("adoptPayload", arguments: payload)
    }
  }

  private func restoreLastClosedWindow() -> Bool {
    guard
      let newest = entries.filter({ $0.isClosedByUser })
        .max(by: { $0.hiddenAt < $1.hiddenAt })
    else { return false }
    revive(newest, payload: "", width: 0, height: 0)
    return true
  }

  private func lastActiveSlot() -> Int? {
    if let window = lastActiveWindow,
      let entry = entries.first(where: { $0.window === window }),
      !entry.isClosedByUser, entry.window.isVisible, let slot = entry.busSlot
    {
      return slot
    }
    // ⚠️ חלון מוסתר לעולם אינו נבחר — קישור חיצוני היה מקפיץ אותו למסך.
    return entries.filter { !$0.isClosedByUser && $0.window.isVisible }
      .compactMap { $0.busSlot }
      .min()
  }
}

// ignore_for_file: implementation_imports, invalid_use_of_internal_member
// הקובץ היחיד שנוגע ב-API הפנימי של Flutter לחלונות; כל השאר עובר דרכו.
import 'dart:async';
import 'dart:io';
import 'dart:ui' show FlutterView, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/src/foundation/_features.dart' as features;
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/src/widgets/_window_linux.dart'
    show WindowControllerLinux;
import 'package:flutter/src/widgets/_window_macos.dart'
    show WindowControllerMacOS, WindowingOwnerMacOS;
import 'package:flutter/src/widgets/_window_win32.dart'
    show WindowControllerWin32;
import 'package:flutter/widgets.dart';
import 'package:otzaria/core/windowing/multiview/cocoa_view_window_native.dart';

/// האם אפשר לפתוח חלונות Dart נוספים באותו מנוע; בלעדיהם — חלון יחיד.
abstract final class MultiViewMode {
  static bool? _override;
  static bool _ownerInstalled = false;
  static bool _macRunnerReady = false;

  @visibleForTesting
  static bool? debugIsMacOS;

  static bool get _isMacOS => debugIsMacOS ?? Platform.isMacOS;

  /// ב-Windows וב-Linux תמיד ריבוי תצוגות. macOS רק אחרי אישור ה-runner
  /// ([awaitMacRunnerHandshake]); בלעדיו חלון יחיד.
  static bool get supported =>
      _isMacOS ? _macRunnerReady : Platform.isWindows || Platform.isLinux;

  /// רק אחרי ש-[installWindowingOwner] התקין בעלים אמיתי (לא בבדיקות).
  static bool get enabled => _override ?? (supported && _ownerInstalled);

  /// האם הותקן בעלים אמיתי לחלונות ה-Dart.
  static bool get ownerInstalled => _ownerInstalled;

  @visibleForTesting
  static set debugOverride(bool? value) => _override = value;

  @visibleForTesting
  static void debugResetOwnerInstalled() => _ownerInstalled = false;

  @visibleForTesting
  static void debugResetMacRunner() {
    _macRunnerReady = false;
    debugIsMacOS = null;
  }
}

/// macOS, לפני [installWindowingOwner]: ה-runner הפך את ריבוי התצוגות במנוע?
/// בלי זה החלון הראשון של Dart היה קורס על ה-assert של `enableMultiView`.
/// מחזיר null כשמוכן, ואחרת את הסיבה (חלון יחיד).
Future<String?> awaitMacRunnerHandshake({
  CocoaViewWindowNative native = const CocoaViewWindowNative(),
}) async {
  final reason = await native.multiViewUnavailableReason();
  MultiViewMode._macRunnerReady = reason == null;
  return reason;
}

/// macOS: ה-`NSWindow*` של החלון הראשי (התצוגה המרומזת); null כשאין.
int? implicitViewWindowHandle() {
  final view = WidgetsBinding.instance.platformDispatcher.implicitView;
  if (view == null) return null;
  final address = WindowingOwnerMacOS.getWindowHandle(view).address;
  return address == 0 ? null : address;
}

/// מדליק את דגל החלונות של המסגרת רק למשך [body]. מחוץ לו הדגל כבוי, ולכן
/// `showDialog` נשאר בתוך התצוגה ו-`MaterialApp` אינו עוטף ב-`WindowManager`.
T withWindowing<T>(T Function() body) {
  final previous = features.isWindowingEnabled;
  features.isWindowingEnabled = true;
  try {
    return body();
  } finally {
    features.isWindowingEnabled = previous;
  }
}

/// פעם אחת, אחרי אתחול ה-binding ולפני פתיחת חלון ראשון. מחזיר אם הותקן.
bool installWindowingOwner() {
  if (MultiViewMode._ownerInstalled) return true;
  if (!MultiViewMode.supported || !hasRealPlatformDispatcher()) return false;
  withWindowing(
    () =>
        WidgetsBinding.instance.windowingOwner = createDefaultWindowingOwner(),
  );
  return MultiViewMode._ownerInstalled = true;
}

/// binding של בדיקות מחזיר engineId=1, והמנוע מפרש אותו כמצביע וקורס.
/// TODO(upstream): TestPlatformDispatcher.engineId; GetEngineForId בלי בדיקה.
@visibleForTesting
bool hasRealPlatformDispatcher() {
  final dispatcher = WidgetsBinding.instance.platformDispatcher;
  return identical(dispatcher, PlatformDispatcher.instance) &&
      dispatcher.engineId != null;
}

/// חלון נייטיב שנוצר מ-Dart. עוטף את הבקר הפנימי כדי שהוא לא ידלוף החוצה.
class ViewWindowHandle {
  ViewWindowHandle._(this._controller, {required this._defersDestroy});

  @visibleForTesting
  ViewWindowHandle.forTesting(
    RegularWindowController controller, {
    this._defersDestroy = false,
  }) : _controller = controller;

  final RegularWindowController _controller;

  /// Linux 3.47.2: הריסה עם פריים בדרך קורסת (flutter#192873), ולכן קודם
  /// מסתירים ומפרקים את התצוגה, והורסים רק אחרי כמה פריימים.
  final bool _defersDestroy;
  bool _retiring = false;

  /// בהריסה נדחית: נקרא מיד, כדי להסתיר את החלון ולהוציא אותו מהעץ.
  VoidCallback? onRetire;

  FlutterView get view => _controller.rootView;

  /// גודל אזור הציור של החלון, ביחידות הלוגיות של מערכת ההפעלה.
  Size get logicalContentSize => _controller.contentSize;

  /// מודיע על שינוי גודל, הפעלה, כותרת ומגבלות; לא על הזזה בלבד.
  Listenable get changes => _controller;

  bool _destroyed = false;

  /// האם החלון כבר נהרס (WM_DESTROY).
  bool get isDestroyed => _destroyed;

  /// החלון העליון כמספר: HWND, `GtkWindow*` או `NSWindow*`; null אחרי ההריסה.
  int? get nativeHandle {
    final controller = _controller;
    if (_destroyed) return null;
    if (controller is WindowControllerWin32) {
      return (controller as WindowControllerWin32).windowHandle.address;
    }
    if (controller is WindowControllerLinux) {
      return (controller as WindowControllerLinux).windowHandle.address;
    }
    if (controller is WindowControllerMacOS) {
      return (controller as WindowControllerMacOS).windowHandle.address;
    }
    return null;
  }

  /// Linux: ה-`FlView*` של התצוגה; null מחוץ ל-Linux או אחרי ההריסה.
  int? get flutterViewHandle {
    final controller = _controller;
    if (_destroyed || controller is! WindowControllerLinux) return null;
    return (controller as WindowControllerLinux).flutterViewHandle.address;
  }

  /// ה-HWND של החלון העליון; null מחוץ ל-Windows או אחרי ההריסה.
  int? get hwnd {
    final controller = _controller;
    if (_destroyed || controller is! WindowControllerWin32) return null;
    return (controller as WindowControllerWin32).windowHandle.address;
  }

  bool get isActivated => !_destroyed && _controller.isActivated;
  bool get isMaximized => !_destroyed && _controller.isMaximized;
  bool get isMinimized => !_destroyed && _controller.isMinimized;
  bool get isFullscreen => !_destroyed && _controller.isFullscreen;

  void setTitle(String title) {
    if (!_destroyed) _controller.setTitle(title);
  }

  void setMaximized(bool value) {
    if (!_destroyed) _controller.setMaximized(value);
  }

  void setMinimized(bool value) {
    if (!_destroyed) _controller.setMinimized(value);
  }

  void setFullscreen(bool value) {
    if (!_destroyed) _controller.setFullscreen(value);
  }

  void setMinimumSize(Size size) {
    if (_destroyed) return;
    _controller.setConstraints(
      BoxConstraints(minWidth: size.width, minHeight: size.height),
    );
  }

  /// מותר לקרוא כמה פעמים; `onDestroyed` נקרא כשהחלון באמת נהרס.
  void destroy() {
    if (!_defersDestroy) return _controller.destroy();
    if (_retiring) return;
    _retiring = true;
    onRetire?.call();
    unawaited(_destroyAfterFrames());
  }

  /// הריסה נדחית שהתחילה: החלון כבר מחוץ לעץ וממתין להריסה.
  bool get isRetiring => _retiring;

  Future<void> _destroyAfterFrames() async {
    final scheduler = SchedulerBinding.instance;
    for (var i = 0; i < 3; i++) {
      // כפוי: חלון מוסתר עשוי להעביר את האפליקציה ל-hidden ולעצור פריימים.
      scheduler.scheduleForcedFrame();
      // בלי פריימים אין גם פריים בדרך, ואפשר להמשיך.
      await scheduler.endOfFrame.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () {},
      );
    }
    _controller.destroy();
  }

  /// אחרי WM_DESTROY: שאילתות מחזירות ערך ברירת מחדל ופעולות אינן עושות דבר.
  void markDestroyed() => _destroyed = true;

  void dispose() => _controller.dispose();
}

/// פותח חלון רגיל (את הכותרת מסיר ה-registry). מוסתר עד הפריים הראשון.
ViewWindowHandle createViewWindow({
  required Size size,
  required String title,
  required void Function(ViewWindowHandle handle) onCloseRequested,
  required void Function(ViewWindowHandle handle) onDestroyed,
}) {
  if (!MultiViewMode.ownerInstalled) {
    throw StateError('אין בעלים לחלונות Dart (installWindowingOwner לא הותקן)');
  }
  final delegate = _ViewWindowDelegate(onCloseRequested, onDestroyed);
  final controller = withWindowing(
    () => RegularWindowController(
      size: size,
      title: title,
      delegate: delegate,
    ),
  );
  return delegate.handle = ViewWindowHandle._(
    controller,
    defersDestroy: Platform.isLinux,
  );
}

// בלי super: מימושי ברירת המחדל זורקים כשהדגל כבוי, והוא כבוי כשהודעה מגיעה.
class _ViewWindowDelegate extends RegularWindowControllerDelegate {
  _ViewWindowDelegate(this._onCloseRequested, this._onDestroyed);

  final void Function(ViewWindowHandle handle) _onCloseRequested;
  final void Function(ViewWindowHandle handle) _onDestroyed;
  late final ViewWindowHandle handle;

  @override
  void onWindowCloseRequested(RegularWindowController controller) =>
      _onCloseRequested(handle);

  @override
  void onWindowDestroyed() => _onDestroyed(handle);
}

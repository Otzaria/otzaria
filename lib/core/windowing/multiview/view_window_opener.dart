// Intentional use of window_manager 0.6's legacy facade during the
// staged nativeapi migration; remove after moving these callers to Window.
// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'dart:ui' show Rect, Size;
import 'package:otzaria/core/messages/window_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/user_state/window_bounds.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/core/window_persistence.dart';
import 'package:otzaria/core/windowing/multiview/cocoa_view_window_native.dart';
import 'package:otzaria/core/windowing/multiview/gtk_view_window_native.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';
import 'package:otzaria/core/windowing/multiview/view_focus_sync.dart';
import 'package:otzaria/core/windowing/multiview/view_window_native.dart';
import 'package:otzaria/core/windowing/multiview/view_window_registry.dart';
import 'package:otzaria/core/windowing/new_window_placement.dart';
import 'package:otzaria/core/windowing/runner_window_channel.dart';
import 'package:otzaria/core/windowing/window_opener.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:window_manager/legacy.dart';

/// מסגרת מסך: macOS בנקודות גלובליות; Windows/Linux בפיקסלים פיזיים.
typedef PhysicalBounds = ({int left, int top, int width, int height});

/// חלון שנסגר ואפשר לשחזר ב-Ctrl+Shift+T: סשן של חלון Dart, או החלון הראשי.
class _ClosedWindow {
  const _ClosedWindow.view(this.session, {this.keptSlot}) : isMain = false;
  const _ClosedWindow.main() : session = null, keptSlot = null, isMain = true;

  final WindowSession? session;
  final bool isMain;

  /// המשבצת שהשורה שלה נשארה במסד (החלון האחרון במק); null כשנמחקה.
  final int? keptSlot;
}

/// פתיחת חלונות כחלונות Dart באותו מנוע (ריבוי תצוגות), במקום תהליך-מנוע
/// חדש לכל חלון. המשבצות נקבעות כאן, ולכן אין מרוץ על המשבצת הפנויה.
class ViewWindowOpener implements WindowOpener {
  ViewWindowOpener({
    this._registry,
    ViewWindowNative? native,
    this._sessions,
    Future<bool> Function()? isMainWindowVisible,
    Future<bool> Function()? restoreMainWindow,
    Size Function()? defaultSize,
    Future<int?> Function()? mainWindowHwnd,
    Future<bool> Function()? isMainWindowFullscreen,
    Future<void> Function()? showMainWindow,
    bool? keepsProcessAfterLastWindow,
    this.firstFrameTimeout = const Duration(seconds: 20),
  }) : _native = native ?? ViewWindowNative.platform(),
       _showMainWindow = showMainWindow ?? _windowManagerShow,
       keepsProcessAfterLastWindow =
           keepsProcessAfterLastWindow ?? (!kIsWeb && Platform.isMacOS),
       _isMainWindowVisible = isMainWindowVisible ?? windowManager.isVisible,
       _restoreMainWindow =
           restoreMainWindow ??
           const RunnerWindowChannel().restoreLastClosedWindow,
       _defaultSize = defaultSize ?? _implicitViewSize,
       _mainWindowHwnd = mainWindowHwnd ?? _windowManagerHwnd,
       _isMainWindowFullscreen =
           isMainWindowFullscreen ?? windowManager.isFullScreen;

  static final ViewWindowOpener instance = ViewWindowOpener();

  /// כמו ב-runner: מסגרת קטנה מזה אינה הצמדה אמיתית.
  static const int minBoundsWidth = 320;
  static const int minBoundsHeight = 240;

  /// כמה חלונות סגורים נזכרים לשחזור.
  static const int closedLimit = 10;

  final ViewWindowRegistry? _registry;
  final ViewWindowNative _native;
  final WindowSessionStore? _sessions;
  final Future<bool> Function() _isMainWindowVisible;
  final Future<bool> Function() _restoreMainWindow;
  final Size Function() _defaultSize;
  final Future<int?> Function() _mainWindowHwnd;
  final Future<bool> Function() _isMainWindowFullscreen;
  final Future<void> Function() _showMainWindow;
  final Duration firstFrameTimeout;

  /// macOS: סגירת החלון האחרון אינה יציאה; האפליקציה נשארת ב-Dock.
  final bool keepsProcessAfterLastWindow;

  ViewWindowRegistry get registry => _registry ?? ViewWindowRegistry.instance;
  WindowSessionStore get _store => _sessions ?? WindowSessionStore.instance;

  /// יציאה מהתוכנה כשנסגר החלון האחרון שעל המסך; נקבע ב-main.
  Future<void> Function()? endProcess;

  /// משבצות שממתינות לשחזור בהפעלה; חלון חדש אינו תופס אותן.
  final Set<int> _pendingRestore = {};
  final List<_ClosedWindow> _closed = [];
  Future<void> _queue = Future.value();
  Future<void> _closeQueue = Future.value();

  static Size _implicitViewSize() {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view == null || view.devicePixelRatio <= 0) {
      return const Size(1280, 800);
    }
    final size = view.physicalSize / view.devicePixelRatio;
    return size.isEmpty ? const Size(1280, 800) : size;
  }

  static Future<int?> _windowManagerHwnd() async {
    if (Platform.isMacOS) return implicitViewWindowHandle();
    try {
      // nativeapi Window.id is not an HWND/GtkWindow*. Ask the runner
      // for the raw handle used to parent secondary desktop windows.
      return await const RunnerWindowChannel().mainWindowHandle();
    } catch (e) {
      debugPrint('main window hwnd failed: $e');
      return null;
    }
  }

  static Future<void> _windowManagerShow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  /// חלון המקור: חלון Dart שבחזית, ואחרת הראשי; באותן יחידות כמו המתאם.
  Future<SourceWindowPlacement?> _sourceWindow() async {
    final foreground = await _native.foregroundWindow();
    final view = registry.windows
        .where((w) => w.handle.nativeHandle == foreground)
        .firstOrNull;
    final hwnd = view?.handle.nativeHandle ?? await _mainWindowHwnd();
    if (hwnd == null) return null;
    final placement = await _native.placement(hwnd);
    final area = await _native.workArea(hwnd);
    if (placement == null || area == null) return null;
    final maximized =
        placement.maximized ||
        (view?.handle.isFullscreen ?? await _isMainWindowFullscreen());
    var normal = placement.normal;
    final cocoa = _native is CocoaViewWindowNative;
    if (maximized &&
        (cocoa || (_native is GtkViewWindowNative && view == null))) {
      var saved = WindowBounds.decode(
        await _store.loadBoundsJson(view?.slot ?? 1),
      );
      if (cocoa && view == null && saved?.hasRect != true) {
        saved = await WindowPersistence.current.loadSavedBounds();
      }
      final bounds = saved?.toPhysical(screenPoints: cocoa);
      if (bounds != null) {
        normal = Rect.fromLTWH(
          bounds.left.toDouble(),
          bounds.top.toDouble(),
          bounds.width.toDouble(),
          bounds.height.toDouble(),
        );
      } else if (cocoa) {
        normal = placement.normal.topLeft & WindowPersistence.defaultSize;
      }
    }
    return SourceWindowPlacement(
      normal: _physical(normal),
      workArea: _physical(area),
      maximized: maximized,
      dpi: placement.dpi,
    );
  }

  static PhysicalRect _physical(Rect r) => (
    left: r.left.round(),
    top: r.top.round(),
    width: r.width.round(),
    height: r.height.round(),
  );

  static bool _isWindowSized(PhysicalBounds? bounds) =>
      bounds != null &&
      bounds.width >= minBoundsWidth &&
      bounds.height >= minBoundsHeight;

  /// פתיחה אחת בכל רגע: משבצת פנויה ומחיקת השארית שלה אינן מתנגשות.
  /// כשל הוא false, כמו במודל הקודם: הקוראים אינם מצפים לחריגה.
  Future<bool> _serialized(Future<bool> Function() body) {
    final result = _queue.then((_) => body()).catchError((Object e) {
      debugPrint('ViewWindowOpener failed: $e');
      return false;
    });
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// בדיקת החלון האחרון והסגירה חייבות להיות יחידה אחת בין כל החלונות.
  Future<bool> serializeClose(Future<bool> Function() close) {
    final result = _closeQueue.then((_) => close());
    _closeQueue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// התור חי מעבר לבדיקה, וממשיך ב-zone שבו נוצר; ב-FakeAsync של בדיקה אחרת
  /// הוא לא היה מתקדם לעולם.
  @visibleForTesting
  void resetCloseQueueForTest() => _closeQueue = Future.value();

  @override
  Future<bool> openWindow({
    OpenedTab? tab,
    ({int x, int y})? origin,
    PhysicalBounds? bounds,
    bool inheritPlacement = true,
  }) => _serialized(() async {
    if (!_canOpen) return false;
    final slot = registry.freeSlot(excluding: _pendingRestore);
    // שארית מקריסה במשבצת הזו אינה שייכת לחלון החדש.
    await _store.delete(slot);
    // בלי מסגרת שמורה: גודל חיצוני של המקור, ולא גודל התוכן ועוד כותרת.
    final source = _isWindowSized(bounds) || !inheritPlacement
        ? null
        : await _sourceWindow();
    var target = bounds;
    var maximized = false;
    Size? size;
    if (source != null && origin == null) {
      final cascade = cascadeNewWindowPlacement(source);
      target = cascade.bounds;
      maximized = cascade.maximized;
    } else if (source != null) {
      size = Size(
        source.normal.width.toDouble(),
        source.normal.height.toDouble(),
      );
    }
    return _open(
      slot: slot,
      tab: tab == null ? null : OpenedTab.fromJson(tab.toTransferJson()),
      origin: origin,
      bounds: target,
      size: size,
      maximized: maximized,
      deleteRowOnTimeout: true,
    );
  });

  @override
  Future<bool> openEmptyWindow() async {
    // חלון יחיד (בלי בעלים): האפשרות מוסתרת, ואין על מה לדווח.
    if (!MultiViewMode.enabled) return false;
    if (!await canOpenAnotherWindow()) {
      await reportOpenWindowFailure();
      return false;
    }
    final opened = await openWindow();
    if (!opened) await reportOpenWindowFailure();
    return opened;
  }

  /// שומר את [slots] לשחזור עוד לפני שהוא מתחיל, כדי שחלון חדש לא ימחק אותן.
  void reserveForRestore(Iterable<int> slots) => _pendingRestore.addAll(slots);

  /// "שחזר את כל החלונות": חלון לכל משבצת, עם הסשן והגבולות שלה. משבצת
  /// שנכשלה נשארת שמורה, כדי שהסשן שלה יאומץ בהפעלה הבאה ולא יימחק.
  Future<void> restoreAllWindows(List<int> slots) async {
    reserveForRestore(slots);
    for (final slot in slots) {
      if (!await _serialized(() => _openSession(slot))) {
        debugPrint('שחזור חלונות נעצר: פתיחת חלון למשבצת $slot נכשלה');
        return;
      }
      _pendingRestore.remove(slot);
    }
  }

  Future<bool> _openSession(int slot) async {
    if (registry.isSlotOpen(slot) || !_canOpen) {
      return false;
    }
    final saved = WindowBounds.decode(await _store.loadBoundsJson(slot));
    return _open(
      slot: slot,
      bounds: saved?.toPhysical(screenPoints: _native is CocoaViewWindowNative),
      maximized: saved?.maximized ?? false,
    );
  }

  @override
  Future<bool> restoreLastClosedWindow() => _serialized(() async {
    while (_closed.isNotEmpty) {
      final closed = _closed.last;
      if (closed.isMain) {
        // false: הראשי כבר גלוי, ממשיכים לחלון הקודם.
        if (await _restoreMainWindow()) {
          _closed.remove(closed);
          return true;
        }
        _closed.remove(closed);
        continue;
      }
      final session = closed.session!;
      if (!_canOpen) {
        await reportOpenWindowFailure();
        return false;
      }
      final slot = registry.freeSlot(excluding: _pendingRestore);
      await _store.delete(slot);
      // השורה שנשארה תשוחזר כאן; בלי זה ההפעלה הבאה הייתה פותחת אותה שוב.
      // משבצת שחלון חדש כבר תפס — השורה כבר שלו.
      final kept = closed.keptSlot;
      if (kept != null && kept != slot && !registry.isSlotOpen(kept)) {
        await _store.delete(kept);
      }
      await _store.save(
        slot,
        tabsJson: session.tabsJson,
        currentIndex: session.currentIndex,
      );
      if (session.activeWorkspaceId != null) {
        await _store.saveActiveWorkspace(slot, session.activeWorkspaceId);
      }
      if (session.boundsJson != null) {
        await _store.saveBounds(slot, session.boundsJson);
      }
      if (await _openSession(slot)) {
        _closed.remove(closed);
        return true;
      }
      // נכשל: השורה שנכתבה כאן אינה של אף חלון, והחלון נשאר לניסיון חוזר.
      await _store.delete(slot);
      return false;
    }
    return false;
  });

  @override
  Future<bool> canOpenAnotherWindow() async => _canOpen;

  /// בלי בעלים לחלונות Dart (integration_test) אין חלונות נוספים כלל.
  bool get _canOpen => MultiViewMode.enabled && registry.canOpenAnotherWindow;

  /// החלון הראשי נספר תמיד, גם מוסתר: הוא חי ותופס מקום בתקרה.
  @override
  Future<({int count, int max})?> windowCount() async => (
    count: registry.windows.length + 1,
    max: ViewWindowRegistry.maxWindows,
  );

  @override
  Future<void> reportOpenWindowFailure() async {
    final info = await windowCount();
    if (info != null && info.count >= info.max) {
      UiSnack.show(WindowMessages.windowLimitReached(info.max));
    } else {
      UiSnack.showError(WindowMessages.openWindowFailed);
    }
  }

  Future<bool> _open({
    required int slot,
    OpenedTab? tab,
    ({int x, int y})? origin,
    PhysicalBounds? bounds,
    Size? size,
    bool maximized = false,
    bool deleteRowOnTimeout = false,
  }) async {
    final entry = registry.open(
      size: _defaultSize(),
      initialTab: tab,
      slot: slot,
    );
    if (entry == null) {
      tab?.dispose();
      return false;
    }
    try {
      await _place(entry, origin: origin, bounds: bounds, size: size);
      await entry.firstFrame.timeout(firstFrameTimeout);
      bool live() =>
          registry.windows.contains(entry) &&
          !entry.isClosing &&
          !entry.handle.isRetiring;
      if (!live()) return false;
      if (maximized) entry.handle.setMaximized(true);
      final hwnd = entry.handle.nativeHandle;
      if (hwnd == null) throw StateError('View window has no native handle');
      await _native.reveal(hwnd);
      if (!live()) return false;
      ViewFocusSync.viewWindowRevealed(entry.handle.view.viewId);
      return true;
    } catch (error) {
      debugPrint('View window failed to open: $error');
      entry.endSession();
      entry.takeInitialTab()?.dispose();
      entry.handle.destroy();
      if (deleteRowOnTimeout) await _store.delete(slot);
      return false;
    }
  }

  /// לפני הפריים הראשון, כשהחלון עוד מוסתר. בלי מיקום — ברירת המחדל של המערכת.
  /// [size] היא המסגרת החיצונית לחלון שנפתח ב-[origin]; בלעדיה — הגודל הנוכחי.
  Future<void> _place(
    ViewWindowEntry entry, {
    ({int x, int y})? origin,
    PhysicalBounds? bounds,
    Size? size,
  }) async {
    final hwnd = entry.handle.nativeHandle;
    if (hwnd == null) return;
    if (bounds != null && _isWindowSized(bounds)) {
      final target = Rect.fromLTWH(
        bounds.left.toDouble(),
        bounds.top.toDouble(),
        bounds.width.toDouble(),
        bounds.height.toDouble(),
      );
      await _native.setWindowRect(hwnd, target);
      // מסך עם DPI אחר משנה את הגודל ב-WM_DPICHANGED; שם כבר אין שינוי.
      if (await _native.windowRect(hwnd) != target) {
        await _native.setWindowRect(hwnd, target);
      }
      return;
    }
    if (origin == null) return;
    final current = size ?? (await _native.windowRect(hwnd))?.size;
    if (current == null) return;
    final x = origin.x.toDouble(), y = origin.y.toDouble();
    await _native.setWindowRect(
      hwnd,
      Rect.fromLTWH(x, y, current.width, current.height),
    );
    // המעבר למסך אחר עשוי לשנות את הגודל לפי ה-DPI שלו; מהדקים אחריו.
    final moved =
        await _native.windowRect(hwnd) ??
        Rect.fromLTWH(x, y, current.width, current.height);
    final area = await _native.workArea(hwnd);
    if (area == null) return;
    await _native.setWindowRect(hwnd, clampToArea(moved, area));
  }

  /// מזיז את המסגרת לתוך אזור העבודה, ומקטין אותה כשאינה נכנסת.
  @visibleForTesting
  static Rect clampToArea(Rect rect, Rect area) {
    final width = rect.width.clamp(0.0, area.width);
    final height = rect.height.clamp(0.0, area.height);
    var left = rect.left, top = rect.top;
    if (left + width > area.right) left = area.right - width;
    if (left < area.left) left = area.left;
    if (top + height > area.bottom) top = area.bottom - height;
    if (top < area.top) top = area.top;
    return Rect.fromLTWH(left, top, width, height);
  }

  /// האם [entry] הוא החלון האחרון שעל המסך, כלומר סגירתו היא יציאה.
  Future<bool> isLastVisibleWindow(ViewWindowEntry entry) async {
    if (registry.windows.any((w) => w != entry)) return false;
    try {
      return !await _isMainWindowVisible();
    } catch (e) {
      // לא ידוע: לא לצאת, החלון נסגר לבדו.
      debugPrint('isMainWindowVisible failed: $e');
      return false;
    }
  }

  /// נקרא אחרי ה-flush ולפני מחיקת הסשן, כדי ש-Ctrl+Shift+T יחזיר אותו.
  /// [keptRow]: הסשן אינו נמחק (החלון האחרון במק).
  Future<void> rememberClosed(int slot, {bool keptRow = false}) async {
    try {
      final session = await _store.load(slot);
      if (session != null) {
        _push(_ClosedWindow.view(session, keptSlot: keptRow ? slot : null));
      }
    } catch (e) {
      debugPrint('rememberClosed failed: $e');
    }
  }

  /// לפני הסתרת החלון הראשי: חלון שעוד נפתח מוסתר עד הפריים הראשון,
  /// וה-runner משאיר את התהליך חי רק בזכות חלון Dart גלוי.
  Future<void> beforeMainWindowHides() async {
    _push(const _ClosedWindow.main());
    Future<void> pending;
    do {
      pending = _queue;
      await pending;
    } while (!identical(pending, _queue));
  }

  /// יציאה מהתוכנה, אחרי השטיפה: הסשנים נשארים להפעלה הבאה והחלונות נהרסים.
  /// הסשן מסתיים קודם: המסדים כבר נסגרו, ופירוק העץ לא יפתח אותם מחדש.
  void destroyAllForQuit() {
    for (final entry in registry.windows) {
      entry.endSession();
      entry.handle.destroy();
    }
  }

  /// macOS: לחיצה על ה-Dock כשאין חלון גלוי. true תמיד, חוץ מכשל.
  Future<bool> reopenFromDock() async {
    if (await restoreLastClosedWindow()) return true;
    if (await _restoreMainWindow()) return true;
    await _showMainWindow();
    return true;
  }

  void _push(_ClosedWindow closed) {
    _closed.add(closed);
    if (_closed.length > closedLimit) _closed.removeAt(0);
  }

  @visibleForTesting
  int get closedCountForTest => _closed.length;

  @visibleForTesting
  Set<int> get pendingRestoreForTest => Set.unmodifiable(_pendingRestore);
}

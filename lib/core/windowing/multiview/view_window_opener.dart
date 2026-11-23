import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
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
import 'package:otzaria/core/windowing/multiview/window_event_log.dart';
import 'package:otzaria/core/windowing/new_window_placement.dart';
import 'package:otzaria/core/windowing/runner_window_channel.dart';
import 'package:otzaria/core/windowing/window_opener.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:window_manager/window_manager.dart';

/// מסגרת מסך: macOS בנקודות גלובליות; Windows/Linux בפיקסלים פיזיים.
typedef PhysicalBounds = ({int left, int top, int width, int height});

/// חלון שנסגר ואפשר לשחזר ב-Ctrl+Shift+T: סשן של חלון Dart, או החלון הראשי.
class _ClosedWindow {
  const _ClosedWindow.view(WindowSession this.session, {this.keptSlot})
    : isMain = false;
  const _ClosedWindow.main(this.session, {this.keptSlot}) : isMain = true;

  /// הסשן לשחזור; בראשי האחרון במק הסשן נשאר במשבצת.
  final WindowSession? session;
  final bool isMain;

  /// משבצת שנשארה במסד, בגלל כשל כתיבה או סגירת החלון האחרון במק.
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
  bool _savedClosedLoaded = false;
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
      // ל-window_manager אין getId ב-Linux; ה-runner מחזיר את ה-GtkWindow*.
      if (Platform.isLinux) {
        return await const MethodChannel(
          'otzaria/multiwindow',
        ).invokeMethod<int>('mainWindowHandle');
      }
      return await windowManager.getId();
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
      WindowEventLog.instance.addFailure('openerFailed', e);
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

  /// מאפס את המופע המשותף בין בדיקות שמשתמשות במסד וב-FakeAsync נפרדים.
  @visibleForTesting
  void resetForTest() {
    _queue = Future.value();
    _closeQueue = Future.value();
    _closed.clear();
    _pendingRestore.clear();
    _savedClosedLoaded = false;
  }

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
        WindowEventLog.instance.add('restoreStopped', {'slot': slot});
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
    try {
      await _loadSavedClosed();
    } catch (error) {
      debugPrint('load closed windows failed: $error');
    }
    for (final closed in _closed.reversed.toList()) {
      if (closed.isMain) {
        // בקשת הצגה יכולה להגיע לפני שה-runner הספיק להסתיר את הראשי.
        if (!await _restoreMainWindow()) continue;
        await _activateMain(closed);
        return true;
      }
      if (!_canOpen) {
        await reportOpenWindowFailure();
        return false;
      }
      return _restoreClosedView(closed);
    }
    return false;
  });

  Future<bool> _restoreClosedView(_ClosedWindow closed) async {
    final kept = closed.keptSlot;
    final slot = !_savedClosedLoaded && kept != null
        ? kept
        : registry.freeSlot(excluding: {..._pendingRestore}..remove(kept));
    if (slot == kept) {
      if (!await _openSession(slot)) return false;
      _pendingRestore.remove(slot);
      _closed.remove(closed);
      return true;
    }

    final original = _closed.toList();
    await _replaceClosed(
      original.where((entry) => entry != closed).toList(),
      removeSlot: kept,
      activate: closed.session!.atSlot(slot),
    );
    if (kept != null) _pendingRestore.remove(kept);

    var opened = false;
    try {
      return opened = await _openSession(slot);
    } finally {
      if (!opened) {
        await _rollbackRestore(original, closed, slot);
      }
    }
  }

  Future<void> _rollbackRestore(
    List<_ClosedWindow> original,
    _ClosedWindow closed,
    int slot,
  ) async {
    final kept = closed.keptSlot;
    try {
      await _replaceClosed(
        original,
        removeSlot: slot,
        activate: kept == null ? null : closed.session!.atSlot(kept),
      );
      if (kept != null) _pendingRestore.add(kept);
    } catch (error) {
      debugPrint('window restore rollback failed: $error');
      _pendingRestore.add(slot);
      _setClosed([
        for (final entry in original)
          if (entry == closed)
            _ClosedWindow.view(closed.session!, keptSlot: slot)
          else
            entry,
      ]);
    }
  }

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
    WindowEventLog.instance.add('openRefused', {
      'count': info?.count,
      'max': info?.max,
    });
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
    final log = WindowEventLog.instance;
    log.add('open', {
      'slot': slot,
      'created': entry != null,
      'withTab': tab != null,
      'maximized': maximized,
      if (bounds != null) ...{
        'requestedBounds': bounds.toString(),
        'requestedBoundsUnit': _native is CocoaViewWindowNative
            ? 'screenPoints'
            : 'physicalPixels',
      },
    });
    if (entry == null) {
      tab?.dispose();
      return false;
    }
    final watch = Stopwatch()..start();
    try {
      await _place(entry, origin: origin, bounds: bounds, size: size);
      await entry.firstFrame.timeout(firstFrameTimeout);
      log.add('firstFrame', {'slot': slot, 'ms': watch.elapsedMilliseconds});
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
      log.add('revealed', {'slot': slot, 'ms': watch.elapsedMilliseconds});
      return true;
    } catch (error) {
      debugPrint('View window failed to open: $error');
      log.addFailure('openFailed', error, {
        'slot': slot,
        'ms': watch.elapsedMilliseconds,
      });
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

  /// מעביר סשן של חלון שסיים לשמור לרשימת השחזור.
  Future<bool> rememberClosed(int slot, {bool keptRow = false}) =>
      _serialized(() async {
        try {
          final session = await _store.load(slot);
          if (session == null) return true;
          if (keptRow) _pendingRestore.add(slot);
          return await _recordClose(
            _ClosedWindow.view(session, keptSlot: keptRow ? slot : null),
            removeSlot: keptRow ? null : slot,
          );
        } catch (error) {
          _pendingRestore.add(slot);
          debugPrint('rememberClosed failed: $error');
          return false;
        }
      });

  /// ממתין לחלונות שנפתחים ושומר את הסשן של הראשי לפני ההסתרה.
  Future<bool> beforeMainWindowHides({int? slot}) => _serialized(() async {
    WindowSession? session;
    if (slot != null) {
      try {
        session = await _store.load(slot);
      } catch (error) {
        debugPrint('load main window session failed: $error');
        await _recordClose(const _ClosedWindow.main(null));
        return false;
      }
    }
    return _recordClose(
      _ClosedWindow.main(session),
      removeSlot: session == null ? null : slot,
    );
  });

  /// מחזיר את הסשן לשורת הראשי כשה-runner הציג אותו מחדש.
  Future<bool> mainWindowShown() => _serialized(() async {
    final main = _closed.where((entry) => entry.isMain).lastOrNull;
    if (main == null) return true;
    return _activateMain(main);
  });

  Future<bool> _activateMain(_ClosedWindow main) async {
    final session = main.session;
    if (session == null || main.keptSlot != null) {
      _closed.remove(main);
      return true;
    }
    try {
      await _replaceClosed(
        _closed.where((entry) => entry != main).toList(),
        activate: session,
      );
      return true;
    } catch (error) {
      debugPrint('restore main window session failed: $error');
      return false;
    }
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

  Future<bool> _recordClose(_ClosedWindow closed, {int? removeSlot}) async {
    List<_ClosedWindow> withEntry(_ClosedWindow entry) {
      final next = [
        for (final previous in _closed)
          if (!entry.isMain || !previous.isMain || entry.session == null)
            previous,
        entry,
      ];
      if (next.length > closedLimit) next.removeAt(0);
      return next;
    }

    try {
      await _loadSavedClosed();
      await _replaceClosed(withEntry(closed), removeSlot: removeSlot);
      return true;
    } catch (error) {
      debugPrint('save closed windows failed: $error');
      if (removeSlot == null) {
        _setClosed(withEntry(closed));
      } else if (closed.isMain) {
        _setClosed(
          withEntry(_ClosedWindow.main(closed.session, keptSlot: removeSlot)),
        );
      } else {
        _pendingRestore.add(removeSlot);
        _setClosed(
          withEntry(_ClosedWindow.view(closed.session!, keptSlot: removeSlot)),
        );
      }
      return false;
    }
  }

  /// טוען את ההיסטוריה בשימוש הראשון, בלי להמתין לה באתחול.
  Future<void> _loadSavedClosed() async {
    if (_savedClosedLoaded) return;
    final saved = await _store.loadClosed();
    _closed.insertAll(0, [
      for (final session in saved) _ClosedWindow.view(session),
    ]);
    if (_closed.length > closedLimit) {
      _closed.removeRange(0, _closed.length - closedLimit);
    }
    _savedClosedLoaded = true;
  }

  Future<void> _replaceClosed(
    List<_ClosedWindow> next, {
    int? removeSlot,
    WindowSession? activate,
  }) async {
    await _store.saveClosed(
      [
        for (final entry in next)
          if (entry.session case final session? when entry.keptSlot == null)
            session,
      ],
      removeSlot: removeSlot,
      activate: activate,
    );
    _setClosed(next);
  }

  void _setClosed(List<_ClosedWindow> next) {
    _closed
      ..clear()
      ..addAll(next);
  }

  @visibleForTesting
  int get closedCountForTest => _closed.length;

  @visibleForTesting
  Set<int> get pendingRestoreForTest => Set.unmodifiable(_pendingRestore);
}

import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/multiview/host_window_app_window_controller.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';
import 'package:otzaria/core/windowing/multiview/view_window_native.dart';
import 'package:otzaria/core/windowing/multiview/window_event_log.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';

/// יוצר חלון נייטיב; ניתן להחלפה בבדיקות.
typedef ViewWindowFactory =
    ViewWindowHandle Function({
      required Size size,
      required String title,
      required void Function(ViewWindowHandle handle) onCloseRequested,
      required void Function(ViewWindowHandle handle) onDestroyed,
    });

/// חלון Dart פתוח. [slot] הוא משבצת הסשן שלו (1 שמורה לחלון הראשי).
/// חי מעל RestartWidget: הבקר, המפתחות והסשן שורדים אתחול מחדש.
class ViewWindowEntry {
  ViewWindowEntry._(
    this.slot,
    this.handle,
    ViewWindowNative native,
    OpenedTab? initialTab,
  ) : id = AppWindowId('window-view-$slot'),
      openedWithTab = initialTab != null,
      _initialTab = initialTab {
    keys = AppWindowKeys(id: id);
    // אחרי סיום הסשן החלון אינו שומר: סגירת ה-blocs הייתה יוצרת אותו מחדש.
    tabsSession = WindowTabsSession(slot: () => _sessionEnded ? null : slot);
    controller = HostWindowAppWindowController(
      id: id,
      handle: handle,
      onClose: requestClose,
      native: native,
    );
  }

  final int slot;
  final ViewWindowHandle handle;
  final AppWindowId id;
  late final AppWindowKeys keys;
  late final WindowTabsSession tabsSession;
  late final HostWindowAppWindowController controller;

  /// האם החלון נפתח עם כרטיסיה, כלומר ישר למסך הקריאה.
  final bool openedWithTab;
  OpenedTab? _initialTab;
  bool _sessionEnded = false;

  final Completer<void> _firstFrame = Completer<void>();
  final DateTime openedAt = DateTime.now();

  /// מסתיים בפריים הראשון של החלון.
  Future<void> get firstFrame => _firstFrame.future;

  void markFirstFrame() {
    if (!_firstFrame.isCompleted) _firstFrame.complete();
  }

  /// הכרטיסיה שהחלון נפתח איתה, פעם אחת: אתחול מחדש לא יוסיף אותה שוב.
  OpenedTab? takeInitialTab() {
    final tab = _initialTab;
    _initialTab = null;
    return tab;
  }

  /// מכאן החלון אינו כותב לסשן שלו.
  void endSession() => _sessionEnded = true;

  /// סגירה שאושרה: כרטיסיה שתועבר לחלון מעכשיו תאבד איתו.
  bool get isClosing => _closing || _sessionEnded;
  bool _closing = false;
  set closing(bool value) => _closing = value;

  /// מסלול הסגירה של החלון, כשהעץ שלו מורכב; בלעדיו — הריסה ישירה.
  Future<void> Function()? closeHandler;

  /// סגירה מבוקשת (X, Alt+F4, `close()`).
  Future<void> requestClose() async {
    final handler = closeHandler;
    if (handler != null) return handler();
    handle.destroy();
  }
}

/// רשימת חלונות ה-Dart של התהליך. יושבת מעל RestartWidget, כדי שהחלונות
/// ישרדו אתחול מחדש ורק העצים שבתוכם ייבנו מחדש.
class ViewWindowRegistry extends ChangeNotifier {
  ViewWindowRegistry({ViewWindowFactory? factory, ViewWindowNative? native})
    : _factory = factory ?? createViewWindow,
      _native = native ?? ViewWindowNative.platform();

  static final ViewWindowRegistry instance = ViewWindowRegistry();

  /// תקרה רכה, כולל החלון הראשי.
  static const int maxWindows = 8;

  final ViewWindowFactory _factory;
  final ViewWindowNative _native;
  final List<ViewWindowEntry> _windows = [];

  List<ViewWindowEntry> get windows => List.unmodifiable(_windows);

  bool get canOpenAnotherWindow => _windows.length + 1 < maxWindows;

  /// פותח חלון, עם [initialTab] אם ניתנה; null בתקרה או כש-[slot] תפוסה.
  ViewWindowEntry? open({
    required Size size,
    String title = 'אוצריא',
    OpenedTab? initialTab,
    int? slot,
  }) {
    if (!canOpenAnotherWindow) return null;
    if (slot != null && isSlotOpen(slot)) return null;
    late final ViewWindowEntry entry;
    final handle = _factory(
      size: size,
      title: title,
      onCloseRequested: (_) => unawaited(entry.requestClose()),
      onDestroyed: (_) => _remove(entry),
    );
    entry = ViewWindowEntry._(
      slot ?? freeSlot(),
      handle,
      _native,
      initialTab,
    );
    handle.onRetire = () => _retire(entry);
    AppWindowKeys.register(entry.keys);
    _windows.add(entry);
    notifyListeners();
    final hwnd = handle.nativeHandle;
    if (hwnd != null) {
      unawaited(_native.installViewHooks(hwnd));
      // לפני הפריים הראשון, בעוד החלון מוסתר: בלי הבהוב של המסגרת.
      unawaited(_native.makeFrameless(hwnd));
    }
    return entry;
  }

  /// מצב חלונות ה-Dart לדוח, כולל מידות התצוגה ואזור התוכן.
  Future<List<Map<String, Object?>>> describe() async {
    final result = <Map<String, Object?>>[];
    for (final entry in _windows.toList()) {
      final handle = entry.handle;
      if (handle.isDestroyed) continue;
      final hwnd = handle.nativeHandle;
      final view = handle.view;
      final physicalSize = view.physicalSize;
      final contentSize = handle.logicalContentSize;
      result.add({
        'slot': entry.slot,
        'aliveMs': DateTime.now().difference(entry.openedAt).inMilliseconds,
        'firstFrame': entry._firstFrame.isCompleted,
        'closing': entry.isClosing,
        'maximized': handle.isMaximized,
        'minimized': handle.isMinimized,
        'viewSizePx': '${physicalSize.width}x${physicalSize.height}',
        'viewDevicePixelRatio': view.devicePixelRatio,
        'windowContentSizeLogical':
            '${contentSize.width}x${contentSize.height}',
        'visible': hwnd == null ? null : await _native.isVisible(hwnd),
      });
    }
    return result;
  }

  bool isSlotOpen(int slot) => _windows.any((w) => w.slot == slot);

  /// המשבצת הפנויה הראשונה מ-2, בלי [excluding] (משבצות שממתינות לשחזור).
  int freeSlot({Set<int> excluding = const {}}) {
    final used = {for (final w in _windows) w.slot, ...excluding};
    var slot = 2;
    while (used.contains(slot)) {
      slot++;
    }
    return slot;
  }

  void _remove(ViewWindowEntry entry) {
    if (!_detach(entry) && !entry.handle.isRetiring) return;
    // הבקר משוחרר רק אחרי שהעץ שלו פורק בפריים הבא.
    SchedulerBinding.instance.addPostFrameCallback(
      (_) => entry.handle.dispose(),
    );
    SchedulerBinding.instance.scheduleFrame();
  }

  /// הריסה נדחית: החלון יוצא מהרשימה ומהעץ ומוסתר עכשיו, ונהרס אחר כך.
  void _retire(ViewWindowEntry entry) {
    final native = entry.handle.nativeHandle;
    _detach(entry);
    if (native != null) _native.hide(native);
  }

  bool _detach(ViewWindowEntry entry) {
    if (!_windows.remove(entry)) return false;
    WindowEventLog.instance.add('closed', {
      'slot': entry.slot,
      'firstFrame': entry._firstFrame.isCompleted,
      'aliveMs': DateTime.now().difference(entry.openedAt).inMilliseconds,
    });
    entry.handle.markDestroyed();
    entry.endSession();
    entry.closeHandler = null;
    AppWindowKeys.unregister(entry.keys);
    notifyListeners();
    return true;
  }
}

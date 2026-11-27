import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/core/user_state/user_state_slot.dart';
import 'package:otzaria/core/user_state/window_bounds.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/window_manager_app_window_controller.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:screen_retriever/screen_retriever.dart';

/// שמירה ושחזור של גבולות החלון הראשי.
///
/// חזית סטטית בלי מצב: המצב יושב ב-[WindowPersistenceBinding] של החלון.
class WindowPersistence {
  static const _kLeft = 'window_bounds_left';
  static const _kTop = 'window_bounds_top';
  static const _kWidth = 'window_bounds_width';
  static const _kHeight = 'window_bounds_height';
  static const _kDpr = 'window_bounds_dpr';
  static const _kIsMaximized = 'window_is_maximized';

  static const double _minWidth = 420;
  static const double _minHeight = 400;
  static const Size minSize = Size(_minWidth, _minHeight);
  static const Size defaultSize = Size(1280, 720);
  static const Duration _debounceDuration = Duration(milliseconds: 400);

  /// גובה רצועת האחיזה (פס הכותרת המותאם) בפיקסלים לוגיים. בדיקת הנגישות
  /// דורשת שהרצועה הזו — לא סתם פינת חלון — תהיה על מסך חי, אחרת אין מה לגרור.
  static const double _grabStripExtent = 32;

  /// המסגרת הבלתי נראית ש-Windows מוסיף סביב חלון (7px ב-96 DPI) — חלון
  /// מוצמד לקצה המסך חורג בה משטח העבודה, וזה לא כיסוי של שורת המשימות.
  static const double _invisibleFrameExtent = 8;

  /// החלון הראשי; לכל חלון Dart נוסף [WindowPersistenceBinding] משלו.
  static final WindowPersistenceBinding current = WindowPersistenceBinding();

  /// האם החלון הראשי עדיין בשלב הפתיחה הנייטיבי.
  static bool get splashMode => current._splashMode;
  static set splashMode(bool value) => current.splashMode = value;

  /// קושר את החלון הראשי. נקרא פעם אחת מ-`main`, עם אותו מופע
  /// שנכנס ל-[AppWindowScope] — כדי שיהיה מקור אמת אחד.
  static void bindWindow({
    required AppWindowController controller,
    required AppWindowGeometry geometry,
  }) => current.bindWindow(controller: controller, geometry: geometry);

  static bool get isRestoring => current.isRestoring;

  static Future<void> restoreIfAny() => current.restoreIfAny();

  static Future<void> applyRestoredBounds() => current.applyRestoredBounds();

  static Future<void> applyPendingMaximize() => current.applyPendingMaximize();

  static Future<void> applyPendingFullscreen() =>
      current.applyPendingFullscreen();

  static void scheduleSave() => current.scheduleSave();

  /// ה-DPR שאיתו window_manager ממיר לוגי→פיזי (window.devicePixelRatio);
  /// שימוש באותו מקור מבטיח שההמרות מתבטלות במדויק.
  static double _currentDevicePixelRatio() =>
      _validDevicePixelRatio(PlatformDispatcher.instance.implicitView);

  static double _validDevicePixelRatio(FlutterView? view) {
    final dpr = view?.devicePixelRatio;
    return (dpr != null && dpr > 0) ? dpr : 1.0;
  }

  static Rect _scaleRect(Rect rect, double factor) => Rect.fromLTWH(
    rect.left * factor,
    rect.top * factor,
    rect.width * factor,
    rect.height * factor,
  );

  /// Convert a screen work area to physical coordinates when the display
  /// reports finite, usable geometry. Invalid monitor data must not make a
  /// previously reachable window appear off-screen during restoration.
  @visibleForTesting
  static Rect? physicalWorkAreaOrNull(
    Rect logicalWorkArea,
    double scaleFactor,
  ) {
    if (!scaleFactor.isFinite ||
        scaleFactor <= 0 ||
        logicalWorkArea.width <= 0 ||
        logicalWorkArea.height <= 0 ||
        !logicalWorkArea.left.isFinite ||
        !logicalWorkArea.top.isFinite ||
        !logicalWorkArea.right.isFinite ||
        !logicalWorkArea.bottom.isFinite) {
      return null;
    }

    final physical = _scaleRect(logicalWorkArea, scaleFactor);
    return physical.left.isFinite &&
            physical.top.isFinite &&
            physical.right.isFinite &&
            physical.bottom.isFinite
        ? physical
        : null;
  }

  /// האם רצועת האחיזה — [stripExtent] העליונים של [bounds] — מונחת במלואה
  /// (לגובהה) ולרוחב [stripExtent] לפחות על אחד מ-[displayRects]. גבולות
  /// שנשמרו בטעות כשהחלון ממוזער (חניה ב--32000, ראה `_saveNow`), מסך שנותק,
  /// או חלון שרק תחתיתו מציצה למסך — נכשלים כאן.
  @visibleForTesting
  static bool titleStripReachableOnAnyDisplay(
    Rect bounds,
    List<Rect> displayRects,
    double stripExtent,
  ) {
    final strip = Rect.fromLTWH(
      bounds.left,
      bounds.top,
      bounds.width,
      stripExtent,
    );
    for (final displayRect in displayRects) {
      final overlap = strip.intersect(displayRect);
      if (overlap.width >= stripExtent && overlap.height >= stripExtent) {
        return true;
      }
    }
    return false;
  }

  static Rect _fitOverTaskbar(
    Rect bounds,
    Rect screen,
    Rect workArea,
    double scale,
  ) {
    // ScreenRetriever rounds logical coordinates before we convert them back.
    final tolerance = (_invisibleFrameExtent + 1) * scale;
    final tolerated = workArea.inflate(tolerance);
    if (screen.inflate(scale).intersect(workArea) != workArea ||
        screen.inflate(tolerance).intersect(bounds) != bounds ||
        tolerated.intersect(bounds) == bounds ||
        workArea.width < minSize.width * scale ||
        workArea.height < minSize.height * scale) {
      return bounds;
    }

    final width = math.min(bounds.width, workArea.width);
    final height = math.min(bounds.height, workArea.height);
    final fitsHorizontally =
        bounds.left >= tolerated.left && bounds.right <= tolerated.right;
    final fitsVertically =
        bounds.top >= tolerated.top && bounds.bottom <= tolerated.bottom;
    return Rect.fromLTWH(
      fitsHorizontally
          ? bounds.left
          : bounds.left.clamp(workArea.left, workArea.right - width),
      fitsVertically
          ? bounds.top
          : bounds.top.clamp(workArea.top, workArea.bottom - height),
      fitsHorizontally ? bounds.width : width,
      fitsVertically ? bounds.height : height,
    );
  }
}

/// שמירה ושחזור של גבולות חלון אחד, עם המצב של החלון הזה בלבד.
///
/// המשבצת נקבעת בכל קריאה, כי החלון תופס אותה רק אחרי שהמופע נוצר.
class WindowPersistenceBinding {
  WindowPersistenceBinding({
    AppWindowController controller = const WindowManagerAppWindowController(),
    this._geometry = const WindowManagerAppWindowController(),
    int? Function()? slot,
    this._sessions,
    double Function()? devicePixelRatio,
    FlutterView? view,
  }) : _window = controller,
       _slot = slot ?? (() => UserStateSlot.main),
       _devicePixelRatio =
           devicePixelRatio ??
           (view == null
               ? WindowPersistence._currentDevicePixelRatio
               : () => WindowPersistence._validDevicePixelRatio(view));

  final int? Function() _slot;

  /// ה-DPR של התצוגה שהחלון הזה מוצג בה ([view], נקרא בכל שימוש); ברירת
  /// המחדל היא ה-implicit view.
  final double Function() _devicePixelRatio;
  final WindowSessionStore? _sessions;

  WindowSessionStore get _store => _sessions ?? WindowSessionStore.instance;

  /// הגבולות של החלון הזה מהסשן שלו; בהיעדרם — מפתחות ההגדרות הישנים,
  /// שבהם נשמרו גבולות החלון היחיד לפני שכל חלון קיבל סשן.
  Future<WindowBounds> loadSavedBounds() async {
    final slot = _slot();
    // בהפעלה ראשונה אין עדיין ספרייה, ופתיחת המסד הייתה יוצרת אותו במיקום
    // ברירת מחדל לפני שהמשתמש בחר; גם אין שם גבולות לקרוא.
    final hasLibrary =
        (Settings.getValue<String>(SettingsRepository.keyLibraryPath) ?? '')
            .isNotEmpty;
    if (slot != null && hasLibrary) {
      final bounds = WindowBounds.decode(await _store.loadBoundsJson(slot));
      if (bounds != null) return bounds;
    }
    return WindowBounds(
      left: Settings.getValue<double>(WindowPersistence._kLeft),
      top: Settings.getValue<double>(WindowPersistence._kTop),
      width: Settings.getValue<double>(WindowPersistence._kWidth),
      height: Settings.getValue<double>(WindowPersistence._kHeight),
      dpr: Settings.getValue<double>(WindowPersistence._kDpr),
      maximized:
          Settings.getValue<bool>(WindowPersistence._kIsMaximized) ?? false,
    );
  }

  Timer? _debounce;
  bool _restored = false;
  bool _isRestoring = false;
  bool _pendingMaximize = false;
  bool _pendingFullscreen = false;

  /// גבולות לשחזור לפני החשיפה: macOS בנקודות מסך, ובשאר בפיקסלים פיזיים.
  /// null בהפעלה ראשונה — יוחל גודל ברירת מחדל.
  Rect? _restoredPhysicalBounds;

  /// ה-devicePixelRatio של רגע השמירה — הגבולות נשמרים לוגיים (כפי ש-getBounds
  /// מחזיר), וה-DPR הזה מאפשר לשחזר את הפיזי במדויק גם אם ה-DPR הנוכחי שונה.
  double? _restoredDpr;

  /// בזמן מסך הפתיחה החלון קטן/שקוף; אסור לשמור את גודלו (אחרת ההפעלה הבאה
  /// "תשחזר" חלון זעיר). כשהדגל דלוק, [scheduleSave] הוא no-op.
  /// זהו גם המנגנון שמונע שמירת גודל ה-splash מלכתחילה — ולכן אין צורך ב-clamp
  /// "שפיות" בשחזור (שפגע בחלונות קטנים חוקיים כמו 500x420).
  bool _splashMode = false;
  set splashMode(bool value) => _splashMode = value;

  /// החלון שהמופע פועל עליו.
  ///
  /// ברירת המחדל היא החלון הראשי, כדי שקריאה מוקדמת ומהבדיקות תמשיך לעבוד
  /// בלי הזרקה.
  AppWindowController _window;
  AppWindowGeometry _geometry;

  /// קושר את המופע לחלון, עם אותו מופע שנכנס ל-[AppWindowScope].
  void bindWindow({
    required AppWindowController controller,
    required AppWindowGeometry geometry,
  }) {
    _window = controller;
    _geometry = geometry;
  }

  bool get isRestoring => _isRestoring;

  Future<void> restoreIfAny() async {
    if (_restored) return;
    _restored = true;
    _isRestoring = true;

    try {
      final saved = await loadSavedBounds();
      final left = saved.left;
      final top = saved.top;
      final width = saved.width;
      final height = saved.height;
      final savedDpr = saved.dpr;

      _pendingMaximize = saved.maximized;
      // מצב מסך מלא משוחזר אף הוא רק אחרי show() (ב-applyPendingFullscreen):
      // קריאה ל-setFullScreen בעוד החלון מוסתר גורמת ל-plugin לצלם את סגנון
      // החלון ללא WS_VISIBLE, וביציאה ממסך מלא הסגנון השמור מוחל כלשונו —
      // והחלון נעלם (נשאר תהליך רץ בלי חלון).
      _pendingFullscreen =
          Settings.getValue<bool>(SettingsRepository.keyIsFullscreen) ?? false;

      // If we don't have a complete set of bounds, do nothing.
      // Maximize (if needed) will be applied after `show()` via
      // `applyPendingMaximize` — calling it before show is unreliable on
      // Windows because `show()` issues SW_SHOWNORMAL which restores
      // maximized state to the previous windowed size.
      if (left == null || top == null || width == null || height == null) {
        return;
      }

      const minSize = WindowPersistence.minSize;
      final clampedWidth = width < minSize.width ? minSize.width : width;
      final clampedHeight = height < minSize.height ? minSize.height : height;

      // macOS שומר נקודות גלובליות; הכפלה ב-DPR מעוותת מיקום בין מסכים.
      // בשאר הפלטפורמות משחזרים פיקסלים לפי ה-DPR של רגע השמירה.
      final dpr = defaultTargetPlatform == TargetPlatform.macOS
          ? 1.0
          : (savedDpr != null && savedDpr > 0)
          ? savedDpr
          : _devicePixelRatio();
      _restoredDpr = dpr;
      _restoredPhysicalBounds = Rect.fromLTWH(
        left * dpr,
        top * dpr,
        clampedWidth * dpr,
        clampedHeight * dpr,
      );
    } catch (_) {
      // window manager may fail on first launch;
      // silently continue with default window dimensions.
    } finally {
      _isRestoring = false;
    }
  }

  /// מחילה את גבולות החלון השמורים (או גודל ברירת מחדל ממורכז בהפעלה ראשונה).
  /// נקראת מוקדם, מיד לאחר [restoreIfAny], בעוד החלון מוסתר — כדי ששינוי DPI
  /// אפשרי (מעבר מסך) יתייצב הרבה לפני שהחלון יוצג ב-[presentMainWindow].
  Future<void> applyRestoredBounds() async {
    _isRestoring = true;
    try {
      // חלון גלוי = main רץ שוב על חלון חי (hot restart). setBounds על חלון
      // ממוקסם מקטין אותו ומשאיר WS_MAXIMIZE, ו-maximize() כבר לא מתקן.
      if (await _window.isVisible()) return;
      final physicalBounds = _restoredPhysicalBounds;
      // macOS מציב נקודות; בשאר הפלטפורמות מבטלים את המרת ה-DPR של setBounds.
      final currentDpr = defaultTargetPlatform == TargetPlatform.macOS
          ? 1.0
          : _devicePixelRatio();
      if (physicalBounds == null) {
        // אין גבולות שמורים (הפעלה ראשונה) — גודל ברירת מחדל ממורכז.
        await _geometry.setSize(WindowPersistence.defaultSize);
        await _window.center();
        return;
      }

      final (workAreas, restoredBounds) = await _boundsAndWorkAreas(
        physicalBounds,
      );
      if (workAreas.isEmpty ||
          WindowPersistence.titleStripReachableOnAnyDisplay(
            restoredBounds,
            workAreas,
            WindowPersistence._grabStripExtent * (_restoredDpr ?? 1),
          )) {
        await _geometry.setBounds(
          WindowPersistence._scaleRect(restoredBounds, 1 / currentDpr),
        );
      } else {
        // גבולות מחוץ לכל מסך (מסך שנותק, עיוות DPI בין מסכים) — החלון היה
        // נפתח "בלתי-נראה". משמרים את הגודל וממרכזים על מסך חי.
        await _geometry.setSize(physicalBounds.size / currentDpr);
        await _window.center();
      }
    } catch (_) {
      // Ignore; window stays at its current bounds.
    } finally {
      _isRestoring = false;
    }
  }

  Future<(List<Rect>, Rect)> _boundsAndWorkAreas(Rect bounds) async {
    try {
      final displays = await screenRetriever.getAllDisplays();
      final platform = defaultTargetPlatform;
      final displayRects = <Rect>[];
      for (final display in displays) {
        final position = display.visiblePosition;
        final size = display.visibleSize;
        if (position == null || size == null) continue;
        final scale = platform == TargetPlatform.macOS
            ? 1.0
            : (display.scaleFactor ?? 1).toDouble();
        final workArea = WindowPersistence.physicalWorkAreaOrNull(
          position & size,
          scale,
        );
        if (workArea == null) continue;
        displayRects.add(workArea);
        if (platform == TargetPlatform.windows &&
            displays.length == 1 &&
            display.scaleFactor != null &&
            !_pendingMaximize &&
            !_pendingFullscreen) {
          // ב-Windows גודל המסך נמדד מהפינה הגלויה עד הקצה הימני־תחתון.
          // למסך יחיד מקור פיזי ידוע (0, 0), גם כשהפס למעלה או משמאל.
          final screen = WindowPersistence.physicalWorkAreaOrNull(
            Rect.fromLTWH(
              0,
              0,
              display.size.width + position.dx,
              display.size.height + position.dy,
            ),
            scale,
          );
          if (screen != null) {
            bounds = WindowPersistence._fitOverTaskbar(
              bounds,
              screen,
              workArea,
              scale,
            );
          }
        }
      }
      return (displayRects, bounds);
    } catch (_) {
      return (const <Rect>[], bounds);
    }
  }

  /// Applies a maximize that was deferred from `restoreIfAny` until after
  /// `windowManager.show()` was called. Must be invoked after show() —
  /// otherwise the maximize is undone by Windows' SW_SHOWNORMAL semantics.
  Future<void> applyPendingMaximize() async {
    if (!_pendingMaximize) return;
    _pendingMaximize = false;
    _isRestoring = true;
    try {
      await _window.maximize();
    } catch (_) {
      // Ignore; window stays at the restored bounds.
    } finally {
      _isRestoring = false;
    }
  }

  /// מחילה שחזור מסך מלא שנדחה מ-[restoreIfAny] עד אחרי `windowManager.show()`
  /// (ואחרי [applyPendingMaximize], כדי שיציאה עתידית ממסך מלא תחזיר את החלון
  /// למצב הממוקסם אם זה היה מצבו). חובה לקרוא רק כשהחלון גלוי: setFullScreen
  /// על חלון מוסתר מצלם סגנון ללא WS_VISIBLE, וביציאה ממסך מלא החלון נעלם.
  Future<void> applyPendingFullscreen() async {
    if (!_pendingFullscreen) return;
    _pendingFullscreen = false;
    _isRestoring = true;
    try {
      // show() מצדו מבצע ShowWindowAsync — ההצגה נרשמת אסינכרונית, וקריאת
      // setFullScreen מיד אחריה עלולה עדיין לצלם סגנון ללא WS_VISIBLE.
      // ממתינים שהחלון גלוי בפועל; אם לא נהיה גלוי (לא אמור לקרות) מדלגים —
      // עדיף חלון רגיל גלוי ממסך מלא שייעלם ביציאה ממנו.
      var visible = false;
      for (var i = 0; i < 50 && !visible; i++) {
        visible = await _window.isVisible();
        if (!visible) {
          await Future<void>.delayed(const Duration(milliseconds: 16));
        }
      }
      if (visible) {
        await _geometry.setFullScreen(true);
      }
    } catch (_) {
      // Ignore; window stays at the restored bounds.
    } finally {
      _isRestoring = false;
    }
  }

  void scheduleSave() {
    // אין לשמור את גודל חלון ה-splash הקטן.
    if (_splashMode) return;
    _debounce?.cancel();
    _debounce = Timer(WindowPersistence._debounceDuration, () {
      unawaited(_saveNow().catchError(_logSaveFailure));
    });
  }

  // כשל דיסק בשמירת הגבולות נרשם ליומן ואינו יוצא כשגיאה לא מטופלת.
  void _logSaveFailure(Object error, StackTrace stackTrace) {
    try {
      ErrorLogFile.appendInBackground(
        title: 'שמירת גבולות החלון נכשלה',
        error: error,
        stackTrace: stackTrace,
      );
    } catch (logError, logStackTrace) {
      debugPrint('רישום כשל שמירת גבולות נכשל: $logError\n$logStackTrace');
    }
  }

  /// שומר לסשן של החלון הזה. חלון בלי משבצת אינו שומר — ובשום מצב אינו
  /// כותב על הגבולות של חלון אחר.
  Future<void> _saveNow() async {
    final slot = _slot();
    if (slot == null) return;
    // חלון ממוזער "חונה" ב-(-32000,-32000) ו-isMaximized מחזיר בו false —
    // שמירה במצב הזה מרעילה גם את הגבולות וגם את דגל המיקסום. לא שומרים.
    if (await _window.isMinimized()) return;

    final isFullscreen = await _window.isFullScreen();
    final isMaximized = await _window.isMaximized();
    final store = _store;
    var next =
        (WindowBounds.decode(await store.loadBoundsJson(slot)) ??
                const WindowBounds())
            .copyWith(maximized: isMaximized);

    // When fullscreen or maximized, don't overwrite the last "normal" bounds.
    // getBounds() while maximized returns the full-screen rect, not the
    // windowed size — saving that would cause a visible jump on the next launch
    // (setBounds to full-screen rect, then maximize).
    if (!isFullscreen && !isMaximized) {
      final bounds = await _geometry.getBounds();
      // getBounds מחזיר לוגי (פיזי חלקי ה-DPR הנוכחי); שמירת ה-DPR לצד הערכים
      // מאפשרת לשחזר את הפיזי במדויק בהפעלה הבאה גם אם ה-DPR ישתנה.
      next = next.copyWith(
        left: bounds.left,
        top: bounds.top,
        width: bounds.width,
        height: bounds.height,
        dpr: _devicePixelRatio(),
      );
    }
    // החלון נסגר בזמן השמירה: הכתיבה הייתה יוצרת מחדש את הסשן שנמחק.
    if (_slot() != slot) return;
    await store.saveBounds(slot, next.encode());
  }

  /// מבטל שמירה ממתינה; החלון כבר לא קיים.
  void dispose() {
    _debounce?.cancel();
    _debounce = null;
  }
}

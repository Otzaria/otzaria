import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

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
  static const Duration _debounceDuration = Duration(milliseconds: 400);

  /// גובה רצועת האחיזה (פס הכותרת המותאם) בפיקסלים לוגיים. בדיקת הנגישות
  /// דורשת שהרצועה הזו — לא סתם פינת חלון — תהיה על מסך חי, אחרת אין מה לגרור.
  static const double _grabStripExtent = 32;

  static Timer? _debounce;
  static bool _restored = false;
  static bool _isRestoring = false;
  static bool _pendingMaximize = false;
  static bool _pendingFullscreen = false;

  /// גבולות החלון השמורים **בפיקסלים פיזיים**, נקראים ב-[restoreIfAny] ומוחלים
  /// ב-[applyRestoredBounds] — מוקדם, בעוד החלון מוסתר וה-splash מוצג (כדי
  /// ששינוי ה-DPI אפשרי יתייצב לפני החשיפה). null = אין גבולות שמורים
  /// (הפעלה ראשונה) → יוחל גודל ברירת מחדל.
  static Rect? _restoredPhysicalBounds;

  /// ה-devicePixelRatio של רגע השמירה — הגבולות נשמרים לוגיים (כפי ש-getBounds
  /// מחזיר), וה-DPR הזה מאפשר לשחזר את הפיזי במדויק גם אם ה-DPR הנוכחי שונה.
  static double? _restoredDpr;

  /// בזמן מסך הפתיחה החלון קטן/שקוף; אסור לשמור את גודלו (אחרת ההפעלה הבאה
  /// "תשחזר" חלון זעיר). כשהדגל דלוק, [scheduleSave]/[saveNow] הם no-op.
  /// זהו גם המנגנון שמונע שמירת גודל ה-splash מלכתחילה — ולכן אין צורך ב-clamp
  /// "שפיות" בשחזור (שפגע בחלונות קטנים חוקיים כמו 500x420).
  static bool _splashMode = false;
  static set splashMode(bool value) => _splashMode = value;

  static bool get isRestoring => _isRestoring;

  /// האם החלון הראשי אמור להיפתח ממוקסם (לפי המצב השמור). נקרא אחרי
  /// [restoreIfAny] כדי להחליט אם למקסם כבר את חלון ה-splash השקוף.
  static bool get willMaximize => _pendingMaximize;

  static Future<void> restoreIfAny() async {
    if (_restored) return;
    _restored = true;
    _isRestoring = true;

    try {
      final isMaximized = Settings.getValue<bool>(_kIsMaximized) ?? false;
      final left = Settings.getValue<double>(_kLeft);
      final top = Settings.getValue<double>(_kTop);
      final width = Settings.getValue<double>(_kWidth);
      final height = Settings.getValue<double>(_kHeight);
      final savedDpr = Settings.getValue<double>(_kDpr);

      _pendingMaximize = isMaximized;
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

      final clampedWidth = width < minSize.width ? minSize.width : width;
      final clampedHeight = height < minSize.height ? minSize.height : height;

      // ממירים לפיזי לפי ה-DPR של רגע השמירה (שמירות ישנות ללא DPR — לפי
      // הנוכחי). ההשוואה למסכים וההצבה נעשות בפיזי, אחיד לכל המסכים.
      final dpr = (savedDpr != null && savedDpr > 0)
          ? savedDpr
          : _currentDevicePixelRatio();
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
  static Future<void> applyRestoredBounds() async {
    _isRestoring = true;
    try {
      final physicalBounds = _restoredPhysicalBounds;
      // setBounds מכפיל את הערכים ב-DPR הנוכחי — חלוקה בו נותנת הצבה פיזית
      // מדויקת גם כשהחלון נשמר על מסך עם קנה מידה שונה מהמסך הראשי.
      final currentDpr = _currentDevicePixelRatio();
      if (physicalBounds == null) {
        // אין גבולות שמורים (הפעלה ראשונה) — גודל ברירת מחדל ממורכז.
        await windowManager.setSize(const Size(1280, 720));
        await windowManager.center();
      } else if (await _isReachableOnConnectedDisplay(physicalBounds)) {
        // הגבולות כבר עברו clamp ל-minSize (420x400) ב-restoreIfAny, וגודל
        // ה-splash לעולם לא נשמר (splashMode) — לכן מכבדים כל גודל חוקי שנשמר,
        // כולל חלונות קטנים שהמשתמש בחר במכוון.
        await windowManager.setBounds(
          _scaleRect(physicalBounds, 1 / currentDpr),
        );
      } else {
        // גבולות מחוץ לכל מסך (מסך שנותק, עיוות DPI בין מסכים) — החלון היה
        // נפתח "בלתי-נראה". משמרים את הגודל וממרכזים על מסך חי.
        await windowManager.setSize(physicalBounds.size / currentDpr);
        await windowManager.center();
      }
    } catch (_) {
      // Ignore; window stays at its current bounds.
    } finally {
      _isRestoring = false;
    }
  }

  /// ה-DPR שאיתו window_manager ממיר לוגי→פיזי (window.devicePixelRatio);
  /// שימוש באותו מקור מבטיח שההמרות מתבטלות במדויק.
  static double _currentDevicePixelRatio() {
    final dpr = PlatformDispatcher.instance.implicitView?.devicePixelRatio;
    return (dpr != null && dpr > 0) ? dpr : 1.0;
  }

  static Rect _scaleRect(Rect rect, double factor) => Rect.fromLTWH(
    rect.left * factor,
    rect.top * factor,
    rect.width * factor,
    rect.height * factor,
  );

  /// האם רצועת האחיזה של [physicalBounds] נגישה על מסך מחובר כלשהו. כשל
  /// בקריאת רשימת המסכים לא חוסם את השחזור — עדיף שחזור רגיל ממירכוז מיותר.
  static Future<bool> _isReachableOnConnectedDisplay(
    Rect physicalBounds,
  ) async {
    try {
      final displays = await screenRetriever.getAllDisplays();
      // screen_retriever מחזיר קואורדינטות לוגיות פר-מסך (מחולקות ב-scale של
      // אותו מסך) — הכפלה ב-scaleFactor מחזירה אותן לפיזי, מרחב אחיד.
      final displayRects = [
        for (final display in displays)
          if (display.visiblePosition != null && display.visibleSize != null)
            _scaleRect(
              display.visiblePosition! & display.visibleSize!,
              (display.scaleFactor ?? 1).toDouble(),
            ),
      ];
      if (displayRects.isEmpty) return true;
      return titleStripReachableOnAnyDisplay(
        physicalBounds,
        displayRects,
        _grabStripExtent * (_restoredDpr ?? 1),
      );
    } catch (_) {
      return true;
    }
  }

  /// האם רצועת האחיזה — [stripExtent] העליונים של [bounds] — מונחת במלואה
  /// (לגובהה) ולרוחב [stripExtent] לפחות על אחד מ-[displayRects]. גבולות
  /// שנשמרו בטעות כשהחלון ממוזער (חניה ב--32000, ראה [_saveNow]), מסך שנותק,
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

  /// Applies a maximize that was deferred from `restoreIfAny` until after
  /// `windowManager.show()` was called. Must be invoked after show() —
  /// otherwise the maximize is undone by Windows' SW_SHOWNORMAL semantics.
  static Future<void> applyPendingMaximize() async {
    if (!_pendingMaximize) return;
    _pendingMaximize = false;
    _isRestoring = true;
    try {
      await windowManager.maximize();
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
  static Future<void> applyPendingFullscreen() async {
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
        visible = await windowManager.isVisible();
        if (!visible) {
          await Future<void>.delayed(const Duration(milliseconds: 16));
        }
      }
      if (visible) {
        await windowManager.setFullScreen(true);
      }
    } catch (_) {
      // Ignore; window stays at the restored bounds.
    } finally {
      _isRestoring = false;
    }
  }

  static void scheduleSave() {
    // אין לשמור את גודל חלון ה-splash הקטן.
    if (_splashMode) return;
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () {
      // Fire-and-forget; any failure here shouldn't crash the app.
      unawaited(_saveNow());
    });
  }

  static Future<void> saveNow() async {
    if (_splashMode) return;
    _debounce?.cancel();
    _debounce = null;

    try {
      await _saveNow();
    } catch (_) {
      // Ignore persistence errors; should never crash the app.
    }
  }

  static Future<void> _saveNow() async {
    // חלון ממוזער "חונה" ב-(-32000,-32000) ו-isMaximized מחזיר בו false —
    // שמירה במצב הזה מרעילה גם את הגבולות וגם את דגל המיקסום. לא שומרים.
    if (await windowManager.isMinimized()) return;

    final isFullscreen = await windowManager.isFullScreen();
    final isMaximized = await windowManager.isMaximized();
    await Settings.setValue(_kIsMaximized, isMaximized);

    // When fullscreen or maximized, don't overwrite the last "normal" bounds.
    // getBounds() while maximized returns the full-screen rect, not the
    // windowed size — saving that would cause a visible jump on the next launch
    // (setBounds to full-screen rect, then maximize).
    if (isFullscreen || isMaximized) return;

    final bounds = await windowManager.getBounds();
    await Settings.setValue(_kLeft, bounds.left);
    await Settings.setValue(_kTop, bounds.top);
    await Settings.setValue(_kWidth, bounds.width);
    await Settings.setValue(_kHeight, bounds.height);
    // getBounds מחזיר לוגי (פיזי חלקי ה-DPR הנוכחי); שמירת ה-DPR לצד הערכים
    // מאפשרת לשחזר את הפיזי במדויק בהפעלה הבאה גם אם ה-DPR ישתנה.
    await Settings.setValue(_kDpr, _currentDevicePixelRatio());
  }
}

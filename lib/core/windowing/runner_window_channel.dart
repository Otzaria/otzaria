import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/core/windowing/drag_preview_colors.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';

/// תוצאת גרירה שהמערכת ניהלה — ראו [RunnerWindowChannel.dragOutToSystem].
///
/// [snapped] הוא מה שמבדיל בין "פתח כאן" לבין "פתח **במסגרת הזו**": התצוגה
/// היא בגודל כרטיסיה, ושימוש עיוור במסגרת היה יוצר חלון אוצריא של 176×40.
typedef SystemDragOutcome = ({
  bool ran,
  bool snapped,
  int left,
  int top,
  int width,
  int height,
  int x,
  int y,
  int? slot,
  bool isSelf,
  bool isShellTray,
  bool inWorkArea,
  bool atTaskbarEdge,
  int? hwnd,
});

/// מה שתחת הסמן — ראו [RunnerWindowChannel.windowAtCursor].
typedef CursorTarget = ({
  int? slot,
  bool isSelf,
  bool isShellTray,
  bool inWorkArea,
  bool approachingTop,
  int minUpwardTravel,
  int x,
  int y,
  int? hwnd,
});

/// הערוץ מול ה-runner עבור החלון הראשי: הסתרה, הבאה לחזית, הצגה מחדש של
/// ראשי מוסתר, ותצוגת הגרירה של כרטיסיה מחוץ לחלון (Windows).
/// חלונות נוספים הם חלונות Dart באותו מנוע — ראו `ViewWindowOpener`.
class RunnerWindowChannel {
  const RunnerWindowChannel();

  static const MethodChannel channel = MethodChannel('otzaria/multiwindow');

  /// Real native pointer for the primary window; nativeapi's Window.id
  /// is not an HWND (Windows) or GtkWindow* (Linux).
  Future<int?> mainWindowHandle() =>
      channel.invokeMethod<int>('mainWindowHandle');

  /// האם אפשר לפתוח חלונות נוספים: ריבוי תצוגות פעיל. בלעדיו (macOS בלי
  /// handshake, בלי בעלים) התוכנה בחלון יחיד והאפשרויות מוסתרות.
  static bool get canOpenWindows =>
      debugSupportedOverride ?? (!kIsWeb && MultiViewMode.enabled);

  /// האם אפשר לגרור כרטיסיה החוצה לחלון חדש או לחלון קיים.
  ///
  /// Windows בלבד: ב-macOS ובלינוקס ה-runner אינו מממש את מסלול הגרירה
  /// (מיקום חלון לפי הסמן אינו אפשרי ב-Wayland).
  static bool get canDragTabsOut =>
      debugSupportedOverride ??
      (!kIsWeb && Platform.isWindows && MultiViewMode.enabled);

  /// לכל runner של דסקטופ יש את הערוץ, גם בחלון יחיד.
  static bool get _hasRunner =>
      debugSupportedOverride ??
      (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux));

  /// דורס את [canOpenWindows], [canDragTabsOut] וזמינות הערוץ **בבדיקות בלבד**,
  /// כדי שההחלטות שמעבר לערוץ (המדומה) ייבדקו בכל פלטפורמה.
  @visibleForTesting
  static bool? debugSupportedOverride;

  /// מביא את החלון הראשי לחזית, ומציג אותו אם הוסתר.
  Future<void> raiseSelf() async {
    final raised = await _guarded(_hasRunner, 'raiseSelf', false, () async {
      await channel.invokeMethod<void>('raiseSelf');
      return true;
    });
    if (raised) _reportMainWindowShown();
  }

  /// מתחיל להציג את הכרטיסיה הנגררת **מחוץ** לחלון.
  ///
  /// ⚠️ ה-`feedback` של `Draggable` מצויר ב-Overlay של החלון ולכן נחתך
  /// בגבולותיו: ברגע שהסמן יוצא, הכרטיסיה נעלמת. ה-runner מציג חלון layered
  /// שעוקב אחרי הסמן ומופיע רק בחוץ. [colors] הם צבעי הערכה, כ-ARGB.
  /// [sourceHwnd] — חלון Dart שממנו גוררים; בלעדיו המקור הוא החלון הראשי.
  Future<void> beginTabDrag(
    String title, {
    required DragPreviewColors colors,
    int? sourceHwnd,
  }) => _guarded(
    canDragTabsOut,
    'beginTabDrag',
    null,
    () => channel.invokeMethod<void>('beginTabDrag', {
      'title': title,
      ...colors.toArgb(),
      'sourceHwnd': ?sourceHwnd,
    }),
  );

  /// שולח צילום RGBA מוקטן לתצוגת הגרירה; GDI מותח אותו לגודל חלון היעד.
  /// הפיקסלים מוכפלים מראש כנדרש ב־AlphaBlend.
  Future<bool> setTabDragImage(
    Uint8List rgba,
    int width,
    int height, {
    int? targetWidth,
    int? targetHeight,
  }) => _guarded(canDragTabsOut, 'setTabDragImage', false, () async {
    await channel.invokeMethod<void>('setTabDragImage', {
      'bytes': rgba,
      'width': width,
      'height': height,
      'targetWidth': ?targetWidth,
      'targetHeight': ?targetHeight,
    });
    return true;
  });

  /// מוסר ל-Windows את המשך הגרירה, וממתין עד שהמשתמש שחרר.
  ///
  /// ## למה זו הדרך היחידה ל-Snap Layouts
  ///
  /// אין API שפותח את מסדר החלונות. ה-shell פותח אותו בעצמו, ורק כשהוא
  /// משוכנע שהמשתמש גורר **חלון** לעבר קצה המסך. לכן התצוגה עצמה היא חלון
  /// עם סגנונות של חלון אמיתי, והיא זו שנמסרת למערכת; החלון האמיתי נפתח רק
  /// בשחרור, על פי התוצאה שחוזרת מכאן.
  ///
  /// ⚠️ הקריאה חוסמת לכל משך הגרירה, וזה במתכוון: התשובה היא המסגרת
  /// הסופית — כולל הצמדה, אם המשתמש הצמיד.
  ///
  /// [withHwnd] (חלונות Dart): התשובה כוללת את ה-HWND שתחת הסמן, ו-isSelf
  /// נמדד מול [selfHwnd] (בלעדיו — החלון הראשי).
  Future<SystemDragOutcome?> dragOutToSystem({
    int? selfHwnd,
    bool withHwnd = false,
  }) => _guarded(canDragTabsOut, 'dragOutToSystem', null, () async {
    final info = await channel.invokeMapMethod<String, dynamic>(
      'dragOutToSystem',
      withHwnd ? {'selfHwnd': ?selfHwnd} : null,
    );
    if (info == null) return null;
    return (
      ran: info['ran'] == true,
      snapped: info['snapped'] == true,
      left: (info['left'] as int?) ?? 0,
      top: (info['top'] as int?) ?? 0,
      width: (info['width'] as int?) ?? 0,
      height: (info['height'] as int?) ?? 0,
      x: (info['x'] as int?) ?? 0,
      y: (info['y'] as int?) ?? 0,
      slot: info['slot'] as int?,
      isSelf: info['isSelf'] == true,
      isShellTray: info['isShellTray'] == true,
      // runner ישן אינו מדווח — בתוך אזור העבודה.
      inWorkArea: info['inWorkArea'] != false,
      // הסמן נכלא בקצה אזור העבודה ליד שורת המשימות.
      atTaskbarEdge: info['atTaskbarEdge'] == true,
      hwnd: info['hwnd'] as int?,
    );
  });

  /// עוצר את המעקב ומשאיר את התצוגה **גלויה במקום השחרור**.
  ///
  /// ⚠️ נקרא בסיום הגרירה ולא [endTabDrag], כי בשלב הזה עוד לא ידוע אם
  /// ייפתח חלון: `onDragFinishedAnywhere` נורה **לפני** `onDroppedOutside`.
  /// ה-runner מסתיר את התצוגה ברשת ביטחון של ארבע שניות.
  Future<void> freezeTabDrag() => _send(canDragTabsOut, 'freezeTabDrag');

  /// מסתיר את תצוגת הגרירה מיד. לכל מסלול סיום שאינו פותח חלון.
  Future<void> endTabDrag() => _send(canDragTabsOut, 'endTabDrag');

  /// מציג שוב את החלון הראשי אם Dart הסתיר אותו. true אם היה מוסתר.
  Future<bool> restoreLastClosedWindow() async {
    final restored = await _guarded(
      _hasRunner,
      'restoreLastClosedWindow',
      false,
      () async =>
          await channel.invokeMethod<bool>('restoreLastClosedWindow') ?? false,
    );
    if (restored) _reportMainWindowShown();
    return restored;
  }

  /// ה-runner הציג את הראשי בעצמו, ולא דרך `windowManager.show()`.
  ///
  /// ⚠️ window_manager 0.5.2 פלט `show` גם על הצגה נייטיבית (`WM_SHOWWINDOW`,
  /// אותות GTK); 0.6 פולט אותו רק מ-`show()` של Dart. בלי הדיווח כאן התוספים
  /// של ראשי שנסגר ושוחזר נשארים מושהים עד אירוע פוקוס, שב-Windows אינו
  /// מובטח כשהמערכת חוסמת את `SetForegroundWindow`. ההסתרה מדווחת ב-Dart
  /// לפני [closeSelf] (`AppWindowListener`). הדיווח אידמפוטנטי.
  static void _reportMainWindowShown() =>
      PluginRuntimeDispatcher.instance.setWindowShown(true);

  /// ממיר נקודת מסך לקואורדינטות אזור-הלקוח של החלון, בפיקסלים לוגיים.
  ///
  /// ⚠️ ההמרה ב-runner ולא כאן: Flutter אינו יודע היכן החלון יושב על המסך.
  /// [hwnd] — חלון Dart שאליו ממירים; בלעדיו — החלון הראשי.
  Future<Offset?> screenToClient(
    int x,
    int y,
    double devicePixelRatio, {
    int? hwnd,
  }) => _guarded(canDragTabsOut, 'screenToClient', null, () async {
    final p = await channel.invokeMapMethod<String, dynamic>(
      'screenToClient',
      {'x': x, 'y': y, 'hwnd': ?hwnd},
    );
    if (p == null) return null;
    return Offset(
      ((p['x'] as int?) ?? 0) / devicePixelRatio,
      ((p['y'] as int?) ?? 0) / devicePixelRatio,
    );
  });

  /// מה נמצא תחת סמן העכבר ברגע זה.
  ///
  /// [slot] הוא 1 כשהסמן מעל החלון הראשי, ואחרת null; חלון Dart מזוהה לפי
  /// [hwnd]. [isShellTray] הוא שורת המשימות, ששחרור מעליה אינו "פתח חלון כאן".
  ///
  /// ⚠️ מחזיר `null` כשלא ניתן היה לברר, ו**לא** "שולחן העבודה": אחרת כשל
  /// ערוץ פתח חלון חדש בפינה (0,0) ומחק את הכרטיסיה מהמקור.
  /// [selfHwnd] ו-[withHwnd] — כמו ב-[dragOutToSystem].
  Future<CursorTarget?> windowAtCursor({
    int? selfHwnd,
    bool withHwnd = false,
  }) => _guarded(canDragTabsOut, 'windowAtCursor', null, () async {
    final info = await channel.invokeMapMethod<String, dynamic>(
      'windowAtCursor',
      withHwnd ? {'selfHwnd': ?selfHwnd} : null,
    );
    if (info == null) return null;
    return (
      slot: info['slot'] as int?,
      isSelf: info['isSelf'] == true,
      isShellTray: info['isShellTray'] == true,
      // runner ישן אינו מדווח — בתוך אזור העבודה.
      inWorkArea: info['inWorkArea'] != false,
      approachingTop: info['approachingTop'] == true,
      // ערך חסר דורש נסיעה שמרנית יותר.
      minUpwardTravel: (info['minUpwardTravel'] as int?) ?? 24,
      x: (info['x'] as int?) ?? 0,
      y: (info['y'] as int?) ?? 0,
      hwnd: info['hwnd'] as int?,
    );
  });

  /// מסתיר את החלון הראשי בלי לסיים את התהליך.
  ///
  /// ⚠️ ולא `AppWindowController.quitApplication`: ב-Windows הוא
  /// `PostQuitMessage(0)` בלבד — לולאת ההודעות של **התהליך** יוצאת, כל
  /// החלונות נסגרים, והמנוע נהרס בעוד Dart רץ עליו. ראו התיעוד שם.
  Future<void> closeSelf() => _send(_hasRunner, 'closeSelf');

  /// מריץ [call] רק כש-[enabled]; כשל בערוץ מודפס ומחזיר את [fallback].
  Future<T> _guarded<T>(
    bool enabled,
    String method,
    T fallback,
    Future<T> Function() call,
  ) async {
    if (!enabled) return fallback;
    try {
      return await call();
    } catch (e) {
      debugPrint('$method failed: $e');
      return fallback;
    }
  }

  /// קריאת void לערוץ דרך [_guarded].
  Future<void> _send(bool enabled, String method, [Object? arguments]) =>
      _guarded(
        enabled,
        method,
        null,
        () => channel.invokeMethod<void>(method, arguments),
      );

  /// הכרטיסיה אחרי מסע הלוך-ושוב דרך JSON, כמו בשמירת הסשן; null בכשל.
  ///
  /// ⚠️ דרך `jsonEncode` ולא `toJson`→`fromJson` ישירות: מפה עם מפתחות שאינם
  /// מחרוזת עוברת העתקה ישירה ונכשלת בשחזור הסשן בהפעלה הבאה.
  @visibleForTesting
  static OpenedTab? transferRoundTrip(OpenedTab tab) {
    final decoded = jsonDecode(jsonEncode(tab.toTransferJson()));
    if (decoded is! Map) return null;
    return OpenedTab.fromJson(Map<String, dynamic>.from(decoded));
  }

  /// האם הכרטיסיה שורדת העברה לחלון אחר.
  ///
  /// ⚠️ נבדק **לפני** שמסירים אותה מהחלון המקורי: כרטיסיה שאינה ניתנת
  /// לשחזור הייתה נעלמת מהמקור ולא נפתחת ביעד. "לא זרק" אינו "נאמן": טאב
  /// מפוצל שאיבד חלונית עובר פענוח, ולכן נבדק גם **מבנה** התוצאה.
  ///
  /// ⚠️ **הבדיקה יקרה — אל תקרא לה בלולאה.** הפענוח בונה כרטיסיה מלאה (BLoC,
  /// repository, מנויים), ולכן היא נבדקת פעם אחת בתחילת הגרירה או לפני
  /// פעולת תפריט.
  static bool canTransfer(OpenedTab tab) {
    OpenedTab? restored;
    try {
      restored = transferRoundTrip(tab);
      if (restored == null) {
        debugPrint(
          'canTransfer: ${tab.runtimeType} אינה שורדת את מסלול ההעברה',
        );
        return false;
      }
      if (tab is CombinedTab && restored is! CombinedTab) {
        debugPrint(
          'canTransfer: טאב מפוצל איבד חלונית בסריאליזציה — לא מועבר',
        );
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('canTransfer failed for ${tab.runtimeType}: $e');
      return false;
    } finally {
      // ⚠️ הכרטיסיה שנבנתה כאן נזרקת, ובלי השחרור המנויים שלה נשארים חיים.
      try {
        restored?.dispose();
      } catch (e) {
        debugPrint('canTransfer: dispose of probe tab failed: $e');
      }
    }
  }
}

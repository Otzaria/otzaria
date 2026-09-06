import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/core/messages/window_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/windowing/drag_preview_colors.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';

/// תוצאת גרירה שהמערכת ניהלה — ראו [MultiWindowService.dragOutToSystem].
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
});

/// פותח חלונות אוצריא נוספים.
///
/// כל חלון הוא `FlutterEngine` נפרד, ב-isolate נפרד, **באותו תהליך**
/// (ראו `docs/multi-window.md`). ה-runner הוא שיוצר את החלון,
/// כי יצירת חלון ולולאת הודעות אינן זמינות מ-Dart.
///
/// ## ⚠️ כל המנועים חולקים את ה-thread הראשי. זהו חוב פתוח.
///
/// ההכרעה במודל A נשענה על thread ייעודי לכל מנוע — נמדד 102ms השהיה מול
/// 2,092ms ב-thread משותף, פי 20. **המימוש לא הצליח לספק אותו:** יצירת
/// מנוע על thread ייעודי קורסת בעקביות ברגע שהחלון הראשון רץ
/// (`Isolate main is already scheduled on mutator thread`), וזהו גם מה
/// שעושה `desktop_multi_window`. ראו ההערה ב-
/// `CreateSecondaryWindowOnThisThread`.
///
/// המשמעות המעשית: **חלון עסוק יכול להקפיא את השני.** התוכנה רצה בתצורת
/// הבקרה, זו של 2,092ms. גרסה קודמת של התיעוד כאן הצהירה על ה-thread
/// הייעודי כעל עובדה ש"אינה פרט מימוש שאפשר לוותר עליו", וה-runner אמר את
/// ההפך המדויק — כלומר קוד היצור ניתב את המתחזק אל טענה שגויה.
///
/// זו המשימה הראשונה בהמשך: למדוד p95 זמן פריים בחלון סרק בזמן שהשני עסוק
/// (בדיקה 10 של P-2, שטרם הורצה מול המימוש). שתי דרכים לא-בדוקות אם
/// ההרעה גדולה מפי 2: יצירה על ה-thread הראשי ואז העברת בעלות ל-thread
/// ייעודי, או הדגל `RunOnSeparateThread` — שעובד אך המנוע מכריז שיוסר.
class MultiWindowService {
  const MultiWindowService();

  /// הערוץ מול ה-runner.
  ///
  /// חשוף כי התקשורת דו-כיוונית: `adoptPayload` נשלחת מה-runner אל החלון
  /// כשהוא מחזיר חלון מוסתר לשימוש עם כרטיסיה חדשה.
  static const MethodChannel channel = MethodChannel('otzaria/multiwindow');

  /// האם ריבוי חלונות נתמך בפלטפורמה הנוכחית.
  ///
  /// היום Windows בלבד — הצד הנייטיב מומש ב-`windows/runner`. macOS ו-Linux
  /// הם פרק 12 במפת הדרכים.
  static bool get isSupported =>
      debugSupportedOverride ?? (!kIsWeb && Platform.isWindows);

  /// דורס את [isSupported] **בבדיקות בלבד**.
  ///
  /// ⚠️ קיים כדי שסוויטת ההחלטות של הגרירה תרוץ בכל פלטפורמה. היא הייתה
  /// מגודרת ב-`@TestOn('windows')`, וה-CI רץ על ubuntu — כלומר כל הבדיקות
  /// של "מה קורה לכרטיסיה" (הסרה רק אחרי אישור, כרטיסיה אחרונה, שורת
  /// המשימות, הצמדה) היו ירוקות על מכונת המפתח בלבד. ההיגיון עצמו אינו
  /// תלוי פלטפורמה — רק ה-runner שמעבר לערוץ, והוא מדומה בבדיקה.
  @visibleForTesting
  static bool? debugSupportedOverride;

  /// פותח חלון חדש, ואם [tab] אינו null — עם אותו טאב פתוח בו.
  ///
  /// מחזיר true רק אחרי שהחלון **נוצר בפועל** (או שחלון מוסתר הוחזר
  /// לשימוש). ה-runner עונה מלולאת ההודעות שלו, אחרי היצירה.
  ///
  /// ⚠️ קודם לכן הוא החזיר true מיד אחרי הכנסת הבקשה לתור, וערך ההחזרה של
  /// היצירה עצמה נזרק. שני אתרי הקריאה מוחקים את הכרטיסיה על סמך התשובה
  /// הזו — כלומר כרטיסיה נמחקה על סמך הצלחה שלא נבדקה.
  /// [origin] היא **הפינה** שבה החלון ייפתח, בקואורדינטות מסך.
  ///
  /// ⚠️ פינה, ולא "נקודת השחרור" שסביבה מחשבים. הגרסה הקודמת קיבלה את
  /// מיקום הסמן והזיזה את החלון `-width + 100` — היסט שנועד לתצוגה ברוחב
  /// 300, ועם חלון ברוחב 1400 הוא 1,300 פיקסלים שמאלה. אחרי ההידוק לקצה
  /// המסך התוצאה הייתה קבועה: חלון שנגרר ימינה נפתח בשמאל.
  ///
  /// בלעדיה החלון נפתח בהיסט מדורג מהפינה, בלי קשר למקום שאליו גררו.
  ///
  /// [bounds] היא מסגרת מדויקת שדוחה את [origin] — כך חלון שהמשתמש
  /// **הצמיד** בגרירה נוצר בדיוק במסגרת שההצמדה נתנה. בלעדיה ההצמדה
  /// שהמשתמש ראה נעלמת ברגע שהחלון האמיתי מופיע.
  Future<bool> openWindow({
    OpenedTab? tab,
    ({int x, int y})? origin,
    ({int left, int top, int width, int height})? bounds,
  }) async {
    if (!isSupported) return false;
    try {
      // המידות נשלחות ל-runner כדי שייצור את החלון בגודל הנכון מלכתחילה.
      // שינוי גודל אחרי היצירה היה מאתחל את ה-swapchain של המנוע וגורם
      // להבהוב, בדיוק כמו שקורה בחלון הראשון (ראו initSettingsAndWindow).
      Size? inherited;
      try {
        inherited = await windowManager.getSize();
      } catch (_) {
        // בלי מידות ה-runner ייצור בגודל ברירת מחדל.
      }
      final opened = await channel
          .invokeMethod<bool>('openWindow', {
            'payload': _encodePayload(tab),
            if (inherited != null) 'width': inherited.width.round(),
            if (inherited != null) 'height': inherited.height.round(),
            if (origin != null) 'originX': origin.x,
            if (origin != null) 'originY': origin.y,
            if (bounds != null)
              'bounds': {
                'left': bounds.left,
                'top': bounds.top,
                'width': bounds.width,
                'height': bounds.height,
              },
          })
          // ⚠️ רשת ביטחון. התשובה מגיעה מלולאת ההודעות של ה-runner,
          // ואם החלון הפותח נהרס לפני שההודעה טופלה — אין מי שיענה.
          // בלי ה-timeout מסלול העברת הכרטיסיה נשאר תלוי לנצח.
          .timeout(const Duration(seconds: 20), onTimeout: () => false);
      // false פירושו שהתקרה הושגה, או שהיצירה נכשלה — ה-runner הוא מקור
      // האמת לשניהם.
      return opened ?? false;
    } on PlatformException catch (e) {
      debugPrint('openWindow failed: ${e.code} ${e.message}');
      return false;
    } on MissingPluginException {
      // ה-runner בגרסה זו אינו מכיר את הערוץ — למשל בבדיקות widget.
      return false;
    }
  }

  /// המשבצות של חלונות אוצריא **שמוצגים על המסך** כרגע.
  ///
  /// ⚠️ "עונה על האפיק" אינו "פתוח": חלון שהמשתמש סגר מוסתר ולא נהרס,
  /// וה-isolate שלו ממשיך לענות. הנראות נמדדת בנייטיב, כי חלון מוסתר אינו
  /// יודע שהוסתר.
  ///
  /// מחזיר null כשלא ניתן היה לברר — אז אין לסנן, כי סינון על סמך מידע
  /// חסר היה מסתיר חלונות פתוחים מהתפריט.
  Future<Set<int>?> visibleSlots() async {
    if (!isSupported) return null;
    try {
      final slots = await channel.invokeListMethod<int>('visibleSlots');
      return slots?.toSet();
    } catch (e) {
      debugPrint('visibleSlots failed: $e');
      return null;
    }
  }

  /// מספר החלונות הפתוחים, התקרה, ומספר המנועים החיים.
  ///
  /// ה-runner הוא מקור האמת: ה-isolate של כל חלון רואה רק את עצמו.
  ///
  /// ⚠️ [engines] **אינו** [count]. חלון שנסגר מוסתר ולא נהרס, והמנוע שלו
  /// נשאר חי — כלומר "נסגר החלון האחרון" יכול לקרות בעוד שלושה מנועים
  /// רצים. ההבדל קובע אם `exit()` בטוח: P-2 מדד ש-`exit()` בזמן שמנוע אחר
  /// חי מפיל בדיקה של ה-Dart VM ב-~1% מהיציאות.
  ///
  /// ⚠️ מחזיר `null` כש**לא ידוע** (הערוץ זרק). "חלון יחיד" מוחזר רק כשזו
  /// באמת התשובה — הנחת "אני האחרון" בכשל הרגה את שאר החלונות ב-`exit(0)`.
  Future<({int count, int max, int engines})?> windowCount() async {
    if (!isSupported) return _singleWindow;
    try {
      final info = await channel.invokeMapMethod<String, dynamic>(
        'windowCount',
      );
      if (info == null) return null;
      return (
        count: (info['count'] as int?) ?? 1,
        max: (info['max'] as int?) ?? 1,
        engines: (info['engines'] as int?) ?? 1,
      );
    } on PlatformException catch (e) {
      debugPrint('windowCount failed: ${e.code} ${e.message}');
      return null;
    } on MissingPluginException {
      // הפלטפורמה אינה מכירה את הערוץ — כאן "חלון יחיד" הוא באמת התשובה.
      return _singleWindow;
    }
  }

  static const ({int count, int max, int engines}) _singleWindow = (
    count: 1,
    max: 1,
    engines: 1,
  );

  /// מביא את החלון הנוכחי לחזית.
  ///
  /// ⚠️ חלון משני נוצר מוסתר כדי שלא ייראה מצטייר, ו-`show()` על חלון
  /// מוסתר אינו מפעיל אותו — הוא נחשף **מאחורי** החלון שפתח אותו.
  Future<void> raiseSelf() async {
    if (!isSupported) return;
    try {
      await channel.invokeMethod<void>('raiseSelf');
    } catch (e) {
      debugPrint('raiseSelf failed: $e');
    }
  }

  /// מתחיל להציג את הכרטיסיה הנגררת **מחוץ** לחלון.
  ///
  /// ⚠️ ה-`feedback` של `Draggable` מצויר ב-Overlay של החלון ולכן נחתך
  /// בגבולותיו: ברגע שהסמן יוצא, הכרטיסיה נעלמת. המשתמש אינו רואה שהוא
  /// גורר משהו, ולכן גם אינו יכול לכוון לשורת המשימות או לחלון אחר.
  /// ה-runner מציג חלון layered שעוקב אחרי הסמן ומופיע רק בחוץ.
  /// [colors] הם צבעי הערכה, כ-ARGB.
  ///
  /// ⚠️ הם היו מקודדים קשיח בגוונים בהירים בצד הנייטיב. בערכה כהה זה
  /// נראה כמו מלבן לבן זוהר על מסך כהה — הפוך בדיוק ממה שהמשתמש מצפה
  /// שייגרר.
  Future<void> beginTabDrag(
    String title, {
    required DragPreviewColors colors,
  }) async {
    if (!isSupported) return;
    try {
      await channel.invokeMethod<void>('beginTabDrag', {
        'title': title,
        ...colors.toArgb(),
      });
    } catch (e) {
      debugPrint('beginTabDrag failed: $e');
    }
  }

  /// מחליף את הכרטיסיה המשורטטת בתמונה **אמיתית** שלה.
  ///
  /// ⚠️ שרטוט מחדש ב-GDI אינו יכול להיות זהה: הוא אינו יודע את הגופן, את
  /// אייקון סוג הכרטיסיה, את כפתור ה-X או את סימון הבחירה. הבקשה הייתה
  /// שהגרירה תיראה כמו בכרום — כלומר הכרטיסיה עצמה.
  ///
  /// [rgba] הוא `ImageByteFormat.rawRgba`, שהוא **מוכפל-מראש** — בדיוק מה
  /// ש-`AlphaBlend` מצפה לו אחרי החלפת אדום וכחול.
  /// ⚠️ **גודל היעד נפרד מגודל הצילום, ובמכוון.** מה שנגרר הוא מוק של
  /// החלון שייפתח — כרטיסיה והתוכן שלה — כלומר בגודל חלון מלא. צילום כזה
  /// בפיקסלים פיזיים הוא מיליוני פיקסלים, והעברתו בערוץ בתחילת כל גרירה
  /// היא עשרות MB ולפניהם קריאת פיקסלים מה-GPU. לכן הצילום קטן יותר
  /// (ראו `previewCaptureRatio`), ו-GDI מותח אותו ל-[targetWidth] ×
  /// [targetHeight].
  Future<void> setTabDragImage(
    Uint8List rgba,
    int width,
    int height, {
    int? targetWidth,
    int? targetHeight,
  }) async {
    if (!isSupported) return;
    try {
      await channel.invokeMethod<void>('setTabDragImage', {
        'bytes': rgba,
        'width': width,
        'height': height,
        'targetWidth': ?targetWidth,
        'targetHeight': ?targetHeight,
      });
    } catch (e) {
      debugPrint('setTabDragImage failed: $e');
    }
  }

  /// מוסר ל-Windows את המשך הגרירה, וממתין עד שהמשתמש שחרר.
  ///
  /// ## למה זו הדרך היחידה ל-Snap Layouts
  ///
  /// אין API שפותח את מסדר החלונות. ה-shell פותח אותו בעצמו, ורק כשהוא
  /// משוכנע שהמשתמש גורר **חלון** לעבר קצה המסך. כל עוד הכרטיסיה נגררת
  /// בתוך התהליך שלנו — Flutter לוכד את הסמן, וה-runner מזיז חלון layered
  /// בטיימר — מבחינת Windows שום חלון אינו נגרר.
  ///
  /// לכן התצוגה עצמה היא חלון עם סגנונות של חלון אמיתי, והיא זו שנמסרת
  /// למערכת. **שום מנוע Flutter אינו נוצר כאן** — זו הנקודה: החלון
  /// האמיתי נפתח רק בשחרור, על פי התוצאה שחוזרת מכאן.
  ///
  /// ⚠️ הקריאה חוסמת לכל משך הגרירה, וזה במתכוון: התשובה היא המסגרת
  /// הסופית — כולל הצמדה, אם המשתמש הצמיד.
  Future<SystemDragOutcome?> dragOutToSystem() async {
    if (!isSupported) return null;
    try {
      final info = await channel.invokeMapMethod<String, dynamic>(
        'dragOutToSystem',
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
      );
    } catch (e) {
      debugPrint('dragOutToSystem failed: $e');
      return null;
    }
  }

  /// עוצר את המעקב ומשאיר את התצוגה **גלויה במקום השחרור**.
  ///
  /// ⚠️ נקרא בסיום הגרירה ולא [endTabDrag], כי בשלב הזה עוד לא ידוע אם
  /// ייפתח חלון: `onDragFinishedAnywhere` נורה **לפני**
  /// `onDroppedOutside`. פתיחת חלון לוקחת מאות מילישניות, ובלי ההקפאה
  /// המסך ריק בדיוק בפרק הזמן שבו המשתמש מחכה לראות תוצאה.
  ///
  /// ה-runner מסתיר את התצוגה כשהחלון האמיתי נחשף, וגם ברשת ביטחון של
  /// ארבע שניות.
  Future<void> freezeTabDrag() async {
    if (!isSupported) return;
    try {
      await channel.invokeMethod<void>('freezeTabDrag');
    } catch (e) {
      debugPrint('freezeTabDrag failed: $e');
    }
  }

  /// מסתיר את תצוגת הגרירה מיד. לכל מסלול סיום שאינו פותח חלון.
  Future<void> endTabDrag() async {
    if (!isSupported) return;
    try {
      await channel.invokeMethod<void>('endTabDrag');
    } catch (e) {
      debugPrint('endTabDrag failed: $e');
    }
  }

  /// משחזר את החלון האחרון שנסגר. מחזיר true אם היה כזה.
  ///
  /// ⚠️ אפשרי **רק** מפני שחלון סגור מוסתר ולא נהרס: המנוע שלו חי עם
  /// הכרטיסיות שהיו בו, ולכן השחזור הוא הצגה בלבד ולא טעינה מחדש.
  Future<bool> restoreLastClosedWindow() async {
    if (!isSupported) return false;
    try {
      return await channel.invokeMethod<bool>('restoreLastClosedWindow') ??
          false;
    } catch (e) {
      debugPrint('restoreLastClosedWindow failed: $e');
      return false;
    }
  }

  /// ממיר נקודת מסך לקואורדינטות אזור-הלקוח של החלון הזה, בפיקסלים
  /// לוגיים.
  ///
  /// ⚠️ ההמרה ב-runner ולא כאן: המיקום מגיע מחלון אחר, ו-Flutter אינו
  /// יודע היכן החלון שלו יושב על המסך.
  Future<Offset?> screenToClient(int x, int y, double devicePixelRatio) async {
    if (!isSupported) return null;
    try {
      final p = await channel.invokeMapMethod<String, dynamic>(
        'screenToClient',
        {'x': x, 'y': y},
      );
      if (p == null) return null;
      return Offset(
        ((p['x'] as int?) ?? 0) / devicePixelRatio,
        ((p['y'] as int?) ?? 0) / devicePixelRatio,
      );
    } catch (e) {
      debugPrint('screenToClient failed: $e');
      return null;
    }
  }

  /// מודיע ל-runner באיזו משבצת באפיק החלון הזה יושב.
  ///
  /// ⚠️ בלי זה אי אפשר לגרור כרטיסיה בין חלונות: Win32 יודע איזה **חלון**
  /// נמצא תחת הסמן, ו-Dart מזהה חלונות לפי משבצת. זה המתרגם.
  Future<void> setBusSlot(int slot) async {
    if (!isSupported) return;
    try {
      await channel.invokeMethod<void>('setBusSlot', slot);
    } catch (e) {
      debugPrint('setBusSlot failed: $e');
    }
  }

  /// מה נמצא תחת סמן העכבר ברגע זה.
  ///
  /// [slot] הוא משבצת חלון אוצריא, או null כשהסמן מעל שולחן העבודה או מעל
  /// תוכנה אחרת. [isSelf] מבדיל בין שחרור מעל החלון שממנו גוררים לבין
  /// שחרור מעל חלון אחר.
  ///
  /// [isShellTray] הוא שורת המשימות של Windows (או חלון קופץ שלה). היא
  /// מדווחת בנפרד כי שחרור מעליה אינו מחווה של "פתח חלון כאן": היא נגישה
  /// גם בחלון ממוקסם, וקודם לכן שחרור עליה פתח חלון שני והכרטיסיה עזבה.
  /// ⚠️ מחזיר `null` כשלא ניתן היה לברר, ו**לא** "שולחן העבודה".
  ///
  /// הגרסה הקודמת החזירה `(slot: null, isSelf: false)` בכשל — בדיוק הצורה
  /// של "שוחרר על שולחן העבודה". כלומר כשל ערוץ פתח חלון חדש בפינה (0,0)
  /// ומחק את הכרטיסיה מהמקור.
  Future<({int? slot, bool isSelf, bool isShellTray, int x, int y})?>
  windowAtCursor() async {
    if (!isSupported) return null;
    try {
      final info = await channel.invokeMapMethod<String, dynamic>(
        'windowAtCursor',
      );
      if (info == null) return null;
      return (
        slot: info['slot'] as int?,
        isSelf: info['isSelf'] == true,
        isShellTray: info['isShellTray'] == true,
        x: (info['x'] as int?) ?? 0,
        y: (info['y'] as int?) ?? 0,
      );
    } catch (e) {
      debugPrint('windowAtCursor failed: $e');
      return null;
    }
  }

  /// סוגר את החלון הנוכחי בלי לסיים את התהליך.
  ///
  /// ⚠️ ולא `windowManager.destroy()`: הוא קורא ל-`DestroyWindow` מתוך
  /// טיפול בערוץ, כלומר מתוך ריצת ה-Dart של החלון. הריסת מנוע משם היא
  /// ריאנטרנטית, ונמדד שהיא מפילה את התהליך כולו בכל סגירת חלון.
  Future<void> closeSelf() async {
    if (!isSupported) return;
    try {
      await channel.invokeMethod<void>('closeSelf');
    } catch (e) {
      debugPrint('closeSelf failed: $e');
    }
  }

  /// שם ה-box של ההעדפות. חייב להתאים ל-[HiveCache.keyName].
  static const String _preferencesBoxName = 'app_preferences';

  /// המטען הוא מחרוזת ולא Map, כי הוא עובר כארגומנט לנקודת הכניסה של
  /// המנוע החדש (`set_dart_entrypoint_arguments`), וזו מקבלת מחרוזות בלבד.
  /// ⚠️ חשוף לבדיקות כדי שהמסלול ייבדק **דרך JSON** ולא רק
  /// `toJson`→`fromJson`. `jsonEncode` דורש פרימיטיבים, ומפה עם מפתחות
  /// שאינם מחרוזת חוזרת ממנו אחרת — טיפוס שעובר בדיקה ישירה יכול להיכשל
  /// כאן, והמשתמש רואה חלון חדש שנפתח בלי הכרטיסיה.
  @visibleForTesting
  static String encodePayloadForTest(OpenedTab? tab) => _encodePayload(tab);

  static String _encodePayload(OpenedTab? tab) {
    return jsonEncode({
      'version': 1,
      if (tab != null) 'tab': tab.toJson(),
      'settings': _snapshotPreferences(),
    });
  }

  /// צילום של כל העדפות החלון הנוכחי, כדי לזרוע בהן את החלון החדש.
  ///
  /// ⚠️ בלי זה החלון החדש חסר תועלת: שורש הנתונים שלו פרטי (Hive נועל
  /// בלעדית), ולכן הוא אינו יודע היכן הספרייה ומציג את מסך ההתחלה.
  ///
  /// זו **זריעה חד-פעמית ולא שיתוף חי**: שינוי הגדרה בחלון אחד לא יופיע
  /// בשני. השיתוף החי הוא פרק 3 במפת הדרכים.
  static Map<String, dynamic> _snapshotPreferences() {
    try {
      if (!Hive.isBoxOpen(_preferencesBoxName)) return const {};
      final box = Hive.box<dynamic>(_preferencesBoxName);
      final snapshot = <String, dynamic>{};
      for (final entry in box.toMap().entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String) continue;
        // רק ערכים שעוברים JSON. `CacheProvider` שומר פרימיטיבים ורשימות
        // מחרוזות בלבד, אבל בדיקה מפורשת עדיפה על מטען שנכשל בסריאליזציה
        // ומפיל את פתיחת החלון כולה.
        if (value is bool ||
            value is num ||
            value is String ||
            (value is List && value.every((e) => e is String))) {
          snapshot[key] = value;
        }
      }
      return snapshot;
    } catch (e) {
      debugPrint('_snapshotPreferences failed: $e');
      return const {};
    }
  }

  /// מפענח את צילום ההעדפות מתוך מטען.
  static Map<String, dynamic> decodePreferences(String? payload) {
    if (payload == null || payload.isEmpty) return const {};
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return const {};
      final settings = decoded['settings'];
      if (settings is! Map) return const {};
      return Map<String, dynamic>.from(settings);
    } catch (e) {
      debugPrint('decodePreferences failed: $e');
      return const {};
    }
  }

  /// סוג בקשה באפיק: קבלת כרטיסיה שהועברה מחלון אחר.
  static const String requestReceiveTab = 'receiveTab';

  /// סוג בקשה באפיק: תיאור החלון לתצוגה בתפריט.
  static const String requestDescribe = 'describe';

  /// סוג בקשה באפיק: כרטיסיה נגררת מעל החלון הזה כרגע.
  ///
  /// ⚠️ החלון היעד אינו יודע דבר על גרירה שמתרחשת בחלון אחר — הם isolates
  /// נפרדים, ומחוות העכבר נתפסת אצל המקור. בלי ההודעה הזו אין דרך להציג
  /// קו חיווי או להדגיש את היעד.
  static const String requestDragOver = 'dragOver';

  /// סוג בקשה באפיק: הגרירה עזבה את החלון הזה או הסתיימה.
  static const String requestDragLeave = 'dragLeave';

  /// מודיע לחלון [slot] שכרטיסיה נגררת מעליו, בנקודה גלובלית נתונה.
  ///
  /// מחזיר את מיקום ההכנסה ברצועת הכרטיסיות שלו, או null כשהסמן אינו מעל
  /// הרצועה — כך המקור יודע אם השחרור ימזג למקום מדויק או רק יעביר.
  Future<int?> notifyDragOver(int slot, int x, int y, String title) async {
    final result = await WindowBus.instance.request(slot, {
      'type': requestDragOver,
      'x': x,
      'y': y,
      'title': title,
    }, timeout: const Duration(milliseconds: 400));
    return result is int ? result : null;
  }

  /// מודיע לחלון [slot] שהגרירה עזבה אותו. fire-and-forget: אם לא נמסר,
  /// החיווי ייעלם ממילא בסיום הגרירה.
  void notifyDragLeave(int slot) {
    unawaited(
      WindowBus.instance.request(slot, {'type': requestDragLeave}),
    );
  }

  /// מעביר [tab] לחלון קיים במשבצת [slot].
  ///
  /// מחזיר true רק אם החלון היעד **אישר** שקיבל את הכרטיסיה. זה חשוב:
  /// המעביר מסיר את הכרטיסיה מעצמו רק אחרי אישור, אחרת כרטיסיה שנשלחה
  /// לחלון שנסגר בדיוק אז הייתה נעלמת משני הצדדים.
  ///
  /// ⚠️ שלושה מצבים ולא שניים: `true` אושר, `false` סורב במפורש, ו-`null`
  /// **לא ידוע** — היעד לא ענה בזמן, וייתכן שקלט את הכרטיסיה בכל זאת.
  /// [index] הוא מיקום ההכנסה ברצועת היעד, כשהשחרור היה מעליה. `null`
  /// מוסיף בסוף — התנהגות "העבר לחלון קיים" מהתפריט.
  /// ⚠️ **אינו** קורא ל-[canTransfer]. הקורא בדק כבר — בתחילת הגרירה או
  /// לפני פעולת התפריט — ובדיקה חוזרת כאן פירושה בניית כרטיסיה שלמה שנייה
  /// לכל העברה.
  Future<bool?> sendTabToWindow(int slot, OpenedTab tab, {int? index}) async {
    final result = await WindowBus.instance.request(
      slot,
      {'type': requestReceiveTab, 'tab': tab.toJson(), 'index': ?index},
      // ⚠️ היעד מוסיף את הכרטיסיה ומנווט **לפני** שהוא עונה, וחלון עסוק
      // נמדד ב-2,092ms בטעינת קטלוג. ברירת המחדל של 3 שניות פקעה בעוד
      // היעד כבר קלט — והמשתמש ראה את הכרטיסיה בשני החלונות.
      timeout: const Duration(seconds: 8),
    );
    if (result is bool) return result;
    return null;
  }

  /// החלונות האחרים שעונים על האפיק, עם סימון נראות.
  ///
  /// ⚠️ שני מקורות, ובמכוון: מי **עונה** נקבע באפיק (רק חלון חי עונה), ומי
  /// **מוצג** נקבע בנייטיב. חלון סגור עונה ואינו מוצג, ולכן אסור להציע
  /// אותו כיעד לכרטיסיה — הוא היה מאשר קבלה, המקור היה מוחק, והכרטיסיה
  /// הייתה נמחקת כשהחלון יוחזר לשימוש.
  Future<List<WindowPeer>> otherWindows() async {
    final peers = await WindowBus.instance.peers();
    if (peers.isEmpty) return peers;
    final visible = await visibleSlots();
    if (visible == null) return peers;
    return [
      for (final peer in peers)
        peer.copyWith(isVisible: visible.contains(peer.slot)),
    ];
  }

  /// הרשימה האחרונה שנסרקה, לשימוש מקוד **סינכרוני**.
  ///
  /// ⚠️ קיימת כי בניית תפריט ההקשר סינכרונית, וסריקת החלונות אינה יכולה
  /// להיות. `WindowBusHost` מרענן אותה ברקע. רשימה מעט לא-עדכנית אינה
  /// מסוכנת: שליחה לחלון שנסגר בינתיים נכשלת ומדווחת למשתמש, ולא מאבדת
  /// את הכרטיסיה.
  static final ValueNotifier<List<WindowPeer>> _knownPeers =
      ValueNotifier<List<WindowPeer>>(const []);

  static List<WindowPeer> get knownPeers => _knownPeers.value;

  /// עדכון הרשימה. הקורא היחיד הוא `WindowBusHost`.
  static void publishKnownPeers(List<WindowPeer> peers) {
    _knownPeers.value = peers;
  }

  /// כשל בפתיחת חלון — מברר אם הסיבה היא התקרה ומדווח בהתאם.
  ///
  /// ⚠️ מקום אחד. הלוגיקה `windowCount → count >= max` והמחרוזות שלה
  /// שוכפלו בשלושה אתרי קריאה, ובכל אחד מהם נוסחו מחדש.
  Future<void> reportOpenWindowFailure() async {
    final info = await windowCount();
    if (info != null && info.count >= info.max) {
      UiSnack.show(WindowMessages.windowLimitReached(info.max));
    } else {
      UiSnack.showError(WindowMessages.openWindowFailed);
    }
  }

  /// האם התקרה כבר הושגה — נבדק **לפני** שמציעים למשתמש לפתוח חלון.
  ///
  /// ⚠️ בלי הבדיקה המוקדמת המשתמש משלים גרירה שלמה (כולל בחירת אזור
  /// ב-Snap Layouts) או ממתין ל-`openWindow` עד 20 שניות, ורק אז מקבל
  /// "אפשר לפתוח עד N חלונות".
  Future<bool> canOpenAnotherWindow() async {
    if (!isSupported) return false;
    final info = await windowCount();
    // כשלא ידוע — לתת ל-runner להכריע. הוא אוכף את התקרה ממילא, וחסימה על
    // סמך כשל ערוץ הייתה מונעת פתיחת חלון בלי סיבה.
    if (info == null) return true;
    return info.count < info.max;
  }

  /// החלונות שאפשר להעביר אליהם כרטיסיה — מוצגים על המסך בלבד.
  ///
  /// ⚠️ זה הסינון שמונע את מסלול האובדן: חלון שהמשתמש סגר עדיין עונה
  /// באפיק, ולכן הופיע בתפריט, אישר קבלה, והמקור מחק את הכרטיסיה. היא חיה
  /// בחלון בלתי-נראה ונמחקה סופית כשהוא הוחזר לשימוש.
  static List<WindowPeer> get transferTargets =>
      knownPeers.where((peer) => peer.isVisible).toList();

  /// האם המטען מכיל כרטיסיה, בלי לפענח אותה.
  ///
  /// ⚠️ קיים כי הפענוח המלא תלוי ב-`Settings` ואינו אפשרי בנקודת הכניסה,
  /// אבל הניווט למסך הקריאה צריך להיקבע עוד לפני `runApp`.
  static bool payloadHasTab(String? payload) {
    if (payload == null || payload.isEmpty) return false;
    try {
      final decoded = jsonDecode(payload);
      return decoded is Map && decoded['tab'] is Map;
    } catch (_) {
      return false;
    }
  }

  /// האם הכרטיסיה שורדת מסע הלוך-ושוב של סריאליזציה.
  ///
  /// ⚠️ נבדק **לפני** שמסירים אותה מהחלון המקורי. כרטיסיה שאינה ניתנת
  /// לשחזור הייתה נעלמת מהמקור ולא נפתחת ביעד — כלומר אובדן מידע. עדיף
  /// לא להעביר מאשר לאבד.
  ///
  /// ⚠️ "לא זרק" אינו "נאמן". טאב מפוצל עובר את הבדיקה גם כשחלונית אחת
  /// נכשלה: `decodeCombinedTab` בולע אותה ומחזיר את השורדת — התנהגות
  /// נכונה בשחזור מדיסק (עדיף חצי ספר מכלום), ואובדן מידע בהעברה (הכרטיסיה
  /// כבר נמחקת מהמקור). לכן נבדק גם **מבנה** התוצאה ולא רק היעדר חריגה.
  /// ⚠️ נבדק דרך **המסלול האמיתי** — `jsonEncode` ואחריו `jsonDecode` —
  /// ולא `toJson`→`fromJson` ישירות.
  ///
  /// זו הייתה חור: `jsonEncode` דורש פרימיטיבים, ומפה עם מפתחות שאינם
  /// מחרוזת חוזרת ממנו עם מפתחות מחרוזת. כלומר כרטיסיה יכלה לעבור את
  /// הבדיקה, להימחק מהמקור, ולהיכשל בפענוח ביעד — והמשתמש רואה חלון חדש
  /// שנפתח **בלי הכרטיסיה**. אם `canTransfer` אמור להיות ההגנה, הוא חייב
  /// לבדוק בדיוק את מה שיקרה.
  /// ⚠️ **הבדיקה יקרה — אל תקרא לה בלולאה.** הפענוח בונה כרטיסיה מלאה: את
  /// ה-BLoC שלה, את ה-repository ואת המנויים ואת ה-`ValueNotifier`-ים. לכן
  /// היא נבדקת פעם אחת בתחילת הגרירה ([CrossWindowTabDrag.begin]) או לפני
  /// פעולת תפריט, והתוצאה נזכרת.
  static bool canTransfer(OpenedTab tab) {
    OpenedTab? restored;
    try {
      restored = decodePayload(_encodePayload(tab));
      if (restored == null) {
        debugPrint(
          'canTransfer: ${tab.runtimeType} אינה שורדת את מסלול המטען',
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
      // ⚠️ הכרטיסיה שנבנתה כאן נזרקת, אבל בלי השחרור המנויים וה-notifiers
      // שלה נשארים חיים לכל אורך חיי החלון.
      try {
        restored?.dispose();
      } catch (e) {
        debugPrint('canTransfer: dispose of probe tab failed: $e');
      }
    }
  }

  /// מפענח מטען שהתקבל בנקודת הכניסה של חלון משני.
  ///
  /// מחזיר null כשאין מטען או כשהוא פגום — חלון שנפתח בלי טאב תקין עולה
  /// ריק, וזו התנהגות מכוונת: עדיף חלון ריק מחלון שקורס באתחול.
  static OpenedTab? decodePayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return null;
      final tabJson = decoded['tab'];
      if (tabJson is! Map) return null;
      return OpenedTab.fromJson(Map<String, dynamic>.from(tabJson));
    } catch (e) {
      debugPrint('decodePayload failed: $e');
      return null;
    }
  }
}

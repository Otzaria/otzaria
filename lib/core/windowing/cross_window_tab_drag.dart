import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/messages/window_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/drag_preview_colors.dart';
import 'package:otzaria/core/windowing/runner_window_channel.dart';
import 'package:otzaria/core/windowing/multiview/in_process_tab_drop.dart';
import 'package:otzaria/core/windowing/window_opener.dart';
import 'package:otzaria/core/windowing/tab_drag_preview.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/utils/confirm_close_tabs.dart';

/// גרירת כרטיסיה **מחוץ** לחלון: לחלון אוצריא אחר, או אל שולחן העבודה.
///
/// ⚠️ מחלקה אחת לשתי הרצועות, ובמכוון: גם הרצועה האנכית קולטת כרטיסיות
/// מחלונות אחרים, ובלי המחלקה הזו היא לא הייתה שולחת.
///
/// Flutter אינו יודע דבר מחוץ לחלון שלו, ולכן שני חלקים נייטיביים מגשרים:
/// תצוגת הגרירה (`beginTabDrag`) וזיהוי מה נמצא תחת הסמן (`windowAtCursor`).
class CrossWindowTabDrag {
  CrossWindowTabDrag({@visibleForTesting InProcessTabDrops? inProcess})
    : _inProcessOverride = inProcess;

  final InProcessTabDrops? _inProcessOverride;

  /// היעדים הם חלונות התהליך, וההעברה ישירה בין ה-blocs שלהם.
  InProcessTabDrops get _inProcess =>
      _inProcessOverride ?? InProcessTabDrops.instance;

  /// החלון שהרצועה יושבת בו; מולו נמדד "שחרור מעל החלון עצמו".
  AppWindowId _sourceWindow = AppWindowId.primary;

  int? get _selfHwnd => _inProcess.hwndOf(_sourceWindow);

  /// ⚠️ קצב קבוע ולא `onDragUpdate`: `Draggable` מדווח עשרות עדכונים
  /// בשנייה, וכל אחד היה קריאת ערוץ. 60ms מספיקים כדי שהחיווי
  /// ירגיש רציף, ומורידים את התעבורה בסדר גודל.
  static const Duration _pollInterval = Duration(milliseconds: 60);

  /// המסירה המוקדמת משאירה ל-Windows תנועה שתפעיל את Snap Layouts.
  /// יציאה מהרצועה מבדילה אותה מסידור כרטיסיות מקומי.
  static const RunnerWindowChannel _service = RunnerWindowChannel();

  /// ההעברה סוגרת את הכרטיסיה במקור ומסיימת סשן תיקון שבה, ולכן קודמת לה
  /// בדיקת שינויים שלא נשמרו כמו ב"העבר לחלון" שבתפריט.
  @visibleForTesting
  static Future<bool> Function(OpenedTab tab) confirmTransfer =
      confirmTabTransferWithUnsavedChanges;

  /// נשמרת יציאה מהרצועה, גם אם הסמן חזר אליה בדרך מעלה.
  bool _leftStrip = false;

  /// מזהה עולה לכל גרירה, לגידור תשובות אסינכרוניות של גרירה שהסתיימה.
  int _dragGeneration = 0;

  /// כותרת הכרטיסיה הנגררת כרגע, לשליחה לחלון היעד.
  String? _draggedTitle;

  /// הכרטיסיה הנגררת ובלוק הכרטיסיות של חלון המקור, למסירה מ-[_poll].
  OpenedTab? _draggedTab;
  TabsBloc? _sourceBloc;

  /// ביטול הגרירה של Flutter — ראו `_DraggableTabState._cancelDrag`.
  VoidCallback? _cancelFlutterDrag;

  /// האם הגרירה כבר נמסרה ל-Windows.
  ///
  /// ⚠️ מונע מסלול כפול. הביטול שנשלח ל-Flutter מגיע ל-`onDraggableCanceled`,
  /// כלומר [handleDroppedOutside] **כן** ייקרא — ובלי הדגל אותה כרטיסיה
  /// הייתה מטופלת פעמיים.
  bool _handedOff = false;

  Timer? _timer;

  /// החלון שקיבל את ההודעה האחרונה, כדי לנקות את החיווי כשעוזבים אותו.
  int? _lastDragOverSlot;

  /// האם הכרטיסיה שורדת העברה. נבדק **פעם אחת** בתחילת הגרירה.
  ///
  /// ⚠️ [RunnerWindowChannel.canTransfer] בונה כרטיסיה מלאה — BLoC,
  /// repository ומנויים — ולכן אסור לקרוא לה בלולאת הפעימות של 60ms.
  bool _transferable = true;

  /// ההודעה על כרטיסיה שאינה ניתנת להעברה כבר הוצגה.
  bool _rejectionReported = false;

  /// מוק חייב להישלח לפני המסירה; הנייטיב אינו מעדכנו בתוך גרירת מערכת.
  bool _snapshotSent = false;

  /// פעימות ולא שעון: המסירה מוכרעת בתוך [_poll], והספירה דטרמיניסטית גם בזמן מזויף.
  int _pollsSinceStart = 0;

  /// ⚠️ חסום ולא אינסופי: צילום שנכשל לא יגיע לעולם, וגרירה שלא נמסרת גרועה
  /// ממוק בגודל השרטוט. ~360ms מכסים שני צילומים ומיזוג.
  static const int _snapshotGracePolls = 6;

  /// האם עוד כדאי להמתין למוק לפני מסירת הגרירה למערכת.
  bool get _awaitingSnapshot =>
      !_snapshotSent && _pollsSinceStart <= _snapshotGracePolls;

  /// מיקום ההכנסה שהחלון היעד דיווח עליו, לשימוש בשחרור.
  int? _remoteDropIndex;

  /// נקודת ה-y הנמוכה ביותר, שממנה נמדדת היציאה מעלה.
  /// נזרעת בתחילת הגרירה כדי לא לפספס תנועה לפני פעימת המעקב.
  int? _deepestCursorY;

  /// מתחיל את תצוגת הגרירה הנייטיבית ואת המעקב אחרי החלון שתחת הסמן.
  ///
  /// [colors] נלקחים מהערכה של החלון — ראו [DragPreviewColors].
  ///
  /// [tabsBloc] ו-[cancelDrag] נדרשים כדי למסור את הגרירה ל-Windows
  /// (Snap Layouts) — ראו [_handOffToSystem]. בלעדיהם הגרירה עובדת
  /// כרגיל, וההחלטה נופלת ב-[handleDroppedOutside] בלבד.
  void begin(
    OpenedTab tab,
    DragPreviewColors colors, {
    TabsBloc? tabsBloc,
    VoidCallback? cancelDrag,
    AppWindowId? sourceWindow,
  }) {
    if (!RunnerWindowChannel.canDragTabsOut) return;
    _sourceWindow = sourceWindow ?? AppWindowId.primary;
    _draggedTitle = tab.title;
    _draggedTab = tab;
    _sourceBloc = tabsBloc;
    _cancelFlutterDrag = cancelDrag;
    _handedOff = false;
    _rejectionReported = false;
    // ⚠️ מיקום הכנסה של גרירה **קודמת** אינו תקף לזו. בלי האיפוס כרטיסיה
    // נכנסה למקום שאליו כוונה הגרירה שלפניה.
    _remoteDropIndex = null;
    // מאפס עומק ומוק מהגרירה הקודמת.
    _deepestCursorY = null;
    _leftStrip = false;
    _dragGeneration++;
    // פעם אחת לכל גרירה — ראו [_transferable].
    _transferable = RunnerWindowChannel.canTransfer(tab);
    _snapshotSent = false;
    _pollsSinceStart = 0;
    // דוגם לפני פעימת המעקב הראשונה.
    unawaited(_captureDragOrigin(_dragGeneration));
    final title = tab.title;
    // התצוגה מוצגת רק כשהסמן יוצא מחלון המקור, ולכן אין כפילות מול
    // ה-feedback של `Draggable`.
    unawaited(
      _service.beginTabDrag(title, colors: colors, sourceHwnd: _selfHwnd),
    );
    _timer?.cancel();
    _timer = Timer.periodic(_pollInterval, (_) => unawaited(_poll()));
  }

  /// מחליף את השרטוט במוק של החלון. נקרא **אחרי** [begin], כשהוא מוכן.
  ///
  /// ⚠️ הבעלות על התמונה שב-[preview] עוברת לכאן — היא משוחררת גם בכשל.
  ///
  /// ⚠️ **נשלח מיד, ולא ביציאה מהחלון:** צילום אחרי תחילת הלולאה המודאלית אינו
  /// מוחל, ו-`snapped` כוזב פותח חלון חדש במקום להעביר לחלון שתחת הסמן.
  void applySnapshot(TabWindowPreview preview, int generation) {
    if (!RunnerWindowChannel.canDragTabsOut || generation != _dragGeneration) {
      preview.image.dispose();
      return;
    }
    unawaited(_sendSnapshot(preview, generation));
  }

  /// שולח צילום רק אם יש בו פיקסלים גלויים; צילום שקוף משאיר את שרטוט הגרירה.
  Future<void> _sendSnapshot(TabWindowPreview preview, int generation) async {
    final image = preview.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return;
      final rgba = data.buffer.asUint8List();
      if (!_hasVisiblePixels(rgba)) {
        debugPrint(
          'צילום הכרטיסיה יצא שקוף (${image.width}×${image.height}) — '
          'נשאר השרטוט',
        );
        return;
      }
      if (generation != _dragGeneration) return;
      final sent = await _service.setTabDragImage(
        rgba,
        image.width,
        image.height,
        targetWidth: preview.targetWidth,
        targetHeight: preview.targetHeight,
      );
      // המסירה המוקדמת מותרת רק אחרי שהמוק נשלח.
      if (sent && generation == _dragGeneration) _snapshotSent = true;
    } catch (e) {
      debugPrint('צילום הכרטיסיה לגרירה נכשל: $e');
    } finally {
      image.dispose();
    }
  }

  /// דוגם פיקסלים תחילה, ואז סורק הכול רק אם הדגימה לא מצאה תוכן גלוי.
  static bool _hasVisiblePixels(Uint8List rgba) {
    for (var i = 3; i < rgba.length; i += 4 * 97) {
      if (rgba[i] != 0) return true;
    }
    // הדגימה החמיצה — בדיקה מלאה לפני שמכריזים על תמונה ריקה.
    for (var i = 3; i < rgba.length; i += 4) {
      if (rgba[i] != 0) return true;
    }
    return false;
  }

  /// מסיים את **המעקב**, ומשאיר את התצוגה קפואה במקום השחרור.
  ///
  /// ⚠️ `freezeTabDrag` ולא `endTabDrag`: הסיום נורה **לפני**
  /// [handleDroppedOutside], ועוד לא ידוע אם ייפתח חלון. מי שאינו פותח מסתיר.
  ///
  /// ⚠️ [_remoteDropIndex] **אינו** מתאפס כאן: השחרור צריך את המיקום.
  void end() {
    if (!RunnerWindowChannel.canDragTabsOut) return;
    // ⚠️ הגרירה כבר בידי Windows. `freezeTabDrag` כאן היה מחזיר את הרוח
    // אחרי שהחלון האמיתי הסתיר אותה, ו-`notifyDragLeave` היה מנקה חיווי
    // של חלון שכבר אינו רלוונטי.
    if (_handedOff) return;
    _timer?.cancel();
    _timer = null;
    final last = _lastDragOverSlot;
    if (last != null) _notifyDragLeave(last);
    _lastDragOverSlot = null;
    _draggedTitle = null;
    // צילום שלא נשלח (הגרירה נשארה בתוך החלון) אינו נחוץ יותר.
    unawaited(_service.freezeTabDrag());
  }

  /// ⚠️ חובה בסגירת החלון. הטיימר שואל את ה-runner כל 60ms, ולולאה שנשארה
  /// אחרי שהחלון נסגר ממשיכה לעדכן חיווי של גרירה שאיננה.
  void dispose() {
    _timer?.cancel();
    _timer = null;
    // ⚠️ בלי זה הרוח הנייטיבית נשארת חיה ומצוירת אחרי שהרצועה ירדה מהעץ.
    // המסירה למערכת מנקה בעצמה, ולכן רק גרירה שלא נמסרה מטופלת כאן.
    if (_draggedTitle != null && !_handedOff) _hidePreview();
    // ⚠️ המחלקה חיה יותר מגרירה בודדת (היא שדה של הרצועה). החזקה של
    // כרטיסיה שאולי כבר `dispose`-ה היא הפניה תלויה.
    _draggedTitle = null;
    _draggedTab = null;
    _sourceBloc = null;
    _cancelFlutterDrag = null;
    _lastDragOverSlot = null;
    _remoteDropIndex = null;
    _deepestCursorY = null;
  }

  Future<void> _poll() async {
    final generation = _dragGeneration;
    final title = _draggedTitle;
    if (title == null || _handedOff) return;
    _pollsSinceStart++;
    final target = await _windowAtCursor();
    // ⚠️ כשל בירור אינו "שולחן העבודה" — פשוט מדלגים על הפעימה.
    if (target == null) return;
    // תשובה מאוחרת אינה רשאית לעדכן גרירה שכבר הסתיימה או הוחלפה.
    if (generation != _dragGeneration || _draggedTitle == null || _handedOff) {
      return;
    }
    final slot = target.isSelf ? null : target.slot;

    if (_lastDragOverSlot != null && _lastDragOverSlot != slot) {
      _notifyDragLeave(_lastDragOverSlot!);
      _remoteDropIndex = null;
    }
    _lastDragOverSlot = slot;

    final deepest = _trackDepth(target.y);

    if (target.isSelf) {
      // מסירה מוקדמת דורשת יציאה מהרצועה, תנועה מעלה ומוק זמין.
      // כרטיסיה לא ניתנת להעברה נשארת במסלול המקומי בלי הודעה מטעה.
      if (_leftStrip &&
          _transferable &&
          _snapshotSent &&
          target.approachingTop &&
          deepest - target.y >= target.minUpwardTravel) {
        await _handOffToSystem();
      }
      return;
    }

    // הסמן בחוץ: מכאן והלאה יש למי להציג את התצוגה הנייטיבית.

    // ⚠️ כרטיסיה שאינה ניתנת להעברה נעצרת **כאן**, עם הודעה ועצירת הטיימר:
    // חזרה שקטה הייתה משאירה את הפעימות רצות בלי חיווי למשתמש.
    if (!_transferable) {
      _rejectTransfer();
      return;
    }

    // ⚠️ מוק שמגיע אחרי תחילת לולאת ההזזה נדחה (`SetImage` מדלג על `Compose`),
    // ולכן מדלגים על הפעימה עד שנשלח — לכל היותר [_snapshotGracePolls].
    if (_awaitingSnapshot) return;

    // מעבר לכך — מיד: המסירה אינה פותחת חלון, והיעד מוכרע בשחרור לפי מה
    // שתחת הסמן.
    await _handOffToSystem();
  }

  /// מסמן יציאה מהרצועה; סידור כרטיסיות מקומי אינו מסמן אותה.
  void notePointerLeftStrip() => _leftStrip = true;

  /// מעדכן את עומק הסמן לגרירה שירדה ואז חזרה מעלה.
  int _trackDepth(int y) {
    final deepest = _deepestCursorY;
    if (deepest == null || y > deepest) {
      _deepestCursorY = y;
      return y;
    }
    return deepest;
  }

  /// דוגם את מיקום הסמן בתחילת הגרירה, לפני פעימת המעקב הראשונה.
  /// ה-generation מונע מדגימה מאוחרת לזרוע עומק של גרירה קודמת.
  Future<void> _captureDragOrigin(int generation) async {
    final target = await _windowAtCursor();
    if (target == null || generation != _dragGeneration) return;
    _trackDepth(target.y);
  }

  /// האם [tab] ניתנת להעברה, בלי לבנות אותה מחדש כשכבר נבדקה.
  ///
  /// ⚠️ הבדיקה עצמה יקרה (ראו [RunnerWindowChannel.canTransfer]), ולכן
  /// התוצאה של [begin] נשמרת. הנפילה-לאחור קיימת למסלול שבו [begin] לא רץ
  /// כלל — רצועה שחיברה `onDroppedOutside` בלי `onDragStarted` — ושם עדיף
  /// לשלם על בדיקה אחת מלאבד כרטיסיה.
  bool _canTransfer(OpenedTab tab) => identical(tab, _draggedTab)
      ? _transferable
      : RunnerWindowChannel.canTransfer(tab);

  /// עוצר את הגרירה החוצה ומודיע למשתמש. פעם אחת לכל גרירה.
  void _rejectTransfer() {
    if (_rejectionReported) return;
    _rejectionReported = true;
    // ⚠️ אותו דגל של המסירה למערכת: הוא מה שמונע מ-`handleDroppedOutside`
    // לטפל בכרטיסיה שוב אחרי הביטול ששלחנו ל-Flutter.
    _handedOff = true;
    _timer?.cancel();
    _timer = null;
    final last = _lastDragOverSlot;
    if (last != null) _notifyDragLeave(last);
    _lastDragOverSlot = null;
    _draggedTitle = null;
    _hidePreview();
    _cancelFlutterDrag?.call();
    UiSnack.showError(WindowMessages.cannotTransferTab);
  }

  /// מוסר את הגרירה ל-Windows, ומטפל בתוצאה כשהמשתמש שחרר.
  ///
  /// ⚠️ ה-shell פותח את מסדר החלונות (Snap Layouts) רק כשנגרר **חלון**, ולכן
  /// התצוגה עצמה נמסרת למערכת. חלון אוצריא נפתח **רק בשחרור**.
  ///
  /// ⚠️ מרגע שלולאת ההזזה לוכדת את העכבר Flutter לא יראה את השחרור, ולכן
  /// `_cancelFlutterDrag`; משם [_handedOff] מונע טיפול כפול.
  Future<void> _handOffToSystem() async {
    if (_handedOff) return;
    final tab = _draggedTab;
    final bloc = _sourceBloc;
    // ⚠️ עוצרים את הלולאה ולא רק חוזרים: חזרה שקטה משאירה את הטיימר פועל,
    // עם פעימת ערוץ ותצוגה נייטיבית ב-60Hz לכל אורך הגרירה.
    if (tab == null || bloc == null) {
      _handedOff = true;
      _timer?.cancel();
      _timer = null;
      _hidePreview();
      return;
    }

    _handedOff = true;
    final last = _lastDragOverSlot;
    if (last != null) _notifyDragLeave(last);
    _lastDragOverSlot = null;
    _draggedTitle = null;

    _cancelFlutterDrag?.call();
    final outcome = await _dragOutToSystem();
    _timer?.cancel();
    _timer = null;

    // `ran == false` פירושו שהנייטיב לא הריץ לולאת גרירה בכלל (למשל אין
    // תצוגה חיה). אין תוצאה להסתמך עליה, ולכן אין להעביר את הכרטיסיה.
    if (outcome == null || !outcome.ran) return _hidePreview();
    // ⚠️ נשאר בקוד. את מסלול הגרירה אי אפשר לבדוק אוטומטית — הוא תלוי
    // בהחלטות ה-shell — ושורה אחת בלוג היא ההבדל בין אבחון לניחוש.
    debugPrint(
      'גרירה הסתיימה: snapped=${outcome.snapped} '
      'rect=${outcome.left},${outcome.top} '
      '${outcome.width}×${outcome.height} '
      'slot=${outcome.slot} isSelf=${outcome.isSelf} '
      'tray=${outcome.isShellTray}',
    );

    // ⚠️ הצמדה היא החלטה מפורשת, ולכן עוקפת את "מה תחת הסמן": האזור המוצמד
    // מכסה לרוב את חלון המקור, ו-`isSelf` היה מבטל את הפתיחה בשקט.
    if (!outcome.snapped) {
      // שחרור חזרה מעל חלון המקור — ביטול. אחרת כל גרירה שיצאה וחזרה
      // הייתה פותחת חלון.
      if (outcome.isSelf) return _hidePreview();

      // ⚠️ שורת המשימות אינה מחווה של "פתח חלון כאן". היא נגישה גם בחלון
      // ממוקסם, ולכן שחרור עליה הוא כמעט תמיד החטאה.
      // ⚠️ לולאת ההזזה כולאת את הסמן באזור העבודה: מה שתחתיו אינו היעד,
      // ולכן גם חלון אוצריא שם אינו קולט.
      if (outcome.isShellTray ||
          outcome.atTaskbarEdge ||
          _outsideWorkArea(outcome.slot, outcome.inWorkArea)) {
        debugPrint('גרירה שוחררה מעל שורת המשימות — מבוטלת');
        return _hidePreview();
      }
    }

    if (!await confirmTransfer(tab)) return _hidePreview();

    if (!outcome.snapped && outcome.slot != null) {
      // הכרטיסיה נכנסת לחלון קיים — אין מה להחליף את הרוח, והיא מוסתרת
      // מיד כדי שלא תרחף מעל היעד.
      _hidePreview();
      await _transferToPeer(outcome.slot!, tab, bloc, outcome.x, outcome.y);
      return;
    }

    // ⚠️ מסגרת מדויקת **רק** אחרי הצמדה: התצוגה עצמה בגודל כרטיסיה. בלי
    // הצמדה עוברת הפינה שבה המשתמש ראה את התצוגה נעצרת, ולא מיקום הסמן.
    final moved = await WindowOpener.current.openWindow(
      tab: tab,
      origin: outcome.snapped ? null : (x: outcome.left, y: outcome.top),
      bounds: outcome.snapped
          ? (
              left: outcome.left,
              top: outcome.top,
              width: outcome.width,
              height: outcome.height,
            )
          : null,
    );
    if (moved) {
      _hideAfterViewOpened();
      bloc.add(RemoveTab(tab));
      return;
    }

    _hidePreview();
    await WindowOpener.current.reportOpenWindowFailure();
  }

  /// מעביר את הכרטיסיה לחלון [slot], למקום המדויק שתחת הסמן.
  ///
  /// ⚠️ מיקום ההכנסה נשאל **כאן**, ברגע השחרור, ולא בפעימות הגרירה: מהרגע
  /// שהמסירה למערכת התחילה ה-Dart של המקור אינו מקבל עדכוני מיקום, ולכן
  /// המסלול הזה היה תמיד `index: null` — כלומר הכרטיסיה נכנסה בסוף
  /// הרצועה, גם כשהמשתמש כיוון לנקודה מסוימת בה.
  Future<void> _transferToPeer(
    int slot,
    OpenedTab tab,
    TabsBloc bloc,
    int x,
    int y,
  ) async {
    final index =
        _remoteDropIndex ??
        await _inProcess.notifyDragOver(slot, x, y, tab.title);
    _remoteDropIndex = null;
    final moved = await _inProcess.sendTabToWindow(slot, tab, index: index);
    if (moved == true) {
      bloc.add(RemoveTab(tab));
      return;
    }
    // החיווי ביעד הודלק על ידי `notifyDragOver` — יש לכבות אותו.
    _notifyDragLeave(slot);
    UiSnack.showError(
      moved == false
          ? WindowMessages.transferFailed
          : WindowMessages.transferUnconfirmed,
    );
  }

  /// כרטיסיה שוחררה מחוץ לכל יעד הפלה — ייתכן מחוץ לחלון.
  ///
  /// ⚠️ Flutter אינו יודע דבר מחוץ לחלון שלו, ולכן השאלה "לאן שוחררה"
  /// נשאלת מ-Win32: מה נמצא תחת הסמן ברגע השחרור.
  ///
  /// ארבע תוצאות:
  /// * מעל החלון הזה עצמו — שחרור בתוך החלון שלא פגע ביעד. אין לעשות דבר,
  ///   אחרת כל גרירה שהתפספסה הייתה פותחת חלון.
  /// * מעל שורת המשימות — ביטול. ראו [_service.windowAtCursor].
  /// * מעל חלון אוצריא אחר — הכרטיסיה עוברת אליו.
  /// * מעל שולחן העבודה או תוכנה אחרת — נפתח חלון חדש, כמו בדפדפן.
  Future<void> handleDroppedOutside(OpenedTab tab, TabsBloc tabsBloc) async {
    // ⚠️ הגרירה נמסרה ל-Windows, והביטול ששלחנו ל-Flutter מגיע לכאן.
    // בלי היציאה הזו אותה כרטיסיה הייתה מטופלת פעמיים.
    if (_handedOff) return;

    final target = await _windowAtCursor();

    // ⚠️ כל יציאה מוקדמת מכאן חייבת להסתיר את הרוח שהוקפאה ב-[end].
    // רק המסלול שפותח חלון משאיר אותה, כדי שהיא תוחלף במשהו אמיתי.
    //
    // ⚠️ `null` הוא "לא ידוע", ולא "שולחן העבודה": כך שאילתה שנכשלה אינה
    // פותחת חלון בפינה (0,0) ואינה מוחקת את הכרטיסיה מהמקור.
    if (target == null) return _hidePreview();
    if (target.isSelf) return _hidePreview();

    // ⚠️ שחרור מעל שורת המשימות אינו מחווה של "פתח חלון כאן". היא נגישה
    // גם בחלון ממוקסם, ולכן שחרור עליה הוא כמעט תמיד החטאה.
    if (target.isShellTray ||
        _outsideWorkArea(target.slot, target.inWorkArea)) {
      debugPrint('גרירה שוחררה מעל שורת המשימות — מבוטלת');
      return _hidePreview();
    }

    if (!_canTransfer(tab)) {
      _hidePreview();
      UiSnack.showError(WindowMessages.cannotTransferTab);
      return;
    }

    if (!await confirmTransfer(tab)) return _hidePreview();

    if (target.slot != null) {
      // הכרטיסיה נכנסת לחלון קיים — אין מה להחליף את הרוח, והיא מוסתרת
      // מיד כדי שלא תרחף מעל היעד.
      _hidePreview();
      await _transferToPeer(target.slot!, tab, tabsBloc, target.x, target.y);
      return;
    }

    // ⚠️ החלון נפתח **בנקודת השחרור**, והרוח נשארת שם עד שהוא נחשף.
    final moved = await WindowOpener.current.openWindow(
      tab: tab,
      // מסלול הנפילה, כשהגרירה לא נמסרה למערכת: אין תצוגה שנעצרה
      // במקום, ולכן הסמן הוא כל מה שיש.
      origin: (x: target.x, y: target.y),
    );
    if (moved) {
      _hideAfterViewOpened();
      tabsBloc.add(RemoveTab(tab));
      return;
    }
    _hidePreview();
    await WindowOpener.current.reportOpenWindowFailure();
  }

  void _hidePreview() => unawaited(_service.endTabDrag());

  /// שחרור על "שולחן העבודה" מחוץ לאזור העבודה של כל צג הוא שורת משימות
  /// או appbar, גם כשהמחלקה שלה לא זוהתה. חלון אוצריא שם קולט.
  bool _outsideWorkArea(int? slot, bool inWorkArea) =>
      slot == null && !inWorkArea;

  /// ה-runner אינו מכיר חלונות Dart, ולכן הרוח מוסתרת כאן כשחלון נפתח.
  void _hideAfterViewOpened() => _hidePreview();

  void _notifyDragLeave(int slot) => _inProcess.notifyDragLeave(slot);

  /// מה שתחת הסמן: המשבצת היא של חלון התהליך שה-HWND שלו תחת הסמן, ו-isSelf
  /// נמדד מול חלון המקור ולא תמיד מול החלון הראשי.
  Future<CursorTarget?> _windowAtCursor() async {
    final drops = _inProcess;
    final target = await _service.windowAtCursor(
      selfHwnd: _selfHwnd,
      withHwnd: true,
    );
    if (target == null) return target;
    final slot = drops.resolve(hwnd: target.hwnd, runnerSlot: target.slot);
    return (
      slot: slot,
      isSelf: target.isSelf || _isSourceSlot(drops, slot),
      isShellTray: target.isShellTray,
      inWorkArea: target.inWorkArea,
      approachingTop: target.approachingTop,
      minUpwardTravel: target.minUpwardTravel,
      x: target.x,
      y: target.y,
      hwnd: target.hwnd,
    );
  }

  Future<SystemDragOutcome?> _dragOutToSystem() async {
    final drops = _inProcess;
    final outcome = await _service.dragOutToSystem(
      selfHwnd: _selfHwnd,
      withHwnd: true,
    );
    if (outcome == null) return outcome;
    final slot = drops.resolve(hwnd: outcome.hwnd, runnerSlot: outcome.slot);
    return (
      ran: outcome.ran,
      snapped: outcome.snapped,
      left: outcome.left,
      top: outcome.top,
      width: outcome.width,
      height: outcome.height,
      x: outcome.x,
      y: outcome.y,
      slot: slot,
      isSelf: outcome.isSelf || _isSourceSlot(drops, slot),
      isShellTray: outcome.isShellTray,
      inWorkArea: outcome.inWorkArea,
      atTaskbarEdge: outcome.atTaskbarEdge,
      hwnd: outcome.hwnd,
    );
  }

  bool _isSourceSlot(InProcessTabDrops drops, int? slot) =>
      slot != null && slot == drops.slotOf(_sourceWindow);
}

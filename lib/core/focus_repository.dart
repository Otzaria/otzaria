import 'dart:async';

import 'package:flutter/widgets.dart';

/// מייצג owner של הפוקוס שמסוגל לשחזר אותו לאחר אירועי חלון.
///
/// [restore]    — קריאת שחזור הפוקוס.
/// [canRestore] — האם ה-owner עדיין תקף ויכול לקבל פוקוס כרגע.
class FocusRestorer {
  final VoidCallback restore;
  final bool Function() canRestore;

  const FocusRestorer({required this.restore, required this.canRestore});
}

/// מנהל מרכזי של שחזור פוקוס לאחר אירועי חלון (maximize, fullscreen, resize).
///
/// ## מודל שתי שכבות
///
/// **שכבת מסך** ([setScreenRestorer]): נקבע כשמנווטים למסך חדש.
/// מוחלף כשמנווטים שוב — אחת אחד.
///
/// **שכבת דיאלוג** ([registerActiveRestorer] / [unregisterActiveRestorer]):
/// מוסיף dialog/overlay מעל המסך. כשה-dialog נסגר ומבוטל רישומו, החזרה
/// אוטומטית לבעלים של שכבת המסך (או ל-dialog הקודם, אם היו כמה).
///
/// ## בחירת owner פעיל
///
/// [_effectiveRestorer] עובר מהcstack מלמעלה למטה — dialog קודם מנצח,
/// ובהיעדר dialog תקף: בעלים של המסך.
class FocusRepository {
  static final FocusRepository _instance = FocusRepository._internal();
  factory FocusRepository() => _instance;
  FocusRepository._internal();

  final FocusNode librarySearchFocusNode = FocusNode();
  final FocusNode findRefSearchFocusNode = FocusNode();

  final TextEditingController librarySearchController = TextEditingController();
  final TextEditingController findRefSearchController = TextEditingController();

  FocusNode? _currentBookContentFocusNode;
  VoidCallback? _moreScreenFocusRequester;
  VoidCallback? _settingsFocusRequester;

  // שכבת מסך — owner יחיד, מוחלף בכל ניווט למסך
  FocusRestorer? _screenRestorer;

  // שכבת דיאלוג — stack; כל dialog מוסיף ומסיר את עצמו
  final List<FocusRestorer> _dialogRestorers = [];

  // מניעת קריאות scheduleRestore כפולות באותו frame
  bool _hasScheduledRestore = false;

  // debounce לשחזור בזמן resize רציף
  Timer? _resizeDebounceTimer;

  // ── Effective restorer ─────────────────────────────────────────────────────

  /// מחזיר את ה-owner הפעיל הנוכחי — dialog (top-to-bottom), ואז מסך.
  ///
  /// **לא** צולם ב-snapshot — תמיד מחשב מחדש, כך שסגירת dialog
  /// מחזירה אוטומטית לבעלים של המסך.
  FocusRestorer? get _effectiveRestorer {
    for (int i = _dialogRestorers.length - 1; i >= 0; i--) {
      if (_dialogRestorers[i].canRestore()) return _dialogRestorers[i];
    }
    final screen = _screenRestorer;
    if (screen != null && screen.canRestore()) return screen;
    return null;
  }

  // ── Screen-level registration ──────────────────────────────────────────────

  /// קובע את בעלים ברמת המסך. קרא בעת ניווט למסך חדש.
  ///
  /// - מחליף את בעלי המסך הקודם.
  /// - **אינו** נוגע ב-dialog stack.
  /// - מבטל debounce ממתין (ששייך לבעלים הישן).
  void setScreenRestorer({
    required VoidCallback restore,
    required bool Function() canRestore,
  }) {
    _screenRestorer = FocusRestorer(restore: restore, canRestore: canRestore);
    _resizeDebounceTimer?.cancel();
  }

  // ── Dialog/overlay registration ────────────────────────────────────────────

  /// מוסיף בעלים של dialog מעל בעלי המסך הנוכחי.
  ///
  /// מחזיר token — שמור ותעביר ל-[unregisterActiveRestorer] כשה-dialog נסגר.
  /// מבטל debounce ממתין (כדי שלא יחזיר פוקוס לבעלים הישן).
  FocusRestorer registerActiveRestorer({
    required VoidCallback restore,
    required bool Function() canRestore,
  }) {
    _resizeDebounceTimer?.cancel();
    final restorer = FocusRestorer(restore: restore, canRestore: canRestore);
    _dialogRestorers.add(restorer);
    return restorer;
  }

  /// מסיר בעלים של dialog (לפי זהות אובייקט).
  ///
  /// לאחר ההסרה, [_effectiveRestorer] חוזר אוטומטית לבעלי המסך
  /// (או ל-dialog הבא בstack, אם היו כמה).
  void unregisterActiveRestorer(FocusRestorer restorer) {
    _dialogRestorers.removeWhere((r) => identical(r, restorer));
  }

  // ── Screen focus requests ──────────────────────────────────────────────────

  void requestLibrarySearchFocus({bool selectAll = false}) {
    librarySearchFocusNode.requestFocus();
    if (selectAll) {
      librarySearchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: librarySearchController.text.length,
      );
    }
    setScreenRestorer(
      restore: () {
        if (librarySearchFocusNode.canRequestFocus) {
          librarySearchFocusNode.requestFocus();
        }
      },
      canRestore: () => librarySearchFocusNode.canRequestFocus,
    );
  }

  void requestFindRefSearchFocus({bool selectAll = false}) {
    findRefSearchFocusNode.requestFocus();
    if (selectAll) {
      findRefSearchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: findRefSearchController.text.length,
      );
    }
    setScreenRestorer(
      restore: () {
        if (findRefSearchFocusNode.canRequestFocus) {
          findRefSearchFocusNode.requestFocus();
        }
      },
      canRestore: () => findRefSearchFocusNode.canRequestFocus,
    );
  }

  /// רישום FocusNode של תוכן ספר (נקרא מ-TextBookViewerBloc)
  void registerBookContentFocusNode(FocusNode focusNode) {
    _currentBookContentFocusNode = focusNode;
  }

  /// ביטול רישום FocusNode של תוכן ספר
  void unregisterBookContentFocusNode(FocusNode focusNode) {
    if (_currentBookContentFocusNode == focusNode) {
      _currentBookContentFocusNode = null;
    }
  }

  void requestBookContentFocus() {
    final node = _currentBookContentFocusNode;
    if (node == null) return;
    node.requestFocus();
    setScreenRestorer(
      restore: () {
        final n = _currentBookContentFocusNode;
        if (n != null && n.canRequestFocus) n.requestFocus();
      },
      canRestore: () => _currentBookContentFocusNode?.canRequestFocus ?? false,
    );
  }

  void registerMoreScreenFocusRequester(VoidCallback requester) {
    _moreScreenFocusRequester = requester;
  }

  void unregisterMoreScreenFocusRequester(VoidCallback requester) {
    if (_moreScreenFocusRequester == requester) _moreScreenFocusRequester = null;
  }

  void requestMoreScreenFocus() {
    // setScreenRestorer מטופל בתוך requestActiveTabFocus ← _registerMoreRestorer
    _moreScreenFocusRequester?.call();
  }

  void registerSettingsFocusRequester(VoidCallback requester) {
    _settingsFocusRequester = requester;
  }

  void unregisterSettingsFocusRequester(VoidCallback requester) {
    if (_settingsFocusRequester == requester) _settingsFocusRequester = null;
  }

  void requestSettingsFocus() {
    // setScreenRestorer מטופל בתוך _requestSettingsFocus עצמה
    _settingsFocusRequester?.call();
  }

  // ── Restore scheduling ─────────────────────────────────────────────────────

  /// שחזור לאחר frame אחד — עבור אירועי חלון דיסקרטיים (maximize, fullscreen, restore).
  ///
  /// קריאות מרובות באותו frame מתאחדות לcallback אחד.
  /// השחזור מחשב את [_effectiveRestorer] **בזמן הריצה** (לא snapshot),
  /// כך שאם dialog נסגר לפני שה-callback ירה, הוא ישחזר לבעלי המסך.
  void scheduleRestore() {
    if (_hasScheduledRestore) return;
    if (_effectiveRestorer == null) return;
    _hasScheduledRestore = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hasScheduledRestore = false;
      final r = _effectiveRestorer;
      if (r != null && r.canRestore()) r.restore();
    });
  }

  /// שחזור עם debounce — עבור resize רציף.
  ///
  /// מבטל את הטיימר הקודם בכל קריאה וממתין 150ms ללא resize נוסף.
  /// גם כאן [_effectiveRestorer] מחושב **בזמן ריצת הטיימר**, לא בזמן הקריאה.
  void scheduleRestoreDebounced() {
    _resizeDebounceTimer?.cancel();
    if (_effectiveRestorer == null) return;
    _resizeDebounceTimer = Timer(const Duration(milliseconds: 150), () {
      final r = _effectiveRestorer;
      if (r != null && r.canRestore()) r.restore();
    });
  }

  void dispose() {
    _resizeDebounceTimer?.cancel();
    librarySearchFocusNode.dispose();
    findRefSearchFocusNode.dispose();
    librarySearchController.dispose();
    findRefSearchController.dispose();
  }

  /// מאפס את כל מצב ה-restorers לצורך בדיקות בלבד.
  ///
  /// אין לקרוא לזה מחוץ לקבצי test.
  // ignore: invalid_use_of_visible_for_testing_member
  void resetForTesting() {
    _screenRestorer = null;
    _dialogRestorers.clear();
    _hasScheduledRestore = false;
    _resizeDebounceTimer?.cancel();
    _resizeDebounceTimer = null;
  }

  /// מחזיר את תוצאת canRestore של ה-screen restorer הנוכחי — לצורך בדיקות בלבד.
  // ignore: invalid_use_of_visible_for_testing_member
  bool? screenCanRestoreForTesting() => _screenRestorer?.canRestore();

  /// מריץ שחזור פוקוס סינכרוני מיידי — לצורך בדיקות בלבד.
  ///
  /// מקביל לתוצאה של [scheduleRestore] אחרי frame אחד, ללא צורך ב-pump.
  // ignore: invalid_use_of_visible_for_testing_member
  void restoreNowForTesting() {
    final r = _effectiveRestorer;
    if (r != null && r.canRestore()) r.restore();
  }
}

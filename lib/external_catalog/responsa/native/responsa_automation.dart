import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:otzaria/external_catalog/responsa/native/responsa_discovery.dart';
import 'package:otzaria/external_catalog/responsa/responsa_failure.dart';
import 'package:otzaria/external_catalog/responsa/text/responsa_hebrew.dart';
import 'package:otzaria/external_catalog/responsa/text/responsa_names.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_profile.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_win32.dart';

/// תוצאת פתיחה מוצלחת.
class ResponsaOpenOutcome {
  /// כותרת חלון ה-MDI שנפתח, כפי שנקראה מהתוכנה.
  final String window;

  /// ההפניה שבה השתמשנו בפועל — עשויה להיות קצרה מזו שנשלחה.
  final String usedRef;

  final String selectedResult;
  final int resultCount;
  final bool isNew;
  final int releasedWindows;

  /// כל ההפניות שנוסו עד להצלחה, לפי הסדר. נדרש לאבחון: הפניה שנפתחת
  /// רק בחוליה השלישית מעידה על כשל בבניית הקטלוג, לא על תקלה בתוכנה.
  final List<String> triedRefs;

  const ResponsaOpenOutcome({
    required this.window,
    required this.usedRef,
    required this.selectedResult,
    required this.resultCount,
    required this.isNew,
    required this.releasedWindows,
    this.triedRefs = const [],
  });
}

/// תקציב זמן לפעולה שלמה.
class ResponsaDeadline {
  final Stopwatch _watch = Stopwatch()..start();
  final Duration budget;

  ResponsaDeadline(this.budget);

  Duration get remaining => budget - _watch.elapsed;
  bool get expired => remaining <= Duration.zero;
}

/// אוטומציה סינכרונית מול מופע חי של פרויקט השו"ת.
///
/// **חייבת לרוץ באיזולט רקע.** כל הקריאות חוסמות.
///
/// שלושת הכללים שנקנו במדידה:
///
/// 1. **מודאל "מידע" חוסם את כל הערוץ.** כל הפניה שתישלח בזמן שהוא פתוח
///    מחזירה 0 תוצאות — גם ספר שנפתח בהצלחה רגע קודם.
/// 2. **`WM_CLOSE` על חלון של האפליקציה מפיל אותה.** סגירת מודאל נעשית
///    בלחיצה על כפתור האישור בלבד; חלון MDI נסגר ב-`WM_MDIDESTROY`.
/// 3. **רשימת התוצאות אינה מתנקה מאליה.** בכשל ניתוח היא שומרת את
///    תוצאות ההפניה הקודמת, ולכן חובה ניקוי ואימות שהיא ריקה לפני כל
///    הפניה — אחרת הספירה משקרת.
class ResponsaAutomation {
  final int pid;
  final ResponsaVersionProfile profile;

  /// כותרות החלונות שאוצריא עצמה פתחה, מהוותיק לחדש. **רק אלה
  /// משוחררים** — חלון שהמשתמש פתח אינו שלנו לסגור.
  ///
  /// נמסרת מבחוץ ונקראת בחזרה ב-[openedWindows], כי כל פתיחה רצה
  /// באיזולט משלה: רשימה שנולדת עם המחלקה מתה איתה, והיא הייתה ריקה
  /// בכל פתיחה.
  final List<String> _openedWindows;

  /// החלונות שאוצריא פתחה, כפי שהם אחרי הפעולה. הבקר שומר אותם
  /// ומחזיר אותם לפתיחה הבאה.
  List<String> get openedWindows => List.unmodifiable(_openedWindows);

  ResponsaAutomation({
    required this.pid,
    required this.profile,
    List<String> openedWindows = const [],
  }) : _openedWindows = [...openedWindows];

  static const Duration _poll = Duration(milliseconds: 250);

  /// כל כמה זמן לשלוח שוב את פקודת פתיחת דיאלוג העיון.
  static const Duration _commandRepeat = Duration(seconds: 3);

  /// תקציב לרכישת הדיאלוג, נפרד מזה של הפעולה. הדיאלוג נפתח ב-1–2
  /// שניות כשהכול תקין; תקציב נדיב אינו מציל מצב תקוע, רק מכפיל את זמן
  /// הכשל בכל חוליה.
  static const Duration dialogBudget = Duration(seconds: 12);

  /// תקציב לניקוי רשימת התוצאות, נפרד מזה של הפעולה. הניקוי מיידי
  /// כשהכול תקין; תקציב הפעולה כולה כאן פירושו שחוליה אחת תוקעת את
  /// כל הסולם.
  static const Duration clearBudget = Duration(seconds: 10);

  /// תקציב להמתנה לחלון הספר אחרי לחיצה מוצלחת על "הצג טקסט".
  static const Duration windowBudget = Duration(seconds: 45);

  /// המתנה אחרי פתיחת ספר — התוכנה עסוקה בציור החלון החדש, וקריאה
  /// מיידית אחריה נבלעת.
  static const Duration _afterOpenSettle = Duration(seconds: 1);

  bool Function() cancelled = _neverCancelled;
  static bool _neverCancelled() => false;

  void _wait(Duration duration, ResponsaDeadline deadline) {
    final end = Stopwatch()..start();
    while (end.elapsed < duration) {
      _checkpoint(deadline);
      // השעון נקרא שוב **אחרי** תנאי הלולאה, ולכן הוא יכול כבר לחרוג.
      // `sleep` עם משך שלילי זורק, והחריגה עלתה מהאיזולט ככשל פתיחה
      // בלתי מוסבר — נצפה פעם אחת ב-40 פתיחות.
      final left = duration - end.elapsed;
      if (left <= Duration.zero) break;
      sleepFor(left < _poll ? left : _poll);
    }
    _checkpoint(deadline);
  }

  void _checkpoint(ResponsaDeadline deadline) {
    if (cancelled()) {
      throw const ResponsaAutomationException(
        ResponsaFailure.cancelled,
        'הפעולה בוטלה',
      );
    }
    if (deadline.expired) {
      throw const ResponsaAutomationException(
        ResponsaFailure.timeout,
        'חריגה מתקציב הזמן של הפעולה',
      );
    }
  }

  /// שינה חוסמת. ניתנת להחלפה בבדיקות כדי שלא ימתינו באמת.
  ///
  /// `sleep` של `dart:io` חוסם את השרשור בלי לשרוף מעבד — מותר כאן
  /// בדיוק מפני שהמחלקה רצה באיזולט רקע ולא על ה-UI isolate.
  static void Function(Duration) sleepFor = sleep;

  int get mainWindow {
    final hwnd = ResponsaDiscovery.findMainWindow(pid, profile);
    if (hwnd == null) {
      throw const ResponsaAutomationException(
        ResponsaFailure.responsaNotRunning,
        'לא נמצא חלון ראשי של פרויקט השו"ת',
      );
    }
    return hwnd;
  }

  bool get isRunning => ResponsaDiscovery.findMainWindow(pid, profile) != null;

  // -------------------------------------------------------- מודאל "מידע"

  /// סוגר כל מודאל "מידע" פתוח בלחיצה על כפתור האישור.
  ///
  /// הלולאה חסומה כדי שמודאל שאינו נסגר לא יהפוך לולאה אינסופית.
  int dismissInfoModals({int limit = 5}) {
    var closed = 0;
    for (var attempt = 0; attempt < limit; attempt++) {
      final modals = ResponsaDiscovery.discoverAll(
        pid,
        profile.infoModalHints,
      );
      if (modals.isEmpty) break;
      for (final modal in modals) {
        final button = modal.handle('ok_button');
        if (button == null) continue;
        ResponsaWin32.click(button);
        closed++;
      }
      sleepFor(const Duration(milliseconds: 400));
    }
    return closed;
  }

  // ------------------------------------------------------- דיאלוג העיון

  DiscoveredDialog? findCitationDialog() =>
      ResponsaDiscovery.discoverDialog(pid, profile.citationDialogHints);

  /// מחזיר את עמוד "כתיבת מקורות", ופותח את דיאלוג העיון אם צריך.
  ///
  /// פקודת הפתיחה נשלחת **שוב ושוב**, לא פעם אחת: אחרי פתיחת ספר התוכנה
  /// סוגרת את הדיאלוג ועסוקה בציור החלון החדש, ופקודה בודדת באותו רגע
  /// נבלעת. במדידה זה הוריד את שיעור ההצלחה לאפס מהפתיחה ה-14 ואילך.
  DiscoveredDialog ensureCitationDialog(ResponsaDeadline deadline) {
    final existing = findCitationDialog();
    if (existing != null) return existing;

    final main = mainWindow;
    final own = ResponsaDeadline(
      deadline.remaining < dialogBudget ? deadline.remaining : dialogBudget,
    );
    Stopwatch? sinceCommand;
    while (!own.expired && !deadline.expired) {
      if (sinceCommand == null || sinceCommand.elapsed >= _commandRepeat) {
        ResponsaWin32.postCommand(main, profile.browseCommand);
        sinceCommand = Stopwatch()..start();
      }
      _wait(const Duration(milliseconds: 600), deadline);
      final found = findCitationDialog() ?? _switchToCitationTab(deadline);
      if (found != null) return found;
    }
    throw const ResponsaAutomationException(
      ResponsaFailure.citationDialogNotFound,
      'דיאלוג העיון לא נפתח בזמן שהוקצב',
    );
  }

  /// מעביר את דיאלוג העיון לעמוד "כתיבת מקורות". ה-TabControl נמצא לפי
  /// מחלקתו, לא לפי מזהה.
  DiscoveredDialog? _switchToCitationTab(ResponsaDeadline deadline) {
    for (final dialog in ResponsaDiscovery.candidateDialogs(
      pid,
      profile.citationDialogHints,
    )) {
      for (final child in ResponsaWin32.children(dialog)) {
        if (ResponsaWin32.className(child) == 'SysTabControl32') {
          ResponsaWin32.setTabFocus(child, profile.citationTabIndex);
          _wait(const Duration(milliseconds: 800), deadline);
        }
      }
    }
    return findCitationDialog();
  }

  // ------------------------------------------------- ניקוי רשימת התוצאות

  void clearResults(DiscoveredDialog dialog, ResponsaDeadline deadline) {
    final results = dialog.handle('results_list');
    if (results == null) {
      throw const ResponsaAutomationException(
        ResponsaFailure.citationDialogNotFound,
        'לא נמצאה רשימת התוצאות',
      );
    }

    final clearButton = dialog.handle('clear_button');
    if (clearButton != null) ResponsaWin32.click(clearButton);

    // תקציב משלו, כמו לדיאלוג. `clear_button` אינו פקד חובה בפרופיל,
    // וכשהוא אינו נמצא הלולאה הזו הייתה שורפת את שלוש הדקות של הפעולה
    // כולה על החוליה הראשונה — ואז אף חוליה אחרת לא הייתה נוסה.
    final own = ResponsaDeadline(
      deadline.remaining < clearBudget ? deadline.remaining : clearBudget,
    );
    while (!own.expired) {
      // `-1` = הרשימה לא ענתה. זה **אינו** "ריקה": המשך מכאן היה מייצר
      // בדיוק את הספירה השקרית שהניקוי נועד למנוע.
      if (ResponsaWin32.listBoxCount(results) == 0) return;
      _wait(_poll, deadline);
    }
    throw const ResponsaAutomationException(
      ResponsaFailure.resultsNotCleared,
      'רשימת התוצאות לא התנקתה — הספירה שאחריה אינה אמינה',
    );
  }

  // ------------------------------------------------------ ניתוח הפניה

  /// מזין הפניה למנתח ומחזיר את כל התוצאות.
  ///
  /// רשימה ריקה = ההפניה לא נותחה. זה מצב חוקי, לא חריג.
  ({DiscoveredDialog dialog, List<String> results}) parseReference(
    String reference,
    ResponsaDeadline deadline, {
    int attempts = 3,
    Duration settle = const Duration(milliseconds: 1200),
  }) {
    dismissInfoModals();
    final dialog = ensureCitationDialog(deadline);
    clearResults(dialog, deadline);

    final edit = dialog.handle('reference_edit');
    final search = dialog.handle('search_button');
    final results = dialog.handle('results_list');
    if (edit == null || search == null || results == null) {
      throw const ResponsaAutomationException(
        ResponsaFailure.citationDialogNotFound,
        'עמוד כתיבת המקורות אינו שלם',
      );
    }

    ResponsaWin32.setWindowText(edit, reference);
    var count = 0;
    var waitFor = settle;
    for (var attempt = 0; attempt < attempts; attempt++) {
      ResponsaWin32.click(search);
      _wait(waitFor, deadline);
      // המודאל "לא נמצאה כל תוצאה!" הוא תשובה **סופית** של המנתח, לא
      // כשל זמני. ניסיונות נוספים אחריו רק מבזבזים עשרות שניות.
      if (dismissInfoModals() > 0) {
        return (dialog: dialog, results: const <String>[]);
      }
      count = ResponsaWin32.listBoxCount(results);
      if (count > 0) break;
      waitFor += const Duration(seconds: 1);
    }

    if (count <= 0) return (dialog: dialog, results: const <String>[]);
    return (dialog: dialog, results: ResponsaWin32.listBoxItems(results));
  }

  // ------------------------------------------------- שחרור חלונות MDI

  /// משחרר חלונות כשהמצבור מתקרב לתקרה.
  ///
  /// נמדד: בכ-22 חלונות התוכנה **מפסיקה ליצור חלונות חדשים בשקט** —
  /// הלחיצה מתקבלת, אף חלון לא נוצר, וכל פתיחה פוקעת. סגירת 21 חלונות
  /// ב-`WM_MDIDESTROY` החזירה את המופע לתפקוד מלא בלי להפיל אותו.
  ///
  /// משחרר חלונות כשהמצבור מתקרב לתקרה.
  ///
  /// **שני ספים, ושניהם נמדדו.**
  ///
  /// עד [ResponsaVersionProfile.mdiHardLimit] נסגרים **רק חלונות
  /// שאוצריא פתחה**. חלון שהמשתמש פתח אינו שלנו לסגור. הייתה כאן
  /// נסיגה ל"ותיקים אחרים כשאין שלנו", והיא הייתה **מסלול ברירת המחדל
  /// בפועל**: רשימת החלונות שלנו ישבה באוטומציה, הבקר יוצר אוטומציה
  /// חדשה באיזולט חדש בכל פתיחה, ולכן היא הייתה ריקה תמיד — וכל פתיחה
  /// שלוש-עשרה סגרה שמונה מחלונות המשתמש.
  ///
  /// מעל התקרה הקשה המופע **אינו שמיש כלל**: התוכנה מסרבת לפתוח חלון
  /// חדש, גם למשתמש עצמו. נמדד שמופע טרי עולה עם 22 חלונות משחזור
  /// הסשן — כלומר רווי מהרגע הראשון ובלי אף חלון "שלנו". שם, ורק שם,
  /// נסגרים גם חלונות אחרים, במספר המזערי שמחזיר את המופע לתפקוד,
  /// ו**לעולם לא החלון הפעיל** — זה שהמשתמש מסתכל בו.
  ///
  /// כותרת ריקה אינה נסגרת לעולם: `windowText` מחזיר מחרוזת ריקה גם
  /// כשהחלון לא ענה בזמן, ו-`''` ברשימת היעד היה סוגר **כל** חלון
  /// שאינו עונה — סגירה בלתי חסומה, הרבה מעבר לעודף.
  int releaseMdiWindows(int main) {
    final titles = ResponsaWin32.mdiTitles(main);
    if (titles.length < profile.mdiSoftLimit) return 0;

    final present = titles.where((title) => title.isNotEmpty).toSet();
    final wanted = <String>{
      for (final title in _openedWindows)
        if (present.contains(title)) title,
    };

    if (titles.length >= profile.mdiHardLimit) {
      final active = ResponsaWin32.mdiActiveTitle(main);
      final needed = titles.length - profile.mdiSoftLimit + 1;
      for (final title in present) {
        if (wanted.length >= needed) break;
        if (title == active || wanted.contains(title)) continue;
        wanted.add(title);
      }
      debugPrint(
        'ResponsaAutomation: ${titles.length} חלונות — מעל התקרה הקשה; '
        'נסגרים ${wanted.length}',
      );
    }

    final surplus = titles.length - profile.mdiKeep;
    final toClose = wanted.take(surplus < 0 ? 0 : surplus).toSet();
    if (toClose.isEmpty) return 0;

    final client = ResponsaWin32.mdiClient(main);
    if (client == null) return 0;
    var closed = 0;
    for (final child in ResponsaWin32.directChildren(client)) {
      if (closed >= toClose.length) break;
      final title = ResponsaWin32.windowText(child);
      if (title.isEmpty || !toClose.contains(title)) continue;
      ResponsaWin32.destroyMdiChild(main, child);
      closed++;
      sleepFor(const Duration(milliseconds: 200));
    }
    _openedWindows.removeWhere(toClose.contains);
    return closed;
  }

  // -------------------------------------------------------- פתיחת ספר

  /// פותח ספר לפי סולם הפניות, ומאמת שהחלון שנפתח הוא הספר הנכון.
  ///
  /// [references] מגיע מהקטלוג לפי סדר יורד של סיכוי, והראשונה שהמנתח
  /// מזהה היא זו שנפתחת.
  ///
  /// **אין כאן השמטת מילים מההתחלה.** היא הייתה כאן, והמדידה הראתה
  /// שהיא אינה מוסיפה אף פתיחה מוצלחת: כל ההצלחות הגיעו מחוליה של
  /// הקטלוג. מה שהיא כן עשתה הוא לייצר שברי שם גנריים (`פסחים`,
  /// `פרשת קדושים`) שפותחים ספר אחר — עד 33 שניות מבוזבזות לכל כשל.
  ResponsaOpenOutcome openBook(
    List<String> references,
    ResponsaDeadline deadline, {
    String? expectedTitle,
    int? resultIndex,
  }) {
    final ladder = [
      for (final reference in references)
        if (reference.trim().isNotEmpty) reference.trim(),
    ];
    if (ladder.isEmpty) {
      throw const ResponsaAutomationException(
        ResponsaFailure.referenceNotParsed,
        'לא נמסרה הפניה לפתיחה',
      );
    }
    final openRef = ladder.first;

    final main = mainWindow;
    final released = releaseMdiWindows(main);
    final before = ResponsaWin32.mdiTitles(main).toSet();
    final atLimit = before.length >= profile.mdiSoftLimit;

    final tried = <String>[];
    var usedRef = openRef;
    DiscoveredDialog? dialog;
    var results = const <String>[];
    // חוליה שהמנתח זיהה אך תוצאותיה אינן הספר המבוקש. היא נשמרת כנסיגה
    // ואינה עוצרת את הסולם: `לעזי רש"י תלמוד מנחות` אינו מזוהה, החוליה
    // שאחריה — `תלמוד מנחות` — מזוהה היטב ופותחת את הגמרא, והחוליה
    // שאחריה, `לעזי רש"י מנחות`, היא הנכונה. עצירה בראשונה שנותחה
    // הפילה 37 ספרים על ספר שנפתח ונפסל.
    //
    // **רק ההפניה נשמרת, לא התוצאות.** כל חוליה שאחריה מריצה
    // `clearResults`, שמנקה את רשימת התוצאות בפקד עצמו; שורות שנשמרו
    // בזיכרון מתארות רשימה שכבר אינה קיימת, ובחירה לפי אינדקס בתוכן
    // בוחרת שורה אחרת לגמרי — או שום שורה, ברשימה שהתרוקנה.
    String? fallbackRef;
    for (final candidate in ladder) {
      if (tried.contains(candidate)) continue;
      tried.add(candidate);
      // ניסיון חוזר רק לחוליה הראשונה: הניסיונות החוזרים קיימים בשביל
      // טעינה קרה, ואחריה הדיאלוג כבר חם.
      //
      // שניים ולא שלושה: לחיצת החיפוש היא שליחה סינכרונית, והתוכנה
      // מבצעת את החיפוש לפני שהיא חוזרת. כל ניסיון נוסף על הפניה
      // שהמנתח אינו מכיר עולה כ-5 שניות ומעולם לא שינה את התוצאה.
      final attempt = parseReference(
        candidate,
        deadline,
        attempts: tried.length == 1 ? 2 : 1,
      );
      if (attempt.results.isEmpty) continue;
      if (hasPlausibleResult(attempt.results, candidate, expectedTitle)) {
        usedRef = candidate;
        dialog = attempt.dialog;
        results = attempt.results;
        break;
      }
      fallbackRef ??= candidate;
    }
    if (dialog == null && fallbackRef != null) {
      // אף חוליה לא הניבה תוצאה משכנעת. מריצים **מחדש** את הטובה
      // שבהן ונותנים לאימות הכותרת להכריע — הוא מדויק יותר מהשוואת
      // השורות. הרצה מחדש ולא שחזור מהזיכרון: ראו ההערה למעלה.
      final again = parseReference(fallbackRef, deadline);
      if (again.results.isNotEmpty) {
        usedRef = fallbackRef;
        dialog = again.dialog;
        results = again.results;
      }
    }
    if (dialog == null || results.isEmpty) {
      throw ResponsaAutomationException(
        ResponsaFailure.referenceNotParsed,
        'פרויקט השו"ת לא זיהה אף אחת מההפניות לספר',
        {'ref': openRef, 'tried': tried},
      );
    }

    final index = resultIndex ?? bestResult(results, usedRef, expectedTitle);
    if (index >= results.length) {
      throw ResponsaAutomationException(
        ResponsaFailure.referenceNotParsed,
        'התוצאה $index אינה קיימת',
        {'ref': openRef, 'resultCount': results.length},
      );
    }

    final chosen = results[index];
    final listBox = dialog.handle('results_list');
    final showButton = dialog.handle('show_text_button');
    if (listBox == null || showButton == null) {
      throw const ResponsaAutomationException(
        ResponsaFailure.citationDialogNotFound,
        'חסר פקד בעמוד כתיבת המקורות',
      );
    }

    ResponsaWin32.listBoxSelect(dialog.container, listBox, index);
    _wait(const Duration(milliseconds: 400), deadline);
    // הלחיצה היא שליחה סינכרונית; `false` פירושו שהתוכנה לא ענתה בתוך
    // 15 שניות, כלומר הבקשה מעולם לא התקבלה. המתנה לחלון אחריה הייתה
    // שורפת את יתרת שלוש הדקות ומדווחת "פג הזמן" — תיאור שגוי של מצב
    // שבו התוכנה תקועה.
    if (!ResponsaWin32.click(showButton)) {
      throw ResponsaAutomationException(
        ResponsaFailure.timeout,
        'פרויקט השו"ת לא הגיב ללחיצה על "הצג טקסט"',
        {'ref': openRef, 'usedRef': usedRef},
      );
    }

    final String title;
    try {
      title = _awaitBookWindow(main, before, chosen, expectedTitle, deadline);
    } on ResponsaAutomationException catch (error) {
      // כשהמצבור בתקרה, "אין חלון חדש" אינו איטיות אלא סירוב שקט של
      // התוכנה. מסר מדויק עדיף על "פג הזמן".
      if (error.failure == ResponsaFailure.timeout && atLimit) {
        throw ResponsaAutomationException(
          ResponsaFailure.mdiWindowLimitReached,
          'פרויקט השו"ת אינו פותח חלונות נוספים — יש לסגור חלונות בתוכנה',
          {'windows': before.length},
        );
      }
      rethrow;
    }

    // **החלון נרשם כשלנו ברגע שהוא נפתח**, לפני האימות ולפני כל מה
    // שיכול לזרוק. חלון שנפתח ונפסל הוא שלנו בדיוק כמו חלון שנפתח
    // והתקבל — ומי שאינו רושם אותו אינו סוגר אותו לעולם. נמדד: מופעים
    // שהצטברו עד 110MB, וכל פתיחה מהן ואילך פקעה.
    if (!before.contains(title) && !_openedWindows.contains(title)) {
      _openedWindows.add(title);
    }

    dismissInfoModals();
    sleepFor(_afterOpenSettle);

    // שתי בדיקות בלתי-תלויות: שהחלון הוא **השורה שבחרנו**, ושהוא הספר
    // **שביקשנו**. אחת בלבד אינה מספיקה.
    //
    final failed = verifyOpened(
      window: title,
      selectedResult: chosen,
      usedRef: usedRef,
      expectedTitle: expectedTitle,
    );
    if (failed.isNotEmpty) {
      throw ResponsaAutomationException(
        ResponsaFailure.openedWrongBook,
        'נפתח "$title" — אינו תואם ל${failed.join(', ')}',
        {'ref': openRef, 'usedRef': usedRef, 'actual': title},
      );
    }

    // הספר נפתח — עכשיו שיהיה גם גלוי. מופע ממוזער או מוסתר מאחורי
    // אוצריא נראה למשתמש בדיוק כמו פתיחה שנכשלה.
    ResponsaWin32.bringToFront(main);

    final isNew = !before.contains(title);
    return ResponsaOpenOutcome(
      window: title,
      usedRef: usedRef,
      selectedResult: chosen,
      resultCount: results.length,
      isNew: isNew,
      releasedWindows: released,
      triedRefs: tried,
    );
  }

  /// האם ברשימת התוצאות יש שורה שיכולה להיות הספר המבוקש.
  ///
  /// נבדק **לפני** הפתיחה, ולכן הוא חינם: חוליה שהמנתח זיהה אך שכל
  /// תוצאותיה שייכות לספר אחר נדחית בלי לפתוח חלון ובלי לשלם את
  /// 17 השניות של כישלון אימות.
  ///
  /// הבדיקה רכה בכוונה — [ResponsaHebrew.coversTitle] ולא השוואה
  /// מלאה — כי רשימת התוצאות מנוסחת בשפת התוכנה (`תלמוד בבלי מסכת
  /// מנחות`) ואילו הכותרת המצופה היא של הקטלוג. תפקידה לפסול חוליה
  /// שאינה קשורה, לא לאמת את הפתיחה; האימות נעשה על כותרת החלון.
  static bool hasPlausibleResult(
    List<String> results,
    String reference,
    String? expectedTitle,
  ) {
    final wanted = expectedTitle == null
        ? reference
        : ResponsaNames.withoutQualifier(expectedTitle);
    if (wanted.trim().isEmpty) return true;
    return results.any((result) => ResponsaHebrew.coversTitle(wanted, result));
  }

  /// שמות הבדיקות שכותרת החלון שנפתח **לא** עברה. ריק = הספר הנכון.
  ///
  /// שלוש בדיקות בלתי-תלויות, וכל אחת מהן נחוצה:
  ///
  /// * **`selectedResult`** — שהחלון הוא השורה שלחצנו עליה. השוואה בין
  ///   שתי מחרוזות של התוכנה עצמה, ולכן היא המחמירה שבשלוש.
  /// * **`selectedEdition`** — שאותן שתי מחרוזות אינן נושאות מהדורות
  ///   סותרות. זהו המקום **היחיד** שבו מהדורה נבדקת: שאר ההשוואות
  ///   מתעלמות מהסוגריים בכוונה, כי הן מטא-דאטה של הקטלוג. בלעדיה
  ///   `שמות רבה (שנאן)` פותח את `שמות רבה (וילנא)` ומדווח הצלחה.
  /// * **`requestedRef`** — שהחלון מכסה את ההפניה שבה השתמשנו. רכה, כי
  ///   ההפניה נבנתה מהעץ ויכולה להכיל צמתי מבנה שהתוכנה משמיטה:
  ///   `ילקוט יוסף ... פסקי הלכות סימנים קנב-קנג` נפתח ככותרת
  ///   `ילקוט יוסף ... סימנים קנב-קנג` — הספר הנכון בדיוק.
  /// * **`expectedTitle`** — שהחלון מכסה את שם הספר בקטלוג. הרכה
  ///   שבכולן: זו מחרוזת תצוגה של אוצריא ולא של התוכנה, והיא יכולה גם
  ///   להוסיף הקשר שהתוכנה משמיטה (`חידושים על הגמרא`) וגם להשמיט
  ///   מיקום שהתוכנה מוסיפה (`מסכת אבות הקדמה`). ההסתייגות שבסוגריים
  ///   מוסרת ממנה: `היכלות (עמ' 108-126)` נפתח ככותרת
  ///   `אוצר מדרשים (אייזנשטיין) היכלות`, והשוואה מילולית פסלה פתיחה
  ///   תקינה לחלוטין.
  ///
  /// נפרדת מהפתיחה כדי שתהיה ניתנת לבדיקה: כאן יושבת ההכרעה אם ספר
  /// נפתח או לא, וכל הרפיה בה היא ספר שגוי שמדווח כהצלחה.
  static List<String> verifyOpened({
    required String window,
    required String selectedResult,
    required String usedRef,
    String? expectedTitle,
  }) {
    final failed = <String>[
      if (ResponsaHebrew.matchLevel(selectedResult, window) ==
          ResponsaMatchLevel.none)
        'selectedResult',
      if (ResponsaHebrew.editionsConflict(selectedResult, window))
        'selectedEdition',
      if (!ResponsaHebrew.coversTitle(usedRef, window)) 'requestedRef',
    ];
    if (expectedTitle != null) {
      final expected = ResponsaNames.withoutQualifier(expectedTitle);
      if (!ResponsaHebrew.coversTitle(expected, window)) {
        failed.add('expectedTitle');
      }
    }
    return failed;
  }

  /// בוחר את התוצאה שמתאימה ביותר ל**ספר שביקשנו**.
  ///
  /// `result[0]` אינו אמין: שם גנרי מחזיר מאות תוצאות שהראשונה בהן ספר
  /// אחר לגמרי. בשוויון נשארת המוקדמת — התנהגות ברירת המחדל.
  ///
  /// **הכותרת המצופה קודמת להפניה, ולא להפך.** ההפניה היא רק השאילתה
  /// שייצרה את הרשימה; הספר שהמשתמש ביקש הוא הכותרת. כשהחוליה שנותחה
  /// היא חוליית נסיגה, ההפניה מתארת את השאילתה ולא את הספר — ודירוג
  /// לפיה בוחר את השורה הלא נכונה מתוך רשימה שיש בה את הנכונה.
  ///
  /// נמדד על שלוש משפחות: `בית הבחירה למאירי על הש"ס ברכות` נפתח
  /// כ-`שרידי אש על הש"ס ברכות` (14 ספרים), `רי"ד (פסקים) בבא קמא`
  /// נפתח כ-`פסקי רי"ד מסכת ברכות`, ו-`רמב"ם מקוואות` נפתח כשורה שאינה
  /// זו שהחלון הציג. בכל שלושתן החוליה הייתה `על הש"ס ברכות`, `רי"ד`
  /// או `רמב"ם` — שאילתה רחבה שהרשימה שלה מכילה את הספר הנכון.
  static int bestResult(
    List<String> results,
    String openRef,
    String? expectedTitle,
  ) {
    final expected = expectedTitle == null
        ? null
        : ResponsaNames.withoutQualifier(expectedTitle);
    var bestIndex = 0;
    var bestScore = (-1, -1, -1, -1);
    for (var index = 0; index < results.length; index++) {
      // שורה שהמהדורה שלה סותרת את המבוקשת יורדת לתחתית הדירוג.
      // **כאן** נשמרת המהדורה, ולא באימות: שאר ההשוואות מסירות את
      // הסוגריים בכוונה, ולכן `שמות רבה (שנאן)` ו-`שמות רבה (וילנא)`
      // קיבלו ציון זהה, השוויון השאיר את המוקדמת, ומי שנפתח היה מי
      // שהמנתח החזיר ראשון. פסילה באימות אינה מספיקה — היא מונעת ספר
      // שגוי אבל אינה פותחת את הנכון.
      final editionRank =
          expectedTitle != null &&
              ResponsaHebrew.editionsConflict(expectedTitle, results[index])
          ? 0
          : 1;
      // כמה אסימונים מהכותרת המצופה מופיעים בשורה. דירוג **מדורג** ולא
      // כן/לא: `רי"ד (פסקים) בבא קמא משניות` אינו מוכל באף שורה —
      // `משניות` אינו מופיע באף אחת — ושתי הרמות הבינאריות מחזירות
      // שוויון בין `פסקי רי"ד מסכת ברכות` ל-`פסקי רי"ד מסכת בבא קמא`.
      // ספירה מבדילה ביניהן.
      final score = (
        editionRank,
        expected == null
            ? 0
            : ResponsaHebrew.sharedTokenCount(expected, results[index]),
        expected == null
            ? 0
            : ResponsaHebrew.matchLevel(expected, results[index]).rank,
        ResponsaHebrew.matchLevel(openRef, results[index]).rank,
      );
      if (_outranks(score, bestScore)) {
        bestIndex = index;
        bestScore = score;
      }
    }
    return bestIndex;
  }

  static bool _outranks((int, int, int, int) a, (int, int, int, int) b) {
    if (a.$1 != b.$1) return a.$1 > b.$1;
    if (a.$2 != b.$2) return a.$2 > b.$2;
    if (a.$3 != b.$3) return a.$3 > b.$3;
    return a.$4 > b.$4;
  }

  /// ממתין לחלון MDI מתאים.
  ///
  /// חלון **חדש** אינו התנאי היחיד: שחזור-סשן פותח חלונות בעלייה, ולכן
  /// ספר שכבר פתוח לא ייצור חלון נוסף.
  String _awaitBookWindow(
    int main,
    Set<String> before,
    String chosen,
    String? expectedTitle,
    ResponsaDeadline deadline,
  ) {
    final targets = [?expectedTitle, chosen];
    // תקציב משלו. פתיחה מוצלחת יוצרת חלון בשניות בודדות — חציון 2.8
    // שניות מקצה לקצה — ומופע שאינו יוצר חלון תוך 45 שניות אינו איטי
    // אלא תקוע. בלי זה כל כישלון כזה שרף את שלוש הדקות של הפעולה
    // כולה: נמדד בסריקה מלאה שמופע אחד שנתקע ייצר 65 כשלים של שלוש
    // דקות, והוריד את הקצב פי שלושה.
    final own = ResponsaDeadline(
      deadline.remaining < windowBudget ? deadline.remaining : windowBudget,
    );
    while (!own.expired) {
      _checkpoint(deadline);
      final titles = ResponsaWin32.mdiTitles(main);
      final fresh = [
        for (final title in titles)
          if (title.isNotEmpty && !before.contains(title)) title,
      ];
      // חלון חדש **שתואם למה שביקשנו** — המצב הרגיל.
      for (final title in fresh) {
        if (targets.any((t) => ResponsaHebrew.titlesMatch(t, title))) {
          return title;
        }
      }
      // חלון קיים שתואם: שחזור-הסשן פותח חלונות בעלייה, ולכן ספר
      // שכבר פתוח לא ייצור חלון נוסף.
      for (final title in titles) {
        if (title.isNotEmpty &&
            targets.any((t) => ResponsaHebrew.titlesMatch(t, title))) {
          return title;
        }
      }
      // חלון חדש יחיד שאינו תואם — מתקבל. התוכנה מנסחת את הכותרת
      // אחרת לפעמים, והאימות שאחרי זה הוא שיכריע.
      //
      // **אבל לא כשיש כמה.** שחזור-הסשן ממשיך להוסיף חלונות דקות
      // אחרי שהמופע עלה, וכל אחד מהם נראה "חדש". בחירה שרירותית
      // מביניהם ייצרה 60 דיווחי "ספר שגוי" שכולם היו חלון של ספר
      // אחר לגמרי — `משנה ביכורים` "נפתח" כ-`משנה מסכת בבא קמא`.
      if (fresh.length == 1) return fresh.single;
      sleepFor(_poll);
    }
    throw const ResponsaAutomationException(
      ResponsaFailure.timeout,
      'לא נפתח חלון ספר בזמן שהוקצב',
    );
  }

  // ------------------------------------------------------- ניווט לסימן

  /// מנווט את חלון ה-MDI הפעיל לסימן מבוקש.
  ///
  /// כותרת החלון היא האורקל: הסימן הנוכחי נקרא ממנה, ההפרש מחושב
  /// ומצועד. פקודת "ראש סימן" מעבירה למצב שבו כל צעד מקדם סימן שלם.
  String? gotoSiman(
    String bookTitle,
    int siman,
    ResponsaDeadline deadline, {
    int rounds = 3,
  }) {
    final main = mainWindow;
    // גימטריה מוגדרת ל-1..999 בלבד וזורקת מחוץ לתחום. החריגה הזו אינה
    // `ResponsaAutomationException`, ולכן היא הייתה מגיעה לבקר כ"כשל
    // בלתי צפוי" — ומדווחת ככשל פתיחה בזמן שהספר כבר פתוח על המסך.
    final String targetSuffix;
    try {
      targetSuffix = 'סימן ${ResponsaHebrew.intToNumeral(siman)}';
    } catch (error) {
      return ResponsaWin32.mdiActiveTitle(main);
    }
    for (var round = 0; round < rounds; round++) {
      ResponsaWin32.postCommand(main, profile.simanHeadCommand);
      _wait(const Duration(milliseconds: 600), deadline);
      final title = ResponsaWin32.mdiActiveTitle(main);
      final current = simanOf(title);
      if (current == null) return title;
      final delta = siman - current;
      if (delta == 0) return ResponsaWin32.mdiActiveTitle(main);
      final command = delta > 0
          ? profile.simanNextCommand
          : profile.simanPrevCommand;
      for (var step = 0; step < delta.abs(); step++) {
        ResponsaWin32.postCommand(main, command);
        _wait(const Duration(milliseconds: 250), deadline);
      }
      final after = ResponsaWin32.mdiActiveTitle(main);
      if (after != null && after.endsWith(targetSuffix)) return after;
    }
    return ResponsaWin32.mdiActiveTitle(main);
  }

  static int? simanOf(String? title) {
    if (title == null || !title.contains('סימן')) return null;
    final rest = title.split('סימן').last.trim();
    if (rest.isEmpty) return null;
    return ResponsaHebrew.numeralToInt(rest.split(' ').first);
  }
}

import 'dart:io';

import 'package:otzaria/external_catalog/responsa/native/responsa_discovery.dart';
import 'package:otzaria/external_catalog/responsa/text/responsa_hebrew.dart';
import 'package:otzaria/external_catalog/responsa/text/responsa_names.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_profile.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_win32.dart';

/// קוד שגיאה יציב של פעולת אוטומציה. אוצריא מסתמכת על הקוד, לא על הטקסט.
enum ResponsaFailure {
  responsaNotRunning,
  citationDialogNotFound,
  resultsNotCleared,
  referenceNotParsed,
  openedWrongBook,
  mdiWindowLimitReached,
  timeout,
  cancelled,
}

class ResponsaAutomationException implements Exception {
  final ResponsaFailure failure;
  final String message;
  final Map<String, Object?> details;

  const ResponsaAutomationException(
    this.failure,
    this.message, [
    this.details = const {},
  ]);

  @override
  String toString() => '${failure.name}: $message';
}

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

  /// כותרות החלונות שאוצריא עצמה פתחה, מהוותיק לחדש. רק אלה משוחררים
  /// כברירת מחדל — חלון שהמשתמש פתח אינו שלנו לסגור.
  final List<String> _openedWindows = [];

  ResponsaAutomation({required this.pid, required this.profile});

  static const Duration _poll = Duration(milliseconds: 250);

  /// כל כמה זמן לשלוח שוב את פקודת פתיחת דיאלוג העיון.
  static const Duration _commandRepeat = Duration(seconds: 3);

  /// תקציב לרכישת הדיאלוג, נפרד מזה של הפעולה. הדיאלוג נפתח ב-1–2
  /// שניות כשהכול תקין; תקציב נדיב אינו מציל מצב תקוע, רק מכפיל את זמן
  /// הכשל בכל חוליה.
  static const Duration dialogBudget = Duration(seconds: 12);

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

    while (!deadline.expired) {
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
  /// סדר העדיפויות: קודם חלונות שאוצריא פתחה. רק אם אין כאלה והמצבור
  /// בתקרה — גם ותיקים אחרים. הענף השני אינו תיאורטי: שחזור-הסשן מחזיר
  /// מופע רווי גם אחרי הפעלה מחדש, ובלעדיו כשל אחד היה משאיר את
  /// השילוב מקולקל לצמיתות.
  int releaseMdiWindows(int main) {
    final titles = ResponsaWin32.mdiTitles(main);
    if (titles.length < profile.mdiSoftLimit) return 0;

    final surplus = titles.length - profile.mdiKeep;
    if (surplus <= 0) return 0;

    final ours = _openedWindows.where(titles.contains).toList();
    var toClose = ours.take(surplus).toList();
    if (toClose.isEmpty) toClose = titles.take(surplus).toList();
    if (toClose.isEmpty) return 0;

    final wanted = toClose.toSet();
    final client = ResponsaWin32.mdiClient(main);
    var closed = 0;
    if (client != null) {
      for (final child in ResponsaWin32.directChildren(client)) {
        if (wanted.contains(ResponsaWin32.windowText(child))) {
          ResponsaWin32.destroyMdiChild(main, child);
          closed++;
          sleepFor(const Duration(milliseconds: 200));
        }
      }
    }
    _openedWindows.removeWhere(wanted.contains);
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
    ({DiscoveredDialog dialog, List<String> results, String ref})? fallback;
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
      fallback ??= (
        dialog: attempt.dialog,
        results: attempt.results,
        ref: candidate,
      );
    }
    if (dialog == null && fallback != null) {
      // אף חוליה לא הניבה תוצאה משכנעת. פותחים את הטובה ביותר שהייתה
      // ונותנים לאימות הכותרת להכריע — הוא מדויק יותר מהשוואת השורות.
      usedRef = fallback.ref;
      dialog = fallback.dialog;
      results = fallback.results;
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
    ResponsaWin32.click(showButton);

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

    dismissInfoModals();
    sleepFor(_afterOpenSettle);

    // שתי בדיקות בלתי-תלויות: שהחלון הוא **השורה שבחרנו**, ושהוא הספר
    // **שביקשנו**. אחת בלבד אינה מספיקה.
    //
    // הכותרת המצופה נבדקת בלי ההסתייגות שבסוגריים: היא מטא-דאטה של
    // הקטלוג ולא חלק מהשם שהתוכנה מציגה. `היכלות (עמ' 108-126)` נפתח
    // ככותרת `אוצר מדרשים (אייזנשטיין) היכלות`, והשוואה מילולית פסלה
    // פתיחה תקינה לחלוטין.
    // `selectedResult` נשארת מחמירה: היא בודקת שהחלון שנפתח הוא **השורה
    // שלחצנו עליה**, וזו השוואה בין שני מחרוזות של התוכנה עצמה.
    //
    // `requestedRef` רכה, כי ההפניה נבנתה מהעץ והיא יכולה להכיל צמתי
    // מבנה שהתוכנה משמיטה: `ילקוט יוסף ... פסקי הלכות סימנים קנב-קנג`
    // נפתח ככותרת `ילקוט יוסף ... סימנים קנב-קנג` — הספר הנכון בדיוק,
    // ונפסל רק בגלל `פסקי הלכות`.
    final failed = <String>[
      if (ResponsaHebrew.matchLevel(chosen, title) == ResponsaMatchLevel.none)
        'selectedResult',
      if (!ResponsaHebrew.coversTitle(usedRef, title)) 'requestedRef',
    ];
    // הכותרת המצופה נבדקת ב-[ResponsaHebrew.coversTitle], שהיא רכה יותר
    // משתי הבדיקות שמעליה: היא מחרוזת תצוגה של אוצריא ולא של התוכנה,
    // ולכן היא יכולה גם להוסיף הקשר שהתוכנה משמיטה (`חידושים על הגמרא`)
    // וגם להשמיט מיקום שהתוכנה מוסיפה (`מסכת אבות הקדמה`). דרישה
    // סימטרית מלאה פסלה פתיחות תקינות לחלוטין.
    if (expectedTitle != null) {
      final expected = ResponsaNames.withoutQualifier(expectedTitle);
      if (!ResponsaHebrew.coversTitle(expected, title)) {
        failed.add('expectedTitle');
      }
    }
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
    if (isNew) _openedWindows.add(title);
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

  /// בוחר את התוצאה שמתאימה ביותר להפניה שביקשנו.
  ///
  /// `result[0]` אינו אמין: שם גנרי מחזיר מאות תוצאות שהראשונה בהן ספר
  /// אחר לגמרי. בשוויון נשארת המוקדמת — התנהגות ברירת המחדל.
  static int bestResult(
    List<String> results,
    String openRef,
    String? expectedTitle,
  ) {
    var bestIndex = 0;
    var bestScore = (-1, -1);
    for (var index = 0; index < results.length; index++) {
      final score = (
        ResponsaHebrew.matchLevel(openRef, results[index]).rank,
        expectedTitle == null
            ? 0
            : ResponsaHebrew.matchLevel(expectedTitle, results[index]).rank,
      );
      if (score.$1 > bestScore.$1 ||
          (score.$1 == bestScore.$1 && score.$2 > bestScore.$2)) {
        bestIndex = index;
        bestScore = score;
      }
    }
    return bestIndex;
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
    while (!deadline.expired) {
      _checkpoint(deadline);
      final titles = ResponsaWin32.mdiTitles(main);
      final fresh = titles.where((t) => t.isNotEmpty && !before.contains(t));
      if (fresh.isNotEmpty) {
        for (final title in fresh) {
          if (targets.any((t) => ResponsaHebrew.titlesMatch(t, title))) {
            return title;
          }
        }
        return fresh.first;
      }
      for (final title in titles) {
        if (title.isNotEmpty &&
            targets.any((t) => ResponsaHebrew.titlesMatch(t, title))) {
          return title;
        }
      }
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
    final targetSuffix = 'סימן ${ResponsaHebrew.intToNumeral(siman)}';
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

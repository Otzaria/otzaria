import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/models/index_check_scope.dart';
import 'package:otzaria/indexing/models/index_update_mode.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';

/// בקשת רענון שממתינה להחלטת אינדוקס.
/// [reconcile] - נדרשת השוואת טביעות-אצבע מול כל הספרייה.
/// [respectAutoUpdateSetting] - `false` בבקשה מפורשת של המשתמש
/// (otzaria://library/reindex), שרצה גם כשעדכון האינדקס האוטומטי כבוי.
typedef RefreshIndexRequest = ({bool reconcile, bool respectAutoUpdateSetting});

/// מוציא מ-[pendingRequests] את הבקשות שהרענון דיווח כמושלמות ומאחד אותן
/// להחלטה אחת. מזהה שרירה בבקשה שורד מיזוג רענונים, ולכן ההחלטה יוצאת על
/// ה-state שנושא בפועל את הספרים שהשתנו — ולא על רענון מוקדם שקדם למיזוג.
({bool indexWholeLibrary, bool reconcile, bool respectAutoUpdateSetting})
resolveCompletedIndexRequests({
  required Map<int, RefreshIndexRequest> pendingRequests,
  required Set<int>? completedRequestIds,
}) {
  var indexWholeLibrary = false;
  var reconcile = false;
  var respectAutoUpdateSetting = true;
  for (final id in completedRequestIds ?? const <int>{}) {
    final request = pendingRequests.remove(id);
    if (request == null) continue;
    indexWholeLibrary = true;
    reconcile |= request.reconcile;
    respectAutoUpdateSetting &= request.respectAutoUpdateSetting;
  }
  return (
    indexWholeLibrary: indexWholeLibrary,
    reconcile: reconcile,
    respectAutoUpdateSetting: respectAutoUpdateSetting,
  );
}

/// בונה את אירועי האינדוקס לרענון ספרייה בודד: לכל היותר ריצת אינדוקס אחת.
///
/// [newBooks] / [changedBooks] - הספרים שהרענון דיווח עליהם.
/// [indexWholeLibrary] - הרענון בא אחרי עדכון DB או בקשת reindex, ואז הריצה
/// עוברת על כל הספרייה במקום על [newBooks] בלבד.
/// [reconcile] - נדרשת השוואת טביעות-אצבע מול כל הספרייה (הורדה מלאה, או
/// שינוי בטבלאות שאינן ניתנות למיפוי לספרים מסוימים).
/// [indexUpdateMode] - הגדרת המשתמש; כשהיא כבויה לא רצה עבודת אינדוקס, ובמצב
/// "בלי ספרים אישיים" ספרים אישיים אינם נכנסים לתוכנית.
///
/// מחזיר רשימה ריקה כשאין מה לעשות.
List<IndexingEvent> buildRefreshIndexingPlan({
  required Library library,
  required List<Book> newBooks,
  required List<Book> changedBooks,
  required bool indexWholeLibrary,
  required bool reconcile,
  required IndexUpdateMode indexUpdateMode,
}) {
  if (!indexUpdateMode.isAutomatic) {
    if (changedBooks.isNotEmpty || reconcile) {
      return [
        DeferIndexing(
          library,
          changedBooks: changedBooks,
          checkLibrary: reconcile,
        ),
      ];
    }
    return newBooks.isEmpty ? const [] : [CheckIndexStatus(library)];
  }

  if (!indexUpdateMode.indexesPersonalBooks) {
    newBooks = newBooks.where(indexUpdateMode.admits).toList();
    changedBooks = changedBooks.where(indexUpdateMode.admits).toList();
  }
  // קובץ מסד מצורף מדווח כשינוי של כל ספריו; השוואת טביעת האצבע מחליפה רק
  // את אלה שתוכנם באמת השתנה. ל-PDF אין טביעת אצבע, ולכן הוא מוחלף כמדווח.
  final checkedBooks = <Book>[];
  final explicitChanged = <Book>[];
  for (final book in changedBooks) {
    (book.source.isAttached && book is! PdfBook
            ? checkedBooks
            : explicitChanged)
        .add(book);
  }
  final check = reconcile
      ? IndexCheckScope.library
      : checkedBooks.isEmpty
      ? IndexCheckScope.none
      : IndexCheckScope.books(checkedBooks);
  if (!indexWholeLibrary &&
      newBooks.isEmpty &&
      explicitChanged.isEmpty &&
      check.isNone) {
    return const [];
  }
  return [
    RunIndexing(
      library,
      books: indexWholeLibrary ? null : newBooks,
      changedBooks: explicitChanged,
      check: check,
    ),
  ];
}

/// מצב העדכון לתוכנית רענון: בקשה מפורשת ([respectSetting] false) רצה גם
/// כשהעדכון האוטומטי כבוי, ואז על כל הספרים כמו באינדוקס ידני.
IndexUpdateMode refreshIndexUpdateMode(
  IndexUpdateMode setting, {
  required bool respectSetting,
}) => respectSetting || setting.isAutomatic ? setting : IndexUpdateMode.all;

/// אירועי האינדוקס כשהמשתמש מחליף את מצב העדכון האוטומטי.
List<IndexingEvent> indexUpdateModeChangePlan(
  Library library, {
  required IndexUpdateMode previous,
  required IndexUpdateMode current,
}) => [
  if (!current.indexesPersonalBooks && previous.indexesPersonalBooks)
    DropOrphanedIndexEntries(library),
  if (current.isAutomatic &&
      (!previous.isAutomatic ||
          (current.indexesPersonalBooks && !previous.indexesPersonalBooks)))
    StartIndexing(library),
];

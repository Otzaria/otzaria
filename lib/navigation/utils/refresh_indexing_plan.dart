import 'package:otzaria/indexing/bloc/indexing_event.dart';
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

/// בונה את רשימת אירועי האינדוקס לרענון ספרייה בודד, בסדר ההזרמה.
///
/// [newBooks] / [changedBooks] - הספרים שהרענון דיווח עליהם.
/// [indexWholeLibrary] - הרענון בא אחרי עדכון DB או בקשת reindex, ואז
/// `StartIndexing` עובר על כל הספרייה במקום על [newBooks] בלבד.
/// [reconcile] - נדרשת השוואת טביעות-אצבע מול כל הספרייה (הורדה מלאה, או
/// שינוי בטבלאות שאינן ניתנות למיפוי לספרים מסוימים).
/// [autoUpdateIndex] - הגדרת המשתמש; כשהיא כבויה לא רצה עבודת אינדוקס.
///
/// מחזיר רשימה ריקה כשאין מה לעשות.
List<IndexingEvent> buildRefreshIndexingPlan({
  required Library library,
  required List<Book> newBooks,
  required List<Book> changedBooks,
  required bool indexWholeLibrary,
  required bool reconcile,
  required bool autoUpdateIndex,
}) {
  if (!autoUpdateIndex) {
    // ספרים חדשים שלא יאונדקסו משנים את מספר הספרים שאינם באינדקס — רק
    // מרעננים את החיווי. ספרים שהשתנו אינם משנים את המספר הזה.
    return newBooks.isEmpty ? const [] : [CheckIndexStatus(library)];
  }

  final events = <IndexingEvent>[];
  if (indexWholeLibrary) {
    // מדלג על ספרים שכבר באינדקס, ולכן מכסה את newBooks בלי מסלול נפרד.
    events.add(StartIndexing(library));
  } else if (newBooks.isNotEmpty) {
    events.add(IndexSpecificBooks(newBooks, library));
  }

  if (reconcile) {
    // ReconcileIndex מטפל רק בספרים שיש להם טביעת אצבע; PDF נשאר במסלול
    // המדויק של הספרים שהשתנו, כי אין לו טביעת אצבע להשוואה.
    events.add(ReconcileIndex(library));
    final changedPdfBooks = changedBooks.whereType<PdfBook>().toList();
    if (changedPdfBooks.isNotEmpty) {
      events.add(ReindexChangedBooks(changedPdfBooks, library));
    }
  } else if (changedBooks.isNotEmpty) {
    // קובץ מסד מצורף מדווח כשינוי של כל ספריו; ההשוואה לפי טביעת אצבע
    // מאנדקסת מחדש רק את אלה שתוכנם באמת השתנה.
    final attachedTextBooks = <Book>[];
    final otherBooks = <Book>[];
    for (final book in changedBooks) {
      (book.source.isAttached && book is! PdfBook
              ? attachedTextBooks
              : otherBooks)
          .add(book);
    }
    if (attachedTextBooks.isNotEmpty) {
      events.add(ReconcileIndex(library, books: attachedTextBooks));
    }
    // StartIndexing מדלג על ספרים קיימים — לשונים נדרש מסלול משלהם.
    if (otherBooks.isNotEmpty) {
      events.add(ReindexChangedBooks(otherBooks, library));
    }
  }
  return events;
}

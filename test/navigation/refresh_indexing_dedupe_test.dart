// מריץ את תוכנית הרענון שבה משתמש MainWindowScreen.

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/models/index_check_scope.dart';
import 'package:otzaria/indexing/models/index_update_mode.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/utils/refresh_indexing_plan.dart';

Library _emptyLibrary() => Library(categories: []);

void main() {
  final library = _emptyLibrary();
  final newBooks = [TextBook(title: 'ספר חדש')];
  final changedBooks = [TextBook(title: 'ספר שהשתנה')];

  List<IndexingEvent> plan({
    bool indexWholeLibrary = false,
    bool reconcile = false,
    IndexUpdateMode indexUpdateMode = IndexUpdateMode.all,
    bool withNew = true,
    bool withChanged = true,
  }) => buildRefreshIndexingPlan(
    library: library,
    newBooks: withNew ? newBooks : const [],
    changedBooks: withChanged ? changedBooks : const [],
    indexWholeLibrary: indexWholeLibrary,
    reconcile: reconcile,
    indexUpdateMode: indexUpdateMode,
  );

  RunIndexing single(List<IndexingEvent> events) {
    expect(events, hasLength(1));
    return events.single as RunIndexing;
  }

  group('buildRefreshIndexingPlan', () {
    test('reconcile — ריצה אחת על כל הספרייה עם בדיקה מלאה', () {
      final run = single(plan(indexWholeLibrary: true, reconcile: true));

      expect(run.books, isNull, reason: 'כל הספרייה מכסה את הספרים החדשים');
      expect(run.check, IndexCheckScope.library);
      // ספר שדווח כשונה מוחלף ישירות, ואינו נבדק פעם שנייה.
      expect(run.changedBooks, changedBooks);
    });

    test('reconcile מחליף PDF שדווח כשונה — אין לו טביעת אצבע', () {
      final changedPdf = PdfBook(title: 'ספר סרוק', path: '/tmp/scanned.pdf');
      final run = single(
        buildRefreshIndexingPlan(
          library: library,
          newBooks: newBooks,
          changedBooks: [changedBooks.single, changedPdf],
          indexWholeLibrary: true,
          reconcile: true,
          indexUpdateMode: IndexUpdateMode.all,
        ),
      );

      expect(run.check, IndexCheckScope.library);
      expect(run.changedBooks, [changedBooks.single, changedPdf]);
    });

    test('ספרי מסד מצורף שהשתנה — נבדקים, ואחרים מוחלפים, באותה ריצה', () {
      final attached = TextBook(
        id: 1,
        title: 'ספר ממסד',
        source: BookSource.attached('lib-a'),
      );
      final regular = TextBook(title: 'ספר רגיל');
      final run = single(
        buildRefreshIndexingPlan(
          library: library,
          newBooks: const [],
          changedBooks: [attached, regular],
          indexWholeLibrary: false,
          reconcile: false,
          indexUpdateMode: IndexUpdateMode.all,
        ),
      );

      expect(run.books, isEmpty);
      expect(run.check, IndexCheckScope.books([attached]));
      expect(run.changedBooks, [regular]);
    });

    test('החלפת מסד גדול מחלקת ספרים לבדיקה בזמן ליניארי', () {
      final attached = List.generate(200, _ComparisonCountingBook.new);
      _ComparisonCountingBook.comparisons = 0;

      final run = single(
        buildRefreshIndexingPlan(
          library: library,
          newBooks: const [],
          changedBooks: attached,
          indexWholeLibrary: false,
          reconcile: false,
          indexUpdateMode: IndexUpdateMode.all,
        ),
      );

      expect(
        _ComparisonCountingBook.comparisons,
        lessThan(attached.length * 5),
      );
      expect(run.check.books, hasLength(attached.length));
      expect(run.changedBooks, isEmpty);
    });

    test('PDF ממסד מצורף שהשתנה — מוחלף, בלי טביעת אצבע', () {
      final attachedPdf = PdfBook(
        id: 2,
        title: 'סרוק ממסד',
        path: '/tmp/attached.pdf',
        source: BookSource.attached('lib-a'),
      );
      final run = single(
        buildRefreshIndexingPlan(
          library: library,
          newBooks: const [],
          changedBooks: [attachedPdf],
          indexWholeLibrary: false,
          reconcile: false,
          indexUpdateMode: IndexUpdateMode.all,
        ),
      );

      expect(run.check, IndexCheckScope.none);
      expect(run.changedBooks, [attachedPdf]);
    });

    test('עדכון דלתא בלי reconcile — חדשים ושהשתנו בריצה אחת', () {
      final run = single(plan(indexWholeLibrary: true));

      expect(run.books, isNull);
      expect(run.changedBooks, changedBooks);
      expect(run.check, IndexCheckScope.none);
    });

    test('רענון רגיל (בלי עדכון ספרייה) — רק הספרים שדווחו', () {
      final run = single(plan());

      expect(run.books, same(newBooks));
      expect(run.changedBooks, changedBooks);
      expect(run.check, IndexCheckScope.none);
    });

    test('אינדוקס כבוי — שומר שינויים ובדיקה מלאה בלי להתחיל ריצה', () {
      final events = plan(
        indexWholeLibrary: true,
        reconcile: true,
        indexUpdateMode: IndexUpdateMode.off,
      );

      expect(events.whereType<RunIndexing>(), isEmpty);
      final deferred = events.single as DeferIndexing;
      expect(deferred.library, same(library));
      expect(deferred.changedBooks, changedBooks);
      expect(deferred.checkLibrary, isTrue);
    });

    test('אינדוקס כבוי — שומר שינויים גם בלי ספרים חדשים', () {
      final deferred =
          plan(indexUpdateMode: IndexUpdateMode.off, withNew: false).single
              as DeferIndexing;

      expect(deferred.changedBooks, changedBooks);
      expect(deferred.checkLibrary, isFalse);
    });

    test('אינדוקס כבוי — שומר בדיקה מלאה גם בלי רשימת שינויים', () {
      final deferred =
          plan(
                indexWholeLibrary: true,
                reconcile: true,
                indexUpdateMode: IndexUpdateMode.off,
                withNew: false,
                withChanged: false,
              ).single
              as DeferIndexing;

      expect(deferred.changedBooks, isEmpty);
      expect(deferred.checkLibrary, isTrue);
    });

    test('אינדוקס כבוי — ספרים חדשים בלבד מרעננים את החיווי', () {
      final events = plan(
        indexUpdateMode: IndexUpdateMode.off,
        withChanged: false,
      );

      expect(events.single, isA<CheckIndexStatus>());
    });

    test('אינדוקס כבוי בלי שינויים — אין אירוע כלל', () {
      expect(
        plan(
          indexUpdateMode: IndexUpdateMode.off,
          withNew: false,
          withChanged: false,
        ),
        isEmpty,
      );
    });

    test('אין ספרים חדשים או שונים — ריצה על כל הספרייה בלבד', () {
      final run = single(
        plan(indexWholeLibrary: true, withNew: false, withChanged: false),
      );

      expect(run.books, isNull);
      expect(run.changedBooks, isEmpty);
    });

    test('רענון בלי שום שינוי — אין ריצה', () {
      expect(plan(withNew: false, withChanged: false), isEmpty);
    });
  });

  group('resolveCompletedIndexRequests', () {
    test('בקשה שהרענון דיווח נצרכת ומוסרת מהמפה', () {
      final pending = <int, RefreshIndexRequest>{
        1: (reconcile: true, respectAutoUpdateSetting: true),
      };

      final resolved = resolveCompletedIndexRequests(
        pendingRequests: pending,
        completedRequestIds: {1},
      );

      expect(resolved.indexWholeLibrary, isTrue);
      expect(resolved.reconcile, isTrue);
      expect(resolved.respectAutoUpdateSetting, isTrue);
      expect(pending, isEmpty, reason: 'בקשה שנצרכה לא תרוץ שוב ברענון הבא');
    });

    test('רענון בלי מזהים — אין החלטת אינדוקס, והבקשה נשארת ממתינה', () {
      final pending = <int, RefreshIndexRequest>{
        1: (reconcile: true, respectAutoUpdateSetting: true),
      };

      final resolved = resolveCompletedIndexRequests(
        pendingRequests: pending,
        completedRequestIds: null,
      );

      expect(resolved.indexWholeLibrary, isFalse);
      expect(resolved.reconcile, isFalse);
      expect(pending, hasLength(1));
    });

    test('מזהה שאינו שלנו (רענון של רכיב אחר) — נדחה', () {
      final resolved = resolveCompletedIndexRequests(
        pendingRequests: <int, RefreshIndexRequest>{
          1: (reconcile: true, respectAutoUpdateSetting: true),
        },
        completedRequestIds: {99},
      );

      expect(resolved.indexWholeLibrary, isFalse);
    });

    test('בקשת deep-link אינה מכבדת את הגדרת האינדוקס האוטומטי', () {
      final resolved = resolveCompletedIndexRequests(
        pendingRequests: <int, RefreshIndexRequest>{
          1: (reconcile: true, respectAutoUpdateSetting: false),
        },
        completedRequestIds: {1},
      );

      expect(resolved.respectAutoUpdateSetting, isFalse);
      // כך ה-listener מחשב את מצב העדכון שהוא מעביר לתוכנית.
      final events = plan(
        indexWholeLibrary: resolved.indexWholeLibrary,
        reconcile: resolved.reconcile,
        indexUpdateMode: refreshIndexUpdateMode(
          IndexUpdateMode.off,
          respectSetting: resolved.respectAutoUpdateSetting,
        ),
      );
      final run = single(events);
      expect(run.books, isNull);
      expect(run.check, IndexCheckScope.library);
    });

    test('כמה בקשות שהתמזגו לרענון אחד — reconcile גובר', () {
      final resolved = resolveCompletedIndexRequests(
        pendingRequests: <int, RefreshIndexRequest>{
          1: (reconcile: false, respectAutoUpdateSetting: true),
          2: (reconcile: true, respectAutoUpdateSetting: true),
        },
        completedRequestIds: {1, 2},
      );

      expect(resolved.reconcile, isTrue);
    });
  });

  // המסלול שהיה שובר את הדיכוי: LibraryBloc ממזג רענונים, ולכן הספרים
  // שהשתנו נפלטים ב-state מאוחר יותר מזה שסיים את הרענון שהיה בתנועה.
  group('רענון שהתמזג — ההחלטה רצה על ה-state שנושא את הספרים', () {
    test('הרענון המוקדם אינו צורך את הבקשה, והמאוחד מדכא את המסלול הכפול', () {
      // עדכון הספרייה רשם בקשה בזמן שרענון רקע היה בתנועה.
      final pending = <int, RefreshIndexRequest>{
        7: (reconcile: true, respectAutoUpdateSetting: true),
      };

      // S_A: הרענון שהיה בתנועה מסתיים. המזהה נצבר לרענון המאוחד ולא דווח כאן.
      final resolvedA = resolveCompletedIndexRequests(
        pendingRequests: pending,
        completedRequestIds: null,
      );
      final planA = buildRefreshIndexingPlan(
        library: library,
        newBooks: const [],
        changedBooks: const [],
        indexWholeLibrary: resolvedA.indexWholeLibrary,
        reconcile: resolvedA.reconcile,
        indexUpdateMode: IndexUpdateMode.all,
      );
      expect(
        planA,
        isEmpty,
        reason: 'הרענון המוקדם אינו הרענון שקלט את הבקשה',
      );
      expect(pending, hasLength(1), reason: 'הבקשה עוד ממתינה');

      // S_B: הרענון המאוחד מסתיים — נושא את המזהה *ואת* הספרים שהשתנו.
      final resolvedB = resolveCompletedIndexRequests(
        pendingRequests: pending,
        completedRequestIds: {7},
      );
      final planB = buildRefreshIndexingPlan(
        library: library,
        newBooks: newBooks,
        changedBooks: changedBooks,
        indexWholeLibrary: resolvedB.indexWholeLibrary,
        reconcile: resolvedB.reconcile,
        indexUpdateMode: IndexUpdateMode.all,
      );

      // זה היה הבאג: שני מסלולים חופפים על אותם ספרים. כעת ריצה אחת.
      final run = single(planB);
      expect(run.books, isNull);
      expect(run.check, IndexCheckScope.library);
      expect(pending, isEmpty);
    });
  });

  group('מצב "בלי ספרים אישיים"', () {
    final personalNew = TextBook(
      title: 'ספר אישי חדש',
      source: BookSource.user,
    );
    final personalChanged = PdfBook(
      title: 'PDF אישי',
      path: '/personal/a.pdf',
      source: BookSource.user,
    );

    test('ספרים אישיים חדשים ושהשתנו אינם נכנסים לתוכנית', () {
      final events = buildRefreshIndexingPlan(
        library: library,
        newBooks: [personalNew],
        changedBooks: [personalChanged],
        indexWholeLibrary: false,
        reconcile: false,
        indexUpdateMode: IndexUpdateMode.libraryOnly,
      );

      expect(events, isEmpty);
    });

    test('ספרי הספרייה עדיין מאונדקסים', () {
      final events = buildRefreshIndexingPlan(
        library: library,
        newBooks: [...newBooks, personalNew],
        changedBooks: const [],
        indexWholeLibrary: false,
        reconcile: false,
        indexUpdateMode: IndexUpdateMode.libraryOnly,
      );

      expect(single(events).books, newBooks);
    });

    test('בקשה מפורשת כשהעדכון כבוי רצה על כל הספרים', () {
      expect(
        refreshIndexUpdateMode(IndexUpdateMode.off, respectSetting: false),
        IndexUpdateMode.all,
      );
      expect(
        refreshIndexUpdateMode(
          IndexUpdateMode.libraryOnly,
          respectSetting: false,
        ),
        IndexUpdateMode.libraryOnly,
      );
      expect(
        refreshIndexUpdateMode(IndexUpdateMode.off, respectSetting: true),
        IndexUpdateMode.off,
      );
    });
  });

  group('indexUpdateModeChangePlan', () {
    List<Type> change(IndexUpdateMode from, IndexUpdateMode to) =>
        indexUpdateModeChangePlan(
          library,
          previous: from,
          current: to,
        ).map((e) => e.runtimeType).toList();

    test('מעבר ל"בלי ספרים אישיים" מסיר את הספרים האישיים מהאינדקס', () {
      expect(change(IndexUpdateMode.all, IndexUpdateMode.libraryOnly), [
        DropOrphanedIndexEntries,
      ]);
    });

    test('הפעלה מכבוי ל"בלי ספרים אישיים" — ניקוי ואינדוקס', () {
      expect(change(IndexUpdateMode.off, IndexUpdateMode.libraryOnly), [
        DropOrphanedIndexEntries,
        StartIndexing,
      ]);
    });

    test('חזרה ל"כל הספרים" מאנדקסת את הספרים האישיים', () {
      expect(change(IndexUpdateMode.libraryOnly, IndexUpdateMode.all), [
        StartIndexing,
      ]);
      expect(change(IndexUpdateMode.off, IndexUpdateMode.all), [
        StartIndexing,
      ]);
    });

    test('כיבוי אינו מריץ עבודה', () {
      expect(change(IndexUpdateMode.all, IndexUpdateMode.off), isEmpty);
      expect(change(IndexUpdateMode.libraryOnly, IndexUpdateMode.off), isEmpty);
    });
  });
}

class _ComparisonCountingBook extends TextBook {
  _ComparisonCountingBook(int id)
    : super(id: id, title: 'ספר $id', source: BookSource.attached('large'));

  static int comparisons = 0;

  @override
  bool operator ==(Object other) {
    comparisons++;
    return identical(this, other);
  }

  @override
  int get hashCode => identityHashCode(this);
}

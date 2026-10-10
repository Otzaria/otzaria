// Regression test: אחרי עדכון ספרייה שדורש reconcile רצו שני מסלולי אינדוקס
// חופפים על אותו רענון — ReconcileIndex (כל ספר שטביעת אצבעו השתנתה) ומיד
// אחריו ReindexChangedBooks על אותם ספרים, כ-12,000 פעולות במקום ~6,000.
//
// הטסט מייבא ומריץ את הקוד האמיתי מ-lib/navigation/utils/refresh_indexing_plan
// .dart — אותן פונקציות שה-listener ב-main_window_screen.dart קורא להן.

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
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
    bool autoUpdateIndex = true,
    bool withNew = true,
    bool withChanged = true,
  }) => buildRefreshIndexingPlan(
    library: library,
    newBooks: withNew ? newBooks : const [],
    changedBooks: withChanged ? changedBooks : const [],
    indexWholeLibrary: indexWholeLibrary,
    reconcile: reconcile,
    autoUpdateIndex: autoUpdateIndex,
  );

  group('buildRefreshIndexingPlan', () {
    test('reconcile — רק StartIndexing ו-ReconcileIndex, בלי מסלול שני', () {
      final events = plan(indexWholeLibrary: true, reconcile: true);

      expect(events, hasLength(2));
      expect(events[0], isA<StartIndexing>());
      expect(events[1], isA<ReconcileIndex>());
      expect(
        events.whereType<ReindexChangedBooks>(),
        isEmpty,
        reason: 'ReconcileIndex כבר מאנדקס מחדש כל ספר שהשתנה',
      );
      expect(
        events.whereType<IndexSpecificBooks>(),
        isEmpty,
        reason: 'StartIndexing כבר מכסה את הספרים החדשים',
      );
    });

    test('reconcile מאנדקס מחדש PDF שדווח כשונה, ולא את ספרי הטקסט', () {
      final changedPdf = PdfBook(title: 'ספר סרוק', path: '/tmp/scanned.pdf');
      final events = buildRefreshIndexingPlan(
        library: library,
        newBooks: newBooks,
        changedBooks: [changedBooks.single, changedPdf],
        indexWholeLibrary: true,
        reconcile: true,
        autoUpdateIndex: true,
      );

      expect(events.map((event) => event.runtimeType), [
        StartIndexing,
        ReconcileIndex,
        ReindexChangedBooks,
      ]);
      expect((events.last as ReindexChangedBooks).books, [changedPdf]);
    });

    test('ספרי מסד מצורף שהשתנה — השוואת טביעת אצבע רק להם, אחרים כרגיל', () {
      final attached = TextBook(
        id: 1,
        title: 'ספר ממסד',
        source: BookSource.attached('lib-a'),
      );
      final regular = TextBook(title: 'ספר רגיל');
      final events = buildRefreshIndexingPlan(
        library: library,
        newBooks: const [],
        changedBooks: [attached, regular],
        indexWholeLibrary: false,
        reconcile: false,
        autoUpdateIndex: true,
      );

      expect(events.map((event) => event.runtimeType), [
        ReconcileIndex,
        ReindexChangedBooks,
      ]);
      expect((events[0] as ReconcileIndex).books, [attached]);
      expect((events[1] as ReindexChangedBooks).books, [regular]);
    });

    test('PDF ממסד מצורף שהשתנה — אינדוקס מחדש מלא, בלי טביעת אצבע', () {
      final attachedPdf = PdfBook(
        id: 2,
        title: 'סרוק ממסד',
        path: '/tmp/attached.pdf',
        source: BookSource.attached('lib-a'),
      );
      final events = buildRefreshIndexingPlan(
        library: library,
        newBooks: const [],
        changedBooks: [attachedPdf],
        indexWholeLibrary: false,
        reconcile: false,
        autoUpdateIndex: true,
      );

      expect(events.map((event) => event.runtimeType), [ReindexChangedBooks]);
      expect((events.single as ReindexChangedBooks).books, [attachedPdf]);
    });

    test('עדכון דלתא בלי reconcile — ReindexChangedBooks כן רץ', () {
      final events = plan(indexWholeLibrary: true);

      expect(events, hasLength(2));
      expect(events[0], isA<StartIndexing>());
      expect(
        events[1],
        isA<ReindexChangedBooks>(),
        reason:
            'StartIndexing מדלג על ספרים קיימים — השונים חייבים מסלול משלהם',
      );
      expect(events.whereType<ReconcileIndex>(), isEmpty);
    });

    test('רענון רגיל (בלי עדכון ספרייה) — ספציפי לספרים שדווחו', () {
      final events = plan();

      expect(events, hasLength(2));
      expect(events[0], isA<IndexSpecificBooks>());
      expect((events[0] as IndexSpecificBooks).books, same(newBooks));
      expect(events[1], isA<ReindexChangedBooks>());
      expect((events[1] as ReindexChangedBooks).books, changedBooks);
      expect(events.whereType<StartIndexing>(), isEmpty);
    });

    test('אינדוקס אוטומטי כבוי — אין עבודת אינדוקס, רק CheckIndexStatus', () {
      final events = plan(
        indexWholeLibrary: true,
        reconcile: true,
        autoUpdateIndex: false,
      );

      expect(events.whereType<IndexingWorkEvent>(), isEmpty);
      expect(events, hasLength(1));
      expect(events.single, isA<CheckIndexStatus>());
    });

    test('אינדוקס אוטומטי כבוי בלי ספרים חדשים — אין אירוע כלל', () {
      expect(plan(autoUpdateIndex: false, withNew: false), isEmpty);
    });

    test('אין ספרים חדשים או שונים — StartIndexing בלבד', () {
      final events = plan(
        indexWholeLibrary: true,
        withNew: false,
        withChanged: false,
      );

      expect(events, hasLength(1));
      expect(events.single, isA<StartIndexing>());
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
      // כך ה-listener מחשב את autoUpdateIndex שהוא מעביר לתוכנית.
      final events = plan(
        indexWholeLibrary: resolved.indexWholeLibrary,
        reconcile: resolved.reconcile,
        autoUpdateIndex: !resolved.respectAutoUpdateSetting,
      );
      expect(events.map((e) => e.runtimeType), [
        StartIndexing,
        ReconcileIndex,
      ]);
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
        autoUpdateIndex: true,
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
        autoUpdateIndex: true,
      );

      expect(planB.map((e) => e.runtimeType), [
        StartIndexing,
        ReconcileIndex,
      ]);
      expect(
        planB.whereType<ReindexChangedBooks>(),
        isEmpty,
        reason: 'זה היה הבאג: ReindexChangedBooks רץ מעל ה-ReconcileIndex',
      );
      expect(pending, isEmpty);
    });
  });
}

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/book_search_worker.dart';
import 'package:otzaria/data/repository/book_title_search_diagnostics.dart';

void main() {
  final start = DateTime(2026, 11, 19, 8);
  late List<({String title, Object error, Map<String, String?> details})>
  written;

  BookTitleSearchDiagnostics registry(FakeAsync async) =>
      BookTitleSearchDiagnostics(
        stallThreshold: const Duration(seconds: 60),
        now: () => start.add(async.elapsed),
        writeLog: ({required title, required error, details = const {}}) =>
            written.add((title: title, error: error, details: details)),
      );

  setUp(() => written = []);

  test('השלב שבו החיפוש ממתין והזמן בו נכנסים לדוח', () {
    fakeAsync((async) {
      final searches = registry(async);
      final search = searches.start(
        words: 2,
        wholeLibrary: true,
        repositoryState: () => {'acronymsLoaded': false},
      );
      async.elapse(const Duration(seconds: 2));
      search.enter(BookTitleSearchStage.acronyms);
      async.elapse(const Duration(seconds: 3));

      final collected = searches.collect();
      expect(collected['started'], 1);
      expect(collected['repository'], {'acronymsLoaded': false});
      expect((collected['active'] as List).single, {
        'id': 1,
        'stage': 'acronyms',
        'elapsedMs': 5000,
        'stageMs': 3000,
        'words': 2,
        'wholeLibrary': true,
      });

      search
        ..catalogBuilt(12000)
        ..found(books: 4, categories: 1)
        ..finish();
      final after = searches.collect();
      expect(after['active'], isEmpty);
      expect(after['last'], containsPair('outcome', 'ok'));
      expect(after['last'], containsPair('books', 4));
      expect(after['last'], containsPair('catalogBooks', 12000));
      expect(written, isEmpty);
    });
  });

  test('חיפוש שלא הסתיים נרשם ביומן, וגם סיומו המאוחר', () {
    fakeAsync((async) {
      final searches = registry(async);
      final search = searches.start(
        words: 1,
        wholeLibrary: true,
        repositoryState: () => {
          'worker': {'mode': 'running', 'awaitingReply': true},
        },
      );
      search.enter(BookTitleSearchStage.worker);
      async.elapse(const Duration(seconds: 59));
      expect(written, isEmpty);
      async.elapse(const Duration(seconds: 1));

      expect(written.single.title, 'Library title search stall');
      expect(written.single.details['stage'], 'worker');
      expect(written.single.details['Repository'], contains('awaitingReply'));

      async.elapse(const Duration(minutes: 5));
      expect(written, hasLength(1));
      search.finish(const BookSearchSupersededException());
      expect(written.last.title, 'Library title search stall resolved');
      expect(written.last.error, contains('superseded'));
      expect(searches.collect()['superseded'], 1);
    });
  });

  test('חיפושים נוספים שנתקעים באותו זמן אינם מוסיפים רשומות', () {
    fakeAsync((async) {
      final searches = registry(async);
      final first = searches.start(words: 1, wholeLibrary: true)
        ..enter(BookTitleSearchStage.acronyms);
      async.elapse(const Duration(seconds: 10));
      final second = searches.start(words: 2, wholeLibrary: true)
        ..enter(BookTitleSearchStage.acronyms);
      async.elapse(const Duration(seconds: 70));
      expect(written.single.title, 'Library title search stall');
      expect(written.single.details['Active searches'], '2');

      second.finish();
      first.finish();
      expect(written.last.title, 'Library title search stall resolved');
      expect(written, hasLength(2));
    });
  });

  test('תקיעה מסתיימת ביומן רק אחרי שכל החיפושים שנתקעו הסתיימו', () {
    fakeAsync((async) {
      final searches = registry(async);
      final first = searches.start(words: 1, wholeLibrary: true)
        ..enter(BookTitleSearchStage.acronyms);
      async.elapse(const Duration(seconds: 10));
      final second = searches.start(words: 2, wholeLibrary: true)
        ..enter(BookTitleSearchStage.acronyms);
      async.elapse(const Duration(seconds: 65));

      expect(written.single.details['id'], '1');
      first.finish();
      expect(written, hasLength(1));
      second.finish();
      expect(written, hasLength(2));
      expect(written.last.title, 'Library title search stall resolved');
    });
  });

  test('החלפת הקריאה הנמדדת שומרת את סף הזמן של הקריאה הבאה', () {
    fakeAsync((async) {
      final searches = registry(async);
      final first = searches.start(words: 1, wholeLibrary: true);
      async.elapse(const Duration(seconds: 30));
      final second = searches.start(words: 1, wholeLibrary: true)
        ..enter(BookTitleSearchStage.worker);

      async.elapse(const Duration(seconds: 15));
      first.finish(const BookSearchSupersededException());
      async.elapse(const Duration(seconds: 44));
      expect(written, isEmpty);
      async.elapse(const Duration(seconds: 1));
      expect(written.single.details['id'], '2');

      second.finish(StateError('private details'));
      expect(written.last.error, contains('error:StateError'));
      expect(
        written.last.details.toString(),
        isNot(contains('private details')),
      );
      expect(searches.collect()['failed'], 1);
      expect(searches.collect()['superseded'], 1);
    });
  });

  test('רצף ארוך של חיפושים תקועים שומר מדגם חסום וטיימר אחד', () {
    fakeAsync((async) {
      final searches = registry(async);
      final pending = List.generate(
        128,
        (_) => searches.start(words: 1, wholeLibrary: true),
      );
      var collected = searches.collect();
      final sample = collected['active'] as List;
      expect(sample.length, lessThan(pending.length));
      expect(collected['activeCount'], pending.length);
      expect(sample.first, containsPair('id', 1));
      expect(async.nonPeriodicTimerCount, 1);
      async.elapse(const Duration(seconds: 60));
      expect(written.single.details['id'], '1');

      for (final search in pending.take(127)) {
        search.finish();
      }
      expect(written, hasLength(1));
      pending.last.finish();
      expect(written, hasLength(2));
      collected = searches.collect();
      expect(collected['activeCount'], 0);
      expect(collected['active'], isEmpty);
      expect(async.nonPeriodicTimerCount, 0);
    });
  });

  test('פעילות ממושכת מחוץ למדגם נרשמת בלי שיוך לחיפוש בודד', () {
    fakeAsync((async) {
      final searches = registry(async);
      final sample = List.generate(
        32,
        (_) => searches.start(words: 1, wholeLibrary: true),
      );
      async.elapse(const Duration(seconds: 10));
      final unsampled = searches.start(words: 1, wholeLibrary: true);
      async.elapse(const Duration(seconds: 35));
      for (final search in sample) {
        search.finish();
      }
      expect(searches.collect()['active'], isEmpty);
      expect(async.nonPeriodicTimerCount, 1);

      // גמר של חיפוש חדש ומהיר לא מאפס את שעון הפעילות שמחוץ למדגם.
      async.elapse(const Duration(seconds: 5));
      searches.start(words: 1, wholeLibrary: true).finish();
      final newer = searches.start(words: 1, wholeLibrary: true);
      async.elapse(const Duration(seconds: 19));
      expect(written, isEmpty);
      async.elapse(const Duration(seconds: 1));

      expect(written.single.title, 'Library title search stall');
      expect(written.single.error, contains('not sampled'));
      expect(written.single.details, isNot(contains('id')));
      expect(written.single.details['Active searches'], '2');
      expect(written.single.details['Unsampled active searches'], '1');
      final stallId = written.single.details['Stall id'];
      expect(stallId, isNotNull);
      unsampled.finish();
      expect(written.last.title, 'Library title search stall resolved');
      expect(written.last.details['Stall id'], stallId);
      newer.finish();
      expect(async.nonPeriodicTimerCount, 0);
    });
  });

  test('קטלוג ריק בחיפוש בכל הספרייה נרשם פעם אחת בלבד', () {
    fakeAsync((async) {
      final searches = registry(async);
      for (var i = 0; i < 2; i++) {
        searches.start(words: 1, wholeLibrary: true)
          ..catalogBuilt(0)
          ..found(books: 0, categories: 0)
          ..finish();
      }
      // תיקייה ריקה אינה חשודה.
      searches.start(words: 1, wholeLibrary: false)
        ..catalogBuilt(0)
        ..found(books: 0, categories: 0)
        ..finish();

      expect(written.single.title, 'Library title search: empty catalog');
    });
  });

  test('כשל נספר, ו-finish כפול אינו משנה את התוצאה', () {
    fakeAsync((async) {
      final searches = registry(async);
      searches.start(words: 1, wholeLibrary: true)
        ..finish(StateError('db'))
        ..finish();
      final collected = searches.collect();
      expect(collected['failed'], 1);
      expect(collected['last'], containsPair('outcome', 'error:StateError'));
      async.elapse(const Duration(minutes: 2));
      expect(written, isEmpty);
    });
  });
}

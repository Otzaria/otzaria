import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/active_lexical_searches.dart';

void main() {
  final start = DateTime(2026, 11, 15, 10);
  final query = ActiveLexicalSearches.describeQuery(
    query: 'גיד הנשה של אדם',
    negativeQuery: '',
    mode: 'exact',
    searchOptions: {
      'גיד_0': {'קידומות': true, 'סיומות': false},
      'אדם_3': {'סיומות דקדוקיות': true},
    },
    alternativeWords: {
      1: ['נשה'],
    },
    customSpacing: const {},
    facets: 1,
    isRegex: false,
  );

  late List<({String title, Object error, Map<String, String?> details})>
  written;

  ActiveLexicalSearches registry(FakeAsync async) => ActiveLexicalSearches(
    now: () => start.add(async.elapsed),
    writeStall: ({required title, required error, details = const {}}) =>
        written.add((title: title, error: error, details: details)),
  );

  setUp(() => written = []);

  test('מאפייני השאילתה בלי טקסט השאילתה', () {
    expect(query, {
      'words': 4,
      'mode': 'exact',
      'regex': false,
      'prefixes': true,
      'suffixes': true,
      'options': ['word.grammatical-suffixes', 'word.prefixes'],
      'wordsWithAlternatives': 1,
      'customSpacing': 0,
      'negative': false,
      'facets': 1,
    });
    expect(query.toString(), isNot(contains('גיד')));
  });

  test('רישום, שלב, זמן והסרה', () {
    fakeAsync((async) {
      final searches = registry(async);
      final first = searches.start(query);
      final second = searches.start(query);
      async.elapse(const Duration(seconds: 3));
      first.onEvent(phase: LexicalSearchPhase.counting, total: 12);
      async.elapse(const Duration(seconds: 2));
      first.onEvent(received: 5);

      final collected = searches.collect();
      expect(collected['activeCount'], 2);
      final described = (collected['lexical'] as List).first as Map;
      expect(described['phase'], 'counting');
      expect(described['elapsedMs'], 5000);
      expect(described['sinceLastEventMs'], 0);
      expect(described['received'], 5);
      expect(described['total'], 12);
      expect(described['query'], query);

      first.finish('completed');
      first.finish('cancelled');
      expect(searches.active, [second]);
      second.finish('cancelled');
      expect(searches.collect()['activeCount'], 0);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('חיפוש שלא הסתיים בזמן נרשם פעם אחת, ובסיומו נרשם המשך', () {
    fakeAsync((async) {
      final searches = registry(async);
      final search = searches.start(query);
      async.elapse(const Duration(seconds: 59));
      expect(written, isEmpty);
      async.elapse(const Duration(seconds: 1));
      expect(written, hasLength(1));
      expect(written.single.title, 'Search stall');
      expect(written.single.details['phase'], 'waitingFirstPage');
      expect(written.single.details['elapsedMs'], '60000');
      expect(written.single.details['Active searches'], '1');
      expect(written.single.details.toString(), isNot(contains('גיד')));

      async.elapse(const Duration(minutes: 5));
      expect(written, hasLength(1));
      search.finish('completed');
      expect(written.last.title, 'Search stall resolved');
      expect(written.last.details['Outcome'], 'completed');
      expect(written.last.details['elapsedMs'], '360000');
    });
  });

  test('חיפוש שהסתיים או בוטל לפני הסף אינו נרשם', () {
    fakeAsync((async) {
      final searches = registry(async);
      searches.start(query).finish('completed');
      final cancelled = searches.start(query);
      async.elapse(const Duration(seconds: 30));
      cancelled.finish('cancelled');
      async.elapse(const Duration(minutes: 2));
      expect(written, isEmpty);
      expect(async.pendingTimers, isEmpty);
    });
  });
}

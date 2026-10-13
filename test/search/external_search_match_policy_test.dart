import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/view/external_search_results_section.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SearchScope, WordMatchMode;

import '../support/search_engine_test_init.dart';

/// מדיניות ההתאמה שהמדור החיצוני שולח לספק (issue #1427): במצב המתקדם
/// היא נמסרת כמות שהיא; במדויק/מקורב אין לה משמעות, והספק מקבל ברירת מחדל.
Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  SearchState stateWith(SearchMode mode) => SearchState(
    searchQuery: 'ברכת המזון',
    totalResults: 0,
    results: const [],
    configuration: SearchConfiguration(
      searchMode: mode,
      proximityScope: SearchScope.sameParagraph,
      wordMatchMode: WordMatchMode.mostWords,
    ),
  );

  test('במצב המתקדם הטווח ומדיניות המילים עוברים לספק', () {
    final policy = externalMatchPolicyOf(stateWith(SearchMode.advanced));
    expect(policy.proximityScope, SearchScope.sameParagraph);
    expect(policy.wordMatchMode, WordMatchMode.mostWords);
  });

  test('במדויק ובמקורב נשלחת ברירת המחדל גם כשנשאר טווח מהמתקדם', () {
    for (final mode in [SearchMode.exact, SearchMode.fuzzy]) {
      expect(
        externalMatchPolicyOf(stateWith(mode)),
        SearchMatchPolicy.standard,
      );
    }
  });

  test('בכל סדר עובר לספק רק כשהוא חל בפועל', () {
    SearchState orderFree(SearchMode mode, {String query = 'ברכת המזון'}) =>
        SearchState(
          searchQuery: query,
          configuration: SearchConfiguration(searchMode: mode, anyOrder: true),
        );
    expect(externalMatchPolicyOf(orderFree(SearchMode.exact)).anyOrder, isTrue);
    expect(
      externalMatchPolicyOf(orderFree(SearchMode.fuzzy)),
      SearchMatchPolicy.standard,
    );
    expect(
      externalMatchPolicyOf(
        orderFree(SearchMode.advanced),
        customSpacing: const {'0-1': '2'},
      ).anyOrder,
      isFalse,
    );
    expect(
      externalMatchPolicyOf(
        orderFree(SearchMode.exact, query: 'ברכת'),
      ).anyOrder,
      isFalse,
    );
  }, skip: !engineReady);
}

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search_feedback/semantic_search_strings.dart';
import 'package:otzaria/semantic_search/models/semantic_result_item.dart';
import 'package:otzaria/tabs/models/semantic_search_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';

import '../test_helpers/memory_cache_provider.dart';

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  const options = SemanticQueryOptions(
    query: 'צדקה',
    facets: ['/הלכה'],
    includeLexical: false,
    groupIdenticalText: false,
  );

  test('נשמרת ומשוחזרת ככרטיסייה סמנטית עם האפשרויות', () {
    final tab = SemanticSearchTab(options: options, isPinned: true);
    addTearDown(tab.dispose);

    final restored = OpenedTab.fromJson(tab.toJson());
    addTearDown(restored.dispose);

    expect(restored, isA<SemanticSearchTab>());
    restored as SemanticSearchTab;
    expect(restored.options, options);
    expect(restored.isPinned, isTrue);
    expect(restored.title, '$kSemanticSearchModeName: צדקה');
  });

  test('שחזור ושכפול של חיפוש מתוך ספר שומרים את הספר והממדים', () {
    const bookFacet = '/הלכה/id:1';
    final tab = SemanticSearchTab(
      options: options.copyWith(facets: ['/הלכה', '/base']),
      lockedBookFacet: bookFacet,
    );
    final restored = OpenedTab.fromJson(tab.toJson()) as SemanticSearchTab;
    final clone = tab.clone();
    for (final candidate in [tab, restored, clone]) {
      addTearDown(candidate.dispose);
      expect(candidate.lockedBookFacet, bookFacet);
      expect(candidate.options.facets, ['/base', bookFacet]);
    }
  });

  test('שכפול נשאר כרטיסייה סמנטית עצמאית', () {
    final tab = SemanticSearchTab(options: options);
    addTearDown(tab.dispose);

    final copy = OpenedTab.from(tab);
    addTearDown(copy.dispose);

    expect(copy, isA<SemanticSearchTab>());
    expect(identical(copy, tab), isFalse);
    expect((copy as SemanticSearchTab).options, options);
  });
}

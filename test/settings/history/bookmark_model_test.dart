import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

void main() {
  test('Bookmark.fromJson handles missing commentators field', () {
    final json = {
      'ref': 'test ref',
      'index': 1,
      'book': {'title': 'Book A', 'type': 'TextBook'},
    };
    final bookmark = Bookmark.fromJson(json);
    expect(bookmark.commentatorsToShow, isEmpty);
  });

  test('Bookmark preserves label in json roundtrip', () {
    final bookmark = Bookmark(
      ref: 'בראשית א',
      index: 0,
      book: Bookmark.fromJson({
        'ref': 'inner',
        'index': 1,
        'book': {'title': 'Book A', 'type': 'TextBook'},
      }).book,
      label: 'בראשית ברא אלהים את',
    );

    final restored = Bookmark.fromJson(bookmark.toJson());

    expect(restored.label, 'בראשית ברא אלהים את');
  });

  test('Bookmark.copyWith with clearLabel resets label to null', () {
    final bookmark = Bookmark(
      ref: 'בראשית א',
      index: 0,
      book: Bookmark.fromJson({
        'ref': 'inner',
        'index': 1,
        'book': {'title': 'Book A', 'type': 'TextBook'},
      }).book,
      label: 'תיאור',
    );

    expect(bookmark.copyWith(label: 'חדש').label, 'חדש');
    expect(bookmark.copyWith(clearLabel: true).label, isNull);
  });

  test('Bookmark preserves search scope facets in json roundtrip', () {
    final bookmark = Bookmark(
      ref: 'query',
      index: 0,
      book: Bookmark.fromJson({
        'ref': 'inner',
        'index': 1,
        'book': {'title': 'Book A', 'type': 'TextBook'},
      }).book,
      isSearch: true,
      searchScopeFacets: const ['/root/a', '/root/b'],
    );

    final json = bookmark.toJson();
    final restored = Bookmark.fromJson(json);

    expect(restored.searchScopeFacets, ['/root/a', '/root/b']);
  });

  test('Bookmark preserves search mode in json roundtrip', () {
    final bookmark = Bookmark(
      ref: 'query',
      index: 0,
      book: Bookmark.fromJson({
        'ref': 'inner',
        'index': 1,
        'book': {'title': 'Book A', 'type': 'TextBook'},
      }).book,
      isSearch: true,
      searchMode: SearchMode.fuzzy,
    );

    final json = bookmark.toJson();
    final restored = Bookmark.fromJson(json);

    expect(restored.searchMode, SearchMode.fuzzy);
  });

  test(
    'search filters survive JSON and copy, including an empty selection',
    () {
      for (final filter in <List<String>?>[
        null,
        [],
        ['/root/a'],
      ]) {
        final json = {
          'ref': 'query',
          'index': 0,
          'book': {'title': 'query', 'type': 'TextBook'},
          'isSearch': true,
          'searchScopeFacets': ['/root'],
          'searchFilterFacets': ?filter,
        };
        final bookmark = Bookmark.fromJson(json);
        final restored = Bookmark.fromJson(bookmark.copyWith().toJson());
        expect(restored.searchScopeFacets, ['/root']);
        expect(restored.searchFilterFacets, filter);
        expect(restored.historyKey, bookmark.historyKey);
        expect(
          restored.toJson().containsKey('searchFilterFacets'),
          filter != null,
        );
      }
    },
  );

  test('Bookmark preserves search distance in json roundtrip', () {
    final bookmark = Bookmark(
      ref: 'query',
      index: 0,
      book: Bookmark.fromJson({
        'ref': 'inner',
        'index': 1,
        'book': {'title': 'Book A', 'type': 'TextBook'},
      }).book,
      isSearch: true,
      distance: 5,
    );

    final json = bookmark.toJson();
    final restored = Bookmark.fromJson(json);

    expect(restored.distance, 5);
  });

  test('Bookmark preserves full search configuration in json roundtrip', () {
    const config = SearchConfiguration(
      distance: 4,
      searchMode: SearchMode.advanced,
      wordMatchMode: WordMatchMode.atLeast,
      wordMatchCount: 3,
      resultGrouping: ResultGroupingMode.sameSection,
      regexEnabled: true,
      caseSensitive: true,
      numResults: 250,
    );

    final bookmark = Bookmark(
      ref: 'query',
      index: 0,
      book: Bookmark.fromJson({
        'ref': 'inner',
        'index': 1,
        'book': {'title': 'Book A', 'type': 'TextBook'},
      }).book,
      isSearch: true,
      searchConfiguration: config.toMap(),
    );

    final restored = Bookmark.fromJson(bookmark.toJson());
    final restoredConfig = SearchConfiguration.fromMap(
      restored.searchConfiguration!,
    );

    expect(restoredConfig.distance, 4);
    expect(restoredConfig.wordMatchMode, WordMatchMode.atLeast);
    expect(restoredConfig.wordMatchCount, 3);
    expect(restoredConfig.resultGrouping, ResultGroupingMode.sameSection);
    expect(restoredConfig.regexEnabled, isTrue);
    expect(restoredConfig.caseSensitive, isTrue);
    expect(restoredConfig.numResults, 250);
  });

  test(
    'search configuration drops its facet copies, also from old entries',
    () {
      const facets = ['/ספרים אישיים/א', '/ספרים אישיים/ב'];
      final old = {
        'ref': 'query',
        'index': 0,
        'book': {'title': 'query', 'type': 'TextBook'},
        'isSearch': true,
        'searchScopeFacets': facets,
        'searchConfiguration': const SearchConfiguration(
          distance: 3,
          currentFacets: facets,
          searchScopeFacets: facets,
        ).toMap(),
      };

      final rewritten = Bookmark.fromJson(old).toJson();
      final config = rewritten['searchConfiguration'] as Map<String, dynamic>;

      expect(config.containsKey('currentFacets'), isFalse);
      expect(config.containsKey('searchScopeFacets'), isFalse);
      expect(config['distance'], 3);
      expect(rewritten['searchScopeFacets'], facets);
      expect(SearchConfiguration.fromMap(config).searchScopeFacets, ['/']);
    },
  );

  test('Bookmark.fromJson treats missing search configuration as null', () {
    final restored = Bookmark.fromJson({
      'ref': 'query',
      'index': 0,
      'book': {'title': 'Book A', 'type': 'TextBook'},
      'isSearch': true,
    });

    expect(restored.searchConfiguration, isNull);
  });

  test('Bookmark.fromJson treats missing distance as null', () {
    final restored = Bookmark.fromJson({
      'ref': 'query',
      'index': 0,
      'book': {'title': 'Book A', 'type': 'TextBook'},
      'isSearch': true,
    });

    expect(restored.distance, isNull);
  });
}

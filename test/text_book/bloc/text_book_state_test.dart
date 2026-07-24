import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

void main() {
  group('TextBookLoaded equality', () {
    test('changes when spacing values change', () {
      final withSpacing = _loadedState(
        spacingValues: const {'0-1': '1'},
      );
      final withoutSpacing = _loadedState();

      expect(withSpacing, isNot(equals(withoutSpacing)));
    });

    test('changes when advanced search options change', () {
      final withOptions = _loadedState(
        searchOptions: const {
          'אמר_0': {'סיומות': true},
        },
      );
      final withoutOptions = _loadedState();

      expect(withOptions, isNot(equals(withoutOptions)));
    });

    test('changes when search mode changes', () {
      final advanced = _loadedState(searchMode: SearchMode.advanced);
      final exact = _loadedState();

      expect(advanced, isNot(equals(exact)));
    });

    test('changes when typo tolerance option changes', () {
      final withTypoTolerance = _loadedState(
        searchOptions: const {
          'אמר_0': {'שגיאות כתיב': true},
        },
      );
      final withoutTypoTolerance = _loadedState(
        searchOptions: const {
          'אמר_0': {'שגיאות כתיב': false},
        },
      );

      expect(withTypoTolerance, isNot(equals(withoutTypoTolerance)));
    });

    test(
      'changes when content version changes even if content length stays same',
      () {
        final older = _loadedState(
          content: const ['שורה א'],
          contentVersion: 1,
        );
        final newer = _loadedState(
          content: const ['שורה ב'],
          contentVersion: 2,
        );

        expect(older, isNot(equals(newer)));
      },
    );

    test('changes when selected indices change', () {
      final single = _loadedState(selectedIndices: const {3});
      final multi = _loadedState(selectedIndices: const {3, 7});

      expect(single, isNot(equals(multi)));
    });

    test('selectedIndices defaults to empty', () {
      expect(_loadedState().selectedIndices, isEmpty);
    });

    test('changes when heCategories is enriched in background', () {
      final beforeEnrich = _loadedState();
      final afterEnrich = _loadedState(heCategories: 'תנ״ך, תורה');

      expect(beforeEnrich, isNot(equals(afterEnrich)));
    });
  });
}

TextBookLoaded _loadedState({
  List<String> content = const ['שורה א'],
  int contentVersion = 0,
  Map<String, Map<String, bool>> searchOptions = const {},
  Map<int, List<String>> alternativeWords = const {},
  Map<String, String> spacingValues = const {},
  SearchMode searchMode = SearchMode.exact,
  Set<int> selectedIndices = const {},
  String? heCategories,
}) {
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה', heCategories: heCategories),
    showLeftPane: false,
    content: content,
    contentVersion: contentVersion,
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    visibleLinks: const [],
    linksByLine: const {},
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0],
    selectedIndices: selectedIndices,
    pinLeftPane: false,
    searchText: 'אמר רבי',
    searchOptions: searchOptions,
    alternativeWords: alternativeWords,
    spacingValues: spacingValues,
    searchMode: searchMode,
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );
}

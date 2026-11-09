import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/content_line_changes.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SearchScope;

void main() {
  test('דלתת תוכן נשמרת בשינוי UI ונמחקת בהחלפת תוכן לא מוכרת', () {
    final changes = ContentLineChanges(
      fromVersion: 1,
      ranges: [(first: 3, last: 5), (first: 1, last: 3)],
    );
    expect(changes.ranges, [(first: 1, last: 5)]);
    final state = _loadedState().copyWith(
      contentVersion: 2,
      contentChanges: changes,
    );
    expect(state.copyWith(fontSize: 30).contentChanges, same(changes));
    expect(state.copyWith(content: ['תוכן חדש']).contentChanges, isNull);
    expect(state.copyWith(contentVersion: 3).contentChanges, isNull);
    expect(state.copyWith(loadedLineFlags: [true]).contentChanges, isNull);
  });

  group('TextBookLoaded equality', () {
    test('maps compare by content, not insertion order', () {
      final left = _loadedState(
        searchOptions: {
          'אמר_0': {'סיומות': true, 'כתיב': false},
          'רבי_1': {'חילוף': true},
        },
        alternativeWords: {
          0: ['אמר', 'ויאמר'],
          1: ['רבי'],
        },
        spacingValues: {'0-1': '2', '1-2': '5'},
      );
      final right = _loadedState(
        searchOptions: {
          'רבי_1': {'חילוף': true},
          'אמר_0': {'כתיב': false, 'סיומות': true},
        },
        alternativeWords: {
          1: ['רבי'],
          0: ['אמר', 'ויאמר'],
        },
        spacingValues: {'1-2': '5', '0-1': '2'},
      );

      expect(left, equals(right));
      expect(left.hashCode, right.hashCode);
    });

    test('alternative word list order remains significant', () {
      final left = _loadedState(
        alternativeWords: const {
          0: ['אמר', 'ויאמר'],
        },
      );
      final right = _loadedState(
        alternativeWords: const {
          0: ['ויאמר', 'אמר'],
        },
      );
      expect(left, isNot(equals(right)));
    });

    test('large search maps compare without sorting thousands of keys', () {
      final names = List.generate(1000, (index) => 'word_$index');
      final optionsA = {
        for (final name in names) name: {'exact': true, 'fuzzy': false},
      };
      final optionsB = {
        for (final name in names.reversed)
          name: {'fuzzy': false, 'exact': true},
      };
      final first = _loadedState(searchOptions: optionsA);
      final second = _loadedState(searchOptions: optionsB);

      expect(first, equals(second));
      expect(first.hashCode, second.hashCode);
    });

    test('TextBookInitial uses the same unordered map comparison', () {
      final book = TextBook(title: 'ספר בדיקה');
      final first = TextBookInitial.named(
        book,
        0,
        false,
        const [],
        searchOptions: {
          'a': {'x': true, 'y': false},
          'b': {'z': true},
        },
        alternativeWords: {
          0: ['one', 'two'],
          1: ['three'],
        },
        spacingValues: {'a': '1', 'b': '2'},
      );
      final reversed = TextBookInitial.named(
        book,
        0,
        false,
        const [],
        searchOptions: {
          'b': {'z': true},
          'a': {'y': false, 'x': true},
        },
        alternativeWords: {
          1: ['three'],
          0: ['one', 'two'],
        },
        spacingValues: {'b': '2', 'a': '1'},
      );
      expect(first, equals(reversed));
      expect(first.hashCode, reversed.hashCode);
    });

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

    test('changes when match policy changes', () {
      // ההשוואה חייבת לזהות את שינוי מדיניות ההתאמה, אחרת חלונית החיפוש
      // לא תריץ חיפוש מחדש כשהמשתמש עובר ל"באותה פסקה".
      final sameParagraph = _loadedState(
        matchPolicy: const SearchMatchPolicy(
          proximityScope: SearchScope.sameParagraph,
        ),
      );
      final wordDistance = _loadedState();

      expect(sameParagraph, isNot(equals(wordDistance)));
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
    test('changes when selected link types change', () {
      final withFilter = _loadedState(selectedLinkTypes: const {'REFERENCE'});
      final noFilter = _loadedState();

      expect(withFilter, isNot(equals(noFilter)));
    });

    test('changes when one link type is swapped for another of same size', () {
      final quotation = _loadedState(selectedLinkTypes: const {'QUOTATION'});
      final related = _loadedState(selectedLinkTypes: const {'RELATED'});

      expect(quotation, isNot(equals(related)));
    });

    test('changes when selected indices change', () {
      final single = _loadedState(selectedIndices: const {3});
      final multi = _loadedState(selectedIndices: const {3, 7});

      expect(single, isNot(equals(multi)));
    });

    test('search result lines compare by content regardless of order', () {
      final a = _loadedState(searchResultLines: {1, 2, 3});
      final b = _loadedState(searchResultLines: {3, 2, 1});

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(_loadedState(searchResultLines: {1, 2, 4}))));
      expect(
        _loadedState(searchResultLines: const {}),
        isNot(equals(_loadedState())),
      );
    });

    test('compares thousands of search result lines in linear time', () {
      // השוואה ריבועית של 40,000 שורות נמשכת שניות ארוכות.
      final lines = List<int>.generate(40000, (i) => i);
      final a = _loadedState(searchResultLines: lines.toSet());
      final b = _loadedState(searchResultLines: lines.reversed.toSet());

      final stopwatch = Stopwatch()..start();
      expect(a == b, isTrue);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('selectedIndices defaults to empty', () {
      expect(_loadedState().selectedIndices, isEmpty);
    });

    test('changes when heCategories is enriched in background', () {
      final beforeEnrich = _loadedState();
      final afterEnrich = _loadedState(heCategories: 'תנ״ך, תורה');

      expect(beforeEnrich, isNot(equals(afterEnrich)));
    });

    test('changes when the Tanach nikud exemption changes', () {
      expect(
        _loadedState(nikudExemptByTanach: true),
        isNot(equals(_loadedState())),
      );
    });

    test('changes when the commentary nikud override changes', () {
      expect(
        _loadedState(commentaryRemoveNikudOverride: false),
        isNot(equals(_loadedState())),
      );
    });
  });

  group('commentaryRemoveNikud', () {
    test('hides nikud in commentaries of a Tanach book showing nikud', () {
      // הבאג: "הצג ניקוד בתנ״ך" הותיר ניקוד גם במפרשי התנ״ך.
      final state = _loadedState(
        removeNikud: false,
        nikudExemptByTanach: true,
      );

      expect(state.removeNikud, isFalse);
      expect(state.commentaryRemoveNikud, isTrue);
    });

    test('keeps the exemption when the toolbar re-shows nikud', () {
      final state = _loadedState(
        removeNikud: false,
        nikudExemptByTanach: true,
      );

      expect(state.copyWith(removeNikud: true).commentaryRemoveNikud, isTrue);
      expect(state.copyWith(removeNikud: false).commentaryRemoveNikud, isTrue);
    });

    test('commentary override does not change the main book', () {
      final state = _loadedState(
        removeNikud: false,
        nikudExemptByTanach: true,
      );

      final showingCommentaries = state.copyWith(
        commentaryRemoveNikudOverride: false,
      );

      expect(showingCommentaries.removeNikud, isFalse);
      expect(showingCommentaries.commentaryRemoveNikud, isFalse);
    });

    test('follows the tab when no exemption applies', () {
      final showing = _loadedState(removeNikud: false);
      final hiding = _loadedState(removeNikud: true);

      expect(showing.commentaryRemoveNikud, isFalse);
      expect(hiding.commentaryRemoveNikud, isTrue);
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
  SearchMatchPolicy matchPolicy = SearchMatchPolicy.standard,
  Set<int> selectedIndices = const {},
  Set<String> selectedLinkTypes = const {},
  Set<int>? searchResultLines,
  String? heCategories,
  bool removeNikud = false,
  bool nikudExemptByTanach = false,
  bool? commentaryRemoveNikudOverride,
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
    selectedLinkTypes: selectedLinkTypes,
    linksByLine: const {},
    tableOfContents: const [],
    removeNikud: removeNikud,
    nikudExemptByTanach: nikudExemptByTanach,
    commentaryRemoveNikudOverride: commentaryRemoveNikudOverride,
    visibleIndices: const [0],
    selectedIndices: selectedIndices,
    pinLeftPane: false,
    searchText: 'אמר רבי',
    searchOptions: searchOptions,
    alternativeWords: alternativeWords,
    spacingValues: spacingValues,
    searchMode: searchMode,
    matchPolicy: matchPolicy,
    searchResultLines: searchResultLines,
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/utils/in_book_search_routing.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SearchScope, WordMatchMode;

import '../../support/search_engine_test_init.dart';

Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  group('canRunAsSimpleSearch', () {
    test('שאילתה ליטרלית בלי תוספות — מסלול פשוט', () {
      expect(
        InBookSearchRouting.canRunAsSimpleSearch(
          searchMode: SearchMode.exact,
          distance: 0,
        ),
        isTrue,
      );
    });

    test('מרווח בין מילים — מסלול המנוע', () {
      // הבאג המקורי: תוצאה מחיפוש "תדע זרעך" במרווח מילים נפתחה בספר
      // כחיפוש מחרוזת רצופה, ולכן חלונית החיפוש הציגה "אין תוצאות".
      expect(
        InBookSearchRouting.canRunAsSimpleSearch(
          searchMode: SearchMode.exact,
          distance: 2,
        ),
        isFalse,
      );
      expect(
        InBookSearchRouting.canRunAsSimpleSearch(
          searchMode: SearchMode.advanced,
          distance: 3,
        ),
        isFalse,
      );
    });

    test('מצב מקורב — מסלול המנוע גם בלי מרווח', () {
      expect(
        InBookSearchRouting.canRunAsSimpleSearch(
          searchMode: SearchMode.fuzzy,
          distance: 0,
        ),
        isFalse,
      );
    });

    test('מצב מתקדם בלי תוספות בכלל — מסלול פשוט', () {
      expect(
        InBookSearchRouting.canRunAsSimpleSearch(
          searchMode: SearchMode.advanced,
          distance: 0,
        ),
        isTrue,
      );
    });

    test('אפשרות פר-מילה דלוקה — מסלול המנוע', () {
      expect(
        InBookSearchRouting.canRunAsSimpleSearch(
          searchMode: SearchMode.advanced,
          distance: 0,
          searchOptions: const {
            'תדע_0': {'ראשי תיבות': true},
          },
        ),
        isFalse,
      );
    });

    test('אפשרויות פר-מילה כבויות בלבד — מסלול פשוט', () {
      expect(
        InBookSearchRouting.canRunAsSimpleSearch(
          searchMode: SearchMode.exact,
          distance: 0,
          searchOptions: const {
            'תדע_0': {'קידומות': false, 'סיומות': false},
          },
        ),
        isTrue,
      );
    });

    test('מילים חלופיות — מסלול המנוע; רשימה ריקה או רווחים — פשוט', () {
      expect(
        InBookSearchRouting.canRunAsSimpleSearch(
          searchMode: SearchMode.exact,
          distance: 0,
          alternativeWords: const {
            0: ['ידע'],
          },
        ),
        isFalse,
      );
      expect(
        InBookSearchRouting.canRunAsSimpleSearch(
          searchMode: SearchMode.exact,
          distance: 0,
          alternativeWords: const {
            0: ['   ', ''],
          },
        ),
        isTrue,
      );
    });

    test('מרווח ידני בין מילים — מסלול המנוע; ערך ריק — פשוט', () {
      expect(
        InBookSearchRouting.canRunAsSimpleSearch(
          searchMode: SearchMode.exact,
          distance: 0,
          spacingValues: const {'תדע_0': '2'},
        ),
        isFalse,
      );
      expect(
        InBookSearchRouting.canRunAsSimpleSearch(
          searchMode: SearchMode.exact,
          distance: 0,
          spacingValues: const {'תדע_0': '  '},
        ),
        isTrue,
      );
    });

    test('טווח קרבה פסקה/כותרת — מסלול המנוע', () {
      for (final scope in [
        SearchScope.sameParagraph,
        SearchScope.sameSection,
      ]) {
        expect(
          InBookSearchRouting.canRunAsSimpleSearch(
            searchMode: SearchMode.advanced,
            distance: 0,
            matchPolicy: SearchMatchPolicy(proximityScope: scope),
          ),
          isFalse,
          reason: 'טווח $scope אינו התאמת מחרוזת רצופה',
        );
      }
    });

    test('התאמה חלקית של מילות השאילתה — מסלול המנוע', () {
      for (final mode in [
        WordMatchMode.anyWord,
        WordMatchMode.mostWords,
        WordMatchMode.atLeast,
      ]) {
        expect(
          InBookSearchRouting.canRunAsSimpleSearch(
            searchMode: SearchMode.advanced,
            distance: 0,
            matchPolicy: SearchMatchPolicy(wordMatchMode: mode),
          ),
          isFalse,
          reason: 'התאמה $mode אינה התאמת מחרוזת רצופה',
        );
      }
    });

    test('בכל סדר במילה אחת — המסלול המקומי', () {
      expect(
        InBookSearchRouting.resolveForReadingTab(
          searchMode: SearchMode.exact,
          distance: 0,
          matchPolicy: const SearchMatchPolicy(anyOrder: true),
          query: 'שלום',
        ),
        const InBookSearchParameters(searchMode: SearchMode.exact, distance: 0),
      );
    }, skip: !engineReady);

    test('בכל סדר — מסלול המנוע', () {
      expect(
        InBookSearchRouting.canRunAsSimpleSearch(
          searchMode: SearchMode.exact,
          distance: 0,
          matchPolicy: const SearchMatchPolicy(anyOrder: true),
        ),
        isFalse,
      );
    });
  });

  group('resolveForReadingTab', () {
    test('שאילתה פשוטה מתנרמלת ל-exact/0 (המסלול המקומי המהיר)', () {
      expect(
        InBookSearchRouting.resolveForReadingTab(
          searchMode: SearchMode.advanced,
          distance: 0,
        ),
        const InBookSearchParameters(
          searchMode: SearchMode.exact,
          distance: 0,
        ),
      );
    });

    test('מרווח בין מילים עובר לטאב הקריאה במלואו', () {
      expect(
        InBookSearchRouting.resolveForReadingTab(
          searchMode: SearchMode.advanced,
          distance: 3,
        ),
        const InBookSearchParameters(
          searchMode: SearchMode.advanced,
          distance: 3,
        ),
      );
    });

    test('מרווח במצב מדויק נשמר — המנוע מנתב אותו למסלול המתקדם', () {
      expect(
        InBookSearchRouting.resolveForReadingTab(
          searchMode: SearchMode.exact,
          distance: 2,
        ),
        const InBookSearchParameters(
          searchMode: SearchMode.exact,
          distance: 2,
        ),
      );
    });

    test('מצב מקורב שומר את מרחק העריכה', () {
      expect(
        InBookSearchRouting.resolveForReadingTab(
          searchMode: SearchMode.fuzzy,
          distance: 1,
        ),
        const InBookSearchParameters(
          searchMode: SearchMode.fuzzy,
          distance: 1,
        ),
      );
    });

    test('אפשרויות/חלופות/מרווחים ידניים שומרים את המצב המקורי', () {
      expect(
        InBookSearchRouting.resolveForReadingTab(
          searchMode: SearchMode.advanced,
          distance: 0,
          alternativeWords: const {
            0: ['ידע'],
          },
        ),
        const InBookSearchParameters(
          searchMode: SearchMode.advanced,
          distance: 0,
        ),
      );
    });

    test('מדיניות ההתאמה עוברת כפי שהיא לטאב הקריאה', () {
      const policy = SearchMatchPolicy(
        proximityScope: SearchScope.sameParagraph,
        wordMatchMode: WordMatchMode.atLeast,
        wordMatchCount: 3,
      );
      expect(
        InBookSearchRouting.resolveForReadingTab(
          searchMode: SearchMode.advanced,
          distance: 0,
          matchPolicy: policy,
        ),
        const InBookSearchParameters(
          searchMode: SearchMode.advanced,
          distance: 0,
          matchPolicy: policy,
        ),
      );
    });

    test('שאילתה פשוטה מאפסת את מדיניות ההתאמה לברירת המחדל', () {
      expect(
        InBookSearchRouting.resolveForReadingTab(
          searchMode: SearchMode.exact,
          distance: 0,
        ).matchPolicy,
        SearchMatchPolicy.standard,
      );
    });

    test('מרחק שלילי מתנרמל לאפס', () {
      expect(
        InBookSearchRouting.resolveForReadingTab(
          searchMode: SearchMode.fuzzy,
          distance: -5,
        ),
        const InBookSearchParameters(
          searchMode: SearchMode.fuzzy,
          distance: 0,
        ),
      );
    });
  });
}

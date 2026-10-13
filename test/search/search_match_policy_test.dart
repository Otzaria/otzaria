import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SearchScope, WordMatchMode;

import '../support/search_engine_test_init.dart';

Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  group('SearchMatchPolicy', () {
    test('ברירת המחדל היא מרווח מילים וכל המילים', () {
      expect(SearchMatchPolicy.standard.isStandard, isTrue);
      expect(
        SearchMatchPolicy.standard.proximityScope,
        SearchScope.wordDistance,
      );
      expect(SearchMatchPolicy.standard.wordMatchMode, WordMatchMode.all);
    });

    test('טווח קרבה שאינו מרווח מילים אינו ברירת מחדל', () {
      expect(
        const SearchMatchPolicy(
          proximityScope: SearchScope.sameSection,
        ).isStandard,
        isFalse,
      );
    });

    test('התאמה חלקית אינה ברירת מחדל', () {
      expect(
        const SearchMatchPolicy(
          wordMatchMode: WordMatchMode.mostWords,
        ).isStandard,
        isFalse,
      );
    });

    test('מספר מילים לבדו אינו הופך את המדיניות ללא-רגילה', () {
      // המונה משמעותי רק במצב "לפחות X מילים", ולכן אינו נבדק ב-isStandard.
      expect(const SearchMatchPolicy(wordMatchCount: 5).isStandard, isTrue);
    });

    test('שוויון לפי ערכים — מאפשר השוואת state בלי רענון מיותר', () {
      const first = SearchMatchPolicy(
        proximityScope: SearchScope.sameParagraph,
        wordMatchMode: WordMatchMode.atLeast,
        wordMatchCount: 3,
      );
      const second = SearchMatchPolicy(
        proximityScope: SearchScope.sameParagraph,
        wordMatchMode: WordMatchMode.atLeast,
        wordMatchCount: 3,
      );
      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first, isNot(const SearchMatchPolicy()));
    });

    test('SearchConfiguration.forInBookSearch נושא את המדיניות לדיאלוג', () {
      // דיאלוג החיפוש המתקדם שנפתח מתוך ספר קורא את הקונפיגורציה הזו;
      // בלי המדיניות הוא היה נפתח בברירות מחדל ומוחק אותה באישור.
      const policy = SearchMatchPolicy(
        proximityScope: SearchScope.sameSection,
        wordMatchMode: WordMatchMode.atLeast,
        wordMatchCount: 3,
      );
      final configuration = SearchConfiguration.forInBookSearch(
        searchMode: SearchMode.advanced,
        distance: 4,
        matchPolicy: policy,
      );

      expect(configuration.searchMode, SearchMode.advanced);
      expect(configuration.distance, 4);
      expect(configuration.matchPolicy, policy);
    });

    test('SearchConfiguration.matchPolicy נגזר משדות הקונפיגורציה', () {
      const configuration = SearchConfiguration(
        proximityScope: SearchScope.sameSection,
        wordMatchMode: WordMatchMode.anyWord,
        wordMatchCount: 4,
      );
      expect(
        configuration.matchPolicy,
        const SearchMatchPolicy(
          proximityScope: SearchScope.sameSection,
          wordMatchMode: WordMatchMode.anyWord,
          wordMatchCount: 4,
        ),
      );
    });

    test('בכל סדר אינו ברירת מחדל ומפנה את ההדגשה מהביטוי הרציף', () {
      const policy = SearchMatchPolicy(anyOrder: true);
      expect(policy.isStandard, isFalse);
      expect(policy.hasStandardWordMatching, isFalse);
      expect(policy, isNot(SearchMatchPolicy.standard));
    });

    test('JSON בלי anyOrder נטען לפי הסדר; עם anyOrder נשמר', () {
      expect(
        SearchMatchPolicy.fromJson(SearchMatchPolicy.standard.toJson()),
        SearchMatchPolicy.standard,
      );
      expect(SearchMatchPolicy.standard.toJson(), isNot(contains('anyOrder')));
      const policy = SearchMatchPolicy(anyOrder: true);
      expect(SearchMatchPolicy.fromJson(policy.toJson()), policy);
    });

    test(
      'appliesAnyOrder: לא במקורב, ובמתקדם רק במרווח מילים עם כל המילים',
      () {
        const exact = SearchConfiguration(
          searchMode: SearchMode.exact,
          anyOrder: true,
          // טווח שנשאר מהמצב המתקדם אינו חל במדויק.
          proximityScope: SearchScope.sameParagraph,
        );
        expect(exact.appliesAnyOrder(), isTrue);
        expect(exact.matchPolicy, const SearchMatchPolicy(anyOrder: true));

        const advanced = SearchConfiguration(anyOrder: true);
        expect(advanced.appliesAnyOrder(), isTrue);
        expect(
          advanced.appliesAnyOrder(customSpacing: const {'0-1': '3'}),
          isFalse,
        );
        expect(
          advanced.copyWith(searchMode: SearchMode.fuzzy).appliesAnyOrder(),
          isFalse,
        );
        expect(
          advanced
              .copyWith(proximityScope: SearchScope.sameSection)
              .appliesAnyOrder(),
          isFalse,
        );
        expect(
          advanced
              .copyWith(wordMatchMode: WordMatchMode.anyWord)
              .appliesAnyOrder(),
          isFalse,
        );
        expect(const SearchConfiguration().appliesAnyOrder(), isFalse);
      },
    );

    test('בשאילתה של מילה אחת "בכל סדר" אינו חל', () {
      const configuration = SearchConfiguration(
        searchMode: SearchMode.exact,
        anyOrder: true,
      );
      expect(configuration.appliesAnyOrder(query: 'ברא אלהים'), isTrue);
      expect(configuration.appliesAnyOrder(query: 'ברא'), isFalse);
      expect(
        configuration.matchPolicyWithSpacing(const {}, query: 'ברא').anyOrder,
        isFalse,
      );
      const policy = SearchMatchPolicy(anyOrder: true);
      expect(policy.forQuery('ברא'), SearchMatchPolicy.standard);
      expect(identical(policy.forQuery('ברא אלהים'), policy), isTrue);
    }, skip: !engineReady);

    test('anyOrder נשמר במפה; מפה ישנה בלי המפתח נטענת לפי הסדר', () {
      const configuration = SearchConfiguration(anyOrder: true);
      expect(SearchConfiguration.fromMap(configuration.toMap()), configuration);
      final legacy = const SearchConfiguration().toMap()..remove('anyOrder');
      expect(SearchConfiguration.fromMap(legacy).anyOrder, isFalse);
    });

    test('forInBookSearch נושא גם את סדר המילים', () {
      final configuration = SearchConfiguration.forInBookSearch(
        searchMode: SearchMode.advanced,
        distance: 2,
        matchPolicy: const SearchMatchPolicy(anyOrder: true),
      );
      expect(configuration.anyOrder, isTrue);
      expect(configuration.matchPolicy.anyOrder, isTrue);
    });
  });
}

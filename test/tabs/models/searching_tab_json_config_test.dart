import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_defaults.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show ResultsOrder, SearchScope;

import '../../helpers/memory_settings_cache.dart';

/// טאב חיפוש נשמר ל-JSON בסגירת התוכנה ומשוחזר בהפעלה הבאה. `sortBy` היה
/// שם מאז ומתמיד ו-`resultGrouping`/`proximityScope` לא — ולכן האיחוד וטווח
/// הקרבה "נשכחו" בכל הפעלה בעוד המיון שרד.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  SearchingTab tabWith(SearchConfiguration configuration) {
    final tab = SearchingTab(
      'חיפוש: בראשית',
      'בראשית',
      initialConfiguration: configuration,
    );
    addTearDown(tab.dispose);
    return tab;
  }

  SearchingTab restore(Map<String, dynamic> json) {
    final tab = SearchingTab.fromJson(json);
    addTearDown(tab.dispose);
    return tab;
  }

  group('שמירת מצב האיחוד ב-JSON של הטאב', () {
    test('toJson כולל את מצב האיחוד', () {
      final tab = tabWith(
        const SearchConfiguration(
          resultGrouping: ResultGroupingMode.sameSection,
        ),
      );

      expect(
        tab.toJson()['resultGrouping'],
        ResultGroupingMode.sameSection.index,
      );
    });

    test('כל מצב איחוד עובר שמירה ושחזור', () {
      for (final mode in ResultGroupingMode.values) {
        final tab = tabWith(SearchConfiguration(resultGrouping: mode));

        final restored = restore(tab.toJson());

        expect(
          restored.searchBloc.state.resultGrouping,
          mode,
          reason: mode.label,
        );
      }
    });

    test('המיון והאיחוד משוחזרים יחד ואינם דורסים זה את זה', () {
      final tab = tabWith(
        const SearchConfiguration(
          sortBy: ResultsOrder.relevance,
          resultGrouping: ResultGroupingMode.identicalText,
        ),
      );

      final restored = restore(tab.toJson());

      expect(restored.searchBloc.state.sortBy, ResultsOrder.relevance);
      expect(
        restored.searchBloc.state.resultGrouping,
        ResultGroupingMode.identicalText,
      );
    });

    test('שאר קונפיגורציית החיפוש שורדת את השחזור', () {
      final tab = tabWith(
        const SearchConfiguration(
          searchMode: SearchMode.exact,
          distance: 4,
          numResults: 300,
          resultGrouping: ResultGroupingMode.sameSection,
          currentFacets: ['/תנך'],
          searchScopeFacets: ['/תנך'],
        ),
      );

      final restored = restore(tab.toJson()).searchBloc.state.configuration;

      expect(restored.resultGrouping, ResultGroupingMode.sameSection);
      expect(restored.searchMode, SearchMode.exact);
      expect(restored.distance, 4);
      expect(restored.numResults, 300);
      expect(restored.currentFacets, ['/תנך']);
    });
  });

  group('שמירת טווח הקרבה ב-JSON של הטאב', () {
    test('toJson כולל את טווח הקרבה', () {
      final tab = tabWith(
        const SearchConfiguration(proximityScope: SearchScope.sameSection),
      );

      expect(tab.toJson()['proximityScope'], SearchScope.sameSection.index);
    });

    test('כל טווח קרבה עובר שמירה ושחזור', () {
      for (final scope in SearchScope.values) {
        final tab = tabWith(SearchConfiguration(proximityScope: scope));

        final restored = restore(tab.toJson());

        expect(
          restored.searchBloc.state.proximityScope,
          scope,
          reason: scope.name,
        );
      }
    });

    test('טווח הקרבה, המרווח והמיון משוחזרים יחד', () {
      final tab = tabWith(
        const SearchConfiguration(
          searchMode: SearchMode.advanced,
          proximityScope: SearchScope.sameParagraph,
          distance: 5,
          sortBy: ResultsOrder.relevance,
          resultGrouping: ResultGroupingMode.sameSection,
        ),
      );

      final restored = restore(tab.toJson()).searchBloc.state.configuration;

      expect(restored.proximityScope, SearchScope.sameParagraph);
      expect(restored.distance, 5);
      expect(restored.sortBy, ResultsOrder.relevance);
      expect(restored.resultGrouping, ResultGroupingMode.sameSection);
    });

    test('טאב שנשמר בגרסה קודמת (בלי המפתח) נפתח במרווח מילים', () {
      final saved = tabWith(
        const SearchConfiguration(proximityScope: SearchScope.sameSection),
      ).toJson()..remove('proximityScope');

      expect(
        restore(saved).searchBloc.state.proximityScope,
        SearchScope.wordDistance,
      );
    });

    test('אינדקס פגום נופל למרווח מילים', () {
      final saved = tabWith(const SearchConfiguration()).toJson();

      for (final broken in [
        SearchScope.values.length,
        99,
        -1,
        'sameSection',
        null,
      ]) {
        expect(
          restore({
            ...saved,
            'proximityScope': broken,
          }).searchBloc.state.proximityScope,
          SearchScope.wordDistance,
          reason: '$broken',
        );
      }
    });
  });

  group('שמירת סדר המילים ב-JSON של הטאב (issue #2006)', () {
    test('בכל סדר עובר שמירה ושחזור', () {
      final saved = tabWith(
        const SearchConfiguration(distance: 2, anyOrder: true),
      ).toJson();
      expect(saved['anyOrder'], isTrue);
      final restored = restore(saved).searchBloc.state;
      expect(restored.anyOrder, isTrue);
      expect(restored.distance, 2);
    });

    test('טאב שנשמר בגרסה קודמת (בלי המפתח) נפתח לפי הסדר', () {
      final saved = tabWith(
        const SearchConfiguration(anyOrder: true),
      ).toJson()..remove('anyOrder');
      expect(restore(saved).searchBloc.state.anyOrder, isFalse);
    });
  });

  group('שחזור טאב אינו נחטף על ידי ההעדפה השמורה', () {
    test('טאב שנשמר עם "ללא איחוד" נפתח בלי איחוד גם כשההעדפה מאחדת', () {
      final saved = tabWith(const SearchConfiguration()).toJson();
      SearchDefaults.saveResultGroupingDefault(
        ResultGroupingMode.identicalText,
      );
      SearchDefaults.saveSortOrderDefault(ResultsOrder.relevance);

      final restored = restore(saved);

      expect(restored.searchBloc.state.resultGrouping, ResultGroupingMode.none);
      expect(restored.searchBloc.state.sortBy, ResultsOrder.catalogue);
    });

    test('טאב שנשמר עם איחוד נפתח מאוחד גם כשההעדפה "ללא איחוד"', () {
      final saved = tabWith(
        const SearchConfiguration(
          resultGrouping: ResultGroupingMode.sameSection,
        ),
      ).toJson();
      SearchDefaults.saveResultGroupingDefault(ResultGroupingMode.none);

      final restored = restore(saved);

      expect(
        restored.searchBloc.state.resultGrouping,
        ResultGroupingMode.sameSection,
      );
    });
  });

  group('JSON חסר או פגום', () {
    test('טאב שנשמר בגרסה קודמת (בלי המפתח) נפתח בלי איחוד', () {
      final saved = tabWith(
        const SearchConfiguration(
          resultGrouping: ResultGroupingMode.identicalText,
        ),
      ).toJson()..remove('resultGrouping');
      SearchDefaults.saveResultGroupingDefault(ResultGroupingMode.sameSection);

      final restored = restore(saved);

      expect(restored.searchBloc.state.resultGrouping, ResultGroupingMode.none);
    });

    test('אינדקס מחוץ לטווח נופל ל"ללא איחוד"', () {
      final saved = tabWith(const SearchConfiguration()).toJson();

      for (final broken in [ResultGroupingMode.values.length, 99, -1]) {
        expect(
          restore({
            ...saved,
            'resultGrouping': broken,
          }).searchBloc.state.resultGrouping,
          ResultGroupingMode.none,
          reason: '$broken',
        );
      }
    });

    test('ערך שאינו מספר נופל ל"ללא איחוד"', () {
      final saved = tabWith(const SearchConfiguration()).toJson();

      expect(
        restore({
          ...saved,
          'resultGrouping': 'sameSection',
        }).searchBloc.state.resultGrouping,
        ResultGroupingMode.none,
      );
      expect(
        restore({
          ...saved,
          'resultGrouping': null,
        }).searchBloc.state.resultGrouping,
        ResultGroupingMode.none,
      );
    });
  });
}

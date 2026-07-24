import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../../support/search_engine_test_init.dart';

Future<void> main() async {
  // הקוד הנבדק קורא ל-sanitizeQuery/splitQueryWords שמאצילים למנוע ה-Rust;
  // הטסטים המסומנים מדולגים כשאין build נייטיבי זמין.
  final engineReady = await tryInitSearchEngine();

  WidgetsFlutterBinding.ensureInitialized();

  group('SearchingTab persistence', () {
    test('toJson/fromJson משחזר distance מיד ב-state של ה-Bloc, '
        'בלי תלות בעיבוד events', () {
      final source = SearchingTab(
        'חיפוש: צדיק גאולה תפילה',
        'צדיק גאולה תפילה',
        initialConfiguration: const SearchConfiguration(distance: 10),
      );
      addTearDown(source.dispose);

      final json = source.toJson();
      final restored = SearchingTab.fromJson(json);
      addTearDown(restored.dispose);

      // הבדיקה הקריטית: ה-state חייב לכלול distance=10 *סינכרונית* אחרי
      // fromJson. אם הערך מועבר רק דרך event, ה-state כאן עוד יהיה 0
      // כי ה-event לא עיבד עדיין — ואז ה-UI שמפעיל UpdateSearchQuery
      // ב-initState יגרום לחיפוש בלי distance.
      expect(restored.searchBloc.state.configuration.distance, 10);
      expect(restored.queryController.text, 'צדיק גאולה תפילה');
    });

    test('toJson/fromJson משחזר searchMode סינכרונית', () {
      final source = SearchingTab(
        'חיפוש',
        'שלום',
        initialConfiguration: const SearchConfiguration(
          searchMode: SearchMode.fuzzy,
        ),
      );
      addTearDown(source.dispose);

      final restored = SearchingTab.fromJson(source.toJson());
      addTearDown(restored.dispose);

      expect(
        restored.searchBloc.state.configuration.searchMode,
        SearchMode.fuzzy,
      );
    });

    test('toJson/fromJson משחזר searchOptions פר-מילה', () {
      final source = SearchingTab('חיפוש', 'צדיק גאולה');
      addTearDown(source.dispose);
      source.searchOptions['צדיק_0'] = {'חלק ממילה': true};
      source.searchOptions['גאולה_1'] = {'כתיב מלא/חסר': true};

      final restored = SearchingTab.fromJson(source.toJson());
      addTearDown(restored.dispose);

      expect(restored.searchOptions['צדיק_0']?['חלק ממילה'], true);
      expect(restored.searchOptions['גאולה_1']?['כתיב מלא/חסר'], true);
    });

    test(
      'fromJson מנקה state פר-מילה שנשמר על פיצול-מילים ישן',
      () {
        // מפתחות שנבנו כשחוקי הפיצול היו אחרים (רמב"ם כשתי מילים) אינם
        // תואמים את הפיצול הנוכחי — שחזורם היה מזליג אפשרויות/מרווחים
        // למילה הלא-נכונה, ולכן הם נזרקים כמקשה אחת.
        final source = SearchingTab('חיפוש', 'רמב"ם משה');
        addTearDown(source.dispose);
        source.searchOptions['רמב_0'] = {'חלק ממילה': true};
        source.searchOptions['ם_1'] = {'כתיב מלא/חסר': true};
        source.alternativeWords[2] = ['רבינו'];
        source.spacingValues['1-2'] = '3';

        final restored = SearchingTab.fromJson(source.toJson());
        addTearDown(restored.dispose);

        expect(restored.searchOptions, isEmpty);
        expect(restored.alternativeWords, isEmpty);
        expect(restored.spacingValues, isEmpty);
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );

    test('toJson/fromJson משחזר alternativeWords ו-spacingValues', () {
      final source = SearchingTab('חיפוש', 'א ב');
      addTearDown(source.dispose);
      source.alternativeWords[0] = ['חלופה'];
      source.spacingValues['0-1'] = '3';

      final restored = SearchingTab.fromJson(source.toJson());
      addTearDown(restored.dispose);

      expect(restored.alternativeWords[0], ['חלופה']);
      expect(restored.spacingValues['0-1'], '3');
    });

    test(
      'toJson/fromJson משחזר globalSearchOptions ו-useGlobalSearchOptions',
      () {
        final source = SearchingTab('חיפוש', 'שלום');
        addTearDown(source.dispose);
        source.globalSearchOptions['חלק ממילה'] = true;
        source.useGlobalSearchOptions.value = false;

        final restored = SearchingTab.fromJson(source.toJson());
        addTearDown(restored.dispose);

        expect(restored.globalSearchOptions['חלק ממילה'], true);
        expect(restored.useGlobalSearchOptions.value, false);
      },
    );

    test('toJson/fromJson משחזר sortBy ו-facets', () {
      final source = SearchingTab(
        'חיפוש',
        'א',
        initialConfiguration: const SearchConfiguration(
          sortBy: ResultsOrder.relevance,
          currentFacets: ['/חסידות'],
          searchScopeFacets: ['/חסידות'],
        ),
      );
      addTearDown(source.dispose);

      final restored = SearchingTab.fromJson(source.toJson());
      addTearDown(restored.dispose);

      expect(
        restored.searchBloc.state.configuration.sortBy,
        ResultsOrder.relevance,
      );
      expect(
        restored.searchBloc.state.configuration.currentFacets,
        ['/חסידות'],
      );
      expect(
        restored.searchBloc.state.configuration.searchScopeFacets,
        ['/חסידות'],
      );
    });

    test('toJson/fromJson משחזר דגלי regex', () {
      final source = SearchingTab(
        'חיפוש',
        'א',
        initialConfiguration: const SearchConfiguration(
          regexEnabled: true,
          caseSensitive: true,
          multiline: true,
          dotAll: true,
          unicode: false,
        ),
      );
      addTearDown(source.dispose);

      final restored = SearchingTab.fromJson(source.toJson());
      addTearDown(restored.dispose);

      final config = restored.searchBloc.state.configuration;
      expect(config.regexEnabled, true);
      expect(config.caseSensitive, true);
      expect(config.multiline, true);
      expect(config.dotAll, true);
      expect(config.unicode, false);
    });
  });

  group('SearchingTab title updates', () {
    // רגרסיה מפורום 884: כותרת הכרטיסייה לא התעדכנה כששאילתת החיפוש
    // השתנתה, כי דבר לא האזין ל-titleNotifier ולא קרא ל-updateTitleFromAppliedQuery.
    test(
      'updateTitleFromAppliedQuery מעדכן title ו-titleNotifier לפי השאילתה',
      () {
        final tab = SearchingTab('חיפוש', null);
        addTearDown(tab.dispose);

        tab.updateTitleFromAppliedQuery('צדיק גאולה');

        expect(tab.title, 'חיפוש: צדיק גאולה');
        expect(tab.titleNotifier.value, 'חיפוש: צדיק גאולה');
      },
    );

    test(
      'updateTitleFromAppliedQuery עם שאילתה ריקה מחזיר לכותרת ברירת המחדל',
      () {
        final tab = SearchingTab('חיפוש: ישן', 'ישן');
        addTearDown(tab.dispose);

        tab.updateTitleFromAppliedQuery('   ');

        expect(tab.title, 'חיפוש');
        expect(tab.titleNotifier.value, 'חיפוש');
      },
    );

    test('titleNotifier מאותחל עם הכותרת ההתחלתית של הטאב', () {
      final tab = SearchingTab('חיפוש: התחלתי', 'התחלתי');
      addTearDown(tab.dispose);

      expect(tab.titleNotifier.value, 'חיפוש: התחלתי');
    });
  });

  group('SearchingTab.clone', () {
    test('clone מטמיע את כל ה-configuration סינכרונית, '
        'בלי תלות בעיבוד events', () {
      final source = SearchingTab(
        'חיפוש',
        'צדיק',
        initialConfiguration: const SearchConfiguration(
          distance: 7,
          searchMode: SearchMode.fuzzy,
          numResults: 250,
          sortBy: ResultsOrder.relevance,
          currentFacets: ['/חסידות'],
          searchScopeFacets: ['/חסידות'],
        ),
      );
      addTearDown(source.dispose);
      source.searchOptions['צדיק_0'] = {'חלק ממילה': true};

      final cloned = SearchingTab.clone(source);
      addTearDown(cloned.dispose);

      // הבדיקה הקריטית: כל הערכים חייבים להיות ב-state כבר עכשיו (סינכרונית).
      // אם clone יחזור לדפוס של "שלח event אחרי בנייה", state יישאר ב-default
      // וה-UI יפעיל UpdateSearchQuery לפני שה-events יעבדו.
      final config = cloned.searchBloc.state.configuration;
      expect(config.distance, 7);
      expect(config.searchMode, SearchMode.fuzzy);
      expect(config.numResults, 250);
      expect(config.sortBy, ResultsOrder.relevance);
      expect(config.searchScopeFacets, ['/חסידות']);
      expect(cloned.searchOptions['צדיק_0']?['חלק ממילה'], true);
      expect(cloned.queryController.text, 'צדיק');
    });
  });
}

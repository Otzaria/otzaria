import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/in_book_search_settings.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_defaults.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SearchScope, WordMatchMode;

import '../../helpers/memory_settings_cache.dart';

/// חיפוש מקישור otzaria:// נפתח בלי הדיאלוג — ועדיין חייב לכבד את ברירות
/// המחדל של המשתמש (קידומות, כתיב מלא/חסר, מרווח ומצב), כמו חיפוש מהממשק.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  SearchingTab newSearch({SearchMode? mode}) {
    final tab = SearchingTab.newSearch('חיפוש: בראשית', 'בראשית', mode: mode);
    addTearDown(tab.dispose);
    return tab;
  }

  group('חיפוש חדש לפי ברירות המחדל (issue #2322)', () {
    test('בלי מצב מפורש — מצב, מרווח ואפשרויות מברירת המחדל', () {
      SearchDefaults.saveModeDefault(SearchMode.exact);
      SearchDefaults.saveDistanceDefault(3);
      SearchDefaults.saveExactDefaults({
        'קידומות דקדוקיות': true,
        'כתיב מלא/חסר': true,
      });

      final tab = newSearch();
      final config = tab.searchBloc.state.configuration;

      expect(tab.queryController.text, 'בראשית');
      expect(config.searchMode, SearchMode.exact);
      expect(config.distance, 3);
      expect(tab.globalSearchOptions['קידומות דקדוקיות'], isTrue);
      expect(tab.globalSearchOptions['כתיב מלא/חסר'], isTrue);
    });

    test('מצב מפורש בקישור גובר, והאפשרויות הן של אותו מצב', () {
      SearchDefaults.saveModeDefault(SearchMode.exact);
      SearchDefaults.saveDefaults({'כתיב מלא/חסר': true});

      final tab = newSearch(mode: SearchMode.advanced);

      expect(
        tab.searchBloc.state.configuration.searchMode,
        SearchMode.advanced,
      );
      expect(tab.globalSearchOptions['כתיב מלא/חסר'], isTrue);
    });
  });

  group('טווח הקרבה וסדר המילים כברירת מחדל (issue #2006)', () {
    const savedPolicy = SearchMatchPolicy(
      proximityScope: SearchScope.sameParagraph,
      wordMatchMode: WordMatchMode.atLeast,
      wordMatchCount: 3,
    );

    tearDown(() {
      // שכבת הסשן סטטית — מחזירים אותה לברירת המחדל עבור הטסטים הבאים.
      SearchDefaults.saveMatchPolicyDefault(SearchMatchPolicy.standard);
      SearchDefaults.saveAnyOrderDefault(false);
    });

    test('בלי שמירה: מרווח בין מילים, כל המילים ולפי הסדר', () {
      expect(
        SearchDefaults.loadMatchPolicyDefault(),
        SearchMatchPolicy.standard,
      );
      expect(SearchDefaults.loadAnyOrderDefault(), isFalse);
      final config = newSearch(
        mode: SearchMode.advanced,
      ).searchBloc.state.configuration;
      expect(config.proximityScope, SearchScope.wordDistance);
      expect(config.wordMatchMode, WordMatchMode.all);
      expect(config.anyOrder, isFalse);
    });

    test('חיפוש חדש נפתח בטווח ובסדר השמורים', () {
      SearchDefaults.saveMatchPolicyDefault(savedPolicy);
      SearchDefaults.saveAnyOrderDefault(true);

      final config = newSearch(
        mode: SearchMode.advanced,
      ).searchBloc.state.configuration;
      expect(config.proximityScope, SearchScope.sameParagraph);
      expect(config.wordMatchMode, WordMatchMode.atLeast);
      expect(config.wordMatchCount, 3);
      expect(config.anyOrder, isTrue);
    });

    test('הערכים נשמרים בשם ה-enum ונקראים בהפעלה הבאה', () {
      SearchDefaults.saveMatchPolicyDefault(savedPolicy);
      expect(
        Settings.getValue<String>('key-search-default-proximity-scope'),
        'sameParagraph',
      );
      expect(
        Settings.getValue<String>('key-search-default-word-match-mode'),
        'atLeast',
      );
      expect(SearchDefaults.loadMatchPolicyDefault(), savedPolicy);
    });

    test('שכבת הסשן גוברת על השמור עד הפעלה מחדש', () {
      SearchDefaults.rememberSessionMatchPolicy(savedPolicy);
      SearchDefaults.rememberSessionAnyOrder(true);
      expect(
        SearchDefaults.loadMatchPolicyDefault(),
        SearchMatchPolicy.standard,
      );
      expect(SearchDefaults.initialMatchPolicyForNewSearch(), savedPolicy);
      expect(SearchDefaults.initialAnyOrderForNewSearch(), isTrue);
    });

    test('חיפוש בספר מתחיל מברירת המחדל; טווח חל רק במתקדם', () {
      SearchDefaults.saveMatchPolicyDefault(savedPolicy);
      SearchDefaults.saveAnyOrderDefault(true);

      SearchDefaults.saveModeDefault(SearchMode.advanced);
      // טווח פסקה מבטל את "בכל סדר" — המילים בכל סדר ממילא.
      expect(
        InBookSearchSettings.savedDefaults().matchPolicy,
        savedPolicy,
      );

      SearchDefaults.saveModeDefault(SearchMode.exact);
      expect(
        InBookSearchSettings.savedDefaults().matchPolicy,
        const SearchMatchPolicy(wordMatchCount: 3, anyOrder: true),
      );
    });
  });
}

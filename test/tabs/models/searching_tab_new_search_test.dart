import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_defaults.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';

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
}

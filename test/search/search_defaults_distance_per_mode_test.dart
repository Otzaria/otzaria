import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/in_book_search_settings.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_defaults.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';

import '../helpers/memory_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    for (final mode in [SearchMode.exact, SearchMode.advanced]) {
      SearchDefaults.rememberSessionDistance(0, mode);
    }
  });

  int newSearchDistance(SearchMode mode) {
    final tab = SearchingTab.newSearch('חיפוש', 'בראשית', mode: mode);
    addTearDown(tab.dispose);
    return tab.searchBloc.state.distance;
  }

  group('מרווח ברירת מחדל נפרד לכל מצב (issue #5758)', () {
    test('שמירה במצב אחד אינה דורסת את המצב השני', () {
      SearchDefaults.saveDistanceDefault(3, mode: SearchMode.advanced);
      SearchDefaults.saveDistanceDefault(0, mode: SearchMode.exact);

      expect(SearchDefaults.loadDistanceDefault(SearchMode.advanced), 3);
      expect(SearchDefaults.loadDistanceDefault(SearchMode.exact), 0);
      expect(newSearchDistance(SearchMode.advanced), 3);
      expect(newSearchDistance(SearchMode.exact), 0);
    });

    test('מרווח הסשן נשמר לכל מצב בנפרד', () {
      SearchDefaults.rememberSessionDistance(4, SearchMode.advanced);

      expect(
        SearchDefaults.initialDistanceForNewSearch(SearchMode.advanced),
        4,
      );
      expect(SearchDefaults.initialDistanceForNewSearch(SearchMode.exact), 0);
    });

    test('ערך שנשמר לפני ההפרדה חל על שני המצבים', () {
      Settings.setValue<int>('key-search-default-distance', 2);

      expect(SearchDefaults.loadDistanceDefault(SearchMode.exact), 2);
      expect(SearchDefaults.loadDistanceDefault(SearchMode.advanced), 2);

      SearchDefaults.saveDistanceDefault(5, mode: SearchMode.advanced);
      expect(SearchDefaults.loadDistanceDefault(SearchMode.exact), 2);
      expect(Settings.getValue<int>('key-search-default-distance'), 2);
    });

    test('חיפוש בתוך ספר לוקח את המרווח של מצב ברירת המחדל', () {
      SearchDefaults.saveDistanceDefault(3, mode: SearchMode.advanced);
      SearchDefaults.saveModeDefault(SearchMode.advanced);
      expect(InBookSearchSettings.savedDefaults().distance, 3);

      SearchDefaults.saveModeDefault(SearchMode.exact);
      expect(InBookSearchSettings.savedDefaults().distance, 0);
    });

    test('מקורב אינו מושפע — נפתח במרחק העריכה המרבי', () {
      SearchDefaults.saveDistanceDefault(3, mode: SearchMode.advanced);
      SearchDefaults.saveDistanceDefault(3, mode: SearchMode.exact);

      expect(newSearchDistance(SearchMode.fuzzy), kMaxFuzzyDistance);
    });
  });
}

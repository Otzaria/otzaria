import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/models/bookmark_sort_mode.dart';

import '../helpers/memory_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  test('ברירת המחדל היא category כשאין ערך שמור', () {
    expect(loadBookmarkSortMode(), BookmarkSortMode.category);
  });

  test('save ו-load עוברים סיבוב מלא', () async {
    await saveBookmarkSortMode(BookmarkSortMode.dateAdded);
    expect(loadBookmarkSortMode(), BookmarkSortMode.dateAdded);

    await saveBookmarkSortMode(BookmarkSortMode.category);
    expect(loadBookmarkSortMode(), BookmarkSortMode.category);
  });

  test('ערך שמור לא תקין נופל חזרה ל-category', () async {
    await Settings.setValue<String>('key-bookmark-sort-mode', 'garbage');
    expect(loadBookmarkSortMode(), BookmarkSortMode.category);
  });
}

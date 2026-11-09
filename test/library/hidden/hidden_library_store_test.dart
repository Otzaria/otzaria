import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const store = HiddenLibraryStore();
  late MemoryCacheProvider cache;

  setUp(() async {
    cache = MemoryCacheProvider();
    await Settings.init(cacheProvider: cache);
  });

  test('שמירה וטעינה של הסתרות (issue #1448)', () async {
    await store.save(
      const HiddenLibrarySelection(
        bookKeys: {'o__10__שמות'},
        categoryPaths: {'/תנ"ך/תורה'},
      ),
    );

    final loaded = store.load();

    expect(loaded.bookKeys, {'o__10__שמות'});
    expect(loaded.categoryPaths, {'/תנ"ך/תורה'});
  });

  test('אין הסתרות שמורות — נטען ריק (issue #1448)', () {
    expect(store.load().isEmpty, isTrue);
  });

  test('ערך פגום אינו מסתיר דבר (issue #1448)', () async {
    await Settings.setValue<String>(
      HiddenLibraryStore.bookKeysSetting,
      'not json at all',
    );

    expect(
      store.load().bookKeys,
      isEmpty,
      reason: 'ברירת המחדל הבטוחה היא להציג, לא להעלים בשקט',
    );
  });

  test('ערכים ריקים מסוננים (issue #1448)', () async {
    await Settings.setValue<String>(
      HiddenLibraryStore.categoryPathsSetting,
      '["", "/תנ\\"ך", 7]',
    );

    expect(store.load().categoryPaths, {'/תנ"ך'});
  });

  test('כשל בכתיבה השנייה מחזיר את הבחירה שנשמרה בפועל', () async {
    await Settings.init(cacheProvider: _FailingCategoryCacheProvider());
    final result = await store.saveAndRead(
      const HiddenLibrarySelection(
        bookKeys: {'o__10__שמות'},
        categoryPaths: {'/תורה'},
      ),
    );

    expect(result.error, isA<StateError>());
    expect(result.actual.bookKeys, {'o__10__שמות'});
    expect(result.actual.categoryPaths, isEmpty);
  });

  test('סימון ממתין נשמר לפני הבחירה ושורד אתחול הגדרות', () async {
    await store.beginVisibilityIndexUpdate();
    await store.save(const HiddenLibrarySelection(bookKeys: {'book'}));
    await Settings.init(cacheProvider: cache);

    expect(store.load().bookKeys, {'book'});
    expect(store.hasPendingVisibilityIndex, isTrue);
    await store.clearPendingVisibilityIndex(store.visibilityRevision);
  });
}

class _FailingCategoryCacheProvider extends MemoryCacheProvider {
  @override
  Future<void> setObject<T>(String key, T? value) async {
    if (key == HiddenLibraryStore.categoryPathsSetting) {
      throw StateError('second write failed');
    }
    await super.setObject<T>(key, value);
  }
}

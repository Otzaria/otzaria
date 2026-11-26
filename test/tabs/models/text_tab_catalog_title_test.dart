import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _Provider implements LibraryProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _seedCatalog(BookSource source) {
  final provider = _Provider();
  final key = BookCompositeKey.create(
    title: 'שו״ת באר מרדכי',
    categoryId: 7,
    source: source,
  );
  LibraryProviderManager.instance.seedMappingsForTesting(
    mapping: {key: provider},
    providers: [provider],
    bookIds: {key: 7458},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  tearDown(LibraryProviderManager.instance.resetForTesting);

  test('טאב מספר שנשמר בכותרת בלי גרשיים נבנה בכותרת הקטלוגית (#2766)', () {
    _seedCatalog(BookSource.official);
    final tab = TextBookTab(
      book: TextBook(title: 'שות באר מרדכי', categoryId: 7),
      index: 0,
    );
    addTearDown(tab.dispose);

    expect(tab.book.title, 'שו״ת באר מרדכי');
    expect(tab.title, 'שו״ת באר מרדכי');
    expect(tab.toJson()['book']['title'], 'שו״ת באר מרדכי');
    expect((tab.bloc.state as TextBookInitial).book.title, 'שו״ת באר מרדכי');
  });

  test('כותרת קטלוגית ממקור אחר אינה מחליפה את הכותרת', () {
    _seedCatalog(BookSource.user);
    final tab = TextBookTab(
      book: TextBook(title: 'שות באר מרדכי', categoryId: 7),
      index: 0,
    );
    addTearDown(tab.dispose);

    expect(tab.book.title, 'שות באר מרדכי');
  });
}

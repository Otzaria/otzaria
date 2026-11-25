import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/models/book_source.dart';

class _Provider implements LibraryProvider {
  final requestedTitles = <String>[];

  @override
  bool get isInitialized => true;

  @override
  Future<String?> getBookText(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async {
    requestedTitles.add(title);
    return 'טקסט';
  }

  @override
  Future<Set<String>> getAvailableBookTitles() async => {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BookCompositeKey _key(String title, int categoryId) =>
    BookCompositeKey.create(title: title, categoryId: categoryId);

void main() {
  final manager = LibraryProviderManager.instance;

  tearDown(manager.resetForTesting);

  group('כותרת שנשמרה בלי גרשיים (#2766)', () {
    test('כותרת ישנה נפתרת רק לספר הרשמי המאומת', () async {
      final provider = _Provider();
      final key = _key('שו״ת באר מרדכי', 7);
      manager.seedMappingsForTesting(
        mapping: {key: provider},
        providers: [provider],
        bookIds: {key: 7458},
      );

      expect(manager.getProviderForBook('שות באר מרדכי'), same(provider));
      expect(await manager.getBookText('שות באר מרדכי'), 'טקסט');
      expect(provider.requestedTitles, ['שו״ת באר מרדכי']);
      expect(await manager.getBookText('שות  באר מרדכי'), isNull);
      expect(
        manager.catalogTitleFor('שות באר מרדכי', source: BookSource.user),
        isNull,
      );
      expect(
        manager.catalogTitleFor(
          'שות באר מרדכי',
          source: BookSource.official,
          bookId: 123,
        ),
        isNull,
      );
      expect(
        manager.catalogTitleFor(
          'שות באר מרדכי',
          source: BookSource.official,
          bookId: 7458,
        ),
        'שו״ת באר מרדכי',
      );
    });

    test('התאמה מדויקת גוברת על התאמה בלי גרשיים', () {
      final quoted = _Provider();
      final plain = _Provider();
      final quotedKey = _key('שו״ת באר מרדכי', 1);
      manager.seedMappingsForTesting(
        mapping: {quotedKey: quoted, _key('שות באר מרדכי', 2): plain},
        bookIds: {quotedKey: 7458},
        providers: [quoted, plain],
      );

      expect(manager.getProviderForBook('שות באר מרדכי'), same(plain));
      expect(manager.getProviderForBook('שו״ת באר מרדכי'), same(quoted));
    });

    test('כמה כותרות שמתנרמלות לאותה מחרוזת — לא מנחשים', () {
      final first = _Provider();
      final second = _Provider();
      manager.seedMappingsForTesting(
        mapping: {
          _key('שו״ת דברי חיים', 1): first,
          _key('שו"ת דברי חיים', 2): second,
        },
        providers: [first, second],
      );

      expect(manager.getProviderForBook('שות דברי חיים'), isNull);
    });
  });
}

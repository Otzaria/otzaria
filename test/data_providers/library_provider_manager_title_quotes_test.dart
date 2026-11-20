import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/models/book_source.dart';

class _Provider implements LibraryProvider {
  final requestedTitles = <String>[];

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BookCompositeKey _key(String title, int categoryId) =>
    BookCompositeKey.create(title: title, categoryId: categoryId);

void main() {
  final manager = LibraryProviderManager.instance;

  tearDown(manager.resetForTesting);

  group('כותרת שנשמרה בלי גרשיים (#2766)', () {
    test('כותרת ישנה נפתרת לספר המתוקן', () {
      final provider = _Provider();
      manager.seedMappingsForTesting(
        mapping: {_key('שו״ת באר מרדכי', 7): provider},
        providers: [provider],
      );

      expect(manager.getProviderForBook('שות באר מרדכי'), same(provider));
      expect(
        manager.getProviderForBook('שו"ת באר מרדכי', categoryId: 7),
        same(provider),
      );
    });

    test('הספק מקבל את הכותרת הקטלוגית ולא את הכותרת השמורה', () async {
      final provider = _Provider();
      manager.seedMappingsForTesting(
        mapping: {_key('שו״ת באר מרדכי', 7): provider},
        providers: [provider],
      );

      expect(await manager.getBookText('שות  באר מרדכי'), 'טקסט');
      expect(provider.requestedTitles, ['שו״ת באר מרדכי']);
    });

    test('catalogTitleFor מתאים רק כותרת מאותו מקור', () {
      final provider = _Provider();
      manager.seedMappingsForTesting(
        mapping: {
          BookCompositeKey.create(
            title: 'שו״ת קיו',
            categoryId: 1,
            source: BookSource.user,
          ): provider,
          _key('שות קיו', 2): provider,
          _key('שו״ת באר', 3): provider,
        },
        providers: [provider],
      );

      expect(
        manager.catalogTitleFor('שות קיו', source: BookSource.user),
        'שו״ת קיו',
      );
      expect(
        manager.catalogTitleFor('שות קיו', source: BookSource.official),
        isNull,
      );
      expect(
        manager.catalogTitleFor('שות באר', source: BookSource.user),
        isNull,
      );
    });

    test('התאמה מדויקת גוברת על התאמה בלי גרשיים', () {
      final quoted = _Provider();
      final plain = _Provider();
      manager.seedMappingsForTesting(
        mapping: {_key('שו״ת חכם', 1): quoted, _key('שות חכם', 2): plain},
        providers: [quoted, plain],
      );

      expect(manager.getProviderForBook('שות חכם'), same(plain));
      expect(manager.getProviderForBook('שו״ת חכם'), same(quoted));
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

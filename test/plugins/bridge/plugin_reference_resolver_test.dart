import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/plugins/bridge/plugin_reference_resolver.dart';

FindRefRepository _buildRepository() => FindRefRepository(
  isReferenceBooksCacheLoaded: () => true,
  warmUpReferenceBooksCache: () async {},
  searchReferenceBooks: (_, {limit = 50}) => const [],
  getTocEntriesForReference: (_, _, {queryTokens}) async => const [],
  getAllUserBooks: () async => [
    (
      id: 99,
      title: 'ספר אישי',
      filePath: null,
      fileType: 'txt',
      orderIndex: 1.0,
      folderTitles: const ['מחברות'],
    ),
  ],
  getUserBookTocEntries: (_, _, {queryTokens}) async => const [
    {
      'reference': 'ספר אישי פרק ראשון',
      'segment': 12,
      'level': 2,
      'dbLineId': 77,
    },
  ],
);

void main() {
  group('buildPluginReferenceResolver', () {
    test('כולל ספר אישי גם כשהשאילתה היא רק כותרת הספר', () async {
      final repository = _buildRepository();
      addTearDown(repository.dispose);

      final hits = await buildPluginReferenceResolver(repository)('ספר אישי');

      expect(hits, hasLength(1));
      expect(hits.single, (
        title: 'ספר אישי',
        index: 0,
        isPdf: false,
        bookId: 99,
        reference: 'ספר אישי',
        bookPath: 'מחברות',
        isSourceLine: false,
        source: BookSource.user,
      ));
    });

    test('מעביר את תוצאת ה-TOC של ספר אישי בלי לאבד שדות bridge', () async {
      final repository = _buildRepository();
      addTearDown(repository.dispose);

      final hits = await buildPluginReferenceResolver(
        repository,
      )('ספר אישי פרק ראשון');

      expect(hits, hasLength(1));
      expect(hits.single.reference, 'ספר אישי פרק ראשון');
      expect(hits.single.index, 12);
      expect(hits.single.bookId, 99);
      expect(hits.single.bookPath, 'מחברות');
      expect(hits.single.source, BookSource.user);
    });

    test('הכללת ספרים אישיים אינה התנהגות ברירת המחדל של המנוע', () async {
      final repository = _buildRepository();
      addTearDown(repository.dispose);

      final hits = await repository.findRefs('ספר אישי');

      expect(hits, isEmpty);
    });

    test('שתי פתירות מקבילות של אותו תוסף אינן מבטלות זו את זו', () async {
      final repository = _buildRepository();
      addTearDown(repository.dispose);
      final resolve = buildPluginReferenceResolver(repository);

      final results = await Future.wait([
        resolve('ספר אישי פרק ראשון'),
        resolve('ספר אישי'),
      ]);

      expect(results[0].single.index, 12);
      expect(results[1].single.reference, 'ספר אישי');
    });

    test('איתור רגיל עדיין מבטל את הקודם לו', () async {
      final repository = _buildRepository();
      addTearDown(repository.dispose);

      final first = repository.findRefs('ספר אישי', includePersonalBooks: true);
      final second = repository.findRefs(
        'ספר אישי',
        includePersonalBooks: true,
      );

      await expectLater(first, throwsA(isA<FindRefQueryCancelled>()));
      expect(await second, hasLength(1));
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/utils/bookmark_search_aliases.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/utils/category_query_parser.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/widgets/lists/list_search_match.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../helpers/seforim_fixture_db.dart';

class _MockDataRepository extends Mock implements DataRepository {}

/// אותו כינוי נגזר ("פיה"מ סוכה") מזהה את אותו ספר בכל הצרכנים — גם כשהספר
/// ממסד מצורף שאין בו טבלת `book_acronym`, וגם כשהוא ספר אישי.
const _slug = 'lib-a';
const _bookId = SeforimFixtureIds.rashiId;
const _title = 'רמב"ם על משנה סוכה';
const _query = 'פיה"מ סוכה';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AttachedLibraryRegistry previousRegistry;
  late AttachedLibraryRegistry registry;
  final source = BookSource.attached(_slug);
  final book = TextBook(id: _bookId, title: _title, source: source);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria_book_aliases');
    previousRegistry = AttachedLibraryRegistry.instance;
    registry = AttachedLibraryRegistry(idleTimeout: null);
    AttachedLibraryRegistry.instance = registry;
    AcronymsCache.instance.clear();

    final path = SeforimFixtureDb.create(tempDir, SeforimFixtureVariant.full);
    final db = sqlite3.sqlite3.open(path);
    db.execute('UPDATE book SET title = ? WHERE id = ?', [_title, _bookId]);
    db.execute('DROP TABLE book_acronym');
    db.close();
    registry.update([
      AttachedLibrary(
        slug: _slug,
        displayName: 'Lib A',
        path: path,
        addedAt: DateTime(2026),
      ),
    ]);
    await AcronymsCache.instance.warmUpAttached();
  });

  tearDown(() async {
    await registry.closeAll();
    AttachedLibraryRegistry.instance = previousRegistry;
    AcronymsCache.instance.clear();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('איתור מקורות', () async {
    final repo = FindRefRepository(
      dataRepository: _MockDataRepository(),
      isReferenceBooksCacheLoaded: () => true,
      warmUpReferenceBooksCache: () async {},
      searchReferenceBooks: (query, {int limit = 50}) => const [],
      getTocEntriesForReference: (id, title, {queryTokens}) async => const [],
      getAllUserBooks: () async => const [],
    );
    final results = [
      for (final r in await repo.findRefs(_query, includePersonalBooks: true))
        if (r.source == source) r.bookId,
    ];
    expect(results, isNotEmpty);
    expect(results.first, _bookId);
  });

  test('חיפוש הכותרות בספרייה', () {
    expect(AcronymsCache.instance.attachedAcronymsOf(_slug), isEmpty);
    final entry = buildBookSearchEntry(
      0,
      book,
      acronymsFor: AcronymsCache.instance.acronymsFor,
      eraOrderForId: (_, _) => 5,
    );
    final matches = PreparedBookSearchIndex([entry]).search(
      const BookSearchQuery(
        queryWords: ['פיהמ', 'סוכה'],
        topics: [],
        sortByRatio: true,
        normalizedQuery: 'פיהמ סוכה',
      ),
    );
    expect(matches.indices, [0]);
    expect(matches.kinds.single & BookMatchKind.acronym.bit, isNonZero);
  });

  test('צמצום @שם בחיפוש', () {
    final library = Library(
      categories: [
        Category(
          title: 'ספרייה',
          description: '',
          shortDescription: '',
          order: 0,
          subCategories: const [],
          books: [book],
          parent: null,
        ),
      ],
    );
    final parsed = parseCategoryQuery('מילה@$_query', library);
    expect(parsed.facets, [
      FacetHelper.buildBookFacet(FacetHelper.resolveCategoryPath(book), book),
    ]);
  });

  for (final listBook in [
    book,
    TextBook(title: _title, source: BookSource.user),
    TextBook(id: _bookId, title: _title, source: BookSource.user),
  ]) {
    test(
      'חיפוש ברשימות ההיסטוריה והסימניות (${listBook.source}, id=${listBook.id})',
      () {
        final aliases = bookmarkSearchAliases(
          Bookmark(ref: '$_title א', book: listBook, index: 0),
        );
        final key = ListSearchKey('$_title א', bookTitle: _title)
          ..setAliases(aliases);
        expect(aliases, contains('פיהמ סוכה'));
        expect(listSearchRank(ListSearchQuery(_query), key), isNotNull);
      },
    );
  }
}

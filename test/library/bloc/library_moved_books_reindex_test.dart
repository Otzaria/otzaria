import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../support/search_engine_test_init.dart';

class _Files extends Fake implements FileSystemData {
  _Files(this.next);

  final Library next;

  @override
  String libraryPath = '.';

  @override
  Future<Library> getLibrary() async => next;
}

class _ReadyIndex extends Fake implements TantivyDataProvider {
  @override
  Future<bool> reopenIndex({bool force = false}) async => true;
}

class _EmptyHiddenStore extends HiddenLibraryStore {
  const _EmptyHiddenStore();

  @override
  HiddenLibrarySelection load() => const HiddenLibrarySelection();
}

/// בונה ספרייה שבה כל ספר יושב בשרשרת הקטגוריות שלו.
Library _libraryOf(Map<List<String>, List<Book Function(Category)>> tree) {
  final library = Library(categories: []);
  for (final entry in tree.entries) {
    Category parent = library;
    for (final title in entry.key) {
      final child = Category(
        title: title,
        description: '',
        shortDescription: '',
        order: 0,
        subCategories: [],
        books: [],
        parent: parent,
      );
      parent.subCategories.add(child);
      parent = child;
    }
    for (final build in entry.value) {
      parent.books.add(build(parent));
    }
  }
  return library;
}

TextBook _userBook(Category category) => TextBook(
  id: 5,
  title: 'אנציקלופדיה תלמודית אות מ',
  source: BookSource.user,
  category: category,
);

TextBook _officialBook(Category category) =>
    TextBook(id: 9, title: 'משנה ברורה', category: category);

Future<void> main() async {
  final nativeAvailable = await tryInitSearchEngine();
  TestWidgetsFlutterBinding.ensureInitialized();

  late FileSystemData previousFiles;
  late TantivyDataProvider previousIndex;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    previousFiles = FileSystemData.instance;
    previousIndex = TantivyDataProvider.instance;
    TantivyDataProvider.instance = _ReadyIndex();
  });

  tearDown(() {
    FileSystemData.instance = previousFiles;
    TantivyDataProvider.instance = previousIndex;
  });

  Future<List<Book>?> refreshBetween(Library before, Library after) async {
    final files = _Files(after);
    FileSystemData.instance = files;
    final repository = DataRepository(fileSystemData: files);
    repository.library = Future.value(before);
    await repository.library;
    final bloc = LibraryBloc(
      hiddenStore: const _EmptyHiddenStore(),
      repository: repository,
    );
    addTearDown(bloc.close);
    final done = bloc.stream.firstWhere(
      (state) => state.completedRefreshRequestIds?.contains(1) ?? false,
    );
    bloc.add(const RefreshLibrary(requestIds: {1}));
    return (await done).changedBooksToIndex;
  }

  group('רענון שמעביר ספר לקטגוריה אחרת (issue #1977)', () {
    test(
      'מיזוג ספרים אישיים לעץ — הספר שעבר מאונדקס מחדש (issue #1977)',
      () async {
        final before = _libraryOf({
          ['ספרים אישיים', 'ספריה', 'מילונים וספרי יעץ', 'אנציקלופדיות']: [
            _userBook,
          ],
          ['הלכה']: [_officialBook],
        });
        final after = _libraryOf({
          ['מילונים וספרי יעץ', 'אנציקלופדיות']: [_userBook],
          ['הלכה']: [_officialBook],
        });

        final changed = await refreshBetween(before, after);

        expect(changed?.map((b) => b.title), ['אנציקלופדיה תלמודית אות מ']);
        expect(
          changed!.single.category!.path,
          '/מילונים וספרי יעץ/אנציקלופדיות',
        );
      },
    );

    test(
      'מיזוג אישי מעדכן את הטווח הקטלוגי ומשאיר חיפוש חוצה שורות בתוך הספר',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'moved_book_index_',
        );
        final engine = await SearchEngine.newInstance(path: directory.path);
        final provider = _NativeIndex(engine);
        addTearDown(() async {
          provider.isIndexing.dispose();
          engine.dispose();
          await directory.delete(recursive: true);
        });
        final indexer = _MemoryTextRepository(provider);
        TextBook earlyBook(Category category) =>
            TextBook(id: 1, title: 'ספר מוקדם', category: category);
        TextBook attachedBook(Category category) => TextBook(
          id: 5,
          title: 'ספר מצורף',
          category: category,
          source: BookSource.attached('reference'),
        );
        final before = _libraryOf({
          ['תנ"ך']: [earlyBook],
          ['הלכה']: [_officialBook],
          ['ספרים אישיים']: [_userBook],
          ['מצורף']: [attachedBook],
        });
        final after = _libraryOf({
          ['תנ"ך']: [earlyBook],
          ['מדרש']: [_userBook],
          ['הלכה']: [_officialBook],
          ['מצורף']: [attachedBook],
        });
        Future<List<SearchResult>> search(
          String query, [
          List<String> facets = const [],
        ]) => engine.searchExact(
          query: query,
          facets: facets,
          limit: 10,
          offset: 0,
          order: ResultsOrder.catalogue,
          matchNikud: false,
          matchTaamim: false,
        );

        final initial = await indexer.indexBooks(
          before.getIndexableBooks(),
          before,
          onProgress: (_, _) {},
        );
        expect(initial.isClean, isTrue);
        final originalIds = {
          for (final hit in await search('שלום')) hit.filePath: hit.id,
        };
        expect(
          originalIds.keys,
          unorderedEquals(['id:1', 'id:9', 'uid:5', 'db:reference:5']),
        );
        expect((await search('שלום עולם')).map((r) => r.filePath), ['uid:5']);
        expect(await search('שלום', ['/מדרש']), isEmpty);

        final changed = await refreshBetween(before, after);
        expect(
          changed?.map(IndexingRepository.catalogueOrderKey),
          unorderedEquals(['uid:5', 'id:9']),
        );
        final result = await indexer.reindexChangedBooks(
          changed!,
          after,
          onProgress: (_, _) {},
        );
        expect(result.isClean, isTrue);
        expect(result.indexedBooks, 2);
        final hits = await search('שלום');
        expect(hits, hasLength(4));
        expect(hits.map((hit) => hit.id).toSet(), hasLength(4));
        final currentOrder = IndexingRepository.buildCatalogueOrderResolver(
          after,
        );
        for (final book in after.getIndexableBooks()) {
          final key = IndexingRepository.catalogueOrderKey(book);
          final hit = hits.singleWhere((hit) => hit.filePath == key);
          expect(
            hit.id,
            IndexingRepository.buildCatalogueDocumentId(
              catalogueOrder: currentOrder.orderFor(key),
              ordinal: 0,
            ),
          );
        }
        for (final key in ['id:1', 'db:reference:5']) {
          expect(
            hits.singleWhere((hit) => hit.filePath == key).id,
            originalIds[key],
          );
        }
        for (final hit in hits) {
          expect(
            (await engine.getDocumentById(id: hit.id))?.filePath,
            hit.filePath,
          );
        }
        expect((await search('שלום עולם')).map((r) => r.filePath), ['uid:5']);
        expect((await search('שלום', ['/מדרש'])).map((r) => r.filePath), [
          'uid:5',
        ]);
        expect(await search('שלום', ['/ספרים אישיים']), isEmpty);
        expect(await refreshBetween(after, after), isNull);
        final reversed = await refreshBetween(after, before);
        expect(
          reversed?.map(IndexingRepository.catalogueOrderKey),
          unorderedEquals(['uid:5', 'id:9']),
        );
        final reverseResult = await indexer.reindexChangedBooks(
          reversed!,
          before,
          onProgress: (_, _) {},
        );
        expect(reverseResult.isClean, isTrue);
        expect(reverseResult.indexedBooks, 2);
        expect({
          for (final hit in await search('שלום')) hit.filePath: hit.id,
        }, originalIds);
        expect((await search('שלום עולם')).map((r) => r.filePath), ['uid:5']);
        expect(
          (await search('שלום', ['/ספרים אישיים'])).map((r) => r.filePath),
          ['uid:5'],
        );
        expect(await search('שלום', ['/מדרש']), isEmpty);
      },
      skip: nativeAvailable ? false : searchEngineSkipReason,
    );

    test('רענון שלא הזיז ספרים — אין אינדוקס מחדש (issue #1977)', () async {
      Library build() => _libraryOf({
        ['מילונים וספרי יעץ', 'אנציקלופדיות']: [_userBook],
        ['הלכה']: [_officialBook],
      });

      expect(await refreshBetween(build(), build()), isNull);
    });
  });
}

class _NativeIndex extends Fake implements TantivyDataProvider {
  _NativeIndex(this.value);

  final SearchEngine value;
  @override
  final indexedFilePaths = <String>{};
  @override
  final isIndexing = ValueNotifier(false);
  @override
  bool get requiresManualReindex => false;
  @override
  String? activeIndexPath;
  @override
  bool get isTempFallback => false;
  @override
  bool ensureCatalogueOrderStamp() => true;
  @override
  Future<SearchEngine> get engine async => value;
  @override
  Future<bool> reopenIndex({bool force = false}) async {
    indexedFilePaths
      ..clear()
      ..addAll(await value.getIndexedFilePaths());
    return true;
  }
}

class _MemoryTextRepository extends IndexingRepository {
  _MemoryTextRepository(super.provider)
    : super(hiddenStore: const _EmptyHiddenStore());

  @override
  Future<
    ({
      Uint8List? bytes,
      String? text,
      int? libraryDbBookId,
      Uint32List? dataUriLines,
    })
  >
  loadTextBookSource(TextBook book) async => (
    bytes: null,
    text: book.source.isUser ? 'שלום\nעולם אישי' : 'שלום\nאחר רשמי',
    libraryDbBookId: null,
    dataUriLines: null,
  );
}

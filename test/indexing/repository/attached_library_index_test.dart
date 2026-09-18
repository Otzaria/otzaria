import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

const _slug = 'lib-a';
final _attached = BookSource.attached(_slug);

void main() {
  group('מפתחות האינדקס של ספר ממסד מצורף', () {
    test('מפתח db: גם כשהמסד מצהיר על externalLibraryId', () {
      final book = TextBook(
        id: 7,
        title: 'Book A',
        source: _attached,
        externalLibraryId: 'official-ext',
      );
      expect(IndexingRepository.catalogueOrderKey(book), 'db:$_slug:7');
      expect(IndexingRepository.buildIndexedBookFilePath(book), 'db:$_slug:7');
    });

    test('PDF ממסד מצורף ממופתח לפי id, זהה למסך החיפוש ב-PDF', () {
      final book = PdfBook(
        id: 3,
        title: 'Pdf A',
        path: '/drive/lib/a.pdf',
        source: _attached,
      );
      expect(IndexingRepository.buildIndexedBookFilePath(book), 'db:$_slug:3');
      expect(
        IndexingRepository.indexedPdfFilePath(
          externalLibraryId: null,
          filePath: book.path,
          source: _attached,
          bookId: 3,
        ),
        'db:$_slug:3',
      );
    });

    test('ספר ממסד מצורף מאונדקס', () {
      expect(
        IndexingRepository.isIndexableBook(
          TextBook(id: 1, title: 'Book A', source: _attached),
        ),
        isTrue,
      );
    });

    test('attachedSlugOfKey', () {
      expect(IndexingRepository.attachedSlugOfKey('db:a:b:12'), 'a:b');
      expect(IndexingRepository.attachedSlugOfKey('db:x:1'), 'x');
      expect(IndexingRepository.attachedSlugOfKey('uid:1'), isNull);
      expect(IndexingRepository.attachedSlugOfKey('db::1'), isNull);
    });
  });

  group('סדר הקטלוג עם מסד מצורף', () {
    test('צירוף מסד — גם ממוזג לקטגוריה רשמית — אינו מזיז ספרים קיימים', () {
      final before = _library();
      final orderBefore = IndexingRepository.buildCatalogueOrderResolver(
        before,
      );
      final keysBefore = before
          .getIndexableBooks()
          .map(IndexingRepository.catalogueOrderKey)
          .toList();

      final after = _library(withAttached: true);
      final orderAfter = IndexingRepository.buildCatalogueOrderResolver(after);

      for (final key in keysBefore) {
        expect(
          orderAfter.orderFor(key),
          orderBefore.orderFor(key),
          reason: key,
        );
      }
      final maxExisting = keysBefore
          .map(orderAfter.orderFor)
          .reduce((a, b) => a > b ? a : b);
      expect(orderAfter.orderFor('db:$_slug:1'), greaterThan(maxExisting));
      expect(orderAfter.orderFor('db:$_slug:2'), greaterThan(maxExisting));
    });

    test('ניתוק המסד מחזיר את הסדר הקודם בדיוק', () {
      final order = IndexingRepository.buildCatalogueOrderResolver(_library());
      final reattached = IndexingRepository.buildCatalogueOrderResolver(
        _library(withAttached: true),
      );
      for (final key in ['id:1', 'id:2', 'uid:1', 'uid:9']) {
        expect(reattached.orderFor(key), order.orderFor(key), reason: key);
      }
    });
  });

  group('dropOrphanedIndexEntries — מפתחות db:', () {
    Future<Set<String>> run({
      required List<AttachedLibrary> libraries,
      bool attachedInTree = true,
    }) async {
      final engine = _Engine();
      final provider = _Provider(engine);
      final library = _library(withAttached: attachedInTree);
      provider.indexedFilePaths.addAll({
        'db:$_slug:1', // בעץ
        'db:$_slug:99', // נמחק מהמסד
        'db:gone:5', // מסד שהוסר מהרשימה
      });
      await IndexingRepository(provider).dropOrphanedIndexEntries(
        library,
        customFolders: const [],
        attachedLibraries: libraries,
      );
      return engine.removed.toSet();
    }

    test('מסד שהוסר — המפתחות שלו נמחקים', () async {
      final removed = await run(libraries: [_lib()]);
      expect(removed, contains('db:gone:5'));
      expect(removed, isNot(contains('db:$_slug:1')));
    });

    test('ספר שנמחק ממסד זמין שנטען לעץ — נמחק', () async {
      expect(await run(libraries: [_lib()]), contains('db:$_slug:99'));
    });

    test('מסד לא-זמין — המפתחות נשמרים', () async {
      final removed = await run(
        libraries: [_lib(status: AttachedLibraryStatus.unreachable)],
        attachedInTree: false,
      );
      expect(removed, {'db:gone:5'});
    });

    test('מסד מוסתר — המפתחות נשמרים', () async {
      final removed = await run(
        libraries: [_lib(hidden: true)],
        attachedInTree: false,
      );
      expect(removed, {'db:gone:5'});
    });

    test('מסד זמין שהקטלוג שלו לא נטען — המפתחות נשמרים', () async {
      final removed = await run(libraries: [_lib()], attachedInTree: false);
      expect(removed, {'db:gone:5'});
    });
  });
}

AttachedLibrary _lib({
  AttachedLibraryStatus status = AttachedLibraryStatus.ok,
  bool hidden = false,
}) => AttachedLibrary(
  slug: _slug,
  displayName: 'Lib A',
  path: '/drive/lib-a.db',
  status: status,
  hidden: hidden,
  addedAt: DateTime(2026),
);

Library _library({bool withAttached = false}) {
  final library = Library(categories: []);
  Category category(String title, int order) => Category(
    title: title,
    description: '',
    shortDescription: '',
    order: order,
    subCategories: [],
    books: [],
    parent: library,
  );
  final first = category('Cat A', 1);
  final second = category('Cat B', 2);
  library.subCategories.addAll([first, second]);
  first.books.addAll([
    TextBook(id: 1, title: 'Official A', order: 1, category: first),
    TextBook(id: 2, title: 'Official B', order: 3, category: first),
  ]);
  second.books.add(
    TextBook(
      id: 1,
      title: 'User A',
      order: 1,
      category: second,
      source: BookSource.user,
    ),
  );
  if (withAttached) {
    // ממוזג לקטגוריה רשמית, בין שני ספרים רשמיים.
    first.books.add(
      TextBook(
        id: 1,
        title: 'Attached A',
        order: 2,
        category: first,
        source: _attached,
      ),
    );
    second.books.add(
      TextBook(
        id: 2,
        title: 'Attached B',
        order: 0,
        category: second,
        source: _attached,
      ),
    );
  }
  library.offTreeBooks = [
    TextBook(id: 9, title: 'Version A', source: BookSource.user),
  ];
  return library;
}

class _Engine implements SearchEngine {
  final List<String> removed = [];

  @override
  Future<void> deleteDocumentsByFilePaths({
    required List<String> filePaths,
  }) async => removed.addAll(filePaths);

  @override
  Future<void> commit() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: $invocation');
}

class _Provider implements TantivyDataProvider {
  _Provider(this._engine);

  final _Engine _engine;

  @override
  final Set<String> indexedFilePaths = {};

  @override
  final ValueNotifier<bool> isIndexing = ValueNotifier<bool>(false);

  @override
  Future<SearchEngine> get engine async => _engine;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: $invocation');
}

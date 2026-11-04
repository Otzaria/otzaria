import 'package:otzaria/data/book_identity.dart';
import 'dart:math';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/indexing/models/index_update_mode.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/search/utils/search_catalogue_order_helper.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../../test_helpers/memory_cache_provider.dart';

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
      expect(BookIdentity.keyOf(book), 'db:$_slug:7');
      expect(BookIdentity.indexedFilePath(book), 'db:$_slug:7');
    });

    test('PDF ממסד מצורף ממופתח לפי id, זהה למסך החיפוש ב-PDF', () {
      final book = PdfBook(
        id: 3,
        title: 'Pdf A',
        path: '/drive/lib/a.pdf',
        source: _attached,
      );
      expect(BookIdentity.indexedFilePath(book), 'db:$_slug:3');
      expect(
        BookIdentity.indexedPdfFilePath(
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
      expect(BookIdentity.attachedSlugOfKey('db:a:b:12'), 'a:b');
      expect(BookIdentity.attachedSlugOfKey('db:x:1'), 'x');
      expect(BookIdentity.attachedSlugOfKey('uid:1'), isNull);
      expect(BookIdentity.attachedSlugOfKey('db::1'), isNull);
    });
  });

  group('מיפוי הסדר עם מסד מצורף', () {
    Future<Map<String, int>> orderOf(Library library) async => {
      for (final entry in await IndexingRepository.buildBookOrder(library))
        entry.filePath: entry.catalogueOrder,
    };

    test(
      'צירוף מסד — גם ממוזג לקטגוריה רשמית — אינו מזיז ספרים קיימים',
      () async {
        final before = await orderOf(_library());
        final after = await orderOf(_library(withAttached: true));

        for (final MapEntry(:key, :value) in before.entries) {
          expect(after[key], value, reason: key);
        }
        final officialMax = [after['id:1']!, after['id:2']!].reduce(max);
        expect(after['db:$_slug:1'], greaterThan(officialMax));
        expect(after['db:$_slug:2'], greaterThan(officialMax));
        // ספרים אישיים אחרי הספרייה והמסדים המצורפים.
        expect(after['uid:1'], greaterThan(after['db:$_slug:2']!));
      },
    );

    test(
      'המיפוי כולל ספרים אישיים, רשמיים ומצורפים, כל מפתח פעם אחת',
      () async {
        final library = _library(withAttached: true);
        final entries = await IndexingRepository.buildBookOrder(library);
        final keys = entries.map((entry) => entry.filePath).toList();

        expect(keys.toSet(), hasLength(keys.length));
        expect(
          keys.toSet(),
          library.getIndexableBooks().map(BookIdentity.indexedFilePath).toSet(),
        );
      },
    );

    test('הסדר זהה לזה שנצרב במזהים הצפופים הישנים', () async {
      final library = _library(withAttached: true);
      final category = library.subCategories.first;
      final extra = [
        PdfBook(title: 'סרוק', path: r'C:\pdfs\a.pdf', category: category),
        PdfBook(
          title: 'סרוק חיצוני',
          path: r'C:\pdfs\b.pdf',
          externalLibraryId: 'hb:7',
          category: category,
        ),
        TextBook(
          title: 'חיצוני',
          externalLibraryId: 'hb:8',
          category: category,
        ),
        TextBook(
          title: 'קובץ',
          filePath: r'C:\books\a.txt',
          source: BookSource.user,
          category: category,
        ),
      ];
      category.books.addAll(extra);

      // הסמנטיקה הישנה: מקום ברצף, וספר אישי בטווח משלו אחרי כל הספרייה.
      final positions = SearchCatalogueOrderHelper.buildKeyOrderMap<String>(
        library,
        keyOf: (book) => BookIdentity.keyOf(book as Book),
      );
      int oldOrder(Book book) {
        final key = BookIdentity.keyOf(book);
        final personalId = key.startsWith('uid:')
            ? int.tryParse(key.substring(4))
            : null;
        return personalId != null ? (1 << 23) + personalId : positions[key]!;
      }

      final mapping = {
        for (final entry in await IndexingRepository.buildBookOrder(library))
          entry.filePath: entry,
      };
      final indexable = library.getIndexableBooks();
      expect(mapping, hasLength(indexable.length));
      for (final book in indexable) {
        final entry = mapping[BookIdentity.indexedFilePath(book)];
        expect(entry, isNotNull, reason: book.title);
        expect(entry!.catalogueOrder, oldOrder(book), reason: book.title);
        expect(
          entry.generationOrder,
          IndexingRepository.chronologicalOrderForBook(book),
          reason: book.title,
        );
      }
    });

    test('טעינת ספרייה מבטלת את הסדר שהחיפוש בספר משווה לפיו', () async {
      await Settings.init(cacheProvider: MemoryCacheProvider());
      final previous = DataRepository.instance.cachedLibraryFutureForTesting;
      addTearDown(() {
        if (previous != null) {
          DataRepository.instance.library = previous;
        } else {
          DataRepository.instance.invalidateLibraryCache();
        }
        IndexingRepository.invalidateBookOrder();
      });
      DataRepository.instance.library = Future.value(_library());
      IndexingRepository.invalidateBookOrder();
      expect(
        await IndexingRepository.bookOrderRanks(),
        isNot(contains('db:$_slug:1')),
      );

      DataRepository.instance.library = Future.value(
        _library(withAttached: true),
      );
      IndexingRepository.invalidateBookOrder();
      final ranks = await IndexingRepository.bookOrderRanks();
      expect(ranks, contains('db:$_slug:1'));
      expect(ranks['uid:1'], greaterThan(ranks['db:$_slug:2']!));
    });

    test('אותו עץ נבנה פעם אחת עד הטעינה הבאה', () async {
      final library = _library();
      IndexingRepository.invalidateBookOrder();
      final first = await IndexingRepository.buildBookOrder(library);
      expect(await IndexingRepository.buildBookOrder(library), same(first));
      IndexingRepository.invalidateBookOrder();
      expect(
        await IndexingRepository.buildBookOrder(library),
        isNot(same(first)),
      );
    });
  });

  group('dropOrphanedIndexEntries — מפתחות db:', () {
    Future<Set<String>> run({
      required List<AttachedLibrary> libraries,
      bool attachedInTree = true,
      IndexUpdateMode mode = IndexUpdateMode.all,
    }) async {
      final engine = _Engine();
      final provider = _Provider(engine);
      final library = _library(withAttached: attachedInTree);
      provider.indexedFilePaths.addAll({
        'db:$_slug:1', // בעץ
        'db:$_slug:99', // נמחק מהמסד
        'db:gone:5', // מסד שהוסר מהרשימה
        'id:1',
        'id:99', // ספר רשמי שעדיין לא נטען
        'ext:official',
      });
      await IndexingRepository(
        provider,
        indexUpdateMode: () => mode,
      ).dropOrphanedIndexEntries(
        library,
        customFolders: const [],
        attachedLibraries: libraries,
      );
      expect(
        provider.indexedFilePaths,
        containsAll({'id:1', 'id:99', 'ext:official'}),
      );
      return engine.removed.toSet();
    }

    for (final (name, library, inTree) in [
      ('זמין', _lib(), true),
      ('מוסתר', _lib(hidden: true), false),
      ('לא נגיש', _lib(status: AttachedLibraryStatus.unreachable), false),
    ]) {
      test('בלי ספרים אישיים: מסד $name מוסר מהאינדקס', () async {
        expect(
          await run(
            libraries: [library],
            attachedInTree: inTree,
            mode: IndexUpdateMode.libraryOnly,
          ),
          {'db:$_slug:1', 'db:$_slug:99', 'db:gone:5'},
        );
      });
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

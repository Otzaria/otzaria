import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/indexing/services/indexing_isolate_service.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';

void main() {
  group('IndexingRepository.shouldSkipManualReindexCheck', () {
    test('מחזיר true עבור ספרייה ריקה - מונע דיאלוג איפוס בלי ספרים', () {
      expect(
        IndexingRepository.shouldSkipManualReindexCheck(
          Library(categories: []),
        ),
        isTrue,
      );
    });

    test('מחזיר true עבור ספרייה עם קטגוריות ריקות', () {
      final library = Library(categories: []);
      library.subCategories.add(
        Category(
          title: 'תנ"ך',
          description: '',
          shortDescription: '',
          order: 1,
          subCategories: [],
          books: [],
          parent: library,
        ),
      );
      expect(
        IndexingRepository.shouldSkipManualReindexCheck(library),
        isTrue,
      );
    });

    test('מחזיר false עבור ספרייה עם ספר אחד', () {
      final library = _buildLibrary(bavliBooks: const [('שבת', 1)]);
      expect(
        IndexingRepository.shouldSkipManualReindexCheck(library),
        isFalse,
      );
    });
  });

  group('IndexingRepository.shouldResetBeforeFullReindex', () {
    test('מחזיר true כשמתחילים בנייה מחדש מעל אינדקס קיים', () {
      final shouldReset = IndexingRepository.shouldResetBeforeFullReindex(
        indexExistedBeforeInit: true,
        booksDone: const [],
      );

      expect(shouldReset, isTrue);
    });

    test('מחזיר false ביצירה ראשונית של אינדקס חדש', () {
      final shouldReset = IndexingRepository.shouldResetBeforeFullReindex(
        indexExistedBeforeInit: false,
        booksDone: const [],
      );

      expect(shouldReset, isFalse);
    });

    test('מחזיר false כשמדובר בעדכון אינקרמנטלי', () {
      final shouldReset = IndexingRepository.shouldResetBeforeFullReindex(
        indexExistedBeforeInit: true,
        booksDone: const ['ספר אחד'],
      );

      expect(shouldReset, isFalse);
    });
  });

  group('IndexingRepository.areAllIndexableBooksIndexed', () {
    test('מחזיר true כשכל הספרים האינדקסביליים קיימים ב-booksDone', () {
      final library = _buildLibrary(
        bavliBooks: const [('שבת', 1)],
        additionalBooks: [
          PdfBook(
            title: 'קובץ PDF',
            path: r'C:\library\sample.pdf',
            categoryPath: 'ספרים אישיים',
          ),
          ExternalLibraryBook(
            title: 'ספר חיצוני',
            id: 900,
            link: 'https://example.com/book',
          ),
        ],
      );

      final indexedBookKeys = library
          .getAllBooks()
          .where(IndexingRepository.isIndexableBook)
          .map(IndexingRepository.catalogueOrderKey);

      expect(
        IndexingRepository.areAllIndexableBooksIndexed(
          library.getAllBooks(),
          indexedBookKeys,
        ),
        isTrue,
      );
    });

    test('מחזיר false כשחסר ספר אינדקסבילי אחד', () {
      final library = _buildLibrary(
        bavliBooks: const [('שבת', 1)],
        additionalBooks: [
          DocxBook(
            title: 'מסמך',
            path: r'C:\library\doc.docx',
            categoryPath: 'ספרים אישיים',
          ),
        ],
      );

      final indexedBookKeys = [
        IndexingRepository.catalogueOrderKey(library.getAllBooks().first),
      ];

      expect(
        IndexingRepository.areAllIndexableBooksIndexed(
          library.getAllBooks(),
          indexedBookKeys,
        ),
        isFalse,
      );
    });

    test('מחזיר false כשאין כלל ספרים אינדקסביליים', () {
      final library = Library(categories: []);
      library.books.add(
        ExternalLibraryBook(
          title: 'ספר חיצוני',
          id: 901,
          link: 'https://example.com/ext',
        ),
      );

      expect(
        IndexingRepository.areAllIndexableBooksIndexed(
          library.getAllBooks(),
          const [],
        ),
        isFalse,
      );
    });
  });

  group('IndexingRepository.shouldUseFastPath', () {
    test(
        'מחזיר true רק כשכל הספרים האינדקסביליים מאונדקסים ואין manual reindex',
        () {
      final library = _buildLibrary(
        bavliBooks: const [('שבת', 1)],
        additionalBooks: [
          ExternalLibraryBook(
            title: 'ספר חיצוני',
            id: 900,
            link: 'https://example.com/book',
          ),
        ],
      );

      final indexedBookKeys = library
          .getAllBooks()
          .where(IndexingRepository.isIndexableBook)
          .map(IndexingRepository.catalogueOrderKey);

      expect(
        IndexingRepository.shouldUseFastPath(
          books: library.getAllBooks(),
          booksDone: indexedBookKeys,
          requiresManualReindex: false,
        ),
        isTrue,
      );
    });

    test('מחזיר false כשנדרש manual reindex גם אם כל הספרים כבר מאונדקסים', () {
      final library = _buildLibrary(bavliBooks: const [('שבת', 1)]);
      final indexedBookKeys = library
          .getAllBooks()
          .where(IndexingRepository.isIndexableBook)
          .map(IndexingRepository.catalogueOrderKey);

      expect(
        IndexingRepository.shouldUseFastPath(
          books: library.getAllBooks(),
          booksDone: indexedBookKeys,
          requiresManualReindex: true,
        ),
        isFalse,
      );
    });
  });

  group('IndexingRepository.indexAllBooks', () {
    test('fast path מחזיר מוקדם בלי להפעיל isolate ובלי callbacks', () async {
      final library = _buildLibrary(bavliBooks: const [('שבת', 1)]);
      final indexedBookKeys = library
          .getAllBooks()
          .where(IndexingRepository.isIndexableBook)
          .map(IndexingRepository.catalogueOrderKey)
          .toList();
      final provider = FakeTantivyDataProvider(
        booksDoneValue: indexedBookKeys,
        ensureIndexStateMatchesCatalogueValue: false,
      );
      final isolateService = FakeIndexingIsolateService();

      final repository = IndexingRepository(
        provider,
        isolateService: isolateService,
      );

      var actualIndexingStarted = false;
      var progressCalls = 0;

      final result = await repository.indexAllBooks(
        library,
        onActualIndexingStarted: () {
          actualIndexingStarted = true;
        },
        onProgress: (_, __) {
          progressCalls++;
        },
      );

      expect(result, isTrue);
      expect(actualIndexingStarted, isFalse);
      expect(progressCalls, 0);
      expect(provider.ensureIndexStateMatchesCatalogueCalls, 1);
      expect(isolateService.wasUsed, isFalse);
    });

    test('לא מדלג ב-fast path כשנדרש manual reindex', () async {
      final library = _buildLibrary(bavliBooks: const [('שבת', 1)]);
      final indexedBookKeys = library
          .getAllBooks()
          .where(IndexingRepository.isIndexableBook)
          .map(IndexingRepository.catalogueOrderKey)
          .toList();
      final provider = FakeTantivyDataProvider(
        booksDoneValue: indexedBookKeys,
        ensureIndexStateMatchesCatalogueValue: true,
      );
      final isolateService = FakeIndexingIsolateService();

      final repository = IndexingRepository(
        provider,
        isolateService: isolateService,
      );

      var actualIndexingStarted = false;
      var progressCalls = 0;

      final result = await repository.indexAllBooks(
        library,
        onActualIndexingStarted: () {
          actualIndexingStarted = true;
        },
        onProgress: (_, __) {
          progressCalls++;
        },
      );

      expect(result, isFalse);
      expect(actualIndexingStarted, isFalse);
      expect(progressCalls, 0);
      expect(provider.ensureIndexStateMatchesCatalogueCalls, 1);
      expect(isolateService.wasUsed, isFalse);
    });
  });

  group('IndexingRepository.buildCatalogueDocumentId', () {
    test('נותן עדיפות לסדר הספר לפני הסדר הפנימי בתוך הספר', () {
      final earlierBookLateSegment =
          IndexingRepository.buildCatalogueDocumentId(
        catalogueOrder: 0,
        ordinal: 500,
      );
      final laterBookFirstSegment = IndexingRepository.buildCatalogueDocumentId(
        catalogueOrder: 1,
        ordinal: 0,
      );

      expect(earlierBookLateSegment, lessThan(laterBookFirstSegment));
    });
  });

  group('IndexingRepository.catalogueOrderKey', () {
    test('מבדיל בין קבצי PDF עם אותו שם לפי הנתיב בפועל', () {
      final first = PdfBook(
        title: 'שבת',
        path: r'C:\books\a.pdf',
        categoryPath: 'תלמוד בבלי, סדר מועד',
      );
      final second = PdfBook(
        title: 'שבת',
        path: r'C:\books\b.pdf',
        categoryPath: 'תלמוד בבלי, סדר מועד',
      );

      expect(
        IndexingRepository.catalogueOrderKey(first),
        isNot(IndexingRepository.catalogueOrderKey(second)),
      );
    });
  });

  group('IndexingRepository.isIndexableBook', () {
    test('DocxBook נכלל באינדוקס דרך מיפוי ל-TextBook', () {
      // רגרסיה: לפני התיקון `isIndexableBook` החזיר false ל-DocxBook,
      // אז `IndexingBloc` סינן אותו לפני indexAllBooks וקבצי DOCX לא נכנסו
      // לאינדקס הטנטיווי. עכשיו הוא ממופה ל-TextBook באמצעות `toTextBook()`
      // ו-`book.text` מחלץ את התוכן דרך docxToText ב-DatabaseLibraryProvider.
      final docx = DocxBook(
        id: 1,
        title: 'בדיקה',
        path: r'C:\library\בדיקה.docx',
        categoryId: 10,
      );
      expect(IndexingRepository.isIndexableBook(docx), isTrue);
    });

    test('TextBook ו-PdfBook נשארים אינדוקסיביליים', () {
      expect(
        IndexingRepository.isIndexableBook(TextBook(title: 'א')),
        isTrue,
      );
      expect(
        IndexingRepository.isIndexableBook(
          PdfBook(title: 'א', path: r'C:\a.pdf'),
        ),
        isTrue,
      );
    });

    test('ExternalLibraryBook לא אינדוקסיבילי', () {
      final external = ExternalLibraryBook(
        title: 'אוצר',
        id: 999,
        link: 'https://example.com',
      );
      expect(IndexingRepository.isIndexableBook(external), isFalse);
    });
  });

  group('DocxBook ↔ TextBook(wrap) — עקביות מפתח קטלוג', () {
    test('catalogueOrderKey זהה ל-DocxBook ול-TextBook העטוף עם id', () {
      // קריטי: שני המפתחות חייבים להיות זהים כדי שהבדיקה
      // `booksDone.contains(indexedBookKey)` תזהה אותו ספר בלי לכפול
      // את האינדוקס בהפעלות חוזרות.
      final docx = DocxBook(
        id: 42,
        title: 'בדיקה',
        path: r'C:\library\בדיקה.docx',
        categoryId: 7,
      );
      expect(
        IndexingRepository.catalogueOrderKey(docx),
        IndexingRepository.catalogueOrderKey(docx.toTextBook()),
      );
    });

    test('catalogueOrderKey זהה גם ללא id (נופל ל-title|category|docx|path)',
        () {
      // FileBook משתמש ב-`book.path` ב-pathKey, ו-TextBook (לא FileBook)
      // משתמש ב-`book.filePath`. `toTextBook()` מעביר `filePath ?? path`,
      // כך שהמפתח נשאר עקבי גם בלי id.
      final docx = DocxBook(
        title: 'בדיקה ללא id',
        path: r'C:\library\בדיקה.docx',
        categoryPath: 'ספרים אישיים',
      );
      expect(
        IndexingRepository.catalogueOrderKey(docx),
        IndexingRepository.catalogueOrderKey(docx.toTextBook()),
      );
    });
  });

  group('IndexingRepository.optimizeIndexBestEffort', () {
    test('מחזיר true כש-optimize מצליח', () async {
      var called = false;

      final completed =
          await IndexingRepository.optimizeIndexBestEffort(() async {
        called = true;
      });

      expect(called, isTrue);
      expect(completed, isTrue);
    });

    test('מחזיר false ולא זורק כש-optimize נכשל אחרי commit', () async {
      Object? reportedError;

      final completed =
          await IndexingRepository.optimizeIndexBestEffort(() async {
        throw StateError('maintenance failed');
      }, onFailure: (error, _) {
        reportedError = error;
      });

      expect(completed, isFalse);
      expect(reportedError, isA<StateError>());
    });
  });
}

class FakeTantivyDataProvider implements TantivyDataProvider {
  FakeTantivyDataProvider({
    required this.booksDoneValue,
    required this.ensureIndexStateMatchesCatalogueValue,
  });

  final List<String> booksDoneValue;
  final bool ensureIndexStateMatchesCatalogueValue;
  int ensureIndexStateMatchesCatalogueCalls = 0;

  @override
  List<String> get booksDone => booksDoneValue;

  @override
  Future<bool> ensureIndexStateMatchesCatalogue() async {
    ensureIndexStateMatchesCatalogueCalls++;
    return ensureIndexStateMatchesCatalogueValue;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('Unexpected call: $invocation');
  }
}

class FakeIndexingIsolateService implements IndexingIsolateService {
  bool wasUsed = false;

  @override
  Future<void> cancelActiveWork() async {
    wasUsed = true;
  }

  @override
  Future<void> dispose() async {
    wasUsed = true;
  }

  @override
  Future<Stream<IndexingIsolateUpdate>> processPdfPages({
    required List<({String reference, String text, int pageIndex})> pages,
  }) async {
    wasUsed = true;
    return const Stream.empty();
  }

  @override
  Future<Stream<IndexingIsolateUpdate>> processTextBook({
    required String text,
  }) async {
    wasUsed = true;
    return const Stream.empty();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('Unexpected call: $invocation');
  }
}

Library _buildLibrary({
  required List<(String, int)> bavliBooks,
  List<Book> additionalBooks = const [],
}) {
  final library = Library(categories: []);
  final tanakh = Category(
    title: 'תנ"ך',
    description: '',
    shortDescription: '',
    order: 1,
    subCategories: [],
    books: [],
    parent: library,
  );
  final bavli = Category(
    title: 'תלמוד בבלי',
    description: '',
    shortDescription: '',
    order: 2,
    subCategories: [],
    books: [],
    parent: library,
  );
  library.subCategories.addAll([tanakh, bavli]);

  tanakh.books.add(
    TextBook(title: 'בראשית', order: 1, category: tanakh),
  );

  bavli.books.addAll(
    bavliBooks
        .map(
          (entry) => TextBook(
            title: entry.$1,
            order: entry.$2,
            category: bavli,
          ),
        )
        .toList(),
  );

  library.books.addAll(additionalBooks);

  return library;
}

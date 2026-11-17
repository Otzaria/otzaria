import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/cache_database_holder.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/migration/models/pdf_anchor_cache_entry.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/utils/file/page_converter.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../helpers/memory_settings_cache.dart';

/// מחרוזת PDF הקסדצימלית ב-UTF-16BE עם BOM — הכתיב היחיד לכותרות עבריות.
String _pdfHexString(String value) {
  final buffer = StringBuffer('<FEFF');
  for (final unit in value.codeUnits) {
    buffer.write(unit.toRadixString(16).padLeft(4, '0').toUpperCase());
  }
  buffer.write('>');
  return buffer.toString();
}

/// בונה קובץ PDF תקין מינימלי עם [pageCount] עמודים ורשימת סימניות שטוחה.
/// [bookmarks] ריק = PDF ללא outline.
Uint8List buildMinimalPdf({
  required int pageCount,
  List<({String title, int page})> bookmarks = const [],
}) {
  final pageObjNums = List.generate(pageCount, (i) => 3 + i);
  final outlinesObjNum = 3 + pageCount;
  final itemObjNums = List.generate(
    bookmarks.length,
    (i) => outlinesObjNum + 1 + i,
  );

  final objects = <String>[
    bookmarks.isEmpty
        ? '<< /Type /Catalog /Pages 2 0 R >>'
        : '<< /Type /Catalog /Pages 2 0 R /Outlines $outlinesObjNum 0 R >>',
    '<< /Type /Pages /Kids [${pageObjNums.map((n) => '$n 0 R').join(' ')}] '
        '/Count $pageCount >>',
    for (var i = 0; i < pageCount; i++)
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>',
  ];

  if (bookmarks.isNotEmpty) {
    objects.add(
      '<< /Type /Outlines /First ${itemObjNums.first} 0 R '
      '/Last ${itemObjNums.last} 0 R /Count ${bookmarks.length} >>',
    );
    for (var i = 0; i < bookmarks.length; i++) {
      objects.add(
        '<< ${[
          '/Title ${_pdfHexString(bookmarks[i].title)}',
          '/Parent $outlinesObjNum 0 R',
          if (i > 0) '/Prev ${itemObjNums[i - 1]} 0 R',
          if (i < bookmarks.length - 1) '/Next ${itemObjNums[i + 1]} 0 R',
          '/Dest [${pageObjNums[bookmarks[i].page - 1]} 0 R /Fit]',
        ].join(' ')} >>',
      );
    }
  }

  final bytes = <int>[];
  void write(String s) => bytes.addAll(s.codeUnits);

  write('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(bytes.length);
    write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }

  final xrefOffset = bytes.length;
  write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n');
  write('startxref\n$xrefOffset\n%%EOF\n');

  return Uint8List.fromList(bytes);
}

PdfOutlineNode _outlineNode(String title, int page) => PdfOutlineNode(
  title: title,
  dest: PdfDest(page, PdfDestCommand.fit, null),
  children: const [],
);

/// ה-outline של מהדורת ה-PDF: שלושה עמודי דף בכתיב המקוצר.
List<PdfOutlineNode> _matchingOutline() => [
  _outlineNode('דף ב.', 1),
  _outlineNode('דף ב:', 2),
  _outlineNode('דף ג.', 3),
];

const _pdfBookmarks = <({String title, int page})>[
  (title: 'דף ב.', page: 1),
  (title: 'דף ב:', page: 2),
  (title: 'דף ג.', page: 3),
];

/// ספק תוכן-עניינים שניתן להחליף בזמן ריצה — כך אפשר לדמות DB שטרם נטען.
class _FakeTocProvider implements LibraryProvider {
  List<TocEntry> toc = const [];

  @override
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async => toc;

  @override
  String get displayName => 'Fake';
  @override
  bool get isInitialized => true;
  @override
  int get priority => 0;
  @override
  String get providerId => 'fake';
  @override
  String get sourceIndicator => 'T';
  @override
  Future<void> initialize() async {}
  @override
  Future<Set<String>> getAvailableBookTitles() async => const {};
  @override
  Future<bool> hasBook(String title, int categoryId, String fileType) async =>
      true;
  @override
  Future<String?> getBookText(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async => '';
  @override
  Future<Library> buildLibraryCatalog(
    Map<String, Map<String, dynamic>> metadata,
    String rootPath,
  ) => throw UnimplementedError();
  @override
  Future<List<Link>> getAllLinksForBook(
    String title,
    int categoryId,
    String fileType,
  ) async => const [];
  @override
  Future<String> getLinkContent(Link link) => throw UnimplementedError();
  @override
  Future<Map<String, List<Book>>> loadBooks(
    Map<String, Map<String, dynamic>> metadata,
  ) async => const {};
}

/// תוכן עניינים של מסכת: שורש ותחתיו שלושה דפים באותו כתיב כמו ה-PDF.
List<TocEntry> _tractateToc(String tractate) {
  final root = TocEntry(text: tractate, index: 0);
  root.children = [
    TocEntry(text: 'דף ב.', index: 10, level: 2, parent: root),
    TocEntry(text: 'דף ב:', index: 20, level: 2, parent: root),
    TocEntry(text: 'דף ג.', index: 30, level: 2, parent: root),
  ];
  return [root];
}

class _CountingLibrary extends Library {
  _CountingLibrary({required super.categories});

  int companionLookups = 0;

  @override
  Book? getCompanionBook(Book book, Type companionType) {
    companionLookups++;
    return super.getCompanionBook(book, companionType);
  }
}

class _TextBookWithToc extends TextBook {
  _TextBookWithToc(String title, this.toc) : super(title: title);

  final List<TocEntry> toc;

  @override
  Future<List<TocEntry>> get tableOfContents async => toc;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Map<String, List<PdfOutlineNode>> outlinesByPath;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    outlinesByPath = {};
    pdfAnchorsReaderForTesting = (pdfPath) async {
      final outline = outlinesByPath[pdfPath];
      if (outline == null) throw FileSystemException('PDF not found', pdfPath);
      return collectPdfAnchors(outline);
    };
    tempDir = await Directory.systemTemp.createTemp('page_converter_cache');
    final dbDir = Directory(p.join(tempDir.path, 'databases'));
    await dbDir.create(recursive: true);

    final previousDataRoot = AppPaths.cachedDataRootPath;
    AppPaths.debugOverrideDataRootPath(tempDir.path);
    await Settings.setValue<String>(
      SettingsRepository.keyDatabasesPath,
      dbDir.path,
    );

    // addTearDown רץ ב-LIFO: קודם סגירת ה-DB, ואחר כך מחיקת התיקייה.
    addTearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {
        // ב-Windows ייתכן שידית לקובץ עוד לא שוחררה ברגע הסיום.
      }
    });
    addTearDown(() => AppPaths.debugOverrideDataRootPath(previousDataRoot));
    addTearDown(() => CacheDatabaseHolder.instance.close());
    addTearDown(() => LibraryProviderManager.instance.resetForTesting());
    addTearDown(() => pdfAnchorsReaderForTesting = null);
  });

  Future<void> writePdf(
    String pdfPath, {
    required List<({String title, int page})> bookmarks,
  }) async {
    outlinesByPath[pdfPath] = [
      for (final bookmark in bookmarks)
        _outlineNode(bookmark.title, bookmark.page),
    ];
    await File(pdfPath).writeAsBytes(
      buildMinimalPdf(pageCount: 3, bookmarks: bookmarks),
    );
  }

  /// ספרייה עם מהדורת PDF אחת ומהדורות טקסט לפי [textTitles], וספק
  /// תוכן-עניינים רשום — בלעדיו `TextBook.tableOfContents` מחזיר רשימה ריקה.
  ({List<TextBook> texts, PdfBook pdf, _FakeTocProvider provider}) seedLibrary({
    required List<String> textTitles,
    required String pdfPath,
    bool withToc = true,
  }) {
    final category = Category(
      title: 'תלמוד בבלי',
      description: '',
      shortDescription: '',
      order: 0,
      subCategories: [],
      books: [],
      parent: null,
    );
    final texts = [
      for (final title in textTitles)
        TextBook(
          title: title,
          category: category,
          categoryId: 1,
          fileType: 'txt',
        ),
    ];
    final pdf = PdfBook(
      title: textTitles.first,
      path: pdfPath,
      category: category,
    );
    category.books
      ..addAll(texts)
      ..add(pdf);

    DataRepository.instance.library = Future.value(
      Library(categories: [category]),
    );

    final provider = _FakeTocProvider();
    if (withToc) provider.toc = _tractateToc(textTitles.first);
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {
        for (final title in textTitles)
          BookCompositeKey.create(
            title: title,
            categoryId: 1,
            fileType: 'txt',
          ): provider,
      },
      providers: [provider],
    );

    return (texts: texts, pdf: pdf, provider: provider);
  }

  /// מריץ [probe] עד שהוא מחזיר ערך שאינו null — הכתיבות למטמון המתמיד
  /// יוצאות ב-`unawaited` ולכן אינן מסונכרנות עם החזרת ההמרה.
  Future<T?> waitFor<T>(
    Future<T?> Function() probe, {
    int attempts = 40,
  }) async {
    for (var i = 0; i < attempts; i++) {
      final value = await probe();
      if (value != null) return value;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return null;
  }

  Future<PdfAnchorCacheEntry?> anchorRow(String pdfPath) async =>
      (await CacheDatabaseHolder.instance.repository).getPdfAnchorCacheEntry(
        pdfPath,
      );

  // ---------------------------------------------------------------------------
  // מטמון מפת העמודים בזיכרון — נבדק דרך pdfToTextPage, שמקבל outline מוכן
  // ולכן אינו נוגע בקובץ כלל.
  // ---------------------------------------------------------------------------
  group('מטמון מפת העמודים בזיכרון', () {
    test('רענון הספרייה מחליף את המפה של אותה מהדורה', () async {
      const title = 'אותו ספר לפני ואחרי רענון';
      final pdfPath = p.join(tempDir.path, 'refreshed-toc.pdf');
      final original = seedLibrary(textTitles: [title], pdfPath: pdfPath);
      expect(await pdfToTextPage(original.pdf, _matchingOutline(), 3), 30);

      final refreshed = seedLibrary(textTitles: [title], pdfPath: pdfPath);
      refreshed.provider.toc = [
        for (final (i, node) in _matchingOutline().indexed)
          TocEntry(text: node.title, index: (i + 1) * 100),
      ];
      expect(await pdfToTextPage(refreshed.pdf, _matchingOutline(), 3), 300);
    });

    test('אותו נתיב PDF עם שני מקורות מוצא כל מהדורת טקסט', () async {
      final books = seedLibrary(
        textTitles: const ['ספר ממקורות שונים'],
        pdfPath: p.join(tempDir.path, 'shared-path.pdf'),
      );
      final official = books.texts.single;
      final attached = TextBook(
        title: official.title,
        category: official.category,
        categoryId: official.categoryId,
        source: BookSource.attached('other-library'),
      );
      final attachedPdf = PdfBook(
        title: official.title,
        path: books.pdf.path,
        category: official.category,
        source: attached.source,
      );
      official.category!.books.addAll([attached, attachedPdf]);
      final attachedProvider = _FakeTocProvider()
        ..toc = [
          for (final (i, node) in _matchingOutline().indexed)
            TocEntry(text: node.title, index: (i + 1) * 100),
        ];
      LibraryProviderManager.instance.seedMappingsForTesting(
        mapping: {
          BookCompositeKey.fromBook(official)!: books.provider,
          BookCompositeKey.fromBook(attached)!: attachedProvider,
        },
        providers: [books.provider, attachedProvider],
      );

      expect(await pdfToTextPage(books.pdf, _matchingOutline(), 3), 30);
      expect(await pdfToTextPage(attachedPdf, _matchingOutline(), 3), 300);
      expect(await pdfToTextPage(books.pdf, _matchingOutline(), 3), 30);
    });

    for (final (dimension, source, categoryId, fileType) in [
      ('מקור אישי', BookSource.user, 1, 'txt'),
      ('מקור מצורף', BookSource.attached('other-library'), 1, 'txt'),
      ('קטגוריה', BookSource.official, 2, 'txt'),
      ('סוג קובץ', BookSource.official, 1, 'md'),
    ]) {
      test('טעינות ומפות נפרדות לאותה כותרת עם $dimension שונה', () async {
        final books = seedLibrary(
          textTitles: ['ברכות-זהות-$dimension'],
          pdfPath: p.join(tempDir.path, 'identity.pdf'),
        );
        final official = books.texts.single;
        final other = TextBook(
          title: official.title,
          category: official.category,
          categoryId: categoryId,
          fileType: fileType,
          source: source,
        );
        final otherProvider = _FakeTocProvider()
          ..toc = [
            for (final (i, node) in _matchingOutline().indexed)
              TocEntry(text: node.title, index: (i + 1) * 100),
          ];
        LibraryProviderManager.instance.seedMappingsForTesting(
          mapping: {
            BookCompositeKey.fromBook(official)!: books.provider,
            BookCompositeKey.fromBook(other)!: otherProvider,
          },
          providers: [books.provider, otherProvider],
        );
        final started = Completer<void>();
        final release = Completer<void>();
        var reads = 0;
        pdfAnchorsReaderForTesting = (_) async {
          reads++;
          if (!started.isCompleted) started.complete();
          await release.future;
          return collectPdfAnchors(_matchingOutline());
        };

        final first = textToPdfPage(other, 200, pdfBook: books.pdf);
        await started.future;
        final second = textToPdfPage(official, 20, pdfBook: books.pdf);
        final conversions = Future.wait([first, second]);
        await Future<void>.delayed(Duration.zero);
        release.complete();

        expect(await conversions, [2, 2]);
        expect(reads, 1);
        expect(await textToPdfPage(other, 100, pdfBook: books.pdf), 1);
        expect(await textToPdfPage(official, 30, pdfBook: books.pdf), 3);
        final sameEdition = TextBook(
          title: other.title,
          categoryId: other.categoryId,
          fileType: other.fileType,
          source: other.source,
        );
        expect(await textToPdfPage(sameEdition, 200, pdfBook: books.pdf), 2);
        expect(reads, 1);
      });
    }

    test('ללא זהות קטלוגית המפה נשמרת בנפרד לכל מופע ספר', () async {
      final books = seedLibrary(
        textTitles: const ['ברכות-ללא-זהות'],
        pdfPath: p.join(tempDir.path, 'no-catalog-identity.pdf'),
      );
      final first = _TextBookWithToc(books.texts.single.title, [
        for (final (i, node) in _matchingOutline().indexed)
          TocEntry(text: node.title, index: (i + 1) * 10),
      ]);
      final second = _TextBookWithToc(first.title, [
        for (final (i, node) in _matchingOutline().indexed)
          TocEntry(text: node.title, index: (i + 1) * 100),
      ]);
      expect(
        await textToPdfPage(
          first,
          20,
          pdfBook: books.pdf,
          outline: _matchingOutline(),
        ),
        2,
      );
      expect(
        await textToPdfPage(
          second,
          200,
          pdfBook: books.pdf,
          outline: _matchingOutline(),
        ),
        2,
      );
      expect(await textToPdfPage(first, 30, pdfBook: books.pdf), 3);
      expect(await textToPdfPage(second, 100, pdfBook: books.pdf), 1);
    });

    for (final fileOutcome in ['כשל', 'ריק', 'שונה']) {
      for (final fileToPdf in [true, false]) {
        test(
          'outline שסופק נשמר מול קריאת קובץ $fileOutcome '
          'בכיוון ${fileToPdf ? 'טקסט ל-PDF' : 'PDF לטקסט'}',
          () async {
            final books = seedLibrary(
              textTitles: const ['ברכות-מקורות-שונים'],
              pdfPath: p.join(tempDir.path, 'different-sources.pdf'),
            );
            final started = Completer<void>();
            final release = Completer<void>();
            var reads = 0;
            final shifted = [
              _outlineNode('דף ב.', 11),
              _outlineNode('דף ב:', 12),
              _outlineNode('דף ג.', 13),
            ];
            pdfAnchorsReaderForTesting = (_) async {
              reads++;
              started.complete();
              await release.future;
              if (fileOutcome == 'כשל') {
                throw const FileSystemException('temporary failure');
              }
              return collectPdfAnchors(fileOutcome == 'ריק' ? [] : shifted);
            };

            final fromFile = fileToPdf
                ? textToPdfPage(books.texts.first, 20, pdfBook: books.pdf)
                : pdfToTextPage(books.pdf, const [], 13);
            await started.future;
            final supplied = fileToPdf
                ? pdfToTextPage(books.pdf, _matchingOutline(), 3)
                : textToPdfPage(
                    books.texts.first,
                    20,
                    pdfBook: books.pdf,
                    outline: _matchingOutline(),
                  );
            try {
              expect(await supplied, fileToPdf ? 30 : 2);
            } finally {
              release.complete();
            }
            expect(
              await fromFile,
              fileOutcome == 'שונה' ? (fileToPdf ? 12 : 30) : isNull,
            );
            expect(await pdfToTextPage(books.pdf, _matchingOutline(), 3), 30);
            expect(reads, 1);
          },
        );
      }
    }

    test('outline טעון מומר לצד טעינה פעילה ללא פתיחה נוספת', () async {
      final books = seedLibrary(
        textTitles: const ['ברכות-outline-מקביל'],
        pdfPath: p.join(tempDir.path, 'mixed-outline-concurrent.pdf'),
      );
      final started = Completer<void>();
      final release = Completer<void>();
      var reads = 0;
      pdfAnchorsReaderForTesting = (_) async {
        reads++;
        started.complete();
        await release.future;
        return collectPdfAnchors(_matchingOutline());
      };

      final toPdf = textToPdfPage(books.texts.first, 20, pdfBook: books.pdf);
      await started.future;
      final toText = pdfToTextPage(books.pdf, _matchingOutline(), 3);
      await Future<void>.delayed(Duration.zero);
      release.complete();

      expect(await toPdf, 2);
      expect(await toText, 30);
      expect(reads, 1);
    });

    test('המרות מקבילות בשני הכיוונים חולקות טעינת PDF אחת', () async {
      final books = seedLibrary(
        textTitles: const ['ברכות-מקביל'],
        pdfPath: p.join(tempDir.path, 'concurrent.pdf'),
      );
      final started = Completer<void>();
      final release = Completer<void>();
      var reads = 0;
      pdfAnchorsReaderForTesting = (_) async {
        reads++;
        if (!started.isCompleted) started.complete();
        await release.future;
        return collectPdfAnchors(_matchingOutline());
      };
      final toPdf = textToPdfPage(books.texts.first, 20, pdfBook: books.pdf);
      await started.future;
      final toText = pdfToTextPage(books.pdf, const [], 3);
      await Future<void>.delayed(Duration.zero);
      release.complete();

      expect(await toPdf, 2);
      expect(await toText, 30);
      expect(reads, 1);
    });

    test('TOC ריק בטעינה משותפת מתפנה ומאפשר ניסיון חוזר', () async {
      final books = seedLibrary(
        textTitles: const ['ברכות-תוכן-עניינים-מקביל'],
        pdfPath: p.join(tempDir.path, 'empty-toc-concurrent.pdf'),
        withToc: false,
      );
      final started = Completer<void>();
      final release = Completer<void>();
      var reads = 0;
      pdfAnchorsReaderForTesting = (_) async {
        reads++;
        if (reads == 1) {
          started.complete();
          await release.future;
        }
        return collectPdfAnchors(_matchingOutline());
      };

      final toPdf = textToPdfPage(books.texts.first, 20, pdfBook: books.pdf);
      await started.future;
      final toText = pdfToTextPage(books.pdf, const [], 3);
      final emptyConversions = Future.wait<int?>([toPdf, toText]);
      await Future<void>.delayed(Duration.zero);
      expect(reads, 1);
      release.complete();

      expect(await emptyConversions, [null, null]);
      expect(reads, 1);
      books.provider.toc = _tractateToc('ברכות-תוכן-עניינים-מקביל');
      expect(await pdfToTextPage(books.pdf, const [], 3), 30);
      expect(reads, 2);
    });

    test('כשל טעינה משותפת מתפנה ומאפשר ניסיון חוזר', () async {
      final books = seedLibrary(
        textTitles: const ['ברכות-ניסיון-חוזר'],
        pdfPath: p.join(tempDir.path, 'retry-concurrent.pdf'),
      );
      final started = Completer<void>();
      final release = Completer<void>();
      var reads = 0;
      pdfAnchorsReaderForTesting = (_) async {
        reads++;
        if (reads == 1) {
          started.complete();
          await release.future;
          throw const FileSystemException('temporary failure');
        }
        return collectPdfAnchors(_matchingOutline());
      };

      final toPdf = textToPdfPage(books.texts.first, 20, pdfBook: books.pdf);
      await started.future;
      final toText = pdfToTextPage(books.pdf, const [], 3);
      final failedConversions = Future.wait<int?>([toPdf, toText]);
      await Future<void>.delayed(Duration.zero);
      expect(reads, 1);
      release.complete();

      expect(await failedConversions, [null, null]);
      expect(reads, 1);
      expect(await pdfToTextPage(books.pdf, const [], 3), 30);
      expect(reads, 2);
    });

    test('מפה אמינה נשמרת ומשרתת את שני הכיוונים ללא גישה לקובץ', () async {
      // הקובץ אינו קיים: אילו הכיוון ההפוך לא היה נהנה מהמטמון, פתיחת ה-PDF
      // הייתה זורקת וההמרה הייתה מחזירה null.
      final books = seedLibrary(
        textTitles: const ['ברכות-מטמון'],
        pdfPath: p.join(tempDir.path, 'never-opened.pdf'),
      );

      expect(await pdfToTextPage(books.pdf, _matchingOutline(), 3), 30);
      expect(await textToPdfPage(books.texts.first, 20, pdfBook: books.pdf), 2);
    });

    test(
      'תוכן עניינים ריק אינו נשמר — הקריאה אחרי טעינת ה-DB מצליחה',
      () async {
        // רגרסיה: תוכן עניינים ריק הוא מצב זמני (ה-DB טרם נטען). אם הוא נשמר
        // במטמון, כל מעבר טקסט↔PDF נופל לתחילת הספר עד להפעלה מחדש.
        final books = seedLibrary(
          textTitles: const ['שבת-מטמון'],
          pdfPath: p.join(tempDir.path, 'toc-later.pdf'),
          withToc: false,
        );

        expect(await pdfToTextPage(books.pdf, _matchingOutline(), 3), isNull);

        books.provider.toc = _tractateToc('שבת-מטמון');
        expect(await pdfToTextPage(books.pdf, _matchingOutline(), 3), 30);
      },
    );

    test('מפה לא אמינה נשמרת בכוונה כשתוכן העניינים כבר נטען', () async {
      // מיפוי שנכשל מול תוכן עניינים קיים הוא עובדה על המהדורות, ולא מצב
      // זמני — הוא נשמר כדי שדפדוף לא יבנה את המפה מחדש בכל עמוד.
      final books = seedLibrary(
        textTitles: const ['עירובין-מטמון'],
        pdfPath: p.join(tempDir.path, 'mismatched.pdf'),
      );

      expect(
        await pdfToTextPage(books.pdf, [_outlineNode('כותרת זרה', 1)], 2),
        isNull,
      );
      expect(await pdfToTextPage(books.pdf, _matchingOutline(), 3), isNull);
    });

    test('מפה שלילית מהקובץ חוסכת פתיחה חוזרת ומתחדשת עם outline', () async {
      final books = seedLibrary(
        textTitles: const ['ספר שהקובץ שלו לא החזיר סימניות'],
        pdfPath: p.join(tempDir.path, 'no-file-outline.pdf'),
      );
      var reads = 0;
      pdfAnchorsReaderForTesting = (_) async {
        reads++;
        return const [];
      };

      for (var page = 1; page <= 3; page++) {
        expect(await pdfToTextPage(books.pdf, const [], page), isNull);
      }
      expect(reads, 1);

      expect(await pdfToTextPage(books.pdf, _matchingOutline(), 3), 30);
      expect(
        await textToPdfPage(books.texts.single, 20, pdfBook: books.pdf),
        2,
      );
      expect(reads, 1);
    });

    test('PDF בלי מהדורת טקסט — חיפוש המלווה רץ פעם אחת לכל ספרייה', () async {
      final category = Category(
        title: 'ספרי PDF',
        description: '',
        shortDescription: '',
        order: 0,
        subCategories: [],
        books: [],
        parent: null,
      );
      final pdf = PdfBook(
        title: 'ספר בלי מלווה',
        path: p.join(tempDir.path, 'no-companion.pdf'),
        category: category,
      );
      category.books.add(pdf);
      final library = _CountingLibrary(categories: [category]);
      DataRepository.instance.library = Future.value(library);

      for (var page = 1; page <= 3; page++) {
        expect(await pdfToTextPage(pdf, _matchingOutline(), page), isNull);
      }
      expect(library.companionLookups, 1);

      // ספרייה שנטענה מחדש מתחילה בלי המטמון הקודם.
      final reloaded = _CountingLibrary(categories: [category]);
      DataRepository.instance.library = Future.value(reloaded);
      expect(await pdfToTextPage(pdf, _matchingOutline(), 1), isNull);
      expect(reloaded.companionLookups, 1);
    });

    test('כשל בפתיחת הקובץ אינו נשמר במטמון', () async {
      final books = seedLibrary(
        textTitles: const ['פסחים-מטמון'],
        pdfPath: p.join(tempDir.path, 'does-not-exist.pdf'),
      );

      expect(
        await textToPdfPage(books.texts.first, 10, pdfBook: books.pdf),
        isNull,
      );
      expect(await pdfToTextPage(books.pdf, _matchingOutline(), 3), 30);
    });
  });

  // ---------------------------------------------------------------------------
  // מטמון העוגנים המתמיד (cache.db) — קורא ופותח קובצי PDF אמיתיים
  // ---------------------------------------------------------------------------
  group('מטמון העוגנים המתמיד (cache.db)', () {
    test('PDF עם סימניות — הרשומה נשמרת וההמרה מצליחה', () async {
      final pdfPath = p.join(tempDir.path, 'with-outline.pdf');
      await writePdf(pdfPath, bookmarks: _pdfBookmarks);
      final books = seedLibrary(
        textTitles: const ['סוכה-מלא'],
        pdfPath: pdfPath,
      );

      expect(await textToPdfPage(books.texts.first, 20, pdfBook: books.pdf), 2);

      final entry = await waitFor(() => anchorRow(pdfPath));
      expect(entry, isNotNull);
      expect(entry!.decodeAnchors(), hasLength(3));
      expect(entry.fileSize, await File(pdfPath).length());
    });

    test(
      'רשומה תקפה משמשת מחדש — createdAt נשמר ו-accessedAt מתעדכן',
      () async {
        // שתי כותרות טקסט מול אותו PDF: מפתח מפת-העמודים שונה, ולכן הקריאה
        // השנייה חוזרת למטמון המתמיד במקום להתקצר במטמון שבזיכרון.
        final pdfPath = p.join(tempDir.path, 'reused.pdf');
        await writePdf(pdfPath, bookmarks: _pdfBookmarks);
        final books = seedLibrary(
          textTitles: const ['יומא-א', 'יומא-ב'],
          pdfPath: pdfPath,
        );

        expect(await textToPdfPage(books.texts[0], 20, pdfBook: books.pdf), 2);
        final first = await waitFor(() => anchorRow(pdfPath));
        expect(first, isNotNull);

        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(await textToPdfPage(books.texts[1], 20, pdfBook: books.pdf), 2);

        final touched = await waitFor(() async {
          final row = await anchorRow(pdfPath);
          return row != null && row.accessedAt > first!.accessedAt ? row : null;
        });
        expect(
          touched,
          isNotNull,
          reason: 'accessedAt אמור להתעדכן בקריאה חוזרת',
        );
        expect(
          touched!.createdAt,
          first!.createdAt,
          reason: 'הרשומה שוחזרה מהמטמון ולא נבנתה מחדש',
        );
      },
    );

    test('החלפת הקובץ פוסלת את הרשומה ומרעננת את העוגנים', () async {
      final pdfPath = p.join(tempDir.path, 'replaced.pdf');
      final file = File(pdfPath);
      await writePdf(
        pdfPath,
        bookmarks: const [(title: 'דף ב.', page: 1)],
      );
      final books = seedLibrary(
        textTitles: const ['נדרים-א', 'נדרים-ב'],
        pdfPath: pdfPath,
      );

      await textToPdfPage(books.texts[0], 10, pdfBook: books.pdf);
      final before = await waitFor(() => anchorRow(pdfPath));
      expect(before!.decodeAnchors(), hasLength(1));

      await writePdf(pdfPath, bookmarks: _pdfBookmarks);

      expect(await textToPdfPage(books.texts[1], 20, pdfBook: books.pdf), 2);
      final after = await waitFor(() async {
        final row = await anchorRow(pdfPath);
        return row != null && row.decodeAnchors().length == 3 ? row : null;
      });
      expect(after, isNotNull, reason: 'הרשומה אמורה להיבנות מחדש מהקובץ החדש');
      expect(after!.fileSize, await file.length());
    });

    test('רשימת עוגנים ריקה אינה נשמרת — הקריאה הבאה חוזרת לקובץ', () async {
      // רגרסיה (issue #1296): כשל חולף שהחזיר outline ריק נשמר לצמיתות
      // (המפתח הוא נתיב+גודל+mtime), והספר לא נפתח שוב במיקום המבוקש.
      final pdfPath = p.join(tempDir.path, 'transient-empty.pdf');
      await writePdf(pdfPath, bookmarks: _pdfBookmarks);
      final previousReader = pdfAnchorsReaderForTesting!;
      var reads = 0;
      pdfAnchorsReaderForTesting = (path) async {
        if (path != pdfPath) return previousReader(path);
        reads++;
        return const [];
      };
      final books = seedLibrary(
        textTitles: const ['תענית-א', 'תענית-ב'],
        pdfPath: pdfPath,
      );

      expect(
        await textToPdfPage(books.texts[0], 20, pdfBook: books.pdf),
        isNull,
      );
      expect(reads, 1);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(await anchorRow(pdfPath), isNull);

      expect(
        await textToPdfPage(books.texts[1], 20, pdfBook: books.pdf),
        isNull,
      );
      expect(reads, 2, reason: 'הקריאה השנייה אמורה לחזור לקובץ');
      expect(await anchorRow(pdfPath), isNull);
    });

    test('רשומה ריקה שנשמרה בעבר — נפסלת והעוגנים נבנים מחדש', () async {
      // ה-touch בקריאה מרענן את ה-accessedAt, ולכן רשומה ריקה מורעלת לא
      // הייתה נגרפת גם ב-TTL — חובה לפסול אותה בקריאה.
      final pdfPath = p.join(tempDir.path, 'poisoned-empty.pdf');
      await writePdf(pdfPath, bookmarks: _pdfBookmarks);
      final stat = await File(pdfPath).stat();
      final now = DateTime.now().millisecondsSinceEpoch;
      await (await CacheDatabaseHolder.instance.repository)
          .upsertPdfAnchorCacheEntry(
            PdfAnchorCacheEntry(
              filePath: pdfPath,
              fileSize: stat.size,
              lastModified: stat.modified.millisecondsSinceEpoch,
              anchorsJson: PdfAnchorCacheEntry.encode(const []),
              createdAt: now,
              accessedAt: now,
            ),
          );

      final books = seedLibrary(
        textTitles: const ['מגילה-א'],
        pdfPath: pdfPath,
      );

      expect(await textToPdfPage(books.texts[0], 20, pdfBook: books.pdf), 2);

      final rebuilt = await waitFor(() async {
        final row = await anchorRow(pdfPath);
        return row != null && row.decodeAnchors().length == 3 ? row : null;
      });
      expect(rebuilt, isNotNull, reason: 'הרשומה הריקה אמורה להיבנות מחדש');
    });

    test('outline ריק מהטאב — הסימניות נקראות מהקובץ', () async {
      // ה-outline של הטאב נטען ברקע; לחיצה לפני שהגיע חייבת ליפול לקובץ.
      final pdfPath = p.join(tempDir.path, 'tab-outline-empty.pdf');
      await writePdf(pdfPath, bookmarks: _pdfBookmarks);
      final books = seedLibrary(
        textTitles: const ['גיטין-רקע'],
        pdfPath: pdfPath,
      );

      expect(await pdfToTextPage(books.pdf, const [], 3), 30);
    });
  });
}

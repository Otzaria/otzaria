import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/indexing/services/indexing_isolate_service.dart';
import 'package:otzaria/search/book_facet.dart';
import 'package:otzaria/search/utils/search_catalogue_order_helper.dart';
import 'package:otzaria/utils/text/ref_helper.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:search_engine/search_engine.dart';

class IndexingRepository {
  final TantivyDataProvider _tantivyDataProvider;
  final IndexingIsolateService? _isolateService;
  IndexingIsolateService? _activeIsolateService;

  IndexingRepository(this._tantivyDataProvider,
      {IndexingIsolateService? isolateService})
      : _isolateService = isolateService;

  @visibleForTesting
  static bool shouldResetBeforeFullReindex({
    required bool indexExistedBeforeInit,
    required List<String> booksDone,
  }) {
    return indexExistedBeforeInit && booksDone.isEmpty;
  }

  /// בודקת אם בכלל יש טעם להריץ את בדיקת requiresManualReindex.
  /// ספרייה ריקה (כולל המקרה של "אין ספרייה") אין טעם לאפס לה אינדקס,
  /// כי אין מה לאנדקס מחדש.
  @visibleForTesting
  static bool shouldSkipManualReindexCheck(Library library) {
    return library.getAllBooks().isEmpty;
  }

  Future<bool> requiresManualReindex(Library library) async {
    if (shouldSkipManualReindexCheck(library)) {
      return false;
    }
    await _tantivyDataProvider.engine;
    return _tantivyDataProvider.requiresManualReindex(
      currentCatalogueOrderSignature: buildCatalogueOrderSignature(library),
    );
  }

  Future<void> prepareForManualReindex(Library library) async {
    await _tantivyDataProvider.engine;
    await _tantivyDataProvider.prepareForManualReindex(
      buildCatalogueOrderSignature(library),
    );
  }

  /// Indexes all books in the provided library.
  ///
  /// [library] The library containing books to index
  /// [onProgress] Callback function to report progress
  /// מבצע אינדוקס ומחזיר true אם הסתיים בהצלחה, false אם בוטל
  Future<bool> indexAllBooks(
    Library library, {
    void Function()? onActualIndexingStarted,
    required void Function(int processed, int total) onProgress,
  }) async {
    _tantivyDataProvider.isIndexing.value = true;
    final isolateService =
        _isolateService ?? await IndexingIsolateService.create();
    _activeIsolateService = isolateService;
    final catalogueOrderSignature = buildCatalogueOrderSignature(library);
    final catalogueOrderByBookKey = SearchCatalogueOrderHelper.buildKeyOrderMap(
      library,
      keyOf: (book) => catalogueOrderKey(book as Book),
    );

    final allBooks = library.getAllBooks();
    final totalBooks = allBooks.length;
    bool cancelled = false;
    var didStartActualIndexing = false;

    try {
      final requiresManualReindex = await _tantivyDataProvider
          .ensureIndexStateMatchesCatalogue(catalogueOrderSignature);
      if (requiresManualReindex) {
        _tantivyDataProvider.isIndexing.value = false;
        return false;
      }

      if (shouldResetBeforeFullReindex(
        indexExistedBeforeInit: _tantivyDataProvider.indexExistedBeforeInit,
        booksDone: _tantivyDataProvider.booksDone,
      )) {
        await _resetExistingIndexBeforeFullReindex();
      }

      int processedBooks = 0;
      int actuallyIndexed = 0;
      int skipped = 0;
      int errors = 0;

      debugPrint('📚 התחלת אינדוקס: $totalBooks ספרים');
      debugPrint(
          '📊 ספרים שכבר מאונדקסים: ${_tantivyDataProvider.booksDone.length}');

      for (Book book in allBooks) {
        if (!_tantivyDataProvider.isIndexing.value) {
          debugPrint('⚠️ אינדוקס בוטל על ידי המשתמש');
          cancelled = true;
          break;
        }

        try {
          final indexedBookKey = catalogueOrderKey(book);
          if (book is TextBook) {
            if (!_tantivyDataProvider.booksDone.contains(indexedBookKey)) {
              debugPrint('📖 מאנדקס ספר טקסט ב-isolate: ${book.title}');
              await _indexTextBook(
                book,
                isolateService,
                catalogueOrderByBookKey: catalogueOrderByBookKey,
                onActualIndexingStarted: () {
                  if (didStartActualIndexing) {
                    return;
                  }
                  didStartActualIndexing = true;
                  onActualIndexingStarted?.call();
                },
              );
              if (!_tantivyDataProvider.isIndexing.value) {
                cancelled = true;
                break;
              }
              _tantivyDataProvider.booksDone.add(indexedBookKey);
              actuallyIndexed++;
            } else {
              debugPrint('⏭️ דילוג על ספר טקסט שכבר מאונדקס: ${book.title}');
              skipped++;
            }
          } else if (book is PdfBook) {
            if (!_tantivyDataProvider.booksDone.contains(indexedBookKey)) {
              debugPrint('📄 מאנדקס PDF ב-isolate: ${book.title}');
              await _indexPdfBook(
                book,
                isolateService,
                catalogueOrderByBookKey: catalogueOrderByBookKey,
                onActualIndexingStarted: () {
                  if (didStartActualIndexing) {
                    return;
                  }
                  didStartActualIndexing = true;
                  onActualIndexingStarted?.call();
                },
              );
              if (!_tantivyDataProvider.isIndexing.value) {
                cancelled = true;
                break;
              }
              _tantivyDataProvider.booksDone.add(indexedBookKey);
              actuallyIndexed++;
            } else {
              debugPrint('⏭️ דילוג על PDF שכבר מאונדקס: ${book.title}');
              skipped++;
            }
          }

          processedBooks++;
          if (processedBooks % 25 == 0) {
            debugPrint('💾 שומר אינדקס (commit)...');
            final index = await _tantivyDataProvider.engine;
            await index.commit();
            saveIndexedBooks();
          }

          if (processedBooks % 50 == 0) {
            debugPrint(
                '📈 התקדמות: $processedBooks/$totalBooks (מאונדקסים: $actuallyIndexed, דולגו: $skipped, שגיאות: $errors)');
          }

          onProgress(processedBooks, totalBooks);
        } catch (e) {
          await Future.microtask(() {
            debugPrint('❌ שגיאה באינדוקס של ${book.title}: $e');
          });
          errors++;
          processedBooks++;
          onProgress(processedBooks, totalBooks);
          await Future.delayed(Duration.zero);
        }

        await Future.delayed(Duration.zero);
      }

      if (!cancelled) {
        debugPrint('✅ אינדוקס הושלם!');
        debugPrint('   📊 סה"כ: $totalBooks ספרים');
        debugPrint('   ✅ מאונדקסים: $actuallyIndexed');
        debugPrint('   ⏭️ דולגו: $skipped');
        debugPrint('   ❌ שגיאות: $errors');

        debugPrint('💾 שומר אינדקס סופי (final commit)...');
        final index = await _tantivyDataProvider.engine;
        await index.commit();
        saveIndexedBooks();
        debugPrint('⚙️ מבצע optimize לאינדקס...');
        await optimizeIndexBestEffort(index.optimize);
        debugPrint('✅ אינדקס נשמר בהצלחה!');
      }
    } finally {
      _activeIsolateService = null;
      if (!identical(isolateService, _isolateService)) {
        await isolateService.dispose();
      }
      _tantivyDataProvider.isIndexing.value = false;
    }
    return !cancelled;
  }

  Future<void> _resetExistingIndexBeforeFullReindex() async {
    final indexPath = await AppPaths.getIndexPath();
    debugPrint('🧹 זוהתה בנייה מחדש מלאה - מוחק אינדקס ישן לפני אינדוקס');
    await _tantivyDataProvider.resetIndex(indexPath);
    await _tantivyDataProvider.reopenIndex();
  }

  Future<void> _indexTextBook(
    TextBook book,
    IndexingIsolateService isolateService, {
    required Map<String, int> catalogueOrderByBookKey,
    String? preloadedText,
    void Function()? onActualIndexingStarted,
  }) async {
    final text = await _loadTextBookText(book, preloadedText: preloadedText);
    if (text == null) {
      return;
    }

    final stream = await isolateService.processTextBook(text: text);
    await _consumePreparedDocuments(
      book: book,
      stream: stream,
      isolateService: isolateService,
      catalogueOrderByBookKey: catalogueOrderByBookKey,
      onActualIndexingStarted: onActualIndexingStarted,
    );
  }

  Future<void> _indexPdfBook(
    PdfBook book,
    IndexingIsolateService isolateService, {
    required Map<String, int> catalogueOrderByBookKey,
    void Function()? onActualIndexingStarted,
  }) async {
    final pages = await _extractPdfPages(book);
    if (pages.isEmpty) return;

    final stream = await isolateService.processPdfPages(pages: pages);
    await _consumePreparedDocuments(
      book: book,
      stream: stream,
      isolateService: isolateService,
      catalogueOrderByBookKey: catalogueOrderByBookKey,
      onActualIndexingStarted: onActualIndexingStarted,
    );
  }

  bool _hasUsablePdfText(
      List<({String reference, String text, int pageIndex})> pages) {
    for (final page in pages) {
      for (final line in page.text.split('\n')) {
        final normalized =
            IndexingDocumentBuilder.normalizePdfTextForIndexing(line);
        if (!IndexingDocumentBuilder.isProbablyGarbagePdfText(normalized)) {
          return true;
        }
      }
    }
    return false;
  }

  Future<List<({String reference, String text, int pageIndex})>>
      _extractPdfPages(PdfBook book) async {
    final file = File(book.path);
    if (!await file.exists()) return const [];

    List<PdfOutlineNode> outline = const [];

    try {
      final document = await PdfDocument.openFile(book.path)
          .timeout(const Duration(seconds: 60));
      outline = await document.loadOutline().timeout(
            const Duration(seconds: 15),
            onTimeout: () => <PdfOutlineNode>[],
          );

      final pages = <({String reference, String text, int pageIndex})>[];

      for (int i = 0; i < document.pages.length; i++) {
        if (!_tantivyDataProvider.isIndexing.value) return const [];

        final pageText = await document.pages[i].loadText().timeout(
              const Duration(seconds: 5),
              onTimeout: () => null,
            );
        if (pageText == null) continue;

        final bookmark = await refFromPageNumber(i + 1, outline, book.title);
        final ref = bookmark.isNotEmpty
            ? '${book.title}, $bookmark, עמוד ${i + 1}'
            : '${book.title}, עמוד ${i + 1}';

        pages.add((reference: ref, text: pageText.fullText, pageIndex: i));
      }

      // Don't call document.dispose() explicitly - pdfrx's background page
      // preloader may still be executing FFI callbacks at this point.
      // Let the GC collect the document instead.

      if (_hasUsablePdfText(pages)) return pages;
    } catch (e) {
      debugPrint('❌ שגיאה בפתיחת PDF לאינדוקס: ${book.title}: $e');
    }

    return _loadPdfSidecar(book, outline);
  }

  Future<List<({String reference, String text, int pageIndex})>>
      _loadPdfSidecar(PdfBook book, List<PdfOutlineNode> outline) async {
    final candidates = <String>{
      '${book.path}.txt',
      p.setExtension(book.path, '.txt'),
    };

    File? sidecar;
    for (final candidate in candidates) {
      final f = File(candidate);
      if (await f.exists()) {
        sidecar = f;
        break;
      }
    }

    if (sidecar == null) return const [];

    final ocrText = await sidecar.readAsString();
    final pagesText =
        ocrText.contains('\f') ? ocrText.split('\f') : <String>[ocrText];

    final pages = <({String reference, String text, int pageIndex})>[];
    for (int pageIndex = 0; pageIndex < pagesText.length; pageIndex++) {
      final bookmark =
          await refFromPageNumber(pageIndex + 1, outline, book.title);
      final ref = bookmark.isNotEmpty
          ? '${book.title}, $bookmark, עמוד ${pageIndex + 1}'
          : '${book.title}, עמוד ${pageIndex + 1}';
      pages.add(
          (reference: ref, text: pagesText[pageIndex], pageIndex: pageIndex));
    }
    return pages;
  }

  Future<String?> _loadTextBookText(
    TextBook book, {
    String? preloadedText,
  }) async {
    String? text = preloadedText;

    if ((text == null || text.isEmpty) && book.categoryId != null) {
      debugPrint(
          '   🔍 מנסה לקרוא מ-DB: ${book.title} (categoryId: ${book.categoryId})');
      text = await SqliteDataProvider.instance.getBookTextFromDb(
        book.title,
        book.categoryId,
        book.fileType ?? 'txt',
      );
    }

    if (text == null || text.isEmpty) {
      debugPrint('   🔍 מנסה לקרוא דרך LibraryProvider: ${book.title}');
      text = await book.text;
    }

    if (text.isEmpty) {
      debugPrint(
          '⚠️ ספר ריק: ${book.title} (categoryId: ${book.categoryId}) - מדלג');
      return null;
    }

    return text;
  }

  Future<void> _consumePreparedDocuments({
    required Book book,
    required Stream<IndexingIsolateUpdate> stream,
    required IndexingIsolateService isolateService,
    required Map<String, int> catalogueOrderByBookKey,
    void Function()? onActualIndexingStarted,
  }) async {
    try {
      await for (final update in stream) {
        if (!_tantivyDataProvider.isIndexing.value) {
          await isolateService.cancelActiveWork();
          return;
        }

        if (update is! IndexingBatchReady) {
          continue;
        }

        await _writePreparedBatch(
          book,
          update.documents,
          catalogueOrderByBookKey: catalogueOrderByBookKey,
          onActualIndexingStarted: onActualIndexingStarted,
        );
        await update.acknowledge();
      }
    } catch (e) {
      await isolateService.cancelActiveWork();
      rethrow;
    }
  }

  Future<void> _writePreparedBatch(
    Book book,
    List<PreparedIndexDocument> documents, {
    required Map<String, int> catalogueOrderByBookKey,
    void Function()? onActualIndexingStarted,
  }) async {
    if (documents.isEmpty) {
      return;
    }

    onActualIndexingStarted?.call();

    if (!_tantivyDataProvider.isIndexing.value) {
      return;
    }

    final index = await _tantivyDataProvider.engine;
    final title = book.title;
    final topics = BookFacet.buildFacetPath(
      title: title,
      topics: book.topics,
      externalLibraryId: book.externalLibraryId,
      bookId: book.id,
      categoryPath: book.category?.path ?? book.categoryPath,
      fileType: book.fileType,
      filePath: book is FileBook ? book.path : book.filePath,
    );
    final isPdf = book is PdfBook;
    final filePath = buildIndexedBookFilePath(book);
    final catalogueOrder =
        catalogueOrderByBookKey[catalogueOrderKey(book)] ?? 0xFFFFFFFF;

    // בניית רשימת מסמכים בקריאת FFI אחת במקום loop של upsertDocument
    final docs = [
      for (final document in documents)
        DocumentInput(
          id: buildCatalogueDocumentId(
            catalogueOrder: catalogueOrder,
            ordinal: document.ordinal,
          ),
          title: title,
          reference: document.reference,
          topics: topics,
          text: document.text,
          segment: BigInt.from(document.segment),
          isPdf: isPdf,
          filePath: filePath,
        ),
    ];

    await index.upsertDocumentsBatch(docs: docs);
  }

  @visibleForTesting
  static Future<bool> optimizeIndexBestEffort(
    Future<void> Function() optimize, {
    void Function(Object error, StackTrace stackTrace)? onFailure,
  }) async {
    try {
      await optimize();
      return true;
    } catch (error, stackTrace) {
      if (onFailure != null) {
        onFailure(error, stackTrace);
      } else {
        debugPrint('⚠️ optimize נכשל אחרי commit; האינדקס כבר נשמר: $error');
        debugPrintStack(
          label: 'optimize failed after final commit',
          stackTrace: stackTrace,
        );
      }
      return false;
    }
  }

  @visibleForTesting
  static BigInt buildCatalogueDocumentId({
    required int catalogueOrder,
    required int ordinal,
  }) {
    return (BigInt.from(catalogueOrder + 1) << 32) + BigInt.from(ordinal + 1);
  }

  static int catalogueOrderFromDocumentId(BigInt documentId) {
    final encodedCatalogueOrder = (documentId >> 32).toInt();
    if (encodedCatalogueOrder <= 0) {
      return -1;
    }
    return encodedCatalogueOrder - 1;
  }

  static String buildCatalogueOrderSignature(Library library) {
    final orderedKeys = SearchCatalogueOrderHelper.buildOrderedKeys(
      library,
      keyOf: (book) => catalogueOrderKey(book as Book),
    );
    return sha1.convert(utf8.encode(orderedKeys.join('\n'))).toString();
  }

  static String catalogueOrderKey(Book book) {
    if (book.externalLibraryId != null && book.externalLibraryId!.isNotEmpty) {
      return 'ext:${book.externalLibraryId}';
    }

    if (book.id != null) {
      return 'id:${book.id}';
    }

    final categoryKey = book.category?.path ?? book.categoryPath ?? '';
    final fileTypeKey = book.fileType ?? book.runtimeType.toString();
    final pathKey = book is FileBook ? book.path : (book.filePath ?? '');
    return '${book.title}|$categoryKey|$fileTypeKey|$pathKey';
  }

  static String buildIndexedBookFilePath(Book book) {
    if (book is PdfBook) {
      return book.path;
    }
    return catalogueOrderKey(book);
  }

  /// Indexes a specific list of books (e.g. newly added personal books).
  ///
  /// מבצע אינדוקס ומחזיר true אם הסתיים בהצלחה, false אם בוטל
  Future<bool> indexBooks(
    List<Book> books,
    Library library, {
    void Function()? onActualIndexingStarted,
    required void Function(int processed, int total) onProgress,
  }) async {
    if (books.isEmpty) return true;

    _tantivyDataProvider.isIndexing.value = true;
    final isolateService =
        _isolateService ?? await IndexingIsolateService.create();
    _activeIsolateService = isolateService;

    if (await requiresManualReindex(library)) {
      _tantivyDataProvider.isIndexing.value = false;
      return false;
    }

    // בנה מפת סדר קטלוג מהספרייה הטרייה שהועברה כפרמטר
    // חשוב: משתמשים בספרייה המלאה כדי שהסדר הגלובלי יהיה נכון לכל הספרים
    final catalogueOrderByBookKey = SearchCatalogueOrderHelper.buildKeyOrderMap(
      library,
      keyOf: (book) => catalogueOrderKey(book as Book),
    );

    final totalBooks = books.length;
    int processedBooks = 0;
    int actuallyIndexed = 0;
    int errors = 0;
    bool cancelled = false;
    var didStartActualIndexing = false;

    try {
      // לא קוראים ל-ensureIndexStateMatchesCatalogue כאן בכוונה:
      // indexBooks מוסיף ספרים חדשים לאינדקס קיים תקין.
      // ניהול חתימת הקטלוג ואיפוס מלא הם אחריות indexAllBooks שרץ בסטארטאפ.
      for (final book in books) {
        if (!_tantivyDataProvider.isIndexing.value) {
          cancelled = true;
          break;
        }

        try {
          final indexedBookKey = catalogueOrderKey(book);
          if (book is TextBook) {
            if (!_tantivyDataProvider.booksDone.contains(indexedBookKey)) {
              debugPrint('📖 מאנדקס ספר טקסט חדש: ${book.title}');
              await _indexTextBook(
                book,
                isolateService,
                catalogueOrderByBookKey: catalogueOrderByBookKey,
                onActualIndexingStarted: () {
                  if (didStartActualIndexing) return;
                  didStartActualIndexing = true;
                  onActualIndexingStarted?.call();
                },
              );
              if (!_tantivyDataProvider.isIndexing.value) {
                cancelled = true;
                break;
              }
              _tantivyDataProvider.booksDone.add(indexedBookKey);
              actuallyIndexed++;
            }
          } else if (book is PdfBook) {
            if (!_tantivyDataProvider.booksDone.contains(indexedBookKey)) {
              debugPrint('📄 מאנדקס PDF חדש: ${book.title}');
              await _indexPdfBook(
                book,
                isolateService,
                catalogueOrderByBookKey: catalogueOrderByBookKey,
                onActualIndexingStarted: () {
                  if (didStartActualIndexing) return;
                  didStartActualIndexing = true;
                  onActualIndexingStarted?.call();
                },
              );
              if (!_tantivyDataProvider.isIndexing.value) {
                cancelled = true;
                break;
              }
              _tantivyDataProvider.booksDone.add(indexedBookKey);
              actuallyIndexed++;
            }
          }

          processedBooks++;
          onProgress(processedBooks, totalBooks);
        } catch (e) {
          debugPrint('❌ שגיאה באינדוקס של ${book.title}: $e');
          errors++;
          processedBooks++;
          onProgress(processedBooks, totalBooks);
        }

        await Future.delayed(Duration.zero);
      }

      if (!cancelled) {
        debugPrint(
            '✅ אינדוקס ספרים ספציפיים הושלם! (מאונדקסים: $actuallyIndexed, שגיאות: $errors)');
        final index = await _tantivyDataProvider.engine;
        await index.commit();
        saveIndexedBooks();
      }
    } finally {
      _activeIsolateService = null;
      if (!identical(isolateService, _isolateService)) {
        await isolateService.dispose();
      }
      _tantivyDataProvider.isIndexing.value = false;
    }
    return !cancelled;
  }

  /// Cancels the ongoing indexing process.
  void cancelIndexing() {
    _tantivyDataProvider.isIndexing.value = false;
    unawaited(_activeIsolateService?.cancelActiveWork());
  }

  /// Persists the list of indexed books to disk.
  void saveIndexedBooks() {
    _tantivyDataProvider.saveBooksDoneToDisk();
  }

  /// Clears the index and resets the list of indexed books.
  Future<void> clearIndex() async {
    await _tantivyDataProvider.clear();
  }

  /// Gets the list of books that have already been indexed.
  List<String> getIndexedBooks() {
    return List<String>.from(_tantivyDataProvider.booksDone);
  }

  /// Returns true for book types that the indexer actually processes.
  /// Non-indexable types (ExternalLibraryBook, DocxBook, etc.) are silently
  /// skipped by indexAllBooks, so they must be excluded from status checks.
  static bool isIndexableBook(Book book) => book is TextBook || book is PdfBook;

  /// Waits until the underlying data provider is fully initialized
  /// (booksDone loaded from disk).
  Future<void> awaitReady() async {
    await _tantivyDataProvider.engine;
  }

  /// Checks if indexing is currently in progress.
  bool isIndexing() {
    return _tantivyDataProvider.isIndexing.value;
  }
}

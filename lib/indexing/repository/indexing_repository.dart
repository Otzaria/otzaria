import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/indexing/services/indexing_isolate_service.dart';

class IndexingRepository {
  final TantivyDataProvider _tantivyDataProvider;
  final IndexingIsolateService? _isolateService;
  IndexingIsolateService? _activeIsolateService;
  int _docIdSequence = 0;

  IndexingRepository(this._tantivyDataProvider,
      {IndexingIsolateService? isolateService})
      : _isolateService = isolateService;

  BigInt _nextDocumentId() {
    _docIdSequence++;
    return (BigInt.from(DateTime.now().microsecondsSinceEpoch) << 20) +
        BigInt.from(_docIdSequence);
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

    final allBooks = library.getAllBooks();
    final totalBooks = allBooks.length;
    bool cancelled = false;
    var didStartActualIndexing = false;

    try {
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
          if (book is TextBook) {
            if (!_tantivyDataProvider.booksDone
                .contains("${book.title}textBook")) {
              debugPrint('📖 מאנדקס ספר טקסט ב-isolate: ${book.title}');
              await _indexTextBook(
                book,
                isolateService,
                onActualIndexingStarted: () {
                  if (didStartActualIndexing) {
                    return;
                  }
                  didStartActualIndexing = true;
                  onActualIndexingStarted?.call();
                },
              );
              _tantivyDataProvider.booksDone.add("${book.title}textBook");
              actuallyIndexed++;
            } else {
              debugPrint('⏭️ דילוג על ספר טקסט שכבר מאונדקס: ${book.title}');
              skipped++;
            }
          } else if (book is PdfBook) {
            if (!_tantivyDataProvider.booksDone
                .contains("${book.title}pdfBook")) {
              debugPrint('📄 מאנדקס PDF ב-isolate: ${book.title}');
              await _indexPdfBook(
                book,
                isolateService,
                onActualIndexingStarted: () {
                  if (didStartActualIndexing) {
                    return;
                  }
                  didStartActualIndexing = true;
                  onActualIndexingStarted?.call();
                },
              );
              _tantivyDataProvider.booksDone.add("${book.title}pdfBook");
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

  Future<void> _indexTextBook(
    TextBook book,
    IndexingIsolateService isolateService, {
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
      onActualIndexingStarted: onActualIndexingStarted,
    );
  }

  Future<void> _indexPdfBook(
    PdfBook book,
    IndexingIsolateService isolateService, {
    void Function()? onActualIndexingStarted,
  }) async {
    final stream = await isolateService.processPdfBook(
      title: book.title,
      path: book.path,
    );
    await _consumePreparedDocuments(
      book: book,
      stream: stream,
      isolateService: isolateService,
      onActualIndexingStarted: onActualIndexingStarted,
    );
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
    void Function()? onActualIndexingStarted,
  }) async {
    if (documents.isEmpty) {
      return;
    }

    onActualIndexingStarted?.call();

    final index = await _tantivyDataProvider.engine;
    final title = book.title;
    final topics = _buildTopicsPath(book);
    final isPdf = book is PdfBook;
    final filePath = isPdf ? book.path : '';

    for (final document in documents) {
      if (!_tantivyDataProvider.isIndexing.value) {
        return;
      }

      await index.addDocument(
        id: _nextDocumentId(),
        title: title,
        reference: document.reference,
        topics: topics,
        text: document.text,
        segment: BigInt.from(document.segment),
        isPdf: isPdf,
        filePath: filePath,
      );
    }
  }

  String _buildTopicsPath(Book book) {
    final topics = "/${book.topics.replaceAll(', ', '/')}";
    return '$topics/${book.title}';
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

  /// Checks if indexing is currently in progress.
  bool isIndexing() {
    return _tantivyDataProvider.isIndexing.value;
  }
}

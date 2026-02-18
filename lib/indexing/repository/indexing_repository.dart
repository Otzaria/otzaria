import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/text_manipulation.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:otzaria/utils/ref_helper.dart';

class IndexingRepository {
  final TantivyDataProvider _tantivyDataProvider;

  IndexingRepository(this._tantivyDataProvider);

  static final RegExp _pdfInvisibleChars = RegExp(
    r'[\u200B-\u200F\u202A-\u202E\u2066-\u2069]'
    r'|\uFEFF',
  );

  static final RegExp _pdfLettersAndDigits =
      RegExp(r'[\u05D0-\u05EAa-zA-Z0-9]');
  static final RegExp _pdfNonLettersNonSpace =
      RegExp(r'[^\s\u05D0-\u05EAa-zA-Z0-9]');

  static String _normalizePdfTextForIndexing(String input) {
    var text = stripHtmlIfNeeded(input);
    text = text.replaceAll(_pdfInvisibleChars, '');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    text = removeVolwels(text);
    return text;
  }

  static bool _isProbablyGarbagePdfText(String normalizedText) {
    final compact = normalizedText.replaceAll(RegExp(r'\s+'), '');
    if (compact.isEmpty) return true;

    final letters = _pdfLettersAndDigits.allMatches(compact).length;
    if (letters == 0) return true;

    final nonLetters = _pdfNonLettersNonSpace.allMatches(compact).length;
    final ratioLetters = letters / compact.length;

    // Heuristic: dot/bullet/garbage glyph-mapped text tends to be mostly
    // punctuation/symbols with very few letters.
    if (compact.length >= 50 && ratioLetters < 0.10) return true;
    if (compact.length >= 20 && ratioLetters < 0.20 && nonLetters > letters) {
      return true;
    }

    return false;
  }

  /// Indexes all books in the provided library.
  ///
  /// [library] The library containing books to index
  /// [onProgress] Callback function to report progress
  Future<void> indexAllBooks(
    Library library,
    void Function(int processed, int total) onProgress,
  ) async {
    _tantivyDataProvider.isIndexing.value = true;
    final allBooks = library.getAllBooks();

    // Filter out books with externalLibraryId (external library books should not be indexed)
    final booksToIndex =
        allBooks.where((book) => book.externalLibraryId == null).toList();

    final totalBooks = booksToIndex.length;
    int processedBooks = 0;

    for (Book book in booksToIndex) {
      // Check if indexing was cancelled
      if (!_tantivyDataProvider.isIndexing.value) {
        return;
      }

      try {
        // Check if this book has already been indexed
        if (book is TextBook) {
          if (!_tantivyDataProvider.booksDone
              .contains("${book.title}textBook")) {
            if (_tantivyDataProvider.booksDone.contains(
                sha1.convert(utf8.encode((await book.text))).toString())) {
              _tantivyDataProvider.booksDone.add("${book.title}textBook");
            } else {
              await _indexTextBook(book);
              _tantivyDataProvider.booksDone.add("${book.title}textBook");
            }
          }
        } else if (book is PdfBook) {
          if (!_tantivyDataProvider.booksDone
              .contains("${book.title}pdfBook")) {
            // Try to get file hash for deduplication
            String? fileHash;
            try {
              // Try to load from database first
              final pdfBytes =
                  await SqliteDataProvider.instance.getPdfBytesFromDb(book);
              if (pdfBytes != null && pdfBytes.isNotEmpty) {
                fileHash = sha1.convert(pdfBytes).toString();
              } else {
                // Fallback to file if exists
                final file = File(book.path);
                if (await file.exists()) {
                  fileHash = sha1.convert(await file.readAsBytes()).toString();
                }
              }
            } catch (e) {
              debugPrint('⚠️ Could not compute hash for ${book.title}: $e');
            }

            if (fileHash != null &&
                _tantivyDataProvider.booksDone.contains(fileHash)) {
              _tantivyDataProvider.booksDone.add("${book.title}pdfBook");
            } else {
              await _indexPdfBook(book);
              _tantivyDataProvider.booksDone.add("${book.title}pdfBook");
            }
          }
        } else if (book is ExternalLibraryBook) {
          if (!_tantivyDataProvider.booksDone
              .contains("${book.title}externalBook")) {
            final idHash = sha1.convert(utf8.encode(book.link)).toString();
            if (_tantivyDataProvider.booksDone.contains(idHash)) {
              _tantivyDataProvider.booksDone.add("${book.title}externalBook");
            } else {
              await _indexExternalLibraryBook(book);
              _tantivyDataProvider.booksDone.add("${book.title}externalBook");
            }
          }
        }
        processedBooks++;
        // Report progress
        onProgress(processedBooks, totalBooks);
      } catch (e) {
        // Use async error handling to prevent event loop blocking
        await Future.microtask(() {
          debugPrint('Error adding ${book.title} to index: $e');
        });
        processedBooks++;
        // Still report progress even after error
        onProgress(processedBooks, totalBooks);
        // Yield control back to event loop after error
        await Future.delayed(Duration.zero);
      }

      await Future.delayed(Duration.zero);
    }

    // Reset indexing flag after completion
    _tantivyDataProvider.isIndexing.value = false;
  }

  /// Indexes a text-based book by processing its content and adding it to the search index.
  Future<void> _indexTextBook(TextBook book) async {
    final index = await _tantivyDataProvider.engine;
    var text = await book.text;
    final title = book.title;
    final topics = "/${book.topics.replaceAll(', ', '/')}";

    final texts = text.split('\n');
    List<String> reference = [];

    // Index each line separately
    for (int i = 0; i < texts.length; i++) {
      if (!_tantivyDataProvider.isIndexing.value) {
        return;
      }

      // Yield control periodically to prevent blocking
      if (i % 100 == 0) {
        await Future.delayed(Duration.zero);
      }

      String line = texts[i];
      // get the reference from the headers
      if (line.startsWith('<h')) {
        if (reference.isNotEmpty &&
            reference.any(
                (element) => element.substring(0, 4) == line.substring(0, 4))) {
          reference.removeRange(
              reference.indexWhere(
                  (element) => element.substring(0, 4) == line.substring(0, 4)),
              reference.length);
        }
        reference.add(line);

        // Index the header also into the main search index so in-book search
        // can find headings that are displayed and highlighted.
        var headerLine = stripHtmlIfNeeded(line);
        headerLine = removeVolwels(headerLine);
        index.addDocument(
            id: BigInt.from(DateTime.now().microsecondsSinceEpoch),
            title: title,
            reference: stripHtmlIfNeeded(reference.join(', ')),
            topics: '$topics/$title',
            text: headerLine,
            segment: BigInt.from(i),
            isPdf: false,
            filePath: '');
      } else {
        line = stripHtmlIfNeeded(line);
        line = removeVolwels(line);

        // Add to search index
        index.addDocument(
            id: BigInt.from(DateTime.now().microsecondsSinceEpoch),
            title: title,
            reference: stripHtmlIfNeeded(reference.join(', ')),
            topics: '$topics/$title',
            text: line,
            segment: BigInt.from(i),
            isPdf: false,
            filePath: '');
      }
    }

    await index.commit();
    saveIndexedBooks();
  }

  /// Indexes an external library book (e.g., Otzar) by indexing its metadata
  /// so the book becomes discoverable in searches.
  Future<void> _indexExternalLibraryBook(ExternalLibraryBook book) async {
    final index = await _tantivyDataProvider.engine;

    final title = book.title;
    final topics = "/${book.topics.replaceAll(', ', '/')}";

    // Combine available metadata into a single text blob for indexing
    final parts = <String>[];
    parts.add(title);
    if (book.author != null) parts.add(book.author!);
    if (book.heShortDesc != null) parts.add(book.heShortDesc!);
    if (book.heDesc != null) parts.add(book.heDesc!);
    if (book.link.isNotEmpty) parts.add(book.link);
    if (book.topics.isNotEmpty) parts.add(book.topics);

    var combined = parts.where((p) => p.isNotEmpty).join(' — ');
    combined = stripHtmlIfNeeded(combined);
    combined = removeVolwels(combined);

    index.addDocument(
      id: BigInt.from(DateTime.now().microsecondsSinceEpoch),
      title: title,
      reference: '',
      topics: '$topics/$title',
      text: combined,
      segment: BigInt.from(0),
      isPdf: false,
      filePath: book.link,
    );

    await index.commit();
    saveIndexedBooks();
  }

  /// Indexes a PDF book by extracting and processing text from each page.
  Future<void> _indexPdfBook(PdfBook book) async {
    final index = await _tantivyDataProvider.engine;

    debugPrint('📚 PDF indexing started: "${book.title}" (${book.path})');

    // Try to load PDF from database first, then fall back to file
    PdfDocument? document;
    try {
      final pdfBytes =
          await SqliteDataProvider.instance.getPdfBytesFromDb(book);
      if (pdfBytes != null && pdfBytes.isNotEmpty) {
        debugPrint('📚 Loading PDF from database for: ${book.title}');
        document = await PdfDocument.openData(pdfBytes);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load PDF from database: $e');
    }

    // Fallback to file if database load failed
    if (document == null) {
      final file = File(book.path);
      if (await file.exists()) {
        debugPrint('📚 Loading PDF from file: ${book.path}');
        document = await PdfDocument.openFile(book.path);
      } else {
        debugPrint('❌ PDF not found in database or file system: ${book.path}');
        return;
      }
    }

    final pages = document.pages;
    final outline = await document.loadOutline();
    final title = book.title;
    final topics = "/${book.topics.replaceAll(', ', '/')}";

    debugPrint(
        '📚 PDF outline items: ${outline.length}, pages: ${pages.length}');

    // Process each page
    var addedAnyInBook = false;
    for (int i = 0; i < pages.length; i++) {
      if (!_tantivyDataProvider.isIndexing.value) {
        return;
      }

      final pageText = await pages[i].loadText();
      final rawLines = pageText?.fullText.split('\n') ?? const <String>[];

      final bookmark = await refFromPageNumber(i + 1, outline, title);
      final ref = bookmark.isNotEmpty
          ? '$title, $bookmark, עמוד ${i + 1}'
          : '$title, עמוד ${i + 1}';

      var addedAny = false;
      for (int j = 0; j < rawLines.length; j++) {
        if (!_tantivyDataProvider.isIndexing.value) {
          return;
        }

        // Yield control periodically to prevent blocking
        if (j % 50 == 0) {
          await Future.delayed(Duration.zero);
        }

        final normalized = _normalizePdfTextForIndexing(rawLines[j]);
        if (_isProbablyGarbagePdfText(normalized)) {
          continue;
        }

        index.addDocument(
          id: BigInt.from(DateTime.now().microsecondsSinceEpoch),
          title: title,
          reference: ref,
          topics: '$topics/$title',
          text: normalized,
          segment: BigInt.from(i),
          isPdf: true,
          filePath: book.path,
        );
        addedAny = true;
        addedAnyInBook = true;
      }

      if (!addedAny && kDebugMode) {
        debugPrint(
          '⚠️ PDF page ${i + 1}: skipped (no usable extracted text) file: ${book.path}',
        );
      }
    }

    // Fallback: some PDFs have no usable text layer, but ship alongside a
    // plain-text OCR dump. If the PDF extraction produced nothing usable,
    // try indexing a sidecar .txt so the book is still searchable.
    if (!addedAnyInBook) {
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

      if (sidecar != null) {
        final ocrText = await sidecar.readAsString();
        final pagesText =
            ocrText.contains('\f') ? ocrText.split('\f') : <String>[ocrText];

        for (int pageIndex = 0; pageIndex < pagesText.length; pageIndex++) {
          if (!_tantivyDataProvider.isIndexing.value) {
            return;
          }

          final bookmark =
              await refFromPageNumber(pageIndex + 1, outline, title);
          final ref = bookmark.isNotEmpty
              ? '$title, $bookmark, עמוד ${pageIndex + 1}'
              : '$title, עמוד ${pageIndex + 1}';

          final lines = pagesText[pageIndex].split('\n');
          for (int j = 0; j < lines.length; j++) {
            if (!_tantivyDataProvider.isIndexing.value) {
              return;
            }
            if (j % 50 == 0) {
              await Future.delayed(Duration.zero);
            }

            final normalized = _normalizePdfTextForIndexing(lines[j]);
            if (_isProbablyGarbagePdfText(normalized)) {
              continue;
            }

            index.addDocument(
              id: BigInt.from(DateTime.now().microsecondsSinceEpoch),
              title: title,
              reference: ref,
              topics: '$topics/$title',
              text: normalized,
              segment: BigInt.from(pageIndex),
              isPdf: true,
              filePath: book.path,
            );
            addedAnyInBook = true;
          }
        }

        if (kDebugMode) {
          debugPrint(
            'ℹ️ Indexed PDF from sidecar text: ${sidecar.path} (pdf: ${book.path})',
          );
        }
      }
    }

    await index.commit();
    saveIndexedBooks();
  }

  /// Cancels the ongoing indexing process.
  void cancelIndexing() {
    _tantivyDataProvider.isIndexing.value = false;
  }

  /// Persists the list of indexed books to disk.
  void saveIndexedBooks() {
    _tantivyDataProvider.saveBooksDoneToDisk();
  }

  /// Clears the index and resets the list of indexed books.
  Future<void> clearIndex() async {
    _tantivyDataProvider.clear();
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

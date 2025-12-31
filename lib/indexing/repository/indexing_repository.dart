import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/text_manipulation.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:otzaria/utils/ref_helper.dart';
import 'package:search_engine/search_engine.dart';

class IndexingRepository {
  final TantivyDataProvider _tantivyDataProvider;

  IndexingRepository(this._tantivyDataProvider);

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
    final totalBooks = allBooks.length;
    int processedBooks = 0;

    for (Book book in allBooks) {
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
            if (_tantivyDataProvider.booksDone.contains(
                sha1.convert(await File(book.path).readAsBytes()).toString())) {
              _tantivyDataProvider.booksDone.add("${book.title}pdfBook");
            } else {
              await _indexPdfBook(book);
              _tantivyDataProvider.booksDone.add("${book.title}pdfBook");
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

  /// Indexes a text-based book by processing its content and adding it to the search index and reference index.
  Future<void> _indexTextBook(TextBook book) async {
    final index = await _tantivyDataProvider.engine;
    final refIndex = await _tantivyDataProvider.refEngine;
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

        // Index the header as a reference
        String refText = stripHtmlIfNeeded(reference.join(" "));
        // שומרים את ה-reference המקורי ללא עיבוד
        // הנרמול יתבצע בשלב החיפוש, לא באינדקס

        refIndex.addDocument(
            id: BigInt.from(DateTime.now().microsecondsSinceEpoch),
            title: title,
            reference: refText,
            shortRef: refText, // שומרים את המקור
            segment: BigInt.from(i),
            isPdf: false,
            filePath: '');

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
    await refIndex.commit();
    saveIndexedBooks();
  }

  /// Indexes a PDF book by extracting and processing text from each page.
  Future<void> _indexPdfBook(PdfBook book) async {
    final index = await _tantivyDataProvider.engine;
    final refIndex = await _tantivyDataProvider.refEngine;

    debugPrint('?? PDF indexing started: "${book.title}" (${book.path})');

    // Extract text from each page
    final document = await PdfDocument.openFile(book.path);
    final pages = document.pages;
    final outline = await document.loadOutline();
    final title = book.title;
    final topics = "/${book.topics.replaceAll(', ', '/')}";

    debugPrint(
        '?? PDF outline items: ${outline.length}, pages: ${pages.length}');

    // Index the PDF outline (headings) as references so find-ref can surface them
    if (outline.isNotEmpty) {
      // קודם נוסיף ערך לשם הספר עצמו (depth 1)
      refIndex.addDocument(
        id: BigInt.from(DateTime.now().microsecondsSinceEpoch),
        title: title,
        reference: title,
        shortRef: title,
        segment: BigInt.from(1),
        isPdf: true,
        filePath: book.path,
      );
      debugPrint('✅ Added PDF book root: "$title" file: ${book.path}');

      await _indexPdfOutline(
        outline,
        title,
        book.path,
        refIndex,
      );
    }

    // Process each page
    for (int i = 0; i < pages.length; i++) {
      final pageText = await pages[i].loadText();
      final texts = pageText?.fullText.split('\n') ?? [];
      // Index each line from the page
      for (int j = 0; j < texts.length; j++) {
        if (!_tantivyDataProvider.isIndexing.value) {
          return;
        }

        // Yield control periodically to prevent blocking
        if (j % 50 == 0) {
          await Future.delayed(Duration.zero);
        }
        final bookmark = await refFromPageNumber(i + 1, outline, title);
        final ref = bookmark.isNotEmpty
            ? '$title, $bookmark, עמוד ${i + 1}'
            : '$title, עמוד ${i + 1}';
        index.addDocument(
            id: BigInt.from(DateTime.now().microsecondsSinceEpoch),
            title: title,
            reference: ref,
            topics: '$topics/$title',
            text: texts[j],
            segment: BigInt.from(i),
            isPdf: true,
            filePath: book.path);
      }
    }

    await index.commit();
    await refIndex.commit();
    saveIndexedBooks();
  }

  /// Index PDF outline (bookmarks/headings) recursively into the reference index.
  Future<void> _indexPdfOutline(
    List<PdfOutlineNode> outline,
    String bookTitle,
    String filePath,
    ReferenceSearchEngine refIndex, {
    String parentRef = '',
  }) async {
    debugPrint(
        '?? Indexing PDF outline level (parent="$parentRef") with ${outline.length} nodes');

    for (final node in outline) {
      if (!_tantivyDataProvider.isIndexing.value) {
        return;
      }

      final nodeTitle = node.title.trim().replaceAll('\n', ' ');
      debugPrint(
          '?? Outline node: "$nodeTitle" (children: ${node.children.length}, dest: ${node.dest?.pageNumber})');
      if (nodeTitle.isEmpty) {
        // Still traverse children to avoid losing deeper headings
        if (node.children.isNotEmpty) {
          await _indexPdfOutline(
            node.children,
            bookTitle,
            filePath,
            refIndex,
            parentRef: parentRef,
          );
        }
        continue;
      }

      final isDuplicateRoot = parentRef.isEmpty &&
          nodeTitle.toLowerCase() == bookTitle.toLowerCase();
      final baseRef = parentRef.isEmpty ? bookTitle : parentRef;
      final currentRef = isDuplicateRoot ? baseRef : '$baseRef, $nodeTitle';
      final pageNumber = node.dest?.pageNumber ?? 1;

      // Only add navigable headings (ones with a destination)
      if (node.dest != null && pageNumber > 0 && !isDuplicateRoot) {
        // שומרים את ה-reference המקורי ללא עיבוד
        // הנרמול יתבצע בשלב החיפוש, לא באינדקס
        refIndex.addDocument(
          id: BigInt.from(DateTime.now().microsecondsSinceEpoch),
          title: bookTitle,
          reference: currentRef,
          shortRef: currentRef, // שומרים את המקור
          segment: BigInt.from(pageNumber),
          isPdf: true,
          filePath: filePath,
        );
        debugPrint(
            '✅ Added PDF outline ref: "$currentRef" (page $pageNumber) file: $filePath');
      }

      // Recursively index children
      if (node.children.isNotEmpty) {
        await _indexPdfOutline(
          node.children,
          bookTitle,
          filePath,
          refIndex,
          parentRef: currentRef,
        );
      }

      // Yield to event loop periodically
      await Future.delayed(Duration.zero);
    }
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

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/text_manipulation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:otzaria/utils/ref_helper.dart';

class IndexingRepository {
  final TantivyDataProvider _tantivyDataProvider;
  int _docIdSequence = 0;

  IndexingRepository(this._tantivyDataProvider);

  static final RegExp _pdfInvisibleChars = RegExp(
    r'[\u200B-\u200F\u202A-\u202E\u2066-\u2069]'
    r'|\uFEFF',
  );

  static final RegExp _pdfLettersAndDigits =
      RegExp(r'[\u05D0-\u05EAa-zA-Z0-9]');
  static final RegExp _pdfNonLettersNonSpace =
      RegExp(r'[^\s\u05D0-\u05EAa-zA-Z0-9]');

  BigInt _nextDocumentId() {
    _docIdSequence++;
    return (BigInt.from(DateTime.now().microsecondsSinceEpoch) << 20) +
        BigInt.from(_docIdSequence);
  }

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
    int actuallyIndexed = 0;
    int skipped = 0;
    int errors = 0;

    debugPrint('📚 התחלת אינדוקס: $totalBooks ספרים');
    debugPrint(
        '📊 ספרים שכבר מאונדקסים: ${_tantivyDataProvider.booksDone.length}');

    for (Book book in booksToIndex) {
      // Check if indexing was cancelled
      if (!_tantivyDataProvider.isIndexing.value) {
        debugPrint('⚠️ אינדוקס בוטל על ידי המשתמש');
        return;
      }

      try {
        // Check if this book has already been indexed
        if (book is TextBook) {
          if (!_tantivyDataProvider.booksDone
              .contains("${book.title}textBook")) {
            final bookText = await book.text;
            final textHash = sha1.convert(utf8.encode(bookText)).toString();

            if (_tantivyDataProvider.booksDone.contains(textHash)) {
              debugPrint('⏭️ דילוג על ספר קיים (hash): ${book.title}');
              _tantivyDataProvider.booksDone.add("${book.title}textBook");
              skipped++;
            } else {
              debugPrint('📖 מאנדקס ספר טקסט: ${book.title}');
              await _indexTextBook(book, preloadedText: bookText);
              _tantivyDataProvider.booksDone.add("${book.title}textBook");
              _tantivyDataProvider.booksDone.add(textHash);
              actuallyIndexed++;
            }
          } else {
            debugPrint('⏭️ דילוג על ספר טקסט שכבר מאונדקס: ${book.title}');
            skipped++;
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
              debugPrint('⚠️ לא ניתן לחשב hash עבור ${book.title}: $e');
            }

            if (fileHash != null &&
                _tantivyDataProvider.booksDone.contains(fileHash)) {
              debugPrint('⏭️ דילוג על PDF קיים (hash): ${book.title}');
              _tantivyDataProvider.booksDone.add("${book.title}pdfBook");
              skipped++;
            } else {
              debugPrint('📄 מאנדקס PDF: ${book.title}');
              await _indexPdfBook(book);
              _tantivyDataProvider.booksDone.add("${book.title}pdfBook");
              if (fileHash != null) {
                _tantivyDataProvider.booksDone.add(fileHash);
              }
              actuallyIndexed++;
            }
          } else {
            debugPrint('⏭️ דילוג על PDF שכבר מאונדקס: ${book.title}');
            skipped++;
          }
        } else if (book is ExternalLibraryBook) {
          if (!_tantivyDataProvider.booksDone
              .contains("${book.title}externalBook")) {
            final idHash = sha1.convert(utf8.encode(book.link)).toString();
            if (_tantivyDataProvider.booksDone.contains(idHash)) {
              debugPrint('⏭️ דילוג על ספר חיצוני קיים (hash): ${book.title}');
              _tantivyDataProvider.booksDone.add("${book.title}externalBook");
              skipped++;
            } else {
              debugPrint('🔗 מאנדקס ספר חיצוני: ${book.title}');
              await _indexExternalLibraryBook(book);
              _tantivyDataProvider.booksDone.add("${book.title}externalBook");
              _tantivyDataProvider.booksDone.add(idHash);
              actuallyIndexed++;
            }
          } else {
            debugPrint('⏭️ דילוג על ספר חיצוני שכבר מאונדקס: ${book.title}');
            skipped++;
          }
        }
        processedBooks++;

        // Commit every 25 books to save progress (optimized for 8GB RAM)
        if (processedBooks % 25 == 0) {
          debugPrint('💾 שומר אינדקס (commit)...');
          final index = await _tantivyDataProvider.engine;
          await index.commit();
          saveIndexedBooks();
        }

        // Report progress every 50 books
        if (processedBooks % 50 == 0) {
          debugPrint(
              '📈 התקדמות: $processedBooks/$totalBooks (מאונדקסים: $actuallyIndexed, דולגו: $skipped, שגיאות: $errors)');
        }

        // Report progress
        onProgress(processedBooks, totalBooks);
      } catch (e) {
        // Use async error handling to prevent event loop blocking
        await Future.microtask(() {
          debugPrint('❌ שגיאה באינדוקס של ${book.title}: $e');
        });
        errors++;
        processedBooks++;
        // Still report progress even after error
        onProgress(processedBooks, totalBooks);
        // Yield control back to event loop after error
        await Future.delayed(Duration.zero);
      }

      await Future.delayed(Duration.zero);
    }

    debugPrint('✅ אינדוקס הושלם!');
    debugPrint('   📊 סה"כ: $totalBooks ספרים');
    debugPrint('   ✅ מאונדקסים: $actuallyIndexed');
    debugPrint('   ⏭️ דולגו: $skipped');
    debugPrint('   ❌ שגיאות: $errors');

    // Final commit to ensure everything is saved
    debugPrint('💾 שומר אינדקס סופי (final commit)...');
    final index = await _tantivyDataProvider.engine;
    await index.commit();
    saveIndexedBooks();
    debugPrint('✅ אינדקס נשמר בהצלחה!');

    // Reset indexing flag after completion
    _tantivyDataProvider.isIndexing.value = false;
  }

  /// Indexes a text-based book by processing its content and adding it to the search index.
  Future<void> _indexTextBook(TextBook book, {String? preloadedText}) async {
    final index = await _tantivyDataProvider.engine;

    try {
      // Try to get text directly from DB if we have categoryId
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

      // Fallback to regular method
      if (text == null || text.isEmpty) {
        debugPrint('   🔍 מנסה לקרוא דרך LibraryProvider: ${book.title}');
        final bookText = await book.text;
        text = bookText;
      }

      if (text.isEmpty) {
        debugPrint(
            '⚠️ ספר ריק: ${book.title} (categoryId: ${book.categoryId}) - מדלג');
        return;
      }

      final title = book.title;
      final topics = "/${book.topics.replaceAll(', ', '/')}";

      final texts = text.split('\n');

      if (texts.length <= 1) {
        debugPrint(
            'ℹ️ ספר קצר: ${book.title} (${texts.length} שורות) - מאנדקס כרגיל');
      }

      List<String> reference = [];

      debugPrint('   📝 מאנדקס ${texts.length} שורות מ-$title');

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
              reference.any((element) =>
                  element.substring(0, 4) == line.substring(0, 4))) {
            reference.removeRange(
                reference.indexWhere((element) =>
                    element.substring(0, 4) == line.substring(0, 4)),
                reference.length);
          }
          reference.add(line);

          // Index the header also into the main search index so in-book search
          // can find headings that are displayed and highlighted.
          var headerLine = stripHtmlIfNeeded(line);
          headerLine = removeVolwels(headerLine);
          index.addDocument(
              id: _nextDocumentId(),
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
              id: _nextDocumentId(),
              title: title,
              reference: stripHtmlIfNeeded(reference.join(', ')),
              topics: '$topics/$title',
              text: line,
              segment: BigInt.from(i),
              isPdf: false,
              filePath: '');
        }
      }

      // Don't commit after every book - too slow!
      // We'll commit periodically in indexAllBooks instead
      debugPrint('   ✅ סיים אינדוקס של $title (${texts.length} שורות)');
    } catch (e) {
      debugPrint('❌ שגיאה באינדוקס של ${book.title}: $e');
      rethrow;
    }
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
      id: _nextDocumentId(),
      title: title,
      reference: '',
      topics: '$topics/$title',
      text: combined,
      segment: BigInt.from(0),
      isPdf: false,
      filePath: book.link,
    );

    // Don't commit after every book - too slow!
    debugPrint('   ✅ סיים אינדוקס של ספר חיצוני: $title');
  }

  /// Indexes a PDF book by extracting and processing text from each page.
  Future<void> _indexPdfBook(PdfBook book) async {
    final index = await _tantivyDataProvider.engine;
    final startTime = DateTime.now();

    debugPrint('📚 PDF indexing started: "${book.title}" (${book.path})');

    // Try to load PDF from file first (much faster!), then fall back to database
    PdfDocument? document;
    File? tempFileCreatedByUs;
    try {
      final file = File(book.path);

      if (await file.exists()) {
        final fileSize = await file.length();
        debugPrint('   📁 מנסה לטעון מקובץ: ${book.path}');
        debugPrint(
            '   📊 גודל קובץ: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');

        try {
          final openStartTime = DateTime.now();
          debugPrint('   ⏳ פותח PDF מקובץ...');

          document = await PdfDocument.openFile(book.path)
              .timeout(Duration(seconds: 60), onTimeout: () {
            final elapsed = DateTime.now().difference(openStartTime).inSeconds;
            debugPrint(
                '   ⏱️ טיימאאוט בפתיחת PDF מקובץ אחרי $elapsed שניות: ${book.title}');
            throw TimeoutException(
                'PDF open timeout from file after $elapsed seconds');
          });

          final openElapsed =
              DateTime.now().difference(openStartTime).inSeconds;
          debugPrint('   ✅ PDF נפתח בהצלחה מקובץ (לקח $openElapsed שניות)');
        } catch (e, stackTrace) {
          debugPrint('   ❌ שגיאה בפתיחת PDF מקובץ: $e');
          debugPrint(
              '   Stack trace: ${stackTrace.toString().split('\n').take(3).join('\n')}');
          // Will try database below
        }
      } else {
        debugPrint('   ⚠️ קובץ PDF לא קיים: ${book.path}');
      }

      // Fallback to database if file load failed
      if (document == null) {
        Uint8List? pdfBytes;

        try {
          debugPrint('   🔍 מנסה לטעון PDF מ-DB: ${book.title}');
          pdfBytes = await SqliteDataProvider.instance.getPdfBytesFromDb(book);

          if (pdfBytes != null && pdfBytes.isNotEmpty) {
            debugPrint(
                '   ✅ נטען מ-DB: ${(pdfBytes.length / 1024 / 1024).toStringAsFixed(2)} MB');

            // Save to temporary file (like pdf_book_screen does)
            debugPrint('   💾 שומר לקובץ זמני...');
            final tempDir = await getTemporaryDirectory();
            final fileName =
                'pdf_index_${book.id ?? book.title.hashCode}_${_nextDocumentId()}.pdf';
            final tempFile = File('${tempDir.path}/$fileName');
            tempFileCreatedByUs = tempFile;

            await tempFile.writeAsBytes(pdfBytes, flush: true);
            debugPrint('   ✅ נשמר לקובץ זמני: ${tempFile.path}');

            // Now open from the temporary file
            debugPrint('   ⏳ פותח PDF מקובץ זמני...');
            final openStartTime = DateTime.now();

            document = await PdfDocument.openFile(tempFile.path)
                .timeout(Duration(seconds: 60), onTimeout: () {
              final elapsed =
                  DateTime.now().difference(openStartTime).inSeconds;
              debugPrint(
                  '   ⏱️ טיימאאוט בפתיחת PDF מקובץ זמני אחרי $elapsed שניות: ${book.title}');
              throw TimeoutException(
                  'PDF open timeout from temp file after $elapsed seconds');
            });

            final openElapsed =
                DateTime.now().difference(openStartTime).inSeconds;
            debugPrint(
                '   ✅ PDF נפתח בהצלחה מקובץ זמני (לקח $openElapsed שניות)');
          } else {
            debugPrint('   ⚠️ PDF לא נמצא ב-DB או ריק');
          }
        } catch (e, stackTrace) {
          debugPrint('   ❌ שגיאה בטעינה מ-DB: $e');
          debugPrint(
              '   Stack trace: ${stackTrace.toString().split('\n').take(3).join('\n')}');
        }
      }

      if (document == null) {
        debugPrint('   ❌ לא ניתן לפתוח את ה-PDF: ${book.title}');
        return;
      }

      final pages = document.pages;
      debugPrint('   ✅ PDF נפתח בהצלחה, מכיל ${pages.length} עמודים');
      debugPrint('   ⏳ טוען outline (סימניות)...');

      final outlineStartTime = DateTime.now();
      final outline = await document.loadOutline().timeout(
        Duration(seconds: 15),
        onTimeout: () {
          final elapsed = DateTime.now().difference(outlineStartTime).inSeconds;
          debugPrint('   ⏱️ טיימאאוט בטעינת outline אחרי $elapsed שניות');
          return <PdfOutlineNode>[];
        },
      );

      final outlineElapsed =
          DateTime.now().difference(outlineStartTime).inSeconds;
      debugPrint(
          '   ✅ outline נטען (${outline.length} סימניות, לקח $outlineElapsed שניות)');

      final title = book.title;
      final topics = "/${book.topics.replaceAll(', ', '/')}";

      // Process each page
      var addedAnyInBook = false;
      int totalLinesIndexed = 0;
      int pagesWithTimeout = 0;
      int pagesWithErrors = 0;

      debugPrint('   ⏳ מתחיל לעבד ${pages.length} עמודים...');

      for (int i = 0; i < pages.length; i++) {
        if (!_tantivyDataProvider.isIndexing.value) {
          debugPrint('   ⚠️ אינדוקס בוטל על ידי המשתמש בעמוד ${i + 1}');
          return;
        }

        // Report progress every 10 pages, and always for first page
        if (i % 10 == 0 || i == 0) {
          debugPrint(
              '   📄 מעבד עמוד ${i + 1}/${pages.length} של $title (מאונדקסו: $totalLinesIndexed שורות)');
        }

        try {
          debugPrint('      🔄 טוען טקסט מעמוד ${i + 1}...');
          final pageStartTime = DateTime.now();

          // Add timeout for page text loading (5 seconds per page - reduced for faster detection)
          final pageText = await pages[i].loadText().timeout(
            Duration(seconds: 5),
            onTimeout: () {
              final elapsed =
                  DateTime.now().difference(pageStartTime).inSeconds;
              debugPrint(
                  '      ⏱️ טיימאאוט בעמוד ${i + 1}/${pages.length} אחרי $elapsed שניות');
              pagesWithTimeout++;
              return null;
            },
          );

          if (pageText == null) {
            debugPrint('      ⏭️ דילוג על עמוד ${i + 1} (טיימאאוט)');
            // Skip this page if timeout occurred
            continue;
          }

          final pageElapsed =
              DateTime.now().difference(pageStartTime).inMilliseconds;
          final rawLines = pageText.fullText.split('\n');

          debugPrint(
              '      ✅ עמוד ${i + 1} נטען (${rawLines.length} שורות, ${pageElapsed}ms)');

          // Log slow pages
          if (pageElapsed > 1000) {
            debugPrint('      ⚠️ עמוד ${i + 1} איטי: לקח ${pageElapsed}ms');
          }

          // Log slow pages
          if (pageElapsed > 2000) {
            debugPrint(
                '   ⚠️ עמוד ${i + 1} לקח $pageElapsed ms לטעינה (${rawLines.length} שורות)');
          }

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
              id: _nextDocumentId(),
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
            totalLinesIndexed++;
          }

          if (!addedAny && kDebugMode) {
            debugPrint(
              '   ⚠️ עמוד ${i + 1}: דולג (אין טקסט שמיש)',
            );
          }
        } catch (e, stackTrace) {
          pagesWithErrors++;
          debugPrint('   ❌ שגיאה בעמוד ${i + 1}/${pages.length} של $title: $e');
          debugPrint(
              '   Stack trace: ${stackTrace.toString().split('\n').take(2).join('\n')}');
          // Continue to next page
        }
      }

      final totalElapsed = DateTime.now().difference(startTime).inSeconds;

      // Print summary
      debugPrint('   ✅ סיים עיבוד PDF: $title');
      debugPrint('   📊 סטטיסטיקה:');
      debugPrint('      • סה"כ עמודים: ${pages.length}');
      debugPrint('      • שורות מאונדקסות: $totalLinesIndexed');
      debugPrint('      • עמודים עם טיימאאוט: $pagesWithTimeout');
      debugPrint('      • עמודים עם שגיאות: $pagesWithErrors');
      debugPrint('      • זמן כולל: $totalElapsed שניות');

      if (!addedAnyInBook) {
        debugPrint('   ⚠️ אזהרה: לא נמצא טקסט שמיש בכל ה-PDF!');
      }

      // Fallback: some PDFs have no usable text layer, but ship alongside a
      // plain-text OCR dump. If the PDF extraction produced nothing usable,
      // try indexing a sidecar .txt so the book is still searchable.
      if (!addedAnyInBook) {
        debugPrint('   🔍 מחפש קובץ טקסט נלווה (sidecar)...');
        final candidates = <String>{
          '${book.path}.txt',
          p.setExtension(book.path, '.txt'),
        };

        File? sidecar;
        for (final candidate in candidates) {
          final f = File(candidate);
          if (await f.exists()) {
            sidecar = f;
            debugPrint('   ✅ נמצא קובץ sidecar: $candidate');
            break;
          }
        }

        if (sidecar != null) {
          debugPrint('   ⏳ מאנדקס מקובץ sidecar...');
          final ocrText = await sidecar.readAsString();
          final pagesText =
              ocrText.contains('\f') ? ocrText.split('\f') : <String>[ocrText];

          int sidecarLinesIndexed = 0;

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
                id: _nextDocumentId(),
                title: title,
                reference: ref,
                topics: '$topics/$title',
                text: normalized,
                segment: BigInt.from(pageIndex),
                isPdf: true,
                filePath: book.path,
              );
              addedAnyInBook = true;
              sidecarLinesIndexed++;
            } // סגירת הלולאה הפנימית (for j)
          } // סגירת הלולאה החיצונית (for pageIndex)

          debugPrint(
              '   ✅ אונדקסו $sidecarLinesIndexed שורות מקובץ sidecar: ${sidecar.path}');
        } else {
          debugPrint('   ⚠️ לא נמצא קובץ sidecar');
        }
      }

      // Don't commit after every book - too slow!
      // Summary already printed above
    } finally {
      document?.dispose();

      if (tempFileCreatedByUs != null && await tempFileCreatedByUs.exists()) {
        try {
          await tempFileCreatedByUs.delete();
        } catch (_) {
          // Ignore error
        }
      }
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

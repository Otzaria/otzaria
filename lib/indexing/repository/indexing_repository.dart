import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' hide Category;
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/cache/generation_cache.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/indexing/utils/book_facet_metadata_cache.dart';
import 'package:otzaria/indexing/utils/pdf_extraction_prefetcher.dart';
import 'package:otzaria/indexing/models/catalogue_order_resolver.dart';
import 'package:otzaria/indexing/models/indexing_run_result.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/book_facet.dart';
import 'package:otzaria/search/utils/search_catalogue_order_helper.dart';
import 'package:otzaria/search/utils/foundational_book_classifier.dart';
import 'package:otzaria/utils/text/ref_helper.dart';
import 'package:otzaria/utils/file/document_converter.dart';
import 'package:otzaria/utils/file/document_conversion_exceptions.dart';
import 'package:otzaria/utils/file/document_format.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

export 'package:otzaria/indexing/utils/pdf_extraction_prefetcher.dart'
    show PdfExtraction;

class _PdfExtractionFailure implements Exception {
  const _PdfExtractionFailure(this.cause);

  final Object cause;

  @override
  String toString() => cause.toString();
}

class IndexingRepository {
  final TantivyDataProvider _tantivyDataProvider;

  IndexingRepository(this._tantivyDataProvider);

  @visibleForTesting
  static IndexingFailure classifyFailureForTesting(
    Book book,
    Object error, [
    StackTrace? stackTrace,
  ]) => _classifyFailure(book, error, stackTrace);

  @visibleForTesting
  static IndexingFailure classifyPdfExtractionFailureForTesting(
    PdfBook book,
    Object error,
  ) => _classifyFailure(book, _PdfExtractionFailure(error), null);

  static IndexingFailure _classifyFailure(
    Book book,
    Object error,
    StackTrace? stackTrace,
  ) {
    final sourceError = error is _PdfExtractionFailure ? error.cause : error;
    final message = sourceError.toString();
    final normalized = message.toLowerCase();
    final kind = switch (sourceError) {
      final RangeError rangeError
          when rangeError.invalidValue == -1 && rangeError.end == 3 =>
        IndexingFailureKind.pdfUnsupported,
      final TimeoutException _ => IndexingFailureKind.timeout,
      _
          when normalized.contains('no password supplied') ||
              normalized.contains('password required') ||
              normalized.contains('incorrect password') ||
              normalized.contains('passwordprovider') =>
        IndexingFailureKind.passwordProtected,
      _
          when normalized.contains('access is denied') ||
              normalized.contains('permission denied') ||
              normalized.contains('operation not permitted') ||
              normalized.contains('os error 5') =>
        IndexingFailureKind.permissionDenied,
      _
          when normalized.contains('timeout') ||
              normalized.contains('timed out') =>
        IndexingFailureKind.timeout,
      _ when error is _PdfExtractionFailure =>
        IndexingFailureKind.pdfUnsupported,
      _ => IndexingFailureKind.unknown,
    };

    return IndexingFailure(
      bookTitle: book.title,
      bookPath: buildIndexedBookFilePath(book),
      kind: kind,
      error: message,
      stackTrace: stackTrace?.toString(),
    );
  }

  /// בודקת אם בכלל יש טעם להריץ את בדיקת requiresManualReindex.
  /// ספרייה ריקה (כולל המקרה של "אין ספרייה") אין טעם לאפס לה אינדקס,
  /// כי אין מה לאנדקס מחדש.
  @visibleForTesting
  static bool shouldSkipManualReindexCheck(Library library) {
    return library.getAllBooks().isEmpty;
  }

  @visibleForTesting
  static bool areAllIndexableBooksIndexed(
    Iterable<Book> books,
    Set<String> indexedFilePaths,
  ) {
    final indexableBooks = books.where(isIndexableBook).toList();
    if (indexableBooks.isEmpty) {
      return false;
    }

    return indexableBooks.every(
      (book) => indexedFilePaths.contains(buildIndexedBookFilePath(book)),
    );
  }

  /// סדר העיבוד באינדוקס מלא: ספרי PDF נדחפים לסוף — חילוצם איטי בסדר
  /// גודל מספרי טקסט, וכך שאר הספרייה זמינה לחיפוש מוקדם ככל האפשר.
  @visibleForTesting
  static List<Book> orderBooksForIndexing(List<Book> books) => [
    ...books.where((b) => b is! PdfBook),
    ...books.whereType<PdfBook>(),
  ];

  @visibleForTesting
  static int chronologicalOrderForBook(Book book) {
    final foundationalTier = foundationalTierForBook(book);
    if (foundationalTier != null) return foundationalTier - 1;

    final eraOrder = GenerationCache.instance.getOrderForBook(
      book.id,
      book.isUserBook,
    );
    final base = book.isUserBook ? 96 : 64;
    return base + eraOrder.clamp(0, 31);
  }

  @visibleForTesting
  static int? foundationalTierForBook(Book book) {
    final categoryPath = book.categoryPath?.isNotEmpty == true
        ? book.categoryPath
        : _categoryPathForBook(book);
    return FoundationalBookClassifier.classify(categoryPath, book.title);
  }

  static String? _categoryPathForBook(Book book) {
    if (!book.isUserBook && book.id != null) {
      final cached = ReferenceBooksCache.instance.getCategoryPathForBookSync(
        book.id!,
      );
      if (cached != null && cached.isNotEmpty) return cached;
    }

    final parts = <String>[];
    Category? current = book.category;
    while (current != null && current is! Library) {
      parts.insert(0, current.title);
      current = current.parent;
    }
    return parts.isEmpty ? null : parts.join(', ');
  }

  /// המנוע רץ על אינדקס זמני (כשל בפתיחת אינדקס הדיסק) — אינדוקס במצב זה
  /// היה נכתב לתיקייה זמנית ונזרק בהפעלה הבאה. מדווח למשתמש ומחזיר true.
  Future<bool> _blockIndexingOnTempFallback() async {
    // הדגל נקבע רק בסיום אתחול המנוע — בדיקה לפני ההמתנה הייתה מחמיצה
    // כשל פתיחה שמתרחש בזמן שהאתחול עוד רץ.
    await _tantivyDataProvider.engine;
    if (!_tantivyDataProvider.isTempFallback) return false;
    debugPrint('⚠️ המנוע על אינדקס זמני — האינדוקס מושהה כדי לא לאבד עבודה');
    UiSnack.showError(LibraryMessages.searchIndexOpenFailed);
    return true;
  }

  /// האם הספר כבר מאונדקס — לפי המסמכים החיים שנקראו מהאינדקס עצמו.
  bool isBookIndexed(Book book) => _tantivyDataProvider.indexedFilePaths
      .contains(buildIndexedBookFilePath(book));

  /// האם האינדקס הקיים דורש איפוס ובנייה מחדש, לפי בדיקת התאימות
  /// של מנוע החיפוש (נקראת מהאינדקס עצמו).
  Future<bool> requiresManualReindex(Library library) async {
    if (shouldSkipManualReindexCheck(library)) {
      return false;
    }
    await _tantivyDataProvider.engine;
    return _tantivyDataProvider.requiresManualReindex;
  }

  /// Indexes all books in the provided library.
  ///
  /// [library] The library containing books to index
  /// [onProgress] Callback function to report progress
  /// מבצע אינדוקס ומחזיר תוצאה מפורטת, כולל ביטול וכשלים פר-ספר.
  Future<IndexingRunResult> indexAllBooks(
    Library library, {
    void Function()? onActualIndexingStarted,
    required void Function(int processed, int total) onProgress,
    bool includePdfBooks = true,
  }) async {
    if (await _blockIndexingOnTempFallback()) {
      return const IndexingRunResult.cancelled(
        processedBooks: 0,
        totalBooks: 0,
        indexedBooks: 0,
      );
    }

    final allBooks = orderBooksForIndexing(
      library.getAllBooks(),
    ).where((book) => includePdfBooks || book is! PdfBook).toList();
    final totalBooks = allBooks.length;

    if (await requiresManualReindex(library)) {
      debugPrint(
        '⚠️ האינדקס דורש איפוס ובנייה מחדש באישור המשתמש - מדלג על אינדוקס אוטומטי',
      );
      return IndexingRunResult.cancelled(
        processedBooks: 0,
        totalBooks: totalBooks,
        indexedBooks: 0,
      );
    }

    if (areAllIndexableBooksIndexed(
      allBooks,
      _tantivyDataProvider.indexedFilePaths,
    )) {
      debugPrint(
        '⚡ Fast path: כל הספרים האינדקסביליים כבר מאונדקסים לפי האינדקס עצמו - מדלג על האינדוקס',
      );
      return IndexingRunResult.completed(
        processedBooks: totalBooks,
        totalBooks: totalBooks,
        indexedBooks: 0,
      );
    }

    _tantivyDataProvider.isIndexing.value = true;
    bool cancelled = false;
    var didStartActualIndexing = false;

    // חילוץ ה-PDF איטי בסדר גודל מאינדוקס ספר טקסט, ולכן חילוצי ה-PDF הבאים
    // רצים מראש ברקע בזמן שהמנוע מאנדקס את הספרים שלפניהם.
    final prefetcher = PdfExtractionPrefetcher(extract: extractPdfPagesGuarded);
    var processedBooks = 0;
    var actuallyIndexed = 0;
    var indexedSinceCommit = 0;
    var skipped = 0;
    var errors = 0;
    final failures = <IndexingFailure>[];

    try {
      await _setDbReadBoost(true);
      // מצב bulk: בלי מיזוגי-רקע של סגמנטים בזמן הבנייה — ה-optimize בסוף
      // ממזג הכול ממילא, והמיזוגים תוך-כדי רק גוזלים CPU מהאינדוקס עצמו
      // (נמדד כ-~0.2ms למסמך של האטה בקריאות המנוע).
      final engineForBulk = await _tantivyDataProvider.engine;
      await engineForBulk.setBulkIndexing(enabled: true);

      final catalogueOrder = buildCatalogueOrderResolver(library);
      await Future.wait([
        GenerationCache.instance.warmUp(),
        ReferenceBooksCache.instance.warmUp(),
        BookFacetMetadataCache.instance.warmUp(),
      ]);

      final totalStopwatch = Stopwatch()..start();
      final commitStopwatch = Stopwatch();

      debugPrint('📚 התחלת אינדוקס: $totalBooks ספרים');
      debugPrint(
        '📊 ספרים שכבר מאונדקסים: ${_tantivyDataProvider.indexedFilePaths.length}',
      );

      // ספרי PDF שטופלו בניקוז המוקדם (הצלחה או כשל) — הלולאה לא מנסה
      // אותם שוב ולא סופרת אותם כמדולגים (כבר נספרו כאינדוקס/שגיאה).
      final earlyHandledBooks = <Book>{};
      bool shouldPrefetch(PdfBook candidate) => !isBookIndexed(candidate);

      bookLoop:
      for (var bookIndex = 0; bookIndex < allBooks.length; bookIndex++) {
        final book = allBooks[bookIndex];
        if (!_tantivyDataProvider.isIndexing.value) {
          debugPrint('⚠️ אינדוקס בוטל על ידי המשתמש');
          cancelled = true;
          break;
        }
        prefetcher.fill(allBooks, bookIndex, shouldPrefetch: shouldPrefetch);

        // ניקוז: חילוץ שהסתיים מאונדקס מיד וסלוטו מתמלא, כך שהצינור אינו
        // נעצר. הספר הנוכחי מוחרג — מסלול הצריכה הרגיל מטפל בו.
        var reportedForDrain = false;
        while (true) {
          final ready = prefetcher.takeReady(exclude: book);
          if (ready == null) break;
          final readyBook = ready.book;
          prefetcher.fill(allBooks, bookIndex, shouldPrefetch: shouldPrefetch);
          earlyHandledBooks.add(readyBook);
          // דיווח לפני הכתיבה, אחרת המונה נראה תקוע לאורך אינדוקס PDF גדול.
          // פעם אחת לסבב — המיקום המדווח הוא של הלולאה ואינו זז בין הניקוזים.
          if (!reportedForDrain) {
            reportedForDrain = true;
            onProgress(bookIndex + 1, totalBooks);
          }
          try {
            final droppedPages = await _indexPdfBook(
              readyBook,
              catalogueOrder: catalogueOrder,
              preExtracted: ready.extraction,
              onActualIndexingStarted: () {
                if (didStartActualIndexing) return;
                didStartActualIndexing = true;
                onActualIndexingStarted?.call();
              },
            );
            if (!_tantivyDataProvider.isIndexing.value) {
              cancelled = true;
              break bookLoop;
            }
            _recordPartialPdfFailure(readyBook, droppedPages, failures);
            _tantivyDataProvider.indexedFilePaths.add(
              buildIndexedBookFilePath(readyBook),
            );
            actuallyIndexed++;
            indexedSinceCommit++;
          } catch (e, stackTrace) {
            debugPrint('❌ שגיאה באינדוקס מוקדם של ${readyBook.title}: $e');
            errors++;
            final failure = _classifyFailure(readyBook, e, stackTrace);
            failures.add(failure);
            final handled = await _markPermanentPdfFailure(
              readyBook,
              failure,
              catalogueOrder,
              failures,
            );
            if (handled) {
              indexedSinceCommit++;
            } else if (!isBookIndexed(readyBook) &&
                !await _discardPartialBookWrites(readyBook)) {
              await _recoverEngineAfterWriteFailure();
              cancelled = true;
              break bookLoop;
            }
          }
        }

        var bookWasIndexed = false;
        try {
          // ספרי מסמך עוברים אינדוקס דרך זרימת TextBook (העטיפה
          // משמרת id/categoryId כדי ש-`book.text` יחלץ קובץ → text).
          // catalogueOrderKey של העטוף זהה למקור: כשיש id המפתח הוא
          // 'id:<id>', וכשאין — title+categoryKey+fileType+path
          // (העטיפה מעבירה filePath ?? path, ו-fileType נשמר).
          final TextBook? textBookForIndex = _asTextBookForIndex(book);
          if (textBookForIndex != null) {
            if (!isBookIndexed(book)) {
              // דיווח הספר הנוכחי כבר בתחילת עיבודו — אחרת המונה נראה
              // תקוע על הספר הקודם לאורך כל עיבוד ספר גדול.
              onProgress(bookIndex + 1, totalBooks);
              await _indexTextBook(
                textBookForIndex,
                catalogueOrder: catalogueOrder,
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
              _tantivyDataProvider.indexedFilePaths.add(
                buildIndexedBookFilePath(book),
              );
              actuallyIndexed++;
              indexedSinceCommit++;
              bookWasIndexed = true;
            } else {
              // דילוג שקט — debugPrint לכל ספר מדולג הציף את תור ההדפסה
              // המוגבל של Flutter באלפי שורות בכל הפעלה שגרתית.
              skipped++;
            }
          } else if (book is PdfBook) {
            if (earlyHandledBooks.contains(book)) {
              // טופל בניקוז המוקדם — כבר נספר שם (אינדוקס או שגיאה).
            } else if (!isBookIndexed(book)) {
              onProgress(bookIndex + 1, totalBooks);
              // מיד אחרי הצריכה מוזנק חילוץ לסלוט שהתפנה, שירוץ במקביל
              // לאינדוקס של הספר הזה.
              final preExtracted = prefetcher.take(book);
              prefetcher.fill(
                allBooks,
                bookIndex + 1,
                shouldPrefetch: shouldPrefetch,
              );
              final droppedPages = await _indexPdfBook(
                book,
                catalogueOrder: catalogueOrder,
                preExtracted: preExtracted,
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
              _recordPartialPdfFailure(book, droppedPages, failures);
              _tantivyDataProvider.indexedFilePaths.add(
                buildIndexedBookFilePath(book),
              );
              actuallyIndexed++;
              indexedSinceCommit++;
              bookWasIndexed = true;
            } else {
              skipped++;
            }
          }

          processedBooks++;
          // commit רק כשבאמת נוספו מסמכים מאז ה-commit הקודם: הסף הישן
          // (processedBooks % 25) ספר גם ספרים מדולגים, כך שסריקה של
          // ספרייה כמעט-מאונדקסת ביצעה מאות commit-ים ריקים — כל אחד
          // מסריאל סגמנטים וטוען reader מחדש לחינם. הסף 100 נבחר לפי
          // הלוגים (~680ms ל-commit; כל 25 ספרים ⇒ ‏9% מזמן האינדוקס) —
          // ה-commit הוא רק נקודת שמירה להתאוששות, לא נדרש תכוף יותר.
          if (indexedSinceCommit >= 100) {
            commitStopwatch
              ..reset()
              ..start();
            final index = await _tantivyDataProvider.engine;
            await index.commit();
            debugPrint(
              '💾 commit אחרי $indexedSinceCommit ספרים: ${commitStopwatch.elapsedMilliseconds}ms',
            );
            // גם כאן, ולא רק ב-commit הסופי: ביטול או קריסה אחרי מאות
            // ספרים שנשמרו היו מותירים אינדקס מלא בלי חותם.
            _stampCatalogueOrderAfterCommit();
            indexedSinceCommit = 0;
          }

          if (processedBooks % 50 == 0) {
            debugPrint(
              '📈 התקדמות: $processedBooks/$totalBooks (מאונדקסים: $actuallyIndexed, דולגו: $skipped, שגיאות: $errors, ${totalStopwatch.elapsed})',
            );
          }

          // אירוע התקדמות לכל ספר שאונדקס בפועל; בסריקת מדולגים — רק אחת
          // ל-25, כדי לא לייצר אירוע BLoC ורינדור UI לכל ספר מדולג.
          if (bookWasIndexed ||
              processedBooks % 25 == 0 ||
              processedBooks == totalBooks) {
            onProgress(processedBooks, totalBooks);
          }
        } catch (e, stackTrace) {
          debugPrint('❌ שגיאה באינדוקס של ${book.title}: $e');
          errors++;
          final failure = _classifyFailure(book, e, stackTrace);
          failures.add(failure);
          processedBooks++;
          onProgress(processedBooks, totalBooks);
          final handled = await _markPermanentPdfFailure(
            book,
            failure,
            catalogueOrder,
            failures,
          );
          if (handled) {
            indexedSinceCommit++;
          } else if (!isBookIndexed(book) &&
              !await _discardPartialBookWrites(book)) {
            // ניקוי כושל ⇒ commit היה חותם ספר חלקי; משליכים את כל החוצץ
            // ועוצרים בלי commit — מה שלא נחתם ינוסה שוב בריצה הבאה.
            await _recoverEngineAfterWriteFailure();
            cancelled = true;
            break;
          }
        }

        await Future.delayed(Duration.zero);
      }

      if (!cancelled) {
        debugPrint('✅ אינדוקס הושלם!');
        debugPrint('   📊 סה"כ: $totalBooks ספרים');
        debugPrint('   ✅ מאונדקסים: $actuallyIndexed');
        debugPrint('   ⏭️ דולגו: $skipped');
        debugPrint('   ❌ שגיאות: $errors');

        final index = await _tantivyDataProvider.engine;
        commitStopwatch
          ..reset()
          ..start();
        await index.commit();
        debugPrint('💾 commit סופי: ${commitStopwatch.elapsedMilliseconds}ms');
        _stampCatalogueOrderAfterCommit();
        final optimizeStopwatch = Stopwatch()..start();
        await optimizeIndexBestEffort(index.optimize);
        debugPrint('⚙️ optimize: ${optimizeStopwatch.elapsedMilliseconds}ms');
        debugPrint('⏱️ סה"כ אינדוקס: ${totalStopwatch.elapsed}');
      }
    } finally {
      prefetcher.dispose();
      await _setDbReadBoost(false);
      // החזרת מדיניות המיזוג הרגילה — גם בביטול/שגיאה, כדי שאינדוקס
      // אינקרמנטלי עתידי ימשיך למזג כרגיל. best-effort: כשל כאן לא
      // מסכן את האינדקס (שכבר עבר commit).
      try {
        final engine = await _tantivyDataProvider.engine;
        await engine.setBulkIndexing(enabled: false);
      } catch (e) {
        debugPrint('⚠️ כיבוי מצב bulk נכשל: $e');
      }
      _tantivyDataProvider.isIndexing.value = false;
    }
    return cancelled
        ? IndexingRunResult.cancelled(
            processedBooks: processedBooks,
            totalBooks: totalBooks,
            indexedBooks: actuallyIndexed,
            failures: List.unmodifiable(failures),
          )
        : IndexingRunResult.completed(
            processedBooks: processedBooks,
            totalBooks: totalBooks,
            indexedBooks: actuallyIndexed,
            failures: List.unmodifiable(failures),
          );
  }

  Future<void> _indexTextBook(
    TextBook book, {
    required CatalogueOrderResolver catalogueOrder,
    void Function()? onActualIndexingStarted,
  }) async {
    // כל הכנת הספר — פיצול לשורות, מעקב reference trail, נרמול, טביעת
    // אצבע ואינדוקס — רצה במנוע בקריאת FFI אחת: התוכן חוצה את הגשר פעם
    // אחת בלבד. במסלול הרגיל (ספר מ-DB) התוכן נקרא כבייטים גולמיים
    // (UTF-8 כפי שמאוחסן ב-SQLite) ונמסר ל-addTextBookBytes — בלי פענוח
    // ל-String וקידוד חוזר על הגשר (~180ms/MB שנמדדו בלוגים).
    final loadStopwatch = Stopwatch()..start();
    final source = await _loadTextBookSource(book);
    final bytes = source.bytes;
    final text = source.text;
    loadStopwatch.stop();

    final hasBytes = bytes != null && bytes.isNotEmpty;
    final hasText = text != null && text.isNotEmpty;
    var wroteDocuments = false;

    if (hasBytes || hasText) {
      // הביטול נבדק לפני הקריאה; בתוך ספר בודד הכתיבה אטומית מבחינתנו.
      onActualIndexingStarted?.call();
      if (!_tantivyDataProvider.isIndexing.value) {
        return;
      }
      final engine = await _tantivyDataProvider.engine;
      final title = book.title;
      final topics = _bookTopics(book);
      final filePath = buildIndexedBookFilePath(book);
      final order = catalogueOrder.orderFor(catalogueOrderKey(book));
      final generationOrder = chronologicalOrderForBook(book);
      final engineStopwatch = Stopwatch()..start();
      final extraFacets = _bookExtraFacets(book);
      final added = hasBytes
          ? await engine.addTextBookBytes(
              title: title,
              topics: topics,
              filePath: filePath,
              catalogueOrder: order,
              generationOrder: generationOrder,
              text: bytes,
              extraFacets: extraFacets,
            )
          : await engine.addTextBook(
              title: title,
              topics: topics,
              filePath: filePath,
              catalogueOrder: order,
              generationOrder: generationOrder,
              text: text!,
              extraFacets: extraFacets,
            );
      engineStopwatch.stop();
      final size = hasBytes
          ? '${bytes.length} בייטים'
          : '${text!.length} תווים';
      debugPrint(
        '📖 "${book.title}": $size → $added מסמכים | '
        'טעינה ${loadStopwatch.elapsedMilliseconds}ms, '
        'מנוע ${engineStopwatch.elapsedMilliseconds}ms',
      );
      wroteDocuments = added > 0;
    } else {
      debugPrint('⚠️ ספר ריק: ${book.title} - מדלג');
    }

    if (!wroteDocuments) {
      // אין תוכן ⇒ אין טביעת אצבע; במסלול המלא המנוע חותם אותה בעצמו.
      await _writeEmptyBookMarker(
        book,
        catalogueOrder: catalogueOrder,
      );
    }
  }

  Future<int> _indexPdfBook(
    PdfBook book, {
    required CatalogueOrderResolver catalogueOrder,
    void Function()? onActualIndexingStarted,
    Future<PdfExtraction>? preExtracted,
  }) async {
    // preExtracted — חילוץ שהוזנק מראש (prefetch) בזמן שהספרים הקודמים
    // אונדקסו; בהיעדרו מחלצים כאן. שני המסלולים עוברים דרך העטיפה
    // ששומרת את השגיאה בתוצאה, כדי שסמנטיקת ה-sidecar/הפצת-שגיאה תישאר
    // זהה.
    final extracted = await (preExtracted ?? extractPdfPagesGuarded(book));
    final pages = extracted.pages;
    final outline = extracted.outline;
    final openError = extracted.error;
    final openStackTrace = extracted.stackTrace;

    if (openError != null) {
      debugPrint('❌ שגיאה בפתיחת PDF לאינדוקס: ${book.title}: $openError');
    }
    debugPrint(
      '📄 "${book.title}": חולצו ${pages.length} עמודים '
      'ב-${extracted.extractMs}ms${preExtracted != null ? ' (prefetch)' : ''}',
    );
    if (!_tantivyDataProvider.isIndexing.value) {
      return extracted.droppedPages;
    }

    // ההכרעה אם ל-PDF יש טקסט שמיש עברה למנוע: add_pdf_book מנרמל ומסנן
    // זבל בעצמו ומחזיר כמה מסמכים נוספו — אין יותר מעבר נרמול מקדים שרץ
    // על ה-main thread ונזרק (הנרמול הכפול הישן של _hasUsablePdfText).
    var added = 0;
    if (pages.isNotEmpty) {
      added = await _addPdfBookToEngine(
        book,
        pages,
        catalogueOrder: catalogueOrder,
        onActualIndexingStarted: onActualIndexingStarted,
      );
    }

    if (added == 0 && _tantivyDataProvider.isIndexing.value) {
      // אין שכבת טקסט שמישה (PDF סרוק) או שהפתיחה נכשלה — sidecar OCR.
      final sidecarPages = await _loadPdfSidecar(book, outline);
      if (sidecarPages.isNotEmpty) {
        added = await _addPdfBookToEngine(
          book,
          sidecarPages,
          catalogueOrder: catalogueOrder,
          onActualIndexingStarted: onActualIndexingStarted,
        );
      }

      if (added == 0 && openError != null) {
        // כשל בטעינת ה-PDF עצמו (להבדיל מטקסט סרוק): בלי sidecar מפיצים את
        // השגיאה, אלא אם ה-sidecar הוסיף בפועל תוכן שמיש.
        Error.throwWithStackTrace(
          _PdfExtractionFailure(openError),
          openStackTrace!,
        );
      }
      if (added == 0 && extracted.droppedPages > 0) {
        // אפס תוכן לאינדוקס אחרי שעמודים חרגו מה-timeout (worker של pdfium
        // שנתקע, או עומס רגעי). sidecar נחשב רק אם המנוע קיבל את תוכנו.
        throw TimeoutException(
          'חילוץ הטקסט של "${book.title}" לא הניב תוכן; '
          '${extracted.droppedPages} עמודים חרגו מה-timeout',
        );
      }
    }

    if (added == 0) {
      await _writeEmptyBookMarker(
        book,
        catalogueOrder: catalogueOrder,
      );
    }
    return extracted.droppedPages;
  }

  void _recordPartialPdfFailure(
    PdfBook book,
    int droppedPages,
    List<IndexingFailure> failures,
  ) {
    if (droppedPages == 0) return;
    failures.add(
      IndexingFailure(
        bookTitle: book.title,
        bookPath: book.path,
        kind: IndexingFailureKind.partialPdf,
        error: '$droppedPages עמודים נשמטו מהחילוץ עקב timeout',
      ),
    );
  }

  /// שולח את עמודי ה-PDF למנוע בקריאת FFI אחת (add_pdf_book: נרמול, סינון
  /// זבל ואינדוקס בתוך המנוע) ומחזיר את מספר המסמכים שנוספו. מחליף את
  /// המסלול הישן — isolate ← נרמול באצוות ← העתקת SendPort ←
  /// addDocumentsBatch — שהעתיק את הטקסט המחולץ ארבע-חמש פעמים לכל ספר.
  Future<int> _addPdfBookToEngine(
    PdfBook book,
    List<({String reference, String text, int pageIndex})> pages, {
    required CatalogueOrderResolver catalogueOrder,
    void Function()? onActualIndexingStarted,
  }) async {
    onActualIndexingStarted?.call();
    if (!_tantivyDataProvider.isIndexing.value) {
      return 0;
    }
    final engine = await _tantivyDataProvider.engine;
    final engineStopwatch = Stopwatch()..start();
    final added = await engine.addPdfBook(
      title: book.title,
      topics: _bookTopics(book),
      filePath: buildIndexedBookFilePath(book),
      catalogueOrder: catalogueOrder.orderFor(catalogueOrderKey(book)),
      generationOrder: chronologicalOrderForBook(book),
      extraFacets: _bookExtraFacets(book),
      pages: [
        for (final page in pages)
          PdfPageInput(
            reference: page.reference,
            text: page.text,
            pageIndex: page.pageIndex,
          ),
      ],
    );
    engineStopwatch.stop();
    debugPrint(
      '📄 "${book.title}": ${pages.length} עמודים → $added מסמכים | '
      'מנוע ${engineStopwatch.elapsedMilliseconds}ms',
    );
    return added;
  }

  /// רושם באינדקס מסמך ריק יחיד עבור ספר שלא הניב תוכן לאינדוקס (למשל PDF
  /// סרוק ללא שכבת טקסט). מסמך ריק לעולם לא עולה בתוצאות חיפוש, אבל הוא
  /// גורם לאינדקס עצמו לזכור שהספר כבר עובד — כך הוא לא יעובד מחדש בכל
  /// הפעלה. בלי זה, מצב האינדוקס (שנקרא מהאינדקס) לעולם לא היה שלם.
  Future<void> _writeEmptyBookMarker(
    Book book, {
    required CatalogueOrderResolver catalogueOrder,
  }) async {
    if (!_tantivyDataProvider.isIndexing.value) {
      return;
    }
    final index = await _tantivyDataProvider.engine;
    // add (ולא upsert): כל מסלולי הכתיבה מדלגים על ספר שכבר מאונדקס
    // (isBookIndexed), כך שהספר כאן תמיד חדש ואין מה למחוק.
    await index.addDocumentsBatch(
      docs: [
        DocumentInput(
          id: buildCatalogueDocumentId(
            catalogueOrder: catalogueOrder.orderFor(catalogueOrderKey(book)),
            ordinal: 0,
          ),
          title: book.title,
          reference: '',
          topics: _bookTopics(book),
          text: '',
          segment: BigInt.zero,
          isPdf: book is PdfBook,
          filePath: buildIndexedBookFilePath(book),
          generationOrder: chronologicalOrderForBook(book),
        ),
      ],
    );
  }

  Future<bool> _markPermanentPdfFailure(
    Book book,
    IndexingFailure failure,
    CatalogueOrderResolver catalogueOrder,
    List<IndexingFailure> failures,
  ) async {
    if (book is! PdfBook || failure.isRetryable) return false;
    if (!_tantivyDataProvider.isIndexing.value) return false;

    try {
      await _writeEmptyBookMarker(
        book,
        catalogueOrder: catalogueOrder,
      );
    } catch (error, stackTrace) {
      failures.add(
        IndexingFailure(
          bookTitle: book.title,
          bookPath: book.path,
          kind: IndexingFailureKind.engineWrite,
          error: error.toString(),
          stackTrace: stackTrace.toString(),
        ),
      );
      debugPrint('⚠️ כתיבת סמן כשל קבוע עבור ${book.title} נכשלה: $error');
      return false;
    }
    if (!_tantivyDataProvider.isIndexing.value) return false;

    _tantivyDataProvider.indexedFilePaths.add(buildIndexedBookFilePath(book));
    return true;
  }

  /// מוחק את המסמכים החלקיים של ספר שכתיבתו למנוע נכשלה באמצע: בלעדי זה
  /// ה-commit הבא חותם ספר חלקי, שנחשב "מאונדקס" ולעולם לא מנוסה שוב.
  Future<bool> _discardPartialBookWrites(Book book) async {
    try {
      final engine = await _tantivyDataProvider.engine;
      await engine.deleteDocumentsByFilePaths(
        filePaths: [buildIndexedBookFilePath(book)],
      );
      return true;
    } catch (e) {
      debugPrint('⚠️ מחיקת מסמכים חלקיים של ${book.title} נכשלה: $e');
      return false;
    }
  }

  /// שחזור בטוח אחרי כשל כתיבה/commit, כשמצב המנוע אינו ידוע: commit עלול
  /// היה להיחתם בדיסק גם כשהקריאה זרקה (כשל ב-reload של ה-reader בלבד).
  Future<void> _recoverEngineAfterWriteFailure() async {
    // rollback קודם — משליך כתיבות ממתינות גם אם ה-reopen ידולג (throttle).
    try {
      await (await _tantivyDataProvider.engine).rollback();
    } catch (e) {
      debugPrint('⚠️ rollback אחרי כשל כתיבה נכשל: $e');
    }
    // reader טרי מהמצב החתום בדיסק + טעינת indexedFilePaths מחדש — קריאה
    // מה-reader הישן עלולה להחזיר מצב מעופש שמשחזר מעקב שגוי.
    try {
      final reopened = await _tantivyDataProvider.reopenIndex(force: true);
      if (!reopened) {
        debugPrint('⚠️ פתיחת המנוע מחדש אחרי כשל כתיבה דולגה');
      }
    } catch (e) {
      debugPrint('⚠️ פתיחת המנוע מחדש אחרי כשל כתיבה נכשלה: $e');
    }
  }

  /// עוטפת את [_extractPdfPages] כך שהתוצאה לעולם אינה זריקה: שגיאת פתיחה
  /// נשמרת בתוצאה (הקורא מכריע בין sidecar להפצתה), ומשך החילוץ נמדד כאן —
  /// כך גם חילוץ שרץ מראש (prefetch) מדווח את זמנו האמיתי.
  @visibleForTesting
  Future<PdfExtraction> extractPdfPagesGuarded(PdfBook book) async {
    final stopwatch = Stopwatch()..start();
    try {
      final extracted = await _extractPdfPages(book);
      return (
        pages: extracted.pages,
        outline: extracted.outline,
        error: null,
        stackTrace: null,
        extractMs: stopwatch.elapsedMilliseconds,
        droppedPages: extracted.droppedPages,
      );
    } catch (e, st) {
      return (
        pages: const <({String reference, String text, int pageIndex})>[],
        outline: const <PdfOutlineNode>[],
        error: e,
        stackTrace: st,
        extractMs: stopwatch.elapsedMilliseconds,
        droppedPages: 0,
      );
    }
  }

  /// חילוץ טקסט העמודים וה-outline מה-PDF עצמו. אינו בודק אם הטקסט שמיש —
  /// ההכרעה הזו עברה למנוע (add_pdf_book מסנן זבל ומחזיר 0 כשאין תוכן);
  /// כשל בפתיחת הקובץ מופץ לקורא, שמחליט בין sidecar להפצת השגיאה.
  Future<
    ({
      List<({String reference, String text, int pageIndex})> pages,
      List<PdfOutlineNode> outline,
      int droppedPages,
    })
  >
  _extractPdfPages(PdfBook book) async {
    const empty = (
      pages: <({String reference, String text, int pageIndex})>[],
      outline: <PdfOutlineNode>[],
      droppedPages: 0,
    );
    final file = File(book.path);
    if (!await file.exists()) return empty;

    final document = await PdfDocument.openFile(
      book.path,
    ).timeout(const Duration(seconds: 60));
    try {
      final outline = await document.loadOutline().timeout(
        const Duration(seconds: 15),
        onTimeout: () => <PdfOutlineNode>[],
      );

      final pages = <({String reference, String text, int pageIndex})>[];
      var droppedPages = 0;

      // סדרתי בכוונה: כל קריאות pdfium מסורלות דרך worker isolate יחיד, כך
      // שטעינת מקבץ לא מאיצה — אבל מפעילה את כל טיימרי ה-timeout יחד ומפילה
      // עמודים תקינים שרק ממתינים בתור.
      final pageCount = document.pages.length;
      for (int i = 0; i < pageCount; i++) {
        if (!_tantivyDataProvider.isIndexing.value) return empty;

        final pageText = await document.pages[i].loadText().timeout(
          const Duration(seconds: 5),
          onTimeout: () => null,
        );
        if (pageText == null) {
          droppedPages++;
          continue;
        }

        final bookmark = referenceFromPageNumber(i + 1, outline, book.title);
        final ref = bookmark.isNotEmpty
            ? '${book.title}, $bookmark, עמוד ${i + 1}'
            : '${book.title}, עמוד ${i + 1}';

        pages.add((reference: ref, text: pageText.fullText, pageIndex: i));
      }

      if (droppedPages > 0) {
        debugPrint(
          '⚠️ "${book.title}": $droppedPages עמודים נשמטו מהחילוץ (timeout)',
        );
      }

      return (pages: pages, outline: outline, droppedPages: droppedPages);
    } finally {
      // בלי סגירה מפורשת המסמך נשאר פתוח ב-pdfium עד סוף התהליך: אין
      // Finalizer על העטיפה, ו-FPDF_CloseDocument נקרא רק מ-dispose.
      await document.dispose();
    }
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
    final pagesText = ocrText.contains('\f')
        ? ocrText.split('\f')
        : <String>[ocrText];

    final pages = <({String reference, String text, int pageIndex})>[];
    for (int pageIndex = 0; pageIndex < pagesText.length; pageIndex++) {
      final bookmark = await refFromPageNumber(
        pageIndex + 1,
        outline,
        book.title,
      );
      final ref = bookmark.isNotEmpty
          ? '${book.title}, $bookmark, עמוד ${pageIndex + 1}'
          : '${book.title}, עמוד ${pageIndex + 1}';
      pages.add((
        reference: ref,
        text: pagesText[pageIndex],
        pageIndex: pageIndex,
      ));
    }
    return pages;
  }

  /// data URIs (תמונות מוטמעות בספרי EPUB/DOCX מומרים) — עשרות MB לספר
  /// מצויר. אינם ניתנים לחיפוש, מנפחים את האינדקס, וגרמו ל-abort של ה-VM
  /// בזמן אינדוקס. ההחלפה משמרת את מבנה השורות (אין מחיקת שורות).
  ///
  /// סריקה ידנית ולא RegExp — מנוע ה-regex של Dart ממוטט את המחסנית
  /// (Stack Overflow) על data URI באורך מיליוני תווים.
  @visibleForTesting
  static String stripDataUrisForIndex(String text) {
    const scheme = 'data:';
    const minPayloadLength = 64;
    var matchStart = text.indexOf(scheme);
    if (matchStart < 0) return text;

    final buffer = StringBuffer();
    var copiedUpTo = 0;
    while (matchStart >= 0) {
      var end = matchStart + scheme.length;
      while (end < text.length && _isDataUriChar(text.codeUnitAt(end))) {
        end++;
      }
      if (end - matchStart - scheme.length >= minPayloadLength) {
        buffer.write(text.substring(copiedUpTo, matchStart));
        copiedUpTo = end;
      }
      matchStart = text.indexOf(scheme, end);
    }
    if (copiedUpTo == 0) return text;
    buffer.write(text.substring(copiedUpTo));
    return buffer.toString();
  }

  /// סריקת bytes ל-'data:' (ASCII, ולכן תקפה על UTF-8) — מכריעה אם מסלול
  /// ה-bytes המהיר חייב לרדת לפענוח וניקוי. false = אין מה לנקות.
  @visibleForTesting
  static bool bytesContainDataUriScheme(Uint8List bytes) {
    const scheme = [0x64, 0x61, 0x74, 0x61, 0x3A]; // 'data:'
    final last = bytes.length - scheme.length;
    for (var i = 0; i <= last; i++) {
      if (bytes[i] != scheme[0]) continue;
      var j = 1;
      while (j < scheme.length && bytes[i + j] == scheme[j]) {
        j++;
      }
      if (j == scheme.length) return true;
    }
    return false;
  }

  static bool _isDataUriChar(int c) =>
      (c >= 0x41 && c <= 0x5A) || // A-Z
      (c >= 0x61 && c <= 0x7A) || // a-z
      (c >= 0x30 && c <= 0x39) || // 0-9
      c == 0x2B || // +
      c == 0x2F || // /
      c == 0x3B || // ;
      c == 0x2C || // ,
      c == 0x3D || // =
      c == 0x2E || // .
      c == 0x2D; // -

  /// מקור הספר בדיוק כפי שנמסר למנוע באינדוקס: bytes גולמיים מה-DB כשאפשר
  /// (בלי פענוח/קידוד על ה-UI isolate), וירידה לטקסט מפוענח ומנוקה רק
  /// כשחייבים (תמונות מוטמעות, פורמט מומר, ספר בלי categoryId). משותף
  /// לאינדוקס ולאימות הטריות — כך שתי החתימות מחושבות על אותו קלט בדיוק.
  Future<({Uint8List? bytes, String? text})> _loadTextBookSource(
    TextBook book,
  ) async {
    Uint8List? bytes;
    String? text;
    if (book.categoryId != null) {
      bytes = await SqliteDataProvider.instance.getBookTextBytesFromDb(
        book.title,
        book.categoryId,
        book.fileType ?? 'txt',
        book.isUserBook,
      );
      // ניקוי תמונות מוטמעות חייב לרוץ בשני הצדדים — אחרת חתימת האינדוקס
      // לעולם לא תתאים לאימות ו-reconcile יאנדקס את הספר מחדש בכל ריצה.
      if (bytes != null && bytesContainDataUriScheme(bytes)) {
        text = stripDataUrisForIndex(utf8.decode(bytes, allowMalformed: true));
        bytes = null;
      }
    }
    if ((bytes == null || bytes.isEmpty) && (text == null || text.isEmpty)) {
      text = await _loadTextForIndex(book);
    }
    return (bytes: bytes, text: text);
  }

  Future<String?> _loadTextBookText(TextBook book) async {
    String? text;

    if (book.categoryId != null) {
      text = await SqliteDataProvider.instance.getBookTextFromDb(
        book.title,
        book.categoryId,
        book.fileType ?? 'txt',
        book.isUserBook,
      );
    }

    if (text == null || text.isEmpty) {
      text = await _loadTextForIndex(book);
    }

    if (text.isEmpty) {
      debugPrint(
        '⚠️ ספר ריק: ${book.title} (categoryId: ${book.categoryId}) - מדלג',
      );
      return null;
    }

    // עקבי עם מסלול האינדוקס — טביעת האצבע מחושבת על הטקסט המנוקה.
    return stripDataUrisForIndex(text);
  }

  /// טוען את טקסט הספר לאינדוקס, בלי להטמיע תמונות כשהממיר תומך בכך.
  ///
  /// לאינדקס אין שימוש ב-base64 של התמונות, והטמעתן מקצה מחרוזות של עשרות
  /// MB לכל ספר. פורמט שאין לו וריאנט חסר-תמונות נופל לניקוי ה-data URI
  /// אחרי ההמרה (§63, §65).
  Future<String> _loadTextForIndex(TextBook book) async {
    final filePath = book.filePath;
    final format = documentFormatOf(fileType: book.fileType, path: filePath);
    if (format != null &&
        format.supportsImageFreeConversion &&
        filePath != null) {
      final file = File(filePath);
      if (await file.exists()) {
        return convertDocumentForIndex(file, book.title, format);
      }
    }
    return stripDataUrisForIndex(await book.text);
  }

  /// ממדי ה-facet הנוספים של הספר (מחבר/תקופה/ספר-יסוד) — משותף לכל
  /// מסלולי הכתיבה, כמו [_bookTopics]. null כשאין ממדים (המנוע מקבל
  /// `extraFacets: null` ולא רשימה ריקה — אותה משמעות, פחות העברה).
  List<String>? _bookExtraFacets(Book book) {
    final facets = BookFacetMetadataCache.instance.extraFacetsForBook(
      book,
      isFoundational: foundationalTierForBook(book) != null,
    );
    return facets.isEmpty ? null : facets;
  }

  /// נתיב ה-facet של הספר — משותף לכל מסלולי הכתיבה (טקסט, PDF, סמן-ריק),
  /// כדי שהמסלולים לא יסטו זה מזה.
  String _bookTopics(Book book) => BookFacet.buildFacetPath(
    title: book.title,
    topics: book.topics,
    externalLibraryId: book.externalLibraryId,
    bookId: book.id,
    isUserBook: book.isUserBook,
    categoryPath: book.category?.path ?? book.categoryPath,
    fileType: book.fileType,
    filePath: book is FileBook ? book.path : book.filePath,
  );

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

  /// משלים חותם סדר קטלוגי שכתיבתו נכשלה באתחול. בלעדיו האינדקס שזה עתה
  /// נחתם ייראה בהפעלה הבאה כאילו נבנה בסדר ישן, והמשתמש יידרש לבנות מחדש.
  void _stampCatalogueOrderAfterCommit() {
    if (_tantivyDataProvider.ensureCatalogueOrderStamp()) return;
    debugPrint(
      '⚠️ חותם הסדר הקטלוגי לא נכתב — ההפעלה הבאה תדרוש בניית אינדקס מחדש',
    );
  }

  /// מוסר הסדר הקטלוגי של הספרייה — הבסיס לחצי העליון של מזהה המסמך.
  @visibleForTesting
  static CatalogueOrderResolver buildCatalogueOrderResolver(Library library) =>
      CatalogueOrderResolver(
        SearchCatalogueOrderHelper.buildKeyOrderMap(
          library,
          keyOf: (book) => catalogueOrderKey(book as Book),
        ),
      );

  @visibleForTesting
  static BigInt buildCatalogueDocumentId({
    required int catalogueOrder,
    required int ordinal,
  }) {
    return (BigInt.from(catalogueOrder + 1) << 32) + BigInt.from(ordinal + 1);
  }

  static String catalogueOrderKey(Book book) => catalogueOrderKeyFromParts(
    title: book.title,
    externalLibraryId: book.externalLibraryId,
    bookId: book.id,
    isUserBook: book.isUserBook,
    categoryKey: book.category?.path ?? book.categoryPath,
    fileTypeKey: book.fileType ?? book.runtimeType.toString(),
    pathKey: book is FileBook ? book.path : book.filePath,
  );

  /// אותו מפתח מרכיבים גולמיים, למי שאין בידיו [Book] (נתיב ה-facet של
  /// החיפוש). מקור אמת יחיד — כל סטייה כאן מפצלת ספר לשתי זהויות.
  static String catalogueOrderKeyFromParts({
    required String title,
    String? externalLibraryId,
    int? bookId,
    bool isUserBook = false,
    String? categoryKey,
    String? fileTypeKey,
    String? pathKey,
  }) {
    if (externalLibraryId != null && externalLibraryId.isNotEmpty) {
      return 'ext:$externalLibraryId';
    }

    if (bookId != null) {
      // id טבעי חופף בין seforim.db ל-user_books.db — בלי תיוג המקור
      // ספר אישי 'id:5' מתנגש בספר רשמי 'id:5' ומדולג באינדוקס.
      return isUserBook ? userBookKey(bookId) : officialBookKey(bookId);
    }

    return '$title|${categoryKey ?? ''}|${fileTypeKey ?? ''}|${pathKey ?? ''}';
  }

  /// מפתח catalogueOrderKey לספר אישי (user_books.db) לפי id גולמי.
  static String userBookKey(int id) => 'uid:$id';

  /// מפתח catalogueOrderKey לספר רשמי (seforim.db) לפי id גולמי.
  static String officialBookKey(int id) => 'id:$id';

  static String buildIndexedBookFilePath(Book book) {
    if (book is PdfBook) {
      return book.path;
    }
    return catalogueOrderKey(book);
  }

  /// הספר שמסמך האינדקס מתאר, רק אם הקטלוג עדיין מחזיק שם את אותו ספר.
  static Book? bookForIndexedDocument(
    Map<String, Book>? booksByIndexedFilePath, {
    required String indexedFilePath,
    required String indexedTitle,
  }) => validatedIndexedBook(
    booksByIndexedFilePath?[indexedFilePath],
    indexedTitle: indexedTitle,
  );

  /// [book] אותר לפי מפתח מסמך האינדקס — מוחזר רק אם הוא עדיין אותו ספר.
  ///
  /// המפתח והכותרת נכתבים למסמך יחד מאותו ספר, ולכן כותרת שאינה תואמת
  /// מעידה שה-DB הוחלף והמזהה שייך כבר לספר אחר.
  static Book? validatedIndexedBook(
    Book? book, {
    required String indexedTitle,
  }) => book?.title == indexedTitle ? book : null;

  /// בודק שתוכן ספר טקסט עדיין תואם את חתימת הטקסט שבאינדקס — בלי תלות
  /// ב-metadata (סדר קטלוגי וכו', שנפסלים מכל הוספת ספר — issue #828).
  /// [indexHash] הוא ערך `textHash` מהאינדקס (`getBookTextFingerprint`).
  ///
  /// בדיקה רכה: `true` גם כשאין חתימה או שהספר לא ניתן לאימות — אזהרה
  /// מוצדקת רק על אי-התאמה ודאית.
  Future<bool> textBookContentMatchesIndex(Book book, BigInt indexHash) async {
    final textBook = _asTextBookForIndex(book);
    if (indexHash == BigInt.zero || textBook == null) {
      return true;
    }

    // אותו מקור בדיוק שמסלול האינדוקס חתם: במקרה הנפוץ bytes גולמיים
    // מה-DB עוברים כמות שהם, וה-UI isolate לא מפענח, מקודד או מגבב דבר —
    // הגיבוב רץ על ה-thread pool של המנוע.
    final source = await _loadTextBookSource(textBook);
    final text = source.text;
    final bytes =
        source.bytes ??
        (text == null || text.isEmpty ? null : utf8.encode(text));
    if (bytes == null || bytes.isEmpty) return true;

    return await computeContentFingerprintBytes(text: bytes) == indexHash;
  }

  /// האם רשומת הספר באינדקס מאוחסנת לפי נתיב מוחלט (ולכן תישבר בהעברת
  /// הספרייה ותדרוש ניקוי). PDF תמיד; שאר ספרי הקובץ רק כשאין להם
  /// id/externalLibraryId יציב — אחרת הם מאונדקסים לפי מפתח id ושורדים העברה.
  static bool hasPathKeyedIndexEntry(Book book) {
    if (book is PdfBook) return true;
    if (book is! FileBook) return false;
    return book.id == null &&
        (book.externalLibraryId == null || book.externalLibraryId!.isEmpty);
  }

  /// Indexes a specific list of books (e.g. newly added personal books).
  ///
  /// מבצע אינדוקס ומחזיר תוצאה מפורטת, כולל ביטול וכשלים פר-ספר.
  Future<IndexingRunResult> indexBooks(
    List<Book> books,
    Library library, {
    void Function()? onActualIndexingStarted,
    required void Function(int processed, int total) onProgress,
  }) async {
    if (books.isEmpty) {
      return const IndexingRunResult.completed(
        processedBooks: 0,
        totalBooks: 0,
        indexedBooks: 0,
      );
    }
    if (await _blockIndexingOnTempFallback()) {
      return IndexingRunResult.cancelled(
        processedBooks: 0,
        totalBooks: books.length,
        indexedBooks: 0,
      );
    }

    _tantivyDataProvider.isIndexing.value = true;

    if (await requiresManualReindex(library)) {
      _tantivyDataProvider.isIndexing.value = false;
      return IndexingRunResult.cancelled(
        processedBooks: 0,
        totalBooks: books.length,
        indexedBooks: 0,
      );
    }

    // הספרייה המלאה, ולא רשימת הספרים שמאונדקסת, כדי שהסדר יהיה גלובלי.
    final catalogueOrder = buildCatalogueOrderResolver(library);
    await Future.wait([
      GenerationCache.instance.warmUp(),
      ReferenceBooksCache.instance.warmUp(),
      BookFacetMetadataCache.instance.warmUp(),
    ]);

    final totalBooks = books.length;
    int processedBooks = 0;
    int actuallyIndexed = 0;
    int errors = 0;
    bool cancelled = false;
    var didStartActualIndexing = false;
    final failures = <IndexingFailure>[];

    try {
      await _setDbReadBoost(true);
      for (final book in books) {
        if (!_tantivyDataProvider.isIndexing.value) {
          cancelled = true;
          break;
        }

        try {
          // ספרי מסמך ממופים ל-TextBook (ראה הסבר ב-indexAllBooks).
          final TextBook? textBookForIndex = _asTextBookForIndex(book);
          if (textBookForIndex != null) {
            if (!isBookIndexed(book)) {
              onProgress(processedBooks + 1, totalBooks);
              debugPrint('📖 מאנדקס ספר טקסט חדש: ${book.title}');
              await _indexTextBook(
                textBookForIndex,
                catalogueOrder: catalogueOrder,
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
              _tantivyDataProvider.indexedFilePaths.add(
                buildIndexedBookFilePath(book),
              );
              actuallyIndexed++;
            }
          } else if (book is PdfBook) {
            if (!isBookIndexed(book)) {
              onProgress(processedBooks + 1, totalBooks);
              debugPrint('📄 מאנדקס PDF חדש: ${book.title}');
              final droppedPages = await _indexPdfBook(
                book,
                catalogueOrder: catalogueOrder,
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
              _recordPartialPdfFailure(book, droppedPages, failures);
              _tantivyDataProvider.indexedFilePaths.add(
                buildIndexedBookFilePath(book),
              );
              actuallyIndexed++;
            }
          }

          processedBooks++;
          onProgress(processedBooks, totalBooks);
        } catch (e, stackTrace) {
          debugPrint('❌ שגיאה באינדוקס של ${book.title}: $e');
          errors++;
          final failure = _classifyFailure(book, e, stackTrace);
          failures.add(failure);
          processedBooks++;
          onProgress(processedBooks, totalBooks);
          final handled = await _markPermanentPdfFailure(
            book,
            failure,
            catalogueOrder,
            failures,
          );
          if (!handled &&
              !isBookIndexed(book) &&
              !await _discardPartialBookWrites(book)) {
            // ניקוי כושל ⇒ commit היה חותם ספר חלקי; משליכים את כל החוצץ
            // ועוצרים בלי commit — מה שלא נחתם ינוסה שוב בריצה הבאה.
            await _recoverEngineAfterWriteFailure();
            cancelled = true;
            break;
          }
        }

        await Future.delayed(Duration.zero);
      }

      if (!cancelled) {
        debugPrint(
          '✅ אינדוקס ספרים ספציפיים הושלם! (מאונדקסים: $actuallyIndexed, שגיאות: $errors)',
        );
        final index = await _tantivyDataProvider.engine;
        final commitStopwatch = Stopwatch()..start();
        await index.commit();
        debugPrint('💾 commit: ${commitStopwatch.elapsedMilliseconds}ms');
        _stampCatalogueOrderAfterCommit();
      }
    } finally {
      await _setDbReadBoost(false);
      _tantivyDataProvider.isIndexing.value = false;
    }
    return cancelled
        ? IndexingRunResult.cancelled(
            processedBooks: processedBooks,
            totalBooks: totalBooks,
            indexedBooks: actuallyIndexed,
            failures: List.unmodifiable(failures),
          )
        : IndexingRunResult.completed(
            processedBooks: processedBooks,
            totalBooks: totalBooks,
            indexedBooks: actuallyIndexed,
            failures: List.unmodifiable(failures),
          );
  }

  /// מפעיל/מכבה בוסט זמני לחיבורי הקריאה של ה-DB לטובת הקריאות הרציפות
  /// הכבדות בזמן אינדוקס (כל שורות כל ספר נקראות ברצף). מכסה גם את seforim.db
  /// וגם את user_books.db — ספרי המשתמש נקראים מחיבור נפרד. user_books מבוסט
  /// רק אם כבר פתוח (כדי לא ליצור DB ריק); בזרימת אינדוקס הוא נפתח ממילא בעת
  /// טעינת הספרייה. כשלון אינו קריטי — האינדוקס ימשיך עם פרופיל הסרק החסכוני.
  Future<void> _setDbReadBoost(bool enabled) async {
    final repos = <SeforimRepository?>[
      SqliteDataProvider.instance.repository,
      UserBooksDatabaseHolder.instance.repositoryIfInitialized,
    ];
    for (final repo in repos) {
      if (repo == null) continue;
      try {
        if (enabled) {
          await repo.setReadBoostMode();
        } else {
          await repo.restoreReadCacheDefaults();
        }
      } catch (e) {
        debugPrint('[Indexing] DB read-boost toggle failed: $e');
      }
    }
  }

  /// Cancels the ongoing indexing process.
  void cancelIndexing() {
    _tantivyDataProvider.isIndexing.value = false;
  }

  /// Clears the index and resets the list of indexed books.
  Future<void> clearIndex() async {
    await _tantivyDataProvider.clear();
  }

  /// מסיר מהאינדקס את רשומות הספרים הנתונים — מחיקה מדויקת לפי מפתח
  /// ה-filePath שהמסמכים נכתבו איתו ([buildIndexedBookFilePath]), כך שספר
  /// אחר החולק את אותה כותרת אינו נפגע. מחזיר האם המחיקה נקלטה.
  Future<bool> dropBookIndexEntries(Iterable<Book> books) async {
    final keys = <String>{
      for (final book in books) buildIndexedBookFilePath(book),
    }..remove('');
    return _deleteIndexedFilePaths(keys);
  }

  /// מוחק רשומות אינדקס לפי מפתחות ה-filePath שלהן ומעדכן את המעקב בזיכרון
  /// רק אחרי commit מאושר. בכשל delete/commit מבצע שחזור מנוע אמין
  /// ([_recoverEngineAfterWriteFailure]: rollback + reopen מאולץ) ומחזיר
  /// false — כך המעקב לא מסומן כמנוקה בעוד מחיקה עלולה להיכתב לדיסק מאוחר.
  Future<bool> _deleteIndexedFilePaths(Set<String> keys) async {
    if (keys.isEmpty) return true;

    final engine = await _tantivyDataProvider.engine;
    try {
      await engine.deleteDocumentsByFilePaths(filePaths: keys.toList());
      await engine.commit();
    } catch (e) {
      // מחיקה שנכנסה ל-writer בלי commit הייתה נחתמת ע"י commit מאוחר של
      // מסלול אחר, בעוד הספר עדיין רשום כמאונדקס — rollback משליך אותה.
      debugPrint('⚠️ מחיקת רשומות אינדקס נכשלה: $e');
      await _recoverEngineAfterWriteFailure();
      return false;
    }
    _tantivyDataProvider.indexedFilePaths.removeAll(keys);
    return true;
  }

  /// מסיר מהאינדקס רשומות "יתומות" — ספרים שכבר אינם בספרייה (למשל ספר
  /// אישי שנמחק או תיקייה מותאמת שהוסרה). בלעדי זה מסמכי הספר ממשיכים
  /// לעלות בחיפוש, וגרוע מזה: מזהי המסמכים שלהם (המקודדים לפי סדר קטלוגי)
  /// עלולים להתפענח לספר אחר אחרי שהסדר השתנה.
  ///
  /// שמרני בכוונה: נוגע רק במפתחות ספרים אישיים (`uid:`) ובמפתחות
  /// נתיב-מוחלט (PDF) שהקובץ מאחוריהם כבר לא קיים בדיסק. מפתחות ספרים
  /// רשמיים (`id:`) וחיצוניים (`ext:`) לא נמחקים כאן — טעינה חלקית של
  /// הספרייה הרשמית לא תגרור מחיקת אינדקס המונית ואינדוקס-מחדש של שעות.
  ///
  /// מחזיר את מספר הספרים שהוסרו.
  Future<int> dropOrphanedIndexEntries(Library library) async {
    final books = library.getAllBooks();
    if (books.isEmpty) return 0;

    // מוודא שה-indexedFilePaths כבר נטענו מהאינדקס (חלק מאתחול המנוע).
    await _tantivyDataProvider.engine;

    final libraryKeys = <String>{
      for (final book in books) buildIndexedBookFilePath(book),
    };

    final orphans = <String>{};
    // snapshot — הלולאה מכילה await ואסור שהסט החי ישתנה תחתיה.
    for (final key in _tantivyDataProvider.indexedFilePaths.toList()) {
      if (libraryKeys.contains(key)) continue;
      if (key.startsWith('uid:')) {
        orphans.add(key);
      } else if (p.isAbsolute(key) && !await File(key).exists()) {
        orphans.add(key);
      }
    }
    if (orphans.isEmpty) return 0;

    // כשל delete/commit ⇒ שחזור מנוע והחזרת 0: המעקב לא סומן כמנוקה, כך
    // שקובץ שיחזור לספרייה לא יידלג בטעות כ"מאונדקס".
    if (!await _deleteIndexedFilePaths(orphans)) return 0;
    debugPrint('🧹 נוקו ${orphans.length} ספרים יתומים מהאינדקס');
    return orphans.length;
  }

  /// מסיר מהאינדקס רשומות של ספרי-קובץ שנתיבם השתנה בהעברת הספרייה.
  ///
  /// רשומות אלו מאונדקסות לפי נתיב מוחלט (PDF, וספרי קובץ ללא id יציב),
  /// ולכן אחרי העברה הן מצביעות לנתיב הישן. בלי הסרתן, האינדוקס האוטומטי
  /// שלאחר הרענון מוסיף את אותם ספרים בנתיב החדש ⇒ כפילויות ותוצאות שבורות.
  Future<bool> dropRelocatedFileBookEntries(
    Iterable<Book> relocatedBooks,
  ) async => dropBookIndexEntries(relocatedBooks);

  /// מאנדקס מחדש ספרים שתוכנם השתנה: מסיר את רשומותיהם הישנות מהאינדקס
  /// ומאנדקס אותם מחדש דרך [indexBooks].
  ///
  /// מחזיר תוצאה מפורטת; ביטול כולל מצב שבו נדרש אינדוקס ידני מלא או
  /// שמחיקת הרשומות הישנות נכשלה.
  Future<IndexingRunResult> reindexChangedBooks(
    List<Book> changedBooks,
    Library library, {
    void Function()? onActualIndexingStarted,
    required void Function(int processed, int total) onProgress,
  }) async {
    if (changedBooks.isEmpty) {
      return const IndexingRunResult.completed(
        processedBooks: 0,
        totalBooks: 0,
        indexedBooks: 0,
      );
    }
    if (await requiresManualReindex(library)) {
      return IndexingRunResult.cancelled(
        processedBooks: 0,
        totalBooks: changedBooks.length,
        indexedBooks: 0,
      );
    }

    // המחיקה מדויקת לפי מפתח ה-filePath של כל ספר, ולכן אין צורך להרחיב
    // לספרים אחרים החולקים כותרת — מאנדקסים מחדש רק את מה שבאמת השתנה.
    final booksToReindex = changedBooks.where(isIndexableBook).toList();
    if (booksToReindex.isEmpty) {
      return IndexingRunResult.completed(
        processedBooks: changedBooks.length,
        totalBooks: changedBooks.length,
        indexedBooks: 0,
      );
    }

    if (!await dropBookIndexEntries(booksToReindex)) {
      return IndexingRunResult.cancelled(
        processedBooks: 0,
        totalBooks: booksToReindex.length,
        indexedBooks: 0,
        failures: [
          IndexingFailure(
            bookTitle: booksToReindex.first.title,
            bookPath: buildIndexedBookFilePath(booksToReindex.first),
            kind: IndexingFailureKind.engineWrite,
            error: 'מחיקת רשומות האינדקס הישנות נכשלה',
          ),
        ],
      );
    }
    return indexBooks(
      booksToReindex,
      library,
      onActualIndexingStarted: onActualIndexingStarted,
      onProgress: onProgress,
    );
  }

  /// משווה את טביעות-האצבע שבאינדקס מול תוכן הספרייה הנוכחי ומאנדקס מחדש
  /// רק ספרים שתוכנם השתנה — מכסה מסלולים שבהם איש לא דיווח מה השתנה
  /// (למשל הורדה מלאה של הספרייה, שמחליפה את ה-DB כולו).
  ///
  /// סורק ספרי טקסט בלבד: ל-PDF אין טביעת אצבע (תוכנו לא ב-DB), והוא מכוסה
  /// ע"י זיהוי mtime/גודל בסריקת הקבצים. ספר שאינו באינדקס מדולג — מסלול
  /// הספרים החדשים (StartIndexing/IndexSpecificBooks) מטפל בו.
  ///
  /// [onScanProgress] מדווח על שלב הסריקה (קריאת ה-DB והשוואה);
  /// [onProgress] מדווח על שלב האינדוקס-מחדש של הספרים שנמצאו שונים.
  /// מחזיר תוצאה מפורטת; ריצה ללא שינויים נחשבת השלמה נקייה.
  ///
  /// [loadText] ו-[fingerprintOf] ניתנים להזרקה בטסטים בלבד.
  Future<IndexingRunResult> reconcileIndexWithLibrary(
    Library library, {
    void Function(int processed, int total)? onScanProgress,
    void Function()? onActualIndexingStarted,
    required void Function(int processed, int total) onProgress,
    @visibleForTesting Future<String?> Function(TextBook book)? loadText,
    @visibleForTesting
    Future<BigInt> Function(TextBook book, String text)? fingerprintOf,
  }) async {
    if (await _blockIndexingOnTempFallback() ||
        await requiresManualReindex(library)) {
      return const IndexingRunResult.cancelled(
        processedBooks: 0,
        totalBooks: 0,
        indexedBooks: 0,
      );
    }

    final engine = await _tantivyDataProvider.engine;
    final indexFingerprints = await engine.getBookFingerprints();

    final textLoader = loadText ?? _loadTextBookText;
    // שחזור אותה חתימה קנונית שהאינדוקס חותם — טקסט + metadata (קטגוריה,
    // סדר קטלוגי, דור, ממדי סינון) — דורש את אותם מוסר ומטמונים.
    final catalogueOrder = buildCatalogueOrderResolver(library);
    await Future.wait([
      GenerationCache.instance.warmUp(),
      ReferenceBooksCache.instance.warmUp(),
      BookFacetMetadataCache.instance.warmUp(),
    ]);
    // computeBookFingerprint היא קריאת FFI סינכרונית; העטיפה ה-async
    // נשמרת רק כדי לא לשבור את חתימת ההזרקה של הטסטים.
    final fingerprint =
        fingerprintOf ??
        ((TextBook book, String text) async => computeBookFingerprint(
          text: text,
          title: book.title,
          topics: _bookTopics(book),
          catalogueOrder: catalogueOrder.orderFor(catalogueOrderKey(book)),
          generationOrder: chronologicalOrderForBook(book),
          extraFacets: _bookExtraFacets(book),
        ));

    final candidates = library
        .getAllBooks()
        .where((b) => b is TextBook || b is ConvertibleDocumentBook)
        .toList();
    final total = candidates.length;
    final changed = <Book>[];
    var cancelled = false;

    // isIndexing משמש גם כחיווי עבודה וגם כערוץ הביטול של המשתמש —
    // בדיוק כמו במסלולי האינדוקס עצמם.
    _tantivyDataProvider.isIndexing.value = true;
    try {
      await _setDbReadBoost(true);
      final scanStopwatch = Stopwatch()..start();
      var processed = 0;
      for (final book in candidates) {
        if (!_tantivyDataProvider.isIndexing.value) {
          cancelled = true;
          break;
        }
        processed++;

        final indexHash = indexFingerprints[buildIndexedBookFilePath(book)];
        if (indexHash == null) {
          // הספר אינו באינדקס — ספר חדש, לא ענייננו כאן.
          onScanProgress?.call(processed, total);
          continue;
        }

        final TextBook textBook = _asTextBookForIndex(book)!;
        // ספר פגום אחד אינו מבטל את סריקת כל השאר — הוא רק אינו בר-השוואה.
        String? text;
        try {
          text = await textLoader(textBook);
        } on DocumentConversionException catch (e) {
          debugPrint('🔎 reconcile: דילוג על "${book.title}" — $e');
        }
        if (text == null) {
          // אין תוכן להשוואה (כשל טעינה) — לא נוגעים ברשומה הקיימת.
          onScanProgress?.call(processed, total);
          continue;
        }

        // hash אפס = "לא ניתן לאימות" (מסמכים סותרים / אינדוקס ישן) —
        // מאנדקסים מחדש כדי לרכוש טביעת אצבע תקינה.
        final dbHash = await fingerprint(textBook, text);
        if (indexHash == BigInt.zero || dbHash != indexHash) {
          changed.add(book);
        }

        onScanProgress?.call(processed, total);
        await Future.delayed(Duration.zero);
      }
      debugPrint(
        '🔎 reconcile: סריקת $processed/$total ספרים ב-${scanStopwatch.elapsed}',
      );
    } finally {
      await _setDbReadBoost(false);
      _tantivyDataProvider.isIndexing.value = false;
    }

    if (cancelled) {
      return IndexingRunResult.cancelled(
        processedBooks: 0,
        totalBooks: total,
        indexedBooks: 0,
      );
    }
    if (changed.isEmpty) {
      debugPrint('🔎 reconcile: האינדקס תואם את הספרייה — אין מה לעדכן');
      return IndexingRunResult.completed(
        processedBooks: total,
        totalBooks: total,
        indexedBooks: 0,
      );
    }

    debugPrint('🔁 reconcile: ${changed.length} ספרים השתנו — מאנדקס מחדש');
    return reindexChangedBooks(
      changed,
      library,
      onActualIndexingStarted: onActualIndexingStarted,
      onProgress: onProgress,
    );
  }

  /// Returns true for book types that the indexer actually processes.
  /// Non-indexable types (ExternalLibraryBook וכו') מדולגים בשקט
  /// ב-indexAllBooks, ולכן חייבים להיות מחוץ לבדיקות הסטטוס.
  /// ספרי מסמך נכללים — הם ממופים ל-TextBook ב-indexAllBooks דרך
  /// `toTextBook()`, ו-`book.text` כבר יודע לחלץ את התוכן דרך הממיר
  /// המתאים (ראה DatabaseLibraryProvider.getBookText).
  static bool isIndexableBook(Book book) =>
      book is TextBook || book is PdfBook || book is ConvertibleDocumentBook;

  /// ממפה ספר לזרימת האינדוקס של TextBook; null לסוגים שאינם טקסטואליים.
  static TextBook? _asTextBookForIndex(Book book) => switch (book) {
    final TextBook b => b,
    final ConvertibleDocumentBook b => b.toTextBook(),
    _ => null,
  };

  /// Waits until the underlying data provider is fully initialized
  /// (indexedFilePaths loaded from the index itself).
  Future<void> awaitReady() async {
    await _tantivyDataProvider.engine;
  }

  /// Checks if indexing is currently in progress.
  bool isIndexing() {
    return _tantivyDataProvider.isIndexing.value;
  }
}

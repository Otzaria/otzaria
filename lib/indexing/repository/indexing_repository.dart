import 'package:otzaria/data/book_identity.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/text_book/utils/inline_notes_utils.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';
import 'package:otzaria/indexing/models/index_update_mode.dart';
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' hide Category;
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/info/personal_folders_info.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/cache/generation_cache.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/indexing/utils/book_facet_metadata_cache.dart';
import 'package:otzaria/indexing/utils/indexing_crash_canary.dart';
import 'package:otzaria/indexing/utils/pdf_extraction_prefetcher.dart';
import 'package:otzaria/indexing/utils/pending_reindex_store.dart';
import 'package:otzaria/indexing/repository/index_change_detector.dart';
import 'package:otzaria/indexing/models/index_check_scope.dart';
import 'package:otzaria/indexing/utils/book_source_hashes.dart';
import 'package:otzaria/indexing/models/index_commit_policy.dart';
import 'package:otzaria/indexing/models/indexing_run_result.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/pdf_book/utils/pdf_font_fallback.dart';
import 'package:otzaria/pdf_book/utils/pdf_viewer_activity.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/book_facet.dart';
import 'package:otzaria/search/library_line_source.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';
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

typedef PackedPdfPages = ({
  Uint8List bytes,
  Uint32List ends,
  Uint32List pageIndexes,
});

class _PdfExtractionFailure implements Exception {
  const _PdfExtractionFailure(this.cause);

  final Object cause;

  @override
  String toString() => cause.toString();
}

class IndexingRepository {
  final TantivyDataProvider _tantivyDataProvider;

  /// רשימת ההסתרות. ניתנת להחלפה בבדיקות.
  final HiddenLibraryStore hiddenStore;

  /// מצב העדכון; "בלי ספרים אישיים" מוציא אותם גם מאינדוקס ידני.
  final IndexUpdateMode Function() indexUpdateMode;

  IndexingRepository(
    this._tantivyDataProvider, {
    this.hiddenStore = const HiddenLibraryStore(),
    this.indexUpdateMode = IndexUpdateMode.readStored,
  });

  /// הספרים שייכנסו לאינדוקס מתוך [ordered].
  ///
  /// ספר מוסתר אינו מאונדקס כלל (issue #1448). הוצאה מהאינדקס, ולא סינון של
  /// התוצאות, היא מה ששומר על מונה התוצאות ועל ספירות חלונית הסינון.
  @visibleForTesting
  static List<Book> booksForIndexing(
    List<Book> ordered, {
    required bool includePdfBooks,
    required HiddenLibrarySelection hidden,
    Library? library,
    IndexUpdateMode mode = IndexUpdateMode.all,
  }) {
    final categoryHiddenBooks = library == null
        ? const <Book>{}
        : hidden.booksHiddenByCategory(library);
    return ordered
        .where(
          (book) =>
              isIndexableBook(book) &&
              (includePdfBooks || book is! PdfBook) &&
              mode.admits(book) &&
              !hidden.excludesFromIndex(
                book,
                categoryHiddenBooks: categoryHiddenBooks,
              ),
        )
        .toList();
  }

  bool _paused = false;
  Completer<void>? _resumeGate;
  IndexingCancellationToken? _libraryBatchToken;

  /// ניתן להחלפה בבדיקות שאינן טוענות את המנוע הנייטיבי.
  @visibleForTesting
  static IndexingCancellationToken Function() newCancellationToken =
      IndexingCancellationToken.new;

  @visibleForTesting
  static Future<BigInt?> Function({
    required LibraryBookSource source,
    required int bookId,
    String? dbTitle,
    String? attachedSlug,
  })
  libraryFingerprint = libraryBookContentFingerprint;

  @visibleForTesting
  static IndexCommitPolicy Function() newCommitPolicy = IndexCommitPolicy.new;

  @visibleForTesting
  static Future<BookSourceHashes> Function({Iterable<String> attachedSlugs})
  loadSourceHashes = BookSourceHashes.load;

  @visibleForTesting
  static Future<BigInt> Function({required List<int> text}) contentFingerprint =
      computeContentFingerprintBytes;

  /// שלב הבדיקה שבתחילת [runIndexing].
  late IndexChangeDetector changeDetector = StampChangeDetector(this);

  bool get isPaused => _paused;
  bool get isEconomyIndexing => _tantivyDataProvider.isEconomyIndexing;

  /// משהה את לולאת האינדוקס לפני הספר הבא; הספר שבעיבוד מסתיים כרגיל, ושאר
  /// ספרי אצוות הספרייה שבעיבוד ינוסו שוב בהמשך.
  void pauseIndexing() {
    if (_paused) return;
    _paused = true;
    _resumeGate = Completer<void>();
    _libraryBatchToken?.cancel();
  }

  void resumeIndexing() {
    _paused = false;
    _resumeGate?.complete();
    _resumeGate = null;
  }

  /// מצב חסכוני מגביל את הכנת הספרים ואת ה-writer; חל בגבול אצווה.
  Future<void> setEconomyIndexing(bool enabled) =>
      _tantivyDataProvider.setEconomyIndexing(enabled);

  Future<void> _waitWhilePaused() async {
    while (_paused && _tantivyDataProvider.isIndexing.value) {
      await (_resumeGate?.future ?? Future<void>.value());
    }
  }

  @visibleForTesting
  Future<void> waitWhilePausedForTesting() => _waitWhilePaused();

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
      IndexingCrashedBefore _ => IndexingFailureKind.crashedApp,
      _LibraryBatchCleanupFailure _ => IndexingFailureKind.engineWrite,
      final RangeError rangeError
          when rangeError.invalidValue == -1 && rangeError.end == 3 =>
        IndexingFailureKind.pdfUnsupported,
      // מ-PDF חורגת רק פתיחת המסמך (timeout של עמוד בודד מחזיר null), וקובץ
      // ש-pdfium לא פותח תוך דקה לא ייפתח גם בניסיון הבא.
      final TimeoutException _ when error is _PdfExtractionFailure =>
        IndexingFailureKind.unreadableDocument,
      final TimeoutException _ => IndexingFailureKind.timeout,
      EncryptedDocumentException _ => IndexingFailureKind.passwordProtected,
      CorruptedDocumentException _ || UnsupportedDocumentFormatException _ =>
        IndexingFailureKind.unreadableDocument,
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
          when error is! _PdfExtractionFailure &&
              (normalized.contains('timeout') ||
                  normalized.contains('timed out')) =>
        IndexingFailureKind.timeout,
      _ when error is _PdfExtractionFailure =>
        IndexingFailureKind.pdfUnsupported,
      _ => IndexingFailureKind.unknown,
    };

    return IndexingFailure(
      bookTitle: book.title,
      bookPath: BookIdentity.indexedFilePath(book),
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

  /// האם ריצה שבוטלה צריכה לבצע commit למה שכבר נכתב.
  ///
  /// רק כשל כתיבה מצדיק זניחה: שם החוצץ הושלך במכוון.
  @visibleForTesting
  static bool shouldCommitCancelledRun({
    required int pendingBooks,
    required bool writeBufferDiscarded,
  }) => pendingBooks > 0 && !writeBufferDiscarded;

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
      book.source,
    );
    // כל מקור בטווח משלו: רשמי, אחריו אישי, ואחריו מסד מצורף.
    final base = 64 + 32 * book.source.rank;
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
    if (book.source.isOfficial && book.id != null) {
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
  /// נבדק אחרי [requiresManualReindex]: אינדקס שדורש בנייה מחדש אינו כשל פתיחה.
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
  static int _activeRuns = 0;
  static Completer<void>? _idle;

  /// מסתיים כשאין ריצת אינדוקס שכותבת למנוע. ביטול רק מסמן עצירה, וספר
  /// שבאמצע עוד נכתב ונחתם אחריו.
  static Future<void> whenIdle() =>
      _activeRuns == 0 ? Future.value() : (_idle ??= Completer<void>()).future;

  static void _runStarted() => _activeRuns++;

  static void _runEnded() {
    if (--_activeRuns > 0) return;
    _idle?.complete();
    _idle = null;
  }

  bool isBookIndexed(Book book) => _tantivyDataProvider.indexedFilePaths
      .contains(BookIdentity.indexedFilePath(book));

  /// האם האינדקס הקיים דורש איפוס ובנייה מחדש, לפי בדיקת התאימות
  /// של מנוע החיפוש (נקראת מהאינדקס עצמו).
  Future<bool> requiresManualReindex(Library library) async {
    if (shouldSkipManualReindexCheck(library)) {
      return false;
    }
    await _tantivyDataProvider.engine;
    return _tantivyDataProvider.requiresManualReindex;
  }

  /// האם קיימים ספרים בני-אינדוקס שאינם באינדקס. השוואה בזיכרון מול
  /// הרשימה שנקראה מהאינדקס עצמו - זולה מספיק לרוץ בכל עלייה.
  /// ספר שממתין להחלפה ([PendingReindexStore]) נחשב כחסר: תוכנו באינדקס ישן.
  Future<bool> hasUnindexedBooks(Library library) async {
    await _tantivyDataProvider.engine;
    final store = PendingReindexStore.forIndex(
      _tantivyDataProvider.activeIndexPath,
    );
    final stored = await store?.read();
    if (stored != null &&
        (stored.checkLibrary || stored.checkKeys.isNotEmpty)) {
      return true;
    }
    final pending = stored?.keys ?? const <String>{};
    return booksForIndexing(
      library.getIndexableBooks(),
      includePdfBooks: true,
      hidden: hiddenStore.load(),
      library: library,
      mode: indexUpdateMode(),
    ).any(
      (book) =>
          !isBookIndexed(book) ||
          pending.contains(BookIdentity.indexedFilePath(book)),
    );
  }

  int eligibleBookCount(
    Library library, {
    List<Book>? books,
    bool includePdfBooks = true,
  }) => booksForIndexing(
    books ?? library.getIndexableBooks(),
    includePdfBooks: includePdfBooks,
    hidden: hiddenStore.load(),
    library: library,
    mode: indexUpdateMode(),
  ).length;

  /// מאנדקס את כל ספרי הספרייה שחסרים באינדקס — [runIndexing] על כל הספרייה.
  Future<IndexingRunResult> indexAllBooks(
    Library library, {
    void Function()? onActualIndexingStarted,
    required void Function(int processed, int total) onProgress,
    void Function()? onFinalizing,
    bool includePdfBooks = true,
  }) => runIndexing(
    library,
    includePdfBooks: includePdfBooks,
    onActualIndexingStarted: onActualIndexingStarted,
    onProgress: onProgress,
    onFinalizing: onFinalizing,
  );

  /// בדיקה ([check]) ← לולאה אחת לספרים חדשים ([books], null לכל הספרייה)
  /// ושהשתנו, שמסמכיהם הישנים נמחקים רגע לפני כתיבתם ← commit ואיחוד אחד.
  Future<IndexingRunResult> runIndexing(
    Library library, {
    List<Book>? books,
    List<Book> changedBooks = const [],
    IndexCheckScope check = IndexCheckScope.none,
    bool includePdfBooks = true,
    void Function(int processed, int total)? onScanProgress,
    void Function(int total)? onWorkListReady,
    void Function()? onActualIndexingStarted,
    required void Function(int processed, int total) onProgress,
    void Function()? onFinalizing,
  }) async {
    final mode = indexUpdateMode();
    final hidden = hiddenStore.load();
    List<Book> eligible(List<Book> source, {bool? pdf}) => booksForIndexing(
      source,
      includePdfBooks: pdf ?? includePdfBooks,
      hidden: hidden,
      library: library,
      mode: mode,
    );
    final wholeLibrary = books == null;
    final scope = eligible(
      orderBooksForIndexing(books ?? library.getIndexableBooks()),
    );
    final explicitChanged = eligible(changedBooks);
    if (!wholeLibrary &&
        scope.isEmpty &&
        explicitChanged.isEmpty &&
        check.isNone) {
      return const IndexingRunResult.completed(
        processedBooks: 0,
        totalBooks: 0,
        indexedBooks: 0,
      );
    }

    if (await requiresManualReindex(library)) {
      debugPrint(
        '⚠️ האינדקס דורש איפוס ובנייה מחדש באישור המשתמש - מדלג על אינדוקס אוטומטי',
      );
      return IndexingRunResult.cancelled(
        processedBooks: 0,
        totalBooks: scope.length,
        indexedBooks: 0,
      );
    }
    if (await _blockIndexingOnTempFallback()) {
      return const IndexingRunResult.cancelled(
        processedBooks: 0,
        totalBooks: 0,
        indexedBooks: 0,
      );
    }

    await syncBookOrder(library);
    final libraryBooks = wholeLibrary
        ? scope
        : eligible(library.getIndexableBooks());
    // מפתח רשימת ההחלפה שאינו עוד ספר בר-אינדוקס נזרק: ניקוי היתומים מטפל בו.
    final pendingStore = PendingReindexStore.forIndex(
      _tantivyDataProvider.activeIndexPath,
    );
    final stored = await pendingStore?.read();
    final storedPending = stored?.keys ?? const <String>{};
    // בדיקה שנדחתה (ריצה שבוטלה לפני שבדקה) רצה בריצה הבאה: מלאה — בריצה על
    // כל הספרייה; של ספרים מסוימים — בכל ריצה.
    final deferredCheck = wholeLibrary && (stored?.checkLibrary ?? false);
    if (deferredCheck) {
      check = IndexCheckScope.library;
    } else if (!check.wholeLibrary && (stored?.checkKeys.isNotEmpty ?? false)) {
      final checkKeys = stored!.checkKeys;
      check = IndexCheckScope.books([
        ...check.books,
        for (final book in libraryBooks)
          if (checkKeys.contains(BookIdentity.indexedFilePath(book))) book,
      ]);
    }
    final checkKeys = {
      for (final book in check.books) BookIdentity.indexedFilePath(book),
    };
    final changedByKey = <String, Book>{
      for (final book in explicitChanged)
        BookIdentity.indexedFilePath(book): book,
    };
    if (storedPending.isNotEmpty) {
      for (final book in libraryBooks) {
        final key = BookIdentity.indexedFilePath(book);
        if (storedPending.contains(key)) {
          changedByKey.putIfAbsent(key, () => book);
        }
      }
    }
    final pending = changedByKey.keys.toSet();
    if (!setEquals(pending, storedPending) ||
        (check.wholeLibrary && !deferredCheck) ||
        !setEquals(checkKeys, stored?.checkKeys ?? const <String>{})) {
      await pendingStore?.save(
        pending,
        checkLibrary: check.wholeLibrary ? true : null,
        checkKeys: check.wholeLibrary ? null : checkKeys,
      );
    }

    // מפתחות שהוצאו מהמעקב וטרם נמחקו חוזרים אליו בסוף: מסמכיהם עדיין באינדקס.
    final removedFromIndexed = <String>{};
    List<Book> buildWorkList() {
      final indexed = _tantivyDataProvider.indexedFilePaths;
      removedFromIndexed.addAll(changedByKey.keys.where(indexed.contains));
      indexed.removeAll(changedByKey.keys);
      final seen = <String>{};
      return orderBooksForIndexing([
        for (final book in [...scope, ...changedByKey.values])
          if (!isBookIndexed(book) &&
              seen.add(BookIdentity.indexedFilePath(book)))
            book,
      ]);
    }

    var allBooks = const <Book>[];
    if (check.isNone) {
      allBooks = buildWorkList();
      if (allBooks.isEmpty) {
        debugPrint('⚡ אין ספרים לאינדוקס — כל הספרים כבר מאונדקסים');
        return const IndexingRunResult.completed(
          processedBooks: 0,
          totalBooks: 0,
          indexedBooks: 0,
        );
      }
    }

    _tantivyDataProvider.isIndexing.value = true;
    bool cancelled = false;
    // כשל כתיבה מרוקן את חוצץ ה-writer; commit אחריו היה חותם מצב חלקי.
    bool writeBufferDiscarded = false;
    final onFirstActualIndexing = _callOnce(onActualIndexingStarted);

    // חילוץ ה-PDF איטי בסדר גודל מאינדוקס ספר טקסט, ולכן חילוצי ה-PDF הבאים
    // רצים מראש ברקע בזמן שהמנוע מאנדקס את הספרים שלפניהם.
    PdfExtractionPrefetcher? prefetcher;
    var processedBooks = 0;
    var actuallyIndexed = 0;
    final commitPolicy = newCommitPolicy();
    final libraryBatches = _LibraryBatches();
    var skipped = 0;
    var errors = 0;
    final failures = <IndexingFailure>[];
    // מפתחות שמסמכיהם הישנים טרם נמחקו מה-writer.
    final replaceKeys = {...pending};

    // ספר יוצא מהרשימה רק כשנכתב מחדש ונחתם; ספר שמסמכיו הישנים נמחקו ולא
    // נכתב (ביטול, כשל) נשאר בה, אחרת היה נעלם מהאינדקס עד ריצה מלאה.
    _writtenThisRun.clear();
    Future<void> savePendingAfterCommit() async {
      final remaining = pending
          .where((k) => !_writtenThisRun.contains(k))
          .toSet();
      if (remaining.length == pending.length) return;
      pending
        ..clear()
        ..addAll(remaining);
      await pendingStore?.save(pending);
    }

    _runStarted();
    try {
      if (!check.isNone) {
        final candidates = [
          for (final book
              in check.wholeLibrary ? libraryBooks : eligible(check.books))
            if (!changedByKey.containsKey(BookIdentity.indexedFilePath(book)))
              book,
        ];
        final detected = await changeDetector.detectChanged(
          candidates,
          library: library,
          isCancelled: () => !_tantivyDataProvider.isIndexing.value,
          waitWhilePaused: _waitWhilePaused,
          onProgress: onScanProgress,
        );
        if (detected == null || !_tantivyDataProvider.isIndexing.value) {
          return IndexingRunResult.cancelled(
            processedBooks: 0,
            totalBooks: candidates.length,
            indexedBooks: 0,
          );
        }
        for (final book in detected) {
          changedByKey.putIfAbsent(
            BookIdentity.indexedFilePath(book),
            () => book,
          );
        }
        if (changedByKey.length != pending.length) {
          debugPrint('🔁 בדיקה: ${detected.length} ספרים השתנו — מוחלפים');
          pending.addAll(changedByKey.keys);
          replaceKeys.addAll(pending);
        }
        await pendingStore?.save(
          pending,
          checkLibrary: check.wholeLibrary ? false : null,
          checkKeys: const {},
        );
        allBooks = buildWorkList();
        if (allBooks.isEmpty) {
          debugPrint('🔎 בדיקה: האינדקס תואם את הספרייה — אין מה לעדכן');
          return const IndexingRunResult.completed(
            processedBooks: 0,
            totalBooks: 0,
            indexedBooks: 0,
          );
        }
      }
      final totalBooks = allBooks.length;
      final replacing = pending.isNotEmpty;
      onWorkListReady?.call(totalBooks);

      IndexingCrashCanary.start(
        _tantivyDataProvider.activeIndexPath,
        // ספר שקרס נשאר חסום כל עוד הוא בספרייה; ריצה חלקית אינה מנקה חסימות.
        pendingKeys: wholeLibrary
            ? () =>
                  (includePdfBooks
                          ? libraryBooks
                          : eligible(library.getIndexableBooks(), pdf: true))
                      .map(BookIdentity.indexedFilePath)
            : null,
      );
      final canary = IndexingCrashCanary.current;
      if (canary?.recovering ?? false) {
        // ספר שהוחלף נשאר באינדקס החתום בתוכנו הישן — אינו מעיד שלא קרס.
        canary!.forgetIndexed(
          (await (await _tantivyDataProvider.engine).getIndexedFilePaths())
              .where((key) => !pending.contains(key)),
        );
      }
      prefetcher = PdfExtractionPrefetcher(
        extract: extractPdfPagesGuarded,
        maxInFlight: IndexingCrashCanary.current?.recovering ?? false
            ? 0
            : PdfExtractionPrefetcher.defaultMaxInFlight,
      );
      final sourceHashes = await loadSourceHashes(
        attachedSlugs: [for (final book in allBooks) ?_attachedSlug(book)],
      );
      await Future.wait([
        GenerationCache.instance.warmUp(),
        ReferenceBooksCache.instance.warmUp(),
        BookFacetMetadataCache.instance.warmUp(),
      ]);

      final totalStopwatch = Stopwatch()..start();
      final commitStopwatch = Stopwatch();

      debugPrint(
        '📚 התחלת אינדוקס: $totalBooks ספרים (${pending.length} מוחלפים)',
      );

      // ספרי PDF שטופלו בניקוז המוקדם (הצלחה או כשל) — הלולאה לא מנסה
      // אותם שוב ולא סופרת אותם כמדולגים (כבר נספרו כאינדוקס/שגיאה).
      final earlyHandledBooks = <Book>{};
      bool shouldPrefetch(PdfBook candidate) => !isBookIndexed(candidate);

      bookLoop:
      for (var bookIndex = 0; bookIndex < allBooks.length; bookIndex++) {
        final book = allBooks[bookIndex];
        await _waitWhilePaused();
        if (!_tantivyDataProvider.isIndexing.value) {
          debugPrint('⚠️ אינדוקס בוטל על ידי המשתמש');
          cancelled = true;
          break;
        }
        await prefetcher.fill(
          allBooks,
          bookIndex,
          shouldPrefetch: shouldPrefetch,
        );

        // ניקוז: חילוץ שהסתיים מאונדקס מיד וסלוטו מתמלא, כך שהצינור אינו
        // נעצר. הספר הנוכחי מוחרג — מסלול הצריכה הרגיל מטפל בו.
        var reportedForDrain = false;
        while (true) {
          final ready = prefetcher.takeReady(exclude: book);
          if (ready == null) break;
          final readyBook = ready.book;
          await prefetcher.fill(
            allBooks,
            bookIndex,
            shouldPrefetch: shouldPrefetch,
          );
          earlyHandledBooks.add(readyBook);
          // דיווח לפני הכתיבה, אחרת המונה נראה תקוע לאורך אינדוקס PDF גדול.
          // פעם אחת לסבב — המיקום המדווח הוא של הלולאה ואינו זז בין הניקוזים.
          if (!reportedForDrain) {
            reportedForDrain = true;
            onProgress(bookIndex + 1, totalBooks);
          }
          try {
            await _dropReplacedDocs(replaceKeys, [readyBook]);
            final droppedPages = await _indexPdfBook(
              readyBook,
              sourceHashes: sourceHashes,
              preExtracted: ready.extraction,
              onActualIndexingStarted: onFirstActualIndexing,
            );
            if (!_tantivyDataProvider.isIndexing.value) {
              writeBufferDiscarded = !await _discardCancelledBookWrites(
                readyBook,
              );
              cancelled = true;
              break bookLoop;
            }
            _recordPartialPdfFailure(readyBook, droppedPages, failures);
            _markWritten(BookIdentity.indexedFilePath(readyBook));
            actuallyIndexed++;
            commitPolicy.recordBook();
          } catch (e, stackTrace) {
            debugPrint('❌ שגיאה באינדוקס מוקדם של ${readyBook.title}: $e');
            errors++;
            final failure = _classifyFailure(readyBook, e, stackTrace);
            failures.add(failure);
            final handled = await _markPermanentFailure(
              readyBook,
              failure,
              sourceHashes,
              failures,
              replaceKeys: replaceKeys,
            );
            if (handled) {
              commitPolicy.recordBook();
            } else if (!isBookIndexed(readyBook) &&
                !await _discardPartialBookWrites(readyBook)) {
              await _recoverEngineAfterWriteFailure();
              cancelled = true;
              writeBufferDiscarded = true;
              break bookLoop;
            }
          }
          IndexingCrashCanary.current?.end(
            BookIdentity.indexedFilePath(readyBook),
          );
        }

        var bookWasIndexed = false;
        try {
          // ספרי מסמך עוברים אינדוקס דרך זרימת TextBook (העטיפה
          // משמרת id/categoryId כדי ש-`book.text` יחלץ קובץ → text).
          // BookIdentity.keyOf של העטוף זהה למקור: כשיש id המפתח הוא
          // 'id:<id>', וכשאין — title+categoryKey+fileType+path
          // (העטיפה מעבירה filePath ?? path, ו-fileType נשמר).
          final TextBook? textBookForIndex = _asTextBookForIndex(book);
          if (textBookForIndex != null) {
            if (libraryBatches.handled.remove(book)) {
              // נוסף באצוות ספרייה קודמת, ונספר שם.
              bookWasIndexed = true;
            } else if (!isBookIndexed(book)) {
              // דיווח הספר הנוכחי כבר בתחילת עיבודו — אחרת המונה נראה
              // תקוע על הספר הקודם לאורך כל עיבוד ספר גדול.
              onProgress(bookIndex + 1, totalBooks);
              final batch = await _indexLibraryBatch(
                allBooks,
                bookIndex,
                libraryBatches,
                replaceKeys: replaceKeys,
                sourceHashes: sourceHashes,
                onActualIndexingStarted: onFirstActualIndexing,
              );
              for (final docs in batch) {
                actuallyIndexed++;
                commitPolicy.recordBook(docs: docs);
              }
              if (libraryBatches.handled.remove(book)) {
                bookWasIndexed = true;
              } else {
                if (!_tantivyDataProvider.isIndexing.value) {
                  cancelled = true;
                  break;
                }
                await _dropReplacedDocs(replaceKeys, [book]);
                final docs = await _indexTextBook(
                  textBookForIndex,
                  sourceHashes: sourceHashes,
                  onActualIndexingStarted: onFirstActualIndexing,
                );
                if (!_tantivyDataProvider.isIndexing.value) {
                  writeBufferDiscarded = !await _discardCancelledBookWrites(
                    book,
                  );
                  cancelled = true;
                  break;
                }
                _markWritten(BookIdentity.indexedFilePath(book));
                actuallyIndexed++;
                commitPolicy.recordBook(docs: docs);
                bookWasIndexed = true;
              }
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
              final preExtracted = prefetcher.take(book);
              // PDFium מעבד קריאה אחת בכל פעם: החילוץ הבא מוזנק רק כשזה הסתיים,
              // ורץ במקביל לאינדוקס של הספר הזה.
              if (preExtracted != null) await preExtracted;
              await prefetcher.fill(
                allBooks,
                bookIndex + 1,
                shouldPrefetch: shouldPrefetch,
              );
              await _dropReplacedDocs(replaceKeys, [book]);
              final droppedPages = await _indexPdfBook(
                book,
                sourceHashes: sourceHashes,
                preExtracted: preExtracted,
                onActualIndexingStarted: onFirstActualIndexing,
              );
              if (!_tantivyDataProvider.isIndexing.value) {
                writeBufferDiscarded = !await _discardCancelledBookWrites(book);
                cancelled = true;
                break;
              }
              _recordPartialPdfFailure(book, droppedPages, failures);
              _markWritten(BookIdentity.indexedFilePath(book));
              actuallyIndexed++;
              commitPolicy.recordBook();
              bookWasIndexed = true;
            } else {
              skipped++;
            }
          }

          processedBooks++;
          if (commitPolicy.isDue) {
            commitStopwatch
              ..reset()
              ..start();
            await _commitIndex();
            debugPrint(
              '💾 commit אחרי ${commitPolicy.pendingBooks} ספרים '
              '(${commitPolicy.pendingDocs} מסמכים): '
              '${commitStopwatch.elapsedMilliseconds}ms',
            );
            // גם כאן, ולא רק ב-commit הסופי: ביטול או קריסה אחרי מאות
            // ספרים שנשמרו היו מותירים אינדקס מלא בלי חותם.
            commitPolicy.committed();
            await savePendingAfterCommit();
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
          final handled = await _markPermanentFailure(
            book,
            failure,
            sourceHashes,
            failures,
            replaceKeys: replaceKeys,
          );
          if (handled) {
            commitPolicy.recordBook();
          } else if (e is _LibraryBatchCleanupFailure ||
              (!isBookIndexed(book) &&
                  !await _discardPartialBookWrites(book))) {
            // ניקוי כושל ⇒ commit היה חותם ספר חלקי; משליכים את כל החוצץ
            // ועוצרים בלי commit — מה שלא נחתם ינוסה שוב בריצה הבאה.
            await _recoverEngineAfterWriteFailure();
            cancelled = true;
            writeBufferDiscarded = true;
            break;
          }
        }

        IndexingCrashCanary.current?.end(BookIdentity.indexedFilePath(book));
        await Future.delayed(Duration.zero);
      }

      if (!cancelled) {
        // מחיקה רק מסמנת את המסמכים הישנים; בלי איחוד הם נשארים בדיסק.
        final compact = wholeLibrary || replacing;
        if (compact) onFinalizing?.call();
        debugPrint('✅ אינדוקס הושלם!');
        debugPrint('   📊 סה"כ: $totalBooks ספרים');
        debugPrint('   ✅ מאונדקסים: $actuallyIndexed');
        debugPrint('   ⏭️ דולגו: $skipped');
        debugPrint('   ❌ שגיאות: $errors');

        commitStopwatch
          ..reset()
          ..start();
        final index = await _commitIndex();
        debugPrint('💾 commit סופי: ${commitStopwatch.elapsedMilliseconds}ms');
        await savePendingAfterCommit();
        if (compact) {
          final optimizeStopwatch = Stopwatch()..start();
          await optimizeIndexBestEffort(index.optimize);
          debugPrint(
            '⚙️ optimize: ${optimizeStopwatch.elapsedMilliseconds}ms',
          );
        }
        debugPrint('⏱️ סה"כ אינדוקס: ${totalStopwatch.elapsed}');
      } else if (shouldCommitCancelledRun(
        pendingBooks: commitPolicy.pendingBooks,
        writeBufferDiscarded: writeBufferDiscarded,
      )) {
        // בלי commit בביטול, כל מה שאונדקס מאז ה-commit האחרון אבד.
        await _commitIndex();
        debugPrint('💾 commit אחרי ביטול: ${commitPolicy.pendingBooks} ספרים');
        await savePendingAfterCommit();
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
    } finally {
      _tantivyDataProvider.indexedFilePaths.addAll(
        removedFromIndexed.where(replaceKeys.contains),
      );
      prefetcher?.dispose();
      await IndexingCrashCanary.current?.finish();
      _tantivyDataProvider.isIndexing.value = false;
      _runEnded();
      await LibraryLineSource.reportLibraryFallbacks();
    }
  }

  /// מוחק את מסמכיהם הישנים של ספרים שהוחלפו, רגע לפני כתיבתם — באותו
  /// commit, כך שהספר אינו נעלם מהחיפוש לאורך הריצה.
  Future<void> _dropReplacedDocs(
    Set<String> replaceKeys,
    Iterable<Book> books,
  ) async {
    if (replaceKeys.isEmpty) return;
    final keys = [
      for (final book in books)
        if (replaceKeys.contains(BookIdentity.indexedFilePath(book)))
          BookIdentity.indexedFilePath(book),
    ];
    if (keys.isEmpty) return;
    final engine = await _tantivyDataProvider.engine;
    await engine.deleteDocumentsByFilePaths(filePaths: keys);
    replaceKeys.removeAll(keys);
  }

  /// מחזיר את מספר המסמכים שנוספו (0 כשנכתב סמן ספר ריק).
  Future<int> _indexTextBook(
    TextBook book, {
    required BookSourceHashes sourceHashes,
    void Function()? onActualIndexingStarted,
  }) async {
    // כל הכנת הספר — פיצול לשורות, מעקב reference trail, נרמול, טביעת
    // אצבע ואינדוקס — רצה במנוע בקריאת FFI אחת: התוכן חוצה את הגשר פעם
    // אחת בלבד. במסלול הרגיל (ספר מ-DB) התוכן נקרא כבייטים גולמיים
    // (UTF-8 כפי שמאוחסן ב-SQLite) ונמסר ל-addTextBookBytes — בלי פענוח
    // ל-String וקידוד חוזר על הגשר (~180ms/MB שנמדדו בלוגים).
    await _beginBook(book);
    final loadStopwatch = Stopwatch()..start();
    final source = await loadTextBookSource(book);
    final bytes = source.bytes;
    final text = source.text;
    loadStopwatch.stop();

    final hasBytes = bytes != null && bytes.isNotEmpty;
    final hasText = text != null && text.isNotEmpty;
    var added = 0;

    if (hasBytes || hasText) {
      // הביטול נבדק לפני הקריאה; בתוך ספר בודד הכתיבה אטומית מבחינתנו.
      onActualIndexingStarted?.call();
      if (!_tantivyDataProvider.isIndexing.value) {
        return 0;
      }
      final engine = await _tantivyDataProvider.engine;
      final title = book.title;
      final topics = _bookTopics(book);
      final filePath = BookIdentity.indexedFilePath(book);
      final engineStopwatch = Stopwatch()..start();
      final extraFacets = _bookExtraFacets(book);
      final textStorage = textStorageFor(
        filePath: filePath,
        libraryDbBookId: source.libraryDbBookId,
        userBooksDbBookId: source.userBooksDbBookId,
        attachedDbBookId: source.attachedDbBookId,
        hostApiReady: LibraryLineSource.hostApiReady,
        userBooksConfigured: LibraryLineSource.userBooksConfigured,
        attachedConfigured: _attachedEngineSourceConfigured,
      );
      final storedLines = textStorage == TextStorage.libraryDb
          ? source.dataUriLines
          : null;
      // קידוד String על גשר המנוע רץ על ה-UI isolate (337ms לספר של 18M תווים).
      final payload = hasBytes ? bytes : await _utf8EncodeOffFrame(text!);
      added = await engine.addTextBookBytes(
        title: title,
        topics: topics,
        filePath: filePath,
        text: payload,
        sourceHash: _dbSourceHash(book, sourceHashes),
        extraFacets: extraFacets,
        textStorage: textStorage,
        storedLines: storedLines,
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
    } else {
      debugPrint('⚠️ ספר ריק: ${book.title} - מדלג');
    }

    if (added == 0) {
      // אין תוכן ⇒ אין טביעת אצבע; במסלול המלא המנוע חותם אותה בעצמו.
      await _writeEmptyBookMarker(
        book,
        sourceHashes: sourceHashes,
      );
    }
    return added;
  }

  /// המסד שהמנוע קורא ממנו בעצמו את שורות הספר (`addLibraryBooks`), או null
  /// למסלול הרגיל: אותם ספרים שנשמרים כ-[TextStorage.libraryDb] היום.
  @visibleForTesting
  static LibraryBookSource? engineBookSource(
    Book book, {
    required bool hostApiReady,
    required bool userBooksConfigured,
    bool Function(String slug) attachedConfigured = _noAttachedSource,
  }) {
    final id = book.id;
    if (!hostApiReady || book is! TextBook || id == null) return null;
    if (book.categoryId == null) return null;
    final key = BookIdentity.indexedFilePath(book);
    return switch (book.source) {
      OfficialBookSource() when key == BookIdentity.officialBookKey(id) =>
        LibraryBookSource.library_,
      // ספר מקובץ: השורות במסד נבנות בסריקה, והתצוגה קוראת את הקובץ.
      UserBookSource()
          when userBooksConfigured &&
              key == BookIdentity.userBookKey(id) &&
              (book.filePath?.trim().isEmpty ?? true) =>
        LibraryBookSource.userBooks,
      AttachedBookSource(:final slug)
          when attachedConfigured(slug) &&
              key == BookIdentity.attachedBookKey(slug, id) =>
        LibraryBookSource.attached,
      _ => null,
    };
  }

  LibraryBookSource? _engineBookSource(Book book) => engineBookSource(
    book,
    hostApiReady: LibraryLineSource.hostApiReady,
    userBooksConfigured: LibraryLineSource.userBooksConfigured,
    attachedConfigured: _attachedEngineSourceConfigured,
  );

  static String? _attachedSlug(Book book) => switch (book.source) {
    AttachedBookSource(:final slug) => slug,
    _ => null,
  };

  LibraryBookInput _libraryBookInput(
    TextBook book,
    LibraryBookSource source,
    BookSourceHashes sourceHashes,
  ) => LibraryBookInput(
    source: source,
    attachedSlug: _attachedSlug(book),
    bookId: book.id!,
    // כמו קריאת האפליקציה: id שעבר לספר אחר בעדכון ספרייה אינו נקרא.
    dbTitle: book.title,
    title: book.title,
    topics: _bookTopics(book),
    filePath: BookIdentity.indexedFilePath(book),
    extraFacets: _bookExtraFacets(book),
    textStorage: TextStorage.libraryDb,
    sourceHash: _dbSourceHash(book, sourceHashes),
  );

  /// מאנדקס במנוע את רצף ספרי הספרייה מ-[start] ומחזיר את מסמכי כל ספר שנוסף.
  /// ספר שהמנוע לא הוסיף נשאר למסלול הרגיל; ספר שהאצווה בוטלה לפניו — לאצווה הבאה.
  Future<List<int>> _indexLibraryBatch(
    List<Book> books,
    int start,
    _LibraryBatches batches, {
    required Set<String> replaceKeys,
    required BookSourceHashes sourceHashes,
    void Function()? onActualIndexingStarted,
  }) async {
    final added = <int>[];
    final first = books[start];
    while (!batches.disabled &&
        _engineBookSource(first) != null &&
        !batches.attempted.contains(first) &&
        !isBookIndexed(first)) {
      await _waitWhilePaused();
      if (!_tantivyDataProvider.isIndexing.value) break;
      final canary = IndexingCrashCanary.current;
      // אחרי קריסה מאנדקסים ספר-ספר, כדי שרק האשם ייספר.
      final limit = canary?.recovering ?? false ? 1 : batches.sizer.size;
      final picked = <(TextBook, LibraryBookSource)>[];
      final pickedKeys = <String>{};
      for (var i = start; i < books.length && picked.length < limit; i++) {
        final book = books[i];
        final key = BookIdentity.indexedFilePath(book);
        if (batches.handled.contains(book) ||
            isBookIndexed(book) ||
            pickedKeys.contains(key)) {
          continue;
        }
        final source = _engineBookSource(book);
        if (source == null ||
            batches.attempted.contains(book) ||
            canary?.begin(key) == false) {
          break;
        }
        pickedKeys.add(key);
        picked.add((book as TextBook, source));
      }
      await canary?.flush();
      if (picked.isEmpty) break;

      onActualIndexingStarted?.call();
      final engine = await _tantivyDataProvider.engine;
      final token = newCancellationToken();
      void cancelOnStop() {
        if (!_tantivyDataProvider.isIndexing.value) token.cancel();
      }

      _tantivyDataProvider.isIndexing.addListener(cancelOnStop);
      _libraryBatchToken = token;
      final stopwatch = Stopwatch()..start();
      final List<LibraryBookResult> results;
      try {
        await engine.openIndexWriter();
        await _dropReplacedDocs(replaceKeys, [
          for (final (book, _) in picked) book,
        ]);
        results = await engine.addLibraryBooks(
          books: [
            for (final (book, source) in picked)
              _libraryBookInput(book, source, sourceHashes),
          ],
          cancel: token,
        );
      } catch (error) {
        // ספרי האצווה עלולים להיות ב-writer חלקית; המסלול הרגיל ינסה אותם
        // ספר-ספר, ומחיקה שנכשלה עוצרת את הריצה כמו כשל כתיבה של ספר.
        debugPrint('⚠️ אצוות ספרייה נכשלה, חוזרים לאינדוקס ספר-ספר: $error');
        batches.disabled = true;
        try {
          await engine.deleteDocumentsByFilePaths(
            filePaths: [
              for (final (book, _) in picked)
                BookIdentity.indexedFilePath(book),
            ],
          );
        } catch (error) {
          throw _LibraryBatchCleanupFailure(error);
        }
        break;
      } finally {
        _libraryBatchToken = null;
        _tantivyDataProvider.isIndexing.removeListener(cancelOnStop);
      }
      stopwatch.stop();

      var docs = 0;
      var indexedBooks = 0;
      var cancelledBooks = 0;
      for (var i = 0; i < picked.length; i++) {
        final (book, _) = picked[i];
        final result = results[i];
        switch (result.status) {
          case LibraryBookStatus.indexed:
            final key = BookIdentity.indexedFilePath(book);
            _markWritten(key);
            batches.handled.add(book);
            canary?.end(key);
            added.add(result.docs);
            indexedBooks++;
            docs += result.docs;
          case LibraryBookStatus.cancelled:
            cancelledBooks++;
          case LibraryBookStatus.missing ||
              LibraryBookStatus.unavailable ||
              LibraryBookStatus.failed:
            batches.attempted.add(book);
        }
      }
      if (cancelledBooks == 0) {
        batches.sizer.recordBatch(picked.length, stopwatch.elapsed);
      }
      debugPrint(
        '📚 אצוות ספרייה: ${picked.length} ספרים → $indexedBooks נוספו '
        '($docs מסמכים), $cancelledBooks בוטלו | '
        '${stopwatch.elapsedMilliseconds}ms',
      );
      if (!token.isCancelled) break;
    }
    return added;
  }

  Future<int> _indexPdfBook(
    PdfBook book, {
    required BookSourceHashes sourceHashes,
    void Function()? onActualIndexingStarted,
    Future<PdfExtraction>? preExtracted,
  }) async {
    // חילוץ מוקדם וישיר שומרים שגיאות בתוצאה; חסימת קריסה חלה גם על OCR.
    final extracted = await (preExtracted ?? extractPdfPagesGuarded(book));
    final pages = extracted.pages;
    final outline = extracted.outline;
    final openError = extracted.error;
    final openStackTrace = extracted.stackTrace;
    if (openError is IndexingCrashedBefore) {
      Error.throwWithStackTrace(openError, openStackTrace!);
    }

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
        sourceHashes: sourceHashes,
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
          sourceHashes: sourceHashes,
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
        sourceHashes: sourceHashes,
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

  /// שולח את עמודי ה-PDF למנוע בקריאת FFI אחת (נרמול, סינון זבל ואינדוקס
  /// בתוך המנוע) ומחזיר את מספר המסמכים שנוספו.
  Future<int> _addPdfBookToEngine(
    PdfBook book,
    List<({String reference, String text, int pageIndex})> pages, {
    required BookSourceHashes sourceHashes,
    void Function()? onActualIndexingStarted,
  }) async {
    onActualIndexingStarted?.call();
    // FRB מקודד ומפענח את הארגומנטים על ה-UI thread; רשימת עמודים גדולה הקפיאה
    // אותו (#3443). חוצץ בתים שנארז ב-isolate עובר כהעתקה אחת.
    final packed = await _packPdfPagesOffFrame(pages);
    if (!_tantivyDataProvider.isIndexing.value) {
      return 0;
    }
    final engine = await _tantivyDataProvider.engine;
    final engineStopwatch = Stopwatch()..start();
    final added = await engine.addPdfBookBytes(
      title: book.title,
      topics: _bookTopics(book),
      filePath: BookIdentity.indexedFilePath(book),
      extraFacets: _bookExtraFacets(book),
      bytes: packed.bytes,
      ends: packed.ends,
      pageIndexes: packed.pageIndexes,
    );
    engineStopwatch.stop();
    debugPrint(
      '📄 "${book.title}": ${pages.length} עמודים → $added מסמכים | '
      'מנוע ${engineStopwatch.elapsedMilliseconds}ms',
    );
    return added;
  }

  static Future<PackedPdfPages> _packPdfPagesOffFrame(
    List<({String reference, String text, int pageIndex})> pages,
  ) => Isolate.run(() => packPdfPages(pages));

  /// אורז את העמודים לפורמט של `addPdfBookBytes`: לכל עמוד ההפניה ואחריה
  /// הטקסט ב-UTF-8, ו-[PackedPdfPages.ends] מחזיק את סוף כל אחד מהם.
  @visibleForTesting
  static PackedPdfPages packPdfPages(
    List<({String reference, String text, int pageIndex})> pages,
  ) {
    final builder = BytesBuilder(copy: false);
    final ends = Uint32List(pages.length * 2);
    final pageIndexes = Uint32List(pages.length);
    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      builder.add(utf8.encode(page.reference));
      ends[2 * i] = builder.length;
      builder.add(utf8.encode(page.text));
      ends[2 * i + 1] = builder.length;
      pageIndexes[i] = page.pageIndex;
    }
    return (
      bytes: builder.takeBytes(),
      ends: ends,
      pageIndexes: pageIndexes,
    );
  }

  /// רושם באינדקס מסמך ריק יחיד עבור ספר שלא הניב תוכן לאינדוקס (למשל PDF
  /// סרוק ללא שכבת טקסט). מסמך ריק לעולם לא עולה בתוצאות חיפוש, אבל הוא
  /// גורם לאינדקס עצמו לזכור שהספר כבר עובד — כך הוא לא יעובד מחדש בכל
  /// הפעלה. בלי זה, מצב האינדוקס (שנקרא מהאינדקס) לעולם לא היה שלם.
  Future<void> _writeEmptyBookMarker(
    Book book, {
    required BookSourceHashes sourceHashes,
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
          ordinal: 0,
          title: book.title,
          reference: '',
          topics: _bookTopics(book),
          text: '',
          segment: BigInt.zero,
          isPdf: book is PdfBook,
          filePath: BookIdentity.indexedFilePath(book),
          extraFacets: _bookExtraFacets(book),
          sourceHash: _dbSourceHash(book, sourceHashes),
          // טביעת הטקסט הריק: כך ספר שנשאר ריק נמצא תואם בבדיקה הבאה.
          textHash: book is PdfBook
              ? null
              : await contentFingerprint(text: const []),
        ),
      ],
    );
  }

  /// כשל קבוע מקבל סמן ריק באינדקס, אחרת הספר "חסר" לנצח ומפעיל ריצת
  /// אינדוקס מלאה בכל עלייה.
  Future<bool> _markPermanentFailure(
    Book book,
    IndexingFailure failure,
    BookSourceHashes sourceHashes,
    List<IndexingFailure> failures, {
    Set<String> replaceKeys = const {},
  }) async {
    if (failure.isRetryable) return false;
    if (!_tantivyDataProvider.isIndexing.value) return false;

    try {
      await _dropReplacedDocs(replaceKeys, [book]);
      await _writeEmptyBookMarker(
        book,
        sourceHashes: sourceHashes,
      );
    } catch (error, stackTrace) {
      failures.add(
        IndexingFailure(
          bookTitle: book.title,
          bookPath: BookIdentity.indexedFilePath(book),
          kind: IndexingFailureKind.engineWrite,
          error: error.toString(),
          stackTrace: stackTrace.toString(),
        ),
      );
      debugPrint('⚠️ כתיבת סמן כשל קבוע עבור ${book.title} נכשלה: $error');
      return false;
    }
    if (!_tantivyDataProvider.isIndexing.value) return false;

    _markWritten(BookIdentity.indexedFilePath(book));
    return true;
  }

  /// ספרים שנכתבו בריצה הנוכחית — רק הם יוצאים מרשימת ההחלפה אחרי commit.
  final Set<String> _writtenThisRun = {};

  void _markWritten(String key) {
    _tantivyDataProvider.indexedFilePaths.add(key);
    _writtenThisRun.add(key);
  }

  /// מוחק את המסמכים החלקיים של ספר שכתיבתו למנוע נכשלה באמצע: בלעדי זה
  /// ה-commit הבא חותם ספר חלקי, שנחשב "מאונדקס" ולעולם לא מנוסה שוב.
  Future<bool> _discardPartialBookWrites(Book book) async {
    try {
      final engine = await _tantivyDataProvider.engine;
      await engine.deleteDocumentsByFilePaths(
        filePaths: [BookIdentity.indexedFilePath(book)],
      );
      return true;
    } catch (e) {
      debugPrint('⚠️ מחיקת מסמכים חלקיים של ${book.title} נכשלה: $e');
      return false;
    }
  }

  /// ביטול עשוי להגיע אחרי שהמנוע כתב ספר אך לפני שנרשם במעקב. אין לחתום
  /// אותו יחד עם הספרים הקודמים; מחיקה לפי מפתח הספר בטוחה גם אם טרם נכתב.
  Future<bool> _discardCancelledBookWrites(Book book) async {
    if (await _discardPartialBookWrites(book)) return true;
    await _recoverEngineAfterWriteFailure();
    return false;
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

  // ספר שהפיל את התהליך פעמיים ברצף נזרק, ומסומן ככשל קבוע במקום לנסותו לעד.
  Future<void> _beginBook(Book book) async {
    final canary = IndexingCrashCanary.current;
    if (canary?.begin(BookIdentity.indexedFilePath(book)) == false) {
      throw const IndexingCrashedBefore();
    }
    await canary?.flush();
  }

  /// עוטפת את [_extractPdfPages] כך שהתוצאה לעולם אינה זריקה: שגיאת פתיחה
  /// נשמרת בתוצאה (הקורא מכריע בין sidecar להפצתה), ומשך החילוץ נמדד כאן —
  /// כך גם חילוץ שרץ מראש (prefetch) מדווח את זמנו האמיתי.
  @visibleForTesting
  Future<PdfExtraction> extractPdfPagesGuarded(PdfBook book) async {
    final stopwatch = Stopwatch()..start();
    try {
      await _beginBook(book);
      // pdfium של האינדוקס ממתין בתור ה-worker לכל עבודה אחרת (הקורא קודם).
      final extracted = await Pdfrx.runAsBackgroundWork(
        () => _extractPdfPages(book),
      );
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

    // הקורא קודם — טאב שממתין לעמוד היעד לא יחכה בתור מאחורי האינדוקס.
    await PdfViewerActivity.instance.waitUntilIdle();
    final document = await PdfFontFallback.openFile(
      book.path,
    ).timeout(const Duration(seconds: 60));
    try {
      final outline = await document.loadOutline().timeout(
        const Duration(seconds: 15),
        onTimeout: () => <PdfOutlineNode>[],
      );

      final extracted = await extractPageTextsWithRetry(
        pageCount: document.pages.length,
        loadPageText: (i) async {
          final text = await document.pages[i].loadText().timeout(
            const Duration(seconds: 5),
            onTimeout: () => null,
          );
          return text?.fullText;
        },
        beforeEachPage: () async {
          if (!_tantivyDataProvider.isIndexing.value) return false;
          await PdfViewerActivity.instance.waitUntilIdle();
          return true;
        },
      );
      if (extracted == null) return empty;

      final pages = <({String reference, String text, int pageIndex})>[];
      for (final entry in extracted.texts.entries) {
        final i = entry.key;
        final bookmark = referenceFromPageNumber(i + 1, outline, book.title);
        final ref = bookmark.isNotEmpty
            ? '${book.title}, $bookmark, עמוד ${i + 1}'
            : '${book.title}, עמוד ${i + 1}';
        pages.add((reference: ref, text: entry.value, pageIndex: i));
      }

      if (extracted.droppedPages > 0) {
        debugPrint(
          '⚠️ "${book.title}": ${extracted.droppedPages} עמודים נשמטו '
          'מהחילוץ (timeout)',
        );
      }

      return (
        pages: pages,
        outline: outline,
        droppedPages: extracted.droppedPages,
      );
    } finally {
      // בלי סגירה מפורשת המסמך נשאר פתוח ב-pdfium עד סוף התהליך: אין
      // Finalizer על העטיפה, ו-FPDF_CloseDocument נקרא רק מ-dispose.
      await document.dispose();
    }
  }

  /// טקסט העמודים לפי אינדקס, בסדר עולה. עמוד שחרג מה-timeout (null) מנוסה
  /// שוב פעם אחת בסוף הספר, כשה-worker של pdfium כבר פנוי.
  ///
  /// סדרתי בכוונה: כל קריאות pdfium מסורלות דרך worker יחיד, ותקיעה של עמוד
  /// אחד מפילה את הטיימרים של העמודים שממתינים אחריו בתור — הניסיון החוזר
  /// מחזיר אותם. מחזיר null כשה-[beforeEachPage] ביטל את האינדוקס.
  @visibleForTesting
  static Future<({Map<int, String> texts, int droppedPages})?>
  extractPageTextsWithRetry({
    required int pageCount,
    required Future<String?> Function(int pageIndex) loadPageText,
    required Future<bool> Function() beforeEachPage,
  }) async {
    final texts = SplayTreeMap<int, String>();
    final timedOut = <int>[];
    for (int i = 0; i < pageCount; i++) {
      if (!await beforeEachPage()) return null;
      final text = await loadPageText(i);
      if (text == null) {
        timedOut.add(i);
      } else {
        texts[i] = text;
      }
    }

    var droppedPages = 0;
    for (final i in timedOut) {
      if (!await beforeEachPage()) return null;
      final text = await loadPageText(i);
      if (text == null) {
        droppedPages++;
      } else {
        texts[i] = text;
      }
    }
    return (texts: texts, droppedPages: droppedPages);
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
      final bookmark = referenceFromPageNumber(
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
    const minPayloadLength = _minDataUriPayload;
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

  static const _minDataUriPayload = 64;

  /// השורות (0-based, לפי `\n`) ש-[stripDataUrisForIndex] מסיר מהן data URI.
  /// המנוע שומר את הטקסט המנוקה שלהן באינדקס במקום לקרוא מהמסד את התמונה.
  @visibleForTesting
  static Uint32List dataUriLineOrdinals(Uint8List bytes) {
    final lines = <int>[];
    var line = 0;
    var i = 0;
    while (i < bytes.length) {
      final byte = bytes[i];
      if (byte == 0x0A) {
        line++;
      } else if (byte == 0x64 &&
          i + 5 <= bytes.length &&
          bytes[i + 1] == 0x61 &&
          bytes[i + 2] == 0x74 &&
          bytes[i + 3] == 0x61 &&
          bytes[i + 4] == 0x3A) {
        var end = i + 5;
        while (end < bytes.length && _isDataUriChar(bytes[end])) {
          end++;
        }
        if (end - i - 5 >= _minDataUriPayload &&
            (lines.isEmpty || lines.last != line)) {
          lines.add(line);
        }
        i = end;
        continue;
      }
      i++;
    }
    return Uint32List.fromList(lines);
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

  /// מעל הסף הזה (בייטים או תווים) עבודת ה-data URI מפסיקה לרוץ ברצף על
  /// ה-thread שמצייר פריימים. נמדד על ספר מצויר (226MiB): סריקה + פענוח +
  /// בנייה מחדש = 1.4 שניות. מתחת לסף הכול יחד הוא מילישניות בודדות.
  static const int _dataUriOffFrameThreshold = 1 << 20;

  /// מנת הסריקה. נמדד 0.72ms/MiB, ולכן 4MiB ≈ 4.4ms — בתוך תקציב פריים גם
  /// ב-120Hz, בלי לפרק את הסריקה ליותר מדי סבבי event loop.
  static const int _dataUriScanChunk = 4 << 20;

  /// זהה ל-[bytesContainDataUriScheme] + [stripDataUrisForIndex], בלי לחסום
  /// פריים בספר גדול: הסריקה נפרסת למנות על ה-thread הקורא, ורק כשנמצא
  /// `data:` הפענוח והבנייה מחדש עוברים ל-isolate. [bytes] נשמר רק כשהוא
  /// נקי; אחרת [text] מחזיק את המקור המנוקה, ו-[dataUriLines] את
  /// [dataUriLineOrdinals] שלו (null כשאין).
  ///
  /// הסריקה רצה **פעם אחת**, וכאן — תוצאתה היא שמכריעה אם צריך isolate
  /// בכלל. גרסה שסרקה כאן וגם שוב בתוך ה-isolate הכפילה את החסימה.
  @visibleForTesting
  static Future<({Uint8List? bytes, String? text, Uint32List? dataUriLines})>
  cleanDataUrisOffFrame(Uint8List bytes) async {
    if (bytes.length < _dataUriOffFrameThreshold) {
      if (!bytesContainDataUriScheme(bytes)) {
        return (bytes: bytes, text: null, dataUriLines: null);
      }
      final cleaned = _stripDataUriBytes(bytes);
      return (bytes: null, text: cleaned.text, dataUriLines: cleaned.lines);
    }
    if (!await _containsDataUriInChunks(bytes)) {
      return (bytes: bytes, text: null, dataUriLines: null);
    }
    // מעבירים בעלות על הבתים במקום ללכוד Uint8List ב-closure: שליחת רשימה
    // mutable ל-isolate מעתיקה אותה, ובספר מצויר גדול מוסיפה עותק שלם לשיא
    // הזיכרון. אחרי הסריקה החיובית אין עוד צורך להחזיק במסלול ה-bytes.
    final transferable = TransferableTypedData.fromList([bytes]);
    final cleaned = await Isolate.run(
      () => _stripDataUriBytes(transferable.materialize().asUint8List()),
    );
    return (bytes: null, text: cleaned.text, dataUriLines: cleaned.lines);
  }

  static ({String text, Uint32List? lines}) _stripDataUriBytes(
    Uint8List bytes,
  ) {
    final lines = dataUriLineOrdinals(bytes);
    return (
      text: stripDataUrisForIndex(utf8.decode(bytes, allowMalformed: true)),
      lines: lines.isEmpty ? null : lines,
    );
  }

  /// המנות חופפות ב-4 בייטים — בלי החפיפה `data:` שיושב על תפר בין מנות
  /// נעלם, וספר מצויר נחשב נקי.
  static Future<bool> _containsDataUriInChunks(Uint8List bytes) async {
    const overlap = 4; // 'data:'.length - 1
    for (var start = 0; start < bytes.length; start += _dataUriScanChunk) {
      var end = start + _dataUriScanChunk + overlap;
      if (end > bytes.length) end = bytes.length;
      if (bytesContainDataUriScheme(Uint8List.sublistView(bytes, start, end))) {
        return true;
      }
      await Future<void>.delayed(Duration.zero);
    }
    return false;
  }

  static Future<Uint8List> _utf8EncodeOffFrame(String text) =>
      Isolate.run(() => utf8.encode(text));

  /// [stripDataUrisForIndex] בלי לחסום פריים בספר גדול. כאן, בשונה ממסלול
  /// ה-bytes, גם הסריקה עוברת ל-isolate: מחרוזת אינה מועתקת בהעברה (נמדד
  /// 0ms על 20M תווים), ולכן בדיקה מקדימה כאן רק הייתה מכפילה את החסימה.
  @visibleForTesting
  static Future<String> stripDataUrisOffFrame(String text) {
    if (text.length < _dataUriOffFrameThreshold) {
      return Future.value(stripDataUrisForIndex(text));
    }
    return Isolate.run(() => stripDataUrisForIndex(text));
  }

  /// מקור הספר בדיוק כפי שנמסר למנוע באינדוקס: bytes גולמיים מה-DB כשאפשר
  /// (בלי פענוח/קידוד על ה-UI isolate), וירידה לטקסט מפוענח ומנוקה רק
  /// כשחייבים (תמונות מוטמעות, פורמט מומר, ספר בלי categoryId). משותף
  /// לאינדוקס ולאימות הטריות — כך שתי החתימות מחושבות על אותו קלט בדיוק.
  /// [libraryDbBookId] — ה-id ב-seforim.db כשהמקור הוא שורות הספר משם;
  /// [userBooksDbBookId] — כמוהו ב-user_books.db, [attachedDbBookId] — במסד מצורף.
  /// [dataUriLines] — השורות שנוקו מהן תמונות; ראו [dataUriLineOrdinals].
  @visibleForTesting
  Future<
    ({
      Uint8List? bytes,
      String? text,
      int? libraryDbBookId,
      int? userBooksDbBookId,
      int? attachedDbBookId,
      Uint32List? dataUriLines,
    })
  >
  loadTextBookSource(TextBook book) async {
    Uint8List? bytes;
    String? text;
    int? libraryDbBookId;
    int? userBooksDbBookId;
    int? attachedDbBookId;
    Uint32List? dataUriLines;
    if (book.categoryId != null) {
      final fromDb = await SqliteDataProvider.instance.getBookTextBytesFromDb(
        book.title,
        book.categoryId,
        book.fileType ?? 'txt',
        book.source,
      );
      bytes = fromDb?.bytes;
      libraryDbBookId = fromDb?.officialBookId;
      userBooksDbBookId = fromDb?.userBookId;
      attachedDbBookId = fromDb?.attachedBookId;
      if (bytes != null && libraryDbBookId != null) {
        final notes = await _dbBookNotes(book);
        if (!notes.isEmpty) {
          // הטקסט המאונדקס שונה משורות המסד, ולכן המנוע שומר אותו בעצמו.
          final stored = bytes;
          bytes = await Isolate.run(
            () => utf8.encode(
              rehydrateInlineNotesInText(utf8.decode(stored), notes),
            ),
          );
          libraryDbBookId = null;
        }
      }
      // ניקוי תמונות מוטמעות חייב לרוץ בשני הצדדים — אחרת חתימת האינדוקס
      // לעולם לא תתאים לאימות ו-reconcile יאנדקס את הספר מחדש בכל ריצה.
      if (bytes != null) {
        // כשהמקור מצויר, cleanDataUrisOffFrame מעביר אותו ל-isolate. מאפסים
        // את ההפניה המקומית לפני ה-await; במקרה הנקי היא מוחזרת בתוצאה.
        final rawBytes = bytes;
        bytes = null;
        final cleaned = await cleanDataUrisOffFrame(rawBytes);
        bytes = cleaned.bytes;
        text = cleaned.text;
        dataUriLines = cleaned.dataUriLines;
      }
    }
    if ((bytes == null || bytes.isEmpty) && (text == null || text.isEmpty)) {
      libraryDbBookId = null;
      userBooksDbBookId = null;
      attachedDbBookId = null;
      dataUriLines = null;
      text = await _loadTextForIndex(book);
    }
    return (
      bytes: bytes,
      text: text,
      libraryDbBookId: libraryDbBookId,
      userBooksDbBookId: userBooksDbBookId,
      attachedDbBookId: attachedDbBookId,
      dataUriLines: dataUriLines,
    );
  }

  /// הערות השוליים שהוצאו משורות הספר במסד — האינדקס מכיל אותן כמו בסכמה 6,
  /// כדי שמילה שמופיעה רק בהערה תימצא. בלי מטמון: האינדוקס עובר על כל הספרייה.
  static Future<BookNotes> _dbBookNotes(TextBook book) {
    if (!book.source.isOfficial) return Future.value(BookNotes.empty);
    return DatabaseLibraryProvider.instance.getBookNotes(
      book.title,
      categoryId: book.categoryId,
      source: book.source,
    );
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
    return stripDataUrisOffFrame(await book.text);
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
    source: book.source,
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

  /// commit לאינדקס ורישום הספרים שנחתמו בקנרית הקריסות.
  Future<SearchEngine> _commitIndex() async {
    final index = await _tantivyDataProvider.engine;
    await index.commit();
    IndexingCrashCanary.current?.committed(
      _tantivyDataProvider.indexedFilePaths,
    );
    return index;
  }

  /// עוטף את [callback] כך שיופעל רק בקריאה הראשונה — דיווח "האינדוקס
  /// בפועל התחיל" נשלח פעם אחת לריצה, גם כשכל ספר מדווח עליו.
  static void Function() _callOnce(void Function()? callback) {
    var called = false;
    return () {
      if (called) return;
      called = true;
      callback?.call();
    };
  }

  /// חותם התוכן של המסד לספר שנקרא מהמסד (רשמי או מצורף); null לכל השאר.
  static BigInt? _dbSourceHash(Book book, BookSourceHashes hashes) {
    final id = book.id;
    if (book is! TextBook || id == null) return null;
    if (book.filePath?.trim().isNotEmpty ?? false) return null;
    final key = BookIdentity.indexedFilePath(book);
    final fromDb = switch (book.source) {
      OfficialBookSource() => key == BookIdentity.officialBookKey(id),
      AttachedBookSource(:final slug) =>
        key == BookIdentity.attachedBookKey(slug, id),
      _ => false,
    };
    return fromDb ? hashes.forSource(book.source, id) : null;
  }

  /// סדר הקטלוג והדורות של כל ספר בר-אינדוקס בעץ [library], לפי מפתח האינדקס.
  /// [library] חייב להיות העץ המלא: ספר שחסר במיפוי ממוין בסוף התוצאות.
  static Future<List<BookOrderEntry>> buildBookOrder(Library library) async {
    final cached = _lastOrder;
    if (cached != null && identical(cached.library, library)) {
      return cached.entries;
    }
    await Future.wait([
      GenerationCache.instance.warmUp(),
      ReferenceBooksCache.instance.warmUp(),
    ]);
    final positions = SearchCatalogueOrderHelper.buildKeyOrderMap<String>(
      library,
      keyOf: (book) => BookIdentity.keyOf(book as Book),
    );
    final entries = <String, BookOrderEntry>{};
    for (final book in SearchCatalogueOrderHelper.buildOrderedKeys<Book>(
      library,
      keyOf: (book) => book as Book,
    )) {
      if (!isIndexableBook(book)) continue;
      final key = BookIdentity.indexedFilePath(book);
      entries[key] ??= BookOrderEntry(
        filePath: key,
        catalogueOrder: _catalogueOrderOf(BookIdentity.keyOf(book), positions),
        generationOrder: chronologicalOrderForBook(book),
      );
    }
    _bookOrderRanks = {
      for (final entry in entries.values) entry.filePath: entry.catalogueOrder,
    };
    final result = entries.values.toList();
    _lastOrder = (library: library, entries: result);
    return result;
  }

  // אותו עץ נבנה פעם אחת לטעינה: הדחיפה בטעינה וריצות האינדוקס שאחריה חולקות אותו.
  static ({Library library, List<BookOrderEntry> entries})? _lastOrder;

  /// נקרא בכל טעינת ספרייה בכל חלון; הסדר נבנה מחדש כשיידרש.
  static void invalidateBookOrder() {
    _lastOrder = null;
    _bookOrderRanks = null;
  }

  // ספרים אישיים ממוינים אחרי כל הספרייה והמסדים המצורפים, לפי id; הבסיס
  // מעל כל מקום אפשרי ברצף, והסכום חייב להיכנס ב-u32 של המיפוי.
  static const _personalOrderBase = 1 << 23;
  static const _maxCatalogueOrder = 0xFFFFFFFF;

  static int _catalogueOrderOf(String key, Map<String, int> positions) {
    final position = positions[key]!;
    if (!key.startsWith('uid:')) return position;
    final id = int.tryParse(key.substring(4));
    if (id == null || id < 0 || 'uid:$id' != key) return position;
    final order = _personalOrderBase + id;
    return order > _maxCatalogueOrder ? position : order;
  }

  static Map<String, int>? _bookOrderRanks;

  /// מיקום כל ספר במיפוי הסדר — כפי שהמנוע ממיין בסדר הקטלוג.
  static Future<Map<String, int>> bookOrderRanks() async {
    final cached = _bookOrderRanks;
    if (cached != null) return cached;
    try {
      await buildBookOrder(await DataRepository.instance.library);
    } catch (e) {
      debugPrint('⚠️ בניית סדר הספרים נכשלה: $e');
    }
    return _bookOrderRanks ?? const {};
  }

  /// מעדכן במנוע את מיפוי הסדר; מיון התוצאות משתנה בלי אינדוקס מחדש.
  Future<void> syncBookOrder(Library library) async {
    try {
      final entries = await buildBookOrder(library);
      final engine = await _tantivyDataProvider.engine;
      await engine.setBookOrder(entries: entries);
    } catch (e) {
      debugPrint('⚠️ עדכון סדר הספרים במנוע נכשל: $e');
    }
  }

  /// [TextStorage.libraryDb] רק לשורות ספר שמפתחו `id:`/`uid:`/`db:<slug>:` של
  /// אותו id, כשהמנוע קורא את המסד הזה; אחרת הטקסט נשמר באינדקס.
  @visibleForTesting
  static TextStorage textStorageFor({
    required String filePath,
    required int? libraryDbBookId,
    required int? userBooksDbBookId,
    int? attachedDbBookId,
    required bool hostApiReady,
    required bool userBooksConfigured,
    bool Function(String slug) attachedConfigured = _noAttachedSource,
  }) {
    if (!hostApiReady) return TextStorage.inIndex;
    if (libraryDbBookId != null &&
        filePath == BookIdentity.officialBookKey(libraryDbBookId)) {
      return TextStorage.libraryDb;
    }
    if (userBooksConfigured &&
        userBooksDbBookId != null &&
        filePath == BookIdentity.userBookKey(userBooksDbBookId)) {
      return TextStorage.libraryDb;
    }
    final slug = BookIdentity.attachedSlugOfKey(filePath);
    if (slug != null &&
        attachedDbBookId != null &&
        attachedConfigured(slug) &&
        filePath == BookIdentity.attachedBookKey(slug, attachedDbBookId)) {
      return TextStorage.libraryDb;
    }
    return TextStorage.inIndex;
  }

  static bool _noAttachedSource(String slug) => false;

  static bool _attachedEngineSourceConfigured(String slug) =>
      AttachedLibraryRegistry.instance.isEngineSourceConfigured(slug);

  /// האם תוכן הספר עדיין תואם את `textHash` שבאינדקס (בלי metadata — #828).
  /// בדיקה רכה: `true` כשאין חתימה או כשהספר אינו בר-אימות.
  Future<bool> textBookContentMatchesIndex(Book book, BigInt indexHash) async {
    if (indexHash == BigInt.zero) return true;
    final current = await currentTextFingerprint(book);
    return current == null || current == indexHash;
  }

  /// טביעת הטקסט הנוכחית של ספר טקסט, כפי שהאינדוקס היה חותם, או null כשאין
  /// לספר מקור. ספר שהתרוקן במסד מקבל את טביעת הטקסט הריק — לא "לא ידוע".
  Future<BigInt?> currentTextFingerprint(Book book) async {
    final textBook = _asTextBookForIndex(book);
    if (textBook == null) return null;
    final engineSource = _engineBookSource(book);
    if (engineSource != null) {
      try {
        final hash = await libraryFingerprint(
          source: engineSource,
          bookId: book.id!,
          attachedSlug: _attachedSlug(book),
          dbTitle: book.title,
        );
        if (hash != null) return hash;
      } catch (error) {
        debugPrint('⚠️ טביעת תוכן מהמנוע נכשלה ל-${book.title}: $error');
      }
    }
    final source = await loadTextBookSource(textBook);
    final text = source.text;
    final bytes =
        source.bytes ??
        (text == null || text.isEmpty ? null : utf8.encode(text));
    if (bytes != null && bytes.isNotEmpty) {
      return contentFingerprint(text: bytes);
    }
    // המנוע ומסלול הבייטים אינם מבחינים בין ספר ריק לספר חסר; המסד כן.
    if (textBook.categoryId == null) return null;
    final dbText = await SqliteDataProvider.instance.getBookTextFromDb(
      textBook.title,
      textBook.categoryId,
      textBook.fileType ?? 'txt',
      textBook.source,
      true,
    );
    return dbText == null ? null : contentFingerprint(text: const []);
  }

  /// שומר לריצה הבאה את מה שריצה שבוטלה לפני שהתחילה הייתה מחליפה ובודקת.
  Future<void> rememberChangedBooks(
    List<Book> books, {
    bool checkLibrary = false,
  }) async {
    if (books.isEmpty && !checkLibrary) return;
    await _tantivyDataProvider.engine;
    final store = PendingReindexStore.forIndex(
      _tantivyDataProvider.activeIndexPath,
    );
    if (store == null) return;
    await store.save({
      ...await store.load(),
      for (final book in books) BookIdentity.indexedFilePath(book),
    }, checkLibrary: checkLibrary ? true : null);
  }

  /// Cancels the ongoing indexing process.
  void cancelIndexing() {
    _tantivyDataProvider.isIndexing.value = false;
    // ביטול בזמן השהיה מעיר את הלולאה כדי שתפגוש את דגל הביטול.
    resumeIndexing();
  }

  /// Clears the index and resets the list of indexed books.
  Future<bool> clearIndex() async {
    final schemaCheck = SqliteDataProvider.instance.checkUnsupportedDbSchema();
    if (schemaCheck is bool ? schemaCheck : await schemaCheck) {
      return false;
    }
    await _tantivyDataProvider.clear();
    return true;
  }

  /// מסיר מהאינדקס את רשומות הספרים הנתונים — מחיקה מדויקת לפי מפתח
  /// ה-filePath שהמסמכים נכתבו איתו ([BookIdentity.indexedFilePath]), כך שספר
  /// אחר החולק את אותה כותרת אינו נפגע. מחזיר האם המחיקה נקלטה.
  Future<bool> dropBookIndexEntries(Iterable<Book> books) async {
    final keys = <String>{
      for (final book in books) BookIdentity.indexedFilePath(book),
    }..remove('');
    return _deleteIndexedFilePaths(keys);
  }

  Future<bool> dropHiddenIndexEntries(Library library) async {
    final hidden = hiddenStore.load();
    if (hidden.isEmpty) return true;
    await _tantivyDataProvider.engine;
    final categoryHiddenBooks = hidden.booksHiddenByCategory(library);
    return dropBookIndexEntries(
      library.getIndexableBooks().where(
        (book) =>
            hidden.excludesFromIndex(
              book,
              categoryHiddenBooks: categoryHiddenBooks,
            ) &&
            isBookIndexed(book),
      ),
    );
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

  /// מוחק את כל רשומות הספרים האישיים (`uid:`); false כשהמחיקה נכשלה.
  Future<bool> dropUserBookEntries() async {
    await _tantivyDataProvider.engine;
    return _deleteIndexedFilePaths({
      for (final key in _tantivyDataProvider.indexedFilePaths)
        if (key.startsWith('uid:')) key,
    });
  }

  /// מסיר מהאינדקס רשומות "יתומות" — ספרים שכבר אינם בספרייה (למשל ספר
  /// אישי שנמחק או תיקייה מותאמת שהוסרה). בלעדי זה מסמכי הספר ממשיכים
  /// לעלות בחיפוש ולהיפתח לספר שגוי.
  ///
  /// שמרני בכוונה: נוגע רק במפתחות ספרים אישיים (`uid:`), מסדים מצורפים
  /// (`db:`, ראה [_attachedOrphanRule]) ובמפתחות נתיב-מוחלט (PDF) שהקובץ
  /// מאחוריהם כבר לא קיים בדיסק. מפתחות ספרים
  /// רשמיים (`id:`) וחיצוניים (`ext:`) לא נמחקים כאן — טעינה חלקית של
  /// הספרייה הרשמית לא תגרור מחיקת אינדקס המונית ואינדוקס-מחדש של שעות.
  ///
  /// מחזיר את מספר הספרים שהוסרו.
  Future<int> dropOrphanedIndexEntries(
    Library library, {
    @visibleForTesting List<CustomFolder>? customFolders,
    @visibleForTesting Set<String>? preservedHiddenUserBookKeys,
    @visibleForTesting List<AttachedLibrary>? attachedLibraries,
    @visibleForTesting String? libraryRoot,
  }) async {
    final books = library.getIndexableBooks();
    if (books.isEmpty) return 0;

    // מוודא שה-indexedFilePaths כבר נטענו מהאינדקס (חלק מאתחול המנוע).
    await _tantivyDataProvider.engine;

    // "בלי ספרים אישיים": רשומות הספרים האישיים נמחקות כמו יתומים.
    final mode = indexUpdateMode();
    final libraryKeys = <String>{
      for (final book in books)
        if (mode.admits(book)) BookIdentity.indexedFilePath(book),
    };
    final excludedPersonalKeys = <String>{
      for (final book in books)
        if (!mode.admits(book)) BookIdentity.indexedFilePath(book),
    };

    // כונן חיצוני מנותק: השורש אינו קיים, ולכן הקבצים שתחתיו אינם יתומים
    // אלא בלתי-נגישים — מחיקתם הייתה מאנדקסת אותם מחדש בכל חיבור.
    final folders =
        customFolders ?? PersonalFoldersInfo.readConfiguredFolders();
    final unreachableRoots = <String>[];
    for (final folder in folders) {
      if (!await Directory(folder.path).exists()) {
        unreachableRoots.add(folder.path);
      }
    }

    // תיקייה מוסתרת אינה נכנסת לעץ, אבל הספרים שלה נשארים ב-user_books.db.
    // מפתחות `uid:` של ספר קיים מאותה תיקייה נשמרים; מפתח של ספר שנמחק
    // באמת אינו מופיע במסד ולכן ממשיך להימחק כיתום.
    final hiddenUserBookKeys = !mode.indexesPersonalBooks
        ? const <String>{}
        : preservedHiddenUserBookKeys ??
              await _hiddenUserBookIndexKeys(folders);

    final attached = attachedLibraries ?? _registeredAttachedLibraries();
    final isAttachedOrphan = _attachedOrphanRule(books, attached);

    // ספרי תיקייה מוסתרת אינם בעץ ומזוהים לפי שורשה; ספרייה או מסד מצורף
    // שבתוכה אינם אישיים. null — לא ידוע מה מוגן, ולא מוחקים.
    final hiddenFolderNames = CustomFoldersManager.hiddenFolderNames(folders);
    final hiddenPersonalRoots = [
      for (final folder in folders)
        if (hiddenFolderNames.contains(folder.name) &&
            !unreachableRoots.contains(folder.path))
          folder.path,
    ];
    final protectedRoots =
        mode.indexesPersonalBooks || hiddenPersonalRoots.isEmpty
        ? null
        : await _nonPersonalRoots(libraryRoot, attached);

    final orphans = <String>{};
    // snapshot — הלולאה מכילה await ואסור שהסט החי ישתנה תחתיה.
    for (final key in _tantivyDataProvider.indexedFilePaths.toList()) {
      if (libraryKeys.contains(key)) continue;
      if (excludedPersonalKeys.contains(key)) {
        orphans.add(key);
      } else if (key.startsWith('uid:')) {
        // null = כשל בקריאת user_books.db: נשארים שמרניים ולא מוחקים ספרי
        // תיקייה מוסתרת שעלולים לחזור לעץ בלי אינדוקס מחדש.
        if (hiddenUserBookKeys == null || !hiddenUserBookKeys.contains(key)) {
          orphans.add(key);
        }
      } else if (key.startsWith('db:')) {
        if (isAttachedOrphan(key)) orphans.add(key);
      } else if (p.isAbsolute(key) &&
          protectedRoots != null &&
          hiddenPersonalRoots.any((root) => p.isWithin(root, key)) &&
          !protectedRoots.any(
            (root) => p.equals(root, key) || p.isWithin(root, key),
          )) {
        orphans.add(key);
      } else if (p.isAbsolute(key) &&
          !unreachableRoots.any((root) => p.isWithin(root, key)) &&
          !await File(key).exists()) {
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

  static Future<List<String>?> _nonPersonalRoots(
    String? libraryRoot,
    List<AttachedLibrary>? attached,
  ) async {
    if (attached == null) return null;
    String? root = libraryRoot;
    if (root == null) {
      try {
        root = await AppPaths.getLibraryPath();
      } catch (error) {
        debugPrint('⚠️ לא ניתן לקרוא את נתיב הספרייה: $error');
        return null;
      }
    }
    return [root, for (final library in attached) p.dirname(library.path)];
  }

  /// null — הרשימה לא נקראה, ואז אף מפתח `db:` אינו נמחק.
  static List<AttachedLibrary>? _registeredAttachedLibraries() {
    try {
      return AttachedLibraryRegistry.instance.librariesIfKnown;
    } catch (error) {
      debugPrint('⚠️ לא ניתן לקרוא את רשימת המסדים המצורפים: $error');
      return null;
    }
  }

  /// מפתח `db:` יתום רק כשהמסד הוסר מהרשימה, או כשהמסד זמין ונטען לעץ
  /// והספר כבר אינו בו. מסד לא-זמין או מוסתר שומר את האינדקס שלו (#1295).
  static bool Function(String key) _attachedOrphanRule(
    List<Book> books,
    List<AttachedLibrary>? libraries,
  ) {
    if (libraries == null) return (_) => false;
    final registered = {for (final library in libraries) library.slug};
    final loaded = {
      for (final book in books)
        if (book.source case AttachedBookSource(:final slug)) slug,
    };
    final visible = {
      for (final library in libraries)
        if (library.isVisibleInLibrary) library.slug,
    };
    return (key) {
      final slug = BookIdentity.attachedSlugOfKey(key);
      if (slug == null) return false;
      if (!registered.contains(slug)) return true;
      return visible.contains(slug) && loaded.contains(slug);
    };
  }

  /// מפתחות האינדקס של ספרים שקיימים רק בתיקיות שמוסתרות מהעץ.
  ///
  /// ל-`uid:` אין נתיב, ולכן הקריאה נשענת על `source` של user_books.db
  /// במקום לדלג על כל המפתחות ברגע שקיימת תיקייה מוסתרת אחת.
  Future<Set<String>?> _hiddenUserBookIndexKeys(
    List<CustomFolder> folders,
  ) async {
    final hiddenFolderNames = CustomFoldersManager.hiddenFolderNames(folders);
    if (hiddenFolderNames.isEmpty) return const {};

    final hiddenFolders = folders
        .where((folder) => hiddenFolderNames.contains(folder.name))
        .toList(growable: false);
    final hiddenSources = {
      for (final folder in hiddenFolders)
        CustomFolderSource.nameForFolder(folder.path),
    };

    try {
      final repository = await UserBooksDatabaseHolder.instance.repository;
      final books = await repository.getAllBooksLean();
      final sourceNames = <int, String?>{};
      for (final sourceId in books.map((book) => book.sourceId).toSet()) {
        sourceNames[sourceId] = (await repository.getSourceById(
          sourceId,
        ))?.name;
      }

      return {
        for (final book in books)
          if (_isHiddenFolderBook(
            sourceName: sourceNames[book.sourceId],
            filePath: book.filePath,
            hiddenSources: hiddenSources,
            hiddenFolders: hiddenFolders,
          ))
            BookIdentity.userBookKey(book.id),
      };
    } catch (error) {
      debugPrint('⚠️ לא ניתן לזהות ספרי תיקיות מוסתרות באינדקס: $error');
      return null;
    }
  }

  static bool _isHiddenFolderBook({
    required String? sourceName,
    required String? filePath,
    required Set<String> hiddenSources,
    required List<CustomFolder> hiddenFolders,
  }) {
    if (sourceName != CustomFolderSource.legacyExternalSourceName) {
      return hiddenSources.contains(sourceName);
    }
    if (filePath == null || filePath.isEmpty) return false;
    return hiddenFolders.any(
      (folder) =>
          p.equals(folder.path, filePath) || p.isWithin(folder.path, filePath),
    );
  }

  /// מסיר מהאינדקס רשומות של ספרי-קובץ שנתיבם השתנה בהעברת הספרייה.
  ///
  /// רשומות אלו מאונדקסות לפי נתיב מוחלט (PDF, וספרי קובץ ללא id יציב),
  /// ולכן אחרי העברה הן מצביעות לנתיב הישן. בלי הסרתן, האינדוקס האוטומטי
  /// שלאחר הרענון מוסיף את אותם ספרים בנתיב החדש ⇒ כפילויות ותוצאות שבורות.
  Future<bool> dropRelocatedFileBookEntries(
    Iterable<Book> relocatedBooks,
  ) async => dropBookIndexEntries(relocatedBooks);

  /// Returns true for book types that the indexer actually processes.
  /// Non-indexable types (ExternalLibraryBook וכו') מדולגים בשקט
  /// ב-indexAllBooks, ולכן חייבים להיות מחוץ לבדיקות הסטטוס.
  /// ספרי מסמך נכללים — הם ממופים ל-TextBook ב-indexAllBooks דרך
  /// `toTextBook()`, ו-`book.text` כבר יודע לחלץ את התוכן דרך הממיר
  /// המתאים (ראה DatabaseLibraryProvider.getBookText).
  static bool isIndexableBook(Book book) =>
      book is TextBook ||
      (book is PdfBook && !isBundledTalmudBavliPdf(book)) ||
      book is ConvertibleDocumentBook;

  /// מסכת PDF מצורפת אינה מאונדקסת: הטקסט המלא שלה כבר באינדקס, ותוצאת
  /// טקסט נפתחת ב-PDF לפי הגדרת פורמט הפתיחה — האינדוקס רק הכפיל תוצאות.
  static bool isBundledTalmudBavliPdf(PdfBook book) =>
      book.source.isOfficial &&
      DatabaseConstants.isTalmudBavliPdfExternalLibraryId(
        book.externalLibraryId,
      );

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

class _LibraryBatchCleanupFailure implements Exception {
  const _LibraryBatchCleanupFailure(this.cause);
  final Object cause;

  @override
  String toString() => cause.toString();
}

/// מצב אצוות הספרייה לאורך ריצת אינדוקס אחת.
class _LibraryBatches {
  final sizer = LibraryBatchSizer();

  /// נוספו באצווה ונרשמו במעקב; הלולאה ספר-ספר רק סופרת אותם.
  final handled = <Book>{};

  /// המנוע לא הוסיף אותם (חסר/לא זמין/כשל) — למסלול הרגיל.
  final attempted = <Book>{};

  /// כשל writer באצווה: שאר הריצה במסלול הרגיל.
  bool disabled = false;
}

/// בדיקה במעבר אחד על חותמות המנוע: metadata לכל ספר בלי לקרוא טקסט, ותוכן
/// לפי חותם המסד — ובהיעדרו לפי טביעת הטקסט. PDF וספר אישי: רק metadata.
class StampChangeDetector implements IndexChangeDetector {
  StampChangeDetector(
    this._repository, {
    @visibleForTesting this._loadSourceHashes,
    @visibleForTesting this._textMatchesIndex,
    @visibleForTesting
    this._metadataFingerprint = computeBookMetadataFingerprint,
  });

  final IndexingRepository _repository;
  final Future<BookSourceHashes> Function(List<Book> books)? _loadSourceHashes;
  final Future<bool> Function(Book book, BigInt textHash)? _textMatchesIndex;
  final BigInt Function({
    required String title,
    required String topics,
    List<String>? extraFacets,
  })
  _metadataFingerprint;

  @override
  Future<List<Book>?> detectChanged(
    List<Book> candidates, {
    required Library library,
    required bool Function() isCancelled,
    required Future<void> Function() waitWhilePaused,
    void Function(int processed, int total)? onProgress,
  }) async {
    final engine = await _repository._tantivyDataProvider.engine;
    final stamps = {
      for (final stamp in await engine.getBookStamps()) stamp.filePath: stamp,
    };
    final indexed = [
      for (final book in candidates)
        if (stamps.containsKey(
          BookIdentity.indexedFilePath(book),
        ))
          book,
    ];
    if (indexed.isEmpty) return const [];
    await Future.wait([
      GenerationCache.instance.warmUp(),
      ReferenceBooksCache.instance.warmUp(),
      BookFacetMetadataCache.instance.warmUp(),
    ]);
    final sourceHashes =
        await (_loadSourceHashes?.call(indexed) ??
            IndexingRepository.loadSourceHashes(
              attachedSlugs: [
                for (final book in indexed)
                  ?IndexingRepository._attachedSlug(book),
              ],
            ));

    final total = indexed.length;
    onProgress?.call(0, total);
    final changed = <Book>[];
    final stopwatch = Stopwatch()..start();
    var textReads = 0;
    for (final (index, book) in indexed.indexed) {
      await waitWhilePaused();
      if (isCancelled()) return null;
      final stamp = stamps[BookIdentity.indexedFilePath(book)]!;
      final metadata = _metadataFingerprint(
        title: book.title,
        topics: _repository._bookTopics(book),
        extraFacets: _repository._bookExtraFacets(book),
      );
      if (stamp.metadataHash == BigInt.zero || stamp.metadataHash != metadata) {
        changed.add(book);
      } else {
        final sourceHash = IndexingRepository._dbSourceHash(book, sourceHashes);
        if (sourceHash != null && stamp.sourceHash != BigInt.zero) {
          if (sourceHash != stamp.sourceHash) changed.add(book);
        } else if (_needsTextCheck(book)) {
          textReads++;
          // textHash אפס = "לא ניתן לאימות" — מאנדקסים כדי לרכוש חותם תקין.
          if (stamp.textHash == BigInt.zero ||
              !await _textMatches(book, stamp.textHash)) {
            changed.add(book);
          }
          if (isCancelled()) return null;
        }
      }
      onProgress?.call(index + 1, total);
      if (index % 50 == 49) await Future<void>.delayed(Duration.zero);
    }
    debugPrint(
      '🔎 בדיקה: $total ספרים, $textReads בטביעת טקסט, '
      '${changed.length} השתנו, ב-${stopwatch.elapsed}',
    );
    return isCancelled() ? null : changed;
  }

  // ספר פגום אחד אינו מבטל את הבדיקה — הוא רק אינו בר-השוואה.
  Future<bool> _textMatches(Book book, BigInt textHash) async {
    try {
      final injected = _textMatchesIndex;
      if (injected != null) return await injected(book, textHash);
      return await _repository.textBookContentMatchesIndex(book, textHash);
    } on DocumentConversionException catch (e) {
      debugPrint('🔎 בדיקה: דילוג על "${book.title}" — $e');
      return true;
    }
  }

  /// שינוי בספר אישי או בקובץ מדווח במדויק בסריקת התיקיות.
  static bool _needsTextCheck(Book book) =>
      book is! PdfBook &&
      !book.source.isUser &&
      (book is TextBook || book is ConvertibleDocumentBook);
}

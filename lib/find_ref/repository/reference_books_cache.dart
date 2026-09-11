import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/book_database_resolver.dart';
import 'package:otzaria/data/data_providers/cache_database_holder.dart';
import 'package:otzaria/data/repository/data_repository.dart'
    show bookSearchWordMatchesFuzzy, bookSearchWordPairMatches;
import 'package:otzaria/data/data_providers/file_system_library_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/category.dart' as db_models;
import 'package:otzaria/migration/models/pdf_outline_cache_entry.dart';
import 'package:otzaria/pdf_book/utils/pdf_viewer_activity.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:pdfrx/pdfrx.dart';

/// In-memory cache for reference finding.
///
/// Uses shared caches:
/// - BooksCache: shared with library screen (book table)
/// - AcronymsCache: exclusive to FindRef (book_acronym table)
///
/// This avoids loading the same data twice into memory.
/// Scope: only the "book selection" phase. TOC lookup is handled elsewhere.
class ReferenceBooksCache {
  ReferenceBooksCache._();

  static final ReferenceBooksCache instance = ReferenceBooksCache._();
  static const Duration _persistentPdfOutlineCacheTtl = Duration(days: 90);

  bool _isLoaded = false;
  Future<void>? _loadingFuture;

  /// מונה דורות לזיהוי [clear] שקרה במהלך טעינה.
  int _generation = 0;

  // Normalized titles cache (computed from BooksCache)
  final Map<int, String> _normalizedTitles = <int, String>{};

  /// כל המילים השונות שבכותרות ובכינויים, ומזהי הספרים לכל מילה. הספרייה
  /// כולה מכילה ~6,900 מילים שונות בלבד, ולכן ההתאמה המקורבת רצה עליהן פעם
  /// אחת לכל מילת שאילתה במקום על ~190,000 המילים שבספרים.
  final List<String> _fuzzyVocabulary = <String>[];
  final List<Uint32List> _fuzzyVocabularyBooks = <Uint32List>[];

  /// מטמון חסום של המסננת לפי מילת שאילתה: `findRefs` קורא ל-[search] עד
  /// ארבע פעמים על אותה שאילתה, וההקלדה הבאה חוזרת על כל המילים חוץ מהאחרונה.
  final Map<String, Set<int>> _fuzzyWordCandidates = <String, Set<int>>{};
  static const int _fuzzyWordCandidatesLimit = 128;

  // PDF books from file system (not in DB) — stored as (normalizedTitle, hit)
  final List<(String, ReferenceBookHit)> _fsPdfBooks =
      <(String, ReferenceBookHit)>[];

  // Lazy PDF outline cache: filePath → Future of outline entries
  // Populated on demand (and optionally pre-warmed in background after warmUp).
  final Map<String, Future<List<(String, String, int)>>> _pdfOutlineCache =
      <String, Future<List<(String, String, int)>>>{};

  /// פונקציית הפענוח של outline מ-PDF. ניתן להחליפה בבדיקות כדי להחליף את
  /// ה-I/O הממשי בפעולה דטרמיניסטית, בלי להוציא את התלות ב-pdfrx לחוץ.
  @visibleForTesting
  Future<List<(String, String, int)>> Function(String filePath)
  pdfOutlineParser = _parsePdfOutlineEntries;

  /// Injection לבדיקות בלבד: repository ייעודי ל-persistent cache של
  /// outlines. אם לא סופק — נשתמש ב-[SqliteDataProvider.instance.repository].
  @visibleForTesting
  SeforimRepository? pdfOutlineCacheRepositoryOverride;

  /// Injection לבדיקות בלבד: קריאת metadata של הקובץ (size + mtime).
  /// מחזיר `null` אם הקובץ לא זמין ולכן אין טעם לגשת ל-persistent cache.
  @visibleForTesting
  Future<({int fileSize, int lastModified})?> Function(String filePath)?
  pdfFileMetadataProviderOverride;

  /// Injection לבדיקות בלבד: שעון מילישניות.
  @visibleForTesting
  int Function()? nowProviderOverride;

  /// Injection לבדיקות בלבד: ספק הקטגוריות עבור [_prewarmCategoryPaths]. אם
  /// `null` (ברירת מחדל) — `_prewarmCategoryPaths` ניגש ל-[SqliteDataProvider].
  /// טסטים יכולים להציב פונקציה זורקת חריגה לבדיקת מסלול הכשל, או רשימה
  /// קונקרטית לבדיקת הצלחה.
  @visibleForTesting
  Future<List<db_models.Category>> Function()? categoriesProviderOverride;

  bool get isLoaded => _isLoaded;

  Future<void> warmUp() async {
    if (_isLoaded) return;
    if (_loadingFuture != null) return _loadingFuture;

    _loadingFuture = _loadInternal();

    try {
      await _loadingFuture;
    } finally {
      _loadingFuture = null;
    }
  }

  Future<void> _loadInternal() async {
    final myGen = _generation;
    try {
      // Warm up shared caches
      await BooksCache.instance.warmUp();
      if (myGen != _generation) return;
      // רשימה ריקה תקינה; רק טעינה שלא הושלמה מעידה שאין עדיין במה לחפש.
      if (!BooksCache.instance.isLoaded) {
        debugPrint(
          '[ReferenceBooksCache] aborting warmUp — BooksCache not loaded; '
          'next warmUp() will retry',
        );
        return;
      }
      await AcronymsCache.instance.warmUp();
      if (myGen != _generation) return;

      // Pre-compute normalized titles for fast matching.
      // בונים למפה מקומית — ה-cache החי לא נוגע עד ה-swap בסוף.
      // יציאה ל-event loop כל chunk כדי לא לחסום את ה-UI thread על
      // ספריות גדולות (~50K ספרים × regex לנורמליזציה).
      final localNormalizedTitles = <int, String>{};
      const yieldBatch = 1000;
      var processed = 0;
      for (final book in BooksCache.instance.books) {
        localNormalizedTitles[book.id] = _normalizeForMatch(book.title);
        if (++processed % yieldBatch == 0) {
          await Future<void>.delayed(Duration.zero);
          if (myGen != _generation) return;
        }
      }

      // Collect DB PDF titles to avoid duplicates with file-system PDFs
      final dbPdfTitles = BooksCache.instance.books
          .where((b) => b.fileType == 'pdf')
          .map((b) => b.title)
          .toSet();

      // מפה מכותרת → orderIndex הנמוך ביותר מקרב כל ספרי ה-DB (כולל טקסט).
      // FS PDF בעל אותה כותרת כספר DB יירש את ה-orderIndex שלו, כדי שלא
      // ידחק לסוף הרשימה (999.0 קבוע).
      final titleToDbOrderIndex = <String, double>{};
      for (final book in BooksCache.instance.books) {
        final existing = titleToDbOrderIndex[book.title];
        if (existing == null || book.orderIndex < existing) {
          titleToDbOrderIndex[book.title] = book.orderIndex;
        }
      }

      // Load PDF books from file system that are not in the DB.
      // PDF outline parsing is NOT done here — it happens lazily via getPdfOutlineEntries().
      final localFsPdfBooks = <(String, ReferenceBookHit)>[];
      if (FileSystemLibraryProvider.instance.isInitialized) {
        final keyToPath = await FileSystemLibraryProvider.instance.keyToPath;
        if (myGen != _generation) return;
        var processedPdfs = 0;
        for (final entry in keyToPath.entries) {
          final key = BookCompositeKey.tryParse(entry.key);
          if (key == null || key.fileType != 'pdf') continue;
          if (dbPdfTitles.contains(key.title)) continue;

          final normalizedTitle = _normalizeForMatch(key.title);
          if (normalizedTitle.isEmpty) continue;

          // FS PDF inherits the DB book's orderIndex when one exists with the same title,
          // preventing it from being pushed behind all text books (default 999.0).
          final orderIdx = titleToDbOrderIndex[key.title] ?? 999.0;

          localFsPdfBooks.add((
            normalizedTitle,
            ReferenceBookHit(
              bookId: -1,
              title: key.title,
              normalizedTitle: normalizedTitle,
              filePath: entry.value,
              fileType: 'pdf',
              matchRank: 0,
              orderIndex: orderIdx,
            ),
          ));
          if (++processedPdfs % yieldBatch == 0) {
            await Future<void>.delayed(Duration.zero);
            if (myGen != _generation) return;
          }
        }
      }

      // Swap אטומי — רק אם הדור עדיין שלנו.
      if (myGen != _generation) return;

      _normalizedTitles
        ..clear()
        ..addAll(localNormalizedTitles);
      _fsPdfBooks
        ..clear()
        ..addAll(localFsPdfBooks);
      _categoryPaths.clear();

      if (!await _prewarmFuzzyVocabulary(localNormalizedTitles, myGen)) return;
      if (myGen != _generation) return;

      // Pre-warm category paths **לפני** סימון הקאש כ-loaded — דירוג ה-FindRef
      // מסתמך על resolver סינכרוני שיחזיר null אם הקאש עוד לא מוכן, ואז
      // כל הסיווג "ספר יסוד" מבוטל בחיפוש הראשון. שאילתה אחת + walk בזיכרון
      // היא חבילה זולה (~hundreds of ms על ספרייה של ~10K ספרים), שווה
      // לחסום את ה-warmUp עליה. PDF outline pre-warm נשאר בריקה כי הוא
      // יקר משמעותית (file I/O).
      //
      // אם prewarm נכשל (לדוגמה, lock זמני על ה-DB) — נחזור בלי לסמן
      // `_isLoaded = true`, כך שה-warmUp הבא יזכה לנסות שוב במקום להישאר
      // עם classifier מבוטל לכל ה-session.
      final pathsOk = await _prewarmCategoryPaths(myGen);
      if (myGen != _generation) return;
      if (!pathsOk) {
        debugPrint(
          '[ReferenceBooksCache] aborting warmUp — category-path prewarm failed; '
          'next warmUp() will retry',
        );
        return;
      }

      _isLoaded = true;
      debugPrint(
        '[ReferenceBooksCache] Ready with ${BooksCache.instance.books.length} DB books'
        ' + ${_fsPdfBooks.length} FS PDF books',
      );

      final knownFsPdfPaths = FileSystemLibraryProvider.instance.isInitialized
          ? localFsPdfBooks
                .map((entry) => entry.$2.filePath)
                .where((path) => path.isNotEmpty)
                .toSet()
          : null;

      unawaited(
        _prunePersistentPdfOutlineCache(
          generation: myGen,
          knownFilePaths: knownFsPdfPaths,
        ).catchError((Object e) {
          debugPrint('[ReferenceBooksCache] PDF outline prune failed: $e');
        }),
      );

      // Pre-warm PDF outlines in the background — typically 20-40 FS PDFs,
      // each requiring a file open + outline parse on first FindRef hit.
      // Running here (post-swap) keeps `warmUp()`'s returned Future fast,
      // while the throttled parse fills the cache before the user types.
      unawaited(
        prewarmAllPdfOutlines().catchError((Object e) {
          debugPrint('[ReferenceBooksCache] PDF outline pre-warm failed: $e');
        }),
      );
    } catch (e) {
      debugPrint('[ReferenceBooksCache] Warmup failed: $e');
      // לא מסמנים loaded: כשל זמני (למשל DB נעול ביציאה ממצב שינה) יאופשר
      // retry ב-warmUp הבא, במקום קאש ריק שמחזיר "לא נמצא ספר" לכל ה-session.
      if (myGen == _generation) {
        _normalizedTitles.clear();
        _fuzzyVocabulary.clear();
        _fuzzyVocabularyBooks.clear();
        _fuzzyWordCandidates.clear();
        _fsPdfBooks.clear();
        _categoryPaths.clear();
        _isLoaded = false;
      }
    }
  }

  void clear() {
    _generation++;
    _normalizedTitles.clear();
    _fuzzyVocabulary.clear();
    _fuzzyVocabularyBooks.clear();
    _fuzzyWordCandidates.clear();
    _fsPdfBooks.clear();
    _pdfOutlineCache.clear();
    _categoryPaths.clear();
    _isLoaded = false;
    _loadingFuture = null;
    // Note: We don't clear the shared caches here as they may be used by other components
  }

  // Category-path cache: bookId → category path string of the book's category
  // chain, **excluding** the book itself. e.g. for book "בראשית" (categoryId
  // points to "תורה"), the path is "תנ"ך, תורה" — אורך 2. עבור "משנה תורה,
  // הלכות שבת" (categoryId="ספר זמנים"), הנתיב הוא
  // "הלכה, משנה תורה, ספר זמנים" — אורך 3.
  //
  // הקאש נטען ב-[_prewarmCategoryPaths] לפני שהקאש מסומן כ-loaded (single
  // SQL + O(books) in-memory walk), כדי שדירוג ה-FindRef יוכל לסווג "ספר
  // יסוד" מול "מפרש" סינכרונית בלי race עם ה-warmUp.
  final Map<int, String> _categoryPaths = <int, String>{};

  /// גרסה סינכרונית של [getCategoryPathForBook]: מחזירה `null` אם הערך
  /// אינו בקאש (למשל לפני warmUp או עבור ספרים שאינם ב-DB).
  String? getCategoryPathForBookSync(int bookId) {
    if (bookId < 0) return null;
    return _categoryPaths[bookId];
  }

  /// מחזיר את נתיב הקטגוריה עבור ספר לפי מזההו.
  /// הנתיב נבנה בפעם הראשונה בלבד ונשמר בזיכרון.
  Future<String> getCategoryPathForBook(int bookId) async {
    if (bookId < 0) return '';
    if (_categoryPaths.containsKey(bookId)) return _categoryPaths[bookId]!;

    final book = BooksCache.instance.getBookById(bookId);
    if (book == null) {
      _categoryPaths[bookId] = '';
      return '';
    }

    final repository = SqliteDataProvider.instance.repository;
    if (repository == null) {
      _categoryPaths[bookId] = '';
      return '';
    }

    try {
      final path = await BookDatabaseResolver.buildCategoryPath(
        repository,
        book.categoryId,
      );
      _categoryPaths[bookId] = path;
      return path;
    } catch (e) {
      debugPrint('[ReferenceBooksCache] getCategoryPathForBook error: $e');
      _categoryPaths[bookId] = '';
      return '';
    }
  }

  /// בונה ב-pass יחיד את כל ה-categoryPaths מ-`book.categoryId` לעלה.
  /// מיועד לקריאה בתוך ה-warmUp **לפני** סימון הקאש כ-loaded.
  ///
  /// ערכי החזרה:
  ///   `true`  — הצלחה (כולל המקרה של "אין DB"), הקאש מוכן לשימוש.
  ///   `false` — כשל בפועל (חריגה בקריאה לשאילתת DB וכד'). הקורא חייב
  ///             *לא* לסמן את הקאש כ-loaded, כך שה-warmUp הבא ינסה שוב.
  ///   ביטול (myGen != _generation) — `true`. הקורא יבדוק את הדור בעצמו
  ///   ויחזור בלי לסמן loaded; זה לא כשל לוגי אלא בקשת הפסקה.
  Future<bool> _prewarmCategoryPaths(int myGen) async {
    final override = categoriesProviderOverride;
    final repository = SqliteDataProvider.instance.repository;
    if (override == null && repository == null) {
      return true; // אין DB — אין מה לחמם, לא נחשב כשל.
    }

    try {
      final categories = override != null
          ? await override()
          : await repository!.getAllCategories();
      if (myGen != _generation) return true; // ביטול, לא כשל.

      final byId = <int, ({int? parentId, String title})>{
        for (final c in categories)
          c.id: (parentId: c.parentId, title: c.title),
      };

      // Memoization של נתיב לפי categoryId — כל נתיב מחושב פעם אחת.
      final pathByCategoryId = <int, String>{};
      String pathFor(int? categoryId) {
        if (categoryId == null) return '';
        final cached = pathByCategoryId[categoryId];
        if (cached != null) return cached;

        final visited = <int>{};
        final parts = <String>[];
        int? cur = categoryId;
        while (cur != null && visited.add(cur)) {
          final entry = byId[cur];
          if (entry == null) break;
          parts.insert(0, entry.title);
          cur = entry.parentId;
        }
        final path = parts.join(', ');
        pathByCategoryId[categoryId] = path;
        return path;
      }

      const yieldBatch = 1000;
      var processed = 0;
      for (final book in BooksCache.instance.books) {
        _categoryPaths[book.id] = pathFor(book.categoryId);
        if (++processed % yieldBatch == 0) {
          await Future<void>.delayed(Duration.zero);
          if (myGen != _generation) return true; // ביטול.
        }
      }
      return true;
    } catch (e) {
      debugPrint('[ReferenceBooksCache] _prewarmCategoryPaths failed: $e');
      return false;
    }
  }

  /// Returns outline entries for a file-system PDF, parsed lazily and cached.
  /// Each entry is (normalizedTitle, originalTitle, pageNumber).
  Future<List<(String, String, int)>> getPdfOutlineEntries(
    String filePath,
  ) async {
    return _pdfOutlineCache.putIfAbsent(filePath, () async {
      if (filePath.isEmpty) return const [];

      final fileMetadata = await _readPdfFileMetadata(filePath);
      if (fileMetadata.isMissing) {
        await _deletePersistentPdfOutline(filePath);
        return const [];
      }

      final persistentEntry = await _loadPersistentPdfOutline(filePath);
      if (fileMetadata.metadata == null) {
        if (persistentEntry != null) {
          try {
            final entries = persistentEntry.decodeEntries();
            unawaited(
              _touchPersistentPdfOutline(filePath).catchError((e) {
                debugPrint(
                  '[ReferenceBooksCache] Failed to touch PDF outline cache '
                  'for $filePath: $e',
                );
              }),
            );
            return entries;
          } catch (e) {
            debugPrint(
              '[ReferenceBooksCache] Failed to decode cached outline for '
              '$filePath after metadata read failure: $e',
            );
          }
        }

        return pdfOutlineParser(filePath);
      }

      final metadata = fileMetadata.metadata!;
      if (persistentEntry != null) {
        final matchesCurrentFile =
            persistentEntry.fileSize == metadata.fileSize &&
            persistentEntry.lastModified == metadata.lastModified;
        if (matchesCurrentFile) {
          try {
            final entries = persistentEntry.decodeEntries();
            unawaited(
              _touchPersistentPdfOutline(filePath).catchError((e) {
                debugPrint(
                  '[ReferenceBooksCache] Failed to touch PDF outline cache '
                  'for $filePath: $e',
                );
              }),
            );
            return entries;
          } catch (e) {
            debugPrint(
              '[ReferenceBooksCache] Failed to decode cached outline for '
              '$filePath: $e',
            );
            await _deletePersistentPdfOutline(filePath);
          }
        } else {
          await _deletePersistentPdfOutline(filePath);
        }
      }

      final entries = await pdfOutlineParser(filePath);
      if (entries.isNotEmpty) {
        await _savePersistentPdfOutline(
          PdfOutlineCacheEntry(
            filePath: filePath,
            fileSize: metadata.fileSize,
            lastModified: metadata.lastModified,
            outlineJson: PdfOutlineCacheEntry.encodeOutlineEntries(entries),
            createdAt: _nowMillis(),
            accessedAt: _nowMillis(),
          ),
        );
      }
      return entries;
    });
  }

  /// Pre-warms the PDF outline cache for all currently-known FS PDF books.
  ///
  /// Runs in bounded batches of [maxConcurrent] files at a time. pdfrx
  /// serializes all PDFium work through a single worker isolate, so a larger
  /// batch only holds more documents in memory and lengthens that queue —
  /// hence the default of 1.
  ///
  /// Idempotent and cheap to re-run: entries already cached are skipped
  /// automatically by [getPdfOutlineEntries]'s `putIfAbsent`.
  ///
  /// Respects [clear] via the generation counter — if the cache is cleared
  /// mid-run, the remaining batches are aborted.
  /// בחלון משני PDFium שייך ל-isolate אחר, לכן אין הקדמה.
  Future<void> prewarmAllPdfOutlines({int maxConcurrent = 1}) async {
    // ולידציה רצה גם ב-release: ערך לא חיובי יוצר לולאה אינסופית
    // (i += 0), עדיף להיכשל בקול מאשר להקפיא את ה-isolate.
    if (maxConcurrent <= 0) {
      throw ArgumentError.value(maxConcurrent, 'maxConcurrent', 'must be > 0');
    }
    if (WindowRole.isSecondary) return;
    final gen = _generation;
    final paths = _fsPdfBooks
        .map((entry) => entry.$2.filePath)
        .where((p) => p.isNotEmpty)
        .toList(growable: false);
    if (paths.isEmpty) return;

    for (var i = 0; i < paths.length; i += maxConcurrent) {
      // הקורא קודם — טאב שממתין לעמוד היעד לא יחכה בתור מאחורי ה-outline.
      await PdfViewerActivity.instance.waitUntilIdle();
      if (gen != _generation) return;
      final end = (i + maxConcurrent < paths.length)
          ? i + maxConcurrent
          : paths.length;
      await Future.wait([
        for (var j = i; j < end; j++) getPdfOutlineEntries(paths[j]),
      ]);
    }
    debugPrint(
      '[ReferenceBooksCache] PDF outline pre-warm complete '
      '(${paths.length} files)',
    );
  }

  /// בדיקות בלבד — מאפשר למלא את רשימת ה-FS PDFs בלי לעבור דרך
  /// [FileSystemLibraryProvider].
  @visibleForTesting
  void setFsPdfBooksForTesting(List<(String, ReferenceBookHit)> books) {
    _fsPdfBooks
      ..clear()
      ..addAll(books);
  }

  /// בדיקות בלבד — מזריק את הכותרות המנורמלות ונתיבי הקטגוריה ישירות, כדי
  /// לבדוק את [searchByEraAndTopic] בלי warmUp מלא מול DB.
  @visibleForTesting
  void seedForTesting({
    required Map<int, String> normalizedTitles,
    required Map<int, String> categoryPaths,
  }) {
    _normalizedTitles
      ..clear()
      ..addAll(normalizedTitles);
    _categoryPaths
      ..clear()
      ..addAll(categoryPaths);
    final booksByWord = <String, List<int>>{};
    _collectFuzzyWords(booksByWord, normalizedTitles.entries);
    _installFuzzyVocabulary(booksByWord);
    _isLoaded = true;
  }

  /// בדיקות בלבד — חושף את מצב מטמון ה-outline (filePath → Future של ערכי
  /// outline) כדי לבדוק אילו קבצים נטענו.
  @visibleForTesting
  Map<String, Future<List<(String, String, int)>>>
  get pdfOutlineCacheForTesting => _pdfOutlineCache;

  /// Searches books by title and acronym from memory.
  ///
  /// Input must already be normalized similarly to [_normalizeForMatch], but we
  /// normalize again defensively.
  List<ReferenceBookHit> search(String query, {int limit = 50}) {
    if (limit <= 0) return const <ReferenceBookHit>[];

    final q = _normalizeForMatch(query);
    if (q.isEmpty) return const <ReferenceBookHit>[];

    final starts = <ReferenceBookHit>[];
    final contains = <ReferenceBookHit>[];

    // מסננת הביגרמים חוסכת את המעבר על כינויי כל הספרים בכל הקלדה — היא
    // קבוצת-על, ולכן הלולאה שמתחתיה נשארת הפוסקת היחידה על הדירוג.
    final acronymCandidates = AcronymsCache.instance.candidatesFor(q);

    // מסננת אוצר-המילים של ההתאמה המקורבת. בלעדיה כל הקלדה הייתה מריצה
    // מרחק-עריכה על הכותרת ועל כל כינוי של כל ספר שלא הותאם מילולית.
    final queryWords = q.split(' ');
    final fuzzyCandidates = _fuzzyCandidateBooks(queryWords);

    for (final book in BooksCache.instance.books) {
      final t = _normalizedTitles[book.id] ?? '';
      if (t.isEmpty) continue;

      int? matchRank;
      String? matchedTerm;
      var tailIsTitleWords = false;

      if (t == q) {
        matchRank = 0;
      } else if (t.startsWith(q)) {
        matchRank = 1;
      } else if (t.contains(q)) {
        matchRank = 2;
      } else if (acronymCandidates?.contains(book.id) ?? true) {
        // התאמת ראשי תיבות — המונחים כבר מנורמלים בעת טעינת הקאש.
        final normalizedAcronyms = AcronymsCache.instance.getAcronymsForBook(
          book.id,
        );
        if (normalizedAcronyms != null) {
          // עצל: החישוב רץ על כל ספר בספרייה בכל הקלדה, ורק התאמת-תחילית
          // צריכה אותו.
          Set<String>? titleTokens;
          for (final a in normalizedAcronyms) {
            if (a == q) {
              matchRank = 3;
              matchedTerm = a;
              break;
            }
            if (a.startsWith(q)) {
              titleTokens ??= titleMatchTokens(t);
              final tailIsTitle = _acronymTailIsTitleWords(a, q, titleTokens);
              // דירוג טוב יותר גובר על קודמיו — אחרת מונח "contains" (5) שנסרק
              // קודם היה מקבע 5 ומונע מהתאמת-התחילית הזו לדרג 4.
              if (matchRank == null ||
                  matchRank > 4 ||
                  (tailIsTitle && !tailIsTitleWords)) {
                matchRank = 4;
                matchedTerm = a;
                tailIsTitleWords = tailIsTitle;
              }
            } else if (a.contains(q) && matchRank == null) {
              matchRank = 5;
              matchedTerm = a;
            }
          }
        }
      }

      // מפלט אחרון: התאמה מקורבת, שמכסה כתיב מלא/חסר ושגיאות הקלדה
      // (issue #1310). רצה רק כשכל ההתאמות המילוליות נכשלו, ומדורגת מתחת
      // לכולן — כך סדר התוצאות הקיים אינו זז.
      if (matchRank == null && fuzzyCandidates.contains(book.id)) {
        final matched = _fuzzyMatchedTerm(queryWords, t, book.id);
        if (matched != null) {
          matchRank = fuzzyMatchRank;
          // כותרת שהותאמה אינה "מונח" — matchedTerm שמור לראשי-תיבות.
          if (matched != t) matchedTerm = matched;
        }
      }

      if (matchRank == null) continue;

      final hit = ReferenceBookHit(
        bookId: book.id,
        title: book.title,
        normalizedTitle: t,
        filePath: book.filePath ?? '',
        fileType: book.fileType,
        matchRank: matchRank,
        matchedTerm: matchedTerm,
        orderIndex: book.orderIndex,
        acronymTailIsTitleWords: tailIsTitleWords,
      );

      if (matchRank <= 1) {
        starts.add(hit);
      } else {
        contains.add(hit);
      }
    }

    // Search file-system PDF books
    for (final (t, baseHit) in _fsPdfBooks) {
      int? matchRank;
      if (t == q) {
        matchRank = 0;
      } else if (t.startsWith(q)) {
        matchRank = 1;
      } else if (t.contains(q)) {
        matchRank = 2;
      }
      if (matchRank == null) continue;

      final hit = ReferenceBookHit(
        bookId: baseHit.bookId,
        title: baseHit.title,
        normalizedTitle: t,
        filePath: baseHit.filePath,
        fileType: baseHit.fileType,
        matchRank: matchRank,
        orderIndex: baseHit.orderIndex,
      );

      if (matchRank <= 1) {
        starts.add(hit);
      } else {
        contains.add(hit);
      }
    }

    int cmp(ReferenceBookHit a, ReferenceBookHit b) {
      final r = a.matchRank.compareTo(b.matchRank);
      if (r != 0) return r;
      // Prefer lower orderIndex, then shorter title.
      final o = a.orderIndex.compareTo(b.orderIndex);
      if (o != 0) return o;
      return a.title.length.compareTo(b.title.length);
    }

    starts.sort(cmp);
    contains.sort(cmp);

    final merged = <ReferenceBookHit>[...starts, ...contains];
    if (merged.length <= limit) return merged;

    // issue #839: כשהתאמות-התחילית לבדן ממלאות את ה-limit, התאמות ה"מכיל"
    // נחתכות כליל ("מא" לא החזיר את יומא) — שמורה להן מכסה בזנב, starts ראשונות.
    const containsReserve = 10;
    if (starts.length >= limit && contains.isNotEmpty) {
      var reserve = containsReserve < contains.length
          ? containsReserve
          : contains.length;
      if (reserve >= limit) reserve = limit - 1;
      return [...starts.take(limit - reserve), ...contains.take(reserve)];
    }
    return merged.take(limit).toList();
  }

  /// מצב "דור + נושא" של איתור מקורות: מחזיר את כל הספרים שדורם (לפי נתיב
  /// הקטגוריה) הוא [era] וכותרתם תואמת את כל [topicTokens]. למשל
  /// `era=ראשונים, topic=["סנהדרין"]` → "חידושי רמב"ן על סנהדרין", "רש"י על
  /// סנהדרין" וכו'.
  ///
  /// אפס שאילתות DB — מסתמך על [_normalizedTitles] ו-[_categoryPaths] שכבר
  /// במטמון. ההתאמה בכותרת זהה במהותה ל-[search]: כל טוקן-נושא חייב להופיע
  /// כתחילית של טוקן כלשהו בכותרת.
  List<ReferenceBookHit> searchByEraAndTopic(
    CommentaryEra era,
    List<String> topicTokens, {
    int limit = 200,
  }) {
    if (topicTokens.isEmpty) return const <ReferenceBookHit>[];

    final hits = <ReferenceBookHit>[];
    for (final book in BooksCache.instance.books) {
      final path = _categoryPaths[book.id];
      if (path == null || path.isEmpty) continue;
      if (eraFromCategoryPath(path) != era) continue;

      final t = _normalizedTitles[book.id] ?? '';
      if (t.isEmpty) continue;
      final titleTokens = t.split(' ').where((w) => w.isNotEmpty);
      final matches = topicTokens.every(
        (qt) => titleTokens.any((w) => w.startsWith(qt)),
      );
      if (!matches) continue;

      hits.add(
        ReferenceBookHit(
          bookId: book.id,
          title: book.title,
          normalizedTitle: t,
          filePath: book.filePath ?? '',
          fileType: book.fileType,
          matchRank: 0,
          orderIndex: book.orderIndex,
        ),
      );
      if (hits.length >= limit) break;
    }
    return hits;
  }

  /// מסווג ספר לדור לפי segment בנתיב הקטגוריה. מכסה ראשונים/אחרונים/מחברי
  /// זמננו — אלה היחידים שמופיעים כ-segment בעץ. ספרי-יסוד וקורפוס מקור
  /// (תנ"ך/תלמוד) אינם מתויגים כך ולכן מוחזרים כ-[CommentaryEra.other].
  static CommentaryEra eraFromCategoryPath(String path) {
    final parts = path.split(', ');
    if (parts.contains('ראשונים')) return CommentaryEra.rishonim;
    if (parts.contains('אחרונים')) return CommentaryEra.acharonim;
    if (parts.contains('מחברי זמננו')) return CommentaryEra.modern;
    return CommentaryEra.other;
  }

  /// האם [acronym] הוא ראש-התיבות [q] בתוספת מילים שכולן מכותרת הספר.
  /// כך "רמב"ם תפילה" מזהה במלואו את "משנה תורה, הלכות תפילה וברכת כהנים"
  /// (ההמשך "וברכת כהנים" הוא כותרת), בעוד "טור חושן" אינו מזהה את "טור"
  /// ("משפט" אינה בכותרת — היא כותרת פנימית שצריכה חיפוש TOC).
  ///
  /// [titleTokens] חייב לבוא מ-[titleMatchTokens]: ראשי-תיבות ב-DB נכתבים
  /// לעתים בלי אות-החיבור שבכותרת ("ראב"ד ... ברכת כהנים" מול "וברכת כהנים"),
  /// והתאמה מדויקת הייתה מחמיצה אותם.
  static bool _acronymTailIsTitleWords(
    String acronym,
    String q,
    Set<String> titleTokens,
  ) {
    final qTokens = q.split(' ');
    final aTokens = acronym.split(' ');
    if (aTokens.length <= qTokens.length) return false;
    // התאמת התחילית חייבת להיות במילים שלמות — "רמבם תפילה" אינו תחילית-טוקנים
    // של "רמבם תפילות ראש השנה".
    for (var i = 0; i < qTokens.length; i++) {
      if (aTokens[i] != qTokens[i]) return false;
    }
    return aTokens.skip(qTokens.length).every(titleTokens.contains);
  }

  /// אורך המילה המינימלי להתאמה מקורבת.
  static const int _minFuzzyWordLength = 3;

  /// דירוג ההתאמה המקורבת — מתחת לכל ההתאמות המילוליות (0–5).
  /// חשוף כי `findRefs` צריך להבחין בו: התאמה מקורבת מצטרפת כמשנית בלבד.
  static const int fuzzyMatchRank = 6;

  /// אוסף ל-[booksByWord] את מילות הכותרת והכינויים של [entries]. כל ספר
  /// נסרק במלואו בבת אחת, ולכן מזההו תמיד בקצה הרשימה — כפילות נמנעת
  /// בהשוואה לאחרון, בלי Set לכל מילה.
  void _collectFuzzyWords(
    Map<String, List<int>> booksByWord,
    Iterable<MapEntry<int, String>> entries,
  ) {
    void addWords(int bookId, String text) {
      for (final word in text.split(' ')) {
        if (word.isEmpty) continue;
        final books = booksByWord.putIfAbsent(word, () => <int>[]);
        if (books.isEmpty || books.last != bookId) books.add(bookId);
      }
    }

    for (final entry in entries) {
      addWords(entry.key, entry.value);
      final acronyms = AcronymsCache.instance.getAcronymsForBook(entry.key);
      if (acronyms == null) continue;
      for (final term in acronyms) {
        addWords(entry.key, term);
      }
    }
  }

  void _installFuzzyVocabulary(Map<String, List<int>> booksByWord) {
    _fuzzyWordCandidates.clear();
    _fuzzyVocabulary
      ..clear()
      ..addAll(booksByWord.keys);
    _fuzzyVocabularyBooks
      ..clear()
      ..addAll(booksByWord.values.map(Uint32List.fromList));
  }

  /// בונה את מסננת אוצר-המילים בפרוסות. `false` = בוטל (דור התחלף), ואז
  /// הקורא חייב לא לסמן את הקאש כ-loaded. בסביבות 140ms על ספרייה מלאה —
  /// רצף כזה על ה-isolate של ה-UI היה מקפיא פריימים.
  Future<bool> _prewarmFuzzyVocabulary(
    Map<int, String> normalizedTitles,
    int myGen,
  ) async {
    final entries = normalizedTitles.entries.toList(growable: false);
    final booksByWord = <String, List<int>>{};
    const batch = 500;

    for (var i = 0; i < entries.length; i += batch) {
      final end = i + batch < entries.length ? i + batch : entries.length;
      _collectFuzzyWords(booksByWord, entries.getRange(i, end));
      await Future<void>.delayed(Duration.zero);
      if (myGen != _generation) return false;
    }

    _installFuzzyVocabulary(booksByWord);
    return true;
  }

  /// מזהי הספרים שבהם לכל אחת מ-[queryWords] יש מילה מתאימה — קבוצת-העל של
  /// ההתאמה המקורבת. [_fuzzyMatchedTerm] נשאר הפוסק, כי הוא דורש שכל המילים
  /// יימצאו ב**אותו** טקסט; כאן הן עשויות לבוא מכינויים שונים.
  Set<int> _fuzzyCandidateBooks(List<String> queryWords) {
    if (!queryWords.any((w) => w.length >= _minFuzzyWordLength)) {
      return const <int>{};
    }

    Set<int>? candidates;
    for (final word in queryWords) {
      if (word.isEmpty) continue;
      final forWord = _fuzzyCandidatesForWord(word);

      // העתקה ולא שימוש חוזר: הרשימה מגיעה מהמטמון, ו-retainAll היה פוגם בה.
      candidates == null
          ? candidates = <int>{...forWord}
          : candidates.retainAll(forWord);
      if (candidates.isEmpty) return const <int>{};
    }
    return candidates ?? const <int>{};
  }

  /// מזהי הספרים שיש בהם מילה המתאימה ל-[word], מהמטמון או בסריקת האוצר.
  Set<int> _fuzzyCandidatesForWord(String word) {
    final cached = _fuzzyWordCandidates[word];
    if (cached != null) return cached;

    // מילה קצרה נדרשת כמילה שלמה ולא בקירוב, ולכן גם המסננת מדויקת —
    // `contains` עליה היה מחזיר כמעט כל מילה באוצר.
    final exact = word.length < _minFuzzyWordLength;
    final books = <int>{};
    for (var i = 0; i < _fuzzyVocabulary.length; i++) {
      final vocabWord = _fuzzyVocabulary[i];
      final matches = exact
          ? vocabWord == word
          : bookSearchWordPairMatches(word, vocabWord);
      if (matches) books.addAll(_fuzzyVocabularyBooks[i]);
    }

    if (_fuzzyWordCandidates.length >= _fuzzyWordCandidatesLimit) {
      _fuzzyWordCandidates.remove(_fuzzyWordCandidates.keys.first);
    }
    _fuzzyWordCandidates[word] = books;
    return books;
  }

  /// מחזיר את הכותרת או המונח שכל [queryWords] נמצאו בו, או `null`.
  ///
  /// כל מילות השאילתה חייבות להיכנס ב**אותו** טקסט — אחרת "חדושי הלכות" היה
  /// מותאם לספר שרק "הלכות" מופיע בו. הכותרת נבדקת ראשונה, ואם נכשלה נבדק
  /// כל כינוי, כי "רמבם תפלה" חי בכינוי ולא בכותרת.
  ///
  /// טוקן קצר ("ב" של פרק ב) נדרש כמילה שלמה ולא בקירוב: בלעדיו
  /// "רמב"ם תפילה ב" היה נראה כזיהוי מלא של הספר, וטוקן המיקום לא היה מגיע
  /// לחיפוש הכותרות הפנימיות.
  String? _fuzzyMatchedTerm(List<String> queryWords, String title, int bookId) {
    bool allWordsIn(String text) {
      List<String>? textWords;
      for (final word in queryWords) {
        if (word.length < _minFuzzyWordLength) {
          textWords ??= text.split(' ');
          if (!textWords.contains(word)) return false;
        } else if (!bookSearchWordMatchesFuzzy(word, text)) {
          return false;
        }
      }
      return true;
    }

    if (allWordsIn(title)) return title;
    final acronyms = AcronymsCache.instance.getAcronymsForBook(bookId);
    if (acronyms == null) return null;
    for (final term in acronyms) {
      if (allWordsIn(term)) return term;
    }
    return null;
  }

  static String _normalizeForMatch(String input) =>
      normalizeForFindRefMatch(input);

  Future<_PdfFileMetadataReadResult> _readPdfFileMetadata(
    String filePath,
  ) async {
    final override = pdfFileMetadataProviderOverride;
    if (override != null) {
      try {
        final metadata = await override(filePath);
        return metadata == null
            ? const _PdfFileMetadataReadResult.missing()
            : _PdfFileMetadataReadResult.available(metadata);
      } catch (e) {
        debugPrint(
          '[ReferenceBooksCache] Failed to read PDF file metadata for '
          '$filePath via override: $e',
        );
        return const _PdfFileMetadataReadResult.unavailable();
      }
    }

    try {
      final stat = await File(filePath).stat();
      if (stat.type == FileSystemEntityType.notFound) {
        return const _PdfFileMetadataReadResult.missing();
      }
      return _PdfFileMetadataReadResult.available((
        fileSize: stat.size,
        lastModified: stat.modified.millisecondsSinceEpoch,
      ));
    } catch (e) {
      debugPrint(
        '[ReferenceBooksCache] Failed to read PDF file metadata for '
        '$filePath: $e',
      );
      return const _PdfFileMetadataReadResult.unavailable();
    }
  }

  /// מחזיר את ה-repository הכתיב למטמון ה-outline. ברירת המחדל היא
  /// [CacheDatabaseHolder] (קובץ `cache.db` נפרד וכתיב) ולא `seforim.db`,
  /// כדי ש-`seforim.db` יוכל להיפתח read-only. בבדיקות ניתן לדרוס דרך
  /// [pdfOutlineCacheRepositoryOverride].
  Future<SeforimRepository?> _resolvePdfOutlineRepository() async {
    final override = pdfOutlineCacheRepositoryOverride;
    if (override != null) return override;

    try {
      return await CacheDatabaseHolder.instance.repository;
    } catch (e) {
      debugPrint(
        '[ReferenceBooksCache] Failed to open cache.db for PDF outline '
        'persistence: $e',
      );
      return null;
    }
  }

  int _nowMillis() => (nowProviderOverride ?? _defaultNowMillis).call();

  static int _defaultNowMillis() => DateTime.now().millisecondsSinceEpoch;

  Future<PdfOutlineCacheEntry?> _loadPersistentPdfOutline(
    String filePath,
  ) async {
    final repository = await _resolvePdfOutlineRepository();
    if (repository == null) return null;

    try {
      return await repository.getPdfOutlineCacheEntry(filePath);
    } catch (e) {
      debugPrint(
        '[ReferenceBooksCache] Failed to load PDF outline cache for '
        '$filePath: $e',
      );
      return null;
    }
  }

  Future<void> _savePersistentPdfOutline(PdfOutlineCacheEntry entry) async {
    final repository = await _resolvePdfOutlineRepository();
    if (repository == null) return;

    try {
      await repository.upsertPdfOutlineCacheEntry(entry);
    } catch (e) {
      debugPrint(
        '[ReferenceBooksCache] Failed to persist PDF outline cache for '
        '${entry.filePath}: $e',
      );
    }
  }

  Future<void> _touchPersistentPdfOutline(String filePath) async {
    final repository = await _resolvePdfOutlineRepository();
    if (repository == null) return;

    try {
      await repository.touchPdfOutlineCacheEntry(filePath, _nowMillis());
    } catch (e) {
      debugPrint(
        '[ReferenceBooksCache] Failed to touch persisted PDF outline cache '
        'for $filePath: $e',
      );
    }
  }

  Future<void> _deletePersistentPdfOutline(String filePath) async {
    final repository = await _resolvePdfOutlineRepository();
    if (repository == null) return;

    try {
      await repository.deletePdfOutlineCacheEntry(filePath);
    } catch (e) {
      debugPrint(
        '[ReferenceBooksCache] Failed to delete persisted PDF outline cache '
        'for $filePath: $e',
      );
    }
  }

  Future<void> _prunePersistentPdfOutlineCache({
    required int generation,
    Set<String>? knownFilePaths,
    Duration ttl = _persistentPdfOutlineCacheTtl,
  }) async {
    final repository = await _resolvePdfOutlineRepository();
    if (repository == null) return;

    final cutoffMillis = _nowMillis() - ttl.inMilliseconds;
    await repository.prunePdfOutlineCacheAccessedBefore(cutoffMillis);
    if (generation != _generation) return;

    if (knownFilePaths != null) {
      await repository.prunePdfOutlineCacheExceptFilePaths(knownFilePaths);
    }
  }

  @visibleForTesting
  Future<void> prunePersistentPdfOutlineCacheForTesting({
    required Set<String>? knownFilePaths,
    Duration ttl = _persistentPdfOutlineCacheTtl,
  }) {
    return _prunePersistentPdfOutlineCache(
      generation: _generation,
      knownFilePaths: knownFilePaths,
      ttl: ttl,
    );
  }

  static Future<List<(String, String, int)>> _parsePdfOutlineEntries(
    String filePath,
  ) async {
    PdfDocument? doc;
    try {
      doc = await PdfDocument.openFile(filePath);
      final outline = await doc.loadOutline();
      final entries = <(String, String, int)>[];
      _collectOutlineEntries(outline, entries, maxDepth: 2, currentDepth: 0);
      debugPrint(
        '[ReferenceBooksCache] Parsed ${entries.length} outline entries for $filePath',
      );
      return entries;
    } catch (e) {
      debugPrint(
        '[ReferenceBooksCache] Failed to parse outline for $filePath: $e',
      );
      return const [];
    } finally {
      // סגירת המסמך משחררת את ה-pdfrx worker. בלי זה הוא נשאר פתוח עד GC
      // ומציף את ה-worker היחיד (פוגע בפעולות pdfrx אחרות כמו תצוגת הדפסה).
      await doc?.dispose();
    }
  }

  static void _collectOutlineEntries(
    List<PdfOutlineNode> nodes,
    List<(String, String, int)> out, {
    required int maxDepth,
    required int currentDepth,
  }) {
    if (currentDepth >= maxDepth) return;
    for (final node in nodes) {
      final page = node.dest?.pageNumber;
      if (page != null && node.title.isNotEmpty) {
        out.add((_normalizeForMatch(node.title), node.title, page));
      }
      _collectOutlineEntries(
        node.children,
        out,
        maxDepth: maxDepth,
        currentDepth: currentDepth + 1,
      );
    }
  }
}

class _PdfFileMetadataReadResult {
  final ({int fileSize, int lastModified})? metadata;
  final bool isMissing;

  const _PdfFileMetadataReadResult.available(
    ({int fileSize, int lastModified}) this.metadata,
  ) : isMissing = false;

  const _PdfFileMetadataReadResult.missing()
    : metadata = null,
      isMissing = true;

  const _PdfFileMetadataReadResult.unavailable()
    : metadata = null,
      isMissing = false;
}

class ReferenceBookHit {
  final int bookId;
  final String title;

  /// הכותרת לאחר [normalizeForFindRefMatch], מחושבת מראש במטמון
  /// כדי לחסוך נורמליזציה חוזרת בצרכן.
  final String normalizedTitle;
  final String filePath;
  final String fileType;
  final int matchRank;
  final String? matchedTerm;
  final double orderIndex;

  /// עבור [matchRank] == 4 (השאילתה היא תחילית-טוקנים של [matchedTerm]): האם
  /// שאר מילות ראש-התיבות כולן מילים מכותרת הספר. אם כן — השאילתה מזהה את
  /// הספר במלואו ("רמב"ם תפילה" ⊂ "רמב"ם תפילה וברכת כהנים"); אם לא — ההמשך
  /// הוא כותרת פנימית ("טור חושן" ⊂ "טור חושן משפט", ו"משפט" אינה בכותרת "טור").
  final bool acronymTailIsTitleWords;

  const ReferenceBookHit({
    required this.bookId,
    required this.title,
    required this.normalizedTitle,
    required this.filePath,
    required this.fileType,
    required this.matchRank,
    required this.orderIndex,
    this.matchedTerm,
    this.acronymTailIsTitleWords = false,
  });
}

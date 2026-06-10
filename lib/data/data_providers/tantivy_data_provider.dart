import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria/core/app_paths.dart';

/// A singleton class that manages search functionality using Tantivy search engine.
///
/// This provider handles the search operations for both text-based and PDF books,
/// maintaining an index for full-text search capabilities.
class TantivyDataProvider {
  static const SearchEngineGateway _searchGateway = SearchEngineGateway();
  static const String _booksDoneKey = 'key-books-done';

  /// Instance of the search engine pointing to the index directory
  late Future<SearchEngine> engine;

  bool _indexExistedBeforeInit = false;

  /// Track if index is being reopened to prevent concurrent reopens
  bool _isReopening = false;
  DateTime? _lastReopenTime;

  static final TantivyDataProvider _singleton = TantivyDataProvider._internal();
  static TantivyDataProvider instance = _singleton;

  // Global cache for facet counts
  static final Map<String, int> _globalFacetCache = {};
  static String _lastCachedQuery = '';

  // Track ongoing counts to prevent duplicates
  static final Set<String> _ongoingCounts = {};
  /// האם האינדקס הקיים על הדיסק תואם לגרסת מנוע החיפוש הנוכחית.
  /// מחושב בעת האתחול באמצעות [checkIndexCompatibility] של מנוע החיפוש,
  /// שמזהה את גרסת סכמת האינדקס שעל הדיסק ומשווה אותה לגרסה שהמנוע דורש.
  /// כל עוד אין אינדקס קיים הערך נשאר true (אין מה לבדוק).
  bool _indexCompatible = true;

  Box? _hiveBox;
  String? _hiveBoxDirectory;

  /// Clear global cache when starting new search
  static void clearGlobalCache() {
    debugPrint(
        '🧹 Clearing global facet cache (${_globalFacetCache.length} entries)');
    _globalFacetCache.clear();
    _ongoingCounts.clear();
    _lastCachedQuery = '';
  }

  /// Indicates whether the indexing process is currently running
  ValueNotifier<bool> isIndexing = ValueNotifier(false);

  /// מסמן שהטעינה האסינכרונית של מצב האינדקס מהדיסק (booksDone) הסתיימה.
  /// עד שהערך הופך ל-true, אסור להסיק "אין אינדקס" מ-booksDone.isEmpty.
  final ValueNotifier<bool> isInitialized = ValueNotifier(false);

  /// Maintains a list of processed books to avoid reindexing
  late List<String> booksDone = [];

  TantivyDataProvider._internal() {
    // Initialize sequentially: check index existence BEFORE the engine
    // recreates the directory, then load booksDone.
    engine = _initAll();
  }

  Future<SearchEngine> _initAll() async {
    // Check if the index directory existed BEFORE the engine creates it.
    final indexPath = await AppPaths.getIndexPath();
    final indexExistedBefore = Directory(indexPath).existsSync();
    _indexExistedBeforeInit = indexExistedBefore;

    // בדיקת תאימות האינדקס שעל הדיסק לפני פתיחת המנוע (שכותב מטא-נתונים
    // מעודכנים לאינדקס תואם). כך נזהה אינדקס שנבנה בגרסת מנוע ישנה.
    _indexCompatible = _evaluateIndexCompatibility(indexPath, indexExistedBefore);

    // Load persisted booksDone from disk.
    await _loadBooksDone();

    // If the index was manually deleted, clear booksDone so every book
    // is re-indexed from scratch.
    if (!indexExistedBefore && booksDone.isNotEmpty) {
      debugPrint('⚠️ תיקיית האינדקס נמחקה – מנקה רשימת ספרים מאונדקסים');
      booksDone.clear();
      await saveBooksDoneToDisk();
    }

    // booksDone כעת משקפת נכונה את מצב האינדקס על הדיסק. צרכנים שמסיקים
    // "אין אינדקס" מתוך הרשימה צריכים לחכות לסימן הזה כדי לא להציג שגוי בהפעלה.
    isInitialized.value = true;

    // Now initialise the search engine (creates the directory if needed).
    return _initEngine();
  }

  Future<SearchEngine> _initEngine() async {
    String? indexPath;
    File? sentinelFile;

    try {
      indexPath = await AppPaths.getIndexPath();
      final parentDir = Directory(indexPath).parent;
      if (!parentDir.existsSync()) {
        parentDir.createSync(recursive: true);
      }

      sentinelFile = File('${parentDir.path}/.engine_init_started');

      // Check for previous crash
      if (sentinelFile.existsSync()) {
        debugPrint(
            '⚠️ Detected crash during previous engine init. Moving corrupted index aside.');
        try {
          if (Directory(indexPath).existsSync()) {
            // Use rename instead of delete - much safer on Windows
            final corruptedPath =
                '${indexPath}_corrupted_${DateTime.now().millisecondsSinceEpoch}';
            Directory(indexPath).renameSync(corruptedPath);
            debugPrint('📦 Moved corrupted index to $corruptedPath');
          }
        } catch (e) {
          debugPrint('❌ Failed to rename corrupted index: $e');
          // If rename fails, force use a new path
          indexPath =
              '${indexPath}_new_${DateTime.now().millisecondsSinceEpoch}';
        }

        // Try to clear sentinel
        try {
          sentinelFile.deleteSync();
        } catch (_) {}
      }

      // Create sentinel for THIS run
      try {
        await sentinelFile.writeAsString(DateTime.now().toString());
      } catch (e) {
        debugPrint('⚠️ Failed to create sentinel file: $e');
      }

      // Ensure the index directory exists before opening the engine.
      final indexDir = Directory(indexPath);
      if (!indexDir.existsSync()) {
        indexDir.createSync(recursive: true);
      }

      // Try to open engine
      // If this CRASHES the process, the sentinel remains for next run.
      // If it throws an Exception, we catch it below.
      final engine = SearchEngine(path: indexPath);

      // If we got here, success! Remove sentinel.
      try {
        await sentinelFile.delete();
      } catch (_) {}

      return engine;
    } catch (e) {
      debugPrint('❌ Failed to initialize search engine: $e');

      // Cleanup sentinel since it was a soft error
      if (sentinelFile != null && sentinelFile.existsSync()) {
        try {
          sentinelFile.deleteSync();
        } catch (_) {}
      }

      // Recover by falling back to temp memory index
      debugPrint('⚠️ Falling back to temporary in-memory index');
      try {
        final tempDir =
            Directory.systemTemp.createTempSync('otzaria_temp_index_');
        return SearchEngine(path: tempDir.path);
      } catch (e2) {
        debugPrint('❌ CRITICAL: Failed to create temp index: $e2');
        rethrow;
      }
    }
  }

  /// פותח את box ה-Hive בנתיב הנתון. אם כבר פתוח באותו נתיב — מחזיר אותו.
  /// אם פתוח בנתיב אחר — סוגר קודם ופותח מחדש.
  Future<Box> _openBox(String directory) async {
    if (_hiveBox != null &&
        _hiveBox!.isOpen &&
        _hiveBoxDirectory == directory) {
      return _hiveBox!;
    }
    if (_hiveBox != null && _hiveBox!.isOpen) {
      await _hiveBox!.close();
    }
    _hiveBox = await Hive.openBox('books_indexed', path: directory);
    _hiveBoxDirectory = directory;
    return _hiveBox!;
  }

  Future<void> _closeBox() async {
    if (_hiveBox != null && _hiveBox!.isOpen) {
      await _hiveBox!.close();
    }
    _hiveBox = null;
    _hiveBoxDirectory = null;
  }

  Future<void> _loadBooksDone() async {
    try {
      final lockPath = await AppPaths.getTantivyLockPath();
      booksDone = await _readBooksDoneFromBox(lockPath);
    } catch (e) {
      debugPrint('⚠️ Error loading books done: $e');
      booksDone = [];
    }
  }

  Future<List<String>> _readBooksDoneFromBox(String directory) async {
    final box = await _openBox(directory);
    final dynamic value = box.get(_booksDoneKey, defaultValue: []);
    if (value is List) {
      return value.map<String>((e) => e.toString()).toList();
    }
    return [];
  }

  /// בודק אם האינדקס הקיים בנתיב [indexPath] תואם לגרסת מנוע החיפוש הנוכחית.
  ///
  /// משתמש ב-[checkIndexCompatibility] של מנוע החיפוש, שקורא את מטא-הנתונים
  /// של האינדקס ומזהה את גרסת הסכמה שלו. מחזיר true כשאין אינדקס קיים
  /// (אין מה לבדוק) או כשהאינדקס תואם. אם הבדיקה עצמה נכשלת לא מכריחים
  /// בנייה מחדש כדי לא לפגוע במשתמש בלי סיבה ודאית.
  bool _evaluateIndexCompatibility(String indexPath, bool indexExists) {
    if (!indexExists) {
      return true;
    }
    try {
      final compatibility = checkIndexCompatibility(path: indexPath);
      if (!compatibility.compatible) {
        debugPrint(
          '⚠️ אינדקס החיפוש אינו תואם לגרסת המנוע הנוכחית '
          '(status=${compatibility.status}, '
          'foundSchemaVersion=${compatibility.foundSchemaVersion}, '
          'requiredSchemaVersion=${compatibility.requiredSchemaVersion}) '
          '- נדרש איפוס ובנייה מחדש',
        );
      }
      return compatibility.compatible;
    } catch (e) {
      debugPrint('⚠️ כשל בבדיקת תאימות האינדקס: $e');
      return true;
    }
  }

  @visibleForTesting
  static bool shouldPromptForManualReindex({
    required bool indexExistedBeforeInit,
    required bool indexCompatible,
  }) {
    return indexExistedBeforeInit && !indexCompatible;
  }

  /// מחזיר האם נדרש איפוס ובנייה מחדש של האינדקס באישור המשתמש, כלומר כשקיים
  /// על הדיסק אינדקס שאינו תואם לגרסת סכמת מנוע החיפוש הנוכחית.
  bool requiresManualReindex() {
    return shouldPromptForManualReindex(
      indexExistedBeforeInit: _indexExistedBeforeInit,
      indexCompatible: _indexCompatible,
    );
  }

  Future<bool> ensureIndexStateMatchesCatalogue() async {
    if (!requiresManualReindex()) {
      return false;
    }

    debugPrint(
      '⚠️ אינדקס החיפוש אינו תואם לגרסת המנוע הנוכחית '
      '- נדרש איפוס ואינדוקס ידני באישור המשתמש',
    );
    return true;
  }

  Future<void> prepareForManualReindex() async {
    final lockPath = await AppPaths.getTantivyLockPath();
    booksDone = [];
    // לאחר האיפוס והבנייה מחדש המנוע יכתוב מטא-נתונים תואמים לאינדקס החדש.
    _indexCompatible = true;
    await _persistIndexState(lockPath);
  }

  Future<void> _persistIndexState(String directory) async {
    final box = await _openBox(directory);
    await box.put(_booksDoneKey, booksDone);
  }

  Future<void> _handleSchemaError() async {
    try {
      String indexPath = await AppPaths.getIndexPath();
      await resetIndex(indexPath);
      await reopenIndex();
    } catch (e) {
      debugPrint('❌ Error handling schema error: $e');
    }
  }

  Future<void> reopenIndex() async {
    // Prevent concurrent reopens that would cause lock conflicts
    if (_isReopening) {
      debugPrint('⚠️ Index reopen already in progress, skipping...');
      return;
    }

    // Prevent too frequent reopens (less than 5 seconds apart)
    if (_lastReopenTime != null &&
        DateTime.now().difference(_lastReopenTime!).inSeconds < 5) {
      debugPrint('⚠️ Index reopen too soon after last reopen, skipping...');
      return;
    }

    _isReopening = true;
    _lastReopenTime = DateTime.now();
    debugPrint('🔄 Reopening search index...');

    try {
      final indexPath = await AppPaths.getIndexPath();
      _indexExistedBeforeInit = Directory(indexPath).existsSync();

      // Dispose previous engine to release locks
      await dispose();

      // Reset engines
      engine = _initEngine();

      // Check engine
      engine.then((value) {
        try {
          // Test the search engine
          _searchGateway
              .search(
            RustSearchEngineOperations(value),
            const SearchEngineRequest(
              query: 'a',
              limit: 10,
              offset: 0,
              facets: ["/"],
              order: ResultsOrder.catalogue,
              searchMode: SearchMode.exact,
            ),
          )
              .then((results) {
            // Engine test successful
            debugPrint('✅ Search engine test successful');
          }).catchError((e) {
            debugPrint('❌ Engine test error: $e');
          });
        } catch (e) {
          // Log sync engine test error
          debugPrint('❌ Sync engine test error: $e');
          if (e.toString() ==
              "PanicException(Failed to create index: SchemaError(\"An index exists but the schema does not match.\"))") {
            // Handle schema error asynchronously
            _handleSchemaError();
          } else {
            rethrow;
          }
        }
      });

      await _loadBooksDone();

      debugPrint('✅ Search index reopened successfully');
    } finally {
      _isReopening = false;
    }
  }

  /// Persists the list of indexed books to disk using Hive storage.
  Future<void> saveBooksDoneToDisk() async {
    final lockPath = await AppPaths.getTantivyLockPath();
    await _persistIndexState(lockPath);
  }

  /// מחזיר האם תיקיית האינדקס כבר הייתה קיימת לפני פתיחת המנוע הנוכחי.
  ///
  /// משמש כדי להבחין בין יצירת אינדקס ראשונית לבין בנייה מחדש מעל אינדקס ישן.
  bool get indexExistedBeforeInit => _indexExistedBeforeInit;

  Future<int> countTexts(String query, List<String> books, List<String> facets,
      {bool fuzzy = false,
      int distance = 0,
      SearchMode searchMode = SearchMode.exact,
      Map<String, String>? customSpacing,
      Map<int, List<String>>? alternativeWords,
      Map<String, Map<String, bool>>? searchOptions}) async {
    // Global cache check
    final cacheKey =
        '$query|${facets.join(',')}|$fuzzy|$searchMode|$distance|${customSpacing.toString()}|${alternativeWords.toString()}|${searchOptions.toString()}';

    if (_lastCachedQuery == query && _globalFacetCache.containsKey(cacheKey)) {
      debugPrint(
          '🎯 GLOBAL CACHE HIT for $facets: ${_globalFacetCache[cacheKey]}');
      return _globalFacetCache[cacheKey]!;
    }

    // Check if this count is already in progress
    if (_ongoingCounts.contains(cacheKey)) {
      debugPrint('⏳ Count already in progress for $facets, waiting...');
      // Wait for the ongoing count to complete
      while (_ongoingCounts.contains(cacheKey)) {
        await Future.delayed(const Duration(milliseconds: 50));
        if (_globalFacetCache.containsKey(cacheKey)) {
          debugPrint(
              '🎯 DELAYED CACHE HIT for $facets: ${_globalFacetCache[cacheKey]}');
          return _globalFacetCache[cacheKey]!;
        }
      }
    }

    // Mark this count as in progress
    _ongoingCounts.add(cacheKey);

    try {
      final count = await _searchGateway.count(
        RustSearchEngineOperations(await engine),
        SearchEngineRequest(
          query: query,
          facets: facets,
          searchMode: fuzzy ? SearchMode.fuzzy : searchMode,
          distance: distance,
          customSpacing: customSpacing ?? const {},
          alternativeWords: alternativeWords ?? const {},
          searchOptions: searchOptions ?? const {},
        ),
      );

      // Save to global cache
      _lastCachedQuery = query;
      _globalFacetCache[cacheKey] = count;
      _ongoingCounts.remove(cacheKey); // Mark as completed
      debugPrint('💾 GLOBAL CACHE SAVE for $facets: $count');

      return count;
    } catch (e) {
      // Log error in production
      rethrow;
    } finally {
      // Remove from ongoing counts even on error
      _ongoingCounts.remove(cacheKey);
    }
  }

  Future<void> resetIndex(String indexPath,
      {bool closeBooksDoneBox = true}) async {
    debugPrint('🔄 Resetting index at: $indexPath');

    // Close engines first to release locks
    try {
      await dispose();
      debugPrint('🔒 Engines disposed before reset');
    } catch (e) {
      debugPrint('⚠️ Error disposing engines before reset: $e');
    }

    Directory indexDirectory = Directory(indexPath);
    if (closeBooksDoneBox) {
      try {
        await _closeBox();
      } catch (e) {
        debugPrint('⚠️ Error closing Hive box: $e');
      }
    }

    if (indexDirectory.existsSync()) {
      try {
        indexDirectory.deleteSync(recursive: true);
      } catch (e) {
        debugPrint('❌ Failed to delete index directory: $e');
        // On Windows, sometimes files are locked for a bit longer
        await Future.delayed(const Duration(seconds: 1));
        if (indexDirectory.existsSync()) {
          indexDirectory.deleteSync(recursive: true);
        }
      }
    }

    indexDirectory.createSync(recursive: true);

    debugPrint('✅ Index reset completed');
  }

  Future<Map<String, int>> countByBook(
    String query,
    List<String> facets, {
    bool fuzzy = false,
    int distance = 0,
    SearchMode searchMode = SearchMode.exact,
    Map<String, String>? customSpacing,
    Map<int, List<String>>? alternativeWords,
    Map<String, Map<String, bool>>? searchOptions,
  }) async {
    final results = await _searchGateway.countByBook(
      RustSearchEngineOperations(await engine),
      SearchEngineRequest(
        query: query,
        facets: facets,
        searchMode: fuzzy ? SearchMode.fuzzy : searchMode,
        distance: distance,
        customSpacing: customSpacing ?? const {},
        alternativeWords: alternativeWords ?? const {},
        searchOptions: searchOptions ?? const {},
      ),
    );

    return Map<String, int>.from(results);
  }

  /// Performs an asynchronous stream-based search operation across indexed texts.
  ///
  /// [query] The search query string
  /// [books] List of book identifiers to search within
  /// [limit] Maximum number of results to return
  /// [fuzzy] Whether to perform fuzzy matching
  ///
  /// Returns a Stream of search results that can be listened to for real-time updates
  Stream<List<SearchResult>> searchTextsStream(
      String query, List<String> facets, int limit, bool fuzzy) async* {
    yield* _searchGateway.searchStream(
      RustSearchEngineOperations(await engine),
      SearchEngineRequest(
        query: query,
        facets: facets,
        limit: limit,
        searchMode: fuzzy ? SearchMode.fuzzy : SearchMode.exact,
      ),
      chunkSize: 50,
    );
  }

  /// ספירה מקבצת של תוצאות עבור מספר facets בבת אחת - לשיפור ביצועים.
  /// מקבץ facets לפי parent prefix ומשתמש ב-getFacetCounts כשיש כמה siblings,
  /// כדי לחסוך קריאות FFI מיותרות.
  Future<Map<String, int>> countTextsForMultipleFacets(
      String query, List<String> books, List<String> facets,
      {bool fuzzy = false,
      int distance = 0,
      SearchMode searchMode = SearchMode.exact,
      Map<String, String>? customSpacing,
      Map<int, List<String>>? alternativeWords,
      Map<String, Map<String, bool>>? searchOptions,
      bool allowEarlyStop = true}) async {
    debugPrint(
        '🔍 TantivyDataProvider: Starting batch count for ${facets.length} facets');
    final stopwatch = Stopwatch()..start();

    final operations = RustSearchEngineOperations(await engine);
    final results = <String, int>{};
    final baseRequest = SearchEngineRequest(
      query: query,
      facets: facets,
      searchMode: fuzzy ? SearchMode.fuzzy : searchMode,
      distance: distance,
      customSpacing: customSpacing ?? const {},
      alternativeWords: alternativeWords ?? const {},
      searchOptions: searchOptions ?? const {},
    );

    // קיבוץ facets לפי parent prefix כדי לחסוך קריאות FFI
    final Map<String, List<String>> byParent = {};
    for (final facet in facets) {
      final lastSlash = facet.lastIndexOf('/');
      final parent = lastSlash > 0 ? facet.substring(0, lastSlash) : '/';
      (byParent[parent] ??= []).add(facet);
    }

    for (final entry in byParent.entries) {
      final parent = entry.key;
      final siblings = entry.value;

      if (siblings.length > 1) {
        // כמה siblings מאותו parent - קריאה אחת ל-getFacetCounts מספיקה
        try {
          debugPrint(
              '🔍 getFacetCounts: parent=$parent (${siblings.length} siblings)');
          final facetCounts = await _searchGateway.getFacetCounts(
            operations,
            baseRequest.copyWith(facets: [parent]),
            facetPrefix: parent,
          );
          final countMap = {
            for (final fc in facetCounts) fc.path: fc.count.toInt(),
          };
          for (final sibling in siblings) {
            results[sibling] = countMap[sibling] ?? 0;
          }
          debugPrint(
              '✅ getFacetCounts: ${countMap.entries.where((e) => e.value > 0).length} non-zero');
        } catch (e) {
          debugPrint('⚠️ getFacetCounts failed for $parent, fallback: $e');
          // fallback לקריאות count נפרדות
          for (final facet in siblings) {
            try {
              results[facet] = await _searchGateway.count(
                operations,
                baseRequest.copyWith(facets: [facet]),
              );
            } catch (e2) {
              debugPrint('❌ count failed for $facet: $e2');
              results[facet] = 0;
            }
          }
        }
      } else {
        // sibling יחיד - count ישיר יעיל יותר
        final facet = siblings[0];
        try {
          results[facet] = await _searchGateway.count(
            operations,
            baseRequest.copyWith(facets: [facet]),
          );
        } catch (e) {
          debugPrint('❌ count failed for $facet: $e');
          results[facet] = 0;
        }
      }
    }

    stopwatch.stop();
    debugPrint(
        '✅ TantivyDataProvider: Batch count completed in ${stopwatch.elapsedMilliseconds}ms');
    debugPrint(
        '📊 Results: ${results.entries.where((e) => e.value > 0).map((e) => '${e.key}: ${e.value}').join(', ')}');

    return results;
  }

  /// Clears the index and resets the list of indexed books.
  ///
  /// מוחק פיזית את תיקיית האינדקס הפעילה וכל תיקיות אינדקס ישנות שנשארו
  /// בנתיבי ברירת מחדל אחרים, ואז פותח מנוע חדש. כך, אם המשתמש העביר
  /// את הספרייה לכונן אחר, האינדקס הבא ייבנה ליד הספרייה החדשה.
  Future<void> clear() async {
    isIndexing.value = false;
    booksDone.clear();
    // האינדקס נמחק ונבנה מחדש מאפס, ולכן יהיה תואם לגרסת המנוע הנוכחית.
    _indexCompatible = true;

    // שחרור משאבים לפני מחיקה פיזית של הקבצים (חשוב במיוחד ב-Windows
    // שבו קבצים פתוחים אינם ניתנים למחיקה).
    try {
      await dispose();
    } catch (e) {
      debugPrint('⚠️ Engine dispose during clear failed: $e');
    }
    try {
      await _closeBox();
    } catch (e) {
      debugPrint('⚠️ Hive box close during clear failed: $e');
    }

    // מחיקת תיקיית האינדקס הפעילה + כל ברירות המחדל הישנות. בלי זה,
    // אם נשארת תיקייה ב-APPDATA למשל, getIndexPath בהפעלה הבאה היה
    // ממשיך לבחור בה במקום בנתיב החדש ליד הספרייה.
    await _deleteAllKnownIndexDirectories();

    // אחרי המחיקה אין יותר אינדקס קיים על הדיסק.
    _indexExistedBeforeInit = false;

    // פתיחה מחדש: getIndexPath יחזיר עכשיו את ברירת המחדל הנוכחית
    // (ליד הספרייה, אם אין הגדרה ידנית ב-keyIndexPath).
    engine = _initEngine();

    // שמירת המצב הנקי בתיקיית ה-lock של הנתיב החדש.
    await saveBooksDoneToDisk();
  }

  Future<void> _deleteAllKnownIndexDirectories() async {
    final paths = <String>{};
    try {
      paths.add(await AppPaths.getIndexPath());
    } catch (e) {
      debugPrint('⚠️ Failed to resolve active index path: $e');
    }
    try {
      paths.addAll(await AppPaths.getStaleDefaultIndexPaths());
    } catch (e) {
      debugPrint('⚠️ Failed to resolve stale index paths: $e');
    }

    for (final path in paths) {
      final dir = Directory(path);
      if (!dir.existsSync()) continue;
      try {
        dir.deleteSync(recursive: true);
        debugPrint('🧹 נמחקה תיקיית אינדקס: $path');
      } catch (e) {
        debugPrint('⚠️ כשל במחיקת תיקיית אינדקס $path: $e');
      }
    }
  }

  /// Dispose of resources and close engines
  Future<void> dispose() async {
    try {
      final index = await engine;
      index.dispose();
    } catch (e) {
      debugPrint('⚠️ Error disposing search engine: $e');
    }
  }
}

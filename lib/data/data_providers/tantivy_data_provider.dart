import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:search_engine/search_engine.dart';
import 'package:hive/hive.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/core/app_paths.dart';

/// A singleton class that manages search functionality using Tantivy search engine.
///
/// This provider handles the search operations for both text-based and PDF books,
/// maintaining an index for full-text search capabilities.
class TantivyDataProvider {
  /// Instance of the search engine pointing to the index directory
  late Future<SearchEngine> engine;

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

  /// Maintains a list of processed books to avoid reindexing
  late List<String> booksDone = [];

  TantivyDataProvider._internal() {
    // Initialize engines
    engine = _initEngine();
    _loadBooksDone();
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

  Future<void> _loadBooksDone() async {
    try {
      String indexPath = await AppPaths.getIndexPath();
      booksDone = Hive.box(
        name: 'books_indexed',
        directory: indexPath,
      )
          .get('key-books-done', defaultValue: [])
          .map<String>((e) => e.toString())
          .toList();
    } catch (e) {
      booksDone = [];
    }
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
      // Dispose previous engine to release locks
      await dispose();

      // Reset engines
      engine = _initEngine();

      // Check engine
      engine.then((value) {
        try {
          // Test the search engine
          value
              .search(
                  regexTerms: ['a'],
                  limit: 10,
                  slop: 0,
                  maxExpansions: 10,
                  facets: ["/"],
                  order: ResultsOrder.catalogue)
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
    Hive.box(
      name: 'books_indexed',
      directory: await AppPaths.getIndexPath(),
    ).put('key-books-done', booksDone);
  }

  Future<int> countTexts(String query, List<String> books, List<String> facets,
      {bool fuzzy = false,
      int distance = 2,
      Map<String, String>? customSpacing,
      Map<int, List<String>>? alternativeWords,
      Map<String, Map<String, bool>>? searchOptions}) async {
    // Global cache check
    final cacheKey =
        '$query|${facets.join(',')}|$fuzzy|$distance|${customSpacing.toString()}|${alternativeWords.toString()}|${searchOptions.toString()}';

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
    final index = await engine;

    // המרת החיפוש לפורמט המנוע החדש - בדיוק כמו ב-SearchRepository!
    final params = SearchQueryBuilder.prepareQueryParams(
        query, fuzzy, distance, customSpacing, alternativeWords, searchOptions);
    final List<String> regexTerms = params['regexTerms'] as List<String>;
    final int effectiveSlop = params['effectiveSlop'] as int;
    final int maxExpansions = params['maxExpansions'] as int;

    try {
      final count = await index.count(
          regexTerms: regexTerms,
          facets: facets,
          slop: effectiveSlop,
          maxExpansions: maxExpansions);

      // Save to global cache
      _lastCachedQuery = query;
      _globalFacetCache[cacheKey] = count;
      _ongoingCounts.remove(cacheKey); // Mark as completed
      debugPrint('💾 GLOBAL CACHE SAVE for $facets: $count');

      return count;
    } catch (e) {
      // Remove from ongoing counts even on error
      _ongoingCounts.remove(cacheKey);
      // Log error in production
      rethrow;
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
        Hive.box(name: 'books_indexed', directory: indexPath).close();
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
    // הפונקציה הזו לא נתמכת במנוע החדש - נחזיר תוצאה חד-פעמית
    final searchRepository = SearchRepository();
    final results =
        await searchRepository.searchTexts(query, facets, limit, fuzzy: fuzzy);
    yield results;
  }

  /// ספירה מקבצת של תוצאות עבור מספר facets בבת אחת - לשיפור ביצועים
  Future<Map<String, int>> countTextsForMultipleFacets(
      String query, List<String> books, List<String> facets,
      {bool fuzzy = false,
      int distance = 2,
      Map<String, String>? customSpacing,
      Map<int, List<String>>? alternativeWords,
      Map<String, Map<String, bool>>? searchOptions,
      bool allowEarlyStop = true}) async {
    debugPrint(
        '🔍 TantivyDataProvider: Starting batch count for ${facets.length} facets');
    final stopwatch = Stopwatch()..start();

    final index = await engine;
    final results = <String, int>{};

    // המרת החיפוש לפורמט המנוע החדש - בדיוק כמו ב-countTexts
    final params = SearchQueryBuilder.prepareQueryParams(
        query, fuzzy, distance, customSpacing, alternativeWords, searchOptions);
    final List<String> regexTerms = params['regexTerms'] as List<String>;
    final int effectiveSlop = params['effectiveSlop'] as int;
    final int maxExpansions = params['maxExpansions'] as int;

    // ביצוע ספירה עבור כל facet - בזה אחר זה (לא במקביל כי זה לא עובד)
    int processedCount = 0;
    int zeroResultsCount = 0;

    for (final facet in facets) {
      try {
        debugPrint(
            '🔍 Counting facet: $facet (${processedCount + 1}/${facets.length})');
        final facetStopwatch = Stopwatch()..start();
        final count = await index.count(
            regexTerms: regexTerms,
            facets: [facet],
            slop: effectiveSlop,
            maxExpansions: maxExpansions);
        facetStopwatch.stop();
        debugPrint(
            '✅ Facet $facet: $count (${facetStopwatch.elapsedMilliseconds}ms)');
        results[facet] = count;

        processedCount++;
        if (count == 0) {
          zeroResultsCount++;
        }

        // אם יש יותר מדי facets עם 0 תוצאות, נפסיק מוקדם
        if (allowEarlyStop &&
            processedCount >= 10 &&
            zeroResultsCount > processedCount * 0.8) {
          debugPrint('⚠️ Too many zero results, stopping early');
          // נמלא את השאר עם 0
          for (int i = processedCount; i < facets.length; i++) {
            results[facets[i]] = 0;
          }
          break;
        }
      } catch (e) {
        debugPrint('❌ Error counting facet $facet: $e');
        results[facet] = 0;
        processedCount++;
        zeroResultsCount++;
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
  Future<void> clear() async {
    isIndexing.value = false;
    final index = await engine;
    await index.clear();
    booksDone.clear();
    await saveBooksDoneToDisk();
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

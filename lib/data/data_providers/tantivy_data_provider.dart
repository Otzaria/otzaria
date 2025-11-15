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
  late ReferenceSearchEngine refEngine;

  static final TantivyDataProvider _singleton = TantivyDataProvider();
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

  TantivyDataProvider() {
    _initializeEngines();
  }

  Future<void> _initializeEngines() async {
    String indexPath = await AppPaths.getIndexPath();
    String refIndexPath = await AppPaths.getRefIndexPath();

    engine = Future.value(SearchEngine(path: indexPath));

    try {
      refEngine = ReferenceSearchEngine(path: refIndexPath);
    } catch (e) {
      if (e.toString() ==
          "PanicException(Failed to create index: SchemaError(\"An index exists but the schema does not match.\"))") {
        resetIndex(indexPath);
        await _initializeEngines();
      } else {
        rethrow;
      }
    }
  }

  Future<void> reopenIndex() async {
    await _initializeEngines();

    // Initialize booksDone list
    try {
      final indexPath = await AppPaths.getIndexPath();
      final box = Hive.box(
        name: 'books_indexed',
        directory: indexPath,
      );
      booksDone = (box.get('key-books-done', defaultValue: []) as List)
          .map<String>((e) => e.toString())
          .toList();
    } catch (e) {
      debugPrint('⚠️ Error loading booksDone: $e');
      booksDone = [];
    }
  }

  /// Persists the list of indexed books to disk using Hive storage.
  Future<void> saveBooksDoneToDisk() async {
    try {
      final indexPath = await AppPaths.getIndexPath();
      final box = Hive.box(
        name: 'books_indexed',
        directory: indexPath,
      );
      box.put('key-books-done', booksDone);
    } catch (e) {
      debugPrint('⚠️ Error saving booksDone: $e');
    }
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

  Future<void> resetIndex(String indexPath) async {
    Directory indexDirectory = Directory(indexPath);
    Hive.box(name: 'books_indexed', directory: indexPath).close();
    indexDirectory.deleteSync(recursive: true);
    indexDirectory.createSync(recursive: true);
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

  Future<List<ReferenceSearchResult>> searchRefs(
      String reference, int limit, bool fuzzy) async {
    return refEngine.search(
        query: reference,
        limit: limit,
        fuzzy: fuzzy,
        order: ResultsOrder.relevance);
  }

  /// ספירה מקבצת של תוצאות עבור מספר facets בבת אחת - לשיפור ביצועים
  Future<Map<String, int>> countTextsForMultipleFacets(
      String query, List<String> books, List<String> facets,
      {bool fuzzy = false,
      int distance = 2,
      Map<String, String>? customSpacing,
      Map<int, List<String>>? alternativeWords,
      Map<String, Map<String, bool>>? searchOptions}) async {
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
        if (processedCount >= 10 && zeroResultsCount > processedCount * 0.8) {
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
    final refIndex = refEngine;
    await refIndex.clear();
    booksDone.clear();
    await saveBooksDoneToDisk();
  }
}

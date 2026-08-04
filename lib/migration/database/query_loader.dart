import 'package:flutter/services.dart' show rootBundle;

/// Utility class to load and parse SQL query files (.sq)
class QueryLoader {
  static final Map<String, Map<String, String>> _queryCache = {};
  static bool _initialized = false;

  /// Returns a snapshot of the loaded cache for transport to another isolate.
  /// Call [initialize] first on the source isolate.
  static Map<String, Map<String, String>> get cacheSnapshot => Map.fromEntries(
    _queryCache.entries.map(
      (e) => MapEntry(e.key, Map<String, String>.from(e.value)),
    ),
  );

  /// Seeds the cache from a snapshot received from another isolate.
  /// After this call [initialize] is a no-op; no [rootBundle] access needed.
  static void seedCache(Map<String, Map<String, String>> snapshot) {
    _queryCache.addAll(snapshot);
    _initialized = true;
  }

  /// Initialize the query loader by preloading all query files
  /// Must be called before using loadQueries
  static Future<void> initialize() async {
    if (_initialized) return;

    final queryFiles = [
      'AcronymQueries.sq',
      'AuthorQueries.sq',
      'BookHasLinksQueries.sq',
      'BookQueries.sq',
      'CategoryClosureQueries.sq',
      'CategoryQueries.sq',
      'ConnectionTypeQueries.sq',
      'Database.sq',
      'DocxTextCacheQueries.sq',
      'GenerationQueries.sq',
      'LineQueries.sq',
      'LineTocQueries.sq',
      'LinkQueries.sq',
      'PdfAnchorCacheQueries.sq',
      'PdfOutlineCacheQueries.sq',
      'PubDateQueries.sq',
      'PubPlaceQueries.sq',
      'SearchQueries.sq',
      'SourceQueries.sq',
      'TocQueries.sq',
      'TocTextQueries.sq',
      'TopicQueries.sq',
    ];

    for (final fileName in queryFiles) {
      await _loadQueryFile(fileName);
    }
    _initialized = true;
  }

  /// Load a single query file from assets
  static Future<void> _loadQueryFile(String fileName) async {
    final assetPath = 'lib/migration/database/sql/$fileName';
    try {
      final content = await rootBundle.loadString(assetPath);
      final queries = _parseQueries(content);
      _queryCache[fileName] = queries;
    } catch (e) {
      throw Exception('Query file not found: $assetPath - $e');
    }
  }

  /// Load queries from a .sq file (synchronous, requires initialize() to be called first)
  static Map<String, String> loadQueries(String fileName) {
    if (!_initialized) {
      throw StateError(
        'QueryLoader not initialized. Call QueryLoader.initialize() first.',
      );
    }

    final queries = _queryCache[fileName];
    if (queries == null) {
      throw Exception('Query file not found in cache: $fileName');
    }
    return queries;
  }

  /// Parse the content of a .sq file into a map of query names to SQL
  static Map<String, String> _parseQueries(String content) {
    final queries = <String, String>{};
    final lines = content.split('\n');

    String? currentQueryName;
    final queryBuffer = StringBuffer();

    for (final line in lines) {
      final trimmedLine = line.trim();

      // Skip empty lines and comments
      if (trimmedLine.isEmpty || trimmedLine.startsWith('--')) {
        continue;
      }

      // Check if this is a query name (ends with ':')
      if (trimmedLine.endsWith(':')) {
        // Save previous query if exists
        if (currentQueryName != null && queryBuffer.isNotEmpty) {
          queries[currentQueryName] = queryBuffer.toString().trim();
          queryBuffer.clear();
        }

        // Start new query
        currentQueryName = trimmedLine.substring(0, trimmedLine.length - 1);
      } else if (currentQueryName != null) {
        // Add line to current query
        if (queryBuffer.isNotEmpty) {
          queryBuffer.write('\n');
        }
        queryBuffer.write(line);
      }
    }

    // Save the last query
    if (currentQueryName != null && queryBuffer.isNotEmpty) {
      queries[currentQueryName] = queryBuffer.toString().trim();
    }

    return queries;
  }

  /// Get a specific query by name from a .sq file
  static String getQuery(String fileName, String queryName) {
    final queries = loadQueries(fileName);
    final query = queries[queryName];
    if (query == null) {
      throw ArgumentError('Query "$queryName" not found in $fileName');
    }
    return query;
  }
}

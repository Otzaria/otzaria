import 'dart:collection';

/// Service for caching markdown to HTML conversions and overrides
class EditorCacheService {
  static final EditorCacheService _instance = EditorCacheService._internal();
  factory EditorCacheService() => _instance;
  EditorCacheService._internal();

  // Cache for markdown to HTML conversions
  final Map<String, String> _markdownCache = {};
  final LinkedHashMap<String, String> _overrideCache = LinkedHashMap();

  static const int _maxCacheSize = 100;
  static const int _maxOverrideCacheSize = 50;

  /// Generates cache key from bookId, sectionId, and contentHash
  String _generateCacheKey(
      String bookId, String sectionId, String contentHash) {
    return '${bookId}_${sectionId}_$contentHash';
  }

  /// Caches markdown to HTML conversion
  void cacheMarkdownHtml(
      String bookId, String sectionId, String contentHash, String html) {
    final key = _generateCacheKey(bookId, sectionId, contentHash);

    // Remove oldest entries if cache is full
    if (_markdownCache.length >= _maxCacheSize) {
      final oldestKey = _markdownCache.keys.first;
      _markdownCache.remove(oldestKey);
    }

    _markdownCache[key] = html;
  }

  /// Gets cached HTML for markdown conversion
  String? getCachedMarkdownHtml(
      String bookId, String sectionId, String contentHash) {
    final key = _generateCacheKey(bookId, sectionId, contentHash);
    return _markdownCache[key];
  }

  /// Caches override content
  void cacheOverride(String bookId, String sectionId, String content) {
    final key = '${bookId}_$sectionId';

    // Remove oldest entries if cache is full (LRU)
    if (_overrideCache.length >= _maxOverrideCacheSize) {
      final oldestKey = _overrideCache.keys.first;
      _overrideCache.remove(oldestKey);
    }

    _overrideCache[key] = content;
  }

  /// Gets cached override content
  String? getCachedOverride(String bookId, String sectionId) {
    final key = '${bookId}_$sectionId';
    final content = _overrideCache.remove(key);
    if (content != null) {
      // Move to end (most recently used)
      _overrideCache[key] = content;
    }
    return content;
  }

  /// Invalidates cache for a specific section
  void invalidateSection(String bookId, String sectionId) {
    final overrideKey = '${bookId}_$sectionId';
    _overrideCache.remove(overrideKey);

    // Remove all markdown cache entries for this section
    final keysToRemove = _markdownCache.keys
        .where((key) => key.startsWith('${bookId}_$sectionId'))
        .toList();

    for (final key in keysToRemove) {
      _markdownCache.remove(key);
    }
  }

  /// Clears all caches
  void clearAll() {
    _markdownCache.clear();
    _overrideCache.clear();
  }

  /// Clears caches for a specific book
  void clearBook(String bookId) {
    // Remove override cache entries
    final overrideKeysToRemove = _overrideCache.keys
        .where((key) => key.startsWith('${bookId}_'))
        .toList();

    for (final key in overrideKeysToRemove) {
      _overrideCache.remove(key);
    }

    // Remove markdown cache entries
    final markdownKeysToRemove = _markdownCache.keys
        .where((key) => key.startsWith('${bookId}_'))
        .toList();

    for (final key in markdownKeysToRemove) {
      _markdownCache.remove(key);
    }
  }

  /// Gets cache statistics
  Map<String, int> getCacheStats() {
    return {
      'markdownCacheSize': _markdownCache.length,
      'overrideCacheSize': _overrideCache.length,
      'maxMarkdownCacheSize': _maxCacheSize,
      'maxOverrideCacheSize': _maxOverrideCacheSize,
    };
  }
}

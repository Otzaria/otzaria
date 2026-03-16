import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';

/// In-memory cache for the `book_acronym` table.
///
/// This cache is used exclusively by the FindRef feature for matching
/// book acronyms during reference searches.
class AcronymsCache {
  AcronymsCache._();

  static final AcronymsCache instance = AcronymsCache._();

  bool _isLoaded = false;
  Future<void>? _loadingFuture;

  final Map<int, List<String>> _acronymsByBookId = <int, List<String>>{};

  bool get isLoaded => _isLoaded;

  /// Returns all acronyms for a given book ID
  List<String>? getAcronymsForBook(int bookId) => _acronymsByBookId[bookId];

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
    final repository = SqliteDataProvider.instance.repository;
    if (repository == null) {
      debugPrint('[AcronymsCache] DB not initialized; skipping warmup');
      _acronymsByBookId.clear();
      _isLoaded = false;
      return;
    }

    try {
      final db = await repository.database.database;
      final acrRows = db.select(
        'SELECT bookId, term FROM book_acronym ORDER BY bookId',
      );

      _acronymsByBookId.clear();
      for (final row in acrRows) {
        final bookId = row['bookId'] as int;
        final term = (row['term'] as String?) ?? '';
        if (term.isEmpty) continue;
        _acronymsByBookId.putIfAbsent(bookId, () => <String>[]).add(term);
      }

      _isLoaded = true;
      debugPrint(
        '[AcronymsCache] Loaded ${acrRows.length} acronyms for ${_acronymsByBookId.length} books',
      );
    } catch (e) {
      debugPrint('[AcronymsCache] Warmup failed: $e');
      _acronymsByBookId.clear();
      _isLoaded = true; // Mark as loaded to avoid repeated attempts
    }
  }

  void clear() {
    _acronymsByBookId.clear();
    _isLoaded = false;
    _loadingFuture = null;
  }
}

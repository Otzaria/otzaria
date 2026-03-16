import 'package:sqlite3/sqlite3.dart' as sqlite3;
import '../../core/models/search_result.dart';
import '../sqflite/sqlite3_utils.dart';
import '../sqflite/query_loader.dart';
import 'database.dart';

class SearchDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  SearchDao(this._db) {
    _queries = QueryLoader.loadQueries('SearchQueries.sq');
  }

  Future<sqlite3.Database> get database => _db.database;

  Future<List<SearchResult>> searchAll(String query,
      {int limit = 20, int offset = 0}) async {
    final db = await database;
    return db
        .select(_queries['searchAll']!, [query, limit, offset])
        .toMapList()
        .map((row) => _mapToSearchResult(row))
        .toList();
  }

  Future<List<SearchResult>> searchInBook(String query, int bookId,
      {int limit = 20, int offset = 0}) async {
    final db = await database;
    return db
        .select(_queries['searchInBook']!, [query, bookId, limit, offset])
        .toMapList()
        .map((row) => _mapToSearchResult(row))
        .toList();
  }

  Future<List<SearchResult>> searchByAuthor(String query, String authorName,
      {int limit = 20, int offset = 0}) async {
    final db = await database;
    return db
        .select(_queries['searchByAuthor']!, [query, authorName, limit, offset])
        .toMapList()
        .map((row) => _mapToSearchResult(row))
        .toList();
  }

  Future<List<SearchResult>> searchWithBookFilter(
      String query, String bookTitleFilter,
      {int limit = 20, int offset = 0}) async {
    final db = await database;
    return db
        .select(_queries['searchWithBookFilter']!,
            [query, bookTitleFilter, limit, offset])
        .toMapList()
        .map((row) => _mapToSearchResult(row))
        .toList();
  }

  Future<List<SearchResult>> searchExactPhrase(String query,
      {int limit = 20, int offset = 0}) async {
    final db = await database;
    return db
        .select(_queries['searchExactPhrase']!, [query, limit, offset])
        .toMapList()
        .map((row) => _mapToSearchResult(row))
        .toList();
  }

  Future<List<SearchResult>> searchWithOperators(String query,
      {int limit = 20, int offset = 0}) async {
    final db = await database;
    return db
        .select(_queries['searchWithOperators']!, [query, limit, offset])
        .toMapList()
        .map((row) => _mapToSearchResult(row))
        .toList();
  }

  Future<int> countSearchResults(String query) async {
    final db = await database;
    return firstIntValue(db.select(_queries['countSearchResults']!, [query])) ??
        0;
  }

  Future<int> countSearchResultsInBook(String query, int bookId) async {
    final db = await database;
    return firstIntValue(db
            .select(_queries['countSearchResultsInBook']!, [query, bookId])) ??
        0;
  }

  Future<void> rebuildFts5Index() async {
    final db = await database;
    db.execute(_queries['rebuildFts5Index']!);
  }

  SearchResult _mapToSearchResult(Map<String, dynamic> map) {
    return SearchResult(
      bookId: map['bookId'] as int,
      bookTitle: map['bookTitle'] as String,
      lineId: map['id'] as int, // The query returns 'id' as lineId
      lineIndex: map['lineIndex'] as int,
      snippet: map['snippet'] as String,
      rank: (map['rank'] as num).toDouble(),
    );
  }
}

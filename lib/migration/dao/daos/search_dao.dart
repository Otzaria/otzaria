import 'package:sqflite/sqflite.dart';
import '../../core/models/search_result.dart';
import '../sqflite/query_loader.dart';
import 'database.dart';

class SearchDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  SearchDao(this._db) {
    _queries = QueryLoader.loadQueries('SearchQueries.sq');
  }

  Future<Database> get database => _db.database;

  Future<List<SearchResult>> searchAll(String query,
      {int limit = 20, int offset = 0}) async {
    final db = await database;
    final result =
        await db.rawQuery(_queries['searchAll']!, [query, limit, offset]);
    return result.map((row) => _mapToSearchResult(row)).toList();
  }

  Future<List<SearchResult>> searchInBook(String query, int bookId,
      {int limit = 20, int offset = 0}) async {
    final db = await database;
    final result = await db
        .rawQuery(_queries['searchInBook']!, [query, bookId, limit, offset]);
    return result.map((row) => _mapToSearchResult(row)).toList();
  }

  Future<List<SearchResult>> searchByAuthor(String query, String authorName,
      {int limit = 20, int offset = 0}) async {
    final db = await database;
    final result = await db.rawQuery(
        _queries['searchByAuthor']!, [query, authorName, limit, offset]);
    return result.map((row) => _mapToSearchResult(row)).toList();
  }

  Future<List<SearchResult>> searchWithBookFilter(
      String query, String bookTitleFilter,
      {int limit = 20, int offset = 0}) async {
    final db = await database;
    final result = await db.rawQuery(_queries['searchWithBookFilter']!,
        [query, bookTitleFilter, limit, offset]);
    return result.map((row) => _mapToSearchResult(row)).toList();
  }

  Future<List<SearchResult>> searchExactPhrase(String query,
      {int limit = 20, int offset = 0}) async {
    final db = await database;
    final result = await db
        .rawQuery(_queries['searchExactPhrase']!, [query, limit, offset]);
    return result.map((row) => _mapToSearchResult(row)).toList();
  }

  Future<List<SearchResult>> searchWithOperators(String query,
      {int limit = 20, int offset = 0}) async {
    final db = await database;
    final result = await db
        .rawQuery(_queries['searchWithOperators']!, [query, limit, offset]);
    return result.map((row) => _mapToSearchResult(row)).toList();
  }

  Future<int> countSearchResults(String query) async {
    final db = await database;
    final result = await db.rawQuery(_queries['countSearchResults']!, [query]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> countSearchResultsInBook(String query, int bookId) async {
    final db = await database;
    final result = await db
        .rawQuery(_queries['countSearchResultsInBook']!, [query, bookId]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> rebuildFts5Index() async {
    final db = await database;
    await db.rawQuery(_queries['rebuildFts5Index']!);
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

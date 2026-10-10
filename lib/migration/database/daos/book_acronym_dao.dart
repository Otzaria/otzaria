import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import '../query_loader.dart';
import '../sqlite3_utils.dart';
import 'database.dart';

class BookAcronymDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  BookAcronymDao(this._db) {
    _queries = QueryLoader.loadQueries('AcronymQueries.sq');
  }

  Future<sqlite3.Database> get database => _db.database;

  /// Gets all book IDs that have acronym terms matching the pattern (LIKE search)
  Future<List<int>> getBookIdsByTermLike(String pattern, {int? limit}) async {
    final db = await database;
    return db
        .select(_queries['selectBookIdsByTermLike']!, [pattern, limit ?? 1000])
        .toMapList()
        .map((row) => row['bookId'] as int)
        .toList();
  }

  /// Deletes all acronyms for a specific book
  Future<void> deleteByBookId(int bookId) async {
    final db = await database;
    db.execute(_queries['deleteByBookId']!, [bookId]);
  }

  /// Counts the number of acronym terms for a specific book
  Future<int> countByBookId(int bookId) async {
    final db = await database;
    return firstIntValue(db.select(_queries['countByBookId']!, [bookId])) ?? 0;
  }

  /// Searches for books by acronym term with LIKE pattern
  Future<List<int>> searchBooksByAcronym(
    String searchTerm, {
    int? limit,
  }) async {
    return await getBookIdsByTermLike('%$searchTerm%', limit: limit);
  }
}

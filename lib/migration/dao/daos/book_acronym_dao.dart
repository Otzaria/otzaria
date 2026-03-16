import 'package:sqlite3/sqlite3.dart' as sqlite3;
import '../sqflite/query_loader.dart';
import '../sqflite/sqlite3_utils.dart';
import 'database.dart';

class BookAcronymDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  BookAcronymDao(this._db) {
    _queries = QueryLoader.loadQueries('AcronymQueries.sq');
  }

  Future<sqlite3.Database> get database => _db.database;

  /// Gets all acronym terms for a specific book
  Future<List<String>> getTermsByBookId(int bookId) async {
    final db = await database;
    return db
        .select(_queries['selectTermsByBookId']!, [bookId])
        .toMapList()
        .map((row) => row['term'] as String)
        .toList();
  }

  /// Gets all acronym records for a specific book
  Future<List<Map<String, dynamic>>> getByBookId(int bookId) async {
    final db = await database;
    return db.select(_queries['selectByBookId']!, [bookId]).toMapList();
  }

  /// Gets all book IDs that have a specific acronym term (exact match)
  Future<List<int>> getBookIdsByTerm(String term) async {
    final db = await database;
    return db
        .select(_queries['selectBookIdsByTerm']!, [term])
        .toMapList()
        .map((row) => row['bookId'] as int)
        .toList();
  }

  /// Gets all book IDs that have acronym terms matching the pattern (LIKE search)
  Future<List<int>> getBookIdsByTermLike(String pattern, {int? limit}) async {
    final db = await database;
    return db
        .select(_queries['selectBookIdsByTermLike']!, [pattern, limit ?? 1000])
        .toMapList()
        .map((row) => row['bookId'] as int)
        .toList();
  }

  /// Inserts a single acronym term for a book
  /// Uses ON CONFLICT DO NOTHING to avoid duplicates
  Future<void> insertAcronym(int bookId, String term) async {
    final db = await database;
    db.execute(_queries['insert']!, [bookId, term]);
  }

  /// Bulk inserts multiple acronym terms for a book
  Future<void> bulkInsertAcronyms(int bookId, List<String> terms) async {
    if (terms.isEmpty) return;
    final db = await database;
    withTransaction(db, () {
      for (final term in terms) {
        db.execute(_queries['insert']!, [bookId, term]);
      }
    });
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
  Future<List<int>> searchBooksByAcronym(String searchTerm,
      {int? limit}) async {
    return await getBookIdsByTermLike('%$searchTerm%', limit: limit);
  }
}

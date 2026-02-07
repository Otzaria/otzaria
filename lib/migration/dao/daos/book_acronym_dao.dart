import 'package:sqflite/sqflite.dart';
import '../sqflite/query_loader.dart';
import 'database.dart';

class BookAcronymDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  BookAcronymDao(this._db) {
    _queries = QueryLoader.loadQueries('AcronymQueries.sq');
  }

  Future<Database> get database => _db.database;

  /// Gets all acronym terms for a specific book
  Future<List<String>> getTermsByBookId(int bookId) async {
    final db = await database;
    final result =
        await db.rawQuery(_queries['selectTermsByBookId']!, [bookId]);
    return result.map((row) => row['term'] as String).toList();
  }

  /// Gets all acronym records for a specific book
  Future<List<Map<String, dynamic>>> getByBookId(int bookId) async {
    final db = await database;
    return await db.rawQuery(_queries['selectByBookId']!, [bookId]);
  }

  /// Gets all book IDs that have a specific acronym term (exact match)
  Future<List<int>> getBookIdsByTerm(String term) async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectBookIdsByTerm']!, [term]);
    return result.map((row) => row['bookId'] as int).toList();
  }

  /// Gets all book IDs that have acronym terms matching the pattern (LIKE search)
  Future<List<int>> getBookIdsByTermLike(String pattern, {int? limit}) async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectBookIdsByTermLike']!,
        [pattern, limit ?? 1000] // Default limit of 1000 if not specified
        );
    return result.map((row) => row['bookId'] as int).toList();
  }

  /// Inserts a single acronym term for a book
  /// Uses ON CONFLICT DO NOTHING to avoid duplicates
  Future<void> insertAcronym(int bookId, String term) async {
    final db = await database;
    await db.rawInsert(_queries['insert']!, [bookId, term]);
  }

  /// Bulk inserts multiple acronym terms for a book
  Future<void> bulkInsertAcronyms(int bookId, List<String> terms) async {
    if (terms.isEmpty) return;

    final db = await database;
    final batch = db.batch();

    for (final term in terms) {
      batch.rawInsert(_queries['insert']!, [bookId, term]);
    }

    await batch.commit(noResult: true);
  }

  /// Deletes all acronyms for a specific book
  Future<void> deleteByBookId(int bookId) async {
    final db = await database;
    await db.rawDelete(_queries['deleteByBookId']!, [bookId]);
  }

  /// Counts the number of acronym terms for a specific book
  Future<int> countByBookId(int bookId) async {
    final db = await database;
    final result = await db.rawQuery(_queries['countByBookId']!, [bookId]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Searches for books by acronym term with LIKE pattern
  Future<List<int>> searchBooksByAcronym(String searchTerm,
      {int? limit}) async {
    return await getBookIdsByTermLike('%$searchTerm%', limit: limit);
  }
}

import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import '../../models/author.dart';
import '../sqlite3_utils.dart';
import '../query_loader.dart';
import 'database.dart';

class AuthorDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  AuthorDao(this._db) {
    _queries = QueryLoader.loadQueries('AuthorQueries.sq');
  }

  Future<sqlite3.Database> get database => _db.database;

  Future<Author?> getAuthorByName(String name) async {
    final db = await database;
    final result = db.select(_queries['selectByName']!, [name]).toMapList();
    if (result.isEmpty) return null;
    return Author.fromMap(result.first);
  }

  Future<int> insertAuthor(String name) async {
    final db = await database;
    db.execute(_queries['insert']!, [name]);
    return db.lastInsertRowId;
  }

  Future<int?> getAuthorIdByName(String name) async {
    final db = await database;
    final result = db.select(_queries['selectIdByName']!, [name]).toMapList();
    if (result.isEmpty) return null;
    return result.first['id'] as int;
  }

  // Junction table operations
  Future<int> linkBookAuthor(int bookId, int authorId) async {
    final db = await database;
    db.execute(_queries['linkBookAuthor']!, [bookId, authorId]);
    return db.lastInsertRowId;
  }

  Future<int> unlinkBookAuthor(int bookId, int authorId) async {
    final db = await database;
    db.execute(_queries['unlinkBookAuthor']!, [bookId, authorId]);
    return db.updatedRows;
  }

  Future<int> deleteAllBookAuthors(int bookId) async {
    final db = await database;
    db.execute(_queries['deleteAllBookAuthors']!, [bookId]);
    return db.updatedRows;
  }

  Future<int> countBookAuthors(int bookId) async {
    final db = await database;
    return firstIntValue(db.select(_queries['countBookAuthors']!, [bookId])) ??
        0;
  }

  /// מחזירה מיפוי title ← שם תקופה לכל הספרים שיש להם מחבר עם תקופה ידועה
  Future<Map<String, String>> getAllBookTitleToGeneration() async {
    if (!(await _db.capabilities).hasGenerations) return {};
    final db = await database;
    final rows = db
        .select(_queries['selectAllBookTitleToGeneration']!)
        .toMapList();
    final result = <String, String>{};
    for (final row in rows) {
      final title = row['title'] as String?;
      final gen = row['generationName'] as String?;
      if (title != null && gen != null) {
        result[title] = gen;
      }
    }
    return result;
  }
}

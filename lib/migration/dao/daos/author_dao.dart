import 'package:sqlite3/sqlite3.dart' as sqlite3;
import '../../core/models/author.dart';
import '../sqflite/sqlite3_utils.dart';
import '../sqflite/query_loader.dart';
import 'database.dart';

class AuthorDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  AuthorDao(this._db) {
    _queries = QueryLoader.loadQueries('AuthorQueries.sq');
  }

  Future<sqlite3.Database> get database => _db.database;

  Future<List<Author>> getAllAuthors() async {
    final db = await database;
    return db.select(_queries['selectAll']!).toMapList()
        .map((row) => Author.fromMap(row)).toList();
  }

  Future<Author?> getAuthorById(int id) async {
    final db = await database;
    final result = db.select(_queries['selectById']!, [id]).toMapList();
    if (result.isEmpty) return null;
    return Author.fromMap(result.first);
  }

  Future<Author?> getAuthorByName(String name) async {
    final db = await database;
    final result = db.select(_queries['selectByName']!, [name]).toMapList();
    if (result.isEmpty) return null;
    return Author.fromMap(result.first);
  }

  Future<List<Author>> getAuthorsByBookId(int bookId) async {
    final db = await database;
    return db.select(_queries['selectByBookId']!, [bookId]).toMapList()
        .map((row) => Author.fromMap(row)).toList();
  }

  Future<int> insertAuthor(String name) async {
    final db = await database;
    db.execute(_queries['insert']!, [name]);
    return db.lastInsertRowId;
  }

  Future<int> insertAuthorAndGetId(String name) async {
    final db = await database;
    db.execute(_queries['insertAndGetId']!, [name]);
    return db.lastInsertRowId;
  }

  Future<int?> getAuthorIdByName(String name) async {
    final db = await database;
    final result = db.select(_queries['selectIdByName']!, [name]).toMapList();
    if (result.isEmpty) return null;
    return result.first['id'] as int;
  }

  Future<int> deleteAuthor(int id) async {
    final db = await database;
    db.execute(_queries['delete']!, [id]);
    return db.updatedRows;
  }

  Future<int> countAllAuthors() async {
    final db = await database;
    return firstIntValue(db.select(_queries['countAll']!)) ?? 0;
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
    return firstIntValue(db.select(_queries['countBookAuthors']!, [bookId])) ?? 0;
  }
}

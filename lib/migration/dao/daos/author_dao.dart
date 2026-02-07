import 'package:sqflite/sqflite.dart';
import '../../core/models/author.dart';
import '../sqflite/query_loader.dart';
import 'database.dart';

class AuthorDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  AuthorDao(this._db) {
    _queries = QueryLoader.loadQueries('AuthorQueries.sq');
  }

  Future<Database> get database => _db.database;

  Future<List<Author>> getAllAuthors() async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectAll']!);
    return result.map((row) => Author.fromMap(row)).toList();
  }

  Future<Author?> getAuthorById(int id) async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectById']!, [id]);
    if (result.isEmpty) return null;
    return Author.fromMap(result.first);
  }

  Future<Author?> getAuthorByName(String name) async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectByName']!, [name]);
    if (result.isEmpty) return null;
    return Author.fromMap(result.first);
  }

  Future<List<Author>> getAuthorsByBookId(int bookId) async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectByBookId']!, [bookId]);
    return result.map((row) => Author.fromMap(row)).toList();
  }

  Future<int> insertAuthor(String name) async {
    final db = await database;
    return await db.rawInsert(_queries['insert']!, [name]);
  }

  Future<int> insertAuthorAndGetId(String name) async {
    final db = await database;
    await db.rawInsert(_queries['insertAndGetId']!, [name]);
    final result = await db.rawQuery(_queries['lastInsertRowId']!);
    return result.first.values.first as int;
  }

  Future<int?> getAuthorIdByName(String name) async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectIdByName']!, [name]);
    if (result.isEmpty) return null;
    return result.first['id'] as int;
  }

  Future<int> deleteAuthor(int id) async {
    final db = await database;
    return await db.rawDelete(_queries['delete']!, [id]);
  }

  Future<int> countAllAuthors() async {
    final db = await database;
    final result = await db.rawQuery(_queries['countAll']!);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // Junction table operations
  Future<int> linkBookAuthor(int bookId, int authorId) async {
    final db = await database;
    return await db.rawInsert(_queries['linkBookAuthor']!, [bookId, authorId]);
  }

  Future<int> unlinkBookAuthor(int bookId, int authorId) async {
    final db = await database;
    return await db
        .rawDelete(_queries['unlinkBookAuthor']!, [bookId, authorId]);
  }

  Future<int> deleteAllBookAuthors(int bookId) async {
    final db = await database;
    return await db.rawDelete(_queries['deleteAllBookAuthors']!, [bookId]);
  }

  Future<int> countBookAuthors(int bookId) async {
    final db = await database;
    final result = await db.rawQuery(_queries['countBookAuthors']!, [bookId]);
    return Sqflite.firstIntValue(result) ?? 0;
  }
}

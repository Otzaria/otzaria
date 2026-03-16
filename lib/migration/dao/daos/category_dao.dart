import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import '../sqflite/sqlite3_utils.dart';
import '../../core/models/category.dart';
import '../sqflite/query_loader.dart';
import 'database.dart';

class CategoryDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  CategoryDao(this._db) {
    _queries = QueryLoader.loadQueries('CategoryQueries.sq');
  }

  Future<sqlite3.Database> get database => _db.database;

  Future<List<Category>> getAllCategories() async {
    final db = await database;
    final categories = db
        .select(_queries['selectAll']!)
        .toMapList()
        .map((row) => Category.fromJson(row))
        .toList();

    // Filter out special categories (except in debug mode)
    if (!kDebugMode) {
      return categories
          .where((cat) => cat.title != 'ספרים מספריות חיצוניות')
          .toList();
    }
    return categories;
  }

  /// Gets all category rows, optionally within an ongoing transaction.
  /// Used by [DatabaseLibraryProvider] to load books and categories atomically.
  /// Must be called synchronously inside a [withTransaction] block.
  List<Map<String, dynamic>> getAllCategoryRows(
      sqlite3.Database db) {
    return db
        .select('SELECT * FROM category ORDER BY orderIndex, title')
        .toMapList();
  }

  Future<Category?> getCategoryById(int id) async {
    final db = await database;
    final result = db.select(_queries['selectById']!, [id]).toMapList();
    if (result.isEmpty) return null;
    return Category.fromJson(result.first);
  }

  Future<List<Category>> getRootCategories() async {
    final db = await database;
    final categories = db
        .select(_queries['selectRoot']!)
        .toMapList()
        .map((row) => Category.fromJson(row))
        .toList();

    // Filter out special categories (except in debug mode)
    if (!kDebugMode) {
      return categories
          .where((cat) => cat.title != 'ספרים מספריות חיצוניות')
          .toList();
    }
    return categories;
  }

  Future<List<Category>> getCategoriesByParentId(int parentId) async {
    final db = await database;
    return db
        .select(_queries['selectByParentId']!, [parentId])
        .toMapList()
        .map((row) => Category.fromJson(row))
        .toList();
  }

  Future<int> insertCategory(int? parentId, String title, int level,
      {int orderIndex = 999}) async {
    final db = await database;
    db.execute(_queries['insert']!, [parentId, title, level, orderIndex]);
    return db.lastInsertRowId;
  }

  Future<int> insertCategoryWithId(
      int id, int? parentId, String title, int level,
      {int orderIndex = 999}) async {
    final db = await database;
    db.execute(
        _queries['insertWithId']!, [id, parentId, title, level, orderIndex]);
    return db.lastInsertRowId;
  }

  Future<int> insertCategoryAndGetId(int? parentId, String title, int level,
      {int orderIndex = 999}) async {
    final db = await database;
    db.execute(_queries['insert']!, [parentId, title, level, orderIndex]);
    return db.lastInsertRowId;
  }

  Future<int> updateCategory(int id, String title, {int? orderIndex}) async {
    final db = await database;
    db.execute(_queries['update']!, [title, orderIndex ?? 999, id]);
    return db.updatedRows;
  }

  Future<int> updateCategoryOrderIndex(int id, int orderIndex) async {
    final db = await database;
    db.execute(_queries['updateOrderIndex']!, [orderIndex, id]);
    return db.updatedRows;
  }

  Future<int> deleteCategory(int id) async {
    final db = await database;
    db.execute(_queries['delete']!, [id]);
    return db.updatedRows;
  }

  Future<int> countAllCategories() async {
    final db = await database;
    return firstIntValue(db.select(_queries['countAll']!)) ?? 0;
  }

  /// Gets a category by its title.
  Future<Category?> getCategoryByTitle(String title) async {
    final db = await database;
    final result = db.select(_queries['selectByTitle']!, [title]).toMapList();
    if (result.isEmpty) return null;
    return Category.fromJson(result.first);
  }

  /// Gets a category by its title and parent ID.
  Future<Category?> getCategoryByTitleAndParent(
      String title, int? parentId) async {
    final db = await database;
    final result = db.select(
      _queries['selectByTitleAndParent']!,
      [title, parentId, parentId],
    ).toMapList();
    if (result.isEmpty) return null;
    return Category.fromJson(result.first);
  }
}


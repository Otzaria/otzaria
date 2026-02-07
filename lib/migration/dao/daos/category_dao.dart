import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:sqflite/sqflite.dart';
import '../../core/models/category.dart';
import '../sqflite/query_loader.dart';
import 'database.dart';

class CategoryDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  CategoryDao(this._db) {
    _queries = QueryLoader.loadQueries('CategoryQueries.sq');
  }

  Future<Database> get database => _db.database;

  Future<List<Category>> getAllCategories() async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectAll']!);
    final categories = result.map((row) => Category.fromJson(row)).toList();

    // Filter out special categories (except in debug mode)
    if (!kDebugMode) {
      return categories.where((cat) => cat.title != 'אודות התוכנה').toList();
    }
    return categories;
  }

  Future<Category?> getCategoryById(int id) async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectById']!, [id]);
    if (result.isEmpty) return null;
    return Category.fromJson(result.first);
  }

  Future<List<Category>> getRootCategories() async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectRoot']!);
    final categories = result.map((row) => Category.fromJson(row)).toList();

    // Filter out special categories (except in debug mode)
    if (!kDebugMode) {
      return categories.where((cat) => cat.title != 'אודות התוכנה').toList();
    }
    return categories;
  }

  Future<List<Category>> getCategoriesByParentId(int parentId) async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectByParentId']!, [parentId]);
    return result.map((row) => Category.fromJson(row)).toList();
  }

  Future<int> insertCategory(int? parentId, String title, int level,
      {int orderIndex = 999}) async {
    final db = await database;
    return await db
        .rawInsert(_queries['insert']!, [parentId, title, level, orderIndex]);
  }

  Future<int> insertCategoryWithId(
      int id, int? parentId, String title, int level,
      {int orderIndex = 999}) async {
    final db = await database;
    return await db.rawInsert(
        _queries['insertWithId']!, [id, parentId, title, level, orderIndex]);
  }

  Future<int> insertCategoryAndGetId(int? parentId, String title, int level,
      {int orderIndex = 999}) async {
    final db = await database;
    await db
        .rawInsert(_queries['insert']!, [parentId, title, level, orderIndex]);
    final result = await db.rawQuery(_queries['lastInsertRowId']!);
    return result.first.values.first as int;
  }

  Future<int> updateCategory(int id, String title, {int? orderIndex}) async {
    final db = await database;
    return await db
        .rawUpdate(_queries['update']!, [title, orderIndex ?? 999, id]);
  }

  Future<int> updateCategoryOrderIndex(int id, int orderIndex) async {
    final db = await database;
    return await db.rawUpdate(_queries['updateOrderIndex']!, [orderIndex, id]);
  }

  Future<int> deleteCategory(int id) async {
    final db = await database;
    return await db.rawDelete(_queries['delete']!, [id]);
  }

  Future<int> countAllCategories() async {
    final db = await database;
    final result = await db.rawQuery(_queries['countAll']!);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Gets a category by its title.
  Future<Category?> getCategoryByTitle(String title) async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectByTitle']!, [title]);
    if (result.isEmpty) return null;
    return Category.fromJson(result.first);
  }

  /// Gets a category by its title and parent ID.
  Future<Category?> getCategoryByTitleAndParent(
      String title, int? parentId) async {
    final db = await database;
    final result = await db.rawQuery(
      _queries['selectByTitleAndParent']!,
      [title, parentId, parentId],
    );
    if (result.isEmpty) return null;
    return Category.fromJson(result.first);
  }
}

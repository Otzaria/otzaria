import 'package:sqflite/sqflite.dart';
import '../../core/models/toc_entry.dart';
import '../sqflite/query_loader.dart';
import 'database.dart';

class TocDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  TocDao(this._db) {
    _queries = QueryLoader.loadQueries('TocQueries.sq');
  }

  Future<Database> get database => _db.database;

  Future<List<TocEntry>> selectByBookId(int bookId) async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectByBookId']!, [bookId]);
    return result.map((row) => TocEntry.fromMap(row)).toList();
  }

  Future<TocEntry?> selectTocById(int id) async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectTocById']!, [id]);
    if (result.isEmpty) return null;
    return TocEntry.fromMap(result.first);
  }

  Future<List<TocEntry>> selectRootByBookId(int bookId) async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectRootByBookId']!, [bookId]);
    return result.map((row) => TocEntry.fromMap(row)).toList();
  }

  Future<List<TocEntry>> selectChildren(int parentId) async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectChildren']!, [parentId]);
    return result.map((row) => TocEntry.fromMap(row)).toList();
  }

  Future<TocEntry?> selectByLineId(int lineId) async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectByLineId']!, [lineId]);
    if (result.isEmpty) return null;
    return TocEntry.fromMap(result.first);
  }

  Future<int> insertTocEntry(TocEntry entry) async {
    final db = await database;
    return await db.rawInsert(_queries['insert']!, [
      entry.bookId,
      entry.parentId,
      entry.textId,
      entry.level,
      entry.lineId,
      entry.lineIndex,
      entry.isLastChild ? 1 : 0,
      entry.hasChildren ? 1 : 0,
    ]);
  }

  Future<int> insertWithId(TocEntry entry) async {
    final db = await database;
    return await db.rawInsert(_queries['insertWithId']!, [
      entry.id,
      entry.bookId,
      entry.parentId,
      entry.textId,
      entry.level,
      entry.lineId,
      entry.lineIndex,
      entry.isLastChild ? 1 : 0,
      entry.hasChildren ? 1 : 0,
    ]);
  }

  Future<int> updateLineId(int tocId, int lineId) async {
    final db = await database;
    return await db.rawUpdate(_queries['updateLineId']!, [lineId, tocId]);
  }

  Future<int> updateIsLastChild(int tocId, bool isLastChild) async {
    final db = await database;
    return await db.rawUpdate(
        _queries['updateIsLastChild']!, [isLastChild ? 1 : 0, tocId]);
  }

  Future<int> updateHasChildren(int tocId, bool hasChildren) async {
    final db = await database;
    return await db.rawUpdate(
        _queries['updateHasChildren']!, [hasChildren ? 1 : 0, tocId]);
  }

  Future<int> delete(int id) async {
    final db = await database;
    return await db.rawDelete(_queries['delete']!, [id]);
  }

  Future<int> deleteByBookId(int bookId) async {
    final db = await database;
    return await db.rawDelete(_queries['deleteByBookId']!, [bookId]);
  }

  Future<int> getLastInsertRowId() async {
    final db = await database;
    final result = await db.rawQuery(_queries['lastInsertRowId']!);
    return result.first.values.first as int;
  }
}

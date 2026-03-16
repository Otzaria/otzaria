import 'package:sqlite3/sqlite3.dart' as sqlite3;
import '../../core/models/toc_entry.dart';
import '../sqflite/sqlite3_utils.dart';
import '../sqflite/query_loader.dart';
import 'database.dart';

class TocDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  TocDao(this._db) {
    _queries = QueryLoader.loadQueries('TocQueries.sq');
  }

  Future<sqlite3.Database> get database => _db.database;

  Future<List<TocEntry>> selectByBookId(int bookId) async {
    final db = await database;
    return db
        .select(_queries['selectByBookId']!, [bookId])
        .toMapList()
        .map((row) => TocEntry.fromMap(row))
        .toList();
  }

  Future<TocEntry?> selectTocById(int id) async {
    final db = await database;
    final result = db.select(_queries['selectTocById']!, [id]).toMapList();
    if (result.isEmpty) return null;
    return TocEntry.fromMap(result.first);
  }

  Future<List<TocEntry>> selectRootByBookId(int bookId) async {
    final db = await database;
    return db
        .select(_queries['selectRootByBookId']!, [bookId])
        .toMapList()
        .map((row) => TocEntry.fromMap(row))
        .toList();
  }

  Future<List<TocEntry>> selectChildren(int parentId) async {
    final db = await database;
    return db
        .select(_queries['selectChildren']!, [parentId])
        .toMapList()
        .map((row) => TocEntry.fromMap(row))
        .toList();
  }

  Future<TocEntry?> selectByLineId(int lineId) async {
    final db = await database;
    final result = db.select(_queries['selectByLineId']!, [lineId]).toMapList();
    if (result.isEmpty) return null;
    return TocEntry.fromMap(result.first);
  }

  Future<int> insertTocEntry(TocEntry entry) async {
    final db = await database;
    db.execute(_queries['insert']!, [
      entry.bookId,
      entry.parentId,
      entry.textId,
      entry.level,
      entry.lineId,
      entry.lineIndex,
      entry.isLastChild ? 1 : 0,
      entry.hasChildren ? 1 : 0,
    ]);
    return db.lastInsertRowId;
  }

  Future<int> insertWithId(TocEntry entry) async {
    final db = await database;
    db.execute(_queries['insertWithId']!, [
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
    return db.lastInsertRowId;
  }

  Future<int> updateLineId(int tocId, int lineId) async {
    final db = await database;
    db.execute(_queries['updateLineId']!, [lineId, tocId]);
    return db.updatedRows;
  }

  Future<int> updateIsLastChild(int tocId, bool isLastChild) async {
    final db = await database;
    db.execute(_queries['updateIsLastChild']!, [isLastChild ? 1 : 0, tocId]);
    return db.updatedRows;
  }

  Future<int> updateHasChildren(int tocId, bool hasChildren) async {
    final db = await database;
    db.execute(_queries['updateHasChildren']!, [hasChildren ? 1 : 0, tocId]);
    return db.updatedRows;
  }

  Future<int> delete(int id) async {
    final db = await database;
    db.execute(_queries['delete']!, [id]);
    return db.updatedRows;
  }

  Future<int> deleteByBookId(int bookId) async {
    final db = await database;
    db.execute(_queries['deleteByBookId']!, [bookId]);
    return db.updatedRows;
  }

  Future<int> getLastInsertRowId() async {
    final db = await database;
    return db.lastInsertRowId;
  }
}


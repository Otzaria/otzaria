import 'package:sqlite3/sqlite3.dart' as sqlite3;
import '../../core/models/line.dart';
import '../sqflite/sqlite3_utils.dart';
import '../sqflite/query_loader.dart';
import 'database.dart';

class LineDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  LineDao(this._db) {
    _queries = QueryLoader.loadQueries('LineQueries.sq');
  }

  Future<sqlite3.Database> get database => _db.database;

  Future<Line?> getLineById(int id) async {
    final db = await database;
    final result = db.select(_queries['selectById']!, [id]).toMapList();
    if (result.isEmpty) return null;
    return _mapToLine(result.first);
  }

  Future<List<Line>> selectByBookId(int bookId) async {
    final db = await database;
    return db
        .select(_queries['selectByBookId']!, [bookId])
        .toMapList()
        .map((row) => _mapToLine(row))
        .toList();
  }

  Future<List<Line>> selectByBookIdRange(
      int bookId, int startIndex, int endIndex) async {
    final db = await database;
    return db
        .select(
            _queries['selectByBookIdRange']!, [bookId, startIndex, endIndex])
        .toMapList()
        .map((row) => _mapToLine(row))
        .toList();
  }

  Future<Line?> selectByBookIdAndIndex(int bookId, int lineIndex) async {
    final db = await database;
    final result = db.select(
        _queries['selectByBookIdAndIndex']!, [bookId, lineIndex]).toMapList();
    if (result.isEmpty) return null;
    return _mapToLine(result.first);
  }

  Future<Line?> selectByHeRef(String heRef) async {
    final db = await database;
    final result = db.select(_queries['selectByHeRef']!, [heRef]).toMapList();
    if (result.isEmpty) return null;
    return _mapToLine(result.first);
  }

  Future<List<Line>> selectByHeRefLike(String heRefPattern, int limit) async {
    final db = await database;
    return db
        .select(_queries['selectByHeRefLike']!, [heRefPattern, limit])
        .toMapList()
        .map((row) => _mapToLine(row))
        .toList();
  }

  Future<int> insertLine(Line line) async {
    final db = await database;
    db.execute(_queries['insert']!, [
      line.bookId,
      line.lineIndex,
      line.content,
      line.heRef,
      null, // tocEntryId - set later
    ]);
    return db.lastInsertRowId;
  }

  Future<int> insertWithId(Line line) async {
    final db = await database;
    db.execute(_queries['insertWithId']!, [
      line.id,
      line.bookId,
      line.lineIndex,
      line.content,
      line.heRef,
      null, // tocEntryId - set later
    ]);
    return db.lastInsertRowId;
  }

  Future<int> updateTocEntryId(int lineId, int tocEntryId) async {
    final db = await database;
    db.execute(_queries['updateTocEntryId']!, [tocEntryId, lineId]);
    return db.updatedRows;
  }

  Future<int> updateHeRef(int lineId, String heRef) async {
    final db = await database;
    db.execute(_queries['updateHeRef']!, [heRef, lineId]);
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

  Future<int> countByBookId(int bookId) async {
    final db = await database;
    return firstIntValue(db.select(_queries['countByBookId']!, [bookId])) ?? 0;
  }

  Future<int> getLastInsertRowId() async {
    final db = await database;
    return db.lastInsertRowId;
  }

  Line _mapToLine(Map<String, dynamic> map) {
    return Line(
      id: map['id'] as int,
      bookId: map['bookId'] as int,
      lineIndex: map['lineIndex'] as int,
      content: map['content'] as String,
      heRef: map['heRef'] as String?,
    );
  }
}


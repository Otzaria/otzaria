import 'package:sqflite/sqflite.dart';
import '../../core/models/line.dart';
import '../sqflite/query_loader.dart';
import 'database.dart';

class LineDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  LineDao(this._db) {
    _queries = QueryLoader.loadQueries('LineQueries.sq');
  }

  Future<Database> get database => _db.database;

  Future<Line?> getLineById(int id) async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectById']!, [id]);
    if (result.isEmpty) return null;
    return _mapToLine(result.first);
  }

  Future<List<Line>> selectByBookId(int bookId) async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectByBookId']!, [bookId]);
    return result.map((row) => _mapToLine(row)).toList();
  }

  Future<List<Line>> selectByBookIdRange(
      int bookId, int startIndex, int endIndex) async {
    final db = await database;
    final result = await db.rawQuery(
        _queries['selectByBookIdRange']!, [bookId, startIndex, endIndex]);
    return result.map((row) => _mapToLine(row)).toList();
  }

  Future<Line?> selectByBookIdAndIndex(int bookId, int lineIndex) async {
    final db = await database;
    final result = await db
        .rawQuery(_queries['selectByBookIdAndIndex']!, [bookId, lineIndex]);
    if (result.isEmpty) return null;
    return _mapToLine(result.first);
  }

  Future<Line?> selectByHeRef(String heRef) async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectByHeRef']!, [heRef]);
    if (result.isEmpty) return null;
    return _mapToLine(result.first);
  }

  Future<List<Line>> selectByHeRefLike(String heRefPattern, int limit) async {
    final db = await database;
    final result = await db
        .rawQuery(_queries['selectByHeRefLike']!, [heRefPattern, limit]);
    return result.map((row) => _mapToLine(row)).toList();
  }

  Future<int> insertLine(Line line) async {
    final db = await database;
    return await db.rawInsert(_queries['insert']!, [
      line.bookId,
      line.lineIndex,
      line.content,
      line.heRef,
      null, // tocEntryId - set later
    ]);
  }

  Future<int> insertWithId(Line line) async {
    final db = await database;
    return await db.rawInsert(_queries['insertWithId']!, [
      line.id,
      line.bookId,
      line.lineIndex,
      line.content,
      line.heRef,
      null, // tocEntryId - set later
    ]);
  }

  Future<int> updateTocEntryId(int lineId, int tocEntryId) async {
    final db = await database;
    return await db
        .rawUpdate(_queries['updateTocEntryId']!, [tocEntryId, lineId]);
  }

  Future<int> updateHeRef(int lineId, String heRef) async {
    final db = await database;
    return await db.rawUpdate(_queries['updateHeRef']!, [heRef, lineId]);
  }

  Future<int> delete(int id) async {
    final db = await database;
    return await db.rawDelete(_queries['delete']!, [id]);
  }

  Future<int> deleteByBookId(int bookId) async {
    final db = await database;
    return await db.rawDelete(_queries['deleteByBookId']!, [bookId]);
  }

  Future<int> countByBookId(int bookId) async {
    final db = await database;
    final result = await db.rawQuery(_queries['countByBookId']!, [bookId]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> getLastInsertRowId() async {
    final db = await database;
    final result = await db.rawQuery(_queries['lastInsertRowId']!);
    return result.first.values.first as int;
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

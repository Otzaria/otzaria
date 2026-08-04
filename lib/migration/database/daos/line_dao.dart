import 'dart:typed_data';

import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import '../../models/line.dart';
import '../sqlite3_utils.dart';
import '../query_loader.dart';
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

  /// תוכן כל שורות הספר בסדר השורות, בלי בניית Map ואובייקט [Line] לכל
  /// שורה — מסלול הקריאה של האינדוקס, שרק מאחה את התוכן לטקסט אחד.
  Future<List<String>> selectContentByBookId(int bookId) async {
    final db = await database;
    return db
        .select(_queries['selectContentByBookId']!, [bookId])
        .map((row) => (row.values.first as String?) ?? '')
        .toList();
  }

  /// תוכן כל שורות הספר כבייטים גולמיים (UTF-8 כפי שמאוחסן ב-SQLite),
  /// מאוחים ב-`\n` — בלי פענוח ל-String: מסלול האינדוקס מעביר את הבייטים
  /// למנוע כמות-שהם וחוסך את סבב הקידוד UTF-8→UTF-16→UTF-8 על גשר ה-FFI.
  Future<Uint8List> selectContentBytesByBookId(int bookId) async {
    final db = await database;
    final parts = db
        .select(_queries['selectContentBlobByBookId']!, [bookId])
        .map((row) => (row.values.first as Uint8List?) ?? Uint8List(0))
        .toList();
    if (parts.isEmpty) return Uint8List(0);

    var total = parts.length - 1; // מפרידי \n
    for (final part in parts) {
      total += part.length;
    }
    final joined = Uint8List(total);
    var offset = 0;
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) joined[offset++] = 0x0A; // '\n'
      joined.setAll(offset, parts[i]);
      offset += parts[i].length;
    }
    return joined;
  }

  Future<List<Line>> selectByBookIdRange(
    int bookId,
    int startIndex,
    int endIndex,
  ) async {
    final db = await database;
    return db
        .select(_queries['selectByBookIdRange']!, [
          bookId,
          startIndex,
          endIndex,
        ])
        .toMapList()
        .map((row) => _mapToLine(row))
        .toList();
  }

  Future<Line?> selectByBookIdAndIndex(int bookId, int lineIndex) async {
    final db = await database;
    final result = db.select(_queries['selectByBookIdAndIndex']!, [
      bookId,
      lineIndex,
    ]).toMapList();
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

  /// זוגות (lineIndex, heRef) של כל השורות בעלות heRef בספר, בסדר השורות.
  /// מסלול רזה — בלי content — לרזולוציית הפניה לרמת שורה.
  Future<List<({int lineIndex, String heRef})>> selectRefsByBookId(
    int bookId,
  ) async {
    final db = await database;
    return db
        .select(_queries['selectRefsByBookId']!, [bookId])
        .map(
          (row) => (
            lineIndex: row['lineIndex'] as int,
            heRef: row['heRef'] as String,
          ),
        )
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

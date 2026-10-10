import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import '../../models/line.dart';
import '../line_content_codec.dart';
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

  /// שאילתת תוכן לפי צורת המסד: בסכמה 6 התוכן ב-`line_content`.
  Future<String> _forShape(String name) async =>
      (await _db.capabilities).hasSplitLineContent
      ? _queries['${name}Split']!
      : _queries[name]!;

  Future<List<Line>> selectByBookId(int bookId) async {
    final db = await database;
    return db
        .select(await _forShape('selectByBookId'), [bookId])
        .toMapList()
        .map((row) => _mapToLine(row, LineContentCodec.of(db)))
        .toList();
  }

  /// תוכן כל שורות הספר בסדר השורות, בלי בניית Map ואובייקט [Line] לכל
  /// שורה — מסלול הקריאה של האינדוקס, שרק מאחה את התוכן לטקסט אחד.
  Future<List<String>> selectContentByBookId(int bookId) async {
    final db = await database;
    final codec = LineContentCodec.of(db);
    return db
        .select(await _forShape('selectContentByBookId'), [bookId])
        .map((row) => codec.text(row.values.first) ?? '')
        .toList();
  }

  Future<List<Line>> selectByBookIdRange(
    int bookId,
    int startIndex,
    int endIndex,
  ) async {
    final db = await database;
    return db
        .select(await _forShape('selectByBookIdRange'), [
          bookId,
          startIndex,
          endIndex,
        ])
        .toMapList()
        .map((row) => _mapToLine(row, LineContentCodec.of(db)))
        .toList();
  }

  Future<Line?> selectByBookIdAndIndex(int bookId, int lineIndex) async {
    final db = await database;
    final result = db.select(await _forShape('selectByBookIdAndIndex'), [
      bookId,
      lineIndex,
    ]).toMapList();
    if (result.isEmpty) return null;
    return _mapToLine(result.first, LineContentCodec.of(db));
  }

  Future<Line?> selectByHeRef(String heRef) async {
    final db = await database;
    final result = db.select(await _forShape('selectByHeRef'), [
      heRef,
    ]).toMapList();
    if (result.isEmpty) return null;
    return _mapToLine(result.first, LineContentCodec.of(db));
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

  Line _mapToLine(Map<String, dynamic> map, LineContentCodec codec) {
    return Line(
      id: map['id'] as int,
      bookId: map['bookId'] as int,
      lineIndex: map['lineIndex'] as int,
      content: codec.text(map['content'])!,
      heRef: map['heRef'] as String?,
    );
  }
}

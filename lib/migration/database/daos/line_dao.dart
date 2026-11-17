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

  /// קורא טווח סגור בשאילתה אחת, ומפענח את תוכן השורות לפי צריכתן.
  /// השאילתה מסתיימת לפני הפענוח והסריקה כדי לשחרר את נעילת הקריאה.
  Future<Iterable<({int lineIndex, String content})>>
  selectIndexedContentByBookIdRange(
    int bookId,
    int startIndex,
    int endIndex,
  ) async {
    final db = await database;
    final rows = db.select(
      await _forShape('selectIndexedContentByBookIdRange'),
      [bookId, startIndex, endIndex],
    ).rows;
    if (rows.isEmpty) return const [];
    final codec = LineContentCodec.of(db);
    return rows.map(
      (row) => (lineIndex: row[0] as int, content: codec.text(row[1])!),
    );
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

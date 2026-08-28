import 'dart:collection';
import 'dart:typed_data';

import 'package:otzaria/data/content/compressed_content.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import '../../models/line.dart';
import '../sqlite3_utils.dart';
import '../query_loader.dart';
import 'database.dart';

class LineDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;
  bool? _hasBookContent;
  final LinkedHashMap<int, Future<List<String>?>> _contentCache =
      LinkedHashMap();

  LineDao(this._db) {
    _queries = QueryLoader.loadQueries('LineQueries.sq');
  }

  Future<sqlite3.Database> get database => _db.database;

  Future<Line?> getLineById(int id) async {
    final db = await database;
    final result = db.select(_queries['selectById']!, [id]).toMapList();
    if (result.isEmpty) return null;
    return _mapToHydratedLine(result.first);
  }

  Future<List<Line>> selectByBookId(int bookId) async {
    final db = await database;
    final rows = db
        .select(_queries['selectByBookId']!, [bookId])
        .toMapList();
    return _hydrateRows(rows);
  }

  /// תוכן כל שורות הספר בסדר השורות, בלי בניית Map ואובייקט [Line] לכל
  /// שורה — מסלול הקריאה של האינדוקס, שרק מאחה את התוכן לטקסט אחד.
  Future<List<String>> selectContentByBookId(int bookId) async {
    final compressed = await _compressedLines(bookId);
    if (compressed != null) return compressed;
    final db = await database;
    return db
        .select(_queries['selectContentByBookId']!, [bookId])
        .map((row) => (row.values.first as String?) ?? '')
        .toList();
  }

  /// Returns the compact Zstd frame when available, otherwise legacy UTF-8.
  Future<Uint8List> selectContentBytesByBookId(int bookId) async {
    final db = await database;
    final packed = await _selectBookContent(db, bookId);
    if (packed != null) return packed.contentZstd;
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
    final rows = db
        .select(_queries['selectByBookIdRange']!, [
          bookId,
          startIndex,
          endIndex,
        ])
        .toMapList();
    return _hydrateRows(rows);
  }

  Future<Line?> selectByBookIdAndIndex(int bookId, int lineIndex) async {
    final db = await database;
    final result = db.select(_queries['selectByBookIdAndIndex']!, [
      bookId,
      lineIndex,
    ]).toMapList();
    if (result.isEmpty) return null;
    return _mapToHydratedLine(result.first);
  }

  Future<Line?> selectByHeRef(String heRef) async {
    final db = await database;
    final result = db.select(_queries['selectByHeRef']!, [heRef]).toMapList();
    if (result.isEmpty) return null;
    return _mapToHydratedLine(result.first);
  }

  Future<List<Line>> selectByHeRefLike(String heRefPattern, int limit) async {
    final db = await database;
    final rows = db
        .select(_queries['selectByHeRefLike']!, [heRefPattern, limit])
        .toMapList();
    return Future.wait(rows.map(_mapToHydratedLine));
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

  Future<List<Line>> _hydrateRows(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return const [];
    final compressed = await _compressedLines(rows.first['bookId'] as int);
    return rows
        .map(
          (row) => _mapToLine(
            row,
            content: compressed == null
                ? null
                : _contentAt(compressed, row['lineIndex'] as int),
          ),
        )
        .toList();
  }

  Future<Line> _mapToHydratedLine(Map<String, dynamic> row) async {
    final compressed = await _compressedLines(row['bookId'] as int);
    return _mapToLine(
      row,
      content: compressed == null
          ? null
          : _contentAt(compressed, row['lineIndex'] as int),
    );
  }

  String _contentAt(List<String> lines, int lineIndex) {
    if (lineIndex < 0 || lineIndex >= lines.length) {
      throw FormatException('Invalid compressed line index $lineIndex');
    }
    return lines[lineIndex];
  }

  Future<List<String>?> _compressedLines(int bookId) {
    final cached = _contentCache.remove(bookId);
    if (cached != null) {
      _contentCache[bookId] = cached;
      return cached;
    }

    final loaded = _loadCompressedLines(bookId);
    _contentCache[bookId] = loaded;
    if (_contentCache.length > 2) {
      _contentCache.remove(_contentCache.keys.first);
    }
    return loaded;
  }

  Future<List<String>?> _loadCompressedLines(int bookId) async {
    final db = await database;
    final packed = await _selectBookContent(db, bookId);
    if (packed == null) return null;
    if (packed.format != 1) {
      throw FormatException('Unsupported book-content format ${packed.format}');
    }
    final payload = await decompressVerifiedContent(
      compressed: packed.contentZstd,
      uncompressedSize: packed.uncompressedSize,
      contentHash: packed.contentHash,
    );
    return decodeBookContentPayload(
      payload,
      expectedLines: packed.totalLines,
    );
  }

  Future<
    ({
      int format,
      Uint8List contentZstd,
      int uncompressedSize,
      Uint8List contentHash,
      int totalLines,
    })?
  >
  _selectBookContent(sqlite3.Database db, int bookId) async {
    _hasBookContent ??= db
        .select(
          "SELECT 1 FROM sqlite_master WHERE type='table' AND name='book_content' LIMIT 1",
        )
        .isNotEmpty;
    if (!_hasBookContent!) return null;
    final rows = db.select(
      '''
      SELECT bc.format, bc.contentZstd, bc.uncompressedSize, bc.contentHash,
             b.totalLines
      FROM book_content bc JOIN book b ON b.id = bc.bookId
      WHERE bc.bookId = ? LIMIT 1
      ''',
      [bookId],
    ).toMapList();
    if (rows.isEmpty) return null;
    final row = rows.first;
    return (
      format: row['format'] as int? ?? 1,
      contentZstd: row['contentZstd'] as Uint8List,
      uncompressedSize: row['uncompressedSize'] as int,
      contentHash: row['contentHash'] as Uint8List,
      totalLines: row['totalLines'] as int,
    );
  }

  Line _mapToLine(Map<String, dynamic> map, {String? content}) {
    return Line(
      id: map['id'] as int,
      bookId: map['bookId'] as int,
      lineIndex: map['lineIndex'] as int,
      content: content ?? map['content'] as String,
      heRef: map['heRef'] as String?,
    );
  }
}

import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import '../../models/toc_entry.dart';
import '../sqlite3_utils.dart';
import '../query_loader.dart';
import 'database.dart';

class TocDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;
  Map<String, String>? _resolvedQueries;

  TocDao(this._db) {
    _queries = QueryLoader.loadQueries('TocQueries.sq');
  }

  Future<sqlite3.Database> get database => _db.database;

  /// ל-seforim.db v3 אין עמודת tocEntry.lineIndex (רק lineId), ואזכור שלה
  /// היה מפיל את השאילתה ב-prepare. משמיטים אותה מה-COALESCE; ל-user_books.db
  /// (TOC של ספרי PDF) משאירים אותה.
  Future<Map<String, String>> _resolved() async {
    if (_resolvedQueries != null) return _resolvedQueries!;
    final db = await database;
    final hasLineIndex = db
        .select(
          "SELECT 1 FROM pragma_table_info('tocEntry') WHERE name = 'lineIndex'",
        )
        .isNotEmpty;
    _resolvedQueries = hasLineIndex
        ? _queries
        : {
            for (final e in _queries.entries)
              e.key: e.value.replaceAll(
                'l.lineIndex, t.lineIndex, t.lineId',
                'l.lineIndex, t.lineId',
              ),
          };
    return _resolvedQueries!;
  }

  Future<List<TocEntry>> selectByBookId(int bookId) async {
    final db = await database;
    final queries = await _resolved();
    return db
        .select(queries['selectByBookId']!, [bookId])
        .toMapList()
        .map((row) => TocEntry.fromMap(row))
        .toList();
  }

  Future<TocEntry?> selectTocById(int id) async {
    final db = await database;
    final queries = await _resolved();
    final result = db.select(queries['selectTocById']!, [id]).toMapList();
    if (result.isEmpty) return null;
    return TocEntry.fromMap(result.first);
  }

  Future<List<TocEntry>> selectRootByBookId(int bookId) async {
    final db = await database;
    final queries = await _resolved();
    return db
        .select(queries['selectRootByBookId']!, [bookId])
        .toMapList()
        .map((row) => TocEntry.fromMap(row))
        .toList();
  }

  Future<List<TocEntry>> selectChildren(int parentId) async {
    final db = await database;
    final queries = await _resolved();
    return db
        .select(queries['selectChildren']!, [parentId])
        .toMapList()
        .map((row) => TocEntry.fromMap(row))
        .toList();
  }

  Future<TocEntry?> selectByLineId(int lineId) async {
    final db = await database;
    final queries = await _resolved();
    final result = db.select(queries['selectByLineId']!, [lineId]).toMapList();
    if (result.isEmpty) return null;
    return TocEntry.fromMap(result.first);
  }

  Future<int> insertTocEntry(TocEntry entry) async {
    final db = await database;
    return insertTocEntrySync(db, entry);
  }

  /// גרעין סינכרוני של [insertTocEntry] — לשימוש בתוך `withTransaction`.
  int insertTocEntrySync(sqlite3.Database db, TocEntry entry) {
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

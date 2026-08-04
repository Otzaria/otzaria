import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import '../../models/toc_text.dart';
import '../sqlite3_utils.dart';
import '../query_loader.dart';
import 'database.dart';

class TocTextDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  TocTextDao(this._db) {
    _queries = QueryLoader.loadQueries('TocTextQueries.sq');
  }

  Future<sqlite3.Database> get database => _db.database;

  Future<List<TocText>> selectAll() async {
    final db = await database;
    return db
        .select(_queries['selectAll']!)
        .toMapList()
        .map((row) => TocText.fromMap(row))
        .toList();
  }

  Future<TocText?> selectById(int id) async {
    final db = await database;
    final result = db.select(_queries['selectById']!, [id]).toMapList();
    if (result.isEmpty) return null;
    return TocText.fromMap(result.first);
  }

  Future<TocText?> selectByText(String text) async {
    final db = await database;
    final result = db.select(_queries['selectByText']!, [text]).toMapList();
    if (result.isEmpty) return null;
    return TocText.fromMap(result.first);
  }

  Future<int> insert(TocText tocText) async {
    final db = await database;
    db.execute(_queries['insert']!, [tocText.text]);
    return db.lastInsertRowId;
  }

  Future<int> insertAndGetId(TocText tocText) async {
    final db = await database;
    db.execute(_queries['insertAndGetId']!, [tocText.text]);
    return db.lastInsertRowId;
  }

  Future<int> selectIdByText(String text) async {
    final db = await database;
    final result = db.select(_queries['selectIdByText']!, [text]).toMapList();
    if (result.isEmpty) return 0;
    return result.first['id'] as int;
  }

  /// גרעין סינכרוני: מאתר או יוצר tocText ומחזיר את ה-id — לשימוש בתוך
  /// `withTransaction`.
  int getOrCreateIdSync(sqlite3.Database db, String text) {
    final existing = db.select(_queries['selectIdByText']!, [text]).toMapList();
    if (existing.isNotEmpty) return existing.first['id'] as int;
    db.execute(_queries['insertAndGetId']!, [text]);
    final inserted = db.select(_queries['selectIdByText']!, [text]).toMapList();
    if (inserted.isNotEmpty) return inserted.first['id'] as int;
    throw StateError('Failed to insert tocText (length: ${text.length})');
  }

  Future<int> delete(int id) async {
    final db = await database;
    db.execute(_queries['delete']!, [id]);
    return db.updatedRows;
  }

  Future<int> countAll() async {
    final db = await database;
    return firstIntValue(db.select(_queries['countAll']!)) ?? 0;
  }

  Future<int> getLastInsertRowId() async {
    final db = await database;
    return db.lastInsertRowId;
  }
}

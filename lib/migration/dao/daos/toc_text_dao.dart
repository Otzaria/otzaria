import 'package:sqlite3/sqlite3.dart' as sqlite3;
import '../../core/models/toc_text.dart';
import '../sqflite/sqlite3_utils.dart';
import '../sqflite/query_loader.dart';
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


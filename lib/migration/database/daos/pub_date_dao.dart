import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import '../../models/pub_date.dart';
import '../sql/sqlite3_utils.dart';
import '../sql/query_loader.dart';
import 'database.dart';

class PubDateDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  PubDateDao(this._db) {
    _queries = QueryLoader.loadQueries('PubDateQueries.sq');
  }

  Future<sqlite3.Database> get database => _db.database;

  Future<List<PubDate>> getAllPubDates() async {
    final db = await database;
    return db
        .select(_queries['selectAll']!)
        .toMapList()
        .map((row) => PubDate.fromJson(row))
        .toList();
  }

  Future<PubDate?> getPubDateById(int id) async {
    final db = await database;
    final result = db.select(_queries['selectById']!, [id]).toMapList();
    if (result.isEmpty) return null;
    return PubDate.fromJson(result.first);
  }

  Future<PubDate?> getPubDateByDate(String date) async {
    final db = await database;
    final result = db.select(_queries['selectByDate']!, [date]).toMapList();
    if (result.isEmpty) return null;
    return PubDate.fromJson(result.first);
  }

  Future<List<PubDate>> getPubDatesByBookId(int bookId) async {
    final db = await database;
    return db
        .select(_queries['selectByBookId']!, [bookId])
        .toMapList()
        .map((row) => PubDate.fromJson(row))
        .toList();
  }

  Future<int> insertPubDate(String date) async {
    final db = await database;
    db.execute(_queries['insert']!, [date]);
    return db.lastInsertRowId;
  }

  Future<int> insertPubDateAndGetId(String date) async {
    final db = await database;
    db.execute(_queries['insert']!, [date]);
    return db.lastInsertRowId;
  }

  Future<int> linkBookPubDate(int bookId, int pubDateId) async {
    final db = await database;
    db.execute(_queries['linkBookPubDate']!, [bookId, pubDateId]);
    return db.lastInsertRowId;
  }

  Future<int> deletePubDate(int id) async {
    final db = await database;
    db.execute(_queries['delete']!, [id]);
    return db.updatedRows;
  }

  Future<int> countAllPubDates() async {
    final db = await database;
    return firstIntValue(db.select(_queries['countAll']!)) ?? 0;
  }
}

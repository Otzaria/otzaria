import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import '../../models/pub_date.dart';
import '../sqlite3_utils.dart';
import '../query_loader.dart';
import 'database.dart';

class PubDateDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  PubDateDao(this._db) {
    _queries = QueryLoader.loadQueries('PubDateQueries.sq');
  }

  Future<sqlite3.Database> get database => _db.database;

  Future<PubDate?> getPubDateByDate(String date) async {
    final db = await database;
    final result = db.select(_queries['selectByDate']!, [date]).toMapList();
    if (result.isEmpty) return null;
    return PubDate.fromJson(result.first);
  }

  Future<int> insertPubDate(String date) async {
    final db = await database;
    db.execute(_queries['insert']!, [date]);
    return db.lastInsertRowId;
  }

  Future<int> linkBookPubDate(int bookId, int pubDateId) async {
    final db = await database;
    db.execute(_queries['linkBookPubDate']!, [bookId, pubDateId]);
    return db.lastInsertRowId;
  }

}

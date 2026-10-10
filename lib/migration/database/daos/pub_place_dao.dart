import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import '../../models/pub_place.dart';
import '../sqlite3_utils.dart';
import '../query_loader.dart';
import 'database.dart';

class PubPlaceDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  PubPlaceDao(this._db) {
    _queries = QueryLoader.loadQueries('PubPlaceQueries.sq');
  }

  Future<sqlite3.Database> get database => _db.database;

  Future<PubPlace?> getPubPlaceByName(String name) async {
    final db = await database;
    final result = db.select(_queries['selectByName']!, [name]).toMapList();
    if (result.isEmpty) return null;
    return PubPlace.fromJson(result.first);
  }

  Future<int> insertPubPlace(String name) async {
    final db = await database;
    db.execute(_queries['insert']!, [name]);
    return db.lastInsertRowId;
  }

  Future<int> linkBookPubPlace(int bookId, int pubPlaceId) async {
    final db = await database;
    db.execute(_queries['linkBookPubPlace']!, [bookId, pubPlaceId]);
    return db.lastInsertRowId;
  }

}

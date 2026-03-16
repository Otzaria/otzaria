import 'package:sqlite3/sqlite3.dart' as sqlite3;
import '../../core/models/pub_place.dart';
import '../sqflite/sqlite3_utils.dart';
import '../sqflite/query_loader.dart';
import 'database.dart';

class PubPlaceDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  PubPlaceDao(this._db) {
    _queries = QueryLoader.loadQueries('PubPlaceQueries.sq');
  }

  Future<sqlite3.Database> get database => _db.database;

  Future<List<PubPlace>> getAllPubPlaces() async {
    final db = await database;
    return db
        .select(_queries['selectAll']!)
        .toMapList()
        .map((row) => PubPlace.fromJson(row))
        .toList();
  }

  Future<PubPlace?> getPubPlaceById(int id) async {
    final db = await database;
    final result = db.select(_queries['selectById']!, [id]).toMapList();
    if (result.isEmpty) return null;
    return PubPlace.fromJson(result.first);
  }

  Future<PubPlace?> getPubPlaceByName(String name) async {
    final db = await database;
    final result = db.select(_queries['selectByName']!, [name]).toMapList();
    if (result.isEmpty) return null;
    return PubPlace.fromJson(result.first);
  }

  Future<List<PubPlace>> getPubPlacesByBookId(int bookId) async {
    final db = await database;
    return db
        .select(_queries['selectByBookId']!, [bookId])
        .toMapList()
        .map((row) => PubPlace.fromJson(row))
        .toList();
  }

  Future<int> insertPubPlace(String name) async {
    final db = await database;
    db.execute(_queries['insert']!, [name]);
    return db.lastInsertRowId;
  }

  Future<int> insertPubPlaceAndGetId(String name) async {
    final db = await database;
    db.execute(_queries['insert']!, [name]);
    return db.lastInsertRowId;
  }

  Future<int> linkBookPubPlace(int bookId, int pubPlaceId) async {
    final db = await database;
    db.execute(_queries['linkBookPubPlace']!, [bookId, pubPlaceId]);
    return db.lastInsertRowId;
  }

  Future<int> deletePubPlace(int id) async {
    final db = await database;
    db.execute(_queries['delete']!, [id]);
    return db.updatedRows;
  }

  Future<int> countAllPubPlaces() async {
    final db = await database;
    return firstIntValue(db.select(_queries['countAll']!)) ?? 0;
  }
}


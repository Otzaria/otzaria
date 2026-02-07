import 'package:sqflite/sqflite.dart';
import '../../core/models/pub_place.dart';
import '../sqflite/query_loader.dart';
import 'database.dart';

class PubPlaceDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  PubPlaceDao(this._db) {
    _queries = QueryLoader.loadQueries('PubPlaceQueries.sq');
  }

  Future<Database> get database => _db.database;

  Future<List<PubPlace>> getAllPubPlaces() async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectAll']!);
    return result.map((row) => PubPlace.fromJson(row)).toList();
  }

  Future<PubPlace?> getPubPlaceById(int id) async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectById']!, [id]);
    if (result.isEmpty) return null;
    return PubPlace.fromJson(result.first);
  }

  Future<PubPlace?> getPubPlaceByName(String name) async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectByName']!, [name]);
    if (result.isEmpty) return null;
    return PubPlace.fromJson(result.first);
  }

  Future<List<PubPlace>> getPubPlacesByBookId(int bookId) async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectByBookId']!, [bookId]);
    return result.map((row) => PubPlace.fromJson(row)).toList();
  }

  Future<int> insertPubPlace(String name) async {
    final db = await database;
    return await db.rawInsert(_queries['insert']!, [name]);
  }

  Future<int> insertPubPlaceAndGetId(String name) async {
    final db = await database;
    await db.rawInsert(_queries['insert']!, [name]);
    final result = await db.rawQuery(_queries['lastInsertRowId']!);
    return result.first.values.first as int;
  }

  Future<int> linkBookPubPlace(int bookId, int pubPlaceId) async {
    final db = await database;
    return await db
        .rawInsert(_queries['linkBookPubPlace']!, [bookId, pubPlaceId]);
  }

  Future<int> deletePubPlace(int id) async {
    final db = await database;
    return await db.rawDelete(_queries['delete']!, [id]);
  }

  Future<int> countAllPubPlaces() async {
    final db = await database;
    final result = await db.rawQuery(_queries['countAll']!);
    return Sqflite.firstIntValue(result) ?? 0;
  }
}

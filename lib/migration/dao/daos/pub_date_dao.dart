import 'package:sqflite/sqflite.dart';
import '../../core/models/pub_date.dart';
import '../sqflite/query_loader.dart';
import 'database.dart';

class PubDateDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  PubDateDao(this._db) {
    _queries = QueryLoader.loadQueries('PubDateQueries.sq');
  }

  Future<Database> get database => _db.database;

  Future<List<PubDate>> getAllPubDates() async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectAll']!);
    return result.map((row) => PubDate.fromJson(row)).toList();
  }

  Future<PubDate?> getPubDateById(int id) async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectById']!, [id]);
    if (result.isEmpty) return null;
    return PubDate.fromJson(result.first);
  }

  Future<PubDate?> getPubDateByDate(String date) async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectByDate']!, [date]);
    if (result.isEmpty) return null;
    return PubDate.fromJson(result.first);
  }

  Future<List<PubDate>> getPubDatesByBookId(int bookId) async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectByBookId']!, [bookId]);
    return result.map((row) => PubDate.fromJson(row)).toList();
  }

  Future<int> insertPubDate(String date) async {
    final db = await database;
    return await db.rawInsert(_queries['insert']!, [date]);
  }

  Future<int> insertPubDateAndGetId(String date) async {
    final db = await database;
    await db.rawInsert(_queries['insert']!, [date]);
    final result = await db.rawQuery(_queries['lastInsertRowId']!);
    return result.first.values.first as int;
  }

  Future<int> linkBookPubDate(int bookId, int pubDateId) async {
    final db = await database;
    return await db
        .rawInsert(_queries['linkBookPubDate']!, [bookId, pubDateId]);
  }

  Future<int> deletePubDate(int id) async {
    final db = await database;
    return await db.rawDelete(_queries['delete']!, [id]);
  }

  Future<int> countAllPubDates() async {
    final db = await database;
    final result = await db.rawQuery(_queries['countAll']!);
    return Sqflite.firstIntValue(result) ?? 0;
  }
}

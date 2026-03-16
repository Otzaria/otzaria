import 'package:sqlite3/sqlite3.dart' as sqlite3;
import '../../core/models/generation.dart';
import '../sqflite/sqlite3_utils.dart';
import '../sqflite/query_loader.dart';
import 'database.dart';

class GenerationDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  GenerationDao(this._db) {
    _queries = QueryLoader.loadQueries('GenerationQueries.sq');
  }

  Future<sqlite3.Database> get database => _db.database;

  Future<List<Generation>> getAllGenerations() async {
    final db = await database;
    return db
        .select(_queries['selectAll']!)
        .toMapList()
        .map((row) => Generation.fromJson(row))
        .toList();
  }

  Future<Generation?> getGenerationById(int id) async {
    final db = await database;
    final result = db.select(_queries['selectById']!, [id]).toMapList();
    if (result.isEmpty) return null;
    return Generation.fromJson(result.first);
  }

  Future<Generation?> getGenerationByName(String name) async {
    final db = await database;
    final result = db.select(_queries['selectByName']!, [name]).toMapList();
    if (result.isEmpty) return null;
    return Generation.fromJson(result.first);
  }

  Future<List<Generation>> getChildren(int parentGenerationId) async {
    final db = await database;
    return db
        .select(_queries['selectChildren']!, [parentGenerationId])
        .toMapList()
        .map((row) => Generation.fromJson(row))
        .toList();
  }
}

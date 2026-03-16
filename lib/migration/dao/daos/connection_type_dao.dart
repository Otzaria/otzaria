import 'package:sqlite3/sqlite3.dart' as sqlite3;
import '../sqflite/query_loader.dart';
import '../sqflite/sqlite3_utils.dart';
import 'database.dart';

// Simple model for connection type table entries
class ConnectionTypeEntry {
  final int id;
  final String name;

  const ConnectionTypeEntry({
    required this.id,
    required this.name,
  });

  factory ConnectionTypeEntry.fromMap(Map<String, dynamic> map) {
    return ConnectionTypeEntry(
      id: map['id'] as int,
      name: map['name'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
    };
  }
}

class ConnectionTypeDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  ConnectionTypeDao(this._db) {
    _queries = QueryLoader.loadQueries('ConnectionTypeQueries.sq');
  }

  Future<sqlite3.Database> get database => _db.database;

  Future<List<ConnectionTypeEntry>> getAllConnectionTypes() async {
    final db = await database;
    return db
        .select(_queries['selectAll']!)
        .toMapList()
        .map((row) => ConnectionTypeEntry.fromMap(row))
        .toList();
  }

  Future<ConnectionTypeEntry?> getConnectionTypeById(int id) async {
    final db = await database;
    final result = db.select(_queries['selectById']!, [id]).toMapList();
    if (result.isEmpty) return null;
    return ConnectionTypeEntry.fromMap(result.first);
  }

  Future<ConnectionTypeEntry?> getConnectionTypeByName(String name) async {
    final db = await database;
    final result = db.select(_queries['selectByName']!, [name]).toMapList();
    if (result.isEmpty) return null;
    return ConnectionTypeEntry.fromMap(result.first);
  }

  Future<int> insertConnectionType(String name) async {
    final db = await database;
    db.execute(_queries['insert']!, [name]);
    return db.lastInsertRowId;
  }

  Future<int> insertConnectionTypeAndGetId(String name) async {
    final db = await database;
    db.execute(_queries['insert']!, [name]);
    return db.lastInsertRowId;
  }

  Future<int> updateConnectionType(int id, String name) async {
    final db = await database;
    db.execute(_queries['update']!, [name, id]);
    return db.updatedRows;
  }

  Future<int> deleteConnectionType(int id) async {
    final db = await database;
    db.execute(_queries['delete']!, [id]);
    return db.updatedRows;
  }
}


import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;

import '../query_loader.dart';
import '../sqlite3_utils.dart';
import 'database.dart';

/// בסיס ל-DAO של מטמון לפי נתיב קובץ: אותן שאילתות בשמן, שונה רק הרשומה.
class FileCacheDao<E> {
  final MyDatabase _db;
  final Map<String, String> queries;
  final E Function(Map<String, dynamic> map) _fromMap;

  /// ערכי ה-upsert בסדר העמודות שבשאילתה.
  final List<Object?> Function(E entry) _upsertArgs;

  FileCacheDao(this._db, String queriesFile, this._fromMap, this._upsertArgs)
    : queries = QueryLoader.loadQueries(queriesFile);

  Future<sqlite3.Database> get database => _db.database;

  Future<E?> selectByFilePath(String filePath) async {
    final db = await database;
    final result = db.select(queries['selectByFilePath']!, [
      filePath,
    ]).toMapList();
    if (result.isEmpty) return null;
    return _fromMap(result.first);
  }

  Future<void> upsert(E entry) async {
    final db = await database;
    db.execute(queries['upsert']!, _upsertArgs(entry));
  }

  Future<void> updateAccessedAt(String filePath, int accessedAt) async {
    final db = await database;
    db.execute(queries['updateAccessedAt']!, [accessedAt, filePath]);
  }

  Future<void> deleteByFilePath(String filePath) async {
    final db = await database;
    db.execute(queries['deleteByFilePath']!, [filePath]);
  }

  Future<void> deleteAccessedBefore(int cutoffMillis) async {
    final db = await database;
    db.execute(queries['deleteAccessedBefore']!, [cutoffMillis]);
  }
}

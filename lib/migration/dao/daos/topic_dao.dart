import 'package:sqlite3/sqlite3.dart' as sqlite3;
import '../../core/models/topic.dart';
import '../sqflite/sqlite3_utils.dart';
import '../sqflite/query_loader.dart';
import 'database.dart';

class TopicDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  TopicDao(this._db) {
    _queries = QueryLoader.loadQueries('TopicQueries.sq');
  }

  Future<sqlite3.Database> get database => _db.database;

  Future<List<Topic>> getAllTopics() async {
    final db = await database;
    return db
        .select(_queries['selectAll']!)
        .toMapList()
        .map((row) => Topic.fromJson(row))
        .toList();
  }

  Future<Topic?> getTopicById(int id) async {
    final db = await database;
    final result = db.select(_queries['selectById']!, [id]).toMapList();
    if (result.isEmpty) return null;
    return Topic.fromJson(result.first);
  }

  Future<Topic?> getTopicByName(String name) async {
    final db = await database;
    final result = db.select(_queries['selectByName']!, [name]).toMapList();
    if (result.isEmpty) return null;
    return Topic.fromJson(result.first);
  }

  Future<List<Topic>> getTopicsByBookId(int bookId) async {
    final db = await database;
    return db
        .select(_queries['selectByBookId']!, [bookId])
        .toMapList()
        .map((row) => Topic.fromJson(row))
        .toList();
  }

  Future<int> insertTopic(String name) async {
    final db = await database;
    db.execute(_queries['insert']!, [name]);
    return db.lastInsertRowId;
  }

  Future<int> insertTopicAndGetId(String name) async {
    final db = await database;
    db.execute(_queries['insertAndGetId']!, [name]);
    return db.lastInsertRowId;
  }

  Future<int?> getTopicIdByName(String name) async {
    final db = await database;
    final result = db.select(_queries['selectIdByName']!, [name]).toMapList();
    if (result.isEmpty) return null;
    return result.first['id'] as int;
  }

  Future<int> deleteTopic(int id) async {
    final db = await database;
    db.execute(_queries['delete']!, [id]);
    return db.updatedRows;
  }

  Future<int> countAllTopics() async {
    final db = await database;
    return firstIntValue(db.select(_queries['countAll']!)) ?? 0;
  }

  // Junction table operations
  Future<int> linkBookTopic(int bookId, int topicId) async {
    final db = await database;
    db.execute(_queries['linkBookTopic']!, [bookId, topicId]);
    return db.lastInsertRowId;
  }

  Future<int> unlinkBookTopic(int bookId, int topicId) async {
    final db = await database;
    db.execute(_queries['unlinkBookTopic']!, [bookId, topicId]);
    return db.updatedRows;
  }

  Future<int> deleteAllBookTopics(int bookId) async {
    final db = await database;
    db.execute(_queries['deleteAllBookTopics']!, [bookId]);
    return db.updatedRows;
  }

  Future<int> countBookTopics(int bookId) async {
    final db = await database;
    return firstIntValue(db.select(_queries['countBookTopics']!, [bookId])) ??
        0;
  }
}


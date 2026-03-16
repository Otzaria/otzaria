import 'package:sqlite3/sqlite3.dart' as sqlite3;
import '../../core/models/link.dart';
import '../sqflite/sqlite3_utils.dart';
import '../sqflite/query_loader.dart';
import 'database.dart';

class LinkDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  LinkDao(this._db) {
    _queries = QueryLoader.loadQueries('LinkQueries.sq');
  }

  Future<sqlite3.Database> get database => _db.database;

  Future<Link?> selectLinkById(int id) async {
    final db = await database;
    final result = db.select(_queries['selectLinkById']!, [id]).toMapList();
    if (result.isEmpty) return null;
    return _mapToLink(result.first);
  }

  Future<int> countAllLinks() async {
    final db = await database;
    return firstIntValue(db.select(_queries['countAllLinks']!)) ?? 0;
  }

  Future<List<Map<String, dynamic>>> selectLinksBySourceLineIds(
      List<int> lineIds) async {
    final db = await database;
    final placeholders = List.filled(lineIds.length, '?').join(',');
    final query =
        _queries['selectLinksBySourceLineIds']!.replaceFirst('?', placeholders);
    return db.select(query, lineIds).toMapList();
  }

  Future<List<Map<String, dynamic>>> selectLinksBySourceBook(int bookId) async {
    final db = await database;
    return db
        .select(_queries['selectLinksBySourceBook']!, [bookId]).toMapList();
  }

  Future<List<Map<String, dynamic>>> selectCommentatorsByBook(
      int bookId) async {
    final db = await database;
    return db
        .select(_queries['selectCommentatorsByBook']!, [bookId]).toMapList();
  }

  Future<int> insertLink(Link link, int connectionTypeId) async {
    final db = await database;
    db.execute(_queries['insert']!, [
      link.sourceBookId,
      link.targetBookId,
      link.sourceLineId,
      link.targetLineId,
      connectionTypeId
    ]);
    return db.lastInsertRowId;
  }

  Future<Link?> selectLinkByDetails(int sourceBookId, int targetBookId,
      int sourceLineId, int targetLineId) async {
    final db = await database;
    final result = db.select('''
      SELECT id FROM link
      WHERE sourceBookId = ? AND targetBookId = ? AND sourceLineId = ? AND targetLineId = ?
    ''', [sourceBookId, targetBookId, sourceLineId, targetLineId]).toMapList();

    if (result.isEmpty) return null;
    final linkId = result.first['id'] as int;
    return await selectLinkById(linkId);
  }

  Future<int> delete(int id) async {
    final db = await database;
    db.execute(_queries['delete']!, [id]);
    return db.updatedRows;
  }

  Future<int> deleteByBookId(int bookId) async {
    final db = await database;
    db.execute(_queries['deleteByBookId']!, [bookId, bookId]);
    return db.updatedRows;
  }

  Future<int> getLastInsertRowId() async {
    final db = await database;
    return db.lastInsertRowId;
  }

  Future<int> countLinksBySourceBook(int bookId) async {
    final db = await database;
    return firstIntValue(
            db.select(_queries['countLinksBySourceBook']!, [bookId])) ??
        0;
  }

  Future<int> countLinksByTargetBook(int bookId) async {
    final db = await database;
    return firstIntValue(
            db.select(_queries['countLinksByTargetBook']!, [bookId])) ??
        0;
  }

  Future<int> countLinksBySourceBookAndType(int bookId, String typeName) async {
    final db = await database;
    return firstIntValue(db.select(
            _queries['countLinksBySourceBookAndType']!, [bookId, typeName])) ??
        0;
  }

  Future<int> countLinksByTargetBookAndType(int bookId, String typeName) async {
    final db = await database;
    return firstIntValue(db.select(
            _queries['countLinksByTargetBookAndType']!, [bookId, typeName])) ??
        0;
  }

  Link _mapToLink(Map<String, dynamic> map) {
    return Link(
      id: map['id'] as int,
      sourceBookId: map['sourceBookId'] as int,
      targetBookId: map['targetBookId'] as int,
      sourceLineId: map['sourceLineId'] as int,
      targetLineId: map['targetLineId'] as int,
      connectionType:
          ConnectionType.fromString(map['connectionType'] as String),
    );
  }
}


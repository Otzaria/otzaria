import 'package:sqflite/sqflite.dart';
import '../../core/models/link.dart';
import '../sqflite/query_loader.dart';
import 'database.dart';

class LinkDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  LinkDao(this._db) {
    _queries = QueryLoader.loadQueries('LinkQueries.sq');
  }

  Future<Database> get database => _db.database;

  Future<Link?> selectLinkById(int id) async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectLinkById']!, [id]);
    if (result.isEmpty) return null;
    return _mapToLink(result.first);
  }

  Future<int> countAllLinks() async {
    final db = await database;
    final result = await db.rawQuery(_queries['countAllLinks']!);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<Map<String, dynamic>>> selectLinksBySourceLineIds(
      List<int> lineIds) async {
    final db = await database;
    final placeholders = List.filled(lineIds.length, '?').join(',');
    final query =
        _queries['selectLinksBySourceLineIds']!.replaceFirst('?', placeholders);
    return await db.rawQuery(query, lineIds);
  }

  Future<List<Map<String, dynamic>>> selectLinksBySourceBook(int bookId) async {
    final db = await database;
    return await db.rawQuery(_queries['selectLinksBySourceBook']!, [bookId]);
  }

  Future<List<Map<String, dynamic>>> selectCommentatorsByBook(
      int bookId) async {
    final db = await database;
    return await db.rawQuery(_queries['selectCommentatorsByBook']!, [bookId]);
  }

  Future<int> insertLink(Link link, int connectionTypeId) async {
    final db = await database;
    return await db.rawInsert(_queries['insert']!, [
      link.sourceBookId,
      link.targetBookId,
      link.sourceLineId,
      link.targetLineId,
      connectionTypeId
    ]);
  }

  Future<Link?> selectLinkByDetails(int sourceBookId, int targetBookId,
      int sourceLineId, int targetLineId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT id FROM link
      WHERE sourceBookId = ? AND targetBookId = ? AND sourceLineId = ? AND targetLineId = ?
    ''', [sourceBookId, targetBookId, sourceLineId, targetLineId]);

    if (result.isEmpty) return null;
    final linkId = result.first['id'] as int;
    return await selectLinkById(linkId);
  }

  Future<int> delete(int id) async {
    final db = await database;
    return await db.rawDelete(_queries['delete']!, [id]);
  }

  Future<int> deleteByBookId(int bookId) async {
    final db = await database;
    return await db.rawDelete(_queries['deleteByBookId']!, [bookId, bookId]);
  }

  Future<int> getLastInsertRowId() async {
    final db = await database;
    final result = await db.rawQuery(_queries['lastInsertRowId']!);
    return result.first.values.first as int;
  }

  Future<int> countLinksBySourceBook(int bookId) async {
    final db = await database;
    final result =
        await db.rawQuery(_queries['countLinksBySourceBook']!, [bookId]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> countLinksByTargetBook(int bookId) async {
    final db = await database;
    final result =
        await db.rawQuery(_queries['countLinksByTargetBook']!, [bookId]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> countLinksBySourceBookAndType(int bookId, String typeName) async {
    final db = await database;
    final result = await db.rawQuery(
        _queries['countLinksBySourceBookAndType']!, [bookId, typeName]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> countLinksByTargetBookAndType(int bookId, String typeName) async {
    final db = await database;
    final result = await db.rawQuery(
        _queries['countLinksByTargetBookAndType']!, [bookId, typeName]);
    return Sqflite.firstIntValue(result) ?? 0;
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

import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/data/data_providers/link_visibility_sql.dart';
import '../../models/link.dart';
import '../db_capabilities.dart';
import '../sqlite3_utils.dart';
import '../query_loader.dart';
import 'database.dart';

class LinkDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  LinkDao(this._db) {
    _queries = QueryLoader.loadQueries('LinkQueries.sq');
  }

  Future<sqlite3.Database> get database => _db.database;

  Future<DbCapabilities> get _capabilities => _db.capabilities;

  /// שאילתה עם מסנן הנראות, או null כשאין במסד קישורים.
  Future<String?> _visibilityAwareQuery(String queryName) async {
    final query = _queries[queryName]!;
    if (!query.contains(linkVisibilityFilterMarker)) {
      throw StateError('Missing visibility marker in $queryName');
    }
    final capabilities = await _capabilities;
    if (!capabilities.hasLinks) return null;
    return capabilities
        .adaptBookQuery(query)
        .replaceFirst(
          linkVisibilityFilterMarker,
          suppressedSideFilter(
            capabilities.hasLinkSuppressedSide,
            displayedSide: 0,
          ),
        );
  }

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
    List<int> lineIds,
  ) async {
    final db = await database;
    final placeholders = List.filled(lineIds.length, '?').join(',');
    final query = _queries['selectLinksBySourceLineIds']!.replaceFirst(
      '?',
      placeholders,
    );
    return db.select(query, lineIds).toMapList();
  }

  Future<List<Map<String, dynamic>>> selectLinksBySourceBook(int bookId) async {
    final db = await database;
    return db.select(_queries['selectLinksBySourceBook']!, [
      bookId,
    ]).toMapList();
  }

  Future<List<Map<String, dynamic>>> selectCommentatorsByBook(
    int bookId,
  ) async {
    final query = await _visibilityAwareQuery('selectCommentatorsByBook');
    if (query == null) return const [];
    final db = await database;
    return db.select(query, [bookId]).toMapList();
  }

  /// מחזיר את כל המפרשים על טווח שורות המקור [`startLineIndex`, `endLineIndex`)
  /// בספר [bookId], כולל `targetLineIndex` — ה-`lineIndex` הראשון בספר המפרש
  /// על פני הטווח. מאפשר ל-FindRef לאסוף את כל מפרשי הקטע (כותרת עד הכותרת
  /// הבאה) ולפתוח כל מפרש במיקום המקביל, ללא שאילתה נפרדת בעת הקליק.
  Future<List<Map<String, dynamic>>> selectCommentatorsByLineRange(
    int bookId,
    int startLineIndex,
    int endLineIndex,
  ) async {
    final query = await _visibilityAwareQuery('selectCommentatorsByLineRange');
    if (query == null) return const [];
    final db = await database;
    return db.select(
      query,
      [
        bookId,
        startLineIndex,
        endLineIndex,
      ],
    ).toMapList();
  }

  /// מחזיר את הקישורים למפרשים על טווח שורות המקור [`startLineIndex`,
  /// `endLineIndex`) בספר [bookId]. לכל מפרש מוחזרים `minTargetLineIndex`/
  /// `maxTargetLineIndex` (קצות הטווח) ו-`exactTargetLineIndex` (המיקום המקביל
  /// ל-[exactSourceLineIndex] המדויק, או NULL). [excludeBookId] הוא ספר המפרש
  /// הפתוח (מוחרג כדי לא להחזירו כ"מפרש נוסף" על עצמו).
  Future<List<Map<String, dynamic>>> selectCommentaryLinksByLineRange(
    int bookId,
    int startLineIndex,
    int endLineIndex,
    int excludeBookId,
    int exactSourceLineIndex,
  ) async {
    final query = await _visibilityAwareQuery(
      'selectCommentaryLinksByLineRange',
    );
    if (query == null) return const [];
    final db = await database;
    return db.select(
      query,
      [
        exactSourceLineIndex,
        bookId,
        startLineIndex,
        endLineIndex,
        excludeBookId,
      ],
    ).toMapList();
  }

  /// מחזיר את מפרשי ברירת המחדל של הספר [bookId], ממוינים לפי `position`.
  /// כל שורה: `targetBookTitle` (שם ספר המפרש) ו-`position`.
  Future<List<Map<String, dynamic>>> selectDefaultCommentators(
    int bookId,
  ) async {
    if (!(await _capabilities).hasDefaultCommentators) return const [];
    final db = await database;
    return db.select(_queries['selectDefaultCommentators']!, [
      bookId,
    ]).toMapList();
  }

  /// מחזיר את תרגומי ברירת המחדל של הספר [bookId], ממוינים לפי `position`.
  /// כל שורה: `targetBookTitle` (שם ספר התרגום) ו-`position`.
  Future<List<Map<String, dynamic>>> selectDefaultTargums(int bookId) async {
    if (!(await _capabilities).hasDefaultTargums) return const [];
    final db = await database;
    return db.select(_queries['selectDefaultTargums']!, [bookId]).toMapList();
  }

  Future<int> insertLink(Link link, int connectionTypeId) async {
    final db = await database;
    db.execute(_queries['insert']!, [
      link.sourceBookId,
      link.targetBookId,
      link.sourceLineId,
      link.targetLineId,
      connectionTypeId,
    ]);
    return db.lastInsertRowId;
  }

  Future<Link?> selectLinkByDetails(
    int sourceBookId,
    int targetBookId,
    int sourceLineId,
    int targetLineId,
  ) async {
    final db = await database;
    final result = db
        .select(
          '''
      SELECT id FROM link
      WHERE sourceBookId = ? AND targetBookId = ? AND sourceLineId = ? AND targetLineId = ?
    ''',
          [sourceBookId, targetBookId, sourceLineId, targetLineId],
        )
        .toMapList();

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
          db.select(_queries['countLinksBySourceBook']!, [bookId]),
        ) ??
        0;
  }

  Future<int> countLinksByTargetBook(int bookId) async {
    final db = await database;
    return firstIntValue(
          db.select(_queries['countLinksByTargetBook']!, [bookId]),
        ) ??
        0;
  }

  Future<int> countLinksBySourceBookAndType(int bookId, String typeName) async {
    final db = await database;
    return firstIntValue(
          db.select(_queries['countLinksBySourceBookAndType']!, [
            bookId,
            typeName,
          ]),
        ) ??
        0;
  }

  Future<int> countLinksByTargetBookAndType(int bookId, String typeName) async {
    final db = await database;
    return firstIntValue(
          db.select(_queries['countLinksByTargetBookAndType']!, [
            bookId,
            typeName,
          ]),
        ) ??
        0;
  }

  Link _mapToLink(Map<String, dynamic> map) {
    return Link(
      id: map['id'] as int,
      sourceBookId: map['sourceBookId'] as int,
      targetBookId: map['targetBookId'] as int,
      sourceLineId: map['sourceLineId'] as int,
      targetLineId: map['targetLineId'] as int,
      connectionType: ConnectionType.fromString(
        map['connectionType'] as String,
      ),
    );
  }
}

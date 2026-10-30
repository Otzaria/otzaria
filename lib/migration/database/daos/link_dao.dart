import 'dart:convert';

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

  /// גרסת Official מניחה את האינדקסים של seforim.db; במסד אחר היא סורקת את כל link.
  String _forDb(String queryName) =>
      _db.isOfficial ? '${queryName}Official' : queryName;

  /// A line-first join is best for a short window. As the window approaches a
  /// whole book it probes many lines, while the link-first query scans that
  /// book's links once. Both indexes exist only in the official database, so
  /// attached databases keep their original query.
  Future<String> _forLineRange(
    String queryName,
    int bookId,
    int startLineIndex,
    int endLineIndex,
  ) async {
    if (!_db.isOfficial || endLineIndex - startLineIndex <= 512) {
      return _forDb(queryName);
    }

    final db = await database;
    // Sparse books are faster link-first even for moderately short ranges.
    // This covering-index probe avoids reading line metadata for them.
    if (db.select(
      'SELECT 1 FROM link WHERE sourceBookId = ? LIMIT 1 OFFSET 31',
      [bookId],
    ).isEmpty) {
      return queryName;
    }

    final bounds = db.select(
      'SELECT (SELECT lineIndex FROM line WHERE bookId = ? '
      'ORDER BY lineIndex LIMIT 1) AS firstIdx, '
      '(SELECT lineIndex FROM line WHERE bookId = ? '
      'ORDER BY lineIndex DESC LIMIT 1) AS lastIdx',
      [bookId, bookId],
    ).first;
    final firstIndex = bounds['firstIdx'] as int?;
    final lastIndex = bounds['lastIdx'] as int?;
    if (firstIndex == null || lastIndex == null) {
      return '${queryName}Official';
    }
    // A whole-book range scans every line with the line-first join.
    if (startLineIndex <= firstIndex && endLineIndex > lastIndex) {
      return queryName;
    }

    // Official books normally number lines densely. Clipping index bounds
    // estimates the window in constant time; gaps can affect plan selection
    // but never the rows returned by either query.
    final clippedStart = startLineIndex > firstIndex
        ? startLineIndex
        : firstIndex;
    final clippedEnd = endLineIndex <= lastIndex ? endLineIndex : lastIndex + 1;
    final rangeWidth = clippedEnd > clippedStart
        ? clippedEnd - clippedStart
        : 0;
    if (rangeWidth <= 512) return '${queryName}Official';

    // Require more links as the range approaches a whole book. The bounded
    // probe uses the covering source-book index in both analyzed and older DBs.
    final bookSpan = lastIndex - firstIndex + 1;
    if (rangeWidth * 4 >= bookSpan * 3) return queryName;
    final minLinks =
        (rangeWidth * (bookSpan + 6 * rangeWidth) + 2 * bookSpan - 1) ~/
        (2 * bookSpan);
    final hasEnoughLinks = db.select(
      'SELECT 1 FROM link WHERE sourceBookId = ? LIMIT 1 OFFSET ?',
      [bookId, minLinks - 1],
    ).isNotEmpty;
    return hasEnoughLinks ? '${queryName}Official' : queryName;
  }

  /// שאילתה עם מסנן הנראות, או null כשאין במסד קישורים.
  Future<String?> _visibilityAwareQuery(
    String queryName, {
    DbCapabilities? capabilities,
  }) async {
    final query = _queries[queryName]!;
    if (!query.contains(linkVisibilityFilterMarker)) {
      throw StateError('Missing visibility marker in $queryName');
    }
    final dbCapabilities = capabilities ?? await _capabilities;
    if (!dbCapabilities.hasLinks) return null;
    return dbCapabilities
        .adaptBookQuery(query)
        .replaceFirst(
          linkVisibilityFilterMarker,
          suppressedSideFilter(
            dbCapabilities.hasLinkSuppressedSide,
            displayedSide: 0,
          ),
        );
  }

  Future<String?> _lineRangeQuery(
    String queryName,
    int bookId,
    int startLineIndex,
    int endLineIndex,
    DbCapabilities capabilities,
  ) async {
    final selectedName = await _forLineRange(
      queryName,
      bookId,
      startLineIndex,
      endLineIndex,
    );
    final query = await _visibilityAwareQuery(
      selectedName,
      capabilities: capabilities,
    );
    if (query == null || !_db.isOfficial || selectedName != queryName) {
      return query;
    }

    // On old official DBs without ANALYZE, SQLite otherwise visits each line
    // before checking whether a link has a commentary type. Fix only this
    // official link-first plan; attached databases retain their original SQL.
    const typeJoin = 'JOIN connection_type ct';
    const sourceLineJoin = 'JOIN line sl';
    if (!query.contains(typeJoin) || !query.contains(sourceLineJoin)) {
      throw StateError('Missing link-first joins in $queryName');
    }
    return query
        .replaceFirst(typeJoin, 'CROSS JOIN connection_type ct')
        .replaceFirst(sourceLineJoin, 'CROSS JOIN line sl');
  }

  Future<List<Map<String, dynamic>>> selectCommentatorsByBook(
    int bookId,
  ) async {
    final query = await _visibilityAwareQuery('selectCommentatorsByBook');
    if (query == null) return const [];
    final db = await database;
    return db.select(query, [bookId]).toMapList();
  }

  /// שם האוסף וספר הבסיס של כל ספר שכותרתו ב-[titles].
  Future<List<Map<String, dynamic>>> selectCommentatorIdentities(
    List<String> titles,
  ) async {
    final capabilities = await _capabilities;
    if (!capabilities.hasBooks || titles.isEmpty) return const [];
    final baseOrder = capabilities.hasColumn('book', 'isBaseBook')
        ? 'bb.isBaseBook DESC, bb.id'
        : 'bb.id';
    final baseBook = capabilities.has('book_base_text')
        ? '(SELECT bb.title FROM book_base_text t JOIN book bb '
              'ON bb.id = t.baseBookId WHERE t.bookId = b.id '
              'ORDER BY $baseOrder LIMIT 1)'
        : 'NULL';
    final db = await database;
    return db.select(
      'SELECT b.title AS title, '
      '${capabilities.column('book', 'collectiveTitleHe', qualifier: 'b')}, '
      '$baseBook AS baseBookTitle '
      'FROM book b WHERE b.title IN (SELECT value FROM json_each(?))',
      [jsonEncode(titles)],
    ).toMapList();
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
    final capabilities = await _capabilities;
    if (!capabilities.hasLinks) return const [];
    final query = await _lineRangeQuery(
      'selectCommentatorsByLineRange',
      bookId,
      startLineIndex,
      endLineIndex,
      capabilities,
    );
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
    final capabilities = await _capabilities;
    if (!capabilities.hasLinks) return const [];
    final query = await _lineRangeQuery(
      'selectCommentaryLinksByLineRange',
      bookId,
      startLineIndex,
      endLineIndex,
      capabilities,
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
}

import 'package:flutter/foundation.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_probe.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/migration/database/daos/line_ref_dao.dart';
import 'package:otzaria/migration/database/db_capabilities.dart';
import 'package:otzaria/migration/database/untrusted_database.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/utils/text/ref_key.dart';

/// מסד שאפשר לפתור בו יעד של `external_link` — ערכים פשוטים בלבד, כך שעובר
/// ל-isolate. [wireKey] הוא ה-wireKey של BookSource (`o` או `d:<slug>`);
/// [slug] null למסד הרשמי. [version] מזהה את תוכן המסד — שורות שנפתרו מולו
/// תקפות רק כל עוד הוא לא השתנה.
typedef ExternalTargetDb = ({
  String wireKey,
  String? slug,
  ReadOnlyDbTarget target,
  String version,
});

/// קישור חיצוני שיעדו נפתר לשורה במסד היעד.
typedef ResolvedExternalLink = ({
  int sourceBookId,
  String sourceTitle,
  int? sourceCategoryId,
  int sourceLineIndex,
  String? sourceHeRef,
  String targetWireKey,
  String targetTitle,
  int? targetCategoryId,
  int targetBookId,
  int targetLineIndex,
  String? targetHeRef,
  String connectionType,
});

/// הערך `external_link.targetSource` שמציין את הספרייה הרשמית.
const kExternalTargetOfficial = 'official';

/// סוג החיבור כפי שהוא נראה מצד היעד — אותו כלל של הקישור ההפוך ב-seforim.db:
/// מפרש מוצג בבסיסו כ'מקור', ו'מקור' מוצג בבסיס כמפרש.
String inverseExternalConnectionType(String connectionType) {
  if (LinkTypes.isDependentTextLink(connectionType)) return LinkTypes.source;
  if (LinkTypes.normalize(connectionType) == LinkTypes.source) {
    return LinkTypes.commentary;
  }
  return connectionType;
}

int? _int(Object? value) => value is int ? value : null;

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// נעילה זמנית, כולל קודי שגיאה מורחבים; אינה תוצאה ריקה שאפשר לשמור.
bool isTransientExternalLinkLock(Object error) =>
    error is sqlite3.SqliteException &&
    (error.resultCode == sqlite3.SqlError.SQLITE_BUSY ||
        error.resultCode == sqlite3.SqlError.SQLITE_LOCKED);

/// פותר יעדי `external_link` מול רשימת מסדי יעד. מחזיק את החיבורים פתוחים עד
/// [close], כך שסדרת שורות נפתרת בלי לפתוח את אותו מסד שוב ושוב.
class ExternalTargetResolver {
  ExternalTargetResolver(
    this.targets, {
    this.excludeWireKey,
    this.readHold = const Duration(milliseconds: 50),
  });

  final List<ExternalTargetDb> targets;

  /// המסד של ספר המקור — אינו יעד כשה-targetSource ריק.
  final String? excludeWireKey;

  final Map<String, (sqlite3.Database, DbCapabilities)?> _open = {};
  final Map<(String, String), List<(int, int?)>> _books = {};
  final Map<(String, String), sqlite3.PreparedStatement> _statements = {};

  /// תקרת השאילתות המוכנות שנשמרות — שאילתת ההפניה משתנה לפי ספרי הכותרת.
  static const maxCachedStatements = 64;

  /// מספר ההכנות של שאילתות פתרון — לוודא בבדיקות שהן אינן מוכנות לכל שורה.
  @visibleForTesting
  int preparedStatements = 0;

  /// ה-SQL האחרון של פתרון לפי הפניה — לוודא בבדיקות איזה נוסח נשלח בפועל.
  @visibleForTesting
  String? lastRefCandidatesSql;

  /// המסד שה-targetSource מצביע עליו; ריק (null בערך) — כל המסדים לפי הסדר.
  List<ExternalTargetDb> candidatesFor(String? targetSource) {
    final requested = _text(targetSource);
    if (requested == null) {
      return [
        for (final t in targets)
          if (t.wireKey != excludeWireKey) t,
      ];
    }
    if (requested.toLowerCase() == kExternalTargetOfficial) {
      return [
        for (final t in targets)
          if (t.slug == null) t,
      ];
    }
    // אותה נורמליזציה שבה נגזר ה-slug של המסד מ-library_id.
    final slug = AttachedLibraryProbe.sanitizeSlug(requested);
    return [
      for (final t in targets)
        if (t.slug != null && t.slug == slug) t,
    ];
  }

  (sqlite3.Database, DbCapabilities)? _connection(ExternalTargetDb target) {
    if (!_open.containsKey(target.wireKey)) {
      sqlite3.Database? db;
      try {
        db = openReadOnlyTarget(target.target);
        // קצר: כותב שממתין לנעילה מחזיק PENDING, ובו הקורא ממתין לו.
        db.execute('PRAGMA busy_timeout=$targetBusyTimeoutMs');
        _open[target.wireKey] = (db, DbCapabilities.probe(db));
      } catch (e) {
        db?.close();
        if (isTransientExternalLinkLock(e)) rethrow;
        _open[target.wireKey] = null;
      }
    }
    final connection = _open[target.wireKey];
    // שאילתה מחוץ לטרנזקציה נועלת את הקובץ ובודקת יומן — עשרות µs לכל אחת.
    if (connection != null && connection.$1.autocommit) {
      connection.$1.execute('BEGIN');
      if (!_readClock.isRunning) {
        _readClock
          ..reset()
          ..start();
      }
    }
    return connection;
  }

  /// תקציב החזקת הקריאה שנבדק בין שורות פתרון; שאילתה בודדת עשויה לחרוג ממנו.
  final Duration readHold;
  final Stopwatch _readClock = Stopwatch();

  static const targetBusyTimeoutMs = 300;

  /// משחרר את נעילת הקריאה על מסדי היעד; חובה לפני המתנה ארוכה (השהיית בנייה).
  void releaseReads() {
    _readClock.stop();
    for (final connection in _open.values) {
      final db = connection?.$1;
      if (db != null && !db.autocommit) db.execute('COMMIT');
    }
    _readClock.reset();
  }

  void _releaseExpiredReads() {
    if (_readClock.elapsed >= readHold) releaseReads();
  }

  /// תקרת הכותרות שנשמרות בזיכרון — מסד עוין עם מיליוני יעדים שונים.
  static const maxCachedTitles = 4096;

  List<(int, int?)> _booksByTitle(ExternalTargetDb target, String title) {
    final key = (target.wireKey, title);
    final cached = _books[key];
    if (cached != null) return cached;
    final books = _queryBooks(target, title);
    if (_books.length >= maxCachedTitles) _books.clear();
    return _books[key] = books;
  }

  List<(int, int?)> _queryBooks(ExternalTargetDb target, String title) {
    final connection = _connection(target);
    if (connection == null) return const [];
    final (db, caps) = connection;
    if (!caps.hasBooks) return const [];
    final category = caps.hasBookCategories ? 'categoryId' : 'NULL';
    try {
      return [
        for (final row in db.select(
          'SELECT id, $category AS categoryId FROM book WHERE title = ? '
          'ORDER BY id LIMIT 64',
          [title],
        ))
          if (_int(row['id']) != null)
            (row['id'] as int, _int(row['categoryId'])),
      ];
    } catch (e) {
      if (isTransientExternalLinkLock(e)) rethrow;
      // כשל קבוע נשמר כדי שמסד פגום לא יישאל מחדש לכל שורה.
      return const [];
    }
  }

  /// הכנת השאילתה יקרה מהרצתה, ובבניית האינדקס אותה שאילתה חוזרת לכל שורה.
  sqlite3.ResultSet _select(
    ExternalTargetDb target,
    sqlite3.Database db,
    String sql,
    List<Object?> parameters,
  ) {
    final key = (target.wireKey, sql);
    var statement = _statements.remove(key);
    if (statement == null) {
      statement = db.prepare(sql);
      preparedStatements++;
      if (_statements.length >= maxCachedStatements) {
        final oldest = _statements.keys.first;
        _statements.remove(oldest)!.close();
      }
    }
    _statements[key] = statement;
    return statement.select(parameters);
  }

  /// המסד הראשון מבין המועמדים שיש בו ספר בשם [targetTitle].
  ExternalTargetDb? bookDatabase(String? targetSource, String targetTitle) {
    for (final target in candidatesFor(targetSource)) {
      if (_booksByTitle(target, targetTitle).isNotEmpty) return target;
    }
    return null;
  }

  /// השורה שהקישור מצביע עליה: לפי [targetRef] דרך `line_ref` של מסד היעד,
  /// ואם אין — לפי [targetLineIndex]. null כשלא נפתר.
  ({
    ExternalTargetDb target,
    int bookId,
    int? categoryId,
    int lineIndex,
    String? heRef,
  })?
  resolve({
    required String? targetSource,
    required String targetTitle,
    required String? targetRef,
    required int? targetLineIndex,
  }) {
    _releaseExpiredReads();
    // הספר נמצא במסד הראשון — לא ממשיכים למסד אחר גם אם השורה לא נפתרה.
    final target = bookDatabase(targetSource, targetTitle);
    if (target == null) return null;
    try {
      return _resolveIn(target, targetTitle, targetRef, targetLineIndex);
    } catch (e) {
      if (isTransientExternalLinkLock(e)) rethrow;
      return null;
    }
  }

  ({
    ExternalTargetDb target,
    int bookId,
    int? categoryId,
    int lineIndex,
    String? heRef,
  })?
  _resolveIn(
    ExternalTargetDb target,
    String targetTitle,
    String? targetRef,
    int? targetLineIndex,
  ) {
    final books = _booksByTitle(target, targetTitle);
    final (db, caps) = _connection(target)!;
    final ref = _text(targetRef);
    if (ref != null &&
        caps.hasLineRef &&
        caps.hasColumn('line', 'heRef') &&
        caps.hasColumn('line_ref', 'refKeyHash')) {
      final hit = _byRef(
        target,
        db,
        books,
        targetTitle,
        ref,
        official: target.slug == null && !target.target.untrusted,
      );
      if (hit != null) {
        return (
          target: target,
          bookId: hit.$1,
          categoryId: hit.$2,
          lineIndex: hit.$3,
          heRef: hit.$4,
        );
      }
    }
    if (targetLineIndex != null && targetLineIndex >= 0 && caps.hasLines) {
      final (bookId, categoryId) = books.first;
      final heRef = caps.hasColumn('line', 'heRef') ? 'heRef' : 'NULL';
      final rows = _select(
        target,
        db,
        'SELECT $heRef AS heRef FROM line WHERE bookId = ? AND lineIndex = ? '
        'LIMIT 1',
        [bookId, targetLineIndex],
      );
      if (rows.isNotEmpty) {
        return (
          target: target,
          bookId: bookId,
          categoryId: categoryId,
          lineIndex: targetLineIndex,
          heRef: _text(rows.first['heRef']),
        );
      }
    }
    return null;
  }

  (int, int?, int, String?)? _byRef(
    ExternalTargetDb target,
    sqlite3.Database db,
    List<(int, int?)> books,
    String title,
    String ref, {
    required bool official,
  }) {
    final key = buildLineRefKey(ref, [title]);
    if (key == null) return null;
    final keyTokens = refKeyTokens(key);
    final categoryByBook = {for (final (id, cat) in books) id: cat};
    final sql = refCandidatesSql(categoryByBook.keys, official: official);
    lastRefCandidatesSql = sql;
    final rows = _select(target, db, sql, [refKeyHash(key)]);
    for (final row in rows) {
      final heRef = _text(row['heRef']);
      final bookId = _int(row['bookId']);
      final lineIndex = _int(row['lineIndex']);
      if (heRef == null || bookId == null || lineIndex == null) continue;
      // ה-hash לבדו אינו מספיק — טוקני המפתח חייבים להיות סיומת של ה-heRef.
      if (!endsWithRefKeyTokens(refKeyTokens(heRef), keyTokens)) continue;
      return (bookId, categoryByBook[bookId], lineIndex, heRef);
    }
    return null;
  }

  /// מסד מצורף עלול להיות בלי line.id, ולכן העמודות מצומצמות ל-heRef.
  @visibleForTesting
  static String refCandidatesSql(
    Iterable<int> bookIds, {
    required bool official,
  }) => LineRefDao.candidatesSql(
    bookIds,
    official: official,
    columns: 'lr.bookId, lr.lineIndex, l.heRef',
  );

  /// sqlite3_close_v2 מגלגל אחורה את טרנזקציית הקריאה הפתוחה בעצמו.
  void close() {
    for (final statement in _statements.values) {
      statement.close();
    }
    _statements.clear();
    for (final connection in _open.values) {
      connection?.$1.close();
    }
    _open.clear();
    _books.clear();
  }
}

/// קורא את שורות `external_link` של [source] ופותר את יעדיהן. [book] ו-
/// [lineRange] מצמצמים לספר ולטווח שורות; בלעדיהם — כל הטבלה (בניית האינדקס).
/// עם [onRow] כל שורה נמסרת לו מיד ואינה נצברת — הרשימה המוחזרת ריקה.
List<ResolvedExternalLink> readResolvedExternalLinks({
  required ReadOnlyDbTarget source,
  required String sourceWireKey,
  required List<ExternalTargetDb> targets,
  ({String title, int? categoryId})? book,
  (int, int)? lineRange,
  (int, int)? resumeFrom,
  int maxRows = kMaxExternalLinkRows,
  void Function(ResolvedExternalLink row)? onRow,
  void Function(VoidCallback releaseTargetReads)? onScanned,
}) {
  final db = openReadOnlyTarget(source);
  final resolver = ExternalTargetResolver(
    targets,
    excludeWireKey: sourceWireKey,
  );
  try {
    // מיון desktop יכול לגלוש לדיסק; ב-mobile נשמרת מדיניות החיבור.
    // Android אינו מבטיח temp ל-SQLite; שינוי נתיב גלובלי בחיבורים פעילים אינו בטוח.
    if (defaultTargetPlatform
        case TargetPlatform.windows ||
            TargetPlatform.linux ||
            TargetPlatform.macOS) {
      db.execute('PRAGMA temp_store=FILE');
    }
    final caps = DbCapabilities.probe(db);
    if (!caps.hasExternalLinks) return const [];
    int? bookId;
    if (book != null) {
      bookId = _selectBookId(db, caps, book.title, book.categoryId);
      if (bookId == null) return const [];
    }
    String col(String name) =>
        caps.column('external_link', name, qualifier: 'e');
    final category = caps.hasBookCategories ? 'b.categoryId' : 'NULL';
    final heRef = caps.hasLines && caps.hasColumn('line', 'heRef')
        ? '(SELECT heRef FROM line l WHERE l.bookId = e.sourceBookId '
              'AND l.lineIndex = e.sourceLineIndex LIMIT 1)'
        : 'NULL';
    // קריאה בזרם עם תקרה: מסד עוין או ענק לא ימלא את הזיכרון ויפיל את התהליך.
    final statement = db.prepare('''
      SELECT e.sourceBookId AS sourceBookId, e.sourceLineIndex AS sourceLineIndex,
        b.title AS sourceTitle, $category AS sourceCategoryId,
        $heRef AS sourceHeRef, e.targetTitle AS targetTitle,
        ${col('targetSource')}, ${col('targetRef')}, ${col('targetLineIndex')},
        ${col('connectionType')}
      FROM external_link e JOIN book b ON b.id = e.sourceBookId
      WHERE 1 = 1
        ${bookId != null ? 'AND e.sourceBookId = ?' : ''}
        ${lineRange != null ? 'AND e.sourceLineIndex BETWEEN ? AND ?' : ''}
        ${resumeFrom != null ? 'AND (e.sourceBookId, e.sourceLineIndex) >= (?, ?)' : ''}
      ORDER BY e.sourceBookId, e.sourceLineIndex
      LIMIT ?
      ''');
    final result = <ResolvedExternalLink>[];
    try {
      final cursor = statement.selectCursor([
        ?bookId,
        if (lineRange != null) ...[lineRange.$1, lineRange.$2],
        if (resumeFrom != null) ...[resumeFrom.$1, resumeFrom.$2],
        maxRows + 1,
      ]);
      var count = 0;
      while (cursor.moveNext()) {
        if (++count > maxRows) {
          throw const ExternalLinksTooLargeException();
        }
        final resolved = _resolveRow(cursor.current, resolver);
        if (resolved != null) {
          onRow != null ? onRow(resolved) : result.add(resolved);
        }
        onScanned?.call(resolver.releaseReads);
      }
    } finally {
      statement.close();
    }
    return result;
  } finally {
    resolver.close();
    db.close();
  }
}

/// תקרת השורות מ-`external_link` של מסד אחד; מעליה המסד מדולג. שומרת ממסד עוין
/// שמנפח את cache.db — מתחת למחצית ~11.4M הקישורים של הספרייה הרשמית.
const kMaxExternalLinkRows = 5000000;

/// תקרת הקישורים של ספר בודד בקריאה ישירה, שנצברים בזיכרון — פי ~4 מהספר
/// העשיר ביותר בספרייה הרשמית (~130K).
const kMaxExternalLinkRowsPerBook = 500000;

/// תקרת אורך לכותרת ולהפניה של יעד — ערך עוין ארוך אינו נשמר ואינו נפתר.
const kMaxExternalTextLength = 512;

/// `external_link` של המסד עובר את תקרת השורות.
class ExternalLinksTooLargeException implements Exception {
  const ExternalLinksTooLargeException();

  @override
  String toString() => 'external_link exceeds the row limit';
}

String? _boundedText(Object? value) {
  final text = _text(value);
  if (text == null || text.length <= kMaxExternalTextLength) return text;
  return text.substring(0, kMaxExternalTextLength);
}

ResolvedExternalLink? _resolveRow(
  sqlite3.Row row,
  ExternalTargetResolver resolver,
) {
  final sourceBook = _int(row['sourceBookId']);
  final sourceLine = _int(row['sourceLineIndex']);
  final sourceTitle = _boundedText(row['sourceTitle']);
  final targetTitle = _boundedText(row['targetTitle']);
  if (sourceBook == null ||
      sourceLine == null ||
      sourceTitle == null ||
      targetTitle == null) {
    resolver._releaseExpiredReads();
    return null;
  }
  final resolved = resolver.resolve(
    targetSource: _boundedText(row['targetSource']),
    targetTitle: targetTitle,
    targetRef: _boundedText(row['targetRef']),
    targetLineIndex: _int(row['targetLineIndex']),
  );
  if (resolved == null) return null;
  final type = LinkTypes.normalize(_boundedText(row['connectionType']));
  return (
    sourceBookId: sourceBook,
    sourceTitle: sourceTitle,
    sourceCategoryId: _int(row['sourceCategoryId']),
    sourceLineIndex: sourceLine,
    sourceHeRef: _boundedText(row['sourceHeRef']),
    targetWireKey: resolved.target.wireKey,
    targetTitle: targetTitle,
    targetCategoryId: resolved.categoryId,
    targetBookId: resolved.bookId,
    targetLineIndex: resolved.lineIndex,
    targetHeRef: _boundedText(resolved.heRef),
    connectionType: type.isEmpty ? LinkTypes.reference : type,
  );
}

int? _selectBookId(
  sqlite3.Database db,
  DbCapabilities caps,
  String title,
  int? categoryId,
) {
  final byCategory = categoryId != null && caps.hasBookCategories;
  final rows = db.select(
    byCategory
        ? 'SELECT id FROM book WHERE title = ? AND categoryId = ? '
              'ORDER BY id LIMIT 1'
        : 'SELECT id FROM book WHERE title = ? ORDER BY id LIMIT 1',
    [title, if (byCategory) categoryId],
  );
  return rows.isEmpty ? null : _int(rows.first['id']);
}

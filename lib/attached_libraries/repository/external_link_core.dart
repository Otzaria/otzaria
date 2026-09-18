import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
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

/// פותר יעדי `external_link` מול רשימת מסדי יעד. מחזיק את החיבורים פתוחים עד
/// [close], כך שסדרת שורות נפתרת בלי לפתוח את אותו מסד שוב ושוב.
class ExternalTargetResolver {
  ExternalTargetResolver(this.targets, {this.excludeWireKey});

  final List<ExternalTargetDb> targets;

  /// המסד של ספר המקור — אינו יעד כשה-targetSource ריק.
  final String? excludeWireKey;

  final Map<String, (sqlite3.Database, DbCapabilities)?> _open = {};
  final Map<(String, String), List<(int, int?)>> _books = {};

  /// המסד שה-targetSource מצביע עליו; ריק (null בערך) — כל המסדים לפי הסדר.
  List<ExternalTargetDb> candidatesFor(String? targetSource) {
    final requested = _text(targetSource);
    if (requested == null) {
      return [
        for (final t in targets)
          if (t.wireKey != excludeWireKey) t,
      ];
    }
    final lower = requested.toLowerCase();
    if (lower == kExternalTargetOfficial) {
      return [
        for (final t in targets)
          if (t.slug == null) t,
      ];
    }
    return [
      for (final t in targets)
        if (t.slug != null && t.slug == lower) t,
    ];
  }

  (sqlite3.Database, DbCapabilities)? _connection(ExternalTargetDb target) {
    return _open.putIfAbsent(target.wireKey, () {
      try {
        final db = openReadOnlyTarget(target.target);
        return (db, DbCapabilities.probe(db));
      } catch (_) {
        return null;
      }
    });
  }

  List<(int, int?)> _booksByTitle(ExternalTargetDb target, String title) {
    return _books.putIfAbsent((target.wireKey, title), () {
      final connection = _connection(target);
      if (connection == null) return const [];
      final (db, caps) = connection;
      if (!caps.hasBooks) return const [];
      final category = caps.hasBookCategories ? 'categoryId' : 'NULL';
      return [
        for (final row in db.select(
          'SELECT id, $category AS categoryId FROM book WHERE title = ? '
          'ORDER BY id',
          [title],
        ))
          if (_int(row['id']) != null)
            (row['id'] as int, _int(row['categoryId'])),
      ];
    });
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
    // הספר נמצא במסד הראשון — לא ממשיכים למסד אחר גם אם השורה לא נפתרה.
    final target = bookDatabase(targetSource, targetTitle);
    if (target == null) return null;
    final books = _booksByTitle(target, targetTitle);
    final (db, caps) = _connection(target)!;
    final ref = _text(targetRef);
    if (ref != null && caps.hasLineRef) {
      final hit = _byRef(db, books, targetTitle, ref);
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
      final rows = db.select(
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
    sqlite3.Database db,
    List<(int, int?)> books,
    String title,
    String ref,
  ) {
    final key = buildLineRefKey(ref, [title]);
    if (key == null) return null;
    final keyTokens = refKeyTokens(key);
    final categoryByBook = {for (final (id, cat) in books) id: cat};
    final ids = categoryByBook.keys.join(',');
    final rows = db.select(
      'SELECT lr.bookId, lr.lineIndex, l.heRef FROM line_ref lr '
      'JOIN line l ON l.bookId = lr.bookId AND l.lineIndex = lr.lineIndex '
      'WHERE lr.refKeyHash = ? AND lr.bookId IN ($ids) '
      'ORDER BY lr.bookId, lr.lineIndex',
      [refKeyHash(key)],
    );
    for (final row in rows) {
      final heRef = _text(row['heRef']);
      final bookId = _int(row['bookId']);
      final lineIndex = _int(row['lineIndex']);
      if (heRef == null || bookId == null || lineIndex == null) continue;
      // ה-hash לבדו אינו מספיק — טוקני המפתח חייבים להיות סיומת של ה-heRef.
      if (!_endsWith(refKeyTokens(heRef), keyTokens)) continue;
      return (bookId, categoryByBook[bookId], lineIndex, heRef);
    }
    return null;
  }

  static bool _endsWith(List<String> tokens, List<String> suffix) {
    if (suffix.isEmpty || suffix.length > tokens.length) return false;
    final offset = tokens.length - suffix.length;
    for (var i = 0; i < suffix.length; i++) {
      if (tokens[offset + i] != suffix[i]) return false;
    }
    return true;
  }

  void close() {
    for (final connection in _open.values) {
      connection?.$1.close();
    }
    _open.clear();
    _books.clear();
  }
}

/// קורא את שורות `external_link` של [source] ופותר את יעדיהן. [bookId] ו-
/// [lineRange] מצמצמים לספר ולטווח שורות; בלעדיהם — כל הטבלה (בניית האינדקס).
List<ResolvedExternalLink> readResolvedExternalLinks({
  required ReadOnlyDbTarget source,
  required String sourceWireKey,
  required List<ExternalTargetDb> targets,
  ({String title, int? categoryId})? book,
  (int, int)? lineRange,
}) {
  final db = openReadOnlyTarget(source);
  final resolver = ExternalTargetResolver(
    targets,
    excludeWireKey: sourceWireKey,
  );
  try {
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
    final rows = db.select(
      '''
      SELECT e.sourceBookId AS sourceBookId, e.sourceLineIndex AS sourceLineIndex,
        b.title AS sourceTitle, $category AS sourceCategoryId,
        $heRef AS sourceHeRef, e.targetTitle AS targetTitle,
        ${col('targetSource')}, ${col('targetRef')}, ${col('targetLineIndex')},
        ${col('connectionType')}
      FROM external_link e JOIN book b ON b.id = e.sourceBookId
      WHERE 1 = 1
        ${bookId != null ? 'AND e.sourceBookId = ?' : ''}
        ${lineRange != null ? 'AND e.sourceLineIndex BETWEEN ? AND ?' : ''}
      ORDER BY e.sourceBookId, e.sourceLineIndex
      ''',
      [
        ?bookId,
        if (lineRange != null) ...[lineRange.$1, lineRange.$2],
      ],
    );

    final result = <ResolvedExternalLink>[];
    for (final row in rows) {
      final sourceBook = _int(row['sourceBookId']);
      final sourceLine = _int(row['sourceLineIndex']);
      final sourceTitle = _text(row['sourceTitle']);
      final targetTitle = _text(row['targetTitle']);
      if (sourceBook == null ||
          sourceLine == null ||
          sourceTitle == null ||
          targetTitle == null) {
        continue;
      }
      final resolved = resolver.resolve(
        targetSource: _text(row['targetSource']),
        targetTitle: targetTitle,
        targetRef: _text(row['targetRef']),
        targetLineIndex: _int(row['targetLineIndex']),
      );
      if (resolved == null) continue;
      final type = LinkTypes.normalize(_text(row['connectionType']));
      result.add((
        sourceBookId: sourceBook,
        sourceTitle: sourceTitle,
        sourceCategoryId: _int(row['sourceCategoryId']),
        sourceLineIndex: sourceLine,
        sourceHeRef: _text(row['sourceHeRef']),
        targetWireKey: resolved.target.wireKey,
        targetTitle: targetTitle,
        targetCategoryId: resolved.categoryId,
        targetBookId: resolved.bookId,
        targetLineIndex: resolved.lineIndex,
        targetHeRef: resolved.heRef,
        connectionType: type.isEmpty ? LinkTypes.reference : type,
      ));
    }
    return result;
  } finally {
    resolver.close();
    db.close();
  }
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
        ? 'SELECT id FROM book WHERE title = ? AND categoryId = ? LIMIT 1'
        : 'SELECT id FROM book WHERE title = ? LIMIT 1',
    [title, if (byCategory) categoryId],
  );
  return rows.isEmpty ? null : _int(rows.first['id']);
}

/// היעדים שספר [book] במסד [source] מקושר אליהם ב-`external_link`, ברמת ספר
/// בלבד (בלי פתרון שורות) — לבניית רשימת המפרשים.
List<({String targetTitle, String targetWireKey, String connectionType})>
readExternalLinkTargets({
  required ReadOnlyDbTarget source,
  required String sourceWireKey,
  required List<ExternalTargetDb> targets,
  required String title,
  required int? categoryId,
}) {
  final db = openReadOnlyTarget(source);
  final resolver = ExternalTargetResolver(
    targets,
    excludeWireKey: sourceWireKey,
  );
  try {
    final caps = DbCapabilities.probe(db);
    if (!caps.hasExternalLinks) return const [];
    final bookId = _selectBookId(db, caps, title, categoryId);
    if (bookId == null) return const [];
    final rows = db.select(
      'SELECT DISTINCT ${caps.column('external_link', 'targetSource')}, '
      'targetTitle, ${caps.column('external_link', 'connectionType')} '
      'FROM external_link WHERE sourceBookId = ?',
      [bookId],
    );
    final result =
        <({String targetTitle, String targetWireKey, String connectionType})>[];
    for (final row in rows) {
      final targetTitle = _text(row['targetTitle']);
      if (targetTitle == null) continue;
      final target = resolver.bookDatabase(
        _text(row['targetSource']),
        targetTitle,
      );
      if (target == null) continue;
      final type = LinkTypes.normalize(_text(row['connectionType']));
      result.add((
        targetTitle: targetTitle,
        targetWireKey: target.wireKey,
        connectionType: type.isEmpty ? LinkTypes.reference : type,
      ));
    }
    return result;
  } finally {
    resolver.close();
    db.close();
  }
}

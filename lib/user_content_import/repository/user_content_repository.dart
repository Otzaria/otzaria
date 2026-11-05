import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/sqlite3_utils.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/user_content_import/models/user_import_models.dart';
import 'package:otzaria/user_content_import/services/user_headings_builder.dart';
import 'package:path/path.dart' as p;

/// גישת כתיבה/קריאה לנתוני-המשתמש ב-user_books.db: דור הספר (book_generation)
/// וקישורי-משתמש מיובאים (user_link).
///
/// משתמש ב-SQL ישיר על אותו [MyDatabase] של user_books.db (writable).
class UserContentRepository {
  final MyDatabase _db;
  bool _seeded = false;

  UserContentRepository(this._db);

  /// מוחק את כל נתוני-הייבוא (דור + קישורים). ב-user_books.db טבלאות אלה
  /// מנוהלות אך ורק ע"י הייבוא, לכן בטוח לרוקן. משמש את פעולת "נקה הכל"
  /// (הייבוא עצמו מצטבר ואינו מנקה).
  Future<void> clearAllUserContent() async {
    final db = await _db.database;
    db.execute('DELETE FROM book_generation');
    // רק ייבוא ידני: קישורים עם source שייכים לתיקיית הספרים, ומחיקתם כאן
    // הייתה מעלימה אותם עד הסריקה הבאה.
    db.execute('DELETE FROM user_link WHERE source IS NULL');
    db.execute('DELETE FROM book_author');
    db.execute('DELETE FROM author');
    // כותרות וגרסאות מקובצי התיקייה אינן "מיובאות" — הן חוזרות בסריקה הבאה.
    await forgetSidecar(manualImportSource);
  }

  /// מה ש-[clearAllUserContent] מוחק, לפי טבלה, בסדר שמכבד את התלויות.
  static const Map<String, String> _manualContentFilters = {
    'book_generation': '1',
    'author': '1',
    'book_author': '1',
    'user_link': 'source IS NULL',
    'user_alt_toc_structure': "source = '$manualImportSource'",
    'user_alt_toc_entry':
        'structureId IN (SELECT id FROM user_alt_toc_structure '
        "WHERE source = '$manualImportSource')",
    'user_book_version': "source = '$manualImportSource'",
  };

  static String _baselineTable(String table) => 'import_baseline_$table';

  /// שומר את הנתונים הידניים הקיימים כבסיס שכל בנייה מחדש משחזרת. כך ייבוא
  /// מגרסה שקדמה לספריית הקבצים אינו נמחק כשנוסף אליה הקובץ הראשון.
  Future<void> captureManualBaseline() async {
    final db = await _db.database;
    for (final MapEntry(key: table, value: filter)
        in _manualContentFilters.entries) {
      final baseline = _baselineTable(table);
      db.execute('DROP TABLE IF EXISTS $baseline');
      db.execute(
        'CREATE TABLE $baseline AS SELECT * FROM $table WHERE $filter',
      );
    }
  }

  /// מחזיר את הבסיס שנשמר ב-[captureManualBaseline], אם נשמר. ⚠️ OR IGNORE:
  /// קובץ תיקייה שכתב מאז את אותו ספר מנצח, אחרת השחזור נופל על מפתח ייחודי.
  Future<void> restoreManualBaseline() async {
    final db = await _db.database;
    for (final table in _manualContentFilters.keys) {
      final baseline = _baselineTable(table);
      final baselineColumns = _columns(db, baseline);
      if (baselineColumns.isEmpty) continue;
      // רק העמודות המשותפות: שדרוג סכמה אחרי השמירה מוסיף עמודות ליעד.
      final columns = _columns(
        db,
        table,
      ).where(baselineColumns.contains).join(', ');
      // ערכים רק של מבנים שהוחזרו בפועל, אחרת נשארים יתומים.
      final where = table == 'user_alt_toc_entry'
          ? ' WHERE structureId IN (SELECT id FROM user_alt_toc_structure '
                "WHERE source = '$manualImportSource')"
          : '';
      db.execute(
        'INSERT OR IGNORE INTO $table ($columns) '
        'SELECT $columns FROM $baseline$where',
      );
    }
  }

  Future<void> dropManualBaseline() async {
    final db = await _db.database;
    for (final table in _manualContentFilters.keys) {
      db.execute('DROP TABLE IF EXISTS ${_baselineTable(table)}');
    }
  }

  static List<String> _columns(sqlite3.Database db, String table) => [
    for (final row in db.select('PRAGMA table_info($table)'))
      row['name'] as String,
  ];

  // ---- דורות ----

  /// מוסיף את שמות הדורות הקנוניים (idempotent). מבוצע פעם אחת לכל instance —
  /// קריאות חוזרות (למשל מכל setBookGeneration) הן no-op.
  Future<void> seedCanonicalGenerations() async {
    if (_seeded) return;
    final db = await _db.database;
    for (final name in kCanonicalEraNames) {
      db.execute('INSERT OR IGNORE INTO generation (name) VALUES (?)', [name]);
    }
    _seeded = true;
  }

  Future<int?> generationIdByName(String name) async {
    final db = await _db.database;
    final rows = db.select('SELECT id FROM generation WHERE name = ? LIMIT 1', [
      name,
    ]);
    return rows.isEmpty ? null : rows.first['id'] as int;
  }

  Future<int?> bookIdByTitle(String title, {int? categoryId}) async {
    final db = await _db.database;
    final rows = categoryId != null
        ? db.select(
            'SELECT id FROM book WHERE title = ? AND categoryId = ? LIMIT 1',
            [title, categoryId],
          )
        : db.select('SELECT id FROM book WHERE title = ? LIMIT 1', [title]);
    return rows.isEmpty ? null : rows.first['id'] as int;
  }

  /// קובע את דור הספר לפי שם דור קנוני (מחליף דור קודם — idempotent).
  Future<void> setBookGeneration(int bookId, String eraName) async {
    await seedCanonicalGenerations();
    final genId = await generationIdByName(eraName);
    if (genId == null) return;
    final db = await _db.database;
    db.execute('DELETE FROM book_generation WHERE bookId = ?', [bookId]);
    db.execute(
      'INSERT INTO book_generation (bookId, generationId) VALUES (?, ?)',
      [bookId, genId],
    );
  }

  /// קובע את מחבר הספר (מחליף מחבר קודם — idempotent). המחבר מוזרם משם
  /// ל-`book.author` ומשתתף באיתור בספרייה (issue #1082).
  Future<void> setBookAuthor(int bookId, String authorName) async {
    final db = await _db.database;
    db.execute('INSERT OR IGNORE INTO author (name) VALUES (?)', [authorName]);
    final authorId =
        db.select('SELECT id FROM author WHERE name = ? LIMIT 1', [
              authorName,
            ]).first['id']
            as int;
    db.execute('DELETE FROM book_author WHERE bookId = ?', [bookId]);
    db.execute('INSERT INTO book_author (bookId, authorId) VALUES (?, ?)', [
      bookId,
      authorId,
    ]);
  }

  // ---- כותרות וגרסאות ----

  /// המקור של נתונים שיובאו מדיאלוג ההגדרות (ולא מקובץ שבתיקיית הספרים).
  static const manualImportSource = 'import';

  /// כותב מחדש את כל מבני הכותרות של [bookId] שמקורם ב-[source].
  Future<void> replaceBookHeadings(
    int bookId,
    List<UserAltTocStructureData> structures, {
    required String source,
  }) async {
    final db = await _db.database;
    db.execute(
      'DELETE FROM user_alt_toc_entry WHERE structureId IN '
      '(SELECT id FROM user_alt_toc_structure WHERE bookId = ? AND source = ?)',
      [bookId, source],
    );
    db.execute(
      'DELETE FROM user_alt_toc_structure WHERE bookId = ? AND source = ?',
      [bookId, source],
    );

    for (var position = 0; position < structures.length; position++) {
      final structure = structures[position];
      // מבנה באותו שם ממקור אחר נדרס — יחד עם ערכיו, שאחרת היו מתייתמים.
      db.execute(
        'DELETE FROM user_alt_toc_entry WHERE structureId IN '
        '(SELECT id FROM user_alt_toc_structure WHERE bookId = ? AND key = ?)',
        [bookId, structure.key],
      );
      db.execute(
        'DELETE FROM user_alt_toc_structure WHERE bookId = ? AND key = ?',
        [bookId, structure.key],
      );
      db.execute(
        'INSERT INTO user_alt_toc_structure '
        '(bookId, key, heTitle, position, source) VALUES (?, ?, ?, ?, ?)',
        [bookId, structure.key, structure.heTitle, position, source],
      );
      final structureId = db.lastInsertRowId;
      final ids = <int>[];
      for (final entry in structure.entries) {
        db.execute(
          'INSERT INTO user_alt_toc_entry '
          '(structureId, parentId, level, text, lineIndex, isLastChild, hasChildren) '
          'VALUES (?, ?, ?, ?, ?, ?, ?)',
          [
            structureId,
            entry.parentIndex == null ? null : ids[entry.parentIndex!],
            entry.level,
            entry.text,
            entry.lineIndex,
            entry.isLastChild ? 1 : 0,
            entry.hasChildren ? 1 : 0,
          ],
        );
        ids.add(db.lastInsertRowId);
      }
    }
  }

  /// כותב מחדש את כל רשומות הגרסאות שמקורן ב-[source].
  Future<void> replaceVersions(
    List<UserBookVersionRecord> versions, {
    required String source,
  }) async {
    final db = await _db.database;
    db.execute('DELETE FROM user_book_version WHERE source = ?', [source]);
    for (final version in versions) {
      db.execute(
        'INSERT OR REPLACE INTO user_book_version '
        '(versionBookId, primaryBookId, primarySource, primaryTitle, '
        'primaryCategoryPath, versionTitle, versionNotes, priority, source) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          version.versionBookId,
          version.primaryBookId,
          version.primarySource.wireKey,
          version.primaryTitle,
          version.primaryCategoryPath,
          version.versionTitle,
          version.versionNotes,
          version.priority,
          source,
        ],
      );
    }
  }

  /// מוחק את כל מה שנקלט מקובץ [source] (כותרות, גרסאות וקישורים), ואת רישום
  /// המעקב שלו.
  Future<void> forgetSidecar(String source) async {
    final db = await _db.database;
    db.execute(
      'DELETE FROM user_alt_toc_entry WHERE structureId IN '
      '(SELECT id FROM user_alt_toc_structure WHERE source = ?)',
      [source],
    );
    db.execute('DELETE FROM user_alt_toc_structure WHERE source = ?', [source]);
    db.execute('DELETE FROM user_book_version WHERE source = ?', [source]);
    db.execute('DELETE FROM user_link WHERE source = ?', [source]);
    db.execute('DELETE FROM user_sidecar_link_book WHERE path = ?', [source]);
    db.execute('DELETE FROM user_sidecar_file WHERE path = ?', [source]);
  }

  /// חתימת היישום האחרון של קובץ נלווה, או null אם מעולם לא יושם.
  Future<String?> sidecarSignature(String path) async {
    final db = await _db.database;
    final rows = db.select(
      'SELECT signature FROM user_sidecar_file WHERE path = ? LIMIT 1',
      [path],
    );
    return rows.isEmpty ? null : rows.first['signature'] as String;
  }

  /// מצב הספרים האישיים בכותרות שקובץ הקישורים מזכיר.
  /// גם הופעת ספר אישי בכותרת שהייתה רשמית מבטלת את החתימה.
  Future<String> sidecarLinkBookSignature(String source) async {
    final db = await _db.database;
    final rows = db.select(
      '''
      SELECT d.title, d.categoryId, b.id, b.lastModified, b.totalLines
      FROM user_sidecar_link_book d LEFT JOIN book b
        ON b.title = d.title
        AND (d.categoryId = -1 OR b.categoryId = d.categoryId)
      WHERE d.path = ?
      ORDER BY d.title, d.categoryId, b.id
    ''',
      [source],
    );
    final state = jsonEncode([
      for (final row in rows)
        [
          row['title'],
          row['categoryId'],
          row['id'],
          row['lastModified'],
          row['totalLines'],
        ],
    ]);
    return sha256.convert(utf8.encode(state)).toString();
  }

  /// מעדכן רק בעת קליטת קובץ; בדיקת חתימה בסריקות הבאות קוראת רשימה מצומצמת.
  Future<void> replaceSidecarLinkBookDependencies(String source) async {
    final db = await _db.database;
    db.execute('DELETE FROM user_sidecar_link_book WHERE path = ?', [source]);
    db.execute(
      '''
      INSERT INTO user_sidecar_link_book (path, title, categoryId)
      SELECT ?, title, -1 FROM (
        SELECT sourceTitle AS title
        FROM user_link WHERE source = ?
        UNION
        SELECT targetTitle AS title
        FROM user_link WHERE source = ?
      )
    ''',
      [source, source, source],
    );
  }

  Future<void> setSidecarSignature(String path, String signature) async {
    final db = await _db.database;
    db.execute(
      'INSERT OR REPLACE INTO user_sidecar_file (path, signature) VALUES (?, ?)',
      [path, signature],
    );
  }

  /// נתיבי הקבצים הנלווים שכבר יושמו ויושבים תחת [folderPath].
  Future<List<String>> trackedSidecarsUnder(String folderPath) async {
    final db = await _db.database;
    // ⚠️ בלי המפריד "C:\ספרים" תופס גם את "C:\ספרים2", וסריקת האחת הייתה
    // שוכחת — ומוחקת את קישוריהם של — הקבצים הנלווים של השנייה.
    final prefix = folderPath.endsWith('/') || folderPath.endsWith('\\')
        ? folderPath
        : '$folderPath${p.separator}';
    final rows = db.select(
      "SELECT path FROM user_sidecar_file WHERE path LIKE ? ESCAPE '\\'",
      ['${escapeLike(prefix)}%'],
    );
    return [for (final row in rows) row['path'] as String];
  }

  /// ספר אישי לפי כותרת (ואם צוינה — קטגוריה), עם נתיב הקובץ שלו.
  Future<({int id, String? filePath, String? fileType, int lastModified})?>
  bookFileByTitle(String title, {int? categoryId}) async {
    final db = await _db.database;
    final rows = categoryId != null
        ? db.select(
            'SELECT id, filePath, fileType, lastModified FROM book '
            'WHERE title = ? AND categoryId = ? LIMIT 1',
            [title, categoryId],
          )
        : db.select(
            'SELECT id, filePath, fileType, lastModified FROM book '
            'WHERE title = ? LIMIT 1',
            [title],
          );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return (
      id: row['id'] as int,
      filePath: row['filePath'] as String?,
      fileType: row['fileType'] as String?,
      lastModified: row['lastModified'] as int? ?? 0,
    );
  }

  /// ספר אישי לפי נתיב הקובץ שלו.
  Future<({int id, String? fileType, int lastModified})?> bookByFilePath(
    String filePath,
  ) async {
    final db = await _db.database;
    final rows = db.select(
      'SELECT id, fileType, lastModified FROM book WHERE filePath = ? LIMIT 1',
      [filePath],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return (
      id: row['id'] as int,
      fileType: row['fileType'] as String?,
      lastModified: row['lastModified'] as int? ?? 0,
    );
  }

  // ---- קישורי-משתמש ----

  /// מוסיף קישור-משתמש, או דורס קישור זהה אם כבר קיים. שני קישורים נחשבים
  /// "זהים" כשכל שדות הזיהוי שווים (מקור, שורת-מקור, יעד ומיקומו) — targetRef
  /// הוא תצוגה בלבד ואינו חלק מהזהות. כך ייבוא חוזר מצטבר ואינו מכפיל.
  Future<void> upsertUserLink(UserLinkRecord link, {String? source}) async {
    final db = await _db.database;
    _deleteUserLinksAt(db, link, source);
    _insertUserLink(db, link, source);
  }

  /// כל צמד-שורות נמחק *פעם אחת* ואז נכתבות כל רשומותיו. ב-[upsertUserLink]
  /// לבדו, הרשומה השנייה של צמד רב-עוגנים הייתה מוחקת את הראשונה.
  Future<void> replaceUserLinks(
    Iterable<UserLinkRecord> links, {
    String? source,
  }) async {
    final db = await _db.database;
    // קובץ תיקייה מגדיר את קישוריו במלואם: כל מה שהיה ממנו יורד, ואז נכתב
    // מה שיש בו עכשיו. בייבוא ידני (source == null) הכתיבה נשארת מצטברת.
    if (source != null) {
      db.execute('DELETE FROM user_link WHERE source = ?', [source]);
    }
    // כשהמקור כבר נמחק במלואו, אין צמד לנקות.
    final cleared = <String>{};
    for (final link in links) {
      if (source != null) {
        _insertUserLink(db, link, source);
        continue;
      }
      final key = [
        link.sourceTitle,
        link.sourceIsUserBook,
        link.sourceCategoryId,
        link.sourceLineIndex,
        link.targetTitle,
        link.targetIsUserBook,
        link.targetCategoryId,
        link.targetLineIndex,
      ].join('|');
      if (cleared.add(key)) _deleteUserLinksAt(db, link, source);
      _insertUserLink(db, link, source);
    }
  }

  /// מוחק את קישורי הצמד של [link] *מאותו [source]*. IS ולא =, כדי ש-NULL
  /// ישווה ל-NULL; כפילות בין מקורות מתמזגת בתצוגה ב-`dedupeUserLinks`.
  void _deleteUserLinksAt(
    sqlite3.Database db,
    UserLinkRecord link,
    String? source,
  ) {
    db.execute(
      'DELETE FROM user_link WHERE sourceTitle = ? AND sourceIsUserBook = ? '
      'AND sourceCategoryId IS ? AND sourceLineIndex = ? '
      'AND targetTitle = ? AND targetIsUserBook = ? AND targetCategoryId IS ? '
      'AND targetLineIndex IS ? AND source IS ?',
      [
        link.sourceTitle,
        link.sourceIsUserBook ? 1 : 0,
        link.sourceCategoryId,
        link.sourceLineIndex,
        link.targetTitle,
        link.targetIsUserBook ? 1 : 0,
        link.targetCategoryId,
        link.targetLineIndex,
        source,
      ],
    );
  }

  void _insertUserLink(
    sqlite3.Database db,
    UserLinkRecord link,
    String? source,
  ) {
    db.execute(
      'INSERT INTO user_link (sourceTitle, sourceCategoryId, sourceIsUserBook, '
      'sourceLineIndex, targetTitle, targetCategoryId, targetIsUserBook, '
      'targetRef, targetLineIndex, anchorStart, anchorEnd, anchorLabel, '
      'sourceLineIndexEnd, targetLineIndexEnd, targetRefEnd, connectionType, '
      'source) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        link.sourceTitle,
        link.sourceCategoryId,
        link.sourceIsUserBook ? 1 : 0,
        link.sourceLineIndex,
        link.targetTitle,
        link.targetCategoryId,
        link.targetIsUserBook ? 1 : 0,
        link.targetRef,
        link.targetLineIndex,
        link.anchorStart,
        link.anchorEnd,
        link.anchorLabel,
        link.sourceLineIndexEnd,
        link.targetLineIndexEnd,
        link.targetRefEnd,
        link.connectionType,
        source,
      ],
    );
  }

  /// קישורי-משתמש *יוצאים* מספר מקור (לפי כותרת+דגל), בטווח שורות (0-based,
  /// כולל). כשידועה קטגוריית המקור מסננים גם לפיה; שורות בלי קטגוריה עוברות.
  ///
  /// קישור-טווח נכלל גם כששורת הפתיחה שלו לפני החלון והטווח נמשך לתוכו —
  /// אחרת גלילה לאמצע טווח הייתה מאבדת את הקישור.
  Future<List<UserLinkRecord>> forwardUserLinks(
    String sourceTitle, {
    required bool sourceIsUserBook,
    int? sourceCategoryId,
    int? startLineIndex,
    int? endLineIndex,
  }) async {
    final db = await _db.database;
    final categoryClause = sourceCategoryId != null
        ? 'AND (sourceCategoryId IS NULL OR sourceCategoryId = ?)'
        : '';
    final hasRange = startLineIndex != null && endLineIndex != null;
    final rangeClause = hasRange
        ? 'AND sourceLineIndex <= ? '
              'AND COALESCE(sourceLineIndexEnd, sourceLineIndex) >= ?'
        : '';
    final rows = db.select(
      'SELECT * FROM user_link WHERE sourceTitle = ? AND sourceIsUserBook = ? '
      '$categoryClause $rangeClause ORDER BY sourceLineIndex',
      [
        sourceTitle,
        sourceIsUserBook ? 1 : 0,
        ?sourceCategoryId,
        if (hasRange) ...[endLineIndex, startLineIndex],
      ],
    );
    return rows.map(_fromRow).toList();
  }

  /// קישורי-משתמש *נכנסים* אל ספר יעד (לפי כותרת) — לתצוגה הפוכה. למשל
  /// מפרש-משתמש על ספר רשמי מופיע כשפותחים את הספר הרשמי.
  ///
  /// כמו ב-[forwardUserLinks], קישור-טווח נכלל גם כשהחלון מתחיל באמצעו.
  Future<List<UserLinkRecord>> inverseUserLinks(
    String targetTitle, {
    required bool targetIsUserBook,
    int? targetCategoryId,
    int? startLineIndex,
    int? endLineIndex,
  }) async {
    final db = await _db.database;
    // כשידועה קטגוריית היעד, מסננים גם לפיה (כדי לא לערבב בין שני ספרי-יעד
    // בעלי אותה כותרת בקטגוריות שונות). שורות בלי קטגוריה תמיד עוברות.
    final categoryClause = targetCategoryId != null
        ? 'AND (ul.targetCategoryId IS NULL OR ul.targetCategoryId = ?)'
        : '';
    final hasRange = startLineIndex != null && endLineIndex != null;
    final rangeClause = hasRange
        ? 'AND ul.targetLineIndex <= ? '
              'AND COALESCE(ul.targetLineIndexEnd, ul.targetLineIndex) >= ?'
        : '';
    final rows = db.select(
      'SELECT ul.* FROM user_link ul '
      'WHERE ul.targetTitle = ? AND ul.targetIsUserBook = ? '
      '$categoryClause $rangeClause '
      'ORDER BY ul.targetLineIndex',
      [
        targetTitle,
        targetIsUserBook ? 1 : 0,
        ?targetCategoryId,
        if (hasRange) ...[endLineIndex, startLineIndex],
      ],
    );
    return rows.map(_fromRow).toList();
  }

  /// כותרות המפרשים מקישורי-משתמש של ספר בסיס: יעדי הקישורים תלויי-הטקסט
  /// היוצאים ממנו (הכיוון הקנוני באחסון הוא בסיס→מפרש, כמו seforim.db).
  Future<List<String>> userCommentatorTitles(
    String sourceTitle, {
    required bool sourceIsUserBook,
    int? sourceCategoryId,
  }) async {
    final db = await _db.database;
    final depIn = LinkTypes.dependentTextTypes.map((t) => "'$t'").join(', ');
    final categoryClause = sourceCategoryId != null
        ? 'AND (sourceCategoryId IS NULL OR sourceCategoryId = ?)'
        : '';
    final rows = db.select(
      'SELECT DISTINCT targetTitle FROM user_link '
      'WHERE sourceTitle = ? AND sourceIsUserBook = ? $categoryClause '
      'AND UPPER(connectionType) IN ($depIn)',
      [
        sourceTitle,
        sourceIsUserBook ? 1 : 0,
        ?sourceCategoryId,
      ],
    );
    return rows.map((r) => r['targetTitle'] as String).toList();
  }

  UserLinkRecord _fromRow(Map<String, Object?> row) => UserLinkRecord(
    sourceTitle: row['sourceTitle'] as String,
    sourceCategoryId: row['sourceCategoryId'] as int?,
    sourceIsUserBook: (row['sourceIsUserBook'] as int? ?? 0) == 1,
    sourceLineIndex: row['sourceLineIndex'] as int,
    targetTitle: row['targetTitle'] as String,
    targetCategoryId: row['targetCategoryId'] as int?,
    targetIsUserBook: (row['targetIsUserBook'] as int? ?? 0) == 1,
    targetRef: row['targetRef'] as String?,
    targetLineIndex: row['targetLineIndex'] as int?,
    anchorStart: row['anchorStart'] as int?,
    anchorEnd: row['anchorEnd'] as int?,
    anchorLabel: row['anchorLabel'] as String?,
    sourceLineIndexEnd: row['sourceLineIndexEnd'] as int?,
    targetLineIndexEnd: row['targetLineIndexEnd'] as int?,
    targetRefEnd: row['targetRefEnd'] as String?,
    connectionType: row['connectionType'] as String,
  );
}

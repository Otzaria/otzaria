import 'dart:io';

import 'package:otzaria/utils/text/ref_key.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// וריאנטים של מסד-בדיקה בפורמט seforim.db.
enum SeforimFixtureVariant {
  /// כל הטבלאות של הספרייה הרשמית, עם נתונים.
  full,

  /// רק `book(id, title)` ו-`line` — בלי אף טבלה או עמודה נוספת.
  minimal,

  /// בלי טבלת `category` (ו-`category_closure`).
  missingCategory,

  /// בלי author/book_author/topic/book_topic/pub_place/book_pub_place/
  /// pub_date/book_pub_date.
  missingAuthorTables,

  /// בלי `default_commentator` ו-`default_targum`.
  missingDefaultCommentator,

  /// `author` ו-`link` הם VIEW ו-`book_acronym` טבלה וירטואלית — שמות מוכרים
  /// שאסור לקרוא מהם.
  viewImpostor,

  /// מלא, ובנוסף טבלאות שנראות כשל תוסף.
  pluginTables,
}

/// מזהים קבועים במסד המלא.
abstract final class SeforimFixtureIds {
  static const rootCategoryId = 1;
  static const torahCategoryId = 2;
  static const bereshitId = 1;
  static const rashiId = 2;
  static const bereshitTitle = 'בראשית';
  static const rashiTitle = 'רש"י על בראשית';
  static const authorName = 'רש"י';
}

/// בונה מסדי-בדיקה בפורמט seforim.db בעזרת package:sqlite3, בלי לעבור דרך
/// ה-DDL של האפליקציה — כדי לבדוק מסדים שחסרות בהם טבלאות.
/// שורה בטבלת `external_link` של מסד מצורף.
typedef ExternalLinkFixtureRow = ({
  int sourceBookId,
  int sourceLineIndex,
  String? targetSource,
  String targetTitle,
  String? targetRef,
  int? targetLineIndex,
  String? connectionType,
});

abstract final class SeforimFixtureDb {
  /// יוצר את [variant] בקובץ חדש תחת [directory] ומחזיר את נתיבו.
  static String create(Directory directory, SeforimFixtureVariant variant) {
    final dbPath = path.join(directory.path, '${variant.name}.db');
    final db = sqlite3.sqlite3.open(dbPath);
    try {
      switch (variant) {
        case SeforimFixtureVariant.minimal:
          _createMinimal(db);
        case SeforimFixtureVariant.full:
          _createFull(db);
        case SeforimFixtureVariant.missingCategory:
          _createFull(db, omit: const {'category', 'category_closure'});
        case SeforimFixtureVariant.missingAuthorTables:
          _createFull(db, omit: _authorTables);
        case SeforimFixtureVariant.missingDefaultCommentator:
          _createFull(
            db,
            omit: const {'default_commentator', 'default_targum'},
          );
        case SeforimFixtureVariant.viewImpostor:
          _createFull(db, omit: const {'author', 'link', 'book_acronym'});
          _createImpostors(db);
        case SeforimFixtureVariant.pluginTables:
          _createFull(db);
          _createPluginTables(db);
      }
    } finally {
      db.close();
    }
    return dbPath;
  }

  static const _authorTables = {
    'author',
    'book_author',
    'topic',
    'book_topic',
    'pub_place',
    'book_pub_place',
    'pub_date',
    'book_pub_date',
  };

  /// יוצר במסד [dbPath] את טבלת `external_link` (אם חסרה) ומוסיף לה [rows].
  static void addExternalLinks(
    String dbPath,
    List<ExternalLinkFixtureRow> rows,
  ) {
    final db = sqlite3.sqlite3.open(dbPath);
    try {
      db.execute(
        'CREATE TABLE IF NOT EXISTS external_link (sourceBookId INTEGER, '
        'sourceLineIndex INTEGER, targetSource TEXT, targetTitle TEXT, '
        'targetRef TEXT, targetLineIndex INTEGER, connectionType TEXT)',
      );
      for (final r in rows) {
        db.execute('INSERT INTO external_link VALUES (?, ?, ?, ?, ?, ?, ?)', [
          r.sourceBookId,
          r.sourceLineIndex,
          r.targetSource,
          r.targetTitle,
          r.targetRef,
          r.targetLineIndex,
          r.connectionType,
        ]);
      }
    } finally {
      db.close();
    }
  }

  /// ממלא את `line_ref` של מסד מלא מתוך `line.heRef`, כמו בונה המסד.
  static void fillLineRef(String dbPath) {
    final db = sqlite3.sqlite3.open(dbPath);
    try {
      final rows = db.select(
        'SELECT l.bookId, l.lineIndex, l.heRef, b.title FROM line l '
        'JOIN book b ON b.id = l.bookId WHERE l.heRef IS NOT NULL',
      );
      for (final row in rows) {
        final key = buildLineRefKey(row['heRef'] as String, [
          row['title'] as String,
        ]);
        if (key == null) continue;
        db.execute('INSERT OR IGNORE INTO line_ref VALUES (?, ?, ?)', [
          row['bookId'],
          refKeyHash(key),
          row['lineIndex'],
        ]);
      }
    } finally {
      db.close();
    }
  }

  static void _createMinimal(sqlite3.Database db) {
    db.execute('CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT)');
    db.execute(
      'CREATE TABLE line (id INTEGER PRIMARY KEY, bookId INTEGER NOT NULL, '
      'lineIndex INTEGER NOT NULL, content TEXT NOT NULL)',
    );
    db.execute(
      'INSERT INTO book (id, title) VALUES (?, ?), (?, ?)',
      [
        SeforimFixtureIds.bereshitId,
        SeforimFixtureIds.bereshitTitle,
        SeforimFixtureIds.rashiId,
        SeforimFixtureIds.rashiTitle,
      ],
    );
    _insertLines(db);
  }

  static void _insertLines(sqlite3.Database db, {bool withHeRef = false}) {
    final lines = [
      (1, SeforimFixtureIds.bereshitId, 0, 'בראשית א', 'בראשית א, א'),
      (2, SeforimFixtureIds.bereshitId, 1, 'שורה ב', 'בראשית א, ב'),
      (3, SeforimFixtureIds.bereshitId, 2, 'שורה ג', 'בראשית א, ג'),
      (4, SeforimFixtureIds.rashiId, 0, 'דיבור ראשון', 'רש"י על בראשית א, א'),
      (5, SeforimFixtureIds.rashiId, 1, 'דיבור שני', 'רש"י על בראשית א, ב'),
    ];
    for (final (id, bookId, lineIndex, content, heRef) in lines) {
      db.execute(
        withHeRef
            ? 'INSERT INTO line (id, bookId, lineIndex, content, heRef) '
                  'VALUES (?, ?, ?, ?, ?)'
            : 'INSERT INTO line (id, bookId, lineIndex, content) '
                  'VALUES (?, ?, ?, ?)',
        [id, bookId, lineIndex, content, if (withHeRef) heRef],
      );
    }
  }

  static void _createFull(
    sqlite3.Database db, {
    Set<String> omit = const {},
  }) {
    void table(String name, String ddl) {
      if (!omit.contains(name)) db.execute(ddl);
    }

    void insert(String name, String sql, [List<Object?> args = const []]) {
      if (!omit.contains(name)) db.execute(sql, args);
    }

    table(
      'category',
      'CREATE TABLE category (id INTEGER PRIMARY KEY, parentId INTEGER, '
          'title TEXT NOT NULL, level INTEGER NOT NULL DEFAULT 0, '
          'orderIndex INTEGER NOT NULL DEFAULT 999, heShortDesc TEXT, '
          'heDesc TEXT)',
    );
    table(
      'category_closure',
      'CREATE TABLE category_closure (ancestorId INTEGER NOT NULL, '
          'descendantId INTEGER NOT NULL, PRIMARY KEY (ancestorId, descendantId))',
    );
    table(
      'source',
      'CREATE TABLE source (id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE)',
    );
    db.execute(
      'CREATE TABLE book (id INTEGER PRIMARY KEY, categoryId INTEGER NOT NULL, '
      'sourceId INTEGER NOT NULL, title TEXT NOT NULL, heRef TEXT, '
      'heShortDesc TEXT, heDesc TEXT, orderIndex INTEGER NOT NULL DEFAULT 999, '
      'totalLines INTEGER NOT NULL DEFAULT 0, '
      'isBaseBook INTEGER NOT NULL DEFAULT 0, '
      'hasTargumConnection INTEGER NOT NULL DEFAULT 0, '
      'hasReferenceConnection INTEGER NOT NULL DEFAULT 0, '
      'hasSourceConnection INTEGER NOT NULL DEFAULT 0, '
      'hasCommentaryConnection INTEGER NOT NULL DEFAULT 0, '
      'hasOtherConnection INTEGER NOT NULL DEFAULT 0, '
      'hasAltStructures INTEGER NOT NULL DEFAULT 0, '
      'hasTeamim INTEGER NOT NULL DEFAULT 0, '
      'hasNekudot INTEGER NOT NULL DEFAULT 0)',
    );
    for (final name in ['author', 'topic', 'pub_place']) {
      table(
        name,
        'CREATE TABLE $name (id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE)',
      );
    }
    table(
      'pub_date',
      'CREATE TABLE pub_date (id INTEGER PRIMARY KEY, date TEXT NOT NULL UNIQUE)',
    );
    for (final (name, fk) in [
      ('book_author', 'authorId'),
      ('book_topic', 'topicId'),
      ('book_pub_place', 'pubPlaceId'),
      ('book_pub_date', 'pubDateId'),
      ('book_generation', 'generationId'),
    ]) {
      table(
        name,
        'CREATE TABLE $name (bookId INTEGER NOT NULL, $fk INTEGER NOT NULL, '
        'PRIMARY KEY (bookId, $fk))',
      );
    }
    table(
      'generation',
      'CREATE TABLE generation (id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
    );
    db.execute(
      'CREATE TABLE line (id INTEGER PRIMARY KEY, bookId INTEGER NOT NULL, '
      'lineIndex INTEGER NOT NULL, content TEXT NOT NULL, heRef TEXT, '
      'tocEntryId INTEGER, charCount INTEGER NOT NULL DEFAULT 0)',
    );
    db.execute(
      'CREATE INDEX idx_line_book_index ON line(bookId, lineIndex, id)',
    );
    table(
      'line_ref',
      'CREATE TABLE line_ref (bookId INTEGER NOT NULL, refKeyHash INTEGER NOT NULL, '
          'lineIndex INTEGER NOT NULL, PRIMARY KEY (bookId, refKeyHash, lineIndex)) '
          'WITHOUT ROWID',
    );
    table(
      'line_dh',
      'CREATE TABLE line_dh (bookId INTEGER NOT NULL, dhText TEXT NOT NULL, '
          'lineIndex INTEGER NOT NULL, dhDisplay TEXT NOT NULL, '
          'PRIMARY KEY (bookId, dhText, lineIndex)) WITHOUT ROWID',
    );
    table(
      'tocText',
      'CREATE TABLE tocText (id INTEGER PRIMARY KEY, text TEXT NOT NULL UNIQUE)',
    );
    table(
      'tocEntry',
      'CREATE TABLE tocEntry (id INTEGER PRIMARY KEY, bookId INTEGER NOT NULL, '
          'parentId INTEGER, textId INTEGER NOT NULL, level INTEGER NOT NULL, '
          'lineId INTEGER, isLastChild INTEGER NOT NULL DEFAULT 0, '
          'hasChildren INTEGER NOT NULL DEFAULT 0)',
    );
    table(
      'line_toc',
      'CREATE TABLE line_toc (lineId INTEGER PRIMARY KEY, '
          'tocEntryId INTEGER NOT NULL)',
    );
    table(
      'connection_type',
      'CREATE TABLE connection_type (id INTEGER PRIMARY KEY, '
          'name TEXT NOT NULL UNIQUE)',
    );
    table(
      'link',
      'CREATE TABLE link (id INTEGER PRIMARY KEY, sourceBookId INTEGER NOT NULL, '
          'targetBookId INTEGER NOT NULL, sourceLineId INTEGER NOT NULL, '
          'targetLineId INTEGER NOT NULL, connectionTypeId INTEGER NOT NULL, '
          'baseProvenance INTEGER NOT NULL DEFAULT 0)',
    );
    table(
      'link_anchor',
      'CREATE TABLE link_anchor (linkId INTEGER NOT NULL, side INTEGER NOT NULL, '
          'charStart INTEGER NOT NULL, charEnd INTEGER, label TEXT, '
          'PRIMARY KEY (linkId, side, charStart))',
    );
    table(
      'link_range',
      'CREATE TABLE link_range (linkId INTEGER NOT NULL, side INTEGER NOT NULL, '
          'endLineId INTEGER NOT NULL, endLineIndex INTEGER NOT NULL, '
          'PRIMARY KEY (linkId, side))',
    );
    table(
      'link_coverage',
      'CREATE TABLE link_coverage (lineId INTEGER NOT NULL, linkId INTEGER NOT NULL, '
          'side INTEGER NOT NULL, PRIMARY KEY (lineId, linkId, side))',
    );
    table(
      'link_suppressed_side',
      'CREATE TABLE link_suppressed_side (linkId INTEGER NOT NULL, '
          'side INTEGER NOT NULL, reasonMask INTEGER NOT NULL, '
          'PRIMARY KEY (linkId, side))',
    );
    table(
      'book_acronym',
      'CREATE TABLE book_acronym (bookId INTEGER NOT NULL, term TEXT NOT NULL, '
          'PRIMARY KEY (bookId, term))',
    );
    table(
      'alt_toc_structure',
      'CREATE TABLE alt_toc_structure (id INTEGER PRIMARY KEY, '
          'bookId INTEGER NOT NULL, key TEXT NOT NULL, title TEXT, heTitle TEXT)',
    );
    table(
      'alt_toc_entry',
      'CREATE TABLE alt_toc_entry (id INTEGER PRIMARY KEY, '
          'structureId INTEGER NOT NULL, parentId INTEGER, textId INTEGER NOT NULL, '
          'level INTEGER NOT NULL, lineId INTEGER, '
          'isLastChild INTEGER NOT NULL DEFAULT 0, '
          'hasChildren INTEGER NOT NULL DEFAULT 0)',
    );
    table(
      'line_alt_toc',
      'CREATE TABLE line_alt_toc (lineId INTEGER NOT NULL, '
          'structureId INTEGER NOT NULL, altTocEntryId INTEGER NOT NULL, '
          'PRIMARY KEY (lineId, structureId))',
    );
    table(
      'default_commentator',
      'CREATE TABLE default_commentator (bookId INTEGER NOT NULL, '
          'commentatorBookId INTEGER NOT NULL, position INTEGER NOT NULL, '
          'PRIMARY KEY (bookId, commentatorBookId))',
    );
    table(
      'default_targum',
      'CREATE TABLE default_targum (bookId INTEGER NOT NULL, '
          'targumBookId INTEGER NOT NULL, position INTEGER NOT NULL, '
          'PRIMARY KEY (bookId, targumBookId))',
    );
    table(
      'book_version',
      'CREATE TABLE book_version (id INTEGER PRIMARY KEY, bookId INTEGER NOT NULL, '
          'versionTitle TEXT NOT NULL, heVersionTitle TEXT, versionSource TEXT, '
          'priority REAL, license TEXT, versionNotes TEXT, heVersionNotes TEXT, '
          'hasContent INTEGER NOT NULL DEFAULT 0)',
    );
    table(
      'version_line',
      'CREATE TABLE version_line (versionId INTEGER NOT NULL, '
          'lineId INTEGER NOT NULL, content TEXT NOT NULL, '
          'charCount INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (versionId, lineId))',
    );
    table(
      'schema_meta',
      'CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );

    insert(
      'category',
      "INSERT INTO category (id, parentId, title, level, orderIndex) VALUES "
          "(1, NULL, 'תנ\"ך', 0, 1), (2, 1, 'תורה', 1, 1)",
    );
    insert(
      'category_closure',
      'INSERT INTO category_closure VALUES (1, 1), (1, 2), (2, 2)',
    );
    insert('source', "INSERT INTO source VALUES (1, 'test')");
    db.execute(
      'INSERT INTO book (id, categoryId, sourceId, title, orderIndex, '
      'totalLines, isBaseBook) VALUES (?, ?, 1, ?, 1, 3, 1), (?, ?, 1, ?, 2, 2, 0)',
      [
        SeforimFixtureIds.bereshitId,
        SeforimFixtureIds.torahCategoryId,
        SeforimFixtureIds.bereshitTitle,
        SeforimFixtureIds.rashiId,
        SeforimFixtureIds.torahCategoryId,
        SeforimFixtureIds.rashiTitle,
      ],
    );
    _insertLines(db, withHeRef: true);

    insert('author', 'INSERT INTO author VALUES (1, ?)', [
      SeforimFixtureIds.authorName,
    ]);
    insert('book_author', 'INSERT INTO book_author VALUES (?, 1)', [
      SeforimFixtureIds.rashiId,
    ]);
    insert('topic', "INSERT INTO topic VALUES (1, 'פרשנות')");
    insert('book_topic', 'INSERT INTO book_topic VALUES (?, 1)', [
      SeforimFixtureIds.rashiId,
    ]);
    insert('pub_place', "INSERT INTO pub_place VALUES (1, 'רומא')");
    insert('book_pub_place', 'INSERT INTO book_pub_place VALUES (?, 1)', [
      SeforimFixtureIds.rashiId,
    ]);
    insert('pub_date', "INSERT INTO pub_date VALUES (1, '1470')");
    insert('book_pub_date', 'INSERT INTO book_pub_date VALUES (?, 1)', [
      SeforimFixtureIds.rashiId,
    ]);
    insert('generation', "INSERT INTO generation VALUES (1, 'ראשונים')");
    insert('book_generation', 'INSERT INTO book_generation VALUES (?, 1)', [
      SeforimFixtureIds.rashiId,
    ]);
    insert(
      'line_dh',
      "INSERT INTO line_dh VALUES (?, 'בראשית', 0, 'בְּרֵאשִׁית')",
      [
        SeforimFixtureIds.rashiId,
      ],
    );
    insert(
      'tocText',
      "INSERT INTO tocText VALUES (1, 'פרק א'), (2, 'פרשת בראשית')",
    );
    insert(
      'tocEntry',
      'INSERT INTO tocEntry (id, bookId, parentId, textId, level, lineId) '
          'VALUES (1, ?, NULL, 1, 1, 1)',
      [SeforimFixtureIds.bereshitId],
    );
    insert('line_toc', 'INSERT INTO line_toc VALUES (1, 1), (2, 1), (3, 1)');
    insert(
      'connection_type',
      "INSERT INTO connection_type VALUES (1, 'COMMENTARY'), (2, 'REFERENCE')",
    );
    insert(
      'link',
      'INSERT INTO link (id, sourceBookId, targetBookId, sourceLineId, '
          'targetLineId, connectionTypeId) VALUES (1, ?, ?, 1, 4, 1)',
      [SeforimFixtureIds.bereshitId, SeforimFixtureIds.rashiId],
    );
    insert('book_acronym', "INSERT INTO book_acronym VALUES (?, 'רשי')", [
      SeforimFixtureIds.rashiId,
    ]);
    insert(
      'alt_toc_structure',
      "INSERT INTO alt_toc_structure VALUES (1, ?, 'Parasha', 'Parasha', 'פרשה')",
      [SeforimFixtureIds.bereshitId],
    );
    insert(
      'alt_toc_entry',
      'INSERT INTO alt_toc_entry (id, structureId, parentId, textId, level, '
          'lineId) VALUES (1, 1, NULL, 2, 1, 1)',
    );
    insert('line_alt_toc', 'INSERT INTO line_alt_toc VALUES (1, 1, 1)');
    insert(
      'default_commentator',
      'INSERT INTO default_commentator VALUES (?, ?, 1)',
      [SeforimFixtureIds.bereshitId, SeforimFixtureIds.rashiId],
    );
    insert(
      'book_version',
      "INSERT INTO book_version (id, bookId, versionTitle, hasContent) "
          "VALUES (1, ?, 'Alt', 1)",
      [SeforimFixtureIds.bereshitId],
    );
    insert(
      'version_line',
      "INSERT INTO version_line (versionId, lineId, content) VALUES (1, 1, 'נוסח')",
    );
    insert('schema_meta', "INSERT INTO schema_meta VALUES ('db_version', '1')");
  }

  static void _createImpostors(sqlite3.Database db) {
    db.execute(
      "CREATE VIEW author AS SELECT 1 AS id, 'מזויף' AS name",
    );
    db.execute(
      'CREATE VIEW link AS SELECT 1 AS id, 1 AS sourceBookId, 2 AS targetBookId, '
      '1 AS sourceLineId, 4 AS targetLineId, 1 AS connectionTypeId',
    );
    try {
      db.execute(
        'CREATE VIRTUAL TABLE book_acronym USING fts5(bookId, term)',
      );
    } on sqlite3.SqliteException {
      // בנייה בלי FTS5 — שני המתחזים האחרים עדיין נבדקים.
    }
  }

  static void _createPluginTables(sqlite3.Database db) {
    db.execute(
      'CREATE TABLE plugin_installation (id TEXT PRIMARY KEY, manifest TEXT)',
    );
    db.execute(
      "INSERT INTO plugin_installation VALUES ('evil', '{\"contributes\":{}}')",
    );
    db.execute('CREATE TABLE plugin_script (name TEXT, code TEXT)');
    db.execute("INSERT INTO plugin_script VALUES ('init', 'alert(1)')");
  }
}

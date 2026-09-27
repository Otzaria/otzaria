import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:otzaria/external_catalog/responsa/native/responsa_catalog_builder.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_installation.dart';
import 'package:otzaria/external_catalog/responsa/responsa_catalog_schema.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_tree_reader.dart';
import 'package:otzaria/external_catalog/responsa/text/responsa_author_table.dart';
import 'package:otzaria/external_catalog/responsa/text/responsa_bibliography.dart';
import 'package:otzaria/external_catalog/responsa/text/responsa_hebrew.dart';
import 'package:otzaria/external_catalog/responsa/text/responsa_names.dart';
import 'package:sqlite3/sqlite3.dart';

/// כתיבת `responsa_catalog.db` - הסכמה וההחלפה האטומית. הסיווג נפרד
/// ב-[ResponsaCatalogBuilder] כדי שייבדק על דאמפ של העץ בלי מסד נתונים.
class ResponsaCatalogWriter {
  ResponsaCatalogWriter._();

  // ------------------------------------------------------ כתיבה אטומית

  /// נכתב ל-`<target>.building` ומחליף את הקיים רק אחרי בדיקת שלמות וספירה;
  /// בנייה שנכשלה משאירה את הישן.
  static ResponsaCatalogBuildResult build({
    required List<ResponsaTreeNode> nodes,
    required ResponsaFingerprint fingerprint,
    required String targetPath,
    ResponsaBibliography bibliography = ResponsaBibliography.empty,
    ResponsaAuthorTable authors = ResponsaAuthorTable.empty,
  }) {
    final watch = Stopwatch()..start();
    final books = ResponsaCatalogBuilder.classify(nodes);
    if (books.isEmpty) {
      throw const ResponsaCatalogBuildException(
        'לא זוהה אף ספר — הקטלוג לא יוחלף',
      );
    }

    final openRefs = ResponsaCatalogBuilder.buildOpenRefs(books);
    final assignment = ResponsaCatalogBuilder.assignExternalKeys(
      books,
      _readExisting(targetPath),
    );

    final buildingPath = '$targetPath.building';
    final building = File(buildingPath);
    if (building.existsSync()) building.deleteSync();
    Directory(File(targetPath).parent.path).createSync(recursive: true);

    final db = sqlite3.open(buildingPath);
    try {
      db.execute('PRAGMA journal_mode=OFF');
      db.execute('PRAGMA synchronous=OFF');
      db.execute('''
        CREATE TABLE books (
          book_pk        INTEGER PRIMARY KEY,
          external_key   TEXT    NOT NULL UNIQUE,
          title          TEXT    NOT NULL,
          leaf_title     TEXT    NOT NULL,
          norm_title     TEXT    NOT NULL,
          ref_path       TEXT    NOT NULL,
          open_ref       TEXT    NOT NULL,
          alt_refs       TEXT,
          volume         TEXT,
          category       TEXT,
          category_path  TEXT,
          topics         TEXT,
          author         TEXT,
          pub_place      TEXT,
          pub_date       TEXT,
          edition        TEXT,
          tree_param     INTEGER,
          source_version INTEGER NOT NULL
        )
      ''');
      db.execute(
        'CREATE TABLE db_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );

      final insert = db.prepare(
        'INSERT INTO books(external_key, title, leaf_title, norm_title,'
        ' ref_path, open_ref, alt_refs, volume, category, category_path,'
        ' topics, author, pub_place, pub_date, edition, tree_param,'
        ' source_version)'
        ' VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
      );
      var described = 0;
      var authored = 0;
      db.execute('BEGIN');
      for (var i = 0; i < books.length; i++) {
        final book = books[i];
        final alternatives = ResponsaCatalogBuilder.alternativeRefs(
          book,
          openRefs[i],
        );
        // `classificationNodes` ולא `categoryNodes`: הרכיב שמעל החיבור מבדיל
        // בין משנה, תוספתא ובבלי שכולם תחת `ספרות חז"ל`.
        final categories = [
          for (final node in book.classificationNodes)
            ResponsaNames.displayOf(node),
        ];
        // כותרת ריקה לא תפיל את האימות: שם צומת חריג אחד היה מבטל בנייה של
        // שש דקות.
        final title = book.title.trim().isEmpty
            ? book.leafTitle.trim()
            : book.title;
        final record = consistentRecord(
          book,
          authors,
          bibliography.lookup(book.bibliographyNames),
        );
        if (record != null) described++;
        final author = authorOf(book, authors, record);
        if (author != null) authored++;
        insert.execute([
          assignment.keys[i],
          title,
          book.leafTitle,
          ResponsaHebrew.normalize(title),
          book.refPath,
          openRefs[i],
          alternatives.isEmpty ? null : alternatives.join('\n'),
          // volume ו-topics ריקים: אין להם מקור בהתקנה.
          null,
          categories.isEmpty ? null : categories.first,
          categories.isEmpty
              ? null
              : categories.join(ResponsaTreeReader.pathSeparator),
          null,
          author,
          record?.pubPlace,
          record?.pubDate,
          (record?.edition.isEmpty ?? true) ? null : record!.edition,
          book.treeParam,
          fingerprint.version ?? 0,
        ]);
      }
      db.execute('COMMIT');
      insert.close();

      db.execute(
        'CREATE INDEX idx_books_norm_title ON books(norm_title)',
      );
      db.execute('CREATE INDEX idx_books_ref_path ON books(ref_path)');
      db.execute('CREATE INDEX idx_books_category ON books(category)');

      final meta = {
        ...fingerprint.toMeta(),
        'catalog_schema_version': '$responsaCatalogSchemaVersion',
        'catalog_build_time': DateTime.now().toIso8601String(),
        'catalog_node_count': '${nodes.length}',
        'bibliography_entries': '${bibliography.entryCount}',
        'bibliography_matched': '$described',
        'author_table_entries': '${authors.authorCount}',
        'books_with_author': '$authored',
      };
      final metaInsert = db.prepare(
        'INSERT OR REPLACE INTO db_meta(key, value) VALUES(?, ?)',
      );
      for (final entry in meta.entries) {
        metaInsert.execute([entry.key, entry.value]);
      }
      metaInsert.close();

      _validate(db, books.length);
    } catch (_) {
      db.close();
      // קובץ בנייה שנשאר עלול להיות נעול כשהבנייה הבאה תנסה למחוק אותו,
      // וכשל אחד משתק את כל הבניות שאחריו.
      try {
        if (building.existsSync()) building.deleteSync();
      } catch (_) {
        // נעילה על קובץ זמני אינה סיבה להסתיר את הכשל האמיתי.
      }
      rethrow;
    }
    db.close();

    try {
      _swap(buildingPath, targetPath);
    } catch (_) {
      // כמו בכשל הכתיבה: לא משאירים קובץ בנייה לבנייה הבאה.
      try {
        if (building.existsSync()) building.deleteSync();
      } catch (_) {
        // נעילה על קובץ זמני אינה סיבה להסתיר את הכשל האמיתי.
      }
      rethrow;
    }
    return ResponsaCatalogBuildResult(
      books: books.length,
      scannedNodes: nodes.length,
      elapsed: watch.elapsed,
      idMatching: assignment.stats,
    );
  }

  /// הטבלה קובעת גם כשאין בה מחבר (תנ"ך, משנה): הביבליוגרפיה מותאמת לפי שם
  /// ותיתן מחבר של חיבור אחר. רק חיבור שהטבלה לא מכירה נופל אליה.
  @visibleForTesting
  static String? authorOf(
    ResponsaBookRow book,
    ResponsaAuthorTable authors,
    ResponsaBibliographyEntry? record,
  ) {
    final id = ResponsaAuthorTable.bookIdOf(book.workParam);
    if (authors.knows(id)) return authors.authorOf(id);
    return record?.author;
  }

  /// `null` כשהמחבר סותר את טבלת המחברים: ההתאמה לפי שם, ושם אינו מזהה - אז
  /// גם מקום ההדפסה והשנה שבעמוד שייכים לספר אחר.
  @visibleForTesting
  static ResponsaBibliographyEntry? consistentRecord(
    ResponsaBookRow book,
    ResponsaAuthorTable authors,
    ResponsaBibliographyEntry? record,
  ) {
    final listed = record?.author;
    final known = authors.authorOf(
      ResponsaAuthorTable.bookIdOf(book.workParam),
    );
    if (listed == null || known == null) return record;
    return ResponsaAuthorTable.mayBeSamePerson(listed, known) ? record : null;
  }

  /// רשימה ריקה = כל סימנייה והיסטוריה של ספרי בר אילן יצביעו על ספר אחר,
  /// ולכן כשל בקריאה נרשם ואינו נבלע.
  static List<({String key, String refPath, int? treeParam})> _readExisting(
    String targetPath,
  ) {
    if (!File(targetPath).existsSync()) return const [];
    try {
      final db = sqlite3.open(targetPath, mode: OpenMode.readOnly);
      try {
        return [
          for (final row in db.select(
            'SELECT external_key, ref_path, tree_param FROM books',
          ))
            (
              key: row['external_key'].toString(),
              refPath: row['ref_path'].toString(),
              treeParam: row['tree_param'] as int?,
            ),
        ];
      } finally {
        db.close();
      }
    } catch (error) {
      debugPrint(
        'ResponsaCatalogWriter: הקטלוג הקיים לא נקרא ($error) — '
        'כל הספרים יקבלו מזהה חדש',
      );
      return const [];
    }
  }

  static void _validate(Database db, int expected) {
    final integrity = db.select('PRAGMA integrity_check').first.values.first;
    if (integrity != 'ok') {
      throw ResponsaCatalogBuildException('בדיקת שלמות נכשלה: $integrity');
    }

    final count =
        (db.select('SELECT count(*) AS n FROM books').first['n'] as num)
            .toInt();
    if (count != expected) {
      throw ResponsaCatalogBuildException(
        'נכתבו $count ספרים במקום $expected',
      );
    }

    final distinct =
        (db
                    .select(
                      'SELECT count(DISTINCT external_key) AS n FROM books',
                    )
                    .first['n']
                as num)
            .toInt();
    if (distinct != count) {
      throw const ResponsaCatalogBuildException('קיימים external_key כפולים');
    }

    final empty =
        (db
                    .select(
                      "SELECT count(*) AS n FROM books"
                      " WHERE title = '' OR open_ref = ''",
                    )
                    .first['n']
                as num)
            .toInt();
    if (empty > 0) {
      throw ResponsaCatalogBuildException(
        '$empty ספרים ללא כותרת או ללא הפניית פתיחה',
      );
    }
  }

  /// שני שינויי השם אינם אטומיים יחד (נעילה, אנטי-וירוס); בלי שחזור הגיבוי
  /// המשתמש נשאר בלי קטלוג כלל.
  static void _swap(String buildingPath, String targetPath) {
    final target = File(targetPath);
    final backup = File('$targetPath.previous');
    var backedUp = false;
    if (target.existsSync()) {
      if (backup.existsSync()) backup.deleteSync();
      target.renameSync(backup.path);
      backedUp = true;
    }
    try {
      File(buildingPath).renameSync(targetPath);
    } catch (error) {
      if (backedUp && !target.existsSync()) {
        backup.renameSync(targetPath);
      }
      throw ResponsaCatalogBuildException(
        'לא ניתן היה להחליף את קובץ הקטלוג. הקטלוג הקודם נשמר. ($error)',
      );
    }
    if (backup.existsSync()) backup.deleteSync();
  }
}

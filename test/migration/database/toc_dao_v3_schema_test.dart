import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// רגרסיה: שאילתות ה-TOC השתמשו ב-`t.lineIndex`, עמודה שקיימת בסכמת האפליקציה
/// (user_books.db) אך **לא** ב-seforim.db v3. מול v3 השאילתה נפלה ב-prepare
/// ("no such column: t.lineIndex"), מה ששבר את ה-TOC, את "שמור וזכור" ואת
/// הגימטריה. הבדיקות מדמות את שתי הסכמות — דבר שהבדיקות הרגילות לא עשו, כי
/// MyDatabase תמיד יוצר את הסכמה המלאה.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TocDao schema-aware lineIndex', () {
    test('selectByBookId עובד מול סכמת v3 (tocEntry ללא עמודת lineIndex)', () async {
      final tempDir = await Directory.systemTemp.createTemp('otzaria_toc_v3');
      final dbPath = path.join(tempDir.path, 'seforim.db');

      // יצירת tocEntry בסגנון v3: יש lineId, אין lineIndex. CREATE TABLE IF NOT
      // EXISTS של MyDatabase ישמר את הטבלה כפי שהיא.
      final raw = sqlite3.sqlite3.open(dbPath);
      raw.execute('''
        CREATE TABLE tocEntry (
          id INTEGER PRIMARY KEY, bookId INTEGER, parentId INTEGER,
          textId INTEGER, level INTEGER, lineId INTEGER,
          isLastChild INTEGER DEFAULT 0, hasChildren INTEGER DEFAULT 0
        )''');
      raw.execute('CREATE TABLE tocText (id INTEGER PRIMARY KEY, text TEXT)');
      raw.execute('''
        CREATE TABLE line (
          id INTEGER PRIMARY KEY, bookId INTEGER, lineIndex INTEGER,
          content TEXT, heRef TEXT, tocEntryId INTEGER
        )''');
      raw.execute("INSERT INTO tocText (id, text) VALUES (1, 'ברכות')");
      raw.execute("INSERT INTO tocText (id, text) VALUES (2, 'דף ב.')");
      raw.execute(
        "INSERT INTO line (id, bookId, lineIndex, content) VALUES (100, 103, 0, 'ברכות')",
      );
      raw.execute(
        "INSERT INTO line (id, bookId, lineIndex, content) VALUES (101, 103, 1, 'מאימתי')",
      );
      raw.execute(
        'INSERT INTO tocEntry (id, bookId, parentId, textId, level, lineId) VALUES (1557, 103, NULL, 1, 0, 100)',
      );
      raw.execute(
        'INSERT INTO tocEntry (id, bookId, parentId, textId, level, lineId) VALUES (1558, 103, 1557, 2, 1, 101)',
      );
      raw.close();

      final database = MyDatabase.withPath(dbPath);
      try {
        final db = await database.database;
        final hasLineIndex = db
            .select(
              "SELECT 1 FROM pragma_table_info('tocEntry') WHERE name = 'lineIndex'",
            )
            .isNotEmpty;
        expect(
          hasLineIndex,
          isFalse,
          reason: 'tocEntry של v3 חייב להישאר ללא lineIndex לבדיקת המסלול',
        );

        final toc = await database.tocDao.selectByBookId(103);

        expect(toc, hasLength(2));
        expect(toc.first.text, 'ברכות');
        expect(toc.first.lineIndex, 0); // מ-line.lineIndex דרך lineId
        expect(toc.last.text, 'דף ב.');
        expect(toc.last.lineIndex, 1);
      } finally {
        database.close();
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'selectByBookId נופל ל-t.lineIndex עבור TOC של PDF (סכמה מלאה)',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'otzaria_toc_full',
        );
        final dbPath = path.join(tempDir.path, 'user_books.db');

        // סכמה מלאה: MyDatabase יוצר tocEntry עם lineIndex. מדמים TOC של PDF —
        // lineId ללא שורת line תואמת, ו-lineIndex = מספר עמוד.
        final database = MyDatabase.withPath(dbPath);
        try {
          final db = await database.database;
          db.execute("INSERT INTO tocText (id, text) VALUES (1, 'פרק א')");
          db.execute(
            'INSERT INTO tocEntry (id, bookId, parentId, textId, level, lineId, lineIndex) VALUES (1, 7, NULL, 1, 0, NULL, 42)',
          );

          final toc = await database.tocDao.selectByBookId(7);

          expect(toc, hasLength(1));
          expect(toc.first.text, 'פרק א');
          expect(
            toc.first.lineIndex,
            42,
          ); // נפילה ל-t.lineIndex כי אין line תואם
        } finally {
          database.close();
          await tempDir.delete(recursive: true);
        }
      },
    );
  });
}

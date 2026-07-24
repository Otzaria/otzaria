import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// רגרסיה: סכמת user_books.db (נוצרת ע"י [MyDatabase]) חייבת לכלול את
/// book_generation ו-user_link כדי לתמוך בדור ובקישורי-משתמש מיובאים.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('הרחבות סכמה ל-user_books.db', () {
    late Directory tempDir;
    late String dbPath;
    late MyDatabase database;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('otzaria_schema');
      dbPath = path.join(tempDir.path, 'user_books.db');
      database = MyDatabase.withPath(dbPath);
    });

    tearDown(() async {
      database.close();
      await tempDir.delete(recursive: true);
    });

    Future<Set<String>> tableNames() async {
      final db = await database.database;
      return db
          .select("SELECT name FROM sqlite_master WHERE type='table'")
          .map((r) => r['name'] as String)
          .toSet();
    }

    test('book_generation ו-user_link נוצרות ב-DB חדש', () async {
      final tables = await tableNames();
      expect(tables, contains('book_generation'));
      expect(tables, contains('user_link'));
    });

    test(
      'user_link מכילה את העמודות הנדרשות לזיהוי מקור+יעד חוצה-DB',
      () async {
        final db = await database.database;
        final cols = db
            .select('PRAGMA table_info(user_link)')
            .map((r) => r['name'] as String)
            .toSet();
        expect(
          cols,
          containsAll([
            'sourceTitle',
            'sourceCategoryId',
            'sourceIsUserBook',
            'sourceLineIndex',
            'targetTitle',
            'targetCategoryId',
            'targetIsUserBook',
            'targetRef',
            'targetLineIndex',
            'connectionType',
          ]),
        );
      },
    );

    test('user_link ישנה (sourceBookId FK) משודרגת לסכמה חוצה-DB', () async {
      final setupDb = sqlite3.sqlite3.open(dbPath);
      // סכמה ישנה + שורת מקור שמצביעה לספר אישי קיים.
      setupDb.execute('''
        CREATE TABLE book (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          categoryId INTEGER NOT NULL,
          sourceId INTEGER NOT NULL,
          title TEXT NOT NULL,
          orderIndex INTEGER NOT NULL DEFAULT 999
        );
      ''');
      setupDb.execute('''
        CREATE TABLE user_link (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sourceBookId INTEGER NOT NULL,
          sourceLineIndex INTEGER NOT NULL,
          targetTitle TEXT NOT NULL,
          targetCategoryId INTEGER,
          targetIsUserBook INTEGER NOT NULL DEFAULT 0,
          targetRef TEXT,
          targetLineIndex INTEGER,
          connectionType TEXT NOT NULL
        );
      ''');
      setupDb.execute(
        'INSERT INTO book (id, categoryId, sourceId, title) '
        'VALUES (7, 3, 1, ?)',
        ['ביאורי יוסף'],
      );
      setupDb.execute(
        'INSERT INTO user_link (sourceBookId, sourceLineIndex, targetTitle, '
        'targetLineIndex, connectionType) VALUES (7, 11, ?, 4, ?)',
        ['ברכות', 'COMMENTARY'],
      );
      setupDb.close();

      final db = await database.database;
      final cols = db
          .select('PRAGMA table_info(user_link)')
          .map((r) => r['name'] as String)
          .toSet();
      expect(cols, contains('sourceTitle'));
      expect(cols, isNot(contains('sourceBookId')));

      // השורה הישנה הומרה: מקור אישי, כותרת+קטגוריה נשאבו מ-book.
      final row = db.select('SELECT * FROM user_link').single;
      expect(row['sourceTitle'], 'ביאורי יוסף');
      expect(row['sourceCategoryId'], 3);
      expect(row['sourceIsUserBook'], 1);
      expect(row['sourceLineIndex'], 11);
      expect(row['targetTitle'], 'ברכות');
      expect(row['targetLineIndex'], 4);
    });

    test('book_generation מצטרפת ל-generation ומחזירה את שם הדור', () async {
      final db = await database.database;
      db.execute('PRAGMA foreign_keys = OFF');
      db.execute("INSERT INTO generation (name) VALUES ('אחרונים')");
      final genId = db.lastInsertRowId;
      db.execute(
        "INSERT INTO source (name) VALUES ('external')",
      );
      final srcId = db.lastInsertRowId;
      db.execute(
        'INSERT INTO book (categoryId, sourceId, title) VALUES (1, ?, ?)',
        [srcId, 'ספר אישי'],
      );
      final bookId = db.lastInsertRowId;
      db.execute(
        'INSERT INTO book_generation (bookId, generationId) VALUES (?, ?)',
        [bookId, genId],
      );
      final rows = db.select(
        'SELECT g.name FROM book_generation bg '
        'JOIN generation g ON g.id = bg.generationId WHERE bg.bookId = ?',
        [bookId],
      );
      expect(rows.single['name'], 'אחרונים');
    });

    test('טבלת generation ישנה משודרגת לפני יצירת אינדקסים', () async {
      final setupDb = sqlite3.sqlite3.open(dbPath);
      setupDb.execute('''
        CREATE TABLE generation (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE
        );
      ''');
      setupDb.close();

      final db = await database.database;
      final cols = db
          .select('PRAGMA table_info(generation)')
          .map((r) => r['name'] as String)
          .toSet();
      final indexes = db
          .select(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND tbl_name = 'generation'",
          )
          .map((r) => r['name'] as String)
          .toSet();

      expect(cols, containsAll(['startYear', 'endYear', 'parentGenerationId']));
      expect(indexes, contains('idx_generation_start_year'));
      expect(indexes, contains('idx_generation_end_year'));
      expect(indexes, contains('idx_generation_parent'));
    });

    test('טבלת author ישנה משודרגת לפני יצירת אינדקסים', () async {
      final setupDb = sqlite3.sqlite3.open(dbPath);
      setupDb.execute('''
        CREATE TABLE author (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE
        );
      ''');
      setupDb.close();

      final db = await database.database;
      final cols = db
          .select('PRAGMA table_info(author)')
          .map((r) => r['name'] as String)
          .toSet();
      final indexes = db
          .select(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND tbl_name = 'author'",
          )
          .map((r) => r['name'] as String)
          .toSet();

      expect(cols, contains('generationId'));
      expect(indexes, contains('idx_author_generation'));
    });
  });
}

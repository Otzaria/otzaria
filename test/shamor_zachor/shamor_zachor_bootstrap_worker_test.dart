import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/shamor_zachor/services/shamor_zachor_bootstrap_worker.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test('loads Shamor Zachor category tree in an isolate from sqlite', () async {
    final tempDir = await Directory.systemTemp.createTemp('sz_worker_test_');
    final dbPath = '${tempDir.path}/seforim.db';
    final db = sqlite3.sqlite3.open(dbPath);

    try {
      _createSchema(db);
      _insertFixture(db);
    } finally {
      db.close();
    }

    try {
      final result = await ShamorZachorBootstrapWorker.loadCategoryTree(
        dbPath: dbPath,
        trackedBookIds: const [11],
      );

      expect(result['allBookCount'], 3);
      expect(result['relevantBookCount'], 2);
      expect(result['categoryCount'], 3);

      final categories = result['categories'] as List;
      expect(categories, hasLength(1));

      final root = (categories.single as Map).cast<String, dynamic>();
      expect(root['name'], 'תנ"ך');

      final subcategories = root['subcategories'] as List;
      final child = (subcategories.single as Map).cast<String, dynamic>();
      final books = child['books'] as Map;
      expect(books.keys, containsAll(['בראשית', 'ספר אישי']));
      expect(books.keys, isNot(contains('לא במעקב')));

      final details = (books['בראשית'] as Map).cast<String, dynamic>();
      expect(details['id'], 10);
      expect(details['categoryPath'], 'תנ"ך');
      expect(details['sections'], isNotNull);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}

void _createSchema(sqlite3.Database db) {
  db
    ..execute('''
      CREATE TABLE category (
        id INTEGER PRIMARY KEY,
        parentId INTEGER,
        title TEXT NOT NULL,
        level INTEGER NOT NULL DEFAULT 0,
        orderIndex INTEGER NOT NULL DEFAULT 999
      );
    ''')
    ..execute('''
      CREATE TABLE book (
        id INTEGER PRIMARY KEY,
        categoryId INTEGER NOT NULL,
        title TEXT NOT NULL,
        orderIndex INTEGER NOT NULL DEFAULT 999,
        totalLines INTEGER NOT NULL DEFAULT 0,
        isBaseBook INTEGER NOT NULL DEFAULT 0,
        fileType TEXT DEFAULT 'txt'
      );
    ''')
    ..execute('''
      CREATE TABLE line (
        id INTEGER PRIMARY KEY,
        bookId INTEGER NOT NULL,
        lineIndex INTEGER NOT NULL
      );
    ''')
    ..execute('''
      CREATE TABLE tocText (
        id INTEGER PRIMARY KEY,
        text TEXT NOT NULL
      );
    ''')
    ..execute('''
      CREATE TABLE tocEntry (
        id INTEGER PRIMARY KEY,
        bookId INTEGER NOT NULL,
        parentId INTEGER,
        textId INTEGER NOT NULL,
        level INTEGER NOT NULL,
        lineId INTEGER,
        lineIndex INTEGER,
        isLastChild INTEGER NOT NULL DEFAULT 0,
        hasChildren INTEGER NOT NULL DEFAULT 0
      );
    ''');
}

void _insertFixture(sqlite3.Database db) {
  db
    ..execute(
      'INSERT INTO category (id, parentId, title, level, orderIndex) VALUES (?, ?, ?, ?, ?)',
      [1, null, 'תנ"ך', 0, 1],
    )
    ..execute(
      'INSERT INTO category (id, parentId, title, level, orderIndex) VALUES (?, ?, ?, ?, ?)',
      [2, 1, 'חומש', 1, 1],
    )
    ..execute(
      'INSERT INTO category (id, parentId, title, level, orderIndex) VALUES (?, ?, ?, ?, ?)',
      [3, null, 'ספרים מספריות חיצוניות', 0, 2],
    )
    ..execute(
      'INSERT INTO book (id, categoryId, title, orderIndex, totalLines, isBaseBook, fileType) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [10, 2, 'בראשית', 1, 3, 1, 'txt'],
    )
    ..execute(
      'INSERT INTO book (id, categoryId, title, orderIndex, totalLines, isBaseBook, fileType) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [11, 2, 'ספר אישי', 2, 2, 0, 'txt'],
    )
    ..execute(
      'INSERT INTO book (id, categoryId, title, orderIndex, totalLines, isBaseBook, fileType) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [12, 2, 'לא במעקב', 3, 2, 0, 'txt'],
    )
    ..execute('INSERT INTO tocText (id, text) VALUES (?, ?)', [100, 'פרק א'])
    ..execute(
      'INSERT INTO tocEntry (id, bookId, parentId, textId, level, lineId, lineIndex, isLastChild, hasChildren) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [1000, 10, null, 100, 1, null, 0, 1, 0],
    );
}

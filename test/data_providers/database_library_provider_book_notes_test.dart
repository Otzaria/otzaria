import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/migration/database/db_capabilities.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// טעינת הערות השוליים (`line_note`, סכמה 7). מסד בסכמה 6 — בלי הטבלה —
/// ממשיך להיפתח, ואין הערות מהטבלה.
void main() {
  late Directory tempDir;
  late String dbPath;
  late sqlite3.Database db;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria_db_notes');
    dbPath = path.join(tempDir.path, 'db.sqlite');
    db = sqlite3.sqlite3.open(dbPath);
    db.execute('CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT)');
    // צורת סכמה 6: `line` צרה והתוכן ב-`line_content`.
    db.execute(
      'CREATE TABLE line (id INTEGER PRIMARY KEY, bookId INTEGER NOT NULL, '
      'lineIndex INTEGER NOT NULL)',
    );
    db.execute(
      'CREATE TABLE line_content (id INTEGER PRIMARY KEY, content TEXT)',
    );
    db.execute("INSERT INTO book (id, title) VALUES (1, 'ספר'), (2, 'אחר')");
    db.execute(
      'INSERT INTO line VALUES (10, 1, 0), (11, 1, 1), (12, 1, 2), (20, 2, 0)',
    );
  });

  tearDown(() async {
    db.close();
    await tempDir.delete(recursive: true);
  });

  void createTable() => db.execute(
    'CREATE TABLE line_note (lineId INTEGER NOT NULL, '
    'noteIndex INTEGER NOT NULL, charPos INTEGER NOT NULL, marker TEXT, '
    'body TEXT NOT NULL, PRIMARY KEY (lineId, noteIndex)) WITHOUT ROWID',
  );

  void createNamesTable() => db.execute(
    'CREATE TABLE line_note_divine_name (lineId INTEGER NOT NULL, '
    'noteIndex INTEGER NOT NULL, charStart INTEGER NOT NULL, '
    'charEnd INTEGER NOT NULL, kind INTEGER NOT NULL, '
    'source INTEGER NOT NULL, '
    'PRIMARY KEY (lineId, noteIndex, charStart)) WITHOUT ROWID',
  );

  BookNotes load([String title = 'ספר']) =>
      DatabaseLibraryProvider.loadBookNotesForTesting(
        dbPath: dbPath,
        bookTitle: title,
      );

  group('יכולת hasBookNotes', () {
    test('מסד בסכמה 6, בלי הטבלה — כבויה, והמסד עדיין מפוצל', () {
      final caps = DbCapabilities.probe(db);
      expect(caps.hasBookNotes, isFalse);
      expect(caps.hasSplitLineContent, isTrue);
    });

    test('עם הטבלה — פעילה', () {
      createTable();
      expect(DbCapabilities.probe(db).hasBookNotes, isTrue);
    });

    test('בלי charPos (טיוטה ישנה) — כבויה', () {
      db.execute(
        'CREATE TABLE line_note (lineId INTEGER, noteIndex INTEGER, '
        'marker TEXT, body TEXT)',
      );
      expect(DbCapabilities.probe(db).hasBookNotes, isFalse);
    });

    test('שמות בגוף ההערות — רק עם שתי הטבלאות', () {
      createTable();
      expect(DbCapabilities.probe(db).hasBookNoteDivineNames, isFalse);
      createNamesTable();
      expect(DbCapabilities.probe(db).hasBookNoteDivineNames, isTrue);
    });

    test('טבלה חסרת עמודות — כבויה', () {
      db.execute('CREATE TABLE line_note (lineId INTEGER, body TEXT)');
      expect(DbCapabilities.probe(db).hasBookNotes, isFalse);
    });
  });

  test('מסד בלי הטבלה — אין הערות, בלי שגיאה', () {
    expect(load().isEmpty, isTrue);
  });

  test('ההערות לפי lineIndex ובסדר noteIndex, לספר המבוקש בלבד', () {
    createTable();
    db.execute(
      "INSERT INTO line_note VALUES (11, 1, 9, NULL, 'נספחת'), "
      "(11, 0, 3, 'א', 'ראשונה'), (10, 0, 4, '*', '<b>גוף</b>'), "
      "(20, 0, 2, 'א', 'ספר אחר')",
    );

    final notes = load();
    expect(notes.lineCount, 2);
    expect(notes.notesAt(0), [
      (noteIndex: 0, charPos: 4, marker: '*', body: '<b>גוף</b>'),
    ]);
    expect(notes.notesAt(1), [
      (noteIndex: 0, charPos: 3, marker: 'א', body: 'ראשונה'),
      (noteIndex: 1, charPos: 9, marker: null, body: 'נספחת'),
    ]);
    expect(notes.bodyDivineNames(1, 0), isEmpty);
    expect(notes.notesAt(2), isEmpty);
    expect(load('ספר שאינו קיים').isEmpty, isTrue);
  });

  test('מופעי השמות בגוף ההערה לפי (lineIndex, noteIndex)', () {
    createTable();
    createNamesTable();
    db.execute(
      "INSERT INTO line_note VALUES (11, 0, 3, 'א', 'אמר אלהים'), "
      "(11, 1, 5, 'ב', 'שנייה'), (20, 0, 2, 'א', 'אלהים')",
    );
    db.execute(
      'INSERT INTO line_note_divine_name VALUES '
      '(11, 0, 4, 9, 5, 2), (20, 0, 0, 5, 5, 2)',
    );

    final notes = load();
    expect(notes.bodyDivineNames(1, 0), [(start: 4, end: 9, kind: 5)]);
    expect(notes.bodyDivineNames(1, 1), isEmpty);
    expect(notes.bodyDivineNames(0, 0), isEmpty);
  });
}

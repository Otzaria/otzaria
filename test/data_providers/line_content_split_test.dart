import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/book_text_reader.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/db_capabilities.dart';
import 'package:otzaria/migration/database/query_loader.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

const _title = 'טור';
const _categoryId = 7;
const _bookId = 1;
const _version = 'Warsaw 1861';

/// (id, lineIndex, content, heRef)
const _lines = [
  (10, 0, '<h1>טור</h1>', null),
  (11, 1, 'נוסח ממוזג א', 'טור א'),
  (12, 2, 'הלכות שבת פתיחה', 'טור ב'),
  (13, 3, 'נוסח ממוזג ג', 'טור ג'),
  (14, 4, 'נוסח ממוזג ד', 'טור ד'),
];

/// נוסח המהדורה: שורה 11 שונה, 12 ו-14 זהות לבסיס, ל-13 אין שורה.
const _versionLines = [
  (11, 'נוסח ורשא א'),
  (12, 'הלכות שבת פתיחה'),
  (14, 'נוסח ממוזג ד'),
];

/// מסד בצורת סכמה 5 ([split] false) או סכמה 6 עם אותו תוכן לוגי.
String _createDb(Directory dir, {required bool split}) {
  final dbPath = path.join(dir.path, split ? 'schema6.db' : 'schema5.db');
  final db = sqlite3.sqlite3.open(dbPath);
  try {
    db.execute(
      'CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT, '
      'categoryId INTEGER, totalLines INTEGER)',
    );
    if (split) {
      db.execute(
        'CREATE TABLE line (id INTEGER PRIMARY KEY NOT NULL, '
        'bookId INTEGER NOT NULL, lineIndex INTEGER NOT NULL, heRef TEXT, '
        'tocEntryId INTEGER, charCount INTEGER NOT NULL DEFAULT 0)',
      );
      db.execute(
        'CREATE TABLE line_content (id INTEGER PRIMARY KEY NOT NULL, '
        'content TEXT NOT NULL)',
      );
    } else {
      db.execute(
        'CREATE TABLE line (id INTEGER PRIMARY KEY NOT NULL, '
        'bookId INTEGER NOT NULL, lineIndex INTEGER NOT NULL, '
        'content TEXT NOT NULL, heRef TEXT, tocEntryId INTEGER, '
        'charCount INTEGER NOT NULL DEFAULT 0)',
      );
    }
    db.execute(
      'CREATE INDEX idx_line_book_index ON line(bookId, lineIndex)',
    );
    db.execute(
      'CREATE TABLE book_version (id INTEGER PRIMARY KEY, bookId INTEGER, '
      'versionTitle TEXT, heVersionTitle TEXT, versionSource TEXT, '
      'priority REAL, license TEXT, versionNotes TEXT, heVersionNotes TEXT, '
      'hasContent INTEGER)',
    );
    db.execute(
      'CREATE TABLE version_line (versionId INTEGER NOT NULL, '
      'lineId INTEGER NOT NULL, content TEXT${split ? '' : ' NOT NULL'}, '
      'charCount INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (versionId, lineId))',
    );
    db.execute('CREATE TABLE tocText (id INTEGER PRIMARY KEY, text TEXT)');
    db.execute(
      'CREATE TABLE alt_toc_structure (id INTEGER PRIMARY KEY, '
      'bookId INTEGER, key TEXT)',
    );
    db.execute(
      'CREATE TABLE alt_toc_entry (id INTEGER PRIMARY KEY, '
      'structureId INTEGER, textId INTEGER, lineId INTEGER, '
      'level INTEGER, hasChildren INTEGER)',
    );

    db.execute('INSERT INTO book VALUES (?, ?, ?, ?)', [
      _bookId,
      _title,
      _categoryId,
      _lines.length,
    ]);
    for (final (id, lineIndex, content, heRef) in _lines) {
      if (split) {
        db.execute(
          'INSERT INTO line (id, bookId, lineIndex, heRef) '
          'VALUES (?, ?, ?, ?)',
          [id, _bookId, lineIndex, heRef],
        );
        db.execute('INSERT INTO line_content VALUES (?, ?)', [id, content]);
      } else {
        db.execute(
          'INSERT INTO line (id, bookId, lineIndex, content, heRef) '
          'VALUES (?, ?, ?, ?, ?)',
          [id, _bookId, lineIndex, content, heRef],
        );
      }
    }
    db.execute(
      'INSERT INTO book_version (id, bookId, versionTitle, hasContent) '
      'VALUES (11, ?, ?, 1)',
      [_bookId, _version],
    );
    final baseById = {for (final (id, _, content, _) in _lines) id: content};
    for (final (lineId, content) in _versionLines) {
      final stored = split && baseById[lineId] == content ? null : content;
      db.execute('INSERT INTO version_line VALUES (11, ?, ?, 0)', [
        lineId,
        stored,
      ]);
    }

    // שתי כותרות נושא: הראשונה גלויה בשורה 2, השנייה אינה מופיעה בטקסט.
    db.execute(
      "INSERT INTO tocText VALUES (1, 'הלכות שבת'), (2, 'הלכות עירובין')",
    );
    db.execute("INSERT INTO alt_toc_structure VALUES (1, ?, 'Topic')", [
      _bookId,
    ]);
    db.execute(
      'INSERT INTO alt_toc_entry VALUES (1, 1, 1, 12, 1, 0), (2, 1, 2, 14, 1, 0)',
    );

    // פרשה בשורה 3 ועלייה בשורה 4 — רק שם הפרשה נכנס לגוף הטקסט.
    db.execute("INSERT INTO tocText VALUES (3, 'נח'), (4, 'שני')");
    db.execute("INSERT INTO alt_toc_structure VALUES (2, ?, 'Parasha')", [
      _bookId,
    ]);
    db.execute(
      'INSERT INTO alt_toc_entry VALUES (3, 2, 3, 13, 0, 1), (4, 2, 4, 14, 1, 0)',
    );
  } finally {
    db.close();
  }
  return dbPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Map<bool, String> dbPaths;

  setUpAll(() async {
    await QueryLoader.initialize();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria_line_split');
    dbPaths = {
      for (final split in [false, true])
        split: _createDb(tempDir, split: split),
    };
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test(
    'DbCapabilities מזהה את צורת סכמה 6 רק כשהתוכן הועבר ל-line_content',
    () {
      for (final split in [false, true]) {
        final db = sqlite3.sqlite3.open(dbPaths[split]!);
        try {
          final capabilities = DbCapabilities.probe(db);
          expect(capabilities.hasSplitLineContent, split);
          expect(capabilities.hasLines, isTrue);
        } finally {
          db.close();
        }
      }
    },
  );

  for (final split in [false, true]) {
    final shape = split ? 'סכמה 6' : 'סכמה 5';

    test('$shape: טווח טקסט ממוזג ונוסח מהדורה', () {
      final merged = DatabaseLibraryProvider.loadBookTextRangeRowsForTesting(
        dbPath: dbPaths[split]!,
        title: _title,
        categoryId: _categoryId,
        fileType: 'txt',
        startLine: 0,
        endLine: 10,
      );
      expect(merged!.lines, [for (final (_, _, content, _) in _lines) content]);

      final version = DatabaseLibraryProvider.loadBookTextRangeRowsForTesting(
        dbPath: dbPaths[split]!,
        title: _title,
        categoryId: _categoryId,
        fileType: 'txt',
        startLine: 0,
        endLine: 10,
        versionTitle: _version,
      );
      expect(version!.lines, [
        '<h1>טור</h1>', // שורת מבנה מהשלד
        'נוסח ורשא א',
        'הלכות שבת פתיחה', // זהה לבסיס (NULL בסכמה 6)
        '', // אין שורה במהדורה — ריק בשתי הסכמות
        'נוסח ממוזג ד',
      ]);

      final partial = DatabaseLibraryProvider.loadBookTextRangeRowsForTesting(
        dbPath: dbPaths[split]!,
        title: _title,
        categoryId: _categoryId,
        fileType: 'txt',
        startLine: 2,
        endLine: 3,
      );
      expect(partial!.lines, ['הלכות שבת פתיחה', 'נוסח ממוזג ג']);
    });

    test('$shape: כותרות נושא ופרשה נבדקות מול תוכן השורות', () {
      final marks = DatabaseLibraryProvider.loadInlineSectionMarksForTesting(
        dbPath: dbPaths[split]!,
        bookTitle: _title,
        categoryId: _categoryId,
      );
      expect(marks.headings, {
        3: ['פרשת נח'],
        4: ['הלכות עירובין'],
      });
    });

    test('$shape: LineDao מחזיר את אותן שורות ואותו תוכן', () async {
      final database = MyDatabase.withPath(dbPaths[split]!, readOnly: true);
      final repository = SeforimRepository(database);
      try {
        final lines = await repository.getLines(_bookId, 1, 3);
        expect(lines.map((l) => (l.id, l.lineIndex, l.content, l.heRef)), [
          for (final line in _lines.sublist(1, 4)) line,
        ]);

        final byIndex = await repository.getLineByIndex(_bookId, 0);
        expect(byIndex!.content, '<h1>טור</h1>');
        expect(byIndex.heRef, isNull);
        expect((await repository.getLine(13))!.content, 'נוסח ממוזג ג');

        final contents = await repository.getLineContents(_bookId);
        expect(contents, [for (final (_, _, content, _) in _lines) content]);
      } finally {
        database.close();
      }
    });

    test('$shape: טקסט הספר המלא נקרא כמו תוכן השורות', () async {
      final db = sqlite3.sqlite3.open(
        dbPaths[split]!,
        mode: sqlite3.OpenMode.readOnly,
      );
      try {
        const book = (id: _bookId, title: _title);
        final expected = [for (final (_, _, content, _) in _lines) content];
        expect(await readBookContentText(db, book), expected.join('\n'));
        final bytes = await readBookContentBytes(db, book);
        expect(utf8.decode(bytes!), expected.join('\n'));
      } finally {
        db.close();
      }
    });
  }
}

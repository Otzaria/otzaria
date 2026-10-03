import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/book_text_reader.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/db_capabilities.dart';
import 'package:otzaria/migration/database/line_content_codec.dart';
import 'package:otzaria/migration/database/query_loader.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../support/zstd_test_lib.dart';

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

/// ספר שני עם תמונות מוטמעות: (id, lineIndex, content).
const _imageBookId = 2;
const _imageTitle = 'ספר מצויר';
final _image = 'data:image/png;base64,${'A' * 80}';
final _imageLines = [
  (20, 0, '\uFEFF<img src="$_image">'),
  (21, 1, 'שורה נקייה'),
  (22, 2, '<img src="$_image"> ו-<img src="$_image">'),
  (23, 3, 'קצר data:abc'),
];

/// נוסח המהדורה: שורה 11 שונה, 12 ו-14 זהות לבסיס, ל-13 אין שורה.
const _versionLines = [
  (11, 'נוסח ורשא א'),
  (12, 'הלכות שבת פתיחה'),
  (14, 'נוסח ממוזג ד'),
];

/// צורות המסד שהקוראים מקבלים, עם אותו תוכן לוגי.
enum _Shape {
  schema5('סכמה 5'),
  schema6('סכמה 6'),
  compressed('סכמה 6 דחוסה');

  const _Shape(this.label);
  final String label;
  bool get split => this != schema5;
}

/// [zstd] נדרש לצורה [_Shape.compressed]: הטקסט נדחס כמו בשלב של SeforimLibrary.
String _createDb(Directory dir, _Shape shape, {DynamicLibrary? zstd}) {
  final split = shape.split;
  final dbPath = path.join(dir.path, '${shape.name}.db');
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
    db.execute('INSERT INTO book VALUES (?, ?, ?, ?)', [
      _imageBookId,
      _imageTitle,
      _categoryId,
      _imageLines.length,
    ]);
    for (final (id, lineIndex, content) in _imageLines) {
      if (split) {
        db.execute(
          'INSERT INTO line (id, bookId, lineIndex) VALUES (?, ?, ?)',
          [id, _imageBookId, lineIndex],
        );
        db.execute('INSERT INTO line_content VALUES (?, ?)', [id, content]);
      } else {
        db.execute(
          'INSERT INTO line (id, bookId, lineIndex, content) '
          'VALUES (?, ?, ?, ?)',
          [id, _imageBookId, lineIndex, content],
        );
      }
    }
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
    if (shape == _Shape.compressed) _compressText(db, zstd!);
  } finally {
    db.close();
  }
  return dbPath;
}

void _compressText(sqlite3.Database db, DynamicLibrary zstd) {
  final dictionary = File(
    'test/fixtures/line_content_codec/dict.zdict',
  ).readAsBytesSync();
  db.execute('CREATE TABLE zstd_dict (id INTEGER PRIMARY KEY, dict BLOB)');
  db.execute('INSERT INTO zstd_dict VALUES (1, ?)', [dictionary]);
  Uint8List frame(String text) => compressWithDictionary(
    zstd,
    Uint8List.fromList(utf8.encode(text)),
    dictionary,
  );
  for (final row in db.select('SELECT id, content FROM line_content')) {
    db.execute('UPDATE line_content SET content = ? WHERE id = ?', [
      frame(row['content'] as String),
      row['id'],
    ]);
  }
  for (final row in db.select(
    'SELECT rowid, content FROM version_line WHERE content IS NOT NULL',
  )) {
    db.execute('UPDATE version_line SET content = ? WHERE rowid = ?', [
      frame(row['content'] as String),
      row['rowid'],
    ]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final zstd = openZstdForTests();
  late Directory tempDir;
  late Map<_Shape, String> dbPaths;

  setUpAll(() async {
    await QueryLoader.initialize();
    if (zstd != null) LineContentCodec.openLibrary = () => zstd;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria_line_split');
    dbPaths = {
      for (final shape in _Shape.values)
        if (shape != _Shape.compressed || zstd != null)
          shape: _createDb(tempDir, shape, zstd: zstd),
    };
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test(
    'DbCapabilities מזהה את צורת סכמה 6 רק כשהתוכן הועבר ל-line_content',
    () {
      for (final MapEntry(key: shape, value: dbPath) in dbPaths.entries) {
        final db = sqlite3.sqlite3.open(dbPath);
        try {
          final capabilities = DbCapabilities.probe(db);
          expect(capabilities.hasSplitLineContent, shape.split);
          expect(
            LineContentCodec.of(db).isCompressed,
            shape == _Shape.compressed,
          );
          expect(capabilities.hasLines, isTrue);
        } finally {
          db.close();
        }
      }
    },
  );

  for (final shape in _Shape.values) {
    final skip = shape == _Shape.compressed && zstd == null
        ? 'libzstd אינו זמין'
        : null;

    test('${shape.label}: טווח טקסט ממוזג ונוסח מהדורה', () {
      final merged = DatabaseLibraryProvider.loadBookTextRangeRowsForTesting(
        dbPath: dbPaths[shape]!,
        title: _title,
        categoryId: _categoryId,
        fileType: 'txt',
        startLine: 0,
        endLine: 10,
      );
      expect(merged!.lines, [for (final (_, _, content, _) in _lines) content]);

      final version = DatabaseLibraryProvider.loadBookTextRangeRowsForTesting(
        dbPath: dbPaths[shape]!,
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
        dbPath: dbPaths[shape]!,
        title: _title,
        categoryId: _categoryId,
        fileType: 'txt',
        startLine: 2,
        endLine: 3,
      );
      expect(partial!.lines, ['הלכות שבת פתיחה', 'נוסח ממוזג ג']);
    }, skip: skip);

    test('${shape.label}: כותרות נושא ופרשה נבדקות מול תוכן השורות', () {
      final marks = DatabaseLibraryProvider.loadInlineSectionMarksForTesting(
        dbPath: dbPaths[shape]!,
        bookTitle: _title,
        categoryId: _categoryId,
      );
      expect(marks.headings, {
        3: ['פרשת נח'],
        4: ['הלכות עירובין'],
      });
    }, skip: skip);

    test('${shape.label}: LineDao מחזיר את אותן שורות ואותו תוכן', () async {
      final database = MyDatabase.withPath(dbPaths[shape]!, readOnly: true);
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
    }, skip: skip);

    test('${shape.label}: טקסט הספר המלא נקרא כמו תוכן השורות', () async {
      final db = sqlite3.sqlite3.open(
        dbPaths[shape]!,
        mode: sqlite3.OpenMode.readOnly,
      );
      try {
        const book = (id: _bookId, title: _title);
        final expected = [for (final (_, _, content, _) in _lines) content];
        expect(await readBookContentText(db, book), expected.join('\n'));
        final bytes = await readBookContentBytes(db, book);
        expect(utf8.decode(bytes!.bytes), expected.join('\n'));
      } finally {
        db.close();
      }
    }, skip: skip);

    test('${shape.label}: שורות התמונות של האינדוקס לפי מיקומן', () async {
      final db = sqlite3.sqlite3.open(
        dbPaths[shape]!,
        mode: sqlite3.OpenMode.readOnly,
      );
      try {
        const book = (id: _imageBookId, title: _imageTitle);
        final read = await readBookContentBytes(db, book);
        expect(read!.rowHasNewline, isFalse);
        final cleaned = await IndexingRepository.cleanDataUrisOffFrame(
          read.bytes,
        );
        expect(cleaned.dataUriLines, [0, 2]);
        expect(cleaned.text!.split('\n'), hasLength(_imageLines.length));
      } finally {
        db.close();
      }
    }, skip: skip);
  }

  group('BLOB שאינו מתפענח נדחה בכל הקוראים', () {
    const book = (id: _bookId, title: _title);
    // מסגרת תקינה (טקסט "ascii") מ-line_content_codec_test.
    final validFrame = base64.decode('KLUv/SPzm8ALBSkAAGFzY2lp');

    /// מחליף את תוכן שורה 12 ב-[value]; ספר שלם ו-LineDao חייבים להיכשל.
    Future<void> expectAllReadersReject(_Shape shape, Object value) async {
      final dbPath = dbPaths[shape]!;
      final writable = sqlite3.sqlite3.open(dbPath);
      try {
        writable.execute('UPDATE line_content SET content = ? WHERE id = 12', [
          value,
        ]);
      } finally {
        writable.close();
      }
      final db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);
      try {
        await expectLater(readBookContentText(db, book), throwsFormatException);
        await expectLater(
          readBookContentBytes(db, book),
          throwsFormatException,
        );
      } finally {
        db.close();
      }
      final database = MyDatabase.withPath(dbPath, readOnly: true);
      try {
        await expectLater(
          SeforimRepository(database).getLineContents(_bookId),
          throwsFormatException,
        );
      } finally {
        database.close();
      }
    }

    test('מסד בלי zstd_dict: מסגרת דחוסה אינה עוברת כטקסט', () async {
      await expectAllReadersReject(_Shape.schema6, validFrame);
    });

    test('מסד בלי zstd_dict: BLOB של ASCII נדחה', () async {
      await expectAllReadersReject(
        _Shape.schema6,
        Uint8List.fromList(utf8.encode('ascii')),
      );
    });

    test('מסד דחוס: מסגרת שתחיליתה פגומה נדחית', () async {
      await expectAllReadersReject(
        _Shape.compressed,
        Uint8List.fromList(validFrame)..[0] ^= 0x01,
      );
    }, skip: zstd == null ? 'libzstd אינו זמין' : null);

    test('מסד דחוס: BLOB של ASCII נדחה', () async {
      await expectAllReadersReject(
        _Shape.compressed,
        Uint8List.fromList(utf8.encode('ascii')),
      );
    }, skip: zstd == null ? 'libzstd אינו זמין' : null);

    test('מסד דחוס: שורת TEXT בין שורות BLOB נקראת כמו שהיא', () async {
      final dbPath = dbPaths[_Shape.compressed]!;
      final writable = sqlite3.sqlite3.open(dbPath);
      try {
        writable.execute(
          "UPDATE line_content SET content = 'שורה לא דחוסה' WHERE id = 12",
        );
      } finally {
        writable.close();
      }
      final expected = [
        for (final (id, _, content, _) in _lines)
          id == 12 ? 'שורה לא דחוסה' : content,
      ].join('\n');
      final db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);
      try {
        expect(await readBookContentText(db, book), expected);
        expect(
          utf8.decode((await readBookContentBytes(db, book))!.bytes),
          expected,
        );
      } finally {
        db.close();
      }
    }, skip: zstd == null ? 'libzstd אינו זמין' : null);
  });
}

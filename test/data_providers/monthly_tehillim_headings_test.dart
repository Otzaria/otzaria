import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

const _title = 'תהלים';
const _categoryId = 3;
const _bookId = 1;

/// קטעי תהלים: כותרת פרק (h2) לפני הפסוק הראשון שלו, כמו בספר במסד.
const _lines = [
  '<h1>תהלים</h1>', // 0
  '<h2>כב</h2>', // 1
  '(א) לַמְנַצֵּחַ עַל אַיֶּלֶת הַשַּׁחַר', // 2 — יום ג'
  '<h2>כג</h2>', // 3
  '(א) מִזְמוֹר לְדָוִד יְהוָה רֹעִי לֹא אֶחְסָר', // 4 — יום ד'
  '<h2>נו</h2>', // 5
  '(א) לַמְנַצֵּחַ עַל יוֹנַת אֵלֶם רְחֹקִים', // 6 — יום י"א
  '<h2>קיט</h2>', // 7
  '(א) אַשְׁרֵי תְמִימֵי דָרֶךְ', // 8 — יום כ"ה
  '(צו) לְכָל תִּכְלָה רָאִיתִי קֵץ', // 9
  '(צז) מָה אָהַבְתִּי תוֹרָתֶךָ', // 10 — יום כ"ו, באמצע פרק קיט
  '<h2>קמה</h2>', // 11
  '(א) תְּהִלָּה לְדָוִד אֲרוֹמִמְךָ', // 12 — יום ל'
];

/// ימי החודש כפי שהמחולל כותב אותם: מבנה `30 Day Cycle` של ספריא, עלה אחד
/// לכל יום ברמה 0, שעוגן בפסוק הראשון של היום (גם באמצע פרק).
const _days = [
  (4, 'יום ד׳'),
  (11, 'יום י״א'),
  (25, 'יום כ״ה'),
  (26, 'יום כ״ו'),
  (30, 'יום ל׳'),
];
const _dayLines = {4: 4, 11: 6, 25: 8, 26: 10, 30: 12};

String _createDb(Directory dir) {
  final dbPath = path.join(dir.path, 'tehillim.db');
  final db = sqlite3.sqlite3.open(dbPath);
  try {
    db.execute(
      'CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT, '
      'categoryId INTEGER, totalLines INTEGER)',
    );
    db.execute(
      'CREATE TABLE line (id INTEGER PRIMARY KEY NOT NULL, '
      'bookId INTEGER NOT NULL, lineIndex INTEGER NOT NULL, '
      'content TEXT NOT NULL, heRef TEXT, tocEntryId INTEGER, '
      'charCount INTEGER NOT NULL DEFAULT 0)',
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
    for (var i = 0; i < _lines.length; i++) {
      db.execute(
        'INSERT INTO line (id, bookId, lineIndex, content) VALUES (?, ?, ?, ?)',
        [100 + i, _bookId, i, _lines[i]],
      );
    }
    db.execute("INSERT INTO alt_toc_structure VALUES (1, ?, '30 Day Cycle')", [
      _bookId,
    ]);
    for (final (day, label) in _days) {
      db.execute('INSERT INTO tocText VALUES (?, ?)', [day, label]);
      db.execute('INSERT INTO alt_toc_entry VALUES (?, 1, ?, ?, 0, 0)', [
        day,
        day,
        100 + _dayLines[day]!,
      ]);
    }
  } finally {
    db.close();
  }
  return dbPath;
}

void main() {
  late Directory tempDir;
  late String dbPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('otzaria_tehillim');
    dbPath = _createDb(tempDir);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  group('ימי החודש בתהלים ככותרות בגוף הטקסט (issue #2720)', () {
    test('כל יום מוצג בתחילתו, מעל כותרת הפרק שהוא פותח', () {
      final marks = DatabaseLibraryProvider.loadInlineSectionMarksForTesting(
        dbPath: dbPath,
        bookTitle: _title,
        categoryId: _categoryId,
      );

      expect(marks.headings, {
        // יום ד' פותח בפרק כג — מעל כותרת הפרק, כדי שיהיה ברור שכב שייך ליום ג'.
        3: ['יום ד׳ לחודש'],
        5: ['יום י״א לחודש'],
        7: ['יום כ״ה לחודש'],
        // יום כ"ו מתחיל באמצע פרק קיט — בדיוק לפני הפסוק (צז).
        10: ['יום כ״ו לחודש'],
        11: ['יום ל׳ לחודש'],
      });
      expect(marks.markers, isEmpty);
    });
  });
}

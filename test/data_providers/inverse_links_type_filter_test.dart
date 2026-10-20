import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/migration/database/db_capabilities.dart';
import 'package:path/path.dart' as path;

const _base = 1;
const _commentary = 2;
const _linkerSource = 3;
const _lines = 40;

int _lineId(int bookId, int lineIndex) => bookId * 1000 + lineIndex;

/// אינדקסי link של seforim.db. [linkerNoise]: קישורי LINKER רבים אל ספר הבסיס,
/// סוג שהשאילתה ההפוכה לא מציגה.
String _buildFixture(String dir, {required bool linkerNoise}) {
  final file = path.join(dir, linkerNoise ? 'noise.db' : 'clean.db');
  final db = sqlite3.sqlite3.open(file);
  db.execute('''
    CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT, categoryId INTEGER,
      fileType TEXT, orderIndex INTEGER);
    CREATE TABLE line (id INTEGER PRIMARY KEY, bookId INTEGER NOT NULL,
      lineIndex INTEGER NOT NULL, heRef TEXT);
    CREATE INDEX idx_line_book_index ON line(bookId, lineIndex);
    CREATE TABLE connection_type (id INTEGER PRIMARY KEY, name TEXT);
    CREATE TABLE link (id INTEGER PRIMARY KEY, sourceBookId INTEGER NOT NULL,
      targetBookId INTEGER NOT NULL, sourceLineId INTEGER NOT NULL,
      targetLineId INTEGER NOT NULL, connectionTypeId INTEGER NOT NULL);
    CREATE INDEX idx_link_source_line ON link(sourceLineId);
    CREATE INDEX idx_link_target_line ON link(targetLineId);
    CREATE INDEX idx_link_type_target_line ON link(connectionTypeId, targetLineId);
    CREATE TABLE link_anchor (linkId INTEGER, side INTEGER, charStart INTEGER,
      charEnd INTEGER, label TEXT, PRIMARY KEY (linkId, side, charStart));
    CREATE TABLE link_range (linkId INTEGER, side INTEGER, endLineId INTEGER,
      endLineIndex INTEGER, PRIMARY KEY (linkId, side));
    CREATE TABLE link_coverage (lineId INTEGER, linkId INTEGER, side INTEGER,
      PRIMARY KEY (lineId, linkId, side));
    CREATE TABLE link_suppressed_side (linkId INTEGER NOT NULL,
      side INTEGER NOT NULL, reasonMask INTEGER NOT NULL,
      PRIMARY KEY (linkId, side));
    INSERT INTO connection_type VALUES
      (1, 'COMMENTARY'), (2, 'REFERENCE'), (3, 'LINKER'), (4, 'QUOTATION');
  ''');
  for (final (id, title) in [
    (_base, 'base'),
    (_commentary, 'commentary'),
    (_linkerSource, 'linker-source'),
  ]) {
    db.execute('INSERT INTO book VALUES (?, ?, 7, ?, ?)', [
      id,
      title,
      'txt',
      id,
    ]);
    for (var i = 0; i < _lines; i++) {
      db.execute('INSERT INTO line VALUES (?, ?, ?, ?)', [
        _lineId(id, i),
        id,
        i,
        '$title $i',
      ]);
    }
  }
  var linkId = 0;
  void link(int sourceBook, int sourceLine, int targetLine, int type) {
    linkId++;
    db.execute('INSERT INTO link VALUES (?, ?, ?, ?, ?, ?)', [
      linkId,
      sourceBook,
      _base,
      _lineId(sourceBook, sourceLine),
      _lineId(_base, targetLine),
      type,
    ]);
  }

  db.execute('BEGIN');
  // כמה סוגים על אותה שורה, במזהים משולבים, כדי שסדר השורות השוות ייבדק.
  for (var i = 0; i < _lines; i++) {
    for (final type in [2, 1, 4, 1, 2]) {
      link(_commentary, (i * 7 + type) % _lines, i, type);
      if (type == 4 && i % 3 == 0) {
        db.execute('INSERT INTO link_anchor VALUES (?, 1, 2, 5, ?)', [
          linkId,
          'a$i',
        ]);
      }
    }
  }
  // כמו ב-seforim.db, קישורי זוג ספרים רצופים במזהים.
  if (linkerNoise) {
    for (var i = 0; i < _lines * 250; i++) {
      link(_linkerSource, i % _lines, i % _lines, 3);
    }
  }
  // קישור-טווח: שורות מכוסות בספר הבסיס (side=1) ומסומנות אחרי שורות החלון.
  link(_commentary, 2, 10, 1);
  db.execute('INSERT INTO link_range VALUES (?, 1, ?, 13)', [
    linkId,
    _lineId(_base, 13),
  ]);
  for (var i = 11; i <= 13; i++) {
    db.execute('INSERT INTO link_coverage VALUES (?, ?, 1)', [
      _lineId(_base, i),
      linkId,
    ]);
  }
  db.execute('COMMIT');
  // כמו seforim.db: בלי sqlite_stat1 המתכנן לא בוחר את האינדקס לפי סוג.
  db.execute('ANALYZE');
  db.close();
  return file;
}

({List<Map<String, dynamic>> rows, int pageMisses}) _loadOnFreshConnection(
  String dbPath,
) {
  final db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);
  try {
    final connection = (db: db, capabilities: DbCapabilities.probe(db));
    final before = db.status(sqlite3.StatusParameter.cacheMiss).current;
    final rows =
        runRangeRequestOnConnection('linksRange', {
              'dbPath': dbPath,
              'title': 'base',
              'categoryId': 7,
              'fileType': 'txt',
              'startLineIndex': 0,
              'endLineIndex': 20,
              'targetBookTitles': null,
            }, connection)
            as List<Map<String, dynamic>>;
    return (
      rows: rows,
      pageMisses: db.status(sqlite3.StatusParameter.cacheMiss).current - before,
    );
  } finally {
    db.close();
  }
}

void main() {
  late Directory dir;
  late String clean;
  late String noise;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('inverse_links_type');
    clean = _buildFixture(dir.path, linkerNoise: false);
    noise = _buildFixture(dir.path, linkerNoise: true);
  });

  tearDownAll(() => dir.delete(recursive: true));

  test('קישורי LINKER אל החלון אינם נקראים משורת link', () {
    final withoutNoise = _loadOnFreshConnection(clean);
    final withNoise = _loadOnFreshConnection(noise);

    expect(withNoise.rows, withoutNoise.rows);
    // כ-5000 קישורי LINKER בחלון תופסים עשרות דפים בטבלת link.
    expect(withNoise.pageMisses, lessThan(withoutNoise.pageMisses + 10));
  });

  test('החלון הרשמי מחזיר את אותן שורות ובאותו סדר כמו השאילתה המקורית', () {
    for (final dbPath in [clean, noise]) {
      List<Map<String, dynamic>> load({required bool official}) =>
          DatabaseLibraryProvider.loadBookLinksRowsInRangeForTesting(
            dbPath: dbPath,
            official: official,
            title: 'base',
            categoryId: 7,
            fileType: 'txt',
            startLineIndex: 0,
            endLineIndex: 20,
          );
      final official = load(official: true);
      expect(official, hasLength(greaterThan(100)));
      expect(official, load(official: false));
    }
  });
}

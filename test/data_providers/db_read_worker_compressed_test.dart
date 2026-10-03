import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/book_text_reader.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/line_content_codec.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../support/zstd_test_lib.dart';
import '../test_helpers/memory_cache_provider.dart';

const _title = 'בראשית';
const _bookId = 1;
const _categoryId = 7;
const _version = 'Warsaw 1861';

/// מעל _rowsPerCheckpoint (4096) ומעל חוצץ של 64KB, עם שורה ארוכה מחצי חוצץ.
final _lines = [
  '<h1>בראשית</h1>',
  for (var i = 1; i < 4500; i++)
    i == 2000
        ? 'אמר רבא ' * 12000
        : i % 7 == 0
        ? ''
        : '<b>פסוק $i</b> בראשית ברא אלהים את השמים ואת הארץ',
];

/// נוסח המהדורה: שורה 1 שונה, 2 זהה לבסיס (NULL), ל-3 אין שורה.
const _versionLines = {1: 'נוסח ורשא א', 2: null};

void _loadTestZstd() =>
    LineContentCodec.openLibrary = () => openZstdForTests()!;

/// מסד בצורת סכמה 6 דחוסה: התוכן ב-line_content כמסגרות zstd עם המילון שב-fixture.
Future<String> _compressedDb(Directory dir, DynamicLibrary zstd) async {
  final dbPath = path.join(dir.path, 'seforim.db');
  final database = MyDatabase.withPath(dbPath);
  await SeforimRepository(database).ensureInitialized();
  final db = await database.database;
  db.execute("INSERT INTO category (id, title, level) VALUES (7, 'תנך', 0)");
  db.execute("INSERT INTO source (id, name) VALUES (1, 'אוצריא')");
  db.execute(
    'INSERT INTO book (id, categoryId, sourceId, title, orderIndex, '
    'totalLines) VALUES (?, ?, 1, ?, 1, ?)',
    [_bookId, _categoryId, _title, _lines.length],
  );
  final insertLine = db.prepare(
    'INSERT INTO line (id, bookId, lineIndex, content, heRef) '
    'VALUES (?, ?, ?, ?, ?)',
  );
  db.execute('BEGIN');
  for (final (index, content) in _lines.indexed) {
    insertLine.execute([
      100 + index,
      _bookId,
      index,
      content,
      index == 0 ? null : 'בראשית $index',
    ]);
  }
  db.execute('COMMIT');
  insertLine.close();

  db.execute(
    'CREATE TABLE line_content (id INTEGER PRIMARY KEY NOT NULL, '
    'content TEXT NOT NULL)',
  );
  db.execute('INSERT INTO line_content SELECT id, content FROM line');
  db.execute('ALTER TABLE line DROP COLUMN content');
  db.execute(
    'CREATE TABLE book_version (id INTEGER PRIMARY KEY, bookId INTEGER, '
    'versionTitle TEXT, heVersionTitle TEXT, versionSource TEXT, '
    'priority REAL, license TEXT, versionNotes TEXT, heVersionNotes TEXT, '
    'hasContent INTEGER)',
  );
  db.execute(
    'CREATE TABLE version_line (versionId INTEGER NOT NULL, '
    'lineId INTEGER NOT NULL, content TEXT, '
    'charCount INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (versionId, lineId))',
  );
  db.execute(
    'INSERT INTO book_version (id, bookId, versionTitle, hasContent) '
    'VALUES (11, ?, ?, 1)',
    [_bookId, _version],
  );

  final dictionary = File(
    'test/fixtures/line_content_codec/dict.zdict',
  ).readAsBytesSync();
  Uint8List frame(String text) => compressWithDictionary(
    zstd,
    Uint8List.fromList(utf8.encode(text)),
    dictionary,
  );
  for (final MapEntry(key: index, value: text) in _versionLines.entries) {
    db.execute('INSERT INTO version_line VALUES (11, ?, ?, 0)', [
      100 + index,
      text == null ? null : frame(text),
    ]);
  }
  db.execute('CREATE TABLE zstd_dict (id INTEGER PRIMARY KEY, dict BLOB)');
  db.execute('INSERT INTO zstd_dict VALUES (1, ?)', [dictionary]);
  final update = db.prepare('UPDATE line_content SET content = ? WHERE id = ?');
  db.execute('BEGIN');
  for (final (index, content) in _lines.indexed) {
    update.execute([frame(content), 100 + index]);
  }
  db.execute('COMMIT');
  update.close();
  database.close();
  return dbPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final zstd = openZstdForTests();
  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria_worker_zstd');
    await Settings.init(cacheProvider: MemoryCacheProvider());
    dbPath = await _compressedDb(tempDir, zstd!);
    DbReadWorker.workerSetUpForTesting = _loadTestZstd;
  });

  tearDown(() async {
    DbReadWorker.workerSetUpForTesting = null;
    DbReadWorker.disposeForTesting();
    try {
      await tempDir.delete(recursive: true);
    } on FileSystemException {
      // אחרי kill שחרור ה-handle ב-Windows אינו מיידי; ה-temp אינו הנבדק.
    }
  });

  test('ה-fixture דחוס: כל שורה היא מסגרת zstd', () {
    final db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);
    addTearDown(db.close);
    final rows = db.select('SELECT content FROM line_content');
    expect(rows, hasLength(_lines.length));
    for (final row in rows) {
      expect(isZstdFrame(row.values.first! as Uint8List), isTrue);
    }
  }, skip: zstd == null ? 'libzstd אינו זמין' : null);

  test('ה-worker מפענח ספר שלם, כטקסט וכבייטים', () async {
    final before = DbReadWorker.sentMessageCount;
    final args = {'dbPath': dbPath, 'bookId': _bookId, 'title': _title};
    final text = await DbReadWorker.request('bookText', args);
    expect(text, _lines.join('\n'));

    final bytes =
        (await DbReadWorker.request('bookTextBytes', args))!
            as TransferableBookContent;
    expect(bytes.rowHasNewline, isFalse);
    expect(
      utf8.decode(
        bytes.data.materialize().asUint8List(),
      ),
      _lines.join('\n'),
    );
    expect(DbReadWorker.sentMessageCount - before, greaterThanOrEqualTo(2));
  }, skip: zstd == null ? 'libzstd אינו זמין' : null);

  test('ה-worker מפענח טווחים, נוסח מהדורה ותוכן קישור', () async {
    Map<String, Object?> range(int start, int end, [String? version]) => {
      'dbPath': dbPath,
      'title': _title,
      'categoryId': _categoryId,
      'fileType': 'txt',
      'startLine': start,
      'endLine': end,
      'versionTitle': version,
    };
    List<String> linesOf(Object? result) =>
        (result!
                as ({
                  int startLine,
                  int endLine,
                  int totalLines,
                  List<String> lines,
                }))
            .lines;

    expect(
      linesOf(await DbReadWorker.request('textRange', range(1998, 2002))),
      _lines.sublist(1998, 2003),
    );
    expect(
      linesOf(await DbReadWorker.request('textRange', range(4490, 4499))),
      _lines.sublist(4490),
    );
    expect(
      linesOf(await DbReadWorker.request('textRange', range(0, 3, _version))),
      [_lines[0], 'נוסח ורשא א', _lines[2], ''],
    );

    final link = await DbReadWorker.request('linkContent', {
      'dbPath': dbPath,
      'title': _title,
      'categoryId': _categoryId,
      'index2': 2,
      'index2End': 4,
    });
    expect((link! as Map)['content'], _lines.sublist(1, 4).join('<br>'));
  }, skip: zstd == null ? 'libzstd אינו זמין' : null);
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/line_content_codec.dart';
import 'package:otzaria/migration/database/line_content_encoder.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/generator/generator.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../../support/zstd_test_lib.dart';

const _longLine =
    'אמר רבי יוחנן משום רבי שמעון בן יוחאי מנין שאין הקדוש ברוך הוא '
    'עושה דבר אלא אם כן נמלך בפמליא של מעלה שנאמר ואמת הדבר וצבא גדול ';

/// עותק של המילון עם מזהה אחר בכותרתו — כמו מילון שאומן מחדש בספרייה.
Uint8List _withDictionaryId(Uint8List dictionary, int id) {
  final copy = Uint8List.fromList(dictionary);
  ByteData.sublistView(copy).setUint32(4, id, Endian.little);
  return copy;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final lib = openZstdForTests();
  final skip = lib == null ? 'libzstd אינו זמין' : null;
  final dictionary = File(
    'test/fixtures/line_content_codec/dict.zdict',
  ).readAsBytesSync();
  final dictionaryId = zstdDictionaryId(dictionary)!;

  setUpAll(() {
    if (lib != null) LineContentCodec.openLibrary = () => lib;
  });

  sqlite3.Database librarySource(Uint8List? dict) {
    final db = sqlite3.sqlite3.openInMemory();
    addTearDown(db.close);
    if (dict != null) {
      db.execute(
        'CREATE TABLE zstd_dict (id INTEGER PRIMARY KEY NOT NULL, '
        'dict BLOB NOT NULL)',
      );
      db.execute('INSERT INTO zstd_dict VALUES (?, ?)', [
        zstdDictionaryId(dict),
        dict,
      ]);
    }
    return db;
  }

  group('LineContentEncoder', () {
    test('מסגרת מתפענחת ב-LineContentCodec לטקסט המקורי', () {
      final encoder = LineContentEncoder(dictionary);
      addTearDown(encoder.dispose);
      expect(encoder.dictionaryId, dictionaryId);

      final db = librarySource(dictionary);
      final codec = LineContentCodec.of(db);
      for (final text in [_longLine, _longLine * 200, '<b>$_longLine</b>']) {
        final frame = encoder.encode(text)!;
        expect(isZstdFrame(frame), isTrue);
        expect(frame.length, lessThan(utf8.encode(text).length));
        expect(codec.text(frame), text);
      }
    }, skip: skip);

    test('שורה שהדחיסה אינה מקצרת או גדולה מתקרת הפענוח נשארת טקסט', () {
      final encoder = LineContentEncoder(dictionary);
      addTearDown(encoder.dispose);
      expect(encoder.encode(''), isNull);
      expect(encoder.encode('א'), isNull);
      final huge = 'א' * (LineContentCodec.maxLineBytes ~/ 2 + 1);
      expect(encoder.encode(huge), isNull);
    }, skip: skip);
  });

  group('ייבוא ל-user_books.db', () {
    late Directory tempDir;
    late Directory category;
    late MyDatabase userBooks;
    late SeforimRepository repository;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('line-encoder-');
      category = Directory(p.join(tempDir.path, 'ספרייה', 'קטגוריה'))
        ..createSync(recursive: true);
      userBooks = MyDatabase.withPath(p.join(tempDir.path, 'user_books.db'));
      repository = SeforimRepository(userBooks);
      await repository.ensureInitialized();
    });

    tearDown(() async {
      repository.lineContentWriter?.dispose();
      userBooks.close();
      try {
        await tempDir.delete(recursive: true);
      } on FileSystemException {
        // נעילת קובץ ב-Windows אינה מעניינה של הבדיקה.
      }
    });

    final lines = ['<h1>ספר</h1>', _longLine * 3, 'א', '', _longLine];

    Future<int> importBook() async {
      await File(
        p.join(category.path, 'ספר.txt'),
      ).writeAsString(lines.join('\n'), flush: true);
      final library = p.join(tempDir.path, 'ספרייה');
      await DatabaseGenerator(
        library,
        repository,
      ).processDirectory(library, null, 0);
      return (await repository.getAllBooksLean()).single.id;
    }

    Future<List<String>> storageTypes(int bookId) async =>
        (await userBooks.database)
            .select(
              'SELECT typeof(content) FROM line WHERE bookId = ? '
              'ORDER BY lineIndex',
              [bookId],
            )
            .map((row) => row.values.first! as String)
            .toList();

    Future<bool> hasDictionaryTable() async => (await userBooks.database)
        .select("SELECT 1 FROM sqlite_master WHERE name = 'zstd_dict'")
        .isNotEmpty;

    test('עם מילון בספרייה: המילון מועתק והשורות הארוכות נדחסות', () async {
      repository.lineContentWriter = LineContentWriter(
        librarySource(dictionary),
      );
      final bookId = await importBook();

      expect(await storageTypes(bookId), [
        'text',
        'blob',
        'text',
        'text',
        'blob',
      ]);
      final db = await userBooks.database;
      final copied = db.select('SELECT id, dict FROM zstd_dict');
      expect(copied.single.values, [dictionaryId, dictionary]);
      expect(await userBooks.lineDao.selectContentByBookId(bookId), lines);
    }, skip: skip);

    test('בלי מילון בספרייה: טקסט כמו היום, בלי zstd_dict', () async {
      repository.lineContentWriter = LineContentWriter(librarySource(null));
      final bookId = await importBook();

      expect(await storageTypes(bookId), everyElement('text'));
      expect(await hasDictionaryTable(), isFalse);
      expect(await userBooks.lineDao.selectContentByBookId(bookId), lines);
    });

    test('מילון חדש בספרייה נוסף ליד הישן, והשורות הישנות נקראות', () async {
      final db = await userBooks.database;
      final oldWriter = LineContentWriter(librarySource(dictionary));
      final oldFrame = oldWriter.encoderFor(db)!.encode(_longLine)!;
      oldWriter.dispose();

      final retrained = _withDictionaryId(dictionary, dictionaryId + 1);
      repository.lineContentWriter = LineContentWriter(
        librarySource(retrained),
      );
      final bookId = await importBook();

      expect(
        db.select('SELECT id FROM zstd_dict ORDER BY id').map((r) => r['id']),
        [dictionaryId, dictionaryId + 1],
      );
      expect(await userBooks.lineDao.selectContentByBookId(bookId), lines);
      expect(LineContentCodec.of(db).text(oldFrame), _longLine);
    }, skip: skip);

    test('מזהה תפוס במילון אחר: השורות נשמרות כטקסט', () async {
      final db = await userBooks.database;
      final collision = Uint8List.fromList(dictionary)
        ..[dictionary.length - 1] ^= 0xFF;
      db.execute(
        'CREATE TABLE zstd_dict (id INTEGER PRIMARY KEY NOT NULL, '
        'dict BLOB NOT NULL)',
      );
      db.execute('INSERT INTO zstd_dict VALUES (?, ?)', [
        dictionaryId,
        collision,
      ]);
      repository.lineContentWriter = LineContentWriter(
        librarySource(dictionary),
      );
      final bookId = await importBook();

      expect(await storageTypes(bookId), everyElement('text'));
      expect(db.select('SELECT dict FROM zstd_dict').single.values, [
        collision,
      ]);
    }, skip: skip);

    test(
      'חיבור שנטען לפני שה-worker הוסיף מילון מפענח את השורות החדשות',
      () async {
        // החיבור הראשי פותח codec כשהמסד עוד בלי zstd_dict.
        final mainConnection = sqlite3.sqlite3.open(userBooks.path);
        addTearDown(mainConnection.close);
        expect(LineContentCodec.of(mainConnection).isCompressed, isFalse);

        repository.lineContentWriter = LineContentWriter(
          librarySource(dictionary),
        );
        final bookId = await importBook();

        final codec = LineContentCodec.of(mainConnection);
        final read = mainConnection
            .select(
              'SELECT content FROM line WHERE bookId = ? ORDER BY lineIndex',
              [bookId],
            )
            .map((row) => codec.text(row.values.first))
            .toList();
        expect(read, lines);
        expect(identical(LineContentCodec.of(mainConnection), codec), isTrue);

        // מילון נוסף בחיבור השני: גם מזהה חדש נטען בלי לפתוח מחדש.
        final retrained = _withDictionaryId(dictionary, dictionaryId + 1);
        final writer = LineContentWriter(librarySource(retrained));
        addTearDown(writer.dispose);
        final frame = writer
            .encoderFor(await userBooks.database)!
            .encode(
              _longLine,
            )!;
        expect(codec.text(frame), _longLine);
      },
      skip: skip,
    );
  });
}

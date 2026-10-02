import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/book_text_reader.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/book.dart' as db_models;
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;

import '../test_helpers/memory_cache_provider.dart';

/// טקסט ספר מלא נקרא מחוץ ל-UI isolate, וזהה בדיוק למסלול הישן על החיבור
/// הראשי: `join('\n')` של תוכן השורות, והבייטים המאוחים של CAST AS BLOB.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  const titles = {1: 'בראשית', 2: 'ריק', 3: 'שורה ריקה', 99: 'חסר'};
  BookTextKey key(int id) => (id: id, title: titles[id]!);
  db_models.Book book(int id) =>
      db_models.Book(id: id, categoryId: 7, sourceId: 1, title: titles[id]!);

  /// טבלאות מינימליות כמו במסד מצורף חיצוני: `book(id, title)` בלי categoryId.
  void createBareTables(sqlite3.Database db) {
    db.execute('CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT)');
    db.execute("INSERT INTO book VALUES (1, 'בראשית'), (2, 'ריק')");
    db.execute(
      'CREATE TABLE line (bookId INTEGER, lineIndex INTEGER, content TEXT)',
    );
  }

  // שורה ריקה, שורה עם \n פנימי, BOM ותו 4-בייטים.
  final contents = <String>[
    '<h1>כותרת</h1>',
    'שורה ראשונה, עם ניקוד: בְּרֵאשִׁית',
    '',
    'שורה\nעם מעבר פנימי',
    '${String.fromCharCode(0xFEFF)}מתחילה ב-BOM',
    'emoji ${String.fromCharCodes([0xD83D, 0xDE00])} ו-ASCII',
  ];

  Future<String> seedDb(String name) async {
    final dbPath = path.join(tempDir.path, '$name.db');
    final database = MyDatabase.withPath(dbPath);
    await SeforimRepository(database).ensureInitialized();
    final db = await database.database;
    db.execute("INSERT INTO category (id, title, level) VALUES (7, 'תנך', 0)");
    db.execute("INSERT INTO source (id, name) VALUES (1, 'אוצריא')");
    db.execute(
      'INSERT INTO book (id, categoryId, sourceId, title, orderIndex, '
      "totalLines) VALUES (1, 7, 1, 'בראשית', 1, ${contents.length}), "
      "(2, 7, 1, 'ריק', 2, 0), (3, 7, 1, 'שורה ריקה', 3, 1)",
    );
    // הכנסה בסדר הפוך — הסדר חייב לבוא מ-lineIndex ולא מסדר ההכנסה.
    for (var i = contents.length - 1; i >= 0; i--) {
      db.execute(
        'INSERT INTO line (id, bookId, lineIndex, content) VALUES (?, 1, ?, ?)',
        [100 + i, i, contents[i]],
      );
    }
    db.execute(
      "INSERT INTO line (id, bookId, lineIndex, content) VALUES (300, 3, 0, '')",
    );
    database.close();
    return dbPath;
  }

  /// שורות [count] של ~150 בתים לספר [bookId], אחרי השורות הקיימות.
  void insertManyLines(
    sqlite3.Database db, {
    required int bookId,
    required int count,
  }) {
    db.execute(
      'WITH RECURSIVE c(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM c '
      'WHERE i < ?) INSERT INTO line (bookId, lineIndex, content) '
      "SELECT ?, i, printf('%.150c', 'x') FROM c",
      [count, bookId],
    );
  }

  /// המסלול הקודם, כפי שרץ על החיבור הראשי.
  ({String? text, Uint8List? bytes}) legacyRead(String dbPath, int bookId) {
    final db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);
    try {
      final lines = db
          .select(
            'SELECT content FROM line WHERE bookId = ? ORDER BY lineIndex',
            [bookId],
          )
          .map((row) => (row.values.first as String?) ?? '')
          .toList();
      final parts = db
          .select(
            'SELECT CAST(content AS BLOB) FROM line WHERE bookId = ? '
            'ORDER BY lineIndex',
            [bookId],
          )
          .map((row) => (row.values.first as Uint8List?) ?? Uint8List(0))
          .toList();
      final builder = BytesBuilder();
      for (var i = 0; i < parts.length; i++) {
        if (i > 0) builder.addByte(0x0A);
        builder.add(parts[i]);
      }
      final bytes = builder.takeBytes();
      return (
        text: lines.isEmpty ? null : lines.join('\n'),
        bytes: parts.isEmpty ? null : bytes,
      );
    } finally {
      db.close();
    }
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria_book_text');
    await Settings.init(cacheProvider: MemoryCacheProvider());
    BookTextReader.mainConnectionReads = 0;
  });

  tearDown(() async {
    DbReadWorker.stallTimeout = const Duration(seconds: 10);
    DbReadWorker.lifecycleCommandTimeout = const Duration(seconds: 4);
    await DbReadWorker.resumeAfterExternalWrite();
    DbReadWorker.disposeForTesting();
    try {
      await tempDir.delete(recursive: true);
    } on FileSystemException {
      // אחרי kill שחרור ה-handle ב-Windows אינו מיידי; ה-temp אינו הנבדק.
    }
  });

  test(
    'הקריאה על חיבור זהה למסלול הקודם, כולל NULL, BOM ו-\\n פנימי',
    () async {
      final dbPath = await seedDb('seforim');
      final db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);
      addTearDown(db.close);

      for (final bookId in [1, 2, 3, 99]) {
        final legacy = legacyRead(dbPath, bookId);
        final k = key(bookId);
        expect(
          await readBookContentText(db, k),
          legacy.text,
          reason: '$bookId',
        );
        expect((await readBookContentBytes(db, k))?.bytes, legacy.bytes);
        expect(
          (await readBookContentTransferable(
            db,
            k,
          ))?.data.materialize().asUint8List(),
          legacy.bytes,
        );
      }
    },
  );

  test('BOM בתחילת שורה מושמט מהטקסט כמו בפענוח שורה-שורה', () async {
    final dbPath = path.join(tempDir.path, 'bom.db');
    final db = sqlite3.sqlite3.open(dbPath);
    addTearDown(db.close);
    createBareTables(db);
    final bom = String.fromCharCode(0xFEFF);
    final rows = ['$bomא', '$bom$bomב', 'ג$bom', bom, '$bomד'];
    for (var i = 0; i < rows.length; i++) {
      db.execute('INSERT INTO line VALUES (1, ?, ?)', [i, rows[i]]);
    }

    final legacy = legacyRead(dbPath, 1);
    expect(legacy.text, ['א', '$bomב', 'ג$bom', '', 'ד'].join('\n'));
    expect(await readBookContentText(db, key(1)), legacy.text);
    // הבייטים נשארים כפי שמאוחסנים, כולל ה-BOM.
    expect(
      (await readBookContentBytes(db, key(1)))?.bytes,
      utf8.encode(rows.join('\n')),
    );
    expect((await readBookContentBytes(db, key(1)))?.bytes, legacy.bytes);
  });

  test('גבולות חוצץ וחצי חוצץ, שורות ארוכות ו-BOM — זהה', () async {
    final dbPath = path.join(tempDir.path, 'chunks.db');
    final db = sqlite3.sqlite3.open(dbPath);
    addTearDown(db.close);
    createBareTables(db);
    final bom = String.fromCharCode(0xFEFF);
    final rows = <String?>[
      for (var i = 0; i < 3000; i++)
        switch (i % 7) {
          0 => '$bomא${'ב' * (i % 50)}',
          1 => null,
          2 => '',
          _ => 'שורה $i ${'x' * (i % 97)}',
        },
      for (var i = 0; i < 96; i++) '$bom${'x' * (32764 + i % 7)}',
      'ג' * 70000,
      '$bom${'ד' * 40000}',
      bom,
    ];
    for (var i = 0; i < rows.length; i++) {
      db.execute('INSERT INTO line VALUES (1, ?, ?)', [i, rows[i]]);
    }

    final legacy = legacyRead(dbPath, 1);
    expect(await readBookContentText(db, key(1)), legacy.text);
    expect((await readBookContentBytes(db, key(1)))?.bytes, legacy.bytes);
    expect(
      (await readBookContentTransferable(
        db,
        key(1),
      ))?.data.materialize().asUint8List(),
      legacy.bytes,
    );
  });

  for (final encoding in ['UTF-8', 'UTF-16le']) {
    test('תוכן NULL נקרא כשורה ריקה במסד $encoding', () async {
      final dbPath = path.join(tempDir.path, '$encoding.db');
      final db = sqlite3.sqlite3.open(dbPath);
      addTearDown(db.close);
      db.execute("PRAGMA encoding = '$encoding'");
      createBareTables(db);
      final rows = <String?>[...contents, null, 'אחרי NULL'];
      for (var i = 0; i < rows.length; i++) {
        db.execute('INSERT INTO line VALUES (1, ?, ?)', [i, rows[i]]);
      }

      final legacy = legacyRead(dbPath, 1);
      expect(legacy.text, contains('\n\nאחרי NULL'));
      expect(await readBookContentText(db, key(1)), legacy.text);
      expect(await readBookContentText(db, key(2)), isNull);
      if (encoding == 'UTF-8') {
        expect((await readBookContentBytes(db, key(1)))?.bytes, legacy.bytes);
      }
    });
  }

  test('מזהה שכבר שייך לספר אחר מחזיר null ולא את תוכנו', () async {
    final dbPath = await seedDb('stale');
    final db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);
    addTearDown(db.close);
    final BookTextKey stale = (id: 1, title: 'שמות');

    expect(await readBookContentText(db, stale), isNull);
    expect(await readBookContentBytes(db, stale), isNull);
    expect(await readBookContentTransferable(db, stale), isNull);
  });

  test(r'שורה עם \n פנימי מסומנת; המפריד בין השורות אינו נספר', () async {
    final dbPath = path.join(tempDir.path, 'newline.db');
    final db = sqlite3.sqlite3.open(dbPath);
    addTearDown(db.close);
    createBareTables(db);
    db.execute("INSERT INTO book VALUES (3, 'שורה ריקה')");
    for (final (bookId, rows) in [
      (1, ['א', 'ב\nג', 'ד']),
      (2, ['א', 'ב', '']),
      (3, ['ב\n']),
    ]) {
      for (var i = 0; i < rows.length; i++) {
        db.execute('INSERT INTO line VALUES (?, ?, ?)', [bookId, i, rows[i]]);
      }
    }

    for (final (bookId, expected) in [(1, true), (2, false), (3, true)]) {
      final bytes = await readBookContentBytes(db, key(bookId));
      final transferable = await readBookContentTransferable(db, key(bookId));
      expect(bytes?.rowHasNewline, expected, reason: '$bookId');
      expect(transferable?.rowHasNewline, expected, reason: '$bookId');
    }
  });

  test(
    'נקודת עצירה נקראת כל 4096 שורות, וזריקה ממנה קוטעת את הקריאה',
    () async {
      final dbPath = await seedDb('checkpoint');
      final writer = sqlite3.sqlite3.open(dbPath);
      insertManyLines(writer, bookId: 3, count: 10000);
      writer.close();
      final db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);
      addTearDown(db.close);

      var calls = 0;
      final text = await readBookContentText(
        db,
        key(3),
        checkpoint: () async => calls++,
      );
      expect(calls, 2);
      expect(text, await readBookContentText(db, key(3)));

      await expectLater(
        readBookContentBytes(
          db,
          key(3),
          checkpoint: () async => throw const FormatException('stop'),
        ),
        throwsFormatException,
      );
      // המשפט נסגר גם בקטיעה: קריאה נוספת על אותו חיבור עובדת.
      expect(await readBookContentText(db, key(1)), legacyRead(dbPath, 1).text);
    },
  );

  test('מסד מצורף נקרא ב-isolate נפרד, לא על החיבור הראשי', () async {
    final dbPath = await seedDb('attached');
    final database = MyDatabase.untrusted(dbPath);
    addTearDown(database.close);
    final repository = SeforimRepository(database);
    final sentBefore = DbReadWorker.sentMessageCount;

    expect(
      await BookTextReader.text(repository, book(1)),
      legacyRead(dbPath, 1).text,
    );
    expect(
      (await BookTextReader.bytes(repository, book(1)))?.bytes,
      legacyRead(dbPath, 1).bytes,
    );
    expect(await BookTextReader.text(repository, book(2)), isNull);
    expect(BookTextReader.mainConnectionReads, 0);
    expect(DbReadWorker.sentMessageCount, sentBefore);
    expect(database.isOpen, isFalse, reason: 'החיבור הראשי לא נפתח כלל');
  });

  test('user_books.db נשאר על החיבור שלו וזהה למסלול הקודם', () async {
    final dbPath = await seedDb('user_books');
    final database = MyDatabase.withPath(dbPath);
    addTearDown(database.close);
    final repository = SeforimRepository(database);

    expect(
      await BookTextReader.text(repository, book(1)),
      legacyRead(dbPath, 1).text,
    );
    expect(BookTextReader.mainConnectionReads, 1);
  });

  group('seforim.db דרך SqliteDataProvider', () {
    late String dbPath;

    setUp(() async {
      dbPath = await seedDb('seforim');
      AppPaths.debugOverrideDataRootPath(path.join(tempDir.path, 'data'));
      await UserBooksDatabaseHolder.instance.close();
      await Settings.setValue<String>(
        SettingsRepository.keyDbEffectivePath,
        dbPath,
      );
      await SqliteDataProvider.instance.dispose();
      await SqliteDataProvider.instance.initialize();
    });

    tearDown(() async {
      await SqliteDataProvider.instance.dispose();
      await UserBooksDatabaseHolder.instance.close();
      AppPaths.debugOverrideDataRootPath(null);
    });

    test('טקסט ובייטים מלאים נקראים ב-worker וזהים למסלול הקודם', () async {
      final provider = SqliteDataProvider.instance;
      final legacy = legacyRead(dbPath, 1);
      final sentBefore = DbReadWorker.sentMessageCount;

      expect(await provider.getBookTextFromDb('בראשית', 7, 'txt'), legacy.text);
      final read = await provider.getBookTextBytesFromDb('בראשית', 7, 'txt');
      expect(read?.bytes, legacy.bytes);
      expect(read?.officialBookId, isNull, reason: r'שורה עם \n פנימי');
      expect(await provider.getBookTextFromDb('ריק', 7, 'txt'), isNull);
      expect(await provider.getBookTextBytesFromDb('ריק', 7, 'txt'), isNull);
      // שורה ריקה יחידה: טקסט '' אך בלי בייטים — כמו קודם.
      expect(await provider.getBookTextFromDb('שורה ריקה', 7, 'txt'), '');
      expect(
        await provider.getBookTextBytesFromDb('שורה ריקה', 7, 'txt'),
        isNull,
      );

      expect(BookTextReader.mainConnectionReads, 0);
      expect(DbReadWorker.sentMessageCount - sentBefore, 6);
    });

    for (final stalled in [false, true]) {
      test('id רשמי רק לספר שאין בשורותיו \\n '
          '(${stalled ? 'isolate חד-פעמי' : 'worker'})', () async {
        final writer = sqlite3.sqlite3.open(dbPath);
        writer.execute(
          'INSERT INTO book (id, categoryId, sourceId, title, orderIndex, '
          "totalLines) VALUES (4, 7, 1, 'שמות', 4, 2)",
        );
        writer.execute(
          'INSERT INTO line (id, bookId, lineIndex, content) '
          "VALUES (400, 4, 0, 'א'), (401, 4, 1, 'ב')",
        );
        writer.close();
        if (stalled) DbReadWorker.stallTimeout = Duration.zero;
        final provider = SqliteDataProvider.instance;

        final clean = await provider.getBookTextBytesFromDb('שמות', 7, 'txt');
        expect(clean?.bytes, utf8.encode('א\nב'));
        expect(clean?.officialBookId, 4);
        final withNewline = await provider.getBookTextBytesFromDb(
          'בראשית',
          7,
          'txt',
        );
        expect(withNewline?.bytes, legacyRead(dbPath, 1).bytes);
        expect(withNewline?.officialBookId, isNull);
      });
    }

    test('patch שהחליף את הספר במזהה אחרי הפתרון — לא נקרא תוכן זר', () async {
      final repository = SqliteDataProvider.instance.repository!;
      final resolved = (await repository.getBookByTitleAndCategory(
        'בראשית',
        7,
      ))!;
      final writer = sqlite3.sqlite3.open(dbPath);
      writer.execute("UPDATE book SET title = 'שמות' WHERE id = 1");
      writer.close();

      expect(await BookTextReader.text(repository, resolved), isNull);
      expect(await BookTextReader.bytes(repository, resolved), isNull);
      expect(BookTextReader.mainConnectionReads, 0);
    });

    test('worker תקוע — הקריאה עוברת ל-isolate חד-פעמי ונשארת זהה', () async {
      DbReadWorker.stallTimeout = Duration.zero;
      final provider = SqliteDataProvider.instance;
      final legacy = legacyRead(dbPath, 1);

      expect(await provider.getBookTextFromDb('בראשית', 7, 'txt'), legacy.text);
      final read = await provider.getBookTextBytesFromDb('בראשית', 7, 'txt');
      expect(read?.bytes, legacy.bytes);
      expect(read?.officialBookId, isNull, reason: r'שורה עם \n פנימי');
      expect(BookTextReader.mainConnectionReads, 0);
    });

    test('השהיה לכתיבה חיצונית קוטעת קריאת ספר ארוכה ב-worker', () async {
      final writer = sqlite3.sqlite3.open(dbPath);
      insertManyLines(writer, bookId: 3, count: 4096);
      writer.close();
      final repository = SqliteDataProvider.instance.repository!;
      final big = book(3);
      final checkpoint = ReceivePort();
      addTearDown(checkpoint.close);
      DbReadWorker.bookReadCheckpointPort = checkpoint.sendPort;
      // חימום: ה-worker והחיבור שלו כבר קיימים כשהקריאה הארוכה מתחילה.
      expect(await BookTextReader.text(repository, book(1)), isNotNull);

      final read = expectLater(
        BookTextReader.text(repository, big),
        throwsA(isA<DbReadWorkerSuspended>()),
      );
      final release = await checkpoint.first as SendPort;
      final suspending = DbReadWorker.suspendForExternalWrite();
      release.send(null);
      expect(await suspending, isTrue);
      await read;
    });

    test('בזמן השהיה לכתיבה חיצונית הקובץ לא נפתח לקריאה', () async {
      final repository = SqliteDataProvider.instance.repository!;
      expect(await DbReadWorker.suspendForExternalWrite(), isTrue);

      await expectLater(
        BookTextReader.text(repository, book(1)),
        throwsA(isA<DbReadWorkerSuspended>()),
      );
      await expectLater(
        DbReadWorker.runOnFreshIsolate(() => 1),
        throwsA(isA<DbReadWorkerSuspended>()),
      );
      expect(BookTextReader.mainConnectionReads, 0);
    });
  });
}

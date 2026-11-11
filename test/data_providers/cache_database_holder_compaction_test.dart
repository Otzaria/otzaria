import 'dart:io';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/cache_database_holder.dart';
import 'package:sqlite3/sqlite3.dart';

import '../helpers/memory_settings_cache.dart';

/// בדיקות לכיווץ `cache.db` — מטמון הטקסט של docx/epub שומר ספרים שלמים,
/// וה-prune לפי TTL משחרר דפים בלי להקטין את הקובץ.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria-cachedb-');
    await Settings.init(cacheProvider: MemorySettingsCache());
    await CacheDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(tempDir.path);
  });

  tearDown(() async {
    await CacheDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('אינו יוצר cache.db כשעדיין אין קובץ', () async {
    final dbPath = await CacheDatabaseHolder.resolveDbPath();
    // resolveDbPath יוצר את תיקיית ה-databases אך לא את הקובץ עצמו.
    expect(await File(dbPath).exists(), isFalse);

    expect(await CacheDatabaseHolder.instance.compactIfFragmented(), isFalse);
    expect(
      await File(dbPath).exists(),
      isFalse,
      reason: 'משתמש שלא פתח ספר חיצוני מעולם לא אמור לקבל cache.db ריק',
    );
  });

  test('מכווץ את cache.db אחרי ניקוי מטמון ההמרות', () async {
    final repository = await CacheDatabaseHolder.instance.repository;
    final db = await repository.database.database;

    // 40 ספרים ממומרים של ~150KB — מדמה מטמון docx/epub שהצטבר.
    final text = 'א' * 150000;
    db.execute('BEGIN');
    for (var i = 0; i < 40; i++) {
      db.execute(
        'INSERT INTO docx_text_cache (filePath, fileSize, lastModified, '
        'converterVersion, text, createdAt, accessedAt) '
        'VALUES (?, 0, 0, 1, ?, 0, 0)',
        ['/books/book-$i.docx', text],
      );
    }
    db.execute('COMMIT');
    db.execute('PRAGMA wal_checkpoint(TRUNCATE)');

    final dbPath = await CacheDatabaseHolder.resolveDbPath();
    final sizeBeforePrune = File(dbPath).lengthSync();

    // ניקוי TTL — כל הרשומות ישנות מהחתך.
    await repository.pruneDocxTextCacheAccessedBefore(1);
    db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    expect(
      File(dbPath).lengthSync(),
      sizeBeforePrune,
      reason: 'המחיקה לבדה משחררת דפים אך לא מקטינה את הקובץ',
    );

    expect(await CacheDatabaseHolder.instance.compactIfFragmented(), isTrue);
    expect(File(dbPath).lengthSync(), lessThan(sizeBeforePrune ~/ 2));
  });

  test('אינו מכווץ cache.db גדול שאין בו דפים פנויים', () async {
    final repository = await CacheDatabaseHolder.instance.repository;
    final db = await repository.database.database;

    final text = 'א' * 150000;
    db.execute('BEGIN');
    for (var i = 0; i < 40; i++) {
      db.execute(
        'INSERT INTO docx_text_cache (filePath, fileSize, lastModified, '
        'converterVersion, text, createdAt, accessedAt) '
        'VALUES (?, 0, 0, 1, ?, 0, 0)',
        ['/books/book-$i.docx', text],
      );
    }
    db.execute('COMMIT');
    db.execute('PRAGMA wal_checkpoint(TRUNCATE)');

    final dbPath = await CacheDatabaseHolder.resolveDbPath();
    expect(File(dbPath).lengthSync(), greaterThan(4 * 1024 * 1024));
    expect(await CacheDatabaseHolder.instance.compactIfFragmented(), isFalse);
  });

  test('אינו מכווץ cache.db קטן — אין מה להרוויח', () async {
    final repository = await CacheDatabaseHolder.instance.repository;
    final db = await repository.database.database;
    db.execute(
      'INSERT INTO docx_text_cache (filePath, fileSize, lastModified, '
      'converterVersion, text, createdAt, accessedAt) '
      'VALUES (?, 0, 0, 1, ?, 0, 0)',
      ['/books/book.docx', 'א' * 150000],
    );
    await repository.pruneDocxTextCacheAccessedBefore(1);

    expect(await CacheDatabaseHolder.instance.compactIfFragmented(), isFalse);
  });

  test('הכיווץ אינו פוגע ברשומות שנשארו', () async {
    final repository = await CacheDatabaseHolder.instance.repository;
    final db = await repository.database.database;

    final text = 'א' * 150000;
    db.execute('BEGIN');
    for (var i = 0; i < 40; i++) {
      db.execute(
        'INSERT INTO docx_text_cache (filePath, fileSize, lastModified, '
        'converterVersion, text, createdAt, accessedAt) '
        'VALUES (?, 0, 0, 1, ?, 0, ?)',
        ['/books/book-$i.docx', text, i == 0 ? 9999 : 0],
      );
    }
    db.execute('COMMIT');

    await repository.pruneDocxTextCacheAccessedBefore(1);
    expect(await CacheDatabaseHolder.instance.compactIfFragmented(), isTrue);

    final survivor = await repository.getDocxTextCacheEntry(
      '/books/book-0.docx',
    );
    expect(survivor, isNotNull);
    expect(survivor!.text, text);
  });

  test('סגירות מקבילות ממתינות לפתיחה ומאפשרות החלפת קובץ', () async {
    final holder = CacheDatabaseHolder.instance;
    final dbPath = await CacheDatabaseHolder.resolveDbPath();
    // קובץ קיים, כדי שההכנה ב-isolate תרוץ ותאריך את הפתיחה.
    await (await holder.repository).database.database;
    await holder.close();

    final opening = holder.repository;
    final closing = holder.close();
    final closingAgain = holder.close();
    final reopening = holder.repository;

    try {
      expect(closingAgain, same(closing));
      await closingAgain;
      expect(holder.repositoryIfInitialized, isNull);
      final oldRepository = await opening;
      // ב-Windows שינוי שם נכשל כשהקובץ עדיין פתוח.
      File(dbPath).renameSync('$dbPath.moved');
      await expectLater(oldRepository.database.database, throwsStateError);
      expect(await reopening, isNot(same(oldRepository)));
    } finally {
      await Future.wait([opening, closing, closingAgain, reopening]);
    }
  });

  test('פתיחה ממתינה לנעילת SQLite בלי לחסום את ה-isolate', () async {
    final holder = CacheDatabaseHolder.instance;
    final dbPath = await CacheDatabaseHolder.resolveDbPath();
    final writer = sqlite3.open(dbPath)
      ..execute('CREATE TABLE probe(value INTEGER)')
      ..execute('BEGIN IMMEDIATE')
      ..execute('INSERT INTO probe VALUES (1)');
    addTearDown(writer.close);

    final opening = holder.repository;
    try {
      final timerFiredFirst = await Future.any([
        opening.then((_) => false, onError: (Object _) => false),
        Future.delayed(const Duration(milliseconds: 500), () => true),
      ]);
      expect(timerFiredFirst, isTrue);
    } finally {
      writer.execute('COMMIT');
      await opening.then<void>((_) {}, onError: (Object _) {});
    }
    final db = await (await opening).database.database;
    expect(db.select('SELECT value FROM probe').single['value'], 1);
  });

  test('החיבור שהועבר קורא שינויים שנשארו ב-WAL', () async {
    final holder = CacheDatabaseHolder.instance;
    final dbPath = await CacheDatabaseHolder.resolveDbPath();
    final original = sqlite3.open(dbPath)..execute('PRAGMA journal_mode=WAL');
    original.config.setIntConfig(1006, 1); // SQLITE_DBCONFIG_NO_CKPT_ON_CLOSE
    original
      ..execute('CREATE TABLE probe(value INTEGER)')
      ..execute('INSERT INTO probe VALUES (7)')
      ..close();
    expect(File('$dbPath-wal').lengthSync(), greaterThan(0));

    final db = await (await holder.repository).database.database;
    expect(db.select('SELECT value FROM probe').single['value'], 7);
    expect(db.select('PRAGMA journal_mode').single.values.single, 'wal');
    expect(db.select('PRAGMA synchronous').single.values.single, 1);
  });

  test('כשל ביצירת הסכמה משחרר את הקובץ ומאפשר לפתוח מחדש', () async {
    final holder = CacheDatabaseHolder.instance;
    final dbPath = await CacheDatabaseHolder.resolveDbPath();
    sqlite3.open(dbPath)
      ..execute('CREATE VIEW category AS SELECT 1')
      ..close();

    await expectLater(holder.repository, throwsA(isA<SqliteException>()));
    File(dbPath).renameSync('$dbPath.invalid');

    final db = await (await holder.repository).database.database;
    expect(db.select('SELECT COUNT(*) FROM category').single.values.single, 0);
  });
}

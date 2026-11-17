import 'dart:io' as io;

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/indexing/utils/book_source_hashes.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late io.Directory tempDir;

  Future<void> seedDatabase(
    MyDatabase database, {
    required bool withContentHash,
    int extraBooks = 0,
    int bookFiveHash = 42,
  }) async {
    await SeforimRepository(database).ensureInitialized();
    final db = await database.database;
    db.execute("INSERT INTO category (id, title, level) VALUES (1, 'א', 0)");
    db.execute("INSERT INTO source (id, name) VALUES (1, 'אוצריא')");
    if (withContentHash) {
      db.execute(
        'ALTER TABLE book ADD COLUMN contentHash INTEGER NOT NULL DEFAULT 0',
      );
    }
    final insert = db.prepare(
      withContentHash
          ? 'INSERT INTO book (id, categoryId, sourceId, title, orderIndex, totalLines, contentHash) VALUES (?, 1, 1, ?, ?, 0, ?)'
          : 'INSERT INTO book (id, categoryId, sourceId, title, orderIndex, totalLines) VALUES (?, 1, 1, ?, ?, 0)',
    );
    for (final (id, hash) in [
      (5, bookFiveHash),
      (6, -2),
      (7, 0),
      for (var i = 0; i < extraBooks; i++) (10 + i, 10 + i),
    ]) {
      insert.execute([id, 'ספר $id', id, if (withContentHash) hash]);
    }
    insert.close();
  }

  Future<void> openDatabase({
    required bool withContentHash,
    int extraBooks = 0,
  }) async {
    final dbPath = p.join(tempDir.path, 'seforim.db');
    final database = MyDatabase.withPath(dbPath);
    await seedDatabase(
      database,
      withContentHash: withContentHash,
      extraBooks: extraBooks,
    );
    database.close();
    await UserBooksDatabaseHolder.instance.close();
    await Settings.setValue<String>(
      SettingsRepository.keyDbEffectivePath,
      dbPath,
    );
    await SqliteDataProvider.instance.dispose();
    await SqliteDataProvider.instance.initialize();
  }

  setUp(() async {
    tempDir = await io.Directory.systemTemp.createTemp('otzaria_source_hash');
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  tearDown(() async {
    await SqliteDataProvider.instance.dispose();
    DbReadWorker.disposeForTesting();
    try {
      await tempDir.delete(recursive: true);
    } on io.FileSystemException {
      // Windows עלול להחזיק את קובץ המסד עוד רגע אחרי הסגירה.
    }
  });

  test('קורא את book.contentHash כ-u64; 0 = אין חותם', () async {
    await openDatabase(withContentHash: true);

    final hashes = await BookSourceHashes.load();

    expect(hashes.covers(BookSource.official), isTrue);
    expect(hashes.forSource(BookSource.official, 5), BigInt.from(42));
    expect(
      hashes.forSource(BookSource.official, 6),
      (BigInt.one << 64) - BigInt.two,
    );
    expect(hashes.forSource(BookSource.official, 7), isNull);
    expect(hashes.forSource(BookSource.user, 5), isNull);
  });

  test('אותו מזהה נשאר נפרד בין מאגרים, ורק מועמדים נקראים', () async {
    await openDatabase(withContentHash: true);
    final attached = MyDatabase.withPath(p.join(tempDir.path, 'attached.db'));
    await seedDatabase(attached, withContentHash: true, bookFiveHash: 84);
    final previousRegistry = AttachedLibraryRegistry.instance;
    final registry = _HashTestRegistry(SeforimRepository(attached));
    AttachedLibraryRegistry.instance = registry;
    addTearDown(() {
      AttachedLibraryRegistry.instance = previousRegistry;
      attached.close();
    });
    final source = BookSource.attached('selected');
    final hashes = await BookSourceHashes.loadForBooks([
      TextBook(id: 5, title: 'רשמי'),
      TextBook(id: 5, title: 'מצורף', source: source),
      TextBook(id: 6, title: 'אישי', source: BookSource.user),
      TextBook(id: 6, title: 'מקובץ', filePath: '/example.txt'),
      TextBook(id: 6, title: 'חיצוני', externalLibraryId: 'external'),
      TextBook(
        id: 6,
        title: 'מסמך מקובץ במסד מצורף',
        filePath: '/another.txt',
        source: BookSource.attached('skipped'),
      ),
    ]);

    expect(registry.requestedSlugs, ['selected']);
    expect(hashes.forSource(BookSource.official, 5), BigInt.from(42));
    expect(hashes.forSource(source, 5), BigInt.from(84));
    expect(hashes.forSource(BookSource.official, 6), isNull);
    expect(hashes.forSource(source, 6), isNull);
  });

  test('נקראים כל המקטעים וגם מסלול צפוף מחזיר רק מועמדים', () async {
    await openDatabase(withContentHash: true, extraBooks: 1600);
    Future<BookSourceHashes> load(int count) => BookSourceHashes.loadForBooks([
      for (var i = 0; i < count; i++) TextBook(id: 10 + i, title: 'ספר'),
      TextBook(id: 2000, title: 'חסר'),
    ]);

    for (final count in [700, 1200]) {
      final hashes = await load(count);
      for (var i = 0; i < count; i++) {
        expect(
          hashes.forSource(BookSource.official, 10 + i),
          BigInt.from(10 + i),
        );
      }
      expect(hashes.forSource(BookSource.official, 10 + count), isNull);
      expect(hashes.forSource(BookSource.official, 2000), isNull);
    }
  });

  test('כל מקטעי החותמים קוראים את אותה גרסה בזמן כתיבה מקבילה', () {
    final path = p.join(tempDir.path, 'snapshot.db');
    final writer = sqlite3.open(path);
    addTearDown(writer.close);
    writer.execute('''
      PRAGMA journal_mode=WAL;
      CREATE TABLE book_data (id INTEGER PRIMARY KEY, contentHash INTEGER);
      WITH RECURSIVE ids(id) AS (
        VALUES (1) UNION ALL SELECT id + 1 FROM ids WHERE id < 1600
      )
      INSERT INTO book_data SELECT id, id FROM ids;
      CREATE VIEW book AS
        SELECT id, observe_hash(id, contentHash) AS contentHash FROM book_data;
    ''');
    final reader = sqlite3.open(path, mode: OpenMode.readOnly);
    addTearDown(reader.close);
    var wrote = false;
    reader.createFunction(
      functionName: 'observe_hash',
      argumentCount: const AllowedArgumentCount(2),
      directOnly: false,
      function: (args) {
        if (!wrote && args.first == 1) {
          writer.execute(
            'UPDATE book_data SET contentHash = -id WHERE id IN (1, 501)',
          );
          wrote = true;
        }
        return args[1];
      },
    );

    final ids = {for (var id = 1; id <= 501; id++) id};
    final duringWrite = BookSourceHashes.readHashesFromDatabase(reader, ids);

    expect(wrote, isTrue);
    expect(duringWrite[1], BigInt.one);
    expect(duringWrite[501], BigInt.from(501));
    final afterWrite = BookSourceHashes.readHashesFromDatabase(reader, ids);
    expect(afterWrite[1], BookSourceHashes.toUnsigned(-1));
    expect(afterWrite[501], BookSourceHashes.toUnsigned(-501));
  });

  test('מסד בלי העמודה — אין חותמים, והבדיקה נופלת לטביעת הטקסט', () async {
    await openDatabase(withContentHash: false);

    final hashes = await BookSourceHashes.loadForBooks([
      TextBook(id: 5, title: 'ספר'),
    ]);

    expect(hashes.covers(BookSource.official), isFalse);
    expect(hashes.forSource(BookSource.official, 5), isNull);
  });
}

class _HashTestRegistry extends AttachedLibraryRegistry {
  _HashTestRegistry(this.repository);

  final SeforimRepository repository;
  final requestedSlugs = <String>[];

  @override
  Future<SeforimRepository?> repositoryFor(String slug) async {
    requestedSlugs.add(slug);
    return repository;
  }
}

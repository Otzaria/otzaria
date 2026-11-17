import 'dart:async';
import 'dart:io' as io;

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/cache/generation_cache.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/indexing/utils/book_facet_metadata_cache.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../test_helpers/memory_cache_provider.dart';
import '../../helpers/seforim_fixture_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late io.Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = await io.Directory.systemTemp.createTemp('otzaria_facet_cache');
    await Settings.init(cacheProvider: MemoryCacheProvider());
    AppPaths.debugOverrideDataRootPath(tempDir.path);
    dbPath = p.join(tempDir.path, 'seforim.db');
    final database = MyDatabase.withPath(dbPath);
    await SeforimRepository(database).ensureInitialized();
    final db = await database.database;
    db.execute("INSERT INTO author (id, name) VALUES (1, 'רש\"י')");
    db.execute('INSERT INTO book_author (bookId, authorId) VALUES (5, 1)');
    database.close();
    await UserBooksDatabaseHolder.instance.close();
    await Settings.setValue<String>(
      SettingsRepository.keyDbEffectivePath,
      dbPath,
    );
    await SqliteDataProvider.instance.dispose();
    await SqliteDataProvider.instance.initialize();
    GenerationCache.instance.clear();
    BookFacetMetadataCache.instance.clear();
  });

  tearDown(() async {
    BookFacetMetadataCache.instance.clear();
    GenerationCache.instance.clear();
    await UserBooksDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(null);
    await SqliteDataProvider.instance.dispose();
    DbReadWorker.disposeForTesting();
    try {
      await tempDir.delete(recursive: true);
    } on io.FileSystemException {
      // Windows עלול להחזיק את קובץ המסד עוד רגע אחרי הסגירה.
    }
  });

  List<String> facetsOf(Book book) => BookFacetMetadataCache.instance
      .extraFacetsForBook(book, isFoundational: false)
      .where((facet) => facet.startsWith('/author/'))
      .toList();

  Future<void> activate(String path) async {
    await SqliteDataProvider.instance.dispose();
    await Settings.setValue<String>(
      SettingsRepository.keyDbEffectivePath,
      path,
    );
    await SqliteDataProvider.instance.initialize();
    GenerationCache.instance.clear();
    BookFacetMetadataCache.instance.clear();
  }

  test('אחרי החלפת מסד, clear גורם לקריאת המחברים החדשים', () async {
    final book = TextBook(id: 5, title: 'ספר');
    await BookFacetMetadataCache.instance.warmUp();
    expect(facetsOf(book), ['/author/רש"י']);

    final writer = sqlite3.open(dbPath);
    writer.execute("UPDATE author SET name = 'רמב\"ן' WHERE id = 1");
    writer.close();

    await BookFacetMetadataCache.instance.warmUp();
    expect(
      facetsOf(book),
      ['/author/רש"י'],
      reason: 'בלי clear המטמון נשאר על המסד הקודם',
    );

    BookFacetMetadataCache.instance.clear();
    expect(facetsOf(book), isEmpty);
    await BookFacetMetadataCache.instance.warmUp();
    expect(facetsOf(book), ['/author/רמב"ן']);
  });

  test('שומר מחברים מרובים וכפילויות ומנקה רווחים ושמות ריקים', () async {
    final writer = sqlite3.open(dbPath);
    writer.execute('''
      INSERT INTO book (id, categoryId, sourceId, title, isBaseBook)
      VALUES (5, 1, 1, 'ספר', 1)
    ''');
    writer.execute('''
      INSERT INTO author (id, name)
      VALUES (2, '  רמב"ן  '), (3, '   '), (4, ' רש"י ')
    ''');
    writer.execute('''
      INSERT INTO book_author (bookId, authorId)
      VALUES (5, 2), (5, 3), (5, 4)
    ''');
    writer.close();

    await BookFacetMetadataCache.instance.warmUp();

    expect(
      BookFacetMetadataCache.instance.extraFacetsForBook(
        TextBook(id: 5, title: 'ספר'),
        isFoundational: false,
      ),
      ['/author/רש"י', '/author/רמב"ן', '/author/רש"י', '/base'],
    );
  });

  for (final variant in [
    SeforimFixtureVariant.minimal,
    SeforimFixtureVariant.missingAuthorTables,
    SeforimFixtureVariant.viewImpostor,
  ]) {
    test(
      'סכמה אופציונלית אינה מחייבת טבלאות מחברים: ${variant.name}',
      () async {
        final path = SeforimFixtureDb.create(tempDir, variant);
        await activate(path);

        await BookFacetMetadataCache.instance.warmUp();

        expect(facetsOf(TextBook(id: 1, title: 'בראשית')), isEmpty);
      },
    );
  }

  test('חימום מטמון אינו יוצר מסד אישי שאינו פתוח', () async {
    final holder = UserBooksDatabaseHolder.instance;
    final path = await UserBooksDatabaseHolder.resolveDbPath();
    expect(holder.repositoryIfInitialized, isNull);
    expect(await io.File(path).exists(), isFalse);

    await BookFacetMetadataCache.instance.warmUp();

    expect(holder.repositoryIfInitialized, isNull);
    expect(await io.File(path).exists(), isFalse);
    expect(facetsOf(TextBook(id: 5, title: 'ספר')), ['/author/רש"י']);
  });

  test('מזהה זהה בספרייה ובמסד האישי שומר מחברים וספרי יסוד נפרדים', () async {
    final repo = await UserBooksDatabaseHolder.instance.repository;
    final db = await repo.database.database;
    db.execute('''
      INSERT INTO book (id, categoryId, sourceId, title, isBaseBook)
      VALUES (5, 1, 1, 'ספר אישי', 1)
    ''');
    db.execute("INSERT INTO author (id, name) VALUES (1, 'מחבר אישי')");
    db.execute('INSERT INTO book_author (bookId, authorId) VALUES (5, 1)');

    await Future.wait([
      BookFacetMetadataCache.instance.warmUp(),
      BookFacetMetadataCache.instance.warmUp(),
    ]);

    expect(
      BookFacetMetadataCache.instance.extraFacetsForBook(
        TextBook(id: 5, title: 'ספר'),
        isFoundational: false,
      ),
      ['/author/רש"י'],
    );
    expect(
      BookFacetMetadataCache.instance.extraFacetsForBook(
        TextBook(id: 5, title: 'ספר אישי', source: BookSource.user),
        isFoundational: false,
      ),
      ['/author/מחבר אישי', '/base'],
    );
    expect(
      BookFacetMetadataCache.instance.extraFacetsForBook(
        TextBook(id: 5, title: 'ספר מצורף', source: BookSource.attached('x')),
        isFoundational: false,
      ),
      isEmpty,
    );
  });

  test('clear בזמן המתנה לקריאה אינו מפרסם נתונים מהחימום הישן', () async {
    await GenerationCache.instance.warmUp();
    final gates = [Completer<void>(), Completer<void>()];
    final active = [
      for (final gate in gates)
        DbReadWorker.trackFallbackRead(() => gate.future),
    ];
    addTearDown(() async {
      for (final gate in gates) {
        if (!gate.isCompleted) gate.complete();
      }
      await Future.wait(active);
    });

    final loading = BookFacetMetadataCache.instance.warmUp();
    await pumpEventQueue();
    expect(DbReadWorker.resourceUsage.queuedReads, 1);

    BookFacetMetadataCache.instance.clear();
    for (final gate in gates) {
      gate.complete();
    }
    await Future.wait([...active, loading]);
    final book = TextBook(id: 5, title: 'ספר');
    expect(facetsOf(book), isEmpty);

    final writer = sqlite3.open(dbPath);
    writer.execute("UPDATE author SET name = 'חדש' WHERE id = 1");
    writer.close();
    await BookFacetMetadataCache.instance.warmUp();
    expect(facetsOf(book), ['/author/חדש']);
  });

  test('השהיית קריאות אינה מסמנת חימום מוצלח ומאפשרת ניסיון חוזר', () async {
    await GenerationCache.instance.warmUp();
    await DbReadWorker.suspendForExternalWrite();
    try {
      await BookFacetMetadataCache.instance.warmUp();
      expect(facetsOf(TextBook(id: 5, title: 'ספר')), isEmpty);
    } finally {
      await DbReadWorker.resumeAfterExternalWrite();
    }

    await BookFacetMetadataCache.instance.warmUp();
    expect(facetsOf(TextBook(id: 5, title: 'ספר')), ['/author/רש"י']);
  });
}

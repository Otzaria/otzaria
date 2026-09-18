import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_libraries_repository.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_probe.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_store.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/file_system_library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../helpers/seforim_fixture_db.dart';
import '../test_helpers/memory_cache_provider.dart';

const _personalRoot = 'ספרים אישיים';

Category? _child(Category parent, String title) =>
    parent.subCategories.where((c) => c.title == title).firstOrNull;

/// מסד מצורף עוין: הוכחה שקובץ מסד אינו מריץ דבר, אינו נכתב, ואינו נועל את
/// הקובץ אחרי שחרור; ומסד שנעלם אינו מוחק הגדרות.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory copyDir;
  late String libraryPath;
  late AttachedLibraryRegistry registry;
  late AttachedLibrariesRepository attached;
  final provider = DatabaseLibraryProvider.instance;
  final previousRegistry = AttachedLibraryRegistry.instance;
  final previousDataRoot = AppPaths.cachedDataRootPath;

  String fixture(
    String name, {
    SeforimFixtureVariant variant = SeforimFixtureVariant.full,
    void Function(sqlite3.Database db)? tamper,
  }) {
    final dir = Directory(p.join(tempDir.path, 'attached', name))
      ..createSync(recursive: true);
    final created = SeforimFixtureDb.create(dir, variant);
    final path = p.join(dir.path, '$name.db');
    File(created).renameSync(path);
    if (tamper != null) {
      final db = sqlite3.sqlite3.open(path);
      try {
        tamper(db);
      } finally {
        db.close();
      }
    }
    return path;
  }

  Future<AttachedLibrary> attach(String path) async {
    final result = await attached.importFile(path);
    expect(result.isOk, isTrue, reason: '${result.problem}');
    return result.library!;
  }

  Future<Library> buildCatalog() async {
    provider.clearCache();
    await provider.initialize();
    return provider.buildLibraryCatalog({}, libraryPath);
  }

  Future<String?> readText(AttachedLibrary library) =>
      LibraryProviderManager.instance.getBookText(
        SeforimFixtureIds.bereshitTitle,
        categoryId: SeforimFixtureIds.torahCategoryId,
        fileType: 'txt',
        preferSource: library.source!,
      );

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    tempDir = await Directory.systemTemp.createTemp('otzaria_attached_sec');
    copyDir = Directory(p.join(tempDir.path, 'copies'));
    libraryPath = p.join(tempDir.path, 'library');
    Directory(libraryPath).createSync();
    final official = SeforimFixtureDb.create(
      Directory(libraryPath),
      SeforimFixtureVariant.full,
    );
    File(
      official,
    ).renameSync(p.join(libraryPath, DatabaseConstants.databaseFileName));

    await provider.sqliteProvider.dispose();
    provider.clearCache();
    await UserBooksDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(p.join(tempDir.path, 'data_root'));
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryPath,
      libraryPath,
    );
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryFolderName,
      '',
    );
    await Settings.setValue<String>(SettingsRepository.keyDbEffectivePath, '');

    registry = AttachedLibraryRegistry(idleTimeout: null);
    AttachedLibraryRegistry.instance = registry;
    attached = AttachedLibrariesRepository(
      registry: registry,
      probe: (path) async => AttachedLibraryProbe.probeSync(path),
      copyDirectory: () async => copyDir.path,
      copyByDefault: false,
    );
  });

  tearDown(() async {
    LibraryProviderManager.instance.resetForTesting();
    FileSystemLibraryProvider.instance.resetForTesting();
    provider.clearCache();
    await provider.sqliteProvider.dispose();
    await registry.closeAll();
    AttachedLibraryRegistry.instance = previousRegistry;
    await UserBooksDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(previousDataRoot);
    await attached.dispose();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('חיבור מוקשח דרך ה-registry', () {
    test(
      'query_only, trusted_schema, defensive, בלי הרחבות ובלי mmap',
      () async {
        final library = await attach(fixture('מוקשח'));
        final repo = (await registry.repositoryFor(library.slug))!;
        final db = await repo.database.database;

        int pragma(String name) =>
            db.select('PRAGMA $name').first.values.first as int;
        expect(pragma('query_only'), 1);
        expect(pragma('trusted_schema'), 0);
        // mmap על קובץ בכונן נשלף: שגיאת I/O היא אות שמפיל את התהליך.
        expect(pragma('mmap_size'), 0);
        // defensive: writable_schema אינו נדלק.
        db.execute('PRAGMA writable_schema=ON');
        expect(pragma('writable_schema'), 0);
        expect(
          () => db.select("SELECT load_extension('evil')"),
          throwsA(isA<sqlite3.SqliteException>()),
        );
        expect(
          () => db.execute("UPDATE book SET title = 'x'"),
          throwsA(isA<sqlite3.SqliteException>()),
        );
        expect(
          () => db.execute('VACUUM'),
          throwsA(isA<sqlite3.SqliteException>()),
        );
      },
    );

    test('VIEW שקורא לפונקציה לא-תמימה נחסם; טריגר אינו רץ', () async {
      final marker = File(p.join(tempDir.path, 'pwned.txt'));
      final path = fixture(
        'עוין',
        tamper: (db) {
          db.execute(
            "CREATE VIEW evil AS SELECT load_extension('evil') AS x",
          );
          db.execute(
            'CREATE TRIGGER t AFTER UPDATE ON book BEGIN '
            "INSERT INTO source VALUES (777, 'pwned'); END",
          );
          db.execute(
            "ATTACH DATABASE '${marker.path.replaceAll("'", "''")}' AS x",
          );
          db.execute('DETACH DATABASE x');
        },
      );
      if (marker.existsSync()) marker.deleteSync();
      final library = await attach(path);
      final repo = (await registry.repositoryFor(library.slug))!;
      final db = await repo.database.database;

      expect(
        () => db.select('SELECT * FROM evil'),
        throwsA(isA<sqlite3.SqliteException>()),
      );
      await buildCatalog();
      expect(await readText(library), isNotNull);
      expect(marker.existsSync(), isFalse);
      final check = sqlite3.sqlite3.open(path, mode: sqlite3.OpenMode.readOnly);
      addTearDown(check.close);
      expect(check.select('SELECT id FROM source WHERE id = 777'), isEmpty);
    });

    test('ATTACH מתוך החיבור אינו יוצר קובץ', () async {
      final library = await attach(fixture('attach'));
      final repo = (await registry.repositoryFor(library.slug))!;
      final db = await repo.database.database;
      final target = p.join(tempDir.path, 'created_by_attach.db');
      try {
        db.execute("ATTACH DATABASE '$target' AS x");
        db.execute('CREATE TABLE x.t (a)');
      } on sqlite3.SqliteException {
        // צפוי.
      }
      expect(File(target).existsSync(), isFalse);
    });
  });

  group('קבצים ותוכן עוינים', () {
    test('ZIP בסיומת db, קובץ ריק וכותרת SQLite עם זבל — נדחים', () {
      final zip = p.join(tempDir.path, 'archive.db');
      File(
        zip,
      ).writeAsBytesSync([0x50, 0x4B, 0x03, 0x04, ...List.filled(200, 0)]);
      final empty = p.join(tempDir.path, 'empty.db');
      File(empty).writeAsBytesSync(const []);
      final garbage = p.join(tempDir.path, 'garbage.db');
      File(garbage).writeAsBytesSync([
        ...'SQLite format 3'.codeUnits,
        0,
        ...List.generate(8000, (i) => (i * 37) & 0xff),
      ]);

      expect(
        AttachedLibraryProbe.probeSync(zip).problem,
        AttachedLibraryProblem.notSqlite,
      );
      expect(
        AttachedLibraryProbe.probeSync(empty).problem,
        AttachedLibraryProblem.notSqlite,
      );
      expect(AttachedLibraryProbe.probeSync(garbage).isOk, isFalse);
    });

    test(
      'library_id עוין — slug חוקי בלי מפרידי נתיב, והעותק בתיקייה',
      () async {
        for (final id in [
          '../../evil',
          r'..\..\evil',
          'a|b',
          'C:evil',
          r'\\server\share',
          '..',
          '',
          '   ',
          'x' * 5000,
          'con',
        ]) {
          final slug = AttachedLibraryProbe.slugFor(
            libraryId: id,
            fileName: 'file',
          );
          expect(BookSource.isValidSlug(slug), isTrue, reason: id);
          expect(slug, isNot(contains('/')), reason: id);
          expect(slug, isNot(contains(r'\')), reason: id);
          expect(slug, isNot(contains(':')), reason: id);
          expect(slug, isNot(startsWith('.')), reason: id);
        }

        final path = fixture(
          'traversal',
          tamper: (db) => db.execute(
            "INSERT INTO schema_meta VALUES ('library_id', '../../escaped')",
          ),
        );
        final result = await attached.importFile(
          path,
          mode: AttachedLibraryMode.copy,
        );
        expect(result.isOk, isTrue, reason: '${result.problem}');
        expect(p.isWithin(copyDir.path, result.library!.path), isTrue);
        expect(p.dirname(result.library!.path), copyDir.path);
      },
    );

    test('VIEW בשם טבלה מוכרת אינו נקרא בעץ ובקריאה', () async {
      final library = await attach(
        fixture(
          'מתחזה',
          variant: SeforimFixtureVariant.viewImpostor,
          tamper: (db) {
            db.execute('DROP TABLE connection_type');
            db.execute(
              "CREATE VIEW connection_type AS SELECT 1 AS id, 'מזויף' AS name",
            );
          },
        ),
      );
      final catalog = await buildCatalog();
      final books = catalog
          .getAllBooks()
          .where((b) => b.source == library.source)
          .toList();
      expect(books, hasLength(2));
      expect(books.map((b) => b.author), everyElement(isNot('מזויף')));
      expect(await readText(library), isNotNull);
      expect(
        library.capabilities,
        isNot(contains(AttachedLibraryCapability.links)),
      );
    });

    test('טבלאות תוסף במסד — העץ נבנה ואין שום התקנה', () async {
      final library = await attach(
        fixture('תוספים', variant: SeforimFixtureVariant.pluginTables),
      );
      final catalog = await buildCatalog();
      final root = _child(_child(catalog, _personalRoot)!, library.displayName);
      expect(root, isNotNull);
      expect(await readText(library), isNotNull);
    });

    test('נתיבי קובץ שבורחים מתיקיית המסד — לא מוצגים ולא נפתחים', () async {
      final library = await attach(
        fixture(
          'נתיבים',
          tamper: (db) {
            db.execute('ALTER TABLE book ADD COLUMN fileType TEXT');
            db.execute('ALTER TABLE book ADD COLUMN filePath TEXT');
            db.execute(
              'INSERT INTO book (id, categoryId, sourceId, title, fileType, '
              "filePath) VALUES (10, 2, 1, 'pdf-escape', 'pdf', "
              "'../../../Windows/win.ini'), (11, 2, 1, 'pdf-unc', 'pdf', "
              r"'\\server\share\x.pdf'), (12, 2, 1, 'txt-path', 'txt', "
              r"'C:\Windows\win.ini')",
            );
          },
        ),
      );
      final catalog = await buildCatalog();
      final books = catalog
          .getAllBooks()
          .where((b) => b.source == library.source)
          .toList();
      final titles = books.map((b) => b.title).toSet();
      expect(titles, isNot(contains('pdf-escape')));
      expect(titles, isNot(contains('pdf-unc')));
      final txt = books.firstWhere((b) => b.title == 'txt-path');
      expect(txt.filePath, isNull);
    });

    test('סכמה זבל במסד אחד אינה פוגעת בעץ ובמסדים האחרים', () async {
      final good = await attach(fixture('תקין'));
      final bad = await attach(
        fixture(
          'זבל',
          tamper: (db) {
            db.execute('DROP TABLE category');
            db.execute(
              'CREATE TABLE category (id TEXT, parentId TEXT, title BLOB)',
            );
            db.execute(
              "INSERT INTO category VALUES ('x', 'y', x'00ff'), ('2', '2', 5)",
            );
            db.execute("UPDATE book SET title = 42, orderIndex = 'z'");
          },
        ),
      );

      final catalog = await buildCatalog();

      expect(
        catalog.getAllBooks().where((b) => b.source == good.source),
        hasLength(2),
      );
      expect(
        catalog.getAllBooks().where((b) => b.source.isOfficial),
        hasLength(2),
      );
      expect(bad.isOk, isTrue);
    });
  });

  group('נעילת קובץ', () {
    test('אחרי קריאה ו"שחרר קובץ" — אפשר למחוק ולהחליף את הקובץ', () async {
      final path = fixture('נעילה');
      final library = await attach(path);
      await buildCatalog();
      expect(await readText(library), isNotNull);
      expect(registry.isOpen(library.slug), isTrue);

      await attached.release(library);

      expect(registry.isOpen(library.slug), isFalse);
      File(path).deleteSync();
      expect(File(path).existsSync(), isFalse);
      File(fixture('תחליף')).copySync(path);
      expect(await readText(library), isNotNull);
      await attached.release(library);
      File(path).deleteSync();
    });

    test('סגירה אחרי זמן סרק משחררת את הקובץ', () async {
      final idle = AttachedLibraryRegistry(
        idleTimeout: const Duration(minutes: 5),
      );
      AttachedLibraryRegistry.instance = idle;
      addTearDown(idle.closeAll);
      final path = fixture('סרק');
      final repository = AttachedLibrariesRepository(
        registry: idle,
        probe: (path) async => AttachedLibraryProbe.probeSync(path),
        copyByDefault: false,
      );
      addTearDown(repository.dispose);
      final library = (await repository.importFile(path)).library!;
      await idle.repositoryFor(library.slug);
      expect(idle.isOpen(library.slug), isTrue);

      idle.closeIdle(now: DateTime.now().add(const Duration(minutes: 10)));

      expect(idle.isOpen(library.slug), isFalse);
      File(path).deleteSync();
    });
  });

  group('מסד שאינו נגיש', () {
    test('קובץ שהועבר: ספרים מוסתרים, הגדרות נשמרות; חזרה — מופיעים', () async {
      final path = fixture('נשלף');
      final library = await attach(path);
      expect(
        (await buildCatalog()).getAllBooks().where(
          (b) => b.source == library.source,
        ),
        hasLength(2),
      );
      await attached.release(library);
      final moved = '$path.away';
      File(path).renameSync(moved);

      await attached.rescan();
      final catalog = await buildCatalog();

      final stored = const AttachedLibraryStore().loadLibraries().single;
      expect(stored.status, AttachedLibraryStatus.unreachable);
      expect(stored.slug, library.slug);
      expect(stored.path, path);
      expect(
        catalog.getAllBooks().where((b) => b.source.isAttached),
        isEmpty,
      );
      expect(
        catalog.getAllBooks().where((b) => b.source.isOfficial),
        isNotEmpty,
      );
      expect(await readText(library), isNull);

      File(moved).renameSync(path);
      await attached.rescan();

      expect(registry.libraries.single.status, AttachedLibraryStatus.ok);
      expect(
        (await buildCatalog()).getAllBooks().where(
          (b) => b.source == library.source,
        ),
        hasLength(2),
      );
      expect(await readText(library), isNotNull);
    });
  });

  group('סדר (החלטה 10)', () {
    test('במיזוג, ספרי המסד אחרי הספרים הרשמיים באותה קטגוריה', () async {
      final first = await attach(
        fixture(
          'ראשון',
          tamper: (db) => db.execute(
            "INSERT INTO category VALUES (3, 1, 'קטגוריה חדשה', 1, 0, NULL, "
            'NULL)',
          ),
        ),
      );
      final second = await attach(fixture('שני'));
      for (final library in [first, second]) {
        await attached.setPlacement(
          library,
          AttachedLibraryPlacement.mergeIntoLibrary,
        );
      }

      final catalog = await buildCatalog();

      final torah = _child(_child(catalog, 'תנ"ך')!, 'תורה')!;
      final sorted = [...torah.books]
        ..sort((a, b) => a.order.compareTo(b.order));
      expect(
        [for (final b in sorted) b.source],
        [
          BookSource.official,
          BookSource.official,
          first.source,
          first.source,
          second.source,
          second.source,
        ],
      );
      final tanach = _child(catalog, 'תנ"ך')!;
      final newCategory = _child(tanach, 'קטגוריה חדשה');
      if (newCategory != null) {
        final officialOrders = tanach.subCategories
            .where((c) => c != newCategory)
            .map((c) => c.order);
        expect(
          newCategory.order,
          greaterThan(officialOrders.reduce((a, b) => a > b ? a : b)),
        );
      }
    });
  });
}

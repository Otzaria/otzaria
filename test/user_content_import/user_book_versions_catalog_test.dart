import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_libraries_repository.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_probe.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/file_system_library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/services/parallel_editions_service.dart';
import 'package:otzaria/library/view/book_versions_dialog.dart';
import 'package:otzaria/migration/models/book.dart' as migration_models;
import 'package:otzaria/migration/models/category.dart' as migration_models;
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/text_book/text_book_repository.dart';
import 'package:otzaria/text_book/utils/book_versions_action.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../helpers/seforim_fixture_db.dart';
import '../test_helpers/memory_cache_provider.dart';

const _personalRoot = 'ספרים אישיים';
const _versionTitle = 'כתב יד';

Category? _child(Category parent, String title) =>
    parent.subCategories.where((c) => c.title == title).firstOrNull;

/// גרסה אישית של ספר רשמי/מצורף מקצה לקצה: seforim.db (fixture) +
/// user_books.db אמיתי, בניית העץ, דיאלוג הגרסאות, המהדורות המקבילות וקריאה.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String libraryPath;
  late String officialDbPath;
  late AttachedLibraryRegistry registry;
  late AttachedLibrariesRepository attached;
  final provider = DatabaseLibraryProvider.instance;
  final previousRegistry = AttachedLibraryRegistry.instance;
  final previousDataRoot = AppPaths.cachedDataRootPath;
  final previousRepository = AttachedLibrariesRepository.instance;
  final previousExternalIds = ParallelEditionsService.builtInExternalIdsFor;

  /// ספר אישי בתיקייה "מסמכים" עם קובץ טקסט; מחזיר את מזההו ב-user_books.
  Future<int> addUserBook(String title, String content) async {
    final repo = await UserBooksDatabaseHolder.instance.repository;
    final raw = await repo.database.database;
    final rootRows = raw.select(
      'SELECT id FROM category WHERE title = ?',
      [_personalRoot],
    );
    final rootId = rootRows.isNotEmpty
        ? rootRows.first['id'] as int
        : await repo.insertCategory(
            const migration_models.Category(
              title: _personalRoot,
              parentId: null,
              level: 0,
              orderIndex: 1,
            ),
          );
    final folderRows = raw.select(
      "SELECT id FROM category WHERE title = 'docs'",
    );
    final folderId = folderRows.isNotEmpty
        ? folderRows.first['id'] as int
        : await repo.insertCategory(
            migration_models.Category(
              title: 'docs',
              parentId: rootId,
              level: 1,
              orderIndex: 1,
            ),
          );
    final sourceRows = raw.select("SELECT id FROM source WHERE name = 'user'");
    final sourceId = sourceRows.isNotEmpty
        ? sourceRows.first['id'] as int
        : await repo.insertSource('user', -20);
    final file = File(p.join(tempDir.path, '${title.hashCode}.txt'))
      ..writeAsStringSync(content);
    return repo.insertBook(
      migration_models.Book(
        categoryId: folderId,
        sourceId: sourceId,
        title: title,
        filePath: file.path,
        fileType: 'txt',
      ),
    );
  }

  /// מצהיר על [versionBookId] כגרסה של ספר [primaryTitle] ממקור [source].
  Future<void> declareVersion(
    int versionBookId, {
    required BookSource source,
    required String primaryTitle,
    String? categoryPath,
  }) async {
    final repo = await UserBooksDatabaseHolder.instance.repository;
    final raw = await repo.database.database;
    raw.execute(
      'INSERT INTO user_book_version (versionBookId, primaryBookId, '
      'primarySource, primaryTitle, primaryCategoryPath, versionTitle, source) '
      "VALUES (?, NULL, ?, ?, ?, ?, 'import')",
      [
        versionBookId,
        source.wireKey,
        primaryTitle,
        categoryPath,
        _versionTitle,
      ],
    );
  }

  Future<Library> buildCatalog() async {
    provider.clearCache();
    await provider.initialize();
    return provider.buildLibraryCatalog({}, libraryPath);
  }

  Book officialBereshit(Library catalog) =>
      _child(_child(catalog, 'תנ"ך')!, 'תורה')!.books.firstWhere(
        (b) =>
            b.title == SeforimFixtureIds.bereshitTitle && b.source.isOfficial,
      );

  List<Book> personalTreeBooks(Library catalog) =>
      _child(catalog, _personalRoot)?.getAllBooks() ?? const [];

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    tempDir = await Directory.systemTemp.createTemp('otzaria_user_versions');
    libraryPath = p.join(tempDir.path, 'library');
    Directory(libraryPath).createSync();
    final official = SeforimFixtureDb.create(
      Directory(libraryPath),
      SeforimFixtureVariant.full,
    );
    officialDbPath = p.join(libraryPath, DatabaseConstants.databaseFileName);
    File(official).renameSync(officialDbPath);

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
      copyByDefault: false,
    );
    AttachedLibrariesRepository.instance = attached;
    ParallelEditionsService.builtInExternalIdsFor = (_) async => const [];
  });

  tearDown(() async {
    ParallelEditionsService.builtInExternalIdsFor = previousExternalIds;
    AttachedLibrariesRepository.instance = previousRepository;
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

  test('הגרסה נקשרת לספר הרשמי, יוצאת מהעץ ונשארת מאונדקסת', () async {
    final versionId = await addUserBook('ספר א', 'personal A');
    await declareVersion(
      versionId,
      source: BookSource.official,
      primaryTitle: SeforimFixtureIds.bereshitTitle,
      categoryPath: 'תורה',
    );

    final catalog = await buildCatalog();
    final primary = officialBereshit(catalog);

    final personal = provider.getPersonalVersionsOf(primary).single;
    expect(personal.displayTitle, _versionTitle);
    expect(personal.separateBook?.source, BookSource.user);
    expect(personal.separateBook?.id, versionId);
    expect(
      personalTreeBooks(catalog).map((b) => b.id),
      isNot(contains(versionId)),
    );
    expect(catalog.offTreeBooks.map((b) => b.id), [versionId]);

    final group = provider.getUserBookVersions(personal.separateBook!);
    expect(group, hasLength(2));
    expect(group.first.separateBook, same(primary));
    expect(group.last.separateBook?.id, versionId);
  });

  test('מזהה הספר הרשמי השתנה בעדכון — הגרסה נקשרת לפי הכותרת', () async {
    final db = sqlite3.sqlite3.open(officialDbPath);
    for (final table in ['line', 'book_version']) {
      db.execute('UPDATE $table SET bookId = 77 WHERE bookId = 1');
    }
    db.execute('UPDATE book SET id = 77 WHERE id = 1');
    db.close();
    final versionId = await addUserBook('ספר א', 'personal A');
    await declareVersion(
      versionId,
      source: BookSource.official,
      primaryTitle: SeforimFixtureIds.bereshitTitle,
    );

    final catalog = await buildCatalog();
    final primary = officialBereshit(catalog);

    expect(primary.id, 77);
    expect(
      provider.getPersonalVersionsOf(primary).single.separateBook?.id,
      versionId,
    );
  });

  test('ראשי שלא נמצא, או בקטגוריה אחרת — הספר נשאר ספר אישי רגיל', () async {
    final missingId = await addUserBook('ספר א', 'personal A');
    final wrongCategoryId = await addUserBook('ספר ב', 'personal B');
    await declareVersion(
      missingId,
      source: BookSource.official,
      primaryTitle: 'no such book',
    );
    await declareVersion(
      wrongCategoryId,
      source: BookSource.official,
      primaryTitle: SeforimFixtureIds.bereshitTitle,
      categoryPath: 'other',
    );

    final catalog = await buildCatalog();

    final tree = personalTreeBooks(catalog).map((b) => b.id).toSet();
    expect(tree, containsAll([missingId, wrongCategoryId]));
    expect(catalog.offTreeBooks, isEmpty);
    expect(provider.getPersonalVersionsOf(officialBereshit(catalog)), isEmpty);
    for (final book in personalTreeBooks(catalog)) {
      expect(provider.getUserBookVersions(book), isEmpty);
      expect(await hasBookVersionsToOpen(book), isFalse);
    }
  });

  test('בורר הנוסחאות בקורא מציג את המהדורה הרשמית ואת הגרסה האישית', () async {
    final versionId = await addUserBook('ספר א', 'personal A');
    await declareVersion(
      versionId,
      source: BookSource.official,
      primaryTitle: SeforimFixtureIds.bereshitTitle,
    );
    final catalog = await buildCatalog();
    final primary = officialBereshit(catalog);
    final personal = catalog.offTreeBooks.single;

    expect(await hasBookVersionsToOpen(primary), isTrue);
    expect(await hasBookVersionsToOpen(personal), isTrue);

    final versions = await loadBookVersions(primary);
    expect(versions.map((v) => v.versionTitle), ['Alt', _versionTitle]);
    // כשנוסח 'Alt' פתוח — הגרסה האישית עדיין ברשימה.
    final selectable = selectableVersionsFor(versions, 'Alt');
    expect(selectable.single.separateBook?.id, versionId);

    final fromPersonal = await loadBookVersions(personal);
    expect(fromPersonal.first.separateBook, same(primary));
  });

  test('פתיחת הגרסה האישית קוראת את הקובץ האישי ולא את הרשמי', () async {
    final versionId = await addUserBook('ספר א', 'personal A');
    await declareVersion(
      versionId,
      source: BookSource.official,
      primaryTitle: SeforimFixtureIds.bereshitTitle,
    );
    final catalog = await buildCatalog();
    final primary = officialBereshit(catalog);
    final target = provider.getPersonalVersionsOf(primary).single.separateBook;
    final reader = TextBookRepository(fileSystem: FileSystemData.instance);

    expect(await reader.getBookContent(target! as TextBook), 'personal A');
    expect(
      await reader.getBookContent(primary as TextBook),
      isNot(contains('personal A')),
    );
  });

  test('מהדורה מקבילה: מעבר בין הרשמי לאישי בשני הכיוונים', () async {
    final versionId = await addUserBook('ספר א', 'personal A');
    await declareVersion(
      versionId,
      source: BookSource.official,
      primaryTitle: SeforimFixtureIds.bereshitTitle,
    );
    final catalog = await buildCatalog();
    DataRepository.instance.library = Future.value(catalog);
    final primary = officialBereshit(catalog);
    final personal = catalog.offTreeBooks.single;

    final fromOfficial = await ParallelEditionsService.find(primary);
    final toPersonal = fromOfficial.where((e) => e.book.isUserBook).single;
    expect(toPersonal.book.id, versionId);
    expect(toPersonal.label, _versionTitle);

    final fromPersonal = await ParallelEditionsService.find(personal);
    expect(fromPersonal.map((e) => e.book), contains(same(primary)));
    expect(fromPersonal.where((e) => e.book.isUserBook), isEmpty);
  });

  test('ראשי ממסד מצורף נקשר לספר המצורף ולא לרשמי באותו שם', () async {
    final dir = Directory(p.join(tempDir.path, 'attached'))..createSync();
    final created = SeforimFixtureDb.create(dir, SeforimFixtureVariant.full);
    final result = await attached.importFile(created);
    expect(result.isOk, isTrue, reason: '${result.problem}');
    final AttachedLibrary library = result.library!;
    final versionId = await addUserBook('ספר א', 'personal A');
    await declareVersion(
      versionId,
      source: library.source!,
      primaryTitle: SeforimFixtureIds.bereshitTitle,
    );

    final catalog = await buildCatalog();
    final attachedBook = catalog.getAllBooks().firstWhere(
      (b) =>
          b.title == SeforimFixtureIds.bereshitTitle &&
          b.source == library.source,
    );

    expect(provider.getPersonalVersionsOf(officialBereshit(catalog)), isEmpty);
    expect(
      provider.getPersonalVersionsOf(attachedBook).single.separateBook?.id,
      versionId,
    );
    expect(await hasBookVersionsToOpen(attachedBook), isTrue);
  });
}

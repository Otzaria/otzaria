import 'dart:io';

import 'package:otzaria/settings/engine/app_settings_store.dart';
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
import 'package:otzaria/data/data_providers/user_books_catalog_reader.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/services/parallel_editions_service.dart';
import 'package:otzaria/library/view/book_versions_dialog.dart';
import 'package:otzaria/migration/database/db_capabilities.dart';
import 'package:otzaria/migration/models/book.dart' as migration_models;
import 'package:otzaria/migration/models/category.dart' as migration_models;
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
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

  test('קריאת קטלוג ישירה וב־isolate תומכות במסד ותיק ובנתיב שהועבר', () async {
    final bookId = await addUserBook('ספר א', 'personal A');
    await declareVersion(
      bookId,
      source: BookSource.official,
      primaryTitle: SeforimFixtureIds.bereshitTitle,
    );
    final repo = await UserBooksDatabaseHolder.instance.repository;
    final raw = await repo.database.database;
    final oldPath = p.join(tempDir.path, 'old', 'library', 'book.txt');
    final newPath = p.join(libraryPath, 'book.txt');
    File(newPath).writeAsStringSync('personal A');
    raw.execute('UPDATE book SET filePath = ? WHERE id = ?', [oldPath, bookId]);
    raw.execute('DROP TABLE user_attached_book_version');

    final direct = selectUserBooksCatalog(raw, DbCapabilities.probe(raw));
    final isolated = await readUserBooksCatalogInIsolate(
      repo.database.path,
      libraryPath,
    );

    expect(direct.books.single['filePath'], oldPath);
    expect(isolated.books.single['filePath'], newPath);
    expect(isolated.categories, direct.categories);
    expect(isolated.authors, direct.authors);
    expect(direct.versions.single['versionBookId'], bookId);
    expect(isolated.versions, direct.versions);
    expect(direct.attachedVersions, isEmpty);
    expect(isolated.attachedVersions, isEmpty);
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

  Future<AttachedLibrary> attachVersionOf(
    BookSource source,
    String title,
  ) async {
    final dir = Directory(p.join(tempDir.path, 'attached'))..createSync();
    final path = SeforimFixtureDb.create(dir, SeforimFixtureVariant.full);
    final raw = sqlite3.sqlite3.open(path);
    raw.execute(
      'CREATE TABLE book_version_link (versionBookId INTEGER, primarySource TEXT, primaryTitle TEXT, versionTitle TEXT)',
    );
    raw.execute(
      "INSERT INTO book_version_link VALUES (?, ?, ?, 'נוסח מצורף')",
      [SeforimFixtureIds.bereshitId, source.wireKey, title],
    );
    raw.close();
    final imported = await attached.importFile(path);
    expect(imported.isOk, isTrue);
    return imported.library!;
  }

  void expectCompleteGroup(Book primary, List<Book> members) {
    for (final book in [primary, ...members]) {
      final versions = book.isUserBook
          ? provider.getUserBookVersions(book)
          : provider.getPersonalVersionsOf(book);
      final others = versions.map((v) => v.separateBook).toList();
      expect(
        others,
        containsAll([
          for (final member in [primary, ...members])
            if (!identical(member, book)) same(member),
        ]),
      );
      expect(others.toSet(), hasLength(others.length));
    }
  }

  for (final officialRoot in [false, true]) {
    test(
      'שרשרת אישי־מצורף־אישי עם שורש ${officialRoot ? 'רשמי' : 'אישי'} נגישה מכל חבר',
      () async {
        final rootId = await addUserBook('שורש אישי', 'root');
        final versionId = await addUserBook('נוסח אישי', 'version');
        final localId = await addUserBook('נוסח מקומי', 'local');
        final isolatedId = await addUserBook('ספר מבודד', 'isolated');
        final raw = await (await UserBooksDatabaseHolder.instance.repository)
            .database
            .database;
        raw.execute(
          "INSERT INTO user_book_version (versionBookId, primaryBookId, versionTitle, source) VALUES (?, ?, 'נוסח מקומי', 'import')",
          [localId, rootId],
        );
        if (officialRoot) {
          await declareVersion(
            rootId,
            source: BookSource.official,
            primaryTitle: SeforimFixtureIds.bereshitTitle,
          );
        } else {
          raw.execute(
            "INSERT INTO user_book_version (versionBookId, primaryBookId, versionTitle, versionNotes, source) VALUES (?, ?, 'מהדורה ראשונה', 'הערת ראשי', 'import')",
            [rootId, rootId],
          );
        }
        final library = await attachVersionOf(BookSource.user, 'שורש אישי');
        await declareVersion(
          versionId,
          source: library.source!,
          primaryTitle: SeforimFixtureIds.bereshitTitle,
        );

        final catalog = await buildCatalog();
        final books = catalog.getIndexableBooks();
        Book personal(int id) =>
            books.singleWhere((b) => b.source.isUser && b.id == id);
        final attachedBook = books.singleWhere(
          (b) =>
              b.source == library.source &&
              b.id == SeforimFixtureIds.bereshitId,
        );
        final root = officialRoot
            ? officialBereshit(catalog)
            : personal(rootId);
        expectCompleteGroup(root, [
          if (officialRoot) personal(rootId),
          personal(versionId),
          personal(localId),
          attachedBook,
        ]);
        final group = provider.getUserBookVersions(personal(versionId));
        expect(group.first.separateBook, same(root));
        if (!officialRoot) {
          expect(group.first.displayTitle, 'מהדורה ראשונה');
          expect(group.first.heVersionNotes, 'הערת ראשי');
        }
        expect(catalog.getAllBooks(), contains(same(root)));
        expect(catalog.getAllBooks(), contains(same(personal(isolatedId))));
        expect(provider.getUserBookVersions(personal(isolatedId)), isEmpty);
        expect(
          catalog.offTreeBooks,
          containsAll([
            same(personal(versionId)),
            same(personal(localId)),
            same(attachedBook),
          ]),
        );
      },
    );
  }

  test(
    'מעגל אישי־מצורף והגרסה הנכנסת אליו נשארים גלויים בלי קבוצת גרסאות חלקית',
    () async {
      final personalId = await addUserBook('נוסח אישי', 'personal');
      final incomingId = await addUserBook('גרסה נכנסת', 'incoming');
      final library = await attachVersionOf(BookSource.user, 'נוסח אישי');
      await declareVersion(
        personalId,
        source: library.source!,
        primaryTitle: SeforimFixtureIds.bereshitTitle,
      );
      final raw = await (await UserBooksDatabaseHolder.instance.repository)
          .database
          .database;
      raw.execute(
        "INSERT INTO user_book_version (versionBookId, primaryBookId, versionTitle, source) VALUES (?, ?, 'נכנסת', 'import')",
        [incomingId, personalId],
      );

      final catalog = await buildCatalog();
      final personal = catalog.getAllBooks().singleWhere(
        (b) => b.source.isUser && b.id == personalId,
      );
      final incoming = catalog.getAllBooks().singleWhere(
        (b) => b.source.isUser && b.id == incomingId,
      );
      final attachedBook = catalog.getAllBooks().singleWhere(
        (b) =>
            b.source == library.source && b.id == SeforimFixtureIds.bereshitId,
      );
      expect(catalog.offTreeBooks, isEmpty);
      expect(provider.getUserBookVersions(personal), isEmpty);
      expect(provider.getUserBookVersions(incoming), isEmpty);
      expect(provider.getPersonalVersionsOf(attachedBook), isEmpty);
    },
  );

  test('ראשי אישי חסר משאיר את הספר בעץ ומאפשר את גרסאותיו המצורפות', () async {
    final personalId = await addUserBook('נוסח אישי', 'personal');
    final raw = await (await UserBooksDatabaseHolder.instance.repository)
        .database
        .database;
    raw.execute(
      "INSERT INTO user_book_version (versionBookId, primaryBookId, versionTitle, source) VALUES (?, 999999, 'נוסח יתום', 'import')",
      [personalId],
    );
    final library = await attachVersionOf(BookSource.user, 'נוסח אישי');

    final catalog = await buildCatalog();
    final personal = catalog.getAllBooks().singleWhere(
      (b) => b.source.isUser && b.id == personalId,
    );
    final attachedBook = catalog.offTreeBooks.singleWhere(
      (b) => b.source == library.source,
    );
    expectCompleteGroup(personal, [attachedBook]);
  });

  test('שרשרת ארוכה של גרסאות אישיות מתכנסת לראשי יחיד', () async {
    final ids = [
      for (var i = 0; i < 128; i++) await addUserBook('נוסח $i', '$i'),
    ];
    final raw = await (await UserBooksDatabaseHolder.instance.repository)
        .database
        .database;
    for (var i = 1; i < ids.length; i++) {
      raw.execute(
        "INSERT INTO user_book_version (versionBookId, primaryBookId, versionTitle, source) VALUES (?, ?, ?, 'import')",
        [ids[i], ids[i - 1], 'נוסח $i'],
      );
    }

    final catalog = await buildCatalog();
    final root = catalog.getAllBooks().singleWhere((b) => b.source.isUser);
    final last = catalog.offTreeBooks.singleWhere(
      (b) => b.source.isUser && b.id == ids.last,
    );
    expect(root.id, ids.first);
    expect(catalog.offTreeBooks, hasLength(ids.length - 1));
    for (final book in [root, last]) {
      final group = provider.getUserBookVersions(book);
      expect(group.first.separateBook, same(root));
      expect(group.map((v) => v.separateBook).toSet(), hasLength(ids.length));
      expect(group, hasLength(ids.length));
    }
  });

  for (final declaration in ['אוטומטית', 'מוטמעת', 'קובץ משתמש']) {
    final explicit = declaration != 'אוטומטית';
    test(
      'גרסה אישית נשארת בקבוצה כשמצורף נעשה גרסה: $declaration',
      () async {
        final dir = Directory(p.join(tempDir.path, 'attached'))..createSync();
        final path = SeforimFixtureDb.create(dir, SeforimFixtureVariant.full);
        final primaryTitle = explicit
            ? SeforimFixtureIds.rashiTitle
            : SeforimFixtureIds.bereshitTitle;
        if (explicit) {
          final raw = sqlite3.sqlite3.open(path);
          raw.execute(
            'CREATE TABLE book_version_link (versionBookId INTEGER, primarySource TEXT, primaryTitle TEXT, versionTitle TEXT)',
          );
          raw.execute(
            "INSERT INTO book_version_link VALUES (?, 'official', ?, 'נוסח מפורש')",
            [
              SeforimFixtureIds.bereshitId,
              declaration == 'קובץ משתמש'
                  ? SeforimFixtureIds.bereshitTitle
                  : primaryTitle,
            ],
          );
          raw.close();
        }
        final imported = await attached.importFile(path);
        expect(imported.isOk, isTrue);
        final library = imported.library!;
        await attached.setPlacement(
          library,
          AttachedLibraryPlacement.mergeIntoLibrary,
        );
        final versionId = await addUserBook('נוסח אישי', 'personal');
        await declareVersion(
          versionId,
          source: library.source!,
          primaryTitle: SeforimFixtureIds.bereshitTitle,
        );
        final raw = await (await UserBooksDatabaseHolder.instance.repository)
            .database
            .database;
        raw.execute('UPDATE user_book_version SET priority = 5');
        if (declaration == 'קובץ משתמש') {
          raw.execute(
            "INSERT INTO user_attached_book_version (versionDb, versionBookTitle, primarySource, primaryTitle, versionTitle, versionNotes, priority, source) VALUES (?, ?, 'o', ?, 'נוסח משתמש', 'הערת משתמש', 2, 'import')",
            [library.slug, SeforimFixtureIds.bereshitTitle, primaryTitle],
          );
        }

        final catalog = await buildCatalog();
        final primary = catalog.getAllBooks().singleWhere(
          (b) => b.source.isOfficial && b.title == primaryTitle,
        );
        final attachedBook = catalog.offTreeBooks.singleWhere(
          (b) =>
              b.source == library.source &&
              b.id == SeforimFixtureIds.bereshitId,
        );
        final personal = catalog.offTreeBooks.singleWhere(
          (b) => b.source.isUser && b.id == versionId,
        );
        expect(catalog.getAllBooks(), isNot(contains(personal)));
        expect(catalog.getAllBooks(), isNot(contains(attachedBook)));
        final versions = provider.getPersonalVersionsOf(primary);
        expect(
          versions.map((v) => v.separateBook),
          containsAll([same(personal), same(attachedBook)]),
        );
        expect(versions.first.separateBook, same(personal));
        if (declaration == 'קובץ משתמש') {
          final info = versions.singleWhere(
            (v) => identical(v.separateBook, attachedBook),
          );
          expect(info.displayTitle, 'נוסח משתמש');
          expect(info.heVersionNotes, 'הערת משתמש');
          expect(info.priority, 2);
        }
        for (final book in [primary, attachedBook, personal]) {
          final group = book.isUserBook
              ? provider.getUserBookVersions(book)
              : provider.getPersonalVersionsOf(book);
          final others = group.map((v) => v.separateBook).toList();
          expect(
            others,
            containsAll([
              for (final member in [primary, attachedBook, personal])
                if (!identical(member, book)) same(member),
            ]),
          );
          expect(others.toSet(), hasLength(others.length));
        }
      },
    );
  }
}

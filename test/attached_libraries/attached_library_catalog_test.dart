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
import 'package:otzaria/data/data_providers/file_system_library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../helpers/seforim_fixture_db.dart';
import '../test_helpers/memory_cache_provider.dart';

const _personalRoot = 'ספרים אישיים';

/// ספרי [category] ותתי-הקטגוריות שלה.
List<Book> _booksUnder(Category category) => category.getAllBooks();

Category? _child(Category parent, String title) =>
    parent.subCategories.where((c) => c.title == title).firstOrNull;

/// מסדי ספרים מצורפים מקצה לקצה: seforim.db אמיתי (fixture), מסדים מצורפים
/// אמיתיים, בניית העץ, וקריאת טקסט ותוכן עניינים דרך LibraryProviderManager.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String libraryPath;
  late AttachedLibraryRegistry registry;
  late AttachedLibrariesRepository attached;
  final provider = DatabaseLibraryProvider.instance;
  final previousRegistry = AttachedLibraryRegistry.instance;
  final previousDataRoot = AppPaths.cachedDataRootPath;

  /// מסד מצורף מסוג [variant] בשם [name]; שורות הספרים מסומנות בקידומת
  /// [name] כדי שקריאה מהמסד הלא-נכון תיכשל.
  String attachedFixture(String name, SeforimFixtureVariant variant) {
    final dir = Directory(p.join(tempDir.path, 'attached', name))
      ..createSync(recursive: true);
    final created = SeforimFixtureDb.create(dir, variant);
    final path = p.join(dir.path, '$name.db');
    File(created).renameSync(path);
    final db = sqlite3.sqlite3.open(path);
    db.execute("UPDATE line SET content = '$name: ' || content");
    db.close();
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

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    tempDir = await Directory.systemTemp.createTemp('otzaria_attached_catalog');
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

  test('שורש נפרד: ספרים אישיים/<שם המסד>, עם הקטגוריות והמקור', () async {
    final library = await attach(
      attachedFixture('ספרייה', SeforimFixtureVariant.full),
    );

    final catalog = await buildCatalog();

    final root = _child(_child(catalog, _personalRoot)!, library.displayName)!;
    final torah = _child(_child(root, 'תנ"ך')!, 'תורה')!;
    expect(
      [for (final b in torah.books) b.title],
      [
        SeforimFixtureIds.bereshitTitle,
        SeforimFixtureIds.rashiTitle,
      ],
    );
    final book = torah.books.first;
    expect(book.source, BookSource.attached(library.slug));
    expect(book.categoryId, SeforimFixtureIds.torahCategoryId);
    expect(book.id, SeforimFixtureIds.bereshitId);
    // הספרים הרשמיים באותם שמות נשארים במקומם ובמקורם.
    final officialTorah = _child(_child(catalog, 'תנ"ך')!, 'תורה')!;
    expect(officialTorah.books.every((b) => b.source.isOfficial), isTrue);
  });

  test('מיזוג: ספרי המסד נכנסים לקטגוריות הספרייה לפי שם', () async {
    final library = await attach(
      attachedFixture('ממוזג', SeforimFixtureVariant.full),
    );
    await attached.setPlacement(
      library,
      AttachedLibraryPlacement.mergeIntoLibrary,
    );

    final catalog = await buildCatalog();

    expect(catalog.subCategories.where((c) => c.title == 'תנ"ך'), hasLength(1));
    final torah = _child(_child(catalog, 'תנ"ך')!, 'תורה')!;
    final sources = [for (final b in torah.books) b.source];
    expect(sources.where((s) => s.isOfficial), hasLength(2));
    expect(
      sources.where((s) => s == BookSource.attached(library.slug)),
      hasLength(2),
    );
    expect(_child(catalog, _personalRoot), isNull);
  });

  test('מסד מוסתר או לא נגיש — ספריו אינם בעץ', () async {
    final hidden = await attach(
      attachedFixture('מוסתר', SeforimFixtureVariant.full),
    );
    await attached.setHidden(hidden, true);
    final removablePath = attachedFixture('נשלף', SeforimFixtureVariant.full);
    await attach(removablePath);
    File(removablePath).deleteSync();

    final catalog = await buildCatalog();

    final attachedBooks = catalog.getAllBooks().where(
      (b) => b.source.isAttached,
    );
    expect(attachedBooks, isEmpty);

    await attached.rescan();
    expect(
      registry.libraries.map((l) => l.status),
      contains(AttachedLibraryStatus.unreachable),
    );
  });

  test('מסד בלי טבלת קטגוריות — הספרים ישירות תחת שם המסד', () async {
    final library = await attach(
      attachedFixture('ללא-קטגוריות', SeforimFixtureVariant.missingCategory),
    );

    final catalog = await buildCatalog();

    final root = _child(_child(catalog, _personalRoot)!, library.displayName)!;
    expect(root.subCategories, isEmpty);
    expect(
      [for (final b in root.books) b.title],
      [
        SeforimFixtureIds.bereshitTitle,
        SeforimFixtureIds.rashiTitle,
      ],
    );
  });

  test('פתיחת ספר מצורף: טקסט ותוכן עניינים מהמסד שלו', () async {
    final library = await attach(
      attachedFixture('קריאה', SeforimFixtureVariant.full),
    );
    final minimal = await attach(
      attachedFixture('מינימלי', SeforimFixtureVariant.minimal),
    );
    final catalog = await buildCatalog();
    final books = _booksUnder(_child(catalog, _personalRoot)!);
    final book = books.firstWhere(
      (b) =>
          b.source == library.source &&
          b.title == SeforimFixtureIds.bereshitTitle,
    );
    final bare = books.firstWhere(
      (b) =>
          b.source == minimal.source &&
          b.title == SeforimFixtureIds.bereshitTitle,
    );
    final manager = LibraryProviderManager.instance..resetForTesting();

    final text = await manager.getBookText(
      book.title,
      categoryId: book.categoryId,
      fileType: 'txt',
      preferSource: book.source,
    );
    final officialText = await manager.getBookText(
      book.title,
      categoryId: book.categoryId,
      fileType: 'txt',
    );
    final toc = await manager.getBookToc(
      book.title,
      categoryId: book.categoryId,
      fileType: 'txt',
      preferSource: book.source,
    );
    final bareText = await manager.getBookText(
      bare.title,
      categoryId: bare.categoryId,
      fileType: 'txt',
      preferSource: bare.source,
    );
    final bareToc = await manager.getBookToc(
      bare.title,
      categoryId: bare.categoryId,
      fileType: 'txt',
      preferSource: bare.source,
    );

    expect(text!.split('\n'), hasLength(3));
    expect(text.split('\n').every((l) => l.startsWith('קריאה: ')), isTrue);
    expect(officialText, isNot(contains('קריאה: ')));
    expect([for (final e in toc!) e.text], ['פרק א']);
    expect(bareText!.split('\n').first, startsWith('מינימלי: '));
    expect(bareToc ?? const [], isEmpty);
  });

  test('מסד שהוסר מהרשימה — הספר אינו נפתח ואינו נופל לספר הרשמי', () async {
    final library = await attach(
      attachedFixture('הוסר', SeforimFixtureVariant.full),
    );
    await buildCatalog();
    await attached.remove(library);

    final text = await DatabaseLibraryProvider.instance.getBookText(
      SeforimFixtureIds.bereshitTitle,
      SeforimFixtureIds.torahCategoryId,
      'txt',
      preferSource: library.source!,
    );
    expect(text, isNull);
  });
}

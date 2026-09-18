import 'dart:io';
import 'dart:isolate';

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
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/migration/database/untrusted_database.dart';
import 'package:otzaria/plugins/services/plugin_ref_line_resolver.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/text_book/text_book_repository.dart';
import 'package:otzaria/text_book/utils/dibburim_structure.dart';
import 'package:otzaria/text_book/view/page_shape/utils/default_commentators.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../helpers/seforim_fixture_db.dart';
import '../test_helpers/memory_cache_provider.dart';

const _personalRoot = 'ספרים אישיים';

Category? _child(Category parent, String title) =>
    parent.subCategories.where((c) => c.title == title).firstOrNull;

/// תוכן עשיר בספר ממסד מצורף — קישורים, מפרשים, דורות, מפרשי ברירת מחדל,
/// 'כותרות', דיבורי-המתחיל, מהדורות וספרי PDF — נקרא מהמסד של הספר, ומסד
/// שחסרות בו הטבלאות נותן תשובה ריקה בלי לזרוק.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String libraryPath;
  late AttachedLibraryRegistry registry;
  late AttachedLibrariesRepository attached;
  final provider = DatabaseLibraryProvider.instance;
  final previousRegistry = AttachedLibraryRegistry.instance;
  final previousRepository = AttachedLibrariesRepository.instance;
  final previousDataRoot = AppPaths.cachedDataRootPath;

  /// מסד מצורף מלא, שנבדל מהרשמי בכל נתון שנבדק כאן.
  String fullAttached(String name) {
    final dir = Directory(p.join(tempDir.path, 'attached', name))
      ..createSync(recursive: true);
    final path = p.join(dir.path, '$name.db');
    File(
      SeforimFixtureDb.create(dir, SeforimFixtureVariant.full),
    ).renameSync(path);
    final db = sqlite3.sqlite3.open(path);
    db.execute("UPDATE line SET content = '$name: ' || content");
    db.execute("UPDATE generation SET name = 'אחרונים'");
    db.execute("UPDATE tocText SET text = 'פרשה מצורפת' WHERE id = 2");
    db.execute("UPDATE line_dh SET dhDisplay = 'דיבור מצורף'");
    db.execute("UPDATE version_line SET content = 'נוסח מצורף'");
    db.close();
    return path;
  }

  String minimalAttached(String name) {
    final dir = Directory(p.join(tempDir.path, 'attached', name))
      ..createSync(recursive: true);
    final path = p.join(dir.path, '$name.db');
    File(
      SeforimFixtureDb.create(dir, SeforimFixtureVariant.minimal),
    ).renameSync(path);
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

  Future<TextBook> attachedBook(AttachedLibrary library, String title) async {
    final catalog = await buildCatalog();
    final root = _child(_child(catalog, _personalRoot)!, library.displayName)!;
    return root.getAllBooks().whereType<TextBook>().firstWhere(
      (b) => b.title == title,
    );
  }

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    tempDir = await Directory.systemTemp.createTemp('otzaria_attached_rich');
    libraryPath = p.join(tempDir.path, 'library');
    Directory(libraryPath).createSync();
    File(
      SeforimFixtureDb.create(
        Directory(libraryPath),
        SeforimFixtureVariant.full,
      ),
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
    CommentaryService.clearEraCache();

    registry = AttachedLibraryRegistry(idleTimeout: null);
    AttachedLibraryRegistry.instance = registry;
    attached = AttachedLibrariesRepository(
      registry: registry,
      probe: (path) async => AttachedLibraryProbe.probeSync(path),
      copyByDefault: false,
    );
    AttachedLibrariesRepository.instance = attached;
  });

  tearDown(() async {
    CommentaryService.clearEraCache();
    LibraryProviderManager.instance.resetForTesting();
    FileSystemLibraryProvider.instance.resetForTesting();
    provider.clearCache();
    await provider.sqliteProvider.dispose();
    await registry.closeAll();
    AttachedLibraryRegistry.instance = previousRegistry;
    AttachedLibrariesRepository.instance = previousRepository;
    await UserBooksDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(previousDataRoot);
    await attached.dispose();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  TextBookRepository repository() =>
      TextBookRepository(fileSystem: FileSystemData.instance);

  group('מסד מצורף מלא', () {
    test('קישורים: חלון, כל הקישורים ותוכן המפרש — מהמסד המצורף', () async {
      final library = await attach(fullAttached('מלא'));
      final book = await attachedBook(library, SeforimFixtureIds.bereshitTitle);

      final window = await repository().getBookLinksInRange(
        book,
        startIndex: 0,
        endIndex: 2,
      );
      final commentary = window.singleWhere(
        (l) => l.path2 == SeforimFixtureIds.rashiTitle,
      );
      expect(commentary.targetSource, library.source);
      expect(await commentary.content, startsWith('מלא: '));

      final all = await book.links;
      expect(all.map((l) => l.targetSource).toSet(), {library.source});

      final summary = await provider.getBookLinkTargetsSummary(
        book.title,
        book.categoryId!,
        source: book.source,
      );
      expect(
        summary!.targets.map((t) => t.targetTitle),
        contains(SeforimFixtureIds.rashiTitle),
      );
    });

    test('רשימת המפרשים ומפרשים בטווח שורות', () async {
      final library = await attach(fullAttached('מפרשים'));
      final book = await attachedBook(library, SeforimFixtureIds.bereshitTitle);

      final detailed = await repository().getCommentatorsDetailed(book);
      final rashi = detailed.commentators.singleWhere(
        (c) => c.title == SeforimFixtureIds.rashiTitle,
      );
      expect(rashi.author, SeforimFixtureIds.authorName);
      expect(rashi.linkCount, 1);

      final inRange = await repository().getCommentatorsInLineRange(
        book,
        startLine: 0,
        endLine: 0,
      );
      expect(inRange.map((c) => c.title), [SeforimFixtureIds.rashiTitle]);
    });

    test(
      'דורות לפי book_generation של המסד המצורף, ומפרשי ברירת מחדל',
      () async {
        final library = await attach(fullAttached('דורות'));
        final book = await attachedBook(
          library,
          SeforimFixtureIds.bereshitTitle,
        );

        final attachedEras = await utils.splitByEra([
          SeforimFixtureIds.rashiTitle,
        ], source: library.source!);
        expect(attachedEras['אחרונים'], [SeforimFixtureIds.rashiTitle]);
        final officialEras = await utils.splitByEra([
          SeforimFixtureIds.rashiTitle,
        ]);
        expect(officialEras['ראשונים'], [SeforimFixtureIds.rashiTitle]);

        await CommentaryService.preloadEras([
          SeforimFixtureIds.rashiTitle,
        ], source: library.source!);
        expect(
          CommentaryService.getCachedBookEra(
            SeforimFixtureIds.rashiTitle,
            source: library.source!,
          ),
          CommentaryEra.acharonim,
        );

        expect(await DefaultCommentators.getBaseCommentators(book), [
          SeforimFixtureIds.rashiTitle,
        ]);
      },
    );

    test("'כותרות': מבנים, ערכים, קישורי ערך וערך לשורה", () async {
      final library = await attach(fullAttached('כותרות'));
      final book = await attachedBook(library, SeforimFixtureIds.bereshitTitle);

      final structures = await provider.getAlternativeStructuresForBook(book);
      expect(structures, hasLength(1));
      final structure = structures.single;
      expect(structure.source, library.source);

      final entries = await provider.getAllAlternativeEntries(
        structure.id,
        source: structure.source,
      );
      expect(entries.map((e) => e.text), ['פרשה מצורפת']);
      final withLines = await provider.getAltTocEntriesWithLineIndex(
        structure.id,
        source: structure.source,
      );
      expect(withLines.single.lineIndex, 0);
      final entryLinks = await provider.getLinksForAltTocEntry(
        structure.id,
        entries.single.id,
        source: structure.source,
      );
      expect(entryLinks.single.targetSource, library.source);
      expect(
        await provider.getAltTocEntryForLine(
          book.title,
          0,
          structure.id,
          source: structure.source,
        ),
        entries.single.id,
      );
      final marks = await provider.getInlineSectionMarksByLineIndex(
        book.title,
        categoryId: book.categoryId,
        source: book.source,
      );
      expect(marks.markers, isEmpty);
    });

    test('דיבורי-המתחיל של מפרש מצורף', () async {
      final library = await attach(fullAttached('דיבורים'));
      final rashi = await attachedBook(library, SeforimFixtureIds.rashiTitle);
      expect(await loadDibburimForBook(rashi), {0: 'דיבור מצורף'});
    });

    test('מהדורות: רשימה, תפריט ונוסח המהדורה', () async {
      final library = await attach(fullAttached('מהדורות'));
      final book = await attachedBook(library, SeforimFixtureIds.bereshitTitle);

      final versions = await provider.getBookVersions(
        book.title,
        book.categoryId!,
        source: book.source,
      );
      expect(versions.map((v) => v.versionTitle), ['Alt']);
      expect(
        await provider.hasSelectableBookVersions(
          book.title,
          book.categoryId!,
          source: book.source,
        ),
        isTrue,
      );
      final range = await repository().getBookContentRange(
        book.copyWith(versionTitle: 'Alt'),
        startLine: 0,
        endLine: 0,
      );
      expect(range?.lines, ['נוסח מצורף']);
    });
  });

  test('מסד מינימלי: כל התוכן העשיר ריק, בלי חריגה', () async {
    final library = await attach(minimalAttached('מינימלי'));
    final catalog = await buildCatalog();
    final root = _child(_child(catalog, _personalRoot)!, library.displayName)!;
    final book = root.getAllBooks().whereType<TextBook>().first;
    final source = library.source!;

    expect(
      await repository().getBookLinksInRange(book, startIndex: 0, endIndex: 5),
      isEmpty,
    );
    expect((await repository().getCommentatorsDetailed(book)).commentators, [
      ...const <CommentatorInfo>[],
    ]);
    expect(await provider.getAlternativeStructuresForBook(book), isEmpty);
    expect(
      await provider.getAllAlternativeEntries(1, source: source),
      isEmpty,
    );
    expect(
      await provider.getAltTocEntryForLine(book.title, 0, 1, source: source),
      isNull,
    );
    expect(await loadDibburimForBook(book), isEmpty);
    expect(
      await provider.getBookVersions(book.title, 0, source: source),
      isEmpty,
    );
    expect(
      await provider.hasSelectableBookVersions(book.title, 0, source: source),
      isFalse,
    );
    expect(await DefaultCommentators.getBaseCommentators(book), isEmpty);
    expect(
      (await utils.splitByEra(['x'], source: source))['מפרשים נוספים'],
      ['x'],
    );
  });

  test('ספר PDF במסד מצורף: נתיב יחסי מוצג, נתיב שבורח מהתיקייה לא', () async {
    final dir = Directory(p.join(tempDir.path, 'attached', 'קבצים'))
      ..createSync(recursive: true);
    final path = p.join(dir.path, 'קבצים.db');
    File(
      SeforimFixtureDb.create(dir, SeforimFixtureVariant.full),
    ).renameSync(path);
    Directory(p.join(dir.path, 'pdf')).createSync();
    File(p.join(dir.path, 'pdf', 'ספר.pdf')).writeAsBytesSync([1, 2, 3]);
    File(p.join(tempDir.path, 'בחוץ.pdf')).writeAsBytesSync([1, 2, 3]);
    final db = sqlite3.sqlite3.open(path);
    db.execute('ALTER TABLE book ADD COLUMN fileType TEXT');
    db.execute('ALTER TABLE book ADD COLUMN filePath TEXT');
    final outside = p.join(tempDir.path, 'בחוץ.pdf');
    for (final (id, title, filePath) in [
      (10, 'ספר קובץ', 'pdf/ספר.pdf'),
      (11, 'בורח', '../../בחוץ.pdf'),
      (12, 'מוחלט', outside),
      (13, 'חסר', 'pdf/אין.pdf'),
    ]) {
      db.execute(
        'INSERT INTO book (id, categoryId, sourceId, title, fileType, filePath) '
        "VALUES (?, 2, 1, ?, 'pdf', ?)",
        [id, title, filePath],
      );
    }
    Directory(p.join(dir.path, 'txt')).createSync();
    File(p.join(dir.path, 'txt', 'a.txt')).writeAsStringSync('תוכן מהקובץ');
    db.execute(
      'INSERT INTO book (id, categoryId, sourceId, title, fileType, filePath) '
      "VALUES (14, 2, 1, 'קובץ טקסט', 'txt', 'txt/a.txt')",
    );
    db.close();
    final library = await attach(path);

    final catalog = await buildCatalog();
    final root = _child(_child(catalog, _personalRoot)!, library.displayName)!;
    final pdfs = root.getAllBooks().whereType<PdfBook>().toList();
    expect(pdfs.map((b) => b.title), ['ספר קובץ']);
    expect(pdfs.single.path, p.join(dir.path, 'pdf', 'ספר.pdf'));
    expect(pdfs.single.source, library.source);

    // המאגר של המסד מחזיר נתיב מוחלט בתוך התיקייה, ונתיב אסור כ-null.
    final repo = (await registry.repositoryFor(library.slug))!;
    expect(
      (await repo.getBookByTitle('ספר קובץ'))!.filePath,
      p.join(dir.path, 'pdf', 'ספר.pdf'),
    );
    expect((await repo.getBookByTitle('בורח'))!.filePath, isNull);
    expect((await repo.getBookByTitle('מוחלט'))!.filePath, isNull);

    // ספר טקסט מבוסס-קובץ בלי שורות במסד נקרא מהקובץ שבתיקייה.
    final text = await provider.getBookText(
      'קובץ טקסט',
      2,
      'txt',
      preferSource: library.source!,
    );
    expect(text, contains('תוכן מהקובץ'));
  });

  test('בידוד: חיבור מוקשח ב-isolate דוחה כתיבה', () async {
    final path = fullAttached('כתיבה');
    final error = await _tryWriteInIsolate(path);
    expect(error, contains('readonly'));
  });

  test('plugin ref resolver reads line_ref from the attached DB', () async {
    final path = fullAttached('refs');
    SeforimFixtureDb.fillLineRef(path);
    final library = await attach(path);
    final book = await attachedBook(library, SeforimFixtureIds.bereshitTitle);
    expect(book.source, library.source);

    // השורה השנייה של בראשית: הפניה "א ב".
    final line = await PluginRefLineResolver().resolve(
      book: book,
      ref: 'א ב',
    );
    expect(line, 1);
  });
}

/// top-level: closure בתוך הבדיקה היה לוכד את כל ה-scope.
Future<String> _tryWriteInIsolate(String path) => Isolate.run(() {
  final db = openReadOnlyTarget((
    path: path,
    untrusted: true,
    immutable: false,
  ));
  try {
    db.execute('DELETE FROM line');
    return 'written';
  } on sqlite3.SqliteException catch (e) {
    return e.toString().toLowerCase();
  } finally {
    db.close();
  }
});

import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_libraries_repository.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_probe.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/attached_libraries/repository/external_link_core.dart';
import 'package:otzaria/attached_libraries/repository/external_link_repository.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/file_system_library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/migration/database/untrusted_database.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/text_book/text_book_repository.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../helpers/seforim_fixture_db.dart';
import '../test_helpers/memory_cache_provider.dart';

/// כותרות גנריות לספרי המסד המצורף — שלא יתנגשו בכותרות הספרייה הרשמית.
const _commentaryTitle = 'ספר א';
const _baseTitle = 'ספר ב';
const _laterEra = 'אחרונים';

ExternalLinkFixtureRow _row(
  int sourceLineIndex, {
  String? targetSource = 'official',
  String targetTitle = SeforimFixtureIds.bereshitTitle,
  String? targetRef,
  int? targetLineIndex,
  String? connectionType = 'SOURCE',
}) => (
  sourceBookId: SeforimFixtureIds.rashiId,
  sourceLineIndex: sourceLineIndex,
  targetSource: targetSource,
  targetTitle: targetTitle,
  targetRef: targetRef,
  targetLineIndex: targetLineIndex,
  connectionType: connectionType,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String libraryPath;
  late String officialPath;
  late AttachedLibraryRegistry registry;
  late AttachedLibrariesRepository attached;
  late ExternalLinkRepository links;
  final provider = DatabaseLibraryProvider.instance;
  final previousRegistry = AttachedLibraryRegistry.instance;
  final previousRepository = AttachedLibrariesRepository.instance;
  final previousLinks = ExternalLinkRepository.instance;
  final previousDataRoot = AppPaths.cachedDataRootPath;

  String cachePath() => p.join(tempDir.path, 'cache.db');

  /// ה-heRef של שורה [lineIndex] (0-based) בספר הבסיס הרשמי.
  String officialRef(int lineIndex) {
    final db = sqlite3.sqlite3.open(officialPath);
    try {
      return db.select(
            'SELECT heRef FROM line WHERE bookId = ? AND lineIndex = ?',
            [SeforimFixtureIds.bereshitId, lineIndex],
          ).first['heRef']
          as String;
    } finally {
      db.close();
    }
  }

  String attachedDb(String name, {List<ExternalLinkFixtureRow>? rows}) {
    final dir = Directory(p.join(tempDir.path, 'attached', name))
      ..createSync(recursive: true);
    final path = p.join(dir.path, '$name.db');
    File(
      SeforimFixtureDb.create(dir, SeforimFixtureVariant.full),
    ).renameSync(path);
    final db = sqlite3.sqlite3.open(path);
    db.execute("UPDATE book SET title = ? WHERE id = ?", [
      _commentaryTitle,
      SeforimFixtureIds.rashiId,
    ]);
    db.execute("UPDATE book SET title = ? WHERE id = ?", [
      _baseTitle,
      SeforimFixtureIds.bereshitId,
    ]);
    db.execute('UPDATE generation SET name = ?', [_laterEra]);
    db.close();
    if (rows != null) SeforimFixtureDb.addExternalLinks(path, rows);
    return path;
  }

  Future<Library> buildCatalog() async {
    provider.clearCache();
    await provider.initialize();
    return provider.buildLibraryCatalog({}, libraryPath);
  }

  Future<AttachedLibrary> attach(String path) async {
    final result = await attached.importFile(path);
    expect(result.isOk, isTrue, reason: '${result.problem}');
    // המסד הרשמי חייב להיות פתוח כדי שיעדים בו ייפתרו בבניית האינדקס.
    await buildCatalog();
    return result.library!;
  }

  Future<TextBook> bookOf(BookSource source, String title) async {
    final catalog = await buildCatalog();
    return catalog.getAllBooks().whereType<TextBook>().firstWhere(
      (b) => b.title == title && b.source == source,
    );
  }

  Future<List<Link>> externalIn(TextBook book, {int end = 10}) async {
    final all = await TextBookRepository(
      fileSystem: FileSystemData.instance,
    ).getBookLinksInRange(book, startIndex: 0, endIndex: end);
    return [
      for (final link in all)
        if (link.targetSource != book.source) link,
    ];
  }

  int indexRows(String slug) {
    final db = sqlite3.sqlite3.open(cachePath());
    try {
      return db.select(
            'SELECT COUNT(*) AS c FROM attached_external_link_index '
            'WHERE sourceSlug = ?',
            [slug],
          ).first['c']
          as int;
    } finally {
      db.close();
    }
  }

  /// שינוי תוכן הקובץ עם זמן שינוי חדש — כמו עדכון של המסד מבחוץ.
  void touch(String path) {
    final file = File(path);
    file.setLastModifiedSync(
      file.lastModifiedSync().add(const Duration(minutes: 5)),
    );
  }

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    tempDir = await Directory.systemTemp.createTemp('otzaria_external_links');
    libraryPath = p.join(tempDir.path, 'library');
    Directory(libraryPath).createSync();
    officialPath = p.join(libraryPath, DatabaseConstants.databaseFileName);
    File(
      SeforimFixtureDb.create(
        Directory(libraryPath),
        SeforimFixtureVariant.full,
      ),
    ).renameSync(officialPath);
    SeforimFixtureDb.fillLineRef(officialPath);

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
    links = ExternalLinkRepository(
      registry: registry,
      cacheDbPath: () async => cachePath(),
    );
    ExternalLinkRepository.instance = links;
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
    ExternalLinkRepository.instance = previousLinks;
    await UserBooksDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(previousDataRoot);
    await attached.dispose();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('כיוון ישיר — קורא ספר מהמסד המצורף', () {
    test('heRef גובר על מספר השורה, ומספר השורה משמש כשאין heRef', () async {
      final library = await attach(
        attachedDb(
          'ext',
          rows: [
            // מספר השורה שגוי בכוונה — ה-heRef קובע.
            _row(0, targetRef: officialRef(1), targetLineIndex: 0),
            _row(1, targetSource: null, targetLineIndex: 2),
          ],
        ),
      );
      final book = await bookOf(
        BookSource.attached(library.slug),
        _commentaryTitle,
      );

      final external = await externalIn(book);
      expect(
        [for (final l in external) (l.index1, l.index2, l.path2)],
        [
          (1, 2, SeforimFixtureIds.bereshitTitle),
          (2, 3, SeforimFixtureIds.bereshitTitle),
        ],
      );
      expect(external.every((l) => l.targetSource.isOfficial), isTrue);
      expect(external.first.heRef, officialRef(1));
      expect(external.first.targetCategoryId, isNotNull);
    });

    test('יעד שלא נפתר נשמט בשקט', () async {
      final library = await attach(
        attachedDb(
          'ext',
          rows: [
            _row(0, targetTitle: 'no such book', targetLineIndex: 0),
            _row(0, targetLineIndex: 99),
            _row(1, targetSource: 'no-such-library', targetLineIndex: 0),
          ],
        ),
      );
      final book = await bookOf(
        BookSource.attached(library.slug),
        _commentaryTitle,
      );
      expect(await externalIn(book), isEmpty);
    });

    test('מסד בלי טבלת external_link — אין קישורים ואין אינדקס', () async {
      final library = await attach(attachedDb('plain'));
      expect(
        library.capabilities,
        isNot(contains(AttachedLibraryCapability.externalLinks)),
      );
      final book = await bookOf(
        BookSource.attached(library.slug),
        _commentaryTitle,
      );
      expect(await externalIn(book), isEmpty);
      expect(await links.sync(), isEmpty);
      final official = await bookOf(
        BookSource.official,
        SeforimFixtureIds.bereshitTitle,
      );
      expect(await externalIn(official), isEmpty);
    });
  });

  group('כיוון הפוך — מפרש מהמסד המצורף על הספר הרשמי', () {
    test('מופיע בטווח, ברשימת המפרשים ובדור של המסד שלו', () async {
      final library = await attach(
        attachedDb(
          'ext',
          rows: [
            _row(0, targetRef: officialRef(1)),
            _row(1, targetLineIndex: 2),
          ],
        ),
      );
      expect(await links.sync(), {library.slug});
      final book = await bookOf(
        BookSource.official,
        SeforimFixtureIds.bereshitTitle,
      );

      final reverse = await externalIn(book);
      expect(
        [for (final l in reverse) (l.index1, l.index2, l.connectionType)],
        [(2, 1, 'COMMENTARY'), (3, 2, 'COMMENTARY')],
      );
      expect(reverse.first.path2, _commentaryTitle);
      expect(reverse.first.targetSource, BookSource.attached(library.slug));

      // חלון שאינו מכיל את שורות היעד — בלי קישורים הפוכים.
      final narrow = await TextBookRepository(
        fileSystem: FileSystemData.instance,
      ).getBookLinksInRange(book, startIndex: 0, endIndex: 0);
      expect(narrow.where((l) => l.path2 == _commentaryTitle), isEmpty);

      final repository = TextBookRepository(
        fileSystem: FileSystemData.instance,
      );
      final detailed = await repository.getCommentatorsDetailed(book);
      expect(
        detailed.commentators.map((c) => c.title),
        contains(_commentaryTitle),
      );
      final sources = await repository.getExternalCommentatorSources(book);
      expect(sources, {_commentaryTitle: BookSource.attached(library.slug)});
      final eras = await utils.splitByEra(
        [_commentaryTitle],
        sourceByTitle: sources,
      );
      expect(eras[_laterEra], [_commentaryTitle]);
    });

    test('נבנה מחדש רק כשהקובץ השתנה', () async {
      final path = attachedDb('ext', rows: [_row(0, targetLineIndex: 1)]);
      final library = await attach(path);
      expect(await links.sync(), {library.slug});
      expect(await links.sync(), isEmpty);

      SeforimFixtureDb.addExternalLinks(path, [_row(1, targetLineIndex: 2)]);
      touch(path);
      await attached.rescan();
      expect(await links.sync(), {library.slug});
      expect(indexRows(library.slug), 2);
    });

    test('שינוי גרסת המסד הרשמי בונה מחדש', () async {
      final library = await attach(
        attachedDb('ext', rows: [_row(0, targetLineIndex: 1)]),
      );
      await buildCatalog();
      expect(await links.sync(), {library.slug});

      final db = sqlite3.sqlite3.open(officialPath);
      db.execute("UPDATE schema_meta SET value = '2' WHERE key = 'db_version'");
      db.close();
      links.resetRuntime();
      expect(await links.sync(), {library.slug});
    });

    test('הסרת המסד מוחקת את שורותיו', () async {
      final library = await attach(
        attachedDb('ext', rows: [_row(0, targetLineIndex: 1)]),
      );
      await links.sync();
      expect(indexRows(library.slug), 1);

      await attached.remove(library);
      await links.sync();
      expect(indexRows(library.slug), 0);
    });

    test('מסד לא נגיש — השורות נשמרות אך אינן מוגשות', () async {
      final path = attachedDb('ext', rows: [_row(0, targetLineIndex: 1)]);
      final library = await attach(path);
      await links.sync();
      final book = await bookOf(
        BookSource.official,
        SeforimFixtureIds.bereshitTitle,
      );
      expect(await externalIn(book), hasLength(1));

      await registry.closeAll();
      File(path).renameSync('$path.away');
      await attached.rescan();
      expect(
        registry.libraries.single.status,
        AttachedLibraryStatus.unreachable,
      );
      await links.sync();
      expect(indexRows(library.slug), 1);
      expect(await externalIn(book), isEmpty);
    });
  });

  group('חיווט לסיכומים, למפרשים בטווח ולמפרשים נוספים', () {
    test('כיוון הפוך — סיכום, מפרשים בטווח ומפרשים נוספים', () async {
      final library = await attach(
        attachedDb(
          'ext',
          rows: [
            _row(0, targetRef: officialRef(1)),
            _row(1, targetLineIndex: 2),
          ],
        ),
      );
      await links.sync();
      final book = await bookOf(
        BookSource.official,
        SeforimFixtureIds.bereshitTitle,
      );
      final source = BookSource.attached(library.slug);

      final summary = await provider.getBookLinkTargetsSummary(
        book.title,
        book.categoryId!,
      );
      final entry = summary!.targets.singleWhere(
        (t) => t.targetTitle == _commentaryTitle,
      );
      expect(entry.linkCount, 2);
      expect(entry.targetSource, source);
      expect(summary.maxSourceLine, greaterThanOrEqualTo(3));

      final repository = TextBookRepository(
        fileSystem: FileSystemData.instance,
      );
      final inRange = await repository.getCommentatorsInLineRange(
        book,
        startLine: 0,
        endLine: 5,
      );
      expect(inRange.map((c) => c.title), contains(_commentaryTitle));

      final siblings = await repository.getSiblingCommentaries(
        sourceBookTitle: book.title,
        sourceCategoryId: book.categoryId,
        sourceLineIndex: 1,
        currentBookTitle: 'no such book',
        currentCategoryId: null,
      );
      expect(
        siblings.where((l) => l.path2 == _commentaryTitle).single.targetSource,
        source,
      );
    });

    test('כיוון ישיר — סיכום, ויעד מסומן במקור שלו', () async {
      final library = await attach(
        attachedDb('ext', rows: [_row(0, targetLineIndex: 1)]),
      );
      final book = await bookOf(
        BookSource.attached(library.slug),
        _commentaryTitle,
      );
      final summary = await provider.getBookLinkTargetsSummary(
        book.title,
        book.categoryId!,
        source: book.source,
      );
      final entry = summary!.targets.singleWhere(
        (t) => t.targetSource == BookSource.official,
      );
      expect(entry.targetTitle, SeforimFixtureIds.bereshitTitle);
      expect(entry.linkCount, 1);
    });

    test('targetSource מנורמל כמו ה-slug של המסד', () async {
      final target = await attach(attachedDb('ext'));
      final library = await attach(
        attachedDb(
          'src',
          rows: [
            _row(
              0,
              targetSource: 'EXT!',
              targetTitle: _baseTitle,
              targetLineIndex: 1,
            ),
          ],
        ),
      );
      expect(target.slug, 'ext');
      final book = await bookOf(
        BookSource.attached(library.slug),
        _commentaryTitle,
      );
      final external = await externalIn(book);
      expect(external.single.targetSource, BookSource.attached('ext'));
    });

    test('כיוון ישיר נשמר בזיכרון — גלילה אינה פותחת מחדש את המסד', () async {
      final path = attachedDb('ext', rows: [_row(0, targetLineIndex: 1)]);
      final library = await attach(path);
      final book = await bookOf(
        BookSource.attached(library.slug),
        _commentaryTitle,
      );
      final cached = ExternalLinkRepository(
        registry: registry,
        cacheDbPath: () async => cachePath(),
        officialTarget: () => trustedDbTarget(officialPath),
      );
      Future<List<Link>> window(int start) => cached.linksInRange(
        title: book.title,
        categoryId: book.categoryId,
        source: book.source,
        startLineIndex: start,
        endLineIndex: start + 10,
      );
      expect(await window(0), hasLength(1));

      await registry.closeAll();
      await provider.sqliteProvider.dispose();
      final bytes = File(path).readAsBytesSync();
      File(path).writeAsStringSync('not a database');
      addTearDown(() => File(path).writeAsBytesSync(bytes));
      expect(await window(0), hasLength(1));
      expect(await window(5), isEmpty);
    });

    test('מסד רשמי שלא היה זמין נקלט כשהוא נפתח', () async {
      final library = await attach(
        attachedDb('ext', rows: [_row(0, targetLineIndex: 1)]),
      );
      final book = await bookOf(
        BookSource.attached(library.slug),
        _commentaryTitle,
      );
      var available = false;
      final repository = ExternalLinkRepository(
        registry: registry,
        cacheDbPath: () async => cachePath(),
        officialTarget: () => available ? trustedDbTarget(officialPath) : null,
      );
      Future<List<Link>> window() => repository.linksInRange(
        title: book.title,
        categoryId: book.categoryId,
        source: book.source,
        startLineIndex: 0,
        endLineIndex: 10,
      );
      expect(await window(), isEmpty);
      available = true;
      expect(await window(), hasLength(1));
    });

    test('קישור כפול או הדדי מופיע פעם אחת', () {
      Link link(int index2, BookSource target) => Link(
        heRef: 'x',
        index1: 1,
        path2: 'p',
        index2: index2,
        connectionType: 'COMMENTARY',
        targetSource: target,
      );
      final merged = TextBookRepository.mergeExtraLinks(
        [link(1, BookSource.official)],
        [
          link(1, BookSource.official),
          link(2, BookSource.attached('a')),
          link(2, BookSource.attached('a')),
          link(2, BookSource.attached('b')),
        ],
      );
      expect(merged.map((l) => (l.index2, l.targetSource)), [
        (1, BookSource.official),
        (2, BookSource.attached('a')),
        (2, BookSource.attached('b')),
      ]);
    });
  });

  group('מסד עוין או ענק', () {
    test('מעל תקרת השורות — מדולג, מסומן, ולא נבנה שוב עד שינוי', () async {
      final previous = ExternalLinkRepository.maxIndexRows;
      addTearDown(() => ExternalLinkRepository.maxIndexRows = previous);
      ExternalLinkRepository.maxIndexRows = 1;
      final path = attachedDb(
        'ext',
        rows: [_row(0, targetLineIndex: 1), _row(1, targetLineIndex: 2)],
      );
      final library = await attach(path);
      expect(await links.sync(), isEmpty);
      expect(indexRows(library.slug), 0);
      expect(await links.sync(), isEmpty);

      ExternalLinkRepository.maxIndexRows = previous;
      expect(await links.sync(), isEmpty);
      expect(links.tooLargeSlugs.value, {library.slug});
      touch(path);
      await attached.rescan();
      expect(await links.sync(), {library.slug});
      expect(indexRows(library.slug), 2);
      expect(links.tooLargeSlugs.value, isEmpty);
    });

    String? metaSignature(String slug) {
      final db = sqlite3.sqlite3.open(cachePath());
      try {
        return db.select(
              'SELECT targetsSignature FROM attached_external_link_meta '
              'WHERE sourceSlug = ?',
              [slug],
            ).firstOrNull?['targetsSignature']
            as String?;
      } finally {
        db.close();
      }
    }

    List<ExternalLinkFixtureRow> fiveRows() => [
      for (var i = 0; i < 5; i++) _row(i, targetLineIndex: 1),
    ];

    test('נבנה במנות תוך כדי הקריאה, וה-meta נכתב בסוף', () async {
      final previous = ExternalLinkRepository.insertBatchSize;
      addTearDown(() => ExternalLinkRepository.insertBatchSize = previous);
      ExternalLinkRepository.insertBatchSize = 2;
      final library = await attach(attachedDb('ext', rows: fiveRows()));
      expect(await links.sync(), {library.slug});
      expect(indexRows(library.slug), 5);
      expect(metaSignature(library.slug), isNot(startsWith('!')));
      expect(links.tooLargeSlugs.value, isEmpty);
    });

    test('תקרה שנחצית אחרי שמנות נכתבו — הכל נמחק והמסד מסומן', () async {
      final batch = ExternalLinkRepository.insertBatchSize;
      final max = ExternalLinkRepository.maxIndexRows;
      addTearDown(() {
        ExternalLinkRepository.insertBatchSize = batch;
        ExternalLinkRepository.maxIndexRows = max;
      });
      ExternalLinkRepository.insertBatchSize = 2;
      ExternalLinkRepository.maxIndexRows = 3;
      final library = await attach(attachedDb('ext', rows: fiveRows()));
      expect(await links.sync(), isEmpty);
      expect(indexRows(library.slug), 0);
      expect(metaSignature(library.slug), startsWith('!toolarge:'));
      expect(links.tooLargeSlugs.value, {library.slug});
    });

    test('כותרת יעד ארוכה מדי אינה נפתרת', () async {
      final library = await attach(
        attachedDb(
          'ext',
          rows: [
            _row(
              0,
              targetTitle: 'x' * (kMaxExternalTextLength + 1),
              targetLineIndex: 1,
            ),
            _row(1, targetLineIndex: 2),
          ],
        ),
      );
      final book = await bookOf(
        BookSource.attached(library.slug),
        _commentaryTitle,
      );
      expect(await externalIn(book), hasLength(1));
    });
  });
}

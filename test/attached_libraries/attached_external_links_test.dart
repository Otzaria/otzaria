import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:material_ui/material_ui.dart' as mui;
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
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
import 'package:otzaria/library_update/services/library_runtime_refresh_service.dart';
import 'package:otzaria/migration/database/untrusted_database.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/pdf_book/view/pdf_commentary_panel.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../helpers/seforim_fixture_db.dart';
import '../test_helpers/memory_cache_provider.dart';
import '../test_helpers/pdf_document_dispose.dart';

/// כותרות גנריות לספרי המסד המצורף — שלא יתנגשו בכותרות הספרייה הרשמית.
const _commentaryTitle = 'ספר א';
const _baseTitle = 'ספר ב';
const _laterEra = 'אחרונים';

Future<void> _holdExclusiveWriter(String path, SendPort ready) =>
    Isolate.run(() async {
      final db = sqlite3.sqlite3.open(path);
      final release = ReceivePort();
      try {
        db.execute('PRAGMA busy_timeout=5000');
        db.execute('BEGIN EXCLUSIVE');
        ready.send(release.sendPort);
        await release.first;
        db.execute('ROLLBACK');
      } finally {
        release.close();
        db.close();
      }
    });

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

  Future<void> withLockedOfficial(Future<void> Function() action) async {
    final ready = ReceivePort();
    final writer = _holdExclusiveWriter(officialPath, ready.sendPort);
    SendPort? release;
    try {
      release = await Future.any<SendPort>([
        ready.first.then((message) => message as SendPort),
        writer.then<SendPort>(
          (_) => throw StateError('writer exited before acquiring the lock'),
        ),
      ]);
      await action();
    } finally {
      release?.send(null);
      ready.close();
      await writer;
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

  testWidgets('קישורי PDF חוזרים בדפדוף אחרי שחרור נעילת יעד באותו טאב', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => tempDir.path);
    final previousLibrary = await tester.runAsync(
      () async =>
          (value: DataRepository.instance.cachedLibraryFutureForTesting),
    );
    addTearDown(() {
      if (previousLibrary!.value == null) {
        DataRepository.instance.invalidateLibraryCache();
      } else {
        DataRepository.instance.library = previousLibrary.value!;
      }
    });
    final modulePath = Pdfrx.pdfiumModulePath;
    final moduleName = Platform.isWindows
        ? 'pdfium.dll'
        : Platform.isMacOS
        ? 'libpdfium.dylib'
        : 'libpdfium.so';
    Pdfrx.pdfiumModulePath = File(
      'build/native_assets/${Platform.operatingSystem}/$moduleName',
    ).absolute.path;
    addTearDown(() {
      Pdfrx.pdfiumModulePath = modulePath;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    late TextBook book;
    final file = File(p.join(tempDir.path, 'book.pdf'));
    await tester.runAsync(() async {
      final library = await attach(
        attachedDb(
          'pdf-lock',
          rows: [
            _row(1, targetLineIndex: 1, connectionType: LinkTypes.commentary),
          ],
        ),
      );
      await links.sync();
      book = await bookOf(BookSource.attached(library.slug), _commentaryTitle);
      DataRepository.instance.library = buildCatalog();
      await DataRepository.instance.library;
      await pdfrxFlutterInitialize();
      final pdf = pw.Document();
      for (var page = 0; page < 3; page++) {
        pdf.addPage(pw.Page(build: (_) => pw.Text('page ${page + 1}')));
      }
      await file.writeAsBytes(await pdf.save());
    });
    final tab = PdfBookTab(
      pageNumber: 1,
      book: PdfBook(
        title: book.title,
        path: file.path,
        categoryId: book.categoryId,
        source: book.source,
      ),
    );
    final tabs = TabsBloc(repository: _PdfTabsRepository());
    // ignore: invalid_use_of_visible_for_testing_member
    tabs.emit(TabsState(tabs: [tab], currentTabIndex: 0));
    final settings = _PdfSettingsBloc();
    final tour = TourCubit();
    addTearDown(tabs.close);
    addTearDown(settings.close);
    addTearDown(tour.close);
    final ready = ReceivePort();
    late Future<void> writer;
    SendPort? release;
    await tester.runAsync(() async {
      writer = _holdExclusiveWriter(officialPath, ready.sendPort);
      release = await ready.first as SendPort;
    });
    addTearDown(() async {
      release?.send(null);
      ready.close();
      await writer;
    });
    Future<void> pumpUntil(bool Function() condition) async {
      for (var attempt = 0; attempt < 200 && !condition(); attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(condition(), isTrue);
    }

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          mui.DefaultMaterialLocalizations.delegate,
        ],
        home: MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settings),
            BlocProvider<TabsBloc>.value(value: tabs),
            BlocProvider<TourCubit>.value(value: tour),
          ],
          child: PdfBookScreen(tab: tab),
        ),
      ),
    );
    await pumpUntil(
      () => tab.pdfViewerController.isReady && !tab.linksLoadingNotifier.value,
    );
    final screen = tester.state(find.byType(PdfBookScreen));
    final document = tab.pdfViewerController.document;
    expect(
      tab.links.where((link) => link.targetSource != book.source),
      isEmpty,
    );
    await tester.runAsync(() async {
      release!.send(null);
      release = null;
      await writer;
      await tab.pdfViewerController.goToPage(
        pageNumber: 2,
        duration: Duration.zero,
      );
    });
    await pumpUntil(
      () => tab.links.any((link) => link.targetSource == BookSource.official),
    );
    final viewer = find.byType(PdfViewer);
    final menu = tester.widget<AppContextMenuRegion>(
      find.descendant(of: viewer, matching: find.byType(AppContextMenuRegion)),
    );
    final commentators = menu
        .menuBuilder(tester.element(viewer), tester.getCenter(viewer))
        .firstWhere((entry) => entry.label == 'מפרשים')
        .children!;
    expect(
      commentators.map((entry) => entry.label),
      contains(SeforimFixtureIds.bereshitTitle),
    );
    expect(
      commentators.where(
        (entry) =>
            entry.label?.startsWith('הצג את כל ') == true &&
            entry.label != 'הצג את כל המפרשים',
      ),
      hasLength(1),
    );
    expect(tour.hasRegisteredCommentaryOpportunity, isTrue);
    expect(tester.state(find.byType(PdfBookScreen)), same(screen));
    expect(tab.pageNumber, 2);
    expect(tab.linksAreComplete, isFalse);
    expect(
      tab.links.where((link) => link.targetSource == BookSource.official),
      hasLength(1),
    );

    // בדיקת הטיימרים התלויים רצה לפני addTearDown,
    // ו-pdfrx ממתין 100ms לפני טעינת שאר העמודים.
    await tester.pumpWidget(const SizedBox.shrink());
    await disposePdfDocument(tester, document);
    await tester.pump(const Duration(milliseconds: 200));
  });

  test('מפרשי PDF משני מסדים בעלי אותה כותרת נשארים נפרדים', () async {
    final sources = <BookSource>[];
    for (final name in ['library-a', 'library-b']) {
      final path = attachedDb(name, rows: [_row(0, targetLineIndex: 1)]);
      final db = sqlite3.sqlite3.open(path);
      try {
        db.execute(
          'UPDATE line SET content = ? WHERE bookId = ? AND lineIndex = 0',
          ['תוכן של $name', SeforimFixtureIds.rashiId],
        );
      } finally {
        db.close();
      }
      final library = await attach(path);
      sources.add(BookSource.attached(library.slug));
    }
    await links.sync();
    final book = await bookOf(
      BookSource.official,
      SeforimFixtureIds.bereshitTitle,
    );
    final loaded = (await externalIn(
      book,
    )).where((link) => link.path2 == _commentaryTitle).toList();
    expect(loaded, hasLength(2));
    expect(loaded.map((link) => link.targetSource), sources);
    expect(
      await Future.wait(loaded.map(provider.getLinkContent)),
      ['תוכן של library-a', 'תוכן של library-b'],
    );

    expect(
      pdfScopedCommentaryLinks(
        links: loaded,
        startLine: 1,
        endLine: 10,
        extraLineIndices: null,
        activeCommentators: {_commentaryTitle},
        showAllWhenEmpty: false,
      ),
      loaded,
    );
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

    test(
      'רענון הספרייה בונה מחדש קישורים חיצוניים ומשמר חיבור מצורף',
      () async {
        final library = await attach(
          attachedDb('ext', rows: [_row(0, targetLineIndex: 1)]),
        );
        await buildCatalog();
        expect(await links.sync(), {library.slug});

        final db = sqlite3.sqlite3.open(officialPath);
        db.execute(
          "UPDATE schema_meta SET value = '2' WHERE key = 'db_version'",
        );
        db.close();
        final attachedRepository = await registry.repositoryFor(library.slug);
        final attachedConnection = await attachedRepository!.database.database;
        await const LibraryRuntimeRefreshService().refreshAfterDbUpdate();
        expect(
          await registry.repositoryFor(library.slug),
          same(attachedRepository),
        );
        expect(
          await attachedRepository.database.database,
          same(attachedConnection),
        );
        expect(await links.sync(), {library.slug});
      },
    );

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

    test('יעדי אינדקס עם Unicode ו-NUL פנימי נשמרים בנפרד', () async {
      final titles = [
        'א',
        'א\u0000ב',
        'א\u0000ג',
        'A',
        'a',
        'é',
        'e\u0301',
        '😀',
        '𐀀',
      ];
      final db = sqlite3.sqlite3.open(officialPath);
      try {
        for (var i = 0; i < titles.length; i++) {
          db.execute(
            'INSERT INTO book (id, title, categoryId, sourceId) '
            'VALUES (?, ?, 1, 1)',
            [9000 + i, titles[i]],
          );
          db.execute(
            'INSERT INTO line (id, bookId, lineIndex, heRef, content) '
            'VALUES (?, ?, 1, ?, ?)',
            [90000 + i, 9000 + i, titles[i], 'שורת יעד'],
          );
        }
      } finally {
        db.close();
      }
      final library = await attach(
        attachedDb(
          'unicode',
          rows: [
            for (final title in titles)
              _row(0, targetTitle: title, targetLineIndex: 1),
          ],
        ),
      );
      await links.sync();
      expect(indexRows(library.slug), titles.length);
      for (final title in titles) {
        final reverse = await links.linksInRange(
          title: title,
          categoryId: null,
          source: BookSource.official,
          startLineIndex: 0,
          endLineIndex: 3,
        );
        expect(reverse, hasLength(1), reason: title.codeUnits.toString());
        expect(reverse.single.targetSource, BookSource.attached(library.slug));
      }
    });

    test('כל יעדי האינדקס נמצאים — כמה כותרות בכמה מסדים', () async {
      final target = await attach(attachedDb('ext'));
      final library = await attach(
        attachedDb(
          'src',
          rows: [
            _row(0, targetLineIndex: 1),
            _row(
              1,
              targetTitle: SeforimFixtureIds.rashiTitle,
              targetLineIndex: 0,
            ),
            _row(
              2,
              targetSource: 'ext',
              targetTitle: _baseTitle,
              targetLineIndex: 1,
            ),
          ],
        ),
      );
      expect(await links.sync(), containsAll([library.slug]));
      final source = BookSource.attached(library.slug);
      for (final (bookSource, title) in [
        (BookSource.official, SeforimFixtureIds.bereshitTitle),
        (BookSource.official, SeforimFixtureIds.rashiTitle),
        (BookSource.attached(target.slug), _baseTitle),
      ]) {
        final reverse = await externalIn(await bookOf(bookSource, title));
        expect(
          reverse.where((l) => l.targetSource == source),
          hasLength(1),
          reason: '$bookSource $title',
        );
      }
      final unlinked = await bookOf(
        BookSource.attached(target.slug),
        _commentaryTitle,
      );
      expect(await externalIn(unlinked), isEmpty);
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

    test('נעילת יעד זמנית אינה נשמרת כתוצאת כיוון ישיר ריקה', () async {
      final library = await attach(
        attachedDb('ext', rows: [_row(0, targetLineIndex: 1)]),
      );
      await links.sync();
      Future<List<Link>> read() => links.linksInRange(
        title: _commentaryTitle,
        categoryId: null,
        source: BookSource.attached(library.slug),
        startLineIndex: 0,
        endLineIndex: 10,
      );

      await withLockedOfficial(() async {
        await expectLater(read(), throwsA(isA<sqlite3.SqliteException>()));
      });
      expect(await read(), hasLength(1));
      expect(await read(), hasLength(1));
    });

    test('נעילת יעד זמנית אינה נשמרת כסיכום קישורים ריק', () async {
      final library = await attach(
        attachedDb('ext', rows: [_row(0, targetLineIndex: 1)]),
      );
      await links.sync();
      Future<int> read() async => (await links.targetsSummary(
        title: _commentaryTitle,
        categoryId: null,
        source: BookSource.attached(library.slug),
      )).targets.fold<int>(0, (sum, target) => sum + target.linkCount);

      await withLockedOfficial(() async {
        await expectLater(read(), throwsA(isA<sqlite3.SqliteException>()));
      });
      expect(await read(), 1);
    });

    test('נעילת יעד זמנית אינה נשמרת כמפת מפרשים ריקה', () async {
      final library = await attach(
        attachedDb(
          'ext',
          rows: [
            _row(0, targetLineIndex: 1, connectionType: 'COMMENTARY'),
          ],
        ),
      );
      await links.sync();
      Future<Map<String, BookSource>> read() => links.commentatorSources(
        title: _commentaryTitle,
        categoryId: null,
        source: BookSource.attached(library.slug),
      );

      await withLockedOfficial(() async {
        await expectLater(read(), throwsA(isA<sqlite3.SqliteException>()));
      });
      expect(await read(), {
        SeforimFixtureIds.bereshitTitle: BookSource.official,
      });
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

    List<String> indexSnapshot(String slug) {
      final db = sqlite3.sqlite3.open(cachePath());
      try {
        return [
          for (final row in db.select(
            'SELECT sourceBookId, sourceLineIndex, targetLineIndex, connectionType '
            'FROM attached_external_link_index WHERE sourceSlug = ? '
            'ORDER BY sourceBookId, sourceLineIndex, targetLineIndex, connectionType',
            [slug],
          ))
            '${row['sourceBookId']}:${row['sourceLineIndex']}:'
                '${row['targetLineIndex']}:${row['connectionType']}',
        ];
      } finally {
        db.close();
      }
    }

    for (final completedRows in [0, 2]) {
      test(
        'כשל בכתיבה ראשונית אחרי $completedRows שורות נשאר לא שלם ומתחדש',
        () async {
          final previousBatch = ExternalLinkRepository.insertBatchSize;
          addTearDown(
            () => ExternalLinkRepository.insertBatchSize = previousBatch,
          );
          ExternalLinkRepository.insertBatchSize = 2;
          final library = await attach(attachedDb('ext', rows: fiveRows()));
          expect(await links.sync(), {library.slug});
          final full = indexSnapshot(library.slug);

          final db = sqlite3.sqlite3.open(cachePath());
          try {
            for (final table in ['index', 'target', 'meta']) {
              db.execute(
                'DELETE FROM attached_external_link_$table WHERE sourceSlug = ?',
                [library.slug],
              );
            }
            db.execute('''
              CREATE TRIGGER fail_link_batch
              BEFORE INSERT ON attached_external_link_index
              WHEN NEW.sourceLineIndex >= $completedRows
              BEGIN SELECT RAISE(ABORT, 'injected link batch failure'); END;
            ''');
          } finally {
            db.close();
          }

          expect(await links.sync(), isEmpty);
          expect(links.incompleteSlugs.value, {library.slug});
          expect(metaSignature(library.slug), startsWith('!building:'));
          expect(indexRows(library.slug), completedRows);
          expect(links.buildProgress.value, isEmpty);
          expect(links.buildingSlugs.value, isEmpty);

          final reopened = ExternalLinkRepository(
            registry: registry,
            cacheDbPath: () async => cachePath(),
          );
          expect(await reopened.sync(), isEmpty);
          expect(reopened.incompleteSlugs.value, {library.slug});
          expect(indexRows(library.slug), completedRows);
          expect(
            await reopened.linksInRange(
              title: SeforimFixtureIds.bereshitTitle,
              categoryId: null,
              source: BookSource.official,
              startLineIndex: 0,
              endLineIndex: 10,
            ),
            isEmpty,
          );

          final repaired = sqlite3.sqlite3.open(cachePath());
          try {
            repaired.execute('DROP TRIGGER fail_link_batch');
          } finally {
            repaired.close();
          }
          reopened.requestResume(library.slug);
          await reopened.sync();
          expect(reopened.incompleteSlugs.value, isEmpty);
          expect(metaSignature(library.slug), isNot(startsWith('!')));
          expect(indexSnapshot(library.slug), full);
          expect(indexRows(library.slug), 5);
        },
      );
    }

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

    test('נעילת יעד בשורה היחידה אינה מסיימת אינדקס ריק', () async {
      final library = await attach(
        attachedDb('ext', rows: [_row(0, targetLineIndex: 1)]),
      );
      await links.sync();
      final full = indexSnapshot(library.slug);
      expect(full, hasLength(1));

      await withLockedOfficial(() => links.rebuild(library.slug));
      expect(links.incompleteSlugs.value, {library.slug});
      expect(metaSignature(library.slug), startsWith('!building:'));
      expect(indexRows(library.slug), 0);

      links.requestResume(library.slug);
      await links.sync();
      expect(links.incompleteSlugs.value, isEmpty);
      expect(metaSignature(library.slug), isNot(startsWith('!')));
      expect(indexSnapshot(library.slug), full);
    });

    test('נעילת גרסת היעד אינה מוחקת אינדקס תקין או בוחרת מסד חלופי', () async {
      final fallbackPath = attachedDb('fallback');
      final fallback = sqlite3.sqlite3.open(fallbackPath);
      try {
        fallback.execute('UPDATE book SET title = ? WHERE id = ?', [
          SeforimFixtureIds.bereshitTitle,
          SeforimFixtureIds.bereshitId,
        ]);
      } finally {
        fallback.close();
      }
      await attach(fallbackPath);
      final library = await attach(
        attachedDb(
          'ext',
          rows: [_row(0, targetSource: null, targetLineIndex: 1)],
        ),
      );
      await links.sync();
      final signature = metaSignature(library.slug);
      final full = indexSnapshot(library.slug);
      final reopened = ExternalLinkRepository(
        registry: registry,
        cacheDbPath: () async => cachePath(),
        officialTarget: () => trustedDbTarget(officialPath),
      );

      await withLockedOfficial(() async {
        await expectLater(
          reopened.sync(),
          throwsA(
            isA<sqlite3.SqliteException>().having(
              (e) => e.resultCode,
              'resultCode',
              sqlite3.SqlError.SQLITE_BUSY,
            ),
          ),
        );
        expect(metaSignature(library.slug), signature);
        expect(indexSnapshot(library.slug), full);
        await expectLater(
          reopened.rebuild(library.slug),
          throwsA(isA<sqlite3.SqliteException>()),
        );
        expect(metaSignature(library.slug), signature);
        expect(indexSnapshot(library.slug), full);
      });
      expect(await reopened.sync(), isEmpty);
      expect(indexSnapshot(library.slug), full);
      final resolved = await reopened.linksInRange(
        title: _commentaryTitle,
        categoryId: null,
        source: BookSource.attached(library.slug),
        startLineIndex: 0,
        endLineIndex: 10,
      );
      expect(resolved.single.targetSource, BookSource.official);
    });

    for (final resume in [false, true]) {
      test(
        'בקשת ${resume ? 'המשך' : 'בנייה מחדש'} שנכשלת לפני תחילת הבנייה '
        'מדווחת סיום ומאפשרת בקשה חוזרת',
        () async {
          final library = await attach(attachedDb('ext', rows: fiveRows()));
          await links.sync();
          final full = indexSnapshot(library.slug);
          if (resume) {
            final db = sqlite3.sqlite3.open(cachePath());
            try {
              db.execute('BEGIN');
              db.execute(
                "UPDATE attached_external_link_meta SET targetsSignature = "
                "'!building:' || targetsSignature || ? WHERE sourceSlug = ?",
                ['\u0001stop', library.slug],
              );
              db.execute(
                'DELETE FROM attached_external_link_target WHERE sourceSlug = ?',
                [library.slug],
              );
              db.execute('COMMIT');
            } finally {
              db.close();
            }
          }
          final signature = metaSignature(library.slug);
          final reopened = ExternalLinkRepository(
            registry: registry,
            cacheDbPath: () async => cachePath(),
            officialTarget: () => trustedDbTarget(officialPath),
          );
          Future<void> requestAndWait() async {
            final completed = Completer<void>();
            void observe() {
              if (reopened.buildingSlugs.value.isEmpty &&
                  !completed.isCompleted) {
                completed.complete();
              }
            }

            reopened.buildingSlugs.addListener(observe);
            try {
              if (resume) {
                reopened.requestResume(library.slug);
              } else {
                reopened.requestRebuild(library.slug);
              }
              await completed.future.timeout(const Duration(seconds: 5));
            } finally {
              reopened.buildingSlugs.removeListener(observe);
            }
          }

          await withLockedOfficial(() async {
            await requestAndWait();
            expect(metaSignature(library.slug), signature);
            expect(indexSnapshot(library.slug), full);
          });
          await requestAndWait();
          expect(reopened.incompleteSlugs.value, isEmpty);
          expect(metaSignature(library.slug), isNot(startsWith('!')));
          expect(indexSnapshot(library.slug), full);
        },
      );
    }

    test('כשל נעילה אחרי רענון מניע סנכרון אוטומטי בשימוש הבא', () async {
      final library = await attach(
        attachedDb('ext', rows: [_row(0, targetLineIndex: 1)]),
      );
      await links.sync();
      final previousSignature = metaSignature(library.slug);
      final updated = sqlite3.sqlite3.open(officialPath);
      try {
        updated.execute(
          "UPDATE schema_meta SET value = '2' WHERE key = 'db_version'",
        );
      } finally {
        updated.close();
      }
      links.resetRuntime();
      Future<int> targetCount() async => (await links.targetsSummary(
        title: SeforimFixtureIds.bereshitTitle,
        categoryId: null,
        source: BookSource.official,
      )).targets.length;

      await withLockedOfficial(() async {
        await expectLater(
          targetCount(),
          throwsA(isA<sqlite3.SqliteException>()),
        );
        await Future<void>.delayed(Duration.zero);
      });
      final deadline = Stopwatch()..start();
      var count = await targetCount();
      while (count == 0 && deadline.elapsed < const Duration(seconds: 5)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        count = await targetCount();
      }
      expect(count, 1);
      expect(metaSignature(library.slug), isNot(previousSignature));
      expect(metaSignature(library.slug), isNot(startsWith('!')));
      expect(indexRows(library.slug), 1);
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

    test(
      'בנייה שנקטעה — מסומנת כלא שלמה, לא נבנית שוב, ו-rebuild מתקן',
      () async {
        final library = await attach(attachedDb('ext', rows: fiveRows()));
        expect(await links.sync(), {library.slug});
        expect(links.incompleteSlugs.value, isEmpty);

        // הפסקה באמצע הבנייה: הסימון !building נשאר והאינדקס חלקי.
        final db = sqlite3.sqlite3.open(cachePath());
        db.execute(
          "UPDATE attached_external_link_meta SET targetsSignature = "
          "'!building:' || targetsSignature WHERE sourceSlug = ?",
          [library.slug],
        );
        db.close();

        expect(await links.sync(), isEmpty);
        expect(links.incompleteSlugs.value, {library.slug});
        expect(metaSignature(library.slug), startsWith('!building:'));

        await links.rebuild(library.slug);
        expect(links.incompleteSlugs.value, isEmpty);
        expect(metaSignature(library.slug), isNot(startsWith('!')));
        expect(indexRows(library.slug), 5);
      },
    );

    test('buildingSlugs מציג את המסד בזמן הבנייה ונוקה בסיומה', () async {
      final seen = <Set<String>>[];
      void record() => seen.add(links.buildingSlugs.value);
      links.buildingSlugs.addListener(record);
      addTearDown(() => links.buildingSlugs.removeListener(record));
      final library = await attach(attachedDb('ext', rows: fiveRows()));

      expect(await links.sync(), {library.slug});
      expect(seen.first, {library.slug});
      expect(links.buildingSlugs.value, isEmpty);

      // בלי שינוי — אין בנייה ולכן אין סימון.
      seen.clear();
      expect(await links.sync(), isEmpty);
      expect(seen.where((slugs) => slugs.isNotEmpty), isEmpty);
    });

    /// מנות קטנות ודיווח על כל מנה, בלי השהיות לפי שעון הקיר.
    void smallBatches({int batchSize = 1}) {
      final batch = ExternalLinkRepository.insertBatchSize;
      final interval = ExternalLinkRepository.progressInterval;
      addTearDown(() {
        ExternalLinkRepository.insertBatchSize = batch;
        ExternalLinkRepository.progressInterval = interval;
      });
      ExternalLinkRepository.insertBatchSize = batchSize;
      ExternalLinkRepository.progressInterval = Duration.zero;
    }

    test('buildProgress עולה עד total, ומתנקה בסיום', () async {
      final batch = ExternalLinkRepository.insertBatchSize;
      final interval = ExternalLinkRepository.progressInterval;
      addTearDown(() {
        ExternalLinkRepository.insertBatchSize = batch;
        ExternalLinkRepository.progressInterval = interval;
      });
      ExternalLinkRepository.insertBatchSize = 2;
      ExternalLinkRepository.progressInterval = Duration.zero;
      final library = await attach(attachedDb('ext', rows: fiveRows()));
      final seen = <ExternalLinkBuildProgress>[];
      links.buildProgress.addListener(() {
        final progress = links.buildProgress.value[library.slug];
        if (progress != null) seen.add(progress);
      });

      expect(await links.sync(), {library.slug});
      expect(
        seen.map((p) => p.done),
        orderedEquals([...seen.map((p) => p.done)]..sort()),
      );
      // הדיווח הראשון הוא רשימת ה-slugs, עוד לפני ספירת השורות.
      expect(seen.first.total, 0);
      expect(seen.skip(1).every((p) => p.total == 5), isTrue);
      expect(seen[1].done, 0);
      expect(seen.last.done, 5);
      expect(seen.last.fraction, 1);
      expect(links.buildProgress.value, isEmpty);
      expect(links.buildingSlugs.value, isEmpty);
    });

    test('כשל בסנכרון מנקה את buildProgress', () async {
      await attach(attachedDb('ext', rows: fiveRows()));
      // נתיב שהוא תיקייה — פתיחת cache.db נכשלת.
      final broken = ExternalLinkRepository(
        registry: registry,
        cacheDbPath: () async => tempDir.path,
      );
      await expectLater(broken.sync(), throwsA(anything));
      expect(broken.buildProgress.value, isEmpty);
      expect(broken.buildingSlugs.value, isEmpty);
    });

    test('הסרת מסד לא שלם מנקה את incompleteSlugs', () async {
      final library = await attach(attachedDb('ext', rows: fiveRows()));
      await links.sync();
      final db = sqlite3.sqlite3.open(cachePath());
      db.execute(
        "UPDATE attached_external_link_meta SET targetsSignature = "
        "'!building:' || targetsSignature WHERE sourceSlug = ?",
        [library.slug],
      );
      db.close();
      await links.sync();
      expect(links.incompleteSlugs.value, {library.slug});

      await attached.remove(library);
      await links.sync();
      expect(links.incompleteSlugs.value, isEmpty);
    });

    test(
      'מסד בלי externalLinks או לא נגיש אינו מופיע ב-buildProgress',
      () async {
        final reachablePath = attachedDb('ext', rows: fiveRows());
        await attach(reachablePath);
        await links.sync();
        final plain = await attach(attachedDb('plain'));
        expect(
          plain.capabilities.contains(AttachedLibraryCapability.externalLinks),
          isFalse,
        );

        await registry.closeAll();
        File(reachablePath).renameSync('$reachablePath.away');
        await attached.rescan();
        final keys = <String>{};
        links.buildProgress.addListener(
          () => keys.addAll(links.buildProgress.value.keys),
        );
        links.buildingSlugs.addListener(
          () => keys.addAll(links.buildingSlugs.value),
        );
        await links.sync();
        expect(keys, isEmpty);
      },
    );

    test('rebuild רץ בשרשרת — סנכרונים מקבילים אינם נכשלים', () async {
      final library = await attach(attachedDb('ext', rows: fiveRows()));
      await links.sync();
      final db = sqlite3.sqlite3.open(cachePath());
      db.execute(
        "UPDATE attached_external_link_meta SET targetsSignature = "
        "'!building:' || targetsSignature WHERE sourceSlug = ?",
        [library.slug],
      );
      db.close();

      await Future.wait([
        links.sync(),
        links.rebuild(library.slug),
        links.sync(),
        links.sync(),
      ]);
      expect(links.incompleteSlugs.value, isEmpty);
      expect(indexRows(library.slug), 5);
    });

    /// מעמיד את הבקרה לפני שה-isolate יכול לעבור את נקודת הבקרה הראשונה.
    void onNextBuild(void Function() action) {
      expect(links.onBuildStart, isNull);
      links.onBuildStart = () {
        links.onBuildStart = null;
        action();
      };
      addTearDown(() => links.onBuildStart = null);
    }

    /// בונה את [slug] מחדש ועוצר בנקודת הבקרה הראשונה, גם אם המנה חלקית.
    Future<void> rebuildAndCancel(String slug) async {
      onNextBuild(links.cancelBuild);
      try {
        await links.rebuild(slug);
      } finally {
        links.onBuildStart = null;
      }
    }

    int doneOf(String slug) => links.buildProgress.value[slug]?.done ?? -1;

    Future<void> waitForProgress(
      String slug,
      int minimum,
      Future<Object?> build,
    ) async {
      final reached = Completer<void>();
      void record() {
        if (doneOf(slug) >= minimum && !reached.isCompleted) {
          reached.complete();
        }
      }

      links.buildProgress.addListener(record);
      try {
        record();
        await Future.any([
          reached.future,
          build.then((_) {
            if (!reached.isCompleted) {
              fail('הבנייה הסתיימה לפני דיווח ההתקדמות המצופה');
            }
          }),
        ]);
      } finally {
        links.buildProgress.removeListener(record);
      }
    }

    test('השהיה עוצרת את ההתקדמות, והמשך ממשיך', () async {
      smallBatches();
      final library = await attach(attachedDb('ext', rows: fiveRows()));
      onNextBuild(links.pauseBuild);
      var finished = false;
      final done = links.sync().whenComplete(() => finished = true);
      try {
        // המנה הראשונה נכתבה והבנייה ממתינה בהשהיה.
        await waitForProgress(library.slug, 1, done);
        expect(links.buildPaused.value, isTrue);
        expect(doneOf(library.slug), 1);
        expect(indexRows(library.slug), 1);
        expect(finished, isFalse);

        links.resumeBuild();
        expect(await done, {library.slug});
        expect(indexRows(library.slug), 5);
        expect(links.buildPaused.value, isFalse);
        expect(links.buildProgress.value, isEmpty);
      } finally {
        links.cancelBuild();
        await done;
      }
    });

    test('בזמן השהיה המסד הרשמי אינו נעול לכתיבה', () async {
      smallBatches();
      final library = await attach(attachedDb('ext', rows: fiveRows()));
      onNextBuild(links.pauseBuild);
      final done = links.sync();
      try {
        await waitForProgress(library.slug, 1, done);
        expect(indexRows(library.slug), 1);
        final writer = sqlite3.sqlite3.open(officialPath);
        try {
          expect(
            writer.select('PRAGMA journal_mode').first.values.first,
            'delete',
          );
          // BEGIN EXCLUSIVE נכשל מיד כשחיבור אחר מחזיק נעילת קריאה.
          writer.execute('BEGIN EXCLUSIVE');
          writer.execute('ROLLBACK');
        } finally {
          writer.close();
        }
        links.resumeBuild();
        expect(await done, {library.slug});
      } finally {
        links.cancelBuild();
        await done;
      }
    });

    test('נעילת יעד אחרי מנה שמורה מתחדשת ללא אובדן או כפילות', () async {
      smallBatches();
      final library = await attach(attachedDb('ext', rows: fiveRows()));
      await links.sync();
      final full = indexSnapshot(library.slug);
      onNextBuild(links.pauseBuild);
      final done = links.rebuild(library.slug);
      try {
        await waitForProgress(library.slug, 1, done);
        expect(indexRows(library.slug), 1);
        await withLockedOfficial(() async {
          links.resumeBuild();
          await done;
        });
      } finally {
        links.cancelBuild();
        await done;
      }
      expect(links.incompleteSlugs.value, {library.slug});
      expect(metaSignature(library.slug), startsWith('!building:'));
      expect(indexRows(library.slug), 1);

      links.requestResume(library.slug);
      await links.sync();
      expect(links.incompleteSlugs.value, isEmpty);
      expect(indexSnapshot(library.slug), full);
      expect(indexRows(library.slug), 5);
    });

    test('ביטול בזמן נעילת יעד אינו ממתין לכל המנה', () async {
      smallBatches(batchSize: 10);
      final library = await attach(
        attachedDb(
          'locked-target',
          rows: [for (var i = 0; i < 30; i++) _row(i, targetLineIndex: 1)],
        ),
      );
      await links.sync();
      final nextLibrary = await attach(
        attachedDb('after-cancel', rows: [_row(0, targetLineIndex: 2)]),
      );
      final ready = ReceivePort();
      final writer = _holdExclusiveWriter(officialPath, ready.sendPort);
      SendPort? release;
      final scanned = <int>[];
      void record() {
        final progress = links.buildProgress.value[library.slug];
        if (progress != null && progress.done > 0) scanned.add(progress.done);
      }

      links.buildProgress.addListener(record);
      try {
        release = await Future.any<SendPort>([
          ready.first.then((message) => message as SendPort),
          writer.then<SendPort>(
            (_) => throw StateError('writer exited before acquiring the lock'),
          ),
        ]);
        onNextBuild(links.cancelBuild);
        await links.rebuild(library.slug);
        expect(scanned, isEmpty);
        expect(indexRows(library.slug), 0);
        expect(links.incompleteSlugs.value, {library.slug});
        expect(metaSignature(library.slug), endsWith('\u0001stop'));
        expect(metaSignature(nextLibrary.slug), isNull);
        expect(indexRows(nextLibrary.slug), 0);
      } finally {
        links.cancelBuild();
        release?.send(null);
        ready.close();
        links.buildProgress.removeListener(record);
        await writer;
      }
      links.requestResume(library.slug);
      await links.sync();
      expect(links.incompleteSlugs.value, isEmpty);
      expect(indexRows(library.slug), 30);
      expect(indexSnapshot(library.slug).toSet(), hasLength(30));
      expect(indexRows(nextLibrary.slug), 1);
    });

    test('עצירה בזמן השהיה מסיימת את הסנכרון ושומרת התקדמות', () async {
      smallBatches();
      final library = await attach(attachedDb('ext', rows: fiveRows()));
      onNextBuild(links.pauseBuild);
      final done = links.sync();
      try {
        await waitForProgress(library.slug, 1, done);
        links.cancelBuild();
        expect(await done, isEmpty);
        expect(indexRows(library.slug), 1);
        expect(links.incompleteSlugs.value, {library.slug});
        expect(metaSignature(library.slug), contains('stop'));
        expect(links.buildPaused.value, isFalse);
        expect(links.buildProgress.value, isEmpty);
      } finally {
        links.cancelBuild();
        await done;
      }
    });

    test('requestRebuild כפול ללחיצה כפולה מתבצע פעם אחת', () async {
      final library = await attach(attachedDb('ext', rows: fiveRows()));
      await links.sync();
      var builds = 0;
      links.buildingSlugs.addListener(() {
        if (links.buildingSlugs.value.isNotEmpty) builds++;
      });

      links.requestRebuild(library.slug);
      links.requestRebuild(library.slug);
      await links.sync();
      expect(builds, 1);
      expect(indexRows(library.slug), 5);

      // אחרי שהסתיימה, בקשה חדשה מתקבלת.
      links.requestRebuild(library.slug);
      await links.sync();
      expect(builds, 2);
    });

    test(
      'ההתקדמות מונוטונית ומגיעה ל-total גם עם שורות לא פתורות והמשך',
      () async {
        final library = await attach(
          attachedDb(
            'ext',
            rows: [
              _row(0, targetLineIndex: 1),
              _row(1, targetTitle: 'אין כזה', targetLineIndex: 1),
              _row(2, targetLineIndex: 1),
              _row(3, targetTitle: 'אין כזה', targetLineIndex: 1),
              _row(4, targetLineIndex: 1),
            ],
          ),
        );
        await links.sync();
        // כל ריצה (הבנייה שנקטעה וההמשך) ברשימה משלה.
        final runs = <List<int>>[];
        var total = 0;
        links.buildProgress.addListener(() {
          final progress = links.buildProgress.value[library.slug];
          if (progress == null) return;
          if (progress.total == 0) runs.add([]);
          runs.last.add(progress.done);
          if (progress.total > 0) total = progress.total;
        });

        smallBatches(batchSize: 2);
        await rebuildAndCancel(library.slug);
        links.requestResume(library.slug);
        await links.sync();
        expect(links.buildProgress.value, isEmpty);

        expect(total, 5);
        expect(runs, hasLength(2));
        for (final run in runs) {
          expect(run, orderedEquals([...run]..sort()));
        }
        expect(runs.last.last, 5);
        expect(indexRows(library.slug), 3);
      },
    );

    test('שינוי הקובץ בין העצירה להמשך — בנייה מאפס', () async {
      final path = attachedDb('ext', rows: fiveRows());
      final library = await attach(path);
      await links.sync();
      smallBatches(batchSize: 2);
      await rebuildAndCancel(library.slug);
      touch(path);
      await attached.rescan();

      links.requestResume(library.slug);
      expect(await links.sync(), isEmpty);
      expect(indexRows(library.slug), 5);
      expect(links.incompleteSlugs.value, isEmpty);
    });

    /// שורה 0 עם שני קישורים ושורה 1 עם ארבעה: מנה של עד שלושה עשויה
    /// להיחתך באמצע קישורי שורה. ההמשך קורא את השורה האחרונה כולה מחדש.
    List<ExternalLinkFixtureRow> fourPerLine() => [
      for (var target = 0; target < 2; target++)
        _row(0, targetLineIndex: target),
      for (final type in ['SOURCE', 'REFERENCE'])
        for (var target = 0; target < 2; target++)
          _row(1, targetLineIndex: target, connectionType: type),
    ];

    /// ההתקדמות הראשונה (done) שדווחה אחרי ספירת השורות במהלך [action].
    Future<int> firstDoneDuring(String slug, Future<void> Function() action) {
      int? first;
      void record() {
        final progress = links.buildProgress.value[slug];
        if (first == null && progress != null && progress.total > 0) {
          first = progress.done;
        }
      }

      links.buildProgress.addListener(record);
      return action().then((_) {
        links.buildProgress.removeListener(record);
        return first!;
      });
    }

    test('עצירה שומרת התקדמות, מסמנת לא שלם ומנקה את buildProgress', () async {
      final library = await attach(attachedDb('ext', rows: fourPerLine()));
      await links.sync();
      smallBatches(batchSize: 3);
      await rebuildAndCancel(library.slug);

      expect(links.incompleteSlugs.value, {library.slug});
      expect(metaSignature(library.slug), startsWith('!building:'));
      expect(links.buildProgress.value, isEmpty);
      expect(links.buildingSlugs.value, isEmpty);
      expect(indexRows(library.slug), inInclusiveRange(1, 3));
    });

    test(
      'requestResume ממשיך מהנקודה השמורה — אינדקס זהה, בלי כפילויות',
      () async {
        final library = await attach(attachedDb('ext', rows: fourPerLine()));
        await links.sync();
        final continuous = indexSnapshot(library.slug);
        expect(continuous, hasLength(6));

        for (final batchSize in [1, 3]) {
          smallBatches(batchSize: batchSize);
          await rebuildAndCancel(library.slug);
          final saved = indexRows(library.slug);
          expect(saved, inInclusiveRange(1, batchSize));

          final firstDone = await firstDoneDuring(library.slug, () async {
            links.requestResume(library.slug);
            await links.sync();
          });
          // שורה 0 כוללת שני קישורים; חוזרים לתחילת השורה האחרונה שנשמרה.
          expect(firstDone, saved <= 2 ? 0 : 2);
          expect(indexSnapshot(library.slug), continuous);
          expect(links.incompleteSlugs.value, isEmpty);
          expect(metaSignature(library.slug), isNot(startsWith('!')));
        }
      },
    );

    test('טביעת אצבע שונה — המשך בונה מאפס', () async {
      final path = attachedDb('ext', rows: fourPerLine());
      final library = await attach(path);
      await links.sync();
      final continuous = indexSnapshot(library.slug);

      smallBatches(batchSize: 3);
      await rebuildAndCancel(library.slug);
      touch(path);
      await attached.rescan();

      final firstDone = await firstDoneDuring(library.slug, () async {
        links.requestResume(library.slug);
        await links.sync();
      });
      expect(firstDone, 0);
      expect(indexSnapshot(library.slug), continuous);
      expect(links.incompleteSlugs.value, isEmpty);
    });

    test('requestRebuild אחרי עצירה בונה מאפס', () async {
      final library = await attach(attachedDb('ext', rows: fourPerLine()));
      await links.sync();
      final continuous = indexSnapshot(library.slug);

      smallBatches(batchSize: 3);
      await rebuildAndCancel(library.slug);

      final firstDone = await firstDoneDuring(library.slug, () async {
        links.requestRebuild(library.slug);
        await links.sync();
      });
      expect(firstDone, 0);
      expect(indexSnapshot(library.slug), continuous);
      expect(links.incompleteSlugs.value, isEmpty);
    });

    /// כותב ל-meta את סימון `!building` של [slug] עם [suffix], כמו שהיה נשאר
    /// אחרי קריסה (בלי סיומת) או ניסיון אוטומטי שקדם לה.
    void setBuildingMarker(String slug, String suffix) {
      final base = metaSignature(slug)!.split('\u0001').first;
      final db = sqlite3.sqlite3.open(cachePath());
      db.execute(
        'UPDATE attached_external_link_meta SET targetsSignature = ? '
        'WHERE sourceSlug = ?',
        [base + suffix, slug],
      );
      db.close();
    }

    /// בנייה שנקטעה אחרי מנה ראשונה: אינדקס חלקי ונקודת המשך שמורה.
    Future<({String slug, List<String> full})> interruptedBuild() async {
      final library = await attach(attachedDb('ext', rows: fourPerLine()));
      await links.sync();
      final full = indexSnapshot(library.slug);
      smallBatches(batchSize: 3);
      await rebuildAndCancel(library.slug);
      expect(indexRows(library.slug), inInclusiveRange(1, 3));
      return (slug: library.slug, full: full);
    }

    test('המשך אוטומטי: קריסה (בלי סיומת) עם התקדמות ממשיכה', () async {
      final build = await interruptedBuild();
      setBuildingMarker(build.slug, '');

      expect(await links.sync(autoResume: true), {build.slug});
      expect(indexSnapshot(build.slug), build.full);
      expect(links.incompleteSlugs.value, isEmpty);
    });

    test('המשך אוטומטי: התקדמות מאז הניסיון הקודם ממשיכה', () async {
      final build = await interruptedBuild();
      final previousRows = indexRows(build.slug) - 1;
      setBuildingMarker(build.slug, '\u0001auto=$previousRows');

      expect(await links.sync(autoResume: true), {build.slug});
      expect(indexSnapshot(build.slug), build.full);
    });

    test(
      'המשך אוטומטי: בלי התקדמות (גם קריסה באמצע ניסיון) לא ממשיך',
      () async {
        final build = await interruptedBuild();
        final rows = indexRows(build.slug);
        setBuildingMarker(build.slug, '\u0001auto=$rows');

        expect(await links.sync(autoResume: true), isEmpty);
        expect(links.incompleteSlugs.value, {build.slug});
        expect(indexRows(build.slug), rows);
      },
    );

    test('המשך אוטומטי: עצירה ידנית לא ממשיכה, והמשך ידני כן', () async {
      final build = await interruptedBuild();
      expect(metaSignature(build.slug), contains('\u0001stop'));

      expect(await links.sync(autoResume: true), isEmpty);
      expect(links.incompleteSlugs.value, {build.slug});

      links.requestResume(build.slug);
      await links.sync();
      expect(indexSnapshot(build.slug), build.full);
      expect(links.incompleteSlugs.value, isEmpty);
    });

    test('בלי autoResume אין המשך אוטומטי', () async {
      final build = await interruptedBuild();
      setBuildingMarker(build.slug, '');

      expect(await links.sync(), isEmpty);
      expect(links.incompleteSlugs.value, {build.slug});
    });

    test('מצב חסכוני אינו משנה את התוצאה הסופית', () async {
      final batch = ExternalLinkRepository.insertBatchSize;
      addTearDown(() => ExternalLinkRepository.insertBatchSize = batch);
      ExternalLinkRepository.insertBatchSize = 4;
      final library = await attach(attachedDb('ext', rows: fiveRows()));
      var sawEconomy = false;
      onNextBuild(() {
        links.setBuildEconomy(true);
        sawEconomy = links.buildEconomy.value;
      });

      expect(await links.sync(), {library.slug});
      expect(sawEconomy, isTrue);
      expect(indexRows(library.slug), 5);
      expect(metaSignature(library.slug), isNot(startsWith('!')));
      expect(links.buildEconomy.value, isFalse);
    });

    test('המשך שומר על תקרת שורות המקור גם כשיעד אינו נפתר', () async {
      final cap = ExternalLinkRepository.maxIndexRows;
      addTearDown(() => ExternalLinkRepository.maxIndexRows = cap);
      ExternalLinkRepository.maxIndexRows = 5;
      smallBatches(batchSize: 2);
      final library = await attach(
        attachedDb(
          'resume-cap',
          rows: [
            _row(0, targetTitle: 'חסר', targetLineIndex: 1),
            for (var i = 1; i < 6; i++) _row(i, targetLineIndex: 1),
          ],
        ),
      );
      await links.sync();
      expect(links.tooLargeSlugs.value, contains(library.slug));
      await rebuildAndCancel(library.slug);
      expect(indexRows(library.slug), inInclusiveRange(0, 1));
      expect(links.incompleteSlugs.value, {library.slug});
      links.requestResume(library.slug);
      await links.sync();
      expect(links.tooLargeSlugs.value, contains(library.slug));
      expect(indexRows(library.slug), 0);
    });

    test('סריקת יעדים חסרים מכבדת השהיה, עצירה ומנות חסכוניות', () async {
      smallBatches(batchSize: 4);
      final library = await attach(
        attachedDb(
          'unresolved',
          rows: [
            for (var i = 0; i < 30; i++)
              _row(i, targetTitle: 'חסר', targetLineIndex: 1),
          ],
        ),
      );
      final reported = <int>[];
      void record() {
        final progress = links.buildProgress.value[library.slug];
        if (progress != null && progress.total > 0) reported.add(progress.done);
      }

      onNextBuild(() {
        links.setBuildEconomy(true);
        links.pauseBuild();
      });
      links.buildProgress.addListener(record);
      final first = links.sync();
      try {
        await waitForProgress(library.slug, 1, first);
        expect(reported.last, inInclusiveRange(1, 2));
        expect(links.buildEconomy.value, isTrue);
      } finally {
        links.cancelBuild();
        await first;
        links.buildProgress.removeListener(record);
      }
      expect(links.incompleteSlugs.value, {library.slug});
      expect(indexRows(library.slug), 0);
      expect(metaSignature(library.slug), endsWith('\u0001stop'));
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

class _PdfTabsRepository implements TabsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #loadTabs) return [];
    if (invocation.memberName == #loadCurrentTabIndex) return 0;
    return Future<void>.value();
  }
}

class _PdfSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _PdfSettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

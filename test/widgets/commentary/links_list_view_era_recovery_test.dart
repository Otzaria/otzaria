import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/book.dart';
import 'package:otzaria/migration/models/category.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/utils/text/text_manipulation.dart'
    show isEraTableLoaded;
import 'package:otzaria/widgets/commentary/links_list_view.dart';
import 'package:path/path.dart' as p;

import '../../test_helpers/memory_cache_provider.dart';
import '../../test_helpers/stub_settings_bloc.dart';

List<Link> _links({BookSource source = BookSource.official}) => [
  for (final title in ['ספר א', 'ספר ב'])
    Link(
      heRef: '$title, א',
      index1: 1,
      path2: title,
      index2: 1,
      connectionType: LinkTypes.quotation,
      targetSource: source,
    ),
];

Future<void> _pumpLinks(WidgetTester tester, List<Link> links) async {
  await tester.runAsync(() => CommentaryService.preloadErasForLinks(links));
  final settings = StubSettingsBloc();
  addTearDown(settings.close);
  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider<SettingsBloc>.value(
        value: settings,
        child: Scaffold(
          body: LinksListView(
            links: links,
            chipSourceLinks: links,
            openBookTitle: 'ספר מקור',
            selectedLinkTypes: const {},
            onSelectedLinkTypesChanged: (_) {},
            openBookCallback: (_) {},
            fontSize: 16,
            displayProfile: TextDisplayProfile.defaults,
          ),
        ),
      ),
    ),
  );
  // מטמון המסד המצורף מחזיק Future שנוצר ב-runAsync; משלימים גם את ההמתנה אליו.
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
}

double _top(WidgetTester tester, String title) => tester
    .getTopLeft(
      find.descendant(
        of: find.byType(ExpansionTile),
        matching: find.text(title),
      ),
    )
    .dy;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late String dbPath;
  late String unavailablePath;

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    tempDir = await Directory.systemTemp.createTemp('otzaria-links-era-');
    dbPath = p.join(tempDir.path, 'seforim.db');
    unavailablePath = '$dbPath.unavailable';
    final database = MyDatabase.withPath(dbPath);
    final repository = SeforimRepository(database);
    await repository.ensureInitialized();
    final category = await repository.insertCategory(
      const Category(title: 'ק'),
    );
    final source = await repository.insertSource('s', -1);
    final bookIds = <int>[];
    for (final title in ['ספר א', 'ספר ב']) {
      bookIds.add(
        await repository.insertBook(
          Book(
            id: 0,
            categoryId: category,
            sourceId: source,
            title: title,
            fileType: 'txt',
          ),
        ),
      );
    }
    final raw = await database.database;
    raw.execute(
      "INSERT INTO generation (id, name) VALUES (1, 'ראשונים'), (2, 'אחרונים')",
    );
    raw.execute(
      'INSERT INTO book_generation (bookId, generationId) VALUES (?, 2), (?, 1)',
      bookIds,
    );
    raw.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    raw.execute('PRAGMA journal_mode=DELETE');
    database.close();

    await SqliteDataProvider.instance.dispose();
    await Settings.setValue<String>(
      SettingsRepository.keyDbEffectivePath,
      dbPath,
    );
    await File(dbPath).rename(unavailablePath);
    CommentaryService.clearEraCache();
  });

  tearDown(() async {
    CommentaryService.clearEraCache();
    await SqliteDataProvider.instance.dispose();
    await tempDir.delete(recursive: true);
  });

  for (final preloadElsewhere in [false, true]) {
    testWidgets(
      'הקלדה מתקנת סדר דורות אחרי כשל DB חולף (טעינה מפאנל אחר: $preloadElsewhere)',
      (tester) async {
        final links = _links();
        await _pumpLinks(tester, links);
        expect(isEraTableLoaded, isFalse);
        expect(_top(tester, 'ספר א'), lessThan(_top(tester, 'ספר ב')));
        final version = CommentaryService.eraCacheVersion;

        await tester.runAsync(() async {
          await File(unavailablePath).rename(dbPath);
          await SqliteDataProvider.instance.initialize();
          if (preloadElsewhere) {
            await CommentaryService.preloadErasForLinks(links);
          }
        });
        expect(isEraTableLoaded, preloadElsewhere);
        expect(CommentaryService.eraCacheVersion, version);

        await tester.enterText(find.byType(TextField), 'ספר');
        await tester.pumpAndSettle();

        expect(_top(tester, 'ספר ב'), lessThan(_top(tester, 'ספר א')));
        expect(CommentaryService.eraCacheVersion, version);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('דורות רשמיים טעונים אינם מקבעים מיון של מסד מצורף שטרם נטען', (
    tester,
  ) async {
    final source = BookSource.attached('era-recovery');
    final links = _links(source: source);
    CommentaryService.seedEraCache(const {
      'ספר א': CommentaryEra.rishonim,
      'ספר ב': CommentaryEra.acharonim,
    });
    await _pumpLinks(tester, links);
    expect(isEraTableLoaded, isFalse);
    expect(_top(tester, 'ספר א'), lessThan(_top(tester, 'ספר ב')));
    final version = CommentaryService.eraCacheVersion;

    CommentaryService.seedEraCache({
      '${source.wireKey}\u0000ספר א': CommentaryEra.acharonim,
      '${source.wireKey}\u0000ספר ב': CommentaryEra.rishonim,
    });
    await tester.enterText(find.byType(TextField), 'ספר');
    await tester.pumpAndSettle();

    expect(_top(tester, 'ספר ב'), lessThan(_top(tester, 'ספר א')));
    expect(CommentaryService.eraCacheVersion, version);
    expect(tester.takeException(), isNull);
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/alt_toc_sidebar_view.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:otzaria/widgets/navigation/nav_panel_search.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../../helpers/seforim_fixture_db.dart';
import '../../test_helpers/memory_cache_provider.dart';

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _linklessParent = 'כותרת בלי שורה';
const _linklessChild = 'בן ראשון';
const _linkedParent = 'פרשת בראשית';
const _linkedChild = 'בן של כותרת עם שורה';

/// #2166: לחיצה על שורת כותרת בלי קישור משלה פותחת וסוגרת אותה.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final provider = DatabaseLibraryProvider.instance;
  final previousDataRoot = AppPaths.cachedDataRootPath;
  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    tempDir = await Directory.systemTemp.createTemp('otzaria_alt_linkless');
    final libraryPath = p.join(tempDir.path, 'library');
    Directory(libraryPath).createSync();
    dbPath = p.join(libraryPath, DatabaseConstants.databaseFileName);
    File(
      SeforimFixtureDb.create(
        Directory(libraryPath),
        SeforimFixtureVariant.full,
      ),
    ).renameSync(dbPath);
    // במסד: "פרשת בראשית" (1) עם שורה 1. נוספים בן שלה, ואב בלי שורה עם בן.
    final db = sqlite3.sqlite3.open(dbPath);
    db.execute(
      'INSERT INTO tocText VALUES (3, ?), (4, ?), (5, ?)',
      [_linklessParent, _linklessChild, _linkedChild],
    );
    db.execute('UPDATE alt_toc_entry SET hasChildren = 1 WHERE id = 1');
    db.execute(
      'INSERT INTO alt_toc_entry (id, structureId, parentId, textId, level, '
      'lineId, hasChildren) VALUES '
      '(2, 1, 1, 5, 2, 2, 0), (3, 1, NULL, 3, 1, NULL, 1), '
      '(4, 1, 3, 4, 2, 3, 0)',
    );
    db.execute('INSERT INTO line_alt_toc VALUES (2, 1, 2), (3, 1, 4)');
    db.close();

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
    await provider.sqliteProvider.dispose();
    provider.clearCache();
    LibraryProviderManager.instance.resetForTesting();
    await provider.initialize();
  });

  tearDown(() async {
    LibraryProviderManager.instance.resetForTesting();
    provider.clearCache();
    await provider.sqliteProvider.dispose();
    AppPaths.debugOverrideDataRootPath(previousDataRoot);
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<LineScrollController> pumpSidebar(WidgetTester tester) async {
    final book = TextBook(
      title: SeforimFixtureIds.bereshitTitle,
      categoryId: SeforimFixtureIds.torahCategoryId,
    );
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {BookCompositeKey.fromBook(book)!: provider},
      providers: [provider],
    );
    final bloc = _TestTextBookBloc(_loadedState(book));
    addTearDown(bloc.close);
    final lines = LineScrollController();
    addTearDown(lines.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<TextBookBloc>.value(
            value: bloc,
            child: SizedBox(
              width: 400,
              height: 800,
              child: AltTocSidebarView(
                book: book,
                closeLeftPaneCallback: () {},
                lines: lines,
              ),
            ),
          ),
        ),
      ),
    );
    await _settleRealAsync(tester);
    await tester.pumpAndSettle();
    return lines;
  }

  Future<void> tapRow(WidgetTester tester, String title) async {
    await tester.tap(find.text(title));
    await _settleRealAsync(tester);
    await tester.pumpAndSettle();
  }

  testWidgets('לחיצה על שורת כותרת בלי קישור פותחת וסוגרת אותה', (
    tester,
  ) async {
    final lines = await pumpSidebar(tester);
    expect(find.text(_linklessParent), findsOneWidget);
    expect(find.text(_linklessChild), findsNothing);

    await tapRow(tester, _linklessParent);
    expect(find.text(_linklessChild), findsOneWidget);
    expect(lines.position.value?.topLine, 2);

    await tapRow(tester, _linklessParent);
    expect(find.text(_linklessChild), findsNothing);
  });

  testWidgets('לחיצה על שורת כותרת עם קישור משלה אינה פותחת אותה', (
    tester,
  ) async {
    final lines = await pumpSidebar(tester);
    expect(find.text(_linkedChild), findsNothing);

    await tapRow(tester, _linkedParent);
    expect(find.text(_linkedChild), findsNothing);
    expect(lines.position.value?.topLine, 0);
  });

  for (final hasParentMapping in [true, false]) {
    testWidgets(
      'עוגן האב פותח את הסימן הראשון כשהמיפוי שלו '
      '${hasParentMapping ? "מתחיל בסימן הבא" : "חסר"} (issue #3245)',
      (tester) async {
        const parent = 'הלכות הרשאה';
        const child = 'סימן קכב';
        final db = sqlite3.sqlite3.open(dbPath);
        db.execute('UPDATE tocText SET text = ? WHERE id = 2', [parent]);
        db.execute('UPDATE tocText SET text = ? WHERE id = 5', [child]);
        // תחילת האב שייכת לבן הראשון; המיפוי הישיר לאב מתחיל בסימן הבא.
        db.execute('UPDATE alt_toc_entry SET lineId = 1 WHERE id = 2');
        db.execute('DELETE FROM line_alt_toc WHERE lineId IN (1, 2)');
        db.execute('INSERT INTO line_alt_toc VALUES (1, 1, 2)');
        if (hasParentMapping) {
          db.execute('INSERT INTO line_alt_toc VALUES (2, 1, 1)');
        }
        db.close();

        final lines = await pumpSidebar(tester);
        await tapRow(tester, parent);
        expect(lines.position.value?.topLine, 0);

        await tapRow(tester, child);
        expect(lines.position.value?.topLine, 0);
      },
    );
  }

  void configureLaterParentAnchor(String childTarget) {
    final db = sqlite3.sqlite3.open(dbPath);
    db.execute("UPDATE alt_toc_structure SET key = 'Essay' WHERE id = 1");
    db.execute('UPDATE alt_toc_entry SET lineId = 3 WHERE id = 3');
    db.execute('UPDATE alt_toc_entry SET lineId = ? WHERE id = 4', [
      childTarget == 'anchor' ? 2 : (childTarget == 'orphan' ? 999 : null),
    ]);
    db.execute('DELETE FROM line_alt_toc WHERE lineId IN (2, 3)');
    if (childTarget == 'grandchild') {
      db.execute('INSERT INTO tocText VALUES (6, ?)', ['נכד ראשון']);
      db.execute('UPDATE alt_toc_entry SET hasChildren = 1 WHERE id = 4');
      db.execute(
        'INSERT INTO alt_toc_entry (id, structureId, parentId, textId, level, '
        'lineId) VALUES (5, 1, 4, 6, 3, 2)',
      );
      db.execute('INSERT INTO line_alt_toc VALUES (2, 1, 5)');
    } else {
      db.execute('INSERT INTO line_alt_toc VALUES (2, 1, 4)');
    }
    db.close();
  }

  for (final childTarget in ['anchor', 'mapping', 'grandchild', 'orphan']) {
    testWidgets('עוגן אב מאוחר אינו מדלג על פתיחת הבן הראשון: $childTarget', (
      tester,
    ) async {
      configureLaterParentAnchor(childTarget);
      final lines = await pumpSidebar(tester);
      expect(find.text(_linklessChild), findsNothing);

      await tapRow(tester, _linklessParent);
      expect(lines.position.value?.topLine, 1);
      expect(find.text(_linklessChild), findsOneWidget);
      final selected = tester
          .widgetList<NavTreeTile>(find.byType(NavTreeTile))
          .where((tile) => tile.isSelected)
          .map((tile) => tile.title);
      expect(
        selected,
        childTarget == 'grandchild' ? isEmpty : equals([_linklessChild]),
      );

      final navigationEpoch = lines.navigationEpoch.value;
      await tapRow(tester, _linklessParent);
      expect(find.text(_linklessChild), findsNothing);
      expect(lines.position.value?.topLine, 1);
      expect(lines.navigationEpoch.value, navigationEpoch);
    });
  }

  testWidgets('חיפוש כותרת עם עוגן מאוחר מנווט לפתיחת הבן הראשון', (
    tester,
  ) async {
    configureLaterParentAnchor('anchor');
    final lines = await pumpSidebar(tester);
    await tester.tap(find.byType(NavPanelSearchToggle));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), _linklessParent);
    await _settleRealAsync(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(NavTreeTile, _linklessParent));
    await _settleRealAsync(tester);
    await tester.pumpAndSettle();
    expect(lines.position.value?.topLine, 1);
  });

  testWidgets('עוגן אב מוקדם נשמר גם כשאין מיפוי ישיר לאב', (tester) async {
    final db = sqlite3.sqlite3.open(dbPath);
    db.execute("UPDATE alt_toc_structure SET key = 'Essay' WHERE id = 1");
    db.execute('UPDATE alt_toc_entry SET lineId = 2 WHERE id = 3');
    db.close();

    final lines = await pumpSidebar(tester);
    await tapRow(tester, _linklessParent);
    expect(lines.position.value?.topLine, 1);
    expect(find.text(_linklessChild), findsNothing);
  });

  testWidgets('בן מאוחר בסדר העץ אינו מחליף את תחילת האב', (tester) async {
    final db = sqlite3.sqlite3.open(dbPath);
    db.execute("UPDATE alt_toc_structure SET key = 'Essay' WHERE id = 1");
    db.execute('UPDATE alt_toc_entry SET lineId = 2 WHERE id = 3');
    db.execute('INSERT INTO tocText VALUES (6, ?)', ['בן שני']);
    db.execute(
      'INSERT INTO alt_toc_entry (id, structureId, parentId, textId, level, '
      'lineId) VALUES (5, 1, 3, 6, 2, 1)',
    );
    db.close();

    final lines = await pumpSidebar(tester);
    await tapRow(tester, _linklessParent);
    expect(lines.position.value?.topLine, 1);
    expect(find.text(_linklessChild), findsNothing);
  });

  testWidgets('עוגנים בספרים שונים אינם מושווים לפי מספר שורה', (tester) async {
    final db = sqlite3.sqlite3.open(dbPath);
    db.execute("UPDATE alt_toc_structure SET key = 'Essay' WHERE id = 1");
    db.execute('UPDATE alt_toc_entry SET lineId = 3 WHERE id = 3');
    db.execute('UPDATE alt_toc_entry SET lineId = 4 WHERE id = 4');
    db.close();

    final lines = await pumpSidebar(tester);
    await tapRow(tester, _linklessParent);
    expect(lines.position.value?.topLine, 2);
    expect(find.text(_linklessChild), findsNothing);
  });

  for (final lineId in [null, 999]) {
    testWidgets(
      'כותרת בלי עוגן ${lineId == null ? "מפורש" : "תקף"} מנווטת לפי המיפוי',
      (tester) async {
        final db = sqlite3.sqlite3.open(dbPath);
        db.execute('UPDATE alt_toc_entry SET lineId = ? WHERE id = 1', [
          lineId,
        ]);
        db.execute('DELETE FROM line_alt_toc WHERE lineId = 1');
        db.execute(
          'UPDATE line_alt_toc SET altTocEntryId = 1 WHERE lineId = 2',
        );
        db.close();

        final lines = await pumpSidebar(tester);
        await tapRow(tester, _linkedParent);
        expect(lines.position.value?.topLine, 1);
        expect(find.text(_linkedChild), findsNothing);
      },
    );
  }

  testWidgets('לחיצה על שורת המבנה סוגרת ופותחת אותו', (tester) async {
    await pumpSidebar(tester);
    expect(find.text(_linkedParent), findsOneWidget);

    await tapRow(tester, 'פרשה');
    expect(find.text(_linkedParent), findsNothing);

    await tapRow(tester, 'פרשה');
    expect(find.text(_linkedParent), findsOneWidget);
  });
}

/// שאילתות המסד רצות ב-isolate וזקוקות לזמן אמיתי, בזו אחר זו.
Future<void> _settleRealAsync(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
  }
}

TextBookLoaded _loadedState(TextBook book) {
  return TextBookLoaded(
    book: book,
    showLeftPane: true,
    content: const ['בראשית א', 'שורה ב', 'שורה ג'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    visibleLinks: const [],
    linksByLine: const {},
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0],
    selectedIndex: 0,
    pinLeftPane: false,
    searchText: '',
  );
}

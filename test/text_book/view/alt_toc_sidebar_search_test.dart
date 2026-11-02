import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
import 'package:otzaria/text_book/view/alt_toc_sidebar_view.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:otzaria/widgets/navigation/nav_panel_search.dart';
import 'package:path/path.dart' as p;

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

class _RecordingLines extends LineScrollController {
  final List<int> requested = [];

  @override
  Future<void> scrollToLine(
    int line, {
    double alignment = kReadingAnchorAlignment,
    double intraLineFraction = 0,
    Duration duration = const Duration(milliseconds: 250),
    Curve curve = Curves.ease,
    bool rememberPosition = true,
  }) async {
    requested.add(line);
  }
}

/// איתור בלשונית 'כותרות' על שני מבנים: "פרשה" מהמסד ו"דיבורי המתחיל".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final provider = DatabaseLibraryProvider.instance;
  final previousDataRoot = AppPaths.cachedDataRootPath;
  late Directory tempDir;

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    tempDir = await Directory.systemTemp.createTemp('otzaria_alt_search');
    final libraryPath = p.join(tempDir.path, 'library');
    Directory(libraryPath).createSync();
    File(
      SeforimFixtureDb.create(
        Directory(libraryPath),
        SeforimFixtureVariant.full,
      ),
    ).renameSync(p.join(libraryPath, DatabaseConstants.databaseFileName));

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

  Future<_RecordingLines> pumpSidebar(
    WidgetTester tester, {
    Map<int, String> dibburim = const {1: 'בראשית ברא', 2: 'בראשית רבה'},
  }) async {
    final book = TextBook(
      title: SeforimFixtureIds.bereshitTitle,
      categoryId: SeforimFixtureIds.torahCategoryId,
    );
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {BookCompositeKey.fromBook(book)!: provider},
      providers: [provider],
    );
    final toc = [TocEntry(text: 'פרק א', index: 0, level: 1)];
    final bloc = _TestTextBookBloc(_loadedState(book, toc));
    addTearDown(bloc.close);
    final lines = _RecordingLines();

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
                dibburim: dibburim,
                tableOfContents: toc,
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

  List<String> resultTitles(WidgetTester tester) => tester
      .widgetList<NavTreeTile>(find.byType(NavTreeTile))
      .map((t) => t.title)
      .toList();

  String? highlighted(WidgetTester tester) => tester
      .widgetList<NavTreeTile>(find.byType(NavTreeTile))
      .where((t) => t.isSelected)
      .map((t) => t.title)
      .singleOrNull;

  Future<void> search(WidgetTester tester, String query) async {
    if (find.byType(TextField).evaluate().isEmpty) {
      await tester.tap(find.byType(NavPanelSearchToggle));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.enterText(find.byType(TextField), query);
    await _settleRealAsync(tester);
    await tester.pumpAndSettle();
  }

  testWidgets('החיצים ואנטר עוברים על התוצאות משני המבנים', (tester) async {
    final lines = await pumpSidebar(tester);
    await search(tester, 'בראשית');
    expect(resultTitles(tester), [
      'פרשת בראשית',
      'בראשית ברא',
      'בראשית רבה',
    ]);

    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }

    await press(LogicalKeyboardKey.arrowDown);
    expect(highlighted(tester), 'פרשת בראשית');
    await press(LogicalKeyboardKey.arrowDown);
    await press(LogicalKeyboardKey.arrowDown);
    expect(highlighted(tester), 'בראשית רבה');
    await press(LogicalKeyboardKey.arrowDown);
    expect(highlighted(tester), 'בראשית רבה', reason: 'נעצר בתוצאה האחרונה');
    await press(LogicalKeyboardKey.arrowUp);
    expect(highlighted(tester), 'בראשית ברא');

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(lines.requested, [1]);

    await search(tester, 'בראשית ר');
    expect(resultTitles(tester), ['בראשית רבה']);
  });

  testWidgets('החלפת הדיבורים בזמן חיפוש אינה משאירה תוצאות מהקודמים', (
    tester,
  ) async {
    await pumpSidebar(tester);
    await search(tester, 'בראשית');
    expect(find.text('בראשית ברא'), findsOneWidget);

    // אותה שאילתה ונתונים אחרים: דיבור שאינו קיים עוד לא יישאר בתוצאות.
    await pumpSidebar(tester, dibburim: const {2: 'בראשית רבה'});
    expect(find.text('בראשית ברא'), findsNothing);
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

TextBookLoaded _loadedState(TextBook book, List<TocEntry> toc) {
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
    tableOfContents: toc,
    removeNikud: false,
    visibleIndices: const [],
    selectedIndex: null,
    pinLeftPane: false,
    searchText: '',
  );
}

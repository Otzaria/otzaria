import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/alt_toc_sidebar_view.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';
import 'package:otzaria/text_display/models/text_display_policy.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' show HolyNameStyle;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../../helpers/seforim_fixture_db.dart';
import '../../test_helpers/memory_cache_provider.dart';

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  void emitState(TextBookState state) => emit(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// #4204: כשיש כמה מבנים, שבבים מראים את כולם ומוצג מבנה אחד בכל פעם.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final provider = DatabaseLibraryProvider.instance;
  final previousDataRoot = AppPaths.cachedDataRootPath;
  late Directory tempDir;

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    tempDir = await Directory.systemTemp.createTemp('otzaria_alt_chips');
    final libraryPath = p.join(tempDir.path, 'library');
    Directory(libraryPath).createSync();
    final dbPath = p.join(libraryPath, DatabaseConstants.databaseFileName);
    File(
      SeforimFixtureDb.create(
        Directory(libraryPath),
        SeforimFixtureVariant.full,
      ),
    ).renameSync(dbPath);
    // במסד: מבנה "פרשה" עם "פרשת בראשית". נוסף מבנה שני, "פרקים", עם שני פרקים.
    final db = sqlite3.sqlite3.open(dbPath);
    final bookId = db
        .select('SELECT bookId FROM alt_toc_structure')
        .first
        .values
        .first;
    db.execute(
      "INSERT INTO alt_toc_structure VALUES (2, ?, 'Chapters', 'Chapters', "
      "'פרקים')",
      [bookId],
    );
    db.execute(
      "INSERT INTO tocText VALUES (20, 'פרק ראשון'), (21, 'פרק שני'), "
      "(22, 'שירת יהוה')",
    );
    db.execute(
      'INSERT INTO alt_toc_entry (id, structureId, parentId, textId, level, '
      'lineId, hasChildren) VALUES (20, 2, NULL, 20, 1, 1, 0), '
      '(21, 2, NULL, 21, 1, 2, 0), (22, 2, NULL, 22, 1, 3, 0)',
    );
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

  Future<_TestTextBookBloc> pumpSidebar(
    WidgetTester tester, {
    List<TocEntry> toc = const [],
    Map<int, String> dibburim = const {},
    _TestTextBookBloc? existingBloc,
    bool settle = true,
  }) async {
    final book = TextBook(
      title: SeforimFixtureIds.bereshitTitle,
      categoryId: SeforimFixtureIds.torahCategoryId,
    );
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {BookCompositeKey.fromBook(book)!: provider},
      providers: [provider],
    );
    final bloc = existingBloc ?? _TestTextBookBloc(_loadedState(book));
    if (existingBloc == null) addTearDown(bloc.close);
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
                tableOfContents: toc,
                dibburim: dibburim,
                closeLeftPaneCallback: () {},
                lines: lines,
              ),
            ),
          ),
        ),
      ),
    );
    if (settle) {
      await _settleRealAsync(tester);
      await tester.pumpAndSettle();
    }
    return bloc;
  }

  bool chipSelected(WidgetTester tester, String title) => tester
      .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, title))
      .selected;

  for (final refreshToc in [false, true]) {
    testWidgets(
      'דיבורים נבחרים נשארים אחרי רענון ${refreshToc ? "כותרות" : "דיבורים"}',
      (tester) async {
        var toc = [TocEntry(text: 'כותרת', index: 0, level: 1)];
        var dibburim = {1: 'דיבור קיים'};
        final bloc = await pumpSidebar(tester, toc: toc, dibburim: dibburim);
        await tester.tap(find.widgetWithText(ChoiceChip, 'דיבורי המתחיל'));
        await tester.pumpAndSettle();
        expect(find.text('דיבור קיים'), findsOneWidget);
        for (var i = 0; i < 3; i++) {
          if (refreshToc) {
            toc = [TocEntry(text: 'כותרת', index: 0, level: 1)];
          } else {
            dibburim = {1: 'דיבור קיים'};
          }
          await pumpSidebar(
            tester,
            toc: toc,
            dibburim: dibburim,
            existingBloc: bloc,
          );
          expect(chipSelected(tester, 'דיבורי המתחיל'), isTrue);
          expect(find.text('דיבור קיים'), findsOneWidget);
          await tester.tap(find.widgetWithText(ChoiceChip, 'דיבורי המתחיל'));
          await tester.pumpAndSettle();
          expect(find.text('דיבור קיים'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets('רענון דיבורים שומר הרחבה וסימון ומציג את הקלט החדש', (
    tester,
  ) async {
    List<TocEntry> toc() => [
      TocEntry(text: 'פרק א', index: 0, level: 1),
      TocEntry(text: 'פרק ב', index: 2, level: 1),
    ];
    final bloc = await pumpSidebar(
      tester,
      toc: toc(),
      dibburim: {1: 'דיבור ישן', 3: 'דיבור שני'},
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'דיבורי המתחיל'));
    await tester.pumpAndSettle();
    final chapter = find.byWidgetPredicate(
      (w) => w is NavTreeTile && w.title == 'פרק א',
    );
    await tester.tap(
      find.descendant(of: chapter, matching: find.byType(IconButton)),
    );
    bloc.emitState((bloc.state as TextBookLoaded).copyWith(selectedIndex: 1));
    await _settleRealAsync(tester);
    await tester.pumpAndSettle();
    expect(find.text('דיבור ישן'), findsOneWidget);
    await pumpSidebar(
      tester,
      toc: toc(),
      dibburim: {1: 'דיבור חדש', 3: 'דיבור שני'},
      existingBloc: bloc,
    );
    expect(find.text('דיבור ישן'), findsNothing);
    expect(find.text('דיבור חדש'), findsOneWidget);
    expect(tester.widget<NavTreeTile>(chapter).isExpanded, isTrue);
    final selected = tester
        .widgetList<NavTreeTile>(find.byType(NavTreeTile))
        .where((w) => w.isSelected);
    expect(selected.single.title, 'דיבור חדש');
    expect(find.text('דיבור שני'), findsNothing);
  });

  testWidgets(
    'רענון בזמן טעינה, הסרה והוספה מחדש מציגים רק את הדיבורים החדשים',
    (tester) async {
      final toc = [TocEntry(text: 'כותרת', index: 0, level: 1)];
      final bloc = await pumpSidebar(
        tester,
        toc: toc,
        dibburim: {1: 'דיבור ישן'},
        settle: false,
      );
      await pumpSidebar(
        tester,
        toc: toc,
        dibburim: {1: 'דיבור ראשון'},
        existingBloc: bloc,
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'דיבורי המתחיל'));
      await tester.pumpAndSettle();
      expect(find.text('דיבור ראשון'), findsOneWidget);
      await pumpSidebar(tester, toc: toc, existingBloc: bloc);
      expect(find.widgetWithText(ChoiceChip, 'דיבורי המתחיל'), findsNothing);
      await pumpSidebar(
        tester,
        toc: toc,
        dibburim: {1: 'דיבור אחרון'},
        existingBloc: bloc,
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'דיבורי המתחיל'));
      await tester.pumpAndSettle();
      expect(find.text('דיבור אחרון'), findsOneWidget);
      expect(find.text('דיבור ראשון'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('דיבורים מתרעננים ברקע בלי להחליף את המבנה שהמשתמש בחר', (
    tester,
  ) async {
    final toc = [TocEntry(text: 'כותרת', index: 0, level: 1)];
    final bloc = await pumpSidebar(
      tester,
      toc: toc,
      dibburim: {1: 'דיבור ישן'},
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'דיבורי המתחיל'));
    await tester.pumpAndSettle();
    expect(find.text('דיבור ישן'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'פרקים'));
    await pumpSidebar(
      tester,
      toc: toc,
      dibburim: {1: 'דיבור חדש'},
      existingBloc: bloc,
    );
    expect(chipSelected(tester, 'פרקים'), isTrue);
    expect(find.text('פרק ראשון'), findsOneWidget);
    expect(find.text('דיבור חדש'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'דיבורי המתחיל'));
    await tester.pumpAndSettle();
    expect(find.text('דיבור חדש'), findsOneWidget);
    expect(find.text('דיבור ישן'), findsNothing);
  });

  testWidgets('רענונים רצופים בזמן מעקב מיקום אינם מחזירים נתונים ישנים', (
    tester,
  ) async {
    final toc = [TocEntry(text: 'כותרת', index: 0, level: 1)];
    final bloc = await pumpSidebar(
      tester,
      toc: toc,
      dibburim: {1: 'דיבור ישן'},
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'דיבורי המתחיל'));
    await tester.pumpAndSettle();
    expect(find.text('דיבור ישן'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await pumpSidebar(
        tester,
        toc: toc,
        dibburim: {1: 'דיבור חדש $i'},
        existingBloc: bloc,
        settle: false,
      );
    }
    await _settleRealAsync(tester);
    await tester.pumpAndSettle();
    expect(find.text('דיבור חדש 2'), findsOneWidget);
    expect(find.text('דיבור ישן'), findsNothing);
    expect(chipSelected(tester, 'דיבורי המתחיל'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('שבב שהמשתמש בחר נשאר כשמיקום הקריאה משתנה', (tester) async {
    final bloc = await pumpSidebar(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'פרקים'));
    await _settleRealAsync(tester);
    await tester.pumpAndSettle();

    // השורה הבאה שייכת ל"פרשה" במסד; המבנה הנבחר לא מתחלף מעצמו.
    final state = bloc.state as TextBookLoaded;
    bloc.emitState(state.copyWith(visibleIndices: const [1]));
    await tester.pump(const Duration(milliseconds: 400));
    await _settleRealAsync(tester);
    await tester.pumpAndSettle();
    expect(chipSelected(tester, 'פרקים'), isTrue);
    expect(find.text('פרק ראשון'), findsOneWidget);
  });

  testWidgets('שבב לכל מבנה, והמבנה שנבחר הוא היחיד שמוצג', (tester) async {
    await pumpSidebar(tester);
    expect(find.widgetWithText(ChoiceChip, 'פרשה'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'פרקים'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'פרשה'))
          .selected,
      isTrue,
    );
    expect(find.text('פרשת בראשית'), findsOneWidget);
    expect(find.text('פרק ראשון'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'פרקים'));
    await _settleRealAsync(tester);
    await tester.pumpAndSettle();
    expect(find.text('פרק ראשון'), findsOneWidget);
    expect(find.text('פרק שני'), findsOneWidget);
    expect(find.text('פרשת בראשית'), findsNothing);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'פרקים'))
          .selected,
      isTrue,
    );
  });

  testWidgets('הסתרת שם השם חלה גם על הכותרות החלופיות (#3543)', (
    tester,
  ) async {
    TextDisplayPolicy policy(bool replace) => TextDisplayPolicy.fromLegacy(
      defaultRemoveNikud: false,
      removeNikudFromTanach: false,
      defaultRemovePunctuation: false,
      showTeamim: true,
      replaceHolyNames: replace,
      holyNameStyle: HolyNameStyle.kufKuf,
    );
    final bloc = await pumpSidebar(tester);
    final loaded = bloc.state as TextBookLoaded;
    bloc.emitState(loaded.copyWith(displayPolicy: policy(false)));
    await tester.tap(find.widgetWithText(ChoiceChip, 'פרקים'));
    await _settleRealAsync(tester);
    await tester.pumpAndSettle();
    expect(find.text('שירת יהוה'), findsOneWidget);

    // שינוי ההגדרה בזמן שהספר פתוח מתעדכן גם ברשימה שכבר נבנתה.
    bloc.emitState(loaded.copyWith(displayPolicy: policy(true)));
    await tester.pumpAndSettle();
    expect(find.text('שירת יהוה'), findsNothing);
    expect(find.text('שירת יקוק'), findsOneWidget);
  });
}

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

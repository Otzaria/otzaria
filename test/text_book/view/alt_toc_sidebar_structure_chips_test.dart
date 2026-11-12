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
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/alt_toc_sidebar_view.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';
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
    db.execute("INSERT INTO tocText VALUES (20, 'פרק ראשון'), (21, 'פרק שני')");
    db.execute(
      'INSERT INTO alt_toc_entry (id, structureId, parentId, textId, level, '
      'lineId, hasChildren) VALUES (20, 2, NULL, 20, 1, 1, 0), '
      '(21, 2, NULL, 21, 1, 2, 0)',
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

  Future<_TestTextBookBloc> pumpSidebar(WidgetTester tester) async {
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
    return bloc;
  }

  bool chipSelected(WidgetTester tester, String title) => tester
      .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, title))
      .selected;

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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/alt_toc_sidebar_view.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
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
  final TextBookRepository repository = TextBookRepository(
    fileSystem: FileSystemData.instance,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _parent = 'דף ח:';
const _firstChild = 'דף ח: – רי"ף דף ג:';
const _secondChild = 'דף ח: – רי"ף דף ד:';
const _nextPage = 'דף ט.';
const _sharedLine = 'א (דף ח:) ב (דף ט.) ג';

/// #5506: אב, בנו הראשון ודף אחר נפתחים באותה פסקה, והשורה ממופה במסד לאחד מהם.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final provider = DatabaseLibraryProvider.instance;
  final previousDataRoot = AppPaths.cachedDataRootPath;
  late Directory tempDir;

  Future<void> setUpDb({
    required bool mapsToNextPage,
    String structureKey = 'GemaraDapim',
  }) async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    tempDir = await Directory.systemTemp.createTemp('otzaria_gemara_dapim');
    final libraryPath = p.join(tempDir.path, 'library');
    Directory(libraryPath).createSync();
    final dbPath = p.join(libraryPath, DatabaseConstants.databaseFileName);
    File(
      SeforimFixtureDb.create(
        Directory(libraryPath),
        SeforimFixtureVariant.full,
      ),
    ).renameSync(dbPath);
    final db = sqlite3.sqlite3.open(dbPath);
    db.execute('UPDATE alt_toc_structure SET key = ? WHERE id = 1', [
      structureKey,
    ]);
    db.execute('INSERT INTO tocText VALUES (3, ?), (4, ?), (5, ?), (6, ?)', [
      _parent,
      _firstChild,
      _secondChild,
      _nextPage,
    ]);
    db.execute(
      'INSERT INTO alt_toc_entry (id, structureId, parentId, textId, level, '
      'lineId, hasChildren) VALUES (2, 1, NULL, 3, 1, 2, 1), '
      '(3, 1, 2, 4, 2, 2, 0), (4, 1, 2, 5, 2, 3, 0), (5, 1, NULL, 6, 1, 2, 0)',
    );
    db.execute('INSERT INTO line_alt_toc VALUES (2, 1, ?), (3, 1, 4)', [
      mapsToNextPage ? 5 : 3,
    ]);
    db.execute('UPDATE line SET content = ? WHERE id = 2', [_sharedLine]);
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
  }

  tearDown(() async {
    LibraryProviderManager.instance.resetForTesting();
    provider.clearCache();
    await provider.sqliteProvider.dispose();
    AppPaths.debugOverrideDataRootPath(previousDataRoot);
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Finder tileOf(String title) =>
      find.ancestor(of: find.text(title), matching: find.byType(NavTreeTile));
  List<String> selected(WidgetTester tester) => [
    for (final title in [_parent, _firstChild, _secondChild, _nextPage])
      if (find.text(title).evaluate().isNotEmpty &&
          tester.widget<NavTreeTile>(tileOf(title)).isSelected)
        title,
  ];

  Future<_TestTextBookBloc> pumpSidebar(WidgetTester tester) async {
    final book = TextBook(
      title: SeforimFixtureIds.bereshitTitle,
      categoryId: SeforimFixtureIds.torahCategoryId,
    );
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {BookCompositeKey.fromBook(book)!: provider},
      providers: [provider],
    );
    final bloc = _TestTextBookBloc(_loadedState(book, visibleLine: 0));
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

  Future<void> readerAt(
    WidgetTester tester,
    _TestTextBookBloc bloc,
    int line,
  ) async {
    final book = (bloc.state as TextBookLoaded).book;
    // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
    bloc.emit(_loadedState(book, visibleLine: line));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await _settleRealAsync(tester);
    await tester.pumpAndSettle();
  }

  for (final mapsToNextPage in [false, true]) {
    final mapping = mapsToNextPage ? 'לדף הבא' : 'לבן הראשון';
    for (final clicked in [_parent, _firstChild, _nextPage]) {
      testWidgets('שורה ממופה $mapping: "$clicked" נשאר מסומן עד מעבר שורה', (
        tester,
      ) async {
        await tester.runAsync(() => setUpDb(mapsToNextPage: mapsToNextPage));
        final bloc = await pumpSidebar(tester);
        if (clicked == _firstChild) {
          await tester.tap(
            find.descendant(
              of: tileOf(_parent),
              matching: find.byType(IconButton),
            ),
          );
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text(clicked));
        await _settleRealAsync(tester);

        await readerAt(tester, bloc, 1);
        expect(selected(tester), [clicked]);

        await readerAt(tester, bloc, 2);
        expect(selected(tester), [_secondChild]);
      });
    }
  }
  testWidgets('לחיצה על כותרת אב במבנה רגיל חושפת את הבן הממופה', (
    tester,
  ) async {
    await tester.runAsync(
      () => setUpDb(mapsToNextPage: false, structureKey: 'Book'),
    );
    final bloc = await pumpSidebar(tester);
    expect(find.text(_firstChild), findsNothing);
    await tester.tap(find.text(_parent));
    await _settleRealAsync(tester);
    await readerAt(tester, bloc, 1);
    expect(selected(tester), [_firstChild]);
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

TextBookLoaded _loadedState(TextBook book, {required int visibleLine}) {
  return TextBookLoaded(
    book: book,
    showLeftPane: true,
    content: const ['בראשית א', _sharedLine, 'שורה ג'],
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
    visibleIndices: [visibleLine],
    selectedIndex: null,
    pinLeftPane: false,
    searchText: '',
  );
}

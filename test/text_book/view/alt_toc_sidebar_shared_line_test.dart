import 'dart:async';
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
  final _CountingRepository repository = _CountingRepository();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CountingRepository extends TextBookRepository {
  _CountingRepository() : super(fileSystem: FileSystemData.instance);

  final requestedRanges = <(int, int)>[];
  Completer<BookContentRange?>? pendingRange;

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
    int? maxChars,
  }) {
    requestedRanges.add((startLine, endLine));
    if (pendingRange != null) return pendingRange!.future;
    return super.getBookContentRange(
      book,
      startLine: startLine,
      endLine: endLine,
    );
  }
}

const _firstPage = 'דף ו';
const _lastPage = 'דף ז';
const _sharedLine = 'א [דף ו טור א] ב [דף ז טור א] ג';

/// #3181: כמה דפים פותחים באותה פסקה, והשורה ממופה במסד לאחרון שבהם.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final provider = DatabaseLibraryProvider.instance;
  final previousDataRoot = AppPaths.cachedDataRootPath;
  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    tempDir = await Directory.systemTemp.createTemp('otzaria_alt_shared');
    final libraryPath = p.join(tempDir.path, 'library');
    Directory(libraryPath).createSync();
    dbPath = p.join(libraryPath, DatabaseConstants.databaseFileName);
    File(
      SeforimFixtureDb.create(
        Directory(libraryPath),
        SeforimFixtureVariant.full,
      ),
    ).renameSync(dbPath);
    // שני דפים אחים על שורה 2, ו-line_alt_toc ממפה אותה לאחרון — כמו המחולל.
    final db = sqlite3.sqlite3.open(dbPath);
    db.execute("UPDATE alt_toc_structure SET key = 'Dapim' WHERE id = 1");
    db.execute('INSERT INTO tocText VALUES (3, ?), (4, ?)', [
      _firstPage,
      _lastPage,
    ]);
    db.execute(
      'INSERT INTO alt_toc_entry (id, structureId, parentId, textId, level, '
      'lineId, hasChildren) VALUES (2, 1, NULL, 3, 1, 2, 0), '
      '(3, 1, NULL, 4, 1, 2, 0)',
    );
    db.execute('INSERT INTO line_alt_toc VALUES (2, 1, 3), (3, 1, 3)');
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

  bool isSelected(WidgetTester tester, String title) => tester
      .widget<NavTreeTile>(
        find.ancestor(of: find.text(title), matching: find.byType(NavTreeTile)),
      )
      .isSelected;

  Future<void> pumpSidebar(
    WidgetTester tester,
    TextBook book,
    _TestTextBookBloc bloc,
    LineScrollController lines,
  ) async {
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
  }

  testWidgets('הדף שנלחץ נשאר מסומן כשהגלילה מגיעה לשורה המשותפת', (
    tester,
  ) async {
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

    await pumpSidebar(tester, book, bloc, LineScrollController());

    await tester.tap(find.text(_firstPage));
    await _settleRealAsync(tester);
    // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
    bloc.emit(_loadedState(book, visibleLine: 1));
    await tester.pump(const Duration(milliseconds: 350));
    await _settleRealAsync(tester);
    await tester.pumpAndSettle();

    expect(isSelected(tester, _firstPage), isTrue);
    expect(isSelected(tester, _lastPage), isFalse);

    // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
    bloc.emit(_loadedState(book, visibleLine: 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await _settleRealAsync(tester);
    await tester.pumpAndSettle();
    expect(isSelected(tester, _lastPage), isTrue);
    expect(isSelected(tester, _firstPage), isFalse);
  });
  for (final loaded in [true, false]) {
    for (final hasMarker in [true, false]) {
      testWidgets(
        'ניווט ${hasMarker ? "לסמן" : "בלי סמן"} בשורה ${loaded ? "טעונה" : "שטרם נטענה"}',
        (
          tester,
        ) async {
          final book = TextBook(
            title: SeforimFixtureIds.bereshitTitle,
            categoryId: SeforimFixtureIds.torahCategoryId,
          );
          LibraryProviderManager.instance.seedMappingsForTesting(
            mapping: {BookCompositeKey.fromBook(book)!: provider},
            providers: [provider],
          );
          final text = hasMarker ? _sharedLine : 'טקסט ללא סמן';
          final db = sqlite3.sqlite3.open(dbPath);
          db.execute('UPDATE line SET content = ? WHERE id = 2', [text]);
          db.close();
          final bloc = _TestTextBookBloc(
            _loadedState(book, visibleLine: 0).copyWith(
              content: ['בראשית א', loaded ? text : '', 'שורה ג'],
              loadedLineFlags: [true, loaded, true],
            ),
          );
          addTearDown(bloc.close);
          final lines = LineScrollController();
          addTearDown(lines.dispose);
          await pumpSidebar(tester, book, bloc, lines);

          await tester.tap(find.text(_firstPage));
          await _settleRealAsync(tester);
          expect(lines.position.value!.topLine, 1);
          expect(
            lines.position.value!.intraLineFraction,
            closeTo(hasMarker ? text.indexOf('[') / text.length : 0, 0.000001),
          );
          expect(bloc.repository.requestedRanges, loaded ? isEmpty : [(1, 1)]);
        },
      );
    }
  }
  for (final externalNavigation in [false, true]) {
    testWidgets(
      'טעינת סמן אינה דורסת ניווט מאוחר ${externalNavigation ? "בקורא" : "בכותרות"}',
      (tester) async {
        final book = TextBook(
          title: SeforimFixtureIds.bereshitTitle,
          categoryId: SeforimFixtureIds.torahCategoryId,
        );
        LibraryProviderManager.instance.seedMappingsForTesting(
          mapping: {BookCompositeKey.fromBook(book)!: provider},
          providers: [provider],
        );
        final bloc = _TestTextBookBloc(
          _loadedState(book, visibleLine: 0).copyWith(
            content: ['בראשית א', '', 'שורה ג'],
            loadedLineFlags: [true, false, true],
          ),
        );
        addTearDown(bloc.close);
        final pending = Completer<BookContentRange?>();
        bloc.repository.pendingRange = pending;
        final lines = LineScrollController();
        addTearDown(lines.dispose);
        await pumpSidebar(tester, book, bloc, lines);
        await tester.tap(find.text(_firstPage));
        await _settleRealAsync(tester);
        expect(bloc.repository.requestedRanges, [(1, 1)]);

        if (externalNavigation) {
          await lines.scrollToLine(2);
        } else {
          await tester.tap(find.text(_lastPage));
          await _settleRealAsync(tester);
          expect(bloc.repository.requestedRanges, [(1, 1), (1, 1)]);
        }
        pending.complete(
          const BookContentRange(
            startLine: 1,
            endLine: 1,
            totalLines: 3,
            lines: [_sharedLine],
          ),
        );
        await _settleRealAsync(tester);
        expect(lines.position.value!.topLine, externalNavigation ? 2 : 1);
        expect(
          lines.position.value!.intraLineFraction,
          closeTo(
            externalNavigation
                ? 0
                : _sharedLine.indexOf('[דף ז') / _sharedLine.length,
            0.000001,
          ),
        );
      },
    );
  }
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

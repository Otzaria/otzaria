import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/personal_notes/personal_notes_system.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/text_book_screen.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../test_helpers/memory_cache_provider.dart';
import '../../test_helpers/stub_settings_bloc.dart';

/// issue #4609 — רענון הספרים האישיים או ייבוא כותרות חייבים להגיע לספר
/// אישי שכבר פתוח, ולא לספר שלא השתנה.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final previousDataRoot = AppPaths.cachedDataRootPath;
  late Directory tempDir;
  late PersonalNotesBloc personalNotesBloc;

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    tempDir = await Directory.systemTemp.createTemp('otzaria_user_reload');
    AppPaths.debugOverrideDataRootPath(p.join(tempDir.path, 'data_root'));
    personalNotesBloc = PersonalNotesBloc();
    DataRepository.instance.library = Future.value(
      Library(categories: const []),
    );
  });

  tearDown(() async {
    await personalNotesBloc.close();
    AppPaths.debugOverrideDataRootPath(previousDataRoot);
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  final userBook = TextBook(id: 5, title: 'ספר אישי', source: BookSource.user);
  final otherUserBook = TextBook(
    id: 6,
    title: 'ספר אישי אחר',
    source: BookSource.user,
  );
  final officialBook = TextBook(id: 5, title: 'ספר רשמי');

  Future<List<TabsEvent>> reloadLibrary(
    WidgetTester tester, {
    required TextBook openBook,
    List<Book>? changedBooks,
    bool userContentChanged = false,
  }) async {
    final bloc = _TestTextBookBloc(_loadedState(openBook));
    final tab = TextBookTab(book: openBook, index: 0, blocOverride: bloc);
    final tabsBloc = _TestTabsBloc(TabsState(tabs: [tab], currentTabIndex: 0));
    final libraryBloc = _TestLibraryBloc();
    final settingsBloc = StubSettingsBloc(SettingsState.initial());
    final bookmarkBloc = _TestBookmarkBloc();
    final tourCubit = TourCubit();
    final historyBloc = _TestHistoryBloc();
    final navigationBloc = _TestNavigationBloc();
    final focusRepository = FocusRepository()..resetForTesting();

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      for (final closable in <BlocBase<Object?>>[
        bloc,
        tabsBloc,
        libraryBloc,
        settingsBloc,
        bookmarkBloc,
        tourCubit,
        historyBloc,
        navigationBloc,
      ]) {
        await closable.close();
      }
      for (final event in tabsBloc.events.whereType<ReplaceTab>()) {
        event.newTab.dispose();
      }
      tab.dispose();
      focusRepository.resetForTesting();
    });

    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<FocusRepository>.value(value: focusRepository),
          ChangeNotifierProvider<ShamorZachorDataProvider>.value(
            value: _FakeShamorZachorDataProvider(),
          ),
          ChangeNotifierProvider<ShamorZachorProgressProvider>.value(
            value: _FakeShamorZachorProgressProvider(),
          ),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: bloc),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
            BlocProvider<LibraryBloc>.value(value: libraryBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<BookmarkBloc>.value(value: bookmarkBloc),
            BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
            BlocProvider<TourCubit>.value(value: tourCubit),
            BlocProvider<HistoryBloc>.value(value: historyBloc),
            BlocProvider<NavigationBloc>.value(value: navigationBloc),
          ],
          child: MaterialApp(
            home: TextBookViewerBloc(
              tab: tab,
              isInCombinedView: false,
              openBookCallback: (_) {},
            ),
          ),
        ),
      ),
    );
    await _settleRealAsync(tester);
    tabsBloc.events.clear();

    final library = Library(categories: const []);
    libraryBloc.emitForTest(LibraryState(library: library, isLoading: true));
    libraryBloc.emitForTest(
      LibraryState(
        library: library,
        changedBooksToIndex: changedBooks,
        userContentChanged: userContentChanged,
      ),
    );
    await _settleRealAsync(tester);
    return List.of(tabsBloc.events);
  }

  testWidgets('ספר אישי שתוכנו השתנה נטען מחדש בטאב חדש באותו מיקום', (
    tester,
  ) async {
    final events = await reloadLibrary(
      tester,
      openBook: userBook,
      changedBooks: [
        TextBook(id: 5, title: 'ספר אישי', source: BookSource.user),
      ],
    );

    final replace = events.whereType<ReplaceTab>().single;
    expect(replace.oldTab.title, userBook.title);
    expect(replace.newTab, isA<TextBookTab>());
    expect(identical(replace.newTab, replace.oldTab), isFalse);
  });

  testWidgets('ייבוא נתוני משתמש (כותרות) טוען מחדש ספר אישי פתוח', (
    tester,
  ) async {
    final events = await reloadLibrary(
      tester,
      openBook: userBook,
      userContentChanged: true,
    );

    expect(events.whereType<ReplaceTab>(), hasLength(1));
  });

  testWidgets('ספר אישי שלא השתנה אינו נטען מחדש', (tester) async {
    final events = await reloadLibrary(
      tester,
      openBook: userBook,
      changedBooks: [otherUserBook],
    );

    expect(events.whereType<ReplaceTab>(), isEmpty);
  });

  testWidgets('ספר רשמי אינו נטען מחדש גם בייבוא נתוני משתמש', (tester) async {
    final events = await reloadLibrary(
      tester,
      openBook: officialBook,
      changedBooks: [officialBook],
      userContentChanged: true,
    );

    expect(events.whereType<ReplaceTab>(), isEmpty);
  });
}

Future<void> _settleRealAsync(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
}

TextBookLoaded _loadedState(TextBook book) {
  return TextBookLoaded(
    book: book,
    showLeftPane: false,
    content: const ['שורה א', 'שורה ב'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const <Link>[],
    visibleLinks: const <Link>[],
    linksByLine: const {},
    tableOfContents: [TocEntry(text: 'פרק', index: 0)],
    removeNikud: false,
    removePunctuation: false,
    visibleIndices: const [0],
    selectedIndex: 0,
    pinLeftPane: false,
    searchText: '',
    currentTitle: 'פרק',
    searchMode: SearchMode.exact,
  );
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestTabsBloc extends Cubit<TabsState> implements TabsBloc {
  _TestTabsBloc(super.initialState);

  final List<TabsEvent> events = [];

  @override
  void add(TabsEvent event) => events.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestLibraryBloc extends Cubit<LibraryState> implements LibraryBloc {
  _TestLibraryBloc() : super(const LibraryState());

  void emitForTest(LibraryState state) => emit(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestBookmarkBloc extends Cubit<BookmarkState> implements BookmarkBloc {
  _TestBookmarkBloc() : super(BookmarkState.initial());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestHistoryBloc extends Cubit<HistoryState> implements HistoryBloc {
  _TestHistoryBloc() : super(HistoryInitial());

  @override
  void add(HistoryEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestNavigationBloc extends Cubit<NavigationState>
    implements NavigationBloc {
  _TestNavigationBloc()
    : super(const NavigationState(currentScreen: Screen.reading));

  @override
  void add(NavigationEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeShamorZachorDataProvider extends ShamorZachorDataProvider {
  @override
  bool get hasData => false;

  @override
  Future<void> ensureLoaded() async {}
}

class _FakeShamorZachorProgressProvider extends ShamorZachorProgressProvider {
  @override
  Future<void> ensureLoaded() async {}
}

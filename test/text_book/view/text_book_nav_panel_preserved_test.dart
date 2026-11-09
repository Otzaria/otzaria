import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/personal_notes_system.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/search_results.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/text_book/view/text_book_screen.dart';
import 'package:otzaria/text_book/view/text_book_search_screen.dart';
import 'package:otzaria/text_book/view/toc_navigator_screen.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/tour/tour_target_keys.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/memory_cache_provider.dart';

/// החלפת הטאב הפעיל משנה את TourTargetsScope; עליה לשמר את חלונית הניווט.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FocusRepository focusRepository;
  late _FakeShamorZachorDataProvider shamorZachorDataProvider;
  late _FakeShamorZachorProgressProvider shamorZachorProgressProvider;
  late _TestBookmarkBloc bookmarkBloc;
  late PersonalNotesBloc personalNotesBloc;
  late TourCubit tourCubit;

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    DataRepository.instance.library = Future.value(
      Library(categories: const []),
    );
    focusRepository = FocusRepository()..resetForTesting();
    shamorZachorDataProvider = _FakeShamorZachorDataProvider();
    shamorZachorProgressProvider = _FakeShamorZachorProgressProvider();
    bookmarkBloc = _TestBookmarkBloc();
    personalNotesBloc = PersonalNotesBloc();
    tourCubit = TourCubit();
    AppWindowKeys.current.tour.activeTextBookNavPanel = null;
  });

  tearDown(() async {
    await bookmarkBloc.close();
    await personalNotesBloc.close();
    await tourCubit.close();
    focusRepository.resetForTesting();
  });

  /// [settle] מאפשר לעצור לפני סיום בדיקת הכותרות החלופיות.
  Future<_ActiveTabController> pumpScreen(
    WidgetTester tester, {
    String tabSearchText = '',
    bool settle = true,
  }) async {
    final book = TextBook(title: 'ספר בדיקה');
    final bloc = _TestTextBookBloc(_loadedState(book));
    final tab = TextBookTab(
      book: book,
      index: 0,
      searchText: tabSearchText,
      blocOverride: bloc,
    );
    final tabsBloc = _TestTabsBloc(TabsState(tabs: [tab], currentTabIndex: 0));
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await bloc.close();
      await tabsBloc.close();
      await settingsBloc.close();
      tab.dispose();
    });

    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late StateSetter setHostState;
    var isActiveTab = true;
    var theme = ThemeData.light();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<FocusRepository>.value(value: focusRepository),
          ChangeNotifierProvider<ShamorZachorDataProvider>.value(
            value: shamorZachorDataProvider,
          ),
          ChangeNotifierProvider<ShamorZachorProgressProvider>.value(
            value: shamorZachorProgressProvider,
          ),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: bloc),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<BookmarkBloc>.value(value: bookmarkBloc),
            BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
            BlocProvider<TourCubit>.value(value: tourCubit),
          ],
          child: MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                setHostState = setState;
                return Theme(
                  data: theme,
                  child: TourTargetsScope(
                    enabled: isActiveTab,
                    child: TextBookViewerBloc(
                      tab: tab,
                      isInCombinedView: false,
                      openBookCallback: (_) {},
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    if (settle) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    return _ActiveTabController(
      tester: tester,
      setActiveTab: (value) => setHostState(() => isActiveTab = value),
      setTheme: (value) => setHostState(() => theme = value),
    );
  }

  testWidgets('מצב חלונית הניווט נשמר במעבר טאב וחזרה', (tester) async {
    final controller = await pumpScreen(tester);

    expect(find.byType(TocViewer), findsOneWidget);
    final stateBeforeSwitch = tester.state(find.byType(TocViewer));

    await controller.setActive(false);
    await controller.setActive(true);

    expect(find.byType(TocViewer), findsOneWidget);
    expect(
      tester.state(find.byType(TocViewer)),
      same(stateBeforeSwitch),
      reason: 'החלונית נבנתה מאפס — לכן החיפוש-בספר רץ מחדש בכל חזרה לטאב',
    );
  });

  testWidgets('הקלדה בחיפוש-בספר שורדת את סיום בדיקת הכותרות החלופיות', (
    tester,
  ) async {
    await pumpScreen(tester, tabSearchText: 'א', settle: false);

    final searchView = find.byType(TextBookSearchView);
    expect(searchView, findsOneWidget);
    expect(
      find.text('כותרות'),
      findsOneWidget,
      reason: 'הבדיקה עוד לא הסתיימה',
    );
    final stateBefore = tester.state<TextBookSearchViewState>(searchView);
    stateBefore.searchTextController.text = 'ס';

    // הבדיקה מסתיימת, לשונית הכותרות נעלמת ולשונית החיפוש זזה מקום אחד אחורה.
    await tester.pump();
    expect(find.text('כותרות'), findsNothing);

    expect(
      tester.state(searchView),
      same(stateBefore),
      reason:
          'חלונית החיפוש נבנתה מאפס — האות שהוקלדה לפני כן אבדה (issue #1263)',
    );
    expect(
      tester
          .state<TextBookSearchViewState>(searchView)
          .searchTextController
          .text,
      'ס',
    );
  });

  testWidgets('ניווט תוצאות שומר קטעים גם כשהקורא נבנה בעקבות אירועי הבחירה', (
    tester,
  ) async {
    final host = await pumpScreen(tester);
    await tester.tap(find.text('חיפוש'));
    await tester.pumpAndSettle();
    final search = find.byType(TextBookSearchView);
    final state = tester.state<TextBookSearchViewState>(search);
    state.searchTextController.text = 'אור';
    state.searchResults = [
      for (var i = 0; i < 3; i++)
        TextSearchResult(
          index: i,
          snippet: 'קטע $i אוֹר',
          query: 'אור',
          address: 'פרק',
        ),
    ];
    tester.element(search).markNeedsBuild();
    await tester.pump();
    Finder snippet(int i) => find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().startsWith('קטע $i'),
    );
    bool selected(int i) => tester
        .widget<NavTreeContentRow>(
          find.ancestor(
            of: snippet(i),
            matching: find.byType(NavTreeContentRow),
          ),
        )
        .isSelected;
    final bloc = tester.element(search).read<TextBookBloc>();

    await tester.tap(find.byTooltip('התוצאה הבאה'));
    await tester.pump();
    final untouched = tester.widget(snippet(2));
    expect((bloc.state as TextBookLoaded).selectedIndex, 0);
    expect((bloc.state as TextBookLoaded).highlightedLine, 0);
    expect(selected(0), isTrue);

    await tester.tap(find.byTooltip('התוצאה הבאה'));
    await tester.pump();
    expect((bloc.state as TextBookLoaded).selectedIndex, 1);
    expect((bloc.state as TextBookLoaded).highlightedLine, 1);
    expect(selected(0), isFalse);
    expect(selected(1), isTrue);
    expect(tester.widget(snippet(2)), same(untouched));

    state.widget.focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect((bloc.state as TextBookLoaded).selectedIndex, 2);
    expect(selected(2), isTrue);
    await tester.tap(snippet(0));
    await tester.pump();
    expect((bloc.state as TextBookLoaded).selectedIndex, 0);
    expect((bloc.state as TextBookLoaded).highlightedLine, 0);
    expect(selected(0), isTrue);
    expect(tester.widget(snippet(2)), same(untouched));

    await host.changeTheme(ThemeData.dark());
    final darkSnippet = tester.widget<RichText>(snippet(2));
    expect(
      darkSnippet.text.style!.color,
      ThemeData.dark().colorScheme.onSurface,
    );
    expect(darkSnippet, isNot(same(untouched)));
    final settings =
        tester.element(search).read<SettingsBloc>() as _TestSettingsBloc;
    settings.update(settings.state.copyWith(fontFamily: 'TaameyDavidCLM'));
    await tester.pump();
    expect(
      tester.widget<RichText>(snippet(2)).text.style!.fontFamily,
      'TaameyDavidCLM',
    );
    // DD-26: אחרי מעבר החלונית נסגרת רק כשהיא מכסה את הטקסט. כאן היא
    // מוצמדת לצד הטקסט (מסך רחב, נעוצה) — ולכן נשארת פתוחה.
    state.widget.closeLeftPaneCallback();
    await tester.pump();
    expect((bloc.state as TextBookLoaded).showLeftPane, isTrue);
    // לא נעוצה, צפה מעל הטקסט: הקריאה מהחלונית השמורה מגיעה לקורא וסוגרת.
    (bloc as _TestTextBookBloc).update(
      (bloc.state as TextBookLoaded).copyWith(pinLeftPane: false),
    );
    await tester.pump();
    // מצב הפריסה מדווח ב-post-frame.
    await tester.pump();
    expect(tester.state(search), same(state));
    state.widget.closeLeftPaneCallback();
    await tester.pump();
    expect((bloc.state as TextBookLoaded).showLeftPane, isFalse);
  });

  testWidgets('שינוי תצורת חיפוש ובקשה חיצונית מגיעים לחלונית השמורה', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.tap(find.text('חיפוש'));
    await tester.pumpAndSettle();
    final search = find.byType(TextBookSearchView);
    final bloc =
        tester.element(search).read<TextBookBloc>() as _TestTextBookBloc;
    final original = tester.widget<TextBookSearchView>(search);
    bloc.update(
      (bloc.state as TextBookLoaded).copyWith(
        searchOptions: const {
          'אור_0': {'prefix': true},
        },
        alternativeWords: const {
          0: ['אורות'],
        },
        spacingValues: const {'0-1': '2'},
        searchDistance: 3,
        searchMode: SearchMode.fuzzy,
        matchPolicy: const SearchMatchPolicy(anyOrder: true),
      ),
    );
    await tester.pump();
    await tester.pump();
    final changed = tester.widget<TextBookSearchView>(search);
    expect(changed, isNot(same(original)));
    expect(changed.initialSearchOptions, {
      'אור_0': {'prefix': true},
    });
    expect(changed.initialAlternativeWords, {
      0: ['אורות'],
    });
    expect(changed.initialSpacingValues, {'0-1': '2'});
    expect(changed.initialSearchDistance, 3);
    expect(changed.initialSearchMode, SearchMode.fuzzy);
    expect(changed.initialMatchPolicy.anyOrder, isTrue);

    bloc.update((bloc.state as TextBookLoaded).copyWith(searchText: '/[/'));
    await tester.pump();
    await tester.pump();
    expect(
      tester.state<TextBookSearchViewState>(search).searchTextController.text,
      '/[/',
    );
    expect(tester.widget<TextBookSearchView>(search).initialQuery, '/[/');
    bloc.update((bloc.state as TextBookLoaded).copyWith(searchText: ''));
    await tester.pump();
    await tester.pump();
    expect(
      tester.state<TextBookSearchViewState>(search).searchTextController.text,
      isEmpty,
    );
    await tester.pump();
  });

  testWidgets('יעד הסיור מצביע על חלונית הניווט של הטאב הפעיל', (tester) async {
    final controller = await pumpScreen(tester);

    final key = AppWindowKeys.current.tour.activeTextBookNavPanel;
    expect(key, isNotNull);
    expect(
      find.descendant(of: find.byKey(key!), matching: find.byType(TocViewer)),
      findsOneWidget,
    );

    // המפתח נשאר תקף גם אחרי מעבר לרקע וחזרה.
    await controller.setActive(false);
    await controller.setActive(true);

    expect(AppWindowKeys.current.tour.activeTextBookNavPanel, isNotNull);
    expect(
      AppWindowKeys.current.tour.activeTextBookNavPanel!.currentContext,
      isNotNull,
    );
  });
}

class _ActiveTabController {
  _ActiveTabController({
    required this.tester,
    required this.setActiveTab,
    required this.setTheme,
  });

  final WidgetTester tester;
  final void Function(bool) setActiveTab;
  final void Function(ThemeData) setTheme;

  Future<void> changeTheme(ThemeData value) async {
    setTheme(value);
    await tester.pump();
  }

  Future<void> setActive(bool value) async {
    setActiveTab(value);
    await tester.pump();
  }
}

TextBookLoaded _loadedState(TextBook book) {
  return TextBookLoaded(
    book: book,
    showLeftPane: true,
    content: const ['שורה א', 'שורה ב', 'שורה ג'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const <Link>[],
    visibleLinks: const <Link>[],
    linksByLine: const {},
    tableOfContents: const [],
    removeNikud: false,
    removePunctuation: false,
    visibleIndices: const [0],
    selectedIndex: 0,
    pinLeftPane: true,
    searchText: '',
    currentTitle: 'סימן א',
    searchMode: SearchMode.exact,
  );
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {
      final current = state;
      if (current is! TextBookLoaded) return;
      if (event is UpdateSelectedIndex) {
        emit(
          current.copyWith(
            selectedIndex: event.index,
            selectedIndices: {event.index!},
          ),
        );
      } else if (event is HighlightLine) {
        emit(current.copyWith(highlightedLine: event.lineIndex));
      } else if (event is ToggleLeftPane) {
        emit(current.copyWith(showLeftPane: event.show));
      }
    });
  }

  void update(TextBookLoaded next) => emit(next);

  @override
  final TextBookRepository repository = TextBookRepository(
    fileSystem: FileSystemData.instance,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  void update(SettingsState next) => emit(next);

  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestTabsBloc extends Cubit<TabsState> implements TabsBloc {
  _TestTabsBloc(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestBookmarkBloc extends Cubit<BookmarkState> implements BookmarkBloc {
  _TestBookmarkBloc() : super(BookmarkState.initial());

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

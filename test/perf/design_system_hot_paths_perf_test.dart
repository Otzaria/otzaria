// מדידת ביצועים ממוקדת (B-34) בארבעה מסלולים חמים: גלילה בקורא, ניווט
// בתוצאות החיפוש בספר, גלילת רשימת הספרייה, ופתיחת ההגדרות ומעבר בין
// לשוניות.
//
// זו מדידה ב-flutter_test (מצב debug, JIT, בלי GPU): מונה בניות של אלמנטים
// (debugOnRebuildDirtyWidget) וזמן קיר של pump. מונה הבניות דטרמיניסטי ונותן
// השוואה אמינה בין גרסאות; הזמנים יחסיים בלבד ורועשים. אינה מחליפה את
// tool/perf_probe (profile על התוכנה האמיתית).
//
// הקובץ מתקמפל על הבסיס ac97e4490 ועל stage-b בלי שינוי, כדי להשוות באותה
// בדיקה. אין בו ספים: הוא מדפיס `PERF|<תרחיש>|<בניות>|<ms חציון>|<ms מינימום>`.
// הרצה: flutter test test/perf/design_system_hot_paths_perf_test.dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/view/library_browser.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/personal_notes/personal_notes_system.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/l10n/settings_language.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/settings/view/settings_screen.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/search_results.dart';
import 'package:otzaria/text_book/utils/section_search_utils.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';
import 'package:otzaria/text_book/view/text_book_screen.dart';
import 'package:otzaria/text_book/view/text_book_search_screen.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/widgets/navigation/sidebar_nav_item.dart';
import 'package:provider/provider.dart';

import '../test_helpers/memory_cache_provider.dart';

const _runs = 5;

ThemeData get _theme => AppThemeData.light(
  AppThemeData.createColorScheme(AppSeedColors.defaultLight, Brightness.light),
  compactMenuMode: false,
);

/// סופר בניות של אלמנטים וזמן קיר ב-[body].
Future<(int, int)> _measure(Future<void> Function() body) async {
  var builds = 0;
  final previous = debugOnRebuildDirtyWidget;
  debugOnRebuildDirtyWidget = (element, builtOnce) => builds++;
  final watch = Stopwatch()..start();
  try {
    await body();
  } finally {
    debugOnRebuildDirtyWidget = previous;
  }
  return (builds, watch.elapsedMicroseconds);
}

final _results = <String, List<(int, int)>>{};

void _record(String name, (int, int) value) =>
    (_results[name] ??= []).add(value);

void _report() {
  for (final entry in _results.entries) {
    final times = entry.value.map((v) => v.$2).toList()..sort();
    final builds = entry.value.map((v) => v.$1).toSet();
    // ignore: avoid_print
    print(
      'PERF|${entry.key}|${builds.join('/')}|'
      '${(times[times.length ~/ 2] / 1000).toStringAsFixed(1)}|'
      '${(times.first / 1000).toStringAsFixed(1)}',
    );
  }
}

Finder _largestScrollable(WidgetTester tester) {
  final all = find.byType(Scrollable).evaluate().toList();
  all.sort((a, b) {
    final sa = (a.renderObject as RenderBox?)?.size ?? Size.zero;
    final sb = (b.renderObject as RenderBox?)?.size ?? Size.zero;
    return (sb.width * sb.height).compareTo(sa.width * sa.height);
  });
  return find.byElementPredicate((e) => identical(e, all.first));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });
  tearDownAll(_report);

  // ── 1. גלילה בקורא ─────────────────────────────────────────────────────────
  // הבלוקים של ההערות, הסימניות והסיור נסגרים מחוץ ל-testWidgets, כמו ב-
  // text_book_toolbar_overflow_test: סגירתם בתוך האזור המדומה נתקעת.
  late _TestBookmarkBloc bookmarkBloc;
  late PersonalNotesBloc personalNotesBloc;
  late TourCubit tourCubit;
  setUp(() {
    bookmarkBloc = _TestBookmarkBloc();
    personalNotesBloc = PersonalNotesBloc();
    tourCubit = TourCubit();
  });
  tearDown(() async {
    await bookmarkBloc.close();
    await personalNotesBloc.close();
    await tourCubit.close();
  });

  for (var run = 0; run < _runs; run++) {
    testWidgets('reader_scroll #$run', (tester) async {
      DataRepository.instance.library = Future.value(
        Library(categories: const []),
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 900);
      addTearDown(tester.view.reset);
      final focusRepository = FocusRepository()..resetForTesting();
      final book = TextBook(title: 'ספר בדיקה');
      final bloc = _TestTextBookBloc(_readerState(book));
      final tab = TextBookTab(book: book, index: 0, blocOverride: bloc);
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: [tab], currentTabIndex: 0),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      final navigationBloc = _TestNavigationBloc();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await bloc.close();
        await tabsBloc.close();
        await settingsBloc.close();
        await navigationBloc.close();
        tab.dispose();
        focusRepository.resetForTesting();
      });

      final open = await _measure(() async {
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
                BlocProvider<SettingsBloc>.value(value: settingsBloc),
                BlocProvider<BookmarkBloc>.value(value: bookmarkBloc),
                BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
                BlocProvider<TourCubit>.value(value: tourCubit),
                BlocProvider<NavigationBloc>.value(value: navigationBloc),
              ],
              child: MaterialApp(
                theme: _theme,
                home: TextBookViewerBloc(
                  tab: tab,
                  isInCombinedView: false,
                  openBookCallback: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
      });
      _record('reader_open', open);

      final list = _largestScrollable(tester);
      final scroll = await _measure(() async {
        for (var i = 0; i < 30; i++) {
          await tester.drag(list, const Offset(0, -120));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pump(const Duration(milliseconds: 500));
      });
      _record('reader_scroll_30_drags', scroll);
    });
  }

  // ── 2. תוצאות חיפוש בספר ───────────────────────────────────────────────────
  for (var run = 0; run < _runs; run++) {
    testWidgets('search_results #$run', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 900);
      addTearDown(tester.view.reset);
      final textBookBloc = _TestTextBookBloc(_searchState());
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      final focusNode = FocusNode();
      addTearDown(textBookBloc.close);
      addTearDown(settingsBloc.close);
      addTearDown(focusNode.dispose);
      addTearDown(resetSectionSearchWorkerForTesting);
      Future<List<TextSearchResult>> runner(List<String> c, String q) async => [
        for (var i = 0; i < 200; i++)
          TextSearchResult(
            snippet: 'שורה $i ובה המילה אור באמצע המשפט',
            index: i,
            query: q,
            address: 'פרק ${i ~/ 10}',
            matchOffset: 0,
          ),
      ];

      final open = await _measure(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: _theme,
            home: MultiBlocProvider(
              providers: [
                BlocProvider<TextBookBloc>.value(value: textBookBloc),
                BlocProvider<SettingsBloc>.value(value: settingsBloc),
              ],
              child: Scaffold(
                body: SizedBox(
                  width: 400,
                  child: TextBookSearchView(
                    contentLoader: () async => List.filled(200, 'אור'),
                    lines: LineScrollController(),
                    focusNode: focusNode,
                    closeLeftPaneCallback: () {},
                    initialQuery: 'אור',
                    simpleSearchRunner: runner,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      });
      _record('search_open_200_results', open);

      final next = await _measure(() async {
        for (var i = 0; i < 20; i++) {
          await tester.tap(find.byTooltip('התוצאה הבאה'));
          await tester.pump();
        }
        await tester.pumpAndSettle();
      });
      _record('search_next_result_x20', next);

      final list = _largestScrollable(tester);
      final scroll = await _measure(() async {
        for (var i = 0; i < 20; i++) {
          await tester.drag(list, const Offset(0, -150));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pumpAndSettle();
      });
      _record('search_scroll_20_drags', scroll);
    });
  }

  // ── 3. רשימת הספרייה ───────────────────────────────────────────────────────
  testWidgets('library_list', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    final folder = Category(
      title: 'תיקייה',
      description: '',
      shortDescription: '',
      order: 1,
      subCategories: [],
      books: [
        for (var i = 0; i < 300; i++)
          TextBook(title: 'ספר מספר $i', author: 'מחבר $i'),
      ],
      parent: null,
    );
    final library = Library(categories: [folder]);
    folder.parent = library;
    for (final view in ['list', 'grid']) {
      for (var run = 0; run < _runs; run++) {
        final libraryBloc = _MockLibraryBloc();
        final settingsBloc = _MockSettingsBloc();
        final navigationBloc = _MockNavigationBloc();
        final libraryUpdateBloc = _MockLibraryUpdateBloc();
        final calendarCubit = _StubCalendarCubit(CalendarState.initial());
        whenListen(
          libraryBloc,
          const Stream<LibraryState>.empty(),
          initialState: LibraryState(library: library, currentCategory: folder),
        );
        whenListen(
          settingsBloc,
          const Stream<SettingsState>.empty(),
          initialState: SettingsState.initial().copyWith(
            libraryViewMode: view,
            libraryShowPreview: false,
          ),
        );
        whenListen(
          navigationBloc,
          const Stream<NavigationState>.empty(),
          initialState: const NavigationState(currentScreen: Screen.library),
        );
        whenListen(
          libraryUpdateBloc,
          const Stream<LibraryUpdateState>.empty(),
          initialState: const LibraryUpdateState(),
        );

        final open = await _measure(() async {
          await tester.pumpWidget(
            MaterialApp(
              theme: _theme,
              builder: (context, child) => Directionality(
                textDirection: TextDirection.rtl,
                child: child!,
              ),
              home: MultiProvider(
                providers: [
                  Provider<FocusRepository>.value(value: FocusRepository()),
                  BlocProvider<LibraryBloc>.value(value: libraryBloc),
                  BlocProvider<SettingsBloc>.value(value: settingsBloc),
                  BlocProvider<NavigationBloc>.value(value: navigationBloc),
                  BlocProvider<LibraryUpdateBloc>.value(
                    value: libraryUpdateBloc,
                  ),
                  BlocProvider<CalendarCubit>.value(value: calendarCubit),
                  BlocProvider<CustomFoldersBloc>(
                    create: (_) => CustomFoldersBloc(addLibraryEvent: (_) {}),
                  ),
                ],
                child: const LibraryBrowser(),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        });
        // כפתור הדף היומי גולש עם CalendarState מדומה — לא נושא המדידה.
        tester.takeException();
        _record('library_${view}_open_300', open);

        final list = _largestScrollable(tester);
        final scroll = await _measure(() async {
          for (var i = 0; i < 30; i++) {
            await tester.drag(list, const Offset(0, -200));
            await tester.pump(const Duration(milliseconds: 16));
          }
          await tester.pump(const Duration(milliseconds: 500));
        });
        tester.takeException();
        _record('library_${view}_scroll_30_drags', scroll);

        await tester.pumpWidget(const SizedBox.shrink());
        await libraryBloc.close();
        await settingsBloc.close();
        await navigationBloc.close();
        await libraryUpdateBloc.close();
        await calendarCubit.close();
      }
    }
  });

  // ── 4. פתיחת ההגדרות ומעבר בין לשוניות ──────────────────────────────────────
  testWidgets('settings_open', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (var run = 0; run < _runs; run++) {
      final settingsBloc = _MockSettingsBloc();
      final navigationBloc = _MockNavigationBloc();
      whenListen(
        settingsBloc,
        const Stream<SettingsState>.empty(),
        initialState: SettingsState.initial().copyWith(
          settingsLanguageCode: SettingsLanguage.hebrew.code,
        ),
      );
      whenListen(
        navigationBloc,
        const Stream<NavigationState>.empty(),
        initialState: const NavigationState(currentScreen: Screen.settings),
      );

      final open = await _measure(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: _theme,
            home: RepositoryProvider<SettingsRepository>.value(
              value: _FakeSettingsRepository(),
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<SettingsBloc>.value(value: settingsBloc),
                  BlocProvider<NavigationBloc>.value(value: navigationBloc),
                ],
                child: MySettingsScreen(onDesktopBack: () {}),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      });
      _record('settings_open', open);

      final switching = await _measure(() async {
        for (final label in ['כתב', 'מראה', 'כתב', 'מראה']) {
          await tester.tap(find.widgetWithText(SidebarNavItem, label));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        }
      });
      tester.takeException();
      _record('settings_switch_4_tabs', switching);

      await tester.pumpWidget(const SizedBox.shrink());
      await settingsBloc.close();
      await navigationBloc.close();
    }
  });
}

TextBookLoaded _readerState(TextBook book) => TextBookLoaded(
  book: book,
  showLeftPane: false,
  content: [
    for (var i = 0; i < 400; i++)
      'שורה $i: וַיֹּאמֶר אֱלֹהִים יְהִי אוֹר וַיְהִי אוֹר, וַיַּרְא אֱלֹהִים '
          'אֶת הָאוֹר כִּי טוֹב, וַיַּבְדֵּל אֱלֹהִים בֵּין הָאוֹר וּבֵין '
          'הַחֹשֶׁךְ.',
  ],
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
  pinLeftPane: false,
  searchText: '',
  currentTitle: 'סימן א',
  searchMode: SearchMode.exact,
);

TextBookLoaded _searchState() => TextBookLoaded(
  book: TextBook(title: 'ספר בדיקה'),
  showLeftPane: true,
  content: List.filled(200, 'אור'),
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

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestNavigationBloc extends Bloc<NavigationEvent, NavigationState>
    implements NavigationBloc {
  _TestNavigationBloc() : super(NavigationState.initial(true)) {
    on<NavigationEvent>((event, emit) {});
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
  bool addBookmark({
    required String ref,
    required Book book,
    required int index,
    List<String>? commentatorsToShow,
    BookmarkTargetKind targetKind = BookmarkTargetKind.book,
    String? label,
  }) => true;

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

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _MockNavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

class _MockLibraryUpdateBloc
    extends MockBloc<LibraryUpdateEvent, LibraryUpdateState>
    implements LibraryUpdateBloc {}

class _StubCalendarCubit extends Cubit<CalendarState> implements CalendarCubit {
  _StubCalendarCubit(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettingsRepository extends Fake implements SettingsRepository {
  @override
  bool hasProtectedModePassword() => false;
}

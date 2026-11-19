// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
import 'package:flutter/material.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/personal_notes_system.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/reading_screen.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/text_book/view/text_book_screen.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/widgets/feedback/scrollable_positioned_list_scrollbar.dart';
import 'package:provider/provider.dart';

import '../test_helpers/memory_cache_provider.dart';
import '../test_helpers/stub_settings_bloc.dart';

/// issue #4173: מעבר בין טאבים במסך העיון הזיז את סמן פס הגלילה, כי טאב רקע
/// משחרר את תוכנו והערכות הגובה של השורות ששוחררו השתנו.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final themeMode = ValueNotifier(ThemeMode.light);

  late List<TextBookTab> tabs;
  late _TestTabsBloc tabsBloc;

  Future<void> pumpReadingScreen(
    WidgetTester tester, {
    int tabCount = 3,
    TextDirection direction = TextDirection.rtl,
  }) async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    DataRepository.instance.library = Future.value(
      Library(categories: const []),
    );
    final focusRepository = FocusRepository()..resetForTesting();
    final bookmarkBloc = _TestBookmarkBloc();
    final personalNotesBloc = PersonalNotesBloc();
    final tourCubit = TourCubit();
    final historyBloc = _FakeHistoryBloc();
    final settingsBloc = StubSettingsBloc(SettingsState.initial());
    tabs = [
      for (var i = 0; i < tabCount; i++)
        () {
          final book = TextBook(title: 'ספר $i');
          return TextBookTab(
            book: book,
            index: 0,
            blocOverride: TextBookBloc(
              repository: _FakeTextBookRepository(),
              initialState: TextBookInitial.named(book, 0, true, const []),
            )..emit(_loadedState(book)),
          );
        }(),
    ];
    tabsBloc = _TestTabsBloc(TabsState(tabs: tabs, currentTabIndex: 0));

    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    addTearDown(() => themeMode.value = ThemeMode.light);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      for (final tab in tabs) {
        await tab.bloc.close();
        tab.dispose();
      }
      await tabsBloc.close();
      await settingsBloc.close();
      await historyBloc.close();
      await bookmarkBloc.close();
      await personalNotesBloc.close();
      await tourCubit.close();
      focusRepository.resetForTesting();
    });

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
            BlocProvider<TabsBloc>.value(value: tabsBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<BookmarkBloc>.value(value: bookmarkBloc),
            BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
            BlocProvider<TourCubit>.value(value: tourCubit),
            BlocProvider<HistoryBloc>.value(value: historyBloc),
          ],
          child: ValueListenableBuilder<ThemeMode>(
            valueListenable: themeMode,
            builder: (context, mode, _) => MaterialApp(
              theme: ThemeData(),
              darkTheme: ThemeData.dark(),
              themeMode: mode,
              home: Directionality(
                textDirection: direction,
                child: const ReadingScreen(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    // טווח שהוחל מוכיח שהספר נטען בטווחים, תנאי לשחרור התוכן בטאב רקע.
    for (final tab in tabs) {
      tab.bloc.add(
        ApplyBookContentRanges(
          bookTitle: tab.book.title,
          ranges: [
            (startLine: 1500, totalLines: _lineCount, lines: [_line(1500)]),
          ],
        ),
      );
    }
    await tester.pump();
    // ביקור בכל טאב כדי שייבנה ויישמר חי ברקע.
    for (var i = tabCount - 1; i >= 0; i--) {
      await showTab(tester, i);
    }
  }

  testWidgets('חזרה לטאב שתוכנו שוחרר ברקע אינה מזיזה את סמן פס הגלילה', (
    tester,
  ) async {
    await pumpReadingScreen(tester, tabCount: 2);
    final position = scrollPosition(tester, tabs[0]);
    position.jumpTo(position.maxScrollExtent / 2);
    await tester.pumpAndSettle();
    // ה-bloc שהוזרק אינו מאזין למיקום הקריאה של הטאב; מעבירים אותו כמו המאזין.
    tabs[0].bloc.add(
      UpdateVisibleIndecies(tabs[0].lines.position.value!.visibleLines),
    );
    await tester.pumpAndSettle();
    final before = tester.getRect(thumbOf(tabs[0]));

    await showTab(tester, 1);
    expect(
      (tabs[0].bloc.state as TextBookLoaded).content.first,
      isEmpty,
      reason: 'טאב הרקע משחרר את התוכן שמחוץ לחלון',
    );
    await showTab(tester, 0);
    expect(tester.getRect(thumbOf(tabs[0])), before);
    await tester.pumpAndSettle();
    expect(tester.getRect(thumbOf(tabs[0])), before);
  });
}

Finder thumbOf(TextBookTab tab) => find.descendant(
  of: find.byWidgetPredicate(
    (w) => w is TextBookViewerBloc && identical(w.tab, tab),
    skipOffstage: false,
  ),
  matching: find.byKey(
    ScrollablePositionedListScrollbar.thumbKey,
    skipOffstage: false,
  ),
);

ScrollPosition scrollPosition(WidgetTester tester, TextBookTab tab) => tester
    .widget<ScrollablePositionedListScrollbar>(
      find
          .descendant(
            of: find.byWidgetPredicate(
              (w) => w is TextBookViewerBloc && identical(w.tab, tab),
            ),
            matching: find.byType(ScrollablePositionedListScrollbar),
          )
          .first,
    )
    .scrollController
    .scrollController!
    .position;

Future<void> showTab(WidgetTester tester, int index) async {
  final controller = tester
      .widget<PageView>(find.byKey(const ValueKey('normal_tab_view')))
      .controller!;
  final bloc =
      tester.element(find.byType(ReadingScreen)).read<TabsBloc>()
          as _TestTabsBloc;
  bloc.emit(TabsState(tabs: bloc.state.tabs, currentTabIndex: index));
  await tester.pump();
  controller.jumpToPage(index);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

class _FakeHistoryBloc extends Bloc<HistoryEvent, HistoryState>
    implements HistoryBloc {
  _FakeHistoryBloc() : super(HistoryInitial()) {
    on<HistoryEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TextBookLoaded _loadedState(TextBook book) {
  return TextBookLoaded(
    book: book,
    showLeftPane: true,
    content: [for (var i = 0; i < _lineCount; i++) _line(i)],
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

class _FakeTextBookRepository extends TextBookRepository {
  _FakeTextBookRepository() : super(fileSystem: FileSystemData.instance);

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
    int? maxChars,
    bool budgetFromEnd = false,
  }) async {
    final start = startLine.clamp(0, _lineCount - 1);
    final end = endLine.clamp(start, _lineCount - 1);
    return BookContentRange(
      startLine: start,
      endLine: end,
      totalLines: _lineCount,
      lines: [for (var i = start; i <= end; i++) _line(i)],
    );
  }

  @override
  Future<String> getBookContent(TextBook book) async =>
      [for (var i = 0; i < _lineCount; i++) _line(i)].join('\n');
}

const _lineCount = 3000;

/// שורות באורכים שונים, כמו בספר אמיתי.
String _line(int i) => 'שורה $i ' * (1 + i % 7 * 9);

class _TestTabsBloc extends Cubit<TabsState> implements TabsBloc {
  _TestTabsBloc(super.initialState);

  @override
  void add(TabsEvent event) {
    if (event is SetCurrentTab) {
      emit(state.copyWith(currentTabIndex: event.index));
    }
  }

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

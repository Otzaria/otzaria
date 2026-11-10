import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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
import 'package:otzaria/tabs/models/combined_tab.dart';
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
import 'package:provider/provider.dart';

import '../test_helpers/memory_cache_provider.dart';
import '../test_helpers/stub_settings_bloc.dart';

/// שינוי גודל החלון עם כמה טאבים פתוחים: טאבי רקע חיים (KeepAlive) אינם
/// מוצגים, ולכן אסור שייבנו וייפרסו מחדש בכל פריים של הגרירה.
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
            blocOverride: _TestTextBookBloc(_loadedState(book)),
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
    // ביקור בכל טאב כדי שייבנה ויישמר חי ברקע.
    for (var i = tabCount - 1; i >= 0; i--) {
      await showTab(tester, i);
    }
  }

  testWidgets('גרירת גודל החלון אינה בונה מחדש את תוכן טאבי הרקע', (
    tester,
  ) async {
    await pumpReadingScreen(tester);

    var backgroundRebuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (_isInsideBackgroundBook(element)) backgroundRebuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    for (var frame = 1; frame <= 10; frame++) {
      tester.view.physicalSize = Size(1600 - frame * 20, 900 - frame * 10);
      await tester.pump();
    }
    debugOnRebuildDirtyWidget = null;

    expect(
      backgroundRebuilds,
      0,
      reason:
          'טאב רקע אינו מוצג; בנייה ופריסה שלו בכל פריים מכפילות את עלות הגרירה',
    );
  });

  testWidgets('מעבר למצב כהה אינו בונה מחדש את תוכן טאבי הרקע', (
    tester,
  ) async {
    await pumpReadingScreen(tester);

    var backgroundRebuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (_isInsideBackgroundBook(element)) backgroundRebuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    themeMode.value = ThemeMode.dark;
    await tester.pumpAndSettle();
    debugOnRebuildDirtyWidget = null;

    expect(
      backgroundRebuilds,
      0,
      reason: 'אנימציית ערכת הצבע בנתה מחדש כל טאב רקע בכל פריים',
    );
    expect(bookTheme(tester, tabs[0]).brightness, Brightness.dark);

    await showTab(tester, 1);
    await tester.pumpAndSettle();
    expect(bookTheme(tester, tabs[1]).brightness, Brightness.dark);
    expect(bookTheme(tester, tabs[1]), bookTheme(tester, tabs[0]));
  });

  for (final touch in [true, false]) {
    testWidgets(
      '${touch ? 'touch' : 'desktop'} לשונית הנכנסת בהחלקה מקבלת מיד את מדדי החלון',
      (tester) async {
        ReadingScreen.debugForceTouchTabs = touch;
        addTearDown(() => ReadingScreen.debugForceTouchTabs = null);
        await pumpReadingScreen(tester);
        tester.view.devicePixelRatio = 2;
        tester.view.physicalSize = const Size(2000, 1400);
        tester.view.padding = const FakeViewPadding(top: 40);
        tester.view.viewPadding = const FakeViewPadding(top: 40);
        tester.platformDispatcher.textScaleFactorTestValue = 1.1;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pump();
        final controller = tester
            .widget<PageView>(find.byKey(const ValueKey('normal_tab_view')))
            .controller!;
        if (touch) {
          controller.position.jumpTo(250);
        } else {
          final detector = tester.widget<RawGestureDetector>(
            find.byWidgetPredicate(
              (w) => w is RawGestureDetector && w.child is PageView,
            ),
          );
          final factory = detector.gestures[HorizontalDragGestureRecognizer]!;
          final recognizer =
              factory.constructor() as HorizontalDragGestureRecognizer;
          factory.initializer(recognizer);
          addTearDown(recognizer.dispose);
          recognizer.onStart!(DragStartDetails());
          recognizer.onUpdate!(
            DragUpdateDetails(
              delta: const Offset(250, 0),
              globalPosition: Offset.zero,
            ),
          );
        }
        await tester.pump();
        final incoming = find.byWidgetPredicate(
          (w) => w is TextBookViewerBloc && identical(w.tab, tabs[1]),
          skipOffstage: false,
        );
        final scaffold = find.descendant(
          of: incoming,
          matching: find.byType(Scaffold, skipOffstage: false),
        );
        expect(controller.page, closeTo(0.25, 0.001));
        expect(tabsBloc.state.currentTabIndex, 0);
        expect(
          tester
              .getRect(scaffold.first)
              .overlaps(const Rect.fromLTWH(0, 0, 1000, 700)),
          isTrue,
        );
        final data = MediaQuery.of(tester.element(scaffold.first));
        expect(
          {
            'size': data.size,
            'padding': data.padding,
            'ratio': data.devicePixelRatio,
            'textScale': data.textScaler.scale(10),
          },
          {
            'size': const Size(1000, 700),
            'padding': const EdgeInsets.only(top: 20),
            'ratio': 2.0,
            'textScale': 11.0,
          },
        );
      },
    );
  }

  for (final direction in TextDirection.values) {
    testWidgets('החלקה ארוכה, חזרה וביטול שומרים מדדים חיים ($direction)', (
      tester,
    ) async {
      ReadingScreen.debugForceTouchTabs = false;
      addTearDown(() => ReadingScreen.debugForceTouchTabs = null);
      await pumpReadingScreen(tester, tabCount: 4, direction: direction);
      final controller = pageController(tester);
      final recognizer = desktopSwipe(tester);
      final sign = direction == TextDirection.rtl ? 1.0 : -1.0;
      tester.view.physicalSize = const Size(1000, 700);
      await tester.pump();
      recognizer.onStart!(DragStartDetails());
      recognizer.onUpdate!(
        DragUpdateDetails(
          delta: Offset(sign * 1250, 0),
          globalPosition: Offset.zero,
        ),
      );
      await tester.pump();
      expect(controller.page, closeTo(1.25, 0.001));
      expect(tabsBloc.state.currentTabIndex, 0);
      tester.view.physicalSize = const Size(900, 650);
      await tester.pump();
      for (final index in [0, 1, 2]) {
        expect(bookMediaQuery(tester, tabs[index]).size, const Size(900, 650));
      }
      expect(bookMediaQuery(tester, tabs[3]).size, const Size(1600, 900));
      recognizer.onUpdate!(
        DragUpdateDetails(
          delta: Offset(-sign * 900, 0),
          globalPosition: Offset.zero,
        ),
      );
      await tester.pump();
      expect(controller.page, closeTo(0.25, 0.001));
      recognizer.onCancel!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 35));
      expect(controller.page, inExclusiveRange(0, 0.25));
      tester.view.physicalSize = const Size(800, 600);
      await tester.pump();
      for (final index in [0, 1]) {
        expect(bookMediaQuery(tester, tabs[index]).size, const Size(800, 600));
      }
      await tester.pumpAndSettle();
      expect(controller.page, 0);
      var backgroundRebuilds = 0;
      debugOnRebuildDirtyWidget = (element, _) {
        if (_isInsideBackgroundBook(element)) backgroundRebuilds++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = null);
      tester.view.physicalSize = const Size(700, 500);
      await tester.pump();
      debugOnRebuildDirtyWidget = null;
      expect(backgroundRebuilds, 0);
      expect(bookMediaQuery(tester, tabs[1]).size, const Size(800, 600));
    });

    testWidgets('הלשונית היוצאת מתעדכנת במהלך אנימציית מעבר ($direction)', (
      tester,
    ) async {
      ReadingScreen.debugForceTouchTabs = false;
      addTearDown(() => ReadingScreen.debugForceTouchTabs = null);
      await pumpReadingScreen(tester, direction: direction);
      final controller = pageController(tester);
      final recognizer = desktopSwipe(tester);
      final sign = direction == TextDirection.rtl ? 1.0 : -1.0;
      recognizer.onStart!(DragStartDetails());
      recognizer.onUpdate!(
        DragUpdateDetails(
          delta: Offset(sign * 1200, 0),
          globalPosition: Offset.zero,
        ),
      );
      await tester.pump();
      expect(controller.page, closeTo(0.75, 0.001));
      recognizer.onEnd!(DragEndDetails());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 35));
      expect(tabsBloc.state.currentTabIndex, 1);
      expect(controller.page, inExclusiveRange(0.75, 1));
      tester.view.physicalSize = const Size(1000, 700);
      await tester.pump();
      for (final index in [0, 1]) {
        expect(bookMediaQuery(tester, tabs[index]).size, const Size(1000, 700));
      }
      expect(bookMediaQuery(tester, tabs[2]).size, const Size(1600, 900));
      await tester.pumpAndSettle();
      expect(controller.page, 1);
    });
  }

  testWidgets('שתי חלוניות של לשונית מפוצלת פעילה מקבלות מדדים חיים', (
    tester,
  ) async {
    await pumpReadingScreen(tester);
    tabsBloc.emit(
      TabsState(
        tabs: [
          CombinedTab(rightTab: tabs[0], leftTab: tabs[1]),
          tabs[2],
        ],
        currentTabIndex: 0,
      ),
    );
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1000, 700);
    await tester.pump();
    for (final index in [0, 1]) {
      expect(bookMediaQuery(tester, tabs[index]).size, const Size(1000, 700));
    }
    expect(bookMediaQuery(tester, tabs[2]).size, const Size(1600, 900));
  });
  testWidgets('טאב רקע מוצג בגודל החלון החדש כשעוברים אליו', (tester) async {
    await pumpReadingScreen(tester);

    tester.view.physicalSize = const Size(1000, 700);
    await tester.pump();
    await showTab(tester, 1);

    final scaffold = find.descendant(
      of: find.byType(TextBookViewerBloc).hitTestable(),
      matching: find.byType(Scaffold),
    );
    expect(tester.getSize(scaffold.first), const Size(1000, 700));
    expect(
      MediaQuery.sizeOf(tester.element(scaffold.first)),
      const Size(1000, 700),
    );
  });
}

PageController pageController(WidgetTester tester) => tester
    .widget<PageView>(find.byKey(const ValueKey('normal_tab_view')))
    .controller!;

MediaQueryData bookMediaQuery(WidgetTester tester, TextBookTab tab) {
  final book = find.byWidgetPredicate(
    (widget) => widget is TextBookViewerBloc && identical(widget.tab, tab),
    skipOffstage: false,
  );
  final scaffold = find.descendant(
    of: book,
    matching: find.byType(Scaffold, skipOffstage: false),
  );
  return MediaQuery.of(tester.element(scaffold.first));
}

ThemeData bookTheme(WidgetTester tester, TextBookTab tab) {
  final book = find.byWidgetPredicate(
    (widget) => widget is TextBookViewerBloc && identical(widget.tab, tab),
    skipOffstage: false,
  );
  final scaffold = find.descendant(
    of: book,
    matching: find.byType(Scaffold, skipOffstage: false),
  );
  return Theme.of(tester.element(scaffold.first));
}

HorizontalDragGestureRecognizer desktopSwipe(WidgetTester tester) {
  final detector = tester.widget<RawGestureDetector>(
    find.byWidgetPredicate(
      (widget) => widget is RawGestureDetector && widget.child is PageView,
    ),
  );
  final factory = detector.gestures[HorizontalDragGestureRecognizer]!;
  final recognizer = factory.constructor() as HorizontalDragGestureRecognizer;
  factory.initializer(recognizer);
  addTearDown(recognizer.dispose);
  return recognizer;
}

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

/// האם האלמנט שייך למסך ספר שבטאב שאינו הפעיל.
bool _isInsideBackgroundBook(Element element) {
  var insideBook = element.widget is TextBookViewerBloc;
  var background = false;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is TextBookViewerBloc) insideBook = true;
    if (widget is ExcludeFocus && widget.key is ObjectKey) {
      background = widget.excluding;
      return false;
    }
    return true;
  });
  return insideBook && background;
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
    content: [for (var i = 0; i < 100; i++) 'שורה $i'],
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
    on<TextBookEvent>((event, emit) {});
  }

  @override
  final TextBookRepository repository = _FakeTextBookRepository();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTextBookRepository extends TextBookRepository {
  _FakeTextBookRepository() : super(fileSystem: FileSystemData.instance);

  @override
  Future<String> getBookContent(TextBook book) async => 'שורה א\nשורה ב';
}

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

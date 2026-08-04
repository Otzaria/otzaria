import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/core/focus_repository.dart';
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
import 'package:otzaria/text_book/view/text_book_screen.dart';
import 'package:otzaria/text_book/view/toc_navigator_screen.dart';
import 'package:otzaria/text_book/view/widgets/nav_panel_tour_target.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../test_helpers/memory_cache_provider.dart';

/// חלונית הניווט של ספר טקסט חייבת לשרוד מעבר בין טאב פעיל לטאב רקע.
///
/// `enableTourTargets` מתהפך בכל מעבר טאב, וכשהוא שינה את מבנה העץ של החלונית
/// Flutter השמיד את כל תת-העץ שלה — ולכן החיפוש-בספר רץ מחדש בכל חזרה לטאב.
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
    activeTextBookNavPanelTourTargetKey = null;
  });

  tearDown(() async {
    await bookmarkBloc.close();
    await personalNotesBloc.close();
    await tourCubit.close();
    focusRepository.resetForTesting();
  });

  /// מעלה את מסך הספר עם חלונית הניווט פתוחה, ומחזיר בקר להחלפת הטאב הפעיל.
  Future<_ActiveTabController> pumpScreen(WidgetTester tester) async {
    final book = TextBook(title: 'ספר בדיקה');
    final bloc = _TestTextBookBloc(_loadedState(book));
    final tab = TextBookTab(book: book, index: 0, blocOverride: bloc);
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
                return TextBookViewerBloc(
                  tab: tab,
                  isInCombinedView: false,
                  enableTourTargets: isActiveTab,
                  openBookCallback: (_) {},
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    return _ActiveTabController(
      tester: tester,
      setActiveTab: (value) => setHostState(() => isActiveTab = value),
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

  testWidgets('יעד הסיור מצביע על חלונית הניווט של הטאב הפעיל', (tester) async {
    final controller = await pumpScreen(tester);

    final key = activeTextBookNavPanelTourTargetKey;
    expect(key, isNotNull);
    expect(
      find.descendant(of: find.byKey(key!), matching: find.byType(TocViewer)),
      findsOneWidget,
    );

    // המפתח נשאר תקף גם אחרי מעבר לרקע וחזרה.
    await controller.setActive(false);
    await controller.setActive(true);

    expect(activeTextBookNavPanelTourTargetKey, isNotNull);
    expect(activeTextBookNavPanelTourTargetKey!.currentContext, isNotNull);
  });
}

class _ActiveTabController {
  _ActiveTabController({required this.tester, required this.setActiveTab});

  final WidgetTester tester;
  final void Function(bool) setActiveTab;

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
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
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

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
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

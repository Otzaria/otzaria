// בחירה בחלונית אחרת של טאב מפוצל אינה משנה את שורת הכרטיסיות, ולכן אינה
// בונה אותה מחדש; שינוי ברשימת הכרטיסיות עדיין מתעדכן בה.
import 'package:otzaria/work_status/work_status_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/window_fullscreen_cubit.dart';
import 'package:otzaria/core/windowing/window_manager_app_window_controller.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/navigation/view/custom_title_bar.dart';
import 'package:otzaria/navigation/view/reading_tab_strip.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';

import '../helpers/memory_settings_cache.dart';
import '../test_helpers/stub_settings_bloc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  testWidgets('החלפת החלונית הפעילה אינה בונה מחדש את שורת הכרטיסיות, '
      'ופתיחת כרטיסיה מתעדכנת בה', (tester) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final right = _makeTextTab('ימין');
    final left = _makeTextTab('שמאל');
    final others = [for (var i = 0; i < 4; i++) _makeTextTab('ספר $i')];
    final extra = _makeTextTab('ספר נוסף');
    final combined = CombinedTab(rightTab: right, leftTab: left);
    final tabsBloc = _TestTabsBloc(
      TabsState(tabs: <OpenedTab>[combined, ...others], currentTabIndex: 0),
    );
    final navigationBloc = _TestNavigationBloc(
      const NavigationState(currentScreen: Screen.reading),
    );
    final settingsBloc = StubSettingsBloc(SettingsState.initial());
    addTearDown(() async {
      debugOnRebuildDirtyWidget = null;
      combined.dispose();
      for (final tab in [...others, extra]) {
        tab.dispose();
      }
      await tabsBloc.close();
      await navigationBloc.close();
      await settingsBloc.close();
    });

    await tester.pumpWidget(
      AppWindowScope(
        controller: const WindowManagerAppWindowController(),
        geometry: const WindowManagerAppWindowController(),
        child: MultiBlocProvider(
          providers: [
            BlocProvider<WorkStatusCubit>(create: (_) => WorkStatusCubit()),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
            BlocProvider<NavigationBloc>.value(value: navigationBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<WindowFullscreenCubit>(
              create: (_) => WindowFullscreenCubit(
                initial: false,
                persist: (_) async {},
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: CustomTitleBar(onReadingSettingsPressed: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    var rebuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      var inStrip = element.widget is ReadingTabStrip;
      element.visitAncestorElements((ancestor) {
        inStrip = inStrip || ancestor.widget is ReadingTabStrip;
        return !inStrip;
      });
      if (inStrip) rebuilds++;
    };
    for (final pane in [left, right, left]) {
      tabsBloc.emit(
        tabsBloc.state.copyWith(activePane: ActivePaneUpdate.set(pane)),
      );
      await tester.pumpAndSettle();
    }
    debugOnRebuildDirtyWidget = null;
    expect(identical(tabsBloc.state.activePane, left), isTrue);
    expect(rebuilds, 0, reason: 'שום דבר ברצועה אינו תלוי בחלונית הפעילה');

    expect(find.text('ספר נוסף'), findsNothing);
    tabsBloc.emit(
      tabsBloc.state.copyWith(
        tabs: [...tabsBloc.state.tabs, extra],
        currentTabIndex: tabsBloc.state.tabs.length,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ספר נוסף'), findsOneWidget);
  });
}

TextBookTab _makeTextTab(String title, {String currentTitle = ''}) {
  final book = TextBook(title: title);
  final bloc = _TestTextBookBloc(
    TextBookLoaded(
      book: book,
      showLeftPane: false,
      content: const ['שורה א'],
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
      removePunctuation: false,
      visibleIndices: const [0],
      selectedIndex: 0,
      pinLeftPane: false,
      searchText: '',
      currentTitle: currentTitle,
    ),
  );
  final tab = TextBookTab(book: book, index: 0, blocOverride: bloc);
  tab.currentTitle.value = currentTitle;
  return tab;
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

  @override
  void add(TabsEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestNavigationBloc extends Cubit<NavigationState>
    implements NavigationBloc {
  _TestNavigationBloc(super.initialState);

  @override
  void add(NavigationEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

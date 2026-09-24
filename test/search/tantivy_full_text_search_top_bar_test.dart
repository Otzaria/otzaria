import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/models/external_search_status.dart';
import 'package:otzaria/search/view/full_text_settings_widgets.dart';
import 'package:otzaria/search/view/tantivy_full_text_search.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';

import '../test_helpers/memory_cache_provider.dart';
import '../support/search_engine_test_init.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _MockTabsBloc extends MockBloc<TabsEvent, TabsState>
    implements TabsBloc {}

class _MockNavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

class _MockIndexingBloc extends MockBloc<IndexingEvent, IndexingState>
    implements IndexingBloc {}

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class _SearchBloc extends SearchBloc {
  _SearchBloc(SearchState state) {
    emit(state);
  }

  @override
  void add(SearchEvent event) {
    if (event is! LoadMoreResults) super.add(event);
  }
}

Future<void> main() async {
  final engineReady = await tryInitSearchEngine();
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Future<void> pumpSearch(
    WidgetTester tester, {
    required double width,
    SearchState state = const SearchState(
      searchQuery: 'בדיקה',
      totalResults: 12,
    ),
    bool externalProvider = true,
  }) async {
    final searchBloc = _SearchBloc(state);
    final settingsBloc = _MockSettingsBloc();
    final tabsBloc = _MockTabsBloc();
    final navigationBloc = _MockNavigationBloc();
    final indexingBloc = _MockIndexingBloc();
    final libraryBloc = _MockLibraryBloc();
    final tab = SearchingTab('חיפוש', '', searchBloc: searchBloc);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 700);
    tab.isLeftPaneOpen.value = false;
    tab.externalSearchStatus.value = externalProvider
        ? const ExternalSearchStatus(
            sourceTitle: 'היברובוקס',
            loading: false,
            books: 3,
            hits: 7,
          )
        : null;

    whenListen(
      settingsBloc,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState.initial(),
    );
    whenListen(
      tabsBloc,
      const Stream<TabsState>.empty(),
      initialState: TabsState(
        tabs: [tab],
        currentTabIndex: 0,
        rawActivePane: tab,
      ),
    );
    whenListen(
      navigationBloc,
      const Stream<NavigationState>.empty(),
      initialState: const NavigationState(currentScreen: Screen.search),
    );
    whenListen(
      indexingBloc,
      const Stream<IndexingState>.empty(),
      initialState: IndexingInitial(),
    );
    whenListen(
      libraryBloc,
      const Stream<LibraryState>.empty(),
      initialState: const LibraryState(),
    );

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tab.dispose();
      await searchBloc.close();
      await settingsBloc.close();
      await tabsBloc.close();
      await navigationBloc.close();
      await indexingBloc.close();
      await libraryBloc.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<SearchBloc>.value(value: searchBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
            BlocProvider<NavigationBloc>.value(value: navigationBloc),
            BlocProvider<IndexingBloc>.value(value: indexingBloc),
            BlocProvider<LibraryBloc>.value(value: libraryBloc),
          ],
          child: Scaffold(
            body: TantivyFullTextSearch(tab: tab),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('הסרגל הרחב שומר ספירות ומיקום של תוצאות חיצוניות', (
    tester,
  ) async {
    if (!engineReady) {
      markTestSkipped(searchEngineSkipReason);
      return;
    }
    await pumpSearch(tester, width: 1200);

    expect(find.textContaining('אוצריא: 0/12'), findsOneWidget);
    expect(find.textContaining('היברובוקס: 3 ספרים'), findsOneWidget);
    expect(find.byType(ExternalResultsPositionControl), findsOneWidget);
    expect(
      tester
          .widget<ExternalResultsPositionControl>(
            find.byType(ExternalResultsPositionControl),
          )
          .compact,
      isFalse,
    );
    expect(find.text('תוצאות מהיברובוקס מאוחרות'), findsOneWidget);
  });

  testWidgets('הסרגל המכווץ שומר על הפקד החיצוני במצב קומפקטי', (
    tester,
  ) async {
    if (!engineReady) {
      markTestSkipped(searchEngineSkipReason);
      return;
    }
    await pumpSearch(tester, width: 850);

    final control = tester.widget<ExternalResultsPositionControl>(
      find.byType(ExternalResultsPositionControl),
    );
    expect(control.compact, isTrue);
    expect(find.textContaining('אוצריא: 0/12'), findsOneWidget);
    expect(find.textContaining('היברובוקס: 3 ספרים'), findsOneWidget);
    final menu = tester.widget<AppPopupMenuButton<bool>>(
      find.descendant(
        of: find.byType(ExternalResultsPositionControl),
        matching: find.byType(AppPopupMenuButton<bool>),
      ),
    );
    expect(menu.tooltip, 'מיקום תוצאות היברובוקס');
  });

  testWidgets('סרגל ברוחב 909 עם ספק חיצוני אינו חורג (Pixel XL landscape)', (
    tester,
  ) async {
    if (!engineReady) {
      markTestSkipped(searchEngineSkipReason);
      return;
    }
    await pumpSearch(tester, width: 909);

    expect(tester.takeException(), isNull);
  });

  testWidgets('סרגל ברוחב 909 בלי ספק חיצוני — שורת מונים אחת ובלי חריגה', (
    tester,
  ) async {
    if (!engineReady) {
      markTestSkipped(searchEngineSkipReason);
      return;
    }
    await pumpSearch(
      tester,
      width: 909,
      externalProvider: false,
      state: const SearchState(
        searchQuery: 'בדיקה',
        totalResults: 12345,
        totalGroups: 4711,
      ),
    );

    expect(tester.takeException(), isNull);
    // בלי maxLines הטקסט נכרך לשתי שורות בתוך סרגל בגובה שורה אחת.
    expect(
      tester.getSize(find.textContaining('תוצאות מאוחדות')).height,
      lessThan(24),
    );
  });

  testWidgets('בלוק המונים תחום ברוחב כשספק חיצוני פעיל (issue #1051)', (
    tester,
  ) async {
    if (!engineReady) {
      markTestSkipped(searchEngineSkipReason);
      return;
    }
    await pumpSearch(
      tester,
      width: 1200,
      state: const SearchState(
        searchQuery: 'בדיקה',
        totalResults: 58,
        totalGroups: 47,
      ),
    );

    final engineText = find.textContaining('אוצריא: 0/47');
    expect(engineText, findsOneWidget);
    final textWidget = tester.widget<Text>(engineText);
    expect(textWidget.maxLines, 1);
    expect(textWidget.overflow, TextOverflow.ellipsis);
    expect(tester.getSize(engineText).width, lessThanOrEqualTo(240));
    expect(
      tester.getSize(find.textContaining('היברובוקס: 3 ספרים')).width,
      lessThanOrEqualTo(240),
    );
  });

  testWidgets('הטאב ממקד את התוכן שלו כששדה החיפוש אינו מוצג (issue #1349)', (
    tester,
  ) async {
    if (!engineReady) {
      markTestSkipped(searchEngineSkipReason);
      return;
    }
    // אחרי תוסף הפוקוס "חונה" בשורש — כך מדמים את המצב שב-WebView.
    FocusManager.instance.rootScope.requestScopeFocus();
    await pumpSearch(tester, width: 1200);
    await tester.pump();

    final primary = FocusManager.instance.primaryFocus;
    expect(primary?.debugLabel, 'search_tab_content');
  });

  testWidgets('סרגל ברוחב 411 שומר רוחב מזערי למילות החיפוש', (tester) async {
    if (!engineReady) {
      markTestSkipped(searchEngineSkipReason);
      return;
    }
    await pumpSearch(
      tester,
      width: 411,
      externalProvider: false,
      state: const SearchState(
        searchQuery: 'ברכת המזון',
        totalResults: 5957,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(OtzariaSearchDisplayBar)).width,
      greaterThanOrEqualTo(80),
    );
  });
}

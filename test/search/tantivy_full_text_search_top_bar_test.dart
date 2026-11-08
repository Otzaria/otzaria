import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/plugins/services/plugin_search_dialog_registry.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/models/external_search_status.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/view/full_text_settings_widgets.dart';
import 'package:otzaria/search/view/search_navigation_tree.dart';
import 'package:otzaria/search/view/search_results_layout.dart';
import 'package:otzaria/search/view/tantivy_search_results.dart';
import 'package:otzaria/search/view/plugin_search_results_actions.dart';
import 'package:otzaria/search/view/tantivy_full_text_search.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/widgets/misc/app_dropdown_field.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show ResultsOrder, SearchResult, TextStatus;

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

  void publish(SearchState state) => emit(state);

  @override
  void add(SearchEvent event) {
    if (event is! LoadMoreResults) super.add(event);
  }
}

/// כפתורי הסרגל בלבד: גוף המסך (מצב ריק, אחרי התוצאות) מציג את אותו ווידג'ט
/// בתצוגה inline, גם הוא מופיע בעץ כשהוא ריק.
final _barActions = find.byWidgetPredicate(
  (widget) =>
      widget is PluginSearchResultsActions &&
      widget.layout == PluginSearchResultsActionsLayout.bar,
);
final _barButton = find.descendant(
  of: _barActions,
  matching: find.text('המשך בתוסף'),
);

Future<void> main() async {
  final engineReady = await tryInitSearchEngine();
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Future<_SearchBloc> pumpSearch(
    WidgetTester tester, {
    required double width,
    SearchState state = const SearchState(
      searchQuery: 'בדיקה',
      totalResults: 12,
    ),
    bool externalProvider = true,
    LibraryState libraryState = const LibraryState(),
    bool showFacetPane = false,
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
    tab.isLeftPaneOpen.value = showFacetPane;
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
      initialState: libraryState,
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
          child: Scaffold(body: TantivyFullTextSearch(tab: tab)),
        ),
      ),
    );
    await tester.pump();
    return searchBloc;
  }

  testWidgets('ספירה שטרם הושלמה אינה מציגה אפס כספירה סופית', (
    tester,
  ) async {
    await pumpSearch(
      tester,
      width: 1400,
      externalProvider: false,
      state: const SearchState(
        searchQuery: 'בדיקה',
        isLoading: true,
        isCounting: true,
      ),
    );
    expect(find.text('0 תוצאות (הספירה מתעדכנת)'), findsOneWidget);
    expect(find.text('0/0 תוצאות'), findsNothing);
  });

  for (final width in [1400.0, 700.0]) {
    testWidgets('התוצאות מונחות על רקע הלוח של הכלים (רוחב $width)', (
      tester,
    ) async {
      await pumpSearch(tester, width: width, externalProvider: false);

      final layout = find.byType(SearchResultsLayout);
      final backdrop = AppSurfaces.panelBackground(tester.element(layout));
      expect(
        find.descendant(
          of: layout,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                (widget.decoration as BoxDecoration?)?.color == backdrop,
          ),
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets('הרקע מאחורי התוצאות נבדל מכרטיס התוצאה בבהיר ובכהה', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: brightness,
            ),
          ),
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(
        AppSurfaces.panelBackground(context),
        isNot(AppSurfaces.card(context)),
        reason: '$brightness',
      );
    }
  });

  testWidgets('פעימות מונים במסך האמיתי אינן בונות שוב את עץ הסינון', (
    tester,
  ) async {
    if (!engineReady) {
      markTestSkipped(searchEngineSkipReason);
      return;
    }
    final category = Category(
      title: 'תנ"ך',
      description: '',
      shortDescription: '',
      order: 1,
      subCategories: const [],
      books: [TextBook(id: 7, title: 'תהילים', categoryPath: '/תנ"ך')],
      parent: null,
    );
    final library = Library(categories: [category]);
    category.parent = library;
    final searchBloc = await pumpSearch(
      tester,
      width: 1200,
      externalProvider: false,
      showFacetPane: true,
      libraryState: LibraryState(library: library, isLoading: false),
      state: const SearchState(
        searchQuery: 'בדיקה',
        facetCounts: {'/': 5, '/תנ"ך': 5, '/תנ"ך/id:7': 5},
      ),
    );
    final treeFinder = find.byType(SearchNavigationTree);
    final tree = tester.widget<SearchNavigationTree>(treeFinder);

    searchBloc.publish(searchBloc.state.copyWith(totalResults: 123));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('0/123'), findsOneWidget);
    expect(identical(tester.widget(treeFinder), tree), isTrue);

    final counts = {'/': 2, '/תנ"ך': 2, '/תנ"ך/id:7': 2};
    searchBloc.publish(searchBloc.state.copyWith(facetCounts: counts));
    await tester.pump();
    await tester.pump();
    expect(tester.widget<SearchNavigationTree>(treeFinder).facetCounts, counts);
    expect(identical(tester.widget(treeFinder), tree), isFalse);
  });

  for (final width in [1200.0, 700.0]) {
    testWidgets('"איתור ספר" וספירות העץ אינם בונים את המסך (רוחב $width)', (
      tester,
    ) async {
      if (!engineReady) {
        markTestSkipped(searchEngineSkipReason);
        return;
      }
      SearchResult result(int i) => SearchResult(
        id: BigInt.from(i),
        title: 'ספר $i',
        reference: 'ספר $i, א',
        text: 'טקסט <b>בדיקה</b> $i',
        segment: BigInt.from(i),
        isPdf: false,
        filePath: 'book_$i.txt',
        mergedCount: 1,
        merged: const [],
        textStatus: TextStatus.ok,
        continuesToNextLine: false,
      );
      final searchBloc = await pumpSearch(
        tester,
        width: width,
        externalProvider: false,
        state: SearchState(
          searchQuery: 'בדיקה',
          results: [result(1), result(2)],
          totalResults: 3,
        ),
      );
      final parts = {
        'layout': find.byType(SearchResultsLayout),
        'counts': find.textContaining('2/3'),
        'card': find.byType(SearchResultOpenInNewTabRegion).first,
        'terms': find
            .descendant(
              of: find.byType(SearchTermsDisplay),
              matching: find.byType(RichText),
            )
            .first,
        'order': find.descendant(
          of: find.byType(OrderOfResults),
          matching: find.byWidgetPredicate(
            (w) =>
                w is AppDropdownField<ResultsOrder> ||
                w is AppPopupMenuButton<ResultsOrder>,
          ),
        ),
        'grouping': find.descendant(
          of: find.byType(GroupingOfResults),
          matching: find.byWidgetPredicate(
            (w) =>
                w is AppDropdownField<ResultGroupingMode> ||
                w is AppPopupMenuButton<ResultGroupingMode>,
          ),
        ),
      };
      final before = {
        for (final e in parts.entries) e.key: tester.widget(e.value),
      };
      void expectNotRebuilt(Iterable<String> names) {
        for (final name in names) {
          expect(
            identical(tester.widget(parts[name]!), before[name]),
            isTrue,
            reason: '$name נבנה מחדש',
          );
        }
      }

      searchBloc.add(UpdateFilterQuery('תה'));
      await tester.pump();
      await tester.pump();
      searchBloc.publish(searchBloc.state.copyWith(facetCounts: {'/': 3}));
      await tester.pump();
      await tester.pump();
      expectNotRebuilt(parts.keys);

      // אצוות תוצאות: הרשימה והמונים מתעדכנים, הסרגל נשאר.
      searchBloc.publish(
        searchBloc.state.copyWith(results: [result(1), result(2), result(3)]),
      );
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('3/3'), findsOneWidget);
      expect(find.byType(SearchResultOpenInNewTabRegion), findsNWidgets(3));
      expectNotRebuilt(['layout', 'terms', 'order', 'grouping']);
    });
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

  testWidgets('הסרגל המכווץ שומר על הפקד החיצוני במצב קומפקטי', (tester) async {
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

  testWidgets('פעולת תוסף נוספת ומוסרת מהסרגל הפתוח בלי פריט ריק', (
    tester,
  ) async {
    final registry = PluginSearchDialogRegistry.instance;
    addTearDown(() => registry.removeAll('topbar.test'));
    final searchBloc = await pumpSearch(tester, width: 909);
    expect(_barActions, findsNothing);
    registry.registerPayload('topbar.test', {
      'id': 'continue',
      'type': 'checkbox',
      'title': 'המשך',
      'openPluginOnSubmit': true,
      'resultsAction': 'המשך בתוסף',
      'visibleInModes': ['advanced'],
    });
    await tester.pump();
    expect(_barButton, findsOneWidget);
    expect(tester.takeException(), isNull);
    final completed = searchBloc.state;
    for (final hidden in [
      completed.copyWith(isLoading: true),
      completed.copyWith(
        configuration: completed.configuration.copyWith(
          searchMode: SearchMode.exact,
        ),
      ),
      completed.copyWith(errorMessage: 'נכשל'),
    ]) {
      searchBloc.publish(hidden);
      await tester.pump();
      await tester.pump();
      expect(_barActions, findsNothing);
      expect(tester.takeException(), isNull);
      searchBloc.publish(completed);
      await tester.pump();
      await tester.pump();
      expect(
        _barButton,
        findsOneWidget,
        reason:
            'return from loading=${hidden.isLoading}, mode=${hidden.configuration.searchMode}, error=${hidden.errorMessage}',
      );
      expect(tester.takeException(), isNull);
    }
    registry.removeAll('topbar.test');
    await tester.pump();
    expect(_barActions, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'טעינת המשך שומרת את פריט הסרגל, וספירה בעיצומה מסירה אותו',
    (tester) async {
      final registry = PluginSearchDialogRegistry.instance;
      addTearDown(() => registry.removeAll('topbar.loadmore'));
      registry.registerPayload('topbar.loadmore', {
        'id': 'continue',
        'type': 'checkbox',
        'title': 'המשך',
        'openPluginOnSubmit': true,
        'resultsAction': 'המשך בתוסף',
      });
      final searchBloc = await pumpSearch(tester, width: 909);
      final withResults = searchBloc.state.copyWith(
        results: [
          SearchResult(
            id: BigInt.one,
            title: 'ספר',
            reference: 'סימן',
            text: 'טקסט',
            segment: BigInt.zero,
            isPdf: false,
            filePath: 'book.txt',
            mergedCount: 1,
            merged: const [],
            textStatus: TextStatus.ok,
            continuesToNextLine: false,
          ),
        ],
      );
      Future<void> publish(SearchState state) async {
        searchBloc.publish(state);
        await tester.pump();
        await tester.pump();
      }

      await publish(withResults);
      expect(_barButton, findsOneWidget);

      // עמוד נוסף נטען: תוצאות כבר מוצגות, בלי ספירה. הפריט נשאר במקומו.
      await publish(withResults.copyWith(isLoading: true));
      expect(_barButton, findsOneWidget);
      expect(tester.takeException(), isNull);

      // חיפוש ראשוני שהספירה שלו בעיצומה: עדיין אין מה להציג.
      await publish(withResults.copyWith(isLoading: true, isCounting: true));
      expect(_barActions, findsNothing);
      expect(tester.takeException(), isNull);

      await publish(withResults);
      expect(_barButton, findsOneWidget);
    },
  );

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
      state: const SearchState(searchQuery: 'ברכת המזון', totalResults: 5957),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(OtzariaSearchDisplayBar)).width,
      greaterThanOrEqualTo(80),
    );
  });
}

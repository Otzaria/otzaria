import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/repository/app_report_collector.dart';
import 'package:otzaria/core/diagnostics/developer_diagnostics.dart';
import 'package:otzaria/core/diagnostics/frame_stats_overlay.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/utils/search_results_report.dart';
import 'package:otzaria/semantic_search/models/semantic_result_item.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/semantic_search_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';

import '../helpers/memory_settings_cache.dart';

class _FakeWindow extends Fake
    implements AppWindowController, AppWindowGeometry {}

void main() {
  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    DeveloperDiagnostics.instance.resetForTesting();
    AppWindowKeys.resetForTest();
  });
  tearDown(() {
    DeveloperDiagnostics.instance.resetForTesting();
    AppWindowKeys.resetForTest();
  });

  for (final semantic in [false, true]) {
    testWidgets(
      'דוח חיפוש ${semantic ? "חכם" : "רגיל"} עוקב אחרי החלונית הפעילה',
      (
        tester,
      ) async {
        final search = semantic
            ? SemanticSearchTab(
                options: const SemanticQueryOptions(query: 'שאילתה פרטית'),
                createResultsBloc: (_) => throw StateError('must stay lazy'),
              )
            : SearchingTab('חיפוש', 'שאילתה פרטית');
        final book = TextBookTab(book: TextBook(title: 'ספר', id: 7), index: 0);
        addTearDown(search.dispose);
        addTearDown(book.dispose);
        var tabs = TabsState(tabs: [search], currentTabIndex: 0);
        await tester.pumpWidget(
          MaterialApp(
            home: FrameStatsOverlay(
              searchResultsProvider: () => describeSearchResults(tabs),
              child: const SizedBox(),
            ),
          ),
        );
        final collector = AppReportCollector(appInfoLoader: () async => {});
        final single = (await collector.collectDiagnostics())['searchResults'];
        expect(single, containsPair('kind', semantic ? 'semantic' : 'lexical'));
        expect(single.toString(), isNot(contains('שאילתה פרטית')));

        final split = CombinedTab(rightTab: book, leftTab: search);
        tabs = TabsState(
          tabs: [split],
          currentTabIndex: 0,
          rawActivePane: search,
        );
        expect(tabs.activePane, same(search));
        expect((await collector.collectDiagnostics())['searchResults'], single);

        tabs = tabs.copyWith(activePane: ActivePaneUpdate.set(book));
        expect(
          (await collector.collectDiagnostics()).containsKey('searchResults'),
          isFalse,
        );
        tabs = tabs.copyWith(activePane: ActivePaneUpdate.set(search));
        expect((await collector.collectDiagnostics())['searchResults'], single);
        tabs = tabs.copyWith(activePane: const ActivePaneUpdate.clear());
        expect(tabs.activePane, same(book));
        expect(
          (await collector.collectDiagnostics()).containsKey('searchResults'),
          isFalse,
        );
        if (search is SemanticSearchTab) {
          expect(search.createdResultsBloc, isNull);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('דוח בוחר חלון פעיל ודוח קודם אינו קורא את ספק החיפוש', (
    tester,
  ) async {
    final first = AppWindowKeys();
    final second = AppWindowKeys(id: AppWindowId('view:2'));
    AppWindowKeys.register(first);
    AppWindowKeys.register(second);
    final lexical = SearchingTab('חיפוש', null);
    final semantic = SemanticSearchTab(
      options: const SemanticQueryOptions(query: 'שאילתה פרטית'),
      createResultsBloc: (_) => throw StateError('must stay lazy'),
    );
    addTearDown(lexical.dispose);
    addTearDown(semantic.dispose);
    final firstTabs = TabsState(tabs: [lexical], currentTabIndex: 0);
    final secondTabs = TabsState(
      tabs: [CombinedTab(rightTab: lexical, leftTab: semantic)],
      currentTabIndex: 0,
      rawActivePane: semantic,
    );
    var providerCalls = 0;
    Widget window(AppWindowKeys keys, TabsState tabs) => AppWindowScope(
      controller: _FakeWindow(),
      geometry: _FakeWindow(),
      keys: keys,
      child: FrameStatsOverlay(
        searchResultsProvider: () {
          providerCalls++;
          return describeSearchResults(tabs);
        },
        child: const SizedBox(),
      ),
    );
    AppWindowKeys.activate(first);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [window(first, firstTabs), window(second, secondTabs)],
        ),
      ),
    );
    final collector = AppReportCollector(appInfoLoader: () async => {});
    expect(
      await collector.collectDiagnostics(),
      containsPair('searchResults', containsPair('kind', 'lexical')),
    );
    AppWindowKeys.activate(second);
    expect(
      await collector.collectDiagnostics(),
      containsPair('searchResults', containsPair('kind', 'semantic')),
    );
    AppWindowKeys.activate(first);
    expect(
      await collector.collectDiagnostics(),
      containsPair('searchResults', containsPair('kind', 'lexical')),
    );

    final callsBeforePreviousReport = providerCalls;
    final saved = {
      'context': {'screen': 'reading'},
      'searches': {'activeCount': 0},
    };
    final previous = await AppReportCollector(
      appInfoLoader: () async => {},
      includeCurrentContext: false,
      previousRunContext: () async => saved,
    ).collectDiagnostics();
    expect(previous['previousRun'], saved);
    expect(previous.containsKey('searchResults'), isFalse);
    expect(previous.containsKey('recentBookOpens'), isFalse);
    expect(providerCalls, callsBeforePreviousReport);
    expect(semantic.createdResultsBloc, isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

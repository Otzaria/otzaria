import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';

import '../support/search_engine_test_init.dart';
import '../test_helpers/memory_cache_provider.dart';

class _HistoryBloc extends MockBloc<HistoryEvent, HistoryState>
    implements HistoryBloc {}

class _IndexingBloc extends MockBloc<IndexingEvent, IndexingState>
    implements IndexingBloc {}

class _LibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class _NavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

class _TabsBloc extends MockBloc<TabsEvent, TabsState> implements TabsBloc {}

class _TabsEvent extends Fake implements TabsEvent {}

class _HistoryEvent extends Fake implements HistoryEvent {}

Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  setUpAll(() {
    registerFallbackValue(_TabsEvent());
    registerFallbackValue(_HistoryEvent());
  });

  testWidgets(
    'הגשת שאילתה ארוכה מקצרת רק את כותרת הטאב ושומרת את החיפוש המלא',
    (tester) async {
      await Settings.init(cacheProvider: MemoryCacheProvider());
      final historyBloc = _HistoryBloc();
      final indexingBloc = _IndexingBloc();
      final libraryBloc = _LibraryBloc();
      final navigationBloc = _NavigationBloc();
      final tabsBloc = _TabsBloc();
      whenListen(
        historyBloc,
        const Stream<HistoryState>.empty(),
        initialState: HistoryLoaded([]),
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
      whenListen(
        navigationBloc,
        const Stream<NavigationState>.empty(),
        initialState: const NavigationState(currentScreen: Screen.search),
      );
      whenListen(
        tabsBloc,
        const Stream<TabsState>.empty(),
        initialState: const TabsState(tabs: [], currentTabIndex: 0),
      );
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
        await historyBloc.close();
        await indexingBloc.close();
        await libraryBloc.close();
        await navigationBloc.close();
        await tabsBloc.close();
      });

      await tester.binding.setSurfaceSize(const Size(1400, 900));
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<HistoryBloc>.value(value: historyBloc),
            BlocProvider<IndexingBloc>.value(value: indexingBloc),
            BlocProvider<LibraryBloc>.value(value: libraryBloc),
            BlocProvider<NavigationBloc>.value(value: navigationBloc),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) =>
                        const SearchDialog(initialSearchMode: SearchMode.exact),
                  ),
                  child: const Text('פתח'),
                ),
              ),
            ),
          ),
        ),
      );

      final query = List.filled(5000, 'בראשית').join(' ');
      await tester.tap(find.text('פתח'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '  $query  ');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('חפש'));
      await tester.pumpAndSettle();

      final events = verify(() => tabsBloc.add(captureAny())).captured;
      final tab = events.whereType<AddTab>().single.tab as SearchingTab;
      addTearDown(tab.dispose);
      expect(find.byType(SearchDialog), findsNothing);
      expect(tab.title.runes.length, lessThan(120));
      expect(tab.title, SearchingTab.titleForQuery(query));
      expect(tab.titleNotifier.value, tab.title);
      expect(tab.queryController.text, query);
      expect(tab.searchBloc.state.searchQuery, query);
      expect(tab.toJson()['searchText'], query);

      final history = verify(() => historyBloc.add(captureAny())).captured;
      expect(history.whereType<AddHistory>().single.tab, same(tab));
    },
    skip: !engineReady,
  );
}

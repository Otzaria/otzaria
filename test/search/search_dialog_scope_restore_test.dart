import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
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
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_scope_preferences.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/search/view/search_scope_menu.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';

import '../test_helpers/memory_cache_provider.dart';
import '../support/search_engine_test_init.dart';

class _MockHistoryBloc extends MockBloc<HistoryEvent, HistoryState>
    implements HistoryBloc {}

class _MockIndexingBloc extends MockBloc<IndexingEvent, IndexingState>
    implements IndexingBloc {}

class _MockNavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

Library _buildLibrary() {
  final cat = Category(
    title: 'תנ״ך',
    description: '',
    shortDescription: '',
    order: 10,
    subCategories: [],
    books: [TextBook(title: 'בראשית', categoryPath: '/תנ״ך')],
    parent: null,
  );
  final library = Library(categories: [cat]);
  cat.parent = library;
  return library;
}

Future<void> main() async {
  final engineReady = await tryInitSearchEngine();
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Future<void> pumpDialog(
    WidgetTester tester, {
    SearchingTab? editTab,
  }) async {
    final historyBloc = _MockHistoryBloc();
    final indexingBloc = _MockIndexingBloc();
    final navigationBloc = _MockNavigationBloc();
    final libraryBloc = _MockLibraryBloc();

    whenListen(
      historyBloc,
      const Stream<HistoryState>.empty(),
      initialState: HistoryLoaded(const []),
    );
    whenListen(
      indexingBloc,
      const Stream<IndexingState>.empty(),
      initialState: IndexingInitial(),
    );
    whenListen(
      navigationBloc,
      const Stream<NavigationState>.empty(),
      initialState: const NavigationState(currentScreen: Screen.search),
    );
    whenListen(
      libraryBloc,
      const Stream<LibraryState>.empty(),
      initialState: LibraryState(library: _buildLibrary()),
    );

    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      await historyBloc.close();
      await indexingBloc.close();
      await navigationBloc.close();
      await libraryBloc.close();
    });

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: MultiBlocProvider(
          providers: [
            BlocProvider<HistoryBloc>.value(value: historyBloc),
            BlocProvider<IndexingBloc>.value(value: indexingBloc),
            BlocProvider<NavigationBloc>.value(value: navigationBloc),
            BlocProvider<LibraryBloc>.value(value: libraryBloc),
          ],
          child: Scaffold(body: SearchDialog(editTab: editTab)),
        ),
      ),
    );
    await tester.pump();
  }

  Set<String> currentScope(WidgetTester tester) => tester
      .widget<SearchScopeMenuButton>(
        find.byType(SearchScopeMenuButton),
      )
      .selected;

  group('שחזור היקף החיפוש בדיאלוג חדש', () {
    testWidgets('בחירת ספרים שמורה עולה מסומנת בדיאלוג חיפוש חדש', (
      tester,
    ) async {
      await SearchScopePreferences.save(
        searchAllCategories: false,
        manualFacets: {'/תנ״ך/בראשית'},
      );
      await SearchScopePreferences.saveDimensionFacets(const {});

      await pumpDialog(tester);

      expect(currentScope(tester), contains('/תנ״ך/בראשית'));
      expect(currentScope(tester), isNot(contains('/')));
    });

    testWidgets('בחירת מחבר שמורה (facet ממדי) משוחזרת בדיאלוג חדש', (
      tester,
    ) async {
      final authorFacet = FacetHelper.buildAuthorFacet('רש״י');
      await SearchScopePreferences.save(
        searchAllCategories: true,
        manualFacets: const {},
      );
      await SearchScopePreferences.saveDimensionFacets({authorFacet});

      await pumpDialog(tester);

      expect(currentScope(tester), contains(authorFacet));
    });

    testWidgets('"חפש בהכל" שמור עולה כברירת מחדל', (tester) async {
      await SearchScopePreferences.save(
        searchAllCategories: true,
        manualFacets: const {},
      );
      await SearchScopePreferences.saveDimensionFacets(const {});

      await pumpDialog(tester);

      expect(currentScope(tester), {'/'});
    });

    testWidgets('טאב בעריכה גובר על ההעדפה השמורה', (tester) async {
      if (!engineReady) {
        markTestSkipped(searchEngineSkipReason);
        return;
      }
      await SearchScopePreferences.save(
        searchAllCategories: false,
        manualFacets: {'/תנ״ך/בראשית'},
      );

      final editTab = SearchingTab(
        'חיפוש',
        'בדיקה',
        initialConfiguration: const SearchConfiguration(
          currentFacets: ['/מדרש'],
          searchScopeFacets: ['/מדרש'],
        ),
      );
      addTearDown(editTab.dispose);

      await pumpDialog(tester, editTab: editTab);

      expect(currentScope(tester), contains('/מדרש'));
      expect(currentScope(tester), isNot(contains('/תנ״ך/בראשית')));
    });
  });
}

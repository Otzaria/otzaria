import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
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
import 'package:otzaria/search/search_scope_preferences.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/search/view/search_history_menu.dart';
import 'package:otzaria/search/view/search_scope_menu.dart';

import '../test_helpers/memory_cache_provider.dart';

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
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Future<void> pumpDialog(WidgetTester tester, List<Bookmark> history) async {
    final historyBloc = _MockHistoryBloc();
    final indexingBloc = _MockIndexingBloc();
    final navigationBloc = _MockNavigationBloc();
    final libraryBloc = _MockLibraryBloc();

    whenListen(
      historyBloc,
      const Stream<HistoryState>.empty(),
      initialState: HistoryLoaded(history),
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
          child: const Scaffold(body: SearchDialog()),
        ),
      ),
    );
    await tester.pump();
  }

  Set<String> currentScope(WidgetTester tester) => tester
      .widget<SearchScopeMenuButton>(find.byType(SearchScopeMenuButton))
      .selected;

  // issue #4067: בחירת חיפוש מתפריט ההיסטוריה שבדיאלוג משחזרת גם את היקף
  // החיפוש שנשמר איתו, ולא רק את השאילתה.
  testWidgets('בחירה מתפריט ההיסטוריה משחזרת את היקף החיפוש השמור', (
    tester,
  ) async {
    await SearchScopePreferences.save(
      searchAllCategories: true,
      manualFacets: const {},
    );
    await SearchScopePreferences.saveDimensionFacets(const {});

    await pumpDialog(tester, [
      Bookmark(
        ref: 'ממון מזיק',
        book: TextBook(title: 'ממון מזיק'),
        index: 0,
        isSearch: true,
        searchScopeFacets: const ['/תנ״ך/בראשית'],
      ),
    ]);
    expect(currentScope(tester), {'/'});

    await tester.tap(find.byTooltip('היסטוריית חיפושים'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(searchHistoryMenuKey),
        matching: find.text('ממון מזיק'),
      ),
    );
    await tester.pumpAndSettle();

    expect(currentScope(tester), {'/תנ״ך/בראשית'});
  });

  testWidgets('חיפוש מכל הספרייה מההיסטוריה מאפס היקף מצומצם שמור', (
    tester,
  ) async {
    await SearchScopePreferences.save(
      searchAllCategories: false,
      manualFacets: {'/תנ״ך/בראשית'},
    );
    await SearchScopePreferences.saveDimensionFacets(const {});

    await pumpDialog(tester, [
      Bookmark(
        ref: 'ממון מזיק',
        book: TextBook(title: 'ממון מזיק'),
        index: 0,
        isSearch: true,
      ),
    ]);
    expect(currentScope(tester), {'/תנ״ך/בראשית'});

    await tester.tap(find.byTooltip('היסטוריית חיפושים'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(searchHistoryMenuKey),
        matching: find.text('ממון מזיק'),
      ),
    );
    await tester.pumpAndSettle();

    expect(currentScope(tester), {'/'});
  });
}

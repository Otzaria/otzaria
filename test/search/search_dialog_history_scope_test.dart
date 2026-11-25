import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/search/active_lexical_searches.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
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
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SearchScope, WordMatchMode;

import '../support/search_engine_test_init.dart';
import '../test_helpers/memory_cache_provider.dart';

class _MockHistoryBloc extends MockBloc<HistoryEvent, HistoryState>
    implements HistoryBloc {}

class _MockIndexingBloc extends MockBloc<IndexingEvent, IndexingState>
    implements IndexingBloc {}

class _MockNavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class _MockTabsBloc extends MockBloc<TabsEvent, TabsState>
    implements TabsBloc {}

class _TabsEvent extends Fake implements TabsEvent {}

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
    registerFallbackValue(_TabsEvent());
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Future<TabsBloc> pumpDialog(
    WidgetTester tester,
    List<Bookmark> history, {
    SearchingTab? editTab,
  }) async {
    final tabsBloc = _MockTabsBloc();
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
      await tabsBloc.close();
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
            BlocProvider<TabsBloc>.value(value: tabsBloc),
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
    return tabsBloc;
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
  for (final (editTab, editScope, typedCategory, filter) in [
    (false, false, false, const ['/group/book']),
    (false, true, false, const ['/group/book']),
    (false, false, true, const ['/group/book']),
    (true, false, false, const <String>[]),
  ]) {
    testWidgets(
      'הגשה מההיסטוריה, עריכת טאב: $editTab, היקף: $editScope, '
      'קטגוריה מפורשת: $typedCategory, מסנן: $filter',
      (tester) async {
        final previousSearches = ActiveLexicalSearches.instance;
        addTearDown(() => ActiveLexicalSearches.instance = previousSearches);
        ActiveLexicalSearches.instance = ActiveLexicalSearches(
          stallThreshold: null,
        );
        final target = editTab
            ? SearchingTab(
                'קודם',
                'קודם',
                initialConfiguration: const SearchConfiguration(
                  searchMode: SearchMode.exact,
                  currentFacets: ['/old/book'],
                  searchScopeFacets: ['/old'],
                ),
              )
            : null;
        if (target != null) addTearDown(target.dispose);
        final tabsBloc = await pumpDialog(
          tester,
          [
            Bookmark(
              ref: 'בדיקה',
              book: TextBook(title: 'בדיקה אחת נוספת'),
              index: 0,
              isSearch: true,
              searchMode: SearchMode.advanced,
              distance: 6,
              proximityScope: SearchScope.sameSection,
              searchConfiguration: const SearchConfiguration(
                distance: 6,
                wordMatchMode: WordMatchMode.atLeast,
                wordMatchCount: 3,
                anyOrder: true,
              ).toMap(),
              searchFilterFacets: filter,
              negativeSearchText: 'לדלג תמיד',
              negativeSearchOptions: const {
                'לדלג_0': {'קידומות דקדוקיות': true},
              },
              negativeAlternativeWords: const {
                0: ['להחסיר'],
              },
              negativeSpacingValues: const {'0-1': '2'},
            ),
          ],
          editTab: target,
        );
        await tester.tap(find.byTooltip('היסטוריית חיפושים'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byKey(searchHistoryMenuKey),
            matching: find.text('בדיקה'),
          ),
        );
        await tester.pumpAndSettle();
        expect(currentScope(tester), {'/'});
        if (editScope) {
          tester
              .widget<SearchScopeMenuButton>(find.byType(SearchScopeMenuButton))
              .onChanged({'/other'});
          await tester.pump();
        }
        if (typedCategory) {
          await tester.enterText(
            find.byType(EditableText).first,
            'בדיקה אחת נוספת @תנ״ך',
          );
          await tester.pump();
        }
        await tester.tap(find.byTooltip('חפש'));
        await tester.pump();
        final tab =
            target ??
            (verify(
                  () => tabsBloc.add(captureAny()),
                ).captured.whereType<AddTab>().single.tab
                as SearchingTab);
        if (target == null) addTearDown(tab.dispose);
        final scope = editScope
            ? ['/other']
            : typedCategory
            ? ['/תנ״ך']
            : ['/'];
        expect(
          tab.searchBloc.state.searchScopeFacets,
          scope,
        );
        expect(
          tab.searchBloc.state.currentFacets,
          editScope || typedCategory ? scope : filter,
        );
        expect(tab.searchBloc.state.negativeQuery, 'לדלג תמיד');
        expect(tab.negativeSearchOptions, {
          'לדלג_0': {'קידומות דקדוקיות': true},
        });
        expect(tab.negativeAlternativeWords, {
          0: ['להחסיר'],
        });
        expect(tab.negativeSpacingValues, {'0-1': '2'});
        final configuration = tab.searchBloc.state.configuration;
        expect(configuration.searchMode, SearchMode.advanced);
        expect(configuration.distance, 6);
        expect(configuration.proximityScope, SearchScope.sameSection);
        expect(configuration.wordMatchMode, WordMatchMode.atLeast);
        expect(configuration.wordMatchCount, 3);
        expect(configuration.anyOrder, isTrue);
      },
      skip: !engineReady,
    );
  }

  testWidgets('הצ׳יפים של חיפוש מדויק משקפים אפשרויות משוחזרות', (
    tester,
  ) async {
    await pumpDialog(tester, [
      Bookmark(
        ref: 'בדיקה',
        book: TextBook(title: 'בדיקה נוספת'),
        index: 0,
        isSearch: true,
        searchMode: SearchMode.exact,
        searchOptions: const {
          'בדיקה_0': {'קידומות דקדוקיות': true, 'סיומות דקדוקיות': true},
          'נוספת_1': {'קידומות דקדוקיות': true, 'סיומות דקדוקיות': true},
        },
      ),
    ]);
    await tester.tap(find.byTooltip('היסטוריית חיפושים'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(searchHistoryMenuKey),
        matching: find.text('בדיקה'),
      ),
    );
    await tester.pumpAndSettle();

    FilterChip chip(String label) => tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, label),
    );
    expect(chip('קידומות דקדוקיות').selected, isTrue);
    expect(chip('סיומות דקדוקיות').selected, isTrue);
    await tester.tap(find.widgetWithText(FilterChip, 'קידומות דקדוקיות'));
    await tester.pump();
    expect(chip('קידומות דקדוקיות').selected, isFalse);
    expect(chip('סיומות דקדוקיות').selected, isTrue);
  }, skip: !engineReady);
}

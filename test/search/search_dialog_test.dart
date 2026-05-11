import 'package:bloc_test/bloc_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_spinbox/flutter_spinbox.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import '../test_helpers/memory_cache_provider.dart';

class MockHistoryBloc extends MockBloc<HistoryEvent, HistoryState>
    implements HistoryBloc {}

class MockIndexingBloc extends MockBloc<IndexingEvent, IndexingState>
    implements IndexingBloc {}

class MockNavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

Widget _buildDialogHarness({
  required ThemeData theme,
  required HistoryBloc historyBloc,
  required IndexingBloc indexingBloc,
  required NavigationBloc navigationBloc,
  required SearchDialog dialog,
}) {
  return MaterialApp(
    theme: theme,
    home: MultiBlocProvider(
      providers: [
        BlocProvider<HistoryBloc>.value(value: historyBloc),
        BlocProvider<IndexingBloc>.value(value: indexingBloc),
        BlocProvider<NavigationBloc>.value(value: navigationBloc),
      ],
      child: Scaffold(body: dialog),
    ),
  );
}

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets('מגירת ההיסטוריה משתמשת ברקע של הדיאלוג',
      (WidgetTester tester) async {
    final historyBloc = MockHistoryBloc();
    final indexingBloc = MockIndexingBloc();
    final navigationBloc = MockNavigationBloc();
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFB85C38),
      ),
    );

    whenListen(
      historyBloc,
      const Stream<HistoryState>.empty(),
      initialState: HistoryLoaded([
        Bookmark(
          ref: 'משה',
          book: TextBook(title: 'משה'),
          index: 0,
          isSearch: true,
        ),
      ]),
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

    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      await historyBloc.close();
      await indexingBloc.close();
      await navigationBloc.close();
    });

    await tester.binding.setSurfaceSize(const Size(1400, 900));

    await tester.pumpWidget(_buildDialogHarness(
      theme: theme,
      historyBloc: historyBloc,
      indexingBloc: indexingBloc,
      navigationBloc: navigationBloc,
      dialog: const SearchDialog(),
    ));

    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byIcon(FluentIcons.history_24_regular));
    await tester.tap(find.byIcon(FluentIcons.history_24_regular));
    await tester.pumpAndSettle();

    final dropdownContainer = tester.widget<Container>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.margin == const EdgeInsets.only(top: 4) &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color ==
                theme.colorScheme.surfaceContainerHigh,
      ),
    );

    final decoration = dropdownContainer.decoration! as BoxDecoration;
    expect(decoration.color, theme.colorScheme.surfaceContainerHigh);
    expect(find.text('משה'), findsWidgets);
  });

  testWidgets('onSearch לא מעביר פרמטרים מתקדמים במצב exact',
      (WidgetTester tester) async {
    final historyBloc = MockHistoryBloc();
    final indexingBloc = MockIndexingBloc();
    final navigationBloc = MockNavigationBloc();
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB85C38)),
    );
    final tab = SearchingTab('חיפוש', 'חכמה בינה');
    tab.searchOptions.addAll({
      'חכמה_0': {'קידומות': true}
    });
    tab.alternativeWords.addAll({
      0: ['דעת']
    });
    tab.spacingValues.addAll({'0-1': '5'});
    tab.searchBloc.add(SetSearchMode(SearchMode.exact));

    Map<String, Map<String, bool>>? capturedSearchOptions;
    Map<int, List<String>>? capturedAlternativeWords;
    Map<String, String>? capturedSpacingValues;
    SearchMode? capturedSearchMode;

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
      navigationBloc,
      const Stream<NavigationState>.empty(),
      initialState: const NavigationState(currentScreen: Screen.search),
    );

    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      tab.dispose();
      await historyBloc.close();
      await indexingBloc.close();
      await navigationBloc.close();
    });

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(_buildDialogHarness(
      theme: theme,
      historyBloc: historyBloc,
      indexingBloc: indexingBloc,
      navigationBloc: navigationBloc,
      dialog: SearchDialog(
        existingTab: tab,
        onSearch: (
          query,
          searchOptions,
          alternativeWords,
          spacingValues,
          searchMode,
          distance,
        ) {
          capturedSearchOptions = searchOptions;
          capturedAlternativeWords = alternativeWords;
          capturedSpacingValues = spacingValues;
          capturedSearchMode = searchMode;
        },
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('חפש'));
    await tester.pumpAndSettle();

    expect(capturedSearchMode, SearchMode.exact);
    expect(capturedSearchOptions, isEmpty);
    expect(capturedAlternativeWords, isEmpty);
    expect(capturedSpacingValues, isEmpty);
  });

  testWidgets('onSearch לא מעביר פרמטרים מתקדמים במצב fuzzy',
      (WidgetTester tester) async {
    final historyBloc = MockHistoryBloc();
    final indexingBloc = MockIndexingBloc();
    final navigationBloc = MockNavigationBloc();
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB85C38)),
    );
    final tab = SearchingTab('חיפוש', 'חכמה בינה');
    tab.searchOptions.addAll({
      'חכמה_0': {'קידומות': true}
    });
    tab.alternativeWords.addAll({
      0: ['דעת']
    });
    tab.spacingValues.addAll({'0-1': '5'});
    tab.searchBloc.add(SetSearchMode(SearchMode.fuzzy));

    Map<String, Map<String, bool>>? capturedSearchOptions;
    Map<int, List<String>>? capturedAlternativeWords;
    Map<String, String>? capturedSpacingValues;
    SearchMode? capturedSearchMode;

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
      navigationBloc,
      const Stream<NavigationState>.empty(),
      initialState: const NavigationState(currentScreen: Screen.search),
    );

    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      tab.dispose();
      await historyBloc.close();
      await indexingBloc.close();
      await navigationBloc.close();
    });

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(_buildDialogHarness(
      theme: theme,
      historyBloc: historyBloc,
      indexingBloc: indexingBloc,
      navigationBloc: navigationBloc,
      dialog: SearchDialog(
        existingTab: tab,
        onSearch: (
          query,
          searchOptions,
          alternativeWords,
          spacingValues,
          searchMode,
          distance,
        ) {
          capturedSearchOptions = searchOptions;
          capturedAlternativeWords = alternativeWords;
          capturedSpacingValues = spacingValues;
          capturedSearchMode = searchMode;
        },
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('חפש'));
    await tester.pumpAndSettle();

    expect(capturedSearchMode, SearchMode.fuzzy);
    expect(capturedSearchOptions, isEmpty);
    expect(capturedAlternativeWords, isEmpty);
    expect(capturedSpacingValues, isEmpty);
  });

  testWidgets('בדיאלוג צר בתוך ספר אין overflow כששדה המרחק מוצג',
      (WidgetTester tester) async {
    final historyBloc = MockHistoryBloc();
    final indexingBloc = MockIndexingBloc();
    final navigationBloc = MockNavigationBloc();
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB85C38)),
    );
    final tab = SearchingTab('חיפוש', 'חכמה בינה');
    tab.searchBloc.add(SetSearchMode(SearchMode.exact));

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
      navigationBloc,
      const Stream<NavigationState>.empty(),
      initialState: const NavigationState(currentScreen: Screen.search),
    );

    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      tab.dispose();
      await historyBloc.close();
      await indexingBloc.close();
      await navigationBloc.close();
    });

    await tester.binding.setSurfaceSize(const Size(520, 740));
    await tester.pumpWidget(_buildDialogHarness(
      theme: theme,
      historyBloc: historyBloc,
      indexingBloc: indexingBloc,
      navigationBloc: navigationBloc,
      dialog: SearchDialog(
        existingTab: tab,
        bookTitle: 'ספר',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('מרווח בין מילים'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Enter בשדה מרווח בין מילים לא מפעיל onSearch',
      (WidgetTester tester) async {
    final historyBloc = MockHistoryBloc();
    final indexingBloc = MockIndexingBloc();
    final navigationBloc = MockNavigationBloc();
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB85C38)),
    );
    final tab = SearchingTab('חיפוש', 'חכמה בינה');
    tab.searchBloc.add(SetSearchMode(SearchMode.advanced));

    var onSearchCalls = 0;

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
      navigationBloc,
      const Stream<NavigationState>.empty(),
      initialState: const NavigationState(currentScreen: Screen.search),
    );

    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      tab.dispose();
      await historyBloc.close();
      await indexingBloc.close();
      await navigationBloc.close();
    });

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(_buildDialogHarness(
      theme: theme,
      historyBloc: historyBloc,
      indexingBloc: indexingBloc,
      navigationBloc: navigationBloc,
      dialog: SearchDialog(
        existingTab: tab,
        bookTitle: 'ספר',
        onSearch: (
          query,
          searchOptions,
          alternativeWords,
          spacingValues,
          searchMode,
          distance,
        ) {
          onSearchCalls++;
        },
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SpinBox));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(onSearchCalls, 0);
    expect(find.byType(SearchDialog), findsOneWidget);
  });

  testWidgets('returnResultOnSubmit מחזיר תוצאת חיפוש אחרי סגירת הדיאלוג',
      (WidgetTester tester) async {
    final historyBloc = MockHistoryBloc();
    final indexingBloc = MockIndexingBloc();
    final navigationBloc = MockNavigationBloc();
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB85C38)),
    );
    final tab = SearchingTab('חיפוש', 'חכמה בינה');

    SearchDialogResult? capturedResult;

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
      navigationBloc,
      const Stream<NavigationState>.empty(),
      initialState: const NavigationState(currentScreen: Screen.search),
    );

    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      tab.dispose();
      await historyBloc.close();
      await indexingBloc.close();
      await navigationBloc.close();
    });

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<HistoryBloc>.value(value: historyBloc),
          BlocProvider<IndexingBloc>.value(value: indexingBloc),
          BlocProvider<NavigationBloc>.value(value: navigationBloc),
        ],
        child: MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    capturedResult = await showDialog<SearchDialogResult>(
                      context: context,
                      builder: (_) => SearchDialog(
                        existingTab: tab,
                        bookTitle: 'ספר',
                        returnResultOnSubmit: true,
                      ),
                    );
                  },
                  child: const Text('פתח'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('פתח'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('חפש'));
    await tester.pumpAndSettle();

    expect(capturedResult, isNotNull);
    expect(capturedResult!.query, 'חכמה בינה');
    expect(find.byType(SearchDialog), findsNothing);
  });
}

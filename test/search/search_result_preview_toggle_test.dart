import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/view/tantivy_search_results.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../test_helpers/memory_cache_provider.dart';

/// תצוגה מקדימה של תוצאת חיפוש: לחיצה אחת פותחת/סוגרת תצוגה מקדימה
/// (previewTarget בטאב), לחיצה כפולה פותחת בעיון, וכשהתצוגה כבויה
/// (לחצן העין) או במסך צר — לחיצה אחת פותחת בעיון כמו קודם.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    final library = Library(categories: const []);
    library.books.add(TextBook(id: 1, title: 'בראשית'));
    DataRepository.instance.library = Future.value(library);
  });

  Future<({SearchingTab tab, _RecordingTabsBloc tabsBloc, Finder resultFinder})>
  pumpResults(
    WidgetTester tester, {
    required bool showPreviewPane,
    bool searchShowPreview = true,
    SearchBloc? providedSearchBloc,
  }) async {
    final searchBloc = providedSearchBloc ?? _StaticSearchBloc(_searchState());
    final settingsBloc = _MockSettingsBloc();
    whenListen(
      settingsBloc,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState.initial().copyWith(
        searchShowPreview: searchShowPreview,
      ),
    );
    final tabsBloc = _RecordingTabsBloc();
    final searchingTab = SearchingTab(
      'חיפוש',
      'תדע זרעך',
      searchBloc: searchBloc,
    );

    addTearDown(() async {
      searchingTab.dispose();
      await searchBloc.close();
      await settingsBloc.close();
      await tabsBloc.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<SearchBloc>.value(value: searchBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
          ],
          child: Scaffold(
            body: TantivySearchResults(
              tab: searchingTab,
              showPreviewPane: showPreviewPane,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    return (
      tab: searchingTab,
      tabsBloc: tabsBloc,
      resultFinder: find.text('בראשית, פרק טו').first,
    );
  }

  /// לחיצה אחת + המתנה לחלוף חלון הלחיצה הכפולה (אחרת ה-onTap לא יורה)
  /// ולפתרון האסינכרוני של זיהוי הספר.
  Future<void> singleTap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder, warnIfMissed: false);
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('לחיצה אחת פותחת תצוגה מקדימה בלי לפתוח טאב', (tester) async {
    final harness = await pumpResults(tester, showPreviewPane: true);

    await singleTap(tester, harness.resultFinder);

    final target = harness.tab.previewTarget.value;
    expect(target, isNotNull);
    expect(target!.segment, 389);
    expect(target.filePath, 'id:1');
    expect(target.book.title, 'בראשית');
    expect(harness.tabsBloc.openedTabs, isEmpty);
  });

  testWidgets('לחיצה חוזרת על אותה תוצאה סוגרת את התצוגה המקדימה', (
    tester,
  ) async {
    final harness = await pumpResults(tester, showPreviewPane: true);

    await singleTap(tester, harness.resultFinder);
    expect(harness.tab.previewTarget.value, isNotNull);

    await singleTap(tester, harness.resultFinder);
    expect(harness.tab.previewTarget.value, isNull);
    expect(harness.tabsBloc.openedTabs, isEmpty);
  });

  testWidgets('חיפוש חדש אינו מאפשר לפענוח קודם לפתוח תצוגה מקדימה', (
    tester,
  ) async {
    final searchBloc = _DeferredResolutionSearchBloc(_searchState());
    final harness = await pumpResults(
      tester,
      showPreviewPane: true,
      providedSearchBloc: searchBloc,
    );

    await singleTap(tester, harness.resultFinder);
    expect(searchBloc.resolutionRequests, 1);

    searchBloc.updateState(_searchState(query: 'חיפוש חדש'));
    await tester.pump();
    searchBloc.completeResolution();
    await tester.pump();

    expect(harness.tab.previewTarget.value, isNull);
  });

  testWidgets('לחיצה כפולה פותחת את התוצאה בעיון', (tester) async {
    final harness = await pumpResults(tester, showPreviewPane: true);

    await tester.tap(harness.resultFinder, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(harness.resultFinder, warnIfMissed: false);
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(harness.tabsBloc.openedTabs, hasLength(1));
  });

  testWidgets('כשהתצוגה המקדימה כבויה בהגדרה — לחיצה אחת פותחת בעיון', (
    tester,
  ) async {
    final harness = await pumpResults(
      tester,
      showPreviewPane: true,
      searchShowPreview: false,
    );

    await singleTap(tester, harness.resultFinder);

    expect(harness.tab.previewTarget.value, isNull);
    expect(harness.tabsBloc.openedTabs, hasLength(1));
  });

  testWidgets('בלי חלונית תצוגה מקדימה (מסך צר) — לחיצה אחת פותחת בעיון', (
    tester,
  ) async {
    final harness = await pumpResults(tester, showPreviewPane: false);

    await singleTap(tester, harness.resultFinder);

    expect(harness.tab.previewTarget.value, isNull);
    expect(harness.tabsBloc.openedTabs, hasLength(1));
  });
}

SearchState _searchState({String query = 'תדע זרעך'}) => SearchState(
  searchQuery: query,
  totalResults: 1,
  results: [
    SearchResult(
      id: BigInt.one,
      title: 'בראשית',
      reference: 'בראשית, פרק טו',
      text: 'ידע תדע כי־גר יהיה זרעך',
      segment: BigInt.from(389),
      isPdf: false,
      filePath: 'id:1',
      mergedCount: 1,
      merged: const [],
    ),
  ],
);

class _StaticSearchBloc extends SearchBloc {
  _StaticSearchBloc(SearchState initialSearchState) {
    emit(initialSearchState);
  }

  @override
  void add(SearchEvent event) {}
}

class _DeferredResolutionSearchBloc extends _StaticSearchBloc {
  _DeferredResolutionSearchBloc(super.initialSearchState);

  final Completer<IndexedBookResolution> _resolution = Completer();

  int resolutionRequests = 0;

  void updateState(SearchState state) => emit(state);

  void completeResolution() => _resolution.complete(
    (book: TextBook(id: 1, title: 'בראשית'), isStale: false),
  );

  @override
  Future<IndexedBookResolution> resolveBookForIndexedPath(
    String indexedFilePath, {
    required String indexedTitle,
  }) {
    resolutionRequests++;
    return _resolution.future;
  }
}

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _RecordingTabsBloc extends Bloc<TabsEvent, TabsState>
    implements TabsBloc {
  _RecordingTabsBloc() : super(TabsState.initial()) {
    on<TabsEvent>((event, emit) {
      if (event is OpenOrFocusTab) {
        openedTabs.add(event.tab);
      }
    });
  }

  final List<Object> openedTabs = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

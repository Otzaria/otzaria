import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/view/tantivy_search_results.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../test_helpers/memory_cache_provider.dart';

/// issue #3944: תוצאת חיפוש בספר שכבר פתוח באותו סימן (משנה ברורה: כותרת
/// אחת לכל השורות של הסימן) ממקדת את הטאב הקיים — והוא חייב לקפוץ לתוצאה.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const book = 'משנה ברורה';
  const reference = '$book, סימן א';
  const readingLine = 30;
  const resultLine = 45;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    final library = Library(categories: const []);
    library.books.add(TextBook(id: 1, title: book));
    DataRepository.instance.library = Future.value(library);
  });

  /// לוחץ על תוצאה ב-[resultReference] כשהספר פתוח בשורה אחרת של סימן א.
  Future<(TabsBloc, TextBookTab)> clickResult(
    WidgetTester tester, {
    required bool split,
    required String resultReference,
  }) async {
    const configuration = SearchConfiguration(
      searchMode: SearchMode.exact,
    );
    final searchBloc = _StaticSearchBloc(
      SearchState(
        searchQuery: 'נטילת ידים',
        totalResults: 1,
        configuration: configuration,
        results: [
          SearchResult(
            id: BigInt.one,
            title: book,
            reference: resultReference,
            text: 'צריך נטילת ידים',
            segment: BigInt.from(resultLine),
            isPdf: false,
            filePath: 'id:1',
            mergedCount: 1,
            merged: const [],
            textStatus: TextStatus.ok,
            continuesToNextLine: false,
          ),
        ],
      ),
    );
    final settingsBloc = _MockSettingsBloc();
    whenListen(
      settingsBloc,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState.initial(),
    );
    final readingTab = TextBookTab(
      book: TextBook(id: 1, title: book),
      index: readingLine,
    )..currentTitle.value = reference;
    final searchingTab = SearchingTab(
      'חיפוש',
      'נטילת ידים',
      initialConfiguration: configuration,
      searchBloc: searchBloc,
    );
    final OpenedTab readingTop = split
        ? CombinedTab(
            rightTab: readingTab,
            leftTab: TextBookTab(
              book: TextBook(id: 2, title: 'שולחן ערוך, אורח חיים'),
              index: 0,
            ),
          )
        : readingTab;
    final tabsBloc = TabsBloc(
      repository: _MemoryTabs(),
      disposeDelay: Duration.zero,
      withCompanion: (tab) async => tab,
    );
    tabsBloc
      ..add(AddTab(readingTop))
      ..add(AddTab(searchingTab));
    addTearDown(() async {
      await tester.runAsync(tabsBloc.close);
      await searchBloc.close();
      await settingsBloc.close();
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
            body: SizedBox(
              height: 500,
              child: TantivySearchResults(tab: searchingTab),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tabsBloc.state.tabs, hasLength(2));
    expect(tabsBloc.state.currentTabIndex, 1);

    await tester.tap(find.text(resultReference).first);
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    return (tabsBloc, readingTab);
  }

  for (final split in [false, true]) {
    testWidgets(
      'לחיצה על תוצאה קופצת אליה בטאב הפתוח באותו סימן (issue #3944, split=$split)',
      (tester) async {
        final (tabsBloc, readingTab) = await clickResult(
          tester,
          split: split,
          resultReference: reference,
        );

        expect(
          tabsBloc.state.tabs,
          hasLength(2),
          reason: 'הספר פתוח באותו סימן — הטאב הקיים ממוקד ולא נפתח חדש',
        );
        expect(tabsBloc.state.currentTabIndex, 0);
        expect(
          readingTab.index,
          resultLine,
          reason: 'הטאב הקיים חייב לקפוץ לשורת התוצאה, לא להישאר במקומו',
        );
        expect(readingTab.lines.hasPendingTarget, isTrue);
      },
    );

    testWidgets(
      'תוצאה בסימן אחר נפתחת בטאב חדש והטאב הפתוח נשאר במקומו (issue #3944, split=$split)',
      (tester) async {
        final (tabsBloc, readingTab) = await clickResult(
          tester,
          split: split,
          resultReference: '$book, סימן ב',
        );

        expect(tabsBloc.state.tabs, hasLength(3));
        expect(
          tabsBloc.state.currentTab,
          isA<TextBookTab>().having((tab) => tab.index, 'index', resultLine),
        );
        expect(readingTab.index, readingLine);
        expect(readingTab.lines.hasPendingTarget, isFalse);
      },
    );
  }
}

class _StaticSearchBloc extends SearchBloc {
  _StaticSearchBloc(SearchState initialSearchState) {
    emit(initialSearchState);
  }

  @override
  void add(SearchEvent event) {}
}

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _MemoryTabs extends TabsRepository {
  @override
  List<OpenedTab> loadTabs({bool newRuntime = false}) => const [];
  @override
  int loadCurrentTabIndex() => 0;
  @override
  Future<void> saveTabs(List<OpenedTab> tabs, int currentTabIndex) async {}
  @override
  Future<void> saveCurrentTabIndex(List<OpenedTab> tabs, int index) async {}
  @override
  Future<void> flushPendingWrites() async {}
}

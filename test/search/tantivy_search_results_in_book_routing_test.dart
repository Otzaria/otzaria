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
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/utils/cross_line_result.dart';
import 'package:otzaria/search/view/tantivy_search_results.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../test_helpers/memory_cache_provider.dart';

/// פתיחת תוצאה מהחיפוש הגלובלי אל טאב קריאה: הקונפיגורציה שבה נמצאה התוצאה
/// חייבת להגיע לטאב, אחרת חלונית החיפוש שבספר מריצה חיפוש מחרוזת רצופה
/// ומציגה "אין תוצאות" על תוצאה שהחיפוש הגלובלי בהחלט מצא.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    // מפתח יציב ('id:1') חייב ספר תואם בקטלוג — מפתח שנעלם נחסם כאינדקס ישן.
    final library = Library(categories: const []);
    library.books.add(TextBook(id: 1, title: 'בראשית'));
    DataRepository.instance.library = Future.value(library);
  });

  Future<TextBookTab> openFirstResult(
    WidgetTester tester, {
    required SearchConfiguration configuration,
    String? typedAfterSearch,
    bool continuesToNextLine = false,
  }) async {
    final searchBloc = _StaticSearchBloc(
      SearchState(
        searchQuery: 'תדע זרעך',
        totalResults: 1,
        configuration: configuration,
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
            textStatus: TextStatus.ok,
            continuesToNextLine: continuesToNextLine,
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
    final tabsBloc = _RecordingTabsBloc();
    // הפותח קורא את הקונפיגורציה והשאילתה מה-bloc של טאב החיפוש עצמו —
    // באפליקציה זהו אותו מופע שמוזרק כ-Provider, ולכן גם כאן הם משותפים.
    final searchingTab = SearchingTab(
      'חיפוש',
      'תדע זרעך',
      initialConfiguration: configuration,
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
            body: SizedBox(
              height: 500,
              child: TantivySearchResults(tab: searchingTab),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    if (typedAfterSearch != null) {
      // המשתמש מקליד בתיבה בלי להפעיל חיפוש חדש — state.searchQuery נשאר
      // השאילתה שבוצעה, ורק הטקסט בבקר משתנה.
      searchingTab.queryController.text = typedAfterSearch;
    }

    await tester.tap(find.text('בראשית, פרק טו').first);
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    final opened = tabsBloc.openedTabs.whereType<TextBookTab>().toList();
    expect(opened, hasLength(1), reason: 'נפתח טאב קריאה אחד');
    addTearDown(opened.single.dispose);
    return opened.single;
  }

  testWidgets('מרווח בין מילים עובר אל טאב הקריאה', (tester) async {
    // הבאג: המרווח נמחק בדרך, הטאב נפתח כחיפוש מדויק במרווח 0, וחלונית
    // החיפוש בספר לא מצאה את הפסוק שהתוצאה הצביעה עליו.
    final tab = await openFirstResult(
      tester,
      configuration: const SearchConfiguration(
        searchMode: SearchMode.advanced,
        distance: 3,
      ),
    );

    expect(tab.searchText, 'תדע זרעך');
    expect(tab.searchMode, SearchMode.advanced);
    expect(tab.searchDistance, 3);
  });

  testWidgets('מרווח במצב מדויק עובר גם הוא', (tester) async {
    final tab = await openFirstResult(
      tester,
      configuration: const SearchConfiguration(
        searchMode: SearchMode.exact,
        distance: 2,
      ),
    );

    expect(tab.searchMode, SearchMode.exact);
    expect(tab.searchDistance, 2);
  });

  testWidgets('חיפוש מקורב שומר את מרחק העריכה', (tester) async {
    final tab = await openFirstResult(
      tester,
      configuration: const SearchConfiguration(
        searchMode: SearchMode.fuzzy,
        distance: 1,
      ),
    );

    expect(tab.searchMode, SearchMode.fuzzy);
    expect(tab.searchDistance, 1);
  });

  testWidgets('טווח "באותה פסקה" עובר אל הטאב עם מדיניות ההתאמה', (
    tester,
  ) async {
    final tab = await openFirstResult(
      tester,
      configuration: const SearchConfiguration(
        searchMode: SearchMode.advanced,
        distance: 0,
        proximityScope: SearchScope.sameParagraph,
      ),
    );

    expect(tab.searchMode, SearchMode.advanced);
    expect(tab.matchPolicy.proximityScope, SearchScope.sameParagraph);
  });

  testWidgets('מצב "לפחות X מילים" עובר אל הטאב', (tester) async {
    final tab = await openFirstResult(
      tester,
      configuration: const SearchConfiguration(
        searchMode: SearchMode.advanced,
        distance: 0,
        wordMatchMode: WordMatchMode.atLeast,
        wordMatchCount: 3,
      ),
    );

    expect(tab.matchPolicy.wordMatchMode, WordMatchMode.atLeast);
    expect(tab.matchPolicy.wordMatchCount, 3);
  });

  testWidgets('מדיניות ההתאמה מגיעה מהטאב אל ה-state של הספר', (tester) async {
    // הקצה השני של השרשרת: הטאב בונה TextBookInitial, וה-bloc מעביר את
    // המדיניות אל TextBookLoaded — משם חלונית החיפוש שולחת אותה למנוע.
    final tab = await openFirstResult(
      tester,
      configuration: const SearchConfiguration(
        searchMode: SearchMode.advanced,
        distance: 0,
        proximityScope: SearchScope.sameSection,
      ),
    );

    final initialState = tab.bloc.state;
    expect(initialState, isA<TextBookInitial>());
    final initial = initialState as TextBookInitial;
    expect(initial.matchPolicy.proximityScope, SearchScope.sameSection);
    expect(initial.initialSearchResultLines, {389});
  });

  testWidgets('ביטוי שנמשך לשורה הבאה מסמן גם אותה כשורת תוצאה', (
    tester,
  ) async {
    final tab = await openFirstResult(
      tester,
      configuration: const SearchConfiguration(searchMode: SearchMode.exact),
      continuesToNextLine: true,
    );

    expect(find.text(crossLineResultNote), findsOneWidget);
    final initial = tab.bloc.state as TextBookInitial;
    expect(initial.initialSearchResultLines, {389, 390});
  });

  testWidgets('הקלדה אחרי החיפוש אינה מחליפה את השאילתה שבוצעה', (
    tester,
  ) async {
    // הבאג: הפותח קרא את queryController.text במקום את state.searchQuery,
    // וכך טקסט שהוקלד-אך-לא-חופש הפך ל-searchText של טאב הקריאה — ההדגשה
    // בספר חיפשה מחרוזת שהתוצאה מעולם לא נמצאה בה.
    final tab = await openFirstResult(
      tester,
      configuration: const SearchConfiguration(
        searchMode: SearchMode.advanced,
        distance: 3,
      ),
      typedAfterSearch: 'טקסט שהוקלד ולא חופש',
    );

    expect(tab.searchText, 'תדע זרעך');
  });

  testWidgets('שאילתה ליטרלית נפתחת כחיפוש מדויק מקומי', (tester) async {
    final tab = await openFirstResult(
      tester,
      configuration: const SearchConfiguration(
        searchMode: SearchMode.advanced,
        distance: 0,
      ),
    );

    expect(tab.searchMode, SearchMode.exact);
    expect(tab.searchDistance, 0);
  });
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

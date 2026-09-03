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
import 'package:otzaria/search/view/tantivy_search_results.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../test_helpers/memory_cache_provider.dart';

/// מסלול הלחיצה האמיתי על תוצאת חיפוש, מקצה לקצה: מפתח המסמך באינדקס הוא
/// מזהה שורה ב-DB, והחלפת ספרייה מקצה אותו לספר אחר. הכרטיס עדיין מציג את
/// הכותרת הישנה, ולכן פתיחה לפי המפתח בלבד הקפיצה לספר לא קשור (#774, #712).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Future<TextBookTab?> openResultAgainstLibrary(
    WidgetTester tester, {
    required List<Book> catalogue,
    required String resultTitle,
    required String indexedFilePath,
    bool expectOpen = true,
  }) async {
    final library = Library(categories: const []);
    library.books.addAll(catalogue);
    DataRepository.instance.library = Future.value(library);

    final searchBloc = _StaticSearchBloc(
      SearchState(
        searchQuery: 'תמיד של שחר מכפרת',
        totalResults: 1,
        configuration: const SearchConfiguration(searchMode: SearchMode.exact),
        results: [
          SearchResult(
            id: BigInt.one,
            title: resultTitle,
            reference: 'הפניה לתוצאה',
            text: 'תמיד של שחר מכפרת',
            segment: BigInt.from(12),
            isPdf: false,
            filePath: indexedFilePath,
            mergedCount: 1,
            merged: const [],
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
    final searchingTab = SearchingTab(
      'חיפוש',
      'תמיד של שחר מכפרת',
      searchBloc: searchBloc,
    );

    addTearDown(() async {
      searchingTab.dispose();
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

    await tester.tap(find.text('הפניה לתוצאה').first);
    for (var i = 0; i < 24; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    final opened = tabsBloc.openedTabs.whereType<TextBookTab>().toList();
    if (!expectOpen) {
      expect(opened, isEmpty, reason: 'אינדקס עבש אינו פותח ספר');
      return null;
    }
    expect(opened, hasLength(1), reason: 'נפתח טאב קריאה אחד');
    addTearDown(opened.single.dispose);
    return opened.single;
  }

  testWidgets('רגרסיה #774/#712: מפתח שהוסב לספר אחר אינו נפתח', (
    tester,
  ) async {
    final tab = await openResultAgainstLibrary(
      tester,
      catalogue: [TextBook(id: 1234, title: 'רבינו חננאל על מועד קטן')],
      resultTitle: 'רש"י על ישעיהו',
      indexedFilePath: 'id:1234',
      expectOpen: false,
    );
    expect(tab, isNull);
  });

  testWidgets('מפתח תואם פותח את ספר הקטלוג עצמו', (tester) async {
    final book = TextBook(id: 1234, title: 'רש"י על ישעיהו', author: 'רש"י');

    final tab = await openResultAgainstLibrary(
      tester,
      catalogue: [book],
      resultTitle: 'רש"י על ישעיהו',
      indexedFilePath: 'id:1234',
    );

    expect(tab!.book.title, 'רש"י על ישעיהו');
    expect(
      tab.book.author,
      'רש"י',
      reason: 'הספר עצמו מהקטלוג, לא בנייה מכותרת',
    );
  });

  testWidgets('זהות ספר אישי נשמרת כשהכותרות תואמות', (tester) async {
    // כותרות זהות ⇒ השער עובר, וההבחנה בין ספר אישי לרשמי נשמרת.
    final tab = await openResultAgainstLibrary(
      tester,
      catalogue: [
        TextBook(id: 5, title: 'שבת'),
        TextBook(id: 5, title: 'שבת', isUserBook: true),
      ],
      resultTitle: 'שבת',
      indexedFilePath: 'uid:5',
    );

    expect(tab!.book.title, 'שבת');
    expect(tab.book.isUserBook, isTrue);
  });

  testWidgets('מפתח יציב שנעלם מהקטלוג אינו נפתח לפי הכותרת', (tester) async {
    // סריקה מחדש של ספרים אישיים מקצה מזהים חדשים; פתיחה לפי כותרת הייתה
    // מאבדת את זהות הספר האישי ופותחת ספר רשמי באותה כותרת במיקום שגוי.
    final tab = await openResultAgainstLibrary(
      tester,
      catalogue: [TextBook(id: 7, title: 'ספר שאינו בקטלוג')],
      resultTitle: 'ספר שאינו בקטלוג',
      indexedFilePath: 'uid:999999',
      expectOpen: false,
    );
    expect(tab, isNull);
  });

  testWidgets('מפתח חיצוני שנעלם מהקטלוג אינו נפתח לפי הכותרת', (
    tester,
  ) async {
    final tab = await openResultAgainstLibrary(
      tester,
      catalogue: [TextBook(id: 7, title: 'ברכות')],
      resultTitle: 'ברכות',
      indexedFilePath: 'ext:talmud-pdf:ברכות',
      expectOpen: false,
    );
    expect(tab, isNull);
  });

  testWidgets('מפתח legacy בפורמט נתיב ממשיך להיפתח לפי הכותרת', (
    tester,
  ) async {
    final tab = await openResultAgainstLibrary(
      tester,
      catalogue: const [],
      resultTitle: 'ספר מאינדקס ישן',
      indexedFilePath: 'C:/books/ספר מאינדקס ישן.txt',
    );

    expect(tab!.book.title, 'ספר מאינדקס ישן');
  });

  test(
    'רגרסיה #828: מפתח וכותרת תואמים פותחים גם בלי אימות טביעת אצבע',
    () async {
      // הוספת ספר לספרייה מזיזה את הסדר הקטלוגי ופוסלת את החתימה הקנונית של
      // כל הספרים שאחריו — הפתיחה חייבת להסתמך על זהות בלבד (מפתח + כותרת).
      final library = Library(categories: const []);
      library.books.add(TextBook(id: 1234, title: 'משנה תורה'));
      DataRepository.instance.library = Future.value(library);
      final bloc = _StaticSearchBloc(const SearchState());
      addTearDown(bloc.close);

      final resolution = await bloc.resolveBookForIndexedPath(
        'id:1234',
        indexedTitle: 'משנה תורה',
      );
      expect(resolution.book?.title, 'משנה תורה');
      expect(resolution.isStale, isFalse);
    },
  );
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

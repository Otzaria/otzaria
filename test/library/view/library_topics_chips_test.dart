import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/models/library_match_filter.dart';
import 'package:otzaria/library/models/library_navigation_history.dart';
import 'package:otzaria/library/view/library_browser.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/theme/app_theme_data.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/widgets/lists/filter_chips_widget.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/memory_cache_provider.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import '../../test_helpers/stub_tabs_bloc.dart';

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {
  @override
  final navigationHistory = LibraryNavigationHistory();
}

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _MockNavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

class _MockLibraryUpdateBloc
    extends MockBloc<LibraryUpdateEvent, LibraryUpdateState>
    implements LibraryUpdateBloc {}

class _StubCalendarCubit extends Cubit<CalendarState> implements CalendarCubit {
  _StubCalendarCubit(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// סופר קריאות של [topics] — כך נמדדת עבודת חישוב הצ'יפים בלי תלות בזמן.
class _CountingBook extends TextBook {
  static int topicsReads = 0;

  _CountingBook({required super.title, required super.topics});

  @override
  String get topics {
    topicsReads++;
    return super.topics;
  }
}

Future<StreamController<LibraryState>> _pump(
  WidgetTester tester,
  LibraryState state,
) async {
  final states = StreamController<LibraryState>.broadcast();
  final libraryBloc = _MockLibraryBloc();
  final settingsBloc = _MockSettingsBloc();
  final navigationBloc = _MockNavigationBloc();
  final libraryUpdateBloc = _MockLibraryUpdateBloc();
  final calendarCubit = _StubCalendarCubit(CalendarState.initial());

  whenListen(libraryBloc, states.stream, initialState: state);
  whenListen(
    settingsBloc,
    const Stream<SettingsState>.empty(),
    initialState: SettingsState.initial().copyWith(libraryShowPreview: false),
  );
  whenListen(
    navigationBloc,
    const Stream<NavigationState>.empty(),
    initialState: const NavigationState(currentScreen: Screen.library),
  );
  whenListen(
    libraryUpdateBloc,
    const Stream<LibraryUpdateState>.empty(),
    initialState: const LibraryUpdateState(),
  );

  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 900);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.reset();
    await states.close();
    await libraryBloc.close();
    await settingsBloc.close();
    await navigationBloc.close();
    await libraryUpdateBloc.close();
    await calendarCubit.close();
  });

  await tester.pumpWidget(
    MaterialApp(
      theme: AppThemeData.light(
        ColorScheme.fromSeed(seedColor: Colors.blue),
        compactMenuMode: false,
      ),
      locale: const Locale('he', 'IL'),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: MultiProvider(
        providers: [
          Provider<FocusRepository>.value(value: FocusRepository()),
          BlocProvider<LibraryBloc>.value(value: libraryBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<NavigationBloc>.value(value: navigationBloc),
          BlocProvider<TabsBloc>(
            create: (_) => StubTabsBloc(TabsState.initial()),
          ),
          BlocProvider<LibraryUpdateBloc>.value(value: libraryUpdateBloc),
          BlocProvider<CalendarCubit>.value(value: calendarCubit),
          BlocProvider<CustomFoldersBloc>(
            create: (_) => CustomFoldersBloc(addLibraryEvent: (_) {}),
          ),
        ],
        child: const LibraryBrowser(),
      ),
    ),
  );
  await tester.pump();
  // כפתור הדף היומי גולש עם CalendarState מדומה — לא נושא הבדיקה.
  tester.takeException();
  return states;
}

List<String> _chipItems(WidgetTester tester) => tester
    .widget<FilterChipsSelector<String>>(
      find.byType(FilterChipsSelector<String>),
    )
    .items;

List<LibraryMatchFilter> _matchChipItems(WidgetTester tester) => tester
    .widget<FilterChipsSelector<LibraryMatchFilter>>(
      find.byType(FilterChipsSelector<LibraryMatchFilter>),
    )
    .items;

/// תוצאות 'טור' כמו בדיווח #4232: שם, מחבר, תיקיית הספר וכרטיס תיקייה.
LibraryState _turResults({
  Set<LibraryMatchFilter> filters = const {},
  List<String>? topics,
}) {
  final library = Library(categories: []);
  final tur = TextBook(title: 'טור', topics: 'הלכה, ראשונים');
  final einYitzchak = TextBook(title: 'עין יצחק', topics: 'שות, אחרונים');
  final prisha = TextBook(title: 'פרישה', topics: 'הלכה, אחרונים');
  final folder = Category(
    title: 'טורי זהב',
    description: '',
    shortDescription: '',
    order: 0,
    subCategories: [],
    books: [],
    parent: library,
  );
  return LibraryState(
    library: library,
    currentCategory: library,
    searchResults: [tur, einYitzchak, prisha],
    searchCategoryResults: [folder],
    searchMatchKinds: Map.identity()
      ..[tur] = BookMatchKind.title.bit | BookMatchKind.author.bit
      ..[einYitzchak] = BookMatchKind.author.bit
      ..[prisha] = BookMatchKind.folder.bit,
    selectedMatchFilters: filters,
    selectedTopics: topics,
    searchQuery: 'טור',
  );
}

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('fonts/Rubik-VariableFont_wght.ttf'))).load();
  });

  testWidgets(
    'הקלדה שאינה משנה את התוצאות אינה סורקת שוב את נושאי כל התוצאות (perf)',
    (tester) async {
      final library = Library(categories: []);
      const resultCount = 1000;
      final results = [
        for (var i = 0; i < resultCount; i++)
          _CountingBook(title: 'ספר $i', topics: 'הלכה, אחרונים, מחבר $i'),
      ];
      final state = LibraryState(
        library: library,
        currentCategory: library,
        searchResults: results,
        searchQuery: 'ספר',
      );
      final states = await _pump(tester, state);
      expect(_chipItems(tester), ['הלכה', 'אחרונים']);

      _CountingBook.topicsReads = 0;
      for (final query in ['ספר א', 'ספר אב', 'ספר אבג']) {
        states.add(state.copyWith(searchResults: results, searchQuery: query));
        await tester.pump();
        await tester.pump();
      }
      tester.takeException();

      // כרטיסי הרשת המוצגים (עד 100) קוראים את הנושאים שלהם; סריקה של כל
      // התוצאות בכל בנייה הייתה מגיעה לפחות ל-3 × resultCount.
      expect(_CountingBook.topicsReads, lessThan(resultCount));
    },
  );

  testWidgets('צ\'יפי הנושאים מתעדכנים כשמגיעות תוצאות חדשות', (tester) async {
    final library = Library(categories: []);
    final state = LibraryState(
      library: library,
      currentCategory: library,
      searchResults: [
        TextBook(title: 'משנה ברורה', topics: 'הלכה, אחרונים'),
        TextBook(title: 'רמב"ן', topics: 'תנך, ראשונים'),
      ],
      searchQuery: 'ברורה',
    );
    final states = await _pump(tester, state);
    expect(_chipItems(tester), ['תנך', 'הלכה', 'ראשונים', 'אחרונים']);

    states.add(
      state.copyWith(
        searchResults: [TextBook(title: 'תניא', topics: 'חסידות, קבלה')],
        searchQuery: 'תניא',
      ),
    );
    await tester.pump();
    await tester.pump();
    tester.takeException();
    expect(_chipItems(tester), ['חסידות', 'קבלה']);
  });

  testWidgets('מטמון הנושאים מתעדכן אחרי רענון וניקוי חיפוש', (tester) async {
    final oldLibrary = Library(categories: []);
    final oldResults = <Book>[
      TextBook(title: 'ספר ישן', topics: 'תנך, ראשונים', category: oldLibrary),
    ];
    final states = await _pump(
      tester,
      LibraryState(
        library: oldLibrary,
        currentCategory: oldLibrary,
        searchResults: oldResults,
        searchQuery: 'ישן',
      ),
    );
    expect(_chipItems(tester), ['תנך', 'ראשונים']);

    final newLibrary = Library(categories: []);
    final cleared = LibraryState(
      library: newLibrary,
      currentCategory: newLibrary,
      searchQuery: '',
    );
    for (final state in [cleared, cleared.copyWith(searchResults: <Book>[])]) {
      states.add(state);
      await tester.pump();
      await tester.pump();
      expect(find.byType(FilterChipsSelector<String>), findsNothing);
    }

    final results = <Book>[
      for (var i = 0; i < 1000; i++)
        _CountingBook(title: 'ספר חדש $i', topics: 'חסידות, קבלה'),
    ];
    final searched = cleared.copyWith(
      searchResults: results,
      searchQuery: 'חדש',
    );
    states.add(searched);
    await tester.pump();
    await tester.pump();
    expect(_chipItems(tester), ['חסידות', 'קבלה']);

    _CountingBook.topicsReads = 0;
    states.add(searched.copyWith(searchResults: results, searchQuery: 'חדש א'));
    await tester.pump();
    await tester.pump();
    expect(_chipItems(tester), ['חסידות', 'קבלה']);
    expect(_CountingBook.topicsReads, lessThan(results.length));
    tester.takeException();
  });

  testWidgets("צ'יפי סוג ההתאמה מציגים רק סוגים שיש בתוצאות (#4232)", (
    tester,
  ) async {
    await _pump(tester, _turResults());
    expect(_matchChipItems(tester), [
      LibraryMatchFilter.title,
      LibraryMatchFilter.author,
      LibraryMatchFilter.folder,
      LibraryMatchFilter.folders,
    ]);
    expect(find.text('מחבר (2)'), findsOneWidget);
    // שורת הנושאים נשארת מתחת.
    expect(find.byType(FilterChipsSelector<String>), findsOneWidget);
    tester.takeException();
  });

  testWidgets('בחירת מחבר מסתירה ספרים אחרים ואת כרטיסי התיקיות', (
    tester,
  ) async {
    await _pump(tester, _turResults(filters: {LibraryMatchFilter.author}));
    expect(find.text('טור'), findsWidgets);
    expect(find.text('עין יצחק'), findsOneWidget);
    expect(find.text('פרישה'), findsNothing);
    expect(find.text('טורי זהב'), findsNothing);
    tester.takeException();
  });

  testWidgets('בחירת תיקיות מציגה רק את כרטיסי התיקיות', (tester) async {
    await _pump(tester, _turResults(filters: {LibraryMatchFilter.folders}));
    expect(find.text('עין יצחק'), findsNothing);
    expect(find.text('פרישה'), findsNothing);
    expect(find.text('טורי זהב'), findsOneWidget);
    tester.takeException();
  });

  testWidgets("הספירות לפי הנושא שנבחר, וצ'יפ שנבחר נשאר גם בלי תוצאות", (
    tester,
  ) async {
    await _pump(
      tester,
      _turResults(
        filters: {LibraryMatchFilter.folders},
        topics: ['ראשונים'],
      ),
    );
    expect(find.text('מחבר (1)'), findsOneWidget);
    expect(find.text('תיקיות (0)'), findsOneWidget);
    expect(_matchChipItems(tester), contains(LibraryMatchFilter.folders));
    tester.takeException();
  });
}

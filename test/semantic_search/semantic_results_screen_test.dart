import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/search_feedback/semantic_search_strings.dart';
import 'package:otzaria/semantic_search/models/semantic_result_item.dart';
import 'package:otzaria/semantic_search/services/semantic_dwell_binding.dart';
import 'package:otzaria/semantic_search/view/semantic_search_results_screen.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/semantic_search_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SemanticResultSource;

import '../test_helpers/memory_cache_provider.dart';
import 'semantic_ui_test_support.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class _MockNavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

class _RecordingTabsBloc extends Bloc<TabsEvent, TabsState>
    implements TabsBloc {
  _RecordingTabsBloc() : super(TabsState.initial()) {
    on<TabsEvent>((event, emit) {
      if (event is OpenOrFocusTab) opened.add(event);
    });
  }

  final List<OpenOrFocusTab> opened = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    final library = Library(categories: const []);
    for (var i = 1; i <= 35; i++) {
      library.books.add(TextBook(id: i, title: 'ספר $i'));
    }
    DataRepository.instance.library = Future.value(library);
  });

  Future<({RecordingRecorder recorder, _RecordingTabsBloc tabs})> pumpScreen(
    WidgetTester tester, {
    bool runOnFirstShow = true,
  }) async {
    final recorder = RecordingRecorder();
    final items = [
      resultItem(1, source: SemanticResultSource.both),
      resultItem(2, source: SemanticResultSource.semantic, html: 'בלי סימון'),
      resultItem(3, source: SemanticResultSource.lexical),
      for (var i = 4; i <= 35; i++) resultItem(i),
    ];
    final tab = SemanticSearchTab(
      runOnFirstShow: runOnFirstShow,
      options: const SemanticQueryOptions(query: 'כבוד אב'),
      createResultsBloc: (_) => buildResultsBloc(
        source: FakeResultsSource(items: items),
        recorder: recorder,
      ),
    );
    final settings = _MockSettingsBloc();
    whenListen(
      settings,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState.initial().copyWith(searchShowPreview: false),
    );
    final navigation = _MockNavigationBloc();
    whenListen(
      navigation,
      const Stream<NavigationState>.empty(),
      initialState: const NavigationState(currentScreen: Screen.search),
    );
    final tabs = _RecordingTabsBloc();
    final libraryBloc = _MockLibraryBloc();
    whenListen(
      libraryBloc,
      const Stream<LibraryState>.empty(),
      initialState: const LibraryState(),
    );
    addTearDown(() async {
      await libraryBloc.close();
      tab.dispose();
      await settings.close();
      await navigation.close();
      await tabs.close();
    });

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>.value(value: settings),
          BlocProvider<TabsBloc>.value(value: tabs),
          BlocProvider<NavigationBloc>.value(value: navigation),
          BlocProvider<LibraryBloc>.value(value: libraryBloc),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(700, 900)),
            child: SemanticSearchResultsScreen(tab: tab),
          ),
        ),
      ),
    );
    await settle(tester);
    return (recorder: recorder, tabs: tabs);
  }

  testWidgets('הכרטיסים מציגים את תווית המקור', (tester) async {
    await pumpScreen(tester);

    expect(find.text(kSemanticSourceBothLabel), findsWidgets);
    expect(find.text(kSemanticSourceSemanticLabel), findsOneWidget);
    expect(find.text(kSemanticSourceLexicalLabel), findsOneWidget);
  });

  testWidgets('אהבתי, לחיצה חוזרת מבטלת; לא אהבתי', (tester) async {
    final harness = await pumpScreen(tester);

    await tester.tap(find.byKey(const ValueKey('semantic-like-1')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('semantic-like-1')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('semantic-dislike-2')));
    await settle(tester);

    expect(harness.recorder.votes.map((vote) => vote.vote), [
      SearchFeedbackVote.like,
      SearchFeedbackVote.cleared,
      SearchFeedbackVote.dislike,
    ]);
    expect(harness.recorder.votes.last.result.rank, 2);
  });

  testWidgets('פתיחה: התאמה לפי עניין בלבד נפתחת בלי הדגשת מילים', (
    tester,
  ) async {
    final harness = await pumpScreen(tester);

    await tester.tap(find.text('ספר 1, א'));
    await settle(tester);
    await tester.tap(find.text('ספר 2, א'));
    await settle(tester);

    final opened = harness.tabs.opened.map((e) => e.tab as TextBookTab);
    expect(opened.map((tab) => tab.searchText), ['כבוד אב', '']);
    expect(opened.last.initialSearchResultLines, {2});
    expect(harness.recorder.opens.map((open) => open.via), [
      SearchFeedbackOpenVia.click,
      SearchFeedbackOpenVia.click,
    ]);
    SemanticDwellBinding.resetForTesting();
  });

  testWidgets('גלילה לסוף טוענת עמוד ורושמת results_shown עם ההיסט', (
    tester,
  ) async {
    final harness = await pumpScreen(tester);

    // גלילה לסוף הרשימה טוענת את העמוד הבא, כמו "טען תוצאות נוספות".
    for (var i = 0; i < 4; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await settle(tester);
    }

    expect(harness.recorder.shown.map((page) => page.offset), [0, 30]);
    expect(harness.recorder.searches, hasLength(1));
  });

  testWidgets('כרטיסייה משוחזרת אינה מחפשת ואינה רושמת עד לחיצה', (
    tester,
  ) async {
    final harness = await pumpScreen(tester, runOnFirstShow: false);

    expect(harness.recorder.total, 0);
    expect(find.text('ספר 1, א'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('semantic-results-rerun')));
    await settle(tester);

    expect(find.text('ספר 1, א'), findsOneWidget);
    expect(harness.recorder.searches, hasLength(1));
  });
}

/// מחכה לעבודה האסינכרונית האמיתית (פענוח הספר) ולפריימים שאחריה.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

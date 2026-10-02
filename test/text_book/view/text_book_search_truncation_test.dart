import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/section_search_utils.dart';
import 'package:otzaria/text_book/view/text_book_search_screen.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../support/search_engine_test_init.dart';
import '../../test_helpers/memory_cache_provider.dart';

/// issue #1053 — חיווי חיתוך בסרגל תוצאות החיפוש בספר: כשהחיפוש נעצר
/// בתקרת התוצאות, הכיתוב הופך ל"מוצגות N התוצאות הראשונות" במקום
/// "נמצאו N תוצאות" — אחרת המשתמש מניח שאלו כל ההופעות בספר.
Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    DataRepository.instance.library = Future.value(
      Library(categories: const []),
    );
  });

  Future<void> pumpSearchView(
    WidgetTester tester, {
    required SearchRepository searchRepository,
    required String initialQuery,
  }) async {
    final textBookBloc = _TestTextBookBloc(_loadedState());
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    final focusNode = FocusNode();

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await textBookBloc.close();
      await settingsBloc.close();
      focusNode.dispose();
      await resetSectionSearchWorkerForTesting();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: TextBookSearchView(
              contentLoader: () async => const ['שורה א'],
              scrollControler: ItemScrollController(),
              focusNode: focusNode,
              closeLeftPaneCallback: () {},
              initialQuery: initialQuery,
              initialSearchDistance: 2,
              searchRepository: searchRepository,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  testWidgets(
    'מעל תקרת התצוגה — "מוצגות 1000 התוצאות הראשונות"',
    (tester) async {
      final repository = _FixedResultsRepository(
        results: List.generate(
          1001,
          (i) => _result(title: 'ספר בדיקה', reference: 'קטע $i', segment: i),
        ),
      );

      await pumpSearchView(
        tester,
        searchRepository: repository,
        initialQuery: 'תדע זרעך',
      );
      await settle(tester);

      expect(find.text('מוצגות 1000 התוצאות הראשונות'), findsOneWidget);
      expect(find.textContaining('נמצאו'), findsNothing);
    },
    skip: !engineReady,
  );

  testWidgets(
    'מתחת לתקרה — הכיתוב הרגיל "נמצאו N תוצאות" נשאר',
    (tester) async {
      final repository = _FixedResultsRepository(
        results: [
          _result(title: 'ספר בדיקה', reference: 'קטע א', segment: 0),
        ],
      );

      await pumpSearchView(
        tester,
        searchRepository: repository,
        initialQuery: 'תדע זרעך',
      );
      await settle(tester);

      expect(find.text('נמצאו 1 תוצאות'), findsOneWidget);
      expect(find.textContaining('הראשונות'), findsNothing);
    },
    skip: !engineReady,
  );
}

SearchResult _result({
  required String title,
  required String reference,
  required int segment,
}) {
  return SearchResult(
    id: BigInt.from(segment + 1),
    title: title,
    reference: reference,
    text: 'ידע <font color=red>תדע</font> יהיה <font color=red>זרעך</font>',
    segment: BigInt.from(segment),
    isPdf: false,
    filePath: 'id:1',
    mergedCount: 1,
    merged: const [],
    textStatus: TextStatus.ok,
  );
}

class _FixedResultsRepository extends SearchRepository {
  const _FixedResultsRepository({required this.results});

  final List<SearchResult> results;

  @override
  Future<List<SearchResult>> searchTexts(
    String query,
    List<String> facets,
    int limit, {
    int offset = 0,
    ResultsOrder order = ResultsOrder.relevance,
    bool fuzzy = false,
    int distance = 0,
    String negativeQuery = '',
    int? negativeDistance,
    SearchScope scope = SearchScope.wordDistance,
    SearchScope? negativeScope,
    SearchMode searchMode = SearchMode.exact,
    Map<String, String>? customSpacing,
    Map<String, String>? negativeCustomSpacing,
    Map<int, List<String>>? alternativeWords,
    Map<int, List<String>>? negativeAlternativeWords,
    Map<String, Map<String, bool>>? searchOptions,
    Map<String, Map<String, bool>>? negativeSearchOptions,
    bool matchNikud = false,
    bool matchTaamim = false,
    ResultGrouping? grouping,
    WordMatchMode wordMatchMode = WordMatchMode.all,
    int? wordMatchCount,
  }) async {
    return results;
  }
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TextBookLoaded _loadedState() {
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: true,
    content: const ['שורה א'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    visibleLinks: const [],
    linksByLine: const {},
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0],
    selectedIndex: 0,
    pinLeftPane: false,
    searchText: '',
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );
}

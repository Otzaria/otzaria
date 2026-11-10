import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/search_results.dart';
import 'package:otzaria/text_book/utils/section_search_utils.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';
import 'package:otzaria/text_book/view/text_book_search_screen.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';

import '../../test_helpers/memory_cache_provider.dart';
import '../../test_helpers/stub_settings_bloc.dart';

/// מעבר לתוצאה הבאה/הקודמת משנה רק את הבחירה, ולכן אינו אמור לחתוך
/// ולהדגיש מחדש את הקטע של כל שורה גלויה.
Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Future<void> pumpWithResults(WidgetTester tester) async {
    final textBookBloc = _TestTextBookBloc(_loadedState());
    final settingsBloc = StubSettingsBloc(SettingsState.initial());
    final focusNode = FocusNode();
    addTearDown(textBookBloc.close);
    addTearDown(settingsBloc.close);
    addTearDown(focusNode.dispose);
    addTearDown(resetSectionSearchWorkerForTesting);

    Future<List<TextSearchResult>> runner(List<String> c, String q) async => [
      for (var i = 0; i < 6; i++)
        TextSearchResult(
          snippet: 'שורה $i אור',
          index: i,
          query: q,
          address: 'פרק ${i ~/ 2}',
          matchOffset: 0,
        ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: TextBookSearchView(
              contentLoader: () async => List.filled(6, 'אור'),
              lines: LineScrollController(),
              focusNode: focusNode,
              closeLeftPaneCallback: () {},
              initialQuery: 'אור',
              simpleSearchRunner: runner,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder snippetOf(int i) => find.byWidgetPredicate(
    (w) => w is RichText && w.text.toPlainText().startsWith('שורה $i '),
  );

  bool isSelected(WidgetTester tester, int i) => tester
      .widget<NavTreeContentRow>(
        find.ancestor(
          of: snippetOf(i),
          matching: find.byType(NavTreeContentRow),
        ),
      )
      .isSelected;

  VoidCallback? navTap(WidgetTester tester, String tooltip) => tester
      .widget<InkWell>(
        find.descendant(
          of: find.byTooltip(tooltip),
          matching: find.byType(InkWell),
        ),
      )
      .onTap;

  testWidgets('מעבר לתוצאה הבאה אינו בונה מחדש את שורות התוצאות', (
    tester,
  ) async {
    await pumpWithResults(tester);
    final before = tester.widget(snippetOf(4));

    await tester.tap(find.byTooltip('התוצאה הבאה'));
    await tester.pump();

    expect(identical(tester.widget(snippetOf(4)), before), isTrue);
  });

  testWidgets('הבחירה וכפתורי הניווט מתעדכנים במעבר בין תוצאות', (
    tester,
  ) async {
    await pumpWithResults(tester);
    expect(isSelected(tester, 0), isTrue);
    expect(navTap(tester, 'התוצאה הקודמת'), isNull);

    await tester.tap(find.byTooltip('התוצאה הבאה'));
    await tester.pump();
    expect(isSelected(tester, 0), isFalse);
    expect(isSelected(tester, 1), isTrue);
    expect(navTap(tester, 'התוצאה הקודמת'), isNotNull);

    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byTooltip('התוצאה הבאה'));
      await tester.pump();
    }
    expect(isSelected(tester, 5), isTrue);
    expect(isSelected(tester, 1), isFalse);
    expect(navTap(tester, 'התוצאה הבאה'), isNull);

    await tester.tap(snippetOf(2));
    await tester.pump();
    expect(isSelected(tester, 2), isTrue);
    expect(isSelected(tester, 5), isFalse);
    expect(navTap(tester, 'התוצאה הבאה'), isNotNull);
  });
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TextBookLoaded _loadedState() {
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: true,
    content: List.filled(6, 'אור'),
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
  );
}

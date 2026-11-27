import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/text_book/view/reader_line/reader_line_render.dart';
import 'package:otzaria/text_book/view/widgets/selection_gutter_painter.dart';
import 'package:otzaria/widgets/smart_text/smart_text.dart';

import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/stub_personal_notes_bloc.dart';
import '../../../test_helpers/stub_settings_bloc.dart';
import '../../../test_helpers/stub_text_book_bloc.dart';

/// בחירת שורה בקורא בונה מחדש רק את הפריטים שהבחירה בהם השתנתה, ולא את כל
/// השורות הגלויות (perf2, Refs #1692).
final List<String> _lines = [
  for (var i = 0; i < 100; i++) 'שורה $i בספר הבדיקה',
];

TextBookLoaded _state({int? selectedIndex, int? highlightedLine}) =>
    TextBookLoaded(
      book: TextBook(title: 'ספר בחירה'),
      showLeftPane: false,
      content: _lines,
      fontSize: 18,
      showSplitView: true,
      activeCommentators: const [],
      commentatorGroups: const [],
      availableCommentators: const [],
      links: const [],
      linksByLine: const {},
      tableOfContents: const [],
      visibleIndices: const [0],
      selectedIndex: selectedIndex,
      selectedIndices: {?selectedIndex},
      highlightedLine: highlightedLine,
      searchText: '',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Future<EmittingStubTextBookBloc> mount(WidgetTester tester) async {
    final initial = _state();
    final bloc = EmittingStubTextBookBloc(initial);
    final notes = StubPersonalNotesBloc(const PersonalNotesState.initial());
    final settings = StubSettingsBloc(SettingsState.initial());
    final tab = TextBookTab(book: initial.book, index: 0);
    addTearDown(bloc.close);
    addTearDown(notes.close);
    addTearDown(settings.close);
    addTearDown(tab.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: bloc),
            BlocProvider<PersonalNotesBloc>.value(value: notes),
            BlocProvider<SettingsBloc>.value(value: settings),
          ],
          child: Scaffold(
            body: CombinedView(
              data: initial.content,
              openBookCallback: (_) {},
              openLeftPaneTab: (_, {searchText}) {},
              textSize: 18,
              showCommentaryAsExpansionTiles: false,
              tab: tab,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return bloc;
  }

  /// ההחלפה מגיעה לקורא בפריים שאחרי ה-emit.
  Future<void> emit(
    WidgetTester tester,
    EmittingStubTextBookBloc bloc,
    TextBookLoaded state,
  ) async {
    bloc.emitState(state);
    await tester.pump();
    await tester.pump();
  }

  /// מספר בניות [SmartTextWidget] בזמן [body].
  Future<int> countLineBuilds(Future<void> Function() body) async {
    var builds = 0;
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is SmartTextWidget) builds++;
    };
    try {
      await body();
    } finally {
      debugOnRebuildDirtyWidget = previous;
    }
    return builds;
  }

  Finder gutterOn(int line) => find.descendant(
    of: find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is SelectionGutterPainter,
    ),
    matching: find.byWidgetPredicate(
      (w) => w is ReaderLineBlock && w.lineIndex == line,
    ),
  );

  testWidgets('בחירת שורה בונה מחדש רק את השורות שהבחירה בהן השתנתה', (
    tester,
  ) async {
    final bloc = await mount(tester);
    final visible = find.byType(SmartTextWidget).evaluate().length;
    expect(visible, greaterThan(10));

    final first = await countLineBuilds(() async {
      await emit(tester, bloc, _state(selectedIndex: 3));
    });
    expect(first, lessThanOrEqualTo(1));
    expect(gutterOn(3), findsOneWidget);

    final second = await countLineBuilds(() async {
      await emit(tester, bloc, _state(selectedIndex: 5));
    });
    expect(second, lessThanOrEqualTo(2));
    expect(gutterOn(5), findsOneWidget);
    expect(gutterOn(3), findsNothing);

    final cleared = await countLineBuilds(() async {
      await emit(tester, bloc, _state());
    });
    expect(cleared, lessThanOrEqualTo(1));
    expect(gutterOn(5), findsNothing);
  });

  testWidgets('שינוי שאינו בחירה עדיין בונה את כל השורות הגלויות', (
    tester,
  ) async {
    final bloc = await mount(tester);
    await emit(tester, bloc, _state(selectedIndex: 3));
    final visible = find.byType(SmartTextWidget).evaluate().length;

    final builds = await countLineBuilds(() async {
      await emit(tester, bloc, _state(selectedIndex: 3, highlightedLine: 6));
    });
    expect(builds, greaterThanOrEqualTo(visible));
    expect(gutterOn(3), findsOneWidget);
  });
}

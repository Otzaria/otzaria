import 'dart:async';

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
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/text_book/utils/reading_position.dart';
import 'package:otzaria/text_book/view/reader_line/reader_line_render.dart';
import 'package:otzaria/text_book/view/widgets/unloaded_paragraph_placeholder.dart';
import 'package:otzaria/tools/dictionary/widgets/laaz_commentary_subblock.dart';

import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/stub_personal_notes_bloc.dart';
import '../../../test_helpers/stub_settings_bloc.dart';

/// ספר בצורת משנה ברורה: 18 אלף שורות, כותרת סימן כל 10 שורות, TOC של
/// רשומה אחת, ורק תחילתו נטענה כשקופצים רחוק.
const _count = 18119;
const _target = 1993;
final List<String> _lines = [
  for (var i = 0; i < _count; i++)
    i % 10 == 0
        ? '<h2>סימן ${i ~/ 10}</h2>'
        : '(א) היה קורא - ה"ה לד"ת שאם היה עוסק בתורה ונכנס לבית הכנסת '
              'ומצא צבור שקורין ק"ש צריך לקרות עמהם פסוק ראשון $i',
];

List<bool> _loaded(List<(int, int)> ranges) => [
  for (var i = 0; i < _count; i++) ranges.any((r) => i >= r.$1 && i <= r.$2),
];

TextBookLoaded _state(List<bool> loaded, {int version = 1}) => TextBookLoaded(
  book: _Book(),
  showLeftPane: false,
  content: [for (var i = 0; i < _count; i++) loaded[i] ? _lines[i] : ''],
  contentVersion: version,
  fontSize: 18,
  showSplitView: false,
  activeCommentators: const [],
  commentatorGroups: const [],
  availableCommentators: const [],
  links: const [],
  linksByLine: const {},
  tableOfContents: [TocEntry(text: 'משנה ברורה', index: 0)],
  visibleIndices: const [0],
  searchText: '',
  supportsContinuousReadingMode: true,
  continuousReadingMode: false,
  loadedLineFlags: loaded,
);

class _Book extends TextBook {
  _Book() : super(title: 'ספר שורות לא טעונות');
}

class _Bloc extends Bloc<TextBookEvent, TextBookState> implements TextBookBloc {
  _Bloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }
  void emitForTest(TextBookState state) => emit(state);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<(TextBookTab, _Bloc)> _mount(
  WidgetTester tester,
  TextBookLoaded initial,
) async {
  final bloc = _Bloc(initial);
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
            showCommentaryAsExpansionTiles: true,
            tab: tab,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (tab, bloc);
}

int _builtItems() =>
    find.byType(ReaderLineBlock, skipOffstage: false).evaluate().length +
    find
        .byType(UnloadedParagraphPlaceholder, skipOffstage: false)
        .evaluate()
        .length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets('קפיצה רחוקה לאזור שלא נטען בונה רק את פריטי התצוגה', (
    tester,
  ) async {
    final (tab, _) = await _mount(tester, _state(_loaded([(0, 1500)])));
    final loadedJump = _builtItems();

    unawaited(tab.lines.jumpToLine(_target));
    await tester.pump();

    // שורה לא טעונה בגובה אפס אילצה את הרשימה לבנות מאות פריטים כדי למלא
    // את התצוגה ואת אזור המטמון.
    expect(_builtItems(), lessThan(loadedJump * 5));
  });

  testWidgets('אחרי טעינת היעד הקפיצה נוחתת עליו, ושורה ריקה טעונה נשארת '
      'בגובה אפס', (tester) async {
    final (tab, bloc) = await _mount(tester, _state(_loaded([(0, 1500)])));

    final navigation = tab.lines.jumpToLine(_target);
    await tester.pump();
    final loaded = _loaded([(0, 1500), (_target - 120, _target + 260)]);
    final state = _state(loaded, version: 2);
    final emptyLine = _target + 1;
    state.content[emptyLine] = '';
    bloc.emitForTest(state);
    await tester.pumpAndSettle();
    await navigation;

    final segments = readingSegmentsOf(state);
    final position = tab.lines.positionsListener.itemPositions.value.firstWhere(
      (p) => p.index == segments.layout.itemForLine(_target),
    );
    expect(
      lineEdgesInViewport(
        segments,
        _target,
        position,
        measure: tab.lines.itemBoxes.lineExtent,
      ).leading,
      closeTo(kReadingAnchorAlignment, 0.01),
    );
    final empty = tester.getSize(
      find.byWidgetPredicate(
        (w) => w is ReaderLineBlock && w.lineIndex == emptyLine,
      ),
    );
    expect(empty.height, lessThan(10));
  });

  testWidgets('בלוק לעזי רש"י נשמר גם כשהשורה שלו טרם נטענה', (tester) async {
    final state = _state(
      _loaded([(0, 0), (2, 1500)]),
    ).copyWith(book: TextBook(title: 'רש"י על כתובות'));
    await _mount(tester, state);

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is LaazCommentarySubBlock && widget.rashiLineIndex == 2,
      ),
      findsOneWidget,
    );
  });
}

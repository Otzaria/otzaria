import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';
import 'package:otzaria/text_book/view/widgets/continuous_reading_paragraph.dart';
import 'package:otzaria/text_book/view/widgets/unloaded_paragraph_placeholder.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/reading_toc.dart';
import '../../../test_helpers/stub_settings_bloc.dart';

/// ניווט ומיקום במצב רציף נמדדים בשורות מקור: היעד יושב על קו העוגן גם
/// כשהוא באמצע פסקה ממוזגת, ולא בתחילתה.
const int _chapters = 30;
const int _verses = 10;
final List<String> _lines = [
  for (var chapter = 1; chapter <= _chapters; chapter++) ...[
    '<h2 id="chapter$chapter">פרק $chapter</h2>',
    for (var verse = 1; verse <= _verses; verse++)
      'פסוק $verse בפרק $chapter: דברי הברית אשר צוה לכרת את בני ישראל '
          'בארץ מואב מלבד הברית אשר כרת אתם בחרב',
  ],
];

int _line(int chapter, int verse) => (chapter - 1) * (_verses + 1) + verse;

List<bool> _window(int start, int end) => [
  for (var i = 0; i < _lines.length; i++) i >= start && i <= end,
];

TextBookLoaded _state(List<bool> loaded, {bool continuous = true}) {
  return TextBookLoaded(
    book: _NavigationBook(),
    showLeftPane: false,
    content: [
      for (var i = 0; i < _lines.length; i++) loaded[i] ? _lines[i] : '',
    ],
    contentVersion: loaded.where((f) => f).length,
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    linksByLine: const {},
    tableOfContents: headerToc(_lines),
    visibleIndices: const [0],
    pinLeftPane: false,
    searchText: '',
    supportsContinuousReadingMode: true,
    continuousReadingMode: continuous,
    loadedLineFlags: loaded,
  );
}

final _all = _window(0, _lines.length - 1);

class _NavigationBook extends TextBook {
  _NavigationBook() : super(title: 'ספר ניווט');

  @override
  Future<List<TocEntry>> get tableOfContents async => [
    for (var chapter = 1; chapter <= _chapters; chapter++)
      TocEntry(text: 'פרק $chapter', index: _line(chapter, 0)),
  ];
}

class _Fixture {
  _Fixture(this.tab, this.bloc);
  final TextBookTab tab;
  final _TestTextBookBloc bloc;
  LineScrollController get lines => tab.lines;
}

Future<_Fixture> _mount(
  WidgetTester tester,
  TextBookLoaded initial, {
  int index = 0,
  bool preview = false,
  bool outerScope = false,
  void Function(TextBookTab tab)? beforeMount,
}) async {
  final bloc = _TestTextBookBloc(initial);
  final notes = _TestPersonalNotesBloc(const PersonalNotesState.initial());
  final settings = StubSettingsBloc(SettingsState.initial());
  final tab = TextBookTab(book: initial.book, index: index);
  addTearDown(bloc.close);
  addTearDown(notes.close);
  addTearDown(settings.close);
  addTearDown(tab.dispose);
  beforeMount?.call(tab);
  final view = CombinedView(
    data: initial.content,
    openBookCallback: (_) {},
    openLeftPaneTab: (_, {searchText}) {},
    textSize: 18,
    showCommentaryAsExpansionTiles: true,
    isPreviewMode: preview,
    tab: tab,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: bloc),
          BlocProvider<PersonalNotesBloc>.value(value: notes),
          BlocProvider<SettingsBloc>.value(value: settings),
        ],
        child: Scaffold(
          body: outerScope
              ? LineScrollScope(controller: tab.lines, child: view)
              : view,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Fixture(tab, bloc);
}

/// מיקום תחילת [line] בתצוגה (חלק מגובהה), או null כשאינה מוצגת.
double? _lineEdge(_Fixture fixture, int line) {
  final state = fixture.bloc.state as TextBookLoaded;
  final segments = readingSegmentsOf(state);
  final item = segments.layout.itemForLine(line);
  final position = fixture.lines.positionsListener.itemPositions.value
      .where((p) => p.index == item)
      .firstOrNull;
  if (position == null) return null;
  return lineEdgesInViewport(
    segments,
    line,
    position,
    measure: fixture.lines.itemBoxes.lineExtent,
  ).leading;
}

Matcher get _onAnchor => closeTo(kReadingAnchorAlignment, 0.01);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  for (final preview in [true, false]) {
    for (final url in ['#chapter21', '#פרק 21']) {
      testWidgets('קישור $url בפסקה רציפה מנווט (תצוגה מקדימה: $preview)', (
        tester,
      ) async {
        final fixture = await _mount(
          tester,
          _state(_all),
          preview: preview,
          outerScope: !preview,
        );
        final paragraph = tester.widget<ContinuousReadingParagraph>(
          find.byType(ContinuousReadingParagraph).first,
        );

        final navigation = paragraph.onTapUrl!(url);
        await tester.pumpAndSettle();
        expect(await navigation, isTrue);
        expect(fixture.tab.index, _line(21, 0));
        expect(_lineEdge(fixture, _line(21, 0)), _onAnchor);
      });
    }
  }

  testWidgets('ניווט לשורה באמצע פסקה נוחת על השורה ולא על תחילת הפסקה', (
    tester,
  ) async {
    final fixture = await _mount(tester, _state(_all));
    final target = _line(21, 6);

    final navigation = fixture.lines.scrollToLine(target);
    await tester.pumpAndSettle();
    await navigation;

    expect(_lineEdge(fixture, target), _onAnchor);
    expect(fixture.tab.index, target);
    expect(fixture.lines.position.value?.topLine, target);
  });

  testWidgets('tab.index מתעדכן ליעד מיד, עוד לפני שהגלילה נחתה', (
    tester,
  ) async {
    final fixture = await _mount(tester, _state(_all));
    final target = _line(12, 4);

    final navigation = fixture.lines.scrollToLine(target);
    expect(fixture.tab.index, target);
    await tester.pumpAndSettle();
    await navigation;
    expect(fixture.tab.index, target);
  });

  testWidgets('החלפת מצב רגיל↔רציף שומרת את השורה המדויקת', (tester) async {
    final fixture = await _mount(tester, _state(_all));
    final target = _line(17, 7);
    final navigation = fixture.lines.jumpToLine(target);
    await tester.pumpAndSettle();
    await navigation;
    expect(fixture.tab.index, target);

    fixture.bloc.emitForTest(_state(_all, continuous: false));
    await tester.pumpAndSettle();
    expect(fixture.tab.index, target, reason: 'רציף → רגיל');
    expect(_lineEdge(fixture, target), _onAnchor);

    fixture.bloc.emitForTest(_state(_all));
    await tester.pumpAndSettle();
    expect(fixture.tab.index, target, reason: 'רגיל → רציף');
    expect(_lineEdge(fixture, target), _onAnchor);
  });

  testWidgets('יעד שנקבע לפני החיבור נוחת על השורה', (tester) async {
    final target = _line(25, 8);
    final fixture = await _mount(
      tester,
      _state(_all),
      beforeMount: (tab) => tab.lines.scrollToLine(target),
    );
    expect(fixture.tab.index, target);
    expect(_lineEdge(fixture, target), _onAnchor);
  });

  testWidgets(
    'יעד בפסקה שטרם נטענה ממתין לה, ונוחת על השורה כשהיא נטענת',
    (tester) async {
      final target = _line(21, 9);
      final partial = _state(_window(_line(21, 9) - 2, _line(21, 9) + 40));
      final fixture = await _mount(
        tester,
        partial,
        index: target,
        beforeMount: (tab) => tab.lines.jumpToLine(target),
      );
      expect(fixture.tab.index, target, reason: 'מקום שמור אינו דורס את היעד');

      fixture.bloc.emitForTest(_state(_all));
      await tester.pumpAndSettle();
      expect(fixture.tab.index, target);
      expect(_lineEdge(fixture, target), _onAnchor);
    },
  );

  testWidgets('פסקה שנטענת מעל התצוגה אינה מזיזה את הטקסט', (tester) async {
    // פרק 21 טרם נטען; הקורא קופץ לכותרתו וגולל קדימה אל פרק 22, כך שהמקום
    // השמור נמצא בין עוגן הרשימה לראש התצוגה.
    final loaded = [
      for (var i = 0; i < _lines.length; i++)
        i <= _line(21, 0) || i >= _line(22, 0),
    ];
    final fixture = await _mount(tester, _state(loaded));
    final navigation = fixture.lines.jumpToLine(_line(21, 0));
    await tester.pumpAndSettle();
    await navigation;
    await tester.drag(
      find.byType(ScrollablePositionedList),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    final top = fixture.tab.index;
    expect(top, greaterThan(_line(22, 0)), reason: 'המקום השמור מעל התצוגה');
    final edgeBefore = _lineEdge(fixture, top)!;

    fixture.bloc.emitForTest(_state(_all));
    await tester.pumpAndSettle();

    expect(fixture.tab.index, top);
    final viewport = tester.getSize(find.byType(ScrollablePositionedList));
    expect(
      (_lineEdge(fixture, top)! - edgeBefore) * viewport.height,
      closeTo(0, 1),
    );
  });

  testWidgets('פסקה שטרם נטענה מוצגת כמקום שמור ומוחלפת במקומה כשהיא נטענת', (
    tester,
  ) async {
    final fixture = await _mount(tester, _state(_window(0, _line(1, 0))));
    int itemCount() => tester
        .widget<ScrollablePositionedList>(find.byType(ScrollablePositionedList))
        .itemCount;
    final countBefore = itemCount();
    final placeholder = find.byType(UnloadedParagraphPlaceholder);
    expect(placeholder, findsWidgets);
    final placeholderTop = tester.getTopLeft(placeholder.first).dy;

    fixture.bloc.emitForTest(_state(_all));
    await tester.pumpAndSettle();

    expect(itemCount(), countBefore);
    expect(placeholder, findsNothing);
    final paragraph = find.byWidgetPredicate(
      (widget) =>
          widget is ContinuousReadingParagraph &&
          widget.lines.first.lineIndex == _line(1, 1),
    );
    expect(paragraph, findsOneWidget);
    expect(tester.getTopLeft(paragraph).dy, closeTo(placeholderTop, 4));
  });

  testWidgets('יציאה מצורת הדף ממקמת את השורה הנבחרת בתצוגה הבאה', (
    tester,
  ) async {
    final selected = _line(9, 6);
    final fixture = await _mount(
      tester,
      _state(_all),
      beforeMount: (tab) => tab.lines.scrollToLineOnNextAttach(selected),
    );
    expect(fixture.tab.index, selected);
    expect(_lineEdge(fixture, selected), _onAnchor);
  });
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }
  void emitForTest(TextBookState state) => emit(state);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPersonalNotesBloc
    extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _TestPersonalNotesBloc(super.initialState) {
    on<PersonalNotesEvent>((event, emit) {});
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

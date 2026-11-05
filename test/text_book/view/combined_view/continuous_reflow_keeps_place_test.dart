import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/reading_position.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/text_book/view/widgets/continuous_reading_paragraph.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/reading_toc.dart';

const int _chapters = 30;
const int _versesPerChapter = 10;
final List<String> _content = [
  for (var chapter = 1; chapter <= _chapters; chapter++) ...[
    '<h2>פרק $chapter</h2>',
    for (var verse = 1; verse <= _versesPerChapter; verse++)
      'פסוק $verse בפרק $chapter: דברי הברית אשר צוה לכרת את בני ישראל '
          'בארץ מואב מלבד הברית אשר כרת אתם בחרב',
  ],
];
const int _targetLine = 20 * (_versesPerChapter + 1) + 5; // פרק 21

final _longLines = [
  for (var chapter = 1; chapter <= 3; chapter++) ...[
    '<h2>פרק $chapter</h2>',
    for (var verse = 1; verse <= 300; verse++)
      'פסוק $verse בפרק $chapter: דברי הברית אשר צוה לכרת את בני ישראל '
          'בארץ מואב מלבד הברית אשר כרת אתם בחרב',
  ],
];
List<bool> _longWindow(int start, int end) => [
  for (var i = 0; i < _longLines.length; i++) i >= start && i <= end,
];

TextBookLoaded _state(
  List<bool> loaded, {
  String searchText = '',
  List<String>? lines,
}) {
  lines ??= _content;
  final content = [
    for (var i = 0; i < lines.length; i++) loaded[i] ? lines[i] : '',
  ];
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: content,
    contentVersion: loaded.where((f) => f).length,
    fontSize: 18,
    showSplitView: false,
    showPageShapeView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    visibleLinks: const [],
    linksByLine: const {},
    tableOfContents: headerToc(lines),
    removeNikud: false,
    visibleIndices: const [_targetLine],
    pinLeftPane: false,
    searchText: searchText,
    supportsContinuousReadingMode: true,
    continuousReadingMode: true,
    loadedLineFlags: loaded,
  );
}

List<bool> _window(int start, int end) => [
  for (var i = 0; i < _content.length; i++) i >= start && i <= end,
];

Future<({TextBookTab tab, _TestTextBookBloc bloc})> _mount(
  WidgetTester tester,
  TextBookLoaded initial,
  int targetLine,
) async {
  final bloc = _TestTextBookBloc(initial);
  final notes = _TestPersonalNotesBloc(const PersonalNotesState.initial());
  final settings = _TestSettingsBloc(SettingsState.initial());
  final tab = TextBookTab(book: initial.book, index: targetLine);
  addTearDown(bloc.close);
  addTearDown(notes.close);
  addTearDown(settings.close);
  addTearDown(tab.dispose);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('he', 'IL'),
      home: MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: bloc),
          BlocProvider<PersonalNotesBloc>.value(value: notes),
          BlocProvider<SettingsBloc>.value(value: settings),
        ],
        child: Scaffold(
          body: BlocBuilder<TextBookBloc, TextBookState>(
            builder: (context, state) => CombinedView(
              data: (state as TextBookLoaded).content,
              openBookCallback: (_) {},
              openLeftPaneTab: (_, {searchText}) {},
              textSize: 18,
              showCommentaryAsExpansionTiles: true,
              tab: tab,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  bloc.emitForTest(initial.copyWith(visibleIndices: [targetLine]));
  await tester.pumpAndSettle();
  return (tab: tab, bloc: bloc);
}

// בלי חיפוש הבדיקה אינה נזקקת למנוע החיפוש הנייטיב.
Future<void> _backgroundLoadKeepsPlace(
  WidgetTester tester,
  String searchText,
) async {
  final book = TextBook(title: 'ספר בדיקה');
  final partial = _state(
    _window(_targetLine - 30, _targetLine + 60),
    searchText: searchText,
  );
  final textBookBloc = _TestTextBookBloc(partial);
  final personalNotesBloc = _TestPersonalNotesBloc(
    const PersonalNotesState.initial(),
  );
  final settingsBloc = _TestSettingsBloc(SettingsState.initial());
  final tab = TextBookTab(book: book, index: _targetLine);
  addTearDown(textBookBloc.close);
  addTearDown(personalNotesBloc.close);
  addTearDown(settingsBloc.close);
  addTearDown(tab.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: textBookBloc),
          BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
        ],
        child: Scaffold(
          body: CombinedView(
            data: partial.content,
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
  expect(find.textContaining('פסוק 5 בפרק 21'), findsOneWidget);

  // העדכון הראשון שהתצוגה רואה הוא השורות הגלויות, כמו ב-bloc האמיתי.
  textBookBloc.emitForTest(
    partial.copyWith(visibleIndices: [tab.index, tab.index + 1]),
  );
  await tester.pumpAndSettle();
  final placeBeforeWarming = tab.index;
  expect(placeBeforeWarming, inInclusiveRange(_targetLine - 20, _targetLine));

  // חימום הרקע טוען את כל מה שלפני החלון — עשרות פסקאות מתמלאות לפני
  // המקום הנוכחי.
  final warmed = _state(_window(0, _targetLine + 60), searchText: searchText);
  textBookBloc.emitForTest(
    warmed.copyWith(visibleIndices: [tab.index, tab.index + 1]),
  );
  await tester.pumpAndSettle();
  expect(
    tab.index,
    placeBeforeWarming,
    reason: 'issue #1973: הרשימה קפצה למקום אחר אחרי טעינת תחילת הספר',
  );
  expect(find.textContaining('פסוק 5 בפרק 21'), findsOneWidget);

  // השלמת הטעינה אחרי החלון אינה נוגעת במספור שלפניו.
  final full = _state(_window(0, _content.length - 1), searchText: searchText);
  textBookBloc.emitForTest(
    full.copyWith(visibleIndices: [tab.index, tab.index + 1]),
  );
  await tester.pumpAndSettle();
  expect(tab.index, placeBeforeWarming);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets('ניווט פעיל נוחת ביעד כשהפסקה נטענת ברקע', (tester) async {
    final partial = _state(_longWindow(420, 510), lines: _longLines);
    final fixture = await _mount(tester, partial, 450);
    final navigation = fixture.tab.lines.scrollToLine(
      450,
      alignment: kSearchResultAnchorAlignment,
    );
    await tester.pump(const Duration(milliseconds: 60));
    final full = _state(
      _longWindow(0, _longLines.length - 1),
      lines: _longLines,
    );
    fixture.bloc.emitForTest(full);
    await tester.pumpAndSettle();
    await navigation;
    final item = readingLayoutOf(full).itemForLine(450);
    final position = fixture.tab.lines.positionsListener.itemPositions.value
        .singleWhere((p) => p.index == item);
    final edge = lineEdgesInViewport(
      readingSegmentsOf(full),
      450,
      position,
      measure: fixture.tab.lines.itemBoxes.lineExtent,
    ).leading;
    expect(edge, closeTo(kSearchResultAnchorAlignment, kAnchorLandingEpsilon));
  });

  testWidgets('עדכון תוכן אינו שולח ניווט לקורא חיצוני', (
    tester,
  ) async {
    final partial = _state(_longWindow(420, 510), lines: _longLines);
    final fixture = await _mount(tester, partial, 450);
    fixture.bloc.emitForTest(_state(_longWindow(0, 510), lines: _longLines));
    await tester.idle();
    await tester.pump();
    final navigations = <int>[];
    fixture.tab.lines.externalNavigator = (line) async => navigations.add(line);
    await tester.pumpAndSettle();
    expect(navigations, isEmpty);
    fixture.tab.lines.externalNavigator = null;
  });

  testWidgets('החלפת מצב אחרי עדכון תוכן משמרת את יעד החלפת המצב', (
    tester,
  ) async {
    final partial = _state(_longWindow(420, 510), lines: _longLines);
    final fixture = await _mount(tester, partial, 450);
    final warmed = _state(_longWindow(0, 510), lines: _longLines);
    fixture.bloc.emitForTest(warmed);
    await tester.idle();
    await tester.pump();
    final target = fixture.tab.lines.captureAnchor()!;
    final beforeSegments = readingSegmentsOf(warmed);
    final beforePosition = fixture
        .tab
        .lines
        .positionsListener
        .itemPositions
        .value
        .singleWhere(
          (p) => p.index == beforeSegments.layout.itemForLine(target.line),
        );
    final beforeEdges = lineEdgesInViewport(
      beforeSegments,
      target.line,
      beforePosition,
      measure: fixture.tab.lines.itemBoxes.lineExtent,
    );
    expect(beforeEdges.trailing, greaterThan(beforeEdges.leading));
    final regular = warmed.copyWith(continuousReadingMode: false);
    fixture.bloc.emitForTest(regular);
    await tester.pumpAndSettle();
    final position = fixture.tab.lines.positionsListener.itemPositions.value
        .singleWhere(
          (p) => p.index == readingLayoutOf(regular).itemForLine(target.line),
        );
    final edges = lineEdgesInViewport(
      readingSegmentsOf(regular),
      target.line,
      position,
      measure: fixture.tab.lines.itemBoxes.lineExtent,
    );
    expect(edges.trailing, greaterThan(edges.leading));
    expect(
      edges.leading +
          target.intraLineFraction * (edges.trailing - edges.leading),
      closeTo(target.alignment, kAnchorLandingEpsilon),
    );
    expect(fixture.tab.lines.captureAnchor()!.line, target.line);
    expect(tester.takeException(), isNull);
  });

  testWidgets('שני עדכוני תוכן לפני frame משתמשים בפריסה שהוצגה', (
    tester,
  ) async {
    final partial = _state(_window(_targetLine - 30, _targetLine + 60));
    final fixture = await _mount(tester, partial, _targetLine);
    final before = fixture.tab.index;
    fixture.bloc.emitForTest(_state(_window(100, _targetLine + 60)));
    fixture.bloc.emitForTest(_state(_window(0, _content.length - 1)));
    await tester.pumpAndSettle();
    expect(fixture.tab.index, before);
  });

  for (final searchText in ['', 'בחרב']) {
    testWidgets(
      'טעינת רקע של תחילת הספר אינה מזיזה את מקום הקריאה, חיפוש="$searchText"',
      (tester) => _backgroundLoadKeepsPlace(tester, searchText),
    );
  }

  testWidgets('קישור עם mark מדגיש את השורה בתוך פסקה רציפה (issue #2057)', (
    tester,
  ) async {
    final state = _state(
      _window(0, _content.length - 1),
    ).copyWith(permanentHighlightLine: _targetLine);
    await _mount(tester, state, _targetLine);

    final lines = tester
        .widgetList<ContinuousReadingParagraph>(
          find.byType(ContinuousReadingParagraph),
        )
        .expand((paragraph) => paragraph.lines);
    // הרקע מצויר בשכבה לפי טווח השורה, לא כ-backgroundColor של הספאנים.
    expect(
      lines.where((line) => line.background != null).map((l) => l.lineIndex),
      [_targetLine],
    );
    final line = lines.singleWhere((line) => line.lineIndex == _targetLine);
    final scheme = Theme.of(
      tester.element(find.byType(ContinuousReadingParagraph).first),
    ).colorScheme;
    expect(line.background, AppSurfaces.permanentMark(scheme));
    expect(line.style.backgroundColor, isNull);
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

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
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
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/text_book/view/widgets/continuous_reading_paragraph.dart';
import 'package:otzaria/theme/app_colors.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../../test_helpers/memory_cache_provider.dart';

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
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [_targetLine],
    pinLeftPane: false,
    searchText: searchText,
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
    supportsContinuousReadingMode: true,
    continuousReadingMode: true,
    readingSegments: buildReadingSegments(
      content,
      continuous: true,
      loadedLineFlags: loaded,
    ),
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
  bloc.emitForTest(initial.copyWith(visibleIndices: [targetLine]));
  await tester.pumpAndSettle();
  return (tab: tab, bloc: bloc);
}

List<int> _visibleSources(TextBookLoaded state, TextBookTab tab) =>
    sourceLineIndicesForSegmentViewports(
      state.readingSegments,
      tab.positionsListener.itemPositions.value
          .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1)
          .map(
            (p) => ReadingSegmentViewport(
              segmentIndex: p.index,
              leadingEdge: p.itemLeadingEdge,
              trailingEdge: p.itemTrailingEdge,
            ),
          ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  group('reflowAnchor', () {
    // שלושה פרקים; בהתחלה הראשון לא טעון (סגמנט אחד), ואז נטען (שני סגמנטים).
    final partialFlags = [
      for (var i = 0; i < 33; i++) i >= 11,
    ];
    final partial = buildReadingSegments(
      [for (var i = 0; i < 33; i++) partialFlags[i] ? _content[i] : ''],
      continuous: true,
      loadedLineFlags: partialFlags,
    );
    final full = buildReadingSegments(
      _content.sublist(0, 33),
      continuous: true,
    );

    test('פריט שמספרו זז מעוגן במספרו החדש ובאותו גובה', () {
      // partial: [לא-טעון 0..10, כותרת 11, פסקה 12..21, כותרת 22, פסקה 23..32]
      // full:    [כותרת 0, פסקה 1..10, כותרת 11, פסקה 12..21, ...]
      final anchor = reflowAnchor(
        positions: const [
          ItemPosition(index: 2, itemLeadingEdge: -0.4, itemTrailingEdge: 0.3),
          ItemPosition(index: 3, itemLeadingEdge: 0.3, itemTrailingEdge: 0.4),
          ItemPosition(index: 4, itemLeadingEdge: 0.4, itemTrailingEdge: 1.2),
        ],
        previous: partial,
        current: full,
      );
      expect(anchor, (
        index: 3,
        alignment: -0.4,
        fraction: 0.0,
        estimatedExtent: 0.0,
      ));
    });

    test('מספור שלא זז — אין עיגון', () {
      final anchor = reflowAnchor(
        positions: const [
          ItemPosition(index: 3, itemLeadingEdge: 0.0, itemTrailingEdge: 0.9),
        ],
        previous: full,
        current: full,
      );
      expect(anchor, isNull);
    });

    test('עוגן גלוי שמספרו נשמר מפצה על פסקה שגדלה לפניו', () {
      final lines = [
        '<h2>פרק א</h2>',
        for (var i = 1; i < 31; i++) 'פסוק $i',
        '<h2>פרק ב</h2>',
        'פסוק ראשון',
      ];
      List<ReadingSegment> segments(int end) {
        final flags = [
          for (var i = 0; i < lines.length; i++) i <= end || i >= 31,
        ];
        return buildReadingSegments(
          [for (var i = 0; i < lines.length; i++) flags[i] ? lines[i] : ''],
          continuous: true,
          loadedLineFlags: flags,
        );
      }

      final anchor = reflowAnchor(
        positions: const [
          ItemPosition(index: 1, itemLeadingEdge: -0.4, itemTrailingEdge: 0.4),
          ItemPosition(index: 3, itemLeadingEdge: 0.5, itemTrailingEdge: 0.6),
        ],
        previous: segments(8),
        current: segments(18),
      );
      expect(anchor, (
        index: 3,
        alignment: 0.5,
        fraction: 0.0,
        estimatedExtent: 0.0,
      ));
    });

    test('פריטים מחוץ לתצוגה אינם נבחרים כעוגן', () {
      final anchor = reflowAnchor(
        positions: const [
          ItemPosition(index: 1, itemLeadingEdge: -2, itemTrailingEdge: -0.5),
          ItemPosition(index: 3, itemLeadingEdge: 0.1, itemTrailingEdge: 0.9),
        ],
        previous: partial,
        current: full,
      );
      expect(anchor, (
        index: 4,
        alignment: 0.1,
        fraction: 0.0,
        estimatedExtent: 0.0,
      ));
    });
  });

  testWidgets('פסקה יחידה שמתארכת מעל התצוגה שומרת את נקודת המקור', (
    tester,
  ) async {
    final partial = _state(_longWindow(420, 510), lines: _longLines);
    final fixture = await _mount(tester, partial, 450);
    fixture.tab.scrollController.jumpTo(
      index: segmentIndexForLine(partial.readingSegments, 450),
      alignment: -0.2,
    );
    await tester.pumpAndSettle();
    final before = _visibleSources(partial, fixture.tab).first;
    final warmed = _state(_longWindow(0, 510), lines: _longLines);
    fixture.bloc.emitForTest(warmed);
    await tester.idle();
    await tester.pump();
    await tester.pump();
    expect(
      _visibleSources(warmed, fixture.tab).first,
      before,
      reason: 'אסור לצייר את תחילת הפסקה בין שני תיקוני העיגון',
    );
    await tester.pumpAndSettle();
    expect(_visibleSources(warmed, fixture.tab).first, before);
    final full = _state(
      _longWindow(0, _longLines.length - 1),
      lines: _longLines,
    );
    fixture.bloc.emitForTest(full);
    await tester.pumpAndSettle();
    expect(_visibleSources(full, fixture.tab).first, before);
  });

  testWidgets('ניווט חדש בין פריימים מבטל עוגן ממתין', (tester) async {
    final partial = _state(_longWindow(420, 510), lines: _longLines);
    final fixture = await _mount(tester, partial, 450);
    final warmed = _state(_longWindow(0, 510), lines: _longLines);
    fixture.bloc.emitForTest(warmed);
    await tester.idle();
    await tester.pump();
    fixture.tab.scrollController.jumpTo(index: 0);
    await tester.pumpAndSettle();
    expect(_visibleSources(warmed, fixture.tab).first, 0);
  });

  testWidgets('פסקה שמתארכת באותו מספר פריט נמדדת ונעוגנת בקפיצה אחת', (
    tester,
  ) async {
    final partial = _state(_longWindow(0, 80), lines: _longLines);
    final fixture = await _mount(tester, partial, 40);
    fixture.tab.scrollController.jumpTo(index: 1, alignment: -2);
    await tester.pumpAndSettle();
    final before = _visibleSources(partial, fixture.tab).first;
    var jumps = 0;
    fixture.tab.scrollController.addBeforeJumpListener(() => jumps++);
    final warmed = _state(_longWindow(0, 200), lines: _longLines);
    fixture.bloc.emitForTest(warmed);
    await tester.pumpAndSettle();
    expect(_visibleSources(warmed, fixture.tab).first, before);
    expect(jumps, 1);
  });

  testWidgets('ניווט יחסי לפסקה גלויה מבטל תיקון עיגון ממתין', (tester) async {
    final partial = _state(_longWindow(420, 510), lines: _longLines);
    final fixture = await _mount(tester, partial, 450);
    final warmed = _state(_longWindow(0, 510), lines: _longLines);
    fixture.bloc.emitForTest(warmed);
    await tester.idle();
    await tester.pump();
    Future<void>? navigation;
    final generation = fixture.tab.scrollController.navigationGeneration;
    var jumps = 0;
    void onPosition() {
      final positions = fixture.tab.positionsListener.itemPositions.value;
      if (!positions.any((p) => p.index == 3)) return;
      fixture.tab.positionsListener.itemPositions.removeListener(onPosition);
      fixture.tab.scrollController.addBeforeJumpListener(() => jumps++);
      navigation = scrollToSourceLine(
        scrollController: fixture.tab.scrollController,
        scrollOffsetController: fixture.tab.mainOffsetController,
        positionsListener: fixture.tab.positionsListener,
        segments: warmed.readingSegments,
        lineIndex: 470,
        viewportExtent: tester.getSize(find.byType(CombinedView)).height,
        alignment: kReadingAnchorAlignment,
      );
      expect(
        fixture.tab.scrollController.navigationGeneration,
        generation + 1,
        reason: 'ניווט יחסי חייב להודיע לפני animateScroll',
      );
    }

    fixture.tab.positionsListener.itemPositions.addListener(onPosition);
    addTearDown(
      () => fixture.tab.positionsListener.itemPositions.removeListener(
        onPosition,
      ),
    );
    await tester.pumpAndSettle();
    expect(navigation, isNotNull);
    await navigation;
    expect(jumps, 0, reason: 'העוגן הישן אינו רשאי לקפוץ אחרי תחילת ניווט');
    final position = fixture.tab.positionsListener.itemPositions.value
        .singleWhere((p) => p.index == 3);
    final edge =
        position.itemLeadingEdge +
        lineFractionWithinSegment(warmed.readingSegments[3], 470) *
            (position.itemTrailingEdge - position.itemLeadingEdge);
    expect(edge, closeTo(kReadingAnchorAlignment, kAnchorLandingEpsilon));
  });

  for (final event in <PointerEvent>[
    const PointerScrollEvent(
      position: Offset(400, 300),
      scrollDelta: Offset(0, 100),
    ),
    const PointerPanZoomStartEvent(pointer: 10, position: Offset(400, 300)),
  ]) {
    testWidgets('${event.runtimeType} מבטל עיגון ממתין', (tester) async {
      final partial = _state(_longWindow(420, 510), lines: _longLines);
      final fixture = await _mount(tester, partial, 450);
      fixture.bloc.emitForTest(_state(_longWindow(0, 510), lines: _longLines));
      await tester.idle();
      await tester.pump();
      var jumps = 0;
      fixture.tab.scrollController.addBeforeJumpListener(() => jumps++);
      await tester.sendEventToBinding(event);
      if (event is PointerPanZoomStartEvent) {
        await tester.sendEventToBinding(
          const PointerPanZoomEndEvent(pointer: 10, position: Offset(400, 300)),
        );
      }
      await tester.pumpAndSettle();
      expect(jumps, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('ניווט פעיל נוחת ביעד כשפסקה מתארכת ברקע', (tester) async {
    final partial = _state(_longWindow(420, 510), lines: _longLines);
    final fixture = await _mount(tester, partial, 450);
    final navigation = scrollToSourceLine(
      scrollController: fixture.tab.scrollController,
      scrollOffsetController: fixture.tab.mainOffsetController,
      positionsListener: fixture.tab.positionsListener,
      segments: partial.readingSegments,
      latestSegments: () =>
          (fixture.bloc.state as TextBookLoaded).readingSegments,
      lineIndex: 450,
      viewportExtent: tester.getSize(find.byType(CombinedView)).height,
      alignment: kSearchResultAnchorAlignment,
    );
    await tester.pump(const Duration(milliseconds: 60));
    final warmed = _state(_longWindow(0, 510), lines: _longLines);
    fixture.bloc.emitForTest(warmed);
    await tester.pumpAndSettle();
    await navigation;
    final position = fixture.tab.positionsListener.itemPositions.value
        .singleWhere((p) => p.index == 3);
    final edge =
        position.itemLeadingEdge +
        lineFractionWithinSegment(warmed.readingSegments[3], 450) *
            (position.itemTrailingEdge - position.itemLeadingEdge);
    expect(edge, closeTo(kSearchResultAnchorAlignment, kAnchorLandingEpsilon));
  });

  testWidgets('סגירת התצוגה עם עוגן ממתין אינה גוללת קורא מנותק', (
    tester,
  ) async {
    final partial = _state(_longWindow(420, 510), lines: _longLines);
    final fixture = await _mount(tester, partial, 450);
    fixture.bloc.emitForTest(_state(_longWindow(0, 510), lines: _longLines));
    await tester.idle();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(fixture.tab.scrollController.isNativeAttached, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('החלפת קורא כשהעוגן ממתין אינה שולחת ניווט לתוסף', (
    tester,
  ) async {
    final partial = _state(_longWindow(420, 510), lines: _longLines);
    final fixture = await _mount(tester, partial, 450);
    fixture.bloc.emitForTest(_state(_longWindow(0, 510), lines: _longLines));
    await tester.idle();
    await tester.pump();
    final navigations = <int>[];
    fixture.tab.scrollController.externalScroll =
        (index, {sourceLineIndex}) async => navigations.add(index);
    await tester.pumpAndSettle();
    expect(navigations, isEmpty);
    fixture.tab.scrollController.externalScroll = null;
  });

  testWidgets('החלפת מצב עם עוגן ממתין משמרת את יעד החלפת המצב', (
    tester,
  ) async {
    final partial = _state(_longWindow(420, 510), lines: _longLines);
    final fixture = await _mount(tester, partial, 450);
    final warmed = _state(_longWindow(0, 510), lines: _longLines);
    fixture.bloc.emitForTest(warmed);
    await tester.idle();
    await tester.pump();
    final target = fixture.tab.index;
    fixture.bloc.emitForTest(
      warmed.copyWith(
        continuousReadingMode: false,
        readingSegments: buildReadingSegments(
          warmed.content,
          continuous: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final position = fixture.tab.positionsListener.itemPositions.value
        .singleWhere((p) => p.index == target);
    expect(
      position.itemLeadingEdge,
      closeTo(kReadingAnchorAlignment, kAnchorLandingEpsilon),
    );
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

  testWidgets('טעינת רקע של תחילת הספר אינה מזיזה את מקום הקריאה', (
    tester,
  ) async {
    final book = TextBook(title: 'ספר בדיקה');
    final partial = _state(
      _window(_targetLine - 30, _targetLine + 60),
      searchText: 'בחרב',
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

    // חימום הרקע טוען את כל מה שלפני החלון — עשרות פסקאות נכנסות לפני
    // המקום הנוכחי ומספרי הסגמנטים זזים.
    final warmed = _state(_window(0, _targetLine + 60), searchText: 'בחרב');
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
    final full = _state(_window(0, _content.length - 1), searchText: 'בחרב');
    textBookBloc.emitForTest(
      full.copyWith(visibleIndices: [tab.index, tab.index + 1]),
    );
    await tester.pumpAndSettle();
    expect(tab.index, placeBeforeWarming);
  });

  testWidgets('קישור עם mark מדגיש את השורה בתוך פסקה רציפה (issue #2057)', (
    tester,
  ) async {
    final state = _state(
      _window(0, _content.length - 1),
    ).copyWith(permanentHighlightLine: _targetLine);
    await _mount(tester, state, _targetLine);

    final line = tester
        .widgetList<ContinuousReadingParagraph>(
          find.byType(ContinuousReadingParagraph),
        )
        .expand((paragraph) => paragraph.lines)
        .singleWhere((line) => line.lineIndex == _targetLine);
    expect(line.style.backgroundColor, AppColors.permanentHighlight);
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

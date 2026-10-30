import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:positioned_sliver_list/positioned_list.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
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
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/widgets/lists/scroll_position_reanchor.dart';

import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/reading_toc.dart';

const _commentators = ['מפרש א', 'מפרש ב', 'מפרש ג', 'מפרש ד'];
const _segmentsPerCommentator = 4;
const _lineCount = 30;
const _cardLine = 1;

/// issue #1768: במצב "מפרשים מתחת לטקסט" גלילה ארוכה בתוך כרטיס המפרשים
/// קפצה כעבור רגע חזרה לראש הכרטיס, והמפרש הראשון נפתח מחדש.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    LibraryProviderManager.instance.resetForTesting();
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {
        for (final title in _commentators)
          BookCompositeKey.create(
            title: title,
            categoryId: 1,
            fileType: 'txt',
          ): _FakeLibraryProvider(),
      },
      providers: [_FakeLibraryProvider()],
    );
  });

  tearDown(() => LibraryProviderManager.instance.resetForTesting());

  testWidgets('גלילה ארוכה בכרטיס המפרשים אינה מחזירה אותו לראשו', (
    tester,
  ) async {
    await _pumpCombinedView(tester);

    final card = find.byType(CommentaryListBase);
    expect(card, findsOneWidget, reason: 'כרטיס המפרשים לא נפתח');
    ScrollableState innerScrollable() => tester.state<ScrollableState>(
      find.descendant(of: card, matching: find.byType(Scrollable)).first,
    );

    // הרשימה החיצונית זזה מעט, כך שהפריט הראשון שתחילתו במסך הוא פסקת
    // הכרטיס ולא העוגן הנוכחי — כמו בקריאה רגילה.
    await tester.dragFrom(const Offset(400, 10), const Offset(0, -20));
    await _settle(tester);
    await _settle(tester, _scrollRest);

    final listState = tester.state<CommentaryListBaseState>(card);
    final scrollableBefore = innerScrollable();
    final center = tester.getCenter(card);
    for (var i = 0; i < 12; i++) {
      tester.binding.handlePointerEvent(
        PointerScrollEvent(
          position: center,
          scrollDelta: const Offset(0, 100),
          kind: PointerDeviceKind.mouse,
        ),
      );
    }
    await _settle(tester);
    final pixels = innerScrollable().position.pixels;
    expect(
      pixels,
      greaterThan(innerScrollable().position.viewportDimension),
      reason: 'הגלילה בכרטיס קצרה מכדי להפעיל את העיגון',
    );

    await _settle(tester, _scrollRest);

    expect(
      tester.state<CommentaryListBaseState>(card),
      same(listState),
      reason: 'כרטיס המפרשים נבנה מחדש',
    );
    expect(innerScrollable(), same(scrollableBefore));
    expect(innerScrollable().position.pixels, pixels);
  });

  testWidgets('כרטיסים נבחרים מחוץ למטמון משתחררים ומשחזרים כיווץ וגלילה', (
    tester,
  ) async {
    const selected = {2, 42, 82};
    final linksByLine = {
      for (final line in selected)
        line + 1: [
          for (final title in _commentators)
            for (var segment = 0; segment < _segmentsPerCommentator; segment++)
              _link(title, segment, cardLine: line),
        ],
    };
    final content = [
      for (var line = 0; line < 200; line++)
        line % 10 == 0 ? '<h2>פרק $line</h2>' : 'שורה $line',
    ];
    final (tab, _) = await _pumpCombinedView(
      tester,
      initialState: _loadedState(lineCount: 200).copyWith(
        selectedIndices: selected,
        selectedIndex: 82,
        supportsContinuousReadingMode: true,
        content: content,
        tableOfContents: headerToc(content),
        links: linksByLine.values.expand((links) => links).toList(),
        linksByLine: linksByLine,
      ),
    );
    Finder cardAt(int line) => find.descendant(
      of: find.byKey(ValueKey('commentary_card_$line')),
      matching: find.byType(CommentaryListBase),
    );
    ScrollablePositionedList innerList(Finder card) =>
        tester.widget<ScrollablePositionedList>(
          find.descendant(
            of: card,
            matching: find.byType(ScrollablePositionedList),
          ),
        );
    ScrollableState innerScroll(Finder card) => tester.state<ScrollableState>(
      find.descendant(of: card, matching: find.byType(Scrollable)).first,
    );
    final firstCard = cardAt(2);
    expect(firstCard, findsOneWidget);
    final oldState = tester.state<CommentaryListBaseState>(firstCard);
    final oldKey =
        tester.widget<CommentaryListBase>(firstCard).key!
            as GlobalKey<CommentaryListBaseState>;
    await tester.tap(
      find.descendant(of: firstCard, matching: find.text('מפרש א')).first,
    );
    await _settle(tester);
    expect(innerList(firstCard).itemCount, 16);
    innerScroll(firstCard).position.jumpTo(350);
    await _settle(tester);
    final before = innerList(firstCard)
        .itemPositionsListener!
        .itemPositions
        .value
        .where((item) => item.itemTrailingEdge > 0 && item.itemLeadingEdge < 1)
        .reduce((a, b) => a.itemLeadingEdge < b.itemLeadingEdge ? a : b);
    final beforeOffset =
        before.itemLeadingEdge *
        innerScroll(firstCard).position.viewportDimension;
    final visitedStates = <CommentaryListBaseState>[oldState];
    for (final line in [42, 82, 162]) {
      tab.lines.itemController.jumpTo(index: line);
      await _settle(tester);
      if (selected.contains(line)) {
        visitedStates.add(tester.state<CommentaryListBaseState>(cardAt(line)));
      }
    }
    expect(visitedStates.every((state) => !state.mounted), isTrue);
    expect(oldKey.currentState, isNull);

    final bloc =
        tester.element(find.byType(CombinedView)).read<TextBookBloc>()
            as _TestTextBookBloc;
    for (final continuous in [false, true, false]) {
      bloc.emitState(
        (bloc.state as TextBookLoaded).copyWith(
          continuousReadingMode: continuous,
        ),
      );
      await _settle(tester);
      expect(
        tester
            .widget<ScrollablePositionedList>(
              find.byType(ScrollablePositionedList).first,
            )
            .itemCount,
        continuous ? 40 : 200,
      );
      final back = tab.lines.scrollToLine(2, duration: Duration.zero);
      await _settle(tester);
      await back;
      final restoredCard = cardAt(2);
      final restoredState = tester.state<CommentaryListBaseState>(restoredCard);
      expect(restoredState, isNot(same(oldState)));
      expect(innerList(restoredCard).itemCount, 16);
      final restored = innerList(restoredCard)
          .itemPositionsListener!
          .itemPositions
          .value
          .firstWhere((item) => item.index == before.index);
      expect(
        restored.itemLeadingEdge *
            innerScroll(restoredCard).position.viewportDimension,
        moreOrLessEquals(beforeOffset, epsilon: 1),
        reason: 'אבד מיקום הכרטיס במצב רציף=$continuous',
      );
      final leave = tab.lines.scrollToLine(162, duration: Duration.zero);
      await _settle(tester);
      await leave;
      expect(
        restoredState.mounted,
        isFalse,
        reason:
            'רציף=$continuous, שורה=${tab.lines.position.value?.topLine}, '
            'פריטים=${tab.lines.positionsListener.itemPositions.value.map((item) => item.index)}',
      );
    }
  });

  testWidgets('מרווח שורות אחרי ניווט אינו נסחף בגלל חוב של כרטיס שפורק', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const cardLine = 4;
    final (tab, settings) = await _pumpCombinedView(
      tester,
      initialState: _loadedState(
        cardLine: cardLine,
        lineCount: 120,
        multiline: true,
      ),
      lineHeight: 1,
    );
    final reanchor = find.byType(ScrollPositionReanchor).first;
    ScrollableState outerScrollable() => tester.state<ScrollableState>(
      find.descendant(of: reanchor, matching: find.byType(Scrollable)).first,
    );
    final first = tab.lines.positionsListener.itemPositions.value.firstWhere(
      (position) => position.index == 0,
    );
    final distance = first.itemTrailingEdge * 400 * cardLine - 20;
    expect(distance, inExclusiveRange(400, 800));
    outerScrollable().position.jumpTo(distance);
    await tester.pump();
    final card = find.byType(CommentaryListBase);
    expect(card, findsOneWidget);
    await tester.drag(card, const Offset(0, -150));
    await tester.pump();
    await _settle(tester, _scrollRest);

    tab.lines.itemController.jumpTo(index: 50);
    await _settle(tester);
    expect(find.byType(CommentaryListBase), findsNothing);
    final navigated = outerScrollable().position;
    navigated.jumpTo(navigated.pixels + 450);
    await _settle(tester, _scrollRest);
    final top = _firstItemStartingInView(
      tab.lines.positionsListener.itemPositions.value,
    )!;
    settings.changeLineHeight(3);
    await _settle(tester);
    final after = tab.lines.positionsListener.itemPositions.value
        .where((position) => position.index == top.index)
        .firstOrNull;
    expect(after, isNotNull, reason: 'פסקת הקריאה יצאה מהמסך');
    expect(
      after!.itemLeadingEdge,
      moreOrLessEquals(top.itemLeadingEdge, epsilon: 0.02),
    );
  });
}

/// פריימים קצובים במקום pumpAndSettle: שלד הטעינה של המפרשים מונפש.
Future<void> _settle(
  WidgetTester tester, [
  Duration extra = Duration.zero,
]) async {
  if (extra > Duration.zero) await tester.pump(extra);
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<(TextBookTab, _TestSettingsBloc)> _pumpCombinedView(
  WidgetTester tester, {
  TextBookLoaded? initialState,
  double? lineHeight,
}) async {
  final state = initialState ?? _loadedState();
  final textBookBloc = _TestTextBookBloc(state);
  final settingsBloc = _TestSettingsBloc(
    // ברוחב מלא יש סטייה ידועה ונפרדת בשחזור הגלילה הפנימית; מצמידים רוחב יעד.
    SettingsState.initial().copyWith(lineHeight: lineHeight, textMaxWidth: 700),
  );
  final personalNotesBloc = _TestPersonalNotesBloc(
    PersonalNotesState(
      isLoading: false,
      bookId: 'ספר בדיקה',
      locatedNotes: const [],
      missingNotes: const [],
      errorMessage: null,
      filteredLocatedNotes: const [],
      filteredMissingNotes: const [],
    ),
  );
  final tab = TextBookTab(book: TextBook(title: 'ספר בדיקה'), index: 0);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
    tab.dispose();
    await textBookBloc.close();
    await settingsBloc.close();
    await personalNotesBloc.close();
  });

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
            data: state.content,
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
  await _settle(tester);
  await _settle(tester, const Duration(milliseconds: 500));
  return (tab, settingsBloc);
}

Link _link(String title, int segment, {int cardLine = _cardLine}) => Link(
  heRef: 'קטע ${segment + 1}',
  index1: cardLine + 1,
  path2: '$title.txt',
  index2: segment + 1,
  connectionType: LinkTypes.commentary,
  targetCategoryId: 1,
  targetFileType: 'txt',
);

TextBookLoaded _loadedState({
  int cardLine = _cardLine,
  int lineCount = _lineCount,
  bool multiline = false,
}) {
  final links = [
    for (final title in _commentators)
      for (var segment = 0; segment < _segmentsPerCommentator; segment++)
        _link(title, segment, cardLine: cardLine),
  ];
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: [
      for (var i = 0; i < lineCount; i++)
        multiline
            ? 'שורה $i ${'טקסט עברי לבדיקת מרווח שורות ושמירת מקום הקריאה. ' * 5}'
            : 'שורה $i',
    ],
    fontSize: 18,
    showSplitView: false,
    showPageShapeView: false,
    activeCommentators: _commentators,
    commentatorGroups: [
      CommentatorGroup(title: 'ראשונים', commentators: _commentators),
    ],
    availableCommentators: _commentators,
    links: links,
    visibleLinks: const [],
    linksByLine: {cardLine + 1: links},
    linksLoading: false,
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: [cardLine],
    selectedIndex: cardLine,
    selectedIndices: {cardLine},
    pinLeftPane: false,
    searchText: '',
  );
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  void emitState(TextBookLoaded value) => emit(value);

  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  final TextBookRepository repository = _TestTextBookRepository();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestTextBookRepository implements TextBookRepository {
  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async => const [];

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
  void changeLineHeight(double height) =>
      emit(state.copyWith(lineHeight: height));

  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLibraryProvider implements LibraryProvider {
  @override
  String get displayName => 'Fake';

  @override
  bool get isInitialized => true;

  @override
  int get priority => 0;

  @override
  String get providerId => 'fake';

  @override
  String get sourceIndicator => 'T';

  @override
  Future<Library> buildLibraryCatalog(
    Map<String, Map<String, dynamic>> metadata,
    String rootPath,
  ) async => throw UnimplementedError();

  @override
  Future<List<Link>> getAllLinksForBook(
    String title,
    int categoryId,
    String fileType,
  ) async => const [];

  @override
  Future<Set<String>> getAvailableBookTitles() async => {
    for (final title in _commentators) '$title|1|txt',
  };

  @override
  Future<String?> getBookText(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async => null;

  @override
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async => const [];

  @override
  Future<String> getLinkContent(Link link) async =>
      'קטע ${link.index2} של ${link.path2}. ' * 6;

  @override
  Future<bool> hasBook(String title, int categoryId, String fileType) async =>
      true;

  @override
  Future<void> initialize() async {}

  @override
  Future<Map<String, List<Book>>> loadBooks(
    Map<String, Map<String, dynamic>> metadata,
  ) async => const {};
}

/// רגיעה אחרי גלילה, כמו בין פעולות של משתמש.
const _scrollRest = Duration(milliseconds: 350);

/// הפריט הראשון שתחילתו בתוך התצוגה.
ItemPosition? _firstItemStartingInView(Iterable<ItemPosition> positions) {
  ItemPosition? best;
  for (final position in positions) {
    if (position.itemLeadingEdge < 0 || position.itemLeadingEdge > 1) continue;
    if (best == null || position.itemLeadingEdge < best.itemLeadingEdge) {
      best = position;
    }
  }
  return best;
}

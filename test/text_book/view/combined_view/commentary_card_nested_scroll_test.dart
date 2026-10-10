import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../test_helpers/memory_cache_provider.dart';

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
    await _settle(tester, ScrollPositionReanchor.idleDelay);

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

    await _settle(tester, ScrollPositionReanchor.idleDelay);

    expect(
      tester.state<CommentaryListBaseState>(card),
      same(listState),
      reason: 'כרטיס המפרשים נבנה מחדש',
    );
    expect(innerScrollable(), same(scrollableBefore));
    expect(innerScrollable().position.pixels, pixels);
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
    final first = tab.positionsListener.itemPositions.value.firstWhere(
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
    await _settle(tester, ScrollPositionReanchor.idleDelay);

    tab.scrollController.jumpTo(index: 50);
    await _settle(tester);
    expect(find.byType(CommentaryListBase), findsNothing);
    outerScrollable().position.jumpTo(450);
    await _settle(tester, ScrollPositionReanchor.idleDelay);
    final top = reanchorTargetPosition(
      tab.positionsListener.itemPositions.value,
    )!;
    settings.changeLineHeight(3);
    await _settle(tester);
    final after = tab.positionsListener.itemPositions.value
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
    SettingsState.initial().copyWith(lineHeight: lineHeight),
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
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
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

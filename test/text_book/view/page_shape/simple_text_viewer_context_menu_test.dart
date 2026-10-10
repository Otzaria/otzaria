import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/services/target_line_links_service.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:otzaria/text_book/view/tabbed_commentary_panel.dart';
import 'package:otzaria/widgets/misc/app_context_menu.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../test_helpers/memory_cache_provider.dart';

/// תפריט ההקשר של צורת הדף — הפריטים שהיו חסרים בה מול "מפרשים בצד":
/// תת-תפריט "מפרשים" על הטקסט הראשי, ותתי-התפריטים של קטע היעד בלחיצה
/// ימנית על טור מפרש.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  tearDown(() => TargetLineLinksService.resetInstanceForTesting());

  Future<void> pumpViewer(
    WidgetTester tester, {
    required Widget viewer,
    required TextBookBloc textBookBloc,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final personalNotesBloc = _TestPersonalNotesBloc(
      const PersonalNotesState.initial(),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    addTearDown(() async {
      await personalNotesBloc.close();
      await settingsBloc.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(body: viewer),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openContextMenu(WidgetTester tester, {int lineIndex = 0}) async {
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    final center = tester.getCenter(
      find.byType(AppContextMenuRegion).at(lineIndex),
    );
    await gesture.moveTo(center);
    await gesture.down(center);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  group('תפריט הטקסט הראשי', () {
    testWidgets('כולל תת-תפריט "מפרשים" עם פתיחת החלונית ובחירת מפרשים', (
      tester,
    ) async {
      final bloc = _RecordingTextBookBloc(
        _loadedState(
          availableCommentators: const ['רש"י', 'רמב"ן'],
          commentatorGroups: const [
            CommentatorGroup(
              title: 'ראשונים',
              commentators: ['רש"י', 'רמב"ן'],
            ),
          ],
          activeCommentators: const ['רש"י'],
          linksByLine: _commentaryLinks(const ['רש"י', 'רמב"ן']),
        ),
      );
      addTearDown(bloc.close);
      var openedPane = 0;
      var openedFilter = 0;

      await pumpViewer(
        tester,
        textBookBloc: bloc,
        viewer: SimpleTextViewer(
          content: const ['שורה א'],
          fontSize: 18,
          openBookCallback: (_) {},
          isMainText: true,
          onOpenCommentatorsPane: () => openedPane++,
          onOpenCommentatorsPaneWithFilter: () => openedFilter++,
        ),
      );

      await openContextMenu(tester);
      expect(find.text('מפרשים על פסקה זו'), findsOneWidget);

      await tester.tap(find.text('מפרשים על פסקה זו'));
      await tester.pumpAndSettle();

      expect(find.text('פתח את חלונית המפרשים'), findsOneWidget);
      expect(find.text('בחר מפרשים מרובים'), findsOneWidget);
      expect(find.text('הצג את כל המפרשים על פסקה זו'), findsOneWidget);
      expect(find.text('רמב"ן'), findsOneWidget);

      await tester.tap(find.text('רמב"ן'));
      await tester.pumpAndSettle();

      final update = bloc.received.whereType<UpdateCommentators>().single;
      expect(update.commentators, ['רש"י', 'רמב"ן']);
      expect(
        openedPane,
        1,
        reason: 'הוספת מפרש פותחת את חלונית המפרשים, כמו בתצוגה הרגילה',
      );
      expect(openedFilter, 0);
    });

    testWidgets('בלי callbacks — התפריט קיים אך בלי פריטי פתיחת החלונית', (
      tester,
    ) async {
      final bloc = _RecordingTextBookBloc(
        _loadedState(
          availableCommentators: const ['רש"י'],
          activeCommentators: const ['רש"י'],
          commentatorGroups: const [
            CommentatorGroup(title: 'ראשונים', commentators: ['רש"י']),
          ],
          linksByLine: _commentaryLinks(const ['רש"י']),
        ),
      );
      addTearDown(bloc.close);

      await pumpViewer(
        tester,
        textBookBloc: bloc,
        viewer: SimpleTextViewer(
          content: const ['שורה א'],
          fontSize: 18,
          openBookCallback: (_) {},
          isMainText: true,
        ),
      );

      await openContextMenu(tester);
      await tester.tap(find.text('מפרשים על פסקה זו'));
      await tester.pumpAndSettle();

      expect(find.text('פתח את חלונית המפרשים'), findsNothing);
      expect(find.text('בחר מפרשים מרובים'), findsNothing);
      expect(find.text('הצג את כל המפרשים על פסקה זו'), findsOneWidget);
    });

    testWidgets('לחיצה ארוכה מתחילה טעינת מפרשי הפסקה', (tester) async {
      final bloc = _RecordingTextBookBloc(
        _loadedState(
          availableCommentators: const ['רש"י', 'רמב"ן'],
          activeCommentators: const ['רש"י'],
          commentatorGroups: const [
            CommentatorGroup(
              title: 'ראשונים',
              commentators: ['רש"י', 'רמב"ן'],
            ),
          ],
          linksByLine: _commentaryLinks(const ['רש"י']),
        ),
      );
      addTearDown(bloc.close);
      final repository = bloc.repository as _TestTextBookRepository;

      await pumpViewer(
        tester,
        textBookBloc: bloc,
        viewer: SimpleTextViewer(
          content: const ['שורה א'],
          fontSize: 18,
          openBookCallback: (_) {},
          isMainText: true,
        ),
      );

      expect(repository.requestedRanges, isEmpty);
      await tester.longPress(find.byType(AppContextMenuRegion).first);
      await tester.pumpAndSettle();

      expect(repository.requestedRanges, [(startIndex: 0, endIndex: 0)]);
      await tester.tap(find.text('מפרשים על פסקה זו'));
      await tester.pumpAndSettle();
      expect(find.text('רמב"ן'), findsOneWidget);
    });

    testWidgets('בחירת מפרש מסנכרנת את הקטע לשורה שנלחצה בכפתור הימני', (
      tester,
    ) async {
      // רגרסיה: חלונית המפרשים נגזרת מ-selectedIndex, ולכן בחירה מהתפריט על
      // שורה אחרת חייבת להזיז אותו — אחרת מוצגים המפרשים של השורה הקודמת.
      final bloc = _RecordingTextBookBloc(
        _loadedState(
          availableCommentators: const ['רש"י'],
          commentatorGroups: const [
            CommentatorGroup(title: 'ראשונים', commentators: ['רש"י']),
          ],
          linksByLine: _commentaryLinks(const ['רש"י'], lines: 3),
        ),
      );
      addTearDown(bloc.close);

      await pumpViewer(
        tester,
        textBookBloc: bloc,
        viewer: SimpleTextViewer(
          content: const ['שורה א', 'שורה ב', 'שורה ג'],
          fontSize: 18,
          openBookCallback: (_) {},
          isMainText: true,
          onOpenCommentatorsPane: () {},
        ),
      );

      await openContextMenu(tester, lineIndex: 2);
      await tester.tap(find.text('מפרשים על פסקה זו'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('רש"י'));
      await tester.pumpAndSettle();

      final selected = bloc.received.whereType<UpdateSelectedIndex>().single;
      expect(selected.index, 2);
    });

    testWidgets('"פתח קישורים בחלונית צד" פותח את לשונית הקישורים', (
      tester,
    ) async {
      final bloc = _RecordingTextBookBloc(
        _loadedState(
          linksByLine: {
            1: [
              Link(
                heRef: 'בראשית א א',
                index1: 1,
                path2: 'בראשית',
                index2: 1,
                connectionType: 'reference',
              ),
            ],
          },
        ),
      );
      addTearDown(bloc.close);
      var openedTab = -1;

      await pumpViewer(
        tester,
        textBookBloc: bloc,
        viewer: SimpleTextViewer(
          content: const ['שורה א'],
          fontSize: 18,
          openBookCallback: (_) {},
          isMainText: true,
          onOpenSidebarTab: (index) => openedTab = index,
        ),
      );

      await openContextMenu(tester);
      await tester.tap(find.text('קישורים'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('פתח קישורים בחלונית צד'));
      await tester.pumpAndSettle();

      expect(openedTab, kLinksTabIndex);
    });

    testWidgets('the links pane entry is hidden while the links tab is open', (
      tester,
    ) async {
      final bloc = _RecordingTextBookBloc(
        _loadedState(
          linksByLine: {
            1: [
              Link(
                heRef: 'בראשית א א',
                index1: 1,
                path2: 'בראשית',
                index2: 1,
                connectionType: 'reference',
              ),
            ],
          },
        ),
      );
      addTearDown(bloc.close);

      await pumpViewer(
        tester,
        textBookBloc: bloc,
        viewer: SimpleTextViewer(
          content: const ['שורה א'],
          fontSize: 18,
          openBookCallback: (_) {},
          isMainText: true,
          onOpenSidebarTab: (_) {},
          isLinksTabActive: true,
        ),
      );

      await openContextMenu(tester);
      await tester.tap(find.text('קישורים'));
      await tester.pumpAndSettle();

      expect(find.text('פתח קישורים בחלונית צד'), findsNothing);
    });

    testWidgets('כשלשונית המפרשים פתוחה — פריטי הפתיחה מוסתרים', (
      tester,
    ) async {
      final bloc = _RecordingTextBookBloc(
        _loadedState(
          availableCommentators: const ['רש"י'],
          activeCommentators: const ['רש"י'],
          commentatorGroups: const [
            CommentatorGroup(title: 'ראשונים', commentators: ['רש"י']),
          ],
          linksByLine: _commentaryLinks(const ['רש"י']),
        ),
      );
      addTearDown(bloc.close);

      await pumpViewer(
        tester,
        textBookBloc: bloc,
        viewer: SimpleTextViewer(
          content: const ['שורה א'],
          fontSize: 18,
          openBookCallback: (_) {},
          isMainText: true,
          isCommentatorsTabActive: true,
          onOpenCommentatorsPane: () {},
          onOpenCommentatorsPaneWithFilter: () {},
        ),
      );

      await openContextMenu(tester);
      await tester.tap(find.text('מפרשים על פסקה זו'));
      await tester.pumpAndSettle();

      expect(find.text('פתח את חלונית המפרשים'), findsNothing);
      expect(find.text('בחר מפרשים מרובים'), findsNothing);
      expect(find.text('הצג את כל המפרשים על פסקה זו'), findsOneWidget);
    });
  });

  group('תפריט טור המפרש', () {
    testWidgets('מציג מפרשים וקישורים של שורת המפרש שנלחצה', (tester) async {
      // שאילתת קטע היעד מוחלפת ב-loader מדומה: כך אין תלות ב-DB, ואפשר
      // לוודא שהטווח הנשלח הוא שורת המפרש (index 1) ולא שורת הספר הראשי.
      final requested = <({String title, int start, int end})>[];
      TargetLineLinksService.resetInstanceForTesting(
        loader: (book, start, end) async {
          requested.add((title: book.title, start: start, end: end));
          return [
            Link(
              heRef: 'שפתי חכמים, א',
              index1: 2,
              path2: 'שפתי חכמים',
              index2: 1,
              connectionType: 'commentary',
            ),
            Link(
              heRef: 'בראשית, א, א',
              index1: 2,
              path2: 'בראשית',
              index2: 1,
              connectionType: 'reference',
            ),
          ];
        },
      );

      final bloc = _RecordingTextBookBloc(_loadedState());
      addTearDown(bloc.close);

      await pumpViewer(
        tester,
        textBookBloc: bloc,
        viewer: SimpleTextViewer(
          content: const ['שורת מפרש א', 'שורת מפרש ב'],
          fontSize: 18,
          openBookCallback: (_) {},
          isMainText: false,
          bookTitle: 'רש"י',
          reportBook: TextBook(title: 'רש"י', categoryId: 7),
        ),
      );

      // לחיצה על השורה השנייה — קטע היעד חייב להיות שורה 2 בספר המפרש.
      await openContextMenu(tester, lineIndex: 1);
      await tester.pumpAndSettle();

      expect(find.text('מפרשים'), findsOneWidget);
      expect(find.text('קישורים'), findsOneWidget);
      expect(
        requested,
        hasLength(1),
        reason: 'שאילתה אחת מספיקה לשני תתי-התפריטים',
      );
      expect(requested.single.title, 'רש"י');
      expect(
        requested.single.start,
        1,
        reason: 'קטע היעד הוא השורה בספר המפרש, לא שורת הספר הראשי',
      );
    });

    testWidgets('בלי categoryId אין תתי-תפריטים — השאילתה לא תצליח', (
      tester,
    ) async {
      var loaderCalls = 0;
      TargetLineLinksService.resetInstanceForTesting(
        loader: (book, start, end) async {
          loaderCalls++;
          return const [];
        },
      );
      final bloc = _RecordingTextBookBloc(_loadedState());
      addTearDown(bloc.close);

      await pumpViewer(
        tester,
        textBookBloc: bloc,
        viewer: SimpleTextViewer(
          content: const ['שורת מפרש'],
          fontSize: 18,
          openBookCallback: (_) {},
          isMainText: false,
          bookTitle: 'רש"י',
          reportBook: TextBook(title: 'רש"י'),
        ),
      );

      await openContextMenu(tester);
      expect(find.text('מפרשים על פסקה זו'), findsNothing);
      expect(find.text('קישורים'), findsNothing);
      expect(loaderCalls, 0);
    });

    testWidgets('בלי reportBook אין תתי-תפריטים של קטע היעד', (tester) async {
      final bloc = _RecordingTextBookBloc(_loadedState());
      addTearDown(bloc.close);

      await pumpViewer(
        tester,
        textBookBloc: bloc,
        viewer: SimpleTextViewer(
          content: const ['שורת מפרש'],
          fontSize: 18,
          openBookCallback: (_) {},
          isMainText: false,
          bookTitle: 'רש"י',
        ),
      );

      await openContextMenu(tester);
      expect(find.text('מפרשים על פסקה זו'), findsNothing);
      expect(find.text('קישורים'), findsNothing);
      expect(find.textContaining('הוסף הערה אישית'), findsOneWidget);
    });
  });
}

/// קישורי-מפרש לכל אחת מ-[lines] השורות, כדי שהמפרשים ייחשבו "על הפסקה".
Map<int, List<Link>> _commentaryLinks(
  List<String> commentators, {
  int lines = 1,
}) => {
  for (var line = 1; line <= lines; line++)
    line: [
      for (final title in commentators)
        Link(
          heRef: '',
          index1: line,
          path2: 'מפרשים/$title.txt',
          index2: 1,
          connectionType: 'commentary',
        ),
    ],
};

TextBookLoaded _loadedState({
  List<String> availableCommentators = const [],
  List<String> activeCommentators = const [],
  List<CommentatorGroup> commentatorGroups = const [],
  Map<int, List<Link>> linksByLine = const {},
}) => TextBookLoaded(
  book: TextBook(title: 'ספר בדיקה'),
  showLeftPane: false,
  content: const ['שורה א'],
  fontSize: 18,
  showSplitView: false,
  showPageShapeView: true,
  activeCommentators: activeCommentators,
  commentatorGroups: commentatorGroups,
  availableCommentators: availableCommentators,
  links: const [],
  visibleLinks: const [],
  linksByLine: linksByLine,
  tableOfContents: const [],
  removeNikud: false,
  visibleIndices: const [0],
  selectedIndex: 0,
  pinLeftPane: false,
  searchText: '',
  scrollController: ItemScrollController(),
  positionsListener: ItemPositionsListener.create(),
);

class _RecordingTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _RecordingTextBookBloc(super.initialState)
    : repository = _TestTextBookRepository(
        initialState is TextBookLoaded
            ? initialState.availableCommentators
            : const [],
      ) {
    on<TextBookEvent>((event, emit) => received.add(event));
  }

  final List<TextBookEvent> received = [];

  @override
  final TextBookRepository repository;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestTextBookRepository implements TextBookRepository {
  _TestTextBookRepository(this.commentators);

  final List<String> commentators;
  final List<({int startIndex, int endIndex})> requestedRanges = [];

  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async {
    requestedRanges.add((startIndex: startIndex, endIndex: endIndex));
    return [
      for (final title in commentators)
        Link(
          heRef: '',
          index1: startIndex + 1,
          path2: title,
          index2: 1,
          connectionType: 'commentary',
        ),
    ];
  }

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

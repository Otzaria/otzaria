// גלילת חלונית המפרשים במעבר בין קטעי המקור (issue #846): קטע חדש מוצג
// מתחילתו, אך הרחבת הבחירה או החלפת מפרשים באותו קטע שומרות על המיקום.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../test_helpers/memory_cache_provider.dart';

/// מספר המפרשים בכל שורה. חייב להיות גדול דיו כדי שהרשימה תהיה גלילה,
/// ושקפיצה למעלה תהיה מבחינה מהמיקום הגלול.
const int _commentatorCount = 14;
final List<String> _commentators = [
  for (var i = 0; i < _commentatorCount; i++) 'ספר $i',
];
const int _lineCount = 4;

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

  tearDown(() {
    LibraryProviderManager.instance.resetForTesting();
  });

  group('isCommentarySectionChange - מדיניות האיפוס', () {
    test('שורת עוגן אחרת = מעבר לקטע', () {
      expect(
        isCommentarySectionChange(previous: const [10], current: const [11]),
        isTrue,
      );
    });

    test('אותה שורה בדיוק = אינו מעבר', () {
      expect(
        isCommentarySectionChange(previous: const [10], current: const [10]),
        isFalse,
      );
    });

    test('הרחבת הבחירה מהעוגן קדימה (Ctrl+לחיצה) אינה מעבר', () {
      expect(
        isCommentarySectionChange(
          previous: const [10],
          current: const [10, 15],
        ),
        isFalse,
      );
    });

    test('צמצום הבחירה חזרה לעוגן אינו מעבר', () {
      expect(
        isCommentarySectionChange(
          previous: const [10, 15],
          current: const [10],
        ),
        isFalse,
      );
    });

    test('גדילת חלון הנראוּת בסופו אינה מעבר', () {
      expect(
        isCommentarySectionChange(
          previous: const [5, 6, 7],
          current: const [5, 6, 7, 8],
        ),
        isFalse,
      );
    });

    test('החלון זז קדימה (העוגן יצא) = מעבר', () {
      expect(
        isCommentarySectionChange(
          previous: const [5, 6, 7],
          current: const [6, 7, 8],
        ),
        isTrue,
      );
    });

    test('גלילה אחורה שמכניסה שורה לפני העוגן = מעבר', () {
      expect(
        isCommentarySectionChange(
          previous: const [6, 7],
          current: const [5, 6, 7],
        ),
        isTrue,
      );
    });

    test('קפיצה רחוקה = מעבר', () {
      expect(
        isCommentarySectionChange(
          previous: const [5, 6, 7],
          current: const [90, 91],
        ),
        isTrue,
      );
    });

    test('שתי רשימות ריקות אינן מעבר', () {
      expect(
        isCommentarySectionChange(previous: const [], current: const []),
        isFalse,
      );
    });

    test('מריק ללא-ריק ולהיפך = מעבר', () {
      expect(
        isCommentarySectionChange(previous: const [], current: const [3]),
        isTrue,
      );
      expect(
        isCommentarySectionChange(previous: const [3], current: const []),
        isTrue,
      );
    });
  });

  group('CommentaryListBase - איפוס הגלילה במעבר קטע', () {
    testWidgets('מעבר לפסקה הבאה מציג את המפרשים מתחילתם', (tester) async {
      final bloc = await _pump(tester, _sectionState(0));
      await tester.pumpAndSettle();

      await _scrollDown(tester);
      expect(
        _isAtTop(tester),
        isFalse,
        reason: 'הבדיקה חייבת להתחיל ממצב גלול',
      );

      bloc.emitState(_sectionState(1));
      await tester.pumpAndSettle();

      expect(_isAtTop(tester), isTrue);
    });

    testWidgets('מעבר דרך "טוען מפרשים..." מציג את המפרשים מתחילתם', (
      tester,
    ) async {
      // הקישורים של הקטע החדש עדיין לא נטענו — הרשימה יורדת מהעץ ונבנית
      // מחדש, המסלול שבו שחזור מ-PageStorage היה מחזיר את ההיסט הישן.
      final bloc = await _pump(tester, _sectionState(0));
      await tester.pumpAndSettle();

      await _scrollDown(tester);
      expect(_isAtTop(tester), isFalse);

      bloc.emitState(_loadingSectionState(1));
      await tester.pumpAndSettle();
      expect(find.text('טוען מפרשים...'), findsOneWidget);
      expect(find.byType(ScrollablePositionedList), findsNothing);

      bloc.emitState(_sectionState(1));
      await tester.pumpAndSettle();

      expect(_isAtTop(tester), isTrue);
    });

    testWidgets('חזרה לקטע הקודם מציגה אותו מתחילתו', (tester) async {
      final bloc = await _pump(tester, _sectionState(0));
      await tester.pumpAndSettle();
      await _scrollDown(tester);

      bloc.emitState(_sectionState(1));
      await tester.pumpAndSettle();
      await _scrollDown(tester);
      expect(_isAtTop(tester), isFalse);

      bloc.emitState(_sectionState(0));
      await tester.pumpAndSettle();

      expect(_isAtTop(tester), isTrue);
    });

    testWidgets('שני מעברי קטע רצופים - האיפוס חל על שניהם', (tester) async {
      final bloc = await _pump(tester, _sectionState(0));
      await tester.pumpAndSettle();
      await _scrollDown(tester);

      bloc.emitState(_sectionState(1));
      await tester.pumpAndSettle();
      expect(_isAtTop(tester), isTrue);

      await _scrollDown(tester);
      bloc.emitState(_sectionState(2));
      await tester.pumpAndSettle();

      expect(_isAtTop(tester), isTrue);
    });

    testWidgets('אותו קטע נשלח שוב - הגלילה נשמרת', (tester) async {
      final bloc = await _pump(tester, _sectionState(0));
      await tester.pumpAndSettle();
      await _scrollDown(tester);
      final scrolledOffset = _firstTitleOffset(tester);

      // אותו קטע, מצב חדש (למשל שינוי בהגדרות) — אין לאפס.
      bloc.emitState(_sectionState(0, removeNikud: true));
      await tester.pumpAndSettle();

      expect(_isAtTop(tester), isFalse);
      expect(_firstTitleOffset(tester), scrolledOffset);
    });

    testWidgets('הרחבת הבחירה (Ctrl+לחיצה) אינה מאפסת את הגלילה', (
      tester,
    ) async {
      final bloc = await _pump(tester, _sectionState(0));
      await tester.pumpAndSettle();
      await _scrollDown(tester);
      expect(_isAtTop(tester), isFalse);

      bloc.emitState(_multiSelectionState(anchor: 0, extra: 2));
      await tester.pumpAndSettle();

      expect(_isAtTop(tester), isFalse);
    });

    testWidgets('גדילת חלון הנראוּת בלבד אינה מאפסת את הגלילה', (tester) async {
      final bloc = await _pump(tester, _visibleWindowState(const [0, 1]));
      await tester.pumpAndSettle();
      await _scrollDown(tester);
      expect(_isAtTop(tester), isFalse);

      bloc.emitState(_visibleWindowState(const [0, 1, 2]));
      await tester.pumpAndSettle();

      expect(_isAtTop(tester), isFalse);
    });

    testWidgets('הזזת חלון הנראוּת קדימה מאפסת את הגלילה', (tester) async {
      final bloc = await _pump(tester, _visibleWindowState(const [0, 1]));
      await tester.pumpAndSettle();
      await _scrollDown(tester);
      expect(_isAtTop(tester), isFalse);

      bloc.emitState(_visibleWindowState(const [1, 2]));
      await tester.pumpAndSettle();

      expect(_isAtTop(tester), isTrue);
    });

    testWidgets('הטעינה הראשונה אינה מאפסת - נכבד initialScrollIndex', (
      tester,
    ) async {
      // ה-build הראשון אינו "מעבר קטע": אין קטע קודם להשוות אליו.
      await _pump(tester, _sectionState(0));
      await tester.pumpAndSettle();

      expect(_isAtTop(tester), isTrue);
    });

    testWidgets('החלפת מפרשים באותו קטע שומרת את מיקום הגלילה', (tester) async {
      // התנהגות מכוונת קיימת: _lastScrollIndex משוחזר דרך initialScrollIndex
      // כשרשימת המפרשים משתנה, ואין לאפס אותה יחד עם תיקון מעבר הקטע.
      final bloc = await _pump(tester, _sectionState(0));
      await tester.pumpAndSettle();
      await _scrollDown(tester);
      expect(_isAtTop(tester), isFalse);

      bloc.emitState(
        _sectionState(0, activeCommentators: _commentators.sublist(1)),
      );
      await tester.pumpAndSettle();

      expect(_isAtTop(tester), isFalse);
    });

    testWidgets('שינוי indexes מבחוץ (כרטיסיית המפרשים) מאפס את הגלילה', (
      tester,
    ) async {
      await _pump(tester, _sectionState(0), indexes: const [0]);
      await tester.pumpAndSettle();
      await _scrollDown(tester);
      expect(_isAtTop(tester), isFalse);

      await _pump(tester, _sectionState(0), indexes: const [1]);
      await tester.pumpAndSettle();

      expect(_isAtTop(tester), isTrue);
    });

    testWidgets('הרחבת indexes מבחוץ אינה מאפסת את הגלילה', (tester) async {
      await _pump(tester, _sectionState(0), indexes: const [0]);
      await tester.pumpAndSettle();
      await _scrollDown(tester);
      expect(_isAtTop(tester), isFalse);

      await _pump(tester, _sectionState(0), indexes: const [0, 2]);
      await tester.pumpAndSettle();

      expect(_isAtTop(tester), isFalse);
    });
  });
}

/// ההיסט האנכי של כותרת המפרש הראשון ביחס לראש הרשימה, או null כשאינה בנויה.
double? _firstTitleOffset(WidgetTester tester) {
  final list = find.byType(ScrollablePositionedList);
  if (list.evaluate().isEmpty) return null;
  final first = find.text(_commentators.first);
  if (first.evaluate().isEmpty) return null;
  return tester.getTopLeft(first).dy - tester.getRect(list).top;
}

/// האם הרשימה מוצגת מתחילתה — כותרת המפרש הראשון בראש אזור הגלילה.
bool _isAtTop(WidgetTester tester) {
  final offset = _firstTitleOffset(tester);
  return offset != null && offset.abs() < 40;
}

Future<void> _scrollDown(WidgetTester tester) async {
  await tester.drag(
    find.byType(ScrollablePositionedList),
    const Offset(0, -600),
  );
  await tester.pumpAndSettle();
}

Future<_TestTextBookBloc> _pump(
  WidgetTester tester,
  TextBookLoaded state, {
  List<int>? indexes,
}) async {
  final bloc = _existingBloc ?? _TestTextBookBloc(state);
  if (_existingBloc == null) {
    _existingBloc = bloc;
    addTearDown(() async {
      _existingBloc = null;
      await bloc.close();
    });
  }
  final settingsBloc = _existingSettingsBloc ?? _TestSettingsBloc.initial();
  if (_existingSettingsBloc == null) {
    _existingSettingsBloc = settingsBloc;
    addTearDown(() async {
      _existingSettingsBloc = null;
      await settingsBloc.close();
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 20));
    });
  }

  await tester.pumpWidget(
    MaterialApp(
      // האפליקציה כולה RTL (locale he_IL); בלי זה בדיקות מיקום נמדדות הפוך.
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: bloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: CommentaryListBase(
              openBookCallback: _noopOpenBook,
              fontSize: 18,
              showSearch: true,
              shrinkWrap: false,
              indexes: indexes,
              onSelectedCommentatorsOverrideChanged: (_) {},
            ),
          ),
        ),
      ),
    ),
  );

  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return bloc;
}

/// ה-bloc משותף בין קריאות `_pump` באותה בדיקה, כדי שהחלפת `indexes` תשמור
/// על אותו State של הווידג'ט (בדיוק כמו rebuild מההורה באפליקציה).
_TestTextBookBloc? _existingBloc;
_TestSettingsBloc? _existingSettingsBloc;

void _noopOpenBook(_) {}

Link _link({required String title, required int lineIndex}) => Link(
  heRef: 'שורה ${lineIndex + 1}',
  index1: lineIndex + 1,
  path2: '$title.txt',
  index2: lineIndex + 1,
  connectionType: LinkTypes.commentary,
  targetCategoryId: 1,
  targetFileType: 'txt',
);

List<Link> _allLinks() => [
  for (var line = 0; line < _lineCount; line++)
    for (final title in _commentators) _link(title: title, lineIndex: line),
];

Map<int, List<Link>> _linksByLine() => {
  for (var line = 0; line < _lineCount; line++)
    line + 1: [
      for (final title in _commentators) _link(title: title, lineIndex: line),
    ],
};

TextBookLoaded _state({
  required List<int> visibleIndices,
  required Set<int> selectedIndices,
  int? selectedIndex,
  List<String>? activeCommentators,
  Map<int, List<Link>>? linksByLine,
  bool linksLoading = false,
  bool removeNikud = false,
}) {
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: const ['שורה א', 'שורה ב', 'שורה ג', 'שורה ד'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: activeCommentators ?? _commentators,
    commentatorGroups: [
      CommentatorGroup(title: 'ראשונים', commentators: _commentators),
    ],
    availableCommentators: _commentators,
    links: _allLinks(),
    visibleLinks: const [],
    linksByLine: linksByLine ?? _linksByLine(),
    linksLoading: linksLoading,
    tableOfContents: const [],
    removeNikud: removeNikud,
    visibleIndices: visibleIndices,
    selectedIndex: selectedIndex,
    selectedIndices: selectedIndices,
    pinLeftPane: false,
    searchText: '',
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );
}

/// קטע נבחר בודד בשורה [lineIndex].
TextBookLoaded _sectionState(
  int lineIndex, {
  List<String>? activeCommentators,
  bool removeNikud = false,
}) => _state(
  visibleIndices: [lineIndex],
  selectedIndices: {lineIndex},
  selectedIndex: lineIndex,
  activeCommentators: activeCommentators,
  removeNikud: removeNikud,
);

/// קטע נבחר שקישוריו עדיין לא נטענו — מציג "טוען מפרשים...".
TextBookLoaded _loadingSectionState(int lineIndex) => _state(
  visibleIndices: [lineIndex],
  selectedIndices: {lineIndex},
  selectedIndex: lineIndex,
  linksByLine: const {},
  linksLoading: true,
);

/// ריבוי-בחירה: [anchor] נבחר ראשון ואחריו [extra] (Ctrl+לחיצה).
TextBookLoaded _multiSelectionState({
  required int anchor,
  required int extra,
}) => _state(
  visibleIndices: [anchor],
  selectedIndices: {anchor, extra},
  selectedIndex: extra,
);

/// אין בחירה — המפרשים נגזרים מחלון הנראוּת בלבד.
TextBookLoaded _visibleWindowState(List<int> visibleIndices) => _state(
  visibleIndices: visibleIndices,
  selectedIndices: const {},
);

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  /// דוחף מצב חדש לווידג'ט, כדי לדמות מעבר לקטע אחר.
  void emitState(TextBookState state) => emit(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  factory _TestSettingsBloc.initial() =>
      _TestSettingsBloc(SettingsState.initial());

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
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<List<Link>> getAllLinksForBook(
    String title,
    int categoryId,
    String fileType,
  ) async {
    return const [];
  }

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
  }) async {
    return null;
  }

  @override
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async {
    return const [];
  }

  @override
  Future<String> getLinkContent(Link link) async =>
      'תוכן המפרש לשורה ${link.index1}. ' * 6;

  @override
  Future<bool> hasBook(String title, int categoryId, String fileType) async =>
      true;

  @override
  Future<void> initialize() async {}

  @override
  Future<Map<String, List<Book>>> loadBooks(
    Map<String, Map<String, dynamic>> metadata,
  ) async {
    return const {};
  }
}

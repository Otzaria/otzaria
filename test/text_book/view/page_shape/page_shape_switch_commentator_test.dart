// "החלף מפרש" בתפריט ההקשר של טור מפרש בצורת הדף מחליף את המפרש שבטור גם
// כשהטורים מוצגים מברירות המחדל, בלי הגדרה שמורה לספר (issue #3251).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/page_shape/page_shape_screen.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria/widgets/misc/app_context_menu.dart';

import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/stub_personal_notes_bloc.dart';
import '../../../test_helpers/stub_settings_bloc.dart';
import '../../../test_helpers/stub_text_book_bloc.dart';

const _bookTitle = 'ספר בדיקה';
const _content = ['שורה א', 'שורה ב'];
const _columns = ['left', 'right', 'bottom', 'bottomRight'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    LibraryProviderManager.instance.resetForTesting();
  });

  tearDown(LibraryProviderManager.instance.resetForTesting);

  Finder commentaryViewer() => find.byWidgetPredicate(
    (widget) => widget is SimpleTextViewer && !widget.isMainText,
  );

  String? shownCommentator(WidgetTester tester) => tester
      .widgetList<SimpleTextViewer>(commentaryViewer())
      .singleOrNull
      ?.bookTitle;

  /// לחיצה ימנית על טור המפרש ובחירת [to] בתפריט "החלף מפרש".
  Future<void> switchTo(WidgetTester tester, String to) async {
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await gesture.addPointer(location: Offset.zero);
    final line = tester.getCenter(
      find
          .descendant(
            of: commentaryViewer(),
            matching: find.byType(AppContextMenuRegion),
          )
          .first,
    );
    await gesture.moveTo(line);
    await gesture.down(line);
    await tester.pump();
    await gesture.up();
    await gesture.removePointer();
    await tester.pumpAndSettle();

    await tester.tap(find.text('החלף מפרש'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(to).last);
    await _pumpUntil(tester, () => shownCommentator(tester) == to);
  }

  /// צורת הדף של [book] עם המפרשים [names], כשאין הגדרה שמורה וברירות המחדל
  /// מציגות את הראשון בטור [column] בלבד (שאר הטורים מוסתרים). כל בדיקה
  /// משתמשת בשמות משלה: טקסט המפרש נשמר במטמון סטטי בין הבדיקות.
  Future<void> pumpPageShape(
    WidgetTester tester,
    TextBook book,
    List<String> names, {
    String column = 'left',
    Map<String, String?>? defaults,
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final provider = _FakeLibraryProvider(names);
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {
        for (final title in names)
          BookCompositeKey.create(
            title: title,
            categoryId: 1,
            fileType: 'txt',
          ): provider,
      },
      providers: [provider],
    );

    final bloc = StubTextBookBloc(_state(book, names));
    final settings = StubSettingsBloc(SettingsState.initial());
    final notes = StubPersonalNotesBloc(const PersonalNotesState.initial());
    final tab = TextBookTab(book: book, index: 0, blocOverride: bloc);
    final tabs = _TestTabsBloc(TabsState(tabs: [tab], currentTabIndex: 0));
    final navigation = _TestNavigationBloc(
      const NavigationState(currentScreen: Screen.reading),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await bloc.close();
      await settings.close();
      await notes.close();
      await tabs.close();
      await navigation.close();
      tab.dispose();
    });

    // מסך חדש, כמו בפתיחה מחדש של צורת הדף.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: bloc),
          BlocProvider<SettingsBloc>.value(value: settings),
          BlocProvider<PersonalNotesBloc>.value(value: notes),
          BlocProvider<TabsBloc>.value(value: tabs),
          BlocProvider<NavigationBloc>.value(value: navigation),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: PageShapeScreen(
              openBookCallback: (_) {},
              tab: tab,
              defaultsLoader: (book, available) async => (
                commentators:
                    defaults ??
                    <String, String?>{
                      for (final c in _columns)
                        c: c == column ? names.first : null,
                    },
                visibility: <String, bool>{
                  for (final c in _columns)
                    c: defaults == null ? c == column : defaults[c] != null,
                },
              ),
            ),
          ),
        ),
      ),
    );
    await _pumpUntil(tester, () => commentaryViewer().evaluate().isNotEmpty);
  }

  // כל התרחישים בבדיקה אחת: אתחול המסד שמתחיל בבדיקת צורת הדף נשאר תלוי
  // באזור הזמן שלה, ובדיקה נוספת בקובץ הייתה ממתינה לו לנצח.
  testWidgets('"החלף מפרש" בטור צורת הדף מחליף ושומר גם מברירות המחדל '
      '(issue #3251)', (tester) async {
    for (final column in _columns) {
      final title = 'ספר $column';
      final names = ['$column א', '$column ב', '$column ג'];
      await pumpPageShape(
        tester,
        TextBook(title: title),
        names,
        column: column,
      );
      expect(shownCommentator(tester), names[0], reason: column);
      expect(
        PageShapeSettingsManager.loadConfiguration(title),
        isNull,
        reason: '$column: הטורים מוצגים מברירות המחדל',
      );

      await switchTo(tester, names[1]);

      expect(shownCommentator(tester), names[1], reason: column);
      expect(
        PageShapeSettingsManager.loadConfiguration(title)?[column],
        names[1],
        reason: column,
      );
      final visibility = PageShapeSettingsManager.getColumnVisibility(title);
      expect(
        {for (final c in _columns) c: visibility[c]},
        {for (final c in _columns) c: c == column},
        reason: '$column: הטורים שברירת המחדל מסתירה נשארים מוסתרים',
      );
    }

    // מהגדרה שמורה לספר — ההחלפה עובדת, נשמרת ונשארת בפתיחה מחדש.
    const names = ['מפרש א', 'מפרש ב', 'מפרש ג'];
    final book = TextBook(title: _bookTitle);
    await pumpPageShape(tester, book, names);
    await switchTo(tester, names[1]);
    await switchTo(tester, names[2]);
    expect(shownCommentator(tester), names[2]);
    expect(
      PageShapeSettingsManager.loadConfiguration(_bookTitle)?['left'],
      names[2],
    );
    await pumpPageShape(tester, book, names);
    expect(shownCommentator(tester), names[2]);

    // ספר בקטגוריה בלי הגדרה משלו: נשמר לקטגוריה, כמו הסתרת טור.
    const heCategories = 'אוצריא, תלמוד, תלמוד בבלי, סדר מועד';
    const categoryTitle = 'ספר בקטגוריה';
    final categoryBook = TextBook(
      title: categoryTitle,
      heCategories: heCategories,
    );
    await pumpPageShape(tester, categoryBook, names);
    await switchTo(tester, names[1]);
    expect(PageShapeSettingsManager.loadConfiguration(categoryTitle), isNull);
    expect(
      PageShapeSettingsManager.getActiveCategory(heCategories),
      'תלמוד בבלי',
    );
    await pumpPageShape(tester, categoryBook, names);
    expect(shownCommentator(tester), names[1]);

    const duplicateNames = ['מפרש כפול', 'מפרש חלופי'];
    const duplicateBook = 'ספר מפרשים כפולים';
    await pumpPageShape(
      tester,
      TextBook(title: duplicateBook),
      duplicateNames,
      defaults: {'left': duplicateNames[0], 'bottom': duplicateNames[0]},
    );
    await _pumpUntil(tester, () => commentaryViewer().evaluate().length == 2);
    final bottom = tester.widgetList<SimpleTextViewer>(commentaryViewer()).last;
    bottom.onSwitchCommentator!(duplicateNames[1]);
    await _pumpUntil(
      tester,
      () => PageShapeSettingsManager.loadConfiguration(duplicateBook) != null,
    );
    final saved = PageShapeSettingsManager.loadConfiguration(duplicateBook)!;
    expect(saved['left'], duplicateNames[0]);
    expect(saved['bottom'], duplicateNames[1]);
  });
}

/// טעינת טור מפרש עוברת דרך Isolate.run, ולכן ממתינים בזמן אמת עד לתנאי.
Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Link _link(String title, int line) => Link(
  heRef: '$title ${line + 1}',
  index1: line + 1,
  path2: '$title.txt',
  index2: line + 1,
  connectionType: LinkTypes.commentary,
  targetCategoryId: 1,
  targetFileType: 'txt',
);

TextBookLoaded _state(TextBook book, List<String> names) => TextBookLoaded(
  book: book,
  showLeftPane: false,
  content: _content,
  fontSize: 18,
  showSplitView: false,
  showPageShapeView: true,
  activeCommentators: names,
  commentatorGroups: [CommentatorGroup(title: 'ראשונים', commentators: names)],
  availableCommentators: names,
  links: [
    for (var line = 0; line < _content.length; line++)
      for (final title in names) _link(title, line),
  ],
  visibleLinks: const [],
  linksByLine: {
    for (var line = 0; line < _content.length; line++)
      line + 1: [for (final title in names) _link(title, line)],
  },
  tableOfContents: const [],
  visibleIndices: const [0],
  selectedIndex: 0,
  pinLeftPane: false,
  searchText: '',
);

class _TestTabsBloc extends Bloc<TabsEvent, TabsState> implements TabsBloc {
  _TestTabsBloc(super.initialState) {
    on<TabsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestNavigationBloc extends Bloc<NavigationEvent, NavigationState>
    implements NavigationBloc {
  _TestNavigationBloc(super.initialState) {
    on<NavigationEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLibraryProvider implements LibraryProvider {
  _FakeLibraryProvider(this.titles);

  final List<String> titles;

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
    for (final title in titles) '$title|1|txt',
  };

  @override
  Future<String?> getBookText(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async => '$title שורה 1\n$title שורה 2';

  @override
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async => const [];

  @override
  Future<String> getLinkContent(Link link) async => '';

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

// PageDown/PageUp גוללים מסך באזור הקריאה ובחלונית המפרשים (issue #3272).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/widgets/misc/progressive_scrolling.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

import '../../test_helpers/memory_cache_provider.dart';
import '../../test_helpers/stub_settings_bloc.dart';

final List<String> _lines = [
  for (var line = 0; line < 120; line++)
    List.filled(25, 'מילה בשורה $line').join(' '),
];

final List<String> _commentators = [
  for (var i = 0; i < 20; i++) 'מפרש ${i + 1}',
];

final _desktop = TargetPlatformVariant(const {
  TargetPlatform.windows,
  TargetPlatform.macOS,
  TargetPlatform.linux,
});

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

  tearDown(LibraryProviderManager.instance.resetForTesting);

  /// לוחץ על [key] ומחזיר בכמה פיקסלים זזה הרשימה.
  Future<double> press(
    WidgetTester tester,
    ScrollPosition position,
    LogicalKeyboardKey key,
  ) async {
    final before = position.pixels;
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
    return position.pixels - before;
  }

  testWidgets(
    'אזור הקריאה: PageDown גולל מסך קדימה ו-PageUp חוזר (issue #3272)',
    (tester) async {
      final tab = await _mountReader(tester);
      final position = tab.lines.itemController.scrollController!.position;
      final page = position.viewportDimension * 0.8;

      expect(
        await press(tester, position, LogicalKeyboardKey.pageDown),
        closeTo(page, 1),
      );
      expect(
        await press(tester, position, LogicalKeyboardKey.pageDown),
        closeTo(page, 1),
      );
      expect(
        await press(tester, position, LogicalKeyboardKey.pageUp),
        closeTo(-page, 1),
      );

      // גם אחרי לחיצה בטקסט, כשהפוקוס עבר דרך אזור הבחירה.
      await tester.tap(find.textContaining('מילה בשורה 2 ').first);
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      expect(
        await press(tester, position, LogicalKeyboardKey.pageDown),
        closeTo(page, 1),
      );
    },
    variant: _desktop,
  );

  testWidgets(
    'חלונית המפרשים: PageDown גולל מסך קדימה ו-PageUp חוזר (issue #3272)',
    (tester) async {
      tester.view.physicalSize = const Size(500, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _mountCommentaries(tester);
      tester
          .widget<ProgressiveScroll>(find.byType(ProgressiveScroll))
          .focusNode!
          .requestFocus();
      await tester.pumpAndSettle();
      final position = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(ScrollablePositionedList),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      final page = position.viewportDimension * 0.8;

      expect(
        await press(tester, position, LogicalKeyboardKey.pageDown),
        closeTo(page, 1),
      );
      expect(
        await press(tester, position, LogicalKeyboardKey.pageUp),
        closeTo(-page, 1),
      );
    },
    variant: _desktop,
  );
}

Future<TextBookTab> _mountReader(WidgetTester tester) async {
  final initial = TextBookLoaded(
    book: TextBook(title: 'ספר דפדוף'),
    showLeftPane: false,
    content: _lines,
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    linksByLine: const {},
    tableOfContents: const [],
    visibleIndices: const [0],
    pinLeftPane: false,
    searchText: '',
  );
  final bloc = _TestTextBookBloc(initial);
  final notes = _TestPersonalNotesBloc(const PersonalNotesState.initial());
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
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  return tab;
}

Future<void> _mountCommentaries(WidgetTester tester) async {
  final links = [
    for (final title in _commentators)
      Link(
        heRef: 'שורה 1',
        index1: 1,
        path2: '$title.txt',
        index2: 1,
        connectionType: LinkTypes.commentary,
        targetCategoryId: 1,
        targetFileType: 'txt',
      ),
  ];
  final bloc = _TestTextBookBloc(
    TextBookLoaded(
      book: TextBook(title: 'ספר בדיקה'),
      showLeftPane: false,
      content: const ['שורה א'],
      fontSize: 18,
      showSplitView: false,
      activeCommentators: _commentators,
      commentatorGroups: [
        CommentatorGroup(title: 'ראשונים', commentators: _commentators),
      ],
      availableCommentators: _commentators,
      links: links,
      visibleLinks: const [],
      linksByLine: {1: links},
      tableOfContents: const [],
      removeNikud: false,
      visibleIndices: const [0],
      selectedIndex: 0,
      selectedIndices: const {0},
      pinLeftPane: false,
      searchText: '',
    ),
  );
  final settings = StubSettingsBloc(SettingsState.initial());
  addTearDown(bloc.close);
  addTearDown(settings.close);
  await tester.pumpWidget(
    MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: bloc),
          BlocProvider<SettingsBloc>.value(value: settings),
        ],
        child: Scaffold(
          body: CommentaryListBase(
            openBookCallback: (_) {},
            fontSize: 18,
            showSearch: false,
            shrinkWrap: false,
            indexes: const [0],
            onSelectedCommentatorsOverrideChanged: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
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
      List.filled(60, 'מילה בפירוש').join(' ');

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

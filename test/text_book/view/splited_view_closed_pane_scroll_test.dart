// חלונית המפרשים שנסגרה נשארת בעץ: גלילה בספר בזמן שהיא סגורה אינה טוענת
// ובונה את מפרשי הקטע החדש, ופתיחתה מציגה את מפרשי הקטע הנוכחי.
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
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/text_book/view/splited_view/splited_view_screen.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/tour/bloc/tour_state.dart';
import 'package:otzaria/tour/models/live_tip.dart';

import '../../test_helpers/memory_cache_provider.dart';
import '../../test_helpers/stub_personal_notes_bloc.dart';
import '../../test_helpers/stub_settings_bloc.dart';
import '../../test_helpers/stub_text_book_bloc.dart';

const _commentators = ['מפרש א', 'מפרש ב', 'מפרש ג'];
const _content = ['שורה א', 'שורה ב', 'שורה ג', 'שורה ד'];
final _book = TextBook(title: 'ספר בדיקה');
final _loadedLines = <int>[];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    _loadedLines.clear();
    final provider = _FakeLibraryProvider();
    LibraryProviderManager.instance.resetForTesting();
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {
        for (final title in _commentators)
          BookCompositeKey.create(
            title: title,
            categoryId: 1,
            fileType: 'txt',
          ): provider,
      },
      providers: [provider],
    );
  });

  tearDown(LibraryProviderManager.instance.resetForTesting);

  testWidgets('גלילה כשהחלונית סגורה אינה טוענת מפרשים, ופתיחתה מציגה '
      'את מפרשי הקטע הנוכחי', (tester) async {
    final (bloc, tab) = await _pumpScreen(tester);

    tab.toggleCommentatorsPaneNotifier.value++;
    await _settle(tester);
    expect(_loadedLines, contains(1), reason: 'החלונית הפתוחה טוענת מפרשים');

    tab.toggleCommentatorsPaneNotifier.value++;
    await _settle(tester);
    _loadedLines.clear();

    bloc.emitState(_state(2));
    await _settle(tester);
    expect(_loadedLines, isEmpty, reason: 'החלונית סגורה');

    tab.toggleCommentatorsPaneNotifier.value++;
    await _settle(tester);
    expect(_loadedLines, contains(3));
    expect(
      find.textContaining('תוכן לשורה 3', findRichText: true),
      findsWidgets,
    );
    expect(
      find.textContaining('תוכן לשורה 1', findRichText: true),
      findsNothing,
    );
  });

  testWidgets('מעבר קטע כשהחלונית סגורה אינו מתזמן קפיצה ברשימה הישנה', (
    tester,
  ) async {
    final (bloc, tab) = await _pumpScreen(tester);
    final pane = find.descendant(
      of: find.byType(CommentaryListBase, skipOffstage: false),
      matching: find.byWidgetPredicate((_) => true, skipOffstage: false),
      skipOffstage: false,
    );
    Iterable<RenderObject> paneRenderObjects() =>
        pane.evaluate().map((e) => e.renderObject).nonNulls;
    bool hasList() => paneRenderObjects().any(
      (r) => r.runtimeType.toString() == 'RenderSuperSliverList',
    );

    tab.toggleCommentatorsPaneNotifier.value++;
    for (var i = 0; i < 50 && !hasList(); i++) {
      await _settle(tester);
    }
    expect(hasList(), isTrue);
    tab.toggleCommentatorsPaneNotifier.value++;
    await _settle(tester);

    // קפיצה ברשימה מסמנת אותה לפריסה מחדש בפריים שאחרי מעבר הקטע.
    var jumps = 0;
    for (var i = 1; i <= 6; i++) {
      bloc.emitState(_state(i % _content.length));
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump();
        if (paneRenderObjects().any((r) => r.debugNeedsLayout)) jumps++;
      }
      await _settle(tester);
    }
    expect(jumps, 0);

    tab.toggleCommentatorsPaneNotifier.value++;
    final current = find.textContaining(
      'תוכן לשורה ${6 % _content.length + 1}',
      findRichText: true,
    );
    for (var i = 0; i < 50 && current.evaluate().isEmpty; i++) {
      await _settle(tester);
    }
    expect(current, findsWidgets);
  });
}

Future<(EmittingStubTextBookBloc, TextBookTab)> _pumpScreen(
  WidgetTester tester,
) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final bloc = EmittingStubTextBookBloc(_state(0));
  final settings = StubSettingsBloc(SettingsState.initial());
  final notes = StubPersonalNotesBloc(const PersonalNotesState.initial());
  final tab = TextBookTab(book: _book, index: 0, blocOverride: bloc);
  final tabs = _TestTabsBloc(TabsState(tabs: [tab], currentTabIndex: 0));
  final tour = _TestTourCubit();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await bloc.close();
    await settings.close();
    await notes.close();
    await tabs.close();
    await tour.close();
    tab.dispose();
  });

  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<TextBookBloc>.value(value: bloc),
        BlocProvider<SettingsBloc>.value(value: settings),
        BlocProvider<PersonalNotesBloc>.value(value: notes),
        BlocProvider<TabsBloc>.value(value: tabs),
        BlocProvider<TourCubit>.value(value: tour),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SplitedViewScreen(
            content: _content,
            openBookCallback: (_) {},
            searchTextController: TextEditingValue.empty,
            openLeftPaneTab: (_, {searchText}) {},
            tab: tab,
            showSplitView: true,
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  return (bloc, tab);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
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

final _links = [
  for (var line = 0; line < _content.length; line++)
    for (final title in _commentators) _link(title, line),
];

final _linksByLine = {
  for (var line = 0; line < _content.length; line++)
    line + 1: [for (final title in _commentators) _link(title, line)],
};

TextBookLoaded _state(int line) => TextBookLoaded(
  book: _book,
  showLeftPane: false,
  content: _content,
  fontSize: 18,
  showSplitView: true,
  activeCommentators: _commentators,
  commentatorGroups: [
    CommentatorGroup(title: 'ראשונים', commentators: _commentators),
  ],
  availableCommentators: _commentators,
  links: _links,
  visibleLinks: const [],
  linksByLine: _linksByLine,
  tableOfContents: const [],
  visibleIndices: [line],
  selectedIndices: const {},
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

class _TestTourCubit extends Cubit<TourState> implements TourCubit {
  _TestTourCubit() : super(const TourState.inactive());

  @override
  Future<void> recordInteraction(TourInteraction interaction) async {}

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
  Future<String> getLinkContent(Link link) async {
    _loadedLines.add(link.index1);
    return 'תוכן לשורה ${link.index1}';
  }

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

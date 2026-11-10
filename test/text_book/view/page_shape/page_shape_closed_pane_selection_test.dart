// חלונית הצד של צורת הדף שנסגרה נשארת בעץ: בחירת שורה בזמן שהיא סגורה אינה
// טוענת ובונה את מפרשי השורה, ופתיחתה מציגה את מפרשי השורה הנוכחית.
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
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/page_shape/page_shape_screen.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/tour/bloc/tour_state.dart';
import 'package:otzaria/tour/models/live_tip.dart';

import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/stub_settings_bloc.dart';

const _bookTitle = 'ספר בדיקה';
const _commentators = ['מפרש א', 'מפרש ב', 'מפרש ג'];
const _content = ['שורה א', 'שורה ב', 'שורה ג', 'שורה ד'];
final _book = TextBook(title: _bookTitle);
final _loadedLines = <int>[];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    // בלי טורי מפרשים: נבדקת רק חלונית הצד.
    await Settings.setValue<String>(
      'page_shape_book_$_bookTitle',
      'left|null||right|null||bottom|null||bottomRight|null',
    );
    await Settings.setValue<bool>('page_shape_global_visibility_left', false);
    await Settings.setValue<bool>('page_shape_global_visibility_right', false);
    await Settings.setValue<bool>('page_shape_global_visibility_bottom', false);
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

  testWidgets('בחירת שורה כשחלונית הצד סגורה אינה טוענת מפרשים, ופתיחתה '
      'מציגה את מפרשי השורה הנוכחית', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final bloc = _TestTextBookBloc(_state(0));
    final settings = StubSettingsBloc(SettingsState.initial());
    final notes = _TestPersonalNotesBloc(const PersonalNotesState.initial());
    final tab = TextBookTab(book: _book, index: 0, blocOverride: bloc);
    final tabs = _TestTabsBloc(TabsState(tabs: [tab], currentTabIndex: 0));
    final navigation = _TestNavigationBloc(
      const NavigationState(currentScreen: Screen.reading),
    );
    final tour = _TestTourCubit();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await bloc.close();
      await settings.close();
      await notes.close();
      await tabs.close();
      await navigation.close();
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
          BlocProvider<NavigationBloc>.value(value: navigation),
          BlocProvider<TourCubit>.value(value: tour),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: PageShapeScreen(openBookCallback: (_) {}, tab: tab),
          ),
        ),
      ),
    );
    await _settle(tester);

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
  showSplitView: false,
  showPageShapeView: true,
  activeCommentators: _commentators,
  commentatorGroups: [
    CommentatorGroup(title: 'ראשונים', commentators: _commentators),
  ],
  availableCommentators: _commentators,
  links: _links,
  visibleLinks: const [],
  linksByLine: _linksByLine,
  tableOfContents: const [],
  visibleIndices: const [0],
  selectedIndex: line,
  selectedIndices: {line},
  pinLeftPane: false,
  searchText: '',
);

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  void emitState(TextBookState state) => emit(state);

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

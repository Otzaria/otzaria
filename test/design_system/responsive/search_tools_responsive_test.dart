// Responsive: חיפוש, תוצאות, חיפוש סמנטי וכלי העזר (מילונים, ביוגרפיות, גימטריה,
// מדות ושיעורים, משגר הכלים). לכל מסך: רוחב צר, גובה נמוך, הגדלת טקסט, צפיפות
// מצומצמת וכהה; ובכל אחד מצבי הקצה (טקסט ארוך, ריק, שגיאה, מאות תוצאות).
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/plugins/services/plugin_search_dialog_registry.dart';
import 'package:otzaria/search/active_lexical_searches.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/models/external_search_status.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/search/view/search_history_menu.dart';
import 'package:otzaria/search/view/search_navigation_tree.dart';
import 'package:otzaria/search/view/tantivy_full_text_search.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/models/semantic_result_item.dart';
import 'package:otzaria/semantic_search/repository/semantic_search_repository.dart';
import 'package:otzaria/semantic_search/view/semantic_search_results_screen.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/semantic_search_tab.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SearchResult, SemanticResultSource, TextStatus;

import '../../semantic_search/semantic_test_support.dart'
    show FakeBackend, FakeConsentStore, FakeSettingsStore;
import '../../semantic_search/semantic_ui_test_support.dart';
import '../../support/search_engine_test_init.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tools/acronyms_dictionary/acronyms_dictionary_screen.dart';
import 'package:otzaria/tools/acronyms_dictionary/widgets/acronym_result_card.dart';
import 'package:otzaria/tools/aramaic_dictionary/aramaic_dictionary_screen.dart';
import 'package:otzaria/tools/aramaic_dictionary/widgets/aramaic_result_card.dart';
import 'package:otzaria/tools/biographies/biographies_screen.dart';
import 'package:otzaria/tools/biographies/data/biographies_codec.dart';
import 'package:otzaria/tools/biographies/models/biographies_bundle.dart';
import 'package:otzaria/tools/biographies/repository/biographies_repository.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/tools/gematria/gematria_search.dart' as gematria;
import 'package:otzaria/tools/gematria/gematria_search_screen.dart';
import 'package:otzaria/tools/gematria/models/gematria_search_result.dart';
import 'package:otzaria/tools/gematria/widgets/gematria_result_card.dart';
import 'package:otzaria/tools/measurement_converter/measurement_converter_screen.dart';
import 'package:otzaria/tools/view/tools_launcher_panel.dart';
import 'package:otzaria/widgets/layout/context_overlay_panel.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';

import '../../test_helpers/memory_cache_provider.dart';
import '../../test_helpers/stub_settings_bloc.dart';
import '../../tools/biographies_codec_test.dart' show encodeBundle;
import 'responsive_harness.dart';

// ---------------------------------------------------------------------------
// מטריצות: המטריצה הרגילה של השכבה, והגדלות טקסט 1.3/1.5/2.0 ב-320/600 (שלב 1,
// משימה 13), צפיפות מצומצמת וכהה.
// ---------------------------------------------------------------------------

const List<ResponsiveViewport> _textAndDensity = [
  ResponsiveViewport(320, 640, textScale: 1.3, touch: true),
  ResponsiveViewport(320, 640, textScale: 1.5, touch: true),
  ResponsiveViewport(320, 640, textScale: 2.0, touch: true),
  ResponsiveViewport(600, 800, textScale: 1.5),
  ResponsiveViewport(600, 800, textScale: 2.0),
  ResponsiveViewport(360, 640, compact: true, touch: true),
  ResponsiveViewport(
    390,
    844,
    brightness: Brightness.dark,
    textScale: 1.3,
    touch: true,
  ),
];

List<ResponsiveViewport> get _matrix => [
  ...viewportsFor(activeTier),
  ..._textAndDensity,
];

// ---------------------------------------------------------------------------
// טקסטים חריגים.
// ---------------------------------------------------------------------------

const _longBookTitle =
    'שו"ת אגרות משה על ארבעה חלקי שולחן ערוך אורח חיים יורה דעה אבן העזר '
    'וחושן משפט עם הערות וביאורים מהדורה מוערת ומתוקנת (Volume Two, Revised)';
const _mixed =
    'ברכות דף ב ע"א — Berakhot 2a: "מאימתי קורין" (when do we recite) כ-C:\\Seforim\\ברכות.pdf';

// ---------------------------------------------------------------------------
// כלים: משגר הכלים.
// ---------------------------------------------------------------------------

class _PluginsBloc extends Bloc<PluginSystemEvent, PluginSystemState>
    implements PluginSystemBloc {
  _PluginsBloc(super.initialState) {
    on<PluginSystemEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

InstalledPlugin _plugin(String id, String name) => InstalledPlugin(
  pluginId: id,
  name: name,
  version: '1.0.0',
  installPath: '/plugins/$id',
  entrypointPath: 'index.html',
  enabled: true,
  pinned: false,
  pinnedToNavRail: false,
  showInTools: true,
  networkAccessGranted: false,
  sourceType: 'packaged',
  manifest: PluginManifest(
    schemaVersion: 1,
    id: id,
    name: name,
    version: '1.0.0',
    description: 'תיאור התוסף',
    author: 'tester',
    homepage: '',
    entrypoint: 'index.html',
    minAppVersion: '1.0.0',
    sdkVersion: '1.x',
    permissions: const [],
    networkEnabled: false,
    networkAllowlist: const [],
    toolTabTitle: name,
    toolTabOrder: 900,
    defaultPinned: false,
    publishedDataTypes: const [],
  ),
  installedAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

class _OpenLauncher extends StatelessWidget {
  const _OpenLauncher();

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      ContextOverlayPanel(
        isOpen: true,
        onClose: () {},
        alignment: AlignmentDirectional.centerStart,
        child: ToolsLauncherPanel(
          showDevTools: false,
          onClose: () {},
          onToolSelected: (_) {},
        ),
      ),
    ],
  );
}

Widget Function(Widget) _launcherApp(List<InstalledPlugin> plugins) =>
    (app) => MultiBlocProvider(
      providers: [
        BlocProvider<SettingsBloc>(
          create: (_) => StubSettingsBloc(SettingsState.initial()),
        ),
        BlocProvider<PluginSystemBloc>(
          create: (_) => _PluginsBloc(PluginSystemLoaded(plugins)),
        ),
        BlocProvider<TabsBloc>(
          create: (_) => _StubTabs(TabsState.initial()),
        ),
      ],
      child: app,
    );

class _StubTabs extends Cubit<TabsState> implements TabsBloc {
  _StubTabs(super.initialState);

  @override
  void add(TabsEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget Function(Widget) _settingsApp = (app) => BlocProvider<SettingsBloc>(
  create: (_) => StubSettingsBloc(SettingsState.initial()),
  child: app,
);

// ---------------------------------------------------------------------------
// מילונים וביוגרפיות.
// ---------------------------------------------------------------------------

DictionaryLookupRepository _aramaicRepository({
  int extra = 0,
}) => DictionaryLookupRepository(
  loadAramaicEntries: () async => [
    const AramaicDictionaryEntry(aramaic: 'איתא', hebrew: 'יש'),
    const AramaicDictionaryEntry(
      aramaic: 'איתא',
      hebrew: 'קיים',
      dictionary: 'מילון שיח ישראל',
    ),
    AramaicDictionaryEntry(
      aramaic: 'מַאי חָזֵית דְּדָמָא דִּידָךְ סוּמָּק טְפֵי',
      hebrew:
          'מה ראית שדמך אדום יותר, $_mixed. זהו פירוש ארוך מאוד שנועד לבדוק '
          'שהכרטיס עוטף שורות ואינו גולש מרוחב המסך הצר.',
    ),
    for (var i = 0; i < extra; i++)
      AramaicDictionaryEntry(aramaic: 'איתא$i', hebrew: 'פירוש $i'),
  ],
);

DictionaryLookupRepository _acronymRepository() => DictionaryLookupRepository(
  loadAcronyms: () async => {
    'ר"י': [
      'רבי יוסי',
      'רבי ישמעאל',
      'רבינו יונה בן אברהם גירונדי מחבר שערי תשובה וספר היראה',
      'Rabbi Yehuda HaNasi (the compiler of the Mishnah and Rabbi in Hebrew)',
    ],
    'רש"י': ['רבי שלמה יצחקי'],
    'רמב"ם': ['רבי משה בן מימון'],
  },
);

class _FakeBiographies extends BiographiesRepository {
  _FakeBiographies({this.fail = false, this.many = 3});

  final bool fail;
  final int many;

  @override
  Future<BiographiesBundle> loadBundle() async {
    if (fail) throw StateError('no bundle');
    return BiographiesCodec.decode(
      encodeBundle({
        'format': 'biographies-app',
        'version': 1,
        'built': '2026-10-23',
        'release': 'v0.3.0',
        'author': 'abaye',
        'eras': [
          {'key': 'rishonim', 'label': 'ראשונים'},
          {'key': 'acharonim', 'label': 'אחרונים'},
        ],
        'credits': {
          'wikipedia': {
            'name': 'ויקיפדיה העברית',
            'license': 'CC BY-SA 4.0',
            'license_url': 'https://creativecommons.org/licenses/by-sa/4.0/',
            'attribution': 'על פי ערכי ויקיפדיה העברית.',
          },
        },
        'entries': [
          for (var i = 0; i < many; i++)
            {
              'id': 'Q$i',
              'era': i.isEven ? 'rishonim' : 'acharonim',
              'name': i == 0
                  ? 'רבינו משה בן מימון בעל ספר משנה תורה ומורה נבוכים $_mixed'
                  : 'רבי אברהם בן דוד מספר $i',
              'known_as': ['הרמב"ם', 'Maimonides'],
              'born': {'hebrew': 'ד\'תתצ"ח', 'gregorian': '1138'},
              'summary': 'מגדולי הפוסקים. $_mixed',
              'works': [
                {'title': 'משנה תורה', 'description': 'חיבור הלכתי'},
              ],
              'sources': [
                {
                  'credit': 'wikipedia',
                  'title': 'ערך ארוך מאוד בויקיפדיה העברית',
                  'url': 'https://he.wikipedia.org/wiki/Test',
                },
              ],
            },
        ],
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// חיפוש: תלויות משותפות.
// ---------------------------------------------------------------------------

class _MockHistory extends MockBloc<HistoryEvent, HistoryState>
    implements HistoryBloc {}

class _MockIndexing extends MockBloc<IndexingEvent, IndexingState>
    implements IndexingBloc {}

class _MockNavigation extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

class _MockLibrary extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class _MockTabs extends MockBloc<TabsEvent, TabsState> implements TabsBloc {}

class _MockSettings extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _SearchBloc extends SearchBloc {
  _SearchBloc(SearchState state) {
    emit(state);
  }

  @override
  void add(SearchEvent event) {
    if (event is! LoadMoreResults) super.add(event);
  }
}

SearchResult _result(int i, {String? title, String? text, String? reference}) =>
    SearchResult(
      id: BigInt.from(i),
      title: title ?? 'ספר $i',
      reference: reference ?? 'סימן $i',
      text: text ?? 'טקסט בדיקה $i עם מילת חיפוש',
      segment: BigInt.from(i),
      isPdf: false,
      filePath: 'book_$i.txt',
      mergedCount: 1,
      merged: const [],
      textStatus: TextStatus.ok,
      continuesToNextLine: false,
    );

Category _category(
  String title, {
  List<Category> subCategories = const [],
  List<Book> books = const [],
}) => Category(
  title: title,
  description: '',
  shortDescription: '',
  order: 1,
  subCategories: subCategories,
  books: books,
  parent: null,
);

/// ספרייה עם קטגוריות ושמות ארוכים, ו-[perCategory] ספרים בכל קטגוריה.
Library _library({int perCategory = 6}) {
  var id = 0;
  List<Book> books(String category) => [
    for (var i = 0; i < perCategory; i++)
      TextBook(
        id: ++id,
        title: i == 0 ? _longBookTitle : 'ספר $id',
        categoryPath: category,
      ),
  ];
  final top = [
    _category(
      'תנ"ך',
      subCategories: [_category('תורה', books: books('/תנ"ך/תורה'))],
    ),
    _category(
      'תלמוד בבלי והמפרשים עליו ועל סדרי המשנה בכל הדורות',
      books: books('/תלמוד'),
    ),
    _category('הלכה', books: books('/הלכה')),
  ];
  final library = Library(categories: top);
  void link(Category parent) {
    for (final sub in parent.subCategories) {
      sub.parent = parent;
      link(sub);
    }
  }

  for (final cat in top) {
    cat.parent = library;
  }
  link(library);
  return library;
}

/// תלויות כל מסכי החיפוש. עם [searchState] נבנה גם טאב חיפוש חי (פעיל ב-TabsBloc).
Widget Function(Widget) _searchEnv({
  SearchState? searchState,
  bool facets = false,
  bool external = false,
  bool preview = false,
  Library? library,
}) => (app) {
  final history = _MockHistory();
  final indexing = _MockIndexing();
  final navigation = _MockNavigation();
  final libraryBloc = _MockLibrary();
  final tabs = _MockTabs();
  final settings = _MockSettings();
  final searchBloc = searchState == null ? null : _SearchBloc(searchState);
  final tab = searchBloc == null
      ? null
      : SearchingTab(
          'חיפוש',
          searchState!.searchQuery,
          searchBloc: searchBloc,
        );
  if (tab != null) {
    tab.isLeftPaneOpen.value = facets;
    tab.externalSearchStatus.value = external
        ? const ExternalSearchStatus(
            sourceTitle: 'היברובוקס',
            loading: false,
            books: 3,
            hits: 7,
          )
        : null;
  }
  whenListen(
    history,
    const Stream<HistoryState>.empty(),
    initialState: HistoryLoaded([]),
  );
  whenListen(
    indexing,
    const Stream<IndexingState>.empty(),
    initialState: IndexingInitial(),
  );
  whenListen(
    navigation,
    const Stream<NavigationState>.empty(),
    initialState: const NavigationState(currentScreen: Screen.search),
  );
  whenListen(
    libraryBloc,
    const Stream<LibraryState>.empty(),
    initialState: LibraryState(library: library),
  );
  whenListen(
    tabs,
    const Stream<TabsState>.empty(),
    initialState: tab == null
        ? const TabsState(tabs: [], currentTabIndex: 0)
        : TabsState(tabs: [tab], currentTabIndex: 0, rawActivePane: tab),
  );
  whenListen(
    settings,
    const Stream<SettingsState>.empty(),
    initialState: SettingsState.initial().copyWith(
      searchShowPreview: preview,
    ),
  );
  addTearDown(() async {
    // קודם מפרקים את העץ: הווידג'טים עדיין מאזינים ל-notifiers של הטאב.
    final binding = TestWidgetsFlutterBinding.instance;
    binding.attachRootWidget(
      binding.wrapWithDefaultView(const SizedBox.shrink()),
    );
    await binding.pump();
    tab?.dispose();
    await searchBloc?.close();
    await history.close();
    await indexing.close();
    await navigation.close();
    await libraryBloc.close();
    await tabs.close();
    await settings.close();
  });
  return MultiBlocProvider(
    providers: [
      BlocProvider<HistoryBloc>.value(value: history),
      BlocProvider<IndexingBloc>.value(value: indexing),
      BlocProvider<NavigationBloc>.value(value: navigation),
      BlocProvider<LibraryBloc>.value(value: libraryBloc),
      BlocProvider<TabsBloc>.value(value: tabs),
      BlocProvider<SettingsBloc>.value(value: settings),
      if (searchBloc != null) BlocProvider<SearchBloc>.value(value: searchBloc),
    ],
    child: app,
  );
};

Widget _resultsScreen(BuildContext context) => TantivyFullTextSearch(
  tab: context.read<TabsBloc>().state.tabs.single as SearchingTab,
);

/// דיאלוג החיפוש נפתח מכפתור, כמו באפליקציה.
Widget _dialogOpener(SearchDialog Function() dialog) => Builder(
  builder: (context) => Center(
    child: TextButton(
      onPressed: () =>
          showDialog<void>(context: context, builder: (_) => dialog()),
      child: const Text('פתח'),
    ),
  ),
);

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('פתח'));
  await tester.pumpAndSettle();
}

PluginSearchDialogRegistry _registry() {
  final registry = PluginSearchDialogRegistry.forTesting();
  addTearDown(registry.dispose);
  return registry;
}

class _FakeSemanticRepository extends SemanticSearchRepository {
  _FakeSemanticRepository(this.current)
    : super(
        backend: FakeBackend(),
        consent: () => FakeConsentStore(),
        settings: FakeSettingsStore(),
      );

  final SemanticAvailability current;

  @override
  SemanticAvailability get availability => current;

  @override
  Stream<SemanticAvailability> get availabilityChanges => const Stream.empty();

  @override
  Future<SemanticAvailability> refresh() async => current;
}

/// כמה כפתורי תוסף בשדה החיפוש, חלקם עם תווית (תווית רק כשיש מקום).
class _ThreeExtras extends OtzariaSearchFieldExtraActions with ChangeNotifier {
  @override
  int get maxButtonCount => 3;

  @override
  bool get mayShowLabels => true;

  @override
  Widget? build(
    BuildContext context, {
    required TextEditingController controller,
    required ValueChanged<String>? onChanged,
    required ValueChanged<String>? onSubmitted,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      OtzariaSearchFieldButton(
        icon: FluentIcons.book_24_regular,
        tooltip: 'חפש בתוסף הראשון',
        label: 'תוסף ראשון',
        onPressed: () {},
      ),
      OtzariaSearchFieldButton(
        icon: FluentIcons.globe_24_regular,
        tooltip: 'חפש באתר',
        label: 'אתר',
        selected: true,
        onPressed: () {},
      ),
      OtzariaSearchFieldButton(
        icon: FluentIcons.history_24_regular,
        tooltip: 'היסטוריה',
        onPressed: () {},
      ),
    ],
  );
}

Bookmark _historyEntry(String q) => Bookmark(
  ref: q,
  book: TextBook(title: q),
  index: 0,
  isSearch: true,
);

Future<void> _settleSemantic(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder get _firstTextField => find.byType(TextField).first;

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(_firstTextField, text);
  await tester.pumpAndSettle();
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final engineReady = await tryInitSearchEngine();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  // -------------------------------------------------------------------------
  // משגר הכלים
  // -------------------------------------------------------------------------
  group('משגר הכלים', () {
    testResponsive(
      'פאנל הכלים, כלים מובנים ותוספים עם שם ארוך',
      viewports: _matrix,
      scaffold: false,
      wrapApp: _launcherApp([
        _plugin('p1', 'תוסף עם שם ארוך מאוד $_mixed'),
        _plugin('p2', 'תוסף שני'),
      ]),
      build: (_) => const _OpenLauncher(),
      verify: (tester, run) async {
        expectVisible(
          tester,
          run,
          find.byType(OtzariaSearchField),
          name: 'שדה חיפוש הכלים',
        );
        expectInsideViewport(
          tester,
          run,
          find.byType(ToolsLauncherPanel),
          name: 'פאנל הכלים',
        );
        expectVisible(
          tester,
          run,
          find.text('כלים ותוספים'),
          name: 'כותרת הפאנל',
        );
      },
    );

    testResponsive(
      'פאנל הכלים, חיפוש בלי תוצאות',
      viewports: viewportsFor(activeTier),
      scaffold: false,
      wrapApp: _launcherApp(const []),
      build: (_) => const _OpenLauncher(),
      act: (tester, run) => _type(tester, 'zzzzzzzzzzzz'),
      verify: (tester, run) async {
        expectVisible(
          tester,
          run,
          find.byType(OtzariaSearchField),
          name: 'שדה חיפוש הכלים',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // מילונים
  // -------------------------------------------------------------------------
  group('מילון ארמי', () {
    testResponsive(
      'כרטיס תוצאה, ערך ארוך ופירושים מרובים',
      viewports: _matrix,
      build: (_) => ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          AramaicResultCard(
            aramaic: 'מַאי חָזֵית דְּדָמָא דִּידָךְ סוּמָּק טְפֵי',
            hebrew:
                '1. מה ראית שדמך אדום יותר, פירוש ארוך מאוד שנועד לבדוק עטיפה.\n'
                '2. פירוש שני, $_mixed\n3. פירוש שלישי (הערה: ראה שם)',
            query: 'מאי',
          ),
          AramaicResultCard(
            aramaic: 'איתא',
            hebrew: 'יש, קיים',
            queryIsAramaic: false,
            query: 'יש',
          ),
        ],
      ),
      verify: (tester, run) async {
        expect(find.byType(AramaicResultCard), findsWidgets);
      },
    );

    testResponsive(
      'מסך המילון, תוצאות לחיפוש',
      viewports: _matrix,
      wrapApp: _settingsApp,
      build: (_) => AramaicDictionaryScreen(repository: _aramaicRepository()),
      act: (tester, run) async {
        await tester.pumpAndSettle();
        await _type(tester, 'איתא');
      },
      verify: (tester, run) async {
        expectVisible(
          tester,
          run,
          find.byType(TextField).first,
          name: 'שדה החיפוש',
        );
        expect(find.byType(AramaicResultCard), findsWidgets);
      },
    );

    testResponsive(
      'מסך המילון, אפס תוצאות',
      viewports: viewportsFor(activeTier),
      wrapApp: _settingsApp,
      build: (_) => AramaicDictionaryScreen(repository: _aramaicRepository()),
      act: (tester, run) async {
        await tester.pumpAndSettle();
        await _type(tester, 'ללללללללל');
      },
      verify: (tester, run) async {
        expect(find.byType(AramaicResultCard), findsNothing);
        expectVisible(
          tester,
          run,
          find.byType(TextField).first,
          name: 'שדה החיפוש',
        );
      },
    );

    testResponsive(
      'מסך המילון, מאות תוצאות',
      viewports: viewportsFor(activeTier),
      wrapApp: _settingsApp,
      build: (_) =>
          AramaicDictionaryScreen(repository: _aramaicRepository(extra: 300)),
      act: (tester, run) async {
        await tester.pumpAndSettle();
        await _type(tester, 'איתא');
      },
      verify: (tester, run) async {
        expectVisible(
          tester,
          run,
          find.byType(TextField).first,
          name: 'שדה החיפוש',
        );
        expect(find.byType(AramaicResultCard), findsWidgets);
      },
    );
  });

  group('מילון ראשי תיבות', () {
    testResponsive(
      'כרטיס תוצאה, פירושים ארוכים',
      viewports: _matrix,
      build: (_) => ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          AcronymResultCard(
            acronym: 'ר"י',
            meanings: [
              'רבי יוסי',
              'רבינו יונה בן אברהם גירונדי מחבר שערי תשובה וספר היראה',
              'Rabbi Yehuda HaNasi (the compiler of the Mishnah)',
            ],
          ),
        ],
      ),
      verify: (tester, run) async {
        expectVisible(tester, run, find.text('ר"י'), name: 'ראשי התיבות');
      },
    );

    testResponsive(
      'מסך ראשי התיבות, תוצאות',
      viewports: _matrix,
      wrapApp: _settingsApp,
      build: (_) => AcronymsDictionaryScreen(repository: _acronymRepository()),
      act: (tester, run) async {
        await tester.pumpAndSettle();
        await _type(tester, 'ר"י');
      },
      verify: (tester, run) async {
        expectVisible(
          tester,
          run,
          find.byType(TextField).first,
          name: 'שדה החיפוש',
        );
        expect(find.byType(AcronymResultCard), findsWidgets);
      },
    );

    testResponsive(
      'מסך ראשי התיבות, אפס תוצאות',
      viewports: viewportsFor(activeTier),
      wrapApp: _settingsApp,
      build: (_) => AcronymsDictionaryScreen(repository: _acronymRepository()),
      act: (tester, run) async {
        await tester.pumpAndSettle();
        await _type(tester, 'זזזזזזז');
      },
      verify: (tester, run) async {
        expect(find.byType(AcronymResultCard), findsNothing);
      },
    );
  });

  // -------------------------------------------------------------------------
  // ביוגרפיות
  // -------------------------------------------------------------------------
  group('ביוגרפיות', () {
    testResponsive(
      'המסך, רשימה עם שם ארוך',
      viewports: _matrix,
      // סרגל הצ'יפים של התקופות גולל אופקית בכוונה (גלגל, גרירה), כך שבהגדלת
      // טקסט 2.0 ברוחב 320 הוא חורג מהחלון ונגלל.
      horizontalScroll: true,
      wrapApp: _settingsApp,
      build: (_) => BiographiesScreen(repository: _FakeBiographies()),
      verify: (tester, run) async {
        expectVisible(
          tester,
          run,
          find.byType(TextField).first,
          name: 'שדה החיפוש',
        );
      },
    );

    testResponsive(
      'המסך, מאות ערכים',
      viewports: viewportsFor(activeTier),
      horizontalScroll: true, // סרגל הצ'יפים של התקופות גולל אופקית בכוונה
      wrapApp: _settingsApp,
      build: (_) => BiographiesScreen(repository: _FakeBiographies(many: 400)),
      verify: (tester, run) async {
        expectVisible(
          tester,
          run,
          find.byType(TextField).first,
          name: 'שדה החיפוש',
        );
      },
    );

    testResponsive(
      'המסך, חיפוש בלי תוצאות',
      viewports: viewportsFor(activeTier),
      horizontalScroll: true, // סרגל הצ'יפים של התקופות גולל אופקית בכוונה
      wrapApp: _settingsApp,
      build: (_) => BiographiesScreen(repository: _FakeBiographies()),
      act: (tester, run) => _type(tester, 'זזזזזזז'),
      verify: (tester, run) async {
        expectVisible(
          tester,
          run,
          find.text('לא נמצאו תוצאות'),
          name: 'מצב ריק',
        );
      },
    );

    testResponsive(
      'המסך, שגיאת טעינה',
      viewports: viewportsFor(activeTier),
      wrapApp: _settingsApp,
      build: (_) => BiographiesScreen(repository: _FakeBiographies(fail: true)),
      verify: (tester, run) async {
        expectVisible(
          tester,
          run,
          find.byType(TextField).first,
          name: 'שדה החיפוש',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // גימטריה ומדות ושיעורים
  // -------------------------------------------------------------------------
  group('גימטריה, מדות ושיעורים', () {
    testResponsive(
      'כרטיס תוצאה, נתיב ארוך ומספר בן שלוש ספרות',
      viewports: _matrix,
      wrapApp: _settingsApp,
      build: (_) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GematriaResultCard(
            number: 128,
            result: GematriaSearchResult(
              bookTitle: _longBookTitle,
              internalPath: '$_longBookTitle, $_mixed',
              preview: 'בראשית ברא אלהים את השמים ואת הארץ ' * 6,
              data: const gematria.SearchResult(
                file: 'x.txt',
                line: 1,
                text: 'בראשית ברא אלהים',
                contextBefore: 'לפני ההתאמה',
                contextAfter: 'אחרי ההתאמה',
              ),
            ),
          ),
        ],
      ),
      verify: (tester, run) async {
        expect(find.byType(GematriaResultCard), findsOneWidget);
      },
    );

    testResponsive(
      'מסך הגימטריה, מצב התחלתי',
      viewports: _matrix,
      wrapApp: _settingsApp,
      build: (_) => const GematriaSearchScreen(),
      verify: (tester, run) async {
        expectVisible(
          tester,
          run,
          find.byType(TextField).first,
          name: 'שדה החיפוש',
        );
      },
    );

    testResponsive(
      'ממיר המדות והשיעורים',
      viewports: _matrix,
      wrapApp: _settingsApp,
      build: (_) => const MeasurementConverterScreen(),
      verify: (tester, run) async {
        expect(find.byType(MeasurementConverterScreen), findsOneWidget);
      },
    );
  });

  // -------------------------------------------------------------------------
  // חיפוש: דיאלוג, תוצאות, עץ סינון, היסטוריה, שדה החיפוש
  // -------------------------------------------------------------------------
  if (!engineReady) {
    test(
      'חיפוש: סצנות הדיאלוג והתוצאות דורשות את מנוע החיפוש הנייטיבי',
      () {},
      skip: 'אין build נייטיבי של מנוע החיפוש',
    );
  } else {
    setUp(() {
      ActiveLexicalSearches.instance = ActiveLexicalSearches(
        stallThreshold: null,
      );
    });

    group('דיאלוג החיפוש', () {
      Future<void> verifyDialog(WidgetTester tester, ResponsiveRun run) async {
        expectInsideViewport(tester, run, find.byType(Dialog), name: 'הדיאלוג');
        expectVisible(
          tester,
          run,
          find.byKey(const ValueKey('search-dialog-submit')),
          name: 'כפתור החיפוש',
        );
      }

      testResponsive(
        'מצב מדויק',
        viewports: _matrix,
        wrapApp: _searchEnv(),
        build: (_) => _dialogOpener(
          () => SearchDialog(
            initialSearchMode: SearchMode.exact,
            pluginSearchDialogRegistry: _registry(),
            semanticRepository: _FakeSemanticRepository(
              SemanticAvailability.initial,
            ),
          ),
        ),
        act: (tester, run) => _openDialog(tester),
        verify: verifyDialog,
      );

      testResponsive(
        'מצב מתקדם, אפשרויות נוספות פתוחות',
        viewports: _matrix,
        wrapApp: _searchEnv(),
        build: (_) => _dialogOpener(
          () => SearchDialog(
            initialSearchMode: SearchMode.advanced,
            pluginSearchDialogRegistry: _registry(),
            semanticRepository: _FakeSemanticRepository(
              SemanticAvailability.initial,
            ),
          ),
        ),
        act: (tester, run) async {
          await _openDialog(tester);
          final more = find.byKey(const ValueKey('search-dialog-more-options'));
          await tester.ensureVisible(more);
          await tester.tap(more);
          await tester.pumpAndSettle();
        },
        verify: verifyDialog,
      );

      testResponsive(
        'מצב מקורב',
        viewports: viewportsFor(activeTier),
        wrapApp: _searchEnv(),
        build: (_) => _dialogOpener(
          () => SearchDialog(
            initialSearchMode: SearchMode.fuzzy,
            pluginSearchDialogRegistry: _registry(),
            semanticRepository: _FakeSemanticRepository(
              SemanticAvailability.initial,
            ),
          ),
        ),
        act: (tester, run) => _openDialog(tester),
        verify: verifyDialog,
      );

      testResponsive(
        'חיפוש בתוך ספר עם שם ארוך',
        viewports: _matrix,
        wrapApp: _searchEnv(),
        build: (_) => _dialogOpener(
          () => SearchDialog(
            bookTitle: _longBookTitle,
            returnResultOnSubmit: true,
            initialSearchMode: SearchMode.advanced,
            pluginSearchDialogRegistry: _registry(),
            semanticRepository: _FakeSemanticRepository(
              SemanticAvailability.initial,
            ),
          ),
        ),
        act: (tester, run) => _openDialog(tester),
        verify: verifyDialog,
      );

      testResponsive(
        'שאילתה ארוכה בעברית ואנגלית מעורבות',
        viewports: _matrix,
        wrapApp: _searchEnv(),
        build: (_) => _dialogOpener(
          () => SearchDialog(
            initialSearchMode: SearchMode.exact,
            pluginSearchDialogRegistry: _registry(),
            semanticRepository: _FakeSemanticRepository(
              SemanticAvailability.initial,
            ),
          ),
        ),
        act: (tester, run) async {
          await _openDialog(tester);
          await tester.enterText(
            find.byType(TextField).first,
            '$_mixed $_mixed',
          );
          await tester.pumpAndSettle();
        },
        verify: verifyDialog,
      );

      testResponsive(
        'מצב חכם (חיפוש סמנטי) מוכן לשימוש',
        viewports: _matrix,
        wrapApp: _searchEnv(),
        build: (_) => _dialogOpener(
          () => SearchDialog(
            initialSearchMode: SearchMode.exact,
            pluginSearchDialogRegistry: _registry(),
            semanticRepository: _FakeSemanticRepository(
              const SemanticAvailability(
                phase: SemanticAvailabilityPhase.ready,
                consentGranted: true,
              ),
            ),
            semanticConsent: FakeConsentStore(),
          ),
        ),
        act: (tester, run) async {
          await _openDialog(tester);
          final semantic = find.byKey(
            const ValueKey('search-dialog-semantic-mode'),
          );
          await tester.ensureVisible(semantic);
          await tester.tap(semantic);
          await tester.pumpAndSettle();
        },
        verify: verifyDialog,
      );

      for (final scene in <(String, SemanticAvailability, FakeConsentStore)>[
        (
          'מצב חכם, נדרשת הסכמה',
          const SemanticAvailability(
            phase: SemanticAvailabilityPhase.consentRequired,
            consentGranted: false,
          ),
          FakeConsentStore(SearchFeedbackConsent.unknown),
        ),
        (
          'מצב חכם, הורדה מתבצעת',
          const SemanticAvailability(
            phase: SemanticAvailabilityPhase.downloading,
            consentGranted: true,
            progress: SemanticDownloadProgress(
              item: SemanticDownloadItem.model,
              receivedBytes: 40000000,
              totalBytes: 120000000,
              step: 1,
              stepCount: 3,
            ),
          ),
          FakeConsentStore(),
        ),
        (
          'מצב חכם, ההורדה נכשלה (ניתוק רשת)',
          const SemanticAvailability(
            phase: SemanticAvailabilityPhase.failed,
            consentGranted: true,
            failure: SemanticFailure(SemanticFailureKind.network),
          ),
          FakeConsentStore(),
        ),
      ]) {
        testResponsive(
          scene.$1,
          viewports: _matrix,
          wrapApp: _searchEnv(),
          build: (_) => _dialogOpener(
            () => SearchDialog(
              initialSearchMode: SearchMode.exact,
              pluginSearchDialogRegistry: _registry(),
              semanticRepository: _FakeSemanticRepository(scene.$2),
              semanticConsent: scene.$3,
            ),
          ),
          act: (tester, run) async {
            await _openDialog(tester);
            final semantic = find.byKey(
              const ValueKey('search-dialog-semantic-mode'),
            );
            await tester.ensureVisible(semantic);
            await tester.tap(semantic);
            await tester.pump(const Duration(milliseconds: 500));
          },
          verify: (tester, run) async {
            expectInsideViewport(
              tester,
              run,
              find.byType(Dialog),
              name: 'הדיאלוג',
            );
          },
        );
      }

      testResponsive(
        'מצב חכם, ממתין להורדת הנתונים',
        viewports: viewportsFor(activeTier),
        wrapApp: _searchEnv(),
        build: (_) => _dialogOpener(
          () => SearchDialog(
            initialSearchMode: SearchMode.exact,
            pluginSearchDialogRegistry: _registry(),
            semanticRepository: _FakeSemanticRepository(
              const SemanticAvailability(
                phase: SemanticAvailabilityPhase.needsDownload,
                consentGranted: true,
              ),
            ),
            semanticConsent: FakeConsentStore(),
          ),
        ),
        act: (tester, run) async {
          await _openDialog(tester);
          final semantic = find.byKey(
            const ValueKey('search-dialog-semantic-mode'),
          );
          await tester.ensureVisible(semantic);
          await tester.tap(semantic);
          await tester.pumpAndSettle();
        },
        verify: (tester, run) async {
          expectInsideViewport(
            tester,
            run,
            find.byType(Dialog),
            name: 'הדיאלוג',
          );
        },
      );
    });

    group('מסך התוצאות', () {
      Future<void> verifyScreen(WidgetTester tester, ResponsiveRun run) async {
        expect(find.byType(TantivyFullTextSearch), findsOneWidget);
      }

      testResponsive(
        'מאות תוצאות',
        viewports: _matrix,
        scaffold: true,
        wrapApp: _searchEnv(
          searchState: SearchState(
            searchQuery: 'בדיקה',
            totalResults: 1500,
            results: [for (var i = 0; i < 100; i++) _result(i)],
          ),
        ),
        horizontalScroll: true, // תצוגת השאילתה בסרגל גוללת בכוונה
        build: _resultsScreen,
        verify: verifyScreen,
      );

      testResponsive(
        'שם ספר ארוך וטקסט עברי ואנגלי מעורב',
        viewports: _matrix,
        wrapApp: _searchEnv(
          searchState: SearchState(
            searchQuery: 'ברכות',
            totalResults: 3,
            results: [
              _result(
                1,
                title: _longBookTitle,
                reference: '$_longBookTitle, $_mixed',
                text: _mixed,
              ),
              _result(2, title: 'Mishneh Torah, Laws of Prayer', text: _mixed),
              _result(3, text: 'x' * 400),
            ],
          ),
        ),
        horizontalScroll: true, // תצוגת השאילתה בסרגל גוללת בכוונה
        build: _resultsScreen,
        verify: verifyScreen,
      );

      testResponsive(
        'אפס תוצאות',
        viewports: viewportsFor(activeTier),
        wrapApp: _searchEnv(
          searchState: const SearchState(searchQuery: 'בדיקה'),
        ),
        horizontalScroll: true, // תצוגת השאילתה בסרגל גוללת בכוונה
        build: _resultsScreen,
        verify: (tester, run) async {
          // הכותרת ולא הרכיב כולו: ה-hit-test נעשה במרכז הרכיב, ובחלון צר
          // ההודעה נשברת ליותר שורות והמרכז נופל על הרווח שבין האייקון לטקסט.
          expectVisible(tester, run, find.text('אין תוצאות'), name: 'מצב ריק');
        },
      );

      testResponsive(
        'טעינה',
        viewports: viewportsFor(activeTier),
        wrapApp: _searchEnv(
          searchState: const SearchState(
            searchQuery: 'בדיקה',
            isLoading: true,
            isCounting: true,
          ),
        ),
        horizontalScroll: true, // תצוגת השאילתה בסרגל גוללת בכוונה
        build: (context) => TickerMode(
          enabled: false, // ספינר אינסופי: pumpAndSettle לא היה מסתיים
          child: _resultsScreen(context),
        ),
        verify: verifyScreen,
      );

      testResponsive(
        'שגיאת חיפוש',
        viewports: viewportsFor(activeTier),
        wrapApp: _searchEnv(
          searchState: SearchState(
            searchQuery: 'בדיקה',
            errorMessage:
                'שגיאה בקומפילציית הביטוי הרגולרי: unclosed group near ((( $_mixed',
          ),
        ),
        horizontalScroll: true, // תצוגת השאילתה בסרגל גוללת בכוונה
        build: _resultsScreen,
        verify: verifyScreen,
      );

      testResponsive(
        'עץ הסינון פתוח לצד התוצאות',
        viewports: _matrix,
        wrapApp: _searchEnv(
          facets: true,
          library: _library(),
          searchState: SearchState(
            searchQuery: 'בדיקה',
            totalResults: 60,
            results: [for (var i = 0; i < 30; i++) _result(i)],
            facetCounts: const {'/': 60, '/תנ"ך': 20, '/הלכה': 10},
          ),
        ),
        horizontalScroll: true, // תצוגת השאילתה בסרגל גוללת בכוונה
        build: _resultsScreen,
        verify: verifyScreen,
      );

      testResponsive(
        'תצוגה מקדימה פתוחה, תוצאות ועץ סינון',
        // ב-320 עם ספק חיצוני פקדי הסרגל (מיון, איחוד, מיקום המקור)
        // חורגים ב-17 פיקסלים; הפתרון (שורה שנייה לשאילתה) מחכה להכרעה.
        viewports: [
          for (final v in viewportsFor(activeTier))
            if (v.width > 320) v,
        ],
        wrapApp: _searchEnv(
          facets: true,
          preview: true,
          library: _library(),
          external: true,
          searchState: SearchState(
            searchQuery: 'בדיקה',
            totalResults: 60,
            results: [for (var i = 0; i < 30; i++) _result(i)],
            facetCounts: const {'/': 60, '/תנ"ך': 20},
          ),
        ),
        horizontalScroll: true, // תצוגת השאילתה בסרגל גוללת בכוונה
        build: _resultsScreen,
        verify: verifyScreen,
      );
    });

    group('עץ הסינון', () {
      testResponsive(
        'ספרייה גדולה עם שמות ארוכים',
        viewports: _matrix,
        build: (_) {
          final library = _library(perCategory: 80);
          final counts = <String, int>{
            '/': 500,
            '/תנ"ך': 100,
            '/תנ"ך/תורה': 100,
            '/תלמוד': 80,
            '/הלכה': 80,
          };
          for (final book in library.getAllBooks()) {
            counts['id:${book.id}'] = 3;
          }
          return SearchNavigationTree(
            library: library,
            facetCounts: counts,
            selectedFacets: const {},
            expansion: const {
              '/תנ"ך': true,
              '/תנ"ך/תורה': true,
              '/תלמוד': true,
              '/הלכה': true,
            },
            filterQuery: '',
            isLoading: false,
            hasResults: true,
            onSetFacet: (_) {},
            onToggleFacet: (_) {},
            onToggleExpand: (_, _) {},
            onClearAll: () {},
          );
        },
        verify: (tester, run) async {
          expect(find.byType(SearchNavigationTree), findsOneWidget);
        },
      );

      testResponsive(
        'טעינת הספירות',
        viewports: viewportsFor(activeTier),
        build: (_) => SearchNavigationTree(
          library: _library(),
          facetCounts: const {},
          selectedFacets: const {},
          expansion: const {},
          filterQuery: '',
          isLoading: true,
          hasResults: false,
          onSetFacet: (_) {},
          onToggleFacet: (_) {},
          onToggleExpand: (_, _) {},
          onClearAll: () {},
        ),
        verify: (tester, run) async {
          expect(find.byType(SearchNavigationTree), findsOneWidget);
        },
      );
    });

    group('היסטוריית חיפוש ושדה החיפוש', () {
      testResponsive(
        'תפריט ההיסטוריה, רשימה ארוכה',
        viewports: _matrix,
        build: (_) => Center(
          child: SearchHistoryMenu(
            entries: [
              for (var i = 0; i < 40; i++)
                _historyEntry(i.isEven ? '$_mixed $i' : 'חיפוש $i'),
            ],
            onSelect: (_) {},
            onRemove: (_) {},
          ),
        ),
        verify: (tester, run) async {
          expectVisible(
            tester,
            run,
            find.byType(SearchHistoryMenu),
            name: 'תפריט ההיסטוריה',
          );
        },
      );

      testResponsive(
        'תפריט ההיסטוריה, ריק',
        viewports: viewportsFor(activeTier),
        build: (_) => Center(
          child: SearchHistoryMenu(
            entries: const [],
            onSelect: (_) {},
            onRemove: (_) {},
          ),
        ),
        verify: (tester, run) async {
          expectVisible(
            tester,
            run,
            find.byType(SearchHistoryMenu),
            name: 'תפריט ההיסטוריה',
          );
        },
      );

      for (final below in [false, true]) {
        testResponsive(
          'שדה חיפוש עם שלושה תוספים${below ? ', פעולות מתחת' : ''}',
          viewports: _matrix,
          build: (_) => Padding(
            padding: const EdgeInsets.all(8),
            child: Align(
              alignment: Alignment.topCenter,
              child: OtzariaSearchField(
                controller: TextEditingController(text: _mixed),
                hintText: 'חיפוש',
                actionsBelow: below,
                extraActions: _ThreeExtras(),
              ),
            ),
          ),
          verify: (tester, run) async {
            expectVisible(
              tester,
              run,
              find.descendant(
                of: find.byType(OtzariaSearchField),
                matching: find.byType(TextField),
              ),
              name: 'שדה הקלט',
            );
            expectVisible(
              tester,
              run,
              find.byTooltip('היסטוריה'),
              name: 'כפתור התוסף האחרון',
            );
          },
        );
      }
    });

    group('חיפוש סמנטי', () {
      testResponsive(
        'מסך התוצאות, מאות תוצאות ושם ארוך',
        viewports: _matrix,
        horizontalScroll: true, // שאילתה ארוכה בסרגל גוללת בכוונה
        wrapApp: _searchEnv(library: _library()),
        build: (_) {
          final items = [
            resultItem(1, source: SemanticResultSource.both),
            for (var i = 2; i <= 75; i++) resultItem(i),
          ];
          final tab = SemanticSearchTab(
            runOnFirstShow: true,
            options: SemanticQueryOptions(query: _mixed),
            createResultsBloc: (_) => buildResultsBloc(
              source: FakeResultsSource(items: items),
              recorder: RecordingRecorder(),
            ),
          );
          addTearDown(tab.dispose);
          return SemanticSearchResultsScreen(tab: tab, platformSupported: true);
        },
        act: (tester, run) => _settleSemantic(tester),
        verify: (tester, run) async {
          expect(find.byType(SemanticSearchResultsScreen), findsOneWidget);
        },
      );

      testResponsive(
        'מסך התוצאות, אפס תוצאות',
        viewports: viewportsFor(activeTier),
        horizontalScroll: true, // תצוגת השאילתה בסרגל גוללת בכוונה
        wrapApp: _searchEnv(library: _library()),
        build: (_) {
          final tab = SemanticSearchTab(
            runOnFirstShow: true,
            options: SemanticQueryOptions(query: 'אין כזה'),
            createResultsBloc: (_) => buildResultsBloc(
              source: FakeResultsSource(items: const []),
              recorder: RecordingRecorder(),
            ),
          );
          addTearDown(tab.dispose);
          return SemanticSearchResultsScreen(tab: tab, platformSupported: true);
        },
        act: (tester, run) => _settleSemantic(tester),
        verify: (tester, run) async {
          expect(find.byType(SemanticSearchResultsScreen), findsOneWidget);
        },
      );

      testResponsive(
        'מסך התוצאות, שגיאת חיפוש',
        viewports: viewportsFor(activeTier),
        wrapApp: _searchEnv(library: _library()),
        build: (_) {
          final tab = SemanticSearchTab(
            runOnFirstShow: true,
            options: SemanticQueryOptions(query: 'בדיקה'),
            createResultsBloc: (_) => buildResultsBloc(
              source: FakeResultsSource(error: StateError('engine failed')),
              recorder: RecordingRecorder(),
            ),
          );
          addTearDown(tab.dispose);
          return SemanticSearchResultsScreen(tab: tab, platformSupported: true);
        },
        act: (tester, run) => _settleSemantic(tester),
        verify: (tester, run) async {
          expect(find.byType(SemanticSearchResultsScreen), findsOneWidget);
        },
      );

      testResponsive(
        'מסך התוצאות, פלטפורמה שאינה נתמכת',
        viewports: viewportsFor(activeTier),
        wrapApp: _searchEnv(library: _library()),
        build: (_) {
          final tab = SemanticSearchTab(
            runOnFirstShow: true,
            options: SemanticQueryOptions(query: 'בדיקה'),
            createResultsBloc: (_) => buildResultsBloc(
              source: FakeResultsSource(),
              recorder: RecordingRecorder(),
            ),
          );
          addTearDown(tab.dispose);
          return SemanticSearchResultsScreen(
            tab: tab,
            platformSupported: false,
          );
        },
        act: (tester, run) => _settleSemantic(tester),
        verify: (tester, run) async {
          expect(find.byType(SemanticSearchResultsScreen), findsOneWidget);
        },
      );
    });
  }
}

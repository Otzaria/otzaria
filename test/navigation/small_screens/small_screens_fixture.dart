// מסכים קטנים (q12 Q8): החלון הראשי האמיתי (MainWindowScreen) עם המסכים
// העיקריים, בכל גודל חלון. משותף לבדיקת הגלישה (small_screens_overflow_test)
// ולסצנות של התמונות.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_scope/external_activation_service.dart';
import 'package:otzaria/app_scope/process_duties.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/device_chrome.dart';
import 'package:otzaria/core/windowing/window_fullscreen_cubit.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/data/repository/data_repository.dart';
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
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';
import 'package:otzaria/personal_notes/personal_notes_system.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:otzaria/work_status/work_status_cubit.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_state.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:window_manager/window_manager.dart' show TitleBarStyle;

/// הגדלים שנבדקים: מחשב 10" (כולל חצי מסך), טלפון לאורך ולרוחב.
const kSmallScreenSizes = <String, Size>{
  '1280x800': Size(1280, 800),
  '1024x600': Size(1024, 600),
  '960x1080': Size(960, 1080),
  '683x768': Size(683, 768),
  '640x360': Size(640, 360),
  '568x320': Size(568, 320),
  '360x640': Size(360, 640),
  '320x568': Size(320, 568),
};

/// טלפון: הצד הקצר מתחת ל-480 (רוחב או גובה). שם אין כפתורי חלון.
bool isPhoneSize(Size size) => size.shortestSide < 480;

/// המסכים העיקריים שהחלון מציג.
enum SmallScreen { home, reader, pdf, search, settings }

const smallScreenGenesis = [
  '<h2>פרק א</h2>',
  '(א) בְּרֵאשִׁית בָּרָא אֱלֹהִים אֵת הַשָּׁמַיִם וְאֵת הָאָרֶץ:',
  '(ב) וְהָאָרֶץ הָיְתָה תֹהוּ וָבֹהוּ וְחֹשֶׁךְ עַל פְּנֵי תְהוֹם וְרוּחַ אֱלֹהִים מְרַחֶפֶת עַל פְּנֵי הַמָּיִם:',
  '(ג) וַיֹּאמֶר אֱלֹהִים יְהִי אוֹר וַיְהִי אוֹר:',
  '(ד) וַיַּרְא אֱלֹהִים אֶת הָאוֹר כִּי טוֹב וַיַּבְדֵּל אֱלֹהִים בֵּין הָאוֹר וּבֵין הַחֹשֶׁךְ:',
  '(ה) וַיִּקְרָא אֱלֹהִים לָאוֹר יוֹם וְלַחֹשֶׁךְ קָרָא לָיְלָה וַיְהִי עֶרֶב וַיְהִי בֹקֶר יוֹם אֶחָד:',
  '(ו) וַיֹּאמֶר אֱלֹהִים יְהִי רָקִיעַ בְּתוֹךְ הַמָּיִם וִיהִי מַבְדִּיל בֵּין מַיִם לָמָיִם:',
  '(ז) וַיַּעַשׂ אֱלֹהִים אֶת הָרָקִיעַ וַיַּבְדֵּל בֵּין הַמַּיִם אֲשֶׁר מִתַּחַת לָרָקִיעַ וּבֵין הַמַּיִם אֲשֶׁר מֵעַל לָרָקִיעַ וַיְהִי כֵן:',
  '(ח) וַיִּקְרָא אֱלֹהִים לָרָקִיעַ שָׁמָיִם וַיְהִי עֶרֶב וַיְהִי בֹקֶר יוֹם שֵׁנִי:',
  '(ט) וַיֹּאמֶר אֱלֹהִים יִקָּווּ הַמַּיִם מִתַּחַת הַשָּׁמַיִם אֶל מָקוֹם אֶחָד וְתֵרָאֶה הַיַּבָּשָׁה וַיְהִי כֵן:',
  '(י) וַיִּקְרָא אֱלֹהִים לַיַּבָּשָׁה אֶרֶץ וּלְמִקְוֵה הַמַּיִם קָרָא יַמִּים וַיַּרְא אֱלֹהִים כִּי טוֹב:',
];

class _Cubit<S> extends Cubit<S> {
  _Cubit(super.initialState);
}

class _NavBloc extends _Cubit<NavigationState> implements NavigationBloc {
  _NavBloc(super.initialState);
  @override
  void add(NavigationEvent event) {
    // המעבר בין מסכים אמיתי מספיק לסצנות: רק NavigateToScreen.
    if (event is NavigateToScreen) {
      emit(NavigationState(currentScreen: event.screen));
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _SettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TabsBloc extends _Cubit<TabsState> implements TabsBloc {
  _TabsBloc(super.initialState);
  @override
  void add(TabsEvent event) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LibraryBloc extends _Cubit<LibraryState> implements LibraryBloc {
  _LibraryBloc(super.initialState);
  @override
  void add(LibraryEvent event) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IndexingBloc extends _Cubit<IndexingState> implements IndexingBloc {
  _IndexingBloc() : super(IndexingInitial());
  @override
  void add(IndexingEvent event) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HistoryBloc extends _Cubit<HistoryState> implements HistoryBloc {
  _HistoryBloc() : super(HistoryLoaded([]));
  @override
  void add(HistoryEvent event) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WorkspaceBloc extends _Cubit<WorkspaceState> implements WorkspaceBloc {
  _WorkspaceBloc() : super(const WorkspaceState(workspaces: []));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PluginSystemBloc extends _Cubit<PluginSystemState>
    implements PluginSystemBloc {
  _PluginSystemBloc() : super(const PluginSystemLoaded([]));
  @override
  void add(PluginSystemEvent event) {}
  // אין תוספים: כל רישום או מארח של התוספים חסר.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      invocation.isGetter ? null : super.noSuchMethod(invocation);
}

class _LibraryUpdateBloc extends _Cubit<LibraryUpdateState>
    implements LibraryUpdateBloc {
  _LibraryUpdateBloc() : super(const LibraryUpdateState());
  @override
  void add(LibraryUpdateEvent event) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BookmarkBloc extends _Cubit<BookmarkState> implements BookmarkBloc {
  _BookmarkBloc() : super(BookmarkState.initial());
  @override
  bool addBookmark({
    required String ref,
    required Book book,
    required int index,
    List<String>? commentatorsToShow,
    BookmarkTargetKind targetKind = BookmarkTargetKind.book,
    String? label,
  }) => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SearchBloc extends SearchBloc {
  _SearchBloc(SearchState s) {
    emit(s);
  }
  @override
  void add(SearchEvent event) {}
}

class _ShamorData extends ShamorZachorDataProvider {
  @override
  bool get hasData => false;
  @override
  Future<void> ensureLoaded() async {}
}

class _ShamorProgress extends ShamorZachorProgressProvider {
  @override
  Future<void> ensureLoaded() async {}
}

Category _cat(
  String title,
  int order, {
  List<Book> books = const [],
  List<Category> subs = const [],
  String description = '',
}) => Category(
  title: title,
  description: description,
  shortDescription: '',
  order: order,
  subCategories: [...subs],
  books: [...books],
  parent: null,
);

Library smallScreenLibrary() {
  final lib = Library(
    categories: [
      _cat(
        'תנ"ך',
        1,
        description: 'תורה, נביאים וכתובים עם מפרשיהם.',
        subs: [
          _cat(
            'תורה',
            1,
            books: [
              TextBook(title: 'בראשית'),
              TextBook(title: 'שמות'),
            ],
          ),
          _cat('נביאים', 2),
        ],
      ),
      _cat('משנה', 2),
      _cat(
        'תלמוד',
        3,
        subs: [
          _cat('בבלי', 1, books: [TextBook(title: 'ברכות')]),
        ],
      ),
      _cat('מדרש', 4),
      _cat(
        'הלכה',
        5,
        books: [
          TextBook(title: 'שולחן ערוך', author: 'רבי יוסף קארו'),
          TextBook(title: 'משנה תורה', author: 'רמב"ם'),
        ],
      ),
      _cat('קבלה', 6),
      _cat('מחשבת ישראל', 7),
      _cat(
        'חסידות',
        8,
        books: [TextBook(title: 'תניא', author: 'אדמו"ר הזקן')],
      ),
    ],
  );
  for (final c in lib.subCategories) {
    c.parent = lib;
    for (final sc in c.subCategories) {
      sc.parent = c;
    }
  }
  return lib;
}

TextBookLoaded smallScreenBook(TextBook book, {bool commentary = false}) =>
    TextBookLoaded(
      book: book,
      showLeftPane: false,
      content: smallScreenGenesis,
      fontSize: 25,
      showSplitView: commentary,
      activeCommentators: commentary ? const ['רש"י'] : const [],
      commentatorGroups: const [],
      availableCommentators: commentary ? const ['רש"י'] : const [],
      links: const <Link>[],
      visibleLinks: const <Link>[],
      linksByLine: const {},
      tableOfContents: const [],
      removeNikud: false,
      removePunctuation: false,
      visibleIndices: const [0],
      selectedIndex: null,
      pinLeftPane: false,
      searchText: '',
      currentTitle: 'בראשית, פרק א',
      searchMode: SearchMode.exact,
    );

List<SearchResult> smallScreenResults() => [
  for (var i = 0; i < 8; i++)
    SearchResult(
      id: BigInt.from(i + 1),
      title: [
        'בראשית רבה',
        'שולחן ערוך אורח חיים',
        'רש"י על התורה',
        'משנה ברורה',
      ][i % 4],
      reference: 'סימן ${i + 1}',
      text:
          'בראשית ברא אלהים את השמים ואת הארץ, אמר רבי יהושע בן לוי, בשביל התורה שנקראת ראשית, ובשביל ישראל שנקראו ראשית ${i + 1}',
      segment: BigInt.from(i),
      isPdf: false,
      filePath: 'book_$i.txt',
      mergedCount: 1,
      merged: const [],
      textStatus: TextStatus.ok,
      continuesToNextLine: false,
    ),
];

/// החלון הראשי במסך [screen]: מחזיר את הספקים שעוטפים את ה-MaterialApp,
/// שבו `home` הוא [MainWindowScreen]. ערכת הנושא, הגודל וה-pump שייכים
/// לקורא (הבדיקה או הסצנה).
///
/// בגודל טלפון ([isPhoneSize]) שורת הכותרת נבנית כמו בטלפון, בלי כפתורי
/// חלון. [pdfPath] נדרש ל-[SmallScreen.pdf].
///
/// [compactMenuMode]: "צפיפות ממשק" שהמשתמש בחר. null הוא "לא נבחר", כמו
/// בהתקנה חדשה.
Widget Function(Widget app) smallScreenProviders(
  WidgetTester tester, {
  required SmallScreen screen,
  required Size size,
  String? pdfPath,
  bool? compactMenuMode,
}) {
  tz.initializeTimeZones();
  final dataRoot = Directory.systemTemp.createTempSync('otzaria-small-screen-');
  AppPaths.debugOverrideDataRootPath(dataRoot.path);
  final messenger = tester.binding.defaultBinaryMessenger;
  for (final name in ['window_manager', 'otzaria/splash']) {
    messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
      if (call.method == 'isVisible') return true;
      if (call.method.startsWith('is')) return false;
      return null;
    });
  }
  addTearDown(() {
    for (final name in ['window_manager', 'otzaria/splash']) {
      messenger.setMockMethodCallHandler(MethodChannel(name), null);
    }
    AppPaths.debugOverrideDataRootPath(null);
    try {
      dataRoot.deleteSync(recursive: true);
    } on FileSystemException {
      // קובץ שעדיין פתוח נמחק עם תיקיית הזמניים של המערכת.
    }
  });
  DeviceChrome.debugMobileOverride = isPhoneSize(size);
  addTearDown(() => DeviceChrome.debugMobileOverride = null);
  // כמו חלון שאינו בעל התהליך: בלי ניקוז הפעלות חיצוניות.
  ProcessDuties.debugOverride = ProcessDuties(isProcessOwner: () => false);
  addTearDown(() => ProcessDuties.debugOverride = null);
  final library = smallScreenLibrary();
  DataRepository.instance.library = Future.value(library);

  final focus = FocusRepository()..resetForTesting();
  final List<OpenedTab> tabs;
  OpenedTab? openTab;
  _TextBookBloc? bookBloc;
  _SearchBloc? searchBloc;
  switch (screen) {
    case SmallScreen.reader:
      final book = TextBook(title: 'בראשית');
      bookBloc = _TextBookBloc(smallScreenBook(book, commentary: true));
      openTab = TextBookTab(book: book, index: 0, blocOverride: bookBloc);
      tabs = [openTab];
    case SmallScreen.pdf:
      openTab = PdfBookTab(
        book: PdfBook(title: 'ספר בדיקה', path: pdfPath!),
        pageNumber: 1,
      );
      tabs = [openTab];
    case SmallScreen.search:
      searchBloc = _SearchBloc(
        SearchState(
          searchQuery: 'בראשית ברא',
          totalResults: 8,
          results: smallScreenResults(),
        ),
      );
      openTab = SearchingTab(
        'חיפוש: בראשית ברא',
        'בראשית ברא',
        searchBloc: searchBloc,
        autoRunInitialSearch: false,
      );
      tabs = [openTab];
    case SmallScreen.home:
    case SmallScreen.settings:
      tabs = const [];
  }
  final navigation = _NavBloc(
    NavigationState(
      currentScreen: switch (screen) {
        SmallScreen.home => Screen.library,
        SmallScreen.reader || SmallScreen.pdf => Screen.reading,
        SmallScreen.search => Screen.search,
        SmallScreen.settings => Screen.settings,
      },
    ),
  );
  final settings = _SettingsBloc(
    SettingsState.initial().copyWith(
      isOfflineMode: true,
      settingsLanguageCode: 'he',
      compactMenuMode: compactMenuMode,
      compactMenuModeIsSet: compactMenuMode != null,
    ),
  );
  final tabsBloc = _TabsBloc(TabsState(tabs: tabs, currentTabIndex: 0));
  final libraryBloc = _LibraryBloc(
    LibraryState(
      library: library,
      currentCategory: library,
      isLoading: false,
    ),
  );
  final workStatus = WorkStatusCubit();
  final indexing = _IndexingBloc();
  final history = _HistoryBloc();
  final workspace = _WorkspaceBloc();
  final plugins = _PluginSystemBloc();
  final libraryUpdate = _LibraryUpdateBloc();
  final bookmarks = _BookmarkBloc();
  final notes = PersonalNotesBloc();

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    openTab?.dispose();
    for (final bloc in <BlocBase<Object?>>[
      navigation,
      settings,
      tabsBloc,
      libraryBloc,
      workStatus,
      indexing,
      history,
      workspace,
      plugins,
      libraryUpdate,
      bookmarks,
      notes,
      ?bookBloc,
      ?searchBloc,
    ]) {
      await bloc.close();
    }
    focus.resetForTesting();
    DataRepository.instance.invalidateLibraryCache();
  });

  const window = _FakeWindow(AppWindowId('small-screen-window'));
  return (app) => AppWindowScope(
    controller: window,
    geometry: window,
    role: const AppWindowRole(isPrimaryView: false, openedWithTab: true),
    child: MultiProvider(
      providers: [
        Provider<FocusRepository>.value(value: focus),
        RepositoryProvider<SettingsRepository>(
          create: (_) => SettingsRepository(),
        ),
        ChangeNotifierProvider<ShamorZachorDataProvider>(
          create: (_) => _ShamorData(),
        ),
        ChangeNotifierProvider<ShamorZachorProgressProvider>(
          create: (_) => _ShamorProgress(),
        ),
        Provider<ExternalActivationService>(
          create: (_) => ExternalActivationService(),
          dispose: (_, service) => service.dispose(),
        ),
        BlocProvider<NavigationBloc>.value(value: navigation),
        BlocProvider<WorkStatusCubit>.value(value: workStatus),
        BlocProvider<SettingsBloc>.value(value: settings),
        BlocProvider<WindowFullscreenCubit>(
          create: (_) =>
              WindowFullscreenCubit(initial: false, persist: (_) async {}),
        ),
        BlocProvider<IndexingBloc>.value(value: indexing),
        BlocProvider<HistoryBloc>.value(value: history),
        BlocProvider<LibraryBloc>.value(value: libraryBloc),
        BlocProvider<TabsBloc>.value(value: tabsBloc),
        BlocProvider<WorkspaceBloc>.value(value: workspace),
        BlocProvider<PluginSystemBloc>.value(value: plugins),
        BlocProvider<LibraryUpdateBloc>.value(value: libraryUpdate),
        BlocProvider<BookmarkBloc>.value(value: bookmarks),
        BlocProvider<PersonalNotesBloc>.value(value: notes),
        BlocProvider<CustomFoldersBloc>(
          create: (_) => CustomFoldersBloc(addLibraryEvent: (_) {}),
        ),
      ],
      child: app,
    ),
  );
}

class _FakeWindow implements AppWindowController, AppWindowGeometry {
  const _FakeWindow(this.id);

  @override
  final AppWindowId id;

  @override
  Future<void> center() async {}
  @override
  Future<void> close() async {}
  @override
  Future<void> quitApplication() async {}
  @override
  Future<void> focus() async {}
  @override
  Future<Rect> getBounds() async => Rect.zero;
  @override
  Future<bool> isFullScreen() async => false;
  @override
  Listenable get stateChanges => Listenable.merge(const []);
  @override
  Future<bool> isMaximized() async => false;
  @override
  Future<bool> isMinimized() async => false;
  @override
  Future<bool> isVisible() async => true;
  @override
  Future<void> maximize() async {}
  @override
  Future<void> minimize() async {}
  @override
  Future<void> setBounds(Rect bounds) async {}
  @override
  Future<void> setFullScreen(bool value) async {}
  @override
  Future<void> setMinimumSize(Size size) async {}
  @override
  Future<void> setProgressBar(double progress) async {}
  @override
  Future<void> setSize(Size size) async {}
  @override
  Future<void> setTitleBarStyle(
    TitleBarStyle style, {
    required bool windowButtonVisibility,
  }) async {}
  @override
  Future<void> show() async {}
  @override
  Future<void> startDragging() async {}
  @override
  Future<void> unmaximize() async {}
}

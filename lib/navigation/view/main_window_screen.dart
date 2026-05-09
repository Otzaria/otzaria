// לתחזוקת חיבור הסיור המודרך למסך הראשי ראו:
// docs/guided_tour_developer_guide.md

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:collection/collection.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/navigation/startup_indexing_decision.dart';
import 'package:otzaria/navigation/view/startup_work_gate.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/empty_library/empty_library_screen.dart';
import 'package:otzaria/empty_library/bloc/empty_library_bloc.dart';
import 'package:otzaria/find_ref/bloc/find_ref_bloc.dart';
import 'package:otzaria/find_ref/view/find_ref_dialog.dart';
import 'package:otzaria/find_ref/bloc/find_ref_event.dart';
import 'package:otzaria/find_ref/bloc/find_ref_state.dart';
import 'package:otzaria/library/models/library.dart' as library_model;
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/library/view/library_browser.dart';
import 'package:otzaria/tabs/reading_screen.dart';
import 'package:otzaria/text_book/view/text_book_screen.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/tools/tools_screen.dart';
import 'package:otzaria/shortcuts/keyboard_shortcuts.dart';
import 'dart:async';
import 'package:otzaria/update/my_update_widget.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
import 'package:otzaria/widgets/dialogs/ad_popup_dialog.dart';
import 'package:window_manager/window_manager.dart';
import 'package:otzaria/main.dart' show appWindowListener;
import 'package:otzaria/navigation/view/custom_title_bar.dart';
import 'package:otzaria/migration/sync/background_sync_initializer.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_state.dart';
import 'package:otzaria/widgets/layout/context_overlay_panel.dart';
import 'package:otzaria/work_status/work_status_cubit.dart';
import 'package:otzaria/work_status/work_status_item.dart';
import 'package:otzaria/work_status/work_status_overlay.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/file_sync/bloc/file_sync_bloc.dart';
import 'package:otzaria/file_sync/bloc/file_sync_event.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';
import 'package:otzaria/widgets/navigation/nav_rail_item.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart'
    show buildThemePayload;
import 'package:otzaria/core/external_activation_queue.dart';
import 'package:otzaria/core/external_activation_channel.dart';
import 'package:otzaria/core/external_uri_router.dart';
import 'package:otzaria/plugins/services/reader_location_tracker.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/tour/models/live_tip.dart';
import 'package:otzaria/tour/models/tour_step.dart';
import 'package:otzaria/tour/tour_target_keys.dart';
import 'package:otzaria/tour/view/tour_overlay_screen.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/navigation/open_book.dart';

class MainWindowScreen extends StatefulWidget {
  const MainWindowScreen({super.key});

  @override
  MainWindowScreenState createState() => MainWindowScreenState();
}

// Global key for accessing MoreScreen
final GlobalKey<ToolsScreenState> moreScreenKey = GlobalKey<ToolsScreenState>();
final GlobalKey<State<LibraryBrowser>> libraryBrowserKey =
    GlobalKey<State<LibraryBrowser>>();

class MainWindowScreenState extends State<MainWindowScreen>
    with TickerProviderStateMixin {
  // לא final: ה-controller נוצר מחדש בעת שינוי אוריינטציה
  // (ראה _handleOrientationChange) כדי למנוע מצב שבו pixel offset מהציר
  // הישן (vertical) מתפרש כעמוד שגוי בציר החדש (horizontal).
  late PageController pageController;
  late final CalendarCubit _calendarCubit;
  late final SettingsScreenController _settingsScreenController;
  final ExternalActivationQueue _externalActivationQueue =
      const ExternalActivationQueue();
  late final TourCubit _tourCubit;
  final ExternalActivationChannel _externalActivationChannel =
      ExternalActivationChannel();
  ReaderLocationTracker? _readerLocationTracker;
  Orientation? _previousOrientation;
  int _currentPageIndex = 0;

  // Keep the pages list as templates; the actual first page (library)
  // will be built dynamically in build() to allow showing the
  // EmptyLibraryScreen inside the library tab while keeping the
  // rest of the application UI available.
  List<Widget> _pages = [];

  // שמירת הדפים כדי שלא ייבנו מחדש
  Widget? _cachedLibraryPage;
  Widget? _cachedReadingPage;
  Widget? _cachedMorePage;
  Widget? _cachedSettingsPage;

  // שמירת BLoC של EmptyLibrary כדי שלא יאבד את המצב
  EmptyLibraryBloc? _emptyLibraryBloc;

  // שמירת מצב הספרייה הקודם כדי לזהות שינויים
  bool? _previousLibraryEmptyState;

  final StartupWorkGate _startupWorkGate = StartupWorkGate();
  final IndexingRepository _indexingRepository =
      IndexingRepository(TantivyDataProvider.instance);
  bool _hasCheckedAutoIndex = false;
  bool _isShowingStartupManualReindexDialog = false;
  bool _hasRestoredFullscreen = false;
  bool _hasStartedFileSync = false;
  bool _isSearchOpen = false;
  bool _isFindRefOpen = false;
  bool _isReadingSettingsPanelOpen = false;
  bool _openGenesisForTour = false;
  bool _tourStartedAutomaticallyThisLaunch = false;
  OverlayEntry? _tourOverlayEntry;
  bool _tourOverlayInsertScheduled = false;
  bool _tourOpenedOverflowMenu = false;
  bool _tourOpenedTabContextMenu = false;
  late Screen _lastScreen;
  // עוקב אחר מצב ההגדרות הקודם לצורך dispatch ספציפי
  SettingsState? _prevSettingsState;
  // עוקב אחר מצב הלוח הקודם לצורך dispatch ספציפי
  CalendarState? _prevCalendarState;

  bool _hasInitializedPageController = false;
  bool _isProcessingExternalActivations = false;
  StreamSubscription<FileSystemEvent>? _externalActivationWatchSub;
  StreamSubscription<String>? _externalActivationChannelSub;

  static const _navData = [
    (
      screen: Screen.library,
      icon: FluentIcons.library_24_regular,
      iconFilled: FluentIcons.library_24_filled,
      label: 'ספרייה',
      shortcutKey: 'key-shortcut-open-library-browser',
      shortcutDefault: 'ctrl+l',
    ),
    (
      screen: Screen.find,
      icon: FluentIcons.book_search_24_regular,
      iconFilled: FluentIcons.book_search_24_filled,
      label: 'איתור',
      shortcutKey: 'key-shortcut-open-find-ref',
      shortcutDefault: 'ctrl+o',
    ),
    (
      screen: Screen.reading,
      icon: FluentIcons.book_open_24_regular,
      iconFilled: FluentIcons.book_open_24_filled,
      label: 'עיון',
      shortcutKey: 'key-shortcut-open-reading-screen',
      shortcutDefault: 'ctrl+r',
    ),
    (
      screen: Screen.search,
      icon: FluentIcons.search_24_regular,
      iconFilled: FluentIcons.search_24_filled,
      label: 'חיפוש',
      shortcutKey: 'key-shortcut-open-new-search',
      shortcutDefault: 'ctrl+q',
    ),
    (
      screen: Screen.more,
      icon: FluentIcons.apps_24_regular,
      iconFilled: FluentIcons.apps_24_filled,
      label: 'כלים',
      shortcutKey: 'key-shortcut-open-more',
      shortcutDefault: 'ctrl+m',
    ),
    (
      screen: Screen.settings,
      icon: FluentIcons.settings_24_regular,
      iconFilled: FluentIcons.settings_24_filled,
      label: 'הגדרות',
      shortcutKey: 'key-shortcut-open-settings',
      shortcutDefault: 'ctrl+comma',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _calendarCubit = CalendarCubit();
    _settingsScreenController = SettingsScreenController();
    _tourCubit = TourCubit();
    _lastScreen = context.read<NavigationBloc>().state.currentScreen;

    // הצגת פופאפ פרסומת אחרי 5 שניות
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // אתחול tracker למעקב אחרי מיקום הקריאה
      if (mounted) {
        _readerLocationTracker = ReaderLocationTracker(
          tabsBloc: context.read<TabsBloc>(),
        );
      }

      unawaited(_initializeExternalActivationMonitoring());

      AdPopupDialog.showIfNeeded(
        context,
        shouldSkip: () => _tourStartedAutomaticallyThisLaunch,
      );

      // רענון plugin calendar events עם scope אמיתי לאחר שה-context מוכן.
      // הטעינה הראשונית ב-_initializeCalendar נקראה בלי workspace/book IDs —
      // כאן אנחנו מתקנים זאת עם ה-state שמזומן כעת.
      if (!mounted) return;
      try {
        final workspaceId =
            context.read<WorkspaceBloc>().state.activeWorkspaceId;
        final bookId = context.read<TabsBloc>().state.currentTab?.title;
        _calendarCubit.refreshPluginEvents(
          currentWorkspaceId: workspaceId,
          currentBookId: bookId,
        );
      } catch (_) {}
    });

    // Setup fullscreen sync with window manager
    _setupFullscreenSync();

    // Listen to calendar changes for plugin dispatch
    _calendarCubit.stream.listen((state) {
      PluginRuntimeDispatcher.instance.dispatchEvent('calendar.date_changed', {
        'date': state.selectedGregorianDate.toIso8601String(),
      });
    });

    // NOTE: Background sync is now triggered by LibraryBloc listener
    // (see MultiBlocListener) to avoid DB lock contention during library loading.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // אתחול PageController פעם אחת עם initialPage הנכון
    if (!_hasInitializedPageController) {
      _hasInitializedPageController = true;
      final initialScreen = context.read<NavigationBloc>().state.currentScreen;
      _currentPageIndex =
          _pageIndexForScreen(initialScreen) ?? Screen.library.index;
      pageController = PageController(initialPage: _currentPageIndex);
    }
  }

  /// Trigger FileSyncBloc to start syncing AFTER the library is loaded.
  /// Runs only once per app session (guard prevents re-triggering on RefreshLibrary).
  void _startFileSync() {
    if (_hasStartedFileSync) return;
    _hasStartedFileSync = true;

    final isAutoSync =
        Settings.getValue<bool>(SettingsRepository.keyAutoSync) ?? true;
    final settingsState = context.read<SettingsBloc>().state;
    if (isAutoSync && settingsState.canUseSoftwareAndBookUpdates) {
      try {
        context.read<FileSyncBloc>().add(const StartSync());
      } catch (e) {
        debugPrint('Could not start file sync: $e');
      }
    }
  }

  /// Initialize background file sync AFTER library is loaded.
  /// This avoids DB lock contention that caused 17s delays.
  void _initializeBackgroundSync() {
    BackgroundSyncInitializer.initializeAfterDelay(
      delaySeconds: 2, // Small delay to let UI settle after library load
      onComplete: (result) {
        if (!mounted) return;
        if (result.addedBooks > 0 ||
            result.updatedBooks > 0 ||
            result.addedLinks > 0) {
          debugPrint('📚 סנכרון קבצים הושלם: ${result.addedBooks} ספרים חדשים, '
              '${result.updatedBooks} עודכנו, ${result.addedLinks} קישורים');

          // Refresh the library browser to show new books
          try {
            context.read<LibraryBloc>().add(RefreshLibrary());
          } catch (e) {
            debugPrint('Could not refresh library: $e');
          }
        }
      },
    );
  }

  void _tryStartDeferredStartupWork() {
    if (!_startupWorkGate.consumeStartPermission()) {
      return;
    }

    _initializeBackgroundSync();
    _startFileSync();
  }

  /// Setup synchronization between window fullscreen state and settings
  void _setupFullscreenSync() {
    if (kIsWeb ||
        (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS)) {
      return;
    }

    // Listen for fullscreen changes from the window manager (e.g., user presses F11 in OS)
    appWindowListener?.onFullscreenChanged = (isFullscreen) {
      if (!mounted) return;
      final settingsBloc = context.read<SettingsBloc>();
      // Only update if the state is different to avoid loops
      if (settingsBloc.state.isFullscreen != isFullscreen) {
        settingsBloc.add(UpdateIsFullscreen(isFullscreen));
      }
    };

    // שחזור פוקוס לאחר אירועי מצב חלון דיסקרטיים (maximize/unmaximize/fullscreen/restore)
    appWindowListener?.onWindowStateChanged = () {
      if (!mounted) return;
      FocusRepository().scheduleRestore();
    };

    // שחזור פוקוס בזמן resize רציף — עם debounce כדי למנוע הצפת קריאות
    appWindowListener?.onWindowResizeOccurred = () {
      if (!mounted) return;
      FocusRepository().scheduleRestoreDebounced();
    };
  }

  /// Restore fullscreen state from settings when app starts
  Future<void> _restoreFullscreenState(BuildContext context) async {
    if (_hasRestoredFullscreen) return;
    _hasRestoredFullscreen = true;

    if (kIsWeb ||
        (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS)) {
      return;
    }

    final settingsState = context.read<SettingsBloc>().state;
    if (settingsState.isFullscreen) {
      await windowManager.setFullScreen(true);
    }
  }

  void _checkAndStartIndexing(BuildContext context) {
    // Only check once, after settings are loaded
    if (_hasCheckedAutoIndex) return;
    _hasCheckedAutoIndex = true;

    unawaited(_resolveStartupIndexing(context));
  }

  Future<void> _resolveStartupIndexing(BuildContext context) async {
    final autoUpdateIndex = context.read<SettingsBloc>().state.autoUpdateIndex;
    final library = await DataRepository.instance.library;
    if (!mounted || !context.mounted) {
      return;
    }

    final requiresManualReindex =
        await _indexingRepository.requiresManualReindex(library);
    if (!mounted || !context.mounted) {
      return;
    }

    final decision = decideStartupIndexing(
      requiresManualReindex: requiresManualReindex,
      autoUpdateIndex: autoUpdateIndex,
    );

    switch (decision) {
      case StartupIndexingDecision.autoReindexThenStart:
        await _indexingRepository.prepareForManualReindex(library);
        if (!mounted || !context.mounted) {
          return;
        }
        _startupWorkGate.markIndexingDecisionResolved(expectIndexing: true);
        _tryStartDeferredStartupWork();
        context.read<IndexingBloc>().add(StartIndexing(library));
        return;
      case StartupIndexingDecision.promptManualReindex:
        _startupWorkGate.markIndexingDecisionResolved(expectIndexing: false);
        _tryStartDeferredStartupWork();
        await _showStartupManualReindexDialog(context, library);
        return;
      case StartupIndexingDecision.startIndexing:
        _startupWorkGate.markIndexingDecisionResolved(expectIndexing: true);
        _tryStartDeferredStartupWork();
        context.read<IndexingBloc>().add(StartIndexing(library));
        return;
      case StartupIndexingDecision.checkIndexStatus:
        _startupWorkGate.markIndexingDecisionResolved(expectIndexing: false);
        _tryStartDeferredStartupWork();
        context.read<IndexingBloc>().add(CheckIndexStatus(library));
        return;
    }
  }

  Future<void> _showStartupManualReindexDialog(
    BuildContext context,
    library_model.Library library,
  ) async {
    if (_isShowingStartupManualReindexDialog) {
      return;
    }

    _isShowingStartupManualReindexDialog = true;
    final indexingBloc = context.read<IndexingBloc>();
    try {
      final result = await showTwoActionsDialog(
        context: context,
        title: 'נדרש איפוס אינדקס',
        content:
            'האינדקס הקיים אינו מעודכן ביחס לשינויים האחרונים בחיפוש. עד שתבצע איפוס ואינדוקס מחדש, ייתכן שחלק מיכולות החיפוש לא יעבדו כראוי.',
        cancelText: 'אחר כך',
        confirmText: 'אפס ועדכן',
      );
      if (!mounted || !context.mounted || result != true) {
        return;
      }

      await _indexingRepository.prepareForManualReindex(library);
      if (!mounted || !context.mounted) {
        return;
      }

      _startupWorkGate.markIndexingDecisionResolved(expectIndexing: true);
      indexingBloc.add(StartIndexing(library));
    } finally {
      _isShowingStartupManualReindexDialog = false;
    }
  }

  void _startIndexing(BuildContext context) {
    DataRepository.instance.library.then((library) {
      if (!mounted || !context.mounted) return;
      context.read<IndexingBloc>().add(StartIndexing(library));
    });
  }

  Future<void> _processPendingExternalActivations() async {
    if (!mounted || _isProcessingExternalActivations) {
      return;
    }

    _isProcessingExternalActivations = true;
    try {
      final pendingUris = await _externalActivationQueue.drainUriStrings();
      for (final uriString in pendingUris) {
        await _handleExternalActivationUriString(uriString);
      }
    } catch (e, stackTrace) {
      debugPrint('External activation polling failed: $e\n$stackTrace');
    } finally {
      _isProcessingExternalActivations = false;
    }
  }

  Future<void> _initializeExternalActivationMonitoring() async {
    await _externalActivationChannel.initialize();
    await _externalActivationChannelSub?.cancel();
    _externalActivationChannelSub =
        _externalActivationChannel.uriStrings.listen((uriString) {
      unawaited(_handleExternalActivationUriString(uriString));
    });

    final pendingPlatformUris =
        await _externalActivationChannel.takePendingUriStrings();
    for (final uriString in pendingPlatformUris) {
      await _handleExternalActivationUriString(uriString);
    }

    final queuePath = await _externalActivationQueue.resolveQueueFilePath();
    final queueFile = File(queuePath);
    await queueFile.parent.create(recursive: true);

    await _externalActivationWatchSub?.cancel();
    _externalActivationWatchSub = queueFile.parent.watch().listen(
      (event) {
        final normalizedPath = event.path.replaceAll('\\', '/');
        final normalizedQueuePath = queuePath.replaceAll('\\', '/');
        if (normalizedPath != normalizedQueuePath) {
          return;
        }

        unawaited(_processPendingExternalActivations());
      },
      onError: (error, stackTrace) {
        debugPrint(
          'External activation watch failed: $error\n$stackTrace',
        );
      },
    );

    await _processPendingExternalActivations();
  }

  Future<void> _handleExternalActivationUriString(String uriString) async {
    if (!mounted) {
      return;
    }

    try {
      final uri = Uri.tryParse(uriString);
      if (uri == null) return;

      final action = ExternalUriRouter.parseUri(uri);
      if (action == null) return;

      await _bringWindowToFront();
      if (!mounted) return;
      _dispatchExternalUriAction(action);
    } catch (e, stackTrace) {
      debugPrint(
        'Failed to process external activation "$uriString": $e\n$stackTrace',
      );
    }
  }

  Future<void> _bringWindowToFront() async {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      await windowManager.show();
      await windowManager.focus();
    }
  }

  void _dispatchExternalUriAction(ExternalUriAction action) {
    switch (action) {
      case OpenScreenAction(:final screen):
        context.read<NavigationBloc>().add(NavigateToScreen(screen));
      case OpenToolAction(:final toolId):
        context.read<NavigationBloc>().add(const NavigateToScreen(Screen.more));
        // ToolsScreen נבנה lazy בעת המעבר ל־Screen.more, ולכן ייתכן
        // ש־moreScreenKey.currentState עדיין null בפריים הראשון. ניסיונות חוזרים
        // עם hop קצר מבטיחים שהלשונית תיפתח גם בפעם הראשונה שנכנסים אליה.
        _openToolWhenAvailable(toolId);
      case OpenBookAction(:final bookId, :final index, :final searchQuery):
        unawaited(_openBookByExternalId(
          bookId,
          index: index,
          searchQuery: searchQuery,
        ));
      case InstallPluginAction(:final request):
        context.read<NavigationBloc>().add(const NavigateToScreen(Screen.more));
        context.read<PluginSystemBloc>().add(
              InstallRemotePluginRequested(
                request.downloadUri.toString(),
                forceOverwrite: request.forceOverwrite,
              ),
            );
      case RunSearchAction(:final query):
        _runExternalSearch(query);
    }
  }

  void _runExternalSearch(String query) {
    final tab = SearchingTab(SearchingTab.titleForQuery(query), query);
    context.read<HistoryBloc>().add(AddHistory(tab));
    context.read<TabsBloc>().add(AddTab(tab));
    context.read<NavigationBloc>().add(const NavigateToScreen(Screen.search));
    // ה-UpdateSearchQuery נשלח אוטומטית מ-TantivyFullTextSearch.initState
    // ברגע שהלשונית מוצגת לראשונה. ראה tantivy_full_text_search.dart:130-134.
  }

  Future<void> _openBookByExternalId(
    int bookId, {
    int? index,
    String? searchQuery,
  }) async {
    final library = await DataRepository.instance.library;
    if (!mounted) return;
    final book = library.getAllBooks().firstWhereOrNull((b) => b.id == bookId);
    if (book == null) {
      UiSnack.showError('הספר עם המזהה $bookId לא נמצא בספרייה');
      return;
    }
    openBook(context, book, index ?? 0, searchQuery ?? '');
  }

  void _openToolWhenAvailable(String toolId, {int attemptsLeft = 6}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final toolsState = moreScreenKey.currentState;
      if (toolsState != null) {
        toolsState.requestOpenTool(toolId);
        return;
      }
      if (attemptsLeft <= 0) return;
      Future<void>.delayed(const Duration(milliseconds: 50), () {
        if (!mounted) return;
        _openToolWhenAvailable(toolId, attemptsLeft: attemptsLeft - 1);
      });
    });
  }

  @override
  void dispose() {
    // Clean up fullscreen callback
    appWindowListener?.onFullscreenChanged = null;
    appWindowListener?.onWindowStateChanged = null;
    appWindowListener?.onWindowResizeOccurred = null;
    _externalActivationWatchSub?.cancel();
    _externalActivationChannelSub?.cancel();
    _externalActivationChannel.dispose();
    _calendarCubit.close();
    _removeTourOverlay();
    _tourCubit.close();
    _emptyLibraryBloc?.close();
    _readerLocationTracker?.dispose();
    pageController.dispose();
    super.dispose();
  }

  void _handleOrientationChange(BuildContext context, Orientation orientation) {
    if (_previousOrientation == orientation) return;

    final isFirstDetection = _previousOrientation == null;
    _previousOrientation = orientation;
    if (isFirstDetection) return;

    // החלפת ציר ב-PageView (vertical↔horizontal) משבשת את חישוב העמוד
    // הפנימי של PageController: ה-pixel offset נשמר אבל ה-viewport
    // dimension משתנה (height→width), ולכן הנוסחה offset/viewport
    // מקפיצה את העמוד הפעיל. התוצאה: עמוד 1 (מסך עיון) מוצג רגעית מעל
    // המסך הנוכחי, ושאר המסכים נכפים ל-dispose ואז init מחדש (ראה למשל
    // ShamorZachorWidget בלוגים).
    //
    // הפתרון: יוצרים PageController חדש *סינכרונית* לפני בניית ה-PageView
    // החדש (בציר החדש). ה-PageView שייבנה מיד אחרי הקריאה הזו ישתמש
    // ב-controller החדש עם initialPage תקין, בלי offset יורש מהציר הקודם.
    final currentScreen = context.read<NavigationBloc>().state.currentScreen;
    final targetPage = _pageIndexForScreen(currentScreen) ?? _currentPageIndex;
    _currentPageIndex = targetPage;

    final oldController = pageController;
    pageController = PageController(initialPage: targetPage);

    // dispose נדחה לפוסט-פריים: ה-PageView הישן עדיין מחובר ל-oldController
    // עד שתסתיים הרקונסיליאציה של עץ הווידג'טים בפריים הזה.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldController.dispose();
    });
  }

  void _toggleReadingSettingsPanel() {
    setState(() {
      _isReadingSettingsPanelOpen = !_isReadingSettingsPanelOpen;
    });
  }

  /// ודאו שה-PageView מסונכרן למצב הניווט הנוכחי גם אם בחרו שוב באותו יעד.
  Future<void> _syncPageWithState() async {
    if (!mounted || !pageController.hasClients) return;
    final currentScreen = context.read<NavigationBloc>().state.currentScreen;
    final targetPage = _pageIndexForScreen(currentScreen);
    if (targetPage == null) return;
    if (_currentPageIndex == targetPage) return;

    setState(() {
      _currentPageIndex = targetPage;
    });
    pageController.jumpToPage(targetPage);
  }

  List<NavigationDestination> _buildNavigationDestinations() {
    return [
      for (final item in _navData)
        NavigationDestination(
          tooltip: '',
          icon: Tooltip(
            preferBelow: false,
            message: (Settings.getValue<String>(item.shortcutKey) ??
                    item.shortcutDefault)
                .toUpperCase(),
            child: Icon(item.icon),
          ),
          selectedIcon: Icon(item.iconFilled),
          label: item.label,
        ),
    ];
  }

  void _handleNavigationChange(
    BuildContext context,
    NavigationState state,
  ) async {
    if (!mounted || !context.mounted) return;

    if (state.currentScreen != _lastScreen) {
      if (_lastScreen == Screen.library) {
        final libraryState = libraryBrowserKey.currentState;
        if (libraryState != null) {
          (libraryState as dynamic).closeTransientPanels();
        }
      } else if (_lastScreen == Screen.more) {
        moreScreenKey.currentState?.closeTransientPanels();
      }
      _lastScreen = state.currentScreen;
    }

    final targetPage = _pageIndexForScreen(state.currentScreen);
    if (targetPage != null && _currentPageIndex != targetPage) {
      setState(() {
        _currentPageIndex = targetPage;
      });
      if (pageController.hasClients) {
        pageController.animateToPage(
          targetPage,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }

    if (state.currentScreen == Screen.library) {
      context.read<FocusRepository>().requestLibrarySearchFocus(
            selectAll: true,
          );
    } else if (state.currentScreen == Screen.more) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<FocusRepository>().requestMoreScreenFocus();
        }
      });
    } else if (state.currentScreen == Screen.reading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<FocusRepository>().requestBookContentFocus();
        }
      });
    } else if (state.currentScreen == Screen.settings) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<FocusRepository>().requestSettingsFocus();
        }
      });
    } else if (state.currentScreen == Screen.find) {
      // find_ref_dialog registers its own restorer on open
      context.read<FocusRepository>().requestFindRefSearchFocus();
    } else if (state.currentScreen == Screen.search) {
      // TantivyFullTextSearch listens to NavigationBloc and registers
      // itself via setScreenRestorer in _requestSearchFieldFocus.
      // No extra action needed here.
    }
  }

  void _handleTourStepChanged(TourStep step) {
    // סגירת חלוניות איתור/חיפוש בכל מעבר שלב, למעט כאשר השלב החדש דורש פתיחה
    final shouldOpenFindRef = step.action == TourStepAction.openFindRef;
    final shouldOpenSearch = step.action == TourStepAction.openSearch;
    if (!shouldOpenFindRef && _isFindRefOpen) {
      Navigator.of(context, rootNavigator: true).maybePop();
    }
    if (!shouldOpenSearch && _isSearchOpen) {
      Navigator.of(context, rootNavigator: true).maybePop();
    }

    switch (step.action) {
      case TourStepAction.openLibrary:
        context.read<NavigationBloc>().add(
              const NavigateToScreen(Screen.library),
            );
      case TourStepAction.openLibraryHome:
        context.read<NavigationBloc>().add(
              const NavigateToScreen(Screen.library),
            );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          (libraryBrowserKey.currentState as dynamic).navigateHome();
        });
      case TourStepAction.openLibraryBookPreview:
        context.read<NavigationBloc>().add(
              const NavigateToScreen(Screen.library),
            );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final libraryState = libraryBrowserKey.currentState;
          if (libraryState != null) {
            (libraryState as dynamic).prepareTourBookPreview();
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _tourOverlayEntry?.markNeedsBuild();
            _scheduleTourTargetRebuilds(remainingFrames: 6);
          });
        });
      case TourStepAction.openReading:
        context.read<NavigationBloc>().add(
              const NavigateToScreen(Screen.reading),
            );
        if (_openGenesisForTour) {
          _openGenesisForTour = false;
          _openTourGenesisInReader();
        }
        if (step.id == 'toc') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final tocContext = textBookNavigationTourTargetKey.currentContext;
            if (tocContext != null && tocContext.mounted) {
              tocContext.read<TextBookBloc>().add(const ToggleLeftPane(true));
            }
          });
        }
      case TourStepAction.openTools:
        context.read<NavigationBloc>().add(
              const NavigateToScreen(Screen.more),
            );
        _scheduleTourToolTabForStep(step);
      case TourStepAction.openSettings:
        context.read<NavigationBloc>().add(
              const NavigateToScreen(Screen.settings),
            );
      case TourStepAction.openDesignSettings:
        _settingsScreenController.openTab(SettingsTab.design);
        context.read<NavigationBloc>().add(
              const NavigateToScreen(Screen.settings),
            );
      case TourStepAction.openSystemSettings:
        _settingsScreenController.openTab(SettingsTab.system);
        context.read<NavigationBloc>().add(
              const NavigateToScreen(Screen.settings),
            );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final ctx = tourBackupSettingsTargetKey.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(
              ctx,
              duration: const Duration(milliseconds: 200),
              alignment: 0.3,
            );
          }
          _scheduleTourTargetRebuilds(remainingFrames: 15);
        });
      case TourStepAction.openShortcutsSettings:
        _settingsScreenController.openTab(SettingsTab.shortcuts);
        context.read<NavigationBloc>().add(
              const NavigateToScreen(Screen.settings),
            );
        _scheduleTourTargetRebuilds(remainingFrames: 4);
      case TourStepAction.openFindRef:
        _openGenesisForTour = true;
        _openTourFindRef();
      case TourStepAction.openSearch:
        _handleSearchTabOpen(context, closeIfOpen: false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _bringTourOverlayToFront();
        });
      case TourStepAction.none:
        break;
    }
    _scheduleTourOverflowMenuForStep(step);
    _scheduleTourTabContextMenuForStep(step);
    _scheduleTourTargetRebuilds(remainingFrames: 4);
  }

  void _scheduleTourOverlayInsert() {
    if (_tourOverlayInsertScheduled) {
      return;
    }
    _tourOverlayInsertScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tourOverlayInsertScheduled = false;
      if (!mounted) {
        return;
      }
      _ensureTourOverlay();
    });
  }

  void _ensureTourOverlay() {
    if (_tourOverlayEntry != null) {
      return;
    }
    final overlay = Navigator.of(context, rootNavigator: true).overlay;
    if (overlay == null) {
      return;
    }
    _tourOverlayEntry = OverlayEntry(
      builder: (context) => BlocProvider.value(
        value: _tourCubit,
        child: TourOverlayScreen(
          onStepChanged: _handleTourStepChanged,
          onNext: _handleTourNext,
          targetRectResolver: _resolveTourTargetRect,
          targetRectsResolver: _resolveTourTargetRects,
        ),
      ),
    );
    overlay.insert(_tourOverlayEntry!);
  }

  void _bringTourOverlayToFront() {
    final overlay = Navigator.of(context, rootNavigator: true).overlay;
    final entry = _tourOverlayEntry;
    if (overlay == null || entry == null) {
      return;
    }
    entry.remove();
    overlay.insert(entry);
  }

  void _scheduleBringTourOverlayToFront({required int remainingFrames}) {
    if (remainingFrames <= 0) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _bringTourOverlayToFront();
      _tourOverlayEntry?.markNeedsBuild();
      _scheduleBringTourOverlayToFront(
        remainingFrames: remainingFrames - 1,
      );
    });
  }

  void _removeTourOverlay() {
    _tourOverlayEntry?.remove();
    _tourOverlayEntry?.dispose();
    _tourOverlayEntry = null;
  }

  void _handleTourNext(TourStep step) {
    if (step.id == 'find_ref') {
      _openFirstTourFindRefResult();
      return;
    }
    if (step.id == 'advanced_search') {
      if (_isSearchOpen) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _closeTourOverflowMenuIfNeeded();
      _closeTourTabContextMenuIfNeeded();
      _tourCubit.next();
      return;
    }
    _closeTourOverflowMenuIfNeeded();
    _closeTourTabContextMenuIfNeeded();
    _tourCubit.next();
  }

  void _scheduleTourToolTabForStep(TourStep step) {
    final toolId = switch (step.id) {
      'calendar' => 'builtin.calendar',
      'gematria' => 'builtin.gematria',
      'notes' => 'builtin.notes',
      _ => null,
    };
    if (toolId == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      moreScreenKey.currentState?.requestOpenTool(toolId);
      _scheduleTourTargetRebuilds(remainingFrames: 4);
    });
  }

  void _scheduleTourOverflowMenuForStep(TourStep step) {
    if (!_usesReadingOverflowMenu(step.area)) {
      _closeTourOverflowMenuIfNeeded();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _directReadingTourTargetRect(step.area) != null) {
        _closeTourOverflowMenuIfNeeded();
        return;
      }
      _openReadingOverflowMenuForTour();
    });
  }

  bool _usesReadingOverflowMenu(TourSpotlightArea area) {
    return area == TourSpotlightArea.commentators ||
        area == TourSpotlightArea.bookmark ||
        area == TourSpotlightArea.bookSearch ||
        area == TourSpotlightArea.print;
  }

  void _openReadingOverflowMenuForTour() {
    final state = (textBookOverflowTourTargetKey.currentState ??
        pdfBookOverflowTourTargetKey.currentState) as dynamic;
    if (state == null) {
      return;
    }
    state?.showMenu();
    _tourOpenedOverflowMenu = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _bringTourOverlayToFront();
      _scheduleTourTargetRebuilds(remainingFrames: 3);
    });
  }

  void _closeTourOverflowMenuIfNeeded() {
    if (!_tourOpenedOverflowMenu) {
      return;
    }
    _tourOpenedOverflowMenu = false;
    Navigator.of(context, rootNavigator: true).maybePop();
  }

  void _scheduleTourTabContextMenuForStep(TourStep step) {
    if (step.area != TourSpotlightArea.sideBySide) {
      _closeTourTabContextMenuIfNeeded();
      return;
    }
    unawaited(_openTourSideBySideContextMenu());
  }

  Future<void> _openTourSideBySideContextMenu() async {
    await _ensureTourSideBySideCandidates();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (tourTabContextMenuTargetKey.currentState as dynamic)?.showMenu();
      _tourOpenedTabContextMenu = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _bringTourOverlayToFront();
        _scheduleTourTargetRebuilds(remainingFrames: 4);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          (tourTabSideBySideMenuItemTargetKey.currentState as dynamic)
              ?.openSubmenu(() {
            if (!mounted) return;
            _scheduleTourTargetRebuilds(remainingFrames: 4);
          });
        });
      });
    });
  }

  void _closeTourTabContextMenuIfNeeded() {
    if (!_tourOpenedTabContextMenu) {
      return;
    }
    _tourOpenedTabContextMenu = false;
    final state = tourTabContextMenuTargetKey.currentState as dynamic;
    state?.closeMenu();
  }

  Future<void> _ensureTourSideBySideCandidates() async {
    final tabsState = context.read<TabsBloc>().state;
    final readableTabs = tabsState.tabs.where((tab) => tab is! CombinedTab);
    if (readableTabs.length >= 2) {
      return;
    }
    await _openTourBookByTitle('שמות');
  }

  void _openTourFindRef() {
    final focusRepository = context.read<FocusRepository>();
    focusRepository.findRefSearchController.text = 'בראשית';
    focusRepository.findRefSearchController.selection =
        const TextSelection.collapsed(offset: 'בראשית'.length);
    context.read<FindRefBloc>().add(const SearchRefRequested('בראשית'));
    _handleFindRefOpen(
      context,
      closeIfOpen: false,
      transparentBarrier: true,
    );
    _scheduleBringTourOverlayToFront(remainingFrames: 6);
  }

  Future<void> _openFirstTourFindRefResult() async {
    final findRefState = context.read<FindRefBloc>().state;
    if (findRefState is! FindRefSuccess || findRefState.refs.isEmpty) {
      return;
    }

    final ref = findRefState.refs.first;
    Book? book;
    try {
      final library = await DataRepository.instance.library;
      book = _findBookByTitle(library, ref.title);
    } catch (e) {
      debugPrint('Error searching library: $e');
    }

    if (!mounted) {
      return;
    }

    book ??= ref.isPdf
        ? PdfBook(title: ref.title, path: ref.filePath)
        : TextBook(title: ref.title);

    _openGenesisForTour = false;
    if (_isFindRefOpen) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    // סגירת טאבי TextBook קיימים כדי למנוע כפילות GlobalKeys
    _closeExistingTextBookTabsForTour();
    final frameCompleter = Completer<void>();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => frameCompleter.complete());
    await frameCompleter.future;
    if (!mounted) return;
    openBook(context, book, ref.segment.toInt(), '', ignoreHistory: true);
    if (_tourCubit.state.currentStep?.id == 'find_ref') {
      await _tourCubit.next();
    }
  }

  Rect? _resolveTourTargetRect(TourStep step) {
    final exactRect = _exactTourTargetRect(step);
    if (exactRect != null) {
      return exactRect;
    }
    if (_usesReadingOverflowMenu(step.area)) {
      return _readingTourTargetRect(step.area);
    }
    if (step.area != TourSpotlightArea.bookCard) {
      return null;
    }
    final libraryState = libraryBrowserKey.currentState;
    if (libraryState == null) {
      return null;
    }
    return (libraryState as dynamic).tourBookCardRect() as Rect?;
  }

  Rect? _exactTourTargetRect(TourStep step) {
    switch (step.id) {
      case 'navigation':
        return _combinedRectForKeys(tourMainNavigationTargetKeys);
      case 'library':
        return _libraryTourRect('tourLibraryRect');
      case 'library_search':
        return _libraryTourRect('tourLibrarySearchRect');
      case 'categories':
        return _libraryTourRect('tourLibraryCategoriesRect');
      case 'advanced_search':
        return _rectForGlobalKey(tourSearchDialogTargetKey);
      case 'find_ref':
        return _findRefDialogTourRect();
      case 'reading':
        return _rectForGlobalKey(tourReadingScreenTargetKey);
      case 'tabs':
        return _tabsTourTargetRect();
      case 'reading_settings':
        return _rectForGlobalKey(tourReadingSettingsButtonTargetKey);
      case 'tools':
        return _navItemTourRectForScreen(Screen.more);
      case 'calendar':
        return _rectForGlobalKey(tourToolTabTargetKeys['builtin.calendar']!);
      case 'gematria':
        return _rectForGlobalKey(tourToolTabTargetKeys['builtin.gematria']!);
      case 'notes':
        return _rectForGlobalKey(tourToolTabTargetKeys['builtin.notes']!);
      case 'settings':
        return _navItemTourRectForScreen(Screen.settings);
      case 'appearance':
        return _rectForGlobalKey(tourSettingsTabTargetKeys[0]!);
      case 'backup':
        return _rectForGlobalKey(tourBackupSettingsTargetKey) ??
            _rectForGlobalKey(tourSettingsTabTargetKeys[5]!);
      case 'shortcuts':
        return _rectForGlobalKey(tourShortcutsSettingsTargetKey) ??
            _rectForGlobalKey(tourSettingsTabTargetKeys[4]!);
    }

    if (step.id == 'toc') {
      return _rectForGlobalKey(textBookNavigationTourTargetKey) ??
          _rectForGlobalKey(pdfBookNavigationTourTargetKey);
    }

    return switch (step.area) {
      TourSpotlightArea.tableOfContents =>
        _rectForGlobalKey(textBookNavigationTourTargetKey) ??
            _rectForGlobalKey(pdfBookNavigationTourTargetKey),
      _ => null,
    };
  }

  List<Rect> _resolveTourTargetRects(TourStep step) {
    if (step.area == TourSpotlightArea.sideBySide) {
      final tabRect = _rectForGlobalKey(tourTabContextMenuTargetKey);
      final menuItemRect =
          _rectForGlobalKey(tourTabSideBySideMenuItemTargetKey);
      final firstSubitemRect =
          _rectForGlobalKey(tourTabSideBySideFirstItemTargetKey);
      return [
        if (tabRect != null) tabRect,
        if (menuItemRect != null) menuItemRect,
        if (firstSubitemRect != null) firstSubitemRect,
      ];
    }

    if (step.id == 'backup') {
      final contentRect = _rectForGlobalKey(tourBackupSettingsTargetKey);
      final tabRect = _rectForGlobalKey(tourSettingsTabTargetKeys[5]!);
      return [
        if (contentRect != null) contentRect,
        if (tabRect != null) tabRect,
      ];
    }

    if (step.id == 'shortcuts') {
      final contentRect = _rectForGlobalKey(tourShortcutsSettingsTargetKey);
      final tabRect = _rectForGlobalKey(tourSettingsTabTargetKeys[4]!);
      return [
        if (contentRect != null) contentRect,
        if (tabRect != null) tabRect,
      ];
    }

    if (step.id == 'advanced_search') {
      final dialogRect = _rectForGlobalKey(tourSearchDialogTargetKey);
      final navSearchRect = _navItemTourRectForScreen(Screen.search);
      return [
        if (dialogRect != null) dialogRect,
        if (navSearchRect != null) navSearchRect,
      ];
    }

    if (step.id == 'find_ref') {
      final dialogRect = _findRefDialogTourRect();
      final navFindRefRect = _navItemTourRectForScreen(Screen.find);
      return [
        if (dialogRect != null) dialogRect,
        if (navFindRefRect != null) navFindRefRect,
      ];
    }

    if (step.id == 'toc') {
      final buttonRect = _rectForGlobalKey(textBookNavigationTourTargetKey) ??
          _rectForGlobalKey(pdfBookNavigationTourTargetKey);
      final panelRect = _rectForGlobalKey(textBookNavPanelTourTargetKey);
      return [
        if (buttonRect != null) buttonRect,
        if (panelRect != null) panelRect,
      ];
    }

    if (step.id == 'bookmark') {
      final titleBarHistoryRect =
          _rectForGlobalKey(tourTitleBarHistoryButtonTargetKey);
      final titleBarBookmarkRect =
          _rectForGlobalKey(tourTitleBarBookmarkButtonTargetKey);
      final directRect = _directReadingTourTargetRect(step.area);
      if (directRect != null) {
        return [
          directRect,
          if (titleBarHistoryRect != null) titleBarHistoryRect,
          if (titleBarBookmarkRect != null) titleBarBookmarkRect,
        ];
      }
      final overflowRect = _rectForGlobalKey(textBookOverflowTourTargetKey) ??
          _rectForGlobalKey(pdfBookOverflowTourTargetKey);
      final menuItemRect = _readingOverflowMenuItemRect(step.area);
      return [
        if (overflowRect != null) overflowRect,
        if (menuItemRect != null) menuItemRect,
        if (titleBarHistoryRect != null) titleBarHistoryRect,
        if (titleBarBookmarkRect != null) titleBarBookmarkRect,
      ];
    }

    if (!_usesReadingOverflowMenu(step.area)) {
      final rect = _resolveTourTargetRect(step);
      return rect == null ? const [] : [rect];
    }

    final directRect = _directReadingTourTargetRect(step.area);
    if (directRect != null) {
      return [directRect];
    }

    final overflowRect = _rectForGlobalKey(textBookOverflowTourTargetKey) ??
        _rectForGlobalKey(pdfBookOverflowTourTargetKey);
    final menuItemRect = _readingOverflowMenuItemRect(step.area);
    return [
      if (overflowRect != null) overflowRect,
      if (menuItemRect != null) menuItemRect,
    ];
  }

  Rect? _readingTourTargetRect(TourSpotlightArea area) {
    final directRect = _directReadingTourTargetRect(area);
    if (directRect != null) {
      return directRect;
    }

    final overflowRect = _rectForGlobalKey(textBookOverflowTourTargetKey) ??
        _rectForGlobalKey(pdfBookOverflowTourTargetKey);
    final menuItemRect = _readingOverflowMenuItemRect(area);

    if (overflowRect != null && menuItemRect != null) {
      return overflowRect.expandToInclude(menuItemRect);
    }
    return menuItemRect ?? overflowRect;
  }

  Rect? _directReadingTourTargetRect(TourSpotlightArea area) {
    return switch (area) {
      TourSpotlightArea.commentators =>
        _rectForGlobalKey(textBookCommentatorsTourTargetKey),
      TourSpotlightArea.bookmark =>
        _rectForGlobalKey(textBookBookmarkTourTargetKey) ??
            _rectForGlobalKey(pdfBookBookmarkTourTargetKey),
      TourSpotlightArea.bookSearch =>
        _rectForGlobalKey(textBookSearchTourTargetKey) ??
            _rectForGlobalKey(pdfBookSearchTourTargetKey),
      TourSpotlightArea.print =>
        _rectForGlobalKey(textBookPrintTourTargetKey) ??
            _rectForGlobalKey(pdfBookPrintTourTargetKey),
      _ => null,
    };
  }

  Rect? _readingOverflowMenuItemRect(TourSpotlightArea area) {
    return switch (area) {
      TourSpotlightArea.commentators =>
        _rectForGlobalKey(textBookOverflowCommentatorsTourTargetKey),
      TourSpotlightArea.bookmark =>
        _rectForGlobalKey(textBookOverflowBookmarkTourTargetKey) ??
            _rectForGlobalKey(pdfBookOverflowBookmarkTourTargetKey),
      TourSpotlightArea.bookSearch =>
        _rectForGlobalKey(textBookOverflowSearchTourTargetKey) ??
            _rectForGlobalKey(pdfBookOverflowSearchTourTargetKey),
      TourSpotlightArea.print =>
        _rectForGlobalKey(textBookOverflowPrintTourTargetKey) ??
            _rectForGlobalKey(pdfBookOverflowPrintTourTargetKey),
      _ => null,
    };
  }

  Rect? _libraryTourRect(String methodName) {
    final libraryState = libraryBrowserKey.currentState;
    if (libraryState == null) {
      return null;
    }
    final dynamic state = libraryState;
    return switch (methodName) {
      'tourLibraryRect' => state.tourLibraryRect() as Rect?,
      'tourLibrarySearchRect' => state.tourLibrarySearchRect() as Rect?,
      'tourLibraryCategoriesRect' => state.tourLibraryCategoriesRect() as Rect?,
      _ => null,
    };
  }

  Rect? _combinedRectForKeys(Iterable<GlobalKey> keys) {
    Rect? combined;
    for (final key in keys) {
      final rect = _rectForGlobalKey(key);
      if (rect == null) continue;
      combined = combined == null ? rect : combined.expandToInclude(rect);
    }
    return combined;
  }

  Rect? _tabsTourTargetRect() {
    final rect = _rectForGlobalKey(tourReadingTabsTargetKey, inflate: 0);
    if (rect == null) {
      return null;
    }
    final settingsState = context.read<SettingsBloc>().state;
    if (settingsState.alignTabsToRight) {
      return Rect.fromLTRB(
          rect.left - 36, rect.top - 4, rect.right, rect.bottom + 4);
    }
    return Rect.fromLTRB(
      rect.left - 28,
      rect.top - 4,
      rect.right + 28,
      rect.bottom + 4,
    );
  }

  Rect? _findRefDialogTourRect() {
    final contentRect =
        _rectForGlobalKey(tourFindRefDialogTargetKey, inflate: 0);
    if (contentRect == null) {
      return null;
    }
    return Rect.fromLTRB(
      contentRect.left - 24,
      contentRect.top - 80,
      contentRect.right + 24,
      contentRect.bottom + 88,
    );
  }

  Rect? _navItemTourRect(int index) {
    if (index < 0 || index >= tourMainNavigationItemTargetKeys.length) {
      return null;
    }
    return _rectForGlobalKey(
      tourMainNavigationItemTargetKeys[index],
      inflate: 2,
    );
  }

  Rect? _navItemTourRectForScreen(Screen screen) {
    return _navItemTourRect(_navIndexForScreen(screen));
  }

  int _navIndexForScreen(Screen screen) {
    return _navData.indexWhere((item) => item.screen == screen);
  }

  Rect? _rectForGlobalKey(GlobalKey key, {double inflate = 4}) {
    final context = key.currentContext;
    if (context == null || !context.mounted) {
      return null;
    }
    // findRenderObject() can throw in debug mode if the element deactivates
    // between the mounted check and the layout callback — a Flutter-internal
    // race that context.mounted alone cannot prevent.
    RenderObject? renderObject;
    try {
      renderObject = context.findRenderObject();
    } catch (_) {
      return null;
    }
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return null;
    }
    final topLeft = renderObject.localToGlobal(Offset.zero);
    return (topLeft & renderObject.size).inflate(inflate);
  }

  void _scheduleTourTargetRebuilds({required int remainingFrames}) {
    if (remainingFrames <= 0) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _tourOverlayEntry?.markNeedsBuild();
      _scheduleTourTargetRebuilds(remainingFrames: remainingFrames - 1);
    });
  }

  Future<void> _openTourGenesisInReader() async {
    _closeExistingTextBookTabsForTour();
    // Wait for the old TextBookScreen to fully deactivate before mounting a new
    // one with the same tour GlobalKeys — avoids "Duplicate GlobalKeys" assertion
    // and the resulting layout mutations during _RenderLayoutBuilder.performLayout.
    final frameCompleter = Completer<void>();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => frameCompleter.complete());
    await frameCompleter.future;
    if (!mounted) return;
    try {
      final library = await DataRepository.instance.library;
      final book = _findBookByTitle(library, 'בראשית') ??
          TextBook(title: 'בראשית', fileType: 'txt');
      if (!mounted) return;
      openBook(context, book, 0, '', ignoreHistory: true);
    } catch (_) {
      if (!mounted) return;
      openBook(
        context,
        TextBook(title: 'בראשית', fileType: 'txt'),
        0,
        '',
        ignoreHistory: true,
      );
    }
  }

  void _closeExistingTextBookTabsForTour() {
    final tabsBloc = context.read<TabsBloc>();
    final tabsToClose = tabsBloc.state.tabs.whereType<TextBookTab>().toList();
    for (final tab in tabsToClose) {
      tabsBloc.add(RemoveTab(tab));
    }
  }

  Book? _findBookByTitle(library_model.Category category, String title) {
    for (final book in category.books) {
      if (book.title == title) {
        return book;
      }
    }
    for (final subCategory in category.subCategories) {
      final book = _findBookByTitle(subCategory, title);
      if (book != null) {
        return book;
      }
    }
    return null;
  }

  void _scheduleTourStartIfNeeded({required bool libraryLoaded}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_tourCubit.startIfNeeded(libraryLoaded: libraryLoaded)) {
        _tourStartedAutomaticallyThisLaunch = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _calendarCubit),
        BlocProvider.value(value: _tourCubit),
      ],
      child: MultiBlocListener(
        listeners: [
          BlocListener<NavigationBloc, NavigationState>(
            listenWhen: (previous, current) =>
                previous.currentScreen != current.currentScreen,
            listener: (context, state) {
              PluginRuntimeDispatcher.instance
                  .dispatchEvent('navigation.changed', {
                'screen': state.currentScreen.name,
              });
              _handleNavigationChange(context, state);
            },
          ),
          BlocListener<WorkspaceBloc, WorkspaceState>(
            listenWhen: (previous, current) =>
                previous.activeWorkspaceId != current.activeWorkspaceId ||
                (previous.isLoading && !current.isLoading),
            listener: (context, state) {
              PluginRuntimeDispatcher.instance
                  .dispatchEvent('workspace.changed', {
                'workspaceId': state.activeWorkspaceId,
              });
              // עדכון שם שולחן העבודה הנוכחי ב-HistoryBloc
              final currentId = state.activeWorkspaceId;
              if (currentId != null) {
                final workspace =
                    state.workspaces.firstWhere((w) => w.id == currentId);
                context.read<HistoryBloc>().add(
                      SetCurrentWorkspaceName(workspace.name),
                    );
              }
            },
          ),
          BlocListener<LibraryBloc, LibraryState>(
            listenWhen: (previous, current) =>
                previous.isLoading &&
                !current.isLoading &&
                current.library != null,
            listener: (context, state) {
              _startupWorkGate.markLibraryLoaded();
              _tryStartDeferredStartupWork();
              final navigationState = context.read<NavigationBloc>().state;
              if (navigationState.hasCheckedLibrary &&
                  !navigationState.isLibraryEmpty) {
                if (_tourCubit.startIfNeeded(libraryLoaded: true)) {
                  _tourStartedAutomaticallyThisLaunch = true;
                }
              }
            },
          ),
          BlocListener<LibraryBloc, LibraryState>(
            listenWhen: (previous, current) =>
                current.newBooksToIndex != null &&
                current.newBooksToIndex!.isNotEmpty,
            listener: (context, state) {
              if (context.read<SettingsBloc>().state.autoUpdateIndex) {
                context.read<IndexingBloc>().add(
                    IndexSpecificBooks(state.newBooksToIndex!, state.library!));
              } else {
                context
                    .read<IndexingBloc>()
                    .add(CheckIndexStatus(state.library!));
              }
            },
          ),
          BlocListener<IndexingBloc, IndexingState>(
            listenWhen: (previous, current) =>
                (previous is IndexingInProgress) !=
                (current is IndexingInProgress),
            listener: (context, state) {
              _startupWorkGate.markIndexingRunning(
                state is IndexingInProgress,
              );
              _tryStartDeferredStartupWork();
            },
          ),
          BlocListener<IndexingBloc, IndexingState>(
            listener: (context, state) {
              final cubit = context.read<WorkStatusCubit>();
              if (state is IndexingInProgress && state.isCreatingIndex) {
                final total = state.totalBooks ?? 0;
                final processed = state.booksProcessed ?? 0;
                final progress =
                    total > 0 ? (processed / total).clamp(0.0, 1.0) : null;
                cubit.upsert(WorkStatusItem(
                  id: 'indexing',
                  title: 'אינדוקס ספרים',
                  message: 'התוכנה בתהליך אינדוקס',
                  detail: 'התקדמות: $processed/$total',
                  progress: progress,
                ));
              } else {
                cubit.remove('indexing');
              }
            },
          ),
          BlocListener<SettingsBloc, SettingsState>(
            listenWhen: (previous, current) {
              // fire on first load or any change to plugin-visible settings
              if (previous == SettingsState.initial() &&
                  current != SettingsState.initial()) {
                return true;
              }
              return previous.isDarkMode != current.isDarkMode ||
                  previous.followSystemTheme != current.followSystemTheme ||
                  previous.seedColor != current.seedColor ||
                  previous.darkSeedColor != current.darkSeedColor ||
                  previous.fontSize != current.fontSize ||
                  previous.fontFamily != current.fontFamily ||
                  previous.commentatorsFontFamily !=
                      current.commentatorsFontFamily ||
                  previous.commentatorsFontSize !=
                      current.commentatorsFontSize ||
                  previous.lineHeight != current.lineHeight ||
                  previous.autoUpdateIndex != current.autoUpdateIndex ||
                  previous.showTeamim != current.showTeamim ||
                  previous.defaultRemoveNikud != current.defaultRemoveNikud ||
                  previous.removeNikudFromTanach !=
                      current.removeNikudFromTanach ||
                  previous.replaceHolyNames != current.replaceHolyNames ||
                  previous.libraryViewMode != current.libraryViewMode ||
                  previous.alignTabsToRight != current.alignTabsToRight ||
                  previous.copyWithHeaders != current.copyWithHeaders ||
                  previous.copyHeaderFormat != current.copyHeaderFormat;
            },
            listener: (context, current) {
              final previous = _prevSettingsState ?? SettingsState.initial();
              _prevSettingsState = current;

              // --- settings.changed: one event per changed key (allowlist only) ---
              void dispatch(String key, dynamic value) {
                PluginRuntimeDispatcher.instance.dispatchEvent(
                    'settings.changed', {'key': key, 'newValue': value});
              }

              if (previous.isDarkMode != current.isDarkMode) {
                dispatch(SettingsRepository.keyDarkMode, current.isDarkMode);
              }
              if (previous.followSystemTheme != current.followSystemTheme) {
                dispatch(SettingsRepository.keyFollowSystemTheme,
                    current.followSystemTheme);
              }
              if (previous.seedColor != current.seedColor) {
                dispatch(SettingsRepository.keySwatchColor,
                    current.seedColor.toARGB32().toRadixString(16));
              }
              if (previous.darkSeedColor != current.darkSeedColor) {
                dispatch(SettingsRepository.keyDarkSwatchColor,
                    current.darkSeedColor.toARGB32().toRadixString(16));
              }
              if (previous.fontSize != current.fontSize) {
                dispatch(SettingsRepository.keyFontSize, current.fontSize);
              }
              if (previous.fontFamily != current.fontFamily) {
                dispatch(SettingsRepository.keyFontFamily, current.fontFamily);
              }
              if (previous.commentatorsFontFamily !=
                  current.commentatorsFontFamily) {
                dispatch(SettingsRepository.keyCommentatorsFontFamily,
                    current.commentatorsFontFamily);
              }
              if (previous.commentatorsFontSize !=
                  current.commentatorsFontSize) {
                dispatch(SettingsRepository.keyCommentatorsFontSize,
                    current.commentatorsFontSize);
              }
              if (previous.lineHeight != current.lineHeight) {
                dispatch(SettingsRepository.keyLineHeight, current.lineHeight);
              }
              if (previous.showTeamim != current.showTeamim) {
                dispatch(SettingsRepository.keyShowTeamim, current.showTeamim);
              }
              if (previous.defaultRemoveNikud != current.defaultRemoveNikud) {
                dispatch(SettingsRepository.keyDefaultNikud,
                    current.defaultRemoveNikud);
              }
              if (previous.removeNikudFromTanach !=
                  current.removeNikudFromTanach) {
                dispatch(SettingsRepository.keyRemoveNikudFromTanach,
                    current.removeNikudFromTanach);
              }
              if (previous.replaceHolyNames != current.replaceHolyNames) {
                dispatch(SettingsRepository.keyReplaceHolyNames,
                    current.replaceHolyNames);
              }
              if (previous.libraryViewMode != current.libraryViewMode) {
                dispatch(SettingsRepository.keyLibraryViewMode,
                    current.libraryViewMode);
              }
              if (previous.alignTabsToRight != current.alignTabsToRight) {
                dispatch(SettingsRepository.keyAlignTabsToRight,
                    current.alignTabsToRight);
              }
              if (previous.copyWithHeaders != current.copyWithHeaders) {
                dispatch(SettingsRepository.keyCopyWithHeaders,
                    current.copyWithHeaders);
              }
              if (previous.copyHeaderFormat != current.copyHeaderFormat) {
                dispatch(SettingsRepository.keyCopyHeaderFormat,
                    current.copyHeaderFormat);
              }

              // --- theme.changed: only when visual theme changes ---
              final isThemeChange = previous.isDarkMode != current.isDarkMode ||
                  previous.followSystemTheme != current.followSystemTheme ||
                  previous.seedColor != current.seedColor ||
                  previous.darkSeedColor != current.darkSeedColor ||
                  previous.fontSize != current.fontSize ||
                  previous.fontFamily != current.fontFamily ||
                  previous.lineHeight != current.lineHeight ||
                  previous.commentatorsFontFamily !=
                      current.commentatorsFontFamily ||
                  previous.commentatorsFontSize != current.commentatorsFontSize;
              if (isThemeChange) {
                final themePayload = buildThemePayload(context);
                PluginRuntimeDispatcher.instance
                    .dispatchEvent('theme.changed', themePayload);
              }

              // --- internal app logic ---
              _checkAndStartIndexing(context);
              if (!previous.autoUpdateIndex && current.autoUpdateIndex) {
                _startIndexing(context);
              }
              _restoreFullscreenState(context);
            },
          ),
          BlocListener<TabsBloc, TabsState>(
            listenWhen: (previous, current) =>
                previous.currentTab != current.currentTab,
            listener: (context, state) {
              final currentTab = state.currentTab;
              if (currentTab != null) {
                int tabIndex = 0;
                if (currentTab is TextBookTab) tabIndex = currentTab.index;
                if (currentTab is PdfBookTab) tabIndex = currentTab.pageNumber;
                _tourCubit.recordInteraction(
                  TourInteraction(
                    type: TourInteractionType.currentTabChanged,
                    primaryValue: currentTab.title,
                  ),
                );
                if (currentTab is TextBookTab) {
                  _tourCubit.recordInteraction(
                    TourInteraction(
                      type: TourInteractionType.openedTextBook,
                      primaryValue: currentTab.title,
                    ),
                  );
                }
                if (currentTab is CombinedTab) {
                  _tourCubit.recordInteraction(
                    TourInteraction(
                      type: TourInteractionType.sideBySideEnabled,
                      primaryValue: currentTab.title,
                    ),
                  );
                }
                PluginRuntimeDispatcher.instance
                    .dispatchEvent('reader.current_book_changed', {
                  'book': currentTab.title,
                  'index': tabIndex,
                });
              }
            },
          ),
          // settings.changed עבור selectedCity ו-calendarType —
          // שדות אלה נמצאים ב-CalendarState ולא ב-SettingsState
          BlocListener<CalendarCubit, CalendarState>(
            listenWhen: (previous, current) =>
                previous.selectedCity != current.selectedCity ||
                previous.calendarType != current.calendarType,
            listener: (context, current) {
              final previous = _prevCalendarState;
              _prevCalendarState = current;
              if (previous == null) return;
              if (previous.selectedCity != current.selectedCity) {
                PluginRuntimeDispatcher.instance
                    .dispatchEvent('settings.changed', {
                  'key': SettingsRepository.keySelectedCity,
                  'newValue': current.selectedCity,
                });
              }
              if (previous.calendarType != current.calendarType) {
                PluginRuntimeDispatcher.instance
                    .dispatchEvent('settings.changed', {
                  'key': SettingsRepository.keyCalendarType,
                  'newValue': current.calendarType.toString(),
                });
              }
            },
          ),
          // רענון לוח כשמשתנה הספר הפתוח (book-scope events)
          BlocListener<TabsBloc, TabsState>(
            listenWhen: (previous, current) =>
                previous.currentTab?.title != current.currentTab?.title,
            listener: (context, state) {
              final bookId = state.currentTab?.title;
              final workspaceId =
                  context.read<WorkspaceBloc>().state.activeWorkspaceId;
              _calendarCubit.refreshPluginEvents(
                currentBookId: bookId,
                currentWorkspaceId: workspaceId,
              );
            },
          ),
          // רענון לוח כשמשתנה ה-workspace (workspace-scope events)
          BlocListener<WorkspaceBloc, WorkspaceState>(
            listenWhen: (previous, current) =>
                previous.activeWorkspaceId != current.activeWorkspaceId,
            listener: (context, state) {
              final workspaceId = state.activeWorkspaceId;
              final bookId = context.read<TabsBloc>().state.currentTab?.title;
              _calendarCubit.refreshPluginEvents(
                currentWorkspaceId: workspaceId,
                currentBookId: bookId,
              );
            },
          ),
          BlocListener<PluginSystemBloc, PluginSystemState>(
            listenWhen: (previous, current) =>
                false, // Only interested in permission changed, wait, plugin system state doesn't track this perfectly yet.
            listener: (context, state) {},
          ),
        ],
        child: BlocBuilder<NavigationBloc, NavigationState>(
          builder: (context, state) {
            // Build the pages list here so we can inject the EmptyLibraryScreen
            // into the library page while keeping the rest of the app visible.
            // נבנה את הדפים רק פעם אחת ונשמור אותם
            // אם מצב הספרייה השתנה, נבנה מחדש את דף הספרייה
            if (_cachedLibraryPage == null ||
                state.isLibraryEmpty !=
                    (_cachedLibraryPage is EmptyLibraryScreen) ||
                _previousLibraryEmptyState != state.isLibraryEmpty) {
              if (state.isLibraryEmpty) {
                // יצירת BLoC פעם אחת אם עדיין לא קיים
                _emptyLibraryBloc ??= EmptyLibraryBloc();
                _cachedLibraryPage = EmptyLibraryScreen(
                  bloc: _emptyLibraryBloc,
                  onLibraryLoaded: () async {
                    await context.read<NavigationBloc>().refreshLibrary();
                    if (!context.mounted) {
                      return;
                    }
                    context.read<LibraryBloc>().add(RefreshLibrary());
                  },
                );
              } else {
                // אם הספרייה כבר לא ריקה, נסגור את ה-BLoC
                _emptyLibraryBloc?.close();
                _emptyLibraryBloc = null;
                _cachedLibraryPage = LibraryBrowser(key: libraryBrowserKey);
              }
              _previousLibraryEmptyState = state.isLibraryEmpty;
            }

            _cachedReadingPage ??= const ReadingScreen();
            _cachedMorePage ??= ToolsScreen(key: moreScreenKey);
            _cachedSettingsPage ??=
                MySettingsScreen(controller: _settingsScreenController);

            _pages = [
              _cachedLibraryPage!,
              _cachedReadingPage!,
              _cachedMorePage!,
              _cachedSettingsPage!,
            ];

            if (state.hasCheckedLibrary) {
              _scheduleTourStartIfNeeded(libraryLoaded: !state.isLibraryEmpty);
            }
            _scheduleTourOverlayInsert();

            return SafeArea(
              child: KeyboardShortcuts(
                onFindRefRequested: () => _handleFindRefOpen(context),
                child: MyUpdatWidget(
                  child: Scaffold(
                    resizeToAvoidBottomInset: false,
                    body: Stack(
                      children: [
                        Column(
                          children: [
                            CustomTitleBar(
                              onReadingSettingsPressed:
                                  _toggleReadingSettingsPanel,
                              isReadingSettingsPanelOpen:
                                  _isReadingSettingsPanelOpen,
                            ),
                            Expanded(
                              child: OrientationBuilder(
                                builder: (context, orientation) {
                                  _handleOrientationChange(
                                      context, orientation);

                                  final pageView = PageView(
                                    controller: pageController,
                                    scrollDirection:
                                        orientation == Orientation.landscape
                                            ? Axis.vertical
                                            : Axis.horizontal,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    children: _pages,
                                  );

                                  if (orientation == Orientation.landscape) {
                                    return Row(
                                      children: [
                                        ColoredBox(
                                          color: AppSurfaces.panelBackground(
                                            context,
                                          ),
                                          child: SizedBox.fromSize(
                                            size: const Size.fromWidth(74),
                                            child: Column(
                                              children: [
                                                Expanded(
                                                  child: Material(
                                                    color: AppSurfaces
                                                        .panelBackground(
                                                      context,
                                                    ),
                                                    surfaceTintColor:
                                                        Colors.transparent,
                                                    child: LayoutBuilder(
                                                      builder: (context,
                                                          constraints) {
                                                        const buttonHeight =
                                                            60.0;
                                                        final totalButtonsHeight =
                                                            _navData.length *
                                                                buttonHeight;
                                                        final minSpacerHeight =
                                                            20.0;
                                                        final needsScroll =
                                                            totalButtonsHeight +
                                                                    minSpacerHeight >
                                                                constraints
                                                                    .maxHeight;

                                                        if (needsScroll) {
                                                          return SingleChildScrollView(
                                                            child: Column(
                                                              children: [
                                                                for (int i = 0;
                                                                    i <
                                                                        _navData
                                                                            .length;
                                                                    i++)
                                                                  _buildNavRailItem(
                                                                    context,
                                                                    i,
                                                                    state
                                                                        .currentScreen,
                                                                  ),
                                                              ],
                                                            ),
                                                          );
                                                        }

                                                        return Column(
                                                          children: [
                                                            for (int i = 0;
                                                                i < 5;
                                                                i++)
                                                              _buildNavRailItem(
                                                                context,
                                                                i,
                                                                state
                                                                    .currentScreen,
                                                              ),
                                                            const Spacer(),
                                                            for (int i = 5;
                                                                i <
                                                                    _navData
                                                                        .length;
                                                                i++)
                                                              _buildNavRailItem(
                                                                context,
                                                                i,
                                                                state
                                                                    .currentScreen,
                                                              ),
                                                          ],
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const VerticalDivider(
                                            thickness: 1, width: 1),
                                        Expanded(child: pageView),
                                      ],
                                    );
                                  } else {
                                    return Column(
                                      children: [
                                        Expanded(child: pageView),
                                        NavigationBar(
                                          backgroundColor:
                                              AppSurfaces.panelBackground(
                                            context,
                                          ),
                                          surfaceTintColor: Colors.transparent,
                                          destinations:
                                              _buildNavigationDestinations(),
                                          selectedIndex:
                                              _getActiveNavigationIndex(
                                            state.currentScreen,
                                          ),
                                          onDestinationSelected: (index) async {
                                            await _onNavTap(
                                              context,
                                              index,
                                              state.currentScreen,
                                            );
                                          },
                                        ),
                                      ],
                                    );
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        WorkStatusOverlay(
                          onTap: _openIndexingSettings,
                        ),
                        ContextOverlayPanel(
                          isOpen: _isReadingSettingsPanelOpen &&
                              (state.currentScreen == Screen.reading ||
                                  state.currentScreen == Screen.search),
                          onClose: _toggleReadingSettingsPanel,
                          deferChildBuildOnOpen: true,
                          preserveChildStateOnClose: true,
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Text(
                                      'הגדרות תצוגת הספרים',
                                      textDirection: TextDirection.rtl,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                              const Expanded(
                                child: ReadingSettingsPanel(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _openIndexingSettings() {
    _settingsScreenController.openTab(SettingsTab.library);
    context.read<NavigationBloc>().add(
          const NavigateToScreen(Screen.settings),
        );
  }

  int? _pageIndexForScreen(Screen screen) {
    switch (screen) {
      case Screen.library:
        return 0;
      case Screen.reading:
      case Screen.search:
        return 1;
      case Screen.more:
        return 2;
      case Screen.settings:
        return 3;
      case Screen.find:
        return null;
    }
  }

  void _handleSearchTabOpen(BuildContext context, {bool closeIfOpen = true}) {
    if (_isSearchOpen) {
      if (closeIfOpen) {
        Navigator.of(context).pop();
      }
      return;
    }

    final navigationBloc = context.read<NavigationBloc>();
    setState(() => _isSearchOpen = true);

    showDialog(
      context: context,
      builder: (context) => const SearchDialog(existingTab: null),
    ).then((_) {
      if (!mounted) return;
      setState(() => _isSearchOpen = false);
      // Restore focus to the screen below (dialog restorer was already removed
      // by SearchDialog.dispose → unregisterActiveRestorer)
      FocusRepository().scheduleRestore();
      final currentScreen = navigationBloc.state.currentScreen;
      if (currentScreen == Screen.reading || currentScreen == Screen.search) {
        _syncPageWithState();
      }
    });
  }

  void _handleFindRefOpen(
    BuildContext context, {
    bool closeIfOpen = true,
    bool transparentBarrier = true,
  }) {
    if (_isFindRefOpen) {
      if (closeIfOpen) {
        Navigator.of(context).pop();
      }
      return;
    }

    final navigationBloc = context.read<NavigationBloc>();
    setState(() => _isFindRefOpen = true);

    showDialog(
      context: context,
      useRootNavigator: true,
      barrierColor: transparentBarrier
          ? Colors.transparent
          : Theme.of(context).colorScheme.scrim.withValues(alpha: 0.62),
      builder: (context) => FindRefDialog(),
    ).then((_) {
      if (!mounted) return;
      setState(() => _isFindRefOpen = false);
      // Restore focus to the screen below (dialog restorer was already removed
      // by FindRefDialog.dispose → unregisterActiveRestorer)
      FocusRepository().scheduleRestore();
      final currentScreen = navigationBloc.state.currentScreen;
      if (currentScreen == Screen.reading || currentScreen == Screen.search) {
        _syncPageWithState();
      }
    });
  }

  int _getSelectedIndex(Screen currentScreen) {
    // מיפוי מחדש של האינדקסים כיון שהסרנו את דף האיתור
    switch (currentScreen) {
      case Screen.library:
        return 0;
      case Screen.find:
        return -1; // לא נבחר
      case Screen.reading:
        return 2;
      case Screen.search:
        return 3;
      case Screen.more:
        return 4;
      case Screen.settings:
        return 5;
    }
  }

  int _getActiveNavigationIndex(Screen currentScreen) {
    if (_isFindRefOpen) {
      return 1;
    }
    if (_isSearchOpen) {
      return 3;
    }
    return _getSelectedIndex(currentScreen);
  }

  Future<void> _onNavTap(
    BuildContext context,
    int index,
    Screen currentScreen,
  ) async {
    final currentIndex = _getSelectedIndex(currentScreen);
    final item = _navData[index];
    if (index == currentIndex &&
        item.screen != Screen.search &&
        item.screen != Screen.find) {
      await _syncPageWithState();
      return;
    }

    if (item.screen == Screen.search) {
      _handleSearchTabOpen(context);
    } else if (item.screen == Screen.find) {
      _handleFindRefOpen(context);
    } else {
      context.read<NavigationBloc>().add(
            NavigateToScreen(item.screen),
          );
    }

    if (item.screen == Screen.library) {
      context.read<FocusRepository>().requestLibrarySearchFocus(
            selectAll: true,
          );
    }
  }

  Widget _buildNavRailItem(
    BuildContext context,
    int index,
    Screen currentScreen,
  ) {
    final item = _navData[index];
    final isSelected = _getActiveNavigationIndex(currentScreen) == index;
    final tooltip =
        (Settings.getValue<String>(item.shortcutKey) ?? item.shortcutDefault)
            .toUpperCase();

    final step = _tourCubit.state.currentStep;
    final isTourHighlighted = _isTourNavigationItemHighlighted(
      step,
      index,
      currentScreen,
    );
    return NavRailItem(
      icon: item.icon,
      iconFilled: item.iconFilled,
      label: item.label,
      isSelected: isSelected,
      onTap: () => _onNavTap(context, index, currentScreen),
      tooltip: tooltip,
      tourTargetKey: tourMainNavigationTargetKeys[index],
      tourItemKey: tourMainNavigationItemTargetKeys[index],
      isTourHighlighted: isTourHighlighted,
    );
  }

  bool _isTourNavigationItemHighlighted(
    TourStep? step,
    int index,
    Screen currentScreen,
  ) {
    if (step == null) {
      return false;
    }
    if (step.area == TourSpotlightArea.navigation &&
        index == _getActiveNavigationIndex(currentScreen)) {
      return true;
    }

    final targetScreen = _tourNavigationScreenForStep(step);
    return targetScreen != null && _navData[index].screen == targetScreen;
  }

  Screen? _tourNavigationScreenForStep(TourStep step) {
    return switch (step.id) {
      'find_ref' => Screen.find,
      'tools' => Screen.more,
      'advanced_search' => Screen.search,
      'settings' => Screen.settings,
      'library' => Screen.library,
      _ => null,
    };
  }

  Future<void> _openTourBookByTitle(String title) async {
    try {
      final library = await DataRepository.instance.library;
      final book = _findBookByTitle(library, title) ?? TextBook(title: title);
      if (!mounted) return;
      openBook(context, book, 0, '', ignoreHistory: true);
    } catch (_) {
      if (!mounted) return;
      openBook(
        context,
        TextBook(title: title),
        0,
        '',
        ignoreHistory: true,
      );
    }
  }
}

class KeepAlivePage extends StatefulWidget {
  final Widget child;

  const KeepAlivePage({super.key, required this.child});

  @override
  State<KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

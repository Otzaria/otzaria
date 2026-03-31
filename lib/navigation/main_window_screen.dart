import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/navigation/startup_work_gate.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/empty_library/empty_library_screen.dart';
import 'package:otzaria/empty_library/bloc/empty_library_bloc.dart';
import 'package:otzaria/find_ref/find_ref_dialog.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/library/view/library_browser.dart';
import 'package:otzaria/tabs/reading_screen.dart';
import 'package:otzaria/tools/more_screen.dart';
import 'package:otzaria/shortcuts/keyboard_shortcuts.dart';
import 'dart:async';
import 'package:otzaria/update/my_updat_widget.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/widgets/ad_popup_dialog.dart';
import 'package:window_manager/window_manager.dart';
import 'package:otzaria/main.dart' show appWindowListener;
import 'package:otzaria/navigation/custom_title_bar.dart';
import 'package:otzaria/migration/sync/background_sync_initializer.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_state.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/file_sync/file_sync_bloc.dart';
import 'package:otzaria/file_sync/file_sync_event.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/nav_rail_item.dart'; // ← חדש

class MainWindowScreen extends StatefulWidget {
  const MainWindowScreen({super.key});

  @override
  MainWindowScreenState createState() => MainWindowScreenState();
}

class MainWindowScreenState extends State<MainWindowScreen>
    with TickerProviderStateMixin {
  late final PageController pageController;
  late final CalendarCubit _calendarCubit;
  late final SettingsScreenController _settingsScreenController;
  Orientation? _previousOrientation;
  int _currentPageIndex = 0;

  List<Widget> _pages = [];

  Widget? _cachedLibraryPage;
  Widget? _cachedReadingPage;
  Widget? _cachedMorePage;
  Widget? _cachedSettingsPage;

  EmptyLibraryBloc? _emptyLibraryBloc;
  bool? _previousLibraryEmptyState;

  final StartupWorkGate _startupWorkGate = StartupWorkGate();
  bool _hasCheckedAutoIndex = false;
  bool _hasRestoredFullscreen = false;
  bool _hasStartedFileSync = false;

  bool _isSearchOpen = false;
  bool _isFindRefOpen = false;

  // ── נתוני פריטי הניווט הראשי ─────────────────────────────────────────────
  // משמש גם ל-NavRailItem (desktop) וגם ל-_buildNavigationDestinations (mobile)
  static const _navData = [
    (
      icon: FluentIcons.library_24_regular,
      iconFilled: FluentIcons.library_24_filled,
      label: 'ספרייה',
      shortcutKey: 'key-shortcut-open-library-browser',
      shortcutDefault: 'ctrl+l',
    ),
    (
      icon: FluentIcons.book_search_24_regular,
      iconFilled: FluentIcons.book_search_24_filled,
      label: 'איתור',
      shortcutKey: 'key-shortcut-open-find-ref',
      shortcutDefault: 'ctrl+o',
    ),
    (
      icon: FluentIcons.book_open_24_regular,
      iconFilled: FluentIcons.book_open_24_filled,
      label: 'עיון',
      shortcutKey: 'key-shortcut-open-reading-screen',
      shortcutDefault: 'ctrl+r',
    ),
    (
      icon: FluentIcons.search_24_regular,
      iconFilled: FluentIcons.search_24_filled,
      label: 'חיפוש',
      shortcutKey: 'key-shortcut-open-new-search',
      shortcutDefault: 'ctrl+q',
    ),
    (
      icon: FluentIcons.apps_24_regular,
      iconFilled: FluentIcons.apps_24_filled,
      label: 'כלים',
      shortcutKey: 'key-shortcut-open-more',
      shortcutDefault: 'ctrl+m',
    ),
    (
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
    final initialPage = _pageIndexForScreen(
          context.read<NavigationBloc>().state.currentScreen,
        ) ??
        Screen.library.index;
    _currentPageIndex = initialPage;
    pageController = PageController(initialPage: initialPage);

    // הצגת פופאפ פרסומת אחרי 5 שניות
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AdPopupDialog.showIfNeeded(context);
    });

    // Setup fullscreen sync with window manager
    _setupFullscreenSync();

    // NOTE: Background sync is now triggered by LibraryBloc listener
    // (see MultiBlocListener) to avoid DB lock contention during library loading.
  }

  /// Trigger FileSyncBloc to start syncing AFTER the library is loaded.
  /// Runs only once per app session.
  void _startFileSync() {
    if (_hasStartedFileSync) {
      return;
    }

    _hasStartedFileSync = true;

    final isAutoSync =
        Settings.getValue<bool>(SettingsRepository.keyAutoSync) ?? true;
    final isOffline = context.read<SettingsBloc>().state.isOfflineMode;
    if (isAutoSync && !isOffline) {
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
      delaySeconds: 2,
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
  void _setupFullscreenSync() {
    if (kIsWeb ||
        (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS)) {
      return;
    }
    appWindowListener?.onFullscreenChanged = (isFullscreen) {
      if (!mounted) return;
      final settingsBloc = context.read<SettingsBloc>();
      if (settingsBloc.state.isFullscreen != isFullscreen) {
        settingsBloc.add(UpdateIsFullscreen(isFullscreen));
      }
    };
  }

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
    if (_hasCheckedAutoIndex) return;
    _hasCheckedAutoIndex = true;
    if (context.read<SettingsBloc>().state.autoUpdateIndex) {
      DataRepository.instance.library.then((library) {
        if (!mounted || !context.mounted) return;
        context.read<IndexingBloc>().add(StartIndexing(library));
      });
    }
  }

  @override
  void dispose() {
    appWindowListener?.onFullscreenChanged = null;
    _calendarCubit.close();
    _emptyLibraryBloc?.close();
    pageController.dispose();
    super.dispose();
  }

  void _handleOrientationChange(BuildContext context, Orientation orientation) {
    if (_previousOrientation != orientation) {
      _previousOrientation = orientation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final currentScreen =
            context.read<NavigationBloc>().state.currentScreen;
        final targetPage = _pageIndexForScreen(currentScreen);
        if (targetPage == null) return;
        if (_currentPageIndex != targetPage) {
          setState(() => _currentPageIndex = targetPage);
          if (pageController.hasClients) {
            pageController.jumpToPage(targetPage);
          }
        }
      });
    }
  }

  Future<void> _syncPageWithState() async {
    if (!mounted || !pageController.hasClients) return;
    final currentScreen = context.read<NavigationBloc>().state.currentScreen;
    final targetPage = _pageIndexForScreen(currentScreen);
    if (targetPage == null) return;
    if (_currentPageIndex == targetPage) return;
    setState(() => _currentPageIndex = targetPage);
    pageController.jumpToPage(targetPage);
  }

  // ── ניווט ─────────────────────────────────────────────────────────────────

  void _handleNavigationChange(
      BuildContext context, NavigationState state) async {
    if (!mounted || !context.mounted) return;
    final targetPage = _pageIndexForScreen(state.currentScreen);
    if (targetPage != null && _currentPageIndex != targetPage) {
      setState(() => _currentPageIndex = targetPage);
      if (pageController.hasClients) {
        pageController.animateToPage(
          targetPage,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
    if (state.currentScreen == Screen.library) {
      context
          .read<FocusRepository>()
          .requestLibrarySearchFocus(selectAll: true);
    } else if (state.currentScreen == Screen.more) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<FocusRepository>().requestMoreScreenFocus();
      });
    } else if (state.currentScreen == Screen.reading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<FocusRepository>().requestBookContentFocus();
      });
    }
  }

  int _getSelectedIndex(Screen currentScreen) {
    switch (currentScreen) {
      case Screen.library:
        return 0;
      case Screen.find:
        return -1;
      case Screen.reading:
        return 2;
      case Screen.search:
        return 3;
      case Screen.more:
        return 4;
      case Screen.settings:
        return 5;
      case Screen.about:
        return -1;
    }
  }

  bool _isDialogButtonSelected(int index) {
    return switch (index) {
      1 => _isFindRefOpen,
      3 => _isSearchOpen,
      _ => false,
    };
  }

  // ── onTap handler לכל כפתור ניווט ────────────────────────────────────────
  Future<void> _onNavTap(
    BuildContext context,
    int index,
    Screen currentScreen,
  ) async {
    final currentIndex = _getSelectedIndex(currentScreen);
    if (index == currentIndex &&
        index != Screen.search.index &&
        index != Screen.find.index) {
      await _syncPageWithState();
      return;
    }
    if (index == Screen.search.index) {
      _handleSearchTabOpen(context);
    } else if (index == Screen.find.index) {
      _handleFindRefOpen(context);
    } else {
      context
          .read<NavigationBloc>()
          .add(NavigateToScreen(Screen.values[index]));
    }
    if (index == Screen.library.index) {
      context
          .read<FocusRepository>()
          .requestLibrarySearchFocus(selectAll: true);
    }
  }

  // ── NavRail (desktop) ─────────────────────────────────────────────────────
  Widget _buildNavRailItem(
    BuildContext context,
    int index,
    Screen currentScreen,
  ) {
    final isSelected = _getSelectedIndex(currentScreen) == index ||
        _isDialogButtonSelected(index);
    final item = _navData[index];
    final tooltip =
        (Settings.getValue<String>(item.shortcutKey) ?? item.shortcutDefault)
            .toUpperCase();

    return NavRailItem(
      icon: item.icon,
      iconFilled: item.iconFilled,
      label: item.label,
      isSelected: isSelected,
      onTap: () => _onNavTap(context, index, currentScreen),
      tooltip: tooltip,
    );
  }

  // ── NavigationBar (mobile) ─────────────────────────────────────────────────
  List<NavigationDestination> _buildNavigationDestinations() {
    String fmt(String s) => s.toUpperCase();
    return [
      for (final item in _navData)
        NavigationDestination(
          tooltip: '',
          icon: Tooltip(
            preferBelow: false,
            message: fmt(
              Settings.getValue<String>(item.shortcutKey) ??
                  item.shortcutDefault,
            ),
            child: Icon(item.icon),
          ),
          selectedIcon: Icon(item.iconFilled),
          label: item.label,
        ),
    ];
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<NavigationBloc, NavigationState>(
          listenWhen: (previous, current) =>
              previous.currentScreen != current.currentScreen,
          listener: _handleNavigationChange,
        ),
        BlocListener<WorkspaceBloc, WorkspaceState>(
          listenWhen: (previous, current) =>
              previous.activeWorkspaceId != current.activeWorkspaceId ||
              (previous.isLoading && !current.isLoading),
          listener: (context, state) {
            final currentId = state.activeWorkspaceId;
            if (currentId != null) {
              final workspace =
                  state.workspaces.firstWhere((w) => w.id == currentId);
              context
                  .read<HistoryBloc>()
                  .add(SetCurrentWorkspaceName(workspace.name));
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
        BlocListener<SettingsBloc, SettingsState>(
          listenWhen: (previous, current) {
            final isInitialLoad = previous == SettingsState.initial() &&
                current != SettingsState.initial();
            final hasChanged =
                previous.autoUpdateIndex != current.autoUpdateIndex;
            return isInitialLoad || hasChanged;
          },
          listener: (context, state) {
            _checkAndStartIndexing(context);
            _startupWorkGate.markIndexingDecisionResolved(
              expectIndexing: state.autoUpdateIndex,
            );
            _tryStartDeferredStartupWork();
            _restoreFullscreenState(context);
          },
        ),
      ],
      child: BlocProvider.value(
        value: _calendarCubit,
        child: BlocBuilder<NavigationBloc, NavigationState>(
          builder: (context, state) {
            if (_cachedLibraryPage == null ||
                state.isLibraryEmpty !=
                    (_cachedLibraryPage is EmptyLibraryScreen) ||
                _previousLibraryEmptyState != state.isLibraryEmpty) {
              if (state.isLibraryEmpty) {
                _emptyLibraryBloc ??= EmptyLibraryBloc();
                _cachedLibraryPage = EmptyLibraryScreen(
                  bloc: _emptyLibraryBloc,
                  onLibraryLoaded: () =>
                      context.read<NavigationBloc>().refreshLibrary(),
                );
              } else {
                _emptyLibraryBloc?.close();
                _emptyLibraryBloc = null;
                _cachedLibraryPage = const LibraryBrowser();
              }
              _previousLibraryEmptyState = state.isLibraryEmpty;
            }

            _cachedReadingPage ??= const ReadingScreen();
            _cachedMorePage ??= MoreScreen(key: moreScreenKey);
            _cachedSettingsPage ??=
                MySettingsScreen(controller: _settingsScreenController);

            _pages = [
              _cachedLibraryPage!,
              _cachedReadingPage!,
              _cachedMorePage!,
              _cachedSettingsPage!,
            ];

            return SafeArea(
              child: KeyboardShortcuts(
                child: MyUpdatWidget(
                  child: Scaffold(
                    resizeToAvoidBottomInset: false,
                    body: Column(
                      children: [
                        const CustomTitleBar(),
                        Expanded(
                          child: OrientationBuilder(
                            builder: (context, orientation) {
                              _handleOrientationChange(context, orientation);

                              final pageView = PageView(
                                controller: pageController,
                                scrollDirection:
                                    orientation == Orientation.landscape
                                        ? Axis.vertical
                                        : Axis.horizontal,
                                physics: const NeverScrollableScrollPhysics(),
                                children: _pages,
                              );

                              // ── Desktop: NavRail ──────────────────────
                              if (orientation == Orientation.landscape) {
                                return Row(
                                  children: [
                                    ColoredBox(
                                      color:
                                          AppSurfaces.panelBackground(context),
                                      child: SizedBox.fromSize(
                                        size: const Size.fromWidth(74),
                                        child: Column(
                                          children: [
                                            Expanded(
                                              child: Material(
                                                color:
                                                    AppSurfaces.panelBackground(
                                                        context),
                                                surfaceTintColor:
                                                    Colors.transparent,
                                                child: LayoutBuilder(
                                                  builder:
                                                      (context, constraints) {
                                                    const buttonHeight = 60.0;
                                                    final totalButtonsHeight =
                                                        _navData.length *
                                                            buttonHeight;
                                                    final needsScroll =
                                                        totalButtonsHeight +
                                                                20.0 >
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
                                                                      .currentScreen),
                                                          ],
                                                        ),
                                                      );
                                                    } else {
                                                      final topCount =
                                                          _navData.length > 5
                                                              ? 5
                                                              : _navData.length;
                                                      return Column(
                                                        children: [
                                                          for (int i = 0;
                                                              i < topCount;
                                                              i++)
                                                            _buildNavRailItem(
                                                                context,
                                                                i,
                                                                state
                                                                    .currentScreen),
                                                          const Spacer(),
                                                          for (int i = topCount;
                                                              i <
                                                                  _navData
                                                                      .length;
                                                              i++)
                                                            _buildNavRailItem(
                                                                context,
                                                                i,
                                                                state
                                                                    .currentScreen),
                                                        ],
                                                      );
                                                    }
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
                              }

                              // ── Mobile: NavigationBar ─────────────────
                              return Column(
                                children: [
                                  Expanded(child: pageView),
                                  NavigationBar(
                                    backgroundColor:
                                        AppSurfaces.panelBackground(context),
                                    surfaceTintColor: Colors.transparent,
                                    destinations:
                                        _buildNavigationDestinations(),
                                    selectedIndex:
                                        _getSelectedIndex(state.currentScreen),
                                    onDestinationSelected: (index) async {
                                      final currentIndex = _getSelectedIndex(
                                          state.currentScreen);
                                      if (index == currentIndex &&
                                          index != Screen.search.index &&
                                          index != Screen.find.index) {
                                        await _syncPageWithState();
                                        return;
                                      }
                                      _onNavTap(
                                          context, index, state.currentScreen);
                                    },
                                  ),
                                ],
                              );
                            },
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
      case Screen.about:
        return null;
    }
  }

  void _handleSearchTabOpen(BuildContext context) {
    if (_isSearchOpen) {
      Navigator.of(context).pop();
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
      final currentScreen = navigationBloc.state.currentScreen;
      if (currentScreen == Screen.reading || currentScreen == Screen.search) {
        _syncPageWithState();
      }
    });
  }

  void _handleFindRefOpen(BuildContext context) {
    if (_isFindRefOpen) {
      Navigator.of(context).pop();
      return;
    }
    final navigationBloc = context.read<NavigationBloc>();
    setState(() => _isFindRefOpen = true);
    showDialog(
      context: context,
      builder: (context) => FindRefDialog(),
    ).then((_) {
      if (!mounted) return;
      setState(() => _isFindRefOpen = false);
      final currentScreen = navigationBloc.state.currentScreen;
      if (currentScreen == Screen.reading || currentScreen == Screen.search) {
        _syncPageWithState();
      }
    });
  }
}

// ── KeepAlivePage ─────────────────────────────────────────────────────────────
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

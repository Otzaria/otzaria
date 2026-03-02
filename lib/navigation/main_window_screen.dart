import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/empty_library/empty_library_screen.dart';
import 'package:otzaria/empty_library/bloc/empty_library_bloc.dart';
import 'package:otzaria/find_ref/find_ref_dialog.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/library/view/library_browser.dart';
import 'package:otzaria/tabs/reading_screen.dart';
import 'package:otzaria/tools/more_screen.dart';
import 'package:otzaria/navigation/about_dialog.dart';
import 'package:otzaria/shortcuts/keyboard_shortcuts.dart';
import 'dart:async';
import 'package:otzaria/update/my_updat_widget.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tools/calendar/ulits/calendar_cubit.dart';
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

class MainWindowScreen extends StatefulWidget {
  const MainWindowScreen({super.key});

  @override
  MainWindowScreenState createState() => MainWindowScreenState();
}

// Global key for accessing MoreScreen
final GlobalKey<State<MoreScreen>> moreScreenKey =
    GlobalKey<State<MoreScreen>>();

class MainWindowScreenState extends State<MainWindowScreen>
    with TickerProviderStateMixin {
  late final PageController pageController;
  late final CalendarCubit _calendarCubit;
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

  bool _hasCheckedAutoIndex = false;
  bool _hasRestoredFullscreen = false;

  @override
  void initState() {
    super.initState();
    _calendarCubit = CalendarCubit();
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

    // Check if auto-update is enabled
    if (context.read<SettingsBloc>().state.autoUpdateIndex) {
      DataRepository.instance.library.then((library) {
        if (!mounted || !context.mounted) return;
        context.read<IndexingBloc>().add(StartIndexing(library));
      });
    }
  }

  @override
  void dispose() {
    // Clean up fullscreen callback
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
        if (!mounted) {
          return;
        }
        final currentScreen =
            context.read<NavigationBloc>().state.currentScreen;
        final targetPage = _pageIndexForScreen(currentScreen);
        if (targetPage == null) {
          return;
        }

        if (_currentPageIndex != targetPage) {
          setState(() {
            _currentPageIndex = targetPage;
          });
          if (pageController.hasClients) {
            pageController.jumpToPage(targetPage);
          }
        }
      });
    }
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
    String formatShortcut(String shortcut) => shortcut.toUpperCase();

    final libraryShortcut =
        Settings.getValue<String>('key-shortcut-open-library-browser') ??
            'ctrl+l';
    final findShortcut =
        Settings.getValue<String>('key-shortcut-open-find-ref') ?? 'ctrl+o';
    final browseShortcut =
        Settings.getValue<String>('key-shortcut-open-reading-screen') ??
            'ctrl+r';
    final searchShortcut =
        Settings.getValue<String>('key-shortcut-open-new-search') ?? 'ctrl+q';

    return [
      NavigationDestination(
        tooltip: '',
        icon: Tooltip(
          preferBelow: false,
          message: formatShortcut(libraryShortcut),
          child: const Icon(FluentIcons.library_24_regular),
        ),
        label: 'ספרייה',
      ),
      NavigationDestination(
        tooltip: '',
        icon: Tooltip(
          preferBelow: false,
          message: formatShortcut(findShortcut),
          child: const Icon(FluentIcons.book_search_24_regular),
        ),
        label: 'איתור',
      ),
      NavigationDestination(
        tooltip: '',
        icon: Tooltip(
          preferBelow: false,
          message: formatShortcut(browseShortcut),
          child: const Icon(FluentIcons.book_open_24_regular),
        ),
        label: 'עיון',
      ),
      NavigationDestination(
        tooltip: '',
        icon: Tooltip(
          preferBelow: false,
          message: formatShortcut(searchShortcut),
          child: const Icon(FluentIcons.search_24_regular),
        ),
        label: 'חיפוש',
      ),
      NavigationDestination(
        tooltip: '',
        icon: Tooltip(
          preferBelow: false,
          message: formatShortcut(
            Settings.getValue<String>('key-shortcut-open-more') ?? 'ctrl+m',
          ),
          child: const Icon(FluentIcons.apps_24_regular),
        ),
        label: 'כלים',
      ),
      NavigationDestination(
        tooltip: '',
        icon: Tooltip(
          preferBelow: false,
          message: formatShortcut(
            Settings.getValue<String>('key-shortcut-open-settings') ??
                'ctrl+comma',
          ),
          child: const Icon(FluentIcons.settings_24_regular),
        ),
        label: 'הגדרות',
      ),
      NavigationDestination(
        icon: Icon(FluentIcons.info_24_regular),
        label: 'אודות',
      ),
    ];
  }

  void _handleNavigationChange(
    BuildContext context,
    NavigationState state,
  ) async {
    if (!mounted || !context.mounted) {
      return;
    }

    final targetPage = _pageIndexForScreen(state.currentScreen);
    if (targetPage != null && _currentPageIndex != targetPage) {
      setState(() {
        _currentPageIndex = targetPage;
      });
      // מעבר עם אנימציה
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
    } else if (state.currentScreen == Screen.reading) {
      // בקשת focus לתוכן הספר כשעוברים למסך עיון
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<FocusRepository>().requestBookContentFocus();
        }
      });
    }
  }

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
            // Library finished loading - now safe to start background sync
            // without DB lock contention
            _initializeBackgroundSync();
          },
        ),
        BlocListener<SettingsBloc, SettingsState>(
          listenWhen: (previous, current) {
            // Trigger when settings are loaded for the first time (not initial state anymore)
            // or when autoUpdateIndex changes
            final isInitialLoad = previous == SettingsState.initial() &&
                current != SettingsState.initial();
            final hasChanged =
                previous.autoUpdateIndex != current.autoUpdateIndex;
            return isInitialLoad || hasChanged;
          },
          listener: (context, state) {
            // When settings are loaded for the first time, check if we should start indexing
            _checkAndStartIndexing(context);
            // Also restore fullscreen state
            _restoreFullscreenState(context);
          },
        ),
      ],
      child: BlocProvider.value(
        value: _calendarCubit,
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
                  onLibraryLoaded: () {
                    context.read<NavigationBloc>().refreshLibrary();
                  },
                );
              } else {
                // אם הספרייה כבר לא ריקה, נסגור את ה-BLoC
                _emptyLibraryBloc?.close();
                _emptyLibraryBloc = null;
                _cachedLibraryPage = const LibraryBrowser();
              }
              _previousLibraryEmptyState = state.isLibraryEmpty;
            }

            _cachedReadingPage ??= const ReadingScreen();
            _cachedMorePage ??= MoreScreen(key: moreScreenKey);
            _cachedSettingsPage ??= const MySettingsScreen();

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

                              if (orientation == Orientation.landscape) {
                                return Row(
                                  children: [
                                    SizedBox.fromSize(
                                      size: const Size.fromWidth(74),
                                      child: Column(
                                        children: [
                                          Expanded(
                                            child: Material(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .surface,
                                              child: LayoutBuilder(
                                                builder:
                                                    (context, constraints) {
                                                  // חישוב גובה משוער לכל הכפתורים
                                                  const buttonHeight =
                                                      60.0; // גובה משוער לכפתור + padding
                                                  final totalButtonsHeight =
                                                      7 * buttonHeight;
                                                  final minSpacerHeight = 20.0;
                                                  final needsScroll =
                                                      totalButtonsHeight +
                                                              minSpacerHeight >
                                                          constraints.maxHeight;

                                                  if (needsScroll) {
                                                    // אם אין מספיק מקום, השתמש בגלילה
                                                    return SingleChildScrollView(
                                                      child: Column(
                                                        children: [
                                                          for (int i = 0;
                                                              i < 7;
                                                              i++)
                                                            _buildNavButton(
                                                              context,
                                                              _buildNavigationDestinations()[
                                                                  i],
                                                              i,
                                                              state
                                                                  .currentScreen,
                                                            ),
                                                        ],
                                                      ),
                                                    );
                                                  } else {
                                                    // אם יש מספיק מקום, השתמש ב-Spacer
                                                    return Column(
                                                      children: [
                                                        // כפתורים עליונים
                                                        for (int i = 0;
                                                            i < 5;
                                                            i++)
                                                          _buildNavButton(
                                                            context,
                                                            _buildNavigationDestinations()[
                                                                i],
                                                            i,
                                                            state.currentScreen,
                                                          ),
                                                        // רווח גמיש
                                                        const Spacer(),
                                                        // כפתורים תחתונים
                                                        for (int i = 5;
                                                            i < 7;
                                                            i++)
                                                          _buildNavButton(
                                                            context,
                                                            _buildNavigationDestinations()[
                                                                i],
                                                            i,
                                                            state.currentScreen,
                                                          ),
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
                                      destinations:
                                          _buildNavigationDestinations(),
                                      selectedIndex: _getSelectedIndex(
                                        state.currentScreen,
                                      ),
                                      onDestinationSelected: (index) async {
                                        // אם בחרו שוב באותו היעד – רק סנכרנו את ה-PageView למסך
                                        final currentIndex = _getSelectedIndex(
                                            state.currentScreen);
                                        if (index == currentIndex &&
                                            index != Screen.search.index &&
                                            index != Screen.find.index) {
                                          // סנכרון ידני – שימושי כאשר מסיבה כלשהי ה-PageView סטה מהמצב
                                          await _syncPageWithState();
                                          return;
                                        }
                                        if (index == Screen.search.index) {
                                          _handleSearchTabOpen(context);
                                        } else if (index == Screen.find.index) {
                                          _handleFindRefOpen(context);
                                        } else if (index ==
                                            Screen.about.index) {
                                          showDialog(
                                            context: context,
                                            builder: (context) =>
                                                const AboutDialogWidget(),
                                          );
                                        } else {
                                          context.read<NavigationBloc>().add(
                                                NavigateToScreen(
                                                    Screen.values[index]),
                                              );
                                        }
                                        if (index == Screen.library.index) {
                                          context
                                              .read<FocusRepository>()
                                              .requestLibrarySearchFocus(
                                                selectAll: true,
                                              );
                                        }
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
    final useFastSearch = context.read<SettingsBloc>().state.useFastSearch;
    if (!useFastSearch) {
      _openLegacySearchTab(context);
      return;
    }

    final navigationBloc = context.read<NavigationBloc>();

    showDialog(
      context: context,
      builder: (context) => const SearchDialog(existingTab: null),
    ).then((_) {
      // אחרי סגירת הדיאלוג, אם אנחנו במסך reading/search, נוודא שהמצב מסונכרן
      if (!mounted) return;
      final currentScreen = navigationBloc.state.currentScreen;
      if (currentScreen == Screen.reading || currentScreen == Screen.search) {
        _syncPageWithState();
      }
    });
  }

  void _openLegacySearchTab(BuildContext context) {
    final tabsBloc = context.read<TabsBloc>();
    final navigationBloc = context.read<NavigationBloc>();

    final tabsState = tabsBloc.state;
    final hasSearchTab = tabsState.tabs.any(
      (tab) => tab.runtimeType == SearchingTab,
    );

    if (!hasSearchTab) {
      tabsBloc.add(AddTab(SearchingTab("חיפוש", "")));
    } else {
      final currentScreen = navigationBloc.state.currentScreen;
      final isAlreadySearchTab = currentScreen == Screen.search &&
          tabsState.tabs[tabsState.currentTabIndex].runtimeType == SearchingTab;
      if (!isAlreadySearchTab) {
        final searchTabIndex = tabsState.tabs.indexWhere(
          (tab) => tab.runtimeType == SearchingTab,
        );
        if (searchTabIndex != -1) {
          tabsBloc.add(SetCurrentTab(searchTabIndex));
        }
      }
    }

    navigationBloc.add(const NavigateToScreen(Screen.search));
  }

  void _handleFindRefOpen(BuildContext context) {
    final navigationBloc = context.read<NavigationBloc>();

    showDialog(
      context: context,
      builder: (context) => FindRefDialog(),
    ).then((_) {
      // אחרי סגירת הדיאלוג, אם אנחנו במסך reading, נוודא שהמצב מסונכרן
      if (!mounted) return;
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
      case Screen.about:
        return 6;
    }
  }

  Widget _buildNavButton(
    BuildContext context,
    NavigationDestination destination,
    int index,
    Screen currentScreen,
  ) {
    final isSelected = _getSelectedIndex(currentScreen) == index;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 74,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () async {
              // אם בחרו שוב באותו היעד – רק סנכרנו את ה-PageView למסך
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
              } else if (index == Screen.about.index) {
                showDialog(
                  context: context,
                  builder: (context) => const AboutDialogWidget(),
                );
              } else {
                context.read<NavigationBloc>().add(
                      NavigateToScreen(Screen.values[index]),
                    );
              }
              if (index == Screen.library.index) {
                context.read<FocusRepository>().requestLibrarySearchFocus(
                      selectAll: true,
                    );
              }
            },
            icon: IconTheme(
              data: IconThemeData(
                color: isSelected
                    ? colorScheme.onSecondaryContainer
                    : colorScheme.onSurfaceVariant,
                size: 24,
              ),
              child: destination.icon,
            ),
            style: IconButton.styleFrom(
              backgroundColor: isSelected
                  ? colorScheme.secondaryContainer
                  : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              minimumSize: const Size(56, 25),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            destination.label,
            style: TextStyle(
              fontSize: 11,
              color: isSelected
                  ? colorScheme.onSecondaryContainer
                  : colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
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
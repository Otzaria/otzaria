import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/external_catalog/view/external_catalog_settings_helper.dart';
import 'package:otzaria/library/view/resizable_preview_panel.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/daf_yomi/daf_yomi_helper.dart';
import 'package:otzaria/file_sync/file_sync_bloc.dart';
import 'package:otzaria/file_sync/file_sync_event.dart';
import 'package:otzaria/file_sync/file_sync_repository.dart';
import 'package:otzaria/file_sync/file_sync_state.dart';
import 'package:otzaria/daf_yomi/daf_yomi.dart';
import 'package:otzaria/widgets/filter_chips_widget.dart';
import 'package:otzaria/tools/more_screen.dart' show moreScreenKey;
import 'package:otzaria/library/view/grid_items.dart';
import 'package:otzaria/library/view/otzar_book_dialog.dart';
import 'package:otzaria/library/view/book_preview_panel.dart';
import 'package:otzaria/library/view/library_panel_controller.dart';
import 'package:otzaria/settings/panels/library_settings_panel.dart';
import 'package:otzaria/widgets/buttons/action_buttons.dart';
import 'package:otzaria/widgets/app_top_bar.dart';
import 'package:otzaria/widgets/responsive_action_bar.dart';
import 'package:otzaria/utils/open_book.dart';

import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/core/widgets/otzaria_search_field.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/theme/app_surfaces.dart';

enum _LibrarySidePanel {
  none,
  preview,
  settings,
}

class LibraryBrowser extends StatefulWidget {
  const LibraryBrowser({super.key});

  @override
  State<LibraryBrowser> createState() => _LibraryBrowserState();
}

class _LibraryBrowserState extends State<LibraryBrowser>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;

  final FocusNode _firstSearchResultFocusNode = FocusNode();
  int _depth = 0;
  final Set<String> _expandedCategories = {};
  _LibrarySidePanel _activeSidePanel = _LibrarySidePanel.none;
  bool? _previewPanelOverrideVisible;

  /// שולט בנראות השורה השניה של הסרגל העליון.
  /// מתעדכן ע"י NotificationListener של גלילת התוכן.
  late final ValueNotifier<bool> _secondaryRowVisible;

  static const List<String> _orderedTopCategories = [
    'תנ"ך',
    'מדרש',
    'משנה',
    'תלמוד בבלי',
    'תלמוד ירושלמי',
    'תוספתא',
    'הלכה',
    'שו"ת',
    'קבלה',
    'סדר התפילה',
    'מחשבת ישראל',
    'חסידות',
    'ספרי מוסר',
    'מילונים וספרי יעץ',
    'לימוד יומי',
    'ספרות עזר',
    'בית שני',
  ];

  int _getTopCategoryOrder(Category cat) {
    final normalized =
        cat.title.replaceAll('\u05F4', '"').replaceAll('\u05F3', "'");
    final idx = _orderedTopCategories.indexOf(normalized);
    return idx >= 0 ? idx : _orderedTopCategories.length + cat.order;
  }

  static int _normalizeOrder(int order) =>
      order >= 0 ? order : 1000 + order.abs();

  bool _isPreviewPanelVisible(SettingsState settingsState) =>
      _previewPanelOverrideVisible ?? settingsState.libraryShowPreview;

  _LibrarySidePanel _effectiveSidePanel(SettingsState settingsState) {
    if (_activeSidePanel == _LibrarySidePanel.settings) {
      return _LibrarySidePanel.settings;
    }
    if (_isPreviewPanelVisible(settingsState)) {
      return _LibrarySidePanel.preview;
    }
    return _LibrarySidePanel.none;
  }

  void _openSettingsPanel() =>
      setState(() => _activeSidePanel = _LibrarySidePanel.settings);

  void _closeSettingsPanel() {
    if (_activeSidePanel == _LibrarySidePanel.settings) {
      setState(() => _activeSidePanel = _LibrarySidePanel.none);
    }
  }

  void _showPreviewPanel(SettingsState s) {
    setState(() {
      _activeSidePanel = _LibrarySidePanel.preview;
      _previewPanelOverrideVisible = s.libraryShowPreview ? null : true;
    });
  }

  void _hidePreviewPanel(SettingsState s) {
    setState(() {
      _activeSidePanel = _LibrarySidePanel.none;
      _previewPanelOverrideVisible = s.libraryShowPreview ? false : null;
    });
  }

  void _togglePreviewPanel(SettingsState s) {
    if (_effectiveSidePanel(s) == _LibrarySidePanel.preview) {
      _hidePreviewPanel(s);
    } else {
      _showPreviewPanel(s);
    }
  }

  void _syncLibraryPanelController() {
    LibraryPanelController.register(
      isSettingsPanelOpen: () => _activeSidePanel == _LibrarySidePanel.settings,
      showSettingsPanel: _openSettingsPanel,
      closeSettingsPanel: _closeSettingsPanel,
      openPreviewPanel: _showPreviewPanel,
      closePreviewPanel: _hidePreviewPanel,
      togglePreviewPanel: _togglePreviewPanel,
    );
  }

  void _unsyncLibraryPanelController() => LibraryPanelController.unregister();

  late final FileSyncBloc _fileSyncBloc;

  @override
  void initState() {
    super.initState();
    _secondaryRowVisible = ValueNotifier<bool>(true);
    context.read<LibraryBloc>().add(LoadLibrary());
    _syncLibraryPanelController();
    _fileSyncBloc = FileSyncBloc(
      repository: FileSyncRepository(
        githubOwner: 'Otzaria',
        repositoryName: 'SeforimLibrary',
      ),
    );
  }

  @override
  void dispose() {
    _firstSearchResultFocusNode.dispose();
    _secondaryRowVisible.dispose();
    _unsyncLibraryPanelController();
    _fileSyncBloc.close();
    super.dispose();
  }

  // ── טיפול בגלילה לשליטה בשורה השניה ────────────────────────────────────

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      if (delta > 3 && _secondaryRowVisible.value) {
        _secondaryRowVisible.value = false;
      } else if (delta < -3 && !_secondaryRowVisible.value) {
        _secondaryRowVisible.value = true;
      }
    }
    return false;
  }

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return MultiBlocListener(
      listeners: [
        BlocListener<LibraryBloc, LibraryState>(
          listenWhen: (previous, current) =>
              previous.isLoading && !current.isLoading && current.library != null,
          listener: (context, state) {
            final book = _getFirstDisplayedBook(state.currentCategory ?? state.library!);
            if (book != null) {
              context.read<LibraryBloc>().add(SelectBookForPreview(book));
            }
          },
        ),
        BlocListener<SettingsBloc, SettingsState>(
          listenWhen: (p, c) =>
              p.showExternalBooks != c.showExternalBooks ||
              p.autoSyncCatalogs != c.autoSyncCatalogs,
          listener: (context, s) =>
              unawaited(ExternalCatalogSettingsHelper.maybeAutoSyncCatalogs(s)),
        ),
        BlocListener<SettingsBloc, SettingsState>(
          listenWhen: (p, c) =>
              p.showExternalBooks != c.showExternalBooks ||
              p.showHebrewBooks != c.showHebrewBooks ||
              p.showOtzarHachochma != c.showOtzarHachochma,
          listener: (context, s) {
            final query = context.read<LibraryBloc>().state.searchQuery;
            if (query != null && query.trim().length >= 3) {
              _searchWithSettings(context, s);
            }
          },
        ),
      ],
      child: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, settingsState) {
          return BlocBuilder<LibraryBloc, LibraryState>(
            buildWhen: (p, c) =>
                p.isLoading != c.isLoading ||
                p.error != c.error ||
                p.library != c.library ||
                p.currentCategory != c.currentCategory ||
                p.searchResults != c.searchResults ||
                p.searchQuery != c.searchQuery ||
                p.selectedTopics != c.selectedTopics,
            builder: (context, state) {
              if (state.error != null) {
                return Center(child: Text('Error: ${state.error}'));
              }
              if (state.library == null && !state.isLoading) {
                return const Center(child: Text('No library data available'));
              }

              return Stack(
                children: [
                  Scaffold(
                    backgroundColor: AppSurfaces.panelBackground(context),
                    // ── הסרנו את appBar — הסרגל עכשיו חלק מה-body ──
                    body: Column(
                      children: [
                        // ─── AppTopBar חדש ────────────────────────────
                        _buildAppTopBar(context, state, settingsState),
                        // ─── תוכן ─────────────────────────────────────
                        Expanded(
                          child: NotificationListener<ScrollNotification>(
                            onNotification: _handleScrollNotification,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final screenWidth = constraints.maxWidth;
                                const minPreviewWidth = 8.0;
                                final previewWidth =
                                    settingsState.libraryViewMode == 'list'
                                        ? screenWidth * 2 / 3
                                        : screenWidth / 3;
                                final maxPreviewWidth = (screenWidth - 350)
                                    .clamp(minPreviewWidth, screenWidth);

                                final panelMode =
                                    _effectiveSidePanel(settingsState);

                                return Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        children: [
                                          // filter chips — רק בגוף (לא בשורה השניה)
                                          // נשמרת כאן למקרה שהמשתמש מעדיף אותן בגוף
                                          // ניתן להעביר ל-secondaryRow אם רצוי
                                          Expanded(
                                            child: _buildContent(state),
                                          ),
                                        ],
                                      ),
                                    ),
                                    AnimatedSize(
                                      duration:
                                          const Duration(milliseconds: 300),
                                      curve: Curves.easeInOut,
                                      alignment: Alignment.centerRight,
                                      child: panelMode == _LibrarySidePanel.none
                                          ? const SizedBox(width: 0)
                                          : Padding(
                                              padding:
                                                  const EdgeInsets.all(8.0),
                                              child: ResizablePreviewPanel(
                                                key: ValueKey(panelMode.name),
                                                initialWidth: previewWidth,
                                                minWidth: minPreviewWidth,
                                                maxWidth: maxPreviewWidth,
                                                child: _buildSidePanel(
                                                  context,
                                                  settingsState,
                                                  panelMode,
                                                ),
                                              ),
                                            ),
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
                  if (state.isLoading) _buildLoadingOverlay(context),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // ── AppTopBar ────────────────────────────────────────────────────────────

  Widget _buildAppTopBar(
    BuildContext context,
    LibraryState state,
    SettingsState settingsState,
  ) {
    final isCompact = settingsState.compactMenuMode;
    final previewSelected =
        _effectiveSidePanel(settingsState) == _LibrarySidePanel.preview;
    final settingsSelected = _activeSidePanel == _LibrarySidePanel.settings;

    // ── כפתורי ניווט (Leading/ימין) ─────────────────────────────────────
    final navActions = _buildNavActions(context, state, settingsState);

    // ── שדה חיפוש (Center) ──────────────────────────────────────────────
    final searchField = _buildSearchBar(state, isCompact);

    // ── כפתורי trailing (שמאל) ──────────────────────────────────────────
    final trailingItems = _buildTrailingItems(
      context,
      settingsState,
      isCompact,
      previewSelected,
      settingsSelected,
    );

    // ── שורה שניה ────────────────────────────────────────────────────────
    final secondaryRow = _buildSecondaryRow(context, state, settingsState);

    return AppTopBar(
      isCompact: isCompact,
      secondaryRowVisible: _secondaryRowVisible,
      leadingItems: [
        AppTopBarItem(widget: navActions),
      ],
      center: searchField,
      trailingItems: trailingItems,
      secondaryRow: secondaryRow,
    );
  }

  // ── כפתורי ניווט ─────────────────────────────────────────────────────────

  Widget _buildNavActions(
    BuildContext context,
    LibraryState state,
    SettingsState settingsState,
  ) {
    final isCompact = settingsState.compactMenuMode;
    final screenWidth = MediaQuery.of(context).size.width;

    int maxButtons;
    if (screenWidth < 400) {
      maxButtons = 2;
    } else if (screenWidth < 600) {
      maxButtons = 3;
    } else if (screenWidth < 800) {
      maxButtons = 4;
    } else {
      maxButtons = 5;
    }

    return ResponsiveActionBar(
      key: ValueKey('action-bar-offline-${settingsState.isOfflineMode}'),
      actions: _buildPrioritizedLibraryActions(
          context, state, settingsState, isCompact),
      alwaysInMenu: const [],
      originalOrder: _buildOriginalOrderLibraryActions(
          context, state, settingsState, isCompact),
      maxVisibleButtons: maxButtons,
      overflowOnRight: true,
    );
  }

  // ── Trailing items ────────────────────────────────────────────────────────

  List<AppTopBarItem> _buildTrailingItems(
    BuildContext context,
    SettingsState settingsState,
    bool isCompact,
    bool previewSelected,
    bool settingsSelected,
  ) {
    final items = <AppTopBarItem>[];

    // DafYomi — רק במצב desktop (compact) עם מספיק מקום
    if (isCompact) {
      items.add(
        AppTopBarItem(
          widget: DafYomi(
            compact: true,
            onDafYomiTap: (tractate, daf) =>
                openDafYomiBook(context, tractate, ' $daf.'),
            onCalendarTap: () {
              (moreScreenKey.currentState as dynamic)?.resetToCalendar();
              context
                  .read<NavigationBloc>()
                  .add(const NavigateToScreen(Screen.more));
            },
          ),
        ),
      );
    }

    // תצוגה מקדימה
    items.add(AppTopBarItem(
      dividerBefore: true,
      widget: ToolbarActionButton(
        compact: isCompact,
        tooltip: previewSelected ? 'הסתר תצוגה מקדימה' : 'הצג תצוגה מקדימה',
        icon: previewSelected
            ? FluentIcons.eye_off_24_regular
            : FluentIcons.eye_24_regular,
        selected: previewSelected,
        onPressed: () =>
            _togglePreviewPanel(context.read<SettingsBloc>().state),
      ),
    ));

    // הגדרות
    items.add(AppTopBarItem(
      widget: ToolbarActionButton(
        compact: isCompact,
        tooltip: settingsSelected ? 'סגור הגדרות ספרייה' : 'הגדרות ספרייה',
        icon: settingsSelected
            ? FluentIcons.settings_24_filled
            : FluentIcons.settings_24_regular,
        selected: settingsSelected,
        onPressed: () {
          if (settingsSelected) {
            _closeSettingsPanel();
          } else {
            _openSettingsPanel();
          }
        },
      ),
    ));

    return items;
  }

  // ── שורה שניה (secondary row) ─────────────────────────────────────────────

  Widget? _buildSecondaryRow(
    BuildContext context,
    LibraryState state,
    SettingsState settingsState,
  ) {
    final isCompact = settingsState.compactMenuMode;
    final searchText =
        context.read<FocusRepository>().librarySearchController.text;
    final hasSearchResults =
        searchText.length > 2 && state.searchResults != null;

    final List<Widget> children = [];

    // DafYomi בשורה שניה — רק במצב touch (לא desktop)
    if (!isCompact) {
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DafYomi(
                compact: false,
                onDafYomiTap: (tractate, daf) =>
                    openDafYomiBook(context, tractate, ' $daf.'),
                onCalendarTap: () {
                  (moreScreenKey.currentState as dynamic)?.resetToCalendar();
                  context
                      .read<NavigationBloc>()
                      .add(const NavigateToScreen(Screen.more));
                },
              ),
            ],
          ),
        ),
      );
    }

    // filter chips — כשיש חיפוש פעיל
    if (hasSearchResults) {
      final topicsWidget = _buildTopicsSelection(context, state, settingsState);
      if (topicsWidget != null) {
        children.add(topicsWidget);
      }
    }

    if (children.isEmpty) return null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(
          height: 1,
          thickness: 1,
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
        ),
        ...children,
      ],
    );
  }

  // ── שדה חיפוש ────────────────────────────────────────────────────────────

  Widget _buildSearchBar(LibraryState state, bool isCompact) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        final focusRepository = context.read<FocusRepository>();
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.tab): () {
              final moved = _focusFirstSearchResult(state);
              if (!moved) {
                FocusScope.of(context).nextFocus();
              }
            },
          },
          child: OtzariaSearchField(
            controller: focusRepository.librarySearchController,
            focusNode: focusRepository.librarySearchFocusNode,
            autofocus: true,
            slim: isCompact,
            hintText: 'איתור ספר או מחבר ב${state.currentCategory?.title ?? ""}',
            maxWidth: isCompact ? 500 : 400,
            onChanged: (value) {
              context.read<LibraryBloc>().add(UpdateSearchQuery(value));
              context.read<LibraryBloc>().add(const SelectTopics([]));
              _update(context, state, settingsState);
            },
            onClear: () {
              _update(context, state, settingsState);
              _refocusSearchBar();
            },
          ),
        );
      },
    );
  }

  // ── filter chips ──────────────────────────────────────────────────────────

  Widget? _buildTopicsSelection(
    BuildContext context,
    LibraryState state,
    SettingsState settingsState,
  ) {
    if (state.searchResults == null) return null;

    final categoryTopics = [
      'תנך',
      'מדרש',
      'משנה',
      'תלמוד בבלי',
      'תלמוד ירושלמי',
      'הלכה',
      'משנה תורה',
      'שולחן ערוך',
      'חסידות',
      'קבלה',
      'ספרי מוסר',
      'שות',
      'ראשונים',
      'אחרונים',
      'מחברי זמננו',
    ];
    final allTopics = _getAllTopics(state.searchResults!);
    final relevantTopics = categoryTopics.where(allTopics.contains).toList();
    if (relevantTopics.isEmpty) return null;

    return FilterChipsSelector<String>(
      items: relevantTopics,
      selectedItems: state.selectedTopics ?? [],
      labelBuilder: (item) => item,
      wrapAlignment: WrapAlignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      onSelectionChanged: (list) {
        context.read<LibraryBloc>().add(SelectTopics(list));
        _update(context, state, settingsState);
        _refocusSearchBar();
      },
      chipBuilder: (context, item, isSelected) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        child: Chip(
          label: Text(item),
          backgroundColor:
              isSelected ? Theme.of(context).colorScheme.secondary : null,
          labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: isSelected
                    ? Theme.of(context).colorScheme.onSecondary
                    : null,
              ),
          labelPadding: EdgeInsets.zero,
        ),
      ),
    );
  }

  // ── Loading overlay ───────────────────────────────────────────────────────

  Widget _buildLoadingOverlay(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.3),
        child: Center(
          child: Container(
            width: 200,
            height: 80,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context)
                      .colorScheme
                      .shadow
                      .withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Center(child: _LoadingDotsText()),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  action builders  (זהים לקוד המקורי, עם הוספת compact)
  // ─────────────────────────────────────────────────────────────────────────

  ActionButtonData _buildSyncActionButton({required bool compact}) {
    return ActionButtonData(
      widget: BlocProvider.value(
        value: _fileSyncBloc,
        child: BlocConsumer<FileSyncBloc, FileSyncState>(
          listener: (context, syncState) {
            if ((syncState.status == FileSyncStatus.completed ||
                    syncState.status == FileSyncStatus.error) &&
                syncState.hasNewSync) {
              context.read<LibraryBloc>().add(RefreshLibrary());
            }
          },
          builder: (context, syncState) {
            final isSyncing = syncState.status == FileSyncStatus.syncing;
            final icon = switch (syncState.status) {
              FileSyncStatus.completed =>
                FluentIcons.checkmark_circle_24_regular,
              _ => FluentIcons.arrow_sync_24_regular,
            };
            final tooltip = switch (syncState.status) {
              FileSyncStatus.syncing => 'עצור סינכרון',
              FileSyncStatus.completed =>
                syncState.hasNewSync ? 'סנכרון הושלם' : 'אין עדכונים חדשים',
              FileSyncStatus.error => 'שגיאה בסינכרון - לחץ לנסות שוב',
              FileSyncStatus.initial => 'סינכרון',
            };

            return ToolbarActionButton(
              compact: compact,
              tooltip: tooltip,
              icon: icon,
              selected: isSyncing,
              onPressed: () {
                final bloc = context.read<FileSyncBloc>();
                switch (syncState.status) {
                  case FileSyncStatus.syncing:
                    bloc.add(const StopSync());
                  case FileSyncStatus.completed:
                  case FileSyncStatus.error:
                    bloc.add(const ResetState());
                  case FileSyncStatus.initial:
                    bloc.add(const StartSync());
                }
              },
            );
          },
        ),
      ),
      icon: FluentIcons.arrow_sync_24_regular,
      tooltip: 'סינכרון',
      onPressed: () => _fileSyncBloc.add(const StartSync()),
    );
  }

  List<ActionButtonData> _buildOriginalOrderLibraryActions(
    BuildContext context,
    LibraryState state,
    SettingsState settingsState,
    bool compact,
  ) {
    return [
      ActionButtonData(
        widget: ToolbarActionButton(
          compact: compact,
          tooltip: 'חזרה לתיקיה הקודמת',
          icon: FluentIcons.arrow_up_24_regular,
          onPressed: () => _handleNavigateUp(context, state, settingsState),
        ),
        icon: FluentIcons.arrow_up_24_regular,
        tooltip: 'חזרה לתיקיה הקודמת',
        onPressed: () => _handleNavigateUp(context, state, settingsState),
      ),
      ActionButtonData(
        widget: ToolbarActionButton(
          compact: compact,
          tooltip: 'חזרה לתיקיה הראשית',
          icon: FluentIcons.home_24_regular,
          onPressed: () => _handleNavigateHome(context, state, settingsState),
        ),
        icon: FluentIcons.home_24_regular,
        tooltip: 'חזרה לתיקיה הראשית',
        onPressed: () => _handleNavigateHome(context, state, settingsState),
      ),
      if (!settingsState.isOfflineMode)
        _buildSyncActionButton(compact: compact),
      ActionButtonData(
        widget: ToolbarActionButton(
          compact: compact,
          tooltip: 'טעינה מחדש של רשימת הספרים',
          icon: FluentIcons.arrow_clockwise_24_regular,
          onPressed: () => context.read<LibraryBloc>().add(RefreshLibrary()),
        ),
        icon: FluentIcons.arrow_clockwise_24_regular,
        tooltip: 'טעינה מחדש של רשימת הספרים',
        onPressed: () => context.read<LibraryBloc>().add(RefreshLibrary()),
      ),
    ];
  }

  List<ActionButtonData> _buildPrioritizedLibraryActions(
    BuildContext context,
    LibraryState state,
    SettingsState settingsState,
    bool compact,
  ) {
    return [
      ActionButtonData(
        widget: ToolbarActionButton(
          compact: compact,
          tooltip: 'חזרה לתיקיה הקודמת',
          icon: FluentIcons.arrow_up_24_regular,
          onPressed: () => _handleNavigateUp(context, state, settingsState),
        ),
        icon: FluentIcons.arrow_up_24_regular,
        tooltip: 'חזרה לתיקיה הקודמת',
        onPressed: () => _handleNavigateUp(context, state, settingsState),
      ),
      if (!settingsState.isOfflineMode)
        _buildSyncActionButton(compact: compact),
      ActionButtonData(
        widget: ToolbarActionButton(
          compact: compact,
          tooltip: 'חזרה לתיקיה הראשית',
          icon: FluentIcons.home_24_regular,
          onPressed: () => _handleNavigateHome(context, state, settingsState),
        ),
        icon: FluentIcons.home_24_regular,
        tooltip: 'חזרה לתיקיה הראשית',
        onPressed: () => _handleNavigateHome(context, state, settingsState),
      ),
      ActionButtonData(
        widget: ToolbarActionButton(
          compact: compact,
          tooltip: 'טעינה מחדש של רשימת הספרים',
          icon: FluentIcons.arrow_clockwise_24_regular,
          onPressed: () => context.read<LibraryBloc>().add(RefreshLibrary()),
        ),
        icon: FluentIcons.arrow_clockwise_24_regular,
        tooltip: 'טעינה מחדש של רשימת הספרים',
        onPressed: () => context.read<LibraryBloc>().add(RefreshLibrary()),
      ),
    ];
  }

  // ── Navigation handlers ───────────────────────────────────────────────────

  void _handleNavigateUp(
    BuildContext context,
    LibraryState state,
    SettingsState settingsState,
  ) {
    if (settingsState.libraryViewMode == 'list' &&
        _expandedCategories.isNotEmpty) {
      setState(() => _expandedCategories.remove(_expandedCategories.last));
    } else if (state.currentCategory?.parent != null) {
      setState(() => _depth = _depth > 0 ? _depth - 1 : 0);
      context.read<LibraryBloc>().add(NavigateUp());
      context.read<LibraryBloc>().add(const SearchBooks());
      _refocusSearchBar(selectAll: true);
    }
  }

  void _handleNavigateHome(
    BuildContext context,
    LibraryState state,
    SettingsState settingsState,
  ) {
    setState(() {
      _depth = 0;
      _expandedCategories.clear();
    });
    context.read<LibraryBloc>().add(LoadLibrary());
    context.read<FocusRepository>().librarySearchController.clear();
    _update(context, state, settingsState);
    _refocusSearchBar(selectAll: true);
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Content builders (זהים למקור)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildContent(LibraryState state) {
    if (state.library == null || state.currentCategory == null) {
      return const Center(child: SizedBox.shrink());
    }

    final settingsState = context.read<SettingsBloc>().state;
    if (settingsState.libraryViewMode == 'grid') {
      final items = state.searchResults != null
          ? _buildSearchResults(state.searchResults!)
          : _buildCategoryContent(state.currentCategory!);

      return FutureBuilder<List<Widget>>(
        future: items,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.hasData && snapshot.data!.isEmpty) {
            final focusRepository = context.read<FocusRepository>();
            return Center(
              child: Text(
                focusRepository.librarySearchController.text.isNotEmpty
                    ? 'אין תוצאות עבור "${focusRepository.librarySearchController.text}"'
                    : 'אין פריטים להצגה בתיקייה זו',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            );
          }
          return SingleChildScrollView(
            key: PageStorageKey(state.currentCategory),
            child: Column(children: snapshot.data!),
          );
        },
      );
    }

    if (state.searchResults != null) {
      return _buildSearchListView(state.searchResults!);
    }
    return _buildListView(state.currentCategory!);
  }

  Future<List<Widget>> _buildSearchResults(List<Book> books) async {
    // בניית כל הפריטים מראש
    final displayLimit = min(books.length, 100);

    return [
      _buildSearchResultsGrid(books, displayLimit),
    ];
  }

  Future<List<Widget>> _buildCategoryContent(Category category) async {
    List<Widget> items = [];
    final filteredBooks = category.books.toList();
    final filteredSubCategories = category.subCategories.toList();

    filteredBooks.sort((a, b) => a.order.compareTo(b.order));
    if (category is Library) {
      filteredSubCategories.sort(
          (a, b) => _getTopCategoryOrder(a).compareTo(_getTopCategoryOrder(b)));
    } else {
      filteredSubCategories.sort((a, b) =>
          _normalizeOrder(a.order).compareTo(_normalizeOrder(b.order)));
    }

    if (_depth != 0) {
      final bookWidgets =
          filteredBooks.map((book) => _buildBookItem(book)).toList();
      items.add(MyGridView(items: bookWidgets));
      if (filteredBooks.length > 20) {
        items.add(Center(
            child: TextButton(
          onPressed: () => _showAllBooksDialog(filteredBooks),
          child: Text('הצג עוד ${filteredBooks.length - 20} פריטים'),
        )));
      }
      for (Category subCategory in filteredSubCategories) {
        final subFilteredBooks = subCategory.books.toList();
        final subFilteredCategories = subCategory.subCategories.toList();
        subFilteredBooks.sort((a, b) => a.order.compareTo(b.order));
        subFilteredCategories.sort((a, b) => a.order.compareTo(b.order));
        items.add(Center(child: HeaderItem(category: subCategory)));
        final subCategoryItems = <Widget>[
          ...subFilteredBooks.map((book) => _buildBookItem(book)),
          ...subFilteredCategories.map(
            (cat) => CategoryGridItem(
              category: cat,
              onCategoryClickCallback: () => _openCategory(cat),
            ),
          ),
        ];
        if (subFilteredBooks.length > 20) {
          subCategoryItems.add(Center(
              child: TextButton(
            onPressed: () => _showAllBooksDialog(subFilteredBooks),
            child: Text('הצג עוד ${subFilteredBooks.length - 20} פריטים'),
          )));
        }
        items.add(MyGridView(items: subCategoryItems));
      }
    } else {
      final displayedBooks = filteredBooks.map((book) => _buildBookItem(book));
      final categoryItems = <Widget>[
        ...displayedBooks,
        ...filteredSubCategories.map(
          (cat) => CategoryGridItem(
            category: cat,
            onCategoryClickCallback: () => _openCategory(cat),
          ),
        ),
      ];
      items.add(MyGridView(items: categoryItems));
      if (filteredBooks.length > 20) {
        items.add(Center(
            child: TextButton(
          onPressed: () => _showAllBooksDialog(filteredBooks),
          child: Text('הצג עוד ${filteredBooks.length - 20} פריטים'),
        )));
      }
    }

    return items;
  }

  Widget _buildBookItem(
    Book book, {
    bool showTopics = false,
    FocusNode? focusNode,
  }) {
    if (book is ExternalLibraryBook) {
      return BookGridItem(
        book: book,
        onBookClickCallback: () => _openOtzarBook(book),
        showTopics: showTopics,
        focusNode: focusNode,
      );
    }

    return BlocBuilder<LibraryBloc, LibraryState>(
      buildWhen: (previous, current) =>
          (previous.previewBook != current.previewBook) &&
          (previous.previewBook == book || current.previewBook == book),
      builder: (context, state) {
        final isSelected = state.previewBook == book;
        return GestureDetector(
          onDoubleTap: () {
            final index = book is PdfBook ? 1 : 0;
            _openBookInReader(book, index);
          },
          child: Container(
            decoration: isSelected
                ? BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  )
                : null,
            child: BookGridItem(
              book: book,
              showTopics: showTopics,
              focusNode: focusNode,
              onBookClickCallback: () {
                final settingsState = context.read<SettingsBloc>().state;
                if (settingsState.libraryShowPreview) {
                  _showBookPreview(book);
                } else {
                  final index = book is PdfBook ? 1 : 0;
                  _openBookInReader(book, index);
                }
              },
              onBookDeleted: () {
                if (context.mounted) {
                  context.read<LibraryBloc>().add(RefreshLibrary());
                }
              },
            ),
          ),
        );
      },
    );
  }

  void _showBookPreview(Book book) =>
      context.read<LibraryBloc>().add(SelectBookForPreview(book));

  Widget _buildSearchListView(List<Book> books) {
    return ListView.builder(
      itemCount: books.length,
      itemBuilder: (context, index) {
        return _buildListBookItem(
          books[index],
          0,
          focusNode: index == 0 ? _firstSearchResultFocusNode : null,
        );
      },
    );
  }

  Widget _buildListView(Category category) {
    return ListView(children: _buildCategoryTree(category, 0));
  }

  List<Widget> _buildCategoryTree(Category category, int level) {
    List<Widget> widgets = [];
    final filteredBooks = category.books.toList();
    final filteredSubCategories = category.subCategories.toList();

    filteredBooks.sort((a, b) => a.order.compareTo(b.order));
    if (category is Library) {
      filteredSubCategories.sort(
          (a, b) => _getTopCategoryOrder(a).compareTo(_getTopCategoryOrder(b)));
    } else {
      filteredSubCategories.sort((a, b) =>
          _normalizeOrder(a.order).compareTo(_normalizeOrder(b.order)));
    }

    for (final subCategory in filteredSubCategories) {
      final isExpanded = _expandedCategories.contains(subCategory.path);
      widgets.add(_buildListCategoryItem(subCategory, level, isExpanded));
      if (isExpanded) {
        widgets.addAll(_buildCategoryTree(subCategory, level + 1));
      }
    }

    const int displayLimit = 500;
    for (int i = 0; i < filteredBooks.length && i < displayLimit; i++) {
      widgets.add(_buildListBookItem(filteredBooks[i], level));
    }
    if (filteredBooks.length > displayLimit) {
      final remaining = filteredBooks.length - displayLimit;
      widgets.add(InkWell(
        onTap: () => _showAllBooksDialog(filteredBooks),
        child: Container(
          padding: EdgeInsets.only(
            right: 16.0 + (level * 24.0),
            left: 16.0,
            top: 10.0,
            bottom: 10.0,
          ),
          child: Text('הצג עוד $remaining פריטים',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  )),
        ),
      ));
    }
    return widgets;
  }

  Widget _buildListCategoryItem(Category category, int level, bool isExpanded) {
    return InkWell(
      onTap: () {
        setState(() {
          if (isExpanded) {
            _expandedCategories.remove(category.path);
          } else {
            _expandedCategories.add(category.path);
          }
        });
      },
      child: Container(
        padding: EdgeInsets.only(
          right: 16.0 + (level * 24.0),
          left: 16.0,
          top: 12.0,
          bottom: 12.0,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            Icon(
              isExpanded
                  ? FluentIcons.folder_open_24_filled
                  : FluentIcons.folder_24_regular,
              color: Theme.of(context).colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LibraryOverflowTooltipText(
                text: category.title,
                maxLines: 1,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
            Icon(
              isExpanded
                  ? FluentIcons.chevron_up_24_regular
                  : FluentIcons.chevron_down_24_regular,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  /// פריט ספר בתצוגת רשימה
  Widget _buildListBookItem(
    Book book,
    int level, {
    FocusNode? focusNode,
  }) {
    if (book is ExternalLibraryBook) {
      return _buildExternalBookListItem(book, level, focusNode: focusNode);
    }
    return BlocBuilder<LibraryBloc, LibraryState>(
      buildWhen: (previous, current) =>
          (previous.previewBook != current.previewBook) &&
          (previous.previewBook == book || current.previewBook == book),
      builder: (context, state) {
        final isSelected = state.previewBook == book;
        return InkWell(
          focusNode: focusNode,
          onTap: () {
            final settingsState = context.read<SettingsBloc>().state;
            if (settingsState.libraryShowPreview) {
              _showBookPreview(book);
            } else {
              final index = book is PdfBook ? 1 : 0;
              _openBookInReader(book, index);
            }
          },
          onDoubleTap: () {
            final index = book is PdfBook ? 1 : 0;
            _openBookInReader(book, index);
          },
          child: Container(
            padding: EdgeInsets.only(
              right: 16.0 + (level * 24.0),
              left: 16.0,
              top: 10.0,
              bottom: 10.0,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.3)
                  : null,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              textDirection: TextDirection.rtl,
              children: [
                Icon(
                  book is PdfBook
                      ? FluentIcons.document_pdf_24_regular
                      : FluentIcons.document_text_24_regular,
                  color: Theme.of(context).colorScheme.secondary,
                  size: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      LibraryOverflowTooltipText(
                        text: book.title,
                        textDirection: TextDirection.rtl,
                        maxLines: 1,
                        textAlign: TextAlign.right,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                      ),
                      if (book.author != null && book.author!.isNotEmpty)
                        LibraryOverflowTooltipText(
                          text: book.author!,
                          textDirection: TextDirection.rtl,
                          maxLines: 1,
                          textAlign: TextAlign.right,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// פריט ספר חיצוני בתצוגת רשימה
  Widget _buildExternalBookListItem(
    ExternalLibraryBook book,
    int level, {
    FocusNode? focusNode,
  }) {
    return InkWell(
      focusNode: focusNode,
      onTap: () => _openOtzarBook(book),
      child: Container(
        padding: EdgeInsets.only(
          right: 16.0 + (level * 24.0) + 32.0,
          left: 16.0,
          top: 10.0,
          bottom: 10.0,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            Image.asset(
              book.link.toString().contains('tablet.otzar.org')
                  ? 'assets/logos/otzar.ico'
                  : 'assets/logos/hebrew_books.png',
              width: 18,
              height: 18,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  LibraryOverflowTooltipText(
                    text: book.title,
                    textDirection: TextDirection.rtl,
                    maxLines: 1,
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                  if (book.author != null && book.author!.isNotEmpty)
                    LibraryOverflowTooltipText(
                      text: book.author!,
                      textDirection: TextDirection.rtl,
                      maxLines: 1,
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                ],
              ),
            ),
            Icon(
              FluentIcons.open_24_regular,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  void _openBookInReader(Book book, int index) =>
      openBook(context, book, index, '');

  /// מחזיר את הספר הראשון שיוצג בפועל בקטגוריה, לפי אותו סדר תצוגה כמו _buildCategoryContent
  Book? _getFirstDisplayedBook(Category category) {
    final books = category.books.toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    if (books.isNotEmpty) return books.first;

    final subs = category.subCategories.toList();
    if (category is Library) {
      subs.sort((a, b) => _getTopCategoryOrder(a).compareTo(_getTopCategoryOrder(b)));
    } else {
      subs.sort((a, b) => _normalizeOrder(a.order).compareTo(_normalizeOrder(b.order)));
    }
    for (final sub in subs) {
      final book = _getFirstDisplayedBook(sub);
      if (book != null) return book;
    }
    return null;
  }

  void _openCategory(Category category) {
    setState(() => _depth++);
    context.read<LibraryBloc>().add(NavigateToCategory(category));
    final book = _getFirstDisplayedBook(category);
    if (book != null) {
      context.read<LibraryBloc>().add(SelectBookForPreview(book));
    }
    _refocusSearchBar();
  }

  void _openOtzarBook(ExternalLibraryBook book) {
    showDialog(
      context: context,
      builder: (ctx) => OtzarBookDialog(book: book),
    );
    _refocusSearchBar();
  }

  void _showAllBooksDialog(List<Book> books) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('כל הספרים (${books.length})'),
        content: SizedBox(
          width: 600,
          height: 400,
          child: ListView.builder(
            itemCount: books.length,
            itemBuilder: (context, index) =>
                _buildListBookItem(books[index], 0),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('סגור'),
          ),
        ],
      ),
    );
  }

  List<String> _getAllTopics(List<Book> books) {
    final Set<String> topics = {};
    for (final book in books) {
      topics.addAll(book.topics.split(', '));
    }
    return topics.toList();
  }

  void _update(
      BuildContext context, LibraryState state, SettingsState settingsState) {
    final searchText =
        context.read<FocusRepository>().librarySearchController.text;
    final cleanSearchText = searchText.replaceAll('"', '');
    context.read<LibraryBloc>().add(UpdateSearchQuery(cleanSearchText));
    _searchWithSettings(context, settingsState);
    setState(() {});
    _refocusSearchBar();
  }

  void _searchWithSettings(BuildContext context, SettingsState settingsState) {
    context.read<LibraryBloc>().add(SearchBooks(
          showHebrewBooks:
              settingsState.showExternalBooks && settingsState.showHebrewBooks,
          showOtzarHachochma: settingsState.showExternalBooks &&
              settingsState.showOtzarHachochma,
        ));
  }

  void _refocusSearchBar({bool selectAll = false}) {
    context
        .read<FocusRepository>()
        .requestLibrarySearchFocus(selectAll: selectAll);
  }

  bool _focusFirstSearchResult(LibraryState state) {
    final results = state.searchResults;
    if (results == null || results.isEmpty) {
      return false;
    }

    if (_firstSearchResultFocusNode.canRequestFocus) {
      _firstSearchResultFocusNode.requestFocus();
      return true;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (_firstSearchResultFocusNode.canRequestFocus) {
        _firstSearchResultFocusNode.requestFocus();
      }
    });
    return true;
  }

  Widget _buildSearchResultsGrid(List<Book> books, int displayLimit) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount =
            (constraints.maxWidth ~/ 250).clamp(1, 5).toInt();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 45),
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  //max number of items per row is 5 and min is 1
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: 2,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4),
              itemCount: displayLimit,
              itemBuilder: (context, index) {
                final orderIndex = index;
                final focusNode =
                    index == 0 ? _firstSearchResultFocusNode : null;

                return FocusTraversalOrder(
                  order: NumericFocusOrder(orderIndex.toDouble()),
                  child: _buildBookItem(
                    books[index],
                    showTopics: true,
                    focusNode: focusNode,
                  ),
                );
              },
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSidePanel(
    BuildContext context,
    SettingsState settingsState,
    _LibrarySidePanel panelMode,
  ) {
    final theme = Theme.of(context);
    final borderColor = theme.colorScheme.outline.withValues(alpha: 0.3);
    final panelColor = panelMode == _LibrarySidePanel.settings
        ? AppSurfaces.panelBackground(context)
        : theme.colorScheme.surface;

    return Container(
      decoration: BoxDecoration(
        color: panelColor,
        border: Border.all(color: borderColor, width: 1.0),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7.0),
        child: switch (panelMode) {
          _LibrarySidePanel.settings => SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: LibrarySettingsPanel(hebrewBooksPathWidget: null),
              ),
            ),
          _LibrarySidePanel.preview => BlocBuilder<LibraryBloc, LibraryState>(
              buildWhen: (p, c) => p.previewBook != c.previewBook,
              builder: (context, previewState) => GestureDetector(
                onDoubleTap: () {
                  if (previewState.previewBook != null) {
                    _openBookInReader(previewState.previewBook!, 0);
                  }
                },
                child: BookPreviewPanel(
                  book: previewState.previewBook,
                  onOpenInReader: (index) {
                    if (previewState.previewBook != null) {
                      _openBookInReader(previewState.previewBook!, index);
                    }
                  },
                  onClose: () => _hidePreviewPanel(settingsState),
                ),
              ),
            ),
          _LibrarySidePanel.none => const SizedBox.shrink(),
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _LoadingDotsText (זהה למקור)
// ─────────────────────────────────────────────────────────────────────────────

class _LoadingDotsText extends StatefulWidget {
  const _LoadingDotsText();

  @override
  State<_LoadingDotsText> createState() => _LoadingDotsTextState();
}

class _LoadingDotsTextState extends State<_LoadingDotsText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = _controller.value;
        int dots;
        if (progress < 0.25) {
          dots = 0;
        } else if (progress < 0.5) {
          dots = 1;
        } else if (progress < 0.75) {
          dots = 2;
        } else {
          dots = 3;
        }
        final dotsString = '.' * dots + ' ' * (3 - dots);
        return Text(
          'טוען ספרייה$dotsString',
          style: Theme.of(context).textTheme.bodyMedium,
        );
      },
    );
  }
}

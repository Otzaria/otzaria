import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/external_catalog/view/external_catalog_settings_helper.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/tools/calendar/helpers/daf_yomi_navigation.dart';
import 'package:otzaria/file_sync/bloc/file_sync_bloc.dart';
import 'package:otzaria/file_sync/bloc/file_sync_event.dart';
import 'package:otzaria/file_sync/bloc/file_sync_state.dart';
import 'package:otzaria/library/view/library_daf_yomi.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/widgets/lists/filter_chips_widget.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';
import 'package:otzaria/library/view/grid_items.dart';
import 'package:otzaria/library/view/otzar_book_dialog.dart';
import 'package:otzaria/library/view/book_preview_panel.dart';
import 'package:otzaria/library/view/library_panel_controller.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';
import 'package:otzaria/utils/navigation/open_book.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria/widgets/layout/context_overlay_panel.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';

// ── קבועים ────────────────────────────────────────────────────────────────────

/// רוחב מינימלי להצגת LibraryDafYomi בשורה הראשית (לא בשורה שניה)
const double _kDafYomiInlineMinWidth = 820.0;

/// דיבאונס לגלילה (ms) — מונע rebuild חוזר
const int _kScrollDebounceMs = 100;

/// דיבאונס לחיפוש ספרים — מונע הרצת חיפוש כבד על כל אות.
const Duration _kLibrarySearchDebounceDuration = Duration(milliseconds: 250);

enum _LibraryListItemStyle { root, groupedRoot, grouped, search }

/// מחשב רוחב תקין לחלונית התצוגה המקדימה לפי הרוחב הפנוי בספרייה.
@visibleForTesting
({double paneWidth, double minPaneWidth, double maxPaneWidth})
    calculateLibraryPreviewPaneWidths({
  required double availableWidth,
  required String viewMode,
  double? paneWidthOverride,
}) {
  const preferredMinPaneWidth = 280.0;
  const previewWidthFactorGrid = 0.35;
  const previewWidthFactorList = 0.60;
  final minPaneWidth = min(preferredMinPaneWidth, max(0.0, availableWidth));
  final previewWidth = viewMode == 'list'
      ? availableWidth * previewWidthFactorList
      : availableWidth * previewWidthFactorGrid;
  final maxPaneWidth = max(minPaneWidth, availableWidth - 350);
  final paneWidth = (paneWidthOverride ?? previewWidth)
      .clamp(minPaneWidth, maxPaneWidth)
      .toDouble();

  return (
    paneWidth: paneWidth,
    minPaneWidth: minPaneWidth,
    maxPaneWidth: maxPaneWidth,
  );
}

// ─────────────────────────────────────────────────────────────────────────────

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
  final GlobalKey _tourLibraryKey = GlobalKey();
  final GlobalKey _tourLibrarySearchKey = GlobalKey();
  final GlobalKey _tourBookCardKey = GlobalKey();
  final Map<String, GlobalKey> _tourCategoryKeys = {};
  Book? _tourPreviewBook;
  Rect? _lastTourBookCardRect;
  final Set<String> _expandedCategories = {};
  final _settingsPanelOpen = ValueNotifier<bool>(false);
  double? _previewPaneWidthOverride;
  late final ValueNotifier<double> _topBarTotalHeight;

  /// שולט בנראות השורה השניה — מוגן מפני flicker ע"י debounce ב-AppTopBar
  late final ValueNotifier<bool> _secondaryRowVisible;

  /// דיבאונס timer לגלילה — מונע setState חוזר בכל scroll event
  Timer? _scrollDebounce;
  Timer? _searchDebounce;
  bool _lastScrollVisible = true;

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

  bool _isPreviewPanelVisible(SettingsState s) => s.libraryShowPreview;

  void _openSettingsPanel() => _settingsPanelOpen.value = true;

  void _closeSettingsPanel() => _settingsPanelOpen.value = false;

  void _showPreviewPanel(SettingsState s) {
    context.read<SettingsBloc>().add(const UpdateLibraryShowPreview(true));
  }

  void _hidePreviewPanel(SettingsState s) {
    context.read<SettingsBloc>().add(const UpdateLibraryShowPreview(false));
  }

  void _togglePreviewPanel(SettingsState s) {
    context
        .read<SettingsBloc>()
        .add(UpdateLibraryShowPreview(!s.libraryShowPreview));
  }

  void _syncLibraryPanelController() {
    LibraryPanelController.register(
      isSettingsPanelOpen: () => _settingsPanelOpen.value,
      showSettingsPanel: _openSettingsPanel,
      closeSettingsPanel: _closeSettingsPanel,
      openPreviewPanel: _showPreviewPanel,
      closePreviewPanel: _hidePreviewPanel,
      togglePreviewPanel: _togglePreviewPanel,
    );
  }

  @override
  void initState() {
    super.initState();
    _secondaryRowVisible = ValueNotifier<bool>(true);
    _topBarTotalHeight = ValueNotifier<double>(0);
    context.read<LibraryBloc>().add(LoadLibrary());
    _syncLibraryPanelController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ExternalCatalogSettingsHelper.maybeAutoSyncCatalogs(
          context.read<SettingsBloc>().state,
        ),
      );
    });
  }

  @override
  void deactivate() {
    _settingsPanelOpen.value = false;
    super.deactivate();
  }

  @override
  void dispose() {
    _firstSearchResultFocusNode.dispose();
    _scrollDebounce?.cancel();
    _searchDebounce?.cancel();
    _secondaryRowVisible.dispose();
    _topBarTotalHeight.dispose();
    _settingsPanelOpen.dispose();
    LibraryPanelController.unregister();
    super.dispose();
  }

  // ── גלילה עם דיבאונס ─────────────────────────────────────────────────────

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification) return false;
    final delta = notification.scrollDelta ?? 0;

    bool? desired;
    if (delta > 3) desired = false;
    if (delta < -3) desired = true;
    if (desired == null || desired == _lastScrollVisible) return false;

    _lastScrollVisible = desired;
    _scrollDebounce?.cancel();
    _scrollDebounce = Timer(
      const Duration(milliseconds: _kScrollDebounceMs),
      () {
        if (mounted) _secondaryRowVisible.value = desired!;
      },
    );
    return false;
  }

  // ── build ────────────────────────────────────────────────────────────────

  void closeTransientPanels() {
    _settingsPanelOpen.value = false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return MultiBlocListener(
      listeners: [
        BlocListener<LibraryBloc, LibraryState>(
          listenWhen: (previous, current) =>
              previous.isLoading &&
              !current.isLoading &&
              current.library != null,
          listener: (context, state) {
            final book =
                _getFirstDisplayedBook(state.currentCategory ?? state.library!);
            if (book != null) {
              context.read<LibraryBloc>().add(SelectBookForPreview(book));
            }
          },
        ),
        BlocListener<SettingsBloc, SettingsState>(
          listenWhen: (p, c) =>
              p.showExternalBooks != c.showExternalBooks ||
              p.autoSyncCatalogs != c.autoSyncCatalogs,
          listener: (ctx, s) =>
              unawaited(ExternalCatalogSettingsHelper.maybeAutoSyncCatalogs(s)),
        ),
        BlocListener<SettingsBloc, SettingsState>(
          listenWhen: (p, c) =>
              p.showExternalBooks != c.showExternalBooks ||
              p.showHebrewBooks != c.showHebrewBooks ||
              p.showOtzarHachochma != c.showOtzarHachochma,
          listener: (ctx, s) {
            final q = ctx.read<LibraryBloc>().state.searchQuery;
            if (q != null && q.trim().length >= 3) _searchWithSettings(ctx, s);
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
                key: _tourLibraryKey,
                children: [
                  Scaffold(
                    backgroundColor: AppSurfaces.panelBackground(context),
                    body: LayoutBuilder(
                      builder: (ctx, constraints) {
                        // האם יש מספיק מקום ל-DafYomi בשורה הראשית?
                        final dafYomiInline =
                            constraints.maxWidth >= _kDafYomiInlineMinWidth;
                        final isCompact = settingsState.compactMenuMode;

                        // גובה הסרגל הראשי (קבוע) — ממנו נגזר ה-padding התחתון
                        final primaryBarH = AppTopBar.barHeight(isCompact);

                        // גובה השורה השניה המקסימלי משמש כ-fallback לפני שיש
                        // מדידה בפועל מה-AppTopBar.
                        const double kSecondaryRowMaxH = 52.0;
                        final hasSecondaryRow = !dafYomiInline ||
                            (context
                                    .read<FocusRepository>()
                                    .librarySearchController
                                    .text
                                    .length >
                                2);
                        final topPad = hasSecondaryRow
                            ? primaryBarH + kSecondaryRowMaxH
                            : primaryBarH;

                        // Stack: תוכן מאחורה עם padding קבוע, סרגל צף מעל
                        // כך הסרגל לא גורם ל-reflow של ה-ScrollView בגלילה.
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: ValueListenableBuilder<double>(
                                valueListenable: _topBarTotalHeight,
                                builder: (context, topBarHeight, child) {
                                  final effectiveTopPad =
                                      topBarHeight > 0 ? topBarHeight : topPad;
                                  return AnimatedPadding(
                                    duration: const Duration(milliseconds: 180),
                                    curve: Curves.easeOut,
                                    padding:
                                        EdgeInsets.only(top: effectiveTopPad),
                                    child: child,
                                  );
                                },
                                child: NotificationListener<ScrollNotification>(
                                  onNotification: _handleScrollNotification,
                                  child: _buildBodyRow(
                                    ctx,
                                    state,
                                    settingsState,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: _buildAppTopBar(
                                ctx,
                                state,
                                settingsState,
                                dafYomiInline: dafYomiInline,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  ValueListenableBuilder<double>(
                    valueListenable: _topBarTotalHeight,
                    builder: (context, topBarHeight, _) {
                      return ValueListenableBuilder<bool>(
                        valueListenable: _settingsPanelOpen,
                        builder: (context, isOpen, _) {
                          return Positioned.fill(
                            top: topBarHeight,
                            child: _buildSettingsOverlay(context, isOpen),
                          );
                        },
                      );
                    },
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

  // ── AppTopBar ─────────────────────────────────────────────────────────────

  Widget _buildAppTopBar(
    BuildContext context,
    LibraryState state,
    SettingsState settingsState, {
    required bool dafYomiInline,
  }) {
    final isCompact = settingsState.compactMenuMode;
    final previewSelected = _isPreviewPanelVisible(settingsState);

    // ── Trailing items ────────────────────────────────────────────────────
    final trailingItems = <AppTopBarItem>[];

    // LibraryDafYomi: בשורה הראשית כשיש מקום, אחרת בשורה שניה
    if (dafYomiInline) {
      trailingItems.add(
        AppTopBarItem(
          widget: LibraryDafYomi(
            compact: isCompact,
            inlineDate: isCompact, // desktop: date + daf בשורה אחת
            maxWidth: 240,
            onDafYomiTap: (tractate, daf) =>
                openDafYomiBook(context, tractate, ' $daf.'),
          ),
        ),
      );
    }

    // אייקון לוח שנה — תמיד בשורה העליונה
    trailingItems.add(
      AppTopBarItem(
        widget: ToolbarActionButton(
          compact: isCompact,
          tooltip: 'פתח לוח שנה',
          icon: FluentIcons.calendar_24_regular,
          emphasis: ToolbarActionButtonEmphasis.subtle,
          onPressed: () {
            (moreScreenKey.currentState as dynamic)?.resetToCalendar();
            context.read<NavigationBloc>().add(
                  const NavigateToScreen(Screen.more),
                );
          },
        ),
      ),
    );

    trailingItems.addAll([
      AppTopBarItem(
        dividerBefore: true,
        widget: ToolbarActionButton(
          compact: isCompact,
          tooltip: previewSelected ? 'הסתר תצוגה מקדימה' : 'הצג תצוגה מקדימה',
          icon: previewSelected
              ? FluentIcons.eye_24_filled
              : FluentIcons.eye_24_regular,
          selected: previewSelected,
          onPressed: () =>
              _togglePreviewPanel(context.read<SettingsBloc>().state),
        ),
      ),
      AppTopBarItem(
        widget: ValueListenableBuilder<bool>(
          valueListenable: _settingsPanelOpen,
          builder: (context, isOpen, _) => ToolbarActionButton(
            compact: isCompact,
            tooltip: isOpen ? 'סגור הגדרות ספרייה' : 'הגדרות ספרייה',
            icon: isOpen
                ? FluentIcons.settings_24_filled
                : FluentIcons.settings_24_regular,
            selected: isOpen,
            onPressed: isOpen ? _closeSettingsPanel : _openSettingsPanel,
          ),
        ),
      ),
    ]);

    // ── Secondary row ─────────────────────────────────────────────────────
    final secondaryRow = _buildSecondaryRow(
      context,
      state,
      settingsState,
      showDafYomi: !dafYomiInline,
    );

    return AppTopBar(
      totalHeightNotifier: _topBarTotalHeight,
      scrollDebounceMs: _kScrollDebounceMs,
      secondaryRowVisible: secondaryRow != null ? _secondaryRowVisible : null,
      leadingItems: [
        AppTopBarItem(widget: _buildNavActions(context, state, settingsState)),
      ],
      center: _buildSearchBar(state, isCompact),
      trailingItems: trailingItems,
      secondaryRow: secondaryRow,
    );
  }

  // ── Secondary row ─────────────────────────────────────────────────────────

  Widget? _buildSecondaryRow(
    BuildContext context,
    LibraryState state,
    SettingsState settingsState, {
    required bool showDafYomi,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isCompact = settingsState.compactMenuMode;
    final searchText =
        context.read<FocusRepository>().librarySearchController.text;
    final hasSearch = searchText.length > 2 && state.searchResults != null;

    final children = <Widget>[];

    if (showDafYomi) {
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              LibraryDafYomi(
                compact: isCompact,
                inlineDate: false,
                maxWidth: 320,
                onDafYomiTap: (tractate, daf) =>
                    openDafYomiBook(context, tractate, ' $daf.'),
              ),
            ],
          ),
        ),
      );
    }

    if (hasSearch) {
      final topicsWidget = _buildTopicsSelection(context, state, settingsState);
      if (topicsWidget != null) children.add(topicsWidget);
    }

    if (children.isEmpty) return null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(
          height: 1,
          thickness: 1,
          color: cs.outline.withValues(alpha: 0.15),
        ),
        ...children,
      ],
    );
  }

  // ── Nav actions ──────────────────────────────────────────────────────────

  Widget _buildNavActions(
    BuildContext context,
    LibraryState state,
    SettingsState settingsState,
  ) {
    final isCompact = settingsState.compactMenuMode;
    final screenWidth = MediaQuery.of(context).size.width;

    final maxButtons = screenWidth < 400
        ? 2
        : screenWidth < 600
            ? 3
            : screenWidth < 800
                ? 4
                : 5;

    return ResponsiveActionBar(
      key: ValueKey('action-bar-offline-${settingsState.isOfflineMode}'),
      actions: _buildPrioritizedActions(
        context,
        state,
        settingsState,
        isCompact,
      ),
      alwaysInMenu: const [],
      originalOrder: _buildOriginalOrderActions(
        context,
        state,
        settingsState,
        isCompact,
      ),
      maxVisibleButtons: maxButtons,
      overflowOnRight: true,
    );
  }

  // ── Search bar ────────────────────────────────────────────────────────────

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
          child: KeyedSubtree(
            key: _tourLibrarySearchKey,
            child: OtzariaSearchField(
              controller: focusRepository.librarySearchController,
              focusNode: focusRepository.librarySearchFocusNode,
              autofocus: true,
              slim: isCompact,
              hintText:
                  'איתור ספר או מחבר ב${state.currentCategory?.title ?? ""}',
              maxWidth: isCompact ? 500 : 400,
              onChanged: (value) {
                context.read<LibraryBloc>().add(UpdateSearchQuery(value));
                context.read<LibraryBloc>().add(const SelectTopics([]));
                _scheduleSearchWithSettings(context, settingsState);
              },
              onClear: () {
                _update(context, state, settingsState,
                    restoreSearchFocus: true);
              },
            ),
          ),
        );
      },
    );
  }

  // ── Topics filter chips ───────────────────────────────────────────────────

  Widget? _buildTopicsSelection(
    BuildContext context,
    LibraryState state,
    SettingsState settingsState,
  ) {
    if (state.searchResults == null) return null;
    const categoryTopics = [
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
    final relevant = categoryTopics.where(allTopics.contains).toList();
    if (relevant.isEmpty) return null;

    return FilterChipsSelector<String>(
      items: relevant,
      selectedItems: state.selectedTopics ?? [],
      labelBuilder: (item) => item,
      wrapAlignment: WrapAlignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      onSelectionChanged: (list) {
        context.read<LibraryBloc>().add(SelectTopics(list));
        _update(context, state, settingsState, restoreSearchFocus: true);
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

  // ── Body row ──────────────────────────────────────────────────────────────

  Widget _buildBodyRow(
    BuildContext context,
    LibraryState state,
    SettingsState settingsState,
  ) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final previewPaneWidths = calculateLibraryPreviewPaneWidths(
          availableWidth: constraints.maxWidth,
          viewMode: settingsState.libraryViewMode,
          paneWidthOverride: _previewPaneWidthOverride,
        );
        final mainContent = _buildContent(state);

        return AdaptiveSidePane(
          isOpen: _isPreviewPanelVisible(settingsState),
          alignment: AlignmentDirectional.centerStart, // שמאל בעברית (RTL)
          mainContent: RepaintBoundary(child: mainContent),
          paneContent: _buildPreviewPane(settingsState),
          paneWidth: previewPaneWidths.paneWidth,
          minMainContentWidth: 420,
          onClose: () => _hidePreviewPanel(settingsState),
          onOpen: () => _showPreviewPanel(settingsState),
          paneColor: Theme.of(ctx).colorScheme.surface,
          isResizable: true,
          minPaneWidth: previewPaneWidths.minPaneWidth,
          maxPaneWidth: previewPaneWidths.maxPaneWidth,
          onPaneWidthChanged: (nextWidth) {
            _previewPaneWidthOverride = nextWidth;
          },
          autoHandleResponsiveVisibility: false,
          wrapPaneInFloatingPanel: false,
          narrowPaneBuilder: (context, paneContent) => Material(
            color: Theme.of(context).colorScheme.surface,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16),
                child: paneContent,
              ),
            ),
          ),
        );
      },
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
                  color: Theme.of(
                    context,
                  ).colorScheme.shadow.withValues(alpha: 0.2),
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

  // ── Action builders ───────────────────────────────────────────────────────

  ActionButtonData _buildSyncActionButton({required bool compact}) {
    return ActionButtonData(
      widget: BlocConsumer<FileSyncBloc, FileSyncState>(
        listener: (ctx, s) {
          if ((s.status == FileSyncStatus.completed ||
                  s.status == FileSyncStatus.error) &&
              s.hasNewSync) {
            ctx.read<LibraryBloc>().add(RefreshLibrary());
          }
        },
        builder: (ctx, syncState) {
          final isSyncing = syncState.status == FileSyncStatus.syncing;
          final icon = syncState.status == FileSyncStatus.completed
              ? FluentIcons.checkmark_circle_24_regular
              : FluentIcons.arrow_sync_24_regular;
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
              final b = ctx.read<FileSyncBloc>();
              switch (syncState.status) {
                case FileSyncStatus.syncing:
                  b.add(const StopSync());
                case FileSyncStatus.completed:
                case FileSyncStatus.error:
                  b.add(const ResetState());
                case FileSyncStatus.initial:
                  b.add(const StartSync());
              }
            },
          );
        },
      ),
      icon: FluentIcons.arrow_sync_24_regular,
      tooltip: 'סינכרון',
      onPressed: () {
        final b = context.read<FileSyncBloc>();
        if (b.state.status != FileSyncStatus.syncing) {
          b.add(const StartSync());
        }
      },
    );
  }

  void _refreshWithPersonalFolders() {
    context
        .read<CustomFoldersBloc>()
        .add(const RescanCustomFolders(showNoChangesMessage: false));
  }

  List<ActionButtonData> _buildOriginalOrderActions(
    BuildContext context,
    LibraryState state,
    SettingsState settingsState,
    bool compact,
  ) {
    return [
      ActionButtonData.simple(
        compact: compact,
        tooltip: 'חזרה לתיקיה הקודמת',
        icon: FluentIcons.arrow_up_24_regular,
        onPressed: () => _handleNavigateUp(context, state, settingsState),
      ),
      ActionButtonData.simple(
        compact: compact,
        tooltip: 'חזרה לתיקיה הראשית',
        icon: FluentIcons.home_24_regular,
        onPressed: () => _handleNavigateHome(context, state, settingsState),
      ),
      if (settingsState.canUseSoftwareAndBookUpdates)
        _buildSyncActionButton(compact: compact),
      ActionButtonData.simple(
        compact: compact,
        tooltip: 'טעינה מחדש',
        icon: FluentIcons.arrow_clockwise_24_regular,
        onPressed: _refreshWithPersonalFolders,
      ),
    ];
  }

  List<ActionButtonData> _buildPrioritizedActions(
    BuildContext context,
    LibraryState state,
    SettingsState settingsState,
    bool compact,
  ) {
    return [
      ActionButtonData.simple(
        compact: compact,
        tooltip: 'חזרה לתיקיה הקודמת',
        icon: FluentIcons.arrow_up_24_regular,
        onPressed: () => _handleNavigateUp(context, state, settingsState),
      ),
      if (settingsState.canUseSoftwareAndBookUpdates)
        _buildSyncActionButton(compact: compact),
      ActionButtonData.simple(
        compact: compact,
        tooltip: 'חזרה לתיקיה הראשית',
        icon: FluentIcons.home_24_regular,
        onPressed: () => _handleNavigateHome(context, state, settingsState),
      ),
      ActionButtonData.simple(
        compact: compact,
        tooltip: 'טעינה מחדש',
        icon: FluentIcons.arrow_clockwise_24_regular,
        onPressed: _refreshWithPersonalFolders,
      ),
    ];
  }

  void _handleNavigateUp(
    BuildContext context,
    LibraryState state,
    SettingsState settingsState,
  ) {
    if (settingsState.libraryViewMode == 'list' &&
        _expandedCategories.isNotEmpty) {
      setState(() => _expandedCategories.remove(_expandedCategories.last));
    } else if (state.currentCategory?.parent != null) {
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
      _expandedCategories.clear();
    });
    if (state.library != null) {
      context.read<LibraryBloc>().add(NavigateToCategory(state.library!));
    }
    context.read<FocusRepository>().librarySearchController.clear();
    _update(
      context,
      state,
      settingsState,
      restoreSearchFocus: true,
      selectAllOnRestore: true,
    );
  }

  // ── Content ───────────────────────────────────────────────────────────────

  Widget _buildContent(LibraryState state) {
    if (state.library == null || state.currentCategory == null) {
      return const Center(child: SizedBox.shrink());
    }
    final settingsState = context.read<SettingsBloc>().state;
    if (settingsState.libraryViewMode == 'grid') {
      if (state.searchResults != null) {
        final books = state.searchResults!;
        if (books.isEmpty) {
          final repo = context.read<FocusRepository>();
          return Center(
            child: Text(
              repo.librarySearchController.text.isNotEmpty
                  ? 'אין תוצאות עבור "${repo.librarySearchController.text}"'
                  : 'אין פריטים להצגה בתיקייה זו',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          );
        }
        final displayLimit = min(books.length, 100);
        return SingleChildScrollView(
          key: PageStorageKey(state.currentCategory),
          child: _buildSearchResultsGrid(books, displayLimit),
        );
      }
      final categoryItems = _buildCategoryContent(state.currentCategory!);
      if (categoryItems.isEmpty) {
        final repo = context.read<FocusRepository>();
        return Center(
          child: Text(
            repo.librarySearchController.text.isNotEmpty
                ? 'אין תוצאות עבור "${repo.librarySearchController.text}"'
                : 'אין פריטים להצגה בתיקייה זו',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        );
      }
      return SingleChildScrollView(
        key: PageStorageKey(state.currentCategory),
        child: Column(children: categoryItems),
      );
    }
    if (state.searchResults != null) {
      return _buildSearchListView(state.searchResults!);
    }
    return _buildListView(state.currentCategory!);
  }

  List<Widget> _buildCategoryContent(Category category) {
    final List<Widget> items = [];
    final filteredBooks = category.books.toList();
    final filteredSubCategories = category.subCategories.toList();
    filteredBooks.sort((a, b) => a.order.compareTo(b.order));
    if (category is Library) {
      filteredSubCategories.sort(
        (a, b) => _getTopCategoryOrder(a).compareTo(_getTopCategoryOrder(b)),
      );
    } else {
      filteredSubCategories.sort(
        (a, b) => _normalizeOrder(a.order).compareTo(_normalizeOrder(b.order)),
      );
    }

    final allItems = <Widget>[
      ...filteredSubCategories.map(
        (c) => KeyedSubtree(
          key: _tourCategoryKeys.putIfAbsent(c.path, GlobalKey.new),
          child: CategoryGridItem(
            category: c,
            onCategoryClickCallback: () => _openCategory(c),
          ),
        ),
      ),
    ];

    var attachedTourKey = false;
    for (final book in filteredBooks) {
      final item = _buildBookItem(book);
      final isTourBook = _tourPreviewBook != null &&
          !attachedTourKey &&
          book.title == _tourPreviewBook!.title;
      allItems.add(
        isTourBook
            ? KeyedSubtree(
                key: _tourBookCardKey,
                child: item,
              )
            : item,
      );
      if (isTourBook) {
        attachedTourKey = true;
      }
    }
    items.add(MyGridView(items: allItems));
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
    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (p, c) => p.libraryShowPreview != c.libraryShowPreview,
      builder: (ctx, settingsState) {
        return BlocBuilder<LibraryBloc, LibraryState>(
          buildWhen: (p, c) =>
              (p.previewBook != c.previewBook) &&
              (p.previewBook == book || c.previewBook == book),
          builder: (ctx, libState) {
            final isSelected = settingsState.libraryShowPreview &&
                libState.previewBook == book;
            return GestureDetector(
              onDoubleTap: () =>
                  _openBookInReader(book, book is PdfBook ? 1 : 0),
              child: BookGridItem(
                book: book,
                showTopics: showTopics,
                isSelected: isSelected,
                focusNode: focusNode,
                onBookClickCallback: () {
                  if (settingsState.libraryShowPreview) {
                    _showBookPreview(book);
                  } else {
                    _openBookInReader(book, book is PdfBook ? 1 : 0);
                  }
                },
                onBookDeleted: () {
                  if (ctx.mounted) {
                    ctx.read<LibraryBloc>().add(RefreshLibrary());
                  }
                },
              ),
            );
          },
        );
      },
    );
  }

  void _showBookPreview(Book book) =>
      context.read<LibraryBloc>().add(SelectBookForPreview(book));

  Widget _buildSearchListView(List<Book> books) {
    return _LibraryBrowserList(
      itemCount: books.length,
      forPanel: false,
      itemBuilder: (context, index) {
        return _buildListBookItem(
          books[index],
          0,
          itemStyle: _LibraryListItemStyle.search,
          focusNode: index == 0 ? _firstSearchResultFocusNode : null,
        );
      },
    );
  }

  Widget _buildListView(Category category) => _LibraryBrowserList(
        forPanel: false,
        children: _buildCategoryTree(category, 0),
      );

  List<Widget> _buildCategoryTree(Category category, int level) {
    final List<Widget> widgets = [];
    final filteredBooks = category.books.toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final filteredSubs = category.subCategories.toList();
    if (category is Library) {
      filteredSubs.sort(
        (a, b) => _getTopCategoryOrder(a).compareTo(_getTopCategoryOrder(b)),
      );
    } else {
      filteredSubs.sort(
        (a, b) => _normalizeOrder(a.order).compareTo(_normalizeOrder(b.order)),
      );
    }
    for (final sub in filteredSubs) {
      final isExpanded = _expandedCategories.contains(sub.path);
      final isRootItem = level == 0;
      if (isExpanded) {
        final children = _buildCategoryTree(sub, level + 1);
        if (isRootItem && children.isNotEmpty) {
          widgets.addAll(
            _buildGroupedListSectionItems([
              _buildListCategoryItem(
                sub,
                level,
                isExpanded,
                itemStyle: _LibraryListItemStyle.groupedRoot,
              ),
              ...children,
            ]),
          );
        } else {
          widgets.add(
            _buildListCategoryItem(
              sub,
              level,
              isExpanded,
              itemStyle: isRootItem
                  ? _LibraryListItemStyle.root
                  : _LibraryListItemStyle.grouped,
            ),
          );
          widgets.addAll(children);
        }
      } else {
        widgets.add(
          _buildListCategoryItem(
            sub,
            level,
            isExpanded,
            itemStyle: isRootItem
                ? _LibraryListItemStyle.root
                : _LibraryListItemStyle.grouped,
          ),
        );
      }
    }
    const limit = 500;
    for (int i = 0; i < filteredBooks.length && i < limit; i++) {
      widgets.add(
        _buildListBookItem(
          filteredBooks[i],
          level,
          itemStyle: level == 0
              ? _LibraryListItemStyle.root
              : _LibraryListItemStyle.grouped,
        ),
      );
    }
    if (filteredBooks.length > limit) {
      widgets.add(
        InkWell(
          onTap: () => _showAllBooksDialog(filteredBooks),
          child: Padding(
            padding: EdgeInsets.only(
              right: 16.0 + level * 24,
              left: 16,
              top: 10,
              bottom: 10,
            ),
            child: Text(
              'הצג עוד ${filteredBooks.length - limit} פריטים',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.secondary,
                  ),
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  List<Widget> _buildGroupedListSectionItems(List<Widget> children) {
    final cs = Theme.of(context).colorScheme;
    const radius = Radius.circular(AppTokens.radiusXL);

    return [
      for (int i = 0; i < children.length; i++)
        Card(
          elevation: 0,
          color: AppSurfaces.card(context),
          clipBehavior: Clip.antiAlias,
          surfaceTintColor: Colors.transparent,
          margin: EdgeInsets.only(
            top: i == 0 ? 2 : 0,
            bottom: i == children.length - 1 ? 8 : 0,
          ),
          shape: RoundedRectangleBorder(
            side: BorderSide.none,
            borderRadius: BorderRadius.vertical(
              top: i == 0 ? radius : Radius.zero,
              bottom: i == children.length - 1 ? radius : Radius.zero,
            ),
          ),
          child: Column(
            children: [
              children[i],
              if (i < children.length - 1)
                Divider(
                  height: 1,
                  thickness: 1.5,
                  indent: 0,
                  endIndent: 0,
                  color: cs.surfaceContainerHighest,
                ),
            ],
          ),
        ),
    ];
  }

  Widget _buildListCategoryItem(
    Category category,
    int level,
    bool isExpanded, {
    _LibraryListItemStyle itemStyle = _LibraryListItemStyle.root,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isGrouped = itemStyle == _LibraryListItemStyle.grouped;
    final isGroupedRoot = itemStyle == _LibraryListItemStyle.groupedRoot;
    final isInGroupedSection = isGrouped || isGroupedRoot;
    const double iconBoxSize = 26.0;
    const double iconSize = 14.0;
    const double horizontalPadding = 12.0;
    const double verticalPadding = 8.0;
    final indent = isInGroupedSection ? level * 18.0 : level * 24.0;
    final titleStyle = theme.textTheme.titleMedium?.merge(
      AppTextStyles.settingTitle.copyWith(
        fontWeight: isGrouped ? FontWeight.w600 : FontWeight.w700,
        color: cs.onSurface,
        height: isGrouped ? 1.15 : null,
      ),
    );
    final rowBorderRadius = isInGroupedSection
        ? BorderRadius.zero
        : BorderRadius.circular(AppTokens.radiusXL);

    final row = InkWell(
      mouseCursor: SystemMouseCursors.click,
      borderRadius: rowBorderRadius,
      hoverColor: cs.primary.withValues(alpha: 0.06),
      hoverDuration: Durations.medium1,
      onTap: () => setState(() {
        if (isExpanded) {
          _expandedCategories.remove(category.path);
        } else {
          _expandedCategories.add(category.path);
        }
      }),
      child: Padding(
        padding: EdgeInsets.only(
          right: horizontalPadding + indent,
          left: horizontalPadding,
          top: verticalPadding,
          bottom: verticalPadding,
        ),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            Container(
              width: iconBoxSize,
              height: iconBoxSize,
              decoration: BoxDecoration(
                color: cs.secondaryContainer,
                borderRadius: BorderRadius.circular(AppTokens.radiusSM),
              ),
              child: Center(
                child: Icon(
                  isExpanded
                      ? FluentIcons.folder_open_24_regular
                      : FluentIcons.folder_24_regular,
                  color: cs.onSecondaryContainer,
                  size: iconSize,
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: LibraryOverflowTooltipText(
                text: category.title,
                maxLines: 1,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                style: titleStyle,
              ),
            ),
            Icon(
              isExpanded
                  ? FluentIcons.chevron_up_24_regular
                  : FluentIcons.chevron_down_24_regular,
              color: cs.onSecondaryContainer,
              size: 18,
            ),
          ],
        ),
      ),
    );

    if (isInGroupedSection) {
      return row;
    }

    return Card(
      elevation: 0,
      color: AppSurfaces.card(context),
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(vertical: 2),
      shape: const RoundedRectangleBorder(
        side: BorderSide.none,
        borderRadius: BorderRadius.all(Radius.circular(AppTokens.radiusXL)),
      ),
      child: row,
    );
  }

  TextStyle? _libraryListTitleStyle(
    TextTheme textTheme,
    ColorScheme cs, {
    required FontWeight fontWeight,
    double? height,
  }) {
    return textTheme.titleMedium?.merge(
      AppTextStyles.settingTitle.copyWith(
        fontWeight: fontWeight,
        color: cs.onSurface,
        height: height,
        fontSize: (AppTokens.fontMD),
      ),
    );
  }

  TextStyle? _libraryListSubtitleStyle(
    TextTheme textTheme,
    ColorScheme cs, {
    double? height,
  }) {
    return textTheme.bodySmall?.merge(
      AppTextStyles.settingSubtitle.copyWith(
        color: cs.onSecondaryContainer,
        height: height,
      ),
    );
  }

  /// בניית שורת ספר משותפת למספר סוגי ספרים
  Widget _buildLibraryListRowBase({
    required BuildContext context,
    required Widget leadingWidget,
    required String title,
    required String? subtitle,
    required int level,
    required _LibraryListItemStyle itemStyle,
    required bool isSelected,
    required VoidCallback onTap,
    VoidCallback? onDoubleTap,
    FocusNode? focusNode,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isGrouped = itemStyle == _LibraryListItemStyle.grouped;
    final isSearch = itemStyle == _LibraryListItemStyle.search;
    final horizontalPadding = isSearch ? 8.0 : 12.0;
    const double verticalPadding = 8.0;
    final indent = isGrouped ? level * 18.0 : level * 24.0;
    final titleStyle = _libraryListTitleStyle(
      theme.textTheme,
      cs,
      fontWeight: isGrouped ? FontWeight.w600 : FontWeight.w700,
      height: isGrouped ? 1.15 : null,
    );
    final subtitleStyle = _libraryListSubtitleStyle(
      theme.textTheme,
      cs,
      height: isGrouped ? 1.1 : null,
    );

    final row = DecoratedBox(
      decoration: BoxDecoration(
        color: isSelected ? cs.secondaryContainer.withValues(alpha: 0.3) : null,
      ),
      child: InkWell(
        focusNode: focusNode,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: isGrouped
            ? BorderRadius.zero
            : BorderRadius.circular(AppTokens.radiusXL),
        hoverColor: cs.primary.withValues(alpha: 0.06),
        hoverDuration: Durations.medium1,
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        child: Padding(
          padding: EdgeInsets.only(
            right: horizontalPadding + indent,
            left: horizontalPadding,
            top: verticalPadding,
            bottom: verticalPadding,
          ),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              leadingWidget,
              SizedBox(width: isSearch ? 8 : 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LibraryOverflowTooltipText(
                      text: title,
                      maxLines: 1,
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      style: titleStyle,
                    ),
                    if (subtitle != null && subtitle.isNotEmpty)
                      LibraryOverflowTooltipText(
                        text: subtitle,
                        maxLines: 1,
                        textDirection: TextDirection.rtl,
                        textAlign: TextAlign.right,
                        style: subtitleStyle,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (isGrouped) {
      return row;
    }

    return Card(
      elevation: 0,
      color: AppSurfaces.card(context),
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(vertical: 2),
      shape: const RoundedRectangleBorder(
        side: BorderSide.none,
        borderRadius: BorderRadius.all(Radius.circular(AppTokens.radiusXL)),
      ),
      child: row,
    );
  }

  Widget _buildBookListRow({
    required BuildContext context,
    required Book book,
    required int level,
    required _LibraryListItemStyle itemStyle,
    required bool isSelected,
    required VoidCallback onTap,
    required VoidCallback onDoubleTap,
    FocusNode? focusNode,
  }) {
    const double iconBoxSize = 26.0;
    const double iconSize = 14.0;
    final cs = Theme.of(context).colorScheme;

    final leadingWidget = Container(
      width: iconBoxSize,
      height: iconBoxSize,
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(AppTokens.radiusSM),
      ),
      child: Center(
        child: Icon(
          book is PdfBook
              ? FluentIcons.document_pdf_24_regular
              : FluentIcons.document_text_24_regular,
          color: cs.onSecondaryContainer,
          size: iconSize,
        ),
      ),
    );

    return _buildLibraryListRowBase(
      context: context,
      leadingWidget: leadingWidget,
      title: book.title,
      subtitle: book.author,
      level: level,
      itemStyle: itemStyle,
      isSelected: isSelected,
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      focusNode: focusNode,
    );
  }

  Widget _buildExternalBookListRow({
    required BuildContext context,
    required ExternalLibraryBook book,
    required int level,
    required _LibraryListItemStyle itemStyle,
    required VoidCallback onTap,
    FocusNode? focusNode,
  }) {
    const double iconBoxSize = 32.0; // הגדלנו מ-26 ל-32 כדי להכיל שני אייקונים
    const double iconSize = 14.0;
    final cs = Theme.of(context).colorScheme;

    final leadingWidget = Container(
      width: iconBoxSize,
      height: iconBoxSize,
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(AppTokens.radiusSM),
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              book.link.toString().contains('tablet.otzar.org')
                  ? 'assets/logos/otzar.ico'
                  : 'assets/logos/hebrew_books.png',
              width: iconSize,
              height: iconSize,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 4),
            Icon(
              FluentIcons.open_24_regular,
              color: cs.onSecondaryContainer,
              size: iconSize,
            ),
          ],
        ),
      ),
    );

    return _buildLibraryListRowBase(
      context: context,
      leadingWidget: leadingWidget,
      title: book.title,
      subtitle: book.author,
      level: level,
      itemStyle: itemStyle,
      isSelected: false,
      onTap: onTap,
      focusNode: focusNode,
    );
  }

  /// פריט ספר בתצוגת רשימה
  Widget _buildListBookItem(
    Book book,
    int level, {
    _LibraryListItemStyle itemStyle = _LibraryListItemStyle.root,
    FocusNode? focusNode,
  }) {
    if (book is ExternalLibraryBook) {
      return _buildExternalBookListItem(
        book,
        level,
        itemStyle: itemStyle,
        focusNode: focusNode,
      );
    }
    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (p, c) => p.libraryShowPreview != c.libraryShowPreview,
      builder: (ctx, settingsState) {
        return BlocBuilder<LibraryBloc, LibraryState>(
          buildWhen: (p, c) =>
              (p.previewBook != c.previewBook) &&
              (p.previewBook == book || c.previewBook == book),
          builder: (ctx, libState) {
            final isSelected = settingsState.libraryShowPreview &&
                libState.previewBook == book;
            return _buildBookListRow(
              context: ctx,
              book: book,
              level: level,
              itemStyle: itemStyle,
              isSelected: isSelected,
              focusNode: focusNode,
              onTap: () {
                if (settingsState.libraryShowPreview) {
                  _showBookPreview(book);
                } else {
                  _openBookInReader(book, book is PdfBook ? 1 : 0);
                }
              },
              onDoubleTap: () =>
                  _openBookInReader(book, book is PdfBook ? 1 : 0),
            );
          },
        );
      },
    );
  }

  /// פריט ספר חיצוני בתצוגת רשימה
  Widget _buildExternalBookListItem(
    ExternalLibraryBook book,
    int level, {
    _LibraryListItemStyle itemStyle = _LibraryListItemStyle.root,
    FocusNode? focusNode,
  }) {
    return _buildExternalBookListRow(
      context: context,
      book: book,
      level: level,
      itemStyle: itemStyle,
      focusNode: focusNode,
      onTap: () => _openOtzarBook(book),
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
      subs.sort(
          (a, b) => _getTopCategoryOrder(a).compareTo(_getTopCategoryOrder(b)));
    } else {
      subs.sort((a, b) =>
          _normalizeOrder(a.order).compareTo(_normalizeOrder(b.order)));
    }
    for (final sub in subs) {
      final book = _getFirstDisplayedBook(sub);
      if (book != null) return book;
    }
    return null;
  }

  Category? _findTourCategoryWithBooks(Category category) {
    if (category.title == 'תורה' && category.books.isNotEmpty) {
      return category;
    }

    final subs = category.subCategories.toList();
    if (category is Library) {
      subs.sort(
          (a, b) => _getTopCategoryOrder(a).compareTo(_getTopCategoryOrder(b)));
    } else {
      subs.sort((a, b) =>
          _normalizeOrder(a.order).compareTo(_normalizeOrder(b.order)));
    }

    for (final sub in subs) {
      final match = _findTourCategoryWithBooks(sub);
      if (match != null) {
        return match;
      }
    }

    return category.books.isNotEmpty ? category : null;
  }

  /// פותח קטגוריה יציבה עם ספרים ובוחר את הספר הראשון לתצוגה מקדימה עבור הסיור.
  void prepareTourBookPreview() {
    final libraryState = context.read<LibraryBloc>().state;
    final library = libraryState.library;
    if (library == null) {
      return;
    }

    final category = _findTourCategoryWithBooks(library);
    if (category == null) {
      return;
    }

    context.read<FocusRepository>().librarySearchController.clear();
    context.read<LibraryBloc>().add(const SearchBooks());
    context.read<LibraryBloc>().add(NavigateToCategory(category));

    final book = _getFirstDisplayedBook(category);
    if (book != null) {
      setState(() {
        _tourPreviewBook = book;
        _lastTourBookCardRect = null;
      });
      context.read<LibraryBloc>().add(SelectBookForPreview(book));
    }
    _refocusSearchBar();
  }

  void navigateHome() {
    final libraryState = context.read<LibraryBloc>().state;
    final settingsState = context.read<SettingsBloc>().state;
    _handleNavigateHome(context, libraryState, settingsState);
  }

  Rect? tourBookCardRect() {
    return _rectForTourKey(_tourBookCardKey);
  }

  Rect? tourLibraryRect() {
    return _rectForTourKey(_tourLibraryKey);
  }

  Rect? tourLibrarySearchRect() {
    return _rectForTourKey(_tourLibrarySearchKey);
  }

  Rect? tourLibraryCategoriesRect() {
    Rect? combined;
    for (final key in _tourCategoryKeys.values) {
      final rect = _rectForTourKey(key);
      if (rect == null) continue;
      combined = combined == null ? rect : combined.expandToInclude(rect);
    }
    return combined;
  }

  Rect? _rectForTourKey(GlobalKey key) {
    final keyContext = key.currentContext;
    if (keyContext == null) {
      return key == _tourBookCardKey ? _lastTourBookCardRect : null;
    }
    RenderObject? renderObject;
    try {
      renderObject = keyContext.findRenderObject();
    } on FlutterError {
      return key == _tourBookCardKey ? _lastTourBookCardRect : null;
    }
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return key == _tourBookCardKey ? _lastTourBookCardRect : null;
    }
    final topLeft = renderObject.localToGlobal(Offset.zero);
    final rect = topLeft & renderObject.size;
    if (key == _tourBookCardKey) {
      _lastTourBookCardRect = rect;
    }
    return rect;
  }

  void _openCategory(Category category) {
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
            itemBuilder: (context, i) => _buildListBookItem(books[i], 0),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('סגור'),
          ),
        ],
      ),
    );
  }

  List<String> _getAllTopics(List<Book> books) {
    final Set<String> topics = {};
    for (final b in books) {
      topics.addAll(b.topics.split(', '));
    }
    return topics.toList();
  }

  void _update(
    BuildContext context,
    LibraryState state,
    SettingsState settingsState, {
    bool restoreSearchFocus = false,
    bool selectAllOnRestore = false,
  }) {
    _searchDebounce?.cancel();
    final searchText =
        context.read<FocusRepository>().librarySearchController.text;
    context.read<LibraryBloc>().add(
          UpdateSearchQuery(searchText.replaceAll('"', '')),
        );
    _searchWithSettings(context, settingsState);
    setState(() {});
    if (restoreSearchFocus) {
      _refocusSearchBar(selectAll: selectAllOnRestore);
    }
  }

  void _scheduleSearchWithSettings(BuildContext context, SettingsState s) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(_kLibrarySearchDebounceDuration, () {
      if (!mounted) return;
      _searchWithSettings(context, s);
    });
  }

  void _searchWithSettings(BuildContext context, SettingsState s) {
    _searchDebounce?.cancel();
    _searchDebounce = null;
    context.read<LibraryBloc>().add(
          SearchBooks(
            showHebrewBooks: s.showExternalBooks && s.showHebrewBooks,
            showOtzarHachochma: s.showExternalBooks && s.showOtzarHachochma,
          ),
        );
  }

  void _refocusSearchBar({bool selectAll = false}) {
    context.read<FocusRepository>().requestLibrarySearchFocus(
          selectAll: selectAll,
        );
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

  Widget _buildPreviewPane(SettingsState settingsState) {
    return BlocBuilder<LibraryBloc, LibraryState>(
      buildWhen: (p, c) => p.previewBook != c.previewBook,
      builder: (ctx, previewState) => GestureDetector(
        onDoubleTap: () {
          if (previewState.previewBook != null) {
            _openBookInReader(previewState.previewBook!, 0);
          }
        },
        child: BookPreviewPanel(
          book: previewState.previewBook,
          onOpenInReader: (i) {
            if (previewState.previewBook != null) {
              _openBookInReader(previewState.previewBook!, i);
            }
          },
        ),
      ),
    );
  }

  Widget _buildSettingsOverlay(BuildContext context, bool isOpen) {
    return ContextOverlayPanel(
      isOpen: isOpen,
      onClose: _closeSettingsPanel,
      width: 400,
      deferChildBuildOnOpen: true,
      preserveChildStateOnClose: true,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Text(
                  'הגדרות',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Expanded(
            child: SingleChildScrollView(
              child: LibrarySettingsPanel(hebrewBooksPathWidget: null),
            ),
          ),
        ],
      ),
    );
  }
}

// ── _LoadingDotsText ──────────────────────────────────────────────────────────

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
      builder: (_, __) {
        final v = _controller.value;
        final dots = v < 0.25
            ? 0
            : v < 0.5
                ? 1
                : v < 0.75
                    ? 2
                    : 3;
        return Text(
          'טוען ספרייה${'.' * dots}${' ' * (3 - dots)}',
          style: Theme.of(context).textTheme.bodyMedium,
        );
      },
    );
  }
}

class _LibraryBrowserList extends StatelessWidget {
  const _LibraryBrowserList({
    this.children,
    this.itemCount,
    this.itemBuilder,
    this.forPanel = false,
  }) : assert(
          children != null || (itemCount != null && itemBuilder != null),
          'Provide either children or itemCount with itemBuilder',
        );

  final List<Widget>? children;
  final int? itemCount;
  final NullableIndexedWidgetBuilder? itemBuilder;
  final bool forPanel;

  @override
  Widget build(BuildContext context) {
    final padding = forPanel
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
        : const EdgeInsets.symmetric(horizontal: 45, vertical: 8);

    if (children != null) {
      return ListView(
        padding: padding,
        children: children!,
      );
    }

    return ListView.builder(
      padding: padding,
      itemCount: itemCount,
      itemBuilder: itemBuilder!,
    );
  }
}

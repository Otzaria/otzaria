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
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/file_sync/file_sync_bloc.dart';
import 'package:otzaria/file_sync/file_sync_event.dart';
import 'package:otzaria/file_sync/file_sync_state.dart';
import 'package:otzaria/library/view/library_daf_yomi.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/migration/sync/file_sync_service.dart';
import 'package:otzaria/migration/sync/background_db_sync_worker.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';
import 'package:otzaria/widgets/filter_chips_widget.dart';
import 'package:otzaria/navigation/main_window_screen.dart';
import 'package:otzaria/library/view/grid_items.dart';
import 'package:otzaria/library/view/otzar_book_dialog.dart';
import 'package:otzaria/library/view/book_preview_panel.dart';
import 'package:otzaria/library/view/library_panel_controller.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/widgets/app_top_bar.dart';
import 'package:otzaria/widgets/responsive_action_bar.dart';
import 'package:otzaria/utils/open_book.dart';
import 'package:otzaria/widgets/adaptive_side_pane.dart';
import 'package:otzaria/widgets/context_overlay_panel.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/widgets/otzaria_search_field.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/theme/app_surfaces.dart';

// ── קבועים ────────────────────────────────────────────────────────────────────

/// רוחב מינימלי להצגת LibraryDafYomi בשורה הראשית (לא בשורה שניה)
const double _kDafYomiInlineMinWidth = 820.0;

/// דיבאונס לגלילה (ms) — מונע rebuild חוזר
const int _kScrollDebounceMs = 100;

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
  final Set<String> _expandedCategories = {};
  final _settingsPanelOpen = ValueNotifier<bool>(false);
  double? _previewPaneWidthOverride;
  late final ValueNotifier<double> _topBarTotalHeight;

  /// שולט בנראות השורה השניה — מוגן מפני flicker ע"י debounce ב-AppTopBar
  late final ValueNotifier<bool> _secondaryRowVisible;

  /// דיבאונס timer לגלילה — מונע setState חוזר בכל scroll event
  Timer? _scrollDebounce;
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
              _update(context, state, settingsState);
            },
            onClear: () {
              _update(context, state, settingsState, restoreSearchFocus: true);
            },
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
        final screenWidth = constraints.maxWidth;
        const minPreviewWidth = 280.0;
        final previewWidth = settingsState.libraryViewMode == 'list'
            ? screenWidth * 0.55
            : screenWidth * 0.36;
        final maxPreviewWidth = (screenWidth - 350).clamp(
          minPreviewWidth,
          screenWidth,
        );
        final previewPaneWidth = previewWidth.clamp(
          minPreviewWidth,
          maxPreviewWidth,
        );
        final effectivePreviewPaneWidth =
            (_previewPaneWidthOverride ?? previewPaneWidth.toDouble()).clamp(
          minPreviewWidth,
          maxPreviewWidth,
        );
        final mainContent = _buildContent(state);

        return AdaptiveSidePane(
          isOpen: _isPreviewPanelVisible(settingsState),
          alignment: AlignmentDirectional.centerStart, // שמאל בעברית (RTL)
          mainContent: RepaintBoundary(child: mainContent),
          paneContent: _buildPreviewPane(settingsState),
          paneWidth: effectivePreviewPaneWidth.toDouble(),
          minMainContentWidth: 420,
          onClose: () => _hidePreviewPanel(settingsState),
          onOpen: () => _showPreviewPanel(settingsState),
          paneColor: Theme.of(ctx).colorScheme.surface,
          isResizable: true,
          minPaneWidth: minPreviewWidth,
          maxPaneWidth: maxPreviewWidth,
          onPaneWidthChanged: (nextWidth) {
            setState(() {
              _previewPaneWidthOverride = nextWidth;
            });
          },
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

  Future<void> _refreshWithPersonalFolders() async {
    try {
      final sqliteProvider = SqliteDataProvider.instance;
      if (!sqliteProvider.isInitialized) {
        await sqliteProvider.initialize();
      }
      if (!sqliteProvider.isInitialized) return;

      final dbPath = sqliteProvider.dbPath;
      final libraryPath = Settings.getValue<String>('key-library-path');
      if (libraryPath == null || libraryPath.isEmpty) return;

      final customFoldersJson =
          Settings.getValue<String>(SettingsRepository.keyCustomFolders);
      final customFolders = CustomFoldersManager.loadFolders(customFoldersJson);
      final folderName =
          Settings.getValue<String>(SettingsRepository.keyLibraryFolderName) ??
              '';

      await runCustomFoldersDbSyncInIsolate(
        dbPath: dbPath,
        libraryPath: libraryPath,
        customFolders: customFolders,
        folderName: folderName,
      );

      await FileSyncService.saveCustomFoldersSignature(customFolders);
    } catch (_) {
      // גם אם סריקת התיקיות נכשלה, עדיין נרענן את הספרייה.
    }

    if (mounted) {
      context.read<LibraryBloc>().add(RefreshLibrary());
    }
  }

  List<ActionButtonData> _buildOriginalOrderActions(
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
      if (settingsState.canUseSoftwareAndBookUpdates)
        _buildSyncActionButton(compact: compact),
      ActionButtonData(
        widget: ToolbarActionButton(
          compact: compact,
          tooltip: 'טעינה מחדש',
          icon: FluentIcons.arrow_clockwise_24_regular,
          onPressed: _refreshWithPersonalFolders,
        ),
        icon: FluentIcons.arrow_clockwise_24_regular,
        tooltip: 'טעינה מחדש',
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
      if (settingsState.canUseSoftwareAndBookUpdates)
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
          tooltip: 'טעינה מחדש',
          icon: FluentIcons.arrow_clockwise_24_regular,
          onPressed: _refreshWithPersonalFolders,
        ),
        icon: FluentIcons.arrow_clockwise_24_regular,
        tooltip: 'טעינה מחדש',
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
    context.read<LibraryBloc>().add(LoadLibrary());
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
        (c) => CategoryGridItem(
          category: c,
          onCategoryClickCallback: () => _openCategory(c),
        ),
      ),
      ...filteredBooks.map((b) => _buildBookItem(b)),
    ];
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
    return BlocBuilder<LibraryBloc, LibraryState>(
      buildWhen: (p, c) =>
          (p.previewBook != c.previewBook) &&
          (p.previewBook == book || c.previewBook == book),
      builder: (ctx, libState) {
        final isSelected = libState.previewBook == book;
        return GestureDetector(
          onDoubleTap: () => _openBookInReader(book, book is PdfBook ? 1 : 0),
          child: Container(
            decoration: isSelected
                ? BoxDecoration(
                    border: Border.all(
                      color: Theme.of(ctx).colorScheme.primary,
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
                final s = ctx.read<SettingsBloc>().state;
                if (s.libraryShowPreview) {
                  _showBookPreview(book);
                } else {
                  _openBookInReader(book, book is PdfBook ? 1 : 0);
                }
              },
              onBookDeleted: () {
                if (ctx.mounted) ctx.read<LibraryBloc>().add(RefreshLibrary());
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

  Widget _buildListView(Category category) =>
      ListView(children: _buildCategoryTree(category, 0));

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
      widgets.add(_buildListCategoryItem(sub, level, isExpanded));
      if (isExpanded) widgets.addAll(_buildCategoryTree(sub, level + 1));
    }
    const limit = 500;
    for (int i = 0; i < filteredBooks.length && i < limit; i++) {
      widgets.add(_buildListBookItem(filteredBooks[i], level));
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
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _buildListCategoryItem(Category category, int level, bool isExpanded) {
    return InkWell(
      onTap: () => setState(() {
        if (isExpanded) {
          _expandedCategories.remove(category.path);
        } else {
          _expandedCategories.add(category.path);
        }
      }),
      child: Container(
        padding: EdgeInsets.only(
          right: 16.0 + level * 24,
          left: 16,
          top: 12,
          bottom: 12,
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
      buildWhen: (p, c) =>
          (p.previewBook != c.previewBook) &&
          (p.previewBook == book || c.previewBook == book),
      builder: (ctx, libState) {
        final isSelected = libState.previewBook == book;
        return InkWell(
          focusNode: focusNode,
          onTap: () {
            final s = ctx.read<SettingsBloc>().state;
            if (s.libraryShowPreview) {
              _showBookPreview(book);
            } else {
              _openBookInReader(book, book is PdfBook ? 1 : 0);
            }
          },
          onDoubleTap: () => _openBookInReader(book, book is PdfBook ? 1 : 0),
          child: Container(
            padding: EdgeInsets.only(
              right: 16.0 + level * 24,
              left: 16,
              top: 10,
              bottom: 10,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(
                      ctx,
                    ).colorScheme.primaryContainer.withValues(alpha: 0.3)
                  : null,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(ctx).dividerColor,
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
                  color: Theme.of(ctx).colorScheme.secondary,
                  size: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LibraryOverflowTooltipText(
                        text: book.title,
                        maxLines: 1,
                        textDirection: TextDirection.rtl,
                        textAlign: TextAlign.right,
                        style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Theme.of(ctx).colorScheme.primary,
                            ),
                      ),
                      if (book.author != null && book.author!.isNotEmpty)
                        LibraryOverflowTooltipText(
                          text: book.author!,
                          maxLines: 1,
                          textDirection: TextDirection.rtl,
                          textAlign: TextAlign.right,
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                color:
                                    Theme.of(ctx).colorScheme.onSurfaceVariant,
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
            const SizedBox(width: 8),
            Icon(
              FluentIcons.open_24_regular,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 16,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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

  void _searchWithSettings(BuildContext context, SettingsState s) {
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
          onClose: () => _hidePreviewPanel(settingsState),
        ),
      ),
    );
  }

  Widget _buildSettingsOverlay(BuildContext context, bool isOpen) {
    return ContextOverlayPanel(
      isOpen: isOpen,
      onClose: _closeSettingsPanel,
      width: 400,
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

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/empty_library/empty_library_screen.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/tools/calendar/helpers/daf_yomi_navigation.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/library/view/library_daf_yomi.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/widgets/lists/filter_chips_widget.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';
import 'package:otzaria/library/view/grid_items.dart';
import 'package:otzaria/library/view/otzar_book_dialog.dart';
import 'package:otzaria/library/view/book_preview_panel.dart';
import 'package:otzaria/library/view/library_empty_state_widget.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/library/view/library_panel_controller.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';
import 'package:otzaria/utils/navigation/open_book.dart';
import 'package:otzaria/utils/navigation/talmud_bavli_open_format.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria/widgets/layout/context_overlay_panel.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/core/external_uri_router.dart';

// ── קבועים ────────────────────────────────────────────────────────────────────

/// רוחב מינימלי להצגת LibraryDafYomi בשורה הראשית (לא בשורה שניה)
const double _kDafYomiInlineMinWidth = 820.0;

/// דיבאונס לגלילה (ms) — מונע rebuild חוזר
const int _kScrollDebounceMs = 100;

/// דיבאונס לחיפוש ספרים — מונע הרצת חיפוש כבד על כל אות.
const Duration _kLibrarySearchDebounceDuration = Duration(milliseconds: 250);

enum _LibraryListItemStyle { root, grouped, search }

/// מעל מספר זה של שורות נראות, עץ הקטגוריות משוטח ומרונדר וירטואלית
/// (כמו ב-TOC) — מתחתיו נשמר העץ המקונן עם אנימציות ההרחבה.
const int _kLibraryTreeFlattenThreshold = 500;

/// מכסת הספרים המוצגים לקטגוריה; מעבר לה מופיעה שורת "הצג עוד".
const int _kCategoryBooksCap = 500;

/// הסמל בכפתור עדכון הספרייה. מצב מנותק מקבל סמל משלו — כך המשתמש יודע
/// שהעדכון לא רץ, בלי הודעת שגיאה קופצת שאין לו מה לעשות איתה.
@visibleForTesting
IconData libraryUpdateButtonIcon(LibraryUpdateStatus status) =>
    switch (status) {
      LibraryUpdateStatus.completed => FluentIcons.checkmark_circle_24_regular,
      LibraryUpdateStatus.disconnected => FluentIcons.cloud_off_24_regular,
      _ => FluentIcons.arrow_sync_24_regular,
    };

/// התיאור (tooltip) של כפתור עדכון הספרייה.
@visibleForTesting
String libraryUpdateButtonTooltip(LibraryUpdateState state) =>
    switch (state.status) {
      LibraryUpdateStatus.completed =>
        state.hasUpdate ? 'העדכון הושלם' : 'הספרייה מעודכנת',
      LibraryUpdateStatus.error => 'שגיאה בעדכון - לחץ לנסות שוב',
      LibraryUpdateStatus.disconnected => 'אין חיבור לאינטרנט - לחץ לנסות שוב',
      LibraryUpdateStatus.needsFullConfirmation => state.message,
      LibraryUpdateStatus.blocked => state.message,
      _ when state.isBusy => state.message,
      _ => 'עדכון ספרייה',
    };

/// האם לחיצה על הכפתור מנקה את המצב הקודם במקום להתחיל עדכון. מצב מנותק
/// מתחיל ניסיון חדש מיד — אין הודעה שצריך לנקות, ורק הרשת הייתה חסרה.
@visibleForTesting
bool libraryUpdateButtonResets(LibraryUpdateStatus status) =>
    status == LibraryUpdateStatus.completed ||
    status == LibraryUpdateStatus.error ||
    status == LibraryUpdateStatus.blocked;

enum FlatLibraryRowKind { categoryHeader, book, rootBook, showMore }

/// שורה בעץ הספרייה המשוטח. דגלי הקצוות משחזרים את מראה הכרטיס של
/// [ExpandableCard] ברמה העליונה (פינות מעוגלות ורווח בין קבוצות).
@visibleForTesting
class FlatLibraryRow {
  final FlatLibraryRowKind kind;
  final Category? category;
  final Book? book;
  final List<Book>? showMoreBooks;
  final int level;

  /// נתיב הקטגוריה המכילה — מבדיל בין שורות זהות תחת הורים שונים (keys).
  final String parentPath;
  final bool isGroupStart;
  bool isGroupEnd = false;

  FlatLibraryRow({
    required this.kind,
    required this.level,
    required this.parentPath,
    this.category,
    this.book,
    this.showMoreBooks,
    this.isGroupStart = false,
  });
}

/// משטח את הצמתים הנראים בעץ הספרייה (לפי [expandedPaths]) לרשימת שורות —
/// אותו סדר ואותם גבולות (מכסה + "הצג עוד") כמו העץ המקונן.
@visibleForTesting
List<FlatLibraryRow> buildFlatLibraryRows({
  required Category category,
  required Set<String> expandedPaths,
  required int Function(Category) topCategoryOrder,
  required int Function(int) normalizeOrder,
  Set<String> talmudTextTitles = const {},
}) {
  final rows = <FlatLibraryRow>[];

  void collect(Category current, int level) {
    final books =
        current.books
            .where(
              (b) => !isTalmudBavliPdfLibraryDuplicate(b, talmudTextTitles),
            )
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    final subs = current.subCategories.where((c) => c.hasBooks).toList();
    if (current is Library) {
      subs.sort((a, b) => topCategoryOrder(a).compareTo(topCategoryOrder(b)));
    } else {
      subs.sort(
        (a, b) => normalizeOrder(a.order).compareTo(normalizeOrder(b.order)),
      );
    }

    for (final sub in subs) {
      rows.add(
        FlatLibraryRow(
          kind: FlatLibraryRowKind.categoryHeader,
          category: sub,
          level: level,
          parentPath: current.path,
          isGroupStart: level == 0,
        ),
      );
      if (expandedPaths.contains(sub.path)) {
        collect(sub, level + 1);
      }
      if (level == 0) {
        rows.last.isGroupEnd = true;
      }
    }

    for (int i = 0; i < books.length && i < _kCategoryBooksCap; i++) {
      rows.add(
        FlatLibraryRow(
          kind: level == 0
              ? FlatLibraryRowKind.rootBook
              : FlatLibraryRowKind.book,
          book: books[i],
          level: level,
          parentPath: current.path,
        ),
      );
    }
    if (books.length > _kCategoryBooksCap) {
      rows.add(
        FlatLibraryRow(
          kind: FlatLibraryRowKind.showMore,
          showMoreBooks: books,
          level: level,
          parentPath: current.path,
        ),
      );
    }
  }

  collect(category, 0);
  return rows;
}

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
  final maxPaneWidth = max(minPaneWidth, availableWidth - 230);
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
    final normalized = cat.title
        .replaceAll('\u05F4', '"')
        .replaceAll('\u05F3', "'");
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
    context.read<SettingsBloc>().add(
      UpdateLibraryShowPreview(!s.libraryShowPreview),
    );
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

    // מוצג רק בראש הרשימה — לא לפי כיוון הגלילה, אחרת כל תנועה כלפי מעלה
    // באמצע הרשימה הייתה מחזירה את השורה השנייה.
    final atTop = notification.metrics.pixels <= 8;
    if (atTop == _lastScrollVisible) return false;

    _lastScrollVisible = atTop;
    _scrollDebounce?.cancel();
    _scrollDebounce = Timer(
      const Duration(milliseconds: _kScrollDebounceMs),
      () {
        if (mounted) _secondaryRowVisible.value = atTop;
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
    return _buildScaffold(context);
  }

  Future<void> _handleLibraryLoaded() async {
    await context.read<NavigationBloc>().refreshLibrary();
    if (!mounted) return;
    context.read<LibraryBloc>().add(RefreshLibrary());
  }

  Widget _buildScaffold(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<LibraryBloc, LibraryState>(
          listenWhen: (previous, current) =>
              previous.isLoading &&
              !current.isLoading &&
              current.library != null,
          listener: (context, state) {
            final book = _getFirstDisplayedBook(
              state.currentCategory ?? state.library!,
            );
            if (book != null) {
              context.read<LibraryBloc>().add(SelectBookForPreview(book));
            }
          },
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
                        final hasSecondaryRow = !dafYomiInline;
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
                                  final effectiveTopPad = topBarHeight > 0
                                      ? topBarHeight
                                      : topPad;
                                  return AnimatedPadding(
                                    duration: const Duration(milliseconds: 180),
                                    curve: Curves.easeOut,
                                    padding: EdgeInsets.only(
                                      top: effectiveTopPad,
                                    ),
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
    final isLibraryEmpty = context.select<NavigationBloc, bool>(
      (b) => b.state.isLibraryEmpty,
    );
    final previewSelected =
        !isLibraryEmpty && _isPreviewPanelVisible(settingsState);

    // ── Trailing items ────────────────────────────────────────────────────
    final trailingItems = <AppTopBarItem>[];

    // LibraryDafYomi (תאריך + דף יומי): בשורה הראשית כשיש מקום, אחרת בשורה שניה
    if (dafYomiInline) {
      trailingItems.add(
        AppTopBarItem(
          widget: LibraryDafYomi(
            dafEnabled: !isLibraryEmpty,
            onDafYomiTap: (tractate, daf) =>
                openDafYomiBook(context, tractate, ' $daf.'),
          ),
        ),
      );
    }

    trailingItems.addAll([
      AppTopBarItem(
        dividerBefore: true,
        widget: BarButton.icon(
          compact: isCompact,
          tooltip: previewSelected ? 'הסתר תצוגה מקדימה' : 'הצג תצוגה מקדימה',
          icon: previewSelected
              ? FluentIcons.eye_24_filled
              : FluentIcons.eye_24_regular,
          selected: previewSelected,
          // אין ספרייה — אין תצוגה מקדימה, לכן הכפתור מושבת.
          onPressed: isLibraryEmpty
              ? null
              : () => _togglePreviewPanel(context.read<SettingsBloc>().state),
        ),
      ),
      AppTopBarItem(
        widget: ValueListenableBuilder<bool>(
          valueListenable: _settingsPanelOpen,
          builder: (context, isOpen, _) => BarButton.icon(
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
      settingsState,
      showDafYomi: !dafYomiInline,
      isLibraryEmpty: isLibraryEmpty,
    );

    return AppTopBar(
      totalHeightNotifier: _topBarTotalHeight,
      scrollDebounceMs: _kScrollDebounceMs,
      secondaryRowVisible: secondaryRow != null ? _secondaryRowVisible : null,
      leadingItems: [
        AppTopBarItem(
          widget: _buildNavActions(
            context,
            state,
            settingsState,
            isLibraryEmpty: isLibraryEmpty,
          ),
        ),
      ],
      center: _buildSearchBar(state, isCompact),
      trailingItems: trailingItems,
      secondaryRow: secondaryRow,
    );
  }

  // ── Secondary row ─────────────────────────────────────────────────────────

  Widget? _buildSecondaryRow(
    BuildContext context,
    SettingsState settingsState, {
    required bool showDafYomi,
    required bool isLibraryEmpty,
  }) {
    final cs = Theme.of(context).colorScheme;

    final children = <Widget>[];

    if (showDafYomi) {
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Center(
            child: LibraryDafYomi(
              dafEnabled: !isLibraryEmpty,
              onDafYomiTap: (tractate, daf) =>
                  openDafYomiBook(context, tractate, ' $daf.'),
            ),
          ),
        ),
      );
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
    SettingsState settingsState, {
    required bool isLibraryEmpty,
  }) {
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
        isLibraryEmpty: isLibraryEmpty,
      ),
      alwaysInMenu: const [],
      originalOrder: _buildOriginalOrderActions(
        context,
        state,
        settingsState,
        isCompact,
        isLibraryEmpty: isLibraryEmpty,
      ),
      maxVisibleButtons: maxButtons,
      overflowOnRight: true,
    );
  }

  // ── Deep link from search bar ─────────────────────────────────────────────

  /// בודק אם מחרוזת היא קישור otzaria:// או zayit:// תקין וניתן לפענוח.
  static bool _isDeepLinkText(String text) {
    final trimmed = text.trim().toLowerCase();
    if (!trimmed.startsWith('otzaria://') && !trimmed.startsWith('zayit://')) {
      return false;
    }
    final uri = Uri.tryParse(text.trim());
    if (uri == null) return false;
    return ExternalUriRouter.parseUri(uri) != null;
  }

  /// בודק אם הטקסט שהוגש הוא קישור otzaria:// או zayit:// ומנתב אותו.
  /// מחזיר true אם הטקסט טופל כקישור (ואז שדה החיפוש מנוקה).
  /// השדה מנוקה רק לאחר אימות הצלחת הטיפול — אם הקישור תקין תחבירית אך
  /// ה-bookId לא קיים בספרייה, השדה נשאר עם הטקסט שהמשתמש הדביק.
  Future<bool> _tryHandleDeepLink(BuildContext context, String text) async {
    if (!_isDeepLinkText(text)) return false;

    final uri = Uri.tryParse(text.trim())!;
    final normalized = ExternalUriRouter.normalizeUri(uri) ?? uri;

    // מעבירים את הטיפול ל-MainWindowScreenState שמכיל את כל הלוגיקה. רק אם
    // ההחזרה היא true (הספר אומת ונפתח) ננקה את שדה החיפוש.
    final libraryBloc = context.read<LibraryBloc>();
    final focusRepository = context.read<FocusRepository>();

    final handled =
        await mainWindowScreenKey.currentState?.handleInternalDeepLink(
          normalized.toString(),
        ) ??
        false;

    if (handled) {
      focusRepository.librarySearchController.clear();
      libraryBloc.add(const UpdateSearchQuery(''));
      libraryBloc.add(const SearchBooks());
    }
    return handled;
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
              onSubmitted: (value) async {
                if (await _tryHandleDeepLink(context, value)) return;
                if (!context.mounted) return;
                context.read<LibraryBloc>().add(const SelectTopics([]));
                _scheduleSearchWithSettings(context, settingsState);
              },
              onClear: () {
                _update(
                  context,
                  state,
                  settingsState,
                  restoreSearchFocus: true,
                );
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
        // סינון מקומי בלבד של התוצאות המוצגות — בלי חיפוש מחדש, כדי שלא
        // יוצג סמל חיפוש ושצ'יפי שאר הקטגוריות יישארו (מבוססים על כל התוצאות).
        context.read<LibraryBloc>().add(SelectTopics(list));
        _refocusSearchBar();
      },
      chipBuilder: (context, item, isSelected) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        child: Chip(
          label: Text(item),
          backgroundColor: isSelected
              ? Theme.of(context).colorScheme.secondary
              : null,
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
        // כשאין ספרייה מוגדרת מציגים את מסך ההגדרה בתוך אזור התוכן — הסרגל
        // העליון נשאר, ורק התוכן מתחלף. מגיב לשינוי isLibraryEmpty (למשל אחרי
        // הורדה/ייבוא) ומחליף לעץ הספרייה.
        final isLibraryEmpty = ctx.select<NavigationBloc, bool>(
          (b) => b.state.isLibraryEmpty,
        );
        final mainContent = isLibraryEmpty
            ? LibrarySetupView(onLibraryLoaded: _handleLibraryLoaded)
            : _buildContent(state);

        return AdaptiveSidePane(
          // אין ספרייה — התצוגה המקדימה סגורה כפויה (אין ספרים להציג).
          isOpen: !isLibraryEmpty && _isPreviewPanelVisible(settingsState),
          alignment: AlignmentDirectional.centerStart, // שמאל בעברית (RTL)
          mainContent: RepaintBoundary(child: mainContent),
          paneContent: _buildPreviewPane(settingsState),
          paneWidth: previewPaneWidths.paneWidth,
          minMainContentWidth: 200,
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
              borderRadius: AppTokens.borderRadiusAll,
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
      // ריענון הספרייה אחרי עדכון מטופל ב-MainWindowScreen (listener שתמיד
      // mounted). כאן רק בונים את הכפתור.
      widget: BlocBuilder<LibraryUpdateBloc, LibraryUpdateState>(
        builder: (ctx, state) {
          final isBusy = state.isBusy;
          return BarButton.icon(
            compact: compact,
            tooltip: libraryUpdateButtonTooltip(state),
            icon: libraryUpdateButtonIcon(state.status),
            // ספינר מסתובב בזמן עדכון — אינדיקציית פעילות רציפה (ticker עצמאי),
            // כי בשלב ה-apply הארוך אין שינויי state שיבנו מחדש את הכפתור.
            iconWidget: isBusy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : null,
            selected: isBusy,
            onPressed: () {
              final b = ctx.read<LibraryUpdateBloc>();
              if (isBusy) {
                b.add(const CancelLibraryUpdate());
              } else if (libraryUpdateButtonResets(state.status)) {
                b.add(const ResetLibraryUpdate());
              } else {
                b.add(const StartLibraryUpdate());
              }
            },
          );
        },
      ),
      icon: FluentIcons.arrow_sync_24_regular,
      tooltip: 'עדכון ספרייה',
      onPressed: () {
        final b = context.read<LibraryUpdateBloc>();
        if (!b.state.isBusy) {
          b.add(const StartLibraryUpdate());
        }
      },
    );
  }

  void _refreshWithPersonalFolders() {
    context.read<CustomFoldersBloc>().add(
      const RescanCustomFolders(showNoChangesMessage: false),
    );
  }

  List<ActionButtonData> _buildOriginalOrderActions(
    BuildContext context,
    LibraryState state,
    SettingsState settingsState,
    bool compact, {
    required bool isLibraryEmpty,
  }) {
    return [
      ActionButtonData.simple(
        compact: compact,
        tooltip: 'חזרה לתיקיה הקודמת',
        icon: FluentIcons.arrow_up_24_regular,
        onPressed: isLibraryEmpty
            ? null
            : () => _handleNavigateUp(context, state, settingsState),
      ),
      ActionButtonData.simple(
        compact: compact,
        tooltip: 'חזרה לתיקיה הראשית',
        icon: FluentIcons.home_24_regular,
        onPressed: isLibraryEmpty
            ? null
            : () => _handleNavigateHome(context, state, settingsState),
      ),
      if (settingsState.canUseSoftwareAndBookUpdates)
        _buildSyncActionButton(compact: compact),
      ActionButtonData.simple(
        compact: compact,
        tooltip: 'טעינה מחדש',
        icon: FluentIcons.arrow_clockwise_24_regular,
        onPressed: isLibraryEmpty ? null : _refreshWithPersonalFolders,
      ),
    ];
  }

  List<ActionButtonData> _buildPrioritizedActions(
    BuildContext context,
    LibraryState state,
    SettingsState settingsState,
    bool compact, {
    required bool isLibraryEmpty,
  }) {
    return [
      ActionButtonData.simple(
        compact: compact,
        tooltip: 'חזרה לתיקיה הקודמת',
        icon: FluentIcons.arrow_up_24_regular,
        onPressed: isLibraryEmpty
            ? null
            : () => _handleNavigateUp(context, state, settingsState),
      ),
      if (settingsState.canUseSoftwareAndBookUpdates)
        _buildSyncActionButton(compact: compact),
      ActionButtonData.simple(
        compact: compact,
        tooltip: 'חזרה לתיקיה הראשית',
        icon: FluentIcons.home_24_regular,
        onPressed: isLibraryEmpty
            ? null
            : () => _handleNavigateHome(context, state, settingsState),
      ),
      ActionButtonData.simple(
        compact: compact,
        tooltip: 'טעינה מחדש',
        icon: FluentIcons.arrow_clockwise_24_regular,
        onPressed: isLibraryEmpty ? null : _refreshWithPersonalFolders,
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

  void _openSearchDialog(BuildContext context, {String? searchQuery}) {
    final tab = searchQuery != null && searchQuery.isNotEmpty
        ? SearchingTab('חיפוש', searchQuery)
        : null;
    showDialog(
      context: context,
      builder: (context) => SearchDialog(existingTab: tab),
    );
  }

  /// בונה את ווידג'ט המצב הריק עם הלוגיקה המתאימה.
  /// אם טקסט החיפוש הוא קישור otzaria://, מציג מצב קישור ישיר.
  Widget _buildEmptyState(
    BuildContext context,
    LibraryState state,
    SettingsState settingsState,
    FocusRepository repo,
  ) {
    final searchText = repo.librarySearchController.text;
    final isDeepLink = _isDeepLinkText(searchText);

    final message = searchText.isNotEmpty
        ? 'אין תוצאות עבור "$searchText"'
        : 'אין פריטים להצגה בתיקייה זו';

    void onBack() {
      if (searchText.isNotEmpty) {
        repo.librarySearchController.clear();
        context.read<LibraryBloc>().add(const UpdateSearchQuery(''));
        context.read<LibraryBloc>().add(const SearchBooks());
      } else {
        _handleNavigateUp(context, state, settingsState);
      }
    }

    return LibraryEmptyStateWidget(
      message: message,
      onBack: onBack,
      onHome: () => _handleNavigateHome(context, state, settingsState),
      onOpenSearch: () => _openSearchDialog(context, searchQuery: searchText),
      onOpenLink: isDeepLink
          ? () => _tryHandleDeepLink(context, searchText)
          : null,
      showSearchElsewhereHint:
          searchText.isNotEmpty && state.currentCategory != state.library,
    );
  }

  // ── Content ───────────────────────────────────────────────────────────────

  Widget _buildContent(LibraryState state) {
    if (state.library == null || state.currentCategory == null) {
      return const Center(child: SizedBox.shrink());
    }
    return BlocSelector<LibraryBloc, LibraryState, bool>(
      selector: (s) => s.isSearching,
      builder: (ctx, isSearching) {
        if (isSearching) {
          return const Center(child: _SearchingIndicator());
        }
        final settingsState = context.read<SettingsBloc>().state;
        if (settingsState.libraryViewMode == 'grid') {
          if (state.searchResults != null) {
            final books = _visibleBooks(state.searchResults!);
            if (books.isEmpty) {
              final repo = context.read<FocusRepository>();
              return _buildEmptyState(context, state, settingsState, repo);
            }
            final displayBooks = _filterBooksByTopics(
              books,
              state.selectedTopics,
            );
            final displayLimit = min(displayBooks.length, 100);
            final topicsHeader = _buildTopicsSelection(context, state);
            return SingleChildScrollView(
              key: PageStorageKey(state.currentCategory),
              child: Column(
                children: [
                  ?topicsHeader,
                  _buildSearchResultsGrid(displayBooks, displayLimit),
                ],
              ),
            );
          }
          final categoryItems = _buildCategoryContent(state.currentCategory!);
          if (categoryItems.isEmpty) {
            final repo = context.read<FocusRepository>();
            return _buildEmptyState(context, state, settingsState, repo);
          }
          return SingleChildScrollView(
            key: PageStorageKey(state.currentCategory),
            child: Column(children: categoryItems),
          );
        }
        if (state.searchResults != null) {
          final visibleResults = _visibleBooks(state.searchResults!);
          if (visibleResults.isEmpty) {
            final repo = context.read<FocusRepository>();
            return _buildEmptyState(context, state, settingsState, repo);
          }
          return _buildSearchListView(
            _filterBooksByTopics(visibleResults, state.selectedTopics),
            _buildTopicsSelection(context, state),
          );
        }
        return _buildListView(state.currentCategory!);
      },
    );
  }

  List<Widget> _buildCategoryContent(Category category) {
    final List<Widget> items = [];
    final filteredBooks = _visibleBooks(category.books);
    final filteredSubCategories = category.subCategories
        .where((c) => c.hasBooks)
        .toList();
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
      final isTourBook =
          _tourPreviewBook != null &&
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
            final isSelected =
                settingsState.libraryShowPreview &&
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

  Widget _buildSearchListView(List<Book> books, Widget? header) {
    return _LibraryBrowserList(
      header: header,
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

  Widget _buildListView(Category category) {
    final flatRows = _buildFlatTreeRows(category);
    if (flatRows.length <= _kLibraryTreeFlattenThreshold) {
      return _LibraryBrowserList(
        forPanel: false,
        children: _buildCategoryTree(category, 0),
      );
    }
    return _LibraryBrowserList(
      forPanel: false,
      itemCount: flatRows.length,
      itemBuilder: (context, index) =>
          _buildFlatTreeRow(context, flatRows[index]),
    );
  }

  List<FlatLibraryRow> _buildFlatTreeRows(Category category) =>
      buildFlatLibraryRows(
        category: category,
        expandedPaths: _expandedCategories,
        topCategoryOrder: _getTopCategoryOrder,
        normalizeOrder: _normalizeOrder,
        talmudTextTitles: _talmudTextTitles(),
      );

  /// Key יציב לשורה — בלעדיו אנימציית השברון ומצב hover "זולגים" בין
  /// שורות כשההרחבה מזיזה אינדקסים ב-ListView.builder.
  Key _flatRowKey(FlatLibraryRow row) => switch (row.kind) {
    FlatLibraryRowKind.categoryHeader => ValueKey(row.category!.path),
    // ObjectKey ולא title — מהדורות חיצוניות וצמדי טקסט/PDF יכולים
    // לשאת אותו title תחת אותו הורה.
    FlatLibraryRowKind.book ||
    FlatLibraryRowKind.rootBook => ObjectKey(row.book!),
    FlatLibraryRowKind.showMore => ValueKey('more:${row.parentPath}'),
  };

  /// בונה שורה משוטחת בסגנון הכרטיס של העץ המקונן: רקע כרטיס, מפריד בין
  /// שורות, פינות מעוגלות ורווח אנכי בקצות כל קבוצה עליונה.
  Widget _buildFlatTreeRow(BuildContext context, FlatLibraryRow row) {
    final isExpanded =
        row.category != null &&
        _expandedCategories.contains(row.category!.path);

    if (row.kind == FlatLibraryRowKind.rootBook) {
      return KeyedSubtree(
        key: _flatRowKey(row),
        child: _buildListBookItem(
          row.book!,
          row.level,
          itemStyle: _LibraryListItemStyle.root,
        ),
      );
    }

    // "הצג עוד" ברמה 0 מוצג חשוף גם בעץ המקונן — בלי עטיפת כרטיס.
    if (row.kind == FlatLibraryRowKind.showMore && row.level == 0) {
      return KeyedSubtree(
        key: _flatRowKey(row),
        child: _buildShowMoreRow(row.showMoreBooks!, row.level),
      );
    }

    final Widget child = switch (row.kind) {
      FlatLibraryRowKind.categoryHeader => _buildCategoryHeaderRow(
        row.category!,
        row.level,
        isExpanded,
      ),
      FlatLibraryRowKind.book => _buildListBookItem(
        row.book!,
        row.level,
        itemStyle: _LibraryListItemStyle.grouped,
      ),
      FlatLibraryRowKind.showMore => _buildShowMoreRow(
        row.showMoreBooks!,
        row.level,
      ),
      FlatLibraryRowKind.rootBook => throw StateError('unreachable'),
    };

    const radius = Radius.circular(AppTokens.radius);
    Widget content = Material(
      color: AppSurfaces.card(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!row.isGroupStart) AppCard.sectionDivider(context),
          child,
        ],
      ),
    );
    content = ClipRRect(
      borderRadius: BorderRadius.vertical(
        top: row.isGroupStart ? radius : Radius.zero,
        bottom: row.isGroupEnd ? radius : Radius.zero,
      ),
      child: content,
    );
    return KeyedSubtree(
      key: _flatRowKey(row),
      child: Padding(
        padding: EdgeInsets.only(
          top: row.isGroupStart ? 2 : 0,
          bottom: row.isGroupEnd ? 2 : 0,
        ),
        child: content,
      ),
    );
  }

  List<Widget> _buildCategoryTree(Category category, int level) {
    final List<Widget> widgets = [];
    final filteredBooks = _visibleBooks(category.books)
      ..sort((a, b) => a.order.compareTo(b.order));
    final filteredSubs = category.subCategories
        .where((c) => c.hasBooks)
        .toList();
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
      final subChildren = isExpanded
          ? _buildCategoryTree(sub, level + 1)
          : <Widget>[];
      if (level == 0) {
        widgets.add(
          ExpandableCard(
            key: ValueKey(sub.path),
            header: _buildCategoryHeaderRow(sub, level, isExpanded),
            isExpanded: isExpanded,
            margin: const EdgeInsets.symmetric(vertical: 2),
            children: subChildren,
          ),
        );
      } else {
        widgets.add(
          _buildNestedCategorySection(sub, level, isExpanded, subChildren),
        );
      }
    }
    for (int i = 0; i < filteredBooks.length && i < _kCategoryBooksCap; i++) {
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
    if (filteredBooks.length > _kCategoryBooksCap) {
      widgets.add(_buildShowMoreRow(filteredBooks, level));
    }
    return widgets;
  }

  /// שורת "הצג עוד" לקטגוריה שחצתה את מכסת הספרים המוצגים.
  Widget _buildShowMoreRow(List<Book> books, int level) {
    return InkWell(
      onTap: () => _showAllBooksDialog(books),
      child: Padding(
        padding: EdgeInsets.only(
          right: 16.0 + level * 18,
          left: 16,
          top: 10,
          bottom: 10,
        ),
        child: Text(
          'הצג עוד ${books.length - _kCategoryBooksCap} פריטים',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.secondary,
          ),
        ),
      ),
    );
  }

  /// שורת כותרת לתיקייה — ללא עטיפת כרטיס (נוסף ע"י [ExpandableCard]).
  Widget _buildCategoryHeaderRow(
    Category category,
    int level,
    bool isExpanded,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const double iconBoxSize = 26.0;
    const double iconSize = 14.0;
    const double horizontalPadding = 12.0;
    const double verticalPadding = 8.0;
    final indent = level * 18.0;
    final titleStyle = theme.textTheme.titleMedium?.merge(
      AppTextStyles.settingTitle.copyWith(
        fontWeight: level == 0 ? FontWeight.w700 : FontWeight.w600,
        color: cs.onSurface,
        height: level > 0 ? 1.15 : null,
      ),
    );

    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.zero,
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
          children: [
            Container(
              width: iconBoxSize,
              height: iconBoxSize,
              decoration: BoxDecoration(
                color: cs.secondaryContainer,
                borderRadius: AppTokens.borderRadiusAll,
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
                textAlign: TextAlign.right,
                style: titleStyle,
              ),
            ),
            ExpandingChevron(
              isExpanded: isExpanded,
              color: cs.onSecondaryContainer,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  /// שורת תיקייה מקוננת — ללא גבול כרטיס, מיועדת לשימוש
  /// בתוך [ExpandableCard.children] (רמה 1+).
  Widget _buildNestedCategorySection(
    Category category,
    int level,
    bool isExpanded,
    List<Widget> children,
  ) {
    return ExpandableCard(
      key: ValueKey(category.path),
      header: _buildCategoryHeaderRow(category, level, isExpanded),
      isExpanded: isExpanded,
      wrapInCard: false,
      children: children,
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
        borderRadius: isGrouped ? BorderRadius.zero : AppTokens.borderRadiusAll,
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
                      textAlign: TextAlign.right,
                      style: titleStyle,
                    ),
                    if (subtitle != null && subtitle.isNotEmpty)
                      LibraryOverflowTooltipText(
                        text: subtitle,
                        maxLines: 1,
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

    return AppCard(
      margin: const EdgeInsets.symmetric(vertical: 2),
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
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Center(
        child: _buildListRowIconChild(book, cs, iconSize),
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

  /// תוכן אייקון שורת הספר: לוגו הקטלוג החיצוני אם הספר הגיע ממנו (גם כשהוא
  /// ספר היברובוקס מקומי שהומר ל-PdfBook), אחרת אייקון לפי סוג הספר.
  Widget _buildListRowIconChild(Book book, ColorScheme cs, double iconSize) {
    final logoAsset = externalCatalogLogoAsset(book);
    if (logoAsset != null) {
      return Image.asset(
        logoAsset,
        width: iconSize,
        height: iconSize,
        fit: BoxFit.contain,
      );
    }
    return Icon(
      book is PdfBook
          ? FluentIcons.document_pdf_24_regular
          : book is DocxBook || book.fileType == 'docx'
          ? FluentIcons.document_edit_24_regular
          : FluentIcons.document_text_24_regular,
      color: cs.onSecondaryContainer,
      size: iconSize,
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
        borderRadius: AppTokens.borderRadiusAll,
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
            final isSelected =
                settingsState.libraryShowPreview &&
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

  Set<String>? _talmudTextTitlesCache;
  Category? _talmudTextTitlesLibrary;

  /// כותרות מהדורות הטקסט של מסכתות הבבלי, ממוטמנות פר-מופע ספרייה.
  Set<String> _talmudTextTitles() {
    final library = context.read<LibraryBloc>().state.library;
    if (library == null) return const {};
    if (!identical(library, _talmudTextTitlesLibrary)) {
      _talmudTextTitlesLibrary = library;
      _talmudTextTitlesCache = talmudBavliTextTitles(library);
    }
    return _talmudTextTitlesCache!;
  }

  /// מסנן מהתצוגה מהדורות PDF כפולות של מסכתות הבבלי — מוצגת רשומה אחת
  /// למסכת, והפתיחה נקבעת לפי הגדרת פורמט הבבלי.
  List<Book> _visibleBooks(List<Book> books) {
    final titles = _talmudTextTitles();
    return books
        .where((b) => !isTalmudBavliPdfLibraryDuplicate(b, titles))
        .toList();
  }

  Future<void> _openBookInReader(Book book, int index) async {
    final handled = await openLibraryBookPerTalmudBavliFormat(
      context,
      book,
      index,
    );
    if (handled || !mounted) return;
    openBook(context, book, index, '');
  }

  /// מחזיר את הספר הראשון שיוצג בפועל בקטגוריה, לפי אותו סדר תצוגה כמו _buildCategoryContent
  Book? _getFirstDisplayedBook(Category category) {
    final books = _visibleBooks(category.books)
      ..sort((a, b) => a.order.compareTo(b.order));
    if (books.isNotEmpty) return books.first;

    final subs = category.subCategories.toList();
    if (category is Library) {
      subs.sort(
        (a, b) => _getTopCategoryOrder(a).compareTo(_getTopCategoryOrder(b)),
      );
    } else {
      subs.sort(
        (a, b) => _normalizeOrder(a.order).compareTo(_normalizeOrder(b.order)),
      );
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
        (a, b) => _getTopCategoryOrder(a).compareTo(_getTopCategoryOrder(b)),
      );
    } else {
      subs.sort(
        (a, b) => _normalizeOrder(a.order).compareTo(_normalizeOrder(b.order)),
      );
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
        title: Text(
          'כל הספרים (${books.length})',
        ),
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

  /// מסנן את התוצאות המוצגות לפי הקטגוריות הנבחרות — ספר נכלל אם הוא שייך לאחת
  /// מהן (OR). כל צ'יפ נגזר מהתוצאות הקיימות, ולכן הסינון לעולם לא ריק. הרשימה
  /// המלאה נשמרת ב-state כדי שצ'יפי שאר הקטגוריות יישארו.
  List<Book> _filterBooksByTopics(List<Book> books, List<String>? topics) {
    if (topics == null || topics.isEmpty) return books;
    return books.where((book) {
      final bookTopics = book.topics.split(',').map((t) => t.trim()).toSet();
      return topics.any(bookTopics.contains);
    }).toList();
  }

  void _update(
    BuildContext context,
    LibraryState state,
    SettingsState settingsState, {
    bool restoreSearchFocus = false,
    bool selectAllOnRestore = false,
  }) {
    _searchDebounce?.cancel();
    final searchText = context
        .read<FocusRepository>()
        .librarySearchController
        .text;
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
        final crossAxisCount = (constraints.maxWidth ~/ 250)
            .clamp(1, 5)
            .toInt();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 45),
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: 2,
                crossAxisSpacing: kLibraryGridSpacing,
                mainAxisSpacing: kLibraryGridSpacing,
              ),
              itemCount: displayLimit,
              itemBuilder: (context, index) {
                final orderIndex = index;
                final focusNode = index == 0
                    ? _firstSearchResultFocusNode
                    : null;

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
      builder: (ctx, previewState) => BookPreviewPanel(
        book: previewState.previewBook,
        onOpenInReader: (i) {
          if (previewState.previewBook != null) {
            _openBookInReader(previewState.previewBook!, i);
          }
        },
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
      title: 'הגדרות',
      child: const Expanded(
        child: SingleChildScrollView(
          child: LibrarySettingsPanel(hebrewBooksPathWidget: null),
        ),
      ),
    );
  }
}

// ── _SearchingIndicator ───────────────────────────────────────────────────────

class _SearchingIndicator extends StatelessWidget {
  const _SearchingIndicator();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: cs.primary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'מחפש...',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
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
      builder: (_, _) {
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
    this.header,
    this.forPanel = false,
  }) : assert(
         children != null || (itemCount != null && itemBuilder != null),
         'Provide either children or itemCount with itemBuilder',
       );

  final List<Widget>? children;
  final int? itemCount;
  final NullableIndexedWidgetBuilder? itemBuilder;

  /// פריט קבוע בראש הרשימה (למשל צ'יפי סינון) — נגלל יחד עם התוצאות.
  final Widget? header;
  final bool forPanel;

  @override
  Widget build(BuildContext context) {
    final padding = forPanel
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
        : const EdgeInsets.symmetric(horizontal: 16, vertical: 8);

    if (children != null) {
      return ListView(
        padding: padding,
        children: [
          ?header,
          ...children!,
        ],
      );
    }

    final hasHeader = header != null;
    return ListView.builder(
      padding: padding,
      itemCount: itemCount! + (hasHeader ? 1 : 0),
      itemBuilder: (context, index) {
        if (hasHeader && index == 0) return header!;
        return itemBuilder!(context, hasHeader ? index - 1 : index);
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/search/search_defaults.dart';
import 'package:otzaria/search/view/full_text_settings_widgets.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/widgets/navigation/nav_panel_search.dart';
import 'package:otzaria/widgets/navigation/nav_side_panel.dart';
import 'package:otzaria/widgets/navigation/reader_nav_center.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';

/// רוחב הסרגל שמתחתיו בוררי המיון והאיחוד מתכווצים לכפתורי אייקון.
/// הבדיקה היא על רוחב הסרגל עצמו (ולא על גודל החלון), כדי שהכיווץ יקרה
/// בדיוק כשאין מקום לשני ה-dropdown ברוחב מלא.
const double _kMenusCollapseWidth = 900;

/// פריסת מסך תוצאות החיפוש, משותפת לחיפוש הרגיל ולחיפוש החכם: סרגל עליון
/// עם מילות החיפוש והמונים, חלונית הקטגוריות והתוצאות.
class SearchResultsLayout extends StatefulWidget {
  const SearchResultsLayout({
    super.key,
    required this.tab,
    required this.hasQuery,
    required this.onEditSearch,
    required this.countsBuilder,
    required this.resultsBuilder,
    required this.facetPane,
    this.extraTrailingItems,
    this.header,
    this.banners = const [],
    this.label = 'חיפוש',
    this.query,
  });

  final SearchingTab tab;
  final bool hasQuery;
  final VoidCallback onEditSearch;

  /// מוני התוצאות בסרגל; [collapsed] כשהסרגל צר.
  final Widget Function(BuildContext context, bool collapsed) countsBuilder;

  /// אזור התוצאות; חלונית התצוגה המקדימה מוצגת רק בפריסה הרחבה.
  final Widget Function(bool showPreviewPane) resultsBuilder;

  /// עץ הקטגוריות עם הספירות.
  final Widget facetPane;

  /// פקדים נוספים בסוף הסרגל, אחרי לחצן התצוגה המקדימה.
  final List<AppTopBarItem> Function(bool collapsed)? extraTrailingItems;

  /// מעל הסרגל (למשל אזהרת אינדוקס).
  final Widget? header;

  /// מתחת לסרגל, מעל התוצאות.
  final List<Widget> banners;

  /// התווית שלפני מילות החיפוש בפריסה הרחבה.
  final String label;

  /// השאילתה שבסרגל, כשאינה של ה-SearchBloc של הכרטיסייה.
  final String? query;

  /// מעבר מונפש בין ה-dropdown המלא לכפתור האייקון המכווץ.
  static Widget animatedBarControl({
    required bool collapsed,
    required Widget child,
  }) {
    return AnimatedSize(
      duration: AppTokens.animNormal,
      curve: Curves.easeInOut,
      child: AnimatedSwitcher(
        duration: AppTokens.animNormal,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: animation, child: child),
        ),
        child: KeyedSubtree(key: ValueKey(collapsed), child: child),
      ),
    );
  }

  @override
  State<SearchResultsLayout> createState() => _SearchResultsLayoutState();
}

class _SearchResultsLayoutState extends State<SearchResultsLayout> {
  // במסך צר עץ הקטגוריות תופס את כל הרוחב ומסתיר את התוצאות. לכן בכניסה
  // הראשונה לכל טאב במסך צר סוגרים את העץ אוטומטית.
  bool _appliedNarrowLeftPaneDefault = false;
  // רוחב חי של פאנל הסינון בזמן גרירה; נשמר להגדרות ב-onPaneResizeEnd.
  double? _facetPaneWidthOverride;

  /// פעולת החיפוש של חלונית הסינון — מוזנת לסרגל שבסרגל העליון.
  final NavPanelSearchHost _searchHost = NavPanelSearchHost();

  @override
  void dispose() {
    _searchHost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 800;
        if (isNarrow &&
            !_appliedNarrowLeftPaneDefault &&
            widget.tab.isLeftPaneOpen.value) {
          _appliedNarrowLeftPaneDefault = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.tab.isLeftPaneOpen.value = false;
          });
        }
        final collapseMenus = constraints.maxWidth < _kMenusCollapseWidth;
        if (isNarrow) return _buildForSmallScreens(collapseMenus);
        return _buildForWideScreens(collapseMenus);
      },
    );
  }

  Widget _buildForSmallScreens(bool collapseMenus) {
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      child: Column(
        children: [
          ?widget.header,
          _buildSearchTopBar(collapseMenus: collapseMenus),
          ...widget.banners,
          Expanded(
            child: Stack(
              children: [
                Container(
                  clipBehavior: Clip.hardEdge,
                  decoration: const BoxDecoration(),
                  child: widget.resultsBuilder(false),
                ),
                ValueListenableBuilder(
                  valueListenable: widget.tab.isLeftPaneOpen,
                  builder: (context, value, child) => AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    child: SizedBox(
                      width: value ? 500 : 0,
                      child: Container(
                        color: Theme.of(context).colorScheme.surface,
                        child: Column(
                          children: [Expanded(child: widget.facetPane)],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForWideScreens(bool collapseMenus) {
    return Column(
      children: [
        ?widget.header,
        _buildSearchTopBar(collapseMenus: collapseMenus, isWideLayout: true),
        ...widget.banners,
        Expanded(
          child: ValueListenableBuilder<bool>(
            valueListenable: widget.tab.isLeftPaneOpen,
            builder: (context, isOpen, _) {
              return BlocBuilder<SettingsBloc, SettingsState>(
                buildWhen: (p, c) =>
                    p.facetFilteringWidth != c.facetFilteringWidth,
                builder: (context, settingsState) {
                  final paneWidth =
                      (_facetPaneWidthOverride ??
                              settingsState.facetFilteringWidth)
                          .clamp(220.0, 600.0);
                  return NavSidePanel(
                    isOpen: isOpen,
                    alignment: AlignmentDirectional.centerEnd,
                    mainContent: Container(
                      clipBehavior: Clip.hardEdge,
                      decoration: const BoxDecoration(),
                      child: widget.resultsBuilder(true),
                    ),
                    paneContent: NavPanelSearchScope(
                      host: _searchHost,
                      child: NavPanelSearchSlot(
                        index: 0,
                        child: widget.facetPane,
                      ),
                    ),
                    paneWidth: paneWidth,
                    minMainContentWidth: 300,
                    onClose: () => _setLeftPaneOpen(false),
                    isResizable: true,
                    minPaneWidth: 220,
                    maxPaneWidth: 600,
                    autoHandleResponsiveVisibility: false,
                    onPaneWidthChanged: (w) => _facetPaneWidthOverride = w,
                    onPaneResizeEnd: () {
                      final w = _facetPaneWidthOverride;
                      if (w != null) {
                        context.read<SettingsBloc>().add(
                          UpdateFacetFilteringWidth(w),
                        );
                      }
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// שינוי מצב עץ התוצאות ביוזמת המשתמש — נשמר גם כברירת מחדל גלובלית.
  /// סגירות אוטומטיות (מסך צר, הרצת חיפוש) אינן עוברות כאן בכוונה.
  void _setLeftPaneOpen(bool isOpen) {
    widget.tab.isLeftPaneOpen.value = isOpen;
    SearchDefaults.saveResultsTreeOpenDefault(isOpen);
  }

  /// הסרגל העליון — זהה בכל רוחבי המסך.
  /// [collapseMenus] מכווץ את בוררי המיון והאיחוד לכפתורי אייקון.
  Widget _buildSearchTopBar({
    required bool collapseMenus,
    bool isWideLayout = false,
  }) {
    final hasQuery = widget.hasQuery;
    return AppTopBar(
      minCenterWidth: ReaderNavCenter.minTitleWidth,
      leadingItems: [
        AppTopBarItem(
          widget: ValueListenableBuilder<bool>(
            valueListenable: widget.tab.isLeftPaneOpen,
            builder: (context, isOpen, _) => NavPanelToggleButton(
              isOpen: isOpen,
              onToggle: () => _setLeftPaneOpen(!isOpen),
            ),
          ),
        ),
      ],
      center: hasQuery
          ? _buildQueryDisplay(context, showLabel: isWideLayout)
          : const SizedBox.shrink(),
      trailingItems: hasQuery
          ? [
              AppTopBarItem(
                // בלוק המונים מצטמצם עם ellipsis כשאין מקום לשאר הפקדים,
                // במקום לדחוף אותם אל מחוץ לסרגל.
                flexible: true,
                widget: widget.countsBuilder(context, collapseMenus),
              ),
              // לחצן העין קיים רק בפריסה הרחבה — שם יש חלונית תצוגה מקדימה.
              if (isWideLayout)
                AppTopBarItem(
                  dividerBefore: true,
                  widget: _buildPreviewToggleButton(),
                ),
              ...?widget.extraTrailingItems?.call(collapseMenus),
            ]
          : const [],
    );
  }

  /// לחצן עין לכיבוי/הפעלה קבועים של התצוגה המקדימה של תוצאות — כמו בספרייה.
  Widget _buildPreviewToggleButton() {
    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (p, c) =>
          p.searchShowPreview != c.searchShowPreview ||
          p.compactMenuMode != c.compactMenuMode,
      builder: (context, settingsState) {
        final showPreview = settingsState.searchShowPreview;
        return BarButton.icon(
          compact: settingsState.compactMenuMode,
          tooltip: showPreview ? 'הסתר תצוגה מקדימה' : 'הצג תצוגה מקדימה',
          icon: showPreview
              ? FluentIcons.eye_24_filled
              : FluentIcons.eye_24_regular,
          selected: showPreview,
          onPressed: () {
            final next = !showPreview;
            context.read<SettingsBloc>().add(UpdateSearchShowPreview(next));
            if (!next) {
              widget.tab.previewTarget.value = null;
            }
          },
        );
      },
    );
  }

  /// מילות החיפוש בתוך סרגל בעיצוב שדה החיפוש; לחיצה עליו פותחת את דיאלוג
  /// העריכה. בפריסה הצרה התווית 'חיפוש' מושמטת — היא משכפלת את שם הכרטיסייה
  /// ובולעת כמחצית מהמרחב שנשמר למילות החיפוש.
  Widget _buildQueryDisplay(BuildContext context, {required bool showLabel}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showLabel) ...[
          Text(
            widget.label,
            style: TextStyle(
              fontSize: AppTokens.fontMD,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppTokens.spaceSM),
        ],
        Flexible(
          child: OtzariaSearchDisplayBar(
            icon: FluentIcons.edit_24_regular,
            tooltip: 'ערוך חיפוש',
            onTap: widget.onEditSearch,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SearchTermsDisplay(
                  tab: widget.tab,
                  query: widget.query,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

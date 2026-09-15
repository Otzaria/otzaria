import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/core/windowing/cross_window_tab_drag.dart';
import 'package:otzaria/core/windowing/drag_preview_colors.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/navigation/view/reading_tab_strip.dart';
import 'package:otzaria/navigation/view/tab_context_menu.dart';
import 'package:otzaria/navigation/view/tab_visuals.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/misc/middle_click_autoscroll.dart';

/// גובה שורת כרטיסיה בעמודה האנכית.
const double kVerticalTabHeight = 38;

/// רוחב העמודה במצב מכווץ — רק אייקוני סוג הכרטיסיה.
const double kCollapsedTabsColumnWidth = 48;

/// רשימת כרטיסיות העיון כעמודה אנכית, בסגנון הכרטיסיות האנכיות של Edge.
///
/// נשענת על אותה [ReadingTabStrip] של הרצועה האופקית, כדי שהגרירה תמשיך
/// לשרת גם את פיצול החלוניות (אותו מטען מתקבל ב-`PaneDropTarget`).
class VerticalReadingTabStrip extends StatefulWidget {
  /// במצב מכווץ מוצג רק אייקון, והכותרת עוברת ל-tooltip.
  final bool collapsed;

  /// רוחב העמודה — דרוש לכרטיסיה הצפה בגרירה.
  final double width;

  const VerticalReadingTabStrip({
    super.key,
    required this.collapsed,
    required this.width,
  });

  @override
  State<VerticalReadingTabStrip> createState() =>
      _VerticalReadingTabStripState();
}

class _VerticalReadingTabStripState extends State<VerticalReadingTabStrip> {
  /// הכרטיסיה שהעכבר מעליה. שדה ולא משתנה מקומי: בנייה מחדש של העמודה הייתה
  /// מוחקת את ה-X מתחת לסמן לפני שהלחיצה עליו נורית.
  OpenedTab? _hoveredTab;

  /// ⚠️ אותו מנגנון בדיוק כמו ברצועה האופקית. קודם לכן הוא היה כתוב בתוך
  /// `custom_title_bar` בלבד, והעמודה האנכית לא חוברה אליו — היא **כן**
  /// קלטה כרטיסיות מחלונות אחרים, ולכן הפיצ'ר היה חד-כיווני בשקט: משתמש
  /// שעבד עם כרטיסיות בצד יכול היה לקבל כרטיסיה ולא להוציא אחת.
  final CrossWindowTabDrag _crossWindowDrag = CrossWindowTabDrag();

  @override
  void dispose() {
    _crossWindowDrag.dispose();
    super.dispose();
  }

  bool get _isMultiSelectModifierPressed {
    final keyboard = HardwareKeyboard.instance;
    return defaultTargetPlatform == TargetPlatform.macOS
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
  }

  void _closeTab(OpenedTab tab) {
    final selectedTabs = context.read<TabsBloc>().state.selectedTabs;
    if (selectedTabs.length > 1 && selectedTabs.contains(tab)) {
      closeSelectedTabsWithHistory(context);
      return;
    }
    closeTabWithHistory(context, tab);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TabsBloc, TabsState>(
      builder: (context, state) {
        // MouseRegion.onExit אינו נורה כששורת הכרטיסיה מוסרת מהעץ, ולכן סגירת
        // הכרטיסיה שהסמן מעליה הייתה משאירה הפניה חזקה אליה עד הריחוף הבא.
        final hovered = _hoveredTab;
        if (hovered != null && !state.tabs.any((t) => identical(t, hovered))) {
          _hoveredTab = null;
        }

        if (!state.hasOpenTabs) return const SizedBox.shrink();

        final platform = Theme.of(context).platform;
        final isDesktop =
            platform == TargetPlatform.windows ||
            platform == TargetPlatform.linux ||
            platform == TargetPlatform.macOS;

        return ReadingTabStrip(
          stripColor: AppSurfaces.readerBackground(context),
          axis: Axis.vertical,
          scrollable: true,
          crossExtent: widget.width,
          tabs: state.tabs,
          widths: [for (final _ in state.tabs) kVerticalTabHeight],
          requireLongPressToDrag: !isDesktop,
          onReorder: (tab, newIndex) =>
              context.read<TabsBloc>().add(MoveTab(tab, newIndex)),
          // חלונית של טאב מפוצל שנגררת לעמודה חוזרת לכרטיסייה עצמאית.
          acceptsExternal: (tab) => context.read<TabsBloc>().state.tabs.any(
            (t) => t is CombinedTab && t.sibling(tab) != null,
          ),
          onExternalDrop: (tab, insertIndex) => context.read<TabsBloc>().add(
            DetachPane(tab, insertIndex: insertIndex),
          ),
          onDragStarted: (draggedTab, cancelDrag) => _crossWindowDrag.begin(
            draggedTab,
            DragPreviewColors.of(context),
            tabsBloc: context.read<TabsBloc>(),
            cancelDrag: cancelDrag,
          ),
          onTabSnapshot: (_, snapshot, generation) =>
              _crossWindowDrag.applySnapshot(snapshot, generation),
          onDragFinishedAnywhere: _crossWindowDrag.end,
          onDragLeftStrip: _crossWindowDrag.notePointerLeftStrip,
          onDroppedOutside: MultiWindowService.canDragTabsOut
              ? (tab) => _crossWindowDrag.handleDroppedOutside(
                  tab,
                  context.read<TabsBloc>(),
                )
              : null,
          onSpringOpen: (tab) {
            // ה-state שנתפס ב-build עלול להיות מיושן באמצע גרירה.
            final bloc = context.read<TabsBloc>();
            final index = bloc.state.tabs.indexOf(tab);
            if (index != -1 && index != bloc.state.currentTabIndex) {
              bloc.add(SetCurrentTab(index));
            }
          },
          tabBuilder: (tab, index, extent) => SizedBox(
            height: extent,
            child: _buildTab(context, tab, index, state),
          ),
        );
      },
    );
  }

  Widget _buildTab(
    BuildContext context,
    OpenedTab tab,
    int index,
    TabsState state,
  ) {
    return _wrapWithTabPointer(
      context,
      tab,
      index,
      state,
      child: AppContextMenuRegion(
        menuBuilder: (menuCtx, _) => buildTabContextMenuEntries(
          context,
          tab,
          state,
          onCloseTab: _closeTab,
          onCloseSelectedTabs: () => closeSelectedTabsWithHistory(context),
        ),
        child: StatefulBuilder(
          builder: (context, setLocalState) {
            final isHovered = identical(_hoveredTab, tab);
            return MouseRegion(
              onEnter: (_) => setLocalState(() => _hoveredTab = tab),
              onExit: (_) => setLocalState(() {
                if (identical(_hoveredTab, tab)) _hoveredTab = null;
              }),
              child: _VerticalTabRow(
                tab: tab,
                collapsed: widget.collapsed,
                isSelected: index == state.currentTabIndex,
                isInSelection: state.selectedTabs.contains(tab),
                isHovered: isHovered,
                onClose: () => _closeTab(tab),
              ),
            );
          },
        ),
      ),
    );
  }

  /// בחירה מרובה ולחצן אמצעי מטופלים ב-pointer-down (לחיצה ימנית אינה בוחרת),
  /// והבחירה עצמה ב-onTap.
  ///
  /// ה-onTap הכרחי ולא רק נוח: בלעדיו הגרירה המיידית היא היחידה בזירת המחוות
  /// כאן, זוכה בה כבר בלחיצה ללא תזוזה, והלחיצה נבלעת כגרירה.
  Widget _wrapWithTabPointer(
    BuildContext context,
    OpenedTab tab,
    int index,
    TabsState state, {
    required Widget child,
  }) {
    return Listener(
      onPointerDown: (event) {
        if (event.buttons == 4) {
          _closeTab(tab);
          return;
        }
        if (event.buttons != 1) return;
        if (_isMultiSelectModifierPressed) {
          context.read<TabsBloc>().add(ToggleTabSelection(tab));
          return;
        }
        if (HardwareKeyboard.instance.isShiftPressed) {
          context.read<TabsBloc>().add(SelectTabRange(tab));
          return;
        }
        if (state.selectedTabs.isNotEmpty) {
          context.read<TabsBloc>().add(const ClearTabSelection());
        }
      },
      child: GestureDetector(
        onTap: () {
          if (_isMultiSelectModifierPressed ||
              HardwareKeyboard.instance.isShiftPressed) {
            return;
          }
          // ה-state שנתפס ב-build עלול להיות מיושן עד הלחיצה.
          final bloc = context.read<TabsBloc>();
          final target = bloc.state.tabs.indexOf(tab);
          if (target != -1 && target != bloc.state.currentTabIndex) {
            bloc.add(SetCurrentTab(target));
          }
        },
        child: AutoScrollBarrier(child: child),
      ),
    );
  }
}

/// שורת כרטיסיה אחת בעמודה: אייקון סוג, כותרת, נעץ ו-X.
class _VerticalTabRow extends StatelessWidget {
  final OpenedTab tab;
  final bool collapsed;
  final bool isSelected;
  final bool isInSelection;
  final bool isHovered;
  final VoidCallback onClose;

  const _VerticalTabRow({
    required this.tab,
    required this.collapsed,
    required this.isSelected,
    required this.isInSelection,
    required this.isHovered,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final background = isInSelection
        ? cs.secondaryContainer
        : isSelected
        ? cs.surfaceContainerHighest
        : isHovered
        ? cs.surfaceContainerHigh
        : Colors.transparent;

    final leading = buildTabTypeIcon(context, tab);
    final showClose = !collapsed && (isSelected || isHovered);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: collapsed ? 0 : 8,
            end: collapsed ? 0 : 4,
          ),
          child: DefaultTextStyle(
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
            child: LiveTabTitleBuilder(
              tab: tab,
              builder: (context, displayTitle, tooltipMessage) => collapsed
                  // במצב מכווץ מוצג אייקון בלבד, ולכן ה-tooltip הוא המקור היחיד לשם.
                  ? Tooltip(
                      message: tooltipMessage,
                      child: Center(
                        child: leading ?? buildTabFallbackIcon(context),
                      ),
                    )
                  : Row(
                      children: [
                        if (leading != null) ...[
                          leading,
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: TabTitleTooltip(
                            message: tooltipMessage,
                            title: displayTitle,
                            child: buildFadedTabTitle(context, displayTitle),
                          ),
                        ),
                        if (showClose)
                          IconButton(
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: EdgeInsets.zero,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 24,
                              minHeight: 24,
                              maxWidth: 24,
                              maxHeight: 24,
                            ),
                            tooltip: context.settingsText('סגור כרטיסיה'),
                            onPressed: onClose,
                            icon: const Icon(
                              FluentIcons.dismiss_24_regular,
                              size: 12,
                            ),
                          ),
                        if (tab.isPinned) ...[
                          const SizedBox(width: 4),
                          const Icon(FluentIcons.pin_24_filled, size: 14),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

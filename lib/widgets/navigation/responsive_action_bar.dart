import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';

/// זהות לוגית של פעולה שיכולה להופיע בשורת הכלים של הקורא.
///
/// המיקום של הערך ב-[toolbarOverflowOrder] קובע מתי הפעולה
/// עוברת לתפריט "...".
enum ToolbarActionId {
  plugin,
  search,
  handMode,
  zoomOut,
  zoomIn,
  continuousReading,
  punctuation,
  nikud,
  viewMode,
  openCommentatorsTab,
  parallelEdition,
  // כרטיסיות מפרשים (טקסט ו-PDF)
  expandAll,
  bookmarkAdd,
  print,
  // ספרייה
  navigateUp,
  navigateHome,
  sync,
  refresh,
}

/// סדר ההעברה לתפריט overflow.
///
/// הערך הראשון עובר ראשון ל-"...".
/// הערך האחרון נשאר בשורת הכלים זמן רב ככל האפשר.
///
/// כדי לשנות את מדיניות הקדימות יש לשנות רק את הרשימה הזאת.
/// בעת הוספת סוג חדש של כפתור לשורת הכלים יש:
/// 1. להוסיף ערך ל-[ToolbarActionId].
/// 2. להוסיף אותו בדיוק פעם אחת לרשימה הזאת.
const List<ToolbarActionId> toolbarOverflowOrder = [
  ToolbarActionId.plugin,
  ToolbarActionId.search,
  ToolbarActionId.handMode,
  ToolbarActionId.zoomOut,
  ToolbarActionId.zoomIn,
  ToolbarActionId.continuousReading,
  ToolbarActionId.punctuation,
  ToolbarActionId.nikud,
  ToolbarActionId.viewMode,
  ToolbarActionId.openCommentatorsTab,
  ToolbarActionId.parallelEdition,
  // כרטיסיות מפרשים
  ToolbarActionId.expandAll,
  ToolbarActionId.bookmarkAdd,
  ToolbarActionId.print,
  // ספרייה — משתמשת ב-originalOrder (מצב ישן), הסדר כאן לא פעיל
  ToolbarActionId.navigateUp,
  ToolbarActionId.navigateHome,
  ToolbarActionId.sync,
  ToolbarActionId.refresh,
];

final Map<ToolbarActionId, int> toolbarOverflowRank = {
  for (var i = 0; i < toolbarOverflowOrder.length; i++)
    toolbarOverflowOrder[i]: i,
};

int toolbarOverflowRankOf(ToolbarActionId id) {
  final rank = toolbarOverflowRank[id];

  if (rank == null) {
    throw StateError(
      'ToolbarActionId.$id is missing from toolbarOverflowOrder',
    );
  }

  return rank;
}

/// פעולות שחייבות לעבור לתפריט overflow יחד — לעולם לא נשאיר רק חלק מהקבוצה גלוי.
///
/// כדי להוסיף קבוצה אטומית חדשה: הוסף Set נוסף לרשימה.
/// אין צורך לשנות ActionButtonData.
const List<Set<ToolbarActionId>> toolbarAtomicOverflowGroups = [
  {ToolbarActionId.zoomOut, ToolbarActionId.zoomIn},
];

/// מחזיר את קבוצת ה-IDs שאליה שייך [id], כולל עצמו.
/// אם [id] אינו שייך לאף קבוצה אטומית, מחזיר קבוצה של איבר יחיד.
Set<ToolbarActionId> atomicGroupOf(ToolbarActionId id) {
  for (final group in toolbarAtomicOverflowGroups) {
    if (group.contains(id)) return group;
  }
  return {id};
}

/// רכיב שמציג כפתורי פעולה עם יכולת הסתרה במסכים צרים
/// כשחלק מהכפתורים נסתרים, מוצג כפתור "..." שפותח תפריט
///
/// תומך בשני מצבי עבודה:
/// 1. מצב חדש: `actions` + `alwaysInMenu` - כפתורים נעלמים בסדר ההצגה, ותמיד יש תפריט עם כפתורים קבועים
/// 2. מצב ישן: `actions` + `originalOrder` - כפתורים נעלמים לפי עדיפות, תפריט רק אם צריך
class ResponsiveActionBar extends StatefulWidget {
  /// רשימת כפתורי הפעולה.
  /// במצב חדש: סדר ההצגה (מימין לשמאל ב-RTL)
  /// במצב ישן: סדר עדיפות (החשוב ביותר ראשון)
  final List<ActionButtonData> actions;

  /// [מצב חדש] כפתורים שתמיד יהיו בתפריט "..." (גם במסכים רחבים)
  final List<ActionButtonData>? alwaysInMenu;

  /// [מצב ישן] הסדר המקורי של הכפתורים (לתצוגה עקבית)
  final List<ActionButtonData>? originalOrder;

  /// פעולות ניווט שמוצגות כשורת אייקונים בראש התפריט במקום כפריטים נפרדים.
  /// לחיצה עליהן משאירה את התפריט פתוח; לכל פעולה נדרש [ActionButtonData.icon].
  final List<ActionButtonData>? menuHeaderActions;

  /// מספר מקסימלי של כפתורים להציג לפני מעבר לתפריט "..."
  final int? maxVisibleButtons;

  /// האם כפתור "..." יהיה בצד ימין (ברירת מחדל: false - שמאל)
  final bool overflowOnRight;

  /// היסט מיקום לתפריט ה-"..." ביחס לכפתור.
  final Offset overflowMenuOffset;
  final GlobalKey? overflowButtonKey;
  final bool openOverflowMenu;
  final Map<String, GlobalKey>? menuItemKeysByTooltip;

  const ResponsiveActionBar({
    super.key,
    required this.actions,
    this.alwaysInMenu,
    this.originalOrder,
    this.menuHeaderActions,
    this.maxVisibleButtons,
    this.overflowOnRight = false,
    this.overflowMenuOffset = const Offset(0, 4),
    this.overflowButtonKey,
    this.openOverflowMenu = false,
    this.menuItemKeysByTooltip,
  }) : assert(
         alwaysInMenu != null || originalOrder != null,
         'Either alwaysInMenu or originalOrder must be provided',
       );

  @override
  State<ResponsiveActionBar> createState() => _ResponsiveActionBarState();
}

@visibleForTesting
({List<ActionButtonData> visible, List<ActionButtonData> hidden})
partitionToolbarActionsForWidth({
  required List<ActionButtonData> actions,
  required double maxWidth,
  required double standardButtonWidth,
  required double overflowButtonWidth,
  required bool overflowAlreadyRequired,
  int? maxVisibleButtons,
}) {
  double widthOf(ActionButtonData action) =>
      action.toolbarWidth ?? standardButtonWidth;

  // Validation מפורש: כל action חייב actionId לפני כל לוגיקה. // validate
  for (final action in actions) {
    if (action.actionId == null) {
      throw StateError('Every toolbar action must define an actionId.');
    }
  }

  int rankOf(ActionButtonData action) {
    final id = action.actionId;

    if (id == null) {
      throw StateError(
        'Toolbar action "${action.tooltip ?? '<unknown>'}" '
        'is missing actionId. '
        'Add a ToolbarActionId and place it in toolbarOverflowOrder.',
      );
    }

    return toolbarOverflowRankOf(id);
  }

  final indexed = <(int, ActionButtonData)>[
    for (var i = 0; i < actions.length; i++) (i, actions[i]),
  ];

  final candidates = [...indexed]
    ..sort((a, b) {
      final byRank = rankOf(a.$2).compareTo(rankOf(b.$2));

      if (byRank != 0) {
        return byRank;
      }

      // באותה עדיפות מסתירים קודם את המאוחר יותר בסדר התצוגה.
      return b.$1.compareTo(a.$1);
    });

  final hiddenIndexes = <int>{};

  // היסטוריית קבוצות ההסרה לפי סדר ההסרה — לשחזור LIFO.
  final removedGroups = <List<int>>[];

  var visibleWidth = indexed.fold<double>(
    0,
    (sum, entry) => sum + widthOf(entry.$2),
  );

  var overflowRequired = overflowAlreadyRequired;

  bool mustHideMore() {
    final visibleCount = actions.length - hiddenIndexes.length;

    if (maxVisibleButtons != null && visibleCount > maxVisibleButtons) {
      return true;
    }

    if (!maxWidth.isFinite) {
      return false;
    }

    final requiredWidth =
        visibleWidth + (overflowRequired ? overflowButtonWidth : 0.0);

    return requiredWidth > maxWidth;
  }

  var cursor = 0;

  while (mustHideMore() && cursor < candidates.length) {
    final candidate = candidates[cursor++];

    if (hiddenIndexes.contains(candidate.$1)) {
      continue;
    }

    // וידוא שה-candidate מחזיק actionId תקין (נזרק StateError אם לא).
    rankOf(candidate.$2);

    // מצא את כל חברי הקבוצה האטומית של ה-candidate שעדיין גלויים.
    // קבוצת singleton (group.length == 1) → רק ה-candidate עצמו.
    // קבוצה אמיתית (group.length > 1) → כל חברי הקבוצה הגלויים.
    final group = atomicGroupOf(candidate.$2.actionId!);
    final groupMembers = group.length > 1
        ? indexed
              .where(
                (e) =>
                    !hiddenIndexes.contains(e.$1) &&
                    e.$2.actionId != null &&
                    group.contains(e.$2.actionId),
              )
              .toList()
        : [candidate];

    // הסתר את כל חברי הקבוצה ותעד אותה בהיסטוריה.
    final removedIndexes = <int>[];
    for (final member in groupMembers) {
      hiddenIndexes.add(member.$1);
      visibleWidth -= widthOf(member.$2);
      removedIndexes.add(member.$1);
    }
    removedGroups.add(removedIndexes);

    overflowRequired = true;

    // Rebalance LIFO: נסה להחזיר קבוצות שהוסרו לפני הקבוצה הנוכחית, מהאחרונה ראשונה.
    // הקבוצה הנוכחית (האחרונה ב-removedGroups) לא נבדקת — היא זו שגרמה לפינוי המקום.
    for (var gi = removedGroups.length - 2; gi >= 0; gi--) {
      final groupIndexes = removedGroups[gi];

      // דלג על קבוצה שכבר הוחזרה (כל חבריה כבר גלויים).
      if (groupIndexes.every((idx) => !hiddenIndexes.contains(idx))) {
        continue;
      }

      // בדוק אם כל חברי הקבוצה שעדיין נסתרים יכולים להיכנס יחד.
      final stillHidden = groupIndexes
          .where((idx) => hiddenIndexes.contains(idx))
          .toList();
      final groupWidth = stillHidden.fold<double>(
        0,
        (sum, idx) => sum + widthOf(indexed[idx].$2),
      );
      final requiredWithRestore =
          visibleWidth + groupWidth + overflowButtonWidth;

      if (!maxWidth.isFinite || requiredWithRestore <= maxWidth) {
        for (final idx in stillHidden) {
          hiddenIndexes.remove(idx);
          visibleWidth += widthOf(indexed[idx].$2);
        }
        // הקבוצה הוחזרה — לא נוספת מחדש להיסטוריה.
      }
    }
  }

  final visible = <ActionButtonData>[];
  final hidden = <ActionButtonData>[];

  for (final (index, action) in indexed) {
    if (hiddenIndexes.contains(index)) {
      hidden.add(action);
    } else {
      visible.add(action);
    }
  }

  return (visible: visible, hidden: hidden);
}

class _ResponsiveActionBarState extends State<ResponsiveActionBar> {
  bool _menuOpenRequested = false;

  List<ActionButtonData> get _headerActions =>
      widget.menuHeaderActions ?? const <ActionButtonData>[];

  @override
  void didUpdateWidget(covariant ResponsiveActionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.openOverflowMenu) {
      _menuOpenRequested = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // בדיקה אם יש כפתורים בכלל
    final hasAlwaysInMenu =
        widget.alwaysInMenu != null && widget.alwaysInMenu!.isNotEmpty;

    if (widget.actions.isEmpty && !hasAlwaysInMenu && _headerActions.isEmpty) {
      return const SizedBox.shrink();
    }

    // קביעת מצב העבודה
    // New mode is only when originalOrder is NOT provided.
    // If originalOrder is provided, we keep old-mode priority behavior, and
    // allow alwaysInMenu to populate the overflow menu even on wide screens.
    final isNewMode =
        widget.alwaysInMenu != null && widget.originalOrder == null;

    if (isNewMode) {
      return _buildNewMode(context);
    } else {
      return _buildOldMode(context);
    }
  }

  /// מצב חדש: כפתורים נעלמים לפי רוחב אמיתי ועדיפות, תמיד יש תפריט עם כפתורים קבועים
  Widget _buildNewMode(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact =
            context.read<SettingsBloc?>()?.state.compactMenuMode ?? false;

        final standardButtonWidth = BarButton.toolbarWidth(isCompact);

        final partition = partitionToolbarActionsForWidth(
          actions: widget.actions,
          maxWidth: constraints.hasBoundedWidth
              ? constraints.maxWidth
              : double.infinity,
          standardButtonWidth: standardButtonWidth,
          overflowButtonWidth: standardButtonWidth,
          overflowAlreadyRequired:
              widget.alwaysInMenu!.isNotEmpty || _headerActions.isNotEmpty,
          maxVisibleButtons: widget.maxVisibleButtons,
        );

        final visibleActions = partition.visible;
        final hiddenActions = partition.hidden;

        final allHiddenActions = [...hiddenActions, ...widget.alwaysInMenu!];

        final visibleWidgets = visibleActions
            .map((action) => action.widget)
            .toList();

        final children = <Widget>[];

        if (allHiddenActions.isNotEmpty || _headerActions.isNotEmpty) {
          children.add(_buildOverflowButton(allHiddenActions));
        }

        children.addAll(visibleWidgets.reversed);

        return Row(
          mainAxisSize: MainAxisSize.min,
          textDirection: TextDirection.ltr,
          children: children,
        );
      },
    );
  }

  /// מצב ישן: כפתורים נעלמים לפי עדיפות, ותפריט רק אם צריך
  Widget _buildOldMode(BuildContext context) {
    final totalButtons = widget.originalOrder!.length;
    final configuredMaxVisible = widget.maxVisibleButtons ?? totalButtons;
    int effectiveMaxVisible = configuredMaxVisible;

    // אם צריך להסתיר רק כפתור אחד, אין טעם להציג תפריט שתופס מקום בעצמו —
    // אלא אם התפריט קיים ממילא בשביל שורת הניווט.
    if (totalButtons - configuredMaxVisible == 1 && _headerActions.isEmpty) {
      effectiveMaxVisible = totalButtons;
    }

    List<ActionButtonData> visibleActions;
    List<ActionButtonData> hiddenActions;

    // אם יש מקום לכל הכפתורים, נציג את כולם וללא תפריט "..."
    if (effectiveMaxVisible >= totalButtons) {
      visibleActions = List.from(widget.originalOrder!);
      hiddenActions = [];
    } else {
      final numToHide = totalButtons - effectiveMaxVisible;

      // ניקח את הכפתורים הפחות חשובים מרשימת העדיפויות
      final Set<ActionButtonData> actionsToHide = widget.actions.reversed
          .take(numToHide)
          .toSet();

      visibleActions = [];
      hiddenActions = [];

      // נחלק את הכפתורים (לפי הסדר המקורי!) לגלויים ונסתרים
      for (final action in widget.originalOrder!) {
        if (actionsToHide.contains(action)) {
          hiddenActions.add(action);
        } else {
          visibleActions.add(action);
        }
      }
    }

    final visibleWidgets = visibleActions
        .map((action) => action.widget)
        .toList();
    final List<Widget> children = [];

    final alwaysInMenu = widget.alwaysInMenu ?? const <ActionButtonData>[];
    final allHiddenActions = [...hiddenActions, ...alwaysInMenu];

    final showOverflow =
        allHiddenActions.isNotEmpty || _headerActions.isNotEmpty;

    if (widget.overflowOnRight) {
      // מסך הספרייה: תפריט בצד ימין. הסדר החזותי R->L דורש היפוך הרשימה.
      children.addAll(visibleWidgets.reversed);
      if (showOverflow) {
        children.add(_buildOverflowButton(allHiddenActions));
      }
    } else {
      // תפריט בצד שמאל
      if (showOverflow) {
        children.add(_buildOverflowButton(allHiddenActions));
      }
      children.addAll(visibleWidgets);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      textDirection: TextDirection.ltr,
      children: children,
    );
  }

  Widget _buildOverflowButton(List<ActionButtonData> hiddenActions) {
    // יצירת key ייחודי על סמך הכפתורים הנסתרים כדי למנוע בעיות context
    final uniqueKey =
        'overflow_${_headerActions.map((a) => a.tooltip).join('_')}'
        '_${hiddenActions.map((a) => a.tooltip).join('_')}';

    return Builder(
      key: ValueKey(uniqueKey),
      builder: (context) {
        final menuMetrics =
            Theme.of(context).extension<AppMenuMetrics>() ??
            AppMenuMetrics.create(compactMenus: false);
        final menuButton = AppPopupMenuButton<ActionButtonData>(
          key: widget.overflowButtonKey,
          iconData: FluentIcons.more_vertical_24_regular,
          tooltip: 'עוד פעולות',
          position: PopupMenuPosition.under,
          offset: widget.overflowMenuOffset,
          onSelected: (action) {
            action.onPressed?.call();
          },
          itemBuilder: (context) {
            final headerActions = _headerActions;
            final items = <PopupMenuEntry<ActionButtonData>>[];

            if (headerActions.isNotEmpty) {
              items.add(
                AppMenuRowEntry<ActionButtonData>(
                  height: _MenuIconActionRow.rowHeight,
                  child: _MenuIconActionRow(actions: headerActions),
                ),
              );
              if (hiddenActions.isNotEmpty) {
                items.add(PopupMenuDivider(height: menuMetrics.dividerHeight));
              }
            }

            items.addAll(
              hiddenActions.map((action) {
                // אם יש submenuItems, נבנה תת-תפריט
                if (action.submenuItems != null &&
                    action.submenuItems!.isNotEmpty) {
                  final subEntries = action.submenuItems!
                      .map(
                        (subAction) => buildAppPopupMenuItem<ActionButtonData>(
                          context,
                          AppMenuEntry<ActionButtonData>(
                            value: subAction,
                            label: subAction.tooltip ?? '',
                            icon: subAction.icon,
                            enabled: subAction.onPressed != null,
                          ),
                          menuMetrics,
                          null,
                          key: widget
                              .menuItemKeysByTooltip?[subAction.tooltip ?? ''],
                        ),
                      )
                      .toList();
                  return buildAppSubmenuPopupMenuItem<ActionButtonData>(
                    context: context,
                    metrics: menuMetrics,
                    label: action.tooltip ?? '',
                    icon: action.icon,
                    menuChildren: subEntries,
                    onSelected: (subAction) => subAction.onPressed?.call(),
                  );
                }

                // פריט רגיל ללא submenu
                return buildAppPopupMenuItem<ActionButtonData>(
                  context,
                  AppMenuEntry<ActionButtonData>(
                    value: action,
                    label: action.tooltip ?? '',
                    icon: action.icon,
                    enabled: action.onPressed != null,
                  ),
                  menuMetrics,
                  null,
                  key: widget.menuItemKeysByTooltip?[action.tooltip ?? ''],
                );
              }),
            );

            return items;
          },
        );

        if (widget.openOverflowMenu &&
            !_menuOpenRequested &&
            (hiddenActions.isNotEmpty || _headerActions.isNotEmpty)) {
          _menuOpenRequested = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !widget.openOverflowMenu) {
              return;
            }
            final state = widget.overflowButtonKey?.currentState as dynamic;
            state?.showMenu();
          });
        }

        return menuButton;
      },
    );
  }
}

/// שורת כפתורי ניווט בראש התפריט שאינה סוגרת אותו בלחיצה.
class _MenuIconActionRow extends StatelessWidget {
  final List<ActionButtonData> actions;

  const _MenuIconActionRow({required this.actions});

  static const double _buttonSize = 48;
  static const double _iconSize = 20;

  /// גובה השורה בתפריט — [AppMenuRowEntry] מדווח עליו, ו-showAnchoredAppMenu
  /// מסתמך על סכום הגבהים כדי לבחור כיוון פתיחה.
  static const double rowHeight = _buttonSize + 8;

  @override
  Widget build(BuildContext context) {
    assert(
      actions.every((action) => action.icon != null),
      'menuHeaderActions requires an icon for every action',
    );
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final action in actions)
            IconButton(
              onPressed: action.onPressed,
              tooltip: action.tooltip,
              icon: Icon(action.icon, size: _iconSize),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: _buttonSize,
                minHeight: _buttonSize,
              ),
              style: IconButton.styleFrom(
                // צבע פריט תפריט רגיל, לא הגוון המושתק של כפתור סרגל.
                foregroundColor: colorScheme.onSurface,
                shape: const CircleBorder(),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ],
      ),
    );
  }
}

/// נתוני כפתור פעולה
class ActionButtonData {
  /// הווידג'ט של הכפתור
  final Widget widget;

  /// האייקון (לשימוש בתפריט הנפתח)
  final IconData? icon;

  /// הטקסט להצגה בתפריט הנפתח
  final String? tooltip;

  /// הפעולה לביצוע כשלוחצים על הכפתור בתפריט
  final VoidCallback? onPressed;

  /// רשימת פריטי תת-תפריט (אם קיימת, זה יהיה submenu)
  final List<ActionButtonData>? submenuItems;

  /// הרוחב בפיקסלים שהפעולה תופסת כשהיא מוצגת בשורת הכלים.
  /// null = רוחב BarButton רגיל.
  final double? toolbarWidth;

  /// הזהות של הפעולה לצורך קביעת מיקומה בסדר ה-overflow.
  ///
  /// נדרש לכל ActionButtonData שמועבר לרשימת `actions` של
  /// ResponsiveActionBar במצב width-aware.
  /// אינו נדרש לפריטים שקיימים רק בתוך submenu/alwaysInMenu.
  final ToolbarActionId? actionId;

  const ActionButtonData({
    required this.widget,
    this.icon,
    this.tooltip,
    this.onPressed,
    this.submenuItems,
    this.toolbarWidth,
    this.actionId,
  });

  /// אופן הבנייה של כפתור פשוט.
  static const ActionButtonVisual defaultVisual = ActionButtonVisual.toolbar;

  /// Factory constructor לכפתור פשוט — מונע כפילות של icon/tooltip/onPressed
  /// בין הכפתור עצמו לנתוני התפריט.
  factory ActionButtonData.simple({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    required bool compact,
    bool selected = false,
    Key? key,
    ActionButtonVisual visual = defaultVisual,
    ToolbarActionId? actionId,
  }) {
    return ActionButtonData(
      widget: switch (visual) {
        ActionButtonVisual.toolbar => BarButton.icon(
          key: key,
          compact: compact,
          tooltip: tooltip,
          icon: icon,
          selected: selected,
          onPressed: onPressed,
        ),
        ActionButtonVisual.iconButton => IconButton(
          key: key,
          onPressed: onPressed,
          icon: Icon(icon),
          tooltip: tooltip,
        ),
      },
      icon: icon,
      tooltip: tooltip,
      onPressed: onPressed,
      toolbarWidth: switch (visual) {
        ActionButtonVisual.toolbar => BarButton.toolbarWidth(compact),
        ActionButtonVisual.iconButton => kMinInteractiveDimension,
      },
      actionId: actionId,
    );
  }

  /// לחצן מפוצל: [onPressed] היא הפעולה הראשית, ו-[menuItems] נפתחים מהחץ
  /// שלצידה. ב-overflow הפקד הופך לתת-תפריט שהפעולה הראשית היא פריטו הראשון.
  factory ActionButtonData.split({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    required List<ActionButtonData> menuItems,
    required bool compact,
    bool selected = false,
    String? menuTooltip,
    Key? key,
    ToolbarActionId? actionId,
  }) {
    return ActionButtonData(
      // הערך הוא אינדקס ולא ActionButtonData, כי השוואת ActionButtonData היא
      // לפי tooltip ושני פריטים בעלי אותו כיתוב היו מפעילים את אותה פעולה.
      widget: BarSplitButton<int>(
        key: key,
        icon: icon,
        tooltip: tooltip,
        compact: compact,
        selected: selected,
        onPressed: onPressed,
        menuTooltip: menuTooltip ?? 'אפשרויות נוספות',
        entries: [
          for (var i = 0; i < menuItems.length; i++)
            AppMenuEntry<int>(
              value: i,
              label: menuItems[i].tooltip ?? '',
              icon: menuItems[i].icon,
              enabled: menuItems[i].onPressed != null,
            ),
        ],
        onSelected: (index) => menuItems[index].onPressed?.call(),
      ),
      icon: icon,
      tooltip: tooltip,
      onPressed: onPressed,
      toolbarWidth: BarSplitButton.toolbarWidth(compact),
      actionId: actionId,
      submenuItems: [
        ActionButtonData(
          widget: const SizedBox.shrink(),
          icon: icon,
          tooltip: tooltip,
          onPressed: onPressed,
        ),
        ...menuItems,
      ],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActionButtonData &&
          runtimeType == other.runtimeType &&
          tooltip == other.tooltip;

  @override
  int get hashCode => tooltip.hashCode;
}

enum ActionButtonVisual { toolbar, iconButton }

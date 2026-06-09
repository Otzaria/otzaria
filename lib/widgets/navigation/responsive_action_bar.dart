import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';

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

  /// מספר מקסימלי של כפתורים להציג לפני מעבר לתפריט "..."
  final int maxVisibleButtons;

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
    required this.maxVisibleButtons,
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

class _ResponsiveActionBarState extends State<ResponsiveActionBar> {
  bool _menuOpenRequested = false;

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

    if (widget.actions.isEmpty && !hasAlwaysInMenu) {
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

  /// מצב חדש: כפתורים נעלמים בסדר ההצגה, תמיד יש תפריט עם כפתורים קבועים
  Widget _buildNewMode(BuildContext context) {
    final totalButtons = widget.actions.length;
    int effectiveMaxVisible = widget.maxVisibleButtons;

    // אם צריך להסתיר רק כפתור אחד, אין טעם להציג תפריט שתופס מקום בעצמו.
    // עדיף פשוט להציג את כל הכפתורים.
    // החרגה: כשיש alwaysInMenu, כפתור ה-overflow קיים ממילא, ולכן הצגת
    // כל הכפתורים תוסיף רוחב ותגרום לגלישה קלה ב-AppBar במסכים צרים.
    if (totalButtons - widget.maxVisibleButtons == 1 &&
        widget.alwaysInMenu!.isEmpty) {
      effectiveMaxVisible = totalButtons;
    }

    List<ActionButtonData> visibleActions;
    List<ActionButtonData> hiddenActions;

    // אם יש מקום לכל הכפתורים, נציג את כולם
    if (effectiveMaxVisible >= totalButtons) {
      visibleActions = List.from(widget.actions);
      hiddenActions = [];
    } else {
      // מסתירים כפתורים מהסוף לתחילה (הימני ביותר יעלם אחרון)
      final numToShow = effectiveMaxVisible;
      visibleActions = widget.actions.take(numToShow).toList();
      hiddenActions = widget.actions.skip(numToShow).toList();
    }

    // תמיד מוסיפים את הכפתורים שצריכים להיות בתפריט
    final allHiddenActions = [...hiddenActions, ...widget.alwaysInMenu!];

    final visibleWidgets =
        visibleActions.map((action) => action.widget).toList();
    final List<Widget> children = [];

    // מסך הספר: תפריט בצד שמאל, כפתורים מימין לשמאל (RTL)
    // תמיד מציגים כפתור "..." אם יש כפתורים בתפריט
    if (allHiddenActions.isNotEmpty) {
      children.add(_buildOverflowButton(allHiddenActions));
    }
    // הופכים את הסדר כך שהכפתור הראשון ברשימה (PDF) יהיה ימני ביותר
    children.addAll(visibleWidgets.reversed);

    return Row(
      mainAxisSize: MainAxisSize.min,
      textDirection: TextDirection.ltr,
      children: children,
    );
  }

  /// מצב ישן: כפתורים נעלמים לפי עדיxxxxxxפריט רק אם צריך
  Widget _buildOldMode(BuildContext context) {
    final totalButtons = widget.originalOrder!.length;
    int effectiveMaxVisible = widget.maxVisibleButtons;

    // אם צריך להסתיר רק כפתור אחד, אין טעם להציג תפריט שתופס מקום בעצמו.
    // עדיף פשוט להציג את כל הכפתורים.
    if (totalButtons - widget.maxVisibleButtons == 1) {
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
      final Set<ActionButtonData> actionsToHide =
          widget.actions.reversed.take(numToHide).toSet();

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

    final visibleWidgets =
        visibleActions.map((action) => action.widget).toList();
    final List<Widget> children = [];

    final alwaysInMenu = widget.alwaysInMenu ?? const <ActionButtonData>[];
    final allHiddenActions = [...hiddenActions, ...alwaysInMenu];

    if (widget.overflowOnRight) {
      // מסך הספרייה: תפריט בצד ימין. הסדר החזותי R->L דורש היפוך הרשימה.
      children.addAll(visibleWidgets.reversed);
      if (allHiddenActions.isNotEmpty) {
        children.add(_buildOverflowButton(allHiddenActions));
      }
    } else {
      // תפריט בצד שמאל
      if (allHiddenActions.isNotEmpty) {
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
        'overflow_${hiddenActions.map((a) => a.tooltip).join('_')}';

    return Builder(
      key: ValueKey(uniqueKey),
      builder: (context) {
        final menuMetrics = Theme.of(context).extension<AppMenuMetrics>() ??
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
            return hiddenActions.map((action) {
              // אם יש submenuItems, נבנה תת-תפריט
              if (action.submenuItems != null &&
                  action.submenuItems!.isNotEmpty) {
                final subEntries = action.submenuItems!
                    .map((subAction) => buildAppPopupMenuItem<ActionButtonData>(
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
                        ))
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
            }).toList();
          },
        );

        if (widget.openOverflowMenu &&
            !_menuOpenRequested &&
            hiddenActions.isNotEmpty) {
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

  const ActionButtonData({
    required this.widget,
    this.icon,
    this.tooltip,
    this.onPressed,
    this.submenuItems,
  });

  /// אופן הבנייה של כפתור פשוט.
  static const ActionButtonVisual defaultVisual = ActionButtonVisual.toolbar;

  /// Factory constructor לכפתור פשוט — מונע כפילות של icon/tooltip/onPressed
  /// בין הכפתור עצמו לנתוני התפריט.
  factory ActionButtonData.simple({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    required bool compact,
    bool selected = false,
    Key? key,
    ActionButtonVisual visual = defaultVisual,
  }) {
    return ActionButtonData(
      widget: switch (visual) {
        ActionButtonVisual.toolbar => ToolbarActionButton(
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

enum ActionButtonVisual {
  toolbar,
  iconButton,
}

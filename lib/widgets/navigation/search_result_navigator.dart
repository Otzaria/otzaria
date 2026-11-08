import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// ניווט בין תוצאות חיפוש: מונה, הקודמת והבאה, ועצירה בזמן סריקה. אותו
/// רכיב בשדה החיפוש, בסרגל התוצאות של חלונית החיפוש ובסרגלי ההתאמות.
///
/// [current] (מ-1) ו-[total] מציגים מונה "3/12"; null = בלי מונה. [label]
/// נכתב לפני המונה ("במפרשים: 3/12"). [counter] מחליף את המונה, למשל ברשימה
/// נפתחת. [onPrevious]/[onNext] null מציגים את הכפתור כמושבת.
/// [axis] אופקי — חצים לצדדים, לדפדוף בין עמודים.
class SearchResultNavigator extends StatelessWidget {
  static const double buttonSize = 32;
  static const double iconSize = 18;

  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final int? current;
  final int? total;
  final String? label;
  final Widget? counter;

  /// מוסיף כפתור עצירה לפני החצים.
  final VoidCallback? onStop;

  /// null = "תוצאה קודמת" / "תוצאה הבאה" בשפת הממשק.
  final String? previousTooltip;
  final String? nextTooltip;
  final Axis axis;

  const SearchResultNavigator({
    super.key,
    required this.onPrevious,
    required this.onNext,
    this.current,
    this.total,
    this.label,
    this.counter,
    this.onStop,
    this.previousTooltip,
    this.nextTooltip,
    this.axis = Axis.vertical,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final vertical = axis == Axis.vertical;
    final current = this.current;
    final total = this.total;
    final Widget? counterWidget =
        counter ??
        (current == null || total == null
            ? null
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  label == null ? '$current/$total' : '$label: $current/$total',
                  style: TextStyle(
                    fontSize: AppTokens.fontMD,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ));
    final previous = _NavButton(
      icon: vertical
          ? FluentIcons.chevron_up_24_regular
          : FluentIcons.chevron_left_24_regular,
      tooltip: previousTooltip ?? context.settingsText('תוצאה קודמת'),
      onPressed: onPrevious,
    );
    final next = _NavButton(
      icon: vertical
          ? FluentIcons.chevron_down_24_regular
          : FluentIcons.chevron_right_24_regular,
      tooltip: nextTooltip ?? context.settingsText('תוצאה הבאה'),
      onPressed: onNext,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onStop != null)
          _NavButton(
            icon: FluentIcons.stop_24_regular,
            tooltip: context.settingsText('עצור את החיפוש'),
            onPressed: onStop,
          ),
        // אופקי: המונה בין החצים, כמו בדפדוף עמודים.
        if (vertical) ...[
          ?counterWidget,
          previous,
          next,
        ] else ...[
          previous,
          ?counterWidget,
          next,
        ],
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _NavButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: SearchResultNavigator.buttonSize,
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, size: SearchResultNavigator.iconSize),
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        // בתוך שדה, ערכת הכפתורים של העיטור צובעת גם כפתור מושבת בצבע הרגיל.
        disabledColor: Theme.of(context).disabledColor,
      ),
    );
  }
}

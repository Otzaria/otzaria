import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// אזור המרכז האחיד לסרגלי הקריאה: [prev-major] [prev-minor] | כותרת | [next-minor] [next-major].
///
/// [title] — ווידג'ט הכותרת (Text, SelectionArea, LayoutBuilder וכו').
/// [afterTitle] — ווידג'ט אופציונלי אחרי הכותרת (למשל PageNumberDisplay ב-PDF).
class ReaderNavCenter extends StatelessWidget {
  final Widget title;
  final VoidCallback onPrevMajor;
  final VoidCallback onPrevMinor;
  final VoidCallback onNextMinor;
  final VoidCallback onNextMajor;
  final String prevMajorTooltip;
  final String prevMinorTooltip;
  final String nextMinorTooltip;
  final String nextMajorTooltip;
  final Widget? afterTitle;

  const ReaderNavCenter({
    super.key,
    required this.title,
    required this.onPrevMajor,
    required this.onPrevMinor,
    required this.onNextMinor,
    required this.onNextMajor,
    required this.prevMajorTooltip,
    required this.prevMinorTooltip,
    required this.nextMinorTooltip,
    required this.nextMajorTooltip,
    this.afterTitle,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = context.read<SettingsBloc>().state.compactMenuMode;
    const gap = 4.0;
    const minTitleWidth = 80.0;
    // כל BarButton.icon עטוף ב-Padding(horizontal:2) → 4px לרוחב הכולל.
    const buttonPadding = 4.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 340.0;

        // כשהמרחב צר, עוברים ל-compact (36px לכפתור במקום 40px).
        final forceCompact = available < 240 || isCompact;
        final buttonWidth = (forceCompact ? 36.0 : 40.0) + buttonPadding;

        // כפתורי major מוסתרים כשאין מקום ל-4 כפתורים + כותרת מינימלית.
        final showMajor =
            available >= 4 * buttonWidth + 2 * gap + minTitleWidth;
        final visibleButtons = showMajor ? 4 : 2;
        final navButtonsWidth = visibleButtons * buttonWidth + 2 * gap;

        final remainingForTitle = (available - navButtonsWidth).clamp(
          0.0,
          340.0,
        );
        // כשהמרחב קטן מ-minTitleWidth, מאפשרים לכותרת להתכווץ עוד יותר.
        final effectiveMinTitle = remainingForTitle.clamp(0.0, minTitleWidth);

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showMajor)
              BarButton.icon(
                tooltip: prevMajorTooltip,
                icon: FluentIcons.arrow_previous_24_filled,
                compact: forceCompact,
                onPressed: onPrevMajor,
              ),
            BarButton.icon(
              tooltip: prevMinorTooltip,
              icon: FluentIcons.chevron_left_24_regular,
              compact: forceCompact,
              onPressed: onPrevMinor,
            ),
            const SizedBox(width: gap),
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: effectiveMinTitle,
                  maxWidth: remainingForTitle,
                ),
                child: title,
              ),
            ),
            // afterTitle מתכווץ ויזואלית (scaleDown) כשהמרחב אוזל.
            if (afterTitle != null)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: remainingForTitle),
                child: FittedBox(fit: BoxFit.scaleDown, child: afterTitle!),
              ),
            const SizedBox(width: gap),
            BarButton.icon(
              tooltip: nextMinorTooltip,
              icon: FluentIcons.chevron_right_24_regular,
              compact: forceCompact,
              onPressed: onNextMinor,
            ),
            if (showMajor)
              BarButton.icon(
                tooltip: nextMajorTooltip,
                icon: FluentIcons.arrow_next_24_filled,
                compact: forceCompact,
                onPressed: onNextMajor,
              ),
          ],
        );
      },
    );
  }
}

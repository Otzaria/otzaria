import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_density.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// איפה [ReaderNavCenter] שם את החיצים בפריסה האחרונה: בסרגל, או (אין מקום
/// לארבעתם) בשורת האייקונים שבראש התפריט "עוד" של אותו סרגל.
///
/// נכתב בזמן הפריסה ונקרא כשהתפריט נפתח
/// (`ResponsiveActionBar.menuHeaderActionsVisible`). לכן זה שדה פשוט ולא
/// notifier: פריסה לא יכולה לתזמן בנייה מחדש של ווידג'ט אחר.
class ReaderNavPlacement {
  bool arrowsInBar = true;
}

/// אזור המרכז האחיד לסרגלי הקריאה: [prev-major] [prev-minor] | כותרת | [next-minor] [next-major].
///
/// [title] — ווידג'ט הכותרת (Text, SelectionArea, LayoutBuilder וכו').
/// [afterTitle] — ווידג'ט אופציונלי אחרי הכותרת (למשל PageNumberDisplay ב-PDF).
///
/// ארבעת החיצים קודמים לכותרת: כל עוד הם נכנסים ברוחב שהסרגל נותן למרכז,
/// הם בסרגל והכותרת מקבלת את מה שנשאר (גם כלום). רק כשאין מקום לארבעתם הם
/// יוצאים מהסרגל כולם, והכותרת מקבלת את כל המרכז. הסרגל מציג אותם אז בראש
/// התפריט "עוד" לפי [placement] (q12 Q8, סקירה שלישית של 4.11).
class ReaderNavCenter extends StatelessWidget {
  static const double minTitleWidth = 80.0;

  /// הרווח בין החיצים הפנימיים לכותרת, מכל צד.
  static const double navGap = 4.0;

  /// הרוחב שארבעת החיצים צריכים במרכז: ארבעה כפתורי סרגל ושני רווחים.
  static double navButtonsWidth({required bool compact}) =>
      4 * BarButton.toolbarWidth(compact) + 2 * navGap;

  /// במרכז צר מזה הכפתורים בגודל compact גם בצפיפות רגילה.
  static const double _forceCompactBelow = 240.0;

  /// האם ארבעת החיצים נכנסים במרכז ברוחב [centerWidth].
  static bool navFits(double centerWidth, {required bool isCompact}) =>
      centerWidth >=
      navButtonsWidth(
        compact: isCompact || centerWidth < _forceCompactBelow,
      );

  final Widget title;
  final VoidCallback onPrevMajor;
  final VoidCallback onPrevMinor;
  final VoidCallback onNextMinor;
  final VoidCallback onNextMajor;
  final String prevMajorTooltip;
  final String prevMinorTooltip;
  final String nextMinorTooltip;
  final String nextMajorTooltip;
  final IconData prevMajorIcon;
  final IconData nextMajorIcon;
  final Widget? afterTitle;

  /// מקבל בכל פריסה את ההחלטה אם החיצים בסרגל. הסרגל קורא אותו כדי להציג
  /// אותם בראש התפריט "עוד" כשהם לא כאן.
  final ReaderNavPlacement? placement;

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
    this.prevMajorIcon = FluentIcons.chevron_double_left_20_regular,
    this.nextMajorIcon = FluentIcons.chevron_double_right_20_regular,
    this.afterTitle,
    this.placement,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = AppDensity.of(context).isCompact;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 340.0;

        // כשהמרחב צר, עוברים ל-compact (36px לכפתור במקום 40px).
        final forceCompact = available < _forceCompactBelow || isCompact;

        // כל הארבעה או אף אחד: חץ בודד בלי בן זוגו, או שני חיצים בלי
        // מעבר הפרק, אינם ניווט שלם (#891 — אז הם לא היו בשום מקום).
        final showNav = navFits(available, isCompact: isCompact);
        placement?.arrowsInBar = showNav;
        final navButtonsWidth = showNav
            ? ReaderNavCenter.navButtonsWidth(compact: forceCompact)
            : 0.0;

        final remainingForTitle = (available - navButtonsWidth).clamp(
          0.0,
          340.0,
        );
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showNav) ...[
              BarButton.icon(
                tooltip: prevMajorTooltip,
                icon: prevMajorIcon,
                flipInRtl: true,
                compact: forceCompact,
                onPressed: onPrevMajor,
              ),
              BarButton.icon(
                tooltip: prevMinorTooltip,
                icon: FluentIcons.chevron_left_24_regular,
                compact: forceCompact,
                onPressed: onPrevMinor,
              ),
              const SizedBox(width: navGap),
            ],
            Flexible(
              child: ConstrainedBox(
                // רוחב קבוע, כדי שהחיצים לא יזוזו לפי אורך הכותרת.
                constraints: BoxConstraints.tightFor(width: remainingForTitle),
                child: title,
              ),
            ),
            // afterTitle מתכווץ ויזואלית (scaleDown) כשהמרחב אוזל.
            if (afterTitle != null)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: remainingForTitle),
                child: FittedBox(fit: BoxFit.scaleDown, child: afterTitle!),
              ),
            if (showNav) ...[
              const SizedBox(width: navGap),
              BarButton.icon(
                tooltip: nextMinorTooltip,
                icon: FluentIcons.chevron_right_24_regular,
                compact: forceCompact,
                onPressed: onNextMinor,
              ),
              BarButton.icon(
                tooltip: nextMajorTooltip,
                icon: nextMajorIcon,
                flipInRtl: true,
                compact: forceCompact,
                onPressed: onNextMajor,
              ),
            ],
          ],
        );
      },
    );
  }
}

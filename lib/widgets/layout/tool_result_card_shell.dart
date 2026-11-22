import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/layout/result_card_frame.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/misc/app_selection_area.dart';

/// כרטיס תוצאה במסכי כלים: [ResultCardFrame] עם טקסט שאפשר לבחור ולחיצה
/// אופציונלית.
class ToolResultCardShell extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  /// פעולות הכרטיס בתפריט ההקשר שלו (לחיצה ימנית, לחיצה ארוכה או Shift+F10),
  /// לפני "העתק". לפעולות שמופיעות בכרטיס רק בריחוף עכבר.
  final List<AppContextMenuEntry> Function(BuildContext, Offset)? menuEntries;

  const ToolResultCardShell({
    super.key,
    required this.child,
    this.onTap,
    this.menuEntries,
  });

  @override
  Widget build(BuildContext context) {
    // notifier לכל כרטיס מגביל את עלות הסרת מאזיני הטיקרים בפירוק הרשימה.
    return TickerMode(
      enabled: true,
      child: ResultCardFrame(
        // The tap target sits inside the selection area: a tap on the text
        // would otherwise go to the selection and never reach the card.
        child: AppSelectionArea(
          extraMenuEntries: menuEntries,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppTokens.borderRadiusAll,
            child: Padding(padding: AppTokens.cardPadding, child: child),
          ),
        ),
      ),
    );
  }
}

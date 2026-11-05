import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/layout/result_card_frame.dart';
import 'package:otzaria/widgets/misc/app_selection_area.dart';

/// כרטיס תוצאה במסכי כלים: [ResultCardFrame] עם טקסט שאפשר לבחור ולחיצה
/// אופציונלית.
class ToolResultCardShell extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const ToolResultCardShell({super.key, required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ResultCardFrame(
      // The tap target sits inside the selection area: a tap on the text
      // would otherwise go to the selection and never reach the card.
      child: AppSelectionArea(
        child: InkWell(
          onTap: onTap,
          borderRadius: AppTokens.borderRadiusAll,
          focusColor: Colors.transparent,
          child: Padding(padding: AppTokens.cardPadding, child: child),
        ),
      ),
    );
  }
}

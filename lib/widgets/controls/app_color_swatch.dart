import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_tokens.dart';

/// עיגול בחירת צבע: הרכיב היחיד לבוררי הצבע (צבע הבסיס בהגדרות, צבע אירוע
/// בלוח השנה).
///
/// הבחירה אינה מסומנת בצבע בלבד: על העיגול הנבחר מצויר סימן וי, והמסגרת
/// עבה. עיגול שלא נבחר נשאר עם מסגרת דקה, כדי שעיגול לבן על דיאלוג בהיר (או
/// כהה על כהה) לא ייעלם. הקורא מקבל שם ומצב נבחר (`Semantics.selected`).
/// לחיץ בעכבר, במגע ובמקלדת (Enter ורווח).
///
/// ה-[color] הוא צבע תוכן, לא צבע ממשק, ולכן סימן הוי מחושב מבהירות העיגול
/// ([AppSeedColors.checkColorOn]). [color] null הוא "ללא צבע": עיגול ריק עם
/// קו אופקי, שגם הוא מקבל וי כשהוא נבחר.
class AppColorSwatch extends StatefulWidget {
  const AppColorSwatch({
    super.key,
    required this.color,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  /// צבע העיגול; null = "ללא צבע".
  final Color? color;

  final bool selected;

  /// שם הצבע: tooltip ותווית לקורא המסך.
  final String label;

  final VoidCallback onTap;

  /// קוטר העיגול הנראה. סביבו ריפוד, כך ששטח הלחיצה הוא [hitSize].
  static const double diameter = 40;

  /// שטח הלחיצה של עיגול אחד (עיגול וריפוד).
  static const double hitSize = 48;

  @override
  State<AppColorSwatch> createState() => _AppColorSwatchState();
}

class _AppColorSwatchState extends State<AppColorSwatch> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fill = widget.color ?? cs.surfaceContainerHighest;
    // טבעת הפוקוס בצבע ההדגשה, כדי שלא תתבלבל עם טבעת הבחירה.
    final border = _focused
        ? Border.all(color: cs.primary, width: AppTokens.borderThick)
        : widget.selected
        ? Border.all(color: cs.onSurface, width: AppTokens.borderThick)
        : Border.all(color: cs.outline);
    const padding = (AppColorSwatch.hitSize - AppColorSwatch.diameter) / 2;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: Tooltip(
        message: widget.label,
        child: FocusableActionDetector(
          mouseCursor: SystemMouseCursors.click,
          onShowFocusHighlight: (v) => setState(() => _focused = v),
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onTap();
                return null;
              },
            ),
          },
          child: GestureDetector(
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(padding),
              child: Container(
                width: AppColorSwatch.diameter,
                height: AppColorSwatch.diameter,
                decoration: BoxDecoration(
                  color: fill,
                  shape: BoxShape.circle,
                  border: border,
                ),
                child: widget.selected
                    ? Icon(
                        FluentIcons.checkmark_24_regular,
                        color: AppSeedColors.checkColorOn(fill),
                        size: AppTokens.iconMD,
                      )
                    : widget.color == null
                    ? Icon(
                        FluentIcons.line_horizontal_1_24_regular,
                        size: AppTokens.iconSM,
                        color: cs.onSurfaceVariant,
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

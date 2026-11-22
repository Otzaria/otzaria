import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';

/// קישור בתוך טקסט: טקסט בצבע `primary` עם קו תחתון, שלחיצה עליו מפעילה
/// [onTap]. הריפוד, הפינות וסימון המקלדת זהים בכל מקום, ולכן מי שמנווט עם Tab
/// רואה את אותו סימון על כל קישור.
///
/// בלי [onTap] זה טקסט רגיל בסגנון [style] (למשל נתיב שאי אפשר לפתוח), בלי
/// קו תחתון ובלי אזור לחיצה.
///
/// קישור באמצע משפט ב־`Text.rich` נבנה כ־`TextSpan` עם [styleOf] ו־`recognizer`:
/// `TextSpan` אינו מקבל פוקוס מקלדת, ולכן לשם כך נשאר הסגנון המשותף בלבד.
class AppInlineLink extends StatelessWidget {
  const AppInlineLink({
    super.key,
    required this.text,
    required this.onTap,
    this.tooltip,
    this.style,
    this.textDirection,
    this.maxLines,
    this.overflow,
  });

  final String text;

  /// null = טקסט רגיל, לא קישור.
  final VoidCallback? onTap;

  /// הסבר קצר למה שהלחיצה עושה. בלעדיו אין tooltip.
  final String? tooltip;

  /// הסגנון הבסיסי (גודל, משקל). הצבע והקו התחתון של קישור נקבעים כאן.
  final TextStyle? style;

  /// כיוון הטקסט כשהוא שונה מכיוון הממשק, למשל נתיב או כתובת.
  final TextDirection? textDirection;
  final int? maxLines;
  final TextOverflow? overflow;

  /// סגנון קישור על גבי [base]: `primary` וקו תחתון באותו צבע. גם ל־`TextSpan`
  /// בתוך משפט.
  static TextStyle styleOf(BuildContext context, [TextStyle? base]) {
    final primary = Theme.of(context).colorScheme.primary;
    return (base ?? const TextStyle()).copyWith(
      color: primary,
      decoration: TextDecoration.underline,
      decorationColor: primary,
    );
  }

  @override
  Widget build(BuildContext context) {
    final onTap = this.onTap;
    if (onTap == null) {
      return Text(
        text,
        style: style,
        textDirection: textDirection,
        maxLines: maxLines,
        overflow: overflow,
      );
    }
    Widget link = InkWell(
      onTap: onTap,
      borderRadius: AppTokens.borderRadiusAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.space2XS),
        child: Text(
          text,
          style: styleOf(context, style),
          textDirection: textDirection,
          maxLines: maxLines,
          overflow: overflow,
        ),
      ),
    );
    final tooltip = this.tooltip;
    if (tooltip != null) link = Tooltip(message: tooltip, child: link);
    return link;
  }
}

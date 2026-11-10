import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// מצב טעינה: ספינר ממורכז, אופציונלית עם הודעה מתחתיו ([message]) ואייקון
/// מערכת במרכז הטבעת ([icon]).
/// בתוך שורה, ליד טקסט או בכפתור: [LoadingIndicator.inline] (16, עובי 2).
/// לתוכן שעוד לא נטען: [SkeletonLines].
class LoadingIndicator extends StatelessWidget {
  final double? strokeWidth;
  final double? size;
  final Color? color;

  /// התקדמות מדודה (0..1); `null` = ספינר מסתובב.
  final double? value;

  /// הודעה מתחת לספינר, למשל "טוען מפרשים...".
  final String? message;

  /// אייקון במרכז הטבעת, למשל ספרים בטעינת ספרייה. לא פועל עם [size].
  final IconData? icon;

  const LoadingIndicator({
    super.key,
    this.strokeWidth,
    this.size,
    this.color,
    this.message,
    this.icon,
    this.value,
  });

  /// ספינר קטן בתוך שורה: 16 על 16, עובי 2, לא ממורכז. עם [value] הוא טבעת
  /// התקדמות.
  const LoadingIndicator.inline({super.key, this.color, this.value})
    : size = inlineSize,
      strokeWidth = inlineStrokeWidth,
      message = null,
      icon = null;

  static const double inlineSize = AppTokens.iconSM;
  static const double inlineStrokeWidth = 2;

  @override
  Widget build(BuildContext context) {
    final indicator = CircularProgressIndicator(
      value: value,
      strokeWidth: strokeWidth ?? 4.0,
      valueColor: color != null ? AlwaysStoppedAnimation<Color>(color!) : null,
    );

    if (size != null) {
      return SizedBox(
        width: size,
        height: size,
        child: indicator,
      );
    }

    final theme = Theme.of(context);
    final ring = icon == null
        ? indicator
        : SizedBox.square(
            dimension: AppTokens.iconXL,
            child: Stack(
              fit: StackFit.expand,
              children: [
                indicator,
                Center(
                  child: Icon(
                    icon,
                    size: AppTokens.iconLG,
                    color: color ?? theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          );

    if (message == null) return Center(child: ring);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMD),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ring,
            const SizedBox(height: AppTokens.spaceMD),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// שורות שלד לתוכן שנטען. [widths] הם חלקים מרוחב המקום שהשורות קיבלו
/// (לא מרוחב החלון), מיושרים לתחילת השורה.
class SkeletonLines extends StatelessWidget {
  final List<double> widths;
  final double lineHeight;

  /// הרווח מתחת לכל שורה, גם האחרונה.
  final double spacing;

  const SkeletonLines({
    super.key,
    required this.widths,
    this.lineHeight = 16,
    this.spacing = AppTokens.spaceSM,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final width in widths)
          Padding(
            padding: EdgeInsets.only(bottom: spacing),
            child: FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: width,
              child: Container(
                height: lineHeight,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: AppTokens.borderRadiusAll,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

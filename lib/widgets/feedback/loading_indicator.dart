import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// מצב טעינה: ספינר ממורכז, אופציונלית עם הודעה מתחתיו ([message]).
/// בתוך שורה, ליד טקסט או בכפתור: [LoadingIndicator.inline] (16, עובי 2).
/// לתוכן שעוד לא נטען: [SkeletonLines].
class LoadingIndicator extends StatelessWidget {
  final double? strokeWidth;
  final double? size;
  final Color? color;

  /// הודעה מתחת לספינר, למשל "טוען מפרשים...".
  final String? message;

  const LoadingIndicator({
    super.key,
    this.strokeWidth,
    this.size,
    this.color,
    this.message,
  });

  /// ספינר קטן בתוך שורה: 16 על 16, עובי 2, לא ממורכז.
  const LoadingIndicator.inline({super.key, this.color})
    : size = inlineSize,
      strokeWidth = inlineStrokeWidth,
      message = null;

  static const double inlineSize = AppTokens.iconSM;
  static const double inlineStrokeWidth = 2;

  @override
  Widget build(BuildContext context) {
    final indicator = CircularProgressIndicator(
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

    if (message == null) return Center(child: indicator);

    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMD),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            indicator,
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

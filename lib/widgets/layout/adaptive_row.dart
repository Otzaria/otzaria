import 'package:flutter/material.dart';
import 'package:otzaria/theme/layout_tokens.dart';

/// מציג את [children] בשורה אחת על מסכים רחבים — כל פריט עטוף ב-[Expanded]
/// עם רווח [spacing] ביניהם — ובטור על מסכים צרים מ-[breakpoint].
/// כך מגדירים את התוכן פעם אחת במקום לשכפלו לשתי פריסות.
class AdaptiveRow extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final double breakpoint;

  /// עוטף את השורה הרחבה ב-[IntrinsicHeight] כדי שכל הפריטים יהיו בגובה זהה.
  final bool equalHeight;
  final CrossAxisAlignment wideCrossAxisAlignment;

  const AdaptiveRow({
    super.key,
    required this.children,
    this.spacing = LayoutPadding.compact,
    this.breakpoint = LayoutBreakpoints.compact,
    this.equalHeight = false,
    this.wideCrossAxisAlignment = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _withGaps((c) => c, SizedBox(height: spacing)),
          );
        }
        final row = Row(
          // ב-equalHeight חובה stretch כדי שהילדים יימתחו לגובה ש-IntrinsicHeight קבע.
          crossAxisAlignment: equalHeight
              ? CrossAxisAlignment.stretch
              : wideCrossAxisAlignment,
          children: _withGaps(
            (c) => Expanded(child: c),
            SizedBox(width: spacing),
          ),
        );
        return equalHeight ? IntrinsicHeight(child: row) : row;
      },
    );
  }

  List<Widget> _withGaps(Widget Function(Widget) wrap, Widget gap) {
    final result = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) result.add(gap);
      result.add(wrap(children[i]));
    }
    return result;
  }
}

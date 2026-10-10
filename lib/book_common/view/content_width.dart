import 'package:flutter/widgets.dart';

/// Limits a commentary list to [maxWidth]. Aligned to the top and not
/// centered, so a shrink-wrapped list does not float to the middle.
Widget constrainToContentWidth(Widget list, double? maxWidth) {
  if (maxWidth == null || maxWidth <= 0) return list;
  return Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: list,
    ),
  );
}

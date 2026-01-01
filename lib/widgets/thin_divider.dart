import 'package:flutter/material.dart';

/// A reusable divider widget that creates a line with a consistent height,
/// color, and margin to match other dividers in the UI.
class ThinDivider extends StatelessWidget {
  final Color? color;
  final double margin;

  const ThinDivider({
    super.key,
    this.color,
    this.margin = 8.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      color: color ?? Colors.grey.shade300,
      margin: EdgeInsets.symmetric(horizontal: margin),
    );
  }
}

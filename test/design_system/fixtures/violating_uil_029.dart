import 'package:flutter/material.dart';

class AppTokens {
  static const double fontLG = 16;
}

const Widget a = Icon(IconData(0xe000), size: 18); // LINT
const Widget b = Icon(IconData(0xe000), size: AppTokens.fontLG); // LINT
Widget c(VoidCallback f) => IconButton(
  tooltip: 'x',
  iconSize: 20, // LINT
  onPressed: f,
  icon: const Icon(IconData(0xe000)),
);
const IconThemeData theme = IconThemeData(size: 18); // LINT
Widget merged(Widget child, Color color) => IconTheme.merge(
  data: IconThemeData(color: color, size: 20), // LINT
  child: child,
);

import 'package:flutter/material.dart';

Color a(ColorScheme cs) => cs.surfaceContainer;
Brightness icons(bool isDark) => isDark ? Brightness.light : Brightness.dark;
String file(bool isDark) => isDark ? 'dark.png' : 'light.png';
Color seed(bool isDark, Color darkSeed, Color lightSeed) =>
    isDark ? darkSeed : lightSeed;
Color selected(bool isSelected, ColorScheme cs) =>
    isSelected ? cs.primary : cs.surface;

class TilePainter extends CustomPainter {
  TilePainter(this.isDark);

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = isDark ? Colors.white : Colors.black;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(TilePainter old) => old.isDark != isDark;
}

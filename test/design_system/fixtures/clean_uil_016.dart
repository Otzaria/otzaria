import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;

class AppSurfaces {
  static Color hoverRow(ColorScheme cs) => cs.onSurface;
}

Color row(ColorScheme cs) => AppSurfaces.hoverRow(cs);
Color opaque(Color c) => c.withValues(red: 1);
BoxShadow shadow(ColorScheme cs) =>
    BoxShadow(color: cs.shadow.withValues(alpha: 0.2), blurRadius: 4);
pw.Widget paper(pdf.PdfColor c) =>
    pw.Container(color: pdf.PdfColor(c.red, c.green, c.blue).flatten());

class Shade extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) => canvas.drawRect(
    Offset.zero & size,
    Paint()..color = const Color(0xFF000000).withValues(alpha: 0.1),
  );

  @override
  bool shouldRepaint(Shade oldDelegate) => false;
}

import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;

class AppTokens {
  static const double elevation1 = 1;
}

Widget flat() => const Material(elevation: 0);
Widget bar() => const Material(elevation: AppTokens.elevation1);
Widget fromPlugin(Map<String, Object?> args) =>
    Material(elevation: (args['elevation'] as num?)?.toDouble() ?? 0);
double geo(Map<String, Object?> city) => (city['elevation'] as num).toDouble();

class Shade extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) =>
      canvas.drawShadow(Path(), const Color(0x00000000), 2, false);

  Widget sample() => const Material(elevation: 2);

  BoxShadow paper() => const BoxShadow(blurRadius: 2);

  @override
  bool shouldRepaint(Shade oldDelegate) => false;
}

class AppShadows {
  static List<BoxShadow> floating(ColorScheme cs) => const [];
}

BoxDecoration floating(ColorScheme cs) =>
    BoxDecoration(boxShadow: AppShadows.floating(cs));
const pw.BoxShadow page = pw.BoxShadow(blurRadius: 4);

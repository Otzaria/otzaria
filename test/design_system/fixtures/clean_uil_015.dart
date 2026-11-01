import 'package:flutter/material.dart';

const Color clear = Colors.transparent;

Color fromSettings(int value) => Color(value);

BoxShadow shadow() => const BoxShadow(color: Colors.black26, blurRadius: 4);

class Painter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF000000),
    );
  }

  @override
  bool shouldRepaint(Painter oldDelegate) => false;
}

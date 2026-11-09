import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;

BorderRadius computed(double radius) => BorderRadius.circular(radius);
BorderRadiusDirectional computedStart(double radius) =>
    BorderRadiusDirectional.circular(radius);

pw.BorderRadius paper() => pw.BorderRadius.circular(4);

class Painter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3)),
      Paint(),
    );
  }

  @override
  bool shouldRepaint(Painter oldDelegate) => false;
}

Widget iconButton(VoidCallback f) => IconButton(
  tooltip: 'x',
  onPressed: f,
  style: IconButton.styleFrom(shape: const CircleBorder()),
  icon: const Icon(IconData(0xe000)),
);

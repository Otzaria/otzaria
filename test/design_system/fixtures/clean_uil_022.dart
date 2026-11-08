import 'package:flutter/material.dart';

const double _iconOnlyBelow = 560;

bool iconOnly(BoxConstraints constraints) =>
    constraints.maxWidth < _iconOnlyBelow;

// A component size, not a layout breakpoint.
bool tiny(Size size) => size.width < 40;

bool empty(Size size) => size.width <= 0;

int count(List<int> items) => items.length > 100 ? 100 : items.length;

class Painter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width > 300) canvas.drawLine(Offset.zero, Offset.zero, Paint());
  }

  @override
  bool shouldRepaint(Painter oldDelegate) => false;
}

// A component or data width in a local, not the layout width.
bool tab(double tabWidth) => tabWidth >= 100;

bool localNamed(BoxConstraints constraints) {
  final width = constraints.maxWidth;
  return width < _iconOnlyBelow;
}

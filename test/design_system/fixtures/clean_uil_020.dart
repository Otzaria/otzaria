import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;

class AppTokens {
  static const double spaceSM = 8;
}

const EdgeInsets a = EdgeInsets.all(12);
const EdgeInsets b = EdgeInsets.symmetric(horizontal: 24, vertical: 2);
const EdgeInsets c = EdgeInsets.all(AppTokens.spaceSM);
EdgeInsets d(double inset) => EdgeInsets.all(inset * 1.5);
const Widget gap = SizedBox(height: 16);
const Widget box = SizedBox(width: 36, height: 36);
const Widget fill = SizedBox(width: double.infinity);
Widget sized(Widget child) => SizedBox(width: 6, child: child);
const pw.EdgeInsets paper = pw.EdgeInsets.all(5);

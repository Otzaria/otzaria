import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;

const EdgeInsets a = EdgeInsets.only(top: 8, bottom: 4);
const EdgeInsets b = EdgeInsets.fromLTRB(16, 8, 16, 4);
const EdgeInsets c = EdgeInsets.only(left: 12, right: 12);
const EdgeInsetsGeometry d = EdgeInsetsDirectional.only(start: 8);
const AlignmentGeometry e = AlignmentDirectional.centerStart;
const Alignment f = Alignment.center;
Widget g(Widget child) => Positioned(left: 0, right: 0, child: child);
Widget h(Widget child) => Positioned.directional(
  textDirection: TextDirection.rtl,
  start: 4,
  child: child,
);
const pw.EdgeInsets paper = pw.EdgeInsets.only(left: 20);
const Alignment i = Alignment(0, -1);
Alignment j(double x) => Alignment(x, 0);
const BorderRadius k = BorderRadius.only(
  topLeft: Radius.circular(8),
  topRight: Radius.circular(8),
);
const BorderRadius l = BorderRadius.horizontal(
  left: Radius.circular(8),
  right: Radius.circular(8),
);
const BorderRadius m = BorderRadius.vertical(top: Radius.circular(8));
const BorderRadiusGeometry n = BorderRadiusDirectional.only(
  topStart: Radius.circular(8),
);

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

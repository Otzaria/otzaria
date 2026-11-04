import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Widget a(Widget child) => Scrollbar(child: child); // LINT
Widget b(ScrollController c, Widget child) =>
    RawScrollbar(controller: c, child: child); // LINT
Widget d(Widget child) => CupertinoScrollbar(child: child); // LINT
Widget e(Widget child) =>
    Scrollbar(thumbVisibility: true, child: child); // LINT

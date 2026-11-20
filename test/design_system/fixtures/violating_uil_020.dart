import 'package:flutter/material.dart';

class AppTokens {
  static const double spaceSM = 8;
  static const double spaceMD = 16;
  static const double iconMD = 20;
}

const EdgeInsets a = EdgeInsets.all(6); // LINT
const EdgeInsets b = EdgeInsets.symmetric(horizontal: 16, vertical: 10); // LINT
const EdgeInsetsGeometry c = EdgeInsetsDirectional.only(start: 14); // LINT
const EdgeInsets d = EdgeInsets.fromLTRB(8, 8, 8, 5.5); // LINT
const Widget gap = SizedBox(height: 6); // LINT
Widget gapNew() => SizedBox(width: 10); // LINT
const Widget square = SizedBox.square(dimension: 6); // LINT
Widget wrap(List<Widget> items) => Wrap(
  spacing: 6, // LINT
  runSpacing: 10, // LINT
  children: items,
);
Widget row(List<Widget> items) => Row(
  spacing: 6, // LINT
  children: items,
);
Widget column(List<Widget> items) => Column(
  spacing: 3.5, // LINT
  children: items,
);
Widget grid(List<Widget> items) => GridView.count(
  crossAxisCount: 2,
  mainAxisSpacing: 10, // LINT
  children: items,
);
const delegate = SliverGridDelegateWithFixedCrossAxisCount(
  crossAxisCount: 2,
  crossAxisSpacing: 6, // LINT
);
EdgeInsets computedA() => EdgeInsets.all(AppTokens.spaceSM + 1); // LINT
double computedB() => AppTokens.spaceMD - 4; // LINT
Widget computedC() => SizedBox(width: 2 + AppTokens.spaceSM); // LINT
double computedD() => AppTokens.iconMD + 2; // LINT

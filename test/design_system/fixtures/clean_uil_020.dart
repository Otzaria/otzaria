import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;

class AppTokens {
  static const double spaceSM = 8;
  static const double fontMD = 14;
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
const Widget squareGap = SizedBox.square(dimension: 8);
const Widget spinner = SizedBox.square(
  dimension: 18,
  child: CircularProgressIndicator(strokeWidth: 2),
);
const Widget avatar = SizedBox.square(dimension: 40);

class SkeletonLines extends StatelessWidget {
  const SkeletonLines({super.key, this.spacing = 6});
  final double spacing;

  @override
  Widget build(BuildContext context) => const SizedBox();
}

Widget wrapOnScale(List<Widget> items) =>
    Wrap(spacing: 8, runSpacing: 12, children: items);
Widget rowZero(List<Widget> items) => Row(spacing: 0, children: items);
Widget columnToken(List<Widget> items, double gap) =>
    Column(spacing: gap, children: items);
Widget geometry() => const SkeletonLines(spacing: 6);
Widget gridOnScale(List<Widget> items) =>
    GridView.count(crossAxisCount: 2, mainAxisSpacing: 16, children: items);
EdgeInsets tokenScaled() => const EdgeInsets.all(AppTokens.spaceSM * 2);
double tokenPlusVariable(double extra) => AppTokens.spaceSM + extra;
double fontOffset() => AppTokens.fontMD + 1;
double literalOnly() => 8 + 1;

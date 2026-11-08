import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;

TextStyle? body(BuildContext context) => Theme.of(context).textTheme.bodySmall;

TextStyle scaled(double base) => TextStyle(fontSize: base * 1.2);

pw.TextStyle paper() => const pw.TextStyle(fontSize: 10);

Widget icon(IconData data) => Icon(data, size: 16);

import 'package:flutter/material.dart';

Widget inherit(String text) => Text(text);

Widget ltr(String path) => Text(path, textDirection: TextDirection.ltr);

Widget box(Widget child) =>
    Directionality(textDirection: TextDirection.rtl, child: child);

TextPainter measure(String text) => TextPainter(
  text: TextSpan(text: text),
  textDirection: TextDirection.rtl,
);

Widget fromContext(BuildContext context, String text) =>
    Text(text, textDirection: Directionality.of(context));

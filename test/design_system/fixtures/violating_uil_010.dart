import 'package:flutter/material.dart';

Widget a(String text) => Text(text, textDirection: TextDirection.rtl); // LINT
Widget b() => const Text('שלום', textDirection: TextDirection.rtl); // LINT
Widget c(InlineSpan span) => Text.rich(
  span,
  textDirection: TextDirection.rtl, // LINT
);
Widget d(String text) =>
    SelectableText(text, textDirection: (TextDirection.rtl)); // LINT

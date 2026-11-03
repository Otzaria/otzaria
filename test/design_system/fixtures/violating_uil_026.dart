import 'package:flutter/material.dart';

Widget a(Widget child) => MediaQuery.withNoTextScaling(child: child); // LINT
Widget b(InlineSpan span) => RichText(text: span); // LINT
Widget c(String text) => Text(text, textScaler: TextScaler.noScaling); // LINT
TextPainter d(InlineSpan span) => TextPainter(
  text: span,
  textDirection: TextDirection.rtl,
  textScaler: TextScaler.noScaling, // LINT
);

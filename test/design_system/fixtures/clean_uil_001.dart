import 'package:flutter/material.dart';

Widget body(String text) => Text(text);

Future<void> open(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => body('Dialog'));

DialogThemeData dialogTheme(ColorScheme cs) =>
    DialogThemeData(backgroundColor: cs.surfaceContainerHigh);

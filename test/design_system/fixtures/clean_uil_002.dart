import 'package:flutter/material.dart';

class ActionButton extends StatelessWidget {
  const ActionButton({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(text);
}

Widget button() => const ActionButton(text: 'ביטול');

// styleFrom אינו בנאי: סגנון לערכת הנושא או לרכיב המשותף.
ButtonStyle style() => TextButton.styleFrom(padding: EdgeInsets.zero);
ButtonStyle filledStyle() => FilledButton.styleFrom(elevation: 0);

TextButtonThemeData theme(ButtonStyle s) => TextButtonThemeData(style: s);

import 'package:flutter/material.dart';

// ui-lint: allow UIL-033 — מתג בתוך שורת הדפסה שעוד לא עברה ל־AppTogglePill
Widget a(bool v, ValueChanged<bool> f) => CustomSwitch(value: v, onChanged: f);

class CustomSwitch extends StatelessWidget {
  const CustomSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) =>
      Switch(value: value, onChanged: onChanged);
}

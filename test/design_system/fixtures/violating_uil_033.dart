import 'package:flutter/material.dart';

Widget a(bool v, ValueChanged<bool> f) =>
    CustomSwitch(value: v, onChanged: f); // LINT
Widget b(bool v) => const CustomSwitch(value: true, onChanged: null); // LINT

class CustomSwitch extends StatelessWidget {
  const CustomSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) =>
      Switch(value: value, onChanged: onChanged);
}

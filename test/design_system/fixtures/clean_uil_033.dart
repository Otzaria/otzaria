import 'package:flutter/material.dart';

// CustomSwitch בהערה אינו שימוש.
Widget a(bool v, ValueChanged<bool> f) => Switch(value: v, onChanged: f);
Widget b(bool v, ValueChanged<bool> f) =>
    CustomSwitchTile(value: v, onChanged: f);

class CustomSwitchTile extends StatelessWidget {
  const CustomSwitchTile({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) =>
      Switch(value: value, onChanged: onChanged);
}

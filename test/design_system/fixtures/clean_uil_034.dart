import 'package:flutter/material.dart';

class AppIconButton extends StatelessWidget {
  const AppIconButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => const SizedBox();
}

Widget shared(VoidCallback onTap) => AppIconButton(onPressed: onTap);

IconButtonThemeData theme(ButtonStyle style) =>
    IconButtonThemeData(style: style);

ButtonStyle style() => IconButton.styleFrom(padding: EdgeInsets.zero);

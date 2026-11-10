import 'package:flutter/material.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

class CommentatorsFilterButton extends StatelessWidget {
  final VoidCallback onPressed;

  const CommentatorsFilterButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(OtzariaIcons.apps_list_24_regular),
      tooltip: 'בחירת מפרשים',
      onPressed: onPressed,
    );
  }
}

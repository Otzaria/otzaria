import 'package:flutter/material.dart';

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

Widget card(Widget child) => AppCard(child: child);

CardThemeData theme(ColorScheme cs) => CardThemeData(color: cs.surface);

import 'package:flutter/material.dart';

class AppScrollbar extends StatelessWidget {
  const AppScrollbar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

Widget list(Widget child) => AppScrollbar(child: child);

ScrollbarThemeData theme() => const ScrollbarThemeData(crossAxisMargin: 2);

Widget themed(BuildContext context, Widget child) => ScrollbarTheme(
  data: ScrollbarTheme.of(context).copyWith(crossAxisMargin: 6),
  child: child,
);

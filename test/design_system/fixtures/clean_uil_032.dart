import 'package:flutter/material.dart';

// SelectableText בהערה אינו שימוש.
Widget a(Widget child) => SelectionArea(
  contextMenuBuilder: (context, state) => const SizedBox.shrink(),
  child: child,
);
Widget b(Widget child) => AppSelectionArea(child: child);
const Widget c = Text('א');

class AppSelectionArea extends StatelessWidget {
  const AppSelectionArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

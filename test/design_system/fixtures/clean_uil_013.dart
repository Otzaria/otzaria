import 'package:flutter/material.dart';

class LoadingIndicator extends StatelessWidget {
  const LoadingIndicator({super.key});

  const LoadingIndicator.inline({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox();
}

Widget page() => const LoadingIndicator();
Widget row() => const LoadingIndicator.inline();
Widget bar() => const LinearProgressIndicator();

ProgressIndicatorThemeData theme(ColorScheme cs) =>
    ProgressIndicatorThemeData(color: cs.primary);

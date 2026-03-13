import 'package:flutter/material.dart';

class CountFutureBuilder extends StatelessWidget {
  final Future<int> future;
  final Widget Function(BuildContext context, int count) builder;
  final Widget? emptyBuilder;

  const CountFutureBuilder({
    super.key,
    required this.future,
    required this.builder,
    this.emptyBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final count = snapshot.data!;
          if (count > 0 || count == -1) {
            return builder(context, count);
          }
          return emptyBuilder ?? const SizedBox.shrink();
        }
        return builder(context, -1);
      },
    );
  }
}

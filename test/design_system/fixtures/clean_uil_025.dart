import 'package:flutter/material.dart';

class AppDensity {
  const AppDensity(this.isCompact);

  final bool isCompact;

  static AppDensity of(BuildContext context) => const AppDensity(false);
}

class Bar extends StatelessWidget {
  const Bar({super.key, this.compactMenuMode = false});

  /// A parameter of the component itself, not the settings value.
  final bool compactMenuMode;

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: AppDensity.of(context).isCompact ? 36 : 44);
}

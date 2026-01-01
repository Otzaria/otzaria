import 'package:flutter/material.dart';

class LoadingIndicator extends StatelessWidget {
  final double? strokeWidth;
  final double? size;
  final Color? color;

  const LoadingIndicator({
    super.key,
    this.strokeWidth,
    this.size,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final indicator = CircularProgressIndicator(
      strokeWidth: strokeWidth ?? 4.0,
      valueColor: color != null ? AlwaysStoppedAnimation<Color>(color!) : null,
    );

    if (size != null) {
      return SizedBox(
        width: size,
        height: size,
        child: indicator,
      );
    }

    return Center(child: indicator);
  }
}

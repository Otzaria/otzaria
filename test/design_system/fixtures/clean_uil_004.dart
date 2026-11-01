import 'package:flutter/material.dart';

class Swatch {
  const Swatch(this.primaryColor);

  final Color primaryColor;
}

Color fromScheme(BuildContext context) => Theme.of(context).colorScheme.primary;

Color fromField(Swatch swatch) => swatch.primaryColor;

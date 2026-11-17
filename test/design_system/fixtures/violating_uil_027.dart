import 'package:flutter/material.dart';

class AppSurfaces {
  static Color card(BuildContext context) => Theme.of(context).cardColor;
}

Color a(bool isDark, ColorScheme cs) =>
    isDark ? cs.surface : cs.surfaceContainer; // LINT
Color b(BuildContext context) =>
    /* LINT */ Theme.of(context).brightness == Brightness.dark
    ? Theme.of(context).colorScheme.surfaceContainerHighest
    : AppSurfaces.card(context);
Color c(bool dark) => dark ? Colors.black : const Color(0xFFFFFFFF); // LINT
Color d(ColorScheme cs) {
  if (cs.brightness == Brightness.dark /* LINT */ ) {
    return cs.primary.withValues(alpha: 0.5);
  } else {
    return cs.primary;
  }
}

Color e(Brightness brightness, ColorScheme cs) =>
    switch (brightness /* LINT */ ) {
      Brightness.dark => cs.onSurface,
      Brightness.light => cs.shadow,
    };

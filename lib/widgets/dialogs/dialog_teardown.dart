import 'dart:async';

import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_surfaces.dart';

/// כמו [showDialog], אבל משלים `null` גם כשה-Navigator פורק לפני בניית הדיאלוג.
Future<T?> showDialogUntilTornDown<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
    barrierColor:
        DialogTheme.of(context).barrierColor ??
        Theme.of(context).dialogTheme.barrierColor ??
        AppSurfaces.scrim(Theme.of(context).colorScheme),
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  );
  return Future.any([navigator.push<T>(route), route.completed]);
}

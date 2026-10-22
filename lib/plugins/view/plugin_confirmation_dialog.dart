import 'dart:async';

import 'package:flutter/material.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';

/// דיאלוג אישור יחיד שחי רק כל עוד מופע התוסף שפתח אותו חי.
class PluginConfirmationDialog {
  DialogRoute<bool>? _route;
  bool _disposed = false;

  Future<bool> show({
    required BuildContext context,
    required String title,
    required String content,
  }) async {
    if (_disposed) return false;
    if (_route != null) {
      throw Exception('error.conflict: כבר פתוח דיאלוג אישור של מופע התוסף.');
    }
    final navigator = Navigator.of(context, rootNavigator: true);
    final direction = Directionality.of(context);
    final route = DialogRoute<bool>(
      context: context,
      barrierColor:
          DialogTheme.of(context).barrierColor ??
          Theme.of(context).dialogTheme.barrierColor ??
          Colors.black54,
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      builder: (_) => Directionality(
        textDirection: direction,
        child: AppDialog.twoActions(title: title, content: content),
      ),
    );
    _route = route;
    try {
      // השמדת החלון משלימה את completed גם כשה-Future של push נשאר ממתין.
      return await Future.any<bool?>([
            navigator.push(route),
            route.completed,
          ]) ==
          true;
    } finally {
      if (identical(_route, route)) _route = null;
    }
  }

  void dispose() {
    _disposed = true;
    final route = _route;
    if (route == null) return;
    // הסרת route בזמן dispose של ה-host תיגע ב-Navigator כשהעץ נעול.
    scheduleMicrotask(() {
      final navigator = route.navigator;
      if (route.isActive && navigator != null && navigator.mounted) {
        navigator.removeRoute(route, false);
      }
    });
  }
}

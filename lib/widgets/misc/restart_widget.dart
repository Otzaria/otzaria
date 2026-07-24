import 'dart:async';

import 'package:flutter/material.dart';

class RestartWidget extends StatefulWidget {
  const RestartWidget({super.key, required this.child});

  final Widget child;

  static void restartApp(
    BuildContext context, {
    FutureOr<void> Function()? afterRestart,
  }) {
    context.findAncestorStateOfType<_RestartWidgetState>()?.restartApp(
      afterRestart: afterRestart,
    );
  }

  @override
  State<RestartWidget> createState() => _RestartWidgetState();
}

class _RestartWidgetState extends State<RestartWidget> {
  Key key = UniqueKey();

  void restartApp({FutureOr<void> Function()? afterRestart}) {
    setState(() {
      key = UniqueKey();
    });
    if (afterRestart != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await afterRestart();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: key,
      child: widget.child,
    );
  }
}

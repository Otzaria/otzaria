import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';

/// Tells the native freeze detector (Windows) what the user is looking at, so
/// a `UI freeze` record in errors.txt names the screen and tab.
class FreezeContextReporter extends StatefulWidget {
  const FreezeContextReporter({
    super.key,
    required this.describe,
    required this.child,
  });

  final Map<String, Object?> Function() describe;
  final Widget child;

  @override
  State<FreezeContextReporter> createState() => _FreezeContextReporterState();
}

class _FreezeContextReporterState extends State<FreezeContextReporter> {
  static const MethodChannel _channel = MethodChannel(
    'otzaria/process_control',
  );

  // הגלאי מנטר רק את ה-thread של התהליך הראשי; חלון משני היה דורס את ההקשר.
  final bool _enabled =
      defaultTargetPlatform == TargetPlatform.windows &&
      !WindowRole.isSecondary;
  String? _sent;

  @override
  void initState() {
    super.initState();
    if (_enabled) _report();
  }

  void _report() {
    final String text;
    try {
      text = widget
          .describe()
          .entries
          .map((entry) => '${entry.key}: ${entry.value}')
          .join(', ');
    } catch (_) {
      return;
    }
    if (text == _sent) return;
    _sent = text;
    unawaited(
      _channel.invokeMethod<void>('setFreezeContext', text).catchError((_) {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return widget.child;
    return MultiBlocListener(
      listeners: [
        BlocListener<TabsBloc, TabsState>(listener: (_, _) => _report()),
        BlocListener<NavigationBloc, NavigationState>(
          listener: (_, _) => _report(),
        ),
      ],
      child: widget.child,
    );
  }
}

import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/diagnostics/app_context_snapshot.dart';
import 'package:otzaria/core/diagnostics/native_diagnostics_bridge.dart';
import 'package:otzaria/core/startup_timeline.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';

/// מתי נדלק גשר הנגישות (semantics) של Flutter, לדוח ולרשומות התקיעה.
class AccessibilityDiagnostics {
  AccessibilityDiagnostics._();

  static bool _installed = false;
  static int? _enabledAtMs;
  static bool _enabledBeforeInstall = false;
  static final List<VoidCallback> _listeners = [];

  /// מאזין לשינוי בלבד; פעם אחת לתהליך.
  static void install() {
    if (_installed) return;
    _installed = true;
    final binding = SemanticsBinding.instance;
    if (binding.semanticsEnabled) {
      _enabledAtMs = StartupTimeline.instance.elapsedMs;
      _enabledBeforeInstall = true;
    }
    binding.addSemanticsEnabledListener(_onChanged);
  }

  static void _onChanged() {
    if (SemanticsBinding.instance.semanticsEnabled) {
      _enabledAtMs ??= StartupTimeline.instance.elapsedMs;
    }
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  static void addListener(VoidCallback listener) => _listeners.add(listener);
  static void removeListener(VoidCallback listener) =>
      _listeners.remove(listener);

  static bool get _enabled => SemanticsBinding.instance.semanticsEnabled;

  /// חלק שורת ההקשר הנייטיב; ריק כשהגשר כבוי.
  static String get contextLabel =>
      _enabled ? 'semantics=on@${_enabledAtMs}ms' : '';

  /// מקטע האבחון בדוח.
  static Map<String, Object?> describe() {
    final request = NativeDiagnosticsBridge.instance
        ?.firstAccessibilityRequest();
    return {
      'semanticsEnabled': _enabled,
      'semanticsFirstEnabledAtMs': ?_enabledAtMs,
      if (_enabledBeforeInstall) 'semanticsEnabledBeforeInstall': true,
      if (request != null) ...{
        'firstNativeRequest': request.kind,
        'firstNativeRequestAtMs': request.msSinceLaunch,
      },
    };
  }

  @visibleForTesting
  static void resetForTest() {
    if (_installed) {
      SemanticsBinding.instance.removeSemanticsEnabledListener(_onChanged);
    }
    _installed = false;
    _enabledAtMs = null;
    _enabledBeforeInstall = false;
    _listeners.clear();
  }
}

/// מעדכן את ההקשר שה-runner כותב לרשומות `App hang` ו-`Native crash`.
/// מאזין לשינויים בלבד, וקורא ל-FFI רק כשהשורה השתנתה.
class NativeCrashContextScope extends StatefulWidget {
  const NativeCrashContextScope({
    super.key,
    required this.child,
    this.sink,
  });

  final Widget child;

  /// לבדיקות; ברירת המחדל היא ה-runner, ובלעדיו הווידג'ט אינו מאזין.
  final void Function(String context)? sink;

  @override
  State<NativeCrashContextScope> createState() =>
      _NativeCrashContextScopeState();
}

class _NativeCrashContextScopeState extends State<NativeCrashContextScope> {
  final List<StreamSubscription<Object?>> _subscriptions = [];
  void Function(String)? _sink;
  String? _last;

  @override
  void initState() {
    super.initState();
    AccessibilityDiagnostics.install();
    _sink = widget.sink ?? NativeDiagnosticsBridge.instance?.setContext;
    if (_sink == null) return;
    AccessibilityDiagnostics.addListener(_push);
    _subscriptions
      ..add(context.read<NavigationBloc>().stream.listen((_) => _push()))
      ..add(context.read<TabsBloc>().stream.listen((_) => _push()));
    _push();
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    AccessibilityDiagnostics.removeListener(_push);
    super.dispose();
  }

  void _push() {
    final sink = _sink;
    if (sink == null || !mounted) return;
    try {
      final semantics = AccessibilityDiagnostics.contextLabel;
      final text = [
        if (semantics.isNotEmpty) semantics,
        describeShortAppContext(
          screen: context.read<NavigationBloc>().state.currentScreen,
          tabs: context.read<TabsBloc>().state,
        ),
      ].join('; ');
      if (text == _last) return;
      _last = text;
      sink(text);
    } catch (error) {
      debugPrint('NativeCrashContextScope: $error');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

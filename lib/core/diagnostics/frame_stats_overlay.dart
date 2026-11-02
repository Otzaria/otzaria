import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/core/diagnostics/developer_diagnostics.dart';
import 'package:otzaria/core/messages/common_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/theme/app_tokens.dart';

/// Wraps the app, toggles developer mode on Ctrl+Shift+I, and shows the
/// diagnostics panel in a corner while it is on.
class FrameStatsOverlay extends StatefulWidget {
  const FrameStatsOverlay({
    super.key,
    required this.child,
    this.contextProvider,
  });

  final Widget child;

  /// Describes what the app is showing, for the diagnostics log.
  final Map<String, Object?> Function()? contextProvider;

  @override
  State<FrameStatsOverlay> createState() => _FrameStatsOverlayState();
}

class _FrameStatsOverlayState extends State<FrameStatsOverlay> {
  static final _windows = <_FrameStatsOverlayState, AppWindowKeys>{};

  static Map<String, Object?> _activeContext() {
    for (final window in _windows.entries) {
      if (identical(window.value, AppWindowKeys.current)) {
        return window.key.widget.contextProvider?.call() ?? const {};
      }
    }
    return const {};
  }

  DeveloperDiagnostics get _diagnostics => DeveloperDiagnostics.instance;

  @override
  void initState() {
    super.initState();
    _diagnostics.contextProvider = _activeContext;
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _windows[this] = AppWindowKeys.of(context);
  }

  @override
  void didUpdateWidget(FrameStatsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _diagnostics.contextProvider = _activeContext;
  }

  @override
  void dispose() {
    _windows.remove(this);
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (!isDeveloperModeShortcut(event, HardwareKeyboard.instance)) {
      return false;
    }
    // מצב הלוח משותף; מאזין בכל חלון היה מחליף אותו פעמיים.
    if (!AppWindowKeys.isActiveWindow(context)) return false;
    _diagnostics.toggle();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _diagnostics.panelVisible,
      // The child keeps index 0 so toggling the panel never remounts the app.
      builder: (context, visible, child) => Stack(
        fit: StackFit.passthrough,
        children: [
          child!,
          if (visible)
            const Positioned(left: 8, bottom: 8, child: FrameStatsPanel()),
        ],
      ),
      child: widget.child,
    );
  }
}

class FrameStatsPanel extends StatefulWidget {
  const FrameStatsPanel({super.key});

  @override
  State<FrameStatsPanel> createState() => _FrameStatsPanelState();
}

class _FrameStatsPanelState extends State<FrameStatsPanel> {
  bool _expanded = true;
  String? _notice;
  Timer? _noticeTimer;

  DeveloperDiagnostics get _diagnostics => DeveloperDiagnostics.instance;

  @override
  void dispose() {
    _noticeTimer?.cancel();
    super.dispose();
  }

  void _showNotice(String text) {
    _noticeTimer?.cancel();
    setState(() => _notice = text);
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  Future<void> _snapshot() async {
    final path = await _diagnostics.snapshot();
    if (path == null) {
      UiSnack.showError(CommonMessages.diagnosticsSaveError);
    } else if (mounted) {
      _showNotice('saved: $path');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textStyle = TextStyle(
      color: colors.onInverseSurface,
      fontFamily: 'monospace',
      fontSize: 11,
      height: 1.3,
    );
    // The panel sits above the Navigator: it has no Material or Overlay
    // ancestor, so it brings its own Material and uses no tooltips.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        type: MaterialType.transparency,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.inverseSurface.withValues(alpha: 0.88),
            borderRadius: AppTokens.borderRadiusAll,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 4, 6),
            child: IconTheme(
              data: IconThemeData(color: colors.onInverseSurface, size: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildToolbar(),
                  if (_expanded)
                    ValueListenableBuilder<FrameStats>(
                      valueListenable: _diagnostics.stats,
                      builder: (context, stats, _) =>
                          Text(formatFrameStats(stats), style: textStyle),
                    ),
                  if (_notice != null)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Text(_notice!, style: textStyle),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    Widget button(
      IconData icon,
      String label,
      VoidCallback onPressed, {
      bool active = false,
    }) => IconButton(
      icon: Icon(icon),
      isSelected: active,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 26, height: 26),
      onPressed: () {
        onPressed();
        if (label.isNotEmpty) _showNotice(label);
      },
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(
          _expanded
              ? FluentIcons.chevron_down_24_regular
              : FluentIcons.chevron_up_24_regular,
          '',
          () => setState(() => _expanded = !_expanded),
        ),
        button(FluentIcons.camera_24_regular, '', _snapshot),
        ValueListenableBuilder<bool>(
          valueListenable: _diagnostics.performanceOverlay,
          builder: (context, on, _) => button(
            FluentIcons.data_histogram_24_regular,
            'performance graphs ${on ? 'off' : 'on'}',
            () => _diagnostics.performanceOverlay.value = !on,
            active: on,
          ),
        ),
        if (kDebugMode) ...[
          button(
            FluentIcons.paint_brush_24_regular,
            'repaint rainbow ${_diagnostics.repaintRainbow ? 'off' : 'on'}',
            () => setState(
              () => _diagnostics.repaintRainbow = !_diagnostics.repaintRainbow,
            ),
            active: _diagnostics.repaintRainbow,
          ),
          button(
            FluentIcons.border_outside_24_regular,
            'layout bounds ${_diagnostics.paintSize ? 'off' : 'on'}',
            () => setState(
              () => _diagnostics.paintSize = !_diagnostics.paintSize,
            ),
            active: _diagnostics.paintSize,
          ),
        ],
      ],
    );
  }
}

/// Ctrl+Shift+I, as in browser developer tools (Cmd+Shift+I on macOS).
@visibleForTesting
bool isDeveloperModeShortcut(KeyEvent event, HardwareKeyboard keyboard) =>
    event is KeyDownEvent &&
    (event.logicalKey == LogicalKeyboardKey.keyI ||
        event.physicalKey == PhysicalKeyboardKey.keyI) &&
    keyboard.isShiftPressed &&
    (keyboard.isControlPressed || keyboard.isMetaPressed) &&
    !keyboard.isAltPressed;

/// Formats the panel text.
@visibleForTesting
String formatFrameStats(FrameStats stats) {
  String ms(double? v) => v == null ? '-' : v.toStringAsFixed(1);
  final buffer = StringBuffer()
    ..writeln('frames/s  ${stats.framesPerSecond}')
    ..writeln(
      'build ms  avg ${ms(stats.buildAvgMs)}  max ${ms(stats.buildMaxMs)}',
    )
    ..writeln(
      'raster ms avg ${ms(stats.rasterAvgMs)}  max ${ms(stats.rasterMaxMs)}',
    )
    ..writeln(
      'slow      ${stats.slowInWindow} '
      '(${DeveloperDiagnostics.window.inSeconds}s)  total ${stats.slowTotal}',
    )
    ..write('memory    ${stats.rssMb} MB  peak ${stats.peakRssMb} MB');
  final processes = stats.processes;
  if (processes?.hostPrivMb case final priv?) buffer.write('  priv $priv MB');
  if (processes != null && processes.webview.isNotEmpty) {
    final count = processes.webview.values.fold(0, (n, k) => n + k.count);
    buffer.write('\nwebview   ${processes.webviewPrivMb} MB  $count proc');
    if (processes.renderers case final r?) {
      buffer.write('  ${r.count} rend ${r.privMb} MB (max ${r.eachMb.first})');
    }
  }
  final estimates = stats.estimates;
  if (estimates != null) {
    buffer.write(
      '\nestimates ${estimates.count}x  ${ms(estimates.totalMs)} ms  '
      '${estimates.items} items  deferred ${estimates.deferred}  '
      'skipped ${estimates.skipped}',
    );
  }
  for (final entry in stats.topRebuilds.take(5)) {
    buffer.write('\nrebuild   ${entry.value}x ${entry.key}');
  }
  return buffer.toString();
}

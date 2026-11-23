import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:otzaria/core/window_persistence.dart';
import 'package:window_manager/window_manager.dart';

import '../../tool/perf_probe/src/installed_pdf_desktop_contract.dart';
import 'webview_probe_window.dart';

/// תצפיות החלון נשארות native גם בזמן שהחלון מוסתר ואין פריימים.
class InstalledPdfDesktopWindow {
  InstalledPdfDesktopWindow._(this.original);

  final Map<String, Object?> original;
  Map<String, Object?>? normal;
  static const _timeout = Duration(seconds: 15);

  static Future<Map<String, Object?>> read() async => {
    ...await readWebViewProbeWindow(Platform.operatingSystem),
    'maximized': await windowManager.isMaximized(),
    'fullScreen': await windowManager.isFullScreen(),
  };

  static Future<InstalledPdfDesktopWindow> capture() async =>
      InstalledPdfDesktopWindow._(await read().timeout(_timeout));

  Future<Map<String, Object?>> observe(
    String description,
    bool Function(Map<String, Object?>) matches,
  ) async {
    final clock = Stopwatch()..start();
    Map<String, Object?>? previous;
    while (clock.elapsed < _timeout) {
      final state = await read().timeout(_timeout - clock.elapsed);
      if (matches(state) &&
          previous != null &&
          matches(previous) &&
          installedPdfWindowBoundsMatch(
            state['logicalBounds'],
            previous['logicalBounds'],
          )) {
        return state;
      }
      previous = state;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw TimeoutException('$description: $previous', _timeout);
  }

  Future<Map<String, Object?>> reveal() async {
    if (await windowManager.isMinimized().timeout(_timeout)) {
      await windowManager.restore().timeout(_timeout);
    }
    await windowManager.show().timeout(_timeout);
    await windowManager.focus().timeout(_timeout);
    return observe(
      'PDF window becomes visible',
      (state) => state['ready'] == true,
    );
  }

  Future<void> normalize() async {
    await reveal();
    if (await windowManager.isFullScreen().timeout(_timeout)) {
      await windowManager.setFullScreen(false).timeout(_timeout);
      await observe(
        'PDF window leaves full screen',
        (state) => state['fullScreen'] == false,
      );
    }
    if (await windowManager.isMaximized().timeout(_timeout)) {
      await windowManager.unmaximize().timeout(_timeout);
    }
    normal = await observe(
      'PDF window leaves maximized/full-screen mode',
      (state) =>
          state['ready'] == true &&
          state['fullScreen'] == false &&
          state['maximized'] == false,
    );
  }

  Future<Map<String, Object?>> hide() async {
    await windowManager.hide().timeout(_timeout);
    return observe(
      'PDF window is hidden',
      (state) => state['visible'] == false,
    );
  }

  Future<Map<String, Object?>> minimize() async {
    await windowManager.minimize().timeout(_timeout);
    return observe(
      'PDF window is minimized',
      (state) => state['minimized'] == true,
    );
  }

  Map<String, Object?> resizedBounds() {
    final bounds = normal!['logicalBounds']! as Map;
    final width = (bounds['width'] as num).toDouble() - 120;
    final height = (bounds['height'] as num).toDouble() - 80;
    if (width < WindowPersistence.minSize.width ||
        height < WindowPersistence.minSize.height) {
      throw StateError('The controlled desktop window is too small to resize');
    }
    return {
      'x': bounds['x'],
      'y': bounds['y'],
      'width': width,
      'height': height,
    };
  }

  Future<Map<String, Object?>> resize(Map<String, Object?> bounds) async {
    await windowManager
        .setBounds(
          Rect.fromLTWH(
            (bounds['x'] as num).toDouble(),
            (bounds['y'] as num).toDouble(),
            (bounds['width'] as num).toDouble(),
            (bounds['height'] as num).toDouble(),
          ),
        )
        .timeout(_timeout);
    return observe(
      'PDF window adopts requested bounds',
      (state) =>
          state['ready'] == true &&
          installedPdfWindowBoundsMatch(state['logicalBounds'], bounds),
    );
  }

  Future<Map<String, Object?>> restore() async {
    await reveal();
    if (await windowManager.isFullScreen().timeout(_timeout)) {
      await windowManager.setFullScreen(false).timeout(_timeout);
      await observe(
        'PDF window leaves full screen before restoration',
        (state) => state['fullScreen'] == false,
      );
    }
    if (await windowManager.isMaximized().timeout(_timeout)) {
      await windowManager.unmaximize().timeout(_timeout);
    }
    await observe(
      'PDF window normalizes before restoration',
      (state) => state['fullScreen'] == false && state['maximized'] == false,
    );
    final bounds = (normal ?? original)['logicalBounds']! as Map;
    await resize(Map<String, Object?>.from(bounds));
    if (original['maximized'] == true) {
      await windowManager.maximize().timeout(_timeout);
      await observe(
        'PDF window restores maximization',
        (state) => state['maximized'] == true,
      );
    }
    if (original['fullScreen'] == true) {
      await windowManager.setFullScreen(true).timeout(_timeout);
      await observe(
        'PDF window restores full screen',
        (state) => state['fullScreen'] == true,
      );
    }
    if (original['minimized'] == true) {
      await windowManager.minimize().timeout(_timeout);
    }
    if (original['visible'] == false) {
      await windowManager.hide().timeout(_timeout);
    }
    return observe(
      'PDF window restores its original bounds and flags',
      (state) =>
          ['visible', 'minimized', 'maximized', 'fullScreen'].every(
            (key) => state[key] == original[key],
          ) &&
          installedPdfWindowBoundsMatch(
            state['logicalBounds'],
            original['logicalBounds'],
          ),
    );
  }
}

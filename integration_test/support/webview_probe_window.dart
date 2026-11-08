import 'dart:async';

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

const _desktopPlatforms = {'windows', 'linux', 'macos'};
const _windowSize = Size(1000, 700);
const _splashChannel = MethodChannel('otzaria/splash');

/// בודק את חלון המארח, בנפרד מ-document.visibility של ה-WebView.
Future<Map<String, Object?>> readWebViewProbeWindow(String platform) async {
  if (!_desktopPlatforms.contains(platform)) {
    return {
      'availability': 'unsupported',
      'reason': 'Native desktop window checks do not apply on this platform.',
    };
  }
  final visible = await windowManager.isVisible();
  final minimized = await windowManager.isMinimized();
  final opacity = platform == 'macos' ? await windowManager.getOpacity() : null;
  final bounds = await windowManager.getBounds();
  return {
    'availability': 'collected',
    'source': 'window_manager native window queries',
    'visible': visible,
    'minimized': minimized,
    'opacity': ?opacity,
    'logicalBounds': {
      'x': bounds.left,
      'y': bounds.top,
      'width': bounds.width,
      'height': bounds.height,
    },
    'ready':
        visible &&
        !minimized &&
        (opacity == null || opacity == 1) &&
        bounds.width.isFinite &&
        bounds.height.isFinite &&
        bounds.width > 0 &&
        bounds.height > 0,
  };
}

/// חושף את חלון הניסוי לפני יצירת WebView ולפני חלונות המדידה השקטים.
Future<Map<String, Object?>> prepareWebViewProbeWindow({
  required String platform,
  required Future<void> Function() pumpFrame,
  bool closeNativeSplash = true,
  Duration timeout = const Duration(seconds: 10),
}) async {
  if (!_desktopPlatforms.contains(platform)) {
    return readWebViewProbeWindow(platform);
  }
  final clock = Stopwatch()..start();
  Future<T> bounded<T>(Future<T> Function() operation) {
    final remaining = timeout - clock.elapsed;
    if (remaining <= Duration.zero) throw TimeoutException('Window reveal');
    return operation().timeout(remaining);
  }

  Map<String, Object?>? observed;
  try {
    await bounded(windowManager.ensureInitialized);
    await bounded(() => windowManager.setSize(_windowSize));
    await bounded(windowManager.show);
    await bounded(windowManager.focus);
    await bounded(pumpFrame);
    if (closeNativeSplash) {
      await bounded(() => _splashChannel.invokeMethod<void>('close'));
    }
    while (true) {
      await bounded(pumpFrame);
      final state = await bounded(() => readWebViewProbeWindow(platform));
      observed = state;
      if (state['ready'] == true) {
        return {
          ...state,
          'requestedLogicalSize': {
            'width': _windowSize.width,
            'height': _windowSize.height,
          },
        };
      }
      // ShowWindowAsync and the macOS splash fade finish after their replies.
      await bounded(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    }
  } on TimeoutException {
    throw TimeoutException(
      'Desktop window did not become visible and opaque: $observed',
      timeout,
    );
  }
}

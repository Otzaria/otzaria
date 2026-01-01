import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';
import 'package:otzaria/core/window_persistence.dart';

/// Callback type for fullscreen state changes
typedef FullscreenCallback = void Function(bool isFullscreen);

/// Window listener that handles window events properly to prevent crashes
class AppWindowListener extends WindowListener {
  FullscreenCallback? onFullscreenChanged;

  @override
  void onWindowEnterFullScreen() {
    if (kDebugMode) {
      print('Window entered fullscreen');
    }
    onFullscreenChanged?.call(true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (kDebugMode) {
      print('Window left fullscreen');
    }
    onFullscreenChanged?.call(false);
  }

  @override
  void onWindowClose() {
    if (kDebugMode) {
      print('Window close requested');
    }

    try {
      // Perform cleanup operations here if needed

      // Close the window properly
      if (!kIsWeb &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        // Use Future.microtask to avoid blocking the current execution
        Future.microtask(() async {
          await WindowPersistence.saveNow();
          await windowManager.destroy();
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error during window close: $e');
      }
      // Force exit if cleanup fails - but only as last resort
      exit(0);
    }
  }

  @override
  void onWindowFocus() {
    if (kDebugMode) {
      print('Window focused');
    }
  }

  @override
  void onWindowBlur() {
    if (kDebugMode) {
      print('Window blurred');
    }
  }

  @override
  void onWindowMinimize() {
    if (kDebugMode) {
      print('Window minimized');
    }
  }

  @override
  void onWindowRestore() {
    if (kDebugMode) {
      print('Window restored');
    }
  }

  @override
  void onWindowResize() {
    if (kDebugMode) {
      print('Window resized');
    }

    WindowPersistence.scheduleSave();
  }

  @override
  void onWindowMove() {
    if (kDebugMode) {
      print('Window moved');
    }

    WindowPersistence.scheduleSave();
  }

  @override
  void onWindowMaximize() {
    if (kDebugMode) {
      print('Window maximized');
    }
    WindowPersistence.scheduleSave();
  }

  @override
  void onWindowUnmaximize() {
    if (kDebugMode) {
      print('Window unmaximized');
    }
    WindowPersistence.scheduleSave();
  }

  /// Clean up the listener when disposing
  void dispose() {

    // Remove this listener from window manager
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      windowManager.removeListener(this);
    }
  }
}


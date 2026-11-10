// The 0.6 window bridge cannot assume that a hidden Flutter runner window
// is the OS foreground window. Bind the top-level window we already own.
// ignore_for_file: deprecated_member_use

import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:nativeapi/nativeapi.dart' as nativeapi;
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';
import 'package:otzaria/core/windowing/runner_window_channel.dart';
import 'package:window_manager/legacy.dart';

/// Wrap the actual Flutter runner window rather than creating a second one.
/// The returned pointer also serves as the owner for native file dialogs.
///
/// Tests supply [nativeHandleProvider] and [windowFactory] to exercise this
/// without creating native windows or loading a platform-specific library.
Future<int?> bindNativeapiPrimaryWindow({
  Future<int?> Function()? nativeHandleProvider,
  nativeapi.Window? Function(int address)? windowFactory,
}) async {
  final handle = await (nativeHandleProvider ?? _runnerHandle)();
  if (handle == null || handle == 0) return null;
  final window = (windowFactory ??
      (int address) => nativeapi.Window.createWithNativeWindow(
        Pointer<Void>.fromAddress(address),
      ))(handle);
  if (window == null) return null;

  windowManager.bindWindow(window);
  return handle;
}

Future<int?> _runnerHandle() async {
  if (kIsWeb) return null;
  if (Platform.isMacOS) return implicitViewWindowHandle();
  if (Platform.isWindows || Platform.isLinux) {
    return const RunnerWindowChannel().mainWindowHandle();
  }
  return null;
}

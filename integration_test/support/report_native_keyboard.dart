import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win32/win32.dart' as win;

Future<void> pumpNativeUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String reason,
}) async {
  await tester.pump();
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
    await tester.pump(const Duration(milliseconds: 25));
  }
  expect(condition(), isTrue, reason: reason);
}

int _windowProcess(win.HWND window) => using((arena) {
  final process = arena<Uint32>();
  win.GetWindowThreadProcessId(window, process);
  return process.value;
});

// The existing WebView HWND integration test uses the same runner class and
// process check. Without the application's main(), this window starts hidden.
win.HWND _showOwnWindow() => using((arena) {
  final className = win.PCWSTR(
    'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16(allocator: arena),
  );
  win.HWND? previous;
  for (var index = 0; index < 100; index++) {
    final window = win.FindWindowEx(null, previous, className, null).value;
    if (window.isNull) {
      break;
    }
    if (_windowProcess(window) == pid) {
      win.SetWindowPos(
        window,
        null,
        40,
        40,
        1100,
        850,
        win.SWP_NOZORDER,
      );
      win.ShowWindow(window, win.SW_SHOW);
      win.SetForegroundWindow(window);
      return window;
    }
    previous = window;
  }
  throw StateError('No Flutter runner window belongs to process $pid.');
});

int _sendKeys(List<win.VIRTUAL_KEY> keys, {required bool release}) =>
    using((arena) {
      final inputs = arena<win.INPUT>(keys.length);
      for (var index = 0; index < keys.length; index++) {
        final input = inputs[index];
        input.type = win.INPUT_KEYBOARD;
        input.ki.wVk = keys[index];
        input.ki.wScan = win.MapVirtualKey(keys[index], win.MAPVK_VK_TO_VSC);
        input.ki.dwFlags = win.KEYBD_EVENT_FLAGS(
          (release ? win.KEYEVENTF_KEYUP : 0) |
              (keys[index] == win.VK_INSERT ? win.KEYEVENTF_EXTENDEDKEY : 0),
        );
      }
      return win.SendInput(keys.length, inputs, sizeOf<win.INPUT>()).value;
    });

Future<void> focusNativeReportWindow(WidgetTester tester) async {
  final window = _showOwnWindow();
  await pumpNativeUntil(
    tester,
    () => win.GetForegroundWindow().address == window.address,
    reason: 'The test application must own the foreground window.',
  );
  expect(_windowProcess(win.GetForegroundWindow()), pid);
}

/// Sends actual Windows input to this process, never Flutter test key events.
/// Every down sequence has a finally-protected matching release sequence.
Future<void> sendNativePaste(
  WidgetTester tester, {
  required bool shiftInsert,
  required bool Function() applied,
}) async {
  await focusNativeReportWindow(tester);
  final modifier = shiftInsert ? win.VK_SHIFT : win.VK_CONTROL;
  final key = shiftInsert ? win.VK_INSERT : win.VK_V;
  final logicalKey = shiftInsert
      ? LogicalKeyboardKey.insert
      : LogicalKeyboardKey.keyV;
  expect(win.GetAsyncKeyState(modifier) & 0x8000, 0);
  var observed = false;
  bool observe(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == logicalKey &&
        !event.synthesized) {
      observed = true;
    }
    return false;
  }

  HardwareKeyboard.instance.addHandler(observe);
  try {
    expect(
      _sendKeys([modifier, key], release: false),
      2,
      reason: 'Windows must accept both native key-down events.',
    );
    await pumpNativeUntil(
      tester,
      () => observed && applied(),
      reason: 'Native input must reach Flutter and update the actual report.',
    );
    expect(_windowProcess(win.GetForegroundWindow()), pid);
  } finally {
    try {
      expect(
        _sendKeys([key, modifier], release: true),
        2,
        reason: 'Windows must accept both native key-up events.',
      );
      await pumpNativeUntil(
        tester,
        () =>
            !HardwareKeyboard.instance.isControlPressed &&
            !HardwareKeyboard.instance.isShiftPressed &&
            !HardwareKeyboard.instance.logicalKeysPressed.contains(
              logicalKey,
            ) &&
            (win.GetAsyncKeyState(modifier) & 0x8000) == 0 &&
            (win.GetAsyncKeyState(key) & 0x8000) == 0,
        reason:
            'The injected keys must be released even if an assertion fails.',
      );
    } finally {
      HardwareKeyboard.instance.removeHandler(observe);
    }
  }
}

/// Submits down/down/up/up together, without holding Ctrl until Dart responds.
/// Zero wScan is submitted to Windows; the engine's received scan code may differ.
Future<List<Map<String, Object?>>> sendNativeBatchedPaste(
  WidgetTester tester, {
  required bool Function() applied,
}) async {
  await focusNativeReportWindow(tester);
  expect(win.GetAsyncKeyState(win.VK_CONTROL) & 0x8000, 0);
  expect(win.GetAsyncKeyState(win.VK_V) & 0x8000, 0);
  final trace = <Map<String, Object?>>[];
  var observed = false;
  bool observe(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.controlLeft ||
        event.logicalKey == LogicalKeyboardKey.controlRight ||
        event.logicalKey == LogicalKeyboardKey.keyV) {
      trace.add({
        'type': event.runtimeType.toString(),
        'logical': event.logicalKey.keyId,
        'physical': event.physicalKey.usbHidUsage,
        'synthesized': event.synthesized,
        'controlPressed': HardwareKeyboard.instance.isControlPressed,
        'win32LeftControlPressedAtCallback':
            (win.GetKeyState(win.VK_LCONTROL) & 0x8000) != 0,
      });
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.keyV &&
          !event.synthesized) {
        observed = true;
      }
    }
    return false;
  }

  bool released() =>
      !HardwareKeyboard.instance.isControlPressed &&
      !HardwareKeyboard.instance.logicalKeysPressed.contains(
        LogicalKeyboardKey.keyV,
      ) &&
      (win.GetAsyncKeyState(win.VK_CONTROL) & 0x8000) == 0 &&
      (win.GetAsyncKeyState(win.VK_V) & 0x8000) == 0;

  Object? firstError;
  HardwareKeyboard.instance.addHandler(observe);
  try {
    final submitted = using((arena) {
      final inputs = arena<win.INPUT>(4);
      final keys = [win.VK_CONTROL, win.VK_V, win.VK_V, win.VK_CONTROL];
      for (var index = 0; index < keys.length; index++) {
        inputs[index].type = win.INPUT_KEYBOARD;
        inputs[index].ki.wVk = keys[index];
        inputs[index].ki.wScan = 0;
        inputs[index].ki.dwFlags = win.KEYBD_EVENT_FLAGS(
          index >= 2 ? win.KEYEVENTF_KEYUP : 0,
        );
      }
      return win.SendInput(4, inputs, sizeOf<win.INPUT>()).value;
    });
    expect(submitted, 4, reason: 'Windows must accept the complete key batch.');
    await pumpNativeUntil(
      tester,
      () => observed && applied() && released(),
      reason:
          'The complete native chord must paste once and release all keys; '
          'trace: $trace',
    );
    expect(_windowProcess(win.GetForegroundWindow()), pid);
    return List<Map<String, Object?>>.unmodifiable(trace);
  } catch (error, stack) {
    firstError = error;
    debugPrint('Batched paste failure before cleanup: $error\n$stack');
    rethrow;
  } finally {
    final beforeCleanup = <String, Object?>{
      'observedV': observed,
      'released': released(),
      'frameworkKeys': HardwareKeyboard.instance.logicalKeysPressed
          .map((key) => key.keyId)
          .toList(),
      'win32ControlPressed':
          (win.GetAsyncKeyState(win.VK_CONTROL) & 0x8000) != 0,
      'win32VPressed': (win.GetAsyncKeyState(win.VK_V) & 0x8000) != 0,
    };
    try {
      beforeCleanup['applied'] = applied();
    } catch (error) {
      beforeCleanup['appliedError'] = error.toString();
    }
    debugPrint(
      'Batched native Ctrl+V state before cleanup: $beforeCleanup',
    );
    debugPrint('Batched native Ctrl+V trace: $trace');
    try {
      if (!released()) {
        expect(_sendKeys([win.VK_V, win.VK_CONTROL], release: true), 2);
        await pumpNativeUntil(
          tester,
          released,
          reason: 'Batched paste must not leave Ctrl or V pressed.',
        );
      }
    } catch (error, stack) {
      debugPrint('Batched paste cleanup failure: $error\n$stack');
      if (firstError == null) rethrow;
    } finally {
      HardwareKeyboard.instance.removeHandler(observe);
    }
  }
}

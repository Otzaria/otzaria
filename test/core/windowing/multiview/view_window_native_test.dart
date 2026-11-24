@TestOn('windows')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/multiview/view_window_native.dart';
import 'package:win32/win32.dart';

void main() {
  test(
    'startDragging שולח את SC_MOVE של window_manager ולא WM_NCLBUTTONDOWN',
    () {
      // הכול סינכרוני: חלון ותור ההודעות שייכים ל-thread של הקריאה.
      final className = 'STATIC'.toNativeUtf16();
      final msg = calloc<MSG>();
      final hwnd = CreateWindowEx(
        const WINDOW_EX_STYLE(0),
        PCWSTR(className),
        null,
        const WINDOW_STYLE(0),
        0,
        0,
        0,
        0,
        HWND_MESSAGE,
        null,
        null,
        null,
      ).value;
      try {
        expect(hwnd.address, isNot(0));
        const Win32ViewWindowNative().startDragging(hwnd.address);

        expect(PeekMessage(msg, hwnd, 0, 0, PM_REMOVE), isTrue);
        expect(msg.ref.message, WM_SYSCOMMAND);
        expect(msg.ref.wParam, SC_MOVE | HTCAPTION);
        expect(Win32ViewWindowNative.dragCommand, 0xF012);
        expect(PeekMessage(msg, hwnd, 0, 0, PM_REMOVE), isFalse);
      } finally {
        DestroyWindow(hwnd);
        calloc
          ..free(msg)
          ..free(className);
      }
    },
  );
}

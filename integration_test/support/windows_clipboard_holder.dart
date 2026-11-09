import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart' as win;

/// The process whose window has the Windows clipboard open right now.
typedef _ClipboardHolder = ({int pid, String image, String windowClass});

_ClipboardHolder? _clipboardHolder() => using((arena) {
  final window = win.GetOpenClipboardWindow().value;
  if (window.isNull) return null;
  final process = arena<Uint32>();
  win.GetWindowThreadProcessId(window, process);
  final className = arena<Uint16>(256).cast<Utf16>();
  final classLength = win.GetClassName(window, win.PWSTR(className), 256).value;
  var image = '?';
  final handle = win.OpenProcess(
    win.PROCESS_QUERY_LIMITED_INFORMATION,
    false,
    process.value,
  ).value;
  if (!handle.isNull) {
    final path = arena<Uint16>(1024).cast<Utf16>();
    final size = arena<Uint32>()..value = 1024;
    if (win.QueryFullProcessImageName(
      handle,
      win.PROCESS_NAME_WIN32,
      win.PWSTR(path),
      size,
    ).value) {
      image = path.toDartString(length: size.value).split(r'\').last;
    }
    win.CloseHandle(handle);
  }
  return (
    pid: process.value,
    image: image,
    windowClass: classLength > 0 ? className.toDartString() : '?',
  );
});

bool _isOpenClipboardFailure(PlatformException error) =>
    // Flutter's engine reports OpenClipboard's ERROR_ACCESS_DENIED; OLE (used by
    // super_clipboard) reports CLIPBRD_E_CANT_OPEN.
    error.message == 'Unable to open clipboard' ||
    (error.message ?? '').contains('OpenClipboard Failed');

/// Runs [action] again while another process has the clipboard open.
///
/// The Clipboard User Service (svchost.exe) opens the clipboard briefly after
/// writes. A holder inside this process is an app leak, so it fails at once.
Future<T> retryClipboard<T>(Future<T> Function() action) async {
  for (var attempt = 1; ; attempt++) {
    try {
      return await action();
    } on PlatformException catch (error) {
      if (!_isOpenClipboardFailure(error)) rethrow;
      final holder = _clipboardHolder();
      if (holder?.pid == pid || attempt == 40) rethrow;
      // ignore: avoid_print
      print(
        'Clipboard open by ${holder ?? 'a process that already closed it'} '
        '(attempt $attempt); retrying.',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}

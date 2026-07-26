import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _GetFileAttributesW = Uint32 Function(Pointer<Utf16>);
typedef _GetFileAttributesDart = int Function(Pointer<Utf16>);

final _GetFileAttributesDart? _getFileAttributes = Platform.isWindows
    ? DynamicLibrary.open(
        'kernel32.dll',
      ).lookupFunction<_GetFileAttributesW, _GetFileAttributesDart>(
        'GetFileAttributesW',
      )
    : null;

/// מחזיר את מאפייני הקובץ של Windows, או null בפלטפורמה שאינה Windows.
int? windowsFileAttributes(String entityPath) {
  if (!Platform.isWindows) return null;

  final ptr = entityPath.toNativeUtf16();
  try {
    return _getFileAttributes!(ptr);
  } finally {
    calloc.free(ptr);
  }
}

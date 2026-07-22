import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

// FILE_ATTRIBUTE_HIDDEN  = 0x2
// FILE_ATTRIBUTE_SYSTEM  = 0x4
// INVALID_FILE_ATTRIBUTES = 0xFFFFFFFF
const int _kHidden = 0x2;
const int _kSystem = 0x4;
const int _kInvalid = 0xFFFFFFFF;

typedef _GetFileAttributesW = Uint32 Function(Pointer<Utf16>);
typedef _GetFileAttributesDart = int Function(Pointer<Utf16>);

final _GetFileAttributesDart? _getFileAttributes = Platform.isWindows
    ? DynamicLibrary.open(
        'kernel32.dll',
      ).lookupFunction<_GetFileAttributesW, _GetFileAttributesDart>(
        'GetFileAttributesW',
      )
    : null;

/// מחזיר true אם הקובץ/תיקייה מוסתרים או קובץ מערכת.
/// בודק גם לפי שם (נקודה / $ / שמות מערכת) וגם לפי מאפייני Windows.
bool isHiddenOrSystem(String entityPath) {
  final name = entityPath.split(Platform.pathSeparator).last;

  // בדיקה לפי שם
  if (_isHiddenOrSystemName(name)) return true;

  // בדיקה לפי מאפייני Windows
  if (Platform.isWindows) {
    final ptr = entityPath.toNativeUtf16();
    try {
      final attrs = _getFileAttributes!(ptr);
      if (hasHiddenOrSystemWindowsAttributes(attrs)) return true;
    } finally {
      calloc.free(ptr);
    }
  }

  return false;
}

/// מחזיר האם מאפייני קובץ של Windows מסמנים קובץ מוסתר או קובץ מערכת.
@visibleForTesting
bool hasHiddenOrSystemWindowsAttributes(int attributes) {
  return attributes != _kInvalid &&
      ((attributes & _kHidden) != 0 || (attributes & _kSystem) != 0);
}

bool _isHiddenOrSystemName(String name) {
  return name.startsWith('.') || name.startsWith(r'$');
}

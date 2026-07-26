import 'package:flutter/foundation.dart';

import 'file_hidden_utils_stub.dart'
    if (dart.library.io) 'file_hidden_utils_io.dart'
    as impl;

// FILE_ATTRIBUTE_HIDDEN  = 0x2
// FILE_ATTRIBUTE_SYSTEM  = 0x4
// INVALID_FILE_ATTRIBUTES = 0xFFFFFFFF
const int _kHidden = 0x2;
const int _kSystem = 0x4;
const int _kInvalid = 0xFFFFFFFF;

final RegExp _pathSeparator = RegExp(r'[/\\]');

/// מחזיר true אם הקובץ/תיקייה מוסתרים או קובץ מערכת.
/// בודק גם לפי שם (נקודה / $ / שמות מערכת) וגם לפי מאפייני Windows.
bool isHiddenOrSystem(String entityPath) {
  final name = entityPath.split(_pathSeparator).last;

  // בדיקה לפי שם
  if (_isHiddenOrSystemName(name)) return true;

  // בדיקה לפי מאפייני Windows
  final attributes = impl.windowsFileAttributes(entityPath);
  if (attributes != null && hasHiddenOrSystemWindowsAttributes(attributes)) {
    return true;
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

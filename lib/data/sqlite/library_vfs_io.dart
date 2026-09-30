import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:otzaria_zvfs/otzaria_zvfs.dart';

/// תקציב מטמון העמודים המפוענחים לכל קובץ zdb. null — ברירת המחדל של
/// החבילה ([ZVfs.cacheBytesPerFile]); הערך הסופי ייקבע אחרי מדידה.
const int? libraryZdbCacheBytesPerFile = null;

bool _registered = false;
({Object error, StackTrace stackTrace})? _registrationFailure;

/// כשל הרישום ב-isolate הזה, או null.
({Object error, StackTrace stackTrace})? get libraryVfsRegistrationFailure =>
    _registrationFailure;

/// רושם את zvfs כ-VFS ברירת המחדל של התהליך. אידמפוטנטי וזול אחרי הקריאה
/// הראשונה ב-isolate. לא זורק: בלי zvfs מסד seforim.db רגיל עדיין נפתח.
bool ensureLibraryVfs() {
  if (_registered) return true;
  if (_registrationFailure != null) return false;
  try {
    ZVfs.register(
      makeDefault: true,
      cacheBytesPerFile: libraryZdbCacheBytesPerFile,
    );
    _registered = true;
  } catch (error, stackTrace) {
    _registrationFailure = (error: error, stackTrace: stackTrace);
    debugPrint('[library_vfs] zvfs registration failed: $error');
  }
  return _registered;
}

/// האם [path] מתחיל ב-magic של zdb. נתיב פתוח דרך zvfs נענה מהמצב הפתוח.
bool isLibraryZdb(String path) => isZdb(path);

/// האם חיבור כלשהו בתהליך (בכל isolate) מחזיק את [path] פתוח דרך zvfs.
bool isLibraryDbOpenInProcess(String path) => ZVfs.isOpen(path);

/// בתים לוגיים של מסד zdb (בסיס + overlay). סינכרוני ומשחזר את ה-overlay —
/// לא על ה-UI isolate. זורק [ZdbException] כשהקובץ פתוח בתהליך.
Uint8List readLibraryZdbBytes(String path, int offset, int length) =>
    readZdbBytes(path, offset, length);

/// הגודל ש-SQLite רואה במסד zdb. סינכרוני, כמו [readLibraryZdbBytes].
int libraryZdbLogicalSize(String path) => readZdbInfo(path).logicalSize;

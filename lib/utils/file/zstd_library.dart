import 'dart:ffi';
import 'dart:io';

import 'package:otzaria/utils/file/windows_library_preload.dart';

/// ה-DynamicLibrary של zstandard לפלטפורמה הנוכחית; נפתח פעם אחת לכל isolate.
DynamicLibrary openZstandardLib() => _zstandardLib;

final DynamicLibrary _zstandardLib = _openZstandardLib();

DynamicLibrary _openZstandardLib() {
  if (Platform.isAndroid) {
    return DynamicLibrary.open('libzstandard_android.so');
  }
  if (Platform.isWindows) {
    const name = 'zstandard_windows.dll';
    // אותו שם ואותו סדר חיפוש כמו ה-open, ולכן אותו מודול; כשל מדווח ב-open.
    preloadWindowsLibrary(name);
    return DynamicLibrary.open(name);
  }
  if (Platform.isLinux) {
    return DynamicLibrary.open('libzstandard_linux_plugin.so');
  }
  if (Platform.isMacOS) {
    return DynamicLibrary.open('zstandard_macos.framework/zstandard_macos');
  }
  if (Platform.isIOS) {
    return DynamicLibrary.open('zstandard_ios.framework/zstandard_ios');
  }
  throw UnsupportedError('Platform not supported: ${Platform.operatingSystem}');
}

/// windowLogMax לפענוח: ארכיונים נדחסים עם `--long`/`--patch-from` וחלונם
/// גדול מברירת המחדל. ב-32 ביט zstd דוחה 31 — התקרה שם היא 30.
int zstdWindowLogMax([int? pointerSize]) =>
    (pointerSize ?? sizeOf<IntPtr>()) == 4 ? 30 : 31;

// הפלט נכתב אסינכרונית, וכל כתיבה עולה סבב הלוך-חזור ל-IO; חוצצים גדולים
// מהמומלץ של zstd (128KB) מצמצמים את מספר הכתיבות.
const zstdInputChunkBytes = 1 << 20;
const zstdOutputChunkBytes = 4 << 20;

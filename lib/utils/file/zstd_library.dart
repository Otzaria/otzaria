import 'dart:ffi';
import 'dart:io';

/// מחזיר את ה-DynamicLibrary של zstandard לפלטפורמה הנוכחית.
DynamicLibrary openZstandardLib() {
  if (Platform.isAndroid) {
    return DynamicLibrary.open('libzstandard_android.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('zstandard_windows.dll');
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

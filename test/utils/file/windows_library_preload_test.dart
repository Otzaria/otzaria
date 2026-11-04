import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/windows_library_preload.dart';

int _moduleHandle(String name) {
  final getModuleHandle = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<
        IntPtr Function(Pointer<Utf16>),
        int Function(Pointer<Utf16>)
      >('GetModuleHandleW');
  final native = name.toNativeUtf16();
  try {
    return getModuleHandle(native);
  } finally {
    malloc.free(native);
  }
}

void main() {
  test('ה-open אחרי הטעינה המוקדמת מקבל את אותו מודול, גם לפי שם בלבד', () {
    final temp = Directory.systemTemp.createTempSync('otzaria_preload_');
    addTearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } on FileSystemException {
        // ה-DLL טעון עד סוף התהליך.
      }
    });
    // שם ייחודי: איש בתהליך לא טען אותו לפני הבדיקה, והתיקייה אינה בנתיב החיפוש.
    final name = 'otz_preload_${DateTime.now().microsecondsSinceEpoch}.dll';
    final copy = File(
      '${Platform.environment['SystemRoot']}\\System32\\version.dll',
    ).copySync('${temp.path}\\$name');
    expect(_moduleHandle(name), 0);

    expect(preloadWindowsLibrary(copy.path), isTrue);

    final handle = _moduleHandle(name);
    expect(handle, isNot(0));
    expect(DynamicLibrary.open(name).handle.address, handle);
  }, skip: !Platform.isWindows ? 'LoadLibraryW קיים רק ב-Windows' : false);

  test(
    'כשל בטעינה מחזיר false',
    () => expect(preloadWindowsLibrary('otz_missing_module.dll'), isFalse),
    skip: !Platform.isWindows ? 'LoadLibraryW קיים רק ב-Windows' : false,
  );
}

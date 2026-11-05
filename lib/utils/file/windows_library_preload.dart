import 'dart:ffi';

import 'package:ffi/ffi.dart';

final _loadLibraryW = DynamicLibrary.open('kernel32.dll')
    .lookupFunction<
      IntPtr Function(Pointer<Utf16>),
      int Function(Pointer<Utf16>)
    >('LoadLibraryW');

/// `DynamicLibrary.open` אינו safepoint, וסריקת אנטי-וירוס בו עוצרת את ה-GC של כל ה-isolates;
/// `LoadLibraryW` ב-FFI כן. המודול נשאר טעון, וה-open אחריו חוזר מיד. false — הטעינה נכשלה.
bool preloadWindowsLibrary(String modulePath) {
  final path = modulePath.toNativeUtf16();
  try {
    return _loadLibraryW(path) != 0;
  } finally {
    malloc.free(path);
  }
}

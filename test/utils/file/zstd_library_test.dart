import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/zstd_library.dart';

void main() {
  test('windowLogMax הוא 30 ב-32 ביט ו-31 ב-64 ביט', () {
    expect(zstdWindowLogMax(4), 30);
    expect(zstdWindowLogMax(8), 31);
  });

  test('ברירת המחדל לפי גודל המצביע של התהליך', () {
    expect(zstdWindowLogMax(), zstdWindowLogMax(sizeOf<IntPtr>()));
  });
}

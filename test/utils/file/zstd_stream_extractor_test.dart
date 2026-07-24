import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/zstd_stream_extractor.dart';

/// מנסה לטעון את libzstd הסטנדרטי מהמערכת (לא ה-framework של Flutter), כדי
/// לאמת את לוגיקת ה-FFI בבדיקות. מחזיר null אם לא נמצא.
DynamicLibrary? _tryOpenSystemLibzstd() {
  const candidates = [
    '/opt/homebrew/lib/libzstd.dylib',
    '/usr/local/lib/libzstd.dylib',
    '/usr/lib/libzstd.dylib',
    'libzstd.so.1',
    'libzstd.so',
    '/usr/lib/x86_64-linux-gnu/libzstd.so.1',
    '/lib/x86_64-linux-gnu/libzstd.so.1',
  ];
  for (final path in candidates) {
    try {
      return DynamicLibrary.open(path);
    } catch (_) {}
  }
  return null;
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('zstd_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  // characterization: מחלץ patch אמיתי ומשווה ל-uncompressedSha256 מה-manifest.
  // משתמש ב-libzstd הסטנדרטי (ה-API זהה ל-bindings); מדלג אם אינו זמין.
  test(
    'decompress מחלץ patch-v1-v2.db.zst לפלט תקין (sha256)',
    () {
      const src = '/Users/david/Downloads/releases/v2/patch-v1-v2.db.zst';
      const expectedSha =
          'c02ccccd132e2b331e24ee60ca7886c4ee35b122d2b602d3690176e633c8ea05';
      if (!File(src).existsSync()) {
        markTestSkipped('קובץ ה-patch אינו זמין');
        return;
      }
      final lib = _tryOpenSystemLibzstd();
      if (lib == null) {
        markTestSkipped('libzstd אינו זמין במערכת');
        return;
      }
      final out = '${tmp.path}/extracted.db';
      ZstdStreamExtractor.decompressSyncForTest(src, out, lib);
      final hash = sha256.convert(File(out).readAsBytesSync()).toString();
      expect(hash, expectedSha);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('קובץ zst פגום נכשל ומוחק את הפלט החלקי', () {
    final lib = _tryOpenSystemLibzstd();
    if (lib == null) {
      markTestSkipped('libzstd אינו זמין במערכת');
      return;
    }
    final src = '${tmp.path}/corrupt.zst';
    File(src).writeAsBytesSync([0x28, 0xb5, 0x2f, 0xfd, 0x00, 0x01, 0x02]);
    final out = '${tmp.path}/out.db';
    expect(
      () => ZstdStreamExtractor.decompressSyncForTest(src, out, lib),
      throwsA(isA<Exception>()),
    );
    expect(File(out).existsSync(), isFalse); // הפלט החלקי נמחק
  });
}

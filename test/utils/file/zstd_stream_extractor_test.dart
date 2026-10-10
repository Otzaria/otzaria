import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/zstd_stream_extractor.dart';
import 'package:otzaria/utils/file/zstd_stream_extractor_io.dart';
import 'package:path/path.dart' as p;

import '../../empty_library/library_package_test_support.dart';
import '../../support/zstd_test_lib.dart';

void main() {
  late Directory tmp;
  final lib = openZstdForTests();
  final skip = lib == null ? 'libzstd אינו זמין' : null;
  setUp(() => tmp = Directory.systemTemp.createTempSync('zstd_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Uint8List payload(int size) => Uint8List.fromList(
    List.generate(size, (i) => (i * 31 + i ~/ 977) & 0xFF),
  );

  String writeZst(String name, List<Uint8List> frames) {
    final path = p.join(tmp.path, name);
    final bytes = BytesBuilder();
    for (final frame in frames) {
      bytes.add(zstdCompress(lib!, frame));
    }
    File(path).writeAsBytesSync(bytes.takeBytes());
    return path;
  }

  // characterization: מחלץ patch אמיתי ומשווה ל-uncompressedSha256 מה-manifest.
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
      final out = '${tmp.path}/extracted.db';
      decompressSyncForTest(src, out, lib!);
      final hash = sha256.convert(File(out).readAsBytesSync()).toString();
      expect(hash, expectedSha);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('מחלץ קובץ גדול מנתח קריאה אחד במדויק', () {
    final data = payload(3 * 1024 * 1024 + 123);
    final src = writeZst('big.zst', [data]);
    final out = p.join(tmp.path, 'out.db');
    File(out).writeAsStringSync('ישן — חייב להידרס');

    decompressSyncForTest(src, out, lib!);

    expect(File(out).readAsBytesSync(), data);
  }, skip: skip);

  test('קובץ של כמה frames נפרס במלואו', () {
    final a = payload(200000);
    final b = Uint8List.fromList(utf8.encode('frame שני' * 5000));
    final src = writeZst('multi.zst', [a, b]);
    final out = p.join(tmp.path, 'out.db');

    decompressSyncForTest(src, out, lib!);

    expect(File(out).readAsBytesSync(), [...a, ...b]);
  }, skip: skip);

  test('חריגה מ-maxOutputBytes זורקת ומוחקת את הפלט', () {
    final src = writeZst('big.zst', [payload(1 << 20)]);
    final out = p.join(tmp.path, 'out.db');

    expect(
      () => decompressSyncForTest(src, out, lib!, maxOutputBytes: 1000),
      throwsA(isA<ZstdOutputLimitExceeded>()),
    );
    expect(File(out).existsSync(), isFalse);
  }, skip: skip);

  test('פלט בדיוק בגודל maxOutputBytes מתקבל', () {
    final data = payload(5000);
    final src = writeZst('exact.zst', [data]);
    final out = p.join(tmp.path, 'out.db');

    decompressSyncForTest(src, out, lib!, maxOutputBytes: data.length);

    expect(File(out).lengthSync(), data.length);
  }, skip: skip);

  test('קובץ קטוע נכשל ומוחק את הפלט החלקי', () {
    final full = File(
      writeZst('full.zst', [payload(1 << 20)]),
    ).readAsBytesSync();
    final src = p.join(tmp.path, 'truncated.zst');
    File(src).writeAsBytesSync(full.sublist(0, full.length - 100));
    final out = p.join(tmp.path, 'out.db');

    expect(
      () => decompressSyncForTest(src, out, lib!),
      throwsA(isA<FormatException>()),
    );
    expect(File(out).existsSync(), isFalse);
  }, skip: skip);

  test('קובץ zst פגום נכשל ומוחק את הפלט החלקי', () {
    final src = '${tmp.path}/corrupt.zst';
    File(src).writeAsBytesSync([0x28, 0xb5, 0x2f, 0xfd, 0x00, 0x01, 0x02]);
    final out = '${tmp.path}/out.db';
    expect(
      () => decompressSyncForTest(src, out, lib!),
      throwsA(isA<Exception>()),
    );
    expect(File(out).existsSync(), isFalse);
  }, skip: skip);

  group('tar.zst', () {
    String writeTarZst(Map<String, List<int>> files, {List<String>? dirs}) {
      final tar = buildTar(files, dirs: dirs ?? const []);
      return writeZst('archive.tar.zst', [tar]);
    }

    test('פורס לתיקייה בלי קובץ tar זמני ליד הארכיון', () {
      final big = payload(2 * 1024 * 1024);
      final src = writeTarZst(
        {
          'תלמוד בבלי/ברכות.pdf': big,
          'תלמוד בבלי/שבת/דף ב.pdf': utf8.encode('דף'),
        },
        dirs: ['תלמוד בבלי/'],
      );
      final out = p.join(tmp.path, 'out');

      extractTarSyncForTest(src, out, lib!);

      expect(
        File(p.join(out, 'תלמוד בבלי', 'ברכות.pdf')).readAsBytesSync(),
        big,
      );
      expect(
        File(p.join(out, 'תלמוד בבלי', 'שבת', 'דף ב.pdf')).readAsStringSync(),
        'דף',
      );
      final leftovers = tmp
          .listSync()
          .whereType<File>()
          .map((f) => p.basename(f.path))
          .toList();
      expect(leftovers, ['archive.tar.zst']);
    }, skip: skip);

    test('קבצים בשורש הארכיון נפרסים', () {
      final src = writeTarZst({
        'a.txt': utf8.encode('א'),
        'dir/b.txt': utf8.encode('ב'),
      });
      final out = p.join(tmp.path, 'out');

      extractTarSyncForTest(src, out, lib!);

      expect(File(p.join(out, 'a.txt')).readAsStringSync(), 'א');
      expect(File(p.join(out, 'dir', 'b.txt')).readAsStringSync(), 'ב');
    }, skip: skip);

    test('נתיב שבורח מהיעד נדחה', () {
      final src = writeTarZst({'../evil.txt': utf8.encode('x')});
      final out = p.join(tmp.path, 'out');

      expect(
        () => extractTarSyncForTest(src, out, lib!),
        throwsA(isA<FormatException>()),
      );
      expect(File(p.join(tmp.path, 'evil.txt')).existsSync(), isFalse);
    }, skip: skip);

    test('tar.zst קטוע נכשל', () {
      final full = File(
        writeTarZst({'a.bin': payload(1 << 20)}),
      ).readAsBytesSync();
      final src = p.join(tmp.path, 'cut.tar.zst');
      File(src).writeAsBytesSync(full.sublist(0, full.length ~/ 2));

      expect(
        () => extractTarSyncForTest(src, p.join(tmp.path, 'out'), lib!),
        throwsA(isA<FormatException>()),
      );
    }, skip: skip);
  });
}

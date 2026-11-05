import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/tar_stream_extractor.dart';
import 'package:otzaria/utils/file/zstd_stream_extractor.dart';
import 'package:path/path.dart' as p;

import 'tar_stream_extractor_test.dart' show header, padded;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('tar_output_limit_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Uint8List withHardlink(int size) =>
      (BytesBuilder()
            ..add(header('source.bin', size))
            ..add(padded(Uint8List(size)))
            ..add(header('copy.bin', 0, type: 0x31, link: 'source.bin'))
            ..add(Uint8List(1024)))
          .takeBytes();

  test('hardlink copies count against the physical output limit', () async {
    const size = 2 << 20;
    final tar = TarStreamExtractor(
      tmp.path,
      rootFolder: null,
      maxOutputBytes: size + (size ~/ 2),
    );
    try {
      await expectLater(
        tar.add(withHardlink(size)),
        throwsA(isA<ZstdOutputLimitExceeded>()),
      );
    } finally {
      tar.abort();
    }
    expect(File(p.join(tmp.path, 'source.bin')).lengthSync(), size);
    expect(File(p.join(tmp.path, 'copy.bin')).existsSync(), isFalse);
  });

  test('exact physical output limit includes the copied hardlink', () async {
    const size = 2 << 20;
    final tar = TarStreamExtractor(
      tmp.path,
      rootFolder: null,
      maxOutputBytes: 2 * size,
    );
    await tar.add(withHardlink(size));
    tar.close();
    expect(File(p.join(tmp.path, 'source.bin')).lengthSync(), size);
    expect(File(p.join(tmp.path, 'copy.bin')).lengthSync(), size);
  });

  test(
    'cancellation stops within a large hardlink copy and closes it',
    () async {
      const size = 4 << 20;
      var reserved = 0;
      var cancelled = false;
      final failure = StateError('cancelled during hardlink copy');
      final tar = TarStreamExtractor(
        tmp.path,
        rootFolder: null,
        maxOutputBytes: 2 * size,
        checkCancelled: () {
          if (cancelled) throw failure;
        },
        onWrite: (bytes) {
          reserved += bytes;
          if (reserved > size) cancelled = true;
        },
      );
      try {
        await expectLater(tar.add(withHardlink(size)), throwsA(same(failure)));
      } finally {
        tar.abort();
      }
      final copied = File(p.join(tmp.path, 'copy.bin'));
      expect(cancelled, isTrue);
      expect(copied.lengthSync(), lessThan(size));
      await copied.delete();
      expect(File(p.join(tmp.path, 'source.bin')).lengthSync(), size);
    },
  );

  test('regular output never writes the chunk crossing its limit', () async {
    final tar = TarStreamExtractor(
      tmp.path,
      rootFolder: null,
      maxOutputBytes: 8,
    );
    try {
      await tar.add(header('limited.bin', 16));
      await tar.add(Uint8List(8));
      await expectLater(
        tar.add(Uint8List(8)),
        throwsA(isA<ZstdOutputLimitExceeded>()),
      );
    } finally {
      tar.abort();
    }
    expect(File(p.join(tmp.path, 'limited.bin')).lengthSync(), 8);
  });
}

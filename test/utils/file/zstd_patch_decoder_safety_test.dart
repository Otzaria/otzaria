import 'dart:io';
import 'dart:typed_data';

import 'package:otzaria/utils/file/zstd_patch_decoder.dart';
import 'package:otzaria/utils/file/zstd_stream_extractor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../empty_library/library_package_test_support.dart';
import '../../support/zstd_test_lib.dart';

void main() {
  final lib = openZstdForTests();
  late Directory directory;
  late File base;
  late File patch;
  late File output;
  final bytes = Uint8List.fromList(List.generate(4097, (i) => i & 255));

  setUp(() {
    directory = Directory.systemTemp.createTempSync('zstd_patch_safety_');
    base = File(p.join(directory.path, 'base.db'))..writeAsBytesSync(bytes);
    patch = File(p.join(directory.path, 'patch.zst'));
    if (lib != null) patch.writeAsBytesSync(zstdCompress(lib, bytes));
    output = File(p.join(directory.path, 'output.db'));
  });
  tearDown(() => directory.deleteSync(recursive: true));

  Future<void> decode({String? destination, int? limit, int cancel = 0}) =>
      decodePatchForTest(
        patch.path,
        base.path,
        destination ?? output.path,
        lib!,
        maxOutputBytes: limit ?? bytes.length,
        cancelAddress: cancel,
      );

  group('patch decoder source and output ownership', () {
    for (final aliasesBase in [false, true]) {
      test('output cannot alias ${aliasesBase ? 'base' : 'patch'}', () async {
        final source = aliasesBase ? base : patch;
        final original = source.readAsBytesSync();
        await expectLater(
          decode(destination: source.path),
          throwsA(isA<ArgumentError>()),
        );
        expect(source.readAsBytesSync(), original);
      });
    }

    test('output cannot alias a source through a symlink', () async {
      final alias = Link(p.join(directory.path, 'source-alias'));
      try {
        await alias.create(base.path);
      } on FileSystemException {
        markTestSkipped('Symbolic links are unavailable');
        return;
      }
      await expectLater(
        decode(destination: alias.path),
        throwsA(isA<ArgumentError>()),
      );
      expect(base.readAsBytesSync(), bytes);
      expect(await alias.exists(), isTrue);
    });

    test(
      'pre-cancel preserves an output that this call did not open',
      () async {
        await output.writeAsString('previous output');
        final flag = ZstdCancelFlag()..cancel();
        try {
          await expectLater(
            decode(cancel: flag.address),
            throwsA(isA<ZstdDecodeCancelled>()),
          );
        } finally {
          flag.dispose();
        }
        expect(await output.readAsString(), 'previous output');
        expect(base.readAsBytesSync(), bytes);
        expect(patch.existsSync(), isTrue);
      },
    );

    for (final missingBase in [false, true]) {
      test(
        'missing ${missingBase ? 'base' : 'patch'} preserves existing output',
        () async {
          await output.writeAsString('previous output');
          await (missingBase ? base : patch).delete();
          await expectLater(decode(), throwsA(anything));
          expect(await output.readAsString(), 'previous output');
        },
      );
    }
  }, skip: lib == null ? 'libzstd is unavailable' : false);

  group('patch decoder stream completeness and cap', () {
    test(
      'empty compressed input is rejected and partial output removed',
      () async {
        await patch.writeAsBytes(const []);
        await expectLater(decode(), throwsA(isA<FormatException>()));
        expect(output.existsSync(), isFalse);
        expect(base.readAsBytesSync(), bytes);
      },
    );

    test(
      'exact output limit succeeds and one-byte overflow removes output',
      () async {
        await decode();
        expect(await output.readAsBytes(), bytes);
        await output.delete();
        await expectLater(
          decode(limit: bytes.length - 1),
          throwsA(isA<ZstdOutputLimitExceeded>()),
        );
        expect(output.existsSync(), isFalse);
        expect(base.readAsBytesSync(), bytes);
        expect(patch.existsSync(), isTrue);
      },
    );

    test(
      'a truncated second frame cannot publish a complete first frame',
      () async {
        final first = zstdCompress(lib!, bytes);
        final second = zstdCompress(lib, Uint8List(8192));
        await patch.writeAsBytes([...first, ...second.take(second.length - 1)]);
        await expectLater(
          decode(limit: bytes.length + 8192),
          throwsA(isA<FormatException>()),
        );
        expect(output.existsSync(), isFalse);
        expect(base.readAsBytesSync(), bytes);
      },
    );
  }, skip: lib == null ? 'libzstd is unavailable' : false);
}

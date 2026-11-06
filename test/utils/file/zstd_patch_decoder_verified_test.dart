import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:otzaria/utils/file/zstd_library.dart';
import 'package:otzaria/utils/file/zstd_patch_decoder.dart';
import 'package:otzaria/utils/file/zstd_stream_extractor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:zstandard_native/zstandard_native_bindings.dart';

import '../../support/zstd_test_lib.dart';

/// Generates a real prefix-dependent frame with the codec API used by
/// `zstd --patch-from`; ordinary zstd compression cannot exercise the prefix.
Uint8List _prefixPatch(DynamicLibrary lib, Uint8List base, Uint8List target) {
  final codec = ZstandardNativeBindings(lib);
  final context = codec.ZSTD_createCCtx();
  final prefix = malloc<Uint8>(base.length);
  final source = malloc<Uint8>(target.length);
  final bound = codec.ZSTD_compressBound(target.length);
  final output = malloc<Uint8>(bound);
  void check(int result) {
    if (codec.ZSTD_isError(result) != 0) {
      throw StateError(
        codec.ZSTD_getErrorName(result).cast<Utf8>().toDartString(),
      );
    }
  }

  try {
    prefix.asTypedList(base.length).setAll(0, base);
    source.asTypedList(target.length).setAll(0, target);
    check(
      codec.ZSTD_CCtx_setParameter(
        context,
        ZSTD_cParameter.ZSTD_c_checksumFlag,
        1,
      ),
    );
    check(
      codec.ZSTD_CCtx_setParameter(
        context,
        ZSTD_cParameter.ZSTD_c_windowLog,
        21,
      ),
    );
    check(codec.ZSTD_CCtx_refPrefix(context, prefix.cast(), base.length));
    final count = codec.ZSTD_compress2(
      context,
      output.cast(),
      bound,
      source.cast(),
      target.length,
    );
    check(count);
    return Uint8List.fromList(output.asTypedList(count));
  } finally {
    codec.ZSTD_freeCCtx(context);
    malloc.free(prefix);
    malloc.free(source);
    malloc.free(output);
  }
}

void main() {
  final lib = openZstdForTests();
  String? skip;
  try {
    openZstandardLib();
  } catch (_) {
    skip = 'The packaged codec must be available to the production worker';
  }
  if (lib == null) skip = 'libzstd is unavailable';
  if (skip != null &&
      Platform.environment['OTZARIA_REQUIRE_PRODUCTION_CODEC_TESTS'] == '1') {
    throw StateError(skip);
  }

  late Directory directory;
  late File base;
  late File patch;
  late File output;
  late Uint8List baseBytes;
  late Uint8List target;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('zstd_prefix_verified_');
    final random = Random(131);
    baseBytes = Uint8List.fromList(
      List.generate(128 << 10, (_) => random.nextInt(256)),
    );
    target = Uint8List.fromList(baseBytes.sublist(16 << 10, 112 << 10));
    target.setRange(4096, 4100, [1, 2, 3, 4]);
    base = File(p.join(directory.path, 'base.db'));
    patch = File(p.join(directory.path, 'delta.zst'));
    output = File(p.join(directory.path, 'output.db'));
    await base.writeAsBytes(baseBytes);
    if (lib != null) {
      await patch.writeAsBytes(_prefixPatch(lib, baseBytes, target));
    }
  });
  tearDown(() => directory.delete(recursive: true));

  group('verified prefix patch production worker', () {
    test(
      'prefix-dependent frame has an inline digest and final progress',
      () async {
        // Random input makes a tiny frame possible only by using the old file.
        expect(await patch.length(), lessThan(target.length ~/ 4));
        final progress = <int>[];
        final result = await decodePatchVerifiedToFile(
          patch.path,
          base.path,
          output.path,
          maxOutputBytes: target.length,
          onProgress: progress.add,
        );
        expect(await output.readAsBytes(), target);
        expect(result.bytesWritten, target.length);
        expect(result.sha256, sha256.convert(target).toString());
        expect(progress, isNotEmpty);
        expect(progress.last, target.length);
        expect(await base.readAsBytes(), baseBytes);
        expect(await patch.exists(), isTrue);

        // Confirm this is not accidentally an ordinary standalone zstd fixture.
        await expectLater(
          ZstdStreamExtractor.extractVerifiedToFile(
            patch.path,
            p.join(directory.path, 'without-prefix.db'),
            maxOutputBytes: target.length,
          ),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test('final progress observer failure removes the output', () async {
      final failure = StateError('final patch observer failed');
      await expectLater(
        decodePatchVerifiedToFile(
          patch.path,
          base.path,
          output.path,
          maxOutputBytes: target.length,
          onProgress: (written) {
            if (written == target.length) throw failure;
          },
        ),
        throwsA(same(failure)),
      );
      expect(await output.exists(), isFalse);
      expect(await base.readAsBytes(), baseBytes);
      expect(await patch.exists(), isTrue);
    });

    test(
      'cancellation in final progress drains the worker and removes output',
      () async {
        final flag = ZstdCancelFlag();
        var requested = false;
        try {
          await expectLater(
            decodePatchVerifiedToFile(
              patch.path,
              base.path,
              output.path,
              maxOutputBytes: target.length,
              cancelAddress: flag.address,
              onProgress: (written) {
                if (written == target.length) {
                  requested = true;
                  flag.cancel();
                }
              },
            ),
            throwsA(isA<ZstdDecodeCancelled>()),
          );
        } finally {
          flag.dispose();
        }
        expect(requested, isTrue);
        expect(await output.exists(), isFalse);
        expect(await base.readAsBytes(), baseBytes);
        expect(await patch.exists(), isTrue);
      },
    );
  }, skip: skip ?? false);
}

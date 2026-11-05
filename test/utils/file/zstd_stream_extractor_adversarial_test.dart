import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:otzaria/utils/file/zstd_library.dart';
import 'package:otzaria/utils/file/zstd_stream_extractor.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:test/test.dart';

import '../../empty_library/library_package_test_support.dart';
import '../../support/zstd_test_lib.dart';

void main() {
  final compressionLib = openZstdForTests();
  String? skip;
  try {
    openZstandardLib();
  } catch (_) {
    skip = 'The packaged zstd loader must be available to the worker isolate';
  }
  if (compressionLib == null) skip = 'libzstd is unavailable';
  if (skip != null &&
      Platform.environment['OTZARIA_REQUIRE_PRODUCTION_CODEC_TESTS'] == '1') {
    throw StateError(skip);
  }

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('zstd_adversarial_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String writeFrames(String name, List<Uint8List> frames) {
    final file = File(p.join(tmp.path, name));
    final out = file.openSync(mode: FileMode.write);
    try {
      for (final frame in frames) {
        out.writeFromSync(zstdCompress(compressionLib!, frame));
      }
    } finally {
      out.closeSync();
    }
    return file.path;
  }

  Future<FileExtractionResult> extract(
    String source,
    String output,
    int limit, {
    void Function(int)? onProgress,
    bool Function()? isCancelled,
  }) => ZstdStreamExtractor.extractVerifiedToFile(
    source,
    output,
    maxOutputBytes: limit,
    onProgress: onProgress,
    isCancelled: isCancelled,
  );

  group('production worker completion and cleanup', () {
    test(
      'cancellation at final output progress removes the closed output',
      () async {
        final bytes = Uint8List.fromList(List.generate(1024, (i) => i & 255));
        final source = writeFrames('last.zst', [bytes]);
        final output = p.join(tmp.path, 'out.db');
        var cancelled = false;
        await expectLater(
          extract(
            source,
            output,
            bytes.length,
            onProgress: (written) {
              if (written == bytes.length) cancelled = true;
            },
            isCancelled: () => cancelled,
          ),
          throwsA(isA<PatchDownloadCancelled>()),
        );
        expect(cancelled, isTrue);
        expect(File(output).existsSync(), isFalse);
        expect(File(source).existsSync(), isTrue);
      },
    );

    test('a final progress callback failure does not leave output', () async {
      final bytes = Uint8List(8192);
      final source = writeFrames('callback.zst', [bytes]);
      final output = p.join(tmp.path, 'out.db');
      final failure = StateError('observer failed after output');
      await expectLater(
        extract(
          source,
          output,
          bytes.length,
          onProgress: (written) {
            if (written == bytes.length) throw failure;
          },
        ),
        throwsA(same(failure)),
      );
      expect(File(output).existsSync(), isFalse);
    });

    test(
      'cancellation callback failure closes the worker before cleanup',
      () async {
        final bytes = Uint8List(16 << 20);
        final source = writeFrames('cancel-callback.zst', [bytes]);
        final output = p.join(tmp.path, 'out.db');
        var wrote = false;
        final failure = StateError('cancellation observer failed');
        await expectLater(
          extract(
            source,
            output,
            bytes.length,
            onProgress: (written) => wrote = wrote || written > 0,
            isCancelled: () {
              if (wrote) throw failure;
              return false;
            },
          ),
          throwsA(same(failure)),
        );
        expect(wrote, isTrue);
        expect(File(output).existsSync(), isFalse);
      },
    );

    test(
      'one compressed read expanding to many output chunks can cancel',
      () async {
        final source = writeFrames('compressible.zst', [Uint8List(64 << 20)]);
        expect(File(source).lengthSync(), lessThan(zstdInputChunkBytes));
        final output = p.join(tmp.path, 'out.db');
        var cancelled = false;
        var progressCalls = 0;
        await expectLater(
          extract(
            source,
            output,
            64 << 20,
            onProgress: (written) {
              progressCalls++;
              if (written >= zstdOutputChunkBytes) cancelled = true;
            },
            isCancelled: () => cancelled,
          ),
          throwsA(isA<PatchDownloadCancelled>()),
        );
        expect(cancelled, isTrue);
        expect(progressCalls, greaterThan(1));
        expect(File(output).existsSync(), isFalse);
      },
    );
  }, skip: skip);

  group('production worker integrity', () {
    test(
      'exact output limit succeeds and streamed digest matches disk',
      () async {
        final bytes = Uint8List(2 * zstdOutputChunkBytes + 17);
        for (var i = 0; i < bytes.length; i += 997) {
          bytes[i] = i & 255;
        }
        final source = writeFrames('exact.zst', [bytes]);
        final output = p.join(tmp.path, 'out.db');
        final progress = <int>[];
        final result = await extract(
          source,
          output,
          bytes.length,
          onProgress: progress.add,
        );
        expect(result.bytesWritten, bytes.length);
        expect(result.sha256, sha256.convert(bytes).toString());
        expect(
          result.sha256,
          (await File(output).openRead().transform(sha256).first).toString(),
        );
        expect(progress, orderedEquals(progress.toList()..sort()));
        expect(progress.first, 0);
        expect(progress.last, bytes.length);
      },
    );

    test(
      'one byte above output limit rejects before any excess write',
      () async {
        final size = 2 * zstdOutputChunkBytes + 17;
        final source = writeFrames('over.zst', [Uint8List(size)]);
        final output = p.join(tmp.path, 'out.db');
        final reported = <int>[];
        await expectLater(
          extract(source, output, size - 1, onProgress: reported.add),
          throwsA(isA<ZstdOutputLimitExceeded>()),
        );
        expect(reported.every((written) => written <= size - 1), isTrue);
        expect(File(output).existsSync(), isFalse);
      },
    );

    test(
      'truncation after a complete frame still rejects all output',
      () async {
        final bytes = Uint8List(5 << 20);
        final first = zstdCompress(compressionLib!, bytes);
        final second = zstdCompress(compressionLib, bytes);
        final source = File(p.join(tmp.path, 'tail-cut.zst'));
        source.writeAsBytesSync([...first, ...second.take(second.length - 1)]);
        final output = p.join(tmp.path, 'out.db');
        await expectLater(
          extract(source.path, output, 2 * bytes.length),
          throwsA(isA<FormatException>()),
        );
        expect(File(output).existsSync(), isFalse);
      },
    );

    test(
      'tar hardlinks count physical copies toward the output limit',
      () async {
        const payloadBytes = 1 << 20;
        final tar = BytesBuilder()
          ..add(_tarHeader('original.bin', payloadBytes))
          ..add(Uint8List(payloadBytes))
          ..add(_tarHeader('copy.bin', 0, link: 'original.bin'))
          ..add(Uint8List(1024));
        const limit = payloadBytes + (payloadBytes ~/ 2);
        final tarBytes = tar.takeBytes();
        expect(tarBytes.length, lessThan(limit));
        final source = writeFrames('hardlinks.tar.zst', [tarBytes]);
        final rejected = Directory(p.join(tmp.path, 'rejected'))..createSync();
        await expectLater(
          ZstdStreamExtractor.extractTarToDir(
            source,
            rejected.path,
            maxOutputBytes: limit,
          ),
          throwsA(isA<ZstdOutputLimitExceeded>()),
        );
        final written = rejected
            .listSync(recursive: true)
            .whereType<File>()
            .fold<int>(0, (sum, file) => sum + file.lengthSync());
        expect(written, lessThanOrEqualTo(limit));
        expect(File(source).existsSync(), isTrue);

        final exact = Directory(p.join(tmp.path, 'exact'))..createSync();
        await ZstdStreamExtractor.extractTarToDir(
          source,
          exact.path,
          maxOutputBytes: 2 * payloadBytes,
        );
        expect(
          File(p.join(exact.path, 'original.bin')).lengthSync(),
          payloadBytes,
        );
        expect(File(p.join(exact.path, 'copy.bin')).lengthSync(), payloadBytes);
      },
    );

    test(
      'source and output aliases are rejected without touching source',
      () async {
        final source = writeFrames('source.zst', [Uint8List(4096)]);
        final original = File(source).readAsBytesSync();
        await expectLater(
          extract(source, source, 4096),
          throwsArgumentError,
        );
        expect(File(source).readAsBytesSync(), original);
        if (!Platform.isWindows) {
          final alias = p.join(tmp.path, 'source-link.zst');
          Link(alias).createSync(source);
          await expectLater(extract(source, alias, 4096), throwsArgumentError);
          expect(File(source).readAsBytesSync(), original);
        }
      },
    );

    test(
      'pre-cancel and invalid limit leave an existing output untouched',
      () async {
        final source = writeFrames('source.zst', [Uint8List(4096)]);
        final output = File(p.join(tmp.path, 'existing.db'))
          ..writeAsStringSync('keep');
        await expectLater(
          extract(source, output.path, 4096, isCancelled: () => true),
          throwsA(isA<PatchDownloadCancelled>()),
        );
        expect(output.readAsStringSync(), 'keep');
        await expectLater(
          extract(source, output.path, -1),
          throwsArgumentError,
        );
        expect(output.readAsStringSync(), 'keep');
      },
    );
  }, skip: skip);
}

Uint8List _tarHeader(String name, int size, {String? link}) {
  final header = Uint8List(512);
  header.setAll(0, ascii.encode(name));
  if (link != null) header.setAll(157, ascii.encode(link));
  void octal(int offset, int length, int value) => header.setAll(
    offset,
    ascii.encode('${value.toRadixString(8).padLeft(length - 1, '0')}\u0000'),
  );
  octal(100, 8, 420);
  octal(124, 12, size);
  octal(136, 12, 0);
  header[156] = link == null ? 0x30 : 0x31;
  header.setAll(257, ascii.encode('ustar\u000000'));
  header.fillRange(148, 156, 0x20);
  final sum = header.fold<int>(0, (a, b) => a + b);
  header.setAll(
    148,
    ascii.encode('${sum.toRadixString(8).padLeft(6, '0')}\u0000 '),
  );
  return header;
}

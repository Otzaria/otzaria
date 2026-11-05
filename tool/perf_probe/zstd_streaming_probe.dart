import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:otzaria/utils/file/zstd_library.dart';
import 'package:otzaria/utils/file/zstd_stream_extractor.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:zstandard_native/zstandard_native_bindings.dart';

const _frameBytes = 8 << 20;

Future<void> main(List<String> args) async {
  if (args.length < 2 ||
      !['prepare', 'inline', 'two-pass', 'cancel'].contains(args.first)) {
    stderr.writeln(
      'Usage: prepare DIR [MiB...] | inline|two-pass|cancel MANIFEST [cancelAfterBytes]',
    );
    exitCode = 64;
    return;
  }
  if (args.first == 'prepare') {
    await _prepare(Directory(args[1]), args.skip(2).map(int.parse).toList());
    return;
  }
  final manifestFile = File(args[1]).absolute;
  final manifest =
      jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
  final source = p.join(manifestFile.parent.path, manifest['file'] as String);
  final expectedBytes = manifest['bytes'] as int;
  final expectedSha = manifest['sha256'] as String;
  final mode = args.first;
  final output = '$source.probe-$pid.db';
  final baselineRss = ProcessInfo.currentRss;
  final watch = Stopwatch()..start();
  final cancelWatch = Stopwatch();
  var cancelled = false;
  var lastReported = 0;
  final cancelAfter = args.length > 2
      ? int.parse(args[2])
      : zstdOutputChunkBytes;
  try {
    FileExtractionResult? result;
    if (mode == 'two-pass') {
      await ZstdStreamExtractor.extractToFile(
        source,
        output,
        maxOutputBytes: expectedBytes,
      );
      final digest = await _hashInWorker(output);
      result = FileExtractionResult(
        bytesWritten: await File(output).length(),
        sha256: digest,
      );
    } else {
      try {
        result = await ZstdStreamExtractor.extractVerifiedToFile(
          source,
          output,
          maxOutputBytes: expectedBytes,
          isCancelled: mode == 'cancel' ? () => cancelled : null,
          onProgress: (written) {
            lastReported = written;
            if (mode == 'cancel' && !cancelled && written >= cancelAfter) {
              cancelled = true;
              cancelWatch.start();
            }
          },
        );
      } on PatchDownloadCancelled {
        if (mode != 'cancel') rethrow;
      }
    }
    watch.stop();
    cancelWatch.stop();
    if (mode == 'cancel') {
      if (!cancelled || result != null || await File(output).exists()) {
        throw StateError('Cancellation did not remove the staged output');
      }
    } else if (result?.bytesWritten != expectedBytes ||
        result?.sha256 != expectedSha) {
      throw StateError('Output verification failed');
    }
    stdout.writeln(
      jsonEncode({
        'mode': mode,
        'outputBytes': expectedBytes,
        'compressedBytes': await File(source).length(),
        'elapsedMs': watch.elapsedMicroseconds / 1000,
        'baselineRssBytes': baselineRss,
        'peakRssBytes': ProcessInfo.maxRss,
        'lastReportedOutputBytes': lastReported,
        if (mode == 'cancel')
          'cancelMs': cancelWatch.elapsedMicroseconds / 1000,
        'verified': true,
        'fixtureFrameBytes': manifest['frameBytes'],
        'inputChunkBytes': zstdInputChunkBytes,
        'outputChunkBytes': zstdOutputChunkBytes,
        'nativeWindowLogMax': zstdWindowLogMax(),
        'zstdVersionNumber': ZstandardNativeBindings(
          openZstandardLib(),
        ).ZSTD_versionNumber(),
        'runtime': Platform.version,
      }),
    );
  } finally {
    if (await File(output).exists()) await File(output).delete();
  }
}

Future<String> _hashInWorker(String path) => Isolate.run(() => _hashFile(path));

Future<String> _hashFile(String path) async {
  final input = await File(path).open();
  final hasher = Sha256Stream();
  final buffer = Uint8List(1 << 20);
  try {
    while (true) {
      final read = await input.readInto(buffer);
      if (read == 0) break;
      hasher.addSlice(buffer, 0, read);
    }
    return hasher.close();
  } finally {
    hasher.dispose();
    await input.close();
  }
}

// Preparation runs in a separate process so fixture allocations cannot affect peak RSS.
Future<void> _prepare(Directory dir, List<int> sizesMiB) async {
  await dir.create(recursive: true);
  if (sizesMiB.isEmpty) sizesMiB = [64, 512];
  final frame = Uint8List(_frameBytes);
  for (var i = 0; i < frame.length; i++) {
    frame[i] = ((i % 65521) * 31 + (i % 65521) ~/ 113) & 255;
  }
  final compressed = _compress(frame);
  for (final mib in sizesMiB) {
    final bytes = mib << 20;
    if (mib <= 0 || bytes % _frameBytes != 0) {
      throw ArgumentError('Fixture MiB must be positive multiples of 8');
    }
    final name = 'zstd-$mib-mib.zst';
    final file = File(p.join(dir.path, name));
    final output = await file.open(mode: FileMode.write);
    final hash = Sha256Stream();
    try {
      for (var written = 0; written < bytes; written += _frameBytes) {
        await output.writeFrom(compressed);
        hash.add(frame);
      }
      await output.flush();
      final manifest = {
        'file': name,
        'bytes': bytes,
        'sha256': hash.close(),
        'frameBytes': _frameBytes,
        'description':
            'Concatenated identical checked zstd frames with a bounded native window',
      };
      final manifestFile = File('${file.path}.json');
      await manifestFile.writeAsString(jsonEncode(manifest));
      stdout.writeln(manifestFile.absolute.path);
    } finally {
      hash.dispose();
      await output.close();
    }
  }
}

Uint8List _compress(Uint8List bytes) {
  final zstd = ZstandardNativeBindings(openZstandardLib());
  final context = zstd.ZSTD_createCCtx();
  if (context == nullptr) throw StateError('ZSTD_createCCtx failed');
  Pointer<Uint8> input = nullptr;
  Pointer<Uint8> output = nullptr;
  try {
    final capacity = zstd.ZSTD_compressBound(bytes.length);
    input = malloc<Uint8>(bytes.length);
    output = malloc<Uint8>(capacity);
    input.asTypedList(bytes.length).setAll(0, bytes);
    final set = zstd.ZSTD_CCtx_setParameter(
      context,
      ZSTD_cParameter.ZSTD_c_checksumFlag,
      1,
    );
    if (zstd.ZSTD_isError(set) != 0)
      throw StateError('ZSTD checksum configuration failed');
    final size = zstd.ZSTD_compress2(
      context,
      output.cast(),
      capacity,
      input.cast(),
      bytes.length,
    );
    if (zstd.ZSTD_isError(size) != 0) throw StateError('ZSTD_compress2 failed');
    return Uint8List.fromList(output.asTypedList(size));
  } finally {
    if (output != nullptr) malloc.free(output);
    if (input != nullptr) malloc.free(input);
    zstd.ZSTD_freeCCtx(context);
  }
}

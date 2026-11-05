/// מחיל תיקון `zstd --patch-from` בזרימה: הקובץ הישן ממופה לזיכרון ומוזן
/// כ-prefix ל-ZSTD, והתוצאה נכתבת ישירות לדיסק בנתחים.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:otzaria/utils/file/mapped_file.dart';
import 'package:otzaria/utils/file/zstd_library.dart';
import 'package:otzaria/utils/file/zstd_stream_extractor.dart';
import 'package:zstandard_native/zstandard_native_bindings.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

/// הפענוח נעצר לבקשת המשתמש; הפלט החלקי נמחק.
class ZstdDecodeCancelled implements Exception {
  const ZstdDecodeCancelled();

  @override
  String toString() => 'ZstdDecodeCancelled';
}

/// דגל ביטול משותף בין isolates. תא בזיכרון נייטיב ולא פורט: הלולאה בודקת
/// אותו בכל נתח, בלי לחכות להודעה בלולאת האירועים.
class ZstdCancelFlag {
  ZstdCancelFlag() : _cell = calloc<Uint8>();

  final Pointer<Uint8> _cell;

  /// לשליחה אל ה-isolate שמפענח.
  int get address => _cell.address;

  void cancel() => _cell.value = 1;

  /// חובה לקרוא רק אחרי שהפענוח הסתיים.
  void dispose() => calloc.free(_cell);
}

/// Applies a prefix patch in a worker, retaining the historical void API.
Future<void> decodePatchToFile(
  String patchPath,
  String basePath,
  String outputPath, {
  int? maxOutputBytes,
  int cancelAddress = 0,
}) async {
  await _runPatch(
    patchPath,
    basePath,
    outputPath,
    maxOutputBytes,
    cancelAddress,
    hashOutput: false,
  );
}

/// File-to-file extraction with a digest of the bytes actually written.
Future<FileExtractionResult> decodePatchVerifiedToFile(
  String patchPath,
  String basePath,
  String outputPath, {
  required int maxOutputBytes,
  int cancelAddress = 0,
  void Function(int bytesWritten)? onProgress,
}) => _runPatch(
  patchPath,
  basePath,
  outputPath,
  maxOutputBytes,
  cancelAddress,
  hashOutput: true,
  onProgress: onProgress,
);

Future<FileExtractionResult> _runPatch(
  String patchPath,
  String basePath,
  String outputPath,
  int? maxOutputBytes,
  int cancelAddress, {
  required bool hashOutput,
  void Function(int)? onProgress,
}) async {
  final ownFlag = cancelAddress == 0 ? ZstdCancelFlag() : null;
  final address = ownFlag?.address ?? cancelAddress;
  final cell = Pointer<Uint8>.fromAddress(address);
  final events = ReceivePort();
  final drained = Completer<void>();
  Object? callbackError;
  StackTrace? callbackStack;
  final subscription = events.listen((message) {
    if (message == null) {
      if (!drained.isCompleted) drained.complete();
    } else if (message is int && callbackError == null) {
      try {
        onProgress?.call(message);
      } catch (error, stack) {
        callbackError = error;
        callbackStack = stack;
        cell.value = 1;
      }
    }
  });
  var completed = false;
  try {
    final outcome = await _spawnPatch(
      patchPath,
      basePath,
      outputPath,
      maxOutputBytes,
      address,
      hashOutput,
      events.sendPort,
    );
    await drained.future;
    completed = outcome.$2 == null;
    if (callbackError != null) {
      Error.throwWithStackTrace(callbackError!, callbackStack!);
    }
    if (outcome.$2 != null) {
      Error.throwWithStackTrace(outcome.$2!, outcome.$3!);
    }
    if (cell.value != 0) throw const ZstdDecodeCancelled();
    return outcome.$1!;
  } catch (_) {
    // A cancellation raised by the last progress event is still a failure.
    if (completed) {
      try {
        await File(outputPath).delete();
      } on FileSystemException {
        /* original error */
      }
    }
    rethrow;
  } finally {
    await subscription.cancel();
    events.close();
    ownFlag?.dispose();
  }
}

// Only sendable arguments are captured, never the observer or ReceivePort.
Future<(FileExtractionResult?, Object?, StackTrace?)> _spawnPatch(
  String patchPath,
  String basePath,
  String outputPath,
  int? maxOutputBytes,
  int cancelAddress,
  bool hashOutput,
  SendPort progress,
) => Isolate.run(() async {
  try {
    final result = await _decodeWithLib(
      patchPath,
      basePath,
      outputPath,
      openZstandardLib(),
      maxOutputBytes,
      cancelAddress,
      hashOutput: hashOutput,
      onProgress: progress.send,
    );
    return (result, null, null);
  } catch (error, stack) {
    return (null, error, stack);
  } finally {
    progress.send(null);
  }
});

/// Runs the actual codec with an injected native library for tests.
Future<void> decodePatchForTest(
  String patchPath,
  String basePath,
  String outputPath,
  DynamicLibrary lib, {
  int? maxOutputBytes,
  int cancelAddress = 0,
}) async {
  await _decodeWithLib(
    patchPath,
    basePath,
    outputPath,
    lib,
    maxOutputBytes,
    cancelAddress,
    hashOutput: false,
  );
}

Future<FileExtractionResult> _decodeWithLib(
  String patchPath,
  String basePath,
  String outputPath,
  DynamicLibrary dylib,
  int? maxOutputBytes,
  int cancelAddress, {
  required bool hashOutput,
  void Function(int)? onProgress,
}) async {
  if (maxOutputBytes != null && maxOutputBytes < 0) {
    throw ArgumentError.value(maxOutputBytes, 'maxOutputBytes');
  }
  final cancelCell = cancelAddress == 0
      ? nullptr
      : Pointer<Uint8>.fromAddress(cancelAddress);
  void checkCancelled() {
    if (cancelCell != nullptr && cancelCell.value != 0) {
      throw const ZstdDecodeCancelled();
    }
  }

  checkCancelled();
  await _ensureDistinctOutput(patchPath, outputPath);
  await _ensureDistinctOutput(basePath, outputPath);
  checkCancelled();

  final bindings = ZstandardNativeBindings(dylib);
  Pointer<ZSTD_DCtx> dctx = nullptr;
  Pointer<Uint8> inNative = nullptr;
  Pointer<Uint8> outNative = nullptr;
  Pointer<ZSTD_inBuffer_s> inBuf = nullptr;
  Pointer<ZSTD_outBuffer_s> outBuf = nullptr;
  MappedFile? base;
  RandomAccessFile? input;
  Sha256Stream? hasher;
  var ownsOutput = false;
  try {
    // Validate/open both sources before removing an existing staging output.
    input = await File(patchPath).open();
    base = MappedFile.open(basePath);
    dctx = bindings.ZSTD_createDCtx();
    if (dctx == nullptr) throw StateError('ZSTD_createDCtx failed');
    void check(int code, String operation, {bool decoding = false}) {
      if (bindings.ZSTD_isError(code) == 0) return;
      final message = bindings.ZSTD_getErrorName(
        code,
      ).cast<Utf8>().toDartString();
      final error = bindings.ZSTD_getErrorCode(code);
      if (!decoding ||
          error == ZSTD_ErrorCode.ZSTD_error_memory_allocation ||
          error == ZSTD_ErrorCode.ZSTD_error_frameParameter_windowTooLarge) {
        throw StateError('$operation: $message');
      }
      throw FormatException('$operation: $message');
    }

    check(bindings.ZSTD_initDStream(dctx), 'ZSTD_initDStream');
    check(
      bindings.ZSTD_DCtx_setParameter(
        dctx,
        ZSTD_dParameter.ZSTD_d_windowLogMax,
        zstdWindowLogMax(),
      ),
      'windowLogMax',
    );
    check(
      bindings.ZSTD_DCtx_refPrefix(dctx, base.data.cast(), base.length),
      'refPrefix',
    );
    inNative = malloc.allocate<Uint8>(zstdInputChunkBytes);
    outNative = malloc.allocate<Uint8>(zstdOutputChunkBytes);
    inBuf = malloc<ZSTD_inBuffer_s>();
    outBuf = malloc<ZSTD_outBuffer_s>();
    if (hashOutput) hasher = Sha256Stream();
    checkCancelled();
    final output = await File(outputPath).open(mode: FileMode.write);
    ownsOutput = true;
    try {
      final inputView = inNative.asTypedList(zstdInputChunkBytes);
      var totalWritten = 0;
      var totalRead = 0;
      var lastRet = 0;
      while (true) {
        checkCancelled();
        final bytesRead = await input.readInto(inputView);
        if (bytesRead == 0) break;
        totalRead += bytesRead;
        inBuf.ref.src = inNative.cast();
        inBuf.ref.size = bytesRead;
        inBuf.ref.pos = 0;
        var drain = false;
        do {
          checkCancelled();
          outBuf.ref.dst = outNative.cast();
          outBuf.ref.size = zstdOutputChunkBytes;
          outBuf.ref.pos = 0;
          lastRet = bindings.ZSTD_decompressStream(dctx, outBuf, inBuf);
          check(lastRet, 'ZSTD_decompressStream', decoding: true);
          checkCancelled();
          final count = outBuf.ref.pos;
          if (maxOutputBytes != null && count > maxOutputBytes - totalWritten) {
            throw ZstdOutputLimitExceeded(maxOutputBytes);
          }
          if (count > 0) {
            final bytes = outNative.asTypedList(count);
            await output.writeFrom(bytes);
            hasher?.add(bytes);
            totalWritten += count;
            onProgress?.call(totalWritten);
            checkCancelled();
          }
          drain = lastRet != 0 && count == zstdOutputChunkBytes;
        } while (inBuf.ref.pos < inBuf.ref.size || drain);
      }
      if (totalRead == 0 || lastRet != 0) {
        throw const FormatException('Incomplete or empty zstd patch');
      }
      await output.flush();
      checkCancelled();
      return FileExtractionResult(
        bytesWritten: totalWritten,
        sha256: hasher?.close() ?? '',
      );
    } finally {
      await output.close();
    }
  } catch (_) {
    if (ownsOutput) {
      try {
        await File(outputPath).delete();
      } on FileSystemException {
        /* original error */
      }
    }
    rethrow;
  } finally {
    try {
      await input?.close();
    } finally {
      base?.unmap();
      hasher?.dispose();
      malloc.free(inNative);
      malloc.free(outNative);
      malloc.free(inBuf);
      malloc.free(outBuf);
      if (dctx != nullptr) bindings.ZSTD_freeDCtx(dctx);
    }
  }
}

Future<void> _ensureDistinctOutput(String sourcePath, String outputPath) async {
  var same = p.equals(
    p.normalize(p.absolute(sourcePath)),
    p.normalize(p.absolute(outputPath)),
  );
  if (!same &&
      await File(sourcePath).exists() &&
      await File(outputPath).exists()) {
    final source = await File(sourcePath).resolveSymbolicLinks();
    final output = await File(outputPath).resolveSymbolicLinks();
    same =
        p.equals(source, output) ||
        await FileSystemEntity.identical(source, output);
  }
  if (same) {
    throw ArgumentError('Patch input/base and output must be distinct files');
  }
}

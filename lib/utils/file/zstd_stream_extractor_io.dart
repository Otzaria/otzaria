import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:otzaria/utils/file/tar_stream_extractor.dart';
import 'package:otzaria/utils/file/zstd_library.dart';
import 'package:otzaria/utils/file/zstd_stream_decoder.dart';
import 'package:otzaria/utils/file/zstd_stream_extractor.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

Future<void> extractToFile(
  String archivePath,
  String outputPath, {
  void Function(double progress)? onProgress,
  int? maxOutputBytes,
  bool Function()? isCancelled,
}) async {
  await _runWithProgress(
    onProgress: onProgress,
    isCancelled: isCancelled,
    cleanupCompleted: () => File(outputPath).delete(),
    runInIsolate: (port) =>
        _fileInIsolate(archivePath, outputPath, port, maxOutputBytes, false),
  );
}

Future<FileExtractionResult> extractVerifiedToFile(
  String archivePath,
  String outputPath, {
  required int maxOutputBytes,
  bool Function()? isCancelled,
  void Function(int bytesWritten)? onProgress,
}) => _runWithProgress(
  onBytesWritten: onProgress,
  isCancelled: isCancelled,
  cleanupCompleted: () => File(outputPath).delete(),
  runInIsolate: (port) =>
      _fileInIsolate(archivePath, outputPath, port, maxOutputBytes, true),
);

// רק פרמטרים הניתנים להעברה נלכדים ב-closure של ה-isolate.
Future<_WorkerOutcome<FileExtractionResult>> _fileInIsolate(
  String archivePath,
  String outputPath,
  SendPort progress,
  int? maxOutputBytes,
  bool hashOutput,
) => Isolate.run(
  () => _workerOutcome(
    progress,
    () => _decompressWithLib(
      archivePath,
      outputPath,
      openZstandardLib(),
      progressPort: progress,
      maxOutputBytes: maxOutputBytes,
      hashOutput: hashOutput,
    ),
  ),
);

Future<void> extractTarToDir(
  String archivePath,
  String outputDir, {
  void Function(double progress)? onProgress,
  int? maxOutputBytes,
  bool Function()? isCancelled,
}) => _runWithProgress(
  onProgress: onProgress,
  isCancelled: isCancelled,
  runInIsolate: (port) =>
      _tarInIsolate(archivePath, outputDir, port, maxOutputBytes),
);

Future<_WorkerOutcome<void>> _tarInIsolate(
  String archivePath,
  String outputDir,
  SendPort progress,
  int? maxOutputBytes,
) => Isolate.run(
  () => _workerOutcome(
    progress,
    () => _extractTarWithLib(
      archivePath,
      outputDir,
      openZstandardLib(),
      progressPort: progress,
      maxOutputBytes: maxOutputBytes,
    ),
  ),
);

const _progressComplete = 'zstd.progress.complete';

class _WorkerOutcome<T> {
  const _WorkerOutcome({this.result, this.error, this.stack});
  final T? result;
  final Object? error;
  final StackTrace? stack;
}

Future<_WorkerOutcome<T>> _workerOutcome<T>(
  SendPort progress,
  Future<T> Function() action,
) async {
  try {
    return _WorkerOutcome(result: await action());
  } catch (error, stack) {
    return _WorkerOutcome(error: error, stack: stack);
  } finally {
    // ה-sentinel נשלח באותו ערוץ, ולכן מגיע אחרי כל עדכוני ההתקדמות.
    progress.send(_progressComplete);
  }
}

Future<T> _runWithProgress<T>({
  void Function(double)? onProgress,
  void Function(int)? onBytesWritten,
  bool Function()? isCancelled,
  required Future<_WorkerOutcome<T>> Function(SendPort) runInIsolate,
  Future<void> Function()? cleanupCompleted,
}) async {
  _throwIfCancelled(isCancelled);
  final progressPort = ReceivePort();
  final progressDrained = Completer<void>();
  SendPort? cancelPort;
  var cancelled = false;
  Object? callbackError;
  StackTrace? callbackStack;

  void checkCancellation() {
    try {
      cancelled = cancelled || (isCancelled?.call() ?? false);
    } catch (error, stack) {
      callbackError ??= error;
      callbackStack ??= stack;
      cancelled = true;
    }
    if (cancelled) cancelPort?.send(null);
  }

  final sub = progressPort.listen((message) {
    if (message == _progressComplete) {
      progressDrained.complete();
    } else if (message is SendPort) {
      cancelPort = message;
    } else if (callbackError == null && !cancelled) {
      try {
        if (message is double) onProgress?.call(message);
        if (message is int) onBytesWritten?.call(message);
      } catch (error, stack) {
        callbackError = error;
        callbackStack = stack;
        cancelled = true;
      }
    }
    checkCancellation();
  });
  final timer = isCancelled == null
      ? null
      : Timer.periodic(
          const Duration(milliseconds: 20),
          (_) => checkCancellation(),
        );
  var completed = false;
  try {
    final outcome = await runInIsolate(progressPort.sendPort);
    completed = outcome.error == null;
    // כשל spawn/העברת outcome נזרק לפני ההמתנה, בלי sentinel שלא יגיע.
    await progressDrained.future;
    if (callbackError != null) {
      Error.throwWithStackTrace(callbackError!, callbackStack!);
    }
    if (outcome.error != null) {
      Error.throwWithStackTrace(outcome.error!, outcome.stack!);
    }
    if (cancelled) throw const PatchDownloadCancelled();
    _throwIfCancelled(isCancelled);
    return outcome.result as T;
  } catch (_) {
    if (completed && cleanupCompleted != null) {
      try {
        await cleanupCompleted();
      } on FileSystemException {
        // משמרים את הכשל המקורי אם גם הניקוי נכשל.
      }
    }
    if (callbackError != null) {
      Error.throwWithStackTrace(callbackError!, callbackStack!);
    }
    rethrow;
  } finally {
    timer?.cancel();
    await sub.cancel();
    progressPort.close();
  }
}

Future<FileExtractionResult> decompressForTest(
  String archivePath,
  String outputPath,
  DynamicLibrary lib, {
  int? maxOutputBytes,
  bool Function()? isCancelled,
  void Function(int)? onBytesWritten,
  bool hashOutput = false,
}) => _decompressWithLib(
  archivePath,
  outputPath,
  lib,
  maxOutputBytes: maxOutputBytes,
  isCancelled: isCancelled,
  onBytesWritten: onBytesWritten,
  hashOutput: hashOutput,
);

Future<void> extractTarForTest(
  String archivePath,
  String outputDir,
  DynamicLibrary lib, {
  int? maxOutputBytes,
  bool Function()? isCancelled,
}) => _extractTarWithLib(
  archivePath,
  outputDir,
  lib,
  maxOutputBytes: maxOutputBytes,
  isCancelled: isCancelled,
);

Future<FileExtractionResult> _decompressWithLib(
  String archivePath,
  String outputPath,
  DynamicLibrary dylib, {
  SendPort? progressPort,
  int? maxOutputBytes,
  bool Function()? isCancelled,
  void Function(int)? onBytesWritten,
  bool hashOutput = false,
}) async {
  if (maxOutputBytes != null && maxOutputBytes < 0) {
    throw ArgumentError.value(maxOutputBytes, 'maxOutputBytes');
  }
  _throwIfCancelled(isCancelled);
  final outFile = File(outputPath);
  if (p.equals(p.absolute(archivePath), p.absolute(outputPath)) ||
      (await outFile.exists() &&
          await FileSystemEntity.identical(
            await File(archivePath).resolveSymbolicLinks(),
            await outFile.resolveSymbolicLinks(),
          ))) {
    throw ArgumentError('מקור החילוץ ויעד החילוץ חייבים להיות קבצים שונים');
  }
  final cancellation = _WorkerCancellation(progressPort, isCancelled);
  Sha256Stream? hasher;
  var ownsOutput = false;
  try {
    hasher = hashOutput ? Sha256Stream() : null;
    cancellation.check();
    final outputRaf = await outFile.open(mode: FileMode.writeOnly);
    ownsOutput = true;
    var totalWritten = 0;
    try {
      progressPort?.send(0);
      onBytesWritten?.call(0);
      await _decodeFile(archivePath, dylib, progressPort, (output) async {
        cancellation.check();
        if (maxOutputBytes != null &&
            output.length > maxOutputBytes - totalWritten) {
          throw ZstdOutputLimitExceeded(maxOutputBytes);
        }
        await outputRaf.writeFrom(output);
        hasher?.add(output);
        totalWritten += output.length;
        progressPort?.send(totalWritten);
        onBytesWritten?.call(totalWritten);
        cancellation.check();
      }, checkCancelled: cancellation.check);
      await outputRaf.flush();
      cancellation.check();
      return FileExtractionResult(
        bytesWritten: totalWritten,
        sha256: hasher?.close() ?? '',
      );
    } finally {
      await outputRaf.close();
    }
  } catch (_) {
    if (ownsOutput) {
      try {
        await outFile.delete();
      } on FileSystemException {
        // שגיאת החילוץ המקורית נשמרת גם אם מערכת הקבצים מסרבת לניקוי.
      }
    }
    rethrow;
  } finally {
    hasher?.dispose();
    cancellation.close();
  }
}

Future<void> _extractTarWithLib(
  String archivePath,
  String outputDir,
  DynamicLibrary dylib, {
  SendPort? progressPort,
  int? maxOutputBytes,
  bool Function()? isCancelled,
}) async {
  if (maxOutputBytes != null && maxOutputBytes <= 0) {
    throw ArgumentError.value(maxOutputBytes, 'maxOutputBytes');
  }
  final cancellation = _WorkerCancellation(progressPort, isCancelled);
  final tar = TarStreamExtractor(
    outputDir,
    rootFolder: null,
    maxOutputBytes: maxOutputBytes ?? kDefaultMaxExtractedBytes,
    checkCancelled: cancellation.check,
  );
  var totalWritten = 0;
  try {
    await _decodeFile(archivePath, dylib, progressPort, (output) async {
      cancellation.check();
      if (maxOutputBytes != null &&
          output.length > maxOutputBytes - totalWritten) {
        throw ZstdOutputLimitExceeded(maxOutputBytes);
      }
      totalWritten += output.length;
      await tar.add(output);
      cancellation.check();
    }, checkCancelled: cancellation.check);
    tar.close();
  } finally {
    tar.abort();
    cancellation.close();
  }
}

class _WorkerCancellation {
  _WorkerCancellation(SendPort? progress, this.isCancelled) {
    if (progress != null) {
      final port = _port = ReceivePort();
      port.listen((_) => _cancelled = true);
      progress.send(port.sendPort);
    }
  }

  final bool Function()? isCancelled;
  ReceivePort? _port;
  bool _cancelled = false;

  void check() {
    if (_cancelled) throw const PatchDownloadCancelled();
    _throwIfCancelled(isCancelled);
  }

  void close() => _port?.close();
}

void _throwIfCancelled(bool Function()? isCancelled) {
  if (isCancelled?.call() ?? false) throw const PatchDownloadCancelled();
}

Future<void> _decodeFile(
  String archivePath,
  DynamicLibrary dylib,
  SendPort? progressPort,
  Future<void> Function(Uint8List output) onOutput, {
  required void Function() checkCancelled,
}) async {
  checkCancelled();
  final decoder = ZstdStreamDecoder(dylib);
  RandomAccessFile? inputRaf;
  try {
    inputRaf = await File(archivePath).open();
    final totalBytes = await inputRaf.length();
    final buffer = Uint8List(zstdInputChunkBytes);
    var totalRead = 0;
    var lastReported = 0.0;
    while (true) {
      checkCancelled();
      final bytesRead = await inputRaf.readInto(buffer);
      checkCancelled();
      if (bytesRead == 0) break;
      totalRead += bytesRead;
      await decoder.add(Uint8List.sublistView(buffer, 0, bytesRead), onOutput);
      if (progressPort != null && totalBytes > 0) {
        final progress = totalRead / totalBytes;
        if (progress - lastReported >= 0.01) {
          lastReported = progress;
          progressPort.send(progress);
        }
      }
    }
    decoder.close();
    checkCancelled();
  } finally {
    decoder.dispose();
    await inputRaf?.close();
  }
}

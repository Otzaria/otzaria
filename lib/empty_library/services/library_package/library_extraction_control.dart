import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:otzaria/utils/file/zstd_patch_decoder.dart';
import 'package:otzaria/utils/file/zstd_stream_extractor.dart';

/// הפריסה נעצרה לבקשת המשתמש.
class LibraryImportCancelled implements Exception {
  const LibraryImportCancelled();

  @override
  String toString() => 'הייבוא בוטל';
}

/// סופר את כל הפלט המפוענח, לרבות כותרות tar, לפני העברתו לכותב.
class LibraryExtractionBudget {
  LibraryExtractionBudget(this.maxOutputBytes, {this.isCancelled}) {
    if (maxOutputBytes <= 0) {
      throw ArgumentError.value(maxOutputBytes, 'maxOutputBytes');
    }
  }

  final int maxOutputBytes;
  final bool Function()? isCancelled;
  int bytesWritten = 0;

  void checkCancelled() {
    if (isCancelled?.call() ?? false) throw const LibraryImportCancelled();
  }

  void reserve(int bytes) {
    checkCancelled();
    if (bytes > maxOutputBytes - bytesWritten) {
      throw ZstdOutputLimitExceeded(maxOutputBytes);
    }
    bytesWritten += bytes;
  }

  Future<void> write(
    Uint8List bytes,
    Future<void> Function(Uint8List) write,
  ) async {
    reserve(bytes.length);
    await write(bytes);
    checkCancelled();
  }
}

void checkLibraryImportCancelled(ZstdCancelFlag cancel) {
  if (Pointer<Uint8>.fromAddress(cancel.address).value != 0) {
    throw const LibraryImportCancelled();
  }
}

const _progressComplete = 'library.extraction.complete';

class LibraryExtractionWorkerOutcome {
  const LibraryExtractionWorkerOutcome({this.error, this.stack});
  final Object? error;
  final StackTrace? stack;
}

/// ה-sentinel נשלח רק לאחר סגירת כל הקבצים ומשאבי המפענח.
Future<LibraryExtractionWorkerOutcome> completeLibraryExtractionWorker(
  SendPort progress,
  Future<void> Function() action,
) async {
  try {
    await action();
    return const LibraryExtractionWorkerOutcome();
  } catch (error, stack) {
    return LibraryExtractionWorkerOutcome(error: error, stack: stack);
  } finally {
    progress.send(_progressComplete);
  }
}

/// מנקז דיווחים וממתין ל-worker גם כש-observer נכשל או מבטל בדיווח האחרון.
Future<void> runLibraryExtractionWithProgress({
  required Future<LibraryExtractionWorkerOutcome> Function(SendPort) run,
  required void Function(List<dynamic>) onProgress,
  required ZstdCancelFlag cancel,
}) async {
  final cancelled = Pointer<Uint8>.fromAddress(cancel.address);
  if (cancelled.value != 0) throw const LibraryImportCancelled();
  final port = ReceivePort();
  final drained = Completer<void>();
  Object? callbackError;
  StackTrace? callbackStack;
  final sub = port.listen((message) {
    if (message == _progressComplete) {
      drained.complete();
    } else if (message is List && callbackError == null) {
      try {
        onProgress(message);
      } catch (error, stack) {
        callbackError = error;
        callbackStack = stack;
        cancel.cancel();
      }
    }
  });
  try {
    final outcome = await run(port.sendPort);
    await drained.future;
    if (callbackError != null) {
      Error.throwWithStackTrace(callbackError!, callbackStack!);
    }
    if (outcome.error != null) {
      Error.throwWithStackTrace(outcome.error!, outcome.stack!);
    }
    if (cancelled.value != 0) throw const LibraryImportCancelled();
  } finally {
    await sub.cancel();
    port.close();
  }
}

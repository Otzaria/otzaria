import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/empty_library/services/library_package/library_package_extractor.dart';
import 'package:otzaria/empty_library/services/library_package/library_source.dart';
import 'package:otzaria/utils/file/tar_stream_extractor.dart';
import 'package:otzaria/utils/file/zstd_library.dart';
import 'package:otzaria/utils/file/zstd_patch_decoder.dart';
import 'package:otzaria/utils/file/zstd_stream_decoder.dart';
import 'package:otzaria/utils/move_directory.dart';
import 'package:path/path.dart' as p;

/// פריסת נכסים גולמיים אל [destination] (תיקיית staging): כל נכס נכתב בשמו
/// בתיקיית הספרים, ישירות מהזרם — בלי עותק ביניים ובלי חיבור חלקים לקובץ.
class RawAssetJob {
  const RawAssetJob({required this.assets, required this.destination});

  final List<RawLibraryAsset> assets;
  final String destination;
}

/// [done] ו-[total] הם בייטים שנקראו מהמקור, בכל הנכסים יחד.
typedef RawAssetProgress =
    void Function(LibraryComponent component, int done, int total);

typedef RawAssetRunner =
    Future<void> Function(
      RawAssetJob job, {
      required RawAssetProgress onProgress,
      required ZstdCancelFlag cancel,
    });

/// מריץ את [job] ב-isolate נפרד; ביטול דרך [cancel] נבדק בין נתחים.
Future<void> runRawAssetJobInIsolate(
  RawAssetJob job, {
  required RawAssetProgress onProgress,
  required ZstdCancelFlag cancel,
  DynamicLibrary Function() openZstd = openZstandardLib,
}) async {
  final token = job.assets.any((a) => a.folder.usesPlatformChannel)
      ? RootIsolateToken.instance
      : null;
  final port = ReceivePort();
  final sub = port.listen((message) {
    if (message is List && message.length == 3) {
      onProgress(
        LibraryComponent.values[message[0] as int],
        message[1] as int,
        message[2] as int,
      );
    }
  });
  try {
    await _runIsolated(job, token, port.sendPort, cancel.address, openZstd);
  } finally {
    await sub.cancel();
    port.close();
  }
}

// פונקציה נפרדת: closure בהיקף שמחזיק את onProgress היה מעתיק אותו ל-isolate.
Future<void> _runIsolated(
  RawAssetJob job,
  RootIsolateToken? token,
  SendPort sendPort,
  int cancelAddress,
  DynamicLibrary Function() openZstd,
) => Isolate.run(() async {
  if (token != null) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  }
  final cancelCell = Pointer<Uint8>.fromAddress(cancelAddress);
  await extractRawAssetJob(
    job,
    openZstd: openZstd,
    isCancelled: () => cancelCell.value != 0,
    onProgress: (component, done, total) =>
        sendPort.send([component.index, done, total]),
  );
});

/// גוף העבודה, גם לבדיקות בלי isolate. מדווח בכל אחוז או 8MB.
/// libzstd נטען רק כשיש נכס דחוס.
Future<void> extractRawAssetJob(
  RawAssetJob job, {
  required DynamicLibrary Function() openZstd,
  required RawAssetProgress onProgress,
  bool Function()? isCancelled,
}) async {
  final total = job.assets.fold<int>(0, (sum, a) => sum + a.size);
  final step = (total ~/ 100).clamp(1, 8 << 20);
  var done = 0;
  var reported = 0;
  DynamicLibrary? zstd;
  for (final asset in job.assets) {
    if (isCancelled?.call() ?? false) throw const LibraryImportCancelled();
    onProgress(asset.component, done, total);
    await _extractAsset(
      asset,
      job.destination,
      zstd: () => zstd ??= openZstd(),
      isCancelled: isCancelled,
      onBytes: (bytes) {
        done += bytes;
        if (done - reported >= step) {
          reported = done;
          onProgress(asset.component, done, total);
        }
      },
    );
  }
  if (isCancelled?.call() ?? false) throw const LibraryImportCancelled();
  if (job.assets.isNotEmpty) {
    onProgress(job.assets.last.component, total, total);
  }
}

Future<void> _extractAsset(
  RawLibraryAsset asset,
  String destination, {
  required DynamicLibrary Function() zstd,
  required void Function(int bytes) onBytes,
  bool Function()? isCancelled,
}) async {
  final target = p.join(destination, asset.targetName);
  switch (asset.format) {
    case RawAssetFormat.directory:
      await copyDirectoryEntries(
        asset.directoryPath!,
        target,
        checkCancelled: () {
          if (isCancelled?.call() ?? false) {
            throw const LibraryImportCancelled();
          }
        },
      );
    case RawAssetFormat.plain:
      final out = File(target).openSync(mode: FileMode.write);
      try {
        await _streamParts(asset, out.writeFromSync, onBytes, isCancelled);
      } finally {
        out.closeSync();
      }
    case RawAssetFormat.zstd:
      final out = File(target).openSync(mode: FileMode.write);
      final decoder = ZstdStreamDecoder(zstd());
      try {
        await _streamParts(
          asset,
          (chunk) => decoder.add(chunk, out.writeFromSync),
          onBytes,
          isCancelled,
        );
        decoder.close();
      } finally {
        decoder.dispose();
        out.closeSync();
      }
    case RawAssetFormat.tarZstd:
      final decoder = ZstdStreamDecoder(zstd());
      final tar = TarStreamExtractor(destination, rootFolder: asset.targetName);
      try {
        final digest = await _streamParts(
          asset,
          (chunk) => decoder.add(chunk, tar.add),
          onBytes,
          isCancelled,
          wholeDigest: true,
        );
        decoder.close();
        tar.close();
        // בדיקת העדכונים משווה את ה-digest מול ה-release.
        await File(
          DatabaseConstants.talmudBavliVersionFilePath(target),
        ).writeAsString(digest!);
      } finally {
        tar.abort();
        decoder.dispose();
      }
  }
}

/// קורא את חלקי [asset] לפי הסדר אל [consume], עם אימות גודל ו-SHA-256 לכל
/// חלק ולשלם כשידועים. מחזיר את ה-SHA-256 של השלם כש-[wholeDigest].
Future<String?> _streamParts(
  RawLibraryAsset asset,
  void Function(List<int> chunk) consume,
  void Function(int bytes) onBytes,
  bool Function()? isCancelled, {
  bool wholeDigest = false,
}) async {
  final whole = AccumulatorSink<Digest>();
  final wholeInput = wholeDigest || asset.sha256 != null
      ? sha256.startChunkedConversion(whole)
      : null;
  for (final part in asset.parts) {
    final partDigest = AccumulatorSink<Digest>();
    final partInput = part.sha256 == null
        ? null
        : sha256.startChunkedConversion(partDigest);
    Object? consumeError;
    StackTrace? consumeStack;
    var read = 0;
    await for (final chunk in asset.folder.openRead(part.entry)) {
      if (isCancelled?.call() ?? false) throw const LibraryImportCancelled();
      partInput?.add(chunk);
      wholeInput?.add(chunk);
      read += chunk.length;
      // חלק פגום מפיל קודם את הפענוח; ממשיכים לחשב hash עד סוף החלק כדי
      // לדווח איזה חלק פגום, ולא שגיאת zstd סתמית.
      if (consumeError == null) {
        try {
          consume(chunk);
        } on FormatException catch (error, stack) {
          if (partInput == null) rethrow;
          consumeError = error;
          consumeStack = stack;
        }
      }
      onBytes(chunk.length);
    }
    if (read != part.size) {
      throw FormatException('הקובץ ${part.name} אינו בגודל הצפוי');
    }
    if (partInput != null) {
      partInput.close();
      if (partDigest.events.single.toString() != part.sha256) {
        throw FormatException('הקובץ ${part.name} פגום (SHA-256 אינו תואם)');
      }
    }
    if (consumeError != null) {
      Error.throwWithStackTrace(consumeError, consumeStack!);
    }
  }
  if (wholeInput == null) return null;
  wholeInput.close();
  final digest = whole.events.single.toString();
  if (asset.sha256 != null && digest != asset.sha256) {
    throw FormatException('${asset.sourceName} פגום (SHA-256 אינו תואם)');
  }
  return digest;
}

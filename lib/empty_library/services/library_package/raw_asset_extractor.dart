import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/empty_library/services/library_package/library_extraction_control.dart';
import 'package:otzaria/empty_library/services/library_package/library_source.dart';
import 'package:otzaria/utils/file/tar_stream_extractor.dart';
import 'package:otzaria/utils/file/zstd_library.dart';
import 'package:otzaria/utils/file/zstd_patch_decoder.dart';
import 'package:otzaria/utils/file/zstd_stream_decoder.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart'
    show kDefaultMaxExtractedBytes;

/// פריסת נכסים גולמיים אל [destination] (תיקיית staging): כל נכס נכתב בשמו
/// בתיקיית הספרים, ישירות מהזרם — בלי עותק ביניים ובלי חיבור חלקים לקובץ.
class RawAssetJob {
  const RawAssetJob({
    required this.assets,
    required this.destination,
    this.maxOutputBytes = kDefaultMaxExtractedBytes,
  });

  final List<RawLibraryAsset> assets;
  final String destination;
  final int maxOutputBytes;
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
  await runLibraryExtractionWithProgress(
    cancel: cancel,
    run: (port) => _runIsolated(job, token, port, cancel.address, openZstd),
    onProgress: (message) {
      onProgress(
        LibraryComponent.values[message[0] as int],
        message[1] as int,
        message[2] as int,
      );
    },
  );
}

// פונקציה נפרדת: closure בהיקף שמחזיק את onProgress היה מעתיק אותו ל-isolate.
Future<LibraryExtractionWorkerOutcome> _runIsolated(
  RawAssetJob job,
  RootIsolateToken? token,
  SendPort sendPort,
  int cancelAddress,
  DynamicLibrary Function() openZstd,
) => Isolate.run(
  () => completeLibraryExtractionWorker(sendPort, () async {
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
  }),
);

/// גוף העבודה, גם לבדיקות בלי isolate. מדווח בכל אחוז או 8MB.
/// libzstd נטען רק כשיש נכס דחוס.
Future<void> extractRawAssetJob(
  RawAssetJob job, {
  required DynamicLibrary Function() openZstd,
  required RawAssetProgress onProgress,
  bool Function()? isCancelled,
}) async {
  final budget = LibraryExtractionBudget(
    job.maxOutputBytes,
    isCancelled: isCancelled,
  )..checkCancelled();
  var total = 0;
  for (final asset in job.assets) {
    budget.checkCancelled();
    total += asset.format == RawAssetFormat.directory
        ? await _directorySize(asset.directoryPath!, budget)
        : asset.size;
  }
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
      budget: budget,
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
  budget.checkCancelled();
}

Future<void> _extractAsset(
  RawLibraryAsset asset,
  String destination, {
  required DynamicLibrary Function() zstd,
  required void Function(int bytes) onBytes,
  required LibraryExtractionBudget budget,
  bool Function()? isCancelled,
}) async {
  final target = p.join(destination, asset.targetName);
  switch (asset.format) {
    case RawAssetFormat.directory:
      await _copyDirectory(asset.directoryPath!, target, budget, onBytes);
    case RawAssetFormat.plain:
      final out = File(target).openSync(mode: FileMode.write);
      try {
        await _streamParts(
          asset,
          (chunk) => budget.write(_asBytes(chunk), out.writeFrom),
          onBytes,
          isCancelled,
        );
        await out.flush();
        budget.checkCancelled();
      } finally {
        out.closeSync();
      }
    case RawAssetFormat.zstd:
      final decoder = ZstdStreamDecoder(zstd());
      var reportedInput = 0;
      void reportInput() {
        final consumed = decoder.inputBytesConsumed;
        final delta = consumed - reportedInput;
        reportedInput = consumed;
        if (delta > 0) onBytes(delta);
        budget.checkCancelled();
      }
      RandomAccessFile? out;
      try {
        final output = out = await File(target).open(mode: FileMode.write);
        await _streamParts(
          asset,
          (chunk) async {
            await decoder.add(chunk, (bytes) async {
              await budget.write(bytes, output.writeFrom);
              reportInput();
            });
            reportInput();
          },
          onBytes,
          isCancelled,
          reportedInputBytes: () => reportedInput,
        );
        decoder.close();
        await output.flush();
        budget.checkCancelled();
      } finally {
        decoder.dispose();
        await out?.close();
      }
    case RawAssetFormat.tarZstd:
      final decoder = ZstdStreamDecoder(zstd());
      var reportedInput = 0;
      void reportInput() {
        final consumed = decoder.inputBytesConsumed;
        final delta = consumed - reportedInput;
        reportedInput = consumed;
        if (delta > 0) onBytes(delta);
        budget.checkCancelled();
      }
      final decodedBudget = LibraryExtractionBudget(
        budget.maxOutputBytes,
        isCancelled: isCancelled,
      );
      final tar = TarStreamExtractor(
        destination,
        rootFolder: asset.targetName,
        maxOutputBytes: budget.maxOutputBytes,
        checkCancelled: budget.checkCancelled,
        onWrite: budget.reserve,
      );
      try {
        final digest = await _streamParts(
          asset,
          (chunk) async {
            await decoder.add(chunk, (bytes) async {
              await decodedBudget.write(bytes, tar.add);
              reportInput();
            });
            reportInput();
          },
          onBytes,
          isCancelled,
          wholeDigest: true,
          reportedInputBytes: () => reportedInput,
        );
        decoder.close();
        budget.checkCancelled();
        tar.close();
        // בדיקת העדכונים משווה את ה-digest מול ה-release.
        await File(
          DatabaseConstants.talmudBavliVersionFilePath(target),
        ).writeAsString(digest!);
        budget.checkCancelled();
      } finally {
        tar.abort();
        decoder.dispose();
      }
  }
}

Uint8List _asBytes(List<int> bytes) =>
    bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

Future<void> _copyDirectory(
  String source,
  String target,
  LibraryExtractionBudget budget,
  void Function(int) onBytes,
) async {
  budget.checkCancelled();
  await Directory(target).create(recursive: true);
  await for (final entity in Directory(source).list(followLinks: false)) {
    budget.checkCancelled();
    final destination = p.join(target, p.basename(entity.path));
    if (entity is Directory) {
      await _copyDirectory(entity.path, destination, budget, onBytes);
    } else if (entity is File) {
      if (await FileSystemEntity.type(destination, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw FormatException(
          'היעד כבר מכיל קובץ בשם ${p.basename(destination)}',
        );
      }
      final expectedSize = await entity.length();
      final output = await File(destination).open(mode: FileMode.write);
      try {
        var copied = 0;
        await for (final chunk in entity.openRead()) {
          if (chunk.length > expectedSize - copied) {
            throw FormatException(
              'קובץ המקור השתנה בזמן ההעתקה: ${entity.path}',
            );
          }
          await budget.write(_asBytes(chunk), output.writeFrom);
          copied += chunk.length;
          onBytes(chunk.length);
          budget.checkCancelled();
        }
        if (copied != expectedSize) {
          throw FormatException('קובץ המקור השתנה בזמן ההעתקה: ${entity.path}');
        }
        await output.flush();
        budget.checkCancelled();
      } finally {
        await output.close();
      }
    } else if (entity is Link) {
      await Link(destination).create(await entity.target());
    }
  }
  budget.checkCancelled();
}

Future<int> _directorySize(
  String directory,
  LibraryExtractionBudget budget,
) async {
  var size = 0;
  await for (final entity in Directory(
    directory,
  ).list(recursive: true, followLinks: false)) {
    budget.checkCancelled();
    if (entity is File) size += await entity.length();
  }
  budget.checkCancelled();
  return size;
}

/// קורא את חלקי [asset] לפי הסדר אל [consume], עם אימות גודל ו-SHA-256 לכל
/// חלק ולשלם כשידועים. מחזיר את ה-SHA-256 של השלם כש-[wholeDigest].
Future<String?> _streamParts(
  RawLibraryAsset asset,
  Future<void> Function(List<int> chunk) consume,
  void Function(int bytes) onBytes,
  bool Function()? isCancelled, {
  bool wholeDigest = false,
  int Function()? reportedInputBytes,
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
      if (chunk.length > part.size - read) {
        throw FormatException('הקובץ ${part.name} גדול מהגודל הצפוי');
      }
      partInput?.add(chunk);
      wholeInput?.add(chunk);
      read += chunk.length;
      // חלק פגום מפיל קודם את הפענוח; ממשיכים לחשב hash עד סוף החלק כדי
      // לדווח איזה חלק פגום, ולא שגיאת zstd סתמית.
      final alreadyReported = reportedInputBytes?.call() ?? 0;
      if (consumeError == null) {
        try {
          await consume(chunk);
        } on FormatException catch (error, stack) {
          if (partInput == null) rethrow;
          consumeError = error;
          consumeStack = stack;
        }
      }
      final duringConsume = (reportedInputBytes?.call() ?? 0) - alreadyReported;
      final unreported = chunk.length - duringConsume;
      if (unreported > 0) onBytes(unreported);
      if (isCancelled?.call() ?? false) throw const LibraryImportCancelled();
    }
    if (isCancelled?.call() ?? false) throw const LibraryImportCancelled();
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

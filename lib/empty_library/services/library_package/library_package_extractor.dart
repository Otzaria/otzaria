import 'dart:ffi';
import 'dart:isolate';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/empty_library/services/library_package/library_extraction_control.dart';
import 'package:otzaria/empty_library/services/library_package/library_package.dart';
import 'package:otzaria/empty_library/services/library_package/package_folder.dart';
import 'package:otzaria/utils/file/tar_stream_extractor.dart';
import 'package:otzaria/utils/file/zstd_library.dart';
import 'package:otzaria/utils/file/zstd_patch_decoder.dart';
import 'package:otzaria/utils/file/zstd_stream_decoder.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart'
    show kDefaultMaxExtractedBytes;

export 'library_extraction_control.dart' show LibraryImportCancelled;

/// פורס את [package] אל [destination] בזרימה אחת: קריאת החלקים לפי הסדר,
/// SHA-256 של כל חלק ושל השלם, פענוח zstd ופריסת tar — בלי ארכיון ביניים.
/// התוצאה היא `destination/<books|index>/…`; בכשל נשארת פריסה חלקית שהקורא מוחק.
Future<void> extractLibraryPackage({
  required LibraryPackage package,
  required PackageFolder folder,
  required String destination,
  required DynamicLibrary zstd,
  void Function(int bytesRead)? onBytes,
  bool Function()? isCancelled,
  int maxOutputBytes = kDefaultMaxExtractedBytes,
}) async {
  final budget = LibraryExtractionBudget(
    maxOutputBytes,
    isCancelled: isCancelled,
  )..checkCancelled();
  final decoder = ZstdStreamDecoder(
    zstd,
    requireContentChecksum: !package.hasManifest,
  );
  final tar = TarStreamExtractor(
    destination,
    rootFolder: package.kind.rootFolder,
    maxOutputBytes: maxOutputBytes,
    checkCancelled: budget.checkCancelled,
  );
  var reportedInput = 0;
  void reportInput() {
    final consumed = decoder.inputBytesConsumed;
    final delta = consumed - reportedInput;
    reportedInput = consumed;
    if (delta > 0) onBytes?.call(delta);
    budget.checkCancelled();
  }

  final wholeDigest = AccumulatorSink<Digest>();
  final wholeInput = package.hasManifest
      ? sha256.startChunkedConversion(wholeDigest)
      : null;
  try {
    for (final part in package.parts) {
      final partDigest = AccumulatorSink<Digest>();
      final partInput = part.sha256 == null
          ? null
          : sha256.startChunkedConversion(partDigest);
      Object? decodeError;
      StackTrace? decodeStack;
      var read = 0;
      await for (final chunk in folder.openRead(part.entry)) {
        budget.checkCancelled();
        if (chunk.length > part.size - read) {
          throw FormatException('החלק ${part.name} גדול מהגודל הצפוי');
        }
        partInput?.add(chunk);
        wholeInput?.add(chunk);
        read += chunk.length;
        // חלק פגום מפיל קודם את הפענוח; ממשיכים לחשב hash עד סוף החלק כדי
        // לדווח איזה חלק פגום, ולא שגיאת zstd סתמית.
        final alreadyReported = reportedInput;
        if (decodeError == null) {
          try {
            await decoder.add(chunk, (bytes) async {
              await budget.write(bytes, tar.add);
              reportInput();
            });
            reportInput();
          } on FormatException catch (error, stack) {
            if (partInput == null) rethrow;
            decodeError = error;
            decodeStack = stack;
          }
        }
        final unreported = chunk.length - (reportedInput - alreadyReported);
        if (unreported > 0) onBytes?.call(unreported);
        budget.checkCancelled();
      }
      if (read != part.size) {
        throw FormatException('החלק ${part.name} אינו בגודל הצפוי');
      }
      if (partInput != null) {
        partInput.close();
        if (partDigest.events.single.toString() != part.sha256) {
          throw FormatException('החלק ${part.name} פגום (SHA-256 אינו תואם)');
        }
      }
      if (decodeError != null) {
        Error.throwWithStackTrace(decodeError, decodeStack!);
      }
    }
    decoder.close();
    budget.checkCancelled();
    tar.close();
    if (wholeInput != null) {
      wholeInput.close();
      if (wholeDigest.events.single.toString() != package.sha256) {
        throw FormatException(
          '${package.archiveName} פגום (SHA-256 אינו תואם)',
        );
      }
    }
    budget.checkCancelled();
  } finally {
    tar.abort();
    decoder.dispose();
  }
}

/// פריסת הספרייה ואופציונלית האינדקס, כל אחד אל תיקיית staging משלו.
class PackageExtractionJob {
  const PackageExtractionJob({
    required this.packages,
    required this.libraryDestination,
    this.indexDestination,
    this.maxOutputBytes = kDefaultMaxExtractedBytes,
  });

  final LibraryPackageSet packages;
  final String libraryDestination;

  /// null — האינדקס אינו נפרס גם אם הורד.
  final String? indexDestination;

  /// תקרת פלט לכל ארכיון, על פני כל ה-frames שלו.
  final int maxOutputBytes;
}

/// [done] ו-[total] הם בייטים דחוסים שנקראו מכל החלקים יחד.
typedef PackageExtractionProgress =
    void Function(LibraryPackageKind kind, int done, int total);

typedef PackageExtractionRunner =
    Future<void> Function(
      PackageExtractionJob job, {
      required PackageExtractionProgress onProgress,
      required ZstdCancelFlag cancel,
    });

/// מריץ את [job] ב-isolate נפרד; ביטול דרך [cancel] נבדק בין נתחים.
Future<void> runPackageExtractionInIsolate(
  PackageExtractionJob job, {
  required PackageExtractionProgress onProgress,
  required ZstdCancelFlag cancel,
  DynamicLibrary Function() openZstd = openZstandardLib,
}) async {
  final token = job.packages.folder.usesPlatformChannel
      ? RootIsolateToken.instance
      : null;
  await runLibraryExtractionWithProgress(
    cancel: cancel,
    run: (port) => _runIsolated(job, token, port, cancel.address, openZstd),
    onProgress: (message) {
      onProgress(
        LibraryPackageKind.values[message[0] as int],
        message[1] as int,
        message[2] as int,
      );
    },
  );
}

// פונקציה נפרדת: closure שנוצר בהיקף שמחזיק את onProgress היה מעתיק אותו
// (ואת ה-bloc שמאחוריו) אל ה-isolate.
Future<LibraryExtractionWorkerOutcome> _runIsolated(
  PackageExtractionJob job,
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
    await extractPackageJob(
      job,
      zstd: openZstd(),
      isCancelled: () => cancelCell.value != 0,
      onProgress: (kind, done, total) =>
          sendPort.send([kind.index, done, total]),
    );
  }),
);

/// גוף העבודה, גם לבדיקות בלי isolate. מדווח בכל אחוז או 8MB.
Future<void> extractPackageJob(
  PackageExtractionJob job, {
  required DynamicLibrary zstd,
  required PackageExtractionProgress onProgress,
  bool Function()? isCancelled,
}) async {
  final index = job.packages.index;
  final indexDestination = job.indexDestination;
  final tasks = [
    (job.packages.library, job.libraryDestination),
    if (index != null && indexDestination != null) (index, indexDestination),
  ];
  final total = tasks.fold<int>(0, (sum, t) => sum + t.$1.compressedSize);
  final step = (total ~/ 100).clamp(1, 8 << 20);
  var done = 0;
  var reported = 0;
  for (final (package, destination) in tasks) {
    onProgress(package.kind, done, total);
    await extractLibraryPackage(
      package: package,
      folder: job.packages.folder,
      destination: destination,
      zstd: zstd,
      isCancelled: isCancelled,
      maxOutputBytes: job.maxOutputBytes,
      onBytes: (bytes) {
        done += bytes;
        if (done - reported >= step) {
          reported = done;
          onProgress(package.kind, done, total);
        }
      },
    );
  }
  onProgress(tasks.last.$1.kind, total, total);
  if (isCancelled?.call() ?? false) throw const LibraryImportCancelled();
}

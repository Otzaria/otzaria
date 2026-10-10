import 'dart:ffi';
import 'dart:isolate';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/empty_library/services/library_package/library_package.dart';
import 'package:otzaria/empty_library/services/library_package/package_folder.dart';
import 'package:otzaria/utils/file/tar_stream_extractor.dart';
import 'package:otzaria/utils/file/zstd_library.dart';
import 'package:otzaria/utils/file/zstd_patch_decoder.dart';
import 'package:otzaria/utils/file/zstd_stream_decoder.dart';

/// הפריסה נעצרה לבקשת המשתמש.
class LibraryImportCancelled implements Exception {
  const LibraryImportCancelled();

  @override
  String toString() => 'הייבוא בוטל';
}

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
}) async {
  final decoder = ZstdStreamDecoder(
    zstd,
    requireContentChecksum: !package.hasManifest,
  );
  final tar = TarStreamExtractor(
    destination,
    rootFolder: package.kind.rootFolder,
  );
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
        if (isCancelled?.call() ?? false) throw const LibraryImportCancelled();
        partInput?.add(chunk);
        wholeInput?.add(chunk);
        read += chunk.length;
        // חלק פגום מפיל קודם את הפענוח; ממשיכים לחשב hash עד סוף החלק כדי
        // לדווח איזה חלק פגום, ולא שגיאת zstd סתמית.
        if (decodeError == null) {
          try {
            decoder.add(chunk, tar.add);
          } catch (error, stack) {
            if (partInput == null) rethrow;
            decodeError = error;
            decodeStack = stack;
          }
        }
        onBytes?.call(chunk.length);
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
    tar.close();
    if (wholeInput != null) {
      wholeInput.close();
      if (wholeDigest.events.single.toString() != package.sha256) {
        throw FormatException(
          '${package.archiveName} פגום (SHA-256 אינו תואם)',
        );
      }
    }
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
  });

  final LibraryPackageSet packages;
  final String libraryDestination;

  /// null — האינדקס אינו נפרס גם אם הורד.
  final String? indexDestination;
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
  final port = ReceivePort();
  final sub = port.listen((message) {
    if (message is List && message.length == 3) {
      onProgress(
        LibraryPackageKind.values[message[0] as int],
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

// פונקציה נפרדת: closure שנוצר בהיקף שמחזיק את onProgress היה מעתיק אותו
// (ואת ה-bloc שמאחוריו) אל ה-isolate.
Future<void> _runIsolated(
  PackageExtractionJob job,
  RootIsolateToken? token,
  SendPort sendPort,
  int cancelAddress,
  DynamicLibrary Function() openZstd,
) => Isolate.run(() async {
  if (token != null) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  }
  final cancelCell = Pointer<Uint8>.fromAddress(cancelAddress);
  await extractPackageJob(
    job,
    zstd: openZstd(),
    isCancelled: () => cancelCell.value != 0,
    onProgress: (kind, done, total) => sendPort.send([kind.index, done, total]),
  );
});

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
}

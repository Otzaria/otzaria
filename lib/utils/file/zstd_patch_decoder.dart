/// מחיל תיקון `zstd --patch-from` בזרימה: הקובץ הישן ממופה לזיכרון ומוזן
/// כ-prefix ל-ZSTD, והתוצאה נכתבת ישירות לדיסק בנתחים.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:otzaria/utils/file/mapped_file.dart';
import 'package:otzaria/utils/file/zstd_library.dart';
import 'package:otzaria/utils/file/zstd_stream_extractor.dart';
import 'package:zstandard_native/zstandard_native_bindings.dart';

/// הפענוח נעצר לבקשת המשתמש; הפלט החלקי נמחק.
class ZstdDecodeCancelled implements Exception {
  const ZstdDecodeCancelled();

  @override
  String toString() => 'ZstdDecodeCancelled';
}

/// דגל ביטול משותף בין isolates. תא בזיכרון נייטיב ולא פורט, כי לולאת
/// הפענוח סינכרונית ולא תגיע ללולאת האירועים כדי לקבל הודעה.
class ZstdCancelFlag {
  ZstdCancelFlag() : _cell = calloc<Uint8>();

  final Pointer<Uint8> _cell;

  /// לשליחה אל ה-isolate שמפענח.
  int get address => _cell.address;

  void cancel() => _cell.value = 1;

  /// חובה לקרוא רק אחרי שהפענוח הסתיים.
  void dispose() => calloc.free(_cell);
}

/// מחיל את [patchPath] על [basePath] אל [outputPath], ב-isolate נפרד.
/// חריגה מ-[maxOutputBytes] עוצרת מיד ב-[ZstdOutputLimitExceeded].
Future<void> decodePatchToFile(
  String patchPath,
  String basePath,
  String outputPath, {
  int? maxOutputBytes,
  int cancelAddress = 0,
}) => Isolate.run(
  () => _decodeWithLib(
    patchPath,
    basePath,
    outputPath,
    openZstandardLib(),
    maxOutputBytes,
    cancelAddress,
  ),
);

/// נקודת כניסה לבדיקות בלבד: הרצה סינכרונית עם [lib] מוזרק (למשל libzstd
/// של המערכת), כדי לאמת את לוגיקת ה-FFI בלי ה-framework של Flutter.
void decodePatchSyncForTest(
  String patchPath,
  String basePath,
  String outputPath,
  DynamicLibrary lib, {
  int? maxOutputBytes,
  int cancelAddress = 0,
}) => _decodeWithLib(
  patchPath,
  basePath,
  outputPath,
  lib,
  maxOutputBytes,
  cancelAddress,
);

void _decodeWithLib(
  String patchPath,
  String basePath,
  String outputPath,
  DynamicLibrary dylib,
  int? maxOutputBytes,
  int cancelAddress,
) {
  try {
    MappedFile.use(
      basePath,
      (base) => _decodeCore(
        patchPath,
        base,
        outputPath,
        dylib,
        maxOutputBytes,
        cancelAddress,
      ),
    );
  } catch (_) {
    try {
      final partial = File(outputPath);
      if (partial.existsSync()) partial.deleteSync();
    } catch (_) {}
    rethrow;
  }
}

void _decodeCore(
  String patchPath,
  MappedFile base,
  String outputPath,
  DynamicLibrary dylib,
  int? maxOutputBytes,
  int cancelAddress,
) {
  final cancelCell = cancelAddress == 0
      ? nullptr
      : Pointer<Uint8>.fromAddress(cancelAddress);
  final bindings = ZstandardNativeBindings(dylib);
  final inBufSize = bindings.ZSTD_DStreamInSize();
  final outBufSize = bindings.ZSTD_DStreamOutSize();

  final dctx = bindings.ZSTD_createDCtx();
  if (dctx == nullptr) throw Exception('ZSTD_createDCtx נכשל');

  String zstdError(int code) =>
      bindings.ZSTD_getErrorName(code).cast<Utf8>().toDartString();
  void check(int ret, String what) {
    if (bindings.ZSTD_isError(ret) != 0) {
      throw Exception('$what נכשל: ${zstdError(ret)}');
    }
  }

  try {
    check(bindings.ZSTD_initDStream(dctx), 'ZSTD_initDStream');
    // `--patch-from` מייצר frame שחלונו הוא הקובץ הישן; ב-32 ביט frame
    // שדורש חלון מעל 1GB נדחה על ידי zstd עם windowTooLarge.
    check(
      bindings.ZSTD_DCtx_setParameter(
        dctx,
        ZSTD_dParameter.ZSTD_d_windowLogMax,
        zstdWindowLogMax(),
      ),
      'ZSTD_DCtx_setParameter(windowLogMax)',
    );
    check(
      bindings.ZSTD_DCtx_refPrefix(dctx, base.data.cast(), base.length),
      'ZSTD_DCtx_refPrefix',
    );

    final inNative = malloc.allocate<Uint8>(inBufSize);
    final outNative = malloc.allocate<Uint8>(outBufSize);
    final inBuf = malloc<ZSTD_inBuffer_s>();
    final outBuf = malloc<ZSTD_outBuffer_s>();
    try {
      final outFile = File(outputPath);
      if (outFile.existsSync()) outFile.deleteSync();
      final inputRaf = File(patchPath).openSync();
      try {
        final outputRaf = outFile.openSync(mode: FileMode.writeOnly);
        try {
          final inView = inNative.asTypedList(inBufSize);
          var lastRet = 0;
          var totalWritten = 0;
          while (true) {
            final bytesRead = inputRaf.readIntoSync(inView);
            if (bytesRead == 0) break;
            inBuf.ref.src = inNative.cast();
            inBuf.ref.size = bytesRead;
            inBuf.ref.pos = 0;
            while (inBuf.ref.pos < inBuf.ref.size) {
              if (cancelCell != nullptr && cancelCell.value != 0) {
                throw const ZstdDecodeCancelled();
              }
              outBuf.ref.dst = outNative.cast();
              outBuf.ref.size = outBufSize;
              outBuf.ref.pos = 0;
              lastRet = bindings.ZSTD_decompressStream(dctx, outBuf, inBuf);
              check(lastRet, 'ZSTD_decompressStream');
              if (maxOutputBytes != null &&
                  totalWritten + outBuf.ref.pos > maxOutputBytes) {
                throw ZstdOutputLimitExceeded(maxOutputBytes);
              }
              if (outBuf.ref.pos > 0) {
                outputRaf.writeFromSync(outNative.asTypedList(outBuf.ref.pos));
                totalWritten += outBuf.ref.pos;
              }
            }
          }
          if (lastRet != 0) {
            throw Exception('קובץ התיקון קטוע או פגום: ה-frame לא הושלם');
          }
          // flush מפורש כדי לתפוס דיסק מלא (ENOSPC) שנבלע ב-page cache.
          outputRaf.flushSync();
        } finally {
          outputRaf.closeSync();
        }
      } finally {
        inputRaf.closeSync();
      }
    } finally {
      malloc.free(inNative);
      malloc.free(outNative);
      malloc.free(inBuf);
      malloc.free(outBuf);
    }
  } finally {
    bindings.ZSTD_freeDCtx(dctx);
  }
}

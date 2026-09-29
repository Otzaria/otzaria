import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:sqlite3/sqlite3.dart';

import 'ffi/native.dart' as native;

part 'convert.dart';

/// First 8 bytes of every .zdb file.
const List<int> zdbMagic = [0x4F, 0x54, 0x5A, 0x5A, 0x44, 0x42, 0x1A, 0x0A];

/// Error raised by the native layer; [code] is one of the `ZVFS_ERR_*` codes.
class ZdbException implements Exception {
  final int code;
  final String message;
  const ZdbException(this.code, this.message);

  static const int io = 1;
  static const int corrupt = 2;
  static const int noMemory = 3;
  static const int unsupported = 4;
  static const int invalid = 5;
  static const int cancelled = 6;
  static const int notZdb = 7;

  factory ZdbException.fromCode(int code, [String? detail]) {
    final base = native.zvfs_errstr(code).toDartString();
    return code == cancelled
        ? ZdbCancelledException()
        : ZdbException(
            code,
            detail == null || detail.isEmpty ? base : '$base: $detail',
          );
  }

  @override
  String toString() => 'ZdbException($code): $message';
}

class ZdbCancelledException extends ZdbException {
  ZdbCancelledException() : super(ZdbException.cancelled, 'cancelled');
}

/// Cancels running [convertToZdb] / [verifyZdb] calls it was passed to.
class ZdbCancellationToken {
  final Set<Pointer<Int32>> _flags = {};
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    for (final f in _flags) {
      f.value = 1;
    }
  }

  void _attach(Pointer<Int32> flag) {
    _flags.add(flag);
    if (_cancelled) flag.value = 1;
  }

  void _detach(Pointer<Int32> flag) => _flags.remove(flag);
}

class ZVfsStats {
  final int framesDecoded;
  final int cacheHits;
  final int cacheMisses;
  final int compressedBytesRead;
  final int corruptFrames;
  final int cacheBytes;
  final int openFiles;
  const ZVfsStats({
    required this.framesDecoded,
    required this.cacheHits,
    required this.cacheMisses,
    required this.compressedBytesRead,
    required this.corruptFrames,
    required this.cacheBytes,
    required this.openFiles,
  });

  @override
  String toString() =>
      'ZVfsStats(frames: $framesDecoded, hits: $cacheHits, misses: '
      '$cacheMisses, read: $compressedBytesRead, corrupt: $corruptFrames, '
      'cache: $cacheBytes, files: $openFiles)';
}

/// The "zvfs" SQLite VFS. Open databases with `vfs: ZVfs.name`; files
/// without the zdb magic are passed through to the default VFS unchanged.
abstract final class ZVfs {
  static const String name = 'zvfs';

  /// Registers the VFS in this process (idempotent, safe from any isolate).
  static void register({int? cacheBytesPerFile}) {
    if (cacheBytesPerFile != null) ZVfs.cacheBytesPerFile = cacheBytesPerFile;
    if (isRegistered) return;
    final entry =
        Native.addressOf<
          NativeFunction<
            Int Function(
              Pointer<Void>,
              Pointer<Pointer<Char>>,
              Pointer<Void>,
            )
          >
        >(native.sqlite3_otzariazvfs_init);
    sqlite3.ensureExtensionLoaded(SqliteExtension(entry.cast()));
    // Auto-extensions run when a connection opens.
    sqlite3.openInMemory().close();
    if (!isRegistered) {
      throw StateError('zvfs registration failed');
    }
  }

  static bool get isRegistered => native.zvfs_is_registered() != 0;

  /// Byte budget of the decoded-page LRU shared by all connections to one
  /// file. Applies to new inserts immediately; 0 disables the cache.
  static int get cacheBytesPerFile => native.zvfs_get_cache_budget();
  static set cacheBytesPerFile(int bytes) =>
      native.zvfs_set_cache_budget(bytes);

  static ZVfsStats get stats {
    final p = calloc<native.ZvfsStatsStruct>();
    try {
      native.zvfs_get_stats(p);
      final s = p.ref;
      return ZVfsStats(
        framesDecoded: s.framesDecoded,
        cacheHits: s.cacheHits,
        cacheMisses: s.cacheMisses,
        compressedBytesRead: s.compressedBytesRead,
        corruptFrames: s.corruptFrames,
        cacheBytes: s.cacheBytes,
        openFiles: s.openFiles,
      );
    } finally {
      calloc.free(p);
    }
  }

  static String get zstdVersion => native.zvfs_zstd_version().toDartString();
}

/// Whether [path] starts with the zdb magic (does not validate the file).
bool isZdb(String path) {
  RandomAccessFile? f;
  try {
    f = File(path).openSync();
    final head = f.readSync(zdbMagic.length);
    if (head.length != zdbMagic.length) return false;
    for (var i = 0; i < zdbMagic.length; i++) {
      if (head[i] != zdbMagic[i]) return false;
    }
    return true;
  } on FileSystemException {
    return false;
  } finally {
    f?.closeSync();
  }
}

class ZdbInfo {
  final int formatMajor;
  final int formatMinor;
  final int pageSize;
  final int framePages;
  final int logicalSize;
  final int frameCount;
  final int physicalSize;
  final int dictId;
  final int dictLength;
  final String dictName;
  final int level;
  final int compatFeatures;
  final int incompatFeatures;
  final int contentXxh64;
  final DateTime created;
  final Uint8List fileUuid;

  const ZdbInfo({
    required this.formatMajor,
    required this.formatMinor,
    required this.pageSize,
    required this.framePages,
    required this.logicalSize,
    required this.frameCount,
    required this.physicalSize,
    required this.dictId,
    required this.dictLength,
    required this.dictName,
    required this.level,
    required this.compatFeatures,
    required this.incompatFeatures,
    required this.contentXxh64,
    required this.created,
    required this.fileUuid,
  });

  /// Bit 0: the source was in WAL mode; the served header says rollback.
  bool get walHeaderPatched => compatFeatures & 1 != 0;

  double get ratio => logicalSize / physicalSize;

  static ZdbInfo fromNative(native.ZvfsInfoStruct s) {
    final nameBytes = <int>[];
    for (var i = 0; i < 32 && s.dictName[i] != 0; i++) {
      nameBytes.add(s.dictName[i]);
    }
    return ZdbInfo(
      formatMajor: s.formatMajor,
      formatMinor: s.formatMinor,
      pageSize: s.pageSize,
      framePages: s.framePages,
      logicalSize: s.logicalSize,
      frameCount: s.frameCount,
      physicalSize: s.physicalSize,
      dictId: s.dictId,
      dictLength: s.dictLength,
      dictName: ascii.decode(nameBytes, allowInvalid: true),
      level: s.level,
      compatFeatures: s.compatFeatures,
      incompatFeatures: s.incompatFeatures,
      contentXxh64: s.contentXxh64,
      created: DateTime.fromMillisecondsSinceEpoch(s.createdUnixMs),
      fileUuid: Uint8List.fromList([
        for (var i = 0; i < 16; i++) s.fileUuid[i],
      ]),
    );
  }
}

T _withReader<T>(String path, T Function(Pointer<native.ZvfsReader> r) body) {
  final p = path.toNativeUtf8();
  final out = calloc<Pointer<native.ZvfsReader>>();
  try {
    final rc = native.zvfs_reader_open(p, out);
    if (rc != 0) throw ZdbException.fromCode(rc, path);
    try {
      return body(out.value);
    } finally {
      native.zvfs_reader_close(out.value);
    }
  } finally {
    calloc.free(p);
    calloc.free(out);
  }
}

/// Parses and validates header, dictionary and index (not the frames).
ZdbInfo readZdbInfo(String path) => _withReader(path, (r) {
  final info = calloc<native.ZvfsInfoStruct>();
  try {
    native.zvfs_reader_info(r, info);
    return ZdbInfo.fromNative(info.ref);
  } finally {
    calloc.free(info);
  }
});

/// Reads [length] logical (decompressed) bytes at [offset], without SQLite.
Uint8List readZdbBytes(String path, int offset, int length) =>
    _withReader(path, (r) {
      final buf = malloc<Uint8>(length == 0 ? 1 : length);
      try {
        final rc = native.zvfs_reader_read(r, buf, length, offset);
        if (rc != 0 && rc != 8) throw ZdbException.fromCode(rc, path);
        return Uint8List.fromList(buf.asTypedList(length));
      } finally {
        malloc.free(buf);
      }
    });

/// Decodes every frame off the calling isolate and checks the content hash.
Future<ZdbInfo> verifyZdb(
  String path, {
  void Function(int bytesDone, int totalBytes)? onProgress,
  ZdbCancellationToken? cancellationToken,
}) async {
  final cancel = calloc<Int32>();
  final progress = calloc<Int64>();
  cancellationToken?._attach(cancel);
  final cancelAddr = cancel.address;
  final progressAddr = progress.address;
  Timer? timer;
  if (onProgress != null) {
    final total = readZdbInfo(path).logicalSize;
    timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      onProgress(progress.value.clamp(0, total), total);
    });
  }
  try {
    return await Isolate.run(
      () => _withReader(path, (r) {
        final rc = native.zvfs_reader_verify(
          r,
          Pointer<Int32>.fromAddress(cancelAddr),
          Pointer<Int64>.fromAddress(progressAddr),
        );
        if (rc != 0) throw ZdbException.fromCode(rc, path);
        final info = calloc<native.ZvfsInfoStruct>();
        try {
          native.zvfs_reader_info(r, info);
          return ZdbInfo.fromNative(info.ref);
        } finally {
          calloc.free(info);
        }
      }),
    );
  } finally {
    timer?.cancel();
    cancellationToken?._detach(cancel);
    calloc.free(cancel);
    calloc.free(progress);
  }
}

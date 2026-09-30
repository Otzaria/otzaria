part of 'zvfs.dart';

/// A frozen zstd dictionary embedded in the files that use it.
final class ZdbDictionary {
  final String name;
  final Uint8List? _custom;

  const ZdbDictionary._(this.name, this._custom);

  /// Trained on 6000 random pages of the 7.9GB seforim.db (see README).
  static const ZdbDictionary seforimV1 = ZdbDictionary._('seforim-v1', null);
  static const String seforimV1Sha256 =
      'd1f558835b17b2e90c74631e90f0690fbce850b5d1ef0331bb26c8248c65e75e';
  static const int seforimV1Id = 1702679322;

  /// No dictionary: works for any data, compresses small pages worse.
  static const ZdbDictionary none = ZdbDictionary._('', null);

  /// Any zstd dictionary (or raw content) of 1 byte to 1MB, e.g. one written
  /// by `zvfs_cli train`; [name] goes into the header (ASCII, <= 31 bytes).
  factory ZdbDictionary.custom(String name, Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw ArgumentError.value(bytes.length, 'bytes', 'must be 1..$maxBytes');
    }
    return ZdbDictionary._(name, Uint8List.fromList(bytes));
  }

  /// The largest dictionary a .zdb can carry.
  static const int maxBytes = 1 << 20;

  /// Built-in dictionary names, newest first.
  static List<String> get builtinNames => [
    for (var i = 0; i < native.zvfs_builtin_dict_count(); i++) _builtin(i).$1,
  ];

  static (String, Pointer<Void>, int, int) _builtin(int i) {
    final name = calloc<Pointer<Utf8>>();
    final data = calloc<Pointer<Void>>();
    final len = calloc<Size>();
    final id = calloc<Uint32>();
    try {
      final rc = native.zvfs_builtin_dict(i, name, data, len, id);
      if (rc != 0) throw ZdbException.fromCode(rc);
      return (name.value.toDartString(), data.value, len.value, id.value);
    } finally {
      calloc.free(name);
      calloc.free(data);
      calloc.free(len);
      calloc.free(id);
    }
  }

  static (Pointer<Void>, int)? _findBuiltin(String name) {
    for (var i = 0; i < native.zvfs_builtin_dict_count(); i++) {
      final d = _builtin(i);
      if (d.$1 == name) return (d.$2, d.$3);
    }
    return null;
  }

  /// The raw dictionary bytes (a copy).
  Uint8List get bytes {
    final c = _custom;
    if (c != null) return Uint8List.fromList(c);
    if (name.isEmpty) return Uint8List(0);
    final b = _findBuiltin(name);
    if (b == null) {
      throw ArgumentError.value(name, 'name', 'unknown dictionary');
    }
    return Uint8List.fromList(b.$1.cast<Uint8>().asTypedList(b.$2));
  }
}

/// Where [convertToZdb] reads the plain SQLite database from.
sealed class ZdbSource {
  const ZdbSource();

  /// A plain database file. Fails if a non-empty `-wal` file is next to it.
  const factory ZdbSource.file(String path) = _FileSource;

  /// A zstd-compressed database file (e.g. `seforim.db.zst`), decoded
  /// in native code while streaming; no plain copy is written.
  const factory ZdbSource.zstdFile(String path) = _ZstdFileSource;

  /// Chunks from Dart. [open] runs on the converter's worker isolate, so it
  /// must be sendable (a top-level/static function or a closure over
  /// sendable values). With [compressed] the chunks are a zstd stream.
  const factory ZdbSource.stream(
    Stream<List<int>> Function() open, {
    bool compressed,
    int? totalBytes,
  }) = _StreamSource;
}

final class _FileSource extends ZdbSource {
  final String path;
  const _FileSource(this.path);
}

final class _ZstdFileSource extends ZdbSource {
  final String path;
  const _ZstdFileSource(this.path);
}

final class _StreamSource extends ZdbSource {
  final Stream<List<int>> Function() open;
  final bool compressed;
  final int? totalBytes;
  const _StreamSource(this.open, {this.compressed = false, this.totalBytes});
}

class ZdbConvertProgress {
  /// Source bytes consumed (compressed bytes for zstd sources).
  final int bytesIn;

  /// Total source bytes, when known.
  final int? totalBytesIn;
  final int bytesOut;
  final Duration elapsed;
  const ZdbConvertProgress(
    this.bytesIn,
    this.totalBytesIn,
    this.bytesOut,
    this.elapsed,
  );

  double? get fraction => totalBytesIn == null || totalBytesIn == 0
      ? null
      : bytesIn / totalBytesIn!;
}

class ZdbConvertResult {
  final ZdbInfo info;
  final Duration elapsed;

  /// SQLite freelist leaf pages written as zeros (file sources only).
  final int freelistPagesZeroed;
  const ZdbConvertResult(
    this.info,
    this.elapsed, {
    this.freelistPagesZeroed = 0,
  });
}

class _Job {
  final ZdbSource source;
  final String destination;
  final String dictName;
  final Uint8List? customDict;
  final int level;
  final int threads;
  final int batchBytes;
  final bool zeroFreelist;
  final int cancelAddress;
  final SendPort? progress;
  const _Job(
    this.source,
    this.destination,
    this.dictName,
    this.customDict,
    this.level,
    this.threads,
    this.batchBytes,
    this.zeroFreelist,
    this.cancelAddress,
    this.progress,
  );
}

/// Converts a plain SQLite database into a .zdb at [destination].
///
/// Runs on a worker isolate with [threads] native compression threads. The
/// output is written to `<destination>.part` and renamed on success.
/// With [zeroFreelist] a [ZdbSource.file] has its SQLite freelist leaf pages
/// (free space whose bytes SQLite never reads) written as zeros; other
/// sources are converted as they are.
Future<ZdbConvertResult> convertToZdb({
  required ZdbSource source,
  required String destination,
  ZdbDictionary dictionary = ZdbDictionary.seforimV1,
  int level = 9,
  int? threads,
  int batchBytes = 16 << 20,
  bool zeroFreelist = true,
  void Function(ZdbConvertProgress progress)? onProgress,
  ZdbCancellationToken? cancellationToken,
}) async {
  final nThreads = (threads ?? (Platform.numberOfProcessors - 1))
      .clamp(1, 16)
      .toInt();
  if (dictionary._custom == null &&
      dictionary.name.isNotEmpty &&
      ZdbDictionary._findBuiltin(dictionary.name) == null) {
    throw ArgumentError.value(dictionary.name, 'dictionary', 'unknown');
  }
  final cancel = calloc<Int32>();
  cancellationToken?._attach(cancel);
  final port = ReceivePort();
  port.listen((m) {
    if (m is List && onProgress != null) {
      onProgress(
        ZdbConvertProgress(
          m[0] as int,
          m[1] as int?,
          m[2] as int,
          Duration(microseconds: m[3] as int),
        ),
      );
    }
  });
  final job = _Job(
    source,
    destination,
    dictionary.name,
    dictionary._custom,
    level,
    nThreads,
    batchBytes,
    zeroFreelist,
    cancel.address,
    port.sendPort,
  );
  try {
    return await Isolate.run(() => _convertWorker(job));
  } finally {
    cancellationToken?._detach(cancel);
    port.close();
    calloc.free(cancel);
  }
}

Future<ZdbConvertResult> _convertWorker(_Job job) async {
  final part = '${job.destination}.part';
  final cancel = Pointer<Int32>.fromAddress(job.cancelAddress);
  final src = job.source;
  final sw = Stopwatch()..start();

  if (src is _FileSource) {
    final wal = File('${src.path}-wal');
    if (wal.existsSync() && wal.lengthSync() > 0) {
      throw ZdbException(
        ZdbException.invalid,
        'source has an uncheckpointed WAL file: ${wal.path}',
      );
    }
  }
  final int? total = switch (src) {
    _FileSource(:final path) ||
    _ZstdFileSource(:final path) => File(path).lengthSync(),
    _StreamSource(:final totalBytes) => totalBytes,
  };
  final compressed = switch (src) {
    _FileSource() => false,
    _ZstdFileSource() => true,
    _StreamSource(:final compressed) => compressed,
  };

  Pointer<Void> dict = nullptr;
  var dictLen = 0;
  Pointer<Void> ownedDict = nullptr;
  if (job.customDict case final c?) {
    ownedDict = malloc<Uint8>(c.isEmpty ? 1 : c.length).cast();
    ownedDict.cast<Uint8>().asTypedList(c.length).setAll(0, c);
    dict = ownedDict;
    dictLen = c.length;
  } else if (job.dictName.isNotEmpty) {
    final b = ZdbDictionary._findBuiltin(job.dictName)!;
    dict = b.$1;
    dictLen = b.$2;
  }

  const stagingSize = 4 << 20;
  final staging = malloc<Uint8>(stagingSize);
  final view = staging.asTypedList(stagingSize);
  final partPath = part.toNativeUtf8();
  final dictName = job.dictName.toNativeUtf8();
  final convOut = calloc<Pointer<native.ZvfsConv>>();
  final pin = calloc<Uint64>(3);
  Pointer<native.ZvfsConv> conv = nullptr;
  var ok = false;

  void check(int rc) {
    if (rc == 0) return;
    final detail = conv == nullptr
        ? null
        : native.zvfs_conv_error(conv).toDartString();
    throw ZdbException.fromCode(rc, detail);
  }

  var lastReport = -1 << 62;
  void report({bool force = false}) {
    final port = job.progress;
    if (port == null || conv == nullptr) return;
    final now = sw.elapsedMicroseconds;
    if (!force && now - lastReport < 100000) return;
    lastReport = now;
    native.zvfs_conv_progress(conv, pin, pin + 1);
    port.send([pin[0], total, pin[1], now]);
  }

  void feed(int n) {
    if (cancel.value != 0) throw ZdbCancelledException();
    final rc = compressed
        ? native.zvfs_conv_feed_zstd(conv, staging.cast(), n)
        : native.zvfs_conv_feed(conv, staging.cast(), n);
    check(rc);
    report();
  }

  try {
    check(
      native.zvfs_conv_create(
        partPath,
        dict,
        dictLen,
        job.dictName.isEmpty ? nullptr : dictName,
        job.level,
        job.threads,
        1,
        job.batchBytes,
        cancel,
        convOut,
      ),
    );
    conv = convOut.value;
    if (src is _FileSource && job.zeroFreelist) {
      final srcPath = src.path.toNativeUtf8();
      try {
        check(native.zvfs_conv_zero_freelist(conv, srcPath, pin + 2));
      } finally {
        calloc.free(srcPath);
      }
    }
    switch (src) {
      case _FileSource(:final path) || _ZstdFileSource(:final path):
        final raf = File(path).openSync();
        try {
          for (;;) {
            final n = raf.readIntoSync(view);
            if (n <= 0) break;
            feed(n);
          }
        } finally {
          raf.closeSync();
        }
      case _StreamSource(:final open):
        await for (final chunk in open()) {
          var off = 0;
          while (off < chunk.length) {
            final n = (chunk.length - off).clamp(0, stagingSize).toInt();
            view.setRange(0, n, chunk, off);
            off += n;
            feed(n);
          }
        }
    }
    final info = calloc<native.ZvfsInfoStruct>();
    try {
      check(native.zvfs_conv_finish(conv, info));
      report(force: true);
      final result = ZdbInfo.fromNative(info.ref);
      File(part).renameSync(job.destination);
      ok = true;
      return ZdbConvertResult(
        result,
        sw.elapsed,
        freelistPagesZeroed: pin[2],
      );
    } finally {
      calloc.free(info);
    }
  } finally {
    if (conv != nullptr) native.zvfs_conv_destroy(conv);
    malloc.free(staging);
    if (ownedDict != nullptr) malloc.free(ownedDict);
    calloc.free(partPath);
    calloc.free(dictName);
    calloc.free(convOut);
    calloc.free(pin);
    if (!ok) {
      try {
        File(part).deleteSync();
      } on FileSystemException {
        // nothing was written
      }
    }
  }
}

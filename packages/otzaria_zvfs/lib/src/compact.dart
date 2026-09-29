part of 'zvfs.dart';

class ZdbCompactResult {
  /// The new base (no overlay any more).
  final ZdbInfo info;

  /// Physical bytes of base + overlay before, and of the new base.
  final int bytesBefore;
  final int bytesAfter;
  final Duration elapsed;
  const ZdbCompactResult(
    this.info,
    this.bytesBefore,
    this.bytesAfter,
    this.elapsed,
  );
}

/// Rewrites base + overlay of [path] into a new base and swaps it in.
///
/// Writes `<path>.new` through the logical view, verifies it (unless
/// [verify] is false), durably renames it over [path] and deletes the
/// overlay. A crash at any step leaves a readable database with the same
/// content. No connection to [path] may be open, in this process or any
/// other; this process is checked ([ZdbException.busy]), other processes
/// are the caller's job. A pending `-journal` or non-empty `-wal` also
/// fails with [ZdbException.busy]: open the database once to recover it.
Future<ZdbCompactResult> compactZdb(
  String path, {
  int level = 9,
  int? threads,
  bool verify = true,
  void Function(int bytesDone, int totalBytes)? onProgress,
  ZdbCancellationToken? cancellationToken,
}) async {
  final nThreads = (threads ?? (Platform.numberOfProcessors - 1))
      .clamp(1, 16)
      .toInt();
  final before = readZdbInfo(path);
  final ovl = File('$path-zovl');
  final bytesBefore =
      before.physicalSize + (ovl.existsSync() ? ovl.lengthSync() : 0);
  final cancel = calloc<Int32>();
  final progress = calloc<Int64>();
  cancellationToken?._attach(cancel);
  final cancelAddr = cancel.address;
  final progressAddr = progress.address;
  final total = before.logicalSize;
  Timer? timer;
  if (onProgress != null) {
    timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      onProgress(progress.value.clamp(0, total), total);
    });
  }
  final sw = Stopwatch()..start();
  try {
    final info = await Isolate.run(
      () => _compactWorker(
        path,
        level,
        nThreads,
        verify,
        cancelAddr,
        progressAddr,
      ),
    );
    onProgress?.call(total, total);
    return ZdbCompactResult(info, bytesBefore, info.physicalSize, sw.elapsed);
  } finally {
    timer?.cancel();
    cancellationToken?._detach(cancel);
    calloc.free(cancel);
    calloc.free(progress);
  }
}

ZdbInfo _compactWorker(
  String path,
  int level,
  int threads,
  bool verify,
  int cancelAddr,
  int progressAddr,
) {
  final dst = '$path.new';
  final pPath = path.toNativeUtf8();
  final pDst = dst.toNativeUtf8();
  final out = calloc<native.ZvfsInfoStruct>();
  const errLen = 256;
  final err = calloc<Uint8>(errLen);
  final cancel = Pointer<Int32>.fromAddress(cancelAddr);
  var swapped = false;
  try {
    var rc = native.zvfs_compact(
      pPath,
      pDst,
      level,
      threads,
      cancel,
      Pointer<Int64>.fromAddress(progressAddr),
      out,
      err.cast(),
      errLen,
    );
    if (rc != 0) {
      throw ZdbException.fromCode(rc, err.cast<Utf8>().toDartString());
    }
    if (verify) {
      _withReader(dst, (r) {
        final vr = native.zvfs_reader_verify(r, cancel, nullptr);
        if (vr != 0) throw ZdbException.fromCode(vr, dst);
      });
    }
    if (cancel.value != 0) throw ZdbCancelledException();
    rc = native.zvfs_compact_swap(pPath, pDst);
    // After a failed overlay delete the base is already swapped in.
    swapped = rc == 0 || !File(dst).existsSync();
    if (rc != 0) throw ZdbException.fromCode(rc, path);
    return readZdbInfo(path);
  } finally {
    if (!swapped) {
      try {
        File(dst).deleteSync();
      } on FileSystemException {
        // never written
      }
    }
    calloc.free(pPath);
    calloc.free(pDst);
    calloc.free(out);
    calloc.free(err);
  }
}

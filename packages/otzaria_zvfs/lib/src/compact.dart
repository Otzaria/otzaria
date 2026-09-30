part of 'zvfs.dart';

class ZdbCompactResult {
  /// The new base (no overlay any more).
  final ZdbInfo info;

  /// Physical bytes of base + overlay before, and of the new base.
  final int bytesBefore;
  final int bytesAfter;

  /// Frames written, and of them copied from the old base unchanged.
  final int frames;
  final int framesCopied;

  /// SQLite freelist leaf pages written as zeros.
  final int freelistPagesZeroed;
  final Duration elapsed;
  const ZdbCompactResult(
    this.info,
    this.bytesBefore,
    this.bytesAfter,
    this.elapsed, {
    this.frames = 0,
    this.framesCopied = 0,
    this.freelistPagesZeroed = 0,
  });
}

/// Rewrites base + overlay of [path] into a new base and swaps it in.
///
/// Writes `<path>.new` through the logical view, verifies it (unless
/// [verify] is false), durably renames it over [path] and deletes the
/// overlay. Frames of pages the overlay did not change are copied as they
/// are (so [level] applies only to the others), and SQLite freelist leaf
/// pages are written as zeros. A crash at any step leaves a readable
/// database with the same content. No connection to [path] may be open, in this process or any
/// other ([ZdbException.busy]); this process is checked before the file is
/// touched, other processes through the swap lock (see README). A pending
/// `-journal` or non-empty `-wal` also fails with [ZdbException.busy]: open
/// the database once to recover it.
Future<ZdbCompactResult> compactZdb(
  String path, {
  int level = 9,
  int? threads,
  bool verify = true,
  void Function(int bytesDone, int totalBytes)? onProgress,
  ZdbCancellationToken? cancellationToken,
}) async {
  // before touching the file: closing a descriptor drops this process's locks
  if (ZVfs.isOpen(path)) {
    throw ZdbException(ZdbException.busy, 'open in this process: $path');
  }
  ZVfs._register(); // the swap resolves the path through SQLite's VFS
  final nThreads = (threads ?? (Platform.numberOfProcessors - 1))
      .clamp(1, 16)
      .toInt();
  final cancel = calloc<Int32>();
  final progress = calloc<Int64>();
  cancellationToken?._attach(cancel);
  // the worker reports the total once it has replayed the overlay
  final totals = onProgress == null ? null : ReceivePort();
  Timer? timer;
  totals?.listen((total) {
    timer ??= Timer.periodic(const Duration(milliseconds: 200), (_) {
      onProgress!(progress.value.clamp(0, total as int), total);
    });
  });
  final sw = Stopwatch()..start();
  try {
    final (info, stats, bytesBefore, total) = await Isolate.run(
      _compactJob(
        path,
        level,
        nThreads,
        verify,
        cancel.address,
        progress.address,
        totals?.sendPort,
      ),
    );
    onProgress?.call(total, total);
    return ZdbCompactResult(
      info,
      bytesBefore,
      info.physicalSize,
      sw.elapsed,
      frames: stats.$1,
      framesCopied: stats.$2,
      freelistPagesZeroed: stats.$3,
    );
  } finally {
    timer?.cancel();
    totals?.close();
    cancellationToken?._detach(cancel);
    calloc.free(cancel);
    calloc.free(progress);
  }
}

/// Installs the downloaded `.zdb` at [candidatePath] as the base of [path].
///
/// Checks the candidate's header, dictionary and index and, unless [verify]
/// is false, decodes every frame against its checksums and the content hash
/// (as [verifyZdb]). It then proves the rename can succeed: [path] must be
/// replaceable (Windows: no other handle open without delete sharing, retried
/// for about 2s) and the candidate is moved next to it as `<path>.install`,
/// which fails for another volume. Only then are the `-journal`, `-wal`,
/// `-shm`, `-zovl` and `.new` of [path] deleted and the candidate durably
/// renamed over [path]; `-zlck` stays. A failure leaves the candidate at
/// [candidatePath], and before the deletes everything else as it was. A crash
/// can leave the candidate as `<path>.install`, and after the deletes the old
/// base without its overlay (an older, consistent database).
/// [ZdbException.busy] while [path] is open in this process or any other.
Future<ZdbInfo> installZdb(
  String path,
  String candidatePath, {
  bool verify = true,
}) async {
  if (ZVfs.isOpen(path)) {
    throw ZdbException(ZdbException.busy, 'open in this process: $path');
  }
  ZVfs._register(); // the swap resolves the path through SQLite's VFS
  return Isolate.run(() {
    final pPath = path.toNativeUtf8();
    final pCand = candidatePath.toNativeUtf8();
    try {
      final flags = verify ? native.zvfsInstallVerify : 0;
      final rc = native.zvfs_install(pPath, pCand, flags);
      if (rc != 0) throw ZdbException.fromCode(rc, candidatePath);
    } finally {
      calloc.free(pPath);
      calloc.free(pCand);
    }
    return readZdbInfo(path);
  });
}

typedef _CompactOutcome = (ZdbInfo, (int, int, int), int, int);

// A closure made here captures only these values: one made in compactZdb
// would share its context with the progress timer and send onProgress along.
_CompactOutcome Function() _compactJob(
  String path,
  int level,
  int threads,
  bool verify,
  int cancelAddr,
  int progressAddr,
  SendPort? totals,
) =>
    () => _compactWorker(
      path,
      level,
      threads,
      verify,
      cancelAddr,
      progressAddr,
      totals,
    );

/// Returns the new base, the stats, the bytes before and the logical size.
_CompactOutcome _compactWorker(
  String path,
  int level,
  int threads,
  bool verify,
  int cancelAddr,
  int progressAddr,
  SendPort? totals,
) {
  // replays the overlay: never on the calling (UI) isolate
  final before = readZdbInfo(path);
  final ovl = File('$path-zovl');
  final bytesBefore =
      before.physicalSize + (ovl.existsSync() ? ovl.lengthSync() : 0);
  totals?.send(before.logicalSize);
  final dst = '$path.new';
  final pPath = path.toNativeUtf8();
  final pDst = dst.toNativeUtf8();
  final out = calloc<native.ZvfsInfoStruct>();
  final stats = calloc<native.ZvfsCompactStatsStruct>();
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
      0,
      cancel,
      Pointer<Int64>.fromAddress(progressAddr),
      out,
      stats,
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
    final s = stats.ref;
    return (
      readZdbInfo(path),
      (s.frames, s.framesCopied, s.freelistLeaves),
      bytesBefore,
      before.logicalSize,
    );
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
    calloc.free(stats);
    calloc.free(err);
  }
}

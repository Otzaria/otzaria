// ignore_for_file: non_constant_identifier_names
@DefaultAsset('package:otzaria_zvfs/src/ffi/native.dart')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

final class ZvfsInfoStruct extends Struct {
  @Uint32()
  external int formatMajor;
  @Uint32()
  external int formatMinor;
  @Uint32()
  external int pageSize;
  @Uint32()
  external int framePages;
  @Uint64()
  external int logicalSize;
  @Uint64()
  external int frameCount;
  @Uint64()
  external int physicalSize;
  @Uint32()
  external int dictId;
  @Uint32()
  external int dictLength;
  @Uint32()
  external int level;
  @Uint32()
  external int compatFeatures;
  @Uint32()
  external int incompatFeatures;
  @Uint32()
  external int reserved0;
  @Uint64()
  external int contentXxh64;
  @Uint64()
  external int createdUnixMs;
  @Array(16)
  external Array<Uint8> fileUuid;
  @Array(32)
  external Array<Uint8> dictName;
}

final class ZvfsStatsStruct extends Struct {
  @Int64()
  external int framesDecoded;
  @Int64()
  external int cacheHits;
  @Int64()
  external int cacheMisses;
  @Int64()
  external int compressedBytesRead;
  @Int64()
  external int corruptFrames;
  @Int64()
  external int cacheBytes;
  @Int64()
  external int openFiles;
}

final class ZvfsReader extends Opaque {}

final class ZvfsConv extends Opaque {}

@Native<Pointer<Utf8> Function(Int)>(isLeaf: true)
external Pointer<Utf8> zvfs_errstr(int code);

@Native<Pointer<Utf8> Function()>(isLeaf: true)
external Pointer<Utf8> zvfs_zstd_version();

@Native<Int Function(Pointer<Void>, Pointer<Pointer<Char>>, Pointer<Void>)>()
external int sqlite3_otzariazvfs_init(
  Pointer<Void> db,
  Pointer<Pointer<Char>> err,
  Pointer<Void> api,
);

@Native<Int Function()>(isLeaf: true)
external int zvfs_is_registered();

@Native<Void Function(Int64)>(isLeaf: true)
external void zvfs_set_cache_budget(int bytes);

@Native<Int64 Function()>(isLeaf: true)
external int zvfs_get_cache_budget();

@Native<Void Function(Pointer<ZvfsStatsStruct>)>(isLeaf: true)
external void zvfs_get_stats(Pointer<ZvfsStatsStruct> out);

@Native<Int Function(Pointer<Utf8>)>()
external int zvfs_probe_path(Pointer<Utf8> path);

@Native<Int Function(Pointer<Utf8>, Pointer<Pointer<ZvfsReader>>)>()
external int zvfs_reader_open(
  Pointer<Utf8> path,
  Pointer<Pointer<ZvfsReader>> out,
);

@Native<Int Function(Pointer<ZvfsReader>, Pointer<ZvfsInfoStruct>)>(
  isLeaf: true,
)
external int zvfs_reader_info(
  Pointer<ZvfsReader> r,
  Pointer<ZvfsInfoStruct> out,
);

@Native<Int Function(Pointer<ZvfsReader>, Pointer<Uint8>, Int64, Int64)>()
external int zvfs_reader_read(
  Pointer<ZvfsReader> r,
  Pointer<Uint8> buf,
  int n,
  int offset,
);

@Native<Void Function(Pointer<ZvfsReader>)>()
external void zvfs_reader_close(Pointer<ZvfsReader> r);

@Native<Int Function(Pointer<ZvfsReader>, Pointer<Int32>, Pointer<Int64>)>()
external int zvfs_reader_verify(
  Pointer<ZvfsReader> r,
  Pointer<Int32> cancel,
  Pointer<Int64> progress,
);

@Native<
  Int Function(
    Pointer<Utf8>,
    Pointer<Void>,
    Size,
    Pointer<Utf8>,
    Int,
    Int,
    Uint32,
    Uint64,
    Pointer<Int32>,
    Pointer<Pointer<ZvfsConv>>,
  )
>()
external int zvfs_conv_create(
  Pointer<Utf8> dst,
  Pointer<Void> dict,
  int dictLen,
  Pointer<Utf8> dictName,
  int level,
  int threads,
  int framePages,
  int batchBytes,
  Pointer<Int32> cancel,
  Pointer<Pointer<ZvfsConv>> out,
);

@Native<Int Function(Pointer<ZvfsConv>, Pointer<Void>, Size)>()
external int zvfs_conv_feed(Pointer<ZvfsConv> c, Pointer<Void> data, int len);

@Native<Int Function(Pointer<ZvfsConv>, Pointer<Void>, Size)>()
external int zvfs_conv_feed_zstd(
  Pointer<ZvfsConv> c,
  Pointer<Void> data,
  int len,
);

@Native<Int Function(Pointer<ZvfsConv>, Pointer<ZvfsInfoStruct>)>()
external int zvfs_conv_finish(Pointer<ZvfsConv> c, Pointer<ZvfsInfoStruct> out);

@Native<Void Function(Pointer<ZvfsConv>, Pointer<Uint64>, Pointer<Uint64>)>(
  isLeaf: true,
)
external void zvfs_conv_progress(
  Pointer<ZvfsConv> c,
  Pointer<Uint64> bytesIn,
  Pointer<Uint64> bytesOut,
);

@Native<Pointer<Utf8> Function(Pointer<ZvfsConv>)>(isLeaf: true)
external Pointer<Utf8> zvfs_conv_error(Pointer<ZvfsConv> c);

@Native<Void Function(Pointer<ZvfsConv>)>()
external void zvfs_conv_destroy(Pointer<ZvfsConv> c);

@Native<Int Function()>(isLeaf: true)
external int zvfs_builtin_dict_count();

@Native<
  Int Function(
    Int,
    Pointer<Pointer<Utf8>>,
    Pointer<Pointer<Void>>,
    Pointer<Size>,
    Pointer<Uint32>,
  )
>(isLeaf: true)
external int zvfs_builtin_dict(
  int index,
  Pointer<Pointer<Utf8>> name,
  Pointer<Pointer<Void>> data,
  Pointer<Size> len,
  Pointer<Uint32> id,
);

@Native<Uint64 Function(Pointer<Void>, Size, Uint64)>(isLeaf: true)
external int zvfs_xxh64(Pointer<Void> data, int len, int seed);

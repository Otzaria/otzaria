import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:zstandard_native/zstandard_native_bindings.dart';

/// tar אמיתי (GNU long names לשמות ארוכים, UTF-8) מ-package:archive.
Uint8List buildTar(
  Map<String, List<int>> files, {
  List<String> dirs = const [],
}) {
  final archive = Archive();
  for (final dir in dirs) {
    archive.add(ArchiveFile.directory(dir));
  }
  files.forEach((name, bytes) => archive.add(ArchiveFile.bytes(name, bytes)));
  return TarEncoder().encodeBytes(archive);
}

/// דחיסת zstd אמיתית כמו `zstd` של שורת הפקודה: עם checksum של התוכן.
Uint8List zstdCompress(
  DynamicLibrary lib,
  Uint8List data, {
  bool checksum = true,
}) {
  final zstd = ZstandardNativeBindings(lib);
  final ctx = zstd.ZSTD_createCCtx();
  final bound = zstd.ZSTD_compressBound(data.length);
  final src = malloc<Uint8>(data.length + 1);
  final dst = malloc<Uint8>(bound);
  try {
    src.asTypedList(data.length).setAll(0, data);
    zstd.ZSTD_CCtx_setParameter(
      ctx,
      ZSTD_cParameter.ZSTD_c_checksumFlag,
      checksum ? 1 : 0,
    );
    final written = zstd.ZSTD_compress2(
      ctx,
      dst.cast(),
      bound,
      src.cast(),
      data.length,
    );
    if (zstd.ZSTD_isError(written) != 0) throw StateError('compress failed');
    return Uint8List.fromList(dst.asTypedList(written));
  } finally {
    zstd.ZSTD_freeCCtx(ctx);
    malloc
      ..free(src)
      ..free(dst);
  }
}

/// כותב ל-[dir] את הנכס כמו שהמסייע מניח אותו: חלקים בגודל [partSize],
/// ובמידת הצורך גם מניפסט בצורת `split_release_asset.sh`.
List<String> writeSplitAsset(
  Directory dir,
  String archiveName,
  Uint8List archive, {
  required int partSize,
  bool withManifest = true,
}) {
  final names = <String>[];
  final parts = <Map<String, Object>>[];
  for (
    var offset = 0, i = 0;
    offset < archive.length;
    offset += partSize, i++
  ) {
    final end = (offset + partSize).clamp(0, archive.length);
    final bytes = archive.sublist(offset, end);
    final name = '$archiveName.part-${i.toString().padLeft(3, '0')}';
    File(p.join(dir.path, name)).writeAsBytesSync(bytes);
    names.add(name);
    parts.add({
      'name': name,
      'size': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
    });
  }
  if (withManifest) {
    File(p.join(dir.path, '$archiveName.manifest.json')).writeAsStringSync(
      jsonEncode({
        'schemaVersion': 1,
        'archive': archiveName,
        'size': archive.length,
        'sha256': sha256.convert(archive).toString(),
        'partSizeLimit': partSize,
        'githubAssetLimit': 2147483648,
        'parts': parts,
      }),
    );
  }
  return names;
}

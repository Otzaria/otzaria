import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:zstandard/zstandard.dart';

Future<Uint8List> decompressVerifiedContent({
  required Uint8List compressed,
  required int uncompressedSize,
  required Uint8List contentHash,
}) async {
  final decoded = await Zstandard().decompress(compressed);
  if (decoded == null) throw const FormatException('Zstd decompression failed');
  if (decoded.length != uncompressedSize) {
    throw FormatException(
      'Invalid uncompressed size: ${decoded.length}, expected $uncompressedSize',
    );
  }
  if (!_sameBytes(sha256.convert(decoded).bytes, contentHash)) {
    throw const FormatException('Compressed content checksum mismatch');
  }
  return decoded;
}

List<String> decodeBookContentPayload(
  Uint8List payload, {
  required int expectedLines,
}) {
  final data = ByteData.sublistView(payload);
  final lines = <String>[];
  var offset = 0;
  while (offset < payload.length) {
    if (payload.length - offset < 4) {
      throw const FormatException('Truncated book-content line length');
    }
    final length = data.getUint32(offset, Endian.little);
    offset += 4;
    if (length > payload.length - offset) {
      throw const FormatException('Truncated book-content line');
    }
    lines.add(utf8.decode(payload.sublist(offset, offset + length)));
    offset += length;
  }
  if (lines.length != expectedLines) {
    throw FormatException(
      'Invalid book-content line count: ${lines.length}, expected $expectedLines',
    );
  }
  return lines;
}

Map<int, String> decodeVersionContentPayload(Uint8List payload) {
  final data = ByteData.sublistView(payload);
  final lines = <int, String>{};
  var offset = 0;
  while (offset < payload.length) {
    if (payload.length - offset < 12) {
      throw const FormatException('Truncated version-content entry');
    }
    final lineId = data.getInt64(offset, Endian.little);
    final length = data.getUint32(offset + 8, Endian.little);
    offset += 12;
    if (lineId <= 0 || length > payload.length - offset) {
      throw const FormatException('Invalid version-content entry');
    }
    if (lines.containsKey(lineId)) {
      throw FormatException('Duplicate version-content line $lineId');
    }
    lines[lineId] = utf8.decode(payload.sublist(offset, offset + length));
    offset += length;
  }
  return lines;
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}

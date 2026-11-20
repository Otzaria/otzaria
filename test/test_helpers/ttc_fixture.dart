import 'dart:typed_data';

import 'package:otzaria/utils/file/sfnt_bytes.dart';

/// אוסף ttcf מגופנים שלמים: ההיסטים של הטבלאות בכל face הופכים למוחלטים.
Uint8List buildCollection(List<Uint8List> fonts) {
  var cursor = 12 + fonts.length * 4;
  final offsets = <int>[];
  for (final font in fonts) {
    offsets.add(cursor);
    cursor += (font.length + 3) & ~3;
  }
  final out = Uint8List(cursor);
  final data = ByteData.sublistView(out)
    ..setUint32(0, 0x74746366) // "ttcf"
    ..setUint32(4, 0x00010000)
    ..setUint32(8, fonts.length);
  for (var i = 0; i < fonts.length; i++) {
    data.setUint32(12 + i * 4, offsets[i]);
    out.setRange(offsets[i], offsets[i] + fonts[i].length, fonts[i]);
    final numTables = fonts[i].sfntU16(4);
    for (var t = 0; t < numTables; t++) {
      final rec = offsets[i] + 12 + t * 16;
      data.setUint32(rec + 8, data.getUint32(rec + 8) + offsets[i]);
    }
  }
  return out;
}

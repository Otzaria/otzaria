import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_fonts.dart';

// ---------------------------------------------------------------------------
// Helpers — build minimal valid OpenType/TrueType byte sequences
// ---------------------------------------------------------------------------

/// Builds a minimal SFNT with one cmap format-4 subtable, 2 segments.
/// [hebrewRange]: segment covers U+0590–05FF (Hebrew); otherwise U+0041–005A (Latin).
Uint8List _buildSfnt({required bool hebrewRange}) {
  final int sc = hebrewRange ? 0x0590 : 0x0041;
  final int ec = hebrewRange ? 0x05FF : 0x005A;

  // cmap format-4 subtable (2 segments = real + 0xFFFF terminator)
  // size = 14 header + 4 endCodes + 2 pad + 4 startCodes + 4 idDeltas + 4 idRangeOffsets = 32
  final sub = ByteData(32)
    ..setUint16(0, 4)       // format
    ..setUint16(2, 32)      // length
    ..setUint16(4, 0)       // language
    ..setUint16(6, 4)       // segCountX2
    ..setUint16(8, 4)       // searchRange
    ..setUint16(10, 1)      // entrySelector
    ..setUint16(12, 0)      // rangeShift
    ..setUint16(14, ec)     // endCode[0]
    ..setUint16(16, 0xFFFF) // endCode[1] terminator
    ..setUint16(18, 0)      // reservedPad
    ..setUint16(20, sc)     // startCode[0]
    ..setUint16(22, 0xFFFF) // startCode[1] terminator
    ..setUint16(24, 0)      // idDelta[0]
    ..setUint16(26, 1)      // idDelta[1]
    ..setUint16(28, 0)      // idRangeOffset[0]
    ..setUint16(30, 0);     // idRangeOffset[1]

  // cmap table: version(2) + numTables(2) + encoding record(8) + subtable(32) = 44
  // subtable offset relative to cmap start = 4 + 8 = 12
  final cmap = ByteData(44)
    ..setUint16(0, 0)  // version
    ..setUint16(2, 1)  // numTables
    ..setUint16(4, 3)  // platformID = 3 (Windows)
    ..setUint16(6, 1)  // encodingID = 1 (BMP)
    ..setUint32(8, 12); // subtable offset
  for (int i = 0; i < 32; i++) {
    cmap.setUint8(12 + i, sub.getUint8(i));
  }

  // SFNT offset table (12) + 1 table record (16) = 28; cmap starts at 28
  const int cmapOffset = 28;
  final sfnt = ByteData(cmapOffset + 44)
    ..setUint32(0, 0x00010000) // sfVersion (TrueType)
    ..setUint16(4, 1)          // numTables
    ..setUint16(6, 16)         // searchRange
    ..setUint16(8, 0)          // entrySelector
    ..setUint16(10, 0)         // rangeShift
    // table record: "cmap"
    ..setUint8(12, 0x63)..setUint8(13, 0x6D)..setUint8(14, 0x61)..setUint8(15, 0x70)
    ..setUint32(16, 0)           // checksum
    ..setUint32(20, cmapOffset)  // offset
    ..setUint32(24, 44);         // length
  for (int i = 0; i < 44; i++) {
    sfnt.setUint8(cmapOffset + i, cmap.getUint8(i));
  }
  return sfnt.buffer.asUint8List();
}

/// Wraps one or more SFNTs into a TTC file.
Uint8List _buildTtc(List<Uint8List> fonts) {
  final int headerSize = 12 + fonts.length * 4;
  final offsets = <int>[];
  int pos = headerSize;
  for (final f in fonts) {
    offsets.add(pos);
    pos += f.length;
  }
  final ttc = ByteData(pos)
    ..setUint8(0, 0x74)..setUint8(1, 0x74)..setUint8(2, 0x63)..setUint8(3, 0x66) // "ttcf"
    ..setUint32(4, 0x00010000)       // version
    ..setUint32(8, fonts.length);    // numFonts
  for (int i = 0; i < fonts.length; i++) {
    ttc.setUint32(12 + i * 4, offsets[i]);
  }
  for (int i = 0; i < fonts.length; i++) {
    final f = fonts[i];
    for (int j = 0; j < f.length; j++) {
      ttc.setUint8(offsets[i] + j, f[j]);
    }
  }
  return ttc.buffer.asUint8List();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  test('list fonts', () {
    try {
      for (final font in AppFonts.availableFonts) {
        debugPrint('Font: ${font.label}, family: ${font.value}');
      }
    } catch (e) {
      debugPrint('Error: $e');
    }
  });

  group('sfntSupportsHebrew — SFNT', () {
    test('Hebrew range → true', () {
      expect(
        AppFonts.debugSfntSupportsHebrew(_buildSfnt(hebrewRange: true)),
        isTrue,
      );
    });

    test('non-Hebrew range → false', () {
      expect(
        AppFonts.debugSfntSupportsHebrew(_buildSfnt(hebrewRange: false)),
        isFalse,
      );
    });

    test('empty data → false', () {
      expect(AppFonts.debugSfntSupportsHebrew(Uint8List(0)), isFalse);
    });

    test('too-short data → false', () {
      expect(AppFonts.debugSfntSupportsHebrew(Uint8List(4)), isFalse);
    });
  });

  group('sfntSupportsHebrew — TTC', () {
    test('TTC with Hebrew font → true', () {
      final ttc = _buildTtc([_buildSfnt(hebrewRange: true)]);
      expect(AppFonts.debugSfntSupportsHebrew(ttc), isTrue);
    });

    test('TTC with non-Hebrew font → false', () {
      final ttc = _buildTtc([_buildSfnt(hebrewRange: false)]);
      expect(AppFonts.debugSfntSupportsHebrew(ttc), isFalse);
    });

    test('TTC with Hebrew as second font → true', () {
      final ttc = _buildTtc([
        _buildSfnt(hebrewRange: false),
        _buildSfnt(hebrewRange: true),
      ]);
      expect(AppFonts.debugSfntSupportsHebrew(ttc), isTrue);
    });

    test('TTC with only non-Hebrew fonts → false', () {
      final ttc = _buildTtc([
        _buildSfnt(hebrewRange: false),
        _buildSfnt(hebrewRange: false),
      ]);
      expect(AppFonts.debugSfntSupportsHebrew(ttc), isFalse);
    });

    test('TTC header too short → false', () {
      // Only 8 bytes: enough for magic + version but not numFonts
      final bad = Uint8List.fromList([0x74, 0x74, 0x63, 0x66, 0, 1, 0, 0]);
      expect(AppFonts.debugSfntSupportsHebrew(bad), isFalse);
    });
  });
}

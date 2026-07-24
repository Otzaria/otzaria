import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// קריאת קובץ טקסט עם זיהוי קידוד סלחני.
///
/// ספרים אישיים מגיעים לא פעם מקבצים ישנים שנשמרו ב-ANSI עברית
/// (Windows-1255) או ב-UTF-16, ו-`readAsString()` הרגיל זורק עליהם
/// `FileSystemException: Failed to decode data using encoding 'utf-8'`.
/// סדר הזיהוי: BOM (UTF-8/UTF-16) → היוריסטיקת UTF-16 בלי BOM →
/// UTF-8 קפדני → Windows-1255.
Future<String> readTextFileSmart(File file) async {
  final bytes = await file.readAsBytes();
  return decodeTextBytesSmart(bytes);
}

/// מפענח בייטים של טקסט לפי אותה לוגיקת זיהוי של [readTextFileSmart].
String decodeTextBytesSmart(Uint8List bytes) {
  if (bytes.isEmpty) return '';

  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _decodeUtf16(bytes, offset: 2, littleEndian: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _decodeUtf16(bytes, offset: 2, littleEndian: false);
  }

  final utf16 = _tryDecodeUtf16WithoutBom(bytes);
  if (utf16 != null) return utf16;

  try {
    return utf8.decode(bytes);
  } on FormatException {
    // לא UTF-8 חוקי — ממשיכים לזיהוי הבא.
  }

  return _decodeWindows1255(bytes);
}

String? _tryDecodeUtf16WithoutBom(Uint8List bytes) {
  if (bytes.length < 4) return null;
  final evenLength = bytes.length.isEven ? bytes.length : bytes.length - 1;
  final sampleLen = evenLength < 4096 ? evenLength : 4096;
  var littleEndianScore = 0;
  var bigEndianScore = 0;
  for (var i = 0; i + 1 < sampleLen; i += 2) {
    final littleEndian = bytes[i] | (bytes[i + 1] << 8);
    final bigEndian = (bytes[i] << 8) | bytes[i + 1];
    if (_isLikelyTextCodeUnit(littleEndian)) littleEndianScore++;
    if (_isLikelyTextCodeUnit(bigEndian)) bigEndianScore++;
  }

  final pairs = sampleLen ~/ 2;
  if (littleEndianScore * 4 >= pairs * 3 &&
      littleEndianScore > bigEndianScore * 2) {
    return _decodeUtf16(bytes, offset: 0, littleEndian: true);
  }
  if (bigEndianScore * 4 >= pairs * 3 &&
      bigEndianScore > littleEndianScore * 2) {
    return _decodeUtf16(bytes, offset: 0, littleEndian: false);
  }
  return null;
}

bool _isLikelyTextCodeUnit(int unit) {
  return unit == 0x09 ||
      unit == 0x0A ||
      unit == 0x0D ||
      (unit >= 0x20 && unit <= 0x7E) ||
      (unit >= 0x00A0 && unit <= 0x05FF) ||
      (unit >= 0x2000 && unit <= 0x206F);
}

String _decodeUtf16(
  Uint8List bytes, {
  required int offset,
  required bool littleEndian,
}) {
  final codeUnits = <int>[];
  for (var i = offset; i + 1 < bytes.length; i += 2) {
    codeUnits.add(
      littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1],
    );
  }
  return String.fromCharCodes(codeUnits);
}

String _decodeWindows1255(Uint8List bytes) {
  final codeUnits = List<int>.filled(bytes.length, 0);
  for (var i = 0; i < bytes.length; i++) {
    final b = bytes[i];
    codeUnits[i] = b < 0x80 ? b : _cp1255High[b - 0x80];
  }
  return String.fromCharCodes(codeUnits);
}

/// מיפוי Windows-1255 עבור 0x80–0xFF (לפי מפת WHATWG; תווים לא מוגדרים → U+FFFD).
const List<int> _cp1255High = [
  0x20AC, 0xFFFD, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, // 0x80
  0x02C6, 0x2030, 0xFFFD, 0x2039, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, // 0x88
  0xFFFD, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, // 0x90
  0x02DC, 0x2122, 0xFFFD, 0x203A, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, // 0x98
  0x00A0, 0x00A1, 0x00A2, 0x00A3, 0x20AA, 0x00A5, 0x00A6, 0x00A7, // 0xA0
  0x00A8, 0x00A9, 0x00D7, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x00AF, // 0xA8
  0x00B0, 0x00B1, 0x00B2, 0x00B3, 0x00B4, 0x00B5, 0x00B6, 0x00B7, // 0xB0
  0x00B8, 0x00B9, 0x00F7, 0x00BB, 0x00BC, 0x00BD, 0x00BE, 0x00BF, // 0xB8
  0x05B0, 0x05B1, 0x05B2, 0x05B3, 0x05B4, 0x05B5, 0x05B6, 0x05B7, // 0xC0
  0x05B8, 0x05B9, 0x05BA, 0x05BB, 0x05BC, 0x05BD, 0x05BE, 0x05BF, // 0xC8
  0x05C0, 0x05C1, 0x05C2, 0x05C3, 0x05F0, 0x05F1, 0x05F2, 0x05F3, // 0xD0
  0x05F4, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, // 0xD8
  0x05D0, 0x05D1, 0x05D2, 0x05D3, 0x05D4, 0x05D5, 0x05D6, 0x05D7, // 0xE0
  0x05D8, 0x05D9, 0x05DA, 0x05DB, 0x05DC, 0x05DD, 0x05DE, 0x05DF, // 0xE8
  0x05E0, 0x05E1, 0x05E2, 0x05E3, 0x05E4, 0x05E5, 0x05E6, 0x05E7, // 0xF0
  0x05E8, 0x05E9, 0x05EA, 0xFFFD, 0xFFFD, 0x200E, 0x200F, 0xFFFD, // 0xF8
];

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/smart_text/display_sized_memory_image.dart';

/// כותרת PNG בלבד (חתימה + IHDR): די כדי לקבוע מידות, בלי פיקסלים.
Uint8List _pngHeader(int width, int height) {
  final bytes = ByteData(33);
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (var i = 0; i < signature.length; i++) {
    bytes.setUint8(i, signature[i]);
  }
  bytes.setUint32(8, 13);
  bytes.setUint32(12, 0x49484452); // IHDR
  bytes.setUint32(16, width);
  bytes.setUint32(20, height);
  bytes.setUint8(24, 8);
  bytes.setUint8(25, 6);
  return bytes.buffer.asUint8List();
}

Uint8List _jpegHeader(int width, int height, {bool exif = false}) =>
    Uint8List.fromList([
      0xFF, 0xD8, // SOI
      if (exif) ...[0xFF, 0xE1, 0x00, 0x08, 0x45, 0x78, 0x69, 0x66, 0, 0],
      0xFF, 0xE0, 0x00, 0x04, 0x00, 0x00, // APP0 קצר
      0xFF, 0xC0, 0x00, 0x11, 0x08, //
      height >> 8, height & 0xFF, width >> 8, width & 0xFF,
      0x03, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    ]);

void main() {
  group('encodedImagePixelSize', () {
    test('PNG ו-JPEG נקראים מהכותרת', () {
      expect(encodedImagePixelSize(_pngHeader(2002, 2826)), (
        width: 2002,
        height: 2826,
      ));
      expect(encodedImagePixelSize(_jpegHeader(640, 480)), (
        width: 640,
        height: 480,
      ));
    });

    test('JPEG עם Exif ופורמט לא מוכר אינם נקראים', () {
      expect(encodedImagePixelSize(_jpegHeader(640, 480, exif: true)), isNull);
      expect(
        encodedImagePixelSize(Uint8List.fromList(utf8.encode('GIF89a'))),
        isNull,
      );
    });
  });
}

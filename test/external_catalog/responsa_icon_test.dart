import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/responsa/responsa_icon.dart';

/// חילוץ האייקון מקובץ ההרצה.
///
/// הבדיקה רצה מול ההתקנה שעל המכונה כשהיא קיימת, ומדלגת כשאינה. מה
/// שנבדק תמיד הוא שקלט פגום אינו מפיל דבר — זהו המסלול שרץ אצל משתמש
/// עם התקנה חלקית או קובץ שנקטע.
void main() {
  group('קלט פגום מחזיר null ולא חריג', () {
    test('קובץ ריק', () {
      expect(ResponsaIcon.extractFrom(Uint8List(0)), isNull);
    });

    test('קובץ שאינו PE', () {
      expect(
        ResponsaIcon.extractFrom(Uint8List.fromList(List.filled(4096, 7))),
        isNull,
      );
    });

    test('כותרת MZ בלי PE', () {
      final bytes = Uint8List(1024);
      bytes[0] = 0x4D;
      bytes[1] = 0x5A;
      final view = ByteData.sublistView(bytes);
      view.setUint32(0x3C, 900, Endian.little);
      expect(ResponsaIcon.extractFrom(bytes), isNull);
    });

    test('הפניה למדור שאינו קיים', () {
      final bytes = Uint8List(2048);
      final view = ByteData.sublistView(bytes)
        ..setUint32(0x3C, 0x80, Endian.little)
        ..setUint32(0x80, 0x00004550, Endian.little)
        ..setUint16(0x80 + 6, 1, Endian.little)
        ..setUint16(0x80 + 20, 224, Endian.little)
        ..setUint16(0x80 + 24, 0x10b, Endian.little);
      // ספריית משאבים שמצביעה אל מחוץ לכל מדור.
      view.setUint32(0x80 + 24 + 96 + 16, 0x900000, Endian.little);
      expect(ResponsaIcon.extractFrom(bytes), isNull);
    });
  });

  test('חילוץ מההתקנה שעל המכונה', () {
    const candidates = [
      r'C:\Program Files (x86)\ResponsaCD25H\RESPONSA.exe',
      r'C:\Program Files (x86)\ResponsaCD25\RESPONSA.exe',
    ];
    final found = candidates.map(File.new).where((f) => f.existsSync());
    if (found.isEmpty) {
      markTestSkipped('אין התקנה של בר אילן על המכונה הזו');
      return;
    }
    final icon = ResponsaIcon.extractFrom(found.first.readAsBytesSync());
    expect(icon, isNotNull);
    // כותרת ICO: reserved=0, type=1, count=1.
    final header = ByteData.sublistView(icon!);
    expect(header.getUint16(0, Endian.little), 0);
    expect(header.getUint16(2, Endian.little), 1);
    expect(header.getUint16(4, Endian.little), 1);
    expect(header.getUint32(18, Endian.little), 22);
    expect(icon.length, greaterThan(22));
  });
}

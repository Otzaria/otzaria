import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// תעודות ה-CA של נטפרי שהאפליקציה טוענת ב-`_loadCerts` (lib/main.dart).
///
/// כל קובץ הוא באנדל PEM אחד. הבדיקה מוודאת שהקבצים קיימים, תקינים
/// מבחינת מבנה, ושכל שלוש קבוצות התעודות (ישנות לפי ספק, אחיד גירסה 1,
/// אחיד X2) אכן נמצאות — ספקים שונים חותמים היום בשורשים שונים.
void main() {
  const pemHeader = '-----BEGIN CERTIFICATE-----';
  const pemFooter = '-----END CERTIFICATE-----';

  int countBlocks(String pem, String marker) => marker.allMatches(pem).length;

  test('כל קבצי ה-CA ברשימה של main.dart קיימים ובנויים מבלוקי PEM שלמים', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final listed = RegExp(
      r"'(assets/ca/[^']+\.pem)'",
    ).allMatches(mainSource).map((m) => m.group(1)!).toSet();
    expect(listed, {
      'assets/ca/netfree_cas.pem',
      'assets/ca/netfree_root_ca_unified_v1.pem',
      'assets/ca/netfree_root_ca_x2.pem',
    });

    for (final path in listed) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path חסר');
      final pem = file.readAsStringSync();
      final begins = countBlocks(pem, pemHeader);
      expect(begins, greaterThan(0), reason: '$path ריק');
      expect(
        countBlocks(pem, pemFooter),
        begins,
        reason: '$path: בלוק PEM לא סגור',
      );
    }
  });

  test('באנדל X2 מכיל את חמש תעודות השורש האחיד גירסה 2', () {
    final pem = File('assets/ca/netfree_root_ca_x2.pem').readAsStringSync();
    expect(countBlocks(pem, pemHeader), 5);
  });

  test('באנדל גירסה 1 מכיל את חמש תעודות השורש האחיד גירסה 1', () {
    final pem = File(
      'assets/ca/netfree_root_ca_unified_v1.pem',
    ).readAsStringSync();
    expect(countBlocks(pem, pemHeader), 5);
  });
}

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:otzaria/data/book_identity.dart';
import 'package:otzaria/models/books.dart' show PdfBook;

/// זהות ספר PDF במעקב שמור וזכור, זהה בכל מכשיר שמחזיק את אותו ספר.
///
/// ספר קטלוג בעל מזהה חיצוני (היברובוקס: `hb:<id>`) מזוהה לפיו. כל PDF אחר
/// (אישי, או קובץ בתיקייה) מזוהה לפי תוכנו: SHA-256 של גודל הקובץ ושל
/// [sampleBytes] בתחילתו, באמצעו ובסופו. הנתיב, שם הקובץ ומזהה הספר האישי
/// משתנים בין מכשירים ולכן אינם חלק מהזהות.
class PdfTrackingIdentity {
  PdfTrackingIdentity._();

  static const int sampleBytes = 64 * 1024;
  static const String _contentPrefix = 'sha256:';

  /// מפתחות מספריים שנגזרים מזהות נמצאים בטווח [-(2^52-1), -2^51]. מפתח
  /// שלילי מחוץ לטווח הוא מונה מקומי של גרסה קודמת ([isLegacyKey]).
  static const int _keyBit = 1 << 51;

  static Future<String> of(PdfBook book) async {
    final external = book.externalLibraryId;
    if (external != null && external.isNotEmpty && !book.source.isAttached) {
      return BookIdentity.externalIdentityKey(external);
    }
    return '$_contentPrefix${await fingerprint(book.path)}';
  }

  static bool isContentIdentity(String identity) =>
      identity.startsWith(_contentPrefix);

  /// טביעת תוכן של הקובץ ב-[path] (hex).
  static Future<String> fingerprint(String path) async {
    final file = await File(path).open();
    try {
      final size = await file.length();
      final input = BytesBuilder(copy: false)
        ..add((ByteData(8)..setUint64(0, size)).buffer.asUint8List());
      for (final offset in {
        0,
        math.max(0, size ~/ 2 - sampleBytes ~/ 2),
        math.max(0, size - sampleBytes),
      }) {
        await file.setPosition(offset);
        input.add(await file.read(sampleBytes));
      }
      return sha256.convert(input.takeBytes()).toString();
    } finally {
      await file.close();
    }
  }

  /// המפתח המספרי שתחתיו נשמרים ההתקדמות וכל הנתונים המקושרים לספר. נגזר
  /// מהזהות בלבד, ולכן זהה בכל מכשיר ואינו מתנגש במזהי seforim.db החיוביים.
  static int keyOf(String identity) {
    final digest = sha256.convert(utf8.encode(identity)).bytes;
    var value = 0;
    for (var i = 0; i < 7; i++) {
      value = (value << 8) | digest[i];
    }
    return -(_keyBit | (value & (_keyBit - 1)));
  }

  /// מפתח שהוקצה ממונה מקומי (-1, -2, ...) לפני שהזהות נגזרה מהתוכן.
  static bool isLegacyKey(int key) => key < 0 && key > -_keyBit;
}

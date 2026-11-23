import 'dart:convert';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:otzaria/data/book_identity.dart';
import 'package:otzaria/models/books.dart' show PdfBook;
import 'package:otzaria/utils/file/native_sha256.dart';

/// זהות ספר PDF במעקב שמור וזכור, זהה בכל מכשיר שמחזיק את אותו ספר.
///
/// ספר קטלוג בעל מזהה חיצוני (היברובוקס: `hb:<id>`) מזוהה לפיו. כל PDF אחר
/// (אישי, או קובץ בתיקייה) מזוהה לפי SHA-256 של כל הקובץ. הנתיב, שם הקובץ ומזהה הספר האישי
/// משתנים בין מכשירים ולכן אינם חלק מהזהות.
class PdfTrackingIdentity {
  PdfTrackingIdentity._();

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
  static Future<String> fingerprint(String path) =>
      Isolate.run(() => sha256OfFileFast(path));

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

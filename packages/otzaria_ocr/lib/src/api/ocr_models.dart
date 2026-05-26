/// מצבי הזמינות של מנוע ה-OCR.
enum OcrAvailability {
  /// המנוע מוכן לשימוש – המודלים הותקנו בתיקייה הייעודית.
  ready,

  /// הפלטפורמה תומכת (Windows) אבל המודלים עוד לא הותקנו.
  /// יש להציג למשתמש דיאלוג אישור ולקרוא ל-installModels.
  needsInstall,

  /// קבצי המקור (DLLs המצורפים לתוכנה) חסרים. בנייה לא תקינה.
  missingBundledFiles,

  /// הפלטפורמה לא נתמכת (כל מה שאינו Windows).
  unsupportedPlatform,
}

/// אירוע התקדמות במהלך התקנת המודלים.
class OcrInstallProgress {
  const OcrInstallProgress({
    required this.message,
    required this.copied,
    required this.total,
  });

  /// טקסט קצר להצגה למשתמש (בעברית).
  final String message;

  /// כמה קבצים הועתקו עד עכשיו.
  final int copied;

  /// סך הקבצים שצריך להעתיק.
  final int total;

  double get fraction => total == 0 ? 0 : copied / total;
}

/// תוצאת זיהוי OCR.
class OcrResult {
  const OcrResult({required this.text, required this.lineCount});

  /// הטקסט המלא (שורות מופרדות ב-\n).
  final String text;

  /// מספר השורות שזוהו.
  final int lineCount;

  bool get isEmpty => text.trim().isEmpty;
}

/// חריגה שמועלית כשמתבצעת בקשת OCR לפני התקנת המודלים.
class OcrNotInstalledException implements Exception {
  const OcrNotInstalledException();
  @override
  String toString() => 'OcrNotInstalledException: המודלים לא הותקנו עדיין';
}

/// חריגה לפלטפורמה לא נתמכת.
class OcrUnsupportedPlatformException implements Exception {
  const OcrUnsupportedPlatformException();
  @override
  String toString() =>
      'OcrUnsupportedPlatformException: OCR זמין רק ב-Windows';
}

/// חריגה כללית במהלך זיהוי.
class OcrFailureException implements Exception {
  const OcrFailureException(this.message);
  final String message;
  @override
  String toString() => 'OcrFailureException: $message';
}

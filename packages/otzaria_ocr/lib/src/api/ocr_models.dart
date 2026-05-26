/// מצבי הזמינות של מנוע ה-OCR.
enum OcrAvailability {
  /// המנוע מוכן לשימוש - הקבצים נמצאים בתיקיית הבנייה.
  ready,

  /// הפלטפורמה היא Windows אבל קבצי ה-DLL חסרים בבנייה.
  /// המתקין/חבילת ה-zip אמורים לכלול אותם תחת `<app>/ocr_runtime/`.
  missingBundledFiles,

  /// הפלטפורמה לא נתמכת (כל מה שאינו Windows, או Windows ללא החבילה הפרטית).
  unsupportedPlatform,
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

/// חריגה לפלטפורמה לא נתמכת (לא Windows, או Windows עם stub בלבד).
class OcrUnsupportedPlatformException implements Exception {
  const OcrUnsupportedPlatformException();
  @override
  String toString() =>
      'OcrUnsupportedPlatformException: OCR זמין רק ב-Windows עם החבילה הפרטית';
}

/// חריגה כאשר קבצי ה-DLL חסרים בבנייה.
class OcrMissingBundledFilesException implements Exception {
  const OcrMissingBundledFilesException();
  @override
  String toString() =>
      'OcrMissingBundledFilesException: קבצי ה-OCR חסרים בתיקיית הבנייה';
}

/// חריגה כללית במהלך זיהוי.
class OcrFailureException implements Exception {
  const OcrFailureException(this.message);
  final String message;
  @override
  String toString() => 'OcrFailureException: $message';
}

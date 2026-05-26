import 'dart:typed_data';

import 'ocr_models.dart';

/// ממשק שירות ה-OCR.
///
/// הצרכן (אוצריא) מדבר רק עם הממשק הזה. המימוש האמיתי קיים רק ב-Windows
/// (FFI מול oneocr.dll). פלטפורמות אחרות מקבלות מימוש stub שמחזיר
/// [OcrAvailability.unsupportedPlatform] וזורק חריגה ב-recognizeImage.
///
/// אין שלב התקנה ידני - הקבצים נטענים ישירות מתיקיית הבנייה
/// (`<app>/ocr_runtime/`). אם הם חסרים, [getAvailability] תחזיר
/// [OcrAvailability.missingBundledFiles].
abstract class OcrService {
  /// מחזירה את מצב הזמינות הנוכחי.
  /// בודקת פלטפורמה + קיום קבצים בתיקיית ה-runtime.
  Future<OcrAvailability> getAvailability();

  /// מבצעת זיהוי OCR על בייטים של תמונה (PNG/JPEG/וכו').
  /// ניתן לקרוא בריצוף - השירות מנהל isolate מתמשך לאתחול חד-פעמי.
  ///
  /// זורקת [OcrUnsupportedPlatformException] בפלטפורמה לא נתמכת.
  /// זורקת [OcrMissingBundledFilesException] אם הקבצים חסרים בבנייה.
  /// זורקת [OcrFailureException] על כשל בזיהוי עצמו.
  Future<OcrResult> recognizeImage(Uint8List imageBytes);

  /// משחררת משאבים (סוגרת את ה-isolate).
  Future<void> dispose();
}

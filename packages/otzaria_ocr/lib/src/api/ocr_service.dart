import 'dart:typed_data';

import 'ocr_models.dart';

/// ממשק שירות ה-OCR.
///
/// הצרכן (אוצריא) מדבר רק עם הממשק הזה. המימוש האמיתי קיים רק ב-Windows
/// (FFI מול oneocr.dll). פלטפורמות אחרות מקבלות מימוש stub שמחזיר
/// [OcrAvailability.unsupportedPlatform].
///
/// API מינימלי בכוונה - כל לוגיקת ה-PDF, החיתוך והעיבוד נמצאת בצרכן.
abstract class OcrService {
  /// מחזירה את מצב הזמינות הנוכחי.
  /// בודקת פלטפורמה + קיום קבצים בתיקייה הייעודית.
  Future<OcrAvailability> getAvailability();

  /// מתקינה את המודלים: מעתיקה את ה-DLLs מתיקיית התוכנה לתיקייה הייעודית
  /// בתוך תיקיית המשתמש. יש לקרוא רק אחרי שהמשתמש אישר.
  ///
  /// [onProgress] מקבל עדכוני התקדמות (להצגה ב-UI).
  ///
  /// זורקת [OcrUnsupportedPlatformException] בפלטפורמות שאינן Windows.
  /// זורקת חריגה אם הקבצים המקוריים לא נמצאים בתיקיית התוכנה.
  Future<void> installModels({
    void Function(OcrInstallProgress progress)? onProgress,
  });

  /// מבצעת זיהוי OCR על בייטים של תמונה (PNG/JPEG/וכו').
  /// ניתן לקרוא בריצוף - השירות מנהל isolate מתמשך לאתחול חד-פעמי.
  ///
  /// זורקת [OcrNotInstalledException] אם המודלים לא הותקנו.
  /// זורקת [OcrUnsupportedPlatformException] בפלטפורמה לא נתמכת.
  /// זורקת [OcrFailureException] על כשל בזיהוי עצמו.
  Future<OcrResult> recognizeImage(Uint8List imageBytes);

  /// משחררת משאבים (סוגרת את ה-isolate).
  Future<void> dispose();
}

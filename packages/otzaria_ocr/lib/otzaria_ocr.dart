/// Stub ציבורי של חבילת ה-OCR של אוצריא.
///
/// הצרכן (קוד אוצריא) מייבא רק את הקובץ הזה. ב-build רגיל - מקבל את ה-stub
/// שמחזיר תמיד `unsupportedPlatform`. ב-Windows עם החבילה הפרטית מותקנת
/// (דרך `pubspec_overrides.yaml`) - מקבל את המימוש האמיתי.
library;

export 'src/api/ocr_models.dart';
export 'src/api/ocr_service.dart';
export 'src/stub_ocr_service.dart' show createOcrService;

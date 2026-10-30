import 'dart:math' as math;

/// שוליים מזעריים לכל צד כשרוחב הטקסט מוגבל והחלון צר מהיעד.
const double kTextColumnMinMargin = 16;

/// רוחב מרבי לעמודת הטקסט לפי הגדרת "רוחב הטקסט".
///
/// [setting]: 0 (או שלילי, פורמט ישן) = ללא הגבלה; חיובי = רוחב יעד בפיקסלים
/// לוגיים, שמצטמצם רק כשאין מקום ב-[availableWidth].
double resolveTextColumnMaxWidth({
  required double setting,
  required double availableWidth,
}) {
  if (setting <= 0) return 0;
  final room = math.max(0.0, availableWidth - 2 * kTextColumnMinMargin);
  return math.min(setting, room);
}

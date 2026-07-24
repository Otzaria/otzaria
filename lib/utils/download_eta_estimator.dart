/// מעריך את הזמן הנותר להורדה בשיטה המקובלת בדפדפנים (Chrome/Firefox):
/// ממוצע נע של מהירות ההורדה על פני חלון זמן אחרון (ולא ממוצע גלובלי
/// מתחילת ההורדה), כדי שההערכה לא תקפוץ עקב תנודות רגעיות ברשת.
///
/// שימוש:
/// ```dart
/// final estimator = DownloadEtaEstimator();
/// // בכל נתח שמתקבל:
/// final remaining = estimator.update(
///   downloadedBytes: downloadedBytes,
///   totalBytes: totalLength,
///   now: DateTime.now(),
/// );
/// if (remaining != null) print(formatRemainingTimeHebrew(remaining));
/// ```
class DownloadEtaEstimator {
  /// [window] - חלון הזמן שעליו מחושב הממוצע הנע (ברירת מחדל: 5 שניות).
  /// [refreshInterval] - מרווח מינימלי בין רענוני הזמן המוצג (ברירת מחדל:
  ///   3 שניות). המהירות מחושבת בכל קריאה, אבל הערך המוחזר מתעדכן רק אחת
  ///   ל-[refreshInterval] כדי שהשורה לא תיראה קופצנית. בין רענונים מוחזרת
  ///   ההערכה הקודמת.
  DownloadEtaEstimator({
    this.window = const Duration(seconds: 5),
    this.refreshInterval = const Duration(seconds: 3),
  });

  final Duration window;
  final Duration refreshInterval;
  final List<_EtaSample> _samples = [];

  Duration? _lastReportedEta;
  DateTime? _lastReportTime;

  /// מעדכן עם מספר הבייטים הכולל שהורדו עד כה, ומחזיר הערכת זמן נותר.
  ///
  /// מחזיר `null` כאשר אין עדיין מספיק נתונים לחישוב מהימן (פחות משתי
  /// דגימות, או מהירות אפסית). מחזיר [Duration.zero] כשההורדה הושלמה.
  /// בין רענונים (פחות מ-[refreshInterval] מהרענון הקודם) מוחזרת ההערכה
  /// האחרונה שדווחה, כדי לשמור על תצוגה יציבה.
  ///
  /// [downloadedBytes] - סך הבייטים שהורדו עד כה (מצטבר).
  /// [totalBytes] - גודל הקובץ הכולל בבייטים.
  /// [now] - חותמת הזמן הנוכחית (מועברת כפרמטר לצורך בדיקות).
  Duration? update({
    required int downloadedBytes,
    required int totalBytes,
    required DateTime now,
  }) {
    final candidate = _computeEta(
      downloadedBytes: downloadedBytes,
      totalBytes: totalBytes,
      now: now,
    );

    // אין עדיין חישוב מהימן — שומרים על הערך הקודם (אם קיים).
    if (candidate == null) return _lastReportedEta;

    // מרעננים את הערך המוצג רק אחת ל-refreshInterval. סיום ההורדה
    // (Duration.zero) מדווח מיד כדי לא להציג זמן נותר לאחר שהסתיים.
    final due =
        _lastReportTime == null ||
        now.difference(_lastReportTime!) >= refreshInterval ||
        candidate == Duration.zero;
    if (due) {
      _lastReportedEta = candidate;
      _lastReportTime = now;
    }
    return _lastReportedEta;
  }

  /// מחשב את ההערכה הגולמית מהדגימות שבחלון, ללא שיקולי רענון.
  Duration? _computeEta({
    required int downloadedBytes,
    required int totalBytes,
    required DateTime now,
  }) {
    _samples.add(_EtaSample(now, downloadedBytes));

    // שמירת דגימות בתוך החלון בלבד — מותירים לפחות שתי דגימות לחישוב.
    final cutoff = now.subtract(window);
    while (_samples.length > 2 && _samples.first.time.isBefore(cutoff)) {
      _samples.removeAt(0);
    }

    if (_samples.length < 2) return null;

    final first = _samples.first;
    final last = _samples.last;
    final elapsedMicros = last.time.difference(first.time).inMicroseconds;
    final deltaBytes = last.bytes - first.bytes;
    if (elapsedMicros <= 0 || deltaBytes <= 0) return null;

    final remainingBytes = totalBytes - downloadedBytes;
    if (remainingBytes <= 0) return Duration.zero;

    final bytesPerMicro = deltaBytes / elapsedMicros;
    final remainingMicros = remainingBytes / bytesPerMicro;
    return Duration(microseconds: remainingMicros.round());
  }
}

class _EtaSample {
  const _EtaSample(this.time, this.bytes);
  final DateTime time;
  final int bytes;
}

/// מעצב משך זמן נותר לטקסט עברי קריא, למשל: "נותרו כ-7 דקות ו-30 שניות".
///
/// כאשר יש שעות — לא מוצגות שניות (כמו בדפדפנים, לדיוק חסר משמעות).
String formatRemainingTimeHebrew(Duration d) {
  if (d.inSeconds < 1) return 'נותרו רגעים אחרונים';

  // עיגול תמיד לחמישיית השניות הקרובה (למשל "דקה ו-5 שניות", "דקה ו-10 שניות").
  final totalSeconds = ((d.inSeconds / 5).round()) * 5;
  if (totalSeconds < 1) return 'נותרו רגעים אחרונים';

  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  String secondsLabel(int n) => n == 1 ? 'שנייה' : '$n שניות';
  String minutesLabel(int n) => n == 1 ? 'דקה' : '$n דקות';
  String hoursLabel(int n) => n == 1 ? 'שעה' : '$n שעות';

  final parts = <String>[];
  if (hours > 0) {
    parts.add(hoursLabel(hours));
    if (minutes > 0) parts.add(minutesLabel(minutes));
  } else if (minutes > 0) {
    parts.add(minutesLabel(minutes));
    if (seconds > 0) parts.add(secondsLabel(seconds));
  } else {
    parts.add(secondsLabel(seconds));
  }

  return 'נותרו כ-${parts.join(' ו-')}';
}

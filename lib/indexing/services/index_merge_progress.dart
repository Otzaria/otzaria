import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// סיומות קבצי הסגמנט של tantivy. רק הן נספרות: `meta.json`, קבצי הנעילה
/// וחותמות אוצריא אינם חלק מהמיזוג.
const _segmentExtensions = {
  '.store',
  '.idx',
  '.pos',
  '.term',
  '.fast',
  '.fieldnorm',
  '.del',
};

/// מעקב התקדמות אחרי שלב איחוד הסגמנטים (`optimize`) בסיום האינדוקס.
///
/// המנוע ממזג את כל הסגמנטים בקריאה סדרתית אחת ואינו מדווח התקדמות, אבל
/// הוא כותב את הסגמנט הממוזג לקבצים *חדשים* לצד הישנים לפני שהוא מוחק
/// אותם. לכן היחס בין גודל הקבצים החדשים לגודל הסגמנטים שנכנסים למיזוג
/// הוא ההתקדמות בפועל — בלי לגעת במנוע ובלי להאט אותו.
class IndexMergeProgress {
  IndexMergeProgress._(this._directory, this._baseline, this._totalBytes);

  final Directory _directory;
  final Set<String> _baseline;
  final int _totalBytes;
  Timer? _timer;

  /// כמה זמן בין דגימות. הדגימה מבצעת `stat` רק על הקבצים החדשים
  /// (בודדים), ולכן היא זולה גם בתיקייה עם אלפי קבצי סגמנט.
  @visibleForTesting
  static const samplingInterval = Duration(milliseconds: 700);

  /// תקרת ההתקדמות המדווחת. הסגמנט הממוזג קטן מסכום מרכיביו (מיזוג טרמים
  /// והשמטת מסמכים מחוקים), אז 100% היו נראים לפני הסיום האמיתי.
  static const _maxReportedFraction = 0.99;

  /// פותח מעקב על [indexPath] ומדווח שבר בין 0 ל-1 דרך [onProgress].
  ///
  /// מחזיר null כשאין על מה לדווח (התיקייה חסרה, או שאין סגמנטים) —
  /// במקרה כזה החיווי נשאר בלתי-מוגדר, בדיוק כמו קודם.
  static IndexMergeProgress? start(
    String indexPath,
    void Function(double fraction) onProgress,
  ) {
    final directory = Directory(indexPath);
    final baseline = <String>{};
    var totalBytes = 0;
    try {
      if (!directory.existsSync()) return null;
      for (final entry in directory.listSync(followLinks: false)) {
        if (entry is! File) continue;
        final name = p.basename(entry.path);
        if (!_segmentExtensions.contains(p.extension(name))) continue;
        baseline.add(name);
        totalBytes += entry.statSync().size;
      }
    } catch (e) {
      debugPrint('⚠️ מעקב התקדמות המיזוג לא נפתח: $e');
      return null;
    }
    if (totalBytes <= 0) return null;

    final tracker = IndexMergeProgress._(directory, baseline, totalBytes);
    tracker._timer = Timer.periodic(samplingInterval, (_) {
      final fraction = tracker._sample();
      if (fraction != null) onProgress(fraction);
    });
    return tracker;
  }

  /// גודל הקבצים שנוצרו מאז הפתיחה, כשבר מהגודל הכולל שנכנס למיזוג.
  /// null כשהדגימה נכשלה — עדיף להשאיר את החיווי האחרון על כשל רגעי.
  double? _sample() {
    var written = 0;
    try {
      for (final entry in _directory.listSync(followLinks: false)) {
        if (entry is! File) continue;
        final name = p.basename(entry.path);
        if (_baseline.contains(name)) continue;
        if (!_segmentExtensions.contains(p.extension(name))) continue;
        written += entry.statSync().size;
      }
    } catch (_) {
      return null;
    }
    return (written / _totalBytes).clamp(0.0, _maxReportedFraction);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

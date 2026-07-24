/// מדיניות שמירת גיבויים לפי דורות (Grandfather-Father-Son):
/// כל הגיבויים האחרונים, אחד לשבוע לתקופת ביניים, אחד לחודש לטווח ארוך,
/// ומעבר לכך — הגיבוי ממוזג לארכיון ונמחק.
enum RetentionProfile {
  /// 3 ימים / חודש / 3 חודשים
  economy,

  /// 7 ימים / חודשיים / שנה (ברירת מחדל)
  balanced,

  /// ללא רוטציה — שום גיבוי לא נמחק
  keepAll;

  static RetentionProfile fromName(String? name) => switch (name) {
    'economy' => RetentionProfile.economy,
    'keepAll' => RetentionProfile.keepAll,
    _ => RetentionProfile.balanced,
  };

  Duration get dailyWindow => switch (this) {
    RetentionProfile.economy => const Duration(days: 3),
    _ => const Duration(days: 7),
  };

  Duration get weeklyWindow => switch (this) {
    RetentionProfile.economy => const Duration(days: 30),
    _ => const Duration(days: 60),
  };

  Duration get monthlyWindow => switch (this) {
    RetentionProfile.economy => const Duration(days: 90),
    _ => const Duration(days: 365),
  };
}

/// תיאור קובץ גיבוי לצורך החלטת רוטציה.
class BackupEntryInfo {
  final String path;
  final DateTime timestamp;

  /// גיבוי שנוצר ידנית ע"י המשתמש — הרוטציה לא נוגעת בו לעולם.
  final bool isManual;

  const BackupEntryInfo({
    required this.path,
    required this.timestamp,
    this.isManual = false,
  });
}

class BackupRotation {
  /// מחזיר את הגיבויים שפג תוקפם לפי [profile] — מועמדים למיזוג-לארכיון
  /// ומחיקה. גיבויים ידניים לעולם אינם מוחזרים.
  static List<BackupEntryInfo> selectExpired(
    List<BackupEntryInfo> backups,
    RetentionProfile profile,
    DateTime now,
  ) {
    if (profile == RetentionProfile.keepAll) return [];

    final candidates = backups.where((b) => !b.isManual).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final expired = <BackupEntryInfo>[];
    final keptWeekly = <String>{};
    final keptMonthly = <String>{};

    for (final backup in candidates) {
      final age = now.difference(backup.timestamp);

      if (age <= profile.dailyWindow) continue;

      if (age <= profile.weeklyWindow) {
        // אחד לשבוע: הרשימה ממוינת מהחדש לישן, כך שהראשון בכל שבוע נשמר.
        final key = _weekKey(backup.timestamp);
        if (keptWeekly.add(key)) continue;
        expired.add(backup);
        continue;
      }

      if (age <= profile.monthlyWindow) {
        final key = '${backup.timestamp.year}-${backup.timestamp.month}';
        if (keptMonthly.add(key)) continue;
        expired.add(backup);
        continue;
      }

      expired.add(backup);
    }

    return expired;
  }

  /// מפתח שבוע ISO-פשוט: ימים מאז epoch חלקי 7, מיושר ליום שני.
  static String _weekKey(DateTime t) {
    final daysSinceEpoch =
        DateTime.utc(t.year, t.month, t.day).millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay;
    // 1970-01-01 היה יום חמישי; הסטה של 3 מיישרת את תחילת השבוע ליום שני.
    return ((daysSinceEpoch + 3) ~/ 7).toString();
  }
}

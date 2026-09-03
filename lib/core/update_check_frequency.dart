import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

/// תדירות בדיקת העדכונים האוטומטית בעליית התוכנה (תוכנה וספרייה כאחד).
/// בדיקות יזומות של המשתמש אינן כפופות לתדירות.
enum UpdateCheckFrequency {
  everyLaunch('always'),
  daily('daily'),
  weekly('weekly');

  const UpdateCheckFrequency(this.storageValue);

  /// הערך הנשמר ב-Settings.
  final String storageValue;

  /// ערך שמור לא מוכר נופל ל-[everyLaunch] — ההתנהגות ההיסטורית.
  static UpdateCheckFrequency fromStorage(String? value) => values.firstWhere(
    (frequency) => frequency.storageValue == value,
    orElse: () => everyLaunch,
  );
}

/// האם הגיע זמן לבדיקת עדכונים אוטומטית, לפי התדירות שנבחרה וחותמת
/// הבדיקה המוצלחת האחרונה (null = טרם נבדקה).
bool shouldCheckForUpdatesNow({
  required UpdateCheckFrequency frequency,
  required DateTime? lastSuccessfulCheck,
  required DateTime now,
}) {
  if (frequency == UpdateCheckFrequency.everyLaunch) return true;
  if (lastSuccessfulCheck == null) return true;
  final elapsed = now.difference(lastSuccessfulCheck);
  // חותמת עתידית (שעון שהוזז אחורה) אסור שתחסום בדיקות לתמיד.
  if (elapsed.isNegative) return true;
  return switch (frequency) {
    UpdateCheckFrequency.everyLaunch => true,
    UpdateCheckFrequency.daily => elapsed >= const Duration(days: 1),
    UpdateCheckFrequency.weekly => elapsed >= const Duration(days: 7),
  };
}

/// התדירות שנבחרה בהגדרות.
UpdateCheckFrequency currentUpdateCheckFrequency() =>
    UpdateCheckFrequency.fromStorage(
      Settings.getValue<String>(SettingsRepository.keyUpdateCheckFrequency),
    );

/// האם בדיקה אוטומטית שחותמתה נשמרת תחת [lastCheckKey] נדרשת כעת.
bool isAutoUpdateCheckDue(String lastCheckKey, {DateTime? now}) =>
    shouldCheckForUpdatesNow(
      frequency: currentUpdateCheckFrequency(),
      lastSuccessfulCheck: DateTime.tryParse(
        Settings.getValue<String>(lastCheckKey) ?? '',
      ),
      now: now ?? DateTime.now(),
    );

/// רושם בדיקה מוצלחת תחת [lastCheckKey]. בדיקות כושלות אינן נרשמות
/// בכוונה — כך הניסיון הבא מתבצע כבר בעלייה הבאה.
Future<void> recordSuccessfulUpdateCheck(String lastCheckKey) =>
    Settings.setValue<String>(lastCheckKey, DateTime.now().toIso8601String());

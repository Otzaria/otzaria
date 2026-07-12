import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';

/// שירות לניהול הצגת פופאפ פרסומת
class AdPopupService {
  static const String _keyDontShowAgain = 'ad_popup_dont_show_again';
  static const String _keyRemindLater = 'ad_popup_remind_later_timestamp';
  static const String _keyLastCampaignShow = 'ad_popup_last_campaign_show';

  /// ימי קמפיין: בימים אלו הפופאפ יוצג גם למי שביטל אותו — פעם ביום לפחות.
  /// לשינוי הימים ערוך רשימה זו. כל תאריך בפורמט [שנה, חודש, יום].
  static const List<List<int>> _campaignDays = [
    [2026, 7, 12], // ראשון
    [2026, 7, 13], // שני
    [2026, 7, 14], // שלישי
    [2026, 7, 15], // רביעי
    [2026, 7, 16], // חמישי
  ];

  static bool _isCampaignDay(DateTime now) {
    return _campaignDays
        .any((d) => now.year == d[0] && now.month == d[1] && now.day == d[2]);
  }

  /// טווח התאריכים (כולל) שבו שורת המצ'ינג מוצגת ומהבהבת. מחוץ לטווח היא נסתרת.
  /// לשינוי — ערוך את שני התאריכים. פורמט: [שנה, חודש, יום].
  static const List<int> _matchingStart = [2026, 7, 4];
  static const List<int> _matchingEnd = [2026, 7, 8];

  /// האם שורת המצ'ינג פעילה כעת (לפי הטווח שלמעלה)
  static bool get isMatchingBannerActive {
    // בבנייה של דיבאג מציגים תמיד, ללא תלות בתאריך (לא משפיע על release)
    if (kDebugMode) return true;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start =
        DateTime(_matchingStart[0], _matchingStart[1], _matchingStart[2]);
    final end = DateTime(_matchingEnd[0], _matchingEnd[1], _matchingEnd[2]);
    return !today.isBefore(start) && !today.isAfter(end);
  }

  static String _dateKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  /// בדיקה האם להציג את הפופאפ
  static Future<bool> shouldShowAd() async {
    final now = DateTime.now();

    final dontShowAgain = Settings.getValue<bool>(_keyDontShowAgain) ?? false;

    final remindLaterTimestamp = Settings.getValue<int>(_keyRemindLater);
    final remindLaterActive = remindLaterTimestamp != null &&
        now.isBefore(DateTime.fromMillisecondsSinceEpoch(remindLaterTimestamp));

    // המשתמש השתיק את הפופאפ (לצמיתות או זמנית)
    if (dontShowAgain || remindLaterActive) {
      // בימי קמפיין עוקפים את ההשתקה, אך פעם אחת ביום בלבד
      if (_isCampaignDay(now) &&
          Settings.getValue<String>(_keyLastCampaignShow) != _dateKey(now)) {
        await Settings.setValue<String>(_keyLastCampaignShow, _dateKey(now));
        return true;
      }
      return false;
    }

    return true;
  }

  /// סימון "אל תציג שוב"
  static Future<void> setDontShowAgain() async {
    await Settings.setValue<bool>(_keyDontShowAgain, true);
  }

  /// סימון "תזכיר לי מאוחר יותר" (ברירת מחדל: 7 ימים)
  static Future<void> setRemindLater({int days = 7}) async {
    final remindDate = DateTime.now().add(Duration(days: days));
    await Settings.setValue<int>(
        _keyRemindLater, remindDate.millisecondsSinceEpoch);
  }

  /// איפוס ההגדרות (לצורך בדיקה)
  static Future<void> reset() async {
    await Settings.setValue<bool?>(_keyDontShowAgain, null);
    await Settings.setValue<int?>(_keyRemindLater, null);
    await Settings.setValue<String?>(_keyLastCampaignShow, null);
  }
}

import 'package:flutter_settings_screens/flutter_settings_screens.dart';

/// שירות לניהול הצגת פופאפ פרסומת
class AdPopupService {
  static const String _keyDontShowAgain = 'ad_popup_dont_show_again';
  static const String _keyRemindLater = 'ad_popup_remind_later_timestamp';

  /// בדיקה האם להציג את הפופאפ
  static Future<bool> shouldShowAd() async {
    // אם המשתמש בחר "אל תציג שוב"
    final dontShowAgain = Settings.getValue<bool>(_keyDontShowAgain) ?? false;
    if (dontShowAgain) {
      return false;
    }

    // בדיקה אם המשתמש בחר "תזכיר לי מאוחר יותר"
    final remindLaterTimestamp = Settings.getValue<int>(_keyRemindLater);
    if (remindLaterTimestamp != null) {
      final remindLaterDate = DateTime.fromMillisecondsSinceEpoch(
        remindLaterTimestamp,
      );
      final now = DateTime.now();

      // אם עדיין לא עבר הזמן - לא להציג
      if (now.isBefore(remindLaterDate)) {
        return false;
      }
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
      _keyRemindLater,
      remindDate.millisecondsSinceEpoch,
    );
  }

  /// איפוס ההגדרות (לצורך בדיקה)
  static Future<void> reset() async {
    await Settings.setValue<bool?>(_keyDontShowAgain, null);
    await Settings.setValue<int?>(_keyRemindLater, null);
  }
}

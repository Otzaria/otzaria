import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/windowing/window_bus.dart';

/// סנכרון הגדרות **חי** בין חלונות אוצריא.
///
/// ## למה בכלל, ולמה לא דרך המאגר המשותף
///
/// חלון משני מקבל שורש Hive פרטי, ולכן `app_preferences` שלו הוא קובץ
/// נפרד שנזרע פעם אחת בפתיחה. זריעה חד-פעמית פירושה שהחלפת ערכת נושא או
/// גודל גופן בחלון אחד לא נראית בשני — והמשתמש רואה שני חלונות של אותה
/// תוכנה נראים שונה.
///
/// ניתוב ההגדרות לבעלים, כמו ההיסטוריה והסימניות, **אינו** אפשרי כאן:
/// `Settings.getValue` סינכרוני ונקרא מתוך `build`, מאות פעמים בפריים.
/// בקשת אפיק לכל קריאה כזו אינה באה בחשבון.
///
/// ## המודל: כתיבה מקומית + שידור
///
/// כל חלון ממשיך לכתוב ל-box שלו — קריאה נשארת סינכרונית וחינמית. אחרי
/// הכתיבה הערך **משודר**, ושאר החלונות מחילים אותו על ה-box שלהם ומרעננים
/// את ה-state שנגזר ממנו.
///
/// ⚠️ אין כאן פתרון להתנגשויות, ובמכוון: הגדרה היא ערך יחיד שהמשתמש שינה
/// בחלון אחד, ואין "מיזוג" של שתי בחירות. האחרון קובע, וזה גם מה שהמשתמש
/// מצפה שיקרה.
class SettingsSync {
  SettingsSync._();

  static final SettingsSync instance = SettingsSync._();

  /// סוג הבקשה באפיק.
  static const String requestChanged = 'settingChanged';

  /// "כל ההגדרות נמחקו" — הודעה אחת במקום אחת לכל מפתח.
  ///
  /// איפוס הגדרות מוחק מאות מפתחות, ושידור נפרד לכל אחד מהם היה פותח
  /// `ReceivePort` פר-מפתח פר-חלון.
  static const String requestReset = 'settingsReset';

  /// ⚠️ debounce לכל מפתח. גרירת מחוון גודל גופן כותבת עשרות פעמים
  /// בשנייה, וכל כתיבה הייתה שידור לשלושה חלונות. הערך האחרון הוא היחיד
  /// שמעניין.
  static const Duration _coalesce = Duration(milliseconds: 150);

  /// הפונקציה שכותבת ערך ל-box המקומי. מוזרקת על ידי `HiveCache`, כדי
  /// שהקובץ הזה לא יהיה תלוי בשכבת הנתונים.
  Future<void> Function(String key, Object? value)? applyLocally;

  /// הפונקציה שמוחקת את כל ההגדרות המקומיות. מוזרקת על ידי `HiveCache`.
  Future<void> Function()? clearLocally;

  final Map<String, Timer> _pending = {};
  final Map<String, Object?> _latest = {};

  final StreamController<String> _changes = StreamController<String>.broadcast(
    sync: true,
  );

  /// מפתחות שהשתנו **בחלון אחר**. מי שמאזין צריך לטעון מחדש את ה-state
  /// שנגזר מהם.
  Stream<String> get changes => _changes.stream;

  /// ⚠️ מונע לופ. החלת שינוי מרוחק כותבת ל-box, והכתיבה הזו עוברת דרך
  /// אותם setters — בלי הדגל היא הייתה משודרת בחזרה, לנצח.
  bool _applyingRemote = false;

  /// מפתחות שהם **מצב של חלון** ולא הגדרה של התוכנה, ולכן אינם מסונכרנים.
  ///
  /// ⚠️ גבולות החלון ומצב המיקסום נשמרים באותו box, אבל שידורם היה מזיז
  /// חלון אחד בכל פעם שהמשתמש מזיז את השני. `WindowPersistence` כבר אינו
  /// שומר אותם בחלון משני, וזו שכבת ההגנה השנייה — והמקום שאליו יתווסף כל
  /// מפתח פר-חלון עתידי.
  static const Set<String> _windowScopedPrefixes = {
    'window_bounds_',
    'window_is_',
  };

  /// ⚠️ מסך מלא הוא מצב חלון שאינו נושא את התחילית. שידורו הפשיט את סרגל
  /// הכותרת בחלונות האחרים בלי ששום מעבר נייטיב קרה, ובלי דרך לצאת.
  static const Set<String> _windowScopedKeys = {'key-is-fullscreen'};

  static bool _isWindowScoped(String key) =>
      _windowScopedKeys.contains(key) ||
      _windowScopedPrefixes.any(key.startsWith);

  /// נקרא מכל setter של `HiveCache` אחרי הכתיבה המקומית.
  void broadcastChange(String key, Object? value) {
    // בפלטפורמה בלי ריבוי חלונות אין למי לשדר, וכל שמירת הגדרה שילמה
    // `Timer` ו-`ReceivePort` בשביל יכולת שאינה קיימת שם.
    if (!MultiWindowService.isSupported) return;
    if (_applyingRemote) return;
    if (_isWindowScoped(key)) return;
    if (!_isSyncable(value)) return;
    _latest[key] = value;
    _pending[key]?.cancel();
    _pending[key] = Timer(_coalesce, () {
      _pending.remove(key);
      final latest = _latest.remove(key);
      WindowBus.instance.broadcast({
        'type': requestChanged,
        'key': key,
        'value': latest,
      });
    });
  }

  /// מודיע לשאר החלונות שכל ההגדרות אופסו.
  ///
  /// ⚠️ בלי זה החלון השני ממשיך עם הערכים הישנים בזיכרון וכותב אותם בחזרה
  /// בשמירה הבאה — כלומר האיפוס מתבטל מעצמו.
  void broadcastReset() {
    if (!MultiWindowService.isSupported) return;
    if (_applyingRemote) return;
    // הכתיבות התלויות מתייתרות: הן עומדות להימחק בכל מקרה.
    dispose();
    WindowBus.instance.broadcast({'type': requestReset});
  }

  /// רק ערכים שעוברים את גבול ה-isolate כפי שהם.
  ///
  /// `SendPort` מעביר גרפים של אובייקטים, אבל ערך שאינו פרימיטיבי יגיע
  /// כעותק שאינו זהה למה ש-`CacheProvider` יודע לקרוא. שאר המפתחות פשוט
  /// אינם מסונכרנים, וזה עדיף על ערך שנכתב שבור.
  static bool _isSyncable(Object? value) =>
      value == null ||
      value is bool ||
      value is num ||
      value is String ||
      (value is List && value.every((e) => e is String));

  /// מטפל בהודעת שינוי שהגיעה מחלון אחר. מחזיר null כשהבקשה אינה שלנו.
  Future<Object?> handleRequest(Map<String, dynamic> request) async {
    if (request['type'] == requestReset) return _applyReset();
    if (request['type'] != requestChanged) return null;
    final key = request['key'];
    if (key is! String) return null;

    final apply = applyLocally;
    if (apply == null) return false;
    _applyingRemote = true;
    try {
      await apply(key, request['value']);
    } catch (e) {
      debugPrint('SettingsSync: failed to apply $key: $e');
      return false;
    } finally {
      _applyingRemote = false;
    }
    _changes.add(key);
    return true;
  }

  /// מוחק את ההגדרות המקומיות בעקבות איפוס בחלון אחר, ומרענן את ה-state.
  Future<Object?> _applyReset() async {
    final clear = clearLocally;
    if (clear == null) return false;
    // שידור בהמתנה היה כותב ערך ישן בחזרה אחרי המחיקה.
    dispose();
    _applyingRemote = true;
    try {
      await clear();
    } catch (e) {
      debugPrint('SettingsSync: failed to apply reset: $e');
      return false;
    } finally {
      _applyingRemote = false;
    }
    // ה-key הריק הוא "הכול" — המאזין היחיד טוען מחדש בכל מקרה.
    _changes.add('');
    return true;
  }

  /// ⚠️ חובה בסגירת חלון: טיימר שנשאר משדר שינוי אחרי שהחלון נעלם.
  void dispose() {
    for (final timer in _pending.values) {
      timer.cancel();
    }
    _pending.clear();
    _latest.clear();
  }
}

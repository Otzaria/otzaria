import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/tabs/models/tab.dart';

/// מסנכרן את רשימת הטאבים הפתוחים ל-Jump List של שורת המשימות ב-Windows.
///
/// כל פריט ב-Jump List מריץ את אוצריא עם `otzaria://open/tab/<index>`, וה-runner
/// הנייטיב מעביר זאת למופע החי (single-instance) שמחליף לטאב המבוקש. הסנכרון
/// מתבצע רק ב-Windows; בשאר הפלטפורמות הקריאות הן no-op.
class WindowsJumpListService {
  static const MethodChannel _channel = MethodChannel('otzaria/jumplist');

  /// כותרות הטאבים שנשלחו לאחרונה — מונע קריאות נייטיב מיותרות כשהמצב לא השתנה.
  List<String>? _lastTitles;

  bool get _isSupported => !kIsWeb && Platform.isWindows;

  /// מעדכן את ה-Jump List לרשימת הטאבים הנתונה (לפי הסדר). שולח רק כאשר
  /// הכותרות או סדרן השתנו מאז הקריאה הקודמת.
  Future<void> sync(List<OpenedTab> tabs) async {
    if (!_isSupported) return;

    final titles = tabs.map((tab) => tab.title).toList(growable: false);
    if (listEquals(_lastTitles, titles)) return;

    try {
      final ok = await _channel.invokeMethod<bool>('updateTabs', {
        'titles': titles,
      });
      // מעדכנים את הזיכרון רק בהצלחה — אחרת אותה רשימה תישלח שוב בשינוי הבא
      // במקום להיתקע על מצב שלא נכתב בפועל.
      if (ok == true) {
        _lastTitles = titles;
      }
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('עדכון ה-Jump List נכשל: $error\n$stackTrace');
      }
    }
  }
}

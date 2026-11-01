import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:window_manager/window_manager.dart';

/// מעדכן את כותרת החלון לפי הכרטיסיה הפעילה בו, כמו בדפדפן. הכותרת אינה
/// נראית בחלון עצמו (סרגל כותרת מותאם), אלא בשורת המשימות וב-Alt+Tab.
///
/// ⚠️ **הכותרת אינה מזהה יציב.** `main.cpp` מזהה את החלון הראשי דרך מאפיין
/// חלון (`OtzariaMainWindow`), ולא דרך הכותרת.
class WindowTitleSync {
  WindowTitleSync({Future<void> Function(String title)? setTitle})
    : _setTitle = setTitle ?? windowManager.setTitle;

  /// הכותרת של החלון הראשי; חלון Dart נוסף קושר מופע משלו ב-[bind].
  static final WindowTitleSync current = WindowTitleSync();

  static final Expando<WindowTitleSync> _perWindow = Expando('WindowTitleSync');

  /// חלון באותו isolate קושר מופע משלו למפתחות שלו.
  static void bind(AppWindowKeys keys, WindowTitleSync sync) =>
      _perWindow[keys] = sync;

  static void unbind(AppWindowKeys keys, WindowTitleSync sync) {
    if (identical(_perWindow[keys], sync)) _perWindow[keys] = null;
  }

  /// המופע של החלון ש-[context] יושב בו; בלי קשירה — [current].
  static WindowTitleSync of(BuildContext context) =>
      _perWindow[AppWindowKeys.of(context)] ?? current;

  final Future<void> Function(String title) _setTitle;

  /// שם התוכנה, שנשאר בסוף הכותרת בכל מצב.
  ///
  /// מיקום בסוף ולא בהתחלה: שורת המשימות ו-Alt+Tab חותכים כותרות ארוכות
  /// **מהסוף**, ולכן מה שמזהה את החלון חייב לבוא ראשון.
  static const String appName = 'אוצריא';

  static bool get _isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// הכותרת שנשלחה לאחרונה לחלון הזה — מונע קריאת ערוץ בכל שינוי state.
  String? _lastSent;

  /// בונה את הכותרת לכרטיסיה הפעילה.
  ///
  /// [activeTabTitle] הוא null כשאין כרטיסיות או כשהמשתמש במסך אחר.
  @visibleForTesting
  static String titleFor(String? activeTabTitle, {int tabCount = 0}) {
    final trimmed = activeTabTitle?.trim();
    if (trimmed == null || trimmed.isEmpty) return appName;
    // מספר הכרטיסיות בסוגריים כמו בדפדפן, ורק כשיש יותר מאחת — בכרטיסיה
    // בודדת זה רק רעש.
    final suffix = tabCount > 1 ? ' ($tabCount)' : '';
    return '$trimmed$suffix — $appName';
  }

  /// כמו [sync], ורק בפלטפורמות שיש בהן כותרת חלון.
  Future<void> syncIfSupported(
    String? activeTabTitle, {
    int tabCount = 0,
  }) async {
    if (!_isSupported) return;
    await sync(activeTabTitle, tabCount: tabCount);
  }

  /// מעדכן את כותרת החלון הזה, אם היא שונה מזו שנשלחה אליו.
  Future<void> sync(String? activeTabTitle, {int tabCount = 0}) async {
    final title = titleFor(activeTabTitle, tabCount: tabCount);
    if (title == _lastSent) return;
    _lastSent = title;
    try {
      await _setTitle(title);
    } catch (e) {
      // כותרת אינה שווה קריסה, ואינה שווה גם הודעה למשתמש.
      debugPrint('setTitle failed: $e');
    }
  }
}

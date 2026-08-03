import 'package:flutter/widgets.dart';
import 'package:otzaria/settings/l10n/settings_language.dart';

/// מפיץ את שפת ההגדרות לתת-העץ של מסך ההגדרות.
///
/// מחוץ למסך ההגדרות אין scope, ולכן [languageOf] מחזירה עברית — כך שאר
/// האפליקציה נשארת עברית ללא תלות בבחירת המשתמש.
class SettingsTextScope extends InheritedWidget {
  const SettingsTextScope({
    super.key,
    required this.language,
    required super.child,
  });

  final SettingsLanguage language;

  /// שפת ההגדרות התקפה ב-[context]; עברית כשאין scope.
  static SettingsLanguage languageOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SettingsTextScope>()
          ?.language ??
      SettingsLanguage.source;

  /// כמו [languageOf] אך ללא רישום תלות — לשימוש מחוץ ל-build,
  /// למשל בפתיחת דיאלוג מתוך callback.
  static SettingsLanguage languageOfStatic(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SettingsTextScope>()?.language ??
      SettingsLanguage.source;

  @override
  bool updateShouldNotify(SettingsTextScope oldWidget) =>
      language != oldWidget.language;
}

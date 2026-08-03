import 'package:flutter/widgets.dart';
import 'package:otzaria/settings/l10n/settings_catalogs.g.dart';
import 'package:otzaria/settings/l10n/settings_language.dart';
import 'package:otzaria/settings/l10n/settings_text_scope.dart';

/// בונה את מפתח הקטלוג. הקשר נוסף מפריד מחרוזות עבריות זהות שתרגומן שונה,
/// למשל 'דף' בהדפסה מול 'דף' בגמרא.
String buildSettingsTextKey(String hebrew, [String? context]) =>
    context == null || context.isEmpty ? hebrew : '$hebrew|$context';

/// מתרגם טקסט של מסך ההגדרות. המקור העברי הוא גם המפתח, כדי שחיפוש רגיל
/// בקוד לפי מה שכתוב על המסך ימשיך למצוא את מקום השימוש.
///
/// [hebrew] - הטקסט העברי, משמש כמפתח ומוצג כמות שהוא בשפת המקור.
/// [context] - מבחין בין מחרוזות עבריות זהות בעלות תרגום שונה.
/// [args] - ערכים ל-placeholders בפורמט `{name}`.
/// [catalog] - קטלוג חלופי, לבדיקות בלבד.
///
/// כשחסר תרגום מוחזר המקור העברי; הבדיקות תופסות מפתח חסר.
String resolveSettingsText(
  String hebrew, {
  required SettingsLanguage language,
  String? context,
  Map<String, Object?>? args,
  Map<String, String>? catalog,
}) {
  final entries = catalog ?? kSettingsCatalogs[language.code];
  final text = language == SettingsLanguage.source || entries == null
      ? hebrew
      : entries[buildSettingsTextKey(hebrew, context)] ??
            entries[hebrew] ??
            hebrew;
  return _applyArgs(text, args);
}

String _applyArgs(String text, Map<String, Object?>? args) {
  if (args == null || args.isEmpty) return text;
  var result = text;
  for (final entry in args.entries) {
    result = result.replaceAll('{${entry.key}}', '${entry.value}');
  }
  return result;
}

extension SettingsTextExtension on BuildContext {
  /// מתרגם טקסט לשפת ההגדרות הנוכחית. ראה [resolveSettingsText].
  String settingsText(
    String hebrew, {
    String? context,
    Map<String, Object?>? args,
  }) => resolveSettingsText(
    hebrew,
    language: SettingsTextScope.languageOf(this),
    context: context,
    args: args,
  );
}

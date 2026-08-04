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
  final isSourceLanguage = language == SettingsLanguage.source;
  final text = isSourceLanguage || entries == null
      ? hebrew
      : entries[buildSettingsTextKey(hebrew, context)] ??
            entries[hebrew] ??
            hebrew;
  // הבידוד נקבע לפי התרגום עצמו — לפני הכנסת הערכים — אחרת ערך עברי
  // בתוך משפט אנגלי היה גורם לבידוד המשפט כולו.
  return _applyArgs(
    _isolateBidi(text, isSourceLanguage),
    args,
    isSourceLanguage,
  );
}

// ── בידוד כיווניות ───────────────────────────────────────────────────────────
// בהקשר LTR, פיסוק בקצה טקסט עברי הוא תו נייטרלי ולכן מקבל את כיוון הפסקה
// ולא את כיוון הטקסט — נקודה בסוף משפט עברי "בורחת" לצד הנגדי. בידוד
// (isolate) מצמיד לתווים האלה את כיוון הטקסט שהם שייכים לו.

/// First Strong Isolate — הכיוון נגזר מהתו החזק הראשון שבתוכו.
const String _fsi = '\u2068';

/// Pop Directional Isolate — סוגר [_fsi].
const String _pdi = '\u2069';

final RegExp _hebrewLetter = RegExp(r'[֐-׿]');

/// עוטף ערך דינמי (שם ספר, תיקייה) בבידוד, כדי שהפיסוק סביבו במשפט
/// המתורגם לא יתהפך.
String _isolateArg(String value) =>
    _hebrewLetter.hasMatch(value) ? '$_fsi$value$_pdi' : value;

/// עוטף טקסט שנשאר עברי בשפה שאינה עברית — כלומר נפל ל-fallback, או תוכן
/// שאינו מתורגם בכוונה. בשפת המקור אין צורך: כיוון הפסקה כבר RTL.
String _isolateBidi(String text, bool isSourceLanguage) =>
    isSourceLanguage || !_hebrewLetter.hasMatch(text)
    ? text
    : '$_fsi$text$_pdi';

String _applyArgs(
  String text,
  Map<String, Object?>? args,
  bool isSourceLanguage,
) {
  if (args == null || args.isEmpty) return text;
  var result = text;
  for (final entry in args.entries) {
    final value = '${entry.value}';
    result = result.replaceAll(
      '{${entry.key}}',
      isSourceLanguage ? value : _isolateArg(value),
    );
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

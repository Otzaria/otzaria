import 'package:flutter/widgets.dart';
import 'package:otzaria/settings/l10n/settings_text_scope.dart';

/// עוטף תוכן של דיאלוג בשפה ובכיווניות של מסך ההגדרות.
///
/// דיאלוג נבנה ב-Overlay של ה-Navigator ולא בתת-העץ שפתח אותו, ולכן אינו
/// יורש את [SettingsTextScope] ואת ה-`Directionality` המקומיים. בלי העטיפה
/// הזו דיאלוג שנפתח מההגדרות באנגלית היה מוצג עברית ו-RTL.
///
/// השפה נלקחת מה-scope של מי שפתח את הדיאלוג. ה-scope של האפליקציה עוטף את
/// כולה, ולכן גם מחוץ להגדרות הדיאלוג מקבל את שפת הממשק ואת הכיוון שלה.
Widget wrapWithSettingsScope(BuildContext context, Widget child) {
  final language = SettingsTextScope.languageOfStatic(context);
  return Directionality(
    textDirection: language.textDirection,
    child: SettingsTextScope(language: language, child: child),
  );
}

/// גרסת [wrapWithSettingsScope] לשימוש כ-`builder` של `showDialog`.
///
/// [context] הוא ה-context שפותח את הדיאלוג — ממנו נלקחת השפה.
WidgetBuilder settingsDialogBuilder(
  BuildContext context,
  WidgetBuilder builder,
) {
  final language = SettingsTextScope.languageOfStatic(context);
  return (dialogContext) => Directionality(
    textDirection: language.textDirection,
    child: SettingsTextScope(
      language: language,
      child: Builder(builder: builder),
    ),
  );
}

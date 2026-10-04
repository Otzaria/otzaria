/// התוספים שנארזים בחבילות ההתקנה: מזהה החנות (מכתובת עמוד התוסף באתר)
/// ממופה אל מזהה המניפסט (`id` שב-manifest.json). ה-workflow מוריד לפי מזהה
/// החנות, והאפליקציה מאמתת שהארכיון מצהיר בדיוק על מזהה המניפסט — ארכיון
/// שהוחלף או שאינו ברשימה לא יירשם (docs/bundled_plugins.md).
///
/// סינון פלטפורמות אופציונלי: `@` אחרי מזהה המניפסט ואחריו שמות
/// `Platform.operatingSystem` מופרדים בפסיקים, למשל
/// `'com.x.y@windows,linux'`. בלי `@` — התוסף נארז בכל הפלטפורמות.
///
/// זוג אחד בכל שורה. סקריפטי ההורדה קוראים את הרשימה הזו, ולכן הפורמט חייב
/// להישאר `'מזהה-חנות': 'מזהה-מניפסט[@פלטפורמות]',` בשורה אחת.
const bundledPlugins = <String, String>{
  '6a9342ce60ff32edf765ec31': 'com.otzaria_word_editor.superdoc',
  '6a313ffbb3f53b688248fa40': 'com.otzaria.kidush-hachodesh',
  '6a01cd9954ae49eaed8dab2a': 'otzaria.plugins_directory',
};

/// תוספים מהרשימה שנרשמים רק כש-https://otzaria.org/ עונה 200 — בלי רשת
/// אין בהם תועלת. כשאין תשובה כזו הרישום נדחה לעלייה הבאה.
const networkGatedBundledPluginIds = <String>{'otzaria.plugins_directory'};

/// מזהי המניפסט המותרים בפלטפורמה [platform] (ערך `Platform.operatingSystem`).
Set<String> bundledPluginIdsForPlatform(
  String platform, [
  Map<String, String> plugins = bundledPlugins,
]) => {
  for (final value in plugins.values)
    if (!value.contains('@') ||
        value.split('@')[1].split(',').contains(platform))
      value.split('@').first,
};

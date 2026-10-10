import 'system_font_locator_stub.dart'
    if (dart.library.io) 'system_font_locator_io.dart'
    as impl;

/// מאתר את קבצי הגופנים (ttf/otf) המותקנים במערכת.
///
/// בדסקטופ: סריקת תיקיות הגופנים המוכרות, ובווינדוס גם רישום ה-registry —
/// שמכסה גופנים שמותקנים מחוץ לתיקיות (למשל הגופנים הפרטיים של Office).
/// ב-web מוחזרת רשימה ריקה.
class SystemFontLocator {
  SystemFontLocator._();

  /// עם [family]: רק קבצים ששמם או שם הרישום שלהם מזכירים את המשפחה.
  static List<String> installedFontPaths([String? family]) =>
      impl.installedFontPaths(family);

  /// בלי רישיות, רווחים וסימנים: "FrankRuehlCLM-Bold" מזכיר את "Frank Ruehl CLM".
  static bool nameMentionsFamily(String name, String family) {
    final key = _compact(family);
    return key.isNotEmpty && _compact(name).contains(key);
  }

  static String _compact(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
}

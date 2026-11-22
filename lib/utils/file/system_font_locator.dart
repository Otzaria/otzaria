import 'system_font_locator_stub.dart'
    if (dart.library.io) 'system_font_locator_io.dart'
    as impl;

/// מאתר את קבצי הגופנים (ttf/otf, ואוספי ttc/otc) המותקנים במערכת.
///
/// בדסקטופ: סריקת תיקיות הגופנים המוכרות, ובווינדוס גם רישום ה-registry —
/// שמכסה גופנים שמותקנים מחוץ לתיקיות (למשל הגופנים הפרטיים של Office).
/// ב-web מוחזרת רשימה ריקה.
class SystemFontLocator {
  SystemFontLocator._();

  /// עם [family]: רק קבצים ששמם או שם הרישום שלהם מזכירים את המשפחה.
  static List<String> installedFontPaths([String? family]) =>
      impl.installedFontPaths(family);

  /// האם [path] הוא אוסף גופנים (`.ttc`/`.otc`) עם כמה faces בקובץ אחד.
  static bool isCollectionFile(String path) => impl.isCollectionFile(path);

  /// נתיב לקובץ גופן עצמאי של face מספר [index] באוסף [path] (מחולץ למטמון
  /// בפעם הראשונה). [index] ריק: [path] עצמו, בלי קריאה לדיסק.
  static String faceFilePath(String path, int? index) =>
      impl.faceFilePath(path, index);

  /// תיקיית הגופנים שהמשתמש מייבא (iOS בלבד), או null בפלטפורמה אחרת.
  static String? get userFontsDirectory => impl.userFontsDirectory();

  /// בלי רישיות, רווחים וסימנים: "FrankRuehlCLM-Bold" מזכיר את "Frank Ruehl CLM".
  static bool nameMentionsFamily(String name, String family) {
    final key = _compact(family);
    return key.isNotEmpty && _compact(name).contains(key);
  }

  static String _compact(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
}

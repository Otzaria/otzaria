import 'dart:io';

import 'package:path/path.dart' as p;

/// קובץ החרגה אופציונלי לכל תוסף. הצבת `.otzignore` בשורש תיקיית התוסף
/// משאירה קבצים *מחוץ* ל-`.otzplugin` הנבנה (מקורות גולמיים, source maps,
/// נתונים גדולים שאין בהם צורך בזמן ריצה וכו'). התחביר זהה ל-`.gitignore`:
///   - תבנית אחת בכל שורה; שורות ריקות ושורות שמתחילות ב-`#` מתעלמים מהן
///   - `*` מתאים בתוך מקטע נתיב, `**` חוצה מקטעים, `?` תו בודד
///   - `/` בסוף תבנית = תיקייה (וכל מה שתחתיה)
///   - תבנית ללא `/` מתאימה לפי שם הקובץ בכל עומק (למשל `*.map`)
///   - תבנית עם `/` מעוגנת לשורש התוסף (למשל `src/dev.js`)
///   - `!` בתחילת שורה מחזיר נתיב שהוחרג ע"י תבנית קודמת
///
/// התחביר והסמנטיקה זהים למימוש ה-JS ב-Action הרשמי
/// (`otzaria-plugin-validator/src/ignore.js`), כדי שהאריזה המקומית וה-CI
/// יחריגו בדיוק את אותם הקבצים.
const String kOtzignoreFilename = '.otzignore';

/// תווים בעלי משמעות ב-RegExp שיש לברוח מהם כשהם מופיעים מילולית בתבנית.
final RegExp _specialChar = RegExp(r'[.+^${}()|[\]\\]');

/// כלל מהודר יחיד: האם הוא שלילה (`!`), וה-RegExp שמתאים לנתיב יחסי.
class _IgnoreRule {
  final bool negate;
  final RegExp re;
  const _IgnoreRule(this.negate, this.re);
}

/// מַתאם `.otzignore` — מחליט אם נתיב יחסי (עם מפרידי `/`) מוחרג.
class PluginIgnore {
  final List<_IgnoreRule> _rules;

  /// האם הקובץ כולל כללי `!` (החזרה). כשאין — אפשר לגזום תיקיות מוחרגות
  /// שלמות בלי לפספס קובץ-צאצא שצריך להיכלל בכל זאת.
  final bool hasNegation;

  const PluginIgnore._(this._rules, this.hasNegation);

  /// האם [relPath] (מנורמל למפרידי `/`) מוחרג. הכלל האחרון שמתאים קובע, כך
  /// ש-`!pattern` מאוחר מחזיר החרגה קודמת.
  bool ignores(String relPath) {
    var excluded = false;
    for (final r in _rules) {
      if (r.re.hasMatch(relPath)) excluded = !r.negate;
    }
    return excluded;
  }

  /// האם הכלל *האחרון* שמתאים ל-[relPath] הוא `!` (החזרה). מאפשר ל-`!` מפורש
  /// לגבור על החרגת קבצי/תיקיות המטא-דאטה באריזה.
  bool reIncludes(String relPath) {
    var negated = false;
    for (final r in _rules) {
      if (r.re.hasMatch(relPath)) negated = r.negate;
    }
    return negated;
  }

  /// מספר הכללים הפעילים (ללא הערות ושורות ריקות).
  int get ruleCount => _rules.length;

  /// בונה מַתאם משורות `.otzignore`.
  static PluginIgnore fromLines(Iterable<String> lines) {
    final rules = <_IgnoreRule>[];
    for (final line in lines) {
      final rule = _compileLine(line);
      if (rule != null) rules.add(rule);
    }
    return PluginIgnore._(rules, rules.any((r) => r.negate));
  }

  /// טוען `.otzignore` משורש תוסף. בהיעדר הקובץ — מַתאם שלא מחריג דבר.
  static PluginIgnore load(String rootDir) {
    final file = File(p.join(rootDir, kOtzignoreFilename));
    if (!file.existsSync()) return const PluginIgnore._(<_IgnoreRule>[], false);
    return fromLines(file.readAsStringSync().split(RegExp(r'\r?\n')));
  }
}

/// מהדר שורת תבנית בודדת לכלל, או `null` עבור הערה/שורה ריקה.
_IgnoreRule? _compileLine(String rawLine) {
  var pat = rawLine.trim();
  if (pat.isEmpty || pat.startsWith('#')) return null;

  var negate = false;
  if (pat.startsWith('!')) {
    negate = true;
    pat = pat.substring(1);
  }

  var dirOnly = false;
  if (pat.endsWith('/')) {
    dirOnly = true;
    pat = pat.substring(0, pat.length - 1);
  }

  // `/` כלשהו (מעבר לזה הסופי שכבר הוסר) מעגן את התבנית לשורש; אחרת ההתאמה
  // לפי שם הקובץ בכל עומק.
  final anchored = pat.contains('/');
  pat = pat.replaceFirst(RegExp(r'^/'), '');
  final body = _globToRegExp(pat);

  // התאמה לנתיב עצמו או לכל מה שתחתיו (כך שתיקייה מותאמת מחריגה את כל תת-העץ).
  // תבנית תיקייה-בלבד מחייבת מקטע-צאצא, כך שלא תתאים לקובץ פשוט באותו שם.
  final tail = dirOnly ? '/.*' : '(?:/.*)?';
  final prefix = anchored ? '^' : '(?:^|.*/)';
  return _IgnoreRule(negate, RegExp('$prefix$body$tail\$'));
}

/// מתרגם glob (כבר ללא `!`, `/` מוביל ו-`/` סופי) ל-RegExp שמתאים נתיב
/// יחסי עם מפרידי `/`.
String _globToRegExp(String glob) {
  final sb = StringBuffer();
  for (var i = 0; i < glob.length; i++) {
    final c = glob[i];
    if (c == '*') {
      if (i + 1 < glob.length && glob[i + 1] == '*') {
        i++; // צריכת הכוכב השני
        if (i + 1 < glob.length && glob[i + 1] == '/') {
          i++; // צריכת ה-`/`: `**/` חוצה אפס או יותר תיקיות
          sb.write('(?:[^/]+/)*');
        } else {
          sb.write('.*'); // `**` סופי — הכל, כולל מפרידים
        }
      } else {
        sb.write('[^/]*'); // `*` נשאר בתוך מקטע יחיד
      }
    } else if (c == '?') {
      sb.write('[^/]');
    } else if (_specialChar.hasMatch(c)) {
      sb.write('\\$c');
    } else {
      sb.write(c);
    }
  }
  return sb.toString();
}

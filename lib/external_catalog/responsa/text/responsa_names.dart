import 'package:otzaria/external_catalog/responsa/text/responsa_hebrew.dart';

/// שמות במאגר מאוחסנים בסדר חזותי (`(בבא בתרא (ליברמן`), ומנתח ההפניות
/// אינו מוצא אותם כך. היכן מתחיל השם מחליט [ResponsaStructure].
class ResponsaNames {
  ResponsaNames._();

  static final RegExp _hebrewLetter = RegExp('[א-ת]');

  // ------------------------------------------------ עטיפת הסוגריים

  /// המבנה המאוחסן הוא `( PRE CORE ( POST`; ההסתייגות היא `POST` ואחריו `PRE`
  /// בסדר הפוך: `(108-126 'היכלות (עמ` → `היכלות` + `עמ' 108-126`.
  static ({String core, String? qualifier}) split(String raw) {
    var value = _moveLeadingMark(raw.trim());
    if (value.isEmpty) return (core: '', qualifier: null);

    if (value.startsWith('(') && value.indexOf('(', 1) > 0) {
      final rest = value.substring(1);
      final cut = rest.indexOf('(');
      final head = rest.substring(0, cut);
      final post = rest.substring(cut + 1).trim();
      final firstLetter = _hebrewLetter.firstMatch(head);
      final pre = firstLetter == null
          ? ''
          : head.substring(0, firstLetter.start);
      final core = firstLetter == null
          ? head
          : head.substring(firstLetter.start);
      // בלי ליבה השם נשאר כפי שהוא - מחרוזת ריקה מוחקת את הספר מהתצוגה
      // ומההפניה כאחד.
      if (_trimMarks(core).isEmpty) return (core: value, qualifier: null);
      final pieces = [
        post,
        ...pre.split(' ').where((p) => p.isNotEmpty).toList().reversed,
      ].where((p) => p.isNotEmpty);
      final qualifier = pieces
          .join(' ')
          // גרש ומרכאות שייכים למילה שלפניהם: `עמ '` → `עמ'`.
          .replaceAll(" ' ", "' ")
          .replaceAll(' " ', '" ')
          .trim();
      return (
        core: _trimMarks(core),
        qualifier: qualifier.isEmpty ? null : qualifier,
      );
    }
    return (core: _trimMarks(value), qualifier: null);
  }

  /// גרש בראש השם הוא אותו היפוך חזותי: `'מלחמת ה` הוא `מלחמת ה'`. גרש
  /// לעולם אינו פותח שם עברי, ולכן אין כאן ניחוש.
  static String _moveLeadingMark(String value) {
    if (value.isEmpty) return value;
    final first = value[0];
    if (first != "'" && first != '"' && first != '׳' && first != '״') {
      return value;
    }
    return '${value.substring(1).trimRight()}$first';
  }

  /// כוכבית מובילה מסמנת בעץ סימן שאינו במקומו הרגיל. היא אינה חלק מהשם
  /// ומנתח ההפניות אינו מקבל אותה.
  static String _trimMarks(String value) =>
      value.replaceAll(RegExp(r'^[*\s]+|[\s]+$'), '');

  /// השם בלי ההסתייגות — מה שנשלח למנתח ההפניות.
  static String coreOf(String raw) => split(raw).core;

  static final RegExp _parenthetical = RegExp(r'\([^)]*\)?|\)');

  /// המנתח אינו מקבל הסתייגות, והיא גם אינה חלק מכותרת החלון - אימות מילולי
  /// יפסול פתיחה תקינה.
  static String withoutQualifier(String name) => name
      .replaceAll(_parenthetical, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// השם הקריא, כולל ההסתייגות בסדר נכון.
  static String displayOf(String raw) {
    final parts = split(raw);
    if (parts.qualifier == null) return parts.core;
    return '${parts.core} (${parts.qualifier})';
  }

  // -------------------------------------------- חיבור רכיבים לשם אחד

  /// מסיר צמתים שחוזרים על שם אביהם (`חלק א > חלק א חתימת הספר`). רק על גבול
  /// מילה: `חלק א` מול `חלק אבן העזר` אינם חזרה.
  static String joinParts(Iterable<String> parts) {
    final kept = <String>[];
    for (final raw in parts) {
      final part = raw.trim();
      if (part.isEmpty) continue;
      final key = ResponsaHebrew.spellingKey(part);
      if (kept.isNotEmpty && key.isNotEmpty) {
        final previous = ResponsaHebrew.spellingKey(kept.last);
        if (previous.isNotEmpty) {
          // הרכיב הנוכחי בולע את הקודם — הקודם מיותר.
          if (key == previous || key.startsWith('$previous ')) {
            kept.removeLast();
          } else if (previous.startsWith('$key ')) {
            // הקודם כבר מכיל את הנוכחי — אין מה להוסיף.
            continue;
          }
        }
      }
      kept.add(part);
    }
    return kept.join(' ');
  }

  /// השם הקריא של רכיבי נתיב, מחובר ומנוקה מחזרות.
  static String titleOf(Iterable<String> parts) =>
      joinParts(parts.map(displayOf));

  /// נגזר מאותם רכיבים כמו [titleOf], כדי שהודעת שגיאה תזכיר את השם שהוצג.
  static String referenceOf(Iterable<String> parts) =>
      joinParts(parts.map(coreOf));

  // ------------------------------------------ תחום שנדבק לשם החיבור

  static final RegExp _trailingDashClause = RegExp(r'\s+-\s+\S.*$');

  /// המנתח מכיר רק את שם החיבור (`תרגום יונתן נביאים` נדחה). מילה אחרונה מוסרת
  /// רק משם בן שלוש ומעלה - מילה גנרית אחת פותחת ספר אחר.
  static List<String> withoutScope(String workName) {
    final name = workName.trim();
    if (name.isEmpty) return const [];
    final candidates = <String>[];

    final withoutClause = name.replaceFirst(_trailingDashClause, '').trim();
    if (withoutClause.isNotEmpty && withoutClause != name) {
      candidates.add(withoutClause);
    }

    final words = name.split(RegExp(r'\s+'));
    if (words.length >= 3) {
      final shorter = words.sublist(0, words.length - 1).join(' ');
      if (!candidates.contains(shorter)) candidates.add(shorter);
    }
    return candidates;
  }
}

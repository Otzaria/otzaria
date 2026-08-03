import 'package:otzaria/settings/l10n/settings_language.dart';
import 'package:otzaria/settings/l10n/settings_text.dart';
import 'package:otzaria/settings/view/settings_screen.dart';

/// פריט בודד באינדקס החיפוש של ההגדרות.
///
/// כל פריט מתאר הגדרה שניתנת לחיפוש: כותרת, תיאור, טאב יעד,
/// ומזהה אנכור (cardId) שמצביע על הכרטיס בו ההגדרה ממוקמת.
class SettingsSearchEntry {
  /// מזהה ייחודי של ההגדרה (לדוג' 'design.theme.dark_mode').
  final String id;

  /// כותרת מוצגת בתוצאה (טקסט הכותרת של ההגדרה).
  final String title;

  /// תיאור מוצג בתוצאה (subtitle או הסבר קצר).
  final String subtitle;

  /// מילות מפתח נוספות לחיפוש שלא מופיעות בכותרת/בתת-כותרת.
  final List<String> keywords;

  /// הטאב בו ממוקמת ההגדרה.
  final SettingsTab tab;

  /// מזהה הכרטיס (SettingsCard) בו ממוקמת ההגדרה.
  /// בלחיצה על תוצאה — נווט לטאב ונגלול לכרטיס בעל ה-cardId הזה.
  /// אם null — ינווט רק לטאב מבלי לגלול.
  final String? cardId;

  /// אם true, בטעינת הטאב יתבצע גם פתיחה אוטומטית של תוכן מורחב
  /// (רלוונטי לכרטיסים עם AnimatedSize/expandable, כגון גיבוי, סייפר).
  final String? expandSection;

  const SettingsSearchEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.tab,
    this.cardId,
    this.keywords = const [],
    this.expandSection,
  });

  /// מחשב ציון התאמה (גבוה יותר = רלוונטי יותר) לשאילתת חיפוש מנורמלת.
  /// 0 = לא מתאים. שאילתה ריקה תחזיר 0.
  int matchScore(String normalizedQuery) =>
      _scoreFor(normalizedQuery, title, subtitle, keywords);

  /// ציון התאמה בשפת התצוגה [language].
  ///
  /// המקור העברי נשאר בר-חיפוש תמיד, ולכן משתמש דו-לשוני — וגם מתחזק —
  /// יכולים להקליד בכל אחת מהשפות. טקסט שאין לו תרגום נופל לעברית ממילא.
  int matchScoreIn(String normalizedQuery, SettingsLanguage language) {
    final hebrewScore = matchScore(normalizedQuery);
    if (language == SettingsLanguage.source) return hebrewScore;

    String translate(String text) =>
        resolveSettingsText(text, language: language);
    final translatedScore = _scoreFor(
      normalizedQuery,
      translate(title),
      translate(subtitle),
      keywords.map(translate).toList(),
    );
    return hebrewScore > translatedScore ? hebrewScore : translatedScore;
  }

  static int _scoreFor(
    String normalizedQuery,
    String title,
    String subtitle,
    List<String> keywords,
  ) {
    if (normalizedQuery.isEmpty) return 0;
    final normalizedTitle = normalize(title);
    final normalizedSubtitle = normalize(subtitle);
    final normalizedKeywords = keywords.map(normalize).toList();

    var score = 0;
    if (normalizedTitle == normalizedQuery) {
      score += 100;
    } else if (normalizedTitle.startsWith(normalizedQuery)) {
      score += 60;
    } else if (normalizedTitle.contains(normalizedQuery)) {
      score += 40;
    }
    if (normalizedSubtitle.contains(normalizedQuery)) {
      score += 15;
    }
    for (final kw in normalizedKeywords) {
      if (kw.contains(normalizedQuery)) {
        score += 10;
        break;
      }
    }
    return score;
  }

  static String normalize(String s) {
    // הסרת ניקוד, תווי משק, רווחים מיותרים, גרשיים — לחיפוש סלחני.
    final lower = s.toLowerCase();
    final buffer = StringBuffer();
    for (final rune in lower.runes) {
      // טווח ניקוד עברי 0x0591-0x05C7
      if (rune >= 0x0591 && rune <= 0x05C7) continue;
      final ch = String.fromCharCode(rune);
      if (ch == '"' || ch == "'" || ch == '׳' || ch == '״') continue;
      buffer.write(ch);
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// טקסט החיפוש המנורמל לאותה הגדרה (משמש להשוואה).
  String get normalizedSearchText =>
      '${normalize(title)} ${normalize(subtitle)} ${keywords.map(normalize).join(' ')}';
}

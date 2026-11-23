/// כינויי ספרים — המקום היחיד שקובע מה נחשב שם של ספר מלבד כותרתו, לכל הצרכנים:
/// איתור מקורות, חיפוש הכותרות בספרייה, צמצום `@שם` בחיפוש, והחיפוש ברשימות
/// ההיסטוריה והסימניות.
///
/// שלושה מקורות, באותו סדר עדיפות:
/// 1. **כינויים מילוליים** מטבלת `book_acronym` של המסד (רשמי או מצורף). הם נקראים
///    ומנורמלים ב-[collectBookAliasTerms] בלבד.
/// 2. **כינויים שנגזרים מהכותרת** בכללים שבקוד ([derivedBookAliases]) — חלים על כל
///    ספר שיש לו כותרת: מסד מצורף בלי טבלת כינויים, ספר אישי, קטלוג חיצוני.
/// 3. **צורות ההשוואה** של כינוי מול שאילתה ([bookNameAcronymForm],
///    [bookNameTractateAcronymForm]): מילות קישור שאינן מכריעות.
///
/// כל הקלטים כבר עברו `normalizeForFindRefMatch`. הקובץ Dart טהור, בלי Flutter,
/// ורץ גם ב-isolate של איתור המקורות.
library;

import 'dart:typed_data';

import 'package:otzaria/find_ref/book_name_match.dart';
import 'package:otzaria/utils/text/find_ref_text_matching.dart';

// ── מילות קישור ───────────────────────────────────────────────────────────────

/// צורת ההשוואה בין שאילתה לכינוי: [bookNameSpellingForm] בלי "על" שבין מילים
/// (#5599, #5611). "על" בקצה הצירוף נשארת: בראש היא חלק מהשם ("על התורה").
String bookNameAcronymForm(String text) {
  final t = bookNameSpellingForm(text);
  return t.contains(' על ') ? t.replaceAll(' על ', ' ') : t;
}

/// גיבוי נוסף לכינוי שלא נמצא, גם בלי "מסכת" שבין מילים (#5609, #5620).
String bookNameTractateAcronymForm(String acronymForm) {
  if (!acronymForm.contains(' מסכת ')) return acronymForm;
  final words = acronymForm.split(' ');
  return [
    for (var i = 0; i < words.length; i++)
      if (i == 0 || i == words.length - 1 || !isTractateWord(words[i]))
        words[i],
  ].join(' ');
}

/// המילה המפורשת "מסכת". אחרי נרמול "מס'" ו"מס" אינן ניתנות להבחנה.
bool isTractateWord(String word) => word == 'מסכת';

// ── כינויים שנגזרים מהכותרת ───────────────────────────────────────────────────

/// שמות קיבוציים של סט ספרים, לפי תחילית הכותרת המשותפת לספריו: "פיה"מ ברכות"
/// הוא "רמב"ם על משנה ברכות" (#5599). בנתוני הכינויים השם הזה קיים רק לחלק מהסט,
/// ובמסד מצורף — לאף ספר.
const Map<String, List<String>> bookSetCollectiveNames = {
  'רמבם על משנה': ['פירוש המשניות', 'פרוש המשניות', 'פיהמ', 'פיהמש'],
};

/// הכינויים שנגזרים מ-[normalizedTitle] בכללי הקוד, בלי הכותרת עצמה. לכל שם
/// קיבוצי גם עם ייחוס למחבר ("פירוש המשניות לרמב"ם ברכות").
List<String> derivedBookAliases(String normalizedTitle) {
  for (final MapEntry(key: prefix, value: names)
      in bookSetCollectiveNames.entries) {
    if (!normalizedTitle.startsWith('$prefix ')) continue;
    final rest = normalizedTitle.substring(prefix.length + 1);
    final author = prefix.substring(0, prefix.indexOf(' '));
    return [
      for (final name in names) ...[
        '$name $rest',
        '$name ל$author $rest',
        '$name לה$author $rest',
      ],
    ];
  }
  return const [];
}

/// בדיקה זולה לפני נרמול הכותרת: האם [rawTitle] עשויה לקבל כינויים נגזרים.
/// הנרמול שומר את סדר האותיות, ולכן כותרת שאותיותיה הראשונות אינן של אחת
/// מתחיליות [bookSetCollectiveNames] — לא תקבל.
bool mayHaveDerivedBookAliases(String rawTitle) {
  for (final prefix in bookSetCollectiveNames.keys) {
    var k = 0;
    for (var i = 0; i < rawTitle.length && k < 3; i++) {
      final c = rawTitle.codeUnitAt(i);
      if (c < 0x05D0 || c > 0x05EA) continue;
      if (c != prefix.codeUnitAt(k)) break;
      k++;
    }
    if (k == 3) return true;
  }
  return false;
}

/// כל הכינויים של ספר: המילוליים ([literal], מנורמלים) ואחריהם הנגזרים מהכותרת
/// שאינם כבר ביניהם. [literal] חוזר כפי שהוא כשאין מה להוסיף, כך שמטמונים
/// שמזהים שינוי לפי זהות הרשימה נשארים תקפים. `null` — אין כינויים כלל.
///
/// הכינויים המילוליים הם תחילית הרשימה: מקום `i >= literal.length` הוא כינוי
/// נגזר, שהתאמה מילולית קודמת לו.
List<String>? bookAliasesOf(List<String>? literal, String normalizedTitle) {
  final derived = derivedBookAliases(normalizedTitle);
  if (derived.isEmpty) return literal;
  if (literal == null || literal.isEmpty) return derived;
  final own = literal.map(bookNameSpellingForm).toSet();
  final extra = [
    for (final alias in derived)
      if (!own.contains(bookNameSpellingForm(alias))) alias,
  ];
  return extra.isEmpty ? literal : [...literal, ...extra];
}

/// [bookAliasesOf] לפי הכותרת הגולמית [rawTitle]; היא מנורמלת רק כשהיא עשויה
/// לקבל כינוי נגזר ([mayHaveDerivedBookAliases]).
List<String> bookAliasesForTitle(List<String>? literal, String rawTitle) =>
    mayHaveDerivedBookAliases(rawTitle)
    ? bookAliasesOf(literal, normalizeForFindRefMatch(rawTitle)) ?? const []
    : literal ?? const [];

// ── קריאת הכינויים המילוליים ──────────────────────────────────────────────────

/// הכינויים המילוליים מזוגות `(bookId, term)` גולמיים של `book_acronym`, אחרי
/// [normalize]. מסלול הקריאה היחיד — לקטלוג הרשמי ולמסדים המצורפים.
({
  Map<int, List<String>> aliasesByBookId,
  Map<int, Set<String>> quotedWordsByBookId,
  int rowCount,
})
collectBookAliasTerms(
  Iterable<(int, String)> rawPairs,
  String Function(String) normalize, {
  bool withQuotedWords = true,
}) {
  final aliasesByBookId = <int, List<String>>{};
  final quotedWordsByBookId = <int, Set<String>>{};
  var rowCount = 0;
  for (final (bookId, term) in rawPairs) {
    rowCount++;
    if (term.isEmpty) continue;
    final normalized = normalize(term);
    if (normalized.isEmpty) continue;
    aliasesByBookId.putIfAbsent(bookId, () => <String>[]).add(normalized);
    if (!withQuotedWords) continue;
    final quoted = quotedWordsOf(term, normalize);
    if (quoted.isNotEmpty) {
      quotedWordsByBookId.putIfAbsent(bookId, () => <String>{}).addAll(quoted);
    }
  }
  return (
    aliasesByBookId: aliasesByBookId,
    quotedWordsByBookId: quotedWordsByBookId,
    rowCount: rowCount,
  );
}

// ── אינדקס הכינויים ───────────────────────────────────────────────────────────

/// קבוצת-על ממוינת של מזהי ספרים שכינוי שלהם עלול להתאים לשאילתה.
/// הבדיקה היא חיפוש בינארי — ללא הקצאות, כדי שתרוץ פעם אחת לכל ספר בכל הקלדה.
class AcronymCandidateBooks {
  const AcronymCandidateBooks._(this._sortedBookIds);

  final List<int> _sortedBookIds;

  /// האם ייתכן שכינוי של [bookId] מתאים לשאילתה. ההכרעה נשארת בידי הקורא —
  /// זו קבוצת-על.
  bool contains(int bookId) {
    var low = 0;
    var high = _sortedBookIds.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final value = _sortedBookIds[mid];
      if (value == bookId) return true;
      if (value < bookId) {
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return false;
  }

  /// המזהים עצמם, ממוינים.
  Iterable<int> get bookIds => _sortedBookIds;

  /// לבדיקות — מספר הספרים שנותרו לסריקה.
  int get length => _sortedBookIds.length;
}

final AcronymCandidateBooks _noCandidates = AcronymCandidateBooks._(
  Int32List(0),
);

/// כינויים מנורמלים לפי ספר, עם אינדקס ביגרמים שמצמצם את הסריקה.
class AcronymCacheData {
  final Map<int, List<String>> acronymsByBookId;

  /// לכל צמד תווים סמוכים שמופיע במונח כלשהו — מזהי הספרים שלהם יש מונח כזה,
  /// ממוינים. המפתח הוא `(תו ראשון << 16) | תו שני`.
  final Map<int, List<int>> bookIdsByBigram;
  final int rowCount;

  /// מילים שכינוי של הספר כותב בגרשיים ("רמב"ם"), בצורתן המנורמלת — הנרמול
  /// מוחק את הגרשיים, והאיתור מעדיף בשוויון ספר שכתוב כמו השאילתה.
  final Map<int, Set<String>> quotedWordsByBookId;

  const AcronymCacheData({
    required this.acronymsByBookId,
    required this.bookIdsByBigram,
    required this.rowCount,
    this.quotedWordsByBookId = const {},
  });

  /// קבוצת-על של הספרים שכינוי שלהם עלול להתאים ל-[normalizedQuery] — בזהות,
  /// בתחילית או בהכלה. `null` פירושו "אין צמצום, סרוק את כל הספרים".
  ///
  /// המסננת אינה מחמיצה: כל שלוש צורות ההתאמה דורשות מונח **שמכיל** את
  /// השאילתה, ומונח כזה מכיל בהכרח כל ביגרם שלה — ולכן הספר מופיע בכל רשימות
  /// הביגרמים, כולל הנדירה שבהן. שאילתה קצרה מ-2 תווים אינה ניתנת לאינדוקס.
  AcronymCandidateBooks? candidatesFor(String normalizedQuery) {
    // אינדקס ריק מול מונחים קיימים — נפילה לסריקה מלאה. קבוצה ריקה כאן
    // הייתה משתיקה כל התאמת כינויים, בלי שגיאה.
    if (bookIdsByBigram.isEmpty || normalizedQuery.length < 2) return null;

    List<int>? rarestBookIds;
    for (var i = 0; i + 1 < normalizedQuery.length; i++) {
      final bookIds =
          bookIdsByBigram[_bigramKey(
            normalizedQuery.codeUnitAt(i),
            normalizedQuery.codeUnitAt(i + 1),
          )];
      // ביגרם שאינו במאגר — אף מונח אינו מכיל את השאילתה.
      if (bookIds == null) return _noCandidates;
      if (rarestBookIds == null || bookIds.length < rarestBookIds.length) {
        rarestBookIds = bookIds;
      }
    }
    return AcronymCandidateBooks._(rarestBookIds!);
  }
}

/// מנרמל זוגות `(bookId, term)` ובונה מהם את [AcronymCacheData].
AcronymCacheData buildAcronymCacheData(
  Iterable<(int, String)> rawPairs,
  String Function(String) normalize,
) {
  final terms = collectBookAliasTerms(rawPairs, normalize);
  return AcronymCacheData(
    acronymsByBookId: terms.aliasesByBookId,
    bookIdsByBigram: buildBookAliasBigrams(terms.aliasesByBookId),
    rowCount: terms.rowCount,
    quotedWordsByBookId: terms.quotedWordsByBookId,
  );
}

/// אינדקס הביגרמים של [AcronymCacheData.bookIdsByBigram] לכינויים מנורמלים.
Map<int, List<int>> buildBookAliasBigrams(
  Map<int, List<String>> aliasesByBookId,
) {
  final postings = <int, List<int>>{};
  final bookIds = aliasesByBookId.keys.toList()..sort();
  for (final bookId in bookIds) {
    for (final term in aliasesByBookId[bookId]!) {
      var previous = -1;
      for (var i = 0; i < term.length; i++) {
        final current = term.codeUnitAt(i);
        if (previous >= 0) {
          final key = (previous << 16) | current;
          final list = postings[key];
          if (list == null) {
            postings[key] = <int>[bookId];
          } else if (list.last != bookId) {
            list.add(bookId);
          }
        }
        previous = current;
      }
    }
  }
  return {
    for (final MapEntry(key: bigram, value: ids) in postings.entries)
      // במסד מצורף מזהה SQLite יכול לחרוג מטווח Int32.
      bigram: ids.first >= -0x80000000 && ids.last <= 0x7fffffff
          ? Int32List.fromList(ids)
          : ids,
  };
}

int _bigramKey(int first, int second) => (first << 16) | second;

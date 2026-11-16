import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/models/book_source.dart';

/// ערכים שנלכדו מ-`ratio` של fuzzywuzzy 1.2.0, שהמיון השתמש בו קודם. שינוי
/// בערך כאן משנה את סדר תוצאות החיפוש בספרייה.
void main() {
  const expected = <(String, String, int)>[
    ('', '', 0),
    ('', 'אבג', 0),
    ('א', '', 0),
    ('א', 'א', 100),
    ('א', 'בגדהוזחטיכלמנסא', 13),
    ('אב', 'בא', 50),
    ('רמבם', 'הרמבם', 89),
    ('שבת', 'שבות', 86),
    ('מסכת שבת', 'תלמוד בבלי מסכת שבת', 59),
    ('abc', 'ABC', 0),
    ('ציוני מהרן', 'בועז על משנה יומא', 30),
    ('ציוני מהרן', 'ציוני מהרן על משנה תורה הלכות תשובה', 44),
    ('כתב סופר', 'בן יהוידע על בבא קמא', 21),
    ('כתב סופר', 'כתב סופר אורח חיים', 62),
    ('ברטנורא', 'תלמוד ירושלמי נזיר', 24),
    ('ברטנורא', 'ברטנורא על משנה גיטין', 50),
    ('הלל', 'עמודי ירושלים על תלמוד ירושלמי דמאי', 11),
    ('הלל', 'הלל', 100),
    ('תשובות', 'לפלגות ראובן חלק ב', 25),
    ('תשובות', 'תשובות מהרים', 67),
    ('חדושי הלכות', 'פסקי הראש על נדרים', 28),
    ('חדושי הלכות', 'חדושי הלכות על מנחות', 71),
    ('חיי', 'מחזור ליום כפור ספרד', 17),
    ('חיי', 'חיי יוסף', 55),
    ('בני', 'קרן אורה על תענית', 20),
    ('בני', 'בני בנימין על משנה תורה הלכות עבודה זרה וחוקות הגויים', 11),
    ('לחם', 'שלמי תודה שוע', 13),
    ('לחם', 'לחם שמים על משנה קידושין', 22),
    ('פסקי תוספות', 'כסף משנה על משנה תורה הלכות בית הבחירה', 24),
    ('פסקי תוספות', 'פסקי תוספות על ראש השנה', 65),
    ('מלאכת', 'חברותא על בכורות', 29),
    ('מלאכת', 'מלאכת שלמה על משנה תורה הלכות גזילה ואבידה', 21),
    ('אור שמח', 'מקורי הרמבם לרשש על משנה תורה הלכות שחיטה', 25),
    ('אור שמח', 'אור שמח על משנה תורה הלכות תלמוד תורה', 32),
    ('לחם', 'בניהו על חגיגה', 24),
    ('לחם', 'לחם שמים על משנה בבא קמא', 22),
    ('רמבם', 'המאור הקטן על מגילה', 17),
    ('רמבם', 'רמבם על משנה עירובין', 33),
    ('מעשי', 'הגהות הרדל על ספר הפרנס', 7),
    ('מעשי', 'מעשי למלך על משנה תורה הלכות מעשה הקרבנות', 18),
    ('שורשי הים', 'מראה הפנים על תלמוד ירושלמי מגילה', 29),
    ('שורשי הים', 'שורשי הים על משנה תורה הלכות תעניות', 41),
    ('מגלה עמוקות', 'שלחן המלך', 30),
    ('מגלה עמוקות', 'מגלה עמוקות על התורה', 71),
    ('חברותא', 'בית אבי גדר', 35),
    ('חברותא', 'חברותא על חולין', 57),
    ('קרית', 'מדרש שמואל', 14),
    ('קרית', 'קרית ספר על משנה תורה הלכות טוען ונטען', 19),
    ('חזון איש', 'פלפולא חריפתא על סנהדרין', 25),
    ('חזון איש', 'חזון איש אמונה ובטחון', 55),
    ('הגהות מהרם', 'מגדל עוז על משנה תורה הלכות תפילה וברכת כהנים', 29),
    ('הגהות מהרם', 'הגהות מהרם די לונזאנו על תלמוד ירושלמי בבא בתרא', 35),
    ('רשש על', 'תוספתא מנחות', 11),
    ('רשש על', 'רשש על משנה חולין', 52),
    ('מלאכת', 'מאירי על שבת', 35),
    ('מלאכת', 'מלאכת שלמה על משנה פסחים', 34),
    ('רבינו חננאל', 'רן על יומא', 38),
    ('רבינו חננאל', 'רבינו חננאל על שמות', 73),
    ('אגודת אזוב', 'תוספות רבי עקיבא איגר על משנה ערכין', 18),
    ('אגודת אזוב', 'אגודת אזוב אורח חיים', 67),
    ('אור', 'נימוקי יוסף על מנחות', 9),
    ('אור', 'אור שמח על משנה תורה הלכות שגגות', 17),
    ('בן יהוידע', 'חגי', 17),
    ('בן יהוידע', 'בן יהוידע על סנהדרין', 62),
    ('בן', 'פני משה על תלמוד ירושלמי מועד קטן', 6),
    ('בן', 'בן אריה על משנה תורה הלכות תרומות', 11),
    ('מצודת', 'בית אהרן', 15),
    ('מצודת', 'מצודת דוד על דברי הימים ב', 33),
    ('נועם ירושלמי', 'יד איתן על משנה תורה הלכות שחיטה', 27),
    ('נועם ירושלמי', 'נועם ירושלמי על סנהדרין', 69),
    ('רשי', 'לחם שמים על משנה דמאי', 17),
    ('רשי', 'רשי על כריתות', 38),
    ('ייטב', 'פני משה על תלמוד ירושלמי ברכות', 18),
    ('ייטב', 'ייטב לב בראשית', 44),
    ('קרית', 'דרוש וחידוש על השס חלק שני', 13),
    ('קרית', 'קרית ספר על משנה תורה הלכות מלווה ולווה', 19),
    ('חמדת שלמה', 'ים של שלמה על כתובות', 34),
    ('חמדת שלמה', 'חמדת שלמה על ראש השנה', 60),
    ('רש', 'שער המלך על משנה תורה הלכות מעשר שני ונטע רבעי', 8),
    ('רש', 'רש משאנץ על משנה שביעית', 16),
  ];

  test('sorted results match eager ratios across every ranking tier', () {
    const query = 'הלכות שבת';
    final cases =
        <({String title, int tier, List<String> acronyms, String path})>[
          (title: query, tier: 4, acronyms: [], path: ''),
          (title: 'דיני הלכות שבת', tier: 3, acronyms: [], path: ''),
          (
            title: 'הלכות שבת כל הפרטים והמנהגים',
            tier: 3,
            acronyms: [],
            path: '',
          ),
          (title: 'הלכות דיני שבת', tier: 2, acronyms: [], path: ''),
          (title: 'הלכות מפורטות שבת', tier: 2, acronyms: [], path: ''),
          (title: 'קיצור דינים', tier: 1, acronyms: [query], path: ''),
          (title: 'הלכותי שבתון', tier: 0, acronyms: [], path: ''),
          (title: 'הלכוד שבת', tier: -1, acronyms: [], path: ''),
          (title: 'קיצור דינים', tier: -2, acronyms: [], path: query),
        ];
    final entries = <BookSearchEntry>[];
    final tiers = <int, int>{};
    for (final item in cases) {
      for (final era in [0, 2, 5]) {
        for (final source in [
          BookSource.official,
          BookSource.user,
          BookSource.attached('test'),
        ]) {
          for (final external in [false, true]) {
            for (var duplicate = 0; duplicate < 2; duplicate++) {
              final index = entries.length;
              tiers[index] = item.tier;
              entries.add(
                BookSearchEntry(
                  index: index,
                  title: item.title,
                  author: '',
                  topics: '',
                  eraOrder: era,
                  source: source,
                  isExternalCatalog: external,
                  acronyms: item.acronyms,
                  categoryPath: item.path,
                ),
              );
            }
          }
        }
      }
    }
    final ratios = {
      for (final entry in entries)
        entry.index: bookSearchRatio(query, entry.title),
    };
    final expected = List<BookSearchEntry>.of(entries)
      ..sort((a, b) {
        if (a.isExternalCatalog != b.isExternalCatalog) {
          return a.isExternalCatalog ? 1 : -1;
        }
        final tier = tiers[b.index]!.compareTo(tiers[a.index]!);
        if (tier != 0) return tier;
        final era = a.eraOrder.compareTo(b.eraOrder);
        if (era != 0) return era;
        final source = a.source.rank.compareTo(b.source.rank);
        if (source != 0) return source;
        final ratio = ratios[b.index]!.compareTo(ratios[a.index]!);
        return ratio != 0 ? ratio : a.index.compareTo(b.index);
      });
    entries.shuffle(Random(19));

    expect(
      filterBookSearchEntries(
        entries: entries,
        queryWords: query.split(' '),
        topics: [],
        sortByRatio: true,
        normalizedQuery: query,
      ),
      expected.map((entry) => entry.index).toList(),
    );
  });

  test('bookSearchRatio matches the captured fuzzywuzzy values', () {
    for (final (a, b, ratio) in expected) {
      expect(bookSearchRatio(a, b), ratio, reason: "'$a' / '$b'");
    }
  });

  test('bookSearchRatio is symmetric', () {
    for (final (a, b, ratio) in expected) {
      expect(bookSearchRatio(b, a), ratio, reason: "'$b' / '$a'");
    }
  });
}

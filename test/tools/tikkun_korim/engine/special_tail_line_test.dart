/// הפטרה שנגמרת בתוך שירה: השורה האחרונה מחזיקה את תוכנה בתאים, ולכן
/// אסור לסמן אותה כפתוחה — הסימון היה מחזיר אותה למסלול השורה הרגילה.
library;

import 'package:otzaria/tools/tikkun_korim/tikkun_korim.dart';
import 'package:test/test.dart';

import '../support/tikkun_fixtures.dart';

const StamWidthModel _widths = StamWidthModel.uniform();

/// הפטרת בשלח כמנהג אשכנז — מסתיימת בפסוק האחרון של שירת דבורה.
const Haftarah _beshalach = Haftarah(
  id: 'h:test',
  category: 'parasha',
  name: 'בשלח',
  ashkenaz: [
    VerseRange(book: 'שופטים', fromCh: 4, fromVs: 4, toCh: 5, toVs: 31),
  ],
  sephard: [],
);

void main() {
  late List<TikkunLine> lines;

  setUpAll(() {
    final tokens = markSpecialSections(
      tokenizeText(cleanRawText(readFixture('shoftim'))),
      'שופטים',
    );
    lines = buildHaftarahLines(_beshalach, 'ashkenaz', {
      'שופטים': tokens,
    }, _widths);
  });

  test('השורה האחרונה נשארת שורת שירה ואינה מסומנת כפתוחה', () {
    expect(lines.last.layout, LineLayout.shiraZigzag);
    expect(lines.last.manualCells, isNotNull);
  });

  test('סוף השירה אינו נבלע — לשורה האחרונה יש תוכן', () {
    final words = lines.last.manualCells!.expand((c) => c.words);
    expect(words, isNotEmpty);
  });

  test('אין שורה ריקה בסוף ההפטרה', () {
    expect(lines.last.layout, isNot(LineLayout.empty));
    expect(lines.last.words, isEmpty, reason: 'התוכן יושב בתאים');
  });
}

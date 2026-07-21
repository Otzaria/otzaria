import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/section_search_utils.dart';

import 'literal_pattern_test_helper.dart';

void main() {
  tearDown(() async {
    await resetSectionSearchWorkerForTesting();
  });

  group('searchInContent - whole word matching', () {
    test('finds exact whole-word match', () async {
      final results = await searchInContent(
        content: ['שמע ישראל'],
        query: 'שמע',
        patternSource: literalPatternSource('שמע'),
      );
      expect(results.length, 1);
    });

    test(
      'does not match partial word (query is prefix of longer word)',
      () async {
        final results = await searchInContent(
          content: ['שמעון'],
          query: 'שמע',
          patternSource: literalPatternSource('שמע'),
        );
        expect(results, isEmpty);
      },
    );

    test(
      'does not match partial word (query is suffix of longer word)',
      () async {
        final results = await searchInContent(
          content: ['ושמע'],
          query: 'שמע',
          patternSource: literalPatternSource('שמע'),
        );
        expect(results, isEmpty);
      },
    );

    test(
      'does not match partial word (query is infix of longer word)',
      () async {
        final results = await searchInContent(
          content: ['ושמעון'],
          query: 'שמע',
          patternSource: literalPatternSource('שמע'),
        );
        expect(results, isEmpty);
      },
    );

    test('finds word at beginning of line', () async {
      final results = await searchInContent(
        content: ['ישראל עם'],
        query: 'ישראל',
        patternSource: literalPatternSource('ישראל'),
      );
      expect(results.length, 1);
    });

    test('finds word at end of line', () async {
      final results = await searchInContent(
        content: ['עם ישראל'],
        query: 'ישראל',
        patternSource: literalPatternSource('ישראל'),
      );
      expect(results.length, 1);
    });

    test('finds word surrounded by punctuation', () async {
      final results = await searchInContent(
        content: ['(שמע)'],
        query: 'שמע',
        patternSource: literalPatternSource('שמע'),
      );
      expect(results.length, 1);
    });

    test(
      'does not match when query appears only as partial in all occurrences',
      () async {
        final results = await searchInContent(
          content: ['שמעון ושמעיהו'],
          query: 'שמע',
          patternSource: literalPatternSource('שמע'),
        );
        expect(results, isEmpty);
      },
    );

    test(
      'finds match when one occurrence is whole word and another is partial',
      () async {
        final results = await searchInContent(
          content: ['שמע ושמעון'],
          query: 'שמע',
          patternSource: literalPatternSource('שמע'),
        );
        expect(results.length, 1);
      },
    );

    test('מוצא מילה מנוקדת הצמודה לגרשיים עבריים (״)', () async {
      final results = await searchInContent(
        content: ['דִּכְתִיב: ״וַאֲשֶׁר הֲרֵעֹתִי״.'],
        query: 'הרעתי',
        patternSource: literalPatternSource('הרעתי'),
      );
      expect(results.length, 1);
    });

    test('מוצא מילה מנוקדת גם כשהשאילתה עצמה מנוקדת', () async {
      final results = await searchInContent(
        content: ['דִּכְתִיב: ״וַאֲשֶׁר הֲרֵעֹתִי״.'],
        query: 'הֲרֵעֹתִי',
        patternSource: literalPatternSource('הֲרֵעֹתִי'),
      );
      expect(results.length, 1);
    });

    test('מוצא מילה הצמודה לגרש עברי (׳)', () async {
      final results = await searchInContent(
        content: ['ר׳ עקיבא'],
        query: 'ר',
        patternSource: literalPatternSource('ר'),
      );
      expect(results.length, 1);
    });

    test('ליגטורת יידיש (װ) נחשבת אות — לא שוברת מילה שלמה', () async {
      final results = await searchInContent(
        content: ['אװ שלום'],
        query: 'אװ',
        patternSource: literalPatternSource('אװ'),
      );
      expect(results.length, 1);
    });

    test('ליגטורת יידיש צמודה פוסלת התאמה חלקית', () async {
      final results = await searchInContent(
        content: ['שמעװ'],
        query: 'שמע',
        patternSource: literalPatternSource('שמע'),
      );
      expect(results, isEmpty);
    });

    test('returns empty for empty content', () async {
      final results = await searchInContent(
        content: [],
        query: 'שמע',
        patternSource: literalPatternSource('שמע'),
      );
      expect(results, isEmpty);
    });

    test('returns empty for empty query', () async {
      final results = await searchInContent(content: ['שמע ישראל'], query: '');
      expect(results, isEmpty);
    });
  });

  group('searchInContent - הופעות מרובות באותה שורה', () {
    test('שתי הופעות באותה שורה — שתי תוצאות על אותו אינדקס', () async {
      final results = await searchInContent(
        content: ['אמר רבי יהודה דבר אחד ועוד אמר יהודה בן גרוש דבר אחר'],
        query: 'יהודה',
        patternSource: literalPatternSource('יהודה'),
      );
      expect(results.length, 2);
      expect(results[0].index, 0);
      expect(results[1].index, 0);
    });

    test('הופעות קרובות — כל snippet מכיל רק את ההופעה שלו', () async {
      final results = await searchInContent(
        content: ['אמר רבי יהודה דבר אחד ועוד אמר יהודה בן גרוש דבר אחר'],
        query: 'יהודה',
        patternSource: literalPatternSource('יהודה'),
      );
      expect(results.length, 2);
      for (final result in results) {
        expect('יהודה'.allMatches(result.snippet).length, 1);
      }
      expect(results[0].snippet, contains('רבי'));
      expect(results[1].snippet, contains('בן גרוש'));
    });

    test('בשורה ארוכה — כל תוצאה מקבלת snippet סביב ההופעה שלה', () async {
      final padding = List.generate(60, (i) => 'מלל$i').join(' ');
      final results = await searchInContent(
        content: ['יהודה בתחילה $padding יהודה בסוף'],
        query: 'יהודה',
        patternSource: literalPatternSource('יהודה'),
      );
      expect(results.length, 2);
      expect(results[0].snippet, contains('בתחילה'));
      expect(results[0].snippet, isNot(contains('בסוף')));
      expect(results[1].snippet, contains('בסוף'));
      expect(results[1].snippet, isNot(contains('בתחילה')));
    });

    test('כל תוצאה נושאת את היסט ההופעה שלה בשורה', () async {
      final results = await searchInContent(
        content: ['אמר רבי יהודה דבר אחד ועוד אמר יהודה בן גרוש דבר אחר'],
        query: 'יהודה',
        patternSource: literalPatternSource('יהודה'),
      );
      expect(results.length, 2);
      expect(results[0].matchOffset, 8);
      expect(results[1].matchOffset, 31);
    });

    test('שורה קצרה — ה-snippet הוא השורה המלאה', () async {
      final results = await searchInContent(
        content: ['שמע ישראל'],
        query: 'שמע',
        patternSource: literalPatternSource('שמע'),
      );
      expect(results.single.snippet, 'שמע ישראל');
    });

    test('תקרת 1000 התוצאות נאכפת גם על הופעות באותה שורה', () async {
      final line = List.filled(1005, 'שמע').join(' ');
      final results = await searchInContent(
        content: [line],
        query: 'שמע',
        patternSource: literalPatternSource('שמע'),
      );
      expect(results.length, 1000);
    });
  });

  group('searchInContent - whitespace normalization', () {
    test('מוצא ביטוי כשיש תג HTML עם רווחים סביבו', () async {
      final results = await searchInContent(
        content: ['<b>כמשה </b> מפי הגבורה'],
        query: 'כמשה מפי הגבורה',
        patternSource: literalPatternSource('כמשה מפי הגבורה'),
      );
      expect(results.length, 1);
    });

    test('מוצא ביטוי כשמקף עברי מפריד מילים', () async {
      final results = await searchInContent(
        content: ['אשר־שמע משה'],
        query: 'אשר שמע',
        patternSource: literalPatternSource('אשר שמע'),
      );
      expect(results.length, 1);
    });

    test('מוצא ביטוי כשהשאילתה מכילה רווח כפול', () async {
      final results = await searchInContent(
        content: ['שמע ישראל'],
        query: 'שמע  ישראל',
        patternSource: literalPatternSource('שמע  ישראל'),
      );
      expect(results.length, 1);
    });

    test('מוצא ביטוי כשהמקף במילת החיפוש עצמה', () async {
      final results = await searchInContent(
        content: ['אשר־שמע משה'],
        query: 'אשר־שמע',
        patternSource: literalPatternSource('אשר־שמע'),
      );
      expect(results.length, 1);
    });

    test('מוצא מילה כששאילתה מסתיימת בגרשיים (הרעתי")', () async {
      final results = await searchInContent(
        content: ['דכתיב: ״ואשר הרעתי״.'],
        query: 'הרעתי"',
        patternSource: literalPatternSource('הרעתי"'),
      );
      expect(results.length, 1);
    });

    test('מוצא ביטוי רב-מילים עם גרש פנימי (ר׳ עקיבא)', () async {
      final results = await searchInContent(
        content: ['אמר ר׳ עקיבא שלום'],
        query: 'ר׳ עקיבא',
        patternSource: literalPatternSource('ר׳ עקיבא'),
      );
      expect(results.length, 1);
    });

    test('גרשיים פנימי אינו גבול — "רש" לא נמצא בתוך רש״י', () async {
      final results = await searchInContent(
        content: ['אמר רש״י כאן'],
        query: 'רש',
        patternSource: literalPatternSource('רש'),
      );
      expect(results, isEmpty);
    });

    test('זוג גרשים (\'\') נחשב גרשיים — "אב" לא נמצא בתוך אב\'\'ג', () async {
      final results = await searchInContent(
        content: ["דף עם אב''ג בתוכו"],
        query: 'אב',
        patternSource: literalPatternSource('אב'),
      );
      expect(results, isEmpty);
    });

    test('סימן צמוד אחרי גרשיים אינו עוקף את הגבול', () async {
      final results = await searchInContent(
        content: ['דף עם אב״ֿג בתוכו'],
        query: 'אב',
        patternSource: literalPatternSource('אב'),
      );
      expect(results, isEmpty);
    });

    test('רצפי-ציטוט משורשרים בסימנים (רמב' 'ְ"ם) — טוקן אחד', () async {
      final results = await searchInContent(
        content: ['דף עם רמב' 'ְ"ם בתוכו'],
        query: 'רמב',
        patternSource: literalPatternSource('רמב'),
      );
      expect(results, isEmpty);
    });
  });

  group('matchFractionInLine', () {
    test('מילה בתחילת השורה — שבר 0', () {
      expect(
        matchFractionInLine(
          'ישראל עם קדוש',
          'ישראל',
          pattern: literalPattern('ישראל'),
        ),
        0,
      );
    });

    test('מילה בסוף השורה — שבר גבוה', () {
      expect(
        matchFractionInLine(
          'שמע ישראל',
          'ישראל',
          pattern: literalPattern('ישראל'),
        ),
        greaterThan(0.3),
      );
    });

    test('שאילתה מנוקדת מול שורה מנוקדת', () {
      final fraction = matchFractionInLine(
        'בְּרֵאשִׁית בָּרָא אֱלֹהִים',
        'אלהים',
        pattern: literalPattern('אלהים'),
      );
      expect(fraction, greaterThan(0.5));
    });

    test('אין התאמה — שבר 0', () {
      expect(
        matchFractionInLine('שמע ישראל', 'משה', pattern: literalPattern('משה')),
        0,
      );
    });

    test('מילה מנוקדת הצמודה לגרשיים — נמצאת בחישוב השבר', () {
      expect(
        matchFractionInLine(
          'דִּכְתִיב: ״וַאֲשֶׁר הֲרֵעֹתִי״.',
          'הרעתי',
          pattern: literalPattern('הרעתי'),
        ),
        greaterThan(0),
      );
    });

    test('שורה ריקה — שבר 0', () {
      expect(matchFractionInLine('', 'שמע', pattern: literalPattern('שמע')), 0);
    });

    test('matchOffset מפורש גובר על ההופעה הראשונה', () {
      const line = 'יהודה אמר ועוד אמר יהודה דבר';
      final firstFraction = matchFractionInLine(
        line,
        'יהודה',
        matchOffset: 0,
        pattern: literalPattern('יהודה'),
      );
      final secondFraction = matchFractionInLine(
        line,
        'יהודה',
        matchOffset: 19,
        pattern: literalPattern('יהודה'),
      );
      expect(firstFraction, 0);
      expect(secondFraction, greaterThan(0.5));
    });

    test('שבר גלילה מתעלם מתג HTML עם רווחים בין המילים', () {
      final fraction = matchFractionInLine(
        'בראשית <b>ברא </b> אלהים',
        'ברא אלהים',
        pattern: literalPattern('ברא אלהים'),
      );
      expect(fraction, greaterThan(0));
    });
  });

  group('queryMatchesInlineNoteOnly', () {
    const noteLine = 'שלום עולם '
        '<sup class="footnote-marker">1</sup>'
        '<i class="footnote">כאן מופיע דין מיוחד</i>';

    test('מונח שנמצא רק בגוף ההערה — אמת', () {
      expect(
        queryMatchesInlineNoteOnly(
          noteLine,
          'דין',
          pattern: literalPattern('דין'),
        ),
        isTrue,
      );
    });

    test('מונח שנמצא בטקסט הראשי — שקר (אין צורך בחלונית ההערות)', () {
      expect(
        queryMatchesInlineNoteOnly(
          noteLine,
          'שלום',
          pattern: literalPattern('שלום'),
        ),
        isFalse,
      );
    });

    test('מונח שאינו קיים כלל — שקר', () {
      expect(
        queryMatchesInlineNoteOnly(
          noteLine,
          'משה',
          pattern: literalPattern('משה'),
        ),
        isFalse,
      );
    });

    test('שורה ללא הערת שוליים — שקר', () {
      expect(
        queryMatchesInlineNoteOnly(
          'שלום עולם דין',
          'דין',
          pattern: literalPattern('דין'),
        ),
        isFalse,
      );
    });

    test('התאמה חלקית בהערה (תת-מחרוזת) אינה נספרת', () {
      expect(
        queryMatchesInlineNoteOnly(
          noteLine,
          'די',
          pattern: literalPattern('די'),
        ),
        isFalse,
      );
    });

    test('מונח מנוקד מול הערה — מתעלם מניקוד', () {
      const vocalized = 'פתיחה '
          '<sup class="footnote-marker">2</sup>'
          '<i class="footnote">אֱלֹהִים חיים</i>';
      expect(
        queryMatchesInlineNoteOnly(
          vocalized,
          'אלהים',
          pattern: literalPattern('אלהים'),
        ),
        isTrue,
      );
    });

    test('שאילתה ריקה — שקר', () {
      expect(queryMatchesInlineNoteOnly(noteLine, ''), isFalse);
    });
  });
}

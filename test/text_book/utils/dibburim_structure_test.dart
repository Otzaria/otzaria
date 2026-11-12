import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/models/alt_toc_entry.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/utils/dibburim_structure.dart';

TocEntry _e(String text, int index, int level, {List<TocEntry>? children}) {
  final entry = TocEntry(text: text, index: index, level: level);
  for (final c in children ?? const <TocEntry>[]) {
    entry.children.add(c);
  }
  return entry;
}

/// עץ לדוגמה: כותרת ראשית (0) → פרק א (2) → משנה א (4), משנה ב (9); פרק ב (14).
List<TocEntry> _toc() => [
  _e(
    'ספר',
    0,
    1,
    children: [
      _e(
        'פרק א',
        2,
        2,
        children: [_e('משנה א', 4, 3), _e('משנה ב', 9, 3)],
      ),
      _e('פרק ב', 14, 2),
    ],
  ),
];

List<String> _texts(List<TocEntry> entries) =>
    entries.map((e) => e.text).toList();

void main() {
  group('attachDibburimToToc', () {
    test('מפה ריקה — מחזירה את העץ המקורי עצמו', () {
      final toc = _toc();
      expect(identical(attachDibburimToToc(toc, const {}), toc), isTrue);
    });

    test('כל דיבור נתלה תחת הכותרת האחרונה שלפניו, גם כשהיא עלה', () {
      final merged = attachDibburimToToc(_toc(), {
        3: 'ד"ה שלפני משנה א',
        5: 'ד"ה במשנה א',
        7: 'ד"ה שני במשנה א',
        11: 'ד"ה במשנה ב',
        20: 'ד"ה בפרק ב',
      });

      final perekA = merged.single.children[0];
      final mishnaA = perekA.children[1];
      final mishnaB = perekA.children[2];
      final perekB = merged.single.children[1];

      // הדיבור שבין "פרק א" ל"משנה א" קודם לתתי-הכותרות של הפרק.
      expect(_texts(perekA.children), [
        'ד"ה שלפני משנה א',
        'משנה א',
        'משנה ב',
      ]);
      expect(_texts(mishnaA.children), ['ד"ה במשנה א', 'ד"ה שני במשנה א']);
      expect(_texts(mishnaB.children), ['ד"ה במשנה ב']);
      expect(_texts(perekB.children), ['ד"ה בפרק ב']);
    });

    test('דיבור הוא רמה אחת מתחת לכותרתו, עם parent ו-index של השורה', () {
      final merged = attachDibburimToToc(_toc(), {5: 'ד"ה'});
      final mishnaA = merged.single.children[0].children[0];
      final dibbur = mishnaA.children.single;

      expect(dibbur.index, 5);
      expect(dibbur.level, mishnaA.level + 1);
      expect(identical(dibbur.parent, mishnaA), isTrue);
      expect(dibbur.fullText, 'פרק א, משנה א, ד"ה');
    });

    test('העץ המקורי אינו משתנה', () {
      final toc = _toc();
      attachDibburimToToc(toc, {5: 'ד"ה', 20: 'ד"ה'});

      expect(toc.single.children[0].children[0].children, isEmpty);
      expect(toc.single.children[1].children, isEmpty);
    });

    test('דיבור שלפני הכותרת הראשונה או על שורת כותרת — נשמט', () {
      final toc = [_e('כותרת', 3, 1), _e('כותרת ב', 8, 1)];
      final merged = attachDibburimToToc(toc, {
        1: 'לפני הכל',
        8: 'על שורת הכותרת',
        9: 'אחרי כותרת ב',
      });

      expect(merged[0].children, isEmpty);
      expect(_texts(merged[1].children), ['אחרי כותרת ב']);
    });
  });

  group('truncateDibbur', () {
    test('דיבור קצר מוחזר כמות שהוא', () {
      expect(truncateDibbur('אמר רבא', maxWords: 4), 'אמר רבא');
    });

    test('דיבור ארוך נחתך למספר המילים עם סימן קיצור', () {
      expect(
        truncateDibbur('ואם יש לו צורת פתח אפילו רחב מעשר', maxWords: 4),
        'ואם יש לו צורת…',
      );
    });

    test('זהה למימוש הקודם בכל יחידת קוד ובכל מספר מילים (perf)', () {
      // המימוש הקודם כלשונו: trim() של Dart כולל U+0085, ו-\s של RegExp לא.
      String old(String text, int maxWords) {
        final words = text.trim().split(RegExp(r'\s+'));
        if (words.length <= maxWords) return text.trim();
        return '${words.take(maxWords).join(' ')}…';
      }

      for (var c = 0; c <= 0xFFFF; c++) {
        final ch = String.fromCharCode(c);
        for (final text in [
          ch,
          '$chא$ch',
          'א$chב ג ד ה',
          'א ב$ch$chג ד ה ו',
          '$ch א ב ג ד$ch',
          'א ב ג ד$chה',
        ]) {
          for (var maxWords = 0; maxWords <= 6; maxWords++) {
            expect(
              truncateDibbur(text, maxWords: maxWords),
              old(text, maxWords),
              reason: '${c.toRadixString(16)} $maxWords',
            );
          }
        }
      }
    });
  });

  group('buildDibburimEntries', () {
    test('מפה ריקה — אין ערכים', () {
      expect(buildDibburimEntries(_toc(), const {}), isEmpty);
    });

    test('כותרות בלי דיבורים נשמטות, והשורש היחיד (שם הספר) מושמט', () {
      final entries = buildDibburimEntries(_toc(), {11: 'ד"ה במשנה ב'});

      expect(entries.map((e) => e.text), ['פרק א', 'משנה ב', 'ד"ה במשנה ב']);
      expect(entries.map((e) => e.level), [0, 1, 2]);
      // "פרק ב" ו"משנה א" לא נכללו: אין דיבור תחתיהם.
    });

    test('מזהים והורות: הדיבור מקודד לשורה שלו, ההורה לכותרת שלו', () {
      final entries = buildDibburimEntries(_toc(), {5: 'ד"ה', 20: 'ד"ה ב'});
      final byText = {for (final e in entries) e.text!: e};

      final perekA = byText['פרק א']!;
      final mishnaA = byText['משנה א']!;
      final dibbur = byText['ד"ה']!;
      final perekB = byText['פרק ב']!;

      expect(perekA.parentId, isNull);
      expect(mishnaA.parentId, perekA.id);
      expect(dibbur.parentId, mishnaA.id);
      expect(dibburimLineIndex(dibbur.id), 5);
      expect(dibburimLineIndex(byText['ד"ה ב']!.id), 20);
      expect(dibbur.hasChildren, isFalse);
      expect(mishnaA.hasChildren, isTrue);
      expect(perekB.isLastChild, isTrue);
      expect(entries.every((e) => e.structureId == kDibburimStructureId), true);
    });

    test('טקסט הדיבור מקוצר, טקסט הכותרת לא', () {
      final longHeading = 'כותרת ארוכה מאוד עם הרבה מאוד מילים';
      final toc = [_e(longHeading, 0, 1), _e('כותרת ב', 5, 1)];
      final entries = buildDibburimEntries(toc, {
        3: 'דיבור ארוך מאוד עם הרבה מאוד מילים',
        6: 'ד"ה',
      });

      expect(entries[0].text, longHeading);
      expect(
        entries[1].text,
        truncateDibbur('דיבור ארוך מאוד עם הרבה מאוד מילים'),
      );
    });

    test('כמה שורשים עם דיבורים נשמרים כולם', () {
      final toc = [_e('דף ב.', 1, 1), _e('דף ב:', 6, 1), _e('דף ג.', 12, 1)];
      final entries = buildDibburimEntries(toc, {2: 'א', 7: 'ב'});

      expect(entries.map((e) => e.text), ['דף ב.', 'א', 'דף ב:', 'ב']);
      expect(entries.where((e) => e.parentId == null).length, 2);
    });
  });

  group('hasDibburimEntries', () {
    test('אין מבנה כשה-TOC ריק או שכל הדיבורים לפני הכותרת הראשונה', () {
      expect(hasDibburimEntries(const [], {2: 'ד"ה'}), isFalse);
      expect(
        hasDibburimEntries([_e('כותרת', 3, 1)], {1: 'ד"ה', 3: 'ד"ה ב'}),
        isFalse,
      );
    });

    test('דיבור שאחרי כותרת ואינו על שורתה מצדיק מבנה', () {
      expect(hasDibburimEntries(_toc(), {5: 'ד"ה'}), isTrue);
    });
  });

  group('activeDibburimEntryId', () {
    final entries = buildDibburimEntries(_toc(), {5: 'א', 7: 'ב', 20: 'ג'});

    test('שורה בתוך דיבור — הדיבור; שורה על כותרת — הכותרת', () {
      expect(dibburimLineIndex(activeDibburimEntryId(entries, 6)!), 5);
      expect(dibburimLineIndex(activeDibburimEntryId(entries, 8)!), 7);
      // "משנה ב" (9) אינה במבנה — אין תחתיה דיבור — ולכן הדיבור שלפניה נשאר.
      expect(dibburimLineIndex(activeDibburimEntryId(entries, 9)!), 7);
      expect(dibburimLineIndex(activeDibburimEntryId(entries, 14)!), 14);
      expect(dibburimLineIndex(activeDibburimEntryId(entries, 30)!), 20);
    });

    test('שורה לפני הערך הראשון — אין ערך פעיל', () {
      expect(activeDibburimEntryId(entries, 1), isNull);
    });

    test('עץ גדול מחזיר את הערך האחרון שאינו אחרי השורה', () {
      final largeEntries = List.generate(
        20000,
        (index) => AltTocEntry(
          id: dibburimEntryId(index * 2),
          structureId: kDibburimStructureId,
          textId: 0,
          level: 0,
        ),
      );

      expect(
        activeDibburimEntryId(largeEntries, 33333),
        dibburimEntryId(33332),
      );
    });
  });
}

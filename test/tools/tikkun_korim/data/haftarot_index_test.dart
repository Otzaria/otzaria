import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/data/tanach_structure.g.dart';
import 'package:otzaria/tools/tikkun_korim/data/tikkun_data.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';

Haftarah _byId(String id) => TikkunData.haftarot.firstWhere((h) => h.id == id);

void main() {
  final haftarot = TikkunData.haftarot;

  Map<String, int> neviimChapters() {
    final out = <String, int>{};
    for (final raw in kTanachNeviim) {
      final m = (raw as Map).cast<String, Object?>();
      out[m['name'] as String] = m['chapters'] as int;
    }
    return out;
  }

  group('תקינות טבלת ההפטרות', () {
    test('אין מזהים כפולים', () {
      final ids = haftarot.map((h) => h.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('כל מקטע מפנה לספר נביאים קיים ולפרק בטווח', () {
      final chapters = neviimChapters();
      for (final h in haftarot) {
        for (final seg in [...h.ashkenaz, ...h.sephard]) {
          expect(
            chapters.containsKey(seg.book),
            isTrue,
            reason: '${h.id}: ${seg.book}',
          );
          expect(seg.fromCh, inInclusiveRange(1, chapters[seg.book]!));
          expect(seg.toCh, inInclusiveRange(1, chapters[seg.book]!));
          expect(seg.fromVs, greaterThan(0));
          expect(seg.toVs, greaterThan(0));
        }
      }
    });

    test('לכל ערך יש מקטעי אשכנז', () {
      for (final h in haftarot) {
        expect(h.ashkenaz, isNotEmpty, reason: h.id);
      }
    });

    test('land הוא ערך מוכר', () {
      for (final h in haftarot) {
        expect(['both', 'israel', 'diaspora'], contains(h.land));
      }
    });
  });

  group('פרשות מחוברות', () {
    const combined = {
      'p:Vayakhel-Pekudei': 'p:Pekudei',
      'p:Tazria-Metzora': 'p:Metzora',
      'p:Behar-Bechukotai': 'p:Bechukotai',
      'p:Chukat-Balak': 'p:Balak',
      'p:Matot-Masei': 'p:Masei',
      // נצבים-וילך: השבת שלפני ר"ה, ומפטירים בה "שוש אשיש" של נצבים.
      'p:Nitzavim-Vayeilech': 'p:Nitzavim',
    };

    test('שבע פרשות מחוברות ברשימה', () {
      final ids = haftarot.map((h) => h.id).toSet();
      for (final id in [...combined.keys, 'p:Achrei Mot-Kedoshim']) {
        expect(ids, contains(id));
      }
    });

    test('ההפטרה זהה לזו של הפרשה שממנה היא נלקחת', () {
      combined.forEach((joined, second) {
        expect(_byId(joined).ashkenaz, _byId(second).ashkenaz, reason: joined);
        expect(_byId(joined).sephard, _byId(second).sephard, reason: joined);
      });
    });

    test('אחרי מות-קדושים הוא החריג: אשכנז כאחרי מות, ספרדי כקדושים', () {
      final joined = _byId('p:Achrei Mot-Kedoshim');
      expect(joined.ashkenaz, _byId('p:Achrei Mot').ashkenaz);
      expect(joined.sephard, _byId('p:Kedoshim').sephard);
    });
  });

  group('ערכים כפולים במקור הוסרו', () {
    test('שבועות רק כשני ימים', () {
      final ids = haftarot.map((h) => h.id).toSet();
      expect(ids, isNot(contains('h:Shavuot')));
      expect(ids, containsAll(['h:Shavuot I', 'h:Shavuot II']));
    });

    test('מנחת יום כיפור — ערך יחיד', () {
      final yk = haftarot.where((h) => h.id.contains('Yom Kippur (Mincha'));
      expect(yk.map((h) => h.id), ['h:Yom Kippur (Mincha)']);
      expect(yk.single.name, 'יום כיפור - מנחה');
    });

    test('שבת שובה רק בשני הווריאנטים', () {
      final ids = haftarot.map((h) => h.id).toSet();
      expect(ids, isNot(contains('h:Shabbat Shuva')));
      expect(
        ids,
        containsAll([
          'h:Shabbat Shuva (with Vayeilech)',
          'h:Shabbat Shuva (with Ha\'azinu)',
        ]),
      );
    });
  });

  group('תעניות', () {
    test('מנחת תענית ציבור — לספרדים אין הפטרה', () {
      final fast = _byId('h:Fast Day (Afternoon)');
      expect(fast.sephardNone, isTrue);
      expect(fast.hasNusach('sephard'), isFalse);
      expect(fast.forNusach('sephard'), isEmpty);
      expect(fast.forNusach('ashkenaz'), isNotEmpty);
    });

    test('מנחת תשעה באב — דרשו לאשכנז, שובה ישראל לספרדים', () {
      final tb = _byId('h:Tish\'a B\'Av (Mincha)');
      expect(tb.forNusach('ashkenaz'), const [
        VerseRange(
          book: 'ישעיהו',
          fromCh: 55,
          fromVs: 6,
          toCh: 56,
          toVs: 8,
        ),
      ]);
      expect(tb.forNusach('sephard'), const [
        VerseRange(book: 'הושע', fromCh: 14, fromVs: 2, toCh: 14, toVs: 10),
        VerseRange(book: 'מיכה', fromCh: 7, fromVs: 18, toCh: 7, toVs: 20),
      ]);
    });
  });

  group('חזרה על הפסוק הלפני-אחרון', () {
    test('שבת ראש חודש מסיימת בחזרת ישעיהו סו, כג', () {
      for (final nusach in ['ashkenaz', 'sephard']) {
        expect(
          _byId('h:Shabbat Rosh Chodesh').forNusach(nusach).last,
          const VerseRange(
            book: 'ישעיהו',
            fromCh: 66,
            fromVs: 23,
            toCh: 66,
            toVs: 23,
          ),
        );
      }
    });

    test('שבת הגדול מסיימת בחזרת מלאכי ג, כג', () {
      for (final nusach in ['ashkenaz', 'sephard']) {
        expect(
          _byId('h:Shabbat HaGadol').forNusach(nusach).last,
          const VerseRange(
            book: 'מלאכי',
            fromCh: 3,
            fromVs: 23,
            toCh: 3,
            toVs: 23,
          ),
        );
      }
    });
  });

  group('ארץ ישראל וחוץ לארץ', () {
    test('יום טוב שני של גלויות מסומן diaspora', () {
      for (final id in [
        'h:Pesach II',
        'h:Pesach VIII',
        'h:Shavuot II',
        'h:Sukkot II',
        'h:Shmini Atzeret',
      ]) {
        expect(_byId(id).land, 'diaspora', reason: id);
      }
    });

    test('יום טוב ראשון נקרא בשתי הארצות', () {
      for (final id in ['h:Pesach I', 'h:Shavuot I', 'h:Sukkot I']) {
        expect(_byId(id).land, 'both', reason: id);
      }
    });
  });

  group('שבתות ראש חודש', () {
    const rcAshkenaz = [
      VerseRange(book: 'ישעיהו', fromCh: 66, fromVs: 1, toCh: 66, toVs: 24),
      VerseRange(book: 'ישעיהו', fromCh: 66, fromVs: 23, toCh: 66, toVs: 23),
    ];

    test('ר"ח אלול: "עניה סוערה" לספרדים, "השמים כסאי" לאשכנז', () {
      final elul = _byId('h:Shabbat Rosh Chodesh Elul');
      expect(elul.forNusach('ashkenaz'), rcAshkenaz);
      expect(elul.forNusach('sephard'), const [
        VerseRange(book: 'ישעיהו', fromCh: 54, fromVs: 11, toCh: 55, toVs: 5),
      ]);
      expect(elul.land, 'both');
    });

    test('ר"ח שני ימים: ספרדים מוסיפים פסוק ראשון ואחרון של "מחר חודש"', () {
      final rc = _byId('h:Shabbat Rosh Chodesh (Machar Chodesh)');
      expect(rc.forNusach('ashkenaz'), rcAshkenaz);
      expect(rc.forNusach('sephard'), [
        ...rcAshkenaz,
        const VerseRange(
          book: 'שמואל א',
          fromCh: 20,
          fromVs: 18,
          toCh: 20,
          toVs: 18,
        ),
        const VerseRange(
          book: 'שמואל א',
          fromCh: 20,
          fromVs: 42,
          toCh: 20,
          toVs: 42,
        ),
      ]);
    });

    test('מסעי בשבת ר"ח: בארץ ישראל אשכנז ב"השמים כסאי", בחו"ל "שמעו"', () {
      final israel = _byId('h:Masei on Shabbat Rosh Chodesh (Israel)');
      final diaspora = _byId('h:Masei on Shabbat Rosh Chodesh');
      expect(israel.land, 'israel');
      expect(diaspora.land, 'diaspora');
      expect(israel.forNusach('ashkenaz'), rcAshkenaz);
      expect(diaspora.forNusach('ashkenaz').first.book, 'ירמיהו');
      // הספרדים אומרים "שמעו" בשתי הארצות.
      expect(israel.sephard, diaspora.sephard);
    });
  });

  test('שמחת תורה: ספרדים מסיימים ביהושע א, ט', () {
    expect(
      _byId('h:Simchat Torah').forNusach('sephard'),
      _byId('p:Vezot Haberakhah').forNusach('sephard'),
    );
    expect(_byId('h:Simchat Torah').forNusach('sephard').single.toVs, 9);
  });

  test('שם קדושים כולל את ההערה על סיום ההפטרה', () {
    expect(_byId('p:Kedoshim').name, contains('יש הקוראים עד כב, טז'));
  });
}

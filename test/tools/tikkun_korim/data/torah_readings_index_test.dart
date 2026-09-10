import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/data/tikkun_data.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';

const _lands = {'israel', 'diaspora', 'both'};
const _nusachim = {'ashkenaz', 'sephard'};

TorahReading _byId(String id) =>
    TikkunData.torahReadings.firstWhere((r) => r.id == id);

List<String> _ranges(String id) => _byId(id).aliyot
    .map(
      (a) =>
          '${a.aliyaLabel} ${a.range.book} '
          '${a.range.fromCh}:${a.range.fromVs}-${a.range.toCh}:${a.range.toVs}',
    )
    .toList();

void main() {
  final readings = TikkunData.torahReadings;

  group('תקינות כללית של טבלת הקריאות', () {
    test('אין מזהים כפולים', () {
      final ids = readings.map((r) => r.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('כל ערך: ארץ ונוסח מתוך הערכים המותרים, וקטגוריה מוכרת', () {
      for (final r in readings) {
        expect(_lands, contains(r.land), reason: r.id);
        if (r.nusach != null) {
          expect(_nusachim, contains(r.nusach), reason: r.id);
        }
        expect(
          TikkunData.torahReadingsCategories.keys,
          contains(r.category),
          reason: r.id,
        );
        expect(r.aliyot, isNotEmpty, reason: r.id);
      }
    });

    test('כל טווח: ספר מוכר, פרק ופסוק חיוביים, ותחילה לפני סוף', () {
      final bookNames = TikkunData.torahBooks.values.map((b) => b.name).toSet();
      for (final r in readings) {
        for (final a in r.aliyot) {
          final where = '${r.id} / ${a.aliyaLabel}';
          expect(bookNames, contains(a.range.book), reason: where);
          expect(a.range.fromCh, greaterThan(0), reason: where);
          expect(a.range.fromVs, greaterThan(0), reason: where);
          expect(a.aliyaLabel, isNotEmpty, reason: where);
          final from = a.range.fromCh * 1000 + a.range.fromVs;
          final to = a.range.toCh * 1000 + a.range.toVs;
          expect(from, lessThanOrEqualTo(to), reason: where);
        }
      }
    });
  });

  group('חנוכה', () {
    test("יום א' — צורת הרמ\"א לאשכנז וצורת השו\"ע לספרדי", () {
      expect(_byId('tr:Chanukah Day 1').nusach, 'ashkenaz');
      expect(_ranges('tr:Chanukah Day 1'), [
        'ראשון במדבר 7:1-7:11',
        'שני במדבר 7:12-7:14',
        'שלישי במדבר 7:15-7:17',
      ]);
      final sephard = _byId('custom:Chanukah Day 1 Sephard');
      expect(sephard.nusach, 'sephard');
      expect(_ranges(sephard.id), [
        'ראשון במדבר 6:22-7:3',
        'שני במדבר 7:4-7:11',
        'שלישי במדבר 7:12-7:17',
      ]);
    });

    test("יום ו' בא\"י הוא ראש חודש טבת — ג' עולים דר\"ח ורביעי דחנוכה", () {
      expect(_ranges('custom:Chanukah Day 6 IL'), [
        'ראשון במדבר 28:1-28:5',
        'שני במדבר 28:6-28:10',
        'שלישי במדבר 28:11-28:15',
        'רביעי במדבר 7:42-7:47',
      ]);
      expect(
        _ranges('custom:Chanukah Day 6 IL'),
        _ranges('tr:Chanukah Day 6'),
      );
    });

    test('שבת ראש חודש חנוכה — מפטיר לפי היום השישי או השביעי', () {
      expect(
        _ranges('tr:Shabbat Rosh Chodesh Chanukah').last,
        'מפטיר במדבר 7:42-7:47',
      );
      expect(
        _ranges('custom:Shabbat Rosh Chodesh Chanukah Day 7').last,
        'מפטיר במדבר 7:48-7:53',
      );
    });
  });

  group('סוכות', () {
    test('לשבת חוה"מ יש מפטיר לכל יום אפשרי, בשתי הצורות', () {
      for (final day in [3, 5, 6]) {
        final israel = _byId('custom:Sukkot Shabbat CHM Day $day IL');
        final diaspora = _byId('custom:Sukkot Shabbat CHM Day $day');
        expect(israel.land, 'israel');
        expect(diaspora.land, 'diaspora');
        expect(israel.aliyot.length, 8);
        expect(israel.aliyot.last.aliya, 'M');
        expect(diaspora.aliyot.last.aliya, 'M');
        final il = israel.aliyot.last.range;
        final ch = diaspora.aliyot.last.range;
        expect(il.toVs, ch.toVs);
        expect(ch.fromVs, il.fromVs - 3);
      }
      expect(
        TikkunData.torahReadings.where(
          (r) => r.id == 'tr:Sukkot Shabbat Chol ha-Moed',
        ),
        isEmpty,
      );
    });

    test('הושענא רבה — צורת החזרה בא"י מול ספיקא דיומא בחו"ל', () {
      expect(_byId('tr:Sukkot Final Day (Hoshana Raba)').land, 'diaspora');
      expect(_ranges('custom:Hoshana Raba IL'), [
        'ראשון במדבר 29:32-29:34',
        'שני במדבר 29:32-29:34',
        'שלישי במדבר 29:32-29:34',
        'רביעי במדבר 29:32-29:34',
      ]);
    });

    test('שמחת תורה — תוויות חתן תורה, חתן בראשית וחתן מעונה', () {
      for (final id in ['custom:Shmini Atzeret IL', 'tr:Simchat Torah']) {
        expect(_byId(id).nusach, 'ashkenaz');
        final labels = _byId(id).aliyot.map((a) => a.aliyaLabel);
        expect(labels, containsAll(['חתן תורה', 'חתן בראשית']));
        final sephard = _byId('$id Sephard');
        expect(sephard.nusach, 'sephard');
        expect(
          sephard.aliyot.map((a) => a.aliyaLabel),
          containsAll(['חתן מעונה', 'חתן תורה', 'חתן בראשית']),
        );
        final maonah = sephard.aliyot
            .firstWhere((a) => a.aliyaLabel == 'חתן מעונה')
            .range;
        expect(maonah.book, 'דברים');
        expect(
          [maonah.fromCh, maonah.fromVs, maonah.toCh, maonah.toVs],
          [
            33,
            27,
            33,
            29,
          ],
        );
      }
    });
  });

  group('ראש חודש ותעניות', () {
    test('חלופת הגר"א: לוי עד סוף הפרשה והשלישי חוזר', () {
      expect(_ranges('custom:Rosh Chodesh Gra'), [
        'ראשון במדבר 28:1-28:3',
        'שני במדבר 28:4-28:8',
        'שלישי במדבר 28:6-28:10',
        'רביעי במדבר 28:11-28:15',
      ]);
    });

    test('שם קריאת התענית מציין שחרית ומנחה', () {
      expect(_byId('tr:Fast Day (Morning)').name, 'תענית ציבור (שחרית ומנחה)');
    });
  });
}

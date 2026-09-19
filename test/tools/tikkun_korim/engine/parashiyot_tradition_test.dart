/// פרשיות תלויות-מסורת: המסד מסמן בהערת שוליים פרשה שאינה קיימת בכל הספרים,
/// והמנוע בוחר אותה לפי שיטת החלוקה.
library;

import 'package:otzaria/tools/tikkun_korim/tikkun_korim.dart';
import 'package:test/test.dart';

import '../support/tikkun_fixtures.dart';

/// קטע HTML במבנה של המסד: שני פסוקים, כל אחד עם סמן פתוחה שתלויה בו הערה.
const String _syntheticVayikra7 =
    '<h2>PEREK</h2>\n'
    '(20) AAA BBB&nbsp;<span class="mam-spi-pe">{PE}</span> '
    '<sup class="footnote-marker">*</sup>'
    '<i class="footnote">(NOTE_SEPH)</i>\n'
    '(21) CCC DDD&nbsp;<span class="mam-spi-pe">{PE}</span> '
    '<sup class="footnote-marker">*</sup>'
    '<i class="footnote">(NOTE_TEIMAN)</i>\n'
    '(22) EEE FFF\n';

/// מספרי הפסוקים שאחריהם עומדת פתוחה, בפרק [chapter].
List<int> _petuchaAfterVerses(List<TikkunToken> tokens, int chapter) {
  final out = <int>[];
  var ch = 0;
  var vs = 0;
  for (final tok in tokens) {
    switch (tok.type) {
      case TikkunTokenType.chapterBreak:
        ch = tok.chapterNum!;
      case TikkunTokenType.verseBreak:
        vs = tok.verseNum!;
      case TikkunTokenType.petucha:
        if (ch == chapter) out.add(vs);
      default:
        break;
    }
  }
  return out;
}

({int pe, int samekh}) _countParashiyot(List<TikkunToken> tokens) {
  var pe = 0;
  var samekh = 0;
  for (final tok in tokens) {
    if (tok.type == TikkunTokenType.petucha) pe++;
    if (tok.type == TikkunTokenType.setuma) samekh++;
  }
  return (pe: pe, samekh: samekh);
}

void main() {
  group('בחירת פרשה לפי מסורת — קטע סינתטי במבנה המסד', () {
    final html = _syntheticVayikra7
        .replaceAll('PEREK', 'פרק ז')
        .replaceAll('{PE}', '{פ}')
        .replaceAll('AAA BBB', 'אבג דהו')
        .replaceAll('CCC DDD', 'זחט יכל')
        .replaceAll('EEE FFF', 'מנס עפצ')
        .replaceAll('(20)', '(כ)')
        .replaceAll('(21)', '(כא)')
        .replaceAll('(22)', '(כב)')
        .replaceAll('NOTE_SEPH', 'אין פרשה בספרי ספרד ואשכנז')
        .replaceAll('NOTE_TEIMAN', 'אין פרשה בספרי תימן');

    test('רמ"ה / רמ"ח — נשארת רק הפתוחה שאינה בספרי תימן', () {
      final tokens = tokenizeText(cleanRawText(html));
      final kept = filterByTradition(
        tokens,
        TikkunTradition.ashkenazSephard,
      );
      expect(_petuchaAfterVerses(kept, 7), [21]);
    });

    test('rambamRosh — נשארת רק הפתוחה שאינה בספרי ספרד ואשכנז', () {
      final tokens = tokenizeText(cleanRawText(html));
      final kept = filterByTradition(tokens, TikkunTradition.yemen);
      expect(_petuchaAfterVerses(kept, 7), [20]);
    });

    test('בלי סינון — שתי הפתוחות, כנוסח הכתר', () {
      final tokens = tokenizeText(cleanRawText(html));
      expect(_petuchaAfterVerses(tokens, 7), [20, 21]);
    });

    test('השיטה נגזרת מהמזהה', () {
      expect(
        TikkunTradition.forMethod('rambamRosh'),
        TikkunTradition.yemen,
      );
      for (final id in ['ramah', 'ramach', 'single_page', '']) {
        expect(
          TikkunTradition.forMethod(id),
          TikkunTradition.ashkenazSephard,
          reason: id,
        );
      }
    });
  });

  group("מניין הפרשיות בכל התורה — לשון הרמב\"ם (הל' ס\"ת ח, ד)", () {
    // הסיכומים שהרמב"ם מונה בעצמו בסוף ההלכה: (פתוחות, סתומות).
    const rambamCounts = {
      'bereshit': (43, 48),
      'shemot': (69, 95),
      'vayikra': (52, 46),
      'bamidbar': (92, 66),
      'devarim': (34, 124),
    };

    for (final tradition in TikkunTradition.values) {
      test('${tradition.id} — 290 פתוחות ו-379 סתומות, לפי חומש', () {
        var totalPe = 0;
        var totalSamekh = 0;
        for (final entry in rambamCounts.entries) {
          final book = TikkunData.torahBooks[entry.key]!;
          final counts = _countParashiyot(
            tokenizeBook(
              readFixture(entry.key),
              book.name,
              tradition: tradition,
            ),
          );
          expect(
            (counts.pe, counts.samekh),
            entry.value,
            reason: entry.key,
          );
          totalPe += counts.pe;
          totalSamekh += counts.samekh;
        }
        expect(totalPe, 290);
        expect(totalSamekh, 379);
      });
    }

    test("פסוקים ס' ו-פ' אינם נקראים כסמני פרשה", () {
      final tokens = tokenizeBook(readFixture('bamidbar'), 'במדבר');
      final verses = <int>[];
      var ch = 0;
      for (final tok in tokens) {
        if (tok.type == TikkunTokenType.chapterBreak) ch = tok.chapterNum!;
        if (tok.type == TikkunTokenType.verseBreak && ch == 7) {
          verses.add(tok.verseNum!);
        }
      }
      expect(verses, containsAll([60, 80]));
    });
  });

  group('ויקרא — הפרשה השנויה במחלוקת', () {
    late String raw;

    setUpAll(() => raw = readFixture('vayikra'));

    test('הפתוחה השנויה במחלוקת נופלת במקום אחר בכל מסורת', () {
      final ashkenaz = _petuchaAfterVerses(
        tokenizeBook(raw, 'ויקרא'),
        7,
      );
      final yemen = _petuchaAfterVerses(
        tokenizeBook(raw, 'ויקרא', tradition: TikkunTradition.yemen),
        7,
      );
      expect(ashkenaz, contains(27));
      expect(ashkenaz, isNot(contains(21)));
      expect(yemen, contains(21));
      expect(yemen, isNot(contains(27)));
    });
  });

  group('נו"ן מנוזרת', () {
    test('"ויהי בנסוע" — נו"ן הפוכה לפני הקטע ואחריו', () {
      final tokens = tokenizeBook(readFixture('bamidbar'), 'במדבר');
      final nunIndices = <int>[];
      var ch = 0;
      var vs = 0;
      final at = <(int, int)>[];
      for (var i = 0; i < tokens.length; i++) {
        final tok = tokens[i];
        if (tok.type == TikkunTokenType.chapterBreak) ch = tok.chapterNum!;
        if (tok.type == TikkunTokenType.verseBreak) vs = tok.verseNum!;
        if (tok.isWord && tok.value!.contains(kNunHafukha)) {
          nunIndices.add(i);
          at.add((ch, vs));
        }
      }
      expect(nunIndices.length, 2);
      expect(at, [(10, 35), (10, 36)]);
    });

    test('הנו"ן ההפוכה שורדת את הסרת הניקוד', () {
      expect(stripNikud(kNunHafukha), kNunHafukha);
      expect(stripNikud('אָ'), 'א');
    });
  });
}

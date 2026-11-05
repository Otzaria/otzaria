import 'package:otzaria/tools/tikkun_korim/tikkun_korim.dart';
import 'package:test/test.dart';

import '../support/tikkun_fixtures.dart';

void main() {
  setUp(() => variantNoteScans = 0);

  test('ספר בלי הערות חילוף אינו נסרק בביטויי הנוסח', () {
    final raw = readFixture('yeshayahu');
    cleanRawText(raw, tradition: TikkunTradition.ashkenazSephard);
    applyMegillahNusach(raw, 'ashkenaz');
    expect(variantNoteScans, 0);
  });

  test('ספר עם הערות חילוף נסרק', () {
    cleanRawText(
      readFixture('bereshit'),
      tradition: TikkunTradition.ashkenazSephard,
    );
    applyMegillahNusach(readFixture('esther'), 'ashkenaz');
    expect(variantNoteScans, 2);
  });

  for (final name in ['yeshayahu', 'shoftim', 'shmuel_b']) {
    test('$name — בחירת מסורת בלי הערות חילוף אינה משנה את הניקוי', () {
      final raw = readFixture(name);
      for (final tradition in TikkunTradition.values) {
        expect(cleanRawText(raw, tradition: tradition), cleanRawText(raw));
      }
      expect(applyMegillahNusach(raw, 'ashkenaz'), raw);
    });
  }

  group('החלפה לפני <sup זהה ל-replaceAllMapped', () {
    const word =
        r'(?:<(?:big|small)>)?[א-ת]'
        r'(?:[א-ת\u0591-\u05bd\u05bf\u05c1\u05c2\u05c4\u05c5\u05c7]|</?(?:big|small)>)*';
    final patterns = [
      RegExp(
        '($word)<sup[^>]*class="footnote-marker"[^>]*>[^<]*</sup>\\s*'
        r'<i[^>]*class="footnote"[^>]*>\(([^<()]*)\)</i>',
      ),
      RegExp('((?:$word[־\\s]+)?)($word)<sup[^>]*>([^<]*)</sup>'),
      RegExp('($word)<sup'),
    ];
    String replace(Match m) =>
        '{${[for (var g = 1; g <= m.groupCount; g++) m[g]].join('|')}}';

    const edges = [
      '',
      'אבג',
      '<sup>*</sup>',
      'א<sup>*</sup>',
      '<big>א</big>בג<sup>*</sup>',
      'אב<small>ג</small><sup>*</sup>',
      'x אבג<sup>*</sup>',
      'אב־גד הו<sup>*</sup> זח',
      'אב<sup>*</sup>גד<sup>*</sup>',
      'אב<sup ג<sup>*</sup>',
      'אב\u00a0גד\n<big>הו</big> <sup>*</sup>',
      '<b>אב</b><sup>*</sup>',
      'אב (גד)<sup>*</sup>',
      'אבג<sup class="footnote-marker">*</sup>'
          '<i class="footnote">(בספרי תימן אבד)</i> דה<sup>*</sup>',
    ];
    final texts = [
      ...edges,
      for (final id in fixtureBookNames.keys) readFixture(id),
    ];

    for (var p = 0; p < patterns.length; p++) {
      test('ביטוי $p', () {
        for (final text in texts) {
          expect(
            replaceBeforeSup(text, patterns[p], replace),
            text.replaceAllMapped(patterns[p], replace),
            reason: escapeNonAscii(
              text.length > 80 ? text.substring(0, 80) : text,
            ),
          );
        }
      });
    }
  });
}

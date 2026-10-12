import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

// אורקל: המימוש מבוסס-allMatches, שהמימוש הנוכחי חייב להחזיר בדיוק כמוהו.
final RegExp _oracleHolyName = RegExp(
  r"י([\p{Mn}]*)ה([\p{Mn}]*)ו([\p{Mn}]*)ה([\p{Mn}]*)",
  unicode: true,
);

String _oracle(String s, HolyNameStyle style) {
  return s.replaceAllMapped(_oracleHolyName, (match) {
    var letters = 0;
    for (var index = match.start - 1; index >= 0; index--) {
      final char = s[index];
      if (RegExp(r'[\p{Mn}]', unicode: true).hasMatch(char)) continue;
      if (RegExp(r'[א-ת]').hasMatch(char)) {
        if (++letters >= 3) return match.group(0)!;
        continue;
      }
      break;
    }
    return style == HolyNameStyle.hehApostrophe
        ? "ה'"
        : 'י${match[1]}ק${match[2]}ו${match[3]}ק${match[4]}';
  });
}

const _line =
    'וַיֹּ֥אמֶר יְהוָ֖ה אֶל־מֹשֶׁ֣ה, ואמר יהוה לאברהם, ויהודה ויהיה '
    'בני יהויכין והוה יה, י\u{1D167}הוה <b>יהוה</b> ';

void main() {
  group('replaceHolyNames', () {
    test('זהה לאורקל בקלט קצה ובקלט אקראי', () {
      final inputs = <String>['', 'י', 'יה', 'יהו', 'יהוה', _line, 'אבגיהוה'];
      final random = Random(11);
      const pool = [
        'י',
        'ה',
        'ו',
        'ק',
        'א',
        ' ',
        '<',
        '>',
        'ְ',
        'ָ',
        '֖',
        'ּ',
        '̀',
        '\u{1D167}',
        'a',
        '־',
      ];
      for (var i = 0; i < 5000; i++) {
        inputs.add(
          [
            for (var j = random.nextInt(14); j > 0; j--)
              pool[random.nextInt(pool.length)],
          ].join(),
        );
      }
      for (final input in inputs) {
        for (final style in HolyNameStyle.values) {
          expect(
            replaceHolyNames(input, style: style),
            _oracle(input, style),
            reason: input,
          );
        }
      }
    });

    test('זהה לאורקל לכל יחידת קוד שלפני השם', () {
      for (var c = 0; c <= 0xFFFF; c++) {
        final unit = String.fromCharCode(c);
        for (final input in ['אב$unitיהוה', 'א$unitבגיהוה', '$unitיהוה']) {
          for (final style in HolyNameStyle.values) {
            expect(
              replaceHolyNames(input, style: style),
              _oracle(input, style),
              reason: 'U+${c.toRadixString(16)}',
            );
          }
        }
      }
    });

    test('בשורה ארוכה מהיר לפחות פי 3 מהאורקל', () {
      // כמו בשורות הארוכות בספרייה: מאות אלפי תווים ללא ניקוד, מעט מופעי השם.
      final line = [
        for (var i = 0; i < 20000; i++)
          i % 500 == 0 ? 'ואמר יהוה ' : 'אמר רבי יהודה בשם רב ',
      ].join();
      int best(String Function() run) {
        var best = 1 << 62;
        for (var r = 0; r < 5; r++) {
          final sw = Stopwatch()..start();
          run();
          if (sw.elapsedMicroseconds < best) best = sw.elapsedMicroseconds;
        }
        return best;
      }

      expect(replaceHolyNames(line), _oracle(line, HolyNameStyle.kufKuf));
      final current = best(() => replaceHolyNames(line));
      final oracle = best(() => _oracle(line, HolyNameStyle.kufKuf));
      expect(current * 3, lessThan(oracle), reason: '$current vs $oracle');
    });
  });
}

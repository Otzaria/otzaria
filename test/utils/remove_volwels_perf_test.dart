import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

// אורקל: המימוש מבוסס-הרגקס, שהמימוש הנוכחי חייב להחזיר בדיוק כמוהו.
final RegExp _oracleVowels = RegExp(r'[֑-ׇ]');

String _oracleRemoveVolwels(String s) {
  s = s.replaceAll('־', ' ').replaceAll('׀', ' ').replaceAll('|', ' ');
  return s.replaceAll(_oracleVowels, '');
}

const _vocalizedLine =
    '<b>בְּרֵאשִׁ֖ית</b> בָּרָ֣א אֱלֹהִ֑ים אֵ֥ת הַשָּׁמַ֖יִם, וְאֵ֥ת הָאָֽרֶץ׃ '
    'וַיֹּ֥אמֶר יְהוָ֖ה אֶל־מֹשֶׁ֣ה לֵּאמֹ֑ר ׀ דַּבֵּ֞ר אֶל־בְּנֵ֣י יִשְׂרָאֵ֗ל | '
    'רש"י: אין המקרא הזה אומר אלא דרשני (ע"ש.) וכו\' 😀 abc.';

void main() {
  group('removeVolwels', () {
    test('reuses clean text without allocating a copy', () {
      for (final line in [
        'Plain English book content with words and punctuation. ',
        'Latin1 é ÿ café 123 ',
        'בראשית ברא אלהים את השמים ואת הארץ ',
        'English עברית é 中文 😀 \u0590\u05C8 ',
        String.fromCharCodes([0xD83D, 0x41, 0xDE00]),
      ]) {
        final input = List.filled(40, line).join();
        expect(identical(removeVolwels(input), input), isTrue);
      }
    });

    test('cleans the full range after a Unicode prefix', () {
      final prefix = List.filled(40, 'English עברית 😀 é ').join();
      final range = String.fromCharCodes([
        for (var c = 0x0591; c <= 0x05C7; c++) c,
      ]);
      final input = '$prefix$range|\u0590\u05C8😀';
      expect(removeVolwels(input), '$prefix   \u0590\u05C8😀');
    });

    test('identical to the regex oracle on edge and random input', () {
      final inputs = <String>[
        '',
        _vocalizedLine,
        _oracleRemoveVolwels(_vocalizedLine),
        '־׀|',
        // גבולות הטווח: U+0590 ו-U+05C8 נשמרים, U+0591 ו-U+05C7 נמחקים.
        '\u0590\u0591\u05C7\u05C8\u05BD\u05BF',
        'a\u{1F600}b\u05B0',
      ];
      final random = Random(7);
      const pool = [0x20, 0x7C, 0x41, 0x05BE, 0x05C0, 0x05D0, 0x05EA, 0xD83D];
      for (var i = 0; i < 2000; i++) {
        final length = random.nextInt(40);
        inputs.add(
          String.fromCharCodes([
            for (var j = 0; j < length; j++)
              random.nextBool()
                  ? 0x0588 + random.nextInt(0x48)
                  : pool[random.nextInt(pool.length)],
          ]),
        );
      }
      for (final input in inputs) {
        expect(removeVolwels(input), _oracleRemoveVolwels(input));
      }
    });

    test('at least 3x faster than the regex oracle on vocalized lines', () {
      final lines = [
        for (var i = 0; i < 20000; i++) '$_vocalizedLine $i',
      ];
      int timeMicros(String Function(String) clean) {
        for (final line in lines.take(500)) {
          clean(line);
        }
        final stopwatch = Stopwatch()..start();
        var length = 0;
        for (final line in lines) {
          length += clean(line).length;
        }
        stopwatch.stop();
        expect(length, greaterThan(0));
        return stopwatch.elapsedMicroseconds;
      }

      // מינימום של מדידות לסירוגין: מסנן הפרעות GC ו-JIT בסביבת CI עמוסה.
      var oracle = 1 << 62;
      var current = 1 << 62;
      for (var round = 0; round < 5; round++) {
        oracle = min(oracle, timeMicros(_oracleRemoveVolwels));
        current = min(current, timeMicros(removeVolwels));
      }
      expect(
        current * 3,
        lessThan(oracle),
        reason: 'oracle ${oracle}us, current ${current}us',
      );
    });
  });
}

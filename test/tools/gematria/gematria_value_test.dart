import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/gematria/gematria_search.dart';

// אורקל: המימוש לפי runes ומפת מחרוזות, שהמימוש הנוכחי חייב להחזיר בדיוק כמוהו.
const _letters = 'אבגדהוזחטיכךלמםנןסעפףצץקרשת';
const _regular = [
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 20, 30, 40, 40, 50, 50, 60, 70, 80, 80, //
  90, 90, 100, 200, 300, 400,
];
const _small = [
  1, 2, 3, 4, 5, 6, 7, 8, 9, 1, 2, 2, 3, 4, 4, 5, 5, 6, 7, 8, 8, 9, 9, 1, 2, //
  3, 4,
];
const _finalLetters = [
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 500, 30, 40, 600, 50, 700, 60, 70, 80, //
  800, 90, 900, 100, 200, 300, 400,
];

Map<String, int> _mapOf(List<int> values) => {
  for (var i = 0; i < _letters.length; i++) _letters[i]: values[i],
};
final _regularMap = _mapOf(_regular);
final _smallMap = _mapOf(_small);
final _finalLettersMap = _mapOf(_finalLetters);

int _oracleGimatria(String text, String method) {
  final map = switch (method) {
    'small' => _smallMap,
    'finalLetters' => _finalLettersMap,
    _ => _regularMap,
  };
  var sum = 0;
  for (final r in text.runes) {
    sum += map[String.fromCharCode(r)] ?? 0;
  }
  return sum;
}

const _verse =
    'בְּרֵאשִׁ֖ית בָּרָ֣א אֱלֹהִ֑ים אֵ֥ת הַשָּׁמַ֖יִם וְאֵ֥ת הָאָֽרֶץ '
    'וְהָאָ֗רֶץ הָיְתָ֥ה תֹ֙הוּ֙ וָבֹ֔הוּ וְחֹ֖שֶׁךְ עַל־פְּנֵ֣י תְה֑וֹם';

void main() {
  const methods = ['regular', 'small', 'finalLetters', 'unknown'];

  test('gimatria identical to the runes oracle on edge and random input', () {
    final inputs = <String>[
      '',
      _verse,
      _letters,
      // גבולות הטווח: U+05CF ו-U+05EB אינם אותיות; זוג surrogate אינו נספר.
      '׏את׫',
      'a\u{1F600}ב\uD800',
    ];
    final random = Random(11);
    for (var i = 0; i < 2000; i++) {
      final length = random.nextInt(30);
      inputs.add(
        String.fromCharCodes([
          for (var j = 0; j < length; j++)
            random.nextInt(4) == 0
                ? [0x20, 0x41, 0xD83D, 0xDE00][random.nextInt(4)]
                : 0x0590 + random.nextInt(0x60),
        ]),
      );
    }
    for (final method in methods) {
      for (final input in inputs) {
        expect(
          GimatriaSearch.gimatria(input, method: method),
          _oracleGimatria(input, method),
          reason: '$method: $input',
        );
      }
    }
  });
}

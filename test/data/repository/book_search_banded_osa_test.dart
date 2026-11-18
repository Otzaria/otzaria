import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/data_repository.dart';

void main() {
  test('word matching agrees with full OSA across edit thresholds', () {
    final suffixes = <String>[''];
    for (var length = 1; length <= 5; length++) {
      for (var bits = 0; bits < 1 << length; bits++) {
        suffixes.add(
          [
            for (var i = 0; i < length; i++) (bits & (1 << i)) == 0 ? 'a' : 'b',
          ].join(),
        );
      }
    }
    for (final padding in [0, 5, 9, 13]) {
      final prefix = List.filled(padding, 'p').join();
      for (final a in suffixes) {
        for (final b in suffixes) {
          _expectReference('$prefix$a', '$prefix$b');
        }
      }
    }
  });

  test('word matching agrees with full OSA on deterministic mutations', () {
    final random = Random(7301);
    for (var sample = 0; sample < 400; sample++) {
      final a = [
        for (var i = 0, n = 3 + random.nextInt(20); i < n; i++)
          'abc'[random.nextInt(3)],
      ].join();
      var b = a;
      for (var edit = 0, n = 1 + random.nextInt(6); edit < n; edit++) {
        final position = random.nextInt(b.length);
        switch (random.nextInt(4)) {
          case 0:
            b = b.replaceRange(position, position, 'abc'[random.nextInt(3)]);
          case 1:
            if (b.length > 1) b = b.replaceRange(position, position + 1, '');
          case 2:
            b = b.replaceRange(
              position,
              position + 1,
              'abc'[random.nextInt(3)],
            );
          case 3:
            if (position + 1 < b.length) {
              b = b.replaceRange(
                position,
                position + 2,
                '${b[position + 1]}${b[position]}',
              );
            }
        }
      }
      _expectReference(a, b);
      _expectReference(b, a);
    }
  });

  test('one-edit matching preserves the unchanged suffix', () {
    const pairs = [
      ('abcdef', 'abxcdef', true),
      ('abcdef', 'abqdef', true),
      ('aabcde', 'abacde', true),
      ('abcdef', 'abcedf', true),
      ('abcdef', 'abxcdyf', false),
      ('abcdef', 'bacdez', false),
      ('abcdef', 'cbadef', false),
    ];
    for (final (a, b, expected) in pairs) {
      expect(bookSearchWordPairMatches(a, b), expected, reason: '$a / $b');
      expect(bookSearchWordPairMatches(b, a), expected, reason: '$b / $a');
    }
  });

  test('adjacent transposition survives at either edge of the band', () {
    const pairs = [
      ('abcde', 'bacde'),
      ('abcde', 'abced'),
      ('abcdefghi', 'xbacdefghi'),
      ('abcdefghi', 'bacdefgh'),
      ('abcdefghijklm', 'xybacdefghijklm'),
      ('abcdefghijklmnopq', 'xyzbacdefghijklmnopq'),
    ];
    for (final (a, b) in pairs) {
      expect(bookSearchWordPairMatches(a, b), isTrue, reason: '$a / $b');
      expect(bookSearchWordPairMatches(b, a), isTrue, reason: '$b / $a');
    }
  });
}

void _expectReference(String query, String text) {
  final length = max(query.length, text.length);
  final allowed = length <= 4
      ? 0
      : length <= 8
      ? 1
      : length <= 12
      ? 2
      : length <= 16
      ? 3
      : 4;
  // ASCII אינו מפעיל את כללי הכתיב העברי; ההכלה עדיין קודמת ל-OSA.
  final expected =
      text.contains(query) ||
      (query.length >= 3 && allowed > 0 && _osa(query, text) <= allowed);
  expect(
    bookSearchWordPairMatches(query, text),
    expected,
    reason: '$query / $text',
  );
}

int _osa(String a, String b) {
  final table = List.generate(
    a.length + 1,
    (i) => List.generate(
      b.length + 1,
      (j) => i == 0
          ? j
          : j == 0
          ? i
          : 0,
    ),
  );
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      table[i][j] = min(
        table[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
        min(table[i - 1][j] + 1, table[i][j - 1] + 1),
      );
      if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
        table[i][j] = min(table[i][j], table[i - 2][j - 2] + 1);
      }
    }
  }
  return table[a.length][b.length];
}

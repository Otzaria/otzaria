import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/utils/find_match_utils.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

import '../support/search_engine_test_init.dart';

String _referenceNormalizeFindText(String rawText) {
  var cleaned = utils.removeVolwels(rawText);
  cleaned = cleaned.replaceAll('"', '').replaceAll("'", '');
  cleaned = cleaned.replaceAll('״', '').replaceAll('׳', '');
  cleaned = cleaned.replaceAll(
    RegExp(r'[^a-zA-Z0-9\u0590-\u05FF\s/]'),
    ' ',
  );
  return cleaned.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}

Future<void> main() async {
  // sanitizeQuery/splitQueryWords מאצילים למנוע ה-Rust; הטסטים שלהם דורשים
  // את הספרייה הנייטיבית ומדולגים כשאין build זמין.
  final engineReady = await tryInitSearchEngine();

  test(
    'normalizeFindQuery מנרמל ניקוד וגרשיים כמו איתור',
    () {
      expect(normalizeFindQuery('שַׁבָּת "דף" ע׳'), 'שבת דף ע');
    },
    skip: engineReady ? false : searchEngineSkipReason,
  );

  test(
    'normalizeFindRankText שקול לנרמול השאילתה ללא FFI',
    () {
      const samples = [
        'שו”ע ותוס‘',
        'פ.ב.י יב[ע]ר 3.14',
        'א־ב|ג,ד;ה!ו?ז(ח){ט}',
        'לה\uFEFFתיר שלום\u200Fעולם',
        'א\u202Bב\u202Cג',
        'שַׁבָּת "דף" ע׳',
        r'א*ב^ג$ד\ה+ו~ז`ח',
      ];

      for (final sample in samples) {
        expect(normalizeFindRankText(sample), normalizeFindQuery(sample));
      }
    },
    skip: engineReady ? false : searchEngineSkipReason,
  );

  test('normalizeFindText שומר על סמנטיקת האיתור', () {
    expect(
      normalizeFindText('  שַׁבָּת־דף׀ע|ב׳, Test/ABC  '),
      'שבת דף ע ב test/abc',
    );
  });

  test('normalizeFindText שקול למימוש הוותיק', () {
    const chars = [
      'א',
      'ב',
      'ַ',
      '־',
      '׀',
      '|',
      '"',
      "'",
      '״',
      '׳',
      'A',
      'z',
      '4',
      '/',
      ',',
      '.',
      ' ',
      '\t',
      '\n',
      '”',
      '\u200F',
    ];
    final random = Random(660);

    for (var i = 0; i < 500; i++) {
      final value = List.generate(
        random.nextInt(40),
        (_) => chars[random.nextInt(chars.length)],
      ).join();
      expect(normalizeFindText(value), _referenceNormalizeFindText(value));
    }
  });

  test('findNormalizedTextMatchRank מעדיף התאמה מדויקת על contains', () {
    const query = 'שבת דף ע';

    final exactRank = findNormalizedTextMatchRank(
      normalizedQuery: query,
      normalizedPrimaryText: normalizeFindText('שבת דף ע'),
    );
    final containsRank = findNormalizedTextMatchRank(
      normalizedQuery: query,
      normalizedPrimaryText: normalizeFindText('מאירי על שבת דף ע'),
    );

    expect(exactRank, lessThan(containsRank));
  });
}

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

// ---- אורקל: המימוש המקורי מבוסס-הרגקסים, מועתק כלשונו. ----
// כל שינוי ב-normalizeForFindRefMatch חייב להחזיר בדיוק את מה שהוא מחזיר.
final RegExp _oracleVowels = RegExp(r'[֑-ׇ]');
final RegExp _oracleCantillation = RegExp(r'[֑-֯]');

String _oracleRemoveVolwels(String s) {
  s = s.replaceAll('־', ' ').replaceAll('׀', ' ').replaceAll('|', ' ');
  return s.replaceAll(_oracleVowels, '');
}

String _oracleRemoveTeamim(String s) => s
    .replaceAll('־', ' ')
    .replaceAll(' ׀', '')
    .replaceAll('ֽ', '')
    .replaceAll('׀', '')
    .replaceAll(_oracleCantillation, '');

String oracleNormalize(String input) {
  var cleaned = _oracleRemoveTeamim(_oracleRemoveVolwels(input));
  cleaned = cleaned.replaceAllMapped(
    RegExp(r'''(?<![א-ת'"״׳])([א-ת]{1,3})\.(?=\s|$)'''),
    (m) => '${m[1]} א',
  );
  cleaned = cleaned.replaceAllMapped(
    RegExp(r'''(?<![א-ת'"״׳])([א-ת]{1,3}):(?=\s|$)'''),
    (m) => '${m[1]} ב',
  );
  cleaned = cleaned
      .replaceAll('"', '')
      .replaceAll("'", '')
      .replaceAll('״', '')
      .replaceAll('׳', '');
  cleaned = cleaned.replaceAll(RegExp(r'[^a-zA-Z0-9֐-׿\s]'), ' ');
  cleaned = cleaned.toLowerCase();
  return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
}

void _collectJsonStrings(Object? node, Set<String> out) {
  if (node is String) {
    out.add(node);
  } else if (node is List) {
    for (final e in node) {
      _collectJsonStrings(e, out);
    }
  } else if (node is Map) {
    for (final entry in node.entries) {
      _collectJsonStrings(entry.key, out);
      _collectJsonStrings(entry.value, out);
    }
  }
}

final RegExp _dartLiteral = RegExp('\'([^\'\\n]*)\'|"([^"\\n]*)"');
final RegExp _hasHebrew = RegExp(r'[֐-׿]');

/// מחרוזות מכל ה-fixtures, מ-Acronyms.json ומהליטרלים העבריים בטסטים.
Set<String> _loadCorpus() {
  final corpus = <String>{};
  for (final path in [
    'assets/Acronyms.json',
    'test/fixtures/ref_key_fixtures.json',
    'test/fixtures/toc/mikropedia_talmudit_toc.json',
  ]) {
    _collectJsonStrings(jsonDecode(File(path).readAsStringSync()), corpus);
  }
  for (final dir in ['test/find_ref', 'test/data', 'test/utils']) {
    for (final entity in Directory(dir).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      for (final m in _dartLiteral.allMatches(entity.readAsStringSync())) {
        final literal = m[1] ?? m[2]!;
        if (_hasHebrew.hasMatch(literal)) {
          // גרש/גרשיים מוברחים בקוד המקור — גם הצורה הגולמית וגם המפוענחת.
          corpus.add(literal);
          corpus.add(literal.replaceAll(r'\"', '"').replaceAll(r"\'", "'"));
        }
      }
    }
  }
  return corpus;
}

const List<String> _craftedCases = [
  '',
  ' ',
  '\t\n\r',
  'ברכות ב.',
  'ברכות ב:',
  'ברכות ב. ג:',
  'ברכות ב.ג:',
  'ברכות קכא.',
  'ברכות קכאב.',
  'ברכות ב.,',
  'ב.',
  'ב:',
  ':ב',
  '.ב',
  'פ"א.',
  'פ״א.',
  "פ'א.",
  'פ׳א.',
  'ע"א.',
  'רמב"ם.',
  'שו"ע או"ח א.',
  'ברכות ב ע"א',
  'ברכות ב ע״ב',
  "ברכות ב ע'א",
  'ברכות ב ע׳ב',
  'ברכות עא',
  'בְּרֵאשִׁית א.',
  'בְּ֧רֵאשִׁ֖ית',
  'בְּ. ג:',
  'מִ־שָּׁם',
  'ויאמר ׀ אלהים',
  'ויאמר׀ אלהים',
  'אב|גד',
  'שולחן ערוך, אורח חיים - סימן א׃ ב',
  'Genesis 1:1',
  'GENESIS a.',
  'Tur O.C. 1',
  'abc. def:',
  'פרק 1.',
  'סימן 42:',
  'א   ב',
  'א ב',
  'א ב. ',
  'ב. ג',
  'ב. ',
  'ב.﻿',
  'ב.\u0085',
  'א‏ב',
  'א​ב.',
  'שבת 😀 ב.',
  '(ברכות ב.)',
  '[ברכות ב:]',
  'ברכות ב.:',
  'ברכות ב..',
  'ב.ג.ד.',
  'אבג. דהו: זחטי.',
  'ך. ם: ן. ף: ץ.',
  'ײ. װ:',
  'מ״ב ב.',
  'ה׳ א:',
  '״ב.',
  'ב״.',
  '"ב.',
  'ב".',
];

const List<String> _fuzzAlphabet = [
  'א', 'ב', 'ג', 'ע', 'ת', 'ך', 'ם', // אותיות
  'ְ', 'ּ', 'ׁ', 'ֹ', 'ׇ', // ניקוד
  '֑', '֧', '֖', 'ֽ', '֯', // טעמים ומתג
  '־', '׀', '|', // מקף, פסק, קו
  '"', "'", '״', '׳', // גרשיים
  '.', ':', ',', '-', '/', '(', ')', '׃',
  ' ', ' ', ' ', '\t', '\n', ' ', ' ', '﻿', '\u0085',
  'a', 'Z', 'q', '1', '9', '😀',
];

void main() {
  test('normalizeForFindRefMatch זהה לאורקל על כל הקורפוס', () {
    final corpus = {..._loadCorpus(), ..._craftedCases};
    expect(corpus.length, greaterThan(20000));
    final mismatches = <String>[];
    for (final s in corpus) {
      if (normalizeForFindRefMatch(s) != oracleNormalize(s)) mismatches.add(s);
    }
    expect(mismatches, isEmpty);
  });

  test('זהה לאורקל על כל יחידת UTF-16 בכמה הקשרים', () {
    final mismatches = <int>[];
    for (var c = 0; c <= 0xFFFF; c++) {
      final ch = String.fromCharCode(c);
      for (final s in [ch, "א$chב", "ב.$ch", "$chב: ג", "A${ch}z"]) {
        if (normalizeForFindRefMatch(s) != oracleNormalize(s)) {
          mismatches.add(c);
          break;
        }
      }
    }
    expect(mismatches, isEmpty);
  });

  test('זהה לאורקל על מחרוזות אקראיות (seed קבוע)', () {
    final random = Random(20260929);
    final mismatches = <String>[];
    for (var i = 0; i < 60000; i++) {
      final length = random.nextInt(14);
      final buffer = StringBuffer();
      for (var j = 0; j < length; j++) {
        buffer.write(_fuzzAlphabet[random.nextInt(_fuzzAlphabet.length)]);
      }
      final s = buffer.toString();
      if (normalizeForFindRefMatch(s) != oracleNormalize(s)) mismatches.add(s);
    }
    expect(mismatches, isEmpty);
  });
}

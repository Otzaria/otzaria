import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

final RegExp _oracleHtmlEntity = RegExp(
  r'&(#x?[0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);',
);

/// עותק של המימוש הקודם, שעבר תו-תו כמחרוזות. הקלטים בלי גרשיים:
/// הם מוכרעים לפני הלולאה ב-_stripQuotesOutsideTags ונבדקים ב-remove_punctuation_quotes_test.
String _oracleRemovePunctuation(String text) {
  if (text.isEmpty) return text;

  final hadHtmlBreaks = RegExp(
    r'<br\s*/?>',
    caseSensitive: false,
  ).hasMatch(text);
  final normalizedText = text
      .replaceAll(RegExp(r'\r\n?'), '\n')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');

  final lines = normalizedText.split('\n');
  final processedLines = <String>[];
  final originalEndsWithAllowed = <bool>[];

  for (final line in lines) {
    if (line.trim().isEmpty) {
      processedLines.add(line);
      originalEndsWithAllowed.add(true);
      continue;
    }

    originalEndsWithAllowed.add(RegExp(r'[.:](\s*)$').hasMatch(line));

    if (isHeadingLine(line.trim())) {
      processedLines.add(line);
      continue;
    }

    final processed = line;
    final lastAllowedPunctuationIndex = RegExp(
      r'[.:](\s*)$',
    ).firstMatch(processed)?.start;

    final buffer = StringBuffer();
    var parenDepth = 0;
    var inTag = false;
    for (var i = 0; i < processed.length; i++) {
      final ch = processed[i];

      if (inTag) {
        buffer.write(ch);
        if (ch == '>') inTag = false;
        continue;
      }
      if (ch == '<') {
        inTag = true;
        buffer.write(ch);
        continue;
      }
      if (ch == '&') {
        final entity = _oracleHtmlEntity.matchAsPrefix(processed, i);
        if (entity != null) {
          buffer.write(entity.group(0));
          i = entity.end - 1;
          continue;
        }
      }
      if (ch == '(') {
        parenDepth++;
        buffer.write(ch);
        continue;
      }
      if (ch == ')') {
        if (parenDepth > 0) parenDepth--;
        buffer.write(ch);
        continue;
      }

      final isPunctuation =
          ch == '!' ||
          ch == ':' ||
          ch == ';' ||
          ch == '.' ||
          ch == ',' ||
          ch == '?' ||
          ch == '-' ||
          ch == '—' ||
          ch == '–';

      if (parenDepth > 0 && (ch == ':' || ch == '.')) {
        buffer.write(ch);
        continue;
      }
      if (isPunctuation) {
        if (lastAllowedPunctuationIndex != null &&
            i >= lastAllowedPunctuationIndex &&
            (ch == '.' || ch == ':')) {
          buffer.write(ch);
        }
        continue;
      }
      buffer.write(ch);
    }
    processedLines.add(buffer.toString());
  }

  final finalResult = StringBuffer();
  var lastCharWasNewline = false;
  var lastCharWasSpace = false;
  for (var i = 0; i < processedLines.length; i++) {
    final line = processedLines[i];
    final shouldKeepNewline =
        originalEndsWithAllowed[i] ||
        isHeadingLine(line) ||
        (i < processedLines.length - 1 && isHeadingLine(processedLines[i + 1]));

    if (line.trim().isEmpty) {
      if (finalResult.isNotEmpty) {
        finalResult.write('\n');
        lastCharWasNewline = true;
        lastCharWasSpace = false;
      }
      finalResult.write(line);
      if (i < processedLines.length - 1) {
        finalResult.write('\n');
        lastCharWasNewline = true;
        lastCharWasSpace = false;
      }
      continue;
    }
    if (finalResult.isNotEmpty && !lastCharWasNewline && !lastCharWasSpace) {
      finalResult.write(' ');
      lastCharWasSpace = true;
      lastCharWasNewline = false;
    }
    finalResult.write(line);
    lastCharWasNewline = false;
    lastCharWasSpace = false;
    if (shouldKeepNewline && i < processedLines.length - 1) {
      finalResult.write('\n');
      lastCharWasNewline = true;
    }
  }

  final result = finalResult.toString();
  return hadHtmlBreaks ? result.replaceAll('\n', '<br>') : result;
}

const List<String> _fragments = [
  'א', 'ב', 'ש', 'ת', 'ְ', 'ּ', '֑', 'a', 'Z', '1', ' ', '  ', '\t', //
  '!', ':', ';', '.', ',', '?', '-', '—', '–', '־', '׀', '(', ')', //
  '<', '>', '<b>', '</b>', '<a href="x:y.z?a=1;b">', '<br>', '<BR />', //
  '&', '&nbsp;', '&#1488;', '&#x05B4;', '&amp', '&;', '\n', '\r', '\r\n', //
  '# ', '<h2>', '</h2>', '😀', '\uD83D', '\uDE00', '\u{10FFFF}', '\uFFFF', //
  '\u0000',
];

String _randomInput(Random random) {
  final length = random.nextInt(40);
  final buffer = StringBuffer();
  for (var i = 0; i < length; i++) {
    buffer.write(_fragments[random.nextInt(_fragments.length)]);
  }
  return buffer.toString();
}

const List<String> _plainWords = [
  'וַיֹּאמֶר', 'אֱלֹהִים,', 'יְהִי', 'אוֹר;', 'רבינו', 'תם!', '<b>כתב</b>', //
  'פירוש', '(עיין', 'שם:', 'דף', 'ב.)', '&nbsp;', 'והכי', 'איתא', '-', '—', //
];

/// שורה של 80–130 תווים מטקסט מנוקד, פיסוק, תגים וישויות - בלי גרשיים.
String _plainLine(Random random) {
  final target = 80 + random.nextInt(51);
  final buffer = StringBuffer();
  while (buffer.length < target) {
    buffer.write('${_plainWords[random.nextInt(_plainWords.length)]} ');
  }
  return '${buffer.toString().substring(0, target - 1)}.';
}

void main() {
  group('removePunctuation זהה למימוש הקודם', () {
    const edgeCases = [
      '',
      ' ',
      '\n',
      'אב.',
      'אב, גד; הו!',
      'א:ב (ג:ד. ה) ו.',
      '((א.) ב.) ג.',
      ')א.(',
      '<a href="a.b:c,d">ק.ש</a>, ב.',
      'א&nbsp;ב&#1488;;ג&amp;ד &x; ה&',
      '😀, 😀.',
      'a\uD83D,\uDE00b. \uDE00\uD83D:',
      '\uD83D',
      '\uDE00.',
      '\u{1F600}\u{10FFFF}—\u{20000}–',
      '<h1>כותרת, א.</h1>\nטקסט, ב\nסוף.',
      '# כותרת, א\nטקסט; ב',
      'א\r\nב.\rג<br>ד, <BR/>ה',
      '<b',
      'א<b.,>ב,',
    ];
    for (var i = 0; i < edgeCases.length; i++) {
      final input = edgeCases[i];
      test('מקרה קצה $i: ${input.runes.length} תווים', () {
        expect(removePunctuation(input), _oracleRemovePunctuation(input));
      });
    }

    test('5000 קלטים אקראיים', () {
      final random = Random(20261004);
      for (var i = 0; i < 5000; i++) {
        final input = _randomInput(random);
        expect(
          removePunctuation(input),
          _oracleRemovePunctuation(input),
          reason: 'קלט: ${input.codeUnits}',
        );
      }
    });
  });

  test('מהיר לפחות פי 1.5 מהמימוש הקודם על שורות בלי גרשיים', () {
    final lines = [for (var i = 0; i < 2000; i++) _plainLine(Random(i))];
    int timeMicros(String Function(String) clean) {
      for (final line in lines.take(200)) {
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
      oracle = min(oracle, timeMicros(_oracleRemovePunctuation));
      current = min(current, timeMicros(removePunctuation));
    }
    expect(
      current * 3,
      lessThan(oracle * 2),
      reason: 'oracle ${oracle}us, current ${current}us',
    );
  });
}

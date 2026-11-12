import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

final RegExp _oracleHtmlEntity = RegExp(
  r'&(#x?[0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);',
);

/// המימוש הקודם של isHeadingLine, בשני RegExp-ים לכל שורה.
bool _oracleIsHeadingLine(String line) {
  final trimmedLine = line.trim();
  if (trimmedLine.isEmpty) return false;
  return RegExp(
        r'^<h[1-6][^>]*>.*?</h[1-6]>$',
        caseSensitive: false,
      ).hasMatch(trimmedLine) ||
      RegExp(r'^#{1,6}\s').hasMatch(trimmedLine);
}

final RegExp _oracleWordEnd = RegExp(
  "[א-ײ0-9a-zA-Z'׳)\\]\u0591-\u05BD\u05BF\u05C1\u05C2\u05C4\u05C5\u05C7]",
);
final RegExp _oracleWordStart = RegExp(r'[א-ײ0-9a-zA-Z(\[]');

/// התו הגלוי שאחרי רצף פיסוק ותגים, אחרי פענוח ישות.
final RegExp _oracleAfterPunctuation = RegExp(
  r'(?:[!:;.,?\-—–]|<[^>]*>)*(&(?:#x?[0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);|.)?',
  dotAll: true,
);

String _oracleNextVisible(String line, int from) {
  final next = _oracleAfterPunctuation.matchAsPrefix(line, from)?.group(1);
  if (next == null) return '';
  final decoded = next.length > 1 ? decodeHtmlEntities(next) : next;
  return decoded.isEmpty ? '' : decoded[0];
}

/// עותק של המימוש הקודם, שעבר תו-תו כמחרוזות, ועליו פיסוק שבין מילים הופך
/// לרווח. הקלטים בלי גרשיים: הם מוכרעים לפני הלולאה ב-stripNonAcronymQuotes
/// ונבדקים ב-remove_punctuation_quotes_test.
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

    if (_oracleIsHeadingLine(line.trim())) {
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
    var previous = '';
    var previousWasLiteralSpace = false;
    var skipAt = -1;
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
      if (i == skipAt && previousWasLiteralSpace) continue;
      if (ch == '&') {
        final entity = _oracleHtmlEntity.matchAsPrefix(processed, i);
        if (entity != null) {
          final decoded = decodeHtmlEntities(entity.group(0)!);
          if (decoded.isNotEmpty) previous = decoded[decoded.length - 1];
          previousWasLiteralSpace = false;
          buffer.write(entity.group(0));
          i = entity.end - 1;
          continue;
        }
      }
      if (ch == '(') {
        parenDepth++;
        buffer.write(ch);
        previous = ch;
        previousWasLiteralSpace = false;
        continue;
      }
      if (ch == ')') {
        if (parenDepth > 0) parenDepth--;
        buffer.write(ch);
        previous = ch;
        previousWasLiteralSpace = false;
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
        previous = ch;
        previousWasLiteralSpace = false;
        continue;
      }
      if (isPunctuation) {
        if (lastAllowedPunctuationIndex != null &&
            i >= lastAllowedPunctuationIndex &&
            (ch == '.' || ch == ':')) {
          buffer.write(ch);
          previous = ch;
          previousWasLiteralSpace = false;
        } else if (_oracleWordEnd.hasMatch(previous) &&
            _oracleWordStart.hasMatch(_oracleNextVisible(processed, i + 1))) {
          buffer.write(' ');
          previous = ' ';
          previousWasLiteralSpace = true;
        } else if (previousWasLiteralSpace) {
          final next = _oracleAfterPunctuation.matchAsPrefix(processed, i + 1);
          final visible = next?.group(1);
          if (visible == ' ') {
            skipAt = next!.end - 1;
          }
        }
        continue;
      }
      buffer.write(ch);
      previous = ch;
      previousWasLiteralSpace = ch == ' ';
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
        _oracleIsHeadingLine(line) ||
        (i < processedLines.length - 1 &&
            _oracleIsHeadingLine(processedLines[i + 1]));

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
  '\u0000', '\u000B', '\u00A0', '\u2028', '\u3000', '\uFEFF', '\u0085', //
  '\u200B', '\u2029',
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
  group('removePunctuation זהה למימוש המחרוזות', () {
    const edgeCases = [
      '',
      ' ',
      '\n',
      'אב.',
      '(א —: ב)',
      '(א —. ב)',
      'א —\u2029ב',
      'א\u00a0— ב',
      'א&nbsp;— ב',
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
      'א, ב.\u00A0\u3000\uFEFF\nג; ד:\u2028',
      'א, ב.\u0085\nג; ד:\u200B',
      'א.<b>ב:</b> \t',
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

  test('isHeadingLine זהה לשני ה-RegExp-ים הקודמים', () {
    const edgeCases = [
      '<h2>כותרת</h2>',
      '  <H3 class="x">כותרת</H3>\t',
      '<h2>פתוחה',
      '<b>לא כותרת</b>',
      '<hr>',
      '# כותרת',
      '###### ',
      '####### שבע',
      '#כותרת',
      '\uFEFF<h1>א</h1>',
      '\u00A0# א',
      'א <h1>ב</h1>',
    ];
    final random = Random(20261029);
    final inputs = [
      ...edgeCases,
      for (var i = 0; i < 5000; i++) _randomInput(random),
    ];
    for (final input in inputs) {
      expect(
        isHeadingLine(input),
        _oracleIsHeadingLine(input),
        reason: 'קלט: ${input.codeUnits}',
      );
    }
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

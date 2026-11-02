// אורקל: projectLine עם joinAtPunctuation זהה למימוש הקודם (RegExp ו-trim לכל
// תו), ובלעדיו נבדל ממנו רק ברווחים שבמקום פיסוק בין מילים.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/utils/note_anchor_utils.dart';

// העתק מילולי של המימוש הקודם.
bool _oldIsDiacritic(int code) =>
    code >= 0x0591 && code <= 0x05C7 && code != 0x05BE;

// פיסוק שעשוי להיות מוסתר בתצוגה (כמו _isIgnored ב-html_slice): הבחירה מגיעה
// בלעדיו, ולכן מתעלמים ממנו בשני צידי ההשוואה.
final _oldPunctuation = RegExp('[!"\',\\-.:;?\u05F3\u05F4\u2013\u2014]');
bool _oldIsPunct(String ch) => _oldPunctuation.hasMatch(ch);

// בודק אם המקטע rawLine[start..end] (מ-'<' עד '>') הוא תגית <br>.
bool _oldIsBreakTag(String s, int start, int end) {
  int i = start + 1;
  if (i < end && s[i] == '/') i++;
  if (i + 1 >= end) return false;
  final c0 = s.codeUnitAt(i);
  final c1 = s.codeUnitAt(i + 1);
  final isBr = (c0 == 0x62 || c0 == 0x42) && (c1 == 0x72 || c1 == 0x52);
  if (!isBr) return false;
  final next = (i + 2) < end ? s[i + 2] : '>';
  return next == '>' || next == '/' || next.trim().isEmpty;
}

/// מקרין שורה גולמית (HTML+ניקוד) למחרוזת מנורמלת עם מפת אינדקסים חזרה.
LineProjection _oldProjectLine(
  String rawLine, {
  bool keepPunctuation = false,
  bool omitInjectedAnchorMarkers = false,
}) {
  final buffer = StringBuffer();
  final rawIndex = <int>[];
  bool inTag = false;
  int tagStart = 0;
  bool pendingWhitespace = false;
  int pendingWhitespaceRawStart = 0;

  void markWhitespace(int rawStart) {
    if (!pendingWhitespace) {
      pendingWhitespace = true;
      pendingWhitespaceRawStart = rawStart;
    }
  }

  void flushWhitespace() {
    if (pendingWhitespace) {
      rawIndex.add(pendingWhitespaceRawStart);
      buffer.write(' ');
      pendingWhitespace = false;
    }
  }

  for (int i = 0; i < rawLine.length; i++) {
    final ch = rawLine[i];
    final code = rawLine.codeUnitAt(i);

    if (omitInjectedAnchorMarkers && !inTag && ch == '<') {
      final isAnchor = rawLine.startsWith('<a class="link-anchor ', i);
      final isSpan = rawLine.startsWith('<span class="link-anchor ', i);
      if (isAnchor || isSpan) {
        final closingTag = isAnchor ? '</a>' : '</span>';
        final end = rawLine.indexOf(closingTag, i);
        if (end >= 0) {
          i = end + closingTag.length - 1;
          continue;
        }
      }
    }

    if (inTag) {
      if (ch == '>') {
        inTag = false;
        // <br> הוא שבירת שורה — הרינדור מציג אותו כרווח, לכן גם כאן, אחרת
        // בחירה שחוצה <br> לא תאותר בעיגון ותיפול לסימון כל השורה.
        if (_oldIsBreakTag(rawLine, tagStart, i)) markWhitespace(tagStart);
      }
      continue;
    }
    if (ch == '<') {
      inTag = true;
      tagStart = i;
      continue;
    }

    // ניקוד, טעמים ופיסוק — מושמטים לחלוטין.
    if (_oldIsDiacritic(code) || (!keepPunctuation && _oldIsPunct(ch))) {
      continue;
    }

    // מקף עברי (מקף) ורווחים — מכווצים לרווח יחיד.
    final isWhitespace = code == 0x05BE || ch.trim().isEmpty;
    if (isWhitespace) {
      markWhitespace(i);
      continue;
    }

    flushWhitespace();
    rawIndex.add(i);
    buffer.write(ch);
  }

  // רווח בסוף נשמר במפה (כדי שאורך המפה יהיה עקבי) אך לא נכלל בטקסט —
  // למעשה אנו פשוט מתעלמים ממנו ומסיימים את המפה בסוף השורה.
  rawIndex.add(rawLine.length);
  return LineProjection(buffer.toString(), rawIndex);
}

void _expectSame(String line) {
  for (final keep in [false, true]) {
    for (final omit in [false, true]) {
      final want = _oldProjectLine(
        line,
        keepPunctuation: keep,
        omitInjectedAnchorMarkers: omit,
      );
      final got = projectLine(
        line,
        keepPunctuation: keep,
        omitInjectedAnchorMarkers: omit,
        joinAtPunctuation: true,
      );
      expect(got.normalized, want.normalized, reason: line);
      expect(got.rawIndex, want.rawIndex, reason: line);

      final separated = projectLine(
        line,
        keepPunctuation: keep,
        omitInjectedAnchorMarkers: omit,
      );
      expect(_withoutSpaces(separated), _withoutSpaces(want), reason: line);
    }
  }
}

/// התווים שאינם רווח, כל אחד עם מקומו בשורה הגולמית.
List<(String, int)> _withoutSpaces(LineProjection p) => [
  for (var i = 0; i < p.normalized.length; i++)
    if (p.normalized[i] != ' ') (p.normalized[i], p.rawIndex[i]),
];

void main() {
  group('projectLine (perf)', () {
    test('זהה למימוש הקודם לכל יחידת קוד', () {
      for (var code = 0; code <= 0xFFFF; code++) {
        _expectSame('א${String.fromCharCode(code)}ב');
      }
    });

    test('זהה למימוש הקודם על 20,000 שורות אקראיות', () {
      final pieces = [
        ...'אבשךְּ֑֣ ־׀,.:;?!-"\'׳״–—<>/\t\n\u00a0\u2009\u0085'.split(''),
        ...'<b>|</b>|<br>|<BR/>|<br >|<bra>|</br>|😀|<a class="link-anchor x">א</a>'
            .split('|'),
        ...'<span class="link-anchor y">ב</span>|<a class="link-anchor z">'
            .split(
              '|',
            ),
      ];
      final random = Random(7);
      for (var i = 0; i < 20000; i++) {
        final buffer = StringBuffer();
        final length = random.nextInt(24);
        for (var j = 0; j < length; j++) {
          buffer.write(pieces[random.nextInt(pieces.length)]);
        }
        _expectSame(buffer.toString());
      }
    });
  });
}

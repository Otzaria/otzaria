// אורקל: פיצול שורה למילים בסריקת הגימטריה זהה למימוש הקודם (ניקוי HTML
// מלא כולל כיווץ רווחים, ואז פיצול).

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/gematria/gematria_search.dart';

final _htmlTagRe = RegExp(r'<[^>]*>');
final _namedEntityRe = RegExp(r'&[a-zA-Z]+;');
final _decimalEntityRe = RegExp(r'&#\d+;');
final _hexEntityRe = RegExp(r'&#x[0-9a-fA-F]+;');
final _whitespaceRe = RegExp(r'\s+');
final _wordSeparatorRe = RegExp(r'[\s־׀|]+');

// העתק מילולי של המימוש הקודם.
String _oldCleanHtml(String s) {
  var cleaned = s.replaceAll(_htmlTagRe, '');
  cleaned = cleaned.replaceAll('&nbsp;', ' ');
  cleaned = cleaned.replaceAll('&thinsp;', ' ');
  cleaned = cleaned.replaceAll('&ensp;', ' ');
  cleaned = cleaned.replaceAll('&emsp;', ' ');
  cleaned = cleaned.replaceAll('&lt;', '<');
  cleaned = cleaned.replaceAll('&gt;', '>');
  cleaned = cleaned.replaceAll('&amp;', '&');
  cleaned = cleaned.replaceAll('&quot;', '"');
  cleaned = cleaned.replaceAll('&#39;', "'");
  cleaned = cleaned.replaceAll(_namedEntityRe, '');
  cleaned = cleaned.replaceAll(_decimalEntityRe, '');
  cleaned = cleaned.replaceAll(_hexEntityRe, '');
  return cleaned.replaceAll(_whitespaceRe, ' ').trim();
}

List<String> _oldLineWords(String line) => _oldCleanHtml(
  line,
).split(_wordSeparatorRe).where((w) => w.trim().isNotEmpty).toList();

void main() {
  group('GimatriaSearch.lineWords (perf)', () {
    test('זהה למימוש הקודם במקרי קצה', () {
      const cases = [
        '',
        ' ',
        '\t\u00a0\u2003\n',
        'בְּרֵאשִׁ֖ית בָּרָ֣א אֱלֹהִ֑ים',
        'עַל־פְּנֵ֣י תְה֑וֹם ׀ וְ|ר֣וּחַ',
        '  רווח   כפול  ',
        '<b>מודגש</b> רגיל',
        'פרק&nbsp;א&thinsp;ב&ensp;ג&emsp;ד',
        '&lt;b&gt;לא תגית&lt;/b&gt;',
        '&amp;nbsp; &quot;ציטוט&quot; &#39;גרש&#39;',
        '&#1488;&#x5D0;&foo; א',
        'א < ב > ג',
        'א & ב',
        '<span class="x">&nbsp;</span>',
        '&',
        '<',
        '<>',
        '&;',
        'abc\u00a0def',
        '\u0085\u05d0 \u05d1\u0085',
        '|א||ב|',
        'א\u0085ב ~ג',
        'א\u007fב \u058fג \u0600ד',
        'א\u200bב 😀ג',
        'מ׳ ב״ק׃ [א] (ב)',
      ];
      for (final line in cases) {
        expect(
          GimatriaSearch.lineWords(line),
          _oldLineWords(line),
          reason: line,
        );
      }
    });

    test('זהה למימוש הקודם על 20,000 שורות אקראיות', () {
      final pieces = [
        ...'אבשךְּ֑֣ ־׀|<>&;#xa1\t\n\u00a0\u2009\u0085~\u007f\u058f\u0600\u05f3'
            .split(''),
        ...'  |5D0|nbsp|lt|amp|<b>|</b>|<span class="c">|&nbsp;|&lt;|&gt;'
            .split('|'),
        ...'&amp;|&quot;|&#39;|&#1488;|&#x5D0;|&foo;'.split('|'),
      ];
      final random = Random(42);
      for (var i = 0; i < 20000; i++) {
        final buffer = StringBuffer();
        final length = random.nextInt(20);
        for (var j = 0; j < length; j++) {
          buffer.write(pieces[random.nextInt(pieces.length)]);
        }
        final line = buffer.toString();
        expect(
          GimatriaSearch.lineWords(line),
          _oldLineWords(line),
          reason: line,
        );
      }
    });
  });
}

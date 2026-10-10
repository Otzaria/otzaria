import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/file/toc_parser.dart';
import 'package:otzaria/utils/text/ref_helper.dart';

// אורקל: זיהוי הכותרות הקודם, שהוריד אותיות לכל שורה והריץ regex על כולן.
List<(String, int, int)> _oracleHeaders(String content) {
  final lines = content.split('\n');
  final headers = <(String, int, int)>[];
  for (int i = 0; i < lines.length; i++) {
    final line = lines[i].trimLeft();
    final md = RegExp(r'^(#{1,6})\s+(.+?)\s*$').firstMatch(line);
    if (md != null) {
      final text = md.group(2)!.trim();
      if (text.isNotEmpty) headers.add((text, i, md.group(1)!.length));
      continue;
    }
    final lower = line.toLowerCase();
    if (lower.startsWith('<h') && lower.length > 3) {
      final c = lower[2];
      final code = c.codeUnitAt(0);
      if (code >= '1'.codeUnitAt(0) && code <= '6'.codeUnitAt(0)) {
        if (isTocExcludedHeadingLine(lower)) continue;
        final text = line.replaceAll(RegExp(r'<[^>]*>'), '').trim();
        if (text.isNotEmpty) headers.add((text, i, int.tryParse(c) ?? 1));
        continue;
      }
    }
  }
  return headers;
}

List<(String, int, int)> _flatten(List<TocEntry> entries) => [
  for (final entry in entries) ...[
    (entry.text, entry.index, entry.level),
    ..._flatten(entry.children),
  ],
];

void main() {
  group('TocParser.parseEntriesFromContent', () {
    test('parses HTML headings with leading whitespace', () {
      final content = '''
        <h1>כותרת ראשית</h1>
        טקסט רגיל
          <h2>כותרת משנה</h2>
        עוד טקסט
      ''';

      final toc = TocParser.parseEntriesFromContent(content);

      expect(toc.length, 1);
      expect(toc.first.text, 'כותרת ראשית');
      expect(toc.first.level, 1);
      expect(toc.first.children.length, 1);
      expect(toc.first.children.first.text, 'כותרת משנה');
      expect(toc.first.children.first.level, 2);
    });

    test('כותרת עם $kTocExcludeAttr מדולגת (תוכן עניינים מוטמע קובע)', () {
      final content =
          '<h1>ראשית</h1>\n'
          '<h2 $kTocExcludeAttr>כותרת עיצובית</h2>\n'
          '<h2>כותרת אמיתית</h2>';

      final toc = TocParser.parseEntriesFromContent(content);

      expect(toc.length, 1);
      expect(toc.first.children.map((e) => e.text), ['כותרת אמיתית']);
    });

    test('parses Markdown headings (#..######)', () {
      final content = '''
# פרק א
טקסט
## סעיף א
עוד טקסט
### תת סעיף
      ''';

      final toc = TocParser.parseEntriesFromContent(content);

      expect(toc.length, 1);
      expect(toc.first.text, 'פרק א');
      expect(toc.first.level, 1);
      expect(toc.first.children.length, 1);
      expect(toc.first.children.first.text, 'סעיף א');
      expect(toc.first.children.first.level, 2);
      expect(toc.first.children.first.children.length, 1);
      expect(toc.first.children.first.children.first.text, 'תת סעיף');
      expect(toc.first.children.first.children.first.level, 3);
    });

    test('כותרת אחרי דילוג רמה נתלית בכותרת הקודמת הקרובה ברמה נמוכה יותר', () {
      // המבנה של "סוד קיומנו או המחנך": h3 לפני הפרק הראשון, ואז h2 ו-h4.
      const content =
          '<h1>ספר</h1>\n'
          '<h3>הקדמה</h3>\n'
          '<h2>פרק א</h2>\n'
          '<h4>ברכה</h4>\n'
          '<h2>פרק ב</h2>\n'
          '<h4>ניסן</h4>\n'
          'טקסט';

      final toc = TocParser.parseEntriesFromContent(content);
      final flat = flattenToc(toc);

      expect(flat.map((e) => e.index), [0, 1, 2, 3, 4, 5]);
      expect(flat[1].parent?.text, 'ספר');
      expect(flat[3].parent?.text, 'פרק א');
      expect(flat[5].parent?.text, 'פרק ב');
      expect(refFromTocList(6, toc), 'ספר, פרק ב, ניסן');
    });

    test('does not treat hash-without-space as heading', () {
      final content = '###בלי רווח\nטקסט';
      final toc = TocParser.parseEntriesFromContent(content);
      expect(toc, isEmpty);
    });

    test('זהה לזיהוי הקודם על שורות אקראיות (perf)', () {
      const pieces = [
        '#',
        '##',
        '#######',
        ' ',
        '\t',
        '\r',
        '<h',
        '<H',
        '1',
        '3',
        '6',
        '7',
        '0',
        '>',
        '</h1>',
        '<b>',
        'r>',
        ' data-toc="none"',
        ' DATA-TOC="NONE"',
        'İ',
        'א',
        'כותרת',
        'x',
      ];
      final random = Random(11);
      for (var round = 0; round < 300; round++) {
        final content = [
          for (var line = 0; line < 30; line++)
            [
              for (var i = random.nextInt(8); i > 0; i--)
                pieces[random.nextInt(pieces.length)],
            ].join(),
        ].join('\n');
        expect(
          _flatten(TocParser.parseEntriesFromContent(content)),
          _oracleHeaders(content),
          reason: content,
        );
      }
    });
  });
}

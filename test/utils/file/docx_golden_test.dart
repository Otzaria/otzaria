import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/docx_to_otzaria.dart';
import 'package:otzaria/utils/file/document_format.dart';

import 'docx_golden_fixtures.dart';

/// Golden regression של ממיר ה-Word (§23).
///
/// כל תרחיש מקובע כאן כ**פלט מלא ומדויק**, ולא כ-`contains` — זו הנקודה:
/// refactor שמכליל את המנוע ל-DOCM/DOTX/ODT חייב להשאיר את הפלט של DOCX
/// זהה בייט-בבייט. שינוי מכוון בפלט מחייב עדכון golden כאן **וגם** העלאת
/// `kDocxConverterVersion`, אחרת המטמון יגיש פלט ישן.
void main() {
  const title = 'ספר';
  const table =
      '<table style="border-collapse: collapse; border: 1px solid #999;">';
  const indent = '    ';
  String cell(String content) =>
      '<td style="border: 1px solid #999; padding: 4px 8px">$content</td>';
  String row(String cells) => '<tr>$cells</tr>';

  final goldens = <String, String>{
    'plain text': '<h1>ספר</h1>\nשורה ראשונה\nשורה שנייה',

    'headings': '<h1>ספר</h1>\n<h1>פרק א</h1>\n<h2>סימן ב</h2>\nגוף',

    'basedOn heading': '<h1>ספר</h1>\n<h2>כותרת יורשת</h2>',

    'basedOn cycle': '<h1>ספר</h1>\nמעגל',

    'outlineLvl=9': '<h1>ספר</h1>\nגוף ולא כותרת',

    'numbered list': '<h1>ספר</h1>\n1. ראשון\n2. שני\n3. שלישי',

    // ההזחה היא NBSP (U+00A0) ולא רווח רגיל — רווחים רגילים היו נבלעים ברינדור.
    'multilevel list':
        '<h1>ספר</h1>\n1. א\n${indent}1.1. ב\n${indent * 2}1.1.1. ג\n'
        '${indent}1.2. ד',

    'Hebrew numbering': '<h1>ספר</h1>\nא. אלף\nב. בית\nג. גימל',

    'footnote':
        '<h1>ספר</h1>\nטקסט עם הערה<sup class="footnote-marker">1</sup>'
        '<i class="footnote">גוף ההערה</i>',

    'table':
        '<h1>ספר</h1>\n$table'
        '${row(cell('א1') + cell('ב1'))}'
        '${row(cell('א2') + cell('ב2'))}</table>',

    'nested table':
        '<h1>ספר</h1>\n$table'
        '${row(cell('חיצוני<br>$table${row(cell('פנימי'))}</table>'))}'
        '</table>',

    'DrawingML image':
        '<h1>ספר</h1>\n<img src="$kTinyPngDataUri" style="max-width: 100%;"/>',

    'VML image':
        '<h1>ספר</h1>\n<img src="$kTinyPngDataUri" style="max-width: 100%;"/>',

    'text box':
        '<h1>ספר</h1>\n<div style="border: 1px solid #999; padding: 8px; '
        'margin: 4px 0;">בתוך התיבה</div>',

    'text box + background image':
        '<h1>ספר</h1>\n<div style="background-image: url($kTinyPngDataUri); '
        'background-size: contain; background-repeat: no-repeat; '
        'background-position: center; border: 1px solid #999; padding: 8px; '
        'margin: 4px 0;">על הרקע</div>',

    'behindDoc': '<h1>ספר</h1>\nטקסט אחרי הסימן',

    'w:sdt':
        '<h1>ספר</h1>\nבתוך בקרת תוכן\n$table'
        '${row(cell('תא בבקרה'))}</table>',

    'hyperlink external':
        '<h1>ספר</h1>\n<a href="https://otzaria.org">לאתר</a>',

    'hyperlink internal':
        '<h1>ספר</h1>\n<h1 id="_Toc1">כותרת יעד</h1>\n'
        '<a href="#_Toc1">לכותרת</a>',
  };

  final scenarios = buildGoldenScenarios();

  group('golden regression — docxToText (§23)', () {
    test('כל תרחיש מכוסה בדיוק ב-golden אחד', () {
      expect(
        scenarios.keys.toSet(),
        goldens.keys.toSet(),
        reason: 'fixture ללא golden (או להפך) — §23 דורש כיסוי מלא',
      );
    });

    for (final name in goldens.keys) {
      test(name, () {
        expect(docxToText(scenarios[name]!, title), goldens[name]);
      });
    }
  });

  group('אינווריאנטים של הפלט', () {
    test('כל פלט פותח בכותרת הספר כ-h1 בשורה 0', () {
      for (final entry in scenarios.entries) {
        final first = docxToText(entry.value, title).split('\n').first;
        expect(first, '<h1>ספר</h1>', reason: entry.key);
      }
    });

    test('הכותרת עוברת escape ואינה שוברת את ה-HTML', () {
      final out = docxToText(scenarios['plain text']!, 'א<b>&');
      expect(out.split('\n').first, '<h1>א&lt;b&gt;&amp;</h1>');
    });

    test('תמונות מוטמעות כ-data URI — ללא תלות ברשת', () {
      for (final name in [
        'DrawingML image',
        'VML image',
        'text box + background image',
      ]) {
        final out = docxToText(scenarios[name]!, title);
        expect(out, contains('data:image/png;base64,'), reason: name);
        expect(out, isNot(contains('http')), reason: name);
      }
    });

    test('behindDoc אינו משאיר בלוק ריק ואינו בולע את הטקסט שאחריו', () {
      final out = docxToText(scenarios['behindDoc']!, title);
      expect(out, isNot(contains('<img')));
      expect(out, isNot(contains('<div')));
      expect(out, contains('טקסט אחרי הסימן'));
    });

    test('קישור עם סכימה חסומה (safeLinkTarget) נשאר טקסט לא-עטוף', () {
      final bytes = buildDocx(
        document: documentXml(hyperlinkExternal('rId9', 'חסום')),
        rels: hyperlinkRelsXml({'rId9': 'javascript:alert(1)'}),
      );
      final out = docxToText(bytes, title);
      expect(out, '<h1>ספר</h1>\nחסום');
      expect(out, isNot(contains('<a ')));
    });

    test('קישור עם r:id שאינו נמצא ב-rels נשאר טקסט לא-עטוף', () {
      final bytes = buildDocx(
        document: documentXml(hyperlinkExternal('rIdMissing', 'קישור')),
      );
      final out = docxToText(bytes, title);
      expect(out, '<h1>ספר</h1>\nקישור');
      expect(out, isNot(contains('<a ')));
    });

    test('המרה חוזרת דטרמיניסטית', () {
      for (final entry in scenarios.entries) {
        expect(
          docxToText(entry.value, title),
          docxToText(entry.value, title),
          reason: entry.key,
        );
      }
    });
  });

  group('המרה חסרת-תמונות (§64)', () {
    String imageFree(Uint8List bytes) => ooxmlWordToText(
      bytes,
      title,
      format: DocumentFormat.docx,
      embedImages: false,
    );

    test('מספר השורות זהה לחלוטין לווריאנט המלא', () {
      // האינווריאנט הקריטי: אינדקסי ה-TOC נבנים מהווריאנט חסר-התמונות
      // ונקראים מול הווריאנט המלא. פער של שורה אחת מזיז את כל תוכן העניינים.
      for (final entry in scenarios.entries) {
        expect(
          imageFree(entry.value).split('\n').length,
          docxToText(entry.value, title).split('\n').length,
          reason: entry.key,
        );
      }
    });

    test('אין base64 בפלט', () {
      for (final entry in scenarios.entries) {
        expect(
          imageFree(entry.value),
          isNot(contains('base64')),
          reason: entry.key,
        );
      }
    });

    test('תגי התמונה נשארים במקומם (רק ה-URI מתרוקן)', () {
      expect(
        imageFree(scenarios['DrawingML image']!),
        '<h1>ספר</h1>\n<img src="" style="max-width: 100%;"/>',
      );
      expect(
        imageFree(scenarios['VML image']!),
        '<h1>ספר</h1>\n<img src="" style="max-width: 100%;"/>',
      );
    });

    test('תיבת-טקסט עם רקע שומרת את הטקסט', () {
      final out = imageFree(scenarios['text box + background image']!);
      expect(out, contains('על הרקע'));
      expect(out, contains('background-image: url()'));
    });

    test('פלט טקסטואלי זהה כשאין תמונות כלל', () {
      for (final name in [
        'plain text',
        'headings',
        'numbered list',
        'footnote',
        'table',
        'nested table',
        'w:sdt',
      ]) {
        expect(
          imageFree(scenarios[name]!),
          docxToText(scenarios[name]!, title),
          reason: name,
        );
      }
    });
  });

  // §82: ארבעת פורמטי OOXML חולקים מנוע אחד — אותם בייטים חייבים לייצר
  // פלט זהה, ללא תלות בסיומת שהצהיר עליה הקורא.
  group('שקילות בין פורמטי OOXML (§82)', () {
    final ooxmlFormats = [
      DocumentFormat.docx,
      DocumentFormat.docm,
      DocumentFormat.dotx,
      DocumentFormat.dotm,
    ];

    for (final name in goldens.keys) {
      test('$name — זהה בכל ארבעת הפורמטים', () {
        for (final format in ooxmlFormats) {
          expect(
            ooxmlWordToText(scenarios[name]!, title, format: format),
            goldens[name],
            reason: '${format.extension}: $name',
          );
        }
      });
    }
  });
}

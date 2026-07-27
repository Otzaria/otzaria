import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/docx_to_otzaria.dart';

// ─── helpers ──────────────────────────────────────────────────────────────────

// Builds a minimal valid DOCX (ZIP) whose word/document.xml is the given bytes.
Uint8List _buildDocx(
  List<int> documentXmlBytes, {
  List<int>? footnotesXmlBytes,
  List<int>? stylesXmlBytes,
}) {
  final encoder = ZipEncoder();
  final archive = Archive();
  archive.addFile(
    ArchiveFile(
      'word/document.xml',
      documentXmlBytes.length,
      documentXmlBytes,
    ),
  );
  if (footnotesXmlBytes != null) {
    archive.addFile(
      ArchiveFile(
        'word/footnotes.xml',
        footnotesXmlBytes.length,
        footnotesXmlBytes,
      ),
    );
  }
  if (stylesXmlBytes != null) {
    archive.addFile(
      ArchiveFile('word/styles.xml', stylesXmlBytes.length, stylesXmlBytes),
    );
  }
  return Uint8List.fromList(encoder.encode(archive));
}

// Builds document.xml bytes from a plain UTF-8 XML string.
List<int> _utf8Xml(String text) => utf8.encode(text);

// Builds document.xml bytes that declare UTF-8 in the header but embed
// Hebrew text in Windows-1255 encoding — the exact situation that triggered
// the original bug with בדיקה.docx.
List<int> _cp1255Xml(
  String asciiPrefix,
  List<int> hebrewCp1255Bytes,
  String asciiSuffix,
) {
  return [
    ...utf8.encode(asciiPrefix),
    ...hebrewCp1255Bytes,
    ...utf8.encode(asciiSuffix),
  ];
}

const _xmlNs =
    'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"';

String _simpleDocXml(String innerText) =>
    '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document $_xmlNs>
  <w:body>
    <w:p>
      <w:r>
        <w:t>$innerText</w:t>
      </w:r>
    </w:p>
  </w:body>
</w:document>''';

// Windows-1255 bytes for "בדיקה"
// ב=0xE1, ד=0xE3, י=0xE9, ק=0xF7, ה=0xE4
const _cp1255Bedika = [0xE1, 0xE3, 0xE9, 0xF7, 0xE4];

// ─── tests ────────────────────────────────────────────────────────────────────

void main() {
  group('docxToText - קידוד', () {
    test('ממיר DOCX עם עברית UTF-8 תקינה', () {
      final docx = _buildDocx(_utf8Xml(_simpleDocXml('בדיקה')));
      final result = docxToText(docx, 'ספר בדיקה');

      expect(result, contains('<h1>ספר בדיקה</h1>'));
      expect(result, contains('בדיקה'));
    });

    test(
      'ממיר DOCX עם עברית Windows-1255 (fallback) ומחזיר טקסט עברי תקין',
      () {
        // XML header declares UTF-8 but text bytes are Windows-1255 — the exact
        // bug seen in the real בדיקה.docx file.
        final xmlBytes = _cp1255Xml(
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<w:document $_xmlNs><w:body><w:p><w:r><w:t>',
          _cp1255Bedika,
          '</w:t></w:r></w:p></w:body></w:document>',
        );
        final docx = _buildDocx(xmlBytes);
        final result = docxToText(docx, 'ספר בדיקה');

        expect(result, contains('<h1>ספר בדיקה</h1>'));
        expect(result, contains('בדיקה'));
      },
    );

    test('כותרת הספר מופיעה כ-h1 בתחילת הפלט', () {
      final docx = _buildDocx(_utf8Xml(_simpleDocXml('שלום')));
      final result = docxToText(docx, 'כותרת בדיקה');

      expect(result.trimLeft(), startsWith('<h1>כותרת בדיקה</h1>'));
    });

    test('פסקה ריקה לא נוספת לפלט', () {
      final xml =
          '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document $_xmlNs>
  <w:body>
    <w:p><w:r><w:t>שורה ראשונה</w:t></w:r></w:p>
    <w:p></w:p>
    <w:p><w:r><w:t>שורה שנייה</w:t></w:r></w:p>
  </w:body>
</w:document>''';
      final docx = _buildDocx(_utf8Xml(xml));
      final lines = docxToText(docx, 'בדיקה').split('\n');
      final nonEmpty = lines.where((l) => l.trim().isNotEmpty).toList();

      // h1 title + 2 content lines — the blank paragraph is skipped
      expect(nonEmpty, hasLength(3));
    });
  });

  group('docxToText - עיצוב', () {
    test('מודגש מומר ל-<b>', () {
      final xml =
          '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document $_xmlNs>
  <w:body>
    <w:p>
      <w:r>
        <w:rPr><w:b/></w:rPr>
        <w:t>מודגש</w:t>
      </w:r>
    </w:p>
  </w:body>
</w:document>''';
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'בדיקה');
      expect(result, contains('<b>מודגש</b>'));
    });

    test('נטוי מומר ל-<i>', () {
      final xml =
          '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document $_xmlNs>
  <w:body>
    <w:p>
      <w:r>
        <w:rPr><w:i/></w:rPr>
        <w:t>נטוי</w:t>
      </w:r>
    </w:p>
  </w:body>
</w:document>''';
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'בדיקה');
      expect(result, contains('<i>נטוי</i>'));
    });
  });

  group('docxToText - הערות שוליים', () {
    test('הערת שוליים ב-Windows-1255 מפוענחת נכון', () {
      // footnotes.xml declares UTF-8 but text is Windows-1255
      // ה=0xE4, ע=0xF2, ר=0xF8, ה=0xE4
      final cp1255FootnoteText = [0xE4, 0xF2, 0xF8, 0xE4]; // "הערה"
      final footnotesBytes = _cp1255Xml(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<w:footnotes $_xmlNs>'
            '<w:footnote w:id="1"><w:p><w:r><w:t>',
        cp1255FootnoteText,
        '</w:t></w:r></w:p></w:footnote>'
            '</w:footnotes>',
      );
      final documentXml =
          '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document $_xmlNs>
  <w:body>
    <w:p>
      <w:r><w:t>פסקה</w:t></w:r>
      <w:r><w:footnoteReference w:id="1"/></w:r>
    </w:p>
  </w:body>
</w:document>''';

      final docx = _buildDocx(
        _utf8Xml(documentXml),
        footnotesXmlBytes: footnotesBytes,
      );
      final result = docxToText(docx, 'בדיקה');

      expect(result, contains('הערה'));
    });

    test('הערת שוליים מופיעה אחרי הפסקה שמכילה אותה', () {
      final documentXml =
          '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document $_xmlNs>
  <w:body>
    <w:p>
      <w:r><w:t>טקסט</w:t></w:r>
      <w:r>
        <w:footnoteReference w:id="1"/>
      </w:r>
    </w:p>
  </w:body>
</w:document>''';

      final footnotesXml =
          '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:footnotes $_xmlNs>
  <w:footnote w:id="1">
    <w:p><w:r><w:t>הערת שוליים</w:t></w:r></w:p>
  </w:footnote>
</w:footnotes>''';

      final docx = _buildDocx(
        _utf8Xml(documentXml),
        footnotesXmlBytes: _utf8Xml(footnotesXml),
      );
      final result = docxToText(docx, 'בדיקה');

      // פורמט הערות אוצריא: <sup class="footnote-marker"> + <i class="footnote">
      expect(result, contains('<sup class="footnote-marker">1</sup>'));
      expect(result, contains('<i class="footnote">הערת שוליים</i>'));
      // ה-<sup> וגוף ההערה צמודים, באותה שורה, אחרי הטקסט המפנה
      final paraIdx = result.indexOf('טקסט');
      final noteIdx = result.indexOf('הערת שוליים');
      expect(noteIdx, greaterThan(paraIdx));
    });
  });

  group('docxToText - כותרות לפי שם הסגנון', () {
    String docWithStyle(String styleVal, String text) =>
        '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document $_xmlNs>
  <w:body>
    <w:p>
      <w:pPr><w:pStyle w:val="$styleVal"/></w:pPr>
      <w:r><w:t>$text</w:t></w:r>
    </w:p>
  </w:body>
</w:document>''';

    test('Heading1 (שם) מומר ל-<h1>', () {
      final result = docxToText(
        _buildDocx(_utf8Xml(docWithStyle('Heading1', 'פרק'))),
        'ב',
      );
      expect(result, contains('<h1>פרק</h1>'));
    });

    test('"Heading 3" עם רווח מומר ל-<h3>', () {
      final result = docxToText(
        _buildDocx(_utf8Xml(docWithStyle('Heading 3', 'סעיף'))),
        'ב',
      );
      expect(result, contains('<h3>סעיף</h3>'));
    });

    test('Title מומר ל-<h1>', () {
      final result = docxToText(
        _buildDocx(_utf8Xml(docWithStyle('Title', 'שער'))),
        'ב',
      );
      expect(result, contains('<h1>שער</h1>'));
    });

    test('סגנון לא-כותרת נשאר פסקה רגילה (בלי <h>)', () {
      final result = docxToText(
        _buildDocx(_utf8Xml(docWithStyle('Normal', 'רגיל'))),
        'ב',
      );
      expect(result, contains('רגיל'));
      expect(result, isNot(contains('<h2>רגיל')));
    });

    test('כותרת מזוהה דרך outlineLvl כשאין שם סגנון תואם', () {
      final xml =
          '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document $_xmlNs>
  <w:body>
    <w:p>
      <w:pPr><w:outlineLvl w:val="0"/></w:pPr>
      <w:r><w:t>כותרת מתאר</w:t></w:r>
    </w:p>
  </w:body>
</w:document>''';
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'ב');
      expect(result, contains('<h1>כותרת מתאר</h1>'));
    });

    test('outlineLvl=9 ("Body Text") אינו כותרת', () {
      final xml =
          '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document $_xmlNs>
  <w:body>
    <w:p>
      <w:pPr><w:outlineLvl w:val="9"/></w:pPr>
      <w:r><w:t>גוף הטקסט</w:t></w:r>
    </w:p>
  </w:body>
</w:document>''';
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'ב');
      expect(result, contains('גוף הטקסט'));
      expect(result, isNot(contains('<h6>גוף הטקסט')));
    });

    test('outlineLvl=8 (הרמה החוקית העמוקה ביותר) נחתך ל-<h6>', () {
      final xml =
          '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document $_xmlNs>
  <w:body>
    <w:p>
      <w:pPr><w:outlineLvl w:val="8"/></w:pPr>
      <w:r><w:t>רמה תשיעית</w:t></w:r>
    </w:p>
  </w:body>
</w:document>''';
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'ב');
      expect(result, contains('<h6>רמה תשיעית</h6>'));
    });

    test('outlineLvl=9 על הפסקה גובר על pStyle="Heading1"', () {
      final xml =
          '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document $_xmlNs>
  <w:body>
    <w:p>
      <w:pPr>
        <w:pStyle w:val="Heading1"/>
        <w:outlineLvl w:val="9"/>
      </w:pPr>
      <w:r><w:t>גוף</w:t></w:r>
    </w:p>
  </w:body>
</w:document>''';
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'ב');
      expect(result, contains('גוף'));
      expect(result, isNot(contains('<h1>גוף')));
    });

    test('outlineLvl על הפסקה גובר על רמת שם הסגנון', () {
      final xml =
          '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document $_xmlNs>
  <w:body>
    <w:p>
      <w:pPr>
        <w:pStyle w:val="Heading1"/>
        <w:outlineLvl w:val="2"/>
      </w:pPr>
      <w:r><w:t>סעיף</w:t></w:r>
    </w:p>
  </w:body>
</w:document>''';
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'ב');
      expect(result, contains('<h3>סעיף</h3>'));
      expect(result, isNot(contains('<h1>סעיף')));
    });

    test('outlineLvl מחוץ לטווח על הפסקה אינו חוסם את pStyle', () {
      final xml =
          '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document $_xmlNs>
  <w:body>
    <w:p>
      <w:pPr>
        <w:pStyle w:val="Heading1"/>
        <w:outlineLvl w:val="-1"/>
      </w:pPr>
      <w:r><w:t>פרק</w:t></w:r>
    </w:p>
  </w:body>
</w:document>''';
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'ב');
      expect(result, contains('<h1>פרק</h1>'));
    });
  });

  group('docxToText - כותרות לפי styles.xml (styleId מספרי)', () {
    // Word בעברית / המרה מ-HTML: styleId מספרי, השם והמתאר רק בהגדרת הסגנון.
    String docWithStyles(List<(String, String)> paragraphs) {
      final body = paragraphs
          .map(
            (p) =>
                '<w:p><w:pPr><w:pStyle w:val="${p.$1}"/></w:pPr>'
                '<w:r><w:t>${p.$2}</w:t></w:r></w:p>',
          )
          .join();
      return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document $_xmlNs><w:body>$body</w:body></w:document>';
    }

    String stylesXml(String inner) =>
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:styles $_xmlNs>$inner</w:styles>';

    String headingStyle(String id, String name, int outlineLvl) =>
        '<w:style w:type="paragraph" w:styleId="$id">'
        '<w:name w:val="$name"/>'
        '<w:pPr><w:outlineLvl w:val="$outlineLvl"/></w:pPr>'
        '</w:style>';

    test('styleId מספרי עם w:name "heading N" מומר ל-<hN>', () {
      final result = docxToText(
        _buildDocx(
          _utf8Xml(
            docWithStyles([('1', 'פרק'), ('2', 'סימן'), ('3', 'סעיף')]),
          ),
          stylesXmlBytes: _utf8Xml(
            stylesXml(
              headingStyle('1', 'heading 1', 0) +
                  headingStyle('2', 'heading 2', 1) +
                  headingStyle('3', 'heading 3', 2),
            ),
          ),
        ),
        'ב',
      );
      expect(result, contains('<h1>פרק</h1>'));
      expect(result, contains('<h2>סימן</h2>'));
      expect(result, contains('<h3>סעיף</h3>'));
    });

    test('styleId מספרי מזוהה דרך outlineLvl גם כשהשם אינו "heading"', () {
      final result = docxToText(
        _buildDocx(
          _utf8Xml(docWithStyles([('a5', 'כותרת מותאמת')])),
          stylesXmlBytes: _utf8Xml(
            stylesXml(
              '<w:style w:type="paragraph" w:styleId="a5">'
              '<w:name w:val="כותרת שלי"/>'
              '<w:pPr><w:outlineLvl w:val="1"/></w:pPr>'
              '</w:style>',
            ),
          ),
        ),
        'ב',
      );
      expect(result, contains('<h2>כותרת מותאמת</h2>'));
    });

    test('שם סגנון בעברית ("כותרת 2") ב-styles.xml מומר ל-<h2>', () {
      final result = docxToText(
        _buildDocx(
          _utf8Xml(docWithStyles([('7', 'שער')])),
          stylesXmlBytes: _utf8Xml(
            stylesXml(
              '<w:style w:type="paragraph" w:styleId="7">'
              '<w:name w:val="כותרת 2"/></w:style>',
            ),
          ),
        ),
        'ב',
      );
      expect(result, contains('<h2>שער</h2>'));
    });

    test('סגנון תו (character) עם שם heading אינו הופך פסקה לכותרת', () {
      final result = docxToText(
        _buildDocx(
          _utf8Xml(docWithStyles([('10', 'טקסט רגיל')])),
          stylesXmlBytes: _utf8Xml(
            stylesXml(
              '<w:style w:type="character" w:styleId="10">'
              '<w:name w:val="heading 1 Char"/></w:style>',
            ),
          ),
        ),
        'ב',
      );
      expect(result, contains('טקסט רגיל'));
      expect(result, isNot(contains('<h1>טקסט רגיל')));
    });

    test('סגנון ללא outlineLvl ובלי שם כותרת נשאר פסקה רגילה', () {
      final result = docxToText(
        _buildDocx(
          _utf8Xml(docWithStyles([('NormalWeb', 'גוף'), ('TOC2', 'תוכן')])),
          stylesXmlBytes: _utf8Xml(
            stylesXml(
              '<w:style w:type="paragraph" w:styleId="NormalWeb">'
              '<w:name w:val="Normal (Web)"/></w:style>'
              '<w:style w:type="paragraph" w:styleId="TOC2">'
              '<w:name w:val="toc 2"/></w:style>',
            ),
          ),
        ),
        'ב',
      );
      expect(result, contains('גוף'));
      expect(result, contains('תוכן'));
      expect(result, isNot(contains('<h1>גוף')));
      expect(result, isNot(contains('<h2>תוכן')));
    });

    test('outlineLvl גבוה (>5) נחתך ל-<h6>', () {
      final result = docxToText(
        _buildDocx(
          _utf8Xml(docWithStyles([('9', 'עמוק')])),
          stylesXmlBytes: _utf8Xml(stylesXml(headingStyle('9', 'x', 8))),
        ),
        'ב',
      );
      expect(result, contains('<h6>עמוק</h6>'));
    });

    test('styleId שמי (Heading1) עדיין עובד גם כשקיים styles.xml', () {
      final result = docxToText(
        _buildDocx(
          _utf8Xml(docWithStyles([('Heading1', 'פרק')])),
          stylesXmlBytes: _utf8Xml(
            stylesXml(headingStyle('Heading1', 'heading 1', 0)),
          ),
        ),
        'ב',
      );
      expect(result, contains('<h1>פרק</h1>'));
    });

    test('סגנון עם outlineLvl=9 ("Body Text") אינו הופך לכותרת', () {
      final result = docxToText(
        _buildDocx(
          _utf8Xml(docWithStyles([('BodyText', 'פסקת גוף')])),
          stylesXmlBytes: _utf8Xml(
            stylesXml(headingStyle('BodyText', 'Body Text', 9)),
          ),
        ),
        'ב',
      );
      expect(result, contains('פסקת גוף'));
      expect(result, isNot(contains('<h6>פסקת גוף')));
    });

    test('סגנון יורש (basedOn) מקבל את רמת האב', () {
      final result = docxToText(
        _buildDocx(
          _utf8Xml(docWithStyles([('CustomChapter', 'פרק')])),
          stylesXmlBytes: _utf8Xml(
            stylesXml(
              '${headingStyle('Heading1', 'heading 1', 0)}'
              '<w:style w:type="paragraph" w:styleId="CustomChapter">'
              '<w:name w:val="Custom Chapter"/>'
              '<w:basedOn w:val="Heading1"/></w:style>',
            ),
          ),
        ),
        'ב',
      );
      expect(result, contains('<h1>פרק</h1>'));
    });

    test('שרשרת basedOn רב-שלבית נפתרת עד הסוף', () {
      final result = docxToText(
        _buildDocx(
          _utf8Xml(docWithStyles([('C', 'סימן')])),
          stylesXmlBytes: _utf8Xml(
            stylesXml(
              '${headingStyle('2', 'heading 2', 1)}'
              '<w:style w:type="paragraph" w:styleId="B">'
              '<w:name w:val="B"/><w:basedOn w:val="2"/></w:style>'
              '<w:style w:type="paragraph" w:styleId="C">'
              '<w:name w:val="C"/><w:basedOn w:val="B"/></w:style>',
            ),
          ),
        ),
        'ב',
      );
      expect(result, contains('<h2>סימן</h2>'));
    });

    test('outlineLvl מפורש בסגנון היורש דוחה את רמת האב', () {
      final result = docxToText(
        _buildDocx(
          _utf8Xml(docWithStyles([('Sub', 'תת-פרק')])),
          stylesXmlBytes: _utf8Xml(
            stylesXml(
              '${headingStyle('Heading1', 'heading 1', 0)}'
              '<w:style w:type="paragraph" w:styleId="Sub">'
              '<w:name w:val="Sub"/><w:basedOn w:val="Heading1"/>'
              '<w:pPr><w:outlineLvl w:val="2"/></w:pPr></w:style>',
            ),
          ),
        ),
        'ב',
      );
      expect(result, contains('<h3>תת-פרק</h3>'));
      expect(result, isNot(contains('<h1>תת-פרק')));
    });

    test('סגנון יורש עם outlineLvl=9 מפורש אינו כותרת', () {
      final result = docxToText(
        _buildDocx(
          _utf8Xml(docWithStyles([('NotHeading', 'גוף')])),
          stylesXmlBytes: _utf8Xml(
            stylesXml(
              '${headingStyle('Heading1', 'heading 1', 0)}'
              '<w:style w:type="paragraph" w:styleId="NotHeading">'
              '<w:name w:val="Not Heading"/>'
              '<w:basedOn w:val="Heading1"/>'
              '<w:pPr><w:outlineLvl w:val="9"/></w:pPr></w:style>',
            ),
          ),
        ),
        'ב',
      );
      expect(result, contains('גוף'));
      expect(result, isNot(contains('<h1>גוף')));
      expect(result, isNot(contains('<h6>גוף')));
    });

    test('שרשרת basedOn מעגלית אינה תוקעת את ההמרה', () {
      final result = docxToText(
        _buildDocx(
          _utf8Xml(docWithStyles([('X', 'טקסט')])),
          stylesXmlBytes: _utf8Xml(
            stylesXml(
              '<w:style w:type="paragraph" w:styleId="X">'
              '<w:name w:val="X"/><w:basedOn w:val="Y"/></w:style>'
              '<w:style w:type="paragraph" w:styleId="Y">'
              '<w:name w:val="Y"/><w:basedOn w:val="X"/></w:style>',
            ),
          ),
        ),
        'ב',
      );
      expect(result, contains('טקסט'));
      expect(result, isNot(contains('<h1>טקסט')));
    });

    test('basedOn על סגנון שאינו קיים אינו קורס', () {
      final result = docxToText(
        _buildDocx(
          _utf8Xml(docWithStyles([('Orphan', 'טקסט')])),
          stylesXmlBytes: _utf8Xml(
            stylesXml(
              '<w:style w:type="paragraph" w:styleId="Orphan">'
              '<w:name w:val="Orphan"/><w:basedOn w:val="Missing"/></w:style>',
            ),
          ),
        ),
        'ב',
      );
      expect(result, contains('טקסט'));
    });

    test('basedOn על סגנון תו אינו הופך את היורש לכותרת', () {
      final result = docxToText(
        _buildDocx(
          _utf8Xml(docWithStyles([('P', 'טקסט')])),
          stylesXmlBytes: _utf8Xml(
            stylesXml(
              '<w:style w:type="character" w:styleId="HChar">'
              '<w:name w:val="heading 1"/></w:style>'
              '<w:style w:type="paragraph" w:styleId="P">'
              '<w:name w:val="P"/><w:basedOn w:val="HChar"/></w:style>',
            ),
          ),
        ),
        'ב',
      );
      expect(result, contains('טקסט'));
      expect(result, isNot(contains('<h1>טקסט')));
    });

    test('outlineLvl=9 מפורש גובר על שם סגנון דמוי-כותרת', () {
      final result = docxToText(
        _buildDocx(
          _utf8Xml(docWithStyles([('1', 'Body')])),
          stylesXmlBytes: _utf8Xml(
            stylesXml(headingStyle('1', 'Heading 1 Draft', 9)),
          ),
        ),
        'ב',
      );
      expect(result, contains('Body'));
      expect(result, isNot(contains('<h1>Body')));
      expect(result, isNot(contains('<h6>Body')));
    });

    test('outlineLvl תקף גובר על רמה אחרת שבשם הסגנון', () {
      final result = docxToText(
        _buildDocx(
          _utf8Xml(docWithStyles([('9', 'סימן')])),
          stylesXmlBytes: _utf8Xml(
            stylesXml(headingStyle('9', 'heading 1', 1)),
          ),
        ),
        'ב',
      );
      expect(result, contains('<h2>סימן</h2>'));
      expect(result, isNot(contains('<h1>סימן')));
    });

    test('outlineLvl פגום אינו חוסם את הגיבוי לפי שם הסגנון', () {
      final result = docxToText(
        _buildDocx(
          _utf8Xml(docWithStyles([('Q', 'פרק')])),
          stylesXmlBytes: _utf8Xml(
            stylesXml(
              '<w:style w:type="paragraph" w:styleId="Q">'
              '<w:name w:val="heading 1"/>'
              '<w:pPr><w:outlineLvl w:val="abc"/></w:pPr></w:style>',
            ),
          ),
        ),
        'ב',
      );
      expect(result, contains('<h1>פרק</h1>'));
    });

    test('outlineLvl מספרי מחוץ לטווח אינו חוסם את שם הסגנון', () {
      final result = docxToText(
        _buildDocx(
          _utf8Xml(docWithStyles([('Q', 'פרק')])),
          stylesXmlBytes: _utf8Xml(
            stylesXml(
              '<w:style w:type="paragraph" w:styleId="Q">'
              '<w:name w:val="heading 1"/>'
              '<w:pPr><w:outlineLvl w:val="10"/></w:pPr></w:style>',
            ),
          ),
        ),
        'ב',
      );
      expect(result, contains('<h1>פרק</h1>'));
    });

    test('styles.xml פגום — ההמרה ממשיכה בלי לקרוס', () {
      final result = docxToText(
        _buildDocx(
          _utf8Xml(docWithStyles([('1', 'טקסט')])),
          stylesXmlBytes: _utf8Xml('<w:styles<<< not xml'),
        ),
        'ב',
      );
      expect(result, contains('טקסט'));
    });
  });

  group('docxToText - הדגשה עברית (complex-script)', () {
    String runWithProps(String props, String text) =>
        '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document $_xmlNs>
  <w:body>
    <w:p><w:r><w:rPr>$props</w:rPr><w:t>$text</w:t></w:r></w:p>
  </w:body>
</w:document>''';

    test('w:bCs בלבד (בלי w:b) מומר ל-<b>', () {
      final result = docxToText(
        _buildDocx(_utf8Xml(runWithProps('<w:bCs/>', 'מודגש'))),
        'ב',
      );
      expect(result, contains('<b>מודגש</b>'));
    });

    test('w:iCs בלבד (בלי w:i) מומר ל-<i>', () {
      final result = docxToText(
        _buildDocx(_utf8Xml(runWithProps('<w:iCs/>', 'נטוי'))),
        'ב',
      );
      expect(result, contains('<i>נטוי</i>'));
    });

    test('w:strike מומר ל-<s>', () {
      final result = docxToText(
        _buildDocx(_utf8Xml(runWithProps('<w:strike/>', 'חוצה'))),
        'ב',
      );
      expect(result, contains('<s>חוצה</s>'));
    });
  });

  group('docxToText - ניקוי תגים לא נתמכים', () {
    String runWithProps(String props, String text) =>
        '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document $_xmlNs>
  <w:body>
    <w:p><w:r><w:rPr>$props</w:rPr><w:t>$text</w:t></w:r></w:p>
  </w:body>
</w:document>''';

    test('צבע שחור (000000) לא נפלט כ-span', () {
      final result = docxToText(
        _buildDocx(_utf8Xml(runWithProps('<w:color w:val="000000"/>', 'טקסט'))),
        'ב',
      );
      expect(result, contains('טקסט'));
      expect(result, isNot(contains('color')));
    });

    test('גופן (rFonts) לא נפלט כ-font-family', () {
      final result = docxToText(
        _buildDocx(
          _utf8Xml(
            runWithProps('<w:rFonts w:ascii="David" w:cs="David"/>', 'טקסט'),
          ),
        ),
        'ב',
      );
      expect(result, contains('טקסט'));
      expect(result, isNot(contains('font-family')));
    });

    test('צבע אמיתי (לא שחור) כן נשמר', () {
      final result = docxToText(
        _buildDocx(_utf8Xml(runWithProps('<w:color w:val="FF0000"/>', 'אדום'))),
        'ב',
      );
      expect(result, contains('color:#FF0000'));
    });
  });

  group('docxToText - מעברי שורה ורשימות', () {
    test('w:br בתוך פסקה מומר ל-<br>', () {
      final xml =
          '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document $_xmlNs>
  <w:body>
    <w:p><w:r><w:t>שורה א</w:t><w:br/><w:t>שורה ב</w:t></w:r></w:p>
  </w:body>
</w:document>''';
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'ב');
      expect(result, contains('שורה א<br>שורה ב'));
    });

    test('פריט רשימה מקבל קידומת תבליט בלי <ul>', () {
      final xml =
          '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document $_xmlNs>
  <w:body>
    <w:p>
      <w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr>
      <w:r><w:t>פריט</w:t></w:r>
    </w:p>
  </w:body>
</w:document>''';
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'ב');
      expect(result, contains('• פריט'));
      expect(result, isNot(contains('<ul>')));
      expect(result, isNot(contains('<li>')));
    });
  });

  group('docxToText - טבלאות ועמידות', () {
    test('תוכן טבלה אינו זולג ומתערבב עם הזרם הרגיל', () {
      final xml =
          '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document $_xmlNs>
  <w:body>
    <w:p><w:r><w:t>פסקת גוף</w:t></w:r></w:p>
    <w:tbl>
      <w:tr>
        <w:tc><w:p><w:r><w:t>תא1</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:r><w:t>תא2</w:t></w:r></w:p></w:tc>
      </w:tr>
    </w:tbl>
  </w:body>
</w:document>''';
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'ב');
      // הטבלה נפלטת כ-<table> אחד (שורה אחת), עם תאים, ולא זולגת לזרם.
      expect(result, contains('<table'));
      expect(result, contains('<td'));
      expect(result, contains('תא1'));
      expect(result, contains('תא2'));
      expect(result, contains('פסקת גוף'));
      // כל הטבלה בשורה לוגית אחת (כי שורה = widget בקורא).
      final tableLine = result
          .split('\n')
          .firstWhere((l) => l.contains('<table'));
      expect(tableLine, contains('</table>'));
    });

    test('XML פגום לא מקריס את היבוא ומחזיר לפחות את הכותרת', () {
      final docx = _buildDocx(_utf8Xml('<w:document not-closed'));
      final result = docxToText(docx, 'כותרת');
      expect(result, contains('<h1>כותרת</h1>'));
    });
  });

  group('docxToText - טבלאות עשירות', () {
    String cell(String text, {String tcPr = ''}) =>
        '<w:tc><w:tcPr>$tcPr</w:tcPr><w:p><w:r><w:t>$text</w:t></w:r></w:p></w:tc>';
    String table(String inner, {String tblPr = ''}) =>
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document $_xmlNs><w:body><w:tbl><w:tblPr>$tblPr</w:tblPr>'
        '$inner</w:tbl></w:body></w:document>';

    test('מיזוג אופקי (gridSpan) → colspan', () {
      final xml = table(
        '<w:tr>'
        '${cell("ממוזג", tcPr: "<w:gridSpan w:val=\"2\"/>")}'
        '</w:tr>',
      );
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'ב');
      expect(result, contains('colspan="2"'));
      expect(result, contains('ממוזג'));
    });

    test('מיזוג אנכי (vMerge) → rowspan', () {
      final xml = table(
        '<w:tr>'
        '${cell("גובה", tcPr: "<w:vMerge w:val=\"restart\"/>")}'
        '${cell("ימין1")}</w:tr>'
        '<w:tr>'
        '${cell("", tcPr: "<w:vMerge/>")}'
        '${cell("ימין2")}</w:tr>',
      );
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'ב');
      expect(result, contains('rowspan="2"'));
      // תא ההמשך אינו נפלט בנפרד (אין td ריק שני)
      expect('גובה'.allMatches(result), hasLength(1));
    });

    test('רקע תא (w:shd) → background-color', () {
      final xml = table(
        '<w:tr>'
        '${cell("צבעוני", tcPr: "<w:shd w:fill=\"FFFF00\"/>")}'
        '</w:tr>',
      );
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'ב');
      expect(result, contains('background-color: #FFFF00'));
    });

    test('שורת כותרת (tblHeader) → <th>', () {
      final xml = table(
        '<w:tr><w:trPr><w:tblHeader/></w:trPr>'
        '${cell("כותרת")}</w:tr>',
      );
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'ב');
      expect(result, contains('<th'));
      expect(result, contains('כותרת'));
    });

    test('טבלה RTL (bidiVisual) → dir="rtl"', () {
      final xml = table(
        '<w:tr>${cell("ימני")}</w:tr>',
        tblPr: '<w:bidiVisual/>',
      );
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'ב');
      expect(result, contains('<table dir="rtl"'));
    });
  });

  group('docxToText - תמונות מוטמעות (offline)', () {
    // ה-namespaces הדרושים לזיהוי a:blip ו-r:embed.
    const imgNs =
        '$_xmlNs '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"';

    Uint8List buildWithImage(String target, List<int> imageBytes) {
      final docXml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document $imgNs><w:body><w:p><w:r><w:drawing>'
          '<a:blip r:embed="rId1"/></w:drawing></w:r></w:p></w:body>'
          '</w:document>';
      final relsXml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" '
          'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
          'Target="$target"/></Relationships>';
      final encoder = ZipEncoder();
      final archive = Archive();
      final doc = utf8.encode(docXml);
      final rels = utf8.encode(relsXml);
      archive.addFile(ArchiveFile('word/document.xml', doc.length, doc));
      archive.addFile(
        ArchiveFile('word/_rels/document.xml.rels', rels.length, rels),
      );
      archive.addFile(
        ArchiveFile(
          'word/${target.startsWith('/') ? target.substring(1) : target}',
          imageBytes.length,
          imageBytes,
        ),
      );
      return Uint8List.fromList(encoder.encode(archive));
    }

    test('תמונת PNG מוטמעת → <img> עם data URI (base64, ללא אינטרנט)', () {
      final png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]; // חתימת PNG
      final result = docxToText(buildWithImage('media/image1.png', png), 'ב');
      expect(result, contains('<img src="data:image/png;base64,'));
      // לא קישור חיצוני — הכל מוטמע
      expect(result, isNot(contains('http')));
    });

    test('תמונת JPEG → data:image/jpeg', () {
      final jpg = [0xFF, 0xD8, 0xFF];
      final result = docxToText(buildWithImage('media/pic.jpeg', jpg), 'ב');
      expect(result, contains('data:image/jpeg;base64,'));
    });

    test('פורמט לא נתמך (EMF) אינו נפלט כתמונה', () {
      final emf = [0x01, 0x00, 0x00, 0x00];
      final result = docxToText(buildWithImage('media/image1.emf', emf), 'ב');
      expect(result, isNot(contains('<img')));
    });
  });

  group('docxToText - רשימות ממוספרות מקוננות', () {
    // בונה numbering.xml עם רמות נתונות (כולן numId=1 → abstractNumId=0).
    String numberingXml(List<List<String>> levels, {String start = '1'}) {
      final lvls = <String>[];
      for (var i = 0; i < levels.length; i++) {
        lvls.add(
          '<w:lvl w:ilvl="$i"><w:start w:val="$start"/>'
          '<w:numFmt w:val="${levels[i][0]}"/>'
          '<w:lvlText w:val="${levels[i][1]}"/></w:lvl>',
        );
      }
      return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:numbering $_xmlNs><w:abstractNum w:abstractNumId="0">'
          '${lvls.join()}</w:abstractNum>'
          '<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>'
          '</w:numbering>';
    }

    String item(int ilvl, String text) =>
        '<w:p><w:pPr><w:numPr><w:ilvl w:val="$ilvl"/>'
        '<w:numId w:val="1"/></w:numPr></w:pPr>'
        '<w:r><w:t>$text</w:t></w:r></w:p>';

    Uint8List build(String body, String numbering) {
      final docXml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document $_xmlNs><w:body>$body</w:body></w:document>';
      final encoder = ZipEncoder();
      final archive = Archive();
      final d = utf8.encode(docXml);
      final n = utf8.encode(numbering);
      archive.addFile(ArchiveFile('word/document.xml', d.length, d));
      archive.addFile(ArchiveFile('word/numbering.xml', n.length, n));
      return Uint8List.fromList(encoder.encode(archive));
    }

    test('מספור decimal רץ: 1. 2. 3.', () {
      final num = numberingXml([
        ['decimal', '%1.'],
      ]);
      final result = docxToText(
        build('${item(0, "ראשון")}${item(0, "שני")}${item(0, "שלישי")}', num),
        'ב',
      );
      expect(result, contains('1. ראשון'));
      expect(result, contains('2. שני'));
      expect(result, contains('3. שלישי'));
    });

    test('multilevel מקונן: 1. ואז 1.1. ואז 1.1.1.', () {
      final num = numberingXml([
        ['decimal', '%1.'],
        ['decimal', '%1.%2.'],
        ['decimal', '%1.%2.%3.'],
      ]);
      final result = docxToText(
        build(
          '${item(0, "א")}${item(1, "ב")}${item(2, "ג")}${item(1, "ד")}',
          num,
        ),
        'ב',
      );
      expect(result, contains('1. א'));
      expect(result, contains('1.1. ב'));
      expect(result, contains('1.1.1. ג'));
      expect(result, contains('1.2. ד'), reason: 'חזרה לרמה 1 ממשיכה ל-1.2');
    });

    test('אותיות לטיניות (lowerLetter): a. b.', () {
      final num = numberingXml([
        ['lowerLetter', '%1.'],
      ]);
      final result = docxToText(
        build('${item(0, "x")}${item(0, "y")}', num),
        'ב',
      );
      expect(result, contains('a. x'));
      expect(result, contains('b. y'));
    });

    test('אותיות רומיות (upperRoman): I. II. III.', () {
      final num = numberingXml([
        ['upperRoman', '%1.'],
      ]);
      final result = docxToText(
        build('${item(0, "a")}${item(0, "b")}${item(0, "c")}', num),
        'ב',
      );
      expect(result, contains('I. a'));
      expect(result, contains('II. b'));
      expect(result, contains('III. c'));
    });

    test('אותיות עבריות (hebrew1): א. ב. ג.', () {
      final num = numberingXml([
        ['hebrew1', '%1.'],
      ]);
      final result = docxToText(
        build('${item(0, "x")}${item(0, "y")}${item(0, "z")}', num),
        'ב',
      );
      expect(result, contains('א. x'));
      expect(result, contains('ב. y'));
      expect(result, contains('ג. z'));
    });

    test('רשימה שמתחילה ממספר נתון (start=5): 5. 6.', () {
      final num = numberingXml([
        ['decimal', '%1.'],
      ], start: '5');
      final result = docxToText(
        build('${item(0, "x")}${item(0, "y")}', num),
        'ב',
      );
      expect(result, contains('5. x'));
      expect(result, contains('6. y'));
    });

    test('תבליט (bullet) נשאר •', () {
      final num = numberingXml([
        ['bullet', ''],
      ]);
      final result = docxToText(build(item(0, "פריט"), num), 'ב');
      expect(result, contains('• פריט'));
    });

    test('רשימה בלי numbering.xml נופלת לתבליט (לא קורסת)', () {
      final docXml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document $_xmlNs><w:body>${item(0, "פריט")}</w:body></w:document>';
      final result = docxToText(_buildDocx(_utf8Xml(docXml)), 'ב');
      expect(result, contains('• פריט'));
    });
  });

  group('docxToText - escaping של תוכן', () {
    test('שם ספר עם < / & מקבל escape בכותרת (לא שובר HTML)', () {
      final result = docxToText(
        _buildDocx(_utf8Xml(_simpleDocXml('תוכן'))),
        'א < ב & ג',
      );
      expect(result, contains('<h1>א &lt; ב &amp; ג</h1>'));
      expect(result, isNot(contains('<h1>א < ב')));
    });

    test('תווי < ו-> בתוכן הופכים ל-entity ולא שוברים את ה-HTML', () {
      // ב-Word התו "<" מקודד כ-&lt; ב-XML; innerText מחזיר "<" גולמי.
      final xml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document $_xmlNs><w:body><w:p><w:r><w:t>a &lt; b &gt; c</w:t>'
          '</w:r></w:p></w:body></w:document>';
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'ב');
      expect(result, contains('a &lt; b &gt; c'));
      // אין "<" גולמי שיתפרש כתגית פתיחה שבורה
      expect(result, isNot(contains('a < b')));
    });

    test('תו & בתוכן הופך ל-&amp;', () {
      final xml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document $_xmlNs><w:body><w:p><w:r><w:t>ר&apos; &amp; כו&apos;</w:t>'
          '</w:r></w:p></w:body></w:document>';
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'ב');
      expect(result, contains('&amp;'));
    });
  });

  group('docxToText - מיזוג runs מפוצלים', () {
    test('שני runs מודגשים סמוכים ממוזגים ל-<b> אחד', () {
      // Word מפצל "שלום" לשני runs מודגשים — הפלט צריך להיות <b>שלום</b> אחד.
      final xml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document $_xmlNs><w:body><w:p>'
          '<w:r><w:rPr><w:b/></w:rPr><w:t>של</w:t></w:r>'
          '<w:r><w:rPr><w:b/></w:rPr><w:t>ום</w:t></w:r>'
          '</w:p></w:body></w:document>';
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'ב');
      expect(result, contains('<b>שלום</b>'));
      expect(result, isNot(contains('</b><b>')));
    });

    test('runs בעיצוב שונה אינם ממוזגים', () {
      final xml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document $_xmlNs><w:body><w:p>'
          '<w:r><w:rPr><w:b/></w:rPr><w:t>מודגש</w:t></w:r>'
          '<w:r><w:rPr><w:i/></w:rPr><w:t>נטוי</w:t></w:r>'
          '</w:p></w:body></w:document>';
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'ב');
      expect(result, contains('<b>מודגש</b>'));
      expect(result, contains('<i>נטוי</i>'));
    });

    test('runs סמוכים עם עיצוב זהה (צבע) ממוזגים ל-span אחד', () {
      // מבחן ביצועים: ניפוח HTML מ-runs מפוצלים של Word עם אותו עיצוב.
      final xml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document $_xmlNs><w:body><w:p>'
          '<w:r><w:rPr><w:color w:val="FF0000"/></w:rPr><w:t>אב</w:t></w:r>'
          '<w:r><w:rPr><w:color w:val="FF0000"/></w:rPr><w:t>גד</w:t></w:r>'
          '</w:p></w:body></w:document>';
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'ב');
      expect(result, contains('<span style="color:#FF0000">אבגד</span>'));
      // span יחיד — לא עותק לכל run
      expect('color:#FF0000'.allMatches(result), hasLength(1));
    });

    test('עטיפה מורכבת זהה (מודגש+צבע+מרקר) ממוזגת פעם אחת', () {
      final props =
          '<w:rPr><w:bCs/><w:color w:val="1F3B6D"/>'
          '<w:highlight w:val="yellow"/></w:rPr>';
      final xml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document $_xmlNs><w:body><w:p>'
          '<w:r>$props<w:t>חלק </w:t></w:r>'
          '<w:r>$props<w:t>שני </w:t></w:r>'
          '<w:r>$props<w:t>שלישי</w:t></w:r>'
          '</w:p></w:body></w:document>';
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'ב');
      // <b> אחד, span-צבע אחד, span-מרקר אחד — לא שלושה עותקים
      expect('<b>'.allMatches(result), hasLength(1));
      expect('background-color:yellow'.allMatches(result), hasLength(1));
      expect(result, contains('חלק שני שלישי'));
    });
  });

  group('docxToText - מאפייני on/off ומעלית/מורד', () {
    String runWithProps(String props, String text) =>
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document $_xmlNs><w:body><w:p><w:r><w:rPr>$props</w:rPr>'
        '<w:t>$text</w:t></w:r></w:p></w:body></w:document>';

    test('w:b w:val="0" (ביטול ירושה) אינו מודגש', () {
      final result = docxToText(
        _buildDocx(_utf8Xml(runWithProps('<w:b w:val="0"/>', 'רגיל'))),
        'ב',
      );
      expect(result, contains('רגיל'));
      expect(result, isNot(contains('<b>')));
    });

    test('w:b w:val="false" אינו מודגש', () {
      final result = docxToText(
        _buildDocx(_utf8Xml(runWithProps('<w:b w:val="false"/>', 'רגיל'))),
        'ב',
      );
      expect(result, isNot(contains('<b>')));
    });

    test('w:u w:val="none" (ביטול קו תחתי) אינו עוטף ב-<u>', () {
      final result = docxToText(
        _buildDocx(_utf8Xml(runWithProps('<w:u w:val="none"/>', 'טקסט'))),
        'ב',
      );
      expect(result, isNot(contains('<u>')));
    });

    test('w:u w:val="single" כן עוטף ב-<u>', () {
      final result = docxToText(
        _buildDocx(_utf8Xml(runWithProps('<w:u w:val="single"/>', 'קו'))),
        'ב',
      );
      expect(result, contains('<u>קו</u>'));
    });

    test('w:vertAlign superscript מומר ל-<sup>', () {
      final result = docxToText(
        _buildDocx(
          _utf8Xml(runWithProps('<w:vertAlign w:val="superscript"/>', 'מעלית')),
        ),
        'ב',
      );
      expect(result, contains('<sup>מעלית</sup>'));
    });

    test('w:vertAlign subscript מומר ל-<sub>', () {
      final result = docxToText(
        _buildDocx(
          _utf8Xml(runWithProps('<w:vertAlign w:val="subscript"/>', 'מורד')),
        ),
        'ב',
      );
      expect(result, contains('<sub>מורד</sub>'));
    });

    test('טקסט מוסתר (w:vanish) אינו מוצג', () {
      final xml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document $_xmlNs><w:body><w:p>'
          '<w:r><w:t>גלוי</w:t></w:r>'
          '<w:r><w:rPr><w:vanish/></w:rPr><w:t>מוסתר</w:t></w:r>'
          '</w:p></w:body></w:document>';
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'ב');
      expect(result, contains('גלוי'));
      expect(result, isNot(contains('מוסתר')));
    });
  });

  group('docxToText - מרקר ויישור', () {
    String runWithProps(String props, String text) =>
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document $_xmlNs><w:body><w:p><w:r><w:rPr>$props</w:rPr>'
        '<w:t>$text</w:t></w:r></w:p></w:body></w:document>';

    test('w:highlight=yellow מומר לרקע צבעוני', () {
      final result = docxToText(
        _buildDocx(
          _utf8Xml(runWithProps('<w:highlight w:val="yellow"/>', 'מסומן')),
        ),
        'ב',
      );
      expect(result, contains('background-color:yellow'));
      expect(result, contains('מסומן'));
    });

    test('w:highlight=darkYellow ממופה ל-HEX (אין שם CSS)', () {
      final result = docxToText(
        _buildDocx(
          _utf8Xml(runWithProps('<w:highlight w:val="darkYellow"/>', 'כהה')),
        ),
        'ב',
      );
      expect(result, contains('background-color:#808000'));
    });

    test('w:highlight=none אינו יוצר רקע', () {
      final result = docxToText(
        _buildDocx(
          _utf8Xml(runWithProps('<w:highlight w:val="none"/>', 'רגיל')),
        ),
        'ב',
      );
      expect(result, isNot(contains('background-color')));
    });

    test('פסקת גוף עם jc=center מתקבלת מיושרת למרכז', () {
      final xml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document $_xmlNs><w:body><w:p>'
          '<w:pPr><w:jc w:val="center"/></w:pPr>'
          '<w:r><w:t>שירת הים</w:t></w:r></w:p></w:body></w:document>';
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'ב');
      expect(result, contains('text-align: center'));
      expect(result, contains('שירת הים'));
    });

    test('כותרת ממורכזת לא נעטפת ב-div (נשמר זיהוי <h>)', () {
      // כותרת עם jc=center חייבת להישאר <h..> בתחילת השורה כדי ש-TocParser יזהה.
      final xml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document $_xmlNs><w:body><w:p>'
          '<w:pPr><w:pStyle w:val="Heading1"/><w:jc w:val="center"/></w:pPr>'
          '<w:r><w:t>פרק</w:t></w:r></w:p></w:body></w:document>';
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'ב');
      expect(result, contains('<h1>פרק</h1>'));
      expect(result, isNot(contains('text-align')));
    });

    test('jc=right מתקבל מיושר לימין', () {
      final xml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document $_xmlNs><w:body><w:p>'
          '<w:pPr><w:jc w:val="right"/></w:pPr>'
          '<w:r><w:t>ימין</w:t></w:r></w:p></w:body></w:document>';
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'ב');
      expect(result, contains('text-align: right'));
    });

    test('jc=left מתקבל מיושר לשמאל', () {
      final xml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document $_xmlNs><w:body><w:p>'
          '<w:pPr><w:jc w:val="left"/></w:pPr>'
          '<w:r><w:t>שמאל</w:t></w:r></w:p></w:body></w:document>';
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'ב');
      expect(result, contains('text-align: left'));
    });
  });

  group('docxToText - סוגי קווים תחתונים וקו חוצה', () {
    String runWithProps(String props, String text) =>
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document $_xmlNs><w:body><w:p><w:r><w:rPr>$props</w:rPr>'
        '<w:t>$text</w:t></w:r></w:p></w:body></w:document>';

    test('קו תחתי כפול → text-decoration underline double', () {
      final result = docxToText(
        _buildDocx(_utf8Xml(runWithProps('<w:u w:val="double"/>', 'כפול'))),
        'ב',
      );
      expect(result, contains('text-decoration: underline double'));
    });

    test('קו תחתי מנוקד (dotted) → dotted', () {
      final result = docxToText(
        _buildDocx(_utf8Xml(runWithProps('<w:u w:val="dotted"/>', 'מנוקד'))),
        'ב',
      );
      expect(result, contains('underline dotted'));
    });

    test('קו תחתי מקווקו (dash) → dashed', () {
      final result = docxToText(
        _buildDocx(_utf8Xml(runWithProps('<w:u w:val="dash"/>', 'מקווקו'))),
        'ב',
      );
      expect(result, contains('underline dashed'));
    });

    test('קו תחתי גלי (wave) → wavy', () {
      final result = docxToText(
        _buildDocx(_utf8Xml(runWithProps('<w:u w:val="wave"/>', 'גלי'))),
        'ב',
      );
      expect(result, contains('underline wavy'));
    });

    test('קו תחתי עבה (thick) → thickness', () {
      final result = docxToText(
        _buildDocx(_utf8Xml(runWithProps('<w:u w:val="thick"/>', 'עבה'))),
        'ב',
      );
      expect(result, contains('text-decoration-thickness'));
    });

    test('קו תחתי צבעוני → text-decoration-color', () {
      final result = docxToText(
        _buildDocx(
          _utf8Xml(
            runWithProps('<w:u w:val="single" w:color="FF0000"/>', 'צבעוני'),
          ),
        ),
        'ב',
      );
      expect(result, contains('text-decoration-color: #FF0000'));
    });

    test('קו תחתי single רגיל נשאר <u> (ניתן למיזוג)', () {
      final result = docxToText(
        _buildDocx(_utf8Xml(runWithProps('<w:u w:val="single"/>', 'רגיל'))),
        'ב',
      );
      expect(result, contains('<u>רגיל</u>'));
    });

    test('קו חוצה כפול (dstrike) → line-through double', () {
      final result = docxToText(
        _buildDocx(_utf8Xml(runWithProps('<w:dstrike/>', 'חוצה כפול'))),
        'ב',
      );
      expect(result, contains('text-decoration: line-through double'));
    });

    test('קו חוצה יחיד (strike) נשאר <s>', () {
      final result = docxToText(
        _buildDocx(_utf8Xml(runWithProps('<w:strike/>', 'חוצה'))),
        'ב',
      );
      expect(result, contains('<s>חוצה</s>'));
    });
  });

  group('docxToText - מבנים מקוננים (sdt וטבלאות מקוננות)', () {
    test('פסקה בתוך w:sdt (בקרת תוכן) אינה נשמטת', () {
      final xml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document $_xmlNs><w:body>'
          '<w:p><w:r><w:t>לפני</w:t></w:r></w:p>'
          '<w:sdt><w:sdtContent>'
          '<w:p><w:r><w:t>בתוך בקרת תוכן</w:t></w:r></w:p>'
          '</w:sdtContent></w:sdt>'
          '<w:p><w:r><w:t>אחרי</w:t></w:r></w:p>'
          '</w:body></w:document>';
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'ב');
      expect(result, contains('לפני'));
      expect(
        result,
        contains('בתוך בקרת תוכן'),
        reason: 'תוכן עטוף ב-sdt לא נאבד',
      );
      expect(result, contains('אחרי'));
    });

    test('טבלה בתוך w:sdt אינה נשמטת', () {
      final xml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document $_xmlNs><w:body><w:sdt><w:sdtContent>'
          '<w:tbl><w:tr><w:tc><w:p><w:r><w:t>תא-בסדט</w:t></w:r></w:p></w:tc>'
          '</w:tr></w:tbl>'
          '</w:sdtContent></w:sdt></w:body></w:document>';
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'ב');
      expect(result, contains('<table'));
      expect(result, contains('תא-בסדט'));
    });

    test('טבלה מקוננת בתוך תא — תוכנה הפנימי נשמר', () {
      final xml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document $_xmlNs><w:body><w:tbl><w:tr><w:tc>'
          '<w:p><w:r><w:t>חיצוני</w:t></w:r></w:p>'
          '<w:tbl><w:tr><w:tc><w:p><w:r><w:t>פנימי</w:t></w:r></w:p></w:tc>'
          '</w:tr></w:tbl>'
          '</w:tc></w:tr></w:tbl></w:body></w:document>';
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'ב');
      expect(result, contains('חיצוני'));
      expect(result, contains('פנימי'), reason: 'תוכן טבלה מקוננת לא נאבד');
      // שתי טבלאות (חיצונית + מקוננת)
      expect('<table'.allMatches(result).length, greaterThanOrEqualTo(2));
    });

    test('שורת טבלה עטופה ב-w:sdt אינה נשמטת', () {
      final xml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document $_xmlNs><w:body><w:tbl>'
          '<w:tr><w:tc><w:p><w:r><w:t>רגילה</w:t></w:r></w:p></w:tc></w:tr>'
          '<w:sdt><w:sdtContent>'
          '<w:tr><w:tc><w:p><w:r><w:t>בתוך-סדט</w:t></w:r></w:p></w:tc></w:tr>'
          '</w:sdtContent></w:sdt>'
          '</w:tbl></w:body></w:document>';
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'ב');
      expect(result, contains('רגילה'));
      expect(
        result,
        contains('בתוך-סדט'),
        reason: 'שורת טבלה עטופה ב-sdt לא נאבדת',
      );
    });

    test('תא טבלה עטוף ב-w:sdt אינו נשמט', () {
      final xml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document $_xmlNs><w:body><w:tbl><w:tr>'
          '<w:tc><w:p><w:r><w:t>תא-א</w:t></w:r></w:p></w:tc>'
          '<w:sdt><w:sdtContent>'
          '<w:tc><w:p><w:r><w:t>תא-סדט</w:t></w:r></w:p></w:tc>'
          '</w:sdtContent></w:sdt>'
          '</w:tr></w:tbl></w:body></w:document>';
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'ב');
      expect(result, contains('תא-א'));
      expect(result, contains('תא-סדט'), reason: 'תא עטוף ב-sdt לא נאבד');
    });
  });

  group('docxToText - תגיות אוצריא מילוליות', () {
    test('תגיות אוצריא שהוקלדו כטקסט מופעלות כעיצוב אמיתי', () {
      // ב-XML של המסמך התגית מופיעה כ-entities — כלומר טקסט גלוי במסמך Word.
      final docx = _buildDocx(
        _utf8Xml(
          _simpleDocXml(
            '&lt;big&gt;&lt;b&gt;יתגבר כארי&lt;/b&gt;&lt;/big&gt; לעמוד בבקר',
          ),
        ),
      );
      final result = docxToText(docx, 'ב');

      expect(result, contains('<big><b>יתגבר כארי</b></big>'));
      expect(result, isNot(contains('&lt;big&gt;')));
    });

    test('תגית כותרת מילולית הופכת לכותרת אמיתית (וזמינה ל-TocParser)', () {
      final docx = _buildDocx(
        _utf8Xml(_simpleDocXml('&lt;h4&gt;סעיף א&lt;/h4&gt;')),
      );
      final result = docxToText(docx, 'ב');

      expect(result, contains('<h4>סעיף א</h4>'));
      expect(result, isNot(contains('&lt;h4&gt;')));
    });

    test('תגית שפוצלה בין כמה runs מזוהה לאחר האיחוד', () {
      final xml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document $_xmlNs><w:body><w:p>'
          '<w:r><w:t xml:space="preserve">&lt;bi</w:t></w:r>'
          '<w:r><w:t xml:space="preserve">g&gt;מילה&lt;/big&gt;</w:t></w:r>'
          '</w:p></w:body></w:document>';
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'ב');

      expect(result, contains('<big>מילה</big>'));
    });

    test('סוגריים מחודדים שאינם תגית אוצריא נשארים escaped', () {
      final docx = _buildDocx(
        _utf8Xml(_simpleDocXml('נוסחה: a&lt;x&gt; וגם &lt;תנאי&gt; וטקסט')),
      );
      final result = docxToText(docx, 'ב');

      expect(result, contains('a&lt;x&gt;'));
      expect(result, contains('&lt;תנאי&gt;'));
      expect(result, isNot(contains('<x>')));
    });
  });

  group('docxToText - תיבות-טקסט (textbox / shape)', () {
    const drawNs =
        '$_xmlNs '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"';

    test('טקסט בתוך תיבת-טקסט מוצג במסגרת (div) ולא נכפל', () {
      final xml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document $drawNs><w:body><w:p><w:r><w:drawing>'
          '<w:txbxContent>'
          '<w:p><w:r><w:t>טקסט בתוך מסגרת</w:t></w:r></w:p>'
          '</w:txbxContent></w:drawing></w:r></w:p></w:body></w:document>';
      final result = docxToText(_buildDocx(_utf8Xml(xml)), 'ב');
      expect(result, contains('טקסט בתוך מסגרת'));
      expect(result, contains('border:'), reason: 'נעטף במסגרת');
      // לא מופיע פעמיים (פעם inline ופעם בתיבה)
      expect('טקסט בתוך מסגרת'.allMatches(result), hasLength(1));
    });

    test('מסגרת-רקע דקורטיבית (behindDoc) מדולגת — לא בלוק ריק', () {
      final docXml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document $drawNs '
          'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing">'
          '<w:body>'
          '<w:p><w:r><w:drawing>'
          '<wp:anchor behindDoc="1"><a:blip r:embed="rId1"/></wp:anchor>'
          '</w:drawing></w:r></w:p>'
          '<w:p><w:r><w:t>כותרת הספר</w:t></w:r></w:p>'
          '</w:body></w:document>';
      final relsXml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" '
          'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
          'Target="media/i.png"/></Relationships>';
      final encoder = ZipEncoder();
      final archive = Archive();
      final d = utf8.encode(docXml);
      final rels = utf8.encode(relsXml);
      final png = [0x89, 0x50, 0x4E, 0x47];
      archive.addFile(ArchiveFile('word/document.xml', d.length, d));
      archive.addFile(
        ArchiveFile('word/_rels/document.xml.rels', rels.length, rels),
      );
      archive.addFile(ArchiveFile('word/media/i.png', png.length, png));
      final result = docxToText(
        Uint8List.fromList(encoder.encode(archive)),
        'ב',
      );
      expect(result, contains('כותרת הספר'), reason: 'הטקסט נשמר');
      expect(
        result,
        isNot(contains('<img')),
        reason: 'מסגרת-הרקע מדולגת — לא מוצגת כבלוק ריק',
      );
    });

    test('תיבת-טקסט עם תמונת-רקע → טקסט על background-image', () {
      final docXml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document $drawNs><w:body><w:p><w:r><w:drawing>'
          '<a:blip r:embed="rId1"/>'
          '<w:txbxContent>'
          '<w:p><w:r><w:t>על התמונה</w:t></w:r></w:p>'
          '</w:txbxContent></w:drawing></w:r></w:p></w:body></w:document>';
      final relsXml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" '
          'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
          'Target="media/i.png"/></Relationships>';
      final encoder = ZipEncoder();
      final archive = Archive();
      final d = utf8.encode(docXml);
      final rels = utf8.encode(relsXml);
      final png = [0x89, 0x50, 0x4E, 0x47];
      archive.addFile(ArchiveFile('word/document.xml', d.length, d));
      archive.addFile(
        ArchiveFile('word/_rels/document.xml.rels', rels.length, rels),
      );
      archive.addFile(ArchiveFile('word/media/i.png', png.length, png));
      final result = docxToText(
        Uint8List.fromList(encoder.encode(archive)),
        'ב',
      );
      expect(result, contains('על התמונה'));
      expect(
        result,
        contains('background-image: url(data:image/png;base64,'),
        reason: 'הטקסט על תמונת-רקע מוטמעת',
      );
    });

    test('תמונה inline בתוך תיבת-טקסט אינה מזוהה כתמונת-רקע', () {
      final docXml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document $drawNs><w:body><w:p><w:r><w:drawing>'
          '<w:txbxContent>'
          '<w:p><w:r><w:t>לפני תמונה</w:t></w:r>'
          '<w:r><w:drawing><a:blip r:embed="rId1"/></w:drawing></w:r>'
          '</w:p>'
          '</w:txbxContent></w:drawing></w:r></w:p></w:body></w:document>';
      final relsXml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" '
          'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
          'Target="media/i.png"/></Relationships>';
      final encoder = ZipEncoder();
      final archive = Archive();
      final d = utf8.encode(docXml);
      final rels = utf8.encode(relsXml);
      final png = [0x89, 0x50, 0x4E, 0x47];
      archive.addFile(ArchiveFile('word/document.xml', d.length, d));
      archive.addFile(
        ArchiveFile('word/_rels/document.xml.rels', rels.length, rels),
      );
      archive.addFile(ArchiveFile('word/media/i.png', png.length, png));
      final result = docxToText(
        Uint8List.fromList(encoder.encode(archive)),
        'ב',
      );
      expect(result, contains('לפני תמונה'));
      expect(
        result,
        contains('<img src="data:image/png;base64,'),
        reason: 'תמונה בתוך תוכן התיבה נשארת inline',
      );
      expect(
        result,
        isNot(contains('background-image')),
        reason: 'רק תמונה מחוץ ל-txbxContent משמשת כרקע לתיבה',
      );
    });

    test('תיבת-טקסט ריקה עם תמונה → <img> רגיל ולא div ריק', () {
      final docXml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document $drawNs><w:body><w:p><w:r><w:drawing>'
          '<a:blip r:embed="rId1"/>'
          '<w:txbxContent><w:p></w:p></w:txbxContent>'
          '</w:drawing></w:r></w:p></w:body></w:document>';
      final relsXml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" '
          'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
          'Target="media/i.png"/></Relationships>';
      final encoder = ZipEncoder();
      final archive = Archive();
      final d = utf8.encode(docXml);
      final rels = utf8.encode(relsXml);
      final png = [0x89, 0x50, 0x4E, 0x47];
      archive.addFile(ArchiveFile('word/document.xml', d.length, d));
      archive.addFile(
        ArchiveFile('word/_rels/document.xml.rels', rels.length, rels),
      );
      archive.addFile(ArchiveFile('word/media/i.png', png.length, png));
      final result = docxToText(
        Uint8List.fromList(encoder.encode(archive)),
        'ב',
      );
      expect(
        result,
        contains('<img src="data:image/png;base64,'),
        reason: 'תיבה ריקה מטקסט → התמונה כ-<img> רגיל',
      );
      expect(
        result,
        isNot(contains('background-image')),
        reason: 'לא div ריק עם background-image (חסר גובה, לא מציג)',
      );
    });
  });
}

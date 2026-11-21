import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/printing/print_content_models.dart';
import 'package:otzaria/printing/word_export_service.dart';
import 'package:otzaria/utils/file/docx_to_otzaria.dart';
import 'package:otzaria/utils/file/word_xml_to_otzaria.dart';

import 'package:pdf/pdf.dart';

import 'docx_golden_fixtures.dart';

String _hyperlinkRels(Map<String, String> targets) {
  final relations = targets.entries
      .map(
        (entry) =>
            '<Relationship Id="${entry.key}" Target="${entry.value}" '
            'Type="http://schemas.openxmlformats.org/officeDocument/2006/'
            'relationships/hyperlink" TargetMode="External"/>',
      )
      .join();
  return '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
      'relationships">$relations</Relationships>';
}

String _convertDocx(String body, {Map<String, String> links = const {}}) =>
    docxToText(
      buildDocx(
        document: documentXml(body),
        rels: links.isEmpty ? null : _hyperlinkRels(links),
      ),
      'ספר',
    );

Uint8List _wordMl2003(String content) => Uint8List.fromList(
  utf8.encode(
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<w:wordDocument '
    'xmlns:w="http://schemas.microsoft.com/office/word/2003/wordml" '
    'xmlns:wx="http://schemas.microsoft.com/office/word/2003/auxHint" '
    'xmlns:aml="http://schemas.microsoft.com/aml/2001/core">'
    '<w:body><wx:sect>$content</wx:sect></w:body></w:wordDocument>',
  ),
);

String _convertWordMl(String body) => wordXmlToText(_wordMl2003(body), 'ספר');

void main() {
  group('קישורי OOXML', () {
    test('שומר קישור חיצוני מ-relationship', () {
      final result = _convertDocx(
        '<w:p><w:hyperlink r:id="rId7"><w:r><w:t>אתר</w:t></w:r>'
        '</w:hyperlink></w:p>',
        links: {'rId7': 'https://example.test/path?x=1'},
      );

      expect(
        result,
        contains('<a href="https://example.test/path?x=1">אתר</a>'),
      );
    });

    test('r:id גובר על w:anchor כששניהם קיימים', () {
      final result = _convertDocx(
        '<w:p><w:bookmarkStart w:id="1" w:name="מקומי"/>'
        '<w:r><w:t>יעד</w:t></w:r></w:p>'
        '<w:p><w:hyperlink r:id="rId1" w:anchor="מקומי">'
        '<w:r><w:t>קישור</w:t></w:r></w:hyperlink></w:p>',
        links: {'rId1': 'https://example.test/external'},
      );

      expect(result, contains('href="https://example.test/external"'));
      expect(result, isNot(contains('href="#מקומי"')));
      expect(result, isNot(contains('id="מקומי"')));
    });

    test('ממזג runs מעוצבים בתוך עוגן אחד', () {
      final result = _convertDocx(
        '<w:p><w:hyperlink r:id="rId1">'
        '<w:r><w:rPr><w:b/></w:rPr><w:t>מודגש</w:t></w:r>'
        '<w:r><w:t> רגיל</w:t></w:r>'
        '</w:hyperlink></w:p>',
        links: {'rId1': 'https://example.test'},
      );

      expect(
        result,
        contains('<a href="https://example.test"><b>מודגש</b> רגיל</a>'),
      );
    });

    test('קישור פנימי לסימנייה בפסקת גוף מקבל עוגן id', () {
      final result = _convertDocx(
        '<w:p><w:bookmarkStart w:id="1" w:name="פסקה"/>'
        '<w:r><w:t>היעד</w:t></w:r></w:p>'
        '<w:p><w:hyperlink w:anchor="פסקה">'
        '<w:r><w:t>חזרה</w:t></w:r></w:hyperlink></w:p>',
      );

      expect(result, contains('<a id="פסקה"></a>היעד'));
      expect(result, contains('<a href="#פסקה">חזרה</a>'));
    });

    test('סימנייה בכותרת הופכת ל-id של הכותרת', () {
      final result = _convertDocx(
        '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>'
        '<w:bookmarkStart w:id="1" w:name="פרק"/>'
        '<w:r><w:t>פרק</w:t></w:r></w:p>'
        '<w:p><w:hyperlink w:anchor="פרק">'
        '<w:r><w:t>קפוץ</w:t></w:r></w:hyperlink></w:p>',
      );

      expect(result, contains('<h1 id="פרק">פרק</h1>'));
      expect(result, contains('<a href="#פרק">קפוץ</a>'));
    });

    test('יעד חסר או סכימה חסומה נשארים טקסט רגיל', () {
      final unresolved = _convertDocx(
        '<w:p><w:hyperlink r:id="rIdMissing"><w:r><w:t>חסר</w:t></w:r>'
        '</w:hyperlink></w:p>',
      );
      final unsafe = _convertDocx(
        '<w:p><w:hyperlink r:id="rId1"><w:r><w:t>חסום</w:t></w:r>'
        '</w:hyperlink></w:p>',
        links: {'rId1': 'javascript:alert(1)'},
      );

      expect(unresolved, contains('חסר'));
      expect(unresolved, isNot(contains('<a href=')));
      expect(unsafe, contains('חסום'));
      expect(unsafe, isNot(contains('<a href=')));
    });
  });

  group('קישורי WordML 2003', () {
    test('w:hlink עם w:dest חיצוני נשמר', () {
      final result = _convertWordMl(
        '<w:p><w:hlink w:dest="https://example.test/wordml">'
        '<w:r><w:t>אתר</w:t></w:r></w:hlink></w:p>',
      );

      expect(result, contains('<a href="https://example.test/wordml">אתר</a>'));
    });

    test('w:bookmark מפנה לעוגן aml:annotation בפסקת גוף', () {
      final result = _convertWordMl(
        '<w:p><aml:annotation w:type="Word.Bookmark.Start" w:name="יעד"/>'
        '<w:r><w:t>היעד</w:t></w:r></w:p>'
        '<w:p><w:hlink w:bookmark="יעד"><w:r><w:t>חזרה</w:t></w:r>'
        '</w:hlink></w:p>',
      );

      expect(result, contains('<a id="יעד"></a>היעד'));
      expect(result, contains('<a href="#יעד">חזרה</a>'));
    });

    test('יעד WordML מסוכן נשאר טקסט רגיל', () {
      final result = _convertWordMl(
        '<w:p><w:hlink w:dest="javascript:alert(1)">'
        '<w:r><w:t>חסום</w:t></w:r></w:hlink></w:p>',
      );

      expect(result, contains('חסום'));
      expect(result, isNot(contains('<a href=')));
    });
  });

  test('Flat OPC משתמש באותם relationships של OOXML', () {
    final document = documentXml(
      '<w:p><w:hyperlink r:id="rId1"><w:r><w:t>אתר</w:t></w:r>'
      '</w:hyperlink></w:p>',
    );
    final flatOpc =
        '<?xml version="1.0"?><pkg:package '
        'xmlns:pkg="http://schemas.microsoft.com/office/2006/xmlPackage">'
        '<pkg:part pkg:name="/word/document.xml" pkg:contentType="application/xml">'
        '<pkg:xmlData>${document.replaceFirst(RegExp(r'^<\?xml[^>]*\?>'), '')}'
        '</pkg:xmlData></pkg:part>'
        '<pkg:part pkg:name="/word/_rels/document.xml.rels" '
        'pkg:contentType="application/xml"><pkg:xmlData>'
        '${_hyperlinkRels({'rId1': 'mailto:test@example.test'})}'
        '</pkg:xmlData></pkg:part></pkg:package>';

    final result = wordXmlToText(
      Uint8List.fromList(utf8.encode(flatOpc)),
      'ספר',
    );

    expect(result, contains('<a href="mailto:test@example.test">אתר</a>'));
  });

  group('קישורי אוצריא ממסמך Word (issue #5714)', () {
    test('קישור ישיר לספר מ-relationship נשמר', () {
      final result = _convertDocx(
        '<w:p><w:hyperlink r:id="rId1"><w:r><w:t>ברכות</w:t></w:r>'
        '</w:hyperlink></w:p>'
        '<w:p><w:hyperlink r:id="rId2"><w:r><w:t>סריקה</w:t></w:r>'
        '</w:hyperlink></w:p>',
        links: {
          'rId1': 'otzaria://open/book/12?index=2',
          'rId2': 'otzaria://open/pdf/8',
        },
      );

      expect(
        result,
        contains('<a href="otzaria://open/book/12?index=2">ברכות</a>'),
      );
      expect(result, contains('<a href="otzaria://open/pdf/8">סריקה</a>'));
    });

    test('קישור ישיר לספר מ-w:dest של WordML נשמר', () {
      final result = _convertWordMl(
        '<w:p><w:hlink w:dest="otzaria://open/book/12?index=2">'
        '<w:r><w:t>ברכות</w:t></w:r></w:hlink></w:p>',
      );

      expect(
        result,
        contains('<a href="otzaria://open/book/12?index=2">ברכות</a>'),
      );
    });

    test('פעולות otzaria:// אחרות נשארות טקסט רגיל', () {
      final result = _convertDocx(
        '<w:p><w:hyperlink r:id="rId1"><w:r><w:t>הגדרות</w:t></w:r>'
        '</w:hyperlink></w:p>',
        links: {'rId1': 'otzaria://open/settings'},
      );

      expect(result, contains('הגדרות'));
      expect(result, isNot(contains('<a href=')));
    });

    test('קובץ Word שאוצריא ייצאה נפתח עם קישורי המקור', () {
      const source = 'otzaria://open/book/12?source=user&index=2';
      final docx = WordExportService.createWordDocument(
        title: 'ייצוא',
        blocks: const [
          PrintBlock(
            kind: PrintBlockKind.heading,
            headingLevel: 2,
            text: 'מקור',
            sourceLink: source,
          ),
        ],
        format: PdfPageFormat.a4,
        isLandscape: false,
        pageMargin: 20,
      );

      final result = docxToText(docx, 'ייצוא');

      expect(result, contains('href="otzaria://open/book/12?source=user&amp;'));
      expect(result, contains('מקור</a>'));
    });
  });
}

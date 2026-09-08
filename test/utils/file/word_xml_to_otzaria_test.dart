import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/docx_to_otzaria.dart';
import 'package:otzaria/utils/file/document_conversion_exceptions.dart';
import 'package:otzaria/utils/file/document_format.dart';
import 'package:otzaria/utils/file/word_xml_to_otzaria.dart';

import '../../../tool/src/document_fixtures/ooxml_builder.dart';

/// תמונת PNG זעירה תקינה (1×1 שקוף).
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNkYAAAAAYAAjCB'
  '0C8AAAAASUVORK5CYII=',
);

String _body(String content) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/'
    '2006/main"><w:body>$content</w:body></w:document>';

/// עוטף חלקי חבילה כ-Flat OPC — בדיוק המבנה ש-Word כותב ל-‎.xml‎.
Uint8List _flatOpc(
  Map<String, String> xmlParts, {
  Map<String, Uint8List> binaryParts = const {},
}) {
  final buffer = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<?mso-application progid="Word.Document"?>')
    ..write(
      '<pkg:package xmlns:pkg="http://schemas.microsoft.com/office/2006/'
      'xmlPackage">',
    );
  xmlParts.forEach((name, content) {
    final stripped = content.replaceFirst(RegExp(r'^<\?xml[^>]*\?>'), '');
    buffer
      ..write('<pkg:part pkg:name="$name" pkg:contentType="application/xml">')
      ..write('<pkg:xmlData>$stripped</pkg:xmlData></pkg:part>');
  });
  binaryParts.forEach((name, bytes) {
    buffer
      ..write('<pkg:part pkg:name="$name" pkg:contentType="image/png">')
      ..write('<pkg:binaryData>${base64Encode(bytes)}</pkg:binaryData>')
      ..write('</pkg:part>');
  });
  buffer.write('</pkg:package>');
  return Uint8List.fromList(utf8.encode(buffer.toString()));
}

/// עוטף גוף כמסמך WordprocessingML 2003.
Uint8List _wordMl2003(String content, {String extra = ''}) {
  final xml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<?mso-application progid="Word.Document"?>'
      '<w:wordDocument '
      'xmlns:w="http://schemas.microsoft.com/office/word/2003/wordml" '
      'xmlns:wx="http://schemas.microsoft.com/office/word/2003/auxHint" '
      'xmlns:v="urn:schemas-microsoft-com:vml">'
      '$extra'
      '<w:body><wx:sect>$content</wx:sect></w:body>'
      '</w:wordDocument>';
  return Uint8List.fromList(utf8.encode(xml));
}

String _convert(Uint8List bytes, {bool embedImages = true}) =>
    wordXmlToText(bytes, 'ספר', embedImages: embedImages);

void main() {
  group('זיהוי הדיאלקט', () {
    test('Flat OPC מזוהה לפי שורש pkg:package', () {
      final bytes = _flatOpc({'/word/document.xml': _body('')});
      expect(sniffWordXmlDialect(bytes), WordXmlDialect.flatOpc);
      expect(detectDocumentFormatFromContentSync(bytes), DocumentFormat.xml);
    });

    test('WordML 2003 מזוהה לפי שורש w:wordDocument', () {
      final bytes = _wordMl2003('');
      expect(sniffWordXmlDialect(bytes), WordXmlDialect.wordMl2003);
      expect(detectDocumentFormatFromContentSync(bytes), DocumentFormat.xml);
    });

    test('XML שאינו Word אינו מזוהה — ולכן אינו נאסף כספר', () {
      final bytes = Uint8List.fromList(
        utf8.encode('<?xml version="1.0"?><config><item>ערך</item></config>'),
      );
      expect(sniffWordXmlDialect(bytes), isNull);
      expect(detectDocumentFormatFromContentSync(bytes), isNull);
      expect(resolveDocumentFormat(DocumentFormat.xml, bytes), isNull);
    });

    test('הסיומת לבדה אינה מספיקה — xml דורש זיהוי תוכן', () {
      expect(DocumentFormat.xml.needsContentSniffing, isTrue);
      expect(documentFormatFromExtension('a.xml'), DocumentFormat.xml);
      expect(documentFormatFromExtension('a.XML'), DocumentFormat.xml);
    });

    test('שורש שאינו Word זורק חריגה מוקלדת', () {
      final bytes = Uint8List.fromList(
        utf8.encode('<?xml version="1.0"?><rss><channel/></rss>'),
      );
      expect(
        () => _convert(bytes),
        throwsA(isA<UnsupportedDocumentFormatException>()),
      );
    });

    test('XML פגום זורק CorruptedDocumentException', () {
      final bytes = Uint8List.fromList(utf8.encode('<pkg:package><broken'));
      expect(
        () => _convert(bytes),
        throwsA(isA<CorruptedDocumentException>()),
      );
    });
  });

  group('Flat OPC', () {
    test('פלט זהה לחבילת DOCX עם אותו תוכן', () {
      const document =
          '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>'
          '<w:r><w:t>כותרת</w:t></w:r></w:p>'
          '<w:p><w:r><w:rPr><w:b/></w:rPr><w:t>מודגש</w:t></w:r></w:p>';
      final docx = buildOoxmlPackage(document: _body(document));
      final flat = _flatOpc({'/word/document.xml': _body(document)});

      expect(_convert(flat), docxToText(docx, 'ספר'));
    });

    test('חלקים נלווים נקראים — סגנונות, מספור והערות שוליים', () {
      final flat = _flatOpc({
        '/word/document.xml': _body(
          '<w:p><w:pPr><w:pStyle w:val="2"/></w:pPr>'
          '<w:r><w:t>כותרת מסגנון מספרי</w:t></w:r></w:p>'
          '<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/>'
          '</w:numPr></w:pPr><w:r><w:t>פריט</w:t></w:r></w:p>'
          '<w:p><w:r><w:t>גוף</w:t></w:r>'
          '<w:r><w:footnoteReference w:id="2"/></w:r></w:p>',
        ),
        '/word/styles.xml':
            '<w:styles xmlns:w="http://schemas.openxmlformats.org/'
            'wordprocessingml/2006/main"><w:style w:type="paragraph" '
            'w:styleId="2"><w:name w:val="heading 2"/></w:style></w:styles>',
        '/word/numbering.xml':
            '<w:numbering xmlns:w="http://schemas.openxmlformats.org/'
            'wordprocessingml/2006/main"><w:abstractNum w:abstractNumId="0">'
            '<w:lvl w:ilvl="0"><w:numFmt w:val="hebrew1"/>'
            '<w:lvlText w:val="%1."/></w:lvl></w:abstractNum>'
            '<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>'
            '</w:numbering>',
        '/word/footnotes.xml':
            '<w:footnotes xmlns:w="http://schemas.openxmlformats.org/'
            'wordprocessingml/2006/main"><w:footnote w:id="2">'
            '<w:p><w:r><w:t>הערה</w:t></w:r></w:p></w:footnote></w:footnotes>',
      });

      final out = _convert(flat);
      expect(out, contains('<h2>כותרת מסגנון מספרי</h2>'));
      expect(out, contains('א. פריט'));
      expect(
        out,
        contains(
          '<sup class="footnote-marker">1</sup><i class="footnote">הערה</i>',
        ),
      );
    });

    test('חלק בינארי מפוענח לתמונה מוטמעת', () {
      final flat = _flatOpc(
        {
          '/word/document.xml': _body(
            '<w:p><w:r><w:drawing><a:blip xmlns:a="a" r:embed="rId1" '
            'xmlns:r="r"/></w:drawing></w:r></w:p>',
          ),
          '/word/_rels/document.xml.rels':
              '<Relationships xmlns="http://schemas.openxmlformats.org/'
              'package/2006/relationships"><Relationship Id="rId1" '
              'Type="http://x/image" Target="media/image1.png"/>'
              '</Relationships>',
        },
        binaryParts: {'/word/media/image1.png': _png},
      );

      expect(_convert(flat), contains('<img src="data:image/png;base64,'));
    });

    test('ללא הטמעה התג נשאר ומבנה השורות נשמר', () {
      final flat = _flatOpc(
        {
          '/word/document.xml': _body(
            '<w:p><w:r><w:drawing><a:blip xmlns:a="a" r:embed="rId1" '
            'xmlns:r="r"/></w:drawing></w:r></w:p>',
          ),
          '/word/_rels/document.xml.rels':
              '<Relationships xmlns="http://schemas.openxmlformats.org/'
              'package/2006/relationships"><Relationship Id="rId1" '
              'Type="http://x/image" Target="media/image1.png"/>'
              '</Relationships>',
        },
        binaryParts: {'/word/media/image1.png': _png},
      );

      final withImages = _convert(flat);
      final without = _convert(flat, embedImages: false);
      expect(without, contains('<img src=""'));
      expect(without.split('\n').length, withImages.split('\n').length);
    });

    test('חבילה בלי אף חלק קריא נכשלת בקול', () {
      final bytes = Uint8List.fromList(
        utf8.encode(
          '<pkg:package xmlns:pkg="http://schemas.microsoft.com/office/2006/'
          'xmlPackage"/>',
        ),
      );
      expect(
        () => _convert(bytes),
        throwsA(isA<CorruptedDocumentException>()),
      );
    });
  });

  group('WordprocessingML 2003', () {
    test('גוף עטוף ב-wx:sect נקרא, והכותרת מוזרקת', () {
      final out = _convert(
        _wordMl2003('<w:p><w:r><w:t>שלום</w:t></w:r></w:p>'),
      );
      expect(out, '<h1>ספר</h1>\nשלום');
    });

    test('wx:sub-section שקוף אף הוא', () {
      final out = _convert(
        _wordMl2003(
          '<wx:sub-section><w:p><w:r><w:t>פנימי</w:t></w:r></w:p>'
          '</wx:sub-section>',
        ),
      );
      expect(out, contains('פנימי'));
    });

    test('סגנון כותרת מתוך w:styles שבאותו מסמך', () {
      final out = _convert(
        _wordMl2003(
          '<w:p><w:pPr><w:pStyle w:val="3"/></w:pPr>'
          '<w:r><w:t>כותרת</w:t></w:r></w:p>',
          extra:
              '<w:styles><w:style w:type="paragraph" w:styleId="3">'
              '<w:name w:val="heading 3"/></w:style></w:styles>',
        ),
      );
      expect(out, contains('<h3>כותרת</h3>'));
    });

    test('w:listPr — התווית שהמסמך חישב (wx:t) גוברת', () {
      final out = _convert(
        _wordMl2003(
          '<w:p><w:pPr><w:listPr><w:ilvl w:val="0"/><w:ilfo w:val="1"/>'
          '<wx:t wx:val="ג."/></w:listPr></w:pPr>'
          '<w:r><w:t>פריט</w:t></w:r></w:p>',
        ),
      );
      expect(out, contains('ג. פריט'));
    });

    test('w:listPr בלי wx:t מחושב מהגדרת w:lists לפי w:nfc', () {
      final out = _convert(
        _wordMl2003(
          '<w:p><w:pPr><w:listPr><w:ilvl w:val="0"/><w:ilfo w:val="1"/>'
          '</w:listPr></w:pPr><w:r><w:t>פריט</w:t></w:r></w:p>',
          extra:
              '<w:lists><w:listDef w:listDefId="0"><w:lvl w:ilvl="0">'
              '<w:nfc w:val="2"/><w:lvlText w:val="%1."/></w:lvl></w:listDef>'
              '<w:list w:ilfo="1"><w:ilst w:val="0"/></w:list></w:lists>',
        ),
      );
      expect(out, contains('i. פריט'));
    });

    test('הערת שוליים inline אינה נספרת פעמיים', () {
      final out = _convert(
        _wordMl2003(
          '<w:p><w:r><w:t>גוף</w:t></w:r>'
          '<w:r><w:footnote><w:p><w:r><w:t>הערה</w:t></w:r></w:p>'
          '</w:footnote></w:r></w:p>',
        ),
      );
      expect(
        out,
        contains(
          'גוף<sup class="footnote-marker">1</sup>'
          '<i class="footnote">הערה</i>',
        ),
      );
      // גוף ההערה יושב בתוך ה-run; בלי דילוג הוא היה נפלט גם כטקסט הפסקה.
      expect('הערה'.allMatches(out).length, 1);
    });

    test('קישור פנימי (w:anchor) לכותרת עם סימניה תואמת', () {
      final out = _convert(
        _wordMl2003(
          '<w:p><w:pPr><w:pStyle w:val="1"/></w:pPr>'
          '<w:bookmarkStart w:id="1" w:name="_Toc1"/>'
          '<w:r><w:t>כותרת יעד</w:t></w:r>'
          '<w:bookmarkEnd w:id="1"/></w:p>'
          '<w:p><w:hyperlink w:anchor="_Toc1"><w:r><w:t>לכותרת</w:t></w:r>'
          '</w:hyperlink></w:p>',
          extra:
              '<w:styles><w:style w:type="paragraph" w:styleId="1">'
              '<w:name w:val="heading 1"/></w:style></w:styles>',
        ),
      );
      expect(out, contains('<h1 id="_Toc1">כותרת יעד</h1>'));
      expect(out, contains('<a href="#_Toc1">לכותרת</a>'));
    });

    test('קישור חיצוני (r:id) בלי קובץ יחסים נשאר טקסט לא-עטוף', () {
      // בדיאלקט הזה אין word/_rels/document.xml.rels — היעד אינו נפתר,
      // אך טקסט הקישור לא אובד (כמו הפורמטים האחרים לפני התיקון).
      final out = _convert(
        _wordMl2003(
          '<w:p><w:hyperlink r:id="rId9"><w:r><w:t>קישור</w:t></w:r>'
          '</w:hyperlink></w:p>',
        ),
      );
      expect(out, '<h1>ספר</h1>\nקישור');
      expect(out, isNot(contains('<a ')));
    });

    test('תמונה מ-w:binData לפי src של wordml://', () {
      final out = _convert(
        _wordMl2003(
          '<w:p><w:r><w:pict>'
          '<w:binData w:name="wordml://1.png">${base64Encode(_png)}'
          '</w:binData>'
          '<v:shape><v:imagedata src="wordml://1.png"/></v:shape>'
          '</w:pict></w:r></w:p>',
        ),
      );
      expect(out, contains('<img src="data:image/png;base64,'));
    });

    test('עיצוב run — אותן תגיות בדיוק כמו ב-OOXML', () {
      final out = _convert(
        _wordMl2003(
          '<w:p><w:r><w:rPr><w:b/><w:i/><w:color w:val="C00000"/>'
          '<w:highlight w:val="yellow"/></w:rPr><w:t>מעוצב</w:t></w:r></w:p>',
        ),
      );
      expect(
        out,
        contains(
          '<b><i><span style="background-color:yellow">'
          '<span style="color:#C00000">מעוצב</span></span></i></b>',
        ),
      );
    });

    test('תיבת טקסט עם תמונת רקע — המילוי מזוהה לפי src', () {
      final out = _convert(
        _wordMl2003(
          '<w:p><w:r><w:pict>'
          '<w:binData w:name="wordml://bg.png">${base64Encode(_png)}'
          '</w:binData>'
          '<v:shape><v:fill src="wordml://bg.png" type="frame"/>'
          '<v:textbox><w:txbxContent>'
          '<w:p><w:r><w:t>על הרקע</w:t></w:r></w:p>'
          '</w:txbxContent></v:textbox></v:shape>'
          '</w:pict></w:r></w:p>',
        ),
      );
      expect(out, contains('background-image: url(data:image/png;base64,'));
      expect(out, contains('על הרקע'));
    });

    test('w:vmerge באות קטנה מזוהה כמיזוג אנכי', () {
      // WordML 2003 כותב `w:vmerge`, בעוד OOXML כותב `w:vMerge`. השוואה
      // רגישת-רישיות איבדה את כל המיזוגים האנכיים בדיאלקט הזה.
      final out = _convert(
        _wordMl2003(
          '<w:tbl>'
          '<w:tr><w:tc><w:tcPr><w:vmerge w:val="restart"/></w:tcPr>'
          '<w:p><w:r><w:t>ממוזג</w:t></w:r></w:p></w:tc></w:tr>'
          '<w:tr><w:tc><w:tcPr><w:vmerge/></w:tcPr>'
          '<w:p><w:r><w:t>המשך</w:t></w:r></w:p></w:tc></w:tr>'
          '</w:tbl>',
        ),
      );
      expect(out, contains('rowspan="2"'));
      expect(out, isNot(contains('המשך')));
    });

    test('טבלה — כותרת, מיזוג אופקי ו-RTL כמו ב-OOXML', () {
      final out = _convert(
        _wordMl2003(
          '<w:tbl><w:tblPr><w:bidiVisual/></w:tblPr>'
          '<w:tr><w:trPr><w:tblHeader/></w:trPr>'
          '<w:tc><w:tcPr><w:gridSpan w:val="2"/>'
          '<w:shd w:fill="DDEBF7"/><w:vAlign w:val="center"/></w:tcPr>'
          '<w:p><w:r><w:t>כותרת</w:t></w:r></w:p></w:tc></w:tr></w:tbl>',
        ),
      );
      expect(out, contains('<table dir="rtl"'));
      expect(out, contains('<th'));
      expect(out, contains('colspan="2"'));
      expect(out, contains('background-color: #DDEBF7'));
      // ‏Word כותב `center`, אך ב-CSS הערך הוא `middle` — `center` מתעלמים
      // ממנו בשקט.
      expect(out, contains('vertical-align: middle'));
    });

    test('מסמך בלי w:body זורק CorruptedDocumentException', () {
      final bytes = Uint8List.fromList(
        utf8.encode(
          '<w:wordDocument xmlns:w="http://schemas.microsoft.com/office/word/'
          '2003/wordml"><w:docPr/></w:wordDocument>',
        ),
      );
      expect(
        () => _convert(bytes),
        throwsA(isA<CorruptedDocumentException>()),
      );
    });
  });
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/docx_to_otzaria.dart';

// ─── helpers ──────────────────────────────────────────────────────────────────

// Builds a minimal valid DOCX (ZIP) whose word/document.xml is the given bytes.
Uint8List _buildDocx(List<int> documentXmlBytes, {List<int>? footnotesXmlBytes}) {
  final encoder = ZipEncoder();
  final archive = Archive();
  archive.addFile(ArchiveFile(
    'word/document.xml',
    documentXmlBytes.length,
    documentXmlBytes,
  ));
  if (footnotesXmlBytes != null) {
    archive.addFile(ArchiveFile(
      'word/footnotes.xml',
      footnotesXmlBytes.length,
      footnotesXmlBytes,
    ));
  }
  return Uint8List.fromList(encoder.encode(archive));
}

// Builds document.xml bytes from a plain UTF-8 XML string.
List<int> _utf8Xml(String text) => utf8.encode(text);

// Builds document.xml bytes that declare UTF-8 in the header but embed
// Hebrew text in Windows-1255 encoding — the exact situation that triggered
// the original bug with בדיקה.docx.
List<int> _cp1255Xml(String asciiPrefix, List<int> hebrewCp1255Bytes,
    String asciiSuffix) {
  return [
    ...utf8.encode(asciiPrefix),
    ...hebrewCp1255Bytes,
    ...utf8.encode(asciiSuffix),
  ];
}

const _xmlNs =
    'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"';

String _simpleDocXml(String innerText) => '''
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

    test('ממיר DOCX עם עברית Windows-1255 (fallback) ומחזיר טקסט עברי תקין', () {
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
    });

    test('כותרת הספר מופיעה כ-h1 בתחילת הפלט', () {
      final docx = _buildDocx(_utf8Xml(_simpleDocXml('שלום')));
      final result = docxToText(docx, 'כותרת בדיקה');

      expect(result.trimLeft(), startsWith('<h1>כותרת בדיקה</h1>'));
    });

    test('פסקה ריקה לא נוספת לפלט', () {
      final xml = '''
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
      final xml = '''
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
      final xml = '''
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
      final documentXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document $_xmlNs>
  <w:body>
    <w:p>
      <w:r><w:t>פסקה</w:t></w:r>
      <w:r><w:footnoteReference w:id="1"/></w:r>
    </w:p>
  </w:body>
</w:document>''';

      final docx = _buildDocx(_utf8Xml(documentXml),
          footnotesXmlBytes: footnotesBytes);
      final result = docxToText(docx, 'בדיקה');

      expect(result, contains('הערה'));
    });

    test('הערת שוליים מופיעה אחרי הפסקה שמכילה אותה', () {
      final documentXml = '''
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

      final footnotesXml = '''
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

      expect(result, contains('<sup>1</sup>'));
      expect(result, contains('הערת שוליים'));
      // footnote div comes after the paragraph that references it
      final paraIdx = result.indexOf('טקסט');
      final noteIdx = result.indexOf('הערת שוליים');
      expect(noteIdx, greaterThan(paraIdx));
    });
  });
}

// מקבע את **הצימוד** בין פלט הממיר לגרסת הממיר.
//
// הרגרסיה שהבדיקה מונעת: תוקן באג, הפלט השתנה, וגרסת הממיר נשארה מאחור.
// מפתח-התוקף של המטמון כולל את הגרסה, ולכן כל ספר שנפתח פעם אחת ממשיך
// להגיש את הפלט **הבאגי** לצמיתות — גם אחרי שהקוד תוקן.
//
// שינוי מכוון בפלט מחייב שני עדכונים באותה עריכה: הטביעה כאן והגרסה בממיר.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/docx_to_otzaria.dart';
import 'package:otzaria/utils/file/document_format.dart';
import 'package:otzaria/utils/file/epub_to_otzaria.dart';
import 'package:otzaria/utils/file/html_to_otzaria.dart';
import 'package:otzaria/utils/file/legacy_word_properties.dart';
import 'package:otzaria/utils/file/legacy_word_to_otzaria.dart';
import 'package:otzaria/utils/file/markdown_to_otzaria.dart';
import 'package:otzaria/utils/file/odt_to_otzaria.dart';
import 'package:otzaria/utils/file/rtf_to_otzaria.dart';
import 'package:otzaria/utils/file/word_xml_to_otzaria.dart';
import 'package:otzaria/utils/text/inline_style.dart';

/// גרסת הממיר, והטביעה של הפלט שהיא מתארת. **לעדכן את שניהם יחד.**
/// ‎`ooxml`‎ ו-‎`word-xml`‎ חולקים טביעה — Flat OPC מגיע לאותו מנוע ומייצר פלט
/// זהה בייט-בבייט. אי-שוויון ביניהם הוא סימן שהמנוע הותקף מכיוון אחד בלבד.
const Map<String, ({int version, String fingerprint})> _pinned = {
  'ooxml': (version: 15, fingerprint: '1361c1a44610eac7'),
  'word-xml': (version: 1015, fingerprint: '1361c1a44610eac7'),
  'odt': (version: 7, fingerprint: 'e7114c864beedc1d'),
  'rtf': (version: 6, fingerprint: 'cfa322a43935a572'),
  'legacy-word': (version: 9, fingerprint: 'e39829bc7e2dd94f'),
  'epub': (version: 16, fingerprint: 'a999c6001cd8c4f4'),
  'markdown': (version: 8, fingerprint: 'e0ac8348b37de4b8'),
  'html': (version: 2, fingerprint: '022fd0030315b79f'),
};

/// `sha256` ולא `hashCode` — הטביעה חייבת להיות זהה בין הרצות ובין גרסאות
/// Dart, אחרת הבדיקה מתריעה על שינוי שלא היה.
String _fingerprint(String output) =>
    sha256.convert(utf8.encode(output)).toString().substring(0, 16);

Uint8List _utf8(String text) => Uint8List.fromList(utf8.encode(text));

Uint8List _zip(Map<String, String> entries) {
  final archive = Archive();
  entries.forEach((name, content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// מסמך דגימה שנוגע בכל שורה בחוזה ה-markup שיש לה ייצוג בפורמט.
const _ooxmlBody =
    '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>'
    '<w:bookmarkStart w:id="1" w:name="_Toc1"/>'
    '<w:r><w:t>כותרת</w:t></w:r>'
    '<w:bookmarkEnd w:id="1"/></w:p>'
    '<w:p><w:pPr><w:bidi/><w:jc w:val="end"/></w:pPr>'
    '<w:r><w:rPr><w:b/><w:i/><w:u w:val="double"/>'
    '<w:color w:val="C00000"/><w:highlight w:val="yellow"/></w:rPr>'
    '<w:t>מעוצב</w:t></w:r>'
    '<w:r><w:footnoteReference w:id="2"/></w:r></w:p>'
    '<w:p><w:r><w:rPr><w:vanish/></w:rPr><w:t>מוסתר</w:t></w:r></w:p>'
    // עטיפה שקופה: תוכנה חייב להישמר.
    '<w:customXml><w:p><w:r><w:t>בעטיפה</w:t></w:r></w:p></w:customXml>'
    // קישור פנימי לכותרת (תוכן-עניינים אוטומטי) וחיצוני, זה לצד זה בפסקה.
    '<w:p><w:hyperlink w:anchor="_Toc1"><w:r><w:t>לכותרת</w:t></w:r>'
    '</w:hyperlink> <w:hyperlink r:id="rId1"><w:r><w:t>לאתר</w:t></w:r>'
    '</w:hyperlink></w:p>'
    '<w:tbl><w:tr><w:trPr><w:tblHeader/></w:trPr>'
    '<w:tc><w:tcPr><w:gridSpan w:val="2"/>'
    '<w:shd w:fill="EEEEEE"/><w:vAlign w:val="center"/></w:tcPr>'
    '<w:p><w:r><w:t>תא</w:t></w:r></w:p></w:tc></w:tr>'
    // ‏vMerge המשך בלי תא פותח מעליו — תוכנו אינו נמחק.
    '<w:tr><w:tc><w:tcPr><w:vMerge/></w:tcPr>'
    '<w:p><w:r><w:t>המשך</w:t></w:r></w:p></w:tc></w:tr></w:tbl>';

/// document.xml.rels עם יחס hyperlink יחיד — היעד החיצוני של `rId1` לעיל.
const _ooxmlRels =
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
    'relationships"><Relationship Id="rId1" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/'
    'relationships/hyperlink" Target="https://otzaria.org" '
    'TargetMode="External"/></Relationships>';

/// הערת שוליים בת שתי פסקאות — גבול הפסקה חייב להיות רווח.
const _ooxmlFootnotes =
    '<w:footnotes xmlns:w="http://schemas.openxmlformats.org/'
    'wordprocessingml/2006/main"><w:footnote w:id="2">'
    '<w:p><w:r><w:t>שלום</w:t></w:r></w:p>'
    '<w:p><w:r><w:t>עולם</w:t></w:r></w:p></w:footnote></w:footnotes>';

String _wordDocument(String body) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/'
    '2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/'
    '2006/relationships"><w:body>$body</w:body></w:document>';

const _ooxmlStyles =
    '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/'
    '2006/main"><w:style w:type="paragraph" w:styleId="Heading1">'
    '<w:name w:val="heading 1"/></w:style></w:styles>';

Uint8List _sampleOoxml() => _zip({
  'word/document.xml': _wordDocument(_ooxmlBody),
  'word/styles.xml': _ooxmlStyles,
  'word/footnotes.xml': _ooxmlFootnotes,
  'word/_rels/document.xml.rels': _ooxmlRels,
});

Uint8List _sampleWordXml() => _utf8(
  '<?xml version="1.0" encoding="UTF-8"?>'
  '<pkg:package xmlns:pkg="http://schemas.microsoft.com/office/2006/'
  'xmlPackage">'
  '<pkg:part pkg:name="/word/document.xml" '
  'pkg:contentType="application/xml"><pkg:xmlData>'
  '${_wordDocument(_ooxmlBody).replaceFirst(RegExp(r'^<\?xml[^>]*\?>'), '')}'
  '</pkg:xmlData></pkg:part>'
  '<pkg:part pkg:name="/word/styles.xml" '
  'pkg:contentType="application/xml">'
  '<pkg:xmlData>$_ooxmlStyles</pkg:xmlData></pkg:part>'
  '<pkg:part pkg:name="/word/footnotes.xml" '
  'pkg:contentType="application/xml">'
  '<pkg:xmlData>$_ooxmlFootnotes</pkg:xmlData></pkg:part>'
  '<pkg:part pkg:name="/word/_rels/document.xml.rels" '
  'pkg:contentType="application/vnd.openxmlformats-package.'
  'relationships+xml"><pkg:xmlData>'
  '${_ooxmlRels.replaceFirst(RegExp(r'^<\?xml[^>]*\?>'), '')}'
  '</pkg:xmlData></pkg:part>'
  '</pkg:package>',
);

Uint8List _sampleOdt() => _zip({
  'META-INF/manifest.xml': '<manifest/>',
  'content.xml':
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<office:document-content '
      'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
      'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" '
      'xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" '
      'xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" '
      'xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0">'
      '<office:automatic-styles>'
      '<style:style style:name="T" style:family="text">'
      '<style:text-properties fo:font-weight="bold" '
      'style:text-underline-style="solid" '
      'fo:background-color="#ffff00"/></style:style>'
      '<style:style style:name="P" style:family="paragraph">'
      '<style:paragraph-properties fo:text-align="end" '
      'style:writing-mode="rl-tb"/></style:style>'
      '</office:automatic-styles>'
      '<office:body><office:text>'
      '<text:h text:outline-level="1">  כותרת  </text:h>'
      '<text:p text:style-name="P">'
      '<text:span text:style-name="T">אלף<text:s/></text:span>'
      '<text:span text:style-name="T">בית</text:span></text:p>'
      // כותרת רשימה אינה ממוספרת, והפריט שאחריה מתחיל ב-1.
      '<text:list><text:list-header><text:p>מבוא</text:p></text:list-header>'
      '<text:list-item><text:p>ראשון</text:p></text:list-item></text:list>'
      '</office:text></office:body></office:document-content>',
});

Uint8List _sampleRtf() => _utf8(
  r'{\rtf1\ansi{\colortbl;\red192\green0\blue0;\red255\green255\blue255;}'
  r'{\stylesheet{\s1 heading 1;}}'
  r'\pard\s1\outlinelevel0 כותרת\par'
  r'\pard\rtlpar\qr {\b\i\uldb\cf1 מעוצב\tab המשך}\par'
  r'{\v מוסתר}\par'
  r'א\emdash ב\par'
  r'{\*\shpinst{\sp{\sn fLine}{\sv 1}}{\shptxt בתיבה}}\par'
  // רקע תא לבן אינו נכתב.
  r'\trowd\clcbpat2\cellx100 תא\cell\row'
  '}',
);

Uint8List _sampleEpub() => _zip({
  'META-INF/container.xml':
      '<?xml version="1.0"?>'
      '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
      '<rootfiles><rootfile full-path="OEBPS/book.opf"/></rootfiles>'
      '</container>',
  'OEBPS/book.opf':
      '<?xml version="1.0"?>'
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
      '<manifest><item id="c1" href="c1.xhtml" '
      'media-type="application/xhtml+xml"/></manifest>'
      '<spine><itemref idref="c1"/></spine></package>',
  'OEBPS/c1.xhtml':
      '<?xml version="1.0"?>'
      '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
      '<h1>כותרת</h1><p><b>מודגש</b> ורגיל</p>'
      '</body></html>',
});

Uint8List _sampleMarkdown() => _utf8('# כותרת\n\n**מודגש** ורגיל\n');

/// מסמך HTML שנוגע בכל שורה בחוזה — כולל מה שחייב להימחק (סקריפט, מטפל
/// אירועים, `javascript:`, עיצוב שאינו נתמך) ומה שחייב להישמר לצדו.
Uint8List _sampleHtml() => _utf8(
  '<html><head><meta charset="utf-8"><script>alert(1)</script>'
  '<style>body{color:red}</style></head>'
  '<body>'
  '<h1>כותרת</h1>'
  '<p onclick="x()" style="text-align: center">'
  '<b>מודגש</b> ו<span style="color: #c00000">צבוע</span>'
  '<span style="background-color: yellow">מסומן</span></p>'
  '<p style="display:none">מוסתר</p>'
  '<p><span style="font-family: \'SBL Hebrew\', serif; font-size:130%; '
  'font-weight:600">מעוצב</span>'
  '<span style="transform:rotate(5deg); position:absolute">מתקדם</span></p>'
  '<p><a href="javascript:x()">חסום</a>'
  '<a href="https://otzaria.org">פתוח</a>'
  '<a href="book://ברכות#דף ב:">ספר</a>'
  '<a href="#יעד">פנימי</a></p>'
  '<p>מילה<sup class="footnote-marker">1</sup>'
  '<i class="footnote">גוף ההערה</i> המשך</p>'
  '<p><ruby>אנפין<rt>פנים</rt></ruby></p>'
  '<ol type="a"><li>ראשון<ul><li>מקונן</li></ul></li></ol>'
  '<ol reversed><li>שני</li><li>ראשון</li></ol>'
  '<table cellpadding="6"><caption>כיתוב</caption>'
  '<tr><th colspan="2" bgcolor="#eeeeee">תא</th></tr></table>'
  '<hr style="border-top:3px solid #8b0000;">'
  '<blockquote>ציטוט</blockquote>'
  '<details open><summary>הצג</summary>מוסתר-מתקפל</details>'
  '<img src="https://tracker.example/p.png">'
  '<div style="border:1px solid #8b0000; padding:10px">תיבה</div>'
  '<div id="יעד" dir="ltr"><p>English</p></div>'
  '</body></html>',
);

void main() {
  const title = 'ספר';

  final outputs = <String, String>{
    'ooxml': ooxmlWordToText(
      _sampleOoxml(),
      title,
      format: DocumentFormat.docx,
    ),
    'word-xml': wordXmlToText(_sampleWordXml(), title),
    'odt': odtToText(_sampleOdt(), title),
    'rtf': rtfToText(_sampleRtf(), title),
    // ל-Word הבינארי אין מסמך-דגימה זול (הוא דורש מכולת CFB שלמה); הצימוד
    // נשמר דרך שכבת המאפיינים, שהיא מה שמייצר את ה-markup שלו.
    'legacy-word': _legacyMarkupSample(),
    'epub': epubToText(_sampleEpub(), title),
    'markdown': markdownBytesToHtml(_sampleMarkdown(), title),
    'html': htmlToText(_sampleHtml(), title),
  };

  final versions = <String, int>{
    'ooxml': kOoxmlWordConverterVersion,
    'word-xml': kWordXmlConverterVersion,
    'odt': kOdtConverterVersion,
    'rtf': kRtfConverterVersion,
    'legacy-word': kLegacyWordConverterVersion,
    'epub': kEpubConverterVersion,
    'markdown': kMarkdownConverterVersion,
    'html': kHtmlConverterVersion,
  };

  for (final name in _pinned.keys) {
    test('$name — פלט וגרסה נעולים יחד', () {
      expect(
        _fingerprint(outputs[name]!),
        _pinned[name]!.fingerprint,
        reason:
            'הפלט של $name השתנה.\nהפלט בפועל:\n${outputs[name]}\n\n'
            'אם השינוי מכוון — עדכן כאן את הטביעה **וגם** העלה את גרסת '
            'הממיר. בלי העלאת הגרסה המטמון ימשיך להגיש את הפלט הישן לכל '
            'ספר שנפתח פעם אחת.',
      );
      expect(
        versions[name],
        _pinned[name]!.version,
        reason:
            'גרסת $name אינה תואמת לזו שנרשמה כאן לצד הטביעה. עדכן את שתיהן '
            'יחד.',
      );
    });
  }

  test('גרסת ה-XML נגזרת ממנוע ה-OOXML', () {
    // קבוע עצמאי היה נשאר מאחור בשקט בכל שינוי במנוע, והמטמון של ‎.xml‎ היה
    // מגיש פלט מיושן.
    expect(kWordXmlConverterVersion % 1000, kOoxmlWordConverterVersion);
  });
}

String _legacyMarkupSample() {
  const properties = LegacyCharacterProperties(
    bold: true,
    italic: true,
    underline: true,
    underlineKind: UnderlineKind.wavy,
    underlineThick: true,
    strike: true,
    doubleStrike: true,
    color: '#c00000',
    highlight: 'yellow',
    verticalAlign: 'super',
  );
  final tags = properties.tags;
  return '${tags.open}טקסט${tags.close}';
}

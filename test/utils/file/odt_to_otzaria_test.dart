import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/document_conversion_exceptions.dart';
import 'package:otzaria/utils/file/odt_to_otzaria.dart';

// ─── helpers ──────────────────────────────────────────────────────────────

const _ns =
    'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
    'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" '
    'xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" '
    'xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" '
    'xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" '
    'xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" '
    'xmlns:xlink="http://www.w3.org/1999/xlink"';

/// הזחת רמת-רשימה אחת: ארבעה NBSP. רווחים רגילים היו נבלעים ברינדור.
const String _indent = '    ';

/// PNG 1x1 — התוכן הקטן ביותר שהממיר מזהה כתמונה.
final Uint8List _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);
final String _tinyPngUri = 'data:image/png;base64,${base64Encode(_tinyPng)}';

String _contentXml(String body, {String automaticStyles = ''}) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<office:document-content $_ns>'
    '<office:automatic-styles>$automaticStyles</office:automatic-styles>'
    '<office:body><office:text>$body</office:text></office:body>'
    '</office:document-content>';

String _stylesXml(String styles) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<office:document-styles $_ns>'
    '<office:styles>$styles</office:styles>'
    '</office:document-styles>';

Uint8List _odt(
  String content, {
  String? styles,
  Map<String, Uint8List> pictures = const {},
  bool includeMimetype = true,
}) {
  final archive = Archive();
  void add(String name, List<int> bytes) =>
      archive.addFile(ArchiveFile(name, bytes.length, bytes));

  if (includeMimetype) {
    add('mimetype', utf8.encode('application/vnd.oasis.opendocument.text'));
  }
  add('META-INF/manifest.xml', utf8.encode('<manifest/>'));
  add('content.xml', utf8.encode(content));
  if (styles != null) add('styles.xml', utf8.encode(styles));
  pictures.forEach((name, bytes) => add('Pictures/$name', bytes));

  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String _convert(String body, {String? styles, String automaticStyles = ''}) =>
    odtToText(
      _odt(_contentXml(body, automaticStyles: automaticStyles), styles: styles),
      'ספר',
    );

void main() {
  group('טקסט ופסקאות', () {
    test('פסקאות עבריות מומרות שורה לשורה', () {
      final out = _convert(
        '<text:p>שורה ראשונה</text:p><text:p>שורה שנייה</text:p>',
      );
      expect(out, '<h1>ספר</h1>\nשורה ראשונה\nשורה שנייה');
    });

    test('הכותרת מוזרקת כ-h1 בשורה 0 ועוברת escape', () {
      final out = odtToText(_odt(_contentXml('<text:p>א</text:p>')), 'א<b>&');
      expect(out.split('\n').first, '<h1>א&lt;b&gt;&amp;</h1>');
    });

    test('פסקה ריקה אינה נוספת לפלט', () {
      final out = _convert('<text:p></text:p><text:p>תוכן</text:p>');
      expect(out, '<h1>ספר</h1>\nתוכן');
    });

    test('תווי HTML בתוכן עוברים escape', () {
      final out = _convert('<text:p>a &lt; b &amp; c</text:p>');
      expect(out, contains('a &lt; b &amp; c'));
    });

    test('מעבר שורה ורווחים מרובים נשמרים', () {
      final out = _convert(
        '<text:p>א<text:line-break/>ב<text:s text:c="3"/>ג</text:p>',
      );
      // `text:s` נפלט כ-NBSP: רווחים רגילים היו נבלעים ברינדור ה-HTML.
      expect(out, contains('א<br>ב   ג'));
    });
  });

  group('כותרות', () {
    test('text:h לפי outline-level', () {
      final out = _convert(
        '<text:h text:outline-level="1">פרק</text:h>'
        '<text:h text:outline-level="3">סעיף</text:h>',
      );
      expect(out, contains('<h1>פרק</h1>'));
      expect(out, contains('<h3>סעיף</h3>'));
    });

    test('רמה עמוקה מ-6 נחתכת ל-h6', () {
      final out = _convert('<text:h text:outline-level="9">עמוק</text:h>');
      expect(out, contains('<h6>עמוק</h6>'));
    });

    test('כותרת מזוהה לפי שם הסגנון כשאין outline-level', () {
      final out = _convert('<text:h text:style-name="Heading_20_2">כ</text:h>');
      expect(out, contains('<h2>כ</h2>'));
    });

    test('text:p עם סגנון כותרת (מסמך שהומר) מזוהה ככותרת', () {
      final out = _convert(
        '<text:p text:style-name="Heading_20_1">כותרת מפסקה</text:p>',
      );
      expect(out, contains('<h1>כותרת מפסקה</h1>'));
    });

    test('סגנון יורש מקבל את רמת האב', () {
      final out = _convert(
        '<text:p text:style-name="P7">יורשת</text:p>',
        styles: _stylesXml(
          '<style:style style:name="P7" style:family="paragraph" '
          'style:parent-style-name="Heading_20_3"/>',
        ),
      );
      expect(out, contains('<h3>יורשת</h3>'));
    });

    test('שרשרת ירושה מעגלית אינה תוקעת את ההמרה', () {
      final out = _convert(
        '<text:p text:style-name="A">מעגל</text:p>',
        styles: _stylesXml(
          '<style:style style:name="A" style:family="paragraph" '
          'style:parent-style-name="B"/>'
          '<style:style style:name="B" style:family="paragraph" '
          'style:parent-style-name="A"/>',
        ),
      );
      expect(out, '<h1>ספר</h1>\nמעגל');
    });

    test('סגנון שאינו כותרת נשאר פסקה רגילה', () {
      final out = _convert(
        '<text:p text:style-name="Standard">גוף</text:p>',
        styles: _stylesXml(
          '<style:style style:name="Standard" style:family="paragraph"/>',
        ),
      );
      expect(out, '<h1>ספר</h1>\nגוף');
    });
  });

  group('עיצוב', () {
    String withTextStyle(String properties, String body) => _convert(
      body,
      automaticStyles:
          '<style:style style:name="T1" style:family="text">'
          '<style:text-properties $properties/></style:style>',
    );

    test('מודגש → <b>', () {
      final out = withTextStyle(
        'fo:font-weight="bold"',
        '<text:p><text:span text:style-name="T1">חזק</text:span></text:p>',
      );
      expect(out, contains('<b>חזק</b>'));
    });

    test('נטוי → <i>', () {
      final out = withTextStyle(
        'fo:font-style="italic"',
        '<text:p><text:span text:style-name="T1">נטוי</text:span></text:p>',
      );
      expect(out, contains('<i>נטוי</i>'));
    });

    test('קו תחתי וקו חוצה', () {
      final underline = withTextStyle(
        'style:text-underline-style="solid"',
        '<text:p><text:span text:style-name="T1">קו</text:span></text:p>',
      );
      expect(underline, contains('<u>קו</u>'));

      final strike = withTextStyle(
        'style:text-line-through-style="solid"',
        '<text:p><text:span text:style-name="T1">חוצה</text:span></text:p>',
      );
      expect(strike, contains('<s>חוצה</s>'));
    });

    test('צבע שחור אינו נפלט כ-span', () {
      final out = withTextStyle(
        'fo:color="#000000"',
        '<text:p><text:span text:style-name="T1">רגיל</text:span></text:p>',
      );
      expect(out, isNot(contains('<span')));
    });

    test('צבע אמיתי נשמר בדיוק כמו בממיר Word (§24)', () {
      final out = withTextStyle(
        'fo:color="#ff0000"',
        '<text:p><text:span text:style-name="T1">אדום</text:span></text:p>',
      );
      expect(out, contains('<span style="color:#ff0000">אדום</span>'));
    });

    test('span מקונן מצטבר על עיצוב האב', () {
      final out = _convert(
        '<text:p><text:span text:style-name="T1">'
        '<text:span text:style-name="T2">שניהם</text:span>'
        '</text:span></text:p>',
        automaticStyles:
            '<style:style style:name="T1" style:family="text">'
            '<style:text-properties fo:font-weight="bold"/></style:style>'
            '<style:style style:name="T2" style:family="text">'
            '<style:text-properties fo:font-style="italic"/></style:style>',
      );
      expect(out, contains('<b><i>שניהם</i></b>'));
    });

    test('יישור מפורש עוטף ב-div', () {
      final out = _convert(
        '<text:p text:style-name="P1">ממורכז</text:p>',
        automaticStyles:
            '<style:style style:name="P1" style:family="paragraph">'
            '<style:paragraph-properties fo:text-align="center"/>'
            '</style:style>',
      );
      expect(out, contains('<div style="text-align: center;">ממורכז</div>'));
    });

    test('סגנון לא מוכר אינו מוחק טקסט (§45)', () {
      final out = _convert('<text:p text:style-name="לא-קיים">שריד</text:p>');
      expect(out, contains('שריד'));
    });
  });

  group('קישורים', () {
    test('text:a הופך ל-<a href>', () {
      final out = _convert(
        '<text:p><text:a xlink:href="https://a.example">קישור</text:a>'
        '</text:p>',
      );
      expect(out, contains('<a href="https://a.example">קישור</a>'));
    });

    test('קישור ישיר לספר באוצריא נשמר (issue #5714)', () {
      final out = _convert(
        '<text:p><text:a xlink:href="otzaria://open/book/12?index=2">ברכות'
        '</text:a><text:a xlink:href="otzaria://open/settings">הגדרות'
        '</text:a></text:p>',
      );
      expect(
        out,
        contains('<a href="otzaria://open/book/12?index=2">ברכות</a>'),
      );
      expect(out, isNot(contains('href="otzaria://open/settings"')));
      expect(out, contains('הגדרות'));
    });

    test('קישור בלי href משאיר את הטקסט', () {
      final out = _convert('<text:p><text:a>סתם</text:a></text:p>');
      expect(out, contains('סתם'));
      expect(out, isNot(contains('<a ')));
    });
  });

  group('רשימות', () {
    String listStyles(String levels) =>
        '<text:list-style style:name="L1">$levels</text:list-style>';

    String numberLevel(
      int level, {
      String format = '1',
      String suffix = '.',
      String prefix = '',
      int displayLevels = 1,
      int start = 1,
    }) =>
        '<text:list-level-style-number text:level="$level" '
        'style:num-format="$format" style:num-suffix="$suffix" '
        'style:num-prefix="$prefix" text:display-levels="$displayLevels" '
        'text:start-value="$start"/>';

    String item(String text) =>
        '<text:list-item><text:p>$text</text:p>'
        '</text:list-item>';

    test('מספור רץ 1. 2. 3.', () {
      final out = _convert(
        '<text:list text:style-name="L1">'
        '${item('א')}${item('ב')}${item('ג')}</text:list>',
        automaticStyles: listStyles(numberLevel(1)),
      );
      expect(out, contains('1. א'));
      expect(out, contains('2. ב'));
      expect(out, contains('3. ג'));
    });

    test('מספור עברי', () {
      final out = _convert(
        '<text:list text:style-name="L1">${item('ראשון')}${item('שני')}'
        '</text:list>',
        automaticStyles: listStyles(numberLevel(1, format: 'א')),
      );
      expect(out, contains('א. ראשון'));
      expect(out, contains('ב. שני'));
    });

    test('אותיות לטיניות ורומיות', () {
      final letters = _convert(
        '<text:list text:style-name="L1">${item('x')}${item('y')}</text:list>',
        automaticStyles: listStyles(numberLevel(1, format: 'a')),
      );
      expect(letters, contains('a. x'));
      expect(letters, contains('b. y'));

      final roman = _convert(
        '<text:list text:style-name="L1">${item('x')}${item('y')}</text:list>',
        automaticStyles: listStyles(numberLevel(1, format: 'I')),
      );
      expect(roman, contains('I. x'));
      expect(roman, contains('II. y'));
    });

    test('רשימה מקוננת מוזחת וממשיכה את המונה', () {
      final out = _convert(
        '<text:list text:style-name="L1">'
        '${item('ראשי')}'
        '<text:list-item><text:list>${item('משנה')}</text:list></text:list-item>'
        '${item('ראשי שני')}'
        '</text:list>',
        automaticStyles: listStyles('${numberLevel(1)}${numberLevel(2)}'),
      );
      expect(out, contains('1. ראשי'));
      // ההזחה היא NBSP ולא רווח רגיל — רווחים נבלעים ברינדור.
      expect(out, contains('${_indent}1. משנה'));
      expect(out, contains('2. ראשי שני'));
    });

    test('display-levels מצרף את מוני האב', () {
      final out = _convert(
        '<text:list text:style-name="L1">'
        '${item('ראשי')}'
        '<text:list-item><text:list>${item('משנה')}</text:list></text:list-item>'
        '</text:list>',
        automaticStyles: listStyles(
          '${numberLevel(1)}${numberLevel(2, displayLevels: 2)}',
        ),
      );
      expect(out, contains('${_indent}1.1. משנה'));
    });

    test('ערך התחלה מותאם', () {
      final out = _convert(
        '<text:list text:style-name="L1">${item('א')}${item('ב')}</text:list>',
        automaticStyles: listStyles(numberLevel(1, start: 5)),
      );
      expect(out, contains('5. א'));
      expect(out, contains('6. ב'));
    });

    test('תבליט נשאר תבליט', () {
      final out = _convert(
        '<text:list text:style-name="L1">${item('פריט')}</text:list>',
        automaticStyles: listStyles(
          '<text:list-level-style-bullet text:level="1" '
          'text:bullet-char="•"/>',
        ),
      );
      expect(out, contains('• פריט'));
    });

    test('רשימה בלי סגנון נופלת לתבליט ולא קורסת', () {
      final out = _convert('<text:list>${item('ללא סגנון')}</text:list>');
      expect(out, contains('• ללא סגנון'));
    });
  });

  group('טבלאות', () {
    String cell(String text, {String attributes = ''}) =>
        '<table:table-cell $attributes><text:p>$text</text:p>'
        '</table:table-cell>';

    test('טבלה בסיסית', () {
      final out = _convert(
        '<table:table>'
        '<table:table-row>${cell('א1')}${cell('ב1')}</table:table-row>'
        '<table:table-row>${cell('א2')}${cell('ב2')}</table:table-row>'
        '</table:table>',
      );
      expect(out, contains('<table'));
      expect(out, contains('א1'));
      expect(out, contains('ב2'));
      expect('<tr>'.allMatches(out).length, 2);
    });

    test('מיזוג אופקי ואנכי', () {
      final out = _convert(
        '<table:table><table:table-row>'
        '${cell('רחב', attributes: 'table:number-columns-spanned="2"')}'
        '${cell('גבוה', attributes: 'table:number-rows-spanned="3"')}'
        '</table:table-row></table:table>',
      );
      expect(out, contains('colspan="2"'));
      expect(out, contains('rowspan="3"'));
    });

    test('תא מכוסה אינו נפלט', () {
      final out = _convert(
        '<table:table><table:table-row>${cell('גלוי')}'
        '<table:covered-table-cell/></table:table-row></table:table>',
      );
      expect('<td'.allMatches(out).length, 1);
    });

    test('טבלה מקוננת נשמרת', () {
      final out = _convert(
        '<table:table><table:table-row><table:table-cell>'
        '<text:p>חיצוני</text:p>'
        '<table:table><table:table-row>${cell('פנימי')}</table:table-row>'
        '</table:table>'
        '</table:table-cell></table:table-row></table:table>',
      );
      expect(out, contains('חיצוני'));
      expect(out, contains('פנימי'));
      expect('<table'.allMatches(out).length, 2);
    });

    test('שורות כותרת נכללות', () {
      final out = _convert(
        '<table:table><table:table-header-rows>'
        '<table:table-row>${cell('כותרת')}</table:table-row>'
        '</table:table-header-rows>'
        '<table:table-row>${cell('גוף')}</table:table-row></table:table>',
      );
      expect(out, contains('כותרת'));
      expect(out, contains('גוף'));
    });

    test('טבלה ריקה אינה יוצרת <table> ריק', () {
      final out = _convert('<table:table></table:table>');
      expect(out, '<h1>ספר</h1>');
    });

    test('התוכן אינו זולג לזרם הרגיל', () {
      final out = _convert(
        '<text:p>לפני</text:p>'
        '<table:table><table:table-row>${cell('בתוך')}</table:table-row>'
        '</table:table>'
        '<text:p>אחרי</text:p>',
      );
      final lines = out.split('\n');
      expect(lines[1], 'לפני');
      expect(lines[2], startsWith('<table'));
      expect(lines[3], 'אחרי');
    });
  });

  group('הערות שוליים', () {
    test('נפלטות בתבנית המשותפת של אוצריא (§46)', () {
      final out = _convert(
        '<text:p>טקסט<text:note text:note-class="footnote">'
        '<text:note-citation>1</text:note-citation>'
        '<text:note-body><text:p>גוף ההערה</text:p></text:note-body>'
        '</text:note></text:p>',
      );
      expect(
        out,
        contains(
          'טקסט<sup class="footnote-marker">1</sup>'
          '<i class="footnote">גוף ההערה</i>',
        ),
      );
    });

    test('המונה רץ על פני כמה הערות', () {
      String note(String body) =>
          '<text:note><text:note-body><text:p>$body</text:p>'
          '</text:note-body></text:note>';
      final out = _convert(
        '<text:p>א${note('ראשונה')}</text:p>'
        '<text:p>ב${note('שנייה')}</text:p>',
      );
      expect(out, contains('<sup class="footnote-marker">1</sup>'));
      expect(out, contains('<sup class="footnote-marker">2</sup>'));
    });

    test('הערה בלי גוף אינה מייצרת סימון', () {
      final out = _convert('<text:p>טקסט<text:note/></text:p>');
      expect(out, '<h1>ספר</h1>\nטקסט');
    });
  });

  group('תמונות', () {
    String frame(String href) =>
        '<text:p><draw:frame><draw:image xlink:href="$href"/>'
        '</draw:frame></text:p>';

    test('תמונה מוטמעת כ-data URI (offline)', () {
      final out = odtToText(
        _odt(
          _contentXml(frame('Pictures/a.png')),
          pictures: {'a.png': _tinyPng},
        ),
        'ספר',
      );
      expect(out, contains('<img src="$_tinyPngUri"'));
      expect(out, isNot(contains('http')));
    });

    test('נתיב יחסי עם ./ נפתר', () {
      final out = odtToText(
        _odt(
          _contentXml(frame('./Pictures/a.png')),
          pictures: {'a.png': _tinyPng},
        ),
        'ספר',
      );
      expect(out, contains('<img src="$_tinyPngUri"'));
    });

    test('תמונה חסרה אינה מפילה את ההמרה', () {
      final out = odtToText(_odt(_contentXml(frame('Pictures/חסר.png'))), 'ס');
      expect(out, '<h1>ס</h1>');
    });

    test('embedImages=false משאיר תג ריק ושומר על מספר השורות', () {
      final bytes = _odt(
        _contentXml('<text:p>לפני</text:p>${frame('Pictures/a.png')}'),
        pictures: {'a.png': _tinyPng},
      );
      final full = odtToText(bytes, 'ספר');
      final lean = odtToText(bytes, 'ספר', embedImages: false);

      expect(lean, isNot(contains('base64')));
      expect(lean, contains('<img src=""'));
      expect(lean.split('\n').length, full.split('\n').length);
    });
  });

  group('עמידות', () {
    // פלט "כותרת בלבד" נראה כמו ספר תקין וריק: הוא נשמר במטמון, מאונדקס,
    // ומסמן כל הערה אישית שמעבר לשורה 1 כחסרה — לצמיתות.
    test('content.xml פגום זורק חריגה מוקלדת', () {
      final bytes = _odt('<לא xml תקין');
      expect(
        () => odtToText(bytes, 'פגום'),
        throwsA(isA<CorruptedDocumentException>()),
      );
    });

    test('חבילה בלי content.xml זורקת חריגה מוקלדת', () {
      final archive = Archive()
        ..addFile(ArchiveFile('mimetype', 4, utf8.encode('טקסט')));
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
      expect(
        () => odtToText(bytes, 'ריק'),
        throwsA(isA<CorruptedDocumentException>()),
      );
    });

    test('קובץ שאינו ZIP זורק חריגה מוקלדת', () {
      expect(
        () => odtToText(Uint8List.fromList(utf8.encode('לא ZIP')), 'ס'),
        throwsA(isA<CorruptedDocumentException>()),
      );
    });

    test('styles.xml פגום אינו מוחק תוכן', () {
      final bytes = _odt(
        _contentXml('<text:p text:style-name="P1">שריד</text:p>'),
        styles: '<לא xml',
      );
      expect(odtToText(bytes, 'ס'), contains('שריד'));
    });

    test('אלמנט לא מוכר שומר את הטקסט שבתוכו', () {
      final out = _convert(
        '<text:p>לפני <text:unknown-field>ערך</text:unknown-field> אחרי'
        '</text:p>',
      );
      expect(out, contains('לפני ערך אחרי'));
    });

    test('סימני עמוד וסימניות אינם מייצרים פלט', () {
      final out = _convert(
        '<text:p><text:bookmark text:name="b"/>טקסט'
        '<text:soft-page-break/></text:p>',
      );
      expect(out, '<h1>ספר</h1>\nטקסט');
    });

    test('המרה חוזרת דטרמיניסטית', () {
      final bytes = _odt(
        _contentXml(
          '<text:h text:outline-level="1">כ</text:h><text:p>ג</text:p>',
        ),
      );
      expect(odtToText(bytes, 'ס'), odtToText(bytes, 'ס'));
    });
  });

  group('מבנה מקונן', () {
    test('text:section שקוף — התוכן שבו נשמר', () {
      final out = _convert(
        '<text:section><text:p>בתוך מקטע</text:p></text:section>',
      );
      expect(out, contains('בתוך מקטע'));
    });
  });

  group('טקסט מוסתר', () {
    test('text:display="none" מדלג על הטקסט', () {
      final out = _convert(
        '<text:p>גלוי<text:span text:style-name="H">מוסתר</text:span>עוד'
        '</text:p>',
        automaticStyles:
            '<style:style style:name="H" style:family="text">'
            '<style:text-properties text:display="none"/></style:style>',
      );
      expect(out, contains('גלוי'));
      expect(out, contains('עוד'));
      expect(out, isNot(contains('מוסתר')));
    });
  });

  group('וריאנטי עיצוב — חוזה markup משותף עם Word (§24)', () {
    String withStyle(String textProperties, {String text = 'טקסט'}) => _convert(
      '<text:p><text:span text:style-name="T">$text</text:span></text:p>',
      automaticStyles:
          '<style:style style:name="T" style:family="text">'
          '<style:text-properties $textProperties/></style:style>',
    );

    test('קו תחתי כפול', () {
      expect(
        withStyle(
          'style:text-underline-style="solid" '
          'style:text-underline-type="double"',
        ),
        contains('underline double'),
      );
    });

    test('קו תחתי מנוקד/מקווקו/גלי', () {
      expect(
        withStyle('style:text-underline-style="dotted"'),
        contains('underline dotted'),
      );
      expect(
        withStyle('style:text-underline-style="dash"'),
        contains('underline dashed'),
      );
      expect(
        withStyle('style:text-underline-style="wave"'),
        contains('underline wavy'),
      );
    });

    test('קו תחתי עבה וצבעוני', () {
      expect(
        withStyle(
          'style:text-underline-style="solid" '
          'style:text-underline-width="bold"',
        ),
        contains('text-decoration-thickness: 200%'),
      );
      expect(
        withStyle(
          'style:text-underline-style="solid" '
          'style:text-underline-color="#c00000"',
        ),
        contains('text-decoration-color: #c00000'),
      );
    });

    test('קו תחתי פשוט נשאר <u>', () {
      expect(
        withStyle('style:text-underline-style="solid"'),
        contains('<u>טקסט</u>'),
      );
    });

    test('קו חוצה כפול נבדל מיחיד', () {
      expect(
        withStyle('style:text-line-through-style="solid"'),
        contains('<s>טקסט</s>'),
      );
      expect(
        withStyle(
          'style:text-line-through-style="solid" '
          'style:text-line-through-type="double"',
        ),
        contains('line-through double'),
      );
    });

    test('מרקר — אותו תג בדיוק כמו ב-Word', () {
      expect(
        withStyle('fo:background-color="#ffff00"'),
        contains('<span style="background-color:#ffff00">טקסט</span>'),
      );
    });
  });

  group('רצף עיצוב אחיד', () {
    const underlineStyle =
        '<style:style style:name="T" style:family="text">'
        '<style:text-properties style:text-underline-style="solid"/>'
        '</style:style>';

    test('רווח בתוך span נושא את עיצובו — הקו התחתי אינו נקטע', () {
      // ODF מייצג רווח כ-`text:s`; פליטתו חשופה קטעה את הקו בין המילים.
      final out = _convert(
        '<text:p><text:span text:style-name="T">אלף<text:s/></text:span>'
        '<text:span text:style-name="T">בית</text:span></text:p>',
        automaticStyles: underlineStyle,
      );
      expect(out, contains('<u>אלף בית</u>'));
    });

    test('spans סמוכים בעלי אותו סגנון ממוזגים לתג אחד', () {
      final out = _convert(
        '<text:p><text:span text:style-name="T">אלף</text:span>'
        '<text:span text:style-name="T">בית</text:span></text:p>',
        automaticStyles: underlineStyle,
      );
      expect('<u>'.allMatches(out).length, 1);
    });

    test('שינוי עיצוב בין spans עדיין מפצל', () {
      final out = _convert(
        '<text:p><text:span text:style-name="T">אלף</text:span>'
        '<text:span text:style-name="T2">בית</text:span></text:p>',
        automaticStyles:
            '$underlineStyle'
            '<style:style style:name="T2" style:family="text">'
            '<style:text-properties fo:font-weight="bold"/></style:style>',
      );
      expect(out, contains('<u>אלף</u><b>בית</b>'));
    });

    test('טאב נושא אף הוא את עיצוב ה-run', () {
      final out = _convert(
        '<text:p><text:span text:style-name="T">א<text:tab/>ב</text:span>'
        '</text:p>',
        automaticStyles: underlineStyle,
      );
      expect('<u>'.allMatches(out).length, 1);
    });
  });

  group('יישור לוגי', () {
    String withParagraphStyle(String properties) => _convert(
      '<text:p text:style-name="P">טקסט</text:p>',
      automaticStyles:
          '<style:style style:name="P" style:family="paragraph">'
          '<style:paragraph-properties $properties/></style:style>',
    );

    test('בכיוון ברירת המחדל (lr-tb): end→ימין, start→שמאל', () {
      expect(
        withParagraphStyle('fo:text-align="end"'),
        contains('<div style="text-align: right;">'),
      );
      expect(
        withParagraphStyle('fo:text-align="start"'),
        contains('<div style="text-align: left;">'),
      );
    });

    test('ב-rl-tb היישור הלוגי מדולג — הפירוש חלוק בין מפיקי המסמכים', () {
      // מסמך שהומר מ-Word נושא `end` שנועד להיות ימין, בעוד שלפי תקן ODF
      // הוא שמאל. עדיף להשאיר את ברירת המחדל של הקורא.
      expect(
        withParagraphStyle('fo:text-align="end" style:writing-mode="rl-tb"'),
        isNot(contains('<div')),
      );
      expect(
        withParagraphStyle('fo:text-align="start" style:writing-mode="rl-tb"'),
        isNot(contains('<div')),
      );
    });

    test('יישור פיזי מפורש נשמר גם ב-rl-tb', () {
      expect(
        withParagraphStyle('fo:text-align="left" style:writing-mode="rl-tb"'),
        contains('<div style="text-align: left;">'),
      );
    });

    test('justify אינו נעטף', () {
      expect(
        withParagraphStyle('fo:text-align="justify"'),
        isNot(contains('<div')),
      );
    });
  });

  group('מאפייני טבלה', () {
    test('table:table-header-rows → <th>', () {
      final out = _convert(
        '<table:table><table:table-header-rows><table:table-row>'
        '<table:table-cell><text:p>כותרת</text:p></table:table-cell>'
        '</table:table-row></table:table-header-rows>'
        '<table:table-row><table:table-cell><text:p>תא</text:p>'
        '</table:table-cell></table:table-row></table:table>',
      );
      expect(out, contains('<th'));
      expect(out, contains('<td'));
    });

    test('רקע התא ויישור אנכי מגיעים מסגנון התא', () {
      final out = _convert(
        '<table:table><table:table-row>'
        '<table:table-cell table:style-name="C"><text:p>תא</text:p>'
        '</table:table-cell></table:table-row></table:table>',
        automaticStyles:
            '<style:style style:name="C" style:family="table-cell">'
            '<style:table-cell-properties fo:background-color="#ddebf7" '
            'style:vertical-align="middle"/></style:style>',
      );
      expect(out, contains('background-color: #ddebf7'));
      expect(out, contains('vertical-align: middle'));
    });

    test('רקע לבן ושקוף אינם נכתבים', () {
      final out = _convert(
        '<table:table><table:table-row>'
        '<table:table-cell table:style-name="C"><text:p>תא</text:p>'
        '</table:table-cell></table:table-row></table:table>',
        automaticStyles:
            '<style:style style:name="C" style:family="table-cell">'
            '<style:table-cell-properties fo:background-color="transparent"/>'
            '</style:style>',
      );
      expect(out, isNot(contains('background-color')));
    });

    test('טבלה בכיוון rl-tb מסומנת dir="rtl"', () {
      final out = _convert(
        '<table:table table:style-name="Tb"><table:table-row>'
        '<table:table-cell><text:p>תא</text:p></table:table-cell>'
        '</table:table-row></table:table>',
        automaticStyles:
            '<style:style style:name="Tb" style:family="table">'
            '<style:table-properties style:writing-mode="rl-tb"/>'
            '</style:style>',
      );
      expect(out, contains('<table dir="rtl"'));
    });
  });

  group('מסגרות', () {
    test('מסגרת בלי גבול אינה מציירת תיבה — היא פריסה בלבד', () {
      final out = _convert(
        '<text:p><draw:frame draw:style-name="F"><draw:text-box>'
        '<text:p>בפנים</text:p></draw:text-box></draw:frame></text:p>',
        automaticStyles:
            '<style:style style:name="F" style:family="graphic">'
            '<style:graphic-properties draw:stroke="none" draw:fill="none"/>'
            '</style:style>',
      );
      expect(out, contains('בפנים'));
      expect(out, isNot(contains('border: 1px solid #999; padding: 8px')));
    });

    test('מסגרת עם גבול נעטפת ב-div של חוזה ה-markup', () {
      final out = _convert(
        '<text:p><draw:frame draw:style-name="F"><draw:text-box>'
        '<text:p>בתיבה</text:p></draw:text-box></draw:frame></text:p>',
        automaticStyles:
            '<style:style style:name="F" style:family="graphic">'
            '<style:graphic-properties draw:stroke="solid"/></style:style>',
      );
      expect(out, contains('border: 1px solid #999; padding: 8px'));
      expect(out, contains('בתיבה'));
    });

    test('מסגרת עם מילוי-תמונה מקבלת רקע', () {
      final out = odtToText(
        _odt(
          _contentXml(
            '<text:p><draw:frame draw:style-name="F"><draw:text-box>'
            '<text:p>על הרקע</text:p></draw:text-box></draw:frame></text:p>',
            automaticStyles:
                '<style:style style:name="F" style:family="graphic">'
                '<style:graphic-properties draw:fill="bitmap" '
                'draw:fill-image-name="bg"/></style:style>'
                '<draw:fill-image draw:name="bg" '
                'xlink:href="Pictures/bg.png"/>',
          ),
          pictures: {'bg.png': _tinyPng},
        ),
        'ספר',
      );
      expect(out, contains('background-image: url($_tinyPngUri)'));
      expect(out, contains('על הרקע'));
    });
  });
  // issue #1239: פורמט מספור ההערות יושב ב-`text:notes-configuration`.
  group('פורמט מספור הערות', () {
    String note(String body) =>
        '<text:note text:note-class="footnote">'
        '<text:note-body><text:p>$body</text:p></text:note-body>'
        '</text:note>';

    String notesConfig(String numFormat) =>
        '<text:notes-configuration text:note-class="footnote" '
        'style:num-format="$numFormat"/>';

    test('בלי הגדרה — מספור בספרות', () {
      final out = _convert('<text:p>א${note('הערה')}</text:p>');

      expect(out, contains('<sup class="footnote-marker">1</sup>'));
    });

    test('num-format עברי — מספור באותיות', () {
      final out = _convert(
        '<text:p>א${note('ראשונה')} ב${note('שנייה')}</text:p>',
        styles: _stylesXml(notesConfig('א')),
      );

      expect(out, contains('<sup class="footnote-marker">א</sup>'));
      expect(out, contains('<sup class="footnote-marker">ב</sup>'));
      expect(out, isNot(contains('>1</sup>')));
    });

    test('num-format לטיני', () {
      final out = _convert(
        '<text:p>א${note('הערה')}</text:p>',
        styles: _stylesXml(notesConfig('A')),
      );

      expect(out, contains('<sup class="footnote-marker">A</sup>'));
    });

    // num-format ריק מבטל מספור, והסימון הריק היה מנתק את גוף ההערה מהעוגן.
    test('num-format ריק חוזר לספרות', () {
      final out = _convert(
        '<text:p>א${note('הערה')}</text:p>',
        styles: _stylesXml(notesConfig('')),
      );

      expect(out, contains('<sup class="footnote-marker">1</sup>'));
    });
  });
}

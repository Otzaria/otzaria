import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/epub_to_otzaria.dart';

// ─── helpers ──────────────────────────────────────────────────────────────────

const _containerXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0"
    xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf"
        media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''';

/// בונה EPUB מינימלי תקין: container.xml, OPF עם manifest/spine, ופרקים.
Uint8List _buildEpub({
  required Map<String, String> chapters,
  List<String>? spineOrder,
  Map<String, List<int>>? binaryFiles,
  String? extraManifest,
  String? extraSpine,
}) {
  final order = spineOrder ?? chapters.keys.toList();

  final manifestItems = StringBuffer();
  var i = 0;
  for (final name in chapters.keys) {
    manifestItems.writeln(
      '<item id="c$i" href="$name" media-type="application/xhtml+xml"/>',
    );
    i++;
  }
  if (extraManifest != null) manifestItems.writeln(extraManifest);

  final spineItems = StringBuffer();
  for (final name in order) {
    final idx = chapters.keys.toList().indexOf(name);
    spineItems.writeln('<itemref idref="c$idx"/>');
  }
  if (extraSpine != null) spineItems.writeln(extraSpine);

  final opf =
      '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0"
    unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">test-book</dc:identifier>
    <dc:title>ספר בדיקה</dc:title>
  </metadata>
  <manifest>
$manifestItems
  </manifest>
  <spine>
$spineItems
  </spine>
</package>''';

  final encoder = ZipEncoder();
  final archive = Archive();
  void addText(String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  addText('META-INF/container.xml', _containerXml);
  addText('OEBPS/content.opf', opf);
  for (final entry in chapters.entries) {
    addText('OEBPS/${entry.key}', entry.value);
  }
  for (final entry in (binaryFiles ?? const <String, List<int>>{}).entries) {
    archive.addFile(
      ArchiveFile('OEBPS/${entry.key}', entry.value.length, entry.value),
    );
  }
  return Uint8List.fromList(encoder.encode(archive));
}

String _xhtml(String body) =>
    '''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"
    xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>פרק</title></head>
<body>$body</body>
</html>''';

// ─── tests ────────────────────────────────────────────────────────────────────

void main() {
  group('epubToText - מבנה בסיסי', () {
    test('שורת הפתיחה היא h1 עם שם הספר', () {
      final epub = _buildEpub(
        chapters: {
          'ch1.xhtml': _xhtml('<p>שלום עולם</p>'),
        },
      );
      final result = epubToText(epub, 'ספר בדיקה');
      final lines = result.split('\n');

      expect(lines.first, '<h1>ספר בדיקה</h1>');
      expect(lines, contains('שלום עולם'));
    });

    test('פרקים מומרים לפי סדר ה-spine, לא לפי סדר הקבצים', () {
      final epub = _buildEpub(
        chapters: {
          'b.xhtml': _xhtml('<p>שני</p>'),
          'a.xhtml': _xhtml('<p>ראשון</p>'),
        },
        spineOrder: ['a.xhtml', 'b.xhtml'],
      );
      final result = epubToText(epub, 'ספר');

      expect(result.indexOf('ראשון'), lessThan(result.indexOf('שני')));
    });

    test('EPUB פגום (לא ZIP) מחזיר לפחות את הכותרת בלי לזרוק', () {
      final result = epubToText(Uint8List.fromList([1, 2, 3, 4]), 'ספר פגום');
      expect(result, '<h1>ספר פגום</h1>');
    });

    test('פריט spine עם linear="no" מדולג', () {
      final epub = _buildEpub(
        chapters: {
          'main.xhtml': _xhtml('<p>תוכן ראשי</p>'),
          'cover.xhtml': _xhtml('<p>עמוד שער</p>'),
        },
        spineOrder: ['main.xhtml'],
        extraSpine: '<itemref idref="c1" linear="no"/>',
      );
      final result = epubToText(epub, 'ספר');

      expect(result, contains('תוכן ראשי'));
      expect(result, isNot(contains('עמוד שער')));
    });

    test('מסמך הניווט (properties="nav") מדולג', () {
      final epub = _buildEpub(
        chapters: {
          'main.xhtml': _xhtml('<p>תוכן</p>'),
        },
        extraManifest:
            '<item id="nav" href="nav.xhtml" properties="nav" '
            'media-type="application/xhtml+xml"/>',
        extraSpine: '<itemref idref="nav"/>',
      );
      final result = epubToText(epub, 'ספר');
      expect(result, contains('תוכן'));
    });
  });

  group('epubToText - כותרות', () {
    test('כותרות מוסטות רמה אחת מטה (h1 בפרק → h2) לטובת תוכן העניינים', () {
      final epub = _buildEpub(
        chapters: {
          'ch1.xhtml': _xhtml('<h1>פרק א</h1><h2>סימן א</h2><p>גוף</p>'),
        },
      );
      final result = epubToText(epub, 'ספר');
      final lines = result.split('\n');

      expect(lines, contains('<h2>פרק א</h2>'));
      expect(lines, contains('<h3>סימן א</h3>'));
    });

    test('h6 בפרק נשאר h6 (clamp)', () {
      final epub = _buildEpub(
        chapters: {
          'ch1.xhtml': _xhtml('<h6>עמוק</h6>'),
        },
      );
      final result = epubToText(epub, 'ספר');
      expect(result, contains('<h6>עמוק</h6>'));
    });
  });

  group('epubToText - עיצוב inline', () {
    test('strong/em ממופים ל-b/i, ותגיות שאינן נתמכות נשמטות אך תוכנן נשמר', () {
      final epub = _buildEpub(
        chapters: {
          'ch1.xhtml': _xhtml(
            '<p><strong>מודגש</strong> <em>נטוי</em> <span class="x">רגיל</span></p>',
          ),
        },
      );
      final result = epubToText(epub, 'ספר');

      expect(result, contains('<b>מודגש</b>'));
      expect(result, contains('<i>נטוי</i>'));
      expect(result, contains('רגיל'));
      expect(result, isNot(contains('<span')));
    });

    test('תווי < > & בתוכן עוברים escape', () {
      final epub = _buildEpub(
        chapters: {
          'ch1.xhtml': _xhtml('<p>א &lt;ב&gt; &amp; ג</p>'),
        },
      );
      final result = epubToText(epub, 'ספר');
      expect(result, contains('א &lt;ב&gt; &amp; ג'));
    });

    test('קישור רגיל הופך לטקסט (בלי תגית a)', () {
      final epub = _buildEpub(
        chapters: {
          'ch1.xhtml': _xhtml(
            '<p>ראה <a href="http://x.com">כאן</a> בהמשך</p>',
          ),
        },
      );
      final result = epubToText(epub, 'ספר');

      expect(result, contains('ראה כאן בהמשך'));
      expect(result, isNot(contains('<a ')));
    });

    test('script/style אינם תוכן', () {
      final epub = _buildEpub(
        chapters: {
          'ch1.xhtml': _xhtml(
            '<p>תוכן</p><style>p { color: red; }</style>'
            '<script>alert(1)</script>',
          ),
        },
      );
      final result = epubToText(epub, 'ספר');

      expect(result, contains('תוכן'));
      expect(result, isNot(contains('color')));
      expect(result, isNot(contains('alert')));
    });
  });

  group('epubToText - רשימות וטבלאות', () {
    test('רשימה ממוספרת מרונדרת עם מספרים ותבליטים עם נקודה', () {
      final epub = _buildEpub(
        chapters: {
          'ch1.xhtml': _xhtml(
            '<ol><li>ראשון</li><li>שני</li></ol><ul><li>תבליט</li></ul>',
          ),
        },
      );
      final result = epubToText(epub, 'ספר');
      final lines = result.split('\n');

      expect(lines, contains('1. ראשון'));
      expect(lines, contains('2. שני'));
      expect(lines, contains('• תבליט'));
    });

    test('רשימה מקוננת מקבלת הזחה', () {
      final epub = _buildEpub(
        chapters: {
          'ch1.xhtml': _xhtml('<ol><li>אב<ol><li>בן</li></ol></li></ol>'),
        },
      );
      final result = epubToText(epub, 'ספר');
      final lines = result.split('\n');

      expect(lines, contains('1. אב'));
      expect(lines, contains('    1. בן'));
    });

    test('טבלה מקוננת מרונדרת בתוך התא ולא משוטחת לשורות הטבלה החיצונית', () {
      final epub = _buildEpub(
        chapters: {
          'ch1.xhtml': _xhtml(
            '<table>'
            '<tr><td>חיצוני<table><tr><td>פנימי</td></tr></table></td></tr>'
            '<tr><td>שורה שנייה</td></tr>'
            '</table>',
          ),
        },
      );
      final result = epubToText(epub, 'ספר');
      final tableLine = result
          .split('\n')
          .firstWhere((l) => l.startsWith('<table'), orElse: () => '');

      // הטבלה הפנימית שלמה בתוך התא, והתוכן שלה לא מוכפל.
      expect(tableLine, contains('פנימי'));
      expect(RegExp('פנימי').allMatches(tableLine).length, 1);
      // לטבלה החיצונית בדיוק 2 שורות ישירות + שורת הטבלה הפנימית = 3 <tr>.
      expect(RegExp('<tr>').allMatches(tableLine).length, 3);
    });

    test('ערכי colspan/rowspan לא-מספריים נדחים (מניעת הזרקת HTML)', () {
      final epub = _buildEpub(
        chapters: {
          'ch1.xhtml': _xhtml(
            '<table><tr>'
            "<td colspan='2&quot; onclick=&quot;evil()'>תא</td>"
            '<td rowspan="abc">שני</td>'
            '</tr></table>',
          ),
        },
      );
      final result = epubToText(epub, 'ספר');

      expect(result, isNot(contains('onclick')));
      expect(result, isNot(contains('evil')));
      expect(result, isNot(contains('rowspan')));
      expect(result, contains('תא'));
      expect(result, contains('שני'));
    });

    test('טבלה נשמרת כשורת פלט אחת עם colspan', () {
      final epub = _buildEpub(
        chapters: {
          'ch1.xhtml': _xhtml(
            '<table><tr><td colspan="2">רחב</td></tr>'
            '<tr><td>א</td><td>ב</td></tr></table>',
          ),
        },
      );
      final result = epubToText(epub, 'ספר');
      final tableLine = result
          .split('\n')
          .firstWhere((l) => l.startsWith('<table'), orElse: () => '');

      expect(tableLine, contains('colspan="2"'));
      expect(tableLine, contains('רחב'));
      expect(tableLine, contains('</table>'));
    });
  });

  group('epubToText - תמונות', () {
    test('תמונה מה-manifest מוטמעת כ-data URI', () {
      const pngBytes = [0x89, 0x50, 0x4E, 0x47]; // PNG header prefix
      final epub = _buildEpub(
        chapters: {
          'ch1.xhtml': _xhtml('<p><img src="img/pic.png" alt=""/></p>'),
        },
        binaryFiles: {'img/pic.png': pngBytes},
        extraManifest:
            '<item id="pic" href="img/pic.png" media-type="image/png"/>',
      );
      final result = epubToText(epub, 'ספר');

      expect(
        result,
        contains('data:image/png;base64,${base64Encode(pngBytes)}'),
      );
    });

    test('תמונה מעל תקרת הגודל אינה מוטמעת (מניעת ניפוח זיכרון/מטמון)', () {
      final hugeImage = List<int>.filled(4 * 1024 * 1024 + 1, 0x42);
      final epub = _buildEpub(
        chapters: {
          'ch1.xhtml': _xhtml('<p>לפני</p><img src="big.png"/><p>אחרי</p>'),
        },
        binaryFiles: {'big.png': hugeImage},
        extraManifest: '<item id="big" href="big.png" media-type="image/png"/>',
      );
      final result = epubToText(epub, 'ספר');

      expect(result, isNot(contains('<img')));
      expect(result, contains('לפני'));
      expect(result, contains('אחרי'));
    });

    test('תמונה עם כתובת חיצונית (http) אינה מוטמעת ואינה מפילה', () {
      final epub = _buildEpub(
        chapters: {
          'ch1.xhtml': _xhtml(
            '<p>טקסט</p><img src="https://example.com/pic.png"/>',
          ),
        },
      );
      final result = epubToText(epub, 'ספר');

      expect(result, isNot(contains('<img')));
      expect(result, contains('טקסט'));
    });

    test('תמונה חסרה בארכיון לא מפילה את ההמרה', () {
      final epub = _buildEpub(
        chapters: {
          'ch1.xhtml': _xhtml('<p>לפני</p><img src="missing.png"/><p>אחרי</p>'),
        },
      );
      final result = epubToText(epub, 'ספר');

      expect(result, contains('לפני'));
      expect(result, contains('אחרי'));
      expect(result, isNot(contains('<img')));
    });
  });

  group('epubToText - הערות שוליים', () {
    test('הערה סמנטית (epub:type) מוזרקת בפורמט ההערות של אוצריא', () {
      final epub = _buildEpub(
        chapters: {
          'ch1.xhtml': _xhtml(
            '<p>גוף<a epub:type="noteref" href="#fn1">1</a> המשך</p>'
            '<aside epub:type="footnote" id="fn1"><p>תוכן ההערה</p></aside>',
          ),
        },
      );
      final result = epubToText(epub, 'ספר');

      expect(result, contains('<sup class="footnote-marker">1</sup>'));
      expect(result, contains('<i class="footnote">תוכן ההערה</i>'));
      // גוף ההערה אינו מופיע גם כפסקה נפרדת.
      expect(RegExp('תוכן ההערה').allMatches(result).length, 1);
    });

    test('הערה מבוססת-קישור (בלי epub:type בכלל): סמן מספרי + דיכוי היעד', () {
      final epub = _buildEpub(
        chapters: {
          'ch1.xhtml': _xhtml(
            '<p>גוף הטקסט<a href="#fn1">1</a> ממשיך כאן.</p>'
            '<p id="fn1">1. זה גוף ההערה <a href="#ref1">↩</a></p>',
          ),
        },
      );
      final result = epubToText(epub, 'ספר');

      expect(result, contains('<sup class="footnote-marker">1</sup>'));
      // הסמן הכפול ("1.") וקישור-החזרה (↩) הוסרו מגוף ההערה.
      expect(result, contains('<i class="footnote">זה גוף ההערה</i>'));
      // היעד לא מופיע גם כפסקה נפרדת.
      expect(RegExp('זה גוף ההערה').allMatches(result).length, 1);
      expect(result, isNot(contains('↩')));
    });

    test('הערה בקובץ נפרד (חוצת-פרקים) מוזרקת ומדוכאת בקובץ ההערות', () {
      final epub = _buildEpub(
        chapters: {
          'ch1.xhtml': _xhtml(
            '<p>טקסט עם הפניה<a href="notes.xhtml#n1">2</a>.</p>',
          ),
          'notes.xhtml': _xhtml(
            '<p>כותרת ההערות</p>'
            '<p id="n1">[2] תוכן ההערה המרוחקת</p>',
          ),
        },
      );
      final result = epubToText(epub, 'ספר');

      expect(result, contains('<sup class="footnote-marker">2</sup>'));
      expect(result, contains('<i class="footnote">תוכן ההערה המרוחקת</i>'));
      expect(RegExp('תוכן ההערה המרוחקת').allMatches(result).length, 1);
      // תוכן שאינו הערה בקובץ ההערות נשאר.
      expect(result, contains('כותרת ההערות'));
    });

    test('סמן אות עברית (א) מזוהה כהפניית הערה', () {
      final epub = _buildEpub(
        chapters: {
          'ch1.xhtml': _xhtml(
            '<p>דין ראשון<a href="#he1">א</a>.</p>'
            '<p id="he1">א. מקור הדין</p>',
          ),
        },
      );
      final result = epubToText(epub, 'ספר');

      expect(result, contains('<sup class="footnote-marker">א</sup>'));
      expect(result, contains('<i class="footnote">מקור הדין</i>'));
    });

    test('קישור עם טקסט ארוך (ניווט פנימי) אינו מזוהה כהערה והיעד נשמר', () {
      final epub = _buildEpub(
        chapters: {
          'ch1.xhtml': _xhtml(
            '<p>ראה <a href="#sec2">בפרק הבא על הלכות שבת</a>.</p>'
            '<h2 id="sec2">הלכות שבת</h2>'
            '<p>תוכן הפרק.</p>',
          ),
        },
      );
      final result = epubToText(epub, 'ספר');

      expect(result, isNot(contains('footnote-marker')));
      expect(result, contains('ראה בפרק הבא על הלכות שבת'));
      expect(result, contains('<h3>הלכות שבת</h3>'));
    });

    test('סמן מספרי שמצביע על יעד ארוך (קישור לפרק) אינו הופך להערה', () {
      final longText = 'תוכן ארוך מאוד. ' * 100; // מעל תקרת ההיריסטיקה
      final epub = _buildEpub(
        chapters: {
          'toc.xhtml': _xhtml('<p>פרק <a href="ch1.xhtml#c1">1</a></p>'),
          'ch1.xhtml': _xhtml('<div id="c1"><p>$longText</p></div>'),
        },
      );
      final result = epubToText(epub, 'ספר');

      expect(result, isNot(contains('footnote-marker')));
      expect(result, contains('תוכן ארוך מאוד.'));
    });

    test('קישור חיצוני (http) עם fragment אינו מסווג כהערה', () {
      final epub = _buildEpub(
        chapters: {
          'ch1.xhtml': _xhtml(
            '<p>ראה<a href="https://example.com/page#fn1">1</a> במקור</p>'
            '<p id="fn1">פסקה מקומית שאינה קשורה</p>',
          ),
        },
      );
      final result = epubToText(epub, 'ספר');

      expect(result, isNot(contains('footnote-marker')));
      // הפסקה המקומית לא דוכאה בטעות.
      expect(result, contains('פסקה מקומית שאינה קשורה'));
    });

    test('קישור לעוגן של הערה מזוהה גם בלי epub:type על הקישור', () {
      final epub = _buildEpub(
        chapters: {
          'ch1.xhtml': _xhtml(
            '<p>גוף<a href="#fn1">א</a></p>'
            '<div epub:type="rearnote" id="fn1">הערה</div>',
          ),
        },
      );
      final result = epubToText(epub, 'ספר');

      expect(result, contains('<sup class="footnote-marker">א</sup>'));
      expect(result, contains('<i class="footnote">הערה</i>'));
    });
  });

  group('epubToText - עטיפות בלוק', () {
    test('div עוטף עם בלוקים פנימיים שקוף; div עם inline בלבד הופך לשורה', () {
      final epub = _buildEpub(
        chapters: {
          'ch1.xhtml': _xhtml(
            '<div class="wrapper"><p>פסקה</p></div>'
            '<div>טקסט חשוף</div>',
          ),
        },
      );
      final result = epubToText(epub, 'ספר');
      final lines = result.split('\n');

      expect(lines, contains('פסקה'));
      expect(lines, contains('טקסט חשוף'));
      expect(result, isNot(contains('<div')));
    });

    test('רווחים לבנים (הזחות ושורות של ה-XHTML) מכווצים לרווח יחיד', () {
      final epub = _buildEpub(
        chapters: {
          'ch1.xhtml': _xhtml('<p>מילה\n      ראשונה</p>'),
        },
      );
      final result = epubToText(epub, 'ספר');
      expect(result, contains('מילה ראשונה'));
    });
  });
}

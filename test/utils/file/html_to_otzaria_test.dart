// ממיר ה-HTML — מבנה, חוזה ה-markup, וקודם לכול **חוזה האבטחה**.
//
// קובץ HTML הוא הפורמט היחיד שאוצריא קולטת ושהמשתמש מוריד מהאינטרנט
// כדבר שבשגרה, ולכן הבדיקות כאן נועלות במפורש את מה ש**אינו** אמור להגיע
// לגוף הספר: סקריפט, מטפלי אירועים, `javascript:`, משאב רשת, וטקסט שהמחבר
// הסתיר.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/document_conversion_exceptions.dart';
import 'package:otzaria/utils/file/document_format.dart';
import 'package:otzaria/utils/file/html_to_otzaria.dart';
import 'package:otzaria/utils/file/toc_parser.dart';
import 'package:path/path.dart' as p;

const _title = 'ספר';

/// רווח קשיח — ההזחה של פריט רשימה מקונן. רווח רגיל היה מכווץ ונבלע.
final String _nbsp = String.fromCharCode(0xA0);

Uint8List _utf8(String text) => Uint8List.fromList(utf8.encode(text));

/// PNG 1x1 — התוכן הקטן ביותר שנחשב תמונה תקינה.
final Uint8List _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNkYAAAAAYAAj'
  'CB0C8AAAAASUVORK5CYII=',
);

/// ממיר גוף HTML ומחזיר את שורות הספר **בלי** שורת הכותרת.
List<String> _convert(
  String body, {
  bool embedImages = true,
  String? baseDirectory,
}) {
  final lines = htmlToText(
    _utf8('<html><body>$body</body></html>'),
    _title,
    embedImages: embedImages,
    baseDirectory: baseDirectory,
  ).split('\n');
  expect(lines.first, '<h1>ספר</h1>');
  return lines.skip(1).toList();
}

String _joined(String body, {String? baseDirectory}) =>
    _convert(body, baseDirectory: baseDirectory).join('\n');

void main() {
  test('הערה מקוננת בכותרת נשארת בספר ואינה נכנסת לתוכן העניינים', () {
    final content = htmlToText(
      _utf8(
        '<html><body><h2>פרק א'
        '<sup class="footnote-marker">1</sup>'
        '<i class="footnote">הערה <i>נטויה</i> זנב</i>'
        ' סוף</h2></body></html>',
      ),
      _title,
    );
    expect(content, contains('<i class="footnote">הערה <i>נטויה</i> זנב</i>'));
    final toc = TocParser.parseEntriesFromContent(content);
    expect(toc.single.children.single.text, 'פרק א סוף');
  });

  group('מבנה הפלט', () {
    test('שורת הכותרת היא תמיד הראשונה ועוברת escape', () {
      final output = htmlToText(_utf8('<p>תוכן</p>'), 'ספר <גדול> & נחמד');
      expect(
        output.split('\n').first,
        '<h1>ספר &lt;גדול&gt; &amp; נחמד</h1>',
      );
    });

    test('כל פסקה היא שורת ספר אחת', () {
      expect(_convert('<p>ראשונה</p><p>שנייה</p>'), [
        'ראשונה',
        'שנייה',
      ]);
    });

    test('שורת פלט לעולם אינה מכילה שורה חדשה', () {
      final output = htmlToText(
        _utf8('<p>\n  טקסט\n  שנשבר\n</p>\n<div>\nעוד\n</div>'),
        _title,
      );
      // שורת הכותרת + שתי שורות תוכן, ולא יותר.
      expect(output.split('\n').length, 3);
      expect(output, contains('טקסט שנשבר'));
    });

    test('עטיפות שקופות מתפרקות לשורות של הבלוקים שבתוכן', () {
      expect(
        _convert(
          '<div dir="rtl"><section><p>אחת</p><p>שתיים</p></section></div>',
        ),
        ['אחת', 'שתיים'],
      );
    });

    test('טקסט חשוף בין בלוקים אינו נבלע', () {
      expect(_convert('<div>חשוף<p>בפסקה</p>עוד חשוף</div>'), [
        'חשוף',
        'בפסקה',
        'עוד חשוף',
      ]);
    });

    test('כותרות מוסטות רמה אחת מטה — h1 שמור לשם הספר', () {
      expect(_convert('<h1>פרק</h1><h2>סימן</h2><h6>עמוק</h6>'), [
        '<h2>פרק</h2>',
        '<h3>סימן</h3>',
        '<h6>עמוק</h6>',
      ]);
    });

    test('שורת כותרת פותחת ב-<h# — כך TocParser מזהה אותה', () {
      // עטיפת הכותרת ב-`<div>` הייתה מוציאה אותה מתוכן העניינים.
      final lines = _convert(
        '<div style="text-align: center"><h2>כותרת ממורכזת</h2></div>',
      );
      expect(lines.single, startsWith('<h3'));
    });

    test('אלמנט ריק אינו מייצר שורה', () {
      expect(_convert('<p></p><p>   </p><div></div><p>תוכן</p>'), ['תוכן']);
    });
  });

  group('אבטחה — קוד ומטפלי אירועים', () {
    test('<script> נמחק עם תוכנו', () {
      final output = _joined(
        '<p>לפני</p><script>alert("פיצוץ")</script><p>אחרי</p>',
      );
      expect(output, isNot(contains('alert')));
      expect(output, isNot(contains('פיצוץ')));
      expect(output, isNot(contains('script')));
      expect(_convert('<p>לפני</p><script>x()</script><p>אחרי</p>'), [
        'לפני',
        'אחרי',
      ]);
    });

    test('<style> ו-<noscript> נמחקים עם תוכנם', () {
      final output = _joined(
        '<style>body{display:none}</style>'
        '<noscript>אין סקריפט</noscript><p>תוכן</p>',
      );
      expect(output, isNot(contains('display')));
      expect(output, isNot(contains('אין סקריפט')));
      expect(output, contains('תוכן'));
    });

    test('מטפלי אירועים אינם מגיעים לפלט', () {
      final output = _joined(
        '<p onclick="steal()" onmouseover="x()" onerror="y()">טקסט</p>'
        '<span onload="z()">עוד</span>',
      );
      expect(output, isNot(contains('onclick')));
      expect(output, isNot(contains('onmouseover')));
      expect(output, isNot(contains('onerror')));
      expect(output, isNot(contains('onload')));
      expect(output, contains('טקסט'));
    });

    test('<iframe>/<object>/<embed>/<svg>/<canvas> נמחקים עם תוכנם', () {
      final output = _joined(
        '<iframe src="https://evil.example">תוכן מסגרת</iframe>'
        '<object data="x.swf"><param name="a" value="b"></object>'
        '<embed src="x.swf">'
        '<svg><script>alert(1)</script><text>טקסט וקטורי</text></svg>'
        '<canvas>גיבוי</canvas><p>ספר</p>',
      );
      expect(output, isNot(contains('evil.example')));
      expect(output, isNot(contains('תוכן מסגרת')));
      expect(output, isNot(contains('alert')));
      expect(output, isNot(contains('טקסט וקטורי')));
      expect(output, isNot(contains('x.swf')));
      expect(output, contains('ספר'));
    });

    test('פקדי טופס נמחקים אך הטקסט שסביבם נשמר', () {
      final output = _joined(
        '<form action="https://evil.example">'
        '<p>הסבר</p>'
        '<input type="password" name="סיסמה">'
        '<button onclick="send()">שלח</button>'
        '<select><option>אפשרות</option></select>'
        '<textarea>טיוטה</textarea>'
        '</form>',
      );
      expect(output, contains('הסבר'));
      expect(output, isNot(contains('evil.example')));
      expect(output, isNot(contains('שלח')));
      expect(output, isNot(contains('אפשרות')));
      expect(output, isNot(contains('טיוטה')));
    });

    test('מסמך frameset אינו מדליף את תוכן ה-head', () {
      final output = htmlToText(
        _utf8(
          '<html><head><title>כותרת ראש</title>'
          '<script>secret()</script></head>'
          '<frameset><frame src="a.html"></frameset></html>',
        ),
        _title,
      );
      expect(output, isNot(contains('secret')));
      expect(output, isNot(contains('כותרת ראש')));
      expect(output.split('\n'), ['<h1>ספר</h1>']);
    });
  });

  group('אבטחה — קישורים', () {
    test('javascript: מאבד את התגית ושומר את הטקסט', () {
      final output = _joined('<p><a href="javascript:alert(1)">לחץ</a></p>');
      expect(output, isNot(contains('javascript')));
      expect(output, isNot(contains('<a href')));
      expect(output, contains('לחץ'));
    });

    test('data:text/html נחסם', () {
      final output = _joined(
        '<p><a href="data:text/html,&lt;script&gt;x()&lt;/script&gt;">כאן</a>'
        '</p>',
      );
      expect(output, isNot(contains('data:')));
      expect(output, contains('כאן'));
    });

    test('otzaria:// נחסמת — היא שמורה לשימוש הפנימי של התוכנה', () {
      final output = _joined(
        '<p><a href="otzaria://inline-link?path=x&index=1">אחד</a>'
        '<a href="otzaria://note?line=3">שניים</a></p>',
      );
      expect(output, isNot(contains('otzaria://')));
      expect(output, contains('אחד'));
      expect(output, contains('שניים'));
    });

    test('קישור ישיר לספר (otzaria://open/book|pdf) נשמר — #2516', () {
      expect(
        _convert(
          '<p><a href="otzaria://open/book/12?index=3">ספר</a></p>',
        ).single,
        '<a href="otzaria://open/book/12?index=3">ספר</a>',
      );
      expect(
        _convert(
          '<p><a href="otzaria://open/pdf/5?source=user">PDF</a></p>',
        ).single,
        '<a href="otzaria://open/pdf/5?source=user">PDF</a>',
      );
    });

    for (final href in const [
      'otzaria://open/book/%FF',
      'otzaria://open/pdf/%FF',
      'otzaria://open/book/%D7',
      'otzaria://open/b%FFok/12',
    ]) {
      test('נתיב קישור פגום נשאר כטקסט בלי לפגוע בהמרה: $href', () {
        expect(
          _convert(
            '<p>לפני</p><p><a href="$href"><b>קישור</b></a></p>'
            '<p><a href="otzaria://open/book/12?index=3">תקין</a></p>'
            '<p>אחרי</p>',
          ),
          [
            'לפני',
            '<b>קישור</b>',
            '<a href="otzaria://open/book/12?index=3">תקין</a>',
            'אחרי',
          ],
        );
      });
    }

    test('שאר פעולות otzaria:// נחסמות גם ב-HTML', () {
      final output = _joined(
        '<p><a href="otzaria://plugin/install?url=x">התקנה</a>'
        '<a href="otzaria://library/reindex">רענון</a></p>',
      );
      expect(output, isNot(contains('otzaria://')));
      expect(output, contains('התקנה'));
      expect(output, contains('רענון'));
    });

    test('book:// מותרת — היא הדרך המתועדת לקשר בין ספרי אוצריא', () {
      expect(
        _convert('<p><a href="book://ברכות#דף ב:">קישור</a></p>').single,
        '<a href="book://ברכות#דף ב:">קישור</a>',
      );
    });

    test('file: ו-vbscript: נחסמים', () {
      final output = _joined(
        '<p><a href="file:///C:/Windows/system.ini">קובץ</a>'
        '<a href="vbscript:msgbox">סקריפט</a></p>',
      );
      expect(output, isNot(contains('file:')));
      expect(output, isNot(contains('vbscript')));
    });

    test('http/https/mailto ועוגן פנימי נשמרים', () {
      final output = _joined(
        '<p><a href="https://otzaria.org">אתר</a>'
        '<a href="mailto:a@b.c">דואר</a>'
        '<a href="#פרק-ב">פנימי</a></p>',
      );
      expect(output, contains('<a href="https://otzaria.org">אתר</a>'));
      expect(output, contains('<a href="mailto:a@b.c">דואר</a>'));
      expect(output, contains('<a href="#פרק-ב">פנימי</a>'));
    });

    test('href עם גרשיים אינו נחלץ מהמאפיין', () {
      final output = _joined(
        '<p><a href=\'https://a.example/"onmouseover="x()\'>טקסט</a></p>',
      );
      expect(output, isNot(contains('onmouseover="x()')));
      expect(output, contains('&quot;'));
    });
  });

  group('אבטחה — style ומאפיינים', () {
    test('ערך style שמנסה להיחלץ מהמאפיין מסונן', () {
      final output = _joined(
        '<p><span style=\'color: red"onmouseover="x()\'>טקסט</span></p>',
      );
      expect(output, isNot(contains('onmouseover')));
      expect(output, contains('טקסט'));
    });

    test('צבע שאינו ערך CSS תקין מדולג', () {
      final output = _joined(
        '<p><span style="color: url(https://evil.example/p.png)">א</span>'
        '<span style="background-color: expression(alert(1))">ב</span></p>',
      );
      expect(output, isNot(contains('evil.example')));
      expect(output, isNot(contains('expression')));
      expect(output, contains('א'));
      expect(output, contains('ב'));
    });

    test('class מהמקור אינו מגיע לפלט', () {
      // מחלקות כמו `footnote-marker` הן חוזה פנימי של שכבת התצוגה; מסמך
      // שמגדיר אותן היה מזייף סימוני הערות ועוגני מפרשים.
      final output = _joined(
        '<p class="footnote-marker"><span class="link-anchor">א</span>טקסט</p>',
      );
      expect(output, isNot(contains('class=')));
      expect(output, contains('טקסט'));
    });

    test('טקסט מוסתר מדולג לחלוטין', () {
      final output = _joined(
        '<p style="display: none">מוסתר</p>'
        '<p style="visibility:hidden">נעלם</p>'
        '<p hidden>מוצנע</p>'
        '<p>גלוי</p>',
      );
      expect(output, isNot(contains('מוסתר')));
      expect(output, isNot(contains('נעלם')));
      expect(output, isNot(contains('מוצנע')));
      expect(output, contains('גלוי'));
    });

    test('אין מסלול איסוף שעוקף את בדיקת ההסתרה', () {
      // שמונה עקיפות שנמצאו בביקורת אבטחה: תא, פריט רשימה, גוף מתקפל,
      // שורת טבלה, קבוצת שורות, רשימה מקוננת וטבלה מקוננת.
      const bypasses = [
        '<table><tr><td><p style="display:none">סוד</p></td></tr></table>',
        '<table><tr><td><div hidden>סוד</div></td></tr></table>',
        '<ul><li><p style="display:none">סוד</p></li></ul>',
        '<details><summary>ס</summary><p style="display:none">סוד</p>'
            '</details>',
        '<table><tr style="display:none"><td>סוד</td></tr>'
            '<tr><td>גלוי</td></tr></table>',
        '<table><thead style="display:none"><tr><td>סוד</td></tr></thead>'
            '<tr><td>גלוי</td></tr></table>',
        '<ul><li>א<ul style="display:none"><li>סוד</li></ul></li></ul>',
        '<table><tr><td>א<table style="display:none"><tr><td>סוד</td></tr>'
            '</table></td></tr></table>',
      ];
      for (final body in bypasses) {
        expect(_joined(body), isNot(contains('סוד')), reason: body);
      }
    });

    test('תגית לא מוכרת נפתחת ותוכנה נשמר', () {
      expect(_convert('<p>לפני <custom-tag>בתוך</custom-tag> אחרי</p>'), [
        'לפני בתוך אחרי',
      ]);
    });
  });

  group('אבטחה — תמונות', () {
    test('תמונה מהרשת אינה נטענת ואינה מגיעה לפלט', () {
      final output = _joined(
        '<p>לפני</p><img src="https://tracker.example/pixel.png">'
        '<img src="//tracker.example/p.gif"><p>אחרי</p>',
      );
      expect(output, isNot(contains('tracker.example')));
      expect(output, isNot(contains('<img')));
    });

    test('data URI של תמונה נתמכת מוטמע', () {
      final uri = 'data:image/png;base64,${base64Encode(_tinyPng)}';
      final output = _joined('<img src="$uri">');
      expect(output, contains('data:image/png;base64,'));
      expect(output, contains('max-width: 100%'));
    });

    test('width/height/alt/title נשמרים ומאומתים', () {
      final uri = 'data:image/png;base64,${base64Encode(_tinyPng)}';
      final line = _joined(
        '<img src="$uri" width="24" height="24" alt="אייקון" title="הסבר">',
      );
      expect(line, contains('width="24"'));
      expect(line, contains('height="24"'));
      expect(line, contains('alt="אייקון"'));
      expect(line, contains('title="הסבר"'));

      // ערך שאינו מספר חיובי אינו נכתב — העתקה מילולית הייתה מזריקה מאפיין.
      final injected = _joined(
        '<img src="$uri" width=\'24"onerror="x\' height="0">',
      );
      expect(injected, isNot(contains('onerror')));
      expect(injected, isNot(contains('height=')));
    });

    test('data URI שאינו base64 נדחה — הוא נושא markup חי', () {
      final output = _joined(
        '<img src="data:image/svg+xml,<svg onload=alert(1)></svg>">',
      );
      expect(output, isNot(contains('<img')));
      expect(output, isNot(contains('onload')));
    });

    test('SVG ב-data URI נדחה גם כשהוא base64', () {
      final svg = base64Encode(utf8.encode('<svg><script>x()</script></svg>'));
      final output = _joined('<img src="data:image/svg+xml;base64,$svg">');
      expect(output, isNot(contains('<img')));
    });

    test('base64 פגום אינו מגיע לגוף הספר', () {
      final output = _joined('<img src="data:image/png;base64,@@לא-base64@@">');
      expect(output, isNot(contains('<img')));
    });

    test('תמונה מעל התקרה לתמונה בודדת מדולגת', () {
      final big = base64Encode(Uint8List(5 * 1024 * 1024));
      final output = _joined('<img src="data:image/png;base64,$big">');
      expect(output, isNot(contains('<img')));
    });
  });

  group('תמונות מקומיות', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('html-images-');
      File(p.join(dir.path, 'ציור.png')).writeAsBytesSync(_tinyPng);
      await Directory(p.join(dir.path, 'תמונות')).create();
      File(
        p.join(dir.path, 'תמונות', 'פנימית.png'),
      ).writeAsBytesSync(_tinyPng);
    });

    tearDown(() async {
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
      } on FileSystemException {
        // נעילת קובץ ב-Windows אינה מעניינה של הבדיקה.
      }
    });

    test('תמונה לצד המסמך מוטמעת, גם כששמה מקודד ב-URL', () {
      final output = _joined(
        '<img src="${Uri.encodeComponent('ציור.png')}">'
        '<img src="תמונות/פנימית.png">',
        baseDirectory: dir.path,
      );
      expect('data:image/png;base64,'.allMatches(output).length, 2);
    });

    test('יציאה מתיקיית הספר נחסמת', () {
      final outside = File(p.join(dir.parent.path, 'סודי.png'))
        ..writeAsBytesSync(_tinyPng);
      addTearDown(() {
        try {
          outside.deleteSync();
        } on FileSystemException {
          // ראו tearDown.
        }
      });
      final output = _joined(
        '<img src="../סודי.png"><img src="/etc/passwd.png">',
        baseDirectory: dir.path,
      );
      expect(output, isNot(contains('<img')));
    });

    test('בלי baseDirectory אין קריאה מהדיסק כלל', () {
      expect(_joined('<img src="ציור.png">'), isNot(contains('<img')));
    });

    test('embedImages: false משמר את מספר השורות בדיוק', () {
      const body =
          '<p>לפני</p><img src="ציור.png"><p>באמצע</p>'
          '<img src="תמונות/פנימית.png"><p>אחרי</p>';
      final withImages = _convert(body, baseDirectory: dir.path);
      final withoutImages = _convert(
        body,
        embedImages: false,
        baseDirectory: dir.path,
      );
      expect(withoutImages.length, withImages.length);
      expect(withoutImages.where((l) => l.contains('<img')).length, 2);
      expect(withoutImages.join(), isNot(contains('base64')));
      expect(withoutImages.join(), contains('<img src=""'));
    });

    test('embedImages: false משמר את מספר השורות גם על תמונה שנפסלה', () {
      const body = '<p>לפני</p><img src="https://x.example/a.png"><p>אחרי</p>';
      expect(
        _convert(body, embedImages: false, baseDirectory: dir.path).length,
        _convert(body, baseDirectory: dir.path).length,
      );
    });
  });

  group('עיצוב inline', () {
    test('תגיות העיצוב הבסיסיות ממופות לחוזה של אוצריא', () {
      expect(
        _convert(
          '<p><b>מודגש</b><strong>גם</strong><i>נטוי</i><em>גם</em>'
          '<u>קו</u><s>חוצה</s><sup>עילי</sup><sub>תחתי</sub>'
          '<small>קטן</small><big>גדול</big></p>',
        ).single,
        '<b>מודגש</b><b>גם</b><i>נטוי</i><i>גם</i><u>קו</u><s>חוצה</s>'
        '<sup>עילי</sup><sub>תחתי</sub><small>קטן</small><big>גדול</big>',
      );
    });

    test('עיצוב מתוך style מתורגם לתגיות', () {
      expect(
        _convert(
          '<p><span style="font-weight: bold">א</span>'
          '<span style="font-style: italic">ב</span>'
          '<span style="text-decoration: underline">ג</span>'
          '<span style="text-decoration: line-through">ד</span></p>',
        ).single,
        '<b>א</b><i>ב</i><u>ג</u><s>ד</s>',
      );
    });

    test('וריאנט קו תחתי נקרא גם מהצהרה מרובת-מילים', () {
      expect(
        _convert(
          '<p><span style="text-decoration: underline dotted">א</span></p>',
        ).single,
        contains('underline dotted'),
      );
    });

    test('צבע הקו התחתי נקרא מההצהרה הייעודית', () {
      expect(
        _convert(
          '<p><span style="text-decoration: underline; '
          'text-decoration-color: #c00000">א</span></p>',
        ).single,
        contains('text-decoration-color: #c00000'),
      );
    });

    test('עובי הקו נשמר באחוזים ונדחה בפיקסלים', () {
      // המדריך: הקורא מכיר עובי באחוזים בלבד, ומתעלם מפיקסלים. כתיבתם
      // הייתה מצהירה על עובי שאינו מצויר.
      expect(
        _convert(
          '<p><span style="text-decoration: underline; '
          'text-decoration-thickness: 250%">א</span></p>',
        ).single,
        contains('text-decoration-thickness: 250%'),
      );
      expect(
        _convert(
          '<p><span style="text-decoration: underline; '
          'text-decoration-thickness: 3px">א</span></p>',
        ).single,
        isNot(contains('text-decoration-thickness')),
      );
    });

    test('line-through double הופך לקו חוצה כפול', () {
      expect(
        _convert(
          '<p><span style="text-decoration: line-through double">א</span></p>',
        ).single,
        '<span style="text-decoration: line-through double;">א</span>',
      );
    });

    test('<font color> של מסמכים ישנים נשמר', () {
      expect(
        _convert('<p><font color="#c00000">אדום</font></p>').single,
        '<span style="color:#c00000">אדום</span>',
      );
    });

    test('צבע שחור מנוקה, ומרקר לבן מדולג', () {
      final output = _joined(
        '<p><span style="color: black">שחור</span>'
        '<span style="background-color: white">לבן</span>'
        '<span style="color: inherit">ירושה</span></p>',
      );
      expect(output, isNot(contains('style=')));
      expect(output, contains('שחור'));
    });

    test('<mark> הופך למרקר', () {
      expect(
        _convert('<p><mark>מודגש</mark></p>').single,
        '<span style="background-color:yellow">מודגש</span>',
      );
    });

    test('<br> נשמר ורצפי רווחים מכווצים', () {
      expect(
        _convert('<p>אלף   בית<br>\n  גימל</p>').single,
        'אלף בית<br> גימל',
      );
    });

    test('<pre> משמר את מבנה השורות כ-<br> ואינו כופה כיווניות', () {
      // כפיית `dir="ltr"` הייתה הופכת `<pre>` עברי, שאינו נדיר בספרי קודש.
      expect(
        _convert('<pre>שורה א\nשורה ב</pre>').single,
        '<pre>שורה א<br>שורה ב</pre>',
      );
    });

    test('טקסט עובר escape', () {
      expect(
        _convert('<p>a &lt; b &amp; c &gt; d</p>').single,
        'a &lt; b &amp; c &gt; d',
      );
    });
  });

  group('מבנים שהקורא מציג — ואסור לפרק אותם', () {
    test('<details> נשאר שורה אחת ואינו חושף את התוכן המוסתר', () {
      // פירוקו לשורות היה מציג את הטקסט המוסתר כטקסט רגיל ומאבד את
      // ההתקפלות — כלומר שינוי משמעות, לא רק אובדן עיצוב.
      expect(
        _convert(
          '<p>לפני</p>'
          '<details><summary>הצג</summary>מוסתר</details>'
          '<p>אחרי</p>',
        ),
        [
          'לפני',
          '<details><summary>הצג</summary>מוסתר</details>',
          'אחרי',
        ],
      );
    });

    test('<details open> ועיצוב על הקטע נשמרים', () {
      final line = _convert(
        '<details open style="font-size:110%"><summary>כותרת</summary>'
        'גוף</details>',
      ).single;
      expect(line, startsWith('<details open'));
      expect(line, contains('font-size: 110%'));
    });

    test('<ruby> שומר את הפירוש ואינו מדביק אותו למילה', () {
      // בלי שימור התגיות שני הטקסטים נדבקים ל"אנפיןפנים" — טקסט משובש.
      expect(
        _convert('<p><ruby>אנפין<rt>פנים</rt></ruby> המשך</p>').single,
        '<ruby>אנפין<rt>פנים</rt></ruby> המשך',
      );
    });

    test('<hr> נפלט כשורה, וניתן לעצב אותו', () {
      expect(_convert('<p>לפני</p><hr><p>אחרי</p>'), [
        'לפני',
        '<hr>',
        'אחרי',
      ]);
      expect(
        _convert('<hr style="border-top:3px solid #8b0000;">').single,
        '<hr style="border-top: 3px solid #8b0000">',
      );
    });

    test('<blockquote> נשמר, ומתפרק כשיש בו בלוקים', () {
      expect(
        _convert('<blockquote>ציטוט</blockquote>').single,
        '<blockquote>ציטוט</blockquote>',
      );
      expect(
        _convert('<blockquote><p>אחת</p><p>שתיים</p></blockquote>'),
        ['אחת', 'שתיים'],
      );
    });

    test('<caption> נשמר בתוך הטבלה ואינו נשמט', () {
      final line = _convert(
        '<table><caption>טבלת השוואה</caption>'
        '<tr><td>ימין</td></tr></table>',
      ).single;
      expect(line, contains('<caption>טבלת השוואה</caption>'));
      expect(line, startsWith('<table'));
    });

    test('cellpadding מתורגם לריווח בפועל על התא', () {
      // חוזה ה-markup כותב `padding` inline לכל תא והוא דורס כל
      // `cellpadding=`, ולכן כתיבת המאפיין לבדה הייתה מאפיין מת.
      expect(
        _convert('<table cellpadding="8"><tr><td>תא</td></tr></table>').single,
        contains('padding: 8px'),
      );
      final injected = _convert(
        '<table cellpadding=\'8"onload="x\'><tr><td>תא</td></tr></table>',
      ).single;
      expect(injected, isNot(contains('onload')));
      expect(injected, contains('padding: 4px 8px'));
    });

    test('<abbr>/<acronym> ו-<address> נשמרים', () {
      expect(
        _convert('<p><abbr>רמב"ם</abbr><acronym>שו"ע</acronym></p>').single,
        '<abbr>רמב"ם</abbr><abbr>שו"ע</abbr>',
      );
      expect(
        _convert('<address>כתובת</address>').single,
        '<address>כתובת</address>',
      );
    });
  });

  group('הערות שוליים במנגנון של אוצריא', () {
    test('הצירוף מסמן+גוף נפלט מחדש דרך חוזה ה-markup', () {
      final line = _convert(
        '<p>מילה<sup class="footnote-marker">1</sup>'
        '<i class="footnote">גוף ההערה</i> המשך</p>',
      ).single;
      expect(
        line,
        'מילה<sup class="footnote-marker">1</sup>'
        '<i class="footnote">גוף ההערה</i> המשך',
      );
    });

    test('סימן שהוא אות עברית נשמר כפי שהוא', () {
      expect(
        _convert(
          '<p>מילה<sup class="footnote-marker">א</sup>'
          '<i class="footnote">הערה</i></p>',
        ).single,
        contains('<sup class="footnote-marker">א</sup>'),
      );
    });

    test('גוף ההערה אינו מופיע פעמיים', () {
      final line = _convert(
        '<p><sup class="footnote-marker">1</sup>'
        '<i class="footnote">ייחודי</i></p>',
      ).single;
      expect('ייחודי'.allMatches(line).length, 1);
    });

    test('עיצוב בתוך גוף ההערה נשמר', () {
      expect(
        _convert(
          '<p><sup class="footnote-marker">1</sup>'
          '<i class="footnote">עם <b>הדגשה</b></i></p>',
        ).single,
        contains('<i class="footnote">עם <b>הדגשה</b></i>'),
      );
    });

    test('מסמן בלי גוף צמוד נשאר מסמן בלבד', () {
      expect(
        _convert('<p>מילה<sup class="footnote-marker">1</sup> המשך</p>').single,
        'מילה<sup class="footnote-marker">1</sup> המשך',
      );
    });

    test('שאר שמות ה-class השמורים אינם מגיעים לפלט', () {
      // הם קשורים למכונת הקישורים וההערות של הקורא; מסמך זר שהיה מגדיר
      // אותם היה מזייף ממשק.
      final output = _joined(
        '<p><span class="link-anchor">א</span>'
        '<span class="book-note-marker">ב</span>'
        '<sup class="footnote-marker-number">ג</sup></p>',
      );
      expect(output, isNot(contains('link-anchor')));
      expect(output, isNot(contains('book-note-marker')));
      expect(output, isNot(contains('footnote-marker-number')));
      expect(output, contains('א'));
    });
  });

  group('רגרסיות שנמצאו בסקירת QA', () {
    test('data-toc="none" נשמר — אחרת הכותרת מזהמת את תוכן העניינים', () {
      expect(
        _convert('<h2 data-toc="none">כותרת עיצובית</h2>').single,
        '<h3 data-toc="none">כותרת עיצובית</h3>',
      );
    });

    test('עיצוב של תא בטבלה נשמר', () {
      // «ניתן לעצב תא בודד ככל תג אחר» — הדוגמה של המדריך עצמו.
      final line = _convert(
        '<table><tr><td style="color:#8B0000; font-size:120%">תא</td></tr>'
        '</table>',
      ).single;
      expect(line, contains('color: #8B0000'));
      expect(line, contains('font-size: 120%'));
    });

    test('תמונה בתוך פריט רשימה ובתוך תא אינה נמחקת', () {
      final uri = 'data:image/png;base64,${base64Encode(_tinyPng)}';
      expect(
        _convert('<ul><li>לפני <img src="$uri"> אחרי</li></ul>').single,
        contains('<img'),
      );
      expect(
        _convert('<table><tr><td><img src="$uri"></td></tr></table>').single,
        contains('<img'),
      );
    });

    test('טקסט שאינו <li> בתוך רשימה אינו נעלם', () {
      expect(_convert('<ol>הקדמה<li>פריט</li></ol>'), [
        'הקדמה',
        '1. פריט',
      ]);
      expect(_convert('<ul><li>פריט</li>אחרי</ul>'), ['• פריט', 'אחרי']);
    });

    test('טבלה שכל תוכנה כיתוב אינה נעלמת', () {
      expect(
        _convert('<table><caption>טבלת השוואה</caption></table>').single,
        contains('<caption>טבלת השוואה</caption>'),
      );
    });

    test('גוף הערה מוסתר אינו מגיע לגוף הספר ולאינדקס', () {
      expect(
        _convert(
          '<p><sup class="footnote-marker">1</sup>'
          '<i class="footnote" style="display:none">סוד</i></p>',
        ).single,
        '<sup class="footnote-marker">1</sup>',
      );
    });

    test('בלוקים בתוך <details> ובתוך <li> אינם נדבקים למילה אחת', () {
      expect(
        _convert(
          '<details><summary>ס</summary><p>פסקה א</p><p>פסקה ב</p></details>',
        ).single,
        contains('פסקה א<br>פסקה ב'),
      );
      expect(
        _convert('<ul><li><p>אחת</p><p>שתיים</p></li></ul>').single,
        contains('אחת<br>שתיים'),
      );
    });

    test('צבע בתוך קיצור text-decoration אינו אובד', () {
      expect(
        _convert(
          '<p><span style="text-decoration:underline #00A000">קו</span></p>',
        ).single,
        contains('text-decoration-color: #00a000'),
      );
    });

    test('text-decoration:none עובר — תגית אינה יכולה לבטל קו', () {
      expect(
        _convert(
          '<p><a href="https://x.org" style="text-decoration:none">ק</a></p>',
        ).single,
        contains('text-decoration: none'),
      );
    });

    test('עובי קו נכתב כהצהרה אחת ולא על span פנימי מת', () {
      final line = _convert(
        '<p><span style="text-decoration:underline; '
        'text-decoration-thickness:250%">עבה</span></p>',
      ).single;
      expect(line, contains('text-decoration: underline'));
      expect(line, contains('text-decoration-thickness: 250%'));
      expect(line, isNot(contains('<u>')));
    });

    test('שחור ולבן מנוקים גם ברמת הבלוק ובתא', () {
      expect(_convert('<div style="color:black">שחור</div>').single, 'שחור');
      expect(
        _convert('<div style="background-color:#FFFFFF">לבן</div>').single,
        'לבן',
      );
      expect(
        _convert(
          '<table><tr><td style="color:black">תא</td></tr></table>',
        ).single,
        isNot(contains('black')),
      );
    });

    test('רווח קשיח בתחילת שורה אינו נגזם', () {
      // `String.trim()` של דארט מסיר גם U+00A0 — בדיוק התו שהמחבר כתב
      // כדי שהרווח לא יתכווץ.
      expect(
        _convert('<p>${_nbsp * 3}טקסט מוזח</p>').single,
        '${_nbsp * 3}טקסט מוזח',
      );
    });

    test('עוגן שנתבע ולא נפלט אינו גונב את היעד מאלמנט אחר', () {
      expect(
        _convert(
          '<p><a href="#יעד">קפוץ</a></p>'
          '<table id="יעד"></table><p id="יעד">גוף אמיתי</p>',
        ),
        ['<a href="#יעד">קפוץ</a>', '<a id="יעד"></a>גוף אמיתי'],
      );
    });

    test('עוגן של עוטף שכל תוכנו כותרת יושב על הכותרת', () {
      expect(
        _convert('<div id="x"><h2>כ</h2></div><p><a href="#x">ל</a></p>'),
        ['<h3 id="x">כ</h3>', '<a href="#x">ל</a>'],
      );
    });

    test('עוגן של עוטף שלא ייצר שורה אינו נצמד לשורה זרה', () {
      expect(
        _convert(
          '<p><a href="#יעד">קפוץ</a></p>'
          '<div id="יעד"><p style="display:none">מוסתר</p></div>'
          '<p>פרק אחר לגמרי</p>',
        ),
        [
          '<a href="#יעד">קפוץ</a>',
          '<a id="יעד"></a>',
          'פרק אחר לגמרי',
        ],
      );
    });

    test('פריט ריק נספר במספור, כמו בדפדפן', () {
      expect(_convert('<ol><li>א</li><li></li><li>ג</li></ol>'), [
        '1. א',
        '3. ג',
      ]);
    });

    test('מספור יורד סופר רק פריטים נראים', () {
      expect(
        _convert(
          '<ol reversed><li style="display:none">ח</li><li>א</li>'
          '<li>ב</li></ol>',
        ),
        ['2. א', '1. ב'],
      );
    });

    test('כותרת עם שורה חדשה אינה מפצלת את שורה 0', () {
      final lines = htmlToText(_utf8('<p>ג</p>'), 'שם\nעם שורה').split('\n');
      expect(lines.first, '<h1>שם עם שורה</h1>');
      expect(lines.length, 2);
    });
  });

  group('CSS — תכונות שהקורא מכיר עוברות', () {
    test('גופן, גודל וגובה שורה', () {
      expect(
        _convert(
          '<p><span style="font-family: \'SBL Hebrew\', serif; '
          'font-size:130%; line-height:1.5">טקסט</span></p>',
        ).single,
        '<span style="font-family: \'SBL Hebrew\', serif; '
        'font-size: 130%; line-height: 1.5">טקסט</span>',
      );
    });

    test('דרגת עובי מספרית נשמרת ואינה משטחת ל-<b>', () {
      expect(
        _convert('<p><span style="font-weight:600">חצי</span></p>').single,
        '<span style="font-weight: 600">חצי</span>',
      );
      // `bold` ו-700 דווקא כן הופכים לתגית — היא נתמכת גם בקריאה הרציפה.
      expect(
        _convert('<p><span style="font-weight:bold">מלא</span></p>').single,
        '<b>מלא</b>',
      );
    });

    test('מסגרת, ריווח וצל', () {
      expect(
        _convert(
          '<div style="border:1px solid #8b0000; padding:10px; '
          'margin:8px">תיבה</div>',
        ).single,
        '<div style="border: 1px solid #8b0000; padding: 10px; '
        'margin: 8px">תיבה</div>',
      );
      expect(
        _convert(
          '<p><span style="text-shadow: 2px 2px 4px gray">צל</span></p>',
        ).single,
        contains('text-shadow: 2px 2px 4px gray'),
      );
    });

    test('כיווניות כפויה בתוך שורה — direction עם inline-block', () {
      expect(
        _convert(
          '<p>הקובץ ב<span style="direction:ltr; display:inline-block">'
          r'C:\Otzaria\otzaria.exe</span> במחשב</p>',
        ).single,
        contains('direction: ltr; display: inline-block'),
      );
    });

    test('vertical-align ו-white-space', () {
      expect(
        _convert(
          '<p><span style="vertical-align:super">מורם</span></p>',
        ).single,
        contains('vertical-align: super'),
      );
      expect(
        _convert('<p><span style="white-space:nowrap">רצוף</span></p>').single,
        contains('white-space: nowrap'),
      );
    });

    test('overline נשאר הצהרה — אין לו תגית מקבילה', () {
      expect(
        _convert(
          '<p><span style="text-decoration:underline overline">קווים</span>'
          '</p>',
        ).single,
        '<span style="text-decoration: underline overline">קווים</span>',
      );
    });

    test('צבע בכל הצורות שהמדריך מתעד', () {
      for (final color in const [
        '#f00',
        '#2828ac',
        '#2828ac55',
        'rgb(200,30,30)',
        'rgba(200,30,30,0.45)',
        'hsl(120,60%,35%)',
        'darkred',
      ]) {
        expect(
          _convert('<p><span style="color:$color">צבע</span></p>').single,
          '<span style="color:$color">צבע</span>',
          reason: color,
        );
      }
    });

    test('עיצוב מתקדם שאינו נתמך אינו מגיע לפלט', () {
      final output = _joined(
        '<p><span style="transform:rotate(5deg); position:absolute; '
        'float:left; opacity:0.5; border-radius:4px; '
        'text-emphasis:dot; background-image:url(https://evil.example/x.png)'
        '">טקסט</span></p>',
      );
      expect(output, 'טקסט');
    });

    test('הצהרה עם ערך פסול מדולגת, והתקינות שלצדה נשמרות', () {
      expect(
        _convert(
          '<p><span style="font-size:1.5rem; color:#8b0000; '
          'font-style:oblique">טקסט</span></p>',
        ).single,
        '<span style="color:#8b0000">טקסט</span>',
      );
    });
  });

  group('יישור וכיווניות', () {
    test('מרכוז נכתב תמיד, וגם <center>', () {
      expect(
        _convert('<p style="text-align: center">א</p>').single,
        contains(
          'text-align: center',
        ),
      );
      expect(
        _convert('<center>ב</center>').single,
        contains(
          'text-align: center',
        ),
      );
      expect(
        _convert('<p align="center">ג</p>').single,
        contains(
          'text-align: center',
        ),
      );
    });

    test('justify נופל לברירת המחדל של אוצריא', () {
      expect(_convert('<p style="text-align: justify">א</p>').single, 'א');
    });

    test('יישור לוגי מדולג בבלוק RTL ונפתר בבלוק LTR', () {
      expect(
        _convert('<p dir="rtl" style="text-align: end">עברית</p>').single,
        'עברית',
      );
      expect(
        _convert('<p dir="ltr" style="text-align: end">English</p>').single,
        '<div dir="ltr" style="text-align: right">English</div>',
      );
    });

    test('dir="rtl" אינו נכתב — הקורא כולו RTL וההצהרה מיותרת', () {
      expect(_convert('<p>סתם</p>').single, 'סתם');
      expect(_convert('<div dir="rtl"><p>עברית</p></div>').single, 'עברית');
      expect(
        _convert('<table dir="rtl"><tr><td>תא</td></tr></table>').single,
        isNot(contains('dir=')),
      );
    });

    test('dir="ltr" כן נכתב — הוא היחיד שסוטה מברירת המחדל', () {
      expect(
        _convert('<div dir="ltr"><p>English</p></div>').single,
        contains('dir="ltr"'),
      );
    });

    test('כיווניות מ-<html> נזרעת — היא אינה אחד הצמתים שנסרקים', () {
      final lines = htmlToText(
        _utf8('<html dir="ltr"><body><p>English</p></body></html>'),
        _title,
      ).split('\n');
      expect(lines[1], contains('dir="ltr"'));
    });
  });

  group('רשימות', () {
    test('תבליט ומספור, כולל קינון', () {
      // ההזחה היא ברווחים קשיחים — HTML מכווץ רווח מוביל, ורווח רגיל היה
      // מציג את הפריט המקונן באותו מקום כמו פריט ברמה הראשונה.
      expect(
        _convert(
          '<ul><li>תבליט<ul><li>מקונן</li></ul></li></ul>'
          '<ol><li>ראשון</li><li>שני</li></ol>',
        ),
        ['• תבליט', '${_nbsp * 4}• מקונן', '1. ראשון', '2. שני'],
      );
    });

    test('type ו-start נקראים', () {
      expect(_convert('<ol type="a" start="3"><li>פריט</li></ol>'), [
        'c. פריט',
      ]);
      expect(_convert('<ol type="I"><li>פריט</li></ol>'), ['I. פריט']);
    });

    test('list-style-type: hebrew מייצר ספרות עבריות', () {
      expect(
        _convert(
          '<ol style="list-style-type: hebrew"><li>א</li><li>ב</li></ol>',
        ),
        ['א. א', 'ב. ב'],
      );
    });

    test('reversed הופך את סדר המספור', () {
      expect(
        _convert('<ol reversed><li>ראשון</li><li>שני</li></ol>'),
        ['2. ראשון', '1. שני'],
      );
    });

    test('lower-greek מייצר אותיות יווניות', () {
      expect(
        _convert(
          '<ol style="list-style-type: lower-greek"><li>א</li><li>ב</li></ol>',
        ),
        ['α. א', 'β. ב'],
      );
    });

    test('סוגי תבליט נבדלים זה מזה', () {
      String marker(String type) => _convert(
        '<ul style="list-style-type:$type"><li>פריט</li></ul>',
      ).single;
      expect(marker('disc'), startsWith('•'));
      expect(marker('circle'), startsWith('◦'));
      expect(marker('square'), startsWith('▪'));
      // `none` — הזחה בלי סימן, ברווח קשיח שאינו מתכווץ.
      expect(marker('none'), startsWith(_nbsp));
    });

    test('value על פריט קובע את המספור מכאן והלאה', () {
      expect(
        _convert('<ol><li>א</li><li value="7">ב</li><li>ג</li></ol>'),
        ['1. א', '7. ב', '8. ג'],
      );
    });
  });

  group('טבלאות', () {
    test('טבלה היא שורת פלט אחת עם חוזה ה-markup', () {
      final line = _convert(
        '<table><tr><th>כותרת</th><td>תא</td></tr></table>',
      ).single;
      expect(line, startsWith('<table'));
      expect(line, contains('border-collapse: collapse'));
      expect(
        line,
        contains(
          '<th style="border: 1px solid #999; '
          'padding: 4px 8px">כותרת</th>',
        ),
      );
      expect(line, contains('<td'));
    });

    test('colspan/rowspan מאומתים כמספר חיובי', () {
      final line = _convert(
        '<table><tr>'
        '<td colspan="2" rowspan="3">תקין</td>'
        '<td colspan="0" rowspan="-1">אפס</td>'
        '<td colspan=\'2"onclick="x()\'>הזרקה</td>'
        '</tr></table>',
      ).single;
      expect(line, contains('colspan="2" rowspan="3"'));
      expect(line, isNot(contains('colspan="0"')));
      expect(line, isNot(contains('rowspan="-1"')));
      expect(line, isNot(contains('onclick')));
    });

    test('רקע תא ויישור אנכי', () {
      final line = _convert(
        '<table><tr>'
        '<td bgcolor="#eeeeee" valign="middle">א</td>'
        '<td bgcolor="#ffffff">לבן</td>'
        '</tr></table>',
      ).single;
      expect(line, contains('background-color: #eeeeee'));
      expect(line, contains('vertical-align: middle'));
      expect(line, isNot(contains('#ffffff')));
    });

    test('כמה בלוקים בתא מופרדים ב-<br> ואינם נדבקים', () {
      expect(
        _convert(
          '<table><tr><td><p>ראשונה</p><p>שנייה</p></td></tr></table>',
        ).single,
        contains('ראשונה<br>שנייה'),
      );
    });

    test('טבלה מקוננת נשארת בתוך התא — גם בתוך עטיפה', () {
      expect(
        _convert(
          '<table><tr><td><div><table><tr><td>עמוק</td></tr></table></div>'
          '</td></tr></table>',
        ).single,
        contains('עמוק'),
      );
    });

    test('טבלה מקוננת נשארת בתוך התא', () {
      final line = _convert(
        '<table><tr><td><table><tr><td>פנימי</td></tr></table></td></tr>'
        '</table>',
      ).single;
      expect('<table'.allMatches(line).length, 2);
    });

    test('טבלה בלי שורות אינה מייצרת שורה', () {
      expect(_convert('<table></table><p>אחרי</p>'), ['אחרי']);
    });
  });

  group('עוגנים וקישורים פנימיים', () {
    test('id שיש אליו קישור נשמר — כך הניווט בקורא עובד', () {
      final output = _joined(
        '<p><a href="#הערה-1">1</a></p>'
        '<h2 id="הערה-1">גוף ההערה</h2>',
      );
      expect(output, contains('<a href="#הערה-1">1</a>'));
      expect(output, contains('<h3 id="הערה-1">'));
    });

    test('<a name> נשמר כעוגן כשמפנים אליו', () {
      final output = _joined(
        '<p><a href="#יעד">קפוץ</a></p><p><a name="יעד"></a>היעד</p>',
      );
      expect(output, contains('<a id="יעד"></a>היעד'));
    });

    test('עוגן inline כפול נפלט פעם אחת', () {
      final output = _joined(
        '<p><a href="#יעד">קפוץ</a><span id="יעד">א</span></p>'
        '<p id="יעד">ב</p>',
      );
      expect('<a id="יעד"></a>'.allMatches(output), hasLength(1));
    });

    test('id שאיש אינו מפנה אליו אינו מנפח את הפלט', () {
      expect(_convert('<p id="עיצובי">טקסט</p>'), ['טקסט']);
    });

    test('עוגן של עטיפה מצטרף לשורת התוכן ואינו יוצר שורה ריקה', () {
      expect(
        _convert(
          '<p><a href="#פרק">קישור</a></p>'
          '<div id="פרק"><p>תוכן הפרק</p></div>',
        ),
        ['<a href="#פרק">קישור</a>', '<a id="פרק"></a>תוכן הפרק'],
      );
    });
  });

  group('קידוד', () {
    test('UTF-8 עם BOM', () {
      final bytes = Uint8List.fromList([
        0xEF, 0xBB, 0xBF, //
        ...utf8.encode('<html><body><p>שלום</p></body></html>'),
      ]);
      expect(htmlToText(bytes, _title), contains('שלום'));
    });

    test('הצהרת windows-1255 מכריעה מול קידוד עברי אחר', () {
      // הבתים הם Windows-1255 תקין; ההצהרה היא מה שמונע בחירה ב-CP862.
      final bytes = <int>[
        ...latin1.encode(
          '<html><head>'
          '<meta http-equiv="Content-Type" '
          'content="text/html; charset=windows-1255">'
          '</head><body><p>',
        ),
        0xF9, 0xEC, 0xE5, 0xED, // שלום
        ...latin1.encode('</p></body></html>'),
      ];
      expect(htmlToText(Uint8List.fromList(bytes), _title), contains('שלום'));
    });

    test('הצהרה שסותרת UTF-8 שאומת אינה מתקבלת', () {
      // דפים ישנים רבים נשמרו מחדש ב-UTF-8 בלי לעדכן את התגית; קבלת
      // ההצהרה כאן הייתה הופכת ספר תקין לג'יבריש.
      final bytes = _utf8(
        '<html><head><meta charset="windows-1255"></head>'
        '<body><p>שלום עולם</p></body></html>',
      );
      expect(htmlToText(bytes, _title), contains('שלום עולם'));
    });
  });

  group('חוזה הכשל', () {
    test('מכולה בינארית בסיומת HTML נכשלת ואינה נקראת כטקסט', () {
      for (final header in [
        [0x50, 0x4B, 0x03, 0x04], // ZIP
        [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1], // OLE
        [0x25, 0x50, 0x44, 0x46], // %PDF
      ]) {
        expect(
          () => htmlToText(Uint8List.fromList([...header, 1, 2, 3]), _title),
          throwsA(isA<UnsupportedDocumentFormatException>()),
        );
      }
    });

    test('מסמך מעל תקרת הגודל נכשל בחריגה מוקלדת', () {
      expect(
        () => htmlToText(Uint8List(HtmlLimits.maxSourceBytes + 1), _title),
        throwsA(isA<CorruptedDocumentException>()),
      );
    });

    test('הכשל נרשם על הסיומת שזוהתה, ולא תמיד כ-html', () {
      // `fileType` הוא זהות ולא תווית — כשל של .htm חייב לדווח .htm.
      Object? thrown;
      try {
        htmlToText(
          Uint8List.fromList([0x50, 0x4B, 0x03, 0x04]),
          _title,
          format: DocumentFormat.htm,
        );
      } catch (e) {
        thrown = e;
      }
      expect(thrown, isA<UnsupportedDocumentFormatException>());
      expect(
        (thrown! as DocumentConversionException).format,
        DocumentFormat.htm,
      );
    });

    test('מסמך ריק אינו כשל — מוחזרת הכותרת בלבד', () {
      expect(htmlToText(_utf8(''), _title), '<h1>ספר</h1>');
      expect(
        htmlToText(_utf8('<html><body></body></html>'), _title),
        '<h1>ספר</h1>',
      );
    });

    test('HTML שבור אינו מפיל את הממיר', () {
      final output = htmlToText(
        _utf8('<p>לא נסגר <b>מודגש <div>מקונן שגוי</p></b>'),
        _title,
      );
      expect(output, contains('לא נסגר'));
      expect(output, contains('מקונן שגוי'));
    });

    test('קינון עמוק אינו מפיל את הממיר', () {
      final deep = '${'<div>' * 5000}עמוק${'</div>' * 5000}';
      expect(() => htmlToText(_utf8(deep), _title), returnsNormally);
    });

    test('קינון קיצוני נכשל בחריגה מוקלדת ולא ב-StackOverflowError', () {
      // `package:html` עצמו מהלך רקורסיבית על העץ; שגיאה שבורחת מכאן
      // הייתה חוצה את גבול ה-isolate כשגיאה שהצנרת אינה מצפה לה.
      final deep = '${'<div>' * 15000}עמוק${'</div>' * 15000}';
      expect(
        () => htmlToText(_utf8(deep), _title),
        anyOf(returnsNormally, throwsA(isA<DocumentConversionException>())),
      );
    });

    test('אלפי סימוני הערות באותה פסקה אינם סריקה ריבועית', () {
      // לפני התיקון 8,000 מסמנים נמדדו ב-2.5 שניות ו-32,000 ב-128 שניות —
      // גדילה ריבועית. אחרי התיקון הזמן ליניארי, והסף כאן רחב בכוונה כדי
      // שלא ייכשל על מכונת CI איטית אלא רק על חזרת הריבועיות.
      final markers = StringBuffer('<p>');
      for (var i = 0; i < 8000; i++) {
        markers.write('<sup class="footnote-marker">1</sup>x');
      }
      markers.write('</p>');
      final stopwatch = Stopwatch()..start();
      htmlToText(_utf8(markers.toString()), _title);
      stopwatch.stop();
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('טקסט גולמי בלי תגיות הופך לשורת ספר', () {
      expect(htmlToText(_utf8('סתם טקסט'), _title).split('\n'), [
        '<h1>ספר</h1>',
        'סתם טקסט',
      ]);
    });
  });
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/markdown_to_otzaria.dart';

void main() {
  group('MarkdownToOtzaria', () {
    const converter = MarkdownToOtzaria();

    test('ממיר GFM, front matter וכיווניות ברמת בלוק', () async {
      final result = await converter.convertSource('''
---
title: ספר בדיקה
author: מחבר
---
# כותרת

**מודגש** ו-*נטוי*

| א | ב |
|---|---|
| 1 | 2 |

~~מחוק~~

```dart
final value = 1;
```
''');

      expect(result.title, 'ספר בדיקה');
      expect(result.author, 'מחבר');
      expect(
        result.html,
        contains('<h1 id="כותרת" dir="rtl" class="md-block">כותרת</h1>'),
      );
      expect(result.html, contains('<strong>מודגש</strong>'));
      expect(result.html, contains('<table dir="rtl" class="md-block">'));
      expect(result.html, contains('<del>מחוק</del>'));
      expect(result.html, contains('<code class="language-dart" dir="ltr">'));
      expect(result.html, isNot(contains('title: ספר בדיקה')));
    });

    test('מסלול bytes מסיר תמונות חיצוניות', () {
      final html = markdownBytesToHtml(
        Uint8List.fromList(utf8.encode('![מעקב](https://example.com/a.png)')),
        'ספר',
      );
      expect(html, isNot(contains('https://example.com')));
    });

    test('שומר תמונת data URI שאינה דורשת רשת', () {
      final html = markdownBytesToHtml(
        Uint8List.fromList(
          utf8.encode(
            '<img src="data:image/png;base64,AA==">',
          ),
        ),
        'ספר',
      );
      expect(html, contains('data:image/png;base64,AA=='));
    });

    test('משאיר HTML מותר וחוסם סקריפטים, אירועים ו-javascript URLs', () async {
      final result = await converter.convertSource('''
<div class="note" onclick="alert(1)">הערה</div>
<script>alert(1)</script>
<iframe src="https://example.com"></iframe>
<a href="javascript:alert(1)" onload="x()">קישור</a>
''');

      expect(result.html, contains('<div class="md-block">הערה</div>'));
      expect(result.html, isNot(contains('script')));
      expect(result.html, isNot(contains('iframe')));
      expect(result.html, isNot(contains('onclick')));
      expect(result.html, isNot(contains('javascript:')));
    });

    test('מטמיע תמונה מקומית קטנה ומסיר תמונה חסרה', () async {
      final directory = await Directory.systemTemp.createTemp('markdown-book-');
      addTearDown(() => directory.delete(recursive: true));
      await File(
        '${directory.path}${Platform.pathSeparator}image.png',
      ).writeAsBytes(Uint8List.fromList([137, 80, 78, 71]));

      final result = await converter.convertSource(
        '![קיים](image.png)\n\n![חסר](missing.png)',
        baseDirectory: directory.path,
      );

      expect(result.html, contains('src="data:image/png;base64,'));
      expect(result.html, contains('alt="חסר"'));
      expect(result.html, isNot(contains('missing.png')));
    });

    test('קלט Markdown חלקי מוצג במאמץ מיטבי', () async {
      final result = await converter.convertSource(
        '# כותרת\n\n**מודגש ללא סוגר\n\n```dart\nfinal x = 1;',
      );

      expect(
        result.html,
        contains('<h1 id="כותרת" dir="rtl" class="md-block">כותרת</h1>'),
      );
      expect(result.html, contains('מודגש ללא סוגר'));
      expect(result.html, contains('final x = 1;'));
    });

    test('פלט ה-worker אינו מזריק כותרת ואינו תלוי בשם הקובץ', () {
      final bytes = Uint8List.fromList(utf8.encode('# פרק ראשון'));

      expect(
        markdownBytesToHtml(bytes, 'שם קובץ').trim(),
        '<h1 id="פרק-ראשון" dir="rtl" class="md-block">פרק ראשון</h1>',
      );
    });

    test('שומר רשימה, טבלה ובלוק קוד כל אחד בשורת אוצריא אחת', () async {
      final result = await converter.convertSource('''
- ראשון
  - פנימי
- שני

| א | ב |
|---|---|
| 1 | 2 |

```dart
final first = 1;
final second = 2;
```
''');
      final lines = result.html.split('\n');

      expect(lines, hasLength(3));
      expect(lines[0], startsWith('<ul class="md-block">'));
      expect(lines[0], endsWith('</ul>'));
      expect(lines[1], startsWith('<table dir="rtl" class="md-block">'));
      expect(lines[1], endsWith('</table>'));
      expect(lines[2], startsWith('<pre dir="ltr" class="md-block">'));
      expect(lines[2], contains('final first = 1;&#10;final second = 2;'));
    });

    test('מפרק עוטף div שעוטף את כל המסמך לשורות בלוק נפרדות', () async {
      final result = await converter.convertSource('''
<div dir="rtl">

# כותרת ראשית

פסקה.

## תת כותרת

- פריט

</div>
''');
      final lines = result.html.split('\n');

      expect(lines, hasLength(4));
      expect(
        lines[0],
        '<h1 id="כותרת-ראשית" dir="rtl" class="md-block">כותרת ראשית</h1>',
      );
      expect(lines[1], '<p dir="rtl" class="md-block">פסקה.</p>');
      expect(
        lines[2],
        '<h2 id="תת-כותרת" dir="rtl" class="md-block">תת כותרת</h2>',
      );
      expect(lines[3], startsWith('<ul dir="rtl" class="md-block">'));
    });

    test('div עם תוכן inline בלבד נשאר שורה אחת', () async {
      final result = await converter.convertSource(
        '<div class="note">הערה</div>',
      );

      expect(result.html.split('\n'), hasLength(1));
      expect(result.html, contains('<div class="md-block">הערה</div>'));
    });

    test('אלמנט ריק אינו הופך לשורת ספר', () async {
      final result = await converter.convertSource('''
<div dir="rtl">

# כותרת

<i>
</i>

</div>
''');

      expect(result.html.split('\n'), hasLength(1));
      expect(
        result.html,
        contains('<h1 id="כותרת" dir="rtl" class="md-block">כותרת</h1>'),
      );
    });

    test('טוקן קוד בתחילת שורה אינו הופך שורה עברית ל-LTR', () async {
      final result = await converter.convertSource(
        '- `side` — 0 = העוגן על שורת־המקור, 1 = על שורת־היעד',
      );

      expect(result.html, contains('<li dir="rtl">'));
      expect(result.html, contains('<code dir="ltr">side</code>'));
    });

    test('זיהוי כיווניות עוצר בתו חזק מחוץ לקוד גם בעץ מקונן', () async {
      final result = await converter.convertSource(
        '> `English` — **טקסט עברי**\n\n'
        '> `עברית` — English prose',
      );

      final blocks = result.html.split('\n');
      expect(blocks, hasLength(2));
      expect(blocks[0], contains('<blockquote dir="rtl"'));
      expect(blocks[1], contains('<blockquote dir="ltr"'));
    });

    test('כיוון בלוק עם קוד בלבד נשמר לפי טקסט הקוד', () async {
      final result = await converter.convertSource('`English`');
      expect(result.html, contains('<p dir="ltr"'));
    });
    test('טבלה מקבלת כיווניות לפי תוכנה ולא לפי העוטף', () async {
      final result = await converter.convertSource('''
<div dir="rtl">

| key | value |
|-----|-------|
| a   | b     |

</div>
''');

      expect(result.html, startsWith('<table dir="ltr" class="md-block">'));
    });

    test('שורה שכולה אנגלית נשארת LTR', () async {
      final result = await converter.convertSource('- `side` is the anchor');

      expect(result.html, contains('<li dir="ltr">'));
    });

    test('תג בתוך code span אינו דולף ואינו בולע את המשך המסמך', () async {
      final result = await converter.convertSource('''
<div dir="rtl">

# כותרת

טקסט עם `<i data-commentator="x">` בתוך קוד.

## אחרי

סוף.

</div>
''');
      final lines = result.html.split('\n');

      expect(lines, hasLength(4));
      expect(result.html, contains('&lt;i data-commentator='));
      expect(lines[2], startsWith('<h2 id="אחרי"'));
    });

    test('עוגן יעד מפורש נשמר כשורה משלו', () async {
      final result = await converter.convertSource('''
<div dir="rtl">

<a name="יעד-מפורש"></a>
## כותרת בנוסח אחר

טקסט.

</div>
''');

      expect(result.html, contains('name="יעד-מפורש"'));
    });

    test('slug של כותרת תואם ל-GitHub בפיסוק שאינו ASCII', () async {
      final result = await converter.convertSource(
        '## ערכי JSON גולמיים ← מיפוי לשם ב־DB',
      );

      // החץ מוסר ומשאיר שני מקפים, בדיוק כמו ב-github-slugger.
      expect(result.html, contains('id="ערכי-json-גולמיים--מיפוי-לשם-בdb"'));
    });

    test('מייצר מזהי עוגן ייחודיים לכותרות ושומר מזהה מפורש', () async {
      final result = await converter.convertSource('''
# 2. ספירת DB
# 2. ספירת DB
<h2 id="custom-anchor">כותרת</h2>
''');

      expect(result.html, contains('id="2-ספירת-db"'));
      expect(result.html, contains('id="2-ספירת-db-1"'));
      expect(result.html, contains('id="custom-anchor"'));
    });
  });

  test('מסיר תמונות חיצוניות ומחלקות פנימיות מזויפות', () async {
    const converter = MarkdownToOtzaria();
    final result = await converter.convertSource(
      '<img src="https://example.com/track.png" class="link-anchor">',
    );
    expect(result.html, isNot(contains('https://example.com')));
    expect(result.html, isNot(contains('link-anchor')));
  });
}

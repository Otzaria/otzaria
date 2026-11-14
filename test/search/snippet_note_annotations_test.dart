import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/utils/snippet_builder.dart';

const _body = TextStyle(fontSize: 20, color: Colors.black);
const _match = TextStyle(
  fontSize: 22,
  fontWeight: FontWeight.bold,
  color: Colors.red,
);

List<TextSpan> _html(String html, {TextStyle? markStyle}) =>
    SnippetBuilder.fromHighlightedHtml(
      html: html,
      defaultStyle: _body,
      highlightStyle: _match,
      markStyle: markStyle,
    ).cast<TextSpan>();

String _text(Iterable<TextSpan> spans) =>
    spans.map((span) => span.text ?? '').join();

String _matched(Iterable<TextSpan> spans) =>
    _text(spans.where((span) => span.style?.fontWeight == FontWeight.bold));

List<TextSpan> _ranges(
  String html,
  List<List<int>> ranges, {
  String? plainText,
}) => SnippetBuilder.spansFromRanges(
  plainText: plainText ?? SnippetBuilder.htmlToPlainText(html),
  ranges: ranges,
  defaultStyle: _body,
  highlightStyle: _match,
  sourceHtml: html,
).cast<TextSpan>();

void main() {
  group('תגיות הערה בתוצאת מנוע', () {
    test('גוף ההערה מסומן במפורש והסמן מוקטן', () {
      final spans = _html(
        'גוף <otzaria-note-marker>12</otzaria-note-marker> '
        '<otzaria-note>דברי ההערה</otzaria-note> המשך',
      );
      expect(_text(spans), 'גוף 12 [הערה: דברי ההערה] המשך');
      final note = spans.singleWhere((span) => span.text == 'דברי ההערה');
      expect(note.style!.fontStyle, FontStyle.italic);
      expect(note.style!.fontSize, 18);
      final marker = spans.singleWhere((span) => span.text == '12');
      expect(marker.style!.fontSize, 15);
      expect(marker.style!.fontStyle, isNull);
      expect(spans.first.style, same(_body));
      expect(spans.last.style, same(_body));
    });

    test('התאמה רק בהערה נשארת מודגשת בלי להדגיש את התווית', () {
      final spans = _html(
        'חכמה <otzaria-note><font color=red>חכמה</font></otzaria-note> חכמה',
      );
      expect(_text(spans), 'חכמה [הערה: חכמה] חכמה');
      expect(_matched(spans), 'חכמה');
      final match = spans.singleWhere(
        (span) => span.style?.color == Colors.red,
      );
      expect(match.style!.fontStyle, FontStyle.italic);
      expect(match.style!.fontSize, closeTo(19.8, 0.0001));
      expect(
        spans
            .where((span) => span.text == '[הערה: ' || span.text == ']')
            .every((span) => span.style!.fontWeight != FontWeight.bold),
        isTrue,
      );
    });

    test('התאמה בגוף הספר אינה הופכת להערה', () {
      final spans = _html(
        '<font>חכמה</font> <otzaria-note>חכמה</otzaria-note> המשך',
      );
      expect(_matched(spans), 'חכמה');
      expect(spans.first.style, same(_match));
      expect(spans.first.style!.fontStyle, isNull);
      expect(
        spans
            .singleWhere((span) => span.text == 'חכמה' && span != spans.first)
            .style!
            .fontStyle,
        FontStyle.italic,
      );
    });

    test('סמן שמכיל התאמה שומר על הצבע וההדגשה', () {
      final spans = _html(
        '<otzaria-note-marker><font>12</font></otzaria-note-marker>',
      );
      expect(_matched(spans), '12');
      expect(spans.single.style!.fontSize, 16.5);
      expect(spans.single.style!.color, Colors.red);
    });

    test('הדגשת קטע סמנטי נשמרת בתוך הערה', () {
      const markStyle = TextStyle(fontSize: 20, backgroundColor: Colors.yellow);
      final spans = _html(
        '…<otzaria-note><mark>דברי ההערה</mark></otzaria-note>…',
        markStyle: markStyle,
      );
      expect(_text(spans), '…[הערה: דברי ההערה]…');
      final note = spans.singleWhere((span) => span.text == 'דברי ההערה');
      expect(note.style!.backgroundColor, Colors.yellow);
      expect(note.style!.fontStyle, FontStyle.italic);
      expect(note.style!.fontSize, 18);
      expect(spans.first.style, same(_body));
      expect(spans.last.style, same(_body));
    });

    test('תג הדגשה חיצוני נשמר גם סביב גבול הערה', () {
      final spans = _html(
        '<font>גוף <otzaria-note>הערה</otzaria-note> סוף</font>',
      );
      expect(_matched(spans), 'גוף הערה סוף');
      expect(_text(spans), 'גוף [הערה: הערה] סוף');
      expect(spans.first.style, same(_match));
      expect(spans.last.style, same(_match));
    });

    test('תגיות עיצוב רגילות אינן מוסבות להערות', () {
      final spans = _html('גוף<sup>12</sup><i>נטוי</i><b>מודגש</b> סוף');
      expect(_text(spans), 'גוף12נטוימודגש סוף');
      expect(spans.every((span) => identical(span.style, _body)), isTrue);
    });

    test('תגיות מוברחות נשארות תוכן רגיל', () {
      final spans = _html('&lt;otzaria-note&gt;טקסט&lt;/otzaria-note&gt;');
      expect(_text(spans), '<otzaria-note>טקסט</otzaria-note>');
      expect(spans.single.style, same(_body));
    });

    test('HTML ישן בלי תגיות הערה שומר על סגנונותיו המקוריים', () {
      final spans = _html('גוף 12 <font color=red>מפורשת</font> סוף');
      expect(_text(spans), 'גוף 12 מפורשת סוף');
      expect(_matched(spans), 'מפורשת');
      expect(spans[0].style, same(_body));
      expect(spans[1].style, same(_match));
      expect(spans[2].style, same(_body));
    });

    test('החילוץ הגולמי וההתאמות אינם כוללים תוויות שנוספו לתצוגה', () {
      const html =
          ' גוף <otzaria-note-marker>12</otzaria-note-marker> '
          '<otzaria-note>דבר <font>מפורש</font><br>נוסף</otzaria-note> סוף ';
      expect(
        SnippetBuilder.htmlToPlainText(html),
        'גוף 12 דבר מפורש\nנוסף סוף',
      );
      expect(SnippetBuilder.extractHighlightedTerms(html), {'מפורש'});
    });

    test('הערה ריקה אינה מוסיפה תווית לתוצאה', () {
      expect(_text(_html('גוף<otzaria-note></otzaria-note> סוף')), 'גוף סוף');
    });

    test('העתקת הערה שומרת את התווית ואת מעבר השורה', () {
      expect(
        SnippetBuilder.annotatedPlainText(
          'גוף <otzaria-note-marker>12</otzaria-note-marker> '
          '<otzaria-note><font>דבר</font><br>נוסף &amp; אחר</otzaria-note> סוף',
        ),
        'גוף 12 [הערה: דבר\nנוסף & אחר] סוף',
      );
    });

    test('העתקת תוצאה ישנה נשארת בפענוח הקיים של הקורא', () {
      expect(SnippetBuilder.annotatedPlainText('<p>גוף</p><p>סוף</p>'), isNull);
      expect(
        SnippetBuilder.annotatedPlainText('<font>גוף 12 הערה</font> סוף'),
        isNull,
      );
    });

    test('טקסט מוברח או attribute אינם מפעילים העתקת הערה', () {
      expect(
        SnippetBuilder.annotatedPlainText(
          '&lt;otzaria-note&gt;טקסט&lt;/otzaria-note&gt;',
        ),
        isNull,
      );
      expect(
        SnippetBuilder.annotatedPlainText(
          '<span title="otzaria-note">גוף</span>',
        ),
        isNull,
      );
    });
  });

  group('הערות אחרי חישוב טווחי הדגשה מחדש', () {
    const repeated = 'אב <otzaria-note>אב</otzaria-note> אב';

    test('מילה חוזרת ממופה לפי מיקומה בתוך התג', () {
      final spans = _ranges(repeated, [
        [3, 5],
      ]);
      expect(_text(spans), 'אב [הערה: אב] אב');
      expect(_matched(spans), 'אב');
      final match = spans.singleWhere(
        (span) => span.style?.fontWeight == FontWeight.bold,
      );
      expect(match.style!.fontStyle, FontStyle.italic);
      expect(spans.first.style, same(_body));
      expect(spans.last.style, same(_body));
    });

    test('הופעת אותה מילה אחרי ההערה נשארת חלק מהגוף', () {
      final spans = _ranges(repeated, [
        [6, 8],
      ]);
      expect(_matched(spans), 'אב');
      expect(spans.last.style, same(_match));
      expect(spans.last.style!.fontStyle, isNull);
    });

    test('טווח שחוצה את גבולות ההערה אינו צובע את התווית', () {
      final spans = _ranges(repeated, [
        [0, 8],
      ]);
      expect(_text(spans), 'אב [הערה: אב] אב');
      expect(_matched(spans), 'אב אב אב');
      expect(
        spans
            .where((span) => span.text == '[הערה: ' || span.text == ']')
            .every((span) => span.style!.fontWeight != FontWeight.bold),
        isTrue,
      );
    });

    test('רשימת טווחים ריקה עדיין מציגה את ההערה', () {
      final spans = _ranges(repeated, []);
      expect(_text(spans), 'אב [הערה: אב] אב');
      expect(_matched(spans), isEmpty);
    });

    test('טקסט שונה באותו אורך אינו מקבל את עיצוב המקור', () {
      final spans = _ranges(repeated, [
        [3, 5],
      ], plainText: 'גד גד גד');
      expect(_text(spans), 'גד גד גד');
      expect(_matched(spans), 'גד');
      expect(
        spans.every((span) => span.style!.fontStyle != FontStyle.italic),
        isTrue,
      );
    });

    test('גם תת־מחרוזת חוזרת אינה מזוהה בטעות עם ההערה', () {
      final spans = _ranges(repeated, [
        [0, 2],
      ], plainText: 'אב');
      expect(_text(spans), 'אב');
      expect(spans.single.style, same(_match));
    });

    test('ישויות HTML ותווים מחוץ ל־BMP אינם מזיזים טווחים', () {
      const html = '😀 &amp; אב <otzaria-note>אב</otzaria-note> סוף';
      final plain = SnippetBuilder.htmlToPlainText(html);
      final start = plain.lastIndexOf('אב');
      final spans = _ranges(html, [
        [start, start + 2],
      ]);
      expect(_text(spans), '😀 & אב [הערה: אב] סוף');
      expect(_matched(spans), 'אב');
      expect(
        spans
            .singleWhere((span) => span.style?.fontWeight == FontWeight.bold)
            .style!
            .fontStyle,
        FontStyle.italic,
      );
    });

    test('כיווץ רווחים ומעברי שורה תואם לטקסט שעליו חושבו הטווחים', () {
      const html =
          '  גוף\t <otzaria-note-marker> 12 </otzaria-note-marker> '
          '<otzaria-note> אב  <font>אב</font><br> אב </otzaria-note> סוף  ';
      final plain = SnippetBuilder.htmlToPlainText(html);
      final last = plain.lastIndexOf('אב');
      final spans = _ranges(html, [
        [last, last + 2],
      ]);
      expect(_text(spans).replaceAll('[הערה: ', '').replaceAll(']', ''), plain);
      expect(_text(spans), contains('[הערה: '));
      expect(_matched(spans), 'אב');
      expect(
        spans
            .singleWhere((span) => span.style?.fontWeight == FontWeight.bold)
            .style!
            .fontStyle,
        FontStyle.italic,
      );
      expect(_text(spans), contains('\n'));
    });

    test('סמן מוקטן גם כשהוא עצמו התאמה', () {
      final spans = _ranges(
        'גוף <otzaria-note-marker>12</otzaria-note-marker> סוף',
        [
          [4, 6],
        ],
      );
      expect(_text(spans), 'גוף 12 סוף');
      final marker = spans.singleWhere((span) => span.text == '12');
      expect(marker.style!.fontWeight, FontWeight.bold);
      expect(marker.style!.fontSize, 16.5);
    });

    test('שתי הערות עם אותו טקסט שומרות על זהויותיהן', () {
      const html =
          '<otzaria-note>אב</otzaria-note> אב <otzaria-note>אב</otzaria-note>';
      final spans = _ranges(html, [
        [6, 8],
      ]);
      expect(_text(spans), '[הערה: אב] אב [הערה: אב]');
      expect(_matched(spans), 'אב');
      final notes = spans.where((span) => span.text == 'אב').toList();
      expect(notes, hasLength(2));
      expect(notes.first.style!.fontWeight, isNull);
      expect(notes.last.style!.fontWeight, FontWeight.bold);
    });

    test('טווח חורג אינו משבש את גבולות ההערה', () {
      final spans = _ranges(repeated, [
        [0, 99],
      ]);
      expect(_text(spans), 'אב [הערה: אב] אב');
      expect(_matched(spans), isEmpty);
    });

    test('טקסט ישן עם תגיות עיצוב רגילות שומר על סגנון הטווח', () {
      final spans = _ranges('אב <b>אב</b> אב', [
        [3, 5],
      ]);
      expect(_text(spans), 'אב אב אב');
      expect(_matched(spans), 'אב');
      expect(spans[1].style, same(_match));
    });
  });
}

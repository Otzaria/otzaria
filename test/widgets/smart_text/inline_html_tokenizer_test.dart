import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:otzaria/utils/text/otzaria_markup.dart';
import 'package:otzaria/widgets/smart_text/inline_html_tokenizer.dart';

/// מבנה העץ כמחרוזת: תגים, attributes לפי סדר שם, וטקסט.
String _dump(List<dom.Node> nodes) {
  final out = StringBuffer();
  void visit(dom.Node node) {
    if (node is dom.Text) {
      out.write('"${node.data}"');
    } else if (node is dom.Element) {
      final attrs = node.attributes.entries.toList()
        ..sort((a, b) => '${a.key}'.compareTo('${b.key}'));
      out.write('<${node.localName}');
      for (final attr in attrs) {
        out.write(' ${attr.key}=${attr.value}');
      }
      out.write('>');
      node.nodes.forEach(visit);
      out.write('</${node.localName}>');
    }
  }

  nodes.forEach(visit);
  return out.toString();
}

void main() {
  test('תמונה מוטמעת מופנית לתצוגת HTML לפני בניית עץ inline', () {
    final image = otzariaImage(
      'data:image/png;base64,${'A' * (4 << 20)}',
      width: '20',
      alt: 'image',
    );
    expect(parseInlineHtmlNodes('לפני $image אחרי'), isNull);
  });

  test('טקסט דמוי תמונה או תג קטוע שומרים את פרסור HTML5', () {
    const image = '<img src="data:image/png;base64,A">';
    for (final html in [
      '<!-- $image -->טקסט',
      "<span title='$image'>טקסט</span>",
      '&lt;img src="data:image/png;base64,A"&gt;',
      'טקסט <img src="data:image/png;base64,A',
    ]) {
      expect(
        _dump(parseInlineHtmlNodes(html)!),
        _dump(html_parser.parseFragment(html).nodes),
      );
    }
  });

  // הפרסור המהיר מקבל רק קלט שהעץ שלו זהה לזה של פרסר HTML5.
  const accepted = [
    'טקסט פשוט',
    '<b>מודגש</b> <i>נטוי <small>(קטן)</small></i><br>סוף<br/>',
    '<a class="link-anchor link-anchor-2 link-anchor-active" href="otzaria://anchor?ref=3_0">(א)</a>',
    '<a href="otzaria://inline-link?path=%D7%90&index=2&ref=x" style="text-decoration: underline;">קישור</a>',
    "<span style='font-size:92%' data-x=\"1\">גרש</span>",
    'א&nbsp;ב&thinsp;ג &amp; &lt;ד&gt; &quot;ה&quot; &#1488;&#x5D0; & ו',
    '<span class="mam-kq"><span class="mam-kq-k">(כתיב)</span> <span class="mam-kq-q">[קרי]</span></span>',
    '<h2>כותרת <b>מודגשת</b></h2>',
    '<span class="a"   title="x&amp;y" >רווחים</span>',
    '<b>לא נסגר',
    '<SPAN CLASS="x">אותיות גדולות</SPAN>',
  ];
  const rejected = [
    '<b>א<i>ב</b>ג</i>',
    'סוגר יתום</span>',
    '<a href="x">א<a href="y">ב</a></a>',
    '<b><h2>כותרת בתוך תג</h2></b>',
    '<p>פסקה</p>',
    '<span class=x>בלי מירכאות</span>',
    '<!-- הערה -->',
    'א&copy;ב',
    'א&#128;ב',
    'שורה\r\nחדשה',
    'תו\u0000ריק',
    '<span/>',
    '</br>',
    '<a href="x&amp">ישות בלי נקודה-פסיק</a>',
    '<span a="1" a="2">כפול</span>',
  ];

  test('קלט תקין מתפרסר לאותו עץ כמו פרסר HTML5', () {
    for (final html in accepted) {
      final quick = parseWellFormedInlineHtml(html);
      expect(quick, isNotNull, reason: html);
      expect(
        _dump(quick!),
        _dump(html_parser.parseFragment(html).nodes),
        reason: html,
      );
    }
  });

  test('קלט שאין ודאות בעץ שלו נשאר לפרסר המלא', () {
    for (final html in rejected) {
      expect(parseWellFormedInlineHtml(html), isNull, reason: html);
    }
  });
}

/// פרסור מהיר של HTML inline תקין, לעץ זהה לזה של `package:html`.
///
/// רוב שורות הספרים הן תגי עיצוב מקוננים כהלכה; עבורן פרסר HTML5 המלא הוא
/// כמחצית מעלות בניית השורה. כל קלט שאין ודאות שהעץ שלו זהה — קינון שבור,
/// תג או ישות לא מוכרים, הערה, תו CR — מחזיר null, והקורא משתמש בפרסר המלא.
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

const Set<String> _inlineTags = {
  'span',
  'a',
  'b',
  'strong',
  'big',
  'small',
  'u',
  'ins',
  's',
  'strike',
  'del',
  'mark',
  'i',
  'em',
  'cite',
  'dfn',
  'var',
};

const Set<String> _headingTags = {'h1', 'h2', 'h3', 'h4', 'h5', 'h6'};

const Map<String, String> _namedEntities = {
  'nbsp': '\u00A0',
  'thinsp': '\u2009',
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
};

bool _isNameChar(int c) =>
    (c >= 0x61 && c <= 0x7A) ||
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x30 && c <= 0x39);

bool _isSpace(int c) =>
    c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0C || c == 0x0D;

// תג התמונה שהממירים מפיקים. התאמה מתחילת התג הראשון מונעת
// זיהוי של טקסט בתוך הערה או ערך של מאפיין כתמונה.
final _embeddedImage = RegExp(
  r'<img src="data:image/[^"]*"(?: [a-z]+="[^"]*")* */?>',
);

/// null כאשר השורה דורשת HtmlWidget ואפשר לחסוך את בניית העץ הזמני.
List<dom.Node>? parseInlineHtmlNodes(String html) {
  final firstTag = html.indexOf('<');
  if (firstTag == -1 && !html.contains('&')) return [dom.Text(html)];
  if (firstTag >= 0 && _embeddedImage.matchAsPrefix(html, firstTag) != null) {
    return null;
  }
  return parseWellFormedInlineHtml(html) ??
      html_parser.parseFragment(html).nodes;
}

/// הצמתים של [html], או null כשנדרש הפרסר המלא.
List<dom.Node>? parseWellFormedInlineHtml(String html) {
  final root = <dom.Node>[];
  final stack = <dom.Element>[];
  final text = StringBuffer();

  void flushText() {
    if (text.isEmpty) return;
    final node = dom.Text(text.toString());
    text.clear();
    if (stack.isEmpty) {
      root.add(node);
    } else {
      stack.last.append(node);
    }
  }

  var i = 0;
  final length = html.length;
  while (i < length) {
    final c = html.codeUnitAt(i);
    if (c == 0x0D || c == 0x00) return null;
    if (c == 0x26) {
      final decoded = _entity(html, i, inAttribute: false);
      if (decoded == null) return null;
      text.write(decoded.$1);
      i = decoded.$2;
      continue;
    }
    if (c != 0x3C) {
      // רצף הטקסט עד התו המיוחד הבא נכתב בהעתקה אחת.
      var end = i + 1;
      while (end < length) {
        final d = html.codeUnitAt(end);
        if (d == 0x3C || d == 0x26 || d == 0x0D || d == 0x00) break;
        end++;
      }
      text.write(html.substring(i, end));
      i = end;
      continue;
    }
    // תג.
    final closing = i + 1 < length && html.codeUnitAt(i + 1) == 0x2F;
    var p = closing ? i + 2 : i + 1;
    final nameStart = p;
    while (p < length && _isNameChar(html.codeUnitAt(p))) {
      p++;
    }
    if (p == nameStart) return null;
    final name = html.substring(nameStart, p).toLowerCase();
    final isHeading = _headingTags.contains(name);
    if (!_inlineTags.contains(name) && name != 'br' && !isHeading) return null;

    if (closing) {
      while (p < length && _isSpace(html.codeUnitAt(p))) {
        p++;
      }
      if (p >= length || html.codeUnitAt(p) != 0x3E) return null;
      if (stack.isEmpty || stack.last.localName != name) return null;
      flushText();
      stack.removeLast();
      i = p + 1;
      continue;
    }

    final attributes = <Object, String>{};
    var selfClosing = false;
    while (true) {
      final before = p;
      while (p < length && _isSpace(html.codeUnitAt(p))) {
        p++;
      }
      if (p >= length) return null;
      final ch = html.codeUnitAt(p);
      if (ch == 0x3E) {
        p++;
        break;
      }
      if (ch == 0x2F) {
        if (p + 1 < length && html.codeUnitAt(p + 1) == 0x3E) {
          selfClosing = true;
          p += 2;
          break;
        }
        return null;
      }
      // attribute חייב להיות מופרד ברווח מהקודם.
      if (p == before) return null;
      final attrStart = p;
      while (p < length) {
        final a = html.codeUnitAt(p);
        if (_isNameChar(a) || a == 0x2D || a == 0x5F || a == 0x3A) {
          p++;
        } else {
          break;
        }
      }
      if (p == attrStart || p >= length || html.codeUnitAt(p) != 0x3D) {
        return null;
      }
      final attrName = html.substring(attrStart, p).toLowerCase();
      p++;
      if (p >= length) return null;
      final quote = html.codeUnitAt(p);
      if (quote != 0x22 && quote != 0x27) return null;
      p++;
      final value = StringBuffer();
      while (p < length && html.codeUnitAt(p) != quote) {
        final v = html.codeUnitAt(p);
        if (v == 0x0D || v == 0x00) return null;
        if (v == 0x26) {
          final decoded = _entity(html, p, inAttribute: true);
          if (decoded == null) return null;
          value.write(decoded.$1);
          p = decoded.$2;
          continue;
        }
        value.writeCharCode(v);
        p++;
      }
      if (p >= length) return null;
      p++;
      if (attributes.containsKey(attrName)) return null;
      attributes[attrName] = value.toString();
    }

    if (selfClosing && name != 'br') return null;
    // כותרת רק ברמה העליונה; `<a>` בתוך `<a>` נסגר אחרת ב-HTML5.
    if (isHeading && stack.isNotEmpty) return null;
    if (name == 'a' && stack.any((e) => e.localName == 'a')) return null;

    flushText();
    final element = dom.Element.tag(name);
    element.attributes.addAll(attributes);
    if (stack.isEmpty) {
      root.add(element);
    } else {
      stack.last.append(element);
    }
    if (name != 'br') stack.add(element);
    i = p;
  }
  flushText();
  return root;
}

/// ישות שמתחילה ב-[start]: הטקסט והמיקום שאחריה, או null כשאין ודאות.
(String, int)? _entity(String html, int start, {required bool inAttribute}) {
  final length = html.length;
  var p = start + 1;
  if (p >= length) return ('&', p);
  final first = html.codeUnitAt(p);
  if (first == 0x23) {
    p++;
    final hex = p < length && (html.codeUnitAt(p) | 0x20) == 0x78;
    if (hex) p++;
    final digitsStart = p;
    while (p < length && _isNameChar(html.codeUnitAt(p))) {
      p++;
    }
    if (p >= length || html.codeUnitAt(p) != 0x3B) return null;
    final value = int.tryParse(
      html.substring(digitsStart, p),
      radix: hex ? 16 : 10,
    );
    if (value == null) return null;
    final printable =
        (value >= 0x20 && value <= 0x7E) || (value >= 0xA0 && value <= 0xD7FF);
    if (!printable) return null;
    return (String.fromCharCode(value), p + 1);
  }
  if (!_isNameChar(first)) return ('&', p);
  final nameStart = p;
  while (p < length && _isNameChar(html.codeUnitAt(p))) {
    p++;
  }
  if (p < length && html.codeUnitAt(p) == 0x3B) {
    final decoded = _namedEntities[html.substring(nameStart, p)];
    return decoded == null ? null : (decoded, p + 1);
  }
  // `&name=` ב-attribute (פרמטר של URL) נשאר כפי שהוא ב-HTML5.
  if (inAttribute && p < length && html.codeUnitAt(p) == 0x3D) {
    return ('&', nameStart);
  }
  return null;
}

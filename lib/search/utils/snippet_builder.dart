import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// בונה הדגשות לתצוגת תוצאות חיפוש.
///
/// קיימים שני מקורות לתוצאות, ולכל אחד דרך הדגשה משלו:
///
/// 1. **תוצאות ממנוע החיפוש** (`search_engine`) — המנוע מסמן את ההתאמות
///    בתגי הדגשה בתוך ה-HTML שהוא מחזיר. הצד של Dart רק מפרסר את התגים
///    ל-[InlineSpan] באמצעות [fromHighlightedHtml]. אין כל לוגיקת התאמה בצד
///    האפליקציה — המנוע אחראי לכך.
///
/// 2. **חיפוש מקומי בתוך ספר פתוח** — חיפוש ליטרלי של מחרוזת שלמה
///    (ראה `section_search_utils`). ההדגשה מסמנת את הופעות השאילתה כפי
///    שהיא, תוך סובלנות לניקוד וטעמים, באמצעות [highlightLiteral].
class SnippetBuilder {
  SnippetBuilder._();

  /// תגי HTML שהמנוע עוטף בהם התאמות חיפוש.
  ///
  /// `font` (עם צבע) הוא הפורמט ש-`SnippetGenerator` של Tantivy מפיק.
  /// `mark` נתמך כחלופה סמנטית. תגי עיצוב של תוכן הספר עצמו (כגון `b`,
  /// `i`, `h2`) אינם נחשבים הדגשה ומוצגים כטקסט רגיל.
  static const Set<String> _highlightTags = {'font', 'mark'};

  static final RegExp _whitespace = RegExp(r'\s+');

  /// מחלקת תווים של אותיות עבריות — לבדיקת גבולות מילה.
  /// תואם את `_isHebrewLetter` בחיפוש המקומי: אותיות בסיס (U+05D0–U+05EA),
  /// ליגטורות וגרשיים (U+05F0–U+05F4) וצורות תצוגה (U+FB1D–U+FB4F).
  static const String _hebrewLetters = 'א-תװ-״יִ-ﭏ';

  /// תווי ניקוד וטעמים אופציונליים בין אותיות בטקסט המוצג (U+0591–U+05C7).
  static const String _optionalMarks = '[֑-ׇ]*';

  /// ממיר HTML מודגש שמגיע ממנוע החיפוש לרשימת [InlineSpan].
  ///
  /// טקסט שעטוף בתג הדגשה ([_highlightTags]) מקבל את [highlightStyle];
  /// שאר הטקסט מקבל את [defaultStyle]. תגי HTML אחרים מנוקים ומוצג רק
  /// תוכן הטקסט שלהם.
  static List<InlineSpan> fromHighlightedHtml({
    required String html,
    required TextStyle defaultStyle,
    required TextStyle highlightStyle,
  }) {
    final body = html_parser.parse(html).body;
    if (body == null) {
      return [TextSpan(text: '', style: defaultStyle)];
    }

    final spans = <InlineSpan>[];
    _appendHtmlSpans(
      body,
      highlighted: false,
      spans: spans,
      defaultStyle: defaultStyle,
      highlightStyle: highlightStyle,
    );

    if (spans.isEmpty) {
      return [TextSpan(text: '', style: defaultStyle)];
    }
    return spans;
  }

  static void _appendHtmlSpans(
    dom.Node node, {
    required bool highlighted,
    required List<InlineSpan> spans,
    required TextStyle defaultStyle,
    required TextStyle highlightStyle,
  }) {
    for (final child in node.nodes) {
      if (child is dom.Text) {
        final text = child.text.replaceAll(_whitespace, ' ');
        if (text.isEmpty) continue;
        spans.add(TextSpan(
          text: text,
          style: highlighted ? highlightStyle : defaultStyle,
        ));
      } else if (child is dom.Element) {
        final isHighlight =
            highlighted || _highlightTags.contains(child.localName);
        _appendHtmlSpans(
          child,
          highlighted: isHighlight,
          spans: spans,
          defaultStyle: defaultStyle,
          highlightStyle: highlightStyle,
        );
      }
    }
  }

  /// מדגיש הופעות ליטרליות של [query] בטקסט מקומי [plainText].
  ///
  /// ההתאמה סובלנית לניקוד/טעמים ולחילופי גרשיים עבריים/לועזיים, ומכבדת
  /// גבולות מילה — בהתאם לסמנטיקת החיפוש המקומי (`_containsWholeWord`).
  static List<InlineSpan> highlightLiteral({
    required String plainText,
    required String query,
    required TextStyle defaultStyle,
    required TextStyle highlightStyle,
  }) {
    final pattern = _literalQueryPattern(query);
    if (plainText.isEmpty || pattern == null) {
      return [TextSpan(text: plainText, style: defaultStyle)];
    }

    final matches = pattern
        .allMatches(plainText)
        .where((match) => match.end > match.start)
        .toList(growable: false);
    if (matches.isEmpty) {
      return [TextSpan(text: plainText, style: defaultStyle)];
    }

    final spans = <InlineSpan>[];
    var position = 0;
    for (final match in matches) {
      if (match.start > position) {
        spans.add(TextSpan(
          text: plainText.substring(position, match.start),
          style: defaultStyle,
        ));
      }
      spans.add(TextSpan(
        text: plainText.substring(match.start, match.end),
        style: highlightStyle,
      ));
      position = match.end;
    }
    if (position < plainText.length) {
      spans.add(TextSpan(
        text: plainText.substring(position),
        style: defaultStyle,
      ));
    }
    return spans;
  }

  /// מחזיר קטע טקסט סביב ההופעה הליטרלית הראשונה של [query], מוגבל
  /// ל-[maxChars] תווים, עם חיתוך בגבולות מילים והוספת "..." בקצוות.
  static String buildExcerptText({
    required String fullText,
    required String query,
    required int maxChars,
  }) {
    final text = fullText.replaceAll(_whitespace, ' ').trim();
    if (text.length <= maxChars) return text;

    int findWordEnd(int fromIndex) {
      if (fromIndex >= text.length) return text.length;
      final nextSpace = text.indexOf(' ', fromIndex);
      return nextSpace != -1 ? nextSpace : text.length;
    }

    int findWordStart(int fromIndex) {
      if (fromIndex <= 0) return 0;
      final lastSpace = text.lastIndexOf(' ', fromIndex);
      return lastSpace != -1 ? lastSpace + 1 : 0;
    }

    final pattern = _literalQueryPattern(query);
    final anchor = pattern?.firstMatch(text);
    if (anchor == null) {
      final end = findWordEnd(maxChars);
      final suffix = end < text.length ? ' ...' : '';
      return '${text.substring(0, end)}$suffix';
    }

    final len = text.length;
    var start = (anchor.start - (maxChars ~/ 3)).clamp(0, len);
    var end = (start + maxChars).clamp(0, len);
    if (end - start < maxChars) {
      start = (end - maxChars).clamp(0, len);
    }

    start = findWordStart(start);
    end = findWordEnd(end);

    final prefix = start > 0 ? '... ' : '';
    final suffix = end < len ? ' ...' : '';
    return '$prefix${text.substring(start, end)}$suffix';
  }

  /// בונה רגקס להתאמה ליטרלית של [query], סובלני לניקוד וגבולות מילה.
  /// מחזיר `null` אם השאילתה ריקה.
  static RegExp? _literalQueryPattern(String query) {
    final words = query.trim().split(_whitespace).where((w) => w.isNotEmpty);
    final wordPatterns = words.map(_charwisePattern).toList(growable: false);
    if (wordPatterns.isEmpty) return null;

    final phrase = wordPatterns.join(r'\s+');
    return RegExp(
      '(?<![$_hebrewLetters])(?:$phrase)(?![$_hebrewLetters])',
      caseSensitive: false,
      unicode: true,
    );
  }

  /// בונה תבנית לזיהוי מילה בודדת, עם ניקוד אופציונלי בין התווים והתאמת
  /// גרשיים לועזיים (`"`/`'`) גם לעבריים (`״`/`׳`).
  static String _charwisePattern(String word) {
    final buffer = StringBuffer();
    for (final char in word.split('')) {
      if (char == '"') {
        buffer.write('["״]');
      } else if (char == "'") {
        buffer.write("['׳]");
      } else {
        buffer.write(RegExp.escape(char));
      }
      buffer.write(_optionalMarks);
    }
    return buffer.toString();
  }
}

import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:otzaria/search/utils/literal_search_pattern.dart';

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
        spans.add(
          TextSpan(
            text: text,
            style: highlighted ? highlightStyle : defaultStyle,
          ),
        );
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

  /// מחלץ את המונחים שהמנוע סימן כהתאמות (תוכן תגי [_highlightTags]) מתוך
  /// [html]. משמש להדגשת ההתאמות האמיתיות על גבי דפי PDF.
  static Set<String> extractHighlightedTerms(String html) {
    final body = html_parser.parse(html).body;
    if (body == null) return const {};
    final terms = <String>{};
    _collectHighlightedTerms(body, highlighted: false, terms: terms);
    return terms;
  }

  static void _collectHighlightedTerms(
    dom.Node node, {
    required bool highlighted,
    required Set<String> terms,
  }) {
    for (final child in node.nodes) {
      if (child is dom.Text) {
        if (!highlighted) continue;
        final text = child.text.replaceAll(_whitespace, ' ').trim();
        if (text.isNotEmpty) terms.add(text);
      } else if (child is dom.Element) {
        _collectHighlightedTerms(
          child,
          highlighted: highlighted || _highlightTags.contains(child.localName),
          terms: terms,
        );
      }
    }
  }

  /// מחלץ טקסט גולמי מ-HTML של המנוע (מסיר תגים ומנרמל רווחים), לצורך
  /// הדגשה-מחדש בצד האפליקציה בעקביות עם פאנל הקריאה.
  static String htmlToPlainText(String html) {
    final body = html_parser.parse(html).body;
    return (body?.text ?? '').replaceAll(_whitespace, ' ').trim();
  }

  /// בונה [InlineSpan] מטקסט גולמי [plainText] וטווחי הדגשה [ranges]
  /// (זוגות [start, end]). משמש להדגשה עקבית עם פאנל הקריאה בסרגל התוצאות.
  static List<InlineSpan> spansFromRanges({
    required String plainText,
    required List<List<int>> ranges,
    required TextStyle defaultStyle,
    required TextStyle highlightStyle,
  }) {
    if (plainText.isEmpty || ranges.isEmpty) {
      return [TextSpan(text: plainText, style: defaultStyle)];
    }
    final spans = <InlineSpan>[];
    var position = 0;
    for (final range in ranges) {
      final start = range[0];
      final end = range[1];
      if (start < position || start >= end || end > plainText.length) continue;
      if (start > position) {
        spans.add(
          TextSpan(
            text: plainText.substring(position, start),
            style: defaultStyle,
          ),
        );
      }
      spans.add(
        TextSpan(
          text: plainText.substring(start, end),
          style: highlightStyle,
        ),
      );
      position = end;
    }
    if (position < plainText.length) {
      spans.add(
        TextSpan(text: plainText.substring(position), style: defaultStyle),
      );
    }
    return spans;
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
    final pattern = buildLiteralPattern(query)?.regExp;
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
        spans.add(
          TextSpan(
            text: plainText.substring(position, match.start),
            style: defaultStyle,
          ),
        );
      }
      spans.add(
        TextSpan(
          text: plainText.substring(match.start, match.end),
          style: highlightStyle,
        ),
      );
      position = match.end;
    }
    if (position < plainText.length) {
      spans.add(
        TextSpan(
          text: plainText.substring(position),
          style: defaultStyle,
        ),
      );
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

    final pattern = buildLiteralPattern(query)?.regExp;
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
}

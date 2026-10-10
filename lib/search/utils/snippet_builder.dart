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

  static final RegExp _lineBreakTag = RegExp(
    r'<br\s*/?>',
    caseSensitive: false,
  );

  /// תו פרטי שמחליף `<br>` עד אחרי כיווץ הרווחים — רק מעבר שורה שהמנוע
  /// סימן נשמר, ושאר הרווחים (כולל `\n` בתוך טקסט) מתכווצים כרגיל.
  static const String _lineBreakMark = '\uE000';

  static String _withLineBreakMarks(String html) =>
      html.replaceAll(_lineBreakTag, _lineBreakMark);

  /// מכווץ רווחים ומחזיר את סימוני המעבר כמעבר שורה אמיתי, בלי רווח סביבו.
  static String _collapseWhitespace(String text) => text
      .replaceAll(_whitespace, ' ')
      .replaceAll(RegExp(' ?$_lineBreakMark ?'), '\n');

  /// ממיר HTML מודגש שמגיע ממנוע החיפוש לרשימת [InlineSpan].
  ///
  /// טקסט שעטוף בתג הדגשה ([_highlightTags]) מקבל את [highlightStyle];
  /// שאר הטקסט מקבל את [defaultStyle]. תגי HTML אחרים מנוקים ומוצג רק
  /// תוכן הטקסט שלהם. [markStyle], כשניתן, מחליף את [highlightStyle] בתג
  /// `mark` בלבד — שבו המנוע מסמן קטע לפי עניין.
  static List<InlineSpan> fromHighlightedHtml({
    required String html,
    required TextStyle defaultStyle,
    required TextStyle highlightStyle,
    TextStyle? markStyle,
  }) {
    final body = html_parser.parse(_withLineBreakMarks(html)).body;
    if (body == null) {
      return [TextSpan(text: '', style: defaultStyle)];
    }

    final spans = <InlineSpan>[];
    _appendHtmlSpans(
      body,
      style: defaultStyle,
      spans: spans,
      highlightStyle: highlightStyle,
      markStyle: markStyle ?? highlightStyle,
    );

    if (spans.isEmpty) {
      return [TextSpan(text: '', style: defaultStyle)];
    }
    return spans;
  }

  /// [style] הוא הסגנון שהורש; הדגשה חיצונית קובעת גם לתגים שבתוכה.
  static void _appendHtmlSpans(
    dom.Node node, {
    required TextStyle style,
    required List<InlineSpan> spans,
    required TextStyle highlightStyle,
    required TextStyle markStyle,
    bool highlighted = false,
  }) {
    for (final child in node.nodes) {
      if (child is dom.Text) {
        final text = _collapseWhitespace(child.text);
        if (text.isEmpty) continue;
        spans.add(TextSpan(text: text, style: style));
      } else if (child is dom.Element) {
        final tag = child.localName;
        final opens = !highlighted && _highlightTags.contains(tag);
        _appendHtmlSpans(
          child,
          style: !opens
              ? style
              : tag == 'mark'
              ? markStyle
              : highlightStyle,
          spans: spans,
          highlightStyle: highlightStyle,
          markStyle: markStyle,
          highlighted: highlighted || opens,
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
    final body = html_parser.parse(_withLineBreakMarks(html)).body;
    return _collapseWhitespace(body?.text ?? '').trim();
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
  /// ההתאמה סובלנית לניקוד/טעמים ולחילופי גרשיים עבריים/לועזיים.
  /// [wholeWord] חייב להיות זהה לזה שאיתו נמצאו התוצאות, אחרת תוצאה תוצג
  /// בלי הדגשה.
  static List<InlineSpan> highlightLiteral({
    required String plainText,
    required String query,
    required TextStyle defaultStyle,
    required TextStyle highlightStyle,
    bool wholeWord = true,
  }) {
    final pattern = buildLiteralPattern(query, wholeWord: wholeWord)?.regExp;
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
  ///
  /// [anchorOf] מקבל את הטקסט המנורמל ומחזיר את תחילת ההתאמה במקום התבנית
  /// הליטרלית; null ממנו נופל לתבנית הליטרלית.
  static String buildExcerptText({
    required String fullText,
    required String query,
    required int maxChars,
    bool wholeWord = true,
    int? Function(String text)? anchorOf,
  }) {
    final text = fullText
        .replaceAllMapped(
          _whitespace,
          (match) => match[0]!.contains('\n') ? '\n' : ' ',
        )
        .trim();
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

    final anchor =
        anchorOf?.call(text) ??
        buildLiteralPattern(
          query,
          wholeWord: wholeWord,
        )?.regExp.firstMatch(text)?.start;
    if (anchor == null) {
      final end = findWordEnd(maxChars);
      final suffix = end < text.length ? ' ...' : '';
      return '${text.substring(0, end)}$suffix';
    }

    final len = text.length;
    var start = (anchor - (maxChars ~/ 3)).clamp(0, len);
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

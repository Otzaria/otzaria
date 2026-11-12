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

  static final RegExp _spacedLineBreakMark = RegExp(' ?$_lineBreakMark ?');

  /// מכווץ רווחים ומחזיר את סימוני המעבר כמעבר שורה אמיתי, בלי רווח סביבו.
  static String _collapseWhitespace(String text) {
    final collapsed = text.replaceAll(_whitespace, ' ');
    // רוב קטעי הטקסט בלי <br>, ואז אין סימון להחליף.
    if (!collapsed.contains(_lineBreakMark)) return collapsed;
    return collapsed.replaceAll(_spacedLineBreakMark, '\n');
  }

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
      defaultStyle: defaultStyle,
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
    required TextStyle defaultStyle,
    required List<InlineSpan> spans,
    required TextStyle highlightStyle,
    required TextStyle markStyle,
    bool highlighted = false,
    bool inNote = false,
    bool inMarker = false,
  }) {
    for (final child in node.nodes) {
      if (child is dom.Text) {
        final text = _collapseWhitespace(child.text);
        if (text.isEmpty) continue;
        spans.add(
          TextSpan(
            text: text,
            style: _annotationStyle(
              style,
              defaultStyle,
              note: inNote,
              marker: inMarker,
            ),
          ),
        );
      } else if (child is dom.Element) {
        final tag = child.localName;
        final opens = !highlighted && _highlightTags.contains(tag);
        final opensNote =
            tag == 'otzaria-note' &&
            !inNote &&
            _collapseWhitespace(child.text).trim().isNotEmpty;
        final noteStyle = opensNote
            ? _annotationStyle(defaultStyle, defaultStyle, note: true)
            : null;
        if (opensNote) spans.add(TextSpan(text: '[הערה: ', style: noteStyle));
        _appendHtmlSpans(
          child,
          style: !opens
              ? style
              : tag == 'mark'
              ? markStyle
              : highlightStyle,
          defaultStyle: defaultStyle,
          spans: spans,
          highlightStyle: highlightStyle,
          markStyle: markStyle,
          highlighted: highlighted || opens,
          inNote: inNote || opensNote,
          inMarker: inMarker || tag == 'otzaria-note-marker',
        );
        if (opensNote) spans.add(TextSpan(text: ']', style: noteStyle));
      }
    }
  }

  static TextStyle _annotationStyle(
    TextStyle style,
    TextStyle defaultStyle, {
    bool note = false,
    bool marker = false,
  }) {
    if (!note && !marker) return style;
    final size = style.fontSize ?? defaultStyle.fontSize;
    return style.copyWith(
      fontStyle: note ? FontStyle.italic : style.fontStyle,
      fontSize: size == null ? null : size * (marker ? 0.75 : 0.9),
    );
  }

  /// מחלץ את המונחים שהמנוע סימן כהתאמות (תוכן תגי [_highlightTags]) מתוך
  /// [html]. משמש להדגשת ההתאמות האמיתיות על גבי דפי PDF.
  static Set<String> extractHighlightedTerms(String html) {
    final simple = simpleHighlightedTerms(html);
    if (simple != null) return simple;
    final body = html_parser.parse(html).body;
    if (body == null) return const {};
    final terms = <String>{};
    _collectHighlightedTerms(body, highlighted: false, terms: terms);
    return terms;
  }

  static final RegExp _plainTag = RegExp(
    r"""<(?:br[\t\n\f\r ]*/?|(font|mark)(?=[\t\n\f\r />])[^<>"']*>([^<]*)</\1)>""",
    caseSensitive: false,
  );
  static final RegExp _engineEntity = RegExp('&(amp|lt|gt|quot|#x27);');

  /// קטע מנוע (טקסט מוברח, `<br>` ותגי הדגשה סביב טקסט) נקרא בלי המפרסר,
  /// שעל 1000 תוצאות חוסם את המסך. null — כשיש בו מבנה אחר.
  @visibleForTesting
  static Set<String>? simpleHighlightedTerms(String html) {
    final terms = <String>{};
    var tagStart = html.indexOf('<');
    while (tagStart != -1) {
      final tag = _plainTag.matchAsPrefix(html, tagStart);
      if (tag == null) return null;
      tagStart = html.indexOf('<', tag.end);
      var raw = tag[2];
      if (raw == null) continue;
      if (raw.contains('\u0000')) return null;
      if (raw.contains('&')) {
        if (raw.replaceAll(_engineEntity, '').contains('&')) return null;
        raw = raw.replaceAllMapped(
          _engineEntity,
          (m) => switch (m[1]) {
            'amp' => '&',
            'lt' => '<',
            'gt' => '>',
            'quot' => '"',
            _ => "'",
          },
        );
      }
      final text = raw.replaceAll(_whitespace, ' ').trim();
      if (text.isNotEmpty) terms.add(text);
    }
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

  /// טקסט ההעתקה עם תוויות הערה; null משאיר תוכן ישן במסלול ההעתקה שלו.
  static String? annotatedPlainText(String html) {
    if (!html.contains('otzaria-note') ||
        html_parser.parse(html).body?.querySelector('otzaria-note') == null) {
      return null;
    }
    return TextSpan(
      children: fromHighlightedHtml(
        html: html,
        defaultStyle: const TextStyle(),
        highlightStyle: const TextStyle(),
      ),
    ).toPlainText().trim();
  }

  /// בונה [InlineSpan] מטקסט גולמי [plainText] וטווחי הדגשה [ranges]
  /// (זוגות [start, end]). משמש להדגשה עקבית עם פאנל הקריאה בסרגל התוצאות.
  /// [sourceHtml] משמר את סימוני ההערות רק כשהטקסט שבו זהה ל-[plainText].
  static List<InlineSpan> spansFromRanges({
    required String plainText,
    required List<List<int>> ranges,
    required TextStyle defaultStyle,
    required TextStyle highlightStyle,
    String? sourceHtml,
  }) {
    if (plainText.isEmpty) {
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
        TextSpan(text: plainText.substring(start, end), style: highlightStyle),
      );
      position = end;
    }
    if (position < plainText.length) {
      spans.add(
        TextSpan(text: plainText.substring(position), style: defaultStyle),
      );
    }
    if (sourceHtml == null || !sourceHtml.contains('otzaria-note')) {
      return spans;
    }
    return _annotateRanges(sourceHtml, plainText, spans, defaultStyle);
  }

  /// הטווחים נשארים בטקסט המנוע; תווית ההערה נוספת רק אחרי ההדגשה.
  static List<InlineSpan> _annotateRanges(
    String html,
    String plain,
    List<InlineSpan> spans,
    TextStyle defaultStyle,
  ) {
    final body = html_parser.parse(_withLineBreakMarks(html)).body;
    if (body == null) return spans;
    final raw = StringBuffer();
    final annotations = <({int start, int end, bool marker})>[];
    void visit(dom.Node node, {bool inNote = false}) {
      if (node is dom.Text) {
        raw.write(node.text);
        return;
      }
      final tag = node is dom.Element ? node.localName : null;
      final note = tag == 'otzaria-note' && !inNote;
      final marker = tag == 'otzaria-note-marker';
      final start = raw.length;
      for (final child in node.nodes) {
        visit(child, inNote: inNote || note);
      }
      if (note || marker) {
        annotations.add((start: start, end: raw.length, marker: marker));
      }
    }

    visit(body);
    if (annotations.isEmpty) return spans;

    final source = raw.toString();
    final offsets = List<int>.filled(source.length + 1, 0);
    final normalized = StringBuffer();
    var previous = 0;
    void appendLiteral(int end) {
      final target = normalized.length;
      for (var i = previous; i <= end; i++) {
        offsets[i] = target + i - previous;
      }
      normalized.write(source.substring(previous, end));
      previous = end;
    }

    final spaces = RegExp('\\s*$_lineBreakMark\\s*|\\s+');
    for (final match in spaces.allMatches(source)) {
      appendLiteral(match.start);
      normalized.write(match[0]!.contains(_lineBreakMark) ? '\n' : ' ');
      for (var i = match.start + 1; i <= match.end; i++) {
        offsets[i] = normalized.length;
      }
      previous = match.end;
    }
    appendLiteral(source.length);
    final untrimmed = normalized.toString();
    // טקסט שונה, גם אם אורכו זהה, אינו בסיס בטוח להלבשת טווחי המקור.
    if (untrimmed.trim() != plain) return spans;
    final leading = untrimmed.length - untrimmed.trimLeft().length;
    int mapped(int offset) =>
        (offsets[offset] - leading).clamp(0, plain.length);
    final mappedAnnotations = [
      for (final item in annotations)
        if (mapped(item.start) < mapped(item.end))
          (
            start: mapped(item.start),
            end: mapped(item.end),
            marker: item.marker,
          ),
    ];
    final boundaries = <int>{0, plain.length};
    final styled = <({int end, TextStyle style})>[];
    var position = 0;
    for (final span in spans.cast<TextSpan>()) {
      position += span.text!.length;
      boundaries.add(position);
      styled.add((end: position, style: span.style!));
    }
    for (final item in mappedAnnotations) {
      boundaries.addAll([item.start, item.end]);
    }
    final points = boundaries.toList()..sort();
    final result = <InlineSpan>[];
    final noteStyle = _annotationStyle(defaultStyle, defaultStyle, note: true);
    var styleIndex = 0;
    for (var i = 0; i < points.length; i++) {
      final start = points[i];
      for (final item in mappedAnnotations) {
        if (!item.marker && item.end == start) {
          result.add(TextSpan(text: ']', style: noteStyle));
        }
      }
      for (final item in mappedAnnotations) {
        if (!item.marker && item.start == start) {
          result.add(TextSpan(text: '[הערה: ', style: noteStyle));
        }
      }
      if (i == points.length - 1) break;
      while (styled[styleIndex].end <= start) {
        styleIndex++;
      }
      final active = mappedAnnotations.where(
        (item) => item.start <= start && item.end > start,
      );
      result.add(
        TextSpan(
          text: plain.substring(start, points[i + 1]),
          style: _annotationStyle(
            styled[styleIndex].style,
            defaultStyle,
            note: active.any((item) => !item.marker),
            marker: active.any((item) => item.marker),
          ),
        ),
      );
    }
    return result;
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
        TextSpan(text: plainText.substring(position), style: defaultStyle),
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

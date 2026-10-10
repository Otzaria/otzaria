import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/widgets/smart_text/raised_markers.dart';

/// יחסי הגדלים של fwfh ל-`<small>`/`<sup>` ול-`<big>`.
/// זהים בשלושת מסלולי הרינדור כדי ששורות שכנות לא ישנו את גודל הסוגריים.
const double kHtmlSmallerFontScale = 5 / 6;
const double kHtmlLargerFontScale = 6 / 5;

/// ממיר תגי עיצוב פשוטים, סימונים מורמים והדגשות חיפוש ל-[TextSpan].
/// markup שאינו נתמך מחזיר null כדי שהקורא ישתמש ב-HtmlWidget.
class SimpleInlineHtml {
  SimpleInlineHtml._();

  static final RegExp _tagRegex = RegExp(r'<[^>]*>');
  static final RegExp _simpleTagRegex = RegExp(r'^<(/?)([a-zA-Z]+)\s*/?>$');
  static final RegExp _entityRegex = RegExp(
    r'&[a-zA-Z]{2,10};|&#x?[0-9a-fA-F]{1,6};',
  );
  // רווח ASCII בלבד, כמו ב-HTML וב-fwfh: NBSP ו-U+2009 אינם מתכווצים.
  static final RegExp _whitespaceRegex = RegExp(r'[\t\n\f\r ]+');
  static final RegExp _leadingWhitespaceRegex = RegExp(r'^[\t\n\f\r ]+');
  static final RegExp _trailingWhitespaceRegex = RegExp(r'[\t\n\f\r ]+$');

  /// עוגני המפרשים הריקים של שו"ע/טור (`<i data-commentator=…></i>`) — אין
  /// להם תוכן ואין מי שקורא אותם מהעץ המרונדר, ולכן אינם מציירים דבר.
  static final RegExp _emptyDataElementRegex = RegExp(
    r'<i(?: data-[a-z]+="[^"<>]*")+></i>',
  );

  /// span של מקרא על פי המסורה (`mam-kq`, `mam-spi-pe`…) — אין לו עיצוב.
  static final RegExp _mamSpanOpenRegex = RegExp(
    r'^<span class="mam-[a-z-]+">$',
  );

  /// תגי הפתיחה של סימונים מורמים, כפי שנפלטים מ-`_fixFootnoteMarkers`
  /// (מחרוזות קבועות, ולכן השוואה מדויקת). כל span אחר עדיין מפיל ל-HtmlWidget.
  static const String _footnoteMarkerOpen =
      '<span class="$kFootnoteMarkerClass">';
  static const String _raisedSupOpen = '<span class="$kRaisedSupClass">';
  static const String _spanClose = '</span>';

  /// תגי הדגשת החיפוש של `highLight` (text_manipulation.dart), כמחרוזות
  /// מדויקות: שינוי שם פשוט מחזיר את השורות ל-HtmlWidget.
  static final Map<String, _Highlight> _searchHighlightOpens = {
    '<span style="color: red">': _Highlight(_red, null),
    '<span style="color: red; ">': _Highlight(_red, null),
    '<span style="color: blue; background-color: rgba(255, 255, 0, 0.8);">':
        _Highlight(
          const Color(0xFF0000FF),
          _yellowPaint,
        ),
    '<span style="background-color: rgba(255, 255, 0, 0.8); color: black">':
        _Highlight(
          const Color(0xFF000000),
          _yellowPaint,
        ),
  };
  static const Color _red = Color(0xFFFF0000);
  // background ולא backgroundColor — כמו ש-fwfh מצייר background-color.
  // 80% שומר ניגודיות לכחול גם בכהה, ומותיר את הבחירה שמתחת לטקסט נראית.
  static final Paint _yellowPaint = Paint()..color = const Color(0xCCFFFF00);

  /// מנסה להמיר את [html]. מחזיר null אם נדרש HtmlWidget.
  ///
  /// התוצאה (גם null) נשמרת ב-LRU; קלט ריק או תוצאה חריגה אינם נשמרים.
  static TextSpan? tryParse(String html, TextStyle baseStyle) {
    if (html.isEmpty || html.length > _cacheMaxChars) {
      return _tryParseUncached(html, baseStyle);
    }
    // גופן מערכת משתנה מזוהה ברקע ומשנה את fontVariations של הבולד.
    final key = (
      html,
      baseStyle,
      AppFonts.boldFontVariations(baseStyle.fontFamily) != null,
    );
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached.$1;
    }
    final result = _tryParseUncached(html, baseStyle);
    // אומדן לעץ שטוח: כל ילד מחויב כספאן וסגנון, גם אם אין לו סגנון משלו.
    final nodes = 1 + 2 * (result?.children?.length ?? 0);
    if (nodes > _cacheMaxNodes) return result;
    _cache[key] = (result, nodes);
    _cacheChars += html.length;
    _cacheNodes += nodes;
    while (_cacheChars > _cacheMaxChars ||
        _cacheNodes > _cacheMaxNodes ||
        _cache.length > _cacheMaxEntries) {
      final oldestKey = _cache.keys.first;
      final removed = _cache.remove(oldestKey)!;
      _cacheChars -= oldestKey.$1.length;
      _cacheNodes -= removed.$2;
    }
    return result;
  }

  static final LinkedHashMap<(String, TextStyle, bool), (TextSpan?, int)>
  _cache = LinkedHashMap();
  static int _cacheChars = 0;
  static int _cacheNodes = 0;
  static const int _cacheMaxChars = 2 * 1024 * 1024;
  static const int _cacheMaxEntries = 4096;
  static const int _cacheMaxNodes = 32 * 1024;

  static TextSpan? _tryParseUncached(String html, TextStyle baseStyle) {
    if (html.contains('&')) {
      html = html
          .replaceAll('&nbsp;', '\u00A0')
          .replaceAll('&thinsp;', '\u2009');
      if (_entityRegex.hasMatch(html)) return null;
    }
    if (html.contains('<i ')) {
      html = html.replaceAll(_emptyDataElementRegex, '');
    }

    // המקרה הנפוץ ביותר: שורה בלי שום תג.
    if (!html.contains('<')) {
      return TextSpan(text: _trim(html.replaceAll(_whitespaceRegex, ' ')));
    }

    var bold = 0, italic = 0, underline = 0, big = 0, small = 0;
    var footnoteMarkers = 0, raisedSups = 0;
    _Highlight? highlight;
    // איזה סוג span כל `</span>` סוגר — רק שלושת הסוגים שהמסלול מקבל.
    final spanStack = <_SpanKind>[];
    final segments = <_Segment>[];

    TextStyle? styleForCurrent() {
      if (bold == 0 &&
          italic == 0 &&
          underline == 0 &&
          big == 0 &&
          small == 0 &&
          footnoteMarkers == 0 &&
          raisedSups == 0 &&
          highlight == null) {
        return null;
      }
      double? fontSize;
      if (big > 0 || small > 0 || footnoteMarkers > 0 || raisedSups > 0) {
        final base = baseStyle.fontSize ?? 14.0;
        fontSize =
            base *
            math.pow(kHtmlLargerFontScale, big) *
            // raised-sup מוקטן באותו יחס כמו <small>/<sup> — פריטי הגדלים
            // בין המסלולים (ראו התיעוד של kHtmlSmallerFontScale).
            math.pow(kHtmlSmallerFontScale, small + raisedSups) *
            math.pow(kFootnoteMarkerScale, footnoteMarkers);
      }
      final insideMarker = footnoteMarkers > 0 || raisedSups > 0;
      return TextStyle(
        fontWeight: bold > 0 ? FontWeight.bold : null,
        // בולד אמיתי לגופן משתנה — הבסיס יורש דרך Text.rich לספאנים לא-מודגשים.
        fontVariations: bold > 0
            ? AppFonts.boldFontVariations(baseStyle.fontFamily)
            : null,
        fontStyle: (italic > 0 || footnoteMarkers > 0)
            ? FontStyle.italic
            : null,
        decoration: underline > 0 ? TextDecoration.underline : null,
        fontSize: fontSize,
        // גליפי סימון שקופים: תופסים את מקומם בשורה (סדר, בחירה, העתקה),
        // ו-RaisedMarkerOverlay מצייר אותם מורמים — ראו raised_markers.dart.
        color: insideMarker ? const Color(0x00000000) : highlight?.color,
        background: highlight?.background,
      );
    }

    void addText(String raw) {
      if (raw.isEmpty) return;
      // HtmlWidget מכווץ רצפי רווחים לרווח יחיד — משמרים התנהגות זהה.
      segments.add(
        _Segment(raw.replaceAll(_whitespaceRegex, ' '), styleForCurrent()),
      );
    }

    var index = 0;
    for (final match in _tagRegex.allMatches(html)) {
      addText(html.substring(index, match.start));
      index = match.end;

      final rawTag = match[0]!;
      // סימונים מורמים — השוואת מחרוזת מדויקת, בלי פרסור attributes.
      if (rawTag == _footnoteMarkerOpen || rawTag == _raisedSupOpen) {
        final isFootnote = rawTag == _footnoteMarkerOpen;
        spanStack.add(isFootnote ? _SpanKind.footnote : _SpanKind.raisedSup);
        if (isFootnote) {
          footnoteMarkers++;
        } else {
          raisedSups++;
        }
        continue;
      }
      if (_mamSpanOpenRegex.hasMatch(rawTag)) {
        spanStack.add(_SpanKind.plain);
        continue;
      }
      final highlightOpen = _searchHighlightOpens[rawTag];
      if (highlightOpen != null) {
        // הדגשה בתוך הדגשה אינה נפלטת; ירושת הצבע והרקע שם אינה מאומתת.
        if (highlight != null) return null;
        highlight = highlightOpen;
        spanStack.add(_SpanKind.highlight);
        continue;
      }
      if (rawTag == _spanClose) {
        // `</span>` יתום — לא נפתח על-ידי סימון שלנו; span זר כבר היה מפיל
        // את השורה בתג הפתיחה שלו, אז זה markup שבור: נופלים ל-HtmlWidget.
        if (spanStack.isEmpty) return null;
        switch (spanStack.removeLast()) {
          case _SpanKind.footnote:
            footnoteMarkers = math.max(0, footnoteMarkers - 1);
          case _SpanKind.raisedSup:
            raisedSups = math.max(0, raisedSups - 1);
          case _SpanKind.highlight:
            highlight = null;
          case _SpanKind.plain:
            break;
        }
        continue;
      }

      final tagMatch = _simpleTagRegex.firstMatch(rawTag);
      if (tagMatch == null) return null;
      final isClosing = tagMatch[1] == '/';
      final delta = isClosing ? -1 : 1;

      switch (tagMatch[2]!.toLowerCase()) {
        case 'b':
        case 'strong':
          bold = math.max(0, bold + delta);
        case 'i':
        case 'em':
          italic = math.max(0, italic + delta);
        case 'u':
          underline = math.max(0, underline + delta);
        case 'big':
          big = math.max(0, big + delta);
        case 'small':
          small = math.max(0, small + delta);
        case 'br':
          if (!isClosing) segments.add(_Segment.lineBreak());
        default:
          return null;
      }
    }
    addText(html.substring(index));

    _normalizeWhitespace(segments);

    return TextSpan(
      children: [
        for (final segment in segments)
          TextSpan(text: segment.text, style: segment.style),
      ],
    );
  }

  static final RegExp _wholeLineHeadingRegex = RegExp(
    r'^[\t\n\f\r ]*<h([1-6])>(.*)</h\1>[\t\n\f\r ]*$',
    dotAll: true,
  );

  static final RegExp _headingTagRegex = RegExp(r'</?h[1-6]\b');

  /// גודל ברירת המחדל של fwfh לכל רמת כותרת, ביחס לגופן הסובב.
  static const Map<String, double> _defaultHeadingScale = {
    'h1': 2,
    'h2': 1.5,
    'h3': 1.17,
    'h4': 1,
    'h5': 0.83,
    'h6': 0.67,
  };

  /// כותרת שהיא כל השורה (`<hN>` בלי attributes): fwfh מציג אותה כבלוק יחיד
  /// שהשוליים שלו נחתכים בקצות הגוף, ולכן היא טקסט אחד בסגנון [SimpleHeading.style].
  static SimpleHeading? tryParseHeading(String html, TextStyle baseStyle) {
    final style = headingStyle(html, baseStyle);
    if (style == null) return null;
    final match = _wholeLineHeadingRegex.firstMatch(html)!;
    final span = tryParse(match[2]!, style);
    if (span == null || span.toPlainText().isEmpty) return null;
    return SimpleHeading(style, span);
  }

  /// הסגנון שבו fwfh מציג שורה שכולה כותרת, או null כשהשורה אינה כותרת.
  static TextStyle? headingStyle(String html, TextStyle baseStyle) {
    if (!html.contains('<h')) return null;
    final match = _wholeLineHeadingRegex.firstMatch(html);
    if (match == null) return null;
    final content = match[2]!;
    for (
      var tagStart = content.indexOf('<');
      tagStart != -1;
      tagStart = content.indexOf('<', tagStart + 1)
    ) {
      if (_headingTagRegex.matchAsPrefix(content, tagStart) != null) {
        return null;
      }
    }
    final tag = 'h${match[1]}';
    final fontFamily = baseStyle.fontFamily;
    final sizeOverride = AppFonts.headingFontSizeOverride(tag, fontFamily);
    final scale = sizeOverride == null
        ? _defaultHeadingScale[tag]!
        : double.tryParse(sizeOverride.replaceFirst('em', ''));
    if (scale == null) return null;
    final weightOverride = AppFonts.headingFontWeightOverride(tag, fontFamily);
    final weight = weightOverride == null
        ? FontWeight.bold
        : FontWeight.values.firstWhere(
            (w) => w.value == int.tryParse(weightOverride),
            orElse: () => FontWeight.bold,
          );
    return baseStyle.copyWith(
      fontSize: (baseStyle.fontSize ?? 14.0) * scale,
      fontWeight: weight,
      fontVariations:
          baseStyle.fontVariations ??
          AppFonts.boldFontVariations(fontFamily, weight),
    );
  }

  static String _trim(String text) => text
      .replaceFirst(_leadingWhitespaceRegex, '')
      .replaceFirst(_trailingWhitespaceRegex, '');

  /// מדמה את כללי הרווחים של HTML: רווחים צמודים ל-<br> ולקצוות הפסקה נבלעים.
  static void _normalizeWhitespace(List<_Segment> segments) {
    // רווח שאחרי רווח מתכווץ גם מעבר לגבול תג (`<b>א </b> ב`).
    var afterSpace = false;
    for (final segment in segments) {
      if (segment.isBreak) {
        afterSpace = false;
        continue;
      }
      if (afterSpace && segment.text.startsWith(' ')) {
        segment.text = segment.text.substring(1);
      }
      if (segment.text.isNotEmpty) afterSpace = segment.text.endsWith(' ');
    }
    for (var i = 0; i < segments.length; i++) {
      if (!segments[i].isBreak) continue;
      if (i > 0 && !segments[i - 1].isBreak) {
        segments[i - 1].text = segments[i - 1].text.replaceFirst(
          _trailingWhitespaceRegex,
          '',
        );
      }
      if (i + 1 < segments.length && !segments[i + 1].isBreak) {
        segments[i + 1].text = segments[i + 1].text.replaceFirst(
          _leadingWhitespaceRegex,
          '',
        );
      }
    }

    while (segments.isNotEmpty) {
      final first = segments.first;
      first.text = first.isBreak
          ? ''
          : first.text.replaceFirst(_leadingWhitespaceRegex, '');
      if (first.text.isNotEmpty) break;
      segments.removeAt(0);
    }
    while (segments.isNotEmpty) {
      final last = segments.last;
      last.text = last.isBreak
          ? ''
          : last.text.replaceFirst(_trailingWhitespaceRegex, '');
      if (last.text.isNotEmpty) break;
      segments.removeLast();
    }
    segments.removeWhere((segment) => segment.text.isEmpty);
  }
}

/// שורת כותרת שלמה: [span] מוצג ב-[style] של רמת הכותרת.
class SimpleHeading {
  final TextStyle style;
  final TextSpan span;

  const SimpleHeading(this.style, this.span);
}

enum _SpanKind { footnote, raisedSup, highlight, plain }

class _Highlight {
  final Color color;
  final Paint? background;

  const _Highlight(this.color, this.background);
}

class _Segment {
  String text;
  final TextStyle? style;
  final bool isBreak;

  _Segment(this.text, this.style) : isBreak = false;
  _Segment.lineBreak() : text = '\n', style = null, isBreak = true;
}

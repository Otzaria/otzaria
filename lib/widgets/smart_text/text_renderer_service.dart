import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/smart_text/render_settings.dart';

/// שירות מרכזי לעיבוד טקסט
///
/// מחלקה זו מרכזת את כל הלוגיקה של עיבוד טקסט לפני הצגתו,
/// כולל הסרת ניקוד, טעמים, החלפת שמות קדושים, והדגשת חיפוש.
class TextRendererService {
  /// מעבד טקסט לפי הגדרות הרינדור
  ///
  /// [rawText] - הטקסט המקורי
  /// [settings] - הגדרות הרינדור
  ///
  /// מחזיר את הטקסט המעובד כ-HTML מוכן להצגה
  static String processText(String rawText, RenderSettings settings) {
    String processed = rawText;

    // 0. תיקון סדר סימוני הערות (<sup>) ב-RTL
    processed = _fixFootnoteMarkers(processed);
    // 0b. הסתרת טקסט ההערות המודפסות בתוך השורה (למשל "מ: ...")
    processed = _hideInlineFootnotes(processed);

    // 1. הסרת טעמים (אם נדרש)
    if (settings.removeTeamim) {
      processed = utils.removeTeamim(processed);
    }

    // 2. הסרת ניקוד (אם נדרש)
    if (settings.removeNikud) {
      processed = utils.removeVolwels(processed);
    }

    // 3. החלפת שמות קדושים (אם נדרש)
    if (settings.replaceHolyNames) {
      processed = utils.replaceHolyNames(processed);
    }

    // 4. הדגשת טקסט חיפוש (אם יש)
    if (settings.searchText.isNotEmpty) {
      processed = utils.highLight(
        processed,
        settings.searchText,
        currentIndex: settings.currentSearchIndex,
        searchOptions: settings.searchOptions,
        alternativeWords: settings.alternativeWords,
        spacingValues: settings.spacingValues,
        isFuzzy: settings.isFuzzySearch,
      );
    }

    // 5. עיצוב סוגריים (אם נדרש)
    if (settings.formatParentheses) {
      processed = utils.formatTextWithParentheses(processed);
    }

    return processed;
  }

  /// מתקן תגי <sup> כדי למנוע היפוך סדר ב-RTL
  ///
  /// כאשר יש מספר תגי <sup> ברצף, האלגוריתם של bidi עלול להציג אותם בסדר הפוך.
  /// הפתרון: בידוד כל <sup> באמצעות סימני בידוד דו־כיווניות (LRI/RLI + PDI)
  /// בהתאם לתוכן (מספרים/לטינית -> LTR, עברית/ערבית -> RTL).
  static String _fixFootnoteMarkers(String text) {
    final supRegex = RegExp(
      r'<sup(\s[^>]*)?>(.*?)</sup>',
      caseSensitive: false,
      dotAll: true,
    );

    return text.replaceAllMapped(supRegex, (match) {
      final attrs = match[1] ?? '';
      final innerHtml = match[2] ?? '';
      final innerText = innerHtml.replaceAll(RegExp(r'<[^>]+>'), '');
      if (innerText.trim().isEmpty) {
        return '';
      }

      final isFootnoteMarker = RegExp(
        r'\bclass\s*=\s*"[^"]*\bfootnote-marker\b[^"]*"',
        caseSensitive: false,
      ).hasMatch(attrs);

      final isSimple = RegExp(r'^[0-9\u0590-\u05FF]+$').hasMatch(innerText);

      if (!isFootnoteMarker && !isSimple) {
        final wrappedInner = _wrapWithBidiIsolate(innerHtml);
        if (identical(wrappedInner, innerHtml)) {
          return match[0]!;
        }
        return '<sup$attrs>$wrappedInner</sup>';
      }

      final converted = _convertToSuperscriptText(innerText);
      return converted;
    });
  }

  static String _hideInlineFootnotes(String text) {
    return text.replaceAllMapped(
      RegExp(
        r'<i\b([^>]*)\bclass="[^"]*\bfootnote\b[^"]*"([^>]*)>.*?</i>',
        caseSensitive: false,
        dotAll: true,
      ),
      (match) => '<span class="footnote-hidden">\u200B</span>',
    );
  }

  static String _wrapWithBidiIsolate(String innerHtml) {
    if (innerHtml.isEmpty) return innerHtml;

    // Skip if already wrapped with isolate marks.
    if (RegExp(r'[\u2066\u2067\u2068]').hasMatch(innerHtml) ||
        innerHtml.contains('\u2069')) {
      return innerHtml;
    }

    final stripped = innerHtml.replaceAll(RegExp(r'<[^>]+>'), '');
    if (stripped.isEmpty) return innerHtml;

    final hasRtl = RegExp(r'[\u0590-\u08FF]').hasMatch(stripped);
    final isolateStart = hasRtl ? '\u2067' /* RLI */ : '\u2066' /* LRI */;
    const isolateEnd = '\u2069'; // PDI

    return '$isolateStart$innerHtml$isolateEnd';
  }

  static String _convertToSuperscriptText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return trimmed;

    final isNumeric = RegExp(r'^[0-9]+$').hasMatch(trimmed);
    final hasRtl = RegExp(r'[\u0590-\u08FF]').hasMatch(trimmed);

    final isolatedText = isNumeric
        ? '<span class="footnote-marker-number">$trimmed</span>'
        : trimmed;

    final isolateStart = hasRtl ? '\u2067' /* RLI */ : '\u2066' /* LRI */;
    const isolateEnd = '\u2069'; // PDI
    final dirMark = hasRtl ? '\u200F' /* RLM */ : '\u200E' /* LRM */;
    return '$dirMark$isolateStart$isolatedText$isolateEnd$dirMark';
  }

  /// עוטף טקסט ב-div עם כיווניות RTL ו-justify
  static String wrapWithRtlDiv(String text) {
    return '<div style="text-align: justify; direction: rtl;">$text</div>';
  }

  /// מעבד ועוטף טקסט בפעולה אחת
  ///
  /// זהו ה-entry point העיקרי לשימוש - מקבל טקסט גולמי והגדרות,
  /// ומחזיר HTML מוכן להצגה ב-HtmlWidget
  static String render(String rawText, RenderSettings settings) {
    final processed = processText(rawText, settings);
    return wrapWithRtlDiv(processed);
  }

  /// ספירת התאמות חיפוש בטקסט
  ///
  /// [text] - הטקסט לחיפוש בו
  /// [searchQuery] - מחרוזת החיפוש
  ///
  /// מחזיר את מספר ההתאמות שנמצאו
  static int countSearchMatches(String text, String searchQuery) {
    return utils.countMatches(text, searchQuery);
  }

  /// הסרת תגי HTML מטקסט
  static String stripHtml(String text) {
    return utils.stripHtmlIfNeeded(text);
  }

  /// קיצור טקסט לאורך מקסימלי
  static String truncate(String text, int maxLength) {
    return utils.truncate(text, maxLength);
  }
}

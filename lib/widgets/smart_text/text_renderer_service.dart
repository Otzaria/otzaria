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

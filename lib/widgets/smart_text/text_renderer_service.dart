import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:otzaria/text_book/utils/inline_notes_utils.dart' as notes;
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
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
  ///
  /// התוצאה ממוזגת ב-LRU לפי (טקסט, הגדרות): שרשרת ה-regex רצה מחדש לכל
  /// קטע נראה בכל build (גלילה = עשרות קריאות לפריים) — המטמון מנטרל את זה.
  static String processText(String rawText, RenderSettings settings) {
    // כשיש חיפוש, מפתח המטמון נושא את גרסת תבנית ההדגשה — כך שכשתבנית
    // מבוססת-אינדקס חדשה מגיעה (אחרי הרינדור עם ה-fallback), הקריאה הבאה
    // מחשבת מחדש במקום להגיש הדגשה ישנה.
    final revision =
        settings.searchText.isEmpty ? 0 : utils.highlightPatternRevision.value;
    final key =
        _RenderCacheKey(rawText, _processingOnlySettings(settings), revision);
    final cached = _renderCache.remove(key);
    if (cached != null) {
      _renderCache[key] = cached;
      return cached;
    }

    final result = _processTextUncached(rawText, settings);

    _renderCache[key] = result;
    _renderCacheChars += rawText.length + result.length;
    while (
        _renderCacheChars > _renderCacheMaxChars && _renderCache.length > 1) {
      final oldestKey = _renderCache.keys.first;
      final oldestValue = _renderCache.remove(oldestKey)!;
      _renderCacheChars -= oldestKey.text.length + oldestValue.length;
    }

    return result;
  }

  static String _processTextUncached(String rawText, RenderSettings settings) {
    String processed = rawText;

    // 0. תיקון סדר סימוני הערות (<sup>) ב-RTL
    processed = _fixFootnoteMarkers(processed);

    // 0b. הסרת גוף הערות inline (<i class="footnote">...</i>) - מוצגות כמפרש בצד.
    processed = notes.stripInlineNotes(processed);

    // 1. הסרת טעמים (אם נדרש)
    if (settings.removeTeamim) {
      processed = utils.removeTeamim(processed);
    }

    // 2. הסרת ניקוד (אם נדרש)
    if (settings.removeNikud) {
      processed = utils.removeVolwels(processed);
    }

    // 2b. הסרת סימני פיסוק (אם נדרש)
    if (settings.removePunctuation) {
      processed = utils.removePunctuation(processed);
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
        searchDistance: settings.searchDistance,
        yellowBackground: settings.highlightYellowBackground,
        partialWordMatch: settings.partialWordHighlight,
      );
    }

    // 5. עיצוב סוגריים (אם נדרש)
    if (settings.formatParentheses) {
      processed = utils.formatTextWithParentheses(processed);
    }

    return processed;
  }

  // RegExps מקומפלים פעם אחת ברמת הקלאס — הקריאות הקודמות יצרו אותם מחדש
  // בכל קריאת processText (ולכל תג <sup> בנפרד), מה שהוסיף עומס CPU משמעותי
  // ברנדור שורות עם הרבה סימוני הערות.
  static final RegExp _supRegex = RegExp(
    r'<sup(\s[^>]*)?>(.*?)</sup>',
    caseSensitive: false,
    dotAll: true,
  );
  static final RegExp _htmlTagRegex = RegExp(r'<[^>]+>');
  static final RegExp _footnoteMarkerClassRegex = RegExp(
    r'\bclass\s*=\s*"[^"]*\bfootnote-marker\b[^"]*"',
    caseSensitive: false,
  );
  static final RegExp _simpleInnerRegex = RegExp(r'^[0-9\u0590-\u05FF]+$');
  static final RegExp _isolateStartRegex = RegExp(r'[\u2066\u2067\u2068]');
  static final RegExp _rtlCharRegex = RegExp(r'[\u0590-\u08FF]');

  /// מתקן תגי <sup> כדי למנוע היפוך סדר ב-RTL
  ///
  /// הבעיה האמיתית אינה bidi של הטקסט: HtmlWidget מממש `<sup>` באמצעות
  /// WidgetSpan, ומנוע Flutter משבץ inline-placeholders בפסקת RTL בסדר
  /// ויזואלי (שמאל→ימין) במקום לוגי. לכן כשיש שני סימוני הערות או יותר
  /// באותה פסקה — ה*תכנים* שלהם מוצגים בסדר הפוך (2 לפני 1), בעוד מיקומי
  /// העוגנים נשארים נכונים. סימון בודד בשורה אינו מושפע.
  ///
  /// הפתרון: sup *מספרי* (עם או בלי class — שניהם משמשים כמרקרים בספרים)
  /// מומר לספרות-עיליות יוניקוד (¹²³…) — טקסט טהור שמוצג מוגבה ומוקטן בכל
  /// הגופנים, ללא WidgetSpan. מרקר לא-מספרי *מסומן* (`class="footnote-marker"`,
  /// למשל אות עברית) נפלט כ-`<span class="footnote-marker-number">` — ה-class
  /// מקבל גופן מוקטן ונטוי גם ב-[SmartTextWidget] (customStylesBuilder) וגם
  /// בפרסר של מצב קריאה רציפה. sup לא-מספרי שאינו מסומן (superscript תוכני,
  /// כגון `<sup>מעלית</sup>`) נשאר sup. בנוסף, התוכן עטוף בסימני בידוד
  /// דו־כיווניות (LRI/RLI + PDI) בהתאם לתוכן כדי שסימונים סמוכים לא יתמזגו.
  static String _fixFootnoteMarkers(String text) {
    // Early-exit מהיר: אם אין בכלל תג <sup> בשורה, מחזירים את הטקסט כפי שהוא
    // בלי לבצע replaceAllMapped (שמקצה StringBuffer גם כשאין התאמות).
    // משתמשים ב-_supRegex.hasMatch כדי לכבד case-insensitivity של ה-regex
    // עצמו (text.contains('<sup') היה מפספס <SUP>/<Sup>).
    if (!_supRegex.hasMatch(text)) return text;

    return text.replaceAllMapped(_supRegex, (match) {
      final attrs = match[1] ?? '';
      final innerHtml = match[2] ?? '';
      final innerText = innerHtml.replaceAll(_htmlTagRegex, '');
      if (innerText.trim().isEmpty) {
        return '';
      }

      final isFootnoteMarker = _footnoteMarkerClassRegex.hasMatch(attrs);
      final isSimple = _simpleInnerRegex.hasMatch(innerText);

      final wrappedInner = _wrapWithBidiIsolate(innerHtml);
      if (!isFootnoteMarker && !isSimple) {
        if (identical(wrappedInner, innerHtml)) {
          return match[0]!;
        }
        return '<sup$attrs>$wrappedInner</sup>';
      }

      // מספר טהור → ספרות-עיליות יוניקוד (מוגבה ומוקטן מטבעו, ללא תגית).
      // חל גם על <sup>1</sup> חשוף בלי class: חלק מספרי ההערות-inline
      // מקודדים כך את המרקרים, וההמרה חסרת-אובדן גם ל-superscript מספרי אמיתי.
      final trimmedInner = innerText.trim();
      if (_digitsOnlyRegex.hasMatch(trimmedInner)) {
        final superscript = trimmedInner.split('').map((d) {
          return _superscriptDigits[d]!;
        }).join();
        return _wrapWithBidiIsolate(superscript);
      }

      // תוכן לא-מספרי: רק מרקר *מסומן* (class="footnote-marker") הופך ל-span.
      if (isFootnoteMarker) {
        return '<span class="footnote-marker-number">$wrappedInner</span>';
      }

      // sup פשוט שאינו מרקר (למשל <sup>מעלית</sup> מייבוא Word) נשאר sup —
      // שומר הגבהה אמיתית. נשאר חשוף לבאג ההיפוך רק אם יופיעו כמה כאלה
      // באותה פסקה (נדיר עבור superscript תוכני).
      return '<sup>$wrappedInner</sup>';
    });
  }

  static final RegExp _digitsOnlyRegex = RegExp(r'^[0-9]+$');

  /// מיפוי ספרה רגילה → ספרת-עילית יוניקוד. 1–3 בבלוק Latin-1 (U+00B9/B2/B3),
  /// השאר בבלוק Superscripts (U+2070, U+2074–U+2079) — אלה נקודות הקוד
  /// הקנוניות; אין חלופות ל-1–3 בבלוק U+2070.
  static const Map<String, String> _superscriptDigits = {
    '0': '⁰',
    '1': '¹',
    '2': '²',
    '3': '³',
    '4': '⁴',
    '5': '⁵',
    '6': '⁶',
    '7': '⁷',
    '8': '⁸',
    '9': '⁹',
  };

  static String _wrapWithBidiIsolate(String innerHtml) {
    if (innerHtml.isEmpty) return innerHtml;

    // Skip if already wrapped with isolate marks.
    if (_isolateStartRegex.hasMatch(innerHtml) ||
        innerHtml.contains('\u2069')) {
      return innerHtml;
    }

    final stripped = innerHtml.replaceAll(_htmlTagRegex, '');
    if (stripped.isEmpty) return innerHtml;

    final hasRtl = _rtlCharRegex.hasMatch(stripped);
    final isolateStart = hasRtl ? '\u2067' /* RLI */ : '\u2066' /* LRI */;
    const isolateEnd = '\u2069'; // PDI

    return '$isolateStart$innerHtml$isolateEnd';
  }

  /// עוטף טקסט ב-div עם כיווניות RTL ו-justify
  static String wrapWithRtlDiv(String text, {bool justifyText = true}) {
    final textAlign = justifyText ? 'justify' : 'right';
    return '<div style="text-align: $textAlign; direction: rtl;">$text</div>';
  }

  /// מנרמל את ההגדרות לשדות שבאמת משפיעים על [processText] (שדות עיצוב כמו
  /// גופן/יישור נשארים בברירת מחדל) — אחרת שינוי גודל גופן מרוקן את המטמון.
  /// חובה לעדכן כאן כל שדה חדש ש-processText יתחיל להשתמש בו.
  static RenderSettings _processingOnlySettings(RenderSettings settings) {
    return RenderSettings(
      removeNikud: settings.removeNikud,
      removePunctuation: settings.removePunctuation,
      removeTeamim: settings.removeTeamim,
      replaceHolyNames: settings.replaceHolyNames,
      searchText: settings.searchText,
      currentSearchIndex: settings.currentSearchIndex,
      searchOptions: settings.searchOptions,
      alternativeWords: settings.alternativeWords,
      spacingValues: settings.spacingValues,
      isFuzzySearch: settings.isFuzzySearch,
      searchDistance: settings.searchDistance,
      formatParentheses: settings.formatParentheses,
      highlightYellowBackground: settings.highlightYellowBackground,
      partialWordHighlight: settings.partialWordHighlight,
    );
  }

  // המטמון של processText, חסום לפי סך תווים.
  static final LinkedHashMap<_RenderCacheKey, String> _renderCache =
      LinkedHashMap<_RenderCacheKey, String>();
  static int _renderCacheChars = 0;
  static const int _renderCacheMaxChars = 4 * 1024 * 1024;

  /// מעבד ועוטף טקסט בפעולה אחת
  ///
  /// זהו ה-entry point העיקרי לשימוש - מקבל טקסט גולמי והגדרות,
  /// ומחזיר HTML מוכן להצגה ב-HtmlWidget
  static String render(String rawText, RenderSettings settings) {
    final processed = processText(rawText, settings);
    return wrapWithRtlDiv(processed, justifyText: settings.justifyText);
  }

  @visibleForTesting
  static void clearRenderCacheForTesting() {
    _renderCache.clear();
    _renderCacheChars = 0;
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

class _RenderCacheKey {
  final String text;
  final RenderSettings settings;
  final int revision;

  @override
  final int hashCode;

  _RenderCacheKey(this.text, this.settings, this.revision)
      : hashCode = Object.hash(text, settings, revision);

  @override
  bool operator ==(Object other) =>
      other is _RenderCacheKey &&
      hashCode == other.hashCode &&
      text == other.text &&
      revision == other.revision &&
      settings == other.settings;
}

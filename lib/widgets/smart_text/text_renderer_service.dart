import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:otzaria/text_book/utils/inline_notes_utils.dart' as notes;
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/smart_text/raised_markers.dart';
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
    final revision = settings.searchText.isEmpty
        ? 0
        : utils.highlightPatternRevision.value;
    final key = _RenderCacheKey(
      rawText,
      _processingOnlySettings(settings),
      revision,
    );
    final cached = _renderCache.remove(key);
    if (cached != null) {
      _renderCache[key] = cached;
      return cached;
    }

    final result = _processTextUncached(rawText, settings);

    _renderCache[key] = result;
    _renderCacheChars += rawText.length + result.length;
    while (_renderCacheChars > _renderCacheMaxChars &&
        _renderCache.length > 1) {
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

    // 0a. המרת טקסט תחתי (<sub>) לטקסט טהור — ראו _fixSubscripts.
    processed = _fixSubscripts(processed);

    // 0b. הסרת גוף הערות inline (<i class="footnote">...</i>) - מוצגות כמפרש בצד.
    processed = notes.stripInlineNotes(processed);

    // 1+2. טעמים וניקוד — בנפרד, כדי ש"בלי ניקוד, עם טעמים" יהיה אפשרי.
    processed = utils.removeMarks(
      processed,
      nikud: settings.removeNikud,
      teamim: settings.removeTeamim,
    );

    // 2b. הסרת סימני פיסוק (אם נדרש)
    if (settings.removePunctuation) {
      processed = utils.removePunctuation(processed);
    }

    // 3. החלפת שמות קדושים (אם נדרש)
    if (settings.replaceHolyNames) {
      processed = utils.replaceHolyNames(
        processed,
        style: settings.holyNameStyle,
      );
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
        matchPolicy: settings.matchPolicy,
        isSearchResultLine: settings.isSearchResultLine,
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
  static final RegExp _isolateStartRegex = RegExp(r'[\u2066\u2067\u2068]');
  static final RegExp _rtlCharRegex = RegExp(r'[\u0590-\u08FF]');

  /// מתקן תגי <sup> כדי למנוע היפוך סדר ב-RTL ולאפשר הצגה מורמת אמיתית
  ///
  /// הבעיה האמיתית אינה bidi של הטקסט: HtmlWidget מממש `<sup>` באמצעות
  /// WidgetSpan, ומנוע Flutter משבץ inline-placeholders בפסקת RTL בסדר
  /// ויזואלי (שמאל→ימין) במקום לוגי. לכן כשיש שני סימוני הערות או יותר
  /// באותה פסקה — ה*תכנים* שלהם מוצגים בסדר הפוך (2 לפני 1), בעוד מיקומי
  /// העוגנים נשארים נכונים. סימון בודד בשורה אינו מושפע.
  ///
  /// הפתרון: sup פשוט (מספרי או לא) נפלט כ-span טקסט טהור ללא WidgetSpan,
  /// בשני טעמים ששומרים על המטריקות המקוריות של כל אחד:
  ///   * מרקר הערה (`class="footnote-marker"`) → `footnote-marker-number`,
  ///     מוקטן ל-0.75em ונטוי.
  ///   * sup חשוף — אות הפניה מקובץ משתמש או superscript תוכני
  ///     (`<sup>מעלית</sup>`) → `raised-sup`, מוקטן ל-5/6 בלי נטייה, כמו
  ///     שה-`<sup>` נראה קודם ב-fwfh ובקריאה הרציפה.
  ///
  /// ההרמה הוויזואלית מעל השורה נעשית בציור: [SmartTextWidget] צובע את שני
  /// ה-class-ים שקופים ומצייר את תוכנם מורם דרך RaisedMarkerOverlay — ל-fwfh
  /// אין תמיכה ב-`position`/`top` (הן היו no-op גם קודם, ולכן מרקרי הערות
  /// כלל לא הורמו), ולכן ההרמה חייבת שכבת ציור; ראו raised_markers.dart.
  /// בנוסף, התוכן עטוף בסימני בידוד דו־כיווניות (LRI/RLI + PDI) בהתאם
  /// לתוכן כדי שסימונים סמוכים לא יתמזגו.
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

      final wrappedInner = _wrapWithBidiIsolate(innerHtml);
      final isFootnoteMarker = _footnoteMarkerClassRegex.hasMatch(attrs);

      // sup סמנטי או מעוצב נשאר בנתיב ה-HTML כדי לא לאבד attributes וסגנונות
      // מקוננים שהציור המורם אינו יכול לשחזר מ-TextStyle הבסיסי בלבד.
      if (!isFootnoteMarker &&
          (attrs.trim().isNotEmpty || _htmlTagRegex.hasMatch(innerHtml))) {
        return '<sup$attrs>$wrappedInner</sup>';
      }

      // גם מרקר מספרי נשאר ספרות רגילות בגופן הספר: ⁰⁴–⁹ (בלוק Superscripts)
      // חסרות ברוב גופני המערכת ונפלו לגופן אחר, בשונה מ-¹²³ (issue #1236).
      // מרקר הערה מסומן — 0.75em ונטוי.
      if (isFootnoteMarker) {
        return '<span class="$kFootnoteMarkerClass">$wrappedInner</span>';
      }

      // sup חשוף (אות הפניה מקובץ משתמש, או superscript תוכני) — 5/6 בלי
      // נטייה. גם הוא נפלט כ-span טקסט טהור ולא נשאר `<sup>`: מסלול ה-sup של
      // fwfh בונה WidgetSpan, וזה מה שהפך את הסדר כששני סימונים באותה פסקה.
      return '<span class="$kRaisedSupClass">$wrappedInner</span>';
    });
  }

  static final RegExp _subRegex = RegExp(
    r'<sub(\s[^>]*)?>(.*?)</sub>',
    caseSensitive: false,
    dotAll: true,
  );

  /// ממיר תגי <sub> לטקסט טהור.
  ///
  /// HtmlWidget מממש `<sub>` כ-WidgetSpan עם padding עליון (0.4×fontSize),
  /// ולכן הוא מותח את השורה / נשבר לשורה נפרדת, ואינו נכלל בבחירת טקסט
  /// (SelectableRegion מדלג על WidgetSpan). sub *מספרי* מומר לספרות-תחתיות
  /// יוניקוד (₁₂₃…); לתוכן אחר (למשל עברית) אין גליפים תחתיים — נפלט
  /// כ-`<span class="subscript-text">` שמוקטן ב-CSS ונשאר טקסט נבחר.
  static String _fixSubscripts(String text) {
    if (!_subRegex.hasMatch(text)) return text;

    return text.replaceAllMapped(_subRegex, (match) {
      final innerHtml = match[2] ?? '';
      final innerText = innerHtml.replaceAll(_htmlTagRegex, '');
      if (innerText.trim().isEmpty) {
        return '';
      }

      final trimmedInner = innerText.trim();
      if (_digitsOnlyRegex.hasMatch(trimmedInner)) {
        final subscript = trimmedInner.split('').map((d) {
          return _subscriptDigits[d]!;
        }).join();
        return _wrapWithBidiIsolate(subscript);
      }

      return '<span class="subscript-text">${_wrapWithBidiIsolate(innerHtml)}</span>';
    });
  }

  /// מיפוי ספרה רגילה → ספרת-תחתית יוניקוד (U+2080–U+2089).
  static const Map<String, String> _subscriptDigits = {
    '0': '₀',
    '1': '₁',
    '2': '₂',
    '3': '₃',
    '4': '₄',
    '5': '₅',
    '6': '₆',
    '7': '₇',
    '8': '₈',
    '9': '₉',
  };

  static final RegExp _digitsOnlyRegex = RegExp(r'^[0-9]+$');

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
      holyNameStyle: settings.holyNameStyle,
      searchText: settings.searchText,
      currentSearchIndex: settings.currentSearchIndex,
      searchOptions: settings.searchOptions,
      alternativeWords: settings.alternativeWords,
      spacingValues: settings.spacingValues,
      isFuzzySearch: settings.isFuzzySearch,
      searchDistance: settings.searchDistance,
      matchPolicy: settings.matchPolicy,
      isSearchResultLine: settings.isSearchResultLine,
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
  /// [partialWordMatch] - חייב לשקף את `RenderSettings.partialWordHighlight`
  /// של אותו תוכן, אחרת המונה סוטה ממספר ההדגשות בפועל.
  ///
  /// מחזיר את מספר ההתאמות שנמצאו
  static int countSearchMatches(
    String text,
    String searchQuery, {
    bool partialWordMatch = false,
  }) {
    return utils.countMatches(
      text,
      searchQuery,
      partialWordMatch: partialWordMatch,
    );
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

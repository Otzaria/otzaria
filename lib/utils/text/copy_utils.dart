import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:otzaria/models/books.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:otzaria/core/messages/common_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as text_utils;

class CopyUtils {
  /// מחיל העדפות תצוגה על טקסט שמיועד להעתקה.
  ///
  /// [removeNikud] מסיר ניקוד וטעמים מהעותק בלבד (פעולת "העתק בלי ניקוד",
  /// issue #851) — התצוגה עצמה לא משתנה. ההסרה רצה לפני החלפת שמות הקודש
  /// כדי שההחלפה תפעל על טקסט נקי.
  static String applyCopyPreferences({
    required String text,
    required bool replaceHolyNames,
    text_utils.HolyNameStyle holyNameStyle = text_utils.HolyNameStyle.kufKuf,
    bool removeNikud = false,
    TextDisplayProfile? profile,
  }) {
    if (text.isEmpty) return text;
    // פרופיל מלא (ערוץ ההעתקה / "העתק כ...") מחליף את הדגלים הבודדים.
    if (profile != null) return applyTextDisplayProfile(text, profile);
    var result = text;
    if (removeNikud) {
      result = text_utils.removeVolwels(result);
    }
    if (replaceHolyNames) {
      result = text_utils.replaceHolyNames(result, style: holyNameStyle);
    }
    return result;
  }

  /// מחיל העדפות העתקה על plain text ועל HTML יחד,
  /// ושומר על עקביות ביניהם גם אם ה-HTML מפוצל ע"י תגיות inline.
  static ({String plainText, String htmlText})
  applyCopyPreferencesForClipboard({
    required String plainText,
    required String htmlText,
    required bool replaceHolyNames,
    text_utils.HolyNameStyle holyNameStyle = text_utils.HolyNameStyle.kufKuf,
    bool removeNikud = false,
    TextDisplayProfile? profile,
  }) {
    final processedPlainText = applyCopyPreferences(
      text: plainText,
      replaceHolyNames: replaceHolyNames,
      holyNameStyle: holyNameStyle,
      removeNikud: removeNikud,
      profile: profile,
    );

    if ((!replaceHolyNames && !removeNikud && profile == null) ||
        htmlText.isEmpty) {
      return (plainText: processedPlainText, htmlText: htmlText);
    }

    final processedHtmlText = _applyCopyPreferencesToHtml(
      htmlText: htmlText,
      replaceHolyNames: replaceHolyNames,
      holyNameStyle: holyNameStyle,
      removeNikud: removeNikud,
      profile: profile,
    );

    final normalizedPlainText = _normalizeCopiedText(processedPlainText);
    final normalizedHtmlText = _normalizeCopiedText(
      _extractVisibleTextFromHtml(processedHtmlText),
    );

    if (normalizedHtmlText != normalizedPlainText) {
      return (
        plainText: processedPlainText,
        htmlText: processedPlainText,
      );
    }

    return (
      plainText: processedPlainText,
      htmlText: processedHtmlText,
    );
  }

  /// מחלץ את שם הספר
  static String extractBookName(TextBook book) => book.title.trim();

  /// מחלץ את הנתיב ההיררכי הנוכחי:
  /// סורק תגיות כותרת בתוכן; כשחסרות שורות טעונות, משלים הורים מה-TOC.
  static Future<String> extractCurrentPath(
    TextBook book,
    int currentIndex, {
    List<String>? bookContent,
    bool Function(int)? isLineLoaded,
  }) async {
    var knownPath = '';
    try {
      final fromContent = _extractPathFromContentStrict(
        bookContent,
        currentIndex,
        isLineLoaded,
      );
      knownPath = fromContent.path;
      if (fromContent.complete && knownPath.isNotEmpty) return knownPath;

      final toc = await book.tableOfContents;
      if (toc.isEmpty) return knownPath;

      // בעץ עם דילוג ברמות (h4 אחרי h2) סדר ה-pre-order אינו לפי שורה.
      final entries = flattenToc(toc)
        ..sort(
          (a, b) => a.index != b.index
              ? a.index.compareTo(b.index)
              : a.level.compareTo(b.level),
        );
      final lastByLevel = <int, ({String text, int index})>{};
      var hasKnownHeading = fromContent.firstHeaderIndex == null;
      for (final entry in entries) {
        if (entry.index <= currentIndex) {
          if (entry.index == fromContent.firstHeaderIndex) {
            hasKnownHeading = true;
          }
          lastByLevel.removeWhere((level, _) => level > entry.level);
          if (isBookTitleRoot(entry)) continue;
          final clean = _cleanHtml(entry.text);
          if (clean.isNotEmpty) {
            lastByLevel[entry.level] = (text: clean, index: entry.index);
          }
        } else {
          break;
        }
      }

      if (!hasKnownHeading) return knownPath;
      final levels = lastByLevel.keys.toList()..sort();
      final parts = <String>[];
      for (final level in levels) {
        final header = lastByLevel[level]!;
        // כותרות טעונות נשמרות מהתוכן: ה-TOC עשוי לאחד כמה כותרות באותה שורה.
        if (fromContent.firstHeaderIndex != null &&
            header.index >= fromContent.firstHeaderIndex!) {
          continue;
        }
        parts.add(header.text);
      }
      if (knownPath.isNotEmpty) parts.add(knownPath);
      final result = parts.join(', ');

      if (kDebugMode) {
        debugPrint('CopyUtils: Final path (TOC strict): "$result"');
      }
      return result;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('CopyUtils: ERROR in extractCurrentPath: $e\n$st');
      }
      return knownPath;
    }
  }

  /// גוזר מ-reference של תוצאת חיפוש את חלק הנתיב שאחרי שם הספר, כדי
  /// ש-[formatTextWithHeaders] (שמרכיב "שם ספר, נתיב") לא יכפיל את השם:
  /// המנוע מחזיר לעיתים reference שכבר פותח בשם הספר ("עבודה זרה, דף עג.")
  /// ולעיתים נתיב בלבד ("סימן א").
  static String referencePath({
    required String bookName,
    required String reference,
  }) {
    final ref = reference.trim();
    final book = bookName.trim();
    if (book.isEmpty || ref == book) return ref == book ? '' : ref;
    if (!ref.startsWith(book)) return ref;
    final suffix = ref.substring(book.length);
    if (suffix.isNotEmpty &&
        !suffix.startsWith(',') &&
        suffix.trimLeft() == suffix) {
      return ref;
    }
    var rest = suffix.trimLeft();
    if (rest.startsWith(',')) {
      rest = rest.substring(1).trimLeft();
    }
    return rest;
  }

  /// מעצב טקסט עם כותרות בהתאם להגדרות
  static String formatTextWithHeaders({
    required String originalText,
    required String copyWithHeaders,
    required String copyHeaderFormat,
    required String bookName,
    required String currentPath,
  }) {
    if (copyWithHeaders == 'none') {
      return originalText.trimRight();
    }

    String header;

    if (copyWithHeaders == 'book_name') {
      header = bookName;
    } else if (copyWithHeaders == 'book_and_path') {
      header = currentPath.isNotEmpty ? '$bookName, $currentPath' : bookName;
    } else {
      return originalText;
    }

    if (header.trim().isEmpty) {
      return originalText;
    }

    String result;
    switch (copyHeaderFormat) {
      case 'same_line_after_brackets':
        result = '${originalText.trim()} (${header.trim()})';
        break;
      case 'same_line_after_no_brackets':
        result = '${originalText.trim()} ${header.trim()}';
        break;
      case 'same_line_before_brackets':
        result = '(${header.trim()}) ${originalText.trim()}';
        break;
      case 'same_line_before_no_brackets':
        result = '${header.trim()} ${originalText.trim()}';
        break;
      case 'separate_line_after':
        result = '${originalText.trim()}\n${header.trim()}';
        break;
      case 'separate_line_before':
        result = '${header.trim()}\n${originalText.trim()}';
        break;
      default:
        result = '${originalText.trim()} (${header.trim()})';
        break;
    }
    return result;
  }

  /// יוצר HTML מעוצב להעתקה: שורות הביניים כבלוקים (Enter אמיתי ב-Word),
  /// והשורה האחרונה inline — אחרת ההדבקה מוסיפה Enter מיותר בסופה.
  static String buildStyledHtml({
    required String htmlText,
    required String fontFamily,
    required double fontSize,
  }) {
    final style =
        'font-family: $fontFamily; font-size: ${fontSize}px; direction: rtl;';
    final normalizedText = htmlText.trimRight().replaceAll('\r\n', '\n');
    final lines = normalizedText.split('\n');

    final buffer = StringBuffer();
    for (var i = 0; i < lines.length - 1; i++) {
      final line = lines[i].isEmpty ? '<br>' : lines[i];
      buffer.write('<div dir="rtl" style="$style">$line</div>');
    }
    buffer.write('<span dir="rtl" style="$style">${lines.last}</span>');
    return buffer.toString();
  }

  /// פריט לוח: טקסט פשוט, ובלי [plainTextOnly] גם HTML מעוצב לפי הגופן.
  static DataWriterItem buildClipboardItem({
    required String plainText,
    required String htmlText,
    required String fontFamily,
    required double fontSize,
    bool plainTextOnly = false,
  }) {
    final item = DataWriterItem();
    item.add(Formats.plainText(plainText.trimRight()));
    if (!plainTextOnly) {
      item.add(
        Formats.htmlText(
          buildStyledHtml(
            htmlText: htmlText,
            fontFamily: fontFamily,
            fontSize: fontSize,
          ),
        ),
      );
    }
    return item;
  }

  /// העתקת טקסט מעוצב ללוח עם HTML
  /// מטפל בעיצוב HTML עם גופן וגודל, וכתיבה ללוח עם חיווי באפליקציה.
  /// [plainTextOnly] — טקסט פשוט בלבד, בלי HTML.
  static Future<void> copyStyledToClipboard({
    required String plainText,
    required String htmlText,
    required String fontFamily,
    required double fontSize,
    bool plainTextOnly = false,
  }) async {
    try {
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) {
        UiSnack.show(CommonMessages.clipboardUnavailable);
        return;
      }

      await clipboard.write([
        buildClipboardItem(
          plainText: plainText,
          htmlText: htmlText,
          fontFamily: fontFamily,
          fontSize: fontSize,
          plainTextOnly: plainTextOnly,
        ),
      ]);
      UiSnack.show(
        plainTextOnly
            ? CommonMessages.plainTextCopied
            : CommonMessages.formattedTextCopied,
      );
    } catch (e) {
      UiSnack.showError(CommonMessages.copyErrorWithDetails(e));
    }
  }

  // ------------------------------------------------------------
  //                 HELPERS - STRICT CONTENT PARSING
  // ------------------------------------------------------------

  /// סורקים אחורה מהמיקום הנוכחי ואוספים את שרשרת הכותרות שמעליו,
  /// הקרובה ביותר מכל רמה.
  static ({String path, bool complete, int? firstHeaderIndex})
  _extractPathFromContentStrict(
    List<String>? content,
    int currentIndex,
    bool Function(int)? isLineLoaded,
  ) {
    if (content == null ||
        content.isEmpty ||
        currentIndex < 0 ||
        currentIndex >= content.length) {
      return (path: '', complete: false, firstHeaderIndex: null);
    }
    var complete = true;
    int? firstHeaderIndex;

    final Map<int, String> lastHeaderByLevel = {};
    final hTag = RegExp(r'<h([1-6])[^>]*>(.*?)</h\1>', dotAll: true);

    // סריקה מהמיקום הנוכחי אחורה עד להתחלה
    for (int i = currentIndex; i >= 0; i--) {
      // רמה 2 היא הרדודה ביותר שנאספת, ואחריה אין עוד הורה.
      if (lastHeaderByLevel.containsKey(2)) break;

      final line = content[i];
      if (line.isEmpty && isLineLoaded?.call(i) == false) {
        complete = false;
        break;
      }
      for (final match in hTag.allMatches(line).toList().reversed) {
        try {
          final level = int.parse(match.group(1)!);
          if (level <= 1) continue; // רמה 1 = שם הספר, כבר מכוסה ע"י bookName
          final text = _cleanHtml(match.group(2)!);

          // בסריקה אחורה רק כותרת רדודה מכל מה שנמצא היא הורה; עמוקה שייכת לקטע קודם.
          final isAncestor = lastHeaderByLevel.keys.every((l) => level < l);
          if (isAncestor && text.isNotEmpty) {
            lastHeaderByLevel[level] = text;
            firstHeaderIndex = i;
          }
        } catch (_) {
          // התעלם אם תגית ה-h אינה תקינה
        }
      }
    }

    if (lastHeaderByLevel.isEmpty) {
      return (path: '', complete: complete, firstHeaderIndex: null);
    }

    // הרכבת הנתיב לפי סדר הרמות (1, 2, 3...)
    final sortedLevels = lastHeaderByLevel.keys.toList()..sort();
    final parts = <String>[];
    for (final level in sortedLevels) {
      parts.add(lastHeaderByLevel[level]!);
    }

    final result = parts.join(', ');
    if (kDebugMode) {
      if (result.isNotEmpty) {
        debugPrint(
          'CopyUtils: Final path from CONTENT (strict, full scan): "$result"',
        );
      }
    }
    return (
      path: result,
      complete: complete,
      firstHeaderIndex: firstHeaderIndex,
    );
  }

  /// ניקוי תגיות HTML
  static String _cleanHtml(String s) {
    final noTags = s.replaceAll(RegExp(r'<[^>]*>'), '');
    return noTags.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _applyCopyPreferencesToHtml({
    required String htmlText,
    required bool replaceHolyNames,
    required text_utils.HolyNameStyle holyNameStyle,
    bool removeNikud = false,
    TextDisplayProfile? profile,
  }) {
    if (htmlText.isEmpty ||
        (!replaceHolyNames && !removeNikud && profile == null)) {
      return htmlText;
    }

    final fragment = html_parser.parseFragment(htmlText);
    _applyPreferencesToTextNodes(
      fragment.nodes,
      replaceHolyNames: replaceHolyNames,
      removeNikud: removeNikud,
      holyNameStyle: holyNameStyle,
      profile: profile,
    );
    final container = html_dom.Element.tag('div')..nodes.addAll(fragment.nodes);
    return container.innerHtml;
  }

  static void _applyPreferencesToTextNodes(
    List<html_dom.Node> nodes, {
    required bool replaceHolyNames,
    required bool removeNikud,
    required text_utils.HolyNameStyle holyNameStyle,
    TextDisplayProfile? profile,
  }) {
    for (final node in nodes) {
      if (node.nodeType == html_dom.Node.TEXT_NODE) {
        final currentText = node.text;
        if (currentText != null && currentText.isNotEmpty) {
          node.text = applyCopyPreferences(
            text: currentText,
            replaceHolyNames: replaceHolyNames,
            holyNameStyle: holyNameStyle,
            removeNikud: removeNikud,
            profile: profile,
          );
        }
        continue;
      }

      _applyPreferencesToTextNodes(
        node.nodes,
        replaceHolyNames: replaceHolyNames,
        removeNikud: removeNikud,
        holyNameStyle: holyNameStyle,
        profile: profile,
      );
    }
  }

  /// `<br>` מומר לרווח לפני הפענוח — אחרת אינו תורם תו, וההשוואה מול
  /// ה-plain text נכשלת על כל מעבר שורה ומפילה את ה-HTML.
  static String _extractVisibleTextFromHtml(String htmlText) {
    if (htmlText.isEmpty) {
      return '';
    }

    final withBreaks = htmlText.replaceAll(
      RegExp(r'<br\s*/?>', caseSensitive: false),
      ' ',
    );
    return html_parser.parseFragment(withBreaks).text ?? '';
  }

  static String _normalizeCopiedText(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

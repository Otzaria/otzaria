import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:otzaria/models/books.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:otzaria/core/messages/common_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as text_utils;

class CopyUtils {
  /// מחיל העדפות תצוגה על טקסט שמיועד להעתקה.
  static String applyCopyPreferences({
    required String text,
    required bool replaceHolyNames,
  }) {
    if (text.isEmpty || !replaceHolyNames) {
      return text;
    }

    return text_utils.replaceHolyNames(text);
  }

  /// מחיל העדפות העתקה על plain text ועל HTML יחד,
  /// ושומר על עקביות ביניהם גם אם ה-HTML מפוצל ע"י תגיות inline.
  static ({String plainText, String htmlText})
  applyCopyPreferencesForClipboard({
    required String plainText,
    required String htmlText,
    required bool replaceHolyNames,
  }) {
    final processedPlainText = applyCopyPreferences(
      text: plainText,
      replaceHolyNames: replaceHolyNames,
    );

    if (!replaceHolyNames || htmlText.isEmpty) {
      return (plainText: processedPlainText, htmlText: htmlText);
    }

    final processedHtmlText = _applyCopyPreferencesToHtml(
      htmlText: htmlText,
      replaceHolyNames: replaceHolyNames,
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
  /// 1) ניסיון קפדני מתוך התוכן עצמו: רק תגיות <h1>..<h6>
  /// 2) נפילה ל-TOC: לוקחים את הכותרת האחרונה לכל רמה (1..6) עד currentIndex
  static Future<String> extractCurrentPath(
    TextBook book,
    int currentIndex, {
    List<String>? bookContent,
  }) async {
    try {
      // --- שלב 1: ניסיון קפדני מתוך התוכן ---
      final fromContent = _extractPathFromContentStrict(
        bookContent,
        currentIndex,
      );
      if (fromContent.isNotEmpty) return fromContent;

      // --- שלב 2: נפילה ל-TOC בלבד ---
      final toc = await book.tableOfContents;
      if (toc.isEmpty) return '';

      final Map<int, String> lastByLevel = {};
      for (final entry in toc) {
        if (entry.index <= currentIndex) {
          if (entry.level <= 1) {
            continue; // רמה 1 = שם הספר, כבר מכוסה ע"י bookName
          }
          final clean = _cleanHtml(entry.text);
          if (clean.isNotEmpty) {
            lastByLevel[entry.level] = clean;
          }
        } else {
          break;
        }
      }

      if (lastByLevel.isEmpty) return '';

      final levels = lastByLevel.keys.toList()..sort();
      final parts = <String>[];
      for (final lvl in levels) {
        final txt = lastByLevel[lvl];
        if (txt != null && txt.trim().isNotEmpty) parts.add(txt.trim());
      }
      final result = parts.join(', ');

      if (kDebugMode) {
        debugPrint('CopyUtils: Final path (TOC strict): "$result"');
      }
      return result;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('CopyUtils: ERROR in extractCurrentPath: $e\n$st');
      }
      return '';
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

  /// העתקת טקסט מעוצב ללוח עם HTML
  /// מטפל בעיצוב HTML עם גופן וגודל, וכתיבה ללוח עם חיווי באפליקציה.
  static Future<void> copyStyledToClipboard({
    required String plainText,
    required String htmlText,
    required String fontFamily,
    required double fontSize,
  }) async {
    try {
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) {
        UiSnack.show(CommonMessages.clipboardUnavailable);
        return;
      }

      final htmlContent = buildStyledHtml(
        htmlText: htmlText,
        fontFamily: fontFamily,
        fontSize: fontSize,
      );

      final item = DataWriterItem();
      item.add(Formats.plainText(plainText.trimRight())); // טקסט רגיל כגיבוי
      item.add(Formats.htmlText(htmlContent)); // טקסט עם עיצוב

      await clipboard.write([item]);
      UiSnack.show(CommonMessages.formattedTextCopied);
    } catch (e) {
      UiSnack.showError(CommonMessages.copyErrorWithDetails(e));
    }
  }

  // ------------------------------------------------------------
  //                 HELPERS - STRICT CONTENT PARSING
  // ------------------------------------------------------------

  /// הלוגיקה החדשה: סורקים אחורה מהמיקום הנוכחי עד לתחילת הקובץ,
  /// ואוספים את הכותרת האחרונה (הקרובה ביותר) מכל רמה.
  static String _extractPathFromContentStrict(
    List<String>? content,
    int currentIndex,
  ) {
    if (content == null || content.isEmpty) return '';
    if (currentIndex < 0 || currentIndex >= content.length) return '';

    final Map<int, String> lastHeaderByLevel = {};
    final hTag = RegExp(r'<h([1-6])[^>]*>(.*?)</h\1>', dotAll: true);

    // סריקה מהמיקום הנוכחי אחורה עד להתחלה
    for (int i = currentIndex; i >= 0; i--) {
      // עוצרים רק כשיש שרשרת רציפה מרמה 2 עד הרמה העמוקה שנמצאה
      if (lastHeaderByLevel.isNotEmpty) {
        final maxLevel = lastHeaderByLevel.keys.reduce(
          (a, b) => a > b ? a : b,
        );
        bool hasContiguousChain = true;
        for (int lvl = 2; lvl <= maxLevel; lvl++) {
          if (!lastHeaderByLevel.containsKey(lvl)) {
            hasContiguousChain = false;
            break;
          }
        }
        if (hasContiguousChain) break;
      }

      final line = content[i];
      for (final match in hTag.allMatches(line)) {
        try {
          final level = int.parse(match.group(1)!);
          if (level <= 1) continue; // רמה 1 = שם הספר, כבר מכוסה ע"י bookName
          final text = _cleanHtml(match.group(2)!);

          // שומרים רק את הכותרת הראשונה שנמצאה עבור כל רמה (כי אנחנו הולכים אחורה)
          if (!lastHeaderByLevel.containsKey(level) && text.isNotEmpty) {
            lastHeaderByLevel[level] = text;
          }
        } catch (_) {
          // התעלם אם תגית ה-h אינה תקינה
        }
      }
    }

    if (lastHeaderByLevel.isEmpty) return '';

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
    return result;
  }

  /// ניקוי תגיות HTML
  static String _cleanHtml(String s) {
    final noTags = s.replaceAll(RegExp(r'<[^>]*>'), '');
    return noTags.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _applyCopyPreferencesToHtml({
    required String htmlText,
    required bool replaceHolyNames,
  }) {
    if (htmlText.isEmpty || !replaceHolyNames) {
      return htmlText;
    }

    final fragment = html_parser.parseFragment(htmlText);
    _replaceHolyNamesInTextNodes(fragment.nodes, replaceHolyNames);
    final container = html_dom.Element.tag('div')..nodes.addAll(fragment.nodes);
    return container.innerHtml;
  }

  static void _replaceHolyNamesInTextNodes(
    List<html_dom.Node> nodes,
    bool replaceHolyNames,
  ) {
    for (final node in nodes) {
      if (node.nodeType == html_dom.Node.TEXT_NODE) {
        final currentText = node.text;
        if (currentText != null && currentText.isNotEmpty) {
          node.text = applyCopyPreferences(
            text: currentText,
            replaceHolyNames: replaceHolyNames,
          );
        }
        continue;
      }

      _replaceHolyNamesInTextNodes(node.nodes, replaceHolyNames);
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

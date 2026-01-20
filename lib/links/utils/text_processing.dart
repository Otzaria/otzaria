/// עיבוד טקסט וקישורים inline
library;

import 'package:otzaria/models/links.dart';
import 'encoding.dart';

/// מחלקה לעיבוד טקסט עם קישורים
class TextProcessing {
  
  /// הוספת קישורי inline לטקסט
  static String addInlineLinks(String text, List<Link> links) {
    // בדיקות בטיחות
    if (text.isEmpty || text.contains('otzaria://inline-link')) {
      return text;
    }

    // סינון קישורים עם מיקומים תקינים
    final validLinks = links
        .where((link) => _isValidLinkPosition(link, text.length))
        .toList();

    if (validLinks.isEmpty) return text;

    // מיון לפי מיקום התחלה
    validLinks.sort((a, b) => a.start!.compareTo(b.start!));

    return _buildTextWithLinks(text, validLinks);
  }

  /// בדיקה אם מיקום הקישור תקין
  static bool _isValidLinkPosition(Link link, int textLength) {
    final start = link.start;
    final end = link.end;
    
    if (start == null || end == null) return false;
    if (start < 0 || end > textLength) return false;
    if (start >= end) return false;
    
    return true;
  }

  /// בניית טקסט עם קישורים
  static String _buildTextWithLinks(String text, List<Link> links) {
    final buffer = StringBuffer();
    int currentPos = 0;

    for (final link in links) {
      final start = link.start!;
      final end = link.end!;

      // דילוג על קישורים חופפים
      if (start < currentPos) continue;

      // הוספת טקסט לפני הקישור
      if (start > currentPos) {
        buffer.write(text.substring(currentPos, start));
      }

      // הוספת הקישור
      final linkText = text.substring(start, end);
      final url = _buildInlineLinkUrl(link);
      
      buffer.write('<a href="$url" style="text-decoration: underline;">');
      buffer.write(linkText);
      buffer.write('</a>');

      currentPos = end;
    }

    // הוספת שאר הטקסט
    if (currentPos < text.length) {
      buffer.write(text.substring(currentPos));
    }

    return buffer.toString();
  }

  /// בניית URL לקישור inline
  static String _buildInlineLinkUrl(Link link) {
    final encodedPath = UrlEncoding.encode(link.path2);
    final encodedRef = UrlEncoding.encode(link.heRef);
    return 'otzaria://inline-link?path=$encodedPath&index=${link.index2}&ref=$encodedRef';
  }

  /// ניקוי טקסט מתגי HTML
  static String cleanHtml(String text) {
    return text.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  /// חילוץ מספר עמוד מכותרת
  static String? extractPageNumber(String text) {
    // תבנית לזיהוי מספר עמוד עברי
    final pagePattern = RegExp(r'דף\s+([א-ת]{1,3})');
    final match = pagePattern.firstMatch(text);
    if (match != null) {
      return match.group(1);
    }

    // אם אין "דף", נחפש מספר עברי בתחילת הטקסט
    final numberPattern = RegExp(r'^([א-ת]{1,3})(?:\s|$)');
    final numberMatch = numberPattern.firstMatch(text.trim());
    if (numberMatch != null) {
      return numberMatch.group(1);
    }

    return null;
  }

  /// בדיקה אם טקסט תואם לכותרת המבוקשת
  static bool isHeaderMatch(String text, String headerName) {
    // ניקוי טקסטים להשוואה
    final cleanText = _normalizeText(text);
    final cleanHeader = _normalizeText(headerName);

    // השוואה מדויקת
    if (cleanText == cleanHeader) return true;

    // השוואה ללא רווחים
    if (cleanText.replaceAll(' ', '') == cleanHeader.replaceAll(' ', '')) {
      return true;
    }

    // השוואה עם גבולות מילים
    try {
      final pattern = RegExp(r'\b' + RegExp.escape(cleanHeader) + r'\b');
      if (pattern.hasMatch(cleanText)) return true;
    } catch (e) {
      // fallback אם regex נכשל
    }

    // השוואה פשוטה
    return cleanText.contains(cleanHeader);
  }

  /// נרמול טקסט להשוואה
  static String _normalizeText(String text) {
    return text
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'<[^>]*>'), '');
  }

  /// פיצול טקסט לשורות
  static List<String> splitToLines(String text) {
    return text.split('\n').map((line) => line.trim()).toList();
  }

  /// חיפוש טקסט בתוכן
  static List<int> findTextOccurrences(String content, String searchText) {
    final occurrences = <int>[];
    final lines = splitToLines(content);
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (isHeaderMatch(line, searchText)) {
        occurrences.add(i);
      }
    }
    
    return occurrences;
  }
}
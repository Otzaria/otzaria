/// כלים לקידוד ופענוח URLs
library;

import 'package:flutter/foundation.dart';

/// מחלקה לטיפול בקידוד ופענוח URLs
class UrlEncoding {
  
  /// מנסה לפענח URL בצורה בטוחה, תומך בטקסט רגיל ו-URL encoded
  static String safeDecode(String text) {
    if (text.isEmpty) return text;

    try {
      // אם הטקסט מכיל % זה כנראה מקודד
      if (text.contains('%')) {
        return Uri.decodeComponent(text);
      }
      // אחרת, זה כבר טקסט רגיל
      return text;
    } catch (e) {
      // אם הפענוח נכשל, נחזיר את הטקסט המקורי
      debugPrint('Failed to decode URL component: $text, error: $e');
      return text;
    }
  }

  /// מקודד טקסט ל-URL encoding
  static String safeEncode(String text) {
    if (text.isEmpty) return text;
    
    try {
      return Uri.encodeComponent(text);
    } catch (e) {
      debugPrint('Failed to encode URL component: $text, error: $e');
      return text;
    }
  }

  /// ניקוי URL מבעיות קידוד נפוצות
  static String cleanUrl(String url) {
    String cleanUrl = url.trim();
    
    // טיפול בקידוד כפול
    if (cleanUrl.contains('%25')) {
      try {
        cleanUrl = Uri.decodeComponent(cleanUrl);
      } catch (e) {
        debugPrint('Failed to decode double-encoded URL: $url');
      }
    }
    
    return cleanUrl;
  }

  /// בדיקה אם טקסט מקודד
  static bool isEncoded(String text) {
    return text.contains('%') && text.contains(RegExp(r'%[0-9A-Fa-f]{2}'));
  }

  /// פענוח פרמטרים מ-query string
  static Map<String, String> parseQueryParameters(String query) {
    if (query.isEmpty) return {};
    
    try {
      final uri = Uri(query: query);
      return uri.queryParameters.map((key, value) => 
          MapEntry(key, safeDecode(value)));
    } catch (e) {
      debugPrint('Failed to parse query parameters: $query, error: $e');
      return {};
    }
  }

  /// יצירת query string מפרמטרים
  static String buildQueryString(Map<String, String> params) {
    if (params.isEmpty) return '';
    
    final encodedParams = params.entries
        .where((entry) => entry.value.isNotEmpty)
        .map((entry) => '${entry.key}=${safeEncode(entry.value)}')
        .join('&');
        
    return encodedParams.isEmpty ? '' : '?$encodedParams';
  }

  /// ניקוי שם ספר מתווים לא חוקיים ל-URL
  static String sanitizeBookTitle(String title) {
    // הסרת תווים שיכולים לגרום לבעיות ב-URL
    return title
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '') // תווים לא חוקיים בשמות קבצים
        .replaceAll(RegExp(r'\s+'), ' ') // מספר רווחים לרווח אחד
        .trim();
  }

  /// חילוץ שם ספר מנתיב קובץ
  static String extractTitleFromPath(String path) {
    // הסרת סיומת קובץ ונתיב
    String title = path.split('/').last.split('\\').last;
    if (title.endsWith('.txt')) {
      title = title.substring(0, title.length - 4);
    }
    return title;
  }
}
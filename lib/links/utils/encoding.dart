/// כלים לקידוד ופענוח URLs
library;

import 'package:flutter/foundation.dart';

/// מחלקה לטיפול בקידוד ופענוח URLs
class UrlEncoding {
  
  /// פענוח בטוח של URL component
  static String decode(String text) {
    if (text.isEmpty) return text;

    try {
      // אם הטקסט מכיל % זה כנראה מקודד
      if (text.contains('%')) {
        return Uri.decodeComponent(text);
      }
      return text;
    } catch (e) {
      debugPrint('UrlEncoding: Failed to decode: $text, error: $e');
      return text;
    }
  }

  /// קידוד בטוח של URL component
  static String encode(String text) {
    if (text.isEmpty) return text;
    
    try {
      return Uri.encodeComponent(text);
    } catch (e) {
      debugPrint('UrlEncoding: Failed to encode: $text, error: $e');
      return text;
    }
  }

  /// ניקוי URL מבעיות קידוד נפוצות
  static String clean(String url) {
    String cleanUrl = url.trim();
    
    // טיפול בקידוד כפול
    if (cleanUrl.contains('%25')) {
      try {
        cleanUrl = Uri.decodeComponent(cleanUrl);
      } catch (e) {
        debugPrint('UrlEncoding: Failed to decode double-encoded URL: $url');
      }
    }
    
    return cleanUrl;
  }

  /// בדיקה אם טקסט מקודד
  static bool isEncoded(String text) {
    return text.contains('%') && text.contains(RegExp(r'%[0-9A-Fa-f]{2}'));
  }

  /// יצירת query string מפרמטרים
  static String buildQuery(Map<String, String> params) {
    if (params.isEmpty) return '';
    
    final encodedParams = params.entries
        .where((entry) => entry.value.isNotEmpty)
        .map((entry) => '${entry.key}=${encode(entry.value)}')
        .join('&');
        
    return encodedParams.isEmpty ? '' : '?$encodedParams';
  }

  /// פענוח query parameters
  static Map<String, String> parseQuery(String query) {
    if (query.isEmpty) return {};
    
    try {
      final uri = Uri(query: query);
      return uri.queryParameters.map((key, value) => 
          MapEntry(key, decode(value)));
    } catch (e) {
      debugPrint('UrlEncoding: Failed to parse query: $query, error: $e');
      return {};
    }
  }

  /// ניקוי שם ספר מתווים לא חוקיים
  static String sanitizeTitle(String title) {
    return title
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '') // תווים לא חוקיים
        .replaceAll(RegExp(r'\s+'), ' ') // מספר רווחים לרווח אחד
        .trim();
  }

  /// חילוץ שם ספר מנתיב קובץ
  static String extractTitle(String path) {
    String title = path.split('/').last.split('\\').last;
    if (title.endsWith('.txt')) {
      title = title.substring(0, title.length - 4);
    }
    return title;
  }
}
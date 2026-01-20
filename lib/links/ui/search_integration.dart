/// אינטגרציה עם מערכת החיפוש
library;

import 'package:flutter/material.dart';
import '../core/link_parser.dart';
import '../core/link_handler.dart';

/// מחלקה לאינטגרציה עם תיבת החיפוש של הספרייה
class SearchIntegration {
  
  /// בדיקה אם הטקסט שהוזן הוא קישור תקין
  static bool isValidUrl(String text) {
    return LinkParser.isValid(text);
  }
  
  /// טיפול בקישור שהוזן בתיבת החיפוש
  static Future<bool> handleSearchUrl(
    BuildContext context,
    String url,
  ) async {
    if (!isValidUrl(url)) {
      return false;
    }
    
    try {
      return await LinkHandler.openInApp(context, url);
    } catch (e) {
      debugPrint('SearchIntegration: Error handling search URL: $e');
      return false;
    }
  }

  /// זיהוי אוטומטי של קישורים בטקסט
  static List<String> detectUrls(String text) {
    final urls = <String>[];
    final lines = text.split('\n');
    
    for (final line in lines) {
      final trimmedLine = line.trim();
      if (isValidUrl(trimmedLine)) {
        urls.add(trimmedLine);
      }
    }
    
    return urls;
  }

  /// חילוץ קישורים מטקסט מובנה
  static List<String> extractUrls(String text) {
    final urls = <String>[];
    
    // תבניות לזיהוי קישורים
    final patterns = [
      RegExp(r'otzaria://[^\s]+'),
      RegExp(r'book://[^\s]+'),
      RegExp(r'https?://[^\s]+'),
      RegExp(r'#[^\s]+'),
    ];
    
    for (final pattern in patterns) {
      final matches = pattern.allMatches(text);
      for (final match in matches) {
        final url = match.group(0);
        if (url != null && isValidUrl(url)) {
          urls.add(url);
        }
      }
    }
    
    return urls;
  }

  /// בדיקה אם שורת חיפוש מכילה פרמטרי קישור
  static bool hasLinkParameters(String searchText) {
    final lowerText = searchText.toLowerCase();
    
    // בדיקה לפרמטרים אופייניים
    return lowerText.contains('index=') ||
           lowerText.contains('page=') ||
           lowerText.contains('text=') ||
           lowerText.contains('path=') ||
           lowerText.contains('ref=');
  }

  /// המרת שורת חיפוש לקישור אם אפשר
  static String? convertSearchToUrl(String searchText) {
    if (isValidUrl(searchText)) {
      return searchText;
    }
    
    // אם יש פרמטרים, נסה להמיר לקישור
    if (hasLinkParameters(searchText)) {
      // אם זה נראה כמו קישור inline
      if (searchText.contains('path=') && searchText.contains('index=')) {
        return 'otzaria://inline-link?$searchText';
      }
      
      // אם זה נראה כמו קישור ספר
      if (searchText.contains('?')) {
        final parts = searchText.split('?');
        if (parts.length == 2) {
          final bookTitle = parts[0].trim();
          final params = parts[1].trim();
          
          if (bookTitle.isNotEmpty && params.isNotEmpty) {
            // בדיקה אם זה PDF או טקסט
            final isPdf = params.contains('page=') || 
                         bookTitle.toLowerCase().contains('pdf');
            
            final scheme = isPdf ? 'otzaria://pdf/' : 'otzaria://book/';
            return '$scheme$bookTitle?$params';
          }
        }
      }
    }
    
    return null;
  }

  /// הצעות השלמה לקישורים
  static List<String> getSuggestions(String input) {
    final suggestions = <String>[];
    
    if (input.isEmpty) return suggestions;
    
    final lowerInput = input.toLowerCase();
    
    // הצעות לפרוטוקולים
    if ('otzaria://'.startsWith(lowerInput)) {
      suggestions.add('otzaria://book/');
      suggestions.add('otzaria://pdf/');
      suggestions.add('otzaria://inline-link?');
    }
    
    if ('book://'.startsWith(lowerInput)) {
      suggestions.add('book://');
    }
    
    // הצעות לפרמטרים
    if (lowerInput.contains('?') && !lowerInput.contains('=')) {
      suggestions.add('${input}index=');
      suggestions.add('${input}page=');
      suggestions.add('${input}text=');
    }
    
    return suggestions;
  }

  /// תיקון אוטומטי של קישורים שגויים
  static String? autoCorrectUrl(String url) {
    String corrected = url.trim();
    
    // תיקון קידוד כפול
    if (corrected.contains('%25')) {
      try {
        corrected = Uri.decodeComponent(corrected);
      } catch (e) {
        // אם נכשל, נשאיר כמו שהיה
      }
    }
    
    // תיקון פרוטוקולים שגויים
    if (corrected.startsWith('otzaria:/') && !corrected.startsWith('otzaria://')) {
      corrected = corrected.replaceFirst('otzaria:/', 'otzaria://');
    }
    
    if (corrected.startsWith('book:/') && !corrected.startsWith('book://')) {
      corrected = corrected.replaceFirst('book:/', 'book://');
    }
    
    // בדיקה אם התיקון עזר
    if (isValidUrl(corrected) && corrected != url) {
      return corrected;
    }
    
    return null;
  }
}
/// טיפול בקישורים מתיבת החיפוש של הספרייה
library;

import 'package:flutter/material.dart';
import 'package:otzaria/links/core/link_parser.dart';
import 'package:otzaria/links/core/link_handler.dart';

/// מחלקה לטיפול בקישורים שהוזנו בתיבת החיפוש של הספרייה
class SearchBoxLinkHandler {
  
  /// בודק אם הטקסט שהוזן הוא קישור תקין
  static bool isValidUrl(String text) {
    return LinkParser.isValidUrl(text);
  }
  
  /// מטפל בקישור שהוזן בתיבת החיפוש
  static Future<bool> handleSearchUrl(
    BuildContext context,
    String url,
  ) async {
    if (!isValidUrl(url)) {
      return false;
    }
    
    try {
      return await LinkHandler.openLinkInApp(context, url);
    } catch (e) {
      debugPrint('SearchBoxLinkHandler: שגיאה בטיפול בקישור: $e');
      return false;
    }
  }
}
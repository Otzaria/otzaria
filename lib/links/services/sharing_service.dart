/// שירות שיתוף קישורים
library;

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/core/scaffold_messenger.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/tab.dart';
import '../core/link_generator.dart';

/// שירות לשיתוף קישורים לספרים
class SharingService {
  
  /// שיתוף קישור לספר
  static Future<void> shareBook(
    BuildContext context,
    Book book, {
    int? position,
    String? highlightText,
    bool fullSectionHighlight = false,
  }) async {
    try {
      final url = LinkGenerator.createSharingUrl(
        book,
        position: position,
        highlightText: highlightText,
        fullSectionHighlight: fullSectionHighlight,
      );
      
      await _copyToClipboard(url);
      
      if (context.mounted) {
        UiSnack.show('קישור הועתק ללוח: ${book.title}');
      }
    } catch (e) {
      debugPrint('SharingService: שגיאה בשיתוף קישור: $e');
      if (context.mounted) {
        UiSnack.show('שגיאה בשיתוף הקישור');
      }
    }
  }

  /// שיתוף קישור מטאב פתוח
  static Future<void> shareTab(
    BuildContext context,
    OpenedTab tab,
  ) async {
    try {
      final link = LinkGenerator.fromTab(tab);
      final url = LinkGenerator.generate(link);
      
      await _copyToClipboard(url);
      
      if (context.mounted) {
        UiSnack.show('קישור הועתק ללוח: ${tab.title}');
      }
    } catch (e) {
      debugPrint('SharingService: שגיאה בשיתוף קישור טאב: $e');
      if (context.mounted) {
        UiSnack.show('שגיאה בשיתוף הקישור');
      }
    }
  }

  /// שיתוף קישור פשוט לספר
  static Future<void> shareSimpleBook(
    BuildContext context,
    String bookTitle,
  ) async {
    try {
      final url = LinkGenerator.createSimpleUrl(bookTitle);
      
      await _copyToClipboard(url);
      
      if (context.mounted) {
        UiSnack.show('קישור הועתק ללוח: $bookTitle');
      }
    } catch (e) {
      debugPrint('SharingService: שגיאה בשיתוף קישור פשוט: $e');
      if (context.mounted) {
        UiSnack.show('שגיאה בשיתוף הקישור');
      }
    }
  }

  /// שיתוף קישור לכותרת ספציפית
  static Future<void> shareBookHeader(
    BuildContext context,
    String bookTitle,
    String header,
  ) async {
    try {
      final url = LinkGenerator.createHeaderUrl(bookTitle, header);
      
      await _copyToClipboard(url);
      
      if (context.mounted) {
        UiSnack.show('קישור הועתק ללוח: $bookTitle - $header');
      }
    } catch (e) {
      debugPrint('SharingService: שגיאה בשיתוף קישור כותרת: $e');
      if (context.mounted) {
        UiSnack.show('שגיאה בשיתוף הקישור');
      }
    }
  }

  /// שיתוף קישור עם טקסט מודגש
  static Future<void> shareWithHighlight(
    BuildContext context,
    Book book,
    int position,
    String highlightText,
  ) async {
    try {
      final url = LinkGenerator.createSharingUrl(
        book,
        position: position,
        highlightText: highlightText,
      );
      
      await _copyToClipboard(url);
      
      if (context.mounted) {
        UiSnack.show('קישור עם הדגשה הועתק ללוח: ${book.title}');
      }
    } catch (e) {
      debugPrint('SharingService: שגיאה בשיתוף קישור עם הדגשה: $e');
      if (context.mounted) {
        UiSnack.show('שגיאה בשיתוף הקישור');
      }
    }
  }

  /// שיתוף קישור עם הדגשת מקטע מלא
  static Future<void> shareWithFullHighlight(
    BuildContext context,
    Book book,
    int position,
  ) async {
    try {
      final url = LinkGenerator.createSharingUrl(
        book,
        position: position,
        fullSectionHighlight: true,
      );
      
      await _copyToClipboard(url);
      
      if (context.mounted) {
        UiSnack.show('קישור עם הדגשת מקטע הועתק ללוח: ${book.title}');
      }
    } catch (e) {
      debugPrint('SharingService: שגיאה בשיתוף קישור עם הדגשה מלאה: $e');
      if (context.mounted) {
        UiSnack.show('שגיאה בשיתוף הקישור');
      }
    }
  }

  /// קבלת קישור כטקסט (ללא העתקה)
  static String getBookUrl(
    Book book, {
    int? position,
    String? highlightText,
    bool fullSectionHighlight = false,
  }) {
    return LinkGenerator.createSharingUrl(
      book,
      position: position,
      highlightText: highlightText,
      fullSectionHighlight: fullSectionHighlight,
    );
  }

  /// קבלת קישור מטאב כטקסט
  static String getTabUrl(OpenedTab tab) {
    final link = LinkGenerator.fromTab(tab);
    return LinkGenerator.generate(link);
  }

  /// קבלת קישור פשוט כטקסט
  static String getSimpleUrl(String bookTitle) {
    return LinkGenerator.createSimpleUrl(bookTitle);
  }

  /// קבלת קישור לכותרת כטקסט
  static String getHeaderUrl(String bookTitle, String header) {
    return LinkGenerator.createHeaderUrl(bookTitle, header);
  }

  /// העתקה ללוח פרטית
  static Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  // Legacy compatibility methods
  
  /// יצירת קישור בסיסי לספר (legacy)
  static String generateBookLink(OpenedTab tab) {
    final link = LinkGenerator.fromTab(tab);
    return LinkGenerator.generate(link.copyWith(position: null));
  }

  /// יצירת קישור למקטע (legacy)
  static String generateSectionLink(OpenedTab tab) {
    final link = LinkGenerator.fromTab(tab);
    return LinkGenerator.generate(link);
  }

  /// יצירת קישור עם הדגשה (legacy)
  static String generateHighlightedTextLink(OpenedTab tab, {String? selectedText}) {
    final link = LinkGenerator.fromTab(tab);
    
    if (selectedText != null && selectedText.trim().isNotEmpty) {
      return LinkGenerator.generate(link.copyWith(highlightText: selectedText.trim()));
    } else {
      return LinkGenerator.generate(link.copyWith(fullSectionHighlight: true));
    }
  }

  /// העתקת קישור ללוח עם הודעה (legacy)
  static Future<void> copyLinkToClipboard(
    String link, 
    String successMessage,
    Function(String) showSnackBar,
    Function(String) showErrorSnackBar,
  ) async {
    try {
      await _copyToClipboard(link);
      showSnackBar(successMessage);
    } catch (e) {
      showErrorSnackBar('שגיאה ביצירת קישור: $e');
    }
  }
}
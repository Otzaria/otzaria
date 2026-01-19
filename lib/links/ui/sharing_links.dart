/// שיתוף קישורים לספרים
library;

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/core/scaffold_messenger.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/links/core/link_generator.dart';

/// מחלקה לשיתוף קישורים לספרים
class SharingLinks {
  
  /// Helper function to determine the current section index reliably
  /// This function prioritizes visible position over selectedIndex to avoid index=0 issues
  static int getCurrentSectionIndex(
    TextBookTab tab,
    ItemPositionsListener positionsListener,
    TextBookLoaded? state,
  ) {
    // First priority: visible position from scroll listener
    final positions = positionsListener.itemPositions.value;
    if (positions.isNotEmpty) {
      final visibleIndex = positions.first.index;
      return visibleIndex;
    }
    
    // Second priority: selectedIndex from state (if not null)
    if (state?.selectedIndex != null) {
      return state!.selectedIndex!;
    }
    
    // Third priority: tab.index (current tab index)
    return tab.index;
  }

  /// Generates a basic book link without specific location
  static String generateBookLink(OpenedTab tab) {
    if (tab is TextBookTab) {
      return 'otzaria://book/${Uri.encodeComponent(tab.book.title)}';
    } else if (tab is PdfBookTab) {
      return 'otzaria://pdf/${Uri.encodeComponent(tab.book.title)}';
    } else {
      return 'otzaria://book/${Uri.encodeComponent(tab.title)}';
    }
  }

  /// Generates a section/page specific link
  static String generateSectionLink(OpenedTab tab) {
    if (tab is TextBookTab) {
      return 'otzaria://book/${Uri.encodeComponent(tab.book.title)}?index=${tab.index}';
    } else if (tab is PdfBookTab) {
      return 'otzaria://pdf/${Uri.encodeComponent(tab.book.title)}?page=${tab.pageNumber}';
    } else {
      // For generic tabs, add a section parameter to make it different from book link
      return 'otzaria://book/${Uri.encodeComponent(tab.title)}?section=1';
    }
  }

  /// Generates a link with text highlighting parameters
  static String generateHighlightedTextLink(OpenedTab tab, {String? selectedText}) {
    String baseLink = generateSectionLink(tab);
    
    if (selectedText != null && selectedText.trim().isNotEmpty) {
      final trimmedText = selectedText.trim();
      final encodedText = Uri.encodeComponent(trimmedText);
      final separator = baseLink.contains('?') ? '&' : '?';
      final finalLink = '$baseLink${separator}text=$encodedText';
      
      return finalLink;
    } else {
      // If no specific text, just add text flag
      final separator = baseLink.contains('?') ? '&' : '?';
      final fallbackLink = '$baseLink${separator}text=true';
      return fallbackLink;
    }
  }

  /// Copies a link to clipboard and shows user feedback
  static Future<void> copyLinkToClipboard(
    String link, 
    String successMessage,
    Function(String) showSnackBar,
    Function(String) showErrorSnackBar,
  ) async {
    try {
      await Clipboard.setData(ClipboardData(text: link));
      showSnackBar(successMessage);
    } catch (e) {
      showErrorSnackBar('שגיאה ביצירת קישור: $e');
    }
  }

  /// שיתוף קישור לספר
  static Future<void> shareBookLink(
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
      
      await _copyToClipboard(context, url);
      
      if (context.mounted) {
        UiSnack.show('קישור הועתק ללוח: ${book.title}');
      }
    } catch (e) {
      debugPrint('SharingLinks: שגיאה בשיתוף קישור: $e');
      if (context.mounted) {
        UiSnack.show('שגיאה בשיתוף הקישור');
      }
    }
  }

  /// שיתוף קישור מטאב פתוח
  static Future<void> shareTabLink(
    BuildContext context,
    OpenedTab tab,
  ) async {
    try {
      final link = LinkGenerator.createLinkFromTab(tab);
      final url = LinkGenerator.generateUrl(link);
      
      await _copyToClipboard(context, url);
      
      if (context.mounted) {
        UiSnack.show('קישור הועתק ללוח: ${tab.title}');
      }
    } catch (e) {
      debugPrint('SharingLinks: שגיאה בשיתוף קישור טאב: $e');
      if (context.mounted) {
        UiSnack.show('שגיאה בשיתוף הקישור');
      }
    }
  }

  /// Shares book link with user feedback (legacy compatibility)
  static Future<void> shareBookLinkLegacy(
    OpenedTab tab,
    Function(String) showSnackBar,
    Function(String) showErrorSnackBar,
  ) async {
    final link = generateBookLink(tab);
    await copyLinkToClipboard(
      link,
      'קישור ישיר לספר "${tab.title}" הועתק ללוח',
      showSnackBar,
      showErrorSnackBar,
    );
  }

  /// Shares section link with user feedback (legacy compatibility)
  static Future<void> shareSectionLink(
    OpenedTab tab,
    Function(String) showSnackBar,
    Function(String) showErrorSnackBar,
  ) async {
    final link = generateSectionLink(tab);
    await copyLinkToClipboard(
      link,
      'קישור ישיר למקטע הנוכחי ב"${tab.title}" הועתק ללוח',
      showSnackBar,
      showErrorSnackBar,
    );
  }

  /// Shares highlighted text link with user feedback (legacy compatibility)
  static Future<void> shareHighlightedTextLink(
    OpenedTab tab,
    Function(String) showSnackBar,
    Function(String) showErrorSnackBar,
    {String? selectedText}
  ) async {
    final link = generateHighlightedTextLink(tab, selectedText: selectedText);
    
    await copyLinkToClipboard(
      link,
      'קישור ישיר עם הדגשה ב"${tab.title}" הועתק ללוח',
      showSnackBar,
      showErrorSnackBar,
    );
  }

  /// יצירת קישור פשוט לספר
  static Future<void> shareSimpleBookLink(
    BuildContext context,
    String bookTitle,
  ) async {
    try {
      final url = LinkGenerator.createSimpleBookUrl(bookTitle);
      
      await _copyToClipboard(context, url);
      
      if (context.mounted) {
        UiSnack.show('קישור הועתק ללוח: $bookTitle');
      }
    } catch (e) {
      debugPrint('SharingLinks: שגיאה בשיתוף קישור פשוט: $e');
      if (context.mounted) {
        UiSnack.show('שגיאה בשיתוף הקישור');
      }
    }
  }

  /// יצירת קישור לכותרת ספציפית
  static Future<void> shareBookHeaderLink(
    BuildContext context,
    String bookTitle,
    String header,
  ) async {
    try {
      final url = LinkGenerator.createBookHeaderUrl(bookTitle, header);
      
      await _copyToClipboard(context, url);
      
      if (context.mounted) {
        UiSnack.show('קישור הועתק ללוח: $bookTitle - $header');
      }
    } catch (e) {
      debugPrint('SharingLinks: שגיאה בשיתוף קישור כותרת: $e');
      if (context.mounted) {
        UiSnack.show('שגיאה בשיתוף הקישור');
      }
    }
  }

  /// העתקה ללוח
  static Future<void> _copyToClipboard(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  /// קבלת קישור כטקסט (בלי העתקה)
  static String getBookLinkText(
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
  static String getTabLinkText(OpenedTab tab) {
    final link = LinkGenerator.createLinkFromTab(tab);
    return LinkGenerator.generateUrl(link);
  }
}

/// מחלקה לטיפול בשיתוף מתפריטי הקשר (legacy compatibility)
class ContextMenuSharing {
  
  /// Share book link from any text book view
  static Future<void> shareBookLink(
    BuildContext context,
    TextBookTab tab,
    Function(String) onSuccess,
    Function(String) onError,
  ) async {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return;
    
    await SharingLinks.shareBookLinkLegacy(tab, onSuccess, onError);
  }

  /// Share section link for a specific index
  static Future<void> shareSectionLink(
    BuildContext context,
    String bookTitle,
    int index,
    Function(String) onSuccess,
    Function(String) onError,
  ) async {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return;
    
    // Create temporary tab with the specific index
    final tempTab = TextBookTab(book: state.book, index: index);
    
    await SharingLinks.shareSectionLink(tempTab, onSuccess, onError);
  }

  /// Share highlighted text link for a specific index
  static Future<void> shareTextHighlightLink(
    BuildContext context,
    String bookTitle,
    int index,
    String? selectedText,
    Function(String) onSuccess,
    Function(String) onError,
  ) async {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return;
    
    // Create temporary tab with the specific index
    final tempTab = TextBookTab(book: state.book, index: index);
    
    await SharingLinks.shareHighlightedTextLink(
      tempTab,
      onSuccess,
      onError,
      selectedText: selectedText,
    );
  }
}
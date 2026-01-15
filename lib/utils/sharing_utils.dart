import 'package:flutter/services.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';

/// Utility class for generating and handling sharing links
class SharingUtils {
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

  /// Shares book link with user feedback
  static Future<void> shareBookLink(
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

  /// Shares section link with user feedback
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

  /// Shares highlighted text link with user feedback
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
}
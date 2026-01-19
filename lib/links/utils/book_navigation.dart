import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/core/scaffold_messenger.dart';

/// Utility class for book navigation functions
/// This handles navigation within books (headers, pages, etc.)
class BookNavigation {
  
  /// Navigate to a header in the current book
  static Future<void> navigateToHeader(
    BuildContext context, 
    String headerName,
  ) async {
    try {
      // Get current book from BLoC
      final textBookBloc = context.read<TextBookBloc>();
      final state = textBookBloc.state;

      if (state is! TextBookLoaded) {
        throw Exception('לא ניתן לנווט - הספר לא נטען');
      }

      // Search for header in book content
      final index = await findHeaderIndex(state.book, headerName);

      if (index != null) {
        // Navigate to found index
        state.scrollController.scrollTo(
          index: index,
          duration: const Duration(milliseconds: 250),
          curve: Curves.ease,
        );

        if (context.mounted) {
          UiSnack.show('נווט ל: $headerName');
        }
      } else {
        throw Exception('לא נמצאה הכותרת: $headerName');
      }
    } catch (e) {
      debugPrint('שגיאה בניווט לכותרת: $e');

      if (context.mounted) {
        UiSnack.show('לא ניתן לנווט לכותרת: $headerName');
      }
    }
  }

  /// Find the index of a header in a book
  static Future<int?> findHeaderIndex(TextBook book, String headerName) async {
    try {
      // Get table of contents
      final tableOfContents = await book.tableOfContents;

      // Search in table of contents - exact match first
      for (final entry in tableOfContents) {
        if (isHeaderMatch(entry.text, headerName)) {
          return entry.index;
        }
      }

      // If not found, try searching by page number only (without side)
      // This helps when the link includes a side that doesn't exist in TOC
      final pageOnlyMatch = extractPageNumber(headerName);
      if (pageOnlyMatch != null) {
        for (final entry in tableOfContents) {
          final entryPageMatch = extractPageNumber(entry.text);
          if (entryPageMatch != null && entryPageMatch == pageOnlyMatch) {
            return entry.index;
          }
        }
      }

      // If not found in TOC, search in book content itself
      final content = await book.text;
      final lines = content.split('\n');

      // Exact search
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        final cleanLine = line.replaceAll(RegExp(r'<[^>]*>'), '').trim();

        if (isHeaderMatch(cleanLine, headerName)) {
          return i;
        }
      }

      // Search by page only
      if (pageOnlyMatch != null) {
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
          final cleanLine = line.replaceAll(RegExp(r'<[^>]*>'), '').trim();
          final linePageMatch = extractPageNumber(cleanLine);

          if (linePageMatch != null && linePageMatch == pageOnlyMatch) {
            return i;
          }
        }
      }

      return null;
    } catch (e) {
      debugPrint('שגיאה בחיפוש כותרת: $e');
      return null;
    }
  }

  /// Extract page number from header (e.g., "דף כג א" -> "כג")
  static String? extractPageNumber(String text) {
    // Pattern to identify Hebrew page number
    final pagePattern = RegExp(r'דף\s+([א-ת]{1,3})');
    final match = pagePattern.firstMatch(text);
    if (match != null) {
      return match.group(1);
    }

    // If no "דף", try to find Hebrew number at start of string
    final numberPattern = RegExp(r'^([א-ת]{1,3})(?:\s|$)');
    final numberMatch = numberPattern.firstMatch(text.trim());
    if (numberMatch != null) {
      return numberMatch.group(1);
    }

    return null;
  }

  /// Check if text matches the requested header
  static bool isHeaderMatch(String text, String headerName) {
    // Clean texts for comparison
    final cleanText = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final cleanHeader = headerName.trim().replaceAll(RegExp(r'\s+'), ' ');

    // Exact comparison
    if (cleanText == cleanHeader) {
      return true;
    }

    // Comparison without spaces
    if (cleanText.replaceAll(' ', '') == cleanHeader.replaceAll(' ', '')) {
      return true;
    }

    // Use word boundaries to avoid partial matches
    try {
      final pattern = RegExp(r'\b' + RegExp.escape(cleanHeader) + r'\b');
      if (pattern.hasMatch(cleanText)) {
        return true;
      }
    } catch (e) {
      // Fallback for complex patterns
    }

    // Fallback to original logic if regex fails or doesn't match
    if (cleanText.contains(cleanHeader)) {
      return true;
    }

    return false;
  }
}
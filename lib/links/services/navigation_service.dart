/// שירות ניווט בספרים
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/core/scaffold_messenger.dart';
import '../utils/text_processing.dart';

/// שירות לניווט בתוך ספרים
class NavigationService {
  
  /// ניווט לכותרת בספר הנוכחי
  static Future<void> navigateToHeader(
    BuildContext context, 
    String headerName,
  ) async {
    try {
      final textBookBloc = context.read<TextBookBloc>();
      final state = textBookBloc.state;

      if (state is! TextBookLoaded) {
        throw Exception('לא ניתן לנווט - הספר לא נטען');
      }

      final index = await findHeaderIndex(state.book, headerName);

      if (index != null) {
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
      debugPrint('NavigationService: שגיאה בניווט לכותרת: $e');

      if (context.mounted) {
        UiSnack.show('לא ניתן לנווט לכותרת: $headerName');
      }
    }
  }

  /// חיפוש אינדקס של כותרת בספר
  static Future<int?> findHeaderIndex(TextBook book, String headerName) async {
    try {
      // חיפוש בתוכן העניינים
      final tableOfContents = await book.tableOfContents;

      for (final entry in tableOfContents) {
        if (TextProcessing.isHeaderMatch(entry.text, headerName)) {
          return entry.index;
        }
      }

      // חיפוש לפי מספר עמוד בלבד
      final pageNumber = TextProcessing.extractPageNumber(headerName);
      if (pageNumber != null) {
        for (final entry in tableOfContents) {
          final entryPageNumber = TextProcessing.extractPageNumber(entry.text);
          if (entryPageNumber != null && entryPageNumber == pageNumber) {
            return entry.index;
          }
        }
      }

      // חיפוש בתוכן הספר עצמו
      final content = await book.text;
      final occurrences = TextProcessing.findTextOccurrences(content, headerName);
      
      if (occurrences.isNotEmpty) {
        return occurrences.first;
      }

      // חיפוש לפי מספר עמוד בתוכן
      if (pageNumber != null) {
        final lines = TextProcessing.splitToLines(content);
        for (int i = 0; i < lines.length; i++) {
          final line = TextProcessing.cleanHtml(lines[i]);
          final linePageNumber = TextProcessing.extractPageNumber(line);
          if (linePageNumber != null && linePageNumber == pageNumber) {
            return i;
          }
        }
      }

      return null;
    } catch (e) {
      debugPrint('NavigationService: שגיאה בחיפוש כותרת: $e');
      return null;
    }
  }

  /// ניווט לאינדקס ספציפי
  static Future<void> navigateToIndex(
    BuildContext context,
    int index,
  ) async {
    try {
      final textBookBloc = context.read<TextBookBloc>();
      final state = textBookBloc.state;

      if (state is! TextBookLoaded) {
        throw Exception('לא ניתן לנווט - הספר לא נטען');
      }

      state.scrollController.scrollTo(
        index: index,
        duration: const Duration(milliseconds: 250),
        curve: Curves.ease,
      );

      if (context.mounted) {
        UiSnack.show('נווט למקטע $index');
      }
    } catch (e) {
      debugPrint('NavigationService: שגיאה בניווט לאינדקס: $e');

      if (context.mounted) {
        UiSnack.show('לא ניתן לנווט למקטע $index');
      }
    }
  }

  /// קבלת האינדקס הנוכחי
  static int? getCurrentIndex(BuildContext context) {
    try {
      final textBookBloc = context.read<TextBookBloc>();
      final state = textBookBloc.state;

      if (state is TextBookLoaded) {
        return state.selectedIndex;
      }
      
      return null;
    } catch (e) {
      debugPrint('NavigationService: שגיאה בקבלת אינדקס נוכחי: $e');
      return null;
    }
  }

  /// בדיקה אם ניתן לנווט
  static bool canNavigate(BuildContext context) {
    try {
      final textBookBloc = context.read<TextBookBloc>();
      return textBookBloc.state is TextBookLoaded;
    } catch (e) {
      return false;
    }
  }
}
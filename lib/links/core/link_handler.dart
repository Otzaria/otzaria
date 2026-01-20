/// מחלקה מרכזית לטיפול בקישורים
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/scaffold_messenger.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import '../models/link.dart';
import '../models/link_types.dart';
import '../core/link_parser.dart';
import '../services/navigation_service.dart';

/// מחלקה מרכזית לטיפול בקישורים לספרים
class LinkHandler {
  
  /// טיפול בקישור ופתיחת הספר המתאים
  static Future<bool> handle(
    BuildContext context,
    String url,
    Function(OpenedTab) openTab,
  ) async {
    debugPrint('LinkHandler: Processing URL: $url');
    
    try {
      final parseResult = LinkParser.parse(url);
      
      if (!parseResult.success) {
        debugPrint('LinkHandler: Failed to parse URL: ${parseResult.error}');
        if (context.mounted) {
          UiSnack.show('שגיאה בפענוח הקישור: ${parseResult.error}');
        }
        return false;
      }

      final link = parseResult.link!;
      
      switch (link.type) {
        case LinkType.textBook:
        case LinkType.pdfBook:
          return await _handleBookLink(context, link, openTab);
        
        case LinkType.simpleBook:
          return await _handleSimpleLink(context, link, openTab);
        
        case LinkType.internal:
          return await _handleInternalLink(context, link);
        
        case LinkType.inlineLink:
          return await _handleInlineLink(context, link, openTab);
        
        case LinkType.external:
          return await _handleExternalLink(context, link);
      }
    } catch (e, stackTrace) {
      debugPrint('LinkHandler: Error handling link: $e');
      debugPrint('Stack trace: $stackTrace');

      if (context.mounted) {
        UiSnack.show('שגיאה בפתיחת הקישור: $e');
      }

      return false;
    }
  }

  /// טיפול בקישורי ספרים (otzaria://book/ ו-otzaria://pdf/)
  static Future<bool> _handleBookLink(
    BuildContext context,
    BookLink link,
    Function(OpenedTab) openTab,
  ) async {
    try {
      final library = await DataRepository.instance.library;
      final bookType = link.type == LinkType.pdfBook ? PdfBook : TextBook;
      final foundBook = library.findBookByTitle(link.bookTitle, bookType);

      if (foundBook == null) {
        throw Exception('לא נמצא ספר בשם: ${link.bookTitle}');
      }

      // Store mounted status before async calls
      final isMounted = context.mounted;
      if (!isMounted) return false;

      if (link.type == LinkType.pdfBook) {
        return _openPdfBook(foundBook as PdfBook, link, openTab);
      } else {
        return _openTextBook(foundBook as TextBook, link, openTab);
      }
    } catch (e) {
      debugPrint('LinkHandler: Error handling book link: $e');
      // Check if context is still mounted before using it
      if (context.mounted) {
        UiSnack.show('לא ניתן לפתוח את הקישור: $e');
      }
      return false;
    }
  }

  /// פתיחת ספר PDF
  static bool _openPdfBook(
    PdfBook book,
    BookLink link,
    Function(OpenedTab) openTab,
  ) {
    final startPage = link.position ?? 1;
    final pdfTab = PdfBookTab(
      book: book,
      pageNumber: startPage,
    );

    openTab(pdfTab);
    return true;
  }

  /// פתיחת ספר טקסט
  static bool _openTextBook(
    TextBook book,
    BookLink link,
    Function(OpenedTab) openTab,
  ) {
    final startIndex = link.position ?? 0;
    
    final tab = TextBookTab(
      book: book,
      index: startIndex,
      highlightText: link.highlightText ?? '',
      fullSectionHighlight: link.fullSectionHighlight,
      openLeftPane: _shouldOpenSidebar(),
    );

    openTab(tab);
    return true;
  }

  /// בדיקה אם לפתוח את הסרגל הצדדי
  static bool _shouldOpenSidebar() {
    return (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
           (Settings.getValue<bool>('key-default-sidebar-open') ?? false);
  }

  /// טיפול בקישורי book://
  static Future<bool> _handleSimpleLink(
    BuildContext context,
    BookLink link,
    Function(OpenedTab) openTab,
  ) async {
    try {
      final library = await DataRepository.instance.library;
      final foundBook = library.findBookByTitle(link.bookTitle, TextBook);

      if (foundBook == null) {
        throw Exception('לא נמצא ספר בשם: ${link.bookTitle}');
      }

      if (foundBook is! TextBook) {
        throw Exception('הספר ${link.bookTitle} אינו ספר טקסט');
      }

      int startIndex = 0;

      // חיפוש כותרת אם צוינה
      if (link.header != null && link.header!.isNotEmpty) {
        final headerIndex = await NavigationService.findHeaderIndex(foundBook, link.header!);
        if (headerIndex != null) {
          startIndex = headerIndex;
        } else if (context.mounted) {
          UiSnack.show(
              'לא נמצאה הכותרת "${link.header}" בספר ${link.bookTitle}, פותח את תחילת הספר');
        }
      }

      final tab = TextBookTab(
        book: foundBook,
        index: startIndex,
        openLeftPane: _shouldOpenSidebar(),
      );

      openTab(tab);

      if (context.mounted && link.header != null && link.header!.isNotEmpty) {
        UiSnack.show('פתח ספר: ${link.bookTitle} - ${link.header}');
      }
      
      return true;
    } catch (e) {
      debugPrint('LinkHandler: Error handling simple link: $e');
      if (context.mounted) {
        UiSnack.show('לא ניתן לפתוח את הספר: ${link.bookTitle}');
      }
      return false;
    }
  }

  /// טיפול בקישורים פנימיים (#)
  static Future<bool> _handleInternalLink(
    BuildContext context,
    BookLink link,
  ) async {
    try {
      if (link.header == null || link.header!.isEmpty) {
        throw Exception('כותרת ריקה בקישור פנימי');
      }

      await NavigationService.navigateToHeader(context, link.header!);
      return true;
    } catch (e) {
      debugPrint('LinkHandler: Error handling internal link: $e');
      if (context.mounted) {
        UiSnack.show('לא ניתן לנווט לכותרת: ${link.header}');
      }
      return false;
    }
  }

  /// טיפול בקישורי inline
  static Future<bool> _handleInlineLink(
    BuildContext context,
    BookLink link,
    Function(OpenedTab) openTab,
  ) async {
    try {
      if (link.filePath == null || link.filePath!.isEmpty) {
        throw Exception('נתיב קובץ ריק בקישור inline');
      }

      final library = await DataRepository.instance.library;
      final foundBook = library.findBookByTitle(link.bookTitle, TextBook);

      if (foundBook == null) {
        throw Exception('לא נמצא ספר בשם: ${link.bookTitle}');
      }

      if (foundBook is! TextBook) {
        throw Exception('הספר ${link.bookTitle} אינו ספר טקסט');
      }

      final startIndex = link.position ?? 0;
      
      final tab = TextBookTab(
        book: foundBook,
        index: startIndex,
        openLeftPane: _shouldOpenSidebar(),
      );

      openTab(tab);

      if (context.mounted && link.reference != null && link.reference!.isNotEmpty) {
        UiSnack.show('נפתח: ${link.reference}');
      }
      
      return true;
    } catch (e) {
      debugPrint('LinkHandler: Error handling inline link: $e');
      if (context.mounted) {
        UiSnack.show('לא ניתן לפתוח את הקישור: $e');
      }
      return false;
    }
  }

  /// טיפול בקישורים חיצוניים
  static Future<bool> _handleExternalLink(
    BuildContext context,
    BookLink link,
  ) async {
    // כרגע לא מטפלים בקישורים חיצוניים
    if (context.mounted) {
      UiSnack.show('קישורים חיצוניים אינם נתמכים כרגע');
    }
    return false;
  }

  /// פתיחת קישור עם אינטגרציה מלאה לאפליקציה
  static Future<bool> openInApp(
    BuildContext context,
    String url,
  ) async {
    return await handle(
      context,
      url,
      (OpenedTab tab) {
        context.read<TabsBloc>().add(AddTab(tab));
        context.read<NavigationBloc>().add(const NavigateToScreen(Screen.reading));
      },
    );
  }
}
/// מחלקה מרכזית לטיפול בכל סוגי הקישורים
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
import 'package:otzaria/links/utils/book_navigation.dart';
import 'package:otzaria/links/models/link_models.dart';
import 'package:otzaria/links/core/link_parser.dart';

/// מחלקה מרכזית לטיפול בקישורים לספרים
class LinkHandler {
  
  /// מטפל בקישור ופותח את הספר המתאים
  static Future<bool> handleLink(
    BuildContext context,
    String url,
    Function(OpenedTab) openBookCallback,
  ) async {
    debugPrint('LinkHandler: handleLink called with URL: $url');
    
    try {
      // פענוח הקישור
      final parseResult = LinkParser.parseUrl(url);
      
      if (!parseResult.success) {
        debugPrint('LinkHandler: Failed to parse URL: ${parseResult.error}');
        if (context.mounted) {
          UiSnack.show('שגיאה בפענוח הקישור: ${parseResult.error}');
        }
        return false;
      }

      final link = parseResult.link!;
      
      // טיפול לפי סוג הקישור
      switch (link.type) {
        case LinkType.textBook:
        case LinkType.pdfBook:
          return await _handleBookLink(context, link, openBookCallback);
        
        case LinkType.simpleBook:
          return await _handleSimpleBookLink(context, link, openBookCallback);
        
        case LinkType.internal:
          return await _handleInternalLink(context, link);
        
        case LinkType.inlineLink:
          return await _handleInlineLink(context, link, openBookCallback);
        
        case LinkType.external:
          return await _handleExternalLink(context, link);
      }
    } catch (e, stackTrace) {
      debugPrint('LinkHandler: שגיאה בטיפול בקישור: $e');
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
    Function(OpenedTab) openBookCallback,
  ) async {
    try {
      // מציאת הספר בספרייה
      final library = await DataRepository.instance.library;
      final bookType = link.type == LinkType.pdfBook ? PdfBook : TextBook;
      final foundBook = library.findBookByTitle(link.bookTitle, bookType);

      if (foundBook == null) {
        throw Exception('לא נמצא ספר בשם: ${link.bookTitle}');
      }

      if (link.type == LinkType.pdfBook) {
        if (foundBook is! PdfBook) {
          throw Exception('הספר ${link.bookTitle} אינו ספר PDF');
        }

        final startPage = link.position ?? 1;
        final pdfTab = PdfBookTab(
          book: foundBook,
          pageNumber: startPage,
        );

        openBookCallback(pdfTab);
        
        if (context.mounted) {
          UiSnack.show('נפתח ספר PDF: ${link.bookTitle} (עמוד $startPage)');
        }
        
      } else {
        if (foundBook is! TextBook) {
          throw Exception('הספר ${link.bookTitle} אינו ספר טקסט');
        }

        final startIndex = link.position ?? 0;
        
        final tab = TextBookTab(
          book: foundBook,
          index: startIndex,
          highlightText: link.highlightText ?? '',
          fullSectionHighlight: link.fullSectionHighlight,
          openLeftPane: (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
              (Settings.getValue<bool>('key-default-sidebar-open') ?? false),
        );

        openBookCallback(tab);

        // הצגת הודעה למשתמש
        if (context.mounted) {
          String message;
          if (link.fullSectionHighlight) {
            message = startIndex > 0 
              ? 'נפתח ספר: ${link.bookTitle} (מקטע $startIndex) עם הדגשת כל המקטע'
              : 'נפתח ספר: ${link.bookTitle} עם הדגשת כל המקטע';
          } else if (link.highlightText != null && link.highlightText!.isNotEmpty) {
            message = startIndex > 0 
              ? 'נפתח ספר: ${link.bookTitle} (מקטע $startIndex) עם הדגשה: ${link.highlightText}'
              : 'נפתח ספר: ${link.bookTitle} עם הדגשה: ${link.highlightText}';
          } else {
            message = startIndex > 0 
              ? 'נפתח ספר: ${link.bookTitle} (מקטע $startIndex)'
              : 'נפתח ספר: ${link.bookTitle}';
          }
          UiSnack.show(message);
        }
      }
      
      return true;
    } catch (e) {
      debugPrint('LinkHandler: שגיאה בטיפול בקישור ספר: $e');
      if (context.mounted) {
        UiSnack.show('לא ניתן לפתוח את הקישור: $e');
      }
      return false;
    }
  }

  /// טיפול בקישורי book://
  static Future<bool> _handleSimpleBookLink(
    BuildContext context,
    BookLink link,
    Function(OpenedTab) openBookCallback,
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

      // אם צוינה כותרת, נחפש את האינדקס שלה
      if (link.header != null && link.header!.isNotEmpty) {
        final headerIndex = await BookNavigation.findHeaderIndex(foundBook, link.header!);
        if (headerIndex != null) {
          startIndex = headerIndex;
        } else {
          // אם לא נמצאה הכותרת, נציג אזהרה אבל עדיין נפתח את הספר
          if (context.mounted) {
            UiSnack.show(
                'לא נמצאה הכותרת "${link.header}" בספר ${link.bookTitle}, פותח את תחילת הספר');
          }
        }
      }

      final tab = TextBookTab(
        book: foundBook,
        index: startIndex,
        openLeftPane: (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
            (Settings.getValue<bool>('key-default-sidebar-open') ?? false),
      );

      openBookCallback(tab);

      if (context.mounted && link.header != null && link.header!.isNotEmpty) {
        UiSnack.show('פתח ספר: ${link.bookTitle} - ${link.header}');
      }
      
      return true;
    } catch (e) {
      debugPrint('LinkHandler: שגיאה בטיפול בקישור book: $e');
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

      await BookNavigation.navigateToHeader(context, link.header!);
      return true;
    } catch (e) {
      debugPrint('LinkHandler: שגיאה בטיפול בקישור פנימי: $e');
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
    Function(OpenedTab) openBookCallback,
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
        openLeftPane: (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
            (Settings.getValue<bool>('key-default-sidebar-open') ?? false),
      );

      openBookCallback(tab);

      if (context.mounted && link.reference != null && link.reference!.isNotEmpty) {
        UiSnack.show('נפתח: ${link.reference}');
      }
      
      return true;
    } catch (e) {
      debugPrint('LinkHandler: שגיאה בטיפול בקישור inline: $e');
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
    // ניתן להוסיף תמיכה ב-url_launcher בעתיד
    if (context.mounted) {
      UiSnack.show('קישורים חיצוניים אינם נתמכים כרגע');
    }
    return false;
  }

  /// פתיחת קישור עם אינטגרציה מלאה לאפליקציה
  static Future<bool> openLinkInApp(
    BuildContext context,
    String url,
  ) async {
    return await handleLink(
      context,
      url,
      (OpenedTab tab) {
        // פתיחת הטאב החדש
        context.read<TabsBloc>().add(AddTab(tab));
        // מעבר למסך הקריאה
        context.read<NavigationBloc>().add(const NavigateToScreen(Screen.reading));
      },
    );
  }
}
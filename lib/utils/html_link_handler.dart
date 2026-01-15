import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/core/scaffold_messenger.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';

/// מחלקה לטיפול בקישורי HTML בתוך הטקסט
class HtmlLinkHandler {

  /// מנסה לפענח URL בצורה בטוחה, תומך בטקסט רגיל ו-URL encoded
  static String _safeDecode(String text) {
    if (text.isEmpty) return text;

    try {
      // אם הטקסט מכיל % זה כנראה מקודד
      if (text.contains('%')) {
        return Uri.decodeComponent(text);
      }
      // אחרת, זה כבר טקסט רגיל
      return text;
    } catch (e) {
      // אם הפענוח נכשל, נחזיר את הטקסט המקורי
      debugPrint('Failed to decode URL component: $text, error: $e');
      return text;
    }
  }

  /// מטפל בקישורים מבוססי תווים (inline links)
  static Future<void> _handleInlineLink(
    BuildContext context,
    String url,
    Function(OpenedTab) openBookCallback,
  ) async {
    try {
      // פענוח ה-URL ולקיחת הפרמטרים
      final uri = Uri.parse(url);
      final path = _safeDecode(uri.queryParameters['path'] ?? '');
      final indexStr = uri.queryParameters['index'] ?? '';
      final ref = _safeDecode(uri.queryParameters['ref'] ?? '');

      if (path.isEmpty) {
        throw Exception('נתיב לא תקין בקישור');
      }

      // המרת האינדקס למספר (index2 מגיע כ-1-based, אבל אנחנו צריכים 0-based)
      final index = int.tryParse(indexStr);
      if (index == null) {
        throw Exception('אינדקס לא תקין בקישור');
      }

      // מציאת הספר על פי הנתיב
      final bookTitle = _getTitleFromPath(path);
      final library = await DataRepository.instance.library;
      final foundBook = library.findBookByTitle(bookTitle, TextBook);

      if (foundBook == null) {
        throw Exception('לא נמצא ספר בשם: $bookTitle');
      }

      if (foundBook is! TextBook) {
        throw Exception('הספר $bookTitle אינו ספר טקסט');
      }

      // פתיחת הספר באינדקס הנכון (המרה ל-0-based)
      final tab = TextBookTab(
        book: foundBook,
        index: index - 1, // המרה מ-1-based ל-0-based
        openLeftPane: (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
            (Settings.getValue<bool>('key-default-sidebar-open') ?? false),
      );

      openBookCallback(tab);

      if (context.mounted && ref.isNotEmpty) {
        UiSnack.show('נפתח: $ref');
      }
    } catch (e) {
      debugPrint('שגיאה בטיפול בקישור מבוסס תווים: $e');

      if (context.mounted) {
        UiSnack.show('לא ניתן לפתוח את הקישור: $e');
      }
    }
  }

  /// מטפל בקישורי שיתוף (otzaria://book/ ו-otzaria://pdf/)
  static Future<void> _handleSharingLink(
    BuildContext context,
    String url,
    Function(OpenedTab) openBookCallback,
  ) async {
    try {
      // Clean the URL first - handle encoding issues
      String cleanUrl = url.trim();
      
      // Handle potential double encoding
      if (cleanUrl.contains('%25')) {
        cleanUrl = Uri.decodeComponent(cleanUrl);
      }
      
      Uri uri;
      try {
        uri = Uri.parse(cleanUrl);
      } catch (e) {
        // Try to fix encoding issues
        cleanUrl = cleanUrl.replaceAll(' ', '%20');
        uri = Uri.parse(cleanUrl);
      }
      
      final pathSegments = uri.pathSegments;
      final isPdf = cleanUrl.startsWith('otzaria://pdf/');
      
      if (pathSegments.isEmpty) {
        throw Exception('קישור לא תקין - חסר שם ספר');
      }

      // Get book title and handle encoding
      String bookTitle = pathSegments.first;
      
      // Try to decode if it's still encoded
      if (bookTitle.contains('%')) {
        try {
          bookTitle = Uri.decodeComponent(bookTitle);
        } catch (e) {
          // Failed to decode, use as-is
        }
      }
      
      final queryParams = uri.queryParameters;
      
      // מציאת הספר בספרייה
      final library = await DataRepository.instance.library;
      
      // Look for the appropriate book type
      final foundBook = isPdf 
          ? library.findBookByTitle(bookTitle, PdfBook)
          : library.findBookByTitle(bookTitle, TextBook);

      if (foundBook == null) {
        throw Exception('לא נמצא ספר בשם: $bookTitle');
      }

      if (isPdf) {
        if (foundBook is! PdfBook) {
          throw Exception('הספר $bookTitle אינו ספר PDF');
        }

        // Handle PDF book
        int startPage = 1;
        if (queryParams.containsKey('page')) {
          final pageStr = queryParams['page'];
          final parsedPage = int.tryParse(pageStr ?? '');
          if (parsedPage != null && parsedPage > 0) {
            startPage = parsedPage;
          }
        }

        // Create PDF tab
        final pdfTab = PdfBookTab(
          book: foundBook,
          pageNumber: startPage,
        );

        // Call the callback with the PDF tab
        openBookCallback(pdfTab);
        
        if (context.mounted) {
          UiSnack.show('נפתח ספר PDF: $bookTitle (עמוד $startPage)');
        }
        
      } else {
        // Handle text book (existing logic)
        if (foundBook is! TextBook) {
          throw Exception('הספר $bookTitle אינו ספר טקסט');
        }

        // קביעת האינדקס ההתחלתי
        int startIndex = 0;
        if (queryParams.containsKey('index')) {
          final indexStr = queryParams['index'];
          final parsedIndex = int.tryParse(indexStr ?? '');
          if (parsedIndex != null && parsedIndex >= 0) {
            startIndex = parsedIndex;
          }
        }

        debugPrint('HtmlLinkHandler: Creating tab for book: $bookTitle at index: $startIndex');

        // קביעת הטקסט להדגשה
        String highlightText = '';
        bool fullSectionHighlight = false;
        
        if (queryParams.containsKey('text')) {
          final highlightParam = queryParams['text'];
          
          debugPrint('HtmlLinkHandler: Found text parameter: "$highlightParam"');
          
          if (highlightParam == 'true') {
            // Full section highlighting
            fullSectionHighlight = true;
            debugPrint('HtmlLinkHandler: Full section highlighting enabled');
          } else if (highlightParam != null && highlightParam.isNotEmpty) {
            try {
              // Decode URL encoding including %20 for spaces
              highlightText = Uri.decodeComponent(highlightParam);
              
              // Additional cleanup for common encoding issues
              highlightText = highlightText
                  .replaceAll('%20', ' ')  // Handle any remaining %20
                  .replaceAll('+', ' ')    // Handle + as space
                  .trim();
                  
              debugPrint('HtmlLinkHandler: Decoded highlight text: "$highlightText"');
            } catch (e) {
              debugPrint('HtmlLinkHandler: Failed to decode highlight text: $e');
              // If decoding fails, use the original parameter with basic cleanup
              highlightText = highlightParam
                  .replaceAll('%20', ' ')
                  .replaceAll('+', ' ')
                  .trim();
            }
          }
        }

        // פתיחת הספר
        final tab = TextBookTab(
          book: foundBook,
          index: startIndex,
          highlightText: highlightText,
          fullSectionHighlight: fullSectionHighlight,
          openLeftPane: (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
              (Settings.getValue<bool>('key-default-sidebar-open') ?? false),
        );

        openBookCallback(tab);

        // הצגת הודעה למשתמש
        if (context.mounted) {
          String message;
          if (fullSectionHighlight) {
            message = startIndex > 0 
              ? 'נפתח ספר: $bookTitle (מקטע $startIndex) עם הדגשת כל המקטע'
              : 'נפתח ספר: $bookTitle עם הדגשת כל המקטע';
          } else if (highlightText.isNotEmpty) {
            message = startIndex > 0 
              ? 'נפתח ספר: $bookTitle (מקטע $startIndex) עם הדגשה: $highlightText'
              : 'נפתח ספר: $bookTitle עם הדגשה: $highlightText';
          } else {
            message = startIndex > 0 
              ? 'נפתח ספר: $bookTitle (מקטע $startIndex)'
              : 'נפתח ספר: $bookTitle';
          }
          UiSnack.show(message);
        }
      }
      
      debugPrint('HtmlLinkHandler: Successfully handled sharing link');
    } catch (e) {
      debugPrint('HtmlLinkHandler: שגיאה בטיפול בקישור שיתוף: $e');

      if (context.mounted) {
        UiSnack.show('לא ניתן לפתוח את הקישור: $e');
      }
    }
  }

  /// מחלץ שם ספר מנתיב קובץ
  static String _getTitleFromPath(String path) {
    // הסרת סיומת קובץ ונתיב
    String title = path.split('/').last.split('\\').last;
    if (title.endsWith('.txt')) {
      title = title.substring(0, title.length - 4);
    }
    return title;
  }



  /// מטפל בלחיצה על קישור HTML
  ///
  /// הפונקציה מפרשת קישורים בפורמטים הבאים:
  /// - book://שם_הסxxxxxxxxח ספר בתחילת הספר
  /// - book://שם_הספר#כותרת - פותח ספר ומנווט לכותרת ספציפית
  /// - #כותרת - מנווט לכותרת באותו ספר
  /// - otzaria://inline-link?path={path}&index={index}&ref={ref} - קישור מבוסס תווים
  ///
  /// דוגמאות:
  /// - <a href="book://ברכות">ברכות</a>
  /// - <a href="book://ברכות#דף ב">ברכות דף ב</a>
  /// - <a href="#דף ג">דף ג</a>
  static Future<bool> handleLink(
    BuildContext context,
    String url,
    Function(OpenedTab) openBookCallback,
  ) async {
    debugPrint('HtmlLinkHandler: handleLink called with URL: $url');
    
    try {
      // בדיקה אם זה קישור מבוסס תווים (inline-link)
      if (url.startsWith('otzaria://inline-link')) {
        debugPrint('HtmlLinkHandler: Processing inline-link');
        await _handleInlineLink(context, url, openBookCallback);
        return true;
      }

      // בדיקה אם זה קישור שיתוף (otzaria://book/ או otzaria://pdf/)
      if (url.startsWith('otzaria://book/') || url.startsWith('otzaria://pdf/')) {
        debugPrint('HtmlLinkHandler: Processing sharing link');
        await _handleSharingLink(context, url, openBookCallback);
        return true;
      }

      // בדיקה אם זה קישור פנימי לכותרת באותו ספר
      if (url.startsWith('#')) {
        final headerName = _safeDecode(url.substring(1));
        await _navigateToHeader(context, headerName);
        return true;
      }

      // בדיקה אם זה קישור לספר
      if (url.startsWith('book://')) {
        final bookUrl = url.substring(7); // הסרת "book://"

        String bookTitle;
        String? headerName;

        // בדיקה אם יש כותרת ספציפית
        if (bookUrl.contains('#')) {
          final parts = bookUrl.split('#');
          bookTitle = _safeDecode(parts[0]);

          // טיפול במבנה תלמודי: ספר#דף#צד
          if (parts.length >= 2) {
            if (parts.length == 3) {
              // מבנה מלא: ספר#דף#צד
              headerName = _safeDecode('${parts[1]} ${parts[2]}');
            } else {
              // מבנה רגיל: ספר#כותרת
              headerName = _safeDecode(parts[1]);
            }
          }
        } else {
          bookTitle = _safeDecode(bookUrl);
        }

        await _openBookWithHeader(
            context, bookTitle, headerName, openBookCallback);
        return true;
      }

      // אם זה לא קישור שאנחנו מטפלים בו, נחזיר false
      return false;
    } catch (e, stackTrace) {
      debugPrint('שגיאה בטיפול בקישור: $e');
      debugPrint('Stack trace: $stackTrace');

      // הצגת הודעת שגיאה למשתמש
      if (context.mounted) {
        UiSnack.show('שגיאה בפתיחת הקישור: $e');
      }

      return false;
    }
  }

  /// מנווט לכותרת באותו ספר הנוכחי
  static Future<void> _navigateToHeader(
      BuildContext context, String headerName) async {
    try {
      // נקבל את הספר הנוכחי מה-BLoC
      final textBookBloc = context.read<TextBookBloc>();
      final state = textBookBloc.state;

      if (state is! TextBookLoaded) {
        throw Exception('לא ניתן לנווט - הספר לא נטען');
      }

      // חיפוש הכותרת בתוכן הספציפי
      final index = await _findHeaderIndex(state.book, headerName);

      if (index != null) {
        // ניווט לאינדקס שנמצא
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

  /// פותח ספר ומנווט לכותרת ספציפית (אם צוינה)
  static Future<void> _openBookWithHeader(
    BuildContext context,
    String bookTitle,
    String? headerName,
    Function(OpenedTab) openBookCallback,
  ) async {
    try {
      // חיפוש הספר בספרייה
      final library = await DataRepository.instance.library;

      // קבלת רשימת כל הספרים לבדיקה
      final allBooks = library.getAllBooks();

      final foundBook = library.findBookByTitle(bookTitle, TextBook);

      if (foundBook == null) {
        // נסה לחפש בלי להגביל לטיפוס TextBook
        final anyBook = library.findBookByTitle(bookTitle, null);

        if (anyBook != null) {
          throw Exception(
              'הספר "$bookTitle" נמצא אבל הוא מטיפוס ${anyBook.runtimeType}, לא TextBook');
        }

        // הצגת רשימת ספרים זמינים למשתמש
        final availableBooks = allBooks.take(10).map((b) => b.title).join(', ');
        throw Exception(
            'לא נמצא ספר בשם: "$bookTitle".\nספרים זמינים (דוגמאות): $availableBooks');
      }

      // וידוא שזה TextBook
      if (foundBook is! TextBook) {
        throw Exception('הספר $bookTitle אינו ספר טקסט');
      }

      final book = foundBook;
      int startIndex = 0;

      // אם צוינה כותרת, נחפש את האינדקס שלה
      if (headerName != null && headerName.isNotEmpty) {
        final headerIndex = await _findHeaderIndex(book, headerName);
        if (headerIndex != null) {
          startIndex = headerIndex;
        } else {
          // אם לא נמצאה הכותרת, נציג אזהרה אבל עדיין נפתח את הספר
          if (context.mounted) {
            UiSnack.show(
                'לא נמצאה הכותרת "$headerName" בספר $bookTitle, פותח את תחילת הספר');
          }
        }
      }

      // פתיחת הספר
      final tab = TextBookTab(
        book: book,
        index: startIndex,
        openLeftPane: (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
            (Settings.getValue<bool>('key-default-sidebar-open') ?? false),
      );

      openBookCallback(tab);

      if (context.mounted && headerName != null && headerName.isNotEmpty) {
        UiSnack.show('פתח ספר: $bookTitle - $headerName');
      }
    } catch (e) {
      debugPrint('שגיאה בפתיחת ספר: $e');

      if (context.mounted) {
        UiSnack.show('לא ניתן לפתוח את הספר: $bookTitle');
      }
    }
  }

  /// מחפש את האינדקס של כותרת בספר
  static Future<int?> _findHeaderIndex(TextBook book, String headerName) async {
    try {
      // קבלת תוכן הספציפי
      final tableOfContents = await book.tableOfContents;

      // חיפוש בתוכן העניינים - קודם חיפוש מדויק
      for (final entry in tableOfContents) {
        if (isHeaderMatch(entry.text, headerName)) {
          return entry.index;
        }
      }

      // אם לא נמצא, ננסה לחפש רק לפי מספר הדף (בלי עמוד)
      // זה עוזר כשהקישור כולל עמוד שלא קיים בתוכן העניינים
      final pageOnlyMatch = _extractPageNumber(headerName);
      if (pageOnlyMatch != null) {
        for (final entry in tableOfContents) {
          final entryPageMatch = _extractPageNumber(entry.text);
          if (entryPageMatch != null && entryPageMatch == pageOnlyMatch) {
            return entry.index;
          }
        }
      }

      // אם לא נמצא בתוכן העניינים, נחפש בתוכן הספר עצמו
      final content = await book.text;
      final lines = content.split('\n');

      // חיפוש מדויק
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        final cleanLine = line.replaceAll(RegExp(r'<[^>]*>'), '').trim();

        if (isHeaderMatch(cleanLine, headerName)) {
          return i;
        }
      }

      // חיפוש לפי דף בלבד
      if (pageOnlyMatch != null) {
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
          final cleanLine = line.replaceAll(RegExp(r'<[^>]*>'), '').trim();
          final linePageMatch = _extractPageNumber(cleanLine);

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

  /// מחלץ את מספר הדף מכותרת (למשל "דף כג א" -> "כג")
  static String? _extractPageNumber(String text) {
    // דפוס לזיהוי מספר דף עברי
    final pagePattern = RegExp(r'דף\s+([א-ת]{1,3})');
    final match = pagePattern.firstMatch(text);
    if (match != null) {
      return match.group(1);
    }

    // אם אין "דף", ננסה למצוא מספר עברי בתחילת המחרוזת
    final numberPattern = RegExp(r'^([א-ת]{1,3})(?:\s|$)');
    final numberMatch = numberPattern.firstMatch(text.trim());
    if (numberMatch != null) {
      return numberMatch.group(1);
    }

    return null;
  }

  /// בדיקה אם טקסט תואם לכותרת המבוקשת
  static bool isHeaderMatch(String text, String headerName) {
    // ניקוי הטקסטים לצורך השוואה
    final cleanText = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final cleanHeader = headerName.trim().replaceAll(RegExp(r'\s+'), ' ');

    // השוואה מדויקת
    if (cleanText == cleanHeader) {
      return true;
    }

    // השוואה ללא רגישות לרווחים
    if (cleanText.replaceAll(' ', '') == cleanHeader.replaceAll(' ', '')) {
      return true;
    }

    // בדיקה אם הכותרת מכילה את הטקסט המבוקש
    if (cleanText.contains(cleanHeader)) {
      return true;
    }

    // בדיקה הפוכה - אם הטקסט המבוקש מכיל את הכותרת
    if (cleanHeader.contains(cleanText)) {
      return true;
    }

    return false;
  }
}

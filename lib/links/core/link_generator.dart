/// יצירת קישורים לספרים
library;

import 'package:otzaria/links/models/link_models.dart';
import 'package:otzaria/links/utils/url_encoding.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';

/// מחלקה ליצירת קישורים לספרים
class LinkGenerator {
  
  /// יצירת קישור מ-BookLink
  static String generateUrl(BookLink link) {
    switch (link.type) {
      case LinkType.textBook:
        return _generateOtzariaBookUrl(link, 'book');
      case LinkType.pdfBook:
        return _generateOtzariaBookUrl(link, 'pdf');
      case LinkType.simpleBook:
        return _generateSimpleBookUrl(link);
      case LinkType.internal:
        return _generateInternalUrl(link);
      case LinkType.inlineLink:
        return _generateInlineUrl(link);
      case LinkType.external:
        return link.bookTitle; // עבור קישורים חיצוניים, השם הוא ה-URL
    }
  }

  /// יצירת קישור otzaria://book/ או otzaria://pdf/
  static String _generateOtzariaBookUrl(BookLink link, String scheme) {
    final encodedTitle = UrlEncoding.safeEncode(link.bookTitle);
    final baseUrl = 'otzaria://$scheme/$encodedTitle';
    
    final params = <String, String>{};
    
    // הוספת פרמטר position
    if (link.position != null) {
      if (scheme == 'pdf') {
        params['page'] = link.position.toString();
      } else {
        params['index'] = link.position.toString();
      }
    }
    
    // הוספת פרמטר text
    if (link.fullSectionHighlight) {
      params['text'] = 'true';
    } else if (link.highlightText != null && link.highlightText!.isNotEmpty) {
      params['text'] = link.highlightText!;
    }
    
    // הוספת פרמטרים נוספים
    params.addAll(link.additionalParams);
    
    final queryString = UrlEncoding.buildQueryString(params);
    return '$baseUrl$queryString';
  }

  /// יצירת קישור book://
  static String _generateSimpleBookUrl(BookLink link) {
    final encodedTitle = UrlEncoding.safeEncode(link.bookTitle);
    String url = 'book://$encodedTitle';
    
    if (link.header != null && link.header!.isNotEmpty) {
      final encodedHeader = UrlEncoding.safeEncode(link.header!);
      url += '#$encodedHeader';
    }
    
    return url;
  }

  /// יצירת קישור פנימי
  static String _generateInternalUrl(BookLink link) {
    if (link.header == null || link.header!.isEmpty) {
      return '#';
    }
    
    final encodedHeader = UrlEncoding.safeEncode(link.header!);
    return '#$encodedHeader';
  }

  /// יצירת קישור inline
  static String _generateInlineUrl(BookLink link) {
    final params = <String, String>{};
    
    if (link.filePath != null && link.filePath!.isNotEmpty) {
      params['path'] = link.filePath!;
    }
    
    if (link.position != null) {
      params['index'] = (link.position! + 1).toString(); // המרה ל-1-based
    }
    
    if (link.reference != null && link.reference!.isNotEmpty) {
      params['ref'] = link.reference!;
    }
    
    final queryString = UrlEncoding.buildQueryString(params);
    return 'otzaria://inline-link$queryString';
  }

  /// יצירת קישור מספר
  static BookLink createLinkFromBook(Book book, {
    int? position,
    String? highlightText,
    bool fullSectionHighlight = false,
    String? header,
  }) {
    final linkType = book is PdfBook ? LinkType.pdfBook : LinkType.textBook;
    
    return BookLink(
      bookTitle: book.title,
      type: linkType,
      position: position,
      highlightText: highlightText,
      fullSectionHighlight: fullSectionHighlight,
      header: header,
    );
  }

  /// יצירת קישור מטאב פתוח
  static BookLink createLinkFromTab(OpenedTab tab) {
    if (tab is TextBookTab) {
      return BookLink(
        bookTitle: tab.book.title,
        type: LinkType.textBook,
        position: tab.index,
        highlightText: tab.searchText.isEmpty ? null : tab.searchText,
      );
    } else if (tab is PdfBookTab) {
      return BookLink(
        bookTitle: tab.book.title,
        type: LinkType.pdfBook,
        position: tab.pageNumber,
      );
    }
    
    throw ArgumentError('Unsupported tab type: ${tab.runtimeType}');
  }

  /// יצירת קישור שיתוף מהיר
  static String createSharingUrl(Book book, {
    int? position,
    String? highlightText,
    bool fullSectionHighlight = false,
  }) {
    final link = createLinkFromBook(
      book,
      position: position,
      highlightText: highlightText,
      fullSectionHighlight: fullSectionHighlight,
    );
    
    return generateUrl(link);
  }

  /// יצירת קישור פשוט לספר (ללא פרמטרים)
  static String createSimpleBookUrl(String bookTitle) {
    final link = BookLink(
      bookTitle: bookTitle,
      type: LinkType.simpleBook,
    );
    
    return generateUrl(link);
  }

  /// יצירת קישור לכותרת ספציפית בספר
  static String createBookHeaderUrl(String bookTitle, String header) {
    final link = BookLink(
      bookTitle: bookTitle,
      type: LinkType.simpleBook,
      header: header,
    );
    
    return generateUrl(link);
  }

  /// יצירת קישור פנימי לכותרת
  static String createInternalHeaderUrl(String header) {
    final link = BookLink(
      bookTitle: '',
      type: LinkType.internal,
      header: header,
    );
    
    return generateUrl(link);
  }
}
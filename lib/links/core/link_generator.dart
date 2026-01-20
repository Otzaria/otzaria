/// יצירת קישורים לספרים
library;

import '../models/link.dart';
import '../models/link_types.dart';
import '../utils/encoding.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';

/// מחלקה ליצירת קישורים
class LinkGenerator {
  
  /// יצירת URL מ-BookLink
  static String generate(BookLink link) {
    switch (link.type) {
      case LinkType.textBook:
        return _generateOtzariaUrl(link, 'book');
      case LinkType.pdfBook:
        return _generateOtzariaUrl(link, 'pdf');
      case LinkType.simpleBook:
        return _generateSimpleUrl(link);
      case LinkType.internal:
        return _generateInternalUrl(link);
      case LinkType.inlineLink:
        return _generateInlineUrl(link);
      case LinkType.external:
        return link.bookTitle; // עבור קישורים חיצוניים
    }
  }

  /// יצירת קישור otzaria://
  static String _generateOtzariaUrl(BookLink link, String scheme) {
    final encodedTitle = UrlEncoding.encode(link.bookTitle);
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
    params.addAll(link.params);
    
    final queryString = UrlEncoding.buildQuery(params);
    return '$baseUrl$queryString';
  }

  /// יצירת קישור book://
  static String _generateSimpleUrl(BookLink link) {
    final encodedTitle = UrlEncoding.encode(link.bookTitle);
    String url = 'book://$encodedTitle';
    
    if (link.header != null && link.header!.isNotEmpty) {
      final encodedHeader = UrlEncoding.encode(link.header!);
      url += '#$encodedHeader';
    }
    
    return url;
  }

  /// יצירת קישור פנימי
  static String _generateInternalUrl(BookLink link) {
    if (link.header == null || link.header!.isEmpty) {
      return '#';
    }
    
    final encodedHeader = UrlEncoding.encode(link.header!);
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
    
    final queryString = UrlEncoding.buildQuery(params);
    return 'otzaria://inline-link$queryString';
  }

  /// יצירת קישור מספר
  static BookLink fromBook(
    Book book, {
    int? position,
    String? highlightText,
    bool fullSectionHighlight = false,
    String? header,
  }) {
    if (book is PdfBook) {
      return BookLink.pdfBook(book.title, page: position);
    } else {
      return BookLink.textBook(
        book.title,
        index: position,
        highlightText: highlightText,
        fullSectionHighlight: fullSectionHighlight,
      );
    }
  }

  /// יצירת קישור מטאב פתוח
  static BookLink fromTab(OpenedTab tab) {
    if (tab is TextBookTab) {
      return BookLink.textBook(
        tab.book.title,
        index: tab.index,
        highlightText: tab.searchText.isEmpty ? null : tab.searchText,
      );
    } else if (tab is PdfBookTab) {
      return BookLink.pdfBook(
        tab.book.title,
        page: tab.pageNumber,
      );
    }
    
    throw ArgumentError('Unsupported tab type: ${tab.runtimeType}');
  }

  /// יצירת URL לשיתוף מהיר
  static String createSharingUrl(
    Book book, {
    int? position,
    String? highlightText,
    bool fullSectionHighlight = false,
  }) {
    final link = fromBook(
      book,
      position: position,
      highlightText: highlightText,
      fullSectionHighlight: fullSectionHighlight,
    );
    
    return generate(link);
  }

  /// יצירת קישור פשוט לספר
  static String createSimpleUrl(String bookTitle) {
    final link = BookLink.simple(bookTitle);
    return generate(link);
  }

  /// יצירת קישור לכותרת ספציפית
  static String createHeaderUrl(String bookTitle, String header) {
    final link = BookLink.simple(bookTitle, header: header);
    return generate(link);
  }

  /// יצירת קישור פנימי לכותרת
  static String createInternalUrl(String header) {
    final link = BookLink.internal(header);
    return generate(link);
  }
}
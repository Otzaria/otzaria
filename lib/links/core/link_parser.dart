/// פענוח קישורים לספרים
library;

import 'package:flutter/foundation.dart';
import '../models/link.dart';
import '../models/link_types.dart';
import '../utils/encoding.dart';
import '../utils/validation.dart';

/// מחלקה לפענוח קישורים
class LinkParser {
  
  /// פענוח קישור מ-URL string
  static LinkParseResult parse(String url) {
    if (url.isEmpty) {
      return LinkParseResult.empty();
    }

    try {
      final cleanUrl = UrlEncoding.clean(url);
      
      // זיהוי סוג הקישור ופענוח
      if (cleanUrl.startsWith('otzaria://inline-link')) {
        return _parseInlineLink(cleanUrl);
      } else if (cleanUrl.startsWith('otzaria://book/')) {
        return _parseOtzariaLink(cleanUrl, LinkType.textBook);
      } else if (cleanUrl.startsWith('otzaria://pdf/')) {
        return _parseOtzariaLink(cleanUrl, LinkType.pdfBook);
      } else if (cleanUrl.startsWith('book://')) {
        return _parseSimpleLink(cleanUrl);
      } else if (cleanUrl.startsWith('#')) {
        return _parseInternalLink(cleanUrl);
      } else if (LinkValidation.isExternalUrl(cleanUrl)) {
        return _parseExternalLink(cleanUrl);
      } else {
        return _parseImplicitLink(cleanUrl);
      }
    } catch (e) {
      debugPrint('LinkParser: Error parsing URL: $url, error: $e');
      return LinkParseResult.failure('שגיאה בפענוח הקישור: $e');
    }
  }

  /// פענוח קישור inline
  static LinkParseResult _parseInlineLink(String url) {
    try {
      final uri = Uri.parse(url);
      final params = LinkValidation.validateUrlParams(uri.queryParameters);
      
      final path = params['path'];
      final indexStr = params['index'];
      final ref = params['ref'];

      if (path == null || path.isEmpty) {
        return LinkParseResult.missingParams('נתיב חסר');
      }

      final index = int.tryParse(indexStr ?? '');
      if (index == null) {
        return LinkParseResult.missingParams('אינדקס לא תקין');
      }

      final bookTitle = UrlEncoding.extractTitle(path);
      
      final link = BookLink.inline(
        bookTitle,
        filePath: path,
        index: index - 1, // המרה מ-1-based ל-0-based
        reference: ref,
      );

      return LinkParseResult.success(link);
    } catch (e) {
      return LinkParseResult.failure('שגיאה בפענוח קישור inline: $e');
    }
  }

  /// פענוח קישור otzaria://book/ או otzaria://pdf/
  static LinkParseResult _parseOtzariaLink(String url, LinkType type) {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;
      
      if (pathSegments.isEmpty) {
        return LinkParseResult.missingParams('שם ספר חסר');
      }

      final bookTitle = UrlEncoding.decode(pathSegments.first);
      if (!LinkValidation.isValidBookTitle(bookTitle)) {
        return LinkParseResult.invalidFormat('שם ספר לא תקין');
      }

      final params = LinkValidation.validateUrlParams(uri.queryParameters);
      
      // עיבוד פרמטרים
      int? position;
      String? highlightText;
      bool fullSectionHighlight = false;
      
      // טיפול בפרמטר page/index
      if (params.containsKey('page')) {
        position = int.tryParse(params['page']!);
      } else if (params.containsKey('index')) {
        position = int.tryParse(params['index']!);
      }

      // טיפול בפרמטר text
      final textParam = params['text'];
      if (textParam == 'true') {
        fullSectionHighlight = true;
      } else if (textParam != null && textParam.isNotEmpty) {
        highlightText = textParam;
      }

      final link = type == LinkType.pdfBook
          ? BookLink.pdfBook(bookTitle, page: position, params: params)
          : BookLink.textBook(
              bookTitle,
              index: position,
              highlightText: highlightText,
              fullSectionHighlight: fullSectionHighlight,
              params: params,
            );

      return LinkParseResult.success(link);
    } catch (e) {
      return LinkParseResult.failure('שגיאה בפענוח קישור otzaria: $e');
    }
  }

  /// פענוח קישור book://
  static LinkParseResult _parseSimpleLink(String url) {
    try {
      final bookUrl = url.substring(7); // הסרת "book://"
      
      String bookTitle;
      String? header;

      if (bookUrl.contains('#')) {
        final parts = bookUrl.split('#');
        bookTitle = UrlEncoding.decode(parts[0]);

        if (parts.length >= 2) {
          if (parts.length == 3) {
            // מבנה מלא: ספר#דף#צד
            header = UrlEncoding.decode('${parts[1]} ${parts[2]}');
          } else {
            // מבנה רגיל: ספר#כותרת
            header = UrlEncoding.decode(parts[1]);
          }
        }
      } else {
        bookTitle = UrlEncoding.decode(bookUrl);
      }

      if (!LinkValidation.isValidBookTitle(bookTitle)) {
        return LinkParseResult.invalidFormat('שם ספר לא תקין');
      }

      final link = BookLink.simple(bookTitle, header: header);
      return LinkParseResult.success(link);
    } catch (e) {
      return LinkParseResult.failure('שגיאה בפענוח קישור book: $e');
    }
  }

  /// פענוח קישור פנימי
  static LinkParseResult _parseInternalLink(String url) {
    try {
      final header = UrlEncoding.decode(url.substring(1));
      
      if (!LinkValidation.isValidHeader(header)) {
        return LinkParseResult.missingParams('כותרת ריקה');
      }

      final link = BookLink.internal(header);
      return LinkParseResult.success(link);
    } catch (e) {
      return LinkParseResult.failure('שגיאה בפענוח קישור פנימי: $e');
    }
  }

  /// פענוח קישור חיצוני
  static LinkParseResult _parseExternalLink(String url) {
    try {
      final link = BookLink.external(url);
      return LinkParseResult.success(link);
    } catch (e) {
      return LinkParseResult.failure('שגיאה בפענוח קישור חיצוני: $e');
    }
  }

  /// פענוח קישור ללא פרוטוקול מפורש
  static LinkParseResult _parseImplicitLink(String url) {
    try {
      // בדיקה לפרמטרי inline
      if (LinkValidation.hasInlineParams(url)) {
        return _parseInlineLink('otzaria://inline-link?$url');
      }
      
      // בדיקה לפרמטרי ספר
      if (LinkValidation.hasBookParams(url)) {
        final linkType = url.toLowerCase().contains('pdf') || url.contains('.pdf')
            ? LinkType.pdfBook
            : LinkType.textBook;
        
        final protocol = linkType == LinkType.pdfBook ? 'otzaria://pdf/' : 'otzaria://book/';
        return _parseOtzariaLink('$protocol$url', linkType);
      }

      // אחרת, נתייחס אליו כקישור book פשוט
      return _parseSimpleLink('book://$url');
    } catch (e) {
      return LinkParseResult.failure('לא ניתן לזהות את סוג הקישור: $e');
    }
  }

  /// בדיקה אם טקסט הוא קישור תקין
  static bool isValid(String text) {
    return LinkValidation.isValidUrl(text);
  }
}
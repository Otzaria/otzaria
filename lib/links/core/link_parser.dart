/// פענוח וניתוח קישורים
library;

import 'package:flutter/foundation.dart';
import 'package:otzaria/links/models/link_models.dart';
import 'package:otzaria/links/utils/url_encoding.dart';

/// מחלקה לפענוח קישורים לספרים
class LinkParser {
  
  /// פענוח קישור מ-URL string
  static LinkParseResult parseUrl(String url) {
    if (url.isEmpty) {
      return const LinkParseResult.failure('URL ריק');
    }

    try {
      final cleanUrl = UrlEncoding.cleanUrl(url);
      
      // זיהוי סוג הקישור
      if (cleanUrl.startsWith('otzaria://inline-link')) {
        return _parseInlineLink(cleanUrl);
      } else if (cleanUrl.startsWith('otzaria://book/')) {
        return _parseOtzariaBookLink(cleanUrl, LinkType.textBook);
      } else if (cleanUrl.startsWith('otzaria://pdf/')) {
        return _parseOtzariaBookLink(cleanUrl, LinkType.pdfBook);
      } else if (cleanUrl.startsWith('book://')) {
        return _parseSimpleBookLink(cleanUrl);
      } else if (cleanUrl.startsWith('#')) {
        return _parseInternalLink(cleanUrl);
      } else if (cleanUrl.startsWith('http://') || cleanUrl.startsWith('https://')) {
        return _parseExternalLink(cleanUrl);
      } else {
        // נסיון לזהות קישור ללא פרוטוקול
        return _parseImplicitLink(cleanUrl);
      }
    } catch (e) {
      debugPrint('LinkParser: שגיאה בפענוח קישור: $url, שגיאה: $e');
      return LinkParseResult.failure('שגיאה בפענוח הקישור: $e');
    }
  }

  /// פענוח קישור inline (otzaria://inline-link)
  static LinkParseResult _parseInlineLink(String url) {
    try {
      final uri = Uri.parse(url);
      final params = uri.queryParameters;
      
      final path = UrlEncoding.safeDecode(params['path'] ?? '');
      final indexStr = params['index'] ?? '';
      final ref = UrlEncoding.safeDecode(params['ref'] ?? '');

      if (path.isEmpty) {
        return const LinkParseResult.failure('נתיב לא תקין בקישור inline');
      }

      final index = int.tryParse(indexStr);
      if (index == null) {
        return const LinkParseResult.failure('אינדקס לא תקין בקישור inline');
      }

      final bookTitle = UrlEncoding.extractTitleFromPath(path);
      
      final link = BookLink(
        bookTitle: bookTitle,
        type: LinkType.inlineLink,
        position: index - 1, // המרה מ-1-based ל-0-based
        filePath: path,
        reference: ref.isEmpty ? null : ref,
      );

      return LinkParseResult.success(link);
    } catch (e) {
      return LinkParseResult.failure('שגיאה בפענוח קישור inline: $e');
    }
  }

  /// פענוח קישור otzaria://book/ או otzaria://pdf/
  static LinkParseResult _parseOtzariaBookLink(String url, LinkType type) {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;
      
      if (pathSegments.isEmpty) {
        return const LinkParseResult.failure('קישור לא תקין - חסר שם ספר');
      }

      // קבלת שם הספר וטיפול בקידוד
      String bookTitle = pathSegments.first;
      if (bookTitle.contains('%')) {
        try {
          bookTitle = Uri.decodeComponent(bookTitle);
        } catch (e) {
          // אם הפענוח נכשל, נשתמש בשם כמו שהוא
        }
      }

      final queryParams = uri.queryParameters;
      
      // עיבוד פרמטרים
      int? position;
      String? highlightText;
      bool fullSectionHighlight = false;
      
      // טיפול בפרמטר page/index
      if (queryParams.containsKey('page')) {
        position = int.tryParse(queryParams['page'] ?? '');
      } else if (queryParams.containsKey('index')) {
        position = int.tryParse(queryParams['index'] ?? '');
      }

      // טיפול בפרמטר text
      if (queryParams.containsKey('text')) {
        final textParam = queryParams['text'];
        if (textParam == 'true') {
          fullSectionHighlight = true;
        } else if (textParam != null && textParam.isNotEmpty) {
          try {
            highlightText = Uri.decodeComponent(textParam)
                .replaceAll('%20', ' ')
                .replaceAll('+', ' ')
                .trim();
          } catch (e) {
            highlightText = textParam
                .replaceAll('%20', ' ')
                .replaceAll('+', ' ')
                .trim();
          }
        }
      }

      final link = BookLink(
        bookTitle: bookTitle,
        type: type,
        position: position,
        highlightText: highlightText,
        fullSectionHighlight: fullSectionHighlight,
        additionalParams: Map.from(queryParams)..removeWhere((key, value) => 
            ['page', 'index', 'text'].contains(key)),
      );

      return LinkParseResult.success(link);
    } catch (e) {
      return LinkParseResult.failure('שגיאה בפענוח קישור otzaria: $e');
    }
  }

  /// פענוח קישור book://
  static LinkParseResult _parseSimpleBookLink(String url) {
    try {
      final bookUrl = url.substring(7); // הסרת "book://"
      
      String bookTitle;
      String? header;

      // בדיקה אם יש כותרת ספציפית
      if (bookUrl.contains('#')) {
        final parts = bookUrl.split('#');
        bookTitle = UrlEncoding.safeDecode(parts[0]);

        if (parts.length >= 2) {
          if (parts.length == 3) {
            // מבנה מלא: ספר#דף#צד
            header = UrlEncoding.safeDecode('${parts[1]} ${parts[2]}');
          } else {
            // מבנה רגיל: ספר#כותרת
            header = UrlEncoding.safeDecode(parts[1]);
          }
        }
      } else {
        bookTitle = UrlEncoding.safeDecode(bookUrl);
      }

      final link = BookLink(
        bookTitle: bookTitle,
        type: LinkType.simpleBook,
        header: header,
      );

      return LinkParseResult.success(link);
    } catch (e) {
      return LinkParseResult.failure('שגיאה בפענוח קישור book: $e');
    }
  }

  /// פענוח קישור פנימי (#)
  static LinkParseResult _parseInternalLink(String url) {
    try {
      final header = UrlEncoding.safeDecode(url.substring(1));
      
      if (header.isEmpty) {
        return const LinkParseResult.failure('כותרת ריקה בקישור פנימי');
      }

      final link = BookLink(
        bookTitle: '', // יהיה ריק עבור קישורים פנימיים
        type: LinkType.internal,
        header: header,
      );

      return LinkParseResult.success(link);
    } catch (e) {
      return LinkParseResult.failure('שגיאה בפענוח קישור פנימי: $e');
    }
  }

  /// פענוח קישור חיצוני (http/https)
  static LinkParseResult _parseExternalLink(String url) {
    try {
      final link = BookLink(
        bookTitle: url,
        type: LinkType.external,
      );

      return LinkParseResult.success(link);
    } catch (e) {
      return LinkParseResult.failure('שגיאה בפענוח קישור חיצוני: $e');
    }
  }

  /// פענוח קישור ללא פרוטוקול מפורש
  static LinkParseResult _parseImplicitLink(String url) {
    try {
      // אם יש פרמטרים אופייניים, זה כנראה קישור inline
      if (url.contains('path=') && url.contains('index=')) {
        return _parseInlineLink('otzaria://inline-link?$url');
      }
      
      // אם יש פרמטר page או index, זה כנראה קישור לספר
      if (url.contains('?page=') || url.contains('?index=')) {
        final linkType = url.toLowerCase().contains('pdf') || url.contains('.pdf')
            ? LinkType.pdfBook
            : LinkType.textBook;
        
        final protocol = linkType == LinkType.pdfBook ? 'otzaria://pdf/' : 'otzaria://book/';
        return _parseOtzariaBookLink('$protocol$url', linkType);
      }

      // אחרת, נתייחס אליו כקישור book פשוט
      return _parseSimpleBookLink('book://$url');
    } catch (e) {
      return LinkParseResult.failure('לא ניתן לזהות את סוג הקישור: $e');
    }
  }

  /// בדיקה אם טקסט הוא קישור תקין
  static bool isValidUrl(String text) {
    if (text.isEmpty) return false;
    
    final cleanText = text.trim();
    
    // בדיקה לקישורי otzaria
    if (cleanText.startsWith('otzaria://')) return true;
    
    // בדיקה לקישורי book
    if (cleanText.startsWith('book://')) return true;
    
    // בדיקה לקישורים פנימיים
    if (cleanText.startsWith('#')) return true;
    
    // בדיקה לקישורי HTTP/HTTPS
    if (cleanText.startsWith('http://') || cleanText.startsWith('https://')) return true;
    
    // בדיקה לקישורים שמכילים פרמטרים אופייניים
    if (cleanText.contains('path=') && cleanText.contains('index=')) return true;
    
    // בדיקה לקישורים שמכילים שמות ספרים עם פרמטרים
    if (cleanText.contains('?page=') || cleanText.contains('?index=') || cleanText.contains('?text=')) return true;
    
    return false;
  }
}
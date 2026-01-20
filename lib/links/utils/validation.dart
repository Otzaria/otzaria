/// בדיקות תקינות לקישורים
library;

/// מחלקה לבדיקת תקינות קישורים
class LinkValidation {
  
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
    
    // בדיקה לקישורים עם פרמטרים אופייניים
    if (hasInlineParams(cleanText)) return true;
    if (hasBookParams(cleanText)) return true;
    
    return false;
  }

  /// בדיקה לפרמטרי inline
  static bool hasInlineParams(String text) {
    return text.contains('path=') && text.contains('index=');
  }

  /// בדיקה לפרמטרי ספר
  static bool hasBookParams(String text) {
    final queryIndex = text.indexOf('?');
    if (queryIndex <= 0) return false;
    
    final hasParams = text.contains('page=') || 
                     text.contains('index=') || 
                     text.contains('text=');
    
    if (!hasParams) return false;
    
    // ודא שזה לא URL מלא
    final beforeQuery = text.substring(0, queryIndex);
    return !beforeQuery.contains('://');
  }

  /// בדיקה אם שם ספר תקין
  static bool isValidBookTitle(String title) {
    if (title.isEmpty) return false;
    if (title.trim().isEmpty) return false;
    
    // בדיקה לתווים לא חוקיים
    final invalidChars = RegExp(r'[<>:"/\\|?*]');
    if (invalidChars.hasMatch(title)) return false;
    
    return true;
  }

  /// בדיקה אם אינדקס תקין
  static bool isValidIndex(int? index) {
    return index != null && index >= 0;
  }

  /// בדיקה אם עמוד תקין
  static bool isValidPage(int? page) {
    return page != null && page > 0;
  }

  /// בדיקה אם כותרת תקינה
  static bool isValidHeader(String? header) {
    return header != null && header.trim().isNotEmpty;
  }

  /// בדיקה אם נתיב קובץ תקין
  static bool isValidFilePath(String? path) {
    if (path == null || path.isEmpty) return false;
    
    // בדיקה בסיסית לנתיב
    return path.contains('/') || path.contains('\\') || path.endsWith('.txt');
  }

  /// בדיקה אם URL הוא otzaria scheme
  static bool isOtzariaUrl(String url) {
    return url.startsWith('otzaria://');
  }

  /// בדיקה אם URL הוא book scheme
  static bool isBookUrl(String url) {
    return url.startsWith('book://');
  }

  /// בדיקה אם URL הוא קישור פנימי
  static bool isInternalUrl(String url) {
    return url.startsWith('#');
  }

  /// בדיקה אם URL הוא קישור חיצוני
  static bool isExternalUrl(String url) {
    return url.startsWith('http://') || url.startsWith('https://');
  }

  /// בדיקה מקיפה של פרמטרי URL
  static Map<String, String> validateUrlParams(Map<String, String> params) {
    final validParams = <String, String>{};
    
    for (final entry in params.entries) {
      final key = entry.key.trim();
      final value = entry.value.trim();
      
      if (key.isEmpty || value.isEmpty) continue;
      
      // בדיקות ספציפיות לפרמטרים
      switch (key) {
        case 'index':
        case 'page':
          final num = int.tryParse(value);
          if (num != null && num >= 0) {
            validParams[key] = value;
          }
          break;
        case 'text':
          if (value == 'true' || value.isNotEmpty) {
            validParams[key] = value;
          }
          break;
        case 'path':
          if (isValidFilePath(value)) {
            validParams[key] = value;
          }
          break;
        case 'ref':
          if (value.isNotEmpty) {
            validParams[key] = value;
          }
          break;
        default:
          // פרמטרים אחרים - נקבל אותם כמו שהם
          validParams[key] = value;
      }
    }
    
    return validParams;
  }
}
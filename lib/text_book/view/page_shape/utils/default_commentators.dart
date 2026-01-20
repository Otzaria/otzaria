import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/links/links.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;

/// מחלקה לניהול ברירות מחדל של מפרשים לפי סוג הספר
/// ההגדרות נטענות מקובץ JSON חיצוני
class DefaultCommentators {
  /// מחזיר מפרשי ברירת מחדל לפי קטגוריית הספר
  /// מקבל גם את רשימת הקישורים כדי למצוא את השמות המלאים של המפרשים
  static Future<Map<String, String?>> getDefaults(TextBook book, {List<Link>? links}) async {
    final config = await _loadConfig();
    
    // קבלת נתיב הספר
    final titleToPath = await book.data.titleToPath;
    final bookPath = titleToPath[book.title] ?? '';
    
    // קבלת שמות המפרשים מה-JSON
    final defaults = _getDefaultsFromConfig(config, book.title, bookPath);
    
    // אם יש links, נחפש את השמות המלאים של המפרשים
    if (links != null && links.isNotEmpty) {
      return _resolveCommentatorNames(defaults, links);
    }
    
    return defaults;
  }

  /// מחפש את השמות המלאים של המפרשים מתוך רשימת הקישורים
  static Map<String, String?> _resolveCommentatorNames(
      Map<String, String?> defaults, List<Link> links) {
    // קבלת רשימת שמות המפרשים הזמינים
    final availableCommentators = links
        .where((link) =>
            link.connectionType == 'commentary' ||
            link.connectionType == 'targum')
        .map((link) => utils.getTitleFromPath(link.path2))
        .toSet()
        .toList();

    return {
      'right': _findMatchingCommentator(defaults['right'], availableCommentators),
      'left': _findMatchingCommentator(defaults['left'], availableCommentators),
      'bottom': _findMatchingCommentator(defaults['bottom'], availableCommentators),
      'bottomRight': _findMatchingCommentator(defaults['bottomRight'], availableCommentators),
    };
  }

  /// מחפש מפרש שמתאים לשם הנתון
  /// מחזיר את השם המלא אם נמצא, או null אם לא
  static String? _findMatchingCommentator(String? shortName, List<String> available) {
    if (shortName == null) return null;
    
    // 1. התאמה מדויקת
    String? match = available.firstWhereOrNull((name) => name == shortName);
    if (match != null) return match;
    
    // 2. התאמה של התחלה
    match = available.firstWhereOrNull((name) => name.startsWith(shortName));
    if (match != null) return match;
    
    // 3. התאמה של הכלה
    return available.firstWhereOrNull((name) => name.contains(shortName));
  }

  static Future<Map<String, dynamic>> _loadConfig() async {
    try {
      final jsonString =
          await rootBundle.loadString('assets/default_commentators.json');
      return json.decode(jsonString) as Map<String, dynamic>;
    } catch (e, s) {
      debugPrint('Failed to load default commentators config: $e\n$s');
      return {
        'categories': [],
        'default': {
          'right': null,
          'left': null,
          'bottom': null,
          'bottomRight': null,
        }
      };
    }
  }

  static Map<String, String?> _getDefaultsFromConfig(
      Map<String, dynamic> config, String bookTitle, String bookPath) {
    final categories = config['categories'] as List<dynamic>;

    for (final category in categories) {
      if (_matchesCategory(bookPath, category as Map<String, dynamic>)) {
        return _parseCommentators(
            category['commentators'] as Map<String, dynamic>, bookTitle);
      }
    }

    final defaultConfig = config['default'] as Map<String, dynamic>;
    return _parseCommentators(defaultConfig, bookTitle);
  }

  static bool _matchesCategory(
      String bookPath, Map<String, dynamic> category) {
    // pathContains - כל המחרוזות חייבות להיות בנתיב (AND)
    if (category.containsKey('pathContains')) {
      final pathContains = category['pathContains'] as List<dynamic>;
      if (!pathContains.every((p) => bookPath.contains(p as String))) {
        return false;
      }
    }

    // pathContainsAny - לפחות מחרוזת אחת חייבת להיות בנתיב (OR)
    if (category.containsKey('pathContainsAny')) {
      final pathContainsAny = category['pathContainsAny'] as List<dynamic>;
      if (!pathContainsAny.any((p) => bookPath.contains(p as String))) {
        return false;
      }
    }

    // pathNotContains - אף מחרוזת לא יכולה להיות בנתיב
    if (category.containsKey('pathNotContains')) {
      final pathNotContains = category['pathNotContains'] as List<dynamic>;
      if (pathNotContains.any((p) => bookPath.contains(p as String))) {
        return false;
      }
    }

    return true;
  }

  static Map<String, String?> _parseCommentators(
      Map<String, dynamic> commentators, String bookTitle) {
    return {
      'right': _replaceBookTitle(commentators['right'] as String?, bookTitle),
      'left': _replaceBookTitle(commentators['left'] as String?, bookTitle),
      'bottom': _replaceBookTitle(commentators['bottom'] as String?, bookTitle),
      'bottomRight':
          _replaceBookTitle(commentators['bottomRight'] as String?, bookTitle),
    };
  }

  static String? _replaceBookTitle(String? template, String bookTitle) {
    if (template == null) return null;
    return template.replaceAll('{bookTitle}', bookTitle);
  }
}

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/book_common/utils/commentator_name_matching.dart';
import 'package:otzaria/book_common/utils/category_settings_utils.dart';

/// מפרשים קבועים לקטגוריה בתצוגת הקריאה הרגילה (issue #866).
///
/// שכבת עקיפה מעל ברירת המחדל שמ-seforim.db: נשמרים שמות בסיסיים
/// ("רמב"ן" ולא "רמב"ן על ברכות"), והטעינה סורקת את שרשרת הקטגוריות של
/// הספר מהספציפית לכללית — באותה סמנטיקה של הגדרות הקטגוריה בצורת הדף.
class CategoryCommentatorsService {
  static const String _keyPrefix = 'commentators_category_';
  static const String _separator = '||';

  /// בחירה ריקה שנשמרה במפורש (להבדיל מהיעדר קביעה).
  static const String _emptyMarker = '__EMPTY__';

  /// שומר את [selection] כמפרשים הקבועים של [category], בשמות בסיסיים.
  static Future<void> save(
    String category,
    List<String> selection, {
    required String bookTitle,
  }) async {
    final baseNames = <String>[];
    for (final name in selection) {
      final base = commentatorBaseName(
        name,
        commentedBookTitle: bookTitle,
      );
      if (base != null && base.isNotEmpty && !baseNames.contains(base)) {
        baseNames.add(base);
      }
    }
    await Settings.setValue<String>(
      '$_keyPrefix$category',
      baseNames.isEmpty ? _emptyMarker : baseNames.join(_separator),
    );
  }

  /// השמות הבסיסיים שנקבעו לקטגוריה הרלוונטית ביותר של הספר, או null
  /// כשאין קביעה. רשימה ריקה = המשתמש קבע במפורש "ללא מפרשים".
  static List<String>? loadBaseNames(String? heCategories) {
    final category = getActiveCategory(heCategories);
    if (category == null) return null;
    final raw = Settings.getValue<String>('$_keyPrefix$category');
    if (raw == null || raw.isEmpty) return null;
    if (raw == _emptyMarker) return const [];
    return raw.split(_separator).where((name) => name.isNotEmpty).toList();
  }

  /// האם קיימת קביעה לקטגוריה [category].
  static bool hasCategorySettings(String category) {
    if (!Settings.isInitialized) return false;
    final raw = Settings.getValue<String>('$_keyPrefix$category');
    return raw != null && raw.isNotEmpty;
  }

  /// הקטגוריה שממנה תיטען הקביעה עבור [heCategories], או null.
  static String? getActiveCategory(String? heCategories) =>
      findActiveCategory(heCategories, hasCategorySettings);

  /// הסרת הקביעה של [category].
  static Future<void> reset(String category) async {
    await Settings.setValue<String?>('$_keyPrefix$category', null);
  }
}

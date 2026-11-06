import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/book_common/utils/commentator_identity_lookup.dart';
import 'package:otzaria/book_common/utils/commentator_name_matching.dart';
import 'package:otzaria/book_common/utils/category_settings_utils.dart';

/// מפרשים קבועים לקטגוריה בתצוגת הקריאה הרגילה (issue #866).
///
/// שכבת עקיפה מעל ברירת המחדל שמ-seforim.db: נשמרים מפתחות מפרש
/// ("רמב"ן" ולא "רמב"ן על ברכות"), והטעינה סורקת את שרשרת הקטגוריות של
/// הספר מהספציפית לכללית — באותה סמנטיקה של הגדרות הקטגוריה בצורת הדף.
class CategoryCommentatorsService {
  static const String _keyPrefix = 'commentators_category_';
  static const String _separator = '||';

  /// בחירה ריקה שנשמרה במפורש (להבדיל מהיעדר קביעה).
  static const String _emptyMarker = '__EMPTY__';

  /// שומר את [selection] כמפרשים הקבועים של [category], כמפתחות מפרש.
  static Future<void> save(
    String category,
    List<String> selection, {
    required String bookTitle,
  }) async {
    final identities = await lookupCommentatorIdentities(selection);
    final keys = <String>[];
    for (final name in selection) {
      final key = commentatorKey(
        name,
        commentedBookTitle: bookTitle,
        identities: identities,
      );
      if (key.isNotEmpty && !keys.contains(key)) keys.add(key);
    }
    await Settings.setValue<String>(
      '$_keyPrefix$category',
      keys.isEmpty ? _emptyMarker : keys.join(_separator),
    );
  }

  /// מפתחות המפרשים שנקבעו לקטגוריה הרלוונטית ביותר של הספר, או null
  /// כשאין קביעה. רשימה ריקה = המשתמש קבע במפורש "ללא מפרשים".
  static List<String>? loadKeys(String? heCategories) {
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

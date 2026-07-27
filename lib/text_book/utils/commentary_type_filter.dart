import 'package:flutter/foundation.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

/// לוגיקת צ׳יפי הסינון לפי סוג מפרש (תרגום/מדרש/ביאור וכד׳), משותפת לכל
/// המסכים שמציגים את פאנל בחירת המפרשים. בלעדיה כל מסך היה משכפל את החישוב
/// והצ׳יפים היו מסננים במסך אחד בלבד.
class CommentaryTypeFilter {
  const CommentaryTypeFilter._();

  /// מפתחות צ׳יפי סוגי המפרשים שקיימים בפועל ב-[links], בסדר
  /// [LinkTypes.commentaryFilterTypes]. סוג בלי קישורים אינו מקבל צ׳יפ.
  static List<String> chipKeys(List<Link> links) {
    final present = <String>{};
    for (final link in links) {
      if (LinkTypes.isCommentaryFilterType(link.connectionType)) {
        present.add(LinkTypes.canonicalType(link.connectionType));
      }
    }
    return LinkTypes.commentaryFilterTypes
        .where(present.contains)
        .toList(growable: false);
  }

  /// כמו [chipKeys], אך מתעלם מקישורים שספרם אינו ב-[selectedCommentators] —
  /// כדי שלא יוצג צ׳יפ לסוג שכל מפרשיו מוסתרים.
  static List<String> chipKeysForCommentators({
    required List<Link> links,
    required List<String> selectedCommentators,
  }) {
    final commentatorsSet = selectedCommentators.toSet();
    return chipKeys(
      links
          .where(
            (link) =>
                commentatorsSet.contains(utils.getTitleFromPath(link.path2)),
          )
          .toList(growable: false),
    );
  }

  /// מיפוי סוג קנוני → שמות המפרשים שיש להם קישור מאותו סוג. משמש לצמצום
  /// רשימת המפרשים בפאנל הבחירה, כדי שצ׳יפ סוג יסנן אותה כמו צ׳יפ דור.
  static Map<String, Set<String>> commentatorsByType(List<Link> links) {
    final byType = <String, Set<String>>{};
    for (final link in links) {
      if (!LinkTypes.isCommentaryFilterType(link.connectionType)) continue;
      final type = LinkTypes.canonicalType(link.connectionType);
      (byType[type] ??= <String>{}).add(utils.getTitleFromPath(link.path2));
    }
    return byType;
  }

  /// הבחירה האפקטיבית: רק מפתחות שיש להם צ׳יפ בקטע הנוכחי. בחירה שאין לה אף
  /// צ׳יפ קיים נחשבת ריקה = הצג הכל, ולא מסתירה את כל המפרשים.
  static Set<String> effectiveTypes({
    required Set<String> selectedTypes,
    required List<String> availableKeys,
  }) {
    if (selectedTypes.isEmpty) return const {};
    final available = availableKeys.toSet();
    return selectedTypes.where(available.contains).toSet();
  }

  /// סוג יחיד אינו מסנן כלום, ולכן הצ׳יפים מוצגים רק משניים ומעלה — אלא אם
  /// הוא הנבחר, שאז בלעדיהם המשתמש מסונן בשקט בלי דרך לבטל.
  static List<String> visibleChipKeys({
    required List<String> chipKeys,
    required Set<String> effectiveTypes,
  }) => chipKeys.length > 1 || effectiveTypes.isNotEmpty
      ? chipKeys
      : const <String>[];
}

/// מחזיק את בחירת סוגי המפרשים ומודיע למאזינים בשינוי. מאפשר להורה (כרטיסיית
/// המפרשים) להציג את הצ׳יפים בלשונית צדדית בעוד הרשימה מסוננת ברכיב אחר.
///
/// המצב מקומי בכוונה ואינו נשמר להגדרות: הצ׳יפים תלויים בספר הפתוח, ובחירה
/// שנשמרה הייתה מסננת בשקט ספר אחר שנפתח אחריו.
class CommentaryTypeSelection extends ValueNotifier<Set<String>> {
  CommentaryTypeSelection() : super(const {});
}

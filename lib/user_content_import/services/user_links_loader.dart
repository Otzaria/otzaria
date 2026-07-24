import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/user_content_import/repository/user_content_repository.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

/// טוען קישורי-משתמש (מ-user_books.db) ככ-[Link] עבור ספר שנקרא, בשני
/// הכיוונים:
/// - forward: ספר-המשתמש מקושר ליעד (כשקוראים את ספר-המשתמש עצמו).
/// - inverse: ספר-משתמש אחר מצביע אל הספר הזה (כשקוראים רשמי/אישי שעליו
///   נכתב מפרש-משתמש) — כך מפרש-משתמש מופיע גם בספר הרשמי.
///
/// מחזיר רשימה ריקה אם user_books.db לא פתוח (בלי לכפות פתיחתו).
Future<List<Link>> loadUserLinksForBook({
  required String bookTitle,
  required int? bookCategoryId,
  required bool isUserBook,
  required int startLineIndex,
  required int endLineIndex,
  List<String>? targetBookTitles,
}) async {
  final repo = UserBooksDatabaseHolder.instance.repositoryIfInitialized;
  if (repo == null) return const [];

  final ucr = UserContentRepository(repo.database);
  final result = <Link>[];

  // forward — קישורים היוצאים מהספר הנקרא (אישי או רשמי).
  final forward = await ucr.forwardUserLinks(
    bookTitle,
    sourceIsUserBook: isUserBook,
    sourceCategoryId: bookCategoryId,
    startLineIndex: startLineIndex,
    endLineIndex: endLineIndex,
  );
  for (final r in forward) {
    final targetLine = r.targetLineIndex;
    // ללא יעד-שורה אין לאן לפתוח (index2==0 נכשל כ-"Invalid link reference").
    if (targetLine == null) continue;
    result.add(
      Link(
        heRef: r.targetRef ?? r.targetTitle,
        index1: r.sourceLineIndex + 1,
        path2: r.targetTitle,
        index2: targetLine + 1,
        connectionType: r.connectionType,
        targetCategoryId: r.targetCategoryId,
        targetIsUserBook: r.targetIsUserBook,
      ),
    );
  }

  // inverse — קישור-משתמש שמצביע אל הספר הנקרא; פתיחתו חוזרת אל ספר המקור
  // (אישי או רשמי, לפי sourceIsUserBook).
  final inverse = await ucr.inverseUserLinks(
    bookTitle,
    targetIsUserBook: isUserBook,
    targetCategoryId: bookCategoryId,
    startLineIndex: startLineIndex,
    endLineIndex: endLineIndex,
  );
  for (final r in inverse) {
    final targetLine = r.targetLineIndex;
    if (targetLine == null) continue;
    result.add(
      Link(
        heRef: r.sourceTitle,
        index1: targetLine + 1,
        path2: r.sourceTitle,
        index2: r.sourceLineIndex + 1,
        // כמו ה-inverse של seforim.db: מפרש שקורא את בסיסו רואה אותו כ'מקור'
        // וירטואלי בפאנל הקישורים, לא כמפרש.
        connectionType: LinkTypes.isDependentTextLink(r.connectionType)
            ? LinkTypes.source
            : r.connectionType,
        targetIsUserBook: r.sourceIsUserBook,
        targetCategoryId: r.sourceCategoryId,
      ),
    );
  }

  return _applyCommentatorFilter(dedupeUserLinks(result), targetBookTitles);
}

/// כותרות מפרשי-המשתמש של ספר — להזנת רשימת המפרשים לבחירה (שאחרת נבנית
/// רק מ-seforim.db ואינה מכירה קישורי-משתמש). ריק אם user_books.db לא פתוח.
Future<List<String>> loadUserCommentatorTitles({
  required String bookTitle,
  required int? bookCategoryId,
  required bool isUserBook,
}) async {
  final repo = UserBooksDatabaseHolder.instance.repositoryIfInitialized;
  if (repo == null) return const [];
  return UserContentRepository(repo.database).userCommentatorTitles(
    bookTitle,
    sourceIsUserBook: isUserBook,
    sourceCategoryId: bookCategoryId,
  );
}

/// מסיר כפילויות בין forward ל-inverse: קישור דו-כיווני (כמו שמייצר "מנהל
/// המפרשים והקישורים") מיובא משני קבצים ומופיע משני הכיוונים — זהו אותו קישור.
/// ה-forward נוסף ראשון ולכן נשמר (ה-heRef שלו עדיף).
@visibleForTesting
List<Link> dedupeUserLinks(List<Link> links) {
  final seen = <String>{};
  // המפתח כולל גם דגל-אישי וקטגוריה — שני ספרים שונים יכולים לחלוק כותרת.
  return links
      .where(
        (l) => seen.add(
          '${l.index1}|${l.path2}|${l.index2}|'
          '${l.connectionType}|${l.targetIsUserBook}|${l.targetCategoryId}',
        ),
      )
      .toList();
}

/// מסנן קישורי-מפרש לפי המפרשים הנבחרים (כמו הסינון ב-getLinksForBookRange):
/// קישור תלוי-טקסט נכלל רק אם כותרת היעד נבחרה; קישורי הפניה תמיד עוברים.
List<Link> _applyCommentatorFilter(
  List<Link> links,
  List<String>? targetBookTitles,
) {
  if (targetBookTitles == null) return links;
  final selected = targetBookTitles.toSet();
  return links.where((link) {
    if (!LinkTypes.isDependentTextLink(link.connectionType)) return true;
    return selected.contains(utils.getTitleFromPath(link.path2));
  }).toList();
}

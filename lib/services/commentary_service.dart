import 'package:otzaria/models/links.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;

/// מייצג קבוצת קטעי פירוש רצופים מאותו ספר
///
/// הערה: שונה מ-CommentatorGroup שמייצג קבוצת מפרשים לפי תקופה.
/// LinkGroup מייצג קבוצה של קישורים (Links) שכולם מאותו ספר.
class LinkGroup {
  final String bookTitle;
  final List<Link> links;

  const LinkGroup({
    required this.bookTitle,
    required this.links,
  });

  /// מספר הקישורים בקבוצה
  int get count => links.length;

  /// האם הקבוצה ריקה
  bool get isEmpty => links.isEmpty;

  /// האם הקבוצה לא ריקה
  bool get isNotEmpty => links.isNotEmpty;
}

/// סדר הדורות למיון
enum CommentaryEra {
  torahShebichtav(0, 'תורה שבכתב'),
  chazal(1, 'חז"ל'),
  rishonim(2, 'ראשונים'),
  acharonim(3, 'אחרונים'),
  modern(4, 'מחברי זמננו'),
  other(5, 'שאר מפרשים');

  final int order;
  final String hebrewName;

  const CommentaryEra(this.order, this.hebrewName);
}

/// שירות מרכזי לטיפול בלוגיקת המפרשים
///
/// מרכז את כל הפעולות הנפוצות על מפרשים וקישורים:
/// - קיבוץ קישורים לפי ספר
/// - מיון לפי דורות
/// - סינון לפי מפרשים פעילים
class CommentaryService {
  /// מקבץ רשימת קישורים לקבוצות לפי שם הספר (רק קטעים רצופים)
  ///
  /// [links] - רשימת הקישורים לקיבוץ
  ///
  /// מחזיר רשימת קבוצות כאשר כל קבוצה מכילה קישורים רצופים מאותו ספר
  static List<LinkGroup> groupConsecutiveLinks(List<Link> links) {
    if (links.isEmpty) return [];

    final groups = <LinkGroup>[];
    String? currentTitle;
    List<Link> currentGroup = [];

    for (final link in links) {
      final title = utils.getTitleFromPath(link.path2);

      if (currentTitle == null || currentTitle != title) {
        // ספר חדש - שומר את הקבוצה הקודמת ומתחיל קבוצה חדשה
        if (currentGroup.isNotEmpty) {
          groups.add(LinkGroup(
            bookTitle: currentTitle!,
            links: List.unmodifiable(currentGroup),
          ));
        }
        currentTitle = title;
        currentGroup = [link];
      } else {
        // אותו ספר - מוסיף לקבוצה הנוכחית
        currentGroup.add(link);
      }
    }

    // מוסיף את הקבוצה האחרונה
    if (currentGroup.isNotEmpty) {
      groups.add(LinkGroup(
        bookTitle: currentTitle!,
        links: List.unmodifiable(currentGroup),
      ));
    }

    return groups;
  }

  /// מחזיר את הדור של ספר לפי שמו
  ///
  /// [bookTitle] - שם הספר
  ///
  /// מחזיר את הדור המתאים, או [CommentaryEra.other] אם לא נמצא
  static Future<CommentaryEra> getBookEra(String bookTitle) async {
    if (await utils.hasTopic(bookTitle, 'תורה שבכתב')) {
      return CommentaryEra.torahShebichtav;
    } else if (await utils.hasTopic(bookTitle, 'חז"ל')) {
      return CommentaryEra.chazal;
    } else if (await utils.hasTopic(bookTitle, 'ראשונים')) {
      return CommentaryEra.rishonim;
    } else if (await utils.hasTopic(bookTitle, 'אחרונים')) {
      return CommentaryEra.acharonim;
    } else if (await utils.hasTopic(bookTitle, 'מחברי זמננו')) {
      return CommentaryEra.modern;
    } else {
      return CommentaryEra.other;
    }
  }

  /// ממיין קבוצות מפרשים לפי סדר הדורות
  ///
  /// [groups] - רשימת הקבוצות למיון
  ///
  /// מחזיר רשימה ממוינת לפי: תורה שבכתב -> חז"ל -> ראשונים -> אחרונים -> מחברי זמננו -> שאר מפרשים
  /// בתוך כל דור, המיון הוא אלפביתי לפי שם הספר
  static Future<List<LinkGroup>> sortGroupsByEra(List<LinkGroup> groups) async {
    if (groups.isEmpty) return groups;

    // יצירת מפה של כל שם ספר לדור שלו
    final Map<String, CommentaryEra> eraMap = {};

    for (final group in groups) {
      eraMap[group.bookTitle] = await getBookEra(group.bookTitle);
    }

    // מיון הקבוצות לפי הדור
    final sortedGroups = List<LinkGroup>.from(groups);
    sortedGroups.sort((a, b) {
      final eraA = eraMap[a.bookTitle] ?? CommentaryEra.other;
      final eraB = eraMap[b.bookTitle] ?? CommentaryEra.other;

      if (eraA.order != eraB.order) {
        return eraA.order.compareTo(eraB.order);
      }

      // אם שני הספרים באותו דור, ממיינים לפי שם
      return a.bookTitle.compareTo(b.bookTitle);
    });

    return sortedGroups;
  }

  /// מקבץ וממיין קישורים בפעולה אחת
  ///
  /// [links] - רשימת הקישורים
  ///
  /// מחזיר קבוצות ממוינות לפי דור
  static Future<List<LinkGroup>> groupAndSortLinks(List<Link> links) async {
    final groups = groupConsecutiveLinks(links);
    return sortGroupsByEra(groups);
  }

  /// מסנן קישורים לפי אינדקסים ומפרשים פעילים
  ///
  /// זהו wrapper ל-getLinksforIndexs הקיימת, לשמירת API אחיד
  static Future<List<Link>> filterLinks({
    required List<int> indexes,
    required List<Link> links,
    required List<String> activeCommentators,
  }) async {
    return getLinksforIndexs(
      indexes: indexes,
      links: links,
      commentatorsToShow: activeCommentators,
    );
  }

  /// מסנן, מקבץ וממיין קישורים בפעולה אחת
  ///
  /// [indexes] - אינדקסים של שורות להצגת מפרשים
  /// [links] - כל הקישורים
  /// [activeCommentators] - רשימת המפרשים הפעילים
  ///
  /// מחזיר קבוצות ממוינות של קישורים מסוננים
  static Future<List<LinkGroup>> getGroupedCommentaries({
    required List<int> indexes,
    required List<Link> links,
    required List<String> activeCommentators,
  }) async {
    final filteredLinks = await filterLinks(
      indexes: indexes,
      links: links,
      activeCommentators: activeCommentators,
    );
    return groupAndSortLinks(filteredLinks);
  }

  /// בודק אם יש מפרשים זמינים לאינדקסים מסוימים
  ///
  /// [indexes] - אינדקסים לבדיקה
  /// [links] - כל הקישורים
  /// [activeCommentators] - רשימת המפרשים הפעילים
  static bool hasCommentaries({
    required List<int> indexes,
    required List<Link> links,
    required List<String> activeCommentators,
  }) {
    if (activeCommentators.isEmpty || indexes.isEmpty) return false;

    final indexSet = indexes.map((i) => i + 1).toSet();
    final commentatorsSet = activeCommentators.toSet();

    return links.any((link) {
      if (!indexSet.contains(link.index1)) return false;
      if (link.connectionType != "commentary" &&
          link.connectionType != "targum") {
        return false;
      }
      return commentatorsSet.contains(utils.getTitleFromPath(link.path2));
    });
  }
}

import 'package:flutter/foundation.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'dart:isolate';

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

  /// התווית בפאנל הקישורים, שבו היעדים אינם בהכרח מפרשים (דף גמרא, פסוק,
  /// סימן בשו"ע) ולכן "שאר מפרשים" שגוי שם.
  String get linkPanelName =>
      this == CommentaryEra.other ? 'ספרים נוספים' : hebrewName;
}

/// שירות מרכזי לטיפול בלוגיקת המפרשים
///
/// מרכז את כל הפעולות הנפוצות על מפרשים וקישורים:
/// - קיבוץ קישורים לפי ספר
/// - מיון לפי דורות
/// - סינון לפי מפרשים פעילים
class CommentaryService {
  static const int _asyncGroupingThreshold = 80;

  /// מטמון דורות לפי שם ספר - ממולא ע"י [preloadEras]
  ///
  /// מאפשר מיון סינכרוני (כמו בתפריט ההקשר) לאחר שהדורות נטענו פעם אחת
  static final Map<String, CommentaryEra> _eraCache = {};

  static int _eraCacheVersion = 0;

  /// גרסת מטמון הדורות. עולה בכל ניקוי, כדי שצרכנים שמזכירים "כבר טענתי"
  /// יידעו שעליהם לטעון מחדש.
  static int get eraCacheVersion => _eraCacheVersion;

  /// מנקה את מטמון הדורות
  ///
  /// יש לקרוא בעת רענון/איפוס הספרייה, כדי שסיווגי דורות ישנים לא יישארו
  /// בזיכרון לאחר החלפת נתונים.
  static void clearEraCache() {
    // המטמון כאן נגזר מ-_csvCache שב-text_manipulation; ניקוי שלו בלבד מותיר
    // את המקור המיושן וממלא את המטמון מחדש מאותם נתונים.
    utils.clearCommentatorOrderCache();
    _eraCache.clear();
    _eraCacheVersion++;
  }

  /// מזין דורות ישירות למטמון, לטסטים שאין בהם DB.
  @visibleForTesting
  static void seedEraCache(Map<String, CommentaryEra> eras) =>
      _eraCache.addAll(eras);

  /// מפתח צ׳יפ יציב לדור, במרחב מפתחות נפרד מסוגי הקישור.
  static String eraChipKey(CommentaryEra era) =>
      '${LinkTypes.eraKeyPrefix}${era.name.toUpperCase()}';

  /// הדור שמאחורי מפתח צ׳יפ, או null אם אין זה מפתח דור מוכר.
  static CommentaryEra? eraFromChipKey(String key) {
    if (!LinkTypes.isEraKey(key)) return null;
    final name = key.substring(LinkTypes.eraKeyPrefix.length);
    for (final era in CommentaryEra.values) {
      if (era.name.toUpperCase() == name) return era;
    }
    return null;
  }

  /// מפתח הצ׳יפ של קישור: סוג הקישור הקנוני, או מפתח דור ספר היעד עבור
  /// סוגים שתווית הסוג שלהם חסרת משמעות ([LinkTypes.eraGroupedTypes]).
  static String linkChipKey(Link link) {
    final type = LinkTypes.canonicalType(link.connectionType);
    if (!LinkTypes.eraGroupedTypes.contains(type)) return type;
    return eraChipKey(getCachedBookEra(utils.getTitleFromPath(link.path2)));
  }

  /// כל מפתחות הצ׳יפ שקישור משתייך אליהם: [linkChipKey], ובנוסף
  /// [LinkTypes.onBookKey] כשספר היעד הוא ספר "על [openBookTitle]".
  /// קישור יכול להשתייך לכמה צ׳יפים, והסינון ביניהם הוא איחוד.
  static Set<String> linkChipKeys(Link link, {String? openBookTitle}) {
    final keys = {linkChipKey(link)};
    if (isLinkOnBook(link, openBookTitle)) keys.add(LinkTypes.onBookKey);
    return keys;
  }

  /// האם ספר היעד של [link] הוא ספר "על [openBookTitle]" (כמו "רש״י על ברכות").
  /// מחקה את בדיקת הנושא בפאנל המפרשים (`utils.hasTopic`).
  static bool isLinkOnBook(Link link, String? openBookTitle) {
    final bookTitle = openBookTitle?.trim() ?? '';
    if (bookTitle.isEmpty) return false;
    return utils.getTitleFromPath(link.path2).contains('על $bookTitle');
  }

  /// התווית של מפתח צ׳יפ — לדורות, לסוגי קישור ולצ׳יפ "על <הספר הפתוח>".
  static String chipKeyLabel(String key, {String? openBookTitle}) {
    if (key == LinkTypes.onBookKey) return 'על ${openBookTitle ?? ''}'.trim();
    final era = eraFromChipKey(key);
    if (era != null) return era.linkPanelName;
    return LinkTypes.hebrewLabel(key);
  }

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
    String? lastPath;

    for (final link in links) {
      final String title;
      if (link.path2 == lastPath) {
        title = currentTitle!;
      } else {
        title = utils.getTitleFromPath(link.path2);
      }

      if (currentTitle == null || currentTitle != title) {
        // ספר חדש - שומר את הקבוצה הקודמת ומתחיל קבוצה חדשה
        if (currentGroup.isNotEmpty) {
          groups.add(
            LinkGroup(
              bookTitle: currentTitle!,
              links: List.unmodifiable(currentGroup),
            ),
          );
        }
        currentTitle = title;
        lastPath = link.path2;
        currentGroup = [link];
      } else {
        // אותו ספר - מוסיף לקבוצה הנוכחית
        currentGroup.add(link);
      }
    }

    // מוסיף את הקבוצה האחרונה
    if (currentGroup.isNotEmpty) {
      groups.add(
        LinkGroup(
          bookTitle: currentTitle!,
          links: List.unmodifiable(currentGroup),
        ),
      );
    }

    return groups;
  }

  /// מקבץ רשימת קישורים לקבוצות בצורה אסינכרונית כדי לא לחסום את ה-UI
  static Future<List<LinkGroup>> groupConsecutiveLinksAsync(
    List<Link> links,
  ) async {
    if (links.isEmpty) {
      return const [];
    }

    if (links.length <= _asyncGroupingThreshold) {
      return groupConsecutiveLinks(links);
    }

    return Isolate.run(() => groupConsecutiveLinks(links));
  }

  /// מחזיר את הדור של ספר מפרש לפי שמו (מתוך טבלת המחברים ב-DB)
  ///
  /// [bookTitle] - שם הספר
  ///
  /// מחזיר את הדור המתאים, או [CommentaryEra.other] אם לא נמצא.
  ///
  /// שאילתה חיה לספר בודד, ל-fallback של FindRef בלבד. לכל מיון יש להשתמש
  /// ב-[preloadEras] + [getCachedBookEra] — שאילתה מרוכזת אחת לכל הספרייה.
  static Future<CommentaryEra> getBookEra(String bookTitle) async {
    try {
      final repo = SqliteDataProvider.instance.repository;
      if (repo == null) return CommentaryEra.other;
      final generationInfo = await repo.getBookGenerationInfoByTitle(bookTitle);
      if (generationInfo == null) return CommentaryEra.other;
      return _mapGenerationNameToEra(generationInfo.generationName);
    } catch (e) {
      return CommentaryEra.other;
    }
  }

  /// ממפה שם דור מה-DB ל-CommentaryEra
  static CommentaryEra _mapGenerationNameToEra(String generationName) {
    for (final era in CommentaryEra.values) {
      if (era.hebrewName == generationName) return era;
    }
    return CommentaryEra.other;
  }

  /// מחזיר את הדור של ספר מהמטמון בלבד (סינכרוני)
  ///
  /// מחזיר [CommentaryEra.other] אם הדור עדיין לא נטען.
  /// יש להפעיל [preloadEras] מראש כדי למלא את המטמון.
  static CommentaryEra getCachedBookEra(String bookTitle) =>
      _eraCache[bookTitle] ?? CommentaryEra.other;

  /// טוען מראש את דורות הקישורים אל המטמון (לשימוש [sortLinksByEraSync])
  ///
  /// הדור נלקח מ-[utils.splitByEra] (טבלת book_generation ב-DB). ספר שאינו
  /// מתויג ב-DB מסווג כ"שאר מפרשים".
  ///
  /// [bookTitles] - שמות הספרים לטעינה (כפילויות מסוננות אוטומטית)
  static Future<void> preloadEras(Iterable<String> bookTitles) async {
    final missing = bookTitles
        .toSet()
        .where((t) => !_eraCache.containsKey(t))
        .toList();
    if (missing.isEmpty) return;

    final byEra = await utils.splitByEra(missing);
    // טבלת הדורות לא נטענה => כל הכותרות יצאו "מפרשים נוספים". שמירתן הייתה
    // מקבעת את הסיווג השגוי, כי preloadEras מדלגת על כותרת שכבר במטמון.
    if (!utils.isEraTableLoaded) return;

    for (final entry in byEra.entries) {
      final era = _eraFromCategory(entry.key);
      for (final title in entry.value) {
        _eraCache[title] = era;
      }
    }
  }

  /// ממפה שם קטגוריית דור (כפי שמחזירה [utils.splitByEra]) ל-CommentaryEra
  static CommentaryEra _eraFromCategory(String category) {
    for (final era in CommentaryEra.values) {
      if (era.hebrewName == category) return era;
    }
    // 'מפרשים נוספים' וכל קטגוריה לא מוכרת -> שאר מפרשים
    return CommentaryEra.other;
  }

  /// ממיין קבוצות מפרשים לפי סדר הדורות
  ///
  /// [groups] - רשימת הקבוצות למיון
  ///
  /// מחזיר רשימה ממוינת לפי: תורה שבכתב -> חז"ל -> ראשונים -> אחרונים -> מחברי זמננו -> שאר מפרשים
  /// בתוך כל דור, המיון הוא אלפביתי לפי שם הספר
  static Future<List<LinkGroup>> sortGroupsByEra(List<LinkGroup> groups) async {
    if (groups.length <= 1) return groups;

    await preloadEras(groups.map((group) => group.bookTitle));
    return sortGroupsByEraSync(groups);
  }

  /// ממיין קבוצות מפרשים לפי דורות מתוך המטמון בלבד (סינכרוני)
  ///
  /// יש לקרוא ל-[preloadEras] מראש; ספר שאינו במטמון ימוין כ"שאר מפרשים".
  static List<LinkGroup> sortGroupsByEraSync(List<LinkGroup> groups) {
    if (groups.length <= 1) return groups;

    final present = groups.map((g) => g.bookTitle).toSet();
    final baseByTitle = {
      for (final g in groups)
        g.bookTitle: _notesBaseInSet(g.bookTitle, present),
    };

    // מיון הקבוצות לפי הדור, כשספר "הערות על XX" מעוגן לדור ולמיקום של XX
    final sortedGroups = List<LinkGroup>.from(groups);
    sortedGroups.sort((a, b) {
      final anchorA = baseByTitle[a.bookTitle] ?? a.bookTitle;
      final anchorB = baseByTitle[b.bookTitle] ?? b.bookTitle;
      final eraA = getCachedBookEra(anchorA);
      final eraB = getCachedBookEra(anchorB);

      if (eraA.order != eraB.order) {
        return eraA.order.compareTo(eraB.order);
      }
      final anchorCompare = anchorA.compareTo(anchorB);
      if (anchorCompare != 0) return anchorCompare;

      // באותו עוגן - הבסיס לפני ההערות עליו
      final noteA = baseByTitle[a.bookTitle] != null ? 1 : 0;
      final noteB = baseByTitle[b.bookTitle] != null ? 1 : 0;
      if (noteA != noteB) return noteA.compareTo(noteB);

      return a.bookTitle.compareTo(b.bookTitle);
    });

    return sortedGroups;
  }

  /// מחזיר את ספר-הבסיס של "הערות על XX" רק אם XX נמצא ב-[present], אחרת null.
  static String? _notesBaseInSet(String title, Set<String> present) {
    final base = utils.notesBookBaseTitle(title);
    return (base != null && present.contains(base)) ? base : null;
  }

  /// הדור שלפיו [sortLinksByEraSync] מציב את [link] בתוך [presentTitles].
  ///
  /// ספר "הערות על XX" מעוגן לדור של XX, ולכן מי שמקבץ את הרשימה הממוינת
  /// (למשל פס מבדיל בין דורות) חייב את אותה נוסחה — [getCachedBookEra] על
  /// כותרת הפריט עצמו היה מחזיר "שאר מפרשים" ושובר את הקיבוץ.
  static CommentaryEra sortingEraForLink(
    Link link,
    Set<String> presentTitles,
  ) {
    final title = utils.getTitleFromPath(link.path2);
    return getCachedBookEra(_notesBaseInSet(title, presentTitles) ?? title);
  }

  /// ממיין רשימת קישורים שטוחה לפי סדר הדורות
  ///
  /// [links] - רשימת הקישורים למיון
  ///
  /// מחזיר רשימה ממוינת לפי: תורה שבכתב -> חז"ל -> ראשונים -> אחרונים -> מחברי זמננו -> שאר מפרשים
  /// בתוך כל דור המיון הוא אלפביתי לפי שם הספר, ובתוך אותו ספר לפי מיקום הקטע
  static Future<List<Link>> sortLinksByEra(List<Link> links) async {
    if (links.length <= 1) return links;

    // טעינת הדורות של כל ספרי היעד מראש, ואז מיון סינכרוני מהמטמון
    await preloadEras(links.map((link) => utils.getTitleFromPath(link.path2)));
    return sortLinksByEraSync(links);
  }

  /// ממיין רשימת קישורים לפי דורות באופן סינכרוני מתוך המטמון
  ///
  /// משמש בהקשרים סינכרוניים (כמו תפריט הקשר) שבהם אי אפשר להמתין ל-DB.
  /// ספרים שדורם עדיין לא במטמון יטופלו כ"שאר מפרשים".
  /// יש לקרוא ל-[preloadEras] מראש כדי לוודא שהמטמון מלא.
  static List<Link> sortLinksByEraSync(List<Link> links) {
    if (links.length <= 1) return links;

    final titlesByPath = <String, String>{};
    for (final link in links) {
      titlesByPath.putIfAbsent(
        link.path2,
        () => utils.getTitleFromPath(link.path2),
      );
    }

    final present = titlesByPath.values.toSet();
    final eraMap = <String, CommentaryEra>{
      for (final title in present) title: getCachedBookEra(title),
    };
    final baseByTitle = <String, String?>{
      for (final title in present) title: _notesBaseInSet(title, present),
    };

    final sorted = List<Link>.from(links);
    sorted.sort(
      (a, b) => _compareLinksByEra(a, b, titlesByPath, eraMap, baseByTitle),
    );
    return sorted;
  }

  /// משווה שני קישורים לפי דור -> שם ספר -> מיקום קטע.
  /// ספר "הערות על XX" מעוגן לדור ולשם של XX, ומוצב מיד אחריו.
  static int _compareLinksByEra(
    Link a,
    Link b,
    Map<String, String> titlesByPath,
    Map<String, CommentaryEra> eraMap,
    Map<String, String?> baseByTitle,
  ) {
    final titleA = titlesByPath[a.path2]!;
    final titleB = titlesByPath[b.path2]!;
    final anchorA = baseByTitle[titleA] ?? titleA;
    final anchorB = baseByTitle[titleB] ?? titleB;
    final eraA = eraMap[anchorA] ?? CommentaryEra.other;
    final eraB = eraMap[anchorB] ?? CommentaryEra.other;

    if (eraA.order != eraB.order) {
      return eraA.order.compareTo(eraB.order);
    }

    // באותו דור - מיון אלפביתי לפי שם העוגן
    final anchorCompare = anchorA.compareTo(anchorB);
    if (anchorCompare != 0) return anchorCompare;

    // באותו עוגן - הבסיס לפני ההערות עליו
    final noteA = baseByTitle[titleA] != null ? 1 : 0;
    final noteB = baseByTitle[titleB] != null ? 1 : 0;
    if (noteA != noteB) return noteA.compareTo(noteB);

    // שני ספרי הערות שונים על אותו בסיס - לפי שמם
    final titleCompare = titleA.compareTo(titleB);
    if (titleCompare != 0) return titleCompare;

    // באותו ספר - שמירת סדר הקטעים
    return a.index2.compareTo(b.index2);
  }

  /// מקבץ וממיין קישורים בפעולה אחת
  ///
  /// [links] - רשימת הקישורים
  ///
  /// מחזיר קבוצות ממוינות לפי דור
  /// הדורות חייבים להיטען מראש; מטמון קר נופל למיון אלפביתי כדי לא לחסום UI.
  static Future<List<LinkGroup>> groupAndSortLinks(List<Link> links) async {
    final groups = await groupConsecutiveLinksAsync(links);
    return sortGroupsByEraSync(groups);
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
    String? lastPath;
    String? lastTitle;

    return links.any((link) {
      if (!indexSet.contains(link.index1)) return false;
      if (!LinkTypes.isDependentTextLink(link.connectionType)) return false;
      if (link.path2 != lastPath) {
        lastPath = link.path2;
        lastTitle = utils.getTitleFromPath(link.path2);
      }
      return commentatorsSet.contains(lastTitle);
    });
  }
}

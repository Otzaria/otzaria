/* represents links between two books in the library*/

import 'dart:collection';

import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/utils/text/ref_helper.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

/// שורת סיכום של קישורי ספר לפי ספר-יעד וסוג חיבור — תחליף קל-משקל לטעינת
/// כל הקישורים כשנדרשת רק רשימת המפרשים/היעדים של הספר (פאנל מפרשים ב-PDF).
class LinkTargetSummary {
  /// שם ספר היעד (שקול ל-[Link.path2]).
  final String targetTitle;

  /// שם סוג החיבור (שקול ל-[Link.connectionType]).
  final String connectionType;

  /// מספר הקישורים מסוג זה אל ספר היעד.
  final int linkCount;

  const LinkTargetSummary({
    required this.targetTitle,
    required this.connectionType,
    required this.linkCount,
  });
}

/// עוגן-מילה בודד של קישור בשורה המוצגת. קישור יכול לשאת כמה עוגנים
/// (למשל הערה אחת שמסומנת בשני מקומות בשורה).
class LinkAnchorSpan {
  final int start;
  final int? end;
  final String? label;

  const LinkAnchorSpan({required this.start, this.end, this.label});
}

/// Represents a link between two books in the library.
class Link {
  static const int _maxContentCacheEntries = 400;

  // חסום כמו _contentCache — בלי חסם המפה גדלה ללא גבול לאורך session
  // עם הרבה מפרשים (דליפה רכה). LinkedHashMap במפורש: פינוי ה-LRU מסתמך
  // על סדר ההכנסה.
  static const int _maxDisplayReferenceCacheEntries = 1000;
  static final LinkedHashMap<String, Future<String>> _displayReferenceCache =
      LinkedHashMap<String, Future<String>>();

  /// The Hebrew reference of the link.
  final String heRef;

  /// The index of the first book in the link.
  final int index1;

  /// The path of the second book in the link.
  final String path2;

  /// The index of the second book in the link.
  final int index2;

  /// The type of the connection in the link.
  final String connectionType;

  /// The category ID of the target book when known.
  final int? targetCategoryId;

  /// The file type of the target book when known.
  final String? targetFileType;

  /// Whether the target book lives in user_books.db (separate id space).
  /// Set for user-authored links so the target resolves to the right DB.
  final bool targetIsUserBook;

  /// The start character position of the link in the text (optional, for character-based links).
  final int? start;

  /// The end character position of the link in the text (optional, for character-based links).
  final int? end;

  /// עוגן-מילה מטבלת link_anchor שבמסד: אופסט בתווים *גלויים* (תגי HTML לא
  /// נספרים, entity = תו אחד — מוסכמת line.charCount) בשורת המקור שבה יושבת
  /// ההערה. null כשאין לקישור עוגן-מילה.
  final int? anchorStart;

  /// סוף טווח העוגן (אקסקלוסיבי), באותה מוסכמה. null לעוגן-נקודה.
  final int? anchorEnd;

  /// אות הסימון המודפסת (למשל "א") כשהמקור סיפק אותה.
  final String? anchorLabel;

  /// עוגן בצד המקושר (path2/index2) — הטווח המצוטט בתוך קטע-הפאנל, באותה
  /// מוסכמת תווים-גלויים. משמש להדגשת הציטוט בתוך תוכן הקישור המוצג.
  final int? linkedAnchorStart;
  final int? linkedAnchorEnd;

  /// כל עוגני הקישור בשורה המוצגת, ממוינים לפי מיקום. anchorStart/End/Label
  /// הם הראשון שבהם (לתאימות ולאות שבפאנל); ההזרקה לטקסט עוברת על כולם.
  final List<LinkAnchorSpan> anchorSpans;

  /// קישור-טווח: ה-heRef של השורה האחרונה בטווח בצד המקושר (path2), או null
  /// לקישור לשורה בודדת.
  final String? heRefEnd;

  /// קישור-טווח: אינדקס (1-based) של השורה האחרונה בטווח בצד המקושר, או null.
  final int? index2End;

  /// Creates a new instance of [Link] with the provided parameters.
  Link({
    required this.heRef,
    required this.index1,
    required this.path2,
    required this.index2,
    required this.connectionType,
    this.targetCategoryId,
    this.targetFileType,
    this.targetIsUserBook = false,
    this.start,
    this.end,
    this.anchorStart,
    this.anchorEnd,
    this.anchorLabel,
    this.linkedAnchorStart,
    this.linkedAnchorEnd,
    this.anchorSpans = const [],
    this.heRefEnd,
    this.index2End,
  });

  static final LinkedHashMap<String, Future<String>> _contentCache =
      LinkedHashMap<String, Future<String>>();

  /// Returns the content of the link as a [Future] of [String].
  /// The result is cached per (path2, index2) so repeated calls are instant.
  Future<String> get content {
    if (path2.isEmpty || index2 <= 0) {
      return Future<String>.error(
        StateError('Invalid link reference for commentary content'),
      );
    }
    // המפתח כולל את זהות היעד (אישי/רשמי+קטגוריה) כדי ששני קישורים לאותה
    // כותרת ואינדקס — אחד אישי ואחד רשמי — לא יחזירו זה את תוכן זה.
    final key =
        '$path2:$index2:${index2End ?? ''}:${targetIsUserBook ? 'u' : 'o'}:'
        '${targetCategoryId ?? ''}';
    final cached = _contentCache.remove(key);
    if (cached != null) {
      _contentCache[key] = cached;
      return cached;
    }

    final future = LibraryProviderManager.instance.getLinkContent(this);
    _contentCache[key] = future;
    if (_contentCache.length > _maxContentCacheEntries) {
      _contentCache.remove(_contentCache.keys.first);
    }
    return future;
  }

  /// ה-heRef כפי שהוא מוצג למשתמש, בלי הרמה האחרונה. בספר תלת-רמתי כמו
  /// רמב״ן על התורה (פרק × פסוק × פירוש) הרמה הזו היא אינדקס הפירוש בתוך
  /// הפסוק — "רמב״ן על דברים,  ז, ט, א" — וכשלפסוק יש פירוש אחד היא רעש.
  /// התצוגה בלבד; ה-heRef עצמו נשאר שלם ומשמש לקישוריות ולמטמונים.
  ///
  /// מקוצץ רק מ-4 רכיבים (שם הספר + 3 רמות), כי בכתובת תלת-רכיבית הרמה
  /// האחרונה היא יחידת ציטוט אמיתית — הס״ק של משנה ברורה ("משנה ברורה,  לב, ה").
  /// נשמר גם בקישור-טווח שמובחן ברמה האחרונה ("יח, י, ב–ג").
  static const int _minPartsToDropLastLevel = 4;

  String get _displayHeRef {
    final trimmed = heRef.trim();
    final end = heRefEnd?.trim();
    if (end != null && end.isNotEmpty && end != trimmed) return trimmed;

    final parts = trimmed.split(',');
    if (parts.length < _minPartsToDropLastLevel) return trimmed;
    return parts.sublist(0, parts.length - 1).join(',').trimRight();
  }

  /// סיומת טווח לכתובת התצוגה: לקישור-טווח מוסיפה "–<קצה>" כשרק הרכיב האחרון
  /// שונה (למשל "יח, י, ב–ג"), או " – <כתובת מלאה>" כשהכתובות שונות לגמרי.
  String get _rangeDisplaySuffix {
    final end = heRefEnd?.trim();
    if (end == null || end.isEmpty || end == heRef.trim()) return '';
    final startSegs = heRef.trim().split(', ');
    final endSegs = end.split(', ');
    var common = 0;
    while (common < startSegs.length - 1 &&
        common < endSegs.length - 1 &&
        startSegs[common] == endSegs[common]) {
      common++;
    }
    final tail = endSegs.sublist(common).join(', ');
    return common > 0 ? '–$tail' : ' – $tail';
  }

  /// מחזירה כתובת תצוגה בטוחה גם כאשר לא ניתן לחשב TOC מלא.
  String get fallbackDisplayReference {
    final targetTitle = utils.getTitleFromPath(path2);
    return formatDisplayReference(
          bookTitle: targetTitle,
          fallbackRef: _displayHeRef,
        ) +
        _rangeDisplaySuffix;
  }

  /// מחזירה כתובת תצוגה מלאה של ספר היעד, עם מטמון LRU לפי ספר ואינדקס.
  Future<String> get displayReference {
    final cacheKey =
        '${path2}_${index2}_${index2End ?? ''}_'
        '${targetIsUserBook ? 'u' : 'o'}_'
        '${targetCategoryId ?? ''}';
    final cached = _displayReferenceCache.remove(cacheKey);
    if (cached != null) {
      _displayReferenceCache[cacheKey] = cached;
      return cached;
    }
    final future = _computeDisplayReference();
    _displayReferenceCache[cacheKey] = future;
    if (_displayReferenceCache.length > _maxDisplayReferenceCacheEntries) {
      _displayReferenceCache.remove(_displayReferenceCache.keys.first);
    }
    return future;
  }

  Future<String> _computeDisplayReference() async {
    final targetTitle = utils.getTitleFromPath(path2);
    final targetFileType = _resolveTargetFileType();
    if (index2 <= 0) {
      return formatDisplayReference(
            bookTitle: targetTitle,
            fallbackRef: _displayHeRef,
          ) +
          _rangeDisplaySuffix;
    }

    try {
      final resolvedRef = await refFromIndex(
        index2 - 1,
        LibraryProviderManager.instance
            .getBookToc(
              targetTitle,
              categoryId: targetCategoryId,
              fileType: targetFileType,
              preferUserBooks: targetIsUserBook,
            )
            .then((toc) => toc ?? const <TocEntry>[]),
      );
      return formatDisplayReference(
            bookTitle: targetTitle,
            resolvedRef: resolvedRef,
            fallbackRef: _displayHeRef,
          ) +
          _rangeDisplaySuffix;
    } catch (_) {
      return formatDisplayReference(
            bookTitle: targetTitle,
            fallbackRef: _displayHeRef,
          ) +
          _rangeDisplaySuffix;
    }
  }

  String? _resolveTargetFileType() {
    if (targetFileType != null && targetFileType!.trim().isNotEmpty) {
      return targetFileType;
    }

    final normalizedPath = path2.replaceAll('\\', '/');
    final lastDot = normalizedPath.lastIndexOf('.');
    final lastSlash = normalizedPath.lastIndexOf('/');
    if (lastDot > lastSlash && lastDot != -1) {
      return normalizedPath.substring(lastDot + 1).toLowerCase();
    }

    return null;
  }

  /// Constructs a [Link] object from a JSON object.
  ///
  /// The JSON object should have the following keys:
  /// - 'heRef_2': The Hebrew reference of the link.
  /// - 'line_index_1': The index of the first book in the link.
  /// - 'path_2': The path of the second book in the link.
  /// - 'line_index_2': The index of the second book in the link.
  /// - 'Conection Type': The type of the connection in the link.
  /// - 'start': (optional) The start character position of the link.
  /// - 'end': (optional) The end character position of the link.
  Link.fromJson(Map<String, dynamic> json)
    : heRef = json['heRef_2'].toString(),
      index1 = int.parse(json['line_index_1'].toString().split('.').first),
      path2 = json['path_2'].toString(),
      index2 = int.parse(json['line_index_2'].toString().split('.').first),
      connectionType = json['Conection Type'].toString().isEmpty
          ? 'reference'
          : json['Conection Type'].toString(),
      targetCategoryId = json['category_id_2'] != null
          ? int.tryParse(json['category_id_2'].toString())
          : null,
      targetFileType = json['file_type_2']?.toString(),
      targetIsUserBook = false,
      start = json['start'] != null
          ? int.tryParse(json['start'].toString())
          : null,
      end = json['end'] != null ? int.tryParse(json['end'].toString()) : null,
      // עוגני-מילה מגיעים רק ממסד הנתונים (link_anchor), לא מקבצי JSON.
      anchorStart = null,
      anchorEnd = null,
      anchorLabel = null,
      linkedAnchorStart = null,
      linkedAnchorEnd = null,
      anchorSpans = const [],
      // קישורי-טווח מגיעים רק ממסד הנתונים (link_range), לא מקבצי JSON.
      heRefEnd = null,
      index2End = null;
}

/// Retrieves a list of [Link] objects for the given list of [indexes] and the [links] to be processed.
///
/// The [indexes] parameter is a required list of integers representing the indexes of the links to retrieve.
/// The [links] parameter is a required [Future] of a list of [Link] objects representing the links to be processed.
/// The [commentatorsToShow] parameter is a required list of [Book] objects representing the commentators to show.
///
/// Returns a [Future] of a list of [Link] objects representing the retrieved links.
///
/// The function retrieves the list of links by first awaiting the completion of the [links] future.
/// It then iterates over each index in the [indexes] list and filters the retrieved links based on the following criteria:
/// - The index of the link should be equal to the current index plus one.
/// - The connection type of the link should be either "commentary" or "targum".
/// - The title of the second book in the link should be present in the list of commentators to show.
/// The filtered links are sorted based on the order of the commentators to show.
/// The sorted list of links is then returned as a [Future] of a list of [Link] objects.
/// [typesToShow] — סינון נוסף לפי סוג המפרש (תרגום/מדרש וכו׳). קבוצה ריקה =
/// הצג את כל הסוגים, כדי שסוג חדש שיתווסף ל-DB יופיע מאליו.
Future<List<Link>> getLinksforIndexs({
  required List<int> indexes,
  required List<Link> links,
  required List<String> commentatorsToShow,
  Set<String> typesToShow = const {},
}) async {
  // אם אין מפרשים להצגה, מחזיר רשימה ריקה מיד
  if (commentatorsToShow.isEmpty) {
    return [];
  }

  // אם אין אינדקסים, מחזיר רשימה ריקה מיד
  if (indexes.isEmpty) {
    return [];
  }

  // יצירת Set לחיפוש מהיר יותר
  final indexSet = indexes.map((i) => i + 1).toSet();
  final commentatorsSet = commentatorsToShow.toSet();

  // סינון אחד במקום לולאה עם סינונים מרובים
  final filteredLinks = links.where((link) {
    // בדיקות מהירות קודם
    if (!indexSet.contains(link.index1)) return false;
    if (!LinkTypes.isDependentTextLink(link.connectionType)) return false;
    if (typesToShow.isNotEmpty &&
        !typesToShow.contains(LinkTypes.canonicalType(link.connectionType))) {
      return false;
    }
    if (link.path2.isEmpty || link.index2 <= 0) return false;

    // בדיקה איטית יותר בסוף
    return commentatorsSet.contains(utils.getTitleFromPath(link.path2));
  }).toList();

  // אם אין קישורים, מחזיר רשימה ריקה מיד
  if (filteredLinks.isEmpty) {
    return [];
  }

  // מיון אחד משולב במקום שני מיונים נפרדים
  filteredLinks.sort((a, b) {
    // קודם לפי סדר המפרשים
    final commentatorComparison = commentatorsToShow
        .indexOf(utils.getTitleFromPath(a.path2))
        .compareTo(commentatorsToShow.indexOf(utils.getTitleFromPath(b.path2)));

    if (commentatorComparison != 0) {
      return commentatorComparison;
    }

    // אם אותו מפרש — לפי סדר השורות בספר המפרש. השוואת מחרוזות על הכתובת
    // אינה סדר הספר: טו/טז מוקדמים לי', ובמדבר מוקדם לויקרא.
    return a.index2.compareTo(b.index2);
  });

  return filteredLinks;
}

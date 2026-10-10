import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/data/repository/data_repository.dart'
    show bookSearchWordMatchesFuzzy;
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/search/utils/find_match_utils.dart';

/// תוצאת פענוח שאילתה עם תחביר צמצום: `מונח@שם`, כאשר השם הוא קטגוריה או ספר.
///
/// ניתן לציין כמה שמות ברצף, כל אחד לאחר `@` משלו:
/// `ערבך ערבא@רמב"ן@רש"י` → מחפש את המילים רק ברש"י וברמב"ן.
/// `שלום@תורה` → מחפש "שלום" בכל הקטגוריות שכותרתן "תורה"; ו-`שלום@בראשית`
/// → מחפש "שלום" בכל ספר או קטגוריה שכותרתם "בראשית" (בכל עומק בעץ).
class ParsedCategoryQuery {
  /// השאילתה ללא חלק הצמצום (מה שלפני ה-@ הראשון).
  final String query;

  /// השמות כפי שהוקלדו (אחרי כל @), או רשימה ריקה אם לא הופיע `@` בשאילתה.
  final List<String> categoryNames;

  /// נתיבי ה-facet של כל הקטגוריות והספרים שכותרתם תואמת לאחד השמות (בכל עומק).
  /// null כאשר אין תחביר `@` בשאילתה.
  final List<String>? facets;

  /// השמות שהוקלדו אך לא נמצאה להם התאמה בספרייה.
  final List<String> notFoundNames;

  const ParsedCategoryQuery({
    required this.query,
    this.categoryNames = const [],
    this.facets,
    this.notFoundNames = const [],
  });

  /// האם הופיע תחביר `@שם` (עם שם אחד לפחות) בשאילתה.
  bool get hasCategoryToken => categoryNames.isNotEmpty;

  /// האם כל השמות שהוקלדו נמצאו (ולפחות אחד הוקלד).
  bool get categoryFound => hasCategoryToken && notFoundNames.isEmpty;
}

/// החלק שלפני ה-`@` הראשון, ללא trim — האופסטים בטקסט הגולמי נשמרים,
/// כך שניתוח מילים חי (spans לפי מיקום הסמן) יכול לרוץ עליו ישירות.
String categoryQueryPart(String rawQuery) {
  final atIndex = rawQuery.indexOf('@');
  return atIndex < 0 ? rawQuery : rawQuery.substring(0, atIndex);
}

/// מפענח שאילתה בתבנית `מונח@שם@שם...` (קטגוריות או ספרים).
///
/// מחזיר את השאילתה הנקייה (ללא חלק הצמצום) ואת נתיבי ה-facet של כל הקטגוריות
/// והספרים שכותרתם תואמת לאחד השמות שאחרי ה-@ — בכל עומק בעץ הספרייה. אם יש
/// כמה התאמות לאותו שם, כולן נכללות. ההתאמה אינה דורשת שם מדויק — ראה
/// [_facetsForName] לשכבות ההתאמה (כינויים, הכלה ושגיאות כתיב).
///
/// - אם אין `@` בשאילתה: [ParsedCategoryQuery.facets] יהיה null והשאילתה
///   תוחזר כמות שהיא.
/// - שם ריק (למשל `שלום@` או `@@`) נבלע בשקט.
/// - הפיצול מתבצע על כל תווי ה-@; החלק שלפני ה-@ הראשון הוא השאילתה.
ParsedCategoryQuery parseCategoryQuery(String rawQuery, Library? library) {
  final atIndex = rawQuery.indexOf('@');
  if (atIndex < 0) {
    return ParsedCategoryQuery(query: rawQuery);
  }

  final queryPart = rawQuery.substring(0, atIndex).trim();
  final names = rawQuery
      .substring(atIndex + 1)
      .split('@')
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty)
      .toList(growable: false);

  // `@` ללא שם — מתעלמים מהתחביר ומחזירים את החלק שלפני ה-@.
  if (names.isEmpty) {
    return ParsedCategoryQuery(query: queryPart);
  }

  final facets = <String>[];
  final notFoundNames = <String>[];
  for (final name in names) {
    final matches = _facetsForName(name, library);
    if (matches.isEmpty) {
      notFoundNames.add(name);
    } else {
      facets.addAll(matches);
    }
  }

  return ParsedCategoryQuery(
    query: queryPart,
    categoryNames: names,
    facets: facets,
    notFoundNames: notFoundNames,
  );
}

/// נתיבי ה-facet של כל הקטגוריות והספרים שכותרתם תואמת ל-[name].
///
/// כותרת ספר מדויקת כוללת גם קטגוריות בשם זהה. אחרת מחפשים מילים שלמות,
/// הכלה חלקית ולבסוף שגיאות כתיב; מוחזרת השכבה הטובה ביותר שאינה ריקה.
List<String> _facetsForName(String name, Library? library) {
  final normalizedName = normalizeFindText(name);
  if (library == null || normalizedName.isEmpty) {
    return const [];
  }

  final nameWords = normalizedName.split(' ');
  final tiers = [<String>[], <String>[], <String>[], <String>[]];

  // אות שימוש אחת לפני השם ("הרמב"ן", "מקמאי") עדיין נחשבת מילה שלמה.
  final asWords = RegExp(
    '(?:^| )[הובכלמ]?${RegExp.escape(normalizedName)}(?: |\$)',
  );
  // הכינויים במסד חלקיים — כינוי זהה לא יכול לגבור על השם שבכותרת.
  int? tierOf(List<String> texts) {
    if (texts.any(asWords.hasMatch)) return 1;
    if (texts.any((text) => text.contains(normalizedName))) return 2;
    final searchText = texts.join(' ');
    if (nameWords.every(
      (word) => bookSearchWordMatchesFuzzy(word, searchText),
    )) {
      return 3;
    }
    return null;
  }

  for (final book in library.getAllBooks()) {
    final id = book.id;
    final acronyms = id == null
        ? const <String>[]
        : AcronymsCache.instance.acronymsFor(book.source, id) ??
              const <String>[];
    final title = normalizeFindText(book.title);
    final tier = title == normalizedName ? 0 : tierOf([title, ...acronyms]);
    if (tier != null) {
      tiers[tier].add(
        FacetHelper.buildBookFacet(
          FacetHelper.resolveCategoryPath(book),
          book,
        ),
      );
    }
  }
  for (final category in library.getAllCategories()) {
    final title = normalizeFindText(category.title);
    final tier = tiers[0].isNotEmpty && title == normalizedName
        ? 0
        : tierOf([title]);
    if (tier != null) tiers[tier].add(category.path);
  }

  for (final tier in tiers) {
    if (tier.isNotEmpty) return tier;
  }
  return const [];
}

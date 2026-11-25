import 'package:otzaria/book_aliases/book_aliases.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/data/repository/data_repository.dart'
    show bookSearchWordMatchesFuzzy;
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/book_facet.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/search/utils/find_match_utils.dart';

/// תוצאת פענוח שאילתה עם תחביר צמצום: `מונח@שם`, כאשר השם הוא קטגוריה או ספר.
///
/// ניתן לציין כמה שמות ברצף, כל אחד לאחר `@` משלו:
/// `ערבך ערבא@רמב"ן@רש"י` → מחפש את המילים רק ברש"י וברמב"ן.
/// `שלום@תורה` → מחפש "שלום" בכל הקטגוריות שכותרתן "תורה"; ו-`שלום@בראשית`
/// → מחפש "שלום" בכל ספר או קטגוריה שכותרתם "בראשית" (בכל עומק בעץ).
/// שם יכול להיות נתיב: `מוקצה@רשבא/ביצה` → רק "ביצה" שמתחת ל"רשב"א" (בכל סדר).
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

  /// מתוך [facets]: ספרים שנמצאו רק לפי המחבר (שכבת ה-fallback האחרונה).
  final Set<String> authorFacets;

  const ParsedCategoryQuery({
    required this.query,
    this.categoryNames = const [],
    this.facets,
    this.notFoundNames = const [],
    this.authorFacets = const {},
  });

  /// [facets] בלי ספרי מחבר ש-[keep] דוחה — למשל ספר אישי בחיפוש חכם בלבד,
  /// שאחרת היה פוסל את כל ההיקף.
  List<String> facetsKeepingAuthors(bool Function(String facet) keep) => [
    for (final facet in facets ?? const <String>[])
      if (!authorFacets.contains(facet) || keep(facet)) facet,
  ];

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
/// [_CategoryQueryResolver._facetsForName] לשכבות ההתאמה (כינויים, הכלה ושגיאות כתיב).
/// רק כשאף שכבת כותרת/נתיב (בשני הסדרים) לא מצאה דבר — ספרים שהמחבר שלהם
/// הוא השם בדיוק ([ParsedCategoryQuery.authorFacets]).
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

  final resolver = _CategoryQueryResolver(library);
  final facets = <String>[];
  final notFoundNames = <String>[];
  for (final name in names) {
    final matches = resolver.facetsForPath(name);
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
    authorFacets: resolver.authorFacets,
  );
}

class _CategoryQueryResolver {
  final Library? library;

  _CategoryQueryResolver(this.library);

  late final books =
      library?.getAllBooks().map(_BookCandidate.new).toList() ??
      <_BookCandidate>[];
  late final categories =
      library?.getAllCategories().map(_CategoryCandidate.new).toList() ??
      <_CategoryCandidate>[];

  /// ספרים שנמצאו לפי המחבר בלבד, ב-[facetsForPath].
  final authorFacets = <String>{};

  /// נתיבי ה-facet עבור [name], שיכול להיות נתיב `שם/שם...`: כל חלק מותאם רק
  /// מתחת להתאמות החלק שלפניו. אם הסדר שהוקלד לא מניב דבר — מנסים בסדר ההפוך.
  /// רק אם גם זה לא מניב דבר, חלק שאין לו התאמת כותרת מותאם לפי המחבר.
  List<String> facetsForPath(String name) {
    final segments = name
        .split('/')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);

    // שכבות הכותרת של כל חלק נשמרות, כדי שמעבר המחבר לא יחשב אותן שוב.
    final byTitle = <String, List<String>>{};
    List<String> resolve(Iterable<String> ordered, {bool byAuthor = false}) {
      List<String>? scopes;
      for (final segment in ordered) {
        final within = scopes;
        scopes = byTitle.putIfAbsent(
          '$segment\u0000${within?.join('\u0000')}',
          () => _facetsForName(segment, within: within),
        );
        if (scopes.isEmpty && byAuthor) {
          scopes = _facetsByAuthor(segment, within: within);
          authorFacets.addAll(scopes);
        }
        if (scopes.isEmpty) break;
      }
      return scopes ?? const [];
    }

    List<String> resolveBothOrders({bool byAuthor = false}) {
      final matches = resolve(segments, byAuthor: byAuthor);
      return matches.isNotEmpty || segments.length < 2
          ? matches
          : resolve(segments.reversed, byAuthor: byAuthor);
    }

    final matches = resolveBothOrders();
    return matches.isNotEmpty ? matches : resolveBothOrders(byAuthor: true);
  }

  /// נתיבי scope מנורמלים להשוואת קידומת, או null בלי צמצום.
  List<String>? _scopePaths(List<String>? within) => within
      ?.map((scope) => BookFacet.resolveFacetCategoryPath(categoryPath: scope))
      .toList(growable: false);

  static bool _inScope(String facet, List<String>? scopes) {
    if (scopes == null) return true;
    // נתיב הקטגוריה שומר פסיקים; ה-facet של הספר מנרמל אותם למפרידים.
    final normalized = BookFacet.resolveFacetCategoryPath(categoryPath: facet);
    return scopes.any((scope) => normalized.startsWith('$scope/'));
  }

  /// ספרים שאחד ממחבריהם הוא [name] בדיוק (מנורמל): `@רבינו בחיי` מוצא את
  /// "כד הקמח". בלי התאמה חלקית — "רבינו בחיי אבן פקודה" הוא מחבר אחר.
  List<String> _facetsByAuthor(String name, {List<String>? within}) {
    final normalizedName = normalizeFindText(name);
    if (normalizedName.isEmpty) return const [];
    final scopes = _scopePaths(within);
    return [
      for (final book in books)
        if (book.authors.contains(normalizedName) &&
            _inScope(book.facet, scopes))
          book.facet,
    ];
  }

  /// ההתאמות הטובות ביותר ל-[name], מוגבלות לצאצאי [within] אם ניתן.
  /// השכבות הן כותרת מדויקת, מילים שלמות, הכלה חלקית ולבסוף שגיאות כתיב.
  List<String> _facetsForName(String name, {List<String>? within}) {
    final normalizedName = normalizeFindText(name);
    if (library == null || normalizedName.isEmpty) {
      return const [];
    }

    final scopes = _scopePaths(within);
    bool inScope(String facet) => _inScope(facet, scopes);

    // כותרת ספר מדויקת מכריעה לפני בדיקת כינויים או התאמות חלקיות.
    final exact = <String>[
      for (final book in books)
        if (book.title == normalizedName && inScope(book.facet)) book.facet,
    ];
    if (exact.isNotEmpty) {
      for (final category in categories) {
        if (category.title == normalizedName &&
            (scopes == null || inScope(category.path))) {
          exact.add(category.facet);
        }
      }
      return exact;
    }

    final tiers = [<String>[], <String>[]];

    // אות שימוש אחת לפני השם ("הרמב"ן", "מקמאי") עדיין נחשבת מילה שלמה.
    final asWords = RegExp(
      '(?:^| )[הובכלמ]?${RegExp.escape(normalizedName)}(?: |\$)',
    );
    int? literalTierOf(String title, [List<String> acronyms = const []]) {
      if (asWords.hasMatch(title) || acronyms.any(asWords.hasMatch)) return 0;
      if (title.contains(normalizedName) ||
          acronyms.any((text) => text.contains(normalizedName))) {
        return 1;
      }
      return null;
    }

    var hasLiteralMatch = false;
    final bookTitles = List<String?>.filled(books.length, null);
    final bookFacets = within == null
        ? null
        : List<String?>.filled(books.length, null);
    final categoryTitles = List<String?>.filled(categories.length, null);
    for (var i = 0; i < books.length; i++) {
      final book = books[i];
      String? facet;
      if (within != null) {
        facet = book.facet;
        if (!inScope(facet)) continue;
      }
      final title = book.title;
      final tier = literalTierOf(title, book.acronyms);
      if (tier != null) {
        hasLiteralMatch = true;
        tiers[tier].add(facet ?? book.facet);
      } else if (!hasLiteralMatch) {
        bookTitles[i] = title;
        bookFacets?[i] = facet;
      }
    }
    for (var i = 0; i < categories.length; i++) {
      final category = categories[i];
      if (within != null && !inScope(category.path)) continue;
      final title = category.title;
      final tier = literalTierOf(title);
      if (tier != null) {
        hasLiteralMatch = true;
        tiers[tier].add(category.facet);
      } else if (!hasLiteralMatch) {
        categoryTitles[i] = title;
      }
    }

    for (final tier in tiers) {
      if (tier.isNotEmpty) return tier;
    }

    // שומרים את הנרמול והתחום מהמעבר הראשון, בלי לחשב אותם שוב ב-fallback.
    final nameWords = normalizedName.split(' ');
    bool matchesFuzzy(String title, [List<String> acronyms = const []]) {
      final searchText = acronyms.isEmpty
          ? title
          : '$title ${acronyms.join(' ')}';
      return nameWords.every(
        (word) => bookSearchWordMatchesFuzzy(
          word,
          searchText,
          matchBookTitleSpellingVariants: false,
        ),
      );
    }

    final fuzzyMatches = <String>[];
    for (var i = 0; i < books.length; i++) {
      final title = bookTitles[i];
      if (title == null) continue;
      final book = books[i];
      final acronyms = book.acronyms;
      if (matchesFuzzy(title, acronyms)) {
        fuzzyMatches.add(bookFacets?[i] ?? book.facet);
      }
    }
    for (var i = 0; i < categories.length; i++) {
      final title = categoryTitles[i];
      if (title != null && matchesFuzzy(title)) {
        fuzzyMatches.add(categories[i].facet);
      }
    }
    return fuzzyMatches;
  }
}

class _BookCandidate {
  final Book book;

  _BookCandidate(this.book);

  late final title = normalizeFindText(book.title);
  // מחברי הקטלוג הראשי מאוחדים ב-GROUP_CONCAT(name, ', ') — ראו
  // BookDao.selectBookAuthorsMap; משווים כל מחבר, וגם את השדה כולו.
  late final authors = {
    for (final author in [book.author ?? '', ...?book.author?.split(', ')])
      normalizeFindText(author),
  }..remove('');
  late final facet = FacetHelper.buildBookFacet(
    FacetHelper.resolveCategoryPath(book),
    book,
  );
  late final acronyms =
      bookAliasesOf(
        book.id == null
            ? null
            : AcronymsCache.instance.acronymsFor(book.source, book.id!),
        title,
      ) ??
      const <String>[];
}

class _CategoryCandidate {
  final Category category;

  _CategoryCandidate(this.category);

  late final title = normalizeFindText(category.title);
  late final path = category.path;
  late final facet = FacetHelper.categoryFacet(category);
}

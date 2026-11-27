import 'package:otzaria/book_aliases/book_aliases.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/data/repository/data_repository.dart'
    show bookSearchWordMatchesFuzzy;
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/book_facet.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/search/utils/find_match_utils.dart';

typedef _ScopeMatches = ({List<String> titles, List<String> authors});

/// תוצאת פענוח שאילתה עם תחביר צמצום: `מונח@שם` לקטגוריה, ספר או מחבר.
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

  /// נתיבי ה-facet של הקטגוריות והספרים שהותאמו לאחד השמות (בכל עומק).
  /// null כאשר אין תחביר `@` בשאילתה.
  final List<String>? facets;

  /// השמות שהוקלדו אך לא נמצאה להם התאמה בספרייה.
  final List<String> notFoundNames;
  final List<_ScopeMatches> _matchesByName;

  const ParsedCategoryQuery({
    required this.query,
    this.categoryNames = const [],
    this.facets,
    this.notFoundNames = const [],
  }) : _matchesByName = const [];

  const ParsedCategoryQuery._({
    required this.query,
    required this.categoryNames,
    required this.facets,
    required this.notFoundNames,
    required this._matchesByName,
  });

  /// משמיט התאמות מחבר שאינן נתמכות. אם רכיב `@` שלם נשמט,
  /// מחזיר את הבחירה המקורית כדי שבדיקת הכיסוי תדחה את החיפוש.
  List<String> facetsWithSupportedAuthors(bool Function(String) isSupported) {
    final original = facets ?? const <String>[];
    if (_matchesByName.every((match) => match.authors.isEmpty)) return original;
    final filtered = <String>[];
    for (final match in _matchesByName) {
      final previousLength = filtered.length;
      filtered
        ..addAll(match.titles)
        ..addAll(match.authors.where(isSupported));
      if (filtered.length == previousLength) return original;
    }
    return filtered;
  }

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
/// שם ללא נתיב כולל גם מחבר מדויק או תחילית חד-משמעית בגבולות מילים, אלא
/// אם נמצאה כותרת ספר או קטגוריה מדויקת.
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
  final matchesByName = <_ScopeMatches>[];
  for (final name in names) {
    final matches = resolver.facetsForPath(name);
    if (matches.titles.isEmpty && matches.authors.isEmpty) {
      notFoundNames.add(name);
    } else {
      matchesByName.add(matches);
      facets
        ..addAll(matches.titles)
        ..addAll(matches.authors);
    }
  }

  return ParsedCategoryQuery._(
    query: queryPart,
    categoryNames: names,
    facets: facets,
    notFoundNames: notFoundNames,
    matchesByName: matchesByName,
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
  final _normalizedAuthors = <String, String>{};

  /// נתיבי ה-facet עבור [name], שיכול להיות נתיב `שם/שם...`: כל חלק מותאם רק
  /// מתחת להתאמות החלק שלפניו. אם הסדר שהוקלד לא מניב דבר — מנסים בסדר ההפוך.
  _ScopeMatches facetsForPath(String name) {
    final segments = name
        .split('/')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);

    if (segments.length == 1 && !name.contains('/')) {
      return _facetsForName(segments.single, matchAuthor: true);
    }

    List<String> resolve(Iterable<String> ordered) {
      List<String>? scopes;
      for (final segment in ordered) {
        scopes = _facetsForName(segment, within: scopes).titles;
        if (scopes.isEmpty) break;
      }
      return scopes ?? const [];
    }

    final matches = resolve(segments);
    final titles = matches.isNotEmpty || segments.length < 2
        ? matches
        : resolve(segments.reversed);
    return (titles: titles, authors: const []);
  }

  /// ההתאמות הטובות ביותר ל-[name], מוגבלות לצאצאי [within] אם ניתן.
  /// השכבות הן כותרת מדויקת, מילים שלמות, הכלה חלקית ולבסוף שגיאות כתיב.
  _ScopeMatches _facetsForName(
    String name, {
    List<String>? within,
    bool matchAuthor = false,
  }) {
    final normalizedName = normalizeFindText(name);
    if (library == null || normalizedName.isEmpty) {
      return (titles: const [], authors: const []);
    }

    final scopes = within
        ?.map(
          (scope) => BookFacet.resolveFacetCategoryPath(categoryPath: scope),
        )
        .toList(growable: false);
    bool inScope(String facet) {
      if (scopes == null) return true;
      // נתיב הקטגוריה שומר פסיקים; ה-facet של הספר מנרמל אותם למפרידים.
      final normalized = BookFacet.resolveFacetCategoryPath(
        categoryPath: facet,
      );
      return scopes.any((scope) => normalized.startsWith('$scope/'));
    }

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
      return (titles: exact, authors: const []);
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
    final authorFacets = <String, Set<String>>{};
    final authorPrefix = '$normalizedName ';
    final allowAuthorPrefix = normalizedName.contains(' ');
    final includeAuthors =
        matchAuthor &&
        !categories.any((category) => category.title == normalizedName);
    for (var i = 0; i < books.length; i++) {
      final book = books[i];
      String? facet;
      if (within != null) {
        facet = book.facet;
        if (!inScope(facet)) continue;
      }
      if (includeAuthors) {
        for (final rawAuthor in book.book.authors) {
          final author = _normalizedAuthors.putIfAbsent(
            rawAuthor,
            () => normalizeFindText(rawAuthor),
          );
          if (author == normalizedName ||
              (allowAuthorPrefix && author.startsWith(authorPrefix))) {
            (authorFacets[author] ??= {}).add(facet ?? book.facet);
          }
        }
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

    final exactAuthor = authorFacets[normalizedName];
    final matchedAuthor =
        exactAuthor ??
        (authorFacets.length == 1 ? authorFacets.values.single : null);
    _ScopeMatches withAuthor(List<String> titles) => (
      titles: titles,
      authors: matchedAuthor == null
          ? const []
          : matchedAuthor.difference(titles.toSet()).toList(),
    );

    for (final tier in tiers) {
      if (tier.isNotEmpty) return withAuthor(tier);
    }
    if (exactAuthor != null) return withAuthor(const []);

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
    return withAuthor(fuzzyMatches);
  }
}

class _BookCandidate {
  final Book book;

  _BookCandidate(this.book);

  late final title = normalizeFindText(book.title);
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

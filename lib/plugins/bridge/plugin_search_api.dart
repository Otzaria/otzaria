import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/models/plugin_book_identity.dart';
import 'package:otzaria/search/book_facet.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart' as engine;

/// תרגום פרמטרי `search.query` של ה-Plugin SDK לחוזה [SearchRepository],
/// וסידור התוצאות חזרה ל-JSON. הפרמטרים הם אותם פרמטרים שמסך החיפוש של
/// האפליקציה שולח למנוע — התוסף מקבל את התוצאות לעצמו במקום לפתוח טאב.
class PluginSearchApi {
  PluginSearchApi._();

  /// תקרת התוצאות לקריאה אחת. דפדוף מעבר לכך דרך `offset`.
  static const int maxLimit = 500;

  /// חלון התוצאות המרבי שהמנוע רשאי להחזיק בזיכרון עבור דפדוף.
  static const int maxResultWindow = 10000;

  /// המרחק המרבי שנתמך בפועל בחיפוש מקורב.
  static const int fuzzyMaxDistance = 2;

  static const int defaultLimit = 50;

  static const Map<String, SearchMode> searchModes = {
    'exact': SearchMode.exact,
    'advanced': SearchMode.advanced,
    'fuzzy': SearchMode.fuzzy,
  };

  static const Map<String, engine.ResultsOrder> resultOrders = {
    'relevance': engine.ResultsOrder.relevance,
    'catalogue': engine.ResultsOrder.catalogue,
    'generation': engine.ResultsOrder.generation,
  };

  static const Map<String, engine.SearchScope> proximityScopes = {
    'wordDistance': engine.SearchScope.wordDistance,
    'sameParagraph': engine.SearchScope.sameParagraph,
    'sameSection': engine.SearchScope.sameSection,
  };

  static const Map<String, ResultGroupingMode> groupingModes = {
    'none': ResultGroupingMode.none,
    'sameSection': ResultGroupingMode.sameSection,
    'identicalText': ResultGroupingMode.identicalText,
  };

  static const Map<String, engine.WordMatchMode> wordMatchModes = {
    'all': engine.WordMatchMode.all,
    'anyWord': engine.WordMatchMode.anyWord,
    'mostWords': engine.WordMatchMode.mostWords,
    'atLeast': engine.WordMatchMode.atLeast,
  };

  /// כל מפתחות אפשרויות-המילה החוקיים. מסננים אותם לפי המצב בזמן הבנייה
  /// ([SearchQueryBuilder.normalizeParametersForMode]), אבל מפתח שאינו
  /// ברשימה כלל הוא שגיאת קלט — אחרת התוסף מקבל תוצאות בלי האפשרות שביקש.
  static List<String> get wordOptionKeys => [
    ...SearchQueryBuilder.availableWordOptionKeys,
    ...SearchQueryBuilder.advancedOnlyWordOptionKeys,
    ...SearchQueryBuilder.vocalizedWordOptionKeys,
  ];

  /// שמות התקופות לסינון לפי `eras`. זהה לרשימה שתפריט היקף החיפוש מציג.
  static List<String> get eraNames => [
    for (final era in CommentaryEra.values)
      if (era != CommentaryEra.other && era != CommentaryEra.torahShebichtav)
        era.hebrewName,
  ];

  /// אוצר המילים של `search.query` — כל הערכים החוקיים לכל פרמטר, כדי
  /// שתוסף יוכל לבנות מסך חיפוש משלו בלי לקבע רשימות.
  static Map<String, dynamic> describeOptions() => {
    'modes': searchModes.keys.toList(),
    'orders': resultOrders.keys.toList(),
    'proximityScopes': proximityScopes.keys.toList(),
    'grouping': groupingModes.keys.toList(),
    'wordMatchModes': wordMatchModes.keys.toList(),
    'wordOptions': {
      'exact': SearchQueryBuilder.exactWordOptionKeys,
      'advanced': [
        ...SearchQueryBuilder.availableWordOptionKeys,
        ...SearchQueryBuilder.advancedOnlyWordOptionKeys,
      ],
      'vocalized': SearchQueryBuilder.vocalizedWordOptionKeys,
    },
    'eras': eraNames,
    'maxLimit': maxLimit,
    'maxResultWindow': maxResultWindow,
    'fuzzyMaxDistance': fuzzyMaxDistance,
    'defaultLimit': defaultLimit,
  };

  static Never _invalid(String detail) =>
      throw Exception('error.invalid_params: $detail');

  static T _enumArg<T>(Map<String, T> values, Object? raw, T fallback) {
    if (raw == null) return fallback;
    final value = values[raw.toString()];
    if (value == null) {
      _invalid(
        'unknown value "$raw" (expected one of ${values.keys.join(', ')})',
      );
    }
    return value;
  }

  /// הגבול של המנוע — הפרמטרים המספריים עוברים אליו כ-u32.
  static const int _uint32Max = 4294967295;

  static int _intArg(
    Object? raw,
    String name, {
    required int fallback,
    int min = 0,
    int max = _uint32Max,
  }) {
    if (raw == null) return fallback;
    final number = raw is num ? raw : num.tryParse(raw.toString());
    if (number == null || !number.isFinite) {
      _invalid('$name must be a finite number');
    }
    if (number != number.truncate()) {
      _invalid('$name must be a whole number (got $raw)');
    }
    final value = number.toInt();
    if (value < min || value > max) {
      _invalid('$name must be between $min and $max (got $value)');
    }
    return value;
  }

  static Map<String, bool> _boolMap(Object? raw, String name) {
    if (raw == null) return const {};
    if (raw is! Map) _invalid('$name must be an object');
    final result = <String, bool>{};
    raw.forEach((key, value) {
      if (value is! bool) _invalid('$name["$key"] must be a boolean');
      final option = key.toString();
      if (!wordOptionKeys.contains(option)) {
        _invalid('unknown search option "$option"');
      }
      result[option] = value;
    });
    return result;
  }

  static Map<String, Map<String, bool>> _perWordOptions(
    Object? raw,
    String name,
  ) {
    if (raw == null) return const {};
    if (raw is! Map) _invalid('$name must be an object');
    return {
      for (final entry in raw.entries)
        entry.key.toString(): _boolMap(entry.value, '$name["${entry.key}"]'),
    };
  }

  static Map<int, List<String>> _alternativeWords(Object? raw, String name) {
    if (raw == null) return const {};
    if (raw is! Map) _invalid('$name must be an object keyed by word index');
    final result = <int, List<String>>{};
    raw.forEach((key, value) {
      final index = switch (key) {
        int value => value,
        num value when value.isFinite && value == value.truncate() =>
          value.toInt(),
        String value => int.tryParse(value),
        _ => null,
      };
      if (index == null || index < 0) {
        _invalid('$name has a non-numeric word index "$key"');
      }
      if (value is! List) _invalid('$name["$key"] must be an array of strings');
      if (value.any((word) => word is! String)) {
        _invalid('$name["$key"] must be an array of strings');
      }
      result[index] = value.cast<String>();
    });
    return result;
  }

  static Map<String, String> _customSpacing(Object? raw, String name) {
    if (raw == null) return const {};
    if (raw is! Map) _invalid('$name must be an object keyed like "0-1"');
    final result = <String, String>{};
    raw.forEach((key, value) {
      final pair = key.toString().split('-');
      final from = pair.length == 2 ? int.tryParse(pair[0]) : null;
      final to = pair.length == 2 ? int.tryParse(pair[1]) : null;
      // רק זוג מילים *סמוכות*: המנוע קורא את המרווח לכל זוג עוקב, וזוג
      // שאינו סמוך היה מוחל בשקט על מרווחים אחרים ומשנה את התוצאות.
      if (from == null || to == null || from < 0 || to != from + 1) {
        _invalid(
          '$name key "$key" must be a pair of adjacent word indices, like "0-1"',
        );
      }
      final spacing = int.tryParse(value.toString());
      if (spacing == null || spacing < 0 || spacing > _uint32Max) {
        _invalid('$name["$key"] must be a non-negative whole number');
      }
      result[key.toString()] = spacing.toString();
    });
    return result;
  }

  static List<String> _stringList(Object? raw, String name) {
    if (raw == null) return const [];
    if (raw is! List) _invalid('$name must be an array');
    if (raw.any((item) => item is! String)) {
      _invalid('$name must be an array of strings');
    }
    return raw.cast<String>();
  }

  static void _validateBookIdentity(Map<String, dynamic> identity) {
    final rawId = identity['id'];
    if (rawId != null && PluginBookIdentity.parseId(rawId) == null) {
      _invalid('book id must be a whole number');
    }
    for (final key in ['bookId', 'title', 'type', 'source']) {
      if (identity[key] != null && identity[key] is! String) {
        _invalid('book $key must be a string');
      }
    }
    if (rawId == null &&
        identity['bookId'] == null &&
        identity['title'] == null) {
      _invalid('book identity requires id or bookId');
    }
  }

  /// בונה את רשימת ה-facets שנשלחת למנוע מתוך תיאור ההיקף של התוסף.
  /// היקף ריק = כל הספרייה (`/`).
  ///
  /// [findBook] מאתר ספר לפי זהות ה-SDK; מחזיר null כשהזהות אינה חד-משמעית.
  static List<String> resolveFacets(
    Map<String, dynamic> args, {
    required Book? Function(Map<String, dynamic> identity) findBook,
  }) {
    final facets = <String>[];

    for (final facet in _stringList(args['facets'], 'facets')) {
      if (!facet.startsWith('/')) {
        _invalid('facet "$facet" must start with "/"');
      }
      facets.add(facet);
    }

    for (final category in _stringList(args['categories'], 'categories')) {
      final path = BookFacet.resolveFacetCategoryPath(categoryPath: category);
      if (path.isEmpty) _invalid('category "$category" is empty');
      facets.add(path);
    }

    final books = args['books'];
    if (books != null) {
      if (books is! List) _invalid('books must be an array');
      for (final entry in books) {
        if (entry is! Map) _invalid('books entries must be objects');
        final identity = Map<String, dynamic>.from(entry);
        _validateBookIdentity(identity);
        final book = findBook(identity);
        if (book == null) {
          throw Exception(
            'error.not_found: book not found for ${identity['bookId'] ?? identity['id']}',
          );
        }
        facets.add(
          FacetHelper.buildBookFacet(
            FacetHelper.resolveCategoryPath(book),
            book,
          ),
        );
      }
    }

    for (final author in _stringList(args['authors'], 'authors')) {
      if (author.trim().isEmpty) _invalid('author name is empty');
      facets.add(FacetHelper.buildAuthorFacet(author));
    }

    for (final era in _stringList(args['eras'], 'eras')) {
      if (!eraNames.contains(era)) {
        _invalid('unknown era "$era" (expected one of ${eraNames.join(', ')})');
      }
      facets.add(FacetHelper.buildEraFacet(era));
    }

    if (args['baseBooksOnly'] == true) {
      facets.add(FacetHelper.baseDimensionFacet);
    }

    // כשההיקף כולו ממדי (רק מחבר/תקופה/ספרי יסוד) נדרש גם שורש הקטגוריות,
    // אחרת המנוע מקבל קבוצת קטגוריות ריקה ולא מחזיר דבר.
    if (facets.every(FacetHelper.isDimensionFacet)) {
      facets.add('/');
    }
    return facets;
  }

  /// ממיר תוצאת מנוע ל-JSON של ה-SDK. [book] הוא הספר שזוהה לפי
  /// `filePath` של האינדקס — הוא שמאפשר להחזיר `id`/`source`, מה ש-
  /// `search.fullText` הישן לא ידע לעשות.
  static Map<String, dynamic> resultToJson(
    engine.SearchResult result,
    Book? book, {
    Map<String, Book> booksByPath = const {},
  }) {
    // אינדקס שאינו מסונכרן ממפה את מפתח המסמך לספר אחר; עדיף להחזיר לתוסף
    // זהות ריקה מאשר לייחס לתוצאה את ה-id של ספר זר.
    final resolved = IndexingRepository.validatedIndexedBook(
      book,
      indexedTitle: result.title,
    );
    return {
      if (resolved != null)
        ...PluginBookIdentity.toJsonWithUid(resolved)
      else ...{
        'id': null,
        'type': result.isPdf ? 'pdf' : 'text',
        'bookId': result.title,
        'source': null,
      },
      'book': result.title,
      if (resolved != null)
        'categoryPath': FacetHelper.resolveCategoryPath(resolved),
      'reference': result.reference,
      'text': result.text,
      'index': result.segment.toInt(),
      'mergedCount': result.mergedCount,
      if (result.merged.isNotEmpty)
        'merged': [
          for (final sibling in result.merged)
            _siblingToJson(sibling, booksByPath),
        ],
    };
  }

  static Map<String, dynamic> _siblingToJson(
    engine.MergedSibling sibling,
    Map<String, Book> booksByPath,
  ) {
    final book = IndexingRepository.bookForIndexedDocument(
      booksByPath,
      indexedFilePath: sibling.filePath,
      indexedTitle: sibling.title,
    );
    return {
      if (book != null)
        ...PluginBookIdentity.toJsonWithUid(book)
      else ...{
        'id': null,
        'type': sibling.isPdf ? 'pdf' : 'text',
        'bookId': sibling.title,
        'source': null,
      },
      'book': sibling.title,
      if (book != null) 'categoryPath': FacetHelper.resolveCategoryPath(book),
      'reference': sibling.reference,
      'index': sibling.segment.toInt(),
    };
  }

  /// מפתח כל ספר בספרייה לפי הנתיב שבו הוא מאונדקס — כך תוצאה מהמנוע
  /// מתורגמת חזרה לזהות ספר של ה-SDK.
  static Map<String, Book> booksByIndexedFilePath(Library library) {
    final map = <String, Book>{};
    for (final book in library.getAllBooks()) {
      map.putIfAbsent(
        IndexingRepository.buildIndexedBookFilePath(book),
        () => book,
      );
    }
    return map;
  }
}

/// בקשת חיפוש מתוסף, אחרי אימות והמרה לטיפוסי המנוע.
class PluginSearchRequest {
  final String query;
  final String negativeQuery;
  final int limit;
  final int offset;
  final SearchMode searchMode;
  final engine.ResultsOrder order;
  final int distance;
  final int negativeDistance;
  final engine.SearchScope proximityScope;
  final engine.SearchScope negativeProximityScope;
  final engine.ResultGrouping? grouping;
  final engine.WordMatchMode wordMatchMode;
  final int wordMatchCount;
  final bool includeBookCounts;

  /// אפשרויות גלובליות — מורחבות לכל מילה בשאילתה בזמן ההרצה.
  final Map<String, bool> globalOptions;
  final Map<String, bool> negativeGlobalOptions;

  /// אפשרויות פר-מילה במפתחות `"{מילה}_{אינדקס}"`. גוברות על הגלובליות.
  final Map<String, Map<String, bool>> wordOptions;
  final Map<String, Map<String, bool>> negativeWordOptions;

  final Map<int, List<String>> alternativeWords;
  final Map<int, List<String>> negativeAlternativeWords;
  final Map<String, String> customSpacing;
  final Map<String, String> negativeCustomSpacing;

  const PluginSearchRequest({
    required this.query,
    required this.negativeQuery,
    required this.limit,
    required this.offset,
    required this.searchMode,
    required this.order,
    required this.distance,
    required this.negativeDistance,
    required this.proximityScope,
    required this.negativeProximityScope,
    required this.grouping,
    required this.wordMatchMode,
    required this.wordMatchCount,
    required this.includeBookCounts,
    required this.globalOptions,
    required this.negativeGlobalOptions,
    required this.wordOptions,
    required this.negativeWordOptions,
    required this.alternativeWords,
    required this.negativeAlternativeWords,
    required this.customSpacing,
    required this.negativeCustomSpacing,
  });

  /// פרמטרים שרק המצב המתקדם מריץ. בלי הדחייה הזו הם היו נבלעים בשקט
  /// (שאילתה שלילית שאינה מסננת, מרווח שאינו נאכף) והתוסף היה מקבל
  /// תוצאות שגויות בלי שום סימן.
  static const List<String> _advancedOnlyKeys = [
    'negativeQuery',
    'negativeDistance',
    'negativeProximityScope',
    'negativeOptions',
    'negativeWordOptions',
    'negativeAlternativeWords',
    'negativeCustomSpacing',
    'alternativeWords',
    'customSpacing',
  ];

  static const Set<String> _allowedKeys = {
    'query',
    'negativeQuery',
    'mode',
    'order',
    'limit',
    'offset',
    'distance',
    'negativeDistance',
    'proximityScope',
    'negativeProximityScope',
    'grouping',
    'wordMatchMode',
    'wordMatchCount',
    'includeBookCounts',
    'options',
    'negativeOptions',
    'wordOptions',
    'negativeWordOptions',
    'alternativeWords',
    'negativeAlternativeWords',
    'customSpacing',
    'negativeCustomSpacing',
    'facets',
    'categories',
    'books',
    'authors',
    'eras',
    'baseBooksOnly',
  };

  static bool _isPresent(Object? value) => switch (value) {
    null => false,
    String value => value.trim().isNotEmpty,
    Map value => value.isNotEmpty,
    List value => value.isNotEmpty,
    _ => true,
  };

  static void _rejectParametersUnsupportedByMode(
    Map<String, dynamic> args,
    SearchMode mode,
  ) {
    if (mode != SearchMode.advanced) {
      for (final key in _advancedOnlyKeys) {
        if (_isPresent(args[key])) {
          PluginSearchApi._invalid('$key requires mode: "advanced"');
        }
      }
      if (args['proximityScope'] != null &&
          args['proximityScope'] != 'wordDistance') {
        PluginSearchApi._invalid('proximityScope requires mode: "advanced"');
      }
      if (args['wordMatchMode'] != null && args['wordMatchMode'] != 'all') {
        PluginSearchApi._invalid('wordMatchMode requires mode: "advanced"');
      }
    }

    final optionKeys = <String>{
      if (args['options'] case final Map options)
        for (final key in options.keys) key.toString(),
      if (args['wordOptions'] case final Map perWord)
        for (final options in perWord.values)
          if (options is Map)
            for (final key in options.keys) key.toString(),
    };
    if (optionKeys.isEmpty) return;

    // מפתח שאינו קיים כלל קודם למגבלת המצב — אחרת שגיאת הכתיב מדווחת
    // כאילו היא אפשרות מתקדמת.
    for (final key in optionKeys) {
      if (!PluginSearchApi.wordOptionKeys.contains(key)) {
        PluginSearchApi._invalid('unknown search option "$key"');
      }
    }

    if (mode == SearchMode.fuzzy) {
      PluginSearchApi._invalid(
        'search options are not supported in mode: "fuzzy"',
      );
    }
    if (mode == SearchMode.exact) {
      for (final key in optionKeys) {
        if (!SearchQueryBuilder.exactWordOptionKeys.contains(key)) {
          PluginSearchApi._invalid(
            'search option "$key" requires mode: "advanced"',
          );
        }
      }
    }
  }

  factory PluginSearchRequest.fromArgs(Map<String, dynamic> args) {
    final unknownKeys = args.keys.where((key) => !_allowedKeys.contains(key));
    if (unknownKeys.isNotEmpty) {
      PluginSearchApi._invalid('unknown parameter "${unknownKeys.first}"');
    }
    if (args['query'] is! String) {
      PluginSearchApi._invalid('query must be a string');
    }
    if (args['negativeQuery'] != null && args['negativeQuery'] is! String) {
      PluginSearchApi._invalid('negativeQuery must be a string');
    }
    for (final key in ['includeBookCounts', 'baseBooksOnly']) {
      if (args[key] != null && args[key] is! bool) {
        PluginSearchApi._invalid('$key must be a boolean');
      }
    }

    final query = (args['query'] as String).trim();
    if (query.isEmpty) {
      throw Exception('error.invalid_params: query required');
    }

    final searchMode = PluginSearchApi._enumArg(
      PluginSearchApi.searchModes,
      args['mode'],
      SearchMode.exact,
    );
    _rejectParametersUnsupportedByMode(args, searchMode);

    final rawLimit = PluginSearchApi._intArg(
      args['limit'],
      'limit',
      fallback: PluginSearchApi.defaultLimit,
      min: 1,
    );
    final limit = rawLimit > PluginSearchApi.maxLimit
        ? PluginSearchApi.maxLimit
        : rawLimit;
    final offset = PluginSearchApi._intArg(
      args['offset'],
      'offset',
      fallback: 0,
    );
    if (offset > PluginSearchApi.maxResultWindow - limit) {
      PluginSearchApi._invalid(
        'offset + limit must not exceed ${PluginSearchApi.maxResultWindow}',
      );
    }

    final distance = PluginSearchApi._intArg(
      args['distance'],
      'distance',
      fallback: 0,
      max: searchMode == SearchMode.fuzzy
          ? PluginSearchApi.fuzzyMaxDistance
          : PluginSearchApi._uint32Max,
    );
    final proximityScope = PluginSearchApi._enumArg(
      PluginSearchApi.proximityScopes,
      args['proximityScope'],
      engine.SearchScope.wordDistance,
    );
    final wordMatchMode = PluginSearchApi._enumArg(
      PluginSearchApi.wordMatchModes,
      args['wordMatchMode'],
      engine.WordMatchMode.all,
    );
    if (args['wordMatchCount'] != null &&
        (searchMode != SearchMode.advanced ||
            wordMatchMode != engine.WordMatchMode.atLeast)) {
      PluginSearchApi._invalid(
        'wordMatchCount requires mode: "advanced" and wordMatchMode: "atLeast"',
      );
    }
    final wordMatchCount = PluginSearchApi._intArg(
      args['wordMatchCount'],
      'wordMatchCount',
      fallback: 2,
      min: 1,
    );

    return PluginSearchRequest(
      query: query,
      negativeQuery: args['negativeQuery'] as String? ?? '',
      limit: limit,
      offset: offset,
      searchMode: searchMode,
      order: PluginSearchApi._enumArg(
        PluginSearchApi.resultOrders,
        args['order'],
        engine.ResultsOrder.relevance,
      ),
      distance: distance,
      negativeDistance: PluginSearchApi._intArg(
        args['negativeDistance'],
        'negativeDistance',
        fallback: distance,
      ),
      proximityScope: proximityScope,
      negativeProximityScope: PluginSearchApi._enumArg(
        PluginSearchApi.proximityScopes,
        args['negativeProximityScope'],
        proximityScope,
      ),
      grouping: PluginSearchApi._enumArg(
        PluginSearchApi.groupingModes,
        args['grouping'],
        ResultGroupingMode.none,
      ).engineGrouping,
      wordMatchMode: wordMatchMode,
      wordMatchCount: wordMatchCount,
      includeBookCounts: args['includeBookCounts'] == true,
      globalOptions: PluginSearchApi._boolMap(args['options'], 'options'),
      negativeGlobalOptions: PluginSearchApi._boolMap(
        args['negativeOptions'],
        'negativeOptions',
      ),
      wordOptions: PluginSearchApi._perWordOptions(
        args['wordOptions'],
        'wordOptions',
      ),
      negativeWordOptions: PluginSearchApi._perWordOptions(
        args['negativeWordOptions'],
        'negativeWordOptions',
      ),
      alternativeWords: PluginSearchApi._alternativeWords(
        args['alternativeWords'],
        'alternativeWords',
      ),
      negativeAlternativeWords: PluginSearchApi._alternativeWords(
        args['negativeAlternativeWords'],
        'negativeAlternativeWords',
      ),
      customSpacing: PluginSearchApi._customSpacing(
        args['customSpacing'],
        'customSpacing',
      ),
      negativeCustomSpacing: PluginSearchApi._customSpacing(
        args['negativeCustomSpacing'],
        'negativeCustomSpacing',
      ),
    );
  }

  /// הפרמטרים אחרי צמצום למה שהמצב הנבחר תומך בו — אותו נרמול שמסך
  /// החיפוש מריץ, כך שתוסף לא יקבל התנהגות אחרת מהאפליקציה.
  SearchModeScopedParameters get _parameters =>
      SearchQueryBuilder.normalizeParametersForMode(
        searchMode,
        customSpacing: customSpacing,
        alternativeWords: alternativeWords,
        searchOptions: _mergedOptions(globalOptions, wordOptions, query),
      );

  SearchModeScopedParameters get _negativeParameters =>
      SearchQueryBuilder.normalizeParametersForMode(
        searchMode,
        customSpacing: negativeCustomSpacing,
        alternativeWords: negativeAlternativeWords,
        searchOptions: _mergedOptions(
          negativeGlobalOptions,
          negativeWordOptions,
          negativeQuery,
        ),
      );

  static Map<String, Map<String, bool>> _mergedOptions(
    Map<String, bool> global,
    Map<String, Map<String, bool>> perWord,
    String query,
  ) {
    if (query.isEmpty) return const {};
    final merged = global.isEmpty
        ? <String, Map<String, bool>>{}
        : SearchQueryBuilder.expandGlobalOptionsToWords(query, global);
    for (final entry in perWord.entries) {
      merged[entry.key] = entry.value;
    }
    return merged;
  }

  /// מוודא שהמפות הפר-מיליות מתאימות לפיצול המילים של השאילתה: מפתח
  /// `"מילה_אינדקס"` שאינו תואם, או אינדקס מחוץ לטווח, נבלע במנוע בשקט
  /// והתוסף היה מקבל תוצאות בלי האפשרויות שביקש.
  void validateAgainstQuery() {
    _validateSide(query, wordOptions, alternativeWords, customSpacing, '');
    _validateSide(
      negativeQuery,
      negativeWordOptions,
      negativeAlternativeWords,
      negativeCustomSpacing,
      'negative',
    );
  }

  static void _validateSide(
    String query,
    Map<String, Map<String, bool>> wordOptions,
    Map<int, List<String>> alternativeWords,
    Map<String, String> customSpacing,
    String prefix,
  ) {
    if (wordOptions.isEmpty &&
        alternativeWords.isEmpty &&
        customSpacing.isEmpty) {
      return;
    }
    final matches = SearchQueryBuilder.restoredPerWordStateMatches(
      query,
      searchOptions: wordOptions,
      alternativeWords: alternativeWords,
      spacingValues: customSpacing,
    );
    if (!matches) {
      PluginSearchApi._invalid(
        '${prefix.isEmpty ? '' : '$prefix '}per-word parameters do not match '
        'the query words: keys must be "{word}_{index}" and indices must be '
        'within the query (${SearchQueryBuilder.splitQueryWords(query).join(', ')})',
      );
    }
  }

  String get sanitizedQuery => SearchQueryBuilder.sanitizeQuery(query);

  String get sanitizedNegativeQuery =>
      SearchQueryBuilder.sanitizeQuery(negativeQuery);

  Map<String, String> get effectiveCustomSpacing => _parameters.customSpacing;
  Map<int, List<String>> get effectiveAlternativeWords =>
      _parameters.alternativeWords;
  Map<String, Map<String, bool>> get effectiveSearchOptions =>
      _parameters.searchOptions;

  Map<String, String> get effectiveNegativeCustomSpacing =>
      _negativeParameters.customSpacing;
  Map<int, List<String>> get effectiveNegativeAlternativeWords =>
      _negativeParameters.alternativeWords;
  Map<String, Map<String, bool>> get effectiveNegativeSearchOptions =>
      _negativeParameters.searchOptions;
}

/// הגדרות פתיחת טאב חיפוש מתוסף (`reader.openSearchTab` → `settings`).
///
/// תת-קבוצה של פרמטרי `search.query` — מצב, מרווח, מדיניות התאמה ואפשרויות
/// מילה (קידומות, סיומות וכד'). ה-parser משתמש באותו מסלול אימות של
/// `PluginSearchRequest` כדי שהתוסף לא יקבל התנהגות שונה ממסך החיפוש: מפתח
/// לא מוכר, אפשרות שאין למצב הנבחר, או מפתח פר-מילה שאינו תואם לשאילתה —
/// נדחים ב-`error.invalid_params` ולא נבלעים בשקט.
class PluginOpenSearchTabSettings {
  final SearchMode searchMode;
  final int distance;
  final engine.SearchScope proximityScope;
  final engine.WordMatchMode wordMatchMode;
  final int wordMatchCount;

  /// אפשרויות פר-מילה אפקטיביות (גלובליות מורחבות לכל מילה + פר-מילה),
  /// מנורמלות למצב — בדיוק מה שמסך החיפוש שולח למנוע.
  final Map<String, Map<String, bool>> searchOptions;

  const PluginOpenSearchTabSettings({
    required this.searchMode,
    required this.distance,
    required this.proximityScope,
    required this.wordMatchMode,
    required this.wordMatchCount,
    required this.searchOptions,
  });

  /// מפתחות ה-`settings` הנתמכים על ידי `reader.openSearchTab`.
  static const Set<String> _allowedKeys = {
    'mode',
    'distance',
    'proximityScope',
    'wordMatchMode',
    'wordMatchCount',
    'options',
    'wordOptions',
  };

  /// ברירות המחדל של הטאב — זהות ל-`SearchConfiguration()`.
  static const PluginOpenSearchTabSettings _defaults =
      PluginOpenSearchTabSettings(
        searchMode: SearchMode.advanced,
        distance: 0,
        proximityScope: engine.SearchScope.wordDistance,
        wordMatchMode: engine.WordMatchMode.all,
        wordMatchCount: 2,
        searchOptions: {},
      );

  static PluginOpenSearchTabSettings parse(
    Object? raw, {
    required String query,
  }) {
    if (raw == null) return _defaults;
    if (raw is! Map) {
      PluginSearchApi._invalid('settings must be an object');
    }
    final args = Map<String, dynamic>.from(raw);
    final unknownKeys = args.keys
        .where((key) => !_allowedKeys.contains(key))
        .toList();
    if (unknownKeys.isNotEmpty) {
      PluginSearchApi._invalid(
        'unknown settings parameter "${unknownKeys.first}"',
      );
    }

    // בונים מפה מינימלית עבור PluginSearchRequest — כך כל האימות של
    // search.query (מגבלות מצב, מפתחות אפשרויות, מבני ערכים) חל כאן גם.
    final miniArgs = <String, dynamic>{
      'query': query,
      'mode': args['mode'] ?? 'advanced',
      if (args['distance'] != null) 'distance': args['distance'],
      if (args['proximityScope'] != null)
        'proximityScope': args['proximityScope'],
      if (args['wordMatchMode'] != null) 'wordMatchMode': args['wordMatchMode'],
      if (args['wordMatchCount'] != null)
        'wordMatchCount': args['wordMatchCount'],
      if (args['options'] != null) 'options': args['options'],
      if (args['wordOptions'] != null) 'wordOptions': args['wordOptions'],
    };
    final request = PluginSearchRequest.fromArgs(miniArgs)
      ..validateAgainstQuery();
    return PluginOpenSearchTabSettings(
      searchMode: request.searchMode,
      distance: request.distance,
      proximityScope: request.proximityScope,
      wordMatchMode: request.wordMatchMode,
      wordMatchCount: request.wordMatchCount,
      searchOptions: request.effectiveSearchOptions,
    );
  }
}

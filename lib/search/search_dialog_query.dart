import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/plugins/services/plugin_search_field_session_service.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/saved_alternatives_store.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/search/utils/category_query_parser.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/search/utils/user_regex_query.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

/// ה-`request` של `search.requested` — אותו חוזה בשליחת הדיאלוג עם שורת
/// תוסף מסומנת ובכפתור `resultsAction` שבטאב החיפוש.
Map<String, dynamic> pluginSearchRequest({
  required String query,
  required String negativeQuery,
  required SearchMode mode,
  required int distance,
  required SearchScope proximityScope,
  required List<String> facets,
  required SearchConfiguration configuration,
  required SearchModeScopedParameters normalizedParameters,
  required SearchModeScopedParameters normalizedNegativeParameters,
}) => {
  'query': query,
  'mode': mode.name,
  'order': configuration.sortBy.name,
  'limit': configuration.numResults,
  'distance': distance,
  'facets': facets,
  if (normalizedParameters.searchOptions.isNotEmpty)
    'wordOptions': normalizedParameters.searchOptions,
  if (configuration.appliesAnyOrder(
    customSpacing: normalizedParameters.customSpacing,
    query: query,
  ))
    'anyOrder': true,
  if (mode == SearchMode.advanced) ...{
    if (negativeQuery.isNotEmpty) 'negativeQuery': negativeQuery,
    'proximityScope': proximityScope.name,
    'wordMatchMode': configuration.wordMatchMode.name,
    if (configuration.wordMatchMode == WordMatchMode.atLeast)
      'wordMatchCount': configuration.wordMatchCount,
    'grouping': configuration.resultGrouping.name,
    if (normalizedParameters.alternativeWords.isNotEmpty)
      'alternativeWords': _stringKeyed(normalizedParameters.alternativeWords),
    if (normalizedParameters.customSpacing.isNotEmpty)
      'customSpacing': normalizedParameters.customSpacing,
    if (normalizedNegativeParameters.searchOptions.isNotEmpty)
      'negativeWordOptions': normalizedNegativeParameters.searchOptions,
    if (normalizedNegativeParameters.alternativeWords.isNotEmpty)
      'negativeAlternativeWords': _stringKeyed(
        normalizedNegativeParameters.alternativeWords,
      ),
    if (normalizedNegativeParameters.customSpacing.isNotEmpty)
      'negativeCustomSpacing': normalizedNegativeParameters.customSpacing,
  },
};

Map<String, List<String>> _stringKeyed(Map<int, List<String>> values) => {
  for (final entry in values.entries) entry.key.toString(): entry.value,
};

/// מה שדיאלוג החיפוש שולח: השאילתות והפרמטרים של [tab] אחרי נרמול, וה-facets
/// של בחירת ההיקף. הספרייה וההיקף נמסרים מבחוץ, בלי BuildContext.
class SearchDialogQuery {
  const SearchDialogQuery(this.tab, {required this.supportsVocalizedSearch});

  final SearchingTab tab;

  /// ראו `_supportsVocalizedSearch` בדיאלוג: רק במסלולים שמריצים חיפוש אינדקס.
  final bool supportsVocalizedSearch;

  static const String _lastTypingKey = 'key-last-search-typing';

  /// ההקלדה האחרונה בשדה החיפוש, לפתיחה הבאה של הדיאלוג.
  static String loadLastTyping() =>
      Settings.getValue<String>(_lastTypingKey) ?? '';

  static Future<void> saveLastTyping(String text) =>
      Settings.setValue<String>(_lastTypingKey, text);

  /// השאילתות אחרי פענוח תחביר הקטגוריה ונרמול הניקוד והתווים, כמו שהן
  /// נשלחות לחיפוש וללקוח התוסף.
  ({String query, String negativeQuery, ParsedCategoryQuery category})
  normalizedQueries(Library? library) {
    final rawQuery = tab.queryController.text.trim();
    // תחביר קטגוריה: `מונח@קטגוריה` מצמצם את החיפוש לקטגוריה לפי שם.
    // `@` בתוך `/…/` הוא חלק מהביטוי, לא תחביר צמצום.
    final category = UserRegexQuery.isValid(rawQuery)
        ? ParsedCategoryQuery(query: rawQuery)
        : parseCategoryQuery(rawQuery, library);
    var query = category.query;
    var negativeQuery = tab.negativeQueryController.text.trim();

    final vocalizedSearch =
        supportsVocalizedSearch && tab.requestsVocalizedSearch;
    final isUserRegex = UserRegexQuery.isValid(query);
    if (!isUserRegex && !vocalizedSearch && utils.hasNikud(query)) {
      query = utils.removeVolwels(query);
    }
    if (!vocalizedSearch && utils.hasNikud(negativeQuery)) {
      negativeQuery = utils.removeVolwels(negativeQuery);
    }
    return (
      query: isUserRegex ? query : SearchQueryBuilder.sanitizeQuery(query),
      negativeQuery: SearchQueryBuilder.sanitizeQuery(negativeQuery),
      category: category,
    );
  }

  /// הפרמטרים של השאילתות אחרי נרמול למצב הנוכחי, וחלופות המילים שבתוקף.
  ({
    SearchModeScopedParameters positive,
    SearchModeScopedParameters negative,
    Map<int, List<String>> alternatives,
  })
  normalizedParameters({
    required String query,
    required String negativeQuery,
  }) {
    final mode = tab.searchBloc.state.configuration.searchMode;
    final effectiveOptions = SearchQueryBuilder.effectiveSearchOptions(
      query: query,
      useGlobalOptions: tab.useGlobalSearchOptions.value,
      globalOptions: tab.globalSearchOptions,
      perWordOptions: tab.searchOptions,
    );
    // כשמתג "חלופות שמורות" דלוק — הרחבת החיפוש בחלופות הגלובליות השמורות
    final alternatives = tab.useSavedAlternatives
        ? SavedAlternativesStore.mergeIntoQuery(
            query,
            tab.alternativeWords,
          )
        : tab.alternativeWords;
    final effectiveNegativeOptions = SearchQueryBuilder.effectiveSearchOptions(
      query: negativeQuery,
      useGlobalOptions: tab.useGlobalNegativeSearchOptions.value,
      globalOptions: tab.negativeGlobalSearchOptions,
      perWordOptions: tab.negativeSearchOptions,
    );
    return (
      positive: SearchQueryBuilder.normalizeParametersForMode(
        mode,
        customSpacing: tab.spacingValues,
        alternativeWords: alternatives,
        searchOptions: effectiveOptions,
      ),
      negative: SearchQueryBuilder.normalizeParametersForMode(
        mode,
        customSpacing: tab.negativeSpacingValues,
        alternativeWords: tab.negativeAlternativeWords,
        searchOptions: effectiveNegativeOptions,
      ),
      alternatives: alternatives,
    );
  }

  /// ה-facets שנבחרו לחיפוש. תחביר `@קטגוריה`/`@ספר` גובר על הבחירה הידנית.
  static List<String> facetsToSearch(
    ParsedCategoryQuery parsedCategory,
    Set<String> scopeSelection,
  ) {
    final selectedCategories = FacetHelper.categoryFacetsOf(scopeSelection);
    final categoriesToSearch = parsedCategory.categoryFound
        ? parsedCategory.facets!
        : selectedCategories.isEmpty
        ? ['/']
        : selectedCategories;
    // ממדי הסינון שנבחרו בדיאלוג (תקופה/מחבר/ספרי יסוד) מצטרפים ב-AND —
    // גם כשהקטגוריה נקבעה בתחביר `@`.
    return [
      ...categoriesToSearch,
      ...(FacetHelper.dimensionFacetsOf(scopeSelection).toList()..sort()),
    ];
  }

  /// מצב הדיאלוג ברגע הלחיצה על כפתור תוסף בשדה החיפוש: אותה שאילתה ואותם
  /// facets כמו בשליחה, כולל צמצום `@קטגוריה`.
  Map<String, dynamic> pluginInvocationContext({
    required Library? library,
    required Set<String> scopeSelection,
    required Map<String, bool> pluginSelections,
  }) {
    final queries = normalizedQueries(library);
    final query = queries.query;
    final negativeQuery = queries.negativeQuery;
    final state = tab.searchBloc.state;
    final configuration = state.configuration;
    final parameters = normalizedParameters(
      query: query,
      negativeQuery: negativeQuery,
    );
    return {
      PluginSearchFieldContext.requestKey: pluginSearchRequest(
        query: query,
        negativeQuery: negativeQuery,
        mode: configuration.searchMode,
        distance: state.distance,
        proximityScope: configuration.proximityScope,
        facets: facetsToSearch(queries.category, scopeSelection),
        configuration: configuration,
        normalizedParameters: parameters.positive,
        normalizedNegativeParameters: parameters.negative,
      ),
      PluginSearchFieldContext.pluginSelectionsKey: pluginSelections,
    };
  }

  /// מעתיק ל-[target] את השאילתות ואת הגדרות המילים שנערכו בדיאלוג.
  /// חלופות שמורות שמוזגו ([effectiveAlternatives]) הופכות לחלק מהטאב —
  /// נשמרות ומשוחזרות איתו.
  void copyParametersTo(
    SearchingTab target, {
    required String query,
    required String negativeQuery,
    required Map<int, List<String>> effectiveAlternatives,
  }) {
    target.queryController.text = query;
    target.negativeQueryController.text = negativeQuery;
    target.searchOptions
      ..clear()
      ..addAll(
        tab.searchOptions.map(
          (key, value) => MapEntry(key, Map<String, bool>.from(value)),
        ),
      );
    target.globalSearchOptions
      ..clear()
      ..addAll(tab.globalSearchOptions);
    target.negativeSearchOptions
      ..clear()
      ..addAll(
        tab.negativeSearchOptions.map(
          (key, value) => MapEntry(key, Map<String, bool>.from(value)),
        ),
      );
    target.negativeGlobalSearchOptions
      ..clear()
      ..addAll(tab.negativeGlobalSearchOptions);
    target.useGlobalSearchOptions.value = tab.useGlobalSearchOptions.value;
    target.useGlobalNegativeSearchOptions.value =
        tab.useGlobalNegativeSearchOptions.value;
    target.alternativeWords
      ..clear()
      ..addAll(
        effectiveAlternatives.map(
          (key, value) => MapEntry(key, List<String>.from(value)),
        ),
      );
    target.spacingValues
      ..clear()
      ..addAll(tab.spacingValues);
    target.negativeAlternativeWords
      ..clear()
      ..addAll(
        tab.negativeAlternativeWords.map(
          (key, value) => MapEntry(key, List<String>.from(value)),
        ),
      );
    target.negativeSpacingValues
      ..clear()
      ..addAll(tab.negativeSpacingValues);
  }
}

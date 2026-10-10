import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_defaults.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/search/utils/smart_lexical_in_book_search.dart';
import 'package:otzaria/search/utils/in_book_search_routing.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

/// The settings of an in-book search besides the query, shared by the text
/// and PDF search panes: the mode, the distance, the match policy and the
/// per-word options.
@immutable
class InBookSearchSettings {
  const InBookSearchSettings({
    this.searchOptions = const {},
    this.alternativeWords = const {},
    this.spacingValues = const {},
    this.searchMode = SearchMode.exact,
    this.distance = 0,
    this.matchPolicy = SearchMatchPolicy.standard,
    this.optionsForEveryWord,
  });

  /// The settings a new in-book search starts with: the defaults saved with
  /// "קבע כברירת מחדל", whose word options apply to every word typed.
  factory InBookSearchSettings.savedDefaults() {
    if (!Settings.isInitialized) return const InBookSearchSettings();
    final mode = SearchDefaults.loadModeDefault();
    return InBookSearchSettings(
      searchMode: mode,
      distance: mode == SearchMode.fuzzy
          ? kMaxFuzzyDistance
          : SearchDefaults.loadDistanceDefault(),
      optionsForEveryWord: SearchQueryBuilder.normalizeGlobalOptionsForMode(
        mode,
        mode == SearchMode.exact
            ? SearchDefaults.loadExactDefaults()
            : SearchDefaults.loadDefaults(),
      ),
    );
  }

  /// The settings submitted in the advanced search dialog, with the per-word
  /// options normalized for the chosen mode.
  factory InBookSearchSettings.fromDialogResult(SearchDialogResult result) {
    final normalized = SearchQueryBuilder.normalizeParametersForMode(
      result.searchMode,
      customSpacing: result.spacingValues,
      alternativeWords: result.alternativeWords,
      searchOptions: result.searchOptions,
    );
    return InBookSearchSettings(
      searchOptions: normalized.searchOptions,
      alternativeWords: normalized.alternativeWords,
      spacingValues: normalized.customSpacing,
      searchMode: result.searchMode,
      distance: result.distance,
      matchPolicy: result.matchPolicy,
    );
  }

  final Map<String, Map<String, bool>> searchOptions;
  final Map<int, List<String>> alternativeWords;
  final Map<String, String> spacingValues;
  final SearchMode searchMode;
  final int distance;
  final SearchMatchPolicy matchPolicy;

  /// Word options that apply to every word of whatever query is typed, or
  /// null when [searchOptions] were chosen for a specific query.
  final Map<String, bool>? optionsForEveryWord;

  /// These settings with [optionsForEveryWord] spread over the words of
  /// [query].
  InBookSearchSettings forQuery(String query) {
    final options = optionsForEveryWord;
    if (options == null) return this;
    return InBookSearchSettings(
      searchOptions: SearchQueryBuilder.expandGlobalOptionsToWords(
        query,
        options,
      ),
      searchMode: searchMode,
      distance: distance,
      matchPolicy: matchPolicy,
      optionsForEveryWord: options,
    );
  }

  /// Whether these settings need the search engine rather than the local
  /// literal scan.
  bool get requiresEngine => !InBookSearchRouting.canRunAsSimpleSearch(
    searchMode: searchMode,
    distance: distance,
    searchOptions: searchOptions,
    alternativeWords: alternativeWords,
    spacingValues: spacingValues,
    matchPolicy: matchPolicy,
  );

  /// Whether the search runs as the local literal scan.
  bool get isSimpleSearch => !requiresEngine && searchMode == SearchMode.exact;

  /// The per-word options that apply to [searchMode].
  SearchModeScopedParameters get activeParameters =>
      SearchQueryBuilder.normalizeParametersForMode(
        searchMode,
        customSpacing: spacingValues,
        alternativeWords: alternativeWords,
        searchOptions: searchOptions,
      );
}

/// The query an in-book search runs for [raw]: trimmed and without nikud, or
/// null when there is nothing to search for.
String? searchableInBookQuery(String raw) {
  var query = raw.trim();
  if (utils.hasNikud(query)) {
    query = utils.removeVolwels(query);
  }
  return query.isEmpty ? null : query;
}

/// Searches the book whose facet is [bookPath] for [query] through the
/// search engine, with [settings], in the book's order.
Future<List<SearchResult>> searchBookWithEngine(
  SearchRepository repository, {
  required String query,
  required String bookPath,
  required int limit,
  required InBookSearchSettings settings,
}) async {
  if (settings.searchMode == SearchMode.fuzzy &&
      settings.matchPolicy.querySemantics == SearchQuerySemantics.smart) {
    final phrases = smartSearchQuotedPhrases(query);
    if (phrases.isNotEmpty) {
      return searchSmartLexicalInBook(
        repository,
        query: query,
        bookPath: bookPath,
        limit: limit,
        distance: settings.distance,
        phrases: phrases,
      );
    }
  }
  final parameters = settings.activeParameters;
  final policy = settings.matchPolicy;
  return repository.searchTexts(
    SearchEngineRequest(
      query: query,
      facets: [bookPath],
      limit: limit,
      searchOptions: parameters.searchOptions,
      alternativeWords: parameters.alternativeWords,
      customSpacing: parameters.customSpacing,
      distance: settings.distance,
      negativeDistance: settings.distance,
      searchMode: settings.searchMode,
      scope: policy.proximityScope,
      negativeScope: policy.proximityScope,
      wordMatchMode: policy.wordMatchMode,
      wordMatchCount: policy.wordMatchCount,
      order: ResultsOrder.catalogue,
    ),
  );
}

/// How many results an in-book engine search asks for. The engine filters by
/// a facet prefix, so it may also return results of other books under the
/// same facet, which the panes drop; asking for more keeps enough of this
/// book's results after that.
const int kInBookEngineFetchLimit = 5000;

/// How many results an in-book search pane shows.
const int kInBookResultsShown = 1000;

/// The first [kInBookResultsShown] of [results], and whether any were left
/// out.
({List<T> shown, bool truncated}) limitInBookResults<T>(List<T> results) => (
  shown: results.take(kInBookResultsShown).toList(growable: false),
  truncated: results.length > kInBookResultsShown,
);

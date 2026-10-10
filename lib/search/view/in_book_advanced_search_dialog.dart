import 'package:flutter/material.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';

/// יוצר טאב זמני לעריכת הגדרות החיפוש בספר.
/// האתחול הישיר מונע חיפוש לפני שההגדרות הוחלו.
SearchingTab createInBookSearchDialogTab({
  required String query,
  required SearchMode searchMode,
  required int distance,
  required SearchMatchPolicy matchPolicy,
  required Map<String, Map<String, bool>> searchOptions,
  required Map<int, List<String>> alternativeWords,
  required Map<String, String> spacingValues,
  Map<String, bool>? optionsForEveryWord,
}) {
  final tab = SearchingTab(
    'חיפוש',
    query,
    initialConfiguration: SearchConfiguration.forInBookSearch(
      searchMode: searchMode,
      distance: distance,
      matchPolicy: matchPolicy,
    ),
  );
  tab.copyWordSettingsFrom(
    searchOptions: searchOptions,
    alternativeWords: alternativeWords,
    spacingValues: spacingValues,
  );
  final globalOptions = searchMode == SearchMode.exact
      ? SearchQueryBuilder.globalOptionsFromPerWord(searchOptions)
      : null;
  // בחיפוש מדויק הפקדים גלובליים; מפה חלקית או מעורבת נשארת פר-מילה.
  final globalWordKeys = globalOptions == null
      ? const Iterable<String>.empty()
      : SearchQueryBuilder.expandGlobalOptionsToWords(
          query,
          globalOptions,
        ).keys;
  tab.useGlobalSearchOptions.value =
      optionsForEveryWord != null ||
      (globalOptions != null &&
          globalWordKeys.length == searchOptions.length &&
          globalWordKeys.every(searchOptions.containsKey));
  if (tab.useGlobalSearchOptions.value) {
    tab.globalSearchOptions.addAll(optionsForEveryWord ?? globalOptions!);
  }
  return tab;
}

/// פותח חיפוש מתקדם בתוך ספר ומחזיר את ההגדרות שאושרו, או null בביטול.
Future<SearchDialogResult?> showInBookAdvancedSearchDialog(
  BuildContext context, {
  required String? bookTitle,
  required String query,
  required SearchMode searchMode,
  required int distance,
  required SearchMatchPolicy matchPolicy,
  required Map<String, Map<String, bool>> searchOptions,
  required Map<int, List<String>> alternativeWords,
  required Map<String, String> spacingValues,
  Map<String, bool>? optionsForEveryWord,
}) async {
  final tab = createInBookSearchDialogTab(
    query: query,
    searchMode: searchMode,
    distance: distance,
    matchPolicy: matchPolicy,
    searchOptions: searchOptions,
    alternativeWords: alternativeWords,
    spacingValues: spacingValues,
    optionsForEveryWord: optionsForEveryWord,
  );

  final result = await showDialog<SearchDialogResult>(
    context: context,
    builder: (_) => SearchDialog(
      existingTab: tab,
      bookTitle: bookTitle,
      returnResultOnSubmit: true,
    ),
  );

  // Disposing right away would free the tab's FocusNode while the dialog's
  // fade-out still rebuilds it.
  Future.delayed(const Duration(milliseconds: 500), tab.dispose);

  return result;
}

import 'package:flutter/material.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';

/// Builds the temporary tab that the advanced search dialog edits for an
/// in-book search, seeded with the current query and settings.
///
/// The configuration is passed to the constructor rather than as bloc events,
/// so the dialog cannot start a search before the settings are applied.
SearchingTab createInBookSearchDialogTab({
  required String query,
  required SearchMode searchMode,
  required int distance,
  required SearchMatchPolicy matchPolicy,
  required Map<String, Map<String, bool>> searchOptions,
  required Map<int, List<String>> alternativeWords,
  required Map<String, String> spacingValues,
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
  // The restored options are a per-word map; in global mode the dialog reads
  // the empty global map and the restored choices are lost.
  tab.useGlobalSearchOptions.value = false;
  return tab;
}

/// Opens the advanced search dialog for an in-book search and returns the
/// submitted settings, or null when the dialog was closed.
Future<SearchDialogResult?> showInBookAdvancedSearchDialog(
  BuildContext context, {
  required String bookTitle,
  required String query,
  required SearchMode searchMode,
  required int distance,
  required SearchMatchPolicy matchPolicy,
  required Map<String, Map<String, bool>> searchOptions,
  required Map<int, List<String>> alternativeWords,
  required Map<String, String> spacingValues,
}) async {
  final tab = createInBookSearchDialogTab(
    query: query,
    searchMode: searchMode,
    distance: distance,
    matchPolicy: matchPolicy,
    searchOptions: searchOptions,
    alternativeWords: alternativeWords,
    spacingValues: spacingValues,
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
